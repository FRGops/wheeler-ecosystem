# Wheeler Enterprise — System Architecture

**Version:** 1.0.0 | **Last Updated:** 2026-05-23 | **Owner:** SRE Team
**Classification:** Internal — Infrastructure

---

## 1. Physical Topology

### 1.1 Server Inventory

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         WHEELER ENTERPRISE PHYSICAL TOPOLOGY                │
│                                                                            │
│   ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐   │
│   │     EDGE          │   │     AIOPS         │   │     COREDB        │   │
│   │  Hostinger VPS    │   │  Hetzner CPX51    │   │  Hetzner CX32     │   │
│   │                   │   │                   │   │                   │   │
│   │  Public IP:       │   │  Public IP:       │   │  Public IP:       │   │
│   │  187.77.148.88    │   │  5.78.140.118     │   │  5.78.210.123     │   │
│   │                   │   │                   │   │                   │   │
│   │  Tailscale:        │   │  Tailscale:        │   │  Tailscale:        │   │
│   │  100.98.163.17     │   │  100.121.230.28   │   │  (provisioning)   │   │
│   │                   │   │                   │   │                   │   │
│   │  CPU: 4-8 vCPU    │   │  CPU: 16 vCPU     │   │  CPU: 8 vCPU      │   │
│   │  RAM: 8-16 GB     │   │  RAM: 32 GB       │   │  RAM: 16 GB       │   │
│   │  Disk: 100GB NVMe │   │  Disk: 360GB NVMe │   │  Disk: 160GB NVMe │   │
│   │  Net:  1 Gbps     │   │  Net:  1 Gbps     │   │  Net:  1 Gbps     │   │
│   │                   │   │                   │   │                   │   │
│   │  Role:             │   │  Role:             │   │  Role:             │   │
│   │  Public Edge /     │   │  Primary AIOps     │   │  Database /        │   │
│   │  Reverse Proxy     │   │  Orchestrator      │   │  Storage Server    │   │
│   └───────┬───────────┘   └───────┬───────────┘   └───────┬───────────┘   │
│           │                       │                       │               │
│           └───────────────────────┼───────────────────────┘               │
│                                   │                                       │
│                    ┌──────────────┴──────────────┐                         │
│                    │    TAILSCALE MESH (WireGuard) │                        │
│                    │       100.64.0.0/10          │                        │
│                    │   Encrypted, mTLS, zero-trust │                       │
│                    └─────────────────────────────┘                         │
└────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Server Specifications

**EDGE (Hostinger VPS — 187.77.148.88)**
- **OS:** Ubuntu 24.04 LTS
- **Role:** Public-facing reverse proxy, lightweight frontend apps, static site hosting
- **Public Access:** Ports 80, 443 (Traefik)
- **Admin Access:** SSH via Tailscale only (port 22 filtered to 100.64.0.0/10)
- **Key Services:** Traefik (public edge), FRGops/FRGCRM, Chatwoot, n8n, Docuseal, LiteLLM Proxy, MinIO Light, Webhook Receiver
- **Data Layer:** Local PostgreSQL (FRGops only), Local Redis (FRGops cache)

**AIOPS (Hetzner CPX51 — 5.78.140.118)**
- **OS:** Ubuntu 24.04 LTS
- **Role:** All heavy compute, AI services, analytics, monitoring, orchestration
- **Public Access:** Ports 80, 443 (Traefik internal router)
- **Admin Access:** SSH via Tailscale only
- **Key Services:** Prediction Radar (full stack), RavynAI (full stack), Superset, ClickHouse, AI Agent Runtimes, Trading Workers, Realtime Feed Handlers, NATS/RabbitMQ, Prometheus, Grafana, Loki, Alertmanager, Netdata, Uptime Kuma, Portainer, Dockge
- **Data Layer:** Primary PostgreSQL, Primary Redis
- **Docker:** 22 containers, overlay2 storage driver

**COREDB (Hetzner CX32 — 5.78.210.123)**
- **OS:** Ubuntu 24.04 LTS
- **Role:** Dedicated database, vector store, object storage, backup target
- **Public Access:** NONE (zero public ports exposed)
- **Admin Access:** SSH via Tailscale only
- **Key Services:** PostgreSQL (isolated DB), Redis (isolated cache), ClickHouse Native, MinIO (S3-compatible), Qdrant (vector DB), Backup storage
- **UFW:** Most restrictive policy — only Tailscale subnet and specific AIOPS ports

---

## 2. Logical Architecture

### 2.1 Service Dependency Graph

