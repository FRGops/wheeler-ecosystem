# Wheeler Enterprise — Scaling Playbook

**Version:** 1.0.0 | **Last Updated:** 2026-05-23 | **Owner:** SRE Team
**Classification:** Internal — Operations

---

## 1. Capacity Planning Metrics

### 1.1 Key Metrics to Monitor

```
Metric                  Source            Warning           Critical          Action When Triggered
──────────────────────  ────────────────  ────────────────  ────────────────  ─────────────────────
CPU Utilization         Netdata/Prom      70% sustained     90% sustained     Scale vertically or add node
Memory Usage            Netdata/Prom      75% sustained     90% sustained     Increase RAM or optimize
Disk Usage              df / Prometheus   80% used          90% used          Add disk or clean up
Disk I/O Latency        Netdata           >50ms avg         >100ms avg        Move to faster storage
Network Throughput      Netdata           >700 Mbps          >900 Mbps         Add bandwidth or CDN
Docker Container Count  Docker            25 containers     30 containers     Cluster or split services
Open File Descriptors   Node Exporter     50k used          80k used          Tune ulimits, optimize
PostgreSQL Connections  PG Exporter       80% of max        95% of max        Add pgBouncer or read replica
Redis Memory            Redis Exporter    75% of maxmemory   90% of maxmemory  Eviction imminent, scale
Redis Connected Clients Redis Exporter    5k clients        8k clients        Consider Redis Cluster
LiteLLM RPM             LiteLLM metrics   >500 req/min      >1000 req/min     Rate limit or add provider
PM2 Restart Count       PM2 Exporter      >50 restarts/hr   >100 restarts/hr  Restart loop detected
Swap Usage              Netdata           >2GB used         >4GB used         Memory pressure, add RAM
```

### 1.2 Current Baseline (AIOPS CPX51)

```
Resource          Current Usage    Capacity      Headroom     Trend (30-day)
────────────────  ──────────────  ────────────  ───────────  ──────────────
CPU (16 cores)    25-40% avg      16 cores      60-75%        Stable
RAM (32 GB)       18-22 GB used   32 GB         10-14 GB      Slowly growing (+0.5 GB/week)
Disk (360 GB)     218 GB used     360 GB        142 GB        Growing (+5 GB/week)
Network (1 Gbps)  ~200 Mbps avg   1 Gbps        ~800 Mbps     Stable
Docker            22 containers   30 practical  8 headroom    Stable
PostgreSQL Conns  ~45 avg         200 max       155 headroom  Stable
Redis Memory      1.2 GB used     4 GB max      2.8 GB        Slow growth
LiteLLM RPM       ~200 req/min    N/A           N/A           Growing (+10%/week)
```

### 1.3 Growth Forecasting

```
Projected Resource Exhaustion (current trends):
  ├ Disk: 218 GB + 5 GB/week → 80% threshold (288 GB) in ~14 weeks
  ├ RAM:  22 GB + 0.5 GB/week → 75% threshold (24 GB) in ~4 weeks
  └ CPU:  well within limits for 12+ months

Recommended Actions:
  ├ Month 1: Configure swap (8 GB) as RAM safety valve
  ├ Month 2: Clean up old Docker images, logs, and backups (disk)
  ├ Month 3: Review if RAM upgrade needed (move to CPX61: 48 GB)
  └ Month 6: Evaluate horizontal scaling if traffic doubles
```

---

## 2. Vertical vs Horizontal Scaling — Decision Tree

```
                     ┌─────────────────────────────┐
                     │ What's the bottleneck?       │
                     └─────────────┬───────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
       Single service         Entire server          Network I/O
       is saturated          is saturated           is bottleneck
              │                    │                    │
              ▼                    ▼                    ▼
       ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
       │ Is it a      │    │ Is it RAM    │    │ Add CDN or   │
       │ database?    │    │ or CPU?      │    │ edge caching │
       └──┬───────┬───┘    └──┬───────┬───┘    └──────────────┘
          │       │           │       │
          ▼       ▼           ▼       ▼
        Yes      No         RAM      CPU
          │       │           │       │
          ▼       ▼           ▼       ▼
    ┌─────────┐ ┌──────┐ ┌───────┐ ┌──────────┐
    │Read     │ │Scale │ │Add    │ │Vertical: │
    │replica  │ │horiz │ │RAM    │ │More vCPU │
    │first    │ │(more │ │(bigger│ │(bigger   │
    │THEN     │ │nodes)│ │VPS or │ │VPS) OR   │
    │shard if │ │      │ │dedicat│ │Horizontal:│
    │needed   │ │      │ │ed RAM │ │more nodes │
    └─────────┘ └──────┘ └───────┘ └──────────┘

DECISION RULES:
────────────────
1. Always try vertical scaling FIRST (simpler, less risky)
2. Move to horizontal when:
   a. Vertical limit reached (max VPS tier)
   b. Single point of failure must be eliminated (HA requirement)
   c. Workload is stateless and naturally parallelizable
   d. Geographic distribution needed (multi-region latency)
3. Database scaling: read replicas BEFORE sharding
4. Redis scaling: Redis Sentinel BEFORE Redis Cluster
```

