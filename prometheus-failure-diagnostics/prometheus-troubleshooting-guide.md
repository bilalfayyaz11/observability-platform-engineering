# Prometheus Troubleshooting Guide

## Purpose

This guide provides a systematic process for diagnosing Prometheus failures across configuration, service management, scraping, networking, permissions, storage, and query behavior.

The goal is to identify the failing layer before changing configuration or restarting services unnecessarily.


## Troubleshooting Flow

Use this sequence:

    Prometheus service
          ↓
    Configuration syntax
          ↓
    File permissions
          ↓
    Listener state
          ↓
    HTTP health/readiness
          ↓
    Target API
          ↓
    DNS / TCP connectivity
          ↓
    Metrics endpoint
          ↓
    PromQL query
          ↓
    Logs


## 1. Configuration Failures

### Symptoms

- Prometheus fails to start
- lifecycle reload fails
- journal contains parsing or configuration errors
- targets disappear unexpectedly


### Validate Configuration

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml


### Typical Causes

- malformed YAML
- missing colons
- incorrect indentation
- malformed target lists
- duplicate configuration definitions
- unsupported options
- scrape timeout larger than scrape interval


### Important Principle

Valid YAML does not always mean valid Prometheus configuration.

promtool validates both parsing and many Prometheus-specific configuration constraints.


## 2. Rule Validation Failures

Validate rules with:

    promtool check rules \
      /etc/prometheus/rules/example.yml


### Common Causes

- malformed PromQL
- missing parentheses
- invalid label matchers
- invalid template syntax
- duplicate rule names within inappropriate contexts


### Missing Metrics Are Different

A rule referencing a metric that does not currently exist can still be syntactically valid.

For example:

    cpu_usage > 0.8

may pass rule validation even when:

    cpu_usage

does not exist.

In that case the expression normally evaluates to an empty vector rather than producing a parser failure.


## 3. Prometheus Service Failure

Check:

    systemctl status prometheus --no-pager

Then inspect:

    journalctl \
      -u prometheus \
      -n 100 \
      --no-pager


### Common Causes

- invalid configuration
- configuration permission denied
- data-directory permission denied
- port 9090 already occupied
- invalid command-line flag
- corrupted or inaccessible TSDB path


## 4. Permission Failures

Check configuration:

    ls -l /etc/prometheus/prometheus.yml

Check storage:

    ls -ld /var/lib/prometheus


Typical ownership:

    prometheus:prometheus


Prometheus must be able to:

    read configuration
    write TSDB data


Executable binaries should normally remain:

    root:root

and executable by the Prometheus service user.


## 5. Listener Problems

Use:

    ss -lntp | grep ':9090 '

Expected local deployment:

    127.0.0.1:9090


If no listener exists:

    systemctl status prometheus

If another process owns the port:

    ss -lntp | grep ':9090 '

A second Prometheus process cannot bind to the same address and port.


## 6. Prometheus Health

Check:

    curl -fsS \
      http://127.0.0.1:9090/-/healthy


Check readiness:

    curl -fsS \
      http://127.0.0.1:9090/-/ready


Healthy means the process is running.

Ready means Prometheus is ready to serve traffic.


## 7. Scrape Target Troubleshooting

Inspect active targets:

    curl -fsS \
      http://127.0.0.1:9090/api/v1/targets |
      jq .


Useful fields include:

    labels.job
    scrapeUrl
    health
    lastError


### Healthy Target

Example:

    node-exporter
    http://127.0.0.1:9100/metrics
    health=up


### Connection Refused

Example:

    127.0.0.1:8080

means DNS/IP resolution succeeded but no service accepted the TCP connection.

Investigate:

    ss -lntp | grep ':8080 '

and:

    curl -v \
      http://127.0.0.1:8080/metrics


### DNS Failure

Example:

    invalid-hostname:9090

means Prometheus cannot resolve the hostname.

Check:

    getent hosts invalid-hostname


If name resolution fails, the HTTP request never reaches the metrics path.


## 8. Metrics Endpoint Problems

Test the target directly:

    curl -fsS \
      http://127.0.0.1:9100/metrics |
      head


