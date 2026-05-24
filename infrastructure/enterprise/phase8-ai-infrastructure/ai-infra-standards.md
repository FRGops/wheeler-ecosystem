# Wheeler Enterprise AI Infrastructure Standards

**Document Version:** 1.0  
**Last Updated:** 2026-05-23  
**Environment:** Ubuntu 24.04, Docker, Traefik, 3-server Tailscale mesh  
**Scope:** Multi-model AI routing, cost management, observability, and operational standards

---

## Table of Contents

1. [Model Routing Strategy](#1-model-routing-strategy)
2. [Token Usage Tracking](#2-token-usage-tracking)
3. [Cost Monitoring](#3-cost-monitoring)
4. [Request Queueing](#4-request-queueing)
5. [Rate Limiting](#5-rate-limiting)
6. [GPU-Ready Architecture](#6-gpu-ready-architecture)
7. [Provider Health](#7-provider-health)
8. [Security](#8-security)
9. [Observability](#9-observability)

---

## 1. Model Routing Strategy

### 1.1 Overview

Every AI request entering the Wheeler infrastructure passes through the LiteLLM proxy, which decides which upstream model provider serves it. The decision is governed by three configurable routing strategies, selected per request via an HTTP header or a model group name.

### 1.2 Routing Paths

#### Cost-Optimized Path (Default)

Primary strategy for all workloads unless quality is explicitly requested.

```
DeepSeek (deepseek-chat) → OpenAI (gpt-4o-mini) → Anthropic (claude-sonnet-4-6)
```

| Step | Model | Why This Order |
|------|-------|----------------|
| 1 | `deepseek-chat` | Cheapest per token ($0.28/M output), fast, good enough for 80% of tasks |
| 2 | `gpt-4o-mini` | Slightly more expensive ($0.60/M output) but multimodal-capable |
| 3 | `claude-sonnet-4-6` | Most expensive in this chain ($15.00/M output), used only when both above fail |

**Use when:** summarization, classification, RAG retrieval, bulk extraction, code completion, translation, embedding preparation, chatbot responses.

#### Quality Path

Activated by setting the model group to `quality` or header `X-LiteLLM-Routing: quality`.

```
Anthropic (claude-opus-4-7) → OpenAI (gpt-4o) → DeepSeek (deepseek-reasoner)
```

| Step | Model | Why This Order |
|------|-------|----------------|
| 1 | `claude-opus-4-7` | Best reasoning and instruction-following in the industry |
| 2 | `gpt-4o` | Strong multimodal reasoning, large context window |
| 3 | `deepseek-reasoner` | Chain-of-thought model, slower but thorough |

**Use when:** legal document analysis, architectural decisions, complex multi-step reasoning, final-draft generation, security audit reports, executive summaries.

#### Latency-Optimized Path

Activated by `routing_strategy: "latency-based-routing"` in the router config. LiteLLM maintains a rolling average of response latency for each model and routes to the fastest currently-available model within the target group.

**Use when:** interactive chat UIs, real-time copilots, anything where sub-second response matters more than cost or absolute quality.

### 1.3 Decision Matrix

| Criterion | Cost Path | Quality Path | Latency Path |
|-----------|-----------|-------------|--------------|
| **Cost sensitivity** | High (minimize spend) | Low (maximize quality) | Medium |
| **Task complexity** | Low to medium | Medium to very high | Low to medium |
| **Latency tolerance** | Medium | High | Low (<1s target) |
| **Risk of error** | Acceptable | Unacceptable | Acceptable |
| **Multi-turn** | Yes | Yes | Yes |
| **Multimodal needed** | No (falls back to gpt-4o-mini) | Yes (gpt-4o) | Depends on fastest model |
| **Example workloads** | Summaries, extraction, bulk ops | Legal, architecture, final drafts | Chat, copilots, autocomplete |

### 1.4 Model Groups

Clients reference a **model group** rather than a specific provider model. LiteLLM resolves the group to the best available model based on the active routing strategy.

| Group | Intent | Member Models (in priority order) |
|-------|--------|-----------------------------------|
| `cheap` | Minimize cost | `deepseek-v4-pro`, `gpt-4o-mini`, `claude-sonnet-4-6` |
| `quality` | Maximize accuracy | `claude-opus-4-7`, `gpt-4o`, `deepseek-reasoner` |
| `balanced` | Cost/quality tradeoff | `deepseek-v4-pro`, `gpt-4o`, `claude-sonnet-4-6` |

Example client code:

```python
# Cost-optimized
response = client.chat.completions.create(model="cheap", messages=[...])

# Quality-optimized
response = client.chat.completions.create(model="quality", messages=[...])

# Explicit provider (bypasses routing logic)
response = client.chat.completions.create(model="deepseek-v4-pro", messages=[...])
```

### 1.5 Fallback Behavior

LiteLLM attempts the primary model first. If the primary fails (after exhausting retries), it walks the fallback list in order. A model is considered "failed" when:

1. The upstream returns a 5xx error on the third consecutive attempt
2. The request times out after `request_timeout` (120 seconds)
3. The upstream returns a 429 (rate limited) with no Retry-After header

Successful fallback is transparent to the client — they receive the response as if the primary model served it. The `litellm_model` response header disclosing which model actually handled the request is returned to the client for auditability.

---

## 2. Token Usage Tracking

### 2.1 What We Track

Every request is logged to the `litellm.spend_logs` table in PostgreSQL with these dimensions:

| Field | Description |
|-------|-------------|
| `request_id` | UUID, unique per request |
| `api_key` | Hashed key identifier (not the raw key) |
| `user_id` | Authenticated user (from key metadata) |
| `team_id` | Team the user belongs to |
| `model` | Actual model that served the request (after routing) |
| `tokens_in` | Prompt tokens consumed |
| `tokens_out` | Completion tokens generated |
| `tokens_total` | Sum of in + out |
| `cost` | USD cost calculated from per-model pricing |
| `duration_ms` | End-to-end request duration |
| `status` | HTTP status code (200, 429, 5xx, etc.) |
| `timestamp` | UTC timestamp of request completion |

**Explicitly NOT tracked:** prompt content, response content, any PII. `store_prompts: false` and `store_responses: false` are set globally.

### 2.2 Prometheus Metrics

LiteLLM exposes these metrics on `:4000/metrics`:

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `litellm_requests_total` | Counter | `model`, `user`, `team`, `status` | Total API requests |
| `litellm_tokens_total` | Counter | `model`, `direction`, `user`, `team` | Total tokens (direction = input or output) |
| `litellm_cost_total` | Counter | `model`, `user`, `team`, `currency` | Total cost in USD |
| `litellm_latency_seconds` | Histogram | `model`, `quantile` | Request latency distribution |
| `litellm_cache_hits_total` | Counter | `model` | Semantic cache hit count |
| `litellm_queue_depth` | Gauge | `priority` | Current items in each queue tier |
| `litellm_health_status` | Gauge | `model` | 1 = healthy, 0 = unhealthy |

### 2.3 Grafana Dashboard Queries

#### Cost by Model (last 24 hours)

```promql
sum(rate(litellm_cost_total[24h])) by (model)
```

#### Cost by User (last 7 days)

```promql
sum(rate(litellm_cost_total[7d])) by (user)
```

#### Cost by Team (current month)

```promql
sum(increase(litellm_cost_total[30d])) by (team)
```

#### Token Consumption Rate by Model (per minute)

```promql
sum(rate(litellm_tokens_total[1m])) by (model)
```

#### Token Efficiency Ratio (output / input)

```promql
sum(rate(litellm_tokens_total{direction="output"}[1h]))
/
sum(rate(litellm_tokens_total{direction="input"}[1h]))
```

#### Cache Hit Rate

```promql
sum(rate(litellm_cache_hits_total[5m]))
/
sum(rate(litellm_requests_total[5m]))
```

#### Cost Per 1K Requests by Model

```promql
(sum(rate(litellm_cost_total[1h])) by (model))
/
(sum(rate(litellm_requests_total[1h])) by (model))
* 1000
```

### 2.4 Budget Alerts

| Alert | Threshold | Action |
|-------|-----------|--------|
| **Soft Limit Warning** | Spend > 80% of `soft_budget` ($8,000/month default) | Slack notification to `#ai-infra-alerts`, email to team leads |
| **Soft Limit Exceeded** | Spend > `soft_budget` | Slack + email, no request blocking yet |
| **Hard Limit** | Spend > `max_budget` ($10,000/month default) | **All requests rejected** with HTTP 402. Requires admin override to re-enable. |
| **Per-Team Soft Limit** | Team spend > 80% of team budget | Slack to team's channel |
| **Per-Team Hard Limit** | Team spend > team budget | Team requests rejected; other teams unaffected |

Budget resets on the 1st of each month (`budget_duration: "1mo"`). Rolling windows (`"30d"`) are available as an alternative.

---

## 3. Cost Monitoring

### 3.1 Per-Model Cost Rates (May 2026)

| Model | Input (per 1M tokens) | Output (per 1M tokens) | Cached Input | Provider |
|-------|----------------------|------------------------|-------------|----------|
| `deepseek-chat` | $0.14 | $0.28 | $0.014 | DeepSeek |
| `deepseek-reasoner` | $0.55 | $2.19 | $0.055 | DeepSeek |
| `gpt-4o` | $2.50 | $10.00 | $1.25 | OpenAI |
| `gpt-4o-mini` | $0.15 | $0.60 | $0.075 | OpenAI |
| `claude-opus-4-7` | $15.00 | $75.00 | $1.50 | Anthropic |
| `claude-sonnet-4-6` | $3.00 | $15.00 | $0.30 | Anthropic |

**Note:** These rates are embedded in LiteLLM's model cost map. LiteLLM automatically calculates cost per request as `(tokens_in * input_rate) + (tokens_out * output_rate)`. Rates should be reviewed quarterly as providers adjust pricing.

### 3.2 Cost Rollups

| Granularity | Source | Retention | Dashboard |
|-------------|--------|-----------|-----------|
| **Per-request** | PostgreSQL `spend_logs` | 90 days | Grafana "AI Spend Explorer" |
| **Hourly** | Prometheus `litellm_cost_total` rate | 30 days | Grafana "AI Cost Overview" |
| **Daily** | Prometheus recording rule or Mimir downsampling | 1 year | Grafana "AI Cost Trends" |
| **Weekly** | Manual rollup or scheduled report | Indefinite | Executive dashboard |
| **Monthly** | Mimir long-term storage | 2 years | Budget vs. actual report |

Sample Prometheus recording rule for daily cost rollup:

```yaml
groups:
  - name: litellm_cost_rollups
    rules:
      - record: litellm:cost:daily
        expr: sum(increase(litellm_cost_total[24h])) by (model, team)
```

### 3.3 Cost Anomaly Detection

Anomaly detection is implemented in Grafana Alerting using the following query:

```promql
(
  sum(rate(litellm_cost_total[1h]))
  >
  2 * sum(rate(litellm_cost_total[1h] offset 7d))
)
```

**Trigger:** Hourly cost > 2x the 7-day rolling average for the same hour-of-day.

**Severity:** Warning (not critical — could be a legitimate spike from a new workload).

**Response:**
1. Check the "Cost by User" dashboard panel to identify the source
2. If a single user/team is responsible, contact them to confirm legitimacy
3. If unauthorized, rotate the affected API key immediately
4. If authorized but unexpectedly high, review model routing (are they on the quality path when cheap would suffice?)

### 3.4 Showback and Chargeback

**Showback** (informational): A weekly automated report (Grafana dashboard snapshot or PDF) sent to each team lead showing their team's consumption and cost.

**Chargeback** (financial): At month-end, finance pulls the monthly cost by team from the `spend_logs` table (or the Grafana Mimir long-term store) and allocates costs to each department's budget.

Backup query for chargeback (run against PostgreSQL):

```sql
SELECT
    team_id,
    date_trunc('month', timestamp) AS month,
    SUM(cost) AS total_cost,
    SUM(tokens_total) AS total_tokens,
    COUNT(*) AS total_requests
FROM spend_logs
WHERE timestamp >= date_trunc('month', CURRENT_DATE)
GROUP BY team_id, date_trunc('month', timestamp)
ORDER BY total_cost DESC;
```

---

## 4. Request Queueing

### 4.1 Architecture

When `max_parallel_requests` (default: 100) is exceeded, incoming requests are pushed into a Redis-backed priority queue rather than rejected with 429. This smooths traffic spikes and prevents upstream API rate limits from causing failed requests.

```
Client → Traefik → LiteLLM Proxy → [Queue Full?]
                                       ├─ No → Route to model
                                       └─ Yes → Redis Queue → Worker polls → Route to model
```

### 4.2 Priority Tiers

| Priority | Queue Name | Target Latency | Max Depth | Use Case |
|----------|-----------|---------------|-----------|----------|
| **Real-time** | `litellm:queue:realtime` | <1s dequeue | 500 | Interactive chat, UI, copilots |
| **Batch** | `litellm:queue:batch` | <30s dequeue | 2,000 | Document processing, ETL pipelines |
| **Background** | `litellm:queue:background` | Best-effort | 10,000 | Data enrichment, backfills, non-urgent |

Clients select the queue via the `X-LiteLLM-Priority` HTTP header:

```bash
curl -X POST https://ai.wheeler.internal/v1/chat/completions \
  -H "Authorization: Bearer sk-..." \
  -H "X-LiteLLM-Priority: realtime" \
  -d '{"model": "cheap", "messages": [...]}'
```

If no header is provided, requests default to the `realtime` queue.

### 4.3 Queue Depth Monitoring

Prometheus metric: `litellm_queue_depth{priority="realtime|batch|background"}`

Grafana panel query:

```promql
litellm_queue_depth
```

Alert rules:

```yaml
# Queue backing up — potential upstream capacity issue
- alert: QueueDepthHigh
  expr: litellm_queue_depth{priority="realtime"} > 100
  for: 2m
  annotations:
    summary: "Realtime queue depth is {{ $value }} (threshold: 100)"

# Background queue at capacity — increase workers or reduce ingestion
- alert: QueueAtCapacity
  expr: litellm_queue_depth > litellm_queue_max_depth * 0.9
  for: 5m
  annotations:
    summary: "{{ $labels.priority }} queue at {{ $value }}/{{ $labels.max }} items"
```

### 4.4 Backpressure Handling

When any queue reaches its `max_queue_depth`, LiteLLM rejects new requests with:

- HTTP **503 Service Unavailable**
- Header `X-Queue-Status: full`
- Header `Retry-After: 30` (seconds)

The client should implement exponential backoff: 1s, 2s, 4s, 8s, 16s, then fail.

At the infrastructure level, the following triggers indicate backpressure:

1. **Queue depth > 80% capacity** for >60 seconds
2. **Average queue wait time > 5s** for realtime queue

Potential responses:
- Scale up parallel request limits (`max_parallel_requests`)
- Add a new model deployment (or GPU worker) to increase capacity
- Shed load: tell background jobs to pause ingestion
- Cloud burst: route overflow to a cloud API temporarily

---

## 5. Rate Limiting

### 5.1 Token Bucket Algorithm

LiteLLM implements a **token bucket** rate limiter per `(api_key, model)` pair.

```
Bucket parameters:
  capacity: max burst size (tokens or requests)
  refill_rate: tokens/requests added per second

Algorithm:
  On each request:
    1. Refill bucket: tokens += elapsed_seconds * refill_rate (capped at capacity)
    2. If tokens >= request_tokens: deduct and allow
    3. Else: reject (hard limit) or queue (soft limit)
```

### 5.2 Hard Limits vs. Soft Limits

| Type | Behavior | HTTP Response | Use Case |
|------|----------|--------------|----------|
| **Hard limit** | Request rejected immediately | 429 Too Many Requests | Protecting upstream APIs from abuse |
| **Soft limit** | Request queued with delay | 202 Accepted (queued) | Smoothing spikes, prioritizing traffic |

Hard limits are configured per-model in `router_settings.rate_limits.per_model_limits`. Soft limits are implemented via the request queue (see Section 4).

### 5.3 Rate Limit Headers

LiteLLM includes these headers in every response:

| Header | Example | Description |
|--------|---------|-------------|
| `X-RateLimit-Limit-Requests` | `1000` | Max RPM for this key/model |
| `X-RateLimit-Remaining-Requests` | `847` | RPM remaining in current window |
| `X-RateLimit-Limit-Tokens` | `500000` | Max TPM for this key/model |
| `X-RateLimit-Remaining-Tokens` | `412000` | TPM remaining in current window |
| `X-RateLimit-Reset` | `1716508800` | Unix timestamp when limits reset |

Clients should monitor `X-RateLimit-Remaining-*` and proactively slow down as they approach zero, rather than waiting for 429 responses.

### 5.4 Dual-Layer Rate Limiting

| Layer | Enforced By | Scope | Purpose |
|-------|------------|-------|---------|
| **Edge** | Traefik middleware | Per source IP | Prevent DDoS, block abusive IPs |
| **Proxy** | LiteLLM router | Per API key + model | Enforce business limits, fair sharing |

Traefik configuration (applied as a Docker label on the LiteLLM service):

```yaml
labels:
  - "traefik.http.middlewares.rate-limit.ratelimit.average=100"
  - "traefik.http.middlewares.rate-limit.ratelimit.burst=50"
  - "traefik.http.routers.litellm.middlewares=rate-limit"
```

**Rule:** Edge limits are generous (100 req/s per IP) and only catch abuse. Proxy limits are tight and enforce business policy.

---

## 6. GPU-Ready Architecture

### 6.1 Vision

The Wheeler infrastructure is designed to transition from 100% cloud-API to hybrid (GPU server primary, cloud API overflow) as demand grows. A dedicated GPU server (`gpu-worker`) on the Tailscale mesh will host self-hosted models via vLLM or TGI.

### 6.2 Architecture Diagram

```
                    ┌─────────────────────────────┐
                    │       Traefik (HTTPS)        │
                    │    ai.wheeler.internal       │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────▼───────────────┐
                    │      LiteLLM Proxy           │
                    │   Rate limit / Queue / Route │
                    └──┬──────────┬──────────┬─────┘
                       │          │          │
              ┌────────▼──┐ ┌─────▼────┐ ┌──▼──────────┐
              │ vLLM/TGI  │ │ DeepSeek │ │ OpenAI /     │
              │ gpu-worker│ │ API      │ │ Anthropic    │
              │ (PRIMARY) │ │(OVERFLOW)│ │ (OVERFLOW)   │
              └───────────┘ └──────────┘ └─────────────┘
```

### 6.3 vLLM Integration (Future)

When the GPU server is provisioned, LiteLLM will be configured with a local vLLM endpoint:

```yaml
model_list:
  - model_name: llama-3-70b-local
    litellm_params:
      model: openai/llama-3-70b           # vLLM exposes OpenAI-compatible API
      api_base: http://gpu-worker:8000/v1  # Tailscale MagicDNS hostname
      api_key: ${VLLM_API_KEY}             # Shared secret for vLLM auth
      rpm: 5000                            # No per-token API cost; higher limits
      tpm: 10000000
```

### 6.4 Overflow Strategy

Local models serve as the primary. When they are at capacity or unhealthy, requests overflow to cloud APIs:

```yaml
router_settings:
  fallbacks:
    # Local model overloaded → cheapest cloud model first
    - openai/llama-3-70b: ["deepseek/deepseek-chat", "openai/gpt-4o-mini"]
    # Local model with higher quality → quality cloud models
    - openai/llama-3-405b: ["openai/gpt-4o", "anthropic/claude-opus-4-7"]
```

### 6.5 Model Caching and Pre-Warming

**Pre-warming strategy:**

1. On GPU server boot (or model deployment), load the top 2-3 most-requested models into GPU VRAM
2. vLLM startup: `--model llama-3-70b --model qwen-2-72b` (multi-model loading)
3. Use vLLM's `--max-model-len` to limit context window, reserving VRAM for multiple models
4. Monitor VRAM usage via DCGM Prometheus metrics: `DCGM_FI_DEV_FB_USED`

**KV-cache optimization:**

- vLLM supports automatic prefix caching (APC) — reuses KV-cache across requests sharing a common prompt prefix
- This is especially valuable for RAG workloads where the system prompt and retrieved context are identical across many requests
- Expected cache hit rate improvement: 30-50% reduction in time-to-first-token

**Cold-start mitigation:**

- Keep a "liveness probe" that sends a tiny request every 60s to pre-loaded models to keep them resident in VRAM
- If a model is evicted (e.g., during a GPU OOM), the next request triggers a reload; budget 30-60s for model loading

### 6.6 Auto-Scaling GPU Workers

Scaling triggers based on Prometheus metrics:

| Trigger | Condition | Action |
|---------|-----------|--------|
| **Queue pressure** | `litellm_queue_depth{model="llama-3-70b-local"}` > 50 for 2min | Scale vLLM replica from 1 to 2 (if VRAM available) |
| **Latency degradation** | `litellm_latency_seconds{quantile="0.95"}` > 5x baseline | Preferentially route to cloud APIs until latency recovers |
| **GPU utilization** | `DCGM_FI_DEV_GPU_UTIL` > 90% for 5min | Route overflow to cloud APIs; log incident for capacity planning |
| **Idle GPU** | `DCGM_FI_DEV_GPU_UTIL` < 10% for 30min | Consider downscaling or reallocating GPU to other workloads |

For cloud bursting (when on-prem GPU is fully saturated), route to cheapest cloud API as temporary capacity:

```yaml
# Dynamic routing override (via admin API, no config change needed)
POST /model/update
{
  "model_name": "llama-3-70b-local",
  "litellm_params": {
    "fallbacks": ["deepseek/deepseek-chat", "openai/gpt-4o-mini"]
  }
}
```

---

## 7. Provider Health

### 7.1 Health Check Endpoints

Each upstream provider is probed by LiteLLM every 30 seconds. The probe is a lightweight request (model list or token count API) that validates:

1. The API endpoint is reachable (TCP connect + TLS handshake)
2. The API key is valid (authentication succeeds)
3. The API is responsive (response within 5 seconds)

| Provider | Health Check Endpoint | Expected Response |
|----------|----------------------|-------------------|
| DeepSeek | `GET https://api.deepseek.com/v1/models` | 200 with model list |
| OpenAI | `GET https://api.openai.com/v1/models` | 200 with model list |
| Anthropic | `POST https://api.anthropic.com/v1/messages` (minimal) | 200 (even if content is empty) |

LiteLLM exposes a composite health endpoint:

```bash
GET /health
```

Response:

```json
{
  "status": "healthy",
  "providers": {
    "deepseek/deepseek-chat": "healthy",
    "deepseek/deepseek-reasoner": "healthy",
    "openai/gpt-4o": "healthy",
    "openai/gpt-4o-mini": "healthy",
    "anthropic/claude-opus-4-7": "healthy",
    "anthropic/claude-sonnet-4-6": "unhealthy"
  },
  "queue_depth": {
    "realtime": 12,
    "batch": 45,
    "background": 230
  },
  "uptime_seconds": 1209600
}
```

### 7.2 Automatic Failover

When a provider is marked unhealthy, LiteLLM automatically routes all traffic for that provider to its configured fallbacks. This happens transparently — no client-side changes are needed.

**Failover sequence (example: DeepSeek outage):**

```
t=0s    DeepSeek returns 5xx. LiteLLM retries (1s backoff).
t=1s    Retry 1 fails. LiteLLM retries (2s backoff).
t=3s    Retry 2 fails. LiteLLM retries (4s backoff).
t=7s    Retry 3 fails. allowed_fails=3 reached.
        LiteLLM marks deepseek/deepseek-chat as "unhealthy".
        Cooldown timer starts (30s).
t=7s    Next cheap group request → routed to gpt-4o-mini (fallback 1).
t=37s   Cooldown expires. One probe request sent to DeepSeek.
t=37s   Probe returns 200 → DeepSeek marked "healthy", rejoins pool.
```

### 7.3 Circuit Breaker Pattern

The circuit breaker is implemented via LiteLLM's `allowed_fails` + `cooldown_time` parameters:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `allowed_fails` | 3 (configurable to 5) | Consecutive failures before opening the circuit |
| `cooldown_time` | 30s (configurable to 60s) | Duration to keep the circuit open before probing |
| Probe strategy | Single request | If probe succeeds, circuit closes; if it fails, cooldown restarts |

**Why not retry indefinitely?** Indefinite retries waste client time and upstream resources. The circuit breaker pattern fails fast, preserves resources, and recovers gracefully.

**Half-open state:** During cooldown, the circuit is "open" (no traffic). When cooldown expires, it enters "half-open" — one probe request goes through. Success → closed (normal), failure → open (restart cooldown).

### 7.4 Alert Rules

```yaml
groups:
  - name: litellm_provider_alerts
    rules:
      - alert: ProviderDown
        expr: litellm_health_status == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Provider {{ $labels.model }} is unhealthy"
          description: "{{ $labels.model }} has been down for >2 minutes. Traffic is routing to fallbacks."

      - alert: ProviderDegraded
        expr: rate(litellm_requests_total{status=~"5.."}[5m]) / rate(litellm_requests_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.model }} error rate > 10%"
          description: "Failure rate for {{ $labels.model }} is {{ $value | humanizePercentage }}. Investigate upstream status page."

      - alert: ProviderLatencySpike
        expr: histogram_quantile(0.95, rate(litellm_latency_seconds_bucket[5m])) > 30
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.model }} p95 latency > 30s"
```

---

## 8. Security

### 8.1 API Key Management

**Principle: No secrets in config files, no secrets in version control.**

| Key Type | Storage | Injection Method | Rotation |
|----------|---------|-----------------|----------|
| `LITELLM_MASTER_KEY` | Docker secret or HashiCorp Vault | Environment variable at container start | Every 90 days |
| `OPENAI_API_KEY` | Docker secret | Environment variable | Per OpenAI rotation policy |
| `ANTHROPIC_API_KEY` | Docker secret | Environment variable | Per Anthropic rotation policy |
| `DEEPSEEK_API_KEY` | Docker secret | Environment variable | Per DeepSeek rotation policy |
| `REDIS_PASSWORD` | Docker secret | Environment variable | Every 90 days |
| `DB_PASS` | Docker secret | Environment variable | Every 90 days |
| User/Team API keys | PostgreSQL (bcrypt hashed) | Generated via `/key/generate` admin endpoint | On user offboarding |

**Docker Compose secret mounting (example):**

```yaml
services:
  litellm:
    secrets:
      - litellm_master_key
      - openai_api_key
    environment:
      LITELLM_MASTER_KEY_FILE: /run/secrets/litellm_master_key
      OPENAI_API_KEY_FILE: /run/secrets/openai_api_key

secrets:
  litellm_master_key:
    external: true  # Created via: echo "sk-..." | docker secret create litellm_master_key -
```

### 8.2 Request Logging Policy

| Data | Logged? | Rationale |
|------|---------|-----------|
| Model name | Yes | Required for cost tracking |
| Token counts (in/out) | Yes | Required for cost calculation |
| User ID | Yes | Required for showback/chargeback |
| Team ID | Yes | Required for team budgets |
| Request ID | Yes | Required for distributed tracing correlation |
| Timestamp | Yes | Required for time-series analysis |
| Latency | Yes | Required for SLO monitoring |
| HTTP Status | Yes | Required for error rate monitoring |
| **Prompt content** | **No** | PII risk, intellectual property exposure |
| **Response content** | **No** | PII risk, intellectual property exposure |
| Raw API key | No | Hashed version only |
| Client IP | Yes (at Traefik layer only) | For abuse detection; not stored in LiteLLM logs |

Enforced via:

```yaml
general_settings:
  store_prompts: false
  store_responses: false
```

### 8.3 Data Flow and Encryption

```
Client ──HTTPS (TLS 1.3)──▶ Traefik ──HTTP──▶ LiteLLM ──HTTPS──▶ Upstream APIs
         Let's Encrypt            │   Tailscale     │   TLS 1.3
                               WireGuard mesh       │
                                                    │
                              ┌─────────────────────┘
                              │
                              ├──▶ PostgreSQL (Tailscale mesh, TLS optional)
                              ├──▶ Redis (Tailscale mesh, AUTH required)
                              └──▶ OTel Collector (gRPC, no PII in spans)
```

**Key points:**
- Client-to-Traefik: HTTPS with Let's Encrypt automatic cert renewal
- Internal mesh: Tailscale WireGuard encrypts all inter-service traffic at the network layer
- LiteLLM-to-upstream: HTTPS (provider APIs only accept TLS)
- PostgreSQL and Redis: isolated on the Tailscale mesh, not exposed to the public internet

### 8.4 Prompt Injection Detection

LiteLLM supports guardrail callbacks that inspect prompts before they reach the model. Recommended integrations:

| Tool | Purpose | Integration |
|------|---------|-------------|
| [Lakera Guard](https://lakera.ai) | Prompt injection, jailbreak, and PII detection | `lakera_guard` callback |
| [Microsoft Presidio](https://microsoft.github.io/presidio/) | PII detection and redaction | Custom pre-call hook |
| [Guardrails AI](https://www.guardrailsai.com/) | Structured output validation | Custom post-call hook |

LiteLLM config for Lakera Guard:

```yaml
litellm_settings:
  callbacks: ["lakera_guard"]
  lakera_guard:
    api_key: ${LAKERA_API_KEY}
    endpoint: "https://api.lakera.ai/v1"
    # Reject requests scored >0.8 on prompt injection
    threshold: 0.8
    mode: "block"  # "block" = reject request, "log" = only log
```

### 8.5 Rate Limiting by IP and by Key

**Layer 1 — Traefik (per source IP):**
- 100 requests/second per IP (generous — catches DDoS only)
- Burst: 50 additional requests
- Purpose: prevent volumetric attacks from reaching LiteLLM

**Layer 2 — LiteLLM (per API key + model):**
- Token bucket per `(key, model)` pair
- Limits defined in `router_settings.rate_limits.per_model_limits`
- Purpose: enforce business policy, fair sharing, budget adherence

**Two layers exist because they serve different purposes.** The edge layer protects infrastructure. The proxy layer enforces business rules. A user hitting their per-key limit should get a 429 with instructions to upgrade, not be IP-banned.

### 8.6 Admin API Access Control

The LiteLLM admin API (`/key/generate`, `/team/new`, `/user/new`, etc.) is protected by the master key and should only be accessible from the internal network:

```yaml
# Traefik middleware: block /key/*, /team/*, /user/* from external access
labels:
  - "traefik.http.middlewares.admin-block.ipwhitelist.sourcerange=100.64.0.0/10"
  - "traefik.http.routers.litellm-admin.rule=Host(`ai.wheeler.internal`) && PathPrefix(`/key/`, `/team/`, `/user/`)"
  - "traefik.http.routers.litellm-admin.middlewares=admin-block"
```

---

## 9. Observability

### 9.1 Metrics Pipeline

```
LiteLLM (:4000/metrics)
    │
    ▼
Grafana Agent (scrapes every 15s)
    │
    ▼
Grafana Mimir (long-term metrics storage, 13 months retention)
    │
    ▼
Grafana Dashboards
    │
    ├── AI Infrastructure Overview
    ├── AI Cost Explorer
    ├── AI Latency & Errors
    └── AI Team Showback
```

### 9.2 Key Grafana Dashboard Panels

#### AI Infrastructure Overview

| Panel | Type | Query |
|-------|------|-------|
| **Requests/sec by model** | Time series | `sum(rate(litellm_requests_total[1m])) by (model)` |
| **Tokens/sec by model** | Time series | `sum(rate(litellm_tokens_total[1m])) by (model, direction)` |
| **Cost per minute** | Stat (gauge) | `sum(rate(litellm_cost_total[1m])) * 60` |
| **Active providers** | Table | `litellm_health_status` grouped by model |
| **Queue depth** | Time series | `litellm_queue_depth` by priority |
| **Cache hit rate** | Stat (gauge) | `sum(rate(litellm_cache_hits_total[5m])) / sum(rate(litellm_requests_total[5m]))` |
| **Budget utilization** | Bar gauge | `sum(litellm_cost_total) / ${BUDGET} * 100` |
| **Fallback rate** | Time series | Percentage of requests served by fallback model vs. primary |

#### AI Cost Explorer

| Panel | Type | Query |
|-------|------|-------|
| **Cost by model (24h)** | Pie chart | `sum(rate(litellm_cost_total[24h])) by (model)` |
| **Cost by team (7d)** | Bar chart | `sum(rate(litellm_cost_total[7d])) by (team)` |
| **Cost by user (7d)** | Table | `sum(rate(litellm_cost_total[7d])) by (user)` |
| **Cost trend (30d)** | Time series | `sum(rate(litellm_cost_total[1h])) by (model)` |
| **Cost per 1K tokens by model** | Table | `sum(rate(litellm_cost_total[1h])) / sum(rate(litellm_tokens_total[1h])) * 1e6` |
| **Daily cost (month)** | Bar chart | `sum(increase(litellm_cost_total[1d]))` over 30 days |

#### AI Latency & Errors

| Panel | Type | Query |
|-------|------|-------|
| **p50/p95/p99 Latency by model** | Time series | `histogram_quantile(0.50/0.95/0.99, rate(litellm_latency_seconds_bucket[5m])) by (model)` |
| **Error rate by model** | Time series | `sum(rate(litellm_requests_total{status=~"5.."}[5m])) by (model) / sum(rate(litellm_requests_total[5m])) by (model)` |
| **4xx vs 5xx breakdown** | Time series | `sum(rate(litellm_requests_total[5m])) by (status)` |
| **Fallback activations** | Counter | Number of times a fallback model served a request (inferred from model != requested model) |
| **Provider health timeline** | State timeline | `litellm_health_status` over time (1=up, 0=down) |

### 9.3 Alert Rules

All alerts route through Grafana Alerting (or Prometheus Alertmanager), with notifications to Slack `#ai-infra-alerts` for warnings and PagerDuty for criticals.

#### Provider Alerts

```yaml
- alert: ProviderDown
  expr: litellm_health_status == 0
  for: 2m
  severity: critical
  summary: "{{ $labels.model }} is DOWN. All traffic is on fallbacks."

- alert: ProviderDegraded
  expr: rate(litellm_requests_total{status=~"5.."}[5m]) / rate(litellm_requests_total[5m]) > 0.1
  for: 5m
  severity: warning
  summary: "{{ $labels.model }} error rate >10% — check provider status page."

- alert: ProviderLatencySpike
  expr: histogram_quantile(0.95, rate(litellm_latency_seconds_bucket[5m])) > 15
  for: 5m
  severity: warning
  summary: "{{ $labels.model }} p95 latency >15s"
```

#### Cost Alerts

```yaml
- alert: BudgetSoftLimit
  expr: sum(litellm_cost_total) > 8000  # Adjust to match soft_budget
  severity: warning
  summary: "Monthly spend > $8,000 (soft limit)"

- alert: BudgetHardLimit
  expr: sum(litellm_cost_total) > 10000  # Adjust to match max_budget
  severity: critical
  summary: "Monthly spend > $10,000 (hard limit) — ALL requests WILL BE BLOCKED"

- alert: CostAnomaly
  expr: sum(rate(litellm_cost_total[1h])) > 2 * sum(rate(litellm_cost_total[1h] offset 7d))
  severity: warning
  summary: "Hourly cost spike detected — 2x above 7-day average"
```

#### Rate Limit Alerts

```yaml
- alert: RateLimitHit
  expr: rate(litellm_requests_total{status="429"}[5m]) > 0.05
  for: 5m
  severity: warning
  summary: "5%+ of requests are being rate-limited (429). Check team limits."
```

#### Queue Alerts

```yaml
- alert: QueueBackpressure
  expr: litellm_queue_depth{priority="realtime"} > 100
  for: 2m
  severity: warning
  summary: "Realtime queue backing up ({{ $value }} items). Consider scaling."

- alert: QueueAtCapacity
  expr: litellm_queue_depth > litellm_queue_max_depth * 0.9
  for: 5m
  severity: critical
  summary: "{{ $labels.priority }} queue at 90%+ capacity. New requests will be rejected."
```

### 9.4 Distributed Tracing

OpenTelemetry spans provide end-to-end visibility into each request:

```
Traefik Span
  └── LiteLLM Span
        ├── Redis Cache Lookup Span (cache hit/miss)
        ├── Queue Wait Span (if queued)
        └── Upstream API Call Span
              ├── Request serialization
              ├── Network round-trip
              └── Response deserialization
```

Span attributes include: `model`, `tokens_in`, `tokens_out`, `cost`, `user_id`, `team_id`, `cache_hit`, `fallback_model` (if applicable). Prompt and response content are NEVER added to span attributes.

Trace sampling: 10% of all requests are traced (configurable via `otel` settings). 100% of error requests are traced.

### 9.5 Logging Pipeline

```
LiteLLM (JSON to stdout)
    │
    ▼
Docker JSON File Log Driver
    │
    ▼
Grafana Alloy / Promtail (scrapes /var/lib/docker/containers)
    │
    ▼
Grafana Loki (log aggregation, 90-day retention)
    │
    ▼
Grafana Explore (query: {container="litellm"} |= "error")
```

**Log format (example):**

```json
{
  "timestamp": "2026-05-23T14:30:00.000Z",
  "level": "info",
  "event": "request_completed",
  "request_id": "b3e8f4a2-...",
  "model": "deepseek-v4-pro",
  "tokens_in": 1250,
  "tokens_out": 340,
  "cost": 0.00027,
  "duration_ms": 1850,
  "status": 200,
  "user_id": "usr_engineering_01",
  "team_id": "team_engineering",
  "cache_hit": false,
  "fallback_used": false
}
```

Note: No prompt or response content. No raw API keys. No PII.

### 9.6 Runbooks

Each alert in Section 9.3 maps to a runbook. Runbooks are stored in the Wheeler Infrastructure wiki (link TBD). Quick-reference summaries:

| Alert | First Response |
|-------|---------------|
| **ProviderDown** | 1. Check provider status page. 2. If provider-side outage, wait it out (traffic is on fallbacks). 3. If it is a key/credential issue, rotate keys. 4. If persistent, consider adding another provider to the fallback chain. |
| **BudgetSoftLimit** | 1. Open the AI Cost Explorer dashboard. 2. Identify which team(s) are driving the spend increase. 3. Contact team leads to confirm legitimacy. 4. If unauthorized, rotate the affected key. |
| **CostAnomaly** | 1. Check "Cost by User (7d)" for the top spender. 2. Check if they switched to the quality path unintentionally. 3. Check for looping or runaway agent patterns. 4. If legitimate, note for capacity planning. |
| **ProviderLatencySpike** | 1. Check the provider's status page for incidents. 2. Check Tailscale mesh health between LiteLLM and the internet gateway. 3. If persistent >5min, latency-based routing should auto-route away from the slow provider. |
| **QueueBackpressure** | 1. Check if a provider is down (causing all traffic to queue). 2. If all providers are healthy, increase `max_parallel_requests`. 3. Consider spinning up a GPU worker for additional capacity. |

---

## Appendix A: Cost Comparison Reference (May 2026)

| Model | 1K Requests at 1K tokens each | 1M Requests at 1K tokens each | 1K Requests at 10K tokens each |
|-------|------------------------------|-------------------------------|--------------------------------|
| `deepseek-chat` | $0.42 | $420 | $2.80 |
| `gpt-4o-mini` | $0.75 | $750 | $6.15 |
| `gpt-4o` | $12.50 | $12,500 | $102.50 |
| `claude-sonnet-4-6` | $18.00 | $18,000 | $153.00 |
| `claude-opus-4-7` | $90.00 | $90,000 | $765.00 |

**Bottom line:** DeepSeek is 50-200x cheaper than Claude Opus for equivalent token volumes. This is why the cost-optimized path uses DeepSeek for 80%+ of total traffic.

## Appendix B: Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LITELLM_MASTER_KEY` | Yes | — | Master key for LiteLLM admin API |
| `DEEPSEEK_API_KEY` | Yes | — | DeepSeek API key |
| `OPENAI_API_KEY` | Yes | — | OpenAI API key |
| `ANTHROPIC_API_KEY` | Yes | — | Anthropic API key |
| `DB_USER` | Yes | — | PostgreSQL user for LiteLLM database |
| `DB_PASS` | Yes | — | PostgreSQL password |
| `REDIS_HOST` | Yes | — | Redis hostname (Tailscale) |
| `REDIS_PASSWORD` | Yes | — | Redis AUTH password |
| `LITELLM_MAX_BUDGET` | No | `10000` | Monthly hard budget cap in USD |
| `LITELLM_SOFT_BUDGET` | No | `8000` | Monthly soft budget warning in USD |
| `LAKERA_API_KEY` | No | — | Lakera Guard API key for prompt injection detection |
| `SLACK_ALERTS_WEBHOOK` | No | — | Slack webhook for budget/provider alerts |
| `VLLM_API_KEY` | No | — | vLLM API key (future GPU deployment) |

## Appendix C: Quick Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| All requests failing | Master key or provider keys expired | Check `/health`; rotate keys |
| High latency | All traffic on a slow provider | Check fallback chains; latency routing should auto-fix |
| 429 responses | Rate limit hit | Check `X-RateLimit-Remaining-*` headers; bump limits or distribute load |
| 402 responses | Budget exceeded | Increase `max_budget` or wait until next cycle |
| 503 responses | Queue at capacity | Scale up `max_parallel_requests` or add GPU worker |
| High cost | Quality path used for cheap tasks | Check team model group assignments |
| `unhealthy` provider | Provider outage or key invalid | Check provider status page; rotate key if needed |
