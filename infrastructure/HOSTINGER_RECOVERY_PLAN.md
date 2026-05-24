# Hostinger CPU Recovery Plan

> **Target:** Reduce EDGE CPU from 42.4% steal + load 5.13 to under 40% total utilization.
> **Root Cause:** Hostinger hypervisor overcommitted — 42.4% CPU steal means nearly half the vCPUs this VM "owns" are actually running other tenants' workloads.
> **Strategy:** Remove every non-Gatekeeper workload from EDGE per server-role-policies.md (v1.0.0). EDGE must run ONLY Traefik, nginx static files, fail2ban, UFW, node_exporter, and promtail.

## Current State

| Metric | Value | Status |
|--------|-------|--------|
| CPU Steal | 42.4% | **CRITICAL** — hypervisor overcommitted; steal alone exceeds many targets |
| Load Avg (1/5/15) | 1.70 / 4.37 / 5.13 | **CRITICAL** — rising trend; 15-min at 5.13 on ~4-8 vCPUs |
| RAM Used | 6.1 GB / 31 GB | OK — 25 GB available |
| Disk Used | 239 GB / 387 GB (62%) | WARNING — growing; 148 GB free |
| Top CPU: usesend-redis | 17.82% | **CRITICAL VIOLATION** — database on EDGE |
| Top CPU: private-ai-webui | 16.94% | **CRITICAL VIOLATION** — AI/ML on EDGE |
| Top CPU: temporal-server | 10.31% | **CRITICAL VIOLATION** — worker on EDGE |

### Running Services on EDGE (with Policy Violations)

```
CONTAINER                         CPU%     POLICY STATUS
usesend-redis                     17.82%   CRITICAL — Database (Redis) on EDGE
private-ai-webui                  16.94%   CRITICAL — AI/ML service on EDGE
temporal-server                   10.31%   CRITICAL — Worker engine on EDGE
prediction-radar-scheduler         ~3-5%   CRITICAL — Worker/scheduler on EDGE
prediction-radar-worker            ~3-5%   CRITICAL — Worker on EDGE
shared-postgres-recovery           ~1-2%   CRITICAL — Database on EDGE
usesend-app                        ~1-2%   CRITICAL — Application code on EDGE
usesend-minio                      ~1-2%   CRITICAL — Object storage on EDGE
traefik                            ~1-2%   OK — Gatekeeper role
frgops-postgres                    ~1-2%   CRITICAL — Database on EDGE
frgops-redis                       ~1%     CRITICAL — Database on EDGE
n8n-edge                           ~1%     CRITICAL — Worker/app on EDGE
litellm-edge                       ~1%     WARNING — AI proxy on EDGE (arguable)
minio-edge                         ~0.5%   WARNING — Object storage on EDGE
```

**Total CRITICAL violations:** 11 containers running services that must never be on EDGE per server-role-policies.md.

---

## Highest Impact Migrations (ordered by CPU reduction)

| # | Service | CPU% | Mem Est | Migrate To | Difficulty | Time Est | CPU Saved |
|---|---------|------|---------|------------|------------|----------|-----------|
| 1 | usesend-redis | 17.82% | ~500MB | COREDB (join shared Redis) | MEDIUM — data migration, reconnect app | 2h | **17.8%** |
| 2 | private-ai-webui | 16.94% | ~1.5GB | AIOPS (Docker, cgroup-limited) | MEDIUM — GPU/render deps, port config | 1.5h | **16.9%** |
| 3 | temporal-server | 10.31% | ~512MB | AIOPS (Docker, join existing Temporal if present) | EASY — stateless, just move | 1h | **10.3%** |
| 4 | prediction-radar-worker | ~4% | ~256MB | AIOPS (already has API/DB there) | EASY — already has AIOPS infra | 0.5h | **4.0%** |
| 5 | prediction-radar-scheduler | ~3% | ~128MB | AIOPS (already has API/DB there) | EASY — already has AIOPS infra | 0.5h | **3.0%** |
| 6 | usesend-app | ~2% | ~256MB | AIOPS (Docker) | MEDIUM — minio client reconnect | 1.5h | **2.0%** |
| 7 | usesend-minio | ~2% | ~512MB | COREDB (join shared MinIO) | MEDIUM — data migration | 1h | **2.0%** |
| 8 | shared-postgres-recovery | ~2% | ~256MB | AIOPS (or remove if unused) | EASY — likely stale | 0.5h | **2.0%** |
| 9 | frgops-postgres | ~2% | ~512MB | COREDB (dedicated DB) | HARD — critical app data, downtime | 3h | **2.0%** |
| 10 | frgops-redis | ~1% | ~128MB | COREDB (join shared Redis) | MEDIUM — data migration | 1h | **1.0%** |
| 11 | n8n-edge | ~1% | ~384MB | AIOPS (n8n engine belongs on AIOPS) | MEDIUM — workflow migration | 1h | **1.0%** |
| 12 | litellm-edge | ~1% | ~256MB | AIOPS (LiteLLM already exists on AIOPS PM2) | EASY — deduplicate | 0.5h | **1.0%** |
| 13 | minio-edge | ~0.5% | ~512MB | COREDB (join shared MinIO) | MEDIUM — bucket migration | 1h | **0.5%** |