```
                          INTERNET
                             |
                       Cloudflare DNS/WAF
                             |
                    ┌────────┴────────┐
                    │   EDGE SERVER    │
                    │  187.77.148.88   │
                    │                  │
                    │  Traefik (Edge)  │
                    │  :80   :443      │
                    └───┬─────────┬────┘
                        │         │
           Local Apps   │         │  Proxied to AIOPS via Tailscale
           ┌────────────┘         └────────────┐
           │                                   │
    ┌──────┴──────┐              ┌─────────────┴─────────────┐
    │  FRGops     │              │      AIOPS SERVER          │
    │  Chatwoot   │              │     5.78.140.118          │
    │  n8n        │              │                            │
    │  Docuseal   │              │  Traefik (Internal)        │
    │  LiteLLM    │              │  :80  :443                 │
    │  MinIO      │              │                            │
    │  Webhook    │              │  ┌──────────────────────┐  │
    └──────┬──────┘              │  │  Prediction Radar     │  │
           │                     │  │  ├ API (8000)         │  │
    ┌──────┴──────┐              │  │  ├ Web (8098)         │  │
    │  Local PG   │              │  │  ├ Worker             │  │
    │  Local Redis│              │  │  ├ Scheduler          │  │
    └─────────────┘              │  │  ├ DB (5433)          │  │
                                 │  │  └ Redis              │  │
                                 │  └──────────────────────┘  │
                                 │                            │
                                 │  ┌──────────────────────┐  │
                                 │  │  RavynAI             │  │
                                 │  │  ├ API (8007)         │  │
                                 │  │  ├ Worker             │  │
                                 │  │  └ DB (5434)          │  │
                                 │  └──────────────────────┘  │
                                 │                            │
                                 │  ┌──────────────────────┐  │
                                 │  │  AI Agents            │  │
                                 │  │  ├ Agent Runtimes     │  │
                                 │  │  ├ Trading Workers    │  │
                                 │  │  ├ Feed Handlers      │  │
                                 │  │  └ Browser Auto       │  │
                                 │  └──────────────────────┘  │
                                 │                            │
                                 │  ┌──────────────────────┐  │
                                 │  │  Analytics            │  │
                                 │  │  ├ Superset (8088)    │  │
                                 │  │  └ ClickHouse (8123)  │  │
                                 │  └──────────────────────┘  │
                                 │                            │
                                 │  ┌──────────────────────┐  │
                                 │  │  Monitoring           │  │
                                 │  │  ├ Prometheus (9090)  │  │
                                 │  │  ├ Grafana (3002)     │  │
                                 │  │  ├ Loki (3100)        │  │
                                 │  │  ├ Alertmanager (9093)│  │
                                 │  │  ├ Netdata (19999)    │  │
                                 │  │  └ Uptime Kuma (3001) │  │
                                 │  └──────────────────────┘  │
                                 │                            │
                                 │  ┌──────────────────────┐  │
                                 │  │  AIOps PostgreSQL     │  │
                                 │  │  (5432)              │  │
                                 │  └──────────┬───────────┘  │
                                 │             │              │
                                 │  ┌──────────┴───────────┐  │
                                 │  │  AIOps Redis (6379)  │  │
                                 │  └──────────────────────┘  │
                                 └─────────────┬──────────────┘
                                               │ Tailscale
                                    ┌──────────┴──────────┐
                                    │    COREDB SERVER     │
                                    │    5.78.210.123      │
                                    │                      │
                                    │  PostgreSQL  (5432)  │
                                    │  Redis       (6379)  │
                                    │  ClickHouse  (9000)  │
                                    │  MinIO       (9000)  │
                                    │  Qdrant      (6333)  │
                                    │  Backup Storage      │
                                    └──────────────────────┘
```

### 2.2 PM2 Process Topology

Seven Node.js applications managed by PM2 on AIOPS:

```
PM2 Process Tree (AIOPS)
=========================
  pm2-logrotate              # Log rotation daemon
  frgcrm-agent-svc           # FRG CRM Agent Service
  frgcrm-api                 # FRG CRM REST API
  frgcrm-mirror-test         # FRG CRM Mirror Test
  insforge-agent-svc         # InsForge Agent Service
  surplusai-scraper-agent-svc # SurplusAI Scraper Agent
  voice-agent-svc            # Voice AI Agent Service
```

### 2.3 Docker Compose Service Grouping

```
Service Groups (Docker Compose Stacks):
───────────────────────────────────────
  traefik-public/       # Traefik router + dashboard
  prediction-radar/     # Prediction Radar (API + Web + Worker + Scheduler + DB + Redis)
  ravynai/              # RavynAI (API + Worker + DB)
  analytics/            # Superset + ClickHouse
  monitoring/           # Prometheus + Grafana + Loki + Alertmanager + Uptime Kuma + Netdata
  automation/           # ChangeDetection + Browser Automation
  osint/                # Spiderfoot
  trading/              # Trading Engine Workers + Feed Handlers
  messaging/            # NATS / RabbitMQ
  ai-agents/            # AI Agent Runtimes
  data/                 # PostgreSQL + Redis (AIOps)
  management/           # Portainer + Dockge
```

---

## 3. Network Design

### 3.1 Tailscale Mesh Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   TAILSCALE MESH TOPOLOGY                        │
│                                                                  │
│   EDGE (100.98.163.17)                                             │
│     │                                                            │
│     ├──── WireGuard Tunnel ──── AIOPS (100.121.230.28)          │
│     │                                                            │
│     └──── WireGuard Tunnel ──── COREDB (provisioning)           │
│                                                                  │
│   All inter-server traffic encrypted with WireGuard + mTLS       │
│   Coordination server: Tailscale SaaS (no self-hosted DERP)      │
│   MagicDNS enabled: <hostname>.tailnet-name.ts.net               │
│   Subnet routing: none (all hosts directly in mesh)              │
│   ACLs: Tag-based access control enforced at Tailscale level     │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 UFW Firewall Policies

**EDGE Server (Hostinger) — Public-Facing Reverse Proxy**

```
Direction  Action  From              To        Port    Protocol  Purpose
─────────  ──────  ────────────────  ────────  ──────  ────────  ─────────
INCOMING   DENY    0.0.0.0/0         any       all     all       Default deny
OUTGOING   ALLOW   any               0.0.0.0/0  all     all       Default allow
INCOMING   ALLOW   100.64.0.0/10     any       22      tcp       SSH (Tailscale)
INCOMING   ALLOW   0.0.0.0/0         any       80      tcp       HTTP (public)
INCOMING   ALLOW   0.0.0.0/0         any       443     tcp       HTTPS (public)
INCOMING   ALLOW   100.64.0.0/10     any       all     all       Tailscale mesh
INCOMING   LIMIT   0.0.0.0/0         any       22      tcp       SSH rate-limit
```

**AIOPS Server (Hetzner CPX51) — AI & API Orchestrator**

```
Direction  Action  From              To        Port    Protocol  Purpose
─────────  ──────  ────────────────  ────────  ──────  ────────  ─────────
INCOMING   DENY    0.0.0.0/0         any       all     all       Default deny
OUTGOING   ALLOW   any               0.0.0.0/0  all     all       Default allow
INCOMING   ALLOW   100.64.0.0/10     any       22      tcp       SSH (Tailscale)
INCOMING   ALLOW   0.0.0.0/0         any       80      tcp       HTTP (public)
INCOMING   ALLOW   0.0.0.0/0         any       443     tcp       HTTPS (public)
INCOMING   ALLOW   100.64.0.0/10     any       3000    tcp       API port
INCOMING   ALLOW   100.64.0.0/10     any       3001    tcp       WebSocket
INCOMING   ALLOW   100.64.0.0/10     any       9090    tcp       Prometheus
INCOMING   ALLOW   100.64.0.0/10     any       4000    tcp       LiteLLM
INCOMING   ALLOW   100.64.0.0/10     any       19999   tcp       Netdata
INCOMING   ALLOW   100.64.0.0/10     any       all     all       Tailscale mesh
INCOMING   ALLOW   172.16.0.0/12     any       all     all       Docker networks
INCOMING   ALLOW   10.0.0.0/8        any       all     all       Docker networks
```

