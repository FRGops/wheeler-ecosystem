# Wheeler Brain OS — Observability Fusion Plan

## 1. Overview

Observability Fusion is the integration layer that merges metrics, logs, traces, uptime checks, and security events from across the Wheeler ecosystem into a unified intelligence stream. Instead of checking 5 dashboards to answer one question, operators query a single fused view.

### The Fusion Principle

```
BEFORE (fragmented):                    AFTER (fused):
  Grafana → metrics                      "Why is prediction-radar slow?"
  Loki → logs                             → metrics: p99 latency up 3x
  Uptime Kuma → reachability              → logs: "connection timeout to COREDB"
  Prometheus → alerts                     → traces: 2.3s in db_query span
  Netdata → system metrics                → topology: COREDB Redis at 98% memory
  manual → correlation                    → recommendation: flush Redis cache, add memory limit
```

---

## 2. Current Observability Landscape

### 2.1 Existing Tools (8 dashboards, 2 stacks)

```
AIOPS MONITORING STACK:
  Prometheus (v2.55.1)    → 127.0.0.1:9090   → Metrics collection + alert evaluation
  Alertmanager (v0.28.1)  → 127.0.0.1:9093   → Alert routing, grouping, inhibition
  Grafana (v11.5.1)       → 127.0.0.1:3002   → Dashboards + visualization
  Loki (v3.6.3)           → 127.0.0.1:3100   → Log aggregation
  Promtail (v3.6.8)       → log shipper       → All containers → Loki
  Pushgateway (v1.11.2)   → 127.0.0.1:9092   → Ephemeral job metrics
  Webhook Relay           → 127.0.0.1:8085   → Alert → Discord formatter
  Netdata                 → 127.0.0.1:19999  → Real-time system metrics
  Uptime Kuma             → 127.0.0.1:3001   → Uptime monitoring (external targets)

COREDB MONITORING STACK:
  Prometheus (:latest)    → 100.118.166.117:9090  → Metrics for COREDB services
  Grafana (:latest)       → 100.118.166.117:3000  → COREDB dashboards
  Loki (:latest)          → 127.0.0.1:3100        → COREDB log aggregation
  Promtail (:latest)      → log shipper            → COREDB containers → Loki
  Uptime Kuma (:latest)   → 127.0.0.1:3001        → COREDB uptime
  Pushgateway (:latest)   → 127.0.0.1:9092        → COREDB push metrics

EXPORTERS:
  node_exporter (both)    → System metrics (CPU, RAM, disk, network)
  postgres_exporter       → COREDB PostgreSQL metrics
  redis_exporter          → COREDB Redis metrics
  hostinger-health-export → Hostinger server metrics into AIOPS Prometheus

PREDICTION-RADAR MONITORING (internal):
  Prometheus + Alertmanager + Grafana + Uptime Kuma (self-contained stack)
```

### 2.2 Current Gaps

```
MISSING:
  ✗ Distributed tracing — no request-level visibility across service boundaries
  ✗ Unified dashboard — operators must check Grafana + Loki + Uptime Kuma
  ✗ Cross-stack correlation — AIOPS and COREDB stacks are independent
  ✗ Agent performance metrics — no latency/error tracking per agent
  ✗ Business metrics — revenue, user count, conversion (not technical)
  ✗ SLO/SLI tracking — no defined error budgets
  ✗ Synthetic monitoring — no proactive transaction testing
  ✗ Alert deduplication — same issue may fire on both stacks

DEGRADED:
  ⚠ COREDB uses :latest images for all monitoring — version skew risk
  ⚠ backup-verification PM2 process is stopped
  ⚠ No automated backup verification
  ⚠ Alert fatigue potential — 6 critical alerts, no prioritization
```

---

## 3. Fusion Architecture

### 3.1 The Fusion Data Model

```
All observability data is normalized into a unified event schema:

{
  "timestamp": "2026-05-24T08:15:00.000Z",
  "source": "prometheus|grafana|loki|uptime-kuma|netdata|docker|pm2",
  "source_server": "aiops|coredb|hostinger",
  "event_type": "metric|log|alert|healthcheck|trace|event",
  "target": {
    "service": "prediction-radar-api",
    "container": "prediction-radar-app-api",
    "server": "aiops",
    "type": "docker"
  },
  "payload": {
    // Source-specific data, normalized
  },
  "severity": "critical|warning|info|debug",
  "correlation_id": "uuid"  // Links related events across sources
}
```

