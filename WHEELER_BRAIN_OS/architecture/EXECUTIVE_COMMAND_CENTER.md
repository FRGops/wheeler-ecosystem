# Wheeler Brain OS — Executive Command Center

## 1. Overview

The Executive Command Center is the operational nerve center of Wheeler Brain OS — a unified dashboard that answers "how is the ecosystem doing right now?" in a single glance. It serves three distinct audiences at different depth levels: the CEO (strategic), the Operator (tactical), and the AI (autonomous).

### Design Motto

```
"Don't make me check 8 dashboards to know if we're healthy."
```

---

## 2. Audience Views

### 2.1 CEO View (Strategic)

```
Frequency: Weekly review or on-demand
Questions it answers:
  - Are all revenue systems healthy?
  - What's our compliance score?
  - What risks need attention?
  - What's changed since last week?

Display: High-level KPI cards + trend lines + top 5 recommendations
Alert threshold: Only revenue-impacting or critical security issues
```

### 2.2 Operator View (Tactical)

```
Frequency: Daily or during incidents
Questions it answers:
  - What's broken right now?
  - What's about to break?
  - What changed in the last hour?
  - Where do I click to fix it?

Display: Real-time topology map + alert feed + recent events + action buttons
Alert threshold: All warnings and criticals
```

### 2.3 AI View (Autonomous)

```
Frequency: Continuous (every 60s)
Questions it answers:
  - What drift has occurred?
  - What needs auto-healing?
  - What patterns match known incidents?
  - What's the confidence level?

Display: Structured event stream + anomaly scores + remediation queue
Alert threshold: Everything that deviates from desired state
```

---

## 3. Dashboard Layout

