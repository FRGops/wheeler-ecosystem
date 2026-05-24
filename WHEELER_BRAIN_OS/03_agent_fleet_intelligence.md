# Agent Fleet Intelligence Map — Wheeler Brain OS

**Generated:** 2026-05-24
**Source:** AIOPS (100.121.230.28 — wheeler-aiops-01, Hetzner CPX51)
**Operator:** Wheeler AIOPS Control Plane
**Status:** All agents operational unless noted

---

## 1. LLM ROUTING INFRASTRUCTURE

### LiteLLM Proxy (PM2 — Port 4049)
- **Status:** online (mem: 354.8MB — largest PM2 consumer)
- **Config:** `/root/.claude/litellm-deepseek.yaml`
- **Mode:** Local proxy at `127.0.0.1:4049/v1`
- **Cache:** Redis-backed (hosted on Core-DB)
- **Database:** Shared PostgreSQL (for spend tracking/routing)

#### Routed Models

| Model Name | Provider | Backend Model | Rate Limit |
|---|---|---|---|
| `deepseek-chat` | DeepSeek | `openai/deepseek-chat` | 1000 RPM |
| `deepseek-reasoner` | DeepSeek | `openai/deepseek-reasoner` | 500 RPM |
| `claude-sonnet-4` | Anthropic | `anthropic/claude-sonnet-4-20250514` | 100 RPM |
| `claude-opus-4` | Anthropic | `anthropic/claude-opus-4-20250514` | 50 RPM |
| `premium_review` | Anthropic | `anthropic/claude-sonnet-4-20250514` | 100 RPM |

**Secrets consumed:** DEEPSEEK_API_KEY, ANTHROPIC_API_KEY, LITELLM_MASTER_KEY (from `/opt/apps/.env.shared`)

---

## 2. AI AGENT SERVICES (PM2-MANAGED)

All agent services share a common architecture:
- **Runtime:** Node.js (compiled TypeScript in `dist/index.js`)
- **Wrapper:** `/opt/wheeler-ecosystem/scripts/pm2-env-wrapper.sh` (injects `/opt/apps/.env.shared` secrets)
- **Model:** `deepseek-chat` via LiteLLM proxy at `http://localhost:4049/v1`
- **Polling:** 300,000ms (5 min) interval
- **Memory limit:** 500MB each
- **Autorestart:** Yes (max 10 retries, 5s delay)

### 2.1 Domain-Specific Agent Services

| Agent Service | Port | CWD | Purpose / Domain | External Dependencies |
|---|---|---|---|---|
| **frgcrm-agent-svc** | 8003 | `/opt/apps/frgcrm-agent-svc` | FRG CRM operations agent | FRGCRM API (Hostinger:8002), FRGOPS API (Hostinger:8001) |
| **ravyn-agent-svc** | 8005 | `/opt/apps/ravyn-agent-svc` | RavynAI opportunity graph agent | RavynAI app (localhost:8007), FRGCRM API |
| **horizon-agent-svc** | 8006 | `/opt/apps/horizon-agent-svc` | Horizon scanning / monitoring agent | LiteLLM proxy only |
| **surplusai-scraper-agent-svc** | 8007 | `/opt/apps/surplusai-scraper-agent-svc` | Surplus asset lifecycle scraper | SurplusAI Portal API (localhost:8103) |
| **voice-agent-svc** | 8008 | `/opt/apps/voice-agent-svc` | Voice call handling/outreach | LiteLLM, Twilio, ElevenLabs |
| **paperless-agent-svc** | 8009 | `/opt/apps/paperless-agent-svc` | Document processing agent | LiteLLM proxy only |
| **prediction-radar-agent-svc** | 8011 | `/opt/apps/prediction-radar-agent-svc` | Prediction market analysis | Prediction Radar API (Docker:8000 internal) |
| **insforge-agent-svc** | 8013 | `/opt/apps/insforge-agent-svc` | InsForge insurance operations | InsForge API (Hostinger:7130), PostgREST (Hostinger:5430) |
| **design-agent-svc** | 8020 | `/opt/apps/design-agent-svc` | Design/generation agent | LiteLLM proxy only |

### 2.2 Infrastructure AI Services (PM2)

