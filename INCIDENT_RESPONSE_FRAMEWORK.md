# Wheeler Autonomous AI Ops — Incident Response Framework
**Version:** 1.0
**Last Updated:** 2026-05-24
**Governance Engine Integration:** GOVERNANCE_ENGINE.md Section 4.1

---

## 1. Severity Classification System

Incidents are classified across five severity levels. Each level defines the response time, escalation path, auto-remediation posture, and communication requirements. Classification is performed by `/opt/wheeler-ecosystem/scripts/severity-classifier.sh` which accepts structured alert input and returns severity, escalation flag, auto-approval flag, and max response time.

### 1.1 Severity Levels

```
SEV5 / INFO     — Minor anomaly, no user impact, auto-resolved
SEV4 / WARN     — Degraded non-critical service, auto-remediation attempted
SEV3 / HIGH     — Critical service degraded, requires verification after auto-fix
SEV2 / CRITICAL — Multi-service failure, manual approval required for remediation
SEV1 / EMERGENCY — Ecosystem-wide outage, full incident response protocol
```

### 1.2 Severity Classification Table

| Level | Label | Response Time | Auto-Remediation | Escalation | Example |
|-------|-------|--------------|-----------------|------------|---------|
| SEV5 | INFO | Best-effort | Full auto (silent) | None | Single health check flapping, transient error in logs |
| SEV4 | WARN | < 60 min | Auto-attempt, log result | Slack channel only | Disk usage > 75%, cert expires > 30 days, single PM2 restart |
| SEV3 | HIGH | < 30 min | Auto-fix with verification | Slack + Discord notification | Service degraded but not down, API error rate > 5% |
| SEV2 | CRITICAL | < 15 min | Auto-fix for safe actions only | Slack + Discord + war-room | Core DB connection loss, multi-service failure, OOM kill |
| SEV1 | EMERGENCY | < 5 min | Blocked (human only) | Full incident response | Ecosystem-wide outage, security breach, secret leak |

### 1.3 Alert Type to Severity Mapping (from severity-classifier.sh)

The following mapping is enforced by the severity classifier. These rules are the single source of truth for severity assignment:

| Alert Type | Severity | Auto-Approved | Max Response (min) |
|-----------|----------|--------------|-------------------|
| `pm2_restart_storm_critical`, `restart_storm`, `death_loop` | SEV1 | No | 5 |
| `non_loopback_bind` | SEV1 | No | 10 |
| `jlist_secret_leak` | SEV1 | No | 5 |
| `oom_kill` | SEV1 | No | 5 |
| `dead_mans_switch`, `heartbeat_stale` | SEV1 | No | 5 |
| `api_down`, `service_stopped`, `docker_unhealthy` | SEV2 | Yes (non-core) | 30 |
| `postgresql_down`, `redis_down` | SEV2 | No | 15 |
| `pm2_high_memory`, `memory_high`, `cpu_high` | SEV2 | Yes | 60 |
| `node_exporter_down`, `container_down` | SEV2 | No | 30 |
| `cert_expiring_critical` | SEV2 | No | 60 |
| `disk_high`, `disk_full`, `memory_full` | SEV3 | No | 240 |
| `cert_expiring_soon`, `docker_exited`, `docker_latest_images` | SEV3 | Yes | 240 |
| `filesystem_fillup`, `api_error` | SEV3 | Yes | 240 |

### 1.4 Severity Override Rules

The classifier enforces hard overrides regardless of primary classification:

1. **Any alert with "critical" in the name** — minimum SEV2
2. **Any alert matching secret patterns** — always SEV1, escalation=true, auto_approve=false
3. **Unknown alert type from critical sources** (frgcrm-api, litellm, prometheus, alertmanager) — defaults to SEV2

### 1.5 Alert JSON Input Format

Alerts are passed to the severity classifier as JSON:

```json
{
  "alert": "frgcrm-api-down",
  "type": "api_down",
  "source": "frgcrm-api",
  "message": "HTTP 500 on /health for 90 seconds",
  "timestamp": "2026-05-24T10:30:00Z",
  "metrics": { "error_rate": 1.0, "latency_p99": 5000 }
}
```

---

## 2. Alert Correlation Engine

The correlation engine at `/opt/wheeler-ecosystem/scripts/alert-correlation.sh` ingests alerts from all four monitoring sources and groups them into root causes vs. symptoms. This prevents alarm fatigue and ensures responders address the underlying cause, not downstream symptoms.

### 2.1 Causality Map

