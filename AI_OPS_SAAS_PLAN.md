# Wheeler AI Ops SaaS Commercialization Plan

**Version:** 1.0.0  
**Date:** 2026-05-24  
**Classification:** INTERNAL -- EXECUTIVE  
**Based on:** Autonomous AI Ops Architecture v2.0, Revenue Engine Architecture v1.0 (Section 9)  
**Infrastructure Reference:** 3-node deployment (2 Hetzner CPX51 + 1 Hostinger VPS), 41 Docker containers, 20 PM2 processes, Tailscale mesh  

---

## Table of Contents

1. Executive Summary
2. Infrastructure Capacity and Cost Basis
3. Product Portfolio
4. Service Catalog
5. Multi-Tenant Architecture
6. Packaging and Deployment Options
7. Implementation Plan
8. Billing and Pricing Model
9. SLA Framework
10. Go-to-Market Strategy
11. Financial Projections
12. Risks and Mitigations

---

## 1. Executive Summary

The Wheeler AI Ops platform is a production-grade, zero-trust AI infrastructure running across 3 physical nodes with 42 services (41 Docker containers, 20 PM2 processes), a complete observability stack (Prometheus, Grafana, Loki, Alertmanager, Uptime Kuma), deployment and rollback engines, AI model routing via LiteLLM, and a self-healing watchdog system. This document outlines how to package, price, sell, and deliver this infrastructure as commercial SaaS products.

The plan is grounded entirely on real infrastructure capacity. No hypothetical "add 10 more servers" scaling. Multi-tenant design must fit within the existing 3-node, 32 GB RAM per node envelope. Pricing reflects real costs: Hetzner CPX51 at approximately $85/mo per node, Hostinger at approximately $15/mo.

**Core proposition:** Sell hardened, zero-trust AI operations infrastructure to companies that need production-grade monitoring, deployment, AI routing, and security but cannot build it themselves. The product is the infrastructure the Wheeler ecosystem has already validated at 100/100 QA score.

---

## 2. Infrastructure Capacity and Cost Basis

### 2.1 Current Hardware

| Node | Provider | Spec | Monthly Cost | Role | Services |
|------|----------|------|-------------|------|----------|
| AIOPS | Hetzner CPX51 | 16 vCPU, 32 GB RAM, 360 GB NVMe | ~$85/mo | Application, AI agents, monitoring, gateway | 37 Docker, 20 PM2, Nginx |
| COREDB | Hetzner CPX51 | 16 vCPU, 32 GB RAM, 360 GB NVMe | ~$85/mo | Databases, object storage, Temporal | PostgreSQL, Redis, MinIO |
| Hostinger Edge | VPS | 4 vCPU, 8 GB RAM (est) | ~$15/mo | Edge gateway (legacy, decommissioning) | Traefik, legacy services |
| **Total** | | **36 vCPU, 72 GB RAM** | **~$185/mo** | | |

### 2.2 Available Capacity for Tenant Workloads

Current self-hosted services consume approximately 60-70% of AIOPS resources. Conservative remaining capacity:

| Resource | Total | Self-Used | Available for Tenants |
|----------|-------|-----------|----------------------|
| AIOPS RAM | 32 GB | ~22 GB | ~10 GB |
| AIOPS vCPU | 16 | ~10 | ~6 |
| COREDB RAM | 32 GB | ~16 GB | ~16 GB |
| COREDB vCPU | 16 | ~8 | ~8 |
| Disk (AIOPS) | 360 GB | ~120 GB | ~240 GB |
| Disk (COREDB) | 360 GB | ~80 GB | ~280 GB |

**Capacity constraint:** Without adding hardware, the platform can support approximately 5-8 small tenants (basic monitoring) or 2-3 medium tenants (full observability + AI routing) or 1 enterprise tenant (isolated stack).

### 2.3 Cost Multipliers

| Cost Component | Monthly | Per-Tenant (at 5 tenants) | Notes |
|---------------|---------|--------------------------|-------|
| Hetzner (x2) | $170 | $34 | Base compute |
| Hostinger | $15 | $3 | Edge/legacy |
| Tailscale (team) | $0-48 | $0-10 | Free tier for small teams |
| LiteLLM proxy | $0 | $0 | Self-hosted, no SaaS fee |
| Domain/DNS | $15 | $3 | Per-tenant subdomain |
| Stripe fees | 2.9% + $0.30 | Variable | Payment processing |
| Support labor | $0 (included) | $0 | DevOps team already staffed |
| **Total infrastructure** | **~$200/mo** | **~$40-50/mo per tenant** | At 5 tenants |

### 2.4 Break-Even Analysis

| Tenants | Monthly Revenue (Starter mix) | Revenue (Pro mix) | Revenue (Mixed) |
|---------|------------------------------|-------------------|-----------------|
| 1 | $99 | $499 | $499 |
| 3 | $297 | $1,497 | $1,200 |
| 5 | $495 | $2,495 | $1,800 |
| 10 | $990 | $4,990 | $3,500 |

Break-even (covering $200/mo infrastructure): 2 Starter tenants or 1 Pro tenant.

---

## 3. Product Portfolio

### 3.1 AI Ops Starter

**Target market:** Startups, small dev teams, solo founders who need basic monitoring and health checks for their infrastructure.

**Price:** $99/mo (annual: $990/yr, effectively $82.50/mo)

**What they get:**

| Component | Detail | Tenant Isolation |
|-----------|--------|-----------------|
| Uptime monitoring | 10 uptime checks via shared Uptime Kuma | Separate monitor list, shared instance |
| Health check endpoints | 5 HTTP health check endpoints | Per-tenant config in shared instance |
| Basic Prometheus metrics | 5 metrics targets, 7-day retention | Separate scrape target in shared Prometheus |
| Grafana dashboard | 1 shared dashboard (read-only) | Separate Grafana org/ viewer |
| Discord/Slack alerts | 1 alert channel, basic rules | Alertmanager route per tenant |
| Email support | Business hours, 24h response | Shared queue |
| Deployment engine access | 1 service deployment per month | Shared deployment-engine instance |

**Limitations:**
- No self-healing
- No AI routing
- No rollback engine access
- No SLA (best-effort uptime)
- Data retention: 7 days metrics, 30 days logs
- Maximum 5 alerts per day

**Real infrastructure mapping:**
- Runs on existing AIOPS monitoring stack (Prometheus:9090, Grafana:3002, Loki:3100, Alertmanager:9093)
- No additional Docker containers needed
- Adds approximately 0.5 GB RAM per tenant
- Up to 8 tenants on current hardware

**Included support:**
- Email support (24h response business hours)
- Documentation and setup guide
- 30-minute onboarding call

### 3.2 AI Ops Pro

**Target market:** Growth-stage companies, SaaS platforms, agencies with 5-20 servers needing full observability, deployment automation, and AI routing.

**Price:** $499/mo (annual: $4,990/yr, effectively $416/mo)

**What they get (includes everything in Starter, plus):**

| Component | Detail | Tenant Isolation |
|-----------|--------|-----------------|
| Full observability stack | Prometheus + Grafana + Loki + Alertmanager | Per-tenant data sources in shared stack |
| Log aggregation | Loki with 90-day retention, structured logging | Per-tenant label-based isolation |
| Deployment engine | deploy-service.sh access, 10 deployments/mo | Shared engine, per-tenant configs |
| Rollback engine | Auto-rollback on deploy failure | Shared engine, per-tenant backups |
| LiteLLM AI routing | AI model proxy with key management | Per-tenant API keys, shared proxy |
| Self-healing | Container auto-restart, PM2 watch | Covers tenant containers on shared infra |
| Uptime Kuma | 25 external uptime checks | Per-tenant monitor list |
| Nginx gateway | Basic auth + rate limiting for tenant services | Shared Nginx, per-tenant vhost |
| Slack/Teams/PagerDuty | 5 alert channels, configurable routing | Alertmanager routes per tenant |
| Backup management | Daily PostgreSQL backups, 7-day retention | Per-tenant backup schedule |
| Healthchecks.io | 25 cron job monitors | Per-tenant checks |
| Priority support | 8h response, business hours | Shared queue with priority tag |

**Limitations:**
- No white-label (branded as Wheeler AI Ops)
- No multi-server support (single-node tenant)
- No compliance reporting
- Data retention: 90 days metrics, 90 days logs

**Real infrastructure mapping:**
- Reuses existing monitoring stack, deployment engine, rollback engine
- LiteLLM already handles multi-key routing (uses header-based auth)
- Per-tenant backup via existing postgres-backup-local containers
- Each Pro tenant consumes approximately 1.5-2 GB RAM total
- Up to 4 tenants on current hardware

**Included support:**
- Priority email + chat support (8h response business hours)
- Monthly health review call (30 min)
- Deployment support for standard stacks
- Onboarding: 2-hour setup session

### 3.3 AI Ops Enterprise

**Target market:** Mid-market companies, fintech platforms, compliance-sensitive businesses needing zero-trust security, dedicated infrastructure, and SLA guarantees.

**Price:** $1,999/mo (annual: $19,990/yr, effectively $1,666/mo)

**What they get (includes everything in Pro, plus):**

