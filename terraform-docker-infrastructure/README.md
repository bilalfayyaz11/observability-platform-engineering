# Terraform-Managed Docker Infrastructure

## What This Does

This implementation uses Terraform to provision and manage container infrastructure through the Docker provider.

The configuration creates an isolated bridge network, persistent storage, a public Nginx web container, and an internal Apache application container. Variables control environment labels, resource names, image versions, port mappings, and restart behavior.

The complete infrastructure lifecycle was validated through initialization, formatting, validation, planning, provisioning, state inspection, connectivity testing, idempotency verification, and controlled destruction.

## Architecture

    ┌───────────────────────────────────────────────┐
    │                 Terraform CLI                 │
    │                                               │
    │ init → validate → plan → apply → destroy     │
    └───────────────────────┬───────────────────────┘
                            │
                            ▼
    ┌───────────────────────────────────────────────┐
    │          Kreuzwerker Docker Provider          │
    │                                               │
    │       unix:///var/run/docker.sock             │
    └───────────────────────┬───────────────────────┘
                            │
                            ▼
    ┌───────────────────────────────────────────────┐
    │                 Docker Host                   │
    │                                               │
    │  ┌─────────────────────────────────────────┐  │
    │  │ terraform-network                      │  │
    │  │                                         │  │
    │  │  ┌──────────────────┐   Docker DNS     │  │
    │  │  │ terraform-nginx  │──────────────┐   │  │
    │  │  │                  │              ▼   │  │
    │  │  │ Nginx Alpine     │   ┌────────────┐ │  │
    │  │  │ 127.0.0.1:8080   │   │ terraform- │ │  │
    │  │  │        → 80      │   │ application│ │  │
    │  │  └────────┬─────────┘   │            │ │  │
    │  │           │             │ Apache     │ │  │
    │  │           │             │ Internal   │ │  │
    │  │           │             └────────────┘ │  │
    │  └───────────┼─────────────────────────────┘  │
    │              │                                │
    │              ▼                                │
    │  ┌─────────────────────────────────────────┐  │
    │  │ my-custom-volume                        │  │
    │  │ Mounted at /var/cache/nginx             │  │
    │  └─────────────────────────────────────────┘  │
    └───────────────────────────────────────────────┘

## Infrastructure Components

Terraform manages six infrastructure resources:

- Docker bridge network
- Persistent Docker volume
- Nginx container image
- Apache container image
- Public Nginx container
- Internal Apache application container

## Prerequisites

- Linux
- Terraform 1.6 or later
- Docker Engine
- Access to the Docker socket
- Git
- curl
- jq
- Internet access to Terraform Registry and Docker Hub

## Setup and Installation

Clone the repository:

    git clone https://github.com/bilalfayyaz11/observability-platform-engineering.git
    cd observability-platform-engineering/terraform-docker-infrastructure

Install Terraform using HashiCorp's signed Ubuntu repository:

    sudo apt update
    sudo apt install -y ca-certificates curl gpg lsb-release

    curl -fsSL https://apt.releases.hashicorp.com/gpg |
      gpg --dearmor |
      sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
      sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

    sudo apt update
    sudo apt install -y terraform

Ensure Docker is running and the current user has access:

    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"

Reconnect after changing Docker group membership.

Verify the tools:

    terraform version
    docker --version
    docker info

## Configuration Files

### main.tf

Defines the Terraform version, Docker provider, bridge network, persistent volume, container images, public web container, internal application container, labels, and resource dependencies.

### variables.tf

Defines validated configuration for:

- Environment
- Docker network name
- Persistent volume name
- Public HTTP port
- Restart policy
- Container images
- Container names

### outputs.tf

Returns:

- Web container ID
- Application container ID
- Network name
- Volume name
- Public web URL
- Managed container names

### terraform.tfvars

Provides deployment-specific values such as the network name, volume name, port, images, environment, and restart policy.

## How to Reproduce

Initialize the Terraform directory:

    terraform init

Format the configuration:

    terraform fmt -recursive

Validate the configuration:

    terraform validate

Create a saved execution plan:

    terraform plan \
      -var-file="terraform.tfvars" \
      -out="tfplan"

Review the plan:

    terraform show tfplan

Provision the infrastructure:

    terraform apply tfplan

Display managed resources:

    terraform state list

Display outputs:

    terraform output

Display machine-readable outputs:

    terraform output -json | jq .

## Infrastructure Verification

Confirm that both containers are running:

    docker ps \
      --filter "name=terraform-" \
      --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

Inspect the managed network:

    docker network inspect terraform-network

Inspect the persistent volume:

    docker volume inspect my-custom-volume

Test the public Nginx service:

    curl --fail http://localhost:8080

Test internal Docker DNS and connectivity:

    docker exec terraform-nginx \
      wget \
      --quiet \
      --output-document=- \
      http://application

The Nginx container resolves the internal Apache service through the `application` network alias.

## State Management

