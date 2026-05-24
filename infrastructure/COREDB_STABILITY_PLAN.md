# COREDB Stability Plan

> **Purpose:** Stabilize COREDB (Hetzner CX32, 100.118.166.117) as the authoritative data layer — the single source of truth for all Wheeler business data.
> **Policy Reference:** server-role-policies.md v1.0.0 — COREDB is "The Vault": all persistent state, databases, object storage, vector stores, backups. No compute. No dashboards. No public exposure.

## Current State

| Resource | Used | Total | Free | Assessment |
|----------|------|-------|------|------------|
| CPU | 0.6% us | 8 vCPUs | ~99% idle | **Severely underutilized** — barely any compute happening |
| RAM | 1.4 GB | 31 GB | 29.6 GB | **Severely underutilized** — 95% free |
| Disk | 6.2 GB | 338 GB | ~332 GB | **Plenty of headroom** (1.8% used) |
| Docker | 7 containers | — | — | Minimal |
| Tailscale IP | 100.118.166.117 | — | — | Connected |

### Current Docker Containers on COREDB

```
CONTAINER       PURPOSE                        POLICY STATUS
postgres        Primary PostgreSQL (port 5432) OK — primary DB on COREDB
redis           Primary Redis (port 6379)      OK — primary cache on COREDB
minio           Object storage (port 9000)     OK — S3-compatible object store on COREDB
prometheus      Metrics collection             WARNING — dashboards on COREDB (should only have exporters)
grafana         Dashboard visualization        WARNING — dashboards on COREDB (should only have exporters)
loki            Log aggregation                WARNING — log aggregation on COREDB (should only have exporters)
uptime-kuma     Synthetic monitoring           WARNING — application on COREDB (should run on AIOPS)
```

### Policy Compliance Gaps

```
VIOLATION                          SEVERITY    REFERENCE
prometheus on COREDB               WARNING     § "Monitoring Dashboards — NEVER on COREDB"
grafana on COREDB                  WARNING     § "Monitoring Dashboards — NEVER on COREDB"
loki on COREDB                     WARNING     § "Monitoring Dashboards — NEVER on COREDB"
uptime-kuma on COREDB              WARNING     § "Non-DB Container Workloads — NEVER on COREDB"
No enforcement of com.wheeler.* labels   WARNING     § "Role Labeling Standard"
No /data partition (data on root?) INFO       § "Data partition on /data" — verify data volumes are on /data
No pgBouncer (port 6432)           INFO        § "Database Management — pgBouncer recommended"
No Qdrant (port 6333)              INFO        § "Vector Stores — Qdrant planned but not deployed"
No pgBackRest or restic            WARNING     § "Backup Infrastructure — not yet configured"
```

---

## Migration Target: Stateful Services to COREDB

All database, cache, and object storage services currently on EDGE must migrate to COREDB. COREDB becomes the single authoritative data layer.