**COREDB Server (Hetzner CX32) — Database Server (MOST RESTRICTIVE)**

```
Direction  Action  From              To        Port    Protocol  Purpose
─────────  ──────  ────────────────  ────────  ──────  ────────  ─────────
INCOMING   DENY    0.0.0.0/0         any       all     all       Default deny
OUTGOING   DENY    0.0.0.0/0         any       all     all       Default deny
OUTGOING   ALLOW   any               0.0.0.0/0  53      udp       DNS
OUTGOING   ALLOW   any               0.0.0.0/0  123     udp       NTP
OUTGOING   ALLOW   any               0.0.0.0/0  80      tcp       HTTP updates
OUTGOING   ALLOW   any               0.0.0.0/0  443     tcp       HTTPS updates
INCOMING   ALLOW   100.64.0.0/10     any       22      tcp       SSH (Tailscale)
INCOMING   ALLOW   100.64.0.0/10     any       5432    tcp       PostgreSQL
INCOMING   ALLOW   100.64.0.0/10     any       6379    tcp       Redis
INCOMING   ALLOW   100.64.0.0/10     any       9000    tcp       MinIO/ClickHouse
INCOMING   ALLOW   100.64.0.0/10     any       9001    tcp       MinIO Console
INCOMING   ALLOW   100.64.0.0/10     any       6333    tcp       Qdrant Vector
INCOMING   ALLOW   100.64.0.0/10     any       9100    tcp       Node Exporter
INCOMING   ALLOW   100.64.0.0/10     any       9187    tcp       PG Exporter
INCOMING   ALLOW   100.64.0.0/10     any       9121    tcp       Redis Exporter
INCOMING   ALLOW   100.64.0.0/10     any       all     all       Tailscale mesh
```

### 3.3 Docker Network Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     DOCKER NETWORK TOPOLOGY                           │
│                                                                      │
│  EDGE Server (187.77.148.88)                                        │
│  ┌───────────────────────┐                                           │
│  │ traefik-public         │  172.20.0.0/24                          │
│  │ ├ Traefik Edge Router  │                                          │
│  │ └ All public-facing    │                                          │
│  │   services connected    │                                          │
│  └───────────────────────┘                                           │
│  ┌───────────────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ frgops    172.30.x    │  │ ai-proxy     │  │ automation       │  │
│  │ ├ FRGops/FRGCRM       │  │ 172.31.x     │  │ 172.32.x         │  │
│  │ ├ Chatwoot            │  │ ├ LiteLLM    │  │ ├ n8n            │  │
│  │ └ Docuseal            │  │ └ ...        │  │ └ ...            │  │
│  └───────────────────────┘  └──────────────┘  └──────────────────┘  │
│                                                                      │
│  AIOPS Server (5.78.140.118)                                        │
│  ┌───────────────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ traefik-public         │  │ prediction-   │  │ analytics        │  │
│  │ 172.20.0.0/24         │  │ radar         │  │ 172.22.0.0/24    │  │
│  │ ├ Traefik Internal     │  │ 172.21.0.0/24 │  │ ├ Superset       │  │
│  └───────────────────────┘  │ ├ API         │  │ └ ClickHouse     │  │
│                              │ ├ Web         │  └──────────────────┘  │
│  ┌──────────────┐  ┌───────┐│ ├ Worker      │                        │
│  │ ravynai      │  │ ai-   ││ ├ Scheduler   │  ┌──────────────────┐  │
│  │ 172.25.0.0/24│  │ agents││ ├ DB          │  │ trading           │  │
│  │ ├ API        │  │ 172.24││ └ Redis       │  │ 172.26.0.0/24    │  │
│  │ ├ Worker     │  │ .0/24 │└──────────────┘  │ ├ Workers         │  │
│  │ └ DB         │  │       │                   │ └ Feed Handlers   │  │
│  └──────────────┘  └───────┘                   └──────────────────┘  │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │
│  │ messaging    │  │ automation   │  │ data          │               │
│  │ 172.27.0.0/24│  │ 172.28.0.0/24│  │ 172.29.0.0/24 │               │
│  │ ├ NATS       │  │ ├ ChangeDet  │  │ ├ Postgres    │               │
│  │ └ RabbitMQ   │  │ └ BrowserAuto│  │ └ Redis       │               │
│  └──────────────┘  └──────────────┘  └──────────────┘               │
│                                                                      │
│  ┌───────────────────────┐  ┌───────────────────────┐               │
│  │ monitoring             │  │ management             │               │
│  │ 172.35.0.0/24         │  │ 172.36.0.0/24         │               │
│  │ ├ Prometheus          │  │ ├ Portainer            │               │
│  │ ├ Grafana             │  │ └ Dockge               │               │
│  │ ├ Loki                │  └───────────────────────┘               │
│  │ ├ Alertmanager        │                                           │
│  │ ├ Uptime Kuma         │                                           │
│  │ └ Netdata             │                                           │
│  └───────────────────────┘                                           │
│                                                                      │
│  Docker bridge bip: 172.26.0.1/16 (avoids Tailscale 100.64.0.0/10)  │
│  Default address pools: 172.27.0.0/16, 172.28.0.0/16 (size /24)    │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.4 Port Assignment Master Table

