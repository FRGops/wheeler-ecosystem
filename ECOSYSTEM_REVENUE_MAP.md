# Wheeler Ecosystem Revenue Map

**Classification:** EXECUTIVE CONFIDENTIAL
**Version:** 1.0
**Date:** 2026-05-24
**Ecosystem State:** Stage 2 Hardening Complete (QA Scorecard 100/100 A+)
**Author:** Wheeler Autonomous Enforcement Agent

---

## 1. Executive Summary

The Wheeler Ecosystem comprises 61 running services (41 Docker containers + 20 PM2 processes) across 3 physical nodes in a Tailscale mesh, protected by Cloudflare DNS with DDoS/WAF. The platform has achieved a 100/100 A+ QA scorecard for security hardening, but the revenue engine remains only partially operational.

**Revenue-Generating Systems:** 2 of 6 systems are actively serving production traffic (Prediction Radar, Docuseal). FRGCRM has a broken API, SurplusAI has a broken scraper, Voice Agent is entirely dead, and the primary revenue data tier (COREDB) is refusing all application connections.

**Monthly Revenue Run-Rate:** Cannot be established. Stripe is in test mode, COREDB is unreachable, and FRGCRM -- the central CRM system -- cannot serve any API requests.

**Critical Blockers (Priority Order):**
1. COREDB PostgreSQL and Redis refusing all application connections (zero revenue data access)
2. Stripe operating in test mode (no production payment capture)
3. FRGCRM API returning 500 errors on every request (CRM data inaccessible)
4. SurplusAI scraper accumulated 282+ restarts (data ingestion pipeline broken)
5. Voice Agent missing Twilio API keys (outbound revenue channel dead)
6. Temporal workflow engine non-functional (DB unreachable, 42K errors in 8h)
7. No CI/CD pipeline, secrets management, or staging promotion

**Architecture Compliance:**
- AIOPS (Hetzner): 85% compliant -- compute, AI, agents, orchestration
- COREDB (Hetzner): 70% compliant -- PostgreSQL, Redis, MinIO, backups -- but APP TIER UNREACHABLE
- EDGE (Hostinger): 40% compliant -- still running 12 Docker + 38 PM2 processes against target architecture

---

## 2. Revenue System Inventory

### 2.1 Revenue-Generating Systems

| System | Status | Revenue Impact | Platform | Port | Uptime | Restarts | Owner |
|--------|--------|---------------|----------|------|--------|----------|-------|
| **Prediction Radar** (predictionradar.app) | LIVE -- Serving, Test Mode | STRIPE TEST MODE. 7 subscription tiers configured but NO PRODUCTION PAYMENTS | Docker (6 containers) | 8098 | 15h | 0 | Wheeler AI |
| **FRGCRM** | RED -- API returns 500 on all requests. Agent Svc LIVE but degraded | CRM data inaccessible. PipelineDAG 6/6 stages failing. Lost lead tracking | PM2 + Docker | 8082 | 17m (recent restart) | 0 | Wheeler AI |
| **SurplusAI Portal** | LIVE -- Portal serving, Scraper BROKEN | Portal accessible. Scraper (282+ restarts) cannot fetch inventory data | PM2 | 8103 (API) / 3003 (Frontend) | 17m | 1 | Wheeler AI |
| **Voice Agent** | DEAD -- Missing Twilio API keys | Outbound voice channel generating $0 revenue | PM2 | 8008 | 19m | 1 | Wheeler AI |
| **RavynAI** | LIVE -- Opportunity Graph active | AI-driven lead scoring and opportunity detection | Docker | 8007 | 14h | 0 | Wheeler AI |
| **Docuseal** | LIVE -- E-signature platform | Document signing for client agreements. Generates signatures, not direct revenue | Docker | 3010 | 14h | 0 | Wheeler AI |

### 2.2 Revenue-Supporting Systems

| System | Status | Revenue Function | Platform | Port | Uptime |
|--------|--------|-----------------|----------|------|--------|
| **LiteLLM** | LIVE -- AI Gateway (377 MB) | Routes all LLM calls (Anthropic, OpenAI, DeepSeek). Every revenue agent depends on this | PM2 | 4049 | 19m (recent restart) |
| **Chatwoot / Live Chat** | ONLINE | Customer engagement, lead capture via live chat | Docker | -- | 15h |
| **n8n Automation** | LIVE | Workflow automation, lead nurturing sequences | Docker | -- | 15h |
| **usesend** | LIVE on EDGE | Email delivery (SendGrid SMTP), transactional and marketing emails | Docker (host network) | 3007 | 14h |
| **Temporal Server** | DEGRADED -- DB unreachable | Workflow orchestration engine. 42K errors in 8h | Docker (host network) | 7233 | 8h |
| **Discord Webhooks** | ACTIVE | Alerting, notification delivery, operational monitoring | -- | -- | Always |
| **Neo4j Ecosystem Graph** | LIVE (ecosystem-graph) | Relationship graph for entity linking, lead connections | Docker | 7474/7687 | 13h |

### 2.3 Revenue Systems Dependency Map

