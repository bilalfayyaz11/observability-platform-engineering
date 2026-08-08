# Advanced Alert Routing and Inhibition

## What This Does

This implementation provides a complete Linux alerting architecture using Prometheus, Node Exporter, Alertmanager, advanced PromQL, controlled workload generation, routing policies, inhibition rules, and a persistent structured webhook receiver.

The system collects host telemetry, evaluates threshold, composite, and predictive alerts, forwards firing alerts to Alertmanager, applies routing decisions based on severity and alert type, suppresses redundant notifications through inhibition rules, and delivers structured alert events to dedicated webhook paths.

The implementation goes beyond basic threshold monitoring by demonstrating how multiple infrastructure signals can be correlated and how notification noise can be reduced through topology-aware suppression.

This architecture is directly applicable to SRE, AIOps, Platform Engineering, production infrastructure, DevOps, and MLOps environments where alert quality matters as much as alert quantity.


## Architecture

    ┌──────────────────────────────────────────────┐
    │                  Linux Host                  │
    │                                              │
    │      CPU       Memory       Filesystem       │
    │       │           │              │           │
    └───────┼───────────┼──────────────┼───────────┘
            │           │              │
            └───────────┴──────────────┘
                        │
                        ▼
                ┌────────────────┐
                │ Node Exporter  │
                │ 127.0.0.1:9100 │
                └───────┬────────┘
                        │
                        │ scrape every 15s
                        ▼
                ┌────────────────┐
                │   Prometheus   │
                │ 127.0.0.1:9090 │
                ├────────────────┤
                │ Threshold      │
                │ Composite      │
                │ Predictive     │
                │ Alert Rules    │
                └───────┬────────┘
                        │
                        │ firing alerts
                        ▼
                ┌────────────────┐
                │  Alertmanager  │
                │ 127.0.0.1:9093 │
                ├────────────────┤
                │ Grouping       │
                │ Routing        │
                │ Inhibition     │
                └───────┬────────┘
                        │
              ┌─────────┼─────────┐
              │         │         │
              ▼         ▼         ▼

          /critical  /warning  /capacity
              │         │         │
              └─────────┼─────────┘
                        ▼
                ┌────────────────┐
                │ Alert Webhook  │
                │ 127.0.0.1:5001 │
                └────────────────┘


## Components

### Node Exporter

Node Exporter exposes Linux host metrics including:

- CPU time by mode
- memory capacity
- available memory
- filesystem availability
- filesystem capacity


It runs under a dedicated:

    node_exporter

service account.


### Prometheus

Prometheus performs:

- metric collection
- PromQL evaluation
- alert state management
- Alertmanager discovery
- lifecycle configuration reload


Prometheus runs under a dedicated:

    prometheus

service account.


### Alertmanager

Alertmanager provides:

- notification grouping
- severity-based routing
- alert-type routing
- repeat intervals
- notification delivery
- inhibition
- resolved notification handling


Alertmanager runs under a dedicated:

    alertmanager

service account.


### Structured Webhook Receiver

A Python HTTP service accepts Alertmanager POST requests and records normalized JSON events.

Each event includes:

    received_at
    endpoint
    alertname
    status
    severity
    alert_type
    instance
    summary


The webhook runs under a dedicated:

    alert-webhook

service account.


