# Wheeler Ecosystem — Revenue Infrastructure Cutover Plan
## 3-Server Split: Hostinger Edge / Hetzner AIOPS / Hetzner COREDB

> **Plan date:** 2026-05-23
> **Status:** DRAFT — no services stopped, no DNS changed, no configs overwritten
> **Source documents:** ARCHITECTURE.md, REVENUE_APP_INVENTORY.md, DOMAIN_ROUTING_MAP.md, API_READINESS_MATRIX.md
> **Readiness gate:** 6/24 services fully ready, 3 CRITICAL fixes required before cutover

---

## EXECUTIVE SUMMARY

This plan defines the controlled migration of Wheeler ecosystem services across a three-node architecture. The primary goal is database centralization onto the new COREDB node while preserving the Hostinger edge for public traffic termination and the AIOPS node for all application logic.

**Current state:** 24 services running across 2 nodes (Hostinger + AIOPS). 3 revenue-critical services are errored or stuck (FRGCRM API, SurplusAI Scraper Agent, Voice Agent Service). These MUST be repaired before any cutover begins.

**Target state:** Hostinger serves as pure edge (Traefik + SSL + static frontends), AIOPS runs all application compute and AI workloads, COREDB hosts all shared state (PostgreSQL, Redis, MinIO, monitoring storage, Langfuse, vector DBs).

**Estimated total downtime:** 15-30 minutes for revenue-critical services if all pre-cutover gates pass cleanly. Worst case with rollback: 45-60 minutes.

---

## 1. WHAT STAYS ON HOSTINGER (Edge Services — Never Move)

These services remain permanently on the Hostinger edge node (187.77.148.88). They provide public ingress, static hosting, and lightweight tools that benefit from low-latency public termination.

### 1.1 Public Traffic Termination (DO NOT MOVE)

| Service | Port | Domain(s) | Rationale |
|---------|------|-----------|-----------|
| **Traefik Reverse Proxy** | 80, 443 | All public domains | Public TLS termination is the edge node's primary function. Moving Traefik would require DNS changes — explicitly forbidden. |
| **Cloudflare DNS / WAF** | N/A | All public domains | Orange-cloud proxy provides DDoS protection. Unchanged. |

### 1.2 Hostinger-Local Frontend Apps (DO NOT MOVE)

| Service | Port | Public Domain | Rationale |
|---------|------|---------------|-----------|
| **FRGops / FRGCRM Frontend** | 3000 | frgops.fundsrecoverygroup.tech | Primary CRM UI. Connect to FRGCRM API via Tailscale. |
| **FRGCRM Main Site** | 3000 | fundsrecoverygroup.com | Public brand website + lead intake. |
| **Wheeler Brain OS Dashboard** | 3000 | wheeler.frgop.io | Operations dashboard. API already routes to AIOPS via Tailscale. |

### 1.3 Hostinger-Local Tooling (DO NOT MOVE)

| Service | Port | Public Domain | Rationale |
|---------|------|---------------|-----------|
| **Chatwoot** | 3000 (internal) | chatwoot.wheeler.ai | Customer messaging. Low resource, benefits from edge proximity. |
| **n8n Workflows** | 5678 | n8n.wheeler.ai | Automation workflows. May interact with both nodes. |
| **LiteLLM Proxy** | 4000 | litellm.wheeler.ai | AI API proxy. All AI provider keys (DeepSeek, OpenAI, Anthropic) are configured here. Moving would require re-issuing keys. |
| **Webhook Receiver** | 9000 | N/A (internal) | Webhook ingestion endpoint. Must stay at the public edge for low-latency webhook processing. Stripe webhooks especially time-sensitive. |
| **MinIO Console** | 9001 | N/A (internal) | Object storage admin. MinIO data will be migrated to COREDB, but the console instance on Hostinger remains for admin access. |

### 1.4 Hostinger-Local Databases (RETAIN — Do Not Centralize)

| Database | Port | Purpose | Rationale |
|----------|------|---------|-----------|
| **Hostinger PostgreSQL** | 5432 | Chatwoot, n8n, FRGops frontend session state | These tools are tightly coupled to the Hostinger docker-compose stack. Migration would break the compose lifecycle. |
| **Hostinger Redis** | 6379 | Chatwoot cache, n8n queue, frontend sessions | Same tight coupling as PG. Low risk to keep local. |

> **Rule:** Hostinger-local PG and Redis stay as-is. COREDB is for services that already live on or will move to Hetzner.

---

## 2. WHAT MOVES TO AIOPS (Services Transitioning)

These services are already on AIOPS or target AIOPS as their permanent home. The "move" is primarily about redirecting their database/storage connections to COREDB.

### 2.1 Already on AIOPS — Database Connection Redirect Only

These services already run on Hetzner AIOPS (5.78.140.118). The cutover is changing their PostgreSQL and Redis connection strings from local Docker containers to the COREDB node (5.78.210.123).

| # | Service | Type | Current DB | Target DB on COREDB | Migration Action |
|---|---------|------|-----------|---------------------|------------------|
| 1 | **Prediction Radar API** | Docker | prediction-radar-app-db (local PG16 :5432) | COREDB PostgreSQL :5432 | Update DATABASE_URL env var, run migration, restart container |
| 2 | **Prediction Radar Worker** | Docker | Same PG | COREDB PostgreSQL :5432 | Shares DB config with API — updated atomically |
| 3 | **Prediction Radar Scheduler** | Docker | Same PG | COREDB PostgreSQL :5432 | Shares DB config with API — updated atomically |
| 4 | **Prediction Radar Dashboard v2** | Docker | Same PG | COREDB PostgreSQL :5432 | Shares DB config with API — updated atomically |
| 5 | **Prediction Radar Redis** | Docker | prediction-radar-app-redis (local :6379) | COREDB Redis :6379 | Update REDIS_URL env var, restart containers |
| 6 | **RavynAI API** | Docker | aiops-ravynai-postgres (local PG16 :5434) | COREDB PostgreSQL :5434 (new DB) | Create DB on COREDB, update DATABASE_URL, run migration, restart |
| 7 | **FRGCRM Agent Service** | PM2 | frgops-standby (local PG16 :5433) | COREDB PostgreSQL :5433 (new DB) | Create DB on COREDB, update env, `pm2 restart` |
| 8 | **FRGCRM Mirror Test** | PM2 | frgops-standby (local PG16 :5433) | COREDB PostgreSQL :5433 | Shares DB config with Agent Service |
| 9 | **FRGCRM API** | PM2 | frgops-standby (local PG16 :5433) | COREDB PostgreSQL :5433 | **MUST BE FIXED FIRST.** Then update DB config |
| 10 | **SurplusAI Scraper Agent** | PM2 | N/A (local/embedded) | COREDB PostgreSQL (new DB) | **MUST BE FIXED FIRST.** Provision DB, update config |
| 11 | **Voice Agent Service** | PM2 | N/A (local/embedded) | COREDB PostgreSQL (new DB) | **MUST BE FIXED FIRST.** Provision DB, update config |

### 2.2 Services That Currently Live on Hostinger but BELONG on AIOPS

| Service | Current Location | Current DB | Target Location | Reasoning |
|---------|-----------------|------------|-----------------|-----------|
| **LiteLLM Proxy** | Hostinger :4000 | N/A (proxy) | **Debated** — Keep on Hostinger for low-latency AI provider calls. Only move if COREDB adds latency. | LiteLLM is a stateless proxy. Moving it to AIOPS reduces Hostinger CPU load but adds one Tailscale hop for every AI call from Hostinger services. **Recommendation: KEEP on Hostinger for Phase 1.** |
| **MinIO Object Store** | Hostinger :9001 | N/A (local disk) | COREDB MinIO | Move object storage to COREDB for unified backup strategy. Hostinger MinIO console remains as admin interface pointing to COREDB. |
| **Docuseal** | Hostinger → Hetzner :3010 | docuseal-redis | COREDB Redis | Already routes through Tailscale. Move Redis to COREDB. |

> **Decision gate:** LiteLLM location is a performance vs. centralization tradeoff. Defer to Phase 2 unless COREDB latency proves negligible in benchmark.

### 2.3 Services That Stay on AIOPS with NO Database Change

