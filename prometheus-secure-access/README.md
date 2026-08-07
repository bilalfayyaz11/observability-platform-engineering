# Secure Prometheus Access with TLS and Role-Oriented Authorization

## What This Does

This implementation hardens a standalone Prometheus monitoring environment by placing authenticated HTTPS access in front of the monitoring backend while preventing direct external access to Prometheus and Node Exporter.

Prometheus runs with TLS enabled and listens only on the loopback interface. Nginx acts as the externally accessible security gateway, providing TLS termination, HTTP Basic Authentication, role-oriented endpoint authorization, HTTP-to-HTTPS redirection, security headers, and verified encrypted communication with the Prometheus backend.

The environment separates administrative, query, and metrics access across admin, viewer, and readonly identities while validating both permitted and denied authorization paths.

## Architecture

    ┌───────────────────────────────────────────────────────────────┐
    │                       External Client                         │
    │                                                               │
    │        HTTPS :443                         HTTP :80             │
    │            │                                  │               │
    │            │                                  └──── Redirect  │
    │            ▼                                                  │
    │   ┌───────────────────────────────────────────────────────┐   │
    │   │                    Nginx Gateway                      │   │
    │   │                                                       │   │
    │   │  TLS 1.2 / TLS 1.3                                   │   │
    │   │  Basic Authentication                                │   │
    │   │  Security Headers                                    │   │
    │   │  Backend Certificate Verification                    │   │
    │   │                                                       │   │
    │   │  ┌────────────┐ ┌────────────┐ ┌─────────────────┐   │   │
    │   │  │   Admin    │ │   Viewer   │ │    Readonly     │   │   │
    │   │  │            │ │            │ │                 │   │   │
    │   │  │ Web UI     │ │ PromQL     │ │ /metrics        │   │   │
    │   │  │ Admin API  │ │ Query API  │ │ Status API      │   │   │
    │   │  └────────────┘ └────────────┘ └─────────────────┘   │   │
    │   └───────────────────────┬───────────────────────────────┘   │
    │                           │                                   │
    │                  Verified HTTPS                              │
    │                           │                                   │
    │                           ▼                                   │
    │              ┌────────────────────────┐                       │
    │              │      Prometheus        │                       │
    │              │   127.0.0.1:9090      │                       │
    │              │                        │                       │
    │              │ TLS-enabled web API    │                       │
    │              │ TSDB + PromQL engine   │                       │
    │              └────────────┬───────────┘                       │
    │                           │                                   │
    │                      HTTP scrape                              │
    │                           │                                   │
    │                           ▼                                   │
    │              ┌────────────────────────┐                       │
    │              │     Node Exporter      │                       │
    │              │   127.0.0.1:9100      │                       │
    │              │                        │                       │
    │              │ Host system metrics    │                       │
    │              └────────────────────────┘                       │
    │                                                               │
    │                 Linux / systemd Host                           │
    └───────────────────────────────────────────────────────────────┘


## Prerequisites

- Ubuntu Linux with systemd
- sudo privileges
- x86_64 architecture
- Git
- curl
- wget
- tar
- OpenSSL
- Nginx
- apache2-utils for htpasswd
- Prometheus
- promtool
- Node Exporter
- TCP port 80 available
- TCP port 443 available
- TCP port 9090 available internally
- TCP port 9100 available internally


## Setup & Installation

Create non-interactive service identities:

    sudo useradd \
      --system \
      --no-create-home \
      --shell /usr/sbin/nologin \
      prometheus

    sudo useradd \
      --system \
      --no-create-home \
      --shell /usr/sbin/nologin \
      node_exporter

Create the required directories:

    sudo mkdir -p /etc/prometheus
    sudo mkdir -p /var/lib/prometheus
    sudo mkdir -p /etc/ssl/prometheus

Install Prometheus and promtool from the official Prometheus release channel:

    sudo install -m 0755 prometheus /usr/local/bin/prometheus
    sudo install -m 0755 promtool /usr/local/bin/promtool

Install Node Exporter:

    sudo install \
      -o node_exporter \
      -g node_exporter \
      -m 0755 \
      node_exporter \
      /usr/local/bin/node_exporter