---

## 3. Vertical Scaling Procedures

### 3.1 Hetzner VPS Resize (AIOPS or COREDB)

```
 PRE-FLIGHT CHECKLIST:
 ─────────────────────
 [ ] Full backup completed and verified within last 24 hours
 [ ] Maintenance window approved (see Section 6 of deployment playbook)
 [ ] Team notified in #infra-notices at least 1 hour before
 [ ] Users notified via status page (if downtime > 5 min expected)
 [ ] DNS TTL lowered to 120s (if IP will change)

 PROCEDURE (5-10 min downtime):
 ─────────────────────────────
 1. SSH to server and prepare for shutdown:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Save PM2 process list                                    │
    │ pm2 save                                                  │
    │                                                           │
    │ # Gracefully stop all Docker containers                    │
    │ cd /root/infrastructure/aiops                            │
    │ for compose_dir in */; do                                │
    │   cd "$compose_dir" && docker compose stop               │
    │   cd ..                                                  │
    │ done                                                      │
    │                                                           │
    │ # Final sync (flush filesystem buffers)                   │
    │ sync                                                      │
    └─────────────────────────────────────────────────────────────┘

 2. Shut down the VPS:
    ┌─────────────────────────────────────────────────────────────┐
    │ shutdown -h now                                           │
    │ # OR from Hetzner Cloud Console: "Power Off"              │
    └─────────────────────────────────────────────────────────────┘

 3. Resize in Hetzner Cloud Console:
    ├ Navigate to server → Resize → Select new plan
    ├ Current: CPX51 (16 vCPU, 32 GB, 360 GB)
    ├ Options:
    │   ├ CPX61: 24 vCPU, 48 GB RAM, 480 GB NVMe  (~€80/mo)
    │   ├ CX52:  16 vCPU, 64 GB RAM, 360 GB NVMe   (~€60/mo) ← RAM-heavy
    │   └ CX62:  24 vCPU, 64 GB RAM, 480 GB NVMe   (~€100/mo)
    └ The disk and IP are PRESERVED during resize.

 4. Power on the VPS:
    ┌─────────────────────────────────────────────────────────────┐
    │ # From console, or it may auto-start after resize          │
    │ # Wait for server to boot (watch console if possible)     │
    └─────────────────────────────────────────────────────────────┘

 5. Verify and restart services:
    ┌─────────────────────────────────────────────────────────────┐
    │ # SSH in and verify system                                 │
    │ free -h                                                   │
    │ nproc                                                     │
    │ df -h /                                                   │
    │                                                           │
    │ # Restart Docker services                                 │
    │ for compose_dir in /root/infrastructure/aiops/*/; do     │
    │   cd "$compose_dir" && docker compose up -d              │
    │   cd ..                                                  │
    │ done                                                      │
    │                                                           │
    │ # Restart PM2 services                                   │
    │ pm2 resurrect                                             │
    │                                                           │
    │ # Verify all services                                     │
    │ bash /root/infrastructure/enterprise/phase4-healthcheck/healthcheck-all.sh │
    └─────────────────────────────────────────────────────────────┘

 6. Update resource limits:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Update Docker resource limits if they were absolute values│
    │ # Review sysctl settings for new RAM size                  │
    │ # Adjust PostgreSQL shared_buffers based on new RAM        │
    │ #   Rule of thumb: 25% of system RAM for PG              │
    │ #   32 GB → 8 GB shared_buffers                            │
    │ #   64 GB → 16 GB shared_buffers                           │
    │ # Adjust Redis maxmemory if needed                        │
    └─────────────────────────────────────────────────────────────┘

 POST-RESIZE VALIDATION:
 ───────────────────────
 [ ] All Docker containers healthy
 [ ] All PM2 processes online
 [ ] PostgreSQL accepting connections
 [ ] Redis responding to PING
 [ ] Public endpoints returning HTTP 200
 [ ] Monitoring scraping all targets
 [ ] SSL certificates valid
 [ ] Tailscale mesh fully connected
 [ ] System using new resources (check free, nproc)
```

### 3.2 Hostinger VPS Resize (EDGE)

```
 Similar to Hetzner procedure. Key differences:
 ────────────────────────────────────────────────────────────────────
 - Hostinger resize process may differ (check their docs)
 - EDGE is simpler: fewer services, less state
 - Primary concern: DNS propagation if IP changes
 - If IP changes: update Cloudflare A record, wait 5 min for propagation
 - Total downtime target: < 10 minutes
```