| Service | Rationale |
|---------|-----------|
| **Insforge Agent Service** (PM2) | No database dependency. Internal agent logic only. |
| **Spiderfoot** (Docker) | OSINT tool. Local SQLite. No shared state. |
| **Langflow** (Docker) | AI workflow builder. Local SQLite. Low priority to centralize. |
| **ClickHouse** (Docker) | Analytics column store. May move to COREDB in Phase 2 as dedicated analytics DB. For now, keep on AIOPS to avoid cross-node latency on dashboard queries. |
| **Grafana** (Docker) | Monitoring dashboards. Stateless or embedded SQLite. Keep on AIOPS for dashboard performance. |
| **Superset** (Docker) | BI tool. Uses ClickHouse. Keep with ClickHouse on AIOPS. |
| **Uptime Kuma** (Docker) | External monitoring. Local SQLite. Keep on AIOPS. |
| **ChangeDetection** (Docker) | Page monitoring. Local SQLite. Keep on AIOPS. |
| **Healthchecks** (Docker) | Cron monitoring. Local SQLite. Keep on AIOPS. |
| **Netdata** (Docker) | System monitoring. Local storage. Keep on AIOPS. |
| **Prometheus** (Docker) | Metrics collection. Keep on AIOPS. Metrics remote-write to COREDB for long-term storage (Phase 2). |
| **Portainer** (Docker) | Container management. Keep on AIOPS. |
| **Dockge** (Docker) | Compose stack management. Keep on AIOPS. |
| **1Panel** (System) | Server management panel. Keep on AIOPS. |

---

## 3. WHAT CONNECTS TO COREDB (New Database Dependencies)

The COREDB node (5.78.210.123) is the new shared-state layer. It hosts PostgreSQL, Redis, MinIO, backup storage, Langfuse, and vector databases.

### 3.1 COREDB Services to Provision

| Service | Port | Purpose | Provisioning Command |
|---------|------|---------|---------------------|
| **PostgreSQL 16** | 5432 | Primary application database — Prediction Radar, FRGCRM, RavynAI, SurplusAI, Voice Agent | `docker compose up -d postgres` (core stack) |
| **Redis 7** | 6379 | Cache, queues, sessions — Prediction Radar, Docuseal, FRGCRM | `docker compose up -d redis` (core stack) |
| **MinIO** | 9000 (API), 9001 (Console) | Unified object storage — backups, file uploads, document storage | `docker compose up -d minio` (core stack) |
| **Langfuse** | 3000 | LLM observability — traces, evals, cost tracking for all AI services | `docker compose up -d langfuse` |
| **Vector DB (pgvector/chroma/qdrant)** | TBD | AI embeddings store — Wheeler Brain OS, RavynAI RAG | Provision as needed (Phase 2) |
| **Backup Service (pg_dump + restic)** | N/A | Automated PostgreSQL + volume backups to MinIO + offsite | Cron job on COREDB |
| **Monitoring Storage (Prometheus long-term)** | 9090 | Prometheus remote-write target for long-term metrics retention | Phase 2 |
| **PostgreSQL 16 (frgops)** | 5433 | Dedicated DB for FRGCRM services | `CREATE DATABASE frgops ON postgres:5433` |
| **PostgreSQL 16 (ravynai)** | 5434 | Dedicated DB for RavynAI | `CREATE DATABASE ravynai ON postgres:5434` |
| **PostgreSQL 16 (surplusai)** | 5435 | Dedicated DB for SurplusAI | `CREATE DATABASE surplusai ON postgres:5435` |
| **PostgreSQL 16 (voiceagent)** | 5436 | Dedicated DB for Voice Agent | `CREATE DATABASE voiceagent ON postgres:5436` |

### 3.2 Connection Matrix — Service to COREDB

```
PREDICTION RADAR (4 containers)
  ├── PostgreSQL ───► COREDB :5432/prediction_radar
  └── Redis      ───► COREDB :6379 (db 0)

RAVYNAI (2 containers)
  ├── PostgreSQL ───► COREDB :5434/ravynai
  └── (no Redis)

FRGCRM SUITE (3 PM2 processes)
  ├── PostgreSQL ───► COREDB :5433/frgops
  └── (no Redis)

SURPLUSAI AGENT (1 PM2 process)
  └── PostgreSQL ───► COREDB :5435/surplusai

VOICE AGENT (1 PM2 process)
  └── PostgreSQL ───► COREDB :5436/voiceagent

DOCUSEAL (1 container)
  └── Redis      ───► COREDB :6379 (db 1)

MINIO (shared)
  └── S3 API     ───► COREDB :9000

ALL AI SERVICES (Prediction Radar, RavynAI, Langflow)
  └── Langfuse   ───► COREDB :3000 (LLM traces)
```

### 3.3 Tailscale Mesh Verification — COREDB

```
AIOPS (100.121.x.x) ──── Tailscale ────► COREDB (100.x.x.x) :5432 :6379 :9000
HOSTINGER (100.98.x.x) ──── Tailscale ────► COREDB (100.x.x.x) :5432 :6379 :9000
```

> **Validation:** Before any database migration, verify that both AIOPS and Hostinger can reach COREDB PostgreSQL and Redis over the Tailscale mesh. COREDB must be joined to the same Tailscale tailnet.

---

## 4. EXACT CUTOVER ORDER (Numbered Sequence with Dependencies)

The cutover is organized into 5 phases. Each phase must pass its validation gate before Phase N+1 begins. No phase may be skipped or reordered.

### PHASE 0: PRE-FLIGHT REPAIRS (NO CUTOVER — Production Safe)

> **Constraint:** These repairs MUST be completed on the current AIOPS node BEFORE any database migration. They are safe to perform at any time and do not affect the cutover window.

#### Step 0.1: Fix FRGCRM API (PM2 id 6 — ERROred, 15 restarts)

```bash
# On AIOPS (5.78.140.118):
# 1. Inspect error logs
pm2 logs frgcrm-api --lines 100 --nostream

# 2. Check port conflict (8013 shared with frgcrm-agent-svc and insforge-agent-svc?)
netstat -tlnp | grep 8013
ss -tlnp | grep 8013

# 3. Check database connectivity
pg_isready -h localhost -p 5433 -U frgops  # frgops-standby

# 4. Check env vars
pm2 env 6  # PM2 id 6 = frgcrm-api

# 5. Manual start with verbose logging
pm2 start frgcrm-api --node-args="--trace-warnings" --time

# 6. Verify health
curl -s http://localhost:<port>/health

# 7. Save state
pm2 save
```

**Dependency:** None. Safe to fix at any time.
**Success criteria:** `pm2 status` shows `online` for frgcrm-api. Health endpoint responds 200.

#### Step 0.2: Fix SurplusAI Scraper Agent (PM2 id 1 — WAITING, 282 restarts)

```bash
# On AIOPS:
# 1. Inspect error logs
pm2 logs surplusai-scraper-agent-svc --lines 100 --nostream

# 2. Check what it's waiting on
pm2 show surplusai-scraper-agent-svc

# 3. Identify blocking dependency (likely FRGCRM API or DB)
pm2 env 1

# 4. Fix dependency, then restart
pm2 restart surplusai-scraper-agent-svc --update-env

# 5. Verify stable (no restart loop for 2+ minutes)
pm2 status
pm2 save
```

**Dependency:** May depend on Step 0.1 (FRGCRM API) being fixed.
**Success criteria:** `pm2 status` shows `online` for surplusai-scraper-agent-svc. Restart count stops incrementing.

#### Step 0.3: Fix Voice Agent Service (PM2 id 2 — WAITING, 282 restarts)

```bash
# On AIOPS:
# 1. Inspect error logs
pm2 logs voice-agent-svc --lines 100 --nostream

# 2. Check OpenClaw gateway connectivity
curl -s http://localhost:<openclaw-port>/health  # via Prediction Radar

# 3. Check external voice provider API reachability
# (provider-specific — Twilio, Vonage, etc.)

# 4. Fix and restart
pm2 restart voice-agent-svc --update-env

# 5. Verify stable
pm2 status
pm2 save
```

**Dependency:** May depend on OpenClaw gateway (embedded in Prediction Radar).
**Success criteria:** `pm2 status` shows `online` for voice-agent-svc. Restart count stops incrementing.

#### Step 0.4: Verify Stripe Production Mode

