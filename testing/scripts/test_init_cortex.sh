#! /usr/bin/env bash

## Enables sample analyzers in the Cortex organisation created by init.sh (scripts/setup_cortex_access.sh).
## Optional, not run by init.sh. Creates no account and keeps the API key TheHive uses.

source $(dirname $0)/output.sh
source $(dirname $0)/setup_cortex_access.sh

## Superadmin created by init.sh
CORTEX_ADMIN_PASSWORD=$(grep -E '^cortex_admin_password=' ./.env 2> /dev/null | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//')
CORTEX_ADMIN_PASSWORD=${CORTEX_ADMIN_PASSWORD:-secret}

## Analyzers that need neither an API key nor any other value only a user has; the latest version
## of the catalogue is used. TestAnalyzer runs no external call: tests/cortex.sh uses it.
CORTEX_ANALYZERS=(
  Abuse_Finder
  CIRCLHashlookup
  CyberCrime-Tracker
  DomainMailSPFDMARC
  DShield_lookup
  EmlParser
  FileInfo
  GoogleDNS_resolve
  Inoitsu
  Maltiverse_Report
  MaxMind_GeoIP
  StopForumSpam
  TeamCymruMHR
  TestAnalyzer
  UnshortenLink
)

cx_login || { error "Cannot authenticate to Cortex as ${CORTEX_ADMIN_USER} (cortex_admin_password in .env): run scripts/init.sh first."; exit 1; }

## Read again from Cortex on each run, never stored
key=$(cx_user_key "${CORTEX_ORG_ADMIN}")
[[ -n "${key}" ]] || { error "Cannot read the API key of '${CORTEX_ORG_ADMIN}': run scripts/init.sh first."; exit 1; }

info "Enabling analyzers in the Cortex organisation '${CORTEX_ORG}'"
cx_enable_analyzers "${key}"
