# Wheeler Ecosystem Productization Map

## Comprehensive Commercialization Audit and Strategy

**Classification:** EXECUTIVE -- STRATEGIC
**Version:** 1.0.0
**Date:** 2026-05-24
**Author:** Wheeler Brain OS -- Revenue Engineering
**Infrastructure Context:** Stage 2 Hardening Complete (QA Scorecard 100/100 A+)
**Node Topology:** AIOPS (5.78.140.118), COREDB (5.78.210.123), EDGE (187.77.148.88)
**Mesh:** Tailscale (100.121.230.28 / 100.118.166.117 / 100.98.163.17)

---

## Table of Contents

1. Executive Summary
2. Infrastructure Baseline
3. Complete System Catalog
4. Product Classification Matrix
5. Scoring Methodology
6. System-by-System Scoring
7. Dependency Map
8. TOP 10 Commercialization Opportunities
9. Product Category Pitches
10. Build vs. Productize Analysis
11. White-Label Candidate Assessment
12. Infrastructure Capacity for Productization
13. Risk Register
14. Recommendations and Roadmap

---

## 1. Executive Summary

### 1.1 The Thesis

The Wheeler ecosystem currently operates 41 Docker containers, 20 PM2 processes, 50 Claude Code agents, 12 AI agent services, 6 database instances, and 20 operational skills across 3 hardened nodes -- all at 100/100 QA score. This infrastructure represents approximately $400-600/month in raw hosting (2x Hetzner CPX51 + 1x Hostinger VPS) but the engineered capabilities layered on top represent millions in potential product value.

This document answers: **What do we already have that we can sell?**

### 1.2 Key Findings

| Dimension | Count |
|-----------|-------|
| Total catalogued systems | 34 |
| SaaS product candidates | 7 |
| API product candidates | 5 |
| Marketplace candidates | 2 |
| Internal-only (keep) | 10 |
| Enterprise offering candidates | 6 |
| White-label candidates | 4 |
| Systems blocking revenue today | 3 (COREDB connectivity, DEEPSEEK_API_KEY, scraper restart loop) |

### 1.3 Top 3 Immediate Monetization Paths

1. **Prediction Radar SaaS** -- Already deployed with 12 containers, Stripe price IDs configured, 7-day deploy path to live subscriptions
2. **FRG Nationwide** -- Fastest path to cash using existing 6,725 case records, 4-attorney network, deployed CRM API
3. **AI Ops as Managed Service** -- Sell hardened infrastructure-as-a-service to SMBs using existing deployment engine patterns

---

## 2. Infrastructure Baseline

### 2.1 Physical Node Specification

| Node | Provider | Spec | Role | Tailscale IP | Public IP | Containers | PM2 Procs |
|------|----------|------|------|-------------|-----------|------------|-----------|
| AIOPS | Hetzner CPX51 | 16 vCPU, 32GB RAM, 360GB NVMe | Application + AI | 100.121.230.28 | 5.78.140.118 | 37 | 20 |
| COREDB | Hetzner | 16 vCPU, 32GB RAM, 360GB NVMe | Data + Storage | 100.118.166.117 | 5.78.210.123 | 4 | 0 |
| EDGE | Hostinger VPS | Shared | Legacy gateway | 100.98.163.17 | 187.77.148.88 | ~4 (legacy) | ~3 |

### 2.2 Network Security Posture

- Zero containers bound to 0.0.0.0 (all 127.0.0.1 or Tailscale)
- UFW default-deny with 64 explicit allow rules
- All admin dashboards Tailscale-only
- Secrets in `.env` files with `chmod 600` (zero in compose files or PM2 jlist)
- Tailscale WireGuard mesh for inter-node communication

### 2.3 Hosting Cost Baseline

| Node | Estimated Monthly Cost | Utilization |
|------|----------------------|-------------|
| AIOPS (Hetzner CPX51) | ~$60-80 | 16 vCPU, 32GB RAM, ~50% utilized |
| COREDB (Hetzner) | ~$60-80 | 16 vCPU, 32GB RAM, ~30% utilized |
| EDGE (Hostinger) | ~$20-40 | Shared, being decommissioned |
| Tailscale + Domains | ~$20-30 | Mesh networking, DNS |
| **Total Infrastructure** | **~$160-230/mo** | |

---

## 3. Complete System Catalog

### 3.1 Revenue Systems

| # | System | Status | Components | Infrastructure Footprint |
|---|--------|--------|------------|------------------------|
| R01 | FRG Nationwide Engine | Deployed, blocked (DEEPSEEK_API_KEY) | frgcrm-api (:8082), frgcrm-agent-svc (:8008), frgops-standby (:5433 Docker) | 2 PM2, 1 Docker, 122 case records (6,603 on EDGE staging) |
| R02 | SurplusAI Platform | Deployed, partially blocked (scraper crash) | surplusai-portal-api (:8103), surplusai-scraper-agent-svc, surplusai-portal-frontend (:3003) | 2 PM2, 1 scraper agent |
| R03 | Attorney Marketplace | Not built, DocuSeal deployed | DocuSeal (:3010), Usesend (:3007), docuseal-redis | 3 Docker, 0 PM2 marketplace services |
| R04 | Ravyn Capital | Healthy, operational | ravyn-agent-svc (:8011), ravynai-app (:8007), ravynai-postgres (:5434) | 1 PM2, 2 Docker |
| R05 | Prediction Radar SaaS | Deployed, Stripe in test mode | 12 containers (api, web, worker, scheduler, db, db-backup, redis, prometheus, grafana, alertmanager, fail2ban, crowdsec, dashboard-v2, fincept) | 14 Docker, 1 PM2 agent |
| R06 | AI Ops Infrastructure | Healthy, not productized | 17 containers (grafana, prometheus, loki, alertmanager, pushgateway, superset, clickhouse, open-webui, langflow, changedetection, healthchecks, temporal, temporal-ui, webhook-relay, netdata, promtail, hostinger-health-exporter) | 17 Docker |
| R07 | Wheeler Brain OS | Healthy, internal-only | command-center (:8100), war-room-server (:8082), ecosystem-guardian, ecosystem-graph (Neo4j :7474/:7687), event-bus-relay, 50 Claude Code agents, 9 PM2 agent services, litellm (:4049) | 1 Docker (Neo4j), 12+ PM2 |
| R08 | Lead Intelligence | Healthy, partially configured | horizon-agent-svc (:8006), event-bus-relay, Neo4j, Redis | 1 PM2, shared infrastructure |

### 3.2 Infrastructure and Platform Systems

| # | System | Status | Components | Infrastructure Footprint |
|---|--------|--------|------------|------------------------|
| I01 | Deployment Engine | Operational | deploy-service.sh, preflight-check.sh, post-deploy-healthcheck.sh, 4 deploy type scripts | /root/deployment-engine/ (5 scripts) |
| I02 | Rollback Engine | Operational | rollback.sh (5-phase), restore-*.sh (4 scripts) | /root/rollback-engine/ (5 scripts) |
| I03 | Monitoring Stack | Operational | Prometheus (:9090), Grafana (:3002), Loki (:3100), Alertmanager (:9093), Pushgateway (:9092) | 5 Docker |
| I04 | Observability Extras | Operational | Uptime Kuma (:3001), Netdata (:19999), Healthchecks (:3130), promtail | 4 Docker |
| I05 | Analytics Stack | Operational | ClickHouse (:8123), Superset (:8088) | 2 Docker |
| I06 | AI Gateway (LiteLLM) | Operational | litellm PM2 (:4049), routes to DeepSeek/Claude/OpenAI | 1 PM2, 377MB |
| I07 | Workflow Engine | Operational | Temporal Server (:7233) + Temporal UI (:8089) | 2 Docker |
| I08 | AI Workflow Builder | Operational | Langflow (:7860) | 1 Docker |
| I09 | LLM Chat Interface | Operational | Open WebUI (:3000) | 1 Docker (main tag -- needs pinning) |
| I10 | Document Platform | Operational | DocuSeal (:3010), docuseal-redis | 2 Docker |
| I11 | Email Platform | Operational | Usesend (:3007) | 1 Docker |
| I12 | Web Monitoring | Operational | Changedetection.io (:5000) | 1 Docker |
| I13 | Notifications | Operational | Discord webhook-relay (:8085) | 1 Docker |

### 3.3 Enforcement and Security Systems

| # | System | Status | Components | Infrastructure Footprint |
|---|--------|--------|------------|------------------------|
| S01 | Zero-False-Green Auditor | Operational | /root/.claude/agents/zero-false-green-auditor.md, automated daily checks | Agent-based |
| S02 | Drift Detection Framework | Operational | /root/DRIFT_DETECTION_FRAMEWORK.md, lockdown-watchdog.sh (5min interval) | Script + agent |
| S03 | Secrets Scanner | Operational | pm2 jlist scan, env file audit | Automated weekly scan |
| S04 | UFW Enforcement | Operational | 64 rules, lockdown-watchdog.sh, weekly audit | System-level |
| S05 | Port Security Monitor | Operational | ss/tlnp monitoring, 127.0.0.1 enforcement | System-level |
| S06 | PM2 Restart Safety | Operational | env -i delete+start pattern, documented skill | PM2 governance |
| S07 | Database Lockdown | Operational | cap_drop ALL, chmod 600 env files, rotated passwords | Container + file-level |

