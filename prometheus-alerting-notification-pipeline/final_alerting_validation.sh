#!/usr/bin/env bash
set -euo pipefail

cd /home/ubuntu/prometheus-alerting-engineering

echo "===== VERIFY SERVICE STATES ====="

SERVICES=(
    prometheus
    node_exporter
    alertmanager
    prometheus-webhook
)

for service in "${SERVICES[@]}"; do
    STATE="$(sudo systemctl is-active "$service")"
    ENABLED="$(sudo systemctl is-enabled "$service")"

    printf "%-22s active=%-10s enabled=%s\n" \
        "$service" \
        "$STATE" \
        "$ENABLED"

    if [[ "$STATE" != "active" ]]; then
        echo "ERROR: ${service} is not active"
        exit 1
    fi

    if [[ "$ENABLED" != "enabled" ]]; then
        echo "ERROR: ${service} is not enabled"
        exit 1
    fi
done

echo
echo "===== VERIFY LISTENING PORTS ====="

for port in 8080 9090 9093 9100; do

    if ! sudo ss -lnt |
        awk '{print $4}' |
        grep -q ":${port}$"; then

        echo "ERROR: Port ${port} is not listening"
        exit 1
    fi

    echo "Port ${port}: PASS"
done

echo
echo "===== VERIFY PROMETHEUS READY ====="

curl \
  --fail \
  --silent \
  --show-error \
  http://127.0.0.1:9090/-/ready

echo

echo "===== VERIFY ALERTMANAGER READY ====="

curl \
  --fail \
  --silent \
  --show-error \
  http://127.0.0.1:9093/-/ready

echo

echo "===== VERIFY NODE EXPORTER ====="

NODE_HTTP="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    http://127.0.0.1:9100/metrics
)"

echo "Node Exporter HTTP: ${NODE_HTTP}"

if [[ "$NODE_HTTP" != "200" ]]; then
    echo "ERROR: Node Exporter metrics endpoint failed"
    exit 1
fi

echo
echo "===== VERIFY PROMETHEUS CONFIGURATION ====="

sudo -u prometheus \
  /usr/local/bin/promtool \
  check config \
  /etc/prometheus/prometheus.yml

echo
echo "===== VERIFY PROMETHEUS ALERT RULES ====="

sudo -u prometheus \
  /usr/local/bin/promtool \
  check rules \
  /etc/prometheus/alert_rules.yml

echo
echo "===== VERIFY ALERTMANAGER CONFIGURATION ====="

sudo -u prometheus \
  /usr/local/bin/amtool \
  check-config \
  /etc/alertmanager/alertmanager.yml

echo
echo "===== VERIFY PROMETHEUS TARGETS ====="

TARGET_JSON="$(
  curl \
    --fail \
    --silent \
    --show-error \
    http://127.0.0.1:9090/api/v1/targets
)"

jq -r '
  .data.activeTargets[]
  |
  "\(.labels.job) -> \(.health) -> \(.labels.instance)"
' <<<"$TARGET_JSON"

TARGET_COUNT="$(
  jq '.data.activeTargets | length' <<<"$TARGET_JSON"
)"

UP_COUNT="$(
  jq '
    [
      .data.activeTargets[]
      | select(.health == "up")
    ]
    | length
  ' <<<"$TARGET_JSON"
)"

echo "Total targets:   ${TARGET_COUNT}"
echo "Healthy targets: ${UP_COUNT}"

if [[ "$TARGET_COUNT" -ne 2 ]]; then
    echo "ERROR: Expected 2 targets"
    exit 1
fi

if [[ "$UP_COUNT" -ne 2 ]]; then
    echo "ERROR: Expected 2 healthy targets"
    exit 1
fi

echo
echo "===== VERIFY ALERT RULE INVENTORY ====="

RULE_JSON="$(
  curl \
    --fail \
    --silent \
    --show-error \
    http://127.0.0.1:9090/api/v1/rules
)"

