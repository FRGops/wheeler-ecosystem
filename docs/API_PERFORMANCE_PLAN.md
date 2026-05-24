# Wheeler Ecosystem -- Phase 6: API Performance Optimization Plan

**Date:** 2026-05-23
**Target:** AIOPS (5.78.140.118) -- 16 CPU cores, 31 GB RAM, 17 GB used
**Status:** READ-ONLY AUDIT -- plan generation only

---

## 1. Executive Summary

The Wheeler ecosystem runs 18 PM2-managed API/services plus 22 Docker containers on a single 16-core AIOPS host. All PM2 services operate in `fork_mode` with a single instance, severely underutilizing available CPU cores. The system exhibits several categories of performance risk: blocking synchronous I/O in the primary API (frgcrm-api), missing timeout configurations across all Express-based agent services, a single-point-of-failure at the LiteLLM proxy, no job queue for background work, and aggressive PM2 restart behavior that risks retry storms.

**Risk Matrix:**

| Risk Area | Severity | Impact | Likelihood |
|-----------|----------|--------|------------|
| LiteLLM SPOF | CRITICAL | All 9 agent-svcs stall | Medium |
| Sync DB in FastAPI | HIGH | Thread pool exhaustion | High |
| Missing Express timeouts | HIGH | Connection leaks, DoS | High |
| No job queue | MEDIUM | Blocking API endpoints | High |
| PM2 restart storm | MEDIUM | Cascade failure | Medium |
| No response caching | MEDIUM | Repeated expensive DB queries | High |
| Connection pool over-subscription | MEDIUM | PostgreSQL saturation | Medium |
| Worker underutilization | LOW | Wasted CPU capacity | High |

---

## 2. Environment Audit

### 2.1 System Resources (AIOPS)

```
CPU:    16 cores
RAM:    31 GB total, 17 GB used, 13.6 GB available
Swap:   8 GB, 0 used
Disk:   338 GB total, 52 GB used (16%)
Load:   4.31 / 3.20 / 2.53 (moderate for 16-core)
Uptime: 14 days
```

### 2.2 PM2 Services Inventory

| Service | Port | Mode | Inst | Memory | Restarts | Notes |
|---------|------|------|------|--------|----------|-------|
| frgcrm-api | 8082 | fork | 1 (2 uvicorn workers) | 236 MB | 4 | FastAPI, largest API |
| litellm | 4049 | fork | 1 | 361 MB | 5 | LLM proxy, **SPOF** |
| design-agent-svc | 8020 | fork | 1 | 116 MB | 0 | Express, polling 5min |
| horizon-agent-svc | 8006 | fork | 1 | 109 MB | 0 | Express, polling 5min |
| frgcrm-agent-svc | 8003 | fork | 1 | 101 MB | 0 | Express, polling 5min |
| insforge-agent-svc | 8013 | fork | 1 | 73 MB | 0 | Express, polling 5min |
| paperless-agent-svc | 8009 | fork | 1 | 107 MB | 0 | Express, polling 5min |
| prediction-radar-agent-svc | 8011 | fork | 1 | 107 MB | 0 | Express, polling 5min |
| ravyn-agent-svc | 8005 | fork | 1 | 108 MB | 0 | Express, polling 5min |
| surplusai-scraper-agent-svc | 8007 | fork | 1 | 108 MB | 0 | Express, polling 5min |
| voice-agent-svc | 8008 | fork | 1 | 107 MB | 0 | Express, polling 5min |
| openclaw-dashboard | 8110 | fork | 1 | 67 MB | 0 | Node/Express |
| war-room-server | 6399 | fork | 1 | 65 MB | 1 | Node/Express |
| voice-outreach-service | - | fork | 1 | 54 MB | 0 | Voice calls |
| event-bus-relay | - | fork | 1 | 66 MB | 0 | Event relay |
| ecosystem-guardian | - | fork | 1 | 70 MB | 0 | Health checks |
| pm2-logrotate | - | fork | 1 | 94 MB | 0 | Log rotation |

**Total PM2 memory:** ~2.1 GB across 18 processes.

### 2.3 Docker API Services

| Container | Host Port | Status | Notes |
|-----------|-----------|--------|-------|
| prediction-radar-app-api | (internal) | healthy | Python, connects to AI gateway |
| aiops-ravynai-app | 8007 | healthy | Node v20, PostgreSQL |
| prediction-radar-app-web | 8098 | up | Nginx frontend |
| langflow | 7860 | up | AI workflow builder |

