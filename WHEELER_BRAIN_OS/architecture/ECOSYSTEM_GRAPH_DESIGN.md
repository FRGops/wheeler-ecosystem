# Wheeler Brain OS — Ecosystem Graph Design

## 1. Overview

The Ecosystem Graph is the living knowledge graph that models every entity and relationship in the Wheeler ecosystem. It serves as the "memory" layer for Wheeler Brain OS, enabling traversal queries that answer operational questions impossible with flat inventories.

### Why a Graph?

Flat lists (CSVs, tables) can tell you **what** exists. A graph tells you **what depends on what**, **what breaks if X fails**, and **what's the blast radius of Y**. For an ecosystem with 58 containers, 17 PM2 processes, 12 agents, and 15+ repos across 2 servers, the relationship graph is the only tractable representation.

---

## 2. Node Types (Entity Schema)

### 2.1 Physical Layer

```
Node: Server
Properties:
  - hostname: string (unique)
  - tailscale_ip: string (CIDR)
  - public_ip: string
  - provider: string (Hetzner|Hostinger|Local)
  - cpu: string
  - ram_gb: integer
  - disk_gb: integer
  - os: string
  - role: string (application|database|edge|command)
  - ufw_active: boolean
  - status: enum (online|degraded|offline)

Current instances:
  - wheeler-aiops-01        (100.121.230.28, Hetzner CPX51)
  - wheeler-core-db-01      (100.118.166.117, Hetzner)
  - srv1476866              (100.98.163.17, Hostinger)
  - wheelers-macbook-pro    (100.83.80.6, Local)
```

### 2.2 Container Layer

```
Node: DockerContainer
Properties:
  - container_name: string (unique)
  - image: string
  - image_tag: string (pinned|latest)
  - internal_port: integer
  - published_port: string (127.0.0.1:X|100.X.X.X:X|internal)
  - status: enum (healthy|unhealthy|starting|stopped)
  - mem_limit: string
  - cpus: float
  - cap_drop: [string]
  - cap_add: [string]
  - user: string (root|uid:gid)
  - network: string
  - compose_stack: string
  - healthcheck: boolean

Current instances: 40 (AIOPS) + 19 (COREDB) = 59 total
```

### 2.3 Process Layer

```
Node: PM2Process
Properties:
  - process_name: string (unique)
  - pid: integer
  - port: integer
  - runtime: enum (node|python)
  - status: enum (online|stopped|errored|launching)
  - restarts: integer
  - memory_mb: float
  - uptime_seconds: integer
  - cwd: string
  - script: string
  - model: string (for agent processes)

Current instances: 18 (AIOPS only, 17 online + 1 stopped)
```

### 2.4 Agent Layer

```
Node: Agent
Properties:
  - agent_name: string (unique)
  - agent_type: enum (business|intelligence|infrastructure|claude-code|docker)
  - runtime: enum (pm2|docker|claude-code|cron)
  - port: integer
  - domain: string (CRM|trading|voice|design|security|...)
  - llm_model: string
  - llm_proxy: string
  - polling_interval_ms: integer
  - external_dependencies: [string]
  - auto_restart: boolean

Current instances:
  PM2 Agents (9): frgcrm, surplusai-scraper, voice, insforge, design,
                   horizon, paperless, ravyn, prediction-radar
  PM2 Infra (9): litellm, ecosystem-guardian, event-bus-relay, war-room,
                  openclaw-dashboard, frgcrm-api, surplusai-portal-api,
                  voice-outreach, backup-verification
  Claude Code (12): wheeler-worker, wheeler-deploy, wheeler-db, wheeler-infra,
                     wheeler-security, wheeler-mac, engineering-sre,
                     engineering-code-reviewer, docker-expert,
                     devops-smoke-tester, database-rls-auditor,
                     zero-false-green-auditor
```

### 2.5 Data Layer

```
Node: Database
Properties:
  - db_name: string
  - db_type: enum (postgresql|redis|clickhouse|minio)
  - host_server: string
  - port: integer
  - bind_address: string
  - container: string
  - size_gb: float
  - backups: boolean
  - backup_schedule: string

Current instances:
  PostgreSQL: wheeler-core (COREDB), frgops-standby (AIOPS),
              ravynai (AIOPS), prediction-radar (AIOPS), temporal (AIOPS)
  Redis: wheeler-core (COREDB), prediction-radar (AIOPS), docuseal (AIOPS)
  ClickHouse: analytics (AIOPS)
  MinIO: wheeler-minio (COREDB)
```

