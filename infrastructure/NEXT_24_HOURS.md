# Wheeler Enterprise — Next 24 Hours Action Plan
**Window:** 2026-05-23 07:00 UTC → 2026-05-24 07:00 UTC
**Commander:** SRE Lead (on-call rotation)
**Classification:** EXECUTIVE — P1 Response to EDGE CPU saturation

---

## State at T=0

```
EDGE    42.4% CPU steal  load=5.13  (Hostinger VPS — host overcommitted)
AIOPS   65% idle CPU    14GB free   (Hetzner CPX51 — absorption capacity confirmed)
COREDB  99% idle CPU    29GB free   (Hetzner CX32 — severely underutilized)

Violations at T=0:
  CRITICAL: Postgres on EDGE (shared-postgres-recovery)
  CRITICAL: AI services on EDGE (private-ai-webui)
  CRITICAL: Workers on EDGE (prediction-radar-worker, scheduler, temporal-pipeline-worker)
  WARNING:  Duplicated monitoring on COREDB (prometheus, grafana, loki)
  WARNING:  PM2 backup-verification stopped on AIOPS (intentional, verify)
```

---

## Hour 0-2: Immediate Stabilization (07:00-09:00 UTC)

**Objective:** Reduce EDGE load avg below 3.0 immediately. No data moves yet — just stop/disable the worst offenders.

### Minute 0-15: Triage — Identify the CPU hogs

```bash
# === COMMAND BLOCK 1: Run from EDGE ===
ssh root@187.77.148.88

# Top 10 processes by CPU on EDGE
ps aux --sort=-%cpu | head -20

# Docker container CPU usage (top 10)
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}" 2>/dev/null | head -15

# PM2 process CPU usage
pm2 list | grep -E "online|errored" | head -20

# Check swap (must remain 0 on EDGE)
free -h
```

**Decision gate:** If `shared-postgres-recovery` is consuming >20% CPU or `private-ai-webui` is running at all → proceed to minute 15-30 block immediately.

### Minute 15-30: Stop Non-Essential Services on EDGE

```bash
# === COMMAND BLOCK 2: Run from EDGE ===

# STOP 1: private-ai-webui (AI has NO business on EDGE — CRITICAL violation)
docker stop private-ai-webui 2>/dev/null && echo "STOPPED: private-ai-webui"

# STOP 2: temporal-pipeline-worker and temporal-pipeline-scheduler (workers on EDGE — CRITICAL violation)
pm2 stop temporal-pipeline-worker 2>/dev/null && echo "STOPPED: temporal-pipeline-worker"
pm2 stop temporal-pipeline-scheduler 2>/dev/null && echo "STOPPED: temporal-pipeline-scheduler"

# STOP 3: prediction-radar-worker if present on EDGE
pm2 stop prediction-radar-worker 2>/dev/null && echo "STOPPED: prediction-radar-worker"

# STOP 4: prediction-radar-scheduler if present on EDGE
pm2 stop scheduler 2>/dev/null && echo "STOPPED: scheduler (prediction-radar)"

# Verify immediate load drop
uptime
# EXPECTED: load avg drops by at least 0.5-1.0 within 60 seconds
```

### Minute 30-45: Reduce Postgres Pressure on EDGE

```bash
# === COMMAND BLOCK 3: Run from EDGE ===

# Check Postgres connection count and active queries
docker exec shared-postgres-recovery psql -U frgops -d frgops -c \
  "SELECT count(*) AS total_conns, state, count(*) FROM pg_stat_activity GROUP BY state;"

# If >20 active connections: kill idle connections older than 5 minutes
docker exec shared-postgres-recovery psql -U frgops -d frgops -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity
   WHERE state = 'idle' AND state_change < now() - interval '5 minutes'
   AND pid <> pg_backend_pid();"

# Reduce Postgres shared_buffers temporarily (less memory pressure)
# Don't change config — just reduce work_mem at session level
docker exec shared-postgres-recovery psql -U frgops -d frgops -c \
  "ALTER SYSTEM SET work_mem = '4MB';" 2>/dev/null
docker exec shared-postgres-recovery psql -U frgops -d frgops -c \
  "SELECT pg_reload_conf();"
```

