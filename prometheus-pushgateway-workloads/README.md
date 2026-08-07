# Prometheus Pushgateway for Short-Lived Workloads

## What This Does

This implementation provides a production-oriented monitoring pattern for short-lived and batch workloads using Prometheus Pushgateway.

Traditional Prometheus monitoring assumes that an application exposes a long-running HTTP metrics endpoint that Prometheus can scrape periodically.

That model does not work well for workloads that may execute for only a few seconds and terminate before Prometheus has a chance to scrape them.

Pushgateway solves this problem by acting as an intermediary.

Short-lived workloads push their final metrics to Pushgateway before terminating. Pushgateway retains those metrics, and Prometheus scrapes Pushgateway through its normal pull-based collection model.

This implementation demonstrates the complete lifecycle:

    Short-lived workload
            ↓
    Execute business operation
            ↓
    Generate Prometheus metrics
            ↓
    Push metrics over HTTP
            ↓
        Pushgateway
            ↓
      Persistent storage
            ↓
       Prometheus scrape
            ↓
          PromQL
            ↓
       Alert evaluation
            ↓
    Explicit stale-metric cleanup

The implementation also validates a critical operational characteristic of Pushgateway: pushed metrics survive after the originating process exits and can persist across Pushgateway restarts, so obsolete metric groups must be explicitly deleted.

## Architecture

    ┌──────────────────────────────────────────────────────────────┐
    │                    Short-Lived Workloads                     │
    │                                                              │
    │  ┌──────────────────────┐                                   │
    │  │ Data Processing      │                                   │
    │  │                      │                                   │
    │  │ Records              │                                   │
    │  │ Errors               │                                   │
    │  │ Duration             │                                   │
    │  │ Success timestamp    │                                   │
    │  └──────────┬───────────┘                                   │
    │             │                                                │
    │  ┌──────────▼───────────┐                                   │
    │  │ Advanced Processor   │                                   │
    │  │                      │                                   │
    │  │ Records              │                                   │
    │  │ Errors               │                                   │
    │  │ Status               │                                   │
    │  │ Last-run timestamp   │                                   │
    │  └──────────┬───────────┘                                   │
    │             │                                                │
    │  ┌──────────▼───────────┐                                   │
    │  │ Maintenance Process  │                                   │
    │  │                      │                                   │
    │  │ Completed work       │                                   │
    │  │ Failed work          │                                   │
    │  │ Success rate         │                                   │
    │  │ Duration             │                                   │
    │  └──────────┬───────────┘                                   │
    │             │                                                │
    │             │ Prometheus text exposition                    │
    │             │ HTTP POST                                     │
    │             ▼                                                │
    │  ┌───────────────────────────────┐                           │
    │  │         Pushgateway           │                           │
    │  │                               │                           │
    │  │      127.0.0.1:9091          │                           │
    │  │                               │                           │
    │  │ Metric grouping keys          │                           │
    │  │ Metric retention              │                           │
    │  │ Persistent state              │                           │
    │  └──────────────┬────────────────┘                           │
    │                 │                                            │
    │                 │ Prometheus scrape                          │
    │                 ▼                                            │
    │  ┌───────────────────────────────┐                           │
    │  │          Prometheus           │                           │
    │  │                               │                           │
    │  │      127.0.0.1:9090          │                           │
    │  │                               │                           │
    │  │ Time-series storage           │                           │
    │  │ PromQL                        │                           │
    │  │ Alert evaluation              │                           │
    │  └──────────────┬────────────────┘                           │
    │                 │                                            │
    │                 ▼                                            │
    │        Operational Health Checks                             │
    └──────────────────────────────────────────────────────────────┘

## Repository Structure

    prometheus-pushgateway-workloads/
    ├── README.md
    ├── batch_job_simple.sh
    ├── batch_job_advanced.sh
    ├── scheduled_job.sh
    ├── health_check.sh
    ├── final_pushgateway_validation.sh
    ├── short_lived_job_validation.txt
    ├── alert_rule_validation.txt
    ├── pushgateway_lifecycle_validation.txt
    └── validation-report.txt

## Why Pushgateway Is Needed

Prometheus normally uses a pull model:

    Application
        ↓
    Long-lived /metrics endpoint
        ↓
    Prometheus periodically scrapes it

