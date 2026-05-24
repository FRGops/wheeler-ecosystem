# Wheeler Self-Healing Engine

**Version:** 2.0  
**Last Updated:** 2026-05-24  
**Status:** Phase 1 (Stabilize) Complete, Phase 2 (Automate) In Progress

---

## 1. Overview

The Self-Healing Engine is the autonomic nervous system of the Wheeler AI Ops platform. It detects, diagnoses, remediates, and verifies ecosystem failures automatically, operating within a bounded authority model that escalates novel or high-risk failures to human operators.

### 1.1 The Healing Loop

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│  DETECT ──→ DIAGNOSE ──→ REMEDIATE ──→ VERIFY      │
│     ↑                                        │      │
│     └──────────────── LEARN ────────────────┘      │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 1.2 The Verify-Act-Verify Pattern

Every healing action follows the foundational pattern codified from operational experience:

```
PHASE 1 — CAPTURE before-state
  Capture: docker ps, pm2 jlist, ss -tlnp, nginx -T
  Store to: /tmp/pre-mutation-<timestamp>.json

PHASE 2 — VERIFY before-state is safe to act on
  Check: process not in crash loop, not in dependency cascade
  Check: blast radius ≤ 2 services (from ecosystem graph)
  Check: sufficient resource headroom for restart

PHASE 3 — EXECUTE remediation
  Execute: type-specific healing action
  Pattern: env -i delete+start for PM2, docker compose up -d for Docker

PHASE 4 — VERIFY after-state
  Check: status = "healthy" or "online"
  Check: PID changed (proves restart actually occurred)
  Check: health endpoint returns 200 with valid body (not error page)
  Check: dependencies still healthy
  Check: no new alerts fired

PHASE 5 — CAPTURE after-state
  Store to: /tmp/post-mutation-<timestamp>.json
  If PM2: pm2 save --force
```

### 1.3 No-False-Greens Philosophy

A service is not declared "healthy" because it returns HTTP 200. The healthcheck MUST inspect the response body for error signatures. The `_http_check()` function in the master smoke test script (`/root/scripts/smoke-test-all.sh`) rejects:

- Nginx error pages (nginx/X.X.X error)
- HTML error titles (`<title>Error</title>`, `<title>500</title>`)
- Stack traces and exception messages
- Error codes embedded in response body
- Cloudflare error pages
- JSON error envelopes (`"error": "Internal Server Error"`)
- JSON status fields set to "error" or "fail"
- HTTP 200s with response bodies smaller than 64 bytes
- HTTP 200s from upstream 502/503/504 proxies

A 200 with error content is treated as FAIL. This is enforced in every validation script.

---

## 2. Detection Systems

### 2.1 Detection Sources and Latency

| Source | Mechanism | Poll Interval | Detection Latency | Confidence Multiplier |
|--------|-----------|---------------|-------------------|----------------------|
| Docker Healthchecks | Container status → "unhealthy" | 30s check + 3x10s retries | 60s worst case | 1.0 |
| PM2 Daemon Monitor | ecosystem-guardian polls pm2 jlist | 60s | 60s | 1.0 |
| Prometheus Alerts | Alert rules evaluated every 30s | 30s eval + 2m "for" duration | 2.5 min | 1.2 |
| Uptime Kuma | External HTTP/S reachability | 60s | 60s | 0.8 |
| Cron autoheal.sh | Bash script checks Docker + PM2 state | 2 min | 2 min | 0.9 |
| Lockdown Watchdog | Port bind + UFW rule verification | 5 min | 5 min | 1.0 |
| Loki Log Pattern | Log level analysis (ERROR, FATAL) | Near-real-time via promtail | 15-30s | 0.7 |
| Functional Healthcheck | 20-endpoint HTTP + TCP check | On-demand (/slay) | Immediate | 1.0 |

### 2.2 Multi-Source Detection Confidence

The confidence in a detected failure determines the authority level for action:

```
SINGLE SOURCE detection:          confidence = 0.6 (possible transient)
TWO SOURCES agree:                confidence = 0.85 (likely real)
THREE+ SOURCES agree:             confidence = 0.95 (confirmed)

Action thresholds:
  confidence >= 0.85 → autonomous remediation (Tier 2-3)
  confidence >= 0.60 → alert operator (Tier 0-1)
  confidence < 0.60  → log only, wait for confirmation
```

### 2.3 Detection Commands

