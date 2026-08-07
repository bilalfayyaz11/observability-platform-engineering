#!/usr/bin/env python3

from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from prometheus_client import (
    Counter,
    Gauge,
    CollectorRegistry,
    generate_latest,
    CONTENT_TYPE_LATEST,
)
import threading
import time


registry = CollectorRegistry()

deployments_total = Counter(
    "cicd_deployments_total",
    "Total deployment attempts",
    ["result"],
    registry=registry,
)

deployment_duration_seconds = Gauge(
    "cicd_last_deployment_duration_seconds",
    "Duration of the most recent deployment",
    registry=registry,
)

deployment_success_ratio = Gauge(
    "cicd_deployment_success_ratio",
    "Current deployment success ratio",
    registry=registry,
)

deployment_in_progress = Gauge(
    "cicd_deployment_in_progress",
    "Whether a deployment is currently in progress",
    registry=registry,
)

state_lock = threading.Lock()

success_count = 0
failure_count = 0


def refresh_ratio():
    global success_count, failure_count

    total = success_count + failure_count

    ratio = (
        success_count / total
        if total > 0
        else 1.0
    )

    deployment_success_ratio.set(ratio)


class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        return

    def do_GET(self):

        parsed = urlparse(self.path)

        if parsed.path == "/health":

            body = b'{"status":"ok"}\n'

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if parsed.path == "/metrics":

            body = generate_latest(registry)

            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE_LATEST)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if parsed.path == "/simulate":

            query = parse_qs(parsed.query)

            result = query.get("result", ["success"])[0]
            duration = float(
                query.get("duration", ["1.0"])[0]
            )

            if result not in {"success", "failure"}:

                self.send_response(400)
                self.end_headers()
                self.wfile.write(
                    b'{"error":"result must be success or failure"}\n'
                )
                return

            global success_count, failure_count

            with state_lock:

                deployment_in_progress.set(1)

                time.sleep(
                    min(duration, 2.0)
                )

                deployment_duration_seconds.set(duration)

                if result == "success":
                    success_count += 1
                else:
                    failure_count += 1

                deployments_total.labels(
                    result=result
                ).inc()

                refresh_ratio()

                deployment_in_progress.set(0)

            body = (
                f'{{"result":"{result}","duration":{duration}}}\n'
            ).encode()

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_response(404)
        self.end_headers()


if __name__ == "__main__":

    refresh_ratio()

    server = ThreadingHTTPServer(
        ("127.0.0.1", 8081),
        Handler,
    )

    server.serve_forever()