## Directory Layout

    ~/advanced-alerting/
    ├── configs/
    │   ├── prometheus.yml
    │   ├── prometheus-production.yml
    │   ├── alertmanager.yml
    │   ├── alertmanager-advanced.yml
    │   └── alertmanager-production.yml
    │
    ├── rules/
    │   ├── alert_rules.yml
    │   └── alert-rules-production.yml
    │
    ├── webhook/
    │   └── webhook_receiver.py
    │
    ├── services/
    │   ├── prometheus.service
    │   ├── node_exporter.service
    │   ├── alertmanager.service
    │   └── alert-webhook.service
    │
    ├── evidence/
    │   ├── task1-targets.tsv
    │   ├── task1-alertmanager-discovery.json
    │   ├── task2-rule-inventory.tsv
    │   ├── task2-alert-transitions.tsv
    │   ├── task2-resource-samples.tsv
    │   ├── task2-final-alert-snapshot.json
    │   ├── task2-predict-linear-validation.json
    │   ├── task3-routing-tree.txt
    │   ├── task3-routing-events.jsonl
    │   ├── task3-severity-inhibition-events.jsonl
    │   ├── task3-predictive-inhibition-events.jsonl
    │   ├── task3-alertmanager-alerts.json
    │   └── final-validation.txt
    │
    └── README.md


## Service Isolation

Each monitoring component runs under a separate restricted identity:

    Prometheus     → prometheus

    Node Exporter  → node_exporter

    Alertmanager   → alertmanager

    Webhook        → alert-webhook


This avoids sharing one service account across unrelated processes and reduces the impact of a service compromise.


## Localhost Network Design

Internal services listen only on localhost:

    Prometheus     127.0.0.1:9090

    Node Exporter  127.0.0.1:9100

    Alertmanager   127.0.0.1:9093

    Alert Webhook  127.0.0.1:5001


Because all components operate on the same host, there is no operational need to expose these listeners externally.


## Prometheus Scraping

Prometheus collects metrics from:

    prometheus

and:

    node


Representative configuration:

    scrape_configs:

      - job_name: prometheus

        static_configs:

          - targets:
              - 127.0.0.1:9090


      - job_name: node

        static_configs:

          - targets:
              - 127.0.0.1:9100


Prometheus also discovers Alertmanager at:

    127.0.0.1:9093


## Warning CPU Alert

The warning CPU alert detects sustained CPU utilization above 80 percent.

Conceptually:

    CPU usage > 80%
           │
           │ for 2 minutes
           ▼
    HighCPUUsage
           │
           └── severity=warning


PromQL:

    100 -
    (
      avg by(instance) (
        rate(
          node_cpu_seconds_total{
            job="node",
            mode="idle"
          }[1m]
        )
      ) * 100
    ) > 80


## Critical CPU Alert

Critical CPU pressure uses a higher threshold and shorter evaluation period.

    CPU usage > 95%
           │
           │ for 1 minute
           ▼
    CriticalCPUUsage
           │
           └── severity=critical


This creates distinct escalation behavior for warning and critical CPU conditions.


## Composite Alert

The composite alert fires only when two independent conditions are true simultaneously:

    CPU > 70%
        AND
    Memory > 70%
           │
           │ for 3 minutes
           ▼
    SystemUnderStress


The PromQL expression explicitly uses:

    and on(instance)


This ensures that the CPU and memory vectors are joined using the host instance label even when their remaining label sets differ.


## Why Explicit Vector Matching Matters

CPU utilization is calculated with:

    avg by(instance)


This removes labels such as CPU core and metric mode.

Memory metrics may retain additional labels.

A bare PromQL:

    A and B


depends on compatible label sets.

The implementation instead uses:

    A and on(instance) B


which explicitly states that both conditions belong to the same host.


## Predictive Capacity Alert

The predictive rule uses:

    predict_linear()


to project filesystem availability into the future.

Production design:

    historical window   6 hours
    prediction horizon  24 hours


Conceptually:

    filesystem available bytes
              │
              ▼
       six-hour trend
              │
              ▼
        linear projection
              │
              ▼
    predicted availability < 0
              │
              ▼
      DiskSpaceRunningOut


The rule is labeled:

    severity=warning
    alert_type=predictive


## Fresh-Environment Predictive Validation

A newly created host does not contain six hours of meaningful historical telemetry.

The implementation therefore separates:

    production rule semantics

from:

    available-history validation


The full production rule remains configured with a six-hour range.

`predict_linear()` is also tested against the shorter history actually present in the temporary environment to verify that the function evaluates successfully.