```bash
# Docker container health
docker ps --format '{{.Names}} {{.Status}}' | grep -E 'unhealthy|restarting'

# PM2 process status
pm2 jlist | python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data:
    name = p['name']
    status = p['pm2_env']['status']
    restarts = p['pm2_env']['restart_time']
    if status != 'online' or restarts > 5:
        print(f'ISSUE: {name} status={status} restarts={restarts}')
"

# Port bind drift
ss -tlnp | awk '$4 !~ /127.0.0.1|::1|100\.121\.230\.28|:22/ && NR>1 {print}'

# Container :latest audit
docker ps --format '{{.Image}}' | grep ':latest'

# PM2 secret leak scan
pm2 jlist | python3 -c "
import json, sys
sensitive = ['API_KEY','AUTH_TOKEN','PASSWORD','MASTER_KEY','HCLOUD_TOKEN']
for p in json.load(sys.stdin):
    env = p.get('pm2_env',{}).get('env',{})
    found = {k for k in env if any(s in k.upper() for s in sensitive)}
    if found: print(f'LEAK: {p[\"name\"]}: {sorted(found)}')
"
```

### 2.4 Heartbeat Monitoring

The ecosystem-guardian process (PM2, ~56MB RAM) serves as the central heartbeat monitor:

```bash
# Guardian polling loop (simplified)
while true; do
    # 1. Discover current state
    docker_containers=$(docker ps --format json)
    pm2_processes=$(pm2 jlist)
    port_binds=$(ss -tlnp)
    nginx_routes=$(nginx -T 2>/dev/null)

    # 2. Compare against desired state from governance rules
    # 3. Detect drift (missing containers, unexpected ports, new :latest tags)
    # 4. Publish state to Neo4j ecosystem graph
    # 5. Emit events for any detected anomalies

    sleep 60
done
```

---

## 3. PM2 Self-Healing

### 3.1 Crash Detection

PM2 provides built-in crash detection via `autorestart: true`, but the self-healing engine adds a detection layer that looks for:

```
PROCESS-CRASH signature:
  - Status = "errored" or "stopped"
  
CRASH-LOOP signature:
  - Status = "online" but restart_time > 5
  - Interval between restarts decreasing (30min → 15min → 8min)
  
ENV-CORRUPTION signature:
  - Process runs but crashes with "DEEPSEEK_API_KEY" / "API_KEY" errors
  - pm2 jlist shows sensitive env vars that should not be there
```

### 3.2 Root Cause Diagnosis

```bash
# 1. Check crash count and interval
pm2 jlist | jq '.[] | select(.name=="<process>") | .pm2_env.restart_time'

# 2. Check logs
pm2 logs <process> --lines 100 --nostream | tail -50

# 3. Common crash patterns by log output:
#   "DEEPSEEK_API_KEY" error → check LiteLLM proxy
#   "ECONNREFUSED" → dependency down (check COREDB connectivity)
#   "out of memory" → memory limit too low
#   "SyntaxError" → code deployment issue
#   "ENOENT" → missing file or dependency

# 4. Check env vars
pm2 env <process_id> 2>/dev/null | grep -E 'API_KEY|TOKEN|PASSWORD|URL'
```

### 3.3 Restart Procedures

#### Standard Restart (code/config unchanged)

```bash
# verify before
pm2 jlist | jq '.[] | select(.name=="<process>") | .pm2_env.status'

# execute
pm2 restart <process> --update-env

# verify after  
pm2 jlist | jq -r '.[] | select(.name=="<process>") | .pm2_env.status'
# Must return "online"
```

#### env -i Delete+Start (env var changed or jlist secret leak)

```bash
# This is the CANONICAL pattern for PM2 env var changes.
# NEVER use pm2 restart --update-env — it injects shell environment
# into PM2's stored state, leaking secrets to pm2 jlist.

# 1. Verify before
pm2 jlist | jq '.[] | select(.name=="<process>") | .pm2_env.status'

# 2. Delete process with clean environment
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  PM2_HOME=/root/.pm2 pm2 delete <process>

# 3. Start fresh
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  PM2_HOME=/root/.pm2 pm2 start <ecosystem-config> --only <process>

# 4. Save state
pm2 save --force

# 5. Verify after
pm2 jlist | jq -r '.[] | select(.name=="<process>") | .pm2_env.status'
test "$(pm2 jlist | jq -r '.[] | select(.name=="<process>") | .pm2_env.status')" = "online"

# 6. Verify no secret leak
pm2 jlist | python3 -c "..."
```

### 3.4 PM2 Process Config Mapping

Every PM2 process has a known ecosystem.config.js path:

| Process | Config File |
|---------|------------|
| frgcrm-api | /opt/wheeler/apps/frgcrm/api/ecosystem.config.js |
| surplusai-portal-api | /opt/apps/surplusai-portal/ecosystem.config.js |
| design-agent-svc | /opt/apps/design-agent-svc/ecosystem.config.js |
| horizon-agent-svc | /opt/apps/horizon-agent-svc/ecosystem.config.js |
| prediction-radar-agent-svc | /opt/apps/prediction-radar-agent-svc/ecosystem.config.js |
| paperless-agent-svc | /opt/apps/paperless-agent-svc/ecosystem.config.js |
| ravyn-agent-svc | /opt/apps/ravyn-agent-svc/ecosystem.config.js |
| frgcrm-agent-svc | /opt/apps/frgcrm-agent-svc/ecosystem.config.js |
| surplusai-scraper-agent-svc | /opt/apps/surplusai-scraper-agent-svc/ecosystem.config.js |
| insforge-agent-svc | /opt/apps/insforge-agent-svc/ecosystem.config.js |
| voice-agent-svc | /opt/apps/voice-agent-svc/ecosystem.config.js |
| voice-outreach-service | /opt/apps/frgcrm/voice_outreach_service/ecosystem.config.js |
| litellm | /opt/apps/litellm/ecosystem.config.js |
| ecosystem-guardian | /opt/apps/wheeler-brain-os/ecosystem.config.js |
| event-bus-relay | /opt/apps/wheeler-brain-os/ecosystem.config.js |
| backup-verification | /opt/apps/wheeler-brain-os/ecosystem.config.js |
| war-room-server | /opt/apps/war-room/ecosystem.config.js |
| command-center | /opt/apps/command-center/ecosystem.config.js |
| openclaw-dashboard | /opt/openclaw-dashboard/ecosystem.config.js |

### 3.5 Danger Thresholds

```
PER-PROCESS THRESHOLDS:
  Restarts > 3 in 5 minutes    → STOP, investigate before touching
  Memory > 500MB for agents    → WARN, possible memory leak
  Memory > 2GB for frgcrm-api  → WARN, GC pressure
  CPU > 80% sustained (5min)   → WARN, investigate workload

SERVER-LEVEL THRESHOLDS:
  > 5 PM2 restarts across all processes in 5 min → SERVER UNSTABLE
  > 2 PM2 processes in "errored" status           → DECLARE INCIDENT
  > 80% total RAM consumed by PM2                 → WARN, schedule optimization

Auto-remediation limits:
  Max 3 restarts per process per 30 minutes (autonomous)
  After 3rd restart in 30 minutes → escalate to operator
```

### 3.6 Restart Loop Detection

```bash
# Detect accelerating restart pattern
pm2 jlist | python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data:
    name = p['name']
    status = p['pm2_env']['status']
    restarts = p['pm2_env']['restart_time']
    # Check pm2_env.created_at vs pm_uptime to calculate recent restart frequency
    # (simplified: look for high restart counts)
    if restarts > 5:
        print(f'{name}: CRASH LOOP — {restarts} restarts')
    elif restarts > 3:
        print(f'{name}: WARNING — {restarts} restarts')
"
```

---

## 4. Docker Self-Healing

### 4.1 Container Health Check Monitoring

Every Docker container in the ecosystem must define a healthcheck. The healthcheck interval, retries, and start period are standardized:

```yaml
# Standard healthcheck template
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:<port>/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

### 4.2 Restart Policy Enforcement

All containers use `restart: unless-stopped`. The self-healing layer adds:

```bash
# Cron-based container health check (every 2 minutes)
# This runs alongside Docker's built-in restart policy

# 1. Find unhealthy containers
unhealthy=$(docker ps --filter "health=unhealthy" --format '{{.Names}}')

# 2. For each unhealthy container:
for container in $unhealthy; do
    # Log the issue
    echo "[$(date)] Container $container is UNHEALTHY" >> /var/log/wheeler-autoheal.log

    # Check if in restart loop
    status_count=$(docker inspect "$container" --format '{{.RestartCount}}')
    if [ "$status_count" -gt 5 ]; then
        echo "[$(date)] $container in restart loop — escalating" >> /var/log/wheeler-autoheal.log
        continue  # Escalate to operator
    fi

    # Restart
    docker restart "$container"

    # Wait for health check
    sleep 30

    # Verify
    new_status=$(docker inspect "$container" --format '{{.State.Health.Status}}')
    if [ "$new_status" = "healthy" ]; then
        echo "[$(date)] $container recovered" >> /var/log/wheeler-autoheal.log
    else
        echo "[$(date)] $container still unhealthy after restart — escalating" >> /var/log/wheeler-autoheal.log
    fi
done
```

### 4.3 Bind Verification

The lockdown watchdog (`/opt/wheeler-ecosystem/enforcement/wheeler-lockdown-watchdog.sh`) runs every 5 minutes via cron:

```bash
# Check for non-loopback, non-Tailscale, non-SSH binds
violations=$(ss -tlnp | awk '$4 !~ /127.0.0.1|::1|100\.121\.230\.28|:22/ && NR>1 {print}')

if [ -n "$violations" ]; then
    echo "[$(date)] PORT BIND VIOLATION DETECTED:" >> /var/log/wheeler-watchdog.log
    echo "$violations" >> /var/log/wheeler-watchdog.log

    # For each violating container, recreate with 127.0.0.1 bind
    for bind in $violations; do
        port=$(echo "$bind" | awk '{print $4}' | cut -d: -f2)
        process=$(echo "$bind" | awk '{print $7}')
        # Identify container, fix compose file, recreate
    done
