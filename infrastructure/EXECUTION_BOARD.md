# Wheeler Ecosystem — Master Execution Board

> **Version:** 1.0.0 | **Date:** 2026-05-23 | **Owner:** SRE Team
> **Purpose:** Single source of truth for migration execution. Tracks every service — current location vs target location per server-role-policies.md. Updated from live server audits.

---

## 1. CRITICAL VIOLATIONS — FIX TODAY

These are active security risks, data integrity threats, or policy violations classified as CRITICAL by server-role-policies.md. Each must be resolved before any other migration work proceeds.

| # | Violation | Server | Service | Risk | Fix Action |
|---|-----------|--------|---------|------|------------|
| 1 | **DATABASE ON EDGE** | EDGE | `shared-postgres-recovery` | Full database exposed on public-facing server. If EDGE breached, all recovery data exfiltrated. | Dump data → restore on COREDB wheeler-postgres → decommission on EDGE |
| 2 | **DATABASE ON EDGE** | EDGE | `usesend-redis` | Redis at 18% CPU on EDGE. Session/cache data exposed. Pivot point if EDGE compromised. | Migrate to COREDB wheeler-redis → repoint usesend config |
| 3 | **AI/ML ON EDGE** | EDGE | `private-ai-webui` (Open WebUI) | AI inference container at 44% mem of 1.5GB limit. Model access, API keys, user prompts all on public-facing server. | Stop container → recreate on AIOPS behind Tailscale → update DNS |
| 4 | **WORKER ON EDGE** | EDGE | `prediction-radar-app-scheduler` | Background compute consuming EDGE CPU (42.4% steal already critical). Worker code + credentials on public server. | Stop → deploy scheduler on AIOPS as part of prediction-radar stack |
| 5 | **WORKER ON EDGE** | EDGE | `prediction-radar-app-worker` | Async forecast compute on EDGE. Direct DB access from public-facing server. | Stop → deploy worker on AIOPS → verify job queue continuity |

### Near-CRITICAL (fix within 48 hours)

| # | Violation | Server | Service | Risk |
|---|-----------|--------|---------|------|
| 6 | **COMPUTE ON EDGE** | EDGE | `temporal-server` + `temporal-temporal-1` + `temporal-temporal-ui-1` | Workflow orchestration engine (10% CPU) on public server. Temporal has DB access, manages long-running workflows. Pivot risk. |
| 7 | **APP CODE ON EDGE** | EDGE | `usesend` | Full application runtime on public-facing server. |
| 8 | **MINIO ON EDGE** | EDGE | `usesend-storage` | Object storage on public server. User uploads/files accessible from internet. |
| 9 | **MONITORING ON COREDB** | COREDB | `wheeler-prometheus`, `wheeler-grafana`, `wheeler-loki`, `wheeler-uptime-kuma` | 4 dashboard/monitoring servers on the data vault. Violates "exporters only" policy. Attack surface on most critical server. |

---

## 2. Current Resource Utilization

### EDGE Server (Hostinger — 100.98.163.17 TS / 187.77.148.88 public)

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| CPU steal | 42.4% | < 10% | **CRITICAL** — Hostinger massively overcommitted |
| CPU user | 0.8% | < 80% | OK |
| Load avg | 5.13 | < core count | At limit |
| RAM used | 6.1 GB / 31 GB | < 80% | OK (20%) |
| RAM buff/cache | 24 GB | — | High, reclaimable under pressure |
| Swap | 0 | — | OK |
| Disk used | 239 GB / 387 GB (62%) | < 85% | OK |

**EDGE Capacity Headroom:** Essentially **zero** — CPU steal dominates. Every container moved off EDGE frees CPU that Hostinger's hypervisor steals. Migration off EDGE is a performance win for remaining services (Traefik).

**Running Containers (11):**
```
prediction-radar-app-scheduler    — violates worker-on-EDGE
prediction-radar-app-worker       — violates worker-on-EDGE
private-ai-webui                  — violates AI-on-EDGE (44% mem of 1.5GB limit!)
shared-postgres-recovery          — violates DB-on-EDGE
shared-postgres-exporter          — exporter (OK per policy)
temporal-server                   — violates compute-on-EDGE (10% CPU)
temporal-temporal-1               — violates compute-on-EDGE
temporal-temporal-ui-1            — violates compute-on-EDGE
usesend                           — violates app-code-on-EDGE
usesend-storage (MinIO)           — violates storage-on-EDGE
usesend-redis                     — violates DB-on-EDGE (18% CPU!)
```

---

### AIOPS Server (Hetzner CPX51 — 100.121.230.28 TS / 5.78.140.118 public)

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| CPU user | 21.3% | < 80% | OK |
| CPU system | 14.2% | < 30% | OK |
| Load avg | 2.06 | < 16 | OK |
| RAM used | 17.1 GB / 31 GB | < 80% | OK (55%) |
| RAM available | 14.2 GB | — | Good headroom |
| RAM buff/cache | 17.3 GB | — | High |
| Disk used | 52 GB / 338 GB (16%) | < 85% | Excellent headroom |

**AIOPS Capacity Headroom:** ~14 GB RAM available, ~286 GB disk, CPU at 35% combined. Can absorb EDGE workload easily.

