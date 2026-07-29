# Prometheus Host and Application Monitoring

## What This Does

This implementation provides a complete Prometheus monitoring foundation for Linux infrastructure and custom application telemetry.

Prometheus collects operational metrics from three targets: its own internal endpoint, Node Exporter for Linux system metrics, and a Python application exposing custom business-level metrics. All three components run as managed systemd services with automatic startup, failure recovery, controlled permissions, and centralized service logging.

The implementation demonstrates how platform, AIOps, DevSecOps, and application engineering teams can combine infrastructure metrics and application metrics within one time-series monitoring platform.

## Architecture

    +------------------------------------------------------+
    | Engineer / Operations Team                           |
    | Prometheus Web UI and PromQL API                     |
    | http://SERVER-IP:9090                                |
    +--------------------------+---------------------------+
                               |
                               v
    +------------------------------------------------------+
    | Prometheus Server                                    |
    |                                                      |
    | Configuration: /etc/prometheus/prometheus.yml        |
    | Storage: /var/lib/prometheus                         |
    | Scrape Interval: 10 seconds                          |
    | Retention Period: 15 days                            |
    +-----------+------------------+-----------------------+
                |                  |                  |
                | Scrape :9090     | Scrape :9100    | Scrape :8000
                v                  v                  v
    +-------------------+  +-------------------+  +----------------------+
    | Prometheus        |  | Node Exporter     |  | Python Metrics App   |
    | Self-Monitoring   |  |                   |  |                      |
    |                   |  | CPU               |  | app_requests_total   |
    | Runtime metrics   |  | Memory            |  | app_temperature      |
    | Storage metrics   |  | Filesystems       |  |                      |
    | Scrape health     |  | Disk              |  | prometheus_client    |
    | Query metrics     |  | Network           |  |                      |
    +-------------------+  +-------------------+  +----------------------+
                |                  |                  |
                +------------------+------------------+
                                   |
                                   v
    +------------------------------------------------------+
    | Prometheus Time-Series Database                      |
    | Metrics queried through PromQL                       |
    +------------------------------------------------------+

## Components

### Prometheus

Prometheus runs as the central metrics collection and query service on port 9090.

It scrapes configured targets every 10 seconds, stores collected samples under `/var/lib/prometheus`, and provides its web interface and HTTP API for target inspection and PromQL queries.

### Node Exporter

Node Exporter exposes Linux host metrics on `127.0.0.1:9100`.

The exporter provides operating-system telemetry including CPU activity, memory availability, filesystem capacity, disk operations, network statistics, load averages, and kernel information.

The endpoint listens only on localhost because the Prometheus server runs on the same machine and external access is not required.

### Python Metrics Application

The Python application exposes custom Prometheus metrics on `127.0.0.1:8000`.

The application provides:

- `app_requests_total` — Counter representing the total number of simulated requests
- `app_temperature` — Gauge representing a simulated temperature value between 20 and 30

The request counter increments every five seconds while the temperature gauge receives a new randomized value.

### systemd Services

Each component is managed through systemd:

- `prometheus.service`
- `node_exporter.service`
- `prometheus-sample-app.service`

Systemd provides automatic startup, process supervision, restart handling, consistent logs, and controlled runtime permissions.

## Repository Structure

    prometheus-host-application-monitoring/
    |
    +-- README.md
    +-- .gitignore
    |
    +-- application/
    |   +-- sample_app.py
    |
    +-- configuration/
    |   +-- prometheus.yml
    |
    +-- systemd/
        +-- prometheus.service
        +-- node_exporter.service
        +-- prometheus-sample-app.service

## Prerequisites

- Ubuntu 24.04 or another modern systemd-based Linux distribution
- x86_64 processor architecture
- Sudo privileges
- Internet connectivity
- Python 3
- Python virtual environment support
- curl
- wget
- tar
- systemd
- Prometheus
- Promtool
- Node Exporter

## Versions Used

- Ubuntu 24.04.3 LTS
- Python 3.12.3
- Prometheus 3.13.0
- Node Exporter 1.11.1
- prometheus-client Python library

## Setup & Installation

Update the package index and install the required operating-system packages:

    sudo apt-get update

    sudo apt-get install -y \
      ca-certificates \
      curl \
      wget \
      tar \
      python3-pip \
      python3-venv

Create the Prometheus system account:

    sudo useradd \
      --system \
      --no-create-home \
      --shell /usr/sbin/nologin \
      prometheus

Create the Prometheus configuration and storage directories:

    sudo mkdir -p \
      /etc/prometheus \
      /var/lib/prometheus