| Service | Current Location | Size | Migration Method | Validation |
|---------|-----------------|------|-----------------|------------|
| **frgops-postgres** (DB: frgops, frgcrm, chatwoot, docuseal) | EDGE (Hostinger) | ~10 GB | `pg_dump -h EDGE_IP -U frgops -d frgops --no-owner --no-acl \| psql -h localhost -U wheeler_admin -d frgops` (piped over Tailscale). Repeat for frgcrm, chatwoot_production, docuseal_production databases. Use `--jobs=4` for parallel restore. | Row counts match. App integration test (connect FRGops, Chatwoot, Docuseal, FRGCRM to COREDB PostgreSQL and verify CRUD operations). |
| **frgops-redis** (FRGops cache) | EDGE (Hostinger) | ~1 GB | No migration needed — cache-only with allkeys-lru. Rebuild from scratch on COREDB Redis. Create separate DB number (e.g., `/4`) on existing COREDB Redis. | redis-cli PING on new DB. App cache writes/reads functional. |
| **usesend-redis** (17.82% EDGE CPU) | EDGE (Hostinger) | ~2 GB | If persistent data exists: `redis-cli --rdb /tmp/usesend.rdb` on EDGE, SCP over Tailscale, load into COREDB Redis on separate DB number `/5`. | Key count matches. App connectivity verified. |
| **usesend-minio** (S3 objects) | EDGE (Hostinger) | ~5 GB est | `mc mirror EDGE_MINIO/bucket COREDB_MINIO/bucket --watch` (initial sync with continuous replication until cutover). Then `mc diff` to verify. | Bucket listing count matches. Object ETags match. App reads/writes to COREDB MinIO. |
| **minio-edge** (edge object storage) | EDGE (Hostinger) | ~5 GB est | Same `mc mirror` method as usesend-minio. Merge into COREDB MinIO under separate bucket prefix. | Bucket listing matches. App reads/writes verified. |
| **litellm SQLite** (LiteLLM usage tracking) | EDGE (Hostinger) | <100 MB | LiteLLM on AIOPS already uses PostgreSQL. No migration needed — EDGE SQLite is disposable usage stats. Deduplicate into AIOPS litellm. | AIOPS litellm /health endpoint returns 200. All model routes functional. |

### Post-Migration COREDB Service Map

```
SERVICE         PORT    BIND ADDRESS       DB/USER                    NOTE
PostgreSQL      5432    100.118.166.117    frgops, frgcrm, chatwoot,  All app databases consolidated
                                           docuseal, wheeler,         from EDGE + existing schemas
                                           prediction_radar, ravynai
pgBouncer       6432    100.118.166.117    (connection pool, 25 pool)  NEW — connection pooling
Redis           6379    100.118.166.117    /0: wheeler, /1: frgcrm,   All cache data consolidated
                                           /2: chatwoot, /3: docuseal, from EDGE + existing DBs
                                           /4: frgops, /5: usesend
MinIO           9000    100.118.166.117    buckets: backups, uploads,  All object storage consolidated
                                assets, logs-archive, usesend
MinIO Console   9001    100.118.166.117    (admin only, Tailscale IP)  Admin access
Qdrant          6333    100.118.166.117    vector collections          NEW — planned deployment
node_exporter   9100    100.118.166.117    system metrics              OK — exporter only
postgres_exporter 9187  100.118.166.117    PostgreSQL metrics           NEW — required per policy
redis_exporter  9121    100.118.166.117    Redis metrics                NEW — required per policy
```

---

## Duplicated Monitoring Resolution

**Problem:** COREDB runs its own Prometheus + Grafana + Loki stack. This duplicates the monitoring stack on AIOPS and violates server-role-policies.md Section "Monitoring Dashboards — NEVER on COREDB."

Per policy, COREDB should run only **exporters** (node_exporter, postgres_exporter, redis_exporter). Metrics are **pulled** by Prometheus on AIOPS, not collected locally.

### Resolution Steps

```
STEP 1. Install postgres_exporter on COREDB
  ACTION:   docker run -d --name postgres_exporter \
              -e DATA_SOURCE_NAME="postgresql://wheeler_admin:PASS@100.118.166.117:5432/postgres?sslmode=disable" \
              -p 100.118.166.117:9187:9187 \
              prometheuscommunity/postgres-exporter
  VERIFY:   curl http://100.118.166.117:9187/metrics | grep pg_stat_database

STEP 2. Install redis_exporter on COREDB
  ACTION:   docker run -d --name redis_exporter \
              -e REDIS_ADDR="redis://100.118.166.117:6379" \
              -e REDIS_PASSWORD="${REDIS_PASSWORD_COREDB}" \
              -p 100.118.166.117:9121:9121 \
              oliver006/redis_exporter
  VERIFY:   curl http://100.118.166.117:9121/metrics | grep redis_connected_clients

STEP 3. Update AIOPS Prometheus scrape config
  ACTION:   Add COREDB targets to AIOPS prometheus.yml:
              - job_name: coredb-node
                static_configs:
                  - targets: ['100.118.166.117:9100']
              - job_name: coredb-postgres
                static_configs:
                  - targets: ['100.118.166.117:9187']
              - job_name: coredb-redis
                static_configs:
                  - targets: ['100.118.166.117:9121']
  VERIFY:   Prometheus targets page shows all three COREDB targets UP.

STEP 4. Stop and remove duplicate monitoring stack on COREDB
  PRECHECK: AIOPS Prometheus scraping COREDB exporters successfully (3/3 UP).
  ACTION:   docker stop prometheus grafana loki uptime-kuma
            docker rm prometheus grafana loki uptime-kuma
  VERIFY:   AIOPS Grafana dashboards still show COREDB metrics.
            No gaps in metrics timeline (confirm continuous scrape).
  ROLLBACK: docker compose -f <monitoring-compose> up -d (kept compose file for 48h).
```