```
                   ┌──────────────────────────────┐
                   │         COREDB CLUSTER        │
                   │   100.118.166.117 (Tailscale) │
                   │     PostgreSQL :5432 ── RED   │
                   │     Redis :6379     ── RED    │
                   └──────────┬───────────────────┘
                              │ ALL APP CONNECTIONS      REFUSED
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────────┐
│   FRGCRM     │   │  LiteLLM     │   │ Event Bus Relay  │
│   API 500    │   │  No Cache    │   │ Reconnect Loop   │
│ ALL REQUESTS │   │  /health 401 │   │ Every 5 seconds  │
└──────┬───────┘   └──────┬───────┘   └──────────────────┘
       │                  │
       ▼                  ▼
┌──────────────┐   ┌──────────────────────────────────┐
│FRGCRM Agent  │   │       PM2 AGENT FLEET            │
│ Fetch Failed │   │  9 agents all degraded (no cache)│
└──────────────┘   └──────────────────────────────────┘

┌──────────────────────┐   ┌────────────────────────┐
│  Temporal Server     │   │ Prediction Radar       │
│  33,976 DB errors    │   │ Uses LOCAL PG (healthy) │
│  No workflow exec    │   │ Uses LOCAL Redis (AOF)  │
└──────────────────────┘   └────────────────────────┘
```

---

## 3. Lead Flow Map

### 3.1 Current Lead Acquisition Channels

| Channel | Status | Lead Volume | Route | Conversion Stage |
|---------|--------|-------------|-------|-----------------|
| Prediction Radar (predictionradar.app) | LIVE | Unknown (no analytics visible) | Direct to prediction-radar-app-web (:8098) | Pre-payment -- Stripe test mode blocks conversion |
| FRGCRM Web Forms | BROKEN (API 500) | Zero | Cloudflare DNS -> FRGCRM Frontend (Hostinger) -> API (AIOPS :8082) | Dead -- Cannot submit or track |
| Chatwoot / Live Chat | ONLINE | Unknown | Direct to Chatwoot container | Lead capture possible |
| SurplusAI Portal | LIVE (partial) | Unknown | surplusai.io -> Nginx -> Portal API (:8103) | Pre-registration |
| RavynAI Opportunity Graph | LIVE | Entity relationships processed | localhost:8007 | Lead scoring |
| Voice Agent (outbound) | DEAD | Zero | N/A | Dead channel |

### 3.2 Lead Routing Path

```
                    LEAD ENTRY POINTS
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
predictionradar.app    surplusai.io      frgcrm.com (DEAD)
        │                  │                  │
        ▼                  ▼                  │
  Stripe Checkout    Portal Register          │
   (TEST MODE)         (LIVE)                 │
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  FRGCRM API  │── RED (500 errors)
                    │  :8082       │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │  PipelineDAG │── 6/6 STAGES FAILING
                    │  6 stages    │
                    └──────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  COREDB PG   │── REFUSING CONNECTIONS
                    │  :5432       │
                    └──────────────┘
```

### 3.3 Lead Conversion Funnel (Current State)

| Stage | Status | System | Bottleneck |
|-------|--------|--------|------------|
| 1. Lead Acquisition | PARTIAL | Prediction Radar, FRGCRM (dead), SurplusAI | FRGCRM dead channel |
| 2. Lead Capture | PARTIAL | FRGCRM API (500s) -> no persistence | API broken, DB unreachable |
| 3. Lead Scoring | DEGRADED | RavynAI running, cannot access COREDB data | COREDB blocked |
| 4. Nurture | DEGRADED | usesend LIVE but CRM cannot trigger sends | CRM dead -> no campaign triggers |
| 5. Conversion | BLOCKED | Stripe test mode -> no payments | Stripe key issue |
| 6. Fulfillment | BLOCKED | Temporal dead -> no workflow execution | COREDB blocked |

---

## 4. CRM & Data Architecture

### 4.1 FRGCRM System

| Component | Status | Location | Dependencies | Revenue Data |
|-----------|--------|----------|-------------|-------------|
| FRGCRM API (PM2) | RED -- 100% request failure | AIOPS :8082 | COREDB PostgreSQL (REFUSED) | 6,603 cases on Hostinger (not yet migrated) |
| FRGCRM Agent Service | YELLOW -- "fetch failed" in logs | AIOPS :8003 | FRGCRM API (dead) | Cannot access cases |
| FRGCRM Frontend | LIVE on Hostinger (EDGE) | Hostinger | AIOPS API -> COREDB | Frontend accessible, API broken |
| PipelineDAG | 6/6 STAGES FAILING | PM2 | All depend on COREDB | Zero leads processed |

### 4.2 Data Silos (Customer/Lead Data Location)

| Data Store | Contents | Size | Status | CRM Integrated? |
|------------|----------|------|--------|----------------|
| prediction-radar-app-db | Users, predictions, payment records, subscriptions | 38 MB (PG16) | HEALTHY | NO -- independent silo |
| ravynai-postgres | Knowledge graph, opportunity data, entity relationships | 19 MB (PG16 + PostGIS) | HEALTHY | NO -- independent silo |
| frgops-standby | Supposed to be FRGCRM replica. Named "standby" but is PRIMARY | 8 MB (PG16) | MISCONFIGURED (wrong DB name) | YES -- but broken |
| COREDB (wheeler_core) | Target FRGCRM database | Empty | REFUSING CONNECTIONS | TARGET |
| Hostinger (frgops_staging) | 6,603 active CRM cases | Full production data | Not migrated | CURRENT HOME |
| Neo4j (ecosystem-graph) | Entity relationship graph | Unknown | HEALTHY | NO -- independent |
| ClickHouse (analytics) | Business analytics, user activity | Unknown | HEALTHY (no auth) | NO -- independent |

