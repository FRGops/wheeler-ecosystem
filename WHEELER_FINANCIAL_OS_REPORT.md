# Wheeler Ecosystem Financial Operating System
## Master Architecture & Deployment Blueprint

**Date**: 2026-05-25
**Status**: Phase 0 Complete (Recon) → Phase 1 Active (Agent Deployment)
**Revenue Readiness**: 2.9/10 (pre-revenue, Stripe test mode)
**Infrastructure Burn**: ~$200-300/mo (single Hetzner CPX51)

---

## Executive Summary

The Wheeler ecosystem has hardened infrastructure (41 Docker containers, 23 PM2 processes, 3-node Tailscale mesh), an operational AI agent fleet (50+ agents), and detailed monetization architecture (8 revenue paths designed). However, production financial systems are at zero: no revenue collection, no automated financial tracking, no P&L, no forecasting.

This Financial OS blueprint deploys 40 specialized financial agents across 5 capability waves, matching the ecosystem's actual maturity stage. Wave 1 agents operate on real data TODAY (infrastructure costs, AI token spend, resource utilization). Waves 2-5 activate progressively as revenue systems come online.

### Guiding Principles

1. **No fake numbers** — every agent operates on verifiable data sources
2. **Stage-appropriate** — agents match current reality, not aspirational targets
3. **Zero-trust financial governance** — separation of monitoring, approval, and execution
4. **ROI-first** — every agent must produce measurable value (cost savings, risk reduction, or revenue enablement)
5. **Infrastructure-preserving** — financial systems must not degrade operational stability

---

## Current State Assessment

### What Exists (Operational)

| System | State | Data Available |
|--------|-------|---------------|
| Docker fleet | 41 containers, healthy | `docker stats`, `docker ps` |
| PM2 processes | 23 processes, online | `pm2 jlist`, memory/cpu trends |
| LiteLLM proxy | :4049, operational | Spend logs per model/key |
| Tailscale mesh | 3 nodes, healthy | Bandwidth stats |
| Nginx gateway | 1 site enabled | Access logs |
| Postgres | :5433, :5434, :5435 | Query stats, storage |
| Redis | 2 instances | Memory usage |
| Prometheus | :9090 | Time-series metrics |
| Loki | :3100 | Log aggregation |

### What Exists (Financial Agents)

| Agent | Capability | Authority |
|-------|-----------|----------|
| `cost-intelligence` | Tracks infra/AI/SaaS costs, ~$200-300/mo | Advisory |
| `revenue-intelligence` | Monitors 10 planned products, MRR/ARR tracking | Read-only |
| `monetization-orchestrator` | Coordinates revenue lifecycle, tenant provisioning | Level 2 (Supervised) |
| `ai-routing` | AI spend per model, cost-efficient routing | Advisory |
| `autonomous-optimization` | Cost savings identification with ROI estimates | Advisory |

### What Is Broken (Revenue-Critical)

| Issue | Severity | Revenue Impact |
|-------|----------|---------------|
| Stripe test mode | P0 | $0 can be collected |
| COREDB refusing connections | P0 | Blocks all FRG revenue |
| PipelineDAG 6 stages broken | P0 | 6,603 cases stuck |
| Revenue PM2 processes errored | P1 | No metrics collection |
| No dunning engine | P1 | No churn prevention |
| Grafana no revenue datasources | P2 | No revenue dashboards |

### What Is Missing (Financial Systems)

- P&L / profitability analysis by product
- Budget vs. actual variance tracking
- Unit economics (CAC, LTV, payback period)
- Cash flow statements / working capital monitoring
- Revenue/cost forecasting (beyond simple trendlines)
- Pricing optimization / elasticity modeling
- Invoice/AR/AP management
- Tax calculation (sales tax, VAT, income)
- Multi-period financial trend analysis
- Financial compliance (SOC2, GDPR for financial data)

---

## Agent Fleet Architecture

### Wave 1: Operational Cost Intelligence (DEPLOY NOW — Real Data Available)

These agents operate on live infrastructure data TODAY. No revenue required.