The correlation engine maintains a known dependency map. When multiple alerts arrive, the engine identifies which service failures cause downstream failures:

```
Root Cause              → Affected Downstream Services
─────────────────────────────────────────────────────
coredb-postgres         → frgcrm-api, surplusai-api, litellm, surplusai-portal-api
coredb-redis            → event-bus-relay, voice-agent-svc, war-room-server
coredb-pg               → frgcrm-api, surplusai-api, litellm
aiops-node              → disk_full, memory_full, high_memory
pushgateway             → pm2_exporter, cert_exporter, ecosystem_exporter, dead_mans_switch
```

### 2.2 Correlation Sources

The engine aggregates from four monitoring channels:

| Source | Tool | Endpoint | Poll Interval | Data Format |
|--------|------|----------|--------------|-------------|
| Prometheus Alerts | aiops-prometheus (127.0.0.1:9090) | /api/v1/alerts | 15s | JSON alert objects |
| Loki Log Patterns | aiops-loki (127.0.0.1:3100) | /loki/api/v1/query_range | 30s | LogQL queries |
| Uptime Kuma Checks | uptime-kuma (127.0.0.1:3001) | API push | 60s | HTTP status codes |
| Health Check Scripts | functional-healthcheck.sh | HTTP endpoints | 5 min | Exit code + output |

### 2.3 Correlation Algorithm

```
1. COLLECT: Gather all active alerts from Prometheus, Loki, Uptime Kuma, and health checks
2. GROUP: Group by alert source (service name)
3. MAP: For each source, look up downstream dependencies in CAUSALITY map
4. CLASSIFY:
   - Source with downstream alerts active → ROOT CAUSE
   - Source whose upstream dependency has active alerts → SYMPTOM
   - Orphan source (no dependency chain) → INDEPENDENT ISSUE
5. PRIORITIZE: Sort root causes by number of downstream services affected
6. CONFIDENCE: correlation_confidence = min(1.0, root_causes / total_alerts * severity_factor)
7. RECOMMEND: "Fix root causes first. Symptoms resolve automatically."
```

### 2.4 Correlation Output

```json
{
  "root_causes": [
    {"source": "coredb-postgres", "alerts": 3, "types": ["connectivity", "down"]}
  ],
  "symptoms": [
    {"source": "frgcrm-api", "likely_caused_by": "coredb-postgres", "alerts": 2}
  ],
  "correlation_confidence": 0.85,
  "total_alerts": 8,
  "unique_sources": 5,
  "recommendation": "Focus on root causes first. Fixing the root will resolve downstream symptoms."
}
```

### 2.5 False Green Detection Integration

The correlation engine cross-references PM2 "online" status with actual HTTP health responses. This detects False Greens (documented in `/root/NO_FALSE_GREENS_REPORT.md`) where:

- PM2 says "online" but HTTP health endpoint returns 500 → FG-1 pattern (frgcrm-api)
- Docker says "healthy" but service has placeholder secrets → FG-9 pattern (superset)
- PM2 says "online" but downstream dependency unreachable → FG-6 pattern (event-bus-relay)

### 2.6 Multi-Source Alert Lifecycle

```
Prometheus Alert Fires → severity-classifier.sh → correlation engine → Alertmanager
                                                    ↓
Uptime Kuma Check Fails → severity-classifier.sh → correlation engine → Alertmanager
                                                    ↓
Loki Log Spike Detected → severity-classifier.sh → correlation engine → Alertmanager
                                                    ↓
Health Check Returns FAIL → severity-classifier.sh → correlation engine → Alertmanager
```

---

## 3. Incident Lifecycle

Every incident follows a defined lifecycle. The lifecycle transitions are tracked in `/var/log/wheeler/self-healing.log` for automated incidents and in the war-room for manual incidents.

### 3.1 Lifecycle Stages

```
DETECTION → TRIAGE → CONTAINMENT → REMEDIATION → RECOVERY → POSTMORTEM
    |          |            |            |           |            |
    v          v            v            v           v            v
  Alert     Classify    Stop the    Fix root    Verify     Document
  arrives   severity    bleeding    cause       health     prevent
```

### 3.2 Stage 1: Detection (T+0)

Detection sources and their trigger conditions:

| Detection Source | Mechanism | Trigger |
|-----------------|-----------|---------|
| Prometheus Alertmanager (127.0.0.1:9093) | Alert rule evaluation | Alert fires with severity label |
| Uptime Kuma (127.0.0.1:3001) | HTTP health check failure | Monitored endpoint returns non-200 |
| loki log pattern (127.0.0.1:3100) | LogQL anomaly query | Error rate exceeds threshold |
| cron health checks | Script execution | Exit non-zero, output to log |
| dead-mans-switch | Absence of expected signal | No heartbeat for 2x interval |
| ecosystem-guardian (PM2) | Process monitoring | PM2 process status changes |

Detection creates the initial incident record:

```json
{
  "incident_id": "INC-20260524-001",
  "detected_at": "2026-05-24T10:30:00Z",
  "source": "prometheus",
  "alert_name": "frgcrm-api-down",
  "initial_severity": "SEV2",
  "summary": "frgcrm-api returning HTTP 500 for 90 seconds"
}
```

### 3.3 Stage 2: Triage (T+2 min)

Upon detection, the system executes:

```bash
# Phase 1 — Parallel diagnostic commands (from incident-response skill)
docker ps --format '{{.Names}} {{.Status}}' | grep -v healthy
pm2 list | grep -v online
tail -100 /var/log/syslog | grep -iE 'error|fail|critical|oom'

# Phase 2 — Correlation
cat alerts.json | /opt/wheeler-ecosystem/scripts/alert-correlation.sh

# Phase 3 — Severity classification
/opt/wheeler-ecosystem/scripts/severity-classifier.sh --alert-name "$alert" --alert-type "$type" --source "$source"

# Phase 4 — Approval gate check
/opt/wheeler-ecosystem/scripts/auto-approval-gate.sh --severity "$sev" --action "$action" --target "$target"
```

### 3.4 Stage 3: Containment (T+5 min)

Containment strategies per service class:

| Service Class | Containment Action | Script |
|--------------|-------------------|--------|
| Docker container | Restart unhealthy container | `docker restart <name>` |
| PM2 process | Restart stopped process | `pm2 restart <name>` |
| Exposed port | Re-bind to 127.0.0.1 | `docker compose up -d <svc>` |
| Memory spike | Increase resource limit | `docker update --memory <limit> <container>` |
| Disk full | Rotate logs, clean temp | `journalctl --vacuum-time=3d` |
| Security breach | Isolate container | `docker network disconnect bridge <container>` |

### 3.5 Stage 4: Remediation (T+varies)

Remediation is governed by the auto-approval gate (`/opt/wheeler-ecosystem/scripts/auto-approval-gate.sh`). See Section 7 for the full approval matrix.

Remediation patterns mapped to known failure modes:

**Pattern A: PM2 Crash (no config change)**
```bash
# If config/code unchanged → plain restart preserves clean state
pm2 restart <name>
pm2 save --force
# Verify
pm2 jlist | python3 -c "import json,sys; data=json.load(sys.stdin); [print(f'{p[\"name\"]}: {p[\"pm2_env\"][\"status\"]}') for p in data if p['name']=='<name>']"
```

**Pattern B: PM2 Crash (config changed)**
```bash
# env -i delete+start pattern required (from pm2-env-i-pattern.md)
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 delete <name>
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 start <config> --only <name>
pm2 save --force
```

**Pattern C: Docker Unhealthy**
```bash
# Check logs first
docker logs --tail 50 <container>
# Restart
docker restart <name>
# Verify
docker inspect <name> --format '{{.State.Health.Status}}'
```

**Pattern D: Docker OOM Restart Loop**
```bash
# Increase memory limit
docker update --memory <new_limit> --memory-swap <new_limit> <container>
# Verify
docker inspect <name> --format '{{.HostConfig.Memory}}'
```

### 3.6 Stage 5: Recovery (T+fix+5 min)

Post-remediation verification follows the Zero False Green policy (from `/root/.claude/skills/no-false-greens/SKILL.md`):

```bash
# Verify with actual command output (not inferred)
EVIDENCE_LEVEL="CONFIRMED"
COMMAND="curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:<port>/health"
EXIT_CODE=$?
OUTPUT=$(curl -s http://127.0.0.1:<port>/health)
echo "VERIFICATION: Command=$COMMAND Exit=$EXIT_CODE Output=$OUTPUT"

# Re-run full health check
/opt/wheeler-ecosystem/scripts/functional-healthcheck.sh | tail -5
```

### 3.7 Stage 6: Postmortem (within 24h)

Postmortem artifacts are created in the war-room server (port 8100) and stored at `/var/log/wheeler/postmortems/`. Template documented in Section 9.

---

## 4. Escalation Workflows

### 4.1 SEV1/Emergency Escalation

