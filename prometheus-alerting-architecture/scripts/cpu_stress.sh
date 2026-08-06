#!/usr/bin/env bash

DURATION_SECONDS="${1:-180}"
WORKERS="${2:-4}"
PID_FILE="/tmp/prometheus_cpu_stress.pids"

: > "$PID_FILE"

echo "Starting ${WORKERS} CPU workers for ${DURATION_SECONDS} seconds..."

for _ in $(seq 1 "$WORKERS"); do
    timeout "${DURATION_SECONDS}" yes > /dev/null &
    echo "$!" >> "$PID_FILE"
done

echo "Worker PIDs:"
cat "$PID_FILE"