```
Port   Protocol  Server(s)        Service                  Public?  Notes
────   ────────  ───────────────  ───────────────────────  ───────  ──────
22     tcp       ALL              SSH                      No       Tailscale only
53     udp       AIOPS,COREDB     DNS (outbound)           N/A      Outbound only
80     tcp       EDGE,AIOPS       HTTP → HTTPS redirect    Yes      Traefik
123    udp       AIOPS,COREDB     NTP (outbound)           N/A      Outbound only
443    tcp       EDGE,AIOPS       HTTPS (TLS termination)  Yes      Traefik
3000   tcp       EDGE             FRGops/FRGCRM/Chatwoot   Yes      Via Traefik
3000   tcp       AIOPS            API port (internal)      No       Tailscale only
3001   tcp       AIOPS            Uptime Kuma              Yes      Via Traefik
3001   tcp       AIOPS            WebSocket port           No       Tailscale only
3002   tcp       AIOPS            Grafana                  Yes      Via Traefik
3100   tcp       AIOPS            Loki                     No       Internal
3130   tcp       AIOPS            Healthchecks             Yes      Via Traefik
4000   tcp       EDGE             LiteLLM Proxy            Yes      Via Traefik
4000   tcp       AIOPS            LiteLLM (internal)       No       Tailscale only
4222   tcp       AIOPS            NATS                     No       Internal
5000   tcp       AIOPS            ChangeDetection          Yes      Via Traefik
5001   tcp       AIOPS            Dockge                   No       Tailscale only
5432   tcp       AIOPS,COREDB     PostgreSQL               No       Internal/Tailscale
5433   tcp       AIOPS            Prediction Radar DB      No       Internal
5434   tcp       AIOPS            RavynAI DB               No       Internal
5672   tcp       AIOPS            RabbitMQ                 No       Internal
5678   tcp       EDGE             n8n (light)              Yes      Via Traefik
6333   tcp       COREDB           Qdrant Vector DB         No       Tailscale only
6379   tcp       ALL              Redis                    No       Internal/Tailscale
8000   tcp       AIOPS            Prediction Radar API     No       Tailscale
8007   tcp       AIOPS            RavynAI API              Yes      Via Traefik
8080   tcp       AIOPS            Spiderfoot               No       Tailscale only
8080   tcp       AIOPS            Traefik Dashboard        No       Tailscale only
8082   tcp       AIOPS            cAdvisor                 No       Internal
8088   tcp       AIOPS            Superset                 Yes      Via Traefik
8098   tcp       AIOPS            Prediction Radar Web     Yes      Via Traefik
8123   tcp       AIOPS            ClickHouse HTTP          No       Tailscale only
9000   tcp       COREDB           ClickHouse Native        No       Tailscale only
9000   tcp       COREDB           MinIO S3 API             No       Tailscale only
9001   tcp       COREDB           MinIO Console            No       Tailscale only
9090   tcp       AIOPS            Prometheus               No       Tailscale only
9093   tcp       AIOPS            Alertmanager             No       Internal
9100   tcp       ALL              Node Exporter            No       Tailscale only
9121   tcp       ALL              Redis Exporter           No       Tailscale only
9187   tcp       ALL              PostgreSQL Exporter      No       Tailscale only
9323   tcp       ALL              Docker Metrics           No       localhost only
9443   tcp       AIOPS            Portainer                No       Tailscale only
19999  tcp       AIOPS            Netdata                  No       Tailscale only
```

---

## 4. Data Flow Diagrams

### 4.1 User Request Flow

```
User Browser (Internet)
       │
       ▼
  Cloudflare (DNS resolution + DDoS protection + WAF)
       │
       ▼
  EDGE Traefik :443 (TLS termination, Let's Encrypt)
       │
       ├─── Local services (FRGops, Chatwoot, n8n, Docuseal)
       │    │
       │    └─── EDGE PostgreSQL ─── Response
       │
       └─── Proxied to AIOPS via Tailscale
            │
            ▼
       AIOPS Traefik :443 (internal routing)
            │
            ├─── Prediction Radar API (8000)
            │    ├── Prediction Radar Worker (background compute)
            │    ├── Prediction Radar Redis (cache)
            │    └── Prediction Radar DB (5433) ─── Response
            │
            ├─── RavynAI API (8007)
            │    ├── LiteLLM Proxy (4000) → Model Providers
            │    ├── RavynAI Worker (async processing)
            │    └── RavynAI DB (5434) ─── Response
            │
            ├─── Superset (8088)
            │    └── ClickHouse (8123) ─── Response
            │
            ├─── AI Agent Runtime (8001+)
            │    ├── Agent Worker (compute)
            │    ├── NATS/RabbitMQ (message queue)
            │    └── AIOPS PostgreSQL (5432) ─── Response
            │
            └─── COREDB (via Tailscale)
                 ├── PostgreSQL (5432)
                 ├── Redis (6379)
                 ├── Qdrant Vector (6333)
                 └── MinIO (9000)
```

### 4.2 Monitoring Data Flow

```
  ┌──────────┐   ┌──────────┐   ┌──────────┐
  │  EDGE    │   │  AIOPS   │   │  COREDB  │
  │          │   │          │   │          │
  │ NodeExp  │   │ NodeExp  │   │ NodeExp  │
  │ cAdvisor │   │ cAdvisor │   │ PG Exp   │
  │ Docker   │   │ Docker   │   │ RedisExp │
  │ Metrics  │   │ Metrics  │   │ Docker   │
  └────┬─────┘   └────┬─────┘   └────┬─────┘
       │              │              │
       │    Tailscale │ Mesh         │
       └──────────────┼──────────────┘
                      │
                      ▼
              Prometheus (AIOPS:9090)
              │
              ├─── Metrics evaluation ─── Alertmanager (9093)
              │                              │
              │                    ┌─────────┼─────────┐
              │                    │         │         │
              │                 Slack    Email     PagerDuty
              │
              ├─── Grafana (3002) ─── Dashboards + Panels
              │
              └─── Loki (3100) ◄── Promtail (all servers)
                   │                    │
                   │        ┌──────────┴──────────┐
                   │        │   Log Sources        │
                   │        │   ├ Docker logs      │
                   │        │   ├ PM2 logs         │
                   │        │   ├ /var/log/wheeler/│
                   │        │   ├ Nginx logs       │
                   │        │   └ System logs      │
                   └────────┼──────────────────────
                            │
                   Uptime Kuma (3001)
                   ├ HTTP checks every 30s
                   ├ TCP port checks
                   └ SSL expiry checks (30d warning)

  Netdata (19999) → Real-time per-second metrics → netdata.wheeler.ai
```

### 4.3 Backup Data Flow

