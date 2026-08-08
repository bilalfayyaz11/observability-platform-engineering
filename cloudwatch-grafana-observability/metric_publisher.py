#!/usr/bin/env python3

import random
import time
from datetime import datetime, timedelta, timezone

import boto3

ENDPOINT = "http://127.0.0.1:4566"
REGION = "us-east-1"
INSTANCE_ID = "i-1234567890abcdef0"

cloudwatch = boto3.client(
    "cloudwatch",
    endpoint_url=ENDPOINT,
    region_name=REGION,
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def dimensions():
    return [
        {
            "Name": "InstanceId",
            "Value": INSTANCE_ID,
        }
    ]


def wait_for_cloudwatch():
    while True:
        try:
            cloudwatch.list_metrics()
            print("CloudWatch endpoint ready", flush=True)
            return
        except Exception as exc:
            print(
                f"Waiting for CloudWatch: {exc}",
                flush=True,
            )
            time.sleep(2)


def backfill_high_cpu():
    now = datetime.now(timezone.utc)

    print(
        "Publishing sustained high-CPU history...",
        flush=True,
    )

    datapoints = []

    # 5 minutes of high CPU, one point every 5 seconds.
    for seconds_ago in range(300, 0, -5):

        datapoints.append(
            {
                "MetricName": "CPUUtilization",
                "Dimensions": dimensions(),
                "Timestamp": now - timedelta(
                    seconds=seconds_ago
                ),
                "Value": round(
                    random.uniform(85.0, 98.0),
                    2,
                ),
                "Unit": "Percent",
            }
        )

    # CloudWatch PutMetricData allows batches;
    # send in small chunks.
    for start in range(0, len(datapoints), 20):

        cloudwatch.put_metric_data(
            Namespace="AWS/EC2",
            MetricData=datapoints[start:start + 20],
        )

    print(
        f"High CPU history published: "
        f"{len(datapoints)} samples",
        flush=True,
    )


def publish_live():
    sample = 0

    while True:
        sample += 1

        now = datetime.now(timezone.utc)

        cpu = round(
            random.uniform(85.0, 98.0),
            2,
        )

        memory = round(
            random.uniform(40.0, 70.0),
            2,
        )

        network = round(
            random.uniform(1000.0, 100000.0),
            2,
        )

        cloudwatch.put_metric_data(
            Namespace="AWS/EC2",
            MetricData=[
                {
                    "MetricName": "CPUUtilization",
                    "Dimensions": dimensions(),
                    "Timestamp": now,
                    "Value": cpu,
                    "Unit": "Percent",
                },
                {
                    "MetricName": "NetworkIn",
                    "Dimensions": dimensions(),
                    "Timestamp": now,
                    "Value": network,
                    "Unit": "Bytes",
                },
            ],
        )

        cloudwatch.put_metric_data(
            Namespace="System/Linux",
            MetricData=[
                {
                    "MetricName": "MemoryUtilization",
                    "Dimensions": dimensions(),
                    "Timestamp": now,
                    "Value": memory,
                    "Unit": "Percent",
                }
            ],
        )

        print(
            f"{now.isoformat()} "
            f"sample={sample} "
            f"CPUUtilization={cpu}% "
            f"MemoryUtilization={memory}% "
            f"NetworkIn={network}B",
            flush=True,
        )

        time.sleep(5)


if __name__ == "__main__":
    wait_for_cloudwatch()
    backfill_high_cpu()
    publish_live()
