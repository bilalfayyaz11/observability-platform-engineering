# Prometheus TSDB Retention and Storage Engineering

## What This Does

This implementation builds a standalone Prometheus observability environment focused on reliable time-series storage lifecycle management.

Prometheus collects host, application, and synthetic high-volume metrics while enforcing configurable time-based and size-based TSDB retention policies. The environment includes Node Exporter, multiple custom metric generators, storage-growth monitoring, retention validation tooling, and a terminal-based operational dashboard.

The design demonstrates how Prometheus storage can be controlled, observed, and stress-tested before similar policies are introduced into production monitoring infrastructure.

## Architecture

    ┌──────────────────────────────────────────────────────────────┐
    │                    Linux Observability Host                  │
    │                                                              │
    │   ┌─────────────────┐       ┌─────────────────────────────┐  │
    │   │  Node Exporter  │       │ Custom Metrics Generator    │  │
    │   │    :9100        │       │           :8080             │  │
    │   └────────┬────────┘       └──────────────┬──────────────┘  │
    │            │                               │                 │
    │            │                               │                 │
    │   ┌────────▼───────────────────────────────▼──────────────┐  │
    │   │                     Prometheus                        │  │
    │   │                        :9090                          │  │
    │   │                                                       │  │
    │   │  Scrape Engine                                       │  │
    │   │      │                                                │  │
    │   │      ▼                                                │  │
    │   │  TSDB Head + WAL                                      │  │
    │   │      │                                                │  │
    │   │      ▼                                                │  │
    │   │  Persistent TSDB Blocks                               │  │
    │   │      │                                                │  │
    │   │      ├── Time Retention                               │  │
    │   │      └── Size Retention                               │  │
    │   └─────────────────────────┬─────────────────────────────┘  │
    │                             │                                │
    │               /var/lib/prometheus                           │
    │                             │                                │
    │        ┌────────────────────┴────────────────────┐           │
    │        │                                         │           │
    │        ▼                                         ▼           │
    │  Retention Monitor                    Retention Dashboard    │
    │  Storage / Blocks /                   TSDB / Disk /          │
    │  Target Health                        Series / Logs           │
    │                                                              │
    │   ┌───────────────────────────────────────────────────────┐  │
    │   │ Intensive Metric Generators                          │  │
    │   │ :8081  :8082  :8083  :8084  :8085                  │  │
    │   │ Thousands of synthetic time-series samples           │  │
    │   └───────────────────────────────────────────────────────┘  │
    └──────────────────────────────────────────────────────────────┘


## Prerequisites

- Ubuntu Linux with systemd
- sudo privileges
- x86_64 architecture
- Internet access to official Prometheus release assets
- curl
- wget
- tar
- jq
- Python 3
- Git
- Free TCP ports:
  - 9090 for Prometheus
  - 9100 for Node Exporter
  - 8080 for custom metrics
  - 8081-8085 for intensive synthetic metrics


## Setup & Installation

Create a dedicated Prometheus service account and storage directories:

    sudo useradd \
      --system \
      --no-create-home \
      --shell /usr/sbin/nologin \
      prometheus

    sudo mkdir -p /etc/prometheus
    sudo mkdir -p /var/lib/prometheus

    sudo chown prometheus:prometheus /etc/prometheus
    sudo chown prometheus:prometheus /var/lib/prometheus

Install Prometheus and promtool from the official Prometheus release channel and place both executables in:

    /usr/local/bin/prometheus
    /usr/local/bin/promtool

Install Node Exporter from its official release channel and place the executable in:

    /usr/local/bin/node_exporter

Install the supplied systemd service definitions:

    sudo cp prometheus.service /etc/systemd/system/prometheus.service
    sudo cp node_exporter.service /etc/systemd/system/node_exporter.service
    sudo cp custom_metrics.service /etc/systemd/system/custom_metrics.service

    sudo systemctl daemon-reload

Validate the Prometheus configuration:

    promtool check config prometheus.yml


## How to Reproduce

Copy the Prometheus configuration into place:

    sudo cp prometheus.yml /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

Copy the Python metric generators:

    chmod +x custom_metrics.py
    chmod +x intensive_metrics.py

Enable Prometheus and Node Exporter:

    sudo systemctl enable --now node_exporter
    sudo systemctl enable --now prometheus

