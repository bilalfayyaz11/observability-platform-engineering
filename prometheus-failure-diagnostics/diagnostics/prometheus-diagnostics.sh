#!/usr/bin/env bash

TIMESTAMP="$(
  date +%Y%m%d-%H%M%S
)"

LOG_FILE="$HOME/prometheus-troubleshooting/evidence/prometheus-diagnostics-${TIMESTAMP}.log"

FAILURES=0


section() {
    echo
    echo "===== $1 =====" |
      tee -a "$LOG_FILE"
}


run_check() {

    local title="$1"
    shift

    section "$title"

    "$@" 2>&1 |
      tee -a "$LOG_FILE"

    return "${PIPESTATUS[0]}"
}


pass() {
    echo "PASS: $1" |
      tee -a "$LOG_FILE"
}


fail() {
    echo "FAIL: $1" |
      tee -a "$LOG_FILE"

    FAILURES=$((FAILURES + 1))
}


echo "Prometheus Comprehensive Diagnostics" |
tee "$LOG_FILE"

echo "====================================" |
tee -a "$LOG_FILE"

echo "Timestamp: $(date -Is)" |
tee -a "$LOG_FILE"

echo "Hostname: $(hostname)" |
tee -a "$LOG_FILE"


run_check \
  "SYSTEM INFORMATION" \
  uname -a \
  || true


run_check \
  "MEMORY" \
  free -h \
  || true


run_check \
  "DISK" \
  df -h \
  || true


run_check \
  "CPU SUMMARY" \
  bash -c 'lscpu | head -15' \
  || true


section "PROMETHEUS SERVICE"

if systemctl is-active --quiet prometheus; then
    pass "Prometheus service active"
else
    fail "Prometheus service inactive"
fi

systemctl status \
  prometheus \
  --no-pager \
  -l \
  2>&1 |
tee -a "$LOG_FILE" \
|| true


section "NODE EXPORTER SERVICE"

if systemctl is-active --quiet node_exporter; then
    pass "Node Exporter service active"
else
    fail "Node Exporter service inactive"
fi

systemctl status \
  node_exporter \
  --no-pager \
  -l \
  2>&1 |
tee -a "$LOG_FILE" \
|| true


run_check \
  "PROMETHEUS PROCESS" \
  bash -c \
  'ps -eo pid,user,%cpu,%mem,rss,vsz,cmd | grep "[p]rometheus"' \
  || true


run_check \
  "LISTENING PORTS" \
  bash -c \
  'ss -lntp | grep -E ":(9090|9100)\b" || true'


section "CONFIGURATION VALIDATION"

if sudo -u prometheus \
    promtool check config \
    /etc/prometheus/prometheus.yml \
    2>&1 |
    tee -a "$LOG_FILE"
then
    pass "Prometheus configuration valid"
else
    fail "Prometheus configuration invalid"
fi


run_check \
  "CONFIGURATION PERMISSIONS" \
  ls -la \
  /etc/prometheus/prometheus.yml \
  || true


run_check \
  "PROMETHEUS DIRECTORY PERMISSIONS" \
  ls -ld \
  /etc/prometheus \
  /var/lib/prometheus \
  || true


run_check \
  "PROMETHEUS DATA SIZE" \
  du -sh \
  /var/lib/prometheus \
  || true


section "PROMETHEUS HEALTH"

if curl -fsS \
    http://127.0.0.1:9090/-/healthy \
    2>&1 |
    tee -a "$LOG_FILE"
then
    echo |
      tee -a "$LOG_FILE"

    pass "Prometheus healthy"
else
    fail "Prometheus health request failed"
fi


section "PROMETHEUS READINESS"

if curl -fsS \
    http://127.0.0.1:9090/-/ready \
    2>&1 |
    tee -a "$LOG_FILE"
then
    echo |
      tee -a "$LOG_FILE"

    pass "Prometheus ready"
else
    fail "Prometheus readiness request failed"
fi


section "NODE EXPORTER ENDPOINT"

if curl -fsS \
    http://127.0.0.1:9100/metrics \
    2>/dev/null |
    head -10 |
    tee -a "$LOG_FILE"
then
    pass "Node Exporter endpoint responsive"
else
    fail "Node Exporter endpoint failed"
fi


section "TARGET INVENTORY"

TARGETS="$(
  curl -fsS \
    http://127.0.0.1:9090/api/v1/targets \
    2>/dev/null || true
)"

echo "$TARGETS" |
jq -r '
  .data.activeTargets[]? |
  [
    .labels.job,
    .scrapeUrl,
    .health,
    (.lastError // "")
  ] |
  @tsv
' 2>/dev/null |
tee -a "$LOG_FILE"


DOWN_COUNT="$(
  echo "$TARGETS" |
  jq '
    [
      .data.activeTargets[]?
      | select(.health!="up")
    ]
    | length
  ' 2>/dev/null || echo 999
)"

if [ "$DOWN_COUNT" -eq 0 ]; then
    pass "All active scrape targets healthy"
else
    fail "$DOWN_COUNT scrape target(s) unhealthy"
fi


section "UP QUERY"

UP_QUERY="$(
  curl -fsSG \
    --data-urlencode 'query=up' \
    http://127.0.0.1:9090/api/v1/query \
    2>/dev/null || true
)"

echo "$UP_QUERY" |
jq -r '
  .data.result[]? |
  [
    (.metric.job // "unknown"),
    .value[1]
  ] |
  @tsv
' 2>/dev/null |
tee -a "$LOG_FILE"


BAD_UP="$(
  echo "$UP_QUERY" |
  jq '
    [
      .data.result[]?
      | select(.value[1]!="1")
    ]
    | length
  ' 2>/dev/null || echo 999
)"

if [ "$BAD_UP" -eq 0 ]; then
    pass "All returned up metrics equal 1"
else
    fail "$BAD_UP up series report failure"
fi


section "RECENT PROMETHEUS LOGS"

journalctl \
  -u prometheus \
  --since "10 minutes ago" \
  --no-pager \
  2>&1 |
tee -a "$LOG_FILE"


section "RECENT ERROR/WARNING FILTER"

RECENT_ERRORS="$(
  journalctl \
    -u prometheus \
    --since "5 minutes ago" \
    --no-pager |
  grep -Ei \
    'level=error|error=|permission denied|address already in use' \
    || true
)"

if [ -n "$RECENT_ERRORS" ]; then
    echo "$RECENT_ERRORS" |
      tee -a "$LOG_FILE"

    echo \
      "INFO: Historical controlled-failure errors may appear because this environment intentionally reproduced failures." |
      tee -a "$LOG_FILE"
else
    pass "No recent error-pattern log entries"
fi


section "DIAGNOSTIC RESULT"

if [ "$FAILURES" -eq 0 ]; then

    echo "PROMETHEUS DIAGNOSTICS: PASS" |
      tee -a "$LOG_FILE"

    echo "Diagnostic log: $LOG_FILE" |
      tee -a "$LOG_FILE"

    exit 0

else

    echo \
      "PROMETHEUS DIAGNOSTICS: FAIL ($FAILURES active checks)" |
      tee -a "$LOG_FILE"

    echo "Diagnostic log: $LOG_FILE" |
      tee -a "$LOG_FILE"

    exit 1

fi