If the exporter is listening but this fails, investigate:

- metrics path
- HTTP response code
- TLS requirements
- authentication
- proxy configuration
- application errors


## 9. Prometheus up Metric

Query:

    promtool query instant \
      http://127.0.0.1:9090 \
      'up'


Interpretation:

    up = 1
        last scrape succeeded

    up = 0
        target exists but last scrape failed


## 10. Range Query Testing

Use a time range that actually overlaps current data.

Example:

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


Querying historical dates outside local retention will produce no useful current-environment evidence.


## 11. Configuration Reload

Prometheus supports lifecycle reload when started with:

    --web.enable-lifecycle


Reload with:

    curl -fsS \
      -X POST \
      http://127.0.0.1:9090/-/reload


Before reloading:

    promtool check config \
      /etc/prometheus/prometheus.yml


A safe operational sequence is:

    edit
      ↓
    validate
      ↓
    reload
      ↓
    inspect logs
      ↓
    verify targets


## 12. Failed Reload Behavior

A malformed configuration should be detected before reload.

If a running Prometheus process receives a reload request and the new configuration is invalid, the existing process should remain running with its previously loaded configuration.

This provides a safer path than restarting the service with an unvalidated file.


## 13. Debug Logging

Debug logging can help expose:

- target discovery
- scrape behavior
- TSDB activity
- configuration loading
- service initialization


A safe temporary invocation is:

    timeout 25s \
    sudo -u prometheus \
    prometheus \
      --config.file=/etc/prometheus/prometheus.yml \
      --storage.tsdb.path=/var/lib/prometheus \
      --web.listen-address=127.0.0.1:9090 \
      --log.level=debug


Do not leave an unmanaged foreground Prometheus instance running alongside the systemd service.


## 14. Port Conflicts

Check ownership:

    ss -lntp | grep ':9090 '


Symptoms include errors similar to:

    address already in use


Resolve by:

- identifying the existing process
- avoiding duplicate Prometheus instances
- changing the intended listener if appropriate


## 15. Node Exporter Troubleshooting

Check service:

    systemctl status node_exporter --no-pager


Check endpoint:

    curl -fsS \
      http://127.0.0.1:9100/metrics |
      head


Check Prometheus target:

    curl -fsS \
      http://127.0.0.1:9090/api/v1/targets |
      jq -r '
        .data.activeTargets[]
        | select(.labels.job=="node-exporter")
        | [
            .health,
            .lastError
          ]
        | @tsv
      '


## 16. Storage Problems

Check disk:

    df -h


Check Prometheus data path:

    du -sh /var/lib/prometheus


Check permissions:

    ls -ld /var/lib/prometheus


Potential symptoms:

- startup failure
- WAL errors
- compaction errors
- write failures
- unexpectedly high disk consumption


## 17. Resource Problems

Check memory:

    free -h


Check CPU:

    top


Check Prometheus process:

    ps -eo \
      pid,user,%cpu,%mem,rss,vsz,cmd |
      grep '[p]rometheus'


Resource pressure can appear as:

- slow queries
- OOM kills
- missed scrapes
- high evaluation latency
- slow compaction


## 18. Recent Error Logs

Use:

    journalctl \
      -u prometheus \
      --since "10 minutes ago" \
      --no-pager |
      grep -Ei 'error|fail|warn'


Do not troubleshoot only from logs.

Correlate logs with:

    service state
    configuration validation
    target API
    direct endpoint connectivity


## 19. Controlled Failure Testing

Useful controlled scenarios include:

    configuration permission failure
    malformed configuration
    scrape connection failure
    DNS failure
    port conflict


Each scenario should have:

    baseline
      ↓
    controlled fault
      ↓
    captured evidence
      ↓
    identified root cause
      ↓
    repair
      ↓
    post-repair verification


## 20. Production Troubleshooting Principle

Do not begin by restarting Prometheus.

A better sequence is:

    observe
      ↓
    classify
      ↓
    validate
      ↓
    reproduce where safe
      ↓
    repair
      ↓
    verify

Restarting too early can destroy useful transient evidence and hide the original failure condition.
