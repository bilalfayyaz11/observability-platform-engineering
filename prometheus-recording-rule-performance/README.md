# Prometheus Recording Rule Performance Engineering

## What This Does

This implementation demonstrates how Prometheus recording rules can be engineered as a hierarchical metrics layer to reduce repeated PromQL computation and provide stable derived metrics for dashboards, alerts, and downstream rule evaluation.

The architecture starts with raw Node Exporter telemetry and transforms it into a base recording layer containing normalized CPU, memory, disk, and network metrics.

A second composite recording layer consumes only those precomputed base metrics.

The implementation then measures query latency between raw PromQL expressions and their recording-rule equivalents and validates recording-rule health using Prometheus internal instrumentation and the rules API.

A real label-matching issue was also identified during implementation: individually healthy recording rules produced incompatible label sets, causing a composite expression to return an empty vector. The base metric interface was redesigned so dependent metrics expose a consistent per-instance label contract.

The completed architecture validates:

    Raw telemetry
          ↓
    Base recording rules
          ↓
    Stable metric interface
          ↓
    Composite recording rules
          ↓
    Precomputed time series
          ↓
    Low-complexity queries
          ↓
    Benchmarking + health diagnostics

## Architecture

    ┌──────────────────────────────────────────────────────────────┐
    │                      Linux Host                              │
    │                                                              │
    │  CPU                                                         │
    │  Memory                                                      │
    │  Filesystem                                                  │
    │  Network                                                     │
    │      │                                                       │
    │      ▼                                                       │
    │  ┌──────────────────────────────┐                            │
    │  │       Node Exporter          │                            │
    │  │     127.0.0.1:9100          │                            │
    │  └──────────────┬───────────────┘                            │
    │                 │                                            │
    │                 │ Raw node_* metrics                         │
    │                 ▼                                            │
    │  ┌──────────────────────────────┐                            │
    │  │         Prometheus           │                            │
    │  │     127.0.0.1:9090          │                            │
    │  │                              │                            │
    │  │  Raw time-series storage     │                            │
    │  └──────────────┬───────────────┘                            │
    │                 │                                            │
    │                 ▼                                            │
    │  ┌──────────────────────────────┐                            │
    │  │        node_base             │                            │
    │  │      every 15 seconds        │                            │
    │  │                              │                            │
    │  │ CPU utilization              │                            │
    │  │ Memory utilization           │                            │
    │  │ Disk utilization             │                            │
    │  │ Network throughput           │                            │
    │  └──────────────┬───────────────┘                            │
    │                 │                                            │
    │                 │ Recorded base series                       │
    │                 ▼                                            │
    │  ┌──────────────────────────────┐                            │
    │  │      node_composite          │                            │
    │  │      every 30 seconds        │                            │
    │  │                              │                            │
    │  │ System pressure score        │                            │
    │  │ Network throughput Mbps      │                            │
    │  └──────────────┬───────────────┘                            │
    │                 │                                            │
    │                 ▼                                            │
    │       Precomputed Prometheus Series                           │
    │                 │                                            │
    │        ┌────────┴────────┐                                   │
    │        ▼                 ▼                                   │
    │  Query Benchmark    Rule Diagnostics                         │
    └──────────────────────────────────────────────────────────────┘

## Repository Structure

    prometheus-recording-rule-performance/
    ├── README.md
    ├── prometheus.yml
    ├── recording_rules.yml
    ├── bench.sh
    ├── rule_health.sh
    ├── final_recording_rule_validation.sh
    ├── stack_validation.txt
    ├── base_rule_validation.txt
    ├── recording_rule_hierarchy_validation.txt
    ├── benchmark_validation.txt
    ├── bench_results.txt
    ├── rule_health_validation.txt
    ├── rule_health_results.txt
    └── validation-report.txt

## Prometheus

Prometheus provides:

- metric scraping
- time-series storage
- PromQL evaluation
- recording-rule evaluation
- rule-health instrumentation
- HTTP query APIs