---

## 4. Horizontal Scaling: Adding a Second AIOPS Node

### 4.1 Architecture Target

```
Current:
  ┌─────────┐     ┌──────────┐     ┌──────────┐
  │  EDGE   │────▶│  AIOPS-1 │────▶│  COREDB  │
  └─────────┘     └──────────┘     └──────────┘

Target (2 AIOPS nodes):
  ┌─────────┐     ┌──────────┐
  │         │────▶│  AIOPS-1 │──┐
  │  EDGE   │     └──────────┘  │    ┌──────────┐
  │         │                   ├───▶│  COREDB  │
  │         │     ┌──────────┐  │    └──────────┘
  │         │────▶│  AIOPS-2 │──┘
  └─────────┘     └──────────┘
      │                │
      └── Round-robin ─┘  (Traefik load balancing)
```

### 4.2 Step-by-Step Procedure

```
 PRE-FLIGHT:
 ──────────
 [ ] COREDB is ready to serve both AIOPS nodes (already the plan)
 [ ] All stateful services moved to COREDB (databases, Redis, MinIO)
 [ ] Stateless services identified: API servers, workers, agents
 [ ] Load balancing strategy chosen: Traefik round-robin with sticky sessions

 STEP 1: PROVISION NEW AIOPS NODE (15 min)
 ─────────────────────────────────────────────────────────────────────
 1. Create new Hetzner CPX51 (or CPX61 if scaling up):
    - 16 vCPU, 32 GB RAM, 360 GB NVMe (CPX51)
    - Ubuntu 24.04 LTS
    - Same region as COREDB

 2. Apply role: `bash apply-server-hardening.sh aiops`

 3. Install Docker + Tailscale + Node/PM2:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl -fsSL https://get.docker.com | bash                 │
    │ curl -fsSL https://tailscale.com/install.sh | bash        │
    │ tailscale up --auth-key=<KEY> --hostname=aiops-2           │
    │ curl -fsSL https://deb.nodesource.com/setup_20.x | bash - │
    │ apt install -y nodejs && npm install -g pm2              │
    └─────────────────────────────────────────────────────────────┘

 4. Push infrastructure config:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Tag the config repo for this node                        │
    │ git tag aiops-2-deploy                                    │
    │ rsync -avz /root/infrastructure/ root@<AIOPS2_IP>:/root/   │
    └─────────────────────────────────────────────────────────────┘

 STEP 2: DEPLOY STATELESS SERVICES (15 min)
 ─────────────────────────────────────────────────────────────────────
 1. Deploy API services (these are stateless and can run on any node):
    ┌─────────────────────────────────────────────────────────────┐
    │ cd /root/infrastructure/aiops                             │
    │                                                           │
    │ # These services connect to COREDB for state               │
    │ cd prediction-radar && docker compose up -d api worker scheduler web │
    │ cd ../ravynai && docker compose up -d api worker          │
    │ cd ../ai-agents && docker compose up -d                   │
    │ cd ../analytics && docker compose up -d superset          │
    └─────────────────────────────────────────────────────────────┘

 2. Deploy PM2 services (these are also stateless):
    ┌─────────────────────────────────────────────────────────────┐
    │ # Deploy the same PM2 processes as aiops-1                 │
    │ # Configure DB connections to point to COREDB              │
    │ cd /root/infrastructure/aiops/pm2                         │
    │ # Edit ecosystem.config.js to connect to COREDB            │
    │ pm2 start ecosystem.config.js                             │
    │ pm2 save                                                  │
    └─────────────────────────────────────────────────────────────┘

 STEP 3: CONFIGURE LOAD BALANCING (10 min)
 ─────────────────────────────────────────────────────────────────────
 1. Update EDGE Traefik config to load balance between AIOPS nodes:
    ┌─────────────────────────────────────────────────────────────┐
    │ # On EDGE server, edit Traefik dynamic config              │
    │ # /root/infrastructure/edge/traefik/dynamic/routes.yml    │
    │                                                           │
    │ http:                                                     │
    │   services:                                               │
    │     prediction-radar:                                     │
    │       loadBalancer:                                       │
    │         servers:                                          │
    │           - url: "http://100.121.230.28:8098"              │ # AIOPS-1
    │           - url: "http://<AIOPS2_TAILSCALE_IP>:8098"       │ # AIOPS-2
    │         healthCheck:                                      │
    │           path: "/health"                                  │
    │           interval: "10s"                                  │
    │           timeout: "3s"                                    │
    └─────────────────────────────────────────────────────────────┘

 2. Apply the config:
    ┌─────────────────────────────────────────────────────────────┐
    │ docker cp /root/infrastructure/edge/traefik/dynamic/routes.yml \│
    │   traefik:/etc/traefik/dynamic/routes.yml                 │
    │ docker restart traefik                                    │
    └─────────────────────────────────────────────────────────────┘

 STEP 4: MONITOR AND VALIDATE (15 min)
 ─────────────────────────────────────────────────────────────────────
 1. Watch Traefik routing metrics:
    ┌─────────────────────────────────────────────────────────────┐
    │ curl http://localhost:8080/api/rawdata | jq '.services'   │
    └─────────────────────────────────────────────────────────────┘

 2. Verify requests reach both backends:
    ┌─────────────────────────────────────────────────────────────┐
    │ # From EDGE, make 10 requests and check which backend      │
    │ for i in $(seq 1 10); do                                 │
    │   curl -s https://predictionradar.wheeler.ai/health | \   │
    │     grep -o 'hostname.*'                                 │
    │ done                                                      │
    │ # Should see responses from both AIOPS-1 and AIOPS-2      │
    └─────────────────────────────────────────────────────────────┘

 3. Check resource usage on both nodes:
    ┌─────────────────────────────────────────────────────────────┐
    │ ssh aiops-1 "free -h; uptime; docker ps -q | wc -l"       │
    │ ssh aiops-2 "free -h; uptime; docker ps -q | wc -l"       │
    └─────────────────────────────────────────────────────────────┘

 POST-SCALE TASKS:
 ─────────────────
 [ ] Add aiops-2 to Prometheus scrape targets
 [ ] Add aiops-2 to Uptime Kuma monitoring
 [ ] Add aiops-2 to Grafana dashboards
 [ ] Verify backup strategy covers both nodes
 [ ] Update documentation and infra-map
 [ ] Update DR runbook with aiops-2
```

