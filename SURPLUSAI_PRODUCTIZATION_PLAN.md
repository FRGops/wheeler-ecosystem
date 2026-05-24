# SurplusAI Productization Plan

## From County Data Scraper to Enterprise SaaS Platform

**Classification**: Executive Strategy Document
**Date**: 2026-05-24
**Domain**: surplusai.io
**Host**: wheeler-aiops-01 (5.78.140.118) -- 30 GB RAM, 16 vCPUs, 338 GB SSD
**PM2 Ecosystem**: Wheeler Autonomous Operations (20+ services)

---

## 1. Current State Assessment

### 1.1 Running Services

| Service | PM2 ID | Status | Memory | Tech Stack |
|---|---|---|---|---|
| surplusai-scraper-agent-svc | 7 | ONLINE | 108 MB | Node.js / Express / @strands-agents/sdk |
| surplusai-portal-api | 21 | ONLINE | 103 MB | Python FastAPI / SQLAlchemy / Uvicorn |

The scraper runs on port 8007, polls every 5 minutes (configurable via `POLLING_INTERVAL_MS`), and uses the `agent-platform` SDK to coordinate data collection. The portal API serves a FastAPI application on port 8103 with multi-tenant models (Organization, OrganizationMember), state-level expansion engine (StateRule, CountyCourt, AttorneyMatch), and routes covering auth, cases, documents, forms, notifications, stats, admin, intelligence, AI, WebSocket, push, organizations, and expansion.

### 1.2 Available Infrastructure

The SurplusAI platform already sits on a battle-tested production infrastructure:

- **LiteLLM Proxy**: 127.0.0.1:4049 -- running DeepSeek V4 Flash (`deepseek-chat` model), 377 MB RSS, PM2 id 17
- **DeepSeek API Key**: Available in environment, routed through LiteLLM
- **FRGCRM API**: 127.0.0.1:8082 -- PM2 id 22, 235 MB, FastAPI + PostgreSQL
- **FRGCRM Agent**: PM2 id 19, 94 MB -- automated CRM operations
- **Postgres (FRGCRM)**: 127.0.0.1:5433 -- `frgops-standby` Docker container, `frgcrm` database
- **Postgres (RavynAI)**: 127.0.0.1:5434 -- `aiops-ravynai-postgres` container
- **Neo4j Graph**: 127.0.0.1:7474 (HTTP) / 7687 (Bolt) -- `ecosystem-graph` container
- **Docuseal**: 127.0.0.1:3010 -- document e-signature platform
- **Temporal Server**: 127.0.0.1:7233 -- durable workflow orchestration
- **InsForge**: localhost:7130 -- document intelligence storage/auth
- **Superset**: 127.0.0.1:8088 -- BI dashboard layer
- **Prometheus + Loki + Alertmanager**: 127.0.0.1:9090 / 3100 / 9093 -- monitoring stack
- **Netdata**: 127.0.0.1:19999 -- real-time system metrics
- **Cloudflare**: DNS, DDoS protection, edge caching
- **PM2 Guardian**: PM2 id 13 -- ecosystem health monitoring

### 1.3 The Gap

The scraper is functional but collects raw data without structured parsing, scoring, or CRM integration. The portal has multi-tenant infrastructure but no billing, no lead routing, and no automated document pipeline. The product is a set of tools -- not a platform.

---

## 2. Platform Architecture

### 2.1 Microservice Topology

All services bind to 127.0.0.1 and route through Traefik or Cloudflare Tunnel. No service exposes a public port directly.

```
surplusai.io
  |
Cloudflare (DNS + WAF + TLS)
  |
Traefik (L7 routing, rate limiting, basic auth)
  |
  +-- scraper-service        :8007  (Node.js / @strands-agents/sdk)
  |     County data collection, adapter orchestration
  |
  +-- parser-service         :8104  (Python / FastAPI)
  |     PDF ingestion, OCR, AI field extraction
  |
  +-- scoring-service        :8105  (Python / FastAPI)
  |     Lead scoring, ML inference, confidence thresholds
  |
  +-- api-service            :8103  (Python / FastAPI -- existing portal)
  |     Customer-facing REST API, multi-tenant auth
  |
  +-- portal-frontend        :3002  (React / Next.js)
  |     Customer dashboard, attorney portal
  |
  +-- admin-console          :8086  (React / Next.js)
  |     Internal ops: county management, queue review, analytics
```

### 2.2 Service Naming Convention

All SurplusAI microservices follow the Wheeler PM2 naming pattern:

```
surplusai-{service}-svc       # PM2 process name
/opt/apps/surplusai-{service} # filesystem root
127.0.0.1:{port}              # bind address
```

