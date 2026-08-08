# Dynamic Grafana Observability Dashboard

## What This Does

This implementation builds a reusable Grafana monitoring environment where one dashboard dynamically adapts to different services, environments, regions, teams, instances, and time windows.

Instead of maintaining separate dashboards for production, staging, development, individual services, or infrastructure instances, Grafana variables provide interactive filtering across a shared Prometheus telemetry model.

The environment includes Prometheus, Grafana, Node Exporter, and three instrumented sample services representing different operational environments.

Dashboard configuration is managed entirely as code and supports query variables, cascading dependencies, multi-value selections, regex filtering, custom intervals, constant thresholds, and textbox-driven filters.

## Architecture

    ┌──────────────────────────────────────────────────────────────┐
    │                        Linux Host                            │
    │                                                              │
    │   ┌──────────────────┐                                       │
    │   │  Node Exporter   │                                       │
    │   │      :9100       │                                       │
    │   │                  │                                       │
    │   │ CPU              │                                       │
    │   │ Memory           │                                       │
    │   │ Host Metrics     │                                       │
    │   └────────┬─────────┘                                       │
    │            │                                                 │
    │            │ scrape                                          │
    │            ▼                                                 │
    │   ┌──────────────────────────────────────────────────────┐   │
    │   │                    Prometheus                        │   │
    │   │                       :9090                          │   │
    │   │                                                      │   │
    │   │  Jobs / Environments / Regions / Teams / Instances  │   │
    │   └──────────────┬───────────────────────────────────────┘   │
    │                  │                                           │
    │                  │ PromQL                                    │
    │                  ▼                                           │
    │   ┌──────────────────────────────────────────────────────┐   │
    │   │                      Grafana                         │   │
    │   │                       :3000                          │   │
    │   │                                                      │   │
    │   │ Dynamic Variables                                  │   │
    │   │ Cascading Filters                                  │   │
    │   │ Multi-Value Selection                              │   │
    │   │ Regex Filtering                                    │   │
    │   │ Dynamic Panel Titles                               │   │
    │   └──────────────────────────────────────────────────────┘   │
    │                                                              │
    │   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
    │   │ sample-app-1    │  │ sample-app-2    │  │ sample-app-3│ │
    │   │ production      │  │ staging         │  │ development │ │
    │   │ us-east-1       │  │ us-west-2       │  │ eu-west-1   │ │
    │   │ backend         │  │ frontend        │  │ backend      │ │
    │   └─────────────────┘  └─────────────────┘  └─────────────┘ │
    │                                                              │
    └──────────────────────────────────────────────────────────────┘

All services communicate through a dedicated Docker bridge network.

## Variable Model

The dashboard implements a hierarchical variable chain:

    job
     │
     ▼
    environment
     │
     ▼
    region
     │
     ▼
    team
     │
     ▼
    instance

Changing an upstream value automatically changes the available values downstream.

## Query Variables

### Job

Retrieves available Prometheus jobs:

    label_values(up, job)

Supports:

- Multiple selections
- All values
- Automatic refresh

### Environment

Depends on the selected job:

    label_values(
      up{job=~"$job"},
      environment
    )

### Region

Depends on the selected job and environment:

    label_values(
      up{
        job=~"$job",
        environment=~"$environment"
      },
      region
    )

### Team

Depends on job, environment, and region:

    label_values(
      up{
        job=~"$job",
        environment=~"$environment",
        region=~"$region"
      },
      team
    )

### Instance

The deepest cascading variable:

    label_values(
      up{
        job=~"$job",
        environment=~"$environment",
        region=~"$region",
        team=~"$team"
      },
      instance
    )

## Additional Variables

### Interval

Custom interval options:

    1m
    5m
    10m
    30m
    1h
    6h
    12h
    1d

Used directly inside PromQL range selectors:

    rate(metric[$interval])

### Filtered Job

Uses regex filtering to expose only application jobs:

    /.*app.*/

### CPU Threshold

Constant value:

    80

Used by threshold-based infrastructure queries.

### Custom Filter

Textbox default:

    .*

Allows arbitrary instance regex matching.

## Dynamic Panels

### Service Request Rate

    sum by (
      job,
      instance,
      environment,
      region,
      team
    ) (
      rate(
        sample_http_requests_total{
          job=~"$job",
          instance=~"$instance",
          environment=~"$environment",
          region=~"$region",
          team=~"$team"
        }[$interval]
      )
    )