| Service | Port | Runtime | Purpose |
|---|---|---|---|
| **litellm** | 4049 | Python | LLM API proxy/router (all agents go through this) |
| **ecosystem-guardian** | — | Node.js | Ecosystem health/guardian daemon |
| **event-bus-relay** | 6399 | Node.js | Inter-service event relay bus |
| **war-room-server** | 8091 | Python (FastAPI) | Incident war room coordination |
| **openclaw-dashboard** | 8110 | Node.js | OpenClaw multi-agent dashboard |
| **frgcrm-api** | 8082 | Python (FastAPI/uvicorn 4 workers) | FRG CRM REST API (2GB mem limit) |
| **surplusai-portal-api** | 8103 | Python (FastAPI/uvicorn) | SurplusAI Portal API |
| **voice-outreach-service** | 8095 | Python (FastAPI/uvicorn) | Voice outreach automation |
| **backup-verification** | — | — | **STATUS: STOPPED** — backup verification service |

---

## 3. CLAUDE CODE AGENTS (DEFINED IN `/root/.claude/agents/`)

These are AI agent personas running inside Claude Code, each with a specialized domain.

### 3.1 Wheeler System Agents

| Agent | File | Domain | Safety Model |
|---|---|---|---|
| **wheeler-worker-agent** | `wheeler-worker-agent.md` | Core-DB ops, Temporal workflows, data pipelines | READ-ONLY; requires AI Ops approval for changes |
| **wheeler-deploy-agent** | `wheeler-deploy-agent.md` | Safe deployments, canary, rollback, smoke tests | 7 pre-deploy gates; automated rollback protocol |
| **wheeler-db-agent** | `wheeler-db-agent.md` | PostgreSQL, backups, replication, query analysis | READ-ONLY by default; no DDL/DML without approval |
| **wheeler-infra-agent** | `wheeler-infra-agent.md` | Docker, PM2, networking, systemd, system health | READ-ONLY; never modify port bindings without rollback |
| **wheeler-security-agent** | `wheeler-security-agent.md` | Secrets scanning, firewall, SSH hardening, CVEs | NEVER output actual secrets; CRITICAL/HIGH/MEDIUM/LOW |
| **wheeler-mac-agent** | `wheeler-mac-agent.md` | macOS operations, operator cockpit, Tailscale sync | Approval cockpit, not auto-deploy source |

### 3.2 Engineering Agents

| Agent | File | Domain | Description |
|---|---|---|---|
| **engineering-sre** | `engineering-sre.md` | SLOs, error budgets, observability, chaos engineering | Data-driven reliability engineering |
| **engineering-code-reviewer** | `engineering-code-reviewer.md` | Code quality, correctness, security, performance | Constructive, educational review style |
| **docker-expert** | `docker-expert.md` | Dockerfile optimization, multi-stage builds, security hardening | Targets <100MB images, zero critical vulns |
| **devops-smoke-tester** | `devops-smoke-tester.md` | Build verification, deployment checks, CI/CD integrity | Smoke test creation and execution |
| **database-rls-auditor** | `database-rls-auditor.md` | PostgreSQL RLS, Prisma schema, migration safety | Migration safety review, multi-tenant isolation |
| **zero-false-green-auditor** | `zero-false-green-auditor.md` | Claim verification, evidence auditing | Pre-deploy verification integrity checks |

---

## 4. CLAUDE CODE AUTOMATION COMMANDS (`/root/.claude/commands/`)

| Command | Purpose |
|---|---|
| **agent-army** | Multi-agent orchestration commands |
| **audit** | Full ecosystem audit |
| **cost-control** | Cost monitoring and optimization |
| **daily-health** | Quick daily health pulse across all components |
| **db-lockdown** | Database security audit & lockdown |
| **deploy-safe** | Safe deployment with pre-flight checks |
| **docker-health** | Full Docker container audit |
| **ecosystem-map** | Complete topology map generation |
| **fix** | Automated issue remediation |
| **goal** | Goal tracking / OKR management |
| **incident-response** | Incident diagnosis and response |
| **no-false-greens** | Verification integrity enforcement |
| **pm2-health** | PM2 process health audit |
| **private-network** | Network security audit (Tailscale, UFW, Docker) |
| **production-readiness** | Pre-production readiness verification |
| **repo-router** | Repository management / routing |
| **rollback** | Safe rollback procedures |
| **secrets-scan** | Full credential/secret scan |
| **slay** | Sync session to Wheeler Command Brain vault |
| **superpowers** | Full capabilities registry |

---

## 5. OPENCLAW MULTI-AGENT SYSTEM

