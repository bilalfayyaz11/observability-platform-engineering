#!/usr/bin/env bash
set -euo pipefail

JOB_NAME="advanced_data_processor"
INSTANCE="$(hostname)"
PUSHGATEWAY_URL="http://127.0.0.1:9091"
LOG_FILE="/tmp/${JOB_NAME}.log"

push_metrics() {
    local job_status="$1"
    local records_processed="$2"
    local errors_count="$3"
    local duration="$4"
    local timestamp="$5"

    cat <<METRICS |
# HELP batch_job_records_processed_total Total records processed in this run
# TYPE batch_job_records_processed_total counter
batch_job_records_processed_total ${records_processed}
# HELP batch_job_errors_total Total errors encountered in this run
# TYPE batch_job_errors_total counter
batch_job_errors_total ${errors_count}
# HELP batch_job_duration_seconds Duration of the job execution
# TYPE batch_job_duration_seconds gauge
batch_job_duration_seconds ${duration}
# HELP batch_job_status Job completion status (1=success, 0=failure)
# TYPE batch_job_status gauge
batch_job_status ${job_status}
# HELP batch_job_last_run_timestamp Unix timestamp of last job execution
# TYPE batch_job_last_run_timestamp gauge
batch_job_last_run_timestamp ${timestamp}
METRICS
    curl \
      --fail \
      --silent \
      --show-error \
      --data-binary @- \
      "${PUSHGATEWAY_URL}/metrics/job/${JOB_NAME}/instance/${INSTANCE}"
}

log_message() {
    printf '%s - %s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" \
      "$1" |
    tee -a "$LOG_FILE"
}

main() {
    local start_time
    local end_time
    local duration
    local records_processed=0
    local errors_count=0
    local job_status=1

    start_time="$(date +%s)"

    log_message "Starting advanced batch job: ${JOB_NAME}"

    for i in $(seq 1 50); do
        sleep 0.05

        if [[ $((RANDOM % 20)) -eq 0 ]]; then
            errors_count="$((errors_count + 1))"
            log_message "Error processing record ${i}"
        else
            records_processed="$((records_processed + 1))"
        fi
    done

    end_time="$(date +%s)"
    duration="$((end_time - start_time))"

    if [[ "$errors_count" -gt 10 ]]; then
        job_status=0
        log_message "Job failed: too many errors (${errors_count})"
    else
        log_message \
          "Job completed: ${records_processed} records processed, ${errors_count} errors"
    fi

    push_metrics \
      "$job_status" \
      "$records_processed" \
      "$errors_count" \
      "$duration" \
      "$end_time"

    log_message "Metrics pushed to Pushgateway"
}

main
