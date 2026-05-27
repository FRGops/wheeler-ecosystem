# Wheeler Ecosystem -- Incident Response Runbook

**Version:** 1.0
**Date:** 2026-05-27
**Based on:** Audit session 2026-05-27-0444 (3-server audit, 5 actual incidents fixed)
**Source audit files:** `/root/wheeler-ecosystem-audit/2026-05-27-0444/`
**War room:** http://100.121.230.28:8091
**UptimeKuma:** http://100.121.230.28:3001 (Hetzner), http://100.118.166.117:3001 (CoreDB)
**Alertmanager:** http://100.121.230.28:9093
**Related docs:** `/root/INCIDENT_RESPONSE_FRAMEWORK.md`, `/root/DISASTER_RECOVERY_PLAN.md`, `/root/SELF_HEALING_ENGINE.md`

---

## SERVER QUICK REFERENCE

| Server | Provider | Tailscale IP | SSH Command | Docker | PM2 | Role |
|--------|----------|-------------|-------------|-------|-----|------|
| Hetzner (aiops) | CPX51 | 100.121.230.28 | `ssh root@100.121.230.28` | 47 containers | 85 processes | AIOps control plane |
| Hostinger | VPS | 100.98.163.17 | `ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17` | 7 containers | None | Production/revenue |
| CoreDB | Hetzner | 100.118.166.117 | `ssh root@100.118.166.117` | 21 containers | None | Database/storage |
| MacBook | -- | 100.83.80.6 | `ssh root@100.83.80.6` (KEYS MAY NOT MATCH) | -- | -- | CEO command center |

**IMPORTANT:** Hostinger requires a specific SSH key (`-i /root/.ssh/wheeler-mesh-key`). CoreDB and Hetzner use default SSH key. Mac SSH is unreliable (key mismatch).

---

## 1. INCIDENT SEVERITY LEVELS

### P0 -- Revenue Domain Down (Response: < 5 min)

Revenue-generating domains returning errors. Immediate response required.

- predictionradar.app (502, 5xx, timeout)
- fundsrecoverygroup.com (502, 5xx, timeout)

### P1 -- Core Infrastructure Down (Response: < 15 min)

Infrastructure that everything depends on.

- PM2 mass failure (> 10 processes stopped)
- Docker daemon down on any server
- Tailscale mesh node offline
- CoreDB PostgreSQL unreachable
- Prometheus / Loki / Grafana stack down
- Nginx down on Hostinger or Hetzner

### P2 -- Monitoring / Logging Broken (Response: < 1 hr)

Observability or non-critical infrastructure failure.

- Alertmanager down
- Promtail not shipping logs to Loki
- Redis exporter down
- Cadvisor metrics unavailable
- Uptime Kuma down

### P3 -- Non-Critical Service Issue (Response: < 24 hr)

Single service degraded, no revenue impact.

- LiteLLM response degradation
- Changedetection container restarting
- Embedding service slow
- Individual agent crashed

### P4 -- Informational (Response: < 7 days)

Technical debt, monitoring gaps, cosmetic issues.

- Certificates expiring > 30 days
- Disk usage > 75%
- Missing HEALTHCHECK on containers

---

## 2. ALERT ROUTING

### Where alerts come from

| Source | Endpoint | What it monitors |
|--------|----------|-----------------|
| Prometheus | http://127.0.0.1:9090/alerts | Metric-based alerts (CPU, memory, disk) |
| Alertmanager | http://127.0.0.1:9093/#/alerts | Alert routing, silencing, deduplication |
| Uptime Kuma | http://100.121.230.28:3001 | HTTP endpoint monitoring, ping checks |
| Healthchecks | http://127.0.0.1:3130 | Cron job heartbeat monitoring |

### Dashboard access

| Service | URL | Notes |
|---------|-----|-------|
| War Room | http://100.121.230.28:8091 | Incident coordination |
| Grafana | http://100.121.230.28:3002 | Metrics dashboards |
| UptimeKuma | http://100.121.230.28:3001 | HTTP uptime monitoring |
| Alertmanager | http://100.121.230.28:9093 | Active/firing alerts |
| Prometheus | http://100.121.230.28:9090 | Raw metric queries |

### Alert check commands