### 2.4 Port / API Map

| Port | Service | Type | Response Time |
|------|---------|------|---------------|
| 4049 | LiteLLM proxy (Swagger) | Python/LiteLLM | N/A (HTML UI) |
| 8082 | FRG CRM API | FastAPI/uvicorn | Sub-ms (health) |
| 8091 | (uvicorn service) | Python | N/A (HTML UI) |
| 8095 | FastAPI app | Python | Sub-ms |
| 8110 | OpenClaw Dashboard | Node | N/A (HTML UI) |
| 6399 | War Room Server | Node | N/A |
| 3001 | Uptime Kuma | Docker | 2ms |
| 3002 | Grafana | Docker | 1ms |
| 5000 | ChangeDetection | Docker | 9ms |
| 8080 | Dockge test nginx | Docker | <1ms |
| 9090 | Prometheus | Docker | <1ms |

---

## 3. Detailed Findings

### 3.1 Worker Saturation Analysis

**Current State:**
- 16 CPU cores available
- 11 API workers total (2 uvicorn + 9 Express single-thread)
- CPU utilization: ~25% (load 4.3/16)
- All PM2 services are `fork_mode` with 1 instance

**Problem:** 9 agent-svc Express processes each handle only 1 concurrent request by default (Node.js event loop is single-threaded). Under load, requests queue up sequentially. With `fork_mode`, PM2 cannot auto-scale or load-balance across instances.

**Recommendation:**
- Convert agent-svc services to `cluster_mode` with `instances: 2` (requires Node.js `cluster` module support or PM2 cluster mode)
- frgcrm-api: increase uvicorn workers from 2 to 4-6 (but monitor memory -- each worker loads all models, adding ~150-200 MB)
- Total target: ~25-30 API workers across 16 cores

### 3.2 Blocking I/O in FRG CRM API

**Finding:** The FRG CRM API (FastAPI) uses synchronous SQLAlchemy throughout:

```python
# database.py -- synchronous session
engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_size=30, max_overflow=50)

def get_db():
    db = SessionLocal()
    try:
        db.execute(text(f"SET LOCAL statement_timeout = '{_DEFAULT_STATEMENT_TIMEOUT_MS}ms'"))
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
```

All route handlers use `db: Session = Depends(get_db)` which creates a synchronous database session. FastAPI runs these in a thread pool (default 40 threads), but under heavy load the thread pool saturates and requests queue.

**Impact:** Under high concurrency, all 40 thread pool slots can be consumed by slow database queries, causing request queuing. The `pool_size=30` with `max_overflow=50` means up to 80 concurrent database connections per worker process (160 total across 2 uvicorn workers), which can overwhelm PostgreSQL.

**Recommendation:** See Section 6 (Async Migration Plan).

### 3.3 Missing Timeout Configurations

**Express Agent Services:** None of the 9 agent-svc processes configure HTTP timeouts:

```typescript
// Current (all agent-svc)
app.listen(config.port, () => console.log(`[svc] on :${config.port}`));

// Missing:
// server.timeout = 30000;
// server.keepAliveTimeout = 65000;
// server.headersTimeout = 66000;
```

Node.js defaults: `server.timeout = 0` (no timeout), meaning a slow client can hold a connection indefinitely. `keepAliveTimeout = 5000ms` means connections drop quickly, forcing reconnection overhead.

**FRG CRM API:**
- Statement timeout: 10 seconds (good)
- Uvicorn started with `--workers 2` but no `--timeout-keep-alive`, `--limit-concurrency`, or `--backlog` flags
- Default uvicorn timeout is 60s for keep-alive connections

**GovRider Client (Horizon agent):** Good pattern -- uses `AbortSignal.timeout(30000)` on external API calls.

### 3.4 Retry Storm Risk

**PM2 Restart Configuration:**

```
frgcrm-api:         max_restarts=5,  restart_delay=5000ms
agent-svc (all 9):  max_restarts=10, restart_delay=5000ms
```

All 9 agent-svc processes have identical `restart_delay=5000`. If LiteLLM (port 4049) becomes unavailable, all 9 restart simultaneously after 5 seconds, then again after 5 seconds, up to 10 times each. This creates a thundering-herd problem.

The agent-svc ecosystem config hardcodes `OPENAI_BASE_URL: "http://localhost:4049/v1"` -- LiteLLM is a hard dependency for all agent intelligence.

