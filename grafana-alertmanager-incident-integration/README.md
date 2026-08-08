# Grafana and Alertmanager Incident Integration

## What This Does

This implementation builds an end-to-end observability and incident-delivery pipeline using Prometheus, Node Exporter, Alertmanager, Grafana, and a custom webhook receiver.

Prometheus collects infrastructure telemetry and evaluates alert conditions.

Alertmanager receives firing incidents, groups and routes them by severity, applies inhibition rules, and delivers both firing and resolved notifications.

Grafana is integrated with both Prometheus and Alertmanager to provide infrastructure metrics and alert-management visibility from a single operational interface.

A lightweight Python webhook receiver records real Alertmanager notification payloads, allowing the complete incident lifecycle to be validated without external SMTP or chat-service credentials.

## Architecture

    ┌─────────────────────────────────────────────────────────────┐
    │                         Linux Host                          │
    │                                                             │
    │   ┌────────────────────┐                                    │
    │   │   Node Exporter    │                                    │
    │   │       :9100        │                                    │
    │   └─────────┬──────────┘                                    │
    │             │                                               │
    │             │ Metrics                                       │
    │             ▼                                               │
    │   ┌────────────────────┐                                    │
    │   │     Prometheus     │                                    │
    │   │       :9090        │                                    │
    │   │                    │                                    │
    │   │ Scraping           │                                    │
    │   │ PromQL             │                                    │
    │   │ Alert Evaluation   │                                    │
    │   └─────────┬──────────┘                                    │
    │             │                                               │
    │             │ Firing alerts                                 │
    │             ▼                                               │
    │   ┌────────────────────┐                                    │
    │   │    Alertmanager    │                                    │
    │   │       :9093        │                                    │
    │   │                    │                                    │
    │   │ Grouping           │                                    │
    │   │ Routing            │                                    │
    │   │ Inhibition         │                                    │
    │   │ Resolution         │                                    │
    │   └─────────┬──────────┘                                    │
    │             │                                               │
    │             │ HTTP POST                                     │
    │             ▼                                               │
    │   ┌────────────────────┐                                    │
    │   │  Webhook Receiver  │                                    │
    │   │       :5001        │                                    │
    │   │                    │                                    │
    │   │ Firing Payloads    │                                    │
    │   │ Resolved Payloads  │                                    │
    │   │ JSON Audit Log     │                                    │
    │   └────────────────────┘                                    │
    │                                                             │
    │   ┌─────────────────────────────────────────────────────┐   │
    │   │                       Grafana                       │   │
    │   │                        :3000                        │   │
    │   │                                                     │   │
    │   │     Prometheus Data Source                         │   │
    │   │     Alertmanager Data Source                       │   │
    │   │     Metrics + Alert Operations Dashboard           │   │
    │   └─────────────────────────────────────────────────────┘   │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘

## Alert Lifecycle

The validated incident lifecycle is:

    healthy target
        ↓
    target becomes unavailable
        ↓
    Prometheus records up = 0
        ↓
    ServiceDown enters pending state
        ↓
    configured duration expires
        ↓
    ServiceDown enters firing state
        ↓
    Prometheus sends alert to Alertmanager
        ↓
    Alertmanager applies severity routing
        ↓
    critical-webhook receiver selected
        ↓
    webhook receives firing payload
        ↓
    affected service restored
        ↓
    Prometheus sees recovery
        ↓
    alert resolves
        ↓
    Alertmanager sends resolved payload
        ↓
    webhook records resolution

## Components

### Prometheus

Prometheus is responsible for:

- scraping infrastructure metrics
- storing time-series telemetry
- executing PromQL
- evaluating alert conditions
- forwarding firing alerts to Alertmanager

Port:

    9090

## Node Exporter

Node Exporter provides Linux host metrics including:

- CPU
- memory
- filesystem
- network
- load
- system statistics

Port:

    9100

## Alertmanager

Alertmanager handles:

- alert grouping
- severity routing
- inhibition
- deduplication
- notification delivery
- resolved notifications

Port:

    9093

## Grafana

Grafana is provisioned with two data sources:

    Prometheus
    Alertmanager

It provides operational visibility into:

- CPU utilization
- memory utilization
- scrape-target health
- pending alerts
- firing alerts
- alert state
- infrastructure trends

Port:

    3000

## Webhook Receiver

The notification receiver is implemented in Python using Flask.

It is deployed as a dedicated systemd service and runs inside an isolated Python virtual environment.

Port:

    5001

