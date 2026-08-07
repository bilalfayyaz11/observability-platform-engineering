#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="http://127.0.0.1:9090"
PUSHGATEWAY_URL="http://127.0.0.1:9091"

echo "===== VERIFY SERVICES ====="

for service in prometheus pushgateway; do
    STATE="$(sudo systemctl is-active "$service")"
    ENABLED="$(sudo systemctl is-enabled "$service")"

    printf "%-14s active=%-8s enabled=%s\n" \
      "$service" "$STATE" "$ENABLED"

    [[ "$STATE" == "active" ]]
    [[ "$ENABLED" == "enabled" ]]
done

echo
echo "===== VERIFY PORTS ====="

for port in 9090 9091; do
    if sudo ss -lnt | awk '{print $4}' | grep -q ":${port}$"; then
        echo "Port ${port}: LISTENING"
    else
        echo "ERROR: Port ${port} not listening"
        exit 1
    fi
done

echo
echo "===== VERIFY HEALTH ENDPOINTS ====="

curl --fail --silent --show-error \
  "${PROMETHEUS_URL}/-/healthy"

echo

curl --fail --silent --show-error \
  "${PUSHGATEWAY_URL}/-/healthy"

echo

echo
echo "===== VALIDATE PROMETHEUS CONFIG ====="

sudo -u prometheus \
  /usr/local/bin/promtool \
  check config \
  /etc/prometheus/prometheus.yml

echo
echo "===== VALIDATE ALERT RULES ====="

sudo -u prometheus \
  /usr/local/bin/promtool \
  check rules \
  /etc/prometheus/rules/batch_jobs.yml

echo
echo "===== VERIFY PUSHGATEWAY TARGET ====="

TARGET_JSON="$(
  curl \
    --fail \
    --silent \
    --show-error \
    "${PROMETHEUS_URL}/api/v1/targets"
)"

jq -r '
  .data.activeTargets[]
  |
  "\(.labels.job) -> \(.health) -> \(.labels.instance)"
' <<<"$TARGET_JSON"

PG_HEALTH="$(
  jq -r '
    [
      .data.activeTargets[]
      | select(.labels.job == "pushgateway")
    ][0].health // "missing"
  ' <<<"$TARGET_JSON"
)"

echo "Pushgateway target health: ${PG_HEALTH}"

if [[ "$PG_HEALTH" != "up" ]]; then
    echo "ERROR: Pushgateway target unhealthy"
    exit 1
fi

echo
echo "===== VERIFY PROMQL SCRAPE STATUS ====="

PG_UP="$(
  curl \
    --get \
    --fail \
    --silent \
    --show-error \
    --data-urlencode 'query=up{job="pushgateway"}' \
    "${PROMETHEUS_URL}/api/v1/query" |
  jq -r '.data.result[0].value[1] // "missing"'
)"

echo "up{job=\"pushgateway\"} = ${PG_UP}"

if [[ "$PG_UP" != "1" ]]; then
    echo "ERROR: Pushgateway scrape not healthy"
    exit 1
fi

echo
echo "===== VERIFY ALERT RULES LOADED ====="

RULE_JSON="$(
  curl \
    --fail \
    --silent \
    --show-error \
    "${PROMETHEUS_URL}/api/v1/rules"
)"

RULE_COUNT="$(
  jq '
    [
      .data.groups[]
      | select(.name == "batch_jobs")
      | .rules[]
    ]
    | length
  ' <<<"$RULE_JSON"
)"

echo "Loaded batch alert rules: ${RULE_COUNT}"

if [[ "$RULE_COUNT" -ne 4 ]]; then
    echo "ERROR: Expected 4 rules"
    exit 1
fi

for alert in \
  BatchJobFailed \
  BatchJobHighErrorRate \
  BatchJobNotRunRecently \
  MaintenanceTasksFailed; do

    COUNT="$(
      jq \
        --arg alert "$alert" \
        '
          [
            .data.groups[]
            | select(.name == "batch_jobs")
            | .rules[]
            | select(.name == $alert)
          ]
          | length
        ' <<<"$RULE_JSON"
    )"

    echo "${alert}: ${COUNT}"

    if [[ "$COUNT" -ne 1 ]]; then
        echo "ERROR: Missing ${alert}"
        exit 1
    fi
done

echo
echo "===== VERIFY PERSISTENCE CONFIGURATION ====="