Verify Prometheus health:

    curl -fsSL http://localhost:9090/-/healthy

Verify readiness:

    curl -fsSL http://localhost:9090/-/ready

Verify active scrape targets:

    curl -fsSL http://localhost:9090/api/v1/targets | \
      jq -r '.data.activeTargets[] |
      [.labels.job, .health, .scrapeUrl] | @tsv'

Run the retention configuration validation:

    ./test_retention.sh

Run a storage-monitoring window:

    ./monitor_retention.sh 120 30

Start the higher-volume metric generators using the included systemd definitions and verify ingestion:

    curl -fsSG \
      --data-urlencode 'query=count(retention_test_metric)' \
      http://localhost:9090/api/v1/query | jq .

Generate a single operational dashboard snapshot:

    ./retention_dashboard.sh --once


## Tools Used

- Prometheus
- Prometheus TSDB
- promtool
- Node Exporter
- Linux
- systemd
- Bash
- Python 3
- curl
- jq
- GNU coreutils
- Git


## Key Skills Demonstrated

- Prometheus TSDB lifecycle management
- Time-based metric retention configuration
- Size-based metric retention enforcement
- Monitoring storage consumption and capacity
- Prometheus scrape-target validation
- Synthetic metric generation
- High-volume time-series ingestion
- Metric-cardinality testing
- systemd service engineering
- Prometheus configuration validation with promtool
- Runtime configuration reloads
- TSDB block inspection
- WAL-aware storage troubleshooting
- Observability capacity planning
- Linux storage diagnostics
- Operational monitoring automation


## Real-World Use Case

A platform, SRE, AIOps, or infrastructure team operating Prometheus must prevent metric storage from consuming all available disk capacity while still retaining enough historical data for troubleshooting, incident analysis, capacity planning, and reliability reporting. This implementation demonstrates how engineering teams can establish explicit retention boundaries, monitor TSDB growth, understand active-series pressure, verify ingestion health, and apply storage safeguards before monitoring volume becomes an availability risk.


## Lessons Learned

- Prometheus retention should be governed by both time and storage limits rather than relying on a single constraint.
- TSDB storage limits should be planned with additional capacity for WAL and active head data rather than treating retention size as an absolute filesystem ceiling.
- High-cardinality metrics can significantly increase storage pressure even when the number of metric names remains small.
- Configuration validity should be checked with promtool before applying or reloading Prometheus.
- TSDB block lifecycle behavior must be considered when validating retention because data is not removed continuously sample-by-sample.


## Troubleshooting Log

### Outdated Prometheus Binary

The supplied implementation referenced an older Prometheus release.

The environment was updated to use a current Prometheus 3.x release obtained from the official release channel rather than reproducing an obsolete binary installation.


### Outdated Node Exporter Binary

The supplied Node Exporter version was several release generations behind.

A current Node Exporter binary from the official release channel was used instead.


### Retention Configuration Modernization

Older configurations commonly placed retention parameters directly in the Prometheus process startup arguments.

The implementation stores the retention policy declaratively in the Prometheus YAML configuration and validates it before reload.


### Incorrect Counter Generation

The original synthetic metrics logic produced random values for metrics declared as counters.

Counters must increase monotonically except when reset, so the generator was redesigned to accumulate values correctly.


### Invalid Histogram Generation

Independent random values for histogram buckets can produce non-cumulative bucket counts.

The synthetic histogram logic was changed so bucket values remain cumulative and internally consistent.


### Incorrect Oldest-Data Detection

A current Prometheus metric sample timestamp cannot be used as the timestamp of the oldest retained TSDB data.

Retention monitoring was redesigned to inspect TSDB block metadata and storage structures instead.


### Unsafe WAL Removal

Deleting the Prometheus WAL as a routine disk-space remediation can destroy recent recoverable samples.

The implementation avoids destructive WAL deletion and uses retention controls, cardinality reduction, storage expansion, and scrape optimization as safer operational responses.


### Incorrect TSDB Block Counting

Prometheus TSDB blocks use ULID directory names, so filtering directories only by numeric prefixes can miss valid blocks.

Block discovery was changed to identify actual block metadata rather than infer blocks from directory-name patterns.