### 4.3 CRM Architecture Gap

```
INTENDED ARCHITECTURE:
  All apps  ──>  COREDB PostgreSQL :5432  ──> Single source of truth

CURRENT REALITY:
  prediction-radar-app-db ──> LOCAL Docker PG (healthy, independent)
  ravynai-postgres        ──> LOCAL Docker PG (healthy, independent)
  frgops-standby          ──> LOCAL Docker PG (misconfigured, wrong DB name)
  frgcrm-api (AIOPS)      ──> COREDB :5432 ──> REFUSED
  frgcrm-api (Hostinger)  ──> frgops_staging (6,603 cases) ──> Not migrated
  Temporal                ──> COREDB :5432 ──> REFUSED

  5 out of 6 data paths are FRAGMENTED or BROKEN.
  No single CRM view of customer exists.
```

---

## 5. Payment & Monetization Infrastructure

### 5.1 Stripe Configuration

| Parameter | Value | Status |
|-----------|-------|--------|
| Mode | TEST | **BLOCKING -- no production revenue** |
| Integration Point | Prediction Radar App | Configured |
| Subscription Tiers | 7 tiers | Configured but cannot capture real payments |
| Webhooks | Stripe webhook endpoints | Configured |
| API Key Location | Prediction Radar .env | Externalized (600 permissions) |

### 5.2 Subscription Tiers (Prediction Radar)

| Tier | Likely Price Point | Status | Notes |
|------|--------------------|--------|-------|
| Basic | Unknown | Configured | Test mode only |
| Standard | Unknown | Configured | Test mode only |
| Premium | Unknown | Configured | Test mode only |
| Pro | Unknown | Configured | Test mode only |
| Enterprise | Unknown | Configured | Test mode only |
| (3 additional tiers) | Unknown | Configured | Test mode only |

**Revenue Impact:** Zero production revenue captured until Stripe is switched to live mode. All 7 tiers represent potential revenue that is currently blocked.

### 5.3 Email & Notification Infrastructure

| System | Purpose | Status | Provider | Integration |
|--------|---------|--------|----------|-------------|
| usesend | Transactional & marketing email | LIVE on EDGE | SendGrid SMTP | Not connected to CRM (CRM dead) |
| SendGrid SMTP | Email delivery | Configured | SendGrid | In usesend config |
| Discord Webhooks | Alerts & notifications | ACTIVE | Discord | All health check scripts |

### 5.4 Monetization Flow

```
Customer ──> predictionradar.app ──> Stripe Checkout (TEST MODE)
                                          │
                                    [NO PAYMENT CAPTURED]
                                          │
                                          ▼
                                 FRGCRM API :8082 (500)
                                          │
                                    [NO DATA PERSISTED]
                                          │
                                          ▼
                                 usesend (email delivery)
                                    (no trigger events from CRM)
```

---

## 6. AI Agent Fleet

### 6.1 PM2 Agent Services (9 Agents + 2 Business Logic + 6 Infrastructure = 19 Total PM2)

| Agent | Port | Status | Memory | Revenue Function | API Keys |
|-------|------|--------|--------|-----------------|----------|
| **ravyn-agent-svc** | 8005 | ONLINE | 108.9 MB | Opportunity detection, lead scoring | OPENAI |
| **frgcrm-agent-svc** | 8003 | DEGRADED | 94.7 MB | CRM operations, case management | DEEPSEEK, OPENAI, FRGCRM_TOKEN |
| **horizon-agent-svc** | 8006 | ONLINE | 105.1 MB | Market scanning, trend detection | OPENAI |
| **surplusai-scraper-agent-svc** | 8007 | ONLINE | 108.1 MB | Inventory data ingestion | OPENAI, FRGCRM_TOKEN |
| **voice-agent-svc** | 8008 | ONLINE (hollow) | 104.0 MB | Outbound voice calls (missing Twilio keys) | OPENAI |
| **paperless-agent-svc** | 8009 | ONLINE | 104.8 MB | Document processing, analysis | OPENAI |
| **prediction-radar-agent-svc** | 8011 | ONLINE | 110.2 MB | Prediction analysis, market scoring | OPENAI |
| **insforge-agent-svc** | 8013 | ONLINE | 74.7 MB | Insurance intelligence | INSFORGE_API_KEY |
| **design-agent-svc** | 8020 | ONLINE | 109.4 MB | Creative, UI/UX generation | OPENAI |
| **frgcrm-api** | 8082 | DEGRADED (500s) | 235.0 MB | CRM business logic (CRITICAL) | DEEPSEEK, ANTHROPIC, LITELLM, REDIS, HCLOUD |
| **surplusai-portal-api** | 8103 | ONLINE | 103.7 MB | Portal API | DEEPSEEK, ANTHROPIC, LITELLM, REDIS, HCLOUD |
| **voice-outreach-service** | 8095 | ONLINE | 54.2 MB | Outbound campaign management | DEEPSEEK, ANTHROPIC, LITELLM, REDIS, HCLOUD |

### 6.2 Infrastructure PM2 Services