| Component | Detail | Tenant Isolation |
|-----------|--------|-----------------|
| Dedicated monitoring stack | Separate Prometheus/Grafana/Loki per tenant | Full stack isolation |
| Dedicated LiteLLM | Isolated AI proxy instance | Full process isolation |
| Zero-trust security | UFW lockdown, cap_drop ALL, 127.0.0.1 binds | Full enforcement per tenant |
| Secret rotation | Automated internal secret rotation | Per-tenant secret store |
| cap_drop ALL compliance | All tenant containers audited | CI/CD gate enforcement |
| Compliance reporting | Monthly QA scorecard (100-point audit) | Per-tenant report |
| SLA guarantee | 99.5% uptime for tenant monitoring stack | Measured per tenant |
| Multi-server support | Up to 5 tenant servers monitored | Aggregated dashboard |
| Dedicated Nginx vhost | Tenant subdomain with TLS | Full isolation |
| On-premise option | Deploy on tenant's own servers | Full physical isolation |
| Advanced alerting | PagerDuty, OpsGenie, multiple escalation paths | Per-tenant routing |
| 1-year log retention | Full Loki retention | Separate storage allocation |
| SSO/SAML | Identity provider integration | Per-tenant IdP config |
| Security audit | Weekly port bind scan, secret leak detection | Automated report |
| Rollback engine | Unlimited rollbacks, 30-day backup retention | Per-tenant backup chain |

**Real infrastructure mapping:**
- Requires dedicated Docker compose stack per tenant (monitoring + routing)
- Current AIOPS node can support 1-2 Enterprise tenants
- COREDB node provides database isolation per tenant
- Dedicated Grafana org, Prometheus data directory, Loki index per tenant
- Estimated resource consumption: 4-6 GB RAM per enterprise tenant
- At 2 Enterprise tenants, hardware is near saturation -- triggers Phase 2 expansion

**Included support:**
- 24/7 priority support with 2h response
- Dedicated Slack channel
- Weekly health review call
- Monthly executive summary
- Onboarding: full-day setup with migration
- Named support engineer

### 3.4 AI Ops Agency

**Target market:** MSPs, digital agencies, DevOps consultancies that need white-label infrastructure for their own clients.

**Price:** $3,999/mo (annual: $39,990/yr, effectively $3,333/mo)

**What they get:**

| Component | Detail |
|-----------|--------|
| White-label portal | Branded as agency's own product, no Wheeler references |
| Multi-tenant management | Agency manages sub-tenants through admin console |
| Tenant provisioning | Self-service tenant creation via API + UI |
| 10 sub-tenant slots | Agency can onboard up to 10 of their own clients |
| Each sub-tenant at Pro level | All sub-tenants get full Pro feature set |
| Usage metering | Per-tenant metrics collection for agency billing |
| API access | Full API for tenant CRUD, monitoring data, alerts |
| Custom domain | Agency's own domain, TLS managed |
| Agency admin dashboard | Overview of all sub-tenants health, usage, billing |
| Stripe integration ready | Metered billing data exportable to Stripe |
| On-premise option | Deploy on agency's own servers (add $500/mo) |

**Real infrastructure mapping:**
- Each sub-tenant at Pro level (1.5-2 GB RAM each) = 15-20 GB RAM for 10 sub-tenants
- This EXCEEDS current available capacity on AIOPS (10 GB available)
- **Requirement:** Must add 1 Hetzner CX52 node ($115/mo) for agency deployments
- OR limit to 5 sub-tenants on current hardware
- Agency admin dashboard runs on existing command-center infrastructure
- White-labeling: nginx template replacement, Grafana branding API

**Included support:**
- 24/7 priority support with 1h response
- Dedicated account manager
- Weekly operations review
- Monthly business review with usage analytics
- Onboarding: 2-day setup with migration support
- Technical account manager

**Capacity constraint note:** With current 3-node hardware, Agency tier supports maximum 5 sub-tenant slots (not 10) without adding nodes. The 10-slot offering requires adding 1 Hetzner CX52 ($115/mo) to the infrastructure, bringing base cost to ~$300/mo. Pricing already accounts for this at 67% gross margin.

### 3.5 AI Ops API

**Target market:** Developers and platforms that want to integrate infrastructure intelligence into their own products -- health check data, monitoring webhooks, deployment triggers, AI routing.

**Price:** $0.01 per API call (first 1,000 calls free/month)

**Endpoints:**

| Endpoint | Description | Rate Limit | Use Case |
|----------|-------------|------------|----------|
| `GET /v1/health/{target}` | Execute health check against target URL | 60/min | External monitoring |
| `GET /v1/metrics/{target}` | Return latest Prometheus-style metrics | 30/min | Data integration |
| `POST /v1/deploy` | Trigger deployment via deployment engine | 5/min | CI/CD integration |
| `POST /v1/rollback` | Trigger rollback to previous deploy | 5/min | emergency recovery |
| `POST /v1/ai/route` | Route LLM request through LiteLLM proxy | 100/min | AI routing as a service |
| `GET /v1/status/{service}` | Return service health status | 60/min | Status page integration |
| `POST /v1/alerts/webhook` | Ingest external alert into Alertmanager | 30/min | Alert consolidation |
| `GET /v1/scorecard` | Return latest QA scorecard (100-point) | 10/min | Compliance reporting |

**Sample pricing scenarios:**
- Startup monitoring: 5,000 calls/mo = $40/mo (plus $40 for 4K over free tier)
- CI/CD integration: 20,000 calls/mo = $190/mo
- AI routing service: 100,000 calls/mo = $990/mo
- Full platform integration: 500,000 calls/mo = $4,990/mo

**Real infrastructure mapping:**
- API gateway runs on existing command-center PM2 process
- Each endpoint maps to existing scripts/validators
- No new infrastructure required for first 100,000 calls/month
- Rate limiting via existing Nginx configuration
- Authentication via API keys (pattern: INTERNAL_API_KEY)

### 3.6 Comparison Matrix

| Feature | Starter $99 | Pro $499 | Enterprise $1,999 | Agency $3,999 |
|---------|:----------:|:--------:|:-----------------:|:-------------:|
| Uptime monitoring | 10 checks | 25 checks | 100 checks | 250 checks (10 tenants) |
| Health endpoints | 5 | 25 | Unlimited | Unlimited |
| Metrics retention | 7 days | 90 days | 365 days | 90 days per tenant |
| Log retention | 30 days | 90 days | 365 days | 90 days per tenant |
| Deployment engine | 1/mo | 10/mo | Unlimited | Unlimited |
| Rollback engine | -- | Included | Included | Included |
| AI routing (LiteLLM) | -- | 1 model key | 5 model keys | 10 model keys |
| Self-healing | -- | Containers | Full stack | Full stack per tenant |
| Multi-server | -- | -- | Up to 5 nodes | Per-sub-tenant |
| White-label | -- | -- | -- | Full |
| SLA | None | 99.0% | 99.5% | 99.5% per tenant |
| Compliance reports | -- | -- | Weekly | Monthly per tenant |
| SSO/SAML | -- | -- | Included | Included |
| Sub-tenant slots | -- | -- | -- | Up to 10 |
| On-premise | -- | -- | Optional (+$500) | Optional (+$500) |
| Support | Email, 24h | Chat + email, 8h | 24/7, 2h response | 24/7, 1h response |
| Max tenants on current HW | 8 | 4 | 2 | 1 (5 sub-tenants) |

---

## 4. Service Catalog

### 4.1 Managed Monitoring

**What it is:** Full Prometheus + Grafana + Loki + Alertmanager stack configured, maintained, and updated by Wheeler AI Ops.

**Real infrastructure:** Runs on existing monitoring stack at `/opt/apps/monitoring/` (5 containers: prometheus, alertmanager, grafana, loki, webhook-relay). Additionally: Uptime Kuma (docker-run), Healthchecks (docker compose), Netdata (docker-run).

**Delivery model:**
- Per-tenant data sources within shared Grafana (org separation)
- Per-tenant Prometheus scrape configs with label-based isolation
- Per-tenant Loki streams via `tenant_id` label
- Pre-built dashboard templates (20+ dashboards from Wheeler ecosystem)
- Alert rules template library (50+ rule templates)

**Service tiers:**

| Tier | Prometheus | Grafana | Loki | Uptime Kuma | Healthchecks | Price (add-on) |
|------|-----------|---------|------|-------------|-------------|----------------|
| Basic | Shared, 7d retention | 1 org, 5 dashboards | 30d retention | 10 checks | 10 checks | Included in Starter |
| Standard | Shared, 90d retention | 1 org, 20 dashboards | 90d retention | 25 checks | 25 checks | Included in Pro |
| Premium | Dedicated, 365d retention | 1 org, unlimited dashboards | 365d retention | 100 checks | 100 checks | Included in Enterprise |
| Agency | Per-sub-tenant at Standard | Admin org + sub-tenant orgs | Per-sub-tenant | Pooled | Pooled | Included in Agency |

**Operational burden (internal):**
- Stack upgrades: quarterly (Prometheus, Grafana, Loki minor versions), ~2h per upgrade
- Alert rule tuning: 1h per tenant per month initially, decreasing to 15min after stabilization
- Dashboard maintenance: 30min per tenant per month
- **Total ops overhead at 5 tenants: ~10h/month**

