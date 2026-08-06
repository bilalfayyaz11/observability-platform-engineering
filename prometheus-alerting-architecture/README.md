# Prometheus Metrics and Alerting Architecture

## What This Does

This implementation provides a complete single-node observability architecture built with Prometheus, Node Exporter, Process Exporter, and Alertmanager.

Prometheus collects infrastructure and process metrics from multiple exporters, evaluates health and resource-utilization rules, stores time-series data locally, and forwards active alerts to Alertmanager. The services are managed through hardened systemd definitions and are configured to recover automatically after failures or system restarts.

The implementation demonstrates how core Prometheus components interact in a production-style monitoring workflow, from metric exposure and collection to PromQL evaluation, alert generation, routing, and operational validation.

## Architecture

    ┌───────────────────────────────────────────────────────────────┐
    │                         Linux Host                            │
    │                                                               │
    │   ┌────────────────────┐      ┌───────────────────────────┐   │
    │   │   Node Exporter    │      │     Process Exporter      │   │
    │   │                    │      │                           │   │
    │   │ CPU                │      │ Process CPU               │   │
    │   │ Memory             │      │ Process memory            │   │
    │   │ Filesystems        │      │ Process count             │   │
    │   │ Network            │      │ Threads and descriptors   │   │
    │   │                    │      │                           │   │
    │   │ Port 9100          │      │ Port 9256                 │   │
    │   └─────────┬──────────┘      └─────────────┬─────────────┘   │
    │             │                               │                 │
    │             └───────────────┬───────────────┘                 │
    │                             │ HTTP metric scraping            │
    │                             ▼                                 │
    │                ┌──────────────────────────┐                   │
    │                │        Prometheus        │                   │
    │                │                          │                   │
    │                │ Target discovery         │                   │
    │                │ Metric collection        │                   │
    │                │ PromQL evaluation        │                   │
    │                │ Alert-rule evaluation    │                   │
    │                │ Local TSDB storage       │                   │
    │                │                          │                   │
    │                │ Port 9090                │                   │
    │                └────────────┬─────────────┘                   │
    │                             │ Active alerts                   │
    │                             ▼                                 │
    │                ┌──────────────────────────┐                   │
    │                │       Alertmanager       │                   │
    │                │                          │                   │
    │                │ Alert grouping           │                   │
    │                │ Routing                  │                   │
    │                │ Deduplication            │                   │
    │                │ Resolution tracking      │                   │
    │                │                          │                   │
    │                │ Port 9093                │                   │
    │                └──────────────────────────┘                   │
    │                                                               │
    │   Persistent data:                                            │
    │   /var/lib/prometheus                                         │
    │   /var/lib/alertmanager                                       │
    └───────────────────────────────────────────────────────────────┘

## Repository Structure

    prometheus-alerting-architecture/
    ├── README.md
    ├── prometheus/
    │   ├── prometheus.yml
    │   └── alert_rules.yml
    ├── alertmanager/
    │   └── alertmanager.yml
    ├── process-exporter/
    │   └── config.yml
    ├── systemd/
    │   ├── prometheus.service
    │   ├── node_exporter.service
    │   ├── process_exporter.service
    │   └── alertmanager.service
    ├── checksums/
    │   ├── process-exporter.sha256
    │   └── alertmanager.sha256
    └── scripts/
        └── cpu_stress.sh

## Prerequisites

The following environment and tools are required:

- Ubuntu 24.04 or another modern systemd-based Linux distribution
- Linux AMD64 architecture
- Passwordless sudo access or equivalent administrative privileges
- wget
- curl
- tar
- sha256sum
- jq
- systemd
- iproute2
- Git
- Network access to official GitHub release assets

The following ports must be available:

- `9090` for Prometheus
- `9093` for Alertmanager
- `9100` for Node Exporter
- `9256` for Process Exporter

## Setup & Installation

Create dedicated service accounts:

    sudo useradd --system --no-create-home --shell /usr/sbin/nologin prometheus
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin process_exporter
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin alertmanager

Create the required configuration and storage directories:

    sudo install -d -o root -g prometheus -m 0750 /etc/prometheus
    sudo install -d -o prometheus -g prometheus -m 0750 /var/lib/prometheus

    sudo install -d -o root -g process_exporter -m 0750 /etc/process-exporter

    sudo install -d -o root -g alertmanager -m 0750 /etc/alertmanager
    sudo install -d -o alertmanager -g alertmanager -m 0750 /var/lib/alertmanager