### Post-Cleanup COREDB Containers

```
CONTAINER              POLICY STATUS
postgres               OK — primary database
redis                  OK — primary cache
minio                  OK — object storage
pgBouncer (new)        OK — connection pooling
Qdrant (new)           OK — vector store
node_exporter          OK — metrics exporter
postgres_exporter      OK — metrics exporter (NEW)
redis_exporter         OK — metrics exporter (NEW)
```

**8 containers total.** All database/storage/exporters. No dashboards. No compute. No application code.

---

## Backup/Replication Readiness

### Current State (as of 2026-05-23)

| Capability | Status | Action Needed |
|-----------|--------|---------------|
| PostgreSQL WAL archiving | **NOT CONFIGURED** | Enable `archive_mode=on`, `archive_command` to MinIO bucket `backups/wal` |
| pgBackRest | **NOT INSTALLED** | Install and configure for full/differential/incremental backup schedule |
| restic | **NOT INSTALLED** | Install, configure repository on MinIO, set up cron for hourly snapshots |
| Streaming replication | **NOT CONFIGURED** | Set up `wal_level=replica`, `max_wal_senders=5` for AIOPS read replicas |
| Redis AOF persistence | **UNKNOWN** | Verify `appendonly yes` and `appendfsync everysec` in redis.conf |
| Redis RDB snapshots | **UNKNOWN** | Verify `save 900 1`, `save 300 10`, `save 60 10000` in redis.conf |
| MinIO versioning | **NOT CONFIGURED** | Enable versioning on `backups` and `uploads` buckets. Enable object lock on `backups`. |
| Backup verification | **NOT CONFIGURED** | Weekly automated restore test to temp PostgreSQL instance |
| Offsite backup | **NOT CONFIGURED** | rclone sync MinIO `backups` bucket to remote S3 (or Hetzner Storage Box) |

### Gap Analysis