### 4.2 Managed Deployments

**What it is:** Access to the Wheeler deployment engine (`deploy-service.sh`) with 7-gate preflight checks, automated deployment, and post-deploy verification.

**Real infrastructure:** `/root/deployment-engine/deploy-service.sh` pipeline supporting Docker, PM2, static, and systemd service types. Integration with existing rollback engine and smoke tests.

**Service tiers:**

| Tier | Deployments/mo | Preflight Gates | Auto-Rollback | Verification |
|------|---------------|----------------|---------------|--------------|
| Starter | 1 | Gate 1-3 (state, deps, resources) | -- | Basic health check |
| Pro | 10 | Gate 1-5 (state, deps, resources, config, secrets) | On failure | smoke-test-all.sh |
| Enterprise | Unlimited | Gate 1-7 (full) | On any failure | Full smoke test (8 sections) |
| Agency | 10 per sub-tenant | Gate 1-5 per sub-tenant | Per sub-tenant | Per sub-tenant |

**Deployment types supported:**

| Type | Detection | Method | Auto-rollback |
|------|-----------|--------|---------------|
| Docker | docker-compose.yml | compose up -d | Previous image tag |
| PM2 | ecosystem.config.js | pm2 delete + env -i start | PM2 dump restore |
| Static | /public or /dist | rsync to nginx directory | Previous version |
| Systemd | systemd unit file | systemctl restart | Previous unit |

**Operational burden (internal):**
- Deployment engine: zero ongoing maintenance (already stable)
- Tenant deployments require monitoring but no active work (automated)
- Rollback interventions: estimated 1 per 20 deployments (5%)
- **Total ops overhead: ~2h/month per 100 deployments**

### 4.3 Managed Rollbacks

**What it is:** Automated rollback engine that detects deployment failures and reverts to previous known-good state within 60 seconds.

**Real infrastructure:** `/root/rollback-engine/` with 5-phase process: discovery, execute, verification, preservation, notification. Supports docker, pm2, static, routing restores.

**Rollback triggers (configurable per tenant):**
- Container healthcheck fails 3 consecutive times after deploy
- Error rate >2x baseline in 5 minutes
- Memory exceeds limit within 2 minutes
- PM2 process restarts >2 times in first 60 seconds
- Manual rollback via API

**Included in:** Pro, Enterprise, Agency tiers
**Add-on for Starter:** $50/mo (limited to Docker services only)

### 4.4 Managed Security

**What it is:** Zero-trust security enforcement as a service: port lockdown, container capability restrictions, secret rotation, and compliance auditing.

**Real infrastructure:** Direct application of the Wheeler security model:
- UFW rules management (tailscale0-only for admin, 127.0.0.1 binds for all containers)
- cap_drop ALL enforcement on all tenant containers
- Secret rotation via `.env` file management + PM2 `env -i delete+start` pattern
- Port bind watchdog (`wheeler-lockdown-watchdog.sh` runs every 5 minutes)
- PM2 jlist secret scanning (automated detection of credentials in process state)

**Service tiers:**

| Capability | Starter | Pro | Enterprise | Agency |
|-----------|---------|-----|-----------|--------|
| Port bind audit | Monthly | Weekly | Daily | Per sub-tenant |
| cap_drop ALL audit | -- | Weekly | Daily | Per sub-tenant |
| Secret scan | -- | Monthly | Weekly | Per sub-tenant |
| UFW management | -- | -- | Included | Per sub-tenant |
| Secret rotation | -- | Monthly | Weekly | Per sub-tenant |
| Compliance report | -- | -- | Weekly + on-demand | Monthly per sub-tenant |
| Watchdog enforcement | -- | -- | 5-minute interval | Per sub-tenant |

**Real costs:** Zero incremental infrastructure. All tooling exists. Security audits are automated (scripts at `/opt/wheeler-ecosystem/enforcement/`). Manual review adds ~30min per tenant per week for Enterprise tier.

### 4.5 Managed AI Routing

**What it is:** Access to LiteLLM proxy for centralized AI model management, key rotation, fallback routing, and usage tracking.

**Real infrastructure:** LiteLLM runs as PM2 process on AIOPS node (port 4049, 377MB RAM). Routes to Anthropic, OpenAI, DeepSeek. Currently serves 12 internal agent services.

**Service tiers:**

| Capability | Starter | Pro | Enterprise | Agency |
|-----------|---------|-----|-----------|--------|
| API key slots | -- | 1 model key | 5 model keys | 10 model keys |
| Models available | -- | DeepSeek only | Anthropic + OpenAI + DeepSeek | All models |
| Rate limiting | -- | 100 req/min | 1,000 req/min | 500 req/min per sub-tenant |
| Usage tracking | -- | Dashboard | Dashboard + export | Per sub-tenant |
| Custom models | -- | -- | Up to 3 custom endpoints | Up to 5 per sub-tenant |
| Fallback routing | -- | -- | Automatic on failure | Per sub-tenant |
| Key rotation | -- | -- | Automated monthly | Automated per sub-tenant |
| Cost allocation | -- | -- | Per-key billing export | Per sub-tenant billing |

**Pricing add-on (for Starter tier):** $50/mo for single model key access with 1,000 requests/month.

**Real costs:** Zero incremental infrastructure. LiteLLM already handles multi-tenant routing via header-based API key separation. Each additional tenant adds negligible CPU overhead (~0.1 vCPU per 1,000 requests/day).

### 4.6 Managed Self-Healing

**What it is:** Automated detection and remediation of common failure modes -- container crashes, PM2 process death, port binding drift, resource exhaustion.

**Real infrastructure:**
- Cron autoheal.sh (every 2 minutes): restarts stopped Docker containers, crashed PM2 processes
- wheeler-lockdown-watchdog.sh (every 5 minutes): verifies port bindings, restores lockdown
- Docker restart policies: `restart: unless-stopped` on all containers
- PM2 autorestart: all processes with `autorestart: true`, max 10 retries, 5s delay
- healthchecks self-healing: based on decision authority levels (0-3)

**Service tiers:**

| Capability | Starter | Pro | Enterprise | Agency |
|-----------|---------|-----|-----------|--------|
| Container auto-restart | -- | Included | Included | Per sub-tenant |
| PM2 auto-restart | -- | Included | Included | Per sub-tenant |
| Port bind restoration | -- | -- | Included | Per sub-tenant |
| Resource limit enforcement | -- | -- | Included | Per sub-tenant |
| Cascade diagnosis | -- | -- | Neo4j graph analysis | Per sub-tenant |
| Predictive healing | -- | -- | -- | -- (future) |
| Healing authority level | -- | Level 3 only | Level 2-3 | Level 2-3 per sub-tenant |

**Decision authority levels (as defined in architecture):**

| Level | Name | Description | Used For |
|-------|------|-------------|----------|
| 0 | Advisory | AI recommends, human decides | New failure patterns, destructive ops |
| 1 | Assisted | AI drafts plan, human approves, AI executes | Memory scaling, secret rotation |
| 2 | Supervised | AI executes, human reviews within 5min | Container restart, PM2 restart |
| 3 | Autonomous | AI executes, human informed afterward | Log rotation, cache flush, connection cleanup |

**Pro tenants:** Level 3 only (autonomous for safe operations).
**Enterprise tenants:** Levels 2-3 (supervised restart + autonomous cleanup).
**Agency tenants:** Configurable per sub-tenant.

**Real costs:** Self-healing scripts already run on cron. No incremental compute cost. Each healing event generates a Discord notification (existing webhook infrastructure).

### 4.7 Managed Compliance

**What it is:** Automated compliance reporting using the Wheeler QA scorecard methodology, adapted for tenant environments.

**Real infrastructure:** Reuses smoke-test-all.sh (8 sections), healthcheck infrastructure, and the 100-point QA scoring methodology (validated 100/100 for Wheeler ecosystem).

**Compliance domains scored (per tenant):**

| Domain | Weight | Source |
|--------|--------|--------|
| Container Health | 15% | Docker ps + healthcheck status |
| PM2 Status | 15% | PM2 jlist analysis |
| Port Security | 15% | ss -tlnp audit |
| UFW Compliance | 10% | UFW status parsing |
| cap_drop ALL | 10% | Docker inspect on all containers |
| Resource Limits | 10% | mem_limit + cpus verification |
| Secret Hygiene | 10% | PM2 jlist + compose file scan |
| Healthcheck Coverage | 10% | HEALTHCHECK definition audit |
| :latest Tag Hygiene | 5% | Docker image tag audit |

**Reports delivered:**
- Pro: Monthly scorecard (email PDF)
- Enterprise: Weekly scorecard + on-demand via API
- Agency: Per sub-tenant monthly, aggregated agency-wide monthly

**Real costs:** All audit scripts exist. Each full scan takes approximately 30 seconds. Reports are generated from existing data. Cost: negligible.

---

## 5. Multi-Tenant Architecture

### 5.1 Design Principles

