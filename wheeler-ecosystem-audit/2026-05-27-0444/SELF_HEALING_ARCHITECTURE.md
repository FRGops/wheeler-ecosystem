# Wheeler Self-Healing Architecture

**Date:** 2026-05-27
**Author:** Wheeler Autonomous AI Ops

---

## Overview

The Wheeler ecosystem self-healing system is a multi-layered architecture combining a Node.js daemon (ecosystem-guardian), shell-based watchdog scripts, and dedicated healers for specific failure modes. This document inventories all components, what they auto-fix, what requires manual intervention, and how to test each.

---

## 1. What Self-Healing Exists (Current)

| Component | Type | Scope | Auto-Fix Capability | Schedule |
|-----------|------|-------|---------------------|----------|
| `ecosystem-guardian.js` | Node.js daemon (PM2) | PM2, Docker, system, network, TLS, secrets, APIs | Starts stopped PM2/Docker processes on `--fix` | Every 60s (daemon mode) |
| `self-healing-engine.sh` | Shell script | Stopped PM2, unhealthy/exited Docker | Restarts unhealthy containers & processes | Every 5 min (cron) |
| `autoheal-trigger.sh` | Shell script | All (reads health-report.json) | PM2 restart, Docker restart, port drift, resource cleanup, repo-engine | Every 7 min (cron, staggered) |
| `monitoring-stack-healer.sh` | Shell script | Prometheus, Grafana, Alertmanager, Loki, Pushgateway | Docker restart with verification | Every 10 min (cron) |
| `docker-watchdog.sh` | Shell watchdog | Docker container health, binds, restarts | Detection only (alerts via health-report.json) | On-demand (via ecosystem-health.sh) |
| `pm2-watchdog.sh` | Shell watchdog | PM2 process status, restarts, memory, CPU, env vars | Detection only | On-demand (via ecosystem-health.sh) |
| `port-watchdog.sh` | Shell watchdog | Network port drift | Detection only | On-demand (via ecosystem-health.sh) |
| `resource-watchdog.sh` | Shell watchdog | Disk, RAM, CPU, swap | Detection only | On-demand (via ecosystem-health.sh) |
| `ecosystem-health.sh` | Shell orchestrator | Runs 6 watchdogs, aggregates score | Orchestration only (generates health-report.json) | Every 7 min (cron) |

---

## 2. What Was Added (New Scripts - 2026-05-27)

### 2a. `restart-loop-healer.sh`

**Location:** `/root/scripts/aiops-watchdog/restart-loop-healer.sh`

**Purpose:** Detects PM2 processes that are actively crash-looping (high restarts within a short window) and applies graduated remediation.

**Auto-Fix Capability:**
- Detects processes with >5 restarts AND last restart within 5 minutes (active loop)
- For safe-to-restart processes (monitoring agents, watchdog agents, data sync agents): applies env -i delete+start pattern
- For processes with known fixes (ravynai-og-scheduler, executive-dashboard-api, litellm, repo-engine): logs the known diagnostic first

**Will NEVER auto-restart (logs only):**
- `frcrm-api` (production-critical PM2)
- `prediction-radar-agent-svc` (production-critical PM2)
- `open-webui` (production application)

**Escalation conditions:**
- Process with unknown fix and unsafe restart category
- Process still crash-looping after restart attempt
- Production-critical process with loop detected

**Log:** `/var/log/wheeler-restart-loop-healer.log`

**Schedule:** Every 5 minutes via cron (staggered +15s from self-healing engine) + integrated into ecosystem-guardian daemon

### 2b. `docker-container-healer.sh`

**Location:** `/root/scripts/aiops-watchdog/docker-container-healer.sh`

**Purpose:** Detects unhealthy Docker containers and applies graduated remediation with a time-based escalation.

**Auto-Fix Capability:**
- First detection: logs and tracks timestamp in state file (`/var/log/wheeler/docker-healer-state.json`)
- After 5 minutes of persistent "unhealthy": issues `docker restart`
- After 5 additional minutes if still unhealthy: escalates to human
- Also detects "starting" state stuck for >30 seconds

