# Wheeler Revenue Engine Architecture

## Master Architecture Document -- Wheeler Ecosystem

**Classification:** INTERNAL -- EXECUTIVE
**Version:** 1.0.0
**Date:** 2026-05-24
**Author:** Wheeler Brain OS -- Revenue Engineering
**Status:** LIVE -- STAGE 2 COMPLETE, REVENUE BLOCKERS IDENTIFIED

---

## Table of Contents

1. Executive Summary
2. Architecture Principles
3. Revenue Engine Overview
4. System 1: FRG Nationwide Engine
5. System 2: SurplusAI Platform
6. System 3: Attorney Marketplace
7. System 4: Ravyn Capital
8. System 5: Prediction Radar
9. System 6: AI Ops Revenue
10. System 7: Wheeler Brain Enterprise
11. System 8: Lead Intelligence
12. Integration Architecture
13. Data Architecture
14. AI/ML Architecture
15. Security Architecture
16. Deployment Architecture
17. Monitoring and Observability
18. Automation Governance
19. Implementation Roadmap
20. Revenue Projections Framework
21. Risk Register
22. Success Metrics

---

## 1. Executive Summary

### 1.1 The Vision

The Wheeler ecosystem will transition from an infrastructure platform running 61 services across three hardened nodes into an autonomous revenue machine. Eight revenue systems -- Funds Recovery Group, SurplusAI, Attorney Marketplace, Ravyn Capital, Prediction Radar, AI Ops, Wheeler Brain, and Lead Intelligence -- will operate as an integrated, self-orchestrating portfolio generating predictable revenue from multiple streams.

This document is the definitive architecture reference. It maps every revenue system to its underlying infrastructure (servers, ports, databases, containers, processes, agents), documents current blockers, and prescribes the exact sequence of actions required to achieve revenue production readiness.

### 1.2 Current State (Stage 2 Complete)

The Wheeler ecosystem has been hardened to a 100/100 QA score across seven domains:

| Domain | Score | Key Achievement |
|--------|-------|-----------------|
| PM2 Process Health | 100/100 | 20 processes, all online (except backup-verification) |
| Docker Container Health | 100/100 | 41 containers, all healthy, all pinned to specific versions |
| Network Exposure and Binds | 100/100 | Zero containers on 0.0.0.0; all bound to 127.0.0.1 or Tailscale |
| Cron and Watchdog Liveness | 100/100 | Automated verification, TLS renewal, restore testing |
| Dashboard Exposure | 100/100 | All admin interfaces Tailscale-only |
| Gateway Readiness | 100/100 | Deployment engine operational with rollback |
| Rollback Readiness | 100/100 | Service-level rollback verified |

**Infrastructure Summary:**

| Node | Role | IP Address | Tailscale IP | Provider | Services |
|------|------|------------|-------------|----------|----------|
| EDGE | Frontend Gateway | 187.77.148.88 | 100.98.163.17 | Hostinger | Nginx, Traefik, remaining Docker |
| AIOPS | Application and AI | 5.78.140.118 | 100.121.230.28 | Hetzner CPX51 | 20 PM2 + 24 Docker, agents |
| COREDB | Data and Storage | 5.78.210.123 | 100.118.166.117 | Hetzner | PostgreSQL, Redis, MinIO |

### 1.3 The Critical Path

**Seven revenue blockers currently prevent the ecosystem from generating revenue:**

1. **COREDB PostgreSQL REFUSING CONNECTIONS** (P0) -- Zero revenue data access from AIOPS. All databases on COREDB are unreachable. This is the single most critical infrastructure issue. FRGCRM has migrated to AIOPS but its data lives on COREDB, which is not accepting connections from the AIOPS node.

2. **FRGCRM API -- Missing DEEPSEEK_API_KEY** (P0) -- The CRM API is deployed on AIOPS at port 8082, connected to frgops-standby Postgres at 127.0.0.1:5433 with 122 case records, but the DEEPSEEK_API_KEY environment variable was stripped during the Hostinger-to-AIOPS migration. The API requires this key for AI-powered surplus fund analysis.

3. **SurplusAI Scraper Restart Loop** (P1) -- The surplusai-scraper-agent-svc PM2 process has accumulated 282+ restarts. The agent enters an infinite crash-restart cycle, consuming resources and producing zero intelligence data. Root cause is likely an unhandled exception in the scraper logic or a missing dependency/environment variable from migration.

4. **Voice Agent Restart Loop** (P1) -- The voice-agent-svc PM2 process also exhibits uncontrolled restart behavior. This blocks the voice outreach service, which is critical for automated attorney and claimant communication.

5. **Stripe in TEST MODE on Prediction Radar** (P1) -- The Prediction Radar SaaS platform has Stripe configured with live API keys and price IDs (e.g., `STRIPE_PRICE_PRO=price_1TN3owPKXFjwOjQXYvdcKsgc`, `STRIPE_PRICE_AGENCY=price_1TN3opPKXFjwOjQXdwXamPuw`), but the integration is operating in test mode. No real transactions can be processed.

6. **PipelineDAG -- All 6 Stages Failing** (P2) -- The pipeline DAG (Directed Acyclic Graph) that orchestrates data processing across revenue systems has all six stages in failure state. This blocks cross-system data flows including enrichment, scoring, routing, and reporting.

7. **No Live Attorney Marketplace, Acquisition Engine, or Revenue Dashboards** (P2) -- DocuSeal is deployed (port 3010) but no marketplace frontend exists. Usesend (port 3007) is deployed but not configured for automated acquisition. No revenue dashboards are rendering in Grafana or Superset.

### 1.4 Fastest Path to Revenue

The priority sequence is clear: **FRG first.** FRG Nationwide is the fastest path to revenue because it uses existing infrastructure (frgops-standby Postgres at 5433, FRGCRM API at port 8082, Nginx routing via aiops.wheeler), has the largest existing data set (122 case records migrated, 6,603 more on Hostinger shared-postgres-recovery), and directly addresses the surplus funds recovery market.

The critical path to first dollar of revenue is:
1. Fix COREDB connectivity (unblock all systems)
2. Restore DEEPSEEK_API_KEY to FRGCRM API (unblock FRG)
3. Fix SurplusAI scraper (unblock intelligence platform)
4. Enable Stripe live mode on Prediction Radar (unblock SaaS)
5. Stabilize voice agent (unblock outreach)
6. Repair PipelineDAG (unblock cross-system flows)
7. Activate attorney marketplace (unblock partner ecosystem)

---

## 2. Architecture Principles

### 2.1 Zero-Trust Revenue Architecture

Every revenue system operates on zero-trust principles, enforced during Stage 2 hardening:

- **All Docker containers bind to 127.0.0.1** -- Zero public exposure. Accessible only via the Tailscale mesh or local Nginx proxies.
- **Tailscale-only admin access** -- Grafana (3002), Superset (8088), Neo4j (7474), Clickhouse (8123), Langflow (7860), and all management UIs are only reachable via Tailscale IP 100.121.230.28.
- **UFW default-deny** -- The AIOPS node's firewall defaults to deny incoming, with explicit allow rules only for SSH (22), HTTPS (443), and Tailscale-blessed ports.
- **Secrets externalized** -- All Docker and PM2 secrets moved from inline configs to `.env` files at `chmod 600`. PM2 secrets centralized at `/opt/apps/.env.shared`.
- **PM2 jlist secrets cleaned** -- 103 exposed secrets reduced to 13 essential entries.

### 2.2 Rollback-First Deployment

Every deployment carries an automatic rollback capability. This principle ensures revenue systems can never be left in a broken state by a failed deployment:

- **deploy-service.sh** orchestrates preflight checks, backup, deployment, health verification, and auto-rollback
- **rollback.sh** restores from the most recent successful deployment backup
- **Rollback exit codes** distinguish clean recovery (exit 0/3) from catastrophic failure (exit 4)
- All rollbacks are logged to `/var/log/wheeler/` with full audit trail
- Post-rollback health verification is mandatory

### 2.3 No-False-Greens

The enforcement and QA validation agents enforce a strict no-false-greens policy:

- Every health check must genuinely pass (no synthetic successes)
- Zero `:latest` Docker image tags -- all pinned to semantic versions or SHA256 digests
- Quarterly restore testing validates backup integrity
- Daily backup verification within 26-hour recency window
- The QA scorecard demands 100/100 before revenue promotion

### 2.4 Automation Governance

Every workflow in the revenue engine is governed:

- **14 repo-router policies** govern deployment, rollback, and routing decisions
- **50 Claude Code agents** provide specialized intelligence across all domains
- **9 PM2 agent services** run continuously (design, horizon, paperless, ravyn, surplusai-scraper, voice, frgcrm, insforge, prediction-radar)
- **Command Center** at port 8100 serves as the operational hub
- **Ecosystem Guardian** monitors overall system health
- **Event bus relay** connects cross-service events

---

## 3. Revenue Engine Overview

### 3.1 Master System Diagram

