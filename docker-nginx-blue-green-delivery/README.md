# Docker and Nginx Blue-Green Delivery

## What This Does

This implementation provides a zero-downtime deployment workflow using two parallel Docker environments and Nginx as the production traffic router.

Blue runs application version 1.0 while Green runs version 2.0. Both versions remain independently deployable and testable before production traffic is changed. A deployment switcher validates the candidate application, generates a new Nginx configuration, tests the configuration, reloads Nginx gracefully, verifies the active version, records deployment state, and restores the previous configuration automatically when validation fails.

An availability monitor sends continuous HTTP requests while traffic is being switched. The completed deployment cycle proved that Green could be promoted and Blue could be restored without failed production requests.

## Architecture

    ┌─────────────────────────────────────────────────────────────┐
    │                       Client Traffic                        │
    │                                                             │
    │                  HTTP requests to port 80                   │
    └──────────────────────────────┬──────────────────────────────┘
                                   │
                                   ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                       Host Nginx                             │
    │                                                             │
    │  Candidate validation → Config test → Graceful reload       │
    │                                                             │
    │  Production endpoint: http://127.0.0.1                      │
    │  Health endpoint:     http://127.0.0.1/health               │
    └──────────────────────────────┬──────────────────────────────┘
                                   │
                 ┌─────────────────┴─────────────────┐
                 │                                   │
                 ▼                                   ▼
    ┌───────────────────────────┐       ┌───────────────────────────┐
    │ Blue Environment          │       │ Green Environment         │
    │                           │       │                           │
    │ Container: blue-app       │       │ Container: green-app      │
    │ Image: app-blue:1.0       │       │ Image: app-green:2.0      │
    │ Host: 127.0.0.1:8080      │       │ Host: 127.0.0.1:8081      │
    │ Application version: 1.0  │       │ Application version: 2.0  │
    │ Docker health check       │       │ Docker health check       │
    │ Independent health route  │       │ Independent health route  │
    └───────────────────────────┘       └───────────────────────────┘
                 ▲                                   ▲
                 │                                   │
                 └─────────────────┬─────────────────┘
                                   │
                                   ▼
    ┌─────────────────────────────────────────────────────────────┐
    │                 Deployment Control Layer                    │
    │                                                             │
    │  switch-deployment.sh                                       │
    │  - Validates candidate health                               │
    │  - Confirms expected application version                    │
    │  - Uses an exclusive deployment lock                        │
    │  - Generates candidate Nginx configuration                   │
    │  - Backs up the active configuration                        │
    │  - Runs nginx -t before reload                              │
    │  - Reloads Nginx without stopping active connections        │
    │  - Polls until the target version becomes active            │
    │  - Rolls back automatically on validation failure           │
    │                                                             │
    │  monitor-availability.sh                                    │
    │  - Sends continuous HTTP requests during switching          │
    │  - Records response status and timestamps                   │
    │  - Fails when any request becomes unavailable               │
    └─────────────────────────────────────────────────────────────┘

## Deployment Strategy

Blue-green delivery maintains two independent application environments:

- Blue represents the currently stable production version.
- Green represents the candidate version being prepared for release.
- Both environments run simultaneously.
- The candidate is tested directly before receiving production traffic.
- Nginx changes the active upstream through a graceful reload.
- The previous environment remains available for immediate rollback.

This avoids rebuilding or modifying the currently active environment during a release.

## Prerequisites

- Ubuntu or another supported Linux distribution
- Docker Engine
- Docker daemon running
- User access to the Docker socket
- Nginx
- Bash
- curl
- flock
- grep
- sed
- awk
- Git
- sudo privileges
- Internet access for pulling container images

## Installation

Install Nginx:

    sudo apt update
    sudo apt install -y nginx

Enable and start Nginx:

    sudo systemctl enable --now nginx

Verify the Nginx configuration:

    sudo nginx -t
    systemctl is-active nginx

When Docker is not already installed, install and enable it using the appropriate package source for the operating system.

Grant the current user Docker socket access:

    sudo usermod -aG docker "$USER"

Reconnect to the shell after changing group membership.

Verify Docker:

    docker --version
    docker info

## Directory Structure

    docker-nginx-blue-green-delivery/
    ├── blue/
    │   ├── .dockerignore
    │   ├── Dockerfile
    │   ├── default.conf
    │   ├── health
    │   └── index.html
    ├── green/
    │   ├── .dockerignore
    │   ├── Dockerfile
    │   ├── default.conf
    │   ├── health
    │   └── index.html
    ├── monitor-availability.sh
    ├── nginx-config-template.conf
    ├── switch-deployment.sh
    └── README.md

## Application Environments

### Blue Version

The Blue environment provides:

- Application version 1.0
- Docker image 
