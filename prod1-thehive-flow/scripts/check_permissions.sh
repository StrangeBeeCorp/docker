#!/bin/bash
source $(dirname $0)/output.sh

## This program ensures that all files and folders are owned by the current user and permissions are set accordingly to make everything run properly
## This program is run by init.sh program
##
## Not checked: database and object store contents (postgresql/data, s3-store/data), which
## their services manage, and secrets (.env, thehive-flow/secret, rendered Temporal config), kept at 600.

ASSUME_YES=${ASSUME_YES:-0}
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
  esac
done

CURRENT_USER_ID=$(id -u)
CURRENT_GROUP_ID=$(id -g)

DATA_DIRS=(-path ./postgresql/data -o -path ./s3-store/data)
SECRET_FILES=(-path ./thehive-flow/secret/thehive-api-key -o -path ./temporal/config/temporal-server.yaml)
EXECUTABLE_FILES=(-path './scripts/*' -o -path './nginx/docker-entrypoint.d/*.sh')

## Ensure permissions are well set
## Restore permissions
UNEXPECTED_OWNERSHIP=$(find . \( "${DATA_DIRS[@]}" \) -prune -o \( ! -user ${CURRENT_USER_ID} -o ! -group ${CURRENT_GROUP_ID} \) -print)

if [ -n "${UNEXPECTED_OWNERSHIP}" ];
then
  echo "${UNEXPECTED_OWNERSHIP}" | while IFS= read -r line; do
    sudo chown ${CURRENT_USER_ID}:${CURRENT_GROUP_ID} "${line}"
    success "Ownership updated for ${line}"
    done

  [[ $? -ne 0 ]] &&\
  info "Run this command with root privileges to complete the reset process:"
  echo -n "# find . ! -user ${CURRENT_USER_ID} -o ! -group ${CURRENT_GROUP_ID} -exec chown ${CURRENT_USER_ID}:${CURRENT_GROUP_ID} {} \; "
fi

## List directories with unexpected permissions (should be 750)
NON_COMPLIANT_DIRS=$(find ./certificates ./nginx ./postgresql ./s3-store ./scripts ./temporal ./thehive-flow \
  \( "${DATA_DIRS[@]}" \) -prune -o -type d ! -perm 750 -print)

## List non-executable files with unexpected permissions (should be 644)
NON_COMPLIANT_FILES=$(find ./docker-compose.yml ./dot.env.template ./certificates ./nginx ./postgresql ./s3-store ./temporal ./thehive-flow \
  \( "${DATA_DIRS[@]}" \) -prune -o -type f ! \( "${SECRET_FILES[@]}" -o "${EXECUTABLE_FILES[@]}" \) ! -perm 644 -print)

## List executable files with unexpected permissions (should be 755)
NON_COMPLIANT_EXECUTABLE_FILES=$(find ./scripts ./nginx -type f \( "${EXECUTABLE_FILES[@]}" \) ! -perm 755)

## List secret files with unexpected permissions (should be 600)
NON_COMPLIANT_SECRET_FILES=$(find ./thehive-flow ./temporal -type f \( "${SECRET_FILES[@]}" \) ! -perm 600)

if [ -z "${NON_COMPLIANT_DIRS}" ] &&\
   [ -z "${NON_COMPLIANT_FILES}" ] &&\
   [ -z "${NON_COMPLIANT_EXECUTABLE_FILES}" ] &&\
   [ -z "${NON_COMPLIANT_SECRET_FILES}" ]
then
  success "All files and folders have expected permissions."
  exit 0
else
  warning "The following directories do not have expected permissions:"
  echo -n "${NON_COMPLIANT_DIRS}
" | sed '/^$/d' # strip empty lines

  warning "The following files do not have expected permissions:"
  echo -n "${NON_COMPLIANT_FILES}
${NON_COMPLIANT_EXECUTABLE_FILES}
${NON_COMPLIANT_SECRET_FILES}
" | sed '/^$/d' # strip empty lines

  echo  " "
  if [[ "${ASSUME_YES}" -eq 1 ]]; then
    choice="y"
  else
    read -p "Fix permissions ? (y/n): " choice
  fi
  if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
      # Apply 750 permissions to non-compliant directories
      if [ -n "${NON_COMPLIANT_DIRS}" ]; then
          echo "${NON_COMPLIANT_DIRS}" | while IFS= read -r dir; do
              chmod 750 "$dir"
              success "Updated directory permissions for: $dir"
          done
      fi

      # Apply 644 permissions to non-compliant files
      if [ -n "${NON_COMPLIANT_FILES}" ]; then
          echo "${NON_COMPLIANT_FILES}" | while IFS= read -r file; do
              chmod 644 "$file"
              success "Updated file permissions for: $file"
          done
      fi
      # Apply 755 permissions to non-compliant executable files
      if [ -n "${NON_COMPLIANT_EXECUTABLE_FILES}" ]; then
          echo "${NON_COMPLIANT_EXECUTABLE_FILES}" | while IFS= read -r file; do
              chmod 755 "$file"
              success "Updated file permissions for: $file"
          done
      fi
      # Apply 600 permissions to non-compliant secret files
      if [ -n "${NON_COMPLIANT_SECRET_FILES}" ]; then
          echo "${NON_COMPLIANT_SECRET_FILES}" | while IFS= read -r file; do
              chmod 600 "$file"
              success "Updated file permissions for: $file"
          done
      fi

      success "Permissions have been updated for files and directories."
  else
      warning "No changes made."
      exit 1
  fi

fi
