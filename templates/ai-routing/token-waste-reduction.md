# Token Waste Reduction Recommendations
## Wheeler AI Routing -- Phase 7 Optimization

### Audit Date: 2026-05-23
### Current Annual Estimated Waste: ~$800-1,200

---

## 1. SUMMARY OF WASTE SOURCES

| Source | Mechanism | Monthly Waste Est. | Priority |
|--------|-----------|-------------------|----------|
| Disabled Redis caching | Every prompt re-fetched from API | $5-10 | P0 |
| Oversized system prompts | Agents send 300-1000 token prompts for simple tasks | $15-25 | P1 |
| No prompt deduplication | Identical prompts sent multiple times by different agents | $10-20 | P1 |
| max_tokens too high | 2048 default for tasks needing ~100 tokens | $8-15 | P2 |
| No context window awareness | Prompts exceed model limits, causing failures | $5-10 | P2 |
| Unbounded conversation history | Agents accumulate full history without truncation | $20-40 | P2 |
| No token usage budgets per task type | Simple tasks use same budgets as complex ones | $10-15 | P3 |

**Total Estimated Monthly Waste: ~$73-135**
**Total Estimated Annual Waste: ~$876-1,620**

---

## 2. RECOMMENDATIONS

### 2.1 Fix Redis Caching (P0 - Immediate)

**Problem**: Redis auth failure disables all caching. Every identical prompt re-sends to the API.
**Evidence**: Logs show `cached_tokens: 256` but Redis `Authentication required` on every request.

**Action**:
1. Fix Redis password in LiteLLM config to match actual server password
2. Set `cache_ttl: 3600` (1 hour) for prompt caching
3. Enable `cache_prompts: true`
4. Set connection pool size to 20 for concurrent access

**Expected Savings**: ~60-80% reduction in API calls for repeated prompts = $5-10/month

### 2.2 Reduce System Prompt Sizes (P1 - This Week)

**Problem**: Agent system prompts are verbose. Logs show:
- Design audit system prompt: 981 tokens
- Arbitrage analysis system prompt: 320 tokens (even for empty input!)
- Many prompts include detailed JSON schemas inline

**Actions**:
1. Audit all system prompts across the 8 agent-svc services
2. Identify the largest prompts (>500 tokens) and trim to essentials
3. Move JSON schemas to function calling instead of prompt text
4. Use template variables instead of inlining large text blocks
5. Apply prompt compression: remove redundant instructions, combine similar rules

**Before/After Example - Design Agent**:
```
BEFORE (981 tokens):
  "You are an expert design system auditor. Your task is to analyze the provided
   design system components for consistency, accessibility, and best practices.
   For each component, examine: 1) Color usage across light/dark modes,
   2) Typography scale consistency, 3) Spacing system adherence,
   4) Component state definitions (default, hover, focus, active, disabled),
   5) Accessibility contrast ratios per WCAG 2.1 AA standards,
   6) ... [continues for ~900 more tokens]"

AFTER (~350 tokens):
  "Audit design system components for consistency, accessibility (WCAG 2.1 AA),
   and best practices. Check: colors, typography, spacing, states, contrast.
   Output JSON per schema in function call. Be concise."
```

**Expected Savings**: ~25-30% reduction in prompt tokens = $15-25/month

### 2.3 Implement Prompt Deduplication (P1 - This Week)

**Problem**: Different agents send near-identical prompts. For example, all county-processing agents send the same "extract claimant info" prompt with different case data.

**Action**:
1. Add a prompt hash at the LiteLLM proxy level
2. Cache responses by prompt hash (SHA-256 of the messages array)
3. Before forwarding to API, check Redis for identical prompt within TTL
4. If found, return cached response instead of making API call

**Implementation** (in LiteLLM config):
```yaml
cache_params:
  cache_prompts: true
  cache_ttl: 3600
  cache_key_generator: "hash_messages"   # Hash the full messages array
```

**Expected Savings**: ~$10-20/month (depends on prompt overlap across agents)

### 2.4 Dynamic max_tokens per Task Type (P2 - Next Week)

**Problem**: llm_client.py hardcodes `max_tokens=2048` for all calls. Simple tasks (classification, field extraction) need ~100-256 tokens. Setting max_tokens too high wastes token budget and increases latency.

