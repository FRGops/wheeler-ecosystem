# Wheeler Enterprise — Next 7 Days Action Plan

**Window:** 2026-05-24 → 2026-05-30
**Commander:** SRE Team Lead
**Depends on:** NEXT_24_HOURS.md Gate G4 passed (EDGE stabilized, load < 2.5)

---

## Day 1 (2026-05-24): Database Exodus from EDGE — Complete

**Goal:** Zero databases on EDGE. shared-postgres-recovery is the last database on EDGE and must move to COREDB. This is the single highest-risk, highest-ROI migration.

### Success Criteria
- [ ] `docker ps` on EDGE shows zero PostgreSQL containers
- [ ] `ss -tlnp | grep 5432` on EDGE returns empty (no Postgres port bound)
- [ ] All FRGops data queries respond < 500ms from new COREDB location
- [ ] `enforce-roles.sh --server edge --report` shows zero CRITICAL violations
- [ ] No application errors in the 2 hours following migration

### Procedure

```bash
# === PHASE 1: Pre-flight (08:00-08:30 UTC) ===

# 1a. From AIOPS: Verify COREDB is healthy and has space
ssh root@100.64.0.3
ssh root@100.64.0.4 "df -h /data; docker exec postgres-coredb pg_isready -U postgres"
# EXPECTED: /data > 50GB free, pg_isready returns "accepting connections"

# 1b. Create target database on COREDB
ssh root@100.64.0.4
docker exec postgres-coredb psql -U postgres -c "CREATE DATABASE frgops OWNER frgops;"
# If user frgops doesn't exist:
docker exec postgres-coredb psql -U postgres -c "CREATE USER frgops WITH PASSWORD 'frgops_secure_2026';"
docker exec postgres-coredb psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE frgops TO frgops;"

# 1c. From EDGE: Dump the FRGops database
ssh root@100.64.0.2
docker exec shared-postgres-recovery pg_dump -U frgops -d frgops \
  -Fc --no-owner --no-acl -f /tmp/frgops-migration.dump
docker cp shared-postgres-recovery:/tmp/frgops-migration.dump /tmp/frgops-migration.dump
ls -lh /tmp/frgops-migration.dump
# EXPECTED: file > 0 bytes (record exact size for verification)

# 1d. Transfer dump to COREDB via AIOPS relay (NEVER EDGE→COREDB direct)
scp /tmp/frgops-migration.dump root@100.64.0.3:/tmp/frgops-migration.dump
ssh root@100.64.0.3 "scp /tmp/frgops-migration.dump root@100.64.0.4:/tmp/frgops-migration.dump"

# === PHASE 2: Restore (08:30-09:00 UTC) ===

# 2a. Restore to COREDB
ssh root@100.64.0.4
docker cp /tmp/frgops-migration.dump postgres-coredb:/tmp/frgops-migration.dump
docker exec postgres-coredb pg_restore -U frgops -d frgops \
  --clean --if-exists --no-owner --no-acl \
  /tmp/frgops-migration.dump
# EXPECTED: pg_restore completes with "0 errors" (or only benign "does not exist" warnings)

# 2b. Verify row counts between EDGE source and COREDB target
ssh root@100.64.0.2 "docker exec shared-postgres-recovery psql -U frgops -d frgops -t -c \"SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;\"" > /tmp/edge-counts.txt

ssh root@100.64.0.4 "docker exec postgres-coredb psql -U frgops -d frgops -t -c \"SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;\"" > /tmp/coredb-counts.txt

diff /tmp/edge-counts.txt /tmp/coredb-counts.txt
# EXPECTED: No differences (or only ANALYZE timing differences — run ANALYZE on both first)

# 2c. ANALYZE the restored database for accurate statistics
ssh root@100.64.0.4 "docker exec postgres-coredb psql -U frgops -d frgops -c \"ANALYZE;\""

# === PHASE 3: Cutover (09:00-09:30 UTC) ===

# 3a. Put EDGE FRGops in maintenance mode
ssh root@100.64.0.2
# Update FRGops API env to point to COREDB
# File: /root/services/frgops/.env or Docker Compose env
# Change: DATABASE_URL=postgresql://127.0.0.1:5432/frgops
# To:     DATABASE_URL=postgresql://frgops:frgops_secure_2026@100.64.0.4:5432/frgops

# Edit the appropriate .env file:
sed -i 's|DATABASE_URL=postgresql://127.0.0.1:5432/frgops|DATABASE_URL=postgresql://frgops:frgops_secure_2026@100.64.0.4:5432/frgops|g' \
  /root/services/frgops/.env 2>/dev/null
sed -i 's|DATABASE_URL=postgresql://localhost:5432/frgops|DATABASE_URL=postgresql://frgops:frgops_secure_2026@100.64.0.4:5432/frgops|g' \
  /root/services/frgops/.env 2>/dev/null

# 3b. Restart FRGops services to pick up new connection string
docker restart frgops-api frgops-worker 2>/dev/null
pm2 restart frgcrm-api 2>/dev/null

# 3c. Smoke test
curl -s https://frgops.wheeler.ai/api/health | jq .
# EXPECTED: {"status":"ok","database":"connected"} or similar

# === PHASE 4: Decommission EDGE Postgres (09:30-10:00 UTC) ===

# 4a. After 30 minutes of stable operation, stop EDGE Postgres
ssh root@100.64.0.2
docker stop shared-postgres-recovery
# DO NOT rm yet — keep volume for 24h as emergency rollback

# 4b. Verify no connections are failing
# Watch FRGops logs for 5 minutes
docker logs frgops-api --tail 50 --follow
# Ctrl+C after confirming no database errors

# 4c. Run violation audit
bash /root/infrastructure/enterprise/phase9-server-roles/enforce-roles.sh --server edge --report
# EXPECTED: Zero CRITICAL violations
```

