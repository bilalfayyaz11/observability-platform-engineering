#!/usr/bin/env python3

import os
import random
import socket
import uuid

import psutil
from flask import Flask, jsonify, request, Response
from prometheus_client import (
    CollectorRegistry,
    Counter,
    Gauge,
    generate_latest,
    CONTENT_TYPE_LATEST,
)


class NonCompliantApp:
    def __init__(self) -> None:
        self.registry = CollectorRegistry()
        self.app = Flask(__name__)

        self.create_metrics()
        self.register_routes()

    def create_metrics(self) -> None:
        """
        Intentionally bad metric design:
        - weak names
        - ambiguous units
        - unbounded labels
        """

        self.requests = Counter(
            "requests",
            "Bare request counter with no namespace",
            registry=self.registry,
        )

        self.http_requests = Counter(
            "http_requests",
            "Intentionally high-cardinality HTTP request counter",
            [
                "method",
                "endpoint",
                "status",
                "user_id",
                "session_id",
                "ip_address",
            ],
            registry=self.registry,
        )

        self.memory_usage = Gauge(
            "memory_usage",
            "Ambiguous memory gauge with no unit suffix",
            registry=self.registry,
        )

        self.disk_usage = Gauge(
            "disk_usage",
            "Ambiguous disk gauge with no unit suffix",
            registry=self.registry,
        )

    def update_resources(self) -> None:
        self.memory_usage.set(
            psutil.virtual_memory().used
        )

        self.disk_usage.set(
            psutil.disk_usage("/").used
        )

    def random_identity(self):
        user_id = str(
            request.args.get(
                "user_id",
                random.randint(1, 1000000),
            )
        )

        session_id = str(uuid.uuid4())

        ip_address = (
            f"10."
            f"{random.randint(0,255)}."
            f"{random.randint(0,255)}."
            f"{random.randint(1,254)}"
        )

        return user_id, session_id, ip_address

    def home(self) -> tuple:
        user_id, session_id, ip_address = self.random_identity()

        self.requests.inc()

        self.http_requests.labels(
            method=request.method,
            endpoint=request.path,
            status="200",
            user_id=user_id,
            session_id=session_id,
            ip_address=ip_address,
        ).inc()

        self.update_resources()

        return jsonify(
            {
                "service": "non-compliant",
                "hostname": socket.gethostname(),
                "user_id": user_id,
                "session_id": session_id,
            }
        ), 200

    def get_user(self, user_id: str) -> tuple:
        session_id = str(uuid.uuid4())

        ip_address = (
            f"172."
            f"{random.randint(16,31)}."
            f"{random.randint(0,255)}."
            f"{random.randint(1,254)}"
        )

        raw_endpoint = request.path

        self.requests.inc()

        self.http_requests.labels(
            method=request.method,
            endpoint=raw_endpoint,
            status="200",
            user_id=user_id,
            session_id=session_id,
            ip_address=ip_address,
        ).inc()

        self.update_resources()

        return jsonify(
            {
                "service": "non-compliant",
                "user_id": user_id,
            }
        ), 200

    def metrics(self):
        payload = generate_latest(self.registry)

        return Response(
            payload,
            mimetype=CONTENT_TYPE_LATEST,
        )

    def register_routes(self) -> None:
        self.app.add_url_rule(
            "/",
            "home",
            self.home,
            methods=["GET"],
        )

        self.app.add_url_rule(
            "/api/users/<user_id>",
            "get_user",
            self.get_user,
            methods=["GET"],
        )

        self.app.add_url_rule(
            "/metrics",
            "metrics",
            self.metrics,
            methods=["GET"],
        )


service = NonCompliantApp()

if __name__ == "__main__":
    service.app.run(
        host="127.0.0.1",
        port=5000,
        threaded=True,
    )
