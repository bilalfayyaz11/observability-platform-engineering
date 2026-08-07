# Kubernetes Native Prometheus Observability

## What This Does

This implementation builds a Kubernetes-native Prometheus monitoring platform inside a Minikube cluster using manually authored manifests rather than a pre-packaged monitoring chart.

Prometheus uses Kubernetes service discovery and RBAC to collect control-plane, kubelet, cAdvisor, workload, kube-state, and host-level metrics without relying on static target addresses. Node Exporter runs as a DaemonSet, kube-state-metrics exposes Kubernetes object state, and annotated application pods are automatically discovered by Prometheus.

A standalone shell utility validates the complete observability path by managing its own Prometheus port-forward and querying live cluster state, CPU, memory, and workload metrics through the Prometheus HTTP API.

## Architecture

    ┌────────────────────────────────────────────────────────────────────┐
    │                           Minikube Cluster                         │
    │                                                                    │
    │  ┌──────────────────────── monitoring ──────────────────────────┐   │
    │  │                                                             │   │
    │  │  ┌───────────────────────────────────────────────────────┐  │   │
    │  │  │                  Prometheus                           │  │   │
    │  │  │                                                       │  │   │
    │  │  │  Kubernetes Service Discovery                         │  │   │
    │  │  │  PromQL Engine                                        │  │   │
    │  │  │  TSDB                                                  │  │   │
    │  │  └───────────────┬───────────────────────────────────────┘  │   │
    │  │                  │                                          │   │
    │  │       ┌──────────┼─────────────┬──────────────┐             │   │
    │  │       │          │             │              │             │   │
    │  │       ▼          ▼             ▼              ▼             │   │
    │  │   Kubelet     cAdvisor    kube-state-     Node Exporter    │   │
    │  │   Metrics     Metrics     metrics         DaemonSet         │   │
    │  │                              │                │             │   │
    │  │                              │                │             │   │
    │  └──────────────────────────────┼────────────────┼─────────────┘   │
    │                                 │                │                 │
    │                                 │                │                 │
    │  ┌──────────────── monitoring-demo ──────────────┼─────────────┐   │
    │  │                                              │             │   │
    │  │  Nginx Pod 1 + Exporter                      │             │   │
    │  │  Nginx Pod 2 + Exporter                      │             │   │
    │  │  Nginx Pod 3 + Exporter                      │             │   │
    │  │                                              │             │   │
    │  │  prometheus.io/scrape annotations            │             │   │
    │  └──────────────────────────────────────────────┼─────────────┘   │
    │                                                 │                 │
    └─────────────────────────────────────────────────┼─────────────────┘
                                                      │
                                                      │
                                   kubectl port-forward
                                                      │
                                                      ▼
                                        ┌───────────────────────┐
                                        │   cluster-report.sh   │
                                        │                       │
                                        │ Prometheus HTTP API   │
                                        │ PromQL validation     │
                                        │ Human-readable output │
                                        └───────────────────────┘


## Prerequisites

- Ubuntu Linux
- Docker Engine
- Docker access for the current user
- kubectl
- Minikube
- curl
- jq
- Git
- Minimum 2 CPUs available to Minikube
- Minimum 4 GiB memory available to Minikube
- Outbound access to Kubernetes container registries


## Cluster Setup

Start Minikube using the Docker driver:

    minikube start \
      --driver=docker \
      --cpus=2 \
      --memory=4096

Verify cluster health:

    minikube status

    kubectl cluster-info

    kubectl get nodes

The node should report:

    Ready


## Prometheus RBAC

Prometheus runs using a dedicated Kubernetes ServiceAccount.

Its ClusterRole grants read access to:

- nodes
- node proxy endpoints
- pods
- services
- endpoints
- namespaces
- Kubernetes metrics endpoints

Prometheus uses these permissions to dynamically discover and scrape cluster resources.


## Prometheus Service Discovery

The configuration contains dedicated scrape jobs for:

### Prometheus

Self-monitoring of the Prometheus server.

### Kubernetes Nodes

Discovers Kubernetes nodes and retrieves kubelet metrics through the Kubernetes API server proxy.

### Kubernetes cAdvisor

