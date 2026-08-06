# Prometheus Application Metric Type Engineering

## What This Does

This implementation demonstrates how to design, expose, collect, and analyze the four core Prometheus metric types through a functioning Python web service.

The application exposes counters for requests and errors, gauges for changing application state, histograms for request-duration and response-size distributions, and summaries for processing-duration observations. Prometheus continuously scrapes the application, stores the resulting time series, evaluates alert rules, and supports PromQL analysis for rates, averages, quantiles, service-level measurements, and metric cardinality.

All runtime components are managed through systemd so the monitoring workflow remains operational after SSH disconnections and service failures.

## Architecture

    ┌─────────────────────────────────────────────────────────────────────┐
    │                         Linux Host                                  │
    │                                                                     │
    │   ┌──────────────────────────────┐                                  │
    │   │     Traffic Generator        │                                  │
    │   │                              │                                  │
    │   │  /                           │                                  │
    │   │  /api/data                   │                                  │
    │   │  /api/error                  │                                  │
    │   │                              │                                  │
    │   │  systemd managed             │                                  │
    │   └──────────────┬───────────────┘                                  │
    │                  │ HTTP requests                                    │
    │                  ▼                                                  │
    │   ┌─────────────────────────────────────────────────────────────┐   │
    │   │                 Python Flask Application                    │   │
    │   │                                                             │   │
    │   │  Counter                                                    │   │
    │   │  • Request totals                                           │   │
    │   │  • Error totals                                             │   │
    │   │                                                             │   │
    │   │  Gauge                                                      │   │
    │   │  • Active requests                                          │   │
    │   │  • CPU usage                                                │   │
    │   │  • Memory usage                                             │   │
    │   │  • Queue depth                                              │   │
    │   │                                                             │   │
    │   │  Histogram                                                  │   │
    │   │  • Request-duration buckets                                 │   │
    │   │  • Response-size buckets                                    │   │
    │   │                                                             │   │
    │   │  Summary                                                    │   │
    │   │  • Processing-duration count and sum                        │   │
    │   │                                                             │   │
    │   │  Port 8000                                                  │   │
    │   │  Metrics endpoint: /metrics                                 │   │
    │   └──────────────────────────┬──────────────────────────────────┘   │
    │                              │ Prometheus scraping                  │
    │                              ▼                                     │
    │   ┌─────────────────────────────────────────────────────────────┐   │
    │   │                     Prometheus                              │   │
    │   │                                                             │   │
    │   │  Time-series storage                                       │   │
    │   │  PromQL query engine                                       │   │
    │   │  Rate calculations                                         │   │
    │   │  Histogram quantiles                                       │   │
    │   │  SLA calculations                                          │   │
    │   │  Cardinality inspection                                    │   │
    │   │  Alert-rule evaluation                                     │   │
    │   │                                                             │   │
    │   │  Port 9090                                                  │   │
    │   └─────────────────────────────────────────────────────────────┘   │
    │                                                                     │
    │   systemd services                                                  │
    │   • prometheus-metric-app.service                                   │
    │   • prometheus-metric-server.service                                │
    │   • prometheus-traffic-generator.service                            │
    └─────────────────────────────────────────────────────────────────────┘

## Repository Structure

    prometheus-metric-type-engineering/
    ├── README.md
    ├── .gitignore
    ├── requirements.txt
    ├── sample_app.py
    ├── generate_traffic.sh
    ├── prometheus.yml
    ├── alert_rules.yml
    ├── metric_queries_reference.txt
    └── systemd/
        ├── prometheus-metric-app.service
        ├── prometheus-metric-server.service
        └── prometheus-traffic-generator.service

## Prerequisites

The following environment and tooling are required:

- Ubuntu 24.04 or another modern systemd-based Linux distribution
- Python 3.12 or newer
- Python virtual-environment support
- Prometheus
- promtool
- curl
- jq
- Bash
- systemd
- Administrative access through sudo
- Network ports `8000` and `9090` available

## Setup & Installation

Create the working directory:

    mkdir -p ~/prometheus-metric-types
    cd ~/prometheus-metric-types

Create the Python virtual environment:

    python3 -m venv .venv

Upgrade Python packaging tools:

    .venv/bin/python -m pip install \
      --upgrade \
      pip \
      setuptools \
      wheel

Install the required Python packages:

    .venv/bin/python -m pip install \
      -r requirements.txt

Validate the application source:

    .venv/bin/python -m py_compile sample_app.py

Validate Prometheus configuration:

    promtool check config prometheus.yml

Validate alert rules:

    promtool check rules alert_rules.yml

## How to Reproduce

Clone the repository:

    git clone https://github.com/bilalfayyaz11/observability-platform-engineering.git
    cd observability-platform-engineering/prometheus-metric-type-engineering

