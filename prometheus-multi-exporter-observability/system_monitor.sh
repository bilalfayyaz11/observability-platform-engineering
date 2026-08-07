#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="http://127.0.0.1:9090"

query_value() {
    local expression="$1"

    curl \
      --get \
      --silent \
      --show-error \
      --data-urlencode "query=${expression}" \
      "${PROMETHEUS_URL}/api/v1/query" |
    jq -r '.data.result[0].value[1] // "N/A"'
}

echo "========================================"
echo "SYSTEM MONITORING REPORT"
echo "========================================"
echo "Timestamp: $(date --iso-8601=seconds)"
echo

CPU="$(
  query_value \
    '100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'
)"

MEMORY="$(
  query_value \
    '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'
)"

LOAD="$(
  query_value \
    'node_load1'
)"

AVAILABLE_GB="$(
  query_value \
    'node_memory_MemAvailable_bytes / 1073741824'
)"

echo "CPU usage:"

if [[ "$CPU" != "N/A" ]]; then
    printf '  %.2f%%\n' "$CPU"
else
    echo "  N/A"
fi

echo "Memory usage:"

if [[ "$MEMORY" != "N/A" ]]; then
    printf '  %.2f%%\n' "$MEMORY"
else
    echo "  N/A"
fi

echo "Available memory:"

if [[ "$AVAILABLE_GB" != "N/A" ]]; then
    printf '  %.2f GiB\n' "$AVAILABLE_GB"
else
    echo "  N/A"
fi

echo "1-minute load average:"

if [[ "$LOAD" != "N/A" ]]; then
    printf '  %.2f\n' "$LOAD"
else
    echo "  N/A"
fi

echo
echo "========================================"
