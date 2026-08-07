# Prometheus Multi-Exporter Observability Stack

## What This Does

This implementation provides a multi-source infrastructure observability stack built around Prometheus.

The architecture integrates Node Exporter for Linux host telemetry, MySQL Exporter for database monitoring, and Blackbox Exporter for synthetic HTTP and TCP probing.

Prometheus collects metrics from each exporter at regular intervals and provides a unified query layer for system performance, database behavior, service availability, and endpoint connectivity.

The implementation goes beyond static installation checks. Synthetic workloads are generated for CPU, memory, disk I/O, and MySQL activity so that metric changes can be observed and validated through Prometheus.

Reusable monitoring scripts and a unified terminal dashboard provide an operational view across all telemetry sources.

## Architecture

    ┌───────────────────────────────────────────────────────────────┐
    │                         Linux Host                            │
    │                                                               │
    │  ┌──────────────────────┐                                    │
    │  │    Linux Kernel      │                                    │
    │  │    systemd           │                                    │
    │  │    Filesystems       │                                    │
    │  │    Network Stack     │                                    │
    │  └──────────┬───────────┘                                    │
    │             │                                                 │
    │             ▼                                                 │
    │  ┌──────────────────────┐                                    │
    │  │    Node Exporter     │                                    │
    │  │  127.0.0.1:9100     │                                    │
    │  └──────────┬───────────┘                                    │
    │             │                                                 │
    │             │                                                 │
    │  ┌──────────▼───────────┐                                    │
    │  │        MySQL         │                                    │
    │  │  127.0.0.1:3306     │                                    │
    │  └──────────┬───────────┘                                    │
    │             │                                                 │
    │             ▼                                                 │
    │  ┌──────────────────────┐                                    │
    │  │   MySQL Exporter     │                                    │
    │  │  127.0.0.1:9104     │                                    │
    │  └──────────┬───────────┘                                    │
    │             │                                                 │
    │             │                                                 │
    │  ┌──────────▼───────────┐                                    │
    │  │  Blackbox Exporter   │◄──── HTTP/TCP probe targets        │
    │  │  127.0.0.1:9115     │                                    │
    │  └──────────┬───────────┘                                    │
    │             │                                                 │
    │             └────────────────────┐                            │
    │                                  │                            │
    │                Node Exporter ─────┤                            │
    │                MySQL Exporter ────┤                            │
    │                Blackbox HTTP ─────┤                            │
    │                Blackbox TCP ──────┤                            │
    │                                  ▼                            │
    │                    ┌──────────────────────┐                   │
    │                    │     Prometheus       │                   │
    │                    │  127.0.0.1:9090     │                   │
    │                    │                      │                   │
    │                    │  Scraping            │                   │
    │                    │  Time-series storage │                   │
    │                    │  PromQL              │                   │
    │                    └──────────┬───────────┘                   │
    │                               │                               │
    │                               ▼                               │
    │                Monitoring Scripts + Dashboard                 │
    └───────────────────────────────────────────────────────────────┘

## Repository Structure

    prometheus-multi-exporter-observability/
    ├── README.md
    ├── system_monitor.sh
    ├── mysql_monitor.sh
    ├── connectivity_monitor.sh
    ├── monitoring_dashboard.sh
    ├── generate_load.sh
    ├── final_exporter_validation.sh
    ├── monitoring_script_validation.txt
    ├── workload_validation.txt
    ├── dashboard_validation.txt
    └── validation-report.txt

## Prometheus

Prometheus provides the centralized metrics collection and query layer.

Local endpoint:

    127.0.0.1:9090

The configuration includes the following jobs:

    prometheus
    node_exporter
    mysql_exporter
    blackbox_http
    blackbox_tcp

The scrape interval is configured at:

    15 seconds

## Node Exporter

Node Exporter runs on:

    127.0.0.1:9100

It provides Linux host telemetry covering:

- CPU
- Memory
- Filesystem
- Disk I/O
- Network
- Load average
- systemd service state

Examples:

    node_cpu_seconds_total

    node_memory_MemAvailable_bytes

    node_disk_read_bytes_total

    node_disk_written_bytes_total

    node_network_receive_bytes_total

    node_systemd_unit_state

## CPU Utilization

CPU utilization is calculated by subtracting idle time from 100 percent:

    100 - (
      avg by(instance) (
        rate(
          node_cpu_seconds_total{
            mode="idle"
          }[5m]
        )
      ) * 100
    )

## Memory Utilization

Memory utilization is calculated using available and total memory:

    (
      1 -
      (
        node_memory_MemAvailable_bytes
        /
        node_memory_MemTotal_bytes
      )
    ) * 100

## Disk Throughput

Disk write throughput:

    sum(
      rate(
        node_disk_written_bytes_total[5m]
      )
    )

Disk read throughput:

    sum(
      rate(
        node_disk_read_bytes_total[5m]
      )
    )

## MySQL Monitoring

MySQL runs locally on:

    127.0.0.1:3306

MySQL Exporter runs on:

    127.0.0.1:9104

A dedicated monitoring account is used with the permissions required to expose database status and performance metrics.

The exporter credential is stored in:

    /etc/mysql_exporter.cnf

with restrictive permissions.

## MySQL Metrics

Database availability:

    mysql_up

Current connections:

    mysql_global_status_threads_connected

Database uptime:

    mysql_global_status_uptime

Total query count:

    mysql_global_status_queries

Query throughput:

    rate(
      mysql_global_status_queries[5m]
    )

## Database Activity Validation

A dedicated database named:

    testdb

was created along with an activity table.

Real INSERT and SELECT operations were generated so that MySQL metrics could be validated against actual database activity.

The validation confirms:

    MySQL connectivity
        ↓
    Database operations
        ↓
    MySQL internal counters change
        ↓
    MySQL Exporter exposes metrics
        ↓
    Prometheus scrapes exporter
        ↓
    PromQL observes database activity

## Blackbox Exporter

Blackbox Exporter runs on:

    127.0.0.1:9115

It provides synthetic monitoring using probe modules rather than direct application metrics.

Configured modules include:

    http_2xx
    tcp_connect
    icmp

## HTTP Probing

HTTP targets are passed to Blackbox Exporter using Prometheus relabeling.

The original target becomes:

    __param_target

while Prometheus sends the actual scrape request to:

    127.0.0.1:9115

Example local HTTP target:

    http://127.0.0.1:9090/-/ready

External test targets include:

    https://github.com
    https://www.google.com

Probe status is exposed through:

    probe_success

A value of:

    1

means the probe succeeded.

A value of:

    0

means the probe failed.

## TCP Probing

TCP probes validate whether application ports can accept connections.

Configured local targets include:

    127.0.0.1:3306
    127.0.0.1:9090
    127.0.0.1:9104

These verify:

    MySQL
    Prometheus
    MySQL Exporter

## Prometheus Relabeling Pattern

The Blackbox Exporter integration uses a standard multi-target exporter design.

Conceptually:

    Original target
          ↓
    __address__
          ↓
    __param_target
          ↓
    instance label
          ↓
    scrape destination replaced with
    127.0.0.1:9115

This allows Prometheus to probe multiple endpoints through one exporter process while preserving the original target as the metric instance.

## System Monitoring Script

Run:

    ./system_monitor.sh

The report provides:

- CPU utilization
- Memory utilization
- Available memory
- One-minute load average

Example structure:

    SYSTEM MONITORING REPORT

    CPU usage:
      4.21%

    Memory usage:
      9.85%

    Available memory:
      13.72 GiB

    1-minute load average:
      0.18

## MySQL Monitoring Script

Run:

    ./mysql_monitor.sh

The report includes:

- MySQL availability
- Active connections
- Uptime
- Query throughput

