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
echo "MYSQL MONITORING REPORT"
echo "========================================"
echo "Timestamp: $(date --iso-8601=seconds)"
echo

MYSQL_UP="$(
  query_value \
    'mysql_up'
)"

CONNECTIONS="$(
  query_value \
    'mysql_global_status_threads_connected'
)"

UPTIME="$(
  query_value \
    'mysql_global_status_uptime'
)"

QUERY_RATE="$(
  query_value \
    'rate(mysql_global_status_queries[5m])'
)"

echo "Exporter database status:"

if [[ "$MYSQL_UP" == "1" ]]; then
    echo "  MySQL: UP"
else
    echo "  MySQL: DOWN or unavailable"
fi

echo "Active connections:"
echo "  ${CONNECTIONS}"

echo "Uptime:"

if [[ "$UPTIME" != "N/A" ]]; then
    python3 - "$UPTIME" <<'PY'
import sys

seconds = int(float(sys.argv[1]))

hours, remainder = divmod(seconds, 3600)
minutes, seconds = divmod(remainder, 60)

print(f"  {hours}h {minutes}m {seconds}s")
PY
else
    echo "  N/A"
fi

echo "Query throughput:"

if [[ "$QUERY_RATE" != "N/A" ]]; then
    printf '  %.2f queries/sec\n' "$QUERY_RATE"
else
    echo "  N/A"
fi

echo
echo "========================================"
