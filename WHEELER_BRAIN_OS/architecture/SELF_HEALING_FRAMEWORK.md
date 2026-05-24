# Wheeler Brain OS — Self-Healing Framework

## 1. Overview

The Self-Healing Framework detects, diagnoses, remediates, and verifies ecosystem failures automatically. It operates within bounded authority — well-understood failures are healed autonomously; novel or high-risk failures escalate to human operators with diagnostic context.

### The Healing Loop

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  DETECT ──→ DIAGNOSE ──→ REMEDIATE ──→ VERIFY   │
│     ↑                                      │     │
│     └────────────── LEARN ────────────────┘     │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## 2. Authority Model

### 2.1 Healing Tiers

```
TIER 0 — ADVISORY (Human executes):
  New failure patterns, high blast radius, destructive remediation
  Examples: "COREDB PostgreSQL has corruption symptoms. Recommended: pg_restore from backup."
  Action: AI suggests → human decides → human executes

TIER 1 — ASSISTED (Human approves, AI executes):
  Known patterns, medium blast radius, safe remediation
  Examples: "Container X has memory leak. Restart with higher limit? [APPROVE]"
  Action: AI suggests + drafts plan → human approves → AI executes + verifies

TIER 2 — SUPERVISED (AI executes, human reviews within window):
  Well-known patterns, low blast radius, proven remediation
  Examples: Container unhealthy → restart → verify health
  Action: AI executes → AI verifies → human notified → human can override within 5min

TIER 3 — AUTONOMOUS (AI executes, human informed):
  Trivial patterns, no blast radius, routine maintenance
  Examples: Log rotation, cache flush, dead connection cleanup
  Action: AI executes → AI verifies → logged to audit trail
```

### 2.2 Blast Radius Constraints

```
AUTONOMOUS ONLY IF:
  - Blast radius ≤ 2 services (from ecosystem graph)
  - No revenue impact (not prediction-radar, not usesend)
  - No data mutation (read-only or ephemeral state only)
  - Remediation is idempotent (safe to run twice)
  - Successful 10+ times in last 30 days (proven pattern)

HUMAN APPROVAL REQUIRED IF:
  - Blast radius > 2 services
  - Revenue system affected
  - Database mutation involved
  - Remediation involves data loss risk
  - Pattern seen < 3 times before
```

---

## 3. Detection Layer

### 3.1 Detection Sources

```
SOURCE 1 — Docker Healthchecks:
  55/58 containers have healthchecks
  Detection: Container status → "unhealthy"
  Latency: Within healthcheck interval (30s) + retries (3 × 10s) = 60s worst case

SOURCE 2 — PM2 Process Monitor:
  ecosystem-guardian polls PM2 every 60s
  Detection: Process status → "stopped" or "errored" or restart_count spike
  Latency: Within 60s

SOURCE 3 — Prometheus Alerts:
  30s evaluation interval on 6 critical alert rules
  Detection: up == 0, pg_up == 0, redis_up == 0, container metrics missing
  Latency: Within 2 minutes (30s eval + 2m "for" duration)

SOURCE 4 — Uptime Kuma:
  External reachability checks
  Detection: HTTP status != 200 or timeout
  Latency: Within check interval (60s)

SOURCE 5 — Cron Health Scripts:
  docker-healthcheck.sh, pm2-healthcheck.sh, functional-healthcheck.sh
  Detection: Any health check script exits non-zero
  Latency: Within 5 minutes

SOURCE 6 — Synthetic Monitors (to implement):
  Critical path transaction tests
  Detection: User-facing flow broken (not just individual service)
  Latency: Within test interval (5 minutes)
```

### 3.2 Detection Confidence

```
SINGLE SOURCE detection:      confidence = 0.6 (possible transient)
TWO SOURCES agree:             confidence = 0.85 (likely real)
THREE+ SOURCES agree:          confidence = 0.95 (confirmed)

Confidence threshold for action:
  ≥ 0.85 → autonomous remediation (Tier 2-3)
  ≥ 0.60 → alert operator (Tier 0-1)
  < 0.60 → log only, wait for confirmation
```

---

## 4. Diagnosis Layer

### 4.1 Diagnostic Playbooks