This works well for persistent services.

A short-lived workload creates a different problem:

    Process starts
        ↓
    Work completes
        ↓
    Process exits

The process may disappear before the next Prometheus scrape.

Pushgateway provides an intermediate metrics endpoint:

    Short-lived process
        ↓
    Push final metrics
        ↓
    Process exits
        ↓
    Pushgateway retains metrics
        ↓
    Prometheus scrapes them later

This allows Prometheus to observe workloads whose execution lifetime is shorter than the configured scrape interval.

## Services

The environment runs two persistent monitoring services:

    prometheus.service
    pushgateway.service

Verify them with:

    sudo systemctl status prometheus
    sudo systemctl status pushgateway

Both are enabled to start automatically.

## Network Endpoints

Prometheus:

    127.0.0.1:9090

Pushgateway:

    127.0.0.1:9091

The services are intentionally bound to the loopback interface because all components operate on the same host.

This avoids unnecessarily exposing internal monitoring endpoints.

## Prometheus Configuration

Prometheus scrapes itself and Pushgateway.

Conceptually:

    scrape_configs:

      prometheus
          ↓
      127.0.0.1:9090

      pushgateway
          ↓
      127.0.0.1:9091

Pushgateway uses:

    honor_labels: true

This preserves the `job` and `instance` labels supplied through Pushgateway grouping keys rather than replacing them with the Prometheus scrape job labels.

## Simple Data Processing Workload

Run:

    ./batch_job_simple.sh

The process simulates a short-lived data-processing operation.

It publishes:

    batch_job_records_processed_total

    batch_job_errors_total

    batch_job_duration_seconds

    batch_job_last_success_unixtime

Example grouping key:

    job="data_processing_job"
    instance="batch-server-01"

Example result:

    batch_job_records_processed_total{
      instance="batch-server-01",
      job="data_processing_job"
    } 1250

The process terminates immediately after pushing its final metrics.

## Advanced Processing Workload

Run:

    ./batch_job_advanced.sh

This workload simulates processing 50 records with randomly generated processing errors.

It publishes:

    batch_job_records_processed_total

    batch_job_errors_total

    batch_job_duration_seconds

    batch_job_status

    batch_job_last_run_timestamp

The status metric uses:

    1 = successful execution
    0 = failed execution

The runtime hostname is used as the Pushgateway `instance` grouping label.

## Scheduled Maintenance Workload

Run:

    ./scheduled_job.sh

This process simulates scheduled operational work such as:

    cleanup_temp_files
    rotate_logs
    update_cache
    backup_config
    check_disk_space

It publishes:

    maintenance_tasks_total

    maintenance_tasks_completed_total

    maintenance_tasks_failed_total

    maintenance_success_rate_percent

    maintenance_duration_seconds

    maintenance_last_run_timestamp

This models workloads that would commonly execute through cron, systemd timers, orchestration platforms, or scheduled automation.

## Prometheus Text Exposition Format

Metrics are pushed using Prometheus' text representation.

Example:

    # HELP batch_job_status Job completion status
    # TYPE batch_job_status gauge
    batch_job_status 1

The scripts stream these metrics directly into curl:

    generated metrics
          ↓
    standard input
          ↓
    curl --data-binary @-
          ↓
    Pushgateway HTTP endpoint

This avoids temporary metric files.

## Pushgateway Grouping Keys

A push is sent to a URL such as:

    /metrics/job/data_processing_job/instance/batch-server-01

The path determines the Pushgateway grouping labels.

Conceptually:

    /metrics
        /job/<job-name>
        /instance/<instance-name>

These labels identify which pushed metric group belongs to which workload execution identity.

## End-to-End Data Flow

The complete ingestion path is:

    Shell process
        ↓
    Runtime metrics
        ↓
    Prometheus text exposition
        ↓
    HTTP push
        ↓
    Pushgateway
        ↓
    Retained metric group
        ↓
    Prometheus scrape
        ↓
    Time-series database
        ↓
    PromQL query

The validation confirmed that values pushed from all three workload types were later queryable through Prometheus.

## PromQL Validation

Example:

    batch_job_records_processed_total{
      job="data_processing_job"
    }

Another example:

    batch_job_status{
      job="advanced_data_processor"
    }

