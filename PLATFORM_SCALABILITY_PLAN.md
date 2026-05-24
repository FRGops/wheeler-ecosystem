# Wheeler Platform Scalability Plan

**Version:** 1.0
**Last Updated:** 2026-05-24
**Classification:** INTERNAL -- Infrastructure Strategy
**Based On:** Current 3-node architecture (AIOPS, COREDB, EDGE) with real utilization data

---

## Table of Contents

1. Executive Summary
2. Current Capacity Baseline
3. Scaling Triggers and Thresholds
4. Horizontal Scaling Plan
5. Database Scaling
6. Multi-Tenant Scaling
7. Network Scaling
8. Agent Fleet Scaling
9. Monitoring and Observability at Scale
10. Deployment and Rollback at Scale
11. Cost Model
12. Rollback Capability for Every Scaling Decision
13. Risk Register
14. Implementation Roadmap

---

## 1. Executive Summary

The Wheeler ecosystem currently operates on a 3-node architecture (2 Hetzner, 1 Hostinger) supporting 41 Docker containers, 20 PM2 processes, 12 AI agent services, and 6 database instances. Current utilization sits at approximately 20% CPU, 50% RAM, and 18% disk across the primary nodes, providing substantial headroom for near-term growth.

This document defines the scalability architecture from the current 3-node topology through multi-region enterprise scale. Every scaling decision is grounded in real current utilization data, follows the Verify-Act-Verify pattern, and preserves rollback capability at every phase.

The scaling strategy follows five phases:

| Phase | Timeframe | Architecture | Nodes | Max Tenants |
|-------|-----------|-------------|-------|-------------|
| Phase 1 | Current | Single-node Docker + PM2 | 3 (2 active) | 1-3 |
| Phase 2 | 0-3 months | Optimized single-node | 3 | 3-10 |
| Phase 3 | 3-6 months | Worker node offload | 4 | 10-25 |
| Phase 4 | 6-12 months | Docker Swarm + DB replicas | 4-6 | 25-100 |
| Phase 5 | 12+ months | k3s Kubernetes + multi-region | 8+ | 100-500+ |

---

## 2. Current Capacity Baseline

### 2.1 Physical Node Specifications

#### AIOPS Node (Hetzner CPX51)
| Attribute | Value |
|-----------|-------|
| Hostname | wheeler-aiops-01 |
| Tailscale IP | 100.121.230.28 |
| Public IP | 5.78.140.118 |
| Spec | 16 vCPU, 32 GB RAM, 360 GB NVMe, 1 Gbps |
| Role | Application server -- Docker, PM2, AI agents, Nginx gateway, monitoring, analytics |
| Docker Containers | 37 |
| PM2 Processes | 20 |
| Nginx Virtual Hosts | 17 |
| Compose Stacks | 12 |

#### COREDB Node (Hetzner)
| Attribute | Value |
|-----------|-------|
| Hostname | wheeler-core-db-01 |
| Tailscale IP | 100.118.166.117 |
| Public IP | 5.78.210.123 |
| Spec | 16 vCPU, 32 GB RAM, 360 GB NVMe |
| Role | Database server -- PostgreSQL primary, Redis, MinIO, Temporal |
| Access | UFW tailscale0-only (no public ports) |
| Services | PostgreSQL (4 databases), Redis, MinIO, Temporal, Prometheus/Grafana/Loki |

#### EDGE Node (Hostinger VPS)
| Attribute | Value |
|-----------|-------|
| Tailscale IP | 100.98.163.17 |
| Spec | Shared VPS (limited capacity) |
| Role | Legacy edge gateway -- being decommissioned for AI workload |
| Status | Traefik routes remaining; services migrating to AIOPS |

### 2.2 Current Utilization

| Metric | AIOPS | COREDB | EDGE | Aggregate |
|--------|-------|--------|------|-----------|
| CPU | ~20% | ~15% | ~10% | ~18% |
| RAM | 15 GB / 32 GB (47%) | 12 GB / 32 GB (38%) | 2 GB / 8 GB (25%) | ~42% |
| Disk | 61 GB / 360 GB (17%) | 45 GB / 360 GB (13%) | 20 GB / 80 GB (25%) | ~18% |
| Network | ~50 Mbps avg | ~20 Mbps avg | ~10 Mbps avg | -- |
| Docker Containers | 37 | 4 | 6 | 47 total |
| PM2 Processes | 20 | 0 | 0 | 20 total |

**Key observations:**
- AIOPS has 17 GB RAM headroom and 299 GB disk headroom
- COREDB has 20 GB RAM headroom and 315 GB disk headroom
- Both primary nodes are significantly underutilized, providing room for 2-3x growth without hardware changes
- EDGE node is resource-constrained and should not receive new workloads

### 2.3 Largest Service Footprints

| Service | Type | RAM | vCPU Limit | Disk | Notes |
|---------|------|-----|------------|------|-------|
| LiteLLM | PM2 | 377 MB | 2.0 | 500 MB | LLM proxy, traffic-dependent growth |
| FRGCRM API | PM2 | 235 MB | 1.0 | 200 MB | Core API, synchronous workload |
| FRGCRM Agent | PM2 | 94 MB | 0.5 | 100 MB | Background agent processing |
| SurplusAI Scraper | PM2 | 108 MB | 0.5 | 150 MB | Data acquisition, memory-spiky |
| SurplusAI Portal API | PM2 | 103 MB | 0.5 | 100 MB | Portal backend |
| Prediction Radar API | Docker | 256 MB | 1.0 | 2 GB | Container, data-heavy |
| aiops-clickhouse | Docker | 1.2 GB | 2.0 | 20 GB | Largest memory consumer |
| aiops-grafana | Docker | 256 MB | 0.5 | 5 GB | Dashboard, scales with queries |
| aiops-prometheus | Docker | 512 MB | 1.0 | 15 GB | Metrics, scales with targets |
| ecosystem-graph (Neo4j) | Docker | 512 MB | 1.0 | 10 GB | Graph DB, scales with relationships |

**Hottest paths (most frequently hit services):**
1. LiteLLM proxy (all agent LLM calls route through it)
2. FRGCRM API (primary CRM backend)
3. COREDB PostgreSQL (all database-backed services)
4. Nginx gateway (all external traffic)
5. Event bus relay (all inter-agent communication)

### 2.4 Database Current State

| Database | Engine | Location | Size | Growth Rate | Connections |
|----------|--------|----------|------|-------------|-------------|
| prediction_radar | PostgreSQL 16 | AIOPS | 2 GB | ~200 MB/month | 12 |
| frgcrm (frgops-standby) | PostgreSQL 16 | AIOPS | 500 MB | ~100 MB/month | 6 |
| ravynai | PostgreSQL 16 (PostGIS) | AIOPS | 300 MB | ~50 MB/month | 4 |
| wheeler_core | PostgreSQL | COREDB | 1 GB | ~150 MB/month | 8 |
| frgcrm (COREDB) | PostgreSQL | COREDB | 1.5 GB | ~200 MB/month | 6 |
| usesend | PostgreSQL | COREDB | 200 MB | ~30 MB/month | 3 |
| temporal | PostgreSQL | COREDB | 500 MB | ~80 MB/month | 5 |
| aiops-clickhouse | ClickHouse | AIOPS | 10 GB | ~2 GB/month | 4 |
| ecosystem-graph | Neo4j | AIOPS | 2 GB | ~200 MB/month | 3 |

**Connection pool status:** No connection pooling is currently configured. Each service maintains direct PostgreSQL connections. At current scale this is manageable (~48 total connections across all databases), but connection exhaustion becomes a risk beyond 15 simultaneous services.

### 2.5 PM2 Restart Metrics

| Process | Restarts (24h) | Status | Notes |
|---------|----------------|--------|-------|
| frgcrm-api | 0 | ONLINE | Stable |
| frgcrm-agent-svc | 0 | ONLINE | Stable |
| surplusai-portal-api | 0 | ONLINE | Stable |
| surplusai-scraper-agent-svc | 0 (post-fix) | ONLINE | History of 282+ restarts, stabilized |
| prediction-radar-agent-svc | 0 | ONLINE | Stable |
| ravyn-agent-svc | 0 | ONLINE | Stable |
| horizon-agent-svc | 0 | ONLINE | Stable |
| voice-agent-svc | 0 (post-fix) | ONLINE | History of uncontrolled restarts, stabilized |
| voice-outreach-service | 0 | ONLINE | Stable |
| insforge-agent-svc | 0 | ONLINE | Stable |
| paperless-agent-svc | 0 | ONLINE | Stable |
| design-agent-svc | 2 | ONLINE | Elevated but stable |
| litellm | 0 | ONLINE | Stable |
| ecosystem-guardian | 0 | ONLINE | Stable |
| event-bus-relay | 0 | ONLINE | Stable |
| war-room-server | 0 | ONLINE | Stable |
| command-center | 0 | ONLINE | Stable |
| openclaw-dashboard | 0 | ONLINE | Stable |

**Restart loop detection threshold:** Any process exceeding 5 restarts in 60 seconds triggers auto-rollback per deployment engine policy. Processes with persistent restart loops (>10/hour) trigger incident response.

---

## 3. Scaling Triggers and Thresholds

### 3.1 Automatic Scaling Triggers

Each trigger has a defined threshold, measurement method, and escalation path. Triggers are monitored by the existing Prometheus/Alertmanager stack.

| Trigger | Threshold | Measurement | Severity | Response Time |
|---------|-----------|-------------|----------|---------------|
| CPU sustained high | >70% for 5 min | node_cpu_seconds_total | WARNING | 5 min |
| CPU critical | >85% for 2 min | node_cpu_seconds_total | CRITICAL | Immediate |
| RAM usage high | >80% | node_memory_MemTotal_bytes | WARNING | 5 min |
| RAM critical | >90% | node_memory_MemTotal_bytes | CRITICAL | Immediate |
| Disk usage high | >80% | node_filesystem_avail_bytes | WARNING | 15 min |
| Disk critical | >90% | node_filesystem_avail_bytes | CRITICAL | 5 min |
| Disk inode exhaustion | >90% | node_filesystem_files_free | WARNING | 15 min |
| API p95 latency high | >500ms for 5 min | prometheus_http_request_duration_seconds | WARNING | 5 min |
| API p95 latency critical | >1000ms for 2 min | prometheus_http_request_duration_seconds | CRITICAL | Immediate |
| PM2 restart loop | >5 restarts in 60s | pm2_jlist | CRITICAL | Immediate |
| DB connection pool >80% | >80% max_connections | pg_stat_database | WARNING | 5 min |
| DB connection pool exhausted | 100% max_connections | pg_stat_database | CRITICAL | Immediate |
| DB replication lag | >30s | pg_stat_replication | WARNING | 5 min |
| Redis memory | >80% maxmemory | redis_memory_used_bytes | WARNING | 5 min |
| Redis hit rate drop | <80% | redis_keyspace_hits_total | WARNING | 15 min |
| Nginx connection pool | >80% worker_connections | nginx_connections_active | WARNING | 5 min |
| Docker restart loop | >3 restarts in 60s | docker_state_restart_count | CRITICAL | Immediate |
| LiteLLM request queue | >100 pending | litellm_queue_depth | WARNING | 5 min |
| SSL certificate expiry | <14 days | cert_expiry_days | WARNING | Daily check |

### 3.2 Scaling Decision Matrix

| Scenario | Action | Authority Level | Rollback |
|----------|--------|-----------------|----------|
| CPU >70% sustained | Add worker node or redistribute containers | Level 2 (Supervised) | Remove node |
| RAM >80% | Increase container memory limits or add node | Level 2 (Supervised) | Revert limits |
| Disk >80% | Add volume or clean old data | Level 1 (Assisted) | Restore from backup |
| API latency >500ms | Add API replicas behind load balancer | Level 2 (Supervised) | Remove replicas |
| PM2 restart loop | env -i delete+start with new env | Level 2 (Supervised) | Restore previous PM2 dump |
| DB pool exhaustion | Add PgBouncer or increase max_connections | Level 1 (Assisted) | Revert config |
| Redis OOM | Increase maxmemory or add Redis node | Level 1 (Assisted) | Revert config |
| Agent queue backlog | Add worker processes | Level 3 (Autonomous) | Scale down workers |
| Tenant count >10 | Migrate to per-tenant DB schemas | Level 1 (Assisted) | Revert to shared schema |

### 3.3 Cost of Delay

Understanding the cost of NOT scaling is essential for prioritization:

| If Not Scaled | Impact | Revenue at Risk | Time to Critical |
|---------------|--------|-----------------|------------------|
| CPU exhaustion | All services degrade, request queuing | Full revenue stop | 60-90 days at current growth |
| RAM exhaustion | OOM kills, cascading service failure | Full revenue stop | 90-120 days |
| Disk exhaustion | Database write failures, data loss | Full revenue stop | 180+ days |
| DB pool exhaustion | Application errors, lost transactions | Full revenue stop | 12-18 months |
| Network bandwidth | Latency increases, timeouts | Partial degradation | 12+ months |
| API latency >1s | User abandonment, lost subscriptions | 30-50% SaaS revenue | 6-12 months |

**Current headroom projection:** At current growth rates (~20% quarter-over-quarter in containers/services), the system has 12-18 months before any hard capacity limit is reached without additional hardware.

---

## 4. Horizontal Scaling Plan

### 4.1 Phase 2: Optimized Single-Node (0-3 Months)

**Objective:** Maximize utilization of existing hardware before adding nodes. No new infrastructure spend.

#### Actions

**A. Container Memory Limit Optimization**
Many containers have generous memory limits relative to actual usage. Right-sizing recovers headroom:

| Container | Current Limit | Actual Usage | Recommended Limit | Headroom Recovered |
|-----------|--------------|--------------|-------------------|-------------------|
| aiops-grafana | 512 MB | 256 MB | 384 MB | 128 MB |
| aiops-clickhouse | 2 GB | 1.2 GB | 1.5 GB | 512 MB |
| aiops-prometheus | 1 GB | 512 MB | 768 MB | 256 MB |
| aiops-loki | 1 GB | 384 MB | 512 MB | 512 MB |
| prediction-radar-db | 1 GB | 512 MB | 768 MB | 256 MB |
| Various agent containers | 512 MB each | 100-150 MB | 256 MB | 256 MB per agent |

**Total headroom recovered: ~2 GB**

**B. Docker Compose CPU Limits**
Apply CPU limits to non-critical containers to prevent resource contention:

```yaml
# Pattern applied to all non-critical containers
deploy:
  resources:
    limits:
      cpus: '0.5'
      memory: 256M
    reservations:
      cpus: '0.1'
      memory: 64M
```

**C. ClickHouse Cold Data Partitioning**
ClickHouse stores 10 GB of analytics data. Partition by month and configure TTL:

```sql
ALTER TABLE analytics.events
  MODIFY TTL toDate(timestamp) + INTERVAL 12 MONTH DELETE;

ALTER TABLE analytics.events
  MODIFY PARTITION BY toYYYYMM(timestamp);
```

**Expected outcome: ClickHouse storage reduced 40% within 3 months.**

**D. Prometheus Retention Tuning**
Current retention: 30 days at 15 GB. Tune based on criticality:

- Critical metrics: 90 days
- Standard metrics: 30 days
- Debug metrics: 7 days

Estimated storage reduction: 30% (4.5 GB recovered).

**E. PM2 Agent Optimization**
Identify and merge redundant agent polling loops. Three agents currently poll LiteLLM independently -- consolidate to a single polling coordinator.

**Resource savings estimate: 200 MB RAM, 5% CPU**

**F. Nginx Caching Layer**
Enable micro-caching on Nginx for frequently accessed static content:

```
# /etc/nginx/conf.d/micro-cache.conf
proxy_cache_path /tmp/nginx-cache levels=1:2 keys_zone=static_cache:10m max_size=1g inactive=60m;
proxy_cache_key "$scheme$request_method$host$request_uri";
```

**Resource savings: Reduces upstream load by ~30% for cacheable content, frees ~5% CPU on API services.**

**G. Connection Pooling Pre-Phase**
Deploy PgBouncer in transaction-pooling mode on AIOPS before full database scaling:

```ini
[databases]
wheeler_core = host=100.118.166.117 port=5432 dbname=wheeler_core
frgcrm = host=127.0.0.1 port=5433 dbname=frgcrm

[pgbouncer]
pool_mode = transaction
max_client_conn = 200
default_pool_size = 25
reserve_pool_size = 10
reserve_pool_timeout = 3.0
```

**Deployed as:** Docker container, `127.0.0.1:6432`, healthchecked.

**Rollback:** Revert application DATABASE_URL from PgBouncer port to direct PostgreSQL port.

#### Phase 2 Success Criteria
- AIOPS RAM utilization reduced from 47% to <40% headroom
- All containers have documented CPU/memory limits
- PgBouncer deployed and all services connecting through it
- ClickHouse TTL policy in effect
- No regression in API response times

### 4.2 Phase 3: Worker Node Offload (3-6 Months)

**Objective:** Add a dedicated worker node to offload compute-intensive workloads from AIOPS, maintaining AIOPS as the gateway and control plane.

#### 4.2.1 New Node Specification

| Attribute | Value |
|-----------|-------|
| Type | Hetzner CX32 |
| Spec | 8 vCPU, 32 GB RAM, 200 GB SSD |
| Role | Worker node -- agents, batch processing, analytics |
| Network | 1 Gbps, Tailscale mesh |
| Estimated Cost | ~35 EUR/month |
| Tailscale IP | 100.x.x.x (reserved) |

#### 4.2.2 Migration Plan

Services to migrate from AIOPS to Worker Node in order of priority:

**Wave 1 -- Stateless Compute (Week 1 of Phase 3)**
These services have zero persistent state and require minimal migration overhead:

| Service | Type | Current AIOPS Port | Reason for Offload |
|---------|------|-------------------|-------------------|
| surplusai-scraper-agent-svc | PM2 | 8003 | Memory-spiky, CPU-heavy scraping |
| surplusai-portal-api | PM2 | 8103 | API workload, easily replicated |
| voice-agent-svc | PM2 | 8014 | Audio processing, CPU-intensive |
| voice-outreach-service | PM2 | 8005 | Twilio integration, I/O heavy |
| insforge-agent-svc | PM2 | 8008 | Document processing, memory-heavy |

**Wave 2 -- Analytics Workloads (Week 2)**
These services benefit from dedicated compute for batch processing:

| Service | Current AIOPS Port | Reason for Offload |
|---------|-------------------|-------------------|
| aiops-clickhouse | 8123 | Large memory footprint (1.2 GB) |
| aiops-superset | 8088 | Query-heavy, blocks on large datasets |

**Wave 3 -- Agent Processing (Week 3)**
AI agents that can run remotely and communicate via event bus:

| Service | Reason for Offload |
|---------|-------------------|
| paperless-agent-svc | Background document processing |
| design-agent-svc | Batch design generation |
| prediction-radar-agent-svc | Market data polling, schedule-driven |

#### 4.2.3 Communication Architecture After Migration

```
AIOPS (Control Plane)                          Worker Node (Compute)
  │                                                    │
  ├── Nginx Gateway (:443)                             ├── Scraper agents
  ├── LiteLLM Proxy (:4049)                            ├── Voice agents
  ├── Control plane (command-center, guardian)          ├── Analytics (ClickHouse, Superset)
  ├── Critical agents (FRGCRM, Ravyn)                  ├── Batch processing agents
  ├── Monitoring stack                                 │
  ├── Local databases                                    └── Tailscale mesh ──── COREDB
  └── Tailscale mesh ──── COREDB                                          │
                           │                                              │
                    COREDB (Data Layer)                                   │
                      ├── PostgreSQL primary                             │
                      ├── Redis                                          │
                      ├── MinIO                                          │
                      └── Temporal                                       │
```

**Key constraint:** LiteLLM stays on AIOPS because all agents route through it. Worker node agents connect to LiteLLM via Tailscale (`http://100.121.230.28:4049`).

#### 4.2.4 Rollback Plan for Worker Node

Each wave is independently rollbackable:

1. **Stop service on worker node:** `pm2 delete <service>` or `docker compose down`
2. **Restart on AIOPS:** Restore from PM2 dump or Docker compose backup
3. **Verify health:** Run smoke-test-all.sh --service=<name>
4. **Execution time:** <2 minutes per service

Full rollback of all waves: <15 minutes.

#### Phase 3 Success Criteria
- AIOPS CPU utilization reduced to <30% average
- AIOPS RAM utilization reduced to <35%
- Worker node CPU utilization <40%
- All migrated services show identical or improved response times
- No increase in p95 latency for end-user facing services
- Cross-node communication verified (no Tailscale routing issues)

### 4.3 Phase 4: Docker Swarm + DB Replicas (6-12 Months)

**Objective:** Achieve high availability through container orchestration and database replication across 4-6 nodes.

#### 4.3.1 Docker Swarm Architecture

Docker Swarm is chosen over Kubernetes for this phase because:
- The existing codebase is already Docker Compose-based, requiring minimal migration
- Swarm's declarative model maps 1:1 to current Docker Compose stacks
- No learning curve for operations team (same CLI, same concepts)
- Lower resource overhead than k3s for the expected scale (<50 containers)
- Staged migration path to k3s in Phase 5 if needed

**Migration path from current Docker Compose:**

```
Step 1: Add docker-compose.yml v3 deploy section to all stacks
  ├── Add deploy.replicas: 1
  ├── Add deploy.resources limits
  ├── Add deploy.update_config with parallelism and delay
  └── Add deploy.rollback_config

Step 2: Initialize Docker Swarm on AIOPS
  docker swarm init --advertise-addr 100.121.230.28

Step 3: Add Worker Node as swarm worker
  docker swarm join --token <token> 100.121.230.28:2377

Step 4: Deploy all stacks as Docker Stack
  docker stack deploy -c docker-compose.yml <stack-name>

Step 5: Add COREDB as swarm manager (if running Docker)
  docker swarm join --token <manager-token> 100.121.230.28:2377
```

**Service placement constraints:**

```yaml
services:
  frgcrm-api:
    deploy:
      placement:
        constraints:
          - node.role == manager  # Stay on AIOPS for gateway access
  
  clickhouse:
    deploy:
      placement:
        constraints:
          - node.hostname == worker-01  # Dedicated analytics node
  
  postgres-primary:
    deploy:
      placement:
        constraints:
          - node.hostname == coredb-01  # Database stays on COREDB
```

**Key architectural change:** Stateful services (databases) remain on COREDB with placement constraints. Stateless services (APIs, agents) can run on any node. This preserves data locality while enabling compute mobility.

#### 4.3.2 PostgreSQL Read Replicas

**When to add:** When COREDB PostgreSQL query load exceeds 50% of available connections or query latency exceeds 100ms p95.

**Read replica architecture:**

```
                    ┌──────────────────┐
                    │  COREDB Primary  │
                    │  (Read/Write)    │
                    │  100.118.166.117 │
                    └────────┬─────────┘
                             │ Streaming replication
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
    ┌─────────────────┐ ┌────────────┐ ┌────────────┐
    │ AIOPS Replica   │ │ Worker     │ │ Analytics  │
    │ (read-only)     │ │ Replica    │ │ Replica    │
    │ 127.0.0.1:5435  │ │ :5435      │ │ :5435      │
    │ Application     │ │ Agents     │ │ ClickHouse │
    │ reads           │ │ reads      │ │ queries    │
    └─────────────────┘ └────────────┘ └────────────┘
```

**Replica configuration:**

```bash
# On COREDB primary
wal_level = replica
max_wal_senders = 5
wal_keep_size = 1024  # MB

# On each replica
primary_conninfo = 'host=100.118.166.117 port=5432 user=replicator password=<hex_password>'
hot_standby = on
hot_standby_feedback = on
```

**Read/write splitting at the application layer:**

- All WRITE queries route to COREDB primary via PgBouncer (port 6432)
- All READ queries route to nearest replica via read-only PgBouncer (port 6433)
- Application DATABASE_URL supports read/write splitting through PgBouncer configuration

**PgBouncer read/write split configuration:**

```ini
[databases]
wheeler_core = host=100.118.166.117 port=5432 dbname=wheeler_core
wheeler_core_read = host=127.0.0.1 port=5435 dbname=wheeler_core
# Application connects to wheeler_core for writes, wheeler_core_read for reads
```

**Failover procedure for primary database:**

```
1. Detect primary failure (pg_isready fails 3x, 30s interval)
2. Promote best replica: pg_ctl promote on replica with least lag
3. Update PgBouncer configs to point to new primary
4. Verify all applications reconnect
5. Provision new replica to replace promoted one

Manual step: Update application .env files if PgBouncer IP changes
Time to failover: <60 seconds (automated) or <5 minutes (manual)
Test frequency: Quarterly restore testing already covers this
```

#### 4.3.3 Redis Sentinel

**When to add:** When Redis services exceed 70% memory utilization or when HA is required for revenue-critical caching.

**Redis Sentinel topology:**

