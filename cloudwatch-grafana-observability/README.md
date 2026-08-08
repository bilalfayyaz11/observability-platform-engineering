# CloudWatch Observability and Alerting with Grafana

## What This Does

This implementation builds a fully programmatic observability pipeline using Grafana OSS, LocalStack CloudWatch, AWS CLI, and Python.

A Python telemetry publisher continuously generates realistic infrastructure metrics and sends them to a locally simulated CloudWatch API.

Grafana connects to that CloudWatch-compatible endpoint and provides dashboards and alerting without requiring manual browser configuration.

The system monitors three infrastructure metrics:

- CPUUtilization
- MemoryUtilization
- NetworkIn

It also implements automated alert rules for sustained high CPU and memory conditions.

All datasource configuration, dashboard creation, alert provisioning, validation, and incident triggering are performed through CLI commands, scripts, or HTTP APIs.

## Architecture

    ┌─────────────────────────────────────┐
    │       Python Metric Publisher       │
    │                                     │
    │ CPUUtilization                      │
    │ MemoryUtilization                   │
    │ NetworkIn                           │
    └──────────────────┬──────────────────┘
                       │
                       │ boto3 PutMetricData
                       ▼
    ┌─────────────────────────────────────┐
    │        LocalStack CloudWatch        │
    │                                     │
    │ http://127.0.0.1:4566               │
    │                                     │
    │ AWS/EC2                             │
    │ System/Linux                        │
    └──────────────────┬──────────────────┘
                       │
                       │ CloudWatch API
                       ▼
    ┌─────────────────────────────────────┐
    │            Grafana OSS              │
    │                                     │
    │ LocalStack CloudWatch datasource    │
    │                                     │
    │ EC2 Instance Metrics                │
    │ Infrastructure Overview             │
    │                                     │
    │ High CPU alert                      │
    │ High Memory alert                   │
    └──────────────────┬──────────────────┘
                       │
                       ▼
    ┌─────────────────────────────────────┐
    │        Grafana Alert Engine         │
    │                                     │
    │ severity = warning                  │
    │ webhook contact point               │
    └─────────────────────────────────────┘

## Metric Model

The telemetry publisher uses a single simulated EC2 instance:

    InstanceId = i-1234567890abcdef0

Metrics are divided into two namespaces.

### AWS/EC2

    CPUUtilization
    NetworkIn

### System/Linux

    MemoryUtilization

CPU and memory values use realistic percentage ranges.

Network traffic is generated using varying byte values so dashboard lines remain dynamic rather than flat.

## Python Telemetry Publisher

The metric publisher is implemented with boto3.

It connects to:

    http://127.0.0.1:4566

using test AWS credentials suitable for the LocalStack environment.

Normal CPU behavior varies below the configured alert threshold.

The publisher includes endpoint retry logic so it can recover automatically if LocalStack temporarily becomes unavailable.

The background process writes runtime activity to:

    metric_publisher.log

## LocalStack Runtime

LocalStack provides a locally simulated AWS CloudWatch API.

The runtime is exposed on:

    4566

AWS CLI commands use:

    --endpoint-url=http://127.0.0.1:4566

A fixed LocalStack version is used instead of the floating `latest` tag.

This prevents runtime behavior from unexpectedly changing when newer LocalStack releases introduce authentication, licensing, or compatibility changes.

## AWS CLI Profile

A dedicated AWS CLI profile is used:

    localstack

Configuration:

    access key = test
    secret key = test
    region = us-east-1
    output = json

Example validation:

    aws \
      --profile localstack \
      --endpoint-url=http://127.0.0.1:4566 \
      cloudwatch list-metrics

## Grafana CloudWatch Datasource

Grafana uses a datasource named:

    LocalStack CloudWatch

Datasource type:

    cloudwatch

Authentication mode:

    Access Key / Secret Key

Region:

    us-east-1

Custom endpoint:

    http://127.0.0.1:4566

The custom namespace:

    System/Linux

is explicitly configured so Grafana can query memory metrics.

## EC2 Instance Metrics Dashboard

The dashboard contains:

### CPU Utilization

    Panel type: Time series
    Namespace: AWS/EC2
    Metric: CPUUtilization
    Statistic: Average

### Current Memory Utilization

    Panel type: Stat
    Namespace: System/Linux
    Metric: MemoryUtilization
    Statistic: Average

### Network In

    Panel type: Time series
    Namespace: AWS/EC2
    Metric: NetworkIn
    Statistic: Average

Dashboard settings:

    refresh: 30 seconds
    default range: last 1 hour

## Infrastructure Overview Dashboard

The Infrastructure Overview dashboard provides a combined trend view.

It plots:

    CPUUtilization
    MemoryUtilization

on the same time-series panel for infrastructure comparison.

Settings:

    refresh: 30 seconds
    default range: last 1 hour

## Programmatic Dashboard Provisioning

Dashboards are created using the Grafana HTTP API rather than manual browser operations.

This makes the configuration:

- repeatable
- auditable
- portable
- suitable for infrastructure automation
- easier to reproduce across environments

## Alert Rule Group

Alert rules are organized under:

    folder: default
    group: ec2-alerts

Two Grafana-managed rules are configured.

## High CPU Alert

Condition:

    5-minute CPUUtilization average > 75%

Labels:

    severity = warning

Annotation:

    CPUUtilization exceeded 75 percent

The rule evaluates CloudWatch telemetry through Grafana's alerting engine.

## High Memory Alert

Condition:

    5-minute MemoryUtilization average > 80%