**Estimated total CPU saved:** ~63% of current usage. Target: bring total utilization below 40%.

### Migration Ordering Constraints

1. **COREDB migrations first** (usesend-redis, redis, postgres, minio) — data layer must be stable before moving apps
2. **AIOPS app migrations second** (private-ai-webui, temporal, prediction-radar, usesend-app, n8n) — apps need databases already running on COREDB
3. **Decommission last** — remove EDGE services only after AIOPS replacements verified

---

## Safe Shutdown Order

Each step includes a **Pre-Check** and **Post-Verification**. No step proceeds until the previous step is confirmed healthy.

### Phase 1: COREDB Data Layer Setup (target: COREDB ready to receive)

```
STEP 1.1 — Remove duplicated monitoring stack from COREDB
  RATIONALE: COREDB has prometheus+grafana+loki — policy says exporters only.
  ACTION:   Stop prometheus, grafana, loki containers on COREDB.
  VERIFY:   AIOPS monitoring still scrapes COREDB exporters (node_exporter, postgres_exporter, redis_exporter).
  ROLLBACK: docker compose -f <monitoring-compose> up -d
  TIME:     0.5h

STEP 1.2 — Provision FRGops database on COREDB PostgreSQL
  RATIONALE: frgops-postgres on EDGE must move to COREDB shared PostgreSQL.
  ACTION:   Create database 'frgops' on COREDB postgres. Set up pgBouncer routing.
  VERIFY:   psql -h 100.64.0.4 -U wheeler_admin -d frgops -c "SELECT 1"
  ROLLBACK: DROP DATABASE frgops on COREDB (no data yet).
  TIME:     0.5h

STEP 1.3 — Migrate FRGops PostgreSQL data from EDGE to COREDB
  RATIONALE: Critical business data. Must preserve all FRGops/FRGCRM/Chatwoot/Docuseal data.
  ACTION:   pg_dump frgops-postgres on EDGE → pipe over Tailscale → pg_restore to COREDB.
            Use --no-owner --no-acl. Schedule during low-traffic window.
  VERIFY:   Row counts match between source and destination. App connection test.
  ROLLBACK: Keep EDGE postgres running for 24h after migration; revert app DATABASE_URL if issues.
  TIME:     2h (including validation)

STEP 1.4 — Migrate Redis data from EDGE to COREDB
  RATIONALE: usesend-redis (17.82% CPU) and frgops-redis (~1%) both belong on COREDB.
  ACTION:   For usesend: BGSAVE on EDGE, copy RDB to COREDB, load. For frgops: cache-only, no migration needed.
  VERIFY:   redis-cli -h 100.64.0.4 PING; key count matches.
  ROLLBACK: Keep EDGE Redis running for 24h.
  TIME:     1h

STEP 1.5 — Migrate MinIO data from EDGE to COREDB
  RATIONALE: usesend-minio and minio-edge belong on COREDB's shared MinIO.
  ACTION:   mc mirror from EDGE MinIO to COREDB MinIO over Tailscale.
  VERIFY:   mc diff; bucket listing matches; object count matches.
  ROLLBACK: Keep EDGE MinIO running 24h.
  TIME:     1.5h (depends on data volume)
```

### Phase 2: AIOPS Application Migration (target: services running on AIOPS)