Set the required ownership:

    sudo chown -R prometheus:prometheus \
      /etc/prometheus \
      /var/lib/prometheus

Install the Prometheus binaries:

    sudo install \
      -o root \
      -g root \
      -m 0755 \
      prometheus \
      /usr/local/bin/prometheus

    sudo install \
      -o root \
      -g root \
      -m 0755 \
      promtool \
      /usr/local/bin/promtool

Install Node Exporter:

    sudo install \
      -o root \
      -g root \
      -m 0755 \
      node_exporter \
      /usr/local/bin/node_exporter

Root ownership prevents monitoring service accounts from replacing their own executable binaries.

## Python Application Setup

Create the application working directory:

    mkdir -p ~/prometheus-custom-metrics

    cd ~/prometheus-custom-metrics

Create an isolated Python environment:

    python3 -m venv .venv

Activate the environment:

    source .venv/bin/activate

Upgrade pip:

    python -m pip install --upgrade pip

Install the Prometheus Python client:

    python -m pip install prometheus-client

Verify the application syntax:

    python -m py_compile sample_app.py

## Prometheus Configuration

The Prometheus configuration defines three static scrape targets.

    global:
      scrape_interval: 10s
      evaluation_interval: 15s

    scrape_configs:
      - job_name: prometheus
        static_configs:
          - targets:
              - localhost:9090
            labels:
              environment: lab

      - job_name: node_exporter
        static_configs:
          - targets:
              - localhost:9100
            labels:
              job_type: system_metrics

      - job_name: sample_app
        static_configs:
          - targets:
              - localhost:8000
            labels:
              application: sample_metrics
              environment: lab

Copy the configuration into the Prometheus configuration directory:

    sudo cp configuration/prometheus.yml \
      /etc/prometheus/prometheus.yml

Set ownership and permissions:

    sudo chown prometheus:prometheus \
      /etc/prometheus/prometheus.yml

    sudo chmod 0644 \
      /etc/prometheus/prometheus.yml

Validate the configuration before starting or reloading Prometheus:

    sudo promtool check config \
      /etc/prometheus/prometheus.yml

Expected result:

    SUCCESS: /etc/prometheus/prometheus.yml is valid prometheus config file syntax

## systemd Service Deployment

Copy the Prometheus service definition:

    sudo cp systemd/prometheus.service \
      /etc/systemd/system/prometheus.service

Copy the Node Exporter service definition:

    sudo cp systemd/node_exporter.service \
      /etc/systemd/system/node_exporter.service

Copy the Python application service definition:

    sudo cp systemd/prometheus-sample-app.service \
      /etc/systemd/system/prometheus-sample-app.service

Reload systemd:

    sudo systemctl daemon-reload

Validate the service definitions:

    sudo systemd-analyze verify \
      /etc/systemd/system/prometheus.service \
      /etc/systemd/system/node_exporter.service \
      /etc/systemd/system/prometheus-sample-app.service

Enable and start Node Exporter:

    sudo systemctl enable --now node_exporter

Enable and start the Python metrics application:

    sudo systemctl enable --now prometheus-sample-app

Enable and start Prometheus:

    sudo systemctl enable --now prometheus

## How to Reproduce

Clone the repository:

    git clone https://github.com/bilalfayyaz11/observability-platform-engineering.git

Enter the implementation directory:

    cd observability-platform-engineering/prometheus-host-application-monitoring

Install the required operating-system dependencies:

    sudo apt-get update

    sudo apt-get install -y \
      ca-certificates \
      curl \
      wget \
      tar \
      python3-pip \
      python3-venv

Install Prometheus and Node Exporter binaries under `/usr/local/bin`.

Create the Prometheus service account:

    sudo useradd \
      --system \
      --no-create-home \
      --shell /usr/sbin/nologin \
      prometheus

Create the configuration and data directories:

    sudo mkdir -p \
      /etc/prometheus \
      /var/lib/prometheus

    sudo chown -R prometheus:prometheus \
      /etc/prometheus \
      /var/lib/prometheus

Create the application directory:

    mkdir -p ~/prometheus-custom-metrics

Copy the application:

    cp application/sample_app.py \
      ~/prometheus-custom-metrics/sample_app.py

Create its virtual environment:

    cd ~/prometheus-custom-metrics

    python3 -m venv .venv

    source .venv/bin/activate

    python -m pip install --upgrade pip

    python -m pip install prometheus-client

Copy the Prometheus configuration:

    sudo cp \
      ~/observability-platform-engineering/prometheus-host-application-monitoring/configuration/prometheus.yml \
      /etc/prometheus/prometheus.yml