**Docker Containers (24):**
```
prediction-radar-app-api          — OK (right server)
prediction-radar-app-web          — OK
prediction-radar-dashboard-v2     — OK
prediction-radar-app-db           — WARNING: primary DB on AIOPS
prediction-radar-app-redis        — WARNING: Redis on AIOPS
aiops-ravynai-app                 — OK
aiops-ravynai-postgres            — WARNING: primary DB on AIOPS
aiops-superset                    — OK
aiops-clickhouse                  — WARNING: primary analytics DB on AIOPS
aiops-healthchecks                — OK
aiops-changedetection             — OK
aiops-grafana                     — OK
aiops-prometheus                  — OK
langflow                          — OK
docuseal                          — OK
docuseal-redis                    — WARNING: Redis on AIOPS
frgops-standby (Postgres)         — WARNING: primary DB on AIOPS
hostinger-health-exporter         — OK
loki                              — OK
promtail                          — OK
netdata                           — OK
portainer                         — OK
dockge                            — OK
uptime-kuma                       — OK
```

**PM2 Services (17, all on AIOPS):**
```
litellm                           — 358 MB — OK
frgcrm-api                        — 236 MB — OK
surplusai-scraper-agent-svc       — 108 MB — OK
prediction-radar-agent-svc        — 107 MB — OK
voice-agent-svc                   — 107 MB — OK
ravyn-agent-svc                   — 106 MB — OK
paperless-agent-svc               — 105 MB — OK
horizon-agent-svc                 — 108 MB — OK
design-agent-svc                  — 116 MB — OK
frgcrm-agent-svc                  — 100 MB — OK
insforge-agent-svc                —  72 MB — OK
event-bus-relay                   —  65 MB — OK
war-room-server                   —  65 MB — OK
openclaw-dashboard                —  66 MB — OK
ecosystem-guardian                —  70 MB — OK
voice-outreach-service            —  53 MB — OK
backup-verification               — STOPPED
```

---

### COREDB Server (Hetzner CX32 — 100.118.166.117 TS / 5.78.210.123 public)

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| CPU user | 0.6% | < 80% | Idle |
| RAM used | 1.4 GB / 31 GB | < 80% | OK (4.5%) |
| RAM available | 29 GB | — | **MASSIVE free capacity** |
| Disk used | 6.2 GB / 338 GB (2%) | < 85% | **Nearly empty** |

**COREDB Capacity Headroom:** ~29 GB RAM free, ~332 GB disk free. Vastly underutilized. Ready to absorb all databases from EDGE and AIOPS.

**Containers (7):**
```
wheeler-postgres                  — OK (right server)
wheeler-redis                     — OK
wheeler-minio                     — OK
wheeler-prometheus                — WARNING: dashboard on COREDB
wheeler-grafana                   — WARNING: dashboard on COREDB
wheeler-loki                      — WARNING: monitoring on COREDB
wheeler-uptime-kuma               — WARNING: dashboard on COREDB
```

**Missing from COREDB (deployed but not yet present):**
- Qdrant (vector DB) — NOT DEPLOYED
- ClickHouse primary — currently only on AIOPS
- pgBouncer — NOT DEPLOYED

---

## 3. Master Migration Tracking Table

Status legend:
- **OK** = service is on correct server per policy
- **CRITICAL** = active security/data risk, fix today
- **WARNING** = degrades posture, fix within 7 days
- **MIGRATING** = migration in progress
- **PLANNED** = migration scheduled, not started
- **DONE** = migration complete, verified
- **N/A** = not applicable

### 3.1 Docker Services — EDGE Server

| # | Service | Current Server | Target Server | Status | CPU Impact | Risk | Dependencies | Rollback Ready | Comp % |
|---|---------|---------------|---------------|--------|------------|------|-------------|----------------|--------|
| 1 | `traefik-edge` | EDGE | EDGE | **OK** | Low | Low | Let's Encrypt, Cloudflare DNS | N/A | 100% |
| 2 | `shared-postgres-recovery` | EDGE | COREDB | **CRITICAL** | Medium | High | `usesend` (reads recovery data) | Yes — dump/restore | 0% |
| 3 | `shared-postgres-exporter` | EDGE | COREDB | WARNING | Low | Low | `shared-postgres-recovery` | Yes | 0% |
| 4 | `usesend-redis` | EDGE | COREDB | **CRITICAL** | High (18%) | High | `usesend` app | Yes — AOF copy | 0% |
| 5 | `usesend-storage` (MinIO) | EDGE | COREDB | WARNING | Medium | Medium | `usesend` app | Yes — mc mirror | 0% |
| 6 | `usesend` | EDGE | AIOPS | WARNING | Medium | Medium | Usesend-Redis, Usesend-MinIO, Usesend-PG | Yes | 0% |
| 7 | `private-ai-webui` | EDGE | AIOPS | **CRITICAL** | High (44% mem) | High | LiteLLM (AIOPS PM2), DEEPSEEK_API_KEY | Yes — container re-deploy | 0% |
| 8 | `prediction-radar-app-scheduler` | EDGE | AIOPS | **CRITICAL** | Medium | Medium | prediction-radar-app-db, prediction-radar-app-redis | Yes | 0% |
| 9 | `prediction-radar-app-worker` | EDGE | AIOPS | **CRITICAL** | Medium | Medium | prediction-radar-app-db, prediction-radar-app-redis, prediction-radar-api | Yes | 0% |
| 10 | `temporal-server` | EDGE | AIOPS | WARNING | Medium (10%) | Medium | PostgreSQL (temporal needs DB) | Yes — DB is shared or can be migrated | 0% |
| 11 | `temporal-temporal-1` | EDGE | AIOPS | WARNING | Low | Low | temporal-server | Yes | 0% |
| 12 | `temporal-temporal-ui-1` | EDGE | AIOPS | WARNING | Low | Low | temporal-server | Yes | 0% |

