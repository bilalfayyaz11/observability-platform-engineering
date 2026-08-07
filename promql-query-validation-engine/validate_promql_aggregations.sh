#!/usr/bin/env bash
set -euo pipefail

cd /home/ubuntu/promql-query-engineering
source ./pql.sh

run_check() {
    local description="$1"
    local expression="$2"
    local expected_min="${3:-1}"

    echo
    echo "===== ${description} ====="
    echo "PromQL: ${expression}"

    local response
    response="$(pql_instant "$expression")"

    local count
    count="$(jq '.data.result | length' <<<"$response")"

    echo "Result count: ${count}"

    if [[ "$count" -lt "$expected_min" ]]; then
        echo "ERROR: Expected at least ${expected_min} result(s)"
        exit 1
    fi

    jq '
      .data.result[]
      | {
          metric: .metric,
          value: .value[1]
        }
    ' <<<"$response"
}

echo "===== AGGREGATION VALIDATION ====="

run_check \
  "SUM ALL CPU COUNTERS" \
  'sum(node_cpu_seconds_total)'

run_check \
  "CPU RATE GROUPED BY MODE" \
  'sum by (mode) (rate(node_cpu_seconds_total[5m]))'

run_check \
  "CPU RATE GROUPED BY CORE" \
  'sum by (cpu) (rate(node_cpu_seconds_total[5m]))'

run_check \
  "NORMALIZED ONE-MINUTE LOAD" \
  'node_load1 / scalar(count(count by (cpu) (node_cpu_seconds_total)))'

run_check \
  "TOP THREE NETWORK INTERFACES" \
  'topk(3, rate(node_network_receive_bytes_total[5m]))'

run_check \
  "BOTTOM THREE FILESYSTEMS BY FREE PERCENT" \
  'bottomk(3, (node_filesystem_free_bytes / node_filesystem_size_bytes) * 100)'

run_check \
  "DISTINCT CPU CORE COUNT" \
  'count(count by (cpu) (node_cpu_seconds_total))'

echo
echo "===== VERIFY TOPK RETURNS EXACTLY THREE SERIES ====="

TOPK_JSON="$(
  pql_instant \
    'topk(3, rate(node_network_receive_bytes_total[5m]))'
)"

TOPK_COUNT="$(
  jq '.data.result | length' <<<"$TOPK_JSON"
)"

echo "topk result count: ${TOPK_COUNT}"

if [[ "$TOPK_COUNT" -ne 3 ]]; then
    echo "ERROR: Expected exactly three topk series"
    exit 1
fi

echo
echo "===== VERIFY DISTINCT CPU CORE COUNT ====="

CPU_COUNT_JSON="$(
  pql_instant \
    'count(count by (cpu) (node_cpu_seconds_total))'
)"

CPU_COUNT="$(
  jq -r '.data.result[0].value[1]' <<<"$CPU_COUNT_JSON"
)"

HOST_CPU_COUNT="$(nproc)"

echo "Prometheus CPU count: ${CPU_COUNT}"
echo "Linux nproc count:     ${HOST_CPU_COUNT}"

python3 - "$CPU_COUNT" "$HOST_CPU_COUNT" <<'PY'
import sys

prometheus_count = int(float(sys.argv[1]))
linux_count = int(sys.argv[2])

if prometheus_count != linux_count:
    raise SystemExit(
        f"ERROR: Prometheus sees {prometheus_count} CPUs "
        f"but Linux reports {linux_count}"
    )

print("CPU cardinality validation: PASS")
PY

echo
echo "===== VERIFY MODE GROUPING ====="

MODE_JSON="$(
  pql_instant \
    'sum by (mode) (rate(node_cpu_seconds_total[5m]))'
)"

jq -r \
  '.data.result[].metric.mode' \
  <<<"$MODE_JSON" |
sort

MODE_COUNT="$(
  jq '.data.result | length' <<<"$MODE_JSON"
)"

echo "CPU modes discovered: ${MODE_COUNT}"

if [[ "$MODE_COUNT" -lt 4 ]]; then
    echo "ERROR: Unexpectedly low CPU mode count"
    exit 1
fi

echo
echo "===== TEST FIVE-MINUTE RANGE QUERY ====="

END_EPOCH="$(date +%s)"
START_EPOCH="$((END_EPOCH - 300))"

RANGE_JSON="$(
  pql_range \
    '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)' \
    "$START_EPOCH" \
    "$END_EPOCH" \
    "15"
)"

RANGE_SERIES="$(
  jq '.data.result | length' <<<"$RANGE_JSON"
)"

RANGE_SAMPLES="$(
  jq '
    if (.data.result | length) > 0
    then (.data.result[0].values | length)
    else 0
    end
  ' <<<"$RANGE_JSON"
)"

echo "Range series:  ${RANGE_SERIES}"
echo "Range samples: ${RANGE_SAMPLES}"

if [[ "$RANGE_SERIES" -lt 1 || "$RANGE_SAMPLES" -lt 2 ]]; then
    echo "ERROR: Range query returned insufficient data"
    exit 1
fi

echo
echo "===== CREATE AGGREGATION VALIDATION RECORD ====="

cat > aggregation_validation.txt <<SUMMARY
PromQL aggregation validation

Sum all CPU counters: PASS
CPU grouped by mode: PASS
CPU grouped by core: PASS
Normalized load: PASS
Top three network interfaces: PASS
Bottom three filesystems: PASS
Distinct CPU core count: PASS
CPU cardinality matches Linux: PASS
Range-query execution: PASS

Observed CPU cores: ${CPU_COUNT}
Observed CPU modes: ${MODE_COUNT}
Range samples: ${RANGE_SAMPLES}
SUMMARY

cat aggregation_validation.txt

echo
echo "===== STEP 6 COMPLETE ====="
