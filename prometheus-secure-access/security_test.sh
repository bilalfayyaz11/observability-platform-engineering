#!/usr/bin/env bash

PASS=0
FAIL=0

pass() {
    echo "   ✓ $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "   ✗ $1"
    FAIL=$((FAIL + 1))
}

echo "============================================================"
echo "        PROMETHEUS SECURITY VERIFICATION"
echo "============================================================"
echo

echo "1. Prometheus backend TLS"

if curl \
    --cacert /etc/ssl/prometheus/prometheus.crt \
    -fsS \
    https://localhost:9090/-/healthy >/dev/null
then
    pass "Prometheus HTTPS backend is healthy"
else
    fail "Prometheus HTTPS backend failed"
fi

echo
echo "2. Public authentication enforcement"

STATUS=$(curl -k -s \
    -o /dev/null \
    -w '%{http_code}' \
    https://localhost/)

if [ "$STATUS" = "401" ]; then
    pass "Unauthenticated requests are denied"
else
    fail "Expected HTTP 401, received HTTP $STATUS"
fi

echo
echo "3. Admin web access"

STATUS=$(curl -k -s \
    -u 'admin:AdminPass123!' \
    -o /dev/null \
    -w '%{http_code}' \
    https://localhost/)

if [ "$STATUS" = "200" ]; then
    pass "Admin can access Prometheus web interface"
else
    fail "Admin access returned HTTP $STATUS"
fi

echo
echo "4. Viewer query access"

RESULT=$(curl -k -s \
    -u 'viewer:ViewerPass456!' \
    'https://localhost/api/v1/query?query=up' | \
    jq -r '.status // "failed"' 2>/dev/null)

if [ "$RESULT" = "success" ]; then
    pass "Viewer can execute PromQL queries"
else
    fail "Viewer query access failed"
fi

echo
echo "5. Readonly metrics access"

STATUS=$(curl -k -s \
    -u 'readonly:ReadOnlyPass789!' \
    -o /dev/null \
    -w '%{http_code}' \
    https://localhost/metrics)

if [ "$STATUS" = "200" ]; then
    pass "Readonly user can access metrics endpoint"
else
    fail "Readonly metrics access returned HTTP $STATUS"
fi

echo
echo "6. Viewer denied admin endpoint"

STATUS=$(curl -k -s \
    -u 'viewer:ViewerPass456!' \
    -o /dev/null \
    -w '%{http_code}' \
    https://localhost/api/v1/admin/tsdb/snapshot)

if [ "$STATUS" = "401" ] || [ "$STATUS" = "403" ]; then
    pass "Viewer is denied administrative access"
else
    fail "Viewer admin endpoint unexpectedly returned HTTP $STATUS"
fi

echo
echo "7. Readonly denied query endpoint"

STATUS=$(curl -k -s \
    -u 'readonly:ReadOnlyPass789!' \
    -o /dev/null \
    -w '%{http_code}' \
    'https://localhost/api/v1/query?query=up')

if [ "$STATUS" = "401" ] || [ "$STATUS" = "403" ]; then
    pass "Readonly user is denied query access"
else
    fail "Readonly query endpoint unexpectedly returned HTTP $STATUS"
fi

echo
echo "8. HTTP to HTTPS redirect"

STATUS=$(curl -s \
    -o /dev/null \
    -w '%{http_code}' \
    http://localhost/)

if [ "$STATUS" = "301" ] || [ "$STATUS" = "302" ]; then
    pass "HTTP redirects to HTTPS"
else
    fail "HTTP redirect returned HTTP $STATUS"
fi

echo
echo "9. TLS certificate verification"

VERIFY=$(
    openssl s_client \
      -connect localhost:443 \
      -servername localhost \
      -CAfile /etc/ssl/prometheus/prometheus.crt \
      </dev/null 2>/dev/null | \
    grep 'Verify return code'
)

if echo "$VERIFY" | grep -q '0 (ok)'; then
    pass "Nginx TLS certificate validates successfully"
else
    fail "Certificate validation failed: $VERIFY"
fi

echo
echo "10. TLS protocol enforcement"

PROTOCOL=$(
    openssl s_client \
      -connect localhost:443 \
      -servername localhost \
      -tls1_2 \
      -CAfile /etc/ssl/prometheus/prometheus.crt \
      </dev/null 2>/dev/null | \
    grep -E 'Protocol *:' | head -1
)

if echo "$PROTOCOL" | grep -q 'TLSv1.2'; then
    pass "TLS 1.2 connection succeeds"
else
    fail "TLS 1.2 validation failed"
fi

echo
echo "11. Backend network isolation"

PROM_ADDR=$(sudo ss -lnt | awk '$4 ~ /:9090$/ {print $4}')
NODE_ADDR=$(sudo ss -lnt | awk '$4 ~ /:9100$/ {print $4}')

if echo "$PROM_ADDR" | grep -q '127.0.0.1:9090'; then
    pass "Prometheus is restricted to loopback"
else
    fail "Prometheus listener is not loopback-only: $PROM_ADDR"
fi

if echo "$NODE_ADDR" | grep -q '127.0.0.1:9100'; then
    pass "Node Exporter is restricted to loopback"
else
    fail "Node Exporter listener is not loopback-only: $NODE_ADDR"
fi

echo
echo "12. Core service state"

SERVICES_OK=true

for SERVICE in prometheus nginx node_exporter; do
    if systemctl is-active --quiet "$SERVICE"; then
        echo "   ✓ $SERVICE: active"
    else
        echo "   ✗ $SERVICE: inactive"
        SERVICES_OK=false
    fi
done

if [ "$SERVICES_OK" = true ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi

echo
echo "============================================================"
echo "RESULT"
echo "============================================================"
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -eq 0 ]; then
    echo
    echo "SECURITY VALIDATION: PASSED"
    exit 0
else
    echo
    echo "SECURITY VALIDATION: FAILED"
    exit 1
fi