### 3.4 AI Agent Fleet

| # | Agent | PM2 Name | Port | RAM | Status | Domain |
|---|-------|----------|------|-----|--------|--------|
| A01 | FRGCRM API | frgcrm-api | 8082 | 235MB | Online (blocked) | Revenue |
| A02 | FRGCRM Analysis | frgcrm-agent-svc | 8008 | 94MB | Online | Revenue |
| A03 | SurplusAI Portal | surplusai-portal-api | 8103 | 103MB | Online | Intelligence |
| A04 | SurplusAI Scraper | surplusai-scraper-agent-svc | 8003 | 108MB | Crash loop | Intelligence |
| A05 | Prediction Radar | prediction-radar-agent-svc | 8020 | 110MB | Online | Revenue |
| A06 | RavynAI | ravyn-agent-svc | 8011 | 108MB | Online | Revenue |
| A07 | Horizon Scanner | horizon-agent-svc | 8006 | 105MB | Online | Intelligence |
| A08 | InsForge | insforge-agent-svc | 8013 | 74MB | Online | Document |
| A09 | Paperless | paperless-agent-svc | 8009 | 104MB | Online | Document |
| A10 | Voice Agent | voice-agent-svc | -- | 104MB | Crash loop | Outreach |
| A11 | Voice Outreach | voice-outreach-service | 8005 | 54MB | Online | Outreach |
| A12 | Design Agent | design-agent-svc | -- | 109MB | Online | Engineering |
| A13 | LiteLLM | litellm | 4049 | 377MB | Online | AI Gateway |
| A14 | Ecosystem Guardian | ecosystem-guardian | -- | 56MB | Online | Control Plane |
| A15 | Event Bus Relay | event-bus-relay | -- | 57MB | Online | Control Plane |
| A16 | War Room | war-room-server | 8091 | 59MB | Online | Incident Response |
| A17 | OpenClaw Dashboard | openclaw-dashboard | 8110 | 60MB | Online | Control Plane |
| A18 | Command Center | command-center | 8100 | 48MB | Online | Control Plane |

### 3.5 Claude Code Skills (20)

| # | Skill | Category | Productization Potential |
|---|-------|----------|------------------------|
| SK01 | slay | Health + Remediation | HIGH -- sell as managed health audit |
| SK02 | pm2-recovery | Recovery | MEDIUM -- part of managed services |
| SK03 | docker-health | Health | MEDIUM -- part of managed services |
| SK04 | secrets-scan | Security | HIGH -- standalone security product |
| SK05 | rollback-first | Deployment | LOW -- operational process |
| SK06 | deploy-safety | Deployment | LOW -- operational process |
| SK07 | production-readiness | Assessment | HIGH -- consulting deliverable |
| SK08 | no-false-greens | Validation | MEDIUM -- methodology IP |
| SK09 | cost-control | Finance | MEDIUM -- part of managed services |
| SK10 | database-lockdown | Security | MEDIUM -- part of security suite |
| SK11 | hostinger-production-operator | Operations | LOW -- server-specific |
| SK12 | private-network-check | Security | LOW -- methodology IP |
| SK13 | incident-response | Operations | MEDIUM -- consulting |
| SK14 | repo-audit | Assessment | HIGH -- standalone product |
| SK15 | agent-workflow-builder | Engineering | HIGH -- enterprise agent platform |
| SK16 | aiops-control-plane-operator | Operations | HIGH -- managed AI Ops |
| SK17 | worker-routing-operator | Operations | MEDIUM -- part of platform |
| SK18 | mac-command-center-operator | Operations | LOW -- niche |
| SK19 | open-source-repo-evaluator | Assessment | HIGH -- standalone product |
| SK20 | superpowers | Meta-skill | LOW -- methodology |
| SK21 | agent-sdk-dev | Development | MEDIUM -- consulting |
| SK22 | code-modernization | Development | HIGH -- consulting service |

### 3.6 Automation and Data Pipeline Systems

| # | System | Status | Components | Notes |
|---|--------|--------|------------|-------|
| D01 | PipelineDAG | All 6 stages failing | LeadIngestion, CaseScorer, AttorneyMatcher, ClaimantOutreach, DocumentGenerator, PipelineMonitor | Blocked by COREDB + DEEPSEEK |
| D02 | Revenue Health Checks | Operational | /root/scripts/revenue-healthcheck.sh (6-layer) | JSON + human output |
| D03 | Revenue Rollback Checklist | Operational | /root/scripts/revenue-rollback-checklist.sh (5-stage, A-F) | Interactive |
| D04 | Smoke Test Suite | Operational | smoke-test-all.sh (8 sections), ai-routing-validation.sh (11 sections), 6+ validation scripts | 15+ scripts |
| D05 | Backup System | Operational | pg_dump daily, quarterly restore testing, 26-hour recency window | Automated |
| D06 | AI Acquisition Engine | Designed, not built | /root/AI_ACQUISITION_ENGINE.md -- AI content generation, SEO, landing pages | Deliverable |
| D07 | Self-Healing Engine | Operational | autoheal.sh (2min), lockdown-watchdog (5min), Docker restart policies | System-level |
| D08 | Revenue Automation Framework | Governing doc | /root/REVENUE_AUTOMATION_FRAMEWORK.md -- 7 principles, rollback-first | Policy document |
| D09 | Disaster Recovery Plan | Documented | /root/DISASTER_RECOVERY_PLAN.md | Policy document |

### 3.7 Database Inventory

| # | Database | Engine | Location | Port | Records | Revenue System |
|---|----------|--------|----------|------|---------|----------------|
| DB01 | frgops-standby | PostgreSQL 16 | AIOPS | 5433 | 122 cases | FRG Nationwide |
| DB02 | wheeler_core | PostgreSQL | COREDB | 5432 | 0 (blocked) | All systems |
| DB03 | shared-postgres-recovery | PostgreSQL | EDGE | 5432 | 6,603 cases | FRG Nationwide |
| DB04 | ravynai-postgres | PostgreSQL 16 (PostGIS) | AIOPS | 5434 | Active | Ravyn Capital |
| DB05 | prediction-radar-db | PostgreSQL 16 | AIOPS | 5432 | Active | Prediction Radar |
| DB06 | ecosystem-graph | Neo4j 5.26 | AIOPS | 7687 | Active | Wheeler Brain |
| DB07 | aiops-clickhouse | ClickHouse 24.3 | AIOPS | 8123 | Active | AI Ops/Analytics |
| DB08 | prediction-radar-redis | Redis 7 | AIOPS | 6379 | Active | Prediction Radar |
| DB09 | docuseal-redis | Redis 7 Alpine | AIOPS | 6379 | Active | Attorney Marketplace |
| DB10 | usesend-redis | Redis | EDGE | -- | Active | Attorney Marketplace |
| DB11 | wheeler-minio | MinIO | COREDB | 9000 | Active | All systems |

### 3.8 Analytical and Reporting Systems

| # | System | Status | Purpose |
|---|--------|--------|---------|
| X01 | Grafana (:3002) | Operational | Metrics dashboards (6+ pre-built panels) |
| X02 | Prometheus (:9090) | Operational | Metrics collection, alert rules |
| X03 | Superset (:8088) | Operational | BI dashboards, SQL analytics |
| X04 | ClickHouse (:8123) | Operational | Event analytics data warehouse |
| X05 | Revenue Scorecards | Generated | STAGE2_QA_SCORECARD_FINAL.md (100/100) |
| X06 | Ecosystem Health Scoring | Operational | /root/ECOSYSTEM_HEALTH_SCORING.md |
| X07 | Executive Dashboard | Not built | Planned deliverable |
| X08 | Business Unit Relationships | Documented | /root/BUSINESS_UNIT_RELATIONSHIPS.md |
| X09 | Ecosystem Revenue Map | Documented | /root/ECOSYSTEM_REVENUE_MAP.md |
| X10 | Enforcement Gap Analysis | Documented | /root/ENFORCEMENT_GAP_ANALYSIS.md |

### 3.9 Dashboards and Frontends

| # | System | Port | Status | Access |
|---|--------|------|--------|--------|
| F01 | Command Center | 8100 | Online | Tailscale-only |
| F02 | War Room | 8091 | Online | Tailscale-only |
| F03 | OpenClaw Dashboard | 8110 | Online | Tailscale-only |
| F04 | Open WebUI | 3000 | Online | Tailscale-only |
| F05 | Langflow | 7860 | Online | Tailscale + auth |
| F06 | Superset | 8088 | Online | Tailscale + auth |
| F07 | Grafana | 3002 | Online | Tailscale + auth |
| F08 | Uptime Kuma | 3001 | Online | Tailscale-only |
| F09 | Netdata | 19999 | Online | Tailscale-only |
| F10 | Temporal UI | 8089 | Online | Tailscale-only |
| F11 | 1Panel | 8090 | Online | Tailscale-only |

### 3.10 Internal Infrastructure

