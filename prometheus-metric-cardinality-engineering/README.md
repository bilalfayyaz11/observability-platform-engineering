# Prometheus Metric Quality and Cardinality Engineering

## What This Does

This implementation demonstrates how Prometheus metric design directly affects observability-system scalability, memory consumption, query cost, and alert reliability.

Two Python web services expose intentionally different metric designs.

The first implementation deliberately violates Prometheus instrumentation principles by using dynamic user identifiers, session identifiers, IP addresses, and raw URL paths as labels. As traffic grows, each new label combination creates additional time series.

The second implementation uses bounded label vocabularies, explicit units, stable handler names, appropriate metric types, and purpose-built histogram buckets. Its series count remains bounded even as the number of application requests and distinct user identifiers increases.

Prometheus collects metrics from both applications, evaluates recording and alerting rules, and provides the data source for a Grafana dashboard that visualizes the resulting cardinality gap, request rates, error ratios, and p95 request latency.

The implementation also validates alert behavior using controlled HTTP 500 responses and includes recovery of an application-service failure that initially prevented recording rules from producing data.


## Architecture

    ┌────────────────────────────────────────────────────────────────────┐
    │                         Ubuntu Host                                │
    │                                                                    │
    │   ┌─────────────────────┐        ┌──────────────────────────────┐  │
    │   │ Non-Compliant Flask│        │ Production Metric Flask     │  │
    │   │ Service            │        │ Service                     │  │
    │   │                    │        │                              │  │
    │   │ 127.0.0.1:5000     │        │ 127.0.0.1:5001               │  │
    │   │                    │        │                              │  │
    │   │ Dynamic labels:    │        │ Bounded labels:              │  │
    │   │ user_id            │        │ method                       │  │
    │   │ session_id         │        │ handler                      │  │
    │   │ ip_address         │        │ status_code                  │  │
    │   │ raw URL paths      │        │                              │  │
    │   └─────────┬──────────┘        └──────────────┬───────────────┘  │
    │             │                                  │                   │
    │             │ /metrics                         │ /metrics          │
    │             └─────────────────┬────────────────┘                   │
    │                               │                                    │
    │                               ▼                                    │
    │                    ┌───────────────────────┐                       │
    │                    │      Prometheus       │                       │
    │                    │   127.0.0.1:9090      │                       │
    │                    │                       │                       │
    │                    │ Raw Metrics           │                       │
    │                    │ Recording Rules       │                       │
    │                    │ Alerting Rules        │                       │
    │                    │ Cardinality Analysis  │                       │
    │                    └───────────┬───────────┘                       │
    │                                │                                   │
    │                                ▼                                   │
    │                    ┌───────────────────────┐                       │
    │                    │       Grafana         │                       │
    │                    │   127.0.0.1:3000      │                       │
    │                    │                       │                       │
    │                    │ Request Rate          │                       │
    │                    │ Error Ratio           │                       │
    │                    │ Series Comparison     │                       │
    │                    │ P95 Latency           │                       │
    │                    └───────────────────────┘                       │
    │                                                                    │
    │   ┌─────────────────────┐                                         │
    │   │    Node Exporter    │                                         │
    │   │ 127.0.0.1:9100      │                                         │
    │   └─────────────────────┘                                         │
    │                                                                    │
    └────────────────────────────────────────────────────────────────────┘


## Prerequisites

- Ubuntu Linux
- Python 3
- Python virtual environments
- Prometheus
- promtool
- Node Exporter
- Grafana OSS
- systemd
- curl
- jq


## Components

| Component | Purpose | Port |
|---|---|---:|
| Grafana | Visualization | 3000 |
| Non-compliant Flask service | Cardinality anti-pattern demonstration | 5000 |
| Compliant Flask service | Bounded production instrumentation | 5001 |
| Prometheus | Metrics collection, rules, PromQL | 9090 |
| Node Exporter | Host telemetry | 9100 |

Operational endpoints are restricted to localhost for this single-host architecture.