Install Nginx and Basic Authentication tooling:

    sudo apt-get update
    sudo apt-get install -y nginx apache2-utils


## TLS Certificate Configuration

This implementation uses a self-signed certificate for local validation.

The certificate contains Subject Alternative Names for:

    DNS:localhost
    IP:127.0.0.1

Generate the private key and certificate using:

    openssl-prometheus.cnf

Store the resulting files at:

    /etc/ssl/prometheus/prometheus.crt
    /etc/ssl/prometheus/prometheus.key

The private key must remain restricted:

    sudo chmod 600 /etc/ssl/prometheus/prometheus.key

The certificate may be publicly readable:

    sudo chmod 644 /etc/ssl/prometheus/prometheus.crt


## Prometheus TLS Configuration

Prometheus web-server TLS is configured separately from the primary scrape configuration.

The web configuration is stored at:

    /etc/prometheus/web.yml

Prometheus starts with:

    --web.config.file=/etc/prometheus/web.yml

The monitoring backend binds only to:

    127.0.0.1:9090

This prevents clients from bypassing the Nginx authentication and authorization layer.


## Authentication and Authorization

Three identities are separated by Nginx authentication files:

    admin
    viewer
    readonly

Role-oriented access is enforced through explicit Nginx locations.

### Admin

Administrative users can access:

- Prometheus web interface
- Administrative API paths
- Write-oriented administrative endpoints

### Viewer

Viewer users can access:

- PromQL instant queries
- Range queries
- Series queries
- Query-related interface paths

### Readonly

Readonly users can access:

- Prometheus metrics endpoint
- Status-oriented endpoints

Requests using credentials from one role against another role's protected endpoint are rejected.


## Reverse Proxy Security

Nginx is the only externally exposed application component.

Public listeners:

    0.0.0.0:80
    0.0.0.0:443

Internal listeners:

    127.0.0.1:9090
    127.0.0.1:9100

HTTP connections are redirected to HTTPS.

Nginx communicates with Prometheus through HTTPS and validates the backend certificate using:

    proxy_ssl_verify on;
    proxy_ssl_trusted_certificate /etc/ssl/prometheus/prometheus.crt;
    proxy_ssl_name localhost;

This prevents the reverse proxy from accepting an unverified backend TLS connection.


## Security Headers

The Nginx gateway adds defensive response headers including:

    X-Content-Type-Options: nosniff
    X-Frame-Options: SAMEORIGIN
    Referrer-Policy: no-referrer


## How to Reproduce

Install the configuration files:

    sudo cp prometheus.yml /etc/prometheus/prometheus.yml
    sudo cp web.yml /etc/prometheus/web.yml

Install service definitions:

    sudo cp prometheus.service /etc/systemd/system/prometheus.service
    sudo cp node_exporter.service /etc/systemd/system/node_exporter.service

Install the Nginx configuration:

    sudo cp nginx-prometheus.conf /etc/nginx/sites-available/prometheus

    sudo ln -sfn \
      /etc/nginx/sites-available/prometheus \
      /etc/nginx/sites-enabled/prometheus

Validate Prometheus:

    promtool check config /etc/prometheus/prometheus.yml

Validate Nginx:

    sudo nginx -t

Reload systemd:

    sudo systemctl daemon-reload

Start services:

    sudo systemctl enable --now prometheus
    sudo systemctl enable --now node_exporter
    sudo systemctl enable nginx
    sudo systemctl restart nginx

Verify Prometheus health directly:

    curl \
      --cacert /etc/ssl/prometheus/prometheus.crt \
      https://localhost:9090/-/healthy

Verify public authentication:

    curl -k -I https://localhost/

An unauthenticated request should return:

    HTTP 401

Verify HTTP redirection:

    curl -I http://localhost/

Verify backend isolation:

    sudo ss -lntp | grep -E ':(80|443|9090|9100)\b'

Prometheus and Node Exporter should remain bound to loopback.


## Validation

Run:

    ./security_test.sh

The validation checks:

- Prometheus backend HTTPS
- Authentication enforcement
- Admin web access
- Viewer PromQL access
- Readonly metrics access
- Viewer denial from administrative paths
- Readonly denial from query paths
- HTTP-to-HTTPS redirection
- Certificate validation
- TLS protocol support
- Prometheus network isolation
- Node Exporter network isolation
- Prometheus service health
- Nginx service health
- Node Exporter service health