```
                    ┌──────────────────┐
                    │  Redis Sentinel   │
                    │  (3 instances)    │
                    │  :26379           │
                    └──────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Redis        │  │ Redis        │  │ Redis        │
│ Primary      │  │ Replica 1    │  │ Replica 2    │
│ COREDB :6379 │  │ AIOPS :6379  │  │ Worker :6379 │
│ Read/Write   │  │ Read-only    │  │ Read-only    │
└──────────────┘  └──────────────┘  └──────────────┘
```

**Sentinel configuration requirements:**

- Minimum 3 Sentinel instances (on AIOPS, COREDB, Worker nodes) for quorum
- `quorum = 2` (2 out of 3 Sentinels must agree for failover)
- `down-after-milliseconds = 5000` (5-second failure detection)
- `failover-timeout = 30000` (30-second failover window)
- Applications connect to Sentinel for automatic primary discovery

**Rollback:** Stop Sentinel containers, configure applications to connect directly to Redis primary IP.

#### 4.3.4 Load Balancing for Replicated Services

**Nginx upstream blocks for replicated services:**

```nginx
upstream frgcrm-api-backend {
    least_conn;
    server 127.0.0.1:8001 max_fails=3 fail_timeout=30s;
    server 100.x.x.x:8001 max_fails=3 fail_timeout=30s;  # Worker node replica
    keepalive 32;
}

upstream litellm-backend {
    least_conn;
    server 127.0.0.1:4049 max_fails=3 fail_timeout=30s;
    keepalive 16;  # LiteLLM stays single-instance until Phase 5
}

upstream surplusai-api-backend {
    least_conn;
    server 127.0.0.1:8103 max_fails=3 fail_timeout=30s;
    server 100.x.x.x:8103 max_fails=3 fail_timeout=30s;
    keepalive 32;
}
```

**Health check integration with Nginx:**
- Nginx `max_fails=3 fail_timeout=30s` detects unhealthy replicas
- Replicas failing health checks are automatically removed from rotation
- `least_conn` routing ensures even load distribution
- Stickiness not required -- services are stateless (state is in PostgreSQL/Redis)

#### Phase 4 Success Criteria
- All 12 Docker Compose stacks deployable as Docker Stack services
- PostgreSQL read replicas operational with <1s replication lag
- Redis Sentinel configured with automated failover tested
- Zero downtime during single-node failure (any one node can fail)
- Smoke tests pass during node failover scenarios
- All services have at least 2 replicas across at least 2 nodes
- Rolling updates work with zero downtime (tested on each stack)

### 4.4 Phase 5: k3s Kubernetes + Multi-Region (12+ Months)

**Objective:** Full container orchestration with horizontal pod autoscaling, service mesh, and multi-region disaster recovery.

#### 4.4.1 Why k3s (Not Full Kubernetes)

k3s is selected over full Kubernetes for these specific reasons:

1. **Lightweight (~50 MB binary vs 500 MB+ for full K8s)** -- runs efficiently on Hetzner CPX51/CX32 class nodes
2. **Built-in SQLite/etcd3** -- no external etcd cluster needed for small-medium clusters
3. **Traefik integrated** -- matches current Nginx/Traefik routing pattern
4. **Helm charts available** -- for all current Docker images (Prometheus, Grafana, ClickHouse, etc.)
5. **Upstream compatible** -- any Kubernetes tooling works (Helm, Prometheus Operator, cert-manager)
6. **Migration from Docker Swarm** -- containers and concepts map well, `kompose` for initial manifest generation

**Migration path from Docker Swarm:**

```
Step 1: Install k3s on existing nodes (alongside Docker)
  curl -sfL https://get.k3s.io | sh -s - --docker  # Use existing Docker install

Step 2: Convert Docker Compose stacks to Kubernetes manifests
  kompose convert -f docker-compose.yml -o k8s-manifests/
  
Step 3: Deploy stateless services first
  kubectl apply -f k8s-manifests/frgcrm-api/

Step 4: Wire up Tailscale for inter-node Kubernetes networking
  # Use Tailscale as CNI or deploy ts-bootstrap for node connectivity

Step 5: Deploy stateful services with PersistentVolumeClaims
  # PostgreSQL uses existing data on COREDB with local-path-provisioner

Step 6: Gradual migration from Docker Swarm stacks
  # Each stack migrated independently, verified with smoke tests
```

#### 4.4.2 Horizontal Pod Autoscaling (HPA)

**HPA configuration targets:**

```yaml
# frgcrm-api autoscaling
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frgcrm-api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frgcrm-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 75
```

**Target services for HPA:**

| Service | Min Replicas | Max Replicas | Scaling Metric | Cooldown |
|---------|-------------|-------------|----------------|----------|
| frgcrm-api | 2 | 10 | CPU >70% or RAM >75% | 3 min |
| surplusai-portal-api | 2 | 6 | CPU >70% | 3 min |
| surplusai-scraper-agent-svc | 1 | 4 | Queue depth >100 | 5 min |
| litellm | 2 | 8 | Request queue >50 | 2 min |
| ClickHouse | 1 | 3 | Query concurrency >20 | 5 min |
| Nginx gateway | 2 | 6 | Connection count >500 | 2 min |

**Autoscaling cooldown:** Minimum 2 minutes between scale-up events, 5 minutes between scale-down events to prevent thrashing.

#### 4.4.3 Service Mesh (Istio)

**When to add service mesh:** When inter-service communication exceeds 50 unique routes and mTLS is required for cross-node traffic.

**Istio integration points:**

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Service A   │     │  Service B   │     │  Service C   │
│  (AIOPS)     │     │  (Worker)    │     │  (COREDB)    │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       └────────────────────┼────────────────────┘
                            │
                    ┌───────┴───────┐
                    │   Istio Mesh  │
                    │               │
                    │ - mTLS        │
                    │ - Circuit     │
                    │   breakers    │
                    │ - Traffic     │
                    │   splitting   │
                    │ - Telemetry   │
                    └───────────────┘
```

**Capabilities enabled by service mesh:**
- mTLS between all services (zero-trust within cluster)
- Circuit breakers for failing upstream services
- Traffic splitting for canary deployments (5% new version, 95% old version)
- Request retries with timeout (3 retries, exponential backoff)
- Distributed tracing (Jaeger integration)
- Unified telemetry (Prometheus metrics on all mesh traffic)

**Performance overhead:** ~5% additional CPU, ~50 MB RAM per sidecar. Acceptable for production traffic at this scale.

#### 4.4.4 Multi-Region Architecture

**Region layout:**

```
Region 1: EU (Hetzner Falkenstein)        Region 2: US (Hetzner Hillsboro)
  ├── AIOPS node (CPX51)                    ├── AIOPS node (CPX51)
  ├── Worker node (CX32)                    ├── Worker node (CX32)
  ├── COREDB (PostgreSQL primary)           ├── COREDB (PostgreSQL replica)
  ├── Redis primary                         ├── Redis replica + Sentinel
  └── Nginx gateway (regional)              └── Nginx gateway (regional)
                                                    │
              ┌─────────────────────────────────────┘
              │ Tailscale mesh + WireGuard tunnel
              ▼
    Global Cloudflare Load Balancer
      ├── Regional failover (active-active)
      ├── DDoS protection
      ├── SSL termination
      └── Geo-routing (users routed to nearest region)
```

**Cross-region database replication:**

```
PostgreSQL logical replication (region A → region B):
  - publisher on EU primary
  - subscriber on US standby
  - Asynchronous: 50-100ms lag typical for transatlantic
  
Failover: Manual promotion of US to primary if EU region lost
RPO: <60 seconds (async replication at transatlantic latency)
RTO: <5 minutes (DNS + PgBouncer config update)
```

**Redis cross-region setup:**
- Redis Sentinel operates within each region independently
- Cross-region Redis replication via Redis Replicator (async)
- Cache warming on failover: applications reload cache from database

#### 4.4.5 Cost Projection for Multi-Region

| Item | EU Region | US Region | Monthly Cost |
|------|-----------|-----------|-------------|
| AIOPS (CPX51) | 1 | 1 | ~60 EUR/month |
| Worker (CX32) | 1 | 1 | ~70 EUR/month |
| COREDB (CPX51) | 1 | 1 | ~60 EUR/month |
| Total compute | 3 nodes | 3 nodes | ~190 EUR/month |
| Network egress | -- | -- | ~20 EUR/month |
| Cloudflare | 1 plan | 1 plan | ~200 USD/month |
| Backup storage | 1 TB | 1 TB | ~10 EUR/month |
| **Total** | | | **~430 EUR+USD/month** |

**Cost per tenant at multi-region scale (100 tenants):** ~4.30 EUR/month per tenant for infrastructure.

#### Phase 5 Success Criteria
- k3s cluster operational across all nodes
- All services migrated from Docker Swarm to k3s
- HPA working on all target services (verified with load test)
- Istio mesh enabling mTLS between all services
- Multi-region failover tested and verified (<5 minute RTO)
- Cross-region replication lag <60 seconds P99
- Smoke tests passing on both regions independently
- Cost per tenant under 5 EUR/month at 100 tenants

---

## 5. Database Scaling

### 5.1 PostgreSQL Scaling Strategy

#### 5.1.1 Connection Pooling (Phase 2 -- Immediate)

**Problem:** Without connection pooling, each service maintains a direct database connection. At current scale (~40 connections total) this is manageable, but each new service adds connections and the COREDB PostgreSQL `max_connections` is 100.

**Solution:** Deploy PgBouncer in transaction-pooling mode.

| Metric | Without PgBouncer | With PgBouncer | Improvement |
|--------|-------------------|----------------|-------------|
| Max connections used | ~40 | ~25 | 38% reduction |
| Connections per service | 3-8 | 1 | Fixed at 1 |
| COREDB max_connections needed | 100 | 50 | Can reduce or absorb growth |

#### 5.1.2 Read Replicas (Phase 4)

**Scaling trigger:** Query latency exceeds 100ms p95 OR read query volume exceeds 2000 QPS.

**Read replica deployment:**

```
Primary: COREDB (100.118.166.117:5432)
  → AIOPS replica (127.0.0.1:5435)  -- Application reads
  → Worker replica (127.0.0.1:5435) -- Agent reads
  → Analytics replica (127.0.0.1:5435) -- ClickHouse/Superset queries (can be heavy)
```

**Connection routing:** Application connection strings include both primary and replica URLs. The application or PgBouncer routes read queries to replicas and write queries to primary.

#### 5.1.3 Table Partitioning (Phase 4+)

**Target tables for partitioning:**

| Table | Database | Partition Key | Partition Type | Estimated Size at 1 Year |
|-------|----------|---------------|---------------|-------------------------|
| cases | frgcrm | created_at | BY RANGE (monthly) | 500K rows |
| events | analytics | timestamp | BY RANGE (monthly) | 100M rows |
| scraped_cases | frgcrm | sale_date | BY RANGE (monthly) | 200K rows |
| webhook_logs | frgcrm | created_at | BY RANGE (monthly) | 1M rows |
| audit_log | frgcrm | created_at | BY RANGE (monthly) | 5M rows |

**Partition implementation pattern (for each table):**

```sql
CREATE TABLE cases (
    id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- other columns
) PARTITION BY RANGE (created_at);

CREATE TABLE cases_2026_06 PARTITION OF cases
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE cases_2026_07 PARTITION OF cases
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
-- ... monthly partitions created automatically via pg_partman or cron
```

**Benefits at scale:**
- Queries on recent data scan only current month's partition
- Old partitions can be detached and archived without blocking writes
- `VACUUM` runs on individual partitions (faster, less locking)
- Backup can skip archived partitions

#### 5.1.4 Tenant Isolation (Phase 4+)

As tenant count grows, database isolation strategy evolves:

| Tenant Count | Isolation Model | Migration Path |
|-------------|----------------|----------------|
| 1-10 | Shared tables with tenant_id column | Default, no migration needed |
| 10-25 | Schema-per-tenant (same database) | Migration script: CREATE SCHEMA tenant_<id>, copy structure |
| 25-100 | Database-per-tenant (same server) | CREATE DATABASE tenant_<id>, migration per tenant |
| 100+ | Dedicated PostgreSQL instances per tenant group | New server per 25 tenants |

**Schema-per-tenant migration:**

```sql
-- For each tenant being migrated:
CREATE SCHEMA IF NOT EXISTS tenant_123;
SET search_path TO tenant_123;
CREATE TABLE cases (LIKE public.cases INCLUDING ALL);
INSERT INTO tenant_123.cases SELECT * FROM public.cases WHERE tenant_id = 123;