**Will NEVER auto-restart (logs only):**
- Database containers: postgres, redis, neo4j, qdrant (and any container with these in name)
- Production-critical containers: frcrm-api, prediction-radar-app-api, prediction-radar-app-web, open-webui

**Safe to restart:**
- Monitoring exporters (node-exporter, postgres-exporter, redis-exporter, cadvisor)
- Agent containers (any container with "agent" in name)
- Watchdog and relay containers
- Sidecar containers

**State persistence:** Uses JSON state file so unhealthy timing persists across cycles
**Log:** `/var/log/wheeler-docker-container-healer.log`

**Schedule:** Every 10 minutes via cron (staggered +25s) + integrated into ecosystem-guardian daemon

### 2c. `tailscale-mesh-healer.sh`

**Location:** `/root/scripts/aiops-watchdog/tailscale-mesh-healer.sh`

**Purpose:** Monitors Tailscale mesh for offline nodes and attempts reconnection.

**Mesh topology:**
- `wheeler-aiops-01` (Hetzner, 100.121.230.28) -- local node
- `srv1476866` (Hostinger, 100.98.163.17) -- production
- `wheeler-core-db-01` (CoreDB, 100.118.166.117) -- database
- `wheelers-macbook-pro` (Mac, 100.83.80.6) -- development

**Heal strategy by node:**
- **Mac offline:** Log only -- physical intervention required to reconnect
- **CoreDB offline:** Try `tailscale ping` for NAT traversal. If ping succeeds, verify SSH port 22 reachability. If ping fails, log and retry on next cycle. Escalate after 30 min.
- **Hostinger offline:** Same strategy as CoreDB. Try ping + SSH test.

**Auto-Fix Capability:**
- `tailscale ping` forces NAT traversal in Tailscale
- SSH connectivity test confirms reachability even if tailscale status is stale
- State tracking across cycles with graduated timing (5 min warn, 10 min heal, 30 min escalate)

**Cannot fix:**
- Mac disconnected from internet (physical intervention needed)
- Tailscale daemon crashed on remote node (no remote SSH access)
- Firewall blocking Tailscale UDP on port 41641

**Log:** `/var/log/wheeler-tailscale-mesh-healer.log`

**Schedule:** Every 10 minutes via cron (staggered +35s) + integrated into ecosystem-guardian daemon

### 2d. ecosystem-guardian.js Integration

**File:** `/opt/apps/wheeler-brain-os/lib/ecosystem-guardian.js`

The `runShellHealers()` function was added (lines 369-416) which:
- Invokes all three new scripts with `--dry-run` (detection mode only -- actual healing is done by cron)
- Staggers execution: restart-loop every cycle, docker every 2nd cycle, tailscale every 3rd cycle
- Reports results as guardian alerts with severity levels
- Writes results to `/opt/apps/wheeler-brain-os/logs/guardian.log`

---

## 3. Architecture Diagram

```
                    ┌─────────────────────────────┐
                    │    ecosystem-guardian.js     │
                    │     (PM2 daemon, 60s)        │
                    │  ┌───────────────────────┐   │
                    │  │  checkPM2()           │   │
                    │  │  checkDocker()        │   │
                    │  │  checkSystem()        │   │
                    │  │  checkAPIs()          │   │
                    │  │  checkCertExpiry()    │   │
                    │  │  checkJlistSecrets()  │   │
                    │  │  runShellHealers() ───┼───┐
                    │  └───────────────────────┘   │ │
                    └─────────────────────────────┘ │
                          ▲                        │
                          │                        │
                    ┌─────┴──────────────┐         │
                    │ ecosystem-health.sh │         │
                    │   (cron: */7)      │         │
                    └─────┬──────────────┘         │
                          │                        │
                    ┌─────┴──────────────┐         │
                    │ autoheal-trigger.sh │         │
                    │   (cron: */7+60s)  │◄────────┘
                    └─────┬──────────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ▼               ▼               ▼
┌─────────────────┐ ┌────────────────┐ ┌──────────────────┐
│restart-loop-    │ │docker-container│ │tailscale-mesh-   │
│healer.sh        │ │healer.sh       │ │healer.sh         │
│(cron: */5)      │ │(cron: */10)    │ │(cron: */10)      │
│                 │ │                │ │                  │
│► PM2 crash-loop │ │► unhealthy >5m │ │► offline nodes   │
│► Known fix map  │ │► graduated     │ │► ping reconnect  │
│► Production     │ │► state-persist │ │► per-node strat  │
│  safety gate    │ │  db/prod gate  │ │                  │
└─────────────────┘ └────────────────┘ └──────────────────┘
```

