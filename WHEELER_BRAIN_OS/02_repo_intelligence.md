# Repository & Code Asset Map — Wheeler Brain OS

**Generated:** 2026-05-24  
**Nodes surveyed:** AIOPS (100.121.230.28), COREDB (100.118.166.117)  
**Author:** Repo Intelligence Agent

---

## 1. Git Repositories

### 1.1 AIOPS (wheeler-aiops-01)

| # | Repo Path | Remote | Branch | Recent Activity | Purpose |
|---|-----------|--------|--------|-----------------|---------|
| 1 | `/opt/wheeler-ecosystem` | *(none)* | `master` | Zero Trust Stage 2 enforcement scripts (1d15563, c6d7449) | Wheeler ecosystem orchestration: capabilities, control-plane, playbooks, scripts, enforcement, skills, workflows |
| 2 | `/opt/wheeler-revenue-automation` | *(none)* | `master` | Complete Wheeler Revenue Automation & AI Workforce OS (46a0c58) | Revenue automation platform (local, no remote) |
| 3 | `/opt/openclaw-dashboard` | `github.com/tugcantopaloglu/openclaw-dashboard.git` | `main` | Dockerfile merge (d6198d0) | OpenClaw dashboard — PM2-managed at port 8110 |
| 4 | `/opt/wheeler/apps/frgcrm` | `github.com/FRGops/frgcrm.git` | `main` | Agent service sync, 100% agentic pipeline, postgres fix (6ab0f77, 75bf025, eaa5bbc) | FRG CRM monorepo — main application |
| 5 | `/opt/wheeler/apps/frgcrm/frontend` | `github.com/FRGops/frgops-audits.git` | `main` | Error logging fix, admin routes fix (b6bc092, 1df02f2, 23e4c3a) | Frontend (connected to audits remote — verify) |
| 6 | `/opt/wheeler/apps/frgcrm/docs/tools/higgsfield-seedance-skills` | `github.com/beshuaxian/higgsfield-seedance2-jineng.git` | `main` | CONTRIBUTING.md update (83dcb10) | Fork of seedance skills (docs reference) |
| 7 | `/opt/wheeler/apps/frgcrm/docs/tools/ising` | `github.com/NVIDIA/ising.git` | `main` | README update (08d4068) | NVIDIA Ising solver (docs reference) |
| 8 | `/opt/wheeler/apps/frgcrm/docs/tools/starter-workflows` | `github.com/actions/starter-workflows.git` | `main` | Codeowners merge (b01591e) | GitHub Actions starter workflows (docs reference) |
| 9 | `/opt/wheeler/apps/frgcrm/docs/tools/archon` | `github.com/coleam00/Archon.git` | `dev` | Worktree bypass fix (af9ed84) | Archon MCP framework (docs reference) |

### 1.2 COREDB (wheeler-core-db-01)

| # | Repo Path | Remote | Branch | Recent Activity | Purpose |
|---|-----------|--------|--------|-----------------|---------|
| 1 | `/opt/edge-legacy-backups/wheeler-command-brain` | *(none — bare/empty)* | *(detached)* | *(no commits)* | Legacy backup — appears to be empty shell |
| 2 | `/opt/apps/prediction-radar-app/integrations/sports-odds-fetch` | `github.com/nchemb/sports-odds-fetch.git` | `master` | Game-lines market, spread/total points (0b1b46d) | Sports odds integration for prediction-radar |

---

## 2. PM2 Ecosystem — AIOPS Only

**18 PM2 processes running** on AIOPS (no PM2 on COREDB).

### 2.1 Main Ecosystem (`/opt/apps/ecosystem.config.js`)

| # | PM2 App Name | Type | Port | Script | Status |
|---|-------------|------|------|--------|--------|
| 1 | `frgcrm-agent-svc` | Node.js/Agent | 8003 | `dist/index.js` | online |
| 2 | `surplusai-scraper-agent-svc` | Node.js/Agent | 8007 | `dist/index.js` | online |
| 3 | `voice-agent-svc` | Node.js/Agent | 8008 | `dist/index.js` | online |
| 4 | `insforge-agent-svc` | Node.js/Agent | 8013 | `dist/index.js` | online |