| Service | Port | Status | Memory | Function |
|---------|------|--------|--------|----------|
| **litellm** | 4049 | ONLINE | 377.5 MB | AI model gateway (Anthropic, OpenAI, DeepSeek) |
| **ecosystem-guardian** | -- | ONLINE | 56.5 MB | Infrastructure monitoring, anomaly detection |
| **war-room-server** | 8091 | ONLINE | 59.9 MB | Command center / operations dashboard |
| **command-center** | 8100 | ONLINE | 48.3 MB | Operator console |
| **openclaw-dashboard** | 8110 | ONLINE | 61.0 MB | Dashboard service |
| **event-bus-relay** | 6399 | ONLINE | 57.4 MB | Event relay (Redis reconnect loop) |

### 6.3 Claude Code Skills (20 Skills) Mapped to Revenue Functions

| Skill | Revenue Function | 
|-------|-----------------|
| /slay | Full ecosystem health audit -- preserves revenue uptime |
| /pm2-recovery | PM2 crash recovery -- restarts revenue services |
| /docker-health | Container health -- critical for Prediction Radar, Docuseal |
| /secrets-scan | API key leak prevention -- protects Stripe/API keys |
| /deploy-safety | Safe deployment -- minimizes revenue downtime |
| /rollback-first | Rollback safety -- recovery from bad deploys |
| /production-readiness | Pre-deployment validation |
| /cost-control | Infrastructure cost optimization |
| /database-lockdown | Database security -- protects customer data |
| /secrets-scan | Credential exposure prevention |
| /hostinger-production-operator | Hostinger EDGE operations |
| /worker-routing-operator | Agent routing |
| /aiops-control-plane-operator | AIOPS control plane |
| /mac-command-center-operator | Mac command center |
| /private-network-check | Network security |
| /repo-audit | Code audit |
| /agent-workflow-builder | Workflow construction |
| /open-source-repo-evaluator | Third-party code assessment |
| /incident-response | Incident management |
| /no-false-greens | Health check integrity verification |

### 6.4 API Key Propagation Risk Map

```
5 processes carry FULL KEYCHAIN (DEEPSEEK + ANTHROPIC + LITELLM_MASTER + REDIS_PASSWORD + HCLOUD_TOKEN):
  litellm ──> frgcrm-api ──> voice-outreach-service ──> surplusai-portal-api ──> frgcrm-agent-svc

3 processes carry DEEPSEEK + ANTHROPIC:
  openclaw-dashboard ──> ecosystem-guardian ──> war-room-server

7 processes carry OPENAI key:
  ALL *-agent-svc processes

RISK: A single compromised agent exposes API keys for MULTIPLE providers.
```

---

## 7. Domain & Routing Map

### 7.1 Public Domains

| Domain | Target | Service | TLS | Status | Cloudflare |
|--------|--------|---------|-----|--------|------------|
| predictionradar.app | AIOPS :8098 | Prediction Radar Web | YES | LIVE | DDoS/WAF |
| fundsrecoverygroup.com | Hostinger (EDGE) | FRGCRM Frontend | YES | LIVE | DDoS/WAF |
| surplusai.io | AIOPS :8103 | SurplusAI Portal API | YES | LIVE | DDoS/WAF |
| wheeler.ai (14 subdomains) | AIOPS / Tailscale | Various | YES | LIVE | DDoS/WAF |
| frgops.fundsrecoverygroup.tech | Hostinger | Operations | YES | LIVE | DDoS/WAF |
| ravynai.wheeler.ai | AIOPS :8007 | RavynAI | YES | LIVE | DDoS/WAF |

### 7.2 Internal Tailscale Routes (aiops-gateway -- 17 Virtual Hosts)

All routes served via nginx on 100.121.230.28:443 with TLS, auth_basic, and rate limiting:

| Server Name | Backend | Service Type | Route Function |
|-------------|---------|-------------|----------------|
| grafana.aiops | 127.0.0.1:3002 | Monitoring | Revenue metrics visualization |
| kuma.aiops / status.aiops | 127.0.0.1:3001 | Monitoring | Uptime tracking |
| netdata.aiops | 127.0.0.1:19999 | Monitoring | Infrastructure metrics |
| superset.aiops | 127.0.0.1:8088 | Analytics | Revenue analytics |
| healthchecks.aiops | 127.0.0.1:3130 | Monitoring | Health check dashboard |
| langflow.aiops | 127.0.0.1:7860 | AI Ops | AI workflow builder |
| changes.aiops | 127.0.0.1:5000 | Monitoring | Website change detection |
| prometheus.aiops | 127.0.0.1:9090 | Monitoring | Metrics aggregation |
| loki.aiops | 127.0.0.1:3100 | Monitoring | Log aggregation |
| docuseal.aiops | 127.0.0.1:3010 | Revenue | E-signature admin |
| prediction-radar.aiops | 127.0.0.1:8098 | Revenue | Prediction Radar admin |
| openwebui.aiops | 127.0.0.1:3000 | AI Ops | AI chat interface |
| grafana-core.aiops | 100.118.166.117:3000 | Monitoring | Cross-node dashboards |
| prometheus-core.aiops | 100.118.166.117:9090 | Monitoring | Cross-node metrics |
| 1panel.aiops | 127.0.0.1:8090 | Admin | Server management panel |
| crm.aiops | 127.0.0.1:3007 | Revenue | FRGCRM/usesend |
| clickhouse.aiops | 127.0.0.1:8123 | Analytics | SQL analytics engine |
| command.aiops | 127.0.0.1:8100 | Admin | Wheeler Command Center |

### 7.3 CDN / DDoS Protection