Local endpoint:

    127.0.0.1:9090

The global scrape interval is:

    15 seconds

The global evaluation interval is:

    15 seconds

## Node Exporter

Node Exporter runs on:

    127.0.0.1:9100

It supplies the raw telemetry consumed by the base recording layer.

Important source metrics include:

    node_cpu_seconds_total

    node_memory_MemTotal_bytes

    node_memory_MemAvailable_bytes

    node_filesystem_size_bytes

    node_filesystem_avail_bytes

    node_network_receive_bytes_total

    node_network_transmit_bytes_total

## Recording Rule Architecture

Recording rules allow Prometheus to periodically evaluate PromQL expressions and store their results as new time series.

Instead of repeatedly executing:

    raw samples
        ↓
    range-vector selection
        ↓
    rate calculations
        ↓
    aggregation
        ↓
    arithmetic
        ↓
    result

a consumer can query:

    precomputed recorded series
        ↓
    result

This shifts computational work from query time to scheduled evaluation time.

## Base Recording Layer

The first rule group is:

    node_base

Evaluation interval:

    15s

It exposes four derived metrics.

## CPU Utilization

Recorded metric:

    node:cpu_utilization:rate5m

Expression:

    100 -
    (
      avg by (instance) (
        rate(
          node_cpu_seconds_total{
            job="node",
            mode="idle"
          }[5m]
        )
      )
      * 100
    )

The result represents the percentage of CPU time not spent idle, averaged across CPU cores for each monitored instance.

Expected range:

    0 - 100

## Memory Utilization

Recorded metric:

    node:memory_utilization:ratio

Expression:

    1 -
    (
      sum by (instance) (
        node_memory_MemAvailable_bytes{
          job="node"
        }
      )
      /
      sum by (instance) (
        node_memory_MemTotal_bytes{
          job="node"
        }
      )
    )

Expected range:

    0.0 - 1.0

The aggregation deliberately normalizes the output to an instance-only label interface.

## Root Filesystem Utilization

Recorded metric:

    node:disk_utilization:ratio

Expression:

    1 -
    (
      sum by (instance) (
        node_filesystem_avail_bytes{
          job="node",
          mountpoint="/"
        }
      )
      /
      sum by (instance) (
        node_filesystem_size_bytes{
          job="node",
          mountpoint="/"
        }
      )
    )

Expected range:

    0.0 - 1.0

Only the root filesystem is included.

## Network Throughput

Recorded metric:

    node:network_throughput:rate5m_bytes

Expression:

    rate(
      node_network_receive_bytes_total{
        job="node",
        device!="lo"
      }[5m]
    )
    +
    rate(
      node_network_transmit_bytes_total{
        job="node",
        device!="lo"
      }[5m]
    )

The result represents combined inbound and outbound bytes per second.

Unlike CPU, memory, and disk, this metric intentionally preserves the network device label.

Loopback traffic is excluded.

## Stable Label Contract

The base layer exposes a controlled interface to dependent recording rules.

CPU:

    {instance="..."}

Memory:

    {instance="..."}

Disk:

    {instance="..."}

This consistency is essential because PromQL vector arithmetic depends on compatible label sets.

## Label-Matching Failure Discovered

The first memory recording expression preserved an additional label:

    {instance="...", job="node"}

while CPU and disk exposed:

    {instance="..."}

The composite expression attempted arithmetic between these vectors.

Conceptually:

    CPU
    {instance="host"}

            +

    Memory
    {instance="host", job="node"}

            ↓

    no matching vector

            ↓

    empty result

The important observation was that:

    promtool validation: PASS

    rule syntax: PASS

    rule health: PASS

while:

    node:system_pressure:score

returned no data.

The expressions were individually valid, but their interfaces were incompatible.

## Corrected Label Contract

The memory expression was changed to aggregate:

    sum by (instance)

for both available and total memory.

