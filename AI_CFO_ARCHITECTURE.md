# Wheeler AI CFO Architecture
## Institutional-Grade Autonomous Financial Leadership

**Date**: 2026-05-25
**Status**: Deployed — 40-agent fleet operational

---

## Architecture Overview

The Wheeler AI CFO is not a single agent. It is a **layered financial intelligence system** where the `ai-cfo` agent orchestrates 39 specialist agents across 5 capability waves, producing institutional-grade financial oversight.

```
                       HUMAN EXECUTIVE
                             │
                    ┌────────▼────────┐
                    │  CEO COMMAND     │
                    │  CONSOLE (:8180) │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │   AI CFO AGENT   │  ← Strategic Orchestrator
                    │  (ai-cfo.md)    │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼─────┐      ┌──────▼──────┐      ┌─────▼────┐
   │  COST    │      │  REVENUE    │      │ STRATEGY │
   │  LAYER   │      │   LAYER     │      │  LAYER   │
   │ 8 agents │      │  8 agents   │      │ 7 agents │
   └──────────┘      └─────────────┘      └──────────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼─────┐      ┌──────▼──────┐      ┌─────▼────┐
   │TREASURY  │      │ANALYTICS    │      │INTEGRATION│
   │3 agents  │      │7 agents     │      │7 agents   │
   └──────────┘      └─────────────┘      └──────────┘
```

---

## Decision Authority Model

| Level | Name | Scope | Agent Count |
|-------|------|-------|-------------|
| 0 | Read-Only | View financial data, zero modifications | 35 agents |
| 1 | Advisory | Recommend actions, require human approval | 3 agents (AI CFO, Capital Allocation, Wealth Infra) |
| 2 | Supervised | Execute with 5-min human override | 1 agent (Monetization Orchestrator) |
| 3 | Autonomous (minor) | Auto-execute <$10/mo zero-risk optimizations | 1 agent (Autonomous Optimization) |
| 4 | Emergency | Full authority during declared incidents | 0 (reserved for human) |

---

## Information Flow

### Daily Cadence
```
00:00 UTC — Daily cost reports generated (Wave 1 agents)
06:00 UTC — AI spend reports + anomaly detection (Wave 1 agents)
07:00 UTC — CEO Daily Brief auto-generated (Executive Reporting)
08:00 UTC — Revenue health check (Revenue Intelligence)
09:00 UTC — AI CFO synthesizes all reports → Financial Health Score
18:00 UTC — End-of-day reconciliation (Stripe Revenue)
```

### Weekly Cadence
```
Sunday 18:00 UTC — Weekly Executive Summary
Monday 09:00 UTC — Vendor optimization scan
Wednesday — Competitive intelligence update
```

### Monthly Cadence
```
1st business day — Full board package (Financial Reporting)
5th business day — P&L close (Operational Finance)
10th — Budget vs. Actual review (Budget Automation)
15th — Capital allocation review (Capital Allocation)
```

---

## Alert Routing

```
P0 (CRITICAL — immediate war room):
  Revenue system offline >5min
  Cash reserves <3 months
  Unauthorized financial action
  → Routes to: AI CFO + CEO Console + Incident Response

P1 (HIGH — action within 1 hour):
  MRR drop >10% in 24h
  Cost spike >2x daily avg
  Stripe payout failure
  → Routes to: AI CFO + relevant specialist agent

P2 (MEDIUM — action within 24 hours):
  Churn >5% monthly
  Budget variance >20%
  Vendor renewal within 30 days
  → Routes to: AI CFO + specialist agent

P3 (LOW — advisory):
  Optimization opportunity >$50/mo
  New vendor detected
  KPI outside benchmark
  → Routes to: Specialist agent (no escalation)
```

---

## Financial Health Scoring

The AI CFO computes a composite Financial Health Score (0-100):

| Component | Weight | Source |
|-----------|--------|--------|
| Cost Health | 25% | infrastructure-cost, ai-token-cost, vendor-optimization |
| Revenue Health | 25% | revenue-intelligence, stripe-revenue, subscription-analytics |
| Cash Health | 25% | treasury-intelligence, cashflow-forecasting |
| Efficiency Health | 15% | resource-allocation, roi-optimization, profitability-intelligence |
| Risk Health | 10% | financial-governance, ai-spending-governance |

Score published daily to Executive Dashboard (:8180) and CEO Command Console.

---

## Integration Points

- **Executive Dashboard**: :8180/finance — all dashboards
- **Neo4j Knowledge Graph**: :7687 — financial relationships
- **Wheeler Brain Core**: routes "Revenue" and "Costs" queries to AI CFO
- **CEO Command Console**: one-glance financial health status
- **Alert Manager**: :9093 — financial alerts feed into monitoring stack
