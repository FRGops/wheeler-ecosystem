# Timeout Tuning
## Wheeler AI Routing -- Phase 7 Optimization

### Current State: No model-specific timeouts. Global default = 600s (LiteLLM), 60s (httpx client). One-size-fits-all approach.

---

## 1. THE PROBLEM

### 1.1 Why Generic Timeouts Fail

| Scenario | Current Behavior | Problem |
|----------|-----------------|---------|
| DeepSeek Flash | 60s timeout (httpx client) | Should be 30s -- Flash is fast; waiting 60s is wasted time |
| DeepSeek Reasoner | 60s timeout (httpx client) | Complex reasoning can take 40-60s; 60s is tight |
| Claude Opus | 60s timeout (httpx client) | Opus can legitimately need 90-120s for complex tasks |
| LiteLLM global | 600s (10 min) | Too high -- if a request hasn't completed in 2 minutes, it probably never will |

### 1.2 The Timeout Stack

```
┌─────────────────────────────────────────────────┐
│  LiteLLM global request_timeout: 600s             │  ← Last resort safety net
│  ┌───────────────────────────────────────────┐   │
│  │  Model-specific timeout:                   │   │
│  │    deepseek-chat:      30s                │   │  ← First line of defense
│  │    deepseek-reasoner:  60s                │   │
│  │    claude-sonnet-4:    90s                │   │
│  │    claude-opus-4:      120s               │   │
│  │  ┌─────────────────────────────────────┐  │   │
│  │  │  Client timeout (httpx): 60-120s     │  │   │  ← Application-level
│  │  │  ┌───────────────────────────────┐   │  │   │
│  │  │  │  Stream timeout: per-model    │   │  │   │  ← For streaming only
│  │  │  │  DeepSeek Flash: 15s          │   │  │   │
│  │  │  │  DeepSeek Reasoner: 30s       │   │  │   │
│  │  │  └───────────────────────────────┘   │  │   │
│  │  └─────────────────────────────────────┘  │   │
│  └───────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

The rule: **inner timeouts MUST be shorter than outer timeouts**, otherwise the outer timeout fires first and you get generic errors instead of meaningful timeout messages.

---

## 2. RECOMMENDED TIMEOUT CONFIGURATION

### 2.1 LiteLLM Configuration

```yaml
# Global safety net
litellm_settings:
  request_timeout: 180           # 3 minutes global max (was 600s, too high)
  stream_timeout: 60             # 60s for streaming

# Per-model timeouts (in model_list)
model_list:
  - model_name: deepseek-chat
    litellm_params:
      timeout: 30                # Flash responds in 1-5s typically
      stream_timeout: 15

  - model_name: deepseek-reasoner
    litellm_params:
      timeout: 60                # Reasoning takes longer
      stream_timeout: 30

  - model_name: claude-sonnet-4
    litellm_params:
      timeout: 90                # Claude is slower
      stream_timeout: 30

  - model_name: claude-opus-4
    litellm_params:
      timeout: 120               # Opus is the slowest
      stream_timeout: 45

  - model_name: premium_review
    litellm_params:
      timeout: 90                # Same as Sonnet
      stream_timeout: 30
```

### 2.2 LiteLLM Router-Level Timeouts

```yaml
router_settings:
  # Total time budget including retries and fallbacks
  routing_timeout: 120           # Give up after 2 minutes total

  # Per-fallback-leg timeout
  retry_policy:
    retry_timeout: 120           # Retries stop after 2 minutes total

  # Queue timeout (when concurrency limit is hit)
  queue_config:
    queue_timeout: 30            # 30s max in queue
```

### 2.3 Client-Side (llm_client.py) Timeouts

```python
# Timeout map (can be used by both sync and async clients)
MODEL_TIMEOUTS = {
    "deepseek-chat": 30,
    "cheap_coder": 30,
    "deepseek-reasoner": 60,
    "heavy_coder": 60,
    "claude-sonnet-4": 90,
    "claude-haiku-4-5": 30,
    "claude-sonnet-4-6": 90,
    "claude-opus-4": 120,
    "claude-opus-4-7": 120,
    "premium_review": 90,
    "default": 60,
}

def get_timeout(model: str) -> int:
    """Get appropriate timeout for a model."""
    for key, timeout in MODEL_TIMEOUTS.items():
        if key in model.lower():
            return timeout
    return MODEL_TIMEOUTS["default"]