### 3.2 Fusion Pipeline

```
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│Prometheus│  │   Loki   │  │  Uptime  │  │  Netdata │  │  Docker  │
│ Metrics  │  │   Logs   │  │   Kuma   │  │  System  │  │  Events  │
└────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │             │             │
     └──────────┬──┴─────────────┴─────────────┴─────────────┘
                │
                ▼
     ┌─────────────────────┐
     │   FUSION ENGINE     │  ← Normalize, correlate, enrich
     │   (event-bus-relay  │
     │    + ClickHouse)    │
     └─────────┬───────────┘
               │
     ┌─────────┼───────────┐
     │         │           │
     ▼         ▼           ▼
┌─────────┐ ┌──────┐ ┌──────────┐
│Unified  │ │Alert │ │Anomaly   │
│Dashboard│ │Router│ │Detection │
│(Grafana)│ │      │ │          │
└─────────┘ └──┬───┘ └────┬─────┘
               │          │
               ▼          ▼
          Discord    AI Decision
          Alerts     Layer
```

### 3.3 Correlation Engine

```
CORRELATION RULES:

1. Time-based correlation:
   Events within 30s window → same incident hypothesis
   Example: "Container restart" + "connection refused log" + "healthcheck fail"

2. Dependency-based correlation:
   Upstream service alert + downstream service alert → cascade hypothesis
   Example: "COREDB Redis slow" → likely causes "prediction-radar-api timeout"

3. Pattern-based correlation:
   Match against known incident patterns from historical data
   Example: "Memory growth + GC pressure + eventual OOM" = memory leak pattern

4. Topology-based correlation:
   All events on same k-hop subgraph → related
   Example: Events in prediction-radar network (14 containers) → same incident
```

---

## 4. Unified Dashboard Design

### 4.1 The "Single Pane of Glass"

```
┌──────────────────────────────────────────────────────────────┐
│  WHEELER ECOSYSTEM HEALTH                         08:15 UTC  │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐ │
│  │ Servers │ │Container│ │   PM2   │ │  Alerts │ │Uptime  │ │
│  │  2/2 UP │ │ 58/58 ✓ │ │ 17/18 ✓ │ │  0 crit │ │ 99.97% │ │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └────────┘ │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  TOPOLOGY MAP (live)                    ALERTS (24h)          │
│  ┌──────────────────────┐              ┌──────────────────┐  │
│  │ [AIOPS]───[COREDB]   │              │ No critical      │  │
│  │   │  \      │  \     │              │ 2 warnings       │  │
│  │ [40] [17] [19] [0]  │              │  (disk 82%,      │  │
│  │  containers/pm2      │              │   mem warn)      │  │
│  └──────────────────────┘              └──────────────────┘  │
│                                                              │
│  RECENT EVENTS                         RECOMMENDATIONS       │
│  ┌──────────────────────────────────────┐ ┌──────────────┐  │
│  │ 08:14 aiops-healthchecks restart    │ │ Pin 7 :latest │  │
│  │ 08:10 prometheus alert resolved     │ │ images on     │  │
│  │ 08:05 backup-verification stopped   │ │ COREDB        │  │
│  └──────────────────────────────────────┘ └──────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 Drill-Down Views

```
SERVICE DETAIL VIEW (e.g., prediction-radar):
  ┌────────────────────────────────────────────┐
  │ prediction-radar-app                    ✓  │
  │ 14 containers, 6 dashboards, 1 database    │
  │                                            │
  │ LATENCY (p50/p95/p99):  45ms / 230ms / 890ms │
  │ ERROR RATE (5m):        0.02%               │
  │ REQUEST RATE:           142 req/s           │
  │                                            │
  │ DEPENDENCIES:                               │
  │   COREDB PostgreSQL (✓, 2ms)               │
  │   COREDB Redis (✓, 1ms)                    │
  │   Stripe API (✓, 120ms)                    │
  │   Polygon API (✓, 340ms)                   │
  │                                            │
  │ RECENT DEPLOYS: v3.2.1 (2h ago, healthy)   │
  │ RECENT INCIDENTS: None (14 days clean)     │
  └────────────────────────────────────────────┘