```bash
# On AIOPS:
# Check Prediction Radar Stripe keys
docker exec prediction-radar-app-web env | grep STRIPE

# Verify: STRIPE_SECRET_KEY should be sk_live_* (NOT sk_test_*)
# Verify: STRIPE_PUBLISHABLE_KEY should be pk_live_* (NOT pk_test_*)

# If test keys are in use, determine if intentional:
# - Intentional: document reason, proceed with test mode
# - Unintentional: rotate to live keys BEFORE database migration
```

**Dependency:** None. Safe to verify at any time.
**Success criteria:** Stripe key mode confirmed and documented. Decision recorded: live mode or (documented) test mode.

#### Step 0.5: Verify COREDB Node Initial State

```bash
# Verify COREDB (5.78.210.123) is reachable
ping -c 3 5.78.210.123

# Verify SSH access
ssh root@5.78.210.123 "uptime && df -h / && free -h"

# Verify Tailscale is installed and joined to tailnet
ssh root@5.78.210.123 "tailscale status"

# Note COREDB Tailscale IP
ssh root@5.78.210.123 "tailscale ip -4"
# Record result: COREDB_TAILSCALE_IP=<result>
```

**Dependency:** None. Safe at any time.
**Success criteria:** COREDB reachable via public IP and Tailscale. SSH works. Disk and memory adequate.

---

### PHASE 1: COREDB INFRASTRUCTURE PROVISIONING (No Production Impact)

> **Constraint:** This phase provisions databases on COREDB without touching any production services. No downtime.

#### Step 1.1: Deploy PostgreSQL 16 on COREDB

```bash
# On COREDB (5.78.210.123):
mkdir -p /opt/coredb/postgres/data
mkdir -p /opt/coredb/postgres/backups

# Deploy PostgreSQL via Docker Compose
cat > /opt/coredb/docker-compose.yml << 'COMPOSE'
version: "3.8"
services:
  postgres:
    image: postgres:16-alpine
    container_name: coredb-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: <GENERATE_STRONG_PASSWORD>
    ports:
      - "0.0.0.0:5432:5432"  # Bind to Tailscale IP in production
    volumes:
      - /opt/coredb/postgres/data:/var/lib/postgresql/data
      - /opt/coredb/postgres/backups:/backups
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: coredb-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --requirepass <GENERATE_STRONG_PASSWORD>
    ports:
      - "0.0.0.0:6379:6379"
    volumes:
      - /opt/coredb/redis/data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  minio:
    image: minio/minio:latest
    container_name: coredb-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: <GENERATE_STRONG_PASSWORD>
    ports:
      - "0.0.0.0:9000:9000"
      - "0.0.0.0:9001:9001"
    volumes:
      - /opt/coredb/minio/data:/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  langfuse:
    image: ghcr.io/langfuse/langfuse:latest
    container_name: coredb-langfuse
    restart: unless-stopped
    ports:
      - "0.0.0.0:3030:3000"
    environment:
      DATABASE_URL: postgresql://admin:<PASSWORD>@coredb-postgres:5432/langfuse
      NEXTAUTH_SECRET: <GENERATE_STRONG_SECRET>
      SALT: <GENERATE_STRONG_SECRET>
    depends_on:
      postgres:
        condition: service_healthy

COMPOSE

docker compose -f /opt/coredb/docker-compose.yml up -d
```

**Success criteria:** All 4 containers show `healthy`. `pg_isready`, `redis-cli ping`, `curl minio/health/live` all pass.

#### Step 1.2: Create Application Databases on COREDB

```bash
# On COREDB:
docker exec coredb-postgres psql -U admin -c "CREATE DATABASE prediction_radar;"
docker exec coredb-postgres psql -U admin -c "CREATE DATABASE frgops;"
docker exec coredb-postgres psql -U admin -c "CREATE DATABASE ravynai;"
docker exec coredb-postgres psql -U admin -c "CREATE DATABASE surplusai;"
docker exec coredb-postgres psql -U admin -c "CREATE DATABASE voiceagent;"
docker exec coredb-postgres psql -U admin -c "CREATE DATABASE langfuse;"

# Verify
docker exec coredb-postgres psql -U admin -c "\l"
```

#### Step 1.3: Configure Tailscale Firewall on COREDB

```bash
# On COREDB:
# Restrict PostgreSQL and Redis to Tailscale interface only
# Using iptables or nftables:

# Block external access to PostgreSQL
iptables -A INPUT -p tcp --dport 5432 -i eth0 -j DROP
iptables -A INPUT -p tcp --dport 5432 -i tailscale0 -j ACCEPT

# Block external access to Redis
iptables -A INPUT -p tcp --dport 6379 -i eth0 -j DROP
iptables -A INPUT -p tcp --dport 6379 -i tailscale0 -j ACCEPT

# Block external access to MinIO S3 API
iptables -A INPUT -p tcp --dport 9000 -i eth0 -j DROP
iptables -A INPUT -p tcp --dport 9000 -i tailscale0 -j ACCEPT

# Save rules
iptables-save > /etc/iptables/rules.v4  # Debian/Ubuntu
```

> **Security:** PostgreSQL and Redis MUST NOT be accessible from the public internet. Only Tailscale mesh access.

#### Step 1.4: Verify Cross-Node COREDB Connectivity

```bash
# On AIOPS (5.78.140.118):
# Verify PostgreSQL
psql -h <COREDB_TAILSCALE_IP> -p 5432 -U admin -d prediction_radar -c "SELECT 1;"

# Verify Redis
redis-cli -h <COREDB_TAILSCALE_IP> -p 6379 -a <PASSWORD> PING

# On Hostinger (187.77.148.88):
# Verify PostgreSQL
psql -h <COREDB_TAILSCALE_IP> -p 5432 -U admin -d postgres -c "SELECT 1;"

# Verify Redis
redis-cli -h <COREDB_TAILSCALE_IP> -p 6379 -a <PASSWORD> PING
```

**Success criteria:** Both AIOPS and Hostinger can connect to COREDB PostgreSQL and Redis over Tailscale.

---

### PHASE 2: NON-REVENUE DATABASE MIGRATION (Low Risk — Monitoring/Support Services)

> **Constraint:** This phase migrates databases for non-revenue services first. If anything breaks, revenue is unaffected. Provides confidence for Phase 3.

#### Step 2.1: Migrate Docuseal Redis to COREDB

```bash
# On AIOPS:
# 1. Verify current Docuseal Redis state (no critical data, primarily sessions)
docker exec docuseal-redis redis-cli DBSIZE

# 2. Update Docuseal docker-compose env:
#    Change REDIS_URL from redis://docuseal-redis:6379
#    To:           redis://:<PASSWORD>@<COREDB_TAILSCALE_IP>:6379/1

# 3. Restart Docuseal
docker compose --project-name docuseal down
docker compose --project-name docuseal up -d

# 4. Verify
docker compose --project-name docuseal ps
curl -s http://localhost:3010/health
curl -I https://docuseal.wheeler.ai
```

**Rollback:** Restore original REDIS_URL, restart.
**Downtime:** < 1 minute. Docuseal is document signing — low traffic.
**Revenue impact:** None.

#### Step 2.2: Configure Langfuse on COREDB (New Service — No Migration)

```bash
# Langfuse is already deployed in Step 1.1.
# On each AI service, add Langfuse environment variables:

# Prediction Radar docker-compose:
#   LANGFUSE_HOST=http://<COREDB_TAILSCALE_IP>:3030
#   LANGFUSE_PUBLIC_KEY=<key>
#   LANGFUSE_SECRET_KEY=<key>

# RavynAI docker-compose:
#   LANGFUSE_HOST=http://<COREDB_TAILSCALE_IP>:3030
#   LANGFUSE_PUBLIC_KEY=<key>
#   LANGFUSE_SECRET_KEY=<key>

# Restart services after env update:
docker compose --project-name prediction-radar up -d
docker compose --project-name ravynai up -d
```

**Revenue impact:** None. Langfuse is observability, not critical path.
**Rollback:** Remove LANGFUSE_* env vars, restart.

---

### PHASE 3: REVENUE-CRITICAL DATABASE MIGRATION (Requires Downtime Window)

> **WARNING:** This phase involves stopping and restarting Prediction Radar (primary revenue service) and the FRGCRM suite. Schedule during lowest-traffic window. Estimated window: 15-30 minutes.

#### PRE-FLIGHT CHECKLIST (Phase 3 Gate)