### 2.2 App-Specific PM2 Configs

| # | PM2 App Name | Config Location | Type | Port | Script / Args |
|---|-------------|-----------------|------|------|---------------|
| 5 | `frgcrm-api` | `/opt/wheeler/apps/frgcrm/api/ecosystem.config.js` | Python/FastAPI | 8082 | `uvicorn main:app --host 127.0.0.1 --port 8082 --workers 4` |
| 6 | `frgcrm-agent-svc` (v2) | `/opt/wheeler/apps/frgcrm/agents-service/ecosystem.config.js` | Node.js | 8003 | `dist/index.js` (internal token auth) |
| 7 | `voice-outreach-service` | `/opt/wheeler/apps/frgcrm/voice_outreach_service/ecosystem.config.js` | Python/FastAPI | 8095 | `uvicorn app:app --host 127.0.0.1 --port 8095` |
| 8 | `litellm` | `/opt/apps/litellm/ecosystem.config.js` | Python/LiteLLM | 4049 | `litellm --config ... --port 4049 --host 127.0.0.1` |
| 9 | `surplusai-portal-api` | `/opt/apps/surplusai-portal/ecosystem.config.js` | Python/FastAPI | 8103 | `uvicorn main:app --host 127.0.0.1 --port 8103` |
| 10 | `war-room-server` | `/opt/apps/war-room/ecosystem.config.js` | Python/FastAPI | 8091 | `uvicorn server:app --host 127.0.0.1 --port 8091` |
| 11 | `openclaw-dashboard` | `/opt/openclaw-dashboard/ecosystem.config.js` | Node.js | 8110 | `node ./server.js` |
| 12 | `ecosystem-guardian` | `/opt/apps/wheeler-brain-os/ecosystem.config.js` | Node.js | — | `node ...ecosystem-guardian.js --daemon --interval 60000` |
| 13 | `backup-verification` | `/opt/apps/wheeler-brain-os/ecosystem.config.js` | Bash | — | `backup-verify.sh` (cron: daily 6AM, currently stopped) |
| 14 | `event-bus-relay` | `/opt/apps/wheeler-brain-os/ecosystem.config.js` | Node.js | — | `node ...events/relay.js` |
| 15 | `ravynai-opportunity-graph` | `/opt/apps/ravynai-opportunity-graph/ecosystem.config.js` | Node.js | 8007 | `node ./dist/index.js` |
| 16 | `ravynai-og-scheduler` | `/opt/apps/ravynai-opportunity-graph/ecosystem.config.js` | Node.js | — | `node ./dist/scheduler.js` |

### 2.3 Individual Agent-Service EC Configs (`/opt/apps/*-agent-svc/ecosystem.config.js`)

Additional standalone ecosystem configs exist for:
- `ravyn-agent-svc`
- `insforge-agent-svc`
- `prediction-radar-agent-svc`
- `horizon-agent-svc`
- `paperless-agent-svc`
- `wheeler-brain-os`
- `voice-agent-svc`
- `design-agent-svc`
- `surplusai-scraper-agent-svc`

**Note:** Some duplicate entries exist at `/opt/opt/apps/` — likely artifacts from a prior migration.

### 2.4 PM2 Running Status Snapshot

| Name | PID | Uptime | Restarts | Mem | Status |
|------|-----|--------|----------|-----|--------|
| ecosystem-guardian | 2203814 | 61m | 0 | 55.5MB | online |
| event-bus-relay | 2203825 | 61m | 0 | 57.3MB | online |
| litellm | 2204072 | 61m | 0 | 354.8MB | online |
| openclaw-dashboard | 2203591 | 61m | 0 | 55.5MB | online |
| voice-outreach-service | 2203676 | 61m | 0 | 53.5MB | online |
| war-room-server | 2203976 | 61m | 0 | 59.9MB | online |
| surplusai-scraper-agent-svc | 2203301 | 61m | 0 | 97.3MB | online |
| voice-agent-svc | 2203501 | 61m | 0 | 91.6MB | online |
| paperless-agent-svc | 2203073 | 61m | 0 | 91.6MB | online |
| ravyn-agent-svc | 2203149 | 61m | 0 | 97.7MB | online |
| horizon-agent-svc | 2202921 | 61m | 0 | 93.6MB | online |
| design-agent-svc | 2326467 | 12m | 2 | 89.6MB | online |
| frgcrm-agent-svc | 2323395 | 13m | 0 | 86.1MB | online |
| frgcrm-api | 2323837 | 13m | 0 | 235.0MB | online |
| insforge-agent-svc | 2323496 | 13m | 0 | 65.8MB | online |
| prediction-radar-agent-svc | 2323937 | 13m | 0 | 100.8MB | online |
| surplusai-portal-api | 2323606 | 13m | 0 | 103.7MB | online |
| backup-verification | 0 | 0 | 0 | 0B | **stopped** |

