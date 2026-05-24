# Concurrency & Batching Recommendations
## Wheeler AI Routing -- Phase 7 Optimization

### Current State: 8 agent-svc processes, burst pattern of 15-20 concurrent requests, no coordination

---

## 1. PROBLEM ANALYSIS

### 1.1 Burst Behavior

Log analysis shows a clear burst pattern:
```
[04:16:55] POST /v1/chat/completions 200 OK  (port 24880)
[04:16:55] POST /v1/chat/completions 200 OK  (port 24892)
[04:16:55] POST /v1/chat/completions 200 OK  (port 24870)
[04:16:55] POST /v1/chat/completions 200 OK  (port 24912)
[04:16:55] POST /v1/chat/completions 200 OK  (port 24896)
[04:16:55] POST /v1/chat/completions 200 OK  (port 24894)
[04:16:55] POST /v1/chat/completions 200 OK  (port 24932)
[04:16:55] POST /v1/chat/completions 200 OK  (port 24944)
[04:16:55] POST /v1/chat/completions 200 OK  (port 24922)
[04:16:55] POST /v1/chat/completions 200 OK  (port 24956)
... (15-20 requests in rapid succession)
```

**Pattern**: All 8 agent-svc processes fire their AI calls simultaneously (likely triggered by the same scheduler event), causing a wave of 15-20 requests to hit LiteLLM within the same second.

### 1.2 Impact

1. **DeepSeek rate limiting risk**: Sending 20 concurrent requests may trigger 429 responses
2. **No prioritization**: Critical revenue tasks compete equally with background analytics
3. **Resource contention**: All requests fight for the same LiteLLM worker threads
4. **Cascading timeouts**: When one request times out, it doesn't slow down others

---

## 2. SOLUTION: CONCURRENCY CONTROL AT LITELLM

### 2.1 Global max_parallel_requests

Set `max_parallel_requests: 10` at the global LiteLLM level. This caps the number of simultaneous API calls in flight across ALL models and ALL callers.

```yaml
litellm_settings:
  max_parallel_requests: 10
```

This means if 20 requests arrive simultaneously, the first 10 proceed immediately and the remaining 10 are queued. Queued requests wait for an in-flight request to complete before being dispatched.

### 2.2 Per-Model Concurrency Limits

Tighter limits for expensive models:

```yaml
router_settings:
  max_parallel_requests: 10

model_list:
  - model_name: deepseek-chat
    litellm_params:
      max_parallel_requests: 10   # 10 concurrent to deepseek-chat

  - model_name: deepseek-reasoner
    litellm_params:
      max_parallel_requests: 5    # 5 concurrent (slower model)

  - model_name: claude-sonnet-4
    litellm_params:
      max_parallel_requests: 2    # 2 concurrent (expensive)

  - model_name: claude-opus-4
    litellm_params:
      max_parallel_requests: 1    # 1 concurrent (extremely expensive)
```

### 2.3 Request Queuing with Priority

Agents should tag their requests with priority levels so critical tasks jump the queue:

```yaml
# Agent-side: add priority header to requests
headers:
  X-Priority: "high"     # For revenue-critical tasks
  X-Priority: "normal"   # For standard tasks
  X-Priority: "low"      # For background/analytics tasks
```

LiteLLM configuration:
```yaml
router_settings:
  queue_config:
    enabled: true
    max_queue_size: 100
    priority_headers: ["X-Priority"]
    priority_values:
      high: 1      # Highest priority
      normal: 5    # Standard
      low: 10      # Lowest priority
    queue_timeout: 30   # Max seconds in queue before rejection
```

---

## 3. SOLUTION: REQUEST COALESCING (BATCHING)

### 3.1 Semantic Request Coalescing

When multiple agents request the same (or nearly identical) prompt within a short window, coalesce them into a single API call.

**Implementation Strategy**:

1. **Prompt Hashing**: Before forwarding to API, compute SHA-256 of `[model, system_prompt, user_prompt]`
2. **Short Window**: Hold identical requests for 50-100ms
3. **First Wins**: The first request proceeds; subsequent identical requests wait
4. **Broadcast**: When the response arrives, return it to all waiting callers

**Code Pattern** (could be added as LiteLLM middleware):

```python
import hashlib
import asyncio
from collections import defaultdict

class RequestCoalescer:
    def __init__(self, window_ms: int = 100):
        self.window_ms = window_ms
        self.pending: dict[str, list[asyncio.Future]] = defaultdict(list)

    def hash_request(self, model: str, messages: list[dict]) -> str:
        content = model + "||" + json.dumps(messages, sort_keys=True)
        return hashlib.sha256(content.encode()).hexdigest()

    async def coalesce(self, model, messages, make_call):
        request_hash = self.hash_request(model, messages)

        if request_hash in self.pending:
            # Someone else is already calling this — wait for their result
            future = asyncio.get_event_loop().create_future()
            self.pending[request_hash].append(future)
            return await future

        # We're the first — make the call
        self.pending[request_hash] = []
        try:
            result = await asyncio.wait_for(make_call(), timeout=self.window_ms / 1000)
        except Exception as e:
            result = e

        # Broadcast to all waiters
        for future in self.pending[request_hash]:
            if isinstance(result, Exception):
                future.set_exception(result)
            else:
                future.set_result(result)

        del self.pending[request_hash]
        return result
```

