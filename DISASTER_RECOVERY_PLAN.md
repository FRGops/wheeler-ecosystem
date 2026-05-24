# Disaster Recovery Plan — Wheeler Autonomous AI Ops

> **Purpose:** Define RPO/RTO targets, document recovery procedures for every failure scenario, and establish a testing cadence that ensures recoverability.
> **Classification:** OPERATIONS — Disaster Recovery
> **Last Updated:** 2026-05-24

---

## 1. Disaster Recovery Overview

### 1.1 Recovery Objectives

| Tier | Category               | RPO (Recovery Point Objective) | RTO (Recovery Time Objective) | Examples                          |
|------|------------------------|-------------------------------|-------------------------------|-----------------------------------|
| T0   | Critical infrastructure| 0 minutes (no data loss)      | < 5 minutes                   | Traefik routing, PostgreSQL       |
| T1   | Business applications  | < 5 minutes                   | < 15 minutes                  | FRGops API, LiteLLM, CRM          |
| T2   | AI/Worker processes    | < 15 minutes                  | < 30 minutes                  | Prediction radar, agents          |
| T3   | Monitoring & analytics | < 1 hour                      | < 2 hours                     | Prometheus, Grafana, Loki         |
| T4   | Historical data        | < 24 hours                    | < 24 hours                    | Old backups, logs archive         |

### 1.2 Three-Server Architecture

```
EDGE   (100.64.0.2 / Hostinger)  — Gatekeeper: Traefik, nginx, SSL termination
AIOPS  (100.64.0.3 / Hetzner)    — Brain: all APIs, AI, workers, monitoring  
COREDB (100.64.0.4 / Hetzner)    — Vault: PostgreSQL, Redis, MinIO, backups
```

**Key principle:** No single server is irrecoverable because data is distributed. EDGE has no persistent data. COREDB has all persistent data. AIOPS has compute-only state (PM2, Docker volumes) that can be regenerated.

### 1.3 Backup Architecture

```
┌────────────────────────────────────────────────────────────┐
│                     BACKUP ARCHITECTURE                      │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  COREDB MinIO ── backups bucket ────────────────────────── │
│    ├── databases/    (pg_dump -Fc, nightly)                 │
│    ├── configs/      (.env, docker-compose, ecosystem)     │
│    ├── wal/          (WAL archive, continuous)              │
│    ├── redis/        (RDB snapshots, nightly)               │
│    └── offsite/      (rclone sync to remote S3, nightly)   │
│                                                            │
│  /root/backups/  ── filesystem backups ─────────────────── │
│    ├── hostinger/   (EDGE backups, daily)                  │
│    ├── wheeler-ecosystem-20260523-205529/  (full snapshot) │
│    └── .../                                                │
│                                                            │
│  /var/backups/deployments/  ── rollback backups ────────── │
│    ├── <service>/<env>/<timestamp>/                        │
│    │   ├── docker/     (docker-compose.yml, volumes)       │
│    │   ├── pm2/        (ecosystem.config.js, dump.pm2)     │
│    │   ├── routing/    (Traefik, Nginx configs)            │
│    │   ├── env/        (.env files)                        │
│    │   ├── MANIFEST    (file listing)                      │
│    │   ├── VERSION     (deployment version)                │
│    │   └── SHA256SUMS  (checksums)                         │
│    └── rollback-history.jsonl  (audit trail)               │
│                                                            │
│  /root/rollback-engine/  ── recovery tools ─────────────── │
│    ├── rollback.sh              (master orchestrator)      │
│    ├── common-rollback.sh       (shared functions)         │
│    ├── restore-env.sh           (.env restoration)         │
│    ├── restore-docker.sh        (Docker service restore)   │
│    ├── restore-pm2.sh           (PM2 process restore)      │
│    └── restore-routing.sh       (Traefik/Nginx restore)    │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### 1.4 Backup Schedule

| What                              | When              | Tool                   | Stored To          |
|-----------------------------------|-------------------|------------------------|--------------------|
| PostgreSQL full dump              | Daily 02:00 UTC   | pg_dump -Fc            | COREDB MinIO       |
| PostgreSQL WAL archive            | Continuous        | archive_command        | COREDB MinIO       |
| Redis RDB snapshot                | Daily 03:00 UTC   | redis-cli BGSAVE       | COREDB MinIO       |
| Configuration files               | On deploy         | backup_configs()       | /var/backups/      |
| PM2 process list                  | On deploy         | pm2 save               | /var/backups/      |
| Offsite sync (MinIO to remote)    | Daily 05:00 UTC   | rclone sync            | Remote S3          |
| Backup verification (temp restore)| Weekly Sun 04:00  | pgBackRest/restore     | Local temp         |
| MinIO bucket snapshot             | Monthly 1st       | mc mirror              | Archive bucket     |

---

## 2. Failure Scenarios & Recovery Procedures

### 2.1 Single Docker Container Failure

**Symptoms:**
- Docker container status shows "unhealthy" or "restarting"
- Alert from Prometheus: `ContainerUnhealthy`
- Service returns 502/503 through Traefik

**Impact:** Single service degraded. Other services unaffected.

**RTO:** < 2 minutes
**RPO:** N/A (no persistent data loss for stateless containers)

**Recovery Procedure:**

```bash
# Step 1: Identify the failing container
docker ps --filter "health=unhealthy" --format "table {{.Names}}\t{{.Status}}\t{{.Restarts}}"
# Example output:
# langflow          unhealthy    12

# Step 2: Inspect container logs
docker logs --tail 50 langflow 2>&1 | grep -iE "error|fatal|panic|oom|killed|exit"

# Step 3: Check container resource usage
docker stats langflow --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}"

# Step 4: Restart with the same configuration
docker restart langflow

# Step 5: Monitor after restart (wait 30 seconds)
docker inspect langflow --format '{{.State.Health.Status}}'
# Expected: healthy

# Step 6: If restart fails repeatedly:
# a) Check if OutOfMemory: dmesg | grep -i "oom" | tail -5
# b) If OOM, increase memory limit in docker-compose.yml
# c) If config error, restore from latest backup:
/root/rollback-engine/rollback.sh langflow production

# Step 7: If container has persistent data, verify volume integrity:
docker run --rm -v langflow_data:/data alpine ls -la /data
```

### 2.2 Single PM2 Process Failure

**Symptoms:**
- PM2 process shows "errored" or "stopped"
- Alert: `pm2 list` shows < 20 online processes
- Application logs show connection refused

**Impact:** Single process affected. Other PM2 apps unaffected.

**RTO:** < 1 minute
**RPO:** N/A (PM2 processes are stateless or connect to COREDB databases)

**Recovery Procedure:**

```bash
# Step 1: Identify the failed process
pm2 list | grep -v "online"
# Example output:
# frgcrm-api    errored    5     # 5 restarts = crash loop