### 2.6 Repository Layer

```
Node: Repository
Properties:
  - repo_path: string (unique)
  - remote_url: string
  - branch: string
  - last_commit_hash: string
  - has_remote: boolean
  - purpose: string
  - tags: [string]

Current instances: 9 (AIOPS) + 2 (COREDB) = 11 total
```

### 2.7 Dashboard Layer

```
Node: Dashboard
Properties:
  - dashboard_name: string (unique)
  - url: string
  - proxy_target: string
  - port: integer
  - service_type: string (grafana|prometheus|uptime|analytics|admin|app)
  - auth_required: boolean
  - rate_limited: boolean
  - status: enum (accessible|degraded|inaccessible)

Current instances: 19 nginx-proxied + 3 COREDB direct + 5 internal = 27 total
```

### 2.8 Network Layer

```
Node: Network
Properties:
  - network_name: string
  - subnet: string
  - driver: enum (bridge|host|overlay)
  - host: string
  - container_count: integer

Current instances: 16 (AIOPS) + 2 (COREDB) = 18 Docker networks
```

### 2.9 Secret Layer

```
Node: Secret
Properties:
  - secret_name: string
  - category: enum (database|api_key|jwt|token|password)
  - rotation_status: enum (rotated|pending|expired)
  - rotation_date: date (nullable)
  - rotation_interval_days: integer
  - blast_radius: [string] (list of affected services)
  - env_file_path: string

Current instances: 17 internal (rotated) + 60+ external (pending)
```

### 2.10 CronJob Layer

```
Node: CronJob
Properties:
  - job_name: string
  - schedule: string (cron expression)
  - command: string
  - host: string
  - category: enum (health|backup|security|enforcement|cleanup|alerting)
  - status: enum (active|inactive|failing)

Current instances: 14 (AIOPS)
```

---

## 3. Relationship Types (Edge Schema)

### 3.1 Infrastructure Relationships

```
[:RUNS_ON]        Container → Server, PM2Process → Server
[:HOSTS]          Server → Container, Server → PM2Process
[:CONTAINS]       Network → Container, ComposeStack → Container
[:PART_OF]        Container → ComposeStack
[:BOUND_TO]       Container → Port (published)
```

### 3.2 Dependency Relationships

```
[:DEPENDS_ON]     Container → Database, Agent → LLM_Proxy
                  Agent → ExternalAPI, Container → Container
[:CONNECTS_TO]    Agent → Service (active connection)
[:ROUTES_THROUGH] Service → Nginx (proxy routing)
[:PROXIES_TO]     Nginx → Container (virtual host mapping)
[:USES_DB]        Service → Database
[:CACHES_IN]      Service → Redis
```

### 3.3 Operational Relationships

```
[:MONITORS]       Prometheus → Target, UptimeKuma → Endpoint
                  Guardian → Process
[:ALERTS_TO]      Alertmanager → Discord (via webhook)
[:BACKS_UP]       BackupContainer → Database, BackupScript → Path
[:ROTATES]        RotationJob → Secret
[:ENFORCES]       CronJob → Policy
[:HEALS]          AutoHealScript → Container, AutoHealScript → PM2Process
```

### 3.4 Code Relationships

```
[:TRACKED_BY]     Repository → Remote
[:DEPLOYS_TO]     Repository → Server
[:BUILDS]         Repository → ContainerImage
[:OWNS]           Repository → PM2Process
```

### 3.5 Agent Relationships

```
[:ORCHESTRATES]   OrchestratorAgent → Agent
[:DISCOVERS]      EcosystemGuardian → Agent
[:ROUTES_MODEL]   LiteLLM → LLMProvider
[:FAILS_OVER_TO]  Model → FallbackModel
```

---

## 4. Critical Graph Queries

### 4.1 Blast Radius Analysis

```cypher
-- What breaks if COREDB PostgreSQL goes down?
MATCH (db:Database {db_name: 'wheeler-core'})
MATCH (s:Service)-[:DEPENDS_ON|:USES_DB]->(db)
MATCH (a:Agent)-[:CONNECTS_TO]->(s)
RETURN s, a

-- Expected result: frgcrm-api, surplusai-portal-api, usesend,
--                  all 9 PM2 agents, temporal workers, prediction-radar
```