### Rollback Procedure (if needed)

```bash
# 1. Restart EDGE Postgres
ssh root@100.64.0.2 "docker start shared-postgres-recovery"

# 2. Revert FRGops connection string
ssh root@100.64.0.2 "sed -i 's|DATABASE_URL=postgresql://frgops:frgops_secure_2026@100.64.0.4:5432/frgops|DATABASE_URL=postgresql://127.0.0.1:5432/frgops|g' /root/services/frgops/.env"

# 3. Restart FRGops
ssh root@100.64.0.2 "docker restart frgops-api frgops-worker && pm2 restart frgcrm-api"
```

---

## Day 2 (2026-05-25): Worker Consolidation on AIOPS

**Goal:** All worker/queue processing centralized on AIOPS. Zero workers on EDGE.

### Success Criteria
- [ ] `pm2 list` on EDGE shows zero worker processes (no temporal-*, no prediction-radar-*, no scheduler)
- [ ] All workers on AIOPS processing jobs (queue depth decreasing, no errors)
- [ ] EDGE load avg stable below 2.0
- [ ] `enforce-roles.sh --server edge --report` shows zero WARNING for worker violations

### Procedure

```bash
# === Verify and complete worker migration from Day 0-1 ===

# 1. Audit remaining EDGE workers
ssh root@100.64.0.2 "pm2 list | grep -iE 'worker|scheduler|queue|consumer|temporal'" > /tmp/edge-remaining-workers.txt
# EXPECTED: Empty (all workers already moved in 24h plan)

# 2. If any remain, migrate using the rsync+PM2 pattern from 24h plan Task 2.1

# 3. Verify AIOPS worker health
ssh root@100.64.0.3
pm2 list | grep -iE 'worker|scheduler'
docker ps --filter "name=worker" --format "table {{.Names}}\t{{.Status}}"
# EXPECTED: All "Up" or "online"

# 4. Check queue depths (if Redis-based BullMQ)
ssh root@100.64.0.3
docker exec redis-aio redis-cli -a "$REDIS_PASSWORD" KEYS "bull:*:waiting" 2>/dev/null | wc -l
docker exec redis-aio redis-cli -a "$REDIS_PASSWORD" KEYS "bull:*:active" 2>/dev/null | wc -l
docker exec redis-aio redis-cli -a "$REDIS_PASSWORD" KEYS "bull:*:failed" 2>/dev/null | wc -l
# EXPECTED: failed=0, waiting < 50 (normal backlog), active > 0 (jobs processing)

# 5. Check worker error logs for the last 2 hours
pm2 logs --nostream --lines 50 --err 2>/dev/null | grep -iE "error|fail|crash|refused|timeout" | tail -20
```