**County Adapter Retry (local codebase):**
```python
RetryConfig(max_retries=3, base_delay=1.0, max_delay=60.0, backoff_multiplier=2.0, jitter=True)
```
Good: includes jitter and exponential backoff. Bad: `max_retries=3` combined with the 3-second base may not be sufficient for slow county websites.

### 3.5 Connection Pool Analysis

| Service | Pool Config | Per-Process | Total (all workers) |
|---------|------------|-------------|---------------------|
| frgcrm-api | pool_size=30, max_overflow=50 | 80 max | 160 (2 workers) |
| agent-svc (each) | node-postgres default (~10) | 10 | 90 (9 workers) |
| **Total potential DB connections** | | | **250** |

PostgreSQL default `max_connections` is typically 100. With 250 potential connections, the database will reject connections under load.

The FRG CRM API pool is oversized: for a FastAPI app with 2 workers handling typical CRUD, `pool_size=10, max_overflow=20` would be more appropriate.

### 3.6 Queue / Background Job Analysis

**Finding:** No dedicated job queue system exists in production.

- FRG CRM API uses APScheduler (in-process AsyncIOScheduler) for background tasks
- Agent services use polling loops (5-minute intervals via `POLLING_INTERVAL_MS`)
- Local codebase has `ThreadPoolExecutor` for OCR but no distributed queue
- Research agents run on cron schedules, not event-driven

**Risk:** CPU-intensive or long-running operations block the API event loop. APScheduler tasks compete with API request handling for CPU and thread pool resources.

### 3.7 Caching Analysis

**Finding:** No API response caching layer exists.

- Redis is available (100.118.166.117:6379) but only used for agent session/presence
- No ETag, Cache-Control, or CDN headers on API responses
- Dashboard stats endpoints (GET /api/dashboard/stats, GET /api/pipeline/stats) recompute on every request
- Agent intelligence results are not cached, causing repeated LLM calls

### 3.8 LiteLLM Single Point of Failure

```
All 9 agent-svc  ──┐
                   ├──> LiteLLM (port 4049) ──> DeepSeek API
frgcrm-api ────────┘     fork_mode, 1 instance
                          361 MB, 5 restarts
```

LiteLLM is the **critical path** for all AI operations. It runs as a single fork_mode process with no redundancy. If it stops:
1. All agent intelligence stalls
2. PM2 restarts all 9 agent-svc processes (retry storm)
3. frgcrm-api AI features fail
4. No fallback to direct API calls

---

## 4. API Response Time Benchmarks

### 4.1 Measured Response Times (Localhost from AIOPS)

| Endpoint | Port | HTTP | Total Time | Notes |
|----------|------|------|------------|-------|
| FRG CRM API health | 8082 | 200 | <1ms | FastAPI/uvicorn |
| FRG CRM API root | 8082 | 200 | <1ms | JSON metadata |
| Uptime Kuma | 3001 | 302 | 2ms | Docker |
| Grafana | 3002 | 302 | 1ms | Docker |
| ChangeDetection | 5000 | 200 | 9ms | Docker, 55KB response |
| Dockge | 5001 | 200 | 1ms | Docker |
| Prometheus | 9090 | 302 | <1ms | Docker |

### 4.2 FRG CRM API Access Log Patterns (PM2)

Log shows repeated 401 Unauthorized responses from `100.98.163.17` (internal Tailscale IP) every few minutes. This is likely the prediction-radar or agent-svc polling cycle. Pattern:
```
GET /api/cases?stage=qualified&limit=50  -> 401
GET /api/cases?stage=docs_received&limit=50 -> 401
POST /api/surplusai/pipeline/promote -> 401
```
The 401 responses suggest missing or expired internal auth tokens.

### 4.3 Agent-SVC Latency Log Hits

| Service | Latency Log Hits | Severity |
|---------|-----------------|----------|
| frgcrm-agent-svc | **630** | HIGH |
| insforge-agent-svc | 14 | LOW |
| All others | 0 | NONE |

The frgcrm-agent-svc 630 latency hits are the largest concern. This service handles case scoring, attorney matching, and pipeline monitoring -- all LLM-intensive operations routed through LiteLLM.

---

## 5. Codebase Pattern Analysis

### 5.1 Async vs Sync Code Distribution

**FRG CRM API (Python/FastAPI):**
- Framework: FastAPI (async-capable)
- Database: Synchronous SQLAlchemy (blocking)
- Background tasks: AsyncIOScheduler (async)
- Research agents (local): Full async with aiohttp

