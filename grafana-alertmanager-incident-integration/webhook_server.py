#!/usr/bin/env python3

import json
from datetime import datetime, timezone
from pathlib import Path

from flask import Flask, jsonify, request

app = Flask(__name__)

LOG_PATH = Path("/var/log/alert-webhook/alerts.log")


@app.post("/webhook")
def webhook():
    payload = request.get_json(silent=True) or {}

    timestamp = datetime.now(timezone.utc).isoformat()

    entry = {
        "received_at": timestamp,
        "status": payload.get("status"),
        "receiver": payload.get("receiver"),
        "groupLabels": payload.get("groupLabels", {}),
        "commonLabels": payload.get("commonLabels", {}),
        "alerts": payload.get("alerts", []),
    }

    with LOG_PATH.open("a") as handle:
        handle.write(json.dumps(entry) + "\n")

    print(json.dumps(entry, indent=2), flush=True)

    return jsonify(
        {
            "status": "received",
            "received_at": timestamp
        }
    ), 200


@app.get("/health")
def health():
    return jsonify({"status": "healthy"}), 200


if __name__ == "__main__":
    app.run(
        host="127.0.0.1",
        port=5001,
        debug=False
    )
