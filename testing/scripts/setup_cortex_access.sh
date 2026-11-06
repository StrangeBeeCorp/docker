#!/bin/bash

## Sourced by init.sh after setup_flow_access.sh (needs output.sh and th_api): initialises Cortex
## (index, superadmin, organisation and its orgadmin) and registers it in TheHive with the API key
## of the orgadmin.

CORTEX_LOCAL_URL="${CORTEX_LOCAL_URL:-http://127.0.0.1:9001/cortex}"
## URL used by TheHive to reach Cortex: Cortex is served under /cortex
CORTEX_THEHIVE_URL="${CORTEX_THEHIVE_URL:-http://cortex:9001/cortex}"
CORTEX_ADMIN_USER="${CORTEX_ADMIN_USER:-admin}"
## cortex_admin_password in .env, same default as TheHive
CORTEX_ADMIN_PASSWORD="${CORTEX_ADMIN_PASSWORD:-secret}"
## Same organisation name as the one created in TheHive for TheHive Flow
CORTEX_ORG="${CORTEX_ORG:-${FLOW_ORG:-demo}}"
CORTEX_ORG_ADMIN="${CORTEX_ORG_ADMIN:-${CORTEX_ORG}_admin}"
## Analyzers enabled in the organisation, without version: the latest one of the catalogue is used.
## None of them needs an API key.
CORTEX_ANALYZERS=(
  Abuse_Finder
  Crt_sh_Transparency_Logs
  CyberCrime-Tracker
  DShield_lookup
  EmlParser
  FileInfo
  GoogleDNS_resolve
  Maltiverse_Report
  MaxMind_GeoIP
  SpamhausDBL
  TeamCymruMHR
)

_cx_response=$(mktemp)
_cx_cookies=$(mktemp)
trap 'rm -f "${_th_response:-}" "${_cx_response}" "${_cx_cookies}"' EXIT

## cx_api METHOD ENDPOINT [JSON_BODY] [API_KEY]
## Prints the HTTP status code (000 when unreachable), the response body is left in ${_cx_response}.
## Authenticates with the API key when one is given (passed on stdin, never on a command line),
## otherwise with the session opened by cx_login, if any.
cx_api() {
  local method=$1 endpoint=$2 data=${3:-} key=${4:-}
  local args=(-s -o "${_cx_response}" -w '%{http_code}' --connect-timeout 5 --max-time 30 -X "${method}" "${CORTEX_LOCAL_URL}${endpoint}")
  ## Cortex rejects a JSON content type without a body
  [[ -n "${data}" ]] && args+=(-H 'Content-Type: application/json' -d "${data}")
  if [[ -n "${key}" ]]; then
    printf 'Authorization: Bearer %s\n' "${key}" | curl "${args[@]}" -H @- 2> /dev/null || true
  else
    curl "${args[@]}" -b "${_cx_cookies}" -c "${_cx_cookies}" 2> /dev/null || true
  fi
}

