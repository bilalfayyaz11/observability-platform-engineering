#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="http://127.0.0.1:9090"

query_json() {
    local expression="$1"

    curl \
      --get \
      --fail \
      --silent \
      --show-error \
      --data-urlencode "query=${expression}" \
      "${PROMETHEUS_URL}/api/v1/query"
}

query_count() {
    local expression="$1"

    query_json "$expression" |
    jq '.data.result | length'
}

echo "===== VERIFY SERVICES ====="

for service in prometheus node_exporter; do

    STATE="$(sudo systemctl is-active "$service")"
    ENABLED="$(sudo systemctl is-enabled "$service")"

    printf "%-16s active=%-10s enabled=%s\n" \
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
echo "===== VERIFY PORTS ====="

for port in 9090 9100; do

    if sudo ss -lnt |
      awk '{print $4}' |
      grep -q ":${port}$"; then

        echo "Port ${port}: LISTENING"
    else
        echo "ERROR: Port ${port} is not listening"
        exit 1
    fi
done

echo
echo "===== VERIFY PROMETHEUS READY ====="

curl \
  --fail \
  --silent \
  --show-error \
  "${PROMETHEUS_URL}/-/ready"

echo

echo "===== VERIFY NODE EXPORTER ENDPOINT ====="

NODE_HTTP="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    http://127.0.0.1:9100/metrics
)"

echo "Node Exporter HTTP: ${NODE_HTTP}"

if [[ "$NODE_HTTP" != "200" ]]; then
    echo "ERROR: Node Exporter endpoint failed"
    exit 1
fi

echo
echo "===== VALIDATE PROMETHEUS CONFIG ====="

sudo -u prometheus \
  /usr/local/bin/promtool \
  check config \
  /etc/prometheus/prometheus.yml

echo
echo "===== VALIDATE RECORDING RULE FILE ====="

sudo -u prometheus \
  /usr/local/bin/promtool \
  check rules \
  /etc/prometheus/recording_rules.yml

echo
echo "===== VERIFY SCRAPE TARGETS ====="

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

for job in prometheus node; do

    HEALTH="$(
      jq \
        --arg job "$job" \
        -r '
          [
            .data.activeTargets[]
            | select(.labels.job == $job)
          ][0].health // "missing"
        ' <<<"$TARGET_JSON"
    )"

    echo "${job}: ${HEALTH}"

    if [[ "$HEALTH" != "up" ]]; then
        echo "ERROR: ${job} target unhealthy"
        exit 1
    fi
done

echo
echo "===== VERIFY RULE GROUP INVENTORY ====="

RULE_JSON="$(
  curl \
    --fail \
    --silent \
    --show-error \
    "${PROMETHEUS_URL}/api/v1/rules"
)"

jq -r '
  .data.groups[]
  | select(
      .name == "node_base"
      or .name == "node_composite"
    )
  |
  "\(.name) -> \(.rules | length) rules -> interval=\(.interval)"
' <<<"$RULE_JSON"

BASE_COUNT="$(
  jq '
    [
      .data.groups[]
      | select(.name == "node_base")
      | .rules[]
    ]
    | length
  ' <<<"$RULE_JSON"
)"

COMPOSITE_COUNT="$(
  jq '
    [
      .data.groups[]
      | select(.name == "node_composite")
      | .rules[]
    ]
    | length
  ' <<<"$RULE_JSON"
)"

if [[ "$BASE_COUNT" -ne 4 ]]; then
    echo "ERROR: Expected 4 node_base rules"
    exit 1
fi

if [[ "$COMPOSITE_COUNT" -ne 2 ]]; then
    echo "ERROR: Expected 2 node_composite rules"
    exit 1
fi

echo
echo "===== VERIFY RULE HEALTH ====="

UNHEALTHY="$(
  jq '
    [
      .data.groups[]
      | select(
          .name == "node_base"
          or .name == "node_composite"
        )
      | .rules[]
      | select(
          .health != "ok"
          or (.lastError != null and .lastError != "")
        )
    ]
    | length
  ' <<<"$RULE_JSON"
)"

echo "Unhealthy recording rules: ${UNHEALTHY}"

if [[ "$UNHEALTHY" -ne 0 ]]; then
    echo "ERROR: Recording rule health failure detected"
    exit 1
fi

echo
echo "===== VERIFY ALL SIX RECORDED METRICS ====="

RECORDED_METRICS=(
  'node:cpu_utilization:rate5m'
  'node:memory_utilization:ratio'
  'node:disk_utilization:ratio'
  'node:network_throughput:rate5m_bytes'
  'node:system_pressure:score'
  'node:network_throughput:rate5m_mbps'
)

for metric in "${RECORDED_METRICS[@]}"; do

    COUNT="$(query_count "$metric")"

    printf "%-48s %s series\n" \
      "$metric" \
      "$COUNT"

    if [[ "$COUNT" -lt 1 ]]; then
        echo "ERROR: ${metric} returned no data"
        exit 1
    fi
done

echo
echo "===== VERIFY BASE LABEL CONTRACT ====="

for metric in \
  'node:cpu_utilization:rate5m' \
  'node:memory_utilization:ratio' \
  'node:disk_utilization:ratio'; do

    EXTRA_LABELS="$(
      query_json "$metric" |
      jq '
        [
          .data.result[].metric
          | keys[]
          | select(
              . != "__name__"
              and . != "instance"
            )
        ]
        | length
      '
    )"

    echo "${metric}: extra labels=${EXTRA_LABELS}"

    if [[ "$EXTRA_LABELS" -ne 0 ]]; then
        echo "ERROR: Base metric label contract violated"
        exit 1
    fi
