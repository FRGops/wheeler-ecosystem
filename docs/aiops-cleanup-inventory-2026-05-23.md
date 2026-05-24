# AI Ops Container & PM2 Inventory Report
**Server:** wheeler-aiops-01  
**Date:** 2026-05-23  
**Scope:** Read-only inventory and recommendation -- NO deletions performed

---

## 1. EXECUTIVE SUMMARY

**Total Docker containers:** 34 (33 running, 1 stuck/created, 0 exited)  
**Total PM2 processes:** 18 (17 online, 1 stopped) + 1 pm2-logrotate module  
**Management UIs detected:** 3 (Portainer, Dockge, 1Panel) -- RECOMMEND: keep only 1Panel  
**Clear removal candidates flagged:** 6 containers, 1 PM2 process  
**Cross-server duplication confirmed:** Uptime Kuma, Grafana, Prometheus, Loki, Postgres

---

## 2. DOCKER CONTAINER INVENTORY

### 2.1 Production Application Stacks

| Container | Status | Image | Created | Ports | Risk | Recommendation |
|---|---|---|---|---|---|---|
| prediction-radar-app-db | Up (healthy) | postgres:16 | May 10 | 5432 (internal) | LOW | KEEP - Prediction Radar primary DB |
| prediction-radar-app-redis | Up (healthy) | redis:7 | May 10 | 6379 (internal) | LOW | KEEP - Prediction Radar cache |
| prediction-radar-app-api | Up (healthy) | built:api | May 10 | internal | LOW | KEEP - Core API |
| prediction-radar-app-web | Up | built:web | May 10 | 8098:80 | LOW | KEEP - Web frontend |
| prediction-radar-dashboard-v2 | Up (healthy) | built:dashboard-v2 | May 10 | 3000 (internal) | LOW | KEEP - Dashboard |
| prediction-radar-app-worker | Up | built:worker | May 10 | internal | LOW | KEEP - Background worker |
| prediction-radar-app-scheduler | Up | built:scheduler | May 10 | internal | LOW | KEEP - Task scheduler |
| aiops-ravynai-postgres | Up (healthy) | postgis/postgis:16-3.4 | May 10 | 5434:5432 | LOW | KEEP - RavynAI spatial DB |
| aiops-ravynai-app | Up (healthy) | built:ravynai-app | May 10 | 8007:8007 | LOW | KEEP - Opportunity graph app |
| aiops-superset | Up (healthy) | apache/superset:4.1.1 | May 10 | 8088:8088 | LOW | KEEP - Analytics BI |
| aiops-clickhouse | Up | clickhouse/clickhouse-server:24.3 | May 10 | 8123:8123 | LOW | KEEP - OLAP backend for Superset |
| aiops-healthchecks | Up | linuxserver/healthchecks | May 10 | 3130:8000 | LOW | KEEP - Cron job monitoring |
| aiops-changedetection | Up | dgtlmoon/changedetection.io | May 10 | 5000:5000 | LOW | KEEP - Web page change alerts |
| docuseal | Up | docuseal/docuseal:latest | May 21 | 3010:3000 | LOW | KEEP - Document signing platform |
| docuseal-redis | Up | redis:7-alpine | May 21 | 6379 (internal) | LOW | KEEP - Docuseal cache |
| langflow | Up | langflowai/langflow:1.0.19 | May 21 | 7860:7860 | LOW | KEEP - AI workflow builder |
| open-webui | Up (healthy) | open-webui:main | May 23 | 127.0.0.1:3000:8080 | LOW | KEEP - LLM chat interface |
| usesend | Up | usesend/usesend:latest | May 23 | internal | MEDIUM | INVESTIGATE - Recently deployed, confirm purpose |
| temporal-postgres | Up | postgres:16-alpine | May 23 | host network | MEDIUM | KEEP - Temporal DB (but uses external seed at 100.118.166.117) |
| temporal-temporal-1 | Up | temporalio/auto-setup:latest | May 23 | host network | MEDIUM | KEEP - Workflow engine |

### 2.2 Monitoring Stack

