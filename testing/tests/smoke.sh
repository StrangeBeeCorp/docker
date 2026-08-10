#!/usr/bin/env bash

set -uo pipefail

BASE_URL="${BASE_URL:-https://127.0.0.1/thehive}"
CURL_OPTS="${CURL_OPTS:--sk}"
ADMIN_USER="${ADMIN_USER:-admin@thehive.local}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-secret}"
ORG_USER="${ORG_USER:-thehive@thehive.local}"
ORG_PASSWORD="${ORG_PASSWORD:-thehive1234}"
ORG_NAME="${ORG_NAME:-demo}"

info()    { echo "[INFO] $1" >&2; }
success() { echo "[SUCCESS] $1" >&2; }
warning() { echo "[WARN] $1" >&2; }
error()   { echo "[ERROR] $1" >&2; }

# shellcheck disable=SC2086
curl_api() { curl $CURL_OPTS "$@"; }

check_prerequisites() {
  for cmd in curl jq; do
    command -v "$cmd" >/dev/null 2>&1 || { error "$cmd not found"; exit 1; }
  done
}

wait_ready() {
  info "Waiting for TheHive API at ${BASE_URL} ..."
  local max=60 count=0 code
  while [ "$count" -lt "$max" ]; do
    code=$(curl_api -o /dev/null -w '%{http_code}' \
      -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
      "${BASE_URL}/api/v1/user/current" 2>/dev/null || echo 000)
    [ "$code" = "200" ] && { success "TheHive is ready"; return 0; }
    count=$((count + 1)); sleep 5
  done
  error "TheHive did not become ready in time"; exit 1
}

api() {
  local expected=$1 method=$2 endpoint=$3 auth=$4 data=$5; shift 5
  local hdr=() h
  for h in "$@"; do hdr+=(-H "$h"); done
  local body code
  body=$(curl_api -o /tmp/smoke_resp.json -w '%{http_code}' \
    -X "$method" "${BASE_URL}${endpoint}" \
    -H 'Content-Type: application/json' ${hdr[@]+"${hdr[@]}"} \
    -u "$auth" -d "$data" 2>/dev/null || echo 000)
  code=$body
  if [ "$code" = "$expected" ]; then
    cat /tmp/smoke_resp.json 2>/dev/null
    return 0
  fi
  error "${method} ${endpoint} -> HTTP ${code} (expected ${expected}): $(cat /tmp/smoke_resp.json 2>/dev/null)"
  return 1
}

ALERT_ID=""; CASE_ID=""

create_org() {
  info "Creating organisation '${ORG_NAME}'..."
  if api 201 POST "/api/organisation" "${ADMIN_USER}:${ADMIN_PASSWORD}" \
    '{"name":"'"${ORG_NAME}"'","description":"Smoke test org"}' >/dev/null; then
    success "Organisation created"
  else
    warning "Organisation may already exist, continuing"
  fi
}

create_orgadmin() {
  info "Creating org-admin '${ORG_USER}'..."
  local uid
  uid=$(api 201 POST "/api/v1/user" "${ADMIN_USER}:${ADMIN_PASSWORD}" \
    '{"login":"'"${ORG_USER}"'","name":"thehive","organisation":"'"${ORG_NAME}"'","profile":"org-admin","password":"'"${ORG_PASSWORD}"'"}' \
    | jq -r '._id' 2>/dev/null || echo "")
  if [ -n "$uid" ] && [ "$uid" != "null" ]; then
    success "User created (${uid})"
  else
    warning "User may already exist, continuing"
  fi
}

create_customfields() {
  info "Creating custom fields..."
  local n
  for n in \
    '{"name":"businessimpact","reference":"businessimpact","description":"Impact","type":"string","options":["Critical","High","Medium","Low"]}' \
    '{"name":"businessunit","reference":"businessunit","description":"Unit","type":"string","options":["HR","Security","Sales"]}' \
    '{"name":"sla","reference":"sla","description":"SLA hours","type":"integer","options":[4,8,24]}' \
    '{"name":"contact","reference":"contact","description":"Contact email","type":"string","options":[]}' \
    '{"name":"hits","reference":"hits","description":"Hunting hits","type":"integer","options":[]}'; do
    api 201 POST "/api/customField" "${ADMIN_USER}:${ADMIN_PASSWORD}" "$n" >/dev/null \
      || warning "custom field may already exist"
  done
  success "Custom fields ensured"
}

create_case_template() {
  info "Creating case template 'MISPEvent'..."
  api 201 POST "/api/v1/caseTemplate" "${ORG_USER}:${ORG_PASSWORD}" \
    '{"name":"MISPEvent","severity":2,"tlp":2,"pap":2,"tags":["hunting"],"description":"MISP","displayName":"MISP","tasks":[{"order":0,"title":"Search mail gateway logs","group":"default"}]}' \
    >/dev/null && success "Case template created" || warning "Case template may already exist"
}

create_alert() {
  info "Creating alert..."
  ALERT_ID=$(api 201 POST "/api/v1/alert" "${ORG_USER}:${ORG_PASSWORD}" \
    '{"type":"misp","source":"misp server","sourceRef":"1311","title":"Smoke test alert","description":"Imported from MISP","severity":1,"tlp":0,"tags":["tlp:white"]}' \
    "X-Organisation: ${ORG_NAME}" | jq -r '._id')
  if [ -n "$ALERT_ID" ] && [ "$ALERT_ID" != "null" ]; then
    success "Alert created (${ALERT_ID})"
    api 201 POST "/api/v1/alert/${ALERT_ID}/observable" "${ORG_USER}:${ORG_PASSWORD}" \
      '{"dataType":"ip","data":["5.254.43.18"],"tlp":0,"message":"ioc"}' \
      "X-Organisation: ${ORG_NAME}" >/dev/null
    api 201 POST "/api/v1/alert/${ALERT_ID}/comment" "${ORG_USER}:${ORG_PASSWORD}" \
      '{"message":"Initial triage completed."}' "X-Organisation: ${ORG_NAME}" >/dev/null
    success "Alert observable + comment added"
  else
    error "Failed to create alert"; return 1
  fi
}

