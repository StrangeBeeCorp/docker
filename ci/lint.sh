#!/usr/bin/env bash
# Lint: validate every environment's docker-compose.yml and shellcheck all scripts.
# Run locally (`bash ci/lint.sh`) or from .github/workflows/lint.yml.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

ENVS=(testing prod1-thehive prod2-thehive prod1-cortex prod2-cortex prod1-thehive-flow prod2-thehive-flow)

ENVVARS="$(mktemp)"
trap 'rm -f "$ENVVARS"' EXIT
cat versions.env > "$ENVVARS"
{
  echo
  echo "UID=1000"
  echo "GID=1000"
  echo "elasticsearch_password=lint"
  echo "nginx_server_name=localhost"
  echo "nginx_ssl_trusted_certificate="
  echo "cortex_docker_job_directory=/tmp/cortex-jobs"
  echo "docker_gid=0"
  echo "postgres_password=lint"
  echo "flow_db_password=lint"
  echo "temporal_db_password=lint"
  echo "s3_access_key_id=thehive-flow"
  echo "s3_secret_access_key=lint"
  echo "jwt_signing_key=lint"
  echo "thehive_api_key="
  echo "flow_thehive_url=http://thehive:9000"
  echo "flow_public_url=https://localhost"
  echo "nginx_thehive_addresses="
} >> "$ENVVARS"

status=0

echo "== docker compose config =="
for e in "${ENVS[@]}"; do
  if docker compose -f "$e/docker-compose.yml" --env-file "$ENVVARS" config -q; then
    echo "  ok    $e"
  else
    echo "  FAIL  $e"
    status=1
  fi
done

echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2046
  if shellcheck --severity=error $(git ls-files '*.sh'); then
    echo "  ok    shellcheck"
  else
    echo "  FAIL  shellcheck"
    status=1
  fi
else
  echo "  WARN  shellcheck not installed, skipping"
fi

[ "$status" -eq 0 ] && echo "== lint OK ==" || echo "== lint FAILED =="
exit "$status"