The corrected interface became:

    CPU
    {instance="host"}

    Memory
    {instance="host"}

    Disk
    {instance="host"}

            ↓

    vector arithmetic succeeds

            ↓

    System pressure
    {instance="host"}

This demonstrates why recording-rule architecture must define both metric names and label contracts.

## Composite Recording Layer

The second rule group is:

    node_composite

Evaluation interval:

    30s

The architectural constraint is that this layer consumes only metrics produced by `node_base`.

It does not query raw Node Exporter telemetry directly.

## System Pressure Score

Recorded metric:

    node:system_pressure:score

Expression:

    (
      node:cpu_utilization:rate5m
      * 0.40
    )
    +
    (
      node:memory_utilization:ratio
      * 100
      * 0.35
    )
    +
    (
      node:disk_utilization:ratio
      * 100
      * 0.25
    )

Weights:

    CPU       40%
    Memory    35%
    Disk      25%

Expected range:

    0 - 100

The final validation observed a valid score within this range.

## Network Throughput in Mbps

Recorded metric:

    node:network_throughput:rate5m_mbps

Expression:

    node:network_throughput:rate5m_bytes
    * 8
    / 1000000

This converts:

    bytes per second
          ↓
    bits per second
          ↓
    megabits per second

The calculation reuses the base-layer network metric instead of recomputing rates from raw counters.

## Hierarchical Dependency Model

The final hierarchy is:

    node_cpu_seconds_total
            │
            ▼
    node:cpu_utilization:rate5m
            │
            │
            ├────────────────────┐
            │                    │
    memory raw metrics           │
            │                    │
            ▼                    │
    node:memory_utilization:ratio│
            │                    │
            ├────────────────────┤
            │                    │
    filesystem raw metrics       │
            │                    │
            ▼                    │
    node:disk_utilization:ratio  │
            │                    │
            └─────────┬──────────┘
                      │
                      ▼
          node:system_pressure:score

The composite layer therefore depends on a reusable metric interface rather than underlying instrumentation.

## Why the Hierarchy Matters

Without recording rules, multiple consumers may independently execute the same expensive calculation:

    dashboard
        ├── rate()
        ├── aggregation
        └── arithmetic

    alert
        ├── rate()
        ├── aggregation
        └── arithmetic

    another derived expression
        ├── rate()
        ├── aggregation
        └── arithmetic

With recording rules:

    Prometheus scheduled evaluation
                ↓
       calculate once
                ↓
       store recorded series
                ↓
      ┌─────────┼─────────┐
      ▼         ▼         ▼
    dashboard  alert   derived rule

This reduces redundant computation.

## Query Performance Benchmark

The implementation contains:

    /opt/prometheus/bench.sh

The script compares six queries:

    CPU raw PromQL
    CPU recording rule

    Memory raw PromQL
    Memory recording rule

    System pressure raw PromQL
    System pressure recording rule

Each query executes:

    5 iterations

The script measures HTTP query response time and computes the arithmetic mean in milliseconds.

## CPU Benchmark Pair

Raw expression:

    100 -
    (
      avg by (instance) (
        rate(
          node_cpu_seconds_total{
            job="node",
            mode="idle"
          }[5m]
        )
      )
      * 100
    )

Recorded equivalent:

    node:cpu_utilization:rate5m

The recorded form reads an already stored time series.

## Memory Benchmark Pair

Raw expression performs aggregation, division, subtraction, and percentage conversion at query time.

Recorded equivalent:

    node:memory_utilization:ratio * 100

The expensive source calculation has already been evaluated by the recording-rule engine.

## System Pressure Benchmark Pair

The raw version reconstructs the complete weighted expression from raw CPU, memory, and filesystem telemetry.

The recorded equivalent is:

    node:system_pressure:score

This pair represents the clearest example of eliminating repeated nested PromQL computation.

## Benchmark Evidence

Run:

    sudo -u prometheus \
      /opt/prometheus/bench.sh

Captured results are stored in:

    bench_results.txt