Copy the systemd services:

    sudo cp \
      ~/observability-platform-engineering/prometheus-host-application-monitoring/systemd/prometheus.service \
      /etc/systemd/system/prometheus.service

    sudo cp \
      ~/observability-platform-engineering/prometheus-host-application-monitoring/systemd/node_exporter.service \
      /etc/systemd/system/node_exporter.service

    sudo cp \
      ~/observability-platform-engineering/prometheus-host-application-monitoring/systemd/prometheus-sample-app.service \
      /etc/systemd/system/prometheus-sample-app.service

Validate the configuration:

    sudo promtool check config \
      /etc/prometheus/prometheus.yml

Reload systemd and start the services:

    sudo systemctl daemon-reload

    sudo systemctl enable --now node_exporter

    sudo systemctl enable --now prometheus-sample-app

    sudo systemctl enable --now prometheus

## Service Verification

Verify that all services are running:

    sudo systemctl is-active prometheus

    sudo systemctl is-active node_exporter

    sudo systemctl is-active prometheus-sample-app

Each command should return:

    active

Verify that all services start automatically:

    sudo systemctl is-enabled prometheus

    sudo systemctl is-enabled node_exporter

    sudo systemctl is-enabled prometheus-sample-app

Each command should return:

    enabled

Inspect the listening ports:

    sudo ss -lntp | grep -E ':(8000|9090|9100)\b'

Expected listeners:

- Prometheus on port 9090
- Node Exporter on `127.0.0.1:9100`
- Python metrics application on `127.0.0.1:8000`

## Metrics Verification

Verify Prometheus self-metrics:

    curl --fail --silent \
      http://127.0.0.1:9090/metrics \
      | grep '^prometheus_build_info'

Verify Node Exporter metrics:

    curl --fail --silent \
      http://127.0.0.1:9100/metrics \
      | grep '^node_cpu_seconds_total' \
      | head

Verify custom application metrics:

    curl --fail --silent \
      http://127.0.0.1:8000/metrics \
      | grep -E '^(app_requests_total|app_temperature)'

## Target Health Verification

Query all target states through the Prometheus HTTP API:

    curl --fail --silent \
      --get \
      --data-urlencode 'query=up' \
      http://127.0.0.1:9090/api/v1/query \
      | python3 -m json.tool

The following jobs should return a value of `1`:

- `prometheus`
- `node_exporter`
- `sample_app`

A value of `1` confirms that Prometheus is successfully scraping the target.

## PromQL Queries

Check Prometheus self-monitoring:

    up{job="prometheus"}

Check Node Exporter health:

    up{job="node_exporter"}

Check the Python application health:

    up{job="sample_app"}

Query CPU metrics:

    node_cpu_seconds_total

Query the application request counter:

    app_requests_total

Query the application temperature gauge:

    app_temperature

Calculate the application request rate over five minutes:

    rate(app_requests_total{job="sample_app"}[5m])

Because the application increments its counter approximately once every five seconds, the long-term request rate approaches 0.2 requests per second.

## Configuration Reload

Validate the configuration before reloading Prometheus:

    sudo promtool check config \
      /etc/prometheus/prometheus.yml

Reload Prometheus without restarting the service:

    sudo systemctl reload prometheus

Verify that Prometheus remains active:

    sudo systemctl is-active prometheus

The service supports reload through:

    ExecReload=/bin/kill -HUP $MAINPID

This sends a SIGHUP signal to Prometheus and causes it to reload its configuration safely.

## Tools Used

- Prometheus
- Promtool
- Node Exporter
- Python 3
- prometheus-client
- PromQL
- YAML
- systemd
- Linux
- Bash
- curl
- wget
- Git

## Key Skills Demonstrated

- Prometheus installation and configuration
- Linux infrastructure monitoring
- Custom application instrumentation
- Prometheus Python client integration
- Time-series metrics collection
- PromQL query construction
- Static target configuration
- Target health validation
- systemd service engineering
- Service account isolation
- Configuration validation with Promtool
- Process supervision
- Automatic failure recovery
- Network listener verification
- Monitoring endpoint troubleshooting
- Secure local exporter exposure
- Application and infrastructure observability
- AIOps monitoring foundations

## Real-World Use Case

Platform engineering and operations teams need visibility into both infrastructure health and application behavior. Host metrics alone can show CPU, memory, disk, and network conditions, but they cannot explain how an application is behaving from a business or workload perspective.

This architecture combines Linux host telemetry with custom application metrics inside one Prometheus monitoring system. In a production organization, it could monitor API services, background workers, data-processing systems, CI/CD infrastructure, internal platforms, or machine-learning inference services.