**Module:** pm2-logrotate v3.0.0 (PID 2201890, 84.9MB)

---

## 3. Node.js / npm Applications (package.json)

### 3.1 AIOPS — `/opt/apps/`

| Path | Name | Version |
|------|------|---------|
| `/opt/apps/frg-site` | frg-site | 1.0.0 |
| `/opt/apps/ravyn-agent-svc` | ravyn-agent-svc | 1.0.0 |
| `/opt/apps/insforge-agent-svc` | insforge-agent-svc | 1.0.0 |
| `/opt/apps/prediction-radar-agent-svc` | prediction-radar-agent-svc | 1.0.0 |
| `/opt/apps/frgcrm-agent-svc` | agents-service | 1.0.0 |
| `/opt/apps/horizon-agent-svc` | horizon-agent-svc | 1.0.0 |
| `/opt/apps/design-agent-svc` | design-agent-svc | 1.0.0 |
| `/opt/apps/voice-agent-svc` | voice-agent-svc | 1.0.0 |
| `/opt/apps/surplusai-scraper-agent-svc` | surplusai-scraper-agent-svc | 1.0.0 |
| `/opt/apps/agent-platform` | agent-platform | 1.0.0 |
| `/opt/apps/paperless-agent-svc` | paperless-agent-svc | 1.0.0 |
| `/opt/apps/wheeler-brain-os` | wheeler-brain-os | 0.1.0 |
| `/opt/apps/ravynai-opportunity-graph` | ravynai-opportunity-graph | 0.1.0 |

---

## 4. Docker Compose Stacks

### 4.1 AIOPS Stacks

| Compose File | Containers | Images | Ports |
|-------------|-----------|--------|-------|
| `/opt/open-webui/docker-compose.yml` | open-webui | `ghcr.io/open-webui/open-webui:main` | 127.0.0.1:3000->8080 |
| `/opt/stacks/temporal/docker-compose.yml` | temporal-server, temporal-ui | `temporalio/auto-setup:1.29.3`, `temporalio/ui:2.50.0` | 127.0.0.1:7233, 127.0.0.1:8089 |
| `/opt/apps/changedetection/docker-compose.yml` | aiops-changedetection | `ghcr.io/dgtlmoon/changedetection.io:0.55.3` | 127.0.0.1:5000->5000 |
| `/opt/apps/ravynai-opportunity-graph/docker-compose.yml` | aiops-ravynai-postgres, aiops-ravynai-app | `postgis/postgis:16-3.4`, local build | 127.0.0.1:5434, 127.0.0.1:8007 |
| `/opt/apps/monitoring/docker-compose.yml` | aiops-prometheus, aiops-alertmanager, aiops-grafana, hostinger-health-exporter, aiops-loki, aiops-webhook-relay, aiops-pushgateway | `prom/prometheus:v2.55.1`, `prom/alertmanager:v0.28.1`, `grafana/grafana:11.5.1`, `python:3.12-alpine`, `grafana/loki:3.6.3`, `prom/pushgateway:v1.11.2` | All 127.0.0.1 (9090, 9093, 3002, 9091, 3100, 8085, 9092) |
| `/opt/apps/healthchecks/docker-compose.yml` | aiops-healthchecks | `lscr.io/linuxserver/healthchecks:v4.2-ls344` | 127.0.0.1:3130->8000 |
| `/opt/apps/prediction-radar-app/docker-compose.yml` | db, db-backup, redis, api, web, dashboard-v2, worker, scheduler, prometheus, alertmanager, grafana, uptime-kuma, market-analysis, fail2ban, crowdsec, fincept-terminal | postgres:16, redis:7, local builds, prom/prometheus:v2.53.0, grafana/grafana:11.1.0, prom/alertmanager:v0.27.0, louislam/uptime-kuma:1, crazymax/fail2ban, crowdsecurity/crowdsec | 127.0.0.1:8098, internal only |
| `/opt/apps/langflow/docker-compose.yml` | langflow | `langflowai/langflow:1.0.19` | 127.0.0.1:7860->7860 |
| `/opt/apps/analytics/docker-compose.yml` | aiops-clickhouse, aiops-superset | `clickhouse/clickhouse-server:24.3`, `apache/superset:4.1.1` | 127.0.0.1:8123, 127.0.0.1:8088 |
| `/opt/apps/promtail/docker-compose.yml` | promtail | `grafana/promtail:3.6.8` | 127.0.0.1:9080 |
| `/opt/apps/usesend/docker-compose.yml` | usesend | `usesend/usesend:pinned-2026-05-24` | 100.121.230.28:3007, 127.0.0.1:3007 |
| `/opt/apps/docuseal/docker-compose.yml` | docuseal, docuseal-redis | `docuseal/docuseal:3.0.0`, `redis:7-alpine` | 127.0.0.1:3010->3000 |

