#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/prometheus/prometheus.yml"

apply_retention() {
    local retention_time="$1"
    local retention_size="$2"

    echo
    echo "=================================================="
    echo "Applying retention policy:"
    echo "Time: ${retention_time}"
    echo "Size: ${retention_size}"
    echo "=================================================="

    sudo python3 - "$CONFIG" "$retention_time" "$retention_size" <<'PY'
import sys
from pathlib import Path

config = Path(sys.argv[1])
retention_time = sys.argv[2]
retention_size = sys.argv[3]

text = config.read_text()

lines = text.splitlines()
output = []

inside_storage = False
inside_tsdb = False
inside_retention = False

for line in lines:
    stripped = line.strip()

    if stripped == "storage:":
        inside_storage = True

    if inside_storage and stripped == "tsdb:":
        inside_tsdb = True

    if inside_tsdb and stripped == "retention:":
        inside_retention = True

    if inside_retention and stripped.startswith("time:"):
        output.append(f"      time: {retention_time}")
        continue

    if inside_retention and stripped.startswith("size:"):
        output.append(f"      size: {retention_size}")
        inside_retention = False
        continue

    output.append(line)

config.write_text("\n".join(output) + "\n")
PY

    sudo chown prometheus:prometheus "$CONFIG"

    echo
    echo "Validating configuration..."
    /usr/local/bin/promtool check config "$CONFIG"

    echo
    echo "Reloading Prometheus..."
    curl -fsS -X POST http://localhost:9090/-/reload

    sleep 3

    echo
    echo "Active retention configuration:"
    grep -A6 '^storage:' "$CONFIG"

    echo
    echo "Prometheus health:"
    curl -fsS http://localhost:9090/-/ready
    echo

    echo
    echo "Service PID:"
    systemctl show prometheus --property=MainPID --value
}

echo "===== RETENTION CONFIGURATION TEST ====="

echo
echo "Test 1 — short retention"
apply_retention "2h" "500MB"

echo
echo "Test 2 — medium retention"
apply_retention "1d" "1GB"

echo
echo "Test 3 — production-like retention"
apply_retention "15d" "5GB"

echo
echo "===== FINAL VALIDATION ====="

echo "Final configuration:"
grep -A6 '^storage:' /etc/prometheus/prometheus.yml

echo
echo "Prometheus target health:"
curl -fsSL http://localhost:9090/api/v1/targets | \
jq -r '.data.activeTargets[] | [.labels.job, .health] | @tsv'

echo
echo "===== RETENTION TESTING COMPLETE ====="
