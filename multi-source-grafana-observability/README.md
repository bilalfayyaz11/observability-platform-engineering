# Multi-Source Observability with Grafana, Prometheus, and InfluxDB

## What This Does

This implementation builds a multi-source observability platform that connects Grafana to both Prometheus and InfluxDB 3 Core.

Prometheus provides operational monitoring metrics through its pull-based collection model, while InfluxDB stores custom time-series telemetry such as CPU and memory measurements. Grafana acts as the unified visualization layer and queries both systems from a single provisioned dashboard.

The entire Grafana configuration is managed through provisioning files rather than manual browser configuration, making the architecture reproducible, version-controlled, and suitable for infrastructure automation workflows.

## Architecture

    ┌──────────────────────────────────────────────────────────┐
    │                    Linux Host                            │
    │                                                          │
    │   ┌───────────────────────┐   ┌───────────────────────┐  │
    │   │      Prometheus       │   │    InfluxDB 3 Core    │  │
    │   │                       │   │                       │  │
    │   │ Pull-based metrics    │   │ Custom time-series    │  │
    │   │ PromQL engine         │   │ SQL query engine      │  │
    │   │ TSDB storage          │   │ Authenticated writes  │  │
    │   │ Port 9090             │   │ Port 8181             │  │
    │   └───────────┬───────────┘   └───────────┬───────────┘  │
    │               │                           │              │
    │               │ PromQL                    │ SQL          │
    │               │                           │              │
    │               └─────────────┬─────────────┘              │
    │                             ▼                            │
    │                  ┌─────────────────────┐                 │
    │                  │       Grafana       │                 │
    │                  │                     │                 │
    │                  │ Provisioned sources │                 │
    │                  │ Mixed-source views  │                 │
    │                  │ Port 3000           │                 │
    │                  └─────────────────────┘                 │
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
- Grafana
- Prometheus
- Promtool
- InfluxDB 3 Core

Required local service ports:

- `3000` — Grafana
- `9090` — Prometheus
- `8181` — InfluxDB 3 Core

## Setup & Installation

Grafana is installed from the official signed APT repository.

Prometheus binaries are installed under:

    /usr/local/bin/prometheus
    /usr/local/bin/promtool

InfluxDB 3 Core is installed through the official InfluxData repository.

Prometheus configuration is stored at:

    /etc/prometheus/prometheus.yml

Prometheus persistent storage is maintained under:

    /var/lib/prometheus

Grafana provisioning files are stored under:

    /etc/grafana/provisioning/

Dashboard definitions are stored under:

    /var/lib/grafana/dashboards/

## How to Reproduce

### 1. Configure Prometheus

Place the Prometheus configuration at:

    /etc/prometheus/prometheus.yml

Validate it:

    promtool check config /etc/prometheus/prometheus.yml

Enable the service:

    sudo systemctl daemon-reload
    sudo systemctl enable --now prometheus

Verify:

    curl http://127.0.0.1:9090/-/healthy

### 2. Configure InfluxDB 3 Core

Start the packaged service:

    sudo systemctl enable influxdb3-core
    sudo systemctl start influxdb3-core

Verify the service:

    systemctl is-active influxdb3-core

InfluxDB listens on:

    http://127.0.0.1:8181

Create an administrator token:

    influxdb3 create token --admin

Keep the generated token outside version control.

Create the telemetry database:

    influxdb3 create database --token "$INFLUXDB_TOKEN" grafana_metrics

### 3. Write sample telemetry

Example line-protocol input:

    cpu_usage,host=server1,region=us-west value=80.5
    cpu_usage,host=server2,region=us-east value=65.2
    memory_usage,host=server1,region=us-west value=75.8
    memory_usage,host=server2,region=us-east value=82.1

Query the stored data:

    influxdb3 query \
      --database grafana_metrics \
      --token "$INFLUXDB_TOKEN" \
      "SELECT * FROM cpu_usage"

### 4. Provision Grafana data sources

Prometheus provisioning:

    prometheus.yaml

