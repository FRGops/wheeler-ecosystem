# Wheeler Ecosystem Cache Strategy

> **Phase 9 — Cache Strategy**  
> Principal Infrastructure Optimization Engineering  
> Date: 2026-05-23

---

## Executive Summary

The Wheeler ecosystem currently uses **3 fragmented cache mechanisms** with no unified strategy:
1. **LiteLLM Redis semantic cache** — AI response caching (TTL 3600s, similarity threshold 0.9)
2. **Claimant enrichment Redis cache** — serialized `EnrichedClaimant` objects via `redis.asyncio`
3. **In-memory embedding cache** — dict-based, per-process, lost on restart

**Gaps**: No HTTP cache, no query cache, no edge cache, no CDN, no cache invalidation strategy. Every cache is independently managed with no shared TTL policy, no namespace conventions, and no monitoring.

---

## Current Cache Inventory

| Cache Layer | Backend | Scope | TTL | Hit Rate | Status |
|---|---|---|---|---|---|
| LiteLLM semantic cache | Redis | AI responses | 3600s | Unknown | Active |
| Claimant enrichment | Redis | Serialized objects | Configurable | Unknown | Active |
| Embedding cache | In-memory dict | Text embeddings | Process lifetime | Unknown | Per-process |
| HTTP response cache | None | — | — | — | Missing |
| Database query cache | None | — | — | — | Missing |
| Edge/CDN cache | None | — | — | — | Missing |
| Static asset cache | None | — | — | — | Missing |

---

## Cache Architecture Target

```
┌─────────────────────────────────────────────────────┐
│                   EDGE LAYER                         │
│  Traefik/Nginx → Static asset cache (30d)            │
│                → API response cache (60s-300s)       │
│                → SSL session cache (10m)             │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│                 APP LAYER (AIOPS)                    │
│  FastAPI/Flask → @cache_response decorator           │
│               → ETag/If-None-Match headers           │
│               → Cache-Control headers                │
│               → Conditional request handling         │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│               DATA LAYER (COREDB)                    │
│  Redis → Hot data cache                              │
│       → Query result cache (60s-600s)                │
│       → Session cache                                │
│       → Rate limit counters                          │
│       → AI semantic cache (existing)                 │
│       → Claimant enrichment cache (existing)         │
│       → Embedding cache (migrate from in-memory)     │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│             DATABASE LAYER                           │
│  PostgreSQL → shared_buffers (OS/page cache)         │
│            → Effective cache via memory              │
│            → Materialized views for expensive queries│
└─────────────────────────────────────────────────────┘
```

---

## Phase 9.1 — HTTP Cache Layer (CRITICAL — currently missing)

### Problem
No HTTP caching anywhere. Every request recomputes responses. Zero `Cache-Control`, `ETag`, `Last-Modified`, or `If-None-Match` headers.

### Target Architecture

**Nginx reverse proxy cache (on EDGE):**
```nginx
# Enable proxy cache
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=WHEELER_CACHE:100m 
                   max_size=2g inactive=60m use_temp_path=off;

# Cache static assets aggressively
location /static/ {
    proxy_cache WHEELER_CACHE;
    proxy_cache_valid 200 30d;
    proxy_cache_key "$uri";
    add_header X-Cache-Status $upstream_cache_status;
    expires 30d;
}

# Cache API responses conditionally
location /api/ {
    proxy_cache WHEELER_CACHE;
    proxy_cache_valid 200 60s;
    proxy_cache_valid 404 10s;
    proxy_cache_key "$scheme$request_method$host$request_uri";
    proxy_cache_bypass $http_cache_control;
    add_header X-Cache-Status $upstream_cache_status;
    
    # Don't cache mutations
    proxy_cache_methods GET HEAD;
}
```

**FastAPI ETag support (on AIOPS):**
```python
from fastapi import Request, Response
from hashlib import md5
import json

def generate_etag(data: dict) -> str:
    return md5(json.dumps(data, sort_keys=True).encode()).hexdigest()

@app.get("/api/claimant/{id}")
async def get_claimant(id: str, request: Request, response: Response):
    data = await fetch_claimant(id)
    etag = generate_etag(data)
    
    if request.headers.get("If-None-Match") == etag:
        response.status_code = 304
        return None
    
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "public, max-age=300"
    return data
```

### Implementation Priority
1. **HIGH**: Add `Cache-Control` headers to all API responses (immediate, no infrastructure needed)
2. **HIGH**: Enable Nginx static asset cache on EDGE (30d TTL, 2GB cache)
3. **MEDIUM**: Add ETag support to high-traffic GET endpoints
4. **MEDIUM**: Enable Nginx API response cache for read-heavy endpoints

---

## Phase 9.2 — Query Result Cache

### Problem
PostgreSQL has no query-level cache beyond `shared_buffers`. Repeated queries (e.g., claimant lookups, dashboard aggregations) hit the database on every request.