| # | Agent | Data Source | Value |
|---|-------|------------|-------|
| 1 | **Infrastructure Cost Agent** | Docker stats, PM2 metrics, `free`/`df` | Per-service cost allocation |
| 2 | **AI Token Cost Agent** | LiteLLM spend logs :4049 | Per-model, per-key token economics |
| 3 | **API Cost Intelligence Agent** | LiteLLM + external API billing APIs | Cross-provider cost comparison |
| 4 | **AI Spending Governance Agent** | LiteLLM + rate limits | Budget enforcement, anomaly detection |
| 5 | **Infrastructure Optimization Agent** | Docker images, disk usage, memory trends | Right-sizing recommendations |
| 6 | **Vendor Optimization Agent** | SaaS subscriptions, domain registrations | Vendor consolidation, renewal tracking |
| 7 | **Resource Allocation Agent** | System resources, container limits | Cost-per-workload attribution |
| 8 | **Scaling Cost Forecast Agent** | Historical resource trends, growth patterns | Capacity planning with cost estimates |

### Wave 2: Financial Intelligence Core (DEPLOY — Ready for Revenue)

These agents activate when Stripe goes live. Architecture and monitoring paths built now.

| # | Agent | Primary Function | Activation Trigger |
|---|-------|-----------------|-------------------|
| 9 | **AI CFO Agent** | Strategic financial oversight, cross-agent coordination | Stripe live + 1 transaction |
| 10 | **Treasury Intelligence Agent** | Cash position, working capital, payout scheduling | First revenue received |
| 11 | **Capital Allocation Agent** | Investment prioritization, ROI scoring | Multiple revenue streams active |
| 12 | **Revenue Forecasting Agent** | MRR/ARR projections, seasonality modeling | 3+ months revenue history |
| 13 | **Cashflow Forecasting Agent** | 13-week cash flow, burn rate, runway | Revenue + cost data available |
| 14 | **Operational Finance Agent** | P&L statements, margin analysis, cost accounting | Revenue + allocated costs |
| 15 | **Profitability Intelligence Agent** | Per-product margin, unit economics, contribution margin | Per-product revenue + cost data |
| 16 | **Budget Automation Agent** | Budget vs. actual, variance alerts, forecast adjustment | Budget targets defined |
| 17 | **Enterprise KPI Intelligence Agent** | MRR, ARR, CAC, LTV, churn, expansion revenue | Revenue flowing |
| 18 | **Financial Governance Agent** | Policy enforcement, audit trails, compliance monitoring | All financial systems live |

### Wave 3: Revenue Operations (DEPLOY — When Stripe Is Live)

| # | Agent | Primary Function |
|---|-------|-----------------|
| 19 | **Stripe Revenue Agent** | Subscription monitoring, payment reconciliation, webhook health |
| 20 | **Billing Intelligence Agent** | Invoice generation, payment tracking, dunning management |
| 21 | **Subscription Analytics Agent** | Churn analysis, expansion MRR, cohort retention |
| 22 | **SaaS KPI Agent** | SaaS-specific metrics: NDR, LTV:CAC, magic number |
| 23 | **Marketplace KPI Agent** | Attorney marketplace metrics, GMV, take rate, liquidity |
| 24 | **Financial Reporting Agent** | P&L, balance sheet, cash flow statement generation |
| 25 | **Tax Strategy Intelligence Agent** | Sales tax nexus, VAT obligations, estimated tax planning |

### Wave 4: Strategic Finance (DEPLOY — Multi-Product Scale)

| # | Agent | Primary Function |
|---|-------|-----------------|
| 26 | **Acquisition Intelligence Agent** | Target scoring, synergy analysis, valuation modeling |
| 27 | **Investment Opportunity Agent** | Market scanning, opportunity ranking, risk assessment |
| 28 | **Real Estate Financial Intelligence Agent** | Property analysis, cap rates, financing optimization |
| 29 | **Funding Strategy Agent** | Capital stack optimization, debt vs. equity analysis |
| 30 | **Credit Strategy Agent** | Business credit building, financing terms analysis |
| 31 | **Wealth Infrastructure Agent** | Long-term asset allocation, entity structure optimization |
| 32 | **Long-Term Capital Strategy Agent** | 5-10 year capital deployment, intergenerational wealth |
| 33 | **ROI Optimization Agent** | Cross-product ROI comparison, capital efficiency scoring |

### Wave 5: Integration & Intelligence

| # | Agent | Primary Function |
|---|-------|-----------------|
| 34 | **Financial Dashboard Agent** | Bloomberg-terminal style dashboards, executive views |
| 35 | **Executive Reporting Agent** | Board-ready financial packages, investor updates |
| 36 | **Business Intelligence Agent** | Cross-domain analytics, trend identification |
| 37 | **Forecasting Intelligence Agent** | Ensemble forecasting, scenario modeling, Monte Carlo |
| 38 | **Wheeler Brain Integration Agent** | Financial intelligence unified layer, cross-agent synthesis |
| 39 | **No-False-Greens QA Agent** | Independent financial health verification (already exists) |
| 40 | **Autonomous Financial Optimization Agent** | Continuous cost/revenue optimization, self-tuning |