```
STEP 2.1 — Connect AIOPS LiteLLM to COREDB PostgreSQL
  RATIONALE: Deduplicate litellm-edge on EDGE. AIOPS already runs LiteLLM via PM2.
  ACTION:   Verify AIOPS PM2 litellm has all model routes EDGE litellm had.
            Migrate any unique config. Point AIOPS litellm DB to COREDB postgres.
  VERIFY:   curl https://litellm.wheeler.ai/health (Traefik route updated to AIOPS).
  ROLLBACK: Revert Traefik route to EDGE litellm.
  TIME:     0.5h

STEP 2.2 — Deploy private-ai-webui on AIOPS
  RATIONALE: 16.94% CPU on EDGE. AI on AIOPS per policy.
  ACTION:   Clone/recreate private-ai-webui container on AIOPS. Set cgroup limit.
            Configure to use COREDB for any persistence needs.
  VERIFY:   WebUI loads via Traefik route. Model inference works. CPU/mem within limits.
  ROLLBACK: Revert Traefik route to EDGE instance.
  TIME:     1.5h

STEP 2.3 — Deploy Temporal on AIOPS
  RATIONALE: 10.31% CPU on EDGE. Temporal is a worker engine — AIOPS role.
  ACTION:   If Temporal already exists on AIOPS: verify it can absorb EDGE workflows.
            If not: deploy Temporal server + configure workers.
  VERIFY:   Temporal UI accessible. Workflows executing. No backlog.
  ROLLBACK: Revert workflow routing to EDGE Temporal.
  TIME:     1h

STEP 2.4 — Move prediction-radar-worker and scheduler to AIOPS
  RATIONALE: AIOPS already hosts prediction-radar-api (port 8000) and DB (port 5433).
  ACTION:   Update worker/scheduler config to use AIOPS-local API/DB. Deploy on AIOPS.
  VERIFY:   Jobs scheduled and executed on AIOPS. No EDGE workers running.
  ROLLBACK: Restart EDGE worker containers.
  TIME:     0.5h

STEP 2.5 — Deploy usesend-app on AIOPS
  RATIONALE: Application code belongs on AIOPS.
  ACTION:   Recreate usesend-app container on AIOPS. Point to COREDB Redis/MinIO.
  VERIFY:   App accessible, functions working with COREDB data.
  ROLLBACK: Revert Traefik route to EDGE app.
  TIME:     1.5h

STEP 2.6 — Deploy n8n engine on AIOPS
  RATIONALE: n8n workflow engine belongs on AIOPS. Status page only on EDGE.
  ACTION:   Deploy n8n on AIOPS. Migrate workflows from EDGE n8n SQLite.
            Status page (read-only) can remain on EDGE proxied from AIOPS.
  VERIFY:   Workflows execute on AIOPS. Status page loads from EDGE.
  ROLLBACK: Revert Traefik route to EDGE n8n.
  TIME:     1h
```

### Phase 3: EDGE Decommission (target: EDGE runs only Gatekeeper services)

```
STEP 3.1 — Stop usesend-redis on EDGE
  PRECHECK: usesend-app on AIOPS connected to COREDB Redis, verified working.
  ACTION:   docker stop usesend-redis; docker rm usesend-redis
  VERIFY:   No usesend errors in AIOPS logs. COREDB Redis responding.

STEP 3.2 — Stop private-ai-webui on EDGE
  PRECHECK: AIOPS private-ai-webui verified working, Traefik route updated.
  ACTION:   docker stop private-ai-webui; docker rm private-ai-webui
  VERIFY:   EDGE CPU drops ~17%. AIOPS CPU within expected bounds.

STEP 3.3 — Stop temporal-server on EDGE
  PRECHECK: AIOPS Temporal verified working, no pending workflows on EDGE.
  ACTION:   docker stop temporal temporal-ui (if present); docker rm temporal temporal-ui
  VERIFY:   EDGE CPU drops ~10%. All workflows executing on AIOPS.

STEP 3.4 — Stop prediction-radar-worker and scheduler on EDGE
  PRECHECK: AIOPS workers verified executing jobs.
  ACTION:   docker stop prediction-radar-scheduler prediction-radar-worker; docker rm ...
  VERIFY:   Prediction Radar API still functional, jobs running on AIOPS.

STEP 3.5 — Stop usesend-app and usesend-minio on EDGE
  PRECHECK: AIOPS usesend-app verified, COREDB MinIO verified.
  ACTION:   docker stop usesend-app usesend-minio; docker rm ...
  VERIFY:   All data accessible from COREDB. App functional.

STEP 3.6 — Stop frgops-postgres, frgops-redis on EDGE (AFTER 24h verification)
  PRECHECK: 24h elapsed since Phase 1 migration. Zero errors. COREDB stable.
  ACTION:   docker stop frgops-postgres frgops-redis; docker rm ...
  VERIFY:   FRGops/FRGCRM/Chatwoot/Docuseal all functional via COREDB.

STEP 3.7 — Stop n8n-edge, litellm-edge, minio-edge on EDGE
  PRECHECK: AIOPS replacements verified.
  ACTION:   docker stop n8n-edge litellm-edge minio-edge; docker rm ...
  VERIFY:   All services functional via AIOPS/COREDB.

STEP 3.8 — Remove shared-postgres-recovery
  PRECHECK: Confirm this is stale/not needed (name suggests one-time recovery).
  ACTION:   docker stop shared-postgres-recovery; docker rm shared-postgres-recovery
  VERIFY:   No service breaks.
```