### Configuration
- **Dashboard:** Port 8110 (PM2, online, 55.9MB)
- **Config:** `/opt/openclaw-dashboard/ecosystem.config.cjs`
- **Workspace:** `/opt/openclaw-dashboard`
- **Runtime dir:** `/root/.openclaw` (configured but empty — no files found)
- **Agent mode:** OPENCLAW_AGENT configured
- **Auth:** DASHBOARD_AUTH_DIR configured

### Connections
- **LiteLLM:** Would connect via `http://127.0.0.1:4049` (standard pattern)
- **Core-DB:** PostgreSQL via DATABASE_URL, Redis via REDIS_URL
- **FRG CRM:** Used by frgcrm system for dashboard API operations

### Archive History
- Previous env configuration archived at: `/opt/wheeler-cleanup-governance/archive-manifests/stale-envs/openclaw-dashboard-runtime-env-20260523`
- Original FRG CRM config referenced: `DASHBOARD_PORT=8110, OPENCLAW_DIR=/root/.openclaw, WORKSPACE_DIR=/opt/openclaw-dashboard`

---

## 6. LANGFLOW AI WORKFLOW BUILDER

- **Container:** `langflowai/langflow:1.0.19`
- **Status:** Healthy (Docker)
- **Port:** `127.0.0.1:7860` (locked down from 0.0.0.0 in AI Ops remediation)
- **Config:** `/opt/apps/langflow/.env`
- **Auth:** LANGFLOW_SUPERUSER_PASSWORD configured
- **Use case:** Visual AI workflow builder / low-code agent orchestration

---

## 7. OPEN WEBUI — CHAT INTERFACE

- **Container:** `ghcr.io/open-webui/open-webui:main`
- **Status:** Healthy
- **Port:** `127.0.0.1:3000` (locked down)
- **Use case:** Self-hosted ChatGPT-like interface, connected to LiteLLM backend

---

## 8. PM2 INFRASTRUCTURE SERVICES

| Service | Status | CPU | Memory | Port | Notes |
|---|---|---|---|---|---|
| pm2-logrotate | online | 0.2% | 84.9MB | — | Log rotation daemon |
| ecosystem-guardian | online | 0.0% | 55.5MB | — | Ecosystem health watchdog |
| event-bus-relay | online | 0.0% | 57.3MB | 6399 | Inter-service messaging |
| war-room-server | online | 0.2% | 59.9MB | 8091 | Incident coordination |
| openclaw-dashboard | online | 0.0% | 55.9MB | 8110 | Multi-agent dashboard |
| frgcrm-api | online | 0.2% | 235.0MB | 8082 | CRM API (4 workers) |
| surplusai-portal-api | online | 0.0% | 103.7MB | 8103 | SurplusAI portal |
| voice-outreach-service | online | 0.0% | 53.5MB | 8095 | Voice outreach |
| backup-verification | **stopped** | 0.0% | 0.0MB | — | Backup verification service |
| litellm | online | 0.2% | **354.8MB** | 4049 | LLM proxy (largest consumer) |

---

## 9. AUTOMATION TRIGGERS & SCHEDULED TASKS

### 9.1 Crontab — User Scheduled Tasks

| Schedule | Command | Purpose |
|---|---|---|
| `*/5 * * * *` | `wheeler-lockdown-watchdog.sh` | Enforce network lockdown rules |

### 9.2 System Cron.d — Wheeler Cron Jobs

#### /etc/cron.d/wheeler-health
| Schedule | Script | Purpose |
|---|---|---|
| `*/5 * * * *` | `docker-healthcheck.sh` | Docker container health checks |
| `*/5 * * * *` | `pm2-healthcheck.sh` | PM2 process health checks |
| `0 * * * *` | `self-heal.sh` | Hourly self-healing remediation |

#### /etc/cron.d/wheeler-functional-health
| Schedule | Script | Purpose |
|---|---|---|
| `*/5 * * * *` | `functional-healthcheck.sh` | Functional health verification |

#### /etc/cron.d/wheeler-enterprise
| Schedule | Script | Purpose |
|---|---|---|
| `*/5 * * * *` | `healthcheck-all.sh --prometheus` | Full enterprise health check with Prometheus metrics |
| `*/2 * * * *` | `autoheal.sh --once` | Auto-healing daemon (every 2 minutes) |
| `0 * * * *` | `enforce-roles.sh --server aiops --report` | Hourly role compliance audit |
| `0 2 * * *` | `backup-all.sh` | Daily backup at 2AM UTC |
| `0 3 * * *` | `find ... -mtime +30 -delete` | Daily log cleanup (30 day retention) |
| `0 4 * * *` | `backup-verify.sh` | Daily backup verification at 4AM |
| `30 4 * * 0` | `tls-renew.sh` | Weekly TLS certificate renewal check |
| `0 5 1,1,4,7,10 *` | `restore-test.sh` | Quarterly restore test (Jan/Apr/Jul/Oct) |
| `* * * * *` (x2, staggered 30s) | `discord-forwarder.sh` | Discord alert forwarding (every 30s) |