### 4.2 COREDB Stacks

| Compose File | Containers | Images | Ports |
|-------------|-----------|--------|-------|
| `/opt/wheeler-monitoring/docker-compose.yml` | wheeler-grafana, wheeler-prometheus, wheeler-loki, wheeler-uptime-kuma | `grafana/grafana:latest`, `prom/prometheus:latest`, `grafana/loki:latest`, `louislam/uptime-kuma:latest` | 100.118.166.117:3000, 9090, 127.0.0.1:3100, 127.0.0.1:3001 |
| `/opt/temporal/docker-compose.yml` | temporal-server, temporal-ui | `temporalio/auto-setup:latest`, `temporalio/ui:latest` | 127.0.0.1:7233, 127.0.0.1:8080 |
| `/opt/wheeler-core/docker-compose.yml` | wheeler-postgres, wheeler-redis, wheeler-minio | `postgres:16`, `redis:7`, `minio/minio:latest` | 100.118.166.117:5432, :6379, 127.0.0.1:9000-9001 |
| `/opt/apps/usesend/docker-compose.yml` | usesend | `usesend/usesend:latest` | *(details N/A)* |
| `/opt/apps/prediction-radar-app/docker-compose.yml` | prediction-radar-db, prediction-radar-redis, prediction-radar-api, worker, scheduler | `postgres:16`, `redis:7`, local builds | Internal |
| `/opt/apps/prediction-radar/docker-compose.yml` | prediction-radar-worker, prediction-radar-scheduler | `prediction-radar-worker:latest`, `prediction-radar-scheduler:latest` | Internal |
| `/opt/apps/temporal-pipeline/docker-compose.yml` | temporal-pipeline-worker, temporal-pipeline-scheduler | `temporal-pipeline:latest` | Internal |

### 4.3 Stacks (Config-Only — `/opt/stacks/`)

| Stack Dir | Purpose |
|-----------|---------|
| `/opt/stacks/01-monitoring` | Monitoring stack config |
| `/opt/stacks/02-aiops` | AI Ops stack config |
| `/opt/stacks/03-openclaw-staging` | OpenClaw staging config |
| `/opt/stacks/04-brain-staging` | Wheeler Brain staging config |
| `/opt/stacks/05-frgops-staging` | FRG Ops staging config |
| `/opt/stacks/dockerecosystemmanager` | Docker ecosystem manager config |
| `/opt/stacks/temporal` | Temporal stack config |

---

## 5. Directory Structure — `/opt/` on AIOPS