Before starting any Phase 3 step, confirm:
- [ ] Phase 0: All 3 errored services are ONLINE and stable for 30+ minutes
- [ ] Phase 0: Stripe mode confirmed (live or documented test)
- [ ] Phase 1: COREDB PostgreSQL healthy, all 6 databases created
- [ ] Phase 1: COREDB Redis healthy
- [ ] Phase 1: Cross-node connectivity verified (both AIOPS and Hostinger)
- [ ] Phase 1: Tailscale mesh verified between all 3 nodes
- [ ] Phase 2: Docuseal migrated and healthy
- [ ] Current time is within scheduled maintenance window
- [ ] All team members notified — communication channel open

#### Step 3.1: Dump Prediction Radar Database from AIOPS

```bash
# On AIOPS:
# 1. Announce maintenance window START
# 2. Dump Prediction Radar PostgreSQL
docker exec prediction-radar-app-db pg_dump -U prediction_radar -d prediction_radar \
  --no-owner --no-acl --clean --if-exists \
  > /tmp/prediction_radar_$(date +%Y%m%d_%H%M%S).sql

# 3. Verify dump size (should be non-trivial)
ls -lh /tmp/prediction_radar_*.sql

# 4. Copy dump to COREDB
scp /tmp/prediction_radar_*.sql root@<COREDB_TAILSCALE_IP>:/tmp/
```

#### Step 3.2: Restore Prediction Radar Database to COREDB

```bash
# On COREDB:
# 1. Restore dump
docker exec -i coredb-postgres psql -U admin -d prediction_radar \
  < /tmp/prediction_radar_*.sql

# 2. Verify row counts match
docker exec coredb-postgres psql -U admin -d prediction_radar -c "
  SELECT schemaname, relname, n_live_tup
  FROM pg_stat_user_tables
  ORDER BY n_live_tup DESC;
"
# Compare with AIOPS source:
docker exec prediction-radar-app-db psql -U prediction_radar -d prediction_radar -c "
  SELECT schemaname, relname, n_live_tup
  FROM pg_stat_user_tables
  ORDER BY n_live_tup DESC;
"

# 3. Create application user with limited permissions
docker exec coredb-postgres psql -U admin -d prediction_radar -c "
  CREATE USER prediction_radar_app WITH PASSWORD '<GENERATE_STRONG_PASSWORD>';
  GRANT CONNECT ON DATABASE prediction_radar TO prediction_radar_app;
  GRANT USAGE ON SCHEMA public TO prediction_radar_app;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO prediction_radar_app;
  GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO prediction_radar_app;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO prediction_radar_app;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO prediction_radar_app;
"
```

#### Step 3.3: Switch Prediction Radar to COREDB

```bash
# On AIOPS:
# 1. Backup current docker-compose env configuration
cp /opt/prediction-radar/.env /opt/prediction-radar/.env.backup.$(date +%Y%m%d_%H%M%S)
cp /opt/prediction-radar/docker-compose.yml /opt/prediction-radar/docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)

# 2. Update DATABASE_URL in .env
#    OLD: postgresql://prediction_radar:<old_pass>@prediction-radar-app-db:5432/prediction_radar
#    NEW: postgresql://prediction_radar_app:<new_pass>@<COREDB_TAILSCALE_IP>:5432/prediction_radar

# 3. Update REDIS_URL in .env
#    OLD: redis://prediction-radar-app-redis:6379/0
#    NEW: redis://:<redis_pass>@<COREDB_TAILSCALE_IP>:6379/0

# 4. Stop Prediction Radar (DOWNTIME STARTS)
docker compose --project-name prediction-radar down

# 5. Start Prediction Radar with new config (DOWNTIME ENDS)
docker compose --project-name prediction-radar up -d

# 6. Wait for healthy state
sleep 10
docker compose --project-name prediction-radar ps
docker logs prediction-radar-app-web --tail 50

# 7. Verify health
curl -s http://localhost:8000/health
curl -s http://localhost:8098 | head -20  # Web frontend
curl -I https://predictionradar.app        # Public access
```

**Downtime:** ~2-5 minutes for Prediction Radar.
**Rollback:** Restore .env from backup, `docker compose down && docker compose up -d`.
**Revenue impact:** HIGH — Prediction Radar is the primary SaaS revenue generator.

#### Step 3.4: Migrate Prediction Radar Redis Data to COREDB

```bash
# Redis data migration (if Redis has persistent state beyond cache):
# Option A: No migration (Redis used as cache only — safe to start fresh)
# Option B: If Redis has persistent state (queues, sessions):

# On AIOPS:
# 1. Dump Redis
docker exec prediction-radar-app-redis redis-cli --rdb /tmp/dump.rdb SAVE
docker cp prediction-radar-app-redis:/tmp/dump.rdb /tmp/prediction_radar_redis_dump.rdb

# 2. Copy to COREDB
scp /tmp/prediction_radar_redis_dump.rdb root@<COREDB_TAILSCALE_IP>:/tmp/

# 3. On COREDB, restore
docker cp /tmp/prediction_radar_redis_dump.rdb coredb-redis:/data/dump.rdb
docker restart coredb-redis
```

> **Decision:** Confirm whether Prediction Radar Redis holds state or is cache-only. If cache-only, skip data migration — faster and safer.

#### Step 3.5: Migrate FRGCRM Database (frgops-standby → COREDB)

```bash
# On AIOPS:
# 1. Dump frgops-standby database
docker exec frgops-standby pg_dump -U frgops -d frgops \
  --no-owner --no-acl --clean --if-exists \
  > /tmp/frgops_$(date +%Y%m%d_%H%M%S).sql

# 2. Copy to COREDB
scp /tmp/frgops_*.sql root@<COREDB_TAILSCALE_IP>:/tmp/

# 3. On COREDB, restore
docker exec -i coredb-postgres psql -U admin -d frgops \
  < /tmp/frgops_*.sql

# 4. Create FRGCRM application user
docker exec coredb-postgres psql -U admin -d frgops -c "
  CREATE USER frgcrm_app WITH PASSWORD '<GENERATE_STRONG_PASSWORD>';
  GRANT CONNECT ON DATABASE frgops TO frgcrm_app;
  GRANT USAGE ON SCHEMA public TO frgcrm_app;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO frgcrm_app;
  GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO frgcrm_app;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO frgcrm_app;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO frgcrm_app;
"

# 5. On AIOPS, update FRGCRM PM2 environment:
pm2 stop frgcrm-agent-svc
pm2 stop frgcrm-api
pm2 stop frgcrm-mirror-test

# 6. Update DATABASE_URL for each PM2 process:
#    OLD: postgresql://frgops:<pass>@localhost:5433/frgops
#    NEW: postgresql://frgcrm_app:<pass>@<COREDB_TAILSCALE_IP>:5432/frgops
# (Update via PM2 ecosystem file or .env file used by the process)

# 7. Restart FRGCRM services
pm2 restart frgcrm-agent-svc --update-env
pm2 restart frgcrm-api --update-env
pm2 restart frgcrm-mirror-test --update-env

# 8. Verify
pm2 status
curl -s http://localhost:8013/health  # Agent
curl -s http://localhost:<frgcrm_api_port>/health  # API
curl -s http://localhost:8003/health  # Mirror test
curl -I https://frgops.fundsrecoverygroup.tech
```

**Downtime:** ~3-5 minutes for FRGCRM suite.
**Revenue impact:** MEDIUM — CRM offline briefly. Lead intake may queue on frontend.

#### Step 3.6: Migrate RavynAI Database

```bash
# On AIOPS:
# 1. Dump
docker exec aiops-ravynai-postgres pg_dump -U ravynai -d ravynai \
  --no-owner --no-acl --clean --if-exists \
  > /tmp/ravynai_$(date +%Y%m%d_%H%M%S).sql

# 2. Copy to COREDB, restore
scp /tmp/ravynai_*.sql root@<COREDB_TAILSCALE_IP>:/tmp/
ssh root@<COREDB_TAILSCALE_IP> "docker exec -i coredb-postgres psql -U admin -d ravynai < /tmp/ravynai_*.sql"

# 3. Create RavynAI user on COREDB
docker exec coredb-postgres psql -U admin -d ravynai -c "
  CREATE USER ravynai_app WITH PASSWORD '<GENERATE_STRONG_PASSWORD>';
  GRANT CONNECT ON DATABASE ravynai TO ravynai_app;
  GRANT USAGE ON SCHEMA public TO ravynai_app;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ravynai_app;
  GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO ravynai_app;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ravynai_app;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO ravynai_app;
"

# 4. Update RavynAI env and restart
cp /opt/ravynai/.env /opt/ravynai/.env.backup.$(date +%Y%m%d_%H%M%S)
# Update DATABASE_URL in .env
docker compose --project-name ravynai down
docker compose --project-name ravynai up -d

# 5. Verify
docker compose --project-name ravynai ps
curl -s http://localhost:8007/health
curl -I https://ravynai.wheeler.ai/health
```

