# Retry Handling Improvements
## Wheeler AI Routing -- Phase 7 Optimization

### Current State: ZERO retry logic at any layer. First failure = permanent failure.

---

## 1. THE PROBLEM

### 1.1 Current Behavior

```
Agent sends request
  -> LiteLLM forwards to DeepSeek
    -> Network blip (transient 503)
      -> LiteLLM returns error to agent
        -> llm_client.py catches exception, returns None
          -> Agent task FAILS
```

Every transient error (network hiccup, brief API overload, DNS resolution delay) results in a hard failure. There is NO retry at any layer.

### 1.2 What Should Happen

```
Agent sends request
  -> LiteLLM forwards to DeepSeek
    -> Network blip (transient 503)
      -> LiteLLM retries after 1s (attempt 1/3)
        -> Still 503
          -> LiteLLM retries after 2s (attempt 2/3)
            -> Success! Returns response to agent
```

---

## 2. IMPLEMENTATION: THREE-LAYER RETRY STRATEGY

### Layer 1: LiteLLM Proxy Retry (catch-all)

Configured in `litellm-deepseek.yaml`:

```yaml
litellm_settings:
  num_retries: 3                   # Max 3 total retries across all attempts
  num_retries_per_request: 2       # Max 2 retries per individual request leg

router_settings:
  retry_policy:
    strategy: "exponential_backoff"
    base_delay: 1                  # First retry after 1 second
    max_delay: 30                  # Cap at 30 seconds
    jitter: true                   # Add random 0-1s jitter to prevent thundering herd

  # Only retry on transient errors (NOT client errors)
  retry_on_status_codes: [429, 500, 502, 503, 504]

  # Don't retry if we've already exceeded time budget
  retry_timeout: 120               # Give up after 2 minutes total
```

**Behavior**:
- Attempt 1: immediate
- Attempt 2: wait 1s + jitter
- Attempt 3: wait 2s + jitter
- Attempt 4: wait 4s + jitter
- After 4 attempts (1 original + 3 retries) or 120s, return error

### Layer 2: Application-Level Retry (llm_client.py)

Python retry wrapper with exponential backoff:

```python
import asyncio
import random
from typing import Optional

RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}
MAX_RETRIES = 3
BASE_DELAY = 1.0
MAX_DELAY = 30.0
JITTER = 0.5  # +/- 50% jitter

async def _retry_with_backoff(func, *args, **kwargs):
    """Retry an async function with exponential backoff and jitter."""
    last_exception = None

    for attempt in range(MAX_RETRIES + 1):
        try:
            return await func(*args, **kwargs)
        except httpx.HTTPStatusError as e:
            last_exception = e
            if e.response.status_code not in RETRYABLE_STATUS_CODES:
                raise  # Don't retry client errors (400, 401, 403, 404)
            if attempt == MAX_RETRIES:
                raise  # Exhausted retries

        except (httpx.TimeoutException, httpx.ConnectError, httpx.RemoteProtocolError) as e:
            last_exception = e
            if attempt == MAX_RETRIES:
                raise

        except Exception as e:
            last_exception = e
            raise  # Don't retry unexpected errors

        # Calculate delay with exponential backoff and jitter
        delay = min(BASE_DELAY * (2 ** attempt), MAX_DELAY)
        jitter = delay * JITTER * (2 * random.random() - 1)  # +/- 50%
        delay = delay + jitter

        logger.info(
            "Retry attempt %d/%d for %s, waiting %.1fs",
            attempt + 1, MAX_RETRIES, func.__name__, delay,
        )
        await asyncio.sleep(delay)

    raise last_exception


@observe(as_type="generation")
async def llm_complete_async(
    messages: list[dict],
    model: str = DEFAULT_MODEL,
    temperature: float = 0.7,
    max_tokens: int = 2048,
    agent: Optional[str] = None,
    workflow: Optional[str] = None,
    response_format: Optional[dict] = None,
    max_retries: int = MAX_RETRIES,
) -> Optional[str]:
    """Async version of llm_complete with retry support."""
    _start = time.monotonic()

    # ... existing Langfuse setup ...

    async def _do_call():
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                f"{LITELLM_URL}/chat/completions",
                json=payload,
                headers=headers,
            )
            resp.raise_for_status()
            return resp.json()

    try:
        data = await _retry_with_backoff(_do_call)
        # ... rest of existing success handling ...

    except Exception as e:
        logger.warning(
            "[llm_client] LLM call failed after %d retries (model=%s): %s",
            max_retries, model, e,
        )
        # ... existing error handling ...
        return None
```