---

## 4. What Each Healer Auto-Fixes vs Manual Intervention

### Restart Loop Healer

| Condition | Auto-Fix | Manual Intervention Needed |
|-----------|----------|---------------------------|
| agent-svc crash-looping | env -i delete+start | -- |
| ravynai-og-scheduler looping | Suggests diagnostic, restarts | Backoff tuning if persistent |
| executive-dashboard-api looping | Suggests diagnostic, restarts | Port/DB config fix |
| frcrm-api crash-looping | **LOGS ONLY** | Investigate and fix manually |
| prediction-radar-agent-svc looping | **LOGS ONLY** | Investigate and fix manually |
| Unknown process crash-looping | Restart once, escalate if continues | Debug root cause |

### Docker Container Healer

| Condition | Auto-Fix | Manual Intervention Needed |
|-----------|----------|---------------------------|
| Monitoring exporter unhealthy | docker restart | -- |
| Agent container unhealthy | docker restart | -- |
| Database unhealthy | **LOGS ONLY** | Investigate and fix manually |
| Production app unhealthy | **LOGS ONLY** | Investigate and fix manually |
| Still unhealthy after restart | Escalated to log | Manual container rebuild |
| Stuck in "starting" >30s | Treat as unhealthy, attempt restart | Manual `docker logs` inspection |

### Tailscale Mesh Healer

| Condition | Auto-Fix | Manual Intervention Needed |
|-----------|----------|---------------------------|
| CoreDB/Hostinger offline <10min | Log and monitor | -- |
| CoreDB/Hostinger offline >10min | tailscale ping | -- |
| CoreDB/Hostinger offline >30min | Escalated | Manual SSH + tailscale status |
| Mac offline | **LOGS ONLY** | Physically reconnect Mac |
| SSH reachable but TS shows offline | Clears state (display issue) | -- |

---

## 5. Log Locations

| Log | Path | Content |
|-----|------|---------|
| Self-healing engine | `/var/log/wheeler/self-healing.log` | Diagnose-repair-verify cycles |
| Healing cron | `/var/log/wheeler/healing-cron.log` | All cron-based healing actions |
| Auto-heal trigger | `/var/log/wheeler-autoheal.log` | autoheal-trigger.sh output |
| Restart loop healer | `/var/log/wheeler-restart-loop-healer.log` | Crash loop detection and remediation |
| Docker container healer | `/var/log/wheeler-docker-container-healer.log` | Unhealthy container remediation |
| Tailscale mesh healer | `/var/log/wheeler-tailscale-mesh-healer.log` | Cross-server connectivity events |
| Ecosystem guardian | `/opt/apps/wheeler-brain-os/logs/guardian.log` | Guardian anomaly summaries |
| Ecosystem guardian autoheal | `/opt/apps/wheeler-brain-os/logs/autoheal.log` | Guardian auto-fix actions |
| Monitoring stack healer | `/var/log/wheeler/monitoring-healer.log` | Prometheus/Grafana etc. health |
| Health report | `/root/scripts/aiops-watchdog/health-report.json` | Consolidated health score |
| Compliance health | `/root/scripts/aiops-watchdog/compliance-health.json` | Compliance status |
| Wheeler watchdog | `/var/log/wheeler-watchdog.log` | Lockdown watchdog events |
| Dead man's switch | `/var/log/wheeler/dead-mans-switch.last` | Heartbeat timestamp |

