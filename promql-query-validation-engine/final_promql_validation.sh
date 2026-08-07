#!/usr/bin/env bash
set -euo pipefail

cd /home/ubuntu/promql-query-engineering

source ./pql.sh

echo "===== VERIFY SERVICES ====="

PROM_STATE="$(sudo systemctl is-active prometheus.service)"
NODE_STATE="$(sudo systemctl is-active node_exporter.service)"

echo "Prometheus:    ${PROM_STATE}"
echo "Node Exporter: ${NODE_STATE}"

if [[ "$PROM_STATE" != "active" ]]; then
    echo "ERROR: Prometheus is not active"
    exit 1
fi

if [[ "$NODE_STATE" != "active" ]]; then
    echo "ERROR: Node Exporter is not active"
    exit 1
fi

echo "===== VERIFY PROMETHEUS READINESS ====="

curl \
  --connect-timeout 5 \
  --max-time 10 \
  --fail \
  --silent \
  --show-error \
  http://127.0.0.1:9090/-/ready

echo

echo "===== VERIFY TARGET HEALTH ====="

TARGET_JSON="$(
  curl \
    --fail \
    --silent \
    --show-error \
    http://127.0.0.1:9090/api/v1/targets
)"

jq '
  .data.activeTargets[]
  | {
      job: .labels.job,
      instance: .labels.instance,
      health: .health,
      lastError: .lastError
    }
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

if [[ "$TARGET_COUNT" -ne 2 || "$UP_COUNT" -ne 2 ]]; then
    echo "ERROR: Expected two healthy scrape targets"
    exit 1
fi

echo "===== VERIFY EXECUTOR SYNTAX ====="

bash -n pql.sh

echo "pql.sh syntax: PASS"

echo "===== VERIFY QUERY LIBRARY SYNTAX ====="

bash -n query_library.sh

echo "query_library.sh syntax: PASS"

echo "===== VERIFY AGGREGATION VALIDATOR SYNTAX ====="

bash -n validate_promql_aggregations.sh

echo "validate_promql_aggregations.sh syntax: PASS"

echo "===== VERIFY INSTANT QUERY EXECUTOR ====="

INSTANT_JSON="$(
  pql_instant \
    'node_cpu_seconds_total{cpu="0",mode="idle"}'
)"

INSTANT_COUNT="$(
  jq '.data.result | length' <<<"$INSTANT_JSON"
)"

echo "Instant-query result count: ${INSTANT_COUNT}"

if [[ "$INSTANT_COUNT" -lt 1 ]]; then
    echo "ERROR: Instant executor returned no data"
    exit 1
fi

echo "===== VERIFY RANGE QUERY EXECUTOR ====="

END_EPOCH="$(date +%s)"
START_EPOCH="$((END_EPOCH - 300))"

RANGE_JSON="$(
  pql_range \
    'node_cpu_seconds_total{cpu="0",mode="idle"}' \
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

echo "Range-query series:  ${RANGE_SERIES}"
echo "Range-query samples: ${RANGE_SAMPLES}"

if [[ "$RANGE_SERIES" -lt 1 || "$RANGE_SAMPLES" -lt 2 ]]; then
    echo "ERROR: Range executor returned insufficient data"
    exit 1
fi

echo "===== VERIFY INVALID QUERY REJECTION ====="

set +e

INVALID_OUTPUT="$(
  pql_instant \
    'rate(node_cpu_seconds_total)' \
    2>&1
)"

INVALID_EXIT=$?

set -e

echo "Invalid query exit code: ${INVALID_EXIT}"
echo "$INVALID_OUTPUT"

if [[ "$INVALID_EXIT" -eq 0 ]]; then
    echo "ERROR: Invalid PromQL expression was accepted"
    exit 1
fi

echo "Invalid PromQL rejection: PASS"

echo "===== EXECUTE COMPLETE QUERY LIBRARY ====="

bash query_library.sh \
  2>&1 |
tee query_library_output.txt

QUERY_COUNT="$(
  grep -c '^run_query \\' query_library.sh
)"

PASS_COUNT="$(
  grep -c '^PASS$' query_library_output.txt
)"

echo "Queries defined: ${QUERY_COUNT}"
echo "Queries passed:  ${PASS_COUNT}"

if [[ "$QUERY_COUNT" -ne 18 ]]; then
    echo "ERROR: Expected 18 implemented queries"
    exit 1
fi

if [[ "$PASS_COUNT" -ne 18 ]]; then
    echo "ERROR: Expected 18 successful query validations"
    exit 1
fi

if grep -E '(^FAIL|ERROR:)' query_library_output.txt >/dev/null; then
    echo "ERROR: Query library contains failure markers"
    exit 1
fi

echo "Query library validation: PASS"

echo "===== VERIFY CORE RESOURCE DIMENSIONS ====="

for expression in \
  '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)' \
  '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100' \
  'sum(rate(node_disk_read_bytes_total[5m]))' \
  'sum(rate(node_network_receive_bytes_total{device!~"lo|docker.*|br-.*|veth.*"}[5m]))'; do

    RESULT="$(
      pql_instant "$expression"
    )"

    COUNT="$(
      jq '.data.result | length' <<<"$RESULT"
    )"

    echo "${expression}"
    echo "  result count: ${COUNT}"

    if [[ "$COUNT" -lt 1 ]]; then
        echo "ERROR: Core resource query returned no data"
        exit 1
    fi
done

echo "===== VERIFY CORRECTED NORMALIZED LOAD QUERY ====="

LOAD_JSON="$(
  pql_instant \
    'node_load1 / scalar(count(count by (cpu) (node_cpu_seconds_total)))'
)"

LOAD_COUNT="$(
  jq '.data.result | length' <<<"$LOAD_JSON"
)"

jq '
  .data.result[]
  | {
      metric: .metric,
      normalized_load: .value[1]
    }
' <<<"$LOAD_JSON"

if [[ "$LOAD_COUNT" -lt 1 ]]; then
    echo "ERROR: Normalized load query returned no data"
    exit 1
fi

echo "Normalized load validation: PASS"

echo "===== VERIFY CPU CARDINALITY ====="

PROM_CPU_COUNT="$(
  pql_instant \
    'count(count by (cpu) (node_cpu_seconds_total))' |
  jq -r '.data.result[0].value[1]'
)"

HOST_CPU_COUNT="$(nproc)"

echo "Prometheus CPU count: ${PROM_CPU_COUNT}"
echo "Linux CPU count:      ${HOST_CPU_COUNT}"

python3 - "$PROM_CPU_COUNT" "$HOST_CPU_COUNT" <<'PY'
import sys

prom = int(float(sys.argv[1]))
host = int(sys.argv[2])

if prom != host:
    raise SystemExit(
        f"ERROR: Prometheus sees {prom} CPUs while Linux reports {host}"
    )

print("CPU cardinality validation: PASS")
PY

echo "===== VERIFY EXPECTED ARTIFACTS ====="

for file in \
  pql.sh \
  validate_promql_queries.sh \
  selector_function_validation.txt \
  query_library.sh \
  query_library_output.txt \
  validate_promql_aggregations.sh \
  aggregation_validation.txt; do

    if [[ ! -s "$file" ]]; then
        echo "ERROR: Missing or empty artifact: ${file}"
        exit 1
    fi

    printf "%-42s PASS\n" "$file"
done

echo "===== CREATE GITIGNORE ====="

cat > .gitignore <<'EOF'
*.tmp
*.log
