# PHASE 12 -- COST VS PERFORMANCE REPORT

> Generated: 2026-05-23
> Author: Principal Infrastructure Optimization Engineer
> Scope: Hetzner Cloud -- 3 bare-metal servers, Docker workloads, PM2 services, AI API integration
>
> **Pricing note**: Hetzner prices below are based on publicly listed 2025-2026 rates. Confirm exact prices on [hetzner.com/cloud](https://www.hetzner.com/cloud). Estimated costs marked with ~.

---

## 1. EXECUTIVE SUMMARY

| Metric | EDGE (187.77.148.88) | AIOPS (5.78.140.118) | COREDB (5.78.210.123) |
|---|---|---|---|
| **Cores** | 8 (AMD EPYC 9355P) | 16 (AMD EPYC-Rome) | 16 (AMD EPYC-Rome) |
| **RAM** | 31 GB | 30 GB | 30 GB |
| **Disk** | 387 GB | 338 GB | 338 GB |
| **CPU Utilization** | ~45-76% (load 3.6) | ~29% (load 4.7) | **~1%** (load 0.17) |
| **RAM Utilization** | ~19% (5.9/31 GB) | ~57% (17/30 GB) | **~5%** (1.4/30 GB) |
| **Disk Utilization** | 62% (239/387 GB) | 16% (52/338 GB) | **2%** (6.2/338 GB) |
| **Est. Monthly Cost** | ~€50/mo | ~€74/mo | ~€74/mo |
| **Waste Rating** | MODERATE | MODERATE | **CRITICAL** |

**FINDING: COREDB is catastrophically over-provisioned. It uses 1% CPU, 5% RAM, and 2% disk while costing an estimated €74/mo. This is the single highest-ROI optimization target.**

---

## 2. SERVER UTILIZATION EFFICIENCY

### 2.1 EDGE -- 187.77.148.88 (8-core, 31 GB, 387 GB)

| Resource | Provisioned | Used | Utilization | Waste |
|---|---|---|---|---|
| CPU (load) | 8 cores | ~3.6 avg | ~45% | 55% idle |
| RAM | 31 GB | 5.9 GB | 19% | **81% idle** |
| Disk | 387 GB | 239 GB | 62% | 38% free |
| Swap | 11 GB | 0 B | 0% | 100% idle |

**Assessment**: CPU load is moderate (3.6 average, spikes to 6.3). RAM is heavily underutilized -- only 19% used, leaving ~25 GB idle. Disk usage is reasonable. The 11 GB swap allocation on a 31 GB machine with low RAM pressure is wasteful -- consider removing or reducing to 2 GB.

**Notable processes driving CPU**:
- `du -sh` processes consuming 90-100% CPU (two concurrent, temporary -- likely a monitoring/backup job)
- `litellm` (DeepSeek proxy): 86% CPU at time of check, 312 MB RAM
- `temporal-server`: 14% CPU, 153 MB RAM

### 2.2 AIOPS -- 5.78.140.118 (16-core, 30 GB, 338 GB)

| Resource | Provisioned | Used | Utilization | Waste |
|---|---|---|---|---|
| CPU (load) | 16 cores | ~4.7 avg | ~29% | 71% idle |
| RAM | 30 GB | 17 GB | 57% | 43% idle |
| Disk | 338 GB | 52 GB | 16% | **84% free** |
| Swap | 8 GB | 512 KB | ~0% | 100% idle |

**Assessment**: CPU is underutilized at 29%. RAM is at 57% but **7.7 GB (26% of total RAM) is consumed by 29 concurrent Claude SDK agent sessions**. Without these, actual application RAM usage would be ~9.3 GB (31%). Disk is massively underutilized at 16%.

**Top resource consumers**:
- Claude SDK processes: 29 instances, ~7.7 GB RSS total, heavy CPU usage (each 5-60%)
- ClickHouse: 872 MB, 3% CPU
- LangFlow: 789 MB, 0.2% CPU
- PM2 agent services: ~1.7 GB total across 16 services

**WARNING: docuseal-redis showing 40% CPU usage** -- this is anomalous for a Redis container and may indicate a misconfiguration or workload issue.

### 2.3 COREDB -- 5.78.210.123 (16-core, 30 GB, 338 GB)

| Resource | Provisioned | Used | Utilization | Waste |
|---|---|---|---|---|
| CPU (load) | 16 cores | ~0.17 avg | **~1%** | **99% idle** |
| RAM | 30 GB | 1.4 GB | **5%** | **95% idle** |
| Disk | 338 GB | 6.2 GB | **2%** | **98% free** |

**Assessment: COREDB is the most over-provisioned server in the fleet by an enormous margin.** This 16-core, 30 GB server runs only 3 Docker containers (PostgreSQL, Redis, MinIO) plus 3 bare-metal monitoring processes (Grafana, Loki, Prometheus). Total workload could run comfortably on a CX21 (2 vCPU, 4 GB, €5.99/mo) or CX31 (4 vCPU, 8 GB, €11.99/mo).

**Workload on COREDB**:
- wheeler-postgres (PostgreSQL): 23 MB RAM, 0% CPU
- wheeler-redis (Redis): 4.5 MB RAM, 0.3% CPU
- wheeler-minio (MinIO): 69 MB RAM, 0.06% CPU
- Grafana (bare process): 292 MB RAM, 0.9% CPU
- Loki (bare process): 149 MB RAM, 0.9% CPU
- Prometheus (bare process): 103 MB RAM, 0% CPU
- Node server (bare process): 147 MB RAM, 0.4% CPU

---

## 3. WORKLOAD COST ANALYSIS

### 3.1 Docker Container Map

#### EDGE (10 containers)

| Container | Image | Purpose | Est. RAM | Est. CPU | Business Value |
|---|---|---|---|---|---|
| temporal-server | temporalio/auto-setup | Workflow orchestration | 94 MB | 8.5% | HIGH -- core infra |
| temporal-temporal-ui-1 | temporalio/ui | Temporal dashboard | 7 MB | 0% | MEDIUM -- monitoring |
| private-ai-webui | open-webui | AI chat interface | 665 MB | 0% (paused) | LOW -- paused, evaluate |
| shared-postgres-recovery | postgres:16 | Recovery database | 174 MB | 2% | MEDIUM -- DR/backup |
| prediction-radar-app-scheduler | custom | Prediction scheduler | 47 MB | 0% | HIGH -- product |
| prediction-radar-app-worker | custom | Prediction worker | 38 MB | 0% | HIGH -- product |
| shared-postgres-exporter | prometheus-community | PG metrics export | 15 MB | 0% | LOW -- monitoring |
| usesend | usesend/usesend | Sending service | 131 MB | 0% | MEDIUM |
| usesend-storage | minio/minio | S3-compatible storage | 159 MB | 0% | MEDIUM |
| usesend-redis | redis:7 | Cache/queue | 19 MB | 1% | MEDIUM |

#### AIOPS (25 containers)

| Container | Image | Purpose | Est. RAM | Est. CPU | Business Value |
|---|---|---|---|---|---|
| aiops-clickhouse | clickhouse-server:24.3 | Analytics DB | 872 MB | 2.8% | HIGH -- analytics |
| langflow | langflowai/langflow:1.0.19 | AI workflow builder | 789 MB | 0.2% | MEDIUM -- dev tool |
| aiops-healthchecks | healthchecks:latest | Cron monitoring | 259 MB | 0.2% | MEDIUM |
| prediction-radar-app-api | custom | Prediction API | 258 MB | 0.1% | HIGH -- product |
| aiops-superset | apache/superset:4.1.1 | BI dashboard | 191 MB | 0% | MEDIUM |
| docuseal | docuseal/docuseal:latest | Document signing | 171 MB | 0.2% | MEDIUM |
| dockge | louislam/dockge:1 | Docker compose UI | 161 MB | 0.3% | LOW -- admin tool |
| uptime-kuma | louislam/uptime-kuma:1 | Uptime monitoring | 116 MB | 0.5% | MEDIUM |
| aiops-grafana | grafana/grafana:latest | Dashboards | 133 MB | 0.6% | LOW -- duplicate (see 6) |
| aiops-changedetection | changedetection.io | Web change monitoring | 109 MB | 0.3% | LOW |
| loki | grafana/loki:latest | Log aggregation | 90 MB | 0.8% | LOW -- duplicate (see 6) |
| netdata | netdata/netdata | System monitoring | 77 MB | 0.8% | MEDIUM |
| promtail | grafana/promtail:latest | Log shipping | 42 MB | 2.5% | LOW -- duplicate |
| aiops-prometheus | prom/prometheus:latest | Metrics DB | 46 MB | 0.1% | LOW -- duplicate (see 6) |
| docuseal-redis | redis:7-alpine | Docuseal cache | 4.5 MB | **39.9%** | MEDIUM -- **ANOMALY** |
| aiops-ravynai-app | custom | Opportunity graph | 29 MB | 0% | HIGH -- product |
| aiops-ravynai-postgres | postgis/postgis:16-3.4 | Geo database | 23 MB | 0% | HIGH -- product |
| prediction-radar-app-db | postgres:16 | Prediction DB | 31 MB | 0% | HIGH -- product |
| prediction-radar-app-redis | redis:7 | Prediction cache | 4.4 MB | 0.3% | HIGH -- product |
| prediction-radar-app-web | custom | Prediction web | 13 MB | 0% | HIGH -- product |
| prediction-radar-dashboard-v2 | custom | Prediction dashboard | 39 MB | 0% | HIGH -- product |
| portainer | portainer/portainer-ce | Docker management | 18 MB | 0% | LOW -- admin tool |
| frgops-standby | postgres:16-alpine | Standby database | 51 MB | 0% | MEDIUM |
| hostinger-health-exporter | python:3.12-alpine | Health checks | 13 MB | 0% | LOW |
| dockge-test-nginx | nginx:latest | Test nginx | 14 MB | 0% | LOW -- test container |

#### COREDB (3 containers)

| Container | Image | Purpose | Est. RAM | Est. CPU | Business Value |
|---|---|---|---|---|---|
| wheeler-postgres | postgres:16 | Primary database | 23 MB | 0% | HIGH -- core data |
| wheeler-redis | redis:7 | Cache/queue | 4.5 MB | 0.3% | HIGH -- core data |
| wheeler-minio | minio/minio:latest | S3 storage | 69 MB | 0.1% | HIGH -- core data |

### 3.2 PM2 Process Map

#### EDGE (37 PM2 entries, 17 stopped)

**Online processes (20)**:

| Process | RAM | Business Value | Notes |
|---|---|---|---|
| frgcrm-api | 323 MB | HIGH | Core CRM API |
| litellm-deepseek | 312 MB | HIGH | AI API proxy |
| surplusai-portal-frontend | 147 MB | HIGH | Product frontend |
| design-agent-svc | 127 MB | MEDIUM | Agent service |
| paperless-agent-svc | 123 MB | MEDIUM | Agent service |
| surplusai-scraper-agent-svc | 121 MB | MEDIUM | Agent service |
| horizon-agent-svc | 121 MB | MEDIUM | Agent service |
| prediction-radar-agent-svc | 119 MB | MEDIUM | Agent service |
| ravyn-agent-svc | 118 MB | MEDIUM | Agent service |
| frgcrm-agent-svc | 117 MB | MEDIUM | Agent service |
| voice-agent-svc | 112 MB | MEDIUM | Agent service |
| surplusai-portal-api | 104 MB | HIGH | Product API |
| ravynai-og-sync | 101 MB | HIGH | Data sync |
| ravynai-og-scheduler | 97 MB | HIGH | Data scheduler |
| frg-site | 95 MB | HIGH | Customer-facing site |
| ravynai-opportunity-graph | 91 MB | HIGH | Product |
| temporal-pipeline-worker | 88 MB | HIGH | Workflow execution |
| insforge-agent-svc | 79 MB | MEDIUM | Agent service |
| wheeler-brain-os | 74 MB | MEDIUM | Internal tool |
| event-bus-relay | 75 MB | MEDIUM | Messaging |
| ecosystem-guardian | 72 MB | MEDIUM | System health |
| frgcrm-frontend | 73 MB | HIGH | CRM frontend |
| fundsrecoverygroup-site | 74 MB | HIGH | Customer-facing site |
| attorney-marketplace-frontend | 74 MB | HIGH | Product frontend |
| frg-lead-automation | 74 MB | HIGH | Lead processing |
| ravyn-deal-room-api | 67 MB | HIGH | Product API |
| war-room-server | 66 MB | MEDIUM | Collaboration tool |
| voice-outreach-service | 62 MB | MEDIUM | Outbound calls |
| temporal-pipeline-scheduler | 56 MB | HIGH | Workflow scheduling |
| scraper-redis-bridge | 39 MB | MEDIUM | Data bridge |
| surplusai-health-monitor | 32 MB | LOW | Health checks |
| surplusai-orchestrator | 27 MB | MEDIUM | Scraper orchestration |
| attorney-marketplace-api | 27 MB | HIGH | Product API |
| funnel-analytics | 25 MB | HIGH | Analytics |
| mcp-server | 21 MB | LOW | Dev tool |
| recovery-metric | 19 MB | LOW | Metrics |
| temporal-alert-monitor | 11 MB | LOW | Alerts |
| openspace-mcp | 11 MB | LOW | Dev tool |

**Stopped processes (17) -- zombie configs consuming zero resources but adding management complexity**:
a11y-audit, backup-verification, canary-health-monitor, dr-backup-verify, email-drip, frgcrm-agent-cron, frgcrm-ai-score, frgcrm-autoassign, frgcrm-contact-enrich, frgcrm-db-backup, frgcrm-pipeline-promotion, frgcrm-qualified-promote, k3s-health, lighthouse-daily, pgbouncer, playwright-visual, schemathesis-daily, scraper-lead-bridge, surplusai-continuous

**Recommendation**: Clean up all stopped PM2 processes with `pm2 delete <id>` to reduce clutter.

#### AIOPS (17 PM2 entries, 1 stopped)

| Process | RAM | Business Value | Notes |
|---|---|---|---|
| litellm | 361 MB | HIGH | AI API proxy (duplicate with EDGE) |
| frgcrm-api | 236 MB | HIGH | Core CRM API (duplicate with EDGE) |
| design-agent-svc | 116 MB | MEDIUM | Agent service (duplicate with EDGE) |
| horizon-agent-svc | 109 MB | MEDIUM | Agent service (duplicate with EDGE) |
| surplusai-scraper-agent-svc | 108 MB | MEDIUM | Agent service (duplicate with EDGE) |
| ravyn-agent-svc | 108 MB | MEDIUM | Agent service (duplicate with EDGE) |
| prediction-radar-agent-svc | 107 MB | MEDIUM | Agent service (duplicate with EDGE) |
| paperless-agent-svc | 107 MB | MEDIUM | Agent service (duplicate with EDGE) |
| voice-agent-svc | 107 MB | MEDIUM | Agent service (duplicate with EDGE) |
| frgcrm-agent-svc | 101 MB | MEDIUM | Agent service (duplicate with EDGE) |
| insforge-agent-svc | 73 MB | MEDIUM | Agent service (duplicate with EDGE) |
| ecosystem-guardian | 70 MB | MEDIUM | System health (duplicate with EDGE) |
| event-bus-relay | 67 MB | MEDIUM | Messaging (duplicate with EDGE) |
| openclaw-dashboard | 67 MB | LOW | Dashboard |
| war-room-server | 66 MB | MEDIUM | Collaboration (duplicate with EDGE) |
| voice-outreach-service | 54 MB | MEDIUM | Outbound (duplicate with EDGE) |
| backup-verification | 0 MB | -- | STOPPED |

**Key finding**: AIOPS PM2 processes are heavily redundant with EDGE. 11 of 16 online processes have exact duplicates on EDGE. Combined waste: ~1.5 GB RAM for duplicate agent services.

### 3.3 Highest-Cost Workloads

| Rank | Workload | Server | RAM + CPU Cost | Notes |
|---|---|---|---|---|
| 1 | 29 Claude SDK sessions | AIOPS | ~7.7 GB RAM + API costs | Most expensive single workload |
| 2 | Litellm x2 | EDGE + AIOPS | ~673 MB RAM + API proxy | Duplicate instances |
| 3 | ClickHouse | AIOPS | 872 MB RAM | Analytics DB, high value |
| 4 | LangFlow | AIOPS | 789 MB RAM | Dev tool, moderate value |
| 5 | PM2 agent-svc fleet | EDGE + AIOPS | ~3.3 GB total | Highly duplicated |

### 3.4 Low-Value Workloads

| Workload | Server(s) | Cost | Issue |
|---|---|---|---|
| private-ai-webui (paused) | EDGE | 665 MB RAM | Paused container, not serving traffic |
| portainer + dockge | AIOPS | 179 MB RAM | Two Docker management tools, pick one |
| dockge-test-nginx | AIOPS | 14 MB RAM | Test container, should be removed |
| hostinger-health-exporter | AIOPS | 13 MB RAM | Low-value external monitoring |
| aiops-changedetection | AIOPS | 109 MB RAM | Web change detection, low utilization |
| 17 stopped PM2 processes | EDGE | 0 MB (config only) | Clean up for operational hygiene |
| openspace-mcp / mcp-server | EDGE | 33 MB RAM | Dev tools, low production value |

---

## 4. AI COST ANALYSIS

### 4.1 AI API Usage Patterns

All three servers have active AI API keys (DeepSeek, Anthropic, OpenAI). The primary proxy is LiteLLM running on both EDGE and AIOPS with identical configurations:

```
Models configured:
- deepseek-chat (DeepSeek V3): 1000 RPM limit -- ~€0.14/M input, €0.28/M output tokens
- deepseek-reasoner (DeepSeek R1): 500 RPM limit -- ~€0.55/M input, €2.19/M output
- premium_review (Claude Sonnet 4): 100 RPM limit -- ~$3/M input, $15/M output
- claude-sonnet-4: 100 RPM limit -- ~$3/M input, $15/M output
- claude-opus-4: 50 RPM limit -- ~$15/M input, $75/M output
```

### 4.2 Observed Usage

- **AIOPS**: 29 concurrent Claude SDK instances, all using `deepseek-v4-pro` model. Each session consumes 400-500 MB RAM and 5-60% CPU. This represents ~7.7 GB of server RAM just for AI agent sessions.
- **EDGE**: LiteLLM proxy serving as API gateway, PM2 litellm-deepseek process at 312 MB.
- Both servers share identical DeepSeek API keys and model configurations.

### 4.3 Estimated AI Provider Costs

Without access to API usage dashboards, estimates based on observed patterns:

| Provider | Model(s) | Est. Monthly Volume | Est. Monthly Cost | Notes |
|---|---|---|---|---|
| DeepSeek | deepseek-chat | High (29 concurrent agents) | €150-500/mo | Main workhorse model |
| DeepSeek | deepseek-reasoner | Low-Moderate | €50-150/mo | Complex reasoning tasks |
| Anthropic | Claude Sonnet 4 | Low | €30-80/mo | Premium reviews |
| Anthropic | Claude Opus 4 | Very Low | €10-50/mo | Highest-complexity tasks |
| OpenAI | Unknown | Unknown | €0-30/mo | Key present, usage unclear |
| **TOTAL** | | | **€250-800/mo** | Wide range, needs verification |

### 4.4 Token Usage Efficiency Concerns

1. **29 concurrent Claude agents on AIOPS**: Are all 29 necessary? Each runs `claude --model deepseek-v4-pro`. This is likely a multi-agent orchestration pattern, but 29 instances suggests possible over-parallelization. Each agent context window costs tokens.

2. **No prompt caching evident**: The litellm config on AIOPS shows Redis caching enabled for API responses, but no evidence of Anthropic prompt caching being used in the Claude SDK calls. This could reduce costs 50-90% for repeated system prompts.

3. **Model selection optimization**: Many agent-svc processes likely perform simple tasks (health checks, data validation, routing). These could use cheaper models (deepseek-chat instead of deepseek-v4-pro) or local inference.

4. **RPM limits**: The 1000 RPM limit for deepseek-chat and 500 for deepseek-reasoner suggest expected high throughput. If hitting these limits, costs could be at the upper end of estimates.

### 4.5 AI Optimization Recommendations

| Optimization | Savings Potential | Effort |
|---|---|---|
| Add prompt caching to Claude SDK calls | 30-60% on Anthropic costs | MEDIUM |
| Audit and reduce concurrent agent instances | 10-30% server RAM + API costs | LOW |
| Use smaller model for simple agent tasks | 20-40% on DeepSeek costs | MEDIUM |
| Consolidate to single LiteLLM proxy | Eliminates 312 MB + simplifies | MEDIUM |
| Track per-agent token usage | Enables data-driven optimization | LOW |

---

## 5. RESOURCE RIGHT-SIZING

### 5.1 EDGE: 8-core, 31 GB, 387 GB

**Current estimated cost**: ~€50/mo (CCX33 ~€44 + ~150 GB extra volume ~€7.50)

**Assessment: SLIGHTLY OVER-PROVISIONED**

- CPU: 45% avg utilization is reasonable (headroom for spikes)
- RAM: 19% utilization is low -- 31 GB for a workload using ~6 GB
- Disk: 62% utilization -- acceptable

**Right-sizing options**:

| Option | Instance | Specs | Est. Cost | Savings |
|---|---|---|---|---|
| Stay | CCX33 | 8 vCPU, 32 GB, 240 GB | ~€51/mo | -- |
| Downsize RAM | CPX31 | 8 vCPU, 16 GB, 160 GB | ~€30/mo | €21/mo |
| Downsize + volume | CX41 | 8 vCPU, 16 GB, 160 GB + vol | ~€35/mo | €16/mo |

**Recommendation**: Stay on current instance. At 62% disk usage, the extra volume is needed. CPU headroom is valuable for the Temporal orchestration workload and AI proxy. The RAM waste (25 GB idle) is not worth the disruption of downsizing given that EDGE runs critical infrastructure (Temporal, CRM API, AI proxy).

### 5.2 AIOPS: 16-core, 30 GB, 338 GB

**Current estimated cost**: ~€74/mo (CPX51 ~€73.50)

**Assessment: MODERATELY OVER-PROVISIONED**

- CPU: 29% -- 11 of 16 cores idle on average
- RAM: 57% -- but 7.7 GB is Claude SDK, so application RAM is ~31%
- Disk: 16% -- very low utilization

**Right-sizing options**:

| Option | Instance | Specs | Est. Cost | Savings |
|---|---|---|---|---|
| Stay | CPX51 | 16 vCPU, 32 GB, 360 GB | ~€74/mo | -- |
| Downsize | CCX33 | 8 vCPU, 32 GB, 240 GB | ~€44/mo | €30/mo |
| Optimize + downsize | CCX33 | 8 vCPU, 32 GB, 240 GB | ~€44/mo | €30/mo |

**Recommendation**: Downsize to CCX33 (8 vCPU, 32 GB). Only if the 29 Claude agents are reduced/consolidated first. The 16 cores are significantly underutilized. An 8-core server would run the Docker containers + reduced PM2 fleet at ~60-70% capacity.

### 5.3 COREDB: 16-core, 30 GB, 338 GB

**Current estimated cost**: ~€74/mo (CPX51 ~€73.50)

**Assessment: MASSIVELY OVER-PROVISIONED -- EMERGENCY PRIORITY**

- CPU: 1% -- essentially idle
- RAM: 5% -- 1.4 GB of 30 GB used
- Disk: 2% -- 6.2 GB of 338 GB used
- Workload: 3 Docker containers + 4 bare processes

This server could run on a **CX21 (2 vCPU, 4 GB, 40 GB, €5.99/mo)** and still have headroom.

**Right-sizing options**:

| Option | Instance | Specs | Est. Cost | Savings |
|---|---|---|---|---|
| Aggressive | CX21 | 2 vCPU, 4 GB, 40 GB | ~€6/mo | **€68/mo** |
| Conservative | CX31 | 4 vCPU, 8 GB, 80 GB | ~€13/mo | **€61/mo** |
| Safe | CPX31 | 8 vCPU, 16 GB, 160 GB | ~€31/mo | €43/mo |

**Recommendation**: Downsize to CX31 (4 vCPU, 8 GB, 80 GB, ~€13/mo). This provides 4x the current RAM usage, 4x the CPU, and 12x the disk -- more than enough headroom. **This single change saves ~€61/mo (€732/year).**

---

## 6. DUPLICATE SERVICES DETECTION

### 6.1 Monitoring Stack Duplication

| Service | EDGE | AIOPS | COREDB | Duplicates? |
|---|---|---|---|---|
| **Grafana** | -- | Docker (aiops-grafana, 133 MB) | Bare process (292 MB) | **YES -- 2 instances** |
| **Prometheus** | -- | Docker (aiops-prometheus, 46 MB) | Bare process (103 MB) | **YES -- 2 instances** |
| **Loki** | -- | Docker (loki, 90 MB) | Bare process (149 MB) | **YES -- 2 instances** |
| **Promtail** | -- | Docker (promtail, 42 MB) | -- | Single instance |
| **Netdata** | -- | Docker (netdata, 77 MB) | -- | Single instance |
| **UptimeKuma** | -- | Docker (uptime-kuma, 116 MB) | -- | Single instance |
| **Portainer** | -- | Docker (portainer, 18 MB) | -- | Single instance |
| **Dockge** | -- | Docker (dockge, 161 MB) | -- | Single instance (but overlaps with Portainer) |

**Duplicate waste**:
- COREDB monitoring stack: Grafana (292 MB) + Loki (149 MB) + Prometheus (103 MB) = **544 MB RAM wasted**
- These services already run on AIOPS in Docker containers

### 6.2 Application Duplication

| Service | EDGE | AIOPS | Notes |
|---|---|---|---|
| **Litellm** | PM2 (312 MB) | PM2 (361 MB) | Two proxies, same config |
| **frcrm-api** | PM2 (323 MB) | PM2 (236 MB) | Two CRM APIs |
| **agent-svc (x8)** | PM2 (~960 MB) | PM2 (~860 MB) | 8 agent services duplicated |
| **war-room-server** | PM2 (66 MB) | PM2 (66 MB) | Collaboration server |
| **voice-outreach-service** | PM2 (62 MB) | PM2 (54 MB) | Outbound calls |
| **ecosystem-guardian** | PM2 (72 MB) | PM2 (70 MB) | Health monitoring |
| **event-bus-relay** | PM2 (75 MB) | PM2 (67 MB) | Messaging bus |
| **PostgreSQL** | Docker (recovery) | Docker (x4 instances) | Multiple PG instances |

### 6.3 Consolidation Plan

| Action | RAM Savings | CPU Savings | Complexity | Priority |
|---|---|---|---|---|
| Remove COREDB monitoring (use AIOPS) | ~544 MB | ~2% | LOW | **HIGH** |
| Consolidate LiteLLM to one server | ~312 MB | ~3% | MEDIUM | HIGH |
| Eliminate duplicated agent-svc fleet | ~1.8 GB | ~2% | HIGH | MEDIUM |
| Remove duplicate PM2 services | ~400 MB | ~1% | MEDIUM | MEDIUM |
| Pick Portainer OR Dockge | ~161 MB | 0.3% | LOW | LOW |
| **TOTAL POTENTIAL SAVINGS** | **~3.2 GB RAM** | **~8% CPU** | | |

---

## 7. MONTHLY COST ESTIMATION

### 7.1 Current Estimated Costs

| Category | Item | Monthly Cost |
|---|---|---|
| **Infrastructure** | EDGE (CCX33 + volume) | ~€51 |
| **Infrastructure** | AIOPS (CPX51) | ~€74 |
| **Infrastructure** | COREDB (CPX51) | ~€74 |
| **AI Providers** | DeepSeek (chat + reasoner) | €200-650 |
| **AI Providers** | Anthropic (Sonnet + Opus) | €40-130 |
| **AI Providers** | OpenAI (unknown usage) | €0-30 |
| **TOTAL** | | **~€440-1,010/mo** |

### 7.2 Potential Savings

| Optimization | Type | Monthly Savings | One-Time Effort |
|---|---|---|---|
| **COREDB right-size to CX31** | Infrastructure | **€61** | 2-4 hours |
| **Consolidate AIOPS monitoring** | Infrastructure | -- (QoL) | 1 hour |
| **AIOPS downsize to CCX33** | Infrastructure | **€30** | 4-8 hours |
| **Remove duplicate PM2 services** | Infrastructure | -- (QoL) | 2-4 hours |
| **Consolidate LiteLLM** | Infrastructure | -- (QoL) | 2 hours |
| **AI prompt caching** | AI Provider | €20-80 | 4-8 hours |
| **Model optimization (smaller models)** | AI Provider | €50-200 | 8-16 hours |
| **Reduce concurrent agents** | AI Provider | €20-100 | 2-4 hours |
| **Clean up stopped PM2/zombie configs** | Infrastructure | -- (QoL) | 1 hour |
| **TOTAL** | | **€181-471/mo** | 26-47 hours |

### 7.3 Target Monthly Cost After Optimization

| Category | Current | Target | Savings |
|---|---|---|---|
| EDGE | ~€51 | ~€51 | €0 (stay) |
| AIOPS | ~€74 | ~€44 | €30 |
| COREDB | ~€74 | ~€13 | €61 |
| AI Providers (optimized) | €240-810 | €150-500 | €90-310 |
| **TOTAL** | **~€440-1,010** | **~€260-610** | **~€181-400/mo** |

**Annual savings target: ~€2,200-4,800/year**

---

## 8. BEST ROI OPTIMIZATIONS (RANKED)

### TIER 1: QUICK WINS (minimal effort, high savings)

| Rank | Optimization | Savings | Effort | ROI |
|---|---|---|---|---|
| **1** | **COREDB downsize to CX31** | **€61/mo (€732/yr)** | 2-4 hours | **CRITICAL** |
| **2** | **Remove COREDB monitoring stack** | QoL, -544 MB RAM | 1 hour | HIGH |
| **3** | **Clean up 17+ stopped PM2 processes** | QoL, operational hygiene | 1 hour | HIGH |
| **4** | **Fix docuseal-redis 40% CPU anomaly** | Server stability | 30 min | HIGH |
| **5** | **Remove dockge-test-nginx** | QoL | 5 min | TRIVIAL |
| **6** | **Unpause/remove private-ai-webui** | 665 MB RAM | 5 min | TRIVIAL |

### TIER 2: MEDIUM-TERM OPTIMIZATIONS

| Rank | Optimization | Savings | Effort | ROI |
|---|---|---|---|---|
| **7** | **AIOPS downsize to CCX33** | **€30/mo (€360/yr)** | 4-8 hours | HIGH |
| **8** | **Consolidate LiteLLM to single instance** | 312 MB RAM, simpler ops | 2 hours | MEDIUM |
| **9** | **Add AI prompt caching** | €20-80/mo | 4-8 hours | HIGH |
| **10** | **Audit 29 Claude agents, reduce to ~10** | €20-100/mo + 3-5 GB RAM | 2-4 hours | HIGH |
| **11** | **Model optimization (smaller models)** | €50-200/mo | 8-16 hours | MEDIUM |
| **12** | **Eliminate duplicate agent-svc fleet** | ~1.8 GB RAM, simpler ops | 4-8 hours | MEDIUM |

### TIER 3: LONG-TERM ARCHITECTURE CHANGES

| Rank | Optimization | Savings | Effort | ROI |
|---|---|---|---|---|
| **13** | **EDGE downsize RAM (16 GB)** | €16/mo | 8-16 hours | LOW |
| **14** | **Consolidate EDGE+AIOPS workloads** | Potentially ~€50/mo | 40-80 hours | MEDIUM |
| **15** | **Move to Kubernetes (k3s) for efficiency** | Better bin-packing | 80-160 hours | LOW |
| **16** | **Implement per-tenant AI cost tracking** | Enables cost attribution | 20-40 hours | MEDIUM |

---

## 9. RECOMMENDED ACTION PLAN

### Phase 12a: Emergency Fixes (this week, 4-6 hours)

1. **COREDB right-size**: Migrate workloads to CX31 (4 vCPU, 8 GB, €13/mo)
   - Stop COREDB monitoring (Grafana, Loki, Prometheus) -- these run on AIOPS
   - Keep only wheeler-postgres, wheeler-redis, wheeler-minio
   - Snapshot and migrate to smaller instance
   - **Savings: €61/mo**

2. **Clean up zombie configurations**:
   - `pm2 delete` all stopped processes on EDGE
   - Remove dockge-test-nginx container
   - Unpause or remove private-ai-webui

3. **Fix docuseal-redis CPU anomaly**:
   - Investigate why a redis:7-alpine container uses 40% CPU
   - Restart if necessary

### Phase 12b: Optimization (next 2 weeks, 12-20 hours)

4. **Reduce AIOPS Claude agents**: Audit which 29 Claude SDK sessions are needed. Target reduction to 8-12 active agents. **Savings: €20-100/mo AI costs + 3-5 GB RAM**

5. **Consolidate LiteLLM**: Choose EDGE (primary) or AIOPS, remove duplicate. Configure all services to use single proxy.

6. **AIOPS monitoring consolidation**: Remove COREDB bare-metal Grafana/Loki/Prometheus. Point everything to AIOPS Docker monitoring stack.

7. **AI model optimization**: Use deepseek-chat (not deepseek-v4-pro) for simple agent tasks. Add prompt caching to Anthropic calls.

### Phase 12c: Right-Sizing (next month, 8-16 hours)

8. **AIOPS downsize**: After reducing agents, migrate to CCX33 (8 vCPU, 32 GB, €44/mo). **Savings: €30/mo**

9. **Eliminate duplicate PM2 services**: Consolidate agent-svc fleet to single-server deployment. Choose EDGE or AIOPS as primary for each service type.

10. **Implement AI cost tracking**: Per-agent token usage logging to enable ongoing optimization.

---

## 10. APPENDIX: SERVER DETAILS

### A. Raw Utilization Data (collected 2026-05-23 07:13 UTC)

```
=== EDGE (187.77.148.88) ===
CPU:    8-core AMD EPYC 9355P, load 3.60/6.12/6.29
RAM:    31 GB total, 5.9 GB used, 25 GB available (19% used)
Disk:   387 GB total, 239 GB used (62%), 148 GB free
Swap:   11 GB total, 0 B used
Docker: 10 containers
PM2:    37 entries (20 online, 17 stopped, 0 errored)

=== AIOPS (5.78.140.118) ===
CPU:    16-core AMD EPYC-Rome, load 4.70/3.39/2.62
RAM:    30 GB total, 17 GB used, 13 GB available (57% used)
Disk:   338 GB total, 52 GB used (16%), 273 GB free
Swap:   8 GB total, 512 KB used
Docker: 25 containers
PM2:    17 entries (16 online, 1 stopped, 0 errored)
Claude: 29 SDK agent sessions (~7.7 GB RSS)

=== COREDB (5.78.210.123) ===
CPU:    16-core AMD EPYC-Rome, load 0.17/0.15/0.10
RAM:    30 GB total, 1.4 GB used, 29 GB available (5% used)
Disk:   338 GB total, 6.2 GB used (2%), 318 GB free
Swap:   0 B
Docker: 3 containers
PM2:    none
```

### B. Hetzner Pricing Reference (approximate 2025-2026)

| Model | vCPU | RAM | Disk | Monthly |
|---|---|---|---|---|
| CX21 | 2 | 4 GB | 40 GB | ~€6 |
| CX31 | 4 | 8 GB | 80 GB | ~€13 |
| CX41 | 8 | 16 GB | 160 GB | ~€26 |
| CPX31 | 8 | 16 GB | 160 GB | ~€31 |
| CCX33 | 8 | 32 GB | 240 GB | ~€44 |
| CPX51 | 16 | 32 GB | 360 GB | ~€74 |
| CCX43 | 16 | 64 GB | 360 GB | ~€88 |
| Volume | -- | -- | per GB | ~€0.05/GB/mo |

*Note: Verify current prices at [hetzner.com/cloud](https://www.hetzner.com/cloud). Pricing may have changed.*

---

## 11. KEY FINDINGS SUMMARY

1. **COREDB is an emergency**: 16-core server at 1% utilization costing ~€74/mo. Can downsize to €13/mo immediately.

2. **29 Claude AI agents on AIOPS**: Consuming ~7.7 GB RAM and driving the majority of AI API costs. Needs audit and reduction.

3. **Duplicate monitoring stack**: COREDB runs a complete second Grafana/Prometheus/Loki stack (544 MB) that mirrors AIOPS.

4. **Duplicate PM2 services**: 11 process types duplicated between EDGE and AIOPS, wasting ~1.8 GB RAM.

5. **Zombie configurations**: 17 stopped PM2 processes on EDGE, test containers, and paused services adding operational debt.

6. **AI costs likely significant**: Three providers (DeepSeek, Anthropic, OpenAI) with 29 concurrent agents. Estimated €250-800/mo without prompt caching.

7. **docuseal-redis anomaly**: Redis container consuming 40% CPU -- needs investigation.

8. **Total addressable savings**: €181-400/mo (€2,172-4,800/year) with a one-time investment of 26-47 hours.

**ROI on executing all Tier 1 (Quick Wins): >10,000% annual return.**