This avoids claiming historical evidence that does not exist.


## Controlled CPU Pressure

CPU load is generated with `stress-ng`.

The workload intentionally creates enough CPU activity to cross the configured alert thresholds.

Prometheus is polled throughout the workload so alert lifecycle changes can be observed directly.


## Controlled Memory Pressure

The host used for validation had no configured swap.

Rather than allocate a fixed percentage blindly, the implementation:

1. reads total memory
2. reads available memory
3. calculates current utilization
4. computes an allocation targeting approximately 74 percent total usage
5. applies a safety ceiling before launching memory pressure


This creates meaningful memory pressure while reducing unnecessary OOM risk.


## Alert Lifecycle Capture

Alert state transitions are written to:

    task2-alert-transitions.tsv


The transition evidence records:

    UTC observation time
    alert name
    previous state
    new state
    severity
    activeAt


Typical lifecycle:

    inactive
       ↓
    pending
       ↓
    firing
       ↓
    load removed
       ↓
    inactive


This proves rule behavior over time instead of only inspecting one final API response.


## Alert Routing

Alertmanager uses three specialized receivers.


### Critical Receiver

Matcher:

    severity="critical"


Receiver:

    critical-team


Webhook endpoint:

    /critical


Routing behavior:

    group_wait       5s
    repeat_interval  5m


## Warning Receiver

Matcher:

    severity="warning"


Receiver:

    warning-team


Webhook endpoint:

    /warning


Routing behavior:

    repeat_interval  2h


## Capacity Receiver

Matcher:

    alert_type="predictive"


Receiver:

    capacity-planning


Webhook endpoint:

    /capacity


Routing behavior:

    repeat_interval  6h


## Predictive Route Precedence

Predictive alerts can also carry:

    severity="warning"


If the warning route were evaluated first, the alert could incorrectly reach the generic warning receiver.

The routing tree therefore evaluates:

    alert_type="predictive"

before:

    severity="warning"


This guarantees that predictive capacity alerts reach:

    capacity-planning


instead of:

    warning-team


## Routing Flow

    Alert enters Alertmanager
              │
              ▼
    alert_type=predictive ?
         │
      yes│             no
         ▼              │
    capacity-planning   │
                        ▼
                 severity=critical ?
                      │
                   yes│          no
                      ▼           │
                critical-team     │
                                  ▼
                           severity=warning ?
                                │
                             yes│
                                ▼
                           warning-team


## Severity Inhibition

The first inhibition rule reduces duplicate notifications during escalation.

Condition:

    critical alert
         +
    warning alert
         +
    same instance


Result:

    critical notification delivered

    warning notification suppressed


Configuration semantics:

    source:
        severity="critical"

    target:
        severity="warning"

    equal:
        instance


This prevents operators from receiving both warning and critical notifications for the same host condition.


## Severity Inhibition Validation

The implementation sends:

    CriticalSource
        severity=critical
        instance=inhibition-host-1


and then:

    WarningTarget
        severity=warning
        instance=inhibition-host-1


Expected result:

    CriticalSource   → /critical

    WarningTarget    → suppressed


The implementation then sends another warning using a different instance.

That warning must still reach:

    /warning


This proves that inhibition is correctly scoped by instance rather than globally suppressing all warnings.


## Composite / Predictive Inhibition

The second inhibition policy handles correlated alert categories.

Condition:

    composite alert
         +
    predictive alert
         +
    same instance


Result:

    composite notification delivered

    predictive notification suppressed


Configuration semantics:

    source:
        alert_type="composite"

    target:
        alert_type="predictive"

    equal:
        instance


This can prevent a lower-priority capacity prediction from creating additional noise while a more immediate multi-resource condition is already active.


## Composite / Predictive Validation

The validation sends:

    CompositeSource
        alert_type=composite
        instance=inhibition-host-2


