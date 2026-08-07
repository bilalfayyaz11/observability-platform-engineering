#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="http://127.0.0.1:9090"
FAILURES_FOUND=0

query_api() {
    local query="$1"

    curl \
      --get \
      --fail \
      --silent \
      --show-error \
      --data-urlencode "query=${query}" \
      "${PROMETHEUS_URL}/api/v1/query"
}

rule_health_check() {
    local metric_name="$1"

    echo
    echo "----- ${metric_name} -----"

    case "$metric_name" in

        prometheus_rule_evaluation_duration_seconds)

            QUERY='histogram_quantile(0.99, sum by (le, rule_group) (rate(prometheus_rule_evaluation_duration_seconds_bucket[5m])))'

            RESULT="$(
              query_api "$QUERY"
            )"

            COUNT="$(
              jq '.data.result | length' \
              <<<"$RESULT"
            )"

            if [[ "$COUNT" -lt 1 ]]; then
                echo "No p99 evaluation-duration data available yet."
                return
            fi

            jq -r '
              .data.result[]
              |
              "group=\(.metric.rule_group // "unknown") p99_seconds=\(.value[1])"
            ' <<<"$RESULT"
            ;;

        prometheus_rule_evaluation_failures_total)

            RESULT="$(
              query_api \
                'sum by (rule_group) (prometheus_rule_evaluation_failures_total)'
            )"

            COUNT="$(
              jq '.data.result | length' \
              <<<"$RESULT"
            )"

            if [[ "$COUNT" -lt 1 ]]; then
                echo "No rule-failure series returned."
                return
            fi

            while IFS=$'\t' read -r group value; do

                echo "group=${group} failures=${value}"

                python3 - "$value" <<'PY'
import sys

value = float(sys.argv[1])

if value > 0:
    raise SystemExit(1)
PY

                if [[ "$?" -ne 0 ]]; then
                    FAILURES_FOUND=1
                fi

            done < <(
              jq -r '
                .data.result[]
                |
                [
                  (.metric.rule_group // "unknown"),
                  .value[1]
                ]
                | @tsv
              ' <<<"$RESULT"
            )
            ;;

        prometheus_rule_group_last_duration_seconds)

            RESULT="$(
              query_api \
                'prometheus_rule_group_last_duration_seconds'
            )"

            COUNT="$(
              jq '.data.result | length' \
              <<<"$RESULT"
            )"

            if [[ "$COUNT" -lt 1 ]]; then
                echo "No last-duration series returned."
                return
            fi

            jq -r '
              .data.result[]
              |
              "group=\(.metric.rule_group // "unknown") last_duration_seconds=\(.value[1])"
            ' <<<"$RESULT"
            ;;

        *)
            echo "ERROR: Unsupported metric: ${metric_name}" >&2
            exit 1
            ;;
    esac
}

echo "====================================================="
echo "PROMETHEUS RECORDING RULE HEALTH"
echo "====================================================="

rule_health_check \
  "prometheus_rule_evaluation_duration_seconds"

rule_health_check \
  "prometheus_rule_evaluation_failures_total"

rule_health_check \
  "prometheus_rule_group_last_duration_seconds"

echo
echo "===== RULE API HEALTH ====="

RULE_JSON="$(
  curl \
    --fail \
    --silent \
    --show-error \
    "${PROMETHEUS_URL}/api/v1/rules"
)"

jq -r '
  .data.groups[]
  | select(
      .name == "node_base"
      or .name == "node_composite"
    )
  |
  "group=\(.name) interval=\(.interval) evaluation_time=\(.evaluationTime)",
  (
    .rules[]
    |
    "  rule=\(.name) health=\(.health) error=\(.lastError)"
  )
' <<<"$RULE_JSON"

API_ERRORS="$(
  jq '
    [
      .data.groups[]
      | select(
          .name == "node_base"
          or .name == "node_composite"
        )
      | .rules[]
      | select(
          .health != "ok"
          or (.lastError != null and .lastError != "")
        )
    ]
    | length
  ' <<<"$RULE_JSON"
)"

if [[ "$API_ERRORS" -ne 0 ]]; then
    FAILURES_FOUND=1
fi

echo
echo "===== FINAL HEALTH VERDICT ====="

if [[ "$FAILURES_FOUND" -ne 0 ]]; then
    echo "RULE HEALTH DEGRADED" >&2
    exit 1
fi

echo "All rule groups healthy."
exit 0