**Agent Services (TypeScript/Express):**
- Framework: Express (callback-based, inherently synchronous by default)
- Most agent-runner code uses async/await correctly
- GovRider client: Good async with AbortSignal.timeout
- No middleware for request timeout or concurrency limiting

**Local Codebase (wheeler-intelligence-platform):**
- BaseResearchAgent: Fully async (aiohttp, asyncio)
- County adapters: Synchronous (requests library, ThreadPoolExecutor for OCR)
- OCR Pipeline: ThreadPoolExecutor for parallel page processing
- RetryManager: Both sync and async execute methods

### 5.2 Blocking Operations Inventory

| Location | Operation | Risk |
|----------|-----------|------|
| database.py:get_db() | Sync DB session | HIGH |
| base_adapter.py | requests.Session.get() | MEDIUM |
| base_adapter.py | subprocess.run("pdftotext") | HIGH |
| base_adapter.py | subprocess.run("ocrmypdf", timeout=120) | HIGH |
| pdf_ocr_pipeline.py | ThreadPoolExecutor | MEDIUM |
| agent-svc model.ts | Synchronous OpenAIModel constructor | LOW |

### 5.3 Security Note: Hardcoded Credentials Found

During the audit, several agent-svc ecosystem.config.js files were found to contain **hardcoded credentials** in environment variables:

- `OPENAI_API_KEY`, `DEEPSEEK_API_KEY` -- exposed in PM2 process environment
- `DATABASE_URL` -- full PostgreSQL connection strings with passwords
- `REDIS_URL` -- Redis connection strings with passwords
- `INSFORGE_API_KEY` -- API key exposed

**These should be moved to a secrets manager or `.env` files with appropriate file permissions.** This is a CRITICAL security finding separate from the performance scope.

---

## 6. Recommendations

### 6.1 Immediate (High Impact, Low Effort) -- Week 1

#### R6.1.1 Add Express Timeout Middleware to All Agent Services

Every agent-svc Express server needs timeout configuration:

```typescript
// Add to server.ts createServer() or index.ts listen()
const server = app.listen(config.port, () => {
  console.log(`[${svcName}] on :${config.port}`);
});

// Prevent slow-client connection leaks
server.timeout = 30_000;          // 30s idle timeout
server.keepAliveTimeout = 65_000; // Slightly above ALB default
server.headersTimeout = 66_000;   // Slightly above keepAliveTimeout
server.maxConnections = 100;      // Prevent connection flood

// Add request timeout middleware
app.use((req, res, next) => {
  const timeout = setTimeout(() => {
    if (!res.headersSent) {
      res.status(504).json({ error: 'Request timeout' });
    }
  }, 60_000); // 60s max request duration
  res.on('finish', () => clearTimeout(timeout));
  next();
});
```

**Effort:** 30 min per service (add to shared `createServer()` function)
**Impact:** Eliminates connection leaks and infinite-hang scenarios

#### R6.1.2 Stagger PM2 Restart Delays

Add jitter to all agent-svc `restart_delay` values to prevent thundering herd:

```javascript
// ecosystem.config.js -- each service gets a different delay
restart_delay: 5000 + Math.floor(Math.random() * 15000)  // 5-20s
```

Or set explicitly per service:
```
frgcrm-agent-svc:        restart_delay: 5000
surplusai-agent-svc:     restart_delay: 8000
voice-agent-svc:         restart_delay: 11000
insforge-agent-svc:      restart_delay: 14000
design-agent-svc:        restart_delay: 17000
horizon-agent-svc:       restart_delay: 6000
paperless-agent-svc:     restart_delay: 9000
prediction-radar-agent-svc: restart_delay: 12000
ravyn-agent-svc:         restart_delay: 15000
```

**Effort:** 5 min editing ecosystem configs
**Impact:** Eliminates restart-storm cascade failure mode

#### R6.1.3 Reduce FRG CRM API Connection Pool

```python
# database.py -- current vs recommended
# Current:
engine = create_engine(DATABASE_URL, pool_size=30, max_overflow=50, pool_recycle=600)

# Recommended:
engine = create_engine(
    DATABASE_URL,
    pool_size=10,          # Down from 30
    max_overflow=20,       # Down from 50
    pool_recycle=3600,     # Up from 600 (recycle less aggressively)
    pool_pre_ping=True,    # Keep
    pool_timeout=10,       # Add: fail fast if pool exhausted
    connect_args={
        "connect_timeout": 5,            # Add: fast connection failure
        "options": "-c statement_timeout=10000"  # Server-side timeout
    }
)
```