fi
```

### 4.4 Image Hygiene

```bash
# Check for :latest tags (should be 0 in production)
latest_images=$(docker ps --format '{{.Image}}' | grep ':latest')

if [ -n "$latest_images" ]; then
    echo "[$(date)] :latest images found:" >> /var/log/wheeler-watchdog.log
    echo "$latest_images" >> /var/log/wheeler-watchdog.log
    # Each :latest must be investigated and pinned to a specific version
fi
```

### 4.5 Container Lifecycle Commands

```bash
# Restart unhealthy container
wheeler container restart <name>
  → docker restart <name>
  → Wait for healthcheck (up to 60s)
  → Verify healthy

# Recreate crashed container  
wheeler container recreate <name>
  → docker compose down <service>
  → docker compose up -d <service>
  → Wait for healthcheck
  → Verify healthy

# Full rebuild
wheeler container rebuild <name>
  → docker compose build --no-cache <service>
  → docker compose up -d <service>
  → Verify healthy
```

---

## 5. Network Self-Healing

### 5.1 Port Bind Repair

When the lockdown watchdog detects a port bound to 0.0.0.0 instead of 127.0.0.1:

```
DETECTION:
  ss -tlnp | grep '0.0.0.0:<port>' (excluding :22 and :443)
  
DIAGNOSIS:
  Identify container: docker ps | grep <port-mapping>
  Check compose file for published port syntax
  Common cause: "ports: - '8080:80'" instead of "ports: - '127.0.0.1:8080:80'"

REMEDIATION:
  Edit docker-compose.yml: add 127.0.0.1: prefix to published port
  Recreate container: docker compose up -d <service>
  
VERIFICATION:
  ss -tlnp | grep '<port>' → must show 127.0.0.1:<port>
  curl health endpoint → must respond
```

### 5.2 Exposure Auto-Fix

After the Hostinger Stage 2 cleanup (2026-05-24), all 37 Docker containers on the AIOPS node bind exclusively to 127.0.0.1. The auto-fix pattern is:

```bash
# Fix a container that somehow bound to 0.0.0.0
deny_container_bind_public() {
    local container="$1"
    local compose_dir="$2"

    # 1. Find the offending port mapping
    local port_line
    port_line=$(grep -n "published\|'[0-9]\+:[0-9]\+'" "${compose_dir}/docker-compose.yml" | head -1)

    # 2. Fix by adding 127.0.0.1 prefix
    # "8080:80" → "127.0.0.1:8080:80"
    sed -i "s/'\([0-9]\+\):\([0-9]\+\)'/127.0.0.1:\1:\2'/g" "${compose_dir}/docker-compose.yml"

    # 3. Recreate
    docker compose -f "${compose_dir}/docker-compose.yml" up -d

    # 4. Verify
    ss -tlnp | grep -E "^$(grep -oP '127.0.0.1:\K[0-9]+' "${compose_dir}/docker-compose.yml")"
}
```

### 5.3 Tailscale Reconnect

```bash
# Check Tailscale status
tailscale status

# If node is unreachable:
# 1. Check tailscale service
systemctl status tailscaled

# 2. Restart tailscale
systemctl restart tailscaled

# 3. Verify connectivity
tailscale ping 100.118.166.117  # COREDB
tailscale ping 100.98.163.17    # Hostinger

# 4. Verify service connectivity
ssh -o ConnectTimeout=5 root@100.118.166.117 'echo OK'
pg_isready -h 100.118.166.117 -p 5432
```

### 5.4 UFW Enforcement

```bash
# Verify UFW is active and rules are intact
ufw status numbered | head -5
# Should show: Status: active

# Verify COREDB tailscale-only
# On COREDB:
ufw status verbose | grep tailscale0
# Should show: ALLOW IN on tailscale0

# Verify no unexpected allow rules
ufw status numbered | grep -E 'ALLOW IN.*(any|eth0)'
# Should show only: 22/tcp (SSH), 443/tcp (nginx)
```

---

## 6. Database Self-Healing

### 6.1 Connection Recovery

```bash
# Test PostgreSQL connectivity
pg_isready -h 100.118.166.117 -p 5432 -U postgres --timeout=5

# If unreachable:
# 1. Check network
ssh -o ConnectTimeout=5 root@100.118.166.117 'echo OK'

# 2. Check PostgreSQL process (via SSH)
ssh root@100.118.166.117 'systemctl status postgresql || docker ps | grep postgres'

# 3. Restart PostgreSQL (if container)
ssh root@100.118.166.117 'docker compose -f /opt/wheeler-core/docker-compose.yml restart postgres'

# 4. Verify recovery
sleep 10
pg_isready -h 100.118.166.117 -p 5432 -U postgres --timeout=5
```

### 6.2 Replication Check

```bash
# Check replication status on primary (COREDB)
ssh root@100.118.166.117 \
  "psql -U postgres -c \"SELECT client_addr, state, sync_state FROM pg_stat_replication;\""

# Expected: standby should show "streaming" state

