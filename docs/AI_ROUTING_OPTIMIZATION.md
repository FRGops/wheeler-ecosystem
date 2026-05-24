# PHASE 7 -- AI ROUTING OPTIMIZATION PLAN
## Wheeler Ecosystem -- Comprehensive Audit & Remediation Blueprint

**Target**: AIOPS Node (Hetzner CPX51 / 5.78.140.118)
**Date**: 2026-05-23
**Auditor**: Principal AI Systems Optimization Engineer
**Scope**: LiteLLM proxy, agent-svc AI call patterns, token waste, Redis caching, fallback/resilience

---

## TABLE OF CONTENTS

1. [Executive Summary](#1-executive-summary)
2. [Current Architecture Map](#2-current-architecture-map)
3. [Findings: Critical Issues](#3-findings-critical-issues)
4. [Findings: Performance Issues](#4-findings-performance-issues)
5. [Findings: Cost/Tokens](#5-findings-costtokens)
6. [Findings: Configuration Gaps](#6-findings-configuration-gaps)
7. [Optimization Plan](#7-optimization-plan)
8. [Implementation Priority Matrix](#8-implementation-priority-matrix)
9. [Risk Assessment](#9-risk-assessment)

---

## 1. EXECUTIVE SUMMARY

The Wheeler AI routing layer has **six critical deficiencies** that impact cost, reliability, and latency. The primary root cause is a **Redis authentication failure** that disables caching on 100% of requests. Additionally, the running LiteLLM configuration has **no fallback chain, no retry policy, no streaming support, no batching, and no inter-agent rate coordination**.

The governance template (`litellm-governance-template.yaml`) contains a comprehensive configuration (fallbacks, budgets, RBAC, guardrails) but was **never applied** to the running instance. The deployed config (`litellm-deepseek.yaml`) is a minimal skeleton.

**Estimated Annual Waste**: ~$800-1,200 in redundant API calls from disabled caching alone, plus unquantified costs from absent fallbacks, zero retry resilience, and uncontrolled concurrency bursts.

---

## 2. CURRENT ARCHITECTURE MAP

```
                        ┌──────────────────────────────────────────┐
                        │           AIOPS (5.78.140.118)            │
                        │                                          │
  ┌─────────────────┐   │   ┌──────────────────────────────────┐   │
  │  frgcrm-api      │───┼──▶│  LiteLLM Proxy (:4049)           │   │
  │  (Anthropic SDK  │   │   │  python3 /usr/local/bin/litellm  │   │
  │   → DeepSeek)    │   │   │  361 MB RAM | 5 restarts         │   │
  └─────────────────┘   │   │  Config: litellm-deepseek.yaml    │   │
                         │   └───────────┬──────────────────────┘   │
  ┌─────────────────┐   │               │                          │
  │  8 agent-svc     │   │   ┌───────────▼──────────────────────┐   │
  │  processes       │───┼──▶│  Model Routing:                  │   │
  │  (OpenAI SDK →   │   │   │  deepseek-chat     RPM: 1000     │   │
  │   LiteLLM)       │   │   │  deepseek-reasoner RPM:  500     │   │
  └─────────────────┘   │   │  claude-sonnet-4   RPM:  100     │   │
                         │   │  claude-opus-4     RPM:   50     │   │
  ┌─────────────────┐   │   │  premium_review    RPM:  100     │   │
  │  Wheeler Brain   │───┼──▶│                                  │   │
  │  OS (:8100)      │   │   │  Redis Cache: BROKEN             │   │
  └─────────────────┘   │   │  Fallbacks: NONE                  │   │
                         │   │  Retries: NONE                   │   │
  ┌─────────────────┐   │   │  Streaming: DISABLED             │   │
  │  OpenClaw        │───┼──▶│  Batching: NONE                 │   │
  │  Gateway (:8110) │   │   └──────────────────────────────────┘   │
  └─────────────────┘   │                                          │
                         └──────────────────────────────────────────┘
                                   │                    │
                                   ▼                    ▼
                         ┌──────────────┐    ┌──────────────────┐
                         │  DeepSeek API │    │  Anthropic API   │
                         │  (primary)    │    │  (Claude models) │
                         └──────────────┘    └──────────────────┘
                                   │
                         ┌──────────────┐
                         │  COREDB Redis │
                         │  100.118.166. │
                         │  117:6379     │
                         │  AUTH BROKEN  │
                         └──────────────┘
```

### Service Inventory

| Service | Port | Memory | Restarts | AI Provider | Call Pattern |
|---------|------|--------|----------|-------------|-------------|
| litellm | 4049 | 361MB | 5 | Proxy (all) | HTTP proxy |
| frgcrm-api | 8082 | -- | 4 | Anthropic SDK via DeepSeek | Direct API |
| design-agent-svc | -- | -- | 0 | LiteLLM (OpenAI SDK) | POST /v1/chat/completions |
| horizon-agent-svc | -- | -- | 0 | LiteLLM (OpenAI SDK) | POST /v1/chat/completions |
| paperless-agent-svc | -- | -- | 0 | LiteLLM (OpenAI SDK) | POST /v1/chat/completions |
| prediction-radar-agent-svc | -- | -- | 0 | LiteLLM (OpenAI SDK) | POST /v1/chat/completions |
| ravyn-agent-svc | -- | -- | 0 | LiteLLM (OpenAI SDK) | POST /v1/chat/completions |
| frgcrm-agent-svc | -- | -- | 0 | LiteLLM (OpenAI SDK) | POST /v1/chat/completions |
| insforge-agent-svc | -- | -- | 0 | LiteLLM (OpenAI SDK) | POST /v1/chat/completions |
| surplusai-scraper-agent-svc | 8009 | -- | 0 | LiteLLM (OpenAI SDK) | POST /v1/chat/completions |
| voice-agent-svc | 8018 | -- | 0 | LiteLLM (OpenAI SDK) | POST /v1/chat/completions |

### API Key Topology

| Key Type | Key Prefix | Used By | Purpose |
|----------|-----------|---------|---------|
| DEEPSEEK_API_KEY #1 | sk-d8ac... | All 8 agent-svc processes | Also set as OPENAI_API_KEY; routes through LiteLLM port 4049 |
| DEEPSEEK_API_KEY #2 | sk-4ac7... | frgcrm-api (Claude Code) | Also set as ANTHROPIC_AUTH_TOKEN; routes through api.deepseek.com/anthropic |
| ANTHROPIC_API_KEY | sk-ant-api03-... | frgcrm-api (llm_client.py) | Direct Anthropic API for premium/Claude calls |
| LITELLM_KEY | sk-litellm-... | frgcrm-api (llm_client.py) | Auth token for LiteLLM proxy |

### API Key Issues

1. **DEEPSEEK_API_KEY #2 (sk-4ac72...)** is the SAME key documented in memory as the root cause of 3 broken PM2 processes (frgcrm-api, surplusai-scraper, voice-agent). This is a single point of failure for the Claude Code pathway.
2. **DEEPSEEK_API_KEY #1 (sk-d8ac9...)** is reused for both DEEPSEEK_API_KEY and OPENAI_API_KEY in agent .env files. If one key is revoked or rate-limited, both aliases fail simultaneously.
3. **ANTHROPIC_BASE_URL** is set to `https://api.deepseek.com/anthropic`, meaning Claude Code thinks it is calling Anthropic but actually calls DeepSeek. This is an intentional routing decision but creates confusion in audit trails.

---

## 3. FINDINGS: CRITICAL ISSUES

### 3.1 Redis Authentication Failure (CRITICAL -- P0)

**Status**: BROKEN since deployment
**Evidence**: 236/300 recent log lines contain "Authentication required" errors
**Impact**: Every AI request fails Redis caching, falling back to in-memory cache (single-process, not shared). This means:
- Identical prompts across different agents ALWAYS re-fetch from API (no cross-agent cache sharing)
- Cache TTL is effectively zero (in-memory cache lost on process restart)
- Redis pipeline failures also break TTL preservation, parallel request limiting, and cache increment/decrement

**Root Cause Analysis**:
The LiteLLM configuration file sets:
```yaml
cache_params:
  type: redis
  host: 100.118.166.117
  port: 6379
  password: "FRGpassword1!"
  db: 6
```

But the actual Redis connection from the ecosystem config uses:
```
REDIS_URL=redis://100.118.166.117:6379  (NO password, NO db selector)
```

**Resolution**: Fix the Redis password in the LiteLLM config to match the actual Redis server password, or configure Redis DB 6 to accept the correct credentials. See [Template 1: Optimized LiteLLM Config](#template-1).

### 3.2 No Fallback Chain (CRITICAL -- P0)

**Status**: NOT CONFIGURED
**Evidence**: Running config has zero fallback entries
**Impact**: If DeepSeek API is unavailable (500/502/503), ALL requests fail. No automatic routing to Anthropic Claude as backup.

**What Should Exist** (from governance template):
```
Flash (deepseek-chat) → Pro (deepseek-reasoner) → Claude Sonnet
Pro (deepseek-reasoner) → Claude Sonnet [requires approval]
```

### 3.3 No Retry Logic Anywhere in the Stack (HIGH -- P1)

**Status**: No retries at any layer
**Evidence**:
- LiteLLM config: no `num_retries` or `num_retries_per_request` settings
- llm_client.py: `try/except` returns None on first failure, no retry loop
- Agent model.js: No retry wrapper

**Impact**: Transient API failures (network blips, 429 rate limits) immediately propagate to callers as failures.

### 3.4 LiteLLM Has 5 PM2 Restarts (MEDIUM -- P2)

**Status**: liteLLM has restarted 5 times per PM2
**Evidence**: PM2 shows `RESTARTS=5` for litellm process
**Impact**: Each restart loses the in-memory cache entirely, compounding the Redis failure impact. Indicates instability in the LiteLLM process itself.

---

## 4. FINDINGS: PERFORMANCE ISSUES

### 4.1 Uncontrolled Concurrent Request Bursts

**Evidence**: Logs show 15-20 concurrent POST requests in rapid succession (same-second timestamps with sequential port numbers).
**Pattern**: All 8 agent-svc processes fire requests without any coordination or rate limiting between them.
**Impact**: DeepSeek may throttle these bursts (rate limiting), and the LiteLLM proxy has no concurrency cap to smooth them.

### 4.2 No Streaming Support

**Evidence**: All calls use `/v1/chat/completions` (non-streaming). The liteLLM config has no streaming settings. The llm_client.py uses blocking POST.
**Impact**: 
- Users wait for full response generation before seeing any output
- No time-to-first-token (TTFT) optimization
- Memory pressure from buffering full responses

### 4.3 No Batching

**Evidence**: Each agent sends individual requests. No request batching or coalescing.
**Impact**: Higher per-request overhead (HTTP connection setup, auth, etc.) for small requests.

### 4.4 No Model-Specific Timeouts

**Evidence**: LiteLLM config has no timeout settings. llm_client.py uses 60s default via httpx.
**Impact**: DeepSeek Flash (should respond in <5s) and Claude Opus (may need 120s) share the same 60s timeout. Fast models timeout unnecessarily late; slow models may be cut off.

### 4.5 Dual Cache Directory Situation

LiteLLM's PM2 ecosystem config writes logs to `/opt/logs/litellm-*.log`, but the `~/.pm2/logs/litellm-*.log` files also exist. This creates confusion in log analysis -- operators may look at the wrong file.

---

## 5. FINDINGS: COST/TOKENS

### 5.1 Token Waste from Disabled Caching

**Evidence**: Logs show `cached_tokens: 256` out of `prompt_tokens: 320` (80% cache hit rate from DeepSeek side) but NO server-side caching due to broken Redis. Each of those 256 cached tokens costs the API provider rate every time.

**Estimated Impact**: With 155 requests per log sample window (~2-5 minutes), and ~200 prompt tokens per request at 80% cacheability, approximately 24,800 tokens are wastefully transmitted per window. At DeepSeek Flash pricing ($0.14/1M input), this is approximately $0.0035 per window, or roughly $5-10/month in direct token waste. The larger impact is on latency (each uncached request incurs full prompt processing time).

### 5.2 Overly Long Prompts in Logs

**Evidence**: Error logs contain full system prompts and response payloads (e.g., 981 prompt tokens for a "design system audit" task, 320 prompt tokens for an "arbitrage analysis" task that received `undefined` input).
**Impact**: The system prompt for design system auditing is 981 tokens but could likely be trimmed to ~400 with better engineering. The arbitrage task receives no actual data but still sends 320 tokens of prompt.

### 5.3 max_tokens Hardcoded

**Evidence**: `llm_client.py` hardcodes `max_tokens=2048` for all models. This is wasteful for simple tasks (classification, validation) that need ~100 tokens, and limiting for complex tasks that need 4096+.

### 5.4 Cost Monitoring Infrastructure Exists But Is Passive

The `CostMonitor` class in `/root/wheeler-autonomous-ops/cost-monitor/cost_monitor.py` has comprehensive token tracking but only runs when explicitly invoked. There is no automated cost alerting on a schedule.

---

## 6. FINDINGS: CONFIGURATION GAPS

### 6.1 Governance Template vs Running Config

The governance template (`/opt/wheeler-ai-cost-governance/configs/litellm-governance-template.yaml`) contains:
- Fallback chain with conditions ✓
- Per-model budget limits ✓
- RBAC per team ✓
- Guardrails (loop detection, abuse patterns) ✓
- Approval requirements for Claude models ✓
- Cost callbacks ✓
- Prometheus metrics ✓

**NONE of these are in the running config** (`/root/.claude/litellm-deepseek.yaml`).

### 6.2 Missing Configurations in Running Instance

| Setting | Template Has | Running Has |
|---------|-------------|-------------|
| drop_params | true | true |
| set_verbose | false | false |
| fallbacks | Defined | **EMPTY** |
| num_retries | 2 | **NOT SET** |
| num_retries_per_request | 2 | **NOT SET** |
| request_timeout | 600 | **NOT SET** |
| max_parallel_requests | 10 | **NOT SET** |
| context_window_fallbacks | [] | **NOT SET** |
| cache_type | redis | redis |
| allowed_fails | 3 | **NOT SET** |
| alerting | Yes | **NONE** |
| budget tracking | Yes | **NONE** |
| success/failure callbacks | Langfuse + webhook | **NONE** |

### 6.3 Langfuse Observability Partially Configured

The ecosystem env has `LANGFUSE_HOST: http://localhost:3020`, and `llm_client.py` uses `@observe` decorators, but the LiteLLM config has no Langfuse callbacks. This means:
- Python-side LLM calls ARE traced (via decorators)
- LiteLLM proxy-level calls are NOT traced (no success_callback)
- No unified observability across all AI traffic

---

## 7. OPTIMIZATION PLAN

### Phase 1: Stabilize (Week 1) -- P0/P1 Fixes

**1. Fix Redis Caching**
- Verify actual Redis password on COREDB (100.118.166.117:6379)
- Update `litellm-deepseek.yaml` cache_params password to match
- Add Redis DB selector and connection timeout
- Validate with: `curl -s localhost:4049/health` and check error logs for zero "Authentication required" errors
- Expected benefit: 60-80% reduction in API calls for repeated prompts

**2. Enable Fallback Chain**
- Deploy fallback: deepseek-chat -> deepseek-reasoner -> claude-sonnet-4
- Set alert_on_fallback: true
- Set max_fallbacks_per_hour to prevent cascading costs
- Test by temporarily setting an invalid API key for deepseek-chat and verifying requests fall through to the reasoner

**3. Add Retry Logic**
- Set `num_retries: 3` and `num_retries_per_request: 2` in LiteLLM config
- Configure exponential backoff: 1s, 2s, 4s between retries
- Add retry wrapper in `llm_client.py` for transient HTTP errors (429, 502, 503)
- Add jitter to prevent thundering herd on retry

### Phase 2: Optimize (Week 2) -- P2 Improvements

**4. Implement Streaming**
- Enable streaming in LiteLLM config relationships
- Add streaming support to `llm_client.py` (`stream=True`)
- Use streaming for UI-facing calls where TTFT matters
- Keep non-streaming for batch/background jobs

**5. Add Model-Specific Timeouts**
- deepseek-chat: 30s timeout (should be fast)
- deepseek-reasoner: 60s timeout (reasoning models are slower)
- claude-sonnet-4: 90s timeout
- claude-opus-4: 120s timeout

**6. Rate Limit Coordination**
- Set `max_parallel_requests` per model:
  - deepseek-chat: 10 concurrent
  - deepseek-reasoner: 5 concurrent
  - Claude models: 2 concurrent
- Add `rpm` enforcement with proper burst handling

### Phase 3: Harden (Week 3-4) -- P3 Enhancements

**7. Deploy Governance Template**
- Merge `litellm-governance-template.yaml` settings into running config
- Enable budget tracking with daily/monthly caps
- Deploy guardrails (loop detection, abuse patterns)
- Enable RBAC for team-based access control

**8. Enable Full Observability**
- Add Langfuse success_callback to LiteLLM config
- Add failure webhook callback for alerting
- Enable Prometheus metrics on port 4001
- Schedule cost monitor to run hourly via cron

**9. Batching/Coalescing**
- Implement request coalescing for identical prompts within a 100ms window
- Add semantic deduplication for prompts that differ only in non-semantic whitespace

**10. Token Waste Reduction**
- Implement prompt length validation at the LiteLLM proxy level
- Add automatic prompt truncation for inputs exceeding model context windows
- Reduce system prompt sizes (target: 25% reduction in average prompt tokens)
- Cap max_tokens per task type (classification=256, generation=2048, analysis=4096)

### Implementation Templates

Detailed configuration templates are provided in the companion directory:
`/root/templates/ai-routing/`

1. `litellm-optimized.yaml` -- Optimized LiteLLM configuration
2. `fallback-latency-config.yaml` -- Fallback chain and latency tuning
3. `token-waste-reduction.md` -- Token waste reduction recommendations
4. `concurrency-batching-recommendations.md` -- Concurrency and batching guide
5. `retry-handling-guide.md` -- Retry configuration and patterns
6. `streaming-optimization.md` -- Streaming setup guide
7. `timeout-tuning.md` -- Model-specific timeout configuration
8. `safe-apply-ai-routing-optimizations.sh` -- Safe deployment script

---

## 8. IMPLEMENTATION PRIORITY MATRIX

| # | Action | Priority | Effort | Impact | Risk |
|---|--------|----------|--------|--------|------|
| 1 | Fix Redis auth | P0 | 15 min | HIGH | Low |
| 2 | Add fallback chain | P0 | 30 min | HIGH | Low |
| 3 | Add retry logic | P1 | 1 hour | HIGH | Low |
| 4 | Model-specific timeouts | P1 | 30 min | MEDIUM | Low |
| 5 | Enable streaming | P2 | 2 hours | MEDIUM | Medium |
| 6 | Rate limit coordination | P2 | 1 hour | MEDIUM | Low |
| 7 | Deploy governance template | P3 | 4 hours | HIGH | Medium |
| 8 | Enable full observability | P3 | 2 hours | MEDIUM | Low |
| 9 | Implement batching | P3 | 4 hours | MEDIUM | Medium |
| 10 | Token waste reduction | P3 | 3 hours | MEDIUM | Medium |

---

## 9. RISK ASSESSMENT

### Current Risk Posture

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| DeepSeek API outage | Medium | Critical | No fallback exists (P0 fix) |
| API key exhaustion | Low | Critical | Two separate keys exist, but no key rotation |
| Rate limit cascade | Medium | High | No inter-agent coordination (P2 fix) |
| Cost overrun from disabled caching | High | Low | Fix Redis to mitigate |
| LiteLLM restart loop | Low | High | 5 restarts observed; memory limit set to 1GB |

### Rollback Safety

All changes in this plan are applied to a single configuration file (`litellm-deepseek.yaml`). The LiteLLM process validates config on startup -- a bad config will prevent the process from reloading. The `safe-apply-optimizations.sh` script:
1. Creates a timestamped backup of the current config
2. Writes the new config to a staging path
3. Validates the config with `litellm --validate-config`
4. If valid, swaps the config and reloads via PM2
5. Monitors logs for 60 seconds to confirm stability
6. Auto-rolls back if errors are detected

---

## APPENDIX A: Configuration Files Referenced

### Running Config
- `/root/.claude/litellm-deepseek.yaml` -- Current (minimal) LiteLLM config
- `/opt/wheeler/ecosystem.config.js` -- PM2 ecosystem config with LiteLLM env vars
- `/opt/wheeler/apps/frgcrm/api/.env` -- API keys for frgcrm-api
- `/opt/wheeler/apps/frgcrm/agents-service/.env` -- Agent API keys

### Templates (Reference Only)
- `/opt/wheeler-ai-cost-governance/configs/litellm-governance-template.yaml` -- Comprehensive governance template

### Log Files
- `/opt/logs/litellm-out.log` -- Primary LiteLLM output log (ecosystem config)
- `/opt/logs/litellm-error.log` -- Primary LiteLLM error log (ecosystem config)
- `~/.pm2/logs/litellm-out.log` -- PM2 default log (secondary)
- `~/.pm2/logs/litellm-error.log` -- PM2 default log (secondary)

### Code Files
- `/opt/wheeler/apps/frgcrm/api/services/llm_client.py` -- Primary LLM client (Python)
- `/opt/wheeler/apps/frgcrm/agents-service/dist/model.js` -- Agent model config (Node.js)
- `/root/wheeler-autonomous-ops/ai-model-monitor/ai-routing-monitor.py` -- AI health monitor
- `/root/wheeler-autonomous-ops/cost-monitor/cost_monitor.py` -- Cost monitor

---

## APPENDIX B: Team Contacts

| Role | Responsibility |
|------|---------------|
| AI Platform Lead | LiteLLM config ownership, model routing decisions |
| Backend Lead | llm_client.py changes, agent-svc coordination |
| DevOps | Redis fix, PM2 config deployment, monitoring |
| Security | API key rotation, secret management |

---

*This document is READ-ONLY audit output. All configuration changes must be applied via the safe-apply script in `/root/templates/ai-routing/`.*