**Effort:** 5 min editing database.py + PM2 restart
**Impact:** Reduces PostgreSQL connection pressure from 160 to 60 max connections

#### R6.1.4 Add Uvicorn Production Flags

```bash
# Current PM2 command:
python3 -m uvicorn main:app --host 0.0.0.0 --port 8082 --workers 2

# Recommended:
python3 -m uvicorn main:app \
  --host 0.0.0.0 \
  --port 8082 \
  --workers 4 \
  --limit-concurrency 200 \
  --limit-max-requests 10000 \
  --timeout-keep-alive 30 \
  --backlog 128 \
  --log-level warning
```

**Effort:** 2 min updating PM2 process config
**Impact:** Better concurrency control, memory leak protection via max-requests

### 6.2 Short-Term (Medium Effort) -- Weeks 2-3

#### R6.2.1 LiteLLM Redundancy

Add a secondary LiteLLM instance and configure client-side fallback:

```typescript
// model.ts -- current
export function createModel() {
  return new OpenAIModel({
    clientConfig: {
      baseURL: process.env.OPENAI_BASE_URL || 'http://127.0.0.1:4049/v1',
    },
  });
}

// model.ts -- recommended (with fallback)
export function createModel() {
  const primaryURL = process.env.OPENAI_BASE_URL || 'http://127.0.0.1:4049/v1';
  const fallbackURL = process.env.OPENAI_FALLBACK_URL; // direct DeepSeek
  return new OpenAIModel({
    clientConfig: {
      baseURL: primaryURL,
      // Configure SDK-level retry with fallback
      maxRetries: 2,
      timeout: 60_000,
    },
    // If SDK supports fallback baseURL, use it here
  });
}
```

Alternatively, run a second LiteLLM on a different port (4050) and load-balance at the agent level.

**Effort:** 2-4 hours
**Impact:** Eliminates the single most critical SPOF in the system

#### R6.2.2 Redis Response Cache for High-Traffic Endpoints

Add a caching layer for expensive read endpoints:

```python
# cache_decorator.py
import json
import hashlib
from functools import wraps

def redis_cache(ttl_seconds: int = 60):
    """Cache FastAPI endpoint responses in Redis."""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            import redis.asyncio as aioredis
            r = aioredis.from_url(REDIS_URL)
            cache_key = f"api:cache:{func.__name__}:{hashlib.md5(json.dumps(kwargs, sort_keys=True).encode()).hexdigest()}"
            cached = await r.get(cache_key)
            if cached:
                return json.loads(cached)
            result = await func(*args, **kwargs)
            await r.setex(cache_key, ttl_seconds, json.dumps(result, default=str))
            return result
        return wrapper
    return decorator
```

