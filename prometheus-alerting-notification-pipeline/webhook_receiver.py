#!/usr/bin/env python3

from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import logging
import datetime

HOST = "127.0.0.1"
PORT = 8080
LOG_FILE = Path("/home/ubuntu/prometheus-alerting-engineering/webhook_alerts.log")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)


class WebhookHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        logging.info(
            "%s - %s",
            self.address_string(),
            format % args
        )

    def do_POST(self):
        try:
            content_length = int(
                self.headers.get("Content-Length", "0")
            )

            raw_body = self.rfile.read(content_length)

            payload = json.loads(
                raw_body.decode("utf-8")
            )

            timestamp = datetime.datetime.now(
                datetime.timezone.utc
            ).isoformat()

            record = {
                "received_at": timestamp,
                "path": self.path,
                "payload": payload
            }

            with LOG_FILE.open("a", encoding="utf-8") as fh:
                fh.write(
                    json.dumps(record, separators=(",", ":"))
                    + "\n"
                )

            alerts = payload.get("alerts", [])

            print(
                f"Received notification with {len(alerts)} alert(s)",
                flush=True
            )

            for alert in alerts:
                labels = alert.get("labels", {})
                annotations = alert.get("annotations", {})

                print(
                    "ALERT"
                    f" name={labels.get('alertname', 'unknown')}"
                    f" status={alert.get('status', 'unknown')}"
                    f" severity={labels.get('severity', 'unknown')}"
                    f" instance={labels.get('instance', 'unknown')}"
                    f" summary={annotations.get('summary', '')}",
                    flush=True
                )

            response = json.dumps(
                {
                    "status": "accepted",
                    "alerts_received": len(alerts)
                }
            ).encode("utf-8")

            self.send_response(200)
            self.send_header(
                "Content-Type",
                "application/json"
            )
            self.send_header(
                "Content-Length",
                str(len(response))
            )
            self.end_headers()

            self.wfile.write(response)

        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"invalid json")

        except Exception as exc:
            logging.exception(
                "Webhook processing failure: %s",
                exc
            )

            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"internal error")


if __name__ == "__main__":
    LOG_FILE.touch(exist_ok=True)

    server = HTTPServer(
        (HOST, PORT),
        WebhookHandler
    )

    print(
        f"Webhook receiver listening on http://{HOST}:{PORT}",
        flush=True
    )

    server.serve_forever()
