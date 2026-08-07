#!/usr/bin/env bash
set -euo pipefail

cd /home/ubuntu/prometheus-alerting-engineering

echo "===== RECORD CURRENT WEBHOOK LOG SIZE ====="

BEFORE_LINES="$(wc -l < webhook_alerts.log)"

echo "Webhook lines before resolution check: ${BEFORE_LINES}"

echo "===== VERIFY CPU STRESS IS STOPPED ====="

if [[ -f cpu_stress.pids ]]; then
    echo "WARNING: PID file still exists"
    ./stop_cpu_stress.sh || true
fi

if pgrep -x yes >/dev/null 2>&1; then
    echo "WARNING: residual yes processes found"
    pkill -x yes || true
fi

sleep 5

if pgrep -x yes >/dev/null 2>&1; then
    echo "ERROR: CPU stress processes are still running"
    exit 1
else
    echo "CPU stress processes: STOPPED"
fi

echo "===== VERIFY CPU UTILIZATION IS DROPPING ====="

curl \
  --get \
  --silent \
  --show-error \
  --data-urlencode \
  'query=100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)' \
  http://127.0.0.1:9090/api/v1/query |
jq -r '
  .data.result[]
  |
  "instance=\(.metric.instance) cpu=\(.value[1])%"
'

echo "===== WAIT FOR RULE RE-EVALUATION ====="

sleep 45

echo "===== CHECK HIGHCPUUSAGE RULE STATE ====="

RULE_JSON="$(
  curl \
    --fail \
    --silent \
    --show-error \
    http://127.0.0.1:9090/api/v1/rules
)"

echo "$RULE_JSON" |
jq '
  .data.groups[].rules[]
  | select(.name == "HighCPUUsage")
  | {
      name: .name,
      state: .state,
      health: .health,
      alerts: .alerts
    }
'

RULE_STATE="$(
  jq -r '
    .data.groups[].rules[]
    | select(.name == "HighCPUUsage")
    | .state
  ' <<<"$RULE_JSON"
)"

echo "HighCPUUsage state: ${RULE_STATE}"

if [[ "$RULE_STATE" != "inactive" ]]; then
    echo "HighCPUUsage is not inactive yet."
    echo "Waiting another 45 seconds..."
    sleep 45

    RULE_JSON="$(
      curl \
        --fail \
        --silent \
        --show-error \
        http://127.0.0.1:9090/api/v1/rules
    )"

    RULE_STATE="$(
      jq -r '
        .data.groups[].rules[]
        | select(.name == "HighCPUUsage")
        | .state
      ' <<<"$RULE_JSON"
    )"

    echo "HighCPUUsage state after additional wait: ${RULE_STATE}"
fi

if [[ "$RULE_STATE" != "inactive" ]]; then
    echo "ERROR: HighCPUUsage did not resolve"
    exit 1
fi

echo "===== VERIFY PROMETHEUS ACTIVE ALERT CLEARED ====="

PROM_ALERTS="$(
  curl \
    --fail \
    --silent \
    --show-error \
    http://127.0.0.1:9090/api/v1/alerts
)"

PROM_COUNT="$(
  jq '
    [
      .data.alerts[]
      | select(.labels.alertname == "HighCPUUsage")
    ]
    | length
  ' <<<"$PROM_ALERTS"
)"

echo "Prometheus active HighCPUUsage alerts: ${PROM_COUNT}"

if [[ "$PROM_COUNT" -ne 0 ]]; then
    echo "ERROR: Prometheus still reports HighCPUUsage active"
    exit 1
fi

echo "===== WAIT FOR ALERTMANAGER RESOLUTION DELIVERY ====="

sleep 20

echo "===== VERIFY ALERTMANAGER STATE ====="

AM_ALERTS="$(
  curl \
    --fail \
    --silent \
    --show-error \
    http://127.0.0.1:9093/api/v2/alerts
)"

AM_ACTIVE_COUNT="$(
  jq '
    [
      .[]
      | select(
          .labels.alertname == "HighCPUUsage"
          and .status.state == "active"
        )
    ]
    | length
  ' <<<"$AM_ALERTS"
)"

echo "Alertmanager active HighCPUUsage alerts: ${AM_ACTIVE_COUNT}"

if [[ "$AM_ACTIVE_COUNT" -ne 0 ]]; then
    echo "ERROR: Alertmanager still reports HighCPUUsage active"
    exit 1
fi

echo "===== VERIFY RESOLVED WEBHOOK DELIVERY ====="

AFTER_LINES="$(wc -l < webhook_alerts.log)"

echo "Webhook lines before: ${BEFORE_LINES}"
echo "Webhook lines after:  ${AFTER_LINES}"

if [[ "$AFTER_LINES" -le "$BEFORE_LINES" ]]; then
    echo "ERROR: No new webhook notification appeared after resolution"
    exit 1
fi

NEW_LINES="$((AFTER_LINES - BEFORE_LINES))"

echo "New webhook records: ${NEW_LINES}"

tail -n "$NEW_LINES" webhook_alerts.log |
jq -c '
  select(
    .payload.alerts[]?
    | (
        .labels.alertname == "HighCPUUsage"
        and .status == "resolved"
      )
  )
'

RESOLVED_COUNT="$(
  tail -n "$NEW_LINES" webhook_alerts.log |
  jq -s '
    [
      .[]
      | select(
          .payload.alerts[]?
          | (
              .labels.alertname == "HighCPUUsage"
              and .status == "resolved"
            )
        )
    ]
    | length
  '
)"

echo "Resolved HighCPUUsage webhook deliveries: ${RESOLVED_COUNT}"

if [[ "$RESOLVED_COUNT" -lt 1 ]]; then
    echo "ERROR: No resolved HighCPUUsage webhook delivery found"
    exit 1
fi

echo "===== VERIFY ALL SERVICES REMAIN HEALTHY ====="

for service in \
  prometheus \
  node_exporter \
  alertmanager \
  prometheus-webhook; do

    STATE="$(sudo systemctl is-active "$service")"

    printf "%-22s %s\n" \
      "$service" \
      "$STATE"

    if [[ "$STATE" != "active" ]]; then
        echo "ERROR: ${service} is not active"
        exit 1
    fi
done

echo "===== CREATE PIPELINE VALIDATION RECORD ====="

cat > alert_pipeline_validation.txt <<REPORT
Prometheus Alerting Pipeline Validation

HighCPUUsage firing transition: PASS
Prometheus active alert detection: PASS
Alertmanager alert ingestion: PASS
Webhook firing delivery: PASS

CPU stress termination: PASS
HighCPUUsage resolution transition: PASS
Prometheus active alert clearance: PASS
Alertmanager resolution handling: PASS
Webhook resolved delivery: PASS

Prometheus service: PASS
Node Exporter service: PASS
Alertmanager service: PASS
Webhook receiver service: PASS

End-to-end alert lifecycle: PASS
REPORT

cat alert_pipeline_validation.txt

echo "===== STEP 6 COMPLETE ====="