| # | System | Status | Notes |
|---|--------|--------|-------|
| Y01 | Nginx Gateway | Operational | 17 virtual hosts, 443 HTTPS, rate limiting |
| Y02 | Tailscale Mesh | Operational | 3 nodes, WireGuard encrypted |
| Y03 | UFW Firewall | Operational | 64 rules, default-deny |
| Y04 | PM2 Ecosystem | Operational | 20 processes, 18 configs |
| Y05 | Docker Engine | Operational | 41 containers, 12 compose stacks |
| Y06 | Uptime Monitoring | Operational | Multiple uptime robots |
| Y07 | Discord Webhooks | Operational | 4+ channels |

---

## 4. Product Classification Matrix

### 4.1 Classification Definitions

| Classification | Definition | Go-to-Market |
|---------------|------------|--------------|
| **SaaS Product** | Multi-tenant web application with subscription billing. Customer logs into browser. | Stripe + self-serve signup + tiered pricing |
| **API Product** | Programmatic access to data or intelligence via REST/GraphQL. Usage-based billing. | Developer portal + API keys + metered billing |
| **Marketplace** | Two-sided platform connecting supply + demand. Transaction fee revenue. | Network effects + tiered fees |
| **Internal-Only (Keep)** | Core infrastructure that does not externalize. Enables other products. | N/A |
| **Enterprise Offering** | Custom deployment for single client. White-glove, high-touch. | Sales-led + contract + SLA |
| **White-Label Candidate** | Can be rebranded and resold by partners. | Partner program + branding layer |
| **Consulting Service** | Expertise/IP delivered as professional services. | Time + materials or fixed-bid |

### 4.2 System Classification

| System | Primary Classification | Secondary Classification | Rationale |
|--------|----------------------|------------------------|-----------|
| FRG Nationwide Engine | **Enterprise Offering** | Internal Revenue | Requires attorney network, not standalone sellable |
| SurplusAI Platform | **SaaS Product** | API Product | Multi-tenant portal with intelligence subscriptions |
| Attorney Marketplace | **Marketplace** | SaaS Product | Two-sided: attorneys + claimants, transaction fees |
| Ravyn Capital | **Internal-Only** | Enterprise Offering | Deal sourcing engine, could white-label for PE firms |
| Prediction Radar | **SaaS Product** | API Product | Subscription web app with data API, Stripe ready |
| AI Ops Infrastructure | **Enterprise Offering** | White-Label Candidate | Sell hardened infra as managed service |
| Wheeler Brain OS | **Internal-Only** | Enterprise Offering | Agent orchestration platform, not consumer-ready |
| Lead Intelligence | **Internal-Only** | API Product | Lead routing engine, could sell as API feed |
| Deployment Engine | **Internal-Only** | -- | Operational tooling, not productizable independently |
| Rollback Engine | **Internal-Only** | -- | Operational tooling |
| Monitoring Stack | **Enterprise Offering** | White-Label Candidate | Part of managed services offering |
| Analytics Stack | **Internal-Only** | Enterprise Offering | Part of data platform offering |
| LiteLLM Gateway | **SaaS Product** | Enterprise Offering | Sell as managed AI gateway service |
| DocuSeal | **Internal-Only** | -- | Already an open-source product we consume |
| Usesend | **Internal-Only** | -- | Already a product we consume |
| Secrets Scanner | **API Product** | Consulting Service | Standalone security audit tool |
| Production Readiness | **Consulting Service** | -- | Assessment methodology |
| Repo-Router Policies | **Internal-Only** | -- | Governance framework |
| Self-Healing Engine | **Enterprise Offering** | White-Label Candidate | Part of managed AI Ops |
| AI Acquisition Engine | **SaaS Product** | Consulting Service | Not built yet, but productizable |
| Claude Code Skills (selected) | **Consulting Service** | API Product | Developer tooling, training, customization |
| No-False-Greens Methodology | **Consulting Service** | White-Label Candidate | QA methodology IP |
| PipelineDAG | **Internal-Only** | -- | Internal data orchestration |
| Revenue Dashboards | **SaaS Product** | Enterprise Offering | Part of reporting platform |

---

## 5. Scoring Methodology

### 5.1 Scoring Dimensions

Each system is scored on four dimensions using a 1-10 scale:

**Market Readiness (1-10)**
How close is this to being sellable today?
- 1-3: Concept only, core work required
- 4-6: Deployed but needs UI, billing, or documentation
- 7-8: Near-sellable, minor gaps remain
- 9-10: Ship it today

**Revenue Potential ($/mo)**
Estimated monthly recurring revenue at steady state, based on infrastructure capacity and market comparables. No fake projections -- grounded in existing case counts, container capacity, and bandwidth.

**Technical Maturity (1-10)**
How stable, secure, and well-architected is the system?
- 1-3: Prototype quality, frequent failures
- 4-6: Functional but has known issues
- 7-8: Production-grade with minor cleanup needed
- 9-10: Battle-tested, hardened, monitored

**Defensibility (1-10)**
How hard is it for a competitor to replicate?
- 1-3: Commodity feature, easily copied
- 4-6: Some proprietary data/process but replicable
- 7-8: Strong moat (data network effects, integrations)
- 9-10: Extremely hard to replicate (regulation, proprietary data, multi-sided network)

### 5.2 Composite Score

**Opportunity Score** = (Market Readiness x 0.30) + (Revenue Potential normalized x 0.35) + (Technical Maturity x 0.20) + (Defensibility x 0.15)

Revenue Potential is normalized to a 1-10 scale where $10K+/mo = 10, $5K/mo = 5, etc.

---

## 6. System-by-System Scoring

### 6.1 Revenue Systems

#### R01: FRG Nationwide Engine

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **5/10** | CRM API deployed, 6,725 case records exist, 4 attorneys onboarded. Blocked by DEEPSEEK_API_KEY + COREDB. No automated matching, no public frontend. |
| Revenue Potential | **$5K-15K/mo** | 15% recovery on 6,725 cases at $5K avg surplus, 25% fee = ~$1,250/case. Conservative: 4-12 cases/mo at initial capacity = $5K-15K/mo. Scale to 50+ cases/mo = $62.5K/mo. |
| Technical Maturity | **6/10** | API is clean FastAPI. PM2 agents healthy. But 2 critical blockers, no automated pipeline, manual attorney matching. |
| Defensibility | **7/10** | Network of 4 attorneys + data moat from 6,725 case records. County-level knowledge is hard to replicate. First-mover in digitized surplus recovery. |
| **Opportunity Score** | **5.9/10** | Highest immediate revenue potential but needs unblocking. |

#### R02: SurplusAI Platform

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **4/10** | Portal API deployed and healthy. Scraper in crash loop (282+ restarts). No multi-tenant billing, no public frontend, no data pipeline. Platform architecture exists but data flow broken. |
| Revenue Potential | **$3K-10K/mo** | Intelligence subscriptions at $997-2,997/mo. Requires 3-5 enterprise subscribers at steady state. Data licensing: $0.10/case at 10K cases/mo = $1K. |
| Technical Maturity | **5/10** | Portal API is solid (103MB, 0 restarts). Scraper is broken. Adapter framework not built. No ML scoring deployed. AI extraction pipeline designed but unimplemented. |
| Defensibility | **8/10** | County adapter framework is a genuine moat -- each adapter requires domain expertise. Data network effects: more cases = better scoring = better attorney matching. Direct integration with existing attorney network. |
| **Opportunity Score** | **5.3/10** | Strong defensibility, solid architecture, but scraper must be stabilized before any revenue. |

#### R03: Attorney Marketplace

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **2/10** | DocuSeal deployed and healthy. Full database schema designed (14 tables). API endpoints spec'd. No code written for marketplace services. No frontend. |
| Revenue Potential | **$5K-20K/mo** | Referral fees at 20-30% of attorney revenue. 20 attorneys at 10 cases/mo at $5K avg recovery = $1M gross, 25% FRG share = $20.8K/mo. Conservative: 4 attorneys at 5 cases/mo = $2.5K/mo. |
| Technical Maturity | **3/10** | Excellent design documentation. Schema is production-quality. Zero implementation. DocuSeal and Usesend are infrastructure dependencies that work. |
| Defensibility | **7/10** | Two-sided network effects: more attorneys attract more cases, more cases attract more attorneys. Integration with FRGCRM creates switching costs. Performance scoring creates quality moat. |
| **Opportunity Score** | **4.0/10** | Highest long-term potential but requires significant build investment (est. 6-8 weeks to MVP). |

#### R04: Ravyn Capital

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **6/10** | All components healthy. ravyn-agent-svc at 0 restarts. ravynai-app operational. Opportunity graph in Neo4j. But no deal pipeline automation, no external client integration. |
| Revenue Potential | **$1K-5K/mo** | Deal sourcing fees and data licensing to PE/VC firms. Advisory at $5-10K/project. Not a high-volume revenue stream -- boutique advisory model. |
| Technical Maturity | **7/10** | Healthiest revenue system. PostGIS support for spatial analysis. Stable agents. Neo4j graph for opportunity mapping. |
| Defensibility | **6/10** | Opportunity graph is proprietary but PE firms have their own tools. Integration with SurplusAI data is unique but not a hard moat. |
| **Opportunity Score** | **4.8/10** | Solid system, limited revenue ceiling. Best as internal deal engine. |