**Downtime:** ~2-3 minutes.
**Revenue impact:** LOW-MEDIUM — RavynAI is a supporting AI service.

#### Step 3.7: Provision and Connect SurplusAI and Voice Agent Databases

```bash
# On COREDB:
# SurplusAI user
docker exec coredb-postgres psql -U admin -d surplusai -c "
  CREATE USER surplusai_app WITH PASSWORD '<GENERATE_STRONG_PASSWORD>';
  GRANT CONNECT ON DATABASE surplusai TO surplusai_app;
  GRANT ALL PRIVILEGES ON SCHEMA public TO surplusai_app;
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO surplusai_app;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO surplusai_app;
"

# Voice Agent user
docker exec coredb-postgres psql -U admin -d voiceagent -c "
  CREATE USER voiceagent_app WITH PASSWORD '<GENERATE_STRONG_PASSWORD>';
  GRANT CONNECT ON DATABASE voiceagent TO voiceagent_app;
  GRANT ALL PRIVILEGES ON SCHEMA public TO voiceagent_app;
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO voiceagent_app;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO voiceagent_app;
"

# On AIOPS, update PM2 env and restart:
pm2 restart surplusai-scraper-agent-svc --update-env
pm2 restart voice-agent-svc --update-env

# Verify stability
pm2 status
sleep 60
pm2 status  # Restart count should not increment
```

---

### PHASE 4: VERIFICATION AND STABILIZATION (Post-Migration)

#### Step 4.1: Full Health Check — All Revenue Services

```bash
# On AIOPS — Docker containers
docker compose --project-name prediction-radar ps    # All 4 healthy
docker compose --project-name ravynai ps             # All 2 healthy
docker compose --project-name docuseal ps            # Healthy

# On AIOPS — PM2 processes
pm2 status                                           # All online, 0 recent restarts

# On AIOPS — API health checks
curl -s http://localhost:8000/health                 # Prediction Radar API
curl -s http://localhost:8007/health                 # RavynAI API
curl -s http://localhost:8013/health                 # FRGCRM Agent
curl -s http://localhost:8003/health                 # FRGCRM Mirror Test
curl -s http://localhost:3010/health                 # Docuseal

# Public endpoint checks (from any machine with internet)
curl -o /dev/null -s -w "%{http_code}\n" https://predictionradar.app
curl -o /dev/null -s -w "%{http_code}\n" https://fundsrecoverygroup.com
curl -o /dev/null -s -w "%{http_code}\n" https://wheeler.frgop.io
curl -o /dev/null -s -w "%{http_code}\n" https://frgops.fundsrecoverygroup.tech
curl -o /dev/null -s -w "%{http_code}\n" https://ravynai.wheeler.ai/health
curl -o /dev/null -s -w "%{http_code}\n" https://surplusai.io
```

#### Step 4.2: Database Connectivity Audit

```bash
# On AIOPS — verify all services are hitting COREDB, not local DB
# Check Prediction Radar
docker logs prediction-radar-app-web 2>&1 | grep -i "database\|redis\|connection" | tail -20

# Check FRGCRM
pm2 logs frgcrm-agent-svc --lines 20 --nostream | grep -i "database\|connection"

# On COREDB — verify active connections
docker exec coredb-postgres psql -U admin -c "
  SELECT datname, count(*) as connections
  FROM pg_stat_activity
  WHERE state = 'active'
  GROUP BY datname;
"

docker exec coredb-redis redis-cli -a <PASSWORD> CLIENT LIST | wc -l
```

#### Step 4.3: Stripe Payment Verification

```bash
# Test Stripe webhook delivery
# 1. Trigger a test webhook from Stripe dashboard
# 2. Verify Prediction Radar received it:
docker logs prediction-radar-app-web 2>&1 | grep -i "stripe\|webhook" | tail -20

# 3. If in live mode, create a $1 test charge and refund immediately
#    (or verify a recent real transaction processed correctly)
```

#### Step 4.4: Monitor for 30 Minutes

```bash
# Watch for restarts
watch -n 30 'pm2 status && echo "---" && docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "prediction|ravynai|docuseal"'

# Watch COREDB resource usage
ssh root@<COREDB_TAILSCALE_IP> "docker stats --no-stream"

# Check for error spikes in logs
pm2 logs --lines 50 --nostream | grep -i "error\|fail\|timeout\|refused"
```

---

### PHASE 5: CLEANUP AND DE COMMISSIONING (Post-Stabilization — 48+ Hours After)

> **WAIT 48 HOURS** after Phase 3 before performing Phase 5. This ensures no latent issues surface.

#### Step 5.1: Stop Local AIOPS Database Containers (Keep Data)

```bash
# On AIOPS — STOP (do NOT remove) old database containers:
docker stop prediction-radar-app-db
docker stop prediction-radar-app-redis
docker stop frgops-standby
docker stop aiops-ravynai-postgres
docker stop docuseal-redis

# Verify services still functional after stopping local DBs
# (They should be using COREDB exclusively)
```

#### Step 5.2: Archive Old Database Volumes

```bash
# On AIOPS:
# Create archive of old database data (DO NOT DELETE)
mkdir -p /opt/archives/db_migration_$(date +%Y%m%d)
tar -czf /opt/archives/db_migration_$(date +%Y%m%d)/prediction_radar_pg.tar.gz \
  /var/lib/docker/volumes/prediction-radar_postgres_data/
tar -czf /opt/archives/db_migration_$(date +%Y%m%d)/prediction_radar_redis.tar.gz \
  /var/lib/docker/volumes/prediction-radar_redis_data/
tar -czf /opt/archives/db_migration_$(date +%Y%m%d)/frgops_standby.tar.gz \
  /var/lib/docker/volumes/*frgops-standby*/
tar -czf /opt/archives/db_migration_$(date +%Y%m%d)/ravynai_postgres.tar.gz \
  /var/lib/docker/volumes/ravynai_postgres_data/
tar -czf /opt/archives/db_migration_$(date +%Y%m%d)/docuseal_redis.tar.gz \
  /var/lib/docker/volumes/*docuseal-redis*/

ls -lh /opt/archives/db_migration_$(date +%Y%m%d)/
```

#### Step 5.3: Set Up COREDB Automated Backups

```bash
# On COREDB:
cat > /opt/coredb/backup.sh << 'BACKUP_SCRIPT'
#!/bin/bash
BACKUP_DIR=/opt/coredb/postgres/backups
RETENTION_DAYS=30
DATE=$(date +%Y%m%d_%H%M%S)

# Dump all databases
docker exec coredb-postgres pg_dumpall -U admin --clean --if-exists \
  | gzip > $BACKUP_DIR/full_$DATE.sql.gz

# Individual database dumps
for DB in prediction_radar frgops ravynai surplusai voiceagent langfuse; do
  docker exec coredb-postgres pg_dump -U admin -d $DB --clean --if-exists \
    | gzip > $BACKUP_DIR/${DB}_$DATE.sql.gz
done

# Upload to MinIO
docker exec coredb-minio mc cp --recursive /backups/ minio/backups/postgres/

# Cleanup old backups
find $BACKUP_DIR -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "[$(date)] Backup complete: $DATE"
BACKUP_SCRIPT

chmod +x /opt/coredb/backup.sh

# Add cron job (daily at 02:00 UTC)
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/coredb/backup.sh >> /var/log/coredb-backup.log 2>&1") | crontab -
```

---

## 5. VALIDATION GATES

Each gate must be satisfied before proceeding. If a gate fails, stop and execute the rollback for that phase.

### Gate 0: Pre-Flight Repairs Complete

