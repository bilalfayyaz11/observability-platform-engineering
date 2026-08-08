# Linux Infrastructure Observability Dashboard

## What This Does

This implementation provides a reproducible Linux infrastructure monitoring stack using Grafana, Prometheus, and Node Exporter.

Node Exporter exposes operating-system telemetry, Prometheus collects and queries the resulting time-series metrics, and Grafana provides a centralized operational dashboard covering CPU utilization, memory pressure, filesystem consumption, network throughput, system load, running processes, and host information.

The Grafana data source and dashboard are provisioned from configuration files instead of being created manually through the browser. This makes the monitoring environment deterministic, repeatable, version-controlled, and suitable for infrastructure automation workflows.

The dashboard also includes dynamic server filtering, a one-hour default observation window, and automatic 30-second refresh for near-real-time infrastructure visibility.

## Architecture

    ┌──────────────────────────────────────────────────────────┐
    │                     Linux Host                           │
    │                                                          │
    │   ┌──────────────────────────────────────────────────┐   │
    │   │                Node Exporter                     │   │
    │   │                                                  │   │
    │   │ CPU                                              │   │
    │   │ Memory                                           │   │
    │   │ Filesystem                                       │   │
    │   │ Network                                          │   │
    │   │ Load                                             │   │
    │   │ Process and OS Metrics                           │   │
    │   │                                                  │   │
    │   │ Endpoint: :9100                                  │   │
    │   └──────────────────────┬───────────────────────────┘   │
    │                          │                               │
    │                          │ Metrics Scrape                │
    │                          ▼                               │
    │   ┌──────────────────────────────────────────────────┐   │
    │   │                  Prometheus                      │   │
    │   │                                                  │   │
    │   │ Metric Collection                               │   │
    │   │ Time-Series Storage                             │   │
    │   │ PromQL Query Engine                             │   │
    │   │ Target Health                                   │   │
    │   │                                                  │   │
    │   │ Endpoint: :9090                                  │   │
    │   └──────────────────────┬───────────────────────────┘   │
    │                          │                               │
    │                          │ PromQL                        │
    │                          ▼                               │
    │   ┌──────────────────────────────────────────────────┐   │
    │   │                    Grafana                       │   │
    │   │                                                  │   │
    │   │ Provisioned Prometheus Data Source              │   │
    │   │ Dashboard-as-Code                               │   │
    │   │ Dynamic Server Filtering                       │   │
    │   │ 30-Second Refresh                              │   │
    │   │                                                  │   │
    │   │ Endpoint: :3000                                  │   │
    │   └──────────────────────────────────────────────────┘   │
    │                                                          │
    └──────────────────────────────────────────────────────────┘

## Prerequisites

- Ubuntu or another systemd-based Linux distribution
- sudo privileges
- Internet connectivity
- curl
- wget
- GnuPG
- jq
- systemd
- Linux networking utilities
- Grafana
- Prometheus
- Promtool
- Prometheus Node Exporter

Required service ports:

- `3000` — Grafana
- `9090` — Prometheus
- `9100` — Node Exporter

## Setup & Installation

Grafana should be installed from its official signed APT repository.

Prometheus binaries are installed under:

    /usr/local/bin/prometheus
    /usr/local/bin/promtool

Node Exporter is installed under:

    /usr/local/bin/node_exporter

Prometheus configuration is stored at:

    /etc/prometheus/prometheus.yml

Prometheus persistent time-series data is stored at:

    /var/lib/prometheus

Grafana provisioning configuration is stored under:

    /etc/grafana/provisioning/

Dashboard definitions are stored under:

    /var/lib/grafana/dashboards/

## How to Reproduce

### 1. Configure Prometheus

Place the Prometheus configuration at:

    /etc/prometheus/prometheus.yml

The configuration scrapes both Prometheus and Node Exporter:

    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    scrape_configs:
      - job_name: "prometheus"
        static_configs:
          - targets: ["127.0.0.1:9090"]

      - job_name: "node"
        static_configs:
          - targets: ["127.0.0.1:9100"]

Validate it:

    promtool check config /etc/prometheus/prometheus.yml

### 2. Configure the system services

Install the included service definitions:

    sudo cp prometheus.service /etc/systemd/system/prometheus.service
    sudo cp node_exporter.service /etc/systemd/system/node_exporter.service

Reload systemd:

    sudo systemctl daemon-reload

Enable the services:

    sudo systemctl enable --now prometheus
    sudo systemctl enable --now node_exporter
    sudo systemctl enable --now grafana-server

### 3. Validate metric collection