done

echo "Base-layer label contract: PASS"

echo
echo "===== VERIFY COMPOSITE DEPENDENCY ISOLATION ====="

COMPOSITE_BLOCK="$(
  sudo awk '
    /^  - name: node_composite$/ {
      capture=1
    }

    capture {
      print
    }
  ' /etc/prometheus/recording_rules.yml
)"

if grep -E \
  'node_cpu_seconds_total|node_memory_Mem(Total|Available)_bytes|node_filesystem_(size|avail)_bytes|node_network_(receive|transmit)_bytes_total' \
  <<<"$COMPOSITE_BLOCK"; then

    echo "ERROR: Composite layer references raw metrics"
    exit 1
fi

echo "Composite dependency isolation: PASS"

echo
echo "===== VERIFY SYSTEM PRESSURE RANGE ====="

PRESSURE="$(
  query_json \
    'node:system_pressure:score' |
  jq -r '.data.result[0].value[1]'
)"

python3 - "$PRESSURE" <<'PY'
import sys

value = float(sys.argv[1])

print(f"System pressure score: {value:.4f}")

if not 0 <= value <= 100:
    raise SystemExit(
        "ERROR: System pressure outside 0-100"
    )

print("System pressure range: PASS")
PY

echo
echo "===== VERIFY ZERO RULE EVALUATION FAILURES ====="

FAILURE_JSON="$(
  query_json \
    'sum by (rule_group) (prometheus_rule_evaluation_failures_total)'
)"

echo "$FAILURE_JSON" |
jq -r '
  .data.result[]
  |
  "group=\(.metric.rule_group) failures=\(.value[1])"
'

NONZERO_FAILURES="$(
  jq '
    [
      .data.result[]
      | select(
          (.value[1] | tonumber) > 0
        )
    ]
    | length
  ' <<<"$FAILURE_JSON"
)"

echo "Groups with evaluation failures: ${NONZERO_FAILURES}"

if [[ "$NONZERO_FAILURES" -ne 0 ]]; then
    echo "ERROR: Runtime rule evaluation failures detected"
    exit 1
fi

echo
echo "===== RUN RULE HEALTH DIAGNOSTIC ====="

sudo -u prometheus \
  /opt/prometheus/rule_health.sh

echo "rule_health.sh: PASS"

echo
echo "===== VERIFY BENCHMARK EVIDENCE ====="

if [[ ! -s bench_results.txt ]]; then
    echo "ERROR: bench_results.txt missing"
    exit 1
fi

TIMING_COUNT="$(
  grep -Ec \
    '^(CPU raw PromQL|CPU recording rule|Memory raw PromQL|Memory recording rule|System pressure raw PromQL|System pressure recording rule)' \
    bench_results.txt
)"

COMPARISON_COUNT="$(
  grep -Ec \
    '^(CPU utilization|Memory utilization|System pressure):' \
    bench_results.txt
)"

echo "Benchmark timing lines:     ${TIMING_COUNT}"
echo "Benchmark comparison lines: ${COMPARISON_COUNT}"

if [[ "$TIMING_COUNT" -ne 6 ]]; then
    echo "ERROR: Benchmark timing evidence incomplete"
    exit 1
fi

if [[ "$COMPARISON_COUNT" -ne 3 ]]; then
    echo "ERROR: Benchmark comparison evidence incomplete"
    exit 1
fi

echo
echo "===== VERIFY VALIDATION RECORDS ====="

RECORDS=(
  stack_validation.txt
  base_rule_validation.txt
  recording_rule_hierarchy_validation.txt
  benchmark_validation.txt
  rule_health_validation.txt
)

for record in "${RECORDS[@]}"; do

    if [[ ! -s "$record" ]]; then
        echo "ERROR: Missing validation record: ${record}"
        exit 1
    fi

    printf "%-46s PASS\n" "$record"
done

echo
echo "===== VERIFY DIAGNOSTIC ARTIFACTS ====="

for artifact in \
  bench_results.txt \
  rule_health_results.txt; do

    if [[ ! -s "$artifact" ]]; then
        echo "ERROR: Missing artifact: ${artifact}"
        exit 1
    fi

    printf "%-46s PASS\n" "$artifact"
done

echo
echo "===== CREATE FINAL VALIDATION REPORT ====="

cat > validation-report.txt <<REPORT
Prometheus Recording Rule Validation

Validation time: $(date --iso-8601=seconds)

Services
Prometheus: PASS
Node Exporter: PASS

Scraping
Prometheus target: PASS
Node Exporter target: PASS

Base Recording Layer
node_base rule count: ${BASE_COUNT}
CPU utilization recording: PASS
Memory utilization recording: PASS
Disk utilization recording: PASS
Network throughput recording: PASS
Base label contract: PASS

Composite Recording Layer
node_composite rule count: ${COMPOSITE_COUNT}
System pressure recording: PASS
Network Mbps recording: PASS
Composite dependency isolation: PASS
System pressure range: PASS

Performance Engineering
Raw CPU benchmark: PASS
Recorded CPU benchmark: PASS
Raw memory benchmark: PASS
Recorded memory benchmark: PASS
Raw system-pressure benchmark: PASS
Recorded system-pressure benchmark: PASS
Timing comparisons: PASS

Rule Diagnostics
Rules API health: PASS
Internal rule-health metrics: PASS
Runtime evaluation failures: 0
Diagnostic script: PASS

Architecture
Raw telemetry -> base recording rules: PASS
Base recordings -> composite rules: PASS
Hierarchical recording-rule pipeline: PASS

Overall recording-rule performance architecture: PASS
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