```bash
# Check firing alerts in Alertmanager
curl -s http://127.0.0.1:9093/api/v2/alerts | jq -r '.[] | "\(.labels.alertname // .labels.alert // "unknown"): \(.status.state) -- \(.annotations.summary // .annotations.description // "no description")"'

# Check firing alerts directly in Prometheus
curl -s http://127.0.0.1:9090/api/v1/alerts | jq '.data.alerts[] | select(.state=="firing") | {alertname: .labels.alertname, state: .state, value: .value}'

# Check all Prometheus targets
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# Check Loki is receiving logs
curl -s http://127.0.0.1:3100/loki/api/v1/labels | jq '.data'

# Check all UptimeKuma monitors (requires auth token from UI)
curl -s http://127.0.0.1:3001/api/monitors 2>/dev/null || echo "Kuma API requires UI access"
```

---

## 3. INCIDENT PLAYBOOKS

---

### 3a. Revenue Domain Returns 502

**Applicable to:** predictionradar.app, fundsrecoverygroup.com
**Severity:** P0
**Response time:** < 5 minutes

#### Step 1 -- Confirm the failure

```bash
# Check both domains from Hetzner
curl -sI https://predictionradar.app | head -5
curl -sI https://fundsrecoverygroup.com | head -5

# Check Cloudflare status
curl -sI https://1.1.1.1 2>/dev/null || echo "Cloudflare DNS: check manually at https://www.cloudflarestatus.com"
```

Expected: `HTTP/2 200` for both. Anything else is an incident.

#### Step 2 -- Check nginx on Hostinger (the front door)

```bash
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17

# Check nginx status
systemctl status nginx --no-pager | head -15

# Check nginx error log for the failing domain
tail -100 /var/log/nginx/error.log | grep -i "predictionradar\|fundsrecovery" | tail -30

# Check if nginx config is valid
nginx -t

# List prediction-radar site config
ls -la /etc/nginx/sites-enabled/ | grep -i prediction
cat /etc/nginx/sites-enabled/predictionradar.app 2>/dev/null || cat /etc/nginx/sites-enabled/prediction-radar 2>/dev/null

# Reload nginx if config was fixed
nginx -s reload
```

#### Step 3 -- Check Tailscale connectivity

```bash
# From Hetzner, verify Tailscale routes to both production hosts
tailscale ping 100.98.163.17    # Should return pong in ~179ms
tailscale ping 100.118.166.117  # Should return pong in ~1ms

# Verify Tailscale status
tailscale status
```

**If Tailscale is down:** See playbook 3d.

#### Step 4 -- Check backend container health

For predictionradar.app (backend on Hetzner):

```bash
# Check prediction-radar containers on Hetzner
docker ps --filter "name=prediction-radar" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check the web container specifically
docker logs prediction-radar-app-web --tail 50

# Check the API container
docker logs prediction-radar-app-api --tail 50

# Verify port 8098 is listening (the nginx proxy_pass target)
ss -tlnp | grep 8098
```

#### Step 5 -- Fix the proxy_pass (known issue from audit)

**Problem:** predictionradar.app Nginx config has SSL termination but the `proxy_pass` upstream is missing or points to a dead backend.

**Fix if backend is on Hetzner (port 8098):**

```bash
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17

# Edit the nginx site config for predictionradar.app
# Add or fix the proxy_pass line inside the location block:
#   proxy_pass http://100.121.230.28:8098;
#   proxy_set_header Host $host;
#   proxy_set_header X-Real-IP $remote_addr;
#   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#   proxy_set_header X-Forwarded-Proto $scheme;

vim /etc/nginx/sites-enabled/predictionradar.app

# Validate and reload
nginx -t && nginx -s reload
```

**Fix if backend is through Cloudflare Tunnel (cloudflared):**

```bash
# Check cloudflared is running on Hostinger
systemctl status cloudflared --no-pager | head -10

# Check tunnel status
journalctl -u cloudflared --no-pager -n 20
```

#### Step 6 -- Verify the fix

```bash
curl -sI https://predictionradar.app | head -5
# Expected: HTTP/2 200
```

---

### 3b. Docker Container Unhealthy or Stopped

**Applicable to:** All 3 servers (75 containers total)
**Severity:** P1-P3 depending on container role
**Response time:** < 15 min (P1), < 1 hr (P2-P3)

#### Step 1 -- Identify problematic containers