```
PLAYBOOK: Container Unhealthy
─────────────────────────────
1. CHECK container logs (last 50 lines):
   docker logs --tail 50 <container>
   → Categorize: OOM? Port conflict? Config error? Dependency down?

2. CHECK resource usage:
   docker stats --no-stream <container>
   → At limit? (mem_limit hit → OOMKilled)

3. CHECK dependencies:
   Query ecosystem graph: DEPENDS_ON → are all healthy?
   → If dependency unhealthy: promote to cascade diagnosis

4. CHECK recent changes:
   Any deploy, restart, or config change in last 15 minutes?
   → If yes: probable regression

5. CLASSIFY failure:
   Known pattern? → Look up playbook
   New pattern? → Escalate to operator with diagnostic summary

PLAYBOOK: PM2 Process Crash Loop
────────────────────────────────
1. CHECK crash count and interval:
   pm2 jlist | jq '.[] | select(.name=="<process>") | .pm2_env.restart_time'
   → Accelerating? (interval decreasing) → resource leak
   → Constant interval → config/secrets error

2. CHECK logs (last 100 lines):
   pm2 logs <process> --lines 100 --nostream
   → "DEEPSEEK_API_KEY" error → check LiteLLM proxy
   → "ECONNREFUSED" → dependency down
   → "out of memory" → memory limit too low

3. CHECK env vars:
   pm2 env <process_id>
   → Any vars empty that shouldn't be?

4. CHECK dependency chain:
   pm2 process → LiteLLM (4049) → DeepSeek API
   pm2 process → Hostinger services (100.98.163.17)
   → Is the dependency reachable?

PLAYBOOK: Database Connection Failure
─────────────────────────────────────
1. CHECK PostgreSQL:
   pg_isready -h 100.118.166.117 -p 5432
   → No: COREDB PostgreSQL down → CRITICAL, full incident response

2. CHECK network:
   ssh -o ConnectTimeout=5 root@100.118.166.117 echo OK
   → No: COREDB server unreachable → CRITICAL

3. CHECK connection pool:
   SELECT count(*) FROM pg_stat_activity;
   → >100 connections: possible connection leak

4. CHECK disk:
   df -h on COREDB
   → >90%: disk pressure → WAL accumulation
```

### 4.2 Automated Root Cause Analysis

```
CASCADE DETECTION ALGORITHM:

1. Collect all alerts/events in last 5 minutes
2. Sort by dependency depth (from ecosystem graph):
   - Layer 0: Physical (server, network)
   - Layer 1: Infrastructure (PostgreSQL, Redis, nginx)
   - Layer 2: Platform (Temporal, LiteLLM, event-bus)
   - Layer 3: Application (agents, APIs, web)
3. Walk from bottom up:
   If Layer 0 node has alert → all Layer 1-3 alerts are symptoms
   If Layer 1 node has alert → all Layer 2-3 alerts are symptoms
4. Root cause = deepest layer with an alert

Example:
  "ContainerDown: prediction-radar-app-api"
  "ContainerDown: prediction-radar-app-web"
  "PostgreSQLDown: wheeler-postgres"
  → Root cause: COREDB PostgreSQL (Layer 1)
  → prediction-radar alerts are symptoms (Layer 3)
```

---

## 5. Remediation Layer

### 5.1 Standard Remediation Playbooks

```
REMEDIATION: Restart Unhealthy Container
────────────────────────────────────────
Tier: 2 (Supervised)
Applies to: Any container with healthcheck failure, not in crash loop
Procedure:
  1. docker stop <container>
  2. Wait 5s
  3. docker start <container>
  4. Wait for healthcheck (up to 60s)
  5. If healthy: success
  6. If still unhealthy after 2 retries: escalate to operator
Rollback: None needed (restart is idempotent)
Safety: docker stop preserves data volumes

REMEDIATION: Recreate Crashed Container
───────────────────────────────────────
Tier: 2 (Supervised)
Applies to: Container that won't start after 2 restart attempts
Procedure:
  1. docker compose down <service>
  2. docker compose up -d <service>
  3. Wait for healthcheck
  4. If healthy: success
  5. If still unhealthy: escalate to operator
Rollback: docker compose down && docker compose up -d (previous state)

REMEDIATION: Restart Crashed PM2 Process
────────────────────────────────────────
Tier: 2 (Supervised)
Applies to: PM2 process in "stopped" or "errored" status
Procedure:
  1. Verify not in crash loop: restart_count < 3 in 5 minutes
  2. Verify dependency health: LiteLLM + external APIs reachable
  3. pm2 restart <process> --update-env
  4. Wait 10s
  5. Verify status = "online" and PID changed
  6. If still "errored" after 2 retries: escalate
Rollback: None (restart is idempotent)

REMEDIATION: Flush Redis Cache (Memory Pressure)
────────────────────────────────────────────────
Tier: 1 (Assisted)
Applies to: Redis memory > 90% of maxmemory
Procedure:
  1. redis-cli INFO memory | grep used_memory_human
  2. redis-cli --bigkeys (identify largest keys)
  3. Suggest: FLUSHDB or specific key eviction
  4. Wait for operator APPROVE (this is data-destructive)
Rollback: None (cache is ephemeral by design)

REMEDIATION: Scale Container Memory Limit
─────────────────────────────────────────
Tier: 1 (Assisted)
Applies to: Container consistently at >85% memory limit with no leak
Procedure:
  1. Calculate new limit: current_limit * 1.5
  2. Update docker-compose.yml: mem_limit: <new_value>
  3. docker compose up -d <service>
  4. Verify healthy with new limit
Rollback: Revert mem_limit in compose file, redeploy
```

### 5.2 Remediation Decision Tree

```
Is this a known pattern?
  ├── YES → Is blast radius ≤ 2 services?
  │         ├── YES → Is remediation proven (10+ successes)?
  │         │         ├── YES → Autonomous (Tier 2-3)
  │         │         └── NO  → Assisted (Tier 1)
  │         └── NO  → Assisted (Tier 1), even if proven
  └── NO  → Is this affecting a revenue system?
             ├── YES → Advisory (Tier 0) — human must decide
             └── NO  → Advisory (Tier 0) with diagnostic context
```