| # | Condition | Check Command | Must Return |
|---|-----------|---------------|-------------|
| G0.1 | FRGCRM API online | `pm2 status \| grep frgcrm-api` | `online` |
| G0.2 | FRGCRM API health | `curl -s http://localhost:<port>/health` | HTTP 200 |
| G0.3 | SurplusAI agent online | `pm2 status \| grep surplusai` | `online` (restarts < 3 in past 5 min) |
| G0.4 | Voice Agent online | `pm2 status \| grep voice-agent` | `online` (restarts < 3 in past 5 min) |
| G0.5 | Stripe mode confirmed | Documented decision (live or test) | Written confirmation |
| G0.6 | COREDB reachable | `ping -c 3 <COREDB_IP>` | 0% packet loss |
| G0.7 | COREDB SSH works | `ssh root@<COREDB_IP> uptime` | Returns uptime |
| G0.8 | COREDB Tailscale joined | `ssh root@<COREDB_IP> tailscale status` | Shows connected peers |
| G0.9 | All 3 Tailscale IPs documented | `tailscale status` on each node | All 3 IPs recorded |

### Gate 1: COREDB Infrastructure Ready

| # | Condition | Check Command | Must Return |
|---|-----------|---------------|-------------|
| G1.1 | PostgreSQL healthy | `docker exec coredb-postgres pg_isready` | accepting connections |
| G1.2 | Redis healthy | `docker exec coredb-redis redis-cli PING` | PONG |
| G1.3 | MinIO healthy | `curl -s http://localhost:9000/minio/health/live` | 200 OK |
| G1.4 | Langfuse healthy | `curl -s http://localhost:3030/api/public/health` | OK |
| G1.5 | All 6 DBs created | `docker exec coredb-postgres psql -U admin -c "\l"` | 6 databases listed |
| G1.6 | AIOPS→COREDB PG reachable | `psql -h <COREDB_TS_IP> -U admin -c "SELECT 1"` | 1 |
| G1.7 | AIOPS→COREDB Redis reachable | `redis-cli -h <COREDB_TS_IP> PING` | PONG |
| G1.8 | Hostinger→COREDB PG reachable | `psql -h <COREDB_TS_IP> -U admin -c "SELECT 1"` | 1 |
| G1.9 | Hostinger→COREDB Redis reachable | `redis-cli -h <COREDB_TS_IP> PING` | PONG |
| G1.10 | Firewall active | `iptables -L -n \| grep 5432` | DROP on eth0, ACCEPT on tailscale0 |

### Gate 2: Non-Revenue Migration Complete

| # | Condition | Check Command | Must Return |
|---|-----------|---------------|-------------|
| G2.1 | Docuseal healthy | `curl -s http://localhost:3010/health` | HTTP 200 |
| G2.2 | Docuseal public reachable | `curl -I https://docuseal.wheeler.ai` | HTTP 200 |
| G2.3 | Docuseal using COREDB Redis | `docker logs docuseal-app 2>&1 \| grep -i redis` | COREDB IP visible |
| G2.4 | Langfuse reachable from AIOPS | `curl -s http://<COREDB_TS_IP>:3030/api/public/health` | OK |
| G2.5 | No service degradation on revenue apps | All revenue health checks passing | All 200 |

### Gate 3: Revenue Migration Complete

| # | Condition | Check Command | Must Return |
|---|-----------|---------------|-------------|
| G3.1 | Prediction Radar API healthy | `curl -s http://localhost:8000/health` | HTTP 200 |
| G3.2 | Prediction Radar Web healthy | `curl -s http://localhost:8098` | HTTP 200 |
| G3.3 | Prediction Radar public reachable | `curl -I https://predictionradar.app` | HTTP 200 |
| G3.4 | Prediction Radar using COREDB PG | `docker logs prediction-radar-app-web \| grep "COREDB_TS_IP"` | Connection to COREDB |
| G3.5 | Prediction Radar using COREDB Redis | `docker logs prediction-radar-app-web \| grep -i redis` | COREDB IP visible |
| G3.6 | FRGCRM API online | `pm2 status \| grep frgcrm-api` | `online` |
| G3.7 | FRGCRM Agent online | `pm2 status \| grep frgcrm-agent` | `online` |
| G3.8 | FRGCRM Mirror online | `pm2 status \| grep frgcrm-mirror` | `online` |
| G3.9 | FRGCRM public reachable | `curl -I https://frgops.fundsrecoverygroup.tech` | HTTP 200 |
| G3.10 | RavynAI healthy | `curl -s http://localhost:8007/health` | HTTP 200 |
| G3.11 | RavynAI public reachable | `curl -I https://ravynai.wheeler.ai/health` | HTTP 200 |
| G3.12 | SurplusAI agent online | `pm2 status \| grep surplusai` | `online` |
| G3.13 | Voice agent online | `pm2 status \| grep voice-agent` | `online` |
| G3.14 | All PM2 restart counts stable | `pm2 status` twice, 2 min apart | No increment |
| G3.15 | fundsrecoverygroup.com healthy | `curl -I https://fundsrecoverygroup.com` | HTTP 200 |
| G3.16 | wheeler.frgop.io healthy | `curl -I https://wheeler.frgop.io` | HTTP 200 |
| G3.17 | surplusai.io healthy | `curl -I https://surplusai.io` | HTTP 200 |

### Gate 4: Post-Migration Stabilization

| # | Condition | Check Command | Must Return |
|---|-----------|---------------|-------------|
| G4.1 | 30-min uptime all services | `pm2 status` and `docker ps` | All uptimes > 30 min |
| G4.2 | No error spikes in logs | Log scan | No connection refused/timeout to old DB |
| G4.3 | COREDB connection counts normal | `SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname` | Expected connections per DB |
| G4.4 | Stripe webhooks processing | Recent webhook received and 200'd | 200 in Prediction Radar logs |
| G4.5 | AI responses functional | Test Prediction Radar prediction | Valid AI response returned |

---

## 6. ROLLBACK COMMANDS (Exact Commands to Reverse Each Step)

Rollback should be executed immediately if any validation gate fails within its phase. Rollback commands are designed to be copy-paste safe.

### Rollback Phase 3 — Prediction Radar (Reverse Step 3.3)

```bash
# On AIOPS:
# 1. Stop Prediction Radar
docker compose --project-name prediction-radar down

# 2. Restore original environment
cp /opt/prediction-radar/.env.backup.<TIMESTAMP> /opt/prediction-radar/.env

# 3. Start Prediction Radar with original config
docker compose --project-name prediction-radar up -d

# 4. Verify
sleep 10
docker compose --project-name prediction-radar ps
curl -s http://localhost:8000/health
curl -I https://predictionradar.app

# Time to rollback: ~2 minutes
# Downtime during rollback: ~3 minutes (total outage ~5-8 minutes)
```

### Rollback Phase 3 — FRGCRM (Reverse Step 3.5)

```bash
# On AIOPS:
# 1. Stop FRGCRM PM2 processes
pm2 stop frgcrm-agent-svc frgcrm-api frgcrm-mirror-test

# 2. Restore original DATABASE_URL
# (Restore from ecosystem config backup or .env backup)

# 3. Restart with original config
pm2 restart frgcrm-agent-svc --update-env
pm2 restart frgcrm-api --update-env
pm2 restart frgcrm-mirror-test --update-env

# 4. Verify
pm2 status
curl -s http://localhost:8013/health
curl -s http://localhost:8003/health
curl -I https://frgops.fundsrecoverygroup.tech

# Time to rollback: ~2 minutes
```

### Rollback Phase 3 — RavynAI (Reverse Step 3.6)

```bash
# On AIOPS:
docker compose --project-name ravynai down
cp /opt/ravynai/.env.backup.<TIMESTAMP> /opt/ravynai/.env
docker compose --project-name ravynai up -d

# Verify
sleep 5
curl -s http://localhost:8007/health
```

### Rollback Phase 3 — SurplusAI / Voice Agent (Reverse Step 3.7)

```bash
# On AIOPS:
# Restore original PM2 env (remove COREDB connection strings)
pm2 restart surplusai-scraper-agent-svc --update-env
pm2 restart voice-agent-svc --update-env

pm2 status
# Verify restart count stops incrementing
```

### Rollback Phase 2 — Docuseal (Reverse Step 2.1)

```bash
# On AIOPS:
docker compose --project-name docuseal down
# Restore original REDIS_URL pointing to local redis
docker compose --project-name docuseal up -d

curl -s http://localhost:3010/health
```

### Full System Rollback (Emergency — Reverse Everything)