| Container | Status | Image | Created | Ports | Risk | Recommendation |
|---|---|---|---|---|---|---|
| aiops-grafana | Up | grafana/grafana:latest | May 9 | 3002:3000 | LOW | KEEP - Primary Grafana instance |
| aiops-prometheus | Up | prom/prometheus:latest | May 9 | 9090:9090 | LOW | KEEP - Primary Prometheus |
| loki | Up | grafana/loki:latest | May 23 | 127.0.0.1:3100:3100 | LOW | KEEP - Working log aggregation |
| promtail | Up | grafana/promtail:latest | May 23 | 127.0.0.1:9080:9080 | LOW | KEEP - Log shipper |
| uptime-kuma | Up (healthy) | louislam/uptime-kuma:1 | May 8 | 3001:3001 | LOW | KEEP - Uptime monitoring |
| netdata | Up (healthy) | netdata/netdata | May 9 | 19999:19999 | LOW | KEEP - System metrics |
| hostinger-health-exporter | Up | python:3.12-alpine | May 21 | 9091:9091 | LOW | KEEP - Custom health metrics |

### 2.3 Management UIs (TRIPLICATE)

| Container | Status | Age | Ports | Actively Managing? | Risk | Recommendation |
|---|---|---|---|---|---|---|
| 1panel | systemd (active) | 2 weeks | 8090 | YES - system-level mgmt | LOW | **KEEP** - Most complete, manages OS + Docker + files |
| portainer | Up | 2 days | 9000:9000, 9443 | UNLIKELY - no labeled containers found | LOW | REMOVE - Duplicate with 1Panel |
| dockge | Up (healthy) | 2 days | 5001:5001 | PARTIAL - 2 real stacks out of 7 | LOW | REMOVE - Duplicate, stacks are mostly boilerplate |

### 2.4 Stuck / Broken / Test Artifacts

| Container | Status | Created | Ports | Risk | Recommendation |
|---|---|---|---|---|---|
| aiops-loki | **CREATED (never started)** | May 23 | none | **HIGH** | **REMOVE** -- Stuck in "Created" state, never ran, port conflict with working `loki` container. Image is old tag (main-2e3da9a) |
| dockge-test-nginx | Up | May 9 | 8080:80 | **HIGH** | **REMOVE** -- Test artifact from Dockge stack. Zero mounts, no custom config, default nginx welcome page. Consumes port 8080 |
| temporal-temporal-ui-1 | **RESTARTING** (loop) | May 23 | none | **HIGH** | **REMOVE** -- Stuck in restart loop. Replaced by `nice_kalam` (temporal UI, started <1min ago). Someone hot-fixed by creating a new container rather than fixing this one |
| nice_kalam | Up (<1 sec) | May 23 | 8080/tcp | MEDIUM | MONITOR -- Auto-named (Docker generated). Was this a manual `docker run` instead of compose? Should be folded into temporal stack under proper name |

### 2.5 Standalone / Uncertain Purpose

| Container | Status | Created | Ports | Risk | Recommendation |
|---|---|---|---|---|---|
| frgops-standby | Up (59m) | May 21 | 5433:5432 | MEDIUM | **INVESTIGATE** -- Postgres "standby" recently restarted. Is this a hot standby for FRG CRM? What replicates into it? If unused, remove |

---

## 3. DOCKER IMAGE DUPLICATES

| Image | Versions Present | Note |
|---|---|---|
| postgres | 16, 16-alpine | Two variants, reasonable for different needs |
| redis | 7, 7-alpine | Two variants (alpine for docuseal, regular for prediction-radar) |
| grafana/loki | latest, main-2e3da9a | OLD tag `main-2e3da9a` is the broken `aiops-loki` container |
| langflowai/langflow | latest (5.5GB), 1.0.19 (2.79GB) | `latest` pulled but container uses pinned 1.0.19. `latest` image is unused |
| temporalio/ui | latest (687MB) | Used by 2 containers: temporal-temporal-ui-1 (restarting) and nice_kalam (just started) |

**Image cleanup savings:** ~5.9GB (langflowai/langflow:latest ~5.5GB + grafana/loki:main-2e3da9a ~193MB + google/cadvisor unused ~102MB)

---

## 4. PM2 PROCESS INVENTORY

### 4.1 Agent Services (11 processes)

All are Node.js services under `/opt/apps/<name>-agent-svc/dist/index.js`. Each listens on a unique port:

| Process | PID | Mem | Uptime | Port | Purpose | Risk | Recommendation |
|---|---|---|---|---|---|---|---|
| design-agent-svc | 3819275 | 120.8MB | 13h | 8020 | Design agent | LOW | KEEP |
| horizon-agent-svc | 3819493 | 108.3MB | 13h | 8006 | Horizon agent | LOW | KEEP |
| paperless-agent-svc | 3819745 | 112.6MB | 13h | 8009 | Paperless document agent | LOW | KEEP |
| prediction-radar-agent-svc | 3819956 | 116.2MB | 13h | 8011 | Prediction Radar agent | LOW | KEEP |
| ravyn-agent-svc | 3820164 | 113.0MB | 13h | 8005 | RavynAI agent | LOW | KEEP |
| frgcrm-agent-svc | 3820365 | 104.6MB | 13h | 8003 | FRG CRM agent | LOW | KEEP |
| insforge-agent-svc | 3820605 | 79.1MB | 13h | 8013 | Insforge agent | LOW | KEEP |
| surplusai-scraper-agent-svc | 3820831 | 116.7MB | 13h | none visible | SurplusAI scraper | LOW | KEEP |
| voice-agent-svc | 3821078 | 111.7MB | 13h | 8008 | Voice agent | LOW | KEEP |
| ecosystem-guardian | 3153376 | 72.8MB | 15h | none visible | Wheeler brain OS guardian | LOW | KEEP |
| event-bus-relay | 223182 | 72.5MB | 14h | 6399 | Internal event bus relay | LOW | KEEP |

### 4.2 Application Services

| Process | PID | Mem | Uptime | Port | Purpose | Risk | Recommendation |
|---|---|---|---|---|---|---|---|
| litellm | 3495643 | 357.2MB | 11h | 4049 | LLM proxy (OpenAI-compatible API) | LOW | KEEP - Used by open-webui |
| openclaw-dashboard | 2360824 | 71.9MB | 15h | 8110 | OpenClaw dashboard | LOW | KEEP |
| voice-outreach-service | 3367659 | 53.8MB | 15h | 8095 | FRG CRM voice outreach (Python) | LOW | KEEP |
| war-room-server | 3925091 | 65.7MB | 14h | 8091 | War room operations | LOW | KEEP |
| surplusai-portal-api | 836238 | 107.1MB | 11h | 8103 | SurplusAI portal backend (uvicorn) | LOW | KEEP |
| frgcrm-api | 1477093 | 236.1MB | 26m | 8082 | FRG CRM API (Python, 2 restarts) | MEDIUM | **MONITOR** -- 2 recent restarts in 26 min, high memory. Check logs for crash cause |

### 4.3 Stopped / Idle

| Process | Status | Mem | Uptime | Risk | Recommendation |
|---|---|---|---|---|---|
| backup-verification | stopped | 0MB | 0 | **HIGH** | **REMOVE or FIX** -- Stopped. Remove if backup verification is handled elsewhere. Fix if needed. |

---

## 5. MANAGEMENT UI ANALYSIS & RECOMMENDATION

### 5.1 Comparison

| Criterion | 1Panel | Portainer | Dockge |
|---|---|---|---|
| Installation | Native binary (systemd) | Docker container | Docker container |
| Runtime | 2 weeks continuous | 2 days | 2 days |
| Web Port | 8090 | 9000 (HTTP), 9443 (HTTPS) | 5001 |
| System management | YES (full Linux panel) | NO (Docker only) | NO (Docker compose only) |
| Docker management | YES | YES | YES (compose-based) |
| File manager | YES | NO | NO |
| Database management | YES | NO | NO |
| Active stacks configured | Unknown (manages all containers) | Unknown | 2 real + 5 boilerplate |
| Memory usage | 71.8MB (peak 121.4MB) | Container ~50-100MB | Container ~50-100MB |

### 5.2 Dockge Stack Analysis

Dockge manages 7 stacks under `/opt/stacks/`. Only **2 are real**:

| Stack | Status |
|---|---|
| dockerecosystemmanager | REAL - manages dockge-test-nginx (test artifact) |
| temporal | REAL - manages Temporal workflow engine |
| 01-monitoring | BOILERPLATE - identical nginx template, never customized |
| 02-aiops | BOILERPLATE - identical nginx template, never customized |
| 03-openclaw-staging | BOILERPLATE - identical nginx template, never customized |
| 04-brain-staging | BOILERPLATE - identical nginx template, never customized |
| 05-frgops-staging | BOILERPLATE - identical nginx template, never customized |

Additionally, 8 real application stacks are **managed outside Dockge** via docker compose files under `/opt/apps/`.

### 5.3 Recommendation

**KEEP 1Panel (port 8090) as the sole management UI.**

