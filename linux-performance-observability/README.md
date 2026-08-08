# Linux Performance Observability

## What This Does

This implementation provides a reproducible performance observability environment for Linux systems using Prometheus, Node Exporter, Grafana, PromQL, controlled workload generation, and automated performance interpretation.

The system collects CPU, memory, filesystem, disk I/O, load, context-switch, and network telemetry from a Linux host. Prometheus stores and analyzes those time series, while Grafana presents the data through provisioned dashboards rather than manually configured UI state.

The environment also generates controlled CPU, memory, disk, and network activity so that performance behavior can be observed under pressure rather than only at idle.

Alert rules are validated and deliberately exercised to prove that sustained CPU, memory, and composite resource pressure can be detected and that alerts recover after the workload ends.

The result is a compact performance engineering environment useful for SRE, Platform Engineering, AIOps, DevOps, production infrastructure, and systems performance analysis.


## Architecture

    ┌─────────────────────────────────────────────────────┐
    │                    Linux Host                       │
    │                                                     │
    │   CPU        Memory        Disk        Network       │
    │    │            │            │            │          │
    │    └────────────┴────────────┴────────────┘          │
    │                         │                           │
    └─────────────────────────┼───────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Node Exporter   │
                    │ 127.0.0.1:9100   │
                    └────────┬─────────┘
                             │
                             │ scrape every 15s
                             ▼
                    ┌──────────────────┐
                    │    Prometheus    │
                    │ 127.0.0.1:9090   │
                    │                  │
                    │ PromQL           │
                    │ Alert Rules      │
                    │ Baselines        │
                    └────────┬─────────┘
                             │
                             │ provisioned datasource
                             ▼
                    ┌──────────────────┐
                    │      Grafana     │
                    │ 127.0.0.1:3000   │
                    ├──────────────────┤
                    │ System Overview  │
                    │ CPU Analysis     │
                    │ Network Analysis │
                    └──────────────────┘


## Components

### Prometheus

Prometheus provides time-series collection, query execution, alert evaluation, and performance baseline analysis.

The configuration scrapes:

    prometheus
    node-exporter

The environment uses lifecycle reloads so configuration changes can be applied without restarting the Prometheus process.


### Node Exporter

Node Exporter exposes Linux host telemetry including:

- CPU time by mode
- memory capacity and availability
- filesystem capacity
- disk read and write activity
- network traffic
- packet errors
- packet drops
- system load
- context switches


### Grafana

Grafana provides visualization of the Prometheus data.

The Prometheus datasource is provisioned automatically from YAML rather than created manually.

Three dashboards are provisioned from JSON:

    System Performance Overview

    CPU Performance Analysis

    Network Performance Analysis


## Directory Layout

    ~/performance-observability/
    ├── configs/
    │   ├── prometheus.yml
    │   ├── prometheus-with-alerts.yml
    │   ├── prometheus-production.yml
    │   ├── performance-alerts.yml
    │   ├── performance-alerts-production.yml
    │   ├── grafana-prometheus-datasource.yml
    │   └── grafana-dashboard-provider.yml
    │
    ├── dashboards/
    │   ├── system-performance-overview.json
    │   ├── cpu-performance-analysis.json
    │   └── network-performance-analysis.json
    │
    ├── queries/
    │   ├── performance-promql.txt
    │   ├── query-definitions.tsv
    │   ├── baseline-promql.txt
    │   └── short-window-baselines.tsv
    │
    ├── scripts/
    │   └── test-promql.sh
    │
    ├── services/
    │   ├── prometheus.service
    │   ├── node_exporter.service
    │   └── grafana-server-override.conf
    │
    ├── evidence/
    │   ├── task1-targets.tsv
    │   ├── task3-query-validation.tsv
    │   ├── task4-performance-comparison.txt
    │   ├── task5-alerts-during-load.json
    │   ├── task6-short-window-baselines.tsv
    │   ├── task6-production-query-validation.tsv
    │   ├── task6-performance-interpretation.txt
    │   ├── final-prometheus-targets.tsv
    │   ├── version-inventory.txt
    │   └── final-validation.txt
    │
    └── README.md


## Prerequisites

The environment was implemented on Ubuntu Linux with:

- systemd
- Prometheus
- PromQL
- Node Exporter
- Grafana
- stress-ng
- Bash
- curl
- jq
- Python 3
- standard Linux networking utilities


## Prometheus Scrape Configuration

Prometheus collects metrics from itself and Node Exporter.

Representative configuration:

    scrape_configs:

      - job_name: prometheus

        static_configs:

          - targets:
              - 127.0.0.1:9090


      - job_name: node-exporter

        static_configs:

          - targets:
              - 127.0.0.1:9100