```
/opt/
  apps/                      # Application deployments (37 entries)
    agent-platform/           # Agent orchestration platform
    analytics/                # ClickHouse + Superset analytics
    changedetection/          # Website change detection
    design-agent-svc/        # Design AI agent service
    docuseal/                 # Document signing
    frgcrm/                   # FRG CRM voice outreach service
    frgcrm-agent-svc/        # FRG CRM agent service
    frgops-standby/           # FRG Ops standby (Postgres replica)
    frg-site/                 # FRG website
    healthchecks/             # Health check monitoring
    horizon-agent-svc/        # Horizon AI agent service
    insforge-agent-svc/      # Insforge agent service
    langflow/                 # Langflow low-code AI
    litellm/                  # LiteLLM proxy
    monitoring/               # Prometheus + Grafana stack
    paperless-agent-svc/     # Paperless agent service
    prediction-radar/        # Prediction radar (legacy)
    prediction-radar-agent-svc/  # Prediction radar agent service
    prediction-radar-app/    # Main prediction radar app
    promtail/                 # Log shipping
    ravynai/                  # RavynAI (legacy)
    ravynai-opportunity-graph/  # Opportunity graph app
    ravyn-agent-svc/         # Ravyn agent service
    surplusai-portal/        # SurplusAI portal
    surplusai-scraper-agent-svc/  # SurplusAI scraper
    usesend/                  # UseSend email platform
    voice-agent-svc/         # Voice AI agent service
    war-room/                 # War room dashboard
    wheeler-brain-os/        # Wheeler Brain OS core
  stacks/                    # Deployment stack configs
  open-webui/                # Open WebUI
  openclaw-dashboard/        # OpenClaw dashboard
  wheeler/                   # Wheeler core apps
    apps/
      frgcrm/                # FRG CRM monorepo
  wheeler-ecosystem/         # Wheeler ecosystem (capabilities, scripts, skills)
  wheeler-revenue-automation/  # Revenue automation engine
```

---

## 6. Running Docker Containers

### 6.1 AIOPS (29 containers)

| Container | Image | Status | Exposed Ports |
|-----------|-------|--------|---------------|
| open-webui | ghcr.io/open-webui/open-webui:main | healthy | 127.0.0.1:3000 |
| temporal-server | temporalio/auto-setup:1.29.3 | healthy | 127.0.0.1:7233 |
| temporal-ui | temporalio/ui:2.50.0 | healthy | 127.0.0.1:8089 |
| aiops-changedetection | dgtlmoon/changedetection.io:0.55.3 | healthy | 127.0.0.1:5000 |
| aiops-ravynai-postgres | postgis/postgis:16-3.4 | healthy | 127.0.0.1:5434 |
| aiops-ravynai-app | ravynai-opportunity-graph-app | healthy | 127.0.0.1:8007 |
| aiops-prometheus | prom/prometheus:v2.55.1 | healthy | 127.0.0.1:9090 |
| aiops-alertmanager | prom/alertmanager:v0.28.1 | healthy | 127.0.0.1:9093 |
| aiops-grafana | grafana/grafana:11.5.1 | healthy | 127.0.0.1:3002 |
| hostinger-health-exporter | python:3.12-alpine | healthy | 127.0.0.1:9091 |
| aiops-loki | grafana/loki:3.6.3 | healthy | 127.0.0.1:3100 |
| aiops-webhook-relay | python:3.12-alpine | healthy | 127.0.0.1:8085 |
| aiops-pushgateway | prom/pushgateway:v1.11.2 | healthy | 127.0.0.1:9092 |
| aiops-healthchecks | linuxserver/healthchecks:v4.2-ls344 | healthy | 127.0.0.1:3130 |
| aiops-clickhouse | clickhouse/clickhouse-server:24.3 | healthy | 127.0.0.1:8123 |
| aiops-superset | apache/superset:4.1.1 | healthy | 127.0.0.1:8088 |
| prediction-radar-app-db | postgres:16 | healthy | internal |
| prediction-radar-app-redis | redis:7 | healthy | internal |
| prediction-radar-app-api | prediction-radar-app-api | healthy | internal |
| prediction-radar-app-web | prediction-radar-app-web | healthy | 127.0.0.1:8098 |
| prediction-radar-app-db-backup-1 | prodrigestivill/postgres-backup-local:16 | healthy | internal |
| prediction-radar-app-worker | prediction-radar-app-worker | healthy | internal |
| prediction-radar-app-scheduler | prediction-radar-app-scheduler | healthy | internal |
| prediction-radar-dashboard-v2 | prediction-radar-app-dashboard-v2 | healthy | internal |
| prediction-radar-prometheus | prom/prometheus:v2.53.0 | healthy | internal |
| prediction-radar-alertmanager | prom/alertmanager:v0.27.0 | healthy | internal |
| prediction-radar-grafana | grafana/grafana:11.1.0 | healthy | internal |
| prediction-radar-uptime-kuma | louislam/uptime-kuma:1 | healthy | internal |
| prediction-radar-crowdsec | crowdsecurity/crowdsec | up | internal |
| prediction-radar-fail2ban | crazymax/fail2ban | healthy | host net |
| prediction-radar-fincept | prediction-radar-app-fincept-terminal | up | internal |
| promtail | grafana/promtail:3.6.8 | healthy | 127.0.0.1:9080 |
| usesend | usesend/usesend:pinned-2026-05-24 | healthy | 100.121.230.28:3007, 127.0.0.1:3007 |
| docuseal | docuseal/docuseal:3.0.0 | healthy | 127.0.0.1:3010 |
| docuseal-redis | redis:7-alpine | healthy | internal |
| frgops-standby | postgres:16-alpine | healthy | 127.0.0.1:5433 |
| uptime-kuma-backup | louislam/uptime-kuma:1 | healthy | 3001/tcp |