| Provider | Services Protected | Status |
|----------|-------------------|--------|
| Cloudflare DNS | All public domains | ACTIVE |
| Cloudflare DDoS | All proxied domains | ACTIVE |
| Cloudflare WAF | All proxied domains | ACTIVE |
| Cloudflare SSL | All proxied domains | TLS termination |

**Gap:** AIOPS public IP (5.78.140.118) is directly accessible -- not fully behind Cloudflare proxy for all services. 14 Docker containers historically bound to 0.0.0.0 (ALL FIXED in Stage 2 -- now all 127.0.0.1).

---

## 8. Database Topology

### 8.1 Database Inventory

| Database | Engine | Version | Size | Server | Port | Bind | Status | Backup |
|----------|--------|---------|------|--------|------|------|--------|--------|
| prediction-radar-app-db | PostgreSQL | 16 | 38 MB | AIOPS (Docker) | 5432 | Internal | HEALTHY | Daily |
| ravynai-postgres | PostgreSQL (PostGIS) | 16 | 19 MB | AIOPS (Docker) | 5434 | 127.0.0.1 | HEALTHY | Daily |
| frgops-standby | PostgreSQL | 16 | 8 MB | AIOPS (Docker) | 5433 | 127.0.0.1 | MISCONFIGURED (wrong DB name) | Daily |
| COREDB PostgreSQL | PostgreSQL | -- | -- | COREDB (Hetzner) | 5432 | Tailscale | REFUSING CONNECTIONS | Unknown |
| prediction-radar-app-redis | Redis | 7 | 62 MB AOF (0 keys) | AIOPS (Docker) | 6379 | Internal | HEALTHY (AOF bloat) | Daily |
| docuseal-redis | Redis | 7-alpine | 1.64 MB | AIOPS (Docker) | 6379 | Internal | HEALTHY | Daily |
| COREDB Redis | Redis | -- | -- | COREDB (Hetzner) | 6379 | Tailscale | REFUSING CONNECTIONS | Unknown |
| ClickHouse | ClickHouse | 24.3 | Unknown | AIOPS (Docker) | 8123 | 127.0.0.1 | HEALTHY (no auth) | Daily |
| Neo4j | Neo4j | 5.26 | Unknown | AIOPS (Docker) | 7474/7687 | 127.0.0.1 | HEALTHY | Daily |
| Hostinger (frgops_staging) | PostgreSQL | -- | Unknown (6,603 cases) | EDGE (Hostinger) | -- | Internal | ACTIVE (production data) | Unknown |

### 8.2 Backup Status

| Backup Target | Schedule | Verification | Restore Tested? | Status |
|---------------|----------|-------------|-----------------|--------|
| PM2 dumps | Daily 2am | YES (backup-verify.sh) | YES (quarterly restore-test.sh) | HEALTHY |
| Docker volumes | Daily 2am | YES (backup-verify.sh) | YES (quarterly) | HEALTHY |
| PostgreSQL (AIOPS) | Daily 2am | YES | YES (dry-run to /tmp) | HEALTHY |
| PostgreSQL (COREDB) | Unknown | NO | NO | UNKNOWN |
| Redis (AIOPS) | Daily 2am | YES | YES | HEALTHY |
| Nginx configs | Weekly | YES | YES | HEALTHY |
| Hostinger DB (frgops_staging) | NOT BEING BACKED UP | N/A | N/A | NOT COVERED |

### 8.3 Database Access Topology

```
                    ┌─────────────────────────────────────┐
                    │        COREDB (5.78.210.123)         │
                    │                                     │
                    │  PostgreSQL :5432 ──── REFUSING ALL   │
                    │  Redis :6379     ──── REFUSING ALL   │
                    │  MinIO :9000     ──── NOT DEPLOYED   │
                    └──────────────────┬──────────────────┘
                                       │ Tailscale
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        │                              │                              │
        ▼                              ▼                              ▼
┌─────────────────┐    ┌─────────────────────────┐    ┌──────────────────────┐
│  AIOPS LOCAL     │    │  AIOPS PROCESSES TRYING  │    │  HOSTINGER EDGE       │
│  (Working)       │    │  COREDB (Failing)        │    │  (Live Production)    │
├─────────────────┤    ├─────────────────────────┤    ├──────────────────────┤
│ pred-radar-db   │    │ frgcrm-api :8082         │    │ frgops_staging DB    │
│  38 MB PG       │    │   ALL REQUESTS 500        │    │  6,603 CRM cases     │
│ ravynai-pg      │    │ Temporal Server           │    │  ACTIVE DATA          │
│  19 MB PG       │    │  42K errors / 8h          │    │  NOT MIGRATED         │
│ pred-radar-redis │    │ event-bus-relay           │    │                      │
│  0 keys / 62MB  │    │  reconnect loop 5s        │    │                      │
└─────────────────┘    └─────────────────────────┘    └──────────────────────┘
```

---

## 9. Monitoring & Health Infrastructure

### 9.1 Health Check Architecture