Collects container-level CPU, memory, filesystem, and runtime metrics exposed by the kubelet cAdvisor endpoint.

### Kubernetes Pods

Uses Kubernetes pod discovery and annotations:

    prometheus.io/scrape: "true"

to automatically determine which workloads should be monitored.

### kube-state-metrics

Collects Kubernetes object-state information including:

- node metadata
- pod state
- namespaces
- Deployments
- ReplicaSets
- DaemonSets
- StatefulSets
- resource objects

### Node Exporter

Discovers the Node Exporter Service through Kubernetes endpoint discovery and collects Linux host-level metrics.


## Node Exporter

Node Exporter runs as a DaemonSet so every Kubernetes node receives exactly one exporter instance.

Host paths mounted read-only include:

    /proc
    /sys
    /

Node Exporter is configured to interpret the mounted paths as its host filesystem sources.

This provides hardware, filesystem, CPU, memory, kernel, and operating-system metrics for each node.


## Workload Instrumentation

The demonstration workload consists of three Nginx replicas.

Each pod includes:

- Nginx container
- Nginx Prometheus Exporter sidecar
- CPU requests and limits
- memory requests and limits
- Prometheus discovery annotations

Prometheus automatically discovers the exporter endpoint through Kubernetes pod metadata rather than a static IP address.


## Why kube-state-metrics Is Included

Several useful Kubernetes metrics are not exported by the kubelet or cAdvisor.

Examples include:

    kube_node_info
    kube_pod_info
    kube_pod_status_phase

These are supplied by kube-state-metrics.

Including kube-state-metrics makes it possible to query Kubernetes object state alongside runtime resource metrics.


## How to Reproduce

Apply the primary monitoring stack:

    kubectl apply -f monitoring-stack.yaml

Wait for Prometheus:

    kubectl rollout status \
      deployment/prometheus-deployment \
      -n monitoring

Wait for kube-state-metrics:

    kubectl rollout status \
      deployment/kube-state-metrics \
      -n monitoring

Wait for the instrumented workload:

    kubectl rollout status \
      deployment/monitoring-demo-nginx \
      -n monitoring-demo

Apply Node Exporter:

    kubectl apply -f node-exporter.yaml

Verify DaemonSet rollout:

    kubectl rollout status \
      daemonset/node-exporter \
      -n monitoring

Restart Prometheus after configuration changes:

    kubectl rollout restart \
      deployment/prometheus-deployment \
      -n monitoring

Verify rollout:

    kubectl rollout status \
      deployment/prometheus-deployment \
      -n monitoring


## Verify Prometheus Targets

Start a temporary port-forward:

    kubectl port-forward \
      -n monitoring \
      svc/prometheus-service \
      9090:9090

Query active targets:

    curl -fsSL \
      http://127.0.0.1:9090/api/v1/targets | \
      jq -r '.data.activeTargets[] |
      [.labels.job, .health, .scrapeUrl] | @tsv'

Healthy targets should include:

- prometheus
- kubernetes-nodes
- kubernetes-cadvisor
- kubernetes-pods
- kube-state-metrics
- node-exporter


## Cluster Observability Report

Run:

    chmod +x cluster-report.sh
    ./cluster-report.sh

The utility automatically:

1. Starts a local kubectl port-forward
2. Waits until Prometheus becomes ready
3. Executes five PromQL queries
4. Validates the Prometheus API response status
5. Rejects empty query results
6. Formats the metric values
7. Terminates the port-forward before exiting


## PromQL Queries

### Cluster Nodes

    count(kube_node_info)

Reports the number of Kubernetes nodes represented by kube-state-metrics.


### Running Pods

    count(kube_pod_status_phase{phase="Running"})

Reports pods currently in the Running phase.


### Demo Namespace Pods

    count(kube_pod_info{namespace="monitoring-demo"})

Reports pods belonging to the instrumented workload namespace.


### Highest Pod CPU Rate

    topk(
      1,
      rate(
        container_cpu_usage_seconds_total{pod!=""}[5m]
      )
    )

Identifies the container workload producing the highest recent CPU consumption rate.


### Highest Pod Memory Usage

    topk(
      1,
      container_memory_usage_bytes{pod!=""}
    )

