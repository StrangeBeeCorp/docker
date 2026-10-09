#! /usr/bin/env bash

## This program remove all data and delete all files created by init.sh script. Once executed successfully, the folder is clean with no data.

source $(dirname $0)/output.sh  # used to display output

error "This action will completely reset the application stack. All data will be lost!"
read -p "Continue ? (y/n): " choice

if [[ "$choice" == "y" || "$choice" == "Y" ]]
then
  ## Stop services
  docker compose down

  ## Delete folder contents
  DIRECTORIES="./cassandra/data ./cassandra/logs  ./elasticsearch/data ./elasticsearch/logs  ./thehive/data/files ./thehive/logs ./cortex/logs ./postgresql/data ./s3-store/data"


  for D in ${DIRECTORIES}
  do
    rm -rf ${D}/*
  done
  success "All data removed."

  ## DELETE index.conf and secret.conf FILES
  rm ./thehive/config/index.conf
  rm ./thehive/config/secret.conf
  rm ./cortex/config/index.conf
  rm ./cortex/config/secret.conf
  rm -f ./temporal/config/temporal-server.yaml ./thehive-flow/secret/thehive-api-key
  success "index and secret files deleted."

  ## DELETE cert files
  rm -rf ./nginx/certs/*
  success "Certificates deleted."

  ## DELETE .env FILE
  rm .env
  success ".env file deleted."

  ## Restore permissions
  CURRENT_USER_ID=$(id -u)
  CURRENT_GROUP_ID=$(id -g)
  UNEXPECTED_OWNERSHIP=$(find . ! -user ${CURRENT_USER_ID} -o ! -group ${CURRENT_GROUP_ID})

  if [ -n "${UNEXPECTED_OWNERSHIP}" ];
  then
    echo "${UNEXPECTED_OWNERSHIP}" | while IFS= read -r line; do
      sudo chown ${CURRENT_USER_ID}:${CURRENT_GROUP_ID} "${line}"
      success "Ownership updated for ${line}"
      done

    [[ $? -ne 0 ]] && info "Run this command with root privileges to complete the reset process:\n
    # find . ! -user ${CURRENT_USER_ID} -o ! -group ${CURRENT_GROUP_ID} -exec chown ${CURRENT_USER_ID}:${CURRENT_GROUP_ID} {} \; "
  fi

  rm -rf ./cortex/logs/*
  success "Cortex logs removed"

else
  exit 0
fi