### 3.2 Provider-Side Batching (DeepSeek)

DeepSeek supports batch processing at a discount. Enable LiteLLM's batch support:

```yaml
litellm_settings:
  batch_completions: true
  batch_completions_max_requests: 50    # Max 50 requests per batch
  batch_completions_window_ms: 500      # Collect requests for 500ms before batching
```

Note: Batch completions return results asynchronously (not real-time). Only use for background/reporting tasks, NOT for interactive agent calls.

---

## 4. SOLUTION: AGENT-SIDE CONCURRENCY

### 4.1 Per-Agent Semaphore

Each agent should limit its own concurrent AI calls:

**Python (llm_client.py)**:
```python
import asyncio

# Global semaphore — shared by all agents calling through llm_client
_agent_semaphore = asyncio.Semaphore(2)  # Max 2 concurrent calls per agent

async def llm_complete_async(messages, ...):
    async with _agent_semaphore:
        # ... existing async call logic ...
```

**Node.js (agent model.js)**:
```javascript
const pLimit = require('p-limit');
const limit = pLimit(2); // Max 2 concurrent calls per agent

async function callAI(messages) {
    return limit(async () => {
        // ... existing call logic ...
    });
}
```

### 4.2 Per-Agent Rate Limiting

**Config per agent** (could be in agent .env or ecosystem config):

```bash
# In agent .env file
AGENT_MAX_CONCURRENT_AI_CALLS=2
AGENT_MIN_INTERVAL_BETWEEN_CALLS_MS=500     # 2 requests/sec max
AGENT_DAILY_TOKEN_BUDGET=50000               # 50K tokens/day
```

---

## 5. RECOMMENDED CONCURRENCY MATRIX

| Model | Global Concurrency | Per-Agent Limit | RPM Limit | TPM Limit |
|-------|-------------------|-----------------|-----------|-----------|
| deepseek-chat | 10 | 2 per agent | 500 | 1,000,000 |
| deepseek-reasoner | 5 | 1 per agent | 200 | 300,000 |
| claude-sonnet-4 | 2 | 1 per agent | 100 | 100,000 |
| claude-opus-4 | 1 | 1 global | 50 | 30,000 |

**Rationale**:
- With 8 agents, 2 concurrent each = 16 theoretical max, but global cap at 10 for deepseek-chat prevents overload
- Tighter limits on expensive models protect budget
- Claude Opus is globally throttled to 1 concurrent request (cost guard)

---

## 6. AGENT PRIORITIZATION

### Priority Tiers

| Tier | Agents | Max Concurrent | Budget Priority |
|------|--------|---------------|-----------------|
| CRITICAL | frgcrm-agent-svc, voice-agent-svc | 2 each | Highest |
| HIGH | prediction-radar-agent-svc, surplusai-scraper-agent-svc | 2 each | Normal |
| NORMAL | design-agent-svc, horizon-agent-svc, paperless-agent-svc, insforge-agent-svc | 1 each | Normal |
| LOW | ravyn-agent-svc | 1 each | Low |

### Priority Queue Example

```
Queue (FIFO within priority):
  [HIGH]   Voice agent — outbound call analysis
  [HIGH]   FRGCRM agent — claimant enrichment
  [NORMAL] Design agent — UI consistency check
  [LOW]    Ravyn agent — background analytics
  
  (HIGH requests skip to front)
  [HIGH]   Prediction radar — urgent opportunity alert  <-- inserted at front of HIGH queue
  [HIGH]   Voice agent — outbound call analysis
  [HIGH]   FRGCRM agent — claimant enrichment
  [NORMAL] Design agent — UI consistency check
  [LOW]    Ravyn agent — background analytics
```

---

## 7. IMPLEMENTATION CHECKLIST

- [ ] Set `max_parallel_requests: 10` in LiteLLM config
- [ ] Set per-model concurrency limits
- [ ] Add priority headers to agent requests
- [ ] Implement per-agent semaphore (Python: asyncio.Semaphore, Node: p-limit)
- [ ] Implement request coalescing for identical prompts within 100ms window
- [ ] Configure batch completions for background tasks
- [ ] Add concurrency metrics to LiteLLM (Prometheus)
- [ ] Monitor queue depth and latency after deployment
- [ ] Tune limits based on observed behavior (start conservative, loosen if needed)