### 2.3 Data Architecture

```
frgcrm database (127.0.0.1:5433)
  |
  +-- surplus_{tenant}_cases         # Scraped and parsed case data
  +-- surplus_{tenant}_leads         # Scored and ranked leads
  +-- surplus_adapter_configs        # County adapter configurations
  +-- surplus_attorney_assignments   # Attorney matching records
  +-- surplus_document_templates     # Document generation templates
  +-- surplus_billing_plans          # SaaS subscription plans
  +-- surplus_billing_subscriptions  # Tenant subscriptions
  +-- surplus_scoring_models         # ML model metadata (JSON-serialized)
  +-- surplus_audit_log              # All data access audit trail

Neo4j ecosystem-graph (127.0.0.1:7687)
  |
  +-- :County nodes                    # County court metadata
  +-- :Case nodes                      # Case relationships
  +-- :Attorney nodes                  # Attorney specialization graph
  +-- :Claimant nodes                  # Claimant entity resolution

Redis (COREDB or local container)
  |
  +-- surplus:queue:{county}           # Scrape job queues
  +-- surplus:cache:{key}              # Response cache (TTL 5 min)
  +-- surplus:rate:{county}            # Rate limit counters
  +-- surplus:sse:{tenant}             # Server-sent event channels
```

---

## 3. County Adapter Framework

### 3.1 Architecture

Each county gets a standardized adapter implementing a common interface. Adapters live in the scraper service at `/opt/apps/surplusai-scraper-agent-svc/src/adapters/`.

```
src/adapters/
  +-- interface.ts              # ICountyAdapter interface
  +-- registry.ts               # Adapter registry, loaded from DB
  +-- base-adapter.ts           # Shared: rate limiting, retry, logging
  +-- la-ca.adapter.ts          # Los Angeles County, CA
  +-- cook-il.adapter.ts        # Cook County, IL
  +-- harris-tx.adapter.ts      # Harris County, TX
  +-- maricopa-az.adapter.ts    # Maricopa County, AZ
  +-- miami-dade-fl.adapter.ts  # Miami-Dade County, FL
  +-- [county].adapter.ts       # Template for new counties
```

### 3.2 Adapter Interface

```typescript
interface ICountyAdapter {
  countyCode: string;           // e.g., "la-ca"
  countyName: string;           // "Los Angeles"
  stateCode: string;            // "CA"

  // Required: return new/updated surplus fund cases
  fetchCases(): Promise<RawCase[]>;

  // Optional: handle county-specific auth
  authenticate?(): Promise<AuthToken>;

  // Optional: parse county-specific document format
  parseDocument?(buffer: Buffer, mimeType: string): Promise<ParsedDocument>;

  // Rate limiting config
  rateLimit: {
    requestsPerSecond: number;
    burstSize: number;
    backoffMinutes: number;
  };
}
```

### 3.3 Adapter Configuration

Adapter configs are stored in the `surplus_adapter_configs` table in PostgreSQL, with fields:

- `county_code` -- unique adapter identifier
- `base_url` -- county data source endpoint
- `auth_type` -- none, API-key, OAuth2, session-cookie
- `auth_config` -- encrypted JSON credentials
- `enabled` -- boolean toggle per adapter
- `poll_interval_minutes` -- scrape frequency override
- `last_run_at` -- timestamp of last successful scrape
- `last_error` -- last error message (if any)
- `cases_collected_total` -- running count

### 3.4 Priority County Plan

| County | Court | Data Source Type | Complexity | Est. Adapter Dev Time |
|---|---|---|---|---|
| Los Angeles, CA | LA Superior Court | Web portal + PDF | High | 2 days |
| Cook, IL | Cook County Circuit Court | Web portal + PDF | High | 2 days |
| Harris, TX | Harris County District Court | Web portal + PDF | Medium | 1.5 days |
| Maricopa, AZ | Maricopa County Superior Court | API + PDF | Medium | 1 day |
| Miami-Dade, FL | Miami-Dade Circuit Court | Web portal + PDF | High | 2 days |

### 3.5 Scraper Queue Architecture

Uses the existing polling loop (currently 5-minute interval) with Temporal Server (127.0.0.1:7233) for durable workflow execution:

```
Temporal Workflow: SurplusScrapeWorkflow
  |
  +-- Activity 1: FetchAdapterConfig (read county config from DB)
  +-- Activity 2: ExecuteAdapter (run ICountyAdapter.fetchCases())
  +-- Activity 3: ParseResults (run parser-service for each document)
  +-- Activity 4: ScoreCases (run scoring-service for each case)
  +-- Activity 5: NotifyHighValue (webhook/SSE to CRM, admin)
  +-- Activity 6: RecordMetrics (update adapter config, prometheus)
```

