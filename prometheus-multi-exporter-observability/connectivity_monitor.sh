#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="http://127.0.0.1:9090"

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

echo "========================================"
echo "CONNECTIVITY MONITORING REPORT"
echo "========================================"
echo "Timestamp: $(date --iso-8601=seconds)"
echo

echo "HTTP ENDPOINTS"

HTTP_TARGETS=(
    "http://127.0.0.1:9090/-/ready"
    "https://github.com"
    "https://www.google.com"
)

for target in "${HTTP_TARGETS[@]}"; do

    STATUS="$(
      probe_status \
        blackbox_http \
        "$target"
    )"

    case "$STATUS" in
        1)
            echo "  ${target}: REACHABLE"
            ;;
        0)
            echo "  ${target}: UNREACHABLE"
            ;;
        *)
            echo "  ${target}: NO DATA"
            ;;
    esac
done

echo
echo "TCP ENDPOINTS"

TCP_TARGETS=(
    "127.0.0.1:3306"
    "127.0.0.1:9090"
    "127.0.0.1:9104"
)

for target in "${TCP_TARGETS[@]}"; do

    STATUS="$(
      probe_status \
        blackbox_tcp \
        "$target"
    )"

    case "$STATUS" in
        1)
            echo "  ${target}: OPEN"
            ;;
        0)
            echo "  ${target}: CLOSED"
            ;;
        *)
            echo "  ${target}: NO DATA"
            ;;
    esac
done

echo
echo "========================================"
