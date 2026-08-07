#!/usr/bin/env bash
set -euo pipefail

JOB_NAME="data_processing_job"
INSTANCE="batch-server-01"
PUSHGATEWAY_URL="http://127.0.0.1:9091"

echo "===== SIMPLE BATCH JOB ====="
echo "Job:      ${JOB_NAME}"
echo "Instance: ${INSTANCE}"

START_TIME="$(date +%s)"

echo "Processing data..."
sleep 3

RECORDS_PROCESSED=1250
ERRORS_ENCOUNTERED=3

END_TIME="$(date +%s)"
JOB_DURATION="$((END_TIME - START_TIME))"

echo "Records processed: ${RECORDS_PROCESSED}"
echo "Errors encountered: ${ERRORS_ENCOUNTERED}"
echo "Duration: ${JOB_DURATION}s"

cat <<METRICS |
# HELP batch_job_records_processed_total Total number of records processed
# TYPE batch_job_records_processed_total counter
batch_job_records_processed_total ${RECORDS_PROCESSED}
# HELP batch_job_errors_total Total number of errors encountered
# TYPE batch_job_errors_total counter
batch_job_errors_total ${ERRORS_ENCOUNTERED}
# HELP batch_job_duration_seconds Time taken to complete the job
# TYPE batch_job_duration_seconds gauge
batch_job_duration_seconds ${JOB_DURATION}
# HELP batch_job_last_success_unixtime Last time the job completed successfully
# TYPE batch_job_last_success_unixtime gauge
batch_job_last_success_unixtime ${END_TIME}
METRICS
curl \
  --fail \
  --silent \
  --show-error \
  --data-binary @- \
  "${PUSHGATEWAY_URL}/metrics/job/${JOB_NAME}/instance/${INSTANCE}"

echo "Metrics pushed successfully."