1. **No new infrastructure for first 5 tenants.** All multi-tenancy is logical isolation within the existing stack.
2. **Label-based isolation in shared components** (Prometheus, Loki, Grafana).
3. **Process-level isolation for sensitive components** (separate PM2 or Docker for Enterprise tenants).
4. **All tenant traffic routes through shared Nginx** with per-tenant virtual hosts.
5. **No tenant can access another tenant's data** through any channel (API, dashboard, logs, metrics).
6. **Tenant provisioning must be automated** -- no manual config for standard onboarding.

### 5.2 Tenant Isolation Model

```
                        ┌─────────────────────────────────────┐
                        │       Shared Nginx Gateway          │
                        │  (rate-limited, basic auth option)  │
                        └──────────┬──────────────────────────┘
                                   │
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
          ▼                        ▼                        ▼
   ┌──────────────┐       ┌──────────────┐        ┌──────────────┐
   │  Tenant A    │       │  Tenant B    │        │  Tenant C    │
   │  vhost       │       │  vhost       │        │  vhost       │
   └──────┬───────┘       └──────┬───────┘        └──────┬───────┘
          │                      │                        │
          ▼                      ▼                        ▼
   ┌──────────────┐       ┌──────────────┐        ┌──────────────┐
   │ Shared Stack │       │ Shared Stack │        │ Dedicated    │
   │ (Starter/Pro)│       │ (Starter/Pro)│        │ Stack        │
   │              │       │              │        │ (Enterprise) │
   │ Prometheus   │       │ Prometheus   │        │ ┌──────────┐ │
   │   tenant_a   │       │   tenant_b   │        │ │Prometheus│ │
   │ Loki:        │       │ Loki:        │        │ │Grafana   │ │
   │   tenant=a   │       │   tenant=b   │        │ │Loki      │ │
   │ Grafana org  │       │ Grafana org  │        │ └──────────┘ │
   │   "Tenant A" │       │   "Tenant B" │        └──────────────┘
   └──────────────┘       └──────────────┘
```

### 5.3 Prometheus Multi-Tenancy

**Approach:** Label-based isolation with shared Prometheus server.

**Implementation:**
- Each tenant's scrape targets include `tenant_id="<uuid>"` label
- Prometheus alert rules include `tenant_id` in alert labels
- Alertmanager routes per `tenant_id` label value
- Grafana data source uses Prometheus with enforced `tenant_id` filter

**Configuration template:**

```yaml
# /opt/apps/monitoring/prometheus/tenant-scrape-configs/tenant_<id>.yml
scrape_configs:
  - job_name: 'tenant_<name>'
    scrape_interval: 30s
    metrics_path: /metrics
    static_configs:
      - targets: ['<tenant-target>:<port>']
        labels:
          tenant_id: '<uuid>'
          tenant_name: '<name>'
```

**Capacity:** Shared Prometheus on AIOPS (currently handling 30+ scrape targets) can handle approximately 50 additional targets before performance degrades (based on current memory usage of ~2 GB for Prometheus).

### 5.4 Loki Multi-Tenancy

**Approach:** Label-based isolation with shared Loki instance.

**Implementation:**
- All tenant log streams tagged with `tenant_id` label
- Promtail configures per-tenant scrape targets with label injection
- Grafana Loki data source uses label filter in log queries
- Loki retention configured per `tenant_id` via ruler

**Configuration template:**

```yaml
# Promtail scrape config per tenant
scrape_configs:
  - job_name: 'tenant_<name>_docker'
    static_configs:
      - targets: ['localhost']
        labels:
          job: 'tenant_docker_logs'
          tenant_id: '<uuid>'
          __path__: /var/lib/docker/containers/*/*-log.json
```

**Capacity:** Shared Loki on AIOPS (currently ~10 GB log storage) can support 5-8 additional tenants at Pro retention (90 days) before storage expansion needed.

### 5.5 Grafana Multi-Tenancy

**Approach:** Grafana Organization (org) separation.

**Implementation:**
- Each tenant gets a dedicated Grafana org
- Org has its own data sources (Prometheus with tenant filter, Loki with tenant filter)
- Pre-built dashboard set (20 templates) loaded per org
- Org admins can create custom dashboards within their org
- Tenant users cannot see other orgs

**Automated provisioning script (pseudocode):**

```bash
# Create tenant org
curl -X POST -H "Authorization: Bearer $GRAFANA_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Tenant <name>"}' \
  http://localhost:3002/api/orgs

# Create tenant API key for data source provisioning
curl -X POST -H "Authorization: Bearer $GRAFANA_ADMIN_TOKEN" \
  -d '{"name":"tenant-<id>-ds","role":"Editor"}' \
  http://localhost:3002/api/auth/keys

# Import dashboard templates
for dashboard in /opt/templates/dashboards/*.json; do
  curl -X POST -H "Authorization: Bearer $TENANT_API_KEY" \
    -H "Content-Type: application/json" \
    -d @"$dashboard" \
    http://localhost:3002/api/dashboards/db
done
```

### 5.6 LiteLLM Multi-Tenancy

**Approach:** Key-based routing with per-tenant API keys in shared LiteLLM.

**Implementation:**
- LiteLLM already supports virtual keys with budgets, rate limits, and metadata
- Each tenant gets a virtual key for LiteLLM
- Key has configurable:
  - Model access (which models the tenant can use)
  - Rate limit (requests per minute)
  - Budget (max spend per month)
  - Metadata (`tenant_id` for billing attribution)
- Usage logs exported per tenant for billing

**Configuration:**

```yaml
# litellm_config.yml (excerpt for multi-tenant)
general_settings:
  database_url: postgresql://litellm:${LITELLM_DB_PASSWORD}@localhost:5432/litellm

model_list:
  - model_name: deepseek-chat
    litellm_params:
      model: deepseek/deepseek-chat
      api_key: ${DEEPSEEK_API_KEY}

router_settings:
  routing_strategy: latency-based
  num_retries: 3
  fallbacks:
    - deepseek-chat: gpt-4o-mini
```

**Capacity:** LiteLLM at 377MB RAM can handle hundreds of keys with minimal overhead. Current instance serves 12 internal agents with no performance issues.

### 5.7 Usage Metering and Billing Integration

**Metered metrics (collected per tenant):**

| Metric | Collection Method | Billing Use |
|--------|-------------------|-------------|
| API calls to AI Ops API | Nginx access log parsing + Prometheus counter | Per-call billing ($0.01/call) |
| LiteLLM requests | LiteLLM usage logs | Per-model cost allocation |
| Metrics storage (GB) | Prometheus TSDB stats | Storage overage billing |
| Log storage (GB) | Loki index stats | Storage overage billing |
| Deployment count | Deployment engine audit log | Plan limit enforcement |
| Alert volume | Alertmanager metrics | Plan limit enforcement |
| Uptime check count | Uptime Kuma API | Plan limit enforcement |
| Active sub-tenants | Agency admin DB | Agency tier billing |

**Billing integration architecture:**

```
Tenant usage data (Prometheus/Loki/logs)
  → Usage aggregator script (runs daily)
    → Generates per-tenant usage report (JSON)
      → Stripe Metered Billing API
        → Invoice generated automatically
          → Tenant charged on billing cycle
```

**Stripe integration:**

```python
# stripe_billing.py (conceptual)
import stripe
import json

def report_usage(tenant_id, metric_name, quantity):
    """Report metered usage to Stripe."""
    stripe.SubscriptionItem.create_usage_record(
        subscription_item=tenant.subscription_item_id,
        quantity=quantity,
        timestamp=datetime.now(),
        action='increment',
    )

def generate_invoice(tenant):
    """Generate invoice for fixed + metered charges."""
    # Fixed plan charge
    stripe.InvoiceItem.create(
        customer=tenant.stripe_customer_id,
        amount=tenant.plan_price_cents,
        currency='usd',
        description=f"{tenant.plan_name} - {tenant.billing_period}",
    )
    # Metered charges
    for metric in tenant.metered_usage:
        if metric['overage'] > 0:
            stripe.InvoiceItem.create(
                customer=tenant.stripe_customer_id,
                amount=metric['overage'] * metric['unit_price_cents'],
                currency='usd',
                description=f"{metric['name']} overage: {metric['overage']} units",
            )
    # Finalize and send
    stripe.Invoice.finalize_invoice(
        stripe.Invoice.create(customer=tenant.stripe_customer_id)
    )
```

### 5.8 Tenant Provisioning Automation

**Provisioning flow (automated):**

```
1. Tenant signs up via portal (or API)
2. System generates tenant_id (UUID v4)
3. System assigns tenant to capacity pool (AIOPS node)
4. Provisioning script executes:
   a. Creates tenant directory: /opt/tenants/<tenant_id>/
   b. Generates .env with tenant-specific secrets
   c. Creates Prometheus scrape config
   d. Creates Grafana org + data sources + dashboards
   e. Creates Loki tenant label config
   f. Creates Alertmanager route
   g. Creates Nginx vhost for tenant subdomain (if applicable)
   h. Provisions LiteLLM virtual key (if Pro or above)
   i. Creates Stripe customer + subscription
   j. Sends welcome email with credentials
5. Health check: smoke test on tenant stack
6. Send onboarding instructions
```

