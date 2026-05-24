# Wheeler Brain OS — Control Plane Architecture

## 1. Overview

The Control Plane is the orchestration layer that manages every compute resource in the Wheeler ecosystem — Docker containers, PM2 processes, cron jobs, and nginx routing — across both physical servers. It provides a unified command interface that abstracts away the server boundary, so operators issue commands to "the ecosystem" rather than to individual machines.

### Design Principles

1. **Server-transparent commands** — `restart prediction-radar-api` works regardless of which server it runs on
2. **Verify → Act → Verify** — every mutation is bracketed by state verification
3. **Rollback-first** — no deployment proceeds without a tested rollback path
4. **Least-privilege execution** — control plane actions run with minimum required capabilities
5. **Audit-everything** — every command is logged with actor, timestamp, target, before-state, after-state

---

## 2. Control Plane Layers

```
┌─────────────────────────────────────────────────────────┐
│                   COMMAND INTERFACE                       │
│   Claude Code Skills (/slay, /deploy, /rollback, etc.)  │
│   REST API (war-room-server :8091)                       │
│   CEO Console (future)                                   │
├─────────────────────────────────────────────────────────┤
│                   ORCHESTRATION ENGINE                    │
│   Resource Discovery → Dependency Resolution → Execution │
├─────────────────────────────────────────────────────────┤
│                   EXECUTION ADAPTERS                      │
│   Docker Adapter │ PM2 Adapter │ Nginx Adapter │ SSH    │
├─────────────────────────────────────────────────────────┤
│                   VERIFICATION LAYER                      │
│   Health Checks → Metrics → Logs → State Comparison      │
└─────────────────────────────────────────────────────────┘
```

---

## 3. Resource Discovery

### 3.1 Server Registry

```json
{
  "servers": {
    "aiops": {
      "hostname": "wheeler-aiops-01",
      "tailscale_ip": "100.121.230.28",
      "role": "application",
      "capabilities": ["docker", "pm2", "nginx", "cron"],
      "max_containers": 60,
      "max_pm2_processes": 25
    },
    "coredb": {
      "hostname": "wheeler-core-db-01",
      "tailscale_ip": "100.118.166.117",
      "role": "database",
      "capabilities": ["docker", "cron"],
      "max_containers": 25,
      "max_pm2_processes": 0
    },
    "hostinger": {
      "hostname": "srv1476866",
      "tailscale_ip": "100.98.163.17",
      "role": "edge",
      "capabilities": ["docker", "pm2"],
      "external": true
    }
  }
}
```

### 3.2 Discovery Mechanism

```
Discovery Sources (polled every 60s by ecosystem-guardian):
  1. docker ps --format json       → Container inventory
  2. pm2 jlist                     → PM2 process inventory
  3. nginx -T                      → Nginx routing table
  4. crontab -l + /etc/cron.d/*   → Cron job inventory
  5. docker network ls             → Network topology
  6. ss -tlnp                      → Port bindings (verification only)

Canonical state stored in Ecosystem Graph (Neo4j)
```

---

## 4. Docker Control

### 4.1 Container Lifecycle Commands

```
Command                               → Docker Equivalent
─────────────────────────────────────────────────────────
wheeler container up <name>           → docker compose up -d (with pre-flight)
wheeler container down <name>         → docker compose down (with dependency check)
wheeler container restart <name>      → docker restart (with health verification)
wheeler container rebuild <name>      → docker compose build --no-cache && up -d
wheeler container logs <name>         → docker logs --tail 100
wheeler container health <name>       → docker inspect --format='{{.State.Health}}'
wheeler container resources <name>    → docker stats --no-stream
```

### 4.2 Pre-flight Checks (before any mutation)

```
1. Validate compose file syntax:      docker compose config --quiet
2. Check port conflicts:             ss -tlnp | grep <published_port>
3. Check resource headroom:          free -m && df -h
4. Dependency health:                All DEPENDS_ON containers healthy?
5. Backup current state:             docker inspect <name> > /tmp/pre-mutation.json
6. Verify .env file:                 All ${VARS} resolve
7. Check governance compliance:      cap_drop, mem_limit, cpus, 127.0.0.1 bind
```

