# Kubernetes Observability Platform

## What This Does

This implementation builds a Kubernetes-native observability platform using Minikube, Prometheus, Grafana, kube-state-metrics, node-exporter, Metrics Server, and kubelet/cAdvisor telemetry.

Prometheus runs inside Kubernetes and uses Kubernetes-aware service discovery to collect control-plane, workload, node, and container metrics.

Grafana is deployed inside the monitoring namespace and automatically receives Prometheus as its data source through declarative provisioning.

The platform provides visibility into Kubernetes node health, pod state, CPU usage, memory consumption, filesystem usage, network traffic, and container-level resource behavior.

A multi-replica nginx workload is used to validate dynamic discovery and demonstrate that scaling events automatically appear in the monitoring pipeline without manual reconfiguration.

## Architecture

    ┌──────────────────────────────────────────────────────────────────┐
    │                    Minikube Kubernetes Cluster                   │
    │                                                                  │
    │  ┌───────────────────────┐                                       │
    │  │    Kubernetes API     │                                       │
    │  │                       │                                       │
    │  │ Cluster Objects       │                                       │
    │  │ Nodes                 │                                       │
    │  │ Pods                  │                                       │
    │  │ Services              │                                       │
    │  └───────────┬───────────┘                                       │
    │              │                                                   │
    │              │                                                   │
    │  ┌───────────▼────────────┐       ┌──────────────────────────┐   │
    │  │   kube-state-metrics   │       │       node-exporter      │   │
    │  │                        │       │                          │   │
    │  │ kube_pod_info          │       │ CPU                      │   │
    │  │ pod phase              │       │ Memory                   │   │
    │  │ deployment state       │       │ Disk                     │   │
    │  │ node condition         │       │ Network                  │   │
    │  └───────────┬────────────┘       └────────────┬─────────────┘   │
    │              │                                  │                 │
    │              │                                  │                 │
    │  ┌───────────▼──────────────────────────────────▼─────────────┐   │
    │  │                        Prometheus                         │   │
    │  │                                                           │   │
    │  │ Kubernetes API Discovery                                  │   │
    │  │ kube-state-metrics                                        │   │
    │  │ node-exporter                                             │   │
    │  │ kubelet                                                   │   │
    │  │ cAdvisor                                                  │   │
    │  └───────────────────────┬───────────────────────────────────┘   │
    │                          │                                       │
    │                          │ PromQL                                │
    │                          ▼                                       │
    │  ┌───────────────────────────────────────────────────────────┐   │
    │  │                         Grafana                           │   │
    │  │                                                           │   │
    │  │ Node Health                                               │   │
    │  │ Pod State                                                 │   │
    │  │ CPU / Memory                                              │   │
    │  │ Container Metrics                                         │   │
    │  │ Network Traffic                                           │   │
    │  │ Pod Inventory                                             │   │
    │  └───────────────────────────────────────────────────────────┘   │
    │                                                                  │
    │  ┌───────────────────────────────────────────────────────────┐   │
    │  │                   Observed Workloads                      │   │
    │  │                                                           │   │
    │  │ nginx-observed                                            │   │
    │  │       3 replicas                                          │   │
    │  │          ↓                                                │   │
    │  │       5 replicas                                          │   │
    │  │          ↓                                                │   │
    │  │       3 replicas                                          │   │
    │  └───────────────────────────────────────────────────────────┘   │
    │                                                                  │
    └──────────────────────────────────────────────────────────────────┘

## Monitoring Data Sources

The platform intentionally separates Kubernetes telemetry into multiple metric producers.

### kube-state-metrics

Provides metrics describing Kubernetes object state.

Examples:

    kube_pod_info
    kube_pod_status_phase
    kube_node_status_condition

These metrics answer questions about Kubernetes desired and current state.

## Node Exporter

Provides Linux host telemetry.

Examples:

    node_cpu_seconds_total
    node_memory_MemAvailable_bytes
    node_memory_MemTotal_bytes
    node_filesystem_avail_bytes
    node_network_receive_bytes_total

