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

probe_status() {
    local job="$1"
    local instance="$2"

    curl \
      --get \
      --silent \
      --show-error \
      --data-urlencode \
      "query=probe_success{job=\"${job}\",instance=\"${instance}\"}" \
      "${PROMETHEUS_URL}/api/v1/query" |
    jq -r '.data.result[0].value[1] // "missing"'
}

printf_value() {
    local value="$1"
    local suffix="$2"

    if [[ "$value" == "N/A" ]]; then
        echo "N/A"
    else
        printf "%.2f%s\n" "$value" "$suffix"
    fi
}

echo "============================================================"
echo "              OBSERVABILITY STATUS DASHBOARD"
echo "============================================================"
echo "Timestamp: $(date --iso-8601=seconds)"
echo

echo "----- SYSTEM METRICS -----"

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

DISK_WRITE="$(
  query_value \
    'sum(rate(node_disk_written_bytes_total[5m]))'
)"

echo -n "CPU usage:             "
printf_value "$CPU" "%"

echo -n "Memory usage:          "
printf_value "$MEMORY" "%"

echo -n "1-minute load:         "
printf_value "$LOAD" ""

echo -n "Disk write throughput: "
printf_value "$DISK_WRITE" " bytes/sec"

echo
echo "----- MYSQL METRICS -----"

MYSQL_UP="$(
  query_value \
    'mysql_up'
)"

MYSQL_CONNECTIONS="$(
  query_value \
    'mysql_global_status_threads_connected'
)"

MYSQL_UPTIME="$(
  query_value \
    'mysql_global_status_uptime'
)"

MYSQL_QUERY_RATE="$(
  query_value \
    'rate(mysql_global_status_queries[5m])'
)"

if [[ "$MYSQL_UP" == "1" ]]; then
    echo "MySQL status:           UP"
else
    echo "MySQL status:           DOWN/UNKNOWN"
fi

echo "Active connections:     ${MYSQL_CONNECTIONS}"

if [[ "$MYSQL_UPTIME" != "N/A" ]]; then
    python3 - "$MYSQL_UPTIME" <<'PY'
import sys

seconds = int(float(sys.argv[1]))
hours, rem = divmod(seconds, 3600)
minutes, seconds = divmod(rem, 60)

print(f"MySQL uptime:            {hours}h {minutes}m {seconds}s")
PY
else
    echo "MySQL uptime:            N/A"
fi

echo -n "MySQL query rate:       "
printf_value "$MYSQL_QUERY_RATE" " queries/sec"

echo
echo "----- SERVICE STATUS -----"

SERVICES=(
    prometheus
    node_exporter
    mysql
    mysql_exporter
    blackbox_exporter
)

for service in "${SERVICES[@]}"; do
    state="$(
      sudo systemctl is-active "$service" 2>/dev/null || true
    )"

    if [[ "$state" == "active" ]]; then
        printf "%-24s RUNNING\n" "$service"
    else
        printf "%-24s STOPPED\n" "$service"
    fi
done

echo
echo "----- PROMETHEUS TARGET HEALTH -----"

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
  "\(.labels.job) | \(.labels.instance) | \(.health)"
' <<<"$TARGET_JSON" |
sort

echo
echo "----- HTTP CONNECTIVITY -----"

HTTP_TARGETS=(
    "http://127.0.0.1:9090/-/ready"
    "https://github.com"
    "https://www.google.com"
)

for target in "${HTTP_TARGETS[@]}"; do

    status="$(
      probe_status \
        blackbox_http \
        "$target"
    )"

    case "$status" in
        1)
            printf "%-42s REACHABLE\n" "$target"
            ;;
        0)
            printf "%-42s UNREACHABLE\n" "$target"
            ;;
        *)
            printf "%-42s NO DATA\n" "$target"
            ;;
    esac
done

echo
echo "----- TCP CONNECTIVITY -----"

TCP_TARGETS=(
    "127.0.0.1:3306"
    "127.0.0.1:9090"
    "127.0.0.1:9104"
)

for target in "${TCP_TARGETS[@]}"; do

    status="$(
      probe_status \
        blackbox_tcp \
        "$target"
    )"

    case "$status" in
        1)
            printf "%-24s OPEN\n" "$target"
            ;;
        0)
            printf "%-24s CLOSED\n" "$target"
            ;;
        *)
            printf "%-24s NO DATA\n" "$target"
            ;;
    esac
done

echo
echo "============================================================"
echo "Prometheus API: http://127.0.0.1:9090"
echo "============================================================"
