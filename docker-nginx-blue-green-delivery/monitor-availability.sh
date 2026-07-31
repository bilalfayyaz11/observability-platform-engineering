#!/usr/bin/env bash

set -euo pipefail

DURATION="${1:-15}"
INTERVAL="${2:-0.2}"
OUTPUT_FILE="${3:-availability-results.log}"

: > "$OUTPUT_FILE"

START_TIME=$(date +%s)
TOTAL=0
SUCCESSFUL=0
FAILED=0

while (( $(date +%s) - START_TIME < DURATION )); do
    TOTAL=$((TOTAL + 1))

    TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%S.%3NZ')

    HTTP_CODE=$(
        curl \
            --noproxy '*' \
            --silent \
            --output /dev/null \
            --write-out '%{http_code}' \
            --connect-timeout 1 \
            --max-time 2 \
            http://127.0.0.1/ \
            || true
    )

    if [[ "$HTTP_CODE" == "200" ]]; then
        SUCCESSFUL=$((SUCCESSFUL + 1))
        echo "$TIMESTAMP success HTTP=$HTTP_CODE" >> "$OUTPUT_FILE"
    else
        FAILED=$((FAILED + 1))
        echo "$TIMESTAMP failure HTTP=${HTTP_CODE:-000}" >> "$OUTPUT_FILE"
    fi

    sleep "$INTERVAL"
done

{
    echo "total_requests=$TOTAL"
    echo "successful_requests=$SUCCESSFUL"
    echo "failed_requests=$FAILED"
} |
tee -a "$OUTPUT_FILE"

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