## Directory Layout

    ~/metric-quality/
    ├── .venv/
    ├── apps/
    │   ├── bad_app.py
    │   └── good_app.py
    ├── scripts/
    │   └── generate_traffic.py
    ├── dashboards/
    │   └── comparison.json
    ├── evidence/
    │   ├── traffic.log
    │   ├── cardinality.txt
    │   └── final_validation.txt
    └── README.md

    /etc/prometheus/
    ├── prometheus.yml
    └── rules/
        ├── recording_rules.yml
        └── alerting_rules.yml


## Non-Compliant Metric Design

The intentionally unsafe service exposes labels such as:

    method
    endpoint
    status
    user_id
    session_id
    ip_address

Several of these values are effectively unbounded.

For example:

    user_id="812734"
    session_id="1c27..."
    ip_address="10.182.47.93"
    endpoint="/api/users/4821"

Each new combination can produce another Prometheus time series.

This means traffic volume involving new identities can increase memory consumption even when application architecture and request rate remain unchanged.


## Production Metric Design

The production-oriented request counter uses only:

    method
    handler
    status_code

The handler value is selected from a bounded vocabulary such as:

    home
    get_user
    health
    simulate_error

Variable path segments are never inserted into the label value.

A request for:

    /api/users/10

and a request for:

    /api/users/9274

both use:

    handler="get_user"

This keeps cardinality bounded.


## Metric Naming

Examples of production-oriented metric names include:

    myapp_http_requests_total

    myapp_http_request_duration_seconds

    myapp_memory_usage_ratio

    myapp_disk_usage_bytes

The names communicate measurement semantics and units directly.


## Histogram Design

Request latency is recorded using an explicit histogram rather than relying blindly on library defaults.

Representative bucket boundaries span:

    5ms
    10ms
    25ms
    50ms
    100ms
    250ms
    500ms
    1s
    2.5s
    5s

This supports latency-distribution analysis and p95 calculation.


## P95 Request Latency

The dashboard calculates p95 latency with:

    histogram_quantile(
      0.95,
      sum(
        rate(
          myapp_http_request_duration_seconds_bucket[5m]
        )
      ) by (le, handler)
    )

Grouping by both:

    le
    handler

preserves the histogram bucket boundary required by histogram_quantile while producing latency estimates per stable route handler.


## Recording Rules

Three recording rules pre-compute frequently reused PromQL expressions.


### Request Rate

    myapp:http_request_rate5m_by_handler

Calculates the five-minute request rate per bounded handler.


### Error Ratio

    myapp:http_error_ratio5m

Calculates:

    5xx request rate
    ----------------
      all request rate

for the compliant application.

The job label is intentionally preserved so alert selectors can continue to scope the resulting series correctly.


### Disk Usage

    myapp:disk_usage_gib

Converts application-reported disk usage from bytes to gibibytes.


## Why Recording Rules Matter

Dashboards and alerts frequently evaluate the same aggregations.

Without recording rules:

    Raw series
        ↓
    Repeated aggregation
        ↓
    Every dashboard refresh
        ↓
    Every alert evaluation

With recording rules:

    Raw series
        ↓
    Scheduled aggregation
        ↓
    Stored derived series
        ↓
    Fast dashboards and alerts

This moves recurring computational cost from query time into scheduled Prometheus evaluation.


## Alerting Rules

Three alerts are configured.


### HighErrorRate

Condition:

    myapp:http_error_ratio5m{job="good-app"} > 0.05

Pending duration:

    2 minutes

Severity:

    warning


### HighMemoryUsage

Condition:

    myapp_memory_usage_ratio{job="good-app"} > 0.85

Pending duration:

    5 minutes

Severity:

    critical


### ApplicationDown

Condition:

    up{job="good-app"} == 0

Pending duration:

    1 minute

Severity:

    critical


## Controlled Failure Validation

The production-oriented service includes:

    /api/simulate-error

This endpoint intentionally records bounded HTTP 500 responses.

Controlled requests allow the error recording rule and HighErrorRate alert to be tested without actually damaging the service.