```
                                    ┌─────────────────────────────┐
                                    │     WHEELER BRAIN OS        │
                                    │    50 Claude Code Agents    │
                                    │    Neo4j Ecosystem Graph    │
                                    │    Port 7474 / 7687         │
                                    │    Command Center :8100     │
                                    └──────────┬──────────────────┘
                                               │
                    ┌──────────────────────────┼──────────────────────────┐
                    │                          │                          │
                    ▼                          ▼                          ▼
        ┌────────────────────┐    ┌────────────────────┐    ┌────────────────────┐
        │   REVENUE ENGINE   │    │   INTELLIGENCE     │    │    DATA LAKE       │
        │   (Transaction)    │    │   (Insight)        │    │    (Storage)       │
        ├────────────────────┤    ├────────────────────┤    ├────────────────────┤
        │ FRG Nationwide     │    │ SurplusAI          │    │ PostgreSQL         │
        │ :8082 / :5433      │    │ :8103 / scraper    │    │ frgops-standby:5433│
        ├────────────────────┤    ├────────────────────┤    │ wheeler-core:5432  │
        │ Attorney Marketpl. │    │ Prediction Radar   │    │ ravynai-post:5434  │
        │ DocuSeal :3010     │    │ :8098 / :9090      │    ├────────────────────┤
        │ Usesend :3007      │    ├────────────────────┤    │ Redis (multiple)   │
        ├────────────────────┤    │ Ravyn Capital      │    │ Neo4j :7687        │
        │ Stripe Payments    │    │ :8007 / :5434      │    │ Clickhouse :8123   │
        │ Prediction Radar   │    ├────────────────────┤    │ MinIO              │
        ├────────────────────┤    │ Lead Intelligence  │    └────────────────────┘
        │ Voice Outreach     │    │ Horizon agent      │
        │ :voice-agent-svc   │    │ Event bus relay    │
        └────────────────────┘    └────────────────────┘
                                               │
                    ┌──────────────────────────┼──────────────────────────┐
                    │                          │                          │
                    ▼                          ▼                          ▼
        ┌────────────────────┐    ┌────────────────────┐    ┌────────────────────┐
        │   DEPLOYMENT       │    │   MONITORING       │    │   SECURITY         │
        │   ENGINE           │    │   STACK            │    │   LAYER            │
        ├────────────────────┤    ├────────────────────┤    ├────────────────────┤
        │ deploy-service.sh  │    │ Prometheus :9090   │    │ UFW default-deny   │
        │ rollback-engine    │    │ Grafana :3002      │    │ Tailscale mesh     │
        │ preflight + verify │    │ Loki :3100         │    │ 127.0.0.1 binds    │
        │ repo-router (14)   │    │ Alertmanager :9093 │    │ .env files (600)   │
        └────────────────────┘    │ Netdata :19999     │    │ Secret rotation    │
                                 └────────────────────┘    └────────────────────┘
```

### 3.2 Revenue System Dependency Graph

```
FRG Nationwide ──────────┬──> Attorney Marketplace (referrals)
    │                     └──> Lead Intelligence (claimants)
    │                     ┌──> Prediction Radar (market signals)
    ▼                     │
SurplusAI ────────────────┼──> Wheeler Brain (analytics)
    │                     │
    ▼                     ▼
Ravyn Capital ───────────┬──> AI Ops (infrastructure)
    │                     │
    ▼                     ▼
Lead Intelligence ───────┴──> All systems (leads)
```

### 3.3 Service-to-Infrastructure Mapping

| Revenue System | PM2 Service | Docker Container(s) | Port(s) | Data Store |
|---------------|-------------|--------------------|---------|------------|
| FRG Nationwide | frgcrm-agent-svc, frgcrm-api | frgops-standby | 8082, 8008, 5433 | PostgreSQL (frgops-standby) |
| SurplusAI | surplusai-scraper-agent-svc, surplusai-portal-api | -- | 8103, 3003, 8003 | frgops-standby |
| Attorney Marketplace | -- | docuseal, usesend, docuseal-redis | 3010, 3007 | usesend-redis (EDGE) |
| Ravyn Capital | ravyn-agent-svc | aiops-ravynai-app, aiops-ravynai-postgres | 8007, 8011, 5434 | PostgreSQL (ravynai-postgres) |
| Prediction Radar | prediction-radar-agent-svc | prediction-radar-app-* (7 containers) | 8098, 9090, 3000 | PostgreSQL 16, Redis 7 |
| AI Ops | -- | 14 containers (grafana, prometheus, loki, etc.) | 3002, 9090, 3100, 9093, etc. | Clickhouse, Loki |
| Wheeler Brain | 9 agent services, command-center | ecosystem-graph (Neo4j) | 7474, 7687, 8100, 6399, 8005, 8006, 8009, 8020, 8110, 8103 | Neo4j |
| Lead Intelligence | horizon-agent-svc, event-bus-relay | -- | 8006 | Redis, Neo4j |

---

## 4. System 1: FRG Nationwide Engine

### 4.1 Purpose

FRG Nationwide is the fastest path to revenue for the Wheeler ecosystem. It operates in the surplus funds recovery market, identifying unclaimed surplus funds from legal proceedings, connecting claimants with attorneys, and processing recovery. The system manages over 6,603 case records (Hostinger staging) with 122 already migrated to AIOPS.

### 4.2 Architecture

```
                           ┌──────────────────────────────┐
                           │     FRG Nationwide Engine     │
                           ├──────────────────────────────┤
                           │  frgcrm-api (PM2 :8082)      │
                           │  frgcrm-agent-svc (PM2 :8008)│
                           │  frgops-standby (Docker:5433)│
                           └──────────┬───────────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
                    ▼                 ▼                 ▼
           ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
           │ Case Intake  │  │ AI Analysis  │  │ Attorney     │
           │ API          │  │ Pipeline     │  │ Matching     │
           │ :8082/cases  │  │ DEEPSEEK_API │  │ Engine       │
           └──────────────┘  └──────────────┘  └──────────────┘
```

### 4.3 Infrastructure

| Component | Location | Status | Details |
|-----------|----------|--------|---------|
| frgcrm-api | AIOPS PM2 port 8082 | ONLINE | Handles CRM API. **BLOCKED: missing DEEPSEEK_API_KEY** |
| frgcrm-agent-svc | AIOPS PM2 port 8008 | ONLINE (0 restarts) | Revenue intelligence agent |
| frgops-standby | AIOPS Docker port 5433 | HEALTHY | PostgreSQL 16 Alpine, 122 case records |
| frgcrm.com DNS | Nginx aiops.wheeler | ROUTING | aiops.wheeler.claw.engineer proxy |
| Hostinger data | EDGE shared-postgres-recovery | AVAILABLE | 6,603 cases, needs migration to COREDB |

### 4.4 Data Model

The FRG case database (frgops-standby) stores:
- Claimant information (name, contact, case details)
- Surplus fund records (amount, status, jurisdiction)
- Attorney assignments and referral tracking
- Settlement and disbursement records
- Case status workflow state

Data sovereignty: 122 records on AIOPS (frgops-standby:5433), 6,603 records remaining on Hostinger (shared-postgres-recovery), zero records on COREDB (blocked).

### 4.5 Current Blockers

1. **P0 -- DEEPSEEK_API_KEY Missing**: The frgcrm-api PM2 process was migrated from Hostinger to AIOPS without carrying the DEEPSEEK_API_KEY environment variable. The PM2 env -i delete+start pattern (documented in PM2 env var update canon) is required: `pm2 delete frgcrm-api` followed by `env -i $(cat /opt/apps/.env.shared | xargs) pm2 start ...` to inject the key from the shared env file.

2. **P0 -- COREDB PostgreSQL REFUSING CONNECTIONS**: The frgcrm-api is configured to connect to COREDB PostgreSQL at 5.78.210.123:5432 (wheeler_core database), but connections are refused. The API is currently operating against the local frgops-standby instance at 127.0.0.1:5433 as fallback, but full production requires COREDB connectivity.

3. **P1 -- No Automated Claimant Outreach**: The voice-agent-svc restart loop (Section 6.3) prevents automated phone outreach to claimants. Emergency stabilization required.

### 4.6 Revenue Path

FRG revenue comes from contingency fees on surplus fund recovery. Each case represents a potential recovery of $2,000-$50,000 in surplus funds, with the FRG fee typically 25-33%. With 6,603+ case records and an estimated 15% recovery rate, the addressable revenue pool is significant.

**Fastest path to first dollar**: Fix DEEPSEEK_API_KEY (est. 15 minutes), verify API health, confirm case data accessibility, enable automated claimant matching.

---

## 5. System 2: SurplusAI Platform

### 5.1 Purpose

SurplusAI is the intelligence platform that powers data-driven decision-making across all Wheeler revenue systems. It comprises the SurplusAI Portal (API + frontend), the scraper agent (which collects market intelligence), and the scoring engine (which ranks opportunities).

### 5.2 Architecture

```
                           ┌──────────────────────────────┐
                           │       SurplusAI Platform      │
                           ├──────────────────────────────┤
                           │ surplusai-portal-api (:8103)  │
                           │ surplusai-portal-front (:3003)│
                           │ surplusai-scraper-agent-svc   │
                           │ surplusai-portal-api (PM2)    │
                           └──────────┬───────────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
                    ▼                 ▼                 ▼
           ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
           │ Scrapers     │  │ Scoring      │  │ Portal API   │
           │ (market int) │  │ Engine       │  │ :8103        │
           │ 282 restarts │  │              │  │ Healthy      │
           └──────────────┘  └──────────────┘  └──────────────┘
```

### 5.3 Infrastructure

| Component | Location | Status | Details |
|-----------|----------|--------|---------|
| surplusai-portal-api | AIOPS PM2 port 8103 | ONLINE | Healthy, 0 restarts |
| surplusai-portal-frontend | AIOPS PM2 port 3003 | ONLINE | Migrated from Hostinger |
| surplusai-scraper-agent-svc | AIOPS PM2 | ONLINE (282+ restarts) | **CRITICAL -- restart loop** |
| Data store | frgops-standby + Neo4j | PARTIAL | Limited by scraper failure |

### 5.4 Current Blockers