Example:

    MYSQL MONITORING REPORT

    MySQL: UP
    Active connections: 2
    Uptime: 1h 14m 21s
    Query throughput: 3.12 queries/sec

## Connectivity Monitoring Script

Run:

    ./connectivity_monitor.sh

The report separates HTTP and TCP monitoring.

Example:

    HTTP ENDPOINTS

    http://127.0.0.1:9090/-/ready: REACHABLE
    https://github.com: REACHABLE

    TCP ENDPOINTS

    127.0.0.1:3306: OPEN
    127.0.0.1:9090: OPEN
    127.0.0.1:9104: OPEN

The script distinguishes between:

    REACHABLE
    UNREACHABLE
    NO DATA

and:

    OPEN
    CLOSED
    NO DATA

This prevents missing Prometheus data from being incorrectly interpreted as an endpoint failure.

## Unified Monitoring Dashboard

Run:

    ./monitoring_dashboard.sh

The dashboard combines:

- CPU utilization
- Memory utilization
- Load average
- Disk throughput
- MySQL availability
- MySQL connections
- MySQL uptime
- MySQL query throughput
- systemd service states
- Prometheus scrape target health
- HTTP probe status
- TCP probe status

This provides a single operational view across multiple telemetry domains.

## Dynamic Workload Validation

Static metrics only prove that exporters can expose data.

This implementation also generates controlled workload changes and verifies that monitoring data responds accordingly.

Run:

    ./generate_load.sh

The workload includes:

    CPU
        multiple yes workers

    Memory
        stress-ng memory workload

    Disk
        temporary write workload

The process automatically removes temporary resources after execution.

## CPU Response Validation

CPU utilization is captured before and during synthetic load.

The validation requires:

    loaded CPU > baseline CPU

This proves Node Exporter and Prometheus detect a real system-state change.

## Memory Response Validation

Memory utilization is captured before and during a controlled memory workload.

The validation requires:

    loaded memory > baseline memory

## Disk Response Validation

Disk write metrics are inspected while a real write operation is running.

The validation requires observed disk throughput to be greater than zero.

## MySQL Activity Response

Database activity is generated through repeated SQL operations.

The monitoring stack verifies:

    mysql_up == 1

and confirms that:

    mysql_global_status_queries

and:

    rate(mysql_global_status_queries[...])

reflect active database traffic.

## Service Management

The required persistent services are:

    prometheus.service
    node_exporter.service
    mysql.service
    mysql_exporter.service
    blackbox_exporter.service

Verify them with:

    sudo systemctl status \
      prometheus \
      node_exporter \
      mysql \
      mysql_exporter \
      blackbox_exporter

## Runtime Security

The exporter architecture uses several security improvements.

### Loopback Binding

Metrics and control endpoints are bound locally:

    127.0.0.1:9090
    127.0.0.1:9100
    127.0.0.1:9104
    127.0.0.1:9115

MySQL is also accessed locally.

This avoids exposing internal observability endpoints unnecessarily.

### Dedicated Service Accounts

Separate runtime identities are used for:

    prometheus
    node_exporter
    mysql_exporter
    blackbox_exporter

### Root-Owned Executables

Monitoring binaries remain:

    root:root
    0755

Runtime identities therefore cannot modify or replace their own executable files.

### MySQL Credential Protection

The MySQL exporter credential file is restricted to the exporter service identity.

The generated exporter password is not stored in repository artifacts.

## Systemd Hardening

Exporter services use systemd security controls including:

- `NoNewPrivileges`
- `PrivateTmp`
- `ProtectHome`
- `ProtectSystem`
- `ProtectControlGroups`
- `ProtectKernelModules`
- `ProtectKernelTunables`
- Automatic restart on process failure

## Configuration Validation

Prometheus configuration can be checked with:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml

Blackbox Exporter configuration is validated before the service starts.

## Prometheus Target Validation

