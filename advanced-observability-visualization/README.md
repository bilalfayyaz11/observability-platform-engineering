# Advanced Observability Visualization Platform

## What This Does

This implementation builds a containerized observability environment for analyzing infrastructure behavior and application telemetry through advanced Grafana visualizations.

The platform combines Prometheus, Node Exporter, Grafana, and a custom Python metrics service that exposes Prometheus histogram metrics for synthetic HTTP request duration and response size.

The environment demonstrates how raw time-series telemetry can be transformed into heatmaps, statistical distributions, percentile trends, and operational performance views.

It includes CPU, memory, network, latency, response-size, and histogram telemetry together with synthetic load generation for validating behavior under changing system conditions.

## Architecture

    ┌──────────────────────────────────────────────────────────────┐
    │                         Linux Host                           │
    │                                                              │
    │   ┌─────────────────────┐                                    │
    │   │    Node Exporter    │                                    │
    │   │       :9100         │                                    │
    │   │                     │                                    │
    │   │ CPU                 │                                    │
    │   │ Memory              │                                    │
    │   │ Network             │                                    │
    │   │ Filesystem          │                                    │
    │   └──────────┬──────────┘                                    │
    │              │                                               │
    │              │ scrape                                        │
    │              ▼                                               │
    │   ┌─────────────────────┐        ┌────────────────────────┐   │
    │   │     Prometheus      │◄───────│  Metrics Generator     │   │
    │   │       :9090         │ scrape │        :8000           │   │
    │   │                     │        │                        │   │
    │   │ TSDB                │        │ Request Duration       │   │
    │   │ PromQL              │        │ Response Size          │   │
    │   │ Histogram Analysis  │        │ Histogram Buckets      │   │
    │   └──────────┬──────────┘        └────────────────────────┘   │
    │              │                                               │
    │              │ PromQL                                        │
    │              ▼                                               │
    │   ┌───────────────────────────────────────────────────────┐   │
    │   │                       Grafana                         │   │
    │   │                        :3000                          │   │
    │   │                                                       │   │
    │   │ Heatmaps │ Histograms │ Percentiles │ Time Series    │   │
    │   └───────────────────────────────────────────────────────┘   │
    │                                                              │
    └──────────────────────────────────────────────────────────────┘

All services communicate through a dedicated Docker bridge network.

## Components

### Prometheus

Prometheus collects metrics from:

- Prometheus itself
- Node Exporter
- Custom histogram metrics service

The configuration uses Docker service discovery through predictable Compose service names rather than relying on container-local `localhost` addresses.

### Node Exporter

Node Exporter exposes Linux system telemetry including:

- CPU activity
- Memory utilization
- Network throughput
- Filesystem information
- Host operating system metrics

### Custom Metrics Generator

A Python service generates synthetic HTTP telemetry and exposes Prometheus classic histograms for:

    http_request_duration_seconds

and:

    http_response_size_bytes

The service provides the corresponding histogram bucket, sum, and count time series required for statistical analysis.

### Grafana

Grafana is provisioned entirely from files.

No manual data-source or dashboard creation is required.

Provisioned resources include:

    grafana/provisioning/datasources/prometheus.yaml

    grafana/provisioning/dashboards/advanced-panels.yaml

    grafana/dashboards/advanced-observability.json

## Dashboard Visualizations

The dashboard contains multiple advanced telemetry views.

### CPU Activity Heatmap

Displays the distribution of non-idle CPU activity over time.

PromQL:

    rate(node_cpu_seconds_total{mode!="idle"}[5m]) * 100

### Memory Usage Heatmap

Displays changes in memory utilization.

PromQL:

    (1 - (
      node_memory_MemAvailable_bytes /
      node_memory_MemTotal_bytes
    )) * 100

### Network Traffic Heatmap

Combines receive and transmit activity:

    rate(node_network_receive_bytes_total{device!="lo"}[5m])
    +
    rate(node_network_transmit_bytes_total{device!="lo"}[5m])

### HTTP Request Duration Bucket Heatmap

Uses native Prometheus histogram bucket telemetry:

    sum by (le) (
      rate(http_request_duration_seconds_bucket[5m])
    )

This preserves the histogram bucket boundary while aggregating other dimensions.

### Request Duration Percentiles

P50:

    histogram_quantile(
      0.50,
      sum by (le) (
        rate(http_request_duration_seconds_bucket[5m])
      )
    )

P90:

    histogram_quantile(
      0.90,
      sum by (le) (
        rate(http_request_duration_seconds_bucket[5m])
      )
    )

P95:

    histogram_quantile(
      0.95,
      sum by (le) (
        rate(http_request_duration_seconds_bucket[5m])
      )
    )

P99:

    histogram_quantile(
      0.99,
      sum by (le) (
        rate(http_request_duration_seconds_bucket[5m])
      )
    )

These percentiles provide a more useful understanding of application latency than averages alone.

## Prerequisites

- Linux
- Docker Engine
- Docker Compose
- curl
- jq
- stress-ng
- Git

## Setup & Installation

Clone or copy the implementation and enter the directory:

    cd ~/advanced-observability

Validate the Compose configuration:

    docker compose config

Build and start all services:

    docker compose up -d --build

Check container status:

    docker compose ps

Expected services:

    grafana
    prometheus
    node-exporter
    metrics-generator

## Verify Prometheus

Check Prometheus health:

    curl http://127.0.0.1:9090/-/healthy

Inspect scrape targets:

    curl -s http://127.0.0.1:9090/api/v1/targets | jq .