The verification sequence is:

    Generate healthy requests
              ↓
    Generate controlled HTTP 500 responses
              ↓
    Prometheus scrapes request counters
              ↓
    Error-ratio recording rule evaluates
              ↓
    Ratio exceeds 5%
              ↓
    HighErrorRate enters pending/firing state


## Cardinality Validation

Traffic generation sends hundreds of distinct identifiers through both services.

For the non-compliant service, unique identities create unique series because identity data exists in metric labels.

For the production-oriented service, user identifiers never become labels.

The important comparison is therefore:

    Non-compliant series count
               vs
    Compliant series count

The implementation verifies that the former is at least five times larger.

The exact numerical values depend on the generated traffic and scrape timing.


## Grafana Dashboard

Dashboard:

    Prometheus Metric Quality and Cardinality

UID:

    metric-quality-comparison

The dashboard contains exactly four panels.


### Request Rate

PromQL:

    sum(
      myapp:http_request_rate5m_by_handler
    ) by (handler)

Purpose:

Visualizes traffic while preserving the bounded handler vocabulary.


### Error Ratio

PromQL:

    myapp:http_error_ratio5m

Purpose:

Uses a pre-computed recording rule rather than repeatedly calculating the expensive aggregation from raw counters.


### Series Count Comparison

PromQL:

    count({job="bad-app"})

and:

    count({job="good-app"})

Purpose:

Provides direct visual evidence of the cardinality difference between unsafe and bounded instrumentation.


### P95 Request Latency

PromQL:

    histogram_quantile(
      0.95,
      sum(
        rate(
          myapp_http_request_duration_seconds_bucket[5m]
        )
      ) by (le, handler)
    )

Purpose:

Validates the explicit histogram design and demonstrates percentile latency analysis.


## How to Reproduce

Activate the Python environment:

    source ~/metric-quality/.venv/bin/activate

Validate application syntax:

    python -m py_compile \
      ~/metric-quality/apps/bad_app.py \
      ~/metric-quality/apps/good_app.py


## Validate Prometheus Configuration

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml


## Validate Recording Rules

    sudo -u prometheus \
      promtool check rules \
      /etc/prometheus/rules/recording_rules.yml


## Validate Alerting Rules

    sudo -u prometheus \
      promtool check rules \
      /etc/prometheus/rules/alerting_rules.yml


## Inspect Prometheus Rule Health

    curl -fsS \
      http://127.0.0.1:9090/api/v1/rules |
      jq -r '
        .data.groups[].rules[] |
        [
          .type,
          .name,
          .health
        ] |
        @tsv
      '


Expected rule names:

    myapp:http_request_rate5m_by_handler
    myapp:http_error_ratio5m
    myapp:disk_usage_gib
    HighErrorRate
    HighMemoryUsage
    ApplicationDown


## Query Cardinality

Non-compliant:

    curl -fsSG \
      --data-urlencode \
      'query=count({job="bad-app"})' \
      http://127.0.0.1:9090/api/v1/query |
      jq .

Compliant:

    curl -fsSG \
      --data-urlencode \
      'query=count({job="good-app"})' \
      http://127.0.0.1:9090/api/v1/query |
      jq .


## Query Recording Rules

    curl -fsSG \
      --data-urlencode \
      'query=myapp:http_request_rate5m_by_handler' \
      http://127.0.0.1:9090/api/v1/query |
      jq .

    curl -fsSG \
      --data-urlencode \
      'query=myapp:http_error_ratio5m' \
      http://127.0.0.1:9090/api/v1/query |
      jq .


## Query Alerts

    curl -fsS \
      http://127.0.0.1:9090/api/v1/alerts |
      jq .


## Verify Services

    for svc in \
      prometheus \
      node_exporter \
      grafana-server \
      metric-bad-app \
      metric-good-app
    do
        systemctl is-active "$svc"
    done


## Tools Used