### 3.2 Docker Services — AIOPS Server

| # | Service | Current Server | Target Server | Status | CPU Impact | Risk | Dependencies | Rollback Ready | Comp % |
|---|---------|---------------|---------------|--------|------------|------|-------------|----------------|--------|
| 13 | `prediction-radar-app-api` | AIOPS | AIOPS | **OK** | Medium | Low | pred-radar-db, pred-radar-redis | N/A | 100% |
| 14 | `prediction-radar-app-web` | AIOPS | AIOPS | **OK** | Low | Low | pred-radar-api | N/A | 100% |
| 15 | `prediction-radar-dashboard-v2` | AIOPS | AIOPS | **OK** | Low | Low | pred-radar-api | N/A | 100% |
| 16 | `prediction-radar-app-db` | AIOPS | COREDB | WARNING | Medium | Medium | pred-radar-api, pred-radar-worker, pred-radar-scheduler | Yes — pg_dump/restore | 0% |
| 17 | `prediction-radar-app-redis` | AIOPS | COREDB | WARNING | Low | Medium | pred-radar-api, pred-radar-worker | Yes — AOF copy | 0% |
| 18 | `aiops-ravynai-app` | AIOPS | AIOPS | **OK** | Medium | Low | ravynai-postgres, LiteLLM | N/A | 100% |
| 19 | `aiops-ravynai-postgres` | AIOPS | COREDB | WARNING | Medium | Medium | ravynai-app | Yes — pg_dump/restore | 0% |
| 20 | `aiops-superset` | AIOPS | AIOPS | **OK** | Medium | Low | clickhouse, AIOPS PostgreSQL | N/A | 100% |
| 21 | `aiops-clickhouse` | AIOPS | COREDB | WARNING | Medium | High | superset, feed-handlers | Complex — CH data migration | 0% |
| 22 | `aiops-healthchecks` | AIOPS | AIOPS | **OK** | Low | Low | PostgreSQL (local or remote) | N/A | 100% |
| 23 | `aiops-changedetection` | AIOPS | AIOPS | **OK** | Low | Low | None (local state) | N/A | 100% |
| 24 | `aiops-grafana` | AIOPS | AIOPS | **OK** | Low | Low | prometheus, loki | N/A | 100% |
| 25 | `aiops-prometheus` | AIOPS | AIOPS | **OK** | Medium | Low | All exporters on all servers | N/A | 100% |
| 26 | `langflow` | AIOPS | AIOPS | **OK** | Medium | Low | LiteLLM | N/A | 100% |
| 27 | `docuseal` | AIOPS | AIOPS | **OK** | Low | Low | docuseal-redis, PostgreSQL | N/A | 100% |
| 28 | `docuseal-redis` | AIOPS | COREDB | WARNING | Low | Low | docuseal | Yes — AOF copy | 0% |
| 29 | `frgops-standby` (Postgres) | AIOPS | COREDB | WARNING | Low | Medium | frgcrm-api, frgcrm-agent-svc (PM2) | Yes — restore onto COREDB | 0% |
| 30 | `hostinger-health-exporter` | AIOPS | AIOPS | **OK** | Low | Low | None (scrapes Hostinger API) | N/A | 100% |
| 31 | `loki` | AIOPS | AIOPS | **OK** | Medium | Low | promtail (all servers) | N/A | 100% |
| 32 | `promtail` | AIOPS | AIOPS | **OK** | Low | Low | loki | N/A | 100% |
| 33 | `netdata` | AIOPS | AIOPS | **OK** | Low | Low | None | N/A | 100% |
| 34 | `portainer` | AIOPS | AIOPS | **OK** | Low | Low | Docker socket | N/A | 100% |
| 35 | `dockge` | AIOPS | AIOPS | **OK** | Low | Low | Docker socket | N/A | 100% |
| 36 | `uptime-kuma` | AIOPS | AIOPS | **OK** | Low | Low | None (outbound HTTP checks) | N/A | 100% |

### 3.3 Docker Services — COREDB Server

| # | Service | Current Server | Target Server | Status | CPU Impact | Risk | Dependencies | Rollback Ready | Comp % |
|---|---------|---------------|---------------|--------|------------|------|-------------|----------------|--------|
| 37 | `wheeler-postgres` | COREDB | COREDB | **OK** | Low | Low | None | N/A | 100% |
| 38 | `wheeler-redis` | COREDB | COREDB | **OK** | Low | Low | None | N/A | 100% |
| 39 | `wheeler-minio` | COREDB | COREDB | **OK** | Low | Low | None | N/A | 100% |
| 40 | `wheeler-prometheus` | COREDB | AIOPS | WARNING | Medium | Medium | Exporters on COREDB | Yes — config copy | 0% |
| 41 | `wheeler-grafana` | COREDB | AIOPS | WARNING | Low | Low | prometheus (will move too) | Yes — config copy | 0% |
| 42 | `wheeler-loki` | COREDB | AIOPS | WARNING | Medium | Medium | promtail (all servers) | Yes — config copy | 0% |
| 43 | `wheeler-uptime-kuma` | COREDB | AIOPS | WARNING | Low | Low | None | Yes — config copy | 0% |
| 44 | `qdrant` | **NOT DEPLOYED** | COREDB | **MISSING** | N/A | N/A | AI agent services on AIOPS | N/A | 0% |