# Check standby (AIOPS frgops-standby)
docker exec frgops-standby psql -U postgres -c \
  "SELECT pg_is_in_recovery(), pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();"
# pg_is_in_recovery() should return true
```

### 6.3 Backup Verification

```bash
# Check recent backup exists
latest_backup=$(ls -t /opt/backups/databases/*.dump 2>/dev/null | head -1)
if [ -n "$latest_backup" ]; then
    backup_age=$(( ($(date +%s) - $(stat -c %Y "$latest_backup")) / 3600 ))
    if [ "$backup_age" -lt 26 ]; then
        echo "Backup fresh: ${backup_age}h old"
    else
        echo "Backup STALE: ${backup_age}h old"
    fi
fi

# Verify backup integrity (test restore to temp)
pg_restore --list "$latest_backup" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Backup integrity: VALID"
else
    echo "Backup integrity: CORRUPT"
fi
```

### 6.4 Redis Recovery

```bash
# Test Redis connectivity
redis-cli -h 100.118.166.117 -p 6379 PING
# Should return: PONG

# Check memory usage
redis-cli -h 100.118.166.117 -p 6379 INFO memory | grep used_memory_human

# If memory > 90% of maxmemory:
# Suggestion: FLUSHDB (requires operator approval — data-destructive)
redis-cli -h 100.118.166.117 -p 6379 FLUSHDB
# Note: FLUSHDB is TIER 1 (Assisted) — always requires approval
```

---

## 7. Monitoring Stack Self-Healing

### 7.1 Prometheus Recovery

```bash
# Check Prometheus health
curl -s http://127.0.0.1:9090/-/healthy

# Check targets
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up") | .labels.instance'
# Should return: empty (all targets up)

# If Prometheus is down:
docker compose -f /opt/apps/monitoring/docker-compose.yml restart prometheus

# Verify
sleep 15
curl -s http://127.0.0.1:9090/-/healthy | grep -q "Prometheus is Healthy"
```

### 7.2 Loki Recovery

```bash
# Check Loki readiness
curl -s http://127.0.0.1:3100/ready

# Check promtail is shipping logs
docker logs promtail --tail 10 2>&1 | grep -E "completed|targets"

# If Loki is unhealthy:
docker compose -f /opt/apps/monitoring/docker-compose.yml restart loki

# Verify
sleep 10
curl -s http://127.0.0.1:3100/ready
```

### 7.3 Grafana Recovery

```bash
# Check Grafana health
curl -s http://127.0.0.1:3002/api/health | jq '.database'
# Should return: "ok"

# If Grafana is down:
docker compose -f /opt/apps/monitoring/docker-compose.yml restart grafana

# Verify
sleep 15
curl -s http://127.0.0.1:3002/api/health | jq -e '.database == "ok"'
```

### 7.4 Uptime Kuma Recovery

```bash
# Check Uptime Kuma
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3001

# If down:
docker restart uptime-kuma

# Verify
sleep 10
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3001
```

### 7.5 Alertmanager Self-Healing

```bash
# Check Alertmanager health
curl -s http://127.0.0.1:9093/-/healthy

# Verify no silences blocking critical alerts
curl -s http://127.0.0.1:9093/api/v2/silences | jq '.[] | select(.status.state=="active") | .comment'

# Check webhook-relay (sends alerts to Discord)
curl -s http://127.0.0.1:8085/health
```

---

## 8. Rollback Integration

### 8.1 Automatic Rollback Triggers

The rollback engine at `/root/rollback-engine/rollback.sh` integrates with the self-healing system through automatic triggers:

```
AUTOMATIC ROLLBACK TRIGGERS (post-deployment):

  TRIGGER 1 — Container healthcheck fails 3 consecutive times after deploy
    Action: docker compose down && docker compose up -d (previous version)
    Verification: wait for healthy status, check logs

  TRIGGER 2 — Error rate increases >2x baseline in 5-minute window
    Action: Revert to previous image tag
    Verification: Check Prometheus error rate metrics

  TRIGGER 3 — Memory exceeds limit within 2 minutes of deploy
    Action: Revert to previous configuration
    Verification: docker stats within expected range

  TRIGGER 4 — PM2 process restarts >2 times in first 60 seconds
    Action: pm2 stop, restore previous .env, pm2 start
    Verification: status = "online" for 30+ seconds

MANUAL ROLLBACK TRIGGERS:
  - Operator issues /rollback command
  - War room declares incident during deployment
  - CEO console issues abort (future)
```

### 8.2 Deployment Verification

```bash
# Post-deployment verification gates (enforced by post-deploy-healthcheck.sh)

# 1. Container healthy
docker inspect <container> --format '{{.State.Health.Status}}'
test "$(docker inspect <container> --format '{{.State.Health.Status}}')" = "healthy"

# 2. Health endpoint responds
curl -sf http://127.0.0.1:<port>/health > /dev/null

# 3. Logs show no errors
docker logs <container> --tail 50 2>&1 | grep -qiE 'error|fatal|traceback|exception' && echo "LOGS CONTAIN ERRORS" || echo "LOGS CLEAN"

# 4. Prometheus target is up (if applicable)
curl -s http://127.0.0.1:9090/api/v1/targets | jq -e '.data.activeTargets[] | select(.labels.container=="<container>") | .health == "up"' > /dev/null

# 5. No new alerts in Alertmanager
curl -s http://127.0.0.1:9093/api/v2/alerts | jq 'length == 0'
```

### 8.3 Rollback Procedure (5-Phase)

```bash
# Executed by: /root/rollback-engine/rollback.sh <service> <environment>

# Phase 1 — Discovery:
#   Detect type (docker/pm2/static/routing)
#   Find backup (latest or version-tagged)
#   Verify backup integrity

# Phase 2 — Execute:
#   restore-env.sh  → restore .env files from backup
#   restore-docker.sh → docker compose down + up -d (previous image)
#   restore-pm2.sh → pm2 delete + start (previous code)

# Phase 3 — Verification:
#   Container: status=healthy, health endpoint responds
#   PM2: status=online, PID changed within 10s
#   HTTP: curl health endpoint returns 200 with valid body

# Phase 4 — Preservation:
#   Preserve failed deployment logs to /opt/backups/rollback-preservations/
#   Include PM2 logs, Docker logs, system state snapshot

# Phase 5 — Notification:
#   Send rollback alert to Discord
#   Include: service, from_version, to_version, duration_ms, outcome
```

---

## 9. Validation Gates

### 9.1 Gate List

A service is NOT declared "healthy" until ALL of the following gates pass:

```
GATE 1 — Service Health:
  □ Docker: status = "healthy" for >= 2 consecutive checks
  □ PM2: status = "online" for >= 30 seconds
  □ HTTP: health endpoint returns 200

GATE 2 — Body Integrity (No False Greens):
  □ Response body > 64 bytes
  □ No nginx error page signatures
  □ No HTML error titles
  □ No stack traces or exception messages
  □ No JSON error envelopes
  □ No 5xx status in JSON response

GATE 3 — Dependency Health:
  □ All DEPENDS_ON services still healthy
  □ Database: pg_isready returns 0
  □ Redis: PING returns PONG
  □ LiteLLM: /health returns (401 is acceptable — means auth is working)

GATE 4 — Resource Baseline:
  □ CPU within 20% of pre-incident baseline
  □ Memory within 20% of pre-incident baseline
  □ No sustained memory growth (possible leak)

GATE 5 — Alert Verification:
  □ No new CRITICAL alerts in Alertmanager
  □ No new PM2 crash events
  □ No new unhealthy containers

GATE 6 — Functional Check:
  □ For APIs: curl basic endpoint, verify 200 + valid response
  □ For agents: check next polling cycle completed successfully
  □ For databases: run simple SELECT 1 query

GATE 7 — Security Compliance:
  □ No 0.0.0.0 port binds
  □ No :latest image tags
  □ PM2 jlist shows no secret leakage
```

### 9.2 Verification Windows

| Tier | Verification Window | Actions Performed |
|------|-------------------|-------------------|
| Tier 3 (Autonomous) | 60 seconds | Automated checks, no human review |
| Tier 2 (Supervised) | 120 seconds | Automated checks, human can override |
| Tier 1 (Assisted) | 300 seconds | Extended observation period |
| Tier 0 (Advisory) | Operator-defined | Human-led verification |

### 9.3 Failure Escalation

```bash
# If verification fails after remediation:

# 1st failure within 5 minutes:
#   → Automatic retry (same remediation)
#   → Max 2 retries

# 2nd failure within 15 minutes:
#   → Escalate to operator (Discord #war-room)
#   → Include: detection source, diagnosis, attempted remediations, current state

# 3rd failure within 1 hour:
#   → DECLARE INCIDENT
#   → Invoke war-room-server
#   → Full incident response procedure
#   → Post-mortem required
```

---

## 10. No-False-Greens Enforcement

### 10.1 Core Principle

A health check that returns "pass" for a broken service is worse than no health check at all. Every validation in the self-healing engine MUST produce false positives only in the safe direction (failing for a healthy service rather than passing for a broken one).

### 10.2 Enforced Rules

```bash
# Rule 1: HTTP 200 is NOT sufficient — inspect the body
_http_check() {
    local url="$1"
    local response_code
    local response_body

    response_code=$(curl -s -o /tmp/response.txt -w '%{http_code}' "$url")
    response_body=$(cat /tmp/response.txt)

    # HTTP 200 with error body = FAIL
    if [ "$response_code" = "200" ]; then
        local body_size=${#response_body}
        if [ "$body_size" -lt 64 ]; then
            return 1  # Body too small for a real 200
        fi
        if echo "$response_body" | grep -qiE 'error|exception|traceback|500|502|503|504'; then
            return 1  # Error signatures in body
        fi
    fi

    return 0
}

# Rule 2: PM2 "online" is NOT sufficient — check PID changed
pm2_verify_restart() {
    local process="$1"
    local old_pid="$2"
    local new_pid

    new_pid=$(pm2 jlist | jq -r ".[] | select(.name==\"$process\") | .pid")

    if [ "$new_pid" = "$old_pid" ] || [ -z "$new_pid" ]; then
        return 1  # Restart did not actually occur
    fi
    return 0
}

# Rule 3: Container "running" is NOT sufficient — check health status
docker_verify_health() {
    local container="$1"
    local health_status

    health_status=$(docker inspect "$container" --format '{{.State.Health.Status}}')

    if [ "$health_status" != "healthy" ]; then
        return 1  # Not healthy
    fi
    return 0
}
```

### 10.3 False Green Audit

The `/slay` skill includes a jlist secret scan that detects false greens in PM2:

```bash
# Target: 0 real secrets in pm2 jlist
# If any found, they came from a non-env-i restart and must be remediated

pm2 jlist | python3 -c "
import json, sys
sensitive = ['API_KEY','AUTH_TOKEN','PASSWORD','MASTER_KEY','HCLOUD_TOKEN']
for p in json.load(sys.stdin):
    env = p.get('pm2_env',{}).get('env',{})
    found = {k for k in env if any(s in k.upper() for s in sensitive)}
    if found:
        print(f'FALSE GREEN: {p[\"name\"]} leaks {sorted(found)} in jlist')
        print(f'REMEDIATION: env -i delete+start required')
"
```

---

## 11. Auto-Remediation Approval Levels

### 11.1 Authority Matrix

| Remediation Type | Current Tier | Target Tier | Blast Radius | Proven Count | Approval |
|-----------------|-------------|-------------|--------------|--------------|----------|
| Restart unhealthy container | 2 (Supervised) | 3 (Autonomous) | 1 service | 50+ | AI executes, human informed |
| Restart crashed PM2 process | 2 (Supervised) | 3 (Autonomous) | 1 process | 50+ | AI executes, human informed |
| Recreate crashed container | 2 (Supervised) | 2 (Supervised) | 1 service | 20+ | AI executes, 5min override |
| Fix port bind drift | 1 (Assisted) | 2 (Supervised) | 1 service | 5+ | Human approves |
| Scale memory limit | 1 (Assisted) | 2 (Supervised) | 1 service | 10+ | Human approves |
| Flush Redis cache | 1 (Assisted) | 1 (Assisted) | Multi-service | 3+ | Human approves (data loss risk) |
| Restore from backup | 0 (Advisory) | 1 (Assisted) | Multi-service | 2+ | Human executes |
| Rollback deployment | 0 (Advisory) | 1 (Assisted) | 1+ services | 10+ | Human approves |
| Rotate external API key | 0 (Advisory) | 0 (Advisory) | Multi-service | 0 | Human executes (dashboard) |
| Drop table / delete volume | 0 (Advisory) | 0 (Advisory) | Irreversible | 0 | NEVER autonomous |

### 11.2 Blast Radius Constraints

```
AUTONOMOUS ONLY IF:
  - Blast radius <= 2 services (from Neo4j ecosystem graph)
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

### 11.3 Pattern Promotion Lifecycle

```
Discovery:     New failure pattern observed
               → Tier 0 (Advisory)
               → AI suggests, human decides and executes
               → Document in incident knowledge base

Validation:    Same pattern + same fix worked 3 times
               → Tier 1 (Assisted)
               → AI drafts plan, human approves, AI executes
               → Add to remediation playbook

Proven:        Same pattern + same fix worked 10 times, 0 regressions
               → Tier 2 (Supervised)
               → AI executes, human has 5-minute override window
               → Add to auto-remediation scripts

Trusted:       Same pattern + same fix worked 50 times, 0 regressions
               → Tier 3 (Autonomous)
               → AI executes, human informed via Discord
               → Fully automated
```

### 11.4 Kill Switch

```bash
# Emergency halt all autonomous remediation
/slay --halt-autonomy

# Effects:
# - All auto-remediation scripts stop
# - All agents return to advisory-only mode
# - Only human operators can execute mutations
# - Detection continues (logging only)

# Re-enable:
# Manual override required at war-room-server
```

### 11.5 Current Auto-Healing in Place

```
ALREADY ACTIVE (Tier 3 by default):

  Cron autoheal.sh (every 2 minutes):
    - Restarts stopped Docker containers
    - Restarts crashed PM2 processes
    - Verifies service health post-restart
    - Logs all actions to /var/log/wheeler-autoheal.log

  Cron lockdown-watchdog.sh (every 5 minutes):
    - Verifies port bindings haven't drifted
    - Verifies UFW rules haven't changed
    - Restores lockdown if drift detected
    - Logs to /var/log/wheeler-watchdog.log

  Docker daemon:
    - restart: unless-stopped on all containers
    - Built-in crash recovery

  PM2 daemon:
    - autorestart: true on all processes
    - max_restarts: 10, min_uptime: 5000ms
    - Built-in crash recovery
```

### 11.6 Healing Gaps (Not Yet Automated)

```
NOT YET AUTOMATED:

  1. Cascade diagnosis: Root cause identification still manual
     - When multiple services fail, what failed first?
     - Requires Neo4j ecosystem graph traversal

  2. Cross-server healing: COREDB issues detected but not auto-healed from AIOPS
     - Monitoring detects COREDB PostgreSQL down
     - Cannot auto-restart without SSH
     - Escalation path: notify operator with diagnostic context

  3. Memory leak response: Detected (Prometheus) but not auto-mitigated
     - Prometheus alerts on sustained memory growth
     - Auto-restart could clear leak but may cause cascading failures
     - Decision: is this a real leak or just more traffic?

  4. Disk pressure response: Detected but not auto-cleaned
     - Prometheus alerts on disk > 85%
     - Manual cleanup required (old logs, Docker images, backups)
     - Auto-cleanup script exists but not deployed

  5. Backup recovery: No automated restore testing
     - Backups run daily
     - Integrity verified (pg_restore --list)
     - No automated restore-to-test procedure

  6. LiteLLM failover: Single point of failure
     - 9 agents depend on LiteLLM for LLM access
     - If LiteLLM goes down, all agents lose LLM capability
     - No auto-failover to direct API calls (planned for Phase 3)

  7. Agent blind spot: No synthetic transaction monitoring
     - We know individual services are up
     - We don't know if user-facing flows work end-to-end
     - Planned for Phase 3
```

---

## Appendix A: Self-Healing Commands Quick Reference

```bash
# ─── Ecosystem Audit ──────────────────────────────────────
/slay                          # Full 20-endpoint health audit + auto-remediation

# ─── PM2 Self-Healing ─────────────────────────────────────
pm2 jlist | jq '.[].pm2_env.status'           # Check all process statuses
pm2 logs <name> --nostream --lines 50          # Check logs for crash cause
pm2 restart <name> --update-env                # Simple restart (code unchanged)
env -i ... pm2 delete <name>                   # Clean restart (env changed)
env -i ... pm2 start <config> --only <name>    # Start fresh
pm2 save --force                               # Save clean state

# ─── Docker Self-Healing ──────────────────────────────────
docker ps --filter "health=unhealthy"           # Find unhealthy containers
docker inspect <name> --format '{{.State.Health.Status}}'  # Check health status
docker restart <name>                           # Restart container
docker compose -f <path> up -d <service>        # Recreate service

# ─── Network Self-Healing ────────────────────────────────
ss -tlnp | grep -v '127.0.0.1\|::1\|:22'      # Find port bind violations
ufw status numbered                             # Check firewall rules
tailscale status                                # Check mesh connectivity

# ─── Database Self-Healing ────────────────────────────────
pg_isready -h 100.118.166.117 -p 5432           # Check PostgreSQL
redis-cli -h 100.118.166.117 PING               # Check Redis

# ─── Rollback ─────────────────────────────────────────────
/root/rollback-engine/rollback.sh <svc> prod    # Full 5-phase rollback
/root/deployment-engine/rollback-deployment.sh <svc> prod  # Quick rollback
```

## Appendix B: Log Files

| Log File | Purpose | Retention |
|----------|---------|-----------|
| /var/log/wheeler-autoheal.log | Auto-heal actions and results | 90 days |
| /var/log/wheeler-watchdog.log | Lockdown watchdog violations | 90 days |
| /var/log/wheeler/deploy/*/ | Per-deployment logs | 90 days |
| /root/.pm2/logs/*.log | PM2 process logs | logrotate managed |
| /var/log/nginx/ | Nginx access and error | 30 days |
| /var/log/ufw.log | Firewall events | 30 days |

## Appendix C: Monitoring Alert Rules (Prometheus)

```yaml
# Key alert rules evaluated every 30s
groups:
  - name: wheeler_critical
    rules:
      - alert: ContainerDown
        expr: up{job=~"docker.*"} == 0
        for: 2m
        labels: { severity: critical }

      - alert: PM2ProcessDown
        expr: pm2_up{status!="online"} == 1
        for: 1m
        labels: { severity: critical }

      - alert: HighPM2RestartRate
        expr: rate(pm2_restarts_total[5m]) > 0.1
        for: 2m
        labels: { severity: warning }

      - alert: PortBindViolation
        expr: node_port_bind_nonloopback > 0
        for: 0m
        labels: { severity: critical }
        annotations:
          summary: "Container bound to 0.0.0.0 detected"

      - alert: DiskSpaceLow
        expr: node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} < 0.1
        for: 5m
        labels: { severity: warning }
```

---

*End of Self-Healing Engine Design*