---

## Day 3 (2026-05-26): Monitoring Unification

**Goal:** Single Prometheus, single Grafana, single Loki — all on AIOPS. COREDB runs exporters ONLY.

### Success Criteria
- [ ] `docker ps` on COREDB shows zero monitoring dashboards (no prometheus, grafana, loki containers)
- [ ] AIOPS Prometheus scraping all 3 servers (9+ targets all "up")
- [ ] AIOPS Grafana showing data from all 3 servers
- [ ] AIOPS Loki receiving logs from all 3 servers via promtail
- [ ] Alertmanager routing test alerts to Slack

### Procedure

```bash
# === Step 1: Verify COREDB clean (from Day 0-1 Task 2.3) ===
ssh root@100.64.0.4
docker ps --format "table {{.Names}}\t{{.Image}}" | grep -iE "prom|grafana|loki"
# EXPECTED: Empty (already stopped in 24h window)

# === Step 2: Configure AIOPS Prometheus as single source ===
ssh root@100.64.0.3

# 2a. Verify all scrape targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'
# EXPECTED:
#   {job: "node", instance: "100.64.0.2:9100", health: "up"}       # EDGE
#   {job: "node", instance: "100.64.0.3:9100", health: "up"}       # AIOPS
#   {job: "node", instance: "100.64.0.4:9100", health: "up"}       # COREDB
#   {job: "postgres", instance: "100.64.0.4:9187", health: "up"}   # COREDB PG
#   {job: "redis", instance: "100.64.0.4:9121", health: "up"}      # COREDB Redis
#   {job: "cadvisor", instance: "100.64.0.3:8080", health: "up"}   # AIOPS Docker

# 2b. Add missing targets to prometheus.yml if any are absent
cat /root/infrastructure/aiops/monitoring/prometheus.yml

# 2c. Reload Prometheus config
docker exec prometheus kill -HUP 1
# Or: curl -X POST http://localhost:9090/-/reload

# === Step 3: Configure AIOPS Loki as single log sink ===
ssh root@100.64.0.3

# 3a. Verify promtail on all 3 servers
# EDGE
ssh root@100.64.0.2 "docker ps --filter 'name=promtail' --format '{{.Status}}'"
# AIOPS
docker ps --filter "name=promtail" --format "table {{.Names}}\t{{.Status}}"
# COREDB
ssh root@100.64.0.4 "docker ps --filter 'name=promtail' --format '{{.Status}}'"

# 3b. Verify logs flowing to Loki
curl -s "http://localhost:3100/loki/api/v1/labels" | jq '.data[]' | head -10
# EXPECTED: labels like "host", "job", "container_name" with values for all 3 servers
curl -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={host="edge"}' \
  --data-urlencode 'limit=3' | jq '.data.result | length'
# EXPECTED: > 0 (EDGE logs arriving)

# === Step 4: Verify Alertmanager routes ===
ssh root@100.64.0.3

# 4a. Check Alertmanager status
curl -s http://localhost:9093/api/v2/status | jq '.config.original | length'
# EXPECTED: config loaded, > 0 bytes

# 4b. Send test alert to Slack
curl -X POST http://localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[
  {
    "labels": {"alertname": "TestAlert", "severity": "info", "service": "migration"},
    "annotations": {"summary": "Day 3 monitoring unification test alert", "description": "If you see this in Slack, Alertmanager routing works."},
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }
]'
# EXPECTED: Test alert appears in #alerts Slack channel within 30 seconds
```

---

## Day 4 (2026-05-27): Backup Architecture Hardening

**Goal:** Backups centralized on COREDB. Backup verification re-enabled. Off-site sync confirmed.

### Success Criteria
- [ ] All database dumps writing to COREDB MinIO (not local AIOPS disk)
- [ ] backup-verification PM2 app re-enabled on AIOPS (was intentionally stopped)
- [ ] Off-site backup sync confirmed functional (COREDB MinIO → remote target)
- [ ] Backup integrity verified: restore 1 database to temp instance, compare row counts

### Procedure