List tracked resources:

    terraform state list

Inspect the public container:

    terraform state show docker_container.web_server

Inspect the internal container:

    terraform state show docker_container.application_server

Inspect the Docker network:

    terraform state show docker_network.application

Inspect the persistent volume:

    terraform state show docker_volume.nginx_cache

## Idempotency Verification

Run another plan after provisioning:

    terraform plan \
      -var-file="terraform.tfvars" \
      -detailed-exitcode

Terraform should report:

    No changes. Your infrastructure matches the configuration.

This confirms that the deployed resources match the declarative configuration and that Terraform does not introduce unnecessary changes.

## Controlled Destruction

Create a destruction plan:

    terraform plan \
      -destroy \
      -var-file="terraform.tfvars" \
      -out="destroy.tfplan"

Review and apply it:

    terraform show destroy.tfplan
    terraform apply destroy.tfplan

Verify cleanup:

    terraform state list
    docker ps -a --filter "name=terraform-"
    docker network inspect terraform-network
    docker volume inspect my-custom-volume
    curl --max-time 3 http://localhost:8080

## Tools Used

- Terraform
- HashiCorp Configuration Language
- Kreuzwerker Docker provider
- Docker Engine
- Nginx
- Apache HTTP Server
- Linux
- Bash
- Git
- curl
- jq

## Key Skills Demonstrated

- Declarative infrastructure configuration
- Terraform provider management
- Docker infrastructure provisioning
- Container network isolation
- Persistent storage management
- Input-variable validation
- Terraform output management
- Dependency graph management
- Saved execution plans
- Terraform state inspection
- Infrastructure idempotency verification
- Docker DNS and connectivity testing
- Controlled resource destruction
- Docker socket troubleshooting
- Infrastructure configuration debugging

## Real-World Use Case

This pattern can be used by platform, DevSecOps, AIOps, and application engineering teams to create reproducible development, integration, testing, and internal service environments.

The same Terraform lifecycle can be extended to cloud networking, virtual machines, Kubernetes clusters, databases, load balancers, monitoring systems, secrets, and machine-learning infrastructure.

## Security Considerations

- Docker group membership grants elevated control over the host.
- The public container is bound only to `127.0.0.1`.
- The internal application container does not expose a host port.
- Terraform state must never be committed to version control.
- Production state should use encrypted remote storage and locking.
- Provider and container-image versions should be reviewed through controlled updates.
- Container images should be pinned by digest for stronger supply-chain integrity.

## Verified Results

The following outcomes were confirmed:

- Terraform initialized successfully
- Provider dependencies downloaded successfully
- Configuration formatting passed
- Configuration validation passed
- Saved execution plan created
- Six resources provisioned
- Two containers started
- Both containers joined the managed network
- Persistent volume created
- Nginx responded on port 8080
- Internal Apache service resolved through Docker DNS
- Terraform outputs returned expected values
- State tracked all resources
- A second plan reported no changes
- State was backed up before destruction
- All managed resources were removed cleanly

## Lessons Learned

- Terraform state maps configuration to deployed infrastructure.
- Saved plans make changes reviewable before execution.
- Provider version constraints reduce unexpected upgrades.
- Variable validation rejects invalid configuration early.
- Docker aliases provide predictable service discovery.
- Empty volumes should not be mounted over required default content.
- Idempotency confirms that declared and actual infrastructure match.
- Destruction should be planned, reviewed, and verified.
- Local Docker provisioning provides a strong foundation for cloud Infrastructure as Code.

## Troubleshooting Log

### Terraform Missing

Terraform was installed using HashiCorp's signed Ubuntu package repository rather than an old manually downloaded ZIP archive.

### Docker Permission Denied

Docker was running, but the user initially lacked access to `/var/run/docker.sock`.

The user was added to the Docker group:

    sudo usermod -aG docker "$USER"

### Incorrect Shell Through sg

The initial group-activation command used `sg docker -c`, which launched `/bin/sh`. Ubuntu's default `sh` did not support `set -o pipefail`.

The corrected form explicitly launched Bash:

    sg docker -c 'bash -c "commands"'

### Missing Application Container

The initial specification referenced a second application container without defining it. An Apache container was added and attached to the private network.

### Empty Volume Over Nginx Content

Mounting an empty volume over `/usr/share/nginx/html` would hide the default Nginx page.

The persistent volume was mounted at:

    /var/cache/nginx

### Outdated Provider Constraint

The older Docker provider constraint was replaced with a compatible 4.x constraint and validated before provisioning.

## Future Improvements

- Configure encrypted remote state
- Enable state locking
- Add continuous integration checks
- Add infrastructure security scanning
- Pin container images by digest
- Add health checks
- Add monitoring and alerting
- Add centralized logging
- Add reusable Terraform modules
- Add multiple environments
- Extend provisioning to AWS, Azure, or Google Cloud
- Add Kubernetes infrastructure
- Add automated drift detection