Labels:

    severity = warning

Annotation:

    MemoryUtilization exceeded 80 percent

## Contact Point

A webhook contact point is configured:

    name: lab-webhook

Target:

    http://127.0.0.1:9999/alert

The endpoint intentionally does not need to exist for configuration validation.

The objective is to demonstrate correct Grafana notification configuration.

## Incident Simulation

A high-CPU incident is generated programmatically.

The normal telemetry publisher is replaced temporarily with an incident publisher generating:

    CPUUtilization = 85%–98%

To avoid waiting several real minutes for historical normal samples to leave the five-minute alert window, high CPU datapoints are also backfilled across the preceding five minutes.

This produces a realistic sustained threshold violation while keeping validation efficient.

## Alert State Validation

Grafana alert state is queried through:

    /api/prometheus/grafana/api/v1/rules

The workflow polls until the High CPU rule reaches:

    pending

or:

    firing

The raw Grafana API response from the triggered state is saved to:

    ~/alert_validation.txt

This proves the alert state from the actual running Grafana alert engine rather than manually assuming it triggered.

## API-Driven Workflow

No browser-based configuration is required.

The implementation uses:

    Docker CLI
    AWS CLI
    boto3
    Grafana HTTP API
    Grafana Alerting API
    curl
    jq
    Bash
    Python

The entire observability pipeline can therefore be reproduced from a terminal.

## Tools Used

- Ubuntu Linux
- Docker Engine
- Docker Compose
- LocalStack
- AWS CLI
- Python
- boto3
- Grafana OSS
- Grafana CloudWatch datasource
- Grafana Alerting
- curl
- jq
- systemd
- Bash
- JSON

## Key Skills Demonstrated

- CloudWatch metric architecture
- custom metric publishing
- boto3 automation
- AWS CLI endpoint configuration
- cloud-service emulation
- Grafana datasource provisioning
- dashboard-as-code
- CloudWatch query design
- infrastructure visualization
- Grafana-managed alerting
- alert threshold design
- synthetic incident generation
- alert-state validation
- HTTP API automation
- observability troubleshooting
- dependency version management
- infrastructure reproducibility

## Real-World Use Case

The same architecture can be adapted to real AWS infrastructure by replacing the LocalStack endpoint and test credentials with genuine AWS authentication.

A production workflow could monitor:

- EC2 workloads
- machine learning inference servers
- GPU infrastructure
- Kubernetes nodes
- batch processing systems
- API servers
- data pipelines
- model-serving infrastructure

Grafana could then provide centralized visualization and alerting across these environments.

This pattern is particularly useful for AIOps and platform engineering teams that need infrastructure monitoring alongside application and AI-system telemetry.

## Version Compatibility Issue

Using:

    localstack/localstack:latest

initially pulled a newer LocalStack runtime that required authenticated license activation.

The container repeatedly exited with:

    exit code 55

and reported:

    License activation failed
    LOCALSTACK_AUTH_TOKEN required

This broke the original unauthenticated workflow.

The solution was to pin a compatible LocalStack release rather than depending on a floating latest tag.

This is an important infrastructure engineering principle:

    production dependencies should be version pinned

because upstream runtime behavior can change independently of local code.

## Troubleshooting Log

### Docker Socket Permission

The Docker service was running but the current shell did not initially have effective Docker-group access.

The user was added to the docker group and group access was refreshed.

### Ubuntu Python Package Protection

Direct global pip installation was avoided.

A Python virtual environment was created instead:

    ~/localstack-venv

This avoids modifying Ubuntu's externally managed system Python environment.

### LocalStack Runtime Restart Loop

The current LocalStack latest image required authenticated licensing and repeatedly restarted.

The runtime was replaced with a pinned compatible version.

### CloudWatch Connectivity Failure

When LocalStack stopped, the metric publisher remained alive but logged endpoint connection failures.

Retry logic allowed the publisher to recover after LocalStack returned.

### Bash Reserved Variable

A dashboard validation loop initially used:

    UID

which is a readonly Bash variable.

It was replaced with:

    DASH_UID

### Endpoint Formatting

Markdown-formatted endpoint text caused malformed AWS CLI URLs during copied validation commands.

Commands were corrected to use literal endpoint strings:

    http://127.0.0.1:4566

### Custom Memory Namespace

Memory metrics use:

    System/Linux

which is not an AWS-managed service namespace.

The namespace was explicitly configured in the Grafana CloudWatch datasource.

### Alert Evaluation Delay

The High CPU rule uses a five-minute evaluation window.

Instead of waiting for normal historical values to expire naturally, sustained high CPU history was generated programmatically before live incident telemetry continued.

## Lessons Learned

Observability systems are pipelines rather than isolated dashboards.

Telemetry generation, transport, storage, visualization, and alerting all need to work together.

CloudWatch namespaces and dimensions define how metrics are organized and queried.

A Grafana datasource can connect to a non-standard CloudWatch endpoint, which makes local cloud simulation useful for development and testing.

Dashboards should be provisioned programmatically when repeatability matters.

Alert configuration should also be treated as code.

A running process does not necessarily mean the underlying integration is healthy; the metric publisher remained alive even when LocalStack was unavailable.

Dependencies using floating tags such as `latest` can introduce breaking behavior unexpectedly.

Pinning infrastructure runtime versions makes builds more reproducible.

Alerting should be verified from actual rule state rather than only checking that the alert configuration exists.

Synthetic incident generation is a useful way to test monitoring and alerting systems before real failures occur.
