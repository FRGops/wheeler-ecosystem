# Wheeler Autonomous AI Ops Architecture

**Version:** 2.0  
**Last Updated:** 2026-05-24  
**Ecosystem State:** Stage 2 Hardening Complete -- QA Scorecard 100/100 A+

---

## 1. Executive Summary

The Wheeler Autonomous AI Ops Platform is a production-grade, multi-server infrastructure that fuses container orchestration, AI agent management, observability, security enforcement, and self-healing automation into a unified command plane. It manages 41 Docker containers, 19 PM2 processes, 12 AI agent services, 6 database instances, and 20 operational Claude Code skills across 3 physical nodes (2 Hetzner, 1 Hostinger).

The platform operates on four key principles:

1. **Verify-Act-Verify** -- every mutation is bracketed by state capture and health verification
2. **Rollback-First** -- no deployment proceeds without a tested and documented rollback path
3. **No False Greens** -- health checks inspect HTTP response bodies for error signatures, rejecting 200s with error content
4. **Least-Privilege Security** -- all containers bind to 127.0.0.1, UFW enforcement, cap_drop ALL, secrets never in compose files

### Ecosystem Scale (2026-05-24)

| Dimension | Count |
|-----------|-------|
| Physical Servers | 3 (AIOPS, COREDB, Hostinger edge) |
| Docker Containers | 41 (all 127.0.0.1 bound) |
| PM2 Processes | 20 (19 online, 1 intentionally stopped) |
| AI Agent Services | 12 |
| Claude Code Skills | 20 |
| Database Instances | 6 (4 PostgreSQL, 2 Redis, 1 ClickHouse, 1 Neo4j) |
| Compose Stacks | 12 |
| PM2 Ecosystem Configs | 18 |
| UFW Rules | 64 (strict allowlist) |
| Nginx Virtual Hosts | 17 |
| Healthcheck Coverage | 100% of applicable containers |
| Port Security | 100% (0 wildcard binds) |
| Secret Rotation (Phase 1) | 100% (17 internal secrets rotated) |

---

## 2. Architecture Overview

### 2.1 Layered Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    COMMAND & CONTROL LAYER                            │
│  Claude Code (20 skills)  War Room Server  CEO Console (planned)     │
│  /slay  /pm2-health  /docker-health  /rollback  /secrets-scan       │
├─────────────────────────────────────────────────────────────────────┤
│                    CONTROL PLANE                                      │
│  ecosystem-guardian  event-bus-relay  command-center                 │
│  Deployment Engine  (/root/deployment-engine/)                        │
│  Rollback Engine    (/root/rollback-engine/)                          │
├─────────────────────────────────────────────────────────────────────┤
│                    AGENT FLEET (12 PM2 Services)                      │
│  frgcrm-agent  ravyn-agent  horizon-agent  paperless-agent           │
│  prediction-radar-agent  insforge-agent  design-agent                │
│  surplusai-scraper-agent  voice-agent  voice-outreach                │
│  frgcrm-api  surplusai-portal-api                                    │
├─────────────────────────────────────────────────────────────────────┤
│                    AI ROUTING                                         │
│  LiteLLM (PM2 :4049) → Anthropic / OpenAI / DeepSeek                 │
├─────────────────────────────────────────────────────────────────────┤
│                    DATA LAYER                                         │
│  PostgreSQL (COREDB + local)  Redis (COREDB + local)  ClickHouse     │
│  Neo4j (ecosystem graph)  MinIO (object store)                       │
├─────────────────────────────────────────────────────────────────────┤
│                    MONITORING & OBSERVABILITY                         │
│  Prometheus  Loki  Grafana  Alertmanager  Uptime Kuma  Netdata       │
│  Healthchecks  webhook-relay → Discord                                │
├─────────────────────────────────────────────────────────────────────┤
│                    SECURITY LAYER                                     │
│  UFW (64 rules)  127.0.0.1 binds  cap_drop ALL  env-isolated PM2    │
│  Nginx basic auth + rate limiting  Tailscale mesh                    │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Control Flow

```
Operator (human or AI) → Command (skill/CLI/API)
  → Pre-flight Gates (7 gates enforced by deploy-service.sh)
    → State Capture (docker ps, pm2 jlist, ss -tlnp, nginx -T)
      → Execute Mutation (Docker compose, PM2, Nginx)
        → Post-mutation Health Check (body-inspecting HTTP checks)
          → Verification (smoke-test-all.sh across 8 sections)
            → Success: pm2 save, log to audit trail
            → Failure: auto-rollback via rollback-engine/
```

### 2.3 Server Transparency

The control plane abstracts away the server boundary. Commands target "the ecosystem" rather than individual machines. The ecosystem-guardian polls all servers every 60 seconds, discovering:

- Docker containers via `docker ps --format json`
- PM2 processes via `pm2 jlist`
- Nginx routes via `nginx -T`
- Port bindings via `ss -tlnp`
- Network topology via `docker network ls`

Canonical state is stored in the Neo4j ecosystem graph.

---

## 3. Infrastructure Topology

### 3.1 Physical Node Specification

#### AIOPS Node (Hetzner CPX51)
- **Hostname:** wheeler-aiops-01
- **Tailscale IP:** 100.121.230.28
- **Public IP:** 5.78.140.118
- **Spec:** 16 vCPU, 32 GB RAM, 360 GB NVMe, 1 Gbps
- **Role:** Application server -- Docker orchestration, PM2 processes, AI agents, Nginx gateway, monitoring stack, data analytics
- **Docker Containers:** 37
- **PM2 Processes:** 20
- **Nginx Virtual Hosts:** 17
- **Compose Stacks:** 12

#### COREDB Node (Hetzner)
- **Hostname:** wheeler-core-db-01
- **Tailscale IP:** 100.118.166.117
- **Public IP:** 5.78.210.123
- **Spec:** 16 vCPU, 32 GB RAM, 360 GB NVMe
- **Role:** Database server -- PostgreSQL primary, Redis, MinIO, Temporal
- **Access:** UFW tailscale0-only (no public ports)
- **Services:** PostgreSQL (4 databases), Redis, MinIO, Temporal (server + workers), Prometheus/Grafana/Loki for COREDB monitoring

#### Hostinger Edge Node (VPS)
- **Hostname:** srv1476866
- **Tailscale IP:** 100.98.163.17
- **Role:** Edge gateway (users migrated to AIOPS in Stage 2 cleanup)
- **Status:** Legacy services being decommissioned; Traefik routes remaining

### 3.2 Network Topology

```
Internet
  │
  └── Nginx (:443, rate-limited, basic auth on admin paths)
        │
        ├── 17 virtual hosts proxying to 127.0.0.1:<port>
        │     ├── grafana.aiops → 127.0.0.1:3002
        │     ├── kuma.aiops → 127.0.0.1:3001
        │     ├── netdata.aiops → 127.0.0.1:19999
        │     ├── superset.aiops → 127.0.0.1:8088
        │     ├── healthchecks.aiops → 127.0.0.1:3130
        │     ├── langflow.aiops → 127.0.0.1:7860
        │     ├── changes.aiops → 127.0.0.1:5000
        │     ├── prometheus.aiops → 127.0.0.1:9090
        │     ├── loki.aiops → 127.0.0.1:3100
        │     ├── docuseal.aiops → 127.0.0.1:3010
        │     ├── prediction-radar.aiops → 127.0.0.1:8098
        │     ├── openwebui.aiops → 127.0.0.1:3000
        │     ├── grafana-core.aiops → 100.118.166.117:3000
        │     ├── prometheus-core.aiops → 100.118.166.117:9090
        │     ├── 1panel.aiops → 127.0.0.1:8090
        │     ├── crm.aiops → 127.0.0.1:3007
        │     └── clickhouse.aiops → 127.0.0.1:8123
        │
        └── Service mesh (Tailscale)
              ├── AIOPS ↔ COREDB (PostgreSQL, Redis, Temporal)
              └── AIOPS ↔ Hostinger (legacy routing)
```

### 3.3 Service Placement Matrix

| Service Category | AIOPS | COREDB | Hostinger |
|-----------------|-------|--------|-----------|
| Nginx Gateway | 17 vhosts | -- | Traefik (legacy) |
| PostgreSQL | prediction-radar, ravynai, langflow | wheeler_core, frgcrm, usesend, temporal | -- |
| Redis | prediction-radar, docuseal | usesend | -- |
| ClickHouse | analytics | -- | -- |
| Neo4j | ecosystem-graph | -- | -- |
| Monitoring Stack | Prometheus, Loki, Grafana, Alertmanager, Uptime Kuma, Netdata | Prometheus, Grafana, Loki, Uptime Kuma | -- |
| AI Agents | 12 PM2 agent services | -- | -- |
| LiteLLM | PM2 :4049 | -- | -- |
| Temporal | -- | server + workers | -- |
| Prediction Radar | Full stack (API, web, worker, scheduler, DB, Redis) | Worker, scheduler | -- |
| RavynAI | Full stack (app, worker, DB) | -- | -- |
| Analytics | Superset, ClickHouse | -- | -- |
| Document | DocuSeal | -- | -- |
| Monitoring Tools | Healthchecks, ChangeDetection | -- | -- |
| Langflow | Langflow | -- | -- |
| Open WebUI | Open WebUI | -- | -- |
| Usesend | Email stack | DB access | -- |
| Object Storage | -- | MinIO | -- |

