# Observability Platform Engineering

## Overview

This implementation delivers a production-style observability and alerting platform for Linux infrastructure using Prometheus, Alertmanager, Node Exporter, Python, and systemd.

The platform continuously collects host metrics, evaluates alert rules, routes alerts based on severity, and delivers structured notifications to a custom webhook receiver. All monitoring components are deployed as hardened systemd services with automatic startup and recovery.

---

## Architecture

```text
Linux Host
    │
    ▼
Node Exporter (9100)
    │
    ▼
Prometheus (9090)
    │
    ▼
Alertmanager (9093)
    │
    ▼
Python Webhook (5001)
    │
    ▼
systemd Journal
```

---

## Features

- Production-oriented Prometheus deployment
- Alertmanager severity-based routing
- Node Exporter host monitoring
- Custom Python webhook receiver
- Hardened systemd services
- Automatic service recovery
- Prometheus and Alertmanager configuration validation
- Health endpoint verification
- REST API validation
- End-to-end alert lifecycle testing

---

## Alert Rules

| Alert | Condition |
|-------|-----------|
| HighCPUUsage | CPU utilisation > 80% |
| HighMemoryUsage | Memory utilisation > 85% |
| RootFilesystemSpaceLow | Available disk space < 10% |
| NodeExporterDown | Node Exporter unavailable |

---

## Repository Structure

```text
observability-platform-engineering/
├── prometheus/
│   ├── prometheus.yml
│   └── rules/
├── alertmanager/
├── webhook/
├── systemd/
├── testing/
├── .gitignore
└── README.md
```

---

## Technology Stack

- Prometheus
- Alertmanager
- Node Exporter
- Python
- systemd
- PromQL
- Bash
- Linux
- curl
- jq

---

## Skills Demonstrated

- Observability Engineering
- Platform Engineering
- Infrastructure Monitoring
- Prometheus Administration
- PromQL Alert Development
- Alert Routing
- Linux System Administration
- systemd Service Engineering
- Python Automation
- API Validation
- Infrastructure Troubleshooting
- Incident Monitoring

---

## Validation

The implementation was verified by:

- Configuration validation using `promtool`
- Alertmanager validation using `amtool`
- Health endpoint verification
- API verification
- Service verification
- End-to-end alert routing
- Webhook delivery testing
- CPU stress testing
- Alert firing and resolution testing

---

## Real-World Use Cases

- Linux Server Monitoring
- Cloud Infrastructure Monitoring
- Platform Engineering
- Site Reliability Engineering
- DevOps Operations
- Internal Platform Monitoring
- Virtual Machine Monitoring
- Kubernetes Node Monitoring

---

## Key Takeaways

- Built a complete monitoring and alerting pipeline
- Implemented production-style service management
- Designed PromQL alert rules
- Configured Alertmanager routing
- Developed a custom webhook receiver
- Validated the complete alert lifecycle
- Applied Linux service hardening and operational best practices
