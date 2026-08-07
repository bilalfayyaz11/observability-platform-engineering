#!/usr/bin/env python3

from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from datetime import datetime, timezone
import json

LOG_FILE = Path("/var/lib/cicd-webhook/alerts.jsonl")


class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        return

    def do_GET(self):

        if self.path == "/health":

            body = b'{"status":"ok"}\n'

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        else:

            self.send_response(404)
            self.end_headers()

    def do_POST(self):

        if self.path != "/webhook":
            self.send_response(404)
            self.end_headers()
            return

        try:

            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)

            payload = json.loads(raw.decode("utf-8"))

            record = {
                "received_at": datetime.now(timezone.utc).isoformat(),
                "payload": payload
            }

            with LOG_FILE.open("a", encoding="utf-8") as fh:
                fh.write(json.dumps(record, separators=(",", ":")) + "\n")

            response = b'{"status":"received"}\n'

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)

        except Exception as exc:

            response = json.dumps({
                "status": "error",
                "message": str(exc)
            }).encode() + b"\n"

            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)


if __name__ == "__main__":

    server = ThreadingHTTPServer(
        ("127.0.0.1", 5001),
        Handler
    )

    server.serve_forever()