Retrieve all scrape targets:

    curl \
      http://127.0.0.1:9090/api/v1/targets

Expected Prometheus jobs include:

    prometheus
    node_exporter
    mysql_exporter
    blackbox_http
    blackbox_tcp

## Exporter Endpoint Validation

Node Exporter:

    curl \
      http://127.0.0.1:9100/metrics

MySQL Exporter:

    curl \
      http://127.0.0.1:9104/metrics

Blackbox Exporter:

    curl \
      http://127.0.0.1:9115/metrics

## Manual Blackbox Probe

Example HTTP probe:

    curl \
      --get \
      --data-urlencode \
      'target=http://127.0.0.1:9090/-/ready' \
      --data-urlencode \
      'module=http_2xx' \
      http://127.0.0.1:9115/probe

Example TCP probe:

    curl \
      --get \
      --data-urlencode \
      'target=127.0.0.1:3306' \
      --data-urlencode \
      'module=tcp_connect' \
      http://127.0.0.1:9115/probe

## Tools Used

- Prometheus
- PromQL
- Node Exporter
- MySQL
- MySQL Exporter
- Blackbox Exporter
- Linux
- systemd
- Bash
- Python
- curl
- jq
- stress-ng
- Git

## Key Skills Demonstrated

- Deployed multiple Prometheus exporters
- Integrated heterogeneous telemetry sources
- Configured Linux host monitoring
- Configured MySQL monitoring
- Created a restricted database monitoring account
- Protected exporter credentials
- Configured HTTP synthetic monitoring
- Configured TCP synthetic monitoring
- Implemented Prometheus relabeling
- Queried exporter metrics through PromQL
- Validated scrape target health
- Created reusable operational monitoring scripts
- Built a unified terminal observability dashboard
- Generated controlled CPU workload
- Generated controlled memory workload
- Generated controlled disk workload
- Generated real MySQL activity
- Correlated workload changes with telemetry
- Hardened systemd services
- Restricted exporter network exposure
- Automated end-to-end observability validation

## Real-World Use Case

This architecture demonstrates how Prometheus can aggregate telemetry from systems that expose fundamentally different operational signals.

Node Exporter answers questions such as:

    Is the host CPU saturated?
    How much memory is available?
    Is disk activity increasing?
    What services are running?

MySQL Exporter answers questions such as:

    Is the database reachable?
    How many clients are connected?
    How long has MySQL been running?
    How quickly are queries being executed?

Blackbox Exporter answers questions such as:

    Is an HTTP endpoint reachable?
    Does it return a successful response?
    Is a TCP port accepting connections?

Together, these signals provide complementary views of infrastructure health.

The same architecture can be extended to exporters for:

- PostgreSQL
- Redis
- NGINX
- Apache
- Kafka
- RabbitMQ
- Kubernetes
- Hardware platforms
- Network devices
- Cloud services
- Custom applications

## Lessons Learned

- Prometheus itself does not need native knowledge of every monitored service.
- Exporters translate service-specific telemetry into Prometheus-compatible metrics.
- Different exporters solve different observability problems.
- Node Exporter provides host-level visibility.
- MySQL Exporter provides database-specific visibility.
- Blackbox Exporter measures a service externally through probes.
- HTTP and TCP probe success are different from exporter scrape health.
- Prometheus relabeling is fundamental to multi-target exporters such as Blackbox Exporter.
- Missing monitoring data should not automatically be interpreted as a service failure.
- Static metrics prove collection; workload-based testing proves responsiveness.
- Database monitoring should be validated using real database activity.
- Credentials should be generated securely and excluded from repository artifacts.
- Runtime service accounts should not own writable executable binaries.
- Internal monitoring interfaces should remain private unless remote access is required.
- A unified dashboard can combine metrics from unrelated exporters through PromQL.

## Troubleshooting

### Node Exporter Is Not Scraped

Check:

    sudo systemctl status node_exporter

