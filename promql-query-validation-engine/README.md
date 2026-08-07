# PromQL Query Validation Engine

## What This Does

This implementation provides a reusable PromQL execution and validation layer backed by a live Prometheus and Node Exporter environment.

Prometheus continuously collects Linux host telemetry from Node Exporter, including CPU, memory, filesystem, disk, and network metrics. A Bash-based query executor communicates directly with the Prometheus HTTP API and supports both instant and range queries while enforcing API-level error handling.

On top of the executor, a structured query library validates and executes production-relevant PromQL expressions covering resource utilization, counter rates, aggregation, forecasting, ranking, cardinality analysis, and alert-style thresholds.

The resulting workflow can be extended into monitoring automation, Grafana dashboards, alert-rule generation, or CI pipelines that validate PromQL before deployment.

## Architecture

    ┌───────────────────────────────────────────────────────────────┐
    │                         Linux Host                            │
    │                                                               │
    │  ┌──────────────────────┐                                    │
    │  │    Node Exporter     │                                    │
    │  │                      │                                    │
    │  │  CPU metrics         │                                    │
    │  │  Memory metrics      │                                    │
    │  │  Filesystem metrics  │                                    │
    │  │  Disk metrics        │                                    │
    │  │  Network metrics     │                                    │
    │  │                      │                                    │
    │  │  127.0.0.1:9100     │                                    │
    │  └──────────┬───────────┘                                    │
    │             │                                                 │
    │             │ 15-second scrape                                │
    │             ▼                                                 │
    │  ┌──────────────────────┐                                    │
    │  │      Prometheus      │                                    │
    │  │                      │                                    │
    │  │  TSDB storage        │                                    │
    │  │  PromQL engine       │                                    │
    │  │  HTTP query API      │                                    │
    │  │                      │                                    │
    │  │  127.0.0.1:9090     │                                    │
    │  └──────────┬───────────┘                                    │
    │             │                                                 │
    │             │ /api/v1/query                                   │
    │             │ /api/v1/query_range                             │
    │             ▼                                                 │
    │  ┌────────────────────────────────────────────────────────┐   │
    │  │                  pql.sh Executor                       │   │
    │  │                                                        │   │
    │  │  pql_instant()                                        │   │
    │  │  pql_range()                                          │   │
    │  │  API error handling                                   │   │
    │  │  JSON result preservation                             │   │
    │  └──────────────────────┬─────────────────────────────────┘   │
    │                         │                                     │
    │                         ▼                                     │
    │  ┌────────────────────────────────────────────────────────┐   │
    │  │                query_library.sh                        │   │
    │  │                                                        │   │
    │  │  CPU                                                   │   │
    │  │  Memory                                                │   │
    │  │  Disk                                                  │   │
    │  │  Network                                               │   │
    │  │  Alert thresholds                                     │   │
    │  │  Validation                                            │   │
    │  └────────────────────────────────────────────────────────┘   │
    └───────────────────────────────────────────────────────────────┘

## Repository Structure

    promql-query-validation-engine/
    ├── README.md
    ├── .gitignore
    ├── pql.sh
    ├── query_library.sh
    ├── validate_promql_queries.sh
    ├── validate_promql_aggregations.sh
    ├── final_promql_validation.sh
    ├── selector_function_validation.txt
    ├── aggregation_validation.txt
    ├── query_library_output.txt
    └── validation-report.txt

## Prometheus Environment

Prometheus runs locally on:

    127.0.0.1:9090

Node Exporter runs locally on:

    127.0.0.1:9100

Both services are managed by systemd and run using the dedicated `prometheus` system account.

Prometheus scrapes:

    prometheus
    node_exporter

at a 15-second interval.

## Query Executor

The reusable executor is implemented in:

    pql.sh

### Instant Queries

Interface:

    pql_instant QUERY

Example:

    source ./pql.sh

    pql_instant \
      'node_cpu_seconds_total{cpu="0",mode="idle"}'

The function:

- Sends the expression to `/api/v1/query`
- Returns raw Prometheus JSON
- Detects unsuccessful API responses
- Prints Prometheus error messages to stderr
- Returns a non-zero exit status when validation fails

### Range Queries

Interface:

    pql_range QUERY START_EPOCH END_EPOCH STEP

Example:

    END_EPOCH="$(date +%s)"
    START_EPOCH="$((END_EPOCH - 300))"

    pql_range \
      'node_cpu_seconds_total{cpu="0",mode="idle"}' \
      "$START_EPOCH" \
      "$END_EPOCH" \
      15

This communicates with:

    /api/v1/query_range

and returns matrix-style time-series data.

## PromQL Selectors

### Metric Selector

    node_cpu_seconds_total

### Equality Matcher

    node_cpu_seconds_total{
      cpu="0",
      mode="idle"
    }

### Inequality Matcher

    node_cpu_seconds_total{
      mode!="idle"
    }

### Regex Inclusion

    node_cpu_seconds_total{
      mode=~"user|system"
    }

### Regex Exclusion

    node_filesystem_size_bytes{
      fstype!~"tmpfs|devtmpfs|overlay|squashfs"
    }

### Network Device Filtering

    node_network_receive_bytes_total{
      device!~"lo|docker.*|br-.*|veth.*"
    }

## Counter Rate Analysis

Raw counter values represent cumulative activity and should generally be transformed into rates when measuring current throughput.

Example CPU rate:

    rate(
      node_cpu_seconds_total[5m]
    )

Network receive rate:

    rate(
      node_network_receive_bytes_total{
        device!~"lo|docker.*|br-.*|veth.*"
      }[5m]
    )

Traffic increase over five minutes:

    increase(
      node_network_receive_bytes_total{
        device!~"lo|docker.*|br-.*|veth.*"
      }[5m]
    )

## CPU Queries

### Overall CPU Utilization

    100 - (
      avg(
        rate(
          node_cpu_seconds_total{
            mode="idle"
          }[5m]
        )
      ) * 100
    )

### CPU Activity by Mode

    sum by (mode) (
      rate(
        node_cpu_seconds_total[5m]
      )
    ) * 100

### CPU Activity by Core

    sum by (cpu) (
      rate(
        node_cpu_seconds_total{
          mode!~"idle|iowait"
        }[5m]
      )
    )

## Memory Queries

### Used Memory Percentage

    (
      1 -
      (
        node_memory_MemAvailable_bytes
        /
        node_memory_MemTotal_bytes
      )
    ) * 100

### Available Memory in GiB

    node_memory_MemAvailable_bytes
    /
    1073741824

### Memory Trend Forecast

    predict_linear(
      node_memory_MemAvailable_bytes[30m],
      3600
    )

This estimates available memory one hour into the future using the trend observed during the previous 30 minutes.

## Disk Queries

### Filesystem Utilization

    (
      1 -
      (
        node_filesystem_free_bytes{
          fstype!~"tmpfs|devtmpfs|overlay|squashfs"
        }
        /
        node_filesystem_size_bytes{
          fstype!~"tmpfs|devtmpfs|overlay|squashfs"
        }
      )
    ) * 100

### Disk Read Throughput

    sum(
      rate(
        node_disk_read_bytes_total[5m]
      )
    )

### Disk Write Throughput

    sum(
      rate(
        node_disk_written_bytes_total[5m]
      )
    )

### Disk I/O Utilization

    avg(
      rate(
        node_disk_io_time_seconds_total[5m]
      )
    ) * 100

## Network Queries

### Receive Throughput

    sum(
      rate(
        node_network_receive_bytes_total{
          device!~"lo|docker.*|br-.*|veth.*"
        }[5m]
      )
    )

### Transmit Throughput

    sum(
      rate(
        node_network_transmit_bytes_total{
          device!~"lo|docker.*|br-.*|veth.*"
        }[5m]
      )
    )

### Network Error Rate

    sum(
      rate(
        node_network_receive_errs_total[5m]
      )
    )
    +
    sum(
      rate(
        node_network_transmit_errs_total[5m]
      )
    )