**Provisioning time target:** < 10 minutes for Starter, < 30 minutes for Pro (automated). Enterprise and Agency include human review (4h SLA for provisioning).

**Provisioning script locations (new scripts, to be created):**

| Script | Purpose | Location |
|--------|---------|----------|
| `provision-tenant.sh` | Full tenant provisioning orchestrator | `/opt/aiops-saas/provision-tenant.sh` |
| `deprovision-tenant.sh` | Full tenant removal | `/opt/aiops-saas/deprovision-tenant.sh` |
| `meter-usage.sh` | Daily usage collection for billing | `/opt/aiops-saas/meter-usage.sh` |
| `tenant-health-check.sh` | Per-tenant health verification | `/opt/aiops-saas/tenant-health-check.sh` |

---

## 6. Packaging and Deployment Options

### 6.1 White-Label Deployment (Agency Tier)

**What the agency sees:**
- Admin portal branded as their product (logo, colors, domain)
- All sub-tenants listed with health status, usage, billing
- Sub-tenant onboarding via agency's own signup flow
- API for sub-tenant management

**What sub-tenants see:**
- Agency's branding throughout (Grafana org named after agency, emails from agency domain)
- No Wheeler AI Ops references anywhere
- Custom subdomain (e.g., `tenant.agencyplatform.com`)
- Agency's own support contact

**Implementation:**
- Nginx templates with variable substitution for brand values
- Grafana org name and logo configurable per agency
- Email templates with agency branding
- Stripe Connect for agency to bill their own sub-tenants (optional)
- All Wheeler references removed from UI by default

**Operational model:**
- Wheeler manages infrastructure and platform
- Agency manages their sub-tenants (onboarding, support, billing)
- Agency pays Wheeler $3,999/mo flat + $199/mo per sub-tenant over 5
- Agency sets their own pricing to sub-tenants (typical markup: 2-3x)

### 6.2 On-Premise Deployment Option

**What it is:** Deploy the AI Ops platform on the customer's own servers.

**Available for:** Enterprise and Agency tiers (add $500/mo to base price).

**Delivery:**
- Ansible playbook for server setup (UFW, Docker, Nginx, Tailscale)
- Docker compose stacks for monitoring, AI routing, deployment engine
- PM2 ecosystem configs for agent services
- Configuration templates with customer's branding
- SSH key-based remote management (optional, customer can deny)

**Included support for on-premise:**
- Initial setup: 1-day remote session
- Quarterly upgrades: Ansible playbook execution
- Monitoring: Customer can opt-in to remote health monitoring via Tailscale
- Troubleshooting: Remote SSH with customer approval

**Customer requirements:**
- Minimum 8 vCPU, 16 GB RAM, 100 GB SSD per node
- Ubuntu 22.04 or 24.04 LTS
- Docker Engine 24+
- Root SSH access (during setup only)
- Port 443 open for public services (or internal network)

**Wheeler operational burden for on-premise:**
- Setup: 8h per deployment (billable as one-time $2,500 setup fee)
- Monthly maintenance: 2h per deployment per month
- Upgrade cycles: 4h per quarter

### 6.3 Cloud Deployment Templates

**Supported cloud providers:**
- Hetzner Cloud (primary, aligns with existing infrastructure)
- AWS (EC2 + EBS)
- DigitalOcean (Droplets)

**Template contents:**
- Terraform/OpenTofu scripts for infrastructure provisioning
- Ansible playbooks for configuration management
- Docker compose files for service stacks
- Environment variable templates

**Available for:**
- Pro tier: Basic templates (Hetzner only, single-node)
- Enterprise tier: Full templates (all providers, multi-node)
- Agency tier: Full templates with multi-tenant configuration

### 6.4 Migration Service

**What it is:** Professional service to migrate customers from existing monitoring solutions to Wheeler AI Ops.

**Pricing:** One-time fee based on complexity.

| Migration Type | Price | Timeline | Effort |
|---------------|-------|----------|--------|
| Prometheus to managed Prometheus | $500 | 1 day | 4h |
| Grafana dashboard migration | $200 per 5 dashboards | 1 day | 2h |
| Nagios/Zabbix to Prometheus | $1,000 | 2 days | 8h |
| Datadog to self-hosted (cost reduction) | $2,500 | 3 days | 16h |
| Full infrastructure migration | $5,000 | 1 week | 40h |
| Multi-server onboarding | $1,000 per server | 2 weeks | 20h |

**Real case study (for sales materials):** Wheeler AI Ops migrated FRG Nationwide from Hostinger to AIOPS node, reducing monthly hosting cost from approximately $150/mo (Hostinger VPS + services) to zero incremental cost (absorbed into existing Hetzner node), while improving QA score from unknown to 100/100 and reducing attack surface by eliminating 95 UFW rules and 8 public admin panels.

---

## 7. Implementation Plan

### 7.1 Phase 1: Foundation (Weeks 1-2)

**Objective:** Build multi-tenant infrastructure on existing stack. No new hardware.

| Step | Task | Owner | Duration | Dependencies |
|------|------|-------|----------|-------------|
| 1.1 | Implement Prometheus tenant label isolation | Infrastructure | 1 day | None |
| 1.2 | Implement Loki tenant label isolation | Infrastructure | 1 day | None |
| 1.3 | Configure Grafana org provisioning automation | Infrastructure | 2 days | 1.1, 1.2 |
| 1.4 | Build tenant provisioning script | DevOps | 3 days | 1.3 |
| 1.5 | Build tenant deprovisioning script | DevOps | 1 day | 1.4 |
| 1.6 | Implement LiteLLM virtual key provisioning | DevOps | 1 day | None |
| 1.7 | Create Alertmanager route templates per tenant | Infrastructure | 1 day | 1.1 |
| 1.8 | Build Nginx vhost template for tenant subdomains | Infrastructure | 1 day | None |
| 1.9 | Create dashboard template set (20 dashboards) | DevOps | 3 days | 1.3 |
| 1.10 | Test full provisioning pipeline end-to-end | QA | 2 days | 1.4-1.9 |

**Deliverables:**
- Automated tenant provisioning for Starter and Pro tiers
- Working multi-tenant monitoring stack with data isolation
- Provisioning script at `/opt/aiops-saas/provision-tenant.sh`
- Dashboard templates at `/opt/aiops-saas/templates/dashboards/`

### 7.2 Phase 2: Billing and Portal (Weeks 3-4)

**Objective:** Build customer-facing portal, Stripe billing integration, and usage metering.

| Step | Task | Owner | Duration | Dependencies |
|------|------|-------|----------|-------------|
| 2.1 | Set up Stripe Connect account + product catalog | Ops | 1 day | None |
| 2.2 | Build usage metering script | DevOps | 2 days | Phase 1 complete |
| 2.3 | Build billing sync (usage to Stripe) | DevOps | 2 days | 2.1, 2.2 |
| 2.4 | Build customer portal web UI (signup, dashboard, billing) | Dev | 5 days | 2.1 |
| 2.5 | Build tenant admin dashboard (for internal ops) | Dev | 2 days | Phase 1 complete |
| 2.6 | Implement API endpoints for AI Ops API tier | DevOps | 3 days | Phase 1 complete |
| 2.7 | Create API key management for tenants | DevOps | 1 day | 2.6 |
| 2.8 | Implement rate limiting per tenant API key | Infrastructure | 1 day | 2.7 |
| 2.9 | Write tenant onboarding documentation | Docs | 2 days | None |
| 2.10 | Test billing pipeline with edge cases | QA | 2 days | 2.1-2.8 |

**Deliverables:**
- Customer portal web app
- Automated Stripe billing integration
- AI Ops API endpoints operational
- Usage metering and reporting
- API documentation

### 7.3 Phase 3: Enterprise and Agency (Weeks 5-6)

**Objective:** Build Enterprise dedicated stack provisioning, Agency white-label system, and on-premise deployment scripts.

| Step | Task | Owner | Duration | Dependencies |
|------|------|-------|----------|-------------|
| 3.1 | Build dedicated stack provisioning (Enterprise) | Infrastructure | 3 days | Phase 1 complete |
| 3.2 | Implement white-label branding system | DevOps | 2 days | Phase 2.4 (portal) |
| 3.3 | Build agency admin dashboard | Dev | 3 days | Phase 2.5 |
| 3.4 | Implement sub-tenant management API | DevOps | 2 days | Phase 1.4, 3.3 |
| 3.5 | Create on-premise Ansible playbooks | Infrastructure | 4 days | None |
| 3.6 | Build Terraform/OpenTofu templates | Infrastructure | 3 days | 3.5 |
| 3.7 | Implement compliance report generation | DevOps | 2 days | Phase 1 complete |
| 3.8 | Build SLA monitoring and reporting | Infrastructure | 2 days | Phase 1.3 |
| 3.9 | Create migration service toolkit | DevOps | 3 days | 3.5 |
| 3.10 | End-to-end testing all tiers | QA | 3 days | 3.1-3.9 |

**Deliverables:**
- Enterprise dedicated stack provisioning
- White-label system for Agency tier
- Agency admin dashboard with sub-tenant management
- On-premise deployment playbooks
- Cloud deployment templates (Terraform)
- Compliance reporting engine
- SLA monitoring system
- Migration toolkit

