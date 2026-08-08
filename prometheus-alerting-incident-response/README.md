# Prometheus Alerting and Incident Response

## What This Does

This implementation builds a complete metrics-driven incident detection and routing pipeline using Prometheus, Node Exporter, Alertmanager, and Grafana.

Prometheus collects Linux infrastructure metrics and evaluates threshold-based alert rules.

Alertmanager receives firing alerts and applies severity-based routing, grouping, inhibition, silencing, and resolution handling.

Grafana provides an operational dashboard for infrastructure health and current alert state.

The implementation validates the full lifecycle of an incident from metric collection through detection, escalation, routing, recovery, and resolution.

## Architecture

    ┌──────────────────────────────────────────────────────────────┐
    │                        Linux Host                            │
    │                                                              │
    │  ┌──────────────────────┐                                    │
    │  │    Node Exporter     │                                    │
    │  │       :9100          │                                    │
    │  │                      │                                    │
    │  │ CPU                  │                                    │
    │  │ Memory               │                                    │
    │  │ Disk                 │                                    │
    │  │ Network              │                                    │
    │  └──────────┬───────────┘                                    │
    │             │                                                │
    │             │ scrape                                         │
    │             ▼                                                │
    │  ┌──────────────────────┐                                    │
    │  │     Prometheus       │                                    │
    │  │       :9090          │                                    │
    │  │                      │                                    │
    │  │ Metrics Storage      │                                    │
    │  │ PromQL               │                                    │
    │  │ Alert Evaluation     │                                    │
    │  └──────────┬───────────┘                                    │
    │             │                                                │
    │             │ firing alerts                                  │
    │             ▼                                                │
    │  ┌───────────────────────────────────────────────────────┐   │
    │  │                    Alertmanager                       │   │
    │  │                       :9093                           │   │
    │  │                                                       │   │
    │  │ Grouping                                              │   │
    │  │ Severity Routing                                      │   │
    │  │ Inhibition                                            │   │
    │  │ Silencing                                             │   │
    │  │ Resolution Handling                                   │   │
    │  └───────────────────────────────────────────────────────┘   │
    │                                                              │
    │  ┌───────────────────────────────────────────────────────┐   │
    │  │                      Grafana                          │   │
    │  │                       :3000                           │   │
    │  │                                                       │   │
    │  │ Metrics                                               │   │
    │  │ Pending Alerts                                        │   │
    │  │ Firing Alerts                                         │   │
    │  │ Target Health                                         │   │
    │  └───────────────────────────────────────────────────────┘   │
    │                                                              │
    └──────────────────────────────────────────────────────────────┘

## Alert Lifecycle

The complete incident lifecycle validated by this implementation is:

    healthy target
        ↓
    scrape failure
        ↓
    alert condition becomes true
        ↓
    pending
        ↓
    configured duration satisfied
        ↓
    firing
        ↓
    Alertmanager receives alert
        ↓
    severity routing
        ↓
    service recovery
        ↓
    condition becomes false
        ↓
    resolved

## Alert Rules

### High CPU Usage

Triggers when host CPU utilization remains above 80 percent for two minutes.

PromQL:

    100 - (
      avg by (instance) (
        rate(node_cpu_seconds_total{mode="idle"}[2m])
      ) * 100
    ) > 80

Severity:

    warning

### High Memory Usage

Triggers when memory utilization remains above 85 percent for two minutes.

PromQL:

    (
      1 -
      (
        node_memory_MemAvailable_bytes
        /
        node_memory_MemTotal_bytes
      )
    ) * 100 > 85

Severity:

    warning

### Root Disk Usage High

Triggers when the root filesystem remains above 90 percent utilization for one minute.

Severity:

    critical

### Service Down

Detects unavailable Prometheus scrape targets:

    up == 0

The condition must remain true for one minute before firing.

Severity:

    critical

### High Network Traffic

Detects sustained network receive throughput above 10 MB/s:

    rate(
      node_network_receive_bytes_total{
        device!="lo"
      }[2m]
    ) > 10000000

Severity:

    warning

## Alertmanager Routing

The routing tree separates incidents by severity.

Default receiver:

    local-observability

Critical incidents:

    critical-alerts

Warning incidents:

    warning-alerts

Example structure:

    incoming alert
         │
         ├── severity="critical"
         │      ↓
         │  critical-alerts
         │
         └── severity="warning"
                ↓
            warning-alerts

## Grouping

Alerts are grouped using:

    alertname
    instance

Grouping prevents individual notifications from being generated independently for every related alert when they belong to the same incident context.

## Inhibition

Critical alerts can suppress related warning alerts for the same instance.

This helps reduce alert noise when a higher-severity event already represents the underlying failure.

## Silencing

Alertmanager silences were tested using `amtool`.

Example:

    amtool silence add \
      alertname=~"Synthetic.*" \
      --author="Bilal Fayyaz" \
      --comment="Controlled routing and silence validation" \
      --duration=10m \
      --alertmanager.url=http://127.0.0.1:9093

List silences:

    amtool silence query \
      --alertmanager.url=http://127.0.0.1:9093

Expire a silence:

    amtool silence expire <SILENCE_ID> \
      --alertmanager.url=http://127.0.0.1:9093

## End-to-End Incident Validation

A deterministic availability failure was used instead of relying only on CPU saturation.

Node Exporter was stopped:

    sudo systemctl stop node_exporter

Prometheus subsequently reported:

    up{job="node-exporter"} = 0

The ServiceDown alert transitioned to:

    pending

and then:

    firing

after its configured duration.

Alertmanager received the critical event and routed it through:

    critical-alerts

Node Exporter was then restored:

    sudo systemctl start node_exporter

