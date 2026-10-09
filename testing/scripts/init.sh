#!/bin/bash

## This scripts should be run from the directory containing the file `docker-compose.yml` with the following command:
##  bash ./scripts/init.sh

source $(dirname $0)/output.sh         # Used to display output
source $(dirname $0)/generate_certs.sh # Used to generate self signed or custom certificate

ASSUME_YES=${ASSUME_YES:-0}
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
  esac
done

STATUS=0

define_hostname(){
SYSTEM_HOSTNAME=$(uname -n)
if [[ "${ASSUME_YES}" -eq 1 ]]; then
    SERVICE_HOSTNAME="${SERVICE_HOSTNAME:-${SYSTEM_HOSTNAME}}"
    return
fi
info "Define the hostname used to connect to this server"
read -p "Server Name (default: ${SYSTEM_HOSTNAME} ): " choice
SERVICE_HOSTNAME=${choice:-${SYSTEM_HOSTNAME}}
}


## Value of a key in the existing .env file, empty if absent
existing_value() {
  [[ -f ./.env ]] && grep -E "^$1=" ./.env | head -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

## Existing secret from .env, or a new random one
secret_value() {
  local value
  value=$(existing_value "$1")
  echo "${value:-$(openssl rand -hex 32)}"
}

## TheHive Flow: render the Temporal configuration with the database password resolved
render_temporal_config() {
  local password line
  password=$(existing_value temporal_db_password)
  ## Literal substitution: no password on a command line, no sed/awk metacharacters
  while IFS= read -r line || [[ -n "${line}" ]]; do
    printf '%s\n' "${line//\$\{TEMPORAL_DB_PASSWORD\}/${password}}"
  done < ./temporal/config/temporal-server.yaml.template > ./temporal/config/temporal-server.yaml
  chmod 600 ./temporal/config/temporal-server.yaml
}

temporal_admin() {
  docker compose --profile admin run --rm --no-deps -T temporal-admin "$@"
}

## TheHive Flow: creates the databases and their owners, or aligns their passwords with .env.
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

## TheHive Flow: creates the Temporal schema and namespace when missing
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
    ELASTICSEARCH_PASSWORD=$(head -c 8192 /dev/urandom | LC_CTYPE=C tr -dc '[:alnum:]' | head -c 64)

    ## TheHive Flow secrets are kept from a previous run: its databases are initialised with them
    POSTGRES_PASSWORD=$(secret_value postgres_password)
    FLOW_DB_PASSWORD=$(secret_value flow_db_password)
    TEMPORAL_DB_PASSWORD=$(secret_value temporal_db_password)
    S3_SECRET_ACCESS_KEY=$(secret_value s3_secret_access_key)
    JWT_SIGNING_KEY=$(secret_value jwt_signing_key)

    ## INIT THEHIVE CONFIGURATION
    THEHIVEINDEXFILE="./thehive/config/index.conf"
    THEHIVEINDEXFILETEMPLATE="./thehive/config/index.conf.template"
    if [ -f ${THEHIVEINDEXFILE} ]
    then
        rm -f ${THEHIVEINDEXFILE}
    fi
    sed -e "s/###CHANGEME_ELASTICSEARCH_PASSWORD###/$ELASTICSEARCH_PASSWORD/g" < $THEHIVEINDEXFILETEMPLATE > $THEHIVEINDEXFILE

    THEHIVESECRETFILE="./thehive/config/secret.conf"
    if [ ! -f ${THEHIVESECRETFILE} ]
    then
        cat > ${THEHIVESECRETFILE} << _EOF_
play.http.secret.key="$(head -c 8192 /dev/urandom | LC_CTYPE=C tr -dc '[:alnum:]' | head -c 64)"
_EOF_
    else
        STATUS=1
        warning "${THEHIVESECRETFILE} file already exists and has not been modified."
    fi

    ## INIT CORTEX CONFIGURATION
    CORTEXINDEXFILE="./cortex/config/index.conf"
    CORTEXINDEXFILETEMPLATE="./cortex/config/index.conf.template"
    if [ -f ${CORTEXINDEXFILE} ]
    then
        rm -f ${CORTEXINDEXFILE}
    fi
    sed -e "s/###CHANGEME_ELASTICSEARCH_PASSWORD###/$ELASTICSEARCH_PASSWORD/g" < $CORTEXINDEXFILETEMPLATE > $CORTEXINDEXFILE

    CORTEXSECRETFILE="./cortex/config/secret.conf"
    if [ ! -f ${CORTEXSECRETFILE} ]
    then
        cat > ${CORTEXSECRETFILE} << _EOF_
play.http.secret.key="$(head -c 8192 /dev/urandom | LC_CTYPE=C tr -dc '[:alnum:]' | head -c 64)"
_EOF_
    else
        STATUS=1
        warning "${CORTEXSECRETFILE} file already exists and has not been modified."
    fi

    ## CREATE .env FILE
    ENVFILE="./.env"
    if [ -f ${ENVFILE} ]
    then
        rm -f ${ENVFILE}
    fi
    CURRENT_USER_ID=$(id -u)
    CURRENT_GROUP_ID=$(id -g)
    ## GID owning the Docker socket as seen from containers (differs from the host on Docker Desktop)
    NGINX_VERSION=$(grep -E "^nginx_image_version" ../versions.env | cut -d"'" -f2)
    DOCKER_GID=$(docker run --rm --entrypoint stat -v /var/run/docker.sock:/var/run/docker.sock \
      "nginx:${NGINX_VERSION}" -c '%g' /var/run/docker.sock) || { error "Cannot read the Docker socket group."; exit 1; }
    sed -e "s/###CHANGEME_ELASTICSEARCH_PASSWORD###/$ELASTICSEARCH_PASSWORD/g" < ./dot.env.template > $ENVFILE
    cat ../versions.env >> .env
    # Ask user for service hostname
    define_hostname
    check_user_certificates ${SYSTEM_HOSTNAME}
    # bash $(dirname $0)/generate_certs.sh ${SYSTEM_HOSTNAME} # Generate Nginx self-signed certificates if no certificate is installed.
    cat >> ${ENVFILE} << _EOF_
## CONFIGURATION AUTOMATICALLY ADDED BY .scripts/init.sh PROGRAM.
# System variables
UID=${CURRENT_USER_ID}
GID=${CURRENT_GROUP_ID}

# Nginx configuration
nginx_server_name="${SERVICE_HOSTNAME}"
nginx_ssl_trusted_certificate="${NGINX_SSL_TRUSTED_CERTIFICATE_CONFIG}"

# TheHive Flow configuration (secrets are kept when init.sh is run again)
postgres_password=${POSTGRES_PASSWORD}
flow_db_password=${FLOW_DB_PASSWORD}
temporal_db_password=${TEMPORAL_DB_PASSWORD}
s3_access_key_id=thehive-flow
s3_secret_access_key=${S3_SECRET_ACCESS_KEY}
# Same value as TH_ORCHESTRATOR_KEY in TheHive
jwt_signing_key=${JWT_SIGNING_KEY}
thehive_api_key=
flow_thehive_url=http://thehive:9000/thehive
flow_public_url=https://${SERVICE_HOSTNAME}/flow
docker_gid=${DOCKER_GID}
_EOF_
    chmod 600 ${ENVFILE}

    ## INIT THEHIVE FLOW
    render_temporal_config
    ## TheHive Flow does not start without a TheHive API key: use a placeholder until one is created in TheHive
    THEHIVE_API_KEY_FILE="./thehive-flow/secret/thehive-api-key"
    if [[ ! -s "${THEHIVE_API_KEY_FILE}" ]]
    then
        printf '%s' 'replace-with-a-thehive-api-key' > "${THEHIVE_API_KEY_FILE}"
        chmod 600 "${THEHIVE_API_KEY_FILE}"
        warning "Placeholder TheHive API key written to ${THEHIVE_API_KEY_FILE}: replace it with a TheHive API key to let TheHive Flow call TheHive."
    fi
    setup_databases
    setup_temporal

    if [ ${STATUS} == 0 ]
    then
        success "Initialisation completed."
        info "Run the following command to start applications:
        $ docker compose up
        "
        exit 0
    fi
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
    success "Environment initialized successfully. Run 'docker compose up' to start the application stack."
else
    error "Initialisation did not complete due to permissions issue. Please run ./scripts/check_permissions.sh to check"
fi
