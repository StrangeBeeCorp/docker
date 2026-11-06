#!/usr/bin/env bash

## Cortex analyzer test, run from the testing directory, after init.sh.
## Runs TestAnalyzer (no external call, no API key), enabled here when missing, and checks its job
## succeeds: Cortex (run as the host user) starts the analyzer container through the Docker socket
## and writes into ./cortex/cortex-jobs.

set -uo pipefail

BASE_URL="${BASE_URL:-https://127.0.0.1/cortex}"
CURL_OPTS="${CURL_OPTS:--sk --connect-timeout 5 --max-time 330}"
ADMIN_USER="${ADMIN_USER:-admin}"
ORG_ADMIN="${ORG_ADMIN:-demo_admin}"
ANALYZER="${ANALYZER:-TestAnalyzer}"
DATA_TYPE="${DATA_TYPE:-domain}"
DATA="${DATA:-example.com}"

info()    { echo "[INFO] $1" >&2; }
success() { echo "[SUCCESS] $1" >&2; }
error()   { echo "[ERROR] $1" >&2; }

COOKIES=$(mktemp)
trap 'rm -f "${COOKIES}"' EXIT

# shellcheck disable=SC2086
curl_api() { curl $CURL_OPTS "$@"; }

check_prerequisites() {
  for cmd in curl jq; do
    command -v "$cmd" >/dev/null 2>&1 || { error "$cmd not found"; exit 1; }
  done
  ADMIN_PASSWORD=$(grep -E '^cortex_admin_password=' ./.env 2>/dev/null | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//')
  ADMIN_PASSWORD="${ADMIN_PASSWORD:-secret}"
}

## API key of the orgadmin created by init.sh, read with a superadmin session (passed on stdin, never on a command line)
get_key() {
  printf '{"user":"%s","password":"%s"}' "${ADMIN_USER}" "${ADMIN_PASSWORD}" \
    | curl_api -o /dev/null -c "${COOKIES}" -H 'Content-Type: application/json' --data-binary @- \
      "${BASE_URL}/api/login" 2>/dev/null
  KEY=$(curl_api -b "${COOKIES}" "${BASE_URL}/api/user/${ORG_ADMIN}/key" 2>/dev/null | tr -d '"[:space:]')
  [ ${#KEY} -ge 16 ] || { error "Cannot read the API key of '${ORG_ADMIN}'"; return 1; }
}

## curl with the API key in a header read from stdin
curl_key() { printf 'Authorization: Bearer %s\n' "${KEY}" | curl_api -H @- "$@"; }

## id of ${ANALYZER} in the organisation of ${ORG_ADMIN}, empty when not enabled
analyzer_id() {
  curl_key "${BASE_URL}/api/analyzer?range=all" 2>/dev/null \
    | jq -r --arg name "${ANALYZER}_" '[.[] | select(.name | startswith($name))][0].id // empty'
}

## Enables the latest version of ${ANALYZER} from the catalogue
enable_analyzer() {
  local definition code
  definition=$(curl_key "${BASE_URL}/api/analyzerdefinition?range=all" 2>/dev/null \
    | jq -r --arg name "${ANALYZER}" '[.[] | select(.name == $name)] | sort_by(.version | split(".") | map(tonumber? // 0)) | last | .id // empty')
  [ -n "${definition}" ] || { error "${ANALYZER} not found in the Cortex catalogue"; return 1; }
  code=$(curl_key -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    "${BASE_URL}/api/organization/analyzer/${definition}" \
    -d '{"name":"'"${definition}"'","configuration":{"throw_error":false,"auto_extract_artifacts":false,"check_tlp":false,"max_tlp":2,"check_pap":false,"max_pap":2},"jobCache":0,"jobTimeout":30}' 2>/dev/null)
  case "${code}" in
    200|201) success "${definition} enabled" ;;
    *) error "Cannot enable ${definition} (HTTP ${code:-000})"; return 1 ;;
  esac
}

run_analyzer() {
  info "Running ${ANALYZER} on ${DATA_TYPE} '${DATA}'..."
  local analyzer_id job_id status
  analyzer_id=$(analyzer_id)
  if [ -z "${analyzer_id}" ]; then
    enable_analyzer || return 1
    analyzer_id=$(analyzer_id)
  fi
  [ -n "${analyzer_id}" ] || { error "${ANALYZER} is not enabled in the organisation of '${ORG_ADMIN}'"; return 1; }

  job_id=$(curl_key -H 'Content-Type: application/json' "${BASE_URL}/api/analyzer/${analyzer_id}/run" \
    -d '{"dataType":"'"${DATA_TYPE}"'","data":"'"${DATA}"'","tlp":0,"pap":0}' 2>/dev/null | jq -r '.id // empty')
  [ -n "${job_id}" ] || { error "Cannot start the ${ANALYZER} job"; return 1; }

  ## The first run pulls the analyzer image
  status=$(curl_key "${BASE_URL}/api/job/${job_id}/waitreport?atMost=5minutes" 2>/dev/null | jq -r '.status // empty')
  if [ "${status}" = "Success" ]; then
    success "${ANALYZER} job ${job_id} succeeded"
  else
    error "${ANALYZER} job ${job_id} ended with status '${status:-unknown}': check docker compose logs cortex"
    return 1
  fi
}

main() {
  info "=== Cortex analyzer test ==="
  check_prerequisites
  if get_key && run_analyzer; then
    success "=== Cortex analyzer test PASSED ==="
    exit 0
  else
    error "=== Cortex analyzer test FAILED ==="
    exit 1
  fi
}

main