followed by:

    PredictiveTarget
        alert_type=predictive
        instance=inhibition-host-2


Expected result:

    CompositeSource   → /warning

    PredictiveTarget  → suppressed


A predictive alert on another instance is then sent and must reach:

    /capacity


This confirms that suppression is correctly scoped.


## Structured Webhook Events

Webhook events are persisted as JSON Lines.

Example structure:

    {
      "received_at": "UTC timestamp",
      "endpoint": "/critical",
      "alertname": "CriticalCPUUsage",
      "status": "firing",
      "severity": "critical",
      "alert_type": "threshold",
      "instance": "host",
      "summary": "Critical CPU usage"
    }


JSON Lines is useful because each alert delivery remains an independent structured event that can later be:

- searched
- parsed
- forwarded
- indexed
- analyzed
- consumed by automation


## Webhook Health Check

The service exposes:

    GET /health


Expected response:

    {
      "status": "ok",
      "service": "alert-webhook"
    }


## Persistent Webhook Service

The webhook receiver is not launched with a fragile background shell process.

It runs through:

    alert-webhook.service


Advantages include:

- automatic restart
- service identity separation
- journal logging
- startup management
- consistent process lifecycle
- security hardening


## Alertmanager Configuration Reload

Alertmanager configuration is validated first:

    sudo -u alertmanager \
      amtool check-config \
      /etc/alertmanager/alertmanager.yml


The running process is then reloaded through:

    POST /-/reload


Its process ID is captured before and after reload.

Matching process IDs demonstrate that configuration was applied without restarting the service.


## Prometheus Configuration Reload

Prometheus runs with:

    --web.enable-lifecycle


Rule updates can therefore be applied using:

    POST /-/reload


The process ID is similarly checked before and after reload.


## Configuration Validation

Prometheus configuration:

    sudo -u prometheus \
      promtool check config \
      /etc/prometheus/prometheus.yml


Prometheus alert rules:

    sudo -u prometheus \
      promtool check rules \
      /etc/prometheus/alert_rules.yml


Alertmanager configuration:

    sudo -u alertmanager \
      amtool check-config \
      /etc/alertmanager/alertmanager.yml


No production configuration is activated until its syntax has been validated.


## Configuration Permissions

Sensitive service configuration is restricted.

Prometheus configuration:

    owner: prometheus
    mode: 640


Alert rules:

    owner: prometheus
    mode: 640


Alertmanager configuration:

    owner: alertmanager
    mode: 640


The validation workflow checks both ownership and permission width.


## Alertmanager Routing Validation

The effective routing tree is inspected with:

    amtool config routes \
      --alertmanager.url=http://127.0.0.1:9093


Expected specialized receivers:

    critical-team

    warning-team

    capacity-planning


## Synthetic Alert Testing

Alert transport and inhibition behavior are tested using synthetic alerts submitted directly to the Alertmanager API.

This allows routing behavior to be validated without changing the production PromQL thresholds.

The tests cover:

    warning routing

    critical routing

    predictive routing

    predictive precedence

    critical → warning inhibition

    composite → predictive inhibition

    instance-scoped inhibition


## Why Synthetic Alert Tests Matter

Changing production thresholds simply to test notification infrastructure can introduce uncertainty.

Synthetic alerts allow the notification system to be tested independently:

    PromQL rule evaluation
        separate from
    notification routing


This makes transport testing deterministic and repeatable.


## Evidence-Driven Validation

Evidence includes:

    Prometheus target state

    Alertmanager discovery

    loaded rule inventory

    resource samples during pressure

    alert state transitions

    predictive query validation

    routing tree

    webhook events

    severity inhibition results

    predictive inhibition results

    final service state


This allows the final architecture to be independently inspected rather than relying only on a success message.


## Tools Used

- Prometheus
- PromQL
- Node Exporter
- Alertmanager
- amtool
- promtool
- stress-ng
- Python
- systemd
- curl
- jq
- Bash
- Linux process utilities
- Linux networking utilities