```bash
# === Step 1: Re-enable backup-verification on AIOPS ===
ssh root@100.64.0.3
pm2 start backup-verification
pm2 status backup-verification
# EXPECTED: status = "online"
pm2 save

# === Step 2: Configure pg_dump targets to use COREDB ===
# All backup scripts should dump from COREDB (source of truth), not AIOPS-local PG
ssh root@100.64.0.3

# 2a. Find all backup scripts
find /root -name "*backup*" -o -name "*pg_dump*" -o -name "*pgdump*" 2>/dev/null | grep -v node_modules | grep -v '.git'

# 2b. For each, verify --host points to 100.64.0.4 (COREDB Tailscale)
grep -r "pg_dump" /root/backup* /root/infrastructure/enterprise/phase6-backup/ 2>/dev/null | grep -v node_modules

# 2c. Test backup from COREDB
docker exec postgres-coredb pg_dump -U frgops -d frgops -Fc -f /tmp/test-coredb-backup.dump
ls -lh /tmp/test-coredb-backup.dump  # verify non-zero

# === Step 3: Off-site backup sync ===
ssh root@100.64.0.4

# 3a. Check MinIO backup bucket
# (Adjust MinIO endpoint and credentials as configured)
curl -s http://100.64.0.4:9000/minio/health/live
# EXPECTED: HTTP 200

# 3b. List recent backups in MinIO
# Use mc (MinIO client) or aws CLI with S3-compatible endpoint
mc ls coredb-minio/backups/ 2>/dev/null | tail -10

# 3c. Verify off-site replication (if configured)
# Check rclone or rsync cron job logs
grep -i "sync\|backup\|rclone\|rsync" /var/log/syslog | tail -20

# === Step 4: Test restore (per DR runbook Section 10) ===
ssh root@100.64.0.3

# Follow DR runbook Section 10.1 (Monthly Verification):
# 1. Spin up temp postgres: docker run -d --name pg-verify -e POSTGRES_PASSWORD=verify -p 15432:5432 postgres:16-alpine
# 2. Restore latest backup: pg_restore -U postgres -d postgres --clean < latest.dump
# 3. Compare row counts with production
# 4. Clean up: docker stop pg-verify && docker rm pg-verify

# Record results in backup-verification.log
```

---

## Day 5 (2026-05-28): Security Hardening — Zero-Debt Posture

**Goal:** Every server passes `enforce-roles.sh --report` with zero CRITICAL and zero WARNING violations.

### Success Criteria
- [ ] `enforce-roles.sh --server edge --report` = zero violations (CRITICAL and WARNING)
- [ ] `enforce-roles.sh --server aiops --report` = zero violations
- [ ] `enforce-roles.sh --server coredb --report` = zero violations
- [ ] All containers carry `com.wheeler.role` label
- [ ] UFW active and enforcing on all 3 servers
- [ ] fail2ban active on all 3 servers
- [ ] SSH restricted to Tailscale IPs on all 3 servers

### Procedure

```bash
# === Step 1: Run enforcement audit on all servers ===
for server in edge aiops coredb; do
  echo "=== $server ==="
  ssh root@100.64.0.$(case $server in edge) echo 2;; aiops) echo 3;; coredb) echo 4;; esac) \
    "bash /root/infrastructure/enterprise/phase9-server-roles/enforce-roles.sh --server $server --report"
  echo ""
done

# === Step 2: Fix any violations ===
# For unlabeled containers:
#   docker update --label "com.wheeler.role=<role>" --label "com.wheeler.service=<name>" <container>
# For misplaced containers: migrate per Day 1-2 procedures
# For 0.0.0.0 bindings on COREDB/AIOPS: reconfigure service to bind Tailscale IP

# === Step 3: Verify UFW ===
for server in edge aiops coredb; do
  echo "=== $server UFW ==="
  ssh root@100.64.0.$(case $server in edge) echo 2;; aiops) echo 3;; coredb) echo 4;; esac) \
    "ufw status verbose | head -10"
done
# EXPECTED: 
#   EDGE:    Status: active, Default: deny (incoming), allow 22,80,443/tcp
#   AIOPS:   Status: active, Default: deny (incoming), allow from 100.64.0.0/10
#   COREDB:  Status: active, Default: deny (incoming), Default: deny (outgoing)

# === Step 4: Verify fail2ban ===
for server in edge aiops coredb; do
  echo "=== $server fail2ban ==="
  ssh root@100.64.0.$(case $server in edge) echo 2;; aiops) echo 3;; coredb) echo 4;; esac) \
    "fail2ban-client status sshd 2>/dev/null | grep -E 'Status|Currently banned'"
done
# EXPECTED: Status = "active" on all 3

# === Step 5: Verify SSH hardening ===
for server in edge aiops coredb; do
  echo "=== $server SSH ==="
  ssh root@100.64.0.$(case $server in edge) echo 2;; aiops) echo 3;; coredb) echo 4;; esac) \
    "grep -E '^PasswordAuthentication|^PermitRootLogin|^PubkeyAuthentication' /etc/ssh/sshd_config"
done
# EXPECTED:
#   PasswordAuthentication no (on all 3)
#   PermitRootLogin prohibit-password or no (on all 3)
#   PubkeyAuthentication yes (on all 3)
```

