# Prometheus Long-Term Storage with Thanos

## What This Does

This implementation extends Prometheus beyond local short-term retention by integrating it with Thanos and S3-compatible object storage.

Prometheus collects local infrastructure telemetry while the Thanos Sidecar exposes live Prometheus data through the Store API and uploads immutable TSDB blocks into MinIO. Thanos Store Gateway provides access to historical blocks stored in object storage, while Thanos Query presents live and historical metrics through a single PromQL-compatible interface.

Thanos Compactor manages object-storage block optimization, and the complete stack is operated as native systemd services with operational interfaces restricted to localhost.

The architecture includes an explicit historical-data proof in which the live Sidecar is stopped and an older metric is queried successfully through Thanos Query and Store Gateway. This validates that historical data is genuinely being retrieved from object storage rather than from the live Prometheus instance.

## Architecture

    ┌───────────────────────────────────────────────────────────────┐
    │                        Ubuntu Host                            │
    │                                                               │
    │   ┌─────────────────────┐                                     │
    │   │    Node Exporter    │                                     │
    │   │    127.0.0.1:9100  │                                     │
    │   └──────────┬──────────┘                                     │
    │              │                                                │
    │              ▼                                                │
    │   ┌─────────────────────┐                                     │
    │   │     Prometheus      │                                     │
    │   │    127.0.0.1:9090  │                                     │
    │   │                     │                                     │
    │   │ Local TSDB          │                                     │
    │   │ External Labels     │                                     │
    │   │ 6h Local Retention  │                                     │
    │   └──────────┬──────────┘                                     │
    │              │                                                │
    │              │ Prometheus API + TSDB Blocks                   │
    │              ▼                                                │
    │   ┌─────────────────────┐                                     │
    │   │   Thanos Sidecar    │                                     │
    │   │                     │                                     │
    │   │ gRPC :10901         │                                     │
    │   │ HTTP :10902         │                                     │
    │   └─────────┬───────────┘                                     │
    │             │                                                 │
    │             │ Block Upload                                    │
    │             ▼                                                 │
    │   ┌───────────────────────────────┐                            │
    │   │            MinIO              │                            │
    │   │                               │                            │
    │   │ S3 API :9000                  │                            │
    │   │ Console :9001                 │                            │
    │   │ Bucket: thanos-metrics        │                            │
    │   └──────────────┬────────────────┘                            │
    │                  │                                            │
    │                  │ Historical Blocks                          │
    │                  ▼                                            │
    │   ┌───────────────────────────────┐                            │
    │   │      Thanos Store Gateway     │                            │
    │   │                               │                            │
    │   │ gRPC :10905                   │                            │
    │   │ HTTP :10906                   │                            │
    │   └──────────────┬────────────────┘                            │
    │                  │                                            │
    │                  │ Store API                                  │
    │                  ▼                                            │
    │   ┌───────────────────────────────┐                            │
    │   │         Thanos Query          │                            │
    │   │                               │                            │
    │   │ HTTP :10904                   │                            │
    │   │ gRPC :10903                   │                            │
    │   └──────────────▲────────────────┘                            │
    │                  │                                            │
    │                  │ Live Store API                             │
    │                  │                                            │
    │            Thanos Sidecar                                     │
    │                                                               │
    │   ┌───────────────────────────────┐                            │
    │   │       Thanos Compactor        │                            │
    │   │                               │                            │
    │   │ HTTP :10907                   │                            │
    │   │ Object-storage optimization   │                            │
    │   └──────────────┬────────────────┘                            │
    │                  │                                            │
    │                  └──────────────► MinIO                        │
    │                                                               │
    └───────────────────────────────────────────────────────────────┘


## Prerequisites

- Ubuntu Linux
- systemd
- Prometheus
- promtool
- Node Exporter
- Thanos
- MinIO
- MinIO Client
- curl
- wget
- jq
- OpenSSL


## Component Ports

| Component | Interface |
|---|---:|
| MinIO S3 API | 9000 |
| MinIO Console | 9001 |
| Prometheus | 9090 |
| Node Exporter | 9100 |
| Thanos Sidecar gRPC | 10901 |
| Thanos Sidecar HTTP | 10902 |
| Thanos Query gRPC | 10903 |
| Thanos Query HTTP | 10904 |
| Thanos Store gRPC | 10905 |
| Thanos Store HTTP | 10906 |
| Thanos Compactor HTTP | 10907 |

All operational listeners are bound to:

    127.0.0.1

rather than exposed publicly.


## Directory Layout

    /etc/prometheus/
    └── prometheus.yml

    /etc/thanos/
    └── bucket.yml

    /etc/minio/
    └── minio.env

    /var/lib/prometheus/

    /var/lib/thanos/
    ├── store/
    └── compactor/

    /var/lib/minio/

    ~/thanos-storage/
    ├── downloads/
    ├── config/
    ├── evidence/
    │   ├── historical.openmetrics
    │   └── historical_timestamp
    └── verify_stack.sh


