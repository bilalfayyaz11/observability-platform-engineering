#!/usr/bin/env python3

import random
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

from prometheus_client import Histogram, generate_latest, CONTENT_TYPE_LATEST


REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "Synthetic HTTP request duration in seconds",
    buckets=(0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)

RESPONSE_SIZE = Histogram(
    "http_response_size_bytes",
    "Synthetic HTTP response size in bytes",
    buckets=(100, 500, 1000, 5000, 10000, 50000),
)


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

        duration = random.uniform(0.1, 5.0)
        response_size = random.randint(100, 10000)

        REQUEST_DURATION.observe(duration)
        RESPONSE_SIZE.observe(response_size)

        time.sleep(duration / 100)

        body = (
            f"request_duration={duration:.3f}s "
            f"response_size={response_size}B\n"
        ).encode()

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


if __name__ == "__main__":

    for _ in range(200):
        REQUEST_DURATION.observe(random.uniform(0.1, 5.0))
        RESPONSE_SIZE.observe(random.randint(100, 10000))

    print("Metrics generator listening on :8000", flush=True)

    HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