These metrics expose resource utilization and host health.

## kubelet and cAdvisor

Prometheus accesses kubelet metrics through the Kubernetes API server proxy.

cAdvisor provides container-level resource telemetry.

Examples:

    container_cpu_usage_seconds_total
    container_memory_working_set_bytes
    container_network_receive_bytes_total
    container_network_transmit_bytes_total

This enables monitoring at the pod and container level.

## Metrics Server

Metrics Server provides Kubernetes resource metrics used by:

    kubectl top nodes
    kubectl top pods

It is useful for operational inspection but is separate from the Prometheus telemetry pipeline.

## Prometheus

Prometheus runs inside the `monitoring` namespace.

It collects:

- Prometheus self-metrics
- Kubernetes API metrics
- kube-state-metrics
- node-exporter metrics
- kubelet metrics
- cAdvisor container metrics

Prometheus uses Kubernetes RBAC permissions and service discovery rather than relying only on static host configuration.

## Kubernetes Service Discovery

Prometheus can dynamically discover Kubernetes resources.

This is essential because pods and workloads are ephemeral.

The monitoring configuration does not need to be manually rewritten whenever a workload is scaled or recreated.

## RBAC

Prometheus uses a dedicated Kubernetes ServiceAccount.

The ClusterRole provides read-only access required for observability.

Resources include:

    nodes
    nodes/proxy
    nodes/metrics
    services
    endpoints
    pods
    ingresses

Permissions are limited to:

    get
    list
    watch

This allows Prometheus to discover and scrape Kubernetes resources without granting unnecessary write privileges.

## Grafana

Grafana runs inside Kubernetes and is configured declaratively.

Prometheus data source:

    http://prometheus.monitoring.svc.cluster.local:9090

The data source is automatically provisioned from a ConfigMap.

No manual UI configuration is required.

## Kubernetes Dashboard

The provisioned dashboard provides visibility into:

- Ready nodes
- Running pods
- Pending pods
- Container count
- Node CPU utilization
- Node memory utilization
- Root filesystem usage
- Pod CPU usage
- Pod memory usage
- Container network receive traffic
- Container network transmit traffic
- Pod inventory

## Dashboard Queries

### Ready Nodes

    sum(
      kube_node_status_condition{
        condition="Ready",
        status="true"
      }
    )

## Running Pods

    sum(
      kube_pod_status_phase{
        phase="Running"
      }
    )

## Pending Pods

    sum(
      kube_pod_status_phase{
        phase="Pending"
      }
    )

## Node CPU Usage

    100 - (
      avg(
        rate(
          node_cpu_seconds_total{
            mode="idle"
          }[2m]
        )
      ) * 100
    )

## Node Memory Usage

    (
      1 -
      (
        node_memory_MemAvailable_bytes
        /
        node_memory_MemTotal_bytes
      )
    ) * 100

## Pod CPU Usage

    sum by (namespace, pod) (
      rate(
        container_cpu_usage_seconds_total{
          container!="",
          container!="POD",
          pod!=""
        }[2m]
      )
    )

## Pod Memory Usage

    sum by (namespace, pod) (
      container_memory_working_set_bytes{
        container!="",
        container!="POD",
        pod!=""
      }
    )

## Container Network Receive

    sum by (namespace, pod) (
      rate(
        container_network_receive_bytes_total{
          pod!=""
        }[2m]
      )
    )

## Container Network Transmit

    sum by (namespace, pod) (
      rate(
        container_network_transmit_bytes_total{
          pod!=""
        }[2m]
      )
    )

## Workload Validation

A three-replica nginx deployment is used as an observable workload.

Deployment:

    nginx-observed

Service:

    nginx-observed

The workload is intentionally exposed internally using a ClusterIP service.

External access is unnecessary for telemetry validation.

## Dynamic Discovery Test

The nginx workload was initially deployed with:

    3 replicas

Prometheus detected all three pods through Kubernetes telemetry.

