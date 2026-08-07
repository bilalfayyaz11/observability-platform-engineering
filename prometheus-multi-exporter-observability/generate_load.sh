#!/usr/bin/env bash
set -euo pipefail

PID_FILE="/home/ubuntu/prometheus-exporter-engineering/load_test.pids"
TEST_FILE="/tmp/prometheus_exporter_io_test.bin"

cleanup() {
    if [[ -f "$PID_FILE" ]]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < "$PID_FILE"

        rm -f "$PID_FILE"
    fi

    pkill -x yes 2>/dev/null || true
    rm -f "$TEST_FILE"
}

trap cleanup EXIT INT TERM

: > "$PID_FILE"

echo "===== START CPU LOAD ====="

for _ in $(seq 1 "$(nproc)"); do
    yes > /dev/null &
    echo "$!" >> "$PID_FILE"
done

echo "CPU workers started: $(wc -l < "$PID_FILE")"

echo "===== START MEMORY LOAD ====="

stress-ng \
    --vm 1 \
    --vm-bytes 512M \
    --vm-keep \
    --timeout 60s &

echo "$!" >> "$PID_FILE"

echo "===== START DISK I/O ====="

dd \
    if=/dev/zero \
    of="$TEST_FILE" \
    bs=1M \
    count=512 \
    conv=fdatasync \
    status=progress &

echo "$!" >> "$PID_FILE"

echo "===== LOAD ACTIVE ====="
echo "Monitoring interval: 60 seconds"

sleep 60

echo "===== LOAD GENERATION COMPLETE ====="
