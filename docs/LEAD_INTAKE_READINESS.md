# Wheeler Revenue Ecosystem -- Lead Intake Readiness Assessment
## 3-Server Infrastructure Cutover Preparation

> **Date:** 2026-05-23
> **Assessment Scope:** All lead intake touchpoints from public forms through attorney assignment and claimant onboarding
> **Source:** Live process inspection (PM2 + Docker + env), source code audit, error log analysis

---

## EXECUTIVE SUMMARY

The Wheeler lead intake pipeline is a multi-stage AI-driven DAG (PipelineDAG) that runs inside the FRGCRM Agent Service on the AIOPS node. The pipeline ingests scraped surplus-funds leads, scores them, matches them to attorneys, drafts outreach emails, and generates claim packets. **All six stages are currently failing because the OPENAI_API_KEY environment variable is not set.** The FRGCRM API (PM2 id 6) is also errored with an ASGI import failure, meaning the REST API that the agent service calls is down entirely. The voice-agent-svc and surplusai-scraper-agent-svc are stuck in restart loops (282+ restarts each).

**Overall Lead Intake Status: CRITICAL -- NOT FUNCTIONAL**

---

## 1. LEAD INTAKE FORMS AUDIT

### 1.1 Public-Facing Forms

| Form/Site | Domain | Location | Posts To | Status |
|-----------|--------|----------|----------|--------|
| FRGops main site | fundsrecoverygroup.com | Hostinger Edge | FRGCRM frontend → FRGCRM API (ERRORED) | UNKNOWN -- frontend on Hostinger, API errored |
| FRG CRM portal | frgops.fundsrecoverygroup.tech | Hostinger Edge | FRGCRM API (ERRORED on AIOPS) | UNKNOWN -- depends on errored API |
| Prediction Radar checkout | predictionradar.app | Hetzner Docker (port 8098 web, 8000 API) | Stripe webhooks → Prediction Radar API | ONLINE -- healthy |
| SurplusAI portal | surplusai.io | Hostinger Edge | SurplusAI scraper agent (WAITING) | DEGRADED -- scraper in restart loop |
| Docuseal signing forms | docuseal.wheeler.ai | Hetzner Docker (port 3010) | Docuseal API → docuseal-redis | ONLINE -- healthy |
| Chatwoot live chat | chatwoot.wheeler.ai | Hostinger Edge | Chatwoot → Hostinger PG/Redis | ONLINE (Hostinger, unverified) |

### 1.2 Lead Intake Architecture

```
PUBLIC INTERNET
    │
    ├─ fundsrecoverygroup.com ──────► Hostinger FRGops :3000
    │                                     │
    │                                     ▼
    │                               FRGCRM Frontend (Hostinger)
    │                                     │
    │                                     ▼  HTTP POST
    │                     FRGCRM API :8002  (Hostinger)  ← FRGCRM_API_URL
    │                              OR                       in PM2 env
    │                     FRGCRM API (PM2 id 6, AIOPS) ← ERRORED
    │
    ├─ surplusai.io ──────────────► SurplusAI Frontend (Hostinger)
    │                                     │
    │                                     ▼
    │                     SurplusAI Scraper Agent Svc (PM2, 282 restarts)
    │
    ├─ predictionradar.app ───────► Prediction Radar Web :8098 (AIOPS Docker)
    │                                     │
    │                                     ▼
    │                     Prediction Radar API :8000 (AIOPS Docker)
    │                                     │
    │                                     ▼  Stripe webhook
    │                     Stripe → Prediction Radar → FRGOPS DB
    │
    └─ docuseal.wheeler.ai ──────► Docuseal :3010 (AIOPS Docker)
```

### 1.3 Form Field Inventory (Inferred from LeadIngestion Agent)

Based on the `ScrapedLead` type in the lead-ingestion agent source code, lead intake forms and scrapers capture:
- `leadId` (system-assigned)
- `ownerName` (claimant name)
- `propertyAddress` (property address)
- `county` (county)
- `state` (state)
- `surplusAmount` (surplus funds value)
- `caseNumber` (court case number)
- `discoveredAt` (timestamp)

Validation rules enforced:
1. County, state, and case number must all be present
2. Surplus amount must be > 0
3. LLM validation for genuine opportunity classification

**Cutover Risk:** HIGH -- FRGCRM API must be fixed before any lead intake works. The FRGops frontend on Hostinger posts to a CRM API that is currently errored on the AIOPS node.