```
T+0     Alert fires → severity-classifier.sh determines SEV1
T+1     auto-approval-gate.sh DENIES auto-remediation
T+2     Incident record created in war-room (127.0.0.1:8100)
T+3     Discord webhook: @here EMERGENCY with incident details
T+4     Slack #alerts-critical: full incident summary
T+5     command-center (PM2) notified for manual response
T+10    If no acknowledgment → SMS/call escalation (future: PagerDuty integration)
```

### 4.2 SEV2/Critical Escalation

```
T+0     Alert fires → severity-classifier.sh determines SEV2
T+1     auto-approval-gate.sh evaluates action:
          → Safe action (restart, start, reload on non-critical target) → AUTO-APPROVED
          → Dangerous action (delete, force, secret-related) → DENIED, human required
          → Critical target (prometheus, postgres, frgcrm-api) → DENIED, human required
T+2     If denied: Discord notification sent, war-room incident created
T+15    If not resolved by auto-remediation → escalate to SEV1
```

### 4.3 SEV3/High Escalation

```
T+0     Alert fires → severity-classifier.sh determines SEV3
T+1     auto-approval-gate.sh AUTO-APPROVES safe actions
T+2     Self-healing engine executes remediation
T+5     Verification runs
T+10    If remediation fails 3x in 10 minutes → escalate to SEV2
```

### 4.4 SEV4/SEV5 Escalation

```
T+0     Auto-remediation executes (silent for SEV5, logged for SEV4)
T+5     If resolved: incident closed, metrics pushed to pushgateway
T+max   If persists beyond 60 min → escalate to SEV3
```

### 4.5 Escalation Timers

| Severity | Auto-Remediation Window | Manual Intervention Deadline | Auto-Escalate After |
|----------|------------------------|----------------------------|---------------------|
| SEV5 | Unlimited (silent) | N/A | N/A |
| SEV4 | 60 min | N/A | 60 min (SEV3) |
| SEV3 | 30 min | 60 min | 3 failed auto-attempts |
| SEV2 | 15 min (safe actions only) | 30 min | 15 min (SEV1 if critical DB) |
| SEV1 | Blocked (0 min) | 5 min | N/A (already top level) |

### 4.6 Escalation Channels

| Channel | SEV5 | SEV4 | SEV3 | SEV2 | SEV1 |
|---------|------|------|------|------|------|
| Prometheus Alertmanager (127.0.0.1:9093) | Logged | Alert | Alert | Alert | Alert |
| Loki log (127.0.0.1:3100) | Logged | Logged | Logged | Logged | Logged |
| Discord webhook | No | Yes | Yes | Yes | Yes (@here) |
| Slack #alerts-critical | No | No | No | Yes | Yes |
| War-room incident (127.0.0.1:8100) | No | No | No | Yes | Yes |
| PagerDuty (future) | No | No | No | No | Yes |

---

## 5. Root Cause Analysis Methodology

The Wheeler ecosystem follows a systematic RCA methodology based on the incident-response skill's "Read error → Identify wrong assumption → Find minimal reproduction → Trace to root cause" pattern.

### 5.1 RCA Process

```
STEP 1: Collect ALL available evidence before forming hypothesis
  - PM2 logs: pm2 logs <name> --nostream --lines 100
  - Docker logs: docker logs --tail 100 <container>
  - System logs: journalctl -u docker.service --since "5 min ago"
  - Application logs: /var/log/wheeler/*.log
  - Prometheus metrics: curl http://127.0.0.1:9090/api/v1/query?query=<metric>
  - Loki log query: LogQL at http://127.0.0.1:3100/loki/api/v1/query_range

STEP 2: Build dependency chain
  - Use correlation engine to map upstream/downstream relationships
  - Identify which service failed FIRST (not which is "most broken")
  - Check for cascading failures (service A fails → B fails → C fails)

STEP 3: Formulate and test hypotheses
  - Hypothesis: "PostgreSQL connection pool exhausted"
  - Test: Check pg_stat_activity, connection count, pool configuration
  - Accept or reject based on EVIDENCE (NOT assumption)

STEP 4: Identify contributing factors
  - Configuration drift (was a config changed recently?)
  - Resource exhaustion (memory, CPU, disk, inodes)
  - Deployment that introduced regression
  - External dependency failure (API, provider)
  - Secret rotation that missed a service

STEP 5: Document root cause
  - Technical cause (what broke)
  - Trigger cause (what started it)
  - Contributing factors (why it was able to break)
  - Systemic issues (why it was not caught)
```

### 5.2 Known Root Cause Patterns