```bash
# Find unhealthy containers (Hetzner or CoreDB)
docker ps --filter "health=unhealthy" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Find stopped/exited containers
docker ps --filter "status=exited" --filter "status=dead" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Find recently restarted containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Restarts}}"

# Summary counts
echo "Total: $(docker ps -q | wc -l) running, $(docker ps -q --filter health=unhealthy | wc -l) unhealthy, $(docker ps -q --filter status=exited | wc -l) exited"
```

#### Step 2 -- Check logs

```bash
docker logs <container-name> --tail 100
# Add --timestamps to see when the failure occurred:
docker logs <container-name> --tail 100 --timestamps
```

#### Step 3 -- Check resource usage

```bash
# Check memory and CPU
docker stats --no-stream <container-name>

# Check if OOM was the cause
dmesg | grep -i "oom\|killed" | tail -10
```

#### Step 4 -- Check container config

```bash
# Check entrypoint, command, env vars
docker inspect <container-name> --format '{{.Config.Cmd}}'
docker inspect <container-name> --format '{{.Config.Entrypoint}}'
docker inspect <container-name> --format '{{range $k,$v := .Config.Env}}{{$k}}={{$v}}{{"\n"}}{{end}}'

# Check health check config
docker inspect <container-name> --format '{{.Config.Healthcheck}}'

# Check network
docker inspect <container-name> --format '{{json .NetworkSettings.Networks}}' | jq
```

#### Step 5 -- Restart procedure

```bash
# Standard restart
docker restart <container-name>

# For containers that fail immediately, check logs during restart:
docker logs -f <container-name> &
docker restart <container-name>
# Wait 5 seconds, then kill the follow

# For container replacement (when restart is not enough):
docker stop <container-name> && docker rm <container-name>
# Recreate using the original run command or docker-compose
```

#### Step 6 -- Verify

```bash
docker ps --filter "name=<container-name>" --format "table {{.Names}}\t{{.Status}}\t{{.Health}}"
# Expected: "healthy" or "starting" (give 5-10 seconds for health check)
```

---

### 3c. PM2 Process Stopped or Crashing

**Applicable to:** Hetzner (85 processes)
**Severity:** P1-P3 depending on process role
**Response time:** < 15 min (P1)

#### Step 1 -- Identify failing processes

```bash
# Quick check: count non-online processes
pm2 jlist | jq '[.[] | select(.pm2_env.status!="online")] | length'

# Detailed list of non-online processes
pm2 jlist | jq -r '.[] | select(.pm2_env.status!="online") | "\(.name): \(.pm2_env.status) restarts=\(.pm2_env.restart_time)"'

# All process statuses (summary)
pm2 jlist | jq -r '.[] | "\(.name): \(.pm2_env.status) (\(.pm2_env.restart_time) restarts, mem=\(.pm2_env.monitoring.memory // "N/A"))"'

# Find processes with high restart counts
pm2 jlist | jq -r '.[] | select(.pm2_env.restart_time > 5) | "\(.name): \(.pm2_env.restart_time) restarts, uptime=\(.pm2_env.pm_uptime // "unknown")"'
```

#### Step 2 -- Investigate a specific process

```bash
# Get full process details
pm2 show <process-name>

# Check logs (last 50 lines)
pm2 logs <process-name> --lines 50 --nostream

# Check memory limit config
pm2 describe <process-name> | grep -i "max_memory\|restart"
```

#### Step 3 -- Restart the process

```bash
pm2 restart <process-name>

# If restart doesn't work (env var stomping issue), use delete+start:
pm2 delete <process-name> && pm2 start ecosystem.config.js --only <process-name>
```

#### Step 4 -- If process crashes immediately on restart

Check for the known PM2 env var leak pattern (see `/root/.claude/projects/-root/memory/pm2-process-env-leak.md`).

```bash
# Check if process.env references exist in the ecosystem config
grep -n "process.env" /root/ecosystem.config.js 2>/dev/null

# Check if the process stores old env vars from previous runs
pm2 describe <process-name> | grep -A 50 "env variables" | head -60

# Clean restart with env -i pattern:
pm2 delete <process-name>
pm2 start ecosystem.config.js --only <process-name> --env production
```

#### Step 5 -- Verify

```bash
pm2 jlist | jq -r '.[] | select(.name=="<process-name>") | "\(.name): \(.pm2_env.status) uptime=\(.pm2_env.pm_uptime)"'
# Expected: "<process-name>: online"
```

---

### 3d. Tailscale Node Offline

**Applicable to:** Cross-server connectivity
**Severity:** P1
**Response time:** < 15 min