---

## Day 6 (2026-05-29): Documentation and DR Readiness

**Goal:** All documentation reflects current topology. DR runbook validated with a partial test.

### Success Criteria
- [ ] ARCHITECTURE.md updated with current service placements
- [ ] server-role-policies.md updated if any exceptions were granted
- [ ] DR runbook walkthrough completed (tabletop exercise per Section 12)
- [ ] IP address references verified against actual Tailscale IPs
- [ ] Contact sheet in DR runbook filled in with actual names/numbers

### Procedure

```bash
# === Step 1: Update ARCHITECTURE.md ===
# Key changes to document:
#   - FRGops DB now on COREDB (100.64.0.4:5432), not EDGE
#   - Temporal workers on AIOPS, not EDGE
#   - Private AI WebUI removed from EDGE
#   - Monitoring unified on AIOPS (Prometheus, Grafana, Loki)
#   - COREDB exporters only (node_exporter, postgres_exporter, redis_exporter)

vim /root/infrastructure/ARCHITECTURE.md
# Edit the SERVICE PLACEMENT MATRIX tables

# === Step 2: Verify all scripts reference correct IPs ===
ssh root@100.64.0.3
grep -r "100.98.22.10" /root/infrastructure/ /root/scripts/ 2>/dev/null | grep -v ".git"
# EXPECTED: Empty (all old IPs replaced; should have been done in phase migration)
grep -r "100.98.163.17" /root/infrastructure/ /root/scripts/ 2>/dev/null
# EXPECTED: References to current EDGE Tailscale IP if any remain (should be 100.64.0.2)

# Verify all references use current Tailscale IPs:
# EDGE:    100.64.0.2 (was 100.98.163.17, was 100.98.22.10)
# AIOPS:   100.64.0.3 (was 100.121.230.28)
# COREDB:  100.64.0.4 (was 100.118.166.117)

grep -r "100\.121\.230\.28\|100\.118\.166\.117\|100\.98\.163\.17\|100\.98\.22\.10" \
  /root/infrastructure/ 2>/dev/null | grep -v ".git" | grep -v ARCHITECTURE.md
# EXPECTED: Empty or only in historical/changelog sections

# === Step 3: Tabletop DR exercise ===
# Per DR runbook Section 11:
# Walk through EDGE Server Total Loss (Section 3) verbally with team
# Confirm: steps are clear, IPs are correct, commands work
# Time: 1 hour
# Record action items from the walkthrough

# === Step 4: Fill in emergency contacts ===
# Update DR runbook Section 12 with actual names, phones, emails
```

---

## Day 7 (2026-05-30): End State Verification and Handoff

**Goal:** Full system audit. Declare stabilization phase complete. Hand off to steady-state operations.

### Success Criteria
- [ ] EDGE CPU steal < 25% (still degraded from Hostinger overcommit, but manageable)
- [ ] EDGE load avg < 2.0 sustained for 24+ hours
- [ ] AIOPS CPU usage 35-55% (healthy utilization)
- [ ] COREDB RAM usage > 4GB (actually using the 29GB available — databases moved in)
- [ ] Zero CRITICAL violations across all 3 servers
- [ ] All PM2 apps online (including backup-verification re-enabled Day 4)
- [ ] All Docker containers healthy (zero "unhealthy" state)
- [ ] All health check endpoints return 200
- [ ] Daily backups verified (at least 1 restore test completed this week)
- [ ] FINAL_STABILIZATION_CHECKLIST.md completed and signed off

### Procedure