**Actions**:
1. Categorize all LLM call sites by task type:
   - `classification`: 256 tokens
   - `extraction`: 512 tokens
   - `summarization`: 1024 tokens
   - `generation`: 2048 tokens
   - `analysis`: 4096 tokens
2. Update llm_client.py to accept `task_type` parameter
3. Map task_type to max_tokens automatically
4. Add `max_tokens` override for edge cases

**Code Pattern**:
```python
TASK_MAX_TOKENS = {
    "classification": 256,
    "extraction": 512,
    "summarization": 1024,
    "generation": 2048,
    "analysis": 4096,
}

def llm_complete(messages, task_type="generation", max_tokens=None, ...):
    effective_max = max_tokens or TASK_MAX_TOKENS.get(task_type, 2048)
    payload["max_tokens"] = effective_max
    ...
```

**Expected Savings**: ~$8-15/month

### 2.5 Truncate Conversation History (P2 - Next Week)

**Problem**: Agents accumulate full conversation history without truncation. A 10-turn conversation with 300-token responses has 3,000+ tokens of history, but only the last 2-3 turns are relevant for most tasks.

**Actions**:
1. Implement sliding window: keep last N messages (default N=10)
2. Implement token-aware truncation: trim from oldest messages first until under limit
3. Summarize old conversation turns instead of keeping full text
4. Set per-agent context window budgets

**Code Pattern** (in agent model.js / llm_client.py):
```python
def truncate_history(messages, max_tokens=4000):
    """Keep most recent messages, fitting within max_tokens."""
    total = 0
    kept = []
    for msg in reversed(messages):
        tokens = estimate_tokens(msg["content"])
        if total + tokens > max_tokens:
            break
        kept.insert(0, msg)
        total += tokens
    return kept
```

**Expected Savings**: ~$20-40/month

### 2.6 Add Token Budget Per Agent (P3 - This Month)

**Problem**: No per-agent cost awareness. An agent that processes 10 cases/day uses the same model as one processing 1,000, with no cost attribution.

**Actions**:
1. Tag each LLM call with agent_name metadata (already partially done in llm_client.py)
2. Implement per-agent daily token budgets
3. Alert when agent exceeds budget
4. Implement graduated throttling: warn at 80%, throttle at 95%, block at 100%

**Expected Savings**: ~$10-15/month (reduction from cost-aware behavior)

### 2.7 Prompt Template Optimization Checklist

For each agent, audit and optimize:

- [ ] Remove redundant instructions (check if two rules say the same thing)
- [ ] Move output format specs to `response_format` JSON schema (not prompt text)
- [ ] Remove examples that are longer than the instruction they illustrate
- [ ] Use "Be concise" as a standard instruction
- [ ] Set `temperature=0` for deterministic tasks (cheaper than 0.7)
- [ ] Use `deepseek-chat` instead of `deepseek-reasoner` for non-reasoning tasks
- [ ] Only use Claude for PII-sensitive or legally-critical tasks (as per Wheeler policy)
- [ ] Avoid "chain of thought" instructions for simple lookups

---

## 3. MONITORING

After implementing waste reduction, monitor these metrics:

1. **Average prompt tokens per request** -- target: 25% reduction from baseline
2. **Cache hit rate** -- target: >50% after Redis fix
3. **Daily total cost** -- target: visible reduction within 1 week
4. **Agent-specific token consumption** -- identify the top spenders
5. **max_tokens vs actual completion tokens ratio** -- target: <2x (stop wasting budget)

---

## 4. ROI ESTIMATE

| Action | Effort (hours) | Monthly Savings | Annual Savings | Payback |
|--------|---------------|-----------------|----------------|---------|
| Fix Redis Caching | 0.25 | $5-10 | $60-120 | <1 week |
| Reduce system prompts | 2.0 | $15-25 | $180-300 | <2 weeks |
| Prompt deduplication | 1.0 | $10-20 | $120-240 | <1 week |
| Dynamic max_tokens | 2.0 | $8-15 | $96-180 | <1 month |
| Truncate history | 3.0 | $20-40 | $240-480 | <1 month |
| Per-agent budgets | 2.0 | $10-15 | $120-180 | <1 month |
| **TOTAL** | **10.25 hrs** | **$68-125** | **$816-1,500** | **~2 weeks** |