-- Update application connection to include search_path:
-- DATABASE_URL=postgresql://user:pass@host:5432/frgcrm?options=--search_path%3Dtenant_123
```

**Rollback:** Revert `search_path` to public schema and verify data access.

#### 5.1.5 PostgreSQL Upgrade Path

| Current Version | Target | Reason | Migration Method |
|----------------|--------|--------|-----------------|
| 16 (current) | 17 (when available) | Performance, new features | pg_upgrade (tested quarterly) |
| 16 | 17 + pg_tle | If extension loading is needed | Logical replication to new cluster |

**Upgrade procedure:**
1. Deploy new PostgreSQL version on standby node
2. Configure logical replication from current primary to new version
3. Verify data consistency (row count checks)
4. Switch application connections to new primary
5. Decommission old primary

**Rollback during upgrade:** Point application DATABASE_URL back to old primary.

### 5.2 Redis Scaling Strategy

#### 5.2.1 Current State

| Redis Instance | Location | Memory | Use Case | Persistence |
|---------------|----------|--------|----------|-------------|
| prediction-radar-redis | AIOPS Docker | 256 MB allocated | Cache + queues | AOF disabled (cache only) |
| docuseal-redis | AIOPS Docker | 128 MB allocated | Session cache | AOF disabled |
| usesend-redis | COREDB Docker | 256 MB allocated | Email queues | AOF every 1 sec |

#### 5.2.2 Sentinel for HA (Phase 4)

**Architecture:**

```
3 Sentinel instances (AIOPS, COREDB, Worker)
  ├── Monitors Redis primary (COREDB)
  ├── Monitors Redis replicas (AIOPS, Worker)
  └── Automates failover
```

**Application connection change:**
- Before: `redis://password@127.0.0.1:6379`
- After: `redis://password@100.121.230.28:26379,100.118.166.117:26379,100.x.x.x:26379?sentinel=wheeler-redis`

#### 5.2.3 Redis Cluster Mode (Phase 5)

**When to enable clustering:**
- Total Redis memory exceeds 8 GB
- Write throughput exceeds 50,000 ops/second
- Single Redis instance approaches 90% memory utilization

**Cluster topology:**
```
3 master nodes (shard 1, 2, 3) + 3 replica nodes
  ├── Shard 1: keys 0-5461    (AIOPS)
  ├── Shard 2: keys 5462-10922 (COREDB)
  └── Shard 3: keys 10923-16383 (Worker)
  Each shard has 1 replica on a different node
```

**Key distribution strategy:**
- Revenue-critical keys prefixed with `{revenue}` (hash-tagged to same shard for multi-key operations)
- Cache keys distributed across shards by key hash
- Queue keys isolated to shard 1 (prevents queue processing from impacting other shards)

**Migration path from standalone Redis:**
```
1. Deploy Redis cluster nodes alongside existing standalone instances
2. Configure application to use cluster mode (redis-cluster client)
3. Migrate data slowly via SCAN + MIGRATE (no downtime, ~10K keys/second)
4. Decommission standalone Redis once data is verified
```

**Rollback:** Point application back to standalone Redis, run reverse migration.

### 5.3 Neo4j Scaling

#### 5.3.1 Current State

- Single instance on AIOPS: ecosystem-graph container
- Port: 7687 (Bolt), 7474 (HTTP)
- Size: ~2 GB, growing at ~200 MB/month
- No replication configured

#### 5.3.2 Read Replicas (Phase 4)

When query volume exceeds 100 QPS or graph size exceeds 10 GB, add read replicas:

```
Primary: AIOPS (127.0.0.1:7687)
  → Worker Node replica (127.0.0.1:7688) -- Agent queries
  → Analytics replica (127.0.0.1:7689) -- Superset/reporting queries
```

#### 5.3.3 Causal Clustering (Phase 5)

For high availability at scale:

```
Cluster configuration:
  - 3 core nodes (writes + reads)
  - 2+ read replicas (reads only)
  - Minimum 3 cores for quorum
  - Automatic leader election

Deployment: k3s StatefulSet with Neo4j Operator
```

### 5.4 ClickHouse Scaling

#### 5.4.1 Current State

- Single instance on AIOPS: 10 GB analytics data, 1.2 GB RAM
- Growth: ~2 GB/month
- Primary use: Superset dashboards and analytical queries

#### 5.4.2 Optimization Before Scaling (Phase 2)

```sql
-- Partition by month
ALTER TABLE analytics.events ON CLUSTER default
  PARTITION BY toYYYYMM(timestamp);

-- TTL for automatic data lifecycle
ALTER TABLE analytics.events ON CLUSTER default
  MODIFY TTL timestamp + INTERVAL 12 MONTH DELETE;

-- Materialized views for common queries
CREATE MATERIALIZED VIEW analytics.daily_summary_mv
  ENGINE = SummingMergeTree
  PARTITION BY toYYYYMM(day)
  AS SELECT ...;
```

#### 5.4.3 Distributed Tables (Phase 4)

When data exceeds 50 GB or query latency >1 second:

```
ClickHouse cluster with distributed tables:
  ┌──────────────┐  ┌──────────────┐
  │ AIOPS Shard 1 │  │ Worker Shard 2 │
  │ (local table)  │  │ (local table)  │
  └──────┬───────┘  └──────┬───────┘
         └────────┬────────┘
                  │
          ┌───────┴───────┐
          │ Distributed   │
          │ Table (Merge) │
          │ All shards    │
          └───────────────┘
```

**Sharding key:** `cityHash64(event_type)` for even distribution.

**Replication:** `ReplicatedMergeTree` engine with ZooKeeper/Keeper for metadata coordination.

#### 5.4.4 Backup Strategy at Scale

```bash
# ClickHouse backup (Phase 2+)
clickhouse-client --query "BACKUP TABLE analytics.events TO File('/backups/clickhouse/events_$DATE.zip')"

# Automated weekly with 30-day retention
0 2 * * 0 /opt/scripts/clickhouse-backup.sh --retention 30
```

---

## 6. Multi-Tenant Scaling

### 6.1 Tenant Tiers and Isolation Model

The Wheeler ecosystem serves multiple tenant types with different isolation requirements:

| Tier | Max Tenants | Isolation Model | Tenant Count Before Phase Change | Services Affected |
|------|-------------|----------------|----------------------------------|-------------------|
| Freemium | Unlimited | Shared tables with tenant_id | Immediate | SurplusAI Portal |
| Mid-Tier | 25 | Schema-per-tenant | >10 tenants | All PM2 services |
| Enterprise | 100 | Database-per-tenant | >25 tenants | All services |
| White-Label | 25 | Dedicated PostgreSQL instance | >50 tenants | Full stack per tenant |

### 6.2 Freemium Tier: Shared Tables

**Model:** All tenants share the same database tables, differentiated by `tenant_id` column. Every query includes `WHERE tenant_id = ?`.

**Implementation:**
- JWT contains `tenant_id` claim, extracted by middleware
- All SQL queries include tenant filter (enforced by Row-Level Security as defense-in-depth)
- No schema changes needed as tenants are added

```sql
-- Row-Level Security policy
ALTER TABLE cases ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON cases
  USING (tenant_id = current_setting('app.tenant_id')::UUID);
```

**Limits per freemium tenant:**
- Max 50 leads/month
- Max 1 county coverage
- Data retention: 90 days
- No API access

**Scaling limit:** This model works up to ~10 enterprise-equivalent tenants or ~1000 freemium tenants before query performance degrades due to table size.

### 6.3 Mid-Tier: Schema-Per-Tenant

**Migration trigger:** When any single table exceeds 10M rows OR when tenant count exceeds 10 paying customers.

**Architecture:**
- Single PostgreSQL database per service (e.g., `frgcrm`)
- Each tenant has their own schema: `tenant_<uuid>`
- Identical table structure across schemas
- Application connection string includes `search_path` set per-request

**Connection management:**
- PgBouncer handles connection pooling (one pool per active schema)
- Pool configuration: `default_pool_size=5` per tenant, `reserve_pool_size=2`
- Connection count stays manageable: 5 tenants x 5 connections = 25 total

**Schema creation (automated on tenant signup):**

```bash
#!/bin/bash
# create-tenant-schema.sh
TENANT_ID=$1
DB_URL=$2

psql "$DB_URL" <<SQL
CREATE SCHEMA IF NOT EXISTS tenant_${TENANT_ID};
SET search_path TO tenant_${TENANT_ID};
CREATE TABLE cases (LIKE public.cases INCLUDING ALL);
-- ... all other tables

-- Grant permissions
GRANT USAGE ON SCHEMA tenant_${TENANT_ID} TO frgcrm_app;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA tenant_${TENANT_ID} TO frgcrm_app;
SQL
```

**Rollback:** Drop schema, update application search_path back to public.

### 6.4 Enterprise Tier: Database-Per-Tenant

**Migration trigger:** Tenant requires data sovereignty compliance, or tenant data exceeds 50 GB.

**Architecture:**
- Each enterprise tenant gets a dedicated PostgreSQL database on COREDB
- Separate backup schedule per database
- Independent migration cycles
- Connection pooling per database

**Connection string convention:**

```
# Per-tenant DATABASE_URL
# Standard: postgresql://frgcrm_app:password@127.0.0.1:6432/frgcrm?schema=public
# Enterprise: postgresql://tenant_<id>_app:password@127.0.0.1:6432/tenant_<id>_db
```

**Automatic provisioning:**

```bash
#!/bin/bash
# provision-enterprise-tenant.sh
TENANT_ID=$1

# Create database
createdb "tenant_${TENANT_ID}_db"

# Create role
psql -c "CREATE ROLE tenant_${TENANT_ID}_app WITH LOGIN PASSWORD '${TENANT_PASSWORD}';"

# Run migrations on tenant database
psql -d "tenant_${TENANT_ID}_db" -f /opt/migrations/001_base_schema.sql

# Configure PgBouncer
echo "tenant_${TENANT_ID}_db = host=127.0.0.1 port=5432 dbname=tenant_${TENANT_ID}_db" >> /etc/pgbouncer/pgbouncer.ini

# Configure backup
echo "0 3 * * * pg_dump tenant_${TENANT_ID}_db | gzip > /opt/backups/tenant_${TENANT_ID}_\$(date +%Y%m%d).sql.gz" | crontab -
```

### 6.5 White-Label Tier: Dedicated PostgreSQL Instance

**Migration trigger:** Tenant requires hardware-level isolation, or tenant contract exceeds 5,000 EUR/month.

**Architecture:**
- Tenant gets a dedicated PostgreSQL instance (Docker container or separate VM)
- Full control over extensions, config, migration schedule
- Backup schedule negotiated per contract

**When to offer:**
- Enterprise tenants exceeding 100 GB data
- Regulated industries (finance, healthcare)
- White-label resellers requiring custom branding at infrastructure level

### 6.6 Tenant Limit Early Warning System

| Metric | Warning Threshold | Critical Threshold | Expected Timeline to Threshold |
|--------|------------------|-------------------|-------------------------------|
| Shared table size (cases) | 5M rows | 10M rows | 9-12 months |
| Schema-per-tenant count | 25 schemas | 35 schemas | 18-24 months |
| Database-per-tenant count | 50 databases | 75 databases | 24-36 months |
| PgBouncer connection count | 150 connections | 200 connections | 12-18 months |
| Redis key count | 500K keys | 1M keys | 6-12 months |
| Disk utilization (data) | 70% | 85% | 12-18 months |

---

## 7. Network Scaling

### 7.1 Current Network Topology

```
Internet
  │
  └── AIOPS Nginx (:443, rate-limited, basic auth)
        │
        ├── 17 virtual hosts → 127.0.0.1:<port> (AIOPS local)
        ├── 2 virtual hosts → 100.118.166.117:<port> (COREDB cross-server)
        │
        └── Tailscale mesh
              ├── AIOPS (100.121.230.28)
              ├── COREDB (100.118.166.117)
              └── Hostinger (100.98.163.17)
```

**Current bandwidth:** 1 Gbps per Hetzner node. Current utilization: ~50 Mbps average, <200 Mbps peak.

### 7.2 Phase 2: Nginx Optimization

**Problem:** Single Nginx instance handles all 17 virtual hosts. If Nginx fails, all external access is lost.

**Optimization (low effort, high reliability):**

**A. Nginx health monitoring:**
```bash
# /etc/nginx/nginx.conf
# Already monitored by Uptime Kuma and Prometheus node_exporter
```

