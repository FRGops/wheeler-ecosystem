# Wheeler Ecosystem — Revenue Application Inventory
## Phase 1: Full Revenue-Critical App Survey

> **Survey date:** 2026-05-23
> **Survey mode:** Read-only — no services stopped, no DNS changed, no configs overwritten
> **Source:** Live process inspection (PM2 + Docker + netstat), ARCHITECTURE.md, environment variables

---

## REVENUE-CRITICAL APPLICATIONS

| # | App Name | Current Location | Public Domain | Port | Process Mgr | DB Dependency | Redis Dependency | AI Dependency | Health Endpoint | Restart Command | Logs Location | Migration Priority | Revenue Risk |
|---|----------|-----------------|---------------|------|-------------|---------------|------------------|---------------|-----------------|-----------------|---------------|--------------------|--------------|
| 1 | **Prediction Radar API** | Hetzner (Docker) | predictionradar.app | 8098 (web), 8000 (API/internal) | Docker Compose | prediction-radar-app-db (PG16 :5432) | prediction-radar-app-redis (:6379) | OpenAI GPT, DeepSeek, Anthropic | http://localhost:8000/health | `docker compose --project-name prediction-radar up -d` | `/var/lib/docker/containers/*/prediction-radar*.log` | P1 — Immediate | CRITICAL |
| 2 | **Prediction Radar Worker** | Hetzner (Docker) | N/A (internal) | N/A | Docker Compose | prediction-radar-app-db | prediction-radar-app-redis | OpenAI GPT, DeepSeek, Anthropic | Internal only | `docker compose --project-name prediction-radar restart worker` | Same as API | P1 | CRITICAL |
| 3 | **Prediction Radar Scheduler** | Hetzner (Docker) | N/A (internal) | N/A | Docker Compose | prediction-radar-app-db | prediction-radar-app-redis | N/A | Internal only | `docker compose --project-name prediction-radar restart scheduler` | Same as API | P1 | CRITICAL |
| 4 | **Prediction Radar Dashboard v2** | Hetzner (Docker) | predictionradar.app | 3000 (internal) | Docker Compose | prediction-radar-app-db | prediction-radar-app-redis | N/A | Internal health check (healthy) | `docker compose --project-name prediction-radar up -d dashboard-v2` | Container logs | P1 | HIGH |
| 5 | **FRGCRM Agent Service** | Hetzner (PM2) | N/A (API/internal) | 8013 (IPv6) | PM2 (fork) | frgops-standby (PG16 :5433) | N/A | N/A (agent logic) | http://localhost:8013/health | `pm2 restart frgcrm-agent-svc` | `~/.pm2/logs/frgcrm-agent-svc-*.log` | P2 | HIGH |
| 6 | **FRGCRM API** | Hetzner (PM2) | N/A | N/A | PM2 (fork) | frgops-standby (PG16 :5433) | N/A | N/A | **ERROred — 15 restarts** | `pm2 restart frgcrm-api` | `~/.pm2/logs/frgcrm-api-*.log` | P2 — CRITICAL FIX | HIGH |
| 7 | **FRGCRM Mirror Test** | Hetzner (PM2) | N/A | 8003 (IPv6) | PM2 (fork) | frgops-standby (PG16 :5433) | N/A | N/A | http://localhost:8003/health | `pm2 restart frgcrm-mirror-test` | `~/.pm2/logs/frgcrm-mirror-test-*.log` | P2 | MEDIUM |
| 8 | **Insforge Agent Service** | Hetzner (PM2) | N/A | 8013 (IPv6 via insforge) | PM2 (fork) | N/A | N/A | N/A | Internal agent | `pm2 restart insforge-agent-svc` | `~/.pm2/logs/insforge-agent-svc-*.log` | P3 | MEDIUM |
| 9 | **SurplusAI Scraper Agent** | Hetzner (PM2) | N/A | N/A | PM2 (fork) | N/A | N/A | N/A | **WAITING — 282 restarts** | `pm2 restart surplusai-scraper-agent-svc` | `~/.pm2/logs/surplusai-scraper-agent-svc-*.log` | P2 | HIGH |
| 10 | **Voice Agent Service** | Hetzner (PM2) | N/A | N/A | PM2 (fork) | N/A | N/A | N/A (voice gateway) | **WAITING — 282 restarts** | `pm2 restart voice-agent-svc` | `~/.pm2/logs/voice-agent-svc-*.log` | P2 | HIGH |
| 11 | **RavynAI API** | Hetzner (Docker) | ravynai.wheeler.ai | 8007 | Docker Compose | aiops-ravynai-postgres (PG16 :5434) | N/A | N/A | http://localhost:8007/health | `docker compose --project-name ravynai up -d` | Container logs | P2 | HIGH |
| 12 | **FRGops / FRGCRM Frontend** | Hostinger | frgops.fundsrecoverygroup.tech | 3000 (Traefik) | Docker Compose | Hostinger PG :5432 | Hostinger Redis :6379 | N/A | Via Traefik | `docker compose up -d` (on Hostinger) | Hostinger docker logs | P2 | HIGH |
| 13 | **Chatwoot** | Hostinger | chatwoot.wheeler.ai | 3000 (Traefik) | Docker Compose | Hostinger PG :5432 | Hostinger Redis :6379 | N/A | Via Traefik | `docker compose up -d` (on Hostinger) | Hostinger docker logs | P3 | MEDIUM |
| 14 | **LiteLLM Proxy** | Hostinger | litellm.wheeler.ai | 4000 (Traefik) | Docker Compose | N/A | N/A | DeepSeek, OpenAI, Anthropic (proxy) | http://localhost:4000/health | `docker compose up -d` (on Hostinger) | Hostinger docker logs | P2 | HIGH |
| 15 | **n8n Workflows** | Hostinger | n8n.wheeler.ai | 5678 (Traefik) | Docker Compose | Hostinger PG :5432 | Hostinger Redis :6379 | N/A | Via Traefik | `docker compose up -d` (on Hostinger) | Hostinger docker logs | P3 | MEDIUM |
| 16 | **Docuseal** | Hostinger → Hetzner | docuseal.wheeler.ai | 3010 (Hetzner Docker) | Docker Compose | N/A | docuseal-redis (:6379) | N/A | http://localhost:3010/health | `docker compose up -d` (on Hetzner) | Container logs | P3 | LOW |
| 17 | **MinIO Object Store** | Hostinger | N/A (admin via Traefik) | 9001 (Traefik) | Docker Compose | N/A | N/A | N/A | http://localhost:9001/minio/health | `docker compose up -d` (on Hostinger) | Hostinger docker logs | P3 | MEDIUM |
| 18 | **Webhook Receiver** | Hostinger | N/A | 9000 (Traefik) | Docker Compose | N/A | N/A | N/A | Custom endpoint | `docker compose up -d` (on Hostinger) | Hostinger docker logs | P2 — Webhook critical | HIGH |
| 19 | **Spiderfoot (OSINT)** | Hetzner (Docker) | N/A (internal) | 8080 | Docker Compose | N/A | N/A | N/A | http://localhost:8080 | `docker compose up -d` | Container logs | P4 | LOW |
| 20 | **ChangeDetection** | Hetzner (Docker) | changedetect.wheeler.ai | 5000 | Docker Compose | N/A | N/A | N/A | http://localhost:5000/api/healthcheck | `docker compose up -d` | Container logs | P3 | LOW |
| 21 | **Langflow** | Hetzner (Docker) | N/A (internal) | 7860 | Docker Compose | SQLite (local) | N/A | DeepSeek, OpenAI, Anthropic | http://localhost:7860/health | `docker compose up -d` | Container logs | P3 | MEDIUM |
| 22 | **Grafana** | Hetzner (Docker) | grafana.wheeler.ai | 3002 | Docker Compose | N/A | N/A | N/A | http://localhost:3002/api/health | `docker compose up -d` | Container logs | P4 | LOW |
| 23 | **Superset** | Hetzner (Docker) | superset.wheeler.ai | 8088 | Docker Compose | ClickHouse | N/A | N/A | http://localhost:8088/health | `docker compose up -d` | Container logs | P4 | LOW |
| 24 | **Uptime Kuma** | Hetzner (Docker) | uptime.wheeler.ai | 3001 | Docker Compose | N/A | N/A | N/A | http://localhost:3001 | `docker compose up -d` | Container logs | P4 | LOW |

