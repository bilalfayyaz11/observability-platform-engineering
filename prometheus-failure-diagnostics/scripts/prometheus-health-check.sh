#!/usr/bin/env bash

FAILURES=0

pass() {
    echo "PASS: $1"
}

fail() {
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

echo "===== PROMETHEUS HEALTH CHECK ====="
echo "Timestamp: $(date -Is)"

echo
echo "--- Service state ---"

if systemctl is-active --quiet prometheus; then
    pass "Prometheus service active"
else
    fail "Prometheus service inactive"
fi

if systemctl is-active --quiet node_exporter; then
    pass "Node Exporter service active"
else
    fail "Node Exporter service inactive"
fi


echo
echo "--- Listener state ---"

if ss -lnt | grep -q ':9090 '; then
    pass "Prometheus port 9090 listening"
else
    fail "Prometheus port 9090 not listening"
fi

if ss -lnt | grep -q ':9100 '; then
    pass "Node Exporter port 9100 listening"
else
    fail "Node Exporter port 9100 not listening"
fi


echo
echo "--- HTTP health ---"

if curl -fsS \
    http://127.0.0.1:9090/-/healthy \
    >/dev/null
then
    pass "Prometheus healthy endpoint"
else
    fail "Prometheus healthy endpoint"
fi

if curl -fsS \
    http://127.0.0.1:9090/-/ready \
    >/dev/null
then
    pass "Prometheus ready endpoint"
else
    fail "Prometheus ready endpoint"
fi

if curl -fsS \
    http://127.0.0.1:9100/metrics \
    >/dev/null
then
    pass "Node Exporter metrics endpoint"
else
    fail "Node Exporter metrics endpoint"
fi


echo
echo "--- Configuration ---"

if sudo -u prometheus \
    promtool check config \
    /etc/prometheus/prometheus.yml \
    >/dev/null
then
    pass "Prometheus configuration valid"
else
    fail "Prometheus configuration invalid"
fi


echo
echo "--- Target health ---"

TARGETS="$(
  curl -fsS \
    http://127.0.0.1:9090/api/v1/targets \
    2>/dev/null || true
)"

DOWN_COUNT="$(
  echo "$TARGETS" |
  jq '
    [
      .data.activeTargets[]
      | select(.health!="up")
    ] | length
  ' 2>/dev/null || echo 999
)"

if [ "$DOWN_COUNT" -eq 0 ]; then
    pass "All active scrape targets UP"
else
    fail "$DOWN_COUNT scrape target(s) unhealthy"
fi


echo
echo "--- Recent errors ---"

ERRORS="$(
  journalctl \
    -u prometheus \
    --since "5 minutes ago" \
    --no-pager |
  grep -Ei \
    'level=error|error=' \
    || true
)"

if [ -z "$ERRORS" ]; then
    pass "No recent Prometheus error log entries"
else
    echo "$ERRORS"
    fail "Recent Prometheus errors detected"
fi


echo
echo "===== RESULT ====="

if [ "$FAILURES" -eq 0 ]; then
    echo "PROMETHEUS HEALTH: PASS"
    exit 0
else
    echo "PROMETHEUS HEALTH: FAIL ($FAILURES checks)"
    exit 1
fi