### 3.1 CEO View Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  WHEELER ECOSYSTEM COMMAND                    May 24, 2026 08:15 │
│                                                          [REFRESH]│
├──────────┬──────────┬──────────┬──────────┬──────────┬──────────┤
│ SERVERS  │CONTAINERS│   PM2    │ REVENUE  │SECURITY  │COMPLIANCE│
│   2/2    │  58/58   │  17/18   │  100%    │  NO OPEN │   89%    │
│  ONLINE  │ HEALTHY  │  ONLINE  │    UP    │ CRITICAL │  ▲ 4%    │
└──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
┌──────────────────────────────┬───────────────────────────────────┐
│                              │                                   │
│  ECOSYSTEM HEALTH TREND      │  TOP RECOMMENDATIONS              │
│  (30-day)                    │                                   │
│  ┌──────────────────────┐    │  1. Enable UFW on COREDB      ↑  │
│  │ ▁▂▃▄▅▆▇███▇▆▅▄▃▂▁   │    │     No firewall on DB server      │
│  │ Health trending up ▲ │    │                                   │
│  └──────────────────────┘    │  2. Automate COREDB backups   ↑  │
│                              │     No backup for primary DB      │
│  REVENUE SYSTEMS             │                                   │
│  ┌──────────────────────┐    │  3. Pin 11 :latest images     ↑  │
│  │ prediction-radar  ✓  │    │     Version skew risk on COREDB   │
│  │ usesend (CRM)     ✓  │    │                                   │
│  │ voice-outreach    ✓  │    │  4. Add git remotes           ↑  │
│  └──────────────────────┘    │     2 repos have no off-machine   │
│                              │                                   │
│  ACTIVE INCIDENTS            │  5. Rotate external API keys  ↑  │
│  ┌──────────────────────┐    │     60+ keys past rotation date   │
│  │ ✓ No active incidents│    │                                   │
│  │ 14 days clean        │    └───────────────────────────────────┘
│  └──────────────────────┘
└──────────────────────────────┴───────────────────────────────────┘
┌──────────────────────────────────────────────────────────────────┐
│  RESOURCE UTILIZATION                                            │
│  AIOPS: ████████░░ 47% RAM (14/30GB)  ██░░░░░░░░ 19% DISK       │
│  COREDB: █░░░░░░░░░  8% RAM (2.3/30GB) ░░░░░░░░░░  5% DISK       │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 Operator View Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  WHEELER OPERATIONS                           08:15:32 UTC LIVE  │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────────┐ │
│  │SERVERS  │ │CONTAINER│ │PM2 PROCS│ │ ALERTS  │ │ LAST DEPLOY │ │
│  │2/2 UP   │ │58/58 ✓  │ │17/18 ✓  │ │0 crit   │ │ 2h ago  ✓  │ │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └────────────┘ │
├──────────────────────┬───────────────────────────────────────────┤
│                      │                                           │
│  LIVE TOPOLOGY MAP   │  ALERT FEED (24h)                         │
│  (auto-layout from   │  ┌───────────────────────────────────┐    │
│   ecosystem graph)   │  │ 06:15 WARN  Disk AIOPS 82%        │    │
│                      │  │ 05:30 INFO  backup-verify stopped │    │
│  ┌────────────────┐  │  │ 02:00 INFO  daily backup complete │    │
│  │    ╔══════╗    │  │  │ 00:00 INFO  log rotation done     │    │
│  │    ║AIOPS ║    │  │  │          —— No criticals ——      │    │
│  │    ║ 40C  ║    │  │  └───────────────────────────────────┘    │
│  │    ║ 17P  ║    │  │                                           │
│  │    ╚══╤═══╝    │  │  RECENT EVENTS                           │
│  │       │Tailscale│  │  ┌───────────────────────────────────┐    │
│  │    ╔══╧═══╗    │  │  │ 08:14 healthchecks restarted       │    │
│  │    ║COREDB║    │  │  │ 08:10 prometheus alert resolved    │    │
│  │    ║ 19C  ║    │  │  │ 07:55 prediction-radar deploy v3.2 │    │
│  │    ╚══════╝    │  │  │ 07:30 litellm rate limit cleared   │    │
│  └────────────────┘  │  └───────────────────────────────────┘    │
│                      │                                           │
│  QUICK ACTIONS       │  DEPENDENCY HEALTH                        │
│  [Restart] [Logs]    │  ┌───────────────────────────────────┐    │
│  [Health Check]      │  │ LiteLLM ← 9 agents       ✓        │    │
│  [View Config]       │  │ COREDB PG ← 12 services  ✓        │    │
│  [Rollback]          │  │ COREDB Redis ← 3 services ✓       │    │
│                      │  │ Nginx GW ← 16 vhosts    ✓         │    │
│                      │  └───────────────────────────────────┘    │
└──────────────────────┴───────────────────────────────────────────┘
```

### 3.3 Drill-Down: Service Detail (click any service)

```
┌──────────────────────────────────────────────────────────────────┐
│  ← BACK TO OVERVIEW                                              │
│                                                                  │
│  prediction-radar-app                              ✓ HEALTHY     │
│  Stack: /opt/apps/prediction-radar-app/                          │
│  Network: prediction-radar-app_default (172.25.0.0/16)           │
│                                                                  │
│  ┌─────────────────────────┐  ┌─────────────────────────────┐    │
│  │ 14 CONTAINERS           │  │ METRICS (24h)                │    │
│  │                         │  │                              │    │
│  │ api              ✓      │  │ Requests:   142/s avg        │    │
│  │ web              ✓      │  │ p95 latency: 890ms           │    │
│  │ worker           ✓      │  │ Error rate:  0.02%           │    │
│  │ scheduler        ✓      │  │ Memory:      512MB / 1GB     │    │
│  │ db               ✓      │  │ CPU:         0.4 / 1.0       │    │
│  │ redis            ✓      │  │ Uptime:      14d 3h          │    │
│  │ grafana          ✓      │  │                              │    │
│  │ prometheus       ✓      │  └─────────────────────────────┘    │
│  │ alertmanager     ✓      │                                     │
│  │ uptime-kuma      ✓      │  ┌─────────────────────────────┐    │
│  │ dashboard-v2     ✓      │  │ DEPENDENCIES                │    │
│  │ crowdsec         ✓      │  │                              │    │
│  │ fail2ban         ✓      │  │ COREDB PostgreSQL  ✓ (2ms)  │    │
│  │ fincept          ✓      │  │ COREDB Redis       ✓ (1ms)  │    │
│  │ db-backup-1      ✓      │  │ Stripe API         ✓ (120ms)│    │
│  │                         │  │ Polygon API        ✓ (340ms)│    │
│  └─────────────────────────┘  │ Alpaca API         ✓ (90ms) │    │
│                               └─────────────────────────────┘    │
│  ACTIONS:                                                        │
│  [Restart All] [Restart API] [View Logs] [View Config]           │
│  [Scale Memory] [Rollback Deploy] [Declare Incident]             │
└──────────────────────────────────────────────────────────────────┘
```

---

## 4. Command Interface

### 4.1 Natural Language Commands

```
The command center accepts natural language queries:

"Show me everything unhealthy"
  → Filters topology map to 0 unhealthy nodes

"What depends on COREDB PostgreSQL?"
  → Highlights 12 dependent services in topology map

"What changed in the last hour?"
  → Shows event feed for last 60 minutes

"Restart the prediction-radar API"
  → Executes safe restart with pre/post verification

"What's our compliance score?"
  → Shows compliance dashboard with trend

"Are we ready to deploy?"
  → Runs all 7 pre-deployment gates, shows pass/fail

"Take me to the prediction-radar Grafana dashboard"
  → Opens grafana.aiops in context
```

### 4.2 Voice Command Integration (Future)

```
"Wheeler, status report"
  → Reads aloud: "All systems healthy. 58 containers, 17 PM2 processes.
     No active incidents. Compliance at 89%, up 4% from last week."

"Wheeler, what's the alert?"
  → Reads: "Warning: AIOPS disk at 82%. Predicted to reach 90% in 14 days
     at current growth rate. Recommend running log cleanup."

"Wheeler, declare incident"
  → Opens war room, notifies on-call, starts incident timer, captures state