Install the component binaries under `/usr/local/bin`:

    sudo install -o root -g root -m 0755 prometheus /usr/local/bin/prometheus
    sudo install -o root -g root -m 0755 promtool /usr/local/bin/promtool
    sudo install -o root -g root -m 0755 node_exporter /usr/local/bin/node_exporter
    sudo install -o root -g root -m 0755 process-exporter /usr/local/bin/process-exporter
    sudo install -o root -g root -m 0755 alertmanager /usr/local/bin/alertmanager
    sudo install -o root -g root -m 0755 amtool /usr/local/bin/amtool

## How to Reproduce

Clone the repository:

    git clone https://github.com/bilalfayyaz11/observability-platform-engineering.git
    cd observability-platform-engineering/prometheus-alerting-architecture

Copy the Prometheus configuration:

    sudo cp prometheus/prometheus.yml /etc/prometheus/prometheus.yml
    sudo cp prometheus/alert_rules.yml /etc/prometheus/alert_rules.yml

    sudo chown root:prometheus \
      /etc/prometheus/prometheus.yml \
      /etc/prometheus/alert_rules.yml

    sudo chmod 0640 \
      /etc/prometheus/prometheus.yml \
      /etc/prometheus/alert_rules.yml

Copy the Process Exporter configuration:

    sudo cp process-exporter/config.yml /etc/process-exporter/config.yml
    sudo chown root:process_exporter /etc/process-exporter/config.yml
    sudo chmod 0640 /etc/process-exporter/config.yml

Copy the Alertmanager configuration:

    sudo cp alertmanager/alertmanager.yml /etc/alertmanager/alertmanager.yml
    sudo chown root:alertmanager /etc/alertmanager/alertmanager.yml
    sudo chmod 0640 /etc/alertmanager/alertmanager.yml

Install the systemd service definitions:

    sudo cp systemd/prometheus.service /etc/systemd/system/prometheus.service
    sudo cp systemd/node_exporter.service /etc/systemd/system/node_exporter.service
    sudo cp systemd/process_exporter.service /etc/systemd/system/process_exporter.service
    sudo cp systemd/alertmanager.service /etc/systemd/system/alertmanager.service

Validate all configurations:

    sudo -u prometheus promtool check config /etc/prometheus/prometheus.yml
    sudo -u prometheus promtool check rules /etc/prometheus/alert_rules.yml
    sudo -u alertmanager amtool check-config /etc/alertmanager/alertmanager.yml

Reload systemd and start the services:

    sudo systemctl daemon-reload

    sudo systemctl enable --now node_exporter
    sudo systemctl enable --now process_exporter
    sudo systemctl enable --now alertmanager
    sudo systemctl enable --now prometheus

Verify service health:

    sudo systemctl status \
      prometheus \
      node_exporter \
      process_exporter \
      alertmanager

Verify listening ports:

    sudo ss -lntp | grep -E ':(9090|9093|9100|9256)'

Verify Prometheus targets:

    curl --silent http://127.0.0.1:9090/api/v1/targets |
      jq '.data.activeTargets[] | {
        job: .labels.job,
        health: .health,
        error: .lastError
      }'

Execute a basic PromQL query:

    curl --get \
      --silent \
      --data-urlencode 'query=up' \
      http://127.0.0.1:9090/api/v1/query |
      jq '.data.result'

Verify Alertmanager connectivity:

    curl --silent \
      http://127.0.0.1:9090/api/v1/alertmanagers |
      jq '.data.activeAlertmanagers'

## Alert Rules

The Prometheus rule file contains the following infrastructure alerts:

- `InstanceDown` detects targets that remain unavailable for more than one minute
- `HighCPUUsage` detects sustained CPU utilization above 80 percent
- `HighMemoryUsage` detects sustained memory utilization above 85 percent

Each alert includes a severity label and operational annotations that identify the affected instance and condition.

## PromQL Examples

Check the health of every scrape target:

    up

Calculate average CPU usage by instance:

    100 - (
      avg by(instance) (
        rate(node_cpu_seconds_total{mode="idle"}[5m])
      ) * 100
    )

Calculate memory utilization:

    (
      1 -
      (
        node_memory_MemAvailable_bytes
        /
        node_memory_MemTotal_bytes
      )
    ) * 100

Inspect available filesystem capacity:

    node_filesystem_avail_bytes{fstype!="tmpfs"}

Inspect received network traffic:

    rate(node_network_receive_bytes_total[5m])

Inspect process-group counts:

    namedprocess_namegroup_num_procs

## Tools Used