```
GAP 1 — No PostgreSQL backups exist
  RISK:         Complete data loss if COREDB disk fails or PostgreSQL corruption.
  ACTION:       Immediately run pg_dumpall > /data/backups/full_dump_$(date +%Y%m%d).sql
                Then install pgBackRest with Full (weekly), Differential (nightly), Incremental (6h).
  PRIORITY:     CRITICAL — no backups means no recovery. Do this before any EDGE migrations.
  TIME EST:     2h for initial pgBackRest setup + first full backup.

GAP 2 — No point-in-time recovery (PITR)
  RISK:         Can only restore to last pgBackRest backup (up to 24h data loss).
  ACTION:       Enable WAL archiving to MinIO bucket `backups/wal`.
                archive_mode = on
                archive_command = 'mc pipe coredb-minio/backups/wal/%f'
  PRIORITY:     HIGH — needed before database migrations.
  TIME EST:     0.5h.

GAP 3 — No Redis persistence
  RISK:         All Redis data lost on restart. Queue data, session data, cache gone.
  ACTION:       Enable AOF + RDB:
                appendonly yes
                appendfsync everysec
                save 900 1
                save 300 10
                save 60 10000
  PRIORITY:     HIGH — must be enabled before EDGE Redis migration.
  TIME EST:     0.25h.

GAP 4 — No MinIO bucket versioning or object lock
  RISK:         Accidental deletion or corruption of backups is permanent.
  ACTION:       mc version enable coredb-minio/backups
                mc version enable coredb-minio/uploads
                mc retention set coredb-minio/backups --mode compliance --days 30
  PRIORITY:     MEDIUM — enables safe backup lifecycle.
  TIME EST:     0.25h.

GAP 5 — No automated backup verification
  RISK:         Backups exist but are silently corrupt. Only discovered during actual recovery.
  ACTION:       Weekly cron: pgBackRest restore to temp PG instance → verify row counts → drop temp.
  PRIORITY:     MEDIUM — deferred until backup infrastructure stable.
  TIME EST:     1h script creation + cron setup.

GAP 6 — No offsite backup
  RISK:         Hetzner datacenter fire/flood/outage = all data lost.
  ACTION:       rclone sync MinIO `backups` bucket to Hetzner Storage Box or Backblaze B2.
                Nightly cron after backup completes.
  PRIORITY:     MEDIUM — critical for disaster recovery, but staged after local backups working.
  TIME EST:     1h rclone config + test sync.
```

### Recommended Backup Schedule

```
SCHEDULE          WHAT                                     TOOL
Every 6 hours     PostgreSQL incremental + WAL archive      pgBackRest
Nightly 02:00     PostgreSQL differential backup            pgBackRest
Nightly 03:00     Redis BGSAVE to MinIO backups bucket     redis-cli BGSAVE + mc cp
Weekly Sun 01:00  PostgreSQL full backup                    pgBackRest
Weekly Sun 04:00  Backup verification (temp restore)        pgBackRest restore + validation
Nightly 05:00     Offsite sync (rclone to remote S3)        rclone sync
Monthly 1st       MinIO bucket snapshot (all buckets)      mc mirror to archive bucket
```

---

## Security Validation

### Firewall (UFW) Verification

Per policy: COREDB UFW must **default deny ALL incoming**. Allow Tailscale subnet only.

```bash
# Expected UFW state on COREDB
ufw status verbose
# Expected output:
# Default: deny (incoming), allow (outgoing), deny (routed)
# To                         Action      From
# --                         ------      ----
# 22/tcp                     ALLOW       100.64.0.0/10   (SSH, Tailscale only)
# 5432/tcp                   ALLOW       100.64.0.0/10   (PostgreSQL)
# 6379/tcp                   ALLOW       100.64.0.0/10   (Redis)
# 6432/tcp                   ALLOW       100.64.0.0/10   (pgBouncer)
# 9000/tcp                   ALLOW       100.64.0.0/10   (MinIO S3 API)
# 9001/tcp                   ALLOW       100.64.0.0/10   (MinIO Console, admin)
# 6333/tcp                   ALLOW       100.64.0.0/10   (Qdrant)
# 9100/tcp                   ALLOW       100.64.0.0/10   (node_exporter)
# 9187/tcp                   ALLOW       100.64.0.0/10   (postgres_exporter)
# 9121/tcp                   ALLOW       100.64.0.0/10   (redis_exporter)
# NO 0.0.0.0 rules allowed
```

### 0.0.0.0 Binding Check

Per policy: "Every service binds to Tailscale IP or 127.0.0.1. Nothing answers on the public network interface."

```bash
# Run on COREDB
ss -tlnp | grep -v "127.0.0.1\|100.118.166.117\|::1"
# Expected: NO OUTPUT (no 0.0.0.0 bindings)
```