```

---

## 5. SLO / SLI Framework

### 5.1 Service Level Indicators

```
CRITICAL SERVICES (must define SLOs):

prediction-radar-app:
  SLI: API availability = successful_requests / total_requests
  SLO: 99.9% monthly (43m allowable downtime)
  Measurement: Prometheus up{job="prediction-radar"} + http_errors

frcrm-api:
  SLI: API availability + p95 latency < 500ms
  SLO: 99.5% monthly (3.6h allowable downtime)
  Measurement: up{job="frcrm-api"} + histogram_quantile(0.95, http_request_duration)

usesend (CRM portal):
  SLI: Availability + successful login rate
  SLO: 99.9% monthly
  Measurement: up{job="usesend"} + custom login metric

COREDB PostgreSQL:
  SLI: Connection success rate + replication lag
  SLO: 99.95% monthly (21m allowable downtime)
  Measurement: pg_up + pg_replication_lag

LiteLLM Proxy:
  SLI: Availability + p95 latency < 2s
  SLO: 99.5% monthly
  Measurement: up{job="litellm"} + llm_request_duration

Agent Fleet (aggregate):
  SLI: Agent polling success rate (all 9 agents)
  SLO: 99% monthly (7.3h allowable collective downtime)
  Measurement: custom agent health metrics (need to implement)
```

### 5.2 Error Budgets

```
Error Budget = 1 - SLO

prediction-radar:  0.1% monthly = 43 minutes
  → If we burn >50% in a week → freeze deployments
  → If we burn >80% → incident declared, all-hands

frcrm-api:         0.5% monthly = 3.6 hours
  → If we burn >25% in a day → investigate immediately

COREDB PostgreSQL: 0.05% monthly = 21 minutes
  → ANY burn triggers investigation (critical dependency for 12 services)
```

---

## 6. Log Aggregation Strategy

### 6.1 Log Sources

```
DOCKER CONTAINERS (58):
  All: docker json-file → promtail → Loki
  Retention: 30 days (AIOPS), ? days (COREDB)
  Labels: container_name, compose_stack, server, service_type

PM2 PROCESSES (17):
  All: PM2 log files → promtail → Loki
  Retention: 30 days (pm2-logrotate)
  Labels: process_name, runtime, port

NGINX:
  Access log: /var/log/nginx/access.log → promtail → Loki
  Error log: /var/log/nginx/error.log → promtail → Loki
  Labels: vhost, status_code

SYSTEM:
  syslog, auth.log, kernel → not currently in Loki (gap)
```

### 6.2 Log Query Patterns

```
Standard queries (pre-built for dashboards):

"Show me all ERROR logs from the last 15 minutes":
  {level="error"} | json | line_format "{{.message}}"

"What happened around when prediction-radar-api restarted?":
  {container="prediction-radar-app-api"} | json
  | line_format "{{.timestamp}} {{.level}} {{.message}}"

"Show me all authentication failures across all services":
  {level="error"} |= "auth" or "unauthorized" or "forbidden"

"What's the error rate by service in the last hour?":
  sum by (container) (count_over_time({level="error"}[1h]))
  /
  sum by (container) (count_over_time({}[1h]))
```

---

## 7. Synthetic Monitoring

### 7.1 Critical Path Tests (to implement)

```
TEST 1 — User Login Flow (every 5 minutes):
  GET https://email.frgops.io → 200
  POST login → 302 (redirect)
  GET dashboard → 200

TEST 2 — Prediction Radar Data Pipeline (every 15 minutes):
  GET https://prediction-radar.aiops → 200
  GET /api/markets → 200 + valid JSON
  Verify: response has data from <5 minutes ago (freshness check)

TEST 3 — Agent Health Endpoint (every 5 minutes):
  For each agent PM2 process:
    GET http://127.0.0.1:<port>/health → 200

TEST 4 — Database Connectivity (every 1 minute):
  COREDB PostgreSQL: pg_isready -h 100.118.166.117
  COREDB Redis: redis-cli -h 100.118.166.117 PING