---

## Monitoring Checkpoints

After each step, run and record:

```bash
# EDGE
echo "=== EDGE $(date) ==="
uptime                           # load avg must be trending down
top -bn1 | head -5               # CPU steal must decrease
docker ps --format '{{.Names}}'  # fewer containers each step
free -h | grep Mem               # RAM must not spike
df -h /                          # disk must not fill

# AIOPS
echo "=== AIOPS $(date) ==="
uptime                           # load must stay under 8 (16 cores)
docker ps --format '{{.Names}}' | wc -l  # container count
free -h | grep Mem               # must stay above 4GB free

# COREDB
echo "=== COREDB $(date) ==="
uptime                           # must stay under 1
docker ps --format '{{.Names}}'  # minimal containers
free -h | grep Mem               # abundant free expected
df -h /data                      # storage headroom
```

### Critical Thresholds — STOP MIGRATION if:

- EDGE load avg 15 exceeds 6.0 (system already near collapse)
- COREDB PostgreSQL connections exceed 80% of max_connections
- Any application returns 5xx errors for >2 minutes
- Disk on any server exceeds 85%
- Tailscale tunnel drops (packet loss >1%)

---

## Rollback Plan

Each migration is independently reversible. Keep EDGE containers stopped (not removed) for 24 hours. Volumes are preserved until Phase 3.7 is confirmed clean.

### Per-Service Rollback Procedure

1. **Database rollback:** Update application DATABASE_URL back to EDGE IP:port. Restart app. Verify connectivity. Done in <2 min.
2. **Redis rollback:** Update application REDIS_URL back to EDGE. Restart app. Redis cache repopulates on next request.
3. **Service rollback:** Update Traefik route on EDGE to point back to local container. Docker start stopped container. Verify.
4. **Full EDGE restore:** If catastrophic: `docker compose -f <compose-dir>/ up -d` for each stack. All volumes preserved. Back online in <5 min per stack.

### Rollback Triggers

| Symptom | Action |
|---------|--------|
| COREDB PostgreSQL latency >50ms (from <1ms baseline) | Roll back DB migration, investigate COREDB I/O |
| AIOPS CPU exceeds 80% sustained 5 min | Roll back last service moved, add cgroup limits |
| EDGE steal time *increases* after removal | Stop all migrations, contact Hostinger support |
| Any data integrity check fails | Immediate rollback for that service |
| PM2 apps on AIOPS OOM | Roll back heaviest Docker service, adjust limits |

---

## Post-Recovery Target State (EDGE)

After all migrations, EDGE runs ONLY:

```
CONTAINER          PURPOSE                          POLICY
traefik            Public reverse proxy + TLS       EDGE Gatekeeper
nginx-static       Static frontend assets           EDGE (behind Traefik)
fail2ban           Intrusion prevention             EDGE (system)
node_exporter      Prometheus metrics export        EDGE (system)
promtail           Log shipping to AIOPS Loki       EDGE (system)
```

Expected metrics:
- CPU steal: unchanged (hypervisor issue) but actual usage drops to ~8-15%
- Load avg: <1.0 (down from 5.13)
- RAM: <2GB (down from 6.1GB)
- Disk: <50GB (down from 239GB)
- Docker containers: 2-3 (down from 13+)
- Zero CRITICAL policy violations