### Minute 45-60: Harden EDGE Immediately

```bash
# === COMMAND BLOCK 4: Run from EDGE ===

# Kill any zombie/defunct processes
ps aux | grep defunct | awk '{print $2}' | xargs -r kill -9

# Reduce Docker logging verbosity (log-spam is CPU cost on steal-heavy hosts)
for c in $(docker ps -q); do
  container_name=$(docker inspect "$c" --format '{{.Name}}' | sed 's/\///')
  docker inspect "$container_name" --format '{{.HostConfig.LogConfig.Type}}' | \
    grep -q 'json-file' && echo "  $container_name: json-file logging — OK (no action)"
done

# Verify UFW is blocking DB ports from public (non-Tailscale) interfaces
ufw status verbose | grep -E "5432|6379|8123|27017|9200"
# EXPECTED: All DB ports show DENY from any, or ALLOW only from 100.64.0.0/10

# Verify no 0.0.0.0 DB bindings
ss -tlnp | grep -E "0.0.0.0:(5432|6379|8123|27017)"
# EXPECTED: EMPTY (no output = no public DB ports)
```

### Hour 1-2: Verify and Document Baseline

```bash
# === COMMAND BLOCK 5: Run from EDGE ===

# Record new baseline metrics
echo "=== EDGE BASELINE at T+1h ==="
uptime
free -h | head -2
df -h / | tail -1

# === COMMAND BLOCK 6: Run from AIOPS ===
ssh root@100.64.0.3

# Verify AIOPS can receive EDGE workload
free -h | head -2
uptime
docker system df
df -h / | tail -1

# Verify all 17 online PM2 apps still healthy
pm2 list | grep -c "online"
# EXPECTED: 17 (or 18 if backup-verification just ran)
```

**Go/No-Go Gate 1 (T+2h):** EDGE load avg < 3.5? If yes → proceed to Hour 2-6. If no → escalate to Hostinger support (host overselling), consider emergency Hostinger plan upgrade.

---

## Hour 2-6: Critical Migrations (09:00-13:00 UTC)

**Objective:** Move the highest-CPU-reduction services from EDGE to AIOPS. These are the "easy wins" — services that already have AIOPS counterparts or where AIOPS has the Docker images cached.

### Task 2.1: Move Temporal Workers to AIOPS (Hour 2-3)

Temporal workers are already crash-looping on EDGE (no Temporal server). Moving them reduces EDGE CPU by ~5-8% and actually makes them functional.

```bash
# === COMMAND BLOCK 7: Run from AIOPS ===
ssh root@100.64.0.3

# Step 1: Verify Temporal server is running on AIOPS
docker ps --filter "name=temporal" --format "table {{.Names}}\t{{.Status}}"
# EXPECTED: temporal and temporal-postgres both "Up"

# Step 2: Pull EDGE PM2 ecosystem config for temporal workers
scp root@100.64.0.2:/root/.pm2/ecosystem.config.js /tmp/edge-ecosystem.config.js 2>/dev/null
# Or, if not available, create from PM2 dump:
ssh root@100.64.0.2 "pm2 show temporal-pipeline-worker" > /tmp/temporal-worker-info.txt
ssh root@100.64.0.2 "pm2 show temporal-pipeline-scheduler" > /tmp/temporal-scheduler-info.txt

# Step 3: Stop temporal workers on EDGE permanently
ssh root@100.64.0.2 "pm2 delete temporal-pipeline-worker temporal-pipeline-scheduler"
ssh root@100.64.0.2 "pm2 save"

# Step 4: Deploy temporal workers on AIOPS
# Copy the app code directory from EDGE
rsync -avz --progress \
  root@100.64.0.2:/root/apps/temporal-pipeline/ \
  /root/apps/temporal-pipeline/

# Step 5: Register workers in PM2 on AIOPS
cd /root/apps/temporal-pipeline
# Create ecosystem config with AIOPS-local Temporal server address
pm2 start ecosystem.config.js --env production
pm2 save

# Step 6: Verify workers connect to Temporal server
pm2 logs temporal-pipeline-worker --lines 20 --nostream
# EXPECTED: "Connected to Temporal server" or "Worker registered"
# If "Connection refused" → check Temporal server is on localhost:7233
#   docker exec temporal temporal operator cluster health
```

