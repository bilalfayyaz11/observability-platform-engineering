# Prometheus Failure Diagnosis and Recovery

## What This Does

This implementation provides a structured troubleshooting environment for diagnosing and recovering Prometheus failures across configuration, process management, scraping, networking, permissions, query behavior, and service health.

The environment intentionally introduces multiple failure modes and captures evidence at each stage instead of relying on blind restarts.

The scenarios include malformed YAML, invalid Prometheus configuration relationships, invalid PromQL, missing metric references, unavailable scrape targets, DNS resolution failures, file permission problems, configuration reload failures, and TCP port conflicts.

Each failure is classified by layer, reproduced safely, repaired, and validated through Prometheus APIs, promtool, systemd, direct HTTP requests, query execution, and automated diagnostics.

The result is a repeatable troubleshooting workflow suitable for Prometheus operations, SRE, platform engineering, AIOps, and production observability environments.


## Architecture

    ┌──────────────────────────────────────────────────────────────┐
    │                         Ubuntu Host                          │
    │                                                              │
    │   ┌──────────────────────┐                                   │
    │   │    Node Exporter     │                                   │
    │   │   127.0.0.1:9100    │                                   │
    │   └──────────┬───────────┘                                   │
    │              │                                               │
    │              │ /metrics                                      │
    │              ▼                                               │
    │   ┌─────────────────────────────────────────────┐             │
    │   │                Prometheus                   │             │
    │   │             127.0.0.1:9090                 │             │
    │   │                                             │             │
    │   │  Configuration validation                   │             │
    │   │  Target health API                          │             │
    │   │  Lifecycle reload                           │             │
    │   │  PromQL queries                             │             │
    │   │  TSDB storage                               │             │
    │   └──────────────────┬──────────────────────────┘             │
    │                      │                                        │
    │                      ▼                                        │
    │        ┌───────────────────────────────┐                      │
    │        │   Troubleshooting Evidence    │                      │
    │        │                               │                      │
    │        │ promtool output               │                      │
    │        │ systemd logs                  │                      │
    │        │ target API snapshots          │                      │
    │        │ query results                 │                      │
    │        │ debug logs                    │                      │
    │        │ diagnostics reports           │                      │
    │        └───────────────────────────────┘                      │
    │                                                              │
    │   Controlled failure scenarios:                              │
    │                                                              │
    │      malformed YAML                                          │
    │      invalid PromQL                                          │
    │      scrape timeout violation                                │
    │      unreachable TCP target                                  │
    │      DNS resolution failure                                  │
    │      configuration permissions                               │
    │      invalid reload                                          │
    │      port conflict                                           │
    │                                                              │
    └──────────────────────────────────────────────────────────────┘


## Prerequisites

- Ubuntu Linux
- systemd
- Prometheus
- promtool
- Node Exporter
- curl
- jq
- Bash
- standard Linux networking tools


## Directory Layout

    ~/prometheus-troubleshooting/
    ├── configs/
    │   ├── prometheus-initial.yml
    │   ├── broken-syntax.yml
    │   ├── logical-errors.yml
    │   ├── duplicate-job.yml
    │   ├── invalid-timeout.yml
    │   ├── test-rules.yml
    │   ├── missing-metric-valid-rule.yml
    │   ├── fixed-rules.yml
    │   ├── fixed-from-syntax.yml
    │   ├── fixed-from-logical.yml
    │   └── prometheus-fixed.yml
    ├── scripts/
    │   ├── prometheus-health-check.sh
    │   └── simulate-prometheus-problems.sh
    ├── diagnostics/
    │   └── prometheus-diagnostics.sh
    ├── evidence/
    │   ├── environment-baseline.txt
    │   ├── baseline-promtool.txt
    │   ├── broken-syntax-promtool.txt
    │   ├── logical-errors-promtool.txt
    │   ├── duplicate-job-promtool.txt
    │   ├── invalid-timeout-promtool.txt
    │   ├── broken-rules-promtool.txt
    │   ├── missing-metric-valid-rule.txt
    │   ├── fixed-rules-promtool.txt
    │   ├── promtool-analysis.txt
    │   ├── targets-before-repair.tsv
    │   ├── targets-after-repair.tsv
    │   ├── scrape-repair-summary.txt
    │   ├── prometheus-debug.log
    │   ├── task4-final-targets.tsv
    │   ├── promtool-instant-query.txt
    │   ├── promtool-range-query.txt
    │   ├── prometheus-diagnostics-*.log
    │   └── final-validation.txt
    ├── prometheus-troubleshooting-guide.md
    └── README.md


## Troubleshooting Method

The workflow follows this sequence:

    Observe
       ↓
    Classify
       ↓
    Validate
       ↓
    Reproduce safely
       ↓
    Repair
       ↓
    Verify
       ↓
    Capture evidence

The key principle is to identify the failing layer before changing the system.


## Configuration Validation

Prometheus configuration is validated with:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml

The environment demonstrates that failures can exist at multiple levels.


### YAML Syntax Failure

Malformed YAML prevents Prometheus from constructing a valid configuration.

Examples include:

    missing colon
    invalid indentation
    unterminated list


### Prometheus Configuration Semantics

A file can be valid YAML while still violating Prometheus constraints.

One example is:

    scrape_interval: 15s
    scrape_timeout: 30s

The timeout cannot exceed the scrape interval.


## PromQL Rule Validation

Rules are validated with:

    promtool check rules <file>


### Invalid PromQL

Malformed label syntax such as:

    invalid_metric_name{job=}

is rejected by promtool.


### Missing Metric Reference

An expression such as:

    cpu_usage > 0.8

can still pass syntax validation even when the metric currently does not exist.

This distinction is important:

    invalid expression
        ≠
    valid expression with no matching series

A missing metric usually produces an empty result at evaluation time rather than a parser error.


## Scrape Failure Diagnosis

The environment initially includes controlled failures.


### Healthy Node Exporter

Target:

    127.0.0.1:9100

Metrics path:

    /metrics

Expected condition:

    UP


### Unavailable TCP Target

Target:

    127.0.0.1:8080

No process listens on that port.

Failure path:

    Prometheus
        ↓
    TCP connection
        ↓
    connection refused
        ↓
    target DOWN


### DNS Failure

Target:

    invalid-hostname:9090

Failure path:

    Prometheus
        ↓
    hostname resolution
        ↓
    DNS failure
        ↓
    HTTP request never begins
        ↓
    target DOWN

The target API makes these conditions observable through:

    health
    scrapeUrl
    lastError


## Inspecting Targets

    curl -fsS \
      http://127.0.0.1:9090/api/v1/targets |
      jq .


