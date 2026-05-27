# Wheeler Ecosystem Backup & Restore Runbook

**Audit Date:** 2026-05-27
**Auditor:** Wheeler DB Agent
**3-Server Footprint:** COREDB (100.118.166.117) | AIOPS/Hetzner (local) | Hostinger (100.98.163.17)

---

## 1. BACKUP INVENTORY

### 1.1 COREDB (100.118.166.117)

| Asset | Method | Schedule | Location | Retention | Last Success |
|-------|--------|----------|----------|-----------|-------------|
| 16 PostgreSQL databases | `pg_dump -Fc` via Docker exec | Daily 03:00 | `/opt/backups/databases/<db>/` | 7 days | 2026-05-27 03:00 |
| MinIO data | NONE (MinIO running but no backup integration) | N/A | `/var/lib/docker/volumes/wheeler-core_minio_data/` | N/A | N/A |
| Redis data | NONE | N/A | `/var/lib/docker/volumes/wheeler-core_redis_data/` | N/A | N/A |
| Docker volumes | NONE | N/A | Local Docker volume store | N/A | N/A |
| Config files | NONE | N/A | N/A | N/A | N/A |

**Databases backed up (16):** chatwoot_production, frgcrm, frgops_staging, healthchecks, infisical, langfuse, plausible, postgres, prediction_radar, ravynai, shared, temporal, temporal_db, temporal_visibility, usesend, wheeler_core

**Total backup size:** ~45 MB
**Available disk:** 306 GB (6% used) on `/dev/sda1`

### 1.2 AIOPS / Hetzner (local)

| Asset | Method | Schedule | Location | Retention | Last Success |
|-------|--------|----------|----------|-----------|-------------|
| 3 PostgreSQL databases | `pg_dump` pipeline via backup-all.sh | Manual/on-demand | `/root/backups/postgres/` | 7 daily + 4 weekly | 2026-05-26 20:19 |
| 3 Redis instances | BGSAVE + RDB copy via backup-all.sh | Manual/on-demand | `/root/backups/redis/` | 7 copies | 2026-05-26 20:19 |
| Configs (deployment-engine, command-center, scripts, infrastructure) | tar.gz archive via backup-all.sh | Manual/on-demand | `/root/backups/configs/` | 14 days | 2026-05-26 20:20 |
| Neo4j graph DB | `neo4j-admin dump` (stop/backup/start) | Daily 03:17 (cron) | `/root/backups/neo4j/` | 7 daily | 2026-05-27 03:17 |
| prediction-radar PostgreSQL | Docker backup container (`prodrigestivill/postgres-backup-local:16`) | @daily (midnight) | Docker volume (container internal) | 7 days / 4 weeks / 6 months | 2026-05-27 00:00 |
| uptime-kuma data | Docker backup container (duplicate instance) | Unknown | N/A | N/A | Unknown |
| netdata config | Docker backup container (duplicate instance) | Unknown | N/A | N/A | Unknown |

**Databases backed up (3):** frgcrm, prediction_radar, ravynai
**Total backup size:** ~13 MB (postgres 7.5M, redis 48K, configs 5.5M) + neo4j 148K

### 1.3 Hostinger (100.98.163.17)

| Asset | Method | Schedule | Location | Retention | Last Success |
|-------|--------|----------|----------|-----------|-------------|
| 6 shared databases | `pg_dump` via Docker exec (backup-all-dbs.sh) | Daily 03:00 | `/root/backups/auto/<ts>/` | Ongoing (no cleanup) | 2026-05-27 03:00 |
| FRGCRM production DB | pg_dump via backup-all-dbs.sh | Daily 03:00 | `/root/backups/auto/<ts>/` | Ongoing | 2026-05-27 03:00 |
| FRGCRM RDS database | pg_dump via Docker 18 image (pg_dump_backup.sh) | Daily 03:00 | `/backups-enc/` | Unknown | Unknown |
| FRGCRM DB (encrypted, GPG) | pg_dump + GPG encrypt (frg-db-backup-now.sh) | Unknown (last May 11) | `/root/frg-db-backups/` | 30 backups max | 2026-05-11 21:01 |
| SQLite Brain DB | sqlite3 backup (backup-brain-db.sh) | Daily 01:00 | `/root/backups/brain-daily/` | 30 days | 2026-05-13 |
| R2 offsite (FRGCRM dump + configs) | rclone to Cloudflare R2 S3 (r2-backup.sh) | Daily 05:00 | R2 bucket `frg-r2:databases/` + `frg-r2:configs/` | 30 days | BROKEN (no upload confirmed) |
| Docker volumes | Volume tar backup script | Unknown | `/root/backups/docker-volumes/` | Unknown | Unknown |