### 9.3 PM2 Auto-Restart Triggers
- **Agent services:** max 10 restarts, 5s delay, 500MB memory limit
- **All services:** autorestart enabled, log rotation via pm2-logrotate

---

## 10. DOCKER-BASED AI & AUTOMATION CONTAINERS

| Container | Image | Status | Port | Category |
|---|---|---|---|---|
| **langflow** | `langflowai/langflow:1.0.19` | healthy | 127.0.0.1:7860 | AI Workflow |
| **open-webui** | `ghcr.io/open-webui/open-webui:main` | healthy | 127.0.0.1:3000 | AI Chat |
| **aiops-ravynai-app** | `ravynai-opportunity-graph-app` | healthy | 127.0.0.1:8007 | AI App |
| **prediction-radar-app-worker** | `prediction-radar-app-worker` | healthy | internal | AI Worker |
| **prediction-radar-app-scheduler** | `prediction-radar-app-scheduler` | healthy | internal | AI Scheduler |
| **prediction-radar-app-api** | `prediction-radar-app-api` | healthy | internal | AI API |
| **prediction-radar-dashboard-v2** | `prediction-radar-app-dashboard-v2` | healthy | internal | AI Dashboard |
| **aiops-changedetection** | `changedetection.io:0.55.3` | healthy | 127.0.0.1:5000 | Automation |
| **aiops-healthchecks** | `healthchecks:v4.2-ls344` | healthy | 127.0.0.1:3130 | Monitoring |
| **temporal-server** | `temporalio/auto-setup:1.29.3` | healthy | 127.0.0.1:7233 | Orchestration |
| **temporal-ui** | `temporalio/ui:2.50.0` | healthy | 127.0.0.1:8089 | Orchestration UI |
| **usesend** | `usesend/usesend:pinned-2026-05-24` | healthy | 100.121.230.28:3007 | Production App |

---

## 11. DATA FLOW MAP

```
                     ┌──────────────────────────────────────┐
                     │         SHARED SECRETS               │
                     │    /opt/apps/.env.shared             │
                     │  (DEEPSEEK_API_KEY, ANTHROPIC_*,     │
                     │   DATABASE_URL, REDIS_*, etc.)       │
                     └──────────┬───────────────────────────┘
                                │ (loaded via pm2-env-wrapper.sh)
                                ▼
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  DeepSeek   │◄────│   LiteLLM Proxy  │◄────│ Agent Services  │
│  API        │     │   127.0.0.1:4049 │     │ (9 agents)      │
│             │     │   model: deepseek│     │                 │
└─────────────┘     │   -chat          │     │ design-agent    │
                    │                  │     │ horizon-agent   │
┌─────────────┐     │   Also routes:   │     │ paperless-agent │
│ Anthropic   │◄────│   claude-sonnet-4│     │ ravyn-agent     │
│ API         │     │   claude-opus-4  │     │ surplusai-agent │
└─────────────┘     └──────┬───────────┘     │ voice-agent     │
                           │                  │ prediction-radar│
                           │                  │ insforge-agent  │
                           │                  │ frgcrm-agent    │
                           │                  └────────┬────────┘
                           │                           │
                           ▼                           ▼
                    ┌──────────────┐           ┌──────────────┐
                    │  Core-DB     │           │  Hostinger   │
                    │  100.118.    │           │  100.98.     │
                    │  166.117     │           │  163.17      │
                    │  PostgreSQL  │           │  FRGCRM API  │
                    │  Redis       │           │  FRGOPS API  │
                    │  MinIO       │           │  InsForge    │
                    └──────────────┘           │  PostgREST   │
                                               └──────────────┘
```

### Agent-to-Service Dependencies