```bash
# === Step 1: Full system state snapshot ===
cat > /tmp/final-audit.sh << 'AUDITEOF'
#!/bin/bash
echo "=========================================="
echo " WHEELER 7-DAY STABILIZATION FINAL AUDIT"
echo " Date: $(date -u)"
echo "=========================================="
echo ""

# EDGE
echo "--- EDGE (100.64.0.2) ---"
ssh -o ConnectTimeout=5 root@100.64.0.2 "
  echo 'Load: ' \$(uptime | grep -oP 'load average: \K.*')
  echo 'Memory: ' \$(free -h | awk '/^Mem:/{print \$3\"/\"\$2\" used (\"\$4\" free)\"}')
  echo 'Disk: ' \$(df -h / | awk 'NR==2{print \$3\"/\"\$2\" used (\"\$5\")\"}')
  echo 'Docker containers: ' \$(docker ps -q | wc -l)
  echo 'PM2 online: ' \$(pm2 list 2>/dev/null | grep -c 'online')
  echo 'PM2 stopped: ' \$(pm2 list 2>/dev/null | grep -c 'stopped')
  echo 'CPU steal: ' \$(top -bn1 | grep '^%Cpu' | grep -oP '\K[0-9.]+(?= st)')
  echo 'Swap: ' \$(free -h | awk '/^Swap:/{print \$3\"/\"\$2}')
" 2>/dev/null
echo ""

# AIOPS
echo "--- AIOPS (100.64.0.3) ---"
ssh -o ConnectTimeout=5 root@100.64.0.3 "
  echo 'Load: ' \$(uptime | grep -oP 'load average: \K.*')
  echo 'Memory: ' \$(free -h | awk '/^Mem:/{print \$3\"/\"\$2\" used (\"\$4\" free)\"}')
  echo 'Disk: ' \$(df -h / | awk 'NR==2{print \$3\"/\"\$2\" used (\"\$5\")\"}')
  echo 'Docker containers: ' \$(docker ps -q | wc -l)
  echo 'PM2 online: ' \$(pm2 list 2>/dev/null | grep -c 'online')
  echo 'PM2 stopped: ' \$(pm2 list 2>/dev/null | grep -c 'stopped')
  echo 'Docker unhealthy: ' \$(docker ps --filter 'health=unhealthy' -q | wc -l)
  echo 'Swap: ' \$(free -h | awk '/^Swap:/{print \$3\"/\"\$2}')
" 2>/dev/null
echo ""

# COREDB
echo "--- COREDB (100.64.0.4) ---"
ssh -o ConnectTimeout=5 root@100.64.0.4 "
  echo 'Load: ' \$(uptime | grep -oP 'load average: \K.*')
  echo 'Memory: ' \$(free -h | awk '/^Mem:/{print \$3\"/\"\$2\" used (\"\$4\" free)\"}')
  echo 'Disk: ' \$(df -h /data | awk 'NR==2{print \$3\"/\"\$2\" used (\"\$5\")\"}')
  echo 'Docker containers: ' \$(docker ps -q | wc -l)
  echo 'Database size: ' \$(docker exec postgres-coredb psql -U postgres -t -c \"SELECT pg_size_pretty(pg_database_size('frgops'));\" 2>/dev/null || echo 'N/A')
  echo 'Swap: ' \$(free -h | awk '/^Swap:/{print \$3\"/\"\$2}')
" 2>/dev/null
echo ""

# Violation audit
echo "--- ROLE COMPLIANCE ---"
for role in edge aiops coredb; do
  echo -n "$role: "
  case $role in
    edge) ip=2;;
    aiops) ip=3;;
    coredb) ip=4;;
  esac
  critic=$(ssh -o ConnectTimeout=5 root@100.64.0.$ip \
    "bash /root/infrastructure/enterprise/phase9-server-roles/enforce-roles.sh --server $role --report 2>/dev/null | grep -c 'CRITICAL'" 2>/dev/null)
  echo "$critic CRITICAL violations"
done
echo ""

# Endpoints
echo "--- ENDPOINT HEALTH ---"
for endpoint in wheeler.ai litellm.wheeler.ai/health frgops.wheeler.ai/api/health predictionradar.wheeler.ai/health ravynai.wheeler.ai/health; do
  code=$(curl -so /dev/null -w "%{http_code}" "https://$endpoint" 2>/dev/null)
  echo "$endpoint: HTTP $code"
done
AUDITEOF

bash /tmp/final-audit.sh | tee /root/infrastructure/7-day-final-audit-$(date +%Y%m%d).log

# === Step 2: Complete the stabilization checklist ===
# Go through FINAL_STABILIZATION_CHECKLIST.md and check every box
# Any unchecked box becomes an action item for the following week

# === Step 3: Sign off ===
# Meeting with SRE Lead, CTO to review:
# 1. Final audit results
# 2. FINAL_STABILIZATION_CHECKLIST.md
# 3. Any remaining WARNING-level items
# 4. Go-forward monitoring plan
```