### 3.4 PM2 Services — AIOPS Server

All 17 PM2 services currently run on AIOPS, which is their correct server per policy. No migrations needed.

| # | Service | Current Server | Target Server | Status | RAM | Dependencies | Notes |
|---|---------|---------------|---------------|--------|-----|-------------|-------|
| 45 | `litellm` | AIOPS | AIOPS | **OK** | 358 MB | DEEPSEEK_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY | Multi-provider LLM proxy |
| 46 | `frgcrm-api` | AIOPS | AIOPS | **OK** | 236 MB | frgops-standby (PG) | FRG CRM REST API |
| 47 | `surplusai-scraper-agent-svc` | AIOPS | AIOPS | **OK** | 108 MB | LiteLLM, DEEPSEEK_API_KEY | Scraper agent |
| 48 | `prediction-radar-agent-svc` | AIOPS | AIOPS | **OK** | 107 MB | prediction-radar-api, LiteLLM | PR AI agent |
| 49 | `voice-agent-svc` | AIOPS | AIOPS | **OK** | 107 MB | LiteLLM, DEEPSEEK_API_KEY | Voice AI agent |
| 50 | `ravyn-agent-svc` | AIOPS | AIOPS | **OK** | 106 MB | ravynai-app, LiteLLM | RavynAI agent |
| 51 | `paperless-agent-svc` | AIOPS | AIOPS | **OK** | 105 MB | LiteLLM | Paperless agent |
| 52 | `horizon-agent-svc` | AIOPS | AIOPS | **OK** | 108 MB | LiteLLM | Horizon agent |
| 53 | `design-agent-svc` | AIOPS | AIOPS | **OK** | 116 MB | LiteLLM | Design agent |
| 54 | `frgcrm-agent-svc` | AIOPS | AIOPS | **OK** | 100 MB | frgcrm-api, LiteLLM | FRG CRM agent |
| 55 | `insforge-agent-svc` | AIOPS | AIOPS | **OK** | 72 MB | LiteLLM | InsForge agent |
| 56 | `event-bus-relay` | AIOPS | AIOPS | **OK** | 65 MB | NATS, Redis | Internal event relay |
| 57 | `war-room-server` | AIOPS | AIOPS | **OK** | 65 MB | None | War room dashboard backend |
| 58 | `openclaw-dashboard` | AIOPS | AIOPS | **OK** | 66 MB | war-room-server | Dashboard UI |
| 59 | `ecosystem-guardian` | AIOPS | AIOPS | **OK** | 70 MB | Autoheal, healthchecks | Self-healing orchestrator |
| 60 | `voice-outreach-service` | AIOPS | AIOPS | **OK** | 53 MB | voice-agent-svc | Outreach automation |
| 61 | `backup-verification` | AIOPS | AIOPS | **STOPPED** | 0 MB | PostgreSQL, MinIO | Restore-tests backups weekly |

### 3.5 Services NOT YET Deployed (but in infra-map target)

| # | Service | Target Server | Status | Priority | Dependencies |
|---|---------|---------------|--------|----------|-------------|
| 62 | `qdrant` | COREDB | **NOT DEPLOYED** | PHASE 1 | AI agent services on AIOPS (RAG) |
| 63 | `pgbouncer` | COREDB | **NOT DEPLOYED** | PHASE 2 | wheeler-postgres |
| 64 | `pgbackrest` | COREDB | **NOT DEPLOYED** | PHASE 2 | wheeler-postgres, wheeler-minio |
| 65 | `traefik-internal` | AIOPS | **NOT DEPLOYED** | PHASE 3 | traefik-edge (upstream) |
| 66 | `nats` | AIOPS | **NOT DEPLOYED** | PHASE 3 | None |
| 67 | `rabbitmq` | AIOPS | **NOT DEPLOYED** | PHASE 4 | None |
| 68 | `alertmanager` | AIOPS | **NOT DEPLOYED** | PHASE 3 | prometheus |
| 69 | `spiderfoot` | AIOPS | **NOT DEPLOYED** | PHASE 5 | None |
| 70 | `browser-automation` | AIOPS | **NOT DEPLOYED** | PHASE 5 | None |
| 71 | `nginx-static` | EDGE | **NOT DEPLOYED** | PHASE 4 | traefik-edge |

---

## 4. Dependency Graphs

### 4.1 EDGE Services Dependency Chain

```
                                traefik-edge (stay)
                                     |
              ┌──────────────────────┼──────────────────────┐
              |                      |                      |
    private-ai-webui         usesend (app)         prediction-radar-*
    (→ AIOPS, CRITICAL)          |                 (scheduler, worker)
              |                  |                 (→ AIOPS, CRITICAL)
         LiteLLM (AIOPS)    ┌────┼────┐                  |
                            |    |    |         prediction-radar-db (AIOPS)
                     usesend-redis | usesend-    prediction-radar-redis (AIOPS)
                     (→ COREDB)    | storage     prediction-radar-api (AIOPS)
                                   | (→ COREDB)
                            shared-postgres-
                            recovery (→ COREDB)
                                   |
                            shared-postgres-
                            exporter (→ COREDB)

    temporal-server ── temporal-temporal-1 ── temporal-ui-1
    (→ AIOPS, all three move as a unit)
```

