# Wheeler Enterprise — Server Role Enforcement Policies

> **Version:** 1.0.0  
> **Last Updated:** 2026-05-23  
> **Scope:** Three-server Tailscale mesh architecture  
> **Enforcement Script:** `enforce-roles.sh`

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [EDGE Server (Hostinger) — "The Gatekeeper"](#edge-server-hostinger--the-gatekeeper)
3. [AIOPS Server (Hetzner) — "The Brain"](#aiops-server-hetzner--the-brain)
4. [COREDB Server (Hetzner) — "The Vault"](#coredb-server-hetzner--the-vault)
5. [Cross-Server Communication Rules](#cross-server-communication-rules)
6. [Role Labeling Standard](#role-labeling-standard)
7. [Violation Severity Classification](#violation-severity-classification)
8. [Audit & Enforcement Cadence](#audit--enforcement-cadence)
9. [Change Control Process](#change-control-process)

---

## Architecture Overview

```
                          INTERNET
                              |
                     ┌────────┴────────┐
                     │   Cloudflare     │
                     │   DNS / WAF      │
                     └────────┬────────┘
                              │
                    ┌─────────┴─────────┐
                    │  EDGE (Hostinger) │  187.77.148.88
                    │  "The Gatekeeper" │  100.64.0.2 (Tailscale)
                    └─────────┬─────────┘
                              │  Tailscale mesh (100.64.0.0/10)
              ┌───────────────┼───────────────┐
              │               │               │
     ┌────────┴────────┐     │    ┌──────────┴──────────┐
     │ AIOPS (Hetzner) │     │    │ COREDB (Hetzner)    │
     │ "The Brain"     │     │    │ "The Vault"         │
     │ 5.78.140.118    │     │    │ 5.78.210.123        │
     │ 100.64.0.3 (TS) │     │    │ 100.64.0.4 (TS)     │
     └─────────────────┘     │    └─────────────────────┘
                             │
                   NO DIRECT EDGE → COREDB PATH
```

**Three servers. Three distinct roles. Zero overlap of responsibilities.**

Every service, container, port binding, and volume mount must be justified by the server's role. Nothing runs "because it's convenient." This is a defense-in-depth posture where a compromise of any single server must not cascade to the others.

---

## EDGE Server (Hostinger) — "The Gatekeeper"

- **Public IP:** 187.77.148.88
- **Tailscale IP:** 100.64.0.2
- **Purpose:** Public-facing reverse proxy and static frontend delivery
- **Exposure:** This is the ONLY server reachable from the public internet. Cloudflare DNS points here. Every port open to 0.0.0.0 is an attack vector.

### ALLOWED on EDGE

#### Reverse Proxy & Traffic Management
- **Traefik** — The single entry point for all HTTP/HTTPS traffic. Handles:
  - SSL/TLS termination (Let's Encrypt via ACME)
  - Request routing to AIOPS backend services over Tailscale
  - Rate limiting, IP whitelisting/blacklisting middleware
  - HTTP → HTTPS redirect
  - `X-Forwarded-*` header injection
- **nginx** — Static file serving with micro-caching for frontend assets. Must run behind Traefik (no direct public port exposure). Configuration:
  - `gzip` enabled for text-based assets
  - `Cache-Control` headers with appropriate TTLs
  - Must NOT proxy to any internal service directly

#### Static Frontend Assets
- React / Next.js / Vite / SvelteKit production builds
- Static HTML, CSS, JavaScript bundles
- Public asset directories (images, fonts, favicons)
- Service worker files
- `robots.txt`, `sitemap.xml`
- **Rule:** Frontend builds are CI artifacts pushed to EDGE. No `node_modules` on EDGE. No build toolchain on EDGE.

#### Public-Facing Dashboards (READ-ONLY)
- **Uptime Kuma** status page — Public service status. Must be in read-only mode (no admin access from public IP; admin panel bound to Tailscale IP only).
- **Grafana** — Select dashboards exposed as read-only embeds. No edit access. No datasource configuration from public side. Must use anonymous viewer role with no org management.

#### Security & Observability Agents
- **fail2ban** — SSH brute-force protection, Traefik auth failure jailing. Configured with Wheeler-specific jails.
- **UFW** (Uncomplicated Firewall) — Default deny incoming. Only 22, 80, 443 from any source. All other ports rejected.
- **node_exporter** — Prometheus metrics exporter. Must bind to Tailscale IP ONLY (100.64.0.2:9100), never 0.0.0.0.
- **promtail** — Log shipping to Loki on AIOPS. Must connect over Tailscale (100.64.0.3:3100).

#### SSL Certificate Management
- Let's Encrypt certificate renewal via Traefik ACME resolver
- Certificate files stored in `/etc/traefik/certs/` (Docker volume)
- Auto-renewal with 30-day default check interval

### NEVER on EDGE

This list is enforced by `enforce-roles.sh`. Any container or process matching these is a **CRITICAL** violation.

#### Databases — ALL TYPES
- ❌ PostgreSQL (port 5432)
- ❌ Redis (port 6379)
- ❌ ClickHouse (ports 8123, 9000)
- ❌ MongoDB (port 27017)
- ❌ MySQL / MariaDB (port 3306)
- ❌ Elasticsearch (ports 9200, 9300)
- ❌ SQLite files > 10MB (config DBs like Traefik's boltdb are OK but must be < 50MB)
- ❌ Any database connection pooler (pgBouncer, pgbouncer, etc.)

#### AI / ML Services
- ❌ LiteLLM, LangFlow, Ollama, vLLM, LocalAI
- ❌ Any container image containing: `cuda`, `cudnn`, `pytorch`, `tensorflow`, `transformers`, `onnx`, `gguf`, `ggml`
- ❌ GPU drivers or CUDA toolkit packages
- ❌ Vector databases (Qdrant, pgvector extension, Weaviate, Milvus, Chroma)
- ❌ Embedding models or tokenizer services

#### Worker / Queue Processors
- ❌ BullMQ workers
- ❌ Celery workers
- ❌ Sidekiq
- ❌ RabbitMQ consumers
- ❌ Kafka consumers/producers
- ❌ Temporal workers
- ❌ n8n workflow engine (the n8n status page can show on EDGE, but the engine runs on AIOPS)

#### Backup Storage
- ❌ Database dump files (`.sql`, `.dump`, `.pgdump`, WAL archives)
- ❌ Volume backup tarballs
- ❌ `restic` / `borg` / `duplicity` repositories
- ❌ S3 backup buckets or MinIO gateway
- ❌ **Backups are stored on and taken FROM COREDB only.**

#### Application Code
- ❌ Node.js / Python / Go / Rust / Ruby API servers
- ❌ Express, Fastify, FastAPI, Gin, Actix, Rails, Django, Flask runtimes
- ❌ WebSocket servers (these run on AIOPS)
- ❌ GraphQL servers
- ❌ gRPC servers (Traefik can route gRPC, but the servers run on AIOPS)
- ❌ Serverless function runtimes (OpenFaaS, Fission, etc.)

#### Infrastructure Services
- ❌ Docker registry (images are pulled from Docker Hub / GHCR directly on each server)
- ❌ CI/CD runners (GitHub Actions self-hosted runner, GitLab runner, Jenkins agent)
- ❌ Build toolchains (`gcc`, `rustc`, `go build`, `cargo`, `pip install`)
- ❌ Container orchestration dashboards (Portainer, Dockge — these run on AIOPS)
- ❌ DNS servers (bind9, CoreDNS, dnsmasq — except local resolver for Docker)

#### Non-Public Data
- ❌ Environment files with secrets for internal services
- ❌ API keys or service account credentials (except what Traefik needs for routing)
- ❌ SSH private keys for internal servers
- ❌ `/etc/wheeler/secrets/` directory (this belongs on AIOPS and COREDB only)

### Why This Matters

EDGE sits on the public internet. Hostinger's network is outside the Hetzner private network. A compromise of EDGE means an attacker has a foothold on:
- A server with a public IP
- A server that can reach AIOPS and COREDB via Tailscale

Every additional service on EDGE is:
1. A new attack surface (more open ports, more code, more vulnerabilities)
2. A new pivot point (if the attacker gets Redis, they get session data; if they get a database, they get everything)
3. A new exfiltration path (databases on EDGE mean data can be dumped directly to the internet)

**The rule:** If EDGE is breached, the attacker should find Traefik configuration, nginx static files, and nothing else. No credentials. No data. No application logic. No internal network maps beyond what Tailscale's encrypted tunnel reveals (which is nothing useful without the Tailscale key, which is rotated on compromise).

---

## AIOPS Server (Hetzner) — "The Brain"

- **Public IP:** 5.78.140.118
- **Tailscale IP:** 100.64.0.3
- **Purpose:** All compute workloads — AI, APIs, workers, orchestration, monitoring
- **Exposure:** No public internet exposure. All traffic arrives via EDGE over Tailscale. UFW allows only Tailscale subnet (100.64.0.0/10) on service ports.

### ALLOWED on AIOPS

#### AI Inference Services
- **LiteLLM** — Multi-provider LLM proxy with rate limiting, cost tracking, and failover. Listens on Tailscale IP only.
- **LangFlow** — Visual AI workflow builder. Admin UI bound to Tailscale IP.
- **Custom AI Agents** — Python/Node.js agent runtimes using Claude API, OpenAI, or local models.
- **Ollama** (optional) — Local model serving for latency-sensitive or air-gapped inference.
- **Model caches** — Hugging Face model files, GGUF weights, ONNX models. Stored in `/data/models/`.

#### API Servers
- **Node.js** — Express, Fastify, Hono, Nitro servers
- **Python** — FastAPI, Flask, Django (WSGI/ASGI), Litestar
- **Go** — Gin, Echo, Fiber, Chi, standard `net/http`
- **gRPC services** — For internal service-to-service communication
- **WebSocket servers** — Real-time data feeds, live collaboration
- **GraphQL** — Apollo Server, Strawberry, Graphene
- **REST / OpenAPI** — All public and internal API endpoints

#### Worker & Queue Processors
- **BullMQ** — Redis-backed job queues for Node.js
- **Celery** — Distributed task queue for Python
- **Temporal** — Workflow orchestration engine
- **n8n** — Low-code workflow automation (engine + editor on AIOPS; status page only on EDGE)
- **Airflow** (optional) — Scheduled DAG execution for data pipelines

#### Orchestration & Scheduling
- **n8n workflow engine** — Full workflow editor and execution
- **Temporal server + workers** — Durable execution for long-running workflows
- **Cron-based scheduled tasks** — System maintenance, data sync, cleanup jobs

#### Monitoring & Observability Stack
- **Prometheus** — Metrics collection and alerting rules evaluation. Listens on Tailscale IP.
  - Retention: 30 days at 15s scrape interval
  - Remote write to Thanos/Cortex if needed for long-term storage
- **Grafana** — Dashboards, alerts UI, exploration. Admin access on Tailscale IP only.
  - Read-only snapshot dashboards may be proxied to EDGE
- **Loki** — Log aggregation. Receives logs from all three servers via promtail.
- **Alertmanager** — Alert routing to Slack, email, PagerDuty.
- **Promtail** — Ships AIOPS logs to Loki (localhost).

#### Development & Management Tools
- **Portainer** — Docker container management UI. Admin access on Tailscale IP only.
- **Dockge** — Docker Compose stack management. Admin access on Tailscale IP only.
- **CI/CD agents** — Self-hosted GitHub Actions runner, GitLab runner. Must be isolated in Docker.
- **Docker Registry Mirror** — Optional pull-through cache for faster image pulls.

### ALLOWED WITH RESTRICTIONS on AIOPS

#### Database Read Replicas
- PostgreSQL read replicas are allowed ONLY if the container has the Docker label:
  ```
  com.wheeler.role=read-replica
  com.wheeler.primary=100.64.0.4:5432
  ```
- Redis can run as a **cache layer** (volatile data, all-keys LRU eviction) but NOT as primary store.
- ClickHouse **aggregating replicas** are allowed for analytics workloads.

#### Caching Layers
- Redis with `maxmemory-policy allkeys-lru` — cache only, no persistence
- In-memory caches (Node.js `node-cache`, Python `lru-dict`)
- Response caching in API gateway

### NEVER on AIOPS

#### Primary Databases
- ❌ PostgreSQL as primary write master
- ❌ Redis with persistence (`appendonly yes` or RDB snapshots with `save` directive)
- ❌ MySQL / MariaDB as primary
- ❌ MongoDB as primary
- ❌ Any database that is the SOURCE OF TRUTH for business data
- ❌ **Rationale:** If AIOPS is rebuilt, no business data should be lost. COREDB is the source of truth.

#### Long-Term Backup Storage
- ❌ Backup artifacts older than 24 hours
- ❌ `restic` / `borg` repositories (these live on COREDB)
- ❌ Database dump files (WAL archives, `pg_dump` output)
- ❌ Volume snapshot storage
- ❌ **Rationale:** AIOPS can have temporary staging space for backup creation, but completed backups must be pushed to COREDB (MinIO) within 24 hours.

#### Public DNS Zone Files
- ❌ Authoritative DNS zone data
- ❌ CoreDNS serving as authoritative nameserver
- ❌ Cloudflare zone file mirrors
- ❌ **Rationale:** DNS is infrastructure-level config. Zone files live in git, deployed by CI to Cloudflare API.

#### User Upload Storage
- ❌ User-uploaded files stored on local disk
- ❌ User media directories
- ❌ `/data/uploads/` with user content
- ❌ **Rationale:** User uploads go to COREDB MinIO. AIOPS may have a temp staging directory for processing, but final storage is on COREDB.

#### Blockchain Nodes
- ❌ Bitcoin, Ethereum, Solana, or any blockchain full nodes
- ❌ IPFS nodes
- ❌ **Rationale:** These are extremely resource-intensive (storage, bandwidth, CPU). Not a good fit for a compute server that needs predictable performance.

### AIOPS Posture

- **UFW:** Default deny incoming. Allow Tailscale subnet (100.64.0.0/10) on service ports. Allow SSH from Tailscale only.
- **No public ports:** NOTHING on 0.0.0.0 except SSH (and even SSH should be on Tailscale IP eventually).
- **Port bindings:** All services bind to Tailscale IP (100.64.0.3) or 127.0.0.1, never 0.0.0.0.
- **Docker socket:** Protected. Portainer access is authenticated and over Tailscale only.

---

## COREDB Server (Hetzner) — "The Vault"

- **Public IP:** 5.78.210.123
- **Tailscale IP:** 100.64.0.4
- **Purpose:** All persistent state — databases, caches, object storage, vector stores, backups
- **Exposure:** ZERO public access. Most locked-down server. Talks only to AIOPS over Tailscale. Default-deny firewall on everything.

### ALLOWED on COREDB

#### Primary Databases
- **PostgreSQL** — Primary write master. All application schemas live here.
  - Port 5432, bound to Tailscale IP (100.64.0.4) only
  - Streaming replication enabled (replicas on AIOPS are subscribers)
  - WAL archiving enabled (archives stored to MinIO on localhost)
  - Connection pooling via pgBouncer on port 6432
- **Redis** — Primary cache and queue store.
  - Port 6379, bound to Tailscale IP only
  - Persistence: AOF + RDB snapshots (this is the source of truth for queue data)
  - `maxmemory-policy noeviction` (don't silently drop data)
  - Password-protected with `requirepass`

#### Object & File Storage
- **MinIO** — S3-compatible object storage.
  - API on port 9000, bound to Tailscale IP only
  - Web console on port 9001, bound to Tailscale IP only (admin access)
  - Erasure-coded storage across `/data/minio/` disks
  - Buckets: `backups`, `uploads`, `assets`, `logs-archive`
  - Versioning enabled on `backups` and `uploads` buckets
  - Object lock (WORM) enabled on `backups` bucket

#### Vector Stores
- **Qdrant** — Vector similarity search engine.
  - HTTP API on port 6333, gRPC on port 6334, bound to Tailscale IP only
  - Used by AI services on AIOPS for RAG (Retrieval Augmented Generation)
- **pgvector** — PostgreSQL extension for vector embeddings.
  - In-process, no separate port. Controlled via PostgreSQL access controls.

#### Analytics Database
- **ClickHouse** — Column-oriented analytics database.
  - HTTP on port 8123, Native on port 9000, bound to Tailscale IP only
  - Used for event analytics, time-series data, log aggregation summaries
  - Not used for transactional data

#### Backup Infrastructure
- **restic** — Encrypted backup tool. Repository on local MinIO or remote S3.
  - Hourly database snapshots
  - Daily full volume backups
  - Retention: 7 daily, 4 weekly, 3 monthly, 1 yearly
- **pgBackRest** — PostgreSQL backup and restore.
  - Full backups weekly, differential nightly, incremental every 6 hours
  - WAL archiving continuous
- **WAL archiving** — PostgreSQL Write-Ahead Log shipping to MinIO for point-in-time recovery.
- **Backup verification** — Weekly automated restore test to temporary PostgreSQL instance.

#### Database Management
- **pgBouncer** — Connection pooling for PostgreSQL.
  - Port 6432, bound to Tailscale IP only
  - Transaction pooling mode
  - `max_client_conn = 500`, `default_pool_size = 25`
- **pgAdmin** — (Optional) Database administration UI. If installed, bound to Tailscale IP only, behind strong authentication.

### ALLOWED WITH RESTRICTIONS on COREDB

#### Monitoring Exporters (NO DASHBOARDS)
- **node_exporter** — System metrics. Port 9100, bound to Tailscale IP only.
- **postgres_exporter** — PostgreSQL metrics. Port 9187, bound to Tailscale IP only.
- **redis_exporter** — Redis metrics. Port 9121, bound to Tailscale IP only.
- **MinIO metrics** — Built-in Prometheus endpoint on port 9000.
- **Rule:** Exporters only. No Prometheus server scraping. No Grafana. The metrics are PULLED by Prometheus running on AIOPS.

#### Health Endpoints
- Simple HTTP health checks on Tailscale IP for monitoring
- Must not expose any data, just `{"status":"ok"}` with DB connection check
- Must have no auth bypass or data exposure

### NEVER on COREDB

#### Public-Facing Services
- ❌ Traefik, nginx, Caddy, Apache — NO HTTP/HTTPS servers for external or user traffic
- ❌ Any service listening on 0.0.0.0 (only Tailscale IP: 100.64.0.4, or 127.0.0.1 for local)
- ❌ SSL certificates for public domains
- ❌ **Exception:** MinIO web console (port 9001) on Tailscale IP is allowed. This is administrative, not public.

#### Application Code
- ❌ No Node.js / Python / Go / Rust API servers
- ❌ No Express, Fastify, FastAPI, Gin, Django runtimes
- ❌ No compiled application binaries
- ❌ No `node_modules` directories
- ❌ No `pip` virtual environments for application code
- ❌ **Rationale:** COREDB runs databases. Application bugs can corrupt data. Keep the surface minimal.

#### AI Inference
- ❌ No LLM models (LiteLLM, Ollama, vLLM, LocalAI)
- ❌ No embedding generation (sentence-transformers, text-embeddings-inference)
- ❌ No GPU drivers or CUDA libraries
- ❌ No model weights or tokenizer files
- ❌ **Rationale:** AI inference is compute-intensive and distracts from database performance. AIOPS handles all AI.

#### Cron Jobs (Except DB Maintenance)
- ❌ No application cron jobs
- ❌ No data processing pipelines
- ❌ No external API calls from cron
- ❌ **Allowed exceptions:** `VACUUM`, `ANALYZE`, `REINDEX`, backup scripts, WAL archival, log rotation
- ❌ **Rationale:** Cron jobs on the database server can cause unplanned load spikes. Schedule computation on AIOPS.

#### Monitoring Dashboards
- ❌ No Grafana server
- ❌ No Prometheus server
- ❌ No Kibana, Chronograf, or any visualization UI
- ❌ Metrics are EXPOSED by exporters, not CONSUMED here
- ❌ **Rationale:** Dashboards require web servers and authentication. Keep COREDB's surface minimal.

#### CI/CD
- ❌ No GitHub Actions runners, GitLab runners, Jenkins agents
- ❌ No build toolchains (`gcc`, `rustc`, `go`, `cargo`)
- ❌ No Docker image builds
- ❌ No git operations (clone, pull) for application repos
- ❌ **Exception:** `git pull` for infrastructure-as-code repo to update backup scripts is allowed.
- ❌ **Rationale:** CI/CD introduces arbitrary code execution risk on the most critical data server.

#### Non-DB Container Workloads
- ❌ No general-purpose containers that are not database-related
- ❌ No Portainer, Dockge (management UIs — these run on AIOPS)
- ❌ No n8n, Temporal (workflow engines — these run on AIOPS)
- ❌ No message brokers (RabbitMQ, NATS, Kafka) unless they are backend for a database feature

### COREDB Posture

- **UFW:** Default deny ALL incoming. Allow only Tailscale subnet (100.64.0.0/10) on database ports. No SSH from public internet.
- **No 0.0.0.0 bindings:** Every service binds to Tailscale IP or 127.0.0.1. Nothing answers on the public network interface.
- **Data partition:** All database data on `/data` mount (separate volume, not root FS). Prevents disk-full from crashing the OS.
- **No Docker socket exposure:** Docker socket is local-only, not mounted into any container.
- **Encryption at rest:** LUKS on `/data` partition. MinIO server-side encryption enabled. PostgreSQL TDE if available.

---

## Cross-Server Communication Rules

### Allowed Communication Paths

```
EDGE ──────────────────► AIOPS
  │  HTTP/HTTPS via Tailscale
  │  Traefik routes API requests to AIOPS services
  │  nginx serves static files locally (no direct backend access)
  │
  │  NEVER EDGE → COREDB (must go through AIOPS API)
  │
AIOPS ─────────────────► COREDB
  │  PostgreSQL:  5432  (via Tailscale)
  │  pgBouncer:   6432  (via Tailscale)
  │  Redis:       6379  (via Tailscale)
  │  MinIO:       9000  (via Tailscale)
  │  Qdrant:      6333  (via Tailscale)
  │  ClickHouse:  8123  (via Tailscale)
  │
  │  NEVER AIOPS → COREDB:9001 (MinIO console — admin only)
  │
COREDB ─────────────────► AIOPS
  │  Metrics scraped by Prometheus on AIOPS
  │  Logs shipped by promtail to Loki on AIOPS
  │  Health checks from AIOPS monitoring
  │
  │  NEVER COREDB → EDGE (no reason)
```

### Forbidden Communication Paths

| FROM    | TO      | PATH              | REASON                                                    |
|---------|---------|-------------------|-----------------------------------------------------------|
| EDGE    | COREDB  | Any               | EDGE is public-facing. Must never reach the data layer.   |
| COREDB  | EDGE    | Any               | COREDB has no reason to initiate connections to EDGE.     |
| EDGE    | AIOPS   | 5432, 6379, etc.  | EDGE only talks to AIOPS APIs (HTTP), not direct DB.      |
| COREDB  | Internet| Any (except apt)  | COREDB does not initiate outbound internet connections.   |
| AIOPS   | Internet| 0.0.0.0 binds     | AIOPS services do not accept connections from internet.   |

### Tailscale ACL Summary

```jsonc
{
  "acls": [
    // EDGE can only talk to AIOPS on HTTP/HTTPS ports
    {"action": "accept", "src": ["tag:edge"], "dst": ["tag:aiops:80,443,3000-3999,8000-8999"], "proto": "tcp"},

    // AIOPS can talk to COREDB on database ports
    {"action": "accept", "src": ["tag:aiops"], "dst": ["tag:coredb:5432,6379,6432,9000,6333,8123,9000"], "proto": "tcp"},

    // COREDB can talk to AIOPS monitoring
    {"action": "accept", "src": ["tag:coredb"], "dst": ["tag:aiops:3100,9090"], "proto": "tcp"},

    // Default deny everything else
  ]
}
```

### Internet Access Policy

| Server  | Outbound Internet            | Inbound Internet        |
|---------|------------------------------|-------------------------|
| EDGE    | `apt`, `docker pull`, Let's Encrypt, Tailscale | Ports 22, 80, 443 only |
| AIOPS   | `apt`, `docker pull`, Tailscale, API calls (Claude API, etc.) | NONE (all via EDGE)    |
| COREDB  | `apt`, `docker pull`, Tailscale only | NONE                    |

---

## Role Labeling Standard

Every Docker container MUST carry a label identifying its server role. This is the primary mechanism used by `enforce-roles.sh` to detect misplacements.

### Required Labels

| Label                     | Value                       | Required | Description                                    |
|---------------------------|-----------------------------|----------|------------------------------------------------|
| `com.wheeler.role`        | `edge`, `aiops`, `coredb`   | YES      | The server role this container belongs on       |
| `com.wheeler.service`     | e.g. `traefik`, `postgres`  | YES      | Human-readable service name                     |
| `com.wheeler.tier`        | `frontend`, `backend`, `data`| YES     | Architectural tier                              |
| `com.wheeler.managed-by`  | `docker-compose`, `portainer`| RECOMMENDED | How the container is managed                |

### Example Compose Snippet

```yaml
services:
  postgres:
    image: postgres:16-alpine
    labels:
      - "com.wheeler.role=coredb"
      - "com.wheeler.service=postgres"
      - "com.wheeler.tier=data"
      - "com.wheeler.managed-by=docker-compose"
```

### Special Labels

| Label                            | Value      | Meaning                                               |
|----------------------------------|------------|-------------------------------------------------------|
| `com.wheeler.role=read-replica`  | (any)      | DB container on AIOPS is a read replica, not primary  |
| `com.wheeler.role=read-replica`  | `100.64.0.4:5432` | Primary database for this replica           |
| `com.wheeler.unlabeled`          | `warning`  | Container has no role label (generated by audit)      |
| `com.wheeler.violation`          | `critical` | Container is on wrong server (generated by audit)     |

---

## Violation Severity Classification

### CRITICAL — Block Deployment, Require Immediate Fix

These violations represent active security risks or data integrity threats:

- Database running on EDGE
- AI/ML services on EDGE or COREDB
- Application code on COREDB
- Any service bound to 0.0.0.0 on COREDB
- Public port exposure on AIOPS (anything other than SSH on 0.0.0.0)
- Primary database (non-read-replica) on AIOPS
- Backup storage on EDGE or AIOPS (not synced to COREDB within 24h)
- Tailscale not running on any server

### WARNING — Schedule Fix Within 7 Days

These violations degrade the security posture but are not immediate threats:

- Container missing `com.wheeler.role` label
- Volume >1GB on EDGE (not config)
- Data volume on root partition instead of `/data` on COREDB
- Monitoring dashboard running on COREDB
- Cron job on COREDB that is not DB maintenance
- Redis persistence enabled on AIOPS cache
- Any 0.0.0.0 binding that should be Tailscale-only (except on EDGE)

### INFO — Best Practice Recommendation

These are optimization opportunities, not violations:

- Container labels incomplete (has `role` but missing `service` or `tier`)
- Service could benefit from read replica instead of hitting primary DB
- Logs not shipping to Loki
- Metrics not exposed to Prometheus
- No health check endpoint configured

---

## Audit & Enforcement Cadence

| Event                         | Action                                              |
|-------------------------------|-----------------------------------------------------|
| Every Docker container start  | `enforce-roles.sh` run as pre-start hook (if configured) |
| Hourly                        | Automated audit via cron: `enforce-roles.sh --report` |
| Daily                         | Report reviewed by on-call (or automated Slack notification on violations) |
| Weekly                        | Full compliance sweep with `--fix` suggestions reviewed |
| Before any deployment         | `enforce-roles.sh --server <role>` must pass clean   |
| CI/CD pipeline                | Audit report compared against baseline; diff flagged |

### Prometheus Alerting Rules

```yaml
groups:
  - name: role_compliance
    rules:
      - alert: CriticalRoleViolation
        expr: wheeler_role_violations{severity="critical"} > 0
        for: 5m
        labels:
          severity: page
        annotations:
          summary: "CRITICAL role violation on {{ $labels.server }}"
          description: "{{ $labels.container }} is running on wrong server"

      - alert: UnlabeledContainer
        expr: wheeler_containers_unlabeled > 0
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Unlabeled containers on {{ $labels.server }}"
```

---

## Change Control Process

Moving a service between server roles requires:

1. **Proposal:** Document what moves, why, and impact analysis
2. **Security review:** Does this increase attack surface on EDGE? Does this put compute on COREDB?
3. **Policy update:** This document must be updated BEFORE the move
4. **Enforcement script update:** `enforce-roles.sh` must be updated to reflect new policy
5. **Label migration:** New containers must carry correct `com.wheeler.role` labels
6. **Audit pass:** `enforce-roles.sh --report` must show zero CRITICAL violations after migration
7. **72-hour monitoring:** Watch for unexpected cross-server traffic spikes in Tailscale metrics

**No exceptions without documented approval.** The role separation is the foundation of Wheeler's defense-in-depth strategy. Every exception erodes that foundation.