**Hostinger containers running (key ones):** shared-postgres, frgops-postgres (not running as named), cadvisor, temporal, promtail, pushgateway

---

## 2. BACKUP STATUS SUMMARY

### 2.1 Working (green)

- COREDB PostgreSQL daily backup -- runs daily at 03:00, 16/16 databases successful, verified by log
- Hetzner PostgreSQL + Redis + Configs + Neo4j -- all 4 phases pass via backup-all.sh on demand
- prediction-radar DB backup container -- daily at midnight, retention working correctly (daily/weekly/monthly dirs)
- Hostinger backup-all-dbs.sh -- runs daily at 03:00, dumping all shared + production databases

### 2.2 Partially Working (yellow)

- Hostinger R2 offsite backup -- script runs (log created at 05:00) but rclone appears to not actually upload (empty bucket listing, 43-byte log files indicate script fails early)
- Hostinger encrypted FRGCRM backup -- last was May 11; not running on schedule
- Sovereign restore tests -- some databases pass (prediction_radar: PASSED 6/6 checks), others may fail on SQL dump compatibility

### 2.3 Missing / Broken (red)

- **No backup for COREDB Docker volumes** (minio_data, redis_data, grafana_data, loki_data, prometheus_data, uptime_kuma_data)
- **No COREDB offsite backup** -- backups sit on local disk only, no replication to Hetzner or R2
- **No COREDB MinIO backup integration** -- MinIO running healthy but stores nothing backup-related
- **No backup-all.sh cron** on Hetzner -- only Neo4j backup is cronned, the other 3 phases must be run manually
- **No unified backup monitoring** -- no Prometheus alerts for backup freshness, no centralized dashboard
- **No verified restore test pass for all databases** -- sovereign-backup-test.sh exists but needs to cover all databases
- **Hostinger R2 offsite backup is not functioning** -- rclone config exists but uploads are not completing
- **COREDB backup storage at single point of failure** -- if `/dev/sda1` fails, all backups are lost
- **No backup for temporal.io workflow state** beyond PostgreSQL dumps (Temporal has internal state that may not fully capture in PG dump)

---

## 3. RESTORE PROCEDURES

### 3.1 Restore PostgreSQL Database (COREDB -- custom format dump)

```bash
# Find the backup you want
ls -lt /opt/backups/databases/<dbname>/

# Restore to a new database (rename if original still exists)
gunzip -c /opt/backups/databases/<dbname>/<dbname>_20260527_030001.dump.gz | \
  docker exec -i wheeler-postgres pg_restore -U wheeler -d <dbname> --clean --if-exists

# Or restore to a DIFFERENT database name:
docker exec -i wheeler-postgres createdb -U wheeler <dbname>_restore
gunzip -c /opt/backups/databases/<dbname>/<dbname>_YYYYMMDD_HHMMSS.dump.gz | \
  docker exec -i wheeler-postgres pg_restore -U wheeler -d <dbname>_restore

# Verify row count
docker exec wheeler-postgres psql -U wheeler -d <dbname>_restore -c \
  "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 10;"
```

### 3.2 Restore PostgreSQL Database (Hetzner -- SQL format dump)

```bash
# These are .sql.gz files, restore via psql
gunzip -c /root/backups/postgres/<dbname>-<timestamp>.sql.gz | \
  docker exec -i <container-name> psql -U <username> -d <dbname>

# Example for frgcrm on frgops-standby:
gunzip -c /root/backups/postgres/frgcrm-20260526-200549.sql.gz | \
  docker exec -i frgops-standby psql -U frgops -d frgcrm

# Example for prediction_radar:
gunzip -c /root/backups/postgres/prediction_radar-20260526-200549.sql.gz | \
  docker exec -i prediction-radar-app-db psql -U prediction_radar -d prediction_radar
```

### 3.3 Restore PostgreSQL Database (prediction-radar backup container)

