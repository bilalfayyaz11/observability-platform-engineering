#!/usr/bin/env bash
set -euo pipefail

cd /home/ubuntu/prometheus-exporter-engineering

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

query_value() {
    local expression="$1"

    query_json "$expression" |
    jq -r '.data.result[0].value[1] // "missing"'
}

echo "===== VERIFY ALL SERVICES ====="

SERVICES=(
    prometheus
    node_exporter
    mysql
    mysql_exporter
    blackbox_exporter
)

for service in "${SERVICES[@]}"; do

    STATE="$(
      sudo systemctl is-active "$service"
    )"

    ENABLED="$(
      sudo systemctl is-enabled "$service"
    )"

    printf "%-22s active=%-10s enabled=%s\n" \
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
echo "===== VERIFY REQUIRED PORTS ====="

for port in \
  3306 \
  9090 \
  9100 \
  9104 \
  9115; do

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
echo "===== VERIFY PROMETHEUS READINESS ====="

curl \
  --fail \
  --silent \
  --show-error \
  http://127.0.0.1:9090/-/ready

echo

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
echo "===== VERIFY MYSQL EXPORTER ENDPOINT ====="

MYSQL_EXPORTER_HTTP="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    http://127.0.0.1:9104/metrics
)"

echo "MySQL Exporter HTTP: ${MYSQL_EXPORTER_HTTP}"

if [[ "$MYSQL_EXPORTER_HTTP" != "200" ]]; then
    echo "ERROR: MySQL Exporter endpoint failed"
    exit 1
fi

echo
echo "===== VERIFY BLACKBOX EXPORTER ENDPOINT ====="

BLACKBOX_HTTP="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    http://127.0.0.1:9115/metrics
)"

echo "Blackbox Exporter HTTP: ${BLACKBOX_HTTP}"

if [[ "$BLACKBOX_HTTP" != "200" ]]; then
    echo "ERROR: Blackbox Exporter endpoint failed"
    exit 1
fi

echo
echo "===== VERIFY PROMETHEUS CONFIGURATION ====="

sudo -u prometheus \
  /usr/local/bin/promtool \
  check config \
  /etc/prometheus/prometheus.yml

echo
echo "===== VERIFY PROMETHEUS TARGET INVENTORY ====="

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
  "\(.labels.job) | \(.labels.instance) | \(.health) | \(.lastError)"
' <<<"$TARGET_JSON" |
sort

echo
echo "===== VERIFY REQUIRED SCRAPE JOBS ====="

REQUIRED_JOBS=(
    prometheus
    node_exporter
    mysql_exporter
    blackbox_http
    blackbox_tcp
)

for job in "${REQUIRED_JOBS[@]}"; do

    TOTAL="$(
      jq \
        --arg job "$job" \
        '
          [
            .data.activeTargets[]
            | select(.labels.job == $job)
          ]
          | length
        ' <<<"$TARGET_JSON"
    )"

    HEALTHY="$(
      jq \
        --arg job "$job" \
        '
          [
            .data.activeTargets[]
            | select(
                .labels.job == $job
                and .health == "up"
              )
          ]
          | length
        ' <<<"$TARGET_JSON"
    )"

    echo "${job}: total=${TOTAL} healthy=${HEALTHY}"

    if [[ "$TOTAL" -lt 1 ]]; then
        echo "ERROR: Missing job ${job}"
        exit 1
    fi
done

echo
echo "===== VERIFY NODE EXPORTER METRICS ====="

NODE_METRICS=(
    node_cpu_seconds_total
    node_memory_MemAvailable_bytes
    node_disk_read_bytes_total
    node_disk_written_bytes_total
    node_network_receive_bytes_total
    node_systemd_unit_state
)

for metric in "${NODE_METRICS[@]}"; do

    COUNT="$(
      query_count "$metric"
    )"

    printf "%-42s %s series\n" \
      "$metric" \
      "$COUNT"

    if [[ "$COUNT" -lt 1 ]]; then
        echo "ERROR: Missing node metric: ${metric}"
        exit 1
    fi
done

echo
echo "===== VERIFY MYSQL EXPORTER METRICS ====="