## Tools Used

- Prometheus
- promtool
- Node Exporter
- Nginx
- OpenSSL
- HTTP Basic Authentication
- htpasswd
- systemd
- Linux
- Bash
- curl
- Git


## Key Skills Demonstrated

- Prometheus security hardening
- TLS certificate generation and management
- Subject Alternative Name configuration
- Secure reverse-proxy architecture
- HTTP Basic Authentication
- Endpoint-level authorization
- Role-oriented access separation
- Backend TLS certificate validation
- Monitoring service network isolation
- HTTP-to-HTTPS redirection
- Security response headers
- Negative authorization testing
- systemd service hardening
- Linux service-account management
- Secure observability architecture
- Automated security validation


## Real-World Use Case

Monitoring platforms often expose infrastructure metadata, application topology, runtime behavior, resource consumption, internal service names, and operational status. Exposing that information without authentication or transport security can provide attackers with valuable reconnaissance data. A secure reverse-proxy architecture allows organizations to isolate Prometheus from direct network access while enforcing encrypted transport, authenticated access, endpoint-specific authorization, and centralized access controls through a hardened gateway.


## Lessons Learned

- Prometheus should not be directly exposed when a reverse proxy is responsible for authentication and authorization.
- TLS encryption is significantly stronger when both client-facing and backend connections are verified rather than merely encrypted.
- Service identities should use non-interactive system accounts with minimum filesystem permissions.
- Authorization testing must include negative scenarios to prove users cannot reach endpoints outside their intended access scope.
- Backend exporters should remain isolated from public network interfaces whenever external access is unnecessary.
- Self-signed certificates are useful for controlled validation environments, while production deployments should use certificates issued by an appropriate trusted CA.


## Troubleshooting Log

### Outdated Prometheus Release

The supplied installation path referenced an older Prometheus 2.x binary.

The environment was updated to a current Prometheus 3.x release from the official release channel.


### Outdated Node Exporter Release

The supplied Node Exporter binary was several release generations behind.

A current Node Exporter release was used instead.


### Incorrect Prometheus TLS Placement

TLS web-server configuration was originally placed in the primary Prometheus configuration.

Prometheus web security was moved into:

    /etc/prometheus/web.yml

and loaded with:

    --web.config.file=/etc/prometheus/web.yml


### Certificate Subject Alternative Names

The original certificate design relied primarily on:

    CN=localhost

The certificate was modernized to include:

    DNS:localhost
    IP:127.0.0.1


### TLS Directory Permission Failure

Certificate verification initially failed because the invoking user could not traverse the protected TLS directory.

Directory ownership and permissions were corrected while preserving private-key confidentiality.


### Interactive Shell Termination

A verification command was executed under shell error-exit behavior.

When certificate verification returned a permission error, the interactive SSH session terminated.

Subsequent operational commands avoided global interactive error-exit behavior where failure could unnecessarily terminate the remote shell.


### Prometheus Exposure

The original listener configuration exposed Prometheus through:

    0.0.0.0:9090

The hardened deployment binds it to:

    127.0.0.1:9090

ensuring external requests must pass through Nginx.


### Backend TLS Verification

Encrypted Nginx-to-Prometheus communication alone does not verify backend identity.

Backend certificate validation was explicitly enabled using:

    proxy_ssl_verify on;


### Nginx HTTP/2 Syntax

Older Nginx configurations commonly used:

    listen 443 ssl http2;

The configuration uses the modern separated form:

    listen 443 ssl;
    http2 on;


### Authentication Validation

Searching an HTTP response body for the text "401" does not reliably prove authentication enforcement.

Validation was changed to inspect HTTP status codes directly.


### Certificate Verification

Testing specifically for a self-signed verification error does not prove a valid trust relationship.

The generated certificate was explicitly supplied as a trusted CA during verification and validated successfully.


### Authorization Terminology

The access model implemented here is role-oriented path authorization enforced by Nginx.

It should not be confused with a native Prometheus RBAC subsystem.