**Success criteria:**
- `pm2 list` on AIOPS shows temporal-pipeline-worker + temporal-pipeline-scheduler as "online"
- `pm2 list` on EDGE shows both as deleted (not listed)
- EDGE load avg drops by at least 0.3

### Task 2.2: Move prediction-radar-worker and scheduler to AIOPS (Hour 3-4)

These already have counterparts on AIOPS. Moving them consolidates worker execution.

```bash
# === COMMAND BLOCK 8: Run from AIOPS ===
ssh root@100.64.0.3

# Step 1: Check if prediction-radar-worker is already on AIOPS
docker ps --filter "name=prediction" --format "table {{.Names}}\t{{.Status}}"
# EXPECTED: prediction-radar-api, prediction-radar-worker, prediction-radar-scheduler all "Up"

# Step 2: If workers are dockerized on AIOPS, just stop EDGE copies
ssh root@100.64.0.2 "pm2 stop prediction-radar-worker scheduler"
ssh root@100.64.0.2 "pm2 delete prediction-radar-worker scheduler"
ssh root@100.64.0.2 "pm2 save"

# Step 3: Verify worker connectivity from AIOPS Docker containers
docker logs prediction-radar-worker --tail 20 2>/dev/null
# EXPECTED: No "Connection refused" errors, processing jobs normally

# Step 4: If prediction-radar DB is on EDGE (shared-postgres-recovery),
# update connection strings to point to AIOPS-local postgres instead.
# This is temporary — full DB migration happens in Day 2-3.
docker exec prediction-radar-api env | grep DATABASE_URL
# Record current value, update to point to AIOPS postgres:5432
```

**Success criteria:**
- Prediction radar workers removed from EDGE PM2
- AIOPS Docker workers confirmed processing jobs
- EDGE load avg drops by at least 0.5

### Task 2.3: Stop Duplicated Monitoring on COREDB (Hour 4-5)

COREDB has prometheus, grafana, loki running. These belong ONLY on AIOPS. COREDB may only run exporters.

```bash
# === COMMAND BLOCK 9: Run from COREDB ===
ssh root@100.64.0.4

# Step 1: Identify monitoring containers
docker ps --filter "name=prometheus" --format "table {{.Names}}\t{{.Status}}"
docker ps --filter "name=grafana" --format "table {{.Names}}\t{{.Status}}"
docker ps --filter "name=loki" --format "table {{.Names}}\t{{.Status}}"

# Step 2: Stop them immediately (CRITICAL: these are dashboards/write-heavy services on the data vault)
docker stop prometheus grafana loki 2>/dev/null && echo "STOPPED: COREDB monitoring stack"

# Step 3: Verify no monitoring dashboards remain
docker ps --format "table {{.Names}}\t{{.Image}}" | grep -iE "prometheus|grafana|loki|kibana|chronograf"
# EXPECTED: EMPTY (only exporters should remain)

# Step 4: Verify exporters are running (these ARE allowed on COREDB)
docker ps --filter "name=exporter" --format "table {{.Names}}\t{{.Status}}"
# EXPECTED: node_exporter, postgres_exporter, redis_exporter all "Up"

# Step 5: Configure AIOPS Prometheus to scrape COREDB exporters
ssh root@100.64.0.3 "cat /etc/prometheus/prometheus.yml | grep -A5 'coredb'"
# If coredb target is missing, add it:
# ssh root@100.64.0.3
# cat >> /etc/prometheus/prometheus.yml << 'PROMEOF'
#   - job_name: 'coredb'
#     static_configs:
#       - targets:
#         - '100.64.0.4:9100'   # node_exporter
#         - '100.64.0.4:9187'   # postgres_exporter
#         - '100.64.0.4:9121'   # redis_exporter
# PROMEOF
# docker restart prometheus
```