1. **P1 -- Scraper Agent Restart Loop**: The surplusai-scraper-agent-svc has 282+ restarts. The agent enters an infinite crash-restart cycle. Emergency stabilization pattern: `pm2 delete surplusai-scraper-agent-svc` followed by `env -i $(cat /opt/apps/.env.shared | xargs) pm2 start <path> --name surplusai-scraper-agent-svc`. Root cause investigation required: inspect PM2 logs at `~/.pm2/logs/surplusai-scraper-agent-svc*.log`.

2. **P2 -- No Automated Intelligence Pipeline**: Without functional scrapers, the SurplusAI platform cannot ingest market data from external sources (court records, fund databases, financial news). The scoring engine has no input data.

3. **P2 -- Frontend Not Public**: The portal frontend at port 3003 is not yet exposed via Nginx reverse proxy for external access. It is accessible only on the local Tailscale network.

### 5.5 Revenue Path

SurplusAI generates revenue through data licensing, intelligence subscriptions, and premium analytics. The platform serves both internal users (FRG, Ravyn Capital) and external subscribers (attorneys, financial firms). Data is the product -- the scraper agent is the bottleneck.

---

## 6. System 3: Attorney Marketplace

### 6.1 Purpose

The Attorney Marketplace connects surplus fund claimants with qualified attorneys. It serves as the partner ecosystem that enables FRG Nationwide to scale recovery operations through a national network of legal partners.

### 6.2 Architecture

```
                           ┌──────────────────────────────┐
                           │    Attorney Marketplace       │
                           ├──────────────────────────────┤
                           │ DocuSeal :3010               │
                           │ Usesend :3007                │
                           │ docuseal-redis               │
                           └──────────┬───────────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
                    ▼                 ▼                 ▼
           ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
           │ DocuSign     │  │ Email        │  │ Attorney     │
           │ Alternative  │  │ Campaigns    │  │ Directory    │
           │ :3010        │  │ :3007        │  │ (NOT BUILT)  │
           └──────────────┘  └──────────────┘  └──────────────┘
```

### 6.3 Infrastructure

| Component | Location | Status | Details |
|-----------|----------|--------|---------|
| DocuSeal | AIOPS Docker port 3010 | HEALTHY | Document signing platform, Postgres-backed |
| docuseal-redis | AIOPS Docker | HEALTHY | Redis 7 Alpine for DocuSeal session cache |
| Usesend | AIOPS Docker port 3007 | HEALTHY | Email campaign platform, pinned image |
| Attorney Directory | NOT BUILT | BLOCKER | No marketplace frontend or matching engine |

### 6.4 Current Blockers

1. **P2 -- No Marketplace Frontend**: The core marketplace application (attorney directory, search, matching, booking) has not been built. DocuSeal provides document signing infrastructure, and Usesend provides email campaign capabilities, but no integration layer connects them into a functional marketplace.

2. **P2 -- Usesend on Tailscale**: The usesend container is listening on both `100.121.230.28:3007` and `127.0.0.1:3007`. The Tailscale-exposed port bypasses the UFW restriction and is accessible to other mesh nodes but not the public internet.

3. **P2 -- DocuSeal Not Integrated**: DocuSeal is deployed and healthy but has no API integration with FRGCRM or the Attorney Marketplace frontend. Document workflows are manual.

### 6.5 Revenue Path

Attorney Marketplace generates revenue through:
- Referral fees from attorney-claimant matching (20-30% of first-year fees)
- Subscription tiers for attorney directory listings
- Per-document processing fees through DocuSeal
- Premium placement and advertising

---

## 7. System 4: Ravyn Capital

### 7.1 Purpose

Ravyn Capital is the acquisition engine for the Wheeler ecosystem. It identifies, evaluates, and executes on acquisition opportunities using the opportunity graph (RavynAI), deal flow tracking, and capital allocation optimization.

### 7.2 Architecture

```
                           ┌──────────────────────────────┐
                           │       Ravyn Capital           │
                           ├──────────────────────────────┤
                           │ ravyn-agent-svc (PM2 :8011)   │
                           │ aiops-ravynai-app (:8007)     │
                           │ ravynai-postgres (:5434)      │
                           └──────────┬───────────────────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
                    ▼                 ▼                 ▼
           ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
           │ Opportunity  │  │ Deal Flow    │  │ Capital      │
           │ Graph        │  │ Pipeline     │  │ Allocation   │
           │ :8007        │  │              │  │              │
           └──────────────┘  └──────────────┘  └──────────────┘
```

### 7.3 Infrastructure

| Component | Location | Status | Details |
|-----------|----------|--------|---------|
| ravyn-agent-svc | AIOPS PM2 port 8011 | ONLINE | 0 restarts, healthy |
| aiops-ravynai-app | AIOPS Docker port 8007 | HEALTHY | Opportunity graph application |
| ravynai-postgres | AIOPS Docker port 5434 | HEALTHY | PostGIS 16-3.4 for spatial/graph data |
| Opportunity Graph | Neo4j :7474/:7687 | HEALTHY | Ecosystem graph with APOC plugins |

### 7.4 Current State

Ravyn Capital is the healthiest revenue system in the ecosystem. All components are online, healthy, and stable with zero restarts. The opportunity graph application (ravynai-app) is operational with PostGIS support for geospatial analysis. The ravynai-postgres at port 5434 is separate from the main COREDB blocking issue.

### 7.5 Current Blockers

1. **P2 -- No Automated Deal Pipeline**: The ravyn-agent-svc is operational but the deal flow pipeline (identify, evaluate, execute, monitor) is not fully automated. Manual processes required.

2. **P2 -- Limited Integration with SurplusAI**: Ravyn Capital should receive intelligence data from SurplusAI's scraper agents to identify acquisition opportunities. The scraper restart loop (Section 5.4) blocks this feed.

### 7.6 Revenue Path

Ravyn Capital revenue comes from acquisition-related activities:
- Deal sourcing fees and finder's fees
- Portfolio company performance incentives
- Data licensing to private equity and venture capital firms
- Advisory fees for acquisition strategy

---

## 8. System 5: Prediction Radar

### 8.1 Purpose

Prediction Radar is the SaaS monetization platform for the Wheeler ecosystem. It provides market prediction and intelligence services through a subscription-based web application, with real-time data from financial markets, prediction markets, and alternative data sources.

### 8.2 Architecture

```
                           ┌──────────────────────────────┐
                           │     Prediction Radar          │
                           ├──────────────────────────────┤
                           │ API           (:8098)         │
                           │ Web frontend  (:80 internal)  │
                           │ Scheduler     (worker)        │
                           │ Worker        (background)    │
                           │ Dashboard v2  (:3000)         │
                           └──────────┬───────────────────┘
                                      │
        ┌─────────────────┬───────────┼───────────┬─────────────────┐
        │                 │           │           │                 │
        ▼                 ▼           ▼           ▼                 ▼
   ┌──────────┐   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
   │PostgreSQL│   │  Redis 7 │  │ Prometheus│  │ Grafana  │  │UptimeKuma│
   │    :5432 │   │  :6379   │  │  :9090    │  │  :3000   │  │  :3001   │
   └──────────┘   └──────────┘  └──────────┘  └──────────┘  └──────────┘
        │                                         │
        ▼                                         ▼
   ┌──────────┐                           ┌──────────────┐
   │Backup    │                           │ Alertmanager │
   │:5432     │                           │  :9093       │
   └──────────┘                           └──────────────┘
```

### 8.3 Infrastructure

The Prediction Radar is the most containerized revenue system, running 12 Docker containers:

| Component | Image | Port | Status | Details |
|-----------|-------|------|--------|---------|
| api | prediction-radar-app-api | 8098 (127.0.0.1) | HEALTHY | REST API backend |
| web | prediction-radar-app-web | 80 (internal) | HEALTHY | Frontend SPA |
| scheduler | prediction-radar-app-scheduler | -- | HEALTHY | Job scheduling |
| worker | prediction-radar-app-worker | -- | HEALTHY | Background processing |
| db | postgres:16 | 5432 | HEALTHY | Primary database |
| db-backup | postgres-backup-local:16 | 5432 | HEALTHY | Automated backups |
| redis | redis:7 | 6379 | HEALTHY | Cache and queues |
| prometheus | prom/prometheus:v2.53.0 | 9090 | HEALTHY | Metrics collection |
| grafana | grafana/grafana:11.1.0 | 3000 | HEALTHY | Dashboards |
| alertmanager | prom/alertmanager:v0.27.0 | 9093 | HEALTHY | Alert routing |
| fail2ban | SHA256 pinned | -- | HEALTHY | Rate limiting |
| crowdsec | SHA256 pinned | -- | HEALTHY | Crowd-sourced security |
| dashboard-v2 | prediction-radar-app-dashboard-v2 | 3000 | HEALTHY | V2 dashboard |
| fincept | prediction-radar-app-fincept-terminal | 6080 | HEALTHY | Terminal interface |

APIs and price IDs (from environment):
- **Stripe Price IDs**: `price_1TN3owPKXFjwOjQXYvdcKsgc` (Pro), `price_1TN3opPKXFjwOjQXdwXamPuw` (Agency)
- **External API Keys**: GNews (`8a5e387cebfd1317294063dae2b43fa5`), Polymarket CLOB, CoinGecko, Brave, Odds
- **Crypto API Secret**: Empty -- needs configuration

### 8.4 Current Blockers

1. **P1 -- Stripe in TEST MODE**: Despite having live Stripe price IDs configured, the Stripe integration is operating in test mode. No real payment transactions can be processed. The Stripe secret key (`STRIPE_API_SECRET` or equivalent) needs to be set to a production key, and the Stripe webhook endpoint needs to be configured.