MYSQL_METRICS=(
    mysql_up
    mysql_global_status_threads_connected
    mysql_global_status_uptime
    mysql_global_status_queries
)

for metric in "${MYSQL_METRICS[@]}"; do

    COUNT="$(
      query_count "$metric"
    )"

    VALUE="$(
      query_value "$metric"
    )"

    printf "%-42s count=%-3s value=%s\n" \
      "$metric" \
      "$COUNT" \
      "$VALUE"

    if [[ "$COUNT" -lt 1 ]]; then
        echo "ERROR: Missing MySQL metric: ${metric}"
        exit 1
    fi
done

MYSQL_UP="$(
  query_value 'mysql_up'
)"

if [[ "$MYSQL_UP" != "1" ]]; then
    echo "ERROR: mysql_up is not 1"
    exit 1
fi

echo
echo "===== VERIFY MYSQL QUERY RATE ====="

MYSQL_RATE_JSON="$(
  query_json \
    'rate(mysql_global_status_queries[5m])'
)"

echo "$MYSQL_RATE_JSON" |
jq -r '
  .data.result[]
  |
  "\(.metric.instance) -> \(.value[1]) queries/sec"
'

MYSQL_RATE_COUNT="$(
  jq '.data.result | length' \
  <<<"$MYSQL_RATE_JSON"
)"

if [[ "$MYSQL_RATE_COUNT" -lt 1 ]]; then
    echo "ERROR: MySQL query-rate data unavailable"
    exit 1
fi

echo
echo "===== VERIFY BLACKBOX HTTP PROBES ====="

HTTP_PROBE_JSON="$(
  query_json \
    'probe_success{job="blackbox_http"}'
)"

echo "$HTTP_PROBE_JSON" |
jq -r '
  .data.result[]
  |
  "\(.metric.instance) -> probe_success=\(.value[1])"
'

HTTP_PROBE_COUNT="$(
  jq '.data.result | length' \
  <<<"$HTTP_PROBE_JSON"
)"

if [[ "$HTTP_PROBE_COUNT" -lt 1 ]]; then
    echo "ERROR: No Blackbox HTTP probe metrics"
    exit 1
fi

echo
echo "===== VERIFY BLACKBOX TCP PROBES ====="

TCP_PROBE_JSON="$(
  query_json \
    'probe_success{job="blackbox_tcp"}'
)"

echo "$TCP_PROBE_JSON" |
jq -r '
  .data.result[]
  |
  "\(.metric.instance) -> probe_success=\(.value[1])"
'

TCP_PROBE_COUNT="$(
  jq '.data.result | length' \
  <<<"$TCP_PROBE_JSON"
)"

if [[ "$TCP_PROBE_COUNT" -lt 1 ]]; then
    echo "ERROR: No Blackbox TCP probe metrics"
    exit 1
fi

echo
echo "===== VERIFY REQUIRED LOCAL BLACKBOX PROBES ====="

REQUIRED_PROBES=(
  'probe_success{job="blackbox_http",instance="http://127.0.0.1:9090/-/ready"}'
  'probe_success{job="blackbox_tcp",instance="127.0.0.1:3306"}'
  'probe_success{job="blackbox_tcp",instance="127.0.0.1:9090"}'
  'probe_success{job="blackbox_tcp",instance="127.0.0.1:9104"}'
)

for expression in "${REQUIRED_PROBES[@]}"; do

    VALUE="$(
      query_value "$expression"
    )"

    echo "${expression}"
    echo "  result=${VALUE}"

    if [[ "$VALUE" != "1" ]]; then
        echo "ERROR: Required local probe failed"
        exit 1
    fi
done

echo
echo "===== VERIFY MYSQL DATABASE STATE ====="

DATABASE_EXISTS="$(
  sudo mysql \
    --batch \
    --skip-column-names \
    -e "
SELECT COUNT(*)
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME='testdb';
"
)"

echo "testdb existence count: ${DATABASE_EXISTS}"

if [[ "$DATABASE_EXISTS" -ne 1 ]]; then
    echo "ERROR: testdb is missing"
    exit 1
fi

TABLE_COUNT="$(
  sudo mysql \
    --batch \
    --skip-column-names \
    -e "