### 4.3 Post-mutation Verification

```
1. Container reached "healthy" within start_period
2. Published port responds (curl health endpoint)
3. Logs show no ERROR/FATAL in first 10s
4. Prometheus metrics endpoint responds (if applicable)
5. No new alerts fired in Alertmanager
```

### 4.4 Cross-Server Docker Commands

```
# Restart all monitoring stacks everywhere
wheeler container restart --stack monitoring --all-servers

# Show all containers with :latest tags
wheeler container list --tag latest --all-servers

# Health audit across both servers
wheeler container health --all-servers
```

---

## 5. PM2 Process Control

### 5.1 Process Lifecycle Commands

```
Command                               → PM2 Equivalent
─────────────────────────────────────────────────────────
wheeler pm2 restart <name>            → pm2 restart <name> --update-env
wheeler pm2 reload <name>             → pm2 delete <name> && pm2 start (env reload)
wheeler pm2 stop <name>               → pm2 stop <name>
wheeler pm2 start <name>              → pm2 start <name>
wheeler pm2 logs <name>               → pm2 logs <name> --lines 100 --nostream
wheeler pm2 status                    → pm2 jlist (parsed)
wheeler pm2 save                      → pm2 save
```

### 5.2 PM2 Restart Safety Protocol

```
SAFE RESTART PROCEDURE (codified from wheeler operational experience):

1. CAPTURE before-state:
   pm2 jlist > /tmp/pm2-before.json
   pm2 prettylist | grep -E "name|status|restarts|memory"

2. VERIFY before-state is acceptable:
   - Target process is "online" (not errored, not in crash loop)
   - Restart count < 5 in last hour (if not, investigate first)
   - Memory within 2x of baseline

3. EXECUTE restart:
   For env var changes:  pm2 delete <name> && pm2 start ecosystem.config.js --only <name>
   For simple restart:   pm2 restart <name> --update-env

4. VERIFY after-state:
   - Status = "online" within 10s
   - PID changed (proves restart actually happened)
   - Restart count incremented by exactly 1
   - Port listening (ss -tlnp | grep <port>)
   - Health endpoint returns 200 (if applicable)

5. CAPTURE after-state:
   pm2 jlist > /tmp/pm2-after.json

6. SAVE if successful:
   pm2 save
```

### 5.3 Danger Thresholds

```
PER-PROCESS THRESHOLDS:
  Restarts > 3 in 5 minutes    → STOP, investigate before touching
  Memory > 500MB for agents    → WARN, possible leak
  Memory > 2GB for frgcrm-api  → WARN, GC pressure
  CPU > 80% sustained (5min)   → WARN, investigate workload

SERVER-LEVEL THRESHOLDS:
  > 5 PM2 restarts across all processes in 5 min → SERVER UNSTABLE
  > 2 PM2 processes in "errored" status           → DECLARE INCIDENT
  > 80% total RAM consumed by PM2                 → WARN, schedule optimization
```

---

## 6. Nginx Routing Control

### 6.1 Virtual Host Management

```
Command                                    → Action
──────────────────────────────────────────────────────────
wheeler nginx route add <domain> <target>  → Add server block, test, reload
wheeler nginx route remove <domain>        → Remove server block, test, reload
wheeler nginx route list                   → Show all virtual hosts and targets
wheeler nginx route status <domain>       → Check if target is reachable
wheeler nginx reload                       → nginx -t && nginx -s reload
```

### 6.2 Current Routing Table (16 virtual hosts)