### 6.2 COREDB (19 containers)

| Container | Image | Status | Exposed Ports |
|-----------|-------|--------|---------------|
| wheeler-postgres | postgres:16 | healthy | 100.118.166.117:5432 |
| wheeler-redis | redis:7 | healthy | 100.118.166.117:6379 |
| wheeler-minio | minio/minio:latest | healthy | 127.0.0.1:9000-9001 |
| wheeler-grafana | grafana/grafana:latest | healthy | 100.118.166.117:3000 |
| wheeler-prometheus | prom/prometheus:latest | healthy | 100.118.166.117:9090 |
| wheeler-loki | grafana/loki:latest | healthy | 127.0.0.1:3100 |
| wheeler-uptime-kuma | louislam/uptime-kuma:latest | healthy | 127.0.0.1:3001 |
| temporal-server | temporalio/auto-setup:latest | healthy | 127.0.0.1:7233 |
| temporal-ui | temporalio/ui:latest | healthy | 127.0.0.1:8080 |
| prediction-radar-worker | prediction-radar-worker:latest | healthy | internal |
| prediction-radar-scheduler | prediction-radar-scheduler:latest | healthy | internal |
| temporal-pipeline-worker | temporal-pipeline:latest | healthy | internal |
| temporal-pipeline-scheduler | temporal-pipeline:latest | healthy | internal |
| usesend | usesend/usesend:latest | healthy | 127.0.0.1:3007 |
| aiops-pushgateway | prom/pushgateway:latest | healthy | 127.0.0.1:9092 |
| promtail | grafana/promtail:latest | healthy | internal |
| node-exporter | prom/node-exporter:latest | healthy | internal |
| postgres-exporter | prometheuscommunity/postgres-exporter | healthy | internal |
| redis-exporter | oliver006/redis_exporter | healthy | internal |

---

## 7. Environment Files (`.env` — paths only)

### 7.1 AIOPS

```
/opt/apps/analytics/.env
/opt/apps/design-agent-svc/.env
/opt/apps/docuseal/.env
/opt/apps/frgcrm-agent-svc/.env
/opt/apps/frgcrm/voice_outreach_service/.env
/opt/apps/horizon-agent-svc/.env
/opt/apps/insforge-agent-svc/.env
/opt/apps/langflow/.env
/opt/apps/monitoring/.env
/opt/apps/paperless-agent-svc/.env
/opt/apps/prediction-radar-agent-svc/.env
/opt/apps/prediction-radar-app/.env
/opt/apps/ravyn-agent-svc/.env
/opt/apps/ravynai-opportunity-graph/.env
/opt/apps/surplusai-portal/.env
/opt/apps/surplusai-scraper-agent-svc/.env
/opt/apps/usesend/.env
/opt/apps/voice-agent-svc/.env
/opt/openclaw-dashboard/runtime/.env
/opt/open-webui/.env
/opt/opt/apps/design-agent-svc/.env            # Duplicate artifact
/opt/opt/apps/prediction-radar-agent-svc/.env   # Duplicate artifact
/opt/opt/apps/ravyn-agent-svc/.env              # Duplicate artifact
/opt/stacks/01-monitoring/.env
/opt/stacks/02-aiops/.env
/opt/stacks/03-openclaw-staging/.env
/opt/stacks/04-brain-staging/.env
/opt/stacks/05-frgops-staging/.env
/opt/stacks/dockerecosystemmanager/.env
/opt/stacks/temporal/.env
/opt/wheeler/apps/frgcrm/.env
/opt/wheeler/apps/frgcrm/agents-service/.env
/opt/wheeler/apps/frgcrm/api/.env
/opt/wheeler/apps/frgcrm/voice_outreach_service/.env
```