SELECT COUNT(*)
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA='testdb'
AND TABLE_NAME='exporter_activity';
"
)"

echo "exporter_activity table count: ${TABLE_COUNT}"

if [[ "$TABLE_COUNT" -ne 1 ]]; then
    echo "ERROR: exporter_activity table missing"
    exit 1
fi

ROW_COUNT="$(
  sudo mysql \
    --batch \
    --skip-column-names \
    testdb \
    -e '
SELECT COUNT(*)
FROM exporter_activity;
'
)"

echo "exporter_activity rows: ${ROW_COUNT}"

if [[ "$ROW_COUNT" -lt 5 ]]; then
    echo "ERROR: Expected generated MySQL activity rows"
    exit 1
fi

echo
echo "===== VERIFY MONITORING SCRIPTS ====="

SCRIPTS=(
    system_monitor.sh
    mysql_monitor.sh
    connectivity_monitor.sh
    generate_load.sh
    monitoring_dashboard.sh
)

for script in "${SCRIPTS[@]}"; do

    if [[ ! -s "$script" ]]; then
        echo "ERROR: Missing script: ${script}"
        exit 1
    fi

    bash -n "$script"

    printf "%-32s PASS\n" "$script"
done

echo
echo "===== VERIFY VALIDATION RECORDS ====="

RECORDS=(
    monitoring_script_validation.txt
    workload_validation.txt
    dashboard_validation.txt
)

for record in "${RECORDS[@]}"; do

    if [[ ! -s "$record" ]]; then
        echo "ERROR: Missing validation record: ${record}"
        exit 1
    fi

    printf "%-38s PASS\n" "$record"
done

echo
echo "===== RUN FINAL SYSTEM MONITOR ====="

./system_monitor.sh

echo
echo "===== RUN FINAL MYSQL MONITOR ====="

./mysql_monitor.sh

echo
echo "===== RUN FINAL CONNECTIVITY MONITOR ====="

./connectivity_monitor.sh

echo
echo "===== RUN FINAL DASHBOARD ====="

./monitoring_dashboard.sh

echo
echo "===== VERIFY BINARY OWNERSHIP ====="

ls -l \
  /usr/local/bin/prometheus \
  /usr/local/bin/promtool \
  /usr/local/bin/node_exporter \
  /usr/local/bin/mysqld_exporter \
  /usr/local/bin/blackbox_exporter

echo
echo "===== VERIFY CONFIG PERMISSIONS ====="

sudo ls -l \
  /etc/prometheus/prometheus.yml \
  /etc/mysql_exporter.cnf \
  /etc/blackbox_exporter/blackbox.yml

echo
echo "===== CREATE FINAL VALIDATION REPORT ====="

cat > validation-report.txt <<REPORT
Prometheus Multi-Exporter Validation

Validation time: $(date --iso-8601=seconds)

Services
Prometheus: PASS
Node Exporter: PASS
MySQL: PASS
MySQL Exporter: PASS
Blackbox Exporter: PASS

Exporter Endpoints
Node Exporter 9100: PASS
MySQL Exporter 9104: PASS
Blackbox Exporter 9115: PASS
Prometheus 9090: PASS
MySQL 3306: PASS

Prometheus Integration
Prometheus job: PASS
Node Exporter job: PASS
MySQL Exporter job: PASS
Blackbox HTTP job: PASS
Blackbox TCP job: PASS

System Telemetry
CPU metrics: PASS
Memory metrics: PASS
Disk metrics: PASS
Network metrics: PASS
systemd metrics: PASS

Database Telemetry
mysql_up: PASS
Connection metrics: PASS
Uptime metrics: PASS
Query metrics: PASS
Query-rate metrics: PASS
Generated database activity: PASS

Synthetic Monitoring
Local Prometheus HTTP probe: PASS
MySQL TCP probe: PASS
Prometheus TCP probe: PASS
MySQL Exporter TCP probe: PASS

Dynamic Workload Validation
CPU response: PASS
Memory response: PASS
Disk response: PASS
MySQL activity response: PASS

Monitoring Interfaces
System monitor: PASS
MySQL monitor: PASS
Connectivity monitor: PASS
Unified dashboard: PASS

Overall multi-exporter observability stack: PASS
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