Create and prepare the virtual environment:

    python3 -m venv .venv

    .venv/bin/python -m pip install \
      --upgrade \
      pip \
      setuptools \
      wheel

    .venv/bin/python -m pip install \
      -r requirements.txt

Install the systemd service definitions:

    sudo cp systemd/prometheus-metric-app.service \
      /etc/systemd/system/prometheus-metric-app.service

    sudo cp systemd/prometheus-metric-server.service \
      /etc/systemd/system/prometheus-metric-server.service

    sudo cp systemd/prometheus-traffic-generator.service \
      /etc/systemd/system/prometheus-traffic-generator.service

Reload systemd:

    sudo systemctl daemon-reload

Start the instrumented application:

    sudo systemctl enable --now \
      prometheus-metric-app.service

Start Prometheus:

    sudo systemctl enable --now \
      prometheus-metric-server.service

Start continuous traffic generation:

    sudo systemctl enable --now \
      prometheus-traffic-generator.service

Verify service state:

    sudo systemctl status \
      prometheus-metric-app.service \
      prometheus-metric-server.service \
      prometheus-traffic-generator.service

Verify the application endpoint:

    curl http://127.0.0.1:8000/

Verify the metrics endpoint:

    curl http://127.0.0.1:8000/metrics

Verify Prometheus health:

    curl http://127.0.0.1:9090/-/healthy

Verify configured targets:

    curl --silent \
      http://127.0.0.1:9090/api/v1/targets |
      jq '
        .data.activeTargets[]
        | {
            job: .labels.job,
            instance: .labels.instance,
            health: .health,
            error: .lastError
          }
      '

## Metric Types

### Counter

Counters represent cumulative values that increase until the application process restarts.

Implemented counters:

- `demo_http_requests_total`
- `demo_http_errors_total`

Example request-rate query:

    sum by (endpoint) (
      rate(demo_http_requests_total[2m])
    )

Example error-percentage query:

    (
      sum(rate(demo_http_errors_total[2m]))
      /
      clamp_min(
        sum(rate(demo_http_requests_total[2m])),
        0.001
      )
    ) * 100

### Gauge

Gauges represent current values that can increase or decrease.

Implemented gauges:

- `demo_active_requests`
- `demo_cpu_usage_percent`
- `demo_memory_usage_bytes`
- `demo_queue_depth`

Example current-state query:

    demo_cpu_usage_percent

Example historical-average query:

    avg_over_time(
      demo_cpu_usage_percent[2m]
    )

Example maximum-memory query:

    max_over_time(
      demo_memory_usage_bytes[2m]
    )

### Histogram

Histograms organize observations into cumulative buckets and also expose `_sum` and `_count` series.

Implemented histograms:

- `demo_http_request_duration_seconds`
- `demo_http_response_size_bytes`

Example 95th-percentile query:

    histogram_quantile(
      0.95,
      sum by (le) (
        rate(
          demo_http_request_duration_seconds_bucket[2m]
        )
      )
    )

Example average-duration query:

    sum(
      rate(
        demo_http_request_duration_seconds_sum[2m]
      )
    )
    /
    sum(
      rate(
        demo_http_request_duration_seconds_count[2m]
      )
    )

Example percentage of requests under one second:

    (
      sum(
        rate(
          demo_http_request_duration_seconds_bucket{
            le="1.0"
          }[2m]
        )
      )
      /
      clamp_min(
        sum(
          rate(
            demo_http_request_duration_seconds_count[2m]
          )
        ),
        0.001
      )
    ) * 100

### Summary

The Python Prometheus client exposes Summary observation count and sum series but does not expose client-calculated quantile labels.

Implemented summary:

- `demo_processing_duration_seconds`

Example average-processing-duration query:

    sum(
      rate(
        demo_processing_duration_seconds_sum[2m]
      )
    )
    /
    sum(
      rate(
        demo_processing_duration_seconds_count[2m]
      )
    )

Example processing-rate query:

    sum(
      rate(
        demo_processing_duration_seconds_count[2m]
      )
    )

## Alert Rules

The configuration includes three application alerts.

### HighErrorRate

Triggers when more than 10 percent of requests are errors for one minute.

### HighSimulatedCPUUsage

Triggers when the simulated CPU gauge remains above 80 percent for one minute.

### SlowApplicationRequests

Triggers when the estimated 95th-percentile request latency remains above 1.5 seconds for two minutes.

Validate the rules with:

    promtool check rules alert_rules.yml

Inspect loaded rules:

    curl --silent \
      http://127.0.0.1:9090/api/v1/rules |
      jq '
        .data.groups[]
        | {
            group: .name,
            rules: [
              .rules[]
              | {
                  name: .name,
                  state: .state,
                  health: .health
                }
            ]
          }
      '

## Cardinality Analysis

Metric cardinality measures how many unique time series are created by metric names and label combinations.