# In the async client:
async def llm_complete_async(messages, model=DEFAULT_MODEL, ...):
    timeout = get_timeout(model)
    async with httpx.AsyncClient(timeout=timeout) as client:
        resp = await client.post(...)
        ...


# In streaming client:
async def llm_stream_async(messages, model=DEFAULT_MODEL, ...):
    # Streaming needs slightly longer timeout (account for generation time)
    timeout = get_timeout(model) + 30  # Add 30s for streaming overhead
    async with httpx.AsyncClient(timeout=timeout) as client:
        ...
```

---

## 3. TIMEOUT DECISION MATRIX

### 3.1 How We Chose These Numbers

| Model | Typical P50 Latency | Typical P95 Latency | Timeout Set To | Headroom |
|-------|--------------------|--------------------|----------------|----------|
| deepseek-chat | 2-3s | 5-8s | 30s | 6x p50, 3.75x p95 |
| deepseek-reasoner | 5-8s | 15-20s | 60s | 7.5x p50, 3x p95 |
| claude-sonnet-4 | 3-5s | 10-15s | 90s | 18x p50, 6x p95 |
| claude-opus-4 | 8-12s | 25-35s | 120s | 10x p50, 3.4x p95 |

Headroom is intentionally generous for Claude models because:
1. Each Claude call costs 10-50x more than DeepSeek
2. Timing out an Opus call after 60s of processing is expensive waste
3. Claude's latency variance is higher than DeepSeek's

### 3.2 What Timeout Value Is Right?

**Too short**: Requests are killed before the model finishes. Wasted tokens. Retries compound the waste.
**Too long**: Users wait, connections pile up, resources are held unnecessarily.
**Just right**: ~3-6x the p95 latency. Gives headroom for variance without being excessively long.

---

## 4. RETRY + TIMEOUT INTERACTION

Retries multiply the total time budget:

```
deepseek-chat:  30s timeout x 3 retries = 90s max total
deepseek-reasoner: 60s timeout x 2 retries = 120s max total
claude-sonnet-4: 90s timeout x 1 retry = 180s max total
claude-opus-4: 120s timeout x 1 retry = 240s max total
```

The `routing_timeout: 120` (LiteLLM) will cap most of these. For Claude Opus, the 240s theoretical max is acceptable because Opus calls are rare and expensive (better to wait than waste).

---

## 5. CONNECTION TIMEOUTS

Separate from model timeouts, connection-level timeouts should be short:

```yaml
# LiteLLM connection settings
general_settings:
  request_timeout: 10            # 10s to establish connection (NOT model processing)
  connect_timeout: 5             # 5s TCP connect timeout
  read_timeout: 180              # 180s for reading response (covers all models)
```

These are about network-level operations (DNS, TCP handshake, TLS negotiation), not model processing time.

---

## 6. MONITORING TIMEOUTS

Track these metrics:

1. **Timeout rate**: `timeout_count / total_requests` per model
2. **Timeout distribution**: histogram of when timeouts occur (are they all at the limit, or scattered?)
3. **p95 latency vs timeout**: if p95 approaches 80% of timeout, increase timeout
4. **Wasted tokens from timeouts**: tokens consumed by timed-out requests

### Alerting

| Metric | Warning | Critical |
|--------|---------|----------|
| Timeout rate (deepseek-chat) | >2% | >5% |
| Timeout rate (deepseek-reasoner) | >5% | >10% |
| Timeout rate (Claude) | >1% | >3% |
| p95 latency approaching timeout | >60% of timeout | >80% of timeout |

---

## 7. IMPLEMENTATION CHECKLIST

- [ ] Set per-model timeouts in LiteLLM config (deepseek-chat: 30s, reasoner: 60s, Claude: 90-120s)
- [ ] Set `request_timeout: 180` as global safety net (down from 600s)
- [ ] Set `routing_timeout: 120` for retries + fallbacks total
- [ ] Set connection-level timeouts (connect: 5s, read: 180s)
- [ ] Add `get_timeout()` function to llm_client.py
- [ ] Add `MODEL_TIMEOUTS` map
- [ ] Use model-specific timeout for httpx.AsyncClient
- [ ] Add timeout metrics to monitoring
- [ ] Set timeout alerting thresholds
- [ ] Run load test to validate timeouts don't fire prematurely