Healthy targets should include:

    prometheus
    node-exporter
    custom-metrics

## Verify Node Exporter

    curl http://127.0.0.1:9100/metrics

## Verify Custom Histogram Metrics

    curl http://127.0.0.1:8000/metrics

Example histogram families:

    http_request_duration_seconds_bucket
    http_request_duration_seconds_sum
    http_request_duration_seconds_count

    http_response_size_bytes_bucket
    http_response_size_bytes_sum
    http_response_size_bytes_count

## Generate Synthetic HTTP Telemetry

Generate observations:

    for i in $(seq 1 100); do
      curl -s "http://127.0.0.1:8000/request-$i" >/dev/null
    done

Prometheus will collect the generated histogram data during subsequent scrapes.

## Generate Infrastructure Load

The included load generator creates temporary CPU, memory, and HTTP activity.

Run:

    ./load_generator.sh

The script generates:

- CPU pressure
- Memory pressure
- Synthetic HTTP traffic
- Additional latency and response-size observations

This creates varied telemetry that can be inspected through the dashboard.

## Validate Percentiles

P95 request duration:

    curl -sG http://127.0.0.1:9090/api/v1/query \
      --data-urlencode 'query=histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))' \
      | jq .

P90 response size:

    curl -sG http://127.0.0.1:9090/api/v1/query \
      --data-urlencode 'query=histogram_quantile(0.90, sum by (le) (rate(http_response_size_bytes_bucket[5m])))' \
      | jq .

## Performance Validation

Inspect container resource consumption:

    docker stats --no-stream

Verify all Prometheus targets:

    curl -s http://127.0.0.1:9090/api/v1/targets | jq .

Validate Grafana health:

    curl -s http://127.0.0.1:3000/api/health | jq .

Validate dashboard JSON:

    jq empty grafana/dashboards/advanced-observability.json

Validate Compose configuration:

    docker compose config

## Tools Used

- Grafana
- Prometheus
- PromQL
- Prometheus Node Exporter
- Python
- Prometheus Python client
- Docker
- Docker Compose
- Linux
- stress-ng
- curl
- jq
- JSON
- YAML

## Key Skills Demonstrated

- Designing containerized observability architecture
- Prometheus scrape configuration
- Instrumenting custom Python telemetry
- Understanding Prometheus classic histograms
- Working with histogram buckets
- Calculating operational percentiles
- P50, P90, P95, and P99 latency analysis
- PromQL aggregation
- Grafana heatmap engineering
- Histogram-oriented visualization
- Dashboard provisioning
- Dashboard-as-code
- Synthetic workload generation
- Performance validation
- Infrastructure telemetry analysis
- Docker networking
- Reproducible monitoring environments
- Troubleshooting telemetry pipelines

## Real-World Use Case

Modern production systems cannot be understood through average values alone.

A service reporting an average latency of 200 milliseconds could still have a significant group of users experiencing several seconds of delay.

Histogram telemetry and percentile analysis expose these tail-latency conditions.

The same patterns are used for:

- API latency monitoring
- Model inference latency
- AI gateway performance
- Database query latency
- Queue processing duration
- Microservice response times
- Distributed system performance
- Capacity planning
- SLO monitoring
- Anomaly detection

For production AI infrastructure, similar telemetry can measure inference latency, model-serving throughput, GPU workload behavior, embedding request duration, retrieval latency, and agent execution performance.

## Lessons Learned

Prometheus histograms represent distributions using cumulative bucket counters.

Percentile calculations must preserve the `le` histogram boundary.

For classic histograms, a scalable percentile pattern is:

    histogram_quantile(
      percentile,
      sum by (le) (
        rate(metric_bucket[window])
      )
    )

Heatmaps are useful when the objective is to understand how a distribution changes over time.

Histograms are useful when the objective is to understand how observations are distributed across value ranges.

Percentiles are particularly valuable for identifying tail behavior that averages can hide.

Grafana provisioning provides deterministic and reproducible visualization configuration compared with manually creating dashboards through the browser.

## Troubleshooting Log

### Container Scraping Through Localhost

Using:

    localhost:9100

inside the Prometheus container would refer to the Prometheus container itself rather than another container.

The corrected configuration uses:

    node-exporter:9100

and:

    metrics-generator:8000

through the shared Docker network.

### Floating Container Versions

Floating image tags make future deployments non-deterministic.

The Compose configuration uses explicit image versions where practical so the environment can be reproduced consistently.

### Custom Metrics Process Management

Running a Python metrics process with:

    python3 script.py &

creates fragile lifecycle management.

The generator was containerized so Docker controls startup, restart behavior, networking, and shutdown.

### Histogram Quantile Aggregation

Using:

    histogram_quantile(
      0.95,
      rate(http_request_duration_seconds_bucket[5m])
    )

can produce incorrect semantics when multiple time-series dimensions exist.

The implementation aggregates while retaining the histogram boundary:

    histogram_quantile(
      0.95,
      sum by (le) (
        rate(http_request_duration_seconds_bucket[5m])
      )
    )

### Percentile Versus Distribution

A percentile represents a derived statistical threshold.

It is not itself the original histogram distribution.

The dashboard therefore separates raw bucket-oriented visualization from percentile trend analysis.

### Docker Permissions

Docker Engine was already installed, but the user initially lacked daemon access.

The existing installation was preserved and access was corrected by adding the user to the Docker group rather than unnecessarily reinstalling Docker.

## Shutdown

Stop the environment:

    docker compose down

Stop and remove persistent volumes if a complete reset is required:

    docker compose down -v