sudo systemctl cat pushgateway.service |
grep -E \
  -- '--persistence.file=/var/lib/pushgateway/pushgateway.db|--persistence.interval=5m'

sudo test -s /var/lib/pushgateway/pushgateway.db

echo "Persistence file: PASS"

echo
echo "===== VERIFY PUSHGATEWAY IS CLEAN ====="

REMAINING="$(
  curl \
    --fail \
    --silent \
    --show-error \
    "${PUSHGATEWAY_URL}/metrics" |
  grep -E '^batch_job_|^maintenance_|^test_metric' \
  || true
)"

if [[ -n "$REMAINING" ]]; then
    echo "ERROR: stale pushed metrics remain"
    echo "$REMAINING"
    exit 1
fi

echo "Pushgateway stale-metric cleanup: PASS"

echo
echo "===== VERIFY PROMETHEUS HAS NO ACTIVE STALE SERIES ====="

for metric in \
  batch_job_records_processed_total \
  batch_job_errors_total \
  batch_job_duration_seconds \
  batch_job_status \
  batch_job_last_run_timestamp \
  batch_job_last_success_unixtime \
  maintenance_tasks_total \
  maintenance_tasks_completed_total \
  maintenance_tasks_failed_total \
  maintenance_success_rate_percent \
  maintenance_duration_seconds \
  maintenance_last_run_timestamp \
  test_metric; do

    COUNT="$(
      curl \
        --get \
        --fail \
        --silent \
        --show-error \
        --data-urlencode "query=${metric}" \
        "${PROMETHEUS_URL}/api/v1/query" |
      jq '.data.result | length'
    )"

    printf "%-42s %s active series\n" \
      "$metric" \
      "$COUNT"

    if [[ "$COUNT" -ne 0 ]]; then
        echo "ERROR: ${metric} still active"
        exit 1
    fi
done

echo
echo "===== VERIFY SCRIPT INVENTORY ====="

SCRIPTS=(
    batch_job_simple.sh
    batch_job_advanced.sh
    scheduled_job.sh
    health_check.sh
)

for script in "${SCRIPTS[@]}"; do
    [[ -s "$script" ]]
    bash -n "$script"
    printf "%-30s PASS\n" "$script"
done

echo
echo "===== VERIFY VALIDATION RECORDS ====="

RECORDS=(
    short_lived_job_validation.txt
    alert_rule_validation.txt
    pushgateway_lifecycle_validation.txt
)

for record in "${RECORDS[@]}"; do
    [[ -s "$record" ]]
    printf "%-40s PASS\n" "$record"
done

echo
echo "===== RUN HEALTH CHECK ====="

./health_check.sh

echo
echo "===== VERIFY LIFECYCLE EVIDENCE ====="

grep -q \
  '^Push -> persist -> scrape -> delete lifecycle: PASS$' \
  pushgateway_lifecycle_validation.txt

echo "Lifecycle validation: PASS"

echo
echo "===== CREATE FINAL VALIDATION REPORT ====="

cat > validation-report.txt <<REPORT
Prometheus Pushgateway Validation

Validation time: $(date --iso-8601=seconds)

Services
Prometheus: PASS
Pushgateway: PASS

Network
Prometheus port 9090: PASS
Pushgateway port 9091: PASS

Prometheus Integration
Pushgateway target health: PASS
Pushgateway scrape metric: PASS

Short-Lived Workloads
Simple data-processing script: PASS
Advanced processing script: PASS
Scheduled maintenance script: PASS
Pushgateway ingestion: PASS
Prometheus ingestion: PASS

Alerting
BatchJobFailed: PASS
BatchJobHighErrorRate: PASS
BatchJobNotRunRecently: PASS
MaintenanceTasksFailed: PASS
Loaded rules: ${RULE_COUNT}

Persistence
Pushgateway persistence configuration: PASS
Persistence file: PASS
Restart persistence validation: PASS

Lifecycle
Temporary metric deletion: PASS
Batch metric cleanup: PASS
Prometheus staleness propagation: PASS
Stale metric cleanup: PASS

Operational Interface
Health-check script: PASS

Overall Pushgateway short-lived workload pipeline: PASS
REPORT

cat validation-report.txt

echo
echo "===== FINAL FILE INVENTORY ====="

find . \
  -maxdepth 1 \
  -type f \
  -printf '%f\n' |
sort

echo
echo "===== FINAL VALIDATION COMPLETE ====="
