#! /usr/bin/env bash

## This program initialise and configure Cortex and TheHive with sample data. This allows to check that everything works fine.
## Reset the application stack by running the command: bash ./scripts/reset.sh

source $(dirname $0)/output.sh

## Initialize Cortex
info "Initializing Cortex"
bash $(dirname $0)/test_init_cortex.sh

## initialize TheHive
info "Initializing TheHive"
bash $(dirname $0)/test_init_thehive.sh

## System hostname
SYSTEM_HOSTNAME=$(uname -n)

REPORT="
Cortex:

* Cortex URL: https://${SYSTEM_HOSTNAME}/cortex
* Administrator (created by init.sh):
  Login: admin
  Password: cortex_admin_password in .env (default: secret)

* Sample analyzers are enabled in the demo organisation (created by init.sh), including TestAnalyzer.


TheHive has been initialized with following accounts:

* TheHive URL: https://${SYSTEM_HOSTNAME}/thehive
* Administrator:
  Login: admin@thehive.local
  Password: secret

* A user named thehive has been created and is org-admin of the organisation named demo:
  Login: thehive@thehive.local
  Password: thehive1234


TheHive is integrated with Cortex by init.sh.
"


echo -e "${REPORT}"