### 7.4 Phase 4: Scale (Month 2+)

**Objective:** Add capacity, optimize, and expand.

| Step | Task | Owner | Duration | Dependencies |
|------|------|-------|----------|-------------|
| 4.1 | Add Hetzner CX52 for Agency capacity | Ops | 2 days (procure + setup) | Phase 3 economic validation |
| 4.2 | Implement read replicas for tenant databases | Infrastructure | 3 days | 4.1 |
| 4.3 | Optimize Prometheus retention for storage | Infrastructure | 1 day | None |
| 4.4 | Build self-service dashboard for tenants | Dev | 5 days | Phase 2.4 |
| 4.5 | Add SSO/SAML authentication | DevOps | 3 days | Phase 2.4 |
| 4.6 | Implement advanced alert correlation | Infrastructure | 3 days | None |
| 4.7 | Build predictive scaling (auto-add capacity) | DevOps | 5 days | 4.1 |
| 4.8 | Launch referral/partner program | Ops | 2 days | None |
| 4.9 | Public pricing page + documentation site | Ops | 3 days | Phase 2 complete |

### 7.5 Resource Requirements

**Internal effort to build (all phases):**

| Role | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Total |
|------|---------|---------|---------|---------|-------|
| Infrastructure Engineer | 80h | 40h | 80h | 40h | 240h |
| DevOps Engineer | 40h | 80h | 60h | 40h | 220h |
| Full-Stack Developer | 0h | 100h | 60h | 80h | 240h |
| QA/Testing | 40h | 20h | 40h | 20h | 120h |
| Operations/Billing | 0h | 40h | 20h | 40h | 100h |
| **Total** | **160h** | **280h** | **260h** | **220h** | **920h** |

**Ongoing operations (post-launch, per month):**

| Activity | Hours/mo | Notes |
|----------|----------|-------|
| Tenant provisioning/deprovisioning | 5h | Mostly automated |
| Billing support | 10h | Invoicing, disputes, metering |
| Customer support (Starter/Pro) | 20h | ~1h per tenant per week at 5 tenants |
| Customer support (Enterprise/Agency) | 30h | Higher touch |
| Infrastructure maintenance | 20h | Upgrades, patches, capacity mgmt |
| Compliance report generation | 5h | Automated, review time only |
| **Total monthly ops** | **90h** | At 5-8 tenants |

---

## 8. Billing and Pricing Model

### 8.1 Pricing Summary

| Tier | Monthly | Annual (per month) | Annual (total) | Setup Fee |
|------|---------|-------------------|----------------|-----------|
| Starter | $99 | $82.50 | $990 | $0 |
| Pro | $499 | $416 | $4,990 | $0 |
| Enterprise | $1,999 | $1,666 | $19,990 | $2,500 |
| Agency | $3,999 | $3,333 | $39,990 | $5,000 |
| API | $0.01/call | -- | -- | $0 |

### 8.2 Add-On Pricing

| Add-On | Price | Available On |
|--------|-------|-------------|
| Additional Grafana org (extra team within tenant) | $49/mo | Pro, Enterprise |
| Extra 10 uptime checks (block of 10) | $19/mo | Starter, Pro |
| Extra 7 days metrics retention | $29/mo per 7 days | Pro |
| Extra 30 days log retention | $49/mo per 30 days | Pro |
| LiteLLM AI routing (for Starter) | $50/mo | Starter |
| Rollback engine (for Starter) | $50/mo | Starter |
| On-premise deployment | +$500/mo | Enterprise, Agency |
| Extra sub-tenant slot (over 5) | $199/mo | Agency |
| Migration service (per project) | $500-$5,000 one-time | Any |
| Dedicated support engineer | $1,000/mo | Enterprise |
| SSO/SAML (for Pro) | $99/mo | Pro |
| Multi-server (extra node) | $199/mo per node | Pro, Enterprise |

### 8.3 Usage-Based Overage Pricing

| Metric | Included (Pro) | Overage Rate |
|--------|---------------|--------------|
| AI Ops API calls | N/A (API tier only) | $0.01/call |
| LiteLLM requests (Pro) | 10,000/mo | $0.001/request |
| Prometheus metrics targets (Pro) | 25 targets | $5/target/mo |
| Loki log ingest (Pro) | 5 GB/mo | $2/GB/mo |
| Deployment engine calls (Pro) | 10/mo | $25/deploy |
| Alert notifications (Pro) | 500/mo | $0.05/alert |
| Uptime Kuma checks (Pro) | 25 | $2/check/mo |

### 8.4 Grandfather and Discount Policy

| Condition | Discount |
|-----------|----------|
| Annual prepayment | 17% off (2 months free per year) |
| Nonprofit / open source | 50% off (Starter and Pro only) |
| Referral (credited to referrer) | 1 month free for each referral |
| Beta participants (first 10 tenants) | 50% off for 6 months |
| Migration from Datadog/NewRelic (show bill) | Match first month savings |
| Multi-year commitment (2+ years) | 20% off |

### 8.5 Payment Terms

| Term | Starter | Pro | Enterprise | Agency |
|------|---------|-----|-----------|--------|
| Payment method | Credit card | Credit card | Invoice + ACH | Invoice + ACH |
| Billing period | Monthly or annual | Monthly or annual | Monthly or annual | Monthly or annual |
| Due date | Upon invoice | Upon invoice | Net 15 | Net 15 |
| Late fee | 5% after 15 days | 5% after 15 days | 1.5%/mo | 1.5%/mo |
| Minimum commitment | None | None | 3 months | 6 months |
| Cancellation | Anytime | Anytime | 30 days notice | 60 days notice |

---

## 9. SLA Framework

### 9.1 Service Level Objectives

| Component | Pro | Enterprise | Agency |
|-----------|:---:|:----------:|:------:|
| Monitoring stack uptime | 99.0% | 99.5% | 99.5% |
| AI routing (LiteLLM) uptime | 99.0% | 99.5% | 99.5% |
| API availability | 99.0% | 99.9% | 99.9% |
| Deployment engine availability | Best effort | 99.5% | 99.5% |
| Alert delivery latency (P0) | <5 min | <2 min | <2 min |
| Log ingestion latency (P95) | <60s | <30s | <30s |
| Metrics scrape interval | 60s | 30s | 30s |
| Dashboard load time (P95) | <5s | <3s | <3s |

**Starter tier:** No SLA. "Best effort" availability. This is intentional -- the lower price reflects lower operational guarantee.

### 9.2 Incident Response Times

| Priority | Definition | Pro Response | Enterprise Response | Agency Response |
|----------|-----------|:-----------:|:------------------:|:--------------:|
| P0 | Complete monitoring outage for tenant | 2h | 30min | 15min |
| P1 | Partial monitoring degradation | 8h | 2h | 1h |
| P2 | Minor feature impairment | 24h | 8h | 4h |
| P3 | Cosmetic/non-urgent | 48h | 24h | 12h |

### 9.3 SLA Credits

| Uptime (monthly) | Credit (% of monthly fee) |
|-----------------|--------------------------|
| < 99.5% (Enterprise) / < 99.0% (Pro) | 5% |
| < 99.0% (Enterprise) / < 98.0% (Pro) | 10% |
| < 95.0% | 25% |
| < 90.0% | 50% (or 1 month free) |

**Credit cap:** Maximum 50% of monthly fee per month. No cumulative credits.
**Credit request:** Must be submitted within 7 days of the month end.

### 9.4 Maintenance Windows

| Type | Frequency | Duration | Notice | Downtime |
|------|-----------|----------|--------|----------|
| Security patches | As needed | < 30min | 48h | Brief restart |
| Minor upgrades | Monthly | < 1h | 7 days | < 5min |
| Major upgrades | Quarterly | < 4h | 14 days | < 30min |
| Emergency fixes | As needed | As needed | As soon as possible | As needed |

**Scheduled maintenance does not count against SLA uptime.**

---

## 10. Go-to-Market Strategy

### 10.1 Target Customer Profiles

**ICP 1: Technical Startup (Starter)**
- 1-10 employees
- Running on a single VPS or small cloud
- Needs basic monitoring but cannot afford Datadog ($15+/host/month)
- Technical founder who can self-serve setup
- Pain point: Outgrew free tier monitoring, needs structured health checks
- Decision trigger: First production outage they could not detect

**ICP 2: Growth SaaS (Pro)**
- 10-50 employees
- 5-20 servers, multiple environments
- Has outgrown basic monitoring
- Needs deployment automation and rollback safety
- Pain point: Manual deployments causing downtime, no rollback capability
- Decision trigger: Failed deployment that took hours to recover

**ICP 3: Compliance-Sensitive Business (Enterprise)**
- 50-200 employees
- SOC2, HIPAA, or PCI compliance requirements
- Needs audit trails, compliance reporting
- Pain point: Existing monitoring lacks compliance features
- Decision trigger: Auditor finding about monitoring gaps

**ICP 4: MSP / DevOps Agency (Agency)**
- 5-50 clients
- Needs white-label monitoring platform
- Currently reselling Datadog/Grafana Cloud at thin margins
- Pain point: Cannot differentiate on monitoring, margins too thin
- Decision trigger: Client asks for white-label dashboard