---

## 5. Database Scaling

### 5.1 Read Replicas (PostgreSQL)

```
 WHEN TO ADD A READ REPLICA:
 ───────────────────────────
 [ ] Read query latency > 100ms P95 consistently
 [ ] Write throughput fine but reads saturating CPU
 [ ] Reporting/analytics queries impacting OLTP performance
 [ ] Connection count near max_connections limit
 [ ] Need HA (hot standby for failover)

 SETUP PROCEDURE:
 ───────────────
 1. On primary (AIOPS-1 or COREDB):
    ┌─────────────────────────────────────────────────────────────┐
    │ # Enable replication                                       │
    │ ALTER SYSTEM SET wal_level = replica;                     │
    │ ALTER SYSTEM SET max_wal_senders = 5;                    │
    │ ALTER SYSTEM SET wal_keep_size = '4GB';                   │
    │ SELECT pg_reload_conf();                                 │
    │                                                           │
    │ # Create replication user                                 │
    │ CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'xxx'; │
    │ # Add to pg_hba.conf:                                    │
    │ # host replication replicator <REPLICA_IP>/32 md5        │
    └─────────────────────────────────────────────────────────────┘

 2. On replica server:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Take base backup                                         │
    │ pg_basebackup -h <PRIMARY_IP> -U replicator \             │
    │   -D /var/lib/postgresql/data -P -R -X stream            │
    │                                                           │
    │ # Start PostgreSQL (will enter recovery mode)              │
    │ systemctl start postgresql                                │
    │                                                           │
    │ # Verify replication                                       │
    │ docker exec postgres-replica psql -U postgres \           │
    │   -c "SELECT status, replay_lag FROM pg_stat_replication;"│
    └─────────────────────────────────────────────────────────────┘

 3. Update application config to split reads/writes:
    - Reads → Replica
    - Writes → Primary
    - Use pgBouncer to route automatically (see 5.2)

 WHEN TO SHARD:
 ─────────────
 Sharding is a LAST RESORT. Only consider when:
 [ ] Single database > 500 GB
 [ ] Write throughput > 10,000 TPS sustained
 [ ] Read replicas no longer help (write-bound)
 [ ] Multi-tenancy with natural partitioning key (tenant_id)

 Current Wheeler state: NO SHARDING NEEDED
 (Largest DB is ~50 GB, write throughput is ~200 TPS)
```

### 5.2 Connection Pooling with pgBouncer