**B. Nginx caching for static content:**
```nginx
location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2?|ttf|eot)$ {
    expires 7d;
    add_header Cache-Control "public, immutable";
    
    # Micro-cache from upstream
    proxy_cache static_cache;
    proxy_cache_valid 200 60m;
    proxy_cache_use_stale error timeout updating;
}
```

**C. Rate limiting tuning:**
```nginx
# Current: burst=20, nodelay
# Phase 2: Different limits per route type
limit_req_zone $binary_remote_addr zone=api:10m rate=30r/s;
limit_req_zone $binary_remote_addr zone=static:10m rate=100r/s;
limit_req_zone $binary_remote_addr zone=admin:10m rate=5r/s;
```

### 7.3 Phase 3: HAProxy for L7 Load Balancing

**When to add:** When any of these conditions are met:
- Nginx connection count exceeds 500 concurrent
- Second AIOPS node added
- Need for TCP load balancing (PostgreSQL, Redis)

**HAProxy deployment:**

```haproxy
# /etc/haproxy/haproxy.cfg
global
    maxconn 4096
    log /dev/log local0

defaults
    mode http
    timeout connect 5s
    timeout client 30s
    timeout server 30s

# PostgreSQL load balancing (read replicas)
backend postgres_read
    mode tcp
    balance roundrobin
    server coredb-primary 100.118.166.117:5432 check
    server aiops-replica 127.0.0.1:5435 check
    server worker-replica 100.x.x.x:5435 check

# API load balancing
backend frgcrm-api
    mode http
    balance leastconn
    option httpchk GET /health
    server aiops-1 127.0.0.1:8001 check
    server worker-1 100.x.x.x:8001 check
```

**Placement:** HAProxy runs on AIOPS alongside Nginx, or replaces Nginx entirely.

**Migration from Nginx to HAProxy:**
1. Deploy HAProxy with identical routing rules (derived from current Nginx config)
2. Test HAProxy on alternate port (444)
3. Switch traffic gradually: update DNS to point to HAProxy
4. Keep Nginx as backup, verify both converge
5. Decommission Nginx once HAProxy is stable (7 days)

**Rollback:** Point DNS back to Nginx, disable HAProxy.

### 7.4 Phase 4: Service Mesh Foundation

**Before full Istio (Phase 5), implement service mesh patterns manually:**

**mTLS via Tailscale:** Already in place for cross-node traffic. Extend to inter-service:
- All AIOPS-to-COREDB traffic is over Tailscale (encrypted)
- Add internal service certificates for HTTP-level mTLS

**Circuit breakers in application code:**
```python
# Pattern applied to all service-to-service HTTP calls
try:
    response = requests.get(
        "http://127.0.0.1:8001/api/health",
        timeout=5,
        headers={"Authorization": f"Bearer {INTERNAL_API_KEY}"}
    )
except requests.exceptions.Timeout:
    # Circuit opens after 3 consecutive timeouts
    circuit_breaker.record_failure()
    if circuit_breaker.is_open:
        fallback_cache_response()
except Exception as e:
    log_error(e)
    raise
```

**Retry with backoff:**
```python
# Standard retry pattern for all inter-service calls
retry_strategy = Retry(
    total=3,
    backoff_factor=0.5,
    status_forcelist=[500, 502, 503, 504],
    allowed_methods=["GET", "POST"]
)
adapter = HTTPAdapter(max_retries=retry_strategy)
session = requests.Session()
session.mount("http://", adapter)
```

### 7.5 Phase 5: Full Service Mesh (Istio)

**Deployment:** When cross-service calls exceed 100 routes and manual certificate management becomes unmanageable.

**Istio installation on k3s:**

```bash
# Install Istio
istioctl install --set profile=default -y

# Enable mTLS (STRICT mode)
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT
EOF

# Add services to mesh (label namespace)
kubectl label namespace default istio-injection=enabled
```

**Traffic splitting for canary deployments:**

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: frgcrm-api
spec:
  hosts:
  - frgcrm-api
  http:
  - route:
    - destination:
        host: frgcrm-api
        subset: v1
      weight: 95
    - destination:
        host: frgcrm-api
        subset: v2
      weight: 5
```

### 7.6 Cloudflare Multi-Region (Phase 5)

**Configuration for global load balancing:**

```
1. Cloudflare Load Balancer
   ├── Pool 1: EU region (5.78.140.118) — weight 100
   ├── Pool 2: US region (US IP here) — weight 0 (standby)
   ├── Health check: GET /health, 60s interval
   └── Steering: Geo (users routed to nearest region)

2. Cloudflare WAF rules
   ├── Rate limiting: 100 req/s per IP
   ├── Bot management: Challenge known bots
   └── Geo-blocking: Block non-target countries (if needed)

3. DNS: *.wheeler.claw.engineer → Cloudflare Load Balancer
```

**Failover test procedure (quarterly):**
1. Take EU region offline in Cloudflare LB (mark pool as "down")
2. Verify US region handles all traffic
3. Monitor API latency and error rates for 15 minutes
4. Restore EU region, verify traffic distributes
5. Document failover time and any issues

---

## 8. Agent Fleet Scaling

### 8.1 Current Agent Architecture

12 PM2 agent services plus LiteLLM, all running on AIOPS:

| Agent | RAM | CPU Pattern | Bottleneck | Scaling Strategy |
|-------|-----|-------------|------------|-----------------|
| frgcrm-api | 235 MB | Synchronous, request-driven | DB connections, LLM rate limits | Horizontal: add replicas behind Nginx |
| frgcrm-agent-svc | 94 MB | Background, polling | API rate limits | Already efficient |
| surplusai-portal-api | 103 MB | Synchronous | DB connections | Horizontal: add replicas |
| surplusai-scraper-agent | 108 MB | Memory-spiky, CPU-heavy | County API rate limits | Vertical: more RAM, then horizontal per-county |
| prediction-radar-agent | 110 MB | Scheduled, data fetching | External API limits | Queue-based: Temporal for durable execution |
| ravyn-agent-svc | 108 MB | Background analysis | LLM token limits | Vertical: more RAM for larger context |
| horizon-agent-svc | 105 MB | Scanning, polling | External API limits | Temporal for parallel scanning |
| voice-agent-svc | 104 MB | Audio processing | CPU for transcription | Offload to GPU-enabled node |
| voice-outreach-service | 54 MB | I/O-heavy (Twilio) | Network throughput | Already efficient |
| paperless-agent-svc | 104 MB | Document processing | OCR throughput | Queue-based: parallel document processing |
| insforge-agent-svc | 74 MB | Document intelligence | LLM processing time | Queue-based |
| design-agent-svc | 109 MB | Design generation | LLM token limits | Queue-based |
| litellm | 377 MB | Proxy, all agent traffic | Request queue, rate limits | Most critical: must scale first |
| ecosystem-guardian | 56 MB | Polling, minimal | No bottleneck | Already efficient |
| event-bus-relay | 57 MB | Event routing | Message throughput | Horizontal: event partitions |
| war-room-server | 59 MB | Incident response | Low traffic | Already efficient |
| command-center | 48 MB | Orchestration | Command queue | Already efficient |

### 8.2 LiteLLM Scaling (Priority #1)

LiteLLM is the single most critical scaling target because ALL agents route through it.

**Phase 2 -- Configuration optimization:**
- Increase `max_retries` for rate-limited requests
- Enable response caching for identical prompts (TTL: 5 minutes)
- Configure model fallback chain: deepseek-chat → claude-opus → gpt-4

**Phase 3 -- Vertical scaling:**
- Increase LiteLLM `--max_parallel_requests` from current value to 50
- Increase container memory limit from 512 MB to 1 GB
- Monitor queue depth; add LiteLLM instance if depth > 100

**Phase 4 -- Horizontal scaling:**
```yaml
# LiteLLM behind HAProxy
backend litellm
    balance leastconn
    server litellm-1 127.0.0.1:4049 check
    server litellm-2 127.0.0.1:4050 check
    
# Redis-backed request cache shared across instances
cache_params:
  type: redis
  host: 127.0.0.1  # local Redis or COREDB Redis
  port: 6379
  ttl: 300  # 5 minutes
```

**Phase 5 -- Pooled model routing:**
```yaml
# LiteLLM proxy config with per-model pools
model_list:
  - model_name: deepseek-chat
    litellm_params:
      model: deepseek/deepseek-chat
      api_key: ${DEEPSEEK_API_KEY}
      rpm: 100  # requests per minute cap
    pool: 
      - 127.0.0.1:4049
      - 127.0.0.1:4050
  
  - model_name: claude-sonnet
    litellm_params:
      model: anthropic/claude-3-sonnet
      api_key: ${ANTHROPIC_API_KEY}
      rpm: 50
    pool:
      - 127.0.0.1:4049  # Same instance, different model
```

### 8.3 SurplusAI Scraper Scaling

**Phase 2 -- Stabilization (already in progress):**
- Root cause fix: env -i delete+start pattern
- Add health endpoint for PM2 wait_ready
- Set memory limit: 256 MB (current usage: 108 MB)

**Phase 3 -- Offload to Worker Node:**
- Move scraper to worker node (CX32)
- Connect to LiteLLM via Tailscale (`http://100.121.230.28:4049`)

**Phase 4 -- Per-County Queue:**
- Each county scraper runs as an independent PM2 process
- County processes communicate through Temporal for retry logic
- Per-process memory limit: 128 MB

```
Before: 1 scraper process for all counties
After:  N scraper processes (1 per county, up to 10)
         ├── surplusai-scraper-la-ca    (Los Angeles)
         ├── surplusai-scraper-cook-il  (Cook County)
         ├── surplusai-scraper-harris-tx(Harris County)
         ├── surplusai-scraper-maricopa-az (Maricopa)
         └── surplusai-scraper-miami-fl  (Miami-Dade)
```

### 8.4 FRGCRM API Scaling

**Phase 2 -- Connection pooling:**
- Already planned: PgBouncer deployment
- API connects to PgBouncer at 127.0.0.1:6432 instead of direct to PostgreSQL

**Phase 4 -- Horizontal scaling:**
- Two API replicas behind Nginx upstream block
- One on AIOPS, one on Worker node
- Session affinity not required (stateless API)

**Phase 5 -- HPA:**
- Autoscale between 2 and 10 replicas based on CPU >70%

### 8.5 Agent Scaling Patterns

All agents follow these scaling patterns depending on workload type:

**Pattern A: Request-Driven (frgcrm-api, surplusai-portal-api)**
```
Scale: Horizontal (add replicas)
Queue: Not needed (direct request/response)
State: Stateless (all state in database)
Monitor: P95 latency, request count, error rate
```

**Pattern B: Batch/Queue-Driven (scraper, paperless, design)**
```
Scale: Vertical then horizontal (more workers per queue)
Queue: Temporal or Redis list
State: Job state in database
Monitor: Queue depth, job completion rate, failure rate
```

**Pattern C: Scheduled (prediction-radar, horizon)**
```
Scale: By schedule density (configurable interval per task)
Queue: Temporal cron workflows
State: Temporal workflow state
Monitor: Missed schedules, execution duration
```

**Pattern D: Streaming (event-bus-relay, voice)**
```
Scale: By partition count (event streams partitionable by source)
Queue: Redis pub/sub or Kafka (Phase 5)
State: At-most-once delivery (or exactly-once with Kafka)
Monitor: Throughput, lag, delivery failures
```

---

## 9. Monitoring and Observability at Scale

### 9.1 Current Stack Limitations

| Tool | Current Capability | Limitation at Scale |
|------|-------------------|---------------------|
| Prometheus | Single instance, 15 GB retention | Labels cardinality explosion, storage ceiling |
| Loki | Single instance, 1-year retention | Query performance degrades past 50 GB |
| Grafana | Single instance, local SQLite | Dashboard concurrency limits |
| Alertmanager | Single instance, Discord webhook | No grouping/aggregation at high alert volume |

### 9.2 Phase 2 -- Thanos Sidecar for Prometheus

**When to add Prometheus high availability:** When metrics cardinality exceeds 100K series or retention needs exceed 30 days.

**Thanos architecture:**

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ AIOPS        │  │ Worker       │  │ COREDB       │
│ Prometheus   │  │ Prometheus   │  │ Prometheus   │
│ + Thanos     │  │ + Thanos     │  │ + Thanos     │
│ Sidecar      │  │ Sidecar      │  │ Sidecar      │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                 │                 │
       └─────────────────┼─────────────────┘
                         │
                 ┌───────┴───────┐
                 │  Thanos Query │
                 │  (Grafana     │
                 │   datasource) │
                 └───────────────┘
