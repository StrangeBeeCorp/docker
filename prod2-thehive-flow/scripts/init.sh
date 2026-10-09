#!/bin/bash

## This script should be run from the directory containing the file `docker-compose.yml` with the following command:
##  bash ./scripts/init.sh
##
## Non-interactive mode (--yes) reads SERVICE_HOSTNAME, FLOW_THEHIVE_URL and NGINX_THEHIVE_ADDRESSES
## from the environment, falling back to the values of an existing .env file.
##
## Running it again is safe: secrets already in .env are kept, the Temporal schema and
## namespace are only created when missing.

source $(dirname $0)/output.sh         # Used to display output
source $(dirname $0)/generate_certs.sh # Used to generate self signed or custom certificate

ASSUME_YES=${ASSUME_YES:-0}
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
  esac
done

ENVFILE="./.env"
TEMPORAL_CONFIG="./temporal/config/temporal-server.yaml"
TEMPORAL_CONFIG_TEMPLATE="./temporal/config/temporal-server.yaml.template"
THEHIVE_API_KEY_FILE="./thehive-flow/secret/thehive-api-key"

## Value of a key in the existing .env file, empty if absent
existing_value() {
  [[ -f "${ENVFILE}" ]] && grep -E "^$1=" "${ENVFILE}" | head -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

## Existing secret from .env, or a new random one
secret_value() {
  local value
  value=$(existing_value "$1")
  echo "${value:-$(openssl rand -hex 32)}"
}

## Escape a value used as a sed replacement
sed_escape() {
  printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

ask() { ## ask VARIABLE "Prompt" default
  local choice
  if [[ "${ASSUME_YES}" -eq 1 ]]; then
    printf -v "$1" '%s' "${!1:-$3}"
    return
  fi
  read -p "$2 (default: $3): " choice
  printf -v "$1" '%s' "${choice:-$3}"
}

define_settings() {
  info "Define the hostname used to connect to this server"
  ask SERVICE_HOSTNAME "Server Name" "$(existing_value nginx_server_name | grep . || uname -n)"

  info "Define the TheHive URL, as reachable from the TheHive Flow container"
  ask FLOW_THEHIVE_URL "TheHive URL, e.g. http://192.168.1.10:9000" "$(existing_value flow_thehive_url)"
  if [[ ! "${FLOW_THEHIVE_URL}" =~ ^https?://[^[:space:]]+$ ]]; then
    error "Invalid TheHive URL: '${FLOW_THEHIVE_URL}'. Expected http(s)://host[:port][/path]"
    exit 1
  fi

  info "Define the addresses TheHive calls this server from (IPv4 or CIDR, comma-separated)"
  ask NGINX_THEHIVE_ADDRESSES "TheHive addresses" "$(existing_value nginx_thehive_addresses)"
  if [[ -z "${NGINX_THEHIVE_ADDRESSES}" ]]; then
    warning "No TheHive address set: nginx refuses /api/ to every caller until nginx_thehive_addresses is set in .env."
  fi

  FLOW_PUBLIC_URL=$(existing_value flow_public_url)
  FLOW_PUBLIC_URL=${FLOW_PUBLIC_URL:-https://${SERVICE_HOSTNAME}}
}

write_env() {
  local docker_gid nginx_version
  nginx_version=$(grep -E "^nginx_image_version" ../versions.env | cut -d"'" -f2)

  ## GID owning the Docker socket as seen from containers (differs from the host on Docker Desktop)
  docker_gid=$(docker run --rm --entrypoint stat -v /var/run/docker.sock:/var/run/docker.sock \
    "nginx:${nginx_version}" -c '%g' /var/run/docker.sock) || { error "Cannot read the Docker socket group."; exit 1; }

  sed -e "s|###CHANGEME_POSTGRES_PASSWORD###|$(secret_value postgres_password)|" \
      -e "s|###CHANGEME_FLOW_DB_PASSWORD###|$(secret_value flow_db_password)|" \
      -e "s|###CHANGEME_TEMPORAL_DB_PASSWORD###|$(secret_value temporal_db_password)|" \
      -e "s|###CHANGEME_S3_SECRET_ACCESS_KEY###|$(secret_value s3_secret_access_key)|" \
      -e "s|###CHANGEME_JWT_SIGNING_KEY###|$(secret_value jwt_signing_key)|" \
      -e "s|###CHANGEME_THEHIVE_API_KEY###|$(sed_escape "$(existing_value thehive_api_key)")|" \
      -e "s|###CHANGEME_FLOW_THEHIVE_URL###|$(sed_escape "${FLOW_THEHIVE_URL}")|" \
      -e "s|###CHANGEME_FLOW_PUBLIC_URL###|$(sed_escape "${FLOW_PUBLIC_URL}")|" \
      < ./dot.env.template > "${ENVFILE}.new" || exit 1
  {
    echo
    cat ../versions.env
    cat << _EOF_

## CONFIGURATION AUTOMATICALLY ADDED BY .scripts/init.sh PROGRAM.
# System variables
UID=$(id -u)
GID=$(id -g)
docker_gid=${docker_gid}

# Nginx configuration
nginx_server_name="${SERVICE_HOSTNAME}"
nginx_ssl_trusted_certificate="${NGINX_SSL_TRUSTED_CERTIFICATE_CONFIG}"
nginx_thehive_addresses="${NGINX_THEHIVE_ADDRESSES}"
_EOF_
  } >> "${ENVFILE}.new"
  mv "${ENVFILE}.new" "${ENVFILE}"
  chmod 600 "${ENVFILE}"
  success "${ENVFILE} written."
}

render_temporal_config() {
  local password line
  password=$(existing_value temporal_db_password)
  ## Literal substitution: no password on a command line, no sed/awk metacharacters
  while IFS= read -r line || [[ -n "${line}" ]]; do
    printf '%s\n' "${line//\$\{TEMPORAL_DB_PASSWORD\}/${password}}"
  done < "${TEMPORAL_CONFIG_TEMPLATE}" > "${TEMPORAL_CONFIG}"
  chmod 600 "${TEMPORAL_CONFIG}"
  success "${TEMPORAL_CONFIG} written."
}

temporal_admin() {
  docker compose --profile admin run --rm --no-deps -T temporal-admin "$@"
}

## Creates the databases and their owners, or aligns their passwords with .env.
## Passwords are read by psql from the container environment, never from a command line.
setup_databases() {
  info "Starting PostgreSQL..."
  docker compose up -d --wait postgresql || { error "PostgreSQL did not become healthy."; exit 1; }

  docker compose exec -T postgresql psql -v ON_ERROR_STOP=1 -q -U postgres -d postgres << '_EOSQL_' || { error "Database setup failed."; exit 1; }
\getenv flow_password FLOW_DB_PASSWORD
\getenv temporal_password TEMPORAL_DB_PASSWORD
SELECT 'CREATE ROLE thehive_flow LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'thehive_flow') \gexec
SELECT 'CREATE ROLE temporal LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'temporal') \gexec
SELECT format('ALTER ROLE thehive_flow PASSWORD %L', :'flow_password') \gexec
SELECT format('ALTER ROLE temporal PASSWORD %L', :'temporal_password') \gexec
SELECT 'CREATE DATABASE thehive_flow OWNER thehive_flow' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'thehive_flow') \gexec
SELECT 'CREATE DATABASE temporal OWNER temporal' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'temporal') \gexec
SELECT 'CREATE DATABASE temporal_visibility OWNER temporal' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'temporal_visibility') \gexec
-- PostgreSQL 15+ no longer grants CREATE on the public schema to every user
\connect thehive_flow
GRANT ALL ON SCHEMA public TO thehive_flow;
\connect temporal
GRANT ALL ON SCHEMA public TO temporal;
\connect temporal_visibility
GRANT ALL ON SCHEMA public TO temporal;
_EOSQL_
  success "Databases ready."
}

setup_temporal() {

  if docker compose exec -T postgresql psql -U temporal -d temporal -tAc "SELECT 1 FROM schema_version LIMIT 1" > /dev/null 2>&1
  then
    info "Temporal schema already exists."
  else
    info "Creating the Temporal schema..."
    local db
    for db in temporal visibility; do
      local dbname="temporal"
      [[ "${db}" == "visibility" ]] && dbname="temporal_visibility"
      docker compose --profile admin run --rm --no-deps -T -e SQL_PASSWORD="$(existing_value temporal_db_password)" temporal-admin \
        sh -c "temporal-sql-tool --plugin postgres12 --ep postgresql -p 5432 -u temporal --db ${dbname} setup-schema -v 0.0 \
            && temporal-sql-tool --plugin postgres12 --ep postgresql -p 5432 -u temporal --db ${dbname} update-schema -d /etc/temporal/schema/postgresql/v12/${db}/versioned" \
        || { error "Temporal schema creation failed for ${dbname}."; exit 1; }
    done
    success "Temporal schema created."
  fi

  info "Starting Temporal..."
  docker compose up -d --wait temporal || { error "Temporal did not become healthy. Check: docker compose logs temporal"; exit 1; }
  local deadline=$(( $(date +%s) + 120 ))
  until temporal_admin temporal operator cluster health --address temporal:7233 > /dev/null 2>&1; do
    [[ $(date +%s) -gt ${deadline} ]] && { error "Temporal cluster is not serving. Check: docker compose logs temporal"; exit 1; }
    sleep 3
  done

  if temporal_admin temporal operator namespace describe -n default --address temporal:7233 > /dev/null 2>&1
  then
    info "Temporal namespace 'default' already exists."
  else
    temporal_admin temporal operator namespace create -n default --address temporal:7233 || { error "Temporal namespace creation failed."; exit 1; }
    success "Temporal namespace 'default' created."
  fi
}

init() {
  define_settings
  check_user_certificates "${SERVICE_HOSTNAME}"
  write_env
  render_temporal_config
  setup_databases
  setup_temporal

  if [[ -z "$(existing_value thehive_api_key)" && ! -s "${THEHIVE_API_KEY_FILE}" ]]; then
    warning "No TheHive API key: TheHive Flow does not start without one. Write it to ${THEHIVE_API_KEY_FILE} or set thehive_api_key in .env."
  fi

  success "Initialisation completed."
  info "Use this JWT signing key as TH_ORCHESTRATOR_KEY in TheHive: see jwt_signing_key in ${ENVFILE}"
  info "Run the following command to start applications:
        $ docker compose up -d
        "
}


## ENSURE PERMISSIONS ARE WELL SET BEFORE INITIALISING
if [[ "${ASSUME_YES}" -eq 1 ]]; then
    bash $(dirname $0)/check_permissions.sh --yes
else
    bash $(dirname $0)/check_permissions.sh
fi
if [ $? -eq 0 ]
then
    init
else
    error "Initialisation did not complete due to permissions issue. Please run ./scripts/check_permissions.sh to check"
    exit 1
fi