Health endpoint:

    /health

Alert endpoint:

    /webhook

Notification history:

    /var/log/alert-webhook/alerts.log

## Prometheus Alert Rules

### High CPU Usage

Triggers when CPU utilization remains above 80 percent for two minutes.

    100 - (
      avg by (instance) (
        rate(node_cpu_seconds_total{mode="idle"}[2m])
      ) * 100
    ) > 80

Severity:

    warning

## High Memory Usage

Triggers when memory utilization remains above 85 percent for two minutes.

    (
      1 -
      (
        node_memory_MemAvailable_bytes
        /
        node_memory_MemTotal_bytes
      )
    ) * 100 > 85

Severity:

    critical

## Root Disk Usage High

Triggers when root filesystem usage remains above 90 percent.

Severity:

    critical

## Service Down

Detects unavailable Prometheus targets.

    up == 0

Severity:

    critical

This alert was used to validate the complete notification lifecycle.

## Alertmanager Routing

Default receiver:

    webhook-receiver

Critical alerts:

    critical-webhook

Warning alerts:

    warning-webhook

Routing structure:

    incoming alert
         │
         ├── severity="critical"
         │         ↓
         │   critical-webhook
         │
         └── severity="warning"
                   ↓
             warning-webhook

All webhook receivers have:

    send_resolved: true

This ensures recovery events are delivered as well as firing events.

## Inhibition

Alertmanager is configured to inhibit warning alerts when a critical alert exists for the same instance.

This reduces unnecessary notification noise during higher-severity incidents.

## Webhook Payload Logging

Each notification is stored as one JSON object per line.

Example structure:

    {
      "received_at": "...",
      "status": "firing",
      "receiver": "critical-webhook",
      "groupLabels": {},
      "commonLabels": {},
      "alerts": []
    }

Resolved notifications use:

    "status": "resolved"

This creates a simple audit trail for incident delivery.

## End-to-End Validation

Node Exporter was intentionally stopped:

    sudo systemctl stop node_exporter

Prometheus subsequently observed:

    up{job="node-exporter"} = 0

The ServiceDown rule transitioned:

    inactive
        ↓
    pending
        ↓
    firing

Alertmanager received the incident and selected:

    critical-webhook

The webhook receiver recorded:

    status=firing

Node Exporter was then restored:

    sudo systemctl start node_exporter

Prometheus returned to:

    up{job="node-exporter"} = 1

The alert resolved and Alertmanager delivered a second notification containing:

    status=resolved

This proved notification delivery in both directions of the incident lifecycle.

## Grafana Provisioning

Grafana configuration is managed as code.

Data sources:

    observability.yaml

Dashboard provider:

    alertmanager-integration.yaml

Dashboard:

    alertmanager-integration.json

This avoids manual dashboard and data-source creation.

## Prerequisites

- Ubuntu or another systemd Linux distribution
- Prometheus
- Promtool
- Node Exporter
- Alertmanager
- amtool
- Grafana
- Python 3
- Python virtual environments
- Flask
- curl
- jq
- systemd

## Configuration Files

Prometheus:

    /etc/prometheus/prometheus.yml

Alert rules:

    /etc/prometheus/alert_rules.yml

Alertmanager:

    /etc/alertmanager/alertmanager.yml

Webhook application:

    /opt/alert-webhook/webhook_server.py

Grafana data sources:

    /etc/grafana/provisioning/datasources/observability.yaml

Grafana dashboard provider:

    /etc/grafana/provisioning/dashboards/alertmanager-integration.yaml

Grafana dashboard:

    /var/lib/grafana/dashboards/alertmanager-integration.json

## Service Files

    prometheus.service
    node_exporter.service
    alertmanager.service
    alert-webhook.service

## Validate Prometheus

Configuration:

    promtool check config prometheus.yml

Rules:

    promtool check rules alert_rules.yml

Health:

    curl http://127.0.0.1:9090/-/healthy

Targets:

    curl -s \
      http://127.0.0.1:9090/api/v1/targets \
      | jq .

Rules:

    curl -s \
      http://127.0.0.1:9090/api/v1/rules \
      | jq .

Alerts:

    curl -s \
      http://127.0.0.1:9090/api/v1/alerts \
      | jq .

## Validate Alertmanager

Configuration:

    amtool check-config alertmanager.yml

Routes:

    amtool config routes \
      --alertmanager.url=http://127.0.0.1:9093

Health:

    curl http://127.0.0.1:9093/-/healthy