#### R05: Prediction Radar SaaS

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **7/10** | Full 12-container stack deployed and healthy. Stripe price IDs configured (Pro at $49/mo, Agency at $199/mo). Web frontend operational. External API keys connected (GNews, Polymarket, CoinGecko). Fincept terminal at :6080. |
| Revenue Potential | **$2K-15K/mo** | 20 Pro ($49) = $980/mo. 5 Agency ($199) = $995/mo. Total = $1,975/mo early. At scale: 100 Pro + 20 Agency = $8,880/mo. Data licensing adds $2-5K. |
| Technical Maturity | **8/10** | Most containerized system. All HEALTHCHECKs passing. Prometheus/Alertmanager integrated. Fail2ban + Crowdsec for security. Backup container operational. |
| Defensibility | **5/10** | Prediction market space is competitive. Multiple established players. Wheeler differentiator: integration with FRG/SurplusAI data creates unique signals. But defensibility comes from data ecosystem, not the prediction engine alone. |
| **Opportunity Score** | **6.4/10** | Closest system to immediate revenue. Unblock Stripe and ship. |

#### R06: AI Ops Infrastructure

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **4/10** | Platform is fully operational and battle-tested. But no multi-tenant architecture, no service catalog, no billing. Requires 4-6 weeks of productization work. |
| Revenue Potential | **$2K-10K/mo** | Managed AI infrastructure at $500-2K/client. 4-10 SMB clients at build capacity. Enterprise clients at $5K+/mo requires dedicated node. |
| Technical Maturity | **9/10** | 100/100 QA score. Production-grade monitoring, security, and deployment. Zero wildcard binds. Secrets management. Auto-healing. This is genuinely best-in-class infrastructure. |
| Defensibility | **7/10** | Hardened zero-trust architecture is not trivial to replicate. Rollback-first deployment engine. Integration of 20+ open-source tools into cohesive platform. 64 UFW rules, 17 Nginx vhosts, 41 containers all at 127.0.0.1. |
| **Opportunity Score** | **5.8/10** | Most technically mature system. Requires productization investment but high-value offering. |

#### R07: Wheeler Brain OS

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **3/10** | Powerful internal system but built for Wheeler ecosystem. 50 agents are specialized for Wheeler infrastructure. No multi-tenant AI orchestration. No tenant isolation. Heavy customization required for external sale. |
| Revenue Potential | **$2K-8K/mo** | Enterprise agent orchestration. AI command center as product. Consulting on agent ecosystem design. Market is hot (AI agent platforms) but competitive. |
| Technical Maturity | **7/10** | Neo4j ecosystem graph is unique asset. 12 PM2 agent services running 24/7. LiteLLM integration. Event bus relay for agent communication. Battle-tested but very Wheeler-specific. |
| Defensibility | **8/10** | Ecosystem graph with 50 agents is extremely hard to replicate. Custom integration with all Wheeler systems. Agent coordination patterns are proprietary IP. |
| **Opportunity Score** | **4.8/10** | Crown jewel IP but needs significant generalization for external sale. Best medium-term productization play. |

#### R08: Lead Intelligence

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **3/10** | horizon-agent healthy, event bus running. No routing rules implemented, no lead scoring model, no external API. Core infrastructure exists but no product layer. |
| Revenue Potential | **$1K-5K/mo** | Pay-per-lead model at $10-25/lead. 100-200 qualified leads/mo at steady state. Data enrichment licensing adds $. |
| Technical Maturity | **5/10** | Horizon agent is solid (105MB, 0 restarts). Event bus relay functional. Neo4j integration for lead graph. Missing: scoring model, routing rules, external API. |
| Defensibility | **6/10** | Lead scoring against FRG/SurplusAI data is unique. Integration with attorney marketplace creates switching costs. But lead gen is a crowded space. |
| **Opportunity Score** | **3.5/10** | Building block for other products, not standalone sellable without significant work. |

### 6.2 Infrastructure and Platform Systems

#### I01-I02: Deployment + Rollback Engine

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **4/10** | Fully operational for Wheeler infra. 7-gate preflight, 5-phase rollback. But deeply coupled to Wheeler naming conventions and service topology. |
| Revenue Potential | **$1K-3K/mo** | Consulting/training on deployment patterns. License as methodology. Not a standalone SaaS product. |
| Technical Maturity | **9/10** | Production-grade. Auto-rollback on failure. 4 service types supported. 7 deployment gates. Tested and verified. |
| Defensibility | **4/10** | Deployment tooling is a commodity space (Spinnaker, ArgoCD, etc.). Wheeler's differentiator is the verify-act-verify and rollback-first philosophy, but it's a methodology, not a technology moat. |
| **Opportunity Score** | **3.8/10** | Operational excellence, low productization potential. Better as part of managed AI Ops offering. |

#### I03-I05: Monitoring + Analytics Stack

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **5/10** | Full monitoring stack operational. Grafana, Prometheus, Loki, ClickHouse, Superset all healthy. But configured for Wheeler infra -- needs templating for external use. |
| Revenue Potential | **$1K-5K/mo** | Part of managed AI Ops package. Standalone monitoring as a service is crowded (Datadog, Grafana Cloud). |
| Technical Maturity | **9/10** | All components production-grade. Alert pipeline to Discord operational. Health check coverage 100%. No-false-greens validation. |
| Defensibility | **5/10** | Open-source stack is replicable. Wheeler's integration and hardening is differentiator but not a moat. |
| **Opportunity Score** | **4.5/10** | Bundle with AI Ops managed service rather than standalone. |

#### I06: LiteLLM AI Gateway

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **7/10** | Fully operational PM2 service at :4049. Routes to DeepSeek, Claude, OpenAI. 377MB RAM, 0 restarts. Centralized API key management. Usage tracking operational. |
| Revenue Potential | **$2K-8K/mo** | Managed AI gateway as service. $200-500/mo per client for managed LLM routing + key management. 10-15 SMB clients. Plus usage markup (buy wholesale from API providers, sell with margin). |
| Technical Maturity | **8/10** | Production-grade. Model routing, fallback, cost tracking all operational. Integrated with 12 agent services and 3 API providers. |
| Defensibility | **5/10** | LiteLLM is open-source -- anyone can deploy it. Wheeler differentiation: hardened deployment, integration with ecosystem, managed key rotation, usage analytics. Thin moat. |
| **Opportunity Score** | **5.8/10** | Quick to productize (add multi-tenant layer), moderate revenue ceiling. Best as add-on to managed AI Ops. |

#### I09: Open WebUI

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **6/10** | Deployed, functional, accessible via Tailscale. But on `main` tag (violates pinning policy). Single-tenant. |
| Revenue Potential | **$1K-3K/mo** | Shared AI chat interface with backend model access. Sell as managed ChatGPT alternative for businesses. |
| Technical Maturity | **6/10** | Functional but `:main` tag needs pinning. Open source project -- upstream updates frequent. |
| Defensibility | **3/10** | Open-source project anyone can deploy. Zero differentiation. |
| **Opportunity Score** | **3.5/10** | Thin wrapper on open-source. Only valuable as part of larger platform. |

#### I12: Changedetection.io

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **7/10** | Deployed at :5000, healthy. Ready to use. |
| Revenue Potential | **$500-2K/mo** | Web monitoring as a service. Niche but sticky. |
| Technical Maturity | **8/10** | Stable, well-configured. |
| Defensibility | **3/10** | Open-source tool, easily replicated. |
| **Opportunity Score** | **3.2/10** | Feature, not a product. |

### 6.3 Security and Enforcement Systems

#### S03: Secrets Scanner

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **6/10** | Operational for Wheeler ecosystem. Automated PM2 jlist scan. Env file audit. Can be packaged as standalone tool. |
| Revenue Potential | **$1K-5K/mo** | SaaS security scanner for PM2/Docker environments. $100-500/mo per client. DevOps security tooling market is growing. |
| Technical Maturity | **7/10** | Proven in production. Scans PM2 jlist, Docker env, file permissions. Documented patterns for remediation. |
| Defensibility | **5/10** | Security scanning is crowded (GitGuardian, TruffleHog). Wheeler differentiator: PM2-specific scanning + env -i delete+start remediation. Niche but defensible in PM2 ecosystem. |
| **Opportunity Score** | **4.8/10** | Viable niche product with documented IP. Scope limited to PM2/Linux environments. |

#### SK07: Production Readiness Assessment

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **8/10** | Methodology is documented and proven (100/100 QA scorecard). Assessment framework exists. Can be delivered as consulting engagement immediately. |
| Revenue Potential | **$2K-10K/mo** | Consulting: $5-15K per assessment engagement. 1-2 engagements/month. Plus recurring: $1K/mo for quarterly reassessments. |
| Technical Maturity | **9/10** | Proven across 8 domains with 17 checks. 100/100 score achieved on real infrastructure. No-false-greens enforcement. |
| Defensibility | **6/10** | Methodology IP is defensible as process/IP. Cross-domain assessment (PM2, Docker, network, security, deployment) is more comprehensive than point tools. |
| **Opportunity Score** | **6.8/10** | Ready to sell today. Methodology is proven and documented. No code to write -- pure consulting/IP. |

#### SK14: Repo Audit

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **7/10** | Methodology exists, tooling operational. Automated assessment. |
| Revenue Potential | **1K-4K/mo** | Audit engagements at $2-5K each. 2-4/month. |
| Technical Maturity | **8/10** | Proven methodology. |
| Defensibility | **4/10** | Audit space is crowded. |
| **Opportunity Score** | **4.5/10** | Niche consulting service. Good cash flow. |