### Target

**Redis-backed query cache with intelligent invalidation:**

```python
import hashlib
import json
from typing import Optional, Any
import redis.asyncio as redis

class QueryCache:
    """Redis-backed query result cache with TTL and prefix namespacing."""
    
    def __init__(self, redis_url: str, default_ttl: int = 300):
        self.redis = redis.from_url(redis_url)
        self.default_ttl = default_ttl
    
    def _key(self, query: str, params: tuple) -> str:
        payload = json.dumps({"q": query, "p": params}, sort_keys=True)
        return f"qcache:{hashlib.sha256(payload.encode()).hexdigest()[:16]}"
    
    async def get(self, query: str, params: tuple) -> Optional[Any]:
        cached = await self.redis.get(self._key(query, params))
        return json.loads(cached) if cached else None
    
    async def set(self, query: str, params: tuple, result: Any, ttl: int = None):
        key = self._key(query, params)
        await self.redis.setex(key, ttl or self.default_ttl, json.dumps(result))
    
    async def invalidate_table(self, table: str):
        """Invalidate all cached queries for a table (pattern-based)."""
        # Use a version key per table — increment on write
        await self.redis.incr(f"qcache:v:{table}")
```

**Cache TTL guidelines:**
| Query Type | TTL | Rationale |
|---|---|---|
| Claimant profile | 300s | Moderate change rate |
| Dashboard aggregations | 120s | Near real-time needed |
| Reference/lookup data | 3600s | Rarely changes |
| AI model list | 86400s | Changes on deploy only |
| County adapter configs | 600s | Updated via admin |

---

## Phase 9.3 — AI Response Cache Optimization

### Current State
LiteLLM semantic cache is configured but unmonitored. No visibility into:
- Cache hit rate
- Cache memory usage
- Token savings from cache

### Optimizations

1. **Enable LiteLLM cache metrics:**
```yaml
# litellm-config.yaml
router_settings:
  cache: true
  cache_params:
    type: redis
    host: ${REDIS_HOST}
    port: ${REDIS_PORT}
    ttl: 3600
    namespace: "litellm_cache"
    similarity_threshold: 0.92  # Slightly stricter (was 0.9)
  redis_max_connections: 20
```

2. **Tiered AI caching:**
   - **L1**: In-memory exact-match cache (TTL 60s) — for repeated identical prompts
   - **L2**: Redis semantic cache (TTL 3600s) — for semantically similar prompts
   - **L3**: LLM provider — actual API call

3. **Embedding cache centralization:**
   - Migrate from per-process `dict` to Redis
   - Share embeddings across all agent-svc processes
   - Avoid recomputing embeddings after restarts

```python
# Migrate embedding cache to Redis
class RedisEmbeddingCache:
    def __init__(self, redis_url: str):
        self.redis = redis.from_url(redis_url)
    
    async def get(self, text: str, model: str) -> Optional[list[float]]:
        key = f"emb:{model}:{hashlib.sha256(text.encode()).hexdigest()[:24]}"
        cached = await self.redis.get(key)
        return json.loads(cached) if cached else None
    
    async def set(self, text: str, model: str, embedding: list[float], ttl=86400):
        key = f"emb:{model}:{hashlib.sha256(text.encode()).hexdigest()[:24]}"
        await self.redis.setex(key, ttl, json.dumps(embedding))
```