```
wheeler-aiops-01:/etc/nginx/sites-enabled/aiops-gateway

External → :443 (rate-limited, basic auth)
  ├── grafana.aiops              → 127.0.0.1:3002
  ├── kuma.aiops                 → 127.0.0.1:3001
  ├── netdata.aiops              → 127.0.0.1:19999
  ├── superset.aiops             → 127.0.0.1:8088
  ├── healthchecks.aiops         → 127.0.0.1:3130
  ├── langflow.aiops             → 127.0.0.1:7860
  ├── changes.aiops              → 127.0.0.1:5000
  ├── prometheus.aiops           → 127.0.0.1:9090
  ├── loki.aiops                 → 127.0.0.1:3100
  ├── docuseal.aiops             → 127.0.0.1:3010
  ├── prediction-radar.aiops     → 127.0.0.1:8098
  ├── openwebui.aiops            → 127.0.0.1:3000
  ├── grafana-core.aiops         → 100.118.166.117:3000 (cross-server)
  ├── prometheus-core.aiops      → 100.118.166.117:9090 (cross-server)
  ├── 1panel.aiops               → 127.0.0.1:8090
  ├── crm.aiops                  → 127.0.0.1:3007
  ├── clickhouse.aiops           → 127.0.0.1:8123
  └── _ (default)                → 444 (catch-all, "Wheeler AI Ops Gateway — healthy")
```

### 6.3 Route Addition Playbook

```
1. Verify target is healthy:
   curl -s http://<target>/health || curl -s http://<target>/

2. Verify no port conflict:
   No other vhosts proxy to the same target on the same path

3. Add server block:
   server_name <new-subdomain>.aiops;
   location / { proxy_pass http://<target>; }

4. Test configuration:
   nginx -t

5. Reload:
   nginx -s reload

6. Verify route:
   curl -k -H "Host: <new-subdomain>.aiops" https://127.0.0.1/

7. Update ecosystem graph:
   CREATE (:Dashboard {url: '<new-subdomain>.aiops'})-[:PROXIES_TO]->(:Container {name: '<target>'})
```

---

## 7. Deployment Pipeline

### 7.1 Deployment Types

| Type | Scope | Rollback Time | Pre-flight Gates |
|------|-------|---------------|------------------|
| **Hotfix** | Single container/process | < 30s | Health check only |
| **Standard** | Single stack | < 2min | 7 gates |
| **Rolling** | Multiple servers, sequenced | < 5min per server | All gates per server |
| **Major** | Cross-server, coordinated | < 15min | All gates + manual approval |

### 7.2 Seven Pre-Deployment Gates

```
GATE 1 — State Capture:
  Full ecosystem snapshot (docker ps, pm2 jlist, nginx -T, ss -tlnp)

GATE 2 — Dependency Health:
  All DEPENDS_ON services healthy?

GATE 3 — Resource Headroom:
  Target server has >20% free RAM and >10% free disk

GATE 4 — Configuration Valid:
  docker compose config --quiet (for Docker deploys)
  pm2 ecosystem.config.js syntax check (for PM2 deploys)

GATE 5 — Secret Availability:
  All ${ENV_VARS} referenced in compose/config resolve to non-empty values

GATE 6 — Rollback Path:
  Previous image/commit tagged and accessible
  Rollback procedure documented and tested

GATE 7 — Governance Compliance:
  cap_drop: ALL (or documented exception)
  mem_limit + cpus set
  127.0.0.1 or Tailscale IP bind only
  Healthcheck defined
  No :latest tag (production)
```

### 7.3 Canary Deployment (Future)

```
1. Deploy new version alongside old (different port)
2. Route 10% traffic to new version
3. Monitor error rate, latency, memory for 5 minutes
4. If healthy: shift to 100%, remove old
5. If degraded: shift to 0%, remove new, alert
```

---

## 8. Rollback System

### 8.1 Rollback Triggers

```
AUTOMATIC ROLLBACK TRIGGERS:
  - Container fails healthcheck 3 consecutive times after deploy
  - Error rate increases >2x baseline in 5-minute window
  - Memory usage exceeds limit within 2 minutes of deploy
  - PM2 process restarts >2 times in first 60 seconds

MANUAL ROLLBACK TRIGGERS:
  - Operator issues /rollback command
  - War room declares incident during deployment
  - CEO console issues abort
```

### 8.2 Rollback Procedure

