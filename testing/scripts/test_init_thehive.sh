#! /usr/bin/env bash

source $(dirname $0)/output.sh

THEHIVE_URL="https://127.0.0.1/thehive"

set -e
LOG_FILE=$(mktemp)

RED='\033[0;31m'
GREEN='\033[0;32m'
BROWN='\033[0;33m'
NC='\033[0m' # No Color

log() {
  echo "${BROWN}$1 ... ${NC}" | tee -a ${LOG_FILE} >&2
}

ok() {
  echo "OK" >&2
}

ko() {
  echo "KO" >&2
}

check() {
  expected=$1
  count=0
  shift
  while true
  do
    status_code=$(curl -k "$@" -s -o /dev/stderr -w '%{http_code}' 2>>${LOG_FILE}) || true
    if [ "${status_code}" = "${expected}" ]
    then
      break
    else
      warning "got ${status_code}, expected ${expected}" >&2
      warning "retrying in few seconds..."
      #echo "see more detail in $LOG_FILE" >&2
      count=$((${count}+1))
      if [ ${count} = 30 ]
      then
        cat ./thehive/log/application.log
        exit 1
      else
        sleep 40
      fi
    fi
  done
}


# Check service is alive
check_service() {
  check 200 "$THEHIVE_URL/api/v1/user/current" -u admin@thehive.local:secret &&\
  info "TheHive service is running" || warning "TheHive is not started"
}

restart_services() {
  info "Restarting thehive"
  docker compose restart thehive && info "Restarting TheHive"
}

create_org() {
  if [ "$(curl -k -s -o /dev/null -w '%{http_code}' -u admin@thehive.local:secret "$THEHIVE_URL/api/organisation/demo")" = "200" ]
  then
    info "Demo organisation already exists"
    return 0
  fi
  check 201 "$THEHIVE_URL/api/organisation" -H 'Content-Type: application/json' -u admin@thehive.local:secret -d '
    {
      "description" : "demo organisation",
      "name" : "demo" 
    }'
} && success "Demo organisation"


create_orgadmin() {
  info "Creating TheHive orgadmin user"
  ID=`curl -k -s -XPOST "$THEHIVE_URL/api/v1/user" -H 'Content-Type: application/json' -u admin@thehive.local:secret -d '
    {
      "login" : "thehive@thehive.local",
      "name" : "thehive",
      "organisation": "demo",
      "profile": "org-admin",
      "password" : "thehive1234"
    }' | jq -r ._id` 
  

  curl -k -s -XPUT "$THEHIVE_URL/api/v1/user/${ID}/organisations" -H 'Content-Type: application/json' -o /dev/stderr -u admin@thehive.local:secret -d '
    {
      "organisations": [
        {
          "organisation": "admin",
          "profile": "admin"
        },
        {
          "organisation": "demo",
          "profile": "org-admin"
        }
      ]
    }' 2>>${LOG_FILE}
}

create_customfields() {
  info "Creating Custom fields"

  check 201 "$THEHIVE_URL/api/customField" -H 'Content-Type: application/json' -u admin@thehive.local:secret -d '
    {
    "name": "BusinessImpact",
    "reference": "businessimpact",
    "description": "Impact of the incident on business",
    "type": "string",
    "mandatory": false,
    "options": [
        "Critical",
        "High",
        "Medium",
        "Low"
    ]
  }' && success "CF BusinessImpact created"

  check 201 "$THEHIVE_URL/api/customField" -H 'Content-Type: application/json' -u admin@thehive.local:secret -d '
    {
    "name": "BusinesUnit",
    "reference": "businessunit",
    "description": "Targeted business unit",
    "type": "string",
    "mandatory": false,
    "options": [
      "VIP",
      "HR",
      "Security",
      "Sys Administrators",
      "Developers",
      "Sales",
      "Marketing",
      "Procurement",
      "Legal"
    ]
  }' && success "CF BusinessUnit created"

  check 201 "$THEHIVE_URL/api/customField" -H 'Content-Type: application/json' -u admin@thehive.local:secret -d '
    {
    "name": "SLA",
    "reference": "sla",
    "description": "",
    "type": "integer",
    "mandatory": false,
    "options": [
        4,
        8,
        12,
        24
    ]
  }' && success "CF SLA created"

  check 201 "$THEHIVE_URL/api/customField" -H 'Content-Type: application/json' -u admin@thehive.local:secret -d '
    {
    "name": "Contact",
    "reference": "contact",
    "description": "email address of the contact",
    "type": "string",
    "mandatory": false,
    "options": [
    ]
  }' && success "CF Contact created"


  check 201 "$THEHIVE_URL/api/customField" -H 'Content-Type: application/json' -u admin@thehive.local:secret -d '
    {
    "name": "Hits",
    "reference": "hits",
    "description": "Numbers if hits found during the hunting",
    "type": "integer",
    "mandatory": false,
    "options": [
    ]
  }'
} && success "CF Hits created"

create_case_template() {
  info "Creating case template"
  check 201 "$THEHIVE_URL/api/v1/caseTemplate" -H 'Content-Type: application/json' -u thehive@thehive.local:thehive1234 -d '
    {
    "name": "MISPEvent",
    "titlePrefix": null,
    "severity": 2,
    "tlp": 2,
    "pap": 2,
    "tags": [
        "hunting"
    ],
    "tasks": [
        {
            "order": 0,
            "title": "Search for IOCs on Mail gateway logs",
            "group": "default",
            "description": "Run queries in Mail gateway logs and look for IOcs of type IP, email addresses, hostnames, free text. "
        },
        {
            "order": 1,
            "title": "Search for IOCs on Firewall logs",
            "group": "default",
            "description": "Run queries in firewall logs and look for IOcs of type IP, port"
        },
        {
            "order": 2,
            "title": "Search for IOCs on Web proxy logs",
            "group": "default",
            "description": "Run queries in web proxy logs and look for IOcs of type IP, domain, hostname, user-agent"
        }
    ],
    "customFields": [
        {
          "name": "hits",
          "value": null
        }
			],
    "description": "Check if IOCs shared by the community have been seen on the network",
    "displayName": "MISP"
    }'
}