| Script / System | Interval | Checks | Alerts To | Status |
|-----------------|----------|--------|-----------|--------|
| functional-healthcheck.sh | Every 5 min | 20 HTTP endpoints (core APIs, agents, infra, cross-host) | Discord webhook | ACTIVE |
| autoheal.sh (12 responsibilities) | Every 60s | Docker, PM2, ports, disk, memory, CPU, Nginx, DNS | Discord | ACTIVE |
| backup-verify.sh | Daily 4am UTC | Backup existence, recency, integrity, size, PM2 dump | Discord | ACTIVE |
| restore-test.sh | Quarterly | Archive integrity, SQL integrity, config readability, compose syntax | Discord | ACTIVE |
| tls-renew.sh | Weekly Sun 4:30am UTC | Cert expiry <30d, auto-renew, Nginx reload | Log | ACTIVE |
| readiness-scorecard.sh | On-demand | Full ecosystem readiness audit | -- | DISPATCHABLE |
| smoke-test-all.sh | On-demand | Cross-section health smoke test | -- | DISPATCHABLE |
| revenue-healthcheck.sh | On-demand | Revenue system health verification | -- | DISPATCHABLE |
| backup-manifest.sh | On-demand | Full backup inventory | -- | DISPATCHABLE |
| cert-expiry-exporter.sh | Continuous | Certificate expiry metrics | Prometheus | ACTIVE |
| config-drift-detector.sh | Continuous | Configuration drift detection | Discord | ACTIVE |
| dead-mans-switch.sh | Continuous | Meta-monitoring dead man's switch | Discord | ACTIVE |

### 9.2 Observability Stack

| Component | Status | Port | Data Source | Revenue Visibility |
|-----------|--------|------|-------------|-------------------|
| Prometheus | HEALTHY | 9090 | Docker, PM2, Node, Custom exporters | Metrics scraped from 8/9 targets |
| Grafana | HEALTHY | 3002 | Prometheus (not provisioned) | Dashboards exist, no datasources |
| Loki | HEALTHY | 3100 | Promtail (all containers) | Centralized logs |
| Promtail | HEALTHY | 9080 | Docker socket, log files | Ship logs to Loki |
| Alertmanager | HEALTHY | 9093 | Prometheus alerts | Alert routing configured |
| Uptime Kuma | HEALTHY | 3001 | HTTP monitoring of endpoints | External uptime checks |
| Netdata | HEALTHY | 19999 | System metrics | Real-time system monitoring |
| ClickHouse | HEALTHY | 8123 | Analytics data (no auth) | Business analytics |
| Node Exporter | HEALTHY | 9100 | Host metrics | System-level revenue infra metrics |
| Pushgateway | HEALTHY | 9092 | Custom batch metrics | PM2 metrics ingestion |

### 9.3 Cron Schedule

```
*/5 * * * *    functional-healthcheck.sh    (20 endpoints + Discord)
*/2 * * * *    autoheal.sh                  (12 responsibilities)
0 * * * *      Role compliance audit        (security posture)
30 4 * * 0     TLS certificate renewal      (cert expiry)
0 4 * * *      Backup verification          (integrity checks)
0 5 1 1,4,7,10 *  Quarterly restore test    (disaster recovery)
0 2 * * *      Daily backup                 (data preservation)
* * * * *      Discord alert forwarder      (every 30s)
0 5 * * *      Log rotation                 (disk management)
```

### 9.4 Health Check Endpoints (Functional Healthcheck -- 20 Checks)

```
CORE APIS (5):
  frgcrm-api :8082       ── expects 200 ── CURRENT 500 (FAILS)
  surplusai-api :8103    ── expects 200 ── PASS
  litellm :4049           ── expects 200|401 ── PASS
  war-room :8091          ── expects 200 ── PASS
  openclaw-dash :8110    ── expects 200 ── PASS

AGENT SERVICES (9):
  ravyn :8005, frgcrm :8003, horizon :8006, surplusai :8007,
  voice :8008, paperless :8009, pred-radar :8011,
  insforge :8013, design :8020 ── ALL expect 200 ── ALL PASS

INFRASTRUCTURE (4):
  prometheus :9090, alertmanager :9093, grafana :3002, loki :3100 ── ALL PASS

CROSS-HOST (2):
  coredb-pg (via COREDB Prometheus) ── INFO (expected not reachable)
  coredb-reachable (via COREDB Grafana) ── INFO (expected not reachable)
```

---

## 10. Critical Gaps & Immediate Revenue Blockers

### 10.1 Priority Matrix (Revenue Impact)

| Priority | Issue | Revenue Impact | System Affected | Effort to Fix | Dependencies |
|----------|-------|---------------|-----------------|---------------|-------------|
| **P0** | COREDB PostgreSQL refusing connections | All CRM data inaccessible, zero lead tracking, PipelineDAG dead | FRGCRM, Temporal, Event Bus | MEDIUM | COREDB network config |
| **P0** | COREDB Redis refusing connections | No cache, event bus dead, all agents running without cache | LiteLLM, Event Bus, all 9 agents | MEDIUM | COREDB network config |
| **P0** | Stripe in test mode | Zero production payment capture | Prediction Radar (7 tiers) | LOW (key switch) | Stripe account verification |
| **P1** | FRGCRM API returning 500 on all requests | CRM dead, PipelineDAG 6/6 failing, no lead processing | FRGCRM Agent, Frontend, Pipeline | LOW (point to correct DB or fix COREDB) | COREDB connectivity |
| **P1** | SurplusAI scraper 282+ restarts | No inventory data ingestion | SurplusAI platform | MEDIUM | Debug scraper agent |
| **P1** | Voice Agent missing Twilio keys | Outbound voice channel $0 revenue | Voice outreach | LOW (add keys) | Twilio account |
| **P2** | Temporal DB unreachable (42K errors/8h) | No workflow orchestration | All Temporal-dependent processes | MEDIUM | COREDB PostgreSQL |
| **P2** | frgops-standby misconfigured (wrong DB name) | No standby replica, wrong configs | RavynAI, Prediction Radar configs | LOW (fix DB name in .env) | None |
| **P2** | No CI/CD pipeline | Deployments are manual, error-prone | All systems | HIGH | Infrastructure setup |
| **P2** | No secrets management | Plaintext API keys in env vars | All systems | HIGH | Vault/secret store setup |
| **P3** | ClickHouse no auth | Analytics database exposed | Analytics stack | LOW | Set password |
| **P3** | Prediction Radar Redis AOF bloat (62MB, 0 keys) | Wasted disk, slower restarts | Prediction Radar | LOW | BGREWRITEAOF |
| **P3** | Temporal UI on host network | Security isolation bypass | Temporal | MEDIUM | Docker config change |
| **P3** | No staging environment | Can't test before production | All systems | HIGH | Infrastructure |