```bash
# Backups are SQL format in the backup container
# Copy from container and restore
docker cp prediction-radar-app-db-backup-1:/backups/daily/prediction_radar-20260527.sql.gz /tmp/
gunzip -c /tmp/prediction_radar-20260527.sql.gz | \
  docker exec -i prediction-radar-app-db psql -U prediction_radar -d prediction_radar
```

### 3.4 Restore Redis Data

```bash
# Find the RDB backup
ls -lt /root/backups/redis/

# Stop the redis container
docker stop <redis-container>

# Copy the RDB into the container's data directory
# Find the actual volume mount first:
docker inspect <redis-container> --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' | grep /data

# Example: replace dump.rdb
docker run --rm -v <redis-volume>:/data -v /root/backups/redis:/backup alpine:latest \
  cp /backup/<container>-<timestamp>.rdb /data/dump.rdb

# Restart the container
docker start <redis-container>

# Verify
docker exec <redis-container> redis-cli PING
docker exec <redis-container> redis-cli DBSIZE
```

### 3.5 Restore Neo4j Graph Database

```bash
# Find latest backup
ls -lt /root/backups/neo4j/neo4j-*.dump

# WARNING: Neo4j Community Edition does NOT support online restore.
# The container MUST be stopped for neo4j-admin load.

# Stop the running container
docker stop ecosystem-graph

# Run a temporary container to restore
docker run --rm \
  -v wheeler-neo4j-data:/data \
  -v /root/backups/neo4j:/backups \
  neo4j:5.26-community \
  neo4j-admin load --from=/backups/neo4j-<timestamp>.dump --database=neo4j --force

# Restart the container
docker start ecosystem-graph

# Wait for health and verify
sleep 15
docker exec ecosystem-graph cypher-shell -u neo4j -p <password> "MATCH (n) RETURN count(n) AS node_count;"
```

### 3.6 Restore Docker Volumes

```bash
# For volumes backed up as tar.gz archives:
# List available volume backups
ls -lt /root/backups/docker-volumes/

# Restore volume data:
# 1. Stop the container using the volume
docker stop <container-name>

# 2. Restore from archive into the correct volume mount point
# Find the mount path:
docker volume inspect <volume-name> --format '{{.Mountpoint}}'

# 3. Restore using a temporary container
docker run --rm \
  -v <volume-name>:/target \
  -v /root/backups/docker-volumes:/backup \
  alpine:latest \
  tar xzf "/backup/<volume-archive>.tar.gz" -C /target

# 4. Restart the container
docker start <container-name>
```

### 3.7 Restore MinIO Data (COREDB)

```bash
# MinIO stores data on the wheeler-core_minio_data volume
docker run --rm \
  -v wheeler-core_minio_data:/data \
  -v /opt/backups:/backup \
  alpine:latest \
  ls -la /data/

# MinIO stores in bucket directories under /data/
# To restore from a file-level backup:
docker run --rm \
  -v wheeler-core_minio_data:/data \
  -v /path/to/backup:/backup \
  alpine:latest \
  tar xzf /backup/minio-data-<timestamp>.tar.gz -C /data/
```

### 3.8 Full Server Disaster Recovery (Hetzner/AIOPS)

The infrastructure includes a disaster recovery playbook script:

```bash
# Interactive guided recovery
bash /root/infrastructure/shared/backup-rotation/disaster-recovery-playbook.sh

# Manual procedure:
# 1. Provision a new server (CPX51 or equivalent)
# 2. Install Docker + dependencies
# 3. Restore configs:
tar xzf /root/backups/configs/configs-<timestamp>.tar.gz -C /

# 4. Restore PostgreSQL databases (see 3.2)
# 5. Restore Redis (see 3.4)
# 6. Restore Neo4j (see 3.5)
# 7. Restore Docker volumes (see 3.6)
# 8. Restore PM2 state:
pm2 resurrect /root/backups/configs/pm2-<timestamp>/dump.pm2

# 9. Start all containers per docker-compose files
```

---

## 4. CRITICAL GAPS AND REMEDIATION

### 4.1 RPO/RTO Assessment