```

**Benefits:**
- Global view across all nodes from single Grafana datasource
- Unlimited retention via object storage (S3/MinIO)
- Downsampling: older data stored at lower resolution
- No single point of failure (any Prometheus can fail, data preserved in object store)

### 9.3 Phase 3 -- Loki sharding

**When to add Loki horizontal scaling:** When log ingestion exceeds 100 GB/day or query time exceeds 30 seconds.

**Architecture:**

```
Loki distributed mode:
  ┌──────────────┐  ┌──────────────┐
  │ Distributor  │  │ Distributor  │  (receives logs, forwards to ingesters)
  └──────┬───────┘  └──────┬───────┘
         └────────┬────────┘
                  │
     ┌────────────┼────────────┐
     │            │            │
     ▼            ▼            ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│ Ingester │ │ Ingester │ │ Ingester │ (batches logs to object storage)
└──────────┘ └──────────┘ └──────────┘
     │            │            │
     └────────────┼────────────┘
                  │
          ┌───────┴───────┐
          │  Object Store │
          │  (MinIO/S3)   │
          └───────────────┘
```

**In this setup:**
- AIOPS runs 1 distributor + 2 ingesters
- Worker node runs 1 distributor + 1 ingester
- Object store on MinIO (COREDB) for log storage
- Grafana queries through Loki querier

### 9.4 Phase 4 -- Grafana HA

**When to add Grafana HA:** When concurrent dashboard users exceed 10 or dashboard queries timeout.

**Architecture:**
```
2 Grafana instances behind HAProxy
  ├── Shared PostgreSQL dashboard store (existing COREDB PostgreSQL)
  ├── Alerting configured on both instances
  └── Session affinity not required (stateless dashboards)

Database migration:
  Grafana config:
    [database]
    type = postgres
    host = 100.118.166.117:5432
    name = grafana
    user = grafana
    ssl_mode = disable
```

**Migration path:**
1. Export current Grafana dashboards as JSON
2. Create `grafana` database on COREDB PostgreSQL
3. Deploy second Grafana instance pointing to shared database
4. Import dashboards to new database
5. Verify both instances serve identical dashboards

### 9.5 Phase 5 -- Distributed Tracing

**Problem:** In a multi-node, multi-service architecture, debugging a single request that crosses 5+ services becomes impossible with logs and metrics alone.

**Solution:** OpenTelemetry + Jaeger

**Instrumentation targets:**

| Service | Instrumentation | Spans per Request |
|---------|----------------|-------------------|
| Nginx/HAProxy | OpenTelemetry Nginx module | 1 (ingress) |
| frgcrm-api | Python OpenTelemetry SDK | 3 (auth, handler, DB) |
| LiteLLM | LiteLLM built-in tracing | 2 (proxy, upstream) |
| PostgreSQL | pg_stat_statements with trace_id | 1 per query |
| Redis | Redis OpenTelemetry plugin | 1 per operation |
| All agents | Python/Node.js OTEL SDK | 5-10 per workflow |

**Sampling strategy at scale:**
- Head-based: 100% sampling for revenue-critical paths (FRGCRM, Prediction Radar payments)
- Tail-based: 10% sampling for background agent workflows
- Error sampling: 100% sampling for error spans (always capture failures)

---

## 10. Deployment and Rollback at Scale

### 10.1 Current Deployment Engine

The deployment engine at `/root/deployment-engine/` handles single-service deployments with 7 gates, pre-deploy backup, and auto-rollback. This pattern scales to multi-node deployments with the following extensions.

### 10.2 Phase 3 -- Multi-Node Deployment

**Problem:** Current deployment engine deploys to a single node. With a worker node, deployments must target the correct node.

**Solution:** Add node targeting to deployment engine.

```bash
# deploy-service.sh extension: --target-node flag
deploy-service.sh --service surplusai-scraper-agent-svc --target-node worker-01

# Preflight includes node verification
preflight-check.sh --ensure-node worker-01 --ensure-connectivity
```

**Service-to-node mapping configuration:**

```yaml
# /root/deployment-engine/node-map.yml
services:
  frgcrm-api:
    node: aiops-01
    replicas: 1
    depends_on: [litellm]
  
  surplusai-scraper-agent-svc:
    node: worker-01
    replicas: 1
    depends_on: [litellm]
  
  clickhouse:
    node: worker-01
    replicas: 1
    depends_on: [minio]
```

### 10.3 Phase 4 -- Rolling Updates

**Pattern for zero-downtime deployment:**

```yaml
# docker-compose.yml with rolling update config
deploy:
  mode: replicated
  replicas: 2
  update_config:
    parallelism: 1          # Update one replica at a time
    delay: 30s              # Wait 30s between updates
    order: start-first      # Start new before stopping old
    failure_action: rollback
    monitor: 60s            # Monitor for 60s after update
  rollback_config:
    parallelism: 0          # Rollback all at once
    order: stop-first       # Stop new before restoring old
```

**Service type considerations:**
- **Stateless APIs (frgcrm-api, surplusai-portal):** Rolling update with `start-first` order. Multiple versions coexist briefly -- no issue since stateless.
- **Stateful services (PostgreSQL, Redis):** Blue/green deployment with external data volume. Old container stays until new one passes health checks.
- **PM2 processes:** Current `env -i delete+start` pattern has ~5 second downtime. For zero-downtime, run two PM2 processes (v1 and v2) behind Nginx upstream, then remove v1.

### 10.4 Phase 5 -- Canary Deployments

**Pattern for risk mitigation:**

```
Step 1: Deploy v2 to 5% of traffic (Istio VirtualService weight=5)
Step 2: Monitor for 15 minutes (error rate, latency, business metrics)
Step 3: Increase to 25% if healthy
Step 4: Monitor for 30 minutes
Step 5: Increase to 50% if healthy
Step 6: Monitor for 1 hour
Step 7: Increase to 100%
Step 8: Decommission v1 after 24 hours of stability
```

**Automation:**

```bash
# /root/deployment-engine/canary-deploy.sh
canary-deploy.sh --service frgcrm-api --image frgcrm-api:v2.1.0 \
  --steps "5:15min,25:30min,50:1hr,100:24hr" \
  --rollback-on "error_rate>1%,p95_latency>500ms"
```

### 10.5 Rollback Capability at Every Scale

This section defines the rollback strategy for each scaling phase. Every scaling decision has a documented reverse path.

#### Phase 2 Rollbacks (Optimization)

| Change | Rollback Action | Time | Risk |
|--------|----------------|------|------|
| Container memory limits | Revert to previous docker-compose.yml limits | 30s | Low |
| PgBouncer deployment | Update DATABASE_URL to bypass PgBouncer | 60s | Low |
| Nginx caching | Comment out proxy_cache directives, reload | 5s | None |
| ClickHouse partitioning | Drop partitions, restore pre-partition data | 5min | Low (data preserved) |
| Prometheus retention change | Revert retention config, restart Prometheus | 30s | Low |

#### Phase 3 Rollbacks (Worker Node)

| Change | Rollback Action | Time | Risk |
|--------|----------------|------|------|
| Service migrated to worker | Stop on worker, restart on AIOPS from backup | 2min | Low |
| Entire worker node | Drain services back to AIOPS, remove node | 15min | Medium (capacity) |
| Tailscale cross-node comms | Fall back to direct IP if Tailscale down | 5min | Low |

#### Phase 4 Rollbacks (Swarm + Replicas)

| Change | Rollback Action | Time | Risk |
|--------|----------------|------|------|
| Docker Compose to Swarm | docker stack rm, docker compose up on previous config | 5min | Medium (downtime) |
| PostgreSQL read replica | Update PgBouncer to remove replica from pool | 30s | Low |
| Redis Sentinel | Stop Sentinel, configure apps for direct Redis | 2min | Medium (HA loss) |
| Nginx upstream changes | Revert upstream block, reload Nginx | 5s | None |
| Load balancer reconfiguration | Reload HAProxy with previous config | 5s | None |

#### Phase 5 Rollbacks (k3s + Multi-Region)

| Change | Rollback Action | Time | Risk |
|--------|----------------|------|------|
| Service migrated to k3s | kubectl delete deployment, restore Docker Swarm stack | 10min | Medium |
| HPA configuration | kubectl delete hpa, set static replica count | 30s | Low |
| Istio service mesh | istioctl uninstall --purge | 5min | High (mTLS loss) |
| Multi-region failover | Switch Cloudflare LB back to primary region | 60s | Low (tested quarterly) |
| Cross-region replication | Disable subscription, re-enable old primary | 5min | Medium (data sync) |

#### Rollback Testing Cadence

| Component | Test Frequency | Test Method |
|-----------|---------------|-------------|
| Container rollback | Monthly | deploy-service.sh rollback test |
| PM2 rollback | Monthly | pm2 delete + pm2 start from dump |
| PgBouncer bypass | Quarterly | Update DATABASE_URL, verify direct connect |
| Redis Sentinel failover | Quarterly | Stop Redis primary, verify automatic failover |
| PostgreSQL replica promotion | Quarterly (aligned with restore testing) | Promote replica, verify reads/writes |
| Docker Swarm node drain | Quarterly | Drain node, verify services reschedule |
| k3s pod rescheduling | Monthly | kubectl delete pod, verify redeployment |
| Istio traffic splitting | Monthly | Shift 100% traffic to canary, verify |
| Multi-region failover | Quarterly | Take primary region offline via Cloudflare |
| Full DR exercise | Annually | Complete failover to secondary region, run for 24h |

---

## 11. Cost Model

### 11.1 Current Monthly Infrastructure Costs

| Item | Provider | Monthly Cost | Notes |
|------|----------|-------------|-------|
| AIOPS (CPX51) | Hetzner | ~30 EUR | 16 vCPU, 32 GB, 360 GB NVMe |
| COREDB (CPX51) | Hetzner | ~30 EUR | 16 vCPU, 32 GB, 360 GB NVMe |
| EDGE (Hostinger VPS) | Hostinger | ~15 EUR | Shared VPS, being decommissioned |
| Tailscale | Tailscale | Free | Personal plan, <3 users |
| Cloudflare | Cloudflare | Free | Free plan for DNS + DDoS |
| Domain (wheeler.claw.engineer) | Namecheap | ~1 EUR | Annual cost |
| **Total** | | **~76 EUR/month** | |

**Cost per container:** 76 EUR / 41 containers = ~1.85 EUR/container/month
**Cost per PM2 process:** 76 EUR / 20 processes = ~3.80 EUR/process/month
**Cost per service:** 76 EUR / 61 services = ~1.25 EUR/service/month

### 11.2 Phase 3 Cost Projection (3-6 Months)

| Item | Monthly Cost | Cumulative |
|------|-------------|------------|
| Existing nodes | ~76 EUR | ~76 EUR |
| Worker CX32 | ~35 EUR | ~111 EUR |
| Cloudflare Pro | ~20 USD | ~131 EUR+USD |
| **Total** | | **~131 EUR+USD/month** |

**Cost per container (estimated at 50 containers):** ~2.62 EUR/container/month
**Cost per PM2 process (estimated at 25 processes):** ~5.24 EUR/process/month

### 11.3 Phase 4 Cost Projection (6-12 Months)

| Item | Monthly Cost | Cumulative |
|------|-------------|------------|
| Existing + Worker | ~111 EUR | ~111 EUR |
| Additional CX32 (Swarm manager) | ~35 EUR | ~146 EUR |
| PostgreSQL replica storage | ~10 EUR | ~156 EUR |
| Backup storage (2 TB) | ~20 EUR | ~176 EUR |
| **Total** | | **~176 EUR/month** |

### 11.4 Phase 5 Cost Projection (12+ Months)

| Item | EU Region | US Region | Total |
|------|-----------|-----------|-------|
| AIOPS (CPX51) | ~30 EUR | ~30 EUR | ~60 EUR |
| Worker (CX32) | ~35 EUR | ~35 EUR | ~70 EUR |
| COREDB (CPX51) | ~30 EUR | ~30 EUR | ~60 EUR |
| Cloudflare Pro | -- | -- | ~20 USD |
| Backup storage | ~10 EUR | ~10 EUR | ~20 EUR |
| Network egress | ~10 EUR | ~10 EUR | ~20 EUR |
| **Total** | | | **~250 EUR + ~20 USD/month** |

### 11.5 Per-Tenant Cost Breakdown

| Tier | Infrastructure Cost | Support Cost | Total Cost/Tenant | Recommended Price | Margin |
|------|--------------------|-------------|-------------------|-------------------|--------|
| Freemium | ~0.50 EUR | ~0.50 EUR | ~1.00 EUR | Free | N/A (acquisition) |
| Mid-Tier (Pro) | ~1.50 EUR | ~2.00 EUR | ~3.50 EUR | 997 USD/month | 99.6% |
| Enterprise | ~5.00 EUR | ~5.00 EUR | ~10.00 EUR | 2,997 USD/month | 99.7% |
| White-Label | ~15.00 EUR | ~15.00 EUR | ~30.00 EUR | 4,997 USD/month | 99.4% |

**Notes:**
- Infrastructure costs are essentially fixed for all tiers (same cluster, same nodes)
- Per-tenant cost is dominated by support and data storage, not compute
- At 100 paying tenants (mix of tiers), infrastructure cost per tenant is ~1.76 EUR
- Gross margin on all paid tiers exceeds 99% at current cost structure

### 11.6 Capacity Cost Curves

```
Node Count vs Capacity:

  1 node (current):  16 vCPU,  32 GB RAM,  360 GB disk -- ~30 EUR/month
  2 nodes (Phase 3): 24 vCPU,  64 GB RAM,  560 GB disk -- ~65 EUR/month (+117% cost, +50% CPU, +100% RAM)
  4 nodes (Phase 4): 32 vCPU, 128 GB RAM, 1.1 TB disk -- ~130 EUR/month (+333% cost, +100% CPU, +300% RAM)
  6 nodes (Phase 5): 48 vCPU, 192 GB RAM, 1.7 TB disk -- ~250 EUR/month (+733% cost, +200% CPU, +500% RAM)

