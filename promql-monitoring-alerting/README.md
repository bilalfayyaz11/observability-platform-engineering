# PromQL Monitoring and Alerting

## What This Does

This implementation builds a complete Linux observability workflow centered on Prometheus Query Language.

Node Exporter exposes Linux infrastructure telemetry, Prometheus collects and stores the metrics, PromQL transforms raw time-series data into operational signals, and Grafana visualizes those signals through a provisioned dashboard.

The implementation covers CPU, memory, disk, network, load, filesystem, and host-level telemetry while demonstrating rate calculations, aggregation functions, label matching, range vectors, offsets, mathematical expressions, and alert conditions.

Prometheus alert rules monitor critical infrastructure thresholds for CPU utilization, memory pressure, and root filesystem capacity.

## Architecture

    ┌──────────────────────────────────────────────────────────┐
    │                     Linux Host                           │
    │                                                          │
    │   ┌──────────────────────────────────────────────────┐   │
    │   │                Node Exporter                     │   │
    │   │                                                  │   │
    │   │ CPU / Memory / Disk / Network / Load Metrics     │   │
    │   │ Endpoint :9100                                   │   │
    │   └──────────────────────┬───────────────────────────┘   │
    │                          │                               │
    │                          │ Scrape                        │
    │                          ▼                               │
    │   ┌──────────────────────────────────────────────────┐   │
    │   │                  Prometheus                      │   │
    │   │                                                  │   │
    │   │ Time-Series Storage                             │   │
    │   │ PromQL Query Engine                             │   │
    │   │ Alert Rule Evaluation                           │   │
    │   │ Endpoint :9090                                  │   │
    │   └──────────────────────┬───────────────────────────┘   │
    │                          │                               │
    │                          │ PromQL                        │
    │                          ▼                               │
    │   ┌──────────────────────────────────────────────────┐   │
    │   │                    Grafana                       │   │
    │   │                                                  │   │
    │   │ Provisioned Prometheus Data Source              │   │
    │   │ PromQL Dashboard                                │   │
    │   │ Infrastructure Visualizations                   │   │
    │   │ Endpoint :3000                                  │   │
    │   └──────────────────────────────────────────────────┘   │
    │                                                          │
    └──────────────────────────────────────────────────────────┘

## Prerequisites

- Ubuntu or another systemd-based Linux distribution
- sudo privileges
- Internet connectivity
- Grafana
- Prometheus
- Promtool
- Prometheus Node Exporter
- curl
- wget
- jq
- GnuPG
- systemd
- Linux networking utilities

Required ports:

- `3000` — Grafana
- `9090` — Prometheus
- `9100` — Node Exporter

## Setup & Installation

Prometheus binaries:

    /usr/local/bin/prometheus
    /usr/local/bin/promtool

Node Exporter:

    /usr/local/bin/node_exporter

Prometheus configuration:

    /etc/prometheus/prometheus.yml

Alert rules:

    /etc/prometheus/alert_rules.yml

Grafana provisioning:

    /etc/grafana/provisioning/

Dashboard definitions:

    /var/lib/grafana/dashboards/

## How to Reproduce

### Configure Prometheus

Use:

    prometheus.yml

Validate:

    promtool check config prometheus.yml

Install the configuration:

    sudo cp prometheus.yml /etc/prometheus/prometheus.yml

### Install systemd definitions

    sudo cp prometheus.service /etc/systemd/system/prometheus.service
    sudo cp node_exporter.service /etc/systemd/system/node_exporter.service

    sudo systemctl daemon-reload
    sudo systemctl enable --now prometheus
    sudo systemctl enable --now node_exporter

### Verify scrape targets

    curl -s http://127.0.0.1:9090/api/v1/targets | jq .

Both Prometheus and Node Exporter should report healthy.

### Provision Grafana

Install:

    prometheus.yaml

under:

    /etc/grafana/provisioning/datasources/

Install:

    promql-dashboard.yaml

under:

    /etc/grafana/provisioning/dashboards/

Install:

    promql-system-monitoring.json

under:

    /var/lib/grafana/dashboards/

Restart Grafana:

    sudo systemctl restart grafana-server

## PromQL Examples

### CPU Utilization

    100 - (avg by (instance) (
      rate(node_cpu_seconds_total{mode="idle"}[5m])
    ) * 100)

### Memory Utilization

    (1 - (
      node_memory_MemAvailable_bytes /
      node_memory_MemTotal_bytes
    )) * 100

### Root Filesystem Utilization

    100 - (
      (
        node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs"} /
        node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"}
      ) * 100
    )

### Network Receive Rate

    rate(node_network_receive_bytes_total{device!="lo"}[5m])