---

## Data Architecture

### Financial Data Sources (Current)

```
LiteLLM :4049 → AI token spend by model/provider/key
Docker socket → Container resource utilization
PM2 daemon → Process memory/cpu/uptime
/proc → System resources (cpu, mem, disk)
Prometheus :9090 → Time-series infrastructure metrics
Loki :3100 → Log-based cost signals
Postgres :5433 → Database storage/utilization
```

### Financial Data Sources (Planned)

```
Stripe API → Subscriptions, payments, invoices, disputes
FRGCRM :8082 → Lead pipeline value, conversion rates
Revenue Metrics Collector :8170 → Aggregated revenue KPIs
Executive Dashboard :8180 → Unified executive view
Neo4j :7687 → Business relationship graph
Superset :8088 → Financial analytics/visualization
```

### Cost Allocation Model

```
Total Monthly Burn: ~$200-300
├── Infrastructure: ~$50-100 (Hetzner CPX51)
├── AI/API Usage: ~$50-100 (DeepSeek, Anthropic, OpenAI)
├── Domains: ~$20
├── SaaS Subscriptions: ~$50
└── Miscellaneous: ~$10-30
```

### Revenue Allocation Model (Future)

```
Revenue Streams (8 planned):
├── FRG Contingency: 30% of recovered funds
├── Prediction Radar: $99-1,999/mo tiers
├── SurplusAI Enterprise: $99-1,999/mo tiers
├── Attorney Marketplace: 30% referral fee
├── Ravyn Capital: Deal-based
├── Lead Intelligence DaaS: $5-150/lead
├── AI Ops Platform: $99-3,999/mo
└── Wheeler Brain Enterprise: $499-9,999/mo
```

---

## Financial Governance Framework

### Authority Levels

| Level | Name | Scope | Example Agents |
|-------|------|-------|---------------|
| 0 | Read-Only | View financial data, no modifications | Revenue Forecasting, KPI Intelligence |
| 1 | Advisory | Recommend actions, require human approval | AI CFO, Capital Allocation |
| 2 | Supervised | Execute with 5-min override window | Monetization Orchestrator |
| 3 | Autonomous | Execute within guardrails, post-action report | Cost Optimization (minor), Budget Alerts |
| 4 | Emergency | Full authority during declared incidents | None (reserved for human) |

### Alert Escalation Matrix

| Severity | Condition | Response | Agents Notified |
|----------|-----------|----------|----------------|
| P0 | Revenue system offline >5min | Immediate war room | AI CFO, CEO Console, Incident Response |
| P1 | MRR drop >10% in 24h | Investigation within 1hr | Revenue Intel, AI CFO, Monetization Orch |
| P1 | Cost spike >2x daily avg | Spending freeze review | Cost Intel, AI Spending Gov, AI CFO |
| P2 | Churn >5% monthly | Retention analysis | Subscription Analytics, Revenue Intel |
| P2 | Budget variance >20% | Budget review | Budget Automation, AI CFO |
| P3 | Optimization opportunity >$50/mo | Advisory report | Infrastructure Cost, Autonomous Opt |

### Separation of Duties

```
Monitoring (read-only): Revenue Intel, Cost Intel, KPI Intelligence
Authorization (human): AI CFO recommendations, Capital Allocation decisions
Execution (supervised): Monetization Orchestrator, Stripe Revenue Agent
Verification (independent): No-False-Greens QA, Financial Governance
```

---

## Integration Architecture

### Agent Communication Pathways

```
AI CFO Agent
├── → Cost Intelligence (infrastructure costs)
├── → Revenue Intelligence (revenue metrics)
├── → Treasury Intelligence (cash position)
├── → Capital Allocation (investment decisions)
├── → Forecasting Intelligence (projections)
├── → Financial Governance (compliance)
└── → Executive Dashboard (:8180) (reporting)

Treasury Intelligence
├── → Stripe Revenue Agent (payment data)
├── → Billing Intelligence (receivables)
├── → Cashflow Forecasting (liquidity)
└── → AI CFO (treasury recommendations)

Capital Allocation Agent
├── → ROI Optimization (investment scoring)
├── → Infrastructure Cost (infra investment ROI)
├── → Acquisition Intelligence (acquisition targets)
└── → AI CFO (allocation recommendations)

Profitability Intelligence
├── → Revenue Intelligence (per-product revenue)
├── → Cost Intelligence (per-product cost allocation)
├── → SaaS KPI Agent (SaaS unit economics)
└── → AI CFO (profitability recommendations)
```