**Success criteria:**
- Zero monitoring dashboards on COREDB (`docker ps` shows no grafana/prometheus/loki)
- AIOPS Prometheus successfully scraping COREDB exporters
- `curl http://100.64.0.3:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="coredb") | .health'` returns "up"

### Task 2.4: Stop AI Services on EDGE (Hour 5-6)

```bash
# === COMMAND BLOCK 10: Run from EDGE ===
ssh root@100.64.0.2

# Step 1: Identify all AI-related containers
docker ps --format "table {{.Names}}\t{{.Image}}" | grep -iE \
  "ollama|litellm|langflow|vllm|localai|cuda|pytorch|tensorflow|gguf|ggml|transformers"

# Step 2: Stop each
docker stop private-ai-webui 2>/dev/null
# Remove to prevent accidental restart
docker rm private-ai-webui 2>/dev/null

# Step 3: Check for any AI model files taking disk space
du -sh /root/models/ 2>/dev/null
du -sh /data/models/ 2>/dev/null
find / -name "*.gguf" -o -name "*.ggml" -o -name "*.safetensors" 2>/dev/null | head -5
# Record locations for later migration to AIOPS

# Step 4: Verify no AI containers remain
docker ps --format "table {{.Names}}\t{{.Image}}" | grep -iE \
  "ollama|litellm|langflow|vllm|localai|cuda|pytorch|tensorflow|gguf|ggml|transformers"
# EXPECTED: EMPTY
```

**Go/No-Go Gate 2 (T+6h):**
- EDGE load avg < 2.5?
- All CRITICAL violations addressed (no DB, no AI, no workers on EDGE)?
- COREDB monitoring dashboards stopped?
- If yes → proceed to validation. If no → report blocker to CTO.

---

## Hour 6-12: Validation and Monitoring (13:00-19:00 UTC)

**Objective:** Verify every service that was moved or stopped is functioning correctly from its new location. Catch regressions early.

### Task 3.1: Full Health Check — All Servers (Hour 6-7)

```bash
# === COMMAND BLOCK 11: Run from AIOPS ===
ssh root@100.64.0.3

# Run enterprise healthcheck suite
bash /root/infrastructure/enterprise/phase4-healthcheck/healthcheck-all.sh

# Expected output per section:
#   [PASS] EDGE reachable via Tailscale (100.64.0.2)
#   [PASS] AIOPS all Docker containers healthy (24/24)
#   [PASS] COREDB reachable via Tailscale (100.64.0.4)
#   [PASS] PostgreSQL on COREDB accepting connections
#   [PASS] Redis on COREDB responding to PING
```

### Task 3.2: Verify PM2 State Across All Servers (Hour 7)

```bash
# === COMMAND BLOCK 12: Run from each server ===

# EDGE
ssh root@100.64.0.2 "pm2 list" > /tmp/edge-pm2-state.txt
echo "EDGE PM2 online: $(grep -c 'online' /tmp/edge-pm2-state.txt)"
echo "EDGE PM2 stopped: $(grep -c 'stopped' /tmp/edge-pm2-state.txt)"

# AIOPS
ssh root@100.64.0.3 "pm2 list" > /tmp/aiops-pm2-state.txt
echo "AIOPS PM2 online: $(grep -c 'online' /tmp/aiops-pm2-state.txt)"
echo "AIOPS PM2 stopped: $(grep -c 'stopped' /tmp/aiops-pm2-state.txt)"

# EXPECTED:
#   EDGE: 28-32 online (down from 39 — workers and AI removed)
#   AIOPS: 18-20 online (up from 17 — temporal workers added)
#   No "errored" or restart-looping processes on either server
```

### Task 3.3: Endpoint Smoke Test (Hour 7-8)