Alerts:

    curl -s \
      http://127.0.0.1:9093/api/v2/alerts \
      | jq .

Status:

    curl -s \
      http://127.0.0.1:9093/api/v2/status \
      | jq .

## Validate Webhook Receiver

Health:

    curl http://127.0.0.1:5001/health

Logs:

    sudo cat /var/log/alert-webhook/alerts.log

Formatted history:

    sudo jq -r '
      [
        .received_at,
        .status,
        .receiver,
        ([.alerts[].labels.alertname] | join(","))
      ]
      | @tsv
    ' /var/log/alert-webhook/alerts.log

## Validate Grafana

Health:

    curl http://127.0.0.1:3000/api/health

Data sources:

    curl -u admin:admin \
      http://127.0.0.1:3000/api/datasources

Dashboard:

    curl -u admin:admin \
      http://127.0.0.1:3000/api/dashboards/uid/prometheus-alertmanager-integration

## Service Management

Enable services:

    sudo systemctl enable \
      alert-webhook \
      node_exporter \
      alertmanager \
      prometheus \
      grafana-server

Start services:

    sudo systemctl start \
      alert-webhook \
      node_exporter \
      alertmanager \
      prometheus \
      grafana-server

Verify:

    systemctl is-active alert-webhook
    systemctl is-active node_exporter
    systemctl is-active alertmanager
    systemctl is-active prometheus
    systemctl is-active grafana-server

## Tools Used

- Prometheus
- PromQL
- Promtool
- Node Exporter
- Alertmanager
- amtool
- Grafana
- Python
- Flask
- Python virtual environments
- systemd
- Linux
- curl
- jq
- YAML
- JSON

## Key Skills Demonstrated

- Prometheus metrics collection
- PromQL alert engineering
- Alertmanager integration
- Alert routing
- Alert grouping
- Alert inhibition
- Notification lifecycle management
- Webhook integration
- HTTP-based service integration
- Incident-delivery validation
- Grafana data-source provisioning
- Dashboard-as-code
- Python service deployment
- systemd service management
- Service isolation
- Operational debugging
- Failure injection
- Recovery validation

## Real-World Use Case

Modern infrastructure requires more than collecting metrics.

Telemetry must lead to actionable incident signals and those incidents must reliably reach notification systems.

The same architecture can support:

- cloud infrastructure
- Kubernetes platforms
- API services
- databases
- CI/CD systems
- AI inference servers
- model-serving infrastructure
- GPU workers
- agent runtimes
- vector databases
- retrieval pipelines
- distributed data systems

In AI infrastructure, the same notification pipeline can alert engineering teams when model endpoints fail, GPUs become unavailable, request latency increases, queue depth rises, or supporting infrastructure becomes unhealthy.

## Lessons Learned

Prometheus, Alertmanager, and Grafana have different operational responsibilities.

Prometheus detects conditions.

Alertmanager manages incidents.

Grafana provides operational visibility.

A webhook receiver provides a simple and deterministic way to prove notification delivery without depending on external email or messaging credentials.

Resolved notifications are as important as firing notifications because downstream systems need explicit recovery information.

Running operational components as systemd services provides stronger lifecycle control than launching background processes manually.

Dedicated service identities improve isolation and make component ownership clearer.

Grafana provisioning makes dashboards and data-source configuration reproducible rather than dependent on manual UI actions.

## Troubleshooting Log

### Outdated Monitoring Versions

Older component releases were replaced with current supported releases.

### Deprecated Grafana Repository Setup

Legacy `apt-key` installation was replaced with a dedicated signed keyring.

### System Python Package Installation

Direct global Flask installation was avoided.

The webhook application runs inside a dedicated Python virtual environment.

### Temporary Webhook Process

The webhook receiver was converted from a background shell process into a managed systemd service.

### Legacy Alertmanager API

Current Alertmanager v2 API endpoints were used for operational verification.

### Legacy Matcher Configuration

Alertmanager routing and inhibition use current matcher syntax.

### Grafana Notification Responsibility

Prometheus remains responsible for evaluating the infrastructure alert rules.

Alertmanager remains responsible for incident processing and notification delivery.

Grafana is integrated for visibility rather than duplicating the same alert pipeline.

### CPU Stress Reliability

CPU stress alone does not guarantee identical host-wide utilization across machines with different vCPU counts.

A deterministic scrape-target failure was therefore used to prove the incident lifecycle.

### Notification Verification

Notification delivery is not assumed.

Actual firing and resolved payloads are written to the webhook receiver log and verified explicitly.