If any service is bound to 0.0.0.0, this is a **CRITICAL** violation. All services must be reconfigured:
- PostgreSQL: `listen_addresses = '100.118.166.117'` in postgresql.conf
- Redis: `bind 100.118.166.117` in redis.conf
- MinIO: `--address ":9000"` with Docker port mapping to `100.118.166.117:9000:9000`
- node_exporter: `--web.listen-address=100.118.166.117:9100`

### Tailscale ACL Review

Verify the COREDB Tailscale ACL (from shared/security/tailscale-acls.json):

```jsonc
// COREDB rules must enforce:
{
  // COREDB REJECTS all inbound from EDGE
  {"action": "reject", "src": ["tag:edge"], "dst": ["tag:coredb:*"]},
  
  // AIOPS can ONLY reach database/monitoring ports
  {"action": "accept", "src": ["tag:aiops"], "dst": ["tag:coredb:5432,6379,6432,9000,6333,8123,9100,9121,9187"]},
  
  // COREDB can ONLY reach AIOPS monitoring
  {"action": "accept", "src": ["tag:coredb"], "dst": ["tag:aiops:3100,9090"]},
  
  // Default deny
  {"action": "reject", "src": ["*"], "dst": ["tag:coredb:*"]}
}
```

### Credential Rotation

Before accepting EDGE data migrations, rotate database credentials to ensure no stale EDGE credentials work:

```bash
# PostgreSQL — rotate password for application users
ALTER ROLE frgops WITH PASSWORD '<new_secure_password>';
ALTER ROLE wheeler_admin WITH PASSWORD '<new_secure_password>';

# Redis — set requirepass (if not already)
# In redis.conf:
# requirepass <new_secure_password>

# MinIO — rotate root credentials
# mc admin user add coredb-minio <new_access_key> <new_secret_key>
# mc admin user remove coredb-minio <old_access_key>
```

### Filesystem Encryption

Per policy: "LUKS on /data partition." Verify:

```bash
# Check if /data is encrypted
lsblk -f | grep -i luks
# If no LUKS: data at risk if Hetzner server is physically accessed or decommissioned.

# Check if /data is a separate mount point
df -h /data
# If /data is NOT a separate partition: OS disk fill-up could crash PostgreSQL.
```

If /data is not a separate encrypted partition, this is a WARNING-level gap. Schedule LUKS setup during next maintenance window. This is non-blocking for migrations but must be tracked.

### Audit Logging

Enable PostgreSQL audit logging for compliance:

```sql
-- In postgresql.conf:
log_connections = on
log_disconnections = on
log_duration = off
log_statement = 'ddl'  -- Log all CREATE/ALTER/DROP
log_min_duration_statement = 500  -- Log queries >500ms
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
```

---

## Pre-Migration Checklist (Before Any EDGE Data Moves to COREDB)

- [ ] COREDB PostgreSQL WAL archiving enabled (archive_mode=on, archive_command to MinIO)
- [ ] pgBackRest installed and first full backup completed successfully
- [ ] Redis AOF + RDB persistence enabled and verified
- [ ] MinIO bucket versioning enabled on `backups` bucket
- [ ] UFW verified: default deny, Tailscale-only rules, no 0.0.0.0
- [ ] ss -tlnp verified: no 0.0.0.0 bindings
- [ ] All containers labeled with `com.wheeler.role=coredb`
- [ ] Prometheus + Grafana + Loki + UptimeKuma stopped and removed
- [ ] postgres_exporter and redis_exporter installed and scraped by AIOPS Prometheus
- [ ] Database connection strings generated for AIOPS apps (postgres://user:pass@100.118.166.117:5432/db)
- [ ] Redis connection strings generated for AIOPS apps (redis://:pass@100.118.166.117:6379/DB)
- [ ] MinIO access keys generated for AIOPS apps
- [ ] pgBouncer deployed on port 6432 with transaction pooling
- [ ] Credentials rotated (new passwords, no EDGE-origin credentials)
- [ ] Disk monitoring alert configured at 80% capacity
- [ ] PostgreSQL max_connections reviewed (recommended: 200 with pgBouncer in front)