TEST 5 — LLM Proxy Health (every 1 minute):
  GET http://127.0.0.1:4049/health → 200
```

### 7.2 Synthetic Test Runner

```
Implement as a PM2-managed service on AIOPS:
  - wheeler-synthetic-monitor (new PM2 process)
  - Runs test suite on configurable intervals
  - Publishes results to Prometheus (via Pushgateway)
  - Alerts via Alertmanager if any test fails 2 consecutive runs
```

---

## 8. Alert Optimization

### 8.1 Current Alert Problems

```
PROBLEM 1 — Single Prometheus evaluates all rules:
  - 30s evaluation interval creates 30s worst-case detection lag
  - No cross-stack alert correlation between AIOPS and COREDB

PROBLEM 2 — All critical alerts → same Discord channel:
  - No prioritization within "critical"
  - Operator must read every alert to assess severity

PROBLEM 3 — Alert fatigue risk:
  - 6 critical alerts × 2 servers = 12 potential alert sources
  - Group interval 30s × repeat 15m = up to 48 messages/hour if things are bad

PROBLEM 4 — No alert inhibition:
  - "ContainerDown" and "PostgreSQLDown" both fire if COREDB goes down
  - But PostgreSQLDown ⇒ many ContainerDown (cascade) — should inhibit children
```

### 8.2 Optimized Alert Routing

```
TIERED ROUTING:

Tier 1 — Critical (page immediately):
  - COREDB PostgreSQL down
  - COREDB Redis down
  - Nginx gateway down
  - >5 containers unhealthy simultaneously
  Route: Discord #war-room + push notification

Tier 2 — Warning (review within 30 minutes):
  - Single container unhealthy
  - High memory usage (>85%)
  - Disk space <10%
  - PM2 process restarted unexpectedly
  Route: Discord #monitoring

Tier 3 — Info (daily digest):
  - Backup completed
  - Rotation completed
  - Deploy completed
  Route: Discord #audit-log

INHIBITION RULES:
  - PostgreSQLDown inhibits all ContainerDown for services depending on it
  - NginxDown inhibits all VirtualHostDown
  - ServerDown inhibits all alerts from that server
```

---

## 9. Distributed Tracing (Future)

### 9.1 Tracing Architecture

```
Implement OpenTelemetry across the Wheeler stack:

1. Auto-instrumentation:
   - PM2 Python services: opentelemetry-instrument (auto)
   - PM2 Node.js services: @opentelemetry/sdk-node (auto)
   - Nginx: opentelemetry module (compiled)

2. Trace Collector:
   - OpenTelemetry Collector as Docker container
   - Export to: ClickHouse (for analytics) + Grafana (for visualization)

3. Trace Context Propagation:
   - W3C Trace Context headers across all HTTP calls
   - Trace IDs injected into logs (Loki) for log-trace correlation
```

### 9.2 Key Trace Queries

```
"Show me the slowest requests to prediction-radar-api in the last hour"
"Trace all requests that resulted in 500 errors"
"What's the time spent in database queries vs. external API calls?"
"Show me the full trace for request_id X that a user reported as slow"
```

---

## 10. Implementation Roadmap

### Phase 1 — Unify Existing (Now)
- [ ] Single Grafana dashboard pulling from both AIOPS and COREDB Prometheus
- [ ] Label standardization across both stacks
- [ ] Pin COREDB monitoring images (currently :latest)
- [ ] Implement synthetic monitoring for critical paths

### Phase 2 — Correlate (Next)
- [ ] Deploy event-bus-relay correlation rules
- [ ] Build unified health dashboard
- [ ] Implement SLO tracking in Grafana
- [ ] Tiered alert routing with inhibition rules

### Phase 3 — Trace (Future)
- [ ] Deploy OpenTelemetry Collector
- [ ] Auto-instrument 5 critical services
- [ ] Log-trace correlation in Loki

### Phase 4 — Predict (Long-term)
- [ ] ML-based anomaly detection on unified metric stream
- [ ] Predictive alerting (alert before failure, not after)
- [ ] Automated incident correlation and root cause suggestion

---

*End of Observability Fusion Plan*
