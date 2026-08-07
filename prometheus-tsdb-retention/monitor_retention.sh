#!/usr/bin/env bash
set -euo pipefail

DURATION="${1:-300}"
INTERVAL="${2:-30}"
DATA_DIR="/var/lib/prometheus"

show_storage_info() {
    echo "--- STORAGE INFORMATION ---"

    echo "Prometheus data directory:"
    sudo du -sh "$DATA_DIR"

    echo
    echo "Top-level TSDB contents:"
    sudo du -sh "$DATA_DIR"/* 2>/dev/null | sort -h | tail -10 || true

    echo
    echo "Filesystem capacity:"
    df -h "$DATA_DIR"
}

show_retention_settings() {
    echo
    echo "--- RETENTION SETTINGS ---"

    awk '
      /^storage:/,/^scrape_configs:/ {
        if ($0 !~ /^scrape_configs:/) print
      }
    ' /etc/prometheus/prometheus.yml
}

show_tsdb_stats() {
    echo
    echo "--- TSDB STATISTICS ---"

    curl -fsSL http://localhost:9090/api/v1/status/tsdb | \
      jq '{
        headStats: .data.headStats,
        seriesCountByMetricName: (.data.seriesCountByMetricName[0:5] // []),
        labelValueCountByLabelName: (.data.labelValueCountByLabelName[0:5] // [])
      }'
}

show_block_info() {
    echo
    echo "--- TSDB BLOCK INFORMATION ---"

    mapfile -t blocks < <(
      sudo find "$DATA_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name '[0-9A-Z]*' \
        -printf '%f\n' 2>/dev/null | sort
    )

    if [ "${#blocks[@]}" -eq 0 ]; then
        echo "No persisted TSDB blocks yet."
        echo "Prometheus may still be storing recent samples in the head/WAL."
        return
    fi

    echo "Persisted blocks: ${#blocks[@]}"

    for block in "${blocks[@]}"; do
        meta="$DATA_DIR/$block/meta.json"

        if sudo test -f "$meta"; then
            min_time=$(sudo jq -r '.minTime // empty' "$meta")
            max_time=$(sudo jq -r '.maxTime // empty' "$meta")

            if [ -n "$min_time" ] && [ -n "$max_time" ]; then
                min_sec=$((min_time / 1000))
                max_sec=$((max_time / 1000))

                echo
                echo "Block: $block"
                echo "  Start: $(date -d "@$min_sec" '+%Y-%m-%d %H:%M:%S %Z')"
                echo "  End:   $(date -d "@$max_sec" '+%Y-%m-%d %H:%M:%S %Z')"
                echo "  Size:  $(sudo du -sh "$DATA_DIR/$block" | cut -f1)"
            fi
        fi
    done
}

show_metric_health() {
    echo
    echo "--- SCRAPE HEALTH ---"

    curl -fsSL http://localhost:9090/api/v1/targets | \
      jq -r '.data.activeTargets[] |
      [.labels.job, .health, (.lastError // "")] | @tsv'
}

show_recent_logs() {
    echo
    echo "--- RECENT PROMETHEUS LOGS ---"

    sudo journalctl \
      -u prometheus \
      --since "2 minutes ago" \
      --no-pager \
      -n 10 || true
}

echo "===== PROMETHEUS RETENTION MONITOR ====="
echo "Duration: ${DURATION}s"
echo "Interval: ${INTERVAL}s"
echo

END_TIME=$(( $(date +%s) + DURATION ))

while [ "$(date +%s)" -lt "$END_TIME" ]; do

    echo
    echo "============================================================"
    echo "Monitoring update: $(date)"
    echo "============================================================"

    show_storage_info
    show_retention_settings
    show_tsdb_stats
    show_block_info
    show_metric_health
    show_recent_logs

    remaining=$(( END_TIME - $(date +%s) ))

    if [ "$remaining" -le 0 ]; then
        break
    fi

    sleep_time="$INTERVAL"

    if [ "$remaining" -lt "$INTERVAL" ]; then
        sleep_time="$remaining"
    fi

    echo
    echo "Next sample in ${sleep_time}s..."
    sleep "$sleep_time"
done

echo
echo "===== RETENTION MONITORING COMPLETE ====="