# Step 2: Check error logs
pm2 logs frgcrm-api --lines 30 --nostream --err

# Step 3: Try restart
pm2 restart frgcrm-api

# Step 4: Monitor for 30 seconds
sleep 30
pm2 show frgcrm-api | grep -E "status|restart_time|uptime"
# Expected: status online, restart_time stable

# Step 5: If crash loop persists (< 30s uptime after restart):
# a) Check common root cause: DEEPSEEK_API_KEY
pm2 env frgcrm-api | grep DEEPSEEK_API_KEY
# If empty, the env var was cleared — apply the env -i delete+start pattern:

# b) Delete the broken process (preserves env stored in pm2)
pm2 delete frgcrm-api

# c) Restart with env -i to ensure clean environment:
env -i $(cat /root/.env.frgcrm-api | xargs) pm2 start /opt/services/frgcrm-api/ecosystem.config.js \
  --env production --name frgcrm-api 2>&1 | head -20

# d) Verify
pm2 show frgcrm-api | grep "status"
pm2 save

# Step 6: If config is corrupted, restore from deployment backup:
/root/rollback-engine/rollback.sh frgcrm-api production
```

### 2.3 Docker Daemon Failure

**Symptoms:**
- `docker ps` returns "Cannot connect to the Docker daemon"
- All Docker containers go down simultaneously
- Multiple service alerts firing at once
- `systemctl status docker` shows "inactive (dead)" or "failed"

**Impact:** All Docker containers on that server are down. PM2 processes on same server may still function.

**RTO:** < 5 minutes
**RPO:** N/A (Docker volumes persist on disk)

**Recovery Procedure:**

```bash
# Step 1: Verify Docker daemon status
systemctl status docker --no-pager -l
journalctl -u docker --no-pager -n 50

# Step 2: Attempt to start Docker daemon
systemctl start docker

# Step 3: If start fails, check for common issues:
# a) Disk full (Docker cannot write):
df -h /
# If > 90% full: free space via docker system prune -af

# b) Corrupt Docker state:
systemctl stop docker
mv /var/lib/docker /var/lib/docker.corrupt.$(date +%Y%m%d)
# Restore from last known-good backup if available:
# cp -a /var/backups/docker-state/YYYYMMDD /var/lib/docker
systemctl start docker

# c) containerd issue:
systemctl status containerd
systemctl restart containerd
systemctl restart docker

# Step 4: After Docker is running, restore all containers
cd /root/infrastructure/aiops
for compose_file in $(find . -name "docker-compose.yml"); do
  echo "Starting: $compose_file"
  cd "$(dirname "$compose_file")"
  docker compose up -d
  cd - > /dev/null
done

# Step 5: Verify all containers come up healthy
sleep 30
docker ps --format "table {{.Names}}\t{{.Status}}" | head -40

# Step 6: Check for any missing or unhealthy
docker ps --filter "health=unhealthy" --format "{{.Names}}"
docker ps --filter "status=exited" --format "{{.Names}}"
```

### 2.4 PM2 Daemon Failure

**Symptoms:**
- `pm2 list` returns "No such file or directory" or connection refused
- All PM2 processes go down simultaneously
- `pm2 ping` fails

**Impact:** All PM2-managed applications on that server are down.

**RTO:** < 3 minutes
**RPO:** N/A (PM2 dump saved on disk)

**Recovery Procedure:**

```bash
# Step 1: Verify PM2 daemon status
pm2 ping
# If fails: "{\"msg\":\"pong\"}" = alive, anything else = dead

# Step 2: Check if PM2 process exists
ps aux | grep "PM2" | grep -v grep
# If no output, PM2 daemon is dead

# Step 3: Check PM2 home directory exists
ls -la ~/.pm2/

# Step 4: Resurrect PM2 from saved dump
pm2 resurrect
# If resurrection fails:
pm2 kill  # Kill any stale PM2 daemon
pm2 start ~/.pm2/dump.pm2 2>&1 | tail -20

# Step 5: If dump.pm2 is missing or corrupt:
# List ecosystem files and start each one manually
find /opt/wheeler -name "ecosystem.config.js" -o -name "ecosystem.config.cjs" 2>/dev/null
for eco in $(find /opt/wheeler -name "ecosystem.config.js" 2>/dev/null); do
  pm2 start "$eco" --env production
done

# Step 6: Save restored state
pm2 save

# Step 7: Verify all processes restored
pm2 list | grep -c "online"
# Expected: 20 on AIOPS

# Step 8: Set PM2 to start on boot
pm2 startup systemd -u root --hp /root
pm2 save
```

### 2.5 Database Corruption

**Symptoms:**
- Application errors: "relation does not exist", "database corruption", "invalid page in block"
- PostgreSQL logs: "WARNING: page verification failed", "ERROR: invalid page header"
- pg_dump fails with checksum errors
- Query results missing or nonsensical

**Impact:** Data loss or service outage for all applications using that database.

**RTO:** < 30 minutes (from backup)
**RPO:** < 24 hours (nightly backup) or < 5 minutes (WAL archive)

**Recovery Procedure:**

```bash
# === PHASE 1: Assess Damage ===
# Step 1: Check PostgreSQL logs
docker logs postgres-coredb --tail 100 2>&1 | grep -iE "error|corrupt|invalid|fatal|panic"

# Step 2: Identify corrupt database
docker exec postgres-coredb psql -U postgres -c "
  SELECT datname, pg_size_pretty(pg_database_size(datname)) as size
  FROM pg_database WHERE datistemplate = false ORDER BY 2 DESC;"

# Step 3: Check specific table corruption
docker exec postgres-coredb psql -U postgres -d frgops -c "SELECT count(*) FROM pg_class;"

# === PHASE 2: Isolate ===
# Step 4: If single database corruption:
docker exec postgres-coredb psql -U postgres -c "ALTER DATABASE frgops ALLOW_CONNECTIONS = false;"
# Notify all connected apps to reconnect (they will fail and retry with backoff)

# Step 5: Revoke connections
docker exec postgres-coredb psql -U postgres -c "
  SELECT pg_terminate_backend(pid) FROM pg_stat_activity
  WHERE datname = 'frgops' AND pid <> pg_backend_pid();"

# === PHASE 3: Restore from Backup ===
# Step 6: Restore the corrupt database from latest backup
# Find the latest backup:
ssh root@100.64.0.4 "mc ls coredb-minio/backups/databases/" | sort -r | head -5

# Step 7: Download and restore
ssh root@100.64.0.4 "
  LATEST=\$(mc ls coredb-minio/backups/databases/ | sort -r | head -1 | awk '{print \$NF}')
  mc cp coredb-minio/backups/databases/\$LATEST /tmp/
  docker cp /tmp/\$LATEST postgres-coredb:/tmp/
  docker exec postgres-coredb pg_restore -U postgres -d frgops --clean --if-exists /tmp/\$LATEST
"