```
  Daily 03:00 UTC
  ───────────────────────────────────────────────────

  AIOPS:
    pg_dump custom format → /opt/backups/databases/
      ├ prediction_radar.dump
      ├ ravynai.dump
      ├ healthchecks.dump
      ├ superset.dump
      ├ langfuse.dump
      └ plausible.dump

    Docker volumes tarball → /opt/backups/volumes/
      ├ prediction-radar_data.tar.gz
      ├ ravynai_data.tar.gz
      ├ grafana_data.tar.gz
      ├ prometheus_data.tar.gz
      └ loki_data.tar.gz

  COREDB:
    pg_dump → /opt/backups/databases/
      ├ frgops.dump
      ├ frgcrm.dump
      └ chatwoot.dump

  Post-backup:
    ├ GPG encrypt all with public key
    ├ rsync to archive server (off-site)
    └ Rotation:
        ├ Keep 7 daily
        ├ Keep 4 weekly
        └ Keep 3 monthly
```

---

## 5. Storage Architecture

### 5.1 Volume Inventory

```
Volume Name                  Server   Purpose                Size Est.  Backup?
───────────────────────────  ───────  ─────────────────────  ─────────  ──────
prediction-radar_postgres    AIOPS    Prediction Radar DB     ~20GB      Daily
prediction-radar_redis       AIOPS    Prediction Radar Cache  ~2GB       Weekly
ravynai_postgres             AIOPS    RavynAI DB              ~15GB      Daily
ravynai_redis                AIOPS    RavynAI Cache           ~1GB       Weekly
superset_data                AIOPS    Superset metadata       ~5GB       Daily
clickhouse_data              AIOPS    ClickHouse analytics    ~30GB      Weekly
grafana_data                 AIOPS    Grafana dashboards      ~2GB       Daily
prometheus_data              AIOPS    Prometheus TSDB         ~40GB      Weekly
loki_data                    AIOPS    Loki log storage        ~50GB      Weekly
uptime_kuma_data             AIOPS    Uptime Kuma state       ~500MB     Daily
portainer_data               AIOPS    Portainer config        ~200MB     Weekly
change_detection_data        AIOPS    ChangeDetection state   ~2GB       Weekly
healthchecks_data            AIOPS    Healthchecks state      ~500MB     Daily
traefik_certs                EDGE     Traefik ACME certs      ~50MB      Daily
traefik_certs                AIOPS    Traefik ACME certs      ~50MB      Daily
frgops_postgres              EDGE     FRGops/Local DB         ~10GB      Daily
frgops_redis                 EDGE     FRGops Cache            ~1GB       Weekly
minio_data                   COREDB   Object storage          ~50GB      Daily
qdrant_data                  COREDB   Vector embeddings       ~10GB      Daily
```

### 5.2 Storage Usage (Current)

```
AIOPS (360 GB NVMe):
  ├ /                     (root)      ~120 GB used
  ├ /var/lib/docker       (overlay2)  ~80 GB used
  ├ /opt/backups          (backups)    ~40 GB used
  └ Available:                        ~120 GB free (33%)

COREDB (160 GB NVMe):
  ├ /                     (root)      ~30 GB used
  ├ Database storage:                 ~50 GB allocated
  └ Available:                        ~80 GB free (50%)

EDGE (100 GB NVMe):
  ├ /                     (root)      ~40 GB used
  └ Available:                        ~60 GB free (60%)
```

### 5.3 Database Architecture

```
PostgreSQL Instances:
┌──────────────────────────────────────────────────────────────────┐
│ Instance              Server   Port   Purpose                     │
│ ───────────────────── ───────  ────   ────────────────────────    │
│ postgres-aio-main     AIOPS    5432   Primary AI + API database   │
│ postgres-prediction   AIOPS    5433   Prediction Radar (isolated) │
│ postgres-ravynai      AIOPS    5434   RavynAI (isolated)          │
│ postgres-frgops       EDGE     5432   FRGops/Frontend             │
│ postgres-coredb-main  COREDB   5432   Core business data          │
└──────────────────────────────────────────────────────────────────┘

Redis Instances:
┌──────────────────────────────────────────────────────────────────┐
│ Instance              Server   Port   Purpose                     │
│ ───────────────────── ───────  ────   ────────────────────────    │
│ redis-aio-main        AIOPS    6379   Primary cache + pub/sub     │
│ redis-prediction      AIOPS    6379   Prediction Radar cache      │
│ redis-ravynai         AIOPS    6379   RavynAI session cache       │
│ redis-frgops          EDGE     6379   FRGops cache                │
│ redis-coredb-main     COREDB   6379   Shared cache                │
└──────────────────────────────────────────────────────────────────┘

Backup Strategy:
  Method:        pg_dump custom format + WAL archiving
  Schedule:      Daily at 03:00 UTC
  Encryption:    GPG (public key encryption)
  Retention:     7 daily, 4 weekly, 3 monthly on-server
                 30 days off-site via rsync
  Verification:  Monthly restore to temp location and integrity check
```

---

## 6. Security Architecture

### 6.1 Defense-in-Depth Model

