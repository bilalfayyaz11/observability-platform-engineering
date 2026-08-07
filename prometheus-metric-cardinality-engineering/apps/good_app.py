#!/usr/bin/env python3

import os
import random
import time

import psutil
from flask import Flask, jsonify, request, Response
from prometheus_client import (
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    Info,
    generate_latest,
    CONTENT_TYPE_LATEST,
)


class CompliantApp:
    def __init__(self) -> None:
        self.registry = CollectorRegistry()
        self.app = Flask(__name__)

        self.started_at = time.monotonic()
        self.active_user_count = 0

        self.create_metrics()
        self.register_routes()

    def create_metrics(self) -> None:
        self.build_info = Info(
            "myapp_build",
            "Application build information",
            registry=self.registry,
        )

        self.build_info.info(
            {
                "version": "1.0.0",
                "runtime": "python",
            }
        )

        self.requests = Counter(
            "myapp_http_requests",
            "HTTP requests processed",
            [
                "method",
                "handler",
                "status_code",
            ],
            registry=self.registry,
        )

        self.duration = Histogram(
            "myapp_http_request_duration_seconds",
            "HTTP request duration in seconds",
            [
                "method",
                "handler",
            ],
            buckets=[
                0.005,
                0.01,
                0.025,
                0.05,
                0.1,
                0.25,
                0.5,
                1.0,
                2.5,
                5.0,
            ],
            registry=self.registry,
        )

        self.active_users = Gauge(
            "myapp_active_users",
            "Current active synthetic users",
            registry=self.registry,
        )

        self.memory_usage_ratio = Gauge(
            "myapp_memory_usage_ratio",
            "Host memory usage ratio between zero and one",
            registry=self.registry,
        )

        self.disk_usage_bytes = Gauge(
            "myapp_disk_usage_bytes",
            "Host disk bytes currently used",
            registry=self.registry,
        )

        self.errors = Counter(
            "myapp_errors",
            "Application errors by bounded category",
            ["error_type"],
            registry=self.registry,
        )

    def update_system_metrics(self) -> None:
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage("/")

        self.memory_usage_ratio.set(
            memory.percent / 100.0
        )

        self.disk_usage_bytes.set(
            disk.used
        )

        self.active_user_count += random.randint(-2, 3)
        self.active_user_count = max(
            1,
            min(250, self.active_user_count),
        )

        self.active_users.set(
            self.active_user_count
        )

    def record_request(
        self,
        handler: str,
        method: str,
        status_code: int,
        duration_seconds: float
    ) -> None:

        self.requests.labels(
            method=method,
            handler=handler,
            status_code=str(status_code),
        ).inc()

        self.duration.labels(
            method=method,
            handler=handler,
        ).observe(duration_seconds)

    def home(self) -> tuple:
        started = time.perf_counter()

        self.update_system_metrics()

        payload = {
            "service": "compliant",
            "status": "ok",
        }

        duration = time.perf_counter() - started

        self.record_request(
            handler="home",
            method=request.method,
            status_code=200,
            duration_seconds=duration,
        )

        return jsonify(payload), 200

    def get_user(self, user_id: int) -> tuple:
        started = time.perf_counter()

        self.update_system_metrics()

        if user_id < 1 or user_id > 9999:
            self.errors.labels(
                error_type="validation"
            ).inc()

            duration = time.perf_counter() - started

            self.record_request(
                handler="get_user",
                method=request.method,
                status_code=400,
                duration_seconds=duration,
            )

            return jsonify(
                {
                    "error": "user_id must be between 1 and 9999"
                }
            ), 400

        duration = time.perf_counter() - started

        self.record_request(
            handler="get_user",
            method=request.method,
            status_code=200,
            duration_seconds=duration,
        )

        return jsonify(
            {
                "service": "compliant",
                "user_id": user_id,
            }
        ), 200

    def health(self) -> tuple:
        started = time.perf_counter()

        uptime_seconds = (
            time.monotonic() - self.started_at
        )

        duration = time.perf_counter() - started

        self.record_request(
            handler="health",
            method=request.method,
            status_code=200,
            duration_seconds=duration,
        )

        return jsonify(
            {
                "status": "healthy",
                "uptime_seconds": uptime_seconds,
            }
        ), 200

    def simulate_error(self) -> tuple:
        started = time.perf_counter()

        self.errors.labels(
            error_type="synthetic"
        ).inc()

        duration = time.perf_counter() - started

        self.record_request(
            handler="simulate_error",
            method=request.method,
            status_code=500,
            duration_seconds=duration,
        )

        return jsonify(
            {
                "status": "synthetic-error"
            }
        ), 500

    def metrics(self):
        self.update_system_metrics()

        payload = generate_latest(
            self.registry
        )

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
            "/api/users/<int:user_id>",
            "get_user",
            self.get_user,
            methods=["GET"],
        )

        self.app.add_url_rule(
            "/api/health",
            "health",
            self.health,
            methods=["GET"],
        )

        self.app.add_url_rule(
            "/api/simulate-error",
            "simulate_error",
            self.simulate_error,
            methods=["GET"],
        )

        self.app.add_url_rule(
            "/metrics",
            "metrics",
            self.metrics,
            methods=["GET"],
        )


service = CompliantApp()

if __name__ == "__main__":
    service.app.run(
        host="127.0.0.1",
        port=5001,
        threaded=True,
    )