# Step 8: If WAL archiving is enabled, point-in-time recovery to just before corruption:
# docker exec postgres-coredb psql -U postgres -c "
#   SELECT pg_wal_replay_resume();
# "
# Follow PostgreSQL PITR procedure with recovery.conf / recovery.signal

# === PHASE 4: Verify ===
# Step 9: Verify restored data
docker exec postgres-coredb psql -U postgres -d frgops -c "
  SELECT schemaname, count(*) as tables
  FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')
  GROUP BY schemaname;"

# Step 10: Re-enable connections
docker exec postgres-coredb psql -U postgres -c "ALTER DATABASE frgops ALLOW_CONNECTIONS = true;"

# Step 11: Verify application connectivity
curl -s https://frgops.wheeler.ai/api/health | jq .
```

### 2.6 Disk Full

**Symptoms:**
- `df -h` shows > 85% utilization
- `docker exec` fails with "no space left on device"
- PostgreSQL writes fail with "could not extend file"
- System logs: "No space left on device"
- Alerts from `predict_linear(node_filesystem_free_bytes[1h], 86400) < 0`

**Impact:** All write operations fail. Read operations may continue. Recovery time depends on severity.

**RTO:** < 10 minutes (emergency cleanup) or < 1 hour (add storage)
**RPO:** Risk of data loss if cleanup deletes unflushed data

**Recovery Procedure:**

```bash
# === PHASE 1: Emergency Free Space ===
# Step 1: Identify largest space consumers
du -sh /* 2>/dev/null | sort -rh | head -10
du -sh /var/lib/docker/* 2>/dev/null | sort -rh | head -10

# Step 2: Immediate Docker cleanup (reclaims 5-15 GB typically)
docker system prune -af --filter "until=24h" 2>&1 | tail -5
docker volume ls -qf dangling=true | xargs -r docker volume rm

# Step 3: Clean Docker log files (if using json-file driver — largest consumer)
truncate -s 0 $(find /var/lib/docker/containers/ -name "*-json.log" 2>/dev/null)
# WARNING: This clears ALL container logs. Acceptable in emergency.

# Step 4: Prune old Prometheus data blocks
# Prometheus compactor retains 30d by default, but if retention was increased:
curl -s -X POST 'http://localhost:9090/api/v1/admin/tsdb/delete_series?match[]={job=~".+"}' 2>/dev/null

# Step 5: Prune old Loki chunks (if retention > 14 days)
# Loki stores chunks per day — dropping oldest data:
docker exec loki rm -rf /var/lib/loki/chunks/$(date -d '30 days ago' +%Y-%m-%d) 2>/dev/null

# Step 6: Check freed space
df -h /

# === PHASE 2: If still critical, last resort cleanup ===
# Step 7: Remove unused Docker images more aggressively
docker image prune -af 2>&1 | tail -3

# Step 8: Clean apt cache
apt-get clean
rm -rf /var/cache/apt/archives/*.deb 2>/dev/null

# Step 9: Clean journald logs (keep only 3 days)
journalctl --vacuum-time=3d

# === PHASE 3: Prevention ===
# Step 10: Install monitoring if not already present
# Already covered by Prometheus disk-filling alert

# Step 11: Set Docker log rotation globally
cat >> /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker
# NOTE: Restarting Docker restarts all containers. Schedule this.

# Step 12: Add cron for weekly cleanup if not already configured
# /etc/cron.weekly/docker-prune exists? Verify:
ls -la /etc/cron.weekly/docker-prune
```

### 2.7 Network Failure (Tailscale Down)

**Symptoms:**
- `tailscale status` shows one or more nodes as "offline"
- SSH to other servers fails
- Cross-server database connections fail
- Applications on one server cannot reach databases on another

**Impact:** EDGE→AIOPS, AIOPS→COREDB, and any cross-server communication breaks.

**RTO:** < 10 minutes
**RPO:** N/A (no data loss)

**Recovery Procedure:**

```bash
# === PHASE 1: Assess ===
# Step 1: Check Tailscale status on the local server
tailscale status
# Expected:
# 100.64.0.2  edge     -       linux   active; direct
# 100.64.0.3  aiops    -       linux   active; direct
# 100.64.0.4  coredb   -       linux   active; direct

# Step 2: Check which nodes are unreachable
for node in edge aiops coredb; do
  ping -c 2 -W 3 "$node.tailscale.network" 2>/dev/null && echo "$node: OK" || echo "$node: DOWN"
done

# Step 3: Check Tailscale daemon status
systemctl status tailscaled --no-pager -l

# === PHASE 2: Restart Tailscale ===
# Step 4: Restart Tailscale on the affected server(s)
systemctl restart tailscaled

# Step 5: Wait for reconnection (10-30 seconds)
sleep 15
tailscale status

# Step 6: If restart doesn't work, re-authenticate:
tailscale up --auth-key tskey-xxxx  # Get fresh key from Tailscale admin console

# === PHASE 3: Cross-Server Verification ===
# Step 7: Verify cross-server connectivity
# From AIOPS → COREDB:
ssh root@100.64.0.4 "pg_isready -h 100.64.0.4 -U postgres"

# Step 8: Verify all database connections restore
docker exec postgres-coredb psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Step 9: Verify monitoring continuity
curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# === PHASE 4: If Tailscale Cannot Recover (fallback to public IPs) ===
# Step 10: Temporarily allow direct connections on public IPs for critical traffic
# ONLY as emergency measure — re-restrict as soon as Tailscale is restored

# On COREDB, temporarily bind PostgreSQL to listen on public IP as fallback:
docker exec postgres-coredb bash -c "echo 'listen_addresses = '\''*'\''' >> /var/lib/postgresql/data/postgresql.conf"
docker exec postgres-coredb psql -U postgres -c "SELECT pg_reload_conf();"
# WARNING: This exposes PostgreSQL to the public internet. Add UFW rule FIRST:
ufw allow from 5.78.140.118 to any port 5432 proto tcp

# Step 11: Update application connection strings to use public IPs temporarily
# (e.g., change 100.64.0.4 to 5.78.210.123 in docker-compose.yml)

# Step 12: Once Tailscale is restored, revert immediately:
docker exec postgres-coredb bash -c "sed -i 's/listen_addresses = '\''*'\''/listen_addresses = '\''100.118.166.117'\''/' /var/lib/postgresql/data/postgresql.conf"
docker exec postgres-coredb psql -U postgres -c "SELECT pg_reload_conf();"
ufw delete allow from 5.78.140.118 to any port 5432 proto tcp
```

### 2.8 Full Node Failure (Hetzner — AIOPS or COREDB)

**Symptoms:**
- Server is completely unreachable via SSH (public and Tailscale)
- All services on that server are down
- Hetzner Cloud Console shows server as "off" or "error"
- No ping response for > 5 minutes

**Impact:** Total loss of all services on the failed node.

**RTO:** < 1 hour (restore from backup to replacement node)
**RPO:** < 24 hours (nightly backups) or point of last WAL archive

**Recovery Procedure:**

```bash
# === PHASE 1: Verify Total Failure ===
# Step 1: Attempt SSH from multiple sources
ssh -o ConnectTimeout=10 root@5.78.140.118  # AIOPS public IP
ssh -o ConnectTimeout=10 root@100.64.0.3    # AIOPS Tailscale IP
# Both fail = complete node failure

# Step 2: Check Hetzner Cloud Console
# Login to: https://console.hetzner.cloud
# Check server status, power on if off

# === PHASE 2: Provision Replacement ===
# Step 3: If soft reboot fails, provision replacement via Hetzner API:
# NOTE: Requires hcloud CLI: https://github.com/hetznercloud/cli
hcloud server create \
  --name aiops-recovery \
  --type cpx51 \
  --image ubuntu-22.04 \
  --ssh-key wheeler-main \
  --location nbg1

# === PHASE 3: Restore from Backup ===
# Step 4: Deploy base configuration
git clone https://github.com/wheeler-ai/infrastructure /root/infrastructure
bash /root/infrastructure/bootstrap/bootstrap-server.sh --role aiops

# Step 5: Install Docker, PM2, Tailscale
apt-get update && apt-get install -y docker.io docker-compose-plugin
curl -fsSL https://get.pm2.io/PM2 | bash -s -- --no-daemon
tailscale up --auth-key tskey-recovery

# Step 6: Restore database backups to new COREDB (if COREDB failed)
# NOTE: For AIOPS failure, COREDB is still running, so databases are intact.
# For COREDB failure:
# a) Provision new COREDB
# b) Install PostgreSQL
# c) Download latest backup from offsite:
restic -r s3:https://backups.wheeler.ai/restic restore latest --target /var/lib/postgresql/data

# d) Restore each database:
mc cp s3-backup/backups/databases/frgops-latest.dump /tmp/
pg_restore -U postgres -d frgops --clean /tmp/frgops-latest.dump

# Step 7: Restore PM2 processes (if AIOPS failed)
# PM2 dump should be backed up; restore from backup:
/root/rollback-engine/rollback.sh frgcrm-api production
/root/rollback-engine/rollback.sh litellm production
# ... repeat for all 20 PM2 services

# Step 8: Verify full recovery
bash /root/scripts/smoke-test-all.sh --full
```

### 2.9 Multi-Node Failure

**Symptoms:** Two or more servers simultaneously unreachable. All production services down.

**Impact:** Complete service outage.

**RTO:** < 4 hours (critical services), < 24 hours (full recovery)
**RPO:** < 24 hours

**Recovery Procedure:**

```bash
# === PHASE 1: Declare Major Incident ===
# 1. Post in #alerts-critical: "MAJOR INCIDENT — multi-node failure declared"
# 2. Open PagerDuty incident: page all SRE + CTO
# 3. Begin provisioning recovery nodes on Hetzner

# === PHASE 2: Provision in Priority Order ===
# Priority 1: COREDB (databases must come first)
hcloud server create --name coredb-recovery --type cx32 \
  --image ubuntu-22.04 --ssh-key wheeler-main --location nbg1
echo "COREDB provisioning..." | logger -t dr-recovery

# Priority 2: AIOPS (compute next)  
hcloud server create --name aiops-recovery --type cpx51 \
  --image ubuntu-22.04 --ssh-key wheeler-main --location nbg1

# Priority 3: EDGE (gateway last)
# If Hostinger EDGE is down too:
# Provision Hetzner CX22 as temporary EDGE
hcloud server create --name edge-recovery --type cx22 \
  --image ubuntu-22.04 --ssh-key wheeler-main --location nbg1

# === PHASE 3: Restore COREDB First ===
# Follow Section 2.8 (Full Node Failure) for COREDB
# Critical: get PostgreSQL running and data restored first

# === PHASE 4: Restore AIOPS ===
# Follow Section 2.8 for AIOPS
# PM2 processes can start even if COREDB is still restoring
# Docker containers that need databases will retry

# === PHASE 5: Restore EDGE ===
# EDGE has no persistent state — quickest to restore:
apt-get update && apt-get install -y docker.io docker-compose-plugin
git clone https://github.com/wheeler-ai/infrastructure /root/infrastructure
cd /root/infrastructure/edge
docker compose up -d
tailscale up --auth-key tskey-recovery

# === PHASE 6: Verify Full Recovery ===
# Restoration order: COREDB → AIOPS → EDGE
# Verification order: EDGE (public routes) → AIOPS (API health) → COREDB (DB queries)

bash /root/scripts/smoke-test-all.sh --full
```

---

## 3. Rollback Orchestration

### 3.1 Rollback Engine Overview

The rollback engine at `/root/rollback-engine/` is the primary tool for reverting failed deployments. It supports three service types:

| Script               | Purpose                                  | Service Types     |
|----------------------|------------------------------------------|-------------------|
| `rollback.sh`        | Master orchestrator — coordinates phases | docker, pm2, static, routing |
| `common-rollback.sh` | Shared utilities (backup discovery, integrity, alerts) | All |
| `restore-env.sh`     | Restores .env files                      | All types         |
| `restore-docker.sh`  | Restores Docker containers               | docker            |
| `restore-pm2.sh`     | Restores PM2 processes                   | pm2               |
| `restore-routing.sh` | Restores Traefik + Nginx routing         | routing           |

### 3.2 Rollback Flow

```
rollback.sh <service> <environment>
  │
  ├── Phase 1: Discovery
  │   ├── Find latest backup in /var/backups/deployments/<service>/<env>/
  │   ├── Verify backup integrity (MANIFEST + SHA256SUMS)
  │   └── Detect service type (docker/pm2)
  │
  ├── Phase 2: Execute Rollback
  │   ├── restore-env.sh     — restore .env file from backup
  │   └── restore-docker.sh OR restore-pm2.sh
  │       ├── Stop current container/process
  │       ├── Restore config from backup
  │       ├── Start with restored config
  │       └── Monitor health (up to 120s)
  │
  ├── Phase 3: Verification
  │   ├── Check container health / PM2 status
  │   ├── Check HTTP health endpoint (if configured)
  │   └── Detect restart loops (PM2: 3+ restarts in 30s = loop)
  │
  ├── Phase 4: Preservation
  │   ├── Save failed deployment logs
  │   ├── Save system snapshot
  │   └── Archive to /var/backups/deployments/rollback-preservations/
  │
  └── Phase 5: Notification
      ├── Log event to rollback-history.jsonl
      └── Send alert via webhook/email (success or failure)
```

### 3.3 Manual Rollback Commands

```bash
# Roll back to the latest known-good backup
/root/rollback-engine/rollback.sh frgcrm-api production

# Roll back to a specific version tag
/root/rollback-engine/rollback.sh litellm production --version v2.4.1

# Dry-run mode (show what would happen without making changes)
/root/rollback-engine/rollback.sh prediction-radar-api production --dry-run

# Force mode (skip confirmation prompt)
/root/rollback-engine/rollback.sh traefik production --force

# Roll back routing (Traefik + Nginx) — special case
/root/rollback-engine/rollback.sh routing production
```

### 3.4 Rollback History

```bash
# View rollback history (JSONL format)
cat /var/backups/deployments/rollback-history.jsonl | jq -s '.[] | {service: .service, outcome: .outcome, duration: .duration_seconds, timestamp: .timestamp}' | tail -20

# Count rollbacks in the last 30 days
cat /var/backups/deployments/rollback-history.jsonl | jq -s 'group_by(.service) | .[] | {service: .[0].service, count: length}' | sort -k2 -rn
```

---

## 4. Backup Verification

### 4.1 What Is Backed Up

| Asset                  | Location                         | Verification Method        | Frequency |
|------------------------|----------------------------------|----------------------------|-----------|
| PostgreSQL databases   | COREDB MinIO: backups/databases/ | pg_restore test + row count| Daily     |
| Configuration files    | /var/backups/deployments/        | backup-manifest.sh --verify| On deploy |
| PM2 process list       | ~/.pm2/dump.pm2                 | pm2 resurrect dry-run      | On deploy |
| Docker compose files   | /var/backups/deployments/        | backup-manifest.sh --verify| On deploy |
| .env files             | /var/backups/deployments/        | backup-manifest.sh --verify| On deploy |
| Traefik + Nginx config| /var/backups/deployments/        | traefik validate / nginx -t| On deploy |
| Full system backup     | /root/backups/wheeler-ecosystem/ | Manual inspection          | Weekly    |
| Offsite backup         | Remote S3 (rclone)               | rclone check               | Nightly   |

### 4.2 Backup Verification Commands

```bash
# === Verify Deployment Backup Integrity ===
# Uses the backup-manifest.sh script:
/root/scripts/backup-manifest.sh --backup-dir /var/backups/deployments/frgcrm-api/production/20260524T020000Z --verify

# Expected output:
#   Files listed in manifest:       12
#   Files present on disk:          12
#   Checksums valid:                12
#   Result: ALL VALID

# === Verify PostgreSQL Backup Integrity ===
# Download latest backup, restore to temp, compare row counts:
ssh root@100.64.0.4 "
  LATEST=\$(mc ls coredb-minio/backups/databases/ | sort -r | head -1 | awk '{print \$NF}')
  mc cp coredb-minio/backups/databases/\$LATEST /tmp/
  
  # Spin up temp PostgreSQL
  docker stop pg-verify 2>/dev/null; docker rm pg-verify 2>/dev/null
  docker run -d --name pg-verify -e POSTGRES_PASSWORD=verify -p 15432:5432 postgres:16-alpine
  sleep 10
  
  # Restore backup to temp instance
  docker cp /tmp/\$LATEST pg-verify:/tmp/backup.dump
  docker exec pg-verify pg_restore -U postgres -d postgres --clean /tmp/backup.dump 2>&1 | tail -5
  
  # Verify table structure
  docker exec pg-verify psql -U postgres -t -c \
    \"SELECT schemaname, count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') GROUP BY schemaname;\"
  
  # Clean up
  docker stop pg-verify && docker rm pg-verify
  rm /tmp/\$LATEST
"

# === Verify MinIO Backup Bucket ===
mc ls coredb-minio/backups/ --recursive | head -20
mc du coredb-minio/backups/
# Expected: non-zero total size, recent timestamps

# === Verify Offsite Sync ===
rclone check coredb-minio:backups remote-s3:backups --size-only
# Expected: "0 differences found"
```

### 4.3 Automated Backup Verification (Weekly)

```bash
#!/bin/bash
# /root/scripts/verify-backups.sh — Run weekly via cron (Sunday 04:00 UTC)
# Logs to: /var/log/wheeler/backup-verify-$(date +%Y%m%d).log

set -euo pipefail

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a /var/log/wheeler/backup-verify.log; }
PASS=0
FAIL=0

check() {
  local name="$1"
  shift
  if "$@" 2>/dev/null; then
    log "PASS: $name"
    PASS=$((PASS + 1))
  else
    log "FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

log "=== Weekly Backup Verification ==="

# 1. Check MinIO backups exist and are recent
check "MinIO backup freshness" \
  ssh root@100.64.0.4 "mc ls coredb-minio/backups/databases/ | sort -r | head -3 | grep -q \"$(date +%Y-%m-%d)\""

# 2. Check deployment backup manifests
for backup in /var/backups/deployments/*/production/*/; do
  [ ! -f "$backup/MANIFEST" ] && continue
  check "Manifest: $(basename $(dirname $backup))" \
    /root/scripts/backup-manifest.sh --backup-dir "$backup" --verify
done

# 3. Check offsite sync freshness
check "Offsite backup < 48h" \
  rclone lsl remote-s3:backups/ | sort -r | head -1 | grep -q "$(date +%Y-%m-%d)" 2>/dev/null

log "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
```

---

## 5. Service Restoration Order

### 5.1 Dependency Chain

```
Layer 0 (Infrastructure)
  ├── Docker daemon
  ├── PM2 daemon
  ├── Tailscale
  └── UFW firewall

Layer 1 (Data Layer) — COREDB
  ├── PostgreSQL (port 5432)
  ├── Redis (port 6379)
  ├── MinIO (port 9000)
  └── pgBouncer (port 6432) — starts after PostgreSQL

Layer 2 (Messaging) — AIOPS
  ├── NATS (port 4222)
  └── RabbitMQ (port 5672)

Layer 3 (Core APIs) — AIOPS
  ├── LiteLLM (port 4000) — needs PostgreSQL, Redis
  ├── FRGops API (port 4001) — needs PostgreSQL
  ├── FRGCRM API (PM2) — needs LiteLLM
  └── Prediction Radar API — needs PostgreSQL, Redis

Layer 4 (AI Workers) — AIOPS
  ├── frgcrm-agent-svc — needs LiteLLM, FRGCRM API
  ├── insforge-agent-svc — needs LiteLLM
  ├── surplusai-scraper-agent-svc — needs LiteLLM
  └── voice-agent-svc — needs LiteLLM

Layer 5 (Frontend) — AIOPS / EDGE
  ├── Traefik (port 80/443) — needs backend APIs to be healthy
  ├── Superset — needs PostgreSQL
  └── Grafana — needs Prometheus (which runs independently)

Layer 6 (Monitoring) — AIOPS
  ├── Prometheus
  ├── Loki
  ├── Grafana
  ├── Alertmanager
  └── Uptime Kuma
```

### 5.2 Restoration Command Sequence

```bash
# === LAYER 0: Infrastructure (verify first) ===
systemctl is-active docker        # Must be active
pm2 ping                          # Must return pong
tailscale status                  # All 3 nodes visible

# === LAYER 1: Data Layer (COREDB) ===
ssh root@100.64.0.4 "
  docker start postgres-coredb
  docker start redis-coredb
  docker start minio-coredb
  
  # Wait for PostgreSQL
  for i in \$(seq 1 30); do
    docker exec postgres-coredb pg_isready -U postgres && break
    sleep 2
  done
  
  # Start pgBouncer after PostgreSQL
  docker start pgbouncer-coredb
"

# === LAYER 2: Messaging (AIOPS) ===
ssh root@100.64.0.3 "
  docker start nats rabbitmq
"

# === LAYER 3: Core APIs (AIOPS) ===
ssh root@100.64.0.3 "
  # Start via Docker Compose
  cd /root/infrastructure/aiops
  docker compose up -d litellm prediction-radar-api
  
  # Start via PM2
  pm2 start frgcrm-api --env production
  pm2 start frgcrm-agent-svc --env production
  
  # Verify each
  for svc in litellm frgcrm-api prediction-radar-api; do
    curl -s http://localhost:4000/health | grep -q 'ok' && echo \"\$svc: HEALTHY\" || echo \"\$svc: FAILED\"
  done
"

# === LAYER 4: AI Workers (AIOPS) ===
ssh root@100.64.0.3 "
  pm2 start insforge-agent-svc --env production
  pm2 start surplusai-scraper-agent-svc --env production
  pm2 start voice-agent-svc --env production
  
  pm2 save
"

# === LAYER 5: Frontend (EDGE) ===
ssh root@100.64.0.2 "
  docker start traefik nginx
"

# === LAYER 6: Monitoring (AIOPS) ===
ssh root@100.64.0.3 "
  docker start prometheus grafana loki alertmanager uptime-kuma
"

# === FINAL VERIFICATION ===
bash /root/scripts/smoke-test-all.sh --full
```

---

## 6. Config Restoration

### 6.1 Environment File Restoration

```bash
# Restore a specific service's .env file from its last deployment backup
/root/rollback-engine/restore-env.sh frgcrm-api production /var/backups/deployments/frgcrm-api/production/20260524T020000Z/

# Verify: ensure restored env has all required vars
grep -cE "^[A-Z_]+=" /opt/services/frgcrm-api/.env
# Expected: > 20 lines

# After restore, restart the service:
pm2 restart frgcrm-api
```

### 6.2 Docker Compose Restoration

```bash
# Restore Docker service config from backup
/root/rollback-engine/restore-docker.sh litellm production /var/backups/deployments/litellm/production/20260524T010000Z/

# The script automatically:
# 1. Validates backup integrity (MANIFEST + SHA256SUMS)
# 2. Stops current containers
# 3. Restores docker-compose.yml from backup
# 4. Restores volumes (if backed up)
# 5. Starts containers with restored config
# 6. Monitors health for 120s
# 7. Reports success/failure
```

### 6.3 PM2 Config Restoration

```bash
# Restore PM2 process config from backup
/root/rollback-engine/restore-pm2.sh frgcrm-api production /var/backups/deployments/frgcrm-api/production/20260524T020000Z/

# The script automatically:
# 1. Validates backup integrity
# 2. Stops current PM2 process
# 3. Restores ecosystem.config.js from backup
# 4. Restores PM2 dump (dump.pm2) from backup
# 5. Starts process with restored config
# 6. Monitors for restart loops (3+ restarts in 30s)
# 7. Saves PM2 state
```

### 6.4 Routing Configuration Restoration

```bash
# Restore Traefik + Nginx configs
/root/rollback-engine/restore-routing.sh production /var/backups/deployments/routing/production/20260524T010000Z/

# The script:
# 1. Restores Traefik dynamic config to /etc/traefik/dynamic/
# 2. Restores Nginx config to /etc/nginx/sites-enabled/
# 3. Validates Traefik syntax: traefik validate --configFile=/etc/traefik/traefik.yml
# 4. Validates Nginx syntax: nginx -t
# 5. Sends SIGHUP to reload gracefully
# 6. Verifies routes are serving
```

### 6.5 Full Config Backup Locations

```bash
# All current configuration files live at:
/root/infrastructure/              # Infrastructure as code
  ├── aiops/                       # AIOPS-specific configs
  │   ├── docker-compose.yml       # Master compose file
  │   ├── prometheus.yml
  │   └── traefik.yml
  ├── coredb/                      # COREDB-specific configs
  │   └── docker-compose.yml
  ├── edge/                        # EDGE-specific configs
  │   └── docker-compose.yml
  └── shared/                      # Shared configs
      └── security/
          └── tailscale-acls.json

/opt/wheeler/                      # Service-specific configs
  └── <service-name>/
      ├── .env
      ├── ecosystem.config.js      # PM2 config
      └── docker-compose.yml       # Docker compose

/etc/traefik/                      # Traefik config
  ├── traefik.yml                  # Static config
  └── dynamic/                     # Dynamic config (auto-reloaded)
      ├── routes.yml
      ├── services.yml
      └── middleware.yml

/etc/nginx/                        # Nginx config
  ├── nginx.conf
  └── sites-enabled/
```

---

## 7. Deployment Restoration

### 7.1 Re-deploying from Infrastructure Repo

```bash
# Full service deployment via the deployment engine
/root/deployment-engine/deploy-service.sh frgcrm-api production v2.5.0

# Step-by-step:
# 1. preflight-check.sh — validates env syntax, port availability, disk space
# 2. Pre-deploy backup — saves current config to /var/backups/deployments/
# 3. deploy-pm2-service.sh or deploy-docker-service.sh — deploys the new version
# 4. post-deploy-healthcheck.sh — verifies service is healthy
# 5. verify-deployment.sh — runs service-specific validation
# 6. Auto-rollback if health check fails (deploy exit code 3 or 4)

# Quick health check after deployment:
bash /root/scripts/smoke-test-all.sh --service=frgcrm
```

### 7.2 Restoring from Backup to a New Server

```bash
# Complete server restoration script:
#!/bin/bash
# /root/scripts/full-server-restore.sh
# Usage: full-server-restore.sh <role> <backup-date>
# Example: full-server-restore.sh aiops 20260523

ROLE=$1    # aiops, coredb, or edge
DATE=$2    # YYYYMMDD
BACKUP_PATH="/root/backups/wheeler-ecosystem-${DATE}-205529"

case $ROLE in
  aiops)
    # Restore Docker compose files
    cp -a "${BACKUP_PATH}/docker/"* /root/infrastructure/aiops/
    
    # Restore environment files
    cp -a "${BACKUP_PATH}/env-files/"* /opt/wheeler/
    
    # Restore PM2 apps
    cp "${BACKUP_PATH}/pm2/dump.pm2" ~/.pm2/dump.pm2
    pm2 resurrect
    
    # Restore scripts
    cp -a "${BACKUP_PATH}/scripts/"* /root/scripts/
    
    # Deploy Docker services
    cd /root/infrastructure/aiops && docker compose up -d
    ;;
    
  coredb)
    # Restore PostgreSQL (requires database dump, not in ecosystem backup)
    # Use the pg_dump from MinIO instead
    mc cp coredb-minio/backups/databases/latest.dump /tmp/
    pg_restore -U postgres -d postgres --clean /tmp/latest.dump
    
    # Restore Docker compose
    cp -a "${BACKUP_PATH}/docker/"* /root/infrastructure/coredb/
    cd /root/infrastructure/coredb && docker compose up -d
    ;;
    
  edge)
    # Edge has no state — just deploy the compose files
    cp -a "${BACKUP_PATH}/docker/"* /root/infrastructure/edge/
    cd /root/infrastructure/edge && docker compose up -d
    ;;
esac
```

---

## 8. Multi-Node Recovery Strategy

### 8.1 Full Outage Declaration

When two or more servers are down simultaneously:

```bash
# Step 1: Declare major incident (P1)
# Channel: #alerts-critical
# Message: "P1 DECLARED: Multi-node failure. All hands on deck."

# Step 2: Determine surviving nodes
for ip in 2 3 4; do
  ping -c 2 -W 3 "100.64.0.$ip" >/dev/null 2>&1 \
    && echo "100.64.0.$ip: ALIVE" \
    || echo "100.64.0.$ip: DOWN"
done

# Step 3: If COREDB survives, protect it — stop all non-DB activity
# If COREDB is down, restoring it is priority #1

# Step 4: Determine recovery strategy based on which nodes are down:
# COREDB down + AIOPS alive = stop all apps, restore COREDB first
# COREDB alive + AIOPS down = spin up new AIOPS, connect to existing COREDB
# EDGE down + others alive = spin up new EDGE, Traefik routes to existing AIOPS
```

### 8.2 Recovery Node Provisioning

```bash
# Hetzner API recovery node provisioning
# Requires hcloud CLI and API token

# Provision recovery AIOPS if main is down:
hcloud server create \
  --name aiops-dr-$(date +%Y%m%d) \
  --type cpx51 \
  --image ubuntu-22.04 \
  --ssh-key wheeler-main \
  --location nbg1 \
  --user-data-from-file /root/infrastructure/bootstrap/cloud-init-aiops.yaml

# Get the new server IP:
NEW_IP=$(hcloud server ip aiops-dr-$(date +%Y%m%d))
echo "Recovery AIOPS provisioned at: $NEW_IP"

# Bootstrap:
ssh -o StrictHostKeyChecking=no root@$NEW_IP "
  # Install core dependencies
  apt-get update && apt-get install -y docker.io docker-compose-plugin
  
  # Install PM2
  npm install -g pm2
  
  # Join Tailscale
  tailscale up --auth-key tskey-xxxx
  
  # Clone infrastructure
  git clone https://github.com/wheeler-ai/infrastructure /root/infrastructure
  
  # Restore deployment backups
  rsync -avz root@recovery-source:/var/backups/deployments/ /var/backups/deployments/
  
  # Start core services
  cd /root/infrastructure/aiops && docker compose up -d
  
  # Restore PM2 state
  cd /root/infrastructure/aiops/pm2 && pm2 start ecosystem.config.js --env production
  pm2 save
  
  # Verify
  curl -s http://localhost:4000/health
"
```

### 8.3 Traffic Cutover

```bash
# Once recovery nodes are healthy:
# 1. Update DNS records (short TTL = 60s)
# 2. Update Traefik config on EDGE to point to new AIOPS IP
# 3. Verify traffic flows correctly
# 4. Monitor for 1 hour before declaring recovery complete
```

---

## 9. Disaster Recovery Testing Schedule

### 9.1 Testing Cadence

| Test                               | Frequency | Type            | Duration | Owner        |
|------------------------------------|-----------|-----------------|----------|--------------|
| Backup integrity verification      | Weekly    | Automated       | 15 min   | On-call SRE  |
| Single container restart           | Weekly    | Automated       | 5 min    | On-call SRE  |
| Single PM2 process restart         | Weekly    | Automated       | 5 min    | On-call SRE  |
| Database restore to temp instance  | Monthly   | Semi-automated  | 30 min   | SRE Team     |
| Full backup recovery (tabletop)    | Monthly   | Manual          | 1 hour   | SRE Lead     |
| Tailscale failure simulation       | Quarterly | Manual          | 30 min   | SRE Team     |
| AIOPS complete loss (tabletop)     | Quarterly | Manual          | 1 hour   | SRE Lead     |
| COREDB complete loss (tabletop)    | Quarterly | Manual          | 1 hour   | SRE Lead     |
| Multi-node failure (tabletop)      | Annually  | Manual          | 2 hours  | SRE Team+CTO |
| Full production DR exercise        | Annually  | Manual          | 4 hours  | All          |

### 9.2 DR Test Script — Single Container Recovery

```bash
#!/bin/bash
# /root/scripts/dr-test-container.sh
# Tests: Can we recover from a single container failure?
# WARNING: This actually restarts a container. Run during maintenance window.

set -euo pipefail

CONTAINER=${1:-langflow}  # Default: langflow (non-critical, easy to verify)
echo "=== DR Test: Single Container Recovery ==="
echo "Container: $CONTAINER"
echo "Time: $(date -u)"
echo ""

# Record pre-test state
PRE_HEALTH=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "N/A")
echo "Pre-test health: $PRE_HEALTH"

# Simulate failure
echo ""
echo "Step 1: Stopping $CONTAINER..."
docker stop "$CONTAINER"
sleep 2

# Verify stopped
docker ps --filter "name=$CONTAINER" --format "{{.Status}}" | grep -q "Exited" && echo "  CONFIRMED: Container stopped"

echo ""
echo "Step 2: Restarting $CONTAINER..."
docker start "$CONTAINER"

# Monitor recovery
for i in $(seq 1 30); do
  STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "starting")
  if [ "$STATUS" = "healthy" ]; then
    echo "  RECOVERED: Container healthy after ${i}s"
    break
  fi
  sleep 2
done

POST_HEALTH=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "N/A")
echo ""
echo "Post-test health: $POST_HEALTH"

if [ "$POST_HEALTH" = "healthy" ]; then
  echo "RESULT: PASS (RTO: < 60s)"
else
  echo "RESULT: FAIL — container did not recover to healthy state"
  echo "Check: docker logs $CONTAINER --tail 20"
  exit 1
fi
```

### 9.3 DR Test Script — Database Restore

```bash
#!/bin/bash
# /root/scripts/dr-test-db-restore.sh
# Tests: Can we restore a database from the latest backup?
# Creates a temp PostgreSQL, restores backup, compares row counts.

set -euo pipefail

DB_NAME=${1:-frgops}
BACKUP_HOST=${2:-100.64.0.4}  # COREDB

echo "=== DR Test: Database Restore ==="
echo "Database: $DB_NAME"
echo "Time: $(date -u)"
echo ""

# Step 1: Get latest backup
echo "Step 1: Finding latest backup..."
LATEST=$(ssh root@$BACKUP_HOST "mc ls coredb-minio/backups/databases/" 2>/dev/null | sort -r | head -1 | awk '{print $NF}')
if [ -z "$LATEST" ]; then
  echo "  FAIL: No backup found"
  exit 1
fi
echo "  Latest backup: $LATEST"

# Step 2: Download backup
echo ""
echo "Step 2: Downloading backup..."
ssh root@$BACKUP_HOST "mc cp coredb-minio/backups/databases/$LATEST /tmp/$LATEST" 2>/dev/null

# Step 3: Get reference row counts from production
echo ""
echo "Step 3: Capturing production row counts..."
ssh root@$BACKUP_HOST "docker exec postgres-coredb psql -U postgres -d $DB_NAME -t -c \"SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;\"" > /tmp/prod-row-counts.txt 2>/dev/null || {
  echo "  WARN: Could not get live row counts (tables may not be analyzed)"
  echo "  Will verify table count instead"
  ssh root@$BACKUP_HOST "docker exec postgres-coredb psql -U postgres -d $DB_NAME -t -c \"SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema');\"" > /tmp/prod-table-count.txt
}

# Step 4: Spin up temp PostgreSQL
echo ""
echo "Step 4: Starting temp PostgreSQL..."
docker stop pg-dr-test 2>/dev/null; docker rm pg-dr-test 2>/dev/null
START_TIME=$(date +%s)
docker run -d --name pg-dr-test \
  -e POSTGRES_PASSWORD=dr_test \
  -p 15432:5432 \
  postgres:16-alpine 2>&1 | tail -1

# Wait for it to be ready
for i in $(seq 1 20); do
  docker exec pg-dr-test pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 2
done

# Step 5: Copy and restore backup
echo ""
echo "Step 5: Restoring backup to temp instance..."
scp root@$BACKUP_HOST:/tmp/$LATEST /tmp/$LATEST 2>/dev/null
docker cp /tmp/$LATEST pg-dr-test:/tmp/backup.dump
docker exec pg-dr-test pg_restore -U postgres -d postgres --clean --if-exists /tmp/backup.dump 2>&1 | tail -5

# Step 6: Verify restoration
echo ""
echo "Step 6: Verifying restoration..."
docker exec pg-dr-test psql -U postgres -d postgres -t -c \
  "SELECT tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;" > /tmp/restore-row-counts.txt 2>/dev/null

# Compare row counts
echo "  Comparing row counts..."
diff /tmp/prod-row-counts.txt /tmp/restore-row-counts.txt 2>/dev/null && \
  echo "  Row counts MATCH" || \
  echo "  WARN: Row counts differ (may be ANALYZE timing)"

# Table count comparison
RESTORE_TABLES=$(docker exec pg-dr-test psql -U postgres -d postgres -t -c \
  "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema');" 2>/dev/null | tr -d ' ')
echo "  Tables restored: $RESTORE_TABLES"

# Step 7: Measure RTO
END_TIME=$(date +%s)
RTO=$((END_TIME - START_TIME))
echo ""
echo "RTO: ${RTO}s"

# Step 8: Cleanup
echo ""
echo "Step 8: Cleaning up..."
docker stop pg-dr-test && docker rm pg-dr-test
rm -f /tmp/$LATEST /tmp/prod-row-counts.txt /tmp/restore-row-counts.txt /tmp/prod-table-count.txt
ssh root@$BACKUP_HOST "rm /tmp/$LATEST" 2>/dev/null

echo ""
echo "RESULT: Database restore completed in ${RTO}s"
echo "Tables restored: $RESTORE_TABLES"
echo "Recommendation: Update RPO/RTO tracking if this deviates from targets"
```

---

## 10. Emergency Contacts & Escalation

### 10.1 On-Call Rotation

| Role          | Name          | Phone             | Email                   | Backup         |
|---------------|---------------|-------------------|-------------------------|----------------|
| SRE Lead      | [TBD]         | [TBD]             | sre-lead@wheeler.ai     | SRE Team       |
| Primary SRE   | [TBD]         | [TBD]             | sre@wheeler.ai          | SRE Lead       |
| DBA           | [TBD]         | [TBD]             | dba@wheeler.ai          | SRE Lead       |
| Security Lead | [TBD]         | [TBD]             | security@wheeler.ai     | CTO            |
| CTO           | [TBD]         | [TBD]             | cto@wheeler.ai          | CEO            |

### 10.2 Escalation Path

```
Priority 1 (Single Service Down):
  1. Primary SRE (immediate response)
  2. SRE Lead (if unresolved after 15 min)

Priority 2 (Server Down):
  1. Primary SRE + SRE Lead (immediate)
  2. CTO (if unresolved after 30 min)

Priority 3 (Multi-Node Failure):
  1. All SRE + CTO (immediate)
  2. CEO (if ETA to recovery > 2 hours)
  3. External incident response if data breach suspected
```

### 10.3 Communication Channels

| Channel               | Purpose                        | Platform  |
|-----------------------|--------------------------------|-----------|
| #alerts-critical      | P1 incidents, pages            | Slack     |
| #engineering          | General operations             | Slack     |
| #alerts               | Warning-level alerts           | Slack     |
| PagerDuty             | Automated paging for P1 alerts | PagerDuty |
| Email (ops list)      | Scheduled reports              | Email     |

### 10.4 External Providers

| Provider  | Service          | Support Contact    | Account ID    |
|-----------|------------------|--------------------|---------------|
| Hetzner   | AIOPS + COREDB   | https://console.hetzner.cloud/support | [TBD]  |
| Hostinger | EDGE             | https://support.hostinger.com         | [TBD]  |
| Tailscale | Mesh VPN         | https://tailscale.com/support         | [TBD]  |
| Cloudflare| DNS + CDN        | https://dash.cloudflare.com/support   | [TBD]  |
| GitHub    | Infrastructure repo | https://github.com/support         | [TBD]  |

### 10.5 Post-Incident Requirements

After every DR event or test, complete the following within 5 business days:

1. **Incident Report** in /root/docs/incidents/YYYYMMDD-description.md
   - Timeline of events
   - Root cause analysis
   - What went well / what went wrong
   - Action items with owners and deadlines

2. **RPO/RTO Review** — update this document if targets were missed

3. **Runbook Updates** — fix any incorrect commands or IPs discovered during recovery

4. **DR Test Results** — update DR testing schedule with actual metrics

---

**End of Disaster Recovery Plan**
**Next scheduled review:** 2026-06-24