Based on the Wheeler ecosystem's history (documented at `/root/ENFORCEMENT_GAP_ANALYSIS.md` and `/root/NO_FALSE_GREENS_REPORT.md`):

| Pattern | Root Cause | Symptoms | Fix |
|---------|-----------|----------|-----|
| FG-1 | COREDB PostgreSQL connection refused | frgcrm-api HTTP 500, all dependent APIs down | Restart PostgreSQL, verify pg_hba.conf |
| FG-2 | Docker 0.0.0.0 port bind bypasses gateway | Services reachable on public IP | Rebind containers to 127.0.0.1 |
| FG-3/FG-4 | Alertmanager not deployed, Discord bridge missing | Zero alerts delivered | Deploy containers, configure routes |
| FG-5 | Docker iptables DNAT bypasses UFW | UFW says DENY, port still accessible | Set Docker bind to 127.0.0.1 |
| FG-6 | COREDB Redis ECONNREFUSED | event-bus-relay "online" but broken | Restart Redis |
| FG-7 | Missing HEALTHCHECK on loki | Silent log ingestion failure | Add HEALTHCHECK to loki compose |
| FG-9 | Placeholder SUPERSET_SECRET_KEY | Forgeable session cookies | Rotate to unique secret |
| FG-12 | ravyn-agent-svc on [::]:8005 | Service reachable on IPv6 wildcard | Rebind to 127.0.0.1 |

### 5.3 RCA Assist Script

The RCA assistant at `/opt/wheeler-ecosystem/scripts/rca-assistant.sh` automates evidence collection:

```bash
# Usage: rca-assistant.sh --incident <id> --service <name>
/opt/wheeler-ecosystem/scripts/rca-assistant.sh --service frgcrm-api --incident INC-20260524-001
```

This script collects: PM2 logs, Docker logs, system logs, Prometheus metrics for the last 30 minutes, Loki log queries, and recent config changes from the drift detector.

---

## 6. War Room Integration

The war-room server runs as a PM2 process on port 8100 (PM2 name: `war-room-server`, config: `/opt/apps/war-room/ecosystem.config.js`). It serves as the central incident command console.

### 6.1 War Room Capabilities

| Capability | Endpoint | Description |
|-----------|----------|-------------|
| Incident Dashboard | http://127.0.0.1:8100/ | Active incidents, severity, timeline |
| Incident Create | POST /incidents | Create new incident record |
| Incident Update | PUT /incidents/:id | Update status, severity, notes |
| Timeline | GET /incidents/:id/timeline | Full event history |
| Postmortem | POST /incidents/:id/postmortem | Submit post-incident review |
| Metrics | GET /metrics | Currently healthy: 20/20 endpoints |

### 6.2 War Room Integration Points

```
command-center (PM2, port 8100)
  └── Pushes: Incident notifications to Discord webhook
  └── Pushes: Escalation alerts to Slack #alerts-critical
  └── Receives: Alertmanager webhook at /webhook/alertmanager
  └── Receives: Manual incident creation from operator

ecosystem-guardian (PM2, port 6399)
  └── Watches: All 19 PM2 processes
  └── Reports: Status changes to war-room
  └── Triggers: Self-healing engine on process failure

event-bus-relay (PM2, port 6399)
  └── Bridges: Alerts between war-room and ecosystem-guardian
  └── Routes: Incident events to subscribers
```

### 6.3 War Room Incident View

```
INCIDENT: INC-20260524-001
────────────────────────────────────────
TITLE:    frgcrm-api — HTTP 500 (COREDB PostgreSQL down)
SEVERITY: SEV2 (CRITICAL)
STATUS:   [CONTAINING]
SERVICE:  frgcrm-api (port 8082)
SOURCE:   Prometheus alert "frgcrm-api-down"
DURATION: 4 min 30s
────────────────────────────────────────
TIMELINE:
  T+0     Alert fired (error_rate=1.0 for 90s)
  T+1     severity-classifier.sh → SEV2
  T+2     auto-approval-gate.sh → DENIED (critical target: frgcrm-api)
  T+3     Incident created in war-room
  T+4     Discord notification sent (#alerts-critical)
────────────────────────────────────────
ROOT CAUSE ANALYSIS:
  Correlated alerts: frgcrm-api (500), surplusai-api (connection error)
  Upstream dependency: coredb-postgres (100.118.166.117:5432)
  Likely root: PostgreSQL connection refused
────────────────────────────────────────
CURRENT:  Awaiting manual approval to investigate COREDB PostgreSQL
NEXT:     Approve → check pg_hba.conf → restart PostgreSQL
OWNER:    AUTO (unclaimed)
────────────────────────────────────────
```

