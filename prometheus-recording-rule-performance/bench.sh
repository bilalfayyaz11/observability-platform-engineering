#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="http://127.0.0.1:9090"
ITERATIONS=5

declare -A MEANS

bench_query() {
    local description="$1"
    local query="$2"
    local iterations="$3"

    local total_ms="0"
    local elapsed_seconds
    local elapsed_ms
    local response_file

    response_file="$(mktemp)"

    for i in $(seq 1 "$iterations"); do

        elapsed_seconds="$(
          curl \
            --get \
            --fail \
            --silent \
            --show-error \
            --output "$response_file" \
            --write-out '%{time_total}' \
            --data-urlencode "query=${query}" \
            "${PROMETHEUS_URL}/api/v1/query"
        )"

        STATUS="$(
          jq -r '.status' "$response_file"
        )"

        RESULT_COUNT="$(
          jq '.data.result | length' "$response_file"
        )"

        if [[ "$STATUS" != "success" ]]; then
            echo "ERROR: Query failed: ${description}" >&2
            rm -f "$response_file"
            exit 1
        fi

        if [[ "$RESULT_COUNT" -lt 1 ]]; then
            echo "ERROR: Query returned no data: ${description}" >&2
            rm -f "$response_file"
            exit 1
        fi

        elapsed_ms="$(
          python3 - "$elapsed_seconds" <<'PY'
import sys

seconds = float(sys.argv[1])
print(f"{seconds * 1000:.6f}")
PY
        )"

        total_ms="$(
          python3 - "$total_ms" "$elapsed_ms" <<'PY'
import sys

total = float(sys.argv[1])
current = float(sys.argv[2])

print(f"{total + current:.6f}")
PY
        )"
    done

    rm -f "$response_file"

    local mean_ms

    mean_ms="$(
      python3 - "$total_ms" "$iterations" <<'PY'
import sys

total = float(sys.argv[1])
iterations = int(sys.argv[2])

print(f"{total / iterations:.6f}")
PY
    )"

    MEANS["$description"]="$mean_ms"

    printf "%-38s %10.4f ms\n" \
      "$description" \
      "$mean_ms"
}

compare_pair() {
    local pair="$1"
    local raw_key="$2"
    local rule_key="$3"

    local raw="${MEANS[$raw_key]}"
    local rule="${MEANS[$rule_key]}"

    python3 - "$pair" "$raw" "$rule" <<'PY'
import sys

pair = sys.argv[1]
raw = float(sys.argv[2])
rule = float(sys.argv[3])

if raw <= 0 or rule <= 0:
    print(f"{pair}: comparison unavailable")
    raise SystemExit(0)

if rule < raw:
    improvement = ((raw - rule) / raw) * 100
    print(
        f"{pair}: recording rule faster by "
        f"{improvement:.2f}% "
        f"({raw:.4f} ms -> {rule:.4f} ms)"
    )
elif raw < rule:
    difference = ((rule - raw) / raw) * 100
    print(
        f"{pair}: raw query faster by "
        f"{difference:.2f}% "
        f"({raw:.4f} ms -> {rule:.4f} ms)"
    )
else:
    print(
        f"{pair}: equal mean latency "
        f"({raw:.4f} ms)"
    )
PY
}

RAW_CPU='100 - (avg by (instance) (rate(node_cpu_seconds_total{job="node",mode="idle"}[5m])) * 100)'

RULE_CPU='node:cpu_utilization:rate5m'

RAW_MEMORY='(1 - (sum by (instance) (node_memory_MemAvailable_bytes{job="node"}) / sum by (instance) (node_memory_MemTotal_bytes{job="node"}))) * 100'

RULE_MEMORY='node:memory_utilization:ratio * 100'

RAW_PRESSURE='((100 - (avg by (instance) (rate(node_cpu_seconds_total{job="node",mode="idle"}[5m])) * 100)) * 0.40) + (((1 - (sum by (instance) (node_memory_MemAvailable_bytes{job="node"}) / sum by (instance) (node_memory_MemTotal_bytes{job="node"}))) * 100) * 0.35) + ((1 - (sum by (instance) (node_filesystem_avail_bytes{job="node",mountpoint="/"}) / sum by (instance) (node_filesystem_size_bytes{job="node",mountpoint="/"}))) * 100 * 0.25)'

RULE_PRESSURE='node:system_pressure:score'

echo "=============================================================="
echo "PROMETHEUS QUERY LATENCY BENCHMARK"
echo "Iterations per query: ${ITERATIONS}"
echo "=============================================================="
echo

bench_query \
  "CPU raw PromQL" \
  "$RAW_CPU" \
  "$ITERATIONS"

bench_query \
  "CPU recording rule" \
  "$RULE_CPU" \
  "$ITERATIONS"

bench_query \
  "Memory raw PromQL" \
  "$RAW_MEMORY" \
  "$ITERATIONS"

bench_query \
  "Memory recording rule" \
  "$RULE_MEMORY" \
  "$ITERATIONS"

bench_query \
  "System pressure raw PromQL" \
  "$RAW_PRESSURE" \
  "$ITERATIONS"

bench_query \
  "System pressure recording rule" \
  "$RULE_PRESSURE" \
  "$ITERATIONS"

echo
echo "=============================================================="
echo "PAIR COMPARISONS"
echo "=============================================================="

compare_pair \
  "CPU utilization" \
  "CPU raw PromQL" \
  "CPU recording rule"

compare_pair \
  "Memory utilization" \
  "Memory raw PromQL" \
  "Memory recording rule"

compare_pair \
  "System pressure" \
  "System pressure raw PromQL" \
  "System pressure recording rule"

echo
echo "Benchmark complete."