```
 WHEN TO ADD PGBOUNCER:
 ──────────────────────
 [ ] PostgreSQL connections > 100 frequently
 [ ] Multiple services each opening their own connection pools
 [ ] Connection churn visible in pg_stat_activity (many connect/disconnect)

 DEPLOYMENT:
 ───────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # docker-compose.yml fragment                               │
 │ pgbouncer:                                                 │
 │   image: edoburu/pgbouncer:latest                           │
 │   environment:                                             │
 │     DB_HOST: <COREDB_TAILSCALE_IP>                          │
 │     DB_PORT: 5432                                          │
 │     DB_USER: postgres                                      │
 │     DB_PASSWORD: ${PG_PASSWORD}                            │
 │     POOL_MODE: transaction                                 │
 │     MAX_CLIENT_CONN: 200                                   │
 │     DEFAULT_POOL_SIZE: 25                                  │
 │     RESERVE_POOL_SIZE: 5                                   │
 │   ports:                                                   │
 │     - "6432:6432"                                          │
 └─────────────────────────────────────────────────────────────┘

 CONFIGURATION:
 ──────────────
 Pool mode: transaction (best for web apps, connections released after tx)
 Pool size: 25 per database (25 * 5 DBs = 125 to PostgreSQL, well under 200 max)
 Max clients: 200 (applications can open 200 connections to pgBouncer,
                    pgBouncer multiplexes to 25 real connections)

 Application changes:
   Change DATABASE_URL from:
     postgresql://user:pass@coredb:5432/db
   To:
     postgresql://user:pass@pgbouncer:6432/db
```

---

## 6. Redis Scaling

### 6.1 Capacity Planning

```
Redis Memory Usage Thresholds:
  ├ < 50%: Healthy, no action needed
  ├ 50-70%: Monitor, plan for growth
  ├ 70-85%: Set maxmemory-policy, consider scaling
  └ > 85%: IMMINENT EVICTION — scale immediately

Current AIOPS Redis: 1.2 GB used of 4 GB maxmemory (30%)
Current COREDB Redis: capacity TBD after provisioning
```

### 6.2 Redis Sentinel (High Availability)

```
 USE SENTINEL WHEN:
 ──────────────────
 [ ] Redis is a single point of failure for critical services
 [ ] Need automatic failover without operator intervention
 [ ] Can tolerate a few seconds of downtime during failover
 [ ] Have at least 3 nodes (1 primary + 2 replicas minimum)

 ARCHITECTURE:
 ────────────
 ┌────────────┐  ┌────────────┐  ┌────────────┐
 │  Sentinel 1 │  │  Sentinel 2 │  │  Sentinel 3 │
 │  (AIOPS-1)  │  │  (AIOPS-2)  │  │  (EDGE)    │
 └─────┬──────┘  └─────┬──────┘  └─────┬──────┘
       │               │               │
       └───────────────┼───────────────┘
                       │  (monitoring + election)
       ┌───────────────┼───────────────┐
       │               │               │
  ┌────┴─────┐   ┌─────┴────┐   ┌─────┴────┐
  │ Redis    │   │ Redis    │   │ Redis    │
  │ Primary  │──▶│ Replica 1│   │ Replica 2│
  │ (AIOPS-1)│   │ (AIOPS-2)│   │ (COREDB) │
  └──────────┘   └──────────┘   └──────────┘
       │
       └── replication (async) ──┘

 DEPLOYMENT STATUS: NOT YET IMPLEMENTED
 Target: Phase 4 (6-12 months)
```

### 6.3 Redis Cluster (Sharding)

```
 USE CLUSTER WHEN:
 ─────────────────
 [ ] Dataset > available RAM on single node
 [ ] Write throughput > single-node Redis capacity (~100k ops/sec)
 [ ] Need horizontal write scaling
 [ ] Can tolerate Cluster's limitations:
     ├ Multi-key operations only work within same hash slot
     ├ No SELECT (only DB 0)
     └ Client libraries must support Cluster protocol

 WHEN TO CHOOSE SENTINEL vs CLUSTER:
 ──────────────────────────────────
                                  Sentinel         Cluster
 Need automatic failover         YES             YES
 Dataset fits in single node     YES             N/A (overkill)
 Multi-key operations needed     YES             Limited (hash tags)
 Write scaling needed            NO              YES
 Operational complexity          Low             Medium-High

 Current Wheeler state: SENTINEL is the right choice
 (Dataset < 4 GB, fits in single node, HA is the primary need)
```

---

## 7. AI Workload Scaling

### 7.1 GPU Node Integration