Check Prometheus:

    curl http://127.0.0.1:9090/-/healthy

Inspect targets:

    curl -s http://127.0.0.1:9090/api/v1/targets | jq .

Check Node Exporter:

    curl http://127.0.0.1:9100/metrics

Both Prometheus targets should report healthy.

### 4. Provision the Grafana data source

Place:

    prometheus.yaml

under:

    /etc/grafana/provisioning/datasources/

The data source connects Grafana to:

    http://127.0.0.1:9090

using the stable UID:

    prometheus

### 5. Provision the dashboard

Place:

    system-dashboard.yaml

under:

    /etc/grafana/provisioning/dashboards/

Place:

    linux-system-monitoring.json

under:

    /var/lib/grafana/dashboards/

Restart Grafana:

    sudo systemctl restart grafana-server

### 6. Validate Grafana

Check the health endpoint:

    curl -s http://127.0.0.1:3000/api/health | jq .

Validate the dashboard JSON:

    jq empty linux-system-monitoring.json

### 7. Validate key PromQL expressions

CPU utilization:

    100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

Memory utilization:

    (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

Root filesystem utilization:

    (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

Network receive throughput:

    rate(node_network_receive_bytes_total{device!="lo"}[5m]) * 8

Network transmit throughput:

    rate(node_network_transmit_bytes_total{device!="lo"}[5m]) * 8

System load:

    node_load1
    node_load5
    node_load15

Running processes:

    node_procs_running

Host information:

    node_uname_info

## Dashboard Components

The provisioned dashboard contains:

- Dashboard overview
- CPU utilization time series
- Memory utilization gauge
- Root filesystem utilization gauge
- Running process stat
- Network receive and transmit throughput
- System load visualization
- Host and operating-system information table
- Dynamic server selection
- One-hour default time range
- 30-second automatic refresh

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
- GnuPG
- APT
- Grafana provisioning
- JSON
- YAML

## Key Skills Demonstrated

- Designing an infrastructure observability architecture
- Collecting Linux telemetry through Node Exporter
- Configuring Prometheus scrape targets
- Writing operational PromQL expressions
- Measuring CPU, memory, disk, network, load, and process activity
- Designing multiple visualization types
- Building Grafana dashboards as code
- Provisioning Grafana data sources from YAML
- Implementing dynamic dashboard variables
- Designing reusable instance-aware PromQL
- Managing systemd services
- Applying dedicated service identities
- Validating metric pipelines through HTTP APIs
- Designing repeatable monitoring configuration for version control
- Troubleshooting installation, service, and query failures

## Real-World Use Case

This architecture provides the foundation for monitoring Linux hosts that run application workloads, CI/CD workers, container infrastructure, databases, internal services, AI inference workloads, or platform components. Engineering teams can use the dashboard to identify CPU saturation, memory pressure, filesystem capacity problems, network anomalies, abnormal load, and process activity before these conditions become production incidents.

For AIOps environments, the same Prometheus telemetry can also feed anomaly detection, automated incident analysis, capacity forecasting, and remediation systems.

## Lessons Learned

- Raw infrastructure metrics become operationally useful only when transformed into meaningful signals through PromQL.
- Instance-aware queries make dashboards reusable when monitoring expands beyond a single server.
- Grafana provisioning eliminates repetitive browser configuration and makes dashboards reproducible across environments.
- Dedicated Linux identities improve isolation between independent monitoring services.
- Dashboard refresh intervals should balance operational visibility against query volume.
- Validating each component independently simplifies troubleshooting across the complete telemetry pipeline.

## Troubleshooting Log

### Deprecated Grafana repository workflow

Older installation instructions relied on `apt-key` and legacy Grafana repository configuration.

The installation was updated to use a dedicated signed APT keyring.

### Outdated Prometheus release

An older Prometheus 2.x binary was replaced with a current Prometheus 3.x release.

### Outdated Node Exporter release

An older Node Exporter binary was replaced with a current release.

### Service account isolation

Node Exporter was separated from the Prometheus account and configured with its own dedicated system identity.

### Legacy Prometheus service parameters

Unnecessary console template and console library parameters were removed from the Prometheus systemd definition.

### Manual Grafana configuration

Browser-based Prometheus data-source configuration was replaced with native Grafana provisioning.

### Manual dashboard creation

The dashboard was defined directly as JSON and loaded through Grafana provisioning instead of being constructed through manual drag-and-drop operations.

### CPU query scalability

The CPU utilization expression was grouped by instance so the same dashboard can support multiple monitored servers without combining their CPU values into one global average.