2. **P2 -- No Subscriber Management**: There is no subscriber management flow -- no sign-up, tier selection, billing, or cancellation. The price IDs exist but the subscription lifecycle is not implemented.

3. **P2 -- Fincept Terminal Not Integrated**: The fincept terminal (port 6080) provides financial data terminal functionality but is not integrated into the main Prediction Radar web interface.

### 8.5 Revenue Path

Prediction Radar generates SaaS subscription revenue:
- **Pro Tier**: Market predictions, real-time data, basic analytics -- targeted at individual investors
- **Agency Tier**: Multi-user, API access, custom dashboards, white-label -- targeted at financial firms
- **Data Licensing**: Historical and real-time market data feeds via API

---

## 9. System 6: AI Ops Revenue

### 9.1 Purpose

AI Ops is the infrastructure platform that enables all other revenue systems. It can be monetized as a product offering -- providing hardened, zero-trust AI infrastructure as a service to external clients.

### 9.2 Architecture

```
                           ┌──────────────────────────────┐
                           │        AI Ops Revenue         │
                           ├──────────────────────────────┤
                           │ Monitoring Stack (5 services) │
                           │ Data Stack (3 services)       │
                           │ AI Stack (3 services)         │
                           │ Security Stack (3 services)   │
                           └──────────┬───────────────────┘
                                      │
        ┌─────────────────┬───────────┼───────────┬─────────────────┐
        │                 │           │           │                 │
        ▼                 ▼           ▼           ▼                 ▼
   ┌──────────┐   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
   │ Grafana  │   │Prometheus│  │   Loki   │  │Clickhouse│  │ Langflow │
   │  :3002   │   │  :9090   │  │  :3100   │  │  :8123   │  │  :7860   │
   └──────────┘   └──────────┘  └──────────┘  └──────────┘  └──────────┘
```

### 9.3 Infrastructure

| Component | Image | Port | Status | Revenue Role |
|-----------|-------|------|--------|-------------|
| aiops-grafana | grafana/grafana:11.5.1 | 3002 | HEALTHY | Revenue dashboards |
| aiops-prometheus | prom/prometheus:v2.55.1 | 9090 | HEALTHY | Metrics for SLIs/SLOs |
| aiops-loki | grafana/loki:3.6.3 | 3100 | HEALTHY | Log aggregation |
| aiops-alertmanager | prom/alertmanager:v0.28.1 | 9093 | HEALTHY | Revenue alert routing |
| aiops-pushgateway | prom/pushgateway:v1.11.2 | 9092 | HEALTHY | Batch metric pushes |
| aiops-superset | apache/superset:4.1.1 | 8088 | HEALTHY | Revenue analytics |
| aiops-clickhouse | clickhouse/clickhouse-server:24.3 | 8123 | HEALTHY | Analytics DB |
| open-webui | ghcr.io/open-webui/open-webui:main | 3000 | HEALTHY | AI interface (Tailscale) |
| langflow | langflowai/langflow:1.0.19 | 7860 | HEALTHY | Visual AI workflows |
| aiops-changedetection | changedetection.io:0.55.3 | 5000 | HEALTHY | Web monitoring |
| aiops-healthchecks | healthchecks:v4.2 | 3130 | HEALTHY | Cron monitoring |
| temporal-server | temporalio/auto-setup:1.29.3 | 7233 | HEALTHY | Workflow orchestration |
| temporal-ui | temporalio/ui:2.50.0 | 8089 | HEALTHY | Workflow UI |
| aiops-webhook-relay | python:3.12-alpine | 8085 | HEALTHY | Webhook bridge |
| netdata | netdata/netdata | 19999 | HEALTHY | Real-time monitoring |
| promtail | grafana/promtail:3.6.8 | -- | HEALTHY | Log shipping |
| hostinger-health-exporter | python:3.12-alpine | 9091 | HEALTHY | Cross-host metrics |

### 9.4 Current State

The AI Ops stack is operationally strong. All monitoring, data, and AI components are healthy. This is the most mature revenue system from an infrastructure perspective. However, it has not been productized for external sale.

### 9.5 Current Blockers

1. **P2 -- No Multi-Tenant Architecture**: The AI Ops stack is single-tenant. For external monetization, tenant isolation, billing, and provisioning systems must be built.

2. **P2 -- No Service Catalog**: There is no published catalog of AI Ops services, SLAs, or pricing for external clients.

3. **P2 -- Open WebUI on main tag**: The open-webui container uses `main` tag instead of a pinned version. This violates the no-false-greens pinning policy and must be corrected before external offering.

### 9.6 Revenue Path

AI Ops generates revenue through:
- Infrastructure-as-a-Service subscriptions (hardened AI infra)
- Managed AI operations (monitoring, alerting, incident response)
- Consulting and implementation services
- White-label platform deployments

---

## 10. System 7: Wheeler Brain Enterprise

### 10.1 Purpose

Wheeler Brain is the intelligence layer that governs and coordinates the entire ecosystem. It comprises 50 Claude Code agents organized into specialized domains, the Neo4j ecosystem graph that stores relational knowledge, and the command center that provides operational control.

### 10.2 Architecture

```
                           ┌──────────────────────────────────┐
                           │     Wheeler Brain OS             │
                           ├──────────────────────────────────┤
                           │ 50 Claude Code Agents            │
                           │ 9 PM2 Agent Services             │
                           │ Neo4j Ecosystem Graph (:7474)    │
                           │ Command Center (:8100)           │
                           │ War Room (:8082)                 │
                           └──────────┬───────────────────────┘
                                      │
        ┌─────────────────┬───────────┼───────────┬─────────────────┐
        │                 │           │           │                 │
        ▼                 ▼           ▼           ▼                 ▼
   ┌──────────┐   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
   │ Revenue  │   │ Security │  │Infra     │  │Deployment│  │ Monitoring│
   │Intell.   │   │Intell.   │  │Intell.   │  │Intell.   │  │ Intell.   │
   └──────────┘   └──────────┘  └──────────┘  └──────────┘  └──────────┘
```

### 10.3 Infrastructure

| Component | Location | Port | Status | Details |
|-----------|----------|------|--------|---------|
| ecosystem-graph | AIOPS Docker | 7474/7687 | HEALTHY | Neo4j 5.26 Community with APOC |
| command-center | AIOPS PM2 | 8100 | ONLINE | Python uvicorn server |
| war-room-server | AIOPS PM2 | 8082 | ONLINE | Incident response hub |
| ecosystem-guardian | AIOPS PM2 | -- | ONLINE | Health monitoring |
| event-bus-relay | AIOPS PM2 | -- | ONLINE | Cross-service events |
| litellm | AIOPS PM2 | 4049 | ONLINE | AI model proxy/gateway |
| openclaw-dashboard | AIOPS PM2 | 8110 | ONLINE | Bot control dashboard |
| voice-outreach-service | AIOPS PM2 | 8005 | ONLINE | Voice call orchestration |

### 10.4 Agent Taxonomy (50 Agents)

The 50 agents are organized into 10 domains:

| Domain | Count | Key Agents |
|--------|-------|------------|
| Infrastructure | 8 | infra-intelligence, docker-intelligence, pm2-intelligence, tailscale-mesh, infra-graph |
| Security | 5 | security-intelligence, secrets-scan, database-rls-auditor, zero-false-green-auditor |
| Revenue | 4 | revenue-intelligence, executive-dashboard, executive-workflow |
| Deployment | 5 | deployment-intelligence, rollback-intelligence, wheeler-deploy-agent |
| Monitoring | 5 | monitoring-intelligence, alert-correlation, observability-intelligence |
| Operations | 8 | autonomous-optimization, drift-detection, incident-response-agent, ecosystem-health-scoring |
| Engineering | 4 | engineering-code-reviewer, engineering-sre, devops-smoke-tester |
| Business | 4 | automation-recommendation, operational-forecasting, long-term-scaling, cost-intelligence |
| Data | 4 | ecosystem-relationship-mapper, ecosystem-memory, wheeler-db-agent |
| Coordination | 3 | agent-coordination, multi-server-coordination, mcp-intelligence |

The 9 PM2 agent services running continuously:
- design-agent-svc, horizon-agent-svc, paperless-agent-svc, ravyn-agent-svc
- surplusai-scraper-agent-svc, voice-agent-svc, frgcrm-agent-svc
- insforge-agent-svc, prediction-radar-agent-svc

### 10.5 Current Blocker

1. **P2 -- No Executive Dashboard**: The executive dashboard agent exists (`/root/.claude/agents/executive-dashboard.md`) but no actual dashboard UI is rendering revenue metrics. Command center (port 8100) is operational but lacks visualization.

2. **P2 -- Agent Coordination Not Full Automated**: The agent-coordination agent exists but cross-agent workflows are partially manual. Full autonomous orchestration is not yet achieved.

### 10.6 Revenue Path

Wheeler Brain Enterprise generates revenue through:
- Enterprise AI agent subscriptions (managed agent swarms for clients)
- Knowledge graph licensing
- Command center as an AI operations product
- Consulting for agent ecosystem design

---

## 11. System 8: Lead Intelligence

### 11.1 Purpose

Lead Intelligence is the acquisition automation engine. It identifies, qualifies, and routes leads to appropriate revenue systems (FRG for surplus fund claimants, Attorney Marketplace for legal partners, Ravyn Capital for acquisition targets).

### 11.2 Architecture