### 3.4 Docker Compose Stacks (12)

| Stack Path | Services | Description |
|-----------|----------|-------------|
| /opt/apps/monitoring/ | prometheus, alertmanager, grafana, loki, webhook-relay | Primary observability |
| /opt/apps/prediction-radar-app/ | api, web, worker, scheduler, db, redis, + monitoring | Full trading platform |
| /opt/apps/analytics/ | clickhouse, superset | Data warehouse + BI |
| /opt/apps/langflow/ | langflow | LLM workflow builder |
| /opt/apps/docuseal/ | docuseal, docuseal-redis | Document signing |
| /opt/apps/healthchecks/ | healthchecks | Cron job monitoring |
| /opt/apps/changedetection/ | changedetection | Website change monitor |
| /opt/apps/ravynai-opportunity-graph/ | postgres, app | Opportunity graph |
| /opt/apps/usesend/ | usesend | Email platform |
| /opt/open-webui/ | open-webui | LLM chat interface |
| /opt/stacks/temporal/ | temporal-server, temporal-ui | Workflow engine |
| /opt/stacks/02-aiops/ | base stack | Foundation services |

### 3.5 Docker-run Containers (8 standalone)

| Container | Purpose |
|-----------|---------|
| promtail | Log shipping to Loki |
| netdata | Real-time system monitoring |
| netdata-backup | Netdata standby |
| uptime-kuma | External uptime monitoring |
| uptime-kuma-backup | Uptime Kuma standby |
| frgops-standby | Standby PostgreSQL replica |
| hostinger-health-exporter | External node monitoring |
| ecosystem-graph | Neo4j graph database |

---

## 4. Control Plane Architecture

### 4.1 Control Plane Layers

```
┌──────────────────────────────────────────────────────────────┐
│                    COMMAND INTERFACE                           │
│  Claude Code Skills (20)  War Room Server  CEO Console (fut)  │
├──────────────────────────────────────────────────────────────┤
│                    ORCHESTRATION ENGINE                        │
│  Resource Discovery → Dependency Resolution → Execution        │
├──────────────────────────────────────────────────────────────┤
│                    EXECUTION ADAPTERS                           │
│  Docker Adapter  PM2 Adapter  Nginx Adapter  SSH Adapter      │
├──────────────────────────────────────────────────────────────┤
│                    VERIFICATION LAYER                           │
│  smoke-test-all.sh (8 sections)  healthchecks  metrics  logs  │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 Resource Discovery

The ecosystem-guardian (PM2 process, ~56MB RAM) runs continuous discovery:

```bash
# Discovery commands polled every 60 seconds
docker ps --format json        # Container inventory
pm2 jlist                      # PM2 process inventory
nginx -T                       # Nginx routing table
ss -tlnp                       # Port bindings
docker network ls              # Network topology
```

Canonical state is published to the Neo4j ecosystem-graph container and cross-referenced against the desired state defined in governance rules.

### 4.3 Command Center

Two PM2 processes provide command and control:

- **command-center** (48MB): Core orchestration API, dispatches commands across the ecosystem
- **war-room-server** (59MB, port 8091): Incident command interface, coordinates remediation during outages
- **event-bus-relay** (57MB): Propagates state change events between agents and systems

### 4.4 Deployment Gates (7 Gates)

Every deployment through the engine at `/root/deployment-engine/deploy-service.sh` must pass:

```
GATE 1 — State Capture:
  Full ecosystem snapshot before any mutation

GATE 2 — Dependency Health:
  All DEPENDS_ON services healthy

GATE 3 — Resource Headroom:
  >20% free RAM and >10% free disk on target server

GATE 4 — Configuration Valid:
  docker compose config --quiet or pm2 config syntax check

GATE 5 — Secret Availability:
  All ${ENV_VARS} referenced resolve to non-empty values

GATE 6 — Rollback Path:
  Previous image/commit tagged and accessible

GATE 7 — Governance Compliance:
  cap_drop ALL, mem_limit, cpus, 127.0.0.1 bind, healthcheck defined
```

### 4.5 Decision Authority Levels

| Level | Name | Description | Examples |
|-------|------|-------------|---------|
| 0 | Advisory | AI recommends, human decides and executes | New failure patterns, destructive remediation |
| 1 | Assisted | AI drafts plan, human approves, AI executes | Memory limit scaling, secret rotation |
| 2 | Supervised | AI executes, human reviews within 5min window | Container restart, PM2 restart |
| 3 | Autonomous | AI executes, human informed afterward | Log rotation, cache flush, dead connection cleanup |

---

## 5. Agent Fleet Design

### 5.1 Agent Topology

All 12 agent services run as PM2 processes on the AIOPS node and communicate via LiteLLM for LLM access and COREDB PostgreSQL for persistent state.

```
                    ┌──────────────────┐
                    │   LiteLLM Proxy  │
                    │   (PM2 :4049)    │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
         Anthropic       OpenAI         DeepSeek
              │              │              │
    ┌─────────┴─────────┐    │    ┌────────┴────────┐
    │  9 Agent Services  │    │    │  3 Agent Services│
    └───────────────────┘    │    └─────────────────┘
                             │
    All agents → COREDB PostgreSQL via FRGOPS_DATABASE_URL
    All agents → event-bus-relay for inter-agent events