```
┌─────────────────────────────────────────────────────────────────────┐
│                     SECURITY DEFENSE-IN-DEPTH                        │
│                                                                      │
│  Layer 0: Cloudflare                                                 │
│    ├ DDoS protection (HTTP flood, SYN flood)                        │
│    ├ Web Application Firewall (WAF) with OWASP rules                │
│    ├ Bot management                                                  │
│    └ SSL/TLS termination (optional, we terminate at Traefik)        │
│                                                                      │
│  Layer 1: UFW (Host Firewall)                                       │
│    ├ Per-role firewall policies (EDGE/AIOPS/COREDB)                │
│    ├ Default deny inbound on all servers                            │
│    ├ Default deny outbound on COREDB (egress filtering)             │
│    ├ Rate limiting on SSH                                            │
│    ├ Tailscale subnet (100.64.0.0/10) as trusted zone              │
│    └ High logging for denied connections                            │
│                                                                      │
│  Layer 2: fail2ban (Intrusion Prevention)                           │
│    ├ 12 active jails                                                 │
│    ├ Escalating ban times (10min → 1hr → 24hr)                    │
│    ├ SSH: 3 failures / 5min → 1hr ban                             │
│    ├ SSH recidive: 5 failures / 24hr → 7 day ban                   │
│    ├ Traefik-auth: 10 failures / 5min → 1hr ban                   │
│    ├ Nginx-botsearch, noscript, bad-request jails                   │
│    ├ PostgreSQL and Redis auth failure jails                        │
│    ├ Port scanning detection (1 hit / 5min → 24hr ban)             │
│    └ Docker attack detection                                         │
│                                                                      │
│  Layer 3: Tailscale ACLs (Zero-Trust Network)                       │
│    ├ Tag-based access control                                        │
│    ├ Service-level rules (e.g., COREDB:5432 only from AIOPS tag)   │
│    ├ MagicDNS for internal name resolution                          │
│    └ All traffic encrypted with WireGuard + mTLS                   │
│                                                                      │
│  Layer 4: Docker Network Isolation                                  │
│    ├ Each service group on dedicated overlay network                │
│    ├ No host port binding for internal services                    │
│    ├ Container-to-container only for DB/Redis/queues               │
│    ├ AppArmor profiles on all containers                            │
│    ├ Read-only rootfs where possible                                │
│    └ No privileged containers (except Traefik for port 80/443)      │
│                                                                      │
│  Layer 5: Application Security                                      │
│    ├ Traefik rate limiting (per-route, per-IP)                     │
│    ├ CORS policies locked to wheeler.ai domains                    │
│    ├ API key authentication for all AI endpoints                    │
│    ├ JWT + OAuth2 for user-facing services                          │
│    ├ Environment variable secrets (never in code)                   │
│    └ Input validation at API gateway                                │
│                                                                      │
│  Layer 6: Data Security                                             │
│    ├ All backups GPG-encrypted before off-site transfer            │
│    ├ Database connections forced TLS (sslmode=require)              │
│    ├ Sensitive columns encrypted at rest (pgcrypto)                │
│    ├ Redis AUTH required on all instances                           │
│    ├ Log redaction: API keys, tokens → [REDACTED]                  │
│    └ Data retention policies enforced via TTL and cron             │
│                                                                      │
│  Layer 7: Kernel Hardening (sysctl)                                 │
│    ├ Source route filtering disabled                                │
│    ├ ICMP redirects ignored                                          │
│    ├ Reverse path filtering enabled                                  │
│    ├ SYN cookie protection enabled                                   │
│    ├ IP forwarding disabled (EDGE excluded)                          │
│    ├ Martian packet logging enabled                                  │
│    └ OOM killer priority: sshd(-900), postgres(-800), redis(-700)   │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.2 SSH Hardening

- SSH key-only authentication (password auth disabled)
- No root login (PermitRootLogin no)
- Only 3 SSH users: deployer, admin, monitoring
- SSH port 22 filtered to Tailscale subnet (100.64.0.0/10) via UFW
- ClientAliveInterval 300, ClientAliveCountMax 2 (10 min timeout)
- MaxAuthTries 3, MaxSessions 5
- fail2ban SSH jail: 3 failures in 5 min = 1 hour ban

### 6.3 System Hardening

- Unattended security upgrades enabled (check every 6 hours)
- Linux kernel, docker, postgres, redis blacklisted from auto-upgrade
- Automatic reboot DISABLED (controlled by SRE team during windows)
- sysctl hardening via /etc/sysctl.d/99-wheeler-enterprise.conf
- No swap currently (8GB planned, swappiness=10)
- journald: 500MB max, persistent storage, compress=yes
- Core dumps: /var/crash/core.%e.%p.%t (for debugging)
- ASLR: full randomization (kernel.randomize_va_space=2)

---

## 7. Monitoring Architecture

### 7.1 Prometheus Scrape Topology

```
Prometheus Server (AIOPS:9090)
│
├─── Scrape every 15s:
│    ├ localhost:9090     (Prometheus self)
│    ├ localhost:9093     (Alertmanager)
│    ├ localhost:3100     (Loki metrics)
│    ├ localhost:8082     (cAdvisor - container metrics)
│    ├ localhost:9100     (Node Exporter - system metrics)
│    ├ localhost:9187     (PostgreSQL Exporter)
│    ├ localhost:9121     (Redis Exporter)
│    ├ localhost:9323     (Docker Engine metrics)
│    └ localhost:19999    (Netdata bridge metrics)
│
├─── Scrape every 15s (via Tailscale):
│    ├ 100.98.163.17:9100  (EDGE Node Exporter)
│    ├ 100.98.163.17:9323  (EDGE Docker metrics)
│    ├ 100.98.163.17:8082  (EDGE cAdvisor)
│    ├ <coredb-ip>:9100   (COREDB Node Exporter)
│    ├ <coredb-ip>:9187   (COREDB PostgreSQL Exporter)
│    └ <coredb-ip>:9121   (COREDB Redis Exporter)
│
└─── Custom app metrics (scrape every 30s):
     ├ prediction-radar:8000/metrics
     ├ ravynai:8007/metrics
     ├ litellm:4000/metrics
     └ pm2-exporter (PM2 metrics bridge)
```

### 7.2 Alert Routing

```
Prometheus Alert Rules
       │
       ▼
Alertmanager (9093)
       │
       ├─── CRITICAL (match: severity=critical)
       │    ├ PagerDuty (24/7 on-call)
       │    └ Slack #alerts-critical
       │    ├ Group wait: 10s
       │    └ Repeat: every 10min
       │
       ├─── WARNING (match: severity=warning)
       │    ├ Slack #alerts-warning (business hours)
       │    └ Email (24/7)
       │    └ Repeat: every 4hr
       │
       ├─── DATABASE (match: group=database)
       │    ├ Slack #alerts-database
       │    └ Repeat: every 2hr
       │
       ├─── AVAILABILITY (match: group=availability)
       │    ├ PagerDuty + Slack
       │    └ Group wait: 10s (immediate)
       │
       └─── INFO (default)
            └ Slack #alerts-info (no notification, log only)
