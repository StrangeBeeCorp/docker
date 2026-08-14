#!/usr/bin/env bash
# Lint: validate every environment's docker-compose.yml and shellcheck all scripts.
# Run locally (`bash ci/lint.sh`) or from .github/workflows/lint.yml.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

ENVS=(testing prod1-thehive prod2-thehive prod1-cortex prod2-cortex)

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