#### SK19: Open Source Repo Evaluator

| Dimension | Score | Justification |
|-----------|-------|---------------|
| Market Readiness | **8/10** | Skill exists and is operational. Can evaluate any GitHub repo across 6 dimensions. Produces adoption recommendation. |
| Revenue Potential | **$2K-8K/mo** | Automated OSS evaluation as service. $500-1K per evaluation for enterprises adopting open-source. Due diligence for legal/compliance teams. |
| Technical Maturity | **8/10** | Operational skill with structured output. Multi-dimensional analysis. |
| Defensibility | **6/10** | Unique approach combining code quality, maintenance, security, license, dependency analysis. Integration with Claude Code gives edge over static analysis tools. |
| **Opportunity Score** | **6.2/10** | Differentiated offering, immediately sellable. Target: enterprise legal and procurement teams. |

### 6.4 Summary Scoring Table

| Rank | System | Classification | Market Readiness | Revenue Potential ($/mo) | Technical Maturity | Defensibility | Opportunity Score |
|------|--------|---------------|:----------------:|:------------------------:|:------------------:|:-------------:|:-----------------:|
| 1 | Prediction Radar SaaS | SaaS | 7 | $2K-15K | 8 | 5 | **6.4** |
| 2 | Production Readiness Assessment | Consulting | 8 | $2K-10K | 9 | 6 | **6.8** |
| 3 | Open Source Repo Evaluator | Consulting/API | 8 | $2K-8K | 8 | 6 | **6.2** |
| 4 | FRG Nationwide Engine | Enterprise | 5 | $5K-15K | 6 | 7 | **5.9** |
| 5 | LiteLLM AI Gateway | SaaS | 7 | $2K-8K | 8 | 5 | **5.8** |
| 6 | AI Ops Managed Service | Enterprise | 4 | $2K-10K | 9 | 7 | **5.8** |
| 7 | SurplusAI Platform | SaaS | 4 | $3K-10K | 5 | 8 | **5.3** |
| 8 | Secrets Scanner | API | 6 | $1K-5K | 7 | 5 | **4.8** |
| 9 | Ravyn Capital | Internal | 6 | $1K-5K | 7 | 6 | **4.8** |
| 10 | Wheeler Brain OS | Enterprise | 3 | $2K-8K | 7 | 8 | **4.8** |
| 11 | Repo Audit | Consulting | 7 | $1K-4K | 8 | 4 | **4.5** |
| 12 | Monitoring Stack | Enterprise | 5 | $1K-5K | 9 | 5 | **4.5** |
| 13 | Attorney Marketplace | Marketplace | 2 | $5K-20K | 3 | 7 | **4.0** |
| 14 | Deployment Engine | Internal | 4 | $1K-3K | 9 | 4 | **3.8** |
| 15 | Lead Intelligence | Internal | 3 | $1K-5K | 5 | 6 | **3.5** |
| 16 | Open WebUI | SaaS | 6 | $1K-3K | 6 | 3 | **3.5** |
| 17 | Changedetection.io | Internal | 7 | $500-2K | 8 | 3 | **3.2** |

---

## 7. Dependency Map

### 7.1 Revenue System Dependencies

```
Prediction Radar SaaS
  ├── Depends on: LiteLLM (:4049) for AI predictions
  ├── Depends on: PostgreSQL (:5432) for user data
  ├── Depends on: Redis (:6379) for caching
  ├── Depends on: Stripe API (live keys needed)
  └── Depends on: Nginx gateway for public access

FRG Nationwide Engine
  ├── Depends on: frgops-standby (:5433) for case data
  ├── Depends on: DEEPSEEK_API_KEY via LiteLLM (:4049)
  ├── Depends on: COREDB PostgreSQL (:5432) [BLOCKED]
  ├── Depends on: Attorney Marketplace for routing
  └── Depends on: PipelineDAG for automation

SurplusAI Platform
  ├── Depends on: Scraper agent (currently crash-looping)
  ├── Depends on: LiteLLM (:4049) for AI extraction
  ├── Depends on: frgops-standby (:5433) for data
  ├── Depends on: Neo4j (:7687) for relationship graph
  └── Depends on: Temporal (:7233) for durable workflows

Attorney Marketplace
  ├── Depends on: DocuSeal (:3010) for signatures
  ├── Depends on: Usesend (:3007) for email
  ├── Depends on: LiteLLM (:4049) for AI routing
  ├── Depends on: PostgreSQL for attorney data
  └── Depends on: FRGCRM for case integration

AI Ops Managed Service
  ├── Depends on: All monitoring stack (Prometheus, Grafana, Loki, Alertmanager)
  ├── Depends on: Deployment Engine for client deploys
  ├── Depends on: Rollback Engine for safety
  ├── Depends on: LiteLLM for AI gateway
  └── Depends on: No existing client data (greenfield per client)

Wheeler Brain OS
  ├── Depends on: Neo4j (:7687) for ecosystem graph
  ├── Depends on: LiteLLM (:4049) for agent AI
  ├── Depends on: 12 PM2 agent services
  ├── Depends on: 50 Claude Code agents
  ├── Depends on: Command Center (:8100) for orchestration
  └── Depends on: Event bus relay for agent communication
```

### 7.2 Infrastructure Dependency Graph

```
PipelineDAG
  ├── Depends on: COREDB PostgreSQL (:5432) for all stages [BLOCKED]
  ├── Depends on: DEEPSEEK_API_KEY for AI stages [BLOCKED]
  ├── Depends on: SurplusAI scraper for data ingestion [BLOCKED]
  └── Depends on: All 8 revenue systems for data outputs

LiteLLM (:4049)
  ├── Depends on: DEEPSEEK_API_KEY in /opt/apps/.env.shared
  ├── Depends on: External API providers (DeepSeek, Anthropic, OpenAI)
  └── No internal dependencies -- standalone PM2 service

Monitoring Stack
  ├── Depends on: All systems for metrics input
  ├── Depends on: Docker engine for container metrics
  ├── Depends on: PM2 for process metrics
  └── No hard dependencies for stack itself

Deployment Engine
  ├── Depends on: /root/deployment-engine/ scripts
  ├── Depends on: Target service (Docker/PM2/static)
  └── Depends on: Rollback Engine for safety
```

### 7.3 Blocker Dependency Chain

```
COREDB PostgreSQL (:5432 REFUSING CONNECTIONS)
  ├── BLOCKS: FRG Nationwide (wheeler_core database)
  ├── BLOCKS: PipelineDAG (all 6 stages)
  ├── BLOCKS: SurplusAI (data persistence to central store)
  ├── BLOCKS: All agent services (FRGOPS_DATABASE_URL)
  └── BLOCKS: Revenue dashboards (no data source)

DEEPSEEK_API_KEY Missing from frgcrm-api
  ├── BLOCKS: FRGCRM AI case analysis
  ├── BLOCKS: SurplusAI scoring (via LiteLLM)
  ├── BLOCKS: Prediction Radar AI predictions
  └── BLOCKS: Attorney matching AI

SurplusAI Scraper (282+ restarts, crash loop)
  ├── BLOCKS: SurplusAI data pipeline
  ├── BLOCKS: Lead Intelligence input
  ├── BLOCKS: Ravyn Capital opportunity data
  └── BLOCKS: SurplusAI product launch
```

---

## 8. TOP 10 Commercialization Opportunities

Ranked by composite Opportunity Score x urgency x infrastructure readiness.

### #1: Prediction Radar SaaS -- Go Live with Stripe

| Metric | Detail |
|--------|--------|
| Opportunity Score | 6.4/10 (highest) |
| Investment Required | 7 days to production Stripe |
| Revenue Path | $1,975/mo at 20 Pro + 5 Agency subscribers |
| Infrastructure | 12 containers deployed and healthy |
| Blockers | Stripe in test mode (P1), no subscriber management flow |
| Moat | Integration with FRG/SurplusAI data ecosystem |
| Action | Switch Stripe to production keys, build subscription signup flow, deploy pricing page |

**30-second pitch:** Prediction Radar is a fully deployed SaaS prediction platform with 14 containers, integrated Stripe price IDs, and live market data feeds from 5+ providers. It needs 7 days of productization work to flip from test mode to live subscriptions. Target: `$2K/mo` within 30 days of Stripe activation, scaling to `$8K+/mo` within 90 days.

### #2: FRG Nationwide -- Unblock and Ship

| Metric | Detail |
|--------|--------|
| Opportunity Score | 5.9/10 |
| Investment Required | 2-4 hours (DEEPSEEK_API_KEY fix) |
| Revenue Path | $5K-15K/mo within 60 days |
| Infrastructure | 2 PM2 + 1 Docker, 6,725 case records |
| Blockers | DEEPSEEK_API_KEY (P0, 30min fix), COREDB (P0, 2-4h fix) |
| Moat | 6,725 case records, 4-attorney network, county-level domain expertise |
| Action | Fix env var (30min), fix COREDB (2-4h), migrate 6,603 staging cases (2h) |

**30-second pitch:** FRG Nationwide already has 6,725 case records, a deployed CRM API, and 4 enrolled attorneys. Two infrastructure blockers (a missing API key and a DB connection string) are preventing what could be `$5K+/mo` in contingency fee revenue. The fix is 2-4 hours of ops work, not months of development.

