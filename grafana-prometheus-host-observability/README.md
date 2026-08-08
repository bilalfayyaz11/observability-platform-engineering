# Linux Host Observability with Grafana and Prometheus

## What This Does

This implementation provides a reproducible Linux host observability stack using Grafana, Prometheus, and Node Exporter.

Node Exporter exposes operating-system metrics, Prometheus collects and stores those metrics as time-series data, and Grafana provides dashboards for infrastructure health and performance analysis.

Grafana configuration is provisioned from files rather than manual UI operations, making the monitoring configuration repeatable, version-controlled, and suitable for infrastructure automation workflows.

The resulting stack provides visibility into CPU utilization, memory consumption, system load, Prometheus target health, and underlying Linux system metrics.

## Architecture

    ┌──────────────────────────────────────────────┐
    │               Linux Host                     │
    │                                              │
    │   ┌──────────────────────────────────────┐   │
    │   │           Node Exporter              │   │
    │   │                                      │   │
    │   │ Linux CPU / Memory / Load / OS       │   │
    │   │ Metrics Endpoint :9100               │   │
    │   └─────────────────┬────────────────────┘   │
    │                     │                        │
    │                     │ Scrape                 │
    │                     ▼                        │
    │   ┌──────────────────────────────────────┐   │
    │   │            Prometheus                │   │
    │   │                                      │   │
    │   │ Metrics Collection                   │   │
    │   │ Time-Series Storage                  │   │
    │   │ PromQL Query Engine                  │   │
    │   │ Endpoint :9090                       │   │
    │   └─────────────────┬────────────────────┘   │
    │                     │                        │
    │                     │ Prometheus Data Source │
    │                     ▼                        │
    │   ┌──────────────────────────────────────┐   │
    │   │              Grafana                 │   │
    │   │                                      │   │
    │   │ Provisioned Data Source              │   │
    │   │ Provisioned Dashboard                │   │
    │   │ Visualization Endpoint :3000         │   │
    │   └──────────────────────────────────────┘   │
    │                                              │
    └──────────────────────────────────────────────┘

## Prerequisites

- Ubuntu or another systemd-based Linux distribution
- sudo privileges
- Internet access for package and binary installation
- curl
- wget
- GnuPG
- jq
- systemd
- ss/iproute2
- Grafana
- Prometheus
- Promtool
- Prometheus Node Exporter

Required network ports:

- `3000` — Grafana
- `9090` — Prometheus
- `9100` — Node Exporter

## Setup & Installation

Grafana should be installed through its official APT repository using a dedicated repository keyring.

Example repository configuration:

    sudo mkdir -p /etc/apt/keyrings

    sudo wget -q -O /etc/apt/keyrings/grafana.asc \
      https://apt.grafana.com/gpg-full.key

    sudo chmod 644 /etc/apt/keyrings/grafana.asc

    echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" \
      | sudo tee /etc/apt/sources.list.d/grafana.list

    sudo apt update
    sudo apt install -y grafana

Prometheus and Node Exporter binaries should be installed under:

    /usr/local/bin/prometheus
    /usr/local/bin/promtool
    /usr/local/bin/node_exporter

Dedicated service accounts are used:

    prometheus
    node_exporter

Prometheus configuration is stored under:

    /etc/prometheus/prometheus.yml

Persistent Prometheus time-series data is stored under:

    /var/lib/prometheus

## How to Reproduce

### 1. Configure Prometheus

Create `/etc/prometheus/prometheus.yml`:

    global:
      scrape_interval: 15s

    scrape_configs:
      - job_name: "prometheus"
        static_configs:
          - targets: ["127.0.0.1:9090"]

      - job_name: "node"
        static_configs:
          - targets: ["127.0.0.1:9100"]

Validate the configuration:

    promtool check config /etc/prometheus/prometheus.yml

### 2. Configure Prometheus as a systemd service

Use the included:

    prometheus.service

The service runs Prometheus with:

    --config.file=/etc/prometheus/prometheus.yml
    --storage.tsdb.path=/var/lib/prometheus

### 3. Configure Node Exporter

Use the included:

    node_exporter.service

