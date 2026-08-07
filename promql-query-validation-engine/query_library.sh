#!/usr/bin/env bash
set -euo pipefail

cd /home/ubuntu/promql-query-engineering

source ./pql.sh

run_category() {
    local category_name="$1"

    echo
    echo "============================================================"
    echo "${category_name}"
    echo "============================================================"
}

validate_query() {
    local expression="$1"

    local response
    local exit_code

    set +e

    response="$(
      pql_instant "$expression" 2>&1
    )"

    exit_code=$?

    set -e

    if [[ "$exit_code" -ne 0 ]]; then
        echo "$response" >&2
        return 1
    fi

    return 0
}

run_query() {
    local description="$1"
    local expression="$2"

    echo
    echo "Description: ${description}"
    echo "PromQL:      ${expression}"

    if ! validate_query "$expression"; then
        echo "FAIL: PromQL validation failed"
        return 1
    fi

    local response

    response="$(
      pql_instant "$expression"
    )"

    local result_count

    result_count="$(
      jq '.data.result | length' <<<"$response"
    )"

    echo "Result count: ${result_count}"

    if [[ "$result_count" -eq 0 ]]; then
        echo "Values: no active result"
    else
        echo "Values:"

        jq -r '
          .data.result[]
          |
          (
            if (.metric | length) == 0
            then "{}"
            else (.metric | tojson)
            end
          )
          + " => "
          + .value[1]
        ' <<<"$response"
    fi

    echo "PASS"
}

CPU_UTIL='100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'

CPU_BY_MODE='sum by (mode) (rate(node_cpu_seconds_total[5m])) * 100'

CPU_EXCL_IDLE_IOWAIT='sum by (cpu) (rate(node_cpu_seconds_total{mode!~"idle|iowait"}[5m]))'


MEM_USED_PCT='(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'

MEM_AVAILABLE_GB='node_memory_MemAvailable_bytes / 1073741824'

MEM_TREND='predict_linear(node_memory_MemAvailable_bytes[30m], 3600)'


DISK_USED_PCT='(1 - (node_filesystem_free_bytes{fstype!~"tmpfs|devtmpfs|overlay|squashfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|devtmpfs|overlay|squashfs"})) * 100'

DISK_READ_RATE='sum(rate(node_disk_read_bytes_total[5m]))'

DISK_WRITE_RATE='sum(rate(node_disk_written_bytes_total[5m]))'

DISK_IO_UTIL='avg(rate(node_disk_io_time_seconds_total[5m])) * 100'


NET_RX_RATE='sum(rate(node_network_receive_bytes_total{device!~"lo|docker.*|br-.*|veth.*"}[5m]))'

NET_TX_RATE='sum(rate(node_network_transmit_bytes_total{device!~"lo|docker.*|br-.*|veth.*"}[5m]))'

NET_ERR_RATE='sum(rate(node_network_receive_errs_total[5m])) + sum(rate(node_network_transmit_errs_total[5m]))'

NET_TOP3='topk(3, rate(node_network_receive_bytes_total[5m]))'


ALERT_CPU_HIGH='100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80'

ALERT_MEM_HIGH='(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90'

ALERT_DISK_HIGH='(1 - (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 85'

ALERT_TARGET_DOWN='up == 0'


run_category "CPU"

run_query \
  "Overall CPU utilization percentage" \
  "$CPU_UTIL"

run_query \
  "CPU rate grouped by mode" \
  "$CPU_BY_MODE"

run_query \
  "CPU activity excluding idle and iowait" \
  "$CPU_EXCL_IDLE_IOWAIT"


run_category "MEMORY"

run_query \
  "Memory utilization percentage" \
  "$MEM_USED_PCT"

run_query \
  "Available memory in GiB" \
  "$MEM_AVAILABLE_GB"

run_query \
  "Predicted available memory one hour ahead" \
  "$MEM_TREND"


run_category "DISK"

run_query \
  "Filesystem utilization percentage" \
  "$DISK_USED_PCT"

run_query \
  "Aggregate disk read bytes per second" \
  "$DISK_READ_RATE"

run_query \
  "Aggregate disk write bytes per second" \
  "$DISK_WRITE_RATE"

run_query \
  "Average disk I/O utilization percentage" \
  "$DISK_IO_UTIL"


run_category "NETWORK"

run_query \
  "Aggregate network receive bytes per second" \
  "$NET_RX_RATE"

run_query \
  "Aggregate network transmit bytes per second" \
  "$NET_TX_RATE"

run_query \
  "Aggregate network receive and transmit error rate" \
  "$NET_ERR_RATE"

run_query \
  "Top three interfaces by receive rate" \
  "$NET_TOP3"


run_category "ALERT THRESHOLDS"

run_query \
  "CPU utilization above 80 percent" \
  "$ALERT_CPU_HIGH"

run_query \
  "Memory utilization above 90 percent" \
  "$ALERT_MEM_HIGH"

run_query \
  "Root filesystem utilization above 85 percent" \
  "$ALERT_DISK_HIGH"

run_query \
  "Any Prometheus target down" \
  "$ALERT_TARGET_DOWN"