### 10.2 Revenue Blockers Detail

**Blocker 1: COREDB Connectivity (P0)**
The COREDB cluster at 100.118.166.117 is running and Tailscale-reachable (Prometheus exporters show UP), but PostgreSQL on :5432 and Redis on :6379 REFUSE application-level connections. This blocks:
- FRGCRM API (all requests 500)
- Temporal Server (42K errors in 8h -- cannot execute workflows)
- LiteLLM caching (Redis-based)
- Event bus relay (Redis reconnect loop every 5s)
- All 9 agent services (no cache, no CRM data access)

**Root cause:** Unknown. Could be pg_hba.conf, Redis requirepass mismatch, Tailscale ACL, or PostgreSQL not listening on Tailscale interface.

**Blocker 2: Stripe Test Mode (P0)**
Prediction Radar has 7 subscription tiers configured but Stripe is in test mode. The application captures exactly $0 in production revenue. The key issue may be:
- Stripe API key switched from test to live
- Webhook endpoint configured for live mode
- Stripe account verification/onboarding completion

**Blocker 3: CRM Data Split-Brain (P1)**
The frgcrm-api on AIOPS connects to an empty COREDB (which refuses connections anyway). The actual production data (6,603 cases) remains on Hostinger in frgops_staging. Even if COREDB comes online, the AIOPS FRGCRM API has no data until migration completes.

### 10.3 Revenue Loss Estimate

| System | Monthly Revenue Potential | Current Revenue | Loss |
|--------|-------------------------|----------------|------|
| Prediction Radar (7 tiers) | Unknown -- no production data | $0 (test mode) | 100% of potential |
| FRGCRM (case management) | Unknown -- no production data | $0 (all requests 500) | 100% of potential |
| Voice Agent (outbound) | Unknown | $0 (missing keys) | 100% of potential |
| SurplusAI (portal/scraper) | Unknown | Portal LIVE, scraper broken | ~50% of potential |
| Docuseal (e-signatures) | Unknown | LIVE -- operational | 0% (working) |
| RavynAI (opportunity graph) | Unknown | LIVE -- operational | 0% (working) |

---

## 11. Revenue Automation Pipeline

### 11.1 Current State (Manual / Broken)

```
Lead Acquisition ──> Lead Capture ──> Lead Scoring ──> Nurture ──> Conversion ──> Fulfillment
   (Varied)           (BROKEN)        (DEGRADED)       (DEGRADED)  (BLOCKED)      (BLOCKED)

Manual processes:
  - Deployment: SSH + manual commands
  - Health monitoring: Discord alerts (manual response)
  - Scaling: No auto-scaling
  - Backups: Daily cron (working)
  - Recovery: Manual intervention
```

### 11.2 Target State (Fully Automated)

```
Lead Acquisition ──> Lead Capture ──> Lead Scoring ──> Nurture ──> Conversion ──> Fulfillment
   (Automated)       (Automated)      (AI-driven)     (Automated) (Automated)    (Automated)

Automated processes:
  - CI/CD: GitHub Actions -> deploy-service.sh -> health verification -> auto-rollback
  - Health: functional-healthcheck.sh (5min) -> Discord -> autoheal.sh (60s)
  - Scaling: ecossytem-guardian resource trend analysis -> PM2 scale
  - Backups: Daily cron + verification + quarterly restore test (IMPLEMENTED)
  - Recovery: rollback-engine/ + multi-node-recovery.sh + self-healing-engine.sh
  - Secrets: env -i pattern (IMPLEMENTED) + .env files with 600 permissions (IMPLEMENTED)
  - TLS: auto-renewal (IMPLEMENTED) with weekly cron
  - Capacity planning: capacity-forecast.sh + resource-trend-exporter.sh
```

### 11.3 Automation Maturity

| Capability | Current | Target | Gap |
|-----------|---------|--------|-----|
| **Health Monitoring** | LIVE (5min checks, Discord alerts) | Same + automated remediation | Add auto-remediation triggers |
| **Backup & Restore** | LIVE (daily, verified, quarterly test) | Same | No backup for Hostinger production DB |
| **Deployment** | Manual SSH | CI/CD pipeline | No GitHub Actions, no staging |
| **Secrets Management** | .env files (600) | Vault / Docker secrets | Functional but centralized |
| **Scaling** | Manual | Auto-scaling via guardian | No auto-scaling thresholds |
| **TLS** | AUTO (weekly cron) | Same | Working |
| **Database Migration** | Manual pg_dump | Automated with rollback | No migration tooling |
| **Incident Response** | Manual via Claude Code | Automated runbooks | Playbooks exist but manual execution |