For an Applied AI platform, equivalent custom metrics could represent model inference requests, response latency, failed predictions, queue depth, token consumption, accelerator utilization, model version usage, or data-drift indicators.

The collected metrics could later be connected to Grafana dashboards, Alertmanager notifications, service discovery, recording rules, Kubernetes workloads, or long-term metrics storage.

## Security Decisions

- Prometheus runs under a dedicated non-login service account.
- Monitoring binaries are owned by root.
- Node Exporter listens only on localhost.
- The Python metrics application listens only on localhost.
- Service processes cannot gain additional privileges.
- Temporary directories are isolated through systemd.
- Filesystem access is restricted through service hardening.
- Configuration is validated before reload.
- Runtime metric data is excluded from source control.
- Python dependencies are installed inside a virtual environment.
- Prometheus is the only monitoring component exposed externally.

In a production environment, access to port 9090 should be restricted through private networking, firewall policies, authentication, a reverse proxy, or a secured monitoring network.

## Lessons Learned

- Prometheus configuration should always be validated before a service reload or restart.
- Infrastructure metrics and application metrics provide more value when monitored together.
- Exporter endpoints should not be exposed publicly unless remote access is required.
- Service executables should remain root-owned so runtime accounts cannot modify them.
- systemd provides more reliable application management than running processes with a shell background operator.
- Python virtual environments prevent conflicts with Ubuntu's system-managed Python installation.
- Prometheus counters are suitable for continuously increasing event totals.
- Gauges are suitable for values that can increase or decrease.
- Target health should be checked through direct endpoints and PromQL.
- Versioned installations simplify future upgrades and rollback.

## Troubleshooting Log

Issue:
The original Prometheus version was outdated.

Resolution:
Prometheus 3.13.0 was installed instead of Prometheus 2.47.0.

Issue:
The original Node Exporter version was outdated.

Resolution:
Node Exporter 1.11.1 was installed instead of Node Exporter 1.6.1.

Issue:
The supplied Prometheus service did not define a configuration reload operation.

Resolution:
The following directive was added:

    ExecReload=/bin/kill -HUP $MAINPID

This allows `systemctl reload prometheus` to reload the configuration safely.

Issue:
The original Python application was started with a shell background operator.

Resolution:
The application was converted into a systemd service with restart handling, startup enablement, and centralized logs.

Issue:
Ubuntu 24.04 protects the system-managed Python environment.

Resolution:
A dedicated Python virtual environment was created before installing `prometheus-client`.

Issue:
Monitoring service accounts originally owned executable binaries.

Resolution:
Prometheus, Promtool, and Node Exporter binaries were installed with root ownership and executable permissions.

Issue:
Prometheus or Node Exporter fails to start.

Resolution:
Inspect the relevant service:

    sudo systemctl status prometheus --no-pager

    sudo systemctl status node_exporter --no-pager

Inspect recent logs:

    sudo journalctl -u prometheus -n 50 --no-pager

    sudo journalctl -u node_exporter -n 50 --no-pager

Issue:
The Python metrics application fails to start.

Resolution:
Inspect its status and logs:

    sudo systemctl status prometheus-sample-app --no-pager

    sudo journalctl \
      -u prometheus-sample-app \
      -n 50 \
      --no-pager

Verify that the Python dependency is installed:

    ~/prometheus-custom-metrics/.venv/bin/python \
      -m pip show prometheus-client

Check the application syntax:

    ~/prometheus-custom-metrics/.venv/bin/python \
      -m py_compile \
      ~/prometheus-custom-metrics/sample_app.py

Issue:
A Prometheus target appears as down.

Resolution:
Verify all listening ports:

    sudo ss -lntp | grep -E ':(8000|9090|9100)\b'

Test each metrics endpoint:

    curl http://127.0.0.1:9090/metrics

    curl http://127.0.0.1:9100/metrics

    curl http://127.0.0.1:8000/metrics

Verify the configured targets:

    sudo cat /etc/prometheus/prometheus.yml

Wait for at least one scrape interval and query:

    up

Issue:
Prometheus rejects the configuration.

Resolution:
Run:

    sudo promtool check config \
      /etc/prometheus/prometheus.yml

Correct YAML indentation or unsupported fields before attempting a reload.

Issue:
Port 9090 cannot be accessed remotely.

Resolution:
Confirm that Prometheus is listening:

    sudo ss -lntp | grep ':9090'

Check the local endpoint:

    curl http://127.0.0.1:9090/-/healthy

Review the cloud security group, network ACL, host firewall, and routing configuration before exposing the service.