```bash
#!/bin/bash
# EMERGENCY FULL ROLLBACK — Execute only if multiple services fail after migration

echo "=== EMERGENCY FULL ROLLBACK STARTED ==="
echo "Time: $(date)"
echo "This will restore ALL services to pre-migration state."
echo "Estimated downtime: 10-15 minutes total."
echo ""

# Step 1: Rollback Prediction Radar
echo "[1/5] Rolling back Prediction Radar..."
docker compose --project-name prediction-radar down
cp /opt/prediction-radar/.env.backup.* /opt/prediction-radar/.env 2>/dev/null
docker compose --project-name prediction-radar up -d
sleep 10
curl -s http://localhost:8000/health || echo "WARNING: Prediction Radar API not responding"

# Step 2: Rollback FRGCRM
echo "[2/5] Rolling back FRGCRM..."
pm2 stop frgcrm-agent-svc frgcrm-api frgcrm-mirror-test
# Restore original env (manually ensure env points to localhost:5433)
pm2 restart frgcrm-agent-svc --update-env
pm2 restart frgcrm-api --update-env
pm2 restart frgcrm-mirror-test --update-env

# Step 3: Rollback RavynAI
echo "[3/5] Rolling back RavynAI..."
docker compose --project-name ravynai down
cp /opt/ravynai/.env.backup.* /opt/ravynai/.env 2>/dev/null
docker compose --project-name ravynai up -d
sleep 5

# Step 4: Rollback Docuseal
echo "[4/5] Rolling back Docuseal..."
docker compose --project-name docuseal down
# Restore original REDIS_URL
docker compose --project-name docuseal up -d

# Step 5: Restart SurplusAI and Voice Agent with original config
echo "[5/5] Rolling back SurplusAI and Voice Agent..."
pm2 restart surplusai-scraper-agent-svc --update-env
pm2 restart voice-agent-svc --update-env

echo ""
echo "=== FULL ROLLBACK COMPLETE ==="
echo "Time: $(date)"
echo "Run validation: pm2 status && docker ps"
```

---

## 7. DOWNTIME RISK ASSESSMENT

### Per-Service Downtime Matrix

| # | Service | Phase | Downtime Duration | Revenue Impact | Risk Level | Mitigation |
|---|---------|-------|-------------------|----------------|------------|------------|
| 1 | **Prediction Radar** (API+Web+Worker+Scheduler+Dashboard) | Phase 3 (Step 3.3) | 2-5 min | **CRITICAL** — Primary SaaS revenue, Stripe subscriptions, real-time predictions | **HIGH** | Schedule at lowest traffic (typically 03:00-05:00 UTC). Pre-stage dump on COREDB. Have rollback .env ready. |
| 2 | **FRGCRM Agent Service** | Phase 3 (Step 3.5) | 1-2 min | **HIGH** — CRM agent logic, lead processing | **MEDIUM** | Agent is internal. Frontend queues requests. Short outage acceptable if frontend handles gracefully. |
| 3 | **FRGCRM API** | Phase 3 (Step 3.5) | 1-2 min | **HIGH** — CRM API backend for frontend | **MEDIUM** | Must be FIXED (Phase 0) before migration. If it restarts cleanly, downtime is sub-minute. |
| 4 | **FRGCRM Mirror Test** | Phase 3 (Step 3.5) | 1-2 min | **LOW** — Test environment | **LOW** | Non-production. Can be migrated first as a canary test. |
| 5 | **RavynAI API** | Phase 3 (Step 3.6) | 2-3 min | **MEDIUM** — AI support service | **LOW-MEDIUM** | Supporting service. Primary AI still routes through LiteLLM on Hostinger. |
| 6 | **SurplusAI Scraper Agent** | Phase 3 (Step 3.7) | 1-2 min | **HIGH** — Data pipeline | **MEDIUM** | Already has 282 restarts — users may not notice additional restart. Fix first. |
| 7 | **Voice Agent Service** | Phase 3 (Step 3.7) | 1-2 min | **HIGH** — Voice outreach | **MEDIUM** | Already has 282 restarts. Fix first. Voice calls are async — short outage acceptable. |
| 8 | **Docuseal** | Phase 2 (Step 2.1) | < 1 min | **LOW** — Document signing | **LOW** | Low traffic. No revenue dependence. |
| 9 | **LiteLLM Proxy** | N/A (stays on Hostinger) | 0 min | N/A | **NONE** | Not moved. Zero downtime. |
| 10 | **Chatwoot** | N/A (stays on Hostinger) | 0 min | N/A | **NONE** | Not moved. Zero downtime. |
| 11 | **n8n Workflows** | N/A (stays on Hostinger) | 0 min | N/A | **NONE** | Not moved. Zero downtime. |
| 12 | **Webhook Receiver** | N/A (stays on Hostinger) | 0 min | N/A | **NONE** | Not moved. Zero downtime. Stripe webhooks unaffected. |
| 13 | **Grafana / Superset / Uptime Kuma** | N/A (stay on AIOPS) | 0 min | N/A | **NONE** | Monitoring and dashboards. No database migration. |
| 14 | **fundsrecoverygroup.com** (main site) | N/A (stays on Hostinger) | 0 min | N/A | **NONE** | Public website and lead intake. Zero downtime. Traefik + frontend unchanged. |

### Cumulative Downtime Window

```
Phase 2 (Non-Revenue):    < 1 minute   — Docuseal only
Phase 3 (Revenue):        5-10 minutes — Staggered: Prediction Radar first, then FRGCRM, then RavynAI
Phase 3 Rollback:         3-5 minutes  — If any step fails
Phase 5 (Cleanup):        1-2 minutes  — Stopping old DB containers (services already on COREDB)

Total planned downtime:   6-12 minutes
Worst case (full rollback): 15-20 minutes
```

### Risk Heat Map

```
                     Low Traffic          Medium Traffic       High Traffic
                     (03:00-05:00 UTC)    (transition)         (peak hours)
Prediction Radar     🟡 LOW-MEDIUM        🟠 MEDIUM            🔴 HIGH
FRGCRM Suite         🟡 LOW               🟡 LOW-MEDIUM        🟠 MEDIUM
RavynAI              🟢 NEGLIGIBLE        🟢 NEGLIGIBLE        🟡 LOW
Docuseal             🟢 NEGLIGIBLE        🟢 NEGLIGIBLE        🟢 NEGLIGIBLE
Edge Services        🟢 ZERO DOWNTIME     🟢 ZERO DOWNTIME     🟢 ZERO DOWNTIME
```

---

## 8. FINAL GO/NO-GO CHECKLIST (Must-Have Conditions Before Cutover)

### SECTION A: SERVICE HEALTH (All Must Be GO)

| # | Condition | Status | Owner |
|---|-----------|--------|-------|
| A1 | FRGCRM API is ONLINE (not errored) with 0 recent restarts | [ ] GO / [ ] NO-GO | AIOPS Admin |
| A2 | FRGCRM API health endpoint returns 200 | [ ] GO / [ ] NO-GO | AIOPS Admin |
| A3 | SurplusAI Scraper Agent is ONLINE with 0 restarts in last 5 min | [ ] GO / [ ] NO-GO | AIOPS Admin |
| A4 | Voice Agent Service is ONLINE with 0 restarts in last 5 min | [ ] GO / [ ] NO-GO | AIOPS Admin |
| A5 | Prediction Radar all 4 containers healthy (43h+ uptime baseline) | [ ] GO / [ ] NO-GO | AIOPS Admin |
| A6 | RavynAI 2 containers healthy | [ ] GO / [ ] NO-GO | AIOPS Admin |
| A7 | Docuseal healthy | [ ] GO / [ ] NO-GO | AIOPS Admin |
| A8 | FRGCRM Agent Service healthy | [ ] GO / [ ] NO-GO | AIOPS Admin |
| A9 | All PM2 restarts counts stable (no incrementing in 5 min) | [ ] GO / [ ] NO-GO | AIOPS Admin |

### SECTION B: STRIPE & PAYMENTS (All Must Be GO)

| # | Condition | Status | Owner |
|---|-----------|--------|-------|
| B1 | Stripe key mode verified and documented (live vs. test) | [ ] GO / [ ] NO-GO | Finance / AIOPS Admin |
| B2 | If live mode: recent successful transaction confirmed | [ ] GO / [ ] NO-GO | Finance |
| B3 | Stripe webhook endpoint reachable and processing | [ ] GO / [ ] NO-GO | AIOPS Admin |
| B4 | STRIPE_SECRET_KEY and STRIPE_PUBLISHABLE_KEY backed up | [ ] GO / [ ] NO-GO | AIOPS Admin |

