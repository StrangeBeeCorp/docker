#!/bin/bash

## Sourced by init.sh (needs output.sh): provisions the TheHive API key used by TheHive Flow.
## TheHive Flow documentation, step 9: a service account whose profile holds the "Manage analysis"
## and "Manage actions" permissions, member of the organisation(s) running Analyzer/Responder nodes.

THEHIVE_LOCAL_URL="${THEHIVE_LOCAL_URL:-http://127.0.0.1:9000/thehive}"
THEHIVE_ADMIN_USER="${THEHIVE_ADMIN_USER:-admin@thehive.local}"
THEHIVE_ADMIN_PASSWORD="${THEHIVE_ADMIN_PASSWORD:-secret}"
FLOW_ORG="${FLOW_ORG:-demo}"
FLOW_PROFILE="${FLOW_PROFILE:-flow-service}"
FLOW_SERVICE_USER="${FLOW_SERVICE_USER:-thehive-flow@thehive.local}"
FLOW_API_KEY_PLACEHOLDER="replace-with-a-thehive-api-key"

_th_response=$(mktemp)
trap 'rm -f "${_th_response}"' EXIT

## th_api METHOD ENDPOINT [JSON_BODY] [API_KEY]
## Prints the HTTP status code (000 when unreachable), the response body is left in ${_th_response}.
## Authenticates as the TheHive admin, or with the API key when one is given (passed on stdin, never
## on a command line).
th_api() {
  local method=$1 endpoint=$2 data=${3:-} key=${4:-}
  local args=(-s -o "${_th_response}" -w '%{http_code}' --connect-timeout 5 --max-time 30 -X "${method}" "${THEHIVE_LOCAL_URL}${endpoint}" -H 'Content-Type: application/json')
  [[ -n "${data}" ]] && args+=(-d "${data}")
  if [[ -n "${key}" ]]; then
    printf 'Authorization: Bearer %s\n' "${key}" | curl "${args[@]}" -H @- 2> /dev/null || true
  else
    curl "${args[@]}" -u "${THEHIVE_ADMIN_USER}:${THEHIVE_ADMIN_PASSWORD}" 2> /dev/null || true
  fi
}

## Creates the resource with POST unless GET shows it already exists
th_ensure() {
  local what=$1 get_endpoint=$2 post_endpoint=$3 data=$4 code
  code=$(th_api GET "${get_endpoint}")
  if [[ "${code}" == "200" ]]; then
    info "${what} already exists."
    return 0
  fi
  code=$(th_api POST "${post_endpoint}" "${data}")
  if [[ "${code}" != "201" && "${code}" != "200" ]]; then
    error "Cannot create ${what} (HTTP ${code}): $(cat "${_th_response}")"
    exit 1
  fi
  success "${what} created."
}

## TheHive Flow: starts TheHive, creates the service account and stores its API key for TheHive Flow
setup_thehive_flow_access() {
  local key_file="./thehive-flow/secret/thehive-api-key"

  info "Starting TheHive..."
  docker compose up -d --wait thehive || { error "TheHive did not become healthy. Check: docker compose logs thehive"; exit 1; }
  local deadline=$(( $(date +%s) + 180 ))
  until [[ "$(th_api GET /api/v1/user/current)" == "200" ]]; do
    [[ $(date +%s) -gt ${deadline} ]] && { error "Cannot authenticate to TheHive as ${THEHIVE_ADMIN_USER} at ${THEHIVE_LOCAL_URL}. Check: docker compose logs thehive"; exit 1; }
    sleep 3
  done

  th_ensure "Organisation '${FLOW_ORG}'" "/api/organisation/${FLOW_ORG}" /api/organisation \
    '{"name":"'"${FLOW_ORG}"'","description":"Organisation of the TheHive Flow service account"}'
  th_ensure "Profile '${FLOW_PROFILE}'" "/api/v1/profile/${FLOW_PROFILE}" /api/v1/profile \
    '{"name":"'"${FLOW_PROFILE}"'","permissions":["manageAnalyse","manageAction"]}'
  th_ensure "Service account '${FLOW_SERVICE_USER}'" "/api/v1/user/${FLOW_SERVICE_USER}" /api/v1/user \
    '{"login":"'"${FLOW_SERVICE_USER}"'","name":"TheHive Flow","type":"Service","organisation":"'"${FLOW_ORG}"'","profile":"'"${FLOW_PROFILE}"'"}'

  ## Keep the key of a previous run while TheHive still accepts it
  local current_key=""
  [[ -s "${key_file}" ]] && current_key=$(cat "${key_file}")
  if [[ -n "${current_key}" && "${current_key}" != "${FLOW_API_KEY_PLACEHOLDER}" && "$(th_api GET /api/v1/user/current "" "${current_key}")" == "200" ]]; then
    info "TheHive API key of TheHive Flow already provisioned."
    return 0
  fi

  local code new_key
  code=$(th_api POST "/api/v1/user/${FLOW_SERVICE_USER}/key/renew")
  new_key=$(tr -d '"[:space:]' < "${_th_response}")
  if [[ "${code}" != "200" || ${#new_key} -lt 16 || "${new_key}" == *[\{\}]* ]]; then
    error "Cannot create the API key of '${FLOW_SERVICE_USER}' (HTTP ${code})"
    exit 1
  fi
  ( umask 077 && printf '%s' "${new_key}" > "${key_file}" ) || { error "Cannot write ${key_file}"; exit 1; }
  chmod 600 "${key_file}"
  success "TheHive API key of TheHive Flow written to ${key_file}."
}
