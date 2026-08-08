#!/bin/bash

set -u

echo "Generating CPU, memory, and HTTP load..."

stress-ng --cpu 2 --timeout 60s >/tmp/stress-cpu.log 2>&1 &
CPU_PID=$!

stress-ng --vm 1 --vm-bytes 512M --timeout 30s >/tmp/stress-memory.log 2>&1 &
MEM_PID=$!

for i in $(seq 1 200); do
  curl -s "http://127.0.0.1:8000/load-$i" >/dev/null &

  if [ $((i % 20)) -eq 0 ]; then
    wait
    sleep 1
  fi
done

wait "$CPU_PID" 2>/dev/null || true
wait "$MEM_PID" 2>/dev/null || true
wait

echo "Load generation complete."