Observations:
  - RAM scales fastest due to CX32 cost efficiency (32 GB per node at 35 EUR)
  - CPU scales slower (CX32 has 8 vCPU vs CPX51 16 vCPU)
  - Hetzner pricing is nearly linear -- no bulk discount below 10 nodes
```

**Recommendation:** Right-size node types. For CPU-heavy workloads, use CPX51 (16 vCPU, 32 GB). For RAM-heavy workloads, use CX32 (8 vCPU, 32 GB). Mix node types for cost efficiency.

### 11.7 Break-Even Analysis

**Scenario: SurplusAI platform monetization**

| Metric | Month 1 | Month 3 | Month 6 | Month 12 |
|--------|---------|---------|---------|----------|
| Infrastructure cost | ~131 EUR | ~131 EUR | ~176 EUR | ~250 EUR |
| Estimated MRR | $2.5K-7K | $17K-48K | $50K-123K | $200K+ |
| Infrastructure as % of revenue | ~2-5% | ~0.3-0.8% | ~0.1-0.4% | <0.1% |

**Conclusion:** Infrastructure costs are negligible relative to projected revenue. The scalability constraint is not cost -- it is operational complexity and architectural correctness.

### 11.8 Cost Optimization Opportunities

| Opportunity | Savings | Effort | Phase |
|-------------|---------|--------|-------|
| Right-size container limits | ~2 GB RAM freed | Low (1 day) | Phase 2 |
| ClickHouse TTL for old data | 40% disk reduction | Low (1 day) | Phase 2 |
| Prometheus retention tuning | 30% disk reduction | Low (1 day) | Phase 2 |
| Consolidate redundant agents | ~200 MB RAM | Medium (1 week) | Phase 2 |
| Decommission EDGE node entirely | ~15 EUR/month | Low (cleanup) | Phase 2 |
| Reserve Hetzner instances (annual commit) | ~20% discount | Medium (contract) | Phase 3+ |
| Use CX32 instead of CPX51 for worker | ~15 EUR/month per node | Low (ordering) | Phase 3+ |
| Object storage for logs (MinIO) | Reduces Loki storage cost | Medium (2 weeks) | Phase 3+ |

---

## 12. Rollback Capability for Every Scaling Decision

### 12.1 Principle

Every scaling decision in this document is designed with a documented reverse path. No change is irreversible. The rollback procedure for each phase is defined in the relevant section above; this section organizes them by architectural layer.

### 12.2 Hardware Rollback

| Action | Rollback | Downtime |
|--------|----------|----------|
| Add worker node | Drain services back to AIOPS, decommission node | <15 min |
| Add second region | Switch Cloudflare back to primary-only | <2 min |
| Upgrade node specs | Migrate to old node (if still available) | <30 min |
| Change provider | Reverse DNS, redeploy old config | <2 hours |

### 12.3 Container Orchestration Rollback

| Action | Rollback | Downtime |
|--------|----------|----------|
| Docker Compose to Swarm | docker stack rm, restart compose | <5 min |
| Swarm to k3s | kubectl delete deployment, restart Swarm stack | <10 min |
| Service mesh install | Uninstall Istio | <5 min |
| HPA config | Delete HPA, set static replica count | <30s |

### 12.4 Database Rollback

| Action | Rollback | Downtime |
|--------|----------|----------|
| PgBouncer deployment | Update DATABASE_URL to bypass | <60s |
| Read replica added | Remove from PgBouncer pool | <30s |
| Table partitioning | Select from parent table (partition transparent) | None |
| Schema-per-tenant | Revert search_path to public schema | <30s |
| Database-per-tenant | Point application to shared database | <2 min |
| Redis Sentinel | Stop Sentinel, direct connect | <2 min |
| Redis Cluster | Point app back to standalone instance | <5 min |

### 12.5 Network Rollback

| Action | Rollback | Downtime |
|--------|----------|----------|
| Nginx to HAProxy | Point DNS back to Nginx | <60s |
| Add rate limiting | Remove limit_req directives, reload | <5s |
| Enable caching | Clear cache, disable in Nginx | <5s |
| Tailscale reconfiguration | Previous Tailscale config backup | <2 min |
| Cloudflare LB | Disable load balancer, direct DNS | <2 min |

### 12.6 Service Migration Rollback

| Action | Rollback | Downtime |
|--------|----------|----------|
| Migrate PM2 to new node | Stop on new, start on old from PM2 dump | <2 min |
| Migrate Docker to new node | docker compose down on new, up on old | <2 min |
| Canary deployment | Route 100% traffic back to v1 | <30s |
| Rolling update failure | Auto-rollback via Docker Swarm | <60s |

### 12.7 Rollback Testing Schedule

| Test | Frequency | Description |
|------|-----------|-------------|
| Single-service rollback | Monthly | deploy-service.sh rollback test on each service type |
| Database connection fallback | Quarterly | Bypass PgBouncer, verify direct connection |
| Redis Sentinel failover | Quarterly | Take down Redis primary, verify automatic failover |
| Node drain | Quarterly | Drain AIOPS, verify worker handles load |
| Full region failover | Quarterly | Switch Cloudflare to backup region, verify for 1 hour |
| DR exercise | Annually | Complete failover to secondary region, run for 24 hours |

---

## 13. Risk Register

### 13.1 Scaling-Specific Risks

| Risk ID | Description | Phase | Severity | Likelihood | Mitigation |
|---------|-------------|-------|----------|------------|------------|
| S-001 | Worker node underprovisioned for offloaded workload | Phase 3 | MEDIUM | LOW | Start with 1 service, monitor for 1 week, add capacity |
| S-002 | Docker Swarm network partitioning | Phase 4 | HIGH | LOW | Tailscale mesh as backup; document manual recovery |
| S-003 | PostgreSQL replication lag exceeds failover RPO | Phase 4 | HIGH | MEDIUM | Monitor lag via Prometheus; tune wal_level and network |
| S-004 | Redis Sentinel split-brain | Phase 4 | MEDIUM | LOW | Minimum 3 Sentinel instances; quorum=2 |
| S-005 | k3s etcd cluster failure | Phase 5 | CRITICAL | LOW | Embedded etcd backed up to MinIO; recovery documented |
| S-006 | Cross-region network latency >100ms | Phase 5 | MEDIUM | MEDIUM | Async replication only; no synchronous cross-region ops |
| S-007 | HPA overprovisioning during traffic spikes | Phase 5 | MEDIUM | MEDIUM | Scale-up cooldown (2min); max replica caps; load test thresholds |
| S-008 | Service mesh adds >10% latency overhead | Phase 5 | MEDIUM | LOW | Perf test before enabling; selective mesh injection |
| S-009 | Cloudflare failover does not trigger | Phase 5 | HIGH | LOW | Quarterly failover testing; manual failover documented |
| S-010 | Cost overrun due to unused reserved instances | Any | LOW | MEDIUM | Use on-demand only; reserved instances only after 3 months stable utilization |

### 13.2 Risk Response Plans

**S-001 (Worker Underprovisioned):**
If the CX32 worker node runs out of memory or CPU during Phase 3:
1. Immediate: Move largest service back to AIOPS
2. Short-term: Increase CX32 to CX42 (16 vCPU, 32 GB, ~44 EUR/month)
3. Long-term: Evaluate workload profile before adding more nodes

**S-003 (Replication Lag):**
If PostgreSQL replication lag exceeds 30 seconds during Phase 4:
1. Check network latency between nodes (<1ms expected on Hetzner internal)
2. Verify WAL settings: `wal_level=logical`, `max_wal_senders=10`
3. Consider synchronous replication for critical databases
4. Monitor with: `SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag`

**S-007 (HPA Overprovisioning):**
If HPA scales up too aggressively:
1. Increase cooldown period to 5 minutes
2. Reduce max replicas to 4x baseline
3. Switch to custom metrics (request queue depth) vs resource metrics
4. Implement aggressive scale-down delay (15 min)

### 13.3 Anti-Patterns (What NOT to Do)

1. **Do not add Kubernetes before Phase 5.** The migration from Docker Compose to k3s is non-trivial and should only be undertaken when Docker Swarm's limitations are actually encountered (typically >50 containers or >5 nodes). Premature Kubernetes adds operational complexity without benefit.

2. **Do not split databases before Phase 4.** The current COREDB PostgreSQL handles all 4 databases with >70% headroom. Database splitting before hitting 50% capacity adds complexity without performance benefit.

3. **Do not add caching before measuring.** Nginx caching, Redis caching, and application-level caching all add complexity. Only add caching when measurements show it is needed (p95 latency >500ms, database query load >1000 QPS).

4. **Do not over-provision nodes.** The current 3-node architecture has 18-24 months of headroom for container/process growth. Adding nodes before they are needed increases cost without operational benefit.

5. **Do not skip rollback testing.** Every scaling phase introduces new failure modes. Rollback testing is not optional -- it is the safety net that allows aggressive scaling.

---

## 14. Implementation Roadmap

### 14.1 Phase 2: Optimization (0-3 Months)

**Start date:** Immediately
**Cost:** Minimal (operations time only)
**Risk:** Low

| Week | Task | Owner | Dependencies |
|------|------|-------|-------------|
| 1 | Right-size container memory limits | Infrastructure | Current metrics (complete) |
| 1 | Apply CPU limits to all containers | Infrastructure | Memory limits complete |
| 1 | Deploy PgBouncer on AIOPS | Database | Environment review |
| 1 | Configure ClickHouse TTL + partitioning | Data | ClickHouse access |
| 2 | Tune Prometheus retention periods | Monitoring | Configuration review |
| 2 | Enable Nginx micro-caching | Gateway | Nginx config review |
| 2 | Identify and consolidate redundant agent polling | Agents | Agent log review |
| 3-4 | Decommission EDGE node services completely | Infrastructure | Migration of last services |
| 4 | Deploy PgBouncer on COREDB | Database | Phase 2 PgBouncer success |
| 8-10 | Service-to-service circuit breakers (application code) | Engineering | Code review |
| 10-12 | Load test: verify Phase 2 capacity | QA | All Phase 2 tasks |

**Phase 2 exit criteria:**
- AIOPS RAM utilization reduced from 47% to <40%
- All containers have documented CPU and memory limits
- PgBouncer deployed and all services connecting through it
- ClickHouse TTL policy in effect
- Prometheus storage reduced by 30%
- Load test confirms <200ms p95 latency at 2x current traffic

### 14.2 Phase 3: Worker Node (3-6 Months)

**Start date:** Month 3
**Cost:** ~35 EUR/month (CX32)
**Risk:** Low-Medium

| Week | Task | Owner | Dependencies |
|------|------|-------|-------------|
| 1 | Order and configure Hetzner CX32 | Infrastructure | Budget approval |
| 1 | Join to Tailscale mesh | Infrastructure | Node provisioned |
| 1 | Join to UFW allowlist | Security | Tailscale IP assigned |
| 2 | Deploy stateless agents on worker (Wave 1) | Engineering | Node configured |
| 2 | Verify cross-node communication | QA | Wave 1 deployed |
| 3-4 | Migrate analytics workloads (Wave 2) | Data | Wave 1 stable |
| 4-6 | Migrate background agents (Wave 3) | Agents | Wave 2 stable |
| 8 | Run load test: full workload distributed | QA | All waves complete |
| 10 | Document node failure procedure | Operations | Load test complete |
| 12 | Run node drain test | Operations | Documentation complete |

**Phase 3 exit criteria:**
- Worker node handling all planned workloads
- AIOPS CPU <30%, RAM <35%
- All migrated services show equal or better performance
- Cross-node communication verified and monitored
- Node drain tested (all services return to AIOPS within 15 minutes)
- No regression in end-user facing API latency

### 14.3 Phase 4: Docker Swarm + Replicas (6-12 Months)

**Start date:** Month 6
**Cost:** ~35-70 EUR/month (additional nodes)
**Risk:** Medium

| Month | Task | Owner | Dependencies |
|------|------|-------|-------------|
| 6 | Add Docker-compose deploy sections to all stacks | Engineering | All stacks reviewed |
| 7 | Initialize Docker Swarm on 2 nodes | Infrastructure | Test environment ready |
| 7 | Migrate 2-3 low-risk stacks to Swarm | Engineering | Swarm initialized |
| 8 | Deploy PostgreSQL read replica on AIOPS | Database | Swarm operational |
| 8 | Configure PgBouncer read/write splitting | Database | Read replica operational |
| 9 | Deploy Redis Sentinel (3 instances) | Database | Read/write split stable |
| 9 | Migrate remaining stacks to Swarm | Engineering | Previous stacks stable |
| 10 | Load test: node failure scenario | QA | All stacks in Swarm |
| 10 | Test Redis Sentinel failover | QA | Sentinel operational |
| 11 | Test PostgreSQL replica promotion | QA | Replica operational |
| 12 | Full DR test (node failure, replica fail, restore) | Operations | All tests passing |

**Phase 4 exit criteria:**
- All 12 Docker Compose stacks deployable as Docker Stack services
- PostgreSQL read replicas operational with <1s replication lag
- Redis Sentinel configured with automated failover tested
- Zero downtime during single-node failure (tested)
- All services have at least 2 replicas across at least 2 nodes
- Rolling updates work with zero downtime
- Full DR test passes within RPO/RTO targets

### 14.4 Phase 5: k3s + Multi-Region (12+ Months)

**Start date:** Month 12
**Cost:** ~250 EUR/month (full cluster, both regions)
**Risk:** Medium-High

| Month | Task | Owner | Dependencies |
|-------|------|-------|-------------|
| 12 | Install k3s on single node (parallel to Docker) | Infrastructure | R&D environment |
| 12 | Convert 2-3 Docker Compose stacks to k3s manifests | Engineering | k3s operational |
| 13 | Deploy stateless services on k3s | Engineering | Manifests tested |
| 13 | Migrate stateful services (DBs stay on COREDB for now) | Engineering | Stateless services stable |
| 14 | Deploy HPA for target services | Infrastructure | All services in k3s |
| 14 | Install and configure Istio mesh | Network | k3s stable |
| 15 | Configure mTLS for all services | Security | Istio operational |
| 15 | Deploy OpenTelemetry + Jaeger | Monitoring | Istio operational |
| 16 | Load test: full k3s cluster | QA | All services migrated |
| 16 | Document k3s operations | Operations | Load test complete |
| 18 | Provision US region Hetzner nodes | Infrastructure | k3s stable >30 days |
| 18 | Configure cross-region PG replication | Database | US nodes ready |
| 19 | Deploy k3s on US region | Infrastructure | Cross-region replication stable |
| 19 | Configure Cloudflare global load balancer | Network | Both regions operational |
| 20 | Cross-region failover test | QA | Cloudflare LB configured |
| 22 | Full DR exercise: failover to US for 24 hours | Operations | All tests passing |
| 24 | Review multi-region cost vs. benefit | Executive | 6 months operational data |

**Phase 5 exit criteria:**
- k3s cluster operational on all nodes
- HPA verified with load test (scales up/down correctly)
- Istio mesh enabling mTLS between all services
- Jaeger distributed tracing for all revenue-critical paths
- Multi-region failover <5 minutes RTO
- Cross-region replication lag <60 seconds P99
- Cost per tenant <5 EUR/month at 100 tenants
- Full DR exercise completed with documented results

### 14.5 Architecture Decision Records (ADRs)

For each scaling phase, an ADR must be created before implementation begins:

| ADR ID | Title | Phase | Required Before |
|--------|-------|-------|-----------------|
| ADR-001 | PgBouncer connection pooling vs. application-level pooling | Phase 2 | PgBouncer deployment |
| ADR-002 | Worker node service selection criteria | Phase 3 | CX32 ordering |
| ADR-003 | Docker Swarm vs. Nomad vs. continuing with Compose | Phase 4 | Swarm initialization |
| ADR-004 | PostgreSQL replication method (streaming vs. logical) | Phase 4 | Replica deployment |
| ADR-005 | Redis Sentinel vs. Redis Cluster | Phase 4 | Sentinel deployment |
| ADR-006 | k3s vs. microk8s vs. k0s | Phase 5 | k3s installation |
| ADR-007 | Istio vs. Linkerd for service mesh | Phase 5 | Mesh installation |
| ADR-008 | Multi-region strategy (active-active vs. active-passive) | Phase 5 | Region 2 provisioning |

---

## Appendix A: Key Metrics Dashboard

A Grafana dashboard must track these metrics for scalability monitoring:

### Infrastructure Metrics
```
CPU utilization (per node, per container)
RAM utilization (per node, per container)
Disk utilization (per node, per volume)
Network throughput (per node, per interface)
Node temperature (Hetzner API)
```

### Container/Process Metrics
```
Docker container count
PM2 process count
Container restart rate
PM2 restart rate
Container health check pass/fail
Service uptime percentage
```

### Database Metrics
```
PostgreSQL connections (total, active, waiting)
PostgreSQL query latency (p50, p95, p99)
PostgreSQL replication lag
Redis memory utilization
Redis hit rate
Redis connected clients
ClickHouse query latency
Neo4j query latency
```

### Network Metrics
```
Nginx connections (active, waiting)
Nginx latency (p50, p95, p99)
Nginx error rate (4xx, 5xx per vhost)
HAProxy backend health
Tailscale mesh latency
Cross-node traffic volume
```

### Business Metrics (Revenue-Aligned)
```
API requests per minute (per service)
Active tenants
Active users
Active agents
Pipeline DAG success rate
Event bus throughput
Lead processing rate
```

---

## Appendix B: Estimated Capacity by Phase

| Metric | Phase 1 (Current) | Phase 2 (Optimized) | Phase 3 (Worker) | Phase 4 (Swarm) | Phase 5 (k3s + Multi-Region) |
|--------|-------------------|--------------------|------------------|-----------------|------------------------------|
| Total vCPU | 32 | 32 | 40 | 48 | 96 (2 regions) |
| Total RAM | 64 GB | 64 GB | 96 GB | 128 GB | 256 GB |
| Total Disk | 720 GB | 720 GB | 920 GB | 1.3 TB | 2.6 TB |
| Docker containers | 41 | 45 | 55 | 70 | 140 |
| PM2 processes | 20 | 22 | 30 | 40 | 80 |
| Max tenants | 3 | 10 | 25 | 100 | 500+ |
| DB connections | 48 | 200 (PgBouncer) | 400 | 800 | 2000+ |
| Redis throughput | 5K ops/s | 5K ops/s | 10K ops/s | 50K ops/s | 100K ops/s |
| API throughput | 100 req/s | 200 req/s | 500 req/s | 2000 req/s | 10000 req/s |
| Log ingestion | 5 GB/day | 5 GB/day | 10 GB/day | 50 GB/day | 200 GB/day |
| Metrics series | 50K | 50K | 100K | 250K | 1M |
| Storage (DB) | 15 GB | 20 GB | 50 GB | 200 GB | 1 TB |
| PgBouncer connections | 0 (not deployed) | 200 | 400 | 800 | 2000 |
| PostgreSQL replicas | 0 | 0 | 0 | 2 | 6 (3 per region) |
| Redis nodes | 3 standalone | 3 standalone | 3 standalone | 6 (Sentinel) | 12 (Cluster) |
| Load balancer | Nginx single | Nginx + cache | HAProxy | HAProxy + Nginx | Istio + Cloudflare LB |
| Service mesh | None | None | None | Tailscale mTLS | Istio full mesh |
| Multi-region | No | No | No | No | Yes (EU + US) |
| Auto-scaling | Manual | Manual | Manual PM2 | Docker Swarm | k3s HPA |
| Monthly cost | ~76 EUR | ~76 EUR | ~111 EUR | ~176 EUR | ~250 EUR + ~20 USD |

---

## Appendix C: Migration Path Summary (Current to Target)

```
Current Architecture (2026-05-24)
  ├── 3 nodes (2 active)
  ├── Docker Compose (12 stacks)
  ├── PM2 processes (20)
  ├── Single Nginx gateway
  ├── Direct DB connections
  ├── Single-node monitoring
  └── Single-region

        │
        ▼  Phase 2 (0-3 months)

