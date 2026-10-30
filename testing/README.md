# Docker compose for TheHive and Cortex

> [!IMPORTANT]
> all files in the `testing` folder are meant for prototyping, they **MUST NOT** be used in production

Refer to the following documentation pages for installation instructions and configuration:
- [Deploy TheHive with Docker Compose](https://docs.strangebee.com/thehive/installation/docker/)
- [Run Cortex with Docker](https://docs.strangebee.com/cortex/installation-and-configuration/run-cortex-with-docker/)

## Default accounts

`scripts/init.sh` initialises the applications and prints these accounts at the end:

| Application | Login | Password |
|---|---|---|
| TheHive | `admin@thehive.local` | `secret` (TheHive default) |
| Cortex | `admin` | `secret`, set by `cortex_admin_password` in `.env` before the first `init.sh` run |

It also creates:
- in TheHive, the `demo` organisation and the `thehive-flow@thehive.local` service account used by TheHive Flow
- in Cortex, the `demo` organisation and its `demo_admin` orgadmin, whose API key registers Cortex in TheHive, and a few analyzers that need no API key

Cortex listens on `0.0.0.0:9001`: change these passwords before exposing the host.

## Configuration

`dot.env.template` lists every variable of `.env`, with its default. `init.sh` writes `.env` from it, keeps the values already set in an existing `.env`, and sets the `###CHANGEME###` ones.

## Network

The stack runs on a fixed subnet, `172.30.0.0/24` by default. TheHive, Cortex and TheHive Flow have fixed addresses (`thehive_ip`, `cortex_ip`, `thehive_flow_ip`): the egress guard of TheHive Flow allows these three addresses only. The other containers get an address from `stack_ip_range`.

If the subnet overlaps an existing network or VPN route (`Pool overlaps` at startup), change `stack_subnet`, `stack_ip_range` and the three addresses together in `.env`.

> [!NOTE]
> Upgrading an existing stack: recreate its network before starting it, with `docker compose down` then `docker compose up -d`. Do the same after changing these addresses.