| Component | Current RPO (data loss window) | Current RTO (recovery time) | Target | Status |
|-----------|-------------------------------|---------------------------|--------|--------|
| COREDB PostgreSQL | 24h (daily backup) | 15 min (local restore) | 4h/1h | ACCEPTABLE |
| COREDB Docker Volumes | **INFINITE** (no backups) | **INFINITE** (no restore) | 24h/2h | **CRITICAL** |
| Hetzner PostgreSQL | Variable (no cron) | 15 min | 24h/1h | NEEDS SCHEDULE |
| Hetzner Redis | Variable (no cron) | 15 min | 24h/30min | NEEDS SCHEDULE |
| Hostinger FRGCRM | 24h (daily) | 30 min (local) | 4h/1h | ACCEPTABLE |
| Hostinger R2 Offsite | **BROKEN** | N/A | 24h/2h | **CRITICAL** |
| Neo4j Graph DB | 24h (daily) | 30 min (stop/restore/start) | 24h/1h | ACCEPTABLE |

### 4.2 Gap 1: COREDB Docker Volumes Are Not Backed Up

**Impact:** If the COREDB Docker volume store is corrupted, ALL non-PostgreSQL state is permanently lost: MinIO S3 objects, Redis cache/sessions/rate-limit counters, Grafana dashboards, Prometheus metrics history, Loki log archives, Uptime Kuma monitor data.

**Fix:** Deploy a volume backup script on COREDB:

```bash
# Add to COREDB crontab:
# 0 4 * * * /opt/backups/backup-volumes.sh >> /var/log/volume-backup.log 2>&1
```

Create `/opt/backups/backup-volumes.sh` with:
```bash
#!/bin/bash
BACKUP_BASE="/opt/backups/volumes"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION=7

VOLUMES="wheeler-core_minio_data wheeler-core_redis_data wheeler-core_postgres_data wheeler-monitoring_grafana_data wheeler-monitoring_loki_data wheeler-monitoring_prometheus_data wheeler-monitoring_uptime_kuma_data"

mkdir -p "$BACKUP_BASE"
for vol in $VOLUMES; do
  docker run --rm -v ${vol}:/source -v ${BACKUP_BASE}:/backup alpine:latest \
    tar czf "/backup/${vol}_${TIMESTAMP}.tar.gz" -C /source .
done
find "$BACKUP_BASE" -name '*.tar.gz' -mtime +$RETENTION -delete
```

### 4.3 Gap 2: No Offsite Backup for COREDB

**Impact:** A physical server failure of COREDB destroys all backups (they live on the same disk).

**Fix:** Add offsite sync to the backup script or as a cron step:

```bash
# rsync to Hetzner (post-restore-connection)
# or scp
# 30 3 * * * rsync -avz /opt/backups/ root@<hetzner-ip>:/root/backups/coredb/ >> /var/log/coredb-rsync.log 2>&1
```

### 4.4 Gap 3: No backup-all.sh Cron on Hetzner

**Impact:** PostgreSQL, Redis, and Config backups are only created when manually triggered.

**Fix:**
```bash
# Add to Hetzner crontab:
# 0 4 * * * bash /root/deployment-engine/scripts/backup-all.sh >> /root/backups/backup-summary.log 2>&1
```

### 4.5 Gap 4: R2 Offsite Backup Is Broken

**Evidence:** `rclone lsd frg-r2:` returns nothing. The `r2-backup.sh` log consistently shows only "Starting backup to R2..." with no upload confirmation. File sizes are 43 bytes (just the log header).

**Triage:**
```bash
# On Hostinger (100.98.163.17):
rclone config show         # Verify credentials exist
rclone lsd frg-r2:         # Test connectivity
rclone copy /tmp/test.txt frg-r2:test/  # Test upload
cat /root/scripts/r2-backup.sh  # Review the script

# Most likely issues:
# 1. R2 credentials rotated but rclone config not updated
# 2. R2 bucket deleted or renamed
# 3. rclone binary missing or broken
# 4. Network connectivity issue to Cloudflare R2
```

### 4.6 Gap 5: No Prometheus Backup Freshness Alerts

**Impact:** No automated alerting when backups fail. Relies on manual log inspection.