```

### 7.3 Alert Inhibition Rules

- If HostUnreachable fires, suppress all per-service alerts on that host
- If PostgresDown fires, suppress PostgresHighConnections
- If RedisDown fires, suppress RedisHighMemory and RedisCacheHitRateLow

### 7.4 Critical Alert Thresholds

```
Alert Name                  Condition                           Severity
──────────────────────────  ─────────────────────────────────  ──────────
HostUnreachable             up == 0 for 2m                     CRITICAL
ContainerDown               container absent for 1m            CRITICAL
HighCPUUsage                cpu > 90% for 5m                   WARNING
HighMemoryUsage             mem > 95% for 5m                   CRITICAL
HighMemoryUsage             mem > 85% for 10m                  WARNING
DiskSpaceLow                disk > 90% used                    CRITICAL
DiskSpaceLow                disk > 80% used                    WARNING
PostgresDown                pg_up == 0 for 1m                  CRITICAL
RedisDown                   redis_up == 0 for 1m               CRITICAL
HighAPILatency              p95 latency > 2s for 5m            WARNING
HighAPIErrorRate            error rate > 5% for 5m             CRITICAL
SSLCertExpiring             expires < 7 days                   CRITICAL
SSLCertExpiring             expires < 30 days                  WARNING
TailscaleDisconnected       tailscale status != connected      CRITICAL
BackupFailed                last_success > 25hr                CRITICAL
OOMKillerActive             oom_kill_total increase            WARNING
DockerDaemonUnhealthy       docker up != 1 for 1m              CRITICAL
PM2ServiceDown              pm2 status != online for 2m         CRITICAL
```

---

## 8. AI Infrastructure

### 8.1 AI Service Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      AI INFRASTRUCTURE STACK                          │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    LiteLLM Proxy (EDGE:4000)                  │    │
│  │  ┌──────────────────────────────────────────────────────┐   │    │
│  │  │  Unified OpenAI-compatible API                        │   │    │
│  │  │  ├ /v1/chat/completions                              │   │    │
│  │  │  ├ /v1/embeddings                                    │   │    │
│  │  │  └ /v1/models                                        │   │    │
│  │  └──────────────────────────────────────────────────────┘   │    │
│  │                          │                                    │    │
│  │  ┌──────────────┐  ┌────┴─────┐  ┌──────────────┐           │    │
│  │  │ Load Balancer│  │  Router  │  │ Rate Limiter │           │    │
│  │  │ (round-robin)│  │(model→   │  │(per user,    │           │    │
│  │  │              │  │ provider)│  │ per model)    │           │    │
│  │  └──────────────┘  └────┬─────┘  └──────────────┘           │    │
│  │                         │                                     │    │
│  └─────────────────────────┼─────────────────────────────────────┘    │
│                            │                                          │
│         ┌──────────────────┼──────────────────┐                       │
│         │                  │                  │                       │
│         ▼                  ▼                  ▼                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                │
│  │  DeepSeek    │  │  Anthropic   │  │   OpenAI     │                │
│  │  Provider    │  │  Provider    │  │  Provider    │                │
│  │              │  │              │  │              │                │
│  │ deepseek-v3  │  │ claude-4.7  │  │ gpt-4o       │                │
│  │ deepseek-r1  │  │ claude-4.6  │  │ gpt-4o-mini  │                │
│  │ deepseek-coder│ │ claude-haiku│  │ o3-mini      │                │
│  └──────────────┘  └──────────────┘  └──────────────┘                │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    AI Agent Runtimes (AIOPS)                   │   │
│  │                                                                │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │   │
│  │  │ FRG CRM Agent│  │ InsForge     │  │ SurplusAI    │        │   │
│  │  │ Service      │  │ Agent        │  │ Scraper Agent│        │   │
│  │  │ (PM2)        │  │ (PM2)        │  │ (PM2)        │        │   │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │   │
│  │         │                 │                 │                 │   │
│  │         └─────────────────┼─────────────────┘                 │   │
│  │                           │                                   │   │
│  │                           ▼                                   │   │
│  │                    LiteLLM Proxy                               │   │
│  │                    (EDGE:4000 via Tailscale)                   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Voice Agent Service (PM2)                  │   │
│  │  ├ Speech-to-Text (Whisper via API)                          │   │
│  │  ├ LLM Processing (via LiteLLM)                              │   │
│  │  └ Text-to-Speech (OpenAI TTS via API)                       │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 8.2 Model Fallback Chains

```
Primary → Fallback Chain by Use Case:

General Chat:
  deepseek-v3 → claude-haiku-4.5 → gpt-4o-mini

Complex Reasoning:
  claude-4.7 → deepseek-r1 → o3-mini

Code Generation:
  deepseek-coder → claude-4.7 → gpt-4o

Embeddings:
  text-embedding-3-small → bge-large-en

Cost-Efficient (High Volume):
  deepseek-v3 → claude-haiku-4.5 → gpt-4o-mini
  (Each fallback increases cost by ~2-3x)

Fallback Trigger Conditions:
  ├ HTTP 5xx from provider → immediate fallback
  ├ Timeout > 30s → immediate fallback
  ├ Rate limit (429) → exponential backoff then fallback
  └ Provider returns null/empty → fallback after 1 retry
```

---

## 9. Deployment Topology

### 9.1 Configuration Management

```
/root/infrastructure/                           # Git-tracked infrastructure repo
├── ARCHITECTURE.md                             # This document (Phase 2)
├── enterprise/
│   ├── phase1-server-hardening/                # UFW, fail2ban, sysctl, limits, Docker
│   ├── phase2-observability/                   # Prometheus, Grafana, Loki, Alertmanager
│   ├── phase3-logging/                         # Logging architecture + PM2/Docker config
│   ├── phase4-healthcheck/                     # Health check scripts
│   ├── phase5-self-healing/                    # Auto-healing daemon (every 60s)
│   ├── phase6-backup/                          # Backup scripts + GPG config
│   ├── phase7-deployment/                      # Deploy scripts + compose files
│   ├── phase8-ai-infrastructure/               # LiteLLM, model configs
│   ├── phase9-server-roles/                    # Per-server role assignments
│   └── phase10-documentation/                  # These operational playbooks
├── hetzner/                                     # Hetzner-specific configs
├── hostinger/                                   # Hostinger-specific configs
└── shared/                                      # Cross-cutting configuration
```

### 9.2 Service Deployment Methods

```
Service Type          Method              Tooling               Rollback Strategy
────────────────────  ──────────────────  ────────────────────  ──────────────────
Docker Containers     Docker Compose       docker compose up -d  Image tag pin
PM2 Apps              PM2 ecosystem        pm2 start/restart     Git revert + restart
Database Migrations   Manual (psql/flyway) psql -f migrate.sql   Down migration or restore
Traefik Config        File replacement     cp + docker restart   Config backup
UFW/Firewall          Script execution     bash apply script     Reverse rules script
SSL Certificates      Traefik ACME         Automatic via LE      N/A (auto-renewal)
```

---

## 10. DNS and SSL Design

### 10.1 DNS Architecture

```
Zone: wheeler.ai (managed via Cloudflare DNS)