Keeping the services on localhost minimizes unnecessary network exposure when every component runs on the same machine.


## CPU Analysis

### Overall CPU Usage

    100 - (
      avg by(instance) (
        rate(
          node_cpu_seconds_total{
            job="node-exporter",
            mode="idle"
          }[1m]
        )
      ) * 100
    )


### CPU Usage by Core

    100 - (
      avg by(instance, cpu) (
        rate(
          node_cpu_seconds_total{
            job="node-exporter",
            mode="idle"
          }[1m]
        )
      ) * 100
    )


### CPU Usage by Mode

    sum by(instance, mode) (
      rate(
        node_cpu_seconds_total{
          job="node-exporter"
        }[1m]
      )
    ) * 100


### CPU I/O Wait

    avg by(instance) (
      rate(
        node_cpu_seconds_total{
          job="node-exporter",
          mode="iowait"
        }[1m]
      )
    ) * 100


I/O wait is particularly useful when distinguishing CPU saturation from storage-related contention.


## Load Analysis

The environment monitors:

    node_load1
    node_load5
    node_load15


This allows short-term and longer-term system pressure to be compared instead of relying on a single instantaneous value.


## Context Switch Analysis

    rate(
      node_context_switches_total{
        job="node-exporter"
      }[1m]
    )


Context-switch rates can help identify scheduling pressure and workloads with high process or thread churn.


## Memory Analysis

### Memory Utilization

    (
      1 -
      (
        node_memory_MemAvailable_bytes
        /
        node_memory_MemTotal_bytes
      )
    ) * 100


Using `MemAvailable` is more useful than relying only on `MemFree`, because Linux intentionally uses otherwise idle memory for buffers and page cache.


### Available Memory

    node_memory_MemAvailable_bytes


### Total Memory

    node_memory_MemTotal_bytes


### Cache and Buffers

    node_memory_Cached_bytes

    node_memory_Buffers_bytes


## Safe Swap Analysis

The host used for validation had no configured swap.

A direct calculation such as:

    used_swap / total_swap

would therefore divide by zero.

The implementation uses:

    (
      node_memory_SwapTotal_bytes
      -
      node_memory_SwapFree_bytes
    )
    /
    clamp_min(
      node_memory_SwapTotal_bytes,
      1
    )
    * 100


This safely evaluates to zero when no swap exists.


## Filesystem Analysis

Root filesystem usage:

    100 *
    (
      1 -
      (
        node_filesystem_avail_bytes{
          mountpoint="/",
          fstype!~"tmpfs|overlay|squashfs|nsfs|ramfs"
        }
        /
        node_filesystem_size_bytes{
          mountpoint="/",
          fstype!~"tmpfs|overlay|squashfs|nsfs|ramfs"
        }
      )
    )


Pseudo and temporary filesystems are excluded from capacity analysis.


## Disk I/O Analysis

### Read Throughput

    rate(
      node_disk_read_bytes_total[1m]
    )


### Write Throughput

    rate(
      node_disk_written_bytes_total[1m]
    )


### Disk Busy Time

    rate(
      node_disk_io_time_seconds_total[1m]
    ) * 100


These measurements can be correlated with CPU I/O wait to identify storage pressure.


## Network Analysis

### Receive Throughput

    rate(
      node_network_receive_bytes_total{
        device!="lo"
      }[1m]
    )


### Transmit Throughput

    rate(
      node_network_transmit_bytes_total{
        device!="lo"
      }[1m]
    )


### Receive Packets

    rate(
      node_network_receive_packets_total{
        device!="lo"
      }[1m]
    )


### Transmit Packets

    rate(
      node_network_transmit_packets_total{
        device!="lo"
      }[1m]
    )


### Receive Errors

    rate(
      node_network_receive_errs_total{
        device!="lo"
      }[1m]
    )


### Transmit Errors

    rate(
      node_network_transmit_errs_total{
        device!="lo"
      }[1m]
    )


### Packet Drops

    rate(
      node_network_receive_drop_total{
        device!="lo"
      }[1m]
    )

    rate(
      node_network_transmit_drop_total{
        device!="lo"
      }[1m]
    )


Network errors and packet drops should normally remain close to zero and are useful indicators of network congestion, interface problems, or upstream issues.


## Resource Pressure Index

CPU, memory, and root filesystem utilization are combined into a weighted resource pressure metric.

Weights:

    CPU        40%
    Memory     40%
    Filesystem 20%


The important semantic detail is:

    higher value = greater pressure


It is therefore described as a Resource Pressure Index rather than a health score.