**EDGE Migration Order (dependency-respecting):**

```
Wave 1 (independent, can be parallel):
  ├── private-ai-webui → AIOPS  [depends on: LiteLLM (already on AIOPS)]
  └── temporal-* (all 3) → AIOPS  [depends on: PostgreSQL for temporal DB]

Wave 2 (usesend stack, must be sequential):
  ├── 2a. shared-postgres-recovery → COREDB  [depends on: wheeler-postgres ready on COREDB]
  ├── 2b. usesend-redis → COREDB  [depends on: wheeler-redis ready on COREDB]
  ├── 2c. usesend-storage → COREDB  [depends on: wheeler-minio ready on COREDB]
  ├── 2d. shared-postgres-exporter → COREDB  [depends on: shared-postgres-recovery moved]
  └── 2e. usesend → AIOPS  [depends on: all dependencies (a-d) completed, DNS updated]

Wave 3 (prediction-radar workers):
  ├── 3a. Stop prediction-radar-app-scheduler on EDGE
  ├── 3b. Stop prediction-radar-app-worker on EDGE
  ├── 3c. Deploy prediction-radar-app-scheduler on AIOPS
  └── 3d. Deploy prediction-radar-app-worker on AIOPS
```

### 4.2 AIOPS Database Migration Dependency Chain

These warnings involve moving primary databases from AIOPS to COREDB. Each is a carefully sequenced migration with app downtime.

```
COREDB: wheeler-postgres (existing, running)
             |
    ┌────────┼────────┬──────────────┬──────────────┐
    |        |        |              |              |
pred-radar  ravynai  frgops-standby superset?      docuseal?
   DB        DB         DB          clickhouse?      DB
    |        |        |              |              |
pred-api  ravynai  frgcrm-api     superset       docuseal
pred-web  app      frgcrm-agent   grafana
pred-db   LiteLLM

COREDB: wheeler-redis (existing, running)
             |
    ┌────────┼────────┐
    |        |        |
pred-radar  ravynai  docuseal
  redis     redis     redis
    |        |        |
pred-api  ravynai  docuseal
pred-wrk  app
```

### 4.3 COREDB Monitoring Migration Dependency Chain

```
COREDB currently hosts:
  wheeler-prometheus  ────► Move to AIOPS
  wheeler-grafana     ────► Move to AIOPS (depends on prometheus target being updated)
  wheeler-loki        ────► Move to AIOPS (promtail targets updated)
  wheeler-uptime-kuma ────► Move to AIOPS (independent)

Migration order:
  1. Set up prometheus/grafana/loki on AIOPS (they already have aiops-grafana, aiops-prometheus, loki)
  2. Update promtail targets on all servers to point to AIOPS Loki (or keep existing)
  3. Merge COREDB prometheus scrape configs into AIOPS prometheus
  4. Decommission COREDB monitoring containers
```

**Note:** AIOPS already has `aiops-prometheus`, `aiops-grafana`, and `loki` running. The COREDB copies (`wheeler-prometheus`, `wheeler-grafana`, `wheeler-loki`, `wheeler-uptime-kuma`) are **duplicate** monitoring stacks. Migration means merging their configs into the AIOPS instances, then removing the COREDB copies.

---

## 5. Priority-Ordered Migration Plan

### Phase 0: PRE-FLIGHT (before any migration) — COMPLETE

- [x] Live audit of all three servers
- [x] Document current state in this execution board
- [ ] **Backup everything** — all databases, all volumes, all configs on all three servers
- [ ] Verify backups are restorable (smoke test on COREDB spare capacity)
- [ ] Snapshot Docker volumes that will be migrated
- [ ] Notify stakeholders of migration window

### Phase 1: CRITICAL FIXES (today, ~4 hours downtime window)

**Goal:** Eliminate all 5 CRITICAL violations. Zero databases, AI, or workers on EDGE.

| Step | Action | Server | Downtime | Rollback |
|------|--------|--------|----------|----------|
| 1.1 | **Backup** shared-postgres-recovery (pg_dumpall) | EDGE | 0 | N/A |
| 1.2 | **Backup** usesend-redis (BGSAVE to AOF) | EDGE | 0 | N/A |
| 1.3 | **Backup** usesend-storage (mc mirror to COREDB MinIO) | EDGE | 0 | N/A |
| 1.4 | **Stop** private-ai-webui container | EDGE | ~30s | `docker start private-ai-webui` |
| 1.5 | **Deploy** private-ai-webui on AIOPS via docker compose | AIOPS | 0 | `docker compose down` |
| 1.6 | **Verify** private-ai-webui works on AIOPS via Tailscale | AIOPS | 0 | Revert DNS |
| 1.7 | **Update** DNS/traefik route for private-ai-webui → AIOPS | EDGE | 0 | Revert config |
| 1.8 | **Stop** prediction-radar-app-scheduler on EDGE | EDGE | ~30s | `docker start` |
| 1.9 | **Stop** prediction-radar-app-worker on EDGE | EDGE | ~30s | `docker start` |
| 1.10 | **Deploy** scheduler + worker on AIOPS (add to prediction-radar compose) | AIOPS | 0 | Remove from compose |
| 1.11 | **Restore** shared-postgres-recovery data into COREDB wheeler-postgres | COREDB | ~10min | Drop restored DB |
| 1.12 | **Restore** usesend-redis data into COREDB wheeler-redis | COREDB | ~5min | FLUSHDB |
| 1.13 | **Restore** usesend-storage into COREDB wheeler-minio | COREDB | ~15min | Delete bucket |
| 1.14 | **Update** usesend config to point to COREDB (PG, Redis, MinIO) | EDGE→AIOPS | ~5min | Revert env vars |
| 1.15 | **Deploy** usesend on AIOPS with updated config | AIOPS | ~2min | `docker compose down` |
| 1.16 | **Update** DNS/traefik for usesend → AIOPS | EDGE | 0 | Revert config |
| 1.17 | **Stop** usesend, usesend-redis, usesend-storage, shared-postgres-recovery on EDGE | EDGE | 0 | `docker start` |
| 1.18 | **Verify** all 5 CRITICAL violations cleared | ALL | 0 | Re-run audit |

