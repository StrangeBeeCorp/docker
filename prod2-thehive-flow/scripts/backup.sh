#!/bin/bash

## ============================================================
## BACKUP SCRIPT FOR THEHIVE FLOW APPLICATION STACK
## ============================================================
## PURPOSE:
## This script creates a cold backup of TheHive Flow application stack:
## PostgreSQL data (TheHive Flow and Temporal databases), S3 object store
## data, configuration, certificates and the .env file.
##
## IMPORTANT:
## - All services are stopped during the backup to ensure data integrity.
## - The backup contains .env, which holds every secret of the stack: the
##   databases can only be restored together with it. Protect the backup folder.
## - Ensure sufficient storage is available in the backup location.
##
## DISCLAIMER:
## - Users are strongly advised to test this script in a non-production
##   environment to ensure it works as expected with their specific
##   infrastructure and application stack before using it in production.
## - The maintainers of this script are not responsible for any data loss,
##   corruption, or issues arising from the use of this script during your
##   backup or restore processes. Proceed at your own risk.
##
## USAGE:
##    `bash ./scripts/backup.sh [DOCKER_COMPOSE_PATH] [BACKUP_ROOT_FOLDER]`
##
## ============================================================
## DO NOT MODIFY ANYTHING BELOW THIS LINE
## ============================================================

# Display help message
if [[ "$1" == "--help" || "$1" == "-h" ]]
then
  echo "Usage: $0 [DOCKER_COMPOSE_PATH] [BACKUP_ROOT_FOLDER]"
  echo
  echo "This script performs a cold backup of application data, configuration and secrets."
  echo
  echo "Options:"
  echo "  DOCKER_COMPOSE_PATH  Optional. Specify the path of the folder with the docker-compose.yml."
  echo "                      If not provided, you will be prompted for a folder, with a default of '.'."
  echo "  BACKUP_ROOT_FOLDER  Optional. Specify the root folder where backups will be stored."
  echo "                      If not provided, you will be prompted for a folder, with a default of './backup'."
  exit 0
fi

if [[ -z "$1" ]]
then
  read -p "Enter the folder path including your docker compose file [default: ./]: " DOCKER_COMPOSE_PATH
  DOCKER_COMPOSE_PATH=${DOCKER_COMPOSE_PATH:-"."}
else
  DOCKER_COMPOSE_PATH="$1"
fi

if [[ -e "${DOCKER_COMPOSE_PATH}/docker-compose.yml" ]]
then
  echo "Path to your docker compose file: ${DOCKER_COMPOSE_PATH}/docker-compose.yml"
else
  { echo "Docker compose file not found in ${DOCKER_COMPOSE_PATH}"; exit 1; }
fi

if [[ -z "$2" ]]
then
  read -p "Enter the backup root folder [default: ./backup]: " BACKUP_ROOT_FOLDER
  BACKUP_ROOT_FOLDER=${BACKUP_ROOT_FOLDER:-"./backup"}
else
  BACKUP_ROOT_FOLDER="$2"
fi

DATE="$(date +"%Y%m%d-%H%M%z" | sed 's/+/-/')"
BACKUP_FOLDER="${BACKUP_ROOT_FOLDER}/${DATE}"

## Create the backup directory, readable by the current user only
mkdir -p "${BACKUP_FOLDER}" || { echo "Creating backup folder failed"; exit 1; }
chmod 700 "${BACKUP_FOLDER}"
echo "Created backup folder: ${BACKUP_FOLDER}"

## Define the log file and start logging
LOG_FILE="${BACKUP_ROOT_FOLDER}/backup_log_${DATE}.log"
exec &> >(tee -a "$LOG_FILE")

## Stop services
docker compose -f "${DOCKER_COMPOSE_PATH}/docker-compose.yml" stop || { echo "Stopping services failed"; exit 1; }

for FOLDER in postgresql s3-store thehive-flow temporal nginx certificates
do
  echo "Starting ${FOLDER} backup..."
  rsync -aW --no-compress "${DOCKER_COMPOSE_PATH}/${FOLDER}/" "${BACKUP_FOLDER}/${FOLDER}" || { echo "${FOLDER} backup failed"; exit 1; }
  echo "${FOLDER} backup completed."
done

cp -p "${DOCKER_COMPOSE_PATH}/.env" "${BACKUP_FOLDER}/dot.env" || { echo ".env backup failed"; exit 1; }
echo ".env backup completed (stored as dot.env)."

## Restart services
echo "Restarting services..."
docker compose -f "${DOCKER_COMPOSE_PATH}/docker-compose.yml" up -d

echo "Backup process completed at: $(date)"