**Fix:** Add backup metrics and alerts:
```bash
# Option A: Export a Prometheus textfile from the backup script
# Add to backup-postgres.sh:
echo "wheeler_backup_freshness_hours{type=\"postgres\",server=\"coredb\"} $(( ($(date +%s) - $(stat -c %Y /opt/backups/databases/wheeler_core/wheeler_core_$(date +%Y%m%d)*.dump.gz 2>/dev/null || echo 0)) / 3600 ))" > /var/lib/node_exporter/textfile_collector/backup_freshness.prom

# Option B: Use PM2 backup-verification process (already exists but tracks only some backups)
pm2 show backup-verification
```

### 4.7 Gap 6: No Unified Restore Test Pass for All Databases

**Impact:** The sovereign-backup-test.sh exists but has only tested prediction_radar successfully. No automated periodic verification that backups are restorable.

**Fix:**
```bash
# Run a full restore test sweep (non-destructive, uses temp containers):
bash /root/scripts/sovereign-backup-test.sh --all

# Schedule weekly:
# 0 5 * * 0 bash /root/scripts/sovereign-backup-test.sh --all >> /var/log/wheeler/backup-tests/weekly-$(date +\%Y\%m\%d).log 2>&1
```

---

## 5. SCHEDULE CONSOLIDATION (RECOMMENDED)

| Time | Server | Job | Description |
|------|--------|-----|-------------|
| 00:00 | Hetzner | prediction-radar DB backup container | Docker postgres-backup-local |
| 01:00 | Hostinger | brain.db backup | SQLite backup, 30-day retention |
| 03:00 | COREDB | PostgreSQL backup | 16 databases, 7-day retention |
| 03:00 | Hostinger | backup-all-dbs.sh | Shared + production database dumps |
| 03:17 | Hetzner | Neo4j backup | 14s downtime, 7-day retention |
| 04:00 | COREDB | **MISSING**: Docker volume backup | Should back up 7 volumes |
| 04:00 | Hetzner | **MISSING**: backup-all.sh (PG+Redis+Configs) | Should auto-run all 4 phases |
| 05:00 | Hostinger | R2 offsite backup | **BROKEN** -- needs repair |
| 05:00 | Hetzner | **MISSING**: Restore test sweep | Weekly on Sunday |

---

## 6. QUICK COMMAND REFERENCE

### Backup Commands

```bash
# COREDB: Run PostgreSQL backup now
ssh root@100.118.166.117 "bash /opt/backups/backup-postgres.sh"

# COREDB: List latest backup files
ssh root@100.118.166.117 "for d in /opt/backups/databases/*/; do echo \"\$(ls -t \"\$d\" | head -1)\"; done"

# COREDB: View backup log
ssh root@100.118.166.117 "tail -50 /var/log/postgres-backup.log"

# Hetzner: Run full backup
bash /root/deployment-engine/scripts/backup-all.sh

# Hetzner: Run Neo4j backup
bash /root/scripts/neo4j-backup.sh

# Hetzner: Run restore test
bash /root/scripts/sovereign-backup-test.sh --all

# Hostinger: Run database backup
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17 "bash /root/scripts/backup-all-dbs.sh"

# Hostinger: Run R2 offsite (after fixing)
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17 "bash /root/scripts/r2-backup.sh"

# Hostinger: Run encrypted backup
ssh -i /root/.ssh/wheeler-mesh-key root@100.98.163.17 "bash /root/frg-db-backup-now.sh"
```

### Health Check Commands

```bash
# Check backup freshness on COREDB
ssh root@100.118.166.117 "echo 'Last backup:'; ls -lt /opt/backups/databases/wheeler_core/*.dump.gz 2>/dev/null | head -1 | awk '{print \$6,\$7,\$8}'; echo 'Total size:'; du -sh /opt/backups/"

# Check backup freshness on Hetzner
echo "Postgres:"; ls -lt /root/backups/postgres/*.sql.gz 2>/dev/null | head -1 | awk '{print $6,$7,$8}'
echo "Redis:"; ls -lt /root/backups/redis/*.rdb 2>/dev/null | head -1 | awk '{print $6,$7,$8}'
echo "Neo4j:"; ls -lt /root/backups/neo4j/neo4j-*.dump 2>/dev/null | head -1 | awk '{print $6,$7,$8}'
echo "Configs:"; ls -lt /root/backups/configs/configs-*.tar.gz 2>/dev/null | head -1 | awk '{print $6,$7,$8}'

# Check all backup sizes
du -sh /root/backups/*/

# Check backup summary
tail -30 /root/backups/backup-summary.log
```

