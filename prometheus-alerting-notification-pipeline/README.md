# Prometheus Alerting and Notification Pipeline

## What This Does

This implementation provides a complete Prometheus alerting pipeline for Linux infrastructure monitoring.

Node Exporter collects host-level system metrics, Prometheus evaluates alerting rules, Alertmanager receives and routes firing alerts, and a local webhook receiver records both firing and resolved notifications.

The implementation validates the complete alert lifecycle rather than stopping at configuration syntax. CPU utilization is deliberately increased to trigger a real alert, the alert is observed inside Prometheus and Alertmanager, notification delivery is confirmed through the webhook receiver, and the resolved state is verified after the load condition disappears.

A secure email configuration workflow is also included so SMTP delivery can be enabled without storing credentials in repository files or shell commands.

## Architecture

    ┌──────────────────────────────────────────────────────────────┐
    │                         Linux Host                           │
    │                                                              │
    │  ┌─────────────────────┐                                    │
    │  │    Node Exporter    │                                    │
    │  │                     │                                    │
    │  │  CPU                │                                    │
    │  │  Memory             │                                    │
    │  │  Filesystem         │                                    │
    │  │  Disk               │                                    │
    │  │  Network            │                                    │
    │  │                     │                                    │
    │  │  127.0.0.1:9100    │                                    │
    │  └──────────┬──────────┘                                    │
    │             │                                                │
    │             │ 15-second scrape                               │
    │             ▼                                                │
    │  ┌──────────────────────────────┐                            │
    │  │          Prometheus          │                            │
    │  │                              │                            │
    │  │  HighCPUUsage                │                            │
    │  │  HighMemoryUsage             │                            │
    │  │  DiskSpaceLow                │                            │
    │  │  ServiceDown                 │                            │
    │  │                              │                            │
    │  │  127.0.0.1:9090             │                            │
    │  └──────────────┬───────────────┘                            │
    │                 │                                            │
    │                 │ Alert notifications                        │
    │                 ▼                                            │
    │  ┌──────────────────────────────┐                            │
    │  │        Alertmanager          │                            │
    │  │                              │                            │
    │  │  Grouping                    │                            │
    │  │  Routing                     │                            │
    │  │  Resolved notifications      │                            │
    │  │                              │                            │
    │  │  127.0.0.1:9093             │                            │
    │  └──────────────┬───────────────┘                            │
    │                 │                                            │
    │          ┌──────┴─────────┐                                  │
    │          │                │                                  │
    │          ▼                ▼                                  │
    │  ┌──────────────┐   ┌───────────────┐                        │
    │  │ Local Webhook│   │ SMTP Receiver │                        │
    │  │              │   │               │                        │
    │  │ :8080        │   │ Optional      │                        │
    │  └──────────────┘   └───────────────┘                        │
    └──────────────────────────────────────────────────────────────┘

## Repository Structure

    prometheus-alerting-notification-pipeline/
    ├── README.md
    ├── .gitignore
    ├── webhook_receiver.py
    ├── cpu_stress.sh
    ├── stop_cpu_stress.sh
    ├── verify_alert_resolution.sh
    ├── configure_email_notifications.sh
    ├── generate_alertmanager_email_config.sh
    ├── smtp-settings.example
    ├── alert_pipeline_validation.txt
    ├── webhook_alerts.log
    ├── final_alerting_validation.sh
    └── validation-report.txt

## Monitoring Services

Prometheus:

    127.0.0.1:9090

Node Exporter:

    127.0.0.1:9100

Alertmanager:

    127.0.0.1:9093

Webhook Receiver:

    127.0.0.1:8080

All monitoring endpoints are bound to the loopback interface because every component runs on the same machine.

## Alert Rules

### High CPU Usage

Triggers when average CPU utilization remains above 80 percent for two minutes.

    100 - (
      avg by(instance) (
        irate(
          node_cpu_seconds_total{
            mode="idle"
          }[5m]
        )
      ) * 100
    ) > 80

Severity:

    warning

## High Memory Usage

Triggers when memory utilization exceeds 85 percent for two minutes.

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

## Low Disk Space

Triggers when filesystem utilization exceeds 90 percent.

    (
      1 -
      (
        node_filesystem_avail_bytes{
          fstype!="tmpfs"
        }
        /
        node_filesystem_size_bytes{
          fstype!="tmpfs"
        }
      )
    ) * 100 > 90

