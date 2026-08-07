#!/usr/bin/env bash
set -euo pipefail

PID_FILE="/home/ubuntu/prometheus-alerting-engineering/cpu_stress.pids"

if [[ -f "$PID_FILE" ]]; then
    while read -r pid; do
        kill "$pid" 2>/dev/null || true
    done < "$PID_FILE"

    rm -f "$PID_FILE"
fi

: > "$PID_FILE"

WORKERS="$(nproc)"

echo "Starting ${WORKERS} CPU stress workers..."

for _ in $(seq 1 "$WORKERS"); do
    yes > /dev/null &
    echo "$!" >> "$PID_FILE"
done

echo "Stress worker PIDs:"
cat "$PID_FILE"