### 4.2 Single Point of Failure Detection

```cypher
-- Find nodes with >5 inbound dependencies
MATCH (n)<-[r:DEPENDS_ON|:USES_DB|:CONNECTS_TO|:ROUTES_THROUGH]-(d)
WITH n, count(d) AS dependency_count
WHERE dependency_count > 5
RETURN n, dependency_count
ORDER BY dependency_count DESC

-- Expected top results: LiteLLM (9 agents), DeepSeek API (9 agents),
--                       COREDB PostgreSQL (6+ services)
```

### 4.3 Security Posture Query

```cypher
-- Find containers without cap_drop ALL
MATCH (c:DockerContainer)
WHERE NOT 'ALL' IN c.cap_drop
RETURN c.container_name, c.image, c.cap_drop

-- Find containers bound to 0.0.0.0
MATCH (c:DockerContainer)
WHERE c.published_port STARTS WITH '0.0.0.0'
RETURN c.container_name, c.published_port
```

### 4.4 Health Dashboard Query

```cypher
-- What's unhealthy right now?
MATCH (n)
WHERE n.status IN ['unhealthy', 'stopped', 'errored', 'offline', 'failing']
RETURN labels(n) AS type, n

-- Current answer: backup-verification (stopped), none unhealthy
```

### 4.5 Dependency Chain for Deployment

```cypher
-- What needs to be running before starting prediction-radar-app?
MATCH path = (s:Service {name: 'prediction-radar-app'})-[:DEPENDS_ON*1..3]->(d)
RETURN path
```

### 4.6 Secret Rotation Impact

```cypher
-- What services need restart if DEEPSEEK_API_KEY rotates?
MATCH (s:Secret {secret_name: 'DEEPSEEK_API_KEY'})
MATCH (a:Agent)-[:USES_SECRET]->(s)
MATCH (a)-[:ROUTES_THROUGH]->(p:Service)
RETURN a, p
```

### 4.7 Unmonitored Services

```cypher
-- Find services not monitored by any Prometheus or Uptime Kuma
MATCH (s:Service)
WHERE NOT (s)<-[:MONITORS]-(:Prometheus)
  AND NOT (s)<-[:MONITORS]-(:UptimeKuma)
RETURN s
```

---

## 5. Implementation Architecture

### 5.1 Graph Database Choice: Neo4j (Community Edition)

```
Reasons:
  1. Cypher query language — expressive, well-documented
  2. Native graph storage — not a relational-to-graph translation layer
  3. Bloom visualization — executive-friendly graph exploration
  4. APOC library — graph algorithms (centrality, community detection)
  5. Docker deployment — single container, same pattern as rest of Wheeler
```

### 5.2 Deployment Model

```yaml
# Proposed: /opt/stacks/ecosystem-graph/docker-compose.yml
services:
  ecosystem-graph:
    image: neo4j:5-community
    container_name: ecosystem-graph
    ports:
      - "127.0.0.1:7474:7474"   # HTTP
      - "127.0.0.1:7687:7687"   # Bolt
    environment:
      - NEO4J_AUTH=neo4j/${NEO4J_PASSWORD}
      - NEO4J_server_memory_heap_max__size=512m
      - NEO4J_server_memory_pagecache_size=256m
    volumes:
      - ./data:/data
      - ./import:/import
    mem_limit: 1g
    cpus: 1.0
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - DAC_OVERRIDE
      - SETGID
      - SETUID
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:7474 || exit 1"]
```

### 5.3 Population Strategy

```
Phase 1 — Static Import (CSV → Cypher):
  Load servers, containers, PM2 processes, repos, databases
  from the intelligence reports (one-time bulk import)

Phase 2 — Live Sync (Agent-driven):
  ecosystem-guardian agent polls Docker/PM2 every 60s
  → detects changes → upserts nodes/edges via Bolt driver

Phase 3 — Event-driven:
  event-bus-relay publishes change events
  → graph-sync worker consumes → updates graph in near-real-time
```

### 5.4 Integration Points

```
Ecosystem Guardian (PM2) → Bolt driver → Neo4j (write)
CEO Command Console → Cypher queries → Neo4j (read)
AI Decision Layer → Graph algorithms → Neo4j (analytics)
Observability Fusion → Cypher → Neo4j (topology context)
Self-Healing Framework → Dependency queries → Neo4j (blast radius)
```

---

