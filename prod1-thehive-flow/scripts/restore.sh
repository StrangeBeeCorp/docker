#!/bin/bash

## ============================================================
## RESTORE SCRIPT FOR THEHIVE FLOW APPLICATION STACK
## ============================================================
## PURPOSE:
## This script restores a backup of TheHive Flow application stack created
## with scripts/backup.sh, including its .env file (secrets).
##
## IMPORTANT:
## - A backup is highly recommended before running a restore operation.
## - Ensure that the target data folders are empty before running this script.
##   Pre-existing files can cause conflicts or data corruption during the restore process.
## - This script must be run with sufficient permissions to overwrite
##   application data and modify service configurations.
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
##    `bash ./scripts/restore.sh [DOCKER_COMPOSE_PATH] [BACKUP_FOLDER]`
##
## WARNING:
## - This script will overwrite existing data and .env. Use it with caution.
##
## ============================================================
## DO NOT MODIFY ANYTHING BELOW THIS LINE
## ============================================================
# Display help message
if [[ "$1" == "--help" || "$1" == "-h" ]]
then
  echo "Usage: $0 [DOCKER_COMPOSE_PATH] [BACKUP_FOLDER]"
  echo
  echo "This script restores a backup of application data, configuration and secrets."
  echo
  echo "Options:"
  echo "  DOCKER_COMPOSE_PATH  Optional. Specify the path of the folder with the docker-compose.yml."
  echo "                      If not provided, you will be prompted for a folder, with a default of '.'."
  echo "  BACKUP_FOLDER  Optional. Specify the folder containing the data to restore."
  echo "                      If not provided, you will be prompted for a folder or exit; no default folder is used."
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
  read -p "Enter the backup folder [default: None]: " BACKUP_FOLDER
  [[ -z "${BACKUP_FOLDER}" ]] && echo "No backup folder specified, exiting." && exit 1
else
  BACKUP_FOLDER="$2"
fi

## Check if the backup folder to restore exists, else exit
[[ -d "${BACKUP_FOLDER}" ]] || { echo "Backup folder not found, exiting"; exit 1; }
[[ -f "${BACKUP_FOLDER}/dot.env" ]] || { echo "dot.env not found in the backup folder, exiting"; exit 1; }

# Define the log file and start logging. Log file is stored in the current folder
DATE="$(date +"%Y%m%d-%H%M%z" | sed 's/+/-/')"
LOG_FILE="./restore_log_${DATE}.log"
exec &> >(tee -a "$LOG_FILE")

echo "Restoration process started at: $(date)"

## Exit if docker compose is running
[[ -n "$(docker compose -f "${DOCKER_COMPOSE_PATH}/docker-compose.yml" ps -q)" ]] && { echo "Docker Compose services are running. Exiting. Stop services and remove data before restoring data"; exit 1; }

for FOLDER in postgresql s3-store thehive-flow temporal nginx certificates
do
  echo "Restoring ${FOLDER}..."
  rsync -aW --no-compress "${BACKUP_FOLDER}/${FOLDER}/" "${DOCKER_COMPOSE_PATH}/${FOLDER}" || { echo "${FOLDER} restore failed"; exit 1; }
done

cp -p "${BACKUP_FOLDER}/dot.env" "${DOCKER_COMPOSE_PATH}/.env" || { echo ".env restore failed"; exit 1; }
echo ".env restored."

## Restart services
echo "Restarting services..."
docker compose -f "${DOCKER_COMPOSE_PATH}/docker-compose.yml" up -d

echo "Restoration process completed at: $(date)"