The output contains:

    six mean timing lines
    three pairwise comparison lines

The implementation intentionally reports measured results even when timing jitter on a small environment causes an individual raw query to appear faster.

Recording-rule benefits become more significant as:

- the number of monitored targets increases
- cardinality increases
- query ranges grow
- expression complexity grows
- dashboards repeat queries
- alerts reuse expressions
- dependent rule layers increase

## Recording Rule Health

Prometheus exposes internal metrics describing recording-rule execution.

The diagnostic implementation is:

    /opt/prometheus/rule_health.sh

It examines three important internal metrics.

## Evaluation Duration

Metric:

    prometheus_rule_evaluation_duration_seconds

This metric describes recording-rule evaluation latency.

Evaluation duration matters because a rule group should finish before its next scheduled interval.

## Evaluation Failures

Metric:

    prometheus_rule_evaluation_failures_total

The completed implementation confirmed:

    node_base failures = 0

    node_composite failures = 0

Any non-zero result causes the diagnostic script to report degraded health.

## Last Group Duration

Metric:

    prometheus_rule_group_last_duration_seconds

The observed values demonstrate how long the most recent evaluation of each rule group required.

This is useful when determining whether group evaluation is approaching its configured interval.

## Rules API

Current rule state is also inspected through:

    /api/v1/rules

The response exposes information including:

- group name
- configured interval
- evaluation duration
- rule name
- rule health
- last evaluation error

The completed architecture reports:

    node_base
        4 rules
        health = ok

    node_composite
        2 rules
        health = ok

## Parse-Time vs Runtime Validation

These are different validation layers.

### Parse-Time Validation

Run:

    sudo -u prometheus \
      promtool check rules \
      /etc/prometheus/recording_rules.yml

This detects problems such as:

- invalid YAML
- malformed PromQL
- structural configuration errors

### Runtime Validation

A rule can parse correctly but still fail or produce unexpected results during evaluation.

Runtime analysis uses:

    /api/v1/rules

and:

    prometheus_rule_evaluation_failures_total

The label-contract issue discovered during this implementation is a useful example.

The expressions were valid, and the rules evaluated without an explicit engine failure, yet the composite result was empty because vector matching produced no compatible series.

## Rule Health Diagnostic

Run:

    sudo -u prometheus \
      /opt/prometheus/rule_health.sh

Healthy result:

    All rule groups healthy.

Expected exit code:

    0

A degraded result causes:

    RULE HEALTH DEGRADED

and exits with:

    1

This makes the script suitable for automated operational verification.

## Source Metric Validation

Before deploying recording rules, the environment validates that Node Exporter exposes the required source telemetry.

Required signals include:

    CPU counters
    Memory capacity and availability
    Root filesystem capacity and availability
    Receive byte counters
    Transmit byte counters

This ensures missing recorded metrics are not incorrectly attributed to recording-rule logic when the underlying telemetry is absent.

## Security Design

Prometheus and Node Exporter use separate runtime identities:

    prometheus
    node_exporter

Neither service runs as root.

## Binary Ownership

Installed binaries remain:

    root:root
    0755

This prevents runtime service identities from modifying their own executable files.

## Network Exposure

Prometheus:

    127.0.0.1:9090

Node Exporter:

    127.0.0.1:9100

Both interfaces are bound to loopback because this architecture operates entirely on one host.

This avoids unnecessary external exposure.

## Prometheus Persistence

Prometheus stores time-series data under:

    /var/lib/prometheus

The service identity receives write access to this location while installed binaries remain immutable.

## systemd Hardening

Runtime services use operating-system protections including:

    NoNewPrivileges=true
    PrivateTmp=true
    ProtectHome=true
    ProtectSystem=strict
    ProtectControlGroups=true
    ProtectKernelModules=true
    ProtectKernelTunables=true

Prometheus receives explicit write access only where persistent time-series data is required.

## Validation Evidence

The repository contains multiple evidence files.

### Stack Validation

    stack_validation.txt

