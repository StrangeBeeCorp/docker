# Docker Compose environments for TheHive and Cortex

>[!IMPORTANT]
> This repository contains Docker Compose files and additional resources to deploy TheHive and Cortex in both testing and production environments.


This repository offers various Docker Compose profiles to set up TheHive and Cortex for different use cases, including both testing and production environments. These profiles are designed to simplify deployment and ensure optimal performance based on your infrastructure requirements.

## Available Deployment Profiles

- [Testing environment](./testing/): Deploys TheHive and Cortex on a single server for testing purposes. Requirements: 8 GB RAM, 4 vCPU.
- [Production environment #1 - TheHive](./prod1-thehive/): Single server deployment optimized for TheHive. Requirements: 16 GB RAM, 4 vCPU.
- [Production environment #1 - Cortex](./prod1-cortex): Single server deployment optimized for Cortex. Requirements: 16 GB RAM, 4 vCPU.
- [Production environment #2 - TheHive](./prod2-thehive): High-performance deployment for TheHive on a dedicated server. Requirements: 32 GB RAM, 8 vCPU.
- [Production environment #2 - Cortex](./prod2-cortex): High-performance deployment for Cortex on a dedicated server. Requirements: 32 GB RAM, 8 vCPU.