```
 PLANNING PHASE:
 ──────────────
 Determine if GPU is needed:
 [ ] Are external API costs > €1,000/month?     → GPU may save money
 [ ] Is latency to external APIs > 2s for P95?   → GPU reduces latency
 [ ] Do you need data sovereignty?               → GPU keeps data on-prem
 [ ] Do you need model fine-tuning?              → GPU required for training

 GPU Node Spec Options (Hetzner):
 ─────────────────────────────────
 Option A: Dedicated GPU Server
   ├ 1x NVIDIA L40S (48 GB VRAM) → can run Llama-3-70B, Mixtral-8x22B
   ├ €500-800/month
   └ Best for: self-hosted LLM inference at scale

 Option B: Cloud GPU (RunPod / Lambda Labs)
   ├ On-demand GPU rental
   ├ €0.50-2.00/hour for A100/H100
   └ Best for: burst workloads, testing before committing

 Integration with LiteLLM:
 ───────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Add GPU node as a provider in LiteLLM config              │
 │ litellm_settings:                                          │
 │   router_settings:                                         │
 │     routing_strategy: "latency-based-routing"               │
 │                                                           │
 │ model_list:                                               │
 │   - model_name: "llama-3-70b"                              │
 │     litellm_params:                                       │
 │       model: "openai/llama-3-70b"                          │
 │       api_base: "http://<GPU_NODE_TAILSCALE_IP>:8000/v1"   │
 │       api_key: "not-needed"                               │
 │       rpm: 1000                                           │
 │     model_info:                                           │
 │       mode: "chat"                                        │
 │       max_tokens: 4096                                    │
 └─────────────────────────────────────────────────────────────┘

 Fallback configuration:
 ┌─────────────────────────────────────────────────────────────┐
 │ # If GPU is overloaded, fall back to external APIs          │
 │ router_settings:                                           │
 │   fallbacks:                                               │
 │     - "llama-3-70b": ["claude-haiku-4.5"]                   │
 │   allowed_fails: 3                                         │
 └─────────────────────────────────────────────────────────────┘
```

### 7.2 Request Queueing for AI Workloads

```
 PROBLEM: AI model inference is expensive and slow.
          Without queueing, burst traffic can overwhelm providers,
          cause rate limiting, and skyrocket costs.

 SOLUTION: Add a message queue for AI requests with backpressure.

 ARCHITECTURE:
 ────────────
 ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
 │  Client  │────▶│  API     │────▶│   NATS   │────▶│  Worker  │
 │          │     │  Accept  │     │  Queue   │     │  Process │
 │          │     │  202 OK  │     │          │     │  + LLM   │
 └──────────┘     └──────────┘     └──────────┘     └──────────┘
                                                          │
                                                    ┌─────┴─────┐
                                                    │  LiteLLM  │
                                                    │  Router   │
                                                    └───────────┘

 This enables:
  ├ Priority queues (real-time vs batch)
  ├ Rate limiting per queue
  ├ Cost control (reject queue if budget exceeded)
  ├ Retry logic with exponential backoff
  └ Visibility into queue depth as scaling metric

 CONFIGURATION (future enhancement):
 ──────────────────────────────────
 Queue: "ai-requests" (NATS JetStream)
 Max queue depth: 1000
 Warning threshold: 500 → scale workers
 Critical threshold: 900 → reject new requests (429)
 Worker pool: auto-scale 2-10 workers based on queue depth
```

---

## 8. Monitoring During Scale Events

### 8.1 Grafana Dashboard Panels to Watch

```
Scale Event: Vertical Resize
─────────────────────────────
  Watch these panels:
  ├ CPU Utilization (per core) — verify new cores visible
  ├ Memory Usage — verify new RAM recognized and available
  ├ Disk I/O Wait — should not change significantly
  ├ Docker Container Health — all containers should be up
  └ PostgreSQL Buffer Cache Hit Ratio — should improve with more RAM

Scale Event: Adding AIOPS Node
────────────────────────────────
  Watch these panels:
  ├ Traefik Request Rate by Backend — verify traffic split
  ├ Traefik Backend Response Time — compare old vs new node
  ├ Traefik 5xx Rate — ensure no routing errors
  ├ Node CPU/Memory (per-node comparison)
  └ Application Error Rate — ensure no regressions

Scale Event: Database Read Replica
───────────────────────────────────
  Watch these panels:
  ├ PostgreSQL Replication Lag (bytes + seconds) — must stay < 1s
  ├ PostgreSQL Connections (primary vs replica)
  ├ Query Latency P95 (primary vs replica comparison)
  └ Replica Server Resource Usage (CPU, RAM, Disk)

Scale Event: GPU Node Addition
─────────────────────────────────
  Watch these panels:
  ├ LiteLLM Latency by Model — should decrease for GPU-served models
  ├ LiteLLM Cost per Request — GPU-served should be cheaper
  ├ GPU Utilization (nvidia-smi metrics)
  ├ GPU Memory Usage
  └ LiteLLM Request Count by Provider (GPU vs API)
```

### 8.2 Alert Suppression During Planned Scaling

```
 Before starting any scale event:
 ┌─────────────────────────────────────────────────────────────┐
 │ # Add a silence in Alertmanager (prevents false alerts)     │
 │ curl -X POST http://localhost:9093/api/v2/silences \       │
 │   -H "Content-Type: application/json" \                    │
 │   -d '{                                                     │
 │     "matchers": [                                          │
 │       {"name": "server", "value": "aiops-1", "isRegex": false} │
 │     ],                                                      │
 │     "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S)'",        │
 │     "endsAt": "'$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%S)'", │
 │     "createdBy": "SRE Scale Event",                        │
 │     "comment": "Planned vertical scaling of AIOPS-1"       │
 │   }'                                                        │
 └─────────────────────────────────────────────────────────────┘

 REMOVE the silence after the scale event is complete and validated.
```