Maintenance example:

    maintenance_tasks_completed_total{
      job="system_maintenance"
    }

A non-empty result confirms:

    process
        ↓
    Pushgateway
        ↓
    Prometheus

is functioning correctly.

## Alerting

The implementation includes four Prometheus alert rules.

### BatchJobFailed

Expression:

    batch_job_status == 0

Purpose:

Detect a short-lived workload that explicitly reports failed execution.

Severity:

    critical

## BatchJobHighErrorRate

Expression:

    batch_job_errors_total
    /
    batch_job_records_processed_total
    >
    0.1

Purpose:

Detect processing workloads where more than ten percent of processed records are represented as errors.

Severity:

    warning

## BatchJobNotRunRecently

Expression:

    time()
    -
    batch_job_last_success_unixtime
    >
    86400

Purpose:

Detect a workload whose last recorded successful execution is more than 24 hours old.

Severity:

    warning

This is particularly useful for scheduled processes where absence of execution can itself represent a failure.

## MaintenanceTasksFailed

Expression:

    maintenance_tasks_failed_total > 0

Purpose:

Detect maintenance executions where one or more internal operations failed.

Severity:

    warning

## Rule Validation

Prometheus rules are checked with:

    sudo -u prometheus \
      promtool check rules \
      /etc/prometheus/rules/batch_jobs.yml

The complete configuration is checked with:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml

Four rules must be loaded:

    BatchJobFailed
    BatchJobHighErrorRate
    BatchJobNotRunRecently
    MaintenanceTasksFailed

## Operational Health Check

Run:

    ./health_check.sh

The script validates:

    Pushgateway health
    Prometheus health
    Prometheus → Pushgateway scrape
    batch_jobs rule group
    alert-rule count
    firing-alert count

Example:

    Pushgateway: OK
    Prometheus: OK
    Prometheus is scraping Pushgateway: OK
    Loaded batch_jobs rule groups: 1
    Loaded batch alert rules: 4

## Pushgateway Persistence

Pushgateway is configured with persistent storage:

    --persistence.file=/var/lib/pushgateway/pushgateway.db

The state directory is:

    /var/lib/pushgateway

A temporary metric was pushed:

    test_metric 42

The validation then performed:

    push metric
        ↓
    verify metric
        ↓
    stop Pushgateway
        ↓
    verify persistence database
        ↓
    start Pushgateway
        ↓
    query metric again

The value remained available after the process restart.

This proves that pushed metrics can survive Pushgateway process lifecycle events.

## Pushgateway Is Not an Event Store

Pushgateway persistence does not transform the service into an event-history database.

The latest metric group remains exposed until:

- it is replaced by another push using the same grouping key; or
- it is explicitly deleted.

Prometheus itself stores historical samples separately according to its retention policy.

## Stale Metric Problem

A major operational risk with Pushgateway is stale data.

Consider:

    Scheduled workload succeeds
        ↓
    pushes status = 1
        ↓
    workload disappears
        ↓
    workload never runs again
        ↓
    Pushgateway still exposes status = 1

Without explicit lifecycle management, the retained value may incorrectly appear to represent the current state of a workload that no longer exists.

This is why Pushgateway cleanup is part of operational correctness.

## Explicit Metric Deletion

Example deletion:

    curl \
      --request DELETE \
      http://127.0.0.1:9091/metrics/job/data_processing_job/instance/batch-server-01

The advanced workload is deleted using:

    job="advanced_data_processor"
    instance=<hostname>

The scheduled maintenance workload is deleted using:

    job="system_maintenance"
    instance=<hostname>

The complete grouping key must match the labels used during the original push.

## Prometheus Staleness Propagation

Deleting a metric from Pushgateway does not erase previously stored Prometheus samples.

Instead:

    Pushgateway stops exposing series
            ↓
    next Prometheus scrape observes absence
            ↓
    series becomes stale
            ↓
    future instant queries stop returning it

The implementation waits for scrape propagation and validates that the deleted metric series disappear from current PromQL query results.

## Lifecycle Model