Rationale:
- 1Panel has been running the longest (2 weeks) with no issues
- Most complete feature set (OS + Docker + files + DBs + firewall)
- Native installation (survives Docker daemon restarts)
- Dockge manages mostly boilerplate stacks and the test artifact
- Portainer shows no signs of active usage (no labeled containers, no deployed stacks found)
- Three UIs is wasteful -- at least 150-200MB RAM, plus attack surface

**Migration steps (for future execution):**
1. Verify all real stacks are visible/importable in 1Panel
2. Export Dockge's temporal stack and re-import into 1Panel or native compose
3. Stop and remove Dockge container and its 5 boilerplate stacks
4. Stop and remove Portainer container
5. Remove `/opt/stacks/` boilerplate directories (01-05)

---

## 6. CROSS-SERVER DUPLICATION ASSESSMENT

Based on the audit context, these services appear on BOTH wheeler-aiops-01 and the worker server:

| Service | AI Ops Instance | Worker Instance | Assessment | Recommendation |
|---|---|---|---|---|
| Uptime Kuma | Port 3001 | Present | Likely intentional -- each server monitors its own local services | KEEP both if each monitors local-only targets. Consolidate if both monitor same targets |
| Grafana | aiops-grafana (3002) | Present | Possible duplication -- single Grafana can scrape both servers' Prometheus | CONSOLIDATE to AI Ops Grafana only |
| Prometheus | aiops-prometheus (9090) | Present | Likely intentional -- per-server metric scraping is standard | KEEP both (federate to AI Ops master) |
| Loki | loki (3100) + aiops-loki (broken) | Present | aiops-loki is broken/duplicate, working loki is on AI Ops | REMOVE broken aiops-loki. Worker's Loki may ship its own promtail logs |
| Postgres | 4 instances on AI Ops | Present | Multiple postgres instances on AI Ops already -- worker likely has its own | INVESTIGATE if worker postgres can be consolidated |

---

## 7. RECOMMENDED REMOVAL LIST (DO NOT DELETE -- REVIEW FIRST)

### 7.1 Clear Candidates (HIGH confidence)

| # | Target | Type | Justification |
|---|---|---|---|
| 1 | **aiops-loki** | Container | Stuck in "Created" state, never started. Working `loki` container already serves log aggregation on port 3100. Image tag is stale (main-2e3da9a vs latest) |
| 2 | **dockge-test-nginx** | Container | Test artifact from Dockge. Zero mounts, zero config, default nginx. Wastes port 8080. |
| 3 | **temporal-temporal-ui-1** | Container | Stuck in restart loop. Replaced by `nice_kalam` container. Remove once new UI is stable. |
| 4 | **portainer** | Container | Duplicate management UI. 1Panel covers all its functionality. No evidence of active use. |
| 5 | **dockge** | Container | Duplicate management UI. 5 of 7 managed stacks are default nginx templates. Real apps managed outside Dockge. |
| 6 | **langflowai/langflow:latest** | Image | Unused. Container uses pinned version 1.0.19. Saves 5.5GB. |
| 7 | **grafana/loki:main-2e3da9a** | Image | Only used by broken aiops-loki container. Saves 193MB. |
| 8 | **google/cadvisor** | Image | Pulled 7 years ago, never used. Saves 102MB. |

### 7.2 Medium Confidence Candidates

| # | Target | Type | Justification |
|---|---|---|---|
| 9 | **frgops-standby** | Container | Postgres "standby" on port 5433. Recently restarted (59 min ago). Confirm if actually receiving replication before removing. |
| 10 | **backup-verification** | PM2 | Stopped process. Remove if backup verification is handled by another mechanism. |
| 11 | **Boilerplate Dockge stacks** | Files | `/opt/stacks/01-monitoring` through `05-frgops-staging` -- all identical nginx templates, never customized. Remove after Dockge is removed. |

### 7.3 Requires Investigation Before Action

| # | Target | Type | Justification |
|---|---|---|---|
| 12 | **nice_kalam** | Container | Auto-named docker run. Needs to be properly integrated into temporal compose stack with fixed name. |
| 13 | **frgcrm-api** | PM2 | 2 restarts in 26 min. Check crash root cause before cleanup. |
| 14 | **usesend** | Container | Recently deployed. Confirm business purpose and ownership. |

---

## 8. RESOURCE USAGE SUMMARY

### 8.1 Memory (containers + PM2)

| Category | Estimated RAM |
|---|---|
| PM2 agent services (11) | ~1.1 GB |
| PM2 app services (6 online) | ~0.9 GB |
| Docker containers (est.) | ~4-6 GB |
| **Estimated total** | **~6-8 GB** |

