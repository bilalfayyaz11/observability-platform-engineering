#!/usr/bin/env bash

BASE_URL="http://127.0.0.1:8000"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-1}"

echo "Generating traffic against ${BASE_URL}"
echo "Press Ctrl+C to stop when running interactively."

while true; do
    curl \
      --connect-timeout 3 \
      --max-time 5 \
      --silent \
      --output /dev/null \
      "${BASE_URL}/"

    curl \
      --connect-timeout 3 \
      --max-time 5 \
      --silent \
      --output /dev/null \
      "${BASE_URL}/api/data"

    if (( RANDOM % 4 == 0 )); then
        curl \
          --connect-timeout 3 \
          --max-time 5 \
          --silent \
          --output /dev/null \
          "${BASE_URL}/api/error"
    fi

    sleep "$INTERVAL_SECONDS"
done