---

## 4. AI Docket Parsing Engine

### 4.1 Pipeline

Every scraped document passes through a five-stage pipeline:

```
Stage 1: Download
  |
  v
Stage 2: Classify (PDF vs HTML vs scanned image)
  |
  +-- PDF text -> Stage 3 (direct)
  +-- Scanned image -> OCR (Tesseract/PaddleOCR) -> Stage 3
  +-- HTML -> cheerio/html2text -> Stage 3
  |
  v
Stage 3: Extract (LLM structured extraction via DeepSeek V4)
  |
  v
Stage 4: Validate (cross-field consistency checks)
  |
  v
Stage 5: Persist (write to Postgres, index in Neo4j)
```

### 4.2 LLM Extraction Schema

Each document is sent to DeepSeek V4 (via LiteLLM at `http://127.0.0.1:4049/v1`, model `deepseek-chat`) with a structured extraction prompt. The response is JSON-validated against this schema:

```json
{
  "case_number": "string (required)",
  "property_address": "string",
  "surplus_amount": "number (required)",
  "sale_date": "date (ISO 8601)",
  "claimant_names": ["string"],
  "claimant_addresses": ["string"],
  "attorney_name": "string",
  "attorney_bar_number": "string",
  "attorney_firm": "string",
  "court_name": "string",
  "county": "string",
  "state": "string",
  "trustee_name": "string",
  "sale_type": "enum(trustee, foreclosure, tax)",
  "document_date": "date (ISO 8601)",
  "original_judgment": "number"
}
```

### 4.3 Confidence Scoring

Each extracted field receives a confidence score 0.0-1.0:

- **1.0**: Direct extraction from machine-readable text with regex validation
- **0.8-0.9**: LLM extraction from clean text with enum constraint satisfaction
- **0.5-0.7**: LLM extraction from OCR text or ambiguous formatting
- **0.0-0.4**: Hallucination risk -- field inferred from context, not found in source

Case-level confidence = geometric mean of all required field confidences.

Thresholds:
- `< 0.6`: Sent to human review queue (portal admin console)
- `0.6 - 0.85`: Auto-accepted, flagged for spot-check
- `> 0.85`: Auto-accepted, no review needed

### 4.4 Human Review Queue

The admin console (port 8086) provides a review interface with:

- Case detail view showing extracted fields vs. raw document side-by-side
- Field-level correction with undo history
- Bulk approval/rejection
- Reviewer assignment and workload tracking
- Anomaly detection (same-case duplicates, outlier surplus amounts)
- Per-reviewer accuracy tracking (audit of accepted vs. later-corrected)

### 4.5 Training Data Collection

Every reviewed extraction (human-corrected) is persisted as a training example:

```
surplus_training_examples
  - id
  - raw_document_hash       # deduplication key
  - raw_document_text       # truncated to 16K chars
  - llm_extraction          # JSON of what the LLM returned
  - human_corrected         # JSON of corrected values
  - reviewer_id
  - reviewed_at
  - confidence_scores       # JSON of per-field confidences
  - used_in_fine_tune       # boolean flag
```

At 5,000+ training examples, fine-tune a dedicated DeepSeek model via the API. Target: 95% auto-accept rate at 0.85 confidence threshold.

---

## 5. Lead Scoring System

### 5.1 Composite Score Formula

```
LeadScore = w1 x SurplusScore + w2 x FindabilityScore + w3 x CompetitionScore + w4 x UrgencyScore

Where:
  SurplusScore = min(surplus_amount / 50000, 1.0) x 100
    # $50K+ surplus = max score; logarithmic beyond

  FindabilityScore = f(claimant_has_phone, claimant_has_address, social_presence, bankruptcy_status)
    # Weighted heuristic: phone=40, address=30, social=20, bankruptcy_flag=-50

  CompetitionScore = 100 - (active_attorneys_on_case x 20)
    # Fewer competing attorneys = higher score; cap at 0

  UrgencyScore = max(0, 100 - (days_since_sale x 2))
    # Decays 2 points per day; reaches 0 at 50 days

  w1 = 0.35  (surplus amount is primary)
  w2 = 0.30  (findability determines conversion feasibility)
  w3 = 0.20  (competition affects closing probability)
  w4 = 0.15  (urgency prevents missed deadlines)
```

### 5.2 ML Scoring Model

Phase 2 enhancement: train a gradient-boosted model (XGBoost or LightGBM) on historical FRGCRM outcomes:

**Features** (40+ engineered):
- Surplus amount (log, percentile within county)
- Claimant response rate by county
- Attorney win rate by county + case type
- Days elapsed since sale date
- Day of week of sale (some counties have day-dependent judge assignment)
- Property type (residential vs commercial)
- Claimant distance from attorney
- Seasonality (Q4 has higher abandonment rates)

**Target variable**: `converted_to_revenue` (boolean, from FRGCRM deal stage)

**Training pipeline**:
1. Export closed cases from FRGCRM (port 8082) with outcomes
2. Join with surplus_scraped_cases on case_number
3. Feature engineering via `/opt/apps/surplusai-scoring-service/features.py`
4. Train/validate split (80/20, stratified by county)
5. Hyperparameter optimization via Optuna
6. Model weights serialized to `surplus_scoring_models` table as JSON (tree structure in safe format)
7. Online inference via scoring-service API

### 5.3 Territory-Based Prioritization

Each tenant attorney defines a territory matrix (state + county + case type combos). Leads are scored and ranked within each attorney's territory first, then surfaced globally for overflow.

```
surplus_attorney_territories
  - attorney_id
  - state_code
  - county_code (nullable = entire state)
  - case_type (nullable = all types)
  - priority (1 = primary, 2 = secondary, 3 = overflow)
  - max_active_leads (cap per attorney)
  - created_at
```

---

## 6. CRM Integration Layer

### 6.1 FRGCRM Integration

Bidirectional sync between SurplusAI and FRGCRM at `127.0.0.1:8082`:

**SurplusAI to FRGCRM** (outbound):
- New high-scoring lead (score > 75) triggers POST `/api/leads` on FRGCRM
- Lead status changes (contacted -> represented -> won/lost) sync to FRGCRM deal stages
- Document generation events create FRGCRM activity records
- Scoring updates push to FRGCRM custom fields

**FRGCRM to SurplusAI** (inbound):
- Attorney assignments create surplus_attorney_assignments records
- Case outcome data (won/lost, recovery amount) feeds scoring model retraining
- Claimant contact information updates enrich SurplusAI profiles
- Calendar events (court dates, deadlines) sync to surplus calendar

### 6.2 n8n Workflow Integration

For complex multi-step automations, use n8n workflows:

| Workflow | Trigger | Actions |
|---|---|---|
| High-Value Lead Alert | Webhook from scoring-service (score > 90) | Create FRGCRM lead -> notify attorney SMS -> create calendar reminder -> log to audit |
| Weekly Pipeline Digest | Cron (Monday 8 AM) | Aggregate leads by stage -> generate Superset report -> email to stakeholders |
| Document Deadline Reminder | Cron (daily 6 AM) | Query upcoming deadlines (T-7, T-3, T-1 days) -> push notification to attorney dashboard -> SMS alert |
| New County Onboarding | Admin console trigger | Test adapter -> parse 10 sample docs -> validate vs manual review -> enable if > 85% accuracy |

### 6.3 Webhook System

The existing `routes/push.py` and SSE (server-sent events) infrastructure supports real-time notifications:

```
POST /api/v1/webhooks/register  -> Register webhook URL + event types
POST /api/v1/webhooks/test      -> Fire test event

Event types:
  - lead.created
  - lead.scored (score threshold configurable)
  - lead.assigned
  - document.parsed
  - document.ready_for_review
  - deadline.approaching
  - sync.completed
```

---

## 7. Attorney Assignment Engine

### 7.1 Matching Algorithm

The existing attorney matcher engine (`/opt/apps/surplusai-portal/engines/attorney_matcher.py`) already implements a weighted scoring system:

| Dimension | Weight | Data Source |
|---|---|---|
| Same state as case | 30 pts | Attorney license table |
| Same county as case | 15 pts | Territory matrix |
| Specialty match | 10 pts | Practice area mapping |
| Historical success rate | 20 pts | FRGCRM outcomes |
| Years of experience | 10 pts | Attorney profile |
| Availability (not overloaded) | 5 pts | Active leads count |
| Prior relationship with claimant | 10 pts | Case history graph |

### 7.2 Assignment Workflow

```
Lead scored > threshold (e.g., 75)
  |
  v
Query attorney_territories for matching attorneys
  |
  v
Score each attorney using attorney_matcher.py
  |
  v
Select top candidate (or top 3 for manual selection)
  |
  v
Create attorney_assignment record (status: "pending")
  |
  v
Notify attorney (push notification + email + optional SMS via voice-outreach-service)
  |
  v
Attorney response:
  +-- Accept -> status: "active", create FRGCRM deal
  +-- Decline -> status: "declined", move to next candidate
  +-- No response in 24h -> status: "expired", escalate to admin
```

### 7.3 Attorney Dashboard

A dedicated section in the portal frontend (port 3002) for attorneys:

- **My Leads**: Assigned leads with score, status, days remaining
- **My Territory**: Configure state/county/case-type preferences
- **My Performance**: Acceptance rate, time-to-contact, win rate, average recovery
- **Document Queue**: Pending signature requests via Docuseal (127.0.0.1:3010)
- **Calendar**: Court deadlines, filing reminders, status check-ins

---

## 8. Document Automation

### 8.1 Template System

Document templates per county are stored in PostgreSQL (`surplus_document_templates`) and rendered via Jinja2:

```
surplus_document_templates
  - id
  - county_code
  - document_type (claim_form, retention_agreement, disclosure, etc.)
  - template_body (Jinja2 template)
  - fields_required (JSON array of required case fields)
  - fields_optional (JSON array)
  - created_at
  - version
```

### 8.2 Docuseal Integration

Docuseal runs at `127.0.0.1:3010`. Integration flow:

1. Portal generates filled document (PDF via WeasyPrint or Puppeteer)
2. POST to Docuseal API `/templates` to create submission
3. Docuseal sends e-signature request to claimant email
4. Webhook callback on completion updates case status
5. Signed document stored in InsForge (`http://localhost:7130/api/storage`)
6. Document status in portal updates: drafted -> sent -> signed -> filed

### 8.3 Filing Calendar

Automated deadline tracking based on county rules (StateRule model):

```
surplus_calendar_events
  - case_id
  - event_type (filing_deadline, hearing_date, response_due, status_check)
  - due_date
  - days_remaining (computed daily)
  - completed_at (nullable)
  - reminder_sent_at (nullable)
  - assigned_attorney_id
```

Notifications escalate at T-14, T-7, T-3, T-1 days via push, email, and optionally SMS through `voice-outreach-service` (PM2 id 11).

---

## 9. Revenue Dashboards

### 9.1 Superset Integration

Apache Superset runs at `127.0.0.1:8088`, connected to the `frgcrm` PostgreSQL database. Pre-built dashboards:

**Pipeline Overview**
- Leads by stage funnel (scraped -> parsed -> scored -> assigned -> contacted -> represented -> won)
- Conversion rate by stage
- Average time in stage
- Total pipeline value (sum of surplus x win-probability)

**Revenue Forecast**
- Expected value by month: `sum(surplus_amount x win_probability)`
- Confidence intervals via Monte Carlo simulation (1000 runs)
- Actual vs. forecast tracking with variance alerts

**Attorney Performance**
- Leaderboard: recovery amount, cases closed, average days-to-close
- Geographic heatmap: case volume by county
- Trend lines: monthly performance vs. rolling 3-month average

**County Performance**
- Case volume per county (daily/weekly/monthly)
- Average surplus amount per county
- Parsing accuracy rate per county
- Adapter health: success rate, error rate, last success timestamp

### 9.2 Real-Time KPI Service

A lightweight WebSocket service (can extend existing `routes/ws.py`) pushes real-time metrics:

```
WebSocket: wss://surplusai.io/api/v1/ws/metrics

Events:
  - case.scraped   {county, count, avg_amount}
  - case.parsed    {county, accuracy, avg_confidence}
  - lead.created   {score, county, amount}
  - lead.assigned  {attorney, count}
  - deal.won       {attorney, amount, county}
```

---

## 10. Multi-Product Packaging

### 10.1 Tier Definitions

**SurplusAI Basic (Freemium)**
- County scraping for 1 county
- AI parsing with 48-hour turnaround
- Email notifications for new leads
- No CRM integration
- Limit: 50 leads/month
- Price: $0 (acquisition funnel)

**SurplusAI Pro**
- County scraping for up to 5 counties
- AI parsing with real-time processing
- Lead scoring with confidence metrics
- FRGCRM bidirectional sync
- Attorney assignment engine
- Webhook API access (1000 calls/month)
- Document automation (50 docs/month)
- Price: $997/month