This avoids the confusing situation where a metric named "health" becomes larger when system conditions worsen.


## Grafana Provisioning

Grafana receives its Prometheus datasource through:

    /etc/grafana/provisioning/datasources/


Dashboard definitions are provisioned from:

    /etc/grafana/provisioning/dashboards/


This means the visual monitoring configuration can be reproduced without manually rebuilding dashboards.


## System Performance Overview

The overview dashboard includes:

- CPU usage
- memory usage
- root filesystem usage
- system load
- CPU I/O wait
- Resource Pressure Index


The dashboard provides a compact view of the primary infrastructure pressure signals.


## CPU Performance Analysis

The CPU-focused dashboard includes:

- CPU usage by core
- CPU usage by mode
- 1 / 5 / 15 minute load averages
- context switches per second
- I/O wait


This makes it easier to distinguish CPU saturation, scheduler activity, kernel load, and storage-related stalls.


## Network Performance Analysis

The network dashboard includes:

- receive and transmit throughput
- packet rates
- receive and transmit errors
- dropped packets


The loopback interface is excluded so internal localhost traffic does not distort the useful host network view.


## Dashboard Variables

Each Grafana dashboard includes an:

    instance

variable.

The variable is generated from Prometheus labels and allows the same dashboard definition to scale to additional Node Exporter targets.


## Time Controls

Dashboards use:

    default range: 5 minutes
    refresh:       10 seconds


Additional selectable refresh intervals are provisioned for interactive analysis.


## Controlled Performance Testing

Idle metrics alone do not prove that monitoring responds correctly to changing workload behavior.

The implementation generates bounded activity for:

    CPU
    memory
    disk
    network


### CPU and Memory

`stress-ng` creates temporary CPU and memory pressure.


### Disk

A bounded file write generates filesystem and disk activity.


### Network

A bounded release archive download creates measurable inbound traffic without downloading an unnecessarily large operating-system image.


Temporary files are removed after the test.


## Before / During / After Analysis

Performance evidence is captured at three points:

    baseline
       ↓
    workload active
       ↓
    recovery


Metrics compared include:

    CPU usage
    memory usage
    load average
    network throughput


This demonstrates that the telemetry system can observe actual state changes rather than simply expose static counters.


## Alerting

### High CPU Usage

The rule detects sustained CPU utilization above the validation threshold.


### High Memory Usage

The rule detects sustained memory utilization above the validation threshold.


### Disk Space Low

The rule detects root filesystem utilization above the configured capacity threshold.


### High Resource Pressure

The rule evaluates the composite CPU, memory, and filesystem pressure expression.


## Controlled Alert Validation

The validation sequence is:

    normal system
         ↓
    CPU + memory pressure generated
         ↓
    Prometheus evaluates rules
         ↓
    HighCPUUsage FIRING
    HighMemoryUsage FIRING
    HighResourcePressure FIRING
         ↓
    controlled workload ends
         ↓
    metrics recover
         ↓
    alerts recover


This verifies both threshold detection and recovery behavior.


## Prometheus Configuration Reload

Prometheus is started with:

    --web.enable-lifecycle


Configuration changes are applied through:

    POST /-/reload


The Prometheus process ID is checked before and after reload.

Matching process IDs prove that configuration updates were applied without restarting the monitoring process.


## Query Validation

PromQL expressions are tested directly against the Prometheus HTTP API before they are treated as usable monitoring queries.

The reusable validation script checks:

- CPU usage
- memory usage
- filesystem usage
- I/O wait
- network throughput


A broader query inventory validates the full performance query library.


## Baseline Analysis

Performance baselines are important because infrastructure behavior must be compared against what is normal for that system rather than interpreted only from generic thresholds.


### Production CPU Baseline

    avg_over_time(
      (
        100 -
        (
          avg by(instance) (
            rate(
              node_cpu_seconds_total{
                mode="idle"
              }[5m]
            )
          ) * 100
        )
      )[24h:5m]
    )


### Production Peak Memory

    max_over_time(
      (
        (
          1 -
          (
            node_memory_MemAvailable_bytes
            /
            node_memory_MemTotal_bytes
          )
        ) * 100
      )[24h:5m]
    )


### Production Network Baseline

A 24-hour subquery calculates average network throughput over a meaningful historical window.


## Fresh-Environment Baseline Handling

A newly started host does not contain 24 hours of history.

The implementation therefore separates:

    production baseline queries

from:

    currently available short-window measurements


The 24-hour expressions are retained and validated for production use, while actual analysis in the temporary environment uses the historical data that genuinely exists.

This prevents misleading claims based on nonexistent historical telemetry.


## Automated Performance Interpretation

