# Wheeler Ecosystem Financial Map
## Complete Financial Data Source Topology

**Date**: 2026-05-25
**Status**: Live document — maps every financial data source, agent, and flow

---

## Financial Data Sources (Current — May 2026)

```
LIVE DATA SOURCES
├── LiteLLM :4049 → AI token spend by model/key/request
│   ├── /spend/logs — per-request cost
│   ├── /spend/keys — per-API-key attribution
│   └── /global/activity — usage patterns
├── Docker socket → container resource utilization
│   ├── docker stats — CPU, memory, network, disk per container
│   ├── docker system df — image/volume/container disk usage
│   └── docker images — image sizes and ages
├── PM2 daemon → process metrics
│   └── pm2 jlist — memory, cpu, uptime, restart count per process
├── /proc filesystem → system resources
│   ├── /proc/cpuinfo — CPU model and cores
│   ├── /proc/meminfo — detailed memory breakdown
│   └── free, df, uptime — system health
├── Prometheus :9090 → time-series metrics
├── Loki :3100 → log aggregation
└── Nginx → access logs, bandwidth patterns

PLANNED DATA SOURCES (when live)
├── Stripe API → subscriptions, payments, invoices, disputes
├── FRGCRM :8082 → lead pipeline, case values
├── Revenue Metrics Collector :8170 → aggregated KPIs
├── Executive Dashboard :8180 → unified view
└── Neo4j :7687 → financial knowledge graph
```

---

## Cost Flow Map

```
MONTHLY BURN: ~$200-300
│
├── HETZNER CPX51: ~$50-100/mo
│   └── Allocated to services by resource consumption
│       ├── AI/Agent Operations: ~$15-25
│       ├── Data Infrastructure: ~$10-20
│       ├── Observability: ~$10-15
│       ├── Revenue Systems: ~$10-20
│       ├── Security: ~$5-10
│       └── Infrastructure: ~$5-10
│
├── AI/API COSTS: ~$50-100/mo
│   ├── DeepSeek: ~$20-50 (Chat + Reasoner)
│   ├── Anthropic (Claude): ~$20-40
│   └── OpenAI: ~$5-10
│
├── SAAS SUBSCRIPTIONS: ~$50/mo
│   ├── Monitoring tools
│   ├── Development tools
│   └── Productivity tools
│
├── DOMAINS: ~$20/mo (annualized)
│   └── Multiple domain registrations
│
└── OTHER: ~$10-30/mo
    └── Miscellaneous, buffer
```

---

## Revenue Flow Map (Planned)

```
REVENUE STREAMS (8 planned, 0 live)
│
├── FRG CONTINGENCY (30% of recovered surplus funds)
│   └── Tracked in: FRGCRM :8082
│   └── Status: 6,603 cases stuck (PipelineDAG broken)
│
├── PREDICTION RADAR SAAS ($99-1,999/mo tiers)
│   └── Tracked in: Stripe (test mode)
│   └── Status: 14 Docker containers healthy, no payments
│
├── SURPLUSAI ENTERPRISE ($99-1,999/mo tiers)
│   └── Tracked in: Stripe (test mode)
│   └── Status: Portal API online, scraper degraded
│
├── ATTORNEY MARKETPLACE (30% referral fee)
│   └── Tracked in: Attorney Marketplace API :8120
│   └── Status: 4 attorneys, no matching
│
├── RAVYN CAPITAL (deal-based)
│   └── Tracked in: Ravyn API :8007
│   └── Status: API healthy, PostGIS online
│
├── LEAD INTELLIGENCE DAAS ($5-150/lead)
│   └── Status: Not built
│
├── AI OPS PLATFORM ($99-3,999/mo)
│   └── Status: Infrastructure exists, not productized
│
└── WHEELER BRAIN ENTERPRISE ($499-9,999/mo)
    └── Status: Strategic play, not active
```

---

## Agent-to-Data Mapping

| Agent | Primary Data Source(s) | Query Method |
|-------|----------------------|--------------|
| infrastructure-cost | docker stats, pm2 jlist, free, df | Bash (local commands) |
| ai-token-cost | LiteLLM :4049 /spend/* | curl |
| api-cost-intelligence | LiteLLM :4049 + WebSearch (pricing pages) | curl + WebFetch |
| ai-spending-governance | LiteLLM :4049 /global/activity | curl |
| infrastructure-optimization | docker system df, docker images, du | Bash |
| vendor-optimization | WebSearch, local config files | Bash + WebFetch |
| resource-allocation | docker stats, pm2 jlist, /proc | Bash |
| scaling-cost-forecast | Historical trends from above | Computed |
| stripe-revenue | Stripe API (STRIPE_SECRET_KEY) | curl (when live) |
| billing-intelligence | Stripe API (invoices, payment intents) | curl (when live) |
| subscription-analytics | Stripe API (subscriptions, customers) | curl (when live) |
| All Wave 2 agents | Synthesized from Wave 1 + Wave 3 | Computed |
| All Wave 4-5 agents | Synthesized from Waves 1-3 | Computed |

---

## Financial Data Freshness Requirements

| Data Type | Maximum Staleness | Refresh Frequency |
|-----------|------------------|-------------------|
| AI Spend | 15 minutes | Every 5 minutes |
| Infrastructure Cost | 1 hour | Every 30 minutes |
| Container Health | 5 minutes | Every 5 minutes |
| PM2 Process Health | 5 minutes | Every 5 minutes |
| Revenue (when live) | 1 hour | Every 15 minutes |
| KPI Calculations | 24 hours | Daily |
| Forecasts | 24 hours | Daily |
| Vendor/SaaS Costs | 7 days | Weekly |
| Market/Competitive Intel | 7 days | Weekly |