jq -r '
  .data.groups[].rules[]
  | select(.type == "alerting")
  |
  "\(.name) -> state=\(.state) health=\(.health)"
' <<<"$RULE_JSON"

RULE_COUNT="$(
  jq '
    [
      .data.groups[].rules[]
      | select(.type == "alerting")
    ]
    | length
  ' <<<"$RULE_JSON"
)"

echo "Loaded alert rules: ${RULE_COUNT}"

if [[ "$RULE_COUNT" -ne 4 ]]; then
    echo "ERROR: Expected 4 alert rules"
    exit 1
fi

echo
echo "===== VERIFY REQUIRED ALERT NAMES ====="

REQUIRED_ALERTS=(
    HighCPUUsage
    HighMemoryUsage
    DiskSpaceLow
    ServiceDown
)

for alert in "${REQUIRED_ALERTS[@]}"; do

    COUNT="$(
      jq \
        --arg alert "$alert" \
        '
          [
            .data.groups[].rules[]
            | select(
                .type == "alerting"
                and .name == $alert
              )
          ]
          | length
        ' <<<"$RULE_JSON"
    )"

    if [[ "$COUNT" -ne 1 ]]; then
        echo "ERROR: Missing alert rule: ${alert}"
        exit 1
    fi

    echo "${alert}: PASS"
done

echo
echo "===== VERIFY PROMETHEUS ALERTMANAGER CONNECTION ====="

AM_DISCOVERY="$(
  curl \
    --fail \
    --silent \
    --show-error \
    http://127.0.0.1:9090/api/v1/alertmanagers
)"

ACTIVE_AM="$(
  jq '.data.activeAlertmanagers | length' \
  <<<"$AM_DISCOVERY"
)"

echo "Active Alertmanagers: ${ACTIVE_AM}"

if [[ "$ACTIVE_AM" -lt 1 ]]; then
    echo "ERROR: Prometheus cannot reach Alertmanager"
    exit 1
fi

echo
echo "===== VERIFY WEBHOOK SERVICE ====="

WEBHOOK_STATE="$(
  sudo systemctl is-active prometheus-webhook
)"

echo "Webhook service: ${WEBHOOK_STATE}"

if [[ "$WEBHOOK_STATE" != "active" ]]; then
    echo "ERROR: Webhook receiver is not active"
    exit 1
fi

echo
echo "===== DIRECT WEBHOOK HEALTH TEST ====="

DIRECT_RESPONSE="$(
  curl \
    --fail \
    --silent \
    --show-error \
    --request POST \
    --header 'Content-Type: application/json' \
    --data '{
      "status":"firing",
      "alerts":[
        {
          "status":"firing",
          "labels":{
            "alertname":"FinalValidation",
            "severity":"info",
            "instance":"local-validation"
          },
          "annotations":{
            "summary":"Final webhook validation"
          }
        }
      ]
    }' \
    http://127.0.0.1:8080/alerts
)"

echo "$DIRECT_RESPONSE" | jq .

echo
echo "===== VERIFY ALERT LIFECYCLE RECORD ====="

if [[ ! -s alert_pipeline_validation.txt ]]; then
    echo "ERROR: alert_pipeline_validation.txt missing"
    exit 1
fi

cat alert_pipeline_validation.txt

if ! grep -q \
  '^End-to-end alert lifecycle: PASS$' \
  alert_pipeline_validation.txt; then

    echo "ERROR: Alert lifecycle validation did not pass"
    exit 1
fi

echo
echo "===== VERIFY FIRING DELIVERY EXISTS ====="

FIRING_COUNT="$(
  jq -s '
    [
      .[]
      | select(
          .payload.alerts[]?
          | (
              .labels.alertname == "HighCPUUsage"
              and .status == "firing"
            )
        )
    ]
    | length
  ' webhook_alerts.log
)"

