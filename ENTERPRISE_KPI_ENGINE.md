# Wheeler Enterprise KPI Engine
## 360-Degree Performance Measurement & Benchmarking

**Date**: 2026-05-25
**Status**: Framework deployed — metrics trackable when revenue flows

---

## KPI Architecture

The Enterprise KPI Engine tracks 30+ key performance indicators across 6 domains, with automated benchmarking and anomaly detection.

```
                    ┌──────────────────┐
                    │  ENTERPRISE KPI   │
                    │   INTELLIGENCE    │
                    │  (orchestrator)   │
                    └────────┬─────────┘
                             │
    ┌────────────┬───────────┼───────────┬──────────┬────────────┐
    │            │           │           │          │            │
┌───▼──┐   ┌────▼────┐ ┌───▼───┐ ┌────▼────┐ ┌───▼───┐ ┌────▼────┐
│REVENUE│   │ GROWTH  │ │UNIT   │ │EFFICIENCY│ │CUSTOMER│ │   AI    │
│ KPIs  │   │  KPIs   │ │ECON   │ │  KPIs    │ │  KPIs  │ │EFFICIENCY│
└───────┘   └─────────┘ └───────┘ └──────────┘ └────────┘ └─────────┘
```

---

## Complete KPI Catalog

### Revenue KPIs

| # | KPI | Formula | SaaS Benchmark | Frequency |
|---|-----|---------|---------------|-----------|
| R1 | MRR | Sum of normalized monthly subscriptions | — | Daily |
| R2 | ARR | MRR * 12 | — | Daily |
| R3 | ARPU | MRR / Active Paying Customers | Varies by segment | Weekly |
| R4 | Avg Contract Value | Total Contract Value / # Contracts | — | Monthly |
| R5 | Revenue Concentration | Largest Customer MRR / Total MRR | <20% | Monthly |

### Growth KPIs

| # | KPI | Formula | Benchmark | Frequency |
|---|-----|---------|-----------|-----------|
| G1 | MoM MRR Growth | (This Mo - Last Mo) / Last Mo | >10% (early), >5% (scale) | Monthly |
| G2 | YoY MRR Growth | (This Yr - Last Yr) / Last Yr | >100% (early), >40% (scale) | Monthly |
| G3 | Net New MRR | New + Expansion - Contraction - Churn | Must be positive | Weekly |
| G4 | SaaS Quick Ratio | (New + Expansion) / (Contraction + Churn) | >4 | Monthly |
| G5 | Expansion MRR Rate | Expansion MRR / Start MRR | >20% of new MRR | Monthly |

### Unit Economics KPIs

| # | KPI | Formula | Benchmark | Frequency |
|---|-----|---------|-----------|-----------|
| U1 | CAC | Total S&M Spend / New Customers | — | Monthly |
| U2 | LTV | ARPU * Gross Margin% * Avg Lifetime (mo) | — | Monthly |
| U3 | LTV:CAC Ratio | LTV / CAC | >3:1 | Monthly |
| U4 | CAC Payback (months) | CAC / (ARPU * Gross Margin%) | <12 months | Monthly |
| U5 | Customer Acquisition Efficiency | New MRR * GM% / S&M Spend | >1.0 | Monthly |

### Retention KPIs

| # | KPI | Formula | Benchmark | Frequency |
|---|-----|---------|-----------|-----------|
| C1 | Logo Churn Rate | Churned Logos / Start Logos | <2% (SMB), <1% (Ent) | Monthly |
| C2 | Gross MRR Churn | Churned MRR / Start MRR | <3% monthly | Monthly |
| C3 | Net MRR Churn | (Churned - Expansion) / Start MRR | Negative (NDR >100%) | Monthly |
| C4 | Net Dollar Retention | (Start + Exp - Contr - Churn) / Start | >100% | Monthly |
| C5 | Gross Dollar Retention | (Start - Churn) / Start | >90% | Monthly |

### Efficiency KPIs

| # | KPI | Formula | Benchmark | Frequency |
|---|-----|---------|-----------|-----------|
| E1 | Gross Margin | (Rev - COGS) / Rev | >70% (SaaS) | Monthly |
| E2 | Operating Margin | Operating Income / Rev | Trending positive | Monthly |
| E3 | Net Margin | Net Income / Rev | Positive by Year 2 | Monthly |
| E4 | Rule of 40 | Rev Growth% + Profit Margin% | >40% | Monthly |
| E5 | Burn Multiple | Net Burn / Net New ARR | <1.5 (good), <1.0 (great) | Monthly |
| E6 | Magic Number | (Q RR - Prior Q RR) * 4 / Prior Q S&M | >1.0 | Quarterly |
| E7 | Revenue Per Employee | Revenue / FTE Count | >$200K | Monthly |

### AI Efficiency KPIs (Wheeler-Specific)

| # | KPI | Formula | Frequency |
|---|-----|---------|-----------|
| A1 | AI Cost per $ Revenue | Total AI Spend / Total Revenue | Weekly |
| A2 | AI Cost per Task | AI Spend / Tasks Completed | Weekly |
| A3 | Task Automation Rate | Automated Tasks / Total Tasks | Weekly |
| A4 | Cost per Agent Invocation | AI Spend / Agent Calls | Daily |
| A5 | Infrastructure Cost per $ Revenue | Infra Cost / Revenue | Weekly |

---

## KPI Health Scoring

Each KPI gets a status based on benchmark comparison:

```
GREEN  — At or above benchmark for stage
YELLOW — Within 20% of benchmark
RED    — More than 20% below benchmark
GREY   — Insufficient data (pre-revenue, new product, etc.)
```

### Composite KPI Health Score

```
Revenue KPIs:     X/100 (weight: 25%)
Growth KPIs:      X/100 (weight: 25%)
Unit Economics:   X/100 (weight: 20%)
Retention KPIs:   X/100 (weight: 15%)
Efficiency KPIs:  X/100 (weight: 10%)
AI Efficiency:    X/100 (weight: 5%)
─────────────────────────────────
TOTAL KPI HEALTH: XX/100
```

---

## KPI Anomaly Detection

| Condition | Alert |
|-----------|-------|
| Any KPI moves >20% in wrong direction in single period | P2 — investigate |
| Two consecutive periods of deterioration | P2 — pattern alert |
| KPI outside industry benchmark range by >50% | P2 — strategic concern |
| Three or more KPIs deteriorating simultaneously | P1 — systemic issue |
| All KPIs green | P3 — keep doing what you're doing |

---

## KPI Correlation Map

Leading indicators that predict lagging indicators:

```
AI Cost per Task ↑  →  Gross Margin ↓ (2-4 week lag)
Support Tickets ↑   →  Churn ↑ (4-8 week lag)
Login Frequency ↓   →  Churn ↑ (2-6 week lag)
Feature Adoption ↑  →  Expansion MRR ↑ (4-12 week lag)
Page Load Time ↑    →  Conversion ↓ (immediate)
```

---

## Integration

- **Tracking**: enterprise-kpi-intelligence agent (primary), saas-kpi, marketplace-kpi
- **Data**: stripe-revenue, subscription-analytics, profitability-intelligence
- **Display**: Executive Dashboard (:8180/finance/kpis), CEO Daily Brief
- **Alerting**: KPI anomalies → AI CFO → Executive action
