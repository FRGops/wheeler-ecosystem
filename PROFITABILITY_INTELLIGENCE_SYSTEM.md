# Wheeler Profitability Intelligence System
## Per-Product P&L, Unit Economics & Margin Optimization

**Date**: 2026-05-25
**Status**: Framework deployed — activates when revenue flows

---

## System Overview

The Profitability Intelligence System answers the fundamental question: **"Are we making money?"** — per product, per customer, per transaction. It transforms raw revenue and cost data into actionable profitability insights.

---

## Profitability Architecture

```
                    ┌──────────────────┐
                    │   PROFITABILITY   │
                    │   INTELLIGENCE    │
                    │  (orchestrator)   │
                    └────────┬─────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼─────┐      ┌──────▼──────┐      ┌─────▼────┐
   │ Revenue  │      │    Cost     │      │  Unit    │
   │ Sources  │      │ Allocation  │      │Economics │
   └──────────┘      └─────────────┘      └──────────┘
        │                    │                    │
   ┌────▼─────┐      ┌──────▼──────┐      ┌─────▼────┐
   │ Stripe   │      │Resource Alloc│      │ SaaS KPI │
   │ Revenue  │      │infra-cost    │      │ Agent    │
   │ Agent    │      │ai-token-cost │      │          │
   └──────────┘      └─────────────┘      └──────────┘
```

---

## Per-Product Profitability Model

For each Wheeler product, compute full P&L:

```
Product: [Name]
───────────────────────────────────────
Revenue
  Subscription Revenue:        $X
  Usage-Based Revenue:         $X
  Marketplace Revenue:         $X
Total Revenue:                 $X

Direct Costs
  AI Tokens (attributed):     ($X)
  Payment Processing (2.9%):  ($X)
  Hosting (proportional):     ($X)
Total Direct Costs:           ($X)

Gross Profit:                  $X
Gross Margin:                  X%

Allocated Shared Costs
  Shared Infrastructure:      ($X)
  Shared AI/ML:               ($X)
  Shared SaaS Tools:          ($X)
Total Allocated:              ($X)

Net Profit:                    $X
Net Margin:                    X%
```

## Cost Allocation Methodology

Shared costs allocated proportionally to each product:

| Cost Pool | Allocation Basis | Example |
|-----------|-----------------|---------|
| Hetzner Server | CPU-minutes per product | SurplusAI uses 40% CPU → 40% of server cost |
| AI Tokens | Direct attribution via API keys | Each product has its own LiteLLM key |
| SaaS Tools | Active users per product | 100 users total, Product A has 30 → 30% |
| Domains | Equal split across products | 8 products, 1 domain → 1/8 each |

---

## Unit Economics Dashboard

| Metric | Formula | Target | Frequency |
|--------|---------|--------|-----------|
| ARPU | MRR / Active Customers | — | Weekly |
| CAC | S&M Spend / New Customers | — | Monthly |
| LTV | ARPU * GM% * Avg Lifetime (mo) | — | Monthly |
| LTV:CAC | LTV / CAC | >3:1 | Monthly |
| CAC Payback | CAC / (ARPU * GM%) | <12 months | Monthly |
| Gross Margin | (Rev - COGS) / Rev | >70% | Monthly |
| Contribution Margin | (Rev - Variable Costs) / Rev | >50% | Monthly |
| Net Margin | (Rev - All Costs) / Rev | Positive by Year 2 | Monthly |

---

## Customer Profitability Segmentation

```
WHALES (Top 10%)
├── Characteristics: Highest MRR, low support, high NDR
├── Strategy: White-glove retention, expansion focus
├── Risk: Concentration (no single whale >20% of revenue)

CORE (Middle 60%)
├── Characteristics: Steady MRR, average support
├── Strategy: Self-serve optimization, feature education
├── Goal: Move them toward whale status

LOW-VALUE (Bottom 20%)
├── Characteristics: Low MRR, high support burden
├── Strategy: Automate service, reduce cost-to-serve
├── Decision: Raise prices or accept low margin

LOSS-MAKING (Bottom 10%)
├── Characteristics: Cost-to-serve exceeds revenue
├── Strategy: Fix pricing, automate, or offboard
├── Timeline: 90 days to fix or fire
```

---

## Margin Improvement Levers

Ranked by typical impact:

1. **Price optimization** — 1% price increase → ~11% profit increase (for 10% margin business)
2. **AI cost reduction** — Switch to cheaper models for routine tasks (30-60% savings)
3. **Churn reduction** — 1% churn reduction → significant LTV improvement
4. **Infrastructure right-sizing** — Match resources to actual usage (20-40% savings)
5. **Vendor consolidation** — Reduce SaaS tool overlap ($20-50/mo savings)
6. **Payment processing optimization** — ACH vs. cards, volume discounts (0.5-1% savings)

---

## Integration

- **Data Sources**: stripe-revenue, ai-token-cost, infrastructure-cost, resource-allocation
- **Analysis**: profitability-intelligence, operational-finance, saas-kpi
- **Reporting**: Monthly P&L → Board Package (via financial-reporting agent)
- **Action**: Capital allocation decisions informed by per-product profitability