```

### 5.2 Agent Roles and Resource Footprint

| Agent Service | PM2 Name | RAM | Role |
|--------------|----------|-----|------|
| FRGCRM API | frgcrm-api | 235MB | Primary CRM backend API |
| FRGCRM Agent | frgcrm-agent-svc | 94MB | CRM intelligence and automation |
| SurplusAI Portal | surplusai-portal-api | 103MB | Portal backend API |
| SurplusAI Scraper | surplusai-scraper-agent-svc | 108MB | Data acquisition and scraping |
| Prediction Radar | prediction-radar-agent-svc | 110MB | Market prediction intelligence |
| RavynAI | ravyn-agent-svc | 108MB | Opportunity graph analysis |
| Horizon | horizon-agent-svc | 105MB | External threat/opportunity scanning |
| Insforge | insforge-agent-svc | 74MB | Insurance intelligence |
| Paperless | paperless-agent-svc | 104MB | Document processing |
| Voice Agent | voice-agent-svc | 104MB | Voice call AI |
| Voice Outreach | voice-outreach-service | 54MB | Outbound calling (Twilio + ElevenLabs) |
| Design Agent | design-agent-svc | 109MB | System design and architecture |
| LiteLLM | litellm | 377MB | LLM proxy/gateway (largest PM2 process) |
| Ecosystem Guardian | ecosystem-guardian | 56MB | State monitoring and discovery |
| Event Bus | event-bus-relay | 57MB | Inter-agent event routing |
| War Room | war-room-server | 59MB | Incident command interface |
| OpenClaw Dashboard | openclaw-dashboard | 60MB | Claude Code gateway dashboard |
| Command Center | command-center | 48MB | Core orchestration API |

### 5.3 Agent Communication Patterns

```
Service-to-Service:    INTERNAL_API_KEY / FRGCRM_INTERNAL_TOKEN
Agent-to-Database:     FRGOPS_DATABASE_URL → COREDB PostgreSQL (:5432)
Agent-to-LLM:          via LiteLLM proxy (LITELLM_BASE_URL :4049)
Agent Discovery:       ecosystem-guardian monitors PM2 state
Agent Events:          event-bus-relay for publish/subscribe
Cross-Server:          SSH over Tailscale mesh IPs
```

### 5.4 Agent Coordination

Agents coordinate through three mechanisms:

1. **event-bus-relay** -- publish/subscribe event bus for state changes, alerts, and inter-agent messages
2. **COREDB PostgreSQL** -- shared database for persistent state (databases: wheeler_core, frgcrm, usesend, temporal)
3. **ecosystem-guardian** -- continuous discovery and state publication to Neo4j ecosystem graph

Each agent has its own ecosystem.config.js file under `/opt/apps/<agent-name>/ecosystem.config.js` with environment variables pointing to shared resources.

---

## 6. Monitoring & Observability Stack

### 6.1 Stack Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        OBSERVABILITY LAYER                        │
│                                                                   │
│  Prometheus (:9090)       Loki (:3100)        Uptime Kuma (:3001) │
│  Alertmanager (:9093)     promtail (agent)                        │
│  webhook-relay (:8085)  → Discord #alerts                         │
│                                                                   │
│  Grafana (:3002) — dashboards for:                                │
│    ├── Docker container metrics                                   │
│    ├── PM2 process metrics (restarts, memory, CPU)                │
│    ├── PostgreSQL query performance                               │
│    ├── Redis memory and hit rates                                 │
│    ├── Prediction Radar trading metrics                           │
│    └── AI agent health and request rates                          │
│                                                                   │
│  Netdata (:19999) — real-time system monitoring                   │
│  Healthchecks (:8000) — cron job and scheduled task monitoring    │
│                                                                   │
│  Exporters:                                                       │
│    node_exporter       — system metrics (CPU, RAM, disk, net)     │
│    postgres_exporter   — PostgreSQL query and connection metrics  │
│    redis_exporter      — Redis memory, hit rate, connected clients│
│    hostinger-health-exporter  — external node health              │
│    pushgateway         — accepts batch job metrics                │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Alert Pipeline

```
Prometheus evaluates alert-rules.yml (30s interval)
  → Firing alerts sent to Alertmanager (:9093)
    → Routes to webhook-relay (:8085)
      → Formats for Discord webhook
        → Posts to #war-room (critical) or #monitoring (warnings)
