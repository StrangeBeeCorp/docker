> [!CAUTION]
> Please read all this documentation before starting.

# Docker compose for TheHive and Cortex

> [!IMPORTANT]
> all files in the `testing` folder are meant for prototyping, they **MUST NOT** be used in production

This repository includes a docker compose file designed to set up TheHive and Cortex on a server for testing purposes. This version provides all necessary components to deploy both TheHive and Cortex on a single server.

---
- [Docker compose for TheHive and Cortex](#docker-compose-for-thehive-and-cortex)
  - [Requirements](#requirements)
  - [Content of the application stack](#content-of-the-application-stack)
    - [Configuration and data files](#configuration-and-data-files)
    - [Content, and purpose of each files and folders](#content-and-purpose-of-each-files-and-folders)
      - [Cassandra](#cassandra)
      - [Elasticsearch](#elasticsearch)
      - [TheHive](#thehive)
      - [Cortex](#cortex)
      - [Nginx](#nginx)
      - [Certificates](#certificates)
      - [Scripts](#scripts)
  - [First steps / Initialisation](#first-steps--initialisation)
  - [Run the application stack](#run-the-application-stack)
  - [Access to the applications](#access-to-the-applications)
  - [Additional content](#additional-content)
    - [Reset your environment](#reset-your-environment)
    - [Backup / Restore](#backup--restore)
    - [Demo data](#demo-data)

---

## Requirements

Hardware requirements:
- At least 2 vCPUs dedicated to containers
- At least 8GB of RAM  (2GB per container)

Software requirements:
- Docker engine `v23.0.15` and later ([install instructions](https://docs.docker.com/engine/install/))
- Docker compose plugin `v2.20.2` and later ([install instructions](https://docs.docker.com/compose/install/))

## Content of the application stack

This *testing* Docker Compose file deploys the following components:

* Cassandra: The database used by TheHive
* Elasticsearch: Serves as the database for Cortex and the indexing engine for TheHive
* TheHive: Main application
* Cortex: Analyzers and Responders engine
* Nginx: Deployed as an HTTPS reverse proxy

### Configuration and data files

Each container has as dedicated folder for configuration, data and log files. 

```bash
.
├── cassandra
├── certificates
├── cortex
├── docker-compose.yml
├── dot.env.template
├── elasticsearch
├── nginx
├── README.md
├── scripts
└── thehive
```

### Content, and purpose of each files and folders

#### Cassandra

```bash
cassandra
├── data
└── logs
```

* **./cassandra/data**: the database files
* **./cassandra/logs**: the log files

> [!NOTE]
> These folders should not be manually modified

#### Elasticsearch

```bash
elasticsearch
├── data
└── logs
```

* **./elasticsearch/data**: the database files
* **./elasticsearch/logs**: the log files

> [!NOTE]
> These folders should not be manually modified 

#### TheHive

```bash
thehive
├── config
│   ├── application.conf
│   ├── logback.xml
│   └── secret.conf.template
├── data
│   └── files
└── logs
```

* **./thehive/config**: configuration files. `secret.conf` is generated automatically when using our init script.
* **./thehive/data/files**: file storage for TheHive
* **./thehive/logs**: TheHive log files

> [!NOTE]
> These folders should not be manually modified, except in `config` if you know what you are doing. 

#### Cortex

```bash
cortex
├── config
│   ├── application.conf
│   ├── logback.xml
│   └── secret.conf.template
├── cortex-jobs
├── logs
└── neurons
```

* **./cortex/config**: configuration files. `secret.conf` is generated automatically when using our init script.
* **./cortex/cortex-jobs**: temprary data storage for Analyzers and Responders
* **./cortex/logs**: Cortex log files
* **./cortex/neurons**: Folder dedicated to custom Analyzers and Responders

> [!NOTE]
> These folders should not be manually modified, except in `config` if you know what you are doing.


#### Nginx

```bash
nginx
├── certs
└── templates
    └── default.conf.template
```

* **./nginx/templates/default.conf.template**: this file is used to initiate the configuration of Nginx when the container is initialised.

> [!NOTE]
> These folders should not be manually modified.

#### Certificates

This foler is empty. By default, the application stack is initialised with self-signed certificates. 

If you want to use your own certificates, like one signed by an internal authority, create following files - ensure to use the filenames written - : 

```bash
certificates
├── server.crt         ## Server certificate
├── server.key         ## Server private key
└── ca.pem             ## Certificate Authority
```


#### Scripts

```bash
scripts
├── check_permissions.sh
├── generate_certs.sh
├── init.sh
├── output.sh
├── reset.sh
├── test_init_applications.sh
├── test_init_cortex.sh
└── test_init_thehive.sh
```

The application stack includes several utility scripts:

* **check_permissions.sh**: Ensures proper permissions are set on files and folders
* **generate_certs.sh**: Generates a self-signed certificate for Nginx.
* **init.sh**: Initializes the application stack.
* **output.sh**: Displays output messages, called by other scripts.
* **reset.sh**: Resets the testing environmenent. **WARNING** Running this script deletes all data.
* **test_init_applications.sh**: Configures TheHive and Cortex by enabling Analyzers, integrating Cortex with TheHive, and creating sample data in TheHive.
* **test_init_cortex.sh**: Helper script called by *test_init_applications.sh* to set up Cortex
* **test_init_thehive.sh**: Helper script called by *test_init_applications.sh* to set up TheHive

## First steps / Initialisation

The application will run under the user account and group that executes the init script.

Run the *init.sh* script: 

```bash
bash ./scripts/init.sh
```

This script wil perform following actions: 

* Prompts for a service name to include in the Nginx server certificate.
* Initializes the `secret.conf` files for TheHive and Cortex.
* Generates self-signed certificate none is found in `./certificates`
* Creates a `.env` file will user/group information and other application settings
* Verifies file and folder permissions.


## Run the application stack

```bash
docker compose up
```

or 

```bash
docker compose up -d
```

## Access to the applications

Open your browser, and navigate to: 

* `https://HOSTNAME_OR_IP/thehive` to connect to TheHive
* `https://HOSTNAME_OR_IP/cortex` to connect to Cortex


## Additional content

Multiple scripts are also provided to help managing and testing the applications: 

### Reset your environment

Run the following script to delete all data in the *testing* environment: 

```bash
bash ./scripts/reset.sh
```

> [!CAUTION]
> This scripts deletes all data and containers. 

Run the *init.sh* script to reload a new *production* instance. 
 

### Backup / Restore

This profile includes two utility scripts to assist with performing cold backups and restores. You can find these scripts here: [./scripts/backup.sh](./scripts/backup.sh) and [./scripts/restore.sh](./scripts/restore.sh)
For detailed information about backup and restore strategies and processes, please refer to the [dedicated documentation](https://docs.strangebee.com/thehive/operations/backup-restore/overview/).


### Demo data

Run the following script to configure TheHive and Cortex with sample data: 

```bash
bash ./scripts/test_init_applications.sh
```

This scripts will: 

* Initialize Cortex with a `Demo` organisation and `thehive` account
* Enable some free Analyzers
* Initialize TheHive with a `Demo` organisation and `thehive` account
* Integrate TheHive with Cortex
* Add sample data like Alerts, Observables, Custom fields. 