### #3: AI Ops Managed Service

| Metric | Detail |
|--------|--------|
| Opportunity Score | 5.8/10 |
| Investment Required | 4-6 weeks (multi-tenant, service catalog, billing) |
| Revenue Path | $2K-10K/mo at 4-10 SMB clients |
| Infrastructure | 17 containers, 20 PM2 processes, all at 100/100 QA |
| Blockers | No multi-tenant, no service catalog, no billing |
| Moat | Battle-tested zero-trust architecture, deployment engine, auto-healing |
| Action | Build tenant isolation pattern, create service catalog with pricing, build provisioning automation |

**30-second pitch:** Wheeler AI Ops is a production-grade, hardened AI infrastructure platform running at 100/100 QA score across 41 containers, 20 PM2 processes, and 6 databases -- all with zero public exposure. We already run this for ourselves. We can run it for 10 other companies at `$500-2K/mo` each.

### #4: SurplusAI Platform

| Metric | Detail |
|--------|--------|
| Opportunity Score | 5.3/10 |
| Investment Required | 2 weeks (fix scraper + MVP pricing) |
| Revenue Path | $3K-10K/mo at 3-5 enterprise subscribers |
| Infrastructure | Portal API deployed, county adapter framework designed |
| Blockers | Scraper crash-loop (P1), no billing, no public frontend |
| Moat | County adapter framework with domain-specific extraction |
| Action | Fix scraper crash-loop, deploy parser + scoring services, enable 5 county adapters |

**30-second pitch:** SurplusAI turns county court records into structured, scored, and routed legal leads. The portal API is already deployed and healthy. We need to stabilize the scraper and ship the county adapter framework to unlock a multi-tenant intelligence platform at `$997-2,997/mo`.

### #5: Production Readiness Assessment Service

| Metric | Detail |
|--------|--------|
| Opportunity Score | 6.8/10 (highest readiness) |
| Investment Required | 0 days -- ready to sell |
| Revenue Path | $2K-10K/mo at 1-2 engagements/mo |
| Infrastructure | Methodology documented, IP proven |
| Blockers | None |
| Moat | 8-domain assessment framework, no-false-greens methodology |
| Action | Create sales page, publish case study of Wheeler 100/100 score, start outreach |

**30-second pitch:** We audited our own infrastructure across 8 domains (PM2, Docker, network, security, deployment, rollback, monitoring, secrets) and achieved 100/100. We can do the same for your infrastructure. Fixed-price assessment at `$5-15K`.

### #6: Open Source Repo Evaluator

| Metric | Detail |
|--------|--------|
| Opportunity Score | 6.2/10 |
| Investment Required | 1 week (package as API + web UI) |
| Revenue Path | $2K-8K/mo at $500-1K/evaluation |
| Infrastructure | Claude Code skill exists and works |
| Blockers | No standalone frontend, no billing |
| Moat | Multi-dimensional analysis combining 6 axes into adoption recommendation |
| Action | Build simple web UI, add Stripe integration, publish to dev tool directories |

**30-second pitch:** Before your enterprise approves that open-source library, let our AI evaluate it across code quality, maintenance health, security posture, license compliance, dependency freshness, and community activity. One URL in, a buy/hold/avoid recommendation out. `$500 per evaluation`.

### #7: LiteLLM AI Gateway as a Service

| Metric | Detail |
|--------|--------|
| Opportunity Score | 5.8/10 |
| Investment Required | 2-3 weeks (multi-tenant proxy, usage dashboards) |
| Revenue Path | $2K-8K/mo at 10-15 SMB clients |
| Infrastructure | Deployed and stable at :4049, 377MB, 0 restarts |
| Blockers | Single tenant, no client onboarding |
| Moat | Hardened deployment + usage analytics + managed key rotation |
| Action | Build tenant isolation per client, deploy Stripe metered billing, create client dashboard |

**30-second pitch:** Stop managing API keys for 5 different LLM providers. Our hardened AI gateway sits between your apps and OpenAI/Claude/DeepSeek, handling routing, failover, key rotation, and cost tracking. `$200-500/mo` fully managed.

### #8: Secrets Scanner for PM2/Docker

| Metric | Detail |
|--------|--------|
| Opportunity Score | 4.8/10 |
| Investment Required | 2 weeks (package as CLI + SaaS) |
| Revenue Path | $1K-5K/mo |
| Infrastructure | Operational scanner, documented patterns |
| Blockers | No standalone packaging, no distribution |
| Moat | PM2-specific scanning with env -i delete+start remediation pattern |
| Action | Build CLI tool, add CI/CD integration, publish to GitHub and npm |

**30-second pitch:** We found and eliminated 103 exposed secrets from our PM2 process list. Our scanner checks PM2 jlist, Docker env vars, and file permissions -- and tells you exactly how to fix each finding. `$100-500/mo` for automated scanning.

### #9: Claude Code Skills as Consulting Service

| Metric | Detail |
|--------|--------|
| Opportunity Score | 5.0/10 |
| Investment Required | 1 week (package offerings) |
| Revenue Path | $3K-10K/mo at 2-4 engagements/mo |
| Infrastructure | 20 custom skills proven in production |
| Blockers | No sales materials, no packaged delivery |
| Moat | Deep experience building domain-specific Claude Code skills |
| Action | Create skill development offering: assessment, build, deploy, train |

**30-second pitch:** We built 20 custom Claude Code skills for infrastructure management, security, deployment, and monitoring. Let us build domain-specific AI skills for your engineering team. 2-week engagement to identify, build, deploy, and train your team: `$10-20K`.

### #10: Wheeler Brain OS -- Enterprise Agent Platform

| Metric | Detail |
|--------|--------|
| Opportunity Score | 4.8/10 |
| Investment Required | 8-12 weeks (generalization + multi-tenant) |
| Revenue Path | $2K-8K/mo |
| Infrastructure | 50 agents, Neo4j graph, event bus PM2, command center |
| Blockers | Single-tenant, Wheeler-specific, no UI for external use |
| Moat | Ecosystem graph + agent coordination patterns are proprietary IP |
| Action | Abstract Wheeler-specific agents into domain templates, build multi-tenant orchestration, create external dashboard |

**30-second pitch:** Imagine 50 AI agents working together across infrastructure, security, revenue, deployment, and monitoring -- coordinated through a knowledge graph with an event bus and command center. That's Wheeler Brain OS. We'll build a version for your enterprise. 12-week engagement.

---

## 9. Product Category Pitches

### 9.1 SaaS Products ($2K-15K/mo per product)

| Product | Price | Target Market | Time to Launch |
|---------|-------|---------------|---------------|
| Prediction Radar | $49-199/mo | Individual investors, financial firms | 7 days (Stripe fix + signup flow) |
| SurplusAI | $997-2,997/mo | Law firms, real estate investors | 2 weeks (scraper fix + billing) |
| LiteLLM Gateway | $200-500/mo | SMBs using multiple LLMs | 3 weeks (multi-tenant) |
| Open Source Evaluator | $500/eval or $99/mo | Enterprise legal, procurement | 1 week (billing + web UI) |

**Combined SaaS ceiling:** $4,194-7,693/mo per client (assuming all 4 products, unlikely). Realistic: 2-3 products cross-sold at $500-2,000/mo average per client.

### 9.2 Marketplace ($5K-20K/mo)

| Product | Revenue Model | Target Market | Time to Launch |
|---------|---------------|---------------|---------------|
| Attorney Marketplace | 20-30% referral fee | Attorneys nationwide | 8-10 weeks to MVP |

Marketplaces are high-risk, high-reward. Requires critical mass on both sides. Wheeler has supply (6,725 case records) but needs attorney demand. Start with existing 4-attorney network, expand to 20, then productize.

### 9.3 Enterprise Offerings ($2K-10K/mo per client)

| Product | Price | Target Market | Time to Launch |
|---------|-------|---------------|---------------|
| AI Ops Managed Service | $500-2K/mo | SMBs needing hardened AI infra | 4-6 weeks |
| FRG Nationwide | Contingency (25-33%) | Surplus fund claimants | Immediate (unblock only) |
| Wheeler Brain | $2-5K/mo | Enterprises wanting agent orchestration | 8-12 weeks |

### 9.4 Consulting Services ($2K-10K/mo)

| Service | Price | Typical Duration | Available Now? |
|---------|-------|-----------------|---------------|
| Production Readiness Assessment | $5-15K | 1-2 weeks | YES |
| OSS Due Diligence | $500-1K | 1-2 days | YES |
| Claude Code Skill Development | $10-20K | 2 weeks | YES |
| Infrastructure Security Audit | $3-7K | 1 week | YES |
| Deployment Pipeline Design | $5-10K | 1-2 weeks | YES |

### 9.5 White-Label Candidates

| Product | White-Label Potential | Rebranding Effort | Target Partners |
|---------|----------------------|-------------------|-----------------|
| AI Ops Managed Service | HIGH | Moderate -- templated dashboards | MSPs, dev shops |
| SurplusAI | HIGH | High -- needs brand layer at $4,997/mo | Large law firms |
| Prediction Radar | MEDIUM | Moderate -- needs tenant CSS/domain | Financial platforms |
| Production Readiness | LOW | Low -- methodology not visual | Consulting firms |