Severity:

    critical

## Service Availability

Detects failed Prometheus scrape targets.

    up == 0

Severity:

    critical

## Alertmanager Routing

Alertmanager groups notifications using:

    alertname
    instance

Routing parameters:

    group_wait: 10s
    group_interval: 30s
    repeat_interval: 1h

The local webhook receiver is configured with:

    send_resolved: true

This allows both firing and resolved transitions to be captured.

## Webhook Receiver

The Python receiver listens on:

    127.0.0.1:8080

Incoming Alertmanager payloads are written as JSON records to:

    webhook_alerts.log

Each record contains:

- Receipt timestamp
- Request path
- Full Alertmanager payload
- Alert status
- Alert name
- Severity
- Instance
- Annotation summary

## Alert Lifecycle Validation

The CPU alert was validated using real system load.

The stress utility starts one CPU worker for each detected processor:

    ./cpu_stress.sh

The implementation then verifies:

    Linux CPU load increases
        ↓
    Prometheus CPU expression exceeds threshold
        ↓
    HighCPUUsage enters pending state
        ↓
    HighCPUUsage enters firing state
        ↓
    Prometheus exposes active alert
        ↓
    Alertmanager receives alert
        ↓
    Webhook receives firing notification

After stopping the load:

    ./stop_cpu_stress.sh

the reverse lifecycle is validated:

    CPU utilization falls
        ↓
    HighCPUUsage becomes inactive
        ↓
    Prometheus active alert disappears
        ↓
    Alertmanager resolves alert
        ↓
    Webhook receives resolved notification

## Secure SMTP Integration

Real SMTP delivery requires credentials and should not be configured by embedding passwords directly in repository files.

A safe example is included:

    smtp-settings.example

Expected structure:

    SMTP_SMARTHOST=smtp.gmail.com:587
    SMTP_FROM=your-email@gmail.com
    SMTP_USERNAME=your-email@gmail.com
    SMTP_PASSWORD=your-google-app-password
    SMTP_RECIPIENT=recipient@example.com

Create a private runtime file:

    cp smtp-settings.example smtp-settings

Then restrict its permissions:

    chmod 0600 smtp-settings

Populate actual values locally and generate the Alertmanager configuration:

    ./generate_alertmanager_email_config.sh \
      ./smtp-settings

The resulting Alertmanager configuration supports simultaneous:

    Email
    Webhook

notifications.

## Secret Protection

The repository excludes credential-bearing files:

    smtp-settings
    smtp-settings.*

while explicitly retaining:

    smtp-settings.example

This keeps the documented configuration format available without exposing passwords.

## Configuration Validation

Prometheus configuration:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml

Alert rules:

    sudo -u prometheus \
      promtool check rules \
      /etc/prometheus/alert_rules.yml

Alertmanager configuration:

    sudo -u prometheus \
      amtool check-config \
      /etc/alertmanager/alertmanager.yml

## API Verification

Prometheus targets:

    curl \
      http://127.0.0.1:9090/api/v1/targets

Alert rules:

    curl \
      http://127.0.0.1:9090/api/v1/rules

Current Prometheus alerts:

    curl \
      http://127.0.0.1:9090/api/v1/alerts

Prometheus Alertmanager discovery:

    curl \
      http://127.0.0.1:9090/api/v1/alertmanagers

Alertmanager alerts:

    curl \
      http://127.0.0.1:9093/api/v2/alerts

## Systemd Services

The following services are persistent across reboots:

    prometheus.service
    node_exporter.service
    alertmanager.service
    prometheus-webhook.service

Check their state with:

    sudo systemctl status \
      prometheus \
      node_exporter \
      alertmanager \
      prometheus-webhook

## Runtime Security

The services use dedicated identities and systemd hardening including:

- Non-root service execution
- `NoNewPrivileges`
- Private temporary directories
- Protected home directories
- Protected system paths
- Kernel protection controls
- Explicit writable storage paths
- Loopback-only network listeners
- Automatic restart on failure

Monitoring executables are owned by root rather than the runtime service identity, preventing the monitoring account from replacing its own executable binaries.

## Tools Used

- Prometheus
- PromQL
- Alertmanager
- Node Exporter
- promtool
- amtool
- Linux
- systemd
- Bash
- Python
- curl
- jq
- Git

## Key Skills Demonstrated