---

## 7. Auto-Remediation Approval Matrix

The auto-approval gate (`/opt/wheeler-ecosystem/scripts/auto-approval-gate.sh`) enforces strict rules on what can be remediated without human approval. This matrix is the canonical reference.

### 7.1 Action Classification

DANGEROUS actions are NEVER auto-approved at any severity level:

| Dangerous Action Pattern | Reason Blocked |
|-------------------------|----------------|
| `delete`, `rm`, `drop`, `purge` | Destructive — data loss risk |
| `--force`, `kill -9` | Force operations bypass safety |
| `iptables`, `ufw` | Network security — manual review required |
| `docker rm`, `docker system prune` | Container destruction |
| `pm2 delete`, `pm2 kill`, `pm2 reset` | Process destruction |
| `chmod 777` | Security downgrade |
| `secret`, `rotate` | Secret operations — orchestrated separately |
| `truncate`, `vacuum`, `reindex` | Database operations — can cause performance impact |

### 7.2 Critical Target Safelist

The following targets are NEVER auto-remediated for SEV2 (require human approval):

| Target | Reason |
|--------|--------|
| `prometheus` | Central metrics — blind without it |
| `alertmanager` | Central alerting — silence without it |
| `grafana` | Dashboard visibility |
| `loki` | Log aggregation |
| `coredb`, `postgres`, `redis`, `postgresql` | Data tier — corruption risk |
| `frgcrm-api` | Primary business API |
| `litellm` | AI model gateway — all agents depend on it |
| `nginx`, `gateway` | Security perimeter |

### 7.3 Auto-Approval Decision Matrix

| Severity | Target Class | Action Class | Auto-Approved? |
|----------|-------------|--------------|---------------|
| SEV1 | Any | Any | NO (exception: dead-mans-switch heartbeat restart) |
| SEV2 | Critical (safelisted) | Any | NO |
| SEV2 | Non-critical | Dangerous | NO |
| SEV2 | Non-critical | Safe (restart/start/reload) | YES |
| SEV3 | Any | Dangerous | NO |
| SEV3 | Any | Safe | YES |
| SEV4 | Any | Safe | YES |
| SEV5 | Any | Any | YES (silent) |

### 7.4 Safety Valve

The self-healing engine (`/opt/wheeler-ecosystem/scripts/self-healing-engine.sh`) implements a safety valve to prevent remediation loops:

```
SAFETY_LIMIT=3   (max repairs in window)
SAFETY_WINDOW=600 (10 minutes in seconds)

If more than 3 repairs attempted in 10 minutes:
  → SAFETY VALVE ENGAGED
  → All auto-remediation stops
  → Metric: healing_safety_valve{instance="aiops"} = 1
  → Escalate to manual intervention
  → State recorded in: /var/log/wheeler/healing-state.json
```

### 7.5 Approval Decision Output

```json
{"approved": false, "reason": "SEV1 requires human approval", "severity": "sev1", "action": "restart", "target": "frgcrm-api"}
{"approved": true, "reason": "SEV3 safe action auto-approved", "severity": "sev3", "action": "restart", "target": "design-agent-svc"}
```

---

## 8. Incident Communication Templates

Standardized templates ensure consistent communication across all incidents.

### 8.1 Discord Notification (SEV3+)

```
**[Wheeler Alert] [$SEVERITY]** $INCIDENT_ID
**Service:** $SERVICE_NAME ($PORT)
**Summary:** $SUMMARY
**Status:** $STATUS
**Duration:** $DURATION
**Details:** http://127.0.0.1:8100/incidents/$INCIDENT_ID
```

### 8.2 Slack Notification (SEV2+)

```
:warning: Wheeler Incident — *$INCIDENT_ID*
Severity: *$SEVERITY*
Service: $SERVICE_NAME (port $PORT)
What: $SUMMARY
Detected: $TIMESTAMP
Response time target: $MAX_RESPONSE minutes
War Room: http://127.0.0.1:8100/incidents/$INCIDENT_ID
```

### 8.3 SEV1 Emergency Broadcast