---

## 10. Build vs. Productize Analysis

### 10.1 Systems Ready to Sell (Productize, Not Build)

These require zero or minimal new feature development:

| System | Gaps to Close | Effort | Revenue |
|--------|--------------|--------|---------|
| Prediction Radar | Stripe live keys, signup flow | 7 days | $2K-15K/mo |
| Production Readiness | Sales page, case study | 2 days | $2K-10K/mo |
| OSS Evaluator | Web UI, Stripe | 5 days | $2K-8K/mo |
| Secrets Scanner | CLI packaging, docs | 5 days | $1K-5K/mo |
| LiteLLM Gateway | Multi-tenant layer | 2 weeks | $2K-8K/mo |

### 10.2 Systems That Need Building First

These require significant new development:

| System | What Needs Building | Effort | Revenue |
|--------|-------------------|--------|---------|
| Attorney Marketplace | 6 PM2 services, frontend, routing engine | 8-10 weeks | $5K-20K/mo |
| SurplusAI Full Platform | Parser, scorer, billing, frontend | 6-8 weeks | $3K-10K/mo |
| AI Ops Managed Service | Multi-tenant, catalog, billing | 4-6 weeks | $2K-10K/mo |
| Wheeler Brain External | Generalization, UI, tenant isolation | 8-12 weeks | $2K-8K/mo |

### 10.3 Recommendation: Sequencing

**Immediate (Week 1):** Unblock FRG Nationwide + Prediction Radar Stripe. These are the highest-ROI actions in the entire map -- hours of work for thousands in potential monthly revenue.

**Short-term (Weeks 2-4):** Launch Production Readiness Assessment and OSS Evaluator as consulting services. Zero code, immediate revenue. Package LiteLLM Gateway as managed service.

**Medium-term (Weeks 4-8):** Stabilize SurplusAI scraper and ship the platform. Build AI Ops multi-tenant MVP.

**Long-term (Weeks 8-16):** Build Attorney Marketplace MVP. Begin Wheeler Brain generalization.

---

## 11. White-Label Candidate Assessment

### 11.1 Assessment Criteria

Each candidate scored on:
- **Customization Complexity:** How much work to rebrand and deploy per client?
- **Data Isolation:** Can we separate client data without rebuilding architecture?
- **Support Burden:** How much ongoing support does each deployment need?
- **Partner Value:** What's the revenue per partner?

### 11.2 White-Label Candidates

#### AI Ops Managed Service -- BEST FIT

| Criterion | Assessment |
|-----------|-----------|
| Customization Complexity | Medium -- templated dashboards, per-client Nginx configs, branded monitoring. Estimated 2 days per deployment once automated. |
| Data Isolation | Natural -- each client gets their own Docker compose stack. Coralogix-style shared vs. dedicated tier options. |
| Support Burden | Low-Medium -- self-healing engine handles most incidents. Client only contacts us for critical issues. |
| Partner Value | $500-2K/mo per client. MSPs would resell at 2-3x markup. Good partner economics. |
| **White-Label Score** | **8/10** -- productizable, isolatable, resellable. |

#### SurplusAI -- HIGH VALUE, HIGH COMPLEXITY

| Criterion | Assessment |
|-----------|-----------|
| Customization Complexity | High -- tenant branding, custom document templates, per-tenant AI model fine-tuning. Estimated 1 week per enterprise client. |
| Data Isolation | Phase 1: shared DB with tenant_id. Phase 2: dedicated schema. True white-label needs dedicated DB. |
| Support Burden | Medium -- scraping errors, data quality issues, county source changes require attention. |
| Partner Value | $4,997/mo white-label tier. Law firms would pay this for own-branded platform. |
| **White-Label Score** | **6/10** -- high revenue but high support. Best for enterprise tier only. |

#### Prediction Radar -- MODERATE FIT

| Criterion | Assessment |
|-----------|-----------|
| Customization Complexity | Low-Medium -- CSS theming, custom domain, feature flags. |
| Data Isolation | Per-tenant data in shared PostgreSQL with prompt security. |
| Support Burden | Low -- SaaS platform with standard ops. |
| Partner Value | Premium pricing on white-label tier. |
| **White-Label Score** | **5/10** -- possible but limited market for white-label prediction markets. |

---

## 12. Infrastructure Capacity for Productization

### 12.1 Current Headroom

| Resource | Total | Used | Free | Can Support |
|----------|-------|------|------|-------------|
| AIOPS vCPU | 16 | ~20% (3.2) | ~12.8 | ~4-6 additional microservices |
| AIOPS RAM | 32 GB | ~15 GB | ~17 GB | ~10 client deployments (containerized) |
| AIOPS Disk | 360 GB | ~61 GB | ~299 GB | ~200 GB document + DB storage |
| COREDB vCPU | 16 | ~15% | ~13.6 | Read replicas, additional databases |
| COREDB RAM | 32 GB | ~10 GB | ~22 GB | Additional databases, analytics |
| COREDB Disk | 360 GB | ~50 GB | ~310 GB | Data lake expansion |

### 12.2 Multi-Tenant Capacity Estimates

| Product | Per-Client Resource | Max Clients (Current Hardware) | Bottleneck |
|---------|--------------------|-------------------------------|------------|
| LiteLLM Gateway | 0.1 vCPU, 256MB RAM | 50+ | API rate limits, not compute |
| AI Ops Managed | 1 vCPU, 2GB RAM per stack | 8-12 | RAM from AIOPS node |
| SurplusAI | 0.5 vCPU, 1GB RAM per tenant | 16-20 | Scraper I/O, not compute |
| Prediction Radar | N/A (single-tenant SaaS) | N/A | Subscription model, not infra |

### 12.3 Scaling Constraints

- **AIOPS RAM is the primary constraint** for additional client-facing services. At 17GB free, each managed client at ~1.5GB = ~11 clients before headroom exhausted.
- **COREDB is underutilized** and can absorb database workloads for additional clients.
- **EDGE is being decommissioned** and should not host production client services.
- **First scaling investment:** Add a dedicated worker node (Hetzner CX32, ~$30/mo) when AIOPS reaches 70% RAM utilization.

### 12.4 Realistic Revenue Ceiling (Current Infrastructure)