Optimized Architecture
  ├── Same 3 nodes
  ├── Right-sized containers (CPU/memory limits)
  ├── PgBouncer connection pooling
  ├── ClickHouse TTL + partitioning
  ├── Prometheus retention tuned
  ├── Nginx caching enabled
  └── EDGE node decommissioned

        │
        ▼  Phase 3 (3-6 months)

Worker Node Architecture
  ├── 4 nodes (AIOPS, COREDB, Worker, Hostinger-legacy)
  ├── Stateless agents on Worker node
  ├── Analytics (ClickHouse) on Worker node
  ├── Cross-node Tailscale communication
  ├── AIOPS retains: Nginx, LiteLLM, control plane
  └── COREDP retains: All databases

        │
        ▼  Phase 4 (6-12 months)

Highly Available Architecture
  ├── 4-6 nodes (Docker Swarm)
  ├── All services as Docker Stack (replicas >= 2)
  ├── PostgreSQL read replicas (AIOPS, Worker)
  ├── Redis Sentinel (3 instances)
  ├── HAProxy load balancer
  ├── Rolling updates with zero downtime
  └── Single-node failure tolerated

        │
        ▼  Phase 5 (12+ months)

Multi-Region Enterprise Architecture
  ├── 8+ nodes across 2 regions (k3s)
  ├── HPA for all stateless services
  ├── Istio service mesh with mTLS
  ├── Distributed tracing (Jaeger)
  ├── Cross-region PostgreSQL replication
  ├── Redis Cluster (6+ nodes)
  ├── Cloudflare global load balancer
  ├── Regional failover <5 min RTO
  └── Cost per tenant <5 EUR/month at scale
```

---

## Appendix D: Glossary

| Term | Definition |
|------|------------|
| HPA | Horizontal Pod Autoscaler -- automatically scales Kubernetes pod replicas based on CPU/memory/custom metrics |
| k3s | Lightweight Kubernetes distribution by Rancher, ~50 MB binary |
| Docker Swarm | Docker-native container orchestration, built into Docker Engine |
| Istio | Service mesh providing mTLS, traffic routing, and telemetry |
| Thanos | Prometheus HA extension with global query and unlimited retention |
| PgBouncer | Lightweight PostgreSQL connection pooler |
| Redis Sentinel | High availability solution for Redis with automatic failover |
| Tailscale | WireGuard-based mesh VPN for inter-node networking |
| mTLS | Mutual TLS -- both client and server authenticate with certificates |
| RPO | Recovery Point Objective -- maximum acceptable data loss |
| RTO | Recovery Time Objective -- maximum acceptable downtime |
| QPS | Queries Per Second |
| TTL | Time To Live (data retention period) |
| HVM | Hardware Virtual Machine (Hetzner instance type) |
| CPX51 | Hetzner instance: 16 vCPU, 32 GB RAM, 360 GB NVMe |
| CX32 | Hetzner instance: 8 vCPU, 32 GB RAM, 200 GB SSD |

---

*End of Platform Scalability Plan v1.0*

**Next Review Date:** 2026-08-24 (quarterly)
**Owner:** Wheeler Brain OS -- Infrastructure Engineering
**Related Documents:**
- `/root/AUTONOMOUS_AIOPS_ARCHITECTURE.md` -- Infrastructure topology
- `/root/WHEELER_REVENUE_ENGINE_ARCHITECTURE.md` -- Capacity planning context
- `/root/SURPLUSAI_PRODUCTIZATION_PLAN.md` -- Section 12 capacity planning
- `/root/DEPLOYMENT_SYSTEM.md` -- Deployment and rollback architecture
- `/root/SELF_HEALING_ENGINE.md` -- Self-healing and auto-remediation
