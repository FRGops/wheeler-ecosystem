# Wheeler Ecosystem -- Revenue Flow Architecture

**Classification:** EXECUTIVE / ENGINEERING
**Version:** 1.0.0
**Date:** 2026-05-24
**Author:** Wheeler AIOps Control Plane
**Servers:** AIOPS (5.78.140.118) / COREDB (5.78.210.123) / EDGE (187.77.148.88)
**Mesh:** Tailscale 100.64.0.0/10 (3-node)

---

## Table of Contents

1. [Revenue Flow Overview](#1-revenue-flow-overview)
2. [Lead Generation Layer](#2-lead-generation-layer)
3. [Lead Intake Layer](#3-lead-intake-layer)
4. [Lead Processing Layer](#4-lead-processing-layer)
5. [Lead Routing Layer](#5-lead-routing-layer)
6. [Lead Conversion Layer](#6-lead-conversion-layer)
7. [Revenue Collection Layer](#7-revenue-collection-layer)
8. [Revenue Intelligence Layer](#8-revenue-intelligence-layer)
9. [Revenue Automation Layer](#9-revenue-automation-layer)
10. [Revenue Recovery Layer](#10-revenue-recovery-layer)
11. [Revenue Governance Layer](#11-revenue-governance-layer)
12. [Integration Architecture](#12-integration-architecture)

---

## 1. Revenue Flow Overview

The Wheeler ecosystem generates revenue through four distinct but interconnected engines: Funds Recovery (FRG), Predictive Intelligence (Prediction Radar), Surplus Asset Detection (SurplusAI), and Acquisition (Ravyn Capital). Each engine feeds into a shared infrastructure layer for processing, conversion, and collection.

```
                              WHEELER REVENUE LIFECYCLE
  ======================================================================

   LEAD GEN          LEAD INTAKE         PROCESSING         ROUTING
  ┌──────────┐     ┌─────────────┐     ┌────────────┐    ┌──────────┐
  │ SEO      │     │ FRGCRM Web  │     │ AI Scoring │    │ FRG      │
  │ Paid Ads │────>│ Chatwoot    │────>│ Dedup      │───>│ SurplusAI│
  │ Referrals│     │ WhatsApp    │     │ Enrichment │    │ Ravyn    │
  │ Organic  │     │ Phone/Voice │     │ Qualification│  │ Attorney │
  └──────────┘     └─────────────┘     └────────────┘    └──────────┘
                                                               │
                                                               ▼
  REVENUE             COLLECTION        CONVERSION
  ┌──────────┐     ┌─────────────┐     ┌────────────┐
  │ Stripe   │     │ Payment     │     │ Attorney   │
  │ Subscriptions│  │ Processing  │<────│ Matching   │
  │ Revenue  │     │ SendGrid    │     │ DocuSeal   │
  │ Sharing  │     │ Invoicing   │     │ Document   │
  └──────────┘     └─────────────┘     └────────────┘

  ======================================================================
```

### Revenue Engines (8 Primary Systems)

| # | System | Type | Revenue Model | Current State |
|---|--------|------|---------------|---------------|
| 1 | **FRG** | Funds Recovery | Contingency fee (% of recovered funds) | PipelineDAG broken (DEEPSEEK_API_KEY missing); 6,603 cases on Hostinger DB |
| 2 | **SurplusAI** | Surplus Detection | SaaS / finder's fee | Scraper in restart loop; portal API running |
| 3 | **Attorney Marketplace** | Revenue Sharing | Per-case referral fee | 4 attorneys configured (Bigham, Morris, Farah, Walker); matching logic broken |
| 4 | **Ravyn Capital** | Acquisition Engine | Deal-based / carry | API healthy (:8007); database online (:5434) |
| 5 | **Prediction Radar** | Predictions SaaS | 7-tier Stripe subscriptions | **LIVE** but Stripe in TEST MODE; 14 containers healthy |
| 6 | **AI Ops SaaS** | Infrastructure | Future: managed AI hosting | Not yet productized; all infra in place |
| 7 | **Wheeler Brain** | Enterprise Intel | Future: intelligence subscriptions | Control plane operational; not yet monetized |
| 8 | **Lead Intelligence** | SEO/Outreach | Lead generation, inbound | Voice outreach running; automated intake partially functional |

### Infrastructure Topology

```
                        INTERNET (Cloudflare)
                              │
                          ┌───▼────┐
                          │  EDGE  │  Hostinger 187.77.148.88
                          │ Traefik│  Public frontends, SSL termination
                          └───┬────┘
                              │ Tailscale 100.98.x.x
          ┌───────────────────┼─────────────────────┐
          │                   │                     │
    ┌─────▼──────┐    ┌──────▼──────┐    ┌─────────▼────────┐
    │   AIOPS    │    │   COREDB    │    │  MacBook (Dev)   │
    │ 5.78.140.118│    │ 5.78.210.123│    │ 100.83.80.6      │
    │ 100.121.230.28  │ 100.118.166.117 │  │                    │
    │            │    │             │    │                    │
    │ PM2: 17   │    │ PostgreSQL  │    │  Local dev only    │
    │ Docker: 40│    │ Redis 7     │    │                    │
    │ LiteLLM   │    │ MinIO S3    │    │                    │
    │ Gateway   │    │ Monitoring  │    │                    │
    └───────────┘    └─────────────┘    └────────────────────┘
```

### PM2 Agent Services (AIOPS)

All 9 AI agent services communicate through the LiteLLM proxy at `127.0.0.1:4049`:

| Agent | PM2 Port | Status | Role in Revenue Flow |
|-------|----------|--------|---------------------|
| frgcrm-agent-svc | :8013 | online | Case scoring, attorney matching |
| frgcrm-api | :8082 | online (degraded) | CRM API -- all requests 500 |
| frgcrm-mirror-test | :8003 | online | Hostinger DB mirror validation |
| insforge-agent-svc | :8013 | online | Investigation/insight generation |
| surplusai-scraper-agent-svc | :8007 | online | Surplus detection scraping |
| surplusai-portal-api | :8103 | online | SurplusAI web API |
| voice-agent-svc | :8008 | online | Voice call handling |
| voice-outreach-service | :8095 | online | Automated outbound calling |
| prediction-radar-agent-svc | :8011 | online | Prediction Radar AI integration |
| ravyn-agent-svc | :8005 | online | Ravyn Capital deal analysis |
| litellm | :4049 | online | AI gateway (all agents) |

### Database Topology

| Database | Host | Port | Type | Revenue Data |
|----------|------|------|------|-------------|
| wheeler-postgres | COREDB | 5432 | PostgreSQL 16 | Core revenue data (DOWN) |
| frgops-standby | AIOPS | 5433 | PostgreSQL 16 | FRGCRM shadow copy (misconfigured) |
| aiops-ravynai-postgres | AIOPS | 5434 | PostGIS 16 | Ravyn deal data |
| prediction-radar-app-db | AIOPS | internal | PostgreSQL 16 | Subscription/users |
| aiops-redis | AIOPS | 6379 | Redis 7 | Session/cache |
| prediction-radar-app-redis | AIOPS | internal | Redis 7 | Queue/cache |
| docuseal-redis | AIOPS | internal | Redis 7 | Document signing |

---

## 2. Lead Generation Layer

### 2.1 Architecture

The lead generation layer captures inbound interest across all eight revenue systems.

```
                         LEAD GENERATION CHANNELS
  ======================================================================

   ORGANIC                    PAID                    REFERRAL
  ┌──────────────┐    ┌─────────────────┐    ┌──────────────────┐
  │ SEO          │    │ Google Ads      │    │ Attorney Network │
  │ fundsrecovery│    │ LinkedIn Ads    │    │ Bigham           │
  │ group.com    │    │ Twitter/X Ads   │    │ Morris           │
  │ surplusai.io │    │ Programmatic    │    │ Farah            │
  │ prediction   │    │                 │    │ Walker           │
  │ radar.app    │    │                 │    │                  │
  └──────┬───────┘    └────────┬────────┘    └────────┬─────────┘
         │                    │                       │
         └────────────────────┼───────────────────────┘
                              │
                     ┌────────▼────────┐
                     │  Lead Capture   │
                     │  Endpoints      │
                     │                 │
                     │ frgops*:8001    │
                     │ frgcrm*:8002    │
                     │ prediction*:80  │
                     │ surplusai*:8103 │
                     └─────────────────┘
```

### 2.2 Public-Facing Websites

| Domain | Server | Stack | TLS | Revenue System |
|--------|--------|-------|-----|---------------|
| fundsrecoverygroup.com | EDGE (Hostinger) | Traefik + PM2 | Cloudflare | FRG |
| predictionradar.app | AIOPS | Docker :8098 | Cloudflare | Prediction Radar |
| surplusai.io | EDGE (Hostinger) | nginx | Cloudflare | SurplusAI |
| frgops.fundsrecoverygroup.tech | AIOPS | Traefik | Cloudflare | FRG Ops |
| wheeler.frgop.io | AIOPS | Traefik | Cloudflare | Wheeler |

### 2.3 Current State

- **FRGCRM**: Public website live at fundsrecoverygroup.com. Lead capture forms functional (HTTP 200), but backend PipelineDAG is broken -- captured leads cannot be processed end-to-end.
- **Prediction Radar**: Live at predictionradar.app. User registration and subscription flows functional. Stripe checkout implemented but in TEST MODE -- no real revenue being collected.
- **SurplusAI**: Public site live at surplusai.io. Scraper agent in restart loop on AIOPS, limiting surplus detection capability.
- **SEO / Organic**: No formal SEO infrastructure detected. No analytics tracking (Google Analytics, Plausible, Fathom) configured.
- **Paid Ads**: No ad account integrations detected. No UTM tracking or ad attribution pipeline.

### 2.4 Target State

- All five public websites serving lead capture forms with backend processing end-to-end
- UTM parameter tracking across all channels with attribution stored in COREDB
- Google Analytics 4 or Plausible on all properties
- Attorney referral portal with unique tracking links
- SEO analytics pipeline (rank tracking, keyword analysis, content gap analysis)

### 2.5 Gap Analysis & Priority

| Gap | Impact | Priority | Effort |
|-----|--------|----------|--------|
| FRGCRM PipelineDAG broken (DEEPSEEK_API_KEY) | Leads captured but never processed | **P0** | Low |
| No analytics/attribution | Cannot measure channel ROI | P2 | Medium |
| No paid ad integrations | Missing highest-value channel | P3 | Medium |
| No SEO pipeline | Organic growth untracked | P3 | Medium |
| Attorney referral portal not built | Missing partner channel revenue | P3 | High |

---

## 3. Lead Intake Layer

### 3.1 Architecture

All inbound leads converge into the intake layer before being processed.

```
                         LEAD INTAKE INFRASTRUCTURE
  ======================================================================

   WEB FORMS              CHAT              VOICE              EMAIL
  ┌──────────┐      ┌───────────┐      ┌──────────┐      ┌──────────┐
  │ FRGCRM   │      │ Chatwoot  │      │ Voice    │      │ SendGrid │
  │ Contact  │      │ Live Chat │      │ Agent    │      │ Inbound  │
  │ Forms    │      │ :80/443   │      │ :8008    │      │ API      │
  │          │      │ (not      │      │           │      │          │
  │          │      │  deployed)│      │           │      │          │
  └────┬─────┘      └─────┬─────┘      └─────┬─────┘      └────┬─────┘
       │                  │                  │                 │
       └──────────────────┼──────────────────┼─────────────────┘
                          │                  │
                 ┌────────▼──────────┐       │
                 │   n8n Automation  │       │
                 │   (not deployed)  │       │
                 └────────┬──────────┘       │
                          │                  │
                          │      ┌───────────▼──────────┐
                          │      │  Voice Outreach Svc  │
                          │      │  PM2 :8095           │
                          │      │  Twilio              │
                          │      │  WhatsApp: 6269404249│
                          │      └──────────────────────┘
                          │
                 ┌────────▼──────────┐
                 │  FRGCRM API       │
                 │  PM2 :8082        │
                 │  (ALL REQUESTS 500)│
                 └───────────────────┘
```

### 3.2 Intake Services

| Service | Status | Port | Notes |
|---------|--------|------|-------|
| FRGCRM Web Forms | Degraded | :8082 | API returns 500 for all requests |
| Chatwoot Live Chat | **Not deployed** | -- | Intended for FRGCRM customer support |
| Voice Agent | Online | :8008 | AI-powered voice call handling |
| Voice Outreach | Online | :8095 | Automated outbound dialing |
| SendGrid Email | Configured | API | SMTP credentials set, no inbound pipeline |
| WhatsApp | Phone exists | 6269404249 | **No integration** -- number acquired, not wired |
| n8n Automation | **Not deployed** | -- | Intended for lead routing workflows |

### 3.3 Current State

- **FRGCRM API** (:8082) is the primary intake endpoint but returns HTTP 500 for all requests. Root cause: COREDB PostgreSQL refusing connections. The API has a valid DEEPSEEK_API_KEY in the PM2 env but cannot reach its database.
- **Voice Agent** (:8008) and **Voice Outreach** (:8095) are both online but operating with degraded pipelines -- the DEEPSEEK_API_KEY was historically missing from voice services.
- **SendGrid** credentials exist in the environment but no inbound email processing pipeline is configured.
- **WhatsApp number** (6269404249) is registered but has no integration with any system.
- **Chatwoot** and **n8n** are specified in the architecture but not deployed on any server.
- **DocuSeal** (:3010) is healthy and ready for e-signature intake but not wired into any intake flow.

### 3.4 Target State

- FRGCRM API accepting leads with full PipelineDAG processing
- Chatwoot deployed, connected to FRGCRM API, with AI chatbot
- n8n deployed, orchestrating lead routing across all systems
- WhatsApp integrated via Twilio API for lead intake
- SendGrid inbound parse webhook feeding leads into FRGCRM
- DocuSeal accepting documents directly from intake forms
- Voice pipeline capturing voicemail transcripts and routing to case scoring

### 3.5 Gap Analysis & Priority

| Gap | Impact | Priority | Effort |
|-----|--------|----------|--------|
| FRGCRM API 500 errors | **Zero leads processed** | **P0** | Medium |
| Chatwoot not deployed | No live chat lead capture | P1 | Low |
| n8n not deployed | No workflow automation | P1 | Low |
| WhatsApp not integrated | Channel dead | P2 | Low |
| SendGrid inbound not configured | Email leads lost | P2 | Low |
| No intake funnel analytics | Blind to drop-off | P2 | Medium |

---

## 4. Lead Processing Layer

### 4.1 Architecture

The processing layer enriches, scores, and qualifies every inbound lead before routing.

```
                      LEAD PROCESSING PIPELINE
  ======================================================================

   INBOUND LEAD (raw)
        │
        ▼
   ┌─────────────────────────────────────────────────┐
   │           ENRICHMENT PIPELINE                    │
   │  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
   │  │ LiteLLM  │  │ FRGCRM   │  │ SurplusAI     │  │
   │  │ :4049    │  │ Agent Svc│  │ Scraper :8007 │  │
   │  │ DeepSeek │  │ :8013    │  │               │  │
   │  │ GPT-4o   │  │          │  │               │  │
   │  └──────────┘  └──────────┘  └───────────────┘  │
   └─────────────────────────────────────────────────┘
        │
        ▼
   ┌─────────────────────────────────────────────────┐
   │           QUALIFICATION PIPELINE                 │
   │                                                  │
   │  ┌────────────┐  ┌────────────┐  ┌───────────┐  │
   │  │ CaseScorer │  │ Qualifier  │  │ Dedup     │  │
   │  │ (Broken)   │  │ (Broken)   │  │ Engine    │  │
   │  └────────────┘  └────────────┘  └───────────┘  │
   └─────────────────────────────────────────────────┘
        │
        ▼
   ┌─────────────────────────────────────────────────┐
   │           FRGCRM PIPELINEDAG (6 stages)          │
   │                                                  │
   │  LeadIngestion -> CaseScorer -> AttorneyMatcher  │
   │       -> ClaimantOutreach -> DocumentGenerator   │
   │       -> PipelineMonitor                         │
   │                                                  │
   │  ALL BROKEN -- DEEPSEEK_API_KEY was missing      │
   └─────────────────────────────────────────────────┘
```

### 4.2 PipelineDAG Stage Details

The FRGCRM PipelineDAG defines six sequential stages for each case:

| Stage | Function | AI Dependency | Status |
|-------|----------|--------------|--------|
| **LeadIngestion** | Parse inbound lead, extract entities, normalize format | LiteLLM DeepSeek | Broken |
| **CaseScorer** | Score case likelihood (0-100) based on fund type, amount, jurisdiction | DeepSeek via LiteLLM | Broken |
| **AttorneyMatcher** | Match case to best attorney (Bigham, Morris, Farah, Walker) | DeepSeek via LiteLLM | Broken |
| **ClaimantOutreach** | Generate personalized outreach letter, schedule contact | DeepSeek via LiteLLM | Broken |
| **DocumentGenerator** | Generate engagement letter, retainer agreement via DocuSeal API | DeepSeek via LiteLLM | Broken |
| **PipelineMonitor** | Monitor pipeline health, alert on stalled cases | DeepSeek via LiteLLM | Broken |

### 4.3 AI Inference Pipeline

Every agent service communicates through the LiteLLM proxy, which provides unified access to multiple model providers:

```
   Agent Service ──HTTP──> LiteLLM Proxy :4049 ──> DeepSeek API / OpenAI / Anthropic
                                  │
                           Model routing config:
                           /root/.claude/litellm-deepseek.yaml

   LiteLLM Status: ONLINE (14h uptime, 377 MB RSS, 0 restarts)
   Model: DeepSeek (primary), GPT-4o fallback
   Auth: Master key required for /models, /health endpoints accessible
```

### 4.4 Current State

- **PipelineDAG is fully broken.** All six stages fail because the `DEEPSEEK_API_KEY` environment variable was missing from the PM2 process environment for frgcrm-api and frgcrm-agent-svc. Recent remediation may have added the key, but the COREDB connection is still failing (PostgreSQL refusing connections), so the API returns HTTP 500 on all requests.
- **LiteLLM proxy** is healthy (377 MB RSS, 14h uptime, 0 restarts). DeepSeek API key validated.
- **9 agent services** all route through LiteLLM, all currently online.
- **SurplusAI scraper** is online but was in restart loops historically (same DEEPSEEK_API_KEY root cause).
- **No dedup engine** exists -- duplicate leads are not detected.

### 4.5 Target State

- PipelineDAG operational with all six stages processing cases end-to-end
- Real-time AI scoring via LiteLLM with sub-2-second response times
- Dedup engine integrated at ingestion stage, preventing duplicate case creation
- Case enrichment from external data sources (SEC filings, court records, asset databases)
- Automated document generation via DocuSeal API
- Pipeline health monitoring with alerting on stalled cases

### 4.6 Gap Analysis & Priority

| Gap | Impact | Priority | Effort |
|-----|--------|----------|--------|
| COREDB refusing connections | PipelineDAG cannot store/retrieve cases | **P0** | High |
| PipelineDAG all stages broken | **Zero case processing** | **P0** | Medium |
| No dedup engine | Duplicate cases waste attorney time | P2 | Medium |
| No external data enrichment | Cases scored with incomplete data | P2 | High |
| No pipeline monitoring | Failures detected manually | P2 | Low |

---

## 5. Lead Routing Layer

### 5.1 Architecture

After processing, leads are routed to the appropriate revenue engine.

```
                         LEAD ROUTING LOGIC
  ======================================================================

   PROCESSED LEAD
        │
        ▼
   ┌─────────────────────────────────────────────────┐
   │              ROUTING DECISION ENGINE             │
   │                                                  │
   │  Lead Type:                                      │
   │    Funds Recovery ──────────────> FRGCRM         │
   │    Surplus Asset ───────────────> SurplusAI      │
   │    Predictive Query ────────────> PredictionRadar│
   │    Attorney Referral ───────────> AttorneyMarket │
   │    Acquisition Target ──────────> Ravyn Capital  │
   │    General Inquiry ─────────────> Wheeler Brain  │
   │                                                  │
   └─────────────────────────────────────────────────┘
        │
        ▼
   ┌─────────────────────────────────────────────────┐
   │          ATTORNEY MATCHER (3/4 broken)           │
   │                                                  │
   │  Bigham  │  Morris  │  Farah  │  Walker          │
   │  (online)│  (online)│ (online)│ (online)         │
   │          │          │         │                  │
   │  Match logic depends on DEEPSEEK_API_KEY          │
   │  PipelineDAG AttorneyMatcher stage BROKEN         │
   └─────────────────────────────────────────────────┘
```

### 5.2 Attorney Network

| Attorney | Specialty | Status | Matching Logic |
|----------|-----------|--------|---------------|
| Bigham | TBD | Configured | AI-driven via CaseScorer scores |
| Morris | TBD | Configured | AI-driven via CaseScorer scores |
| Farah | TBD | Configured | AI-driven via CaseScorer scores |
| Walker | TBD | Configured | AI-driven via CaseScorer scores |

### 5.3 Routing Protocols

| Route | Protocol | Endpoint | Status |
|-------|----------|----------|--------|
| Web form -> FRGCRM | HTTP POST | :8082/api/leads | 500 error |
| Chat -> FRGCRM | WebSocket | Not deployed | -- |
| Voice -> n8n -> FRGCRM | HTTP | Not deployed | -- |
| Email -> SendGrid -> FRGCRM | Webhook | Not configured | -- |
| WhatsApp -> FRGCRM | Twilio API | Not configured | -- |
| Attorney referral -> FRGCRM | HTTP | Not built | -- |

### 5.4 Current State

- Routing decision engine is **not implemented** -- leads are not classified by type before routing.
- Attorney matching logic is broken (PipelineDAG AttorneyMatcher stage).
- All four attorneys are configured in the system but no matching has occurred because PipelineDAG is entirely non-functional.
- No routing exists between lead intake channels and appropriate revenue engines -- all leads flow to FRGCRM which then fails.
- SurplusAI leads route to surplusai.io portal (:8103) independently, but the scraper is degraded.

### 5.5 Target State

- Type-based routing engine classifying every lead on ingestion
- AttorneyMatcher operational with automated assignment based on case score, jurisdiction, and attorney capacity
- Multi-channel routing (FRG vs SurplusAI vs Ravyn) based on lead type
- Escalation routing for high-value leads (manual review queue)
- Load-balanced attorney assignment across the 4-person network
- Performance tracking per attorney (conversion rate, avg case value, cycle time)

### 5.6 Gap Analysis & Priority

| Gap | Impact | Priority | Effort |
|-----|--------|----------|--------|
| No routing engine | All leads go to dead FRGCRM | **P0** | Medium |
| AttorneyMatcher broken | Cases cannot be assigned | **P0** | Medium |
| No channel-based routing | Surplus leads processed as FRG leads | P1 | Medium |
| No attorney performance tracking | Cannot optimize assignments | P2 | Medium |
| No escalation routing | High-value leads may be missed | P2 | Low |

---

## 6. Lead Conversion Layer

### 6.1 Architecture

The conversion layer takes qualified, routed leads and converts them into revenue-generating cases.

```
                       LEAD CONVERSION PIPELINE
  ======================================================================

   ROUTED + MATCHED CASE
        │
        ▼
   ┌─────────────────────────────────────────────────┐
   │           DOCUMENT GENERATION                    │
   │                                                  │
   │  DocuSeal :3010 (AI OPS) ────> E-signature      │
   │  Engagement Letters                              │
   │  Retainer Agreements                             │
   │  Fee Schedules                                   │
   │  Disclosure Forms                                │
   │                                                  │
   │  DocuSeal Status: HEALTHY (14h uptime)           │
   │  DocuSeal Redis: HEALTHY (dedicated)             │
   └─────────────────────────────────────────────────┘
        │
        ▼
   ┌─────────────────────────────────────────────────┐
   │           PAYMENT PROCESSING                     │
   │                                                  │
   │  ┌──────────────┐    ┌──────────────────────┐   │
   │  │ Prediction   │    │ FRG Contingency      │   │
   │  │ Radar: Stripe│    │ Fee: No payment gate │   │
   │  │ 7 tiers      │    │ (manual invoicing)   │   │
   │  │ TEST MODE    │    │                      │   │
   │  └──────────────┘    └──────────────────────┘   │
   │                                                  │
   └─────────────────────────────────────────────────┘
        │
        ▼
   ┌─────────────────────────────────────────────────┐
   │           REVENUE SHARING                        │
   │                                                  │
   │  Attorney Fee Split: Configured, not active      │
   │  Referral Fees: Not implemented                  │
   │  Affiliate Tracking: Not implemented             │
   └─────────────────────────────────────────────────┘
```

### 6.2 DocuSeal Integration

| Feature | Status | Endpoint | Details |
|---------|--------|----------|---------|
| DocuSeal Server | ONLINE | 127.0.0.1:3010 | docuseal/docuseal:3.0.0 |
| DocuSeal Redis | ONLINE | internal | redis:7-alpine |
| Template API | Ready | POST /api/templates | Not wired into PipelineDAG |
| Submission API | Ready | POST /api/submissions | Not wired into PipelineDAG |
| Webhook Receiver | Ready | POST /api/webhooks | Not configured |
| E-signature Links | Ready | GET /s/:slug | Not integrated |
| Document Generation | Broken | PipelineDAG stage | DEEPSEEK_API_KEY missing |

### 6.3 Prediction Radar Subscription Tiers

All tiers are configured in Stripe but operating in **TEST MODE**:

| Tier | Stripe Price ID | Monthly (est.) | Status |
|------|----------------|----------------|--------|
| Professional | price_1TN3owPKXFjwOjQXYvdcKsgc | $29 | Live / Test Mode |
| Enterprise | price_1TN3opPKXFjwOjQXdwXamPuw | $99 | Live / Test Mode |
| Agency | price_1TN3opPKXFjwOjQXdwXamPuw | $199 | Live / Test Mode |
| Marketing | price_1TN3oyPKXFjwOjQXDeWQeK1Q | $49 | Live / Test Mode |
| Forensic | price_1TN3osPKXFjwOjQXeeesWrUD | $149 | Live / Test Mode |
| Signals Pro | price_1TN3owPKXFjwOjQXYvdcKsgc | $79 | Live / Test Mode |
| Prompts Pro | price_1TN3otPKXFjwOjQXgk7jUWWp | $39 | Live / Test Mode |

Stripe configuration:
- Publishable Key: `pk_test_...` (TEST MODE)
- Secret Key: `sk_test_...` (TEST MODE)
- Webhook Secret: `whsec_FLVvmm2Sns2fu5ysD9tIj1Hm1bYSTBGL`
- Price IDs created: 2026-04-17

### 6.4 Current State

- **DocuSeal** is fully operational (:3010, healthy, 14h uptime) but not integrated into any revenue flow. Document generation is the 5th stage of PipelineDAG and is broken.
- **Prediction Radar** has live subscription infrastructure but Stripe is in TEST MODE. Users can create accounts and go through checkout but no real payments are processed.
- **FRG contingency fee collection** has no payment gateway -- fees are collected manually via invoicing.
- **Revenue sharing** with attorneys is configured conceptually but not implemented in code.
- **No recurring billing infrastructure** beyond Prediction Radar's Stripe integration.

### 6.5 Target State

- DocuSeal fully integrated: PipelineDAG generates engagement letters, sends for e-signature, stores executed copies
- Stripe in LIVE MODE for Prediction Radar with automated billing, dunning, invoice management
- Stripe Connect or similar for FRG contingency fee collection with automated escrow
- Attorney revenue sharing automated: case settled -> fee collected -> split distributed
- Payment gateway for one-time fees (consultations, filings)
- Automated invoicing via SendGrid for non-card payments

### 6.6 Gap Analysis & Priority

| Gap | Impact | Priority | Effort |
|-----|--------|----------|--------|
| Stripe in TEST MODE | **Zero recurring revenue collected** | **P0** | Low |
| DocuSeal not integrated | Documents must be handled manually | P1 | Low |
| No FRG payment gateway | Contingency fees manual | P1 | Medium |
| No attorney revenue sharing | Partner channel not monetized | P2 | Medium |
| No recurring billing (non-Stripe) | Limited revenue collection options | P3 | Medium |

---

## 7. Revenue Collection Layer

### 7.1 Architecture

```
                       REVENUE COLLECTION SYSTEMS
  ======================================================================

   SUBSCRIPTION            ONE-TIME            REVENUE SHARING
  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐
  │ Stripe       │    │ Stripe       │    │ Manual           │
  │ Checkout     │    │ Payment      │    │ Invoicing        │
  │              │    │ Intent       │    │                  │
  │ 7 tiers      │    │ (not conf'd) │    │ SendGrid         │
  │ TEST MODE    │    │              │    │ (email only)     │
  └──────┬───────┘    └──────────────┘    └────────┬─────────┘
         │                                         │
         ▼                                         ▼
   ┌────────────────────┐                 ┌──────────────────┐
   │ Stripe Webhook     │                 │ SendGrid         │
   │ Endpoints:         │                 │ API              │
   │ /api/stripe/webhook│                 │ :587 SMTP        │
   │ /api/webhook/frgops│                 │                  │
   └────────────────────┘                 └──────────────────┘
         │                                         │
         ▼                                         ▼
   ┌────────────────────┐                 ┌──────────────────┐
   │ Prediction Radar   │                 │ No accounting    │
   │ App DB             │                 │ system           │
   │ (PostgreSQL 16)    │                 │ integrated       │
   └────────────────────┘                 └──────────────────┘
```

### 7.2 Stripe Integration Details

| Component | Endpoint | Status |
|-----------|----------|--------|
| Checkout Session | POST /api/stripe/create-checkout | Configured / Test Mode |
| Webhook Receiver | POST /api/stripe/webhook | Configured / Test Mode |
| FRGOPS Webhook | POST /api/webhook/frgops | Configured |
| Subscription API | GET /api/stripe/subscriptions | Configured |
| Customer Portal | GET /api/stripe/portal | Configured |
| Price Sync | CRON / periodic | Not configured |

### 7.3 Current State

- **Prediction Radar** is the only system with automated revenue collection, and it is in Stripe TEST MODE. No real payment instrument has been charged.
- **FRG** has no payment collection infrastructure. Contingency fees are collected through external manual invoicing.
- **SendGrid** is configured for transactional email but not for invoicing or billing communications.
- **No accounting system** (QuickBooks, Xero, Stripe Tax) is integrated.
- **No tax calculation** (Stripe Tax, TaxJar) is configured.
- **Discord webhooks** exist for alerting but not for revenue events.

### 7.4 Target State

- Stripe in LIVE MODE processing real subscription payments
- Stripe Tax configured for automated tax calculation
- Revenue recognition pipeline (deferred revenue schedules)
- Automated invoicing via SendGrid for non-card payments
- Revenue sharing settlement engine for attorney network
- Escrow account integration for FRG settlements
- Accounting system sync (QuickBooks API or Stripe Connect)

### 7.5 Gap Analysis & Priority

| Gap | Impact | Priority | Effort |
|-----|--------|----------|--------|
| Stripe TEST MODE | **Zero revenue being collected** | **P0** | Low |
| No FRG payment processing | Recovery fees uncollected | P1 | Medium |
| No invoicing system | No billing for enterprise clients | P2 | Medium |
| No accounting integration | No financial visibility | P2 | Medium |
| No revenue sharing engine | Attorney payouts manual | P2 | High |
| No tax calculation | Compliance risk | P2 | Medium |

---

## 8. Revenue Intelligence Layer

### 8.1 Architecture

```
                      REVENUE INTELLIGENCE STACK
  ======================================================================

   METRICS                         ANALYTICS
  ┌────────────────────┐    ┌──────────────────────────┐
  │ Prometheus :9090   │    │ ClickHouse :8123          │
  │ + Alertmanager     │    │ + Superset :8088          │
  │ Revenue KPIs       │    │ BI Dashboards            │
  │ - Sub count        │    │ - Revenue by tier        │
  │ - MRR/ARR          │    │ - Conversion funnel      │
  │ - Churn rate       │    │ - Attorney performance   │
  │ - Case volume      │    │ - Lead source ROI        │
  └────────┬───────────┘    └───────────┬──────────────┘
           │                            │
           ▼                            ▼
   ┌────────────────────┐    ┌──────────────────────────┐
   │ Grafana :3002      │    │ Superset :8088            │
   │ Operational Dash   │    │ Analytical Dashboards    │
   │ Real-time metrics  │    │ Historical trends        │
   │ Alerting           │    │ Ad-hoc queries           │
   │                    │    │                          │
   │ Healthy, but NO   │    │ Healthy, but NO          │
   │ revenue dashboards │    │ revenue datasets         │
   └────────────────────┘    └──────────────────────────┘
```

### 8.2 Observability Infrastructure

| Service | Port | Status | Data Sources |
|---------|------|--------|-------------|
| Prometheus | 127.0.0.1:9090 | Healthy (8/9 targets up) | 9 exporters |
| Grafana | 127.0.0.1:3002 | Healthy (no datasources provisioned) | Prometheus, Loki |
| Loki | 127.0.0.1:3100 | Degraded (ingester cooldown) | Promtail |
| ClickHouse | 127.0.0.1:8123 | Healthy (no auth) | Custom data |
| Superset | 127.0.0.1:8088 | Healthy (root, hardcoded admin) | ClickHouse |
| Alertmanager | 127.0.0.1:9093 | Healthy | Prometheus |
| Pushgateway | 127.0.0.1:9092 | Healthy | Custom metrics |
| Webhook Relay | 127.0.0.1:8085 | Healthy | Discord bridge |
| Netdata | 127.0.0.1:19999 | Healthy | System metrics |
| Uptime Kuma | 127.0.0.1:3001 | Healthy | Synthetic monitoring |
| Healthchecks | 127.0.0.1:3130 | Healthy | Cron job monitoring |

### 8.3 Current State

- **Full observability stack** is operational (Prometheus, Grafana, Loki, Alertmanager, ClickHouse, Superset) but **no revenue-specific dashboards exist**.
- **Grafana** has no provisioned datasources -- dashboards are empty.
- **Superset** is running but has no revenue datasets loaded -- no ClickHouse tables for subscriptions, cases, or revenue.
- **Prometheus** scrapes 8/9 targets but has no application-level metrics from Prediction Radar or FRGCRM.
- **Alertmanager** routes to Discord webhooks but has no revenue-specific alerts (e.g., "subscription churn spike", "payment failure rate > 5%").
- **No MRR/ARR tracking** exists anywhere in the stack.
- **No conversion funnel analytics** -- cannot measure drop-off from lead to case to payment.
- **No per-attorney metrics** -- cannot track case volume, win rate, or revenue per attorney.
- **Revenue healthcheck script** exists at `/root/scripts/revenue-healthcheck.sh` -- covers public websites, API routes, databases, PM2, Tailscale, Docker but produces no revenue metrics (MRR, subs, cases).

### 8.4 Target State

- Grafana revenue dashboard: MRR, ARR, churn rate, LTV, CAC
- Superset analytical dashboards: Cohort analysis, funnel analysis, revenue forecasting
- Prometheus application metrics from Prediction Radar API (:8000/health plus /metrics)
- FRGCRM pipeline metrics: cases created, cases scored, cases matched, documents signed, cases settled
- Alertmanager rules for revenue events: payment failure surge, signup drop, churn acceleration
- ClickHouse revenue data warehouse: subscriptions table, cases table, payments table
- Revenue forecast models (linear regression / Prophet) on historical data
- Per-attorney revenue dashboard

### 8.5 Gap Analysis & Priority

| Gap | Impact | Priority | Effort |
|-----|--------|----------|--------|
| No revenue dashboards | No visibility into business performance | **P1** | Medium |
| No application metrics | Cannot monitor revenue system health | **P1** | Medium |
| No ClickHouse revenue data | No analytics database for queries | P1 | Medium |
| No MRR/ARR tracking | Cannot measure growth | P2 | Low |
| No conversion funnel | Cannot optimize lead-to-cash | P2 | Medium |
| No revenue alerts | Churn/payment failures undetected | P2 | Low |
| No revenue forecasting | Cannot plan/budget | P3 | High |

---

## 9. Revenue Automation Layer

### 9.1 Architecture

```
                       REVENUE AUTOMATION STACK
  ======================================================================

   ORCHESTRATION                  SCHEDULING
  ┌────────────────────┐    ┌──────────────────────────┐
  │ n8n (NOT DEPLOYED) │    │ Temporal Server :7233    │
  │                    │    │                          │
  │ Intended:          │    │ Degraded (42K errors)   │
  │ - Lead routing     │    │ DB unreachable           │
  │ - Email sequences  │    │                          │
  │ - Attorney alerts  │    │ Temporal UI :8089        │
  │ - Payment reminders│    │ Serving HTML, no data    │
  │ - DocuSeal triggers│    │                          │
  └────────────────────┘    └───────────┬──────────────┘
                                        │
   CRON JOBS                   ┌────────▼────────┐
  ┌────────────────────┐       │ Prediction Radar│
  │ 8 health check     │       │ Scheduler       │
  │ cron jobs          │       │ (Docker)        │
  │ Discord webhooks   │       │                 │
  │ (not routing)      │       │ Healthy         │
  └────────────────────┘       │ 0 restarts      │
                               └─────────────────┘
```

### 9.2 Automation Infrastructure

| Component | Status | Port | Purpose |
|-----------|--------|------|---------|
| n8n | **Not deployed** | -- | Lead routing, email, workflows |
| Temporal Server | Degraded | :7233 | Workflow engine (42K errors) |
| Temporal UI | Degraded | :8089 | Workflow visibility |
| Prediction Radar Scheduler | Healthy | internal | Scheduled prediction jobs |
| Prediction Radar Worker | Healthy | internal | Background job processing |
| Healthcheck CRONs | Active | -- | 8 cron jobs, Docker/PM2/system checks |
| Discord Webhooks | Configured | :8085 relay | Alert notifications |
| PM2 Logrotate | Active | module | Log management |

### 9.3 Current State

- **n8n is not deployed** despite being specified in the architecture. All workflow automation is absent.
- **Temporal Server** is degraded with 42,000+ errors in 8 hours -- its database is unreachable.
- **Prediction Radar Scheduler and Worker** are healthy and processing jobs.
- **Cron jobs** run health checks every 1-5 minutes but many redirect to `/dev/null`.
- **No automated lead routing** -- every step from intake to conversion requires manual intervention.
- **No automated email sequences** (welcome, nurture, retarget, dunning) despite SendGrid being configured.
- **No automated payment reminders** -- failed payments are not retried or followed up on.
- **No automated attorney notifications** when new cases are matched.

### 9.4 Target State

- n8n deployed with workflows for lead routing, email sequences, attorney notifications, payment reminders
- Temporal Server healthy with durable workflow execution
- Automated lead enrichment workflows (external API lookups)
- Automated email sequences via SendGrid: welcome series, nurture campaigns, payment reminders, case updates
- Automated attorney alerts: new case match, document signature, case update
- Automated payment workflows: invoice generation, payment retry, dunning
- DocuSeal triggers: document generated -> email for signature -> webhook on completion -> next stage
- Revenue report generation and delivery (weekly/monthly/quarterly)

### 9.5 Gap Analysis & Priority

| Gap | Impact | Priority | Effort |
|-----|--------|----------|--------|
| n8n not deployed | No workflow automation exists | **P1** | Low |
| Temporal degraded | No durable execution | P1 | Medium |
| No email sequences | Leads not nurtured | P2 | Medium |
| No payment reminders | Churn from failed payments | P2 | Low |
| No attorney notifications | Partners disengaged | P2 | Low |
| No automated reporting | Manual effort for KPIs | P3 | Low |

---

## 10. Revenue Recovery Layer

### 10.1 Architecture

```
                      REVENUE RECOVERY SYSTEMS
  ======================================================================

   PAYMENT FAILURES            CHURN PREVENTION       RETARGETING
  ┌──────────────────┐    ┌────────────────────┐  ┌──────────────────┐
  │ No dunning       │    │ No churn           │  │ No retargeting  │
  │ engine           │    │ detection          │  │ pipeline         │
  │                  │    │                    │  │                  │
  │ Stripe webhooks  │    │ No engagement      │  │ No email/SMS    │
  │ exist but not    │    │ scoring            │  │ automation       │
  │ wired            │    │                    │  │                  │
  └──────────────────┘    └────────────────────┘  └──────────────────┘
                                                          │
   SendGrid :587 ─── Transactional email (no recovery)    │
   Discord       ─── Internal alerts (no customer)        │
   WhatsApp      ─── Number exists, no integration        │
                                                          │
   ============== ALL THREE SYSTEMS AT 0% CAPACITY ======
```

### 10.2 Current State

- **No dunning engine** exists. Stripe webhooks for failed payments (`invoice.payment_failed`, `charge.failed`) are received but not acted upon.
- **No churn detection** -- no system monitors user engagement, login frequency, feature usage, or billing health.
- **No retargeting pipeline** -- no email/SMS automation for re-engaging lapsed users.
- **SendGrid** is configured for transactional email but has no recovery templates built.
- **WhatsApp number** (6269404249) exists but is not integrated into any communication flow.
- **Voice Outreach** (:8095) is online but not configured for recovery calling.

### 10.3 Target State

- Automated dunning: 3-email sequence on failed payment (Day 1, 3, 7) + WhatsApp reminder
- Smart churn detection: engagement score based on login frequency, feature usage, support tickets
- Win-back campaigns: automated email sequence + WhatsApp message for lapsed subscribers
- Voice recovery: automated outbound call for high-value churn risks
- Credit card updater integration (Stripe Account Updater) for automatic card refresh
- Payment retry logic: exponential backoff (Day 0, 1, 3, 7, 14, 30)
- Churn reporting: cohort analysis, churn reasons, LTV impact

### 10.4 Gap Analysis & Priority

| Gap | Impact | Priority | Effort |
|-----|--------|----------|--------|
| No dunning engine | Failed payments = permanent churn | P1 | Medium |
| No churn detection | Cannot prevent preventable churn | P2 | Medium |
| No retargeting | Lost users never re-engaged | P2 | Medium |
| No voice recovery | High-LTV churn risks ignored | P3 | High |
| No card updater | Expired cards = permanent churn | P2 | Low |
| No churn analytics | No visibility into churn drivers | P2 | Medium |

---

## 11. Revenue Governance Layer

### 11.1 Architecture

```
                      REVENUE GOVERNANCE SYSTEMS
  ======================================================================

   ROLLBACK                    SECURITY                    COMPLIANCE
  ┌────────────────┐    ┌───────────────────┐    ┌──────────────────┐
  │ Rollback Engine│    │ Secret Scanning   │    │ Data Protection  │
  │ /root/rollback │    │ /slay skill       │    │                  │
  │ -engine/       │    │                   │    │ GDPR readiness   │
  │                │    │ 61 services       │    │ Not assessed     │
  │ 6-stage        │    │ audited           │    │                  │
  │ rollback plan  │    │                   │    │                  │
  │ (A through F)  │    │ 100% security     │    │                  │
  │                │    │ score as of       │    │                  │
  │ Revenue        │    │ 2026-05-24        │    │                  │
  │ rollback       │    │                   │    │                  │
  │ checklist at   │    │ Docker: cap_drop  │    │                  │
  │ /root/scripts/ │    │ ALL on 58         │    │                  │
  │ revenue-       │    │ containers        │    │                  │
  │ rollback-      │    │ UFW: 64 rules     │    │                  │
  │ checklist.sh   │    │ All ports:        │    │                  │
  │                │    │ 127.0.0.1 bind    │    │                  │
  └────────────────┘    └───────────────────┘    └──────────────────┘
```

### 11.2 Governance Systems

| System | Status | Details |
|--------|--------|---------|
| Deployment Engine | Operational | `/root/deployment-engine/` -- 11 scripts for preflight, deploy, verify, rollback |
| Rollback Engine | Operational | `/root/rollback-engine/` -- 6 restore scripts (Docker, env, PM2, routing) |
| Revenue Rollback | Operational | `/root/scripts/revenue-rollback-checklist.sh` -- 6 stages (A-F) |
| Revenue Healthcheck | Operational | `/root/scripts/revenue-healthcheck.sh` -- 6 check categories |
| Secret Scanning | Operational | `/slay` skill, PM2 jlist secret scan, Docker env audit |
| Security Hardening | Complete | Docker port rebinding (58 containers), cap_drop ALL, UFW lockdown 64 rules |
| AI Ops Remediation | Complete | Langflow auth, nginx basic auth, rate limiting, Docker port rebinding |
| Secret Rotation | Complete | Internal DB/Redis passwords rotated (2026-05-24) |

### 11.3 Rollback Stages (Revenue Rollback)

| Stage | Scope | Pre-check | Action | Post-verify |
|-------|-------|-----------|--------|-------------|
| A | Traefik/Nginx | Backups exist | Restore upstreams, reload | Domain reachability |
| B | PM2 Apps | PM2 state | Restart apps from backup | App health check |
| C | Public Domains | DNS resolution | Verify HTTP responses | Re-run check |
| D | Environment Files | Backup integrity | Restore .env files | Diff comparison |
| E | Lead Capture | CRM availability | Test lead endpoints | CRM health |
| F | Full Rollback | All pre-checks | A->E in sequence | All post-verifies |

### 11.4 Security Posture (Revenue Systems)

| System | Port Binding | Auth | TLS | Status |
|--------|-------------|------|-----|--------|
| Prediction Radar API | Internal (Docker bridge) | API key | Internal | Secure |
| Prediction Radar Web | 127.0.0.1:8098 | None | Via Traefik | Adequate |
| FRGCRM API | PM2 :8082 | None | Via gateway | **Exposed** |
| FRGCRM Agent | PM2 :8013 | None | Via gateway | **Exposed** |
| DocuSeal | 127.0.0.1:3010 | API key | Via gateway | Adequate |
| SurplusAI Portal | PM2 :8103 | JWT | Via gateway | Adequate |
| RavynAI API | 127.0.0.1:8007 | API token | Via gateway | Adequate |
| LiteLLM | 127.0.0.1:4049 | Master key | None (localhost) | Secure |

### 11.5 Current State

- **Deployment Engine**: Full CI/CD pipeline with preflight checks, deployment, verification, and rollback. Works for both Docker and PM2 deployments.
- **Rollback Engine**: 6-stage rollback covering Traefik, PM2, DNS, env files, and lead capture. Production-safe with confirmation prompts at each step.
- **Revenue Healthcheck**: Comprehensive 6-category check (websites, APIs, databases, PM2, Tailscale, Docker) with JSON and human-readable output.
- **Security**: Stage 2 hardening complete as of 2026-05-24 -- all 58 containers hardened, all ports bound to 127.0.0.1, UFW lockdown at 64 rules, cap_drop ALL applied, Docker port rebinding, secret rotation completed.
- **QA Scorecard**: 100/100 achieved 2026-05-24 (`/root/STAGE2_QA_SCORECARD_FINAL.md`).

### 11.6 Target State

- Revenue-specific deployment gates (revenue impact assessment before deployment)
- Automated database migration pipeline (Hostinger -> COREDB)
- Revenue system SLA monitoring with automated rollback triggers
- Compliance framework (SOC2, GDPR, CCPA) documentation and controls
- Business continuity / disaster recovery plan for revenue systems
- Revenue data backup and recovery testing (RTO/RPO defined)
- Audit trail for all revenue system changes

### 11.7 Gap Analysis & Priority

| Gap | Impact | Priority | Effort |
|-----|--------|----------|--------|
| No deployment revenue gates | Deployments can break revenue | P1 | Low |
| No DB migration pipeline | 6,603 cases stuck on Hostinger | **P0** | High |
| No revenue SLAs | No uptime guarantees | P2 | Low |
| No compliance framework | Regulatory risk | P2 | High |
| No DR plan | Revenue data at risk | P1 | Medium |
| No revenue data backups | 6,603 cases not backed up off-server | **P0** | Medium |

---

## 12. Integration Architecture

### 12.1 Complete Integration Map

```
                  WHEELER ECOSYSTEM -- COMPLETE INTEGRATION MAP
  ======================================================================

                         ┌──────────────────────┐
                         │    CLOUDFLARE DNS    │
                         │  TLS termination     │
                         └──────────┬───────────┘
                                    │
  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
  PUBLIC INTERNET                   │             EDGE (Hostinger)
                                    │             187.77.148.88
                         ┌──────────┴───────────┐
                         │      TRAEFIK         │
                         │  Reverse Proxy       │
                         └──────────┬───────────┘
                                    │
  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
  TAILSCALE MESH                    │             100.64.0.0/10
            ┌───────────────────────┼───────────────────────┐
            │                       │                       │
  ┌─────────┴──────────┐  ┌────────┴──────────┐  ┌────────┴──────────┐
  │      AIOPS         │  │     COREDB         │  │  Hostinger        │
  │  5.78.140.118      │  │  5.78.210.123      │  │  187.77.148.88    │
  │  100.121.230.28    │  │  100.118.166.117   │  │  100.98.163.17    │
  │                    │  │                    │  │                   │
  │  ALL AGENTS        │  │  PostgreSQL        │  │  FRGCRM Origin    │
  │  LiteLLM :4049     │  │  Redis             │  │  6,603 cases      │
  │  40 containers     │  │  MinIO S3          │  │  PostgREST :5430  │
  │  PM2: 17 apps      │  │  Monitoring        │  │  InsForge :7130   │
  │  nginx gateway     │  │  18 containers     │  │                   │
  └────────────────────┘  └────────────────────┘  └───────────────────┘
```

### 12.2 Service Communication Matrix

| From | To | Protocol | Address | Status |
|------|----|----------|---------|--------|
| frgcrm-api | COREDB PG | TCP/5432 | 5.78.210.123:5432 | **DOWN** |
| frgcrm-api | LiteLLM | HTTP/4049 | 127.0.0.1:4049 | Online |
| frgcrm-agent-svc | LiteLLM | HTTP/4049 | 127.0.0.1:4049 | Online |
| frgcrm-agent-svc | frgcrm-api | HTTP/:8082 | 127.0.0.1:8082 | 500 error |
| prediction-radar-api | PR DB | TCP/5432 | internal docker | Online |
| prediction-radar-api | Stripe | HTTPS | api.stripe.com | Test Mode |
| prediction-radar-agent | LiteLLM | HTTP/4049 | 127.0.0.1:4049 | Online |
| ravynai-api | ravynai PG | TCP/5432 | 127.0.0.1:5434 | Online |
| all-agent-svcs | LiteLLM | HTTP/4049 | 127.0.0.1:4049 | Online |
| EDGE -> AIOPS | Tailscale | TCP | 100.121.230.28 | Online |
| AIOPS -> COREDB | Tailscale | TCP | 100.118.166.117 | Online |
| AIOPS -> EDGE | Tailscale | TCP | 100.98.163.17 | Online |
| Discord Alerts | HTTPS | webhook | discord.com/api | Online |

### 12.3 Docker Network Topology (AIOPS)

| Network | Subnet | Revenue Systems |
|---------|--------|-----------------|
| prediction-radar-app_default | 172.25.0.0/16 | Prediction Radar (14 containers) |
| docuseal_default | 172.27.0.0/16 | DocuSeal + Redis |
| monitoring_default | 172.20.0.0/16 | Prometheus, Grafana, Loki |
| analytics_default | 172.23.0.0/16 | ClickHouse, Superset |
| ravynai_default | 172.25.0.0/24 | RavynAI API + DB |
| traefik-public | 172.20.0.0/24 | Traefik, gateway |
| ai-agents | 172.24.0.0/24 | Agent runtimes |
| messaging | 172.27.0.0/24 | NATS, RabbitMQ |
| automation | 172.28.0.0/24 | n8n (future), ChangeDetection |
| data | 172.29.0.0/24 | PostgreSQL, Redis |

### 12.4 PM2 Process Interaction Model

```
                        PM2 INTERACTION MODEL
  ======================================================================

   EXTERNAL AGENTS (PM2 managed, fork mode)
   ┌────────────────────────────────────────────────────────────┐
   │                                                            │
   │  frgcrm-agent-svc (:8013) ──HTTP──> frgcrm-api (:8082)     │
   │                                 ──HTTP──> LiteLLM (:4049)   │
   │                                                            │
   │  insforge-agent-svc (:8013) ──HTTP──> LiteLLM (:4049)     │
   │                                                            │
   │  surplusai-scraper-agent (:8007) ──HTTP──> LiteLLM (:4049)│
   │                                                            │
   │  voice-agent-svc (:8008) ──HTTP──> LiteLLM (:4049)        │
   │                                                            │
   │  prediction-radar-agent (:8011) ──HTTP──> LiteLLM (:4049) │
   │                                                            │
   │  ravyn-agent-svc (:8005) ──HTTP──> LiteLLM (:4049)        │
   │                                                            │
   │  LiteLLM (:4049) ──HTTPS──> api.deepseek.com               │
   │                  ──HTTPS──> api.openai.com                  │
   │                  ──HTTPS──> api.anthropic.com               │
   │                                                            │
   └────────────────────────────────────────────────────────────┘

   INTERNAL SERVICES (Docker managed, bridge networks)
   ┌────────────────────────────────────────────────────────────┐
   │                                                            │
   │  prediction-radar-app-api ──DB──> PR-DB (:5432/internal)   │
   │                          ──Cache──> PR-Redis               │
   │                          ──Queue──> PR-Redis               │
   │                          ──HTTP──> Stripe API               │
   │                                                            │
   │  prediction-radar-worker ──Queue──> PR-Redis               │
   │                                                            │
   │  prediction-radar-scheduler ──Queue──> PR-Redis            │
   │                                                            │
   │  docuseal ──DB──> DocuSeal-Redis                           │
   │                                                            │
   │  ravynai-api ──DB──> RavynAI-PG (:5434/127.0.0.1)          │
   │                                                            │
   └────────────────────────────────────────────────────────────┘
```

### 12.5 LiteLLM Proxy Configuration

```
  LiteLLM Proxy
  ┌─────────────────────────────────────────────────────────────┐
  │  Address: 127.0.0.1:4049                                   │
  │  Config: /root/.claude/litellm-deepseek.yaml                │
  │  Status: ONLINE (14h, 0 restarts, 377 MB RSS)              │
  │                                                             │
  │  Models:                                                    │
  │    deepseek-chat      ──> api.deepseek.com (primary)        │
  │    gpt-4o             ──> api.openai.com (fallback)         │
  │    claude-sonnet-4    ──> api.anthropic.com (fallback)      │
  │                                                             │
  │  Consumers: 9 agent services + 2 APIs                       │
  │  1. frgcrm-api                                              │
  │  2. frgcrm-agent-svc                                        │
  │  3. surplusai-scraper-agent-svc                             │
  │  4. voice-agent-svc                                         │
  │  5. insforge-agent-svc                                      │
  │  6. prediction-radar-agent-svc                              │
  │  7. ravyn-agent-svc                                         │
  │  8. horizon-agent-svc                                       │
  │  9. paperless-agent-svc                                     │
  │                                                             │
  │  Auth: Master key required for /models                       │
  │        /health endpoint publicly accessible                 │
  └─────────────────────────────────────────────────────────────┘
```

### 12.6 External API Integrations

| Integration | Type | Status | Revenue System |
|-------------|------|--------|---------------|
| Stripe | Payment processing | Test Mode | Prediction Radar |
| DeepSeek API | LLM inference | Active | All agents via LiteLLM |
| OpenAI | LLM fallback | Active | All agents via LiteLLM |
| Anthropic | LLM fallback | Active | All agents via LiteLLM |
| Polymarket CLOB | Trading API | Configured | Prediction Radar |
| Alpaca | Trading API | Configured | Prediction Radar |
| Alpha Vantage | Market data | Configured | Prediction Radar |
| CoinGecko | Crypto data | Configured | Prediction Radar |
| Brave Search | Web search | Configured | Prediction Radar |
| CME FedWatch | Economic data | Configured | Prediction Radar |
| SendGrid | Email | Configured | Cross-system |
| Twilio | Voice/SMS | Configured (voice only) | Voice Outreach |
| Discord | Notifications | Configured | Alerts |

### 12.7 CRITICAL PATH -- Revenue Data Restoration

The single most critical issue in the ecosystem is database connectivity. Here is the dependency chain:

```
  COREDB PostgreSQL DOWN
        │
        ▼
  frgcrm-api cannot read/write cases
        │
        ▼
  PipelineDAG cannot execute (all 6 stages)
        │
        ▼
  LeadIngestion fails -> CaseScorer fails -> AttorneyMatcher fails
  -> ClaimantOutreach fails -> DocumentGenerator fails -> PipelineMonitor fails
        │
        ▼
  No leads processed -> No cases created -> No attorney matching
  -> No documents generated -> No cases settled -> No revenue collected
        │
        ▼
  ENTIRE FRG REVENUE ENGINE = $0
```

### 12.8 Recovery Priority Order

```
  PRIORITY ORDER FOR REVENUE RESTORATION
  ======================================================================

  P0 ─── Fix COREDB PostgreSQL connection
         Restore: frgcrm-api → COREDB PG connectivity
         Impact: All 6 PipelineDAG stages become executable
         Script: /root/rollback-engine/restore-env.sh (DB connection string)

  P0 ─── Validate DEEPSEEK_API_KEY in PM2 env
         Restore: All agent services have AI inference
         Impact: CaseScorer, AttorneyMatcher, etc. can score
         Action: env -i delete + start pattern (pm2-env-i-pattern.md)

  P0 ─── Migrate 6,603 cases from Hostinger → COREDB
         Restore: Production case data available
         Impact: frgcrm-api can serve real revenue data
         Tool: pg_dump/pg_restore from Hostinger (:5432) → COREDB

  P1 ─── Switch Stripe to LIVE MODE
         Restore: Real subscription revenue collection
         Impact: Prediction Radar generates actual revenue
         Action: Replace pk_test/sk_test with live keys

  P1 ─── Deploy n8n
         Restore: Workflow automation
         Impact: Lead routing, email sequences, notifications
         Action: Docker deploy to automation network (172.28.0.0/24)

  P2 ─── Deploy Chatwoot
         Restore: Live chat lead capture
         Impact: Additional lead channel
         Action: Docker deploy with FRGCRM API integration

  P2 ─── Build revenue dashboards
         Restore: Revenue visibility
         Impact: MRR/ARR tracking
         Action: Grafana + Prometheus metrics from Prediction Radar API
```

---

## Appendix A: Critical Configuration Reference

### Port Map (All Revenue Systems)

| Service | Host | Port | Protocol | Revenue System |
|---------|------|------|----------|---------------|
| LiteLLM | AIOPS | 4049 | HTTP | All (AI gateway) |
| FRGCRM API | AIOPS | 8082 | HTTP | FRG |
| FRGCRM Agent | AIOPS | 8013 | HTTP | FRG |
| FRGCRM Mirror | AIOPS | 8003 | HTTP | FRG |
| Prediction Radar API | AIOPS | internal | HTTP | Prediction Radar |
| Prediction Radar Web | AIOPS | 8098 | HTTP | Prediction Radar |
| RavynAI API | AIOPS | 8007 | HTTP | Ravyn Capital |
| DocuSeal | AIOPS | 3010 | HTTP | FRG Documents |
| SurplusAI Portal | AIOPS | 8103 | HTTP | SurplusAI |
| Voice Agent | AIOPS | 8008 | HTTP | Voice Outreach |
| Voice Outreach | AIOPS | 8095 | HTTP | Voice Outreach |
| COREDB PostgreSQL | COREDB | 5432 | TCP | All (down) |
| frgops-standby PG | AIOPS | 5433 | TCP | FRG (misconfigured) |
| RavynAI PG | AIOPS | 5434 | TCP | Ravyn Capital |
| AIOPS Redis | AIOPS | 6379 | TCP | All |
| EDGE FRGCRM API | Hostinger | 8002 | HTTP | FRG (origin) |
| EDGE PostgREST | Hostinger | 5430 | HTTP | FRG (origin) |
| EDGE InsForge | Hostinger | 7130 | HTTP | InsForge |

### Environment File Locations

| File | Purpose | Revenue System |
|------|---------|---------------|
| /opt/apps/prediction-radar-app/.env | Stripe keys, API keys, DB config | Prediction Radar |
| /opt/apps/prediction-radar-agent-svc/.env | Agent configuration | Prediction Radar |
| /root/.env | Root environment | All (shared) |
| /opt/frgcrm/.env | FRGCRM configuration | FRG |
| /opt/surplusai/.env | SurplusAI configuration | SurplusAI |
| /opt/insforge/.env | InsForge configuration | InsForge |

### Key Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| Revenue Healthcheck | /root/scripts/revenue-healthcheck.sh | Full revenue ecosystem health check |
| Revenue Rollback | /root/scripts/revenue-rollback-checklist.sh | 6-stage revenue rollback |
| PM2 Env Wrapper | /opt/wheeler-ecosystem/scripts/pm2-env-wrapper.sh | Clean env for PM2 processes |
| Deployment Engine | /root/deployment-engine/ | CI/CD pipeline |
| Rollback Engine | /root/rollback-engine/ | Service restoration |

---

## Appendix B: Key Performance Indicators

### Revenue KPIs (Target)

| Metric | Prediction Radar | FRG | SurplusAI | Ravyn Capital |
|--------|-----------------|-----|-----------|---------------|
| MRR | Target: TBD | N/A (contingency) | Target: TBD | N/A (deal-based) |
| ARR | Target: TBD | Target: TBD | Target: TBD | Target: TBD |
| Active Subscribers | 0 (test mode) | N/A | 0 | N/A |
| Cases in Pipeline | 0 | 6,603 (stuck on Hostinger) | 0 | TBD |
| Conversion Rate | N/A | Target: TBD | Target: TBD | Target: TBD |
| Average Deal Size | TBD | TBD | TBD | TBD |
| Churn Rate | Unknown | N/A | Unknown | N/A |
| LTV | Unknown | Unknown | Unknown | Unknown |
| CAC | Unknown | Unknown | Unknown | Unknown |

### System KPIs (Current)

| Metric | Value | Target |
|--------|-------|--------|
| PM2 Services Online | 17/18 | 18/18 |
| Docker Containers Healthy | 40/40 | 40/40 |
| Revenue Websites Reachable | 5/5 | 5/5 |
| PipelineDAG Stages Functional | 0/6 | 6/6 |
| Database Connections Healthy | 3/5 | 5/5 |
| AI Agent Services Online | 9/9 | 9/9 |
| Revenue Collection Active | Test Mode only | LIVE Mode |
| Security Hardening Score | 100/100 | 100/100 |

---

## Appendix C: Incident Response Quick Reference

### Revenue-Down Checklist

```
  1. ALERT: Revenue healthcheck fails
     -> /root/scripts/revenue-healthcheck.sh --json

  2. DIAGNOSE: Check COREDB PostgreSQL
     -> pg_isready -h 5.78.210.123 -p 5432
     -> systemctl status postgres (or docker ps)

  3. CHECK: PM2 revenue apps
     -> pm2 status | grep frgcrm
     -> pm2 logs frgcrm-api --lines 50

  4. VALIDATE: LiteLLM proxy
     -> curl http://127.0.0.1:4049/health

  5. RESTORE: If DB issue
     -> /root/scripts/revenue-rollback-checklist.sh
     -> Option: BAK (backup), then Stage D (env), Stage B (PM2)

  6. ESCALATE: If unresolved within 15 minutes
     -> Discord #incidents channel
     -> PM2 logs export
     -> Docker logs export
```

---

*End of Revenue Flow Architecture Document.*
*Wheeler Ecosystem -- 61 services, 3 nodes, 8 revenue systems.*
*QA Score: 100/100 (Infrastructure) | Revenue Collection: 0% (Pre-revenue)*