**ICP 5: Developer / Platform (API)**
- Building internal tools or customer-facing dashboards
- Needs infrastructure intelligence data
- Pain point: Building monitoring from scratch is expensive
- Decision trigger: Prototype needs health check data

### 10.2 Positioning

**Against Datadog:**
- Datadog: $15/host/month + $5/log/GB + $7/metric -- a 10-server setup with moderate logging costs $300-500/mo
- Wheeler AI Ops Pro: $499/mo flat (unlimited hosts on tenant node)
- Messaging: "Flat-rate AI operations, not per-host surprise bills"

**Against Grafana Cloud:**
- Grafana Cloud: Free tier is limited, $49/mo for 3 users, scales quickly
- Wheeler AI Ops: Includes deployment engine, rollback, AI routing -- Grafana Cloud does not have these
- Messaging: "Observability + deployment + AI routing -- three products, one price"

**Against self-built:**
- Cost of engineering time to build equivalent stack: 2-4 months of senior DevOps salary ($30K-$60K)
- Wheeler AI Ops: $499/mo, operational immediately
- Messaging: "Stop building ops tools. Start using them."

### 10.3 Channel Strategy

**Direct sales:**
- Wheeler website with self-serve signup (Starter, Pro, API)
- Interactive demo showing live monitoring stack
- Case study: "How Wheeler AI Ops runs 41 containers on $185/mo infrastructure"

**Partner channels:**
- DevOps consultancies as Agency tier resellers
- Cloud provider marketplaces (Hetzner Cloud marketplace, AWS Marketplace)
- Referral program: 20% of first 6 months for referring customer

**Content marketing:**
- Open source the tenant provisioning scripts (attract developers)
- Blog series: "Building Zero-Trust AI Infrastructure" (proven methodology)
- Benchmark posts: Prometheus vs. Datadog cost comparison real numbers
- Performance benchmarks from actual 3-node Hetzner deployment

### 10.4 Sales Materials Needed

| Asset | Type | Phase |
|-------|------|-------|
| Pricing page | Web | Phase 2 |
| Product demo video | Video | Phase 2 |
| Interactive sandbox | Web app | Phase 2 |
| Comparison sheet (vs Datadog, Grafana Cloud) | PDF | Phase 2 |
| Case study: internal Wheeler deployment | PDF | Phase 2 |
| Technical architecture overview | PDF | Phase 2 |
| Compliance & security white paper | PDF | Phase 2 |
| Agency partner deck | PDF | Phase 3 |
| On-premise deployment guide | PDF | Phase 3 |
| Migration from X guide (Datadog, Nagios, etc.) | PDF | Phase 3 |

---

## 11. Financial Projections

### 11.1 Revenue Scenarios

**Conservative (5 tenants by month 6):**

| Month | Starter | Pro | Enterprise | Agency | API | MRR |
|-------|---------|-----|-----------|-------|-----|-----|
| 1 | 0 | 0 | 0 | 0 | 0 | $0 |
| 2 | 2 | 0 | 0 | 0 | 0 | $198 |
| 3 | 3 | 0 | 0 | 0 | 0 | $297 |
| 4 | 3 | 1 | 0 | 0 | 0 | $796 |
| 5 | 3 | 1 | 0 | 0 | ~$40 | $836 |
| 6 | 3 | 2 | 0 | 0 | ~$60 | $1,157 |

**Moderate (10 tenants by month 6):**

| Month | Starter | Pro | Enterprise | Agency | API | MRR |
|-------|---------|-----|-----------|-------|-----|-----|
| 1 | 2 | 0 | 0 | 0 | 0 | $198 |
| 2 | 5 | 1 | 0 | 0 | ~$20 | $1,014 |
| 3 | 3 | 3 | 0 | 0 | ~$40 | $1,794 |
| 4 | 3 | 4 | 1 | 0 | ~$60 | $4,252 |
| 5 | 3 | 4 | 1 | 0 | ~$100 | $4,292 |
| 6 | 5 | 5 | 1 | 0 | ~$150 | $5,794 |

**Aggressive (with Agency tier + hardware expansion by month 6):**

| Month | Starter | Pro | Enterprise | Agency | API | MRR |
|-------|---------|-----|-----------|-------|-----|-----|
| 1 | 3 | 1 | 0 | 0 | ~$20 | $816 |
| 2 | 5 | 3 | 0 | 0 | ~$50 | $2,046 |
| 3 | 5 | 5 | 0 | 0 | ~$100 | $3,544 |
| 4 | 5 | 5 | 1 | 1 | ~$150 | $10,143 |
| 5 | 5 | 5 | 1 | 1 | ~$200 | $10,193 |
| 6 | 5 | 5 | 2 | 1 | ~$300 | $14,191 |

### 11.2 Cost Structure (Monthly)

| Cost Item | Fixed | Variable (per tenant) | Notes |
|-----------|-------|----------------------|-------|
| Hetzner CPX51 x2 | $170 | $0 | Core nodes |
| Hostinger VPS | $15 | $0 | Edge/legacy |
| Hetzner CX52 (Agency expansion) | $115 | $0 | Added in Phase 4 if needed |
| Domain/DNS | $15 | $3 | Per-tenant subdomain |
| Stripe processing fees | $0 | 2.9% + $0.30/transaction | Variable |
| Tailscale Team plan | $48 | $0 | If >3 users |
| **Total** | **$200-$363** | **~$3 + 2.9%** | |

### 11.3 Unit Economics

| Metric | Starter | Pro | Enterprise | Agency |
|--------|---------|-----|-----------|-------|
| Monthly price | $99 | $499 | $1,999 | $3,999 |
| Infrastructure cost (est) | $15 | $35 | $120 | $250 |
| Support cost (est) | $25 | $75 | $300 | $500 |
| Platform overhead (allocated) | $10 | $10 | $10 | $50 |
| **Gross margin** | **~50%** | **~76%** | **~78%** | **~80%** |
| Customer acquisition cost (est) | $200 | $750 | $2,500 | $3,000 |
| Payback period | 2 months | 1.5 months | 1.25 months | <1 month |
| Lifetime value (12mo avg) | $1,188 | $5,988 | $23,988 | $47,988 |
| LTV:CAC ratio | 5.9:1 | 8:1 | 9.6:1 | 16:1 |

### 11.4 Break-Even Timeline

| Scenario | Monthly Cost | Break-Even MRR | Est. Month | Cumulative Investment |
|----------|-------------|----------------|------------|----------------------|
| Conservative | $200 | $200 | Month 3 | $600 (build) + $600 (ops) = $1,200 |
| Moderate | $200 | $200 | Month 2 | $400 (build) + $400 (ops) = $800 |
| Aggressive | $315* | $315 | Month 2 | $630 (build) + $630 (ops) = $1,260 |

*Includes CX52 for Agency capacity.

**Build cost (one-time):** Internal labor at $50/h fully loaded:
- Phase 1-3: 700h x $50 = $35,000 (opportunity cost of internal team time)
- Total cash outlay: near-zero (no new software, no new hardware for first 5 tenants)
- Real cost: diverted engineering time from other Wheeler projects

### 11.5 12-Month Projection (Moderate Scenario)

| Metric | Month 1 | Month 3 | Month 6 | Month 12 |
|--------|---------|---------|---------|----------|
| Tenants | 2 | 6 | 10 | 18 |
| MRR | $198 | $1,794 | $5,794 | $15,000+ |
| ARR | $2,376 | $21,528 | $69,528 | $180,000+ |
| Infrastructure cost | $200 | $200 | $315* | $430** |
| Gross margin | ~0% | ~89% | ~95% | ~97% |
| Cumulative revenue | $198 | $3,786 | $18,368 | $95,000+ |

*Adding CX52 at month 4-5 for Agency/Enterprise capacity
**Adding second CX52 or upgrading to CPX61 at month 10-12

---

## 12. Risks and Mitigations

### 12.1 Technical Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Shared Prometheus crashes under tenant load | All tenants lose monitoring | Low | Implement resource limits, Prometheus federation for scale |
| Loki storage fills up with tenant logs | Log loss, potential disk full | Medium | Enforce per-tenant retention limits, separate storage volumes |
| Tenant isolation breach (cross-tenant data access) | Catastrophic trust loss | Very Low | Regular isolation testing, Grafana org boundary audits |
| LiteLLM becomes bottleneck for all tenants | All AI routing degraded | Low | Implement LiteLLM load balancing, add standby instance |
| Provisioning script fails mid-tenant-creation | Orphaned resources | Medium | Implement idempotent provisioning, rollback on failure |
| Nginx config error affects all tenants | All tenants lose access | Medium | CI/CD gate for nginx config test, canary deployment |

