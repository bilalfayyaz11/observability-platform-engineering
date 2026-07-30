#!/usr/bin/env python3

import logging
import random
import time

logging.basicConfig(
    filename="/home/ubuntu/app.log",
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

messages = [
    ("INFO", "User login successful"),
    ("INFO", "Database connection established"),
    ("INFO", "Background job completed"),
    ("INFO", "Order processed successfully"),
    ("WARNING", "High memory usage detected"),
    ("WARNING", "Slow database query"),
    ("WARNING", "API response exceeded threshold"),
    ("ERROR", "Failed to connect to external API"),
    ("ERROR", "Database timeout"),
    ("ERROR", "Authentication failure")
]

for i in range(50):

    level, message = random.choice(messages)

    if level == "INFO":
        logging.info(message)

    elif level == "WARNING":
        logging.warning(message)

    else:
        logging.error(message)

    time.sleep(random.uniform(0.5, 2.0))

print("Finished generating logs.")
