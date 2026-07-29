#!/usr/bin/env python3

from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
import json


class WebhookHandler(BaseHTTPRequestHandler):

    def do_POST(self):

        try:

            length = int(
                self.headers.get(
                    "Content-Length",
                    "0"
                )
            )

            body = self.rfile.read(length)

            payload = json.loads(body.decode("utf-8"))

            print()
            print("=" * 70)
            print(f"Alert received: {datetime.now().isoformat()}")
            print("=" * 70)

            for alert in payload.get("alerts", []):

                labels = alert.get("labels", {})
                annotations = alert.get("annotations", {})

                print(f"Status      : {alert.get('status')}")
                print(f"Alert       : {labels.get('alertname')}")
                print(f"Severity    : {labels.get('severity')}")
                print(f"Instance    : {labels.get('instance')}")
                print(f"Summary     : {annotations.get('summary')}")
                print(f"Description : {annotations.get('description')}")
                print("-" * 70)

        except Exception as exc:
            print(f"Webhook processing error: {exc}")

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, *args):
        return


if __name__ == "__main__":

    server = HTTPServer(
        ("127.0.0.1", 5001),
        WebhookHandler
    )

    print("Webhook receiver listening on http://127.0.0.1:5001/webhook")

    server.serve_forever()