### Restore Commands (quick reference)

```bash
# RESTORE PostgreSQL (COREDB custom format)
# Latest file:
gunzip -c /opt/backups/databases/<db>/$(ls -t /opt/backups/databases/<db>/*.dump.gz | head -1) | docker exec -i wheeler-postgres pg_restore -U wheeler -d <db> --clean --if-exists

# RESTORE PostgreSQL (Hetzner SQL format)
gunzip -c /root/backups/postgres/$(ls -t /root/backups/postgres/*.sql.gz | head -1) | docker exec -i <container> psql -U <user> -d <db>

# RESTORE Neo4j
docker stop ecosystem-graph && docker run --rm -v wheeler-neo4j-data:/data -v /root/backups/neo4j:/backups neo4j:5.26-community neo4j-admin load --from=/backups/$(ls -t /root/backups/neo4j/neo4j-*.dump | head -1) --database=neo4j --force && docker start ecosystem-graph

# RESTORE Redis
docker stop <container> && docker run --rm -v <volume>:/data -v /root/backups/redis:/backup alpine:latest cp /backup/$(ls -t /root/backups/redis/*.rdb | head -1) /data/dump.rdb && docker start <container>
```

---

## 7. KEY FILES REFERENCED

| File | Server | Purpose |
|------|--------|---------|
| `/opt/backups/backup-postgres.sh` | COREDB | PostgreSQL backup script (16 databases) |
| `/var/log/postgres-backup.log` | COREDB | Backup execution log |
| `/root/deployment-engine/scripts/backup-all.sh` | Hetzner | Master backup orchestrator (4 phases) |
| `/root/deployment-engine/scripts/backup-postgres.sh` | Hetzner | Local PostgreSQL backup (3 databases) |
| `/root/deployment-engine/scripts/backup-redis.sh` | Hetzner | Redis RDB backup (3 instances) |
| `/root/deployment-engine/scripts/backup-configs.sh` | Hetzner | Config archive + PM2 snapshot |
| `/root/deployment-engine/scripts/backup-neo4j.sh` | Hetzner | Neo4j dump (stop/backup/start) |
| `/root/scripts/neo4j-backup.sh` | Hetzner | Neo4j backup cron wrapper |
| `/root/scripts/sovereign-backup-test.sh` | Hetzner | Restore verification test |
| `/var/log/wheeler/backup-tests/` | Hetzner | Restore test logs |
| `/root/backups/backup-summary.log` | Hetzner | backup-all.sh summary |
| `/root/scripts/backup-all-dbs.sh` | Hostinger | Docker database backup (shared + production) |
| `/root/scripts/r2-backup.sh` | Hostinger | R2 offsite backup script (BROKEN) |
| `/root/scripts/backup-brain-db.sh` | Hostinger | SQLite brain.db backup |
| `/root/frg-db-backup-now.sh` | Hostinger | Encrypted FRGCRM backup |
| `/opt/apps/frgcrm/scripts/pg_dump_backup.sh` | Hostinger | FRGCRM RDS pg_dump via Docker 18 |
| `/root/scripts/sync-backups-to-hetzner.sh` | Hostinger | Cross-server sync (stale IP) |
| `/root/infrastructure/shared/backup-rotation/disaster-recovery-playbook.sh` | Hetzner | Interactive full recovery script |
| `/root/wheeler-ecosystem-audit/2026-05-27-0444/BACKUP_AND_RESTORE.md` | All | This runbook |

---

## 8. VERIFIED STATUS SUMMARY

- **COREDB:** 1/4 backup categories covered (PostgreSQL only). Volumes, Redis, configs all unprotected. No offsite copy.
- **Hetzner/AIOPS:** 4/4 backup categories exist but PostgreSQL/Redis/Configs lack cron scheduling. Only Neo4j runs automatically.
- **Hostinger:** 4/6 backup categories covered. R2 offsite is broken. Encrypted backup has not run since May 11.
- **Restore testing:** Exists for PostgreSQL only, not all databases confirmed passing. No automated schedule.
- **Monitoring:** No Prometheus alert rules for backup freshness on any server.
- **Retention:** Inconsistent across servers (7 days on COREDB, 7-14 on Hetzner, 30 on Hostinger R2).