Record Type  Name                            Value              TTL    Proxy
───────────  ──────────────────────────────  ─────────────────  ────   ─────
A            wheeler.ai                      187.77.148.88      300    Yes (orange)
A            *.wheeler.ai                    187.77.148.88      300    Yes
CNAME        predictionradar.wheeler.ai      wheeler.ai         300    Yes
CNAME        ravynai.wheeler.ai              wheeler.ai         300    Yes
CNAME        superset.wheeler.ai             wheeler.ai         300    Yes
CNAME        grafana.wheeler.ai              wheeler.ai         300    Yes
CNAME        uptime.wheeler.ai               wheeler.ai         300    Yes
CNAME        healthchecks.wheeler.ai         wheeler.ai         300    Yes
CNAME        changedetect.wheeler.ai         wheeler.ai         300    Yes
CNAME        docuseal.wheeler.ai             wheeler.ai         300    Yes
CNAME        frgops.wheeler.ai               wheeler.ai         300    Yes
CNAME        chatwoot.wheeler.ai             wheeler.ai         300    Yes
CNAME        n8n.wheeler.ai                  wheeler.ai         300    Yes
CNAME        litellm.wheeler.ai              wheeler.ai         300    Yes
CNAME        netdata.wheeler.ai              wheeler.ai         300    Yes
CNAME        status.wheeler.ai               wheeler.ai         300    Yes
```

### 10.2 SSL Certificate Strategy

```
Provider:         Let's Encrypt (via Traefik ACME)
Challenge Type:   TLS-ALPN-01 (port 443)
Auto-Renewal:     30 days before expiry
Domains Covered:  Single wildcard *.wheeler.ai (preferred)
                  OR individual SAN certs per subdomain

EDGE Traefik:
  ├ *.wheeler.ai → wildcard cert
  └ Renewal: fully automatic

AIOPS Traefik:
  ├ *.internal.wheeler.ai → internal cert
  └ Used for inter-service TLS within the mesh

Manual Renewal (if auto fails):
  docker exec traefik traefik cert renew --dry-run

Expiry Monitoring:
  ├ Uptime Kuma: 30-day warning on all endpoints
  ├ Prometheus alert: SSLCertExpiring (7 days critical, 30 days warning)
  └ Manual check: bash healthcheck-all.sh (includes SSL validity)
```

---

## 11. Future Scaling Notes

### 11.1 Horizontal Scaling (Add More AIOPS Nodes)

```
Current: 1x AIOPS (Hetzner CPX51)
Future:  2-3x AIOPS nodes behind Traefik load balancer

Step 1: Provision new Hetzner CX51/CPX51
Step 2: Join Tailscale mesh
Step 3: Apply AIOPS UFW + hardening scripts
Step 4: Deploy Docker + Traefik + services
Step 5: Add to Traefik load balancer config
Step 6: Move databases to COREDB (dedicated server)
Step 7: Redis Sentinel for HA across nodes
Step 8: Evaluate Docker Swarm or k3s

Considerations:
  ├ Shared state: Move to COREDB + Redis Sentinel
  ├ Session affinity: Traefik sticky sessions
  ├ File storage: MinIO on COREDB (S3-compatible)
  └ Monitoring: Join existing Prometheus scrape config
```

### 11.2 Vertical Scaling (Bigger VPS)

```
Current AIOPS: CPX51 (16 vCPU, 32GB RAM, 360GB NVMe)
Next Tier:     CPX61 (24 vCPU, 48GB RAM, 480GB NVMe)
               OR CX52 (16 vCPU, 64GB RAM, 360GB NVMe) ← RAM-heavy

When to scale vertically:
  ├ RAM consistently >85% → more RAM
  ├ CPU consistently >80% → more vCPU
  ├ Disk consistently >80% → more NVMe
  └ All three borderline → next tier VPS

Hetzner resize process:
  1. Power off VPS via Hetzner Cloud Console
  2. Resize to new plan (preserves disk)
  3. Power on — IP and data preserved
  4. Verify all services restart
  5. Total downtime: ~5-10 minutes
```

### 11.3 GPU Node Integration

```
Future: Dedicated GPU worker nodes for on-premise model inference

GPU Node Spec (planned):
  ├ 1x NVIDIA L40S (48GB VRAM) or 2x A5000
  ├ 16 vCPU, 64GB RAM
  ├ Purpose: Self-hosted LLM inference (Llama, Mistral, Qwen)
  └ Connected via Tailscale mesh

Integration path:
  1. Deploy vLLM or TGI on GPU node
  2. Register as provider in LiteLLM
  3. Route internal workloads to GPU node first
  4. Fallback to external API providers if GPU is saturated
  5. Cost: GPU node amortizes after ~500K daily tokens

Cost Analysis (monthly):
  ├ Hetzner GPU node: ~€300-500/month (dedicated)
  ├ External API costs at scale: ~€1,500/month (100K tokens/day)
  └ Break-even at ~100K internal tokens/day
```

### 11.4 Long-Term Architecture Evolution

```
Phase 3 (Current + 3-6 months):
  ├ Add COREDB as dedicated database server
  ├ Add 1 more AIOPS worker node
  ├ Implement pgBouncer for connection pooling
  └ Redis Sentinel for HA

Phase 4 (6-12 months):
  ├ Docker Swarm across 2-3 AIOPS nodes
  ├ Read replicas for PostgreSQL
  ├ MinIO on COREDB for shared object storage
  └ k6 load testing framework

Phase 5 (12+ months):
  ├ k3s (Kubernetes) on Hetzner cloud
  ├ Auto-scaling with HPA
  ├ GitOps with ArgoCD/Flux
  ├ GPU node for self-hosted LLMs
  └ Hostinger EDGE stays as entry point
```

---

## Document Control

| Version | Date       | Author   | Changes                         |
|---------|------------|----------|---------------------------------|
| 1.0.0   | 2026-05-23 | SRE Team | Initial enterprise architecture |

**Next Review:** 2026-08-23