---

## 9. Scale-Down Procedure

### 9.1 Draining a Node

```
 USE CASE: Removing an AIOPS node for maintenance, cost reduction,
           or replacing with a larger node.

 PROCEDURE:
 ─────────
 1. Mark node as draining (in Traefik):
    ┌─────────────────────────────────────────────────────────────┐
    │ # In Traefik dynamic config, set the server weight to 0     │
    │ # This stops new connections but allows existing to finish │
    │                                                           │
    │ servers:                                                  │
    │   - url: "http://<NODE_TO_REMOVE_IP>:8098"                 │
    │     weight: 0                                             │
    └─────────────────────────────────────────────────────────────┘

 2. Wait for active connections to drain:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Watch connection count decrease                          │
    │ watch -n 5 'docker exec postgres-aio-main psql -U postgres \│
    │   -t -c "SELECT count(*) FROM pg_stat_activity;"'         │
    └─────────────────────────────────────────────────────────────┘

 3. Gracefully stop services:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Stop PM2 (signal workers to finish current tasks)        │
    │ pm2 stop all                                              │
    │                                                           │
    │ # Stop Docker containers gracefully                        │
    │ for dir in /root/infrastructure/aiops/*/; do \             │
    │   cd "$dir" && docker compose stop; cd ..; done          │
    └─────────────────────────────────────────────────────────────┘

 4. Final state check:
    ┌─────────────────────────────────────────────────────────────┐
    │ # Verify no processes using important ports                 │
    │ ss -tlnp | grep -E ':(8000|8007|8098|8088|9090)'          │
    │                                                           │
    │ # Verify no active connections to databases                │
    │ ss -tn | grep -E ':(5432|6379)'                            │
    └─────────────────────────────────────────────────────────────┘

 5. Remove from load balancer:
    - Remove the server entry from Traefik config
    - Restart Traefik

 6. Remove from monitoring:
    - Remove from Prometheus scrape targets
    - Remove from Uptime Kuma monitors
    - Remove from Grafana dashboards

 7. Shut down server (or repurpose):
    ┌─────────────────────────────────────────────────────────────┐
    │ shutdown -h now                                           │
    └─────────────────────────────────────────────────────────────┘
```

---

## 10. Load Testing Methodology

### 10.1 k6 Load Test Setup

```
 INSTALLATION:
 ────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ # Install k6 on your workstation or a dedicated test node   │
 │ curl -fsSL https://dl.k6.io/install.sh | bash              │
 └─────────────────────────────────────────────────────────────┘

 TEST SCRIPT TEMPLATE (load-test.js):
 ────────────────────────────────────
 ┌─────────────────────────────────────────────────────────────┐
 │ import http from 'k6/http';                                 │
 │ import { check, sleep } from 'k6';                          │
 │                                                           │
 │ export const options = {                                   │
 │   stages: [                                                │
 │     { duration: '2m', target: 50 },   // Ramp to 50 users  │
 │     { duration: '5m', target: 50 },   // Stay at 50        │
 │     { duration: '2m', target: 100 },  // Ramp to 100       │
 │     { duration: '5m', target: 100 },  // Stay at 100       │
 │     { duration: '2m', target: 200 },  // Ramp to 200       │
 │     { duration: '5m', target: 200 },  // Stay at 200       │
 │     { duration: '2m', target: 0 },     // Ramp down         │
 │   ],                                                       │
 │   thresholds: {                                            │
 │     http_req_duration: ['p(95)<2000'],  // P95 < 2s        │
 │     http_req_failed: ['rate<0.01'],      // Error rate < 1% │
 │   },                                                       │
 │ };                                                         │
 │                                                           │
 │ export default function () {                               │
 │   const endpoints = [                                      │
 │     'https://predictionradar.wheeler.ai/health',            │
 │     'https://ravynai.wheeler.ai/health',                   │
 │     'https://superset.wheeler.ai/health',                  │
 │   ];                                                       │
 │                                                           │
 │   for (const url of endpoints) {                           │
 │     const res = http.get(url);                             │
 │     check(res, {                                           │
 │       'status is 200': (r) => r.status === 200,            │
 │       'response time < 1s': (r) => r.timings.duration < 1000, │
 │     });                                                    │
 │   }                                                        │
 │                                                           │
 │   sleep(1);                                                │
 │ }                                                          │
 └─────────────────────────────────────────────────────────────┘

 RUN:
 ┌─────────────────────────────────────────────────────────────┐
 │ k6 run load-test.js --out json=results.json                │
 │                                                           │
 │ # During the test, watch Grafana:                          │
 │ #   - Traefik dashboard (request rate, latency, errors)    │
 │ #   - Node dashboard (CPU, RAM, network)                   │
 │ #   - PostgreSQL dashboard (connections, query latency)     │
 │ #   - Redis dashboard (hit rate, memory)                   │
 └─────────────────────────────────────────────────────────────┘
```