4. **Token waste reduction via prompt caching:**
   - Store system prompts in Redis (they're repeated on every call)
   - Only send changing user content
   - Estimated savings: 20-40% of input tokens on agent-svc calls

---

## Phase 9.4 — Claimant Enrichment Cache Optimization

### Current State
Already has Redis cache in `claimant_enrichment.py` with `_cache_get`/`_cache_set` methods. However:
- No cache hit rate monitoring
- No bulk pre-warming
- No invalidation on data updates

### Optimizations

1. **Add cache metrics:**
```python
class EnrichmentCache:
    def __init__(self, redis_url: str):
        self.redis = redis.from_url(redis_url)
        self.hits = 0
        self.misses = 0
    
    @property
    def hit_rate(self) -> float:
        total = self.hits + self.misses
        return self.hits / total if total > 0 else 0
    
    async def get(self, claimant_id: str) -> Optional[dict]:
        result = await self.redis.get(f"enriched:{claimant_id}")
        if result:
            self.hits += 1
            return json.loads(result)
        self.misses += 1
        return None
```

2. **Pre-warming strategy:**
   - On startup, load top 100 most-accessed claimants into cache
   - During batch processing, pipeline cache writes

3. **Cache invalidation hooks:**
   - Invalidate on claimant data update events
   - Use event-bus-relay to broadcast invalidation to all agent-svc instances

---

## Phase 9.5 — Edge Cache (Nginx/Traefik)

### Priority: HIGH (co-located with EDGE overload fix)

```nginx
# Optimized nginx caching config for Wheeler
proxy_cache_path /var/cache/nginx/wheeler 
    levels=1:2 
    keys_zone=wheeler_cache:100m 
    max_size=2g 
    inactive=60m
    use_temp_path=off;

# Cache key includes query string for API diversity
proxy_cache_key "$scheme$request_method$host$request_uri$http_authorization";

# Upstream definition with keepalive
upstream aiops_backend {
    server 5.78.140.118:8080;
    keepalive 32;
}

server {
    # Static assets — cache aggressively
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        proxy_pass http://aiops_backend;
        proxy_cache wheeler_cache;
        proxy_cache_valid 200 30d;
        proxy_cache_use_stale error timeout updating;
        add_header X-Cache-Status $upstream_cache_status;
        expires 30d;
    }
    
    # API reads — cache briefly
    location /api/ {
        proxy_pass http://aiops_backend;
        proxy_cache wheeler_cache;
        proxy_cache_valid 200 60s;
        proxy_cache_valid 404 10s;
        proxy_cache_bypass $http_cache_control;
        proxy_cache_use_stale error timeout updating http_500;
        proxy_cache_lock on;  # Prevent thundering herd
        add_header X-Cache-Status $upstream_cache_status;
        
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # Mutations — never cache
    location /api/ {
        if ($request_method !~ ^(GET|HEAD)$) {
            set $bypass_cache 1;
        }
        proxy_cache_bypass $bypass_cache;
    }
}
```

---

## Phase 9.6 — Cache Invalidation Strategy

### The Cache Invalidation Matrix

| Data Type | Invalidation Trigger | Method |
|---|---|---|
| Claimant profile | Update event | Key delete + version increment |
| AI response | TTL-based only (no invalidation) | TTL expiry |
| Embeddings | Model version change | Namespace prefix rotation |
| Dashboard aggregations | TTL-based | Short TTL (120s) |
| Static assets | Deploy | Cache purge by path prefix |
| Config data | Config change event | Key delete |

### Implementation: Cache-Aside Pattern with Write Invalidation

```python
async def update_claimant(claimant_id: str, data: dict) -> None:
    # 1. Write to database
    await db.claimants.update(claimant_id, data)
    
    # 2. Invalidate cache (NOT update — avoid cache stampede)
    await redis.delete(f"enriched:{claimant_id}")
    await redis.delete(f"qcache:*claimant*{claimant_id}*")  # Pattern
    
    # 3. Publish invalidation event for other processes
    await redis.publish("cache:invalidation", json.dumps({
        "type": "claimant",
        "id": claimant_id,
        "timestamp": time.time()
    }))
```

---

## Cache Performance Targets

| Metric | Current | Target | Timeline |
|---|---|---|---|
| API cache hit rate | 0% (no caching) | 40%+ | 7 days |
| AI cache hit rate | Unknown | 25%+ | 7 days |
| Static asset cache hit rate | 0% | 95%+ | 24 hours |
| Claimant enrichment hit rate | Unknown | 60%+ | 14 days |
| Average API response time | Unknown | <100ms cached | 30 days |
| Redis memory for cache | ~50MB (estimated) | 500MB dedicated | 30 days |

---

## Implementation Roadmap

### Immediate (24 hours)
1. Add `Cache-Control` headers to all API GET responses
2. Enable Nginx static asset caching on EDGE
3. Add cache monitoring to existing Redis caches

### Short-term (7 days)
1. Implement Redis query cache for top 10 slowest queries
2. Migrate embedding cache from in-memory to Redis
3. Configure Nginx API response cache for read endpoints

### Medium-term (30 days)
1. Implement ETag support across all APIs
2. Deploy cache pre-warming for claimant enrichment
3. Implement cache invalidation event system
4. Evaluate CDN for static assets (Cloudflare free tier)

### Long-term (90 days)
1. Multi-region Redis replication for cache locality
2. Tiered caching with memory → Redis → DB fallback
3. Cache analytics dashboard (hit rates, savings, latency)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Stale data served from cache | Medium | High | Short TTLs, event-driven invalidation |
| Cache stampede on cold start | Medium | Medium | Cache lock, pre-warming |
| Redis memory exhaustion | Low | High | maxmemory-policy=allkeys-lru, monitoring |
| Cache poisoning | Low | Critical | Validate cached data before serving |
| Increased complexity | Medium | Low | Start simple, add layers incrementally |

---

## Templates Generated

- `/root/templates/cache/nginx-cache-config.conf` — Nginx cache configuration
- `/root/templates/cache/redis-cache-wrapper.py` — Redis cache helper class
- `/root/templates/cache/query-cache-middleware.py` — FastAPI query cache middleware
- `/root/templates/cache/apply-cache-strategy.sh` — Safe deployment script with rollback