## Prometheus Configuration

Prometheus collects:

- its own internal metrics
- Node Exporter metrics
- Thanos Sidecar metrics
- Thanos Query metrics
- Thanos Store Gateway metrics
- Thanos Compactor metrics

External labels identify the Prometheus source:

    cluster: primary-observability
    replica: prometheus-1

These labels are important when Thanos Query combines multiple Prometheus sources.


## Local Prometheus Retention

Prometheus keeps a limited local retention window:

    --storage.tsdb.retention.time=6h

This demonstrates the separation between short-term local storage and durable object storage.

Historical data that leaves the local Prometheus retention window can remain available through Thanos.


## Thanos Sidecar

The Sidecar integrates directly with Prometheus.

Responsibilities include:

- exposing live Prometheus metrics through the Thanos Store API
- reading Prometheus external labels
- discovering Prometheus TSDB blocks
- uploading immutable blocks into object storage

Endpoints:

    127.0.0.1:10901
    127.0.0.1:10902


## MinIO Object Storage

MinIO provides an S3-compatible backend.

Bucket:

    thanos-metrics

Administrative credentials are generated dynamically and stored in:

    /etc/minio/minio.env

Thanos object-store credentials are stored separately in:

    /etc/thanos/bucket.yml

Both files use restricted permissions and must not be committed to source control.


## Store Gateway

Thanos Store Gateway reads historical TSDB blocks directly from MinIO.

It exposes those blocks using the same Thanos Store API used by Sidecar.

Endpoints:

    gRPC: 127.0.0.1:10905
    HTTP: 127.0.0.1:10906

This allows Thanos Query to retrieve historical metrics without requiring those blocks to remain in the local Prometheus TSDB.


## Thanos Query

Thanos Query provides the unified query layer.

Configured stores:

    Sidecar
        127.0.0.1:10901

    Store Gateway
        127.0.0.1:10905

The Query interface therefore combines:

    live Prometheus data
            +
    object-storage historical data


## Thanos Compactor

Thanos Compactor operates against the object-storage bucket.

Responsibilities include:

- block compaction
- block lifecycle optimization
- preparing data for efficient long-term storage
- metadata consistency operations

Local working directory:

    /var/lib/thanos/compactor


## Historical Data Validation

A synthetic historical metric is created:

    historical_demo_gauge

Expected value:

    42

The sample is intentionally generated several hours in the past and converted into a valid Prometheus TSDB block using promtool.

The block is installed into the Prometheus TSDB and subsequently uploaded into MinIO through Thanos Sidecar.


## Strong Object-Storage Proof

The validation goes beyond merely observing files inside the MinIO bucket.

The following sequence is performed:

    1. Generate historical TSDB block

    2. Load block into Prometheus

    3. Confirm Prometheus can query it

    4. Start Thanos Sidecar

    5. Confirm block upload to MinIO

    6. Start Store Gateway

    7. Confirm Store Gateway discovery

    8. Start Thanos Query

    9. Stop Thanos Sidecar

    10. Query historical_demo_gauge through Thanos Query

Because Sidecar is offline during the historical query, Thanos Query cannot obtain the metric from live Prometheus.

The successful request therefore follows:

    Thanos Query
          │
          ▼
    Store Gateway
          │
          ▼
    MinIO
          │
          ▼
    Historical TSDB Block

Expected result:

    historical_demo_gauge = 42

This validates actual object-storage-backed historical querying.


## How to Reproduce

Validate the Prometheus configuration:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml


Verify services:

    for svc in \
      minio \
      node_exporter \
      prometheus \
      thanos-sidecar \
      thanos-query \
      thanos-store \
      thanos-compactor
    do
        systemctl is-active "$svc"
    done


## Query Current Metrics

Query through Thanos:

    curl -fsSG \
      --data-urlencode 'query=up' \
      http://127.0.0.1:10904/api/v1/query


## Inspect Query Stores

    curl -fsS \
      http://127.0.0.1:10904/api/v1/stores | \
      jq .


Expected stores include:

- Sidecar
- Store Gateway


## Query Historical Metric

Read the historical timestamp:

    HIST_SEC=$(
      cat ~/thanos-storage/evidence/historical_timestamp
    )

Query:

    curl -fsSG \
      --data-urlencode 'query=historical_demo_gauge' \
      --data-urlencode "time=${HIST_SEC}" \
      http://127.0.0.1:10904/api/v1/query


Expected value:

    42