The deployment was then scaled:

    3
    ↓
    5

Kubernetes created two additional pods.

kube-state-metrics automatically exposed their object state.

cAdvisor exposed their resource telemetry.

Prometheus collected the new series without configuration changes.

The workload was then scaled back:

    5
    ↓
    3

The monitoring stack automatically reflected the new desired and running state.

This validates dynamic Kubernetes observability rather than static monitoring.

## Traffic Validation

A temporary curl container generated internal requests against:

    nginx-observed.default.svc.cluster.local

This produced live activity that could be observed through container CPU, memory, and network metrics.

## Prerequisites

- Ubuntu or another supported Linux environment
- Docker
- kubectl
- Minikube
- Helm
- curl
- jq
- Git

## Cluster Resources

The local cluster was configured with:

    Docker driver
    containerd runtime
    3 vCPUs
    8 GiB memory

A non-default Kubernetes API server port was used to avoid a host port conflict.

## Deployment Files

Prometheus:

    prometheus-rbac.yaml
    prometheus-config.yaml
    prometheus-deployment.yaml

Grafana:

    grafana-secret.yaml
    grafana-datasource.yaml
    grafana-dashboard-provider.yaml
    grafana-dashboard.yaml
    grafana-deployment.yaml

Observed workload:

    nginx-observed.yaml
    nginx-observed-service.yaml

## Verify Kubernetes

Cluster information:

    kubectl cluster-info

Nodes:

    kubectl get nodes -o wide

Namespaces:

    kubectl get namespaces

All pods:

    kubectl get pods -A

## Verify Metrics Server

API service:

    kubectl get apiservice v1beta1.metrics.k8s.io

Node resources:

    kubectl top nodes

Pod resources:

    kubectl top pods -A

## Verify Monitoring Components

    kubectl get deployment,daemonset,pod,svc \
      -n monitoring

Expected components include:

    prometheus
    grafana
    kube-state-metrics
    node-exporter

## Verify Prometheus

Find the Prometheus pod:

    PROM_POD=$(
      kubectl get pod \
        -n monitoring \
        -l app.kubernetes.io/name=prometheus \
        -o jsonpath='{.items[0].metadata.name}'
    )

Check health:

    kubectl exec \
      -n monitoring \
      "$PROM_POD" \
      -- wget -qO- \
      http://127.0.0.1:9090/-/healthy

Check targets:

    kubectl exec \
      -n monitoring \
      "$PROM_POD" \
      -- wget -qO- \
      http://127.0.0.1:9090/api/v1/targets

## Validate Metric Families

Kubernetes object state:

    kube_pod_info

Node telemetry:

    node_cpu_seconds_total

Container telemetry:

    container_cpu_usage_seconds_total

Pod state:

    kube_pod_status_phase

Node readiness:

    kube_node_status_condition

## Verify nginx Discovery

Kubernetes:

    kubectl get pods \
      -l app=nginx-observed

Prometheus query:

    kube_pod_info{
      pod=~"nginx-observed.*"
    }

Running state:

    kube_pod_status_phase{
      pod=~"nginx-observed.*",
      phase="Running"
    } == 1

## Scaling Validation

Scale to five replicas:

    kubectl scale deployment nginx-observed \
      --replicas=5

Wait:

    kubectl rollout status \
      deployment/nginx-observed

Restore:

    kubectl scale deployment nginx-observed \
      --replicas=3

This demonstrates that Kubernetes telemetry automatically follows workload lifecycle changes.

## Grafana Provisioning

Grafana is provisioned through Kubernetes ConfigMaps.

The Prometheus data source is mounted into:

    /etc/grafana/provisioning/datasources/

The dashboard provider is mounted into:

    /etc/grafana/provisioning/dashboards/

Dashboard JSON is mounted into:

    /var/lib/grafana/dashboards/

This makes visualization configuration reproducible.

## Tools Used