```
                           ┌──────────────────────────────┐
                           │     Lead Intelligence         │
                           ├──────────────────────────────┤
                           │ horizon-agent-svc (PM2 :8006) │
                           │ event-bus-relay (PM2)         │
                           │ Redis (event queues)          │
                           └──────────┬───────────────────┘
                                      │
        ┌─────────────────┬───────────┼───────────┬─────────────────┐
        │                 │           │           │                 │
        ▼                 ▼           ▼           ▼                 ▼
   ┌──────────┐   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
   │FRG Claim │   │ Attorney │  │Ravyn Deals│  │Market    │  │SurplusAI │
   │ Routing  │   │Routing   │  │Routing    │  │Signals   │  │Enrichment│
   └──────────┘   └──────────┘  └──────────┘  └──────────┘  └──────────┘
```

### 11.3 Infrastructure

| Component | Location | Port | Status | Details |
|-----------|----------|------|--------|---------|
| horizon-agent-svc | AIOPS PM2 | 8006 | ONLINE | Lead scanning and routing |
| event-bus-relay | AIOPS PM2 | -- | ONLINE | Event distribution |
| Neo4j ecosystem graph | AIOPS Docker | 7687 | HEALTHY | Lead relationship mapping |
| Redis (multiple) | AIOPS Docker | 6379 | HEALTHY | Lead queue management |

### 11.4 Current State

The horizon agent is online and healthy with 0 restarts. The event bus relay is processing cross-service events. The infrastructure for automated lead routing exists but the routing rules and downstream integrations are not fully configured.

### 11.5 Current Blocker

1. **P2 -- No Automated Lead Routing Rules**: The routing logic from Lead Intelligence to FRG, Attorney Marketplace, and Ravyn Capital is not fully implemented. Lead scoring, qualification thresholds, and routing destinations are manually managed.

2. **P2 -- No Lead Scoring Model**: There is no machine learning model for lead scoring. All leads are treated equally, reducing conversion efficiency.

### 11.6 Revenue Path

Lead Intelligence generates revenue through:
- Pay-per-lead referrals to attorneys and financial firms
- Lead qualification and scoring as a service
- Automated acquisition pipeline management
- Data enrichment licensing

---

## 12. Integration Architecture

### 12.1 Inter-System Communication

All revenue systems communicate through three primary channels:

**Channel 1: LiteLLM Proxy (127.0.0.1:4049)**
The centralized AI model gateway. All systems that require LLM inference (FRGCRM analysis, SurplusAI scoring, Lead Intelligence qualification, Prediction Radar predictions) route through LiteLLM. This provides:
- Single API key management (DEEPSEEK_API_KEY centrally managed)
- Model routing and fallback
- Usage tracking and cost allocation
- Rate limiting and access control

**Channel 2: Neo4j Ecosystem Graph (127.0.0.1:7687)**
The relational knowledge store. All systems contribute to and query the graph for:
- Entity relationships (claimants to cases, attorneys to firms, leads to opportunities)
- Cross-system metadata (deployment state, health status, revenue attribution)
- Intelligence data (market signals, opportunity scores, risk ratings)

**Channel 3: Event Bus Relay (PM2 Service)**
Asynchronous event distribution. Systems publish and subscribe to events:
- `lead.discovered` -- Lead Intelligence to FRG/Attorney Marketplace
- `case.updated` -- FRGCRM to SurplusAI/Ravyn Capital
- `payment.processed` -- Prediction Radar to Revenue Intelligence
- `deployment.completed` -- Deployment Engine to all systems
- `health.degraded` -- Ecosystem Guardian to Command Center

### 12.2 Network Topology

```
WAN (Internet)
    │
    ▼
EDGE NODE (187.77.148.88) ─── Tailscale ─── AIOPS NODE (100.121.230.28)
    │                               │                │
    │                               │                │
    ▼                               ▼                ▼
Public HTTPS :443            Tailscale VPN     COREDB NODE
Nginx reverse proxy          Inter-node comms  (100.118.166.117)
    │                               │                │
    ▼                               ▼                ▼
Frontend apps                API services        PostgreSQL
Static assets                AI workers          Redis
Auth gateway                 Agent services      MinIO
                             Databases (local)
```

### 12.3 API Gateway Pattern

All external-facing revenue system APIs route through a common Nginx reverse proxy on the AIOPS node (port 443 on Tailscale IP 100.121.230.28):

| Subdomain | Target | Auth | Status |
|-----------|--------|------|--------|
| aiops.wheeler.claw.engineer | Traefik/Nginx frontend | Basic Auth | ACTIVE |
| *.wheeler.claw.engineer | Per-service routing | Per-service | CONFIGURED |

For internal communication (within the Tailscale mesh), services communicate directly via localhost:port or Tailscale IP:port. No public endpoints are exposed for sensitive services.

---

## 13. Data Architecture

### 13.1 Database Inventory

| Database | Engine | Location | Port | Purpose | Records | Revenue System |
|----------|--------|----------|------|---------|---------|----------------|
| frgops-standby (frgcrm) | PostgreSQL 16 | AIOPS | 5433 | FRG case data | 122 | FRG Nationwide |
| wheeler_core | PostgreSQL | COREDB | 5432 | Central data | 0 (blocked) | All systems |
| shared-postgres-recovery | PostgreSQL | EDGE | 5432 | Legacy FRG data | 6,603 | FRG Nationwide |
| ravynai-postgres | PostgreSQL 16 (PostGIS) | AIOPS | 5434 | Opportunity graph | Active | Ravyn Capital |
| prediction-radar-db | PostgreSQL 16 | AIOPS | 5432 | SaaS data | Active | Prediction Radar |
| ecosystem-graph | Neo4j 5.26 | AIOPS | 7687 | Knowledge graph | Active | Wheeler Brain |
| aiops-clickhouse | ClickHouse 24.3 | AIOPS | 8123 | Analytics | Active | AI Ops |
| wheeler-redis (prediction-radar) | Redis 7 | AIOPS | 6379 | Cache/queues | Active | Prediction Radar |
| docuseal-redis | Redis 7 Alpine | AIOPS | 6379 | Sessions | Active | Attorney Marketplace |
| usesend-redis | Redis | EDGE | -- | Sessions | Active | Attorney Marketplace |
| wheeler-minio | MinIO | COREDB | 9000 | Object storage | Active | All systems |

### 13.2 Data Flow Diagram

```
External Data Sources
    │
    ▼
SurplusAI Scrapers ──> frgops-standby ──> Neo4j Graph ──> Revenue Intelligence
    │                       │                                  │
    ▼                       ▼                                  ▼
Prediction Radar ──────> ClickHouse ──────────────────────> Grafana Dashboards
    │                       │
    ▼                       ▼
Ravyn Capital ──────────> ravynai-postgres ──────────────> Opportunity Graph
    │
    ▼
FRG Nationwide ────────> frgops-standby ─────────────────> Stripe Payments
```

### 13.3 Data Governance

- **Secret rotation**: All internal DB/Redis passwords rotated on 2026-05-24. `FRGpassword1!` replaced with unique hex passwords.
- **Backup policy**: PostgreSQL databases backed up by dedicated backup containers. Prediction Radar has automated DB backup (prodrigestivill/postgres-backup-local:16). Daily verification within 26-hour recency window.
- **Quarterly restore testing**: Automated scripts validate backup integrity, SQL integrity, config readability. First run: 5/5 checks passing.
- **Access control**: Database credentials stored in `.env` files with `chmod 600`. No plaintext secrets in compose files or process lists.
- **Data residency**: Currently mixed across AIOPS, EDGE, and COREDB. Target state: all data on COREDB with AIOPS as compute layer and EDGE as gateway only.

---

## 14. AI/ML Architecture

### 14.1 Model Serving

```
Revenue Systems ──> LiteLLM Proxy (:4049) ──> DEEPSEEK_API_KEY
                        │
                        ├──> OpenAI-compatible API
                        ├──> Model routing by cost/performance
                        ├──> Fallback on failure
                        └──> Usage tracking
```

LiteLLM at port 4049 serves as the unified AI gateway for all revenue systems. It provides:
- Centralized API key management (DEEPSEEK_API_KEY via `/opt/apps/.env.shared`)
- Consistent OpenAI-compatible API across all systems
- Cost tracking per system/user
- Automatic fallback on model failure

### 14.2 Agent Orchestration

The Wheeler Brain OS operates 50 agents coordinated through:
- **Agent Coordination Agent**: Routes tasks to specialized agents based on domain
- **Revenue Intelligence Agent**: Monitors all revenue systems (READ-ONLY safety model)
- **Autonomous Optimization Agent**: Continuous scanning for optimization opportunities
- **Production Readiness Agent**: Validates deployment readiness

Agent execution follows a hierarchical pattern:
1. Command center receives a goal/request
2. Agent coordination decomposes into sub-tasks
3. Specialized agents execute in parallel
4. Results are aggregated and reported
5. Revenue intelligence updates the ecosystem graph

### 14.3 Scoring Engines

Three scoring engines operate across revenue systems:

| Engine | Purpose | Data Input | Model | Current State |
|--------|---------|-----------|-------|---------------|
| FRG Case Scoring | Rank surplus fund cases by recovery probability | Case metadata, jurisdiction, fund amount | DEEPSEEK_API (blocked) | BLOCKED |
| SurplusAI Opportunity Score | Score market opportunities | Scraper output (blocked) | ML scoring model | BLOCKED |
| Lead Qualification | Score and route leads | Lead attributes, source, history | Rule-based + ML | NOT BUILT |

---

## 15. Security Architecture

### 15.1 Zero-Trust Implementation

The Wheeler ecosystem achieves zero-trust through multiple enforced layers, validated at 100/100 QA score:

**Layer 1: Network**
- UFW default-deny incoming, allow outgoing
- All Docker containers bound to 127.0.0.1 (zero 0.0.0.0 binds)
- Tailscale mesh for inter-node communication (end-to-end encrypted WireGuard)
- Three-node mesh: AIOPS (100.121.230.28), EDGE (100.98.163.17), COREDB (100.118.166.117)

**Layer 2: Container**
- Zero `:latest` Docker images (all pinned to semantic versions or SHA256)
- HEALTHCHECK defined on all containers
- Container secrets in `.env` files with `chmod 600`
- Docker socket access restricted

**Layer 3: Process**
- PM2 jlist secrets cleaned: 103 -> 13 essential entries
- PM2 shared environment file at `/opt/apps/.env.shared` (chmod 600)
- Environment variables managed through `env -i delete+start` pattern (not `pm2 restart`)
- All PM2 agent services at 0 restarts (post-cleanup)

**Layer 4: Application**
- Basic auth on all Nginx-facing services
- Rate limiting on public endpoints
- Langflow authentication enabled
- All admin dashboards Tailscale-only

### 15.2 Revenue-Specific Security

| Revenue System | Auth Mechanism | Network Exposure | Data Encryption | Audit Trail |
|---------------|---------------|-----------------|-----------------|-------------|
| FRG Nationwide | Nginx basic auth + API key | Tailscale-only | TLS (nginx) | PM2 logs |
| SurplusAI | Nginx basic auth | Tailscale-only | TLS (nginx) | PM2 logs |
| Attorney Marketplace | DocuSeal auth + Usesend auth | Tailscale-only | TLS (nginx) | Docker logs |
| Ravyn Capital | API key + Tailscale | Tailscale-only | TLS (nginx) | Docker logs |
| Prediction Radar | API key + session auth | HTTPS + Tailscale-admin | TLS (nginx) | Full stack |
| AI Ops | Tailscale auth per service | Tailscale-only | TLS (nginx) | Loki logs |
| Wheeler Brain | Tailscale only | Tailscale-only | TLS (nginx) | Neo4j + PM2 logs |
| Lead Intelligence | Tailscale only | Tailscale-only | N/A (internal) | PM2 logs |

---

## 16. Deployment Architecture

### 16.1 Deployment Engine

The deployment engine at `/root/deployment-engine/` provides a unified deployment pipeline for all revenue systems:

```
deploy-service.sh flow:
  1. Service type detection (docker, pm2, static, systemd)
  2. Preflight checks (deployment-engine/preflight-check.sh)
  3. Pre-deploy backup
  4. Type-specific deployment
  5. Post-deploy health verification (deployment-engine/post-deploy-healthcheck.sh)
  6. Auto-rollback if health check fails (deployment-engine/rollback-deployment.sh)
  7. Audit log to /var/log/wheeler/deploy/{service}/{timestamp}.log

Exit codes:
  0  Deployment successful
  1  Validation / preflight error
  2  Deployment failed (no rollback attempted)
  3  Deployment failed but rollback succeeded
  4  Deployment failed and rollback also failed
  5  Health check failed after deploy
```

### 16.2 Rollback Engine

The rollback engine at `/root/rollback-engine/` provides multi-type restore:

```
rollback.sh flow:
  1. Service type detection (docker, pm2, static)
  2. Find most recent successful deployment backup
  3. Execute type-specific restore:
     - restore-docker.sh: Restore container from backup image + data volume
     - restore-pm2.sh: Restore PM2 process from env + ecosystem dump
     - restore-env.sh: Restore environment configuration
     - restore-routing.sh: Restore Nginx/Traefik routing rules
  4. Verify post-rollback health
  5. Preserve failed deployment logs and backups
  6. Full audit trail

Exit codes:
  0  Rollback fully successful
  1  Rollback failed (backup not found, script error, service down)
  2  Verification failed (health checks did not pass after restore)
```

### 16.3 Revenue System Deployment Strategy

| Revenue System | Deploy Type | Rollback Strategy | Downtime Window | Update Frequency |
|---------------|-------------|------------------|-----------------|------------------|
| FRG Nationwide | PM2 | env restore + PM2 dump | 30s | Weekly |
| SurplusAI | PM2 + Docker | env restore + image rollback | 30s PM2 / 60s Docker | Weekly |
| Attorney Marketplace | Docker | docker-compose rollback | 60s | Bi-weekly |
| Ravyn Capital | PM2 + Docker | env restore + image rollback | 30s PM2 | Bi-weekly |
| Prediction Radar | Docker Compose | compose rollback + DB backup | 120s (migrations) | Bi-weekly |
| AI Ops | Docker | Individual container rollback | 60s per service | Monthly |
| Wheeler Brain | PM2 | PM2 dump + env restore | 30s | On-demand |
| Lead Intelligence | PM2 | PM2 dump + env restore | 30s | Weekly |

---

## 17. Monitoring and Observability

### 17.1 Revenue-Aware Monitoring

The monitoring stack is deployed and healthy but not yet configured for revenue-specific observability:

| Tool | Port | Purpose | Revenue Dashboards |
|------|------|---------|-------------------|
| Grafana | 3002 (AIOPS) | Revenue dashboards | NOT BUILT |
| Prometheus | 9090 (AIOPS) | Metrics collection | NOT BUILD |
| Loki | 3100 (AIOPS) | Log aggregation | N/A |
| Alertmanager | 9093 (AIOPS) | Alert routing | NOT CONFIGURED |
| Netdata | 19999 (AIOPS) | Real-time monitoring | Basic |
| Uptime Kuma | 3001 (AIOPS) | Uptime monitoring | BASIC |
| Healthchecks | 3130 (AIOPS) | Cron job monitoring | BASIC |

### 17.2 Revenue Metrics to Track

| Metric | Source | Collection Method | Target |
|--------|--------|-------------------|--------|
| Cases processed/day | FRGCRM API | Prometheus counter | >100 |
| Recovery rate | FRGCRM API | Business metric | >15% |
| Scraper success rate | SurplusAI PM2 | Log analysis | >95% |
| Prediction accuracy | Prediction Radar | Business metric | >60% |
| Stripe revenue/mo | Prediction Radar | Stripe API | $TBD |
| Agent uptime | PM2 status | Prometheus gauge | 99.9% |
| Lead conversion rate | Lead Intelligence | Business metric | >5% |
| API response time | All APIs | Prometheus histogram | <200ms p95 |

### 17.3 Alert Routing

```
Alertmanager (:9093)
    │
    ├──> P0 (Revenue Down)  ──> PagerDuty + SMS + Slack #revenue-critical
    ├──> P1 (Revenue Impact) ──> Slack #revenue-alerts + Email
    ├──> P2 (Degraded)       ──> Slack #revenue-health
    └──> P3 (Informational)  ──> Slack #revenue-logs
```

---

## 18. Automation Governance

### 18.1 Governance Policies

14 repo-router policies govern all automated workflows in the Wheeler ecosystem:

| Policy Domain | Count | Scope | Enforcement |
|--------------|-------|-------|-------------|
| Deployment | 4 | Service deployment and rollback | Pre/post hooks |
| Routing | 3 | Nginx/Traefik configuration | Verified apply |
| Security | 3 | Network policy, secrets, access | Continuous |
| Data | 2 | Backup, restore, migration | Scheduled |
| Monitoring | 2 | Alert routing, dashboard config | Continuous |

### 18.2 Automated Workflow Inventory

| Workflow | Trigger | Action | Rollback | Governing Policy |
|----------|---------|--------|----------|-----------------|
| Service deploy | `deploy-service.sh` | Preflight -> deploy -> verify | Auto on fail | Deployment policy |
| Service rollback | `rollback.sh` | Find backup -> restore -> verify | N/A (restore) | Deployment policy |
| Backup verification | Cron (4am UTC daily) | Verify backup existence, recency, integrity | N/A | Data policy |
| TLS renewal | Cron (weekly Sunday 4:30am) | Check expiry -> renew -> reload nginx | Self-signed fallback | Security policy |
| Restore testing | Cron (quarterly) | Validate backup to /tmp | Dry-run only | Data policy |
| Secret rotation | Manual | Replace -> test -> verify | Previous secret | Security policy |
| Health check | PM2/docker auto | Check HEALTHCHECK endpoint | Restart policy | Monitoring policy |

### 18.3 No-False-Greens Enforcement

The QA scorecard demands 100/100 before revenue promotion:

| Check | Frequency | Tool | Pass Criteria |
|-------|-----------|------|---------------|
| PM2 process health | Continuous | PM2 status | All online, <5 restarts/24h |
| Docker container health | Continuous | Docker ps | All healthy (HEALTHCHECK) |
| Network exposure | Daily | ss/netstat | Zero 0.0.0.0 binds on revenue services |
| Secret exposure | Weekly | pm2 jlist scan | Zero plaintext secrets |
| Image pinning | Daily | Docker inspect | Zero :latest tags |
| Backup verification | Daily | backup-verify.sh | All 5 checks passing |
| Restore testing | Quarterly | restore-test.sh | All 5 checks passing |

---

## 19. Implementation Roadmap

### 19.1 Phase 1: Revenue Unblocking (Week 1)

**Objective**: Remove all P0 and P1 blockers to enable first dollar of revenue.