```
DOCKER ROLLBACK:
  1. docker compose down
  2. Restore previous .env if changed
  3. docker compose up -d (with previous image tag)
  4. Verify health
  5. Verify no data loss (row counts, queue depths)

PM2 ROLLBACK:
  1. pm2 stop <name>
  2. git checkout <previous-commit> (if code change)
  3. Restore previous .env if changed
  4. pm2 start ecosystem.config.js --only <name>
  5. Verify status = online
  6. Verify health endpoint

NGINX ROLLBACK:
  1. Restore nginx config from backup (/etc/nginx/backups/)
  2. nginx -t
  3. nginx -s reload
```

### 8.3 Rollback Safety

```
BEFORE ROLLBACK:
  - Snapshot current state (in case rollback makes things worse)
  - Check if any data was written since deploy (don't lose data)
  - Notify Discord #war-room

DURING ROLLBACK:
  - Execute with --no-healthcheck flag (skip pre-flight, speed is priority)
  - Maximum 120 seconds allowed for full rollback

AFTER ROLLBACK:
  - Full ecosystem health audit
  - Post-incident review within 24h
  - Update runbooks if rollback reason was novel
```

---

## 9. Cross-Server Orchestration

### 9.1 SSH Command Dispatch

```
Pattern: ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=yes root@<tailscale_ip> '<command>'

Safety:
  - All SSH via Tailscale IPs only (never public IPs)
  - Command timeout: 30s default, 120s for long operations
  - Output captured to structured log
  - Failed SSH = failed command (no silent failures)
```

### 9.2 Multi-Server Commands

```
# Restart prediction-radar across both servers
wheeler restart prediction-radar --all-servers
  → AIOPS: docker compose restart web api worker scheduler
  → COREDB: docker compose restart worker scheduler
  → Verify all 6 containers healthy

# Rotate a secret everywhere it's used
wheeler secret rotate DEEPSEEK_API_KEY --all-servers
  → AIOPS: Update .env.shared, restart LiteLLM + 9 agents
  → COREDB: Update .env if used

# Full ecosystem health audit
wheeler health --all-servers
  → AIOPS: docker ps + pm2 jlist + nginx -T + ss -tlnp + df -h + free -m
  → COREDB: docker ps + ss -tlnp + df -h + free -m
  → Cross-reference with ecosystem graph expected state
```

### 9.3 State Synchronization

```
Cross-server state is synchronized via:
  1. COREDB PostgreSQL (authoritative state for all services)
  2. COREDB Redis (ephemeral state, cache, sessions)
  3. ecosystem-guardian (discovers and publishes state to graph)
  4. event-bus-relay (propagates state change events in near-real-time)
```

---

## 10. Audit Trail

### 10.1 Command Logging

Every control plane action logs:

```json
{
  "timestamp": "2026-05-24T08:15:00Z",
  "actor": "claude-code-session-cf1e5c0f",
  "command": "wheeler container restart aiops-healthchecks",
  "target": {
    "server": "aiops",
    "container": "aiops-healthchecks",
    "type": "docker"
  },
  "before_state": {
    "status": "unhealthy",
    "uptime_seconds": 82340
  },
  "after_state": {
    "status": "healthy",
    "uptime_seconds": 12
  },
  "duration_ms": 8234,
  "success": true,
  "gates_passed": ["state_capture", "dependency_health", "config_valid"],
  "rollback_available": true
}
```

### 10.2 Audit Storage

```
Short-term: COREDB PostgreSQL (wheeler_audit table, 90-day retention)
Long-term: Loki (structured log, 1-year retention)
Real-time: event-bus-relay → Discord #audit-log
```

---

## 11. Implementation Roadmap

### Phase 1 — Current (Manual via Claude Code Skills)
- `/slay`, `/docker-health`, `/pm2-health`, `/deploy-safety`, `/rollback`
- All commands executed via Claude Code Bash tool with operator oversight
- Verification is manual (read output, compare with expected)

### Phase 2 — Semi-Automated (War Room Server :8091)
- REST API wrapping the manual skill procedures
- Basic pre-flight gates enforced programmatically
- Audit logging to PostgreSQL

### Phase 3 — Autonomous (Ecosystem Guardian)
- Guardian monitors for drift between desired and actual state
- Self-healing triggers for well-understood failure modes
- CEO Console provides unified command interface

---

*End of Control Plane Architecture*
