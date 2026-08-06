#!/usr/bin/env python3

import random
import threading
import time
from http import HTTPStatus

from flask import Flask, jsonify
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    Summary,
    generate_latest,
)

app = Flask(__name__)

# Counter: cumulative values that increase.
http_requests_total = Counter(
    "demo_http_requests_total",
    "Total HTTP requests processed by the application",
    ["method", "endpoint", "status"],
)

http_errors_total = Counter(
    "demo_http_errors_total",
    "Total HTTP error responses",
    ["endpoint", "status"],
)

# Gauge: values that can increase or decrease.
active_requests = Gauge(
    "demo_active_requests",
    "Number of requests currently being processed",
)

cpu_usage_percent = Gauge(
    "demo_cpu_usage_percent",
    "Simulated application CPU utilization percentage",
)

memory_usage_bytes = Gauge(
    "demo_memory_usage_bytes",
    "Simulated application memory usage in bytes",
)

queue_depth = Gauge(
    "demo_queue_depth",
    "Simulated number of queued work items",
)

# Histogram: observations distributed across cumulative buckets.
request_duration_seconds = Histogram(
    "demo_http_request_duration_seconds",
    "HTTP request processing duration",
    ["endpoint"],
    buckets=(0.1, 0.25, 0.5, 1.0, 1.5, 2.5, 5.0),
)

response_size_bytes = Histogram(
    "demo_http_response_size_bytes",
    "HTTP response size",
    ["endpoint"],
    buckets=(100, 250, 500, 1000, 2500, 5000, 10000),
)

# Summary: client-side observation count and sum.
processing_duration_seconds = Summary(
    "demo_processing_duration_seconds",
    "Time spent processing application work",
    ["operation"],
)


def update_simulated_gauges() -> None:
    while True:
        cpu_usage_percent.set(random.uniform(15.0, 90.0))
        memory_usage_bytes.set(random.randint(50_000_000, 250_000_000))
        queue_depth.set(random.randint(0, 30))
        time.sleep(2)


def observe_request(
    endpoint: str,
    duration: float,
    response_body: str,
    status: int,
) -> None:
    request_duration_seconds.labels(endpoint=endpoint).observe(duration)
    response_size_bytes.labels(endpoint=endpoint).observe(
        len(response_body.encode("utf-8"))
    )
    http_requests_total.labels(
        method="GET",
        endpoint=endpoint,
        status=str(status),
    ).inc()


@app.route("/")
def home():
    endpoint = "/"
    duration = random.uniform(0.05, 0.8)

    with active_requests.track_inprogress():
        time.sleep(duration)
        response_body = "Prometheus metric-type demonstration service"
        observe_request(
            endpoint,
            duration,
            response_body,
            HTTPStatus.OK,
        )

    return response_body, HTTPStatus.OK


@app.route("/api/data")
def api_data():
    endpoint = "/api/data"
    duration = random.uniform(0.2, 1.5)

    with active_requests.track_inprogress():
        with processing_duration_seconds.labels(
            operation="data_generation"
        ).time():
            time.sleep(duration)

        response = {
            "status": "success",
            "values": [random.randint(1, 100) for _ in range(5)],
        }
        response_body = str(response)

        observe_request(
            endpoint,
            duration,
            response_body,
            HTTPStatus.OK,
        )

    return jsonify(response), HTTPStatus.OK


@app.route("/api/error")
def api_error():
    endpoint = "/api/error"
    duration = random.uniform(0.05, 0.4)

    with active_requests.track_inprogress():
        time.sleep(duration)
        response_body = "Simulated internal server error"

        http_errors_total.labels(
            endpoint=endpoint,
            status=str(HTTPStatus.INTERNAL_SERVER_ERROR),
        ).inc()

        observe_request(
            endpoint,
            duration,
            response_body,
            HTTPStatus.INTERNAL_SERVER_ERROR,
        )

    return response_body, HTTPStatus.INTERNAL_SERVER_ERROR


@app.route("/metrics")
def metrics():
    return generate_latest(), HTTPStatus.OK, {
        "Content-Type": CONTENT_TYPE_LATEST
    }


def main() -> None:
    metrics_thread = threading.Thread(
        target=update_simulated_gauges,
        daemon=True,
    )
    metrics_thread.start()

    app.run(
        host="0.0.0.0",
        port=8000,
        debug=False,
        threaded=True,
    )


if __name__ == "__main__":
    main()