Confirms:

- Prometheus health
- Node Exporter health
- target scraping
- raw telemetry availability

### Base Rule Validation

    base_rule_validation.txt

Confirms:

- four base recording rules
- expected value ranges
- network loopback exclusion
- TSDB output
- rule evaluation health

### Hierarchy Validation

    recording_rule_hierarchy_validation.txt

Confirms:

- base-layer architecture
- composite-layer architecture
- label normalization
- dependency isolation
- composite metric output
- zero unhealthy rules

### Benchmark Validation

    benchmark_validation.txt

Confirms:

- five iterations per query
- six timing measurements
- three comparisons
- raw and recorded query execution

### Benchmark Results

    bench_results.txt

Contains the actual measured query latency output.

### Rule Health Validation

    rule_health_validation.txt

Confirms:

- internal Prometheus metrics
- both rule groups
- zero runtime evaluation failures
- diagnostic exit code

### Rule Health Results

    rule_health_results.txt

Contains the runtime health report.

### Final Validation

    validation-report.txt

Summarizes the complete architecture and validation outcome.

## Final Validation

Run:

    ./final_recording_rule_validation.sh

The validator checks:

- Prometheus service state
- Node Exporter service state
- ports 9090 and 9100
- Prometheus readiness
- Node Exporter endpoint
- Prometheus configuration
- recording-rule syntax
- scrape-target health
- rule-group inventory
- rule health
- all six recorded metrics
- base-layer label contract
- composite dependency isolation
- system-pressure range
- runtime evaluation failures
- rule-health diagnostics
- benchmark evidence
- validation records

## Tools Used

- Prometheus
- PromQL
- Node Exporter
- Linux
- systemd
- Bash
- Python
- curl
- jq
- promtool
- Git

## Skills Demonstrated

- Prometheus recording-rule architecture
- hierarchical metric design
- PromQL engineering
- rate calculations
- vector aggregation
- vector matching
- label normalization
- metric interface design
- derived telemetry
- composite health scoring
- query-latency benchmarking
- arithmetic mean calculation
- Prometheus internal instrumentation
- recording-rule diagnostics
- rules API analysis
- runtime failure detection
- parse-time configuration validation
- TSDB-derived metric verification
- performance optimization
- systemd service engineering
- Linux service isolation
- operational automation
- failure investigation

## Real-World Use Cases

The same architecture can support frequently reused metrics such as:

    service-level indicators

    request success ratios

    error-rate calculations

    latency percentiles

    resource saturation scores

    infrastructure health indexes

    fleet-level utilization

    application throughput

    capacity signals

    dashboard aggregates

    alerting inputs

Recording rules are particularly valuable when the same expensive expression is consumed repeatedly across multiple monitoring surfaces.

## Performance Engineering Principle

Without precomputation:

    Query request
         ↓
    raw time series
         ↓
    expensive PromQL
         ↓
    result

Every consumer pays the computational cost.

With recording rules:

    scheduled evaluation
          ↓
    expensive PromQL
          ↓
    stored result
          ↓
    lightweight query

The computation is performed on a predictable schedule and reused.

## Architectural Principle

A recording-rule hierarchy should behave like an internal metrics API.

A dependent layer should not need to understand how its inputs were calculated.

Instead:

    raw instrumentation
          ↓
    normalized base metrics
          ↓
    composite metrics
          ↓
    consumers

This reduces expression duplication and separates telemetry collection from higher-level operational logic.

## Lessons Learned