Identifies the workload currently using the most container memory.


## Tools Used

- Kubernetes
- Minikube
- Docker
- kubectl
- Prometheus
- PromQL
- kube-state-metrics
- Node Exporter
- cAdvisor
- Kubernetes RBAC
- Kubernetes Service Discovery
- ConfigMaps
- ServiceAccounts
- ClusterRoles
- ClusterRoleBindings
- Deployments
- DaemonSets
- Services
- NodePort
- Nginx
- Nginx Prometheus Exporter
- Bash
- curl
- jq


## Key Skills Demonstrated

- Kubernetes-native observability architecture
- Prometheus deployment without Helm
- Kubernetes RBAC design
- Kubernetes ServiceAccount security
- Dynamic Kubernetes service discovery
- kubelet metric scraping
- cAdvisor container monitoring
- annotation-driven workload discovery
- kube-state-metrics integration
- Node Exporter DaemonSet deployment
- host filesystem metric collection
- Prometheus endpoint discovery
- PromQL
- Kubernetes API proxying
- ConfigMap-driven monitoring configuration
- resource requests and limits
- sidecar-based workload instrumentation
- API-driven observability validation
- shell lifecycle and signal handling
- automated port-forward management


## Real-World Use Case

Platform Engineering, SRE, DevOps, and AIOps teams require visibility into both Kubernetes object state and actual workload resource consumption. Prometheus service discovery allows monitoring systems to adapt automatically as pods, services, and nodes appear or disappear. Combining kube-state-metrics, kubelet metrics, cAdvisor, Node Exporter, and instrumented application endpoints provides multiple layers of telemetry needed for incident investigation, capacity management, reliability engineering, autoscaling decisions, anomaly detection, and production operations.


## Lessons Learned

- Kubernetes monitoring requires multiple metric sources because no single endpoint exposes complete cluster state and resource telemetry.
- kube-state-metrics provides object-state information that is fundamentally different from kubelet and cAdvisor runtime metrics.
- Kubernetes service discovery eliminates the operational fragility of maintaining static monitoring target addresses.
- RBAC permissions must include node proxy access when Prometheus retrieves kubelet and cAdvisor metrics through the Kubernetes API server.
- Merely annotating an application pod does not create a Prometheus endpoint; the workload must actually expose Prometheus-format metrics.
- Node Exporter is naturally deployed as a DaemonSet because host-level observability requires an exporter on every node.
- API validation should treat empty PromQL results as failures when metrics are expected to exist.


## Troubleshooting Log

### Docker Group Access

Docker was installed and running, but the active remote shell had not inherited Docker group membership.

The setup used controlled Docker-group execution while configuring persistent group membership instead of replacing the interactive SSH shell.


### Existing Host Port

TCP port 8443 was already occupied by another host service.

Minikube using the Docker driver did not require binding its Kubernetes API server to that host listener, so the existing service did not block cluster creation.


### Full Operating System Upgrade

A complete package upgrade was unnecessary for the short-lived environment and could introduce unrelated system changes.

Only required dependencies were installed.


### Missing kube-state-metrics

The required PromQL report includes:

    kube_node_info
    kube_pod_status_phase
    kube_pod_info

Those metrics are not produced by Node Exporter, kubelet, or cAdvisor.

kube-state-metrics was therefore added explicitly to support Kubernetes object-state queries.


### Nginx Annotation Without Metrics Endpoint

A stock Nginx container does not expose Prometheus metrics on port 80.

An Nginx Prometheus Exporter sidecar was added and pod annotations were directed to its metrics port so annotation-driven discovery results in a valid scrape target.


### Node Exporter Discovery

Node Exporter was exposed through a Kubernetes Service and discovered through Kubernetes endpoint discovery rather than statically configured node addresses.


### Empty Prometheus Query Results

A Prometheus API request can return:

    "status": "success"

while still containing an empty result array.

The reporting utility validates both the API status and result presence before considering a query successful.


### Port-Forward Lifecycle

Leaving background kubectl port-forward processes running can create port conflicts and stale processes.

The reporting utility registers cleanup handlers so the port-forward is terminated on normal exit, error, or signal.