echo "Recorded HighCPUUsage firing deliveries: ${FIRING_COUNT}"

if [[ "$FIRING_COUNT" -lt 1 ]]; then
    echo "ERROR: No firing notification recorded"
    exit 1
fi

echo
echo "===== VERIFY RESOLVED DELIVERY EXISTS ====="

RESOLVED_COUNT="$(
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
  ' webhook_alerts.log
)"

echo "Recorded HighCPUUsage resolved deliveries: ${RESOLVED_COUNT}"

if [[ "$RESOLVED_COUNT" -lt 1 ]]; then
    echo "ERROR: No resolved notification recorded"
    exit 1
fi

echo
echo "===== VERIFY EMAIL CONFIGURATION TOOLING ====="

bash -n configure_email_notifications.sh
bash -n generate_alertmanager_email_config.sh

echo "Email configuration scripts: PASS"

echo
echo "===== VERIFY SMTP SECRET PROTECTION ====="

if ! grep -q '^smtp-settings$' .gitignore; then
    echo "ERROR: smtp-settings is not excluded from Git"
    exit 1
fi

if ! grep -q '^smtp-settings\.\*$' .gitignore; then
    echo "ERROR: smtp-settings.* is not excluded from Git"
    exit 1
fi

if ! grep -q '^!smtp-settings.example$' .gitignore; then
    echo "ERROR: safe SMTP example is not explicitly retained"
    exit 1
fi

echo "SMTP secret exclusions: PASS"

echo
echo "===== VERIFY SCRIPT SYNTAX ====="

for script in \
  webhook_receiver.py \
  cpu_stress.sh \
  stop_cpu_stress.sh \
  verify_alert_resolution.sh \
  configure_email_notifications.sh \
  generate_alertmanager_email_config.sh; do

    if [[ ! -s "$script" ]]; then
        echo "ERROR: Missing artifact: ${script}"
        exit 1
    fi

    echo "${script}: PRESENT"
done

python3 -m py_compile webhook_receiver.py

bash -n cpu_stress.sh
bash -n stop_cpu_stress.sh
bash -n verify_alert_resolution.sh
bash -n configure_email_notifications.sh
bash -n generate_alertmanager_email_config.sh

echo "Script syntax validation: PASS"

echo
echo "===== VERIFY NO SMTP SECRET FILE EXISTS ====="

if [[ -f smtp-settings ]]; then
    echo "WARNING: smtp-settings exists locally."
    echo "Confirm that it contains no credentials before publishing."
else
    echo "No live SMTP credential file present: PASS"
fi

echo
echo "===== CREATE FINAL VALIDATION REPORT ====="

cat > validation-report.txt <<REPORT
Prometheus Alerting Validation

Validation time: $(date --iso-8601=seconds)

Services
Prometheus: PASS
Node Exporter: PASS
Alertmanager: PASS
Webhook Receiver: PASS

Telemetry
Prometheus scrape targets: ${TARGET_COUNT}
Healthy scrape targets: ${UP_COUNT}

Alert Rules
HighCPUUsage: PASS
HighMemoryUsage: PASS
DiskSpaceLow: PASS
ServiceDown: PASS
Total alert rules: ${RULE_COUNT}

Alert Routing
Prometheus to Alertmanager: PASS
Alertmanager to webhook: PASS

Lifecycle
HighCPUUsage firing transition: PASS
HighCPUUsage firing webhook delivery: PASS
HighCPUUsage resolved transition: PASS
HighCPUUsage resolved webhook delivery: PASS

Recorded firing deliveries: ${FIRING_COUNT}
Recorded resolved deliveries: ${RESOLVED_COUNT}

Email Notification Configuration
Secure configuration generator: PASS
SMTP secret exclusion: PASS
External SMTP delivery: NOT TESTED

Reason:
Real SMTP credentials were intentionally not embedded or supplied.

Overall locally verifiable alerting pipeline: PASS
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