---

## PM2 PROCESS DETAIL (Revenue-Critical Only)

```
┌────┬─────────────────────────────┬─────────┬──────────┬──────────┐
│ id │ name                        │ status  │ uptime   │ restarts │
├────┼─────────────────────────────┼─────────┼──────────┼──────────┤
│ 0  │ frgcrm-agent-svc            │ ONLINE  │ 42h      │ 0        │
│ 6  │ frgcrm-api                  │ ERRORED │ 0        │ 15       │  ← NEEDS FIX
│ 4  │ frgcrm-mirror-test          │ ONLINE  │ 42h      │ 0        │
│ 3  │ insforge-agent-svc          │ ONLINE  │ 42h      │ 0        │
│ 1  │ surplusai-scraper-agent-svc │ WAITING │ 0        │ 282+     │  ← NEEDS FIX
│ 2  │ voice-agent-svc             │ WAITING │ 0        │ 282+     │  ← NEEDS FIX
└────┴─────────────────────────────┴─────────┴──────────┴──────────┘
```

---

## DOCKER CONTAINER HEALTH (Revenue-Critical Only)

| Container | Status | Uptime | Health Check |
|-----------|--------|--------|--------------|
| prediction-radar-app-db | Up 43h | healthy | ✅ |
| prediction-radar-app-redis | Up 43h | healthy | ✅ |
| prediction-radar-app-web | Up 43h | N/A | ⚠️ No explicit health check |
| prediction-radar-dashboard-v2 | Up 43h | healthy | ✅ |
| aiops-ravynai-app | Up 43h | healthy | ✅ |
| aiops-ravynai-postgres | Up 43h | healthy | ✅ |
| hostinger-health-exporter | Up 43h | N/A | ⚠️ Monitoring utility |
| frgops-standby | Up 43h | N/A | ⚠️ Standby PG instance |