### Layer 3: LiteLLM Internal Retry (model-level)

Configured per model in the model_list:

```yaml
model_list:
  - model_name: deepseek-chat
    litellm_params:
      model: openai/deepseek-chat
      max_retries: 3              # LiteLLM internal retries for this model
      retry_delay: 2              # Wait 2 seconds between retries

  - model_name: deepseek-reasoner
    litellm_params:
      model: openai/deepseek-reasoner
      max_retries: 2              # Fewer retries for slower model

  - model_name: claude-sonnet-4
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      max_retries: 1              # Minimal retries for expensive model

  - model_name: claude-opus-4
    litellm_params:
      model: anthropic/claude-opus-4-20250514
      max_retries: 1              # Single retry only (cost guard)
```

---

## 3. RETRY DECISION TREE

```
                     ┌──────────────┐
                     │  API Call    │
                     └──────┬───────┘
                            │
                     ┌──────▼───────┐
                ┌────│  Response?   │──── Success ────▶ Return result
                │    └──────────────┘
                │
        ┌───────▼────────┐
        │ What failed?    │
        └───────┬────────┘
                │
    ┌───────────┼───────────┬──────────────┐
    │           │           │              │
    ▼           ▼           ▼              ▼
  429        5xx        Timeout       4xx (not 429)
  │           │           │              │
  ▼           ▼           ▼              ▼
 RETRY      RETRY       RETRY        DO NOT RETRY
(with       (with       (with        (client error —
 backoff)   backoff)    backoff)      retry won't help)
```

---

## 4. RETRY BUDGETING

### 4.1 Avoid Retry Storms

When a model or provider goes down, ALL pending requests retry simultaneously. This creates a "retry storm" that can overwhelm the recovering service.

**Mitigation**:
- **Jitter**: Add random delay to each retry (already configured above)
- **Circuit Breaker**: After 3 consecutive failures, stop sending requests entirely for `cooldown_time` seconds
- **Rate limit retries separately**: Retry attempts count toward the RPM limit

```yaml
router_settings:
  allowed_fails: 3
  cooldown_time: 30
  allowed_fails_policy:
    bad_request_errors: false     # Don't count 400 errors
    authentication_errors: false  # Don't count 401/403
```

### 4.2 Per-Model Retry Budgets

Set different retry strategies based on cost:

| Model | Max Retries | Backoff Start | Max Backoff | Total Time Budget |
|-------|-------------|---------------|-------------|-------------------|
| deepseek-chat | 3 | 1s | 30s | 60s |
| deepseek-reasoner | 2 | 2s | 30s | 90s |
| claude-sonnet-4 | 1 | 5s | 60s | 120s |
| claude-opus-4 | 1 | 10s | 60s | 180s |

Claude models have fewer retries and longer delays because each retry costs more.

---

## 5. MONITORING RETRY HEALTH

Track these metrics after enabling retries:

1. **Retry rate**: `retry_count / total_requests` -- target: <5%
2. **Retry success rate**: `retry_success / retry_count` -- target: >80%
3. **Fallback rate**: `fallback_count / total_requests` -- target: <2%
4. **Average attempts per request**: should be close to 1.0
5. **Retry latency overhead**: how many extra seconds retries add to p95 latency

### Alerting Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Retry rate | >10% | >25% |
| Fallback rate | >5% | >15% |
| Circuit breaker trips | >2/hour | >10/hour |

---

## 6. IMPLEMENTATION CHECKLIST

- [ ] Add `num_retries: 3` and `num_retries_per_request: 2` to LiteLLM config
- [ ] Configure exponential backoff with jitter
- [ ] Set `allowed_fails: 3` and `cooldown_time: 30`
- [ ] Set per-model `max_retries` in model_list
- [ ] Add retry wrapper to `llm_client.py` (Python async and sync)
- [ ] Add retry wrapper to agent `model.js` (Node.js)
- [ ] Only retry on 429, 5xx, and timeout -- NEVER on 4xx
- [ ] Add retry metrics to monitoring
- [ ] Test by temporarily blocking DeepSeek and verifying graceful fallback+retry