### 12.2 Business Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Insufficient tenant demand | Wasted build time | Medium | Validate with 3 pre-sale commitments before full build |
| Tenant churn > 10%/mo | Never reaches break-even | Medium | Annual contracts for Enterprise/Agency, high switching costs |
| Price undercut by Grafana Cloud/Datadog | Lost deals | Medium | Compete on bundled value (monitoring + deploy + AI), not price |
| Support burden exceeds capacity | Degraded service | High (at scale) | Self-serve first, then chat, automation for common issues |
| Hetzner datacenter outage | All tenants affected | Low | Cross-region backup (Hetzner Nuremberg + Falkenstein) |
| Cannot hire/support ops team | Cannot scale | Medium | Keep lean, automate everything, limit tenants to capacity |

### 12.3 Capacity Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Single node failure loses multiple tenants | Partial outage | COREDB as database failover, backups, documented recovery |
| Prometheus data loss on disk full | Historical metrics lost | Separate disk partitions per tenant, alerts at 80% disk |
| All 14 tenants on Starter max out AIOPS RAM | Performance degradation | Hard tenant cap at 8 Starter tenants, enforce resource limits |
| Agency with 10 sub-tenants exceeds capacity | Must add hardware | Clearly communicated limit, pre-provision CX52 before committing |

### 12.4 Go-to-Market Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Tenants cannot self-serve onboarding | High support load | Medium | Detailed documentation, interactive onboarding wizard |
| Enterprise sales cycle too long (3+ months) | Cash flow gap | High | Focus on Pro self-serve first, Enterprise as expansion revenue |
| Agency partners demand customization | Scope creep | High | Clear product boundaries, custom development at $200/h |
| API tier usage spikes cause cost imbalance | Unprofitable customers | Medium | Hard rate limits, budget caps, notify at 80% of threshold |

---

## Appendix A: Infrastructure Mapping -- Service to Revenue Tier

| Existing Service | Port | Used In Tier(s) | Purpose |
|-----------------|------|---------------|---------|
| aiops-grafana | 3002 | All | Tenant dashboards (org separation) |
| aiops-prometheus | 9090 | All | Tenant metrics (label isolation) |
| aiops-loki | 3100 | All | Tenant logs (label isolation) |
| aiops-alertmanager | 9093 | All | Tenant alerts (route separation) |
| aiops-pushgateway | 9092 | Pro+ | Batch metric pushes |
| aiops-webhook-relay | 8085 | All | Discord/Slack alert delivery |
| uptime-kuma | 3001 | All | External uptime monitoring |
| netdata | 19999 | Enterprise+ | Real-time system monitoring |
| healthchecks | 3130 | Pro+ | Cron job monitoring |
| nginx gateway | 443 | All | Tenant routing, rate limiting |
| litellm | 4049 | Pro+ | AI routing (virtual keys) |
| deployment-engine | (scripts) | Pro+ | Tenant deployment automation |
| rollback-engine | (scripts) | Pro+ | Tenant rollback automation |
| smoke-test-all.sh | (script) | Enterprise+ | Tenant health verification |
| promtail | (docker-run) | Pro+ | Tenant log shipping |
| node_exporter | 9100 | Enterprise+ | System metrics |
| ecosystem-guardian | PM2 | Internal | Cross-tenant state monitoring |
| command-center | 8100 | Internal | Tenant provisioning API |
| event-bus-relay | PM2 | Internal | Tenant event routing |

---

## Appendix B: New Infrastructure Required

| Component | Purpose | Created In | Resource Impact |
|-----------|---------|-----------|----------------|
| `/opt/aiops-saas/provision-tenant.sh` | Tenant provisioning | Phase 1 | None (script) |
| `/opt/aiops-saas/deprovision-tenant.sh` | Tenant removal | Phase 1 | None (script) |
| `/opt/aiops-saas/meter-usage.sh` | Usage metering | Phase 2 | None (script) |
| `/opt/aiops-saas/templates/dashboards/` | Dashboard library | Phase 1 | ~50 MB (JSON files) |
| `/opt/aiops-saas/portal/` | Customer portal web app | Phase 2 | ~500 MB (Node.js app) |
| `/opt/aiops-saas/billing/` | Billing integration | Phase 2 | ~200 MB (Python app) |
| `/opt/aiops-saas/playbooks/` | On-premise Ansible | Phase 3 | None (YAML files) |
| `/opt/aiops-saas/terraform/` | Cloud templates | Phase 3 | None (HCL files) |
| Tenant DB in COREDB PostgreSQL | Tenant metadata | Phase 1 | < 1 GB |
| Tenant metrics volume (Prometheus) | Per-tenant metrics | Per tenant | ~2 GB per Pro tenant per 90 days |
| Tenant logs volume (Loki) | Per-tenant logs | Per tenant | ~5 GB per Pro tenant per 90 days |

---

## Appendix C: Tenant Onboarding Checklist

**Customer:**
- [ ] Sign up via portal (or API)
- [ ] Select tier (Starter/Pro/Enterprise/Agency/API)
- [ ] Provide monitoring targets (URLs, IPs, ports)
- [ ] Provide webhook URLs for alerts (Slack, Discord, PagerDuty)
- [ ] Configure basic auth credentials (if using Nginx gateway)
- [ ] Provide LLM API keys (if using LiteLLM AI routing)
- [ ] Review and accept SLA terms
- [ ] Complete billing setup (credit card or ACH)
- [ ] Receive welcome email with credentials

**Internal:**
- [ ] Run provision-tenant.sh
- [ ] Verify tenant monitoring data visible in Grafana
- [ ] Verify tenant can access their dashboard
- [ ] Configure alert rules for tenant
- [ ] Test alert delivery (send test alert)
- [ ] Add tenant to internal support system
- [ ] Schedule onboarding call (Pro+) or send self-serve guide (Starter)
- [ ] Document tenant in internal tenant registry

**Post-onboarding (within 48h):**
- [ ] Review first 24h of monitoring data
- [ ] Adjust alert thresholds if needed
- [ ] Confirm tenant is satisfied with setup
- [ ] Enable billing (trial period ends)

---

## Appendix D: API Tier Endpoint Specifications

**Base URL:** `https://api.aiops.wheeler.claw.engineer/v1`

**Authentication:** Bearer token in `Authorization` header. Tokens generated per tenant.

### Endpoint: Health Check
```
GET /v1/health/{target}
  Headers: Authorization: Bearer <token>
  Response: {
    "status": "healthy" | "degraded" | "down",
    "http_status": 200,
    "response_time_ms": 145,
    "checked_at": "2026-05-24T12:00:00Z",
    "body_contains_errors": false
  }
  Pricing: $0.01/call
  Rate limit: 60/min
```

### Endpoint: Metrics
```
GET /v1/metrics/{target}
  Headers: Authorization: Bearer <token>
  Query: ?metric=cpu_usage&range=1h
  Response: {
    "target": "app.example.com",
    "metric": "cpu_usage",
    "data_points": [
      {"timestamp": "...", "value": 45.2},
      ...
    ]
  }
  Pricing: $0.01/call
  Rate limit: 30/min
```

### Endpoint: Deploy
```
POST /v1/deploy
  Headers: Authorization: Bearer <token>
  Body: {
    "service_type": "docker" | "pm2",
    "service_name": "my-app",
    "config_path": "/opt/tenants/<id>/my-app/docker-compose.yml"
  }
  Response: {
    "deploy_id": "dep_abc123",
    "status": "in_progress",
    "gates_passed": ["state", "deps", "resources", "config", "secrets"],
    "estimated_completion_s": 45
  }
  Pricing: $0.01/call
  Rate limit: 5/min
```

### Endpoint: AI Route
```
POST /v1/ai/route
  Headers: Authorization: Bearer <token>
  Body: {
    "model": "deepseek-chat",
    "messages": [{"role": "user", "content": "..."}],
    "temperature": 0.7
  }
  Response: {
    "model_used": "deepseek-chat",
    "content": "...",
    "usage": {"prompt_tokens": 50, "completion_tokens": 100},
    "latency_ms": 1200
  }
  Pricing: $0.01/call (excludes LLM API cost, billed separately)
  Rate limit: 100/min
```

---

## Appendix E: Comparison to Existing Monitoring SaaS

| Feature | Datadog (10 hosts) | Grafana Cloud (Pro) | Wheeler AI Ops Pro |
|---------|-------------------|--------------------|--------------------|
| Infrastructure monitoring | $150/mo (10 hosts x $15) | $69/mo (10 hosts) | Included |
| Log management (5 GB) | $50/mo ($10/GB) | $36/mo ($7/GB) | Included (up to 5 GB) |
| APM | $310/mo (10 hosts x $31) | Not included | -- (not offered yet) |
| Synthetic monitoring (10 checks) | $50/mo ($5/check) | Included (10k checks) | Included (25 checks) |
| Alerting | Included | Included | Included |
| Deployment engine | Not available | Not available | Included |
| Rollback engine | Not available | Not available | Included |
| AI routing (LiteLLM) | Not available | Not available | Included |
| Self-healing | Not available | Not available | Included |
| Security lockdown | Not available | Not available | Included |
| **Total monthly** | **~$560** | **~$105** | **$499 flat** |

Wheeler AI Ops Pro is not cheaper than Grafana Cloud on raw monitoring. The value is in the bundled deployment engine, rollback engine, AI routing, and self-healing -- capabilities neither Datadog nor Grafana Cloud offer as integrated products.

---

*End of AI Ops SaaS Commercialization Plan v1.0*