### Dashboard Architecture

```
Executive Financial Dashboard (:8180/finance)
├── Revenue Panel (MRR, ARR, Growth Rate)
├── Cost Panel (Infra, AI, SaaS, Total Burn)
├── Profitability Panel (Gross Margin, Net Margin, Per-Product)
├── Cash Panel (Runway, Burn Rate, Cash Position)
├── KPI Panel (NDR, LTV:CAC, CAC Payback, Magic Number)
├── Forecast Panel (Revenue, Cost, Cash Flow Projections)
└── Alert Panel (Active Financial Alerts, Anomalies)
```

---

## Implementation Roadmap

### Phase 1: Foundation (Current — May 2026)
- [x] Ecosystem reconnaissance complete
- [ ] Deploy Wave 1 agents (8 operational cost agents)
- [ ] Fix COREDB connection (P0 blocker)
- [ ] Fix 3 errored revenue PM2 processes
- [ ] Activate Stripe live mode
- [ ] Deploy Wave 2 agents (10 financial intelligence agents)
- **Deliverable**: ECOSYSTEM_FINANCIAL_MAP.md

### Phase 2: Revenue Activation (June 2026)
- [ ] First Stripe transaction processed
- [ ] Revenue metrics collector operational
- [ ] Deploy Wave 3 agents (9 revenue operations agents)
- [ ] Build executive financial dashboard
- [ ] Establish budget baseline
- **Deliverable**: AI_CFO_ARCHITECTURE.md, ENTERPRISE_KPI_ENGINE.md

### Phase 3: Intelligence Layer (July 2026)
- [ ] 3+ months of revenue history
- [ ] Per-product cost allocation implemented
- [ ] P&L automation operational
- [ ] Cashflow forecasting active
- **Deliverable**: PROFITABILITY_INTELLIGENCE_SYSTEM.md, CAPITAL_ALLOCATION_ENGINE.md

### Phase 4: Strategic Finance (August-September 2026)
- [ ] Multiple revenue streams at scale
- [ ] Deploy Wave 4 agents (strategic finance)
- [ ] Acquisition intelligence operational
- [ ] Investment opportunity scanning active
- **Deliverable**: ACQUISITION_INVESTMENT_ENGINE.md

### Phase 5: Autonomous Optimization (October 2026+)
- [ ] All 40 agents operational
- [ ] Self-tuning cost optimization active
- [ ] Continuous profitability improvement
- [ ] Full autonomous financial operations
- **Deliverable**: AUTONOMOUS_FINANCIAL_OPTIMIZATION.md

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Stripe remains in test mode | Medium | Critical | Direct Stripe activation task |
| COREDB data loss | Low | Critical | Backup verification, migration plan |
| AI cost overrun | Medium | High | AI Spending Governance agent, rate limits |
| Revenue forecasts unreliable | High | Medium | Require 3+ months actual data before forecasting |
| Agent authority creep | Medium | High | Financial Governance agent, separation of duties |
| Infrastructure cost growth | Medium | Medium | Infrastructure Cost agent, right-sizing automation |
| No paying customers | Medium | Critical | Product-market fit validation, lead pipeline activation |

---

## Success Metrics

### Phase 1 Success Criteria
- [ ] All 8 Wave 1 agents deployed and producing reports
- [ ] Infrastructure costs tracked per service (not just globally)
- [ ] AI token spend tracked per model/provider/key
- [ ] COREDB accepting connections
- [ ] Revenue PM2 processes online and healthy

### Phase 2 Success Criteria
- [ ] First $1 of revenue processed through Stripe
- [ ] MRR tracking operational
- [ ] Executive financial dashboard live at :8180/finance
- [ ] Cost allocation per product operational
- [ ] Financial alerts firing and routing correctly

### Long-Term Success Criteria
- [ ] Financial OS self-optimizing (costs trend down as % of revenue)
- [ ] P&L per product updated daily
- [ ] Cash flow forecast accurate within 10% at 13-week horizon
- [ ] Capital allocation decisions data-driven (ROI scored, risk-weighted)
- [ ] Zero financial surprises (all anomalies detected within 1 hour)

---

## Appendix: Agent Deployment Commands

All agents deployed to `/root/.claude/agents/` with standard YAML frontmatter:

```yaml
---
name: agent-name
description: one-line capability description
tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch
model: sonnet
color: green
---
```

Activated via the Claude Code agent fleet. All Wave 1 agents use `model: sonnet` for cost efficiency.