## Aggregation

### Aggregate CPU Counters

    sum(
      node_cpu_seconds_total
    )

### Group CPU Rate by Mode

    sum by (mode) (
      rate(
        node_cpu_seconds_total[5m]
      )
    )

### Group CPU Rate by Core

    sum by (cpu) (
      rate(
        node_cpu_seconds_total[5m]
      )
    )

### Distinct CPU Core Count

    count(
      count by (cpu) (
        node_cpu_seconds_total
      )
    )

The result was validated against Linux:

    nproc

to verify that Prometheus observed the same CPU cardinality as the kernel.

## Vector Matching Correction

The original normalized-load expression was:

    node_load1
    /
    count(
      count by (cpu) (
        node_cpu_seconds_total
      )
    )

This produced an empty result.

The denominator is technically a one-element instant vector rather than a PromQL scalar. Binary vector operations perform label matching, and the labels between `node_load1` and the aggregate result did not match.

The corrected expression is:

    node_load1
    /
    scalar(
      count(
        count by (cpu) (
          node_cpu_seconds_total
        )
      )
    )

Converting the global CPU count to a scalar allows it to operate as the intended denominator.

## Ranking Queries

### Top Three Interfaces by Receive Rate

    topk(
      3,
      rate(
        node_network_receive_bytes_total[5m]
      )
    )

### Filesystems with Lowest Free Percentage

    bottomk(
      3,
      (
        node_filesystem_free_bytes
        /
        node_filesystem_size_bytes
      ) * 100
    )

## Alert-Style Expressions

### High CPU

    100 - (
      avg(
        rate(
          node_cpu_seconds_total{
            mode="idle"
          }[5m]
        )
      ) * 100
    ) > 80

### High Memory Usage

    (
      1 -
      (
        node_memory_MemAvailable_bytes
        /
        node_memory_MemTotal_bytes
      )
    ) * 100 > 90

### High Root Filesystem Usage

    (
      1 -
      (
        node_filesystem_free_bytes{
          mountpoint="/"
        }
        /
        node_filesystem_size_bytes{
          mountpoint="/"
        }
      )
    ) * 100 > 85

### Target Down

    up == 0

An empty result from these queries is valid when the corresponding threshold is not currently breached.

## Query Validation

The query library provides:

    validate_query PROMQL_EXPRESSION

Validation passes only when the Prometheus API accepts the expression.

Example invalid expression:

    rate(node_cpu_seconds_total)

This is invalid because `rate()` requires a range vector.

Correct form:

    rate(
      node_cpu_seconds_total[5m]
    )

The executor returns a non-zero status for the invalid expression, allowing the same mechanism to be integrated into automated checks.

## Query Library

The reusable library contains 18 expressions:

    CPU        3
    Memory     3
    Disk       4
    Network    4
    Thresholds 4
    ----------------
    Total     18

The complete library can be executed with:

    bash query_library.sh \
      2>&1 |
      tee query_library_output.txt

Validate successful execution:

    grep -c '^PASS$' \
      query_library_output.txt

Expected:

    18

## Validation

Run the complete validation workflow:

    bash final_promql_validation.sh

The validator checks:

- Prometheus service health
- Node Exporter service health
- Both scrape targets
- Bash syntax
- Instant queries
- Range queries
- Invalid-query rejection
- All 18 library queries
- CPU metrics
- Memory metrics
- Disk metrics
- Network metrics
- Normalized load
- CPU cardinality
- Required output artifacts

## Security and Runtime Design

Both monitoring endpoints are bound to loopback interfaces:

    127.0.0.1:9090
    127.0.0.1:9100

This avoids unnecessary network exposure when queries are executed locally.

The systemd services use:

- Dedicated non-login system identity
- `NoNewPrivileges`
- Private temporary directories
- Protected home directories
- Protected system paths
- Kernel protection controls
- Explicit Prometheus writable data path
- Automatic restart on process failure

## Tools Used

