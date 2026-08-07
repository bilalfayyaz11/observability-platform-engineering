#!/usr/bin/env python3

import argparse
import random
from wsgiref.simple_server import make_server

from prometheus_client import (
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
    CONTENT_TYPE_LATEST,
)


class TrafficSimulator:
    def __init__(self, seed_rng: int) -> None:
        """Initialise counters and histogram state. seed_rng controls randomness."""

        self.rng = random.Random(seed_rng)
        self.registry = CollectorRegistry()

        self.requests = Counter(
            "app_http_requests",
            "Synthetic HTTP requests processed by the application",
            ["method", "status_code", "endpoint"],
            registry=self.registry,
        )

        self.duration = Histogram(
            "app_request_duration_seconds",
            "Synthetic application request latency",
            ["endpoint"],
            buckets=[0.05, 0.1, 0.25, 0.5, 1.0, 2.5],
            registry=self.registry,
        )

        self.sessions = Gauge(
            "app_active_sessions",
            "Synthetic active application sessions",
            registry=self.registry,
        )

        self.active_sessions = self.rng.randint(100, 300)
        self.sessions.set(self.active_sessions)

        self.endpoints = [
            "/",
            "/api/login",
            "/api/search",
            "/api/orders",
            "/api/profile",
        ]

    def tick(self) -> None:
        """Advance simulation by one step: increment counters, record observations, update gauge."""

        observations = self.rng.randint(8, 30)

        for _ in range(observations):
            endpoint = self.rng.choice(self.endpoints)

            method = self.rng.choices(
                ["GET", "POST"],
                weights=[0.75, 0.25],
                k=1,
            )[0]

            status_code = self.rng.choices(
                ["200", "201", "400", "404", "500"],
                weights=[0.70, 0.10, 0.08, 0.07, 0.05],
                k=1,
            )[0]

            request_increment = self.rng.randint(1, 5)

            self.requests.labels(
                method=method,
                status_code=status_code,
                endpoint=endpoint,
            ).inc(request_increment)

            latency = min(
                self.rng.lognormvariate(-1.6, 0.8),
                2.49,
            )

            self.duration.labels(
                endpoint=endpoint
            ).observe(latency)

        self.active_sessions += self.rng.randint(-20, 20)
        self.active_sessions = max(50, min(500, self.active_sessions))

        self.sessions.set(self.active_sessions)

    def get_registry(self):
        """Return the prometheus_client CollectorRegistry containing all metrics."""

        return self.registry


def make_app(simulator: TrafficSimulator, tick_interval_seconds: float):
    """
    Return a callable WSGI application that:
    - Calls simulator.tick() on every request to /metrics
    - Responds with the current registry output in text/plain; version=0.0.4 format
    - Returns 404 for all other paths
    """

    def app(environ, start_response):
        path = environ.get("PATH_INFO", "")

        if path != "/metrics":
            body = b"404 Not Found\n"

            start_response(
                "404 Not Found",
                [
                    ("Content-Type", "text/plain"),
                    ("Content-Length", str(len(body))),
                ],
            )

            return [body]

        simulator.tick()

        body = generate_latest(simulator.get_registry())

        start_response(
            "200 OK",
            [
                ("Content-Type", CONTENT_TYPE_LATEST),
                ("Content-Length", str(len(body))),
            ],
        )

        return [body]

    return app


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--port",
        type=int,
        required=True,
    )

    parser.add_argument(
        "--seed",
        type=int,
        required=True,
    )

    parser.add_argument(
        "--tick-interval",
        type=float,
        default=1.0,
    )

    args = parser.parse_args()

    simulator = TrafficSimulator(args.seed)

    application = make_app(
        simulator,
        args.tick_interval,
    )

    with make_server(
        "127.0.0.1",
        args.port,
        application,
    ) as server:

        print(
            f"Traffic simulator listening on 127.0.0.1:{args.port}",
            flush=True,
        )

        server.serve_forever()


if __name__ == "__main__":
    main()