A compact view:

    curl -fsS \
      http://127.0.0.1:9090/api/v1/targets |
      jq -r '
        .data.activeTargets[] |
        [
          .labels.job,
          .scrapeUrl,
          .health,
          (.lastError // "")
        ] |
        @tsv
      '


## Direct Endpoint Diagnosis

A target should also be tested outside Prometheus.

Node Exporter:

    curl -fsS \
      http://127.0.0.1:9100/metrics |
      head

Port availability:

    ss -lntp

DNS:

    getent hosts <hostname>

This separates:

    DNS
    TCP
    HTTP
    metrics endpoint
    Prometheus scrape behavior


## Safe Configuration Repair

A repaired configuration should always be validated before loading it.

Sequence:

    edit
      ↓
    promtool check config
      ↓
    install configuration
      ↓
    lifecycle reload
      ↓
    inspect targets
      ↓
    inspect logs


## Lifecycle Reload

Prometheus runs with:

    --web.enable-lifecycle

Reload:

    curl -fsS \
      -X POST \
      http://127.0.0.1:9090/-/reload

The Prometheus process ID is captured before and after the operation.

Identical PIDs demonstrate that configuration changed without restarting the process.


## Failed Reload Safety

A malformed configuration was deliberately installed while Prometheus was already running.

promtool detected the problem first.

A lifecycle reload against the invalid configuration was then tested.

The running Prometheus process remained available with its previously loaded configuration.

This demonstrates why:

    validate → reload

is safer than:

    edit → restart


## Permission Failure Simulation

The configuration file was deliberately changed to:

    root:root
    0600

while Prometheus ran as its dedicated service account.

The service could no longer read the configuration.

After capturing service and journal evidence, permissions were restored and Prometheus recovered successfully.


## Port Conflict Simulation

A second Prometheus process was intentionally started against:

    127.0.0.1:9090

while the systemd-managed instance already owned the port.

The second process failed with a bind error equivalent to:

    address already in use

This validates port ownership as an important troubleshooting check.


## Debug Logging

Temporary debug execution uses:

    --log.level=debug

The debug process is bounded with a timeout so it cannot take over the SSH session indefinitely.

Debug evidence can expose:

- configuration loading
- target behavior
- TSDB activity
- scrape processing
- service initialization


## Query Troubleshooting

Instant query:

    promtool query instant \
      http://127.0.0.1:9090 \
      'up'


Range query:

    END_TIME=$(
      date -u +"%Y-%m-%dT%H:%M:%SZ"
    )

    START_TIME=$(
      date -u \
        -d '5 minutes ago' \
        +"%Y-%m-%dT%H:%M:%SZ"
    )

    promtool query range \
      http://127.0.0.1:9090 \
      'up' \
      --start="$START_TIME" \
      --end="$END_TIME" \
      --step=30s


Using the current data window avoids confusing an empty result caused only by querying dates outside local retention.


## Health Automation

The reusable health script checks:

- Prometheus service state
- Node Exporter service state
- port 9090
- port 9100
- Prometheus health
- Prometheus readiness
- Node Exporter metrics endpoint
- configuration validity
- target health
- recent service errors


Run:

    ~/prometheus-troubleshooting/scripts/prometheus-health-check.sh


## Comprehensive Diagnostics

The diagnostic utility captures:

- OS information
- CPU
- memory
- disk
- Prometheus process
- service status
- listener state
- configuration validity
- configuration permissions
- TSDB directory size
- health endpoint
- readiness endpoint
- Node Exporter endpoint
- active target health
- up metric values
- recent Prometheus logs


Run:

    ~/prometheus-troubleshooting/diagnostics/prometheus-diagnostics.sh


A timestamped diagnostic report is generated under:

    ~/prometheus-troubleshooting/evidence/


## Final Healthy State

The repaired configuration contains two scrape targets:

    prometheus
    node-exporter

Expected target state:

    prometheus      UP
    node-exporter   UP

Expected:

    DOWN targets = 0


The up query should return:

    prometheus      1
    node-exporter   1


## Tools Used

- Prometheus
- promtool
- Node Exporter
- PromQL
- systemd
- journalctl
- curl
- jq
- ss
- getent
- Bash
- Linux process management
- Linux permissions
- DNS diagnostics
- TCP diagnostics


## Key Skills Demonstrated

- Prometheus configuration validation
- PromQL validation
- YAML troubleshooting
- scrape target diagnosis
- target API analysis
- DNS troubleshooting
- TCP connectivity troubleshooting
- HTTP endpoint testing
- systemd troubleshooting
- journal analysis
- configuration reloads
- safe rollback
- permission troubleshooting
- port conflict diagnosis
- debug log capture
- instant query testing
- range query testing
- automated health checks
- automated diagnostics
- controlled fault injection
- incident evidence collection
- root-cause classification


## Real-World Use Case

Prometheus failures in production rarely exist at only one layer.

A target reported as DOWN can be caused by:

- DNS
- routing
- firewall policy
- unavailable service
- wrong port
- wrong metrics path
- authentication
- TLS
- application failure
- scrape timeout
- configuration mistakes

Likewise, Prometheus itself can fail because of:

- invalid configuration
- permission problems
- storage failures
- port conflicts
- resource exhaustion
- unsupported flags
- TSDB issues

A systematic troubleshooting workflow prevents operators from making speculative changes that destroy evidence or introduce additional failures.


## Lessons Learned

- Validate before restarting.
- YAML validity does not guarantee Prometheus semantic validity.
- A missing metric is not the same as invalid PromQL.
- The target API is one of the most useful scrape-diagnosis tools.
- Direct endpoint testing helps isolate Prometheus from network or exporter failures.
- DNS failures and TCP failures should be treated as different incident classes.
- Service users should own writable configuration and data paths, not application binaries.
- Lifecycle reload is safer than unnecessary restarts.
- A failed reload can leave the previously loaded configuration operating.
- Process IDs can verify whether a reload occurred without restart.
- Port conflicts should be diagnosed by identifying the existing listener.
- Debug execution should be bounded when working over SSH.
- Current-time queries are more useful than arbitrary historical ranges in temporary environments.
- Troubleshooting scripts should distinguish historical fault-injection evidence from active failures.


## Troubleshooting Log

### Broken YAML

A deliberately malformed Prometheus configuration was validated with promtool.

The parser rejected the configuration before it reached the running Prometheus service.


### Invalid Scrape Timing

A configuration containing:

    scrape_interval: 15s
    scrape_timeout: 30s

was tested.

Prometheus validation rejected the invalid timing relationship.


### Invalid PromQL

A malformed selector was added to a rule expression.

promtool rejected the rule syntax.


### Missing Metric Reference

A syntactically valid expression referenced a metric that did not currently exist.

promtool accepted the rule, demonstrating that metric availability and query syntax are separate concerns.


### TCP Scrape Failure

Prometheus attempted to scrape:

    127.0.0.1:8080

where no service was listening.

The target API reported the target as DOWN and direct curl testing reproduced the connection failure.


### DNS Scrape Failure

Prometheus attempted to scrape an intentionally invalid hostname.

Name resolution failed before an HTTP request could reach the configured metrics path.


### Configuration Repair

The deliberately broken targets were removed and the corrected configuration was validated before installation.

Prometheus reloaded the configuration using its lifecycle endpoint without changing its process ID.


### Permission Failure

Configuration permissions were deliberately restricted so that the Prometheus service account could not read the file.

The service failure was captured through systemd and journal logs before permissions were restored.


### Invalid Reload

Malformed YAML was installed while the existing Prometheus process was running.

The invalid configuration was detected and the process remained available with its previously loaded configuration.


### Port Conflict

A second Prometheus process attempted to bind to the existing Prometheus listener.

The duplicate process failed because port 9090 was already occupied.


### Final Recovery

After all controlled failure scenarios:

    Prometheus = active
    Node Exporter = active
    configuration = valid
    health = pass
    readiness = pass
    active targets = 2
    DOWN targets = 0
    query validation = pass
    automated diagnostics = pass