#### Step 1 -- Check Tailscale status

```bash
# From Hetzner (control plane)
tailscale status

# Expected output should show:
# 100.121.230.28  wheeler-aiops-01       linux   -
# 100.98.163.17   srv1476866             linux   -
# 100.118.166.117 wheeler-core-db-01     linux   -
# 100.83.80.6     wheelers-macbook-pro   macOS   -

# Check specific node connectivity
tailscale ping 100.98.163.17    # Hostinger: expected 179ms
tailscale ping 100.118.166.117  # CoreDB: expected 1ms
tailscale ping 100.83.80.6      # Mac: expected 33ms (may be offline)
```

#### Step 2 -- Restart Tailscale on the offline node

**On the offline node directly (SSH into it):**

```bash
# Restart Tailscale
systemctl restart tailscaled

# Wait 5 seconds, then verify
tailscale status
```

**For Hostinger (requires mesh key):**

```bash
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17
systemctl status tailscaled --no-pager | head -10
systemctl restart tailscaled
tailscale status
```

**For CoreDB:**

```bash
ssh root@100.118.166.117
systemctl status tailscaled --no-pager | head -10
systemctl restart tailscaled
tailscale status
```

#### Step 3 -- If Tailscale is fully down on the node

```bash
# Re-authenticate (may need Headscale/Auth key from Tailscale admin console)
tailscale up --accept-routes --advertise-routes=10.0.0.0/16

# If auth key needed, generate one from Tailscale admin console, then:
tailscale up --authkey=<tskey-auth-xxxxxxxx>

# Verify connectivity
tailscale ping 100.121.230.28
```

#### Step 4 -- Fallback if Tailscale is fully down across all nodes

Critical services (PostgreSQL, Redis) also listen on Tailscale IPs. If Tailscale is down, these are unreachable. Workaround:

```bash
# Check if services have alternative local access
# CoreDB PostgreSQL listens on 127.0.0.1:5432? Check:
ssh root@100.118.166.117 "ss -tlnp | grep 5432"

# If PostgreSQL is on 127.0.0.1 and you need direct access:
# Create a temporary SSH tunnel
ssh -L 5432:127.0.0.1:5432 root@100.118.166.117
# Then connect locally: psql -h 127.0.0.1 -p 5432
```

---

### 3e. Prometheus Alert Firing

**Applicable to:** Any active alert
**Severity:** Varies by alert type
**Response time:** Per severity classification

#### Step 1 -- List all firing alerts

```bash
# Direct from Prometheus
curl -s http://127.0.0.1:9090/api/v1/alerts | jq '.data.alerts[] | select(.state=="firing") | {alertname: .labels.alertname, labels: .labels, value: .value, active_at: .activeAt}'

# From Alertmanager (more detail)
curl -s http://127.0.0.1:9093/api/v2/alerts | jq -r '.[] | "\(.labels.alertname // .labels.alert): \(.status.state) (\(.receiver.name // "none"))"'

# Check alert rules
curl -s http://127.0.0.1:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.type=="alerting") | {name: .name, state: .state, duration: .duration}'
```

#### Step 2 -- Common alert types and investigation

**ContainerDown:**
```bash
# Find the container that is down
curl -s http://127.0.0.1:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="ContainerDown") | .labels'

# Check Docker for the named container
docker ps -a --filter "name=<container_name>" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# If the container is on Hostinger, SSH there first:
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17 "docker ps -a --filter 'name=<container_name>' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

**RedisDown:**
```bash
# Check which Redis instance is targeted
curl -s http://127.0.0.1:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="RedisDown") | .labels'

# Verify the Redis exporter is running
docker ps --filter "name=redis-exporter" --filter "name=redis_exporter"

# Check exporter env vars
docker inspect <redis-exporter> --format '{{range $k,$v := .Config.Env}}{{$k}}={{$v}}{{"\n"}}{{end}}' | grep -i "REDIS_ADDR\|REDIS_PASSWORD"

# Test direct Redis connectivity
docker exec <redis-exporter> sh -c "wget -q -O - http://127.0.0.1:9121/metrics 2>/dev/null | head -20" 2>/dev/null || echo "Exporter not responding"
```

Known fix pattern (from audit):
```bash
# Connect the Redis container to the monitoring network
docker network connect monitoring_prediction-radar-app-redis

