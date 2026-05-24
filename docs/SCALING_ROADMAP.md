# Wheeler Ecosystem Scaling Roadmap

> **Phase 14 — Scaling Roadmap**  
> Principal Scalability Engineering  
> Date: 2026-05-23

---

## Executive Summary

The Wheeler ecosystem has significant scaling headroom but is currently bottlenecked by:
1. **EDGE server CPU steal** — hypervisor overcommitment limits all frontend scaling
2. **AIOPS Docker daemon overhead** — 150% CPU consumed by container management
3. **COREDB extreme under-utilization** — 97% RAM free, ready to absorb workloads
4. **No horizontal worker scaling** — all workers are single-instance PM2 fork processes
5. **No queue-based load leveling** — direct fire-and-forget creates cascading failure risk

This roadmap defines incremental scaling from current capacity to 10× current throughput.

---

## Current Capacity Assessment

| Dimension | Current Limit | Constraint | Headroom |
|---|---|---|---|
| API requests/sec | ~20 RPS (estimated) | EDGE CPU steal, single-instance workers | 2-5× with fixes |
| AI completions/sec | ~5 (estimated) | LiteLLM single instance, model rate limits | 3× with batching |
| Database connections | 100 (default max_connections) | PostgreSQL config | 2× with pooling |
| Concurrent claimants processed | ~50/min | Single-threaded enrichment | 10× with queue workers |
| Edge concurrent connections | ~100 (estimated) | CPU steal limits nginx workers | 5× after VM migration |
| Storage capacity | 338GB × 3 = ~1TB | EDGE disk 62% full | 3× on COREDB |

---

## Phase 14.1 — Immediate Scaling Fixes (24 Hours)

### Fix 1: Resolve EDGE CPU Steal
**Problem**: 66-80% CPU steal time starves all EDGE workloads.
**Solution**: Migrate EDGE VM to a dedicated-CPU instance or different hypervisor.
**Hetzner Options**:
- CCX23 (4 dedicated vCPU, 16GB, €33/mo) — if workload fits
- CCX33 (8 dedicated vCPU, 32GB, €66/mo) — 1:1 replacement
- CX41 (8 vCPU, 16GB, €31/mo) — risk of same steal issue
**Recommendation**: CCX33 with dedicated CPU — eliminates steal time completely.

### Fix 2: Stop Temporal Crash Loop on EDGE
**Problem**: temporal-temporal-1 container in continuous crash loop consuming resources.
**Solution**: 
```bash
docker stop temporal-temporal-1
# Investigate root cause before restarting
docker logs temporal-temporal-1 --tail 100
```

### Fix 3: Migrate 3 AIOPS PostgreSQL Instances to COREDB
**Problem**: AIOPS Docker daemon running at 150% CPU managing 3 PostgreSQL containers.
**Solution**: Move prediction-radar-db, aiops-ravynai-postgres, frgops-standby databases to COREDB's wheeler-postgres as separate databases.
**Benefit**: Reduces AIOPS CPU by ~36% (3 × 12% PostgreSQL), reduces memory by ~500MB.

---

## Phase 14.2 — Horizontal Worker Scaling (7 Days)

### Agent Worker Pool

**Current**: 9 × single-instance PM2 fork agent-svc processes (~1GB RAM, 0% CPU idle).
**Target**: 3 × clustered agent-worker processes, each with 4 instances.

```javascript
// PM2 cluster mode for agent workers
{
  name: "agent-worker",
  script: "worker.py",
  instances: 4,           // 4 per process → 12 total
  exec_mode: "cluster",
  max_memory_restart: "512M",
  env: {
    WORKER_TYPE: "agent",
    QUEUE_URL: "redis://5.78.210.123:6379",
    CONCURRENCY: "5"
  }
}
```

**Scaling triggers**:
- Queue depth > 500 → add 2 instances
- P95 task age > 120s → add 4 instances
- Worker CPU > 80% sustained → add instances

### API Server Scaling

**Current**: frgcrm-api single fork instance (236MB).
**Target**: frgcrm-api in cluster mode with 4 instances.

```javascript
{
  name: "frgcrm-api",
  script: "main.py",
  instances: 4,
  exec_mode: "cluster",
  max_memory_restart: "512M",
  env: {
    WORKERS_PER_INSTANCE: "2"  // uvicorn workers
  }
}
```

**Effective concurrency**: 4 instances × 2 uvicorn workers = 8 concurrent request handlers.

---

## Phase 14.3 — Database Scaling (14 Days)

### PostgreSQL