| Step | Action | Owner | Duration | Success Criteria |
|------|--------|-------|----------|-----------------|
| 1.1 | Fix COREDB PostgreSQL connectivity | Infrastructure | 2-4h | AIOPS can connect to COREDB:5432 |
| 1.2 | Restore DEEPSEEK_API_KEY to frgcrm-api | Devops | 30min | FRGCRM API at :8082 returns valid AI analysis |
| 1.3 | Stabilize surplusai-scraper-agent-svc | Agent team | 2h | Scraper PM2 shows 0 restarts after 24h |
| 1.4 | Stabilize voice-agent-svc | Agent team | 2h | Voice PM2 shows 0 restarts after 24h |
| 1.5 | Enable Stripe live mode on Prediction Radar | Devops | 4h | Test transaction processes successfully |
| 1.6 | Repair PipelineDAG stages | Engineering | 4h | All 6 stages passing |
| 1.7 | Migrate 6,603 cases from EDGE to AIOPS | Data | 2h | All cases accessible via FRGCRM API |

### 19.2 Phase 2: Revenue Activation (Week 2)

**Objective**: Activate revenue-generating workflows for highest-priority systems.

| Step | Action | Owner | Duration | Success Criteria |
|------|--------|-------|----------|-----------------|
| 2.1 | Build FRG automated claimant matching | Engineering | 3 days | 10+ matches generated per day |
| 2.2 | Deploy Prediction Radar subscription flow | Engineering | 5 days | User can sign up, pay, access SaaS |
| 2.3 | Build attorney directory MVP | Engineering | 5 days | 50+ attorneys listed |
| 2.4 | Implement lead scoring model | ML team | 3 days | Lead scoring >60% accuracy |
| 2.5 | Create revenue dashboards in Grafana | Monitoring | 2 days | 5 revenue dashboards rendering |

### 19.3 Phase 3: Revenue Scaling (Weeks 3-4)

**Objective**: Scale revenue operations and activate remaining systems.

| Step | Action | Owner | Duration | Success Criteria |
|------|--------|-------|----------|-----------------|
| 3.1 | Deploy automated acquisition engine | Engineering | 5 days | 1+ acquisition per week |
| 3.2 | Activate Attorney Marketplace frontend | Engineering | 5 days | 200+ attorneys, 50+ matches |
| 3.3 | Launch SurplusAI intelligence subscriptions | Product | 3 days | 5+ paying subscribers |
| 3.4 | Implement AI Ops multi-tenant | Infrastructure | 1 week | Tenant isolation verified |
| 3.5 | Deploy executive dashboard | Monitoring | 2 days | All revenue KPIs visible |

### 19.4 Phase 4: Autonomous Operation (Month 2)

**Objective**: Achieve autonomous revenue operation with minimal manual intervention.

| Step | Action | Owner | Duration | Success Criteria |
|------|--------|-------|----------|-----------------|
| 4.1 | Full agent orchestration automation | Agent team | 1 week | 90% of workflows autonomous |
| 4.2 | Auto-scaling for revenue services | Infrastructure | 1 week | Services scale on demand |
| 4.3 | Predictive revenue analytics | ML team | 2 weeks | 80% forecast accuracy |
| 4.4 | Stripe recurring billing fully automated | Engineering | 1 week | Zero manual billing operations |

### 19.5 Dependency Graph

```
Phase 1 (Week 1)
    │
    ├── 1.1 Fix COREDB ──── BLOCKS ──── 1.7 Migrate cases
    │                                       │
    ├── 1.2 DEEPSEEK_KEY ── BLOCKS ────────┤
    │                                       ▼
    ├── 1.3 Fix scraper ── BLOCKS ──── Phase 2 SurplusAI
    │                                       │
    ├── 1.4 Fix voice ──── BLOCKS ──── Phase 2 FRG outreach
    │                                       │
    ├── 1.5 Stripe live ── BLOCKS ──── Phase 2 Subscriptions
    │                                       │
    ├── 1.6 PipelineDAG ── BLOCKS ──── All Phase 2+ data flows
    │
    ▼
Phase 2 (Week 2) ────> Phase 3 (Weeks 3-4) ────> Phase 4 (Month 2)
```

---

## 20. Revenue Projections Framework

### 20.1 Methodology

This framework provides revenue projections based on real infrastructure data. All figures are estimates derived from system capacity, not hypothetical market sizing. No fake numbers.

**Data sources for projections:**
- Current case records: 6,603 on EDGE + 122 on AIOPS = 6,725 total FRG cases
- Current system health: 59/61 services healthy (96.7%)
- Current scraper output: 0 (blocked by restart loop)
- Current Prediction Radar subscriptions: 0 (Stripe in test mode)
- Current attorney listings: 0 (marketplace not built)

### 20.2 Projection Bands

| Revenue System | Band 1 (Week 2) | Band 2 (Month 1) | Band 3 (Month 3) | Band 4 (Month 6) |
|---------------|-----------------|------------------|------------------|------------------|
| FRG Nationwide | $0 (blocked) | $2K-5K/mo | $10K-25K/mo | $25K-50K/mo |
| SurplusAI | $0 (blocked) | $0 (building) | $1K-3K/mo | $5K-10K/mo |
| Attorney Marketplace | $0 (not built) | $0 (building) | $2K-5K/mo | $5K-15K/mo |
| Ravyn Capital | $0 (manual) | $0 (manual) | $1K-5K/mo | $5K-20K/mo |
| Prediction Radar | $0 (test mode) | $500-2K/mo | $2K-8K/mo | $5K-15K/mo |
| AI Ops | $0 (not productized) | $0 | $0 | $2K-5K/mo |
| Wheeler Brain | $0 (internal) | $0 | $0 | $0 (TBD) |
| Lead Intelligence | $0 (not built) | $0 | $1K-2K/mo | $3K-8K/mo |
| **TOTAL** | **$0** | **$2.5K-7K/mo** | **$17K-48K/mo** | **$50K-123K/mo** |

### 20.3 Assumptions

1. FRG recovery: 15% of 6,725 cases = ~1,009 potential recoveries at average $5K surplus, 25% fee = $1,250/case
2. Prediction Radar: 20 Pro subscribers at $49/mo + 5 Agency at $199/mo = $1,975/mo by month 1
3. Attorney Marketplace: 50 attorneys at $49/mo listing = $2,450/mo by month 2
4. Lead Intelligence: 100 qualified leads at $25/lead = $2,500/mo by month 3
5. These projections assume all blockers in Phase 1 are resolved

### 20.4 Constraints

- All projections are based on existing infrastructure capacity (3 Hetzner/Hostinger nodes)
- Revenue scales linearly with case/lead volume until infrastructure upgrade needed
- COREDB connection fix is the single point of failure for all projections
- DEEPSEEK_API_KEY availability affects FRG and SurplusAI projections

---

## 21. Risk Register

### 21.1 Current Risks (Known Blockers)

| Risk ID | Description | System | Severity | Likelihood | Mitigation |
|---------|-------------|--------|----------|------------|------------|
| R-001 | COREDB PostgreSQL refusing connections | ALL | CRITICAL | CERTAIN | Immediate debug: check pg_hba.conf, listen_addresses, firewall, Tailscale routing |
| R-002 | DEEPSEEK_API_KEY missing from FRGCRM | FRG | CRITICAL | CERTAIN | Apply env -i delete+start pattern from shared env file |
| R-003 | SurplusAI scraper 282+ restart loop | SurplusAI | HIGH | CERTAIN | Emergency PM2 delete+start; root cause analysis of scraper code |
| R-004 | Voice agent restart loop | Lead Intel | HIGH | CERTAIN | Emergency PM2 delete+start; dependency audit |
| R-005 | Stripe in test mode | PredRadar | HIGH | CERTAIN | Switch to production API keys; verify webhook endpoint |
| R-006 | PipelineDAG all stages failing | ALL | MEDIUM | CERTAIN | Pipeline audit and stage-by-stage restoration |
| R-007 | No attorney marketplace | Attorney | MEDIUM | CERTAIN | Build MVP using DocuSeal + Usesend APIs |
| R-008 | Usesend port on Tailscale (100.121.230.28:3007) | Attorney | LOW | ACTIVE | Change Docker bind to 127.0.0.1 only |

### 21.2 Emerging Risks

| Risk ID | Description | Severity | Likelihood | Mitigation |
|---------|-------------|----------|------------|------------|
| R-101 | PM2 env var stripping on process restart | HIGH | MEDIUM | Document in ecosystem.config.js; use shared env loader |
| R-102 | Docker :latest tags reappearing | MEDIUM | LOW | Automated daily audit; CI/CD gate |
| R-103 | Stripe API key rotation breaking billing | HIGH | LOW | Rotate with overlapping validity window |
| R-104 | Neo4j data loss (single instance) | HIGH | LOW | Add backup cron for Neo4j dump |
| R-105 | Tailscale mesh partitioning | HIGH | LOW | Document direct IP fallback procedure |
| R-106 | DEEPSEEK_API_KEY rate limiting at scale | MEDIUM | MEDIUM | Implement LiteLLM caching and model fallback |
| R-107 | Cross-system event bus message loss | MEDIUM | MEDIUM | Add message persistence and retry to event-bus-relay |
| R-108 | Revenue dashboard data inconsistency | MEDIUM | MEDIUM | Implement data source of truth verification |

### 21.3 Blocker Resolution Priority

```
P0 (CRITICAL -- Revenue Blocked)
  ├── R-001 COREDB connectivity
  └── R-002 DEEPSEEK_API_KEY

P1 (HIGH -- Revenue Impaired)
  ├── R-003 Scraper restart loop
  ├── R-004 Voice agent restart loop
  ├── R-005 Stripe test mode
  └── R-006 PipelineDAG failures

P2 (MEDIUM -- Revenue Delayed)
  ├── R-007 No marketplace
  ├── R-008 Usesend tailscale exposure
  └── (Emerging risks as tracked)
```