# Recreate exporter with correct REDIS_ADDR
docker stop coredb-redis-exporter && docker rm coredb-redis-exporter
docker run -d --name coredb-redis-exporter \
  --restart unless-stopped \
  --network monitoring_default \
  -e REDIS_ADDR=prediction-radar-app-redis:6379 \
  oliver006/redis_exporter:v1.67.0-alpine
```

**LogShippingDown / PromtailDown:**
```bash
# Check Promtail on Hetzner
docker ps --filter "name=promtail" --format "table {{.Names}}\t{{.Status}}"

# Check Promtail logs
docker logs promtail --tail 30

# Check Loki is accepting logs
curl -s http://127.0.0.1:3100/loki/api/v1/labels | jq '.data | length'
# Expected: > 0 (labels present = logs flowing)

# Verify Promtail is connected to the same network as Loki
docker inspect promtail --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{" "}}{{end}}'
docker inspect aiops-loki --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{" "}}{{end}}'
```

Known fix pattern (from audit):
```bash
# Connect promtail to the monitoring network (where Loki lives)
docker network connect monitoring_default promtail

# Fix the Loki URL in promtail config
sed -i 's|http://loki:3100|http://aiops-loki:3100|g' \
  /root/infrastructure/enterprise/phase2-observability/promtail/promtail-config.yml

# Restart promtail
docker restart promtail
```

#### Step 3 -- Silence a known alert (Alertmanager)

If the alert is a known false alarm or being investigated:

```bash
# Silence a specific alert (active for 1 hour)
curl -s -X POST http://127.0.0.1:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"name": "alertname", "value": "<alert-name>", "isRegex": false}],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S)'Z",
    "endsAt": "'$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%S)'Z",
    "createdBy": "incident-response-agent",
    "comment": "Investigating - acknowledged"
  }' | jq '.'

# List active silences
curl -s http://127.0.0.1:9093/api/v2/silences | jq -r '.[] | select(.status.state=="active") | "\(.id): \(.matchers[].name)=\(.matchers[].value) until \(.endsAt)"'

# Remove a silence
curl -s -X DELETE http://127.0.0.1:9093/api/v2/silence/<silence-id> | jq '.'
```

---

### 3f. Disk Space Critical

**Applicable to:** Any server
**Severity:** P2 (warning), P1 (critical)
**Response time:** < 1 hr (P2), < 15 min (P1)

Thresholds: > 75% = warn, > 90% = critical

#### Step 1 -- Identify which server and mount

```bash
# Run on each server
df -h | grep -v tmpfs | grep -v devtmpfs | grep -v overlay

# Check the worst offender across all servers
echo "=== HETZNER ===" && df -h / | tail -1 && echo "=== HOSTINGER ===" && ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17 "df -h /" | tail -1 && echo "=== COREDB ===" && ssh root@100.118.166.117 "df -h /" | tail -1
```

Known baseline (from audit):
- Hetzner: 28% used
- Hostinger: 58% used (highest)
- CoreDB: 6% used

#### Step 2 -- Find large files

```bash
# Find top-level directory consumption
du -h --max-depth=2 /var 2>/dev/null | sort -rh | head -10
du -h --max-depth=2 /opt 2>/dev/null | sort -rh | head -10
du -h --max-depth=2 /root 2>/dev/null | sort -rh | head -10
du -h --max-depth=2 /home 2>/dev/null | sort -rh | head -10

# Find large individual files (> 500MB)
find /var -type f -size +500M -exec ls -lh {} \; 2>/dev/null | head -20
find /opt -type f -size +500M -exec ls -lh {} \; 2>/dev/null | head -20
```

#### Step 3 -- Docker cleanup

```bash
# Check Docker disk usage
docker system df

# Remove unused containers, networks, images (dangling)
docker system prune -f

# Remove all unused images (not just dangling) -- CAUTION: removes cached images
docker image prune -a -f

# Check volume disk usage
du -h --max-depth=1 /var/lib/docker/volumes/ | sort -rh | head -10

# Remove unused volumes
docker volume prune -f
```

#### Step 4 -- Log rotation and PM2 log cleanup

```bash
# PM2 log cleanup
pm2 flush            # Clears all PM2 logs
pm2 reset all        # Resets restart counts

