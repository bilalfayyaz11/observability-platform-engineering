#!/usr/bin/env bash
set -euo pipefail

cd /home/ubuntu/promql-query-engineering

source ./pql.sh

run_nonempty_query() {
    local description="$1"
    local query="$2"

    echo
    echo "===== ${description} ====="
    echo "PromQL: ${query}"

    local response
    response="$(pql_instant "$query")"

    local count
    count="$(
      jq '.data.result | length' <<<"$response"
    )"

    echo "Result count: ${count}"

    if [[ "$count" -lt 1 ]]; then
        echo "ERROR: Query returned no results"
        return 1
    fi

    jq '
      .data.result[0:5]
      | map({
          metric: .metric,
          value: .value[1]
        })
    ' <<<"$response"
}

echo "===== SELECTOR-LEVEL QUERIES ====="

run_nonempty_query \
  "ALL CPU COUNTER SERIES" \
  'node_cpu_seconds_total'

run_nonempty_query \
  "CORE 0 IDLE CPU" \
  'node_cpu_seconds_total{cpu="0",mode="idle"}'

run_nonempty_query \
  "ALL CPU MODES EXCEPT IDLE" \
  'node_cpu_seconds_total{mode!="idle"}'

run_nonempty_query \
  "USER AND SYSTEM CPU MODES" \
  'node_cpu_seconds_total{mode=~"user|system"}'

run_nonempty_query \
  "PHYSICAL FILESYSTEMS" \
  'node_filesystem_size_bytes{fstype!~"tmpfs|devtmpfs|overlay|squashfs"}'

run_nonempty_query \
  "NON-VIRTUAL NETWORK INTERFACES" \
  'node_network_receive_bytes_total{device!~"lo|docker.*|br-.*|veth.*"}'

echo
echo "===== RATE AND TRANSFORMATION QUERIES ====="

run_nonempty_query \
  "CPU RATE PER CORE AND MODE" \
  'rate(node_cpu_seconds_total[5m])'

run_nonempty_query \
  "NETWORK RECEIVE RATE" \
  'rate(node_network_receive_bytes_total{device!~"lo|docker.*|br-.*|veth.*"}[5m])'

run_nonempty_query \
  "NETWORK RECEIVE INCREASE OVER FIVE MINUTES" \
  'increase(node_network_receive_bytes_total{device!~"lo|docker.*|br-.*|veth.*"}[5m])'

run_nonempty_query \
  "MEMORY UTILIZATION PERCENT" \
  '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'

run_nonempty_query \
  "ROOT FILESYSTEM UTILIZATION PERCENT" \
  '(1 - (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100'

run_nonempty_query \
  "CPU UTILIZATION PERCENT" \
  '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'

echo
echo "===== CPU UTILIZATION RANGE CHECK ====="

CPU_JSON="$(
  pql_instant \
    '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'
)"

CPU_VALUE="$(
  jq -r '.data.result[0].value[1]' <<<"$CPU_JSON"
)"

echo "CPU utilization: ${CPU_VALUE}%"

python3 - "$CPU_VALUE" <<'PY'
import sys

value = float(sys.argv[1])

if not 0 <= value <= 100:
    raise SystemExit(
        f"ERROR: CPU utilization outside valid range: {value}"
    )

print("CPU utilization validation: PASS")
PY

echo
echo "===== PREDICT_LINEAR CHECK ====="

PREDICT_JSON="$(
  pql_instant \
    'predict_linear(node_memory_MemAvailable_bytes[30m], 3600)'
)"

PREDICT_COUNT="$(
  jq '.data.result | length' <<<"$PREDICT_JSON"
)"

echo "Prediction result count: ${PREDICT_COUNT}"

if [[ "$PREDICT_COUNT" -lt 1 ]]; then
    echo "ERROR: predict_linear returned no result"
    echo
    echo "Current Prometheus data age may be below the required 30-minute range."
    exit 2
fi

jq '
  .data.result[]
  | {
      metric: .metric,
      predicted_available_bytes: .value[1]
    }
' <<<"$PREDICT_JSON"

echo
echo "===== SAVE VALIDATION SUMMARY ====="

cat > selector_function_validation.txt <<SUMMARY
PromQL selector and function validation

Raw CPU selector: PASS
CPU equality matcher: PASS
CPU inequality matcher: PASS
CPU regex matcher: PASS
Filesystem regex exclusion: PASS
Network regex exclusion: PASS
CPU rate: PASS
Network rate: PASS
Network increase: PASS
Memory percentage: PASS
Filesystem percentage: PASS
CPU utilization: PASS
CPU range validation: PASS
predict_linear: PASS
SUMMARY

cat selector_function_validation.txt

echo
echo "===== STEP 4 COMPLETE ====="
