# Wheeler AI Cost Governance System
## Token Economics, Spending Guardrails & Autonomous Cost Optimization

**Date**: 2026-05-25
**Status**: Deployed — 4 dedicated agents + supporting infrastructure

---

## Governance Architecture

The AI Cost Governance system ensures every AI token consumed in the Wheeler ecosystem is tracked, justified, and optimized. Four dedicated agents form the governance stack:

```
┌─────────────────────────────────────────────┐
│         AI SPENDING GOVERNANCE              │
│   Budget enforcement, anomaly detection,    │
│   rate limits, kill switch authority        │
│   (ai-spending-governance.md)               │
└────────────────────┬────────────────────────┘
                     │
┌────────────────────▼────────────────────────┐
│         AI TOKEN COST INTEL                 │
│   Per-model, per-key spend tracking,        │
│   token economics, cost-per-task            │
│   (ai-token-cost.md)                        │
└────────────────────┬────────────────────────┘
                     │
┌────────────────────▼────────────────────────┐
│         API COST INTEL                      │
│   Cross-provider price comparison,          │
│   provider health, routing optimization     │
│   (api-cost-intelligence.md)                │
└────────────────────┬────────────────────────┘
                     │
┌────────────────────▼────────────────────────┐
│         AI ROUTING (Existing)               │
│   LiteLLM proxy management, model selection,│
│   cost-performance balance (:4049)          │
│   (ai-routing.md)                           │
└─────────────────────────────────────────────┘
```

---

## Spending Guardrails

### Budget Tiers

| Tier | Daily Limit | Monthly Limit | Applies To |
|------|------------|---------------|------------|
| Development | $5/day | $150/mo | Testing, experimentation |
| Production | $20/day | $600/mo | Revenue-generating services |
| Premium | $50/day | $1,500/mo | High-value agent orchestration |
| Emergency | Uncapped | Uncapped | Declared incidents only |

### Model Tier Policy

| Model | Cost/Task (approx) | Authorized For | Requires Approval |
|-------|-------------------|----------------|-------------------|
| DeepSeek Chat | $0.001-0.01 | All agents, all tasks | No |
| Claude Haiku | $0.005-0.05 | All agents, routine tasks | No |
| Claude Sonnet | $0.02-0.20 | Complex reasoning, code review | No (with budget) |
| GPT-4o | $0.01-0.15 | Alternative when Anthropic down | No (with budget) |
| Claude Opus | $0.10-1.00 | Architecture, strategy, M&A analysis | Yes |
| DeepSeek Reasoner | $0.005-0.05 | Complex chain-of-thought tasks | No |

### Anomaly Detection Rules

1. **Single request >$1** → P2 alert, investigate prompt
2. **Daily spend >2x 7-day average** → P1 alert, rate limit review
3. **Single API key >50% of total** → investigate concentration
4. **New model usage without approval** → P2 alert
5. **Streaming request >5min without completion** → resource waste flag
6. **Prompt caching hit rate <30%** → optimization opportunity
7. **Weekend/overnight usage spike** → investigate source

---

## Kill Switch Protocol

Three-tier escalation for spending anomalies:

```
LEVEL 1 — SOFT ALERT
Trigger: Spend exceeds 90% of daily budget
Action: Notification to AI CFO + AI Spending Governance
Recovery: Automatic reset at midnight UTC

LEVEL 2 — RATE LIMIT
Trigger: Spend exceeds 150% of daily budget OR anomaly score >80
Action: Temporary per-key rate limit applied via LiteLLM
Recovery: Human or Level 3 agent approval required to lift

LEVEL 3 — HARD STOP
Trigger: Spend exceeds 300% of daily budget OR suspected compromise
Action: API keys rotated, all AI traffic halted
Recovery: Human only — requires incident post-mortem
```

---

## Optimization Vectors

### 1. Model Selection
For each task, use the cheapest model that delivers acceptable quality:
- Classification/labeling → DeepSeek Chat ($0.27/1M input tokens)
- Document analysis → Claude Sonnet with prompt caching ($0.30/1M cached input)
- Complex architecture → Claude Opus with cached system prompt ($1.50/1M cached input)

### 2. Prompt Caching
- All system prompts must have static prefixes (enables Anthropic prompt caching)
- Cache hit rate target: >70%
- Estimated savings from caching: 90% on input tokens for cached content

### 3. Context Window Optimization
- No request should exceed 50% of model context window
- Truncate conversation history aggressively
- Use summary compression for long-running agent conversations

### 4. Batching & Scheduling
- Batch non-urgent AI tasks during low-rate periods
- Pre-compute common analyses (daily reports, weekly summaries)

---

## Cost Monitoring Data Flow

```
LiteLLM :4049
├── /spend/logs → ai-token-cost (per-request economics)
├── /spend/keys → ai-token-cost (per-application attribution)
├── /spend/tags → ai-token-cost (per-category tracking)
├── /global/activity → ai-spending-governance (anomaly detection)
└── /user/daily/activity → ai-spending-governance (budget enforcement)

ai-token-cost → ai-spending-governance (cost data for budget comparison)
ai-spending-governance → ai-cfo (alerts + budget status)
api-cost-intelligence → ai-routing (price comparison for routing decisions)
```