### 11.4 Revenue Recovery Roadmap

```
Phase 1 (Immediate -- Today):
  1. Fix COREDB PostgreSQL connectivity (unblocks FRGCRM, Temporal, Event Bus)
  2. Fix COREDB Redis connectivity (unblocks all agent caches)
  3. Switch Stripe to live mode (unblocks prediction radar revenue)

Phase 2 (This Week):
  4. Migrate Hostinger frgops_staging (6,603 cases) -> COREDB wheeler_core
  5. Fix FRGCRM API connection string -> COREDB (unblocks CRM)
  6. Switch frgcrm.com API route to AIOPS
  7. Add Twilio keys to Voice Agent (unblocks outbound voice)

Phase 3 (Next Week):
  8. Fix SurplusAI scraper (282+ restarts)
  9. Migrate usesend stack (DB -> COREDB, app -> AIOPS)
  10. Migrate Temporal stack -> AIOPS functional COREDB
  11. Clean up Hostinger duplicate PM2 services

Phase 4 (Next 30 Days):
  12. Deploy CI/CD pipeline (GitHub Actions)
  13. Implement staging environment on COREDB
  14. Set up HashiCorp Vault for secrets management
  15. Deploy MinIO on COREDB for object storage
  16. Implement auto-scaling thresholds

Phase 5 (Next 90 Days):
  17. Full revenue automation pipeline (end-to-end)
  18. Revenue analytics dashboard (Grafana + ClickHouse)
  19. Customer lifetime value tracking
  20. Predictive revenue forecasting (RavynAI + Prediction Radar)
```

---

## Appendix A: Server Topology

| Node | Provider | IP (Public) | IP (Tailscale) | Role | RAM | CPU | Disk |
|------|----------|-------------|----------------|------|-----|-----|------|
| wheeler-aiops-01 | Hetzner CPX51 | 5.78.140.118 | 100.121.230.28 | AIOPS -- Compute, AI, Agents | 30 GB | 16 cores | 338 GB |
| wheeler-core-db-01 | Hetzner | 5.78.210.123 | 100.118.166.117 | COREDB -- Data Tier | -- | -- | -- |
| srv1476866 | Hostinger | 187.77.148.88 | 100.98.163.17 | EDGE -- Public routing | 32 GB | 8 cores | -- |

## Appendix B: Claude Code Skills (20 Total)

| Skill | Category | Revenue Function |
|-------|----------|-----------------|
| slay | Health | Full ecosystem audit |
| pm2-recovery | Operations | Service recovery |
| docker-health | Operations | Container health |
| secrets-scan | Security | API key protection |
| deploy-safety | Operations | Safe deployments |
| rollback-first | Operations | Rollback safety |
| production-readiness | Quality | Pre-deployment validation |
| cost-control | Finance | Infrastructure cost |
| database-lockdown | Security | Data protection |
| hostinger-production-operator | Operations | EDGE management |
| worker-routing-operator | Agents | Agent routing |
| aiops-control-plane-operator | Operations | AIOPS management |
| mac-command-center-operator | Operations | Mac management |
| private-network-check | Security | Network audit |
| repo-audit | Quality | Code audit |
| agent-workflow-builder | Development | Workflow construction |
| open-source-repo-evaluator | Quality | Code assessment |
| incident-response | Operations | Incident management |
| no-false-greens | Quality | Health check integrity |
| superpowers | Meta | Best practices |

## Appendix C: Key Metrics Summary

**Ecosystem Scale:**
- 41 Docker containers (all 127.0.0.1 bound)
- 20 PM2 processes (19 online)
- 12 AI agent services
- 6 database instances (4 PG, 2 Redis + ClickHouse + Neo4j)
- 20 Claude Code skills
- 64 UFW rules (strict allowlist)
- 17 Nginx virtual hosts
- 3-node Tailscale mesh

**Revenue Systems Health:**
- 2/6 revenue-generating systems fully LIVE (Prediction Radar, Docuseal)
- 1/6 LIVE but partially broken (SurplusAI -- portal OK, scraper dead)
- 1/6 LIVE but functionally dead (FRGCRM -- API 500s on every request)
- 1/6 DEAD (Voice Agent -- missing Twilio keys)
- 1/6 LIVE and healthy (RavynAI)

**Security Posture (Stage 2 Complete):**
- 100/100 QA Scorecard (A+)
- Zero wildcard Docker binds
- Zero :latest Docker images
- All secrets externalized to .env (600 permissions)
- PM2 env -i pattern implemented (no secrets in jlist)
- TLS auto-renewal active
- Basic auth + rate limiting on all gateway routes
- 17 internal secrets rotated

**Critical Failures:**
- COREDB PostgreSQL: REFUSING all app connections
- COREDB Redis: REFUSING all app connections
- Stripe: TEST MODE (no production payments)
- Temporal: 42K errors / 8h (DB unreachable)
- FRGCRM API: 100% request failure rate
- Hostinger production DB: Not backed up by ecosystem backup system

---

*End of Ecosystem Revenue Map. Generated 2026-05-24 by Wheeler Autonomous Enforcement Agent.*
