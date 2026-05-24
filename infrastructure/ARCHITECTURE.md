# Wheeler AIOps Distributed Infrastructure Architecture
## Phase 2 — Production-Grade Multi-Server AI Operations Stack

---

## ARCHITECTURE DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PUBLIC INTERNET                                 │
│                                   │                                          │
│                            ┌──────┴──────┐                                   │
│                            │  Cloudflare │  (DNS + DDoS + WAF)               │
│                            └──────┬──────┘                                   │
│                                   │                                          │
│                    ┌──────────────┴──────────────┐                            │
│                    │                             │                            │
│         ┌─────────┴──────────┐       ┌──────────┴──────────┐                 │
│         │  HOSTINGER VPS     │       │  HETZNER CPX51      │                 │
│         │  Edge / Frontend   │       │  Primary AIOps      │                 │
│         │  Public IP: x.x.x.x│       │  Public IP: 5.78... │                 │
│         └────────────────────┘       └─────────────────────┘                 │
│                    │                             │                            │
│    ┌───────────────┼───────────────┐    ┌────────┼─────────────────────┐      │
│    │     TRAEFIK (Public Edge)     │    │  TRAEFIK (Internal Router)   │      │
│    │  :80 → HTTPS redirect         │    │  :80/:443 → internal svc     │      │
│    │  :443 → TLS termination       │    │  TLS + mTLS for inter-svc    │      │
│    └───────────────┼───────────────┘    └────────┼─────────────────────┘      │
│                    │                             │                            │
│    ┌───────────────┼───────────────┐    ┌────────┼─────────────────────┐      │
│    │  PUBLIC-FACING SERVICES       │    │  BACKEND / AI / DATA TIER    │      │
│    │                              │    │                              │      │
│    │  • FRGops / FRGCRM          │    │  • Prediction Radar (full)   │      │
│    │  • Chatwoot                  │    │  • RavynAI (full stack)      │      │
│    │  • n8n (light workflows)     │    │  • AI Agent Runtimes         │      │
│    │  • Docuseal                  │    │  • Superset + ClickHouse     │      │
│    │  • LiteLLM Proxy             │    │  • ChangeDetection           │      │
│    │  • MinIO (light obj store)   │    │  • Healthchecks              │      │
│    │  • Webhook Receiver          │    │  • OSINT / Spiderfoot        │      │
│    │  • Static Sites / APIs       │    │  • Browser Automation        │      │
│    │                              │    │  • Trading Engine Workers    │      │
│    └──────────────────────────────┘    │  • Realtime Feed Handlers    │      │
│                                         │  • Automation Workers        │      │
│    ┌──────────────────────────────┐    │  • Postgres (primary AI DB)  │      │
│    │  LIGHT DATA TIER            │    │  • Redis (cache/pubsub)       │      │
│    │  • Postgres (FRGops only)   │    │  • RabbitMQ / NATS            │      │
│    │  • Redis (FRGops cache)     │    │                              │      │
│    └──────────────────────────────┘    └──────────────────────────────┘      │
│                                                                              │
│                    ┌──────────────────────────────┐                           │
│                    │     TAILSCALE MESH (10.x)     │                           │
│                    │  ┌──────────┐  ┌───────────┐  │                           │
│                    │  │Hostinger │  │  Hetzner  │  │                           │
│                    │  │100.98.x  │  │100.121.x  │  │                           │
│                    │  └──────────┘  └───────────┘  │                           │
│                    │      Secure admin + DB access  │                           │
│                    └──────────────────────────────┘                           │
│                                                                              │
│    ┌─────────────────────────────────────────────────────────────────────┐   │
│    │                        MONITORING PLANE                              │   │
│    │  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌──────────────────┐    │   │
│    │  │ Netdata  │  │Prometheus│  │  Grafana  │  │  Uptime Kuma    │    │   │
│    │  │(realtime)│  │(metrics) │  │(dashboards│  │(blackbox+alerts)│    │   │
│    │  └──────────┘  └──────────┘  └───────────┘  └──────────────────┘    │   │
│    └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│    ┌─────────────────────────────────────────────────────────────────────┐   │
│    │                        SECURITY PLANE                               │   │
│    │  UFW → Fail2ban → CrowdSec → Tailscale ACLs → Docker network isol   │   │
│    └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## SERVER SPECIFICATIONS

### Hetzner CPX51 — PRIMARY AIOPS ORCHESTRATOR
- **CPU:** 16 vCPUs (AMD EPYC)
- **RAM:** 32 GB
- **Storage:** 360 GB NVMe
- **Network:** 1 Gbps
- **Role:** All heavy compute, AI, databases, analytics, monitoring
- **Access:** Public web ports (80/443 via Traefik) + Admin via Tailscale ONLY

### Hostinger VPS — PUBLIC EDGE / FRONTEND
- **CPU:** 4-8 vCPUs
- **RAM:** 8-16 GB
- **Role:** Reverse proxy, lightweight public apps, static sites
- **Access:** Public web ports (80/443) + Admin via Tailscale ONLY

---

## SERVICE PLACEMENT MATRIX

### HETZNER CPX51 — Services Running Here

| Service                  | Port  | Network        | Access    | Docker Network   |
|--------------------------|-------|----------------|-----------|------------------|
| **Traefik (Internal)**   | 80/443| public         | public    | traefik-public   |
| **Prediction Radar API** | 8000  | internal       | tailscale | prediction-radar |
| **Prediction Radar Web** | 8098  | traefik        | public    | prediction-radar |
| **Prediction Radar Worker**| -   | internal       | internal  | prediction-radar |
| **Prediction Radar Scheduler**|- | internal     | internal  | prediction-radar |
| **Prediction Radar DB**  | 5433  | internal       | internal  | prediction-radar |
| **Prediction Radar Redis**|6379 | internal       | internal  | prediction-radar |
| **RavynAI API**          | 8007  | traefik        | public    | ravynai          |
| **RavynAI Worker**       | -     | internal       | internal  | ravynai          |
| **RavynAI DB**           | 5434  | internal       | tailscale | ravynai          |
| **Superset**             | 8088  | traefik        | public    | analytics        |
| **ClickHouse**           | 8123  | internal       | tailscale | analytics        |
| **ClickHouse Native**    | 9000  | internal       | internal  | analytics        |
| **ChangeDetection**      | 5000  | traefik        | public    | automation       |
| **Healthchecks**         | 3130  | traefik        | public    | monitoring       |
| **Spiderfoot**           | 8080  | internal       | tailscale | osint            |
| **Browser Automation**   | 3000  | internal       | tailscale | automation       |
| **AI Agent Runtimes**    | 8001+ | internal       | internal  | ai-agents        |
| **Trading Workers**      | -     | internal       | internal  | trading          |
| **Realtime Feed Handler**| -     | internal       | internal  | trading          |
| **NATS/RabbitMQ**        | 4222  | internal       | internal  | messaging        |
| **Grafana**              | 3002  | traefik        | public    | monitoring       |
| **Prometheus**           | 9090  | internal       | tailscale | monitoring       |
| **Netdata**              | 19999 | internal       | tailscale | monitoring       |
| **Uptime Kuma**          | 3001  | traefik        | public    | monitoring       |
| **Portainer**            | 9443  | internal       | tailscale | management       |
| **Dockge**               | 5001  | internal       | tailscale | management       |
| **PostgreSQL (AIOps)**   | 5432  | internal       | internal  | data             |
| **Redis (AIOps)**        | 6379  | internal       | internal  | data             |

### HOSTINGER VPS — Services Running Here

| Service                  | Port  | Network        | Access    | Docker Network   |
|--------------------------|-------|----------------|-----------|------------------|
| **Traefik (Public Edge)**| 80/443| public         | public    | traefik-public   |
| **FRGops / FRGCRM**      | 3000  | traefik        | public    | frgops           |
| **Chatwoot**             | 3000  | traefik        | public    | frgops           |
| **n8n (light)**          | 5678  | traefik        | public    | automation       |
| **Docuseal**             | 3000  | traefik        | public    | frgops           |
| **LiteLLM Proxy**        | 4000  | traefik        | public    | ai-proxy         |
| **MinIO**                | 9001  | traefik        | public    | storage          |
| **Webhook Receiver**     | 9000  | traefik        | public    | webhooks         |
| **Static Sites**         | -     | traefik        | public    | static           |
| **PostgreSQL (FRGops)**  | 5432  | internal       | internal  | data             |
| **Redis (FRGops)**       | 6379  | internal       | internal  | data             |

---

## DOCKER NETWORK ARCHITECTURE

```
┌────────────────────────────────────────────────────────────┐
│                   DOCKER NETWORK TOPOLOGY                    │
│                                                             │
│  ┌─────────────────────┐    ┌─────────────────────┐         │
│  │  traefik-public      │    │  traefik-public      │         │
│  │  (172.20.0.0/24)    │    │  (172.20.0.0/24)    │         │
│  │                     │    │                     │         │
│  │  Traefik ───────────┼────┼──→ Hostinger apps  │         │
│  │  Hetzner apps       │    │                     │         │
│  └─────────────────────┘    └─────────────────────┘         │
│                                                             │
│  Internal networks (Hetzner, no external egress):           │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │ prediction-  │ │  analytics   │ │  ai-agents   │        │
│  │ radar        │ │  (172.22.x)  │ │  (172.24.x)  │        │
│  │ (172.21.x)   │ │              │ │              │        │
│  │              │ │  Superset    │ │  Agent APIs   │        │
│  │  API + Web   │ │  ClickHouse  │ │  Workers      │        │
│  │  Worker+Sched│ │              │ │              │        │
│  │  DB + Redis  │ └──────────────┘ └──────────────┘        │
│  └──────────────┘                                           │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │  ravynai     │ │  trading     │ │  messaging   │        │
│  │  (172.25.x)  │ │  (172.26.x)  │ │  (172.27.x)  │        │
│  │              │ │              │ │              │        │
│  │  API + Worker│ │  Workers     │ │  NATS/Rabbit │        │
│  │  DB          │ │  Feed ingest │ │              │        │
│  └──────────────┘ └──────────────┘ └──────────────┘        │
│  ┌──────────────┐ ┌──────────────┐                         │
│  │  automation  │ │  data        │                         │
│  │  (172.28.x)  │ │  (172.29.x)  │                         │
│  │              │ │              │                         │
│  │  ChangeDetect│ │  Postgres    │                         │
│  │  BrowserAuto │ │  Redis       │                         │
│  └──────────────┘ └──────────────┘                         │
└────────────────────────────────────────────────────────────┘
```

---

## REVERSE PROXY ROUTING TABLE

### Hostinger Traefik (Public Entry Point)

```
Domain                          → Upstream (Hetzner via Tailscale)
─────────────────────────────────────────────────────────────────
predictionradar.wheeler.ai      → http://100.121.230.28:8098
ravynai.wheeler.ai              → http://100.121.230.28:8007
superset.wheeler.ai             → http://100.121.230.28:8088
healthchecks.wheeler.ai         → http://100.121.230.28:3130
changedetect.wheeler.ai         → http://100.121.230.28:5000
grafana.wheeler.ai              → http://100.121.230.28:3002
uptime.wheeler.ai               → http://100.121.230.28:3001

frgops.wheeler.ai               → localhost:3000  (local app)
chatwoot.wheeler.ai             → localhost:3000  (local app)
n8n.wheeler.ai                  → localhost:5678  (local app)
docuseal.wheeler.ai             → localhost:3000  (local app)
litellm.wheeler.ai              → localhost:4000  (local app)
```

### Hetzner Traefik (Internal Router — direct access fallback)

```
Domain                          → Upstream
─────────────────────────────────────────────────────────
*.internal.wheeler.ai           → respective local containers
```

---

## MONITORING & ALERTING ARCHITECTURE

```
┌──────────────────────────────────────────────────────────┐
│                   OBSERVABILITY STACK                     │
│                                                           │
│  Layer 1: SYSTEM HEALTH (Netdata)                         │
│  ├─ CPU, RAM, Disk, Network per-second                    │
│  ├─ Docker container metrics                              │
│  ├─ Alarms → email/slack/webhook                          │
│  └─ netdata.wheeler.ai (Tailscale-only)                   │
│                                                           │
│  Layer 2: METRICS + DASHBOARDS (Prometheus + Grafana)     │
│  ├─ Custom app metrics (API latency, queue depth)         │
│  ├─ Node exporter on both servers                         │
│  ├─ cAdvisor for container metrics                        │
│  ├─ Postgres exporter                                     │
│  ├─ Redis exporter                                        │
│  └─ AlertManager → PagerDuty/Slack/Email                  │
│                                                           │
│  Layer 3: BLACKBOX + SYNTHETIC (Uptime Kuma)             │
│  ├─ HTTP/s checks every 30s                               │
│  ├─ TCP port checks                                       │
│  ├─ API endpoint health checks                            │
│  ├─ SSL certificate expiry (30d warning)                  │
│  └─ Status page: uptime.wheeler.ai                        │
│                                                           │
│  Layer 4: LOG AGGREGATION (Docker json-file + rotation)   │
│  ├─ 10MB per file, max 3 files per container              │
│  ├─ DO NOT use Loki/ELK (avoid overhead)                  │
│  └─ Use docker logs + grep for debugging                  │
└──────────────────────────────────────────────────────────┘
```

---

## BACKUP STRATEGY

```
Schedule:               Daily at 03:00 UTC
Retention:              7 days on-server, 30 days off-site
Databases backed up:    prediction_radar, ravynai, healthchecks, superset, frgops, frgcrm, chatwoot, langfuse, plausible
Method:                 pg_dump custom format + WAL archiving
Volume backups:         Docker named volumes → tarball → off-site

Backup flow:
  Hetzner pg_dump → /opt/backups/databases/
  Hetzner volumes → /opt/backups/volumes/
  → rsync to local archive server
  → rotate: keep 7 daily, 4 weekly, 3 monthly
```

---

## SECURITY ZONES

```
Zone 0: PUBLIC (Internet → Cloudflare → Traefik)
  - Only 80/443 exposed
  - Cloudflare WAF + DDoS
  - Rate limiting at Traefik
  - CrowdSec bouncer on Traefik

Zone 1: SEMI-PUBLIC (Traefik-routed apps)
  - App-level auth required
  - IP whitelist for admin endpoints

Zone 2: TAILSCALE-ONLY (Admin dashboards, DB access)
  - UFW: only Tailscale interface (tailscale0)
  - Netdata, Portainer, Prometheus, direct DB access
  - SSH key-only, no password

Zone 3: INTERNAL (Docker internal networks)
  - No host port binding
  - Container-to-container only
  - DB, Redis, message queues, workers
```

---

## SCALING STRATEGY

```
Current (Phase 2):     Two-server with service isolation
Phase 3 (3-6 months):  Add Hetzner CX32 worker node for trading/agents
Phase 4 (6-12 months): Docker Swarm across 2-3 Hetzner nodes
Phase 5 (12+ months):  Kubernetes (k3s) on Hetzner cloud, Hostinger stays edge

Vertical scaling (now):
  - CPU shares via Docker --cpus limits
  - Memory limits on all containers
  - Swap disabled (OOM killer better than swap thrash)

Horizontal scaling (future):
  - Replica services behind Traefik load balancer
  - Read replicas for Postgres
  - Redis Sentinel for HA
```