- Python
- Flask
- prometheus_client
- psutil
- Prometheus
- PromQL
- promtool
- Node Exporter
- Grafana OSS
- Grafana HTTP API
- Linux
- systemd
- Bash
- curl
- jq


## Key Skills Demonstrated

- Prometheus instrumentation design
- metric naming conventions
- metric unit semantics
- bounded label cardinality
- cardinality analysis
- counter design
- gauge design
- histogram design
- percentile latency calculation
- PromQL
- recording rules
- alerting rules
- SLO-oriented monitoring
- Grafana dashboard automation
- Grafana datasource configuration
- Flask instrumentation
- concurrent synthetic traffic generation
- systemd service management
- observability troubleshooting
- rule dependency analysis
- label propagation
- metrics-system performance awareness


## Real-World Use Case

Large observability platforms can become unstable because of poor instrumentation rather than insufficient compute capacity.

Common sources of uncontrolled cardinality include:

- customer IDs
- session IDs
- request IDs
- trace IDs
- IP addresses
- email addresses
- random identifiers
- raw URL paths
- container IDs
- dynamically generated resource names

A single badly instrumented service can create millions of series and materially increase Prometheus memory consumption, storage requirements, query latency, and operational cost.

For AI platforms, the same principles apply to labels such as:

- model identifiers
- inference endpoint names
- tenant IDs
- GPU identifiers
- experiment IDs
- pipeline execution IDs
- dynamically generated agent/session identifiers

The correct observability architecture treats label cardinality as a design constraint before telemetry reaches production.


## Lessons Learned

- Metric cardinality is an application-architecture decision, not merely a Prometheus setting.
- Labels must use bounded vocabularies whenever possible.
- User and session identifiers should generally not become Prometheus labels.
- Raw URL paths containing identifiers create hidden cardinality growth.
- Metric names should communicate units.
- Histograms require bucket boundaries appropriate for observed workloads.
- Recording rules reduce recurring query cost.
- Recording-rule labels must remain compatible with downstream alert selectors.
- Alerts should be tested with controlled failure conditions.
- Dashboard correctness depends on metric-schema correctness.
- A healthy rule definition does not guarantee that the rule has data.
- Application availability must be checked before diagnosing empty recording-rule results.


## Troubleshooting Log

### Recording Rules Had No Data

Prometheus successfully loaded all recording and alerting rules and reported healthy rule definitions, but the recording rules returned no series.

The root cause was not PromQL syntax.

The compliant Flask service on port 5001 was unavailable.

Because Prometheus could not scrape the application:

    raw metric series = absent

which caused:

    recording-rule output = absent

and therefore:

    alert expression output = absent


### Connection Refused on Port 5001

Synthetic requests returned:

    Failed to connect to 127.0.0.1 port 5001

The systemd-managed application service was inspected, restored, and validated before continuing alert testing.


### Application Recovery

The recovery sequence verified:

    service definition
        ↓
    Python environment
        ↓
    Python imports
        ↓
    source syntax
        ↓
    systemd service
        ↓
    port 5001 listener
        ↓
    /api/health
        ↓
    /metrics
        ↓
    Prometheus target state
        ↓
    recording-rule output


### Why Rule Health Alone Was Insufficient

A Prometheus rule can report:

    health="ok"

while still producing no time series.

The health field confirms that Prometheus successfully evaluates the expression syntactically.

It does not guarantee that the underlying selector currently matches data.

This distinction was important during troubleshooting.


### Missing Synthetic Error Route

The monitoring specification expected controlled error generation but did not include the corresponding endpoint in the main application interface.

A bounded:

    /api/simulate-error

endpoint was added so the error-ratio rule and alert could be validated intentionally.


### Rule Count Inconsistency

The specification describes:

    3 recording rules
    +
    3 alerting rules

which equals:

    6 rules

Some associated wording refers to five rules.

The implementation follows the explicit rule definitions and validates all six.


### Security

Prometheus, Node Exporter, Grafana, and both Flask services are bound to localhost in this single-host architecture.

Grafana administrative credentials are stored separately under restricted permissions and must never be committed to source control.