- Prometheus
- PromQL
- Node Exporter
- promtool
- Linux
- systemd
- Bash
- curl
- jq
- Python
- Git

## Key Skills Demonstrated

- Deployed Prometheus and Node Exporter as persistent services
- Secured monitoring processes with dedicated service identities
- Configured local metric scraping
- Used Prometheus HTTP APIs directly
- Designed reusable Bash query abstractions
- Executed instant and range queries
- Applied equality and inequality label matchers
- Applied regex and negative-regex selectors
- Converted counters into meaningful rates
- Calculated utilization percentages
- Used `predict_linear()` for capacity forecasting
- Aggregated metrics with `sum` and `sum by`
- Ranked time series with `topk` and `bottomk`
- Counted distinct metric dimensions
- Diagnosed PromQL vector matching behavior
- Validated expressions before execution
- Rejected syntactically invalid PromQL
- Built alert-compatible threshold expressions
- Produced machine-checkable validation reports

## Real-World Use Case

This implementation represents the query-validation layer commonly used between telemetry collection and higher-level observability systems.

The same patterns can support:

- Grafana dashboards
- Prometheus alert rules
- Infrastructure monitoring
- Kubernetes observability
- Application performance monitoring
- Capacity planning
- SRE workflows
- AIOps telemetry pipelines
- Automated PromQL linting
- CI validation of monitoring configuration

By separating query execution from query definitions, new expressions can be added and validated without duplicating API communication logic.

## Lessons Learned

- Raw counters are usually less operationally useful than their rate of change.
- Range-vector duration must contain enough samples relative to the scrape interval.
- Label filters determine which time series participate in calculations.
- Regex exclusion is useful for removing virtual devices from host-level telemetry.
- Aggregation changes both the number of output series and their remaining label dimensions.
- A one-element vector is not automatically equivalent to a scalar in PromQL.
- Alert expressions can legitimately return empty vectors when thresholds are not breached.
- Query syntax should be validated before expressions reach dashboards or alerting rules.
- Range queries and instant queries serve different operational purposes.
- Metric cardinality can be correlated with operating-system state to validate telemetry completeness.

## Troubleshooting

### Promtool Could Not Read Configuration

Observed:

    open /etc/prometheus/prometheus.yml: permission denied

Cause:

The configuration had intentionally restrictive ownership:

    prometheus:prometheus
    0640

but validation was executed as the normal login user.

Resolution:

Validate using the same service identity:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml

### Curl Reported Failure Writing Output

Observed after:

    curl ... | grep -m1 ...

The requested metric had already been returned successfully. `grep -m1` exited after the first match while curl was still writing, causing curl to encounter a closed pipe.

This was not a Node Exporter failure.

### Normalized Load Returned No Results

Observed expression:

    node_load1 /
    count(
      count by (cpu) (
        node_cpu_seconds_total
      )
    )

PromQL attempted vector matching and found no compatible series.

Resolution:

    node_load1 /
    scalar(
      count(
        count by (cpu) (
          node_cpu_seconds_total
        )
      )
    )

### Rate Queries Require Historical Samples

Functions such as:

    rate(metric[5m])

require multiple samples inside the selected range.

Immediately after Prometheus starts, insufficient historical data can cause range-based queries to return no results.

### Forecasting Requires a Meaningful Time Window

The memory forecast uses:

    predict_linear(
      node_memory_MemAvailable_bytes[30m],
      3600
    )

Prometheus must first accumulate historical samples within the selected range before a meaningful regression can be calculated.

## Validation Result

The completed implementation validated:

    Prometheus service:                 PASS
    Node Exporter service:              PASS
    Scrape targets:                     2 healthy
    Instant query executor:             PASS
    Range query executor:               PASS
    Invalid PromQL rejection:           PASS
    PromQL library expressions:         18
    PromQL library successful results:  18
    CPU dimension:                      PASS
    Memory dimension:                   PASS
    Disk dimension:                     PASS
    Network dimension:                  PASS
    CPU cardinality:                    PASS
    Normalized load correction:         PASS
    Overall validation:                 PASS
