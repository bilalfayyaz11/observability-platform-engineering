#!/usr/bin/env bash

PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:9090}"

pql_instant() {
    local query="${1:-}"

    if [[ -z "$query" ]]; then
        echo "ERROR: pql_instant requires a PromQL expression" >&2
        return 2
    fi

    local response
    local curl_status

    response="$(
        curl \
          --get \
          --silent \
          --show-error \
          --connect-timeout 5 \
          --max-time 20 \
          --data-urlencode "query=${query}" \
          "${PROMETHEUS_URL}/api/v1/query"
    )"

    curl_status=$?

    if [[ "$curl_status" -ne 0 ]]; then
        echo "ERROR: Prometheus API request failed" >&2
        return "$curl_status"
    fi

    local status
    status="$(
        jq -r '.status // "unknown"' <<<"$response"
    )"

    if [[ "$status" != "success" ]]; then
        local error_type
        local error_message

        error_type="$(
            jq -r '.errorType // "unknown"' <<<"$response"
        )"

        error_message="$(
            jq -r '.error // "unknown Prometheus API error"' <<<"$response"
        )"

        echo "ERROR: ${error_type}: ${error_message}" >&2
        return 1
    fi

    printf '%s\n' "$response"
}

pql_range() {
    local query="${1:-}"
    local start="${2:-}"
    local end="${3:-}"
    local step="${4:-}"

    if [[ -z "$query" || -z "$start" || -z "$end" || -z "$step" ]]; then
        echo "ERROR: pql_range requires QUERY START_EPOCH END_EPOCH STEP" >&2
        return 2
    fi

    local response
    local curl_status

    response="$(
        curl \
          --get \
          --silent \
          --show-error \
          --connect-timeout 5 \
          --max-time 30 \
          --data-urlencode "query=${query}" \
          --data-urlencode "start=${start}" \
          --data-urlencode "end=${end}" \
          --data-urlencode "step=${step}" \
          "${PROMETHEUS_URL}/api/v1/query_range"
    )"

    curl_status=$?

    if [[ "$curl_status" -ne 0 ]]; then
        echo "ERROR: Prometheus range API request failed" >&2
        return "$curl_status"
    fi

    local status
    status="$(
        jq -r '.status // "unknown"' <<<"$response"
    )"

    if [[ "$status" != "success" ]]; then
        local error_type
        local error_message

        error_type="$(
            jq -r '.errorType // "unknown"' <<<"$response"
        )"

        error_message="$(
            jq -r '.error // "unknown Prometheus API error"' <<<"$response"
        )"

        echo "ERROR: ${error_type}: ${error_message}" >&2
        return 1
    fi

    printf '%s\n' "$response"
}