```
:rotating_light: *WHEELER EMERGENCY* :rotating_light:
Incident: $INCIDENT_ID
Severity: SEV1 — EMERGENCY
Summary: $SUMMARY
Impact: Ecosystem-wide ($AFFECTED_SERVICES)
Timeline:
  - T+0: Detected
  - T+5: Auto-remediation BLOCKED (SEV1 requires human approval)
  - T+: Manual response required
Status Page: http://127.0.0.1:3001/status/<monitor-id>
War Room: http://127.0.0.1:8100/incidents/$INCIDENT_ID
```

### 8.4 Incident Resolution Notification

```
✅ *RESOLVED* — $INCIDENT_ID
Service: $SERVICE_NAME
Duration: $DURATION
Root cause: $ROOT_CAUSE
Fix applied: $FIX
Postmortem: http://127.0.0.1:8100/incidents/$INCIDENT_ID/postmortem
```

### 8.5 Health Check Alert (from functional-healthcheck.sh)

```
[Wheeler Health] [$severity] $source: $message
```

---

## 9. Post-Incident Review Process

All SEV1 and SEV2 incidents require a post-incident review within 24 hours. SEV3 incidents may optionally be reviewed.

### 9.1 Postmortem Template

```yaml
---
incident_id: "INC-YYYYMMDD-NNN"
title: "Descriptive title"
severity: SEV1|SEV2|SEV3
date: YYYY-MM-DD
duration_minutes: N

timeline:
  - time: "T+0"
    event: "Alert detected"
    detail: "How it was first noticed"
  - time: "T+5"
    event: "Severity classified"
    detail: "Classified as X, rationale"
  - time: "T+N"
    event: "Remediation started"
    detail: "What was done"
  - time: "T+N"
    event: "Recovery confirmed"
    detail: "Evidence of recovery"
  - time: "T+N"
    event: "Incident closed"
    detail: "Final status"

root_cause:
  technical: "What broke at the code/config level"
  trigger: "What initiated the failure"
  contributing:
    - "Factor 1 (e.g., no resource limits)"
    - "Factor 2 (e.g., missing healthcheck)"
  systemic: "Why detection/prevention missed it"

resolution:
  immediate: "What was done to restore service"
  verification: "Evidence that fix worked"
  evidence_level: CONFIRMED|INFERRED
  verification_command: "exact command run"
  verification_output: "key output lines"

prevention:
  - action: "Specific change to prevent recurrence"
    owner: "Team member or auto-remediation"
    due: YYYY-MM-DD
    type: monitoring|config|code|process

action_items:
  - item: "Specific, measurable action"
    owner: "Assignee"
    due: YYYY-MM-DD
    status: open|in_progress|done

lessons_learned:
  - "What went well"
  - "What went wrong"
  - "What to do differently next time"

blameless: true
reviewed_by: []
---
```

### 9.2 Postmortem Storage

Postmortem documents are stored at:
- `/var/log/wheeler/postmortems/INC-YYYYMMDD-NNN.md`
- War room API: POST /incidents/:id/postmortem

### 9.3 Postmortem Review Cadence

| Incident Type | Review Required | Review Window | Approver |
|--------------|----------------|---------------|----------|
| SEV1 | Yes | 12 hours | Full incident review board |
| SEV2 | Yes | 24 hours | Lead operator |
| SEV3 | Optional | 48 hours | Service owner |
| SEV4/SEV5 | No | N/A | N/A |

### 9.4 Prevention Tracking

Action items from postmortems are tracked in the ecosystem graph (Neo4j at `127.0.0.1:7687`):

```cypher
MATCH (i:Incident {id: 'INC-20260524-001'})-[:HAS_ACTION]->(a:ActionItem)
WHERE a.status <> 'done'
RETURN i.title, a.item, a.owner, a.due
ORDER BY a.due ASC
```

---

## 10. Integration with Existing Monitoring

### 10.1 Prometheus Alert Rules Integration

Alertmanager at `127.0.0.1:9093` receives alerts from `aiops-prometheus` (127.0.0.1:9090). The incident response framework processes alerts through this pipeline:

```
Prometheus Alert Rule Fires
  → Alertmanager Receives (webhook receiver)
  → severity-classifier.sh (severity + auto-approval decision)
  → correlation engine (group by source, identify root causes)
  → If SEV3+: Remediation triggered via self-healing-engine.sh
  → If SEV2+: Incident created in war-room
  → If SEV1: Manual intervention required
```

### 10.2 Uptime Kuma Monitor Integration

Uptime Kuma at `127.0.0.1:3001` monitors HTTP endpoints for all 20 services. The monitors map to the health check endpoints defined in `/opt/wheeler-ecosystem/scripts/functional-healthcheck.sh`:

| Monitor | URL | Expected Status | Check Interval |
|---------|-----|----------------|----------------|
| frgcrm-api | http://127.0.0.1:8082/health | 200 | 60s |
| surplusai-api | http://127.0.0.1:8103/docs | 200 | 60s |
| litellm | http://127.0.0.1:4049/health | 200/401 | 60s |
| war-room | http://127.0.0.1:8091/ | 200 | 60s |
| openclaw-dash | http://127.0.0.1:8110/ | 200 | 60s |
| ravyn-agent | http://127.0.0.1:8005/health | 200 | 60s |
| frgcrm-agent | http://127.0.0.1:8003/health | 200 | 60s |
| horizon-agent | http://127.0.0.1:8006/health | 200 | 60s |
| surplusai-agent | http://127.0.0.1:8009/health | 200 | 60s |
| voice-agent | http://127.0.0.1:8008/health | 200 | 60s |
| paperless-agent | http://127.0.0.1:8007/health | 200 | 60s |
| pred-radar-agent | http://127.0.0.1:8011/health | 200 | 60s |
| insforge-agent | http://127.0.0.1:8013/health | 200 | 60s |
| design-agent | http://127.0.0.1:8020/health | 200 | 60s |
| prometheus | http://127.0.0.1:9090/-/healthy | 200 | 30s |
| alertmanager | http://127.0.0.1:9093/-/healthy | 200 | 30s |
| grafana | http://127.0.0.1:3002/api/health | 200 | 60s |
| loki | http://127.0.0.1:3100/ready | 200 | 60s |
| netdata | http://127.0.0.1:19999/api/v1/info | 200 | 60s |
| changedetection | http://127.0.0.1:5000/ | 200 | 60s |

### 10.3 Loki Log Pattern Alerts

Loki at `127.0.0.1:3100` is queried for log pattern anomalies. The incident framework integrates with Loki through:

```logql
# Example: Detect frgcrm-api error rate spike over 5 minutes
sum(rate({job="frgcrm-api"} |= "ERROR" [5m])) by (level) > 0.1

# Example: Detect PM2 restart loops
count_over_time({job="pm2"} |= "restart" [10m]) > 5

# Example: Detect Docker OOM kills
{job="docker"} |= "OOM" | logfmt
```

### 10.4 Dead Man's Switch

The dead man's switch at `/opt/wheeler-ecosystem/scripts/dead-mans-switch.sh` provides meta-monitoring — if the health check system itself fails, this alerts through a separate channel:

```bash
# Pushed to Pushgateway at configurable interval
echo "dead_mans_switch 1" | curl -s --data-binary @- http://127.0.0.1:9092/metrics/job/dead_mans_switch/instance/aiops

# If this metric is absent for 2x the push interval:
#   → SEV1 alert (the monitoring system itself has failed)
#   → Auto-remediation BLOCKED (SEV1) — human must investigate
```

### 10.5 Integration with ecosystem-guardian

The ecosystem-guardian PM2 process runs as part of the Wheeler Brain OS and monitors all PM2 process states. It feeds into the incident response framework:

```
ecosystem-guardian
  └── Watches: All PM2 process statuses
  └── On process stop: Triggers self-healing
  └── On restart loop: Triggers SEV1 escalation
  └── Reports: Pushgateway metrics at 127.0.0.1:9092
```

Ecosystem guardian config: `/opt/apps/wheeler-brain-os/ecosystem.config.js`

### 10.6 Metrics Pushgateway

All incident metrics are pushed to the Pushgateway at `127.0.0.1:9092` (container `aiops-pushgateway`):

| Metric | Source | Description |
|--------|--------|-------------|
| `healing_actions_total` | self-healing-engine.sh | Total remediation actions |
| `healing_successes_total` | self-healing-engine.sh | Successful remediations |
| `healing_failures_total` | self-healing-engine.sh | Failed remediations |
| `healing_safety_valve` | self-healing-engine.sh | Safety valve engaged (0/1) |
| `auto_approval_decisions_total` | auto-approval-gate.sh | Approved/blocked decisions |
| `config_drift_detected` | config-drift-detector.sh | Drift found (0/1) |
| `config_drift_items` | config-drift-detector.sh | Number of drift items |
| `dead_mans_switch` | dead-mans-switch.sh | Monitoring heartbeat (0/1) |

---

*End of Incident Response Framework. Integrates with `/root/.claude/skills/incident-response/SKILL.md`, `/root/.claude/skills/slay/SKILL.md`, and `/root/.claude/skills/no-false-greens/SKILL.md`.*