---

## 6. Verification Layer

### 6.1 Remediation Success Criteria

```
VERIFICATION CHECKLIST (run after every remediation):

1. SERVICE HEALTH:
   □ Docker: status = "healthy" for ≥ 2 consecutive checks
   □ PM2: status = "online" for ≥ 30 seconds
   □ HTTP: health endpoint returns 200

2. DEPENDENCY HEALTH:
   □ All DEPENDS_ON services still healthy
   □ No new alerts fired during verification window

3. FUNCTIONAL CHECK:
   □ For APIs: curl basic endpoint, verify 200 + valid response
   □ For agents: check next polling cycle completed successfully
   □ For databases: run connectivity test query

4. BASELINE COMPARISON:
   □ CPU within 20% of pre-incident baseline
   □ Memory within 20% of pre-incident baseline
   □ Request rate within 50% of pre-incident baseline (allow for catch-up)

VERIFICATION WINDOW:
  Tier 3 (autonomous): 60 seconds
  Tier 2 (supervised):  120 seconds
  Tier 1 (assisted):    300 seconds (operator may want extended observation)
  Tier 0 (advisory):    Operator-defined
```

### 6.2 Rollback Triggers (Auto-Undo)

```
If any of these occur during verification window:
  → Auto-rollback to pre-remediation state

  - Container healthcheck fails 2 consecutive times
  - New critical alert fires
  - Error rate exceeds 2x baseline
  - Memory usage exceeds new limit within 60 seconds
  - PM2 process restarts within 30 seconds of remediation
```

---

## 7. Current Healing Infrastructure

### 7.1 Existing Auto-Healing

```
ALREADY IN PLACE:

cron: autoheal.sh (every 2 minutes):
  - Restarts stopped Docker containers
  - Restarts crashed PM2 processes
  - Verifies service health post-restart
  - Logs all actions to /var/log/wheeler-autoheal.log

cron: wheeler-lockdown-watchdog.sh (every 5 minutes):
  - Verifies port bindings haven't changed
  - Verifies UFW rules haven't changed
  - Restores lockdown if drift detected

Docker restart policy:
  - All containers: restart: unless-stopped
  - Docker daemon handles crash recovery

PM2 autorestart:
  - All processes: autorestart: true
  - Max 10 retries, 5s delay
  - PM2 handles crash recovery at process level
```

### 7.2 Healing Gaps

```
NOT YET AUTOMATED:

- Cascade diagnosis: Root cause identification still manual
- Cross-server healing: COREDB issues detected but not auto-healed from AIOPS
- Memory leak response: Detected (Prometheus) but not auto-mitigated
- Disk pressure response: Detected but not auto-cleaned
- Backup recovery: No automated restore testing
- Agent blind spot: If LiteLLM goes down, 9 agents go blind — no auto-failover to direct API
```

---

## 8. Learning System

### 8.1 Incident Knowledge Base

```
Every incident is recorded with:
  - Detection: What triggered the alert? What was the latency?
  - Diagnosis: What was the root cause? How was it identified?
  - Remediation: What action was taken? Was it successful?
  - Verification: How was success confirmed?
  - Classification: Is this a new pattern or a repeat?

This builds a training corpus that:
  1. Improves automated diagnosis accuracy over time
  2. Promotes proven remediations from Tier 1 → Tier 2 → Tier 3
  3. Identifies systemic issues (same service failing repeatedly)
```

### 8.2 Pattern Promotion

```
PATTERN LIFECYCLE:

Discovery:     New failure pattern observed → Tier 0 (Advisory)
Validation:    Same pattern + same fix worked 3 times → Tier 1 (Assisted)
Proven:        Same pattern + same fix worked 10 times → Tier 2 (Supervised)
Trusted:       Same pattern + same fix worked 50 times, 0 regressions → Tier 3 (Autonomous)
```

---

## 9. Implementation Roadmap

### Phase 1 — Stabilize Existing (Now)
- [ ] Fix backup-verification PM2 process (currently stopped)
- [ ] Ensure autoheal.sh is running and logging correctly
- [ ] Standardize healthcheck intervals across all containers
- [ ] Implement Tier 0 diagnostics for top 5 failure patterns

### Phase 2 — Automate Known Patterns (Next)
- [ ] Container unhealthy → auto-restart with verification
- [ ] PM2 crash → auto-restart with dependency check
- [ ] Disk pressure → auto-cleanup (old logs, Docker images)
- [ ] Memory pressure → auto-scale mem_limit

### Phase 3 — Intelligent Healing (Future)
- [ ] Cascade diagnosis with ecosystem graph
- [ ] Predictive healing (fix before failure)
- [ ] Cross-server automated healing
- [ ] LiteLLM auto-failover to backup LLM provider

### Phase 4 — Full Autonomy (Long-term)
- [ ] AI-governed healing decisions within bounded authority
- [ ] Automated incident post-mortems
- [ ] Continuous improvement from incident knowledge base

---

*End of Self-Healing Framework Design*