InfluxDB provisioning template:

    influxdb.yaml

The InfluxDB token must be injected through:

    INFLUXDB_TOKEN

Never commit a production token into the repository.

### 5. Provision the dashboard

The dashboard provider is defined in:

    multi-source.yaml

The dashboard itself is:

    multi-source-observability.json

Restart Grafana after provisioning:

    sudo systemctl restart grafana-server

### 6. Verify all services

    systemctl is-active grafana-server
    systemctl is-active prometheus
    systemctl is-active influxdb3-core

Verify listeners:

    sudo ss -ltnp | grep -E ':(3000|8181|9090)\b'

### 7. Verify Prometheus

    curl -sG http://127.0.0.1:9090/api/v1/query \
      --data-urlencode 'query=up' | jq .

### 8. Verify InfluxDB

    curl -s \
      --get http://127.0.0.1:8181/api/v3/query_sql \
      --header "Authorization: Bearer ${INFLUXDB_TOKEN}" \
      --data-urlencode 'db=grafana_metrics' \
      --data-urlencode 'q=SELECT * FROM cpu_usage' \
      --data-urlencode 'format=json' | jq .

### 9. Verify Grafana

    curl -s http://127.0.0.1:3000/api/health | jq .

## Tools Used

- Ubuntu Linux
- Grafana
- Prometheus
- PromQL
- Promtool
- InfluxDB 3 Core
- SQL
- systemd
- curl
- wget
- jq
- GnuPG
- APT
- Grafana provisioning

## Key Skills Demonstrated

- Designing a multi-source observability architecture
- Integrating heterogeneous time-series systems into Grafana
- Configuring Prometheus metric collection
- Operating InfluxDB 3 Core
- Writing and querying time-series data
- Working with PromQL and SQL
- Building Grafana data-source provisioning files
- Provisioning dashboards as code
- Creating mixed-source visualization workflows
- Managing Linux services with systemd
- Implementing authenticated telemetry storage
- Separating runtime secrets from version-controlled configuration
- Validating observability services through HTTP APIs
- Troubleshooting outdated installation and configuration workflows

## Real-World Use Case

A production platform may collect different types of telemetry through different storage systems. Infrastructure health and service metrics can be collected through Prometheus, while custom application, device, operational, or business time-series data can be stored in InfluxDB. Grafana can unify both sources into a common operational view, allowing engineering teams to correlate platform health with custom telemetry without forcing every workload into a single monitoring backend.

## Lessons Learned

- Multi-source dashboards allow different telemetry technologies to coexist behind a single visualization layer.
- Modern InfluxDB 3 workflows differ substantially from legacy InfluxDB 1.x installation, authentication, and query patterns.
- Grafana provisioning makes data-source and dashboard configuration deterministic and reproducible.
- Stable data-source UIDs make dashboard definitions portable across environments.
- Runtime authentication tokens should never be embedded directly into repository configuration.
- Direct API validation provides faster and more reliable troubleshooting than relying solely on browser interfaces.

## Troubleshooting Log

### Deprecated APT key handling

Legacy repository instructions relied on `apt-key`.

Both Grafana and InfluxData repositories were configured using dedicated signed keyrings instead.

### Legacy InfluxDB architecture

The older configuration expected InfluxDB 1.x behavior including:

    influx
    CREATE DATABASE
    USE
    INSERT

The implementation was updated to InfluxDB 3 Core with authenticated CLI operations, line-protocol writes, and SQL queries.

### Legacy InfluxDB port

Older configurations commonly expected port:

    8086

InfluxDB 3 Core uses:

    8181

in this deployment.

### Outdated Prometheus release

The older fixed Prometheus release was replaced with a current Prometheus 3.x binary.

### Manual Grafana data-source configuration

Browser-based Grafana setup was replaced with provisioning YAML.

### Manual dashboard creation

The mixed-source dashboard was defined as code and automatically loaded by Grafana.

### Secret handling

The live InfluxDB administrator token was stored outside version control.

The repository contains only a token placeholder suitable for secure runtime injection.
