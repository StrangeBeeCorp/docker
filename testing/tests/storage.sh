#!/usr/bin/env bash

set -uo pipefail

BASE_URL="${BASE_URL:-https://127.0.0.1/thehive}"
CURL_OPTS="${CURL_OPTS:--sk}"
ORG_USER="${ORG_USER:-thehive@thehive.local}"
ORG_PASSWORD="${ORG_PASSWORD:-thehive1234}"
ORG_NAME="${ORG_NAME:-demo}"
TEST_DIR="${TEST_DIR:-/tmp/thehive-storage-test}"

info()    { echo "[INFO] $1" >&2; }
success() { echo "[SUCCESS] $1" >&2; }
error()   { echo "[ERROR] $1" >&2; }

# shellcheck disable=SC2086
curl_api() { curl $CURL_OPTS -H "X-Organisation: ${ORG_NAME}" -u "${ORG_USER}:${ORG_PASSWORD}" "$@"; }

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }

cleanup() { [ -d "${TEST_DIR}" ] && rm -rf "${TEST_DIR}"; }
trap cleanup EXIT INT TERM

check_prerequisites() {
  for cmd in curl jq; do command -v "$cmd" >/dev/null 2>&1 || { error "$cmd not found"; exit 1; }; done
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || { error "need sha256sum or shasum"; exit 1; }
}

create_test_files() {
  mkdir -p "${TEST_DIR}"; cd "${TEST_DIR}" || exit 1
  printf 'TheHive object-storage verification.\n' > small.txt
  dd if=/dev/urandom of=medium.bin bs=1024 count=1024 2>/dev/null
  seq 1 50000 | sed 's/.*/Line &: the quick brown fox jumps over the lazy dog/' > large.txt
  SMALL_SHA=$(sha256 small.txt); MEDIUM_SHA=$(sha256 medium.bin); LARGE_SHA=$(sha256 large.txt)
  success "Test files created (small/medium 1MiB/large)"
}

setup_case_task() {
  CASE_ID=$(curl_api -X POST "${BASE_URL}/api/v1/case" -H 'Content-Type: application/json' \
    -d '{"title":"Storage test case","description":"object storage","severity":1,"tlp":0}' | jq -r '._id')
  [ -n "$CASE_ID" ] && [ "$CASE_ID" != "null" ] || { error "case create failed"; exit 1; }
  TASK_ID=$(curl_api -X POST "${BASE_URL}/api/v1/case/${CASE_ID}/task" -H 'Content-Type: application/json' \
    -d '{"title":"Storage task","description":"attachments","status":"InProgress"}' | jq -r '._id')
  [ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ] || { error "task create failed"; exit 1; }
  success "Case ${CASE_ID} / task ${TASK_ID} ready"
}

roundtrip_log() {
  local file=$1 expected=$2 resp log_id att_id
  resp=$(curl_api -X POST "${BASE_URL}/api/v1/task/${TASK_ID}/log" \
    -F '_json={"message":"attachment via log"};type=application/json' \
    -F "attachments=@${file}")
  log_id=$(echo "$resp" | jq -r '._id'); att_id=$(echo "$resp" | jq -r '.attachments[0]._id')
  [ -n "$att_id" ] && [ "$att_id" != "null" ] || { error "log upload of ${file} failed: $resp"; return 1; }
  curl_api -X GET "${BASE_URL}/api/v1/log/${log_id}/attachment/${att_id}/download" -o "dl-${file}"
  if [ "$(sha256 "dl-${file}")" = "$expected" ]; then success "✓ log ${file} SHA256 match"; return 0
  else error "✗ log ${file} SHA256 MISMATCH"; return 1; fi
}

roundtrip_observable() {
  local file=$1 expected=$2 resp obs_id att_id
  resp=$(curl_api -X POST "${BASE_URL}/api/v1/case/${CASE_ID}/observable" \
    -F '_json={"dataType":"file","message":"file observable"};type=application/json' \
    -F "attachment=@${file}")
  obs_id=$(echo "$resp" | jq -r '.[0]._id'); att_id=$(echo "$resp" | jq -r '.[0].attachment._id')
  [ -n "$att_id" ] && [ "$att_id" != "null" ] || { error "observable upload of ${file} failed: $resp"; return 1; }
  curl_api -X GET "${BASE_URL}/api/v1/observable/${obs_id}/attachment/${att_id}/download" -o "dlobs-${file}"
  if [ "$(sha256 "dlobs-${file}")" = "$expected" ]; then success "✓ observable ${file} SHA256 match"; return 0
  else error "✗ observable ${file} SHA256 MISMATCH"; return 1; fi
}

main() {
  info "=== TheHive testing-stack object-storage test ==="
  check_prerequisites
  create_test_files
  setup_case_task
  local failed=0
  roundtrip_log small.txt   "$SMALL_SHA"  || failed=$((failed+1))
  roundtrip_log medium.bin  "$MEDIUM_SHA" || failed=$((failed+1))
  roundtrip_log large.txt   "$LARGE_SHA"  || failed=$((failed+1))
  roundtrip_observable small.txt "$SMALL_SHA" || failed=$((failed+1))
  echo "" >&2
  if [ "$failed" -eq 0 ]; then success "=== Object-storage test PASSED ==="; exit 0
  else error "=== Object-storage test FAILED (${failed}) ==="; exit 1; fi
}

main
