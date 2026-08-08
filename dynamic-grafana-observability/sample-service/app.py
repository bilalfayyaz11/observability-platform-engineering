#!/usr/bin/env python3

import os
import random
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

from prometheus_client import Counter, Gauge, generate_latest, CONTENT_TYPE_LATEST


SERVICE = os.getenv("SERVICE_NAME", "unknown-service")
ENVIRONMENT = os.getenv("ENVIRONMENT", "unknown")
REGION = os.getenv("REGION", "unknown")
TEAM = os.getenv("TEAM", "unknown")


REQUESTS = Counter(
    "sample_http_requests_total",
    "Synthetic HTTP requests processed",
    ["service", "environment", "region", "team", "status"]
)

LATENCY = Gauge(
    "sample_request_latency_seconds",
    "Synthetic request latency",
    ["service", "environment", "region", "team"]
)

SERVICE_INFO = Gauge(
    "sample_service_info",
    "Metadata describing the synthetic service",
    ["service", "environment", "region", "team"]
)

SERVICE_INFO.labels(
    service=SERVICE,
    environment=ENVIRONMENT,
    region=REGION,
    team=TEAM
).set(1)


class Handler(BaseHTTPRequestHandler):

    def do_GET(self):

        if self.path == "/metrics":
            payload = generate_latest()

            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE_LATEST)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        latency = random.uniform(0.02, 0.5)
        status = random.choices(
            ["200", "500"],
            weights=[97, 3],
            k=1
        )[0]

        LATENCY.labels(
            service=SERVICE,
            environment=ENVIRONMENT,
            region=REGION,
            team=TEAM
        ).set(latency)

        REQUESTS.labels(
            service=SERVICE,
            environment=ENVIRONMENT,
            region=REGION,
            team=TEAM,
            status=status
        ).inc()

        time.sleep(latency / 20)

        body = (
            f"service={SERVICE} "
            f"environment={ENVIRONMENT} "
            f"region={REGION} "
            f"team={TEAM} "
            f"status={status}\n"
        ).encode()

        self.send_response(int(status))
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
