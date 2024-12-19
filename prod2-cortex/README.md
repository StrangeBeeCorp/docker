> [!CAUTION]
> Please read all this documentation before starting.

# Single server deployment optimized for Cortex

## Requirements

Hardware requirements:
- At least 8 vCPUs dedicated to containers
- At least 32GB of RAM

Software requirements:
- Docker engine `v23.0.15` and later ([install instructions](https://docs.docker.com/engine/install/))
- Docker Compose plugin `v2.20.2` and later ([install instructions](https://docs.docker.com/compose/install/))

To verify that everything is properly installed, you can do the following commands:
```bash
# Check Docker engine version
docker version

# Check that the current user can run Docker commands
# Else (for Linux) check out https://docs.docker.com/engine/install/linux-postinstall/
docker run hello-world

# Check Docker Compose plugin version
docker compose version
```

## Content of the application stack

This *testing* Docker Compose file deploys the following components:

* Elasticsearch: Serves as the database for Cortex
* Cortex: Analyzers and Responders engine
* Nginx: Deployed as an HTTPS reverse proxy

### Configuration and data files

Each container has as dedicated folder for configuration, data and log files. 

```bash
.
├── certificates
├── cortex
├── docker-compose.yml
├── dot.env.template
├── elasticsearch
├── nginx
├── README.md
└── scripts
```

### Content, and purpose of each files and folders

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
└── reset.sh
```

The application stack includes several utility scripts:

* **check_permissions.sh**: Ensures proper permissions are set on files and folders
* **generate_certs.sh**: Generates a self-signed certificate for Nginx.
* **init.sh**: Initializes the application stack.
* **output.sh**: Displays output messages, called by other scripts.
* **reset.sh**: Resets the testing environmenent. **WARNING** Running this script deletes all data.

## First steps / Initialisation

The application will run under the user account and group that executes the init script.

Run the *init.sh* script: 

```bash
bash ./scripts/init.sh
```

This script wil perform following actions: 

* Prompts for a service name to include in the Nginx server certificate.
* Initializes the `secret.conf` files for Cortex.
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

* `https://HOSTNAME_OR_IP` to connect to Cortex


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