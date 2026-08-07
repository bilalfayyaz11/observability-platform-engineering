#!/usr/bin/env python3

import http.server
import socketserver
import sys
import random

PORT = int(sys.argv[1])
GENERATOR = sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        return

    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return

        lines = [
            "# HELP retention_test_metric Synthetic metric for TSDB retention testing",
            "# TYPE retention_test_metric gauge",
        ]

        for i in range(500):
            value = random.uniform(0, 100)

            lines.append(
                f'retention_test_metric{{generator="{GENERATOR}",series="{i}"}} {value}'
            )

        body = ("\n".join(lines) + "\n").encode()

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


with socketserver.TCPServer(("", PORT), Handler) as server:
    print(
        f"Generator {GENERATOR} listening on port {PORT}",
        flush=True,
    )
    server.serve_forever()