```

### 6.3 Health Check Coverage

The functional-healthcheck.sh script (used by /slay) tests 20 endpoints across all services:

| Service | Port | Health Path | Check Type |
|---------|------|-------------|------------|
| frgcrm-api | 8001 | /health | HTTP 200 + body inspection |
| surplusai-portal-api | 8103 | /docs | HTTP 200 |
| litellm | 4049 | /health | HTTP 401 (auth = alive) |
| war-room-server | 8021 | / | HTTP 200 |
| openclaw-dashboard | 8110 | / | HTTP 200 |
| ravyn-agent-svc | 8003 | /health | HTTP 200 |
| frgcrm-agent-svc | 8002 | /health | HTTP 200 |
| horizon-agent-svc | 8006 | /health | HTTP 200 |
| surplusai-scraper-agent | 8009 | /health | HTTP 200 |
| voice-agent-svc | 8014 | /health | HTTP 200 |
| paperless-agent-svc | 8012 | /health | HTTP 200 |
| prediction-radar-agent | 8011 | /health | HTTP 200 |
| insforge-agent-svc | 8008 | /health | HTTP 200 |
| design-agent-svc | 8020 | /health | HTTP 200 |
| prometheus | 9090 | /-/healthy | HTTP 200 |
| alertmanager | 9093 | /-/healthy | HTTP 200 |
| grafana | 3002 | /api/health | HTTP 200 |
| loki | 3100 | /ready | HTTP 200 |
| COREDB PostgreSQL | 5432 | (TCP) | pg_isready |
| COREDB Redis | 6379 | (TCP) | PING PONG |

### 6.4 Smoke Test Validation

The master smoke test (`/root/scripts/smoke-test-all.sh`) runs across 8 sections:

```
Section 1 — Public Routes:    HTTP 200 + body inspection (no error signatures)
Section 2 — AI Routing:       LiteLLM health, DeepSeek model reachability
Section 3 — Database:         PostgreSQL connectivity + key databases exist
Section 4 — Redis:            PING PONG
Section 5 — MinIO:            Health endpoint + console port
Section 6 — Monitoring:       Grafana, Prometheus, Loki, Uptime Kuma
Section 7 — Infrastructure:   Tailscale mesh, PM2 status, Docker containers
Section 8 — Sub-Scripts:      Specialized validators (--full flag)
```

**No False Greens enforcement:** The `_http_check()` function inspects HTTP response bodies for error signatures -- nginx error pages, HTML error titles, stack traces, JSON error envelopes. A 200 with an error body is treated as FAIL.

### 6.5 Log Architecture

```
All containers → json-file driver (10MB per file, max 3 files)
  → promtail (Docker-run container)
    → Loki (:3100, 1-year retention)
      → Grafana log exploration

PM2 processes → pm2-logrotate (cron job)
  → /root/.pm2/logs/<process>-out.log
  → /root/.pm2/logs/<process>-error.log
```

---

## 7. Self-Healing Architecture

*(Detailed in `/root/SELF_HEALING_ENGINE.md`)*

The self-healing system follows the **DETECT -> DIAGNOSE -> REMEDIATE -> VERIFY -> LEARN** loop with bounded autonomy:

| Tier | Authority | Latency | Examples |
|------|-----------|---------|----------|
| 0 | Advisory (human executes) | Immediate | New failure patterns, destructive operations |
| 1 | Assisted (human approves) | <2min | Memory scaling, fallback routing |
| 2 | Supervised (5min override) | <60s | Container restart, PM2 restart |
| 3 | Autonomous (informed) | <30s | Log rotation, cache flush, connection cleanup |

Current auto-healing in place:
- **Cron autoheal.sh** every 2 minutes: restarts stopped Docker containers and crashed PM2 processes
- **wheeler-lockdown-watchdog.sh** every 5 minutes: verifies port bindings, restores lockdown on drift
- **Docker restart policies:** all containers set to `restart: unless-stopped`
- **PM2 autorestart:** all processes configured with `autorestart: true`, max 10 retries, 5s delay

---

## 8. Security Architecture

### 8.1 Defense-in-Depth Layers

```
Layer 1: Network Security
  ├── UFW: 64 rules, strict allowlist
  ├── COREDB: UFW tailscale0-only (no public access)
  ├── Nginx: rate limiting on all paths
  ├── Nginx: basic auth on admin paths (/grafana, /prometheus, /superset, /langflow)
  ├── Docker: ALL ports bound to 127.0.0.1 (0 wildcard binds)
  └── Tailscale: encrypted mesh, ACL-restricted

Layer 2: Container Security
  ├── cap_drop: ALL on every container
  ├── cap_add: minimal required capabilities (documented exceptions)
  ├── mem_limit + cpus on every container
  ├── Non-root user where possible (26/40 containers)
  └── Read-only filesystems where possible