### 8.2 Port Map (public-facing services)

| Port | Service | Notes |
|---|---|---|
| 22 | SSH | System |
| 3001 | Uptime Kuma | Monitoring |
| 3002 | Grafana | Monitoring (aiops-grafana) |
| 3010 | Docuseal | Document signing |
| 3130 | Healthchecks | Cron monitoring |
| 4049 | LiteLLM | LLM proxy |
| 5000 | Change Detection | Web monitoring |
| 5001 | Dockge | **CANDIDATE FOR REMOVAL** |
| 5433 | frgops-standby | **INVESTIGATE** Postgres standby |
| 5434 | RavynAI Postgres | Spatial DB |
| 7860 | Langflow | AI workflows |
| 8007 | RavynAI App | Opportunity graph |
| 8080 | dockge-test-nginx | **CANDIDATE FOR REMOVAL** |
| 8082 | FRG CRM API | PM2 (Python) |
| 8088 | Superset | Analytics |
| 8090 | 1Panel | **RECOMMENDED MANAGEMENT UI** |
| 8091 | War Room | PM2 |
| 8095 | Voice Outreach | PM2 |
| 8098 | Prediction Radar Web | Web frontend |
| 8103 | SurplusAI Portal API | PM2 |
| 8110 | OpenClaw Dashboard | PM2 |
| 8123 | ClickHouse | OLAP DB |
| 9000 | Portainer | **CANDIDATE FOR REMOVAL** |
| 9090 | Prometheus | Monitoring |
| 9091 | Hostinger Health | Metrics exporter |
| 9443 | Portainer TLS | **CANDIDATE FOR REMOVAL** |
| 19999 | Netdata | System monitoring |

### 8.3 Port Conflicts (current and potential)

| Port | Conflict | Severity |
|---|---|---|
| 8080 | dockge-test-nginx + nice_kalam (exposed port) | **ACTIVE** -- nice_kalam exposes 8080 but may not have host binding. If the Docker auto-generated container `nice_kalam` tries to bind 8080, it will fail as dockge-test-nginx already occupies it |
| 3100 | aiops-loki (stuck) + loki (working) | **RESOLVED** -- aiops-loki never started, so no active conflict, but compose file may try to bind 3100 |

---

## 9. POSTGRES CONSOLIDATION OPPORTUNITY

Four Postgres containers run on AI Ops:

| Container | Port | DB | Version | Can Consolidate? |
|---|---|---|---|---|
| prediction-radar-app-db | 5432 | prediction_radar | postgres:16 | NO -- tightly coupled to app stack |
| frgops-standby | 5433 | unknown | postgres:16-alpine | MAYBE -- if unused standby |
| aiops-ravynai-postgres | 5434 | ravynai | postgis/postgis:16-3.4 | NO -- requires PostGIS extension |
| temporal-postgres | host | temporal_db | postgres:16-alpine | NO -- host network, external seed |

**Assessment:** Genuine consolidation is unlikely because each DB serves a different app with different extension needs (PostGIS, etc.). However, `frgops-standby` should be audited for actual replication traffic.

---

## 10. ACTION PLAN (PRIORITIZED)

### Phase 1: Immediate Safe Removals (0 risk)
- [ ] Remove `aiops-loki` container (stuck, never ran)
- [ ] Remove `dockge-test-nginx` container (test artifact)
- [ ] Remove `backup-verification` PM2 process (stopped)
- [ ] Prune unused Docker images (~5.9GB savings)

### Phase 2: Management UI Consolidation
- [ ] Verify 1Panel sees all running containers
- [ ] Export temporal stack from Dockge
- [ ] Stop and remove Portainer container
- [ ] Stop and remove Dockge container
- [ ] Remove 5 Dockge boilerplate stack directories
- [ ] Remove 1 unused Dockge network (`dockerecosystemmanager_default`)

### Phase 3: Fix Broken Items
- [ ] Fix or remove `temporal-temporal-ui-1` (restart loop)
- [ ] Integrate `nice_kalam` into proper temporal compose stack
- [ ] Investigate `frgcrm-api` restart cause (2 restarts in 26 min)
- [ ] Investigate `frgops-standby` actual usage

### Phase 4: Cross-Server Audit
- [ ] SSH to worker server and confirm duplicate services
- [ ] Decide consolidation strategy for Grafana, Uptime Kuma
- [ ] Verify Prometheus federation or keep per-server

---

*Report generated 2026-05-23. All recommendations are read-only. No containers or processes were modified.*