---

## KEY FINDINGS

### Immediate Revenue Risks

1. **FRGCRM API (PM2 id 6) — ERROred**
   - 15 failed restart attempts
   - **Direct impact:** CRM operations down, lead management offline
   - **Action:** Investigate error logs at `~/.pm2/logs/frgcrm-api-error-*.log`

2. **SurplusAI Scraper Agent (PM2 id 1) — WAITING**
   - 282+ restart attempts, stuck in waiting loop
   - **Direct impact:** SurplusAI data pipeline offline
   - **Action:** Check dependency availability, restart constraints

3. **Voice Agent Service (PM2 id 2) — WAITING**
   - 282+ restart attempts, stuck in waiting loop
   - **Direct impact:** Voice outreach stopped
   - **Action:** Check gateway connectivity, restart constraints

4. **Stripe Keys — Test Mode**
   - `STRIPE_SECRET_KEY=sk_test_*` and `STRIPE_PUBLISHABLE_KEY=pk_test_*` observed in Prediction Radar env
   - **Needs verification:** Are production Stripe keys configured on Hostinger?

### Healthy Revenue-Critical Services

1. Prediction Radar (API + Worker + Scheduler + Dashboard) — fully operational
2. FRGCRM Agent Service — online and stable (42h uptime)
3. RavynAI — healthy, operational
4. FRGCRM Mirror Test — operational for testing

---

## NEXT ACTIONS (Phase 1 Complete)

- [ ] Fix FRGCRM API (errored, 15 restarts)
- [ ] Fix SurplusAI Scraper Agent (waiting, 282 restarts)
- [ ] Fix Voice Agent Service (waiting, 282 restarts)
- [ ] Verify Stripe mode (test vs live) across all services
- [ ] Document actual Hostinger services via remote access
- [ ] Verify COREDB node connectivity
