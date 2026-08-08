#!/usr/bin/env python3

import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


LOG_FILE = Path("/var/lib/alert-webhook/events.jsonl")


class AlertWebhookHandler(BaseHTTPRequestHandler):

    def _send_json(self, status_code, payload):
        encoded = json.dumps(payload).encode("utf-8")

        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()

        self.wfile.write(encoded)


    def do_GET(self):

        if self.path == "/health":
            self._send_json(
                200,
                {
                    "status": "ok",
                    "service": "alert-webhook"
                }
            )
            return

        self._send_json(
            404,
            {
                "status": "not_found"
            }
        )


    def do_POST(self):

        try:
            length = int(
                self.headers.get(
                    "Content-Length",
                    "0"
                )
            )

            body = self.rfile.read(length)

            payload = json.loads(
                body.decode("utf-8")
            )

        except Exception as exc:

            self._send_json(
                400,
                {
                    "status": "invalid_json",
                    "error": str(exc)
                }
            )
            return


        received_at = datetime.now(
            timezone.utc
        ).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )


        alerts = payload.get(
            "alerts",
            []
        )


        if not alerts:

            event = {
                "received_at": received_at,
                "endpoint": self.path,
                "alertname": "unknown",
                "status": payload.get(
                    "status",
                    "unknown"
                ),
                "severity": "unknown",
                "alert_type": "unknown",
                "instance": "unknown",
                "summary": "none"
            }

            self._write_event(event)


        for alert in alerts:

            labels = alert.get(
                "labels",
                {}
            )

            annotations = alert.get(
                "annotations",
                {}
            )

            event = {
                "received_at": received_at,
                "endpoint": self.path,
                "alertname": labels.get(
                    "alertname",
                    "unknown"
                ),
                "status": alert.get(
                    "status",
                    payload.get(
                        "status",
                        "unknown"
                    )
                ),
                "severity": labels.get(
                    "severity",
                    "unknown"
                ),
                "alert_type": labels.get(
                    "alert_type",
                    "unknown"
                ),
                "instance": labels.get(
                    "instance",
                    "unknown"
                ),
                "summary": annotations.get(
                    "summary",
                    "none"
                )
            }

            self._write_event(event)


        self._send_json(
            200,
            {
                "status": "ok",
                "received": len(alerts)
            }
        )


    def _write_event(self, event):

        line = json.dumps(
            event,
            sort_keys=True
        )

        print(
            line,
            flush=True
        )

        with LOG_FILE.open(
            "a",
            encoding="utf-8"
        ) as handle:

            handle.write(
                line + "\n"
            )


    def log_message(self, fmt, *args):
        return


def main():

    server = ThreadingHTTPServer(
        (
            "127.0.0.1",
            5001
        ),
        AlertWebhookHandler
    )

    print(
        "alert-webhook listening on 127.0.0.1:5001",
        flush=True
    )

    server.serve_forever()


if __name__ == "__main__":
    main()