```bash
# === COMMAND BLOCK 13: Run from your workstation ===

# Critical endpoints (must return 200 or 3xx)
curl -so /dev/null -w "%{http_code}" https://wheeler.ai
curl -so /dev/null -w "%{http_code}" https://litellm.wheeler.ai/health
curl -so /dev/null -w "%{http_code}" https://frgops.wheeler.ai/api/health
curl -so /dev/null -w "%{http_code}" https://predictionradar.wheeler.ai/health
curl -so /dev/null -w "%{http_code}" https://ravynai.wheeler.ai/health
curl -so /dev/null -w "%{http_code}" https://superset.wheeler.ai/health
curl -so /dev/null -w "%{http_code}" https://grafana.wheeler.ai/api/health
curl -so /dev/null -w "%{http_code}" https://uptime.wheeler.ai

# EXPECTED: All return 200 or 302 (redirect to login is OK)
# If any return 502/503/504 → the upstream on AIOPS is down, check Traefik routing
# If any return 000 → DNS issue, check Cloudflare
```

### Task 3.4: Tailscale Mesh Verification (Hour 8)

```bash
# === COMMAND BLOCK 14: Run from any server ===
tailscale status
# EXPECTED: 3 nodes — edge, aiops, coredb — all showing direct connections
# Check latency
tailscale ping edge
tailscale ping aiops
tailscale ping coredb
# EXPECTED: all < 50ms (EDGE↔AIOPS ~20ms via Tailscale DERP relay if direct fails)
```

### Task 3.5: Monitor for 4 hours (Hour 8-12)

```bash
# === COMMAND BLOCK 15: Run from AIOPS ===
ssh root@100.64.0.3

# Set up a 4-hour monitoring loop (run in background)
nohup bash -c '
  for i in $(seq 1 48); do  # 48 checks at 5-min intervals = 4 hours
    echo "=== CHECK $i at $(date +%H:%M:%S) ==="
    
    # EDGE load via Tailscale
    edge_load=$(ssh -o ConnectTimeout=5 root@100.64.0.2 "uptime" 2>/dev/null | grep -oP "load average: \K.*" || echo "UNREACHABLE")
    echo "EDGE load: $edge_load"
    
    # AIOPS self-check
    echo "AIOPS load: $(uptime | grep -oP "load average: \K.*")"
    
    # COREDB health
    docker exec postgres-coredb pg_isready -U postgres 2>/dev/null && echo "COREDB PG: accepting" || echo "COREDB PG: DOWN"
    
    # Alert if EDGE load creeps back above 3.5
    load1=$(echo "$edge_load" | cut -d, -f1)
    if [ "$(echo "$load1 > 3.5" | bc -l 2>/dev/null)" = "1" ]; then
      echo "ALERT: EDGE load spiked to $load1 — investigate immediately"
    fi
    
    sleep 300
  done
' > /tmp/validation-monitor.log 2>&1 &
echo "Monitor PID: $!"

# Check in after 4 hours:
# tail -100 /tmp/validation-monitor.log
```

**Go/No-Go Gate 3 (T+12h):**
- EDGE load avg stable below 3.0 for at least 2 consecutive hours?
- Zero 502/503 errors from public endpoints?
- All PM2 apps online (except intentionally stopped backup-verification)?
- If yes → green light for stabilization period. If no → roll back the most recent change.

---

## Hour 12-24: Stabilization Period (19:00-07:00 UTC)

**Objective:** Hands-off monitoring. No new changes. If anything regresses, roll back before making new changes.

### Active Monitoring Rules

```bash
# === COMMAND BLOCK 16: Install as cron on AIOPS for overnight monitoring ===
ssh root@100.64.0.3

cat > /etc/cron.d/wheeler-stabilization << 'CRONEOF'
# Wheeler 24h stabilization monitoring — expires 2026-05-24 07:00
# Check EDGE load every 15 minutes, alert if > 3.5
*/15 * * * * root bash -c 'load=$(ssh -o ConnectTimeout=5 root@100.64.0.2 "cat /proc/loadavg" 2>/dev/null | cut -d" " -f1); if [ "$(echo "$load > 3.5" | bc -l 2>/dev/null)" = "1" ]; then echo "EDGE LOAD CRITICAL: $load at $(date)" >> /var/log/wheeler-stabilization.log; fi'

# Check all Docker containers healthy every 30 minutes
*/30 * * * * root bash -c 'unhealthy=$(docker ps --filter "health=unhealthy" -q | wc -l); if [ "$unhealthy" -gt 0 ]; then echo "UNHEALTHY CONTAINERS: $unhealthy at $(date)" >> /var/log/wheeler-stabilization.log; docker ps --filter "health=unhealthy" >> /var/log/wheeler-stabilization.log; fi'
CRONEOF

echo "Stabilization cron installed. Logs at /var/log/wheeler-stabilization.log"
```

