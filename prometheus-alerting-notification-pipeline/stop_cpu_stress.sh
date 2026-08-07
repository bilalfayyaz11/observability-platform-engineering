#!/usr/bin/env bash
set -euo pipefail

PID_FILE="/home/ubuntu/prometheus-alerting-engineering/cpu_stress.pids"

if [[ ! -f "$PID_FILE" ]]; then
    echo "No CPU stress PID file found."
    exit 0
fi

while read -r pid; do
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        echo "Stopped PID ${pid}"
    fi
done < "$PID_FILE"

rm -f "$PID_FILE"

echo "CPU stress stopped."