**SurplusAI Enterprise**
- Unlimited counties
- White-label portal (custom domain under tenant's brand)
- Custom adapter development (new counties)
- Dedicated parser fine-tuning on tenant data
- Unlimited API access
- SLA: 99.5% uptime, 4-hour support response
- Priority adapter updates (legal deadline changes)
- Price: $2,997/month

**SurplusAI API**
- Raw data access for third-party platforms
- Usage-based pricing: $0.10 per case record
- Webhook delivery with retry (3 attempts, exponential backoff)
- Rate limit: 100 requests/min (configurable)
- Price: Pay-as-you-go

**SurplusAI White-Label**
- For law firms and real estate investment firms
- Complete rebranding (logo, domain, colors)
- Multi-user role management (admin, attorney, paralegal, viewer)
- Custom document templates with firm letterhead
- Dedicated database schema (data isolation)
- Price: $4,997/month

### 10.2 Billing Architecture

Billing enforcement uses a lightweight entitlement check baked into the API gateway layer:

```
surplus_billing_plans
  - id
  - plan_code (basic, pro, enterprise, white_label)
  - name
  - price_monthly_cents
  - features (JSON: feature -> boolean or limit value)
  - active

surplus_billing_subscriptions
  - id
  - organization_id (FK to Organization)
  - plan_id (FK to billing_plans)
  - status (active, trialing, past_due, canceled, expired)
  - current_period_start
  - current_period_end
  - stripe_subscription_id (when Stripe integration is added)
  - trial_end (nullable)

API-level enforcement via middleware:
  1. Auth middleware extracts organization_id from JWT
  2. Entitlement middleware queries subscription for plan features
  3. If feature limit reached, return 402 Payment Required
  4. Admin override via organization flag
```

Phase 1 billing: manual invoicing with Stripe integration in Phase 2.

---

## 11. Implementation Roadmap

### Phase 1: Stabilization and Fix (Days 1-2)

**Objective**: Break the crash loop, establish baseline data flow.

- [ ] **Diagnose scraper crash loop**: Inspect `/opt/apps/surplusai-scraper-agent-svc/logs/error.log`. The scraper uses `@strands-agents/sdk` which may be failing to authenticate. Verify the agent-platform dependency resolves correctly (it's a `file:../agent-platform` local reference). Test the config: port conflicts (8007), polling interval, log level.
- [ ] **Validate LiteLLM connectivity**: Test `curl http://127.0.0.1:4049/v1/models` to confirm DeepSeek V4 is reachable. Verify `DEEPSEEK_API_KEY` is set in the PM2 environment.
- [ ] **Verify data pipeline**: The portal connects to `postgresql://frgops:frgops_secure_2026@127.0.0.1:5433/frgcrm`. Confirm the portal tables create correctly (the `lifespan` handler runs `Base.metadata.create_all` on startup).
- [ ] **Fix agent-platform dependency**: The scraper ecosystem config at `/opt/apps/surplusai-scraper-agent-svc/ecosystem.config.js` may need env vars injected. Use the `env -i delete+start` pattern documented in `/root/.claude/projects/-root/memory/pm2-env-i-pattern.md`.
- [ ] **Health check endpoint**: Add `/health` endpoint to scraper (express route) for PM2 `wait_ready` pattern.

### Phase 2: County Adapter Framework + Top 5 Counties (Week 1)

**Objective**: Structured, repeatable data collection from priority counties.

- [ ] **Define adapter interface** in `src/adapters/interface.ts` with TypeScript generics
- [ ] **Build base adapter class** with retry logic (exponential backoff, jitter), rate limiting (token bucket), structured logging (JSON to stdout for Promtail)
- [ ] **Implement LA County adapter** -- highest volume (~40% of US surplus fund cases)
- [ ] **Implement Cook County adapter** -- second largest foreclosure market
- [ ] **Implement Harris, Maricopa, Miami-Dade adapters**
- [ ] **Build adapter registry** with CRUD API (`/api/v1/adapters`) in the portal
- [ ] **Create adapter config DB table** (`surplus_adapter_configs`) and migration
- [ ] **Wire Temporal workflows** for durable, retryable scrape execution
- [ ] **Prometheus metrics**: `surplus_adapter_runs_total`, `surplus_cases_collected_total`, `surplus_adapter_errors_total`, `surplus_scrape_duration_seconds`

### Phase 3: AI Docket Parsing + Lead Scoring (Week 2)

**Objective**: Turn raw court documents into structured, scored leads.

- [ ] **Create parser service** at `/opt/apps/surplusai-parser-service/` on port 8104
- [ ] **Build PDF ingestion pipeline**: download -> classify -> extract -> validate -> persist
- [ ] **Implement DeepSeek extraction prompts** with few-shot examples per county (5 examples each)
- [ ] **Build confidence scoring module** with per-field heuristics
- [ ] **Create human review queue** endpoints in portal admin routes
- [ ] **Build review UI** in admin console: raw doc side-by-side with extracted fields, correction tools
- [ ] **Create scoring service** at `/opt/apps/surplusai-scoring-service/` on port 8105
- [ ] **Implement composite score formula** with configurable weights (stored in `surplus_scoring_models`)
- [ ] **Build training data collection pipeline** (`surplus_training_examples` table)
- [ ] **Implement territory-based prioritization** UI for attorney territory configuration

### Phase 4: CRM Integration + Attorney Assignment (Week 3)

**Objective**: Close the loop from data to action.

- [ ] **Build FRGCRM sync service** at `/opt/apps/surplusai-crm-sync/`
- [ ] **Implement outbound lead creation** -- POST leads to FRGCRM API at 127.0.0.1:8082
- [ ] **Implement inbound outcome sync** -- poll FRGCRM for deal stage changes
- [ ] **Build webhook system** (extend existing `routes/push.py`) with retry and delivery logging
- [ ] **Create n8n workflow templates** for high-value alerts, weekly digests, deadline reminders
- [ ] **Enhance attorney matcher** with territory matrix, capacity scoring, and historical performance weighting
- [ ] **Build attorney dashboard** in portal frontend (port 3002): my leads, my territory, my performance
- [ ] **Implement assignment notification** via push, email, and voice-outreach-service (SMS)
- [ ] **Build assignment analytics**: acceptance rate, time-to-contact, win rate by attorney

### Phase 5: Document Automation + Dashboards (Week 4)

**Objective**: Automated document workflows and executive visibility.

- [ ] **Create document template system** with Jinja2 + WeasyPrint PDF generation
- [ ] **Integrate Docuseal** at 127.0.0.1:3010 for e-signature workflows
- [ ] **Build filing deadline calendar** with multi-escalation notification (T-14, T-7, T-3, T-1)
- [ ] **Create Superset dashboards** (connect to 127.0.0.1:8088): pipeline, forecast, attorney performance, county performance
- [ ] **Build real-time KPI WebSocket** (extend `routes/ws.py`) for live metrics
- [ ] **Implement InsForge storage integration** for signed documents at `http://localhost:7130/api/storage`
- [ ] **Build document status tracking** UI: drafted -> sent -> signed -> filed
- [ ] **Create executive report generator** (weekly PDF export via Superset API)

### Phase 6: Multi-Product Packaging + Billing (Week 5)

**Objective**: Monetize the platform with tiered pricing.

- [ ] **Define billing plans** in `surplus_billing_plans` table
- [ ] **Build entitlement middleware** in FastAPI: check subscription before serving API
- [ ] **Create subscription management UI** in portal: plan selection, upgrade/downgrade
- [ ] **Implement feature gating** per plan (county limits, lead limits, API call limits)
- [ ] **Build admin billing dashboard**: active subscriptions, MRR, churn rate
- [ ] **Integrate Stripe** for payment processing (Phase 1: manual invoicing)
- [ ] **Create white-label onboarding flow**: custom domain, logo, document templates, colors
- [ ] **Add usage metering** for API tier (Prometheus counter -> billing increment)
- [ ] **Build self-service signup** flow (basic: email + password -> free tier activated)

---

## 12. Capacity Planning

### 12.1 Current Headroom

- **CPU**: 16 vCPUs, all services currently use ~20% aggregate. Headroom for 4-6 additional microservices.
- **RAM**: 30 GB total, 15 GB used. Headroom for ~10 GB additional workload.
- **Disk**: 338 GB total, 61 GB used. Headroom for 200+ GB of document storage.
- **Database**: Postgres on separate port (5433), shared with FRGCRM. Expected growth at scale: 50 GB/year at 10,000 cases/month.

### 12.2 Projected Growth

| Metric | Month 1 | Month 6 | Month 12 |
|---|---|---|---|
| Cases scraped | 5,000 | 50,000 | 200,000 |
| Documents parsed | 5,000 | 50,000 | 200,000 |
| Leads scored | 3,000 | 30,000 | 120,000 |
| Attorneys matched | 500 | 5,000 | 20,000 |
| Documents generated | 200 | 2,000 | 10,000 |
| Postgres storage | 2 GB | 20 GB | 80 GB |
| Document storage | 5 GB | 50 GB | 200 GB |
| API requests/month | 10,000 | 100,000 | 500,000 |

### 12.3 Scaling Strategy

At Month 6 volumes, add a dedicated Postgres instance for SurplusAI data (separate from the shared `frgcrm` database). At Month 12, consider:

- **Read replicas** for the analytics workload (Superset queries)
- **Object storage** (S3-compatible) for parsed document payloads
- **Dedicated Neo4j instance** for the case relationship graph
- **Queue-based adapter execution** via Temporal to parallelize county scrapes

---

## 13. Security Architecture

### 13.1 Network Security

- All services bind to `127.0.0.1` only -- no direct external exposure
- Traefik handles TLS termination, rate limiting, and basic auth for admin routes
- Cloudflare WAF at the edge: DDoS protection, bot management, geo-blocking
- All inter-service communication on localhost -- no encryption overhead
- Database connections authenticated with per-service credentials

### 13.2 Data Security

- **At rest**: PostgreSQL TDE (via filesystem-level encryption on the host)
- **In transit**: Cloudflare TLS to edge, plain localhost between services
- **Secrets**: API keys stored in PM2 environment variables, never in code
- **Document store**: InsForge auth at `http://localhost:7130/api/auth` with API key validation
- **Audit**: All data access logged to `surplus_audit_log` table with actor, action, resource, and timestamp
- **PII isolation**: Per-tenant schema separation in white-label tier

### 13.3 Compliance

- Annual security review cadence (aligned with Wheeler AIOps cycle)
- Document retention policies configurable per tenant (default: 7 years)
- Right-to-deletion API endpoint for GDPR/CALEA compliance
- Data export (JSON + PDF) on tenant cancellation

---

## 14. Success Metrics

### 14.1 North Star

**Revenue generated through SurplusAI-assigned leads** (measured via FRGCRM deal stage = "won").

### 14.2 Leading Indicators

| Metric | Target (Month 3) | Target (Month 12) |
|---|---|---|
| Cases scraped per week | 2,500 | 40,000 |
| AI parsing auto-accept rate | 80% | 95% |
| Leads scored per week | 1,500 | 24,000 |
| Leads assigned per week | 250 | 4,000 |
| Attorney acceptance rate | 60% | 80% |
| Average days from scrape to assignment | 3 | < 1 |
| Paid subscribers | 10 | 100 |
| Monthly Recurring Revenue (MRR) | $15,000 | $200,000 |

### 14.3 Quality Gates

Each phase gates on demonstrable metrics before the next phase begins:

- **Phase 1 Gate**: Scraper uptime > 99% over 48 hours, portal API responding < 200ms p95
- **Phase 2 Gate**: Top 5 adapters collecting cases with < 5% error rate over 7 days
- **Phase 3 Gate**: AI parsing auto-accept rate > 75% across 1,000 documents
- **Phase 4 Gate**: Lead-to-assignment time < 24 hours for score > 80
- **Phase 5 Gate**: Document generation success rate > 95%, e-signature turnaround < 48 hours
- **Phase 6 Gate**: MRR > $10,000 with < 5% churn in first 60 days

---

## 15. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| County data source changes format | Medium | High | Adapter health checks with automated alerting; versioned adapter instances with fallback to previous working version |
| DeepSeek API rate limiting | Low | Medium | LiteLLM proxy handles rate limiting and failover; cache common extraction patterns locally |
| LLM hallucination on extracted fields | Medium | High | Confidence scoring with mandatory human review below threshold; field-level validation rules per county |
| Attorney churn (not accepting assignments) | Medium | Medium | Multi-attorney assignment per lead; automated re-assignment on decline; performance score decay for non-responsive attorneys |
| Postgres capacity at scale | Low | Medium | Separate SurplusAI database at Month 6; read replicas at Month 12; archive old cases to object storage |
| Competitor enters market | High | Medium | First-mover advantage with 5-county adapter coverage; white-label lock-in with law firm branding; data network effects from more cases = better scoring |

---

## 16. Appendix: Service Port Map

| Port | Service | Protocol | PM2/Docker |
|---|---|---|---|
| 8007 | SurplusAI Scraper | HTTP | PM2 id 7 |
| 8103 | SurplusAI Portal API | HTTP | PM2 id 21 |
| 8104 | SurplusAI Parser Service | HTTP | New PM2 service |
| 8105 | SurplusAI Scoring Service | HTTP | New PM2 service |
| 8082 | FRGCRM API | HTTP | PM2 id 22 |
| 8086 | SurplusAI Admin Console | HTTP | New PM2 service |
| 3002 | SurplusAI Portal Frontend | HTTP | New PM2 service |
| 4049 | LiteLLM Proxy | HTTP | PM2 id 17 |
| 3010 | Docuseal | HTTP | Docker |
| 7130 | InsForge | HTTP | New or existing |
| 5433 | Postgres (FRGCRM) | PostgreSQL | Docker (frgops-standby) |
| 5434 | Postgres (RavynAI) | PostgreSQL | Docker |
| 7474 | Neo4j HTTP | HTTP | Docker (ecosystem-graph) |
| 7687 | Neo4j Bolt | Bolt | Docker (ecosystem-graph) |
| 7233 | Temporal Server | gRPC | Docker |
| 8088 | Apache Superset | HTTP | Docker |
| 9090 | Prometheus | HTTP | Docker |
| 3100 | Loki | HTTP | Docker |
| 19999 | Netdata | HTTP | Docker |

---

*End of Plan. This document is a living strategy artifact and should be reviewed and updated at each phase gate. All infrastructure references are accurate as of 2026-05-24.*
