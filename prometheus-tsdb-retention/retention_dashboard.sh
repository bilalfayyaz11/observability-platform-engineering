#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="/var/lib/prometheus"
CONFIG="/etc/prometheus/prometheus.yml"

show_header() {
    clear 2>/dev/null || true

    echo "============================================================"
    echo "            PROMETHEUS RETENTION DASHBOARD"
    echo "============================================================"
    echo "Last updated: $(date)"
    echo
}

show_key_metrics() {
    echo "--- KEY RETENTION METRICS ---"

    storage_size=$(sudo du -sh "$DATA_DIR" 2>/dev/null | awk '{print $1}')
    storage_bytes=$(sudo du -sb "$DATA_DIR" 2>/dev/null | awk '{print $1}')

    echo "Total TSDB storage: $storage_size"

    block_count=$(
        sudo find "$DATA_DIR" \
          -mindepth 1 \
          -maxdepth 1 \
          -type f \
          -name meta.json \
          2>/dev/null | wc -l
    )

    if [ "$block_count" -eq 0 ]; then
        block_count=$(
            sudo find "$DATA_DIR" \
              -mindepth 2 \
              -maxdepth 2 \
              -type f \
              -name meta.json \
              2>/dev/null | wc -l
        )
    fi

    echo "Persisted TSDB blocks: $block_count"

    echo
    echo "Configured retention:"

    awk '
      /^storage:/,/^scrape_configs:/ {
        if ($0 !~ /^scrape_configs:/) print "  " $0
      }
    ' "$CONFIG"

    echo
}

show_tsdb_health() {
    echo "--- TSDB HEALTH ---"

    stats=$(curl -fsSL http://localhost:9090/api/v1/status/tsdb 2>/dev/null || true)

    if [ -n "$stats" ]; then

        status=$(echo "$stats" | jq -r '.status // "unknown"')
        series=$(echo "$stats" | jq -r '.data.headStats.numSeries // 0')
        chunks=$(echo "$stats" | jq -r '.data.headStats.chunkCount // 0')

        echo "API status: $status"
        echo "Active series: $series"
        echo "Head chunks: $chunks"

    else
        echo "TSDB API: UNREACHABLE"
    fi

    echo
}

show_scrape_health() {
    echo "--- SCRAPE TARGET HEALTH ---"

    curl -fsSL http://localhost:9090/api/v1/targets 2>/dev/null | \
      jq -r '
        .data.activeTargets[] |
        [.labels.job, .health] |
        @tsv
      ' 2>/dev/null || echo "Unable to query targets"

    echo
}

show_storage_layout() {
    echo "--- STORAGE LAYOUT ---"

    sudo du -sh "$DATA_DIR"/* 2>/dev/null | \
      sort -h | tail -10 || echo "No TSDB contents yet"

    echo
}

show_disk_space() {
    echo "--- FILESYSTEM CAPACITY ---"

    df -h "$DATA_DIR" | tail -1 | \
      awk '{
        print "Filesystem: " $1
        print "Used:       " $3 " / " $2
        print "Usage:      " $5
        print "Available:  " $4
      }'

    echo
}

show_recent_activity() {
    echo "--- RECENT PROMETHEUS ACTIVITY ---"

    sudo journalctl \
      -u prometheus \
      --since "5 minutes ago" \
      --no-pager \
      -n 5 2>/dev/null | \
      sed 's/^/  /' || true

    echo
}

show_recommendations() {
    echo "--- RETENTION ASSESSMENT ---"

    storage_bytes=$(sudo du -sb "$DATA_DIR" 2>/dev/null | awk '{print $1}')

    storage_mb=$(( storage_bytes / 1024 / 1024 ))

    filesystem_percent=$(
        df -P "$DATA_DIR" | awk 'NR==2 {gsub("%","",$5); print $5}'
    )

    echo "Current TSDB size: ${storage_mb} MB"
    echo "Filesystem usage: ${filesystem_percent}%"

    if [ "$filesystem_percent" -ge 80 ]; then

        echo "CRITICAL: filesystem usage is above 80%."
        echo "Recommended actions:"
        echo "  - Reduce retention time"
        echo "  - Reduce retention size ceiling"
        echo "  - Reduce metric cardinality"
        echo "  - Increase persistent storage"

    elif [ "$filesystem_percent" -ge 65 ]; then

        echo "WARNING: storage usage should be monitored closely."
        echo "Review retention settings and metric growth."

    else

        echo "Storage capacity is currently healthy."

    fi

    echo
}

show_retention_test_series() {
    echo "--- SYNTHETIC RETENTION TEST ---"

    count=$(
        curl -fsSG \
          --data-urlencode 'query=count(retention_test_metric)' \
          http://localhost:9090/api/v1/query 2>/dev/null | \
          jq -r '.data.result[0].value[1] // "0"' 2>/dev/null
    )

    echo "Retention-test series currently visible: $count"
    echo
}

render_dashboard() {
    show_header
    show_key_metrics
    show_tsdb_health
    show_scrape_health
    show_storage_layout
    show_disk_space
    show_retention_test_series
    show_recent_activity
    show_recommendations
}

if [ "${1:-}" = "--once" ]; then

    render_dashboard

else

    interval="${1:-30}"

    while true; do
        render_dashboard
        echo "Next refresh in ${interval}s..."
        sleep "$interval"
    done

fi