- Prometheus
- PromQL
- Node Exporter
- Process Exporter
- Alertmanager
- promtool
- amtool
- systemd
- Linux
- Bash
- curl
- wget
- jq
- SHA-256 checksums
- Git

## Key Skills Demonstrated

- Designed a multi-component Prometheus monitoring architecture
- Configured multiple metric exporters and scrape targets
- Built PromQL expressions for infrastructure analysis
- Implemented health, CPU, and memory alert rules
- Integrated Prometheus with Alertmanager
- Validated configuration before service deployment
- Created hardened systemd service definitions
- Diagnosed service startup and port-listening failures
- Performed API-driven target and alert validation
- Tested the complete metric-to-alert lifecycle
- Managed persistent time-series and Alertmanager state
- Applied checksum validation and release-integrity controls

## Real-World Use Case

This architecture can be used as the monitoring foundation for application servers, internal platforms, machine-learning inference hosts, CI workers, data-processing nodes, and cloud infrastructure. Operations teams can use it to identify unavailable services, resource saturation, process-level anomalies, and capacity risks before they cause user-facing failures. The same design can later be extended with service discovery, Grafana dashboards, remote storage, authenticated endpoints, notification integrations, and high-availability Prometheus instances.

## Lessons Learned

- A systemd service can briefly report active before its application has successfully opened the expected network port, so service state and socket state must both be validated.
- Enabling `set -euo pipefail` directly in an interactive SSH shell can terminate the entire remote session when a diagnostic command returns a legitimate nonzero status.
- Commands such as `grep` return exit code `1` when no match is found, which must be handled explicitly during diagnostics.
- Piping a long-running `curl` response into `head` can produce a false `curl: (23)` failure when the downstream process closes the pipe early.
- Referencing an alert-rule file before creating it can prevent Prometheus configuration validation or startup.
- Exporter and Alertmanager release assets do not always expose checksums through the same upstream mechanism.
- A configured webhook receiver must correspond to a real service; otherwise, Alertmanager generates repeated notification failures.
- Alert testing should use controlled workloads with recorded process IDs and automatic cleanup.

## Troubleshooting Log

### Interactive SSH sessions closed unexpectedly

The shell had been configured with:

    set -euo pipefail

A diagnostic `grep` command returned exit status `1` when port `9256` was not immediately visible. Because `set -e` was active in the interactive shell, Bash terminated the shell and closed the SSH connection.

The safer interactive approach is:

    set +e
    set +u
    set +o pipefail

Potentially empty diagnostic results should be handled explicitly:

    if sudo ss -lntp | grep -E ':9256([[:space:]]|$)'; then
        echo "Port 9256 is listening"
    else
        echo "Port 9256 is not listening"
    fi

### Metrics inspection produced curl error 23

The following pattern can fail under `pipefail`:

    curl http://127.0.0.1:9100/metrics | head -20

`head` exits after receiving the requested lines and closes the pipe. Curl then reports a write failure.

The corrected pattern is:

    curl --silent http://127.0.0.1:9100/metrics |
      sed -n '1,20p'

### Process Exporter digest was unavailable

The Process Exporter release asset did not expose a usable SHA-256 digest through the GitHub release API. The archive was validated structurally and a local reproducibility checksum was recorded:

    sha256sum process-exporter-0.8.7.linux-amd64.tar.gz

This checksum provides a reproducibility baseline but is not equivalent to independently authenticated publisher verification.

### Invalid webhook destination

The original Alertmanager receiver pointed to a local webhook on port `5001`, but no webhook service was present. A local null receiver was used to validate grouping, routing, alert ingestion, and resolution without generating failed delivery attempts.

### Prometheus rule-file startup dependency

The main Prometheus configuration referenced `alert_rules.yml`. A valid placeholder rule file was created before Prometheus startup and later replaced with the complete infrastructure rule group.

### Deprecated component versions

Outdated Prometheus, Node Exporter, Process Exporter, and Alertmanager versions were replaced with current stable releases available during implementation.

## Security Considerations

The systemd services run as dedicated non-login accounts with restricted privileges.

Service protections include:

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `ProtectHome=true`
- `ProtectSystem=strict`
- Restricted write access to persistent storage directories
- Kernel and control-group protections for exporters
- Root-owned binaries under `/usr/local/bin`
- Group-restricted configuration files

For production deployment, the following should also be added:

- TLS for web interfaces and metric endpoints
- Authentication and authorization
- Firewall restrictions
- Private network exposure
- Secrets management
- Real notification receivers
- Remote durable storage
- Redundant Prometheus and Alertmanager instances
- Configuration delivery through GitOps or infrastructure automation