The validated lifecycle is:

    CREATE WORKLOAD
          ↓
    RUN WORKLOAD
          ↓
    GENERATE METRICS
          ↓
    PUSH METRICS
          ↓
    JOB TERMINATES
          ↓
    PUSHGATEWAY RETAINS METRICS
          ↓
    PROMETHEUS SCRAPES METRICS
          ↓
    ALERT RULES EVALUATE METRICS
          ↓
    METRIC BECOMES OBSOLETE
          ↓
    DELETE GROUPING KEY
          ↓
    PROMETHEUS MARKS SERIES STALE

This lifecycle is more important than simply installing Pushgateway.

## Persistence Test Workflow

The persistence validation follows this sequence:

    POST test_metric=42
          ↓
    Pushgateway exposes metric
          ↓
    Persistence database written
          ↓
    Pushgateway restarted
          ↓
    Persistence database reloaded
          ↓
    test_metric still equals 42
          ↓
    Prometheus scrapes restored metric
          ↓
    grouping key deleted
          ↓
    metric removed

## Service Security

The implementation uses dedicated service identities:

    prometheus
    pushgateway

Neither process runs as root.

## Binary Ownership

Installed executables remain:

    root:root
    0755

This prevents the service identities from modifying or replacing their own executable binaries.

## Mutable State Separation

Pushgateway executable:

    /usr/local/bin/pushgateway

Pushgateway mutable state:

    /var/lib/pushgateway

Prometheus executable:

    /usr/local/bin/prometheus

Prometheus mutable state:

    /var/lib/prometheus

This separates application binaries from runtime data.

## systemd Hardening

Services use controls including:

    NoNewPrivileges=true
    PrivateTmp=true
    ProtectHome=true
    ProtectSystem=strict
    ProtectControlGroups=true
    ProtectKernelModules=true
    ProtectKernelTunables=true

Only explicitly required state directories are writable.

## Failure-Aware HTTP Requests

The workload scripts use:

    curl --fail --silent --show-error

instead of reporting success after any HTTP response.

This means HTTP 4xx or 5xx responses cause the script to fail rather than falsely printing that the push succeeded.

## Validation Evidence

The implementation generates several validation records.

### Short-Lived Pipeline Validation

    short_lived_job_validation.txt

Validates:

- simple workload execution
- advanced workload execution
- maintenance execution
- Pushgateway ingestion
- Prometheus ingestion
- process termination after execution

### Alert Validation

    alert_rule_validation.txt

Validates:

- four alert definitions
- rule syntax
- configuration syntax
- loaded rule group
- Pushgateway scrape health

### Lifecycle Validation

    pushgateway_lifecycle_validation.txt

Validates:

- temporary metric push
- persistence file creation
- persistence across restart
- Prometheus recovery
- metric deletion
- batch cleanup
- stale-series propagation

### Final Validation

    validation-report.txt

Summarizes the complete deployment and lifecycle result.

## Final Validation

Run:

    ./final_pushgateway_validation.sh

The validator checks:

- Prometheus service state
- Pushgateway service state
- ports 9090 and 9091
- health endpoints
- Prometheus configuration
- alert-rule syntax
- Pushgateway target health
- `up{job="pushgateway"}`
- four required alerts
- persistence configuration
- persistence database
- stale Pushgateway groups
- stale Prometheus series
- workload script syntax
- validation evidence
- operational health checks

## Skills Demonstrated

- Prometheus architecture
- Prometheus Pushgateway
- short-lived workload instrumentation
- batch workload monitoring
- Prometheus text exposition format
- HTTP metric publishing
- Pushgateway grouping keys
- PromQL
- Prometheus scrape configuration
- `honor_labels`
- alert-rule engineering
- job failure detection
- workload staleness detection
- error-rate monitoring
- Pushgateway persistence
- metric lifecycle management
- stale-series cleanup
- systemd service engineering
- Linux service identities
- systemd hardening
- shell scripting
- curl
- jq
- persistence verification
- operational validation

## Real-World Use Cases

The same pattern can be used for workloads such as:

    database backups
    ETL pipelines
    scheduled synchronization
    report generation
    billing processes
    file imports
    batch inference
    data preprocessing
    cleanup automation
    certificate rotation
    periodic integrity checks
    scheduled infrastructure maintenance

Any process that cannot expose a persistent scrape endpoint may potentially require a pattern like Pushgateway.

## Important Design Principle

Pushgateway should not replace normal Prometheus scraping for persistent services.

A long-running application should normally expose:

    /metrics

directly and allow Prometheus to scrape it.

