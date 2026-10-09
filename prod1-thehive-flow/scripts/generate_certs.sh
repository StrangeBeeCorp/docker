#!/bin/bash

## This program checks if the user provides custom certificates. If not, it creates self-signed certificates and use it with NGINX as Reverse Proxy. 

source $(dirname $0)/output.sh


NGINX_CERT_DIR="./nginx/certs"
USER_CERT_DIR="./certificates"

USER_CERT=0
USER_CERT_KEY=0
USER_CA=0

CERT_FILE="${NGINX_CERT_DIR}/server.crt"
KEY_FILE="${NGINX_CERT_DIR}/server.key"
CA_FILE="${NGINX_CERT_DIR}/ca.pem"

check_user_certificates() {    ## this function is called in init.sh

local SERVER_NAME=$1
[[ -f "${USER_CERT_DIR}/server.crt" ]] && USER_CERT=1 
[[ -f "${USER_CERT_DIR}/server.key" ]] && USER_CERT_KEY=1
[[ -f "${USER_CERT_DIR}/ca.pem" ]] && USER_CA=1

if [[ ${USER_CERT} -eq 1 && ${USER_CERT_KEY} -eq 1 && ${USER_CA} -eq 1  ]]
then
    success "Using custom certicates found in ${USER_CERT_DIR}."
    cp ${USER_CERT_DIR}/server.crt ${USER_CERT_DIR}/server.key ${USER_CERT_DIR}/ca.pem ${NGINX_CERT_DIR}
    export NGINX_SSL_TRUSTED_CERTIFICATE_CONFIG="ssl_trusted_certificate /etc/nginx/certs/ca.pem;"  # Configuration added to nginx if using custom certificate and authority
else
    info "No custom certificate found."
    info "If you want to provide your custom certificate for the Reverse Proxy, please copy the following files in the ./certificates directory:
    * ${USER_CERT_DIR}/server.crt 
    * ${USER_CERT_DIR}/server.key
    * ${USER_CERT_DIR}/ca.pem
"
    success "Generating self-signed certificate..."
    # Generate self-signed certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/CN=${SERVER_NAME:-localhost}"
    success "Self-signed certificate generated for ${SERVER_NAME:-localhost}."
    export NGINX_SSL_TRUSTED_CERTIFICATE_CONFIG="" # Do not fill in NGINX configuration when using self signed certificate
fi 
}