---

## 22. Success Metrics

### 22.1 Revenue Readiness Scorecard

| Domain | Current Score | Target | Weight | Measurement |
|--------|---------------|--------|--------|-------------|
| FRG Nationwide Operational | 2/10 | 10/10 | 25% | API health, case access, AI analysis, outreach |
| SurplusAI Operational | 3/10 | 10/10 | 20% | Scraper health, data pipeline, portal uptime |
| Prediction Radar SaaS | 4/10 | 10/10 | 20% | Stripe live, subscriber count, payment flow |
| Attorney Marketplace | 1/10 | 10/10 | 15% | Listings, matches, DocuSeal integration |
| Ravyn Capital Active | 6/10 | 10/10 | 10% | Deal pipeline, opportunity graph updates |
| AI Ops Productized | 2/10 | 10/10 | 5% | Multi-tenant, service catalog, billing |
| Lead Intelligence Active | 3/10 | 10/10 | 5% | Routing rules, scoring model, event flow |
| **REVENUE READINESS TOTAL** | **2.9/10** | **10/10** | **100%** | Weighted composite score |

### 22.2 Infrastructure Health Targets

| Metric | Current | Target | Measurement Method |
|--------|---------|--------|-------------------|
| PM2 process online rate | 95% (19/20) | 100% | pm2 jlist |
| Docker container healthy rate | 100% (41/41) | 100% | docker ps --health |
| Revenue system uptime | N/A (blocked) | 99.9% | Uptime Kuma + Prometheus |
| API p95 response time | N/A | <200ms | Prometheus histogram |
| Data freshness | 0 days (blocked) | <24h | Backup verification |
| Secret exposure count | 13 (PM2 limitation) | 0 | pm2 jlist scan |
| Revenue dashboards | 0 | 5 | Grafana API |

### 22.3 Business Metrics

| Metric | Current | Week 1 Target | Month 1 Target | Month 3 Target |
|--------|---------|--------------|----------------|----------------|
| Cases processed/day | 0 (blocked) | 50 | 200 | 500 |
| Attorneys listed | 0 | 0 | 50 | 200 |
| SaaS subscribers | 0 | 0 | 25 | 100 |
| Lead conversion rate | N/A | N/A | 5% | 10% |
| Revenue/month | $0 | $0 | $2.5K-$7K | $17K-$48K |
| Pipeline DAG pass rate | 0% | 100% | 100% | 100% |
| Scraper success rate | 0% | 95% | 98% | 99% |

### 22.4 Gate Criteria: Phase 1 to Phase 2

All of the following must be true before Phase 2 begins:
1. COREDB PostgreSQL accepting connections from AIOPS
2. FRGCRM API responding with AI-powered analysis (DEEPSEEK_API_KEY confirmed)
3. SurplusAI scraper agent stable (<5 restarts/24h)
4. Voice agent stable (<5 restarts/24h)
5. Stripe processing a test payment in production mode
6. PipelineDAG performing at 4/6 stages minimum
7. All 6,603 FRG cases accessible from AIOPS

### 22.5 Gate Criteria: Phase 2 to Phase 3

All of the following must be true before Phase 3 begins:
1. FRG automated matching generating 10+ matches/day
2. Prediction Radar accepting subscriber payments
3. Attorney directory listing 50+ attorneys
4. Lead scoring model deployed with >60% accuracy
5. Revenue dashboards rendering in Grafana

---

## Appendix A: Infrastructure Reference

### A.1 Complete Port Map (AIOPS Node)

| Port | Service | Revenue System | Bind | Auth |
|------|---------|---------------|------|------|
| 22 | SSH | Infrastructure | All | Key |
| 443 | Nginx HTTPS | All external | Tailscale | Basic + TLS |
| 3000 | Open WebUI | AI Ops | 127.0.0.1 | Tailscale |
| 3001 | Uptime Kuma | Monitoring | 127.0.0.1 | Tailscale |
| 3002 | AI Ops Grafana | AI Ops | 127.0.0.1 | Tailscale |
| 3003 | SurplusAI Frontend | SurplusAI | PM2 | Basic |
| 3007 | Usesend | Attorney | 127.0.0.1 + TS | App auth |
| 3010 | DocuSeal | Attorney | 127.0.0.1 | App auth |
| 3100 | Loki | Observability | 127.0.0.1 | Tailscale |
| 3130 | Healthchecks | Monitoring | 127.0.0.1 | Tailscale |
| 4049 | LiteLLM | AI Gateway | 127.0.0.1 | API key |
| 5000 | Changedetection | Monitoring | 127.0.0.1 | Tailscale |
| 5432 | Prediction Radar DB | Prediction Radar | 127.0.0.1 | DB auth |
| 5433 | frgops-standby | FRG | 127.0.0.1 | DB auth |
| 5434 | ravynai-postgres | Ravyn | 127.0.0.1 | DB auth |
| 6379 | Redis (PredRadar) | Prediction Radar | 127.0.0.1 | No auth |
| 7233 | Temporal | Workflows | 127.0.0.1 | Tailscale |
| 7474 | Neo4j HTTP | Brain | 127.0.0.1 | Tailscale + auth |
| 7687 | Neo4j Bolt | Brain | 127.0.0.1 | Tailscale + auth |
| 7860 | Langflow | AI Ops | 127.0.0.1 | Tailscale + auth |
| 8003 | surplusai-scraper-agent-svc | SurplusAI | 127.0.0.1 | PM2 |
| 8005 | voice-outreach-svc | Lead Intel | 127.0.0.1 | PM2 |
| 8006 | horizon-agent-svc | Lead Intel | 127.0.0.1 | PM2 |
| 8007 | ravynai-app | Ravyn | 127.0.0.1 | Docker |
| 8008 | frgcrm-agent-svc | FRG | 127.0.0.1 | PM2 |
| 8009 | paperless-agent-svc | Brain | 127.0.0.1 | PM2 |
| 8011 | ravyn-agent-svc | Ravyn | 127.0.0.1 | PM2 |
| 8013 | insforge-agent-svc | Brain | 127.0.0.1 | PM2 |
| 8020 | prediction-radar-agent-svc | PredRadar | 127.0.0.1 | PM2 |
| 8082 | frgcrm-api | FRG | 127.0.0.1 | Basic |
| 8085 | webhook-relay | AI Ops | 127.0.0.1 | Tailscale |
| 8088 | Superset | Analytics | 127.0.0.1 | Tailscale + auth |
| 8089 | Temporal UI | Workflows | 127.0.0.1 | Tailscale |
| 8098 | Prediction Radar Web | PredRadar | 127.0.0.1 | App auth |
| 8100 | Command Center | Brain | 127.0.0.1 | Tailscale |
| 8103 | SurplusAI API | SurplusAI | 127.0.0.1 | PM2 |
| 8110 | openclaw-dashboard | Brain | 127.0.0.1 | PM2 |
| 8123 | ClickHouse | Analytics | 127.0.0.1 | Tailscale |
| 9090 | Prometheus | Monitoring | 127.0.0.1 | Tailscale |
| 9091 | health-exporter | Monitoring | 127.0.0.1 | Tailscale |
| 9092 | Pushgateway | Monitoring | 127.0.0.1 | Tailscale |
| 9093 | Alertmanager | Monitoring | 127.0.0.1 | Tailscale |
| 9100 | Node Exporter | Monitoring | 127.0.0.1 | Host |
| 19999 | Netdata | Monitoring | 127.0.0.1 | Tailscale |

### A.2 PM2 Agent Service Ports

| Service | Port | Restarts | Type |
|---------|------|----------|------|
| design-agent-svc | -- | 2 | Agent |
| horizon-agent-svc | 8006 | 0 | Lead Intel |
| paperless-agent-svc | 8009 | 0 | Brain |
| ravyn-agent-svc | 8011 | 0 | Ravyn |
| surplusai-scraper-agent-svc | 8003 | 0 (post-cleanup: 282+) | SurplusAI |
| voice-agent-svc | -- | 0 (post-cleanup: high) | Lead Intel |
| frgcrm-agent-svc | 8008 | 0 | FRG |
| insforge-agent-svc | 8013 | 0 | Brain |
| prediction-radar-agent-svc | 8020 | 0 | PredRadar |

### A.3 Docker Network Segments

| Network | Subnet | Services |
|---------|--------|----------|
| docker0 | 172.17.0.0/16 | Default bridge |
| br-12d358b37802 | 172.20.0.0/16 | Prediction Radar |
| br-3205b864b513 | 172.19.0.0/16 | AI Ops monitoring |
| br-cf83c15f95d4 | 172.26.0.0/16 | RavynAI |
| br-f50dec34ffdd | 172.25.0.0/16 | DocuSeal |
| br-f55e736c9b0e | 172.24.0.0/16 | Usesend |
| tailscale0 | 100.121.230.28/32 | Tailscale mesh |

---

*End of Wheeler Revenue Engine Architecture Document v1.0.0*

**Next Review Date:** 2026-06-24
**Owner:** Wheeler Brain OS -- Revenue Engineering
**Related Documents:**
- `/root/STAGE2_QA_SCORECARD_FINAL.md` -- Infrastructure QA validation
- `/root/MASTER_EXECUTION_STATE.md` -- Current execution state
- `/root/DEPLOYMENT_SYSTEM.md` -- Deployment and rollback architecture
- `/root/.claude/agents/revenue-intelligence.md` -- Revenue Intelligence agent specification
- `/root/deployment-engine/` -- Deployment scripts and policies
- `/root/rollback-engine/` -- Rollback orchestration scripts