Node Exporter exposes Linux host metrics on:

    http://127.0.0.1:9100/metrics

### 4. Start the metric services

    sudo systemctl daemon-reload
    sudo systemctl enable --now prometheus
    sudo systemctl enable --now node_exporter

Validate:

    systemctl is-active prometheus
    systemctl is-active node_exporter

### 5. Provision the Grafana data source

Place:

    prometheus.yaml

under:

    /etc/grafana/provisioning/datasources/

The data source connects Grafana to:

    http://127.0.0.1:9090

with a stable UID:

    prometheus

### 6. Provision the Grafana dashboard

Place:

    system-monitoring.yaml

under:

    /etc/grafana/provisioning/dashboards/

Place:

    system-monitoring.json

under:

    /var/lib/grafana/dashboards/

Restart Grafana:

    sudo systemctl restart grafana-server

### 7. Validate the complete metric path

Check Prometheus health:

    curl http://127.0.0.1:9090/-/healthy

Inspect scrape targets:

    curl -s http://127.0.0.1:9090/api/v1/targets | jq .

Query target availability:

    curl -sG http://127.0.0.1:9090/api/v1/query \
      --data-urlencode 'query=up' | jq .

Check Grafana health:

    curl -s http://127.0.0.1:3000/api/health | jq .

## Tools Used

- Ubuntu Linux
- Grafana
- Prometheus
- PromQL
- Promtool
- Prometheus Node Exporter
- systemd
- curl
- wget
- jq
- GNU Privacy Guard
- APT
- Linux networking utilities

## Key Skills Demonstrated

- Building an infrastructure observability stack from independent services
- Operating Prometheus time-series metric collection
- Exporting Linux host telemetry through Node Exporter
- Writing Prometheus scrape configurations
- Validating Prometheus configuration with Promtool
- Writing and operating systemd services
- Provisioning Grafana data sources as configuration
- Provisioning Grafana dashboards as code
- Writing PromQL queries for infrastructure utilization
- Automating monitoring configuration without dependence on manual UI setup
- Validating service health and TCP listeners
- Troubleshooting Linux service and configuration failures

## Real-World Use Case

This architecture can serve as the host-observability layer for application servers, inference hosts, internal infrastructure, CI/CD workers, container hosts, or AI platform nodes. Operations teams can use Prometheus to collect telemetry continuously while Grafana provides a centralized visualization layer for detecting CPU saturation, memory pressure, abnormal system load, failed scrape targets, and infrastructure degradation.

## Lessons Learned

- Monitoring components should be independently health-checked before validating the complete telemetry pipeline.
- Grafana provisioning removes manual dashboard and data-source configuration and makes observability configuration reproducible.
- Stable Grafana data-source UIDs prevent dashboards from depending on dynamically generated internal identifiers.
- PromQL should represent operational signals rather than merely displaying raw metric series.
- Configuration edits should target specific INI sections because generic substitutions can unintentionally modify unrelated Grafana settings.

## Troubleshooting Log

### Deprecated Grafana repository configuration

Legacy installations used `apt-key` and the older Grafana package repository configuration.

The installation was updated to use a dedicated APT keyring under:

    /etc/apt/keyrings/grafana.asc

and the current Grafana APT repository.

### Outdated Prometheus and Node Exporter releases

Older fixed releases were replaced with current binaries during implementation.

Installed components:

    Prometheus 3.13.2
    Node Exporter 1.11.1

### Grafana CLI deprecation

Direct use of:

    grafana-server

reported a deprecation warning.

Modern direct CLI invocation uses:

    grafana server

The systemd service remains:

    grafana-server.service

### Grafana configuration substitution issue

A broad substitution targeting generic `enabled` parameters affected multiple independent Grafana configuration sections.

The configuration was restored from backup and section-aware modifications were applied only to:

    [users]
    [auth.anonymous]
    [auth.basic]

### Manual Grafana configuration removed

Prometheus data-source creation and dashboard creation were converted from browser-driven configuration to native Grafana provisioning files.

This makes the observability stack deterministic, repeatable, and compatible with version-controlled infrastructure workflows.
