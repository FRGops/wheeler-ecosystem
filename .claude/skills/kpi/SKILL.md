---
name: kpi
description: Wheeler Ecosystem KPI Tracking — revenue, lead gen, infrastructure, deployment, automation, AI agent, product, security, cost, and operational velocity metrics. All measured from live data sources.
metadata:
  type: skill
  version: "1.0.0"
  author: Wheeler Brain OS
  tags:
    - kpi
    - metrics
    - dashboard
    - tracking
---

# KPI Tracking System

Comprehensive KPI tracking across 10 domains. Full system at `/root/ECOSYSTEM_KPI_SYSTEM.md`.

## Subcommands

### `/kpi dashboard`
Show current KPI dashboard across all domains.

**Displays:**
- Overall ecosystem health score
- Revenue MRR/ARR with trends
- Docker/PM2 health percentages
- Active alerts count
- Top 3 KPIs needing attention

### `/kpi revenue`
Show revenue KPIs.

**Metrics:** MRR, ARR, churn rate, LTV, CAC, Stripe health, subscription count, revenue per product, MoM growth, YoY growth.

**Data source:** revenue-metrics-collector (:8170)

### `/kpi health`
Show infrastructure health KPIs.

**Metrics:** Ecosystem health score, Docker health %, PM2 health %, CPU/RAM/Disk utilization, uptime %, backup success rate, MTTR, MTBF.

**Data sources:** Docker, PM2, Prometheus (:9090), Uptime Kuma (:3001)

### `/kpi velocity`
Show operational velocity KPIs.

**Metrics:** Tasks completed today/this week, cycle time, throughput, WIP count, blocked tasks, blocker resolution time, deployment frequency, deployment success rate.

### `/kpi review`
Weekly KPI review.

**Process:**
1. Pull current values for all KPIs
2. Compare against targets
3. Flag KPIs outside acceptable range
4. Show trends (improving/worsening/stable)
5. Recommend actions for red/yellow KPIs
6. Generate weekly KPI report

### `/kpi target <kpi> <value>`
Set or update a KPI target. Persisted to `/root/.kpi/targets.json`.

## KPI Reference

| KPI | Current | Target | Status |
|-----|---------|--------|--------|
| Ecosystem Health | 95/100 | 99/100 | 🟡 |
| Revenue MRR | $72K | $100K | 🟡 ⚠️ |
| Docker Health | 43/44 | 44/44 | 🟡 |
| PM2 Health | 24/24 | 24/24 | 🟢 |
| Backup Success | 100% | 100% | 🟢 |
| Agent Utilization | 0% | >50% | 🔴 |
| AI Cost/Month | ~$50K | <$30K | 🔴 |
| Uptime | ~99% | 99.9% | 🟡 |
| Deploy Success | N/A | >95% | ⚪ |
| MTTR (P1) | N/A | <4h | ⚪ |

## Data Sources

| Source | Endpoint | Metrics |
|--------|----------|---------|
| Revenue Collector | :8170 | MRR, ARR, subscriptions, Stripe |
| Executive Dashboard | :8180 | Aggregated metrics, anomalies |
| Prometheus | :9090 | Time-series, resources, uptime |
| Docker | docker ps | Container health, uptime |
| PM2 | pm2 jlist | Process health, restarts, memory |
| Uptime Kuma | :3001 | Endpoint reachability |
| Loki | :3100 | Error rates, log patterns |
| Alertmanager | :9093 | Active alerts, MTTR |

## Alert Thresholds

| KPI | Yellow | Red |
|-----|--------|-----|
| Health Score | <95 | <85 |
| Docker Health | <95% | <90% |
| PM2 Health | <95% | <90% |
| Revenue MRR | <-5% MoM | <-15% MoM |
| Backup Success | <100% | <90% |
| AI Cost | >$40K/mo | >$60K/mo |
| Uptime | <99.5% | <99% |
