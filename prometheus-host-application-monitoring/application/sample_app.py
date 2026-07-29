#!/usr/bin/env python3

import logging
import random
import time

from prometheus_client import Counter, Gauge, start_http_server


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

requests_counter = Counter(
    "app_requests_total",
    "Total app requests",
)

temperature_gauge = Gauge(
    "app_temperature",
    "Current temperature",
)


def process_request() -> None:
    """Simulate processing one application request."""
    requests_counter.inc()


def update_temperature() -> None:
    """Set a simulated temperature between 20 and 30 degrees."""
    temperature_gauge.set(random.uniform(20.0, 30.0))


def main() -> None:
    """Start the metrics endpoint and continuously update metrics."""
    start_http_server(8000, addr="127.0.0.1")
    logging.info("Metrics server started on http://127.0.0.1:8000/metrics")

    while True:
        process_request()
        update_temperature()
        time.sleep(5)


if __name__ == "__main__":
    main()