**Phase 1 success criteria:** `enforce-roles.sh` reports 0 CRITICAL violations on EDGE.

### Phase 2: COREDB BUILD-OUT (week 1, no downtime)

**Goal:** Deploy missing services on COREDB. Prepare it to absorb AIOPS databases.

| Step | Action | Downtime |
|------|--------|----------|
| 2.1 | Deploy Qdrant on COREDB (docker compose) | 0 |
| 2.2 | Deploy pgBouncer on COREDB (port 6432, Tailscale only) | 0 |
| 2.3 | Deploy pgBackRest on COREDB for wheeler-postgres | 0 |
| 2.4 | Configure WAL archiving to wheeler-minio | 0 |
| 2.5 | Create databases/schemas on wheeler-postgres for all services to be migrated: `prediction_radar`, `ravynai`, `frgops`, `docuseal` | 0 |
| 2.6 | Create Redis logical databases or key prefixes for each service | 0 |
| 2.7 | Create MinIO buckets: `prediction-radar`, `ravynai`, `frgops`, `docuseal`, `backups`, `uploads` | 0 |
| 2.8 | Test connectivity: AIOPS → COREDB (PG:5432, Redis:6379, MinIO:9000, Qdrant:6333) via Tailscale | 0 |

### Phase 3: COREDB MONITORING CLEANUP (week 1, no downtime)

**Goal:** Eliminate dashboard/monitoring servers from COREDB.

| Step | Action | Downtime |
|------|--------|----------|
| 3.1 | Merge wheeler-prometheus scrape configs into aiops-prometheus on AIOPS | 0 |
| 3.2 | Verify aiops-prometheus scrapes all COREDB exporters (node, postgres, redis, minio) | 0 |
| 3.3 | Point wheeler-grafana datasources to aiops-prometheus and AIOPS loki | 0 |
| 3.4 | Export wheeler-grafana dashboards → import into aiops-grafana | 0 |
| 3.5 | Export wheeler-uptime-kuma monitors → import into AIOPS uptime-kuma | 0 |
| 3.6 | Stop + disable: wheeler-prometheus, wheeler-grafana, wheeler-loki, wheeler-uptime-kuma on COREDB | 0 |
| 3.7 | Verify AIOPS monitoring stack fully functional for all three servers | 0 |

### Phase 4: AIOPS DATABASE MIGRATION (week 2, per-service 15-30min downtime)

**Goal:** Move all primary databases from AIOPS to COREDB. This is the largest and riskiest phase.

**Migration pattern (repeat for each DB):**
1. Announce downtime window (15-30 min per database)
2. Stop dependent apps on AIOPS
3. pg_dump the AIOPS database
4. Restore dump into COREDB wheeler-postgres (new database)
5. Update app connection strings to point to COREDB:5432
6. Start apps on AIOPS
7. Smoke test
8. If OK, drop old database on AIOPS

| # | Database | Size Est. | Downtime | Migrate After | Priority |
|---|----------|-----------|----------|---------------|----------|
| 4.1 | prediction-radar-app-db | ~20 GB | 30 min | Phase 2 complete | HIGH |
| 4.2 | prediction-radar-app-redis | ~2 GB | 5 min | Phase 2 complete | HIGH |
| 4.3 | aiops-ravynai-postgres | ~15 GB | 25 min | Phase 2 complete | MEDIUM |
| 4.4 | docuseal-redis | ~500 MB | 2 min | Phase 2 complete | MEDIUM |
| 4.5 | frgops-standby (Postgres) | ~10 GB | 20 min | Phase 2 complete | MEDIUM |
| 4.6 | aiops-clickhouse | ~30 GB | 45 min | Phase 2 complete | LOW (complex) |

### Phase 5: COMPLETION & VERIFICATION (week 3, no downtime)

| Step | Action |
|------|--------|
| 5.1 | Run `enforce-roles.sh --report` on all three servers |
| 5.2 | Verify 0 CRITICAL, 0 WARNING violations |
| 5.3 | Decommission old volumes on EDGE and AIOPS (after 7-day safety period) |
| 5.4 | Deploy nginx-static on EDGE for frontend assets |
| 5.5 | Deploy alertmanager on AIOPS |
| 5.6 | Update infra-map.md with post-migration state |
| 5.7 | Schedule follow-up audit (weekly) |

---

## 6. Per-Service Migration Notes

### 6.1 private-ai-webui (Open WebUI) — CRITICAL

**Current:** EDGE server, Docker container. 44% memory utilization of 1.5GB container limit. Dependent on LiteLLM (PM2 on AIOPS).

**Target:** AIOPS server, behind Tailscale.

