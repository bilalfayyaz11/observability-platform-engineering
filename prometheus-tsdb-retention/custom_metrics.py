#!/usr/bin/env python3

import http.server
import random
import socketserver
import threading

PORT = 8080

disk_io_total = 0
network_bytes_total = 0
request_count = 0
request_sum = 0.0

lock = threading.Lock()


class MetricsHandler(http.server.BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        return

    def do_GET(self):
        global disk_io_total
        global network_bytes_total
        global request_count
        global request_sum

        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return

        with lock:
            cpu_usage = random.uniform(10, 90)
            memory_usage = random.uniform(20, 80)

            disk_io_total += random.randint(20, 150)
            network_bytes_total += random.randint(1000, 10000)

            new_requests = random.randint(10, 30)
            request_count += new_requests
            request_sum += random.uniform(0.5, 5.0)

            bucket_01 = int(request_count * 0.25)
            bucket_05 = int(request_count * 0.60)
            bucket_10 = int(request_count * 0.85)
            bucket_inf = request_count

            metrics = f"""# HELP custom_cpu_usage CPU usage percentage
# TYPE custom_cpu_usage gauge
custom_cpu_usage {cpu_usage:.2f}

# HELP custom_memory_usage Memory usage percentage
# TYPE custom_memory_usage gauge
custom_memory_usage {memory_usage:.2f}

# HELP custom_disk_io Disk I/O operations
# TYPE custom_disk_io counter
custom_disk_io {disk_io_total}

# HELP custom_network_bytes Network bytes transferred
# TYPE custom_network_bytes counter
custom_network_bytes {network_bytes_total}

# HELP custom_request_duration Request duration in seconds
# TYPE custom_request_duration histogram
custom_request_duration_bucket{{le="0.1"}} {bucket_01}
custom_request_duration_bucket{{le="0.5"}} {bucket_05}
custom_request_duration_bucket{{le="1.0"}} {bucket_10}
custom_request_duration_bucket{{le="+Inf"}} {bucket_inf}
custom_request_duration_sum {request_sum:.4f}
custom_request_duration_count {request_count}
"""

        body = metrics.encode()

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


with socketserver.TCPServer(("", PORT), MetricsHandler) as httpd:
    print(f"Serving Prometheus metrics on port {PORT}", flush=True)
    httpd.serve_forever()