### 7.2 COREDB

```
/opt/temporal/.env
/opt/wheeler-core/.env
/opt/apps/prediction-radar-app/.env
```

---

## 8. Application Architecture Summary

### Agent Services (Node.js — PM2 managed)
Each agent-svc is a self-contained Node.js app running as a PM2 fork process. They communicate via internal HTTP to API gateways and use DeepSeek as the LLM backend.

| Service | Port | Function |
|---------|------|----------|
| frgcrm-agent-svc | 8003 | CRM agent orchestration |
| surplusai-scraper-agent-svc | 8007 | Market data scraping |
| voice-agent-svc | 8008 | Voice AI processing |
| insforge-agent-svc | 8013 | Insurance/Benefits agent |
| ravyn-agent-svc | — (auto) | Ravyn AI agent |
| horizon-agent-svc | — (auto) | Horizon AI agent |
| design-agent-svc | — (auto) | Design AI agent |
| paperless-agent-svc | — (auto) | Paperless document agent |
| prediction-radar-agent-svc | — (auto) | Prediction market agent |

### API Services (Python FastAPI — PM2 managed)
| Service | Port | Function |
|---------|------|----------|
| frgcrm-api | 8082 | CRM backend API (4 workers) |
| voice-outreach-service | 8095 | Voice outreach automation |
| surplusai-portal-api | 8103 | SurplusAI portal backend |
| war-room-server | 8091 | War room dashboard backend |

### Infrastructure Services
| Service | Port | Function |
|---------|------|----------|
| litellm | 4049 | LLM API proxy (DeepSeek) |
| openclaw-dashboard | 8110 | OpenClaw monitoring dashboard |
| temporal-server | 7233 | Temporal workflow engine (AIOPS + COREDB) |
| temporal-ui | 8089/8080 | Temporal web UI |

---

## 9. Key Observations

1. **No remote for wheeler-ecosystem** — the main orchestration repository at `/opt/wheeler-ecosystem` has no git remote configured. This is a single-source risk: no off-machine backup or collaboration.

2. **No remote for wheeler-revenue-automation** — same single-source risk.

3. **Duplicate ecosystem configs** — `/opt/apps/ecosystem.config.js` serves as the primary PM2 config for 4 core agent services. However, individual `ecosystem.config.js` files also exist in each app directory. Some of these may be stale/unused.

4. **Duplicate /opt/opt/apps/** — contains stale copies of 3 agent-service directories. Likely artifacts from a prior deployment or migration.

5. **COREDB uses `:latest` tags** extensively (grafana, prometheus, loki, minio, temporal, uptime-kuma) — this is a stability risk.

6. **AIOPS uses pinned versions** for most containers — better practice.

7. **18 PM2 processes + 29 Docker containers** running on AIOPS; 19 Docker containers on COREDB. **No PM2 processes on COREDB.**

8. **frgcrm frontend repo has a mismatched remote** — the frontend at `/opt/wheeler/apps/frgcrm/frontend` points to `github.com/FRGops/frgops-audits.git` instead of the expected frgcrm frontend repo.

9. **`.env` file sprawl** — 34 `.env` files across AIOPS, 3 on COREDB. Several duplicates at `/opt/opt/apps/`. Recommend audit and consolidation.

10. **Backup-verification PM2 process is stopped** — scheduled cron task not currently operational.

---

*End of Repository & Code Asset Map*