Count all demonstration series:

    count({
      __name__=~"demo_.*"
    })

Count series by metric name:

    count by (__name__) ({
      __name__=~"demo_.*"
    })

Labels such as user IDs, request IDs, raw URLs, timestamps, or other unbounded values should not be added to Prometheus metrics because they can generate excessive time-series cardinality.

## Tools Used

- Prometheus
- PromQL
- Python
- Flask
- Prometheus Python client
- systemd
- Bash
- curl
- jq
- promtool
- Python virtual environments
- Git

## Key Skills Demonstrated

- Instrumented a Python web application with Prometheus metrics
- Designed counters, gauges, histograms, and summaries
- Selected metric types based on behavioral requirements
- Created meaningful metric labels without unbounded dimensions
- Built PromQL expressions for rates, averages, quantiles, and percentages
- Calculated request latency and service-level compliance
- Inspected metric cardinality and time-series growth
- Created alert rules for errors, CPU utilization, and latency
- Managed application and monitoring processes through systemd
- Isolated Python dependencies through a virtual environment
- Validated application, Prometheus, and Bash configurations
- Diagnosed dependency failures and service restart loops

## Real-World Use Case

This implementation represents the observability pattern used for API services, model-serving endpoints, internal platforms, data-processing systems, and production web applications. Engineers can use the same instrumentation strategy to understand request volume, error behavior, concurrent workload, resource state, latency distributions, processing throughput, and service-level compliance. Correct metric-type selection directly affects query accuracy, storage efficiency, alert quality, and the ability to aggregate telemetry across multiple application instances.

## Lessons Learned

- Metric types must be selected according to how a value behaves, not merely according to its name.
- Counters should be analyzed with rate functions rather than interpreted only as raw totals.
- Gauges represent changing state and support historical range functions such as averages and maximums.
- Histogram buckets are cumulative and enable server-side quantile calculation across instances.
- Python Summary metrics expose count and sum series but do not automatically provide quantile labels.
- Label design must avoid unbounded values that can create excessive time-series cardinality.
- Python packages must be installed into the exact interpreter environment used by systemd.
- A systemd service may briefly appear active before its process immediately exits.
- Traffic generators must report connection failures rather than silently ignoring unsuccessful requests.

## Troubleshooting Log

### Flask dependency missing from the service environment

The application repeatedly failed with:

    ModuleNotFoundError: No module named 'flask'

The systemd service correctly referenced:

    /home/ubuntu/prometheus-metric-types/.venv/bin/python

However, Flask and the Prometheus Python client were not installed inside that exact virtual environment.

The virtual environment was rebuilt and packages were installed using its interpreter:

    .venv/bin/python -m pip install \
      Flask \
      prometheus-client

Imports were then verified directly:

    .venv/bin/python -c \
      'import flask, prometheus_client'

### Restart loop appeared temporarily active

The application service used:

    Restart=on-failure

Systemd repeatedly restarted the process after every Python import failure. Status output could briefly display `active` during the milliseconds between process creation and failure.

The actual runtime state was confirmed using:

    sudo journalctl \
      -u prometheus-metric-app.service \
      --no-pager

    sudo ss -lntp |
      grep ':8000'

### Traffic generator hid application failures

The first traffic generator suppressed curl output and did not fail on connection errors. The generator therefore appeared active even though no requests reached the application.

Application health must be validated independently through:

    curl --fail \
      http://127.0.0.1:8000/

    curl --fail \
      http://127.0.0.1:8000/metrics

    curl \
      http://127.0.0.1:9090/api/v1/targets

### Unsupported Summary quantile assumption

The original design expected Summary metrics with labels such as:

    quantile="0.95"

The Python Prometheus client does not expose those quantile series. Summary analysis was corrected to use `_sum` and `_count` for averages and rates.

Histogram metrics were used for percentile analysis because their cumulative buckets support `histogram_quantile()`.

### Division-by-zero risk in error calculations

Directly dividing error rate by request rate can produce invalid results when there is no traffic.

The denominator was protected with:

    clamp_min(
      sum(rate(demo_http_requests_total[2m])),
      0.001
    )

### Interactive processes replaced with systemd

Running the application, Prometheus, and traffic generator in separate SSH terminals would stop them when sessions closed.

All runtime components were converted into persistent systemd services with restart policies.

## Security and Production Considerations

The systemd services use restricted execution settings including:

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `ProtectHome=read-only`
- `ProtectSystem=strict`
- Explicit writable paths
- Dedicated working directories

A production deployment should additionally include:

- TLS for application and Prometheus endpoints
- Authentication and authorization
- Firewall restrictions
- Private network exposure
- Reverse-proxy protection
- Bounded metric labels
- Remote durable time-series storage
- Recording rules for expensive queries
- Alertmanager notification routing
- Deployment automation
- Multiple application instances
- Grafana dashboards