### Network Transmit Rate

    rate(node_network_transmit_bytes_total{device!="lo"}[5m])

### Aggregate Network Receive Rate

    sum(rate(node_network_receive_bytes_total[5m]))

### Average System Load

    avg(node_load1)

### Largest Filesystem

    max(node_filesystem_size_bytes)

### Exact Label Match

    node_filesystem_size_bytes{mountpoint="/"}

### Regex Label Match

    node_filesystem_size_bytes{device=~"/dev/.*"}

### Negative Label Match

    node_network_receive_bytes_total{device!="lo"}

### Range Vector

    rate(node_cpu_seconds_total[5m])

### Offset

    node_load1 offset 1h

### Counter Increase

    increase(node_network_receive_bytes_total[1h])

## Alert Rules

The implementation includes three operational alert conditions.

### High CPU Usage

Triggers when CPU utilization remains above 80% for two minutes.

### High Memory Usage

Triggers when memory utilization remains above 85% for two minutes.

### Root Disk Usage High

Triggers when root filesystem utilization remains above 90% for one minute.

Validate the rules:

    promtool check rules alert_rules.yml

Reload Prometheus:

    curl -X POST http://127.0.0.1:9090/-/reload

Inspect rules:

    curl -s http://127.0.0.1:9090/api/v1/rules | jq .

Inspect active alerts:

    curl -s http://127.0.0.1:9090/api/v1/alerts | jq .

## Tools Used

- Prometheus
- PromQL
- Promtool
- Prometheus Node Exporter
- Grafana
- Grafana provisioning
- systemd
- curl
- jq
- Linux
- YAML
- JSON

## Key Skills Demonstrated

- Writing production-oriented PromQL expressions
- Understanding metric types and query semantics
- Using rate functions with counters
- Performing metric aggregation
- Filtering time series with label matchers
- Working with range vectors
- Using historical offsets
- Calculating utilization percentages
- Designing infrastructure alert expressions
- Validating Prometheus configuration
- Validating Prometheus rule files
- Reloading Prometheus without service interruption
- Building dashboards as code
- Provisioning Grafana data sources
- Analyzing infrastructure telemetry
- Troubleshooting incorrect query assumptions

## Real-World Use Case

PromQL is used heavily in production observability environments to transform raw telemetry into signals engineers can use for troubleshooting, capacity planning, incident response, SLO monitoring, alerting, and automated operational decisions.

The same query patterns can support Kubernetes monitoring, cloud infrastructure, application platforms, CI/CD systems, database workloads, and AI infrastructure.

In AIOps environments, PromQL-derived signals can also become inputs for anomaly detection, automated incident classification, predictive capacity systems, and remediation workflows.

## Lessons Learned

- Metric type matters when choosing PromQL functions.
- `rate()` and `increase()` are intended primarily for counter behavior rather than ordinary gauges.
- Labels are fundamental to selecting and grouping Prometheus time series.
- Aggregation transforms high-cardinality telemetry into operational summaries.
- Query semantics must be validated rather than inferred from metric names.
- Alert expressions should represent actionable operating conditions.
- Prometheus rules can be reloaded without restarting the monitoring server when lifecycle endpoints are enabled.

## Troubleshooting Log

### Outdated Prometheus Release

The older Prometheus 2.x release was replaced with a current Prometheus 3.x binary.

### Outdated Node Exporter Release

The older Node Exporter release was replaced with a current version.

### Deprecated Grafana Repository Configuration

Legacy `apt-key` repository handling was replaced with a dedicated signed APT keyring.

### Service Account Isolation

Node Exporter was separated from the Prometheus user and assigned its own service identity.

### Incorrect Process CPU Interpretation

The expression:

    topk(5, rate(node_cpu_seconds_total{mode!="idle"}[5m]))

does not return the top CPU-consuming processes.

`node_cpu_seconds_total` describes CPU time by processor and mode.

True process-level ranking requires a process-aware exporter or application instrumentation.

### Incorrect Gauge Increase Usage

Applying:

    increase(node_memory_MemTotal_bytes[1h])

does not meaningfully represent memory utilization because total system memory is a gauge and is generally static.

Memory utilization is better represented using:

    (1 - (
      node_memory_MemAvailable_bytes /
      node_memory_MemTotal_bytes
    )) * 100

### Manual Grafana Query Editing

Browser-based dashboard and Query Editor operations were replaced with deterministic Grafana provisioning and dashboard JSON.

### Alert Delivery Boundary

Prometheus evaluates alert conditions but does not provide full notification routing by itself.

Production notification delivery normally adds Alertmanager or another supported alert delivery path.