### Morning Handoff (T+24h)

At 07:00 UTC on 2026-05-24, the on-call engineer runs:

```bash
# === COMMAND BLOCK 17: Morning handoff check ===
ssh root@100.64.0.3

# 1. Review overnight logs
cat /var/log/wheeler-stabilization.log
# EXPECTED: Empty or only "no alerts" messages

# 2. Current state snapshot
echo "=== EDGE ==="
ssh root@100.64.0.2 "uptime; free -h | head -2; df -h / | tail -1"

echo "=== AIOPS ==="
uptime; free -h | head -2; df -h / | tail -1

echo "=== COREDB ==="
ssh root@100.64.0.4 "uptime; free -h | head -2; df -h / | tail -1"

# 3. Violation audit
ssh root@100.64.0.2 "bash /root/infrastructure/enterprise/phase9-server-roles/enforce-roles.sh --server edge --report"
ssh root@100.64.0.3 "bash /root/infrastructure/enterprise/phase9-server-roles/enforce-roles.sh --server aiops --report"
ssh root@100.64.0.4 "bash /root/infrastructure/enterprise/phase9-server-roles/enforce-roles.sh --server coredb --report"

# 4. Remove stabilization cron (no longer needed)
rm /etc/cron.d/wheeler-stabilization

# 5. Update PM2 deploy state memory
# Run: /root/infrastructure/enterprise/phase7-deployment/capture-pm2-state.sh
```

---

## Go/No-Go Decision Points Summary

| Gate | Time (UTC) | Condition | Go | No-Go Action |
|------|------------|-----------|-----|--------------|
| G1 | T+2h (09:00) | EDGE load < 3.5 | Proceed to migrations | Contact Hostinger, consider plan upgrade |
| G2 | T+6h (13:00) | EDGE load < 2.5 + zero CRITICAL violations | Proceed to validation | Escalate to CTO, document blockers |
| G3 | T+12h (19:00) | EDGE load stable < 3.0 for 2h + all endpoints 200 | Green light overnight | Roll back last change, investigate |
| G4 | T+24h (07:00) | EDGE load < 2.5 + zero overnight alerts | Handoff to Day 2 | Extend stabilization, no Day 2 migrations |

### Rollback Procedure (Any Gate)

If any gate fails, roll back in reverse order of changes:

```bash
# 1. Re-enable EDGE workers (temporary)
ssh root@100.64.0.2 "pm2 resurrect"  # Restores from pm2 save before deletions

# 2. Re-start COREDB monitoring (if needed for visibility)
ssh root@100.64.0.4 "docker start prometheus grafana loki"

# 3. Do NOT re-enable AI on EDGE — that stays dead regardless
```

---

## Communications Schedule

| Time (UTC) | Audience | Channel | Content |
|------------|----------|---------|---------|
| T+0 (07:00) | #engineering | Slack | "24h stabilization window started. EDGE at 42% steal. Stand by." |
| T+2 (09:00) | #engineering | Slack | Gate 1 result + plan for next 4 hours |
| T+6 (13:00) | #engineering | Slack | Gate 2 result + validation plan |
| T+12 (19:00) | #alerts | Slack | Gate 3 result + overnight handoff |
| T+24 (07:00) | #engineering | Slack | Final state + handoff to 7-day plan |
| Any P1 event | #alerts-critical | Slack + PagerDuty | Immediate escalation per DR runbook Section 1.2 |

---

**End of 24-Hour Window**
**Next document:** NEXT_7_DAYS.md (2026-05-24 through 2026-05-30)