## 6. Graph Algorithms for Intelligence

### 6.1 Centrality Analysis

```
Betweenness Centrality:
  → Identify bottleneck nodes (e.g., LiteLLM, COREDB PostgreSQL)
  → These are the "too important to fail" nodes

PageRank:
  → Identify most-connected services
  → These drive the most value but also the most risk
```

### 6.2 Community Detection

```
Louvain Algorithm:
  → Discover natural service clusters
  → Expected clusters: prediction-radar (14 nodes), monitoring (8 nodes),
    agents (12 nodes), core-db (5 nodes)
  → Validate that network boundaries align with functional boundaries
```

### 6.3 Path Finding

```
Shortest Path:
  → "How does voice-agent-svc reach Twilio?"
  → Shows all intermediate hops

All Shortest Paths:
  → "What are all the routes from external user to prediction-radar-app-db?"
  → Validates security layers (nginx → web → api → db)
```

### 6.4 Impact Analysis

```
k-hop neighborhood from failed node:
  → "What's affected if deepseek API is unreachable for 5 minutes?"
  → k=1: LiteLLM
  → k=2: All 9 PM2 agents
  → k=3: All external services those agents control
```

---

## 7. Visualization: Wheeler Topology Map

The graph data enables automatic topology visualization:

```
┌─────────────────────────────────────────────────────────┐
│                  WHEELER TOPOLOGY MAP                     │
│                                                          │
│   [AIOPS Server] ──RUNS_ON──> [40 Containers]           │
│        │                          │                      │
│        ├──HOSTS──> [17 PM2 Procs] │                      │
│        │              │           │                      │
│        │         [9 Agents]       ├──[14 prediction-radar]│
│        │         [4 APIs]         ├──[8 monitoring]      │
│        │         [4 Infra]        ├──[5 apps]            │
│        │                          ├──[3 databases]       │
│        │                          └──[10 other]          │
│        │                                                 │
│   [COREDB Server] ──RUNS_ON──> [19 Containers]          │
│        │                          │                      │
│        │                     [postgres]─USED_BY─> [6 services]
│        │                     [redis]───USED_BY──> [3 services]
│        │                     [minio]                   │
│        │                     [monitoring stack]        │
│                                                          │
│   Cross-server edges:                                    │
│     AIOPS ──CONNECTS_TO(5432)──> COREDB PostgreSQL      │
│     AIOPS ──CONNECTS_TO(6379)──> COREDB Redis            │
│     AIOPS ──PROXIES_TO──> COREDB Grafana (:3000)         │
└─────────────────────────────────────────────────────────┘
```

---

## 8. Graph Maintenance

### 8.1 Data Freshness Guarantees

| Entity Type | Sync Method | Max Staleness |
|-------------|-------------|---------------|
| Servers | Static + manual update | 24h |
| Docker Containers | ecosystem-guardian poll | 60s |
| PM2 Processes | ecosystem-guardian poll | 60s |
| Agent Status | PM2 jlist + health endpoint | 60s |
| Database Status | Prometheus metrics | 30s |
| Repository Info | Manual + git hook | 24h |
| Secrets | Manual (security boundary) | On rotation |

### 8.2 Garbage Collection

```
Stale node removal:
  - Container not seen for 24h → mark as "offline"
  - PM2 process not seen for 24h → mark as "stopped"
  - Agent not heartbeating for 1h → mark as "degraded"
  - Never auto-delete — keep history for forensic analysis
```

---

## 9. Query API

### 9.1 REST Endpoints (proposed)

```
GET  /api/v1/graph/topology          Full ecosystem topology
GET  /api/v1/graph/node/{type}/{id}  Single node with 1-hop neighbors
GET  /api/v1/graph/blast-radius/{id} k-hop dependency graph from node
GET  /api/v1/graph/spof              Single points of failure (dep > 5)
GET  /api/v1/graph/health            All unhealthy/stopped nodes
GET  /api/v1/graph/security          Security posture summary
GET  /api/v1/graph/dependencies/{id} Full dependency chain (upstream + downstream)
POST /api/v1/graph/query             Execute arbitrary Cypher (read-only, auth'd)
```

### 9.2 Access Control

```
Read-only queries: All dashboards, CEO console, AI decision layer
Write access: Only ecosystem-guardian and graph-sync worker
Admin: Cypher console behind nginx basic auth
```

---

*End of Ecosystem Graph Design*