Current telemetry is interpreted into operational states.

Example categories include:

    normal
    warning
    critical


The interpretation considers:

- CPU utilization
- memory utilization
- filesystem utilization
- CPU I/O wait
- load average
- network throughput
- Resource Pressure Index


Examples:

    high CPU + low I/O wait
        → likely compute pressure

    high I/O wait
        → investigate storage activity

    low available memory
        → investigate memory pressure

    filesystem above capacity threshold
        → investigate disk consumption


## Performance Investigation Workflow

A practical investigation sequence is:

    alert or degradation
           ↓
    inspect CPU utilization
           ↓
    inspect load
           ↓
    inspect memory availability
           ↓
    inspect I/O wait
           ↓
    inspect disk throughput
           ↓
    inspect network errors / drops
           ↓
    correlate across time


The important idea is that no single metric should normally be interpreted in isolation.


## Configuration Validation

Prometheus configuration:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml


Alert rules:

    sudo -u prometheus \
      promtool check rules \
      /etc/prometheus/performance-alerts.yml


Configuration must pass validation before it is considered ready.


## Security Controls

### Localhost Binding

Prometheus, Node Exporter, and Grafana are bound to localhost because the complete architecture runs on one machine.


### Service Accounts

Prometheus and Node Exporter run under dedicated restricted service accounts.


### Binary Ownership

Downloaded service binaries remain owned by:

    root:root


### Grafana Credential Handling

The Grafana administrator credential is generated outside the repository-ready workspace.

The password is not written into dashboard JSON, datasource configuration, scripts, evidence, or documentation.


## Tools Used

- Prometheus
- PromQL
- Node Exporter
- Grafana
- Grafana provisioning
- stress-ng
- systemd
- journalctl
- Bash
- Python
- curl
- jq
- Linux networking utilities
- Linux filesystem utilities


## Key Skills Demonstrated

- Linux performance monitoring
- Prometheus administration
- PromQL engineering
- Grafana dashboard provisioning
- CPU performance analysis
- memory pressure analysis
- filesystem capacity analysis
- disk I/O analysis
- network throughput analysis
- network error analysis
- I/O-wait interpretation
- context-switch analysis
- load-average interpretation
- composite metric design
- safe zero-swap handling
- performance baseline engineering
- controlled workload generation
- before / during / after performance comparison
- alert rule engineering
- alert threshold validation
- monitoring recovery validation
- configuration lifecycle management
- evidence-driven performance analysis


## Real-World Use Case

Infrastructure issues rarely present themselves as one obvious metric.

An application may slow down because of:

    CPU saturation
    memory pressure
    storage contention
    capacity exhaustion
    network errors
    packet drops
    abnormal load


A performance observability system must make these signals available in a form that allows them to be correlated over time.

This implementation provides that foundation by combining:

    host telemetry
         +
    PromQL analysis
         +
    visual dashboards
         +
    controlled workload testing
         +
    alerting
         +
    historical baselines


## Lessons Learned

- Performance monitoring requires interpretation, not only metric collection.
- `MemAvailable` is generally more useful than raw free memory on Linux.
- Zero-swap systems require safe PromQL expressions to avoid invalid division.
- I/O wait should be correlated with disk activity before diagnosing CPU pressure.
- Network errors and drops often provide more diagnostic value than throughput alone.
- Filesystem analysis should exclude pseudo filesystems.
- Dashboard queries should be validated directly against Prometheus.
- Grafana provisioning makes visualization reproducible.
- Controlled workload generation is stronger evidence than idle screenshots.
- Before / during / after measurements demonstrate monitoring responsiveness.
- Composite metrics need names that accurately describe their semantics.
- Alert rules should be deliberately triggered and observed recovering.
- Long-term baselines should not be claimed when the underlying history does not yet exist.
- Production baselines become more meaningful as Prometheus retains real operating history.


## Final Validated State

Services:

    Prometheus      active
    Node Exporter   active
    Grafana         active


Prometheus targets:

    prometheus      UP
    node-exporter   UP


Visualization:

    System Performance Overview    available

    CPU Performance Analysis       available

    Network Performance Analysis   available


Performance analysis validated:

    CPU
    memory
    filesystem
    disk I/O
    network throughput
    network packets
    network errors
    network drops
    system load
    context switches
    I/O wait
    swap-safe analysis
    resource pressure


Controlled behavior validated:

    CPU load
    memory load
    disk activity
    network activity
    performance increase
    alert firing
    alert recovery


The final system demonstrates reproducible Linux performance observability with validated telemetry, provisioned dashboards, controlled load testing, proactive alerts, baseline engineering, and evidence-driven performance interpretation.