## cx_enable_analyzers API_KEY: enables the latest version of ${CORTEX_ANALYZERS} in the organisation of the key owner.
## A failure is reported but does not stop the initialisation.
cx_enable_analyzers() {
  local key=$1 code name analyzer config enabled catalogue
  code=$(cx_api GET '/api/analyzerdefinition?range=all' "" "${key}")
  [[ "${code}" != "200" ]] && { warning "Cannot list the Cortex analyzer catalogue (HTTP ${code}): $(cat "${_cx_response}")"; return 0; }
  catalogue=$(cat "${_cx_response}")
  code=$(cx_api GET '/api/analyzer?range=all' "" "${key}")
  [[ "${code}" != "200" ]] && { warning "Cannot list the Cortex analyzers (HTTP ${code}): $(cat "${_cx_response}")"; return 0; }
  enabled=$(cat "${_cx_response}")
  for name in "${CORTEX_ANALYZERS[@]}"; do
    ## Catalogue ids are <name>_<version>, dots of the version replaced by underscores (e.g. FileInfo_8_0)
    analyzer=$(grep -oE "\"id\":\"${name}_[0-9]+(_[0-9]+)*\"" <<< "${catalogue}" | cut -d'"' -f4 | sort -V | tail -n 1)
    if [[ -z "${analyzer}" ]]; then
      warning "Cortex analyzer ${name} not found in the catalogue."
      continue
    fi
    if [[ "${enabled}" == *"\"name\":\"${analyzer}\""* ]]; then
      info "Cortex analyzer ${analyzer} already enabled."
      continue
    fi
    config='"auto_extract_artifacts":false,"check_tlp":true,"max_tlp":2,"check_pap":true,"max_pap":2'
    case "${analyzer}" in
      EmlParser_*) config='"email_visualisation":true,"wkhtmltoimage_path":"/usr/bin/wkhtmltoimage","auto_extract_artifacts":true,"check_tlp":false,"max_tlp":2,"check_pap":false,"max_pap":2' ;;
      FileInfo_*) config='"manalyze_enable":false,"manalyze_enable_docker":false,"manalyze_enable_binary":false,"auto_extract_artifacts":true,"check_tlp":false,"max_tlp":2,"check_pap":false,"max_pap":2' ;;
      TestAnalyzer_*) config='"throw_error":false,"auto_extract_artifacts":false,"check_tlp":false,"max_tlp":2,"check_pap":false,"max_pap":2' ;;
    esac
    code=$(cx_api POST "/api/organization/analyzer/${analyzer}" '{"name":"'"${analyzer}"'","configuration":{'"${config}"'},"jobCache":10,"jobTimeout":30}' "${key}")
    if [[ "${code}" == "201" || "${code}" == "200" ]]; then
      success "Cortex analyzer ${analyzer} enabled."
    else
      warning "Cannot enable the Cortex analyzer ${analyzer} (HTTP ${code}): $(cat "${_cx_response}")"
    fi
  done
}

cx_login() {
  [[ "$(cx_api POST /api/login '{"user":"'"${CORTEX_ADMIN_USER}"'","password":"'"${CORTEX_ADMIN_PASSWORD}"'"}')" == "200" ]]
}