### SECTION C: COREDB INFRASTRUCTURE (All Must Be GO)

| # | Condition | Status | Owner |
|---|-----------|--------|-------|
| C1 | COREDB node (5.78.210.123) reachable via SSH | [ ] GO / [ ] NO-GO | Infra Admin |
| C2 | COREDB PostgreSQL 16 deployed and healthy | [ ] GO / [ ] NO-GO | Infra Admin |
| C3 | COREDB Redis 7 deployed and healthy | [ ] GO / [ ] NO-GO | Infra Admin |
| C4 | COREDB MinIO deployed and healthy | [ ] GO / [ ] NO-GO | Infra Admin |
| C5 | COREDB Langfuse deployed and healthy | [ ] GO / [ ] NO-GO | Infra Admin |
| C6 | All 6 application databases created (prediction_radar, frgops, ravynai, surplusai, voiceagent, langfuse) | [ ] GO / [ ] NO-GO | Infra Admin |
| C7 | COREDB disk space sufficient (min 50GB free for migration + growth) | [ ] GO / [ ] NO-GO | Infra Admin |
| C8 | COREDB memory adequate (min 4GB free for PostgreSQL + Redis) | [ ] GO / [ ] NO-GO | Infra Admin |
| C9 | COREDB firewall rules active (PG/Redis blocked from public internet) | [ ] GO / [ ] NO-GO | Infra Admin |

### SECTION D: NETWORK & TAILSCALE (All Must Be GO)

| # | Condition | Status | Owner |
|---|-----------|--------|-------|
| D1 | Tailscale mesh verified — all 3 nodes visible in `tailscale status` | [ ] GO / [ ] NO-GO | Infra Admin |
| D2 | AIOPS → COREDB PostgreSQL reachable over Tailscale | [ ] GO / [ ] NO-GO | AIOPS Admin |
| D3 | AIOPS → COREDB Redis reachable over Tailscale | [ ] GO / [ ] NO-GO | AIOPS Admin |
| D4 | Hostinger → COREDB PostgreSQL reachable over Tailscale | [ ] GO / [ ] NO-GO | Hostinger Admin |
| D5 | Hostinger → COREDB Redis reachable over Tailscale | [ ] GO / [ ] NO-GO | Hostinger Admin |
| D6 | Tailscale connectivity between AIOPS (100.121.x.x) and Hostinger (100.98.x.x) verified | [ ] GO / [ ] NO-GO | Infra Admin |
| D7 | No DNS changes planned or in-progress | [ ] GO / [ ] NO-GO | DNS Admin |
| D8 | All domain health checks passing pre-migration | [ ] GO / [ ] NO-GO | AIOPS Admin |

### SECTION E: BACKUPS & ROLLBACK READINESS (All Must Be GO)

| # | Condition | Status | Owner |
|---|-----------|--------|-------|
| E1 | Prediction Radar .env backed up to /opt/prediction-radar/.env.backup.* | [ ] GO / [ ] NO-GO | AIOPS Admin |
| E2 | Prediction Radar docker-compose.yml backed up | [ ] GO / [ ] NO-GO | AIOPS Admin |
| E3 | FRGCRM PM2 ecosystem file backed up | [ ] GO / [ ] NO-GO | AIOPS Admin |
| E4 | RavynAI .env backed up | [ ] GO / [ ] NO-GO | AIOPS Admin |
| E5 | Docuseal docker-compose.yml backed up | [ ] GO / [ ] NO-GO | AIOPS Admin |
| E6 | Full database dumps completed for all 4 source databases | [ ] GO / [ ] NO-GO | AIOPS Admin |
| E7 | Rollback commands tested in dry-run (reviewed, not executed) | [ ] GO / [ ] NO-GO | AIOPS Admin |
| E8 | Emergency full-rollback script reviewed and accessible | [ ] GO / [ ] NO-GO | AIOPS Admin |

### SECTION F: OPERATIONAL READINESS (All Must Be GO)

| # | Condition | Status | Owner |
|---|-----------|--------|-------|
| F1 | Maintenance window scheduled and approved | [ ] GO / [ ] NO-GO | Project Lead |
| F2 | All stakeholders notified (email/Slack/Teams) | [ ] GO / [ ] NO-GO | Project Lead |
| F3 | Communication channel open for real-time coordination | [ ] GO / [ ] NO-GO | Project Lead |
| F4 | At least 2 engineers available during cutover window | [ ] GO / [ ] NO-GO | Engineering Lead |
| F5 | Access to all 3 servers confirmed (SSH keys working) | [ ] GO / [ ] NO-GO | All Admins |
| F6 | This plan document accessible to all engineers | [ ] GO / [ ] NO-GO | Project Lead |
| F7 | Monitoring dashboard (Grafana + Uptime Kuma) visible during cutover | [ ] GO / [ ] NO-GO | AIOPS Admin |

### GO/NO-GO DECISION

```
[ ] ALL SECTIONS GO → PROCEED WITH CUTOVER
[ ] ANY NO-GO → HALT — Fix NO-GO items, re-assess in 24 hours

Decision made by: _____________________
Date/Time: _____________________
Signature: _____________________
```

---

## APPENDIX A: SERVER SUMMARY

| Node | Provider | Public IP | Tailscale Range | Role | Services |
|------|----------|-----------|-----------------|------|----------|
| **EDGE** | Hostinger | 187.77.148.88 | 100.98.x.x | Public TLS termination, static sites, frontend apps, LiteLLM proxy | Traefik, FRGops frontend, Chatwoot, n8n, LiteLLM, Webhook Receiver, MinIO Console |
| **AIOPS** | Hetzner | 5.78.140.118 | 100.121.x.x | All application compute, AI workloads, background workers, monitoring | Prediction Radar, RavynAI, FRGCRM API, SurplusAI, Voice Agent, Grafana, Superset, ClickHouse, Prometheus, Uptime Kuma, Healthchecks, ChangeDetection, Portainer, Dockge, Langflow, Spiderfoot, Netdata |
| **COREDB** | Hetzner | 5.78.210.123 | TBD (Tailscale) | All shared state — databases, cache, object storage, backups, observability storage | PostgreSQL 16, Redis 7, MinIO, Langfuse, Vector DB (Phase 2), Backup Service |

## APPENDIX B: CRITICAL PORTS & FIREWALL RULES

| Node | Port | Service | Public Access | Tailscale Access |
|------|------|---------|---------------|------------------|
| Hostinger | 80, 443 | Traefik | YES | N/A |
| Hostinger | 4000 | LiteLLM | Via Traefik | No |
| Hostinger | 5678 | n8n | Via Traefik | No |
| AIOPS | 8000 | Prediction Radar API | No | Yes |
| AIOPS | 8098 | Prediction Radar Web | Via Traefik | Yes |
| AIOPS | 8007 | RavynAI API | Via Traefik | Yes |
| AIOPS | 8013 | FRGCRM/Insforge Agent | No | Yes |
| AIOPS | 3002 | Grafana | Via Traefik | Yes |
| AIOPS | 9090 | Prometheus | No | Yes |
| COREDB | 5432 | PostgreSQL | **NEVER** | Yes |
| COREDB | 6379 | Redis | **NEVER** | Yes |
| COREDB | 9000 | MinIO S3 API | **NEVER** | Yes |
| COREDB | 9001 | MinIO Console | No | Yes |
| COREDB | 3030 | Langfuse | No | Yes |

## APPENDIX C: CONTACT & ESCALATION

| Role | Name | Contact | Availability |
|------|------|---------|--------------|
| AIOPS Admin | TBD | TBD | During cutover window |
| Hostinger Admin | TBD | TBD | During cutover window |
| COREDB / Infra Admin | TBD | TBD | During cutover window |
| Project Lead | TBD | TBD | During cutover window |
| Escalation (on-call) | TBD | TBD | 24/7 |

---

> **Document version:** 1.0
> **Last updated:** 2026-05-23
> **Next review:** Before cutover execution date (TBD)
> **Change log:** Initial creation — complete cutover plan for Wheeler 3-server infrastructure split