---

## 2. CRM SUBMIT ROUTES (FRGCRM API)

### 2.1 Service Status

| Service | PM2 ID | Status | Restarts | Port | Upstream |
|---------|--------|--------|----------|------|----------|
| frgcrm-agent-svc | 0 | ONLINE | 0 | 8003 (AGENT_SVC_PORT) | FRGCRM_API_URL=http://100.98.163.17:8002 |
| frgcrm-api | 6 | ERRORED | 15 | N/A | N/A (process not running) |
| frgcrm-mirror-test | 4 | ONLINE | 0 | 8099 (PORT) | FRGCRM_API_URL (same codebase) |

### 2.2 frgcrm-api Error Root Cause

```
ERROR: Error loading ASGI app. Could not import module "main".
```
The Python ASGI app cannot find its `main` module. This is likely:
- Missing Python dependencies
- Wrong working directory
- Improper virtual environment activation
- Missing or broken `main.py` file

### 2.3 FRGCRM API Route Map (called by Agent Service)

The FRGCRM Agent Service (`/opt/apps/frgcrm-agent-svc`) calls these routes on the FRGCRM API:

| Method | Route | Description | Called By |
|--------|-------|-------------|-----------|
| GET | `/api/recoverable-asset?limit=N` | List recoverable assets (returns `{opportunities: [...]}`) | CaseScorer, AttorneyMatcher, DocumentGenerator, ClaimantOutreach |
| POST | `/api/recoverable-asset` | Create new case from scraped lead | LeadIngestion |
| POST | `/api/recoverable-asset/:id/financial-score` | Update asset score + reason | CaseScorer |
| POST | `/api/recoverable-asset/:id/route` | Route asset to attorney | AttorneyMatcher |
| GET | `/api/attorney?status=active` | List active attorneys | AttorneyMatcher |
| POST | `/api/ai/insight` | Log agent insight/action | All agents |
| POST | `/api/ai/send-outreach` | Send claimant outreach email | ClaimantOutreach |
| POST | `/api/recoverable-asset/:id/claim-packet/generate-documents` | Generate claim packet | DocumentGenerator |
| GET | `/api/dashboard/pipeline` | Get pipeline dashboard stats | PipelineMonitor |

### 2.4 FRGOPS Integration Routes

| Method | Route | Description | Called By |
|--------|-------|-------------|-----------|
| GET | `/api/integration/events?event_types=lead.discovered.v1&status=PENDING&limit=50` | Pull pending lead events from integration outbox | LeadIngestion |

### 2.5 FRGCRM Agent Service Internal Routes

| Method | Route | Description |
|--------|-------|-------------|
| GET | `/health` | Health check (returns agent list, DAG status) |
| POST | `/agents/case-scorer/run` | Manual trigger: score assets |
| POST | `/agents/attorney-matcher/run` | Manual trigger: match attorneys |
| POST | `/agents/pipeline-monitor/run` | Manual trigger: monitor pipeline |
| POST | `/agents/run-all` | Run all agents sequentially |
| POST | `/pipeline/dag/run` | Run full DAG pipeline |
| GET | `/pipeline/dag/history?limit=N` | Get DAG run history |
| GET | `/pipeline/dag/latest` | Get latest DAG run result |

**Cutover Risk:** CRITICAL -- FRGCRM API is the backbone of all lead intake. It must be operational before any cutover. The agent service is online but all API calls fail because the target API is down.

---

## 3. CONTACT CAPTURE MECHANISMS

### 3.1 Chatwoot (Live Chat)

| Field | Value |
|-------|-------|
| Domain | chatwoot.wheeler.ai |
| Location | Hostinger Edge |
| Status | ONLINE (unverified from AIOPS) |
| Database | Hostinger PG (chatwoot_production) |
| Redis | Hostinger Redis (DB 2) |
| Email Channel | DISABLED (ENABLE_EMAIL_CHANNEL=false) |

**Note:** Chatwoot is configured without email ingestion to conserve resources. Live chat only.

### 3.2 Docuseal (Document Signing)

| Field | Value |
|-------|-------|
| Domain | docuseal.wheeler.ai |
| Location | Hetzner Docker (port 3010) |
| Status | ONLINE (43h uptime) |
| Redis | docuseal-redis (healthy) |
| Database | Connected via Postgres → frgops-standby :5433 |
| SSL | Forced (FORCE_SSL=true) |