- Kubernetes
- Minikube
- Docker
- containerd
- kubectl
- Helm
- Prometheus
- PromQL
- Grafana
- kube-state-metrics
- Prometheus Node Exporter
- Metrics Server
- kubelet
- cAdvisor
- Kubernetes RBAC
- ConfigMaps
- Secrets
- Deployments
- DaemonSets
- Services

## Key Skills Demonstrated

- Kubernetes cluster operations
- Kubernetes observability architecture
- Prometheus Kubernetes service discovery
- Prometheus RBAC
- Kubernetes workload telemetry
- kube-state-metrics integration
- Node Exporter integration
- kubelet metrics collection
- cAdvisor metrics collection
- PromQL
- Grafana provisioning
- Dashboard-as-code
- Kubernetes DNS
- Dynamic workload monitoring
- Replica scaling validation
- Container resource analysis
- Infrastructure troubleshooting

## Real-World Use Case

Production Kubernetes environments constantly change.

Pods are restarted.

Deployments are scaled.

Nodes become resource constrained.

Containers consume different amounts of CPU and memory.

Static monitoring cannot reliably follow these changes.

Prometheus Kubernetes service discovery allows the monitoring system to dynamically adapt to the current cluster state.

This architecture can be applied to:

- Kubernetes application platforms
- microservice environments
- CI/CD worker clusters
- AI inference platforms
- GPU-serving infrastructure
- model-serving workloads
- agent execution environments
- distributed data systems
- internal developer platforms

For Applied AI and MLOps workloads, the same foundation can be extended with GPU utilization, model latency, inference throughput, queue depth, model errors, and application-specific metrics.

## Lessons Learned

Metrics Server and Prometheus serve different purposes.

Metrics Server provides lightweight resource metrics for Kubernetes operational APIs.

Prometheus provides long-term, queryable observability.

kube-state-metrics exposes Kubernetes object state.

Node Exporter exposes host resource telemetry.

kubelet and cAdvisor expose container and workload resource behavior.

A usable Kubernetes observability platform requires these metric sources to be understood separately rather than treating all metrics as if they originate from Prometheus itself.

Kubernetes service discovery is critical because workloads are dynamic.

Grafana provisioning removes manual configuration and makes visualization reproducible.

Scaling workloads provides a strong validation mechanism because it proves the monitoring architecture reacts automatically to changes in Kubernetes state.

## Troubleshooting Log

### Docker Permission Failure

Minikube initially could not access Docker from the existing shell.

Docker group membership was corrected and group-aware execution was used until the session inherited the new membership.

### Host API Port Conflict

Port 8443 was already used by another host service.

A different Kubernetes API server port was selected to avoid disrupting the existing service.

### Missing Metrics Server API

Metrics Server initially failed to enable because Minikube could not access Docker.

After correcting Docker access, the addon was enabled and the Metrics API became available.

### kube-state-metrics Verification

The kube-state-metrics container did not contain wget.

This was not a component failure.

A temporary network utility pod was used to verify the service endpoint instead.

### Missing Kubernetes Metric Producers

Kubernetes object, host, and container metrics originate from different components.

kube-state-metrics, node-exporter, and kubelet/cAdvisor scraping were configured explicitly.

### Legacy RBAC

Older ingress RBAC references were replaced with the current networking.k8s.io API group.

### Manual Grafana Configuration

Manual datasource and dashboard creation was replaced with Kubernetes ConfigMap provisioning.

### Hard-Coded Grafana Credentials

Grafana administrator credentials are stored in a Kubernetes Secret instead of directly in the Deployment manifest.

### NodePort Exposure

Monitoring components and the observed workload use internal ClusterIP services because external exposure is unnecessary for internal observability validation.

### Temporary Storage

Prometheus and Grafana use ephemeral storage in this disposable local environment.

A production deployment should replace this with persistent volumes and appropriate retention policies.

### Static Dashboard Assumptions

The dashboard was built around metric families that were explicitly verified in the running environment rather than relying on an external dashboard ID with unknown dependencies.