| Scenario | Monthly Revenue | Infrastructure Needed |
|----------|---------------|----------------------|
| Conservative (unblock FRG + Prediction Radar only) | $2K-5K/mo | Current hardware (zero add'l) |
| Moderate (+ SurplusAI + consulting) | $8K-20K/mo | Current hardware |
| Aggressive (+ AI Ops managed + LiteLLM gateway) | $15K-40K/mo | Add 1 worker node (~$30/mo) |
| Full build (+ Attorney Marketplace + Brain) | $30K-70K/mo | Add 2-3 worker nodes (~$100/mo) |

---

## 13. Risk Register

### 13.1 Productization Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| COREDB remains unreachable | Medium | CRITICAL -- blocks FRG, PipelineDAG, all data flows | Phase 1 on local AIOPS PostgreSQL; redouble debug effort |
| Stripe production key causes compliance issues | Low | HIGH -- payment processing violations | Use Stripe Atlas or partner payment processor; legal review |
| Scraper crash-loop root cause is code bug | Medium | HIGH -- blocks SurplusAI revenue | Emergency delete+start; root cause analysis; rewrite lowest-quality adapter |
| Market doesn't need another prediction platform | Medium | MEDIUM -- Prediction Radar flops | Pivot to FRG-integrated tool (unique data edge) |
| AI Ops managed service too niche | Medium | MEDIUM -- limited SMB demand | Focus on existing network: dev shops, MSPs, Wheeler contacts |
| Attorney marketplace chicken-and-egg | High | MEDIUM -- no attorneys, no cases; no cases, no attorneys | Start with existing 4-attorney network; manual case routing until network builds |
| Support burden exceeds capacity | Medium | MEDIUM -- consulting clients require hand-holding | Set clear SLA boundaries; productize repeatable assessments; limit concurrent clients |
| White-label partner churn | Low | LOW -- partner loses branding investment | Annual contracts for white-label; data migration fee at termination |

### 13.2 Infrastructure Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AIOPS node failure | Low | CRITICAL -- all client services down | Document recovery procedure; daily backups; plan for HA in Phase 3 |
| Docker `:latest` tag reappears | Low | MEDIUM -- security violation | Automated daily audit; CI/CD gate in deployment engine |
| Secrets leak through productization | Low | HIGH -- client exposure | Separate env files per client; no shared secrets with client data |
| Disk exhaustion from document storage | Medium | MEDIUM -- blocks SurplusAI | Monitor disk usage; archive old cases; add Hetzner volume |
| API provider rate limiting under load | Medium | MEDIUM -- degrades AI features | LiteLLM fallback chains; caching layer; usage tiering |

---

## 14. Recommendations and Roadmap

### 14.1 Immediate Actions (This Week)

| Priority | Action | Effort | Impact | Owner |
|----------|--------|--------|--------|-------|
| P0 | Fix DEEPSEEK_API_KEY in frgcrm-api | 30min | Unblocks FRG Nationwide, SurplusAI scoring | DevOps |
| P0 | Debug COREDB PostgreSQL connectivity | 2-4h | Unblocks all data flows, PipelineDAG | Infra |
| P0 | Switch Prediction Radar Stripe to live | 1h | Enables SaaS subscription revenue | DevOps |
| P1 | Emergency stabilize surplusai-scraper | 1h | Unblocks SurplusAI data pipeline | Agent Team |
| P1 | Emergency stabilize voice-agent-svc | 1h | Unblocks claimant outreach | Agent Team |
| P2 | Create Production Readiness sales page | 1 day | Opens consulting revenue stream | Marketing |

### 14.2 Week 2-4 Actions

| Action | Effort | Expected Revenue |
|--------|--------|-----------------|
| Prediction Radar signup flow + pricing page | 5 days | $2K-5K/mo |
| FRG case migration (6,603 from EDGE) | 1 day | $5K-15K/mo |
| License Verification Worker for Attorney Marketplace | 3 days | Enables attorney onboarding |
| OSS Evaluator web UI + Stripe | 3 days | $2K-4K/mo |
| LiteLLM multi-tenant layer | 5 days | $2K-4K/mo |
| PipelineDAG repair | 3 days | Unblocks all automated flows |

### 14.3 Month 2 Actions

| Action | Effort | Expected Revenue |
|--------|--------|-----------------|
| SurplusAI adapter framework + top 5 counties | 2 weeks | Enables $3K-10K/mo |
| AI Ops service catalog + pricing | 1 week | Enables $2K-10K/mo |
| Secrets Scanner CLI packaging | 1 week | $1K-3K/mo |
| Attorney Marketplace Phase 1 | 2 weeks | Enables $2K-5K/mo |

### 14.4 Month 3+ Actions

| Action | Effort | Expected Revenue |
|--------|--------|-----------------|
| Attorney Marketplace Phase 2+3 | 6 weeks | $5K-20K/mo |
| AI Ops multi-tenant | 3 weeks | $2K-10K/mo |
| Wheeler Brain generalization | 6-8 weeks | $2K-5K/mo |
| AI Acquisition Engine build | 4-6 weeks | $3K-8K/mo |

### 14.5 Revenue Projection (Cumulative)

| Timeline | Conservative | Moderate | Aggressive |
|----------|-------------|----------|------------|
| Week 1 | $0 (unblocking) | $0 (unblocking) | $0 (unblocking) |
| Week 4 | $2K-5K/mo | $4K-8K/mo | $6K-12K/mo |
| Month 2 | $5K-10K/mo | $8K-15K/mo | $12K-25K/mo |
| Month 3 | $8K-18K/mo | $15K-30K/mo | $25K-50K/mo |
| Month 6 | $15K-30K/mo | $25K-50K/mo | $40K-80K/mo |

### 14.6 Final Recommendation

**Do not build anything new until the 3 revenue blockers are fixed.**

The three P0/P1 issues (DEEPSEEK_API_KEY, COREDB connectivity, scraper crash-loop) are blocking revenue from systems that are otherwise deployed and ready. Every hour spent on new features while these blockers exist is time spent building products that cannot generate revenue.

Once unblocked:

1. **Ship Prediction Radar first** (7 days, $2K-15K/mo). Closest to revenue. Stripe is configured, containers are healthy, market exists.
2. **Unblock FRG Nationwide second** (hours, $5K-15K/mo). Highest immediate revenue potential per hour invested. Fix env var, fix DB connection, ship cases.
3. **Productize Production Readiness Assessment third** (2 days, $2K-10K/mo). Zero build, immediate consulting revenue, proves the productization model.
4. **Build SurplusAI fourth** (2 weeks, $3K-10K/mo). Strong moat, higher price point, serves internal intelligence needs.
5. **Build Attorney Marketplace fifth** (8-10 weeks, $5K-20K/mo). Highest long-term revenue ceiling but requires sustained build effort.

---

## Appendix A: Quick Reference -- All Systems and Their Product Classification

| System | Category | Classification | Immediate Revenue? |
|--------|----------|---------------|:-----------------:|
| FRG Nationwide Engine | Revenue | Enterprise Offering | Yes (unblock) |
| SurplusAI Platform | Revenue | SaaS Product | No (blocked) |
| Attorney Marketplace | Revenue | Marketplace | No (not built) |
| Ravyn Capital | Revenue | Internal-Only | No |
| Prediction Radar | Revenue | SaaS Product | YES (7 days) |
| AI Ops Infrastructure | Revenue/Infra | Enterprise Offering | No (4-6 weeks) |
| Wheeler Brain OS | Revenue/Intelligence | Internal-Only | No (8-12 weeks) |
| Lead Intelligence | Revenue | Internal-Only | No |
| Deployment Engine | Infrastructure | Internal-Only | No |
| Rollback Engine | Infrastructure | Internal-Only | No |
| Monitoring Stack | Infrastructure | Enterprise Offering | Add-on |
| Analytics Stack | Infrastructure | Internal-Only | No |
| LiteLLM Gateway | Infrastructure | SaaS Product | YES (2 weeks) |
| DocuSeal | Infrastructure | Internal-Only | No |
| Usesend | Infrastructure | Internal-Only | No |
| Open WebUI | Infrastructure | Internal-Only | No |
| Changedetection | Infrastructure | Internal-Only | No |
| Secrets Scanner | Security | API Product | YES (1 week) |
| Production Readiness | Methodology | Consulting Service | YES (now) |
| OSS Evaluator | Methodology | Consulting/API | YES (1 week) |
| Repo Audit | Methodology | Consulting Service | YES (now) |
| No-False-Greens | Methodology | White-Label Candidate | Add-on |
| PipelineDAG | Data Pipeline | Internal-Only | No |
| Revenue Dashboards | Reporting | SaaS Product | Add-on |
| AI Acquisition Engine | Marketing | SaaS Product | No (not built) |
| Self-Healing Engine | Automation | Enterprise Offering | Add-on |

---

## Appendix B: Infrastructure Reference

### B.1 AIOPS Port Map (Selected Revenue-Critical Ports)

| Port | Service | Product | Revenue Critical? |
|------|---------|---------|:-----------------:|
| 443 | Nginx HTTPS | All | YES |
| 3002 | Grafana | AI Ops | YES |
| 3003 | SurplusAI Frontend | SurplusAI | YES |
| 3007 | Usesend | Attorney | YES |
| 3010 | DocuSeal | Attorney | YES |
| 4049 | LiteLLM | AI Gateway | YES |
| 5432 | Prediction Radar DB | Prediction Radar | YES |
| 5433 | frgops-standby | FRG | YES |
| 5434 | ravynai-postgres | Ravyn | NO |
| 7474 | Neo4j | Brain | YES |
| 7687 | Neo4j Bolt | Brain | YES |
| 8007 | ravynai-app | Ravyn | NO |
| 8082 | frgcrm-api | FRG | YES |
| 8098 | Prediction Radar Web | Prediction Radar | YES |
| 8100 | Command Center | Brain | YES |
| 8103 | SurplusAI API | SurplusAI | YES |

### B.2 Docker Compose Stacks (12)

| Stack | Products Served |
|-------|----------------|
| /opt/apps/monitoring/ | AI Ops |
| /opt/apps/prediction-radar-app/ | Prediction Radar |
| /opt/apps/analytics/ | AI Ops, SurplusAI |
| /opt/apps/langflow/ | AI Ops |
| /opt/apps/docuseal/ | Attorney Marketplace |
| /opt/apps/healthchecks/ | AI Ops |
| /opt/apps/changedetection/ | AI Ops |
| /opt/apps/ravynai-opportunity-graph/ | Ravyn Capital |
| /opt/apps/usesend/ | Attorney Marketplace |
| /opt/open-webui/ | AI Ops |
| /opt/stacks/temporal/ | All |
| /opt/stacks/02-aiops/ | AI Ops |

### B.3 Claude Code Skills by Product Category

| Skill | Product Category |
|-------|-----------------|
| slay | Managed AI Ops |
| production-readiness | Consulting |
| repo-audit | Consulting |
| open-source-repo-evaluator | Consulting/API |
| secrets-scan | API Product |
| docker-health | Managed AI Ops |
| pm2-recovery | Managed AI Ops |
| agent-workflow-builder | Enterprise |
| aiops-control-plane-operator | Managed AI Ops |
| database-lockdown | Security Consulting |
| no-false-greens | Methodology IP |

---

*End of Wheeler Ecosystem Productization Map v1.0.0*

**Next Review Date:** 2026-06-24
**Owner:** Wheeler Brain OS -- Revenue Engineering
**Related Documents:**
- /root/WHEELER_REVENUE_ENGINE_ARCHITECTURE.md (revenue architecture)
- /root/AUTONOMOUS_AIOPS_ARCHITECTURE.md (infrastructure)
- /root/SURPLUSAI_PRODUCTIZATION_PLAN.md (SurplusAI product plan)
- /root/ATTORNEY_MARKETPLACE_ARCHITECTURE.md (marketplace plan)
- /root/FRG_NATIONWIDE_ENGINE.md (FRG engine)
- /root/REVENUE_AUTOMATION_FRAMEWORK.md (governance)
- /root/MASTER_EXECUTION_STATE.md (execution state)
- /root/STAGE2_QA_SCORECARD_FINAL.md (QA validation)