```

---

## 5. Action Framework

### 5.1 One-Click Actions

```
RESTART SERVICE:
  1. Click "Restart" on any service
  2. Confirmation dialog shows blast radius
  3. Pre-flight checks auto-run
  4. Restart executes
  5. Health verification displays in real-time

VIEW LOGS:
  1. Click "Logs" on any service
  2. Last 100 lines streamed from Loki
  3. Filter by: ERROR, WARN, or time range
  4. "Correlate" button finds related events in same time window

ROLLBACK DEPLOY:
  1. Click "Rollback" on recently deployed service
  2. Shows deploy history with timestamps
  3. Select target version
  4. Pre-rollback snapshot captured
  5. Rollback executes with verification

DECLARE INCIDENT:
  1. Click "Declare Incident" (red button, always visible)
  2. Auto-populates with affected services from current alerts
  3. Creates war room channel
  4. Captures full ecosystem state snapshot
  5. Starts incident timer
```

### 5.2 Safety Interlocks

```
CONFIRMATION REQUIRED:
  - Any action affecting >2 services
  - Any action on revenue systems (prediction-radar, usesend)
  - Any action that restarts a database
  - Any action during an active incident

AUTO-APPROVED:
  - View logs, metrics, configs (read-only)
  - Restart single non-revenue container
  - Restart single PM2 process (not in crash loop)
  - Flush non-critical cache
```

---

## 6. Real-Time Data Architecture

### 6.1 Data Sources and Refresh Rates

```
SOURCE                    → REFRESH RATE    → DISPLAY
──────────────────────────────────────────────────────────
Docker health (inspect)    → 10s (poll)     → Container status dots
PM2 status (jlist)         → 10s (poll)     → PM2 process status
Prometheus metrics         → 15s (scrape)   → Metric charts + alerts
Uptime Kuma status         → 60s (poll)     → Uptime percentage
Ecosystem graph (Neo4j)   → 60s (sync)     → Topology map
Loki logs                  → streaming      → Log viewer
Event bus (event-bus-relay) → real-time     → Event feed + alerts
Compliance score           → 5min (cron)    → Compliance dashboard
```

### 6.2 WebSocket Event Stream

```
The command center maintains a WebSocket connection to event-bus-relay:

Events received:
  - container.status.changed  {container, old_status, new_status}
  - pm2.status.changed        {process, old_status, new_status}
  - alert.firing              {alert_name, severity, labels}
  - alert.resolved            {alert_name}
  - deploy.started            {service, version, server}
  - deploy.completed          {service, version, success, duration}
  - heal.executed             {target, action, success}
  - drift.detected            {resource, policy, actual_vs_expected}
  - recommendation.new        {priority, action, impact}

The UI updates without polling — events push state changes.
```

---

## 7. Technology Stack

### 7.1 Implementation

```
FRONTEND:
  Framework: Next.js (consistent with usesend, openclaw-dashboard)
  Visualization: D3.js (topology map), Chart.js (metrics)
  State: WebSocket + React Query (real-time)
  Auth: JWT + basic auth (consistent with nginx)
  Deploy: Docker container, nginx-proxied

BACKEND (extends war-room-server :8091):
  REST API: FastAPI (Python)
  Graph queries: Neo4j Bolt driver
  Real-time: WebSocket via event-bus-relay
  Auth: INTERNAL_API_KEY + JWT

DATA:
  Metrics: Prometheus HTTP API
  Logs: Loki HTTP API
  Graph: Neo4j Bolt
  Events: event-bus-relay WebSocket
```

### 7.2 Deployment

```yaml
# Proposed: /opt/stacks/command-center/docker-compose.yml
services:
  command-center:
    build: /opt/apps/command-center
    container_name: wheeler-command-center
    ports:
      - "127.0.0.1:8100:3000"
    environment:
      - NEO4J_URI=bolt://ecosystem-graph:7687
      - PROMETHEUS_URL=http://127.0.0.1:9090
      - LOKI_URL=http://127.0.0.1:3100
      - EVENT_BUS_URL=ws://127.0.0.1:6399
    mem_limit: 256m
    cpus: 0.5
    cap_drop:
      - ALL
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3000/api/health || exit 1"]

  # Nginx route addition:
  # command.aiops → 127.0.0.1:8100
```

---

## 8. Implementation Phases

### Phase 1 — Static Dashboard (now)
- [ ] Build command center frontend with real data from Docker/PM2 APIs
- [ ] Read-only: status display, topology view, metric charts
- [ ] No actions — view only

### Phase 2 — Interactive (next)
- [ ] Add one-click actions (restart, logs)
- [ ] Add event feed from event-bus-relay
- [ ] Add basic alert integration

### Phase 3 — Intelligent (future)
- [ ] AI recommendations integrated into dashboard
- [ ] Predictive alerts (what's about to break)
- [ ] Natural language command interface

### Phase 4 — Autonomous (long-term)
- [ ] AI-approved actions within bounded authority
- [ ] Voice command integration
- [ ] Mobile push notifications for critical events

---

*End of Executive Command Center Design*