create_alert_observable() {
  ID=$1
  OBS=$2
  check 201 "${THEHIVE_URL}/api/v1/alert/${ID}/observable" -H 'X-Organisation: demo' -H 'Content-Type: application/json' -u thehive@thehive.local:thehive1234 -d "${OBS}"
} && success "Observable for Alert $1 created"

create_case_observable() {
  
  ID=$1
  OBS=$2
  check 201 "${THEHIVE_URL}/api/v1/case/${ID}/observable" -H 'X-Organisation: demo' -H 'Content-Type: application/json' -u thehive@thehive.local:thehive1234 -d "${OBS}"
} && success "Observable for Case $1 created"


create_alerts() {
  info " Creating Alert"
  ID=`curl -k -s -XPOST "${THEHIVE_URL}/api/v1/alert" -H 'X-Organisation: demo' -H 'Content-Type: application/json' -u thehive@thehive.local:thehive1234 -d '
    {
      "caseTemplate": "MISPEvent",
      "customFields": [
            {
              "name": "hits",
              "value": null,
              "order": 0
          }
      ],
      "description": "Imported from MISP Event #1311.",
      "severity": 1,
      "source": "misp server",
      "sourceRef": "1311",
      "tags": [
          "tlp:pwhite",
          "type:OSINT",
          "osint:lifetime=\"perpetual\""
      ],
      "title": "CISA.gov - AA21-062A Mitigate Microsoft Exchange Server Vulnerabilities",
      "tlp": 0,
      "type": "misp"
    }'| jq -r ._id`
    create_alert_observable ${ID} '{
        "tlp": 0,
        "message": "imported from MISP event",
        "dataType": "ip",
        "data": ["5.254.43.18"],
        "ignoreSimilarity": false
      }'
    create_alert_observable ${ID} '{
        "tlp": 0,
        "message": "imported from MISP event",
        "dataType": "ip",
        "data": ["5.2.69.14"],
        "ignoreSimilarity": false
      }'
    create_alert_observable ${ID} '{
        "tlp": 0,
        "message": "imported from MISP event",
        "dataType": "hash",
        "data": ["65149e036fff06026d80ac9ad4d156332822dc93142cf1a122b1841ec8de34b5"],
        "ignoreSimilarity": false
      }'
    create_alert_observable ${ID} '{
        "tlp": 0,
        "message": "imported from MISP event",
        "dataType": "other",
        "data": ["Cybersecurity and Infrastructure Security (CISA) partners have observed active exploitation of vulnerabilities in Microsoft Exchange Server products. Successful exploitation of these vulnerabilities allows an unauthenticated attacker to execute arbitrary code on vulnerable Exchange Servers, enabling the attacker to gain persistent system access, as well as access to files and mailboxes on the server and to credentials stored on that system. Successful exploitation may additionally enable the attacker to compromise trust and identity in a vulnerable network. Microsoft released out-of-band patches to address vulnerabilities in Microsoft Exchange Server. The vulnerabilities impact on-premises Microsoft Exchange Servers and are not known to impact Exchange Online or Microsoft 365 (formerly O365) cloud email services. This Alert includes both tactics, techniques and procedures (TTPs) and the indicators of compromise (IOCs) associated with this malicious activity. To secure against this threat, CISA recommends organizations examine their systems for the TTPs and use the IOCs to detect any malicious activity. If an organization discovers exploitation activity, they should assume network identity compromise and follow incident response procedures. If an organization finds no activity, they should apply available patches immediately and implement the mitigations in this Alert."],
        "ignoreSimilarity": false
      }'
    create_alert_observable ${ID} '{
        "tlp": 0,
        "message": "imported from MISP event",
        "dataType": "ip",
        "data": ["211.56.98.146"],
        "ignoreSimilarity": false
      }'
    create_alert_observable ${ID} '{
        "tlp": 0,
        "message": "imported from MISP event",
        "dataType": "hash",
        "data": ["2b6f1ebb2208e93ade4a6424555d6a8341fd6d9f60c25e44afe11008f5c1aad1"],
        "ignoreSimilarity": false
      }'

  
}

create_case() {
  info " Creating Case"
  ID=`curl -k -s -XPOST "${THEHIVE_URL}/api/v1/case" -H 'X-Organisation: demo' -H 'Content-Type: application/json' -u thehive@thehive.local:thehive1234 -d '
    {
      "customFields": [
            {
              "name": "hits",
              "value": null,
              "order": 0
          }
      ],
      "description": "Case used to test Analyzers and Responders",
      "severity": 1,
      "title": "Analyzers and Responders development",
      "tlp": 0
    }'| jq -r ._id`
    create_case_observable ${ID} '{
        "tlp": 0,
        "message": "Analyzers and Responders development",
        "dataType": "ip",
        "data": ["8.8.8.8"],
        "ignoreSimilarity": false
      }'
    create_case_observable ${ID} '{
        "tlp": 0,
        "message": "Analyzers and Responders development ; EICAR test SHA256",
        "dataType": "hash",
        "data": ["275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f"],
        "ignoreSimilarity": false
      }'
  
}




check_service
create_org
create_orgadmin
create_customfields
create_case_template
create_alerts
create_case 
check_service
