#!/bin/bash

## ============================================================
## RESTORE SCRIPT FOR THEHIVE APPLICATION STACK
## ============================================================
## PURPOSE:
## This script restores a backup of TheHive application stack, 
## including its configuration, data, and logs. It is designed to 
## recover from backups created using the associated backup script.
##
## IMPORTANT:
## - A backup is highly recommended before running a restore operation. 
##   This ensures you can revert to the current state if anything goes wrong.
## - Ensure that the target data folders are empty before running this script. 
##   Pre-existing files can cause conflicts or data corruption during the restore process.
## - This script must be run with sufficient permissions to overwrite 
##   application data and modify service configurations.
## - Ensure the backup folder path is correct and contains all required 
##   files and data.
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
## 1. Update the variables at the start of the script to reflect your setup:
##    - BACKUP_ROOT_FOLDER: Path to the root directory of your backups.
##    - BACKUP_TO_RESTORE: Name of the backup folder to restore.
## 2. Run the script using the following command:
##    `bash ./scripts/restore.sh`
##
## ADDITIONAL RESOURCES:
## Refer to the official documentation for detailed instructions and 
## additional information: https://docs.strangebee.com/thehive/operations/backup-restore/
##
## WARNING:
## - This script ensure Nginx, Elasticsearch, Cassandra, and TheHive services are stopped before performing the restore, and then restarts the services.
## - This script will overwrite existing data. Use it with caution.
## - Do not modify the rest of the script unless necessary.
##
## ============================================================
## DO NOT MODIFY ANYTHING BELOW THIS LINE
## ============================================================
# Display help message
if [[ "$1" == "--help" || "$1" == "-h" ]]
then
  echo "Usage: $0 [DOCKER_COMPOSE_PATH] [BACKUP_FOLDER]"
  echo
  echo "This script restores a backup of application data, including configurations, files, and logs."
  echo
  echo "Options:"
  echo "  DOCKER_COMPOSE_PATH  Optional. Specify the path of the folder with the docker-compose.yml."
  echo "                      If not provided, you will be prompted for a folder, with a default of '.'."
  echo "  BACKUP_FOLDER  Optional. Specify the folder containing the data to restore."
  echo "                      If not provided, you will be prompted for a folder or exit; no default folder is used."
  echo
  echo "Examples:"
  echo "  $0 /path/to/docker-compose-folder /path/to/backup-folder  restores backup stored in the specified folder."
  echo "  $0                 Prompt for docker compose folder and backup folder to restore."
  exit 0
fi

## Checks if the first argument is provided.
## If it is, the script uses it as the value for BACKUP_ROOT_FOLDER
## If no argument is passed, the script prompts the user to enter a value
## 
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
  read -p "Enter the backup root folder [default: None]: " BACKUP_FOLDER
  [[ -z "${BACKUP_FOLDER}" ]] && echo "No backup folder specified, exiting." && exit 1
else
  BACKUP_FOLDER="$2"
fi

## Check if the backup folder to restore exists, else exit
[[ -d ${BACKUP_FOLDER} ]] || { echo "Backup folder not found, exiting"; exit 1; }


# Define the log file and start logging. Log file is stored in the current folder
DATE="$(date +"%Y%m%d-%H%M%z" | sed 's/+/-/')"
LOG_FILE="./restore_log_${DATE}.log"
exec &> >(tee -a "$LOG_FILE")

# Log the start time
echo "Restoration process started at: $(date)"

## Exit if docker compose is running
docker compose ps | grep -q "Up" && { echo "Docker Compose services are running. Exiting. Stop services and remove data before retoring data"; exit 1; }


# Copy TheHive data
echo "Restoring TheHive data and configuration..."
rsync -aW --no-compress ${BACKUP_FOLDER}/thehive/ ${DOCKER_COMPOSE_PATH}/thehive || { echo "TheHive config restore failed"; exit 1; }

# Copy Cortex data
echo "Restoring Cortex data and configuration..."
rsync -aW --no-compress ${BACKUP_FOLDER}/cortex/ ${DOCKER_COMPOSE_PATH}/cortex || { echo "Cortex config restore failed"; exit 1; }

# Copy Casssandra data
echo "Restoring Cassandra data ..."
rsync -aW --no-compress ${BACKUP_FOLDER}/cassandra/ ${DOCKER_COMPOSE_PATH}/cassandra || { echo "Cassandra data restore failed"; exit 1; }


# Copy Elasticsearch data
echo "Restoring Elasticsearch data ..."
rsync -aW --no-compress ${BACKUP_FOLDER}/elasticsearch/ ${DOCKER_COMPOSE_PATH}/elasticsearch || { echo "Elasticsearch data restore failed"; exit 1; }


# Copy Nginx certificates
echo "Restoring Nginx data and configuration..."
rsync -a ${BACKUP_FOLDER}/nginx/ ${DOCKER_COMPOSE_PATH}/nginx  ||
 { echo " Nginx configuration and certificates restore failed"; exit 1; } 
rsync -a ${BACKUP_FOLDER}/certificates/ ${DOCKER_COMPOSE_PATH}/certificates  ||
 { echo " certificates restore failed"; exit 1; } 

## Restart services
echo "Restarting services..."
docker compose up -d

echo "Restoration process completed at: $(date)"