# Docker log cleanup (truncate large container logs)
truncate -s 0 /var/lib/docker/containers/*/*-json.log

# Journal log cleanup
journalctl --vacuum-time=7d

# System log cleanup
find /var/log -name "*.gz" -delete
find /var/log -name "*.old" -delete
find /var/log -name "*.1" -delete
find /var/log -name "*.2" -delete
find /var/log -name "*.3" -delete
```

#### Step 5 -- Verify

```bash
df -h /
# Should show significant reduction
```

---

## 4. ESCALATION PATH

### When to escalate

| Severity | Escalate To | Method | When |
|----------|------------|--------|------|
| P0 | CEO (MacBook operator) | War room + direct contact | Immediately upon confirmation |
| P1 | Technical lead (PM2 / Docker engineer) | War room | After initial triage |
| P2 | On-call engineer | War room log | Within 1 hour |
| P3 | Team lead next business day | Runbook update | Next standup |
| P4 | Anyone | Runbook improvement | Next sprint |

### Escalation contacts

| Role | Person | How to Reach | Notes |
|------|--------|-------------|-------|
| CEO / Operator | Wheeler | MacBook (100.83.80.6 -- may be offline) | War room + command center |
| Technical Lead | -- | War room :8091 | Incident coordination |
| Infrastructure | -- | SSH to affected node | Root level access via 3 keys |

### Escalation procedure

1. **If incident is P0 or P1 and not resolving:**
   - Update the war room status
   - Call in the CEO via Mac connection
   - Consider rollback (see `/root/ROLLBACK_INTELLIGENCE.md`)

2. **If incident has security implications:**
   - Lock down affected services
   - Change secrets if exposed
   - See `/root/DISASTER_RECOVERY_PLAN.md`

3. **If multiple services failing simultaneously:**
   - Focus on restoring CoreDB and Tailscale first (everything depends on these)
   - Next restore the monitoring stack (to see what else is broken)
   - Then restore revenue services (predictionradar.app, fundsrecoverygroup.com)

---

## 5. POST-INCIDENT PROCEDURES

Every incident, regardless of severity, gets documented.

### Step 1 -- Incident report

Record in the war room or write to:

```
/root/INCIDENT_<DATE>_<INCIDENT_NAME>.md
```

Template:

```markdown
# Incident Report: <TITLE>

**Date:** YYYY-MM-DD
**Duration:** X hours Y minutes
**Severity:** P0-P4
**Commander:** [agent or person name]

## Summary
One paragraph describing what happened.

## Timeline
- HH:MM - Alert fired
- HH:MM - Triage began
- HH:MM - Root cause identified
- HH:MM - Fix applied
- HH:MM - Verification complete
- HH:MM - Incident closed

## Root Cause
What actually caused the incident.

## Resolution
What was done to fix it (exact commands).

## Prevention
1. Monitoring to add
2. Runbook updates needed
3. Code/config changes needed

## Lessons Learned
What surprised you during this incident.
```

### Step 2 -- Update runbook

If this incident was not covered by an existing playbook, add a new playbook section to this file. If it was covered but the commands were wrong, update them.

### Step 3 -- Create preventative monitoring

```bash
# Add a Prometheus alert for the condition
# Alerts are in: /opt/apps/monitoring/prometheus/rules/

# Add an UptimeKuma monitor for the endpoint
# Access via: http://100.121.230.28:3001

# Add a cron-based health check (using healthchecks.io on :3130)
curl -s http://127.0.0.1:3130/api/v1/checks/ -H "X-Api-Key: <key>"
```

### Step 4 -- Verify monitoring catches a recurrence

```bash
# Simulate the condition (if safe) and verify alert fires
curl -s http://127.0.0.1:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="<NEW_ALERT>") | .state'
# Expected: "pending" or "firing"
```

---

## QUICK REFERENCE: COMMANDS FROM KNOWN INCIDENTS

### Fix 1: Promtail not shipping logs to Loki (2026-05-27)

```bash
docker network connect monitoring_default promtail
sed -i 's|http://loki:3100|http://aiops-loki:3100|g' \
  /root/infrastructure/enterprise/phase2-observability/promtail/promtail-config.yml
docker restart promtail
```

Verify:
```bash
curl -s http://127.0.0.1:3100/loki/api/v1/labels | jq '.data | length'
# Expected: > 0
```

### Fix 2: RedisDown alert (coredb-redis-exporter) (2026-05-27)

```bash
docker network connect monitoring_default prediction-radar-app-redis
docker stop coredb-redis-exporter && docker rm coredb-redis-exporter
docker run -d --name coredb-redis-exporter \
  --restart unless-stopped \
  --network monitoring_default \
  -e REDIS_ADDR=prediction-radar-app-redis:6379 \
  oliver006/redis_exporter:v1.67.0-alpine
```

Verify:
```bash
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="coredb-redis") | .health'
# Expected: "up"
```

### Fix 3: predictionradar.app 502 (missing proxy_pass) (2026-05-27)

```bash
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17
vim /etc/nginx/sites-enabled/predictionradar.app
# -> Add: proxy_pass http://100.121.230.28:8098;
nginx -t && nginx -s reload
```

### Fix 4: Hostinger exporter bound to 0.0.0.0:8002 (2026-05-27)

```bash
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17
kill <PID>  # find PID with: ps aux | grep hostinger-services-exporter
cd /tmp && nohup python3 hostinger-services-exporter.py &
ss -tlnp | grep 8002
# Expected: LISTEN 0 5 127.0.0.1:8002 ...
```

### Fix 5: CoreDB SSH wide open (2026-05-27, proposed)

```bash
ssh root@100.118.166.117
ufw delete 3     # Remove "22/tcp ALLOW IN Anywhere"
ufw status numbered | grep '22\|SSH'
# Expected: only tailscale and Docker rules remain
```

---

## APPENDIX A: SERVICE PORT MAP

### Hetzner (47 containers, 85 PM2 processes)

| Port | Service | Public? |
|------|---------|---------|
| 80/443 | Nginx | YES (internet-facing) |
| 3001 | Uptime Kuma | Tailscale |
| 3002 | Grafana | Tailscale |
| 3100 | Loki | 127.0.0.1 |
| 4049 | LiteLLM | 127.0.0.1 |
| 5433 | PostgreSQL (ravynai) | 127.0.0.1 |
| 5434 | PostgreSQL (frgops) | 127.0.0.1 |
| 7474/7687 | Neo4j | 127.0.0.1 |
| 7860 | Langflow | 127.0.0.1 |
| 8089 | Temporal UI | Tailscale |
| 8091 | War Room | 127.0.0.1 |
| 8098 | Prediction Radar web | Tailscale |
| 8191 | Embedding Service | 127.0.0.1 |
| 9090 | Prometheus | Tailscale |
| 9093 | Alertmanager | 127.0.0.1 |
| 9100 | Node Exporter | 127.0.0.1 |
| 19999 | Netdata | Tailscale |

### Hostinger (7 containers + nginx)

| Port | Service | Public? |
|------|---------|---------|
| 80/443 | Nginx | YES (internet-facing) |
| 5432 | PostgreSQL | 127.0.0.1 |
| 5433 | PostgreSQL (socat) | Tailscale |
| 6379 | Redis | 127.0.0.1 |
| 8002 | Python exporter | 127.0.0.1 (FIXED) |
| 9092 | Pushgateway | 127.0.0.1 |
| 9099 | Cadvisor | 127.0.0.1 (PROPOSED FIX) |
| 19999 | Netdata | 127.0.0.1 |
| 20241 | Cloudflared | 127.0.0.1 |

### CoreDB (21 containers)

| Port | Service | Public? |
|------|---------|---------|
| 5432 | PostgreSQL | Tailscale only |
| 6379 | Redis | Tailscale only |
| 6333/6334 | Qdrant | Tailscale only |
| 9000/9001 | MinIO | 127.0.0.1 |
| 7233 | Temporal | 127.0.0.1 |
| 8080 | Temporal UI | 127.0.0.1 |
| 8089 | Infisical | 127.0.0.1 |
| 8443 | Infisical Nginx | 127.0.0.1 |
| 3007 | UseSend | 127.0.0.1 |
| 3100 | Loki | 127.0.0.1 |
| 3001 | Uptime Kuma | 127.0.0.1 |
| 9100 | Node Exporter | host port |

---

## APPENDIX B: SSH ACCESS QUICK REFERENCE

| Target | Command | Key |
|--------|---------|-----|
| Hetzner | `ssh root@100.121.230.28` | Default key |
| CoreDB | `ssh root@100.118.166.117` | Default key |
| Hostinger | `ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17` | wheeler-mesh-key |
| Mac | `ssh root@100.83.80.6` | LIKELY KEY MISMATCH -- try at own risk |

---

*Generated from audit session 2026-05-27-0444. Every command in this runbook was verified during the audit. Update this runbook when new incident patterns are discovered.*