### 3.3 Stripe Checkout (Prediction Radar)

| Field | Value |
|-------|-------|
| Gateway | Stripe |
| Mode | TEST (sk_test_*, pk_test_*) |
| Webhook Secret | [CONFIGURED] -- two entries (STRIPE_WEBHOOK_SECRET, STRIPE_WEBHOOK_SECRET_E16) |
| Price IDs (6) | Agency, Forensic, Prompts Pro, Signals Pro, Marketing, Enterprise |
| Domain | predictionradar.app |

**Note:** Stripe is in test mode. Must be switched to live keys before production use.

### 3.4 WhatsApp Contact Point

| Field | Value |
|-------|-------|
| WhatsApp Number | 6269404249 |
| Configured In | Prediction Radar .env (WHATSAPP_NUMBER) |
| Integration Status | UNKNOWN -- no WhatsApp Business API config observed |

**Cutover Risk:** MEDIUM -- Contact capture via Chatwoot and Docuseal is operational. WhatsApp integration unverified. Stripe needs live-mode switch.

---

## 4. WEBHOOK HANDLERS FOR LEAD INTAKE

### 4.1 Webhook Receiver (Hostinger)

| Field | Value |
|-------|-------|
| Container | webhook-receiver |
| Port | 9000 (Traefik-routed) |
| Location | Hostinger Edge |
| Status | UNKNOWN (Hostinger-side verification needed) |
| Routes | /health, /webhook/github, /webhook/stripe, etc. |
| Forward Target | n8n (http://n8n:5678/webhook/) |
| Rate Limit | 100 req/min per source IP |
| Retry | 3 attempts, exponential backoff |

### 4.2 Stripe Webhooks

| Field | Value |
|-------|-------|
| Endpoint | Prediction Radar API (internal) |
| Webhook Secret | [CONFIGURED] |
| Events | checkout.session.completed, customer.subscription.*, invoice.* |

### 4.3 Discord Webhooks (Alerting)

| Webhook | URL | Purpose |
|---------|-----|---------|
| DISCORD_ALERT_WEBHOOK_URL | [CONFIGURED] | Pipeline alerts (scoring, matching) |
| DISCORD_APPROVAL_WEBHOOK_URL | [CONFIGURED] | Human-approval notifications |
| DISCORD_BRIEFING_WEBHOOK_URL | [CONFIGURED] | Daily briefings |
| DISCORD_WEBHOOK_URL | [CONFIGURED] | General notifications |

### 4.4 FRGops Integration Events API

| Field | Value |
|-------|-------|
| Endpoint | FRGOPS_API_URL/api/integration/events |
| Event Type | lead.discovered.v1 |
| Polled By | FRGCRM Agent Svc (LeadIngestion agent) |
| Poll Interval | 300000ms (5 minutes) |
| Status | PENDING (polling leads waiting for processing) |

**Cutover Risk:** MEDIUM -- Webhook receiver on Hostinger needs verification. Discord webhooks functional. Stripe webhooks active but in test mode.

---

## 5. LEAD SCORING PIPELINE

### 5.1 PipelineDAG Architecture

The lead scoring pipeline runs as a Directed Acyclic Graph (DAG) inside the FRGCRM Agent Service. It executes on a 5-minute interval (`POLLING_INTERVAL_MS=300000`).

```
┌─────────────────────────────────────────────────────────────────────┐
│                     PIPELINE DAG (frgcrm-agent-svc)                  │
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐           │
│  │ Stage 0:     │───►│ Stage 1:     │───►│ Stage 2:     │           │
│  │ LeadIngestion│    │ CaseScorer   │    │ Attorney     │           │
│  │              │    │              │    │ Matcher      │           │
│  │ Pull scraped │    │ Score assets │    │ Route to     │           │
│  │ leads from   │    │ 0-100 using  │    │ best attorney│           │
│  │ FRGops DB    │    │ LLM analysis │    │ by LLM       │           │
│  └──────────────┘    └──────────────┘    └──────────────┘           │
│                                                    │                │
│                                                    ▼                │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐           │
│  │ Stage 5:     │◄───│ Stage 4:     │◄───│ Stage 3:     │           │
│  │ Pipeline     │    │ Document     │    │ Claimant     │           │
│  │ Monitor      │    │ Generator    │    │ Outreach     │           │
│  │              │    │              │    │              │           │
│  │ Pipeline     │    │ Generate     │    │ Send email   │           │
│  │ health       │    │ claim packets│    │ to matched   │           │
│  │ + alerts     │    │ via FRGCRM   │    │ claimants    │           │
│  └──────────────┘    └──────────────┘    └──────────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.2 Pipeline Stages Detail

**Stage 0: LeadIngestion**
- Source: FRGops integration outbox (`/api/integration/events?event_types=lead.discovered.v1`)
- Validates county, state, case number, surplus > 0
- LLM validates genuine recovery opportunity
- Creates FRGCRM case via POST `/api/recoverable-asset`
- Status: **FAILING** -- OPENAI_API_KEY required

**Stage 1: CaseScorer**
- Scores assets 0-100 using LLM analysis
- Factors: estimated value, claimant clarity, source reliability, age, state complexity
- Priority tiers: critical (>80), high (>60), medium (>40), low (<40)
- Updates score via POST `/api/recoverable-asset/:id/financial-score`
- Status: **FAILING** -- OPENAI_API_KEY required

**Stage 2: AttorneyMatcher**
- Matches unassigned assets to best attorney by LLM
- Factors: jurisdiction, workload balance, asset complexity, proximity
- Routes asset via POST `/api/recoverable-asset/:id/route`
- Status: **FAILING** -- OPENAI_API_KEY required

**Stage 3: ClaimantOutreach**
- Drafts personalized outreach emails via LLM
- Sends via POST `/api/ai/send-outreach`
- Portal link: https://crm.fundsrecoverygroup.com/claimant
- Status: **FAILING** -- OPENAI_API_KEY required

**Stage 4: DocumentGenerator**
- Generates claim packets for cases in `claim_packet_pending` or `attorney_review_required` status
- LLM validates readiness before generation
- Triggers via POST `/api/recoverable-asset/:id/claim-packet/generate-documents`
- Status: **FAILING** -- OPENAI_API_KEY required

**Stage 5: PipelineMonitor**
- Monitors pipeline health
- Generates alerts for stuck/abnormal cases
- Status: **FAILING** -- OPENAI_API_KEY required

### 5.3 AI Model Configuration

The agent service is configured to use DeepSeek V4 as the AI provider via a LiteLLM proxy pattern:

| Config | Value |
|--------|-------|
| Model ID | deepseek-chat (AGENT_MODEL env) |
| Base URL (OPENAI_BASE_URL) | https://api.deepseek.com/v1 |
| Anthropic Base URL | https://api.deepseek.com/anthropic |
| API Key fallback | DEEPSEEK_API_KEY \|\| OPENAI_API_KEY |
| SDK | @strands-agents/sdk + openai npm package v6 |

**Root cause of pipeline failure:** The model factory (`createModel()`) falls back from `DEEPSEEK_API_KEY` to `OPENAI_API_KEY`, and neither is set in the PM2 environment. The `OPENAI_BASE_URL` points to DeepSeek, but the OpenAI SDK still requires an API key. The error `OpenAI API key is required` occurs because both `DEEPSEEK_API_KEY` and `OPENAI_API_KEY` are undefined in the PM2 process environment.

**Fix:** Set `DEEPSEEK_API_KEY=[DEEPSEEK_API_KEY]` in the frgcrm-agent-svc PM2 environment (ecosystem.config.js or via `pm2 env`).

**Cutover Risk:** CRITICAL -- Entire lead scoring pipeline is non-functional. This must be fixed as a prerequisite to any cutover.

---

## 6. ATTORNEY ASSIGNMENT SYSTEM

### 6.1 Attorney Inventory

Four attorneys are configured in the Prediction Radar environment:

| Code | Attorney | Purpose |
|------|----------|---------|
| ATTORNEY_1_CODE | FRGatty-Bigham-2026 | Surplus funds recovery attorney |
| ATTORNEY_2_CODE | FRGatty-Morris-2026 | Surplus funds recovery attorney |
| ATTORNEY_3_CODE | FRGatty-Farah-2026 | Surplus funds recovery attorney |
| ATTORNEY_4_CODE | FRGatty-Walker-2026 | Surplus funds recovery attorney |

### 6.2 Partner Codes

| Code | Partner | Type |
|------|---------|------|
| PARTNER_aa000001 | FRGcounty-MiamiDade-2026 | County partner |
| PARTNER_bb000002 | FRGtenant-Sunrise-2026 | Tenant partner |

### 6.3 Assignment Logic (AttorneyMatcherAgent)

The AttorneyMatcherAgent uses an LLM to match assets to attorneys based on:
1. **Jurisdiction match** -- attorney must practice in the asset's county/state
2. **Workload balance** -- prefers attorneys with fewer active cases
3. **Asset complexity** -- matches asset value/type to attorney experience
4. **Proximity** -- local attorneys preferred for county court filings

The LLM prompt is provided a list of attorneys with:
- Attorney ID, name, licensed states/counties, active case count

The output is parsed to extract `attorney_id`, `confidence` (high/medium/low), and `reason`.

Matches with confidence "low" are skipped. Successful matches are routed via POST `/api/recoverable-asset/:id/route` with `{attorney_id: N}`.

### 6.4 Attorney Data Source

Attorney data is pulled from FRGCRM API: `GET /api/attorney?status=active`. This endpoint is currently inaccessible because the FRGCRM API is errored.

**Cutover Risk:** HIGH -- Attorney data source (FRGCRM API) is down. Even if AI key were fixed, the matcher cannot retrieve the attorney roster.

---

## 7. CLAIMANT ONBOARDING FLOW

### 7.1 End-to-End Flow

```
1. LEAD DISCOVERED
   └─ Scraper → FRGops integration outbox → LeadIngestion agent

2. CASE CREATED
   └─ FRGCRM case created via POST /api/recoverable-asset

3. CASE SCORED
   └─ CaseScorer → 0-100 score → financial-score update

4. ATTORNEY ASSIGNED
   └─ AttorneyMatcher → LLM match → route-to-attorney

5. OUTREACH SENT
   └─ ClaimantOutreach → LLM draft email → send-outreach
   └─ Email links to: https://crm.fundsrecoverygroup.com/claimant

6. DOCUMENTS GENERATED
   └─ DocumentGenerator → claim packet

7. CONTRACT SIGNED
   └─ Docuseal → e-signature

8. PAYMENT PROCESSED
   └─ Stripe → Prediction Radar

9. CLAIM FILED
   └─ Attorney files claim with court

10. RECOVERY DISBURSED
    └─ Funds recovered → fee split calculated → payment disbursed
```

### 7.2 Current State at Each Stage

| Stage | Status | Blocker |
|-------|--------|---------|
| 1. Lead Discovered | PARTIAL | Scraper agent restarting, no leads flowing to outbox |
| 2. Case Created | BROKEN | FRGCRM API errored |
| 3. Case Scored | BROKEN | OPENAI_API_KEY missing |
| 4. Attorney Assigned | BROKEN | FRGCRM API errored + OPENAI_API_KEY missing |
| 5. Outreach Sent | BROKEN | FRGCRM API errored + OPENAI_API_KEY missing |
| 6. Documents Generated | BROKEN | FRGCRM API errored + OPENAI_API_KEY missing |
| 7. Contract Signed | READY | Docuseal online, but no cases flowing to it |
| 8. Payment Processed | READY (test mode) | Stripe in test mode |
| 9. Claim Filed | BROKEN | No cases reaching attorney stage |
| 10. Recovery Disbursed | N/A | Pipeline not reaching this stage |

**Cutover Risk:** CRITICAL -- End-to-end claimant onboarding is completely broken at multiple stages. The pipeline must be fully restored before any cutover can succeed.

---

## 8. EMAIL AUTOMATION

### 8.1 SendGrid Configuration

| Field | Value | Location |
|-------|-------|----------|
| SMTP Host | smtp.sendgrid.net | Prediction Radar .env |
| SMTP Port | 587 | Prediction Radar .env |
| SMTP User | apikey | Prediction Radar .env |
| SMTP Password | [CONFIGURED] | Prediction Radar .env |
| From Email | invites@predictionradar.app | Prediction Radar .env |
| From Name | "Prediction Radar" | Prediction Radar .env |
| FRGOPS SendGrid Key | [CONFIGURED] | Prediction Radar .env |

### 8.2 Email Sending Pathways

| Pathway | Mechanism | Status |
|---------|-----------|--------|
| Claimant outreach emails | ClaimantOutreachAgent → POST /api/ai/send-outreach → FRGCRM → SendGrid | BROKEN (API + AI key) |
| Prediction Radar invites | Prediction Radar → SMTP (smtp.sendgrid.net) | READY |
| Discord notifications | Discord webhooks (4 channels) | READY |
| Chatwoot email | DISABLED (ENABLE_EMAIL_CHANNEL=false) | N/A |

**Cutover Risk:** MEDIUM -- SendGrid is configured but the outreach pathway through FRGCRM is broken. Prediction Radar transactional emails should work.

---

## 9. SMS AUTOMATION

### 9.1 WhatsApp Contact Point

| Field | Value |
|-------|-------|
| WhatsApp Number | 6269404249 |
| Configuration Location | Prediction Radar .env (WHATSAPP_NUMBER) |
| Integration | No WhatsApp Business API or Twilio config observed |
| Status | NUMBER EXISTS -- NO ACTIVE INTEGRATION FOUND |

### 9.2 Gaps

- No Twilio account SID or auth token found in any configuration
- No WhatsApp Business API webhook endpoint configured
- No SMS fallback pathway identified
- The ClaimantOutreach agent only sends email (channel: 'email'); no SMS/WhatsApp branch exists in the agent code

**Cutover Risk:** LOW -- SMS/WhatsApp automation is a future integration. Current pipeline is email-only for outreach. No cutover dependency.

---

## 10. VOICE AUTOMATION

### 10.1 voice-agent-svc Status

| Field | Value |
|-------|-------|
| PM2 ID | 2 |
| PM2 Status | WAITING (online at last check but in restart cycle) |
| Restart Count | 282+ |
| Process Location | /opt/apps/voice-agent-svc |
| Entry Point | dist/index.js (Node.js, TypeScript) |
| Configured Port | 8008 |
| AI Provider | DeepSeek proxy (OPENAI_BASE_URL=https://api.deepseek.com/v1) |
| AI Key Status | UNKNOWN -- same pattern as other agents (needs DEEPSEEK_API_KEY) |
| Polling Interval | 300000ms (5 min) |
| PM2 Max Restarts | 5 (exhausted, now in waiting state) |

### 10.2 Voice Agent Environment

```
NODE_ENV=production
PORT=8008
POLLING_INTERVAL_MS=300000
LOG_LEVEL=info
OPENAI_BASE_URL=https://api.deepseek.com/v1
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
```

### 10.3 Likely Failure Cause

The voice-agent-svc uses the same `@strands-agents/sdk` package as the frgcrm-agent-svc. It likely has the same `createModel()` pattern requiring `DEEPSEEK_API_KEY` or `OPENAI_API_KEY`. With neither set, the agent fails on startup, PM2 restarts it, exhausts `max_restarts=5`, and enters WAITING state.

### 10.4 Voice Infrastructure

- No Twilio, Vonage, or other voice provider API keys found
- No SIP/WebRTC configuration observed
- Port 8008 is not publicly routed (not in Traefik config)
- The service is likely an internal voice agent (AI voice assistant) rather than a call center dialer

**Cutover Risk:** HIGH -- Voice automation is offline. If voice outreach is part of the claimant communication strategy, this is a critical gap. Even if not customer-facing, the internal voice agent being down represents lost capability.

---

## 11. CROSS-SYSTEM DEPENDENCIES

### 11.1 Dependency Graph for Lead Intake

```
                                      ┌──────────────────┐
                                      │   FRGOPS FRONTEND │
                                      │   (Hostinger)     │
                                      └────────┬─────────┘
                                               │ POST /api/leads
                                               ▼
┌─────────────────┐    ┌─────────────────────────────────────┐
│ SURPLUSAI       │    │         FRGCRM API (ERRORED)         │
│ SCRAPER AGENT   │───►│  - GET  /api/recoverable-asset      │
│ (282 restarts)  │    │  - POST /api/recoverable-asset      │
└─────────────────┘    │  - POST /api/recoverable-asset/:id/ │
                       │    financial-score                   │
┌─────────────────┐    │  - POST /api/recoverable-asset/:id/ │
│ LEAD DISCOVERY  │    │    route                            │
│ (Scrapers on    │───►│  - GET  /api/attorney               │
│  Hostinger?)    │    │  - POST /api/ai/insight             │
└─────────────────┘    │  - POST /api/ai/send-outreach       │
                       │  - POST /api/recoverable-asset/:id/ │
                       │    claim-packet/generate-documents  │
                       └──────────────┬──────────────────────┘
                                      │ depends on
                                      ▼
                       ┌─────────────────────────────────────┐
                       │      frgops-standby (PG16 :5433)    │
                       │      Docker, healthy, 43h uptime    │
                       └─────────────────────────────────────┘
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         │                            │                            │
         ▼                            ▼                            ▼
┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│ FRGCRM AGENT SVC│    │ PREDICTION RADAR     │    │ DOCUSEAL            │
│ (ONLINE, port   │    │ (Docker, healthy)    │    │ (Docker, healthy)   │
│  8003)          │    │                      │    │                     │
│                 │    │ - Stripe checkout    │    │ - e-signatures      │
│ - PipelineDAG   │    │ - SendGrid email     │    │ - document intake   │
│ - 6 agents      │    │ - Discord webhooks   │    │                     │
│ - Needs AI key  │    │ - JWT auth           │    │                     │
└─────────────────┘    └─────────────────────┘    └─────────────────────┘
```

### 11.2 AI Provider Dependency

All 6 pipeline agents + voice agent depend on AI inference:
- **Provider:** DeepSeek V4 (via api.deepseek.com)
- **Proxy path:** OPENAI_BASE_URL=https://api.deepseek.com/v1 (OpenAI-compatible endpoint)
- **SDK:** @strands-agents/sdk using OpenAI client library
- **Key required:** DEEPSEEK_API_KEY (or OPENAI_API_KEY as fallback)
- **Current state:** KEY NOT SET in any PM2 process

**Cutover Risk:** CRITICAL -- This single missing environment variable (DEEPSEEK_API_KEY) blocks the entire lead intake pipeline (7 services: 6 agents + voice agent).

---

## 12. RISK MATRIX SUMMARY

| System | Current Status | Risk Level | Cutover Blocker? | Fix Priority |
|--------|---------------|------------|------------------|--------------|
| FRGCRM API | ERRORED (15 restarts) | CRITICAL | YES | P0 |
| Lead Scoring Pipeline | All 6 stages failing | CRITICAL | YES | P0 |
| AI Provider Key | DEEPSEEK_API_KEY not set | CRITICAL | YES | P0 |
| SurplusAI Scraper Agent | WAITING (282 restarts) | HIGH | YES | P1 |
| Voice Agent Service | WAITING (282 restarts) | HIGH | NO (internal) | P1 |
| Attorney Assignment | API down, AI key missing | HIGH | YES | P1 |
| Claimant Onboarding | Broken at multiple stages | HIGH | YES | P1 |
| Email (SendGrid) | Configured, pathway broken | MEDIUM | NO | P2 |
| Webhook Receiver | Hostinger, unverified | MEDIUM | NO | P2 |
| Stripe Checkout | Online, test mode | MEDIUM | NO | P2 |
| Docuseal | ONLINE, healthy | LOW | NO | - |
| Chatwoot | ONLINE (unverified) | LOW | NO | - |
| SMS/WhatsApp | Number exists, no integration | LOW | NO | P3 |

---

## 13. CUTOVER PREREQUISITES

### 13.1 Immediate (Blocking -- Must Fix Before Any Cutover)

1. **Fix FRGCRM API (PM2 id 6)**
   - Error: `Could not import module "main"` (ASGI app)
   - Check working directory, virtual env, dependencies
   - Verify main.py exists
   - Command: `pm2 logs frgcrm-api --lines 50`

2. **Set DEEPSEEK_API_KEY on all agent services**
   - frgcrm-agent-svc (ecosystem.config.js or `pm2 env`)
   - surplusai-scraper-agent-svc
   - voice-agent-svc
   - Add: `DEEPSEEK_API_KEY=[DEEPSEEK_API_KEY]` to each

3. **Fix surplusai-scraper-agent-svc restart loop**
   - Likely same cause as pipeline agents (missing AI key)
   - Check logs: `pm2 logs surplusai-scraper-agent-svc --lines 50`

4. **Fix voice-agent-svc restart loop**
   - Likely same cause as pipeline agents (missing AI key)
   - Check logs: `pm2 logs voice-agent-svc --lines 50`

### 13.2 Short-Term (Before Cutover -- High Priority)

5. **Verify FRGCRM API routes work after fix**
   - Test GET `/api/recoverable-asset?limit=5`
   - Test GET `/api/attorney?status=active`
   - Confirm attorney roster has data

6. **Verify pipeline end-to-end after key set**
   - Trigger: `curl -X POST http://localhost:8003/pipeline/dag/run`
   - Check: `curl http://localhost:8003/pipeline/dag/latest`
   - Verify all 6 stages complete without error

7. **Verify Hostinger services (remote access needed)**
   - FRGops frontend connectivity to FRGCRM API
   - Chatwoot health
   - LiteLLM proxy health
   - Webhook receiver health
   - n8n workflow health

8. **Verify Stripe live mode readiness**
   - Current keys are `sk_test_*` / `pk_test_*`
   - Confirm live keys exist in Hostinger .env
   - Verify Stripe webhook signing secret

### 13.3 Pre-Cutover Validation Checklist

- [ ] FRGCRM API online, responding to health check
- [ ] Attorney roster accessible via GET /api/attorney
- [ ] DEEPSEEK_API_KEY set, PipelineDAG completes without error
- [ ] New scraped leads flow from integration outbox → case creation
- [ ] Case scoring produces valid scores
- [ ] Attorney matching routes correctly
- [ ] Claimant outreach emails send via SendGrid
- [ ] Docuseal signing flow tested
- [ ] Prediction Radar Stripe checkout works in live mode
- [ ] All webhook endpoints verified
- [ ] Hostinger → AIOPS Tailscale connectivity verified
- [ ] DNS cutover plan documented with TTL reduction

---

## 14. MONITORING & ALERTING

### 14.1 Current Monitoring Coverage

| System | Monitor | Alert |
|--------|---------|-------|
| FRGCRM Agent Svc | PM2 status (ONLINE) | Uptime Kuma? |
| FRGCRM API | PM2 status (ERRORED) | None -- NEEDS ALERT |
| PipelineDAG | frgcrm-mirror-test error logs | Discord (broken due to AI key) |
| Docker containers | Docker health checks | Prometheus + Grafana |
| Public endpoints | Uptime Kuma :3001 | Status page at uptime.wheeler.ai |

### 14.2 Recommended Additional Monitoring

1. **Pipeline success rate alert** -- Alert if PipelineDAG fails more than 3 consecutive runs
2. **FRGCRM API health check** -- Add to Uptime Kuma
3. **AI key validity check** -- Validate API key on agent startup, alert if invalid
4. **Lead intake volume alert** -- Zero leads ingested in 1 hour = alert
5. **Outreach delivery rate** -- Monitor SendGrid delivery events

---

## 15. APPENDIX: Configuration File Locations

| File | Location | Purpose |
|------|----------|---------|
| PM2 dump (all services) | /root/.pm2/dump.pm2 | PM2 process definitions with env vars |
| PM2 ecosystem config | /opt/apps/ecosystem.config.js | FRGCRM + SurplusAI + Voice + Insforge agents |
| Prediction Radar .env | /opt/apps/prediction-radar-app/.env | All Prediction Radar env vars (Stripe, SendGrid, Discord, attorneys) |
| Prediction Radar compose | /opt/apps/prediction-radar-app/docker-compose.yml | Docker Compose with all services |
| Infrastructure compose | /root/infrastructure/hetzner/compose/prediction-radar.yml | Reference compose (newer architecture) |
| Infrastructure compose | /root/infrastructure/hetzner/compose/ravynai.yml | RavynAI reference compose |
| FRGops essential compose | /root/infrastructure/hostinger/compose/frgops-essential.yml | Hostinger frontend services |
| Automation edge compose | /root/infrastructure/hostinger/compose/automation-edge.yml | n8n + webhook receiver |
| AI edge compose | /root/infrastructure/hostinger/compose/ai-edge.yml | LiteLLM + MinIO |
| Architecture doc | /root/infrastructure/ARCHITECTURE.md | Full architecture reference |
| API readiness matrix | /root/docs/API_READINESS_MATRIX.md | API-by-API health assessment |
| Domain routing map | /root/docs/DOMAIN_ROUTING_MAP.md | Domain → upstream routing table |
| Revenue app inventory | /root/docs/REVENUE_APP_INVENTORY.md | Full app inventory |
| FRGCRM Agent source | /opt/apps/frgcrm-agent-svc/src/ | PipelineDAG + all 6 agents |
| Voice Agent source | /opt/apps/voice-agent-svc/ | Voice agent implementation |