| Agent | Connects To | Via |
|---|---|---|
| **frgcrm-agent-svc** | FRGCRM API, FRGOPS API | `localhost:8002`, `localhost:8001` |
| **ravyn-agent-svc** | RavynAI app | `localhost:8007` |
| **horizon-agent-svc** | LiteLLM only (no external deps) | `localhost:4049` |
| **surplusai-scraper-agent-svc** | SurplusAI Portal API | `localhost:8103` |
| **voice-agent-svc** | LiteLLM, Twilio, ElevenLabs | External APIs via secrets |
| **paperless-agent-svc** | LiteLLM only | `localhost:4049` |
| **prediction-radar-agent-svc** | Prediction Radar API | Docker internal network |
| **insforge-agent-svc** | InsForge API, PostgREST | `localhost:7130`, `localhost:5430` |
| **design-agent-svc** | LiteLLM only | `localhost:4049` |

(All agents also connect to LiteLLM at `localhost:4049` as their AI backend)

---

## 12. NODE INVENTORY

### AIOPS Control Plane — `wheeler-aiops-01`
- **Provider:** Hetzner CPX51
- **Public IP:** 5.78.140.118
- **Private IP:** 10.0.0.3
- **Tailscale:** 100.121.230.28
- **Specs:** 16 CPU, 30GB RAM, 338GB disk, Ubuntu 24.04

### Worker Node — `wheeler-core-db-01`
- **Provider:** Hetzner
- **Private IP:** 10.0.0.2
- **Tailscale:** 100.118.166.117
- **Role:** Core-DB (PostgreSQL, Redis, MinIO, Temporal)

### Production Edge — `srv1476866`
- **Provider:** Hostinger
- **Tailscale:** 100.98.163.17
- **Role:** Production (FRGCRM, FRGOPS, InsForge, PostgREST)

### Operator Command Center — `mac-command-center`
- **Provider:** Local (macOS)
- **Role:** Operator cockpit, approvals, development

---

## 13. SECRETS GOVERNANCE

All agent secrets are centralized in `/opt/apps/.env.shared` (loaded at runtime via `pm2-env-wrapper.sh`):

| Secret | Used By | Category |
|---|---|---|
| DEEPSEEK_API_KEY | LiteLLM + all agents (via proxy) | Critical |
| ANTHROPIC_AUTH_TOKEN | LiteLLM (premium models) | Critical |
| OPENAI_API_KEY | LiteLLM (fallback) | Critical |
| SURPLUSAI_OPENAI_API_KEY | SurplusAI agents | Critical |
| LITELLM_MASTER_KEY | LiteLLM proxy auth | Critical |
| INSFORGE_API_KEY | InsForge agent service | High |
| HCLOUD_TOKEN | Infrastructure automation | High |
| REDIS_PASSWORD | All Redis connections | High |
| DATABASE_URL | All PostgreSQL connections | High |

**Rotation policy:** Critical = 30 days, High = 90 days, Medium = 180 days.

---

## 14. SERVICE HEALTH SUMMARY

| Layer | Total | Online | Stopped/Error |
|---|---|---|---|
| PM2 Agent Services | 9 | 9 | 0 |
| PM2 Infrastructure | 11 | 10 | 1 (backup-verification) |
| Claude Code Agents | 12 | 12 (definitions) | 0 |
| Claude Code Commands | 20 | 20 | 0 |
| Docker Containers (AI) | 42 | 42 | 0 |
| Cron Automation | 14 | 14 | 0 |

---

## 15. OBSERVATIONS & RISKS

1. **DeepSeek single point of failure:** All 9 agent services use `deepseek-chat` exclusively. If DeepSeek API goes down, the entire agent fleet is blind. No automatic failover to Anthropic models for standard agents.

2. **LiteLLM proxy chokepoint:** All agent traffic routes through a single LiteLLM instance on port 4049. No load balancing or high availability configuration.

3. **Secret file pattern:** `/opt/apps/.env.shared` contains all critical secrets in a single file. Good that it uses `pm2-env-wrapper.sh` for runtime injection, but represents a blast radius risk.

4. **browser-agent-svc configured but not running:** The Wheeler ecosystem config references a browser-agent-svc on port 8120, but it does not appear in the current PM2 process list.

5. **wheeler-brain-os configured but not running:** The backup ecosystem config defines wheeler-brain-os on port 8100, but it is not currently registered in PM2. The Brain OS may be operated differently (via Claude Code itself).

6. **backup-verification stopped:** PM2 service `backup-verification` is in stopped state.

7. **No Langflow container named aiops-langflow:** The Langflow container is simply named `langflow` in Docker, not `aiops-langflow` as referenced in some configs.