## Historical Range Query

    HIST_SEC=$(
      cat ~/thanos-storage/evidence/historical_timestamp
    )

    START_TIME=$(( HIST_SEC - 60 ))
    END_TIME=$(( HIST_SEC + 300 ))

    curl -fsSG \
      --data-urlencode 'query=historical_demo_gauge' \
      --data-urlencode "start=${START_TIME}" \
      --data-urlencode "end=${END_TIME}" \
      --data-urlencode 'step=30' \
      http://127.0.0.1:10904/api/v1/query_range


## Object Storage Inspection

Use the MinIO client with credentials loaded securely from:

    /etc/minio/minio.env

Do not place credentials directly in shell history or source-controlled scripts.


## Tools Used

- Prometheus
- promtool
- Node Exporter
- Thanos Sidecar
- Thanos Query
- Thanos Store Gateway
- Thanos Compactor
- MinIO
- S3-compatible object storage
- systemd
- Linux
- OpenMetrics
- PromQL
- curl
- jq
- Bash


## Key Skills Demonstrated

- Prometheus long-term storage design
- Thanos architecture
- object-storage-backed metrics retention
- Prometheus TSDB block lifecycle
- historical TSDB backfilling
- OpenMetrics ingestion
- Thanos Sidecar integration
- Thanos Store API
- Store Gateway operation
- unified querying
- Compactor operation
- S3-compatible storage configuration
- MinIO administration
- service isolation
- Linux systemd management
- Prometheus external labels
- historical range queries
- operational validation
- metric-storage troubleshooting
- secure secret-file permissions


## Real-World Use Case

Prometheus is optimized for operational monitoring but is not intended to be the sole long-term storage layer for very large or multi-cluster environments.

Organizations commonly need metrics to remain available for:

- capacity planning
- infrastructure trend analysis
- compliance reporting
- anomaly detection
- model and service reliability analysis
- post-incident investigation
- SLO analysis
- infrastructure forecasting
- long-term cost optimization

Thanos separates short-lived Prometheus storage from durable object storage while retaining PromQL compatibility.

This allows observability systems to scale horizontally without requiring every historical metric to remain on expensive local disks.


## Lessons Learned

- Prometheus and object storage serve different roles in a scalable observability architecture.
- Thanos Sidecar creates the bridge between Prometheus and durable object storage.
- Store Gateway makes historical object-storage blocks queryable without loading them back into Prometheus.
- Thanos Query can transparently combine live and historical data.
- External labels are essential when multiple Prometheus instances are introduced.
- Object-storage validation should prove queryability, not merely prove that files exist in a bucket.
- Historical samples used for backfilling must use correct timestamp units.
- Files protected for a service account should be validated using that service account.
- Operational services should not be exposed on all interfaces when they only communicate locally.
- Secrets should be excluded from source control and protected using restrictive ownership and permissions.


## Troubleshooting Log

### Prometheus Configuration Permission Failure

The Prometheus configuration was intentionally restricted to the Prometheus service account.

Running:

    promtool check config

as the normal interactive user resulted in a permission error.

Validation was corrected to run as:

    sudo -u prometheus promtool check config ...


### Prometheus TSDB Permission Failure

The Prometheus data directory belongs to the Prometheus service account.

Running:

    promtool tsdb list /var/lib/prometheus

as the interactive user failed because promtool creates a temporary sandbox directory during inspection.

The command was corrected to execute as the Prometheus user.


### Historical Timestamp Unit Error

The original historical backfill logic supplied a millisecond timestamp to an OpenMetrics path that interpreted the value as seconds.

This generated a TSDB block far in the future.

The malformed block was detected by inspecting its metadata, removed safely, and regenerated using the correct Unix timestamp unit.


### Historical Data Initially Missing

Because the malformed TSDB block existed far outside the requested query timestamp, Prometheus returned an empty result for the historical metric.

After regenerating the TSDB block with the correct timestamp, the historical sample became queryable.


### SSH Session Termination During Failure

An earlier validation block used:

    exit 1

inside the interactive SSH shell.

When validation failed, this terminated the remote shell.

Recovery logic was changed to execute inside a shell function and use:

    return 1

so validation failures no longer terminate the SSH session.


### Object Storage Validation

Waiting a few minutes for Prometheus configured with multi-hour TSDB blocks is not sufficient proof that Sidecar block shipping is working.

A controlled historical TSDB block was therefore created and its complete lifecycle validated explicitly:

    promtool
       ↓
    Prometheus TSDB
       ↓
    Thanos Sidecar
       ↓
    MinIO
       ↓
    Store Gateway
       ↓
    Thanos Query


### Secret Management

MinIO credentials and Thanos S3 configuration contain sensitive values.

These files must never be pushed to GitHub:

    /etc/minio/minio.env
    /etc/thanos/bucket.yml
