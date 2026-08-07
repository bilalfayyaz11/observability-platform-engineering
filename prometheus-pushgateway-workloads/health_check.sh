#!/usr/bin/env bash
set -euo pipefail

PUSHGATEWAY_URL="http://127.0.0.1:9091"
PROMETHEUS_URL="http://127.0.0.1:9090"

echo "============================================"
echo "PUSHGATEWAY + PROMETHEUS HEALTH CHECK"
echo "============================================"

if curl \
  --fail \
  --silent \
  --show-error \
  "${PUSHGATEWAY_URL}/-/healthy" \
  >/dev/null; then

    echo "1. Pushgateway: OK"
else
    echo "1. Pushgateway: FAILED"
    exit 1
fi

if curl \
  --fail \
  --silent \
  --show-error \
  "${PROMETHEUS_URL}/-/healthy" \
  >/dev/null; then

    echo "2. Prometheus: OK"
else
    echo "2. Prometheus: FAILED"
    exit 1
fi

SCRAPE_RESULT="$(
  curl \
    --get \
    --fail \
    --silent \
    --show-error \
    --data-urlencode \
    'query=up{job="pushgateway"}' \
    "${PROMETHEUS_URL}/api/v1/query" |
  jq -r '.data.result[0].value[1] // "0"'
)"

if [[ "$SCRAPE_RESULT" == "1" ]]; then
    echo "3. Prometheus is scraping Pushgateway: OK"
else
    echo "3. Prometheus is scraping Pushgateway: FAILED"
    exit 1
fi

RULES_RESULT="$(
  curl \
    --fail \
    --silent \
    --show-error \
    "${PROMETHEUS_URL}/api/v1/rules" |
  jq '
    [
      .data.groups[]
      | select(.name == "batch_jobs")
    ]
    | length
  '
)"

echo "4. Loaded batch_jobs rule groups: ${RULES_RESULT}"

if [[ "$RULES_RESULT" -ne 1 ]]; then
    echo "ERROR: batch_jobs rule group missing"
    exit 1
fi

RULE_COUNT="$(
  curl \
    --fail \
    --silent \
    --show-error \
    "${PROMETHEUS_URL}/api/v1/rules" |
  jq '
    [
      .data.groups[]
      | select(.name == "batch_jobs")
      | .rules[]
    ]
    | length
  '
)"

echo "5. Loaded batch alert rules: ${RULE_COUNT}"

if [[ "$RULE_COUNT" -ne 4 ]]; then
    echo "ERROR: Expected 4 batch alert rules"
    exit 1
fi

ALERTS_RESULT="$(
  curl \
    --fail \
    --silent \
    --show-error \
    "${PROMETHEUS_URL}/api/v1/alerts" |
  jq '
    [
      .data.alerts[]
      | select(.state == "firing")
    ]
    | length
  '
)"

echo "6. Firing alerts: ${ALERTS_RESULT}"

echo "Health check completed successfully."