Layer 3: Application Security
  ├── All secrets in .env files (0 hardcoded in compose files)
  ├── Internal passwords rotated 2026-05-24 (hex-encoded, unique)
  ├── Internal JWT/tokens rotated 2026-05-24
  ├── JWT-based service authentication
  └── INTERNAL_API_KEY for service-to-service auth

Layer 4: PM2 Process Security
  ├── env -i delete+start pattern for env var changes
  ├── PM2 jlist secret scan (avoids credential leakage in process state)
  ├── Never use pm2 restart --update-env (injects shell env into PM2 state)
  └── pm2 save --force after clean starts

Layer 5: Observability Security
  ├── All containers healthchecked
  ├── Prometheus metrics on all services
  ├── Loki centralized logging
  └── Alert rules for security boundary violations
```

### 8.2 Secret Management

All secrets reside in server-local `.env` files with `chmod 600`:

```
/opt/wheeler-core/.env                   (COREDB: PostgreSQL, Redis, MinIO)
/opt/wheeler/apps/frgcrm/api/.env        (AIOPS: main API)
/opt/apps/prediction-radar-app/.env      (AIOPS: trading platform)
/opt/apps/usesend/.env                   (AIOPS: email platform)
/opt/apps/monitoring/.env                (AIOPS: Grafana admin, Discord webhook)
/opt/apps/analytics/.env                 (AIOPS: ClickHouse, Superset)
/opt/apps/langflow/.env                  (AIOPS: Langflow)
/opt/apps/docuseal/.env                  (AIOPS: DocuSeal)
/opt/apps/ravynai-opportunity-graph/.env (AIOPS: RavynAI)
/opt/open-webui/.env                     (AIOPS: OpenWebUI)
/opt/stacks/temporal/.env                (AIOPS: Temporal)
```

**Rotation status (2026-05-24):**
- Internal DB/Redis passwords: 5 rotated to unique hex values
- Internal JWT/tokens: 12 rotated
- External API keys: 60+ pending (requires dashboard access for each provider)

### 8.3 Port Bind Security

All services are bound to 127.0.0.1 except:
- SSH (0.0.0.0:22) -- required for remote administration
- Tailscale (tailscale0 interface) -- encrypted mesh networking
- Nginx (0.0.0.0:443) -- public HTTPS gateway with rate limiting

Verified every 5 minutes by `/opt/wheeler-ecosystem/enforcement/wheeler-lockdown-watchdog.sh`:

```bash
# Check for non-loopback, non-Tailscale, non-SSH binds
ss -tlnp | awk '$4 !~ /127.0.0.1|::1|100\.121\.230\.28|:22/ && NR>1 {print}'
```

---

## 9. Gateway & Routing Design

### 9.1 Nginx Gateway

The Nginx gateway handles all external traffic on the AIOPS node:

```
Config: /etc/nginx/sites-enabled/aiops-gateway
Port:   443 (HTTPS), 80 (redirects to 443)

Security:
  - Rate limiting: burst=20, nodelay on all paths
  - Basic auth: /grafana, /prometheus, /superset, /langflow
  - Catch-all: returns 444 "Wheeler AI Ops Gateway -- healthy"

17 virtual hosts routing to internal services:
  - Direct (127.0.0.1:<port>) — local services
  - Cross-server (100.118.166.117:<port>) — COREDB Grafana and Prometheus
```

### 9.2 Tailscale Mesh

All three nodes connected via Tailscale mesh:

| Node | Tailscale IP | Role |
|------|-------------|------|
| AIOPS | 100.121.230.28 | Application gateway |
| COREDB | 100.118.166.117 | Database server |
| Hostinger | 100.98.163.17 | Edge (legacy) |

Cross-server traffic flows exclusively over Tailscale:
- AIOPS → COREDB: PostgreSQL (:5432), Redis (:6379), Temporal (:7233)
- AIOPS → COREDB: Grafana (:3000), Prometheus (:9090) for monitoring dashboards
- AIOPS → Hostinger: Legacy service connections (being decommissioned)

### 9.3 Service Mesh (Planned)

Full service mesh with mTLS, circuit breakers, and canary deployments is planned for Phase 3, building on the current Tailscale foundation and ecosystem graph.

---

## 10. Data Architecture

### 10.1 Database Topology

```
COREDB PostgreSQL (:5432, UFW tailscale0 only)
├── wheeler_core  — FRGCRM API, SurplusAI Portal (primary application DB)
├── frgcrm        — Agent services (9 agents share this DB)
├── usesend       — Email platform
└── temporal      — Workflow engine state

