#!/bin/bash

## This scripts should be run from the directory containing the file `docker-compose.yml` with the following command:
##  bash ./scripts/init.sh

source $(dirname $0)/output.sh         # Used to display output
source $(dirname $0)/generate_certs.sh # Used to generate self signed or custom certificate


STATUS=0

define_hostname(){
SYSTEM_HOSTNAME=$(uname -n)
info "Define the hostname used to connect to this server"
read -p "Server Name (default: ${SYSTEM_HOSTNAME} ): " choice
SERVICE_HOSTNAME=${choice:-${SYSTEM_HOSTNAME}}
}


init() {
    ELASTICSEARCH_PASSWORD=$(cat /dev/urandom | LC_CTYPE=C tr -dc '[:alnum:]' | fold -w 64 | head -n 1)

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
play.http.secret.key="$(cat /dev/urandom | LC_CTYPE=C tr -dc '[:alnum:]' | fold -w 64 | head -n 1)"
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
play.http.secret.key="$(cat /dev/urandom | LC_CTYPE=C tr -dc '[:alnum:]' | fold -w 64 | head -n 1)"
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
_EOF_

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
bash $(dirname $0)/check_permissions.sh
if [ $? -eq 0 ]
then
    init
    success "Environment initialized successfully. Run 'docker compose up' to start the application stack."
else
    error "Initialisation did not complete due to permissions issue. Please run ./scripts/check_permissions.sh to check"
fi