**Risks:**
- Container is using 44% of its memory allocation — indicates active usage
- May have user sessions/conversations that need to be preserved
- DEEPSEEK_API_KEY used inside the container — must verify no exposure

**Rollback:** `docker start private-ai-webui` on EDGE, revert Traefik route (DNS is wildcard, so no DNS change needed).

**Migration Steps:**
```bash
# 1. On EDGE: commit current state as image backup
docker commit private-ai-webui private-ai-webui:backup-$(date +%Y%m%d)
docker save private-ai-webui:backup-$(date +%Y%m%d) | gzip > /tmp/private-ai-webui-backup.tar.gz

# 2. Copy compose config to AIOPS
scp /path/to/docker-compose.yml aiops:/opt/private-ai-webui/

# 3. Stop on EDGE
docker stop private-ai-webui
docker rm private-ai-webui  # DON'T remove volume yet

# 4. Start on AIOPS
ssh aiops "cd /opt/private-ai-webui && docker compose up -d"

# 5. Update Traefik on EDGE to route to AIOPS:3000 via Tailscale
# Edit Traefik dynamic config, add backend: http://100.121.230.28:PORT

# 6. Verify
curl -H "Host: openwebui.wheeler.ai" https://localhost/health

# 7. After 72h verification, remove volume from EDGE
docker volume rm private-ai-webui_data  # (only if no issues)
```

---

### 6.2 prediction-radar-app-scheduler + prediction-radar-app-worker — CRITICAL

**Current:** EDGE server. Background forecast compute and scheduled jobs.

**Target:** AIOPS server, as part of the existing prediction-radar Docker compose stack.

**Risks:**
- Workers have direct database access — DB credentials exposed on EDGE
- Scheduler may have cron-like state that could cause duplicate runs during migration
- Workers may be in the middle of long-running forecast computations

**Pre-migration:**
```bash
# Check for running jobs on EDGE
docker logs --tail 50 prediction-radar-app-worker
docker logs --tail 50 prediction-radar-app-scheduler

# Wait for any active job to complete, or note job ID for resumption
```

**Migration Steps:**
```bash
# 1. Gracefully stop scheduler (let current jobs finish)
docker stop prediction-radar-app-scheduler

# 2. Stop worker
docker stop prediction-radar-app-worker

# 3. On AIOPS: add scheduler and worker services to prediction-radar compose file
# Use same image tags, same env vars (but update DB host to localhost or AIOPS IP)

# 4. Start on AIOPS
ssh aiops "cd /opt/prediction-radar && docker compose up -d scheduler worker"

# 5. Verify
docker logs --tail 20 prediction-radar-app-scheduler  # on AIOPS
docker logs --tail 20 prediction-radar-app-worker     # on AIOPS

# 6. Remove containers and images from EDGE
docker rm prediction-radar-app-scheduler prediction-radar-app-worker
```

---

### 6.3 usesend Stack Migration (usesend + usesend-redis + usesend-storage + shared-postgres-recovery)

**Current:** EDGE server. 4 containers comprising the Usesend application.

**Target:**
- usesend (app) → AIOPS
- usesend-redis → COREDB (wheeler-redis)
- usesend-storage (MinIO) → COREDB (wheeler-minio)
- shared-postgres-recovery → COREDB (wheeler-postgres)

**Risks:**
- Tight coupling between 4 services — must migrate in correct order
- Redis at 18% CPU indicates heavy usage — migration downtime will be noticeable
- Usesend may have pending deliveries/queued jobs in Redis that must be preserved

**Migration order:**
```
1. shared-postgres-recovery → COREDB (data first)
2. usesend-storage → COREDB (files second)
3. usesend-redis → COREDB (cache/queue third)
4. usesend app → AIOPS (compute last, after all data moved)
```

**PostgreSQL Migration:**
```bash
# On EDGE
docker exec shared-postgres-recovery pg_dumpall -U postgres > /tmp/usesend-pg-backup.sql
scp /tmp/usesend-pg-backup.sql coredb:/tmp/

# On COREDB
docker exec wheeler-postgres psql -U postgres -c "CREATE DATABASE usesend OWNER wheeler_admin;"
docker exec -i wheeler-postgres psql -U postgres -d usesend < /tmp/usesend-pg-backup.sql
```

**Redis Migration:**
```bash
# On EDGE
docker exec usesend-redis redis-cli BGSAVE
# Wait for save to complete
docker cp usesend-redis:/data/dump.rdb /tmp/usesend-redis-dump.rdb
scp /tmp/usesend-redis-dump.rdb coredb:/tmp/

# On COREDB: stop redis, replace dump.rdb, start redis
```

**MinIO Migration:**
```bash
# On EDGE
docker exec usesend-storage mc mirror usesend-storage/bucket coredb-minio/bucket
```

---

### 6.4 Temporal Stack Migration (temporal-server + temporal-temporal-1 + temporal-temporal-ui-1)

**Current:** EDGE server. 3 containers. Temporal server at 10% CPU.

**Target:** AIOPS server.

**Risk:** Low — Temporal is workflow orchestration, job state is in PostgreSQL. As long as the DB connection is maintained or DB is migrated with it.

**Migration Steps:**
```bash
# 1. Identify Temporal PostgreSQL database (may be on shared-postgres-recovery or separate)
# 2. If PostgreSQL is local to EDGE: migrate DB to COREDB first
# 3. Deploy Temporal server + worker + UI on AIOPS with DB pointing to COREDB
# 4. Stop EDGE Temporal containers
# 5. Verify Temporal UI accessible via Traefik → AIOPS route
```