Test directly:

    curl \
      http://127.0.0.1:9100/metrics

Check Prometheus target health:

    curl \
      http://127.0.0.1:9090/api/v1/targets

## MySQL Exporter Reports mysql_up 0

Inspect logs:

    sudo journalctl \
      -u mysql_exporter \
      -n 100 \
      --no-pager

Verify MySQL:

    sudo systemctl status mysql

Test exporter credentials using the protected MySQL configuration file.

Verify grants:

    sudo mysql \
      -e "SHOW GRANTS FOR 'exporter'@'localhost';"

## MySQL Metrics Are Missing

Check:

    curl \
      http://127.0.0.1:9104/metrics

Then query:

    mysql_up

inside Prometheus.

If `mysql_up` is `1` but a particular collector metric is absent, verify that the installed exporter version exposes that collector and that the monitoring account has the necessary privilege.

## Blackbox Probe Fails

Probe directly:

    curl \
      --get \
      --data-urlencode \
      'target=http://127.0.0.1:9090/-/ready' \
      --data-urlencode \
      'module=http_2xx' \
      http://127.0.0.1:9115/probe

Inspect:

    probe_success
    probe_duration_seconds
    probe_http_status_code

## External Probe Fails but Local Probes Work

External HTTP probes depend on outbound Internet access and remote endpoint behavior.

A failed external target does not necessarily indicate a Blackbox Exporter configuration failure if local controlled probes continue to return:

    probe_success 1

## Prometheus Cannot Scrape an Exporter

Validate:

    service is active
        ↓
    expected port is listening
        ↓
    local metrics endpoint works
        ↓
    Prometheus configuration is valid
        ↓
    Prometheus target is healthy

## Rate Query Returns No Data

Queries such as:

    rate(metric[5m])

require multiple samples inside the selected range.

Immediately after startup, Prometheus may not yet contain enough historical samples.

## Final Validation

Run:

    ./final_exporter_validation.sh

The final validator checks:

- All required systemd services
- Listening ports
- Prometheus readiness
- Exporter HTTP endpoints
- Prometheus configuration
- Scrape jobs
- Node Exporter metrics
- MySQL Exporter metrics
- MySQL availability
- MySQL query-rate data
- Blackbox HTTP probes
- Blackbox TCP probes
- Local required probes
- Database state
- Generated activity records
- Monitoring script syntax
- Validation evidence
- Unified dashboard functionality

## Validation Result

The completed implementation validated:

    Prometheus:                         PASS
    Node Exporter:                     PASS
    MySQL:                             PASS
    MySQL Exporter:                    PASS
    Blackbox Exporter:                 PASS

    Prometheus endpoint:               PASS
    Node Exporter endpoint:            PASS
    MySQL Exporter endpoint:           PASS
    Blackbox Exporter endpoint:        PASS

    Prometheus scrape job:             PASS
    Node Exporter scrape job:          PASS
    MySQL Exporter scrape job:         PASS
    Blackbox HTTP scrape job:          PASS
    Blackbox TCP scrape job:           PASS

    CPU telemetry:                     PASS
    Memory telemetry:                  PASS
    Disk telemetry:                    PASS
    Network telemetry:                 PASS
    systemd telemetry:                 PASS

    MySQL availability:                PASS
    MySQL connections:                 PASS
    MySQL uptime:                      PASS
    MySQL query metrics:               PASS
    MySQL query-rate metrics:          PASS

    Local Prometheus HTTP probe:       PASS
    MySQL TCP probe:                   PASS
    Prometheus TCP probe:              PASS
    MySQL Exporter TCP probe:          PASS

    CPU workload response:             PASS
    Memory workload response:          PASS
    Disk workload response:            PASS
    Database activity response:        PASS

    System monitoring interface:       PASS
    MySQL monitoring interface:        PASS
    Connectivity monitoring interface: PASS
    Unified observability dashboard:   PASS

    Overall multi-exporter stack:      PASS