- Installed and configured Prometheus
- Deployed Node Exporter
- Built Prometheus alerting rules
- Defined warning and critical severity levels
- Configured rule evaluation intervals
- Integrated Prometheus with Alertmanager
- Configured Alertmanager routing and grouping
- Implemented webhook notifications
- Implemented resolved notifications
- Created a persistent webhook service
- Triggered real alerts through system load
- Validated Prometheus alert state transitions
- Validated Alertmanager alert ingestion
- Validated downstream notification delivery
- Validated alert resolution
- Built secure SMTP configuration tooling
- Protected notification credentials from Git
- Validated YAML with promtool and amtool
- Hardened monitoring services with systemd controls
- Used monitoring APIs for machine-verifiable testing

## Real-World Use Case

This architecture represents the alert-processing layer used in infrastructure monitoring, platform engineering, SRE, DevOps, and AIOps environments.

A production version can route alerts to:

- Email
- Slack
- Microsoft Teams
- PagerDuty
- Opsgenie
- Incident-management platforms
- Custom automation services
- SMS gateways
- Ticketing systems

The same design can also support multi-cluster Kubernetes monitoring or centralized infrastructure observability.

## Lessons Learned

- Successful YAML validation does not prove an alerting pipeline works end to end.
- Alert rules should be tested by creating real threshold conditions.
- The `for:` duration protects against short transient spikes.
- Prometheus determines when an alert condition is true.
- Alertmanager controls grouping, routing, repetition, and notification delivery.
- `send_resolved` is required when downstream systems need explicit recovery notifications.
- Firing and resolved notifications should both be validated.
- SMTP credentials should never be embedded in repository files.
- Service accounts should not own writable copies of their executable binaries.
- Monitoring ports should not be publicly exposed unless remote access is explicitly required.
- Alert grouping and inhibition help prevent alert fatigue.
- API-based validation is more reproducible than manual browser inspection.

## Troubleshooting

### Prometheus Does Not Start

Validate configuration:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml

Check logs:

    sudo journalctl \
      -u prometheus \
      -n 100 \
      --no-pager

## Alert Rules Do Not Load

Validate rules:

    sudo -u prometheus \
      promtool check rules \
      /etc/prometheus/alert_rules.yml

Then inspect:

    curl \
      http://127.0.0.1:9090/api/v1/rules

## Alert Remains Pending

Check whether the threshold is still continuously true for the complete `for:` duration.

Inspect the underlying expression directly through the Prometheus API.

## Alertmanager Does Not Receive Alerts

Verify Prometheus Alertmanager discovery:

    curl \
      http://127.0.0.1:9090/api/v1/alertmanagers

Check Alertmanager readiness:

    curl \
      http://127.0.0.1:9093/-/ready

## Webhook Does Not Receive Notifications

Verify service status:

    sudo systemctl status \
      prometheus-webhook

Check logs:

    sudo journalctl \
      -u prometheus-webhook \
      -n 100 \
      --no-pager

Verify the webhook directly:

    curl \
      -X POST \
      -H 'Content-Type: application/json' \
      -d '{
        "status":"firing",
        "alerts":[]
      }' \
      http://127.0.0.1:8080/alerts

## Email Delivery Fails

Check:

- SMTP server hostname and port
- SMTP username
- App Password or provider-specific credential
- TLS requirements
- Recipient address
- Firewall or outbound SMTP restrictions

For Gmail, an App Password should be used rather than the normal account password when applicable.

## Validation Result

The completed implementation validated:

    Prometheus service:                    PASS
    Node Exporter service:                 PASS
    Alertmanager service:                  PASS
    Webhook receiver service:              PASS

    Prometheus scrape targets:             2
    Healthy scrape targets:                2

    HighCPUUsage rule:                     PASS
    HighMemoryUsage rule:                  PASS
    DiskSpaceLow rule:                     PASS
    ServiceDown rule:                      PASS

    Prometheus to Alertmanager:            PASS
    Alertmanager to webhook:               PASS

    HighCPUUsage firing transition:        PASS
    Firing notification delivery:          PASS
    HighCPUUsage resolution:               PASS
    Resolved notification delivery:        PASS

    SMTP configuration tooling:            PASS
    SMTP secret protection:                PASS
    External SMTP delivery:                NOT TESTED

    Overall locally verifiable pipeline:   PASS
