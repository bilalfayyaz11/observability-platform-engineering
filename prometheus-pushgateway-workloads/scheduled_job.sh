#!/usr/bin/env bash
set -euo pipefail

JOB_NAME="system_maintenance"
INSTANCE="$(hostname)"
PUSHGATEWAY_URL="http://127.0.0.1:9091"

TASKS=(
    cleanup_temp_files
    rotate_logs
    update_cache
    backup_config
    check_disk_space
)

TOTAL_TASKS="${#TASKS[@]}"
COMPLETED_TASKS=0
FAILED_TASKS=0

echo "===== SCHEDULED MAINTENANCE ====="

START_TIME="$(date +%s)"

for task in "${TASKS[@]}"; do

    echo "Executing: ${task}"
    sleep 1

    if [[ $((RANDOM % 10)) -lt 9 ]]; then
        echo "  ${task}: SUCCESS"
        COMPLETED_TASKS="$((COMPLETED_TASKS + 1))"
    else
        echo "  ${task}: FAILED"
        FAILED_TASKS="$((FAILED_TASKS + 1))"
    fi
done

END_TIME="$(date +%s)"
DURATION="$((END_TIME - START_TIME))"

SUCCESS_RATE="$(
  bc -l <<< \
    "scale=2; ${COMPLETED_TASKS} * 100 / ${TOTAL_TASKS}"
)"

echo
echo "Completed tasks: ${COMPLETED_TASKS}"
echo "Failed tasks:    ${FAILED_TASKS}"
echo "Success rate:    ${SUCCESS_RATE}%"
echo "Duration:        ${DURATION}s"

cat <<METRICS |
# HELP maintenance_tasks_total Total number of maintenance tasks
# TYPE maintenance_tasks_total gauge
maintenance_tasks_total ${TOTAL_TASKS}
# HELP maintenance_tasks_completed_total Number of completed tasks
# TYPE maintenance_tasks_completed_total counter
maintenance_tasks_completed_total ${COMPLETED_TASKS}
# HELP maintenance_tasks_failed_total Number of failed tasks
# TYPE maintenance_tasks_failed_total counter
maintenance_tasks_failed_total ${FAILED_TASKS}
# HELP maintenance_success_rate_percent Success rate of maintenance tasks
# TYPE maintenance_success_rate_percent gauge
maintenance_success_rate_percent ${SUCCESS_RATE}
# HELP maintenance_duration_seconds Duration of maintenance execution
# TYPE maintenance_duration_seconds gauge
maintenance_duration_seconds ${DURATION}
# HELP maintenance_last_run_timestamp Last execution timestamp
# TYPE maintenance_last_run_timestamp gauge
maintenance_last_run_timestamp ${END_TIME}
METRICS
curl \
  --fail \
  --silent \
  --show-error \
  --data-binary @- \
  "${PUSHGATEWAY_URL}/metrics/job/${JOB_NAME}/instance/${INSTANCE}"

echo "Maintenance metrics pushed successfully."