AIOPS Local PostgreSQL (various ports)
├── prediction-radar-app-db   — Trading data (historical prices, signals)
├── ravynai-postgres           — Opportunity graph data
├── langflow                   — LLM workflow state
└── frgops-standby             — Standby replica of COREDB

AIOPS Local Redis (various ports)
├── prediction-radar-app-redis — Trading cache (real-time prices)
└── docuseal-redis             — Document processing queue

COREDB Redis (:6379, UFW tailscale0 only)
└── usesend                    — Email queue, caching, session state

AIOPS ClickHouse (:8123)
└── analytics                  — Superset data warehouse (event analytics)

AIOPS Neo4j (:7687)
└── ecosystem-graph            — Infrastructure dependency and state graph
```

### 10.2 Data Flows

```
Users → Nginx (:443)
  → Backend APIs (:8001/:8002)
    → COREDB PostgreSQL (:5432 via Tailscale)
    → COREDB Redis (:6379 via Tailscale)

PM2 Agents → LiteLLM (:4049)
  → Anthropic/OpenAI/DeepSeek APIs
  → COREDB PostgreSQL via FRGOPS_DATABASE_URL
  → FRGCRM API (service-to-service with INTERNAL_API_KEY)

Prediction Radar → Local PostgreSQL + Redis
  → Polygon, Alpaca, Kalshi, Polymarket, HyperLiquid APIs
  → COREDB PostgreSQL for aggregated data

Logs: Docker + PM2 → promtail → Loki
Metrics: Exporters → Prometheus → Alertmanager → webhook-relay → Discord
Uptime: Uptime Kuma → external target health checks
```

### 10.3 Backup Strategy

```bash
# Daily backup at 03:00 UTC
pg_dump -h <host> -U postgres --format=custom <database> > /opt/backups/<db>-<date>.dump

# Volume backups
tar czf /opt/backups/volumes/<volume>-<date>.tar.gz /var/lib/docker/volumes/<volume>

# Retention
Daily:   7 days (on-server)
Weekly:  4 weeks (on-server)
Monthly: 3 months (off-site via rsync)

# Databases backed up
prediction_radar, ravynai, healthchecks, superset, frgops, frgcrm, usesend, temporal
```

---

## 11. Deployment & Rollback Pipeline

### 11.1 Deployment Engine

Located at `/root/deployment-engine/`, the deployment engine supports four service types:

| Type | Deployment Script | Detection Method |
|------|-------------------|-----------------|
| Docker | deploy-docker-service.sh | docker-compose.yml or existing container |
| PM2 | deploy-pm2-service.sh | ecosystem.config.js or PM2 jlist match |
| Static | deploy-static-service.sh | /public or /dist directory |
| Systemd | systemctl restart | systemd unit file |

**Pipeline (deploy-service.sh):**

```
Phase 1: Preflight (7 gates)
Phase 2: Pre-deploy Backup (configs, env, state)
Phase 3: Deploy (type-specific)
Phase 4: Post-deploy Healthcheck (10 retries, 60s timeout)
Phase 5: Verification (smoke-test-all.sh --service=<name>)
Phase 6: Auto-rollback on failure

Exit codes:
  0  Success
  1  Preflight error
  2  Deploy failed (no rollback)
  3  Deploy failed, rollback succeeded
  4  Deploy failed, rollback also failed (CRITICAL)
  5  Health check failed
```

### 11.2 Rollback Engine

Located at `/root/rollback-engine/`, the rollback orchestrator executes a 5-phase process:

```
Phase 1 — Discovery:
  Detect service type (docker/pm2/static/routing)
  Find latest backup or version-tagged backup
  Verify backup integrity

Phase 2 — Execute:
  Restore .env files (restore-env.sh)
  Restore service (restore-docker.sh, restore-pm2.sh, or restore-routing.sh)

Phase 3 — Verification:
  Check container health / PM2 status / HTTP health endpoints
  Verify baseline resource usage

Phase 4 — Preservation:
  Preserve failed deployment logs, system state snapshot

Phase 5 — Notification:
  Send rollback alert to Discord with duration and outcome

Auto-rollback triggers:
  - Container healthcheck fails 3 consecutive times after deploy
  - Error rate >2x baseline in 5 minutes
  - Memory exceeds limit within 2 minutes
  - PM2 process restarts >2 times in first 60 seconds
```

### 11.3 Validation Scripts

Located at `/root/scripts/`:

| Script | Purpose |
|--------|---------|
| smoke-test-all.sh | Master smoke test (8 sections) |
| ai-routing-validation.sh | LiteLLM health, DeepSeek model, latency, fallback testing (11 sections) |
| db-validation.sh | PostgreSQL connectivity and database checks |
| redis-validation.sh | Redis PING and memory checks |
| docker-validation.sh | Container health and governance compliance |
| pm2-validation.sh | PM2 process status and restart loop detection |
| minio-validation.sh | Object storage health |
| public-route-check.sh | External HTTP route validation |
| revenue-healthcheck.sh | Revenue-critical service health |
| readiness-scorecard.sh | Production readiness assessment |

---

## 12. Future Scaling Architecture

### 12.1 Phase 3 (3-6 Months)

```
Add Hetzner CX32 worker node for trading/agents:
  - Offload Prediction Radar workers
  - Offload AI agent processing
  - Dedicated ClickHouse analytics server

