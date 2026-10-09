# Single server deployment optimized for TheHive Flow

TheHive Flow runs as its own stack, next to an existing TheHive deployment. TheHive reaches it through the Nginx TLS proxy; TheHive Flow reaches TheHive over an explicit URL. The two stacks share no Docker network.

Services: `thehive-flow`, `postgresql` (dedicated to TheHive Flow and Temporal, not shared with TheHive), `temporal`, `s3-store` (SeaweedFS), `init-s3-store` (one-shot), `nginx`. `temporal-admin` is only started by `init.sh`.

## Installation

```bash
bash ./scripts/init.sh
printf '%s' '<thehive-api-key>' > ./thehive-flow/secret/thehive-api-key
chmod 600 ./thehive-flow/secret/thehive-api-key
docker compose up -d
curl -fsS http://127.0.0.1:9090/readyz
```

`init.sh` asks for:

- the server name (TLS certificate and webhook URLs);
- the TheHive URL, as reachable from the TheHive Flow container;
- the addresses TheHive calls this server from (IPv4 or CIDR, comma-separated). Nginx refuses `/api/` to any other caller, and to every caller while the list is empty.

It generates every secret into `.env` on the first run and keeps them on later runs, creates the Temporal schema and namespace, and generates a self-signed certificate unless `server.crt`, `server.key` and `ca.pem` are provided in `./certificates`.

## Connecting TheHive

- In TheHive, enable the TheHive Flow connector, set its URL to `https://<this server>` and its JWT signing key (`TH_ORCHESTRATOR_KEY`) to the `jwt_signing_key` value of `.env`.
- Create a TheHive API key for TheHive Flow and store it in `./thehive-flow/secret/thehive-api-key` (or `thehive_api_key` in `.env`). TheHive Flow does not start without it.
- If TheHive is on a private network, allowlist its range under `modules.workers.activities.egress` in `./thehive-flow/config/thehive-flow.yml`.

## Operations

```bash
bash ./scripts/backup.sh    # cold backup (stops services), includes .env
bash ./scripts/restore.sh   # restores a backup folder
bash ./scripts/reset.sh     # WIPES everything, run init.sh again afterwards
```

The backup contains `.env`, with every secret of the stack: the databases can only be restored together with it.

## Security notes

- `thehive-flow` mounts the Docker socket to run Codex activities in containers. This grants root-equivalent access to the host, as for Cortex analyzers.
- Only Nginx (443) is published on the host network, plus the health endpoint `127.0.0.1:9090` on the loopback interface.

## Upgrades

Image tags are pinned in `../versions.env`. Run `bash ./scripts/init.sh` again to apply them, then `docker compose up -d`.

Temporal minor upgrades require a database schema update (`temporal-sql-tool update-schema`) and must be applied one minor version at a time: follow Temporal's upgrade documentation before changing the minor version of `temporal_image_version`.