| Parameter | Current | Optimized | Rationale |
|---|---|---|---|
| shared_buffers | Default (128MB) | 8GB | 25% of COREDB 30GB RAM |
| work_mem | Default (4MB) | 32MB | For sort operations |
| maintenance_work_mem | Default (64MB) | 1GB | For VACUUM/ANALYZE |
| effective_cache_size | Default (4GB) | 24GB | 80% of RAM for OS cache |
| max_connections | Default (100) | 50 + pgbouncer (200) | Connection pooling |
| wal_level | Default (replica) | replica (keep) | For point-in-time recovery |
| max_wal_size | Default (1GB) | 4GB | Reduce checkpoint frequency |
| checkpoint_timeout | Default (5min) | 15min | Reduce write pressure |
| random_page_cost | Default (4.0) | 1.1 | SSD optimization |
| effective_io_concurrency | Default (1) | 200 | NVMe concurrency |

### Connection Pooling (PgBouncer)

```ini
# pgbouncer.ini for COREDB
[databases]
wheeler = host=localhost port=5432 dbname=wheeler
prediction_radar = host=localhost port=5432 dbname=prediction_radar
ravynai = host=localhost port=5432 dbname=ravynai

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 200
default_pool_size = 25
reserve_pool_size = 5
reserve_pool_timeout = 3
```

### Read Replica Path (Future — at 10× current load)

```
COREDB (primary) ──streaming replication──▶ COREDB-REPLICA (read-only)
                                                │
                                                ├── Analytics queries
                                                ├── Dashboard queries
                                                └── Reporting queries
```

---

## Phase 14.4 — Redis Scaling (14 Days)

### Current Architecture
```
AIOPS: docuseal-redis, prediction-radar-app-redis
COREDB: wheeler-redis
EDGE: usesend-redis
```
Four separate Redis instances, no shared cache, no replication.

### Target Architecture

```
┌──────────────────────────────────────────┐
│           COREDB (Primary Redis)          │
│  Redis 7 — 2GB maxmemory                 │
│  Namespaces:                              │
│    cache:     (all app caches)            │
│    queue:     (ARQ/BullMQ job queues)     │
│    session:   (user sessions)             │
│    rate:      (rate limit counters)       │
│    ai:        (LiteLLM semantic cache)    │
│    emb:       (embedding cache)           │
│    enrichment:(claimant enrichment cache) │
└──────────────────────────────────────────┘
          │
          ├── Redis Sentinel (auto-failover)
          │
          └── COREDB-REPLICA (Redis replica, future)
```

### Scaling Triggers

| Metric | Scale Action |
|---|---|
| Memory > 70% of maxmemory | Increase maxmemory to 4GB |
| Ops/sec > 50,000 | Add Redis replica for read scaling |
| Latency > 5ms P99 | Check for big keys, enable lazyfree |
| Evictions > 0 | Tune maxmemory-policy or increase memory |

---

## Phase 14.5 — AI Worker Scaling (30 Days)

### LiteLLM Horizontal Scaling

**Current**: Single LiteLLM instance (361MB, fork mode, 5 restarts).
**Target**: LiteLLM cluster with shared Redis cache.

```javascript
{
  name: "litellm",
  script: "litellm",
  args: "--config /etc/litellm/config.yaml --port 4000",
  instances: 2,              // 2 load-balanced instances
  exec_mode: "cluster",
  max_memory_restart: "512M",
  env: {
    REDIS_URL: "redis://5.78.210.123:6379",
    LITELLM_CACHE_TYPE: "redis"
  }
}
```

### AI Provider Concurrency Limits

| Provider | Current Limit | Recommended | Rationale |
|---|---|---|---|
| DeepSeek | Unknown | 50 concurrent | API tier limit |
| Anthropic | Unknown | 20 concurrent | Tier 2 default |
| OpenAI | Unknown | 30 concurrent | Tier 2 default |

### Token Batching Strategy

```python
# Batch multiple agent requests into single API call
async def batched_agent_call(prompts: list[str], model: str, max_batch: int = 5):
    """Batch up to 5 agent prompts into one API call to reduce overhead."""
    batches = [prompts[i:i+max_batch] for i in range(0, len(prompts), max_batch)]
    results = []
    for batch in batches:
        # Combine prompts with separator tokens
        combined = "\n---\n".join(batch)
        result = await litellm.acompletion(model=model, messages=[
            {"role": "user", "content": combined}
        ])
        results.append(result)
    return results
```

---

## Phase 14.6 — MinIO / Object Storage Scaling (60 Days)

### Current State
- Single MinIO instance on COREDB (6h uptime)
- Used for document storage, backups, model artifacts

### Scaling Path
1. **Short-term**: Increase MinIO disk allocation on COREDB (2% used → up to 50%)
2. **Medium-term**: MinIO distributed mode across 2 drives
3. **Long-term**: MinIO federation for multi-region

---

## Phase 14.7 — Edge / Frontend Scaling (7 Days)

### Prerequisites
1. **Resolve CPU steal first** — no amount of edge tuning helps with 66-80% steal
2. **Enable Nginx caching** — reduce upstream calls by 40-60%
3. **Enable gzip/brotli compression** — reduce bandwidth by 60-80%

### After Fixing CPU Steal