**Target endpoints:**
- `GET /api/dashboard/stats` -- Cache 5 min (expensive aggregation)
- `GET /api/pipeline/stats` -- Cache 5 min
- `GET /api/cases` -- Cache 30s (fast-moving but heavily polled)
- Agent intelligence results -- Cache 10 min (LLM results don't change rapidly)

**Effort:** 4-8 hours to implement and deploy
**Impact:** 60-80% reduction in repeated DB queries for dashboard/pipeline stats

#### R6.2.3 Agent-SVC Polling to Event-Driven Migration

Current state: 9 agent services poll every 5 minutes (300s), generating wasteful load even when nothing changed.

Recommended: Use the existing `event-bus-relay` to push events:

```typescript
// Instead of setInterval polling:
// 1. Subscribe to event-bus-relay for relevant events
// 2. Run agent logic only when triggered by a data change event

// event-bus-relay publishes events like:
// - case.created, case.updated, case.stage_changed
// - surplusai.pipeline.updated
// - document.uploaded

bus.subscribe('case.stage_changed', async (event) => {
  if (event.data.new_stage === 'qualified') {
    const agent = new CaseScorerAgent();
    await agent.run();
  }
});
```

**Migration path:**
1. Add event publishing to frgcrm-api mutation endpoints
2. Have agent-svc listen for events instead of polling
3. Keep polling as fallback (interval increased to 15 min)

**Effort:** 2-5 days per service (depends on event-bus-relay maturity)
**Impact:** 80% reduction in idle API traffic, faster response to changes

#### R6.2.4 Implement Job Queue for Long-Running Operations

Introduce BullMQ (backed by existing Redis) for:
- OCR processing (currently blocking with subprocess.run)
- County scraping jobs
- AI model inference
- PDF generation
- Batch operations

```typescript
// queue.ts
import { Queue, Worker } from 'bullmq';

const ocrQueue = new Queue('ocr-processing', {
  connection: { host: '100.118.166.117', port: 6379, password: 'FRGpassword1!' },
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    timeout: 120_000,  // 2 min OCR timeout
  },
});

// API endpoint enqueues instead of blocking:
app.post('/api/documents/:id/ocr', async (req, res) => {
  const job = await ocrQueue.add('process-pdf', {
    documentId: req.params.id,
    filepath: req.body.filepath,
  });
  res.json({ jobId: job.id, status: 'queued' });
});
```

**Effort:** 1-2 weeks for full implementation
**Impact:** Non-blocking API, retry-able jobs, job monitoring, rate control

### 6.3 Medium-Term (Architectural) -- Weeks 4-6

#### R6.3.1 Async DB Migration for FRG CRM API

The largest performance gain: convert frgcrm-api from synchronous to asynchronous database access.

```python
# database_async.py (new)
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

DATABASE_URL_ASYNC = os.getenv(
    "DATABASE_URL_ASYNC",
    "postgresql+asyncpg://frgops@127.0.0.1:5433/frgcrm"
)

async_engine = create_async_engine(
    DATABASE_URL_ASYNC,
    pool_size=10,
    max_overflow=20,
    pool_recycle=3600,
    pool_pre_ping=True,
    pool_timeout=10,
)

AsyncSessionLocal = async_sessionmaker(
    async_engine, class_=AsyncSession, expire_on_commit=False
)

async def get_async_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

**Migration strategy:**
1. Create async engine alongside sync engine (dual-running)
2. Migrate high-traffic read endpoints first (GET routes)
3. Migrate write endpoints next (POST/PUT routes)
4. Remove synchronous engine after full migration

**Effort:** 3-6 weeks (touches 40+ route modules)
**Impact:** 2-4x throughput improvement for I/O-bound endpoints, eliminates thread pool bottleneck

#### R6.3.2 PM2 Cluster Mode for Agent Services

Convert agent-svc from `fork_mode` to `cluster_mode`:

```javascript
// ecosystem.config.js
module.exports = {
  apps: [{
    name: "frgcrm-agent-svc",
    script: "./dist/index.js",
    exec_mode: "cluster",
    instances: 2,             // or "max" for all cores
    instance_var: "INSTANCE_ID",
    max_memory_restart: "500M",
    // ... rest of config
  }],
};
```

**Caveat:** Express `app.listen()` must be cluster-safe. The `createServer()` pattern used by agent services already supports this since it doesn't bind to a specific port per instance.

**Recommended instances per service:**
- frgcrm-agent-svc: 2 (heavy LLM usage)
- Other agent-svc: 1 (kept at 1 to avoid LiteLLM overload)
- For cluster_mode to work, LiteLLM must be scaled first (R6.2.1)

**Effort:** 1-2 hours testing + deployment
**Impact:** Better CPU utilization, failure isolation between instances

#### R6.3.3 uvicorn Worker Count Tuning for FRG CRM API

```bash
# Worker formula for I/O-bound FastAPI:
# workers = (2 * CPU_CORES) + 1 = (2 * 16) + 1 = 33
# BUT each worker loads all models (~150MB), so:
# max_workers_by_memory = available_RAM / worker_memory = 13GB / 200MB = 65
# Practical: workers = 4-6

uvicorn main:app --host 0.0.0.0 --port 8082 --workers 6 --limit-concurrency 200
```

**Effort:** 5 min updating PM2 config
**Impact:** 3x increase in concurrent request handling capacity

---

## 7. Connection Pool Tuning Summary

### 7.1 Current vs Recommended

| Service | Parameter | Current | Recommended | Rationale |
|---------|-----------|---------|-------------|-----------|
| frgcrm-api | pool_size | 30 | 10 | 30 per worker * 4 workers = 120, too high |
| frgcrm-api | max_overflow | 50 | 20 | Limits burst without overwhelming PG |
| frgcrm-api | pool_recycle | 600s | 3600s | Reduce reconnect churn |
| frgcrm-api | pool_timeout | (unset) | 10s | Fail fast instead of hanging |
| frgcrm-api | connect_args | (unset) | connect_timeout=5 | Fast failure on PG unreachable |
| agent-svc | pool_size | ~10 (default) | 5 | 9 services * 5 = 45, manageable |
| agent-svc | idleTimeoutMillis | 10000 (default) | 30,000 | Reduce reconnect on idle connections |
| agent-svc | connectionTimeoutMillis | 0 (no timeout) | 5,000 | Fail fast |

### 7.2 PostgreSQL Server-Side Tuning

```sql
-- Recommended PostgreSQL settings (on COREDB / local PG instances)
ALTER SYSTEM SET max_connections = 200;         -- Up from default 100
ALTER SYSTEM SET idle_in_transaction_session_timeout = '30s';
ALTER SYSTEM SET statement_timeout = '15s';      -- Hard server-side cap
ALTER SYSTEM SET tcp_keepalives_idle = '60s';
ALTER SYSTEM SET tcp_keepalives_interval = '10s';
SELECT pg_reload_conf();
```

---

## 8. Caching Strategy

### 8.1 Cache Tiers

```
Layer 1: In-Memory (Node.js LRU / Python lru_cache)
  - TTL: 5-30 seconds
  - Use: Hot path computations, config lookups
  - Max size: 1000 entries

Layer 2: Redis
  - TTL: 1-15 minutes
  - Use: Dashboard stats, pipeline views, agent results
  - Max memory: 256 MB

Layer 3: PostgreSQL Materialized Views
  - Refresh: Every 5-15 minutes
  - Use: Complex analytics aggregations
```

### 8.2 Recommended Cache Keys

| Endpoint | Cache Layer | TTL | Key Pattern |
|----------|-------------|-----|-------------|
| GET /api/dashboard/stats | Redis | 300s | `dashboard:stats:{user_id}` |
| GET /api/pipeline/stats | Redis | 300s | `pipeline:stats:{user_id}` |
| GET /api/cases | Redis | 30s | `cases:{stage}:{limit}:{user_id}` |
| Agent run results | Redis | 600s | `agent:{name}:result:{hash}` |
| County adapter configs | In-Memory | 3600s | `adapter:config:{county}` |
| LLM embeddings | Redis | 86400s | `embed:{model}:{hash}` |

### 8.3 Cache Invalidation Strategy

- **Write-through:** Invalidate cache on mutation (POST/PUT/DELETE)
- **Pattern-based:** Delete all keys matching pattern on bulk operations
- **TTL-based:** Fallback invalidation if write-through misses

---

## 9. Queue Architecture

### 9.1 Recommended: BullMQ on Existing Redis

```
                    ┌──────────────┐
                    │   Redis      │
                    │  (existing)  │
                    └──┬───┬───┬───┘
                       │   │   │
          ┌────────────┼───┼───┼────────────┐
          │            │   │   │            │
     ┌────▼────┐  ┌───▼───▼───▼───┐  ┌─────▼─────┐
     │  OCR    │  │  AI Inference │  │  County   │
     │  Queue  │  │  Queue        │  │  Scrape   │
     └─────────┘  └───────────────┘  └───────────┘
```

### 9.2 Queue Definitions

| Queue | Concurrency | Timeout | Retries | Backoff |
|-------|-------------|---------|---------|---------|
| ocr-processing | 2 | 120s | 3 | exponential, 5s base |
| ai-inference | 5 (LiteLLM limit) | 60s | 2 | exponential, 2s base |
| county-scrape | 3 (per county) | 90s | 3 | fixed, 30s |
| email-notification | 10 | 30s | 5 | exponential, 1s base |
| pdf-generation | 2 | 60s | 2 | exponential, 3s base |

### 9.3 Queue Monitoring

```typescript
// Add to ecosystem-guardian health checks
const queueHealth = {
  ocr: { waiting: 0, active: 0, failed: 0, completed: 0 },
  aiInference: { waiting: 0, active: 0, failed: 0, completed: 0 },
  // Alert if waiting > 50 or failed > 10 in last hour
};
```

---

## 10. Safe Apply Script

A script at `/root/templates/api/safe-apply-api-optimizations.sh` provides a phased, verified rollout of low-risk optimizations. Each step includes a pre-check, application, and post-verification. The script is designed to be run in `--dry-run` mode first.

See: `/root/templates/api/safe-apply-api-optimizations.sh`

---

## 11. Implementation Priority Matrix

```
Impact
  ^
  │  R6.1.2 (stagger restarts)      R6.2.1 (LiteLLM redundancy)
  │  R6.1.1 (Express timeouts)      R6.2.2 (Redis cache)
  │  R6.1.3 (reduce DB pool)        R6.2.3 (event-driven)
  │  R6.1.4 (uvicorn flags)
  │                                  R6.2.4 (job queue)
  │                                  R6.3.1 (async DB)
  │  ────────────────────────────────────────────────────>
  │                              Effort
  │
  │  DO FIRST (upper-left)         DO LATER (upper-right)
  │  Quick wins with high impact   Major gains, major effort
  └──────────────────────────────────────────────────────
```

**Week 1:** R6.1.1 through R6.1.4 (all immediate recommendations)
**Week 2-3:** R6.2.1 through R6.2.4 (short-term recommendations)
**Week 4-6:** R6.3.1 through R6.3.3 (architectural improvements)

---

## 12. Risk Register

| ID | Risk | Mitigation | Residual Risk |
|----|------|-----------|---------------|
| R1 | LiteLLM outage cascades to all services | R6.2.1: Secondary instance + fallback | Low |
| R2 | PostgreSQL connection exhaustion | R6.1.3: Reduce pool sizes | Medium |
| R3 | Express connection leaks DoS AIOPS | R6.1.1: Add timeouts everywhere | Low |
| R4 | PM2 restart storm on shared dependency failure | R6.1.2: Stagger restart delays | Low |
| R5 | Thread pool exhaustion blocks all API requests | R6.3.1: Async DB migration | Medium |
| R6 | Agent polling overloads FRG CRM API | R6.2.3: Event-driven + auth fix | Medium |
| R7 | Hardcoded credentials leaked in PM2 env | Separate security initiative | High |

---

## Appendix A: Agent-SVC Port Map

| Service | Port | DB Connected | Redis | LLM |
|---------|------|-------------|-------|-----|
| frgcrm-agent-svc | 8003 | Yes (via FRGCRM/FRGOPS API) | No | LiteLLM |
| horizon-agent-svc | 8006 | Yes (wheeler_core) | Yes | LiteLLM |
| ravyn-agent-svc | 8005 | Yes (wheeler_core) | Yes | LiteLLM |
| surplusai-scraper-agent-svc | 8007 | No | No | LiteLLM |
| voice-agent-svc | 8008 | No | No | LiteLLM |
| paperless-agent-svc | 8009 | Yes (wheeler_core) | Yes | LiteLLM |
| prediction-radar-agent-svc | 8011 | Yes (wheeler_core) | Yes | LiteLLM |
| design-agent-svc | 8020 | Yes (wheeler_core) | Yes | LiteLLM |
| insforge-agent-svc | 8013 | No (via PostgREST/HTTP) | No | LiteLLM (Anthropic) |

## Appendix B: FRG CRM API Route Modules

The FRG CRM API at `/opt/wheeler/apps/frgcrm/api/main.py` includes 40+ route modules:
bulk, cases, contacts, disbursements, dashboard, ai, sync, playbooks, reports, auth,
tasks, calendar, webhooks, attorney, attorney_filing, attorney_coverage, fraud, admin,
sequences, search, pdf_export, notes, notifications, leads, intelligence, partner,
claimant, verification, auction, wealth_protocol, financeos, alphabrain, executionos,
legalshield, dealdesk, ml_score, family_bank, public_stats, cal_webhook, voice_outreach,
surplusai, ravynai, outreach, identity_graph, revenue_pipeline

## Appendix C: Key File Paths

| Component | Path |
|-----------|------|
| FRG CRM API | /opt/wheeler/apps/frgcrm/api/main.py |
| FRG CRM DB config | /opt/wheeler/apps/frgcrm/api/database.py |
| FRG CRM scheduler | /opt/wheeler/apps/frgcrm/api/scheduler.py |
| Agent-svc base | /opt/apps/{name}-agent-svc/src/server.ts |
| Agent ecosystem config | /opt/apps/ecosystem.config.js (PM2 managed) |
| Local: County adapters | /root/wheeler-intelligence-platform/county-adapter-framework/ |
| Local: Research agents | /root/wheeler-intelligence-platform/research-agents/ |
| Local: Orchestrator | /root/wheeler-autonomous-ops/orchestrator/ |
| Local: Health engine | /root/wheeler-autonomous-ops/ecosystem-health-engine/ |