The panel responds to six independent dashboard controls.

### Request Latency

    sample_request_latency_seconds{
      job=~"$job",
      instance=~"$instance",
      environment=~"$environment",
      region=~"$region",
      team=~"$team"
    }

### Active Services

    count(
      up{
        job=~"$job",
        instance=~"$instance",
        environment=~"$environment",
        region=~"$region",
        team=~"$team"
      } == 1
    )

### Selected Jobs Validation

    count(
      up{job=~"$job"}
    )
    or vector(0)

This provides immediate feedback about how many active series the selected job filter resolves to.

### Host CPU Threshold

Actual host CPU utilization is calculated from Node Exporter:

    100 - (
      avg by (instance) (
        rate(
          node_cpu_seconds_total{
            mode="idle"
          }[5m]
        )
      ) * 100
    )

The dashboard compares this value against the constant threshold variable.

### Custom Instance Filtering

Textbox-driven selection:

    up{
      job=~"$job",
      instance=~"$custom_filter"
    }

## Multi-Value Filtering

Grafana multi-select values are used with PromQL regex selectors:

    environment=~"$environment"

rather than strict equality:

    environment="$environment"

This allows Grafana to expand multiple selected values into a valid regular expression.

Example equivalent selection:

    environment=~"production|staging"

## All Selection

All-enabled variables use:

    .*

as the effective regex.

This allows one query to operate against every available value without maintaining a separate query.

## Sample Service Telemetry

Each synthetic service exposes Prometheus-compatible metrics on port `8080`.

Metadata dimensions include:

- service
- environment
- region
- team
- status

Request counter:

    sample_http_requests_total

Latency gauge:

    sample_request_latency_seconds

Service metadata:

    sample_service_info

## Environment Mapping

### sample-app-1

    environment = production
    region      = us-east-1
    team        = backend

### sample-app-2

    environment = staging
    region      = us-west-2
    team        = frontend

### sample-app-3

    environment = development
    region      = eu-west-1
    team        = backend

## Prerequisites

- Linux
- Docker Engine
- Docker Compose
- Git
- curl
- jq

## Setup & Installation

Enter the implementation directory:

    cd ~/dynamic-observability

Validate configuration:

    docker compose config

Build and start:

    docker compose up -d --build

Inspect running services:

    docker compose ps

Expected services:

    prometheus
    grafana
    node-exporter
    sample-app-1
    sample-app-2
    sample-app-3

## Generate Telemetry

Generate requests:

    for i in $(seq 1 50); do
      curl -s http://127.0.0.1:8081/request-$i >/dev/null || true
      curl -s http://127.0.0.1:8082/request-$i >/dev/null || true
      curl -s http://127.0.0.1:8083/request-$i >/dev/null || true
    done

## Verify Prometheus

Health:

    curl http://127.0.0.1:9090/-/healthy

Targets:

    curl -s \
      http://127.0.0.1:9090/api/v1/targets \
      | jq .

Job values:

    curl -s \
      http://127.0.0.1:9090/api/v1/label/job/values \
      | jq .

Environment values:

    curl -s \
      http://127.0.0.1:9090/api/v1/label/environment/values \
      | jq .

Region values:

    curl -s \
      http://127.0.0.1:9090/api/v1/label/region/values \
      | jq .

## Validate Multi-Value Behavior

Example production and staging selection:

    curl -sG \
      http://127.0.0.1:9090/api/v1/query \
      --data-urlencode \
      'query=count(up{environment=~"production|staging"} == 1)' \
      | jq .

## Validate Regex Filtering

    curl -sG \
      http://127.0.0.1:9090/api/v1/query \
      --data-urlencode \
      'query=count(up{job=~".*app.*"} == 1)' \
      | jq .

## Validate Textbox Filtering

    curl -sG \
      http://127.0.0.1:9090/api/v1/query \
      --data-urlencode \
      'query=count(up{instance=~"sample-app-1:8080"} == 1)' \
      | jq .

## Dashboard Provisioning

Grafana data source:

    grafana/provisioning/datasources/prometheus.yaml

Dashboard provider:

    grafana/provisioning/dashboards/dynamic-dashboard.yaml