create_case() {
  info "Creating case..."
  CASE_ID=$(api 201 POST "/api/v1/case" "${ORG_USER}:${ORG_PASSWORD}" \
    '{"title":"Smoke test case","description":"Analyzers and responders","severity":1,"tlp":0}' \
    "X-Organisation: ${ORG_NAME}" | jq -r '._id')
  if [ -n "$CASE_ID" ] && [ "$CASE_ID" != "null" ]; then
    success "Case created (${CASE_ID})"
    api 201 POST "/api/v1/case/${CASE_ID}/observable" "${ORG_USER}:${ORG_PASSWORD}" \
      '{"dataType":"ip","data":["8.8.8.8"],"tlp":0,"message":"obs"}' \
      "X-Organisation: ${ORG_NAME}" >/dev/null
    local i
    for i in 1 2 3; do
      api 201 POST "/api/v1/case/${CASE_ID}/task" "${ORG_USER}:${ORG_PASSWORD}" \
        '{"title":"Task '"$i"'","description":"work","status":"Waiting"}' \
        "X-Organisation: ${ORG_NAME}" >/dev/null
    done
    api 204 PATCH "/api/v1/case/${CASE_ID}" "${ORG_USER}:${ORG_PASSWORD}" \
      '{"status":"InProgress"}' "X-Organisation: ${ORG_NAME}" >/dev/null
    success "Case observable + 3 tasks added, status updated"
  else
    error "Failed to create case"; return 1
  fi
}

verify() {
  info "Verifying created resources..."
  local failed=0

  curl_api -u "${ADMIN_USER}:${ADMIN_PASSWORD}" "${BASE_URL}/api/organisation/${ORG_NAME}" \
    | jq -e '.name == "'"${ORG_NAME}"'"' >/dev/null 2>&1 \
    && success "✓ org '${ORG_NAME}'" || { error "✗ org missing"; failed=$((failed+1)); }

  curl_api -u "${ADMIN_USER}:${ADMIN_PASSWORD}" "${BASE_URL}/api/v1/user/${ORG_USER}" \
    | jq -e '.login == "'"${ORG_USER}"'"' >/dev/null 2>&1 \
    && success "✓ user '${ORG_USER}'" || { error "✗ user missing"; failed=$((failed+1)); }

  local cf
  cf=$(curl_api -u "${ADMIN_USER}:${ADMIN_PASSWORD}" "${BASE_URL}/api/customField" | jq '. | length' 2>/dev/null)
  [ -n "$cf" ] && [ "$cf" -ge 5 ] 2>/dev/null \
    && success "✓ custom fields (${cf})" || { error "✗ custom fields: ${cf} (<5)"; failed=$((failed+1)); }

  curl_api -u "${ORG_USER}:${ORG_PASSWORD}" -H "X-Organisation: ${ORG_NAME}" \
    "${BASE_URL}/api/v1/caseTemplate/MISPEvent" | jq -e '.name == "MISPEvent"' >/dev/null 2>&1 \
    && success "✓ case template" || { error "✗ case template missing"; failed=$((failed+1)); }

  if [ -n "$ALERT_ID" ] && [ "$ALERT_ID" != "null" ] \
     && curl_api -u "${ORG_USER}:${ORG_PASSWORD}" -H "X-Organisation: ${ORG_NAME}" \
        "${BASE_URL}/api/v1/alert/${ALERT_ID}" | jq -e '._id' >/dev/null 2>&1; then
    success "✓ alert '${ALERT_ID}'"
  else
    error "✗ alert missing (id='${ALERT_ID:-}')"; failed=$((failed+1))
  fi

  if [ -n "$CASE_ID" ] && [ "$CASE_ID" != "null" ] \
     && curl_api -u "${ORG_USER}:${ORG_PASSWORD}" -H "X-Organisation: ${ORG_NAME}" \
        "${BASE_URL}/api/v1/case/${CASE_ID}" | jq -e '._id' >/dev/null 2>&1; then
    local tasks
    tasks=$(curl_api -u "${ORG_USER}:${ORG_PASSWORD}" -H "X-Organisation: ${ORG_NAME}" \
      -H "Content-Type: application/json" "${BASE_URL}/api/v1/query?name=tasks" \
      -d '{"query":[{"_name":"getCase","idOrName":"'"${CASE_ID}"'"},{"_name":"tasks"}]}' \
      | jq '. | length' 2>/dev/null)
    [ -n "$tasks" ] && [ "$tasks" -ge 3 ] 2>/dev/null \
      && success "✓ case '${CASE_ID}' has ${tasks} tasks" || { error "✗ case tasks: ${tasks:-0} (<3)"; failed=$((failed+1)); }
  else
    error "✗ case missing (id='${CASE_ID:-}')"; failed=$((failed+1))
  fi

  return $failed
}

main() {
  info "=== TheHive testing-stack smoke test ==="
  check_prerequisites
  wait_ready
  create_org
  create_orgadmin
  create_customfields
  create_case_template
  create_alert
  create_case
  echo "" >&2
  if verify; then
    success "=== Smoke test PASSED ==="
    exit 0
  else
    error "=== Smoke test FAILED ==="
    exit 1
  fi
}

main