### End State Definition (Day 7 Done)

```
EDGE     Load < 2.0    CPU steal < 25%   (Hostinger-limited)
         Role: Gatekeeper only — Traefik, nginx, static files
         Violations: ZERO

AIOPS    CPU ~40-50%   RAM ~18-22GB used  (healthy utilization)
         Role: The Brain — all compute, AI, APIs, workers, monitoring
         Violations: ZERO

COREDB   CPU < 10%     RAM > 4GB used     (databases in memory)
         Role: The Vault — databases, object storage, vector store, backups
         Violations: ZERO

Monitoring:  Single Prometheus + Grafana + Loki on AIOPS
Backups:     Centered on COREDB MinIO, off-site sync verified
Security:    UFW + fail2ban on all 3, Tailscale-only SSH, no 0.0.0.0 DB ports
Docs:        Updated, DR runbook validated via tabletop exercise
```

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Hostinger CPU steal worsens (>50%) | Medium | High — EDGE becomes unusable | Day 1: Contact Hostinger support. Fallback: migrate Traefik to AIOPS + use Cloudflare Tunnel for public entry |
| FRGops DB migration causes data loss | Low | Critical — business data | Pre-migration dump verified; keep EDGE volume 24h; row count diff before cutover |
| Temporal workers fail on AIOPS | Medium | Medium — workflow engine down | Verify Temporal server health before migration; keep EDGE config backup |
| AIOPS capacity exceeded after absorbing EDGE workload | Low | Medium — service degradation | Monitor CPU/RAM hourly Days 1-3; AIOPS has 65% idle CPU and 14GB RAM — ample headroom |
| COREDB becomes bottleneck (single DB) | Low | High — all apps affected | pgBouncer connection pooling; monitor query latency; read replicas on AIOPS if needed |
| Tailscale partition during migration | Low | High — cross-server traffic fails | Verify mesh before every ssh/scp operation; keep local fallback commands documented |
| DNS propagation issues if EDGE IP changes | Very Low | Critical | EDGE IP not planned to change; if forced, follow DR Section 3 Step 5 precisely |
| Human error (wrong server, wrong container stopped) | Medium | Varies | Each command block lists target server explicitly; validate with `hostname` before destructive ops |

---

## Daily Standup Cadence

| Time (UTC) | Duration | Attendees | Purpose |
|------------|----------|-----------|---------|
| 08:00 | 15 min | SRE Lead, on-call, CTO (optional) | Review previous 24h, confirm Day N plan |
| 17:00 | 10 min | SRE Lead, on-call | Mid-day checkpoint, blocker escalation |

---

## Communications

| Event | Channel | Message Template |
|-------|---------|-----------------|
| Day 1 start | #engineering | "7-day stabilization begins. Day 1: Database exodus from EDGE. Stand by for cutover window 09:00-10:00 UTC." |
| Day 1 cutover | #engineering | "FRGops DB cutover in progress. Expected 30-min window. Service may be briefly interrupted." |
| Day 1 complete | #engineering | "FRGops DB migrated to COREDB. Zero errors. EDGE load: X.XX (was 5.13)." |
| Each day complete | #engineering | "Day N complete. [Success criteria met / Blockers: X]. Tomorrow: Day N+1 [goal]." |
| Day 7 complete | #company | "Wheeler 7-day stabilization complete. 3-server architecture fully compliant. See audit: /root/infrastructure/7-day-final-audit-20260530.log" |

---

**End of 7-Day Window**
**Next document:** NEXT_30_DAYS.md (2026-05-31 through 2026-06-29)