Intelligent healing:
  - Cascade diagnosis with ecosystem graph (Neo4j)
  - Predictive healing (fix before failure)
  - Cross-server automated healing
  - LiteLLM auto-failover to backup LLM provider
```

### 12.2 Phase 4 (6-12 Months)

```
Docker Swarm across 2-3 Hetzner nodes:
  - Replica services behind Nginx load balancer
  - Read replicas for PostgreSQL
  - Redis Sentinel for HA
  - CEO Command Console
  - Revenue intelligence dashboard

Full autonomy:
  - AI-governed healing decisions within bounded authority
  - Automated incident post-mortems
  - Continuous improvement from incident knowledge base
```

### 12.3 Phase 5 (12+ Months)

```
Kubernetes (k3s) on Hetzner cloud:
  - Hostinger stays as edge gateway
  - Horizontal pod autoscaling
  - Service mesh with mTLS
  - Multi-region disaster recovery
  - Predictive scaling based on ML models
```

### 12.4 Architectural Principles for Scaling

1. **Server abstraction** -- commands target "the ecosystem," not individual machines
2. **Dependency-first orchestration** -- all scaling decisions gated by ecosystem graph analysis
3. **Observability-driven** -- no new service without metrics, logs, and healthchecks
4. **Security at every layer** -- defense-in-depth from network to application
5. **Rollback from day one** -- every deployment has a tested reverse path
6. **Verify-Act-Verify** -- the foundational pattern that prevents false greens

---

## Appendix A: Ecosystem Health Scorecard (2026-05-24)

| QA Domain | Pass/Fail | Details |
|-----------|-----------|---------|
| Container Health | PASS | 37 containers healthy |
| PM2 Status | PASS | 19/20 online (1 intentionally stopped) |
| Port Security | PASS | 0 wildcard binds |
| UFW Compliance | PASS | 64 rules, strict allowlist |
| cap_drop ALL | PASS | All containers compliant |
| Resource Limits | PASS | All containers have mem_limit + cpus |
| Secret Hygiene | PASS | 0 secrets in jlist, 0 in compose files |
| Healthcheck Coverage | PASS | All applicable containers |
| :latest Hygiene | PASS | 0 :latest images |
| Nginx Security | PASS | Rate limiting + basic auth on admin paths |
| Tailscale Mesh | PASS | 3 nodes connected |
| Deployment Engine | PASS | /root/deployment-engine/ operational |
| Rollback Engine | PASS | /root/rollback-engine/ operational |
| Smoke Tests | PASS | smoke-test-all.sh 8 sections passing |
| AI Routing | PASS | LiteLLM + DeepSeek operational |
| Monitoring Stack | PASS | Prometheus/Loki/Grafana healthy |
| Backup System | PASS | Daily backups running |
| **Overall** | **100/100 A+** | **Stage 2 hardened** |

## Appendix B: Directory Map

```
/root/
├── WHEELER_BRAIN_OS/          Architecture and design documents
│   └── architecture/          Detailed architecture documents
├── deployment-engine/         Master deployment pipeline
│   ├── deploy-service.sh      Main orchestrator
│   ├── preflight-check.sh     7-gate preflight validator
│   ├── deploy-docker-service.sh
│   ├── deploy-pm2-service.sh
│   ├── post-deploy-healthcheck.sh
│   ├── verify-deployment.sh
│   └── rollback-deployment.sh
├── rollback-engine/           Master rollback orchestrator
│   ├── rollback.sh            5-phase rollback
│   ├── restore-env.sh         .env restore
│   ├── restore-docker.sh      Docker state restore
│   ├── restore-pm2.sh         PM2 state restore
│   └── restore-routing.sh     Nginx/Traefik restore
├── scripts/                   Validation and health scripts
│   ├── smoke-test-all.sh      Master smoke test (8 sections)
│   ├── ai-routing-validation.sh  (11 sections)
│   ├── db-validation.sh
│   ├── docker-validation.sh
│   ├── pm2-validation.sh
│   └── revenue-healthcheck.sh
├── .claude/skills/            20 Claude Code skills
├── backups/                   Backup storage
├── configs/                   Service configuration templates
├── infrastructure/            Infrastructure configuration
└── docs/                      Generated reports
```

---

*End of Autonomous AI Ops Architecture*