- Recording rules shift computational cost from query time to scheduled evaluation time.
- Frequently reused PromQL expressions are strong candidates for recording rules.
- Recording-rule names should communicate metric level, subject, and operation.
- Rule hierarchy reduces repeated access to raw instrumentation.
- Composite layers should consume stable lower-level metric interfaces.
- Metric names alone do not define an interface; label sets are equally important.
- PromQL binary arithmetic depends on compatible vector labels.
- A rule can be syntactically valid yet produce an empty result.
- Rule health can remain `ok` even when vector matching produces no series.
- `promtool` validates configuration but cannot prove semantic correctness of every runtime result.
- Prometheus internal metrics provide visibility into evaluation failures and duration.
- The rules API complements internal metrics with current rule state and last errors.
- Evaluation intervals should be designed with dependency timing in mind.
- Recorded query benefits increase with cardinality, expression complexity, query frequency, and range size.
- Benchmark results from small environments should be interpreted with awareness of timing jitter.
- Operational evidence should be regenerated from live checks rather than fabricated when a validation artifact is missing.
- A well-designed recording hierarchy acts as a reusable telemetry abstraction layer.

## Troubleshooting

### Recorded Metric Returns No Data

First query the raw source metrics.

Then inspect:

    /api/v1/rules

Check:

    health
    lastError

If the individual source recordings exist but a composite result is empty, inspect their label sets.

Example:

    node:cpu_utilization:rate5m

    node:memory_utilization:ratio

    node:disk_utilization:ratio

Their labels must be compatible for arithmetic unless explicit vector matching is used.

## Composite Metric Is Empty

Inspect:

    curl \
      --get \
      --data-urlencode \
      'query=node:cpu_utilization:rate5m' \
      http://127.0.0.1:9090/api/v1/query

Repeat for memory and disk.

Compare each result's labels.

A mismatch such as:

    {instance="host"}

versus:

    {instance="host", job="node"}

can prevent normal binary vector matching.

## Rule Syntax Fails

Run:

    sudo -u prometheus \
      promtool check rules \
      /etc/prometheus/recording_rules.yml

Then inspect YAML formatting.

## Full Prometheus Configuration Fails

Run:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml

Do not reload invalid configuration.

## Rule Reports Runtime Error

Inspect:

    curl \
      http://127.0.0.1:9090/api/v1/rules

Then query:

    prometheus_rule_evaluation_failures_total

This distinguishes historical runtime failures from configuration parsing errors.

## Rule Evaluation Is Slow

Inspect:

    prometheus_rule_group_last_duration_seconds

and rule evaluation duration metrics.

Compare group evaluation duration against the group's configured interval.

A rule group consistently approaching its evaluation interval is a performance warning.

## Recording Rule Benchmark Appears Slower

On a very small environment, network timing, scheduling jitter, filesystem caching, and HTTP processing can dominate sub-millisecond differences.

Recording-rule architecture provides its largest advantage when:

    cardinality grows
    target count grows
    range-vector size grows
    expressions become more complex
    queries repeat frequently

The benchmark should therefore be interpreted as both a measurement mechanism and a demonstration of the architectural difference between query-time calculation and precomputation.

## Final Result

The completed implementation validated:

    Prometheus service:                       PASS
    Node Exporter service:                    PASS

    Prometheus scrape target:                 PASS
    Node Exporter scrape target:              PASS

    node_base rules:                          4
    node_composite rules:                     2

    CPU recording:                            PASS
    Memory recording:                         PASS
    Disk recording:                           PASS
    Network byte-rate recording:              PASS
    System-pressure recording:                PASS
    Network Mbps recording:                   PASS

    Base metric label contract:               PASS
    Composite dependency isolation:           PASS

    System pressure range:                    PASS

    Raw CPU benchmark:                        PASS
    Recorded CPU benchmark:                   PASS
    Raw memory benchmark:                     PASS
    Recorded memory benchmark:                PASS
    Raw system-pressure benchmark:            PASS
    Recorded system-pressure benchmark:       PASS

    Benchmark timing lines:                   6
    Benchmark comparison lines:               3

    node_base evaluation failures:            0
    node_composite evaluation failures:       0

    Rule-health diagnostic:                   PASS

    Label-matching issue detected:            PASS
    Label contract corrected:                 PASS

    Raw telemetry -> base recordings:         PASS
    Base recordings -> composite recordings: PASS

    Overall recording-rule architecture:      PASS