**State files (persistent across cycles):**
| State File | Purpose |
|------------|---------|
| `/var/log/wheeler/docker-healer-state.json` | Tracks unhealthy container first-seen and restart timestamps |
| `/var/log/wheeler/tailscale-healer-state.json` | Tracks offline node first-seen and heal-attempt timestamps |
| `/var/log/wheeler/healing-state.json` | Tracks self-healing engine actions for safety valve |

---

## 6. Testing Procedures

### Test Restart Loop Healer
```bash
# Dry run (safe)
bash /root/scripts/aiops-watchdog/restart-loop-healer.sh --dry-run

# Full run (will restart looping non-critical processes)
bash /root/scripts/aiops-watchdog/restart-loop-healer.sh

# Force restart even for non-safe processes
bash /root/scripts/aiops-watchdog/restart-loop-healer.sh --force

# Check PM2 for known high-restart processes
pm2 jlist | python3 -c "import json,sys; [print(p['name'],p['pm2_env'].get('restart_time',0)) for p in json.load(sys.stdin) if p['pm2_env'].get('restart_time',0)>5]"
```

### Test Docker Container Healer
```bash
# Show current state
bash /root/scripts/aiops-watchdog/docker-container-healer.sh --status

# Dry run (safe)
bash /root/scripts/aiops-watchdog/docker-container-healer.sh --dry-run

# Full run
bash /root/scripts/aiops-watchdog/docker-container-healer.sh

# Force restart (override safety)
bash /root/scripts/aiops-watchdog/docker-container-healer.sh --force

# Simulate an unhealthy container:
docker inspect <container> --format '{{.State.Health.Status}}'
docker ps --filter "health=unhealthy"
```

### Test Tailscale Mesh Healer
```bash
# Show mesh status
bash /root/scripts/aiops-watchdog/tailscale-mesh-healer.sh --status

# Dry run
bash /root/scripts/aiops-watchdog/tailscale-mesh-healer.sh --dry-run

# Full run
bash /root/scripts/aiops-watchdog/tailscale-mesh-healer.sh

# Check tailscale directly
tailscale status
tailscale ping 100.118.166.117
```

### Test ecosystem-guardian JS integration
```bash
# Run once with shell healer integration
cd /opt/apps/wheeler-brain-os && node lib/ecosystem-guardian.js

# Check logs for shell healer output
tail -20 /opt/apps/wheeler-brain-os/logs/guardian.log

# Verify the daemon picks up the changes
pm2 logs ecosystem-guardian --lines 30
```

### Test Cron Integration
```bash
# Verify cron file syntax
cjmtool /etc/cron.d/wheeler-healing || run-parts --test /etc/cron.d

# Check cron is running
grep -i heal /var/log/syslog | tail -5

# Manually trigger a specific healer via its cron schedule
# Wait for next :05 or :15 minute mark and check:
tail -f /var/log/wheeler-restart-loop-healer.log
```

---

## 7. Safety Mechanisms

| Safety Mechanism | Implementation | Bypass |
|-----------------|----------------|--------|
| Production-critical process protection | Hardcoded name lists in each script | `--force` flag |
| Database container protection | Hardcoded name patterns in each script | `--force` flag |
| Self-healing safety valve | Limits repairs to 3 per 10 minutes | Edit `SAFETY_LIMIT` in self-healing-engine.sh |
| Dry-run mode | `--dry-run` reports without acting | Remove flag |
| Graduated timing | Containers unhealthy for <5 min are only logged | N/A (time-based) |
| Crash-loop detection | Only acts on restarts within 5 min window | N/A (time-based) |
| env -i pattern | Prevents secret leakage on PM2 restart | N/A (canonical pattern) |
| Verify-after-heal | Scripts verify process came back healthy | N/A (built-in) |

---

## 8. Future Improvements

- Webhook alerting for escalated events (PagerDuty/Slack integration)
- Auto-remediation for TLS certificate expiry (renewal script)
- Prometheus alert integration (forward guardian alerts as metrics)
- Incident ticket creation on escalation
- Multi-node healing via SSH (currently restricted to local tailscale operations)
- Anomaly baseline for restart counts (learn normal restart patterns per process)