## Key Skills Demonstrated

- advanced PromQL alert engineering
- threshold alerting
- multi-condition alerting
- PromQL vector matching
- predictive alerting
- capacity forecasting
- alert lifecycle analysis
- Alertmanager routing
- route precedence
- alert grouping
- inhibition rules
- alert-noise reduction
- webhook engineering
- structured event logging
- service account isolation
- systemd hardening
- controlled workload generation
- deterministic alert testing
- configuration hot reload
- monitoring pipeline validation
- incident notification architecture


## Real-World Use Case

A large production environment may produce multiple signals for one underlying incident.

For example:

    CPU warning
        ↓
    CPU critical
        ↓
    memory pressure
        ↓
    composite resource alert
        ↓
    disk forecast warning


Without routing and inhibition, operators may receive several notifications describing overlapping symptoms.

A better architecture performs:

    detection
        ↓
    classification
        ↓
    correlation
        ↓
    inhibition
        ↓
    routing
        ↓
    notification


This implementation demonstrates that workflow using Prometheus and Alertmanager.


## Alert Fatigue Reduction

Alert quality depends not only on whether an alert is technically correct.

Operators must also receive the right signal at the right priority.

This implementation reduces unnecessary notification volume through:

    severity escalation

    composite conditions

    predictive classification

    route precedence

    instance-scoped inhibition


The result is a more operationally useful alerting topology.


## Lessons Learned

- Alerting architecture should separate detection from notification routing.
- Threshold alerts alone are often insufficient for diagnosing system-wide pressure.
- Composite conditions can reduce noise by requiring multiple signals simultaneously.
- PromQL vector matching must be designed explicitly when combining metrics with different label sets.
- Predictive alerts require enough historical data before their forecasts should be interpreted as operational evidence.
- A fresh monitoring system should not claim long-term historical trends it does not possess.
- Alertmanager route ordering matters when one alert matches multiple categories.
- Predictive alerts should be routed before generic warning alerts when capacity planning has a dedicated receiver.
- Inhibition rules must be scoped carefully to prevent unrelated alerts from being suppressed.
- Testing inhibition on both the same and different instances proves that equality matching works correctly.
- Synthetic alerts are safer and more deterministic than changing production alert thresholds to test transport.
- Structured webhook events are easier to integrate with future automation than unstructured text.
- Dedicated service identities reduce unnecessary privilege sharing.
- Localhost binding is appropriate when every monitoring component operates on one host.
- Configuration should always be validated before reload.
- Hot reloads reduce unnecessary monitoring interruptions.


## Final Validated State

Services:

    Prometheus      active
    Node Exporter   active
    Alertmanager    active
    Alert Webhook   active


Listeners:

    127.0.0.1:9090   Prometheus

    127.0.0.1:9100   Node Exporter

    127.0.0.1:9093   Alertmanager

    127.0.0.1:5001   Alert Webhook


Prometheus targets:

    prometheus   UP

    node         UP


Alert rules:

    HighCPUUsage

    CriticalCPUUsage

    SystemUnderStress

    DiskSpaceRunningOut


Routing:

    critical    → critical-team

    warning     → warning-team

    predictive  → capacity-planning


Webhook endpoints:

    /critical

    /warning

    /capacity


Validated inhibition:

    critical
        suppresses
    warning
        on the same instance


    composite
        suppresses
    predictive
        on the same instance


Validated behavior:

    CPU threshold firing

    composite CPU + memory firing

    alert recovery

    predictive PromQL execution

    warning routing

    critical routing

    predictive routing

    predictive route precedence

    severity inhibition

    composite / predictive inhibition

    instance-scoped suppression

    structured webhook delivery


The final implementation demonstrates an end-to-end advanced alerting architecture with correlated detection, predictive analysis, severity-aware routing, suppression of redundant notifications, structured webhook delivery, and reproducible operational evidence.
