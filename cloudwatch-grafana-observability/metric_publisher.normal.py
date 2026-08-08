#!/usr/bin/env python3

import random
import time
from datetime import datetime, timezone

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

ENDPOINT = "http://127.0.0.1:4566"
REGION = "us-east-1"
INSTANCE_ID = "i-1234567890abcdef0"
INTERVAL_SECONDS = 5

cloudwatch = boto3.client(
    "cloudwatch",
    endpoint_url=ENDPOINT,
    region_name=REGION,
    aws_access_key_id="test",
    aws_secret_access_key="test",
    config=Config(
        retries={
            "max_attempts": 5,
            "mode": "standard",
        }
    ),
)


def wait_for_cloudwatch():
    attempt = 0

    while True:
        attempt += 1

        try:
            cloudwatch.list_metrics()
            print(
                f"{datetime.now(timezone.utc).isoformat()} "
                f"CloudWatch endpoint ready after attempt {attempt}",
                flush=True,
            )
            return

        except (BotoCoreError, ClientError, Exception) as exc:
            print(
                f"{datetime.now(timezone.utc).isoformat()} "
                f"CloudWatch unavailable: {exc}",
                flush=True,
            )

            time.sleep(5)


def publish():
    counter = 0

    while True:
        counter += 1

        cpu = round(random.uniform(15.0, 70.0), 2)
        memory = round(random.uniform(30.0, 78.0), 2)
        network_in = round(random.uniform(1000.0, 100000.0), 2)

        timestamp = datetime.now(timezone.utc)

        try:
            cloudwatch.put_metric_data(
                Namespace="AWS/EC2",
                MetricData=[
                    {
                        "MetricName": "CPUUtilization",
                        "Dimensions": [
                            {
                                "Name": "InstanceId",
                                "Value": INSTANCE_ID,
                            }
                        ],
                        "Timestamp": timestamp,
                        "Value": cpu,
                        "Unit": "Percent",
                    },
                    {
                        "MetricName": "NetworkIn",
                        "Dimensions": [
                            {
                                "Name": "InstanceId",
                                "Value": INSTANCE_ID,
                            }
                        ],
                        "Timestamp": timestamp,
                        "Value": network_in,
                        "Unit": "Bytes",
                    },
                ],
            )

            cloudwatch.put_metric_data(
                Namespace="System/Linux",
                MetricData=[
                    {
                        "MetricName": "MemoryUtilization",
                        "Dimensions": [
                            {
                                "Name": "InstanceId",
                                "Value": INSTANCE_ID,
                            }
                        ],
                        "Timestamp": timestamp,
                        "Value": memory,
                        "Unit": "Percent",
                    }
                ],
            )

            print(
                f"{timestamp.isoformat()} "
                f"sample={counter} "
                f"CPUUtilization={cpu}% "
                f"MemoryUtilization={memory}% "
                f"NetworkIn={network_in}B",
                flush=True,
            )

        except Exception as exc:
            print(
                f"{datetime.now(timezone.utc).isoformat()} "
                f"publish_error={exc}",
                flush=True,
            )

        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    wait_for_cloudwatch()
    publish()