---

### 6.5 COREDB Monitoring Cleanup

AIOP already has `aiops-prometheus`, `aiops-grafana`, `loki`, and `uptime-kuma` running. The COREDB copies are redundant.

**Steps:**
```bash
# 1. Export COREDB prometheus scrape configs
docker exec wheeler-prometheus cat /etc/prometheus/prometheus.yml > /tmp/coredb-prometheus.yml

# 2. Merge additional scrape targets into AIOPS prometheus config
# Add to aiops-prometheus scrape_configs

# 3. Export COREDB Grafana dashboards
# Use Grafana HTTP API to export JSON

# 4. Import into aiops-grafana

# 5. Export Uptime Kuma monitors
# Use Uptime Kuma settings export

# 6. Import into AIOPS uptime-kuma

# 7. Stop + disable on COREDB
docker stop wheeler-prometheus wheeler-grafana wheeler-loki wheeler-uptime-kuma
docker rm wheeler-prometheus wheeler-grafana wheeler-loki wheeler-uptime-kuma
```

---

## 7. Migration Summary Dashboard

### Violation Counts (Pre-Migration)

| Server | CRITICAL | WARNING | OK | Total Services |
|--------|----------|---------|-----|----------------|
| EDGE   | **5**    | 7       | 1   | 13 (12 Docker + Traefik) |
| AIOPS  | 0        | 7       | 37  | 44 (24 Docker + 17 PM2 + system) |
| COREDB | 0        | 4       | 3   | 7 |

### Target State (Post-Migration)

| Server | CRITICAL | WARNING | OK | Total Services |
|--------|----------|---------|-----|----------------|
| EDGE   | 0        | 0       | 3   | 3 (traefik, nginx-static, exporters) |
| AIOPS  | 0        | 0       | 55+ | All compute, monitoring, agents |
| COREDB | 0        | 0       | 12+ | All databases, storage, Qdrant, exporters only |

### Resource Impact of Migrations

| Migration | EDGE CPU Freed | EDGE RAM Freed | EDGE Disk Freed | AIOPS Impact |
|-----------|---------------|----------------|-----------------|--------------|
| private-ai-webui → AIOPS | ~1 vCPU | ~660 MB | ~5 GB | +660 MB RAM |
| prediction-radar workers → AIOPS | ~0.5 vCPU | ~512 MB | ~2 GB | +512 MB RAM |
| temporal-* → AIOPS | ~1.3 vCPU | ~1 GB | ~3 GB | +1 GB RAM |
| usesend stack → AIOPS/COREDB | ~2 vCPU (Redis 18%) | ~2 GB | ~20 GB | +1 GB RAM (+data to COREDB) |
| **Total EDGE freed** | **~4.8 vCPU** | **~4.2 GB** | **~30 GB** | **~3.5 GB RAM AIOPS** |
| **Total to COREDB** | — | — | — | **+30 GB disk, +2 GB RAM** |

AIOPS has 14.2 GB RAM available. The migrations will consume ~3.5 GB, leaving ~10.7 GB headroom — well within capacity.

COREDB has 29 GB RAM available and 332 GB disk free. The data migrations (~30 GB disk) will use ~10% of available disk — well within capacity.

---

## 8. Rollback & Safety

### Rollback Philosophy

Every migration must have a verified rollback path that can be executed within the downtime window. No migration proceeds without a tested rollback.

### Rollback Decision Matrix

| Scenario | Action |
|----------|--------|
| App fails to start on target server | Rollback: start on original server from backup |
| App starts but returns errors | 5-minute debug window, then rollback |
| App works but performance degraded | Monitor 1 hour; if >2x latency increase, rollback |
| All OK after 72 hours | Commit migration: remove old containers/volumes |

### Per-Migration Rollback Commands

```bash
# private-ai-webui rollback
ssh edge "docker start private-ai-webui"  # if container+volume preserved
# OR redeploy from backup:
ssh edge "docker load < /tmp/private-ai-webui-backup.tar.gz && docker compose -f /opt/private-ai-webui/docker-compose.yml up -d"

# prediction-radar workers rollback
ssh edge "docker start prediction-radar-app-scheduler prediction-radar-app-worker"
ssh aiops "docker stop prediction-radar-app-scheduler prediction-radar-app-worker"

# usesend rollback (complex — reverse all 4 migrations)
# 1. Start usesend-redis, usesend-storage, shared-postgres-recovery on EDGE
# 2. Start usesend app on EDGE
# 3. Revert Traefik routes
# 4. Stop usesend on AIOPS
```

---

## 9. Audit Commands

Run these on each server to verify current state matches this board.

```bash
# Full role compliance audit (run on each server)
bash /root/infrastructure/enterprise/phase9-server-roles/enforce-roles.sh --report

# Quick Docker container audit
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

# PM2 audit (AIOPS only)
pm2 jlist | jq '.[] | {name, status, memory: .monit.memory, cpu: .monit.cpu}'

# Port binding audit (any 0.0.0.0 violations)
ss -tlnp | grep -v '127.0.0.1\|100\.'

# Disk usage per Docker volume
docker system df -v

# Tailscale connectivity check
tailscale status | grep -v '^$'
```

---

## 10. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-05-23 | SRE Team | Initial execution board from live server audits |

**Next Review:** After Phase 1 completion, or 2026-05-26 (whichever comes first)