## cx_user_key USER [renew]: prints the API key of USER (a new one with "renew"), read with the
## cx_login session. Never stored: the key goes from curl to stdout only. Prints nothing without a key.
cx_user_key() {
  local endpoint="/api/user/$1/key" method=GET key
  [[ "${2:-}" == "renew" ]] && { endpoint="${endpoint}/renew"; method=POST; }
  key=$(curl -s --connect-timeout 5 --max-time 30 -X "${method}" -b "${_cx_cookies}" -c "${_cx_cookies}" \
    "${CORTEX_LOCAL_URL}${endpoint}" 2> /dev/null | tr -d '"[:space:]')
  ## A key is a bare string, an error a JSON object
  [[ ${#key} -ge 16 && "${key}" != *[\{\}\\]* ]] && printf '%s' "${key}"
}

## Creates the resource with POST unless GET shows it already exists
cx_ensure() {
  local what=$1 get_endpoint=$2 post_endpoint=$3 data=$4 code
  code=$(cx_api GET "${get_endpoint}")
  if [[ "${code}" == "200" ]]; then
    info "${what} already exists."
    return 0
  fi
  code=$(cx_api POST "${post_endpoint}" "${data}")
  if [[ "${code}" != "201" && "${code}" != "200" ]]; then
    error "Cannot create ${what} (HTTP ${code}): $(cat "${_cx_response}")"
    exit 1
  fi
  success "${what} created."
}

## Cortex: starts Cortex, initialises it and registers it in TheHive (TheHive must be running)
setup_cortex_access() {
  info "Starting Cortex..."
  docker compose up -d --wait cortex || { error "Cortex did not become healthy. Check: docker compose logs cortex"; exit 1; }
  local deadline=$(( $(date +%s) + 180 ))
  until [[ "$(cx_api GET /api/status)" == "200" ]]; do
    [[ $(date +%s) -gt ${deadline} ]] && { error "Cortex is not reachable at ${CORTEX_LOCAL_URL}. Check: docker compose logs cortex"; exit 1; }
    sleep 3
  done

  ## Creates or updates the Elasticsearch index, no-op when it is up to date
  local code
  code=$(cx_api POST /api/maintenance/migrate '{}')
  if [[ "${code}" != "204" && "${code}" != "200" ]]; then
    error "Cannot initialise the Cortex index (HTTP ${code}): $(cat "${_cx_response}")"
    exit 1
  fi
  success "Cortex index ready."

  ## The first user can be created without authentication only
  if cx_login; then
    info "Cortex superadmin '${CORTEX_ADMIN_USER}' already exists."
  else
    code=$(cx_api POST /api/user '{"login":"'"${CORTEX_ADMIN_USER}"'","name":"'"${CORTEX_ADMIN_USER}"'","password":"'"${CORTEX_ADMIN_PASSWORD}"'","roles":["superadmin"],"organization":"cortex"}')
    if [[ "${code}" != "201" ]]; then
      error "Cannot create the Cortex superadmin '${CORTEX_ADMIN_USER}' (HTTP ${code}): $(cat "${_cx_response}"). If Cortex already has one, set its password in cortex_admin_password in .env."
      exit 1
    fi
    cx_login || { error "Cannot authenticate to Cortex as ${CORTEX_ADMIN_USER}."; exit 1; }
    success "Cortex superadmin '${CORTEX_ADMIN_USER}' created."
  fi

  cx_ensure "Cortex organisation '${CORTEX_ORG}'" "/api/organization/${CORTEX_ORG}" /api/organization \
    '{"name":"'"${CORTEX_ORG}"'","description":"'"${CORTEX_ORG}"' organisation","status":"Active"}'
  cx_ensure "Cortex user '${CORTEX_ORG_ADMIN}'" "/api/user/${CORTEX_ORG_ADMIN}" /api/user \
    '{"login":"'"${CORTEX_ORG_ADMIN}"'","name":"'"${CORTEX_ORG}"' admin","roles":["read","analyze","orgadmin"],"organization":"'"${CORTEX_ORG}"'"}'

  ## Keep the key of a previous run: TheHive may already use it
  local key
  key=$(cx_user_key "${CORTEX_ORG_ADMIN}")
  if [[ -z "${key}" ]]; then
    key=$(cx_user_key "${CORTEX_ORG_ADMIN}" renew)
    [[ -n "${key}" ]] || { error "Cannot create the API key of '${CORTEX_ORG_ADMIN}'"; exit 1; }
    success "Cortex API key of '${CORTEX_ORG_ADMIN}' created."
  fi

  cx_enable_analyzers "${key}"

  ## Compared in memory: the TheHive configuration holds the API key
  local config
  config=$(curl -s --connect-timeout 5 --max-time 30 -u "${THEHIVE_ADMIN_USER}:${THEHIVE_ADMIN_PASSWORD}" \
    "${THEHIVE_LOCAL_URL}/api/v1/admin/config/cortex" 2> /dev/null)
  if [[ "${config}" == *"\"key\":\"${key}\""* ]]; then
    info "Cortex already registered in TheHive."
    return 0
  fi
  ## Body passed on stdin: it holds the API key
  code=$(printf '%s' '{"statusCheckInterval":"1 minute","refreshDelay":"5 seconds","maxRetryOnError":3,"jobTimeout":"3 hours","servers":[{"name":"cortex","url":"'"${CORTEX_THEHIVE_URL}"'","auth":{"type":"bearer","key":"'"${key}"'"},"wsConfig":{"proxy":{"state":"disabled","protocol":"http","auth":{}},"ssl":{"loose":{"acceptAnyCertificate":false},"trustManager":{}}},"filterOrganization":"all","includedTheHiveOrganisations":["*"],"excludedTheHiveOrganisations":[]}]}' \
    | curl -s -o "${_th_response}" -w '%{http_code}' --connect-timeout 5 --max-time 30 -X PUT "${THEHIVE_LOCAL_URL}/api/v1/admin/config/cortex" \
        -H 'Content-Type: application/json' -u "${THEHIVE_ADMIN_USER}:${THEHIVE_ADMIN_PASSWORD}" --data-binary @- 2> /dev/null || true)
  if [[ "${code}" != "204" && "${code}" != "200" ]]; then
    error "Cannot register Cortex in TheHive (HTTP ${code}): $(cat "${_th_response}")"
    exit 1
  fi
  success "Cortex registered in TheHive with the API key of '${CORTEX_ORG_ADMIN}'."
}
