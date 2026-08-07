#!/usr/bin/env bash

PORT=19090
LOG=/tmp/cluster-report-port-forward.log
PF_PID=""

cleanup() {
    if [ -n "$PF_PID" ]; then
        kill "$PF_PID" 2>/dev/null || true
        wait "$PF_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

query() {
    local label="$1"
    local expression="$2"

    response=$(
        curl -fsSG \
          --data-urlencode "query=$expression" \
          "http://127.0.0.1:${PORT}/api/v1/query"
    ) || fail "Prometheus query request failed: $label"

    status=$(echo "$response" | jq -r '.status // "error"')

    [ "$status" = "success" ] || \
        fail "Prometheus returned non-success status for: $label"

    result_count=$(echo "$response" | jq '.data.result | length')

    [ "$result_count" -gt 0 ] || \
        fail "Prometheus returned no result for: $label"

    case "$label" in

        "Total cluster nodes"|"Running pods"|"monitoring-demo pods")
            value=$(echo "$response" | jq -r '.data.result[0].value[1]')
            ;;

        "Highest pod CPU rate")
            value=$(
                echo "$response" | \
                jq -r '
                  .data.result[0] |
                  "\(.metric.namespace // "unknown")/\(.metric.pod // "unknown") = \(.value[1]) cores"
                '
            )
            ;;

        "Highest pod memory usage")
            value=$(
                echo "$response" | \
                jq -r '
                  .data.result[0] |
                  "\(.metric.namespace // "unknown")/\(.metric.pod // "unknown") = \((.value[1] | tonumber) / 1024 / 1024) MiB"
                '
            )
            ;;
    esac

    printf "%-28s : %s\n" "$label" "$value"
}

echo "Starting Prometheus port-forward..."

kubectl port-forward \
  -n monitoring \
  svc/prometheus-service \
  "${PORT}:9090" >"$LOG" 2>&1 &

PF_PID=$!

for i in $(seq 1 20); do

    if curl -fsS \
        "http://127.0.0.1:${PORT}/-/ready" \
        >/dev/null 2>&1
    then
        break
    fi

    if ! kill -0 "$PF_PID" 2>/dev/null; then
        cat "$LOG" >&2
        fail "kubectl port-forward terminated unexpectedly"
    fi

    sleep 1
done

curl -fsS \
  "http://127.0.0.1:${PORT}/-/ready" \
  >/dev/null 2>&1 || \
  fail "Prometheus port-forward did not become ready"

echo
echo "===== KUBERNETES OBSERVABILITY REPORT ====="

query \
  "Total cluster nodes" \
  'count(kube_node_info)'

query \
  "Running pods" \
  'count(kube_pod_status_phase{phase="Running"})'

query \
  "monitoring-demo pods" \
  'count(kube_pod_info{namespace="monitoring-demo"})'

query \
  "Highest pod CPU rate" \
  'topk(1, rate(container_cpu_usage_seconds_total{pod!=""}[5m]))'

query \
  "Highest pod memory usage" \
  'topk(1, container_memory_usage_bytes{pod!=""})'

echo
echo "Cluster observability report: SUCCESS"
exit 0