### 10.2 Key Metrics to Measure

```
Metric                       Baseline (Prod)    Target Under Load    Action If Exceeded
────────────────────────────  ─────────────────  ───────────────────  ─────────────────
HTTP P95 latency             < 500ms            < 2000ms             Scale horizontally
HTTP error rate              < 0.1%             < 1%                 Investigate root cause
PostgreSQL query P95         < 50ms             < 200ms              Add read replica
Redis hit rate               > 95%              > 90%                Increase Redis memory
CPU utilization (avg)        < 50%              < 85%                Scale vertically
Memory utilization           < 75%              < 90%                Add RAM or optimize
Network throughput           < 500 Mbps         < 900 Mbps            Add bandwidth
Docker restart count         0                  < 3                  Fix unstable service
LiteLLM error rate           < 0.5%             < 2%                 Add fallback provider
```

---

## 11. Cost Optimization

### 11.1 Right-Sizing Analysis

```
Current Monthly Infrastructure Costs (Estimated):
  ├ Hetzner CPX51 (AIOPS):       ~€50/month
  ├ Hetzner CX32 (COREDB):        ~€15/month
  └ Hostinger VPS (EDGE):        ~€15/month
  ──────────────────────────────────────────
  Total Server:                   ~€80/month

  AI API Costs (variable):
  ├ DeepSeek: ~€200/month (primary, cheapest)
  ├ Anthropic: ~€150/month (fallback, complex tasks)
  ├ OpenAI: ~€100/month (embeddings, TTS, fallback)
  ──────────────────────────────────────────
  Total AI:                       ~€450/month

  Other:
  ├ Cloudflare (Free tier):      €0/month
  ├ Tailscale (Free tier):       €0/month
  ├ SendGrid (Free tier):        €0/month
  ──────────────────────────────────────────
  Grand Total:                    ~€530/month
```

### 11.2 Optimization Opportunities

```
Immediate (next 30 days):
  [ ] Route 80% of non-critical AI traffic through DeepSeek (cheapest)
  [ ] Set LiteLLM budget alerts per team/department
  [ ] Enable LiteLLM caching (cache TTL: 1 hour for common prompts)
  [ ] Remove unused Docker images (docker system prune -a)
  ├ Estimated savings: €50-100/month

Short-term (1-3 months):
  [ ] Implement AI request queueing (batch non-urgent requests)
  [ ] Evaluate if GPU node would reduce API costs (see break-even analysis)
  [ ] Right-size EDGE: if utilization is < 30%, downgrade VPS tier
  [ ] Move COREDB to reserved instance (Hetzner doesn't offer, but negotiate)
  ├ Estimated savings: €100-150/month

Medium-term (3-6 months):
  [ ] Self-host embeddings model (bge-large-en on GPU) — avoid OpenAI embedding costs
  [ ] Implement model distillation (use smaller models where quality allows)
  [ ] Tiered storage: move old logs/backups to cold storage (Hetzner Storage Box)
  ├ Estimated savings: €150-200/month

GPU Break-Even Analysis:
─────────────────────────
GPU node cost (Hetzner): ~€400/month
External API at scale: ~€800/month (projected with growth)
Break-even: ~200K tokens/day routed through GPU instead of external APIs
Savings beyond break-even: ~€400/month

Decision: Deploy GPU node when external API spend exceeds €600/month
          (provides clear ROI with buffer)
```

### 11.3 Budget Alerting

```
 Daily AI Spend Budget Alerts (via LiteLLM + Prometheus):
 ────────────────────────────────────────────────────────────────────
 Alert Name: AIDailySpendExceeded
 Condition: sum(litellm_spend_total) by (team) > budget_per_team
 Severity: WARNING at 80%, CRITICAL at 100%

 Team Budgets (daily):
  ├ FRG CRM:        €15/day
  ├ InsForge:        €10/day
  ├ SurplusAI:       €8/day
  ├ Prediction:      €5/day
  └ Infrastructure:  €2/day (internal)
  ──────────────────────────────────
  Total Daily Cap:  €40/day (~€1,200/month)

 Anomaly Detection:
  If spend increases > 50% hour-over-hour → WARNING
  If spend increases > 100% hour-over-hour → CRITICAL (auto-block if confirmed)
```

---

## Document Control

| Version | Date       | Author   | Changes                    |
|---------|------------|----------|----------------------------|
| 1.0.0   | 2026-05-23 | SRE Team | Initial scaling playbook   |

**Next Review:** 2026-08-23