Dashboard definition:

    grafana/dashboards/dynamic-variables.json

The dashboard is loaded automatically when Grafana starts.

## Dashboard Export

The provisioned dashboard can also be retrieved through the Grafana API:

    curl -s \
      -u admin:admin123 \
      http://127.0.0.1:3000/api/dashboards/uid/dynamic-variables-dashboard \
      | jq '.dashboard'

The exported dashboard is stored as:

    dashboard-export.json

Validate:

    jq empty dashboard-export.json

## Tools Used

- Grafana
- Prometheus
- PromQL
- Prometheus Node Exporter
- Docker
- Docker Compose
- Python
- Prometheus Python client
- Linux
- curl
- jq
- JSON
- YAML

## Key Skills Demonstrated

- Grafana query variables
- Grafana custom variables
- Constant variables
- Textbox variables
- Multi-value filtering
- All-value filtering
- Cascading variables
- Variable dependency design
- Prometheus metric label modeling
- PromQL regex selectors
- Dynamic PromQL range vectors
- Dashboard-as-code
- Grafana provisioning
- Dynamic panel titles
- Reusable observability dashboards
- Multi-environment telemetry design
- Docker networking
- Prometheus target validation
- Dashboard export validation

## Real-World Use Case

Large observability environments often contain hundreds or thousands of services, hosts, clusters, regions, namespaces, environments, and application teams.

Creating one static dashboard for every combination creates significant duplication and operational maintenance.

Dynamic variables allow a single dashboard to represent many operational contexts.

For example, an engineer could select:

    production
        ↓
    us-east-1
        ↓
    backend
        ↓
    specific instance

and immediately restrict every panel to that operational scope.

The same design can be extended to:

- Kubernetes clusters
- namespaces
- workloads
- cloud accounts
- model-serving environments
- inference services
- GPU nodes
- application teams
- database clusters
- API gateways
- deployment versions

This is especially useful in AIOps and production AI infrastructure where a reusable dashboard may need to monitor many models, inference endpoints, clusters, tenants, or serving environments.

## Lessons Learned

Grafana variables provide a reusable abstraction over Prometheus labels.

Multi-value variables should normally be paired with PromQL regex selectors:

    =~

rather than strict equality selectors.

Cascading variables reduce irrelevant choices by narrowing downstream values based on upstream selections.

A good variable hierarchy should be derived from the actual telemetry labels rather than arbitrary categories that do not exist in the metric data.

Panel titles can use variables to give immediate visual context about the selected operational scope.

Dashboard provisioning makes the entire visualization model deterministic and reproducible.

## Troubleshooting Log

### Docker Permission Access

Docker was already installed but the active user initially lacked daemon access.

The existing installation was preserved and the user was added to the Docker group instead of unnecessarily reinstalling Docker.

### Sample Service Port Mismatch

The original service architecture used inconsistent container listening ports and host port mappings.

The corrected services listen on:

    8080

inside each container and expose:

    8081
    8082
    8083

on the host.

### Prometheus Servers Used as Applications

Prometheus servers are not appropriate substitutes for application workloads purely to create variable dimensions.

The implementation instead uses lightweight instrumented Python services with meaningful operational metadata.

### Incorrect CPU Metric Interpretation

Prometheus TSDB ingestion counters do not represent host CPU utilization.

Actual CPU telemetry is sourced from:

    node_cpu_seconds_total

### Incorrect Memory Metric Interpretation

Prometheus TSDB head-series counts do not represent system memory utilization.

Actual memory utilization is derived from:

    node_memory_MemAvailable_bytes

and:

    node_memory_MemTotal_bytes

### Invalid Geographic Dependency

A dependency between values such as:

    US
    EU
    ASIA

and AWS-style region values such as:

    us-east-1
    us-west-2
    eu-west-1

requires an explicit mapping layer.

A direct regular-expression dependency is not sufficient.

The implementation instead uses the real Prometheus dimensions in a deterministic hierarchy.

### Browser Performance Boundary

CLI timing can measure Grafana and Prometheus API latency.

It cannot accurately prove complete browser rendering time, JavaScript execution time, or interactive panel paint performance.

Those metrics require browser-side performance instrumentation.

## Shutdown

Stop services:

    docker compose down

Stop services and delete persistent monitoring data:

    docker compose down -v