Pushgateway is most appropriate when the workload lifecycle makes direct scraping impractical.

## Lessons Learned

- Prometheus primarily operates through pull-based metric collection.
- Short-lived processes may terminate before Prometheus can scrape them.
- Pushgateway bridges that lifecycle gap.
- The short-lived workload pushes metrics, but Prometheus still pulls them from Pushgateway.
- Pushgateway grouping keys become identifying metric labels.
- `honor_labels` preserves workload-provided job and instance labels.
- Pushgateway retains metrics after the originating workload exits.
- Persistent Pushgateway storage survives process restarts.
- Persistent pushed data can become operationally stale.
- Pushgateway does not automatically know whether the originating workload still exists.
- Explicit deletion is therefore part of the metric lifecycle.
- Prometheus requires scrape/staleness propagation before deleted series disappear from current instant queries.
- Workload success is different from metric-delivery success.
- HTTP pushes should fail explicitly when Pushgateway rejects the request.
- Alerting can detect both reported failures and absence of expected workload execution.
- Dedicated runtime users reduce service privileges.
- Runtime users should not own writable executable binaries.
- Mutable state should be separated from immutable executables.
- Pushgateway is best understood as an intermediary for ephemeral workload metrics, not as a universal replacement for direct Prometheus instrumentation.

## Troubleshooting

### Pushgateway Is Not Running

Check:

    sudo systemctl status pushgateway

Inspect logs:

    sudo journalctl \
      -u pushgateway \
      -n 100 \
      --no-pager

Check endpoint:

    curl \
      http://127.0.0.1:9091/-/healthy

## Prometheus Cannot Scrape Pushgateway

Check Pushgateway directly:

    curl \
      http://127.0.0.1:9091/metrics

Inspect Prometheus targets:

    curl \
      http://127.0.0.1:9090/api/v1/targets

Query:

    up{job="pushgateway"}

Expected:

    1

## Workload Push Fails

Verify Pushgateway:

    curl \
      http://127.0.0.1:9091/-/healthy

Then test manually:

    echo 'manual_test_metric 1' |
    curl \
      --fail \
      --show-error \
      --data-binary @- \
      http://127.0.0.1:9091/metrics/job/manual_test

## Metric Exists in Pushgateway but Not Prometheus

Confirm the Pushgateway scrape target is healthy.

Then wait at least one Prometheus scrape interval.

Query through Prometheus again.

## Deleted Metric Still Appears in Prometheus

The Pushgateway deletion and Prometheus time-series storage are separate operations.

After deletion:

    Pushgateway immediately stops exposing the series.

Prometheus may require the next scrape and staleness processing before an instant query stops returning it.

Wait for another scrape interval before interpreting the metric as still active.

## Alert Rule Does Not Load

Validate:

    sudo -u prometheus \
      promtool check rules \
      /etc/prometheus/rules/batch_jobs.yml

Then validate:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml

Reload:

    curl \
      --request POST \
      http://127.0.0.1:9090/-/reload

## Persistence Does Not Survive Restart

Verify the configured path:

    sudo systemctl cat pushgateway

Check:

    /var/lib/pushgateway/pushgateway.db

Verify the Pushgateway service identity can write to:

    /var/lib/pushgateway

## Final Result

The completed implementation validated:

    Prometheus service:                     PASS
    Pushgateway service:                    PASS

    Prometheus port 9090:                   PASS
    Pushgateway port 9091:                  PASS

    Pushgateway scrape target:              PASS
    Pushgateway PromQL up metric:           PASS

    Simple workload:                        PASS
    Advanced workload:                      PASS
    Scheduled maintenance workload:         PASS

    Pushgateway metric ingestion:           PASS
    Prometheus metric ingestion:            PASS

    BatchJobFailed:                         PASS
    BatchJobHighErrorRate:                  PASS
    BatchJobNotRunRecently:                 PASS
    MaintenanceTasksFailed:                 PASS

    Pushgateway persistence:                PASS
    Restart persistence:                    PASS

    Temporary metric deletion:              PASS
    Batch workload cleanup:                 PASS
    Prometheus staleness propagation:       PASS

    Health-check interface:                 PASS

    Push -> persist -> scrape -> delete:    PASS

    Overall short-lived workload pipeline:  PASS