Prometheus returned to:

    up{job="node-exporter"} = 1

and the alert resolved.

This validated the complete monitoring and incident response chain.

## Grafana Alert Operations Dashboard

Grafana is provisioned entirely through files.

Data source:

    prometheus.yaml

Dashboard provider:

    alert-operations.yaml

Dashboard:

    alert-operations.json

The dashboard displays:

- CPU utilization
- Memory utilization
- Root disk utilization
- CPU trends
- Memory trends
- Pending Prometheus alerts
- Firing Prometheus alerts
- Healthy scrape targets
- Active alert details

## Prerequisites

- Ubuntu or another systemd-based Linux distribution
- Prometheus
- Promtool
- Node Exporter
- Alertmanager
- amtool
- Grafana
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

Prometheus service:

    /etc/systemd/system/prometheus.service

Node Exporter service:

    /etc/systemd/system/node_exporter.service

Alertmanager service:

    /etc/systemd/system/alertmanager.service

Grafana provisioning:

    /etc/grafana/provisioning/

## Validate Prometheus

Check configuration:

    promtool check config prometheus.yml

Check rules:

    promtool check rules alert_rules.yml

Prometheus health:

    curl http://127.0.0.1:9090/-/healthy

Inspect scrape targets:

    curl -s \
      http://127.0.0.1:9090/api/v1/targets \
      | jq .

Inspect alert rules:

    curl -s \
      http://127.0.0.1:9090/api/v1/rules \
      | jq .

Inspect active alerts:

    curl -s \
      http://127.0.0.1:9090/api/v1/alerts \
      | jq .

## Validate Alertmanager

Check configuration:

    amtool check-config alertmanager.yml

Inspect routing tree:

    amtool config routes \
      --alertmanager.url=http://127.0.0.1:9093

Health:

    curl http://127.0.0.1:9093/-/healthy

Inspect alerts:

    curl -s \
      http://127.0.0.1:9093/api/v2/alerts \
      | jq .

Inspect alert groups:

    curl -s \
      http://127.0.0.1:9093/api/v2/alerts/groups \
      | jq .

## Service Management

Enable services:

    sudo systemctl enable \
      prometheus \
      node_exporter \
      alertmanager \
      grafana-server

Start services:

    sudo systemctl start \
      prometheus \
      node_exporter \
      alertmanager \
      grafana-server

Verify:

    systemctl is-active prometheus
    systemctl is-active node_exporter
    systemctl is-active alertmanager
    systemctl is-active grafana-server

## Tools Used

- Prometheus
- PromQL
- Promtool
- Prometheus Node Exporter
- Alertmanager
- amtool
- Grafana
- systemd
- Linux
- curl
- jq
- YAML
- JSON

## Key Skills Demonstrated

- Metrics-based incident detection
- Prometheus alert rule engineering
- Threshold monitoring
- Alert lifecycle management
- Prometheus rule validation
- Alertmanager configuration
- Severity-based alert routing
- Alert grouping
- Alert inhibition
- Alert silencing
- Incident resolution validation
- Availability monitoring
- Infrastructure telemetry
- Grafana provisioning
- Alert-state visualization
- systemd service management
- Least-privilege service identities
- Operational troubleshooting

## Real-World Use Case

Production systems require engineers to detect failures before users or dependent systems are significantly impacted.

Metrics alone provide visibility, but alerting converts telemetry into operational action.

This architecture can be applied to:

- API availability
- Kubernetes workloads
- infrastructure capacity
- database health
- network saturation
- service dependencies
- model-serving infrastructure
- GPU worker availability
- AI inference latency
- queue backlogs
- CI/CD systems
- cloud infrastructure

In production AI environments, similar rules can detect model-serving failures, elevated inference latency, memory pressure, GPU saturation, request errors, retrieval outages, or degraded agent infrastructure.

## Lessons Learned

Prometheus and Alertmanager have separate responsibilities.

Prometheus evaluates whether an operational condition is true.

Alertmanager controls how resulting incidents are grouped, routed, inhibited, silenced, and eventually resolved.

The `for` clause helps prevent short-lived metric spikes from immediately becoming incidents.

Severity labels allow routing decisions to remain independent from metric expressions.

A deterministic availability failure is often a stronger validation mechanism than load generation because the expected alert transition can be precisely controlled.

Silences are temporary operational controls and should not replace fixing alert rules or underlying failures.

## Troubleshooting Log

### Outdated Monitoring Components

Older Prometheus, Node Exporter, and Alertmanager releases were replaced with newer supported releases.

### Deprecated Grafana Repository Setup

Legacy `apt-key` installation was replaced by a dedicated signed APT keyring.

### Shared Service Account

Node Exporter was separated from the Prometheus service identity.

Each monitoring component now runs with its own service account.

### Placeholder SMTP Configuration

Example SMTP usernames, passwords, sender addresses, and recipients do not prove email delivery.

Actual delivery requires a valid SMTP service and credentials.

### Placeholder Slack Webhook

A placeholder Slack webhook cannot validate notification delivery.

Real Slack delivery requires an actual webhook or supported app integration.

### Notification Validation Boundary

The implementation proves alert detection, Alertmanager receipt, severity routing, grouping, inhibition, silencing, and resolution.

External email or Slack delivery is not claimed without real credentials.

### Non-Deterministic CPU Stress

Fixed numbers of CPU stress processes do not guarantee a specific host-wide CPU percentage across machines with different processor counts.

Service availability was therefore used to validate the alert lifecycle deterministically.

### Alerting Responsibility

Prometheus evaluates the alert conditions.

Alertmanager controls operational incident handling.

Grafana provides visualization and operational context.

Keeping these responsibilities explicit avoids duplicating alert logic across multiple systems.