```nginx
# Optimized nginx for 8 dedicated cores
worker_processes auto;           # 8 workers
worker_connections 2048;         # 16K total connections
worker_rlimit_nofile 65535;

events {
    use epoll;
    multi_accept on;
    worker_connections 2048;
}

http {
    # Connection handling
    keepalive_timeout 65;
    keepalive_requests 1000;
    
    # Compression
    gzip on;
    gzip_comp_level 5;
    gzip_types text/plain text/css application/json application/javascript text/xml;
    
    # Buffers
    client_body_buffer_size 16k;
    client_max_body_size 50m;
    
    # Static file caching
    open_file_cache max=10000 inactive=30s;
    open_file_cache_valid 60s;
    open_file_cache_min_uses 2;
}
```

---

## Phase 14.8 — Multi-Region / HA Path (90 Days)

### Target Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│    EDGE       │     │    AIOPS      │     │    COREDB    │
│  Nuremberg    │     │  Falkenstein  │     │  Falkenstein │
│  (CCX33)      │     │  (CPX51)      │     │  (CX31/CPX31)│
├──────────────┤     ├──────────────┤     ├──────────────┤
│ Traefik      │────▶│ PM2 workers   │────▶│ PostgreSQL   │
│ Nginx cache  │     │ Queue workers │     │ Redis        │
│ SSL term.    │     │ LiteLLM       │     │ MinIO        │
│ Static files │     │ Agent workers │     │ PgBouncer    │
│ Frontend     │     │ APIs          │     │ Backups      │
└──────────────┘     └──────────────┘     └──────────────┘
       │                     │                     │
       └─────────────────────┴─────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   MONITORING    │
                    │  (Distributed)  │
                    ├────────────────┤
                    │ Grafana (COREDB)│
                    │ Prometheus      │
                    │ Loki            │
                    │ UptimeKuma      │
                    └────────────────┘
```

### Future: Read Replicas

```
                    ┌─── COREDB Primary (write)
                    │
    ┌───────────────┼───────────────┐
    │               │               │
    ▼               ▼               ▼
COREDB-RO-1    COREDB-RO-2    Analytics-RO
(API reads)    (Agent reads)  (Reporting)
```

---

## Scaling Decision Matrix

| Trigger | Metric | Action | Timeline |
|---|---|---|---|
| API latency P95 > 500ms | Prometheus | Add API worker instances | Immediate (auto-scale) |
| Queue depth > 1000 | Queue health endpoint | Add queue worker instances | 5 min (auto-scale) |
| DB connections > 40 | pg_stat_activity | Enable PgBouncer, add pool | 1 hour |
| Redis memory > 70% | Redis INFO | Increase maxmemory or add replica | 1 day |
| Disk > 80% on EDGE | df -h | Clean logs, migrate data to COREDB | 1 day |
| AI rate limit errors | LiteLLM metrics | Add provider fallback, reduce concurrency | 1 hour |
| CPU steal > 10% on EDGE | top %st | Migrate VM to dedicated CPU host | 1 week |
| MinIO > 50% disk | MinIO metrics | Add disk or enable distributed mode | 1 week |

---

## Capacity Planning: 10× Growth

| Resource | Current Usage | 10× Projected | Required Upgrade |
|---|---|---|---|
| API throughput | ~20 RPS | 200 RPS | 8→16 API worker instances |
| AI completions | ~5/sec | 50/sec | LiteLLM cluster (3 instances) + provider tier upgrade |
| Database QPS | ~100 (estimated) | 1000 | Read replicas + PgBouncer + query cache |
| Redis ops | ~5000/sec (estimated) | 50000/sec | Redis cluster or Redis Enterprise |
| Storage | ~300GB | 3TB | MinIO distributed (4 drives) |
| Network bandwidth | ~10 Mbps (estimated) | 100 Mbps | Hetzner 1 Gbps (included) |

### 10× Monthly Cost Estimate

| Component | Current (€/mo) | 10× Target (€/mo) |
|---|---|---|
| EDGE (CCX33) | 66 | 66 |
| AIOPS (CPX51) | 74 | 74 |
| COREDB (CPX51→CX31) | 74 → 13 | 13 |
| Read replica (CX31) | 0 | 13 |
| AI API costs | 250-800 | 800-2000 |
| **Total** | **~390-940** | **~966-2166** |

**Cost per unit scales sub-linearly** — 10× throughput for ~2.5× infrastructure cost.

---

## Templates Generated

- `/root/templates/scaling/pgbouncer.ini` — Connection pooler config
- `/root/templates/scaling/pm2-cluster-workers.config.js` — Clustered PM2 config
- `/root/templates/scaling/nginx-scaled.conf` — Optimized nginx for dedicated CPU
- `/root/templates/scaling/redis-namespaces.conf` — Redis namespace configuration
- `/root/templates/scaling/apply-scaling-phase1.sh` — Safe Phase 1 deployment
