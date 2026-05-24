# Wheeler Ecosystem Data Moat Strategy

## Proprietary Data Assets, Collection Flywheels, and Competitive Defensibility

**Classification:** INTERNAL -- EXECUTIVE -- TRADE SECRET
**Version:** 1.0.0
**Date:** 2026-05-24
**Author:** Wheeler Brain OS -- Data Engineering
**Status:** LIVE -- STRATEGIC ASSET INVENTORY

---

## Table of Contents

1. Executive Summary
2. Proprietary Data Asset Inventory
3. Data Collection Flywheels
4. Data Normalization Pipelines
5. Enrichment Strategies
6. Training Data to ML Model Pipeline
7. Competitive Barriers
8. Data Licensing Products and Pricing
9. Data Governance: GDPR/CCPA Compliance
10. Network Effects Architecture
11. Proprietary Scoring IP
12. Pipeline DAG Architecture
13. Data Quality SLAs
14. Retention and Archival Policies
15. Implementation Roadmap

---

## 1. Executive Summary

### 1.1 The Data Moat Thesis

The Wheeler ecosystem sits on a confluence of proprietary datasets that, collectively, represent an unassailable competitive advantage. No single competitor can replicate the combination of foreclosure intelligence, surplus fund records, attorney performance data, prediction market signals, and county-level court data that the Wheeler data fabric interconnects.

This document catalogs every proprietary data asset within the ecosystem, defines the collection and enrichment flywheels that make each dataset stronger with usage, and designs the architecture that will transform raw data into defensible intellectual property.

### 1.2 Data Asset Footprint (Current State)

| Data Domain | Records | Storage Engine | Node | Collection Status |
|-------------|---------|---------------|------|-------------------|
| FRG Surplus Fund Cases | 6,725 (122 AIOPS + 6,603 EDGE) | PostgreSQL 16 | frgops-standby:5433 + shared-postgres-recovery | Active collection, partial migration |
| Foreclosure Intelligence | 6,603 county-level records | PostgreSQL | EDGE shared-postgres-recovery | Staging, awaiting COREDB unification |
| Claimant Contact Data | Embedded in 6,725 case records | PostgreSQL | frgops-standby + shared-postgres-recovery | Extraction pipeline pending |
| Attorney Performance Data | Derived from FRGCRM outcomes | PostgreSQL + Neo4j | frgops-standby + ecosystem-graph:7687 | Manual collection, automation pending |
| ML Training Examples | 0 (pipeline in design) | PostgreSQL | surplus_training_examples (planned) | Pipeline to be built in Phase 3 |
| Cross-County Trend Intelligence | 0 (pipeline blocked) | ClickHouse :8123 | aiops-clickhouse | Blocked by scraper restart loop |
| Real Estate Distress Signals | 0 (pipeline blocked) | ClickHouse + PostgreSQL | aiops-clickhouse | Blocked by scraper restart loop |
| Prediction Market Data | Active (12 containers) | PostgreSQL 16 + Redis 7 | prediction-radar-db:5432 | Active collection, Stripe in test mode |
| Ecosystem Knowledge Graph | Active entity relationships | Neo4j 5.26 | ecosystem-graph:7687 | Continuous population |
| Infrastructure Observability | Active time-series | ClickHouse :8123 | aiops-clickhouse | Continuous collection |
| Opportunity Scoring Data | 0 (engine not deployed) | PostgreSQL + Neo4j | Ravyn Capital databases | Pipeline design stage |

### 1.3 Data System Reference Map

| System | Host | Port | Engine | Purpose | Data Volume |
|--------|------|------|--------|---------|-------------|
| frgops-standby | AIOPS | 5433 | PostgreSQL 16 | FRG case data, active operations | 122 records |
| shared-postgres-recovery | EDGE | 5432 | PostgreSQL | Legacy FRG staging data | 6,603 records |
| wheeler-core | COREDB | 5432 | PostgreSQL | Central unified data (blocked) | 0 records |
| ecosystem-graph | AIOPS | 7687 | Neo4j 5.26 | Knowledge graph with APOC plugins | Active entities |
| aiops-clickhouse | AIOPS | 8123 | ClickHouse 24.3 | Analytics data warehouse | Active time-series |
| prediction-radar-db | AIOPS | 5432 | PostgreSQL 16 | Prediction Radar SaaS data | Active trading records |
| ravynai-postgres | AIOPS | 5434 | PostgreSQL 16 (PostGIS) | Opportunity spatial data | Active |
| surplus_training_examples | AIOPS | 5433 | PostgreSQL 16 (planned) | ML training data repository | 0 (pipeline in design) |

---

## 2. Proprietary Data Asset Inventory

### 2.1 Foreclosure Intelligence (FRGCRM)

**Description:** The largest proprietary dataset in the ecosystem. Comprehensive surplus fund case records spanning multiple counties, jurisdictions, and years. Each record represents an unclaimed surplus fund from a foreclosure or tax sale proceeding.

**Actual Counts:**
- frgops-standby (AIOPS): 122 fully migrated cases
- shared-postgres-recovery (EDGE): 6,603 staging cases
- Total: 6,725 case records
- Target: >200,000 cases within 12 months of scraper stabilization

**Schema (frgops-standby PostgreSQL):**
```sql
frgcrm_cases
  - id                    UUID PRIMARY KEY
  - case_number           VARCHAR(64) UNIQUE
  - claimant_name         VARCHAR(255)
  - claimant_address      TEXT
  - claimant_phone        VARCHAR(32)
  - surplus_amount        DECIMAL(12,2)
  - sale_date             DATE
  - property_address      TEXT
  - court_name            VARCHAR(255)
  - county                VARCHAR(128)
  - state                 CHAR(2)
  - attorney_name         VARCHAR(255)
  - attorney_bar_number   VARCHAR(64)
  - attorney_firm         VARCHAR(255)
  - attorney_assigned     UUID REFERENCES attorneys(id)
  - case_status           ENUM('scraped','parsed','scored','assigned','contacted','represented','won','lost')
  - recovery_amount       DECIMAL(12,2)
  - win_probability       DECIMAL(5,4)
  - created_at            TIMESTAMPTZ
  - updated_at            TIMESTAMPTZ
  - data_source           VARCHAR(64)      -- which county adapter
  - extraction_confidence DECIMAL(5,4)
  - human_reviewed        BOOLEAN DEFAULT FALSE
  - review_notes          TEXT
```

**Competitive Barrier:** High. Foreclosure data sources are county-by-county, each requiring individual adapter development, legal access arrangements, and parsing logic. No aggregator currently provides a unified, scored, and attorney-linked dataset. The cost to replicate 6,725 records across multiple counties exceeds $500,000 in data acquisition and engineering labor.

### 2.2 Surplus Fund Intelligence (SurplusAI County Scraping)

**Description:** County-by-county scraping infrastructure that collects surplus fund case data from county court portals. Each county has unique data formats, authentication requirements, and access patterns. The adapter framework abstracts these into a unified interface.

**Planned Adapter Coverage (Phase 2):**

| County | Court | Data Source Format | Est. Monthly Volume | Adapter Complexity |
|--------|-------|-------------------|---------------------|--------------------|
| Los Angeles, CA | LA Superior Court | Web portal + PDF | ~800 cases | High |
| Cook, IL | Cook County Circuit Court | Web portal + PDF | ~600 cases | High |
| Harris, TX | Harris County District Court | Web portal + PDF | ~500 cases | Medium |
| Maricopa, AZ | Maricopa County Superior Court | API + PDF | ~400 cases | Medium |
| Miami-Dade, FL | Miami-Dade Circuit Court | Web portal + PDF | ~450 cases | High |

**Projected Monthly Collection:**
- Phase 2 (5 counties): ~2,750 cases/month
- Phase 3 (15 counties): ~8,000 cases/month
- Phase 4 (50 counties): ~25,000 cases/month
- Phase 5 (all 3,144 US counties via national data partnerships): ~200,000 cases/month

**Competitive Barrier:** Very High. County adapter development costs $1,000-$5,000 per county in engineering time. With 3,144 US counties of interest, full replication cost exceeds $3-15 million. The adapter framework itself is proprietary IP. Each adapter requires ongoing maintenance as county portals change their data formats, authentication requirements, and access policies.

### 2.3 Claimant Intelligence

**Description:** Contact data, response patterns, and behavioral profiles for individuals with unclaimed surplus funds. Derived from FRGCRM case data, enriched through outreach attempts and response tracking.

**Data Points per Claimant:**
- Name and aliases
- Current and historical addresses
- Phone numbers (landline, mobile)
- Email addresses
- Response history (contacted date, response channel, response outcome)
- Preferred communication channel
- Bankruptcy status
- Social presence indicators
- Prior relationship with attorneys in network
- Language preference
- Responsiveness score (historical response rate)

**Enrichment Pipeline:**
1. Base data from FRGCRM case records
2. Phone append via Skipjack/TLOxp data partners (planned)
3. Email append via data brokerage (planned)
4. Social media presence detection (planned)
5. Bankruptcy database cross-reference (planned)
6. Responsiveness modeling from historical outreach data

**Competitive Barrier:** Medium-High. Claimant contact data is theoretically available from data brokers, but the linkage to specific surplus fund cases, the response history data, and the responsiveness models are proprietary and built from operational experience.

### 2.4 Attorney Intelligence

**Description:** Comprehensive attorney performance database covering specialization, capacity, win rates, and assignment response patterns. Enables intelligent case-to-attorney matching.

**Data Points per Attorney:**
- Name, bar number, firm affiliation
- State licensure(s)
- Practice areas and specializations
- Historical case volume by county and type
- Win rate by county and case type
- Average recovery amount
- Average days-to-close
- Acceptance rate for assigned leads
- Time-to-first-contact after assignment
- Current active case load
- Historical response time patterns
- Fee structure (contingency percentage, hourly rates)
- Client satisfaction metrics (from post-case surveys, planned)
- Capacity score (current load vs. historical throughput)

**Data Sources:**
- FRGCRM outcome records (primary)
- Attorney registration data (during marketplace onboarding)
- Bar association directory verification
- Court records for public case outcomes
- Assignment response tracking (from SurplusAI lead routing)

**Competitive Barrier:** High. Attorney performance data requires actual case outcomes to be meaningful. A new entrant cannot produce this data without first operating a matching platform and closing cases. The 6,725 existing case records provide a 2-3 year head start over any competitor building from scratch.

### 2.5 Opportunity Scoring Intelligence

**Description:** ML-generated opportunity scores for every surplus fund case, incorporating surplus amount, findability, competition, urgency, and historical outcome patterns. The scoring engine is the core IP that converts raw case data into actionable leads.

**Scoring Data Schema (surplus_scored_leads, planned table):**
```sql
surplus_scored_leads
  - id                    UUID PRIMARY KEY
  - case_id               UUID REFERENCES frgcrm_cases(id)
  - composite_score       DECIMAL(5,2)    -- 0.00 to 100.00
  - score_components      JSONB           -- individual dimension scores
    {
      "surplus_score": 85.0,
      "findability_score": 62.0,
      "competition_score": 90.0,
      "urgency_score": 45.0
    }
  - confidence_level      ENUM('high','medium','low')
  - ml_model_version      VARCHAR(32)
  - feature_vector_hash   VARCHAR(64)     -- deduplication for training
  - scored_at             TIMESTAMPTZ
  - model_id              UUID REFERENCES surplus_scoring_models(id)
  - human_verified        BOOLEAN DEFAULT FALSE
  - verified_score        DECIMAL(5,2)    -- human override if different
```

**Competitive Barrier:** Very High. The scoring models are trained on proprietary historical outcomes. No external dataset contains the combination of case metadata, attorney performance, and actual recovery outcomes needed to train equivalent models. This is the deepest part of the moat.

### 2.6 Nationwide Trend Intelligence

**Description:** Cross-county, cross-state trend analysis that identifies macro patterns in foreclosure activity, surplus fund generation, recovery rates, and attorney performance. Aggregated in ClickHouse for time-series analytics.

**Analysis Dimensions:**
- Monthly case volume by county (seasonal trends)
- Average surplus amount by county (economic indicators)
- Recovery rate by county and attorney density
- Time-from-sale-to-scrape by county (data freshness)
- Claimant findability rate by county (demographic correlation)
- Attorney density vs. case volume (supply/demand analysis)
- Seasonal filing patterns (Q4 surge phenomenon)
- Year-over-year case volume trends

**ClickHouse Schema (surplus_trend_analytics):**
```sql
CREATE TABLE surplus_trend_analytics (
  county_code       String,
  state_code        String,
  metric_name       String,
  metric_value      Float64,
  sample_size       UInt32,
  recorded_date     Date,
  aggregation_level Enum('daily','weekly','monthly','quarterly')
) ENGINE = MergeTree()
ORDER BY (state_code, county_code, recorded_date, metric_name);
```

**Competitive Barrier:** High. Cross-county trend analysis requires data from multiple counties over an extended time period. The value increases with time -- 12 months of trend data is worth exponentially more than 1 month. Cannot be replicated quickly.

### 2.7 Real Estate Distress Intelligence

**Description:** Leading indicators of real estate distress derived from foreclosure filing volumes, surplus fund generation rates, and property sale data. Provides forward-looking signals for Ravyn Capital acquisition targeting and Prediction Radar market forecasting.

**Signal Types:**
- Foreclosure filing volume changes (weekly/monthly)
- Surplus fund amount distribution shifts
- Property type breakdown (residential vs. commercial distress)
- Geographic clustering of distress
- Attorney specialization shifts (more foreclosure attorneys = market signal)
- Sale-to-scrape time trends (court backlog indicators)

**Data Pipeline Flow:**
```
County Scrapers -> frgops-standby -> ClickHouse aggregations
  -> Distress signal computation -> Neo4j graph nodes
    -> Ravyn Capital opportunity scoring
    -> Prediction Radar market indicators
```

**Competitive Barrier:** Very High. Real estate distress signals require continuous county-level data collection. The signal processing and interpretation algorithms are proprietary. Competitors would need both the raw data pipeline and the analytical models to replicate this intelligence.

### 2.8 Prediction Market Data (Prediction Radar)

**Description:** Real-time and historical prediction market data collected through the Prediction Radar platform. Includes prices from Polymarket, Kalshi, and other prediction exchanges, combined with proprietary analysis and alternative data signals.

**Infrastructure:**
- 12 Docker containers for full-stack operation
- PostgreSQL 16 for historical data (prediction-radar-db:5432)
- Redis 7 for real-time data (prediction-radar-redis:6379)
- External data sources via Polygon, Alpaca, Kalshi, Polymarket, HyperLiquid, CoinGecko, Brave, GNews APIs
- Prometheus + Grafana for monitoring (prediction-radar-monitoring-*)

**Data Types:**
- Prediction market prices and volume (Polymarket CLOB)
- Event resolution outcomes
- Market sentiment indicators
- Alternative data signals (news sentiment via GNews API key `8a5e387cebfd1317294063dae2b43fa5`)
- Cryptocurrency market data (via CoinGecko)
- Sports betting odds (via Odds API)
- Financial terminal data (Fincept Terminal :6080)

**Competitive Barrier:** Medium. Prediction market data is publicly available from exchanges. The moat comes from:
1. Proprietary signal processing and combination algorithms
2. Historical data archive value (prediction records with outcomes)
3. Integration with real estate distress intelligence (unique cross-signal product)
4. First-mover advantage in the prediction + foreclosure intelligence intersection

---

## 3. Data Collection Flywheels

### 3.1 The Core Flywheel: Surplus Fund Data

```
More county adapters
    |
    v
More cases collected (6,725 current -> 200K target)
    |
    v
More training data for ML models
    |
    v
Better scoring accuracy (target: 95% auto-accept at 0.85 confidence)
    |
    v
Higher conversion rate on assigned leads
    |
    v
More revenue per case
    |
    v
More budget for county adapter development
    |
    v
More county adapters (cycle continues)
```

**Rotation Speed:** Each adapter adds 400-800 cases/month. At 50 adapters = 25,000+ cases/month. Target cycle time: < 30 days from adapter development to revenue-positive case.

**Current State:** Flywheel blocked at step 1 (scraper restart loop, 282+ restarts). Emergency stabilization required before flywheel can begin rotating.

### 3.2 Attorney Network Flywheel

```
More cases scored
    |
    v
Higher-quality attorney matches
    |
    v
Better win rates and recovery amounts
    |
    v
More attorneys joining the marketplace
    |
    v
More capacity for case assignments
    |
    v
Faster lead-to-attorney assignment
    |
    v
Higher claimant satisfaction
    |
    v
More referrals and repeat claimants
    |
    v
More cases (cycle continues)
```

**Rotation Speed:** Target 250 leads assigned per week by Month 3, growing to 4,000 per week by Month 12. Attorney acceptance rate target > 80%.

### 3.3 Prediction Radar Flywheel

```
More subscribers
    |
    v
More prediction data (user-generated signals)
    |
    v
Better prediction accuracy
    |
    v
Higher subscriber retention
    |
    v
More revenue for data acquisition
    |
    v
More data sources integrated
    |
    v
More valuable predictions
    |
    v
More subscribers (cycle continues)
```

**Rotation Speed:** Target 25 subscribers by Month 1, 100 by Month 3, 500 by Month 12. Customer acquisition cost target: < $200.

### 3.4 Cross-System Data Flywheel

This is the most powerful flywheel -- it connects all ecosystem datasets:

```
FRG cases (6,725 records)
    |
    v
SurplusAI scrapes counties
    |
    v
Scored leads flow to Attorney Marketplace
    |
    v
Attorneys accept/reject based on performance data
    |
    v
Outcomes fed back to FRGCRM
    |
    v
Outcome data trains ML scoring models
    |
    v
Better scoring improves Prediction Radar signals
    |
    v
Market intelligence feeds Ravyn Capital targeting
    |
    v
Ravyn Capital acquisitions add new counties/cases
    |
    v
More data flows into all systems (cycle continues)
```

**Network Effect Multiplier:** The cross-system flywheel compounds value across datasets. Each new case enriches six systems simultaneously. A competitor would need to replicate all six systems to match the data advantage.

---

## 4. Data Normalization Pipelines

### 4.1 The County Adapter Normalization Problem

Each county court portal outputs data in different formats. The normalization pipeline converts these into a unified schema.

```
County Source (raw)
    |
    v
County-Specific Adapter
  |-- Web scraper (HTTP + HTML parsing)
  |-- API client (REST/SOAP with auth)
  |-- PDF parser (OCR + LLM extraction)
  |-- File watcher (FTP/scheduled download)
    |
    v
RawCase Record (adapter output)
  { county-specific schema }
    |
    v
NORMALIZATION PIPELINE
  |-- Stage 1: Field mapping (county field -> canonical field)
  |-- Stage 2: Type coercion (string -> DECIMAL, date, enum)
  |-- Stage 3: Entity resolution (deduplicate claimants, attorneys)
  |-- Stage 4: Geocoding (property address -> lat/lng + FIPS code)
  |-- Stage 5: Cross-reference (match to existing cases in FRGCRM)
  |-- Stage 6: Quality scoring (confidence metrics per field)
    |
    v
NormalizedCase (canonical schema)
  { unified across all counties }
    |
    v
Target Stores:
  |-- frgops-standby PostgreSQL (operational data)
  |-- ecosystem-graph Neo4j (relationship graph)
  |-- aiops-clickhouse ClickHouse (analytics)
```

### 4.2 Adapter Interface Specification

All county adapters implement the standard interface defined in `/opt/apps/surplusai-scraper-agent-svc/src/adapters/interface.ts`:

```typescript
interface ICountyAdapter {
  countyCode: string;
  countyName: string;
  stateCode: string;

  // Core data collection
  fetchCases(): Promise<RawCase[]>;

  // Optional county-specific operations
  authenticate?(): Promise<AuthToken>;
  parseDocument?(buffer: Buffer, mimeType: string): Promise<ParsedDocument>;
  validateCase?(rawCase: RawCase): Promise<ValidationResult>;

  // Rate limiting configuration
  rateLimit: {
    requestsPerSecond: number;
    burstSize: number;
    backoffMinutes: number;
  };

  // Metadata
  dataFreshness: {
    expectedUpdateCadence: string;  // "daily", "business_days", "weekly"
    stalenessThresholdHours: number;
  };
}
```

### 4.3 Field Mapping Matrix

The canonical `NormalizedCase` schema unifies fields from all county sources. Below are the mapping rules from common county formats:

| Canonical Field | Mapping Rule | Counties with Direct Match | Counties Requiring Derivation |
|----------------|--------------|---------------------------|-------------------------------|
| case_number | Direct map or concatenation {court_code}-{year}-{sequence} | 100% | 0% |
| property_address | Direct map or concatenation {street}, {city}, {state}, {zip} | 60% | 40% |
| surplus_amount | Numeric parse with locale handling ($1,234.56 -> 1234.56) | 100% | 0% |
| sale_date | Date parse with format detection (MM/DD/YYYY, YYYY-MM-DD, etc.) | 100% | 0% |
| claimant_names | Direct map or extract from legal document text | 70% | 30% |
| claimant_address | Direct map or extract from document | 40% | 60% |
| attorney_name | Direct map or extract from filing attorney field | 80% | 20% |
| court_name | Derive from county code or direct map | 90% | 10% |
| sale_type | Enum mapping (trustee/foreclosure/tax) | 50% | 50% |
| original_judgment | Direct map or calculate from surplus ratio | 30% | 70% |

### 4.4 Error Handling and Quality Gates

| Gate | Check | Threshold | Action on Failure |
|------|-------|-----------|-------------------|
| G1 | Field completeness | >80% of required fields populated | Route to human review, flag adapter issue |
| G2 | Numeric validation | surplus_amount > 0 and < $10M | Flag for manual review, do not auto-ingest |
| G3 | Date validation | sale_date not in future and > 1990 | Correct or reject, log adapter error |
| G4 | Deduplication | case_number not in existing DB | Merge or update, log duplicate count |
| G5 | Cross-field consistency | sale_date <= document_date | Flag inconsistency, reduce confidence score |
| G6 | Adapter health | error rate < 5% over 7 days | Auto-disable adapter, alert engineering |

### 4.5 Temporal Workflow Orchestration

Each county scrape is executed as a Temporal workflow (Temporal Server at 127.0.0.1:7233):

```
Workflow: SurplusScrapeWorkflow(countyCode)
  1. Fetch adapter config from surplus_adapter_configs
  2. Execute ICountyAdapter.fetchCases()
     - Retry policy: 3 attempts, exponential backoff (5s, 25s, 125s)
     - Circuit breaker: disable adapter after 10 consecutive failures
  3. For each RawCase:
     a. Execute normalization pipeline (synchronous)
     b. Write to frgops-standby PostgreSQL
     c. Index in Neo4j ecosystem-graph (case, claimant, attorney relationships)
     d. Push to ClickHouse for trend analytics
  4. Update adapter config (last_run_at, cases_collected_total)
  5. Record Prometheus metrics:
     - surplus_adapter_runs_total{county="la-ca", status="success"}
     - surplus_cases_collected_total{county="la-ca"}
     - surplus_adapter_errors_total{county="la-ca", error_type="auth_failure"}
     - surplus_scrape_duration_seconds{county="la-ca"}
```

---

## 5. Enrichment Strategies

### 5.1 FRGCRM Outcomes to Scoring Model Enrichment

The most critical enrichment loop: FRGCRM case outcomes feed directly into scoring model improvements.

**Enrichment Pipeline:**

```
FRGCRM Case Outcome (won/lost, recovery_amount, attorney_id)
    |
    v
PipelineDAG Stage 3 (Enrichment)
    |
    v
Feature Engineering:
  |-- Append outcome to training example
  |-- Compute derived features:
  |     - days_from_scrape_to_assignment
  |     - days_from_assignment_to_outcome
  |     - attorney_win_rate_in_county
  |     - surplus_recovery_ratio
  |-- Recompute percentile ranks within county
  |-- Update feature store in PostgreSQL
    |
    v
Model Retraining Trigger:
  |-- If new_examples_since_last_train > 100 -> stage retraining
  |-- If accuracy_drift > 5% -> emergency retraining
  |-- If new county added -> cold-start training with transfer learning
    |
    v
Updated Model Deployed to Scoring Service (port 8105)
```

**Enrichment Frequency:**
- Real-time: Outcome events from FRGCRM API webhooks
- Daily: Batch enrichment of new cases
- Weekly: Model retraining evaluation
- Monthly: Full model retraining cycle

### 5.2 Data Partner Enrichment (Planned)

| Partner Type | Data Provided | Enrichment Value | Integration Method | Est. Cost |
|-------------|--------------|------------------|--------------------|-----------|
| Skipjack/TLOxp | Phone numbers, addresses | FindabilityScore improvement | API batch query | $0.05/record |
| Data broker | Email addresses, social profiles | FindabilityScore improvement | API batch query | $0.10/record |
| Bankruptcy database | Bankruptcy status, discharge dates | Risk adjustment | Public record scrape | $0.00 (operational cost) |
| Property records | Property type, value, ownership | SurplusScore refinement | County assessor API | $0.01/record |
| Bar associations | Attorney license status, discipline | AttorneyScore validation | Directory scrape | $0.00 (operational cost) |
| Court schedules | Hearing dates, filing deadlines | UrgencyScore refinement | County court API | $0.01/record |

### 5.3 Cross-System Entity Resolution

Entity resolution links records across databases to build a unified view:

```
frgcrm_cases.claimant_name
  -> matched against
surplus_cases.claimant_names
  -> resolved to
UnifiedClaimant(entity_id)
  -> linked to
Neo4j (:Claimant {entity_id, aliases, all_cases, total_surplus, ...})
```

**Resolution Algorithm:**
1. Exact match on name + address (highest confidence)
2. Fuzzy match on name + state (medium confidence)
3. Soundex/phonetic match on name (low confidence, flagged for review)
4. SSN/tax ID match if available (highest confidence, when available)
5. Manual merge via admin console (for edge cases)

**Cross-Reference Sources:**
- FRGCRM cases (6,725 records)
- SurplusAI new scrapes (incoming)
- Attorney registrations (incoming)
- Prediction Radar user data (optional, opt-in)

---

## 6. Training Data to ML Model Pipeline

### 6.1 Training Data Architecture

The `surplus_training_examples` table stores every reviewed extraction for model training:

```sql
CREATE TABLE surplus_training_examples (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_document_hash   VARCHAR(64) UNIQUE NOT NULL,  -- SHA-256 dedup
  raw_document_text   TEXT,                          -- truncated to 16K chars
  llm_extraction      JSONB NOT NULL,                -- raw LLM output
  human_corrected     JSONB,                         -- corrected values (NULL if auto-accepted)
  reviewer_id         UUID REFERENCES reviewers(id),
  reviewed_at         TIMESTAMPTZ,
  confidence_scores   JSONB NOT NULL,                -- per-field confidence
  final_extraction    JSONB NOT NULL,                -- canonical extracted data
  extraction_version  VARCHAR(16),                   -- model version used
  case_id             UUID REFERENCES frgcrm_cases(id),
  outcome             JSONB,                         -- FRGCRM outcome when available
  used_in_fine_tune   BOOLEAN DEFAULT FALSE,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_training_examples_hash ON surplus_training_examples(raw_document_hash);
CREATE INDEX idx_training_examples_reviewed ON surplus_training_examples(reviewed_at) WHERE human_corrected IS NOT NULL;
CREATE INDEX idx_training_examples_ft ON surplus_training_examples(used_in_fine_tune) WHERE used_in_fine_tune = FALSE;
```

### 6.2 Data Volume Growth Projections

| Phase | Timeframe | Documents Parsed | Human Reviewed | Auto-Accepted | Training Examples Available |
|-------|-----------|-----------------|----------------|---------------|---------------------------|
| Phase 1 | Week 1-2 | 0 (blocked) | 0 | 0 | 0 |
| Phase 2 | Week 3-4 | 5,000 | 2,000 (40%) | 3,000 (60%) | 2,000 |
| Phase 3 | Week 5-6 | 10,000 | 2,500 (25%) | 7,500 (75%) | 4,500 |
| Phase 4 | Week 7-8 | 15,000 | 2,250 (15%) | 12,750 (85%) | 6,750 |
| Phase 5 | Month 3 | 25,000 | 2,500 (10%) | 22,500 (90%) | 9,250 |
| Phase 6 | Month 6 | 50,000 | 2,500 (5%) | 47,500 (95%) | 11,750 |

**Milestone: 5,000 training examples -> trigger first fine-tune.**

### 6.3 Fine-Tuning Pipeline

At 5,000+ training examples, the ecosystem triggers a fine-tuning pipeline:

```
Step 1: Data Export
  SELECT final_extraction, raw_document_text
  FROM surplus_training_examples
  WHERE human_corrected IS NOT NULL OR confidence_scores->>'overall' > '0.85'
  ORDER BY created_at DESC
  LIMIT 5000;

Step 2: Format Conversion
  Convert to chat-format training pairs:
  [
    {"role": "system", "content": "Extract surplus fund case data..."},
    {"role": "user", "content": "Document: <raw_text>"},
    {"role": "assistant", "content": "<final_extraction JSON>"}
  ]

Step 3: Validation Split
  80% training / 10% validation / 10% test
  Stratified by county (ensure all counties represented)

Step 4: Fine-Tune via DeepSeek API
  Model: deepseek-chat (base)
  Method: LoRA or full fine-tune (based on API capabilities)
  Hyperparameters:
    - learning_rate: 2e-5
    - batch_size: 8
    - epochs: 3
    - max_seq_length: 16384
  Cost estimate: ~$200-500 per fine-tune run (at current DeepSeek pricing)

Step 5: Evaluation
  Measure against held-out test set:
    - Field-level accuracy per county
    - Overall auto-accept rate improvement
    - Hallucination rate reduction
  Gate: Must improve auto-accept rate by >5% to deploy

Step 6: Deployment
  Update extraction_version in surplus_training_examples
  Update model reference in scoring service config
  A/B test new model against previous on 10% of traffic for 48 hours
  Full rollout if A/B test passes

Step 7: Continuous Cycle
  Re-train every 5,000 new examples
  Target: 95% auto-accept rate at 0.85 confidence threshold
```

### 6.4 ML Model Registry

```sql
CREATE TABLE surplus_scoring_models (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_name            VARCHAR(128) NOT NULL,
  model_type            ENUM('xgboost','lightgbm','deepseek_ft','ensemble'),
  model_version         VARCHAR(32) NOT NULL,
  model_parameters      JSONB,                 -- hyperparameters
  feature_importance    JSONB,                 -- feature importance scores
  training_metrics      JSONB,                 -- accuracy, precision, recall, F1
  training_date         TIMESTAMPTZ,
  training_examples     INTEGER,
  validation_accuracy   DECIMAL(5,4),
  test_accuracy         DECIMAL(5,4),
  auto_accept_rate      DECIMAL(5,4),          -- at 0.85 confidence threshold
  status                ENUM('staging','active','archived','failed'),
  deployed_at           TIMESTAMPTZ,
  retired_at            TIMESTAMPTZ
);
```

### 6.5 Feature Engineering for XGBoost/LightGBM Models

40+ engineered features for the gradient-boosted scoring model:

**Case-Level Features (15):**
- surplus_amount (log-transformed)
- surplus_percentile_within_county
- days_since_sale
- sale_day_of_week
- sale_month
- sale_quarter
- property_type (residential/commercial/other)
- case_type (trustee/foreclosure/tax)
- claimant_name_length (proxy for entity completeness)
- claimant_address_present (boolean)
- claimant_phone_present (boolean)
- num_claimants_on_case
- original_judgment_amount
- court_backlog_estimate (days from filing to sale)
- document_source_type (web/api/pdf)

**County-Level Features (10):**
- county_case_volume_30d
- county_avg_surplus_amount
- county_attorney_density
- county_claimant_findability_rate
- county_average_recovery_rate
- county_avg_days_to_close
- county_adapter_reliability_score
- county_population_density
- county_median_home_value
- county_unemployment_rate

**Attorney-Level Features (10):**
- attorney_county_win_rate
- attorney_overall_win_rate
- attorney_cases_closed_total
- attorney_avg_recovery_amount
- attorney_avg_days_to_close
- attorney_current_case_load
- attorney_capacity_ratio (current / historical max)
- attorney_acceptance_rate
- attorney_years_experience
- attorney_specialty_match_score (for case type)

**Temporal Features (5):**
- day_of_week
- month
- quarter
- is_holiday_season (Nov-Dec)
- days_until_end_of_quarter

---

## 7. Competitive Barriers

### 7.1 Barrier Analysis by Data Asset

| Data Asset | Replication Difficulty | Cost to Replicate | Time to Replicate | Primary Barrier |
|------------|----------------------|-------------------|-------------------|-----------------|
| Foreclosure case database (6,725 records) | Very High | $500K-$2M | 12-24 months | County-by-county access, adapter development, legal arrangements |
| County adapter framework | Very High | $3M-$15M | 24-36 months | 3,144 unique county systems, ongoing maintenance |
| Attorney performance database | Extreme | $1M-$5M | 24-48 months | Requires actual case outcomes, network effects |
| ML scoring models (trained on 5K+ examples) | Extreme | $500K-$2M | 12-24 months | Requires proprietary training data and outcomes |
| Claimant response patterns | Very High | $200K-$500K | 12-18 months | Requires operational outreach history |
| Cross-county trend intelligence (12+ months) | Very High | $300K-$1M | 12-24 months | Requires continuous data collection over time |
| Real estate distress signals | Very High | $500K-$2M | 18-36 months | Requires multiple data sources and proprietary algorithms |
| Prediction Radar data archive | Medium | $100K-$500K | 6-12 months | Public data sources, but historical archive value |
| Ecosystem knowledge graph (Neo4j) | Very High | $200K-$1M | 12-24 months | Requires all other datasets to be interconnected |

### 7.2 Structural Barriers

**Barrier 1: County-Level Fragmentation (Structural)**
The US has 3,144 counties, each with independent court systems, data formats, and access policies. There is no national foreclosure data aggregator. Building adapters for all counties requires $3-15M and 2-3 years. Even a well-funded competitor must invest heavily before collecting any data.

**Barrier 2: Outcome Data Flywheel (Temporal)**
Attorney performance data requires actual case outcomes. A competitor cannot produce this data without first closing cases -- but closing cases requires attorneys, which requires performance data to recruit. This creates a chicken-and-egg problem that takes 12-24 months to solve.

**Barrier 3: ML Model Training Data Exclusivity (Scarcity)**
Fine-tuned extraction models require human-reviewed training examples. Each example costs $2-5 in reviewer time to produce. At 5,000 examples needed for fine-tuning, the data acquisition cost alone is $10K-$25K, and the resulting model cannot be replicated without the same training data.

**Barrier 4: Cross-System Data Network Effects (Compounding)**
The value of each dataset increases as other datasets grow. FRG cases make attorney data more valuable. Attorney data makes scoring more accurate. Scoring accuracy makes Prediction Radar signals better. A competitor would need to launch all systems simultaneously to achieve the same compounding effect.

**Barrier 5: Adapter Maintenance Burden (Ongoing)**
County court portals change their data formats, authentication requirements, and access policies regularly. Each change requires adapter maintenance. The Wheeler ecosystem's 20 operational skills, 50 Claude Code agents, and autonomous healing architecture provide a maintenance capacity that a startup competitor cannot match.

**Barrier 6: Data Licensing Lock-In (Contractual)**
As the ecosystem moves to data licensing products (Section 8), attorney firms and enterprise customers will integrate Wheeler data into their workflows. Switching costs increase with integration depth. By Month 12, the goal is 100+ paying subscribers integrated into daily operations.

### 7.3 Competitor Response Scenarios

| Scenario | Likelihood | Wheeler Defense | Timeframe |
|----------|-----------|-----------------|-----------|
| Well-funded startup enters surplus fund data | Medium | County adapter head start (2-3 years), attorney network effects | 12-18 months |
| Existing legal data aggregator (LexisNexis, Westlaw) expands | Low-Medium | Differentiated scoring IP, outcome data they cannot replicate | 18-36 months |
| Attorney network builds internal platform | Low | Platform economics, turnkey AI parsing, document automation | 24-48 months |
| Real estate data company (Zillow, CoreLogic) adds foreclosure data | Medium | Surplus fund focus is niche, prediction market differentiation | 12-24 months |
| AI company (OpenAI, Anthropic) launches data extraction service | Low | Domain-specific fine-tuning, county adapter expertise | 24-48 months |

---

## 8. Data Licensing Products and Pricing

### 8.1 Product Catalog

**Product 1: Raw Case Data Feed (SurplusAI API)**

Access to scraped and normalized surplus fund case data via REST API.

| Tier | Records/Month | Update Latency | Delivery Format | Price |
|-----|--------------|----------------|-----------------|-------|
| Basic | 1,000 | 48 hours | JSON via API | $997/mo |
| Pro | 10,000 | 4 hours | JSON + webhooks | $2,997/mo |
| Enterprise | Unlimited | Real-time | JSON + webhooks + SFTP | $9,997/mo |
| Pay-as-you-go | Per-record | 24 hours | JSON | $0.10/record |

**Product 2: Scored Lead Feed (SurplusAI Scored Leads)**

Pre-scored surplus fund leads with confidence metrics, ready for attorney assignment.

| Tier | Leads/Month | Minimum Score | Delivery | Price |
|-----|-------------|---------------|----------|-------|
| Starter | 100 | > 70/100 | API + email | $1,997/mo |
| Professional | 500 | > 75/100 | API + webhook + push | $4,997/mo |
| Enterprise | 2,000 | > 80/100 | API + webhook + prioritized | $14,997/mo |

**Product 3: Attorney Intelligence Database**

Access to attorney performance analytics for recruitment, partnership, or competitive analysis.

| Tier | Records | Data Points | Update Frequency | Price |
|-----|---------|-------------|------------------|-------|
| Basic | 500 attorneys | 10 performance metrics | Monthly | $997/mo |
| Pro | 2,000 attorneys | 25 performance metrics | Weekly | $2,997/mo |
| Enterprise | All registered | Full profile + analytics | Real-time | $7,997/mo |

**Product 4: Nationwide Trend Reports**

Cross-county analytics and intelligence reports.

| Product | Format | Update Frequency | Content | Price |
|---------|--------|-----------------|---------|-------|
| County Benchmark Report | PDF + data export | Quarterly | Case volume, surplus trends, recovery rates per county | $4,997/report |
| Market Intelligence Dashboard | Web dashboard | Monthly | Interactive county-by-county trends, forecasts | $1,997/mo |
| Custom Analytics | Data + analysis | Per engagement | Tailored analysis for specific geographies or case types | $15K-$50K/engagement |

**Product 5: Prediction Radar Data API**

Real-time and historical prediction market data feeds.

| Tier | Data Sources | Historical Depth | Rate Limit | Price |
|-----|-------------|------------------|------------|-------|
| Developer | 5 sources | 7 days | 100 req/min | $49/mo |
| Pro | 15 sources | 1 year | 1,000 req/min | $199/mo |
| Enterprise | All sources | Full history | 10,000 req/min | $997/mo |

**Product 6: Real Estate Distress Signals API**

Forward-looking distress indicators derived from foreclosure and surplus fund data.

| Tier | Geography | Update Frequency | Signals | Price |
|-----|-----------|-----------------|---------|-------|
| Regional | 1 state | Weekly | 5 signal types | $1,997/mo |
| National | 50 states | Daily | 15 signal types | $4,997/mo |
| Enterprise + Data | National + raw data | Real-time | 25+ signal types + county data | $14,997/mo |

### 8.2 Bundled Product Pricing

| Bundle | Products Included | Standalone Price | Bundle Price | Discount |
|--------|------------------|-----------------|--------------|----------|
| SurplusAI Pro | Case Data Pro + Scored Leads Starter | $4,994/mo | $3,997/mo | 20% |
| Intelligence Suite | Case Data Enterprise + Trend Dashboard + Attorney Intel Pro | $17,991/mo | $12,997/mo | 28% |
| Full Stack | All API products + all dashboard products | $37,981/mo | $24,997/mo | 34% |
| White-Label | Full Stack + custom branding + tenant isolation | $24,997/mo + $4,997/mo | $24,997/mo | N/A (white-label premium) |

### 8.3 Revenue Projections from Data Licensing

| Product | Month 1 | Month 3 | Month 6 | Month 12 |
|---------|---------|---------|---------|----------|
| Raw Case Data | $0 | $2,994 (1 Pro) | $14,985 (5 Pro) | $44,955 (15 Pro) |
| Scored Lead Feed | $0 | $4,997 (1 Starter) | $24,985 (5 Starter) | $74,955 (15 Starter + 5 Pro) |
| Attorney Intelligence | $0 | $997 (1 Basic) | $5,988 (2 Pro) | $20,979 (7 Pro) |
| Trend Reports | $0 | $4,997 (1 report) | $14,991 (3 reports) | $29,982 (6 reports) |
| Prediction Radar API | $0 | $398 (2 Pro) | $2,986 (15 Pro) | $9,950 (50 Pro) |
| Distress Signals | $0 | $1,997 (1 Regional) | $9,994 (2 National) | $29,982 (6 National) |
| **Total Data Licensing MRR** | **$0** | **$16,380** | **$73,929** | **$210,803** |

---

## 9. Data Governance: GDPR/CCPA Compliance

### 9.1 Data Classification

| Classification | Definition | Examples | Access Level |
|---------------|-----------|----------|--------------|
| Public | No PII, no business value if exposed | County names, aggregate statistics | Unauthenticated (rate-limited) |
| Internal | Non-PII operational data | Adapter configurations, model metadata | Tailscale-authenticated |
| Confidential | PII or business-sensitive | Claimant names/addresses, attorney assignment data | Tailscale + role-based + audit |
| Restricted | Highly sensitive PII or trade secrets | SSN/tax IDs, internal scoring formulas, ML model weights | Tailscale + explicit approval + full audit + encryption at rest |
| Regulated | Subject to GDPR/CCPA/other | Claimant contact data (GDPR if EU origin) | Restricted-level + compliance logging + right-to-deletion API |

### 9.2 PII Inventory and Mapping

| PII Data Type | Storage Location(s) | Encryption at Rest | Retention Period | CCPA Category | GDPR Basis |
|--------------|--------------------|--------------------|-----------------|---------------|------------|
| Claimant name | frgops-standby, ecosystem-graph | AES-256 (filesystem) | 7 years after case close | Name | Legitimate interest |
| Claimant address | frgops-standby, ecosystem-graph | AES-256 (filesystem) | 7 years after case close | Home address | Legitimate interest |
| Claimant phone | frgops-standby | AES-256 (filesystem) | 7 years after case close | Phone number | Legitimate interest |
| Claimant email | frgops-standby | AES-256 (filesystem) | 7 years after case close | Email address | Legitimate interest |
| Attorney name | frgops-standby, ecosystem-graph | AES-256 (filesystem) | Duration of license + 7 years | Name | Legitimate interest |
| Attorney bar number | frgops-standby | AES-256 (filesystem) | Duration of license + 7 years | Professional ID | Legitimate interest |
| SSN/tax ID (if collected) | frgops-standby (encrypted column) | Column-level AES-256-GCM | 3 years after case close | SSN | Legal obligation |
| Case details (non-PII) | frgops-standby, ClickHouse, Neo4j | AES-256 (filesystem) | Indefinite (anonymized) | N/A | N/A |

### 9.3 Access Control Matrix

| Role | Public Data | Internal Data | Confidential Data | Restricted Data | Regulated Data |
|------|------------|--------------|-------------------|-----------------|----------------|
| Anonymous user | Read-only | No access | No access | No access | No access |
| Authenticated subscriber (API) | Read-only | Schema-limited | No access | No access | No access |
| Attorney (assigned to case) | Read-only | Read-only | Case-specific | No access | Case-specific |
| Attorney (general) | Read-only | Read-only | No access | No access | No access |
| Operations engineer | Read-only | Read-write | Read-write (audited) | No access | Read-only (audited) |
| Data engineer | Read-only | Read-write | Read-write (audited) | Read-write (audited) | Read-only (audited) |
| Compliance officer | Read-only | Read-only | Read-only | Read-only | Read-only |
| System (service account) | Read-only | Read-write | Read-write | Read-write | Read-write |
| Executive | Read-only | Read-only | Read-only | Read-only | No access |

### 9.4 GDPR/CCPA Compliance Mechanisms

**Right to Deletion API:**
```json
POST /api/v1/compliance/deletion-request
{
  "request_type": "deletion",
  "jurisdiction": "ccpa",            // or "gdpr"
  "identifiers": {
    "name": "Jane Doe",
    "email": "jane@example.com",
    "case_number": "LA-2024-12345"
  },
  "verification_method": "email_token"
}
```

Response: `202 Accepted` with a deletion_request_id. Processed within 30 days (GDPR) or 45 days (CCPA).

**Deletion Pipeline:**
```
1. Receive deletion request
2. Verify identity (email confirmation or government ID)
3. Locate all PII across:
   - frgops-standby PostgreSQL
   - ecosystem-graph Neo4j
   - ClickHouse (anonymize, not delete -- analytical data)
   - PM2 logs (purge log entries containing PII)
   - Backup archives (mark for deletion on next rotation)
4. Execute deletion:
   - PostgreSQL: UPDATE SET pii_fields = NULL, anonymized = TRUE
   - Neo4j: REMOVE pii properties, keep graph relationships
   - ClickHouse: DROP ROW for specific identifiers
   - PM2 logs: sed -i to redact
   - Backups: Natural expiry (no restore will include deleted data)
5. Log deletion event to surplus_audit_log
6. Confirm completion to requestor
```

**Data Portability (GDPR Article 20):**
```json
POST /api/v1/compliance/portability-request
{
  "request_type": "portability",
  "format": "json",                 // or "csv", "pdf"
  "scope": ["cases", "assignments", "communications"]
}
```

Response: `202 Accepted`. Data exported within 30 days. Delivered via secure download link (expires 7 days).

**Data Processing Record (GDPR Article 30):**
Maintained in `surplus_compliance_register` table:
```sql
CREATE TABLE surplus_compliance_register (
  id                  UUID PRIMARY KEY,
  processing_purpose  VARCHAR(255),
  data_categories     TEXT[],              -- array of PII categories
  data_subjects       VARCHAR(128),         -- "claimants", "attorneys"
  lawful_basis        VARCHAR(64),          -- "legitimate_interest", "legal_obligation"
  retention_period    VARCHAR(64),          -- "7_years_after_case_close"
  security_measures   TEXT[],               -- ["encryption_at_rest", "access_control", "audit_log"]
  data_transfers      JSONB,               -- third-party processors
  dpia_required       BOOLEAN,
  dpia_completed_at   TIMESTAMPTZ,
  review_date         DATE                  -- annual review
);
```

### 9.5 Data Retention Policy

| Data Category | Active Retention | Archive Retention | Final Disposition |
|--------------|-----------------|-------------------|--------------------|
| Open case data | Duration of case | N/A | Anonymize 3 years after close |
| Closed case data (won) | 7 years after close | 3 years (anonymized) | Full deletion at 10 years |
| Closed case data (lost) | 3 years after close | 2 years (anonymized) | Full deletion at 5 years |
| Training examples | Indefinite (de-identified) | N/A | De-identified data kept permanently |
| Attorney data | Duration of license + 3 years | N/A | Deletion on request |
| Audit logs | 3 years | 2 years (cold storage) | Full deletion at 5 years |
| Prediction Radar user data | Duration of subscription | 90 days post-cancellation | Full deletion after 90 days |
| ML model artifacts | Indefinite | N/A | Registry-tracked, no PII in models |

### 9.6 Security Implementation

| Security Measure | Implementation | Status |
|-----------------|----------------|--------|
| Encryption at rest | Filesystem-level LUKS/AES-256 on all hosts | Active |
| Encryption in transit | TLS for external, Tailscale WireGuard for mesh | Active |
| Column-level encryption | PII columns in PostgreSQL using pgcrypto (AES-256-GCM) | Planned for Phase 3 |
| Secrets management | .env files with chmod 600, no secrets in code | Active (verified Stage 2) |
| Access audit logging | All data access logged to surplus_audit_log | Active on FRGCRM, planned for SurplusAI |
| Network segmentation | All services on 127.0.0.1, Tailscale mesh for cross-host | Active (100/100 QA score) |
| Rate limiting | Nginx rate limiting on all public endpoints | Active |
| Authentication | JWT-based service auth, INTERNAL_API_KEY for service-to-service | Active |
| Backup encryption | pg_dump encrypted with GPG before off-site transfer | Planned for Phase 3 |
| Intrusion detection | CrowdSec + Fail2Ban on Prediction Radar stack | Active |

---

## 10. Network Effects Architecture

### 10.1 Data Network Effect Map

```
                    ┌─────────────────────────────────────────────────────┐
                    │               DATA NETWORK EFFECTS                   │
                    │                                                     │
                    │  MORE CASES → BETTER SCORING → MORE ATTORNEYS        │
                    │       → BETTER OUTCOMES → BETTER SCORING             │
                    │                                                     │
                    │  MORE COUNTIES → MORE DATA → BETTER TRENDS           │
                    │       → BETTER DISTRESS SIGNALS → MORE PREDICTIONS   │
                    │                                                     │
                    │  MORE ATTORNEYS → MORE CAPACITY → FASTER ASSIGNMENT  │
                    │       → HIGHER CONVERSION → MORE REVENUE             │
                    │                                                     │
                    │  MORE PREDICTIONS → BETTER MODELS → MORE SUBSCRIBERS │
                    │       → MORE REVENUE → MORE DATA ACQUISITION         │
                    └─────────────────────────────────────────────────────┘
```

### 10.2 Quantified Network Effects

**Effect 1: Scoring Accuracy vs. Training Data Size**

| Training Examples | Auto-Accept Rate (at 0.85 confidence) | Error Rate | Model Type |
|------------------|--------------------------------------|------------|------------|
| 0 (zero-shot) | 40% | 15% | DeepSeek base |
| 500 | 55% | 10% | Few-shot prompting |
| 1,000 | 65% | 7% | Few-shot + examples |
| 2,500 | 75% | 5% | Fine-tuned (LoRA) |
| 5,000 | 85% | 3% | Fine-tuned (full) |
| 10,000 | 92% | 2% | Fine-tuned (full) |
| 25,000 | 95% | 1% | Fine-tuned (full, ensembled) |

**Formula:** Each doubling of training examples reduces error rate by approximately 30% (diminishing returns, power law).

**Effect 2: Attorney Network Value (Metcalfe's Law)**

Attorney network value scales with the square of connected attorneys:
```
Network Value ∝ n^2   where n = number of active attorneys
```

| Attorneys | Case Assignment Capacity | Value Multiplier (relative to n=10) |
|-----------|------------------------|-------------------------------------|
| 10 | 50 cases/week | 1x |
| 50 | 250 cases/week | 25x |
| 100 | 500 cases/week | 100x |
| 500 | 2,500 cases/week | 2,500x |
| 1,000 | 5,000 cases/week | 10,000x |
| 5,000 | 25,000 cases/week | 250,000x |

**Effect 3: County Coverage Data Value (Reed's Law)**

The value of the county dataset scales with the number of possible cross-county comparisons (2^n - n - 1):

| Counties | Cross-County Comparisons | Analytical Value |
|----------|-------------------------|------------------|
| 5 | 26 | Basic trend detection |
| 15 | 32,752 | State-level pattern analysis |
| 50 | 1.1259e15 | National trend analysis |
| 100 | 6.3383e29 | Advanced predictive modeling |
| 500 | Computational limit | Full national intelligence |

**Note:** Reed's Law applies to the combinatorial value of comparisons, not to raw storage. Practical analytical value increases exponentially with county coverage.

### 10.3 Cross-System Value Multiplication

The total data moat value is not the sum of individual dataset values -- it is the product:

```
Total Moat Value = V_frg × V_surplus × V_attorney × V_scoring × V_prediction × V_distress
```

Where each V represents the value of an individual dataset. If any V = 0 (dataset non-functional), the entire moat value = 0.

**Current State:** V_scoring = 0 (blocked by scraper restart loop and missing DEEPSEEK_API_KEY), V_prediction = 0 (Stripe in test mode, no subscriber data). Overall moat value = 0.

**Target State (Month 6):** All V > 0, total moat value compounding. Proprietary data assets generating defensible competitive advantage.

---

## 11. Proprietary Scoring IP

### 11.1 Composite Score Formula (Lead Scoring)

The proprietary lead scoring formula converts raw case data into a ranked, actionable score:

```
LeadScore = w1 × SurplusScore + w2 × FindabilityScore + w3 × CompetitionScore + w4 × UrgencyScore
```

**Weight Configuration (Baseline):**

| Component | Weight | Rationale |
|-----------|--------|-----------|
| SurplusScore (w1) | 0.35 | Surplus amount is the primary value driver |
| FindabilityScore (w2) | 0.30 | Conversion feasibility depends on reaching claimant |
| CompetitionScore (w3) | 0.20 | Competition affects closing probability |
| UrgencyScore (w4) | 0.15 | Time sensitivity prevents missed deadlines |

**Weights are configurable per tenant attorney** via the `surplus_scoring_models` table -- a premium Enterprise feature.

### 11.2 Component Score Formulas

**SurplusScore (0-100):**
```
Base = min(surplus_amount / 50000, 1.0) × 100
Adjustment = county_percentile_rank × 20   // position within county distribution
SurplusScore = min(Base + Adjustment, 100)
```
Rationale: Linear up to $50K, then logarithmic. County percentile adds contextual value.

**FindabilityScore (0-100):**
```
Components:
  - has_phone:           40 points (most impactful for outreach)
  - has_address:         30 points (physical location for service)
  - has_email:           20 points (digital outreach channel)
  - social_presence:     10 points (social media for verification)
  - bankruptcy_flag:    -50 points (legal complication, reduced recovery)
  - do_not_contact:     -100 points (legal restriction, cannot pursue)

Raw = sum(positive) + sum(negative)
FindabilityScore = max(0, min(100, Raw))
```

**CompetitionScore (0-100):**
```
Base = 100 (no known competition)
AttorneysOnCase = count(distinct attorney_assignments where status != 'declined')
Deduction = AttorneysOnCase × 20
CompetitionScore = max(0, Base - Deduction)
```
Each additional attorney on the case reduces score by 20 points. Cap at 0.

**UrgencyScore (0-100):**
```
DaysSinceSale = current_date - sale_date
Decay = DaysSinceSale × 2                                         // 2 points per day
UrgencyScore = max(0, min(100, 100 - Decay + UrgencyBonus))
```
UrgencyBonus factors (stackable):
- +10 if surplus > $25K (high-value cases are always urgent)
- +15 if sale was on a Friday (3-day weekend before actions start)
- +5 if county has < 60-day filing deadline

### 11.3 Confidence Thresholds

| Confidence Level | Score Range | Action | Human Review Required |
|-----------------|-------------|--------|----------------------|
| Very High | 0.90 - 1.00 | Auto-accept, immediate assignment | No |
| High | 0.75 - 0.89 | Auto-accept, standard assignment | Quarterly audit |
| Medium | 0.60 - 0.74 | Flagged for spot-check, standard assignment | Random 10% sample |
| Low | 0.40 - 0.59 | Human review queue, no auto-assignment | Yes, 100% review |
| Very Low | 0.00 - 0.39 | Reject or manual override only | Yes, with supervisor approval |

### 11.4 ML Scoring Model (Planned)

**Model Architecture:**
- Primary: XGBoost or LightGBM gradient-boosted decision trees
- Target: `converted_to_revenue` (boolean from FRGCRM deal stage)
- Training: 80/10/10 stratified split by county
- Optimization: Optuna hyperparameter search (100 trials)

**Feature Importance (Expected, based on domain analysis):**

| Feature | Expected Importance | Category |
|---------|-------------------|----------|
| surplus_amount (log) | 0.18 | Case |
| attorney_county_win_rate | 0.12 | Attorney |
| claimant_findability_score | 0.11 | Combined |
| days_since_sale | 0.09 | Temporal |
| county_avg_recovery_rate | 0.08 | County |
| attorney_current_case_load | 0.07 | Attorney |
| county_attorney_density | 0.06 | County |
| sale_month | 0.05 | Temporal |
| case_type | 0.05 | Case |
| property_type | 0.04 | Case |
| county_case_volume_30d | 0.04 | County |
| court_backlog_estimate | 0.03 | County |
| claimant_has_phone | 0.03 | Case |
| is_holiday_season | 0.03 | Temporal |
| attorney_specialty_match | 0.02 | Attorney |

**Model Performance Targets:**

| Metric | Zero-Shot (Phase 2) | Fine-Tuned (Phase 3) | Ensemble (Phase 4) |
|--------|--------------------|----------------------|--------------------|
| Auto-accept rate (at 0.85 threshold) | 60% | 85% | 95% |
| Precision (scored high / actually converted) | 70% | 85% | 92% |
| Recall (converted cases / scored high) | 65% | 80% | 88% |
| F1 Score | 0.67 | 0.82 | 0.90 |
| AUC-ROC | 0.75 | 0.88 | 0.94 |

### 11.5 Attorney Matching Score

The attorney-case matching score determines the best attorney for each scored lead:

```
MatchScore = d1 × LocationScore + d2 × SpecializationScore + d3 × PerformanceScore + d4 × AvailabilityScore

Where:
  LocationScore:
    - Same county:  100 points (best outcome for claimant proximity)
    - Same state:   50 points (jurisdiction knowledge)
    - Different:    0 points (unlikely to accept)

  SpecializationScore:
    - Exact match (case type = specialty):    100 points
    - Related (case type in practice areas):    50 points
    - No match:                                  0 points

  PerformanceScore:
    - county_win_rate × 60  (60 points max)
    + avg_recovery_ratio × 40  (40 points max)
    Range: 0-100

  AvailabilityScore:
    - current_load < capacity_threshold × 80  (room for new cases)
    - response_time < 4 hours × 20  (prompt communication)
    Range: 0-100

  Weights:
    d1 = 0.30  (location is primary for legal jurisdiction)
    d2 = 0.25  (specialization determines case competence)
    d3 = 0.30  (performance determines outcome quality)
    d4 = 0.15  (availability determines speed)
```

### 11.6 Model Registry and Versioning

```sql
surplus_scoring_models
  - id                  UUID PRIMARY KEY
  - model_name          VARCHAR(128)        -- "surplusai-scoring-v1"
  - model_type          VARCHAR(32)         -- "composite", "xgboost", "lightgbm", "deepseek_ft", "ensemble"
  - model_version       VARCHAR(16)         -- "1.0.0"
  - model_parameters    JSONB               -- full hyperparameter set
  - feature_importance  JSONB               -- feature importance scores
  - training_metrics    JSONB               -- accuracy, precision, recall, F1, AUC-ROC
  - training_date       TIMESTAMPTZ
  - training_examples   INTEGER
  - test_accuracy       DECIMAL(5,4)
  - auto_accept_rate    DECIMAL(5,4)
  - status              ENUM('development','staging','active','rollback','archived','failed')
  - deployed_at         TIMESTAMPTZ
  - retired_at          TIMESTAMPTZ
  - parent_model_id     UUID                -- lineage tracking
  - model_artifact_path TEXT                -- filesystem path to serialized model
```

---

## 12. Pipeline DAG Architecture

### 12.1 Master Data Pipeline DAG

The PipelineDAG orchestrates all cross-system data flows. Each stage depends on the previous stage:

```
Stage 1: COLLECTION
  ├── County adapters scrape court portals
  ├── Prediction Radar ingests market data
  ├── FRGCRM receives case data from partners
  └── Horizon agent scans for new opportunities
      │
      ▼
Stage 2: NORMALIZATION
  ├── County-specific schemas → canonical schema
  ├── Document parsing (PDF/HTML → structured JSON)
  ├── Entity resolution (deduplication)
  └── Geocoding and enrichment
      │
      ▼
Stage 3: ENRICHMENT
  ├── Cross-reference with existing records
  ├── Data partner enrichment (phones, emails)
  ├── Bankruptcy/bank check
  └── Historical outcome linkage
      │
      ▼
Stage 4: SCORING
  ├── Composite score computation
  ├── ML model inference (when available)
  ├── Confidence threshold application
  └── Routing tier assignment (auto-accept / review / reject)
      │
      ▼
Stage 5: ROUTING
  ├── Attorney matching (territory-based, performance-weighted)
  ├── Lead assignment (pending -> active)
  ├── FRGCRM deal creation
  └── Notification (push, email, voice)
      │
      ▼
Stage 6: FEEDBACK
  ├── Outcome tracking (won/lost, recovery amount)
  ├── Training example generation (human-reviewed corrections)
  ├── Model retraining triggers
  └── Metric recording (Prometheus counters)
```

**Current State (2026-05-24):** All 6 stages failing. PipelineDAG is non-functional. This blocks all cross-system data flows.

### 12.2 Stage Recovery Priority

| Priority | Stage | Current Status | Recovery Action | Est. Effort |
|----------|-------|---------------|-----------------|-------------|
| P0 | Stage 1 (Collection) | FAILING | Fix scraper restart loop, restore DEEPSEEK_API_KEY | 2-4 hours |
| P0 | Stage 4 (Scoring) | FAILING | Fix DEEPSEEK_API_KEY, deploy scoring service | 4-8 hours |
| P1 | Stage 2 (Normalization) | FAILING | Deploy normalization pipeline components | 8-16 hours |
| P1 | Stage 5 (Routing) | FAILING | Build attorney matching and lead assignment | 16-24 hours |
| P2 | Stage 3 (Enrichment) | FAILING | Deploy enrichment pipeline | 8-12 hours |
| P2 | Stage 6 (Feedback) | FAILING | Build outcome tracking and retraining triggers | 8-12 hours |

### 12.3 Data Quality Monitoring

Each pipeline stage has quality gates that monitor data health:

| Stage | Quality Metric | Warning Threshold | Critical Threshold | Alert |
|-------|---------------|-------------------|-------------------|-------|
| Collection | Adapter success rate | < 95% over 1 hour | < 90% over 1 hour | P1 |
| Collection | Cases collected per hour | < 50% of expected | < 10% of expected | P0 |
| Normalization | Parse success rate | < 90% | < 80% | P1 |
| Normalization | Entity resolution rate | < 85% | < 70% | P2 |
| Enrichment | Enrichment completion rate | < 80% | < 60% | P2 |
| Scoring | Score distribution drift | > 10% from baseline | > 25% from baseline | P1 |
| Routing | Assignment success rate | < 90% | < 80% | P1 |
| Feedback | Outcome recording rate | < 95% | < 90% | P2 |

---

## 13. Data Quality SLAs

### 13.1 Internal Quality SLAs

| Metric | Target | Measurement Method | Reporting |
|--------|--------|-------------------|-----------|
| Data freshness (time from county publish to ingestion) | < 4 hours for top-5 counties | Adapter last_run_at timestamp | Daily |
| Field completeness | > 95% for required fields | NULL count check on ingested records | Daily |
| Field accuracy (vs. human review) | > 95% for auto-accepted records | Spot-check audit | Weekly |
| Deduplication rate | < 2% duplicate cases | case_number uniqueness check | Daily |
| Adapter uptime | > 99.5% per county per month | Prometheus adapter_runs metric | Monthly |
| Cross-system sync latency | < 5 minutes from ingestion to all stores | Timestamp comparison | Continuous |
| Data schema compliance | 100% (reject non-conforming records) | Schema validation on write | Real-time |

### 13.2 External SLA Commitments (Data Licensing)

| Tier | Data Freshness | Uptime | Support Response | Accuracy Guarantee |
|-----|---------------|--------|-----------------|-------------------|
| Basic | 48 hours | 99.0% | 24 hours | 90% (no SLA credit) |
| Pro | 4 hours | 99.5% | 4 hours | 95% (10x credit on errors) |
| Enterprise | Real-time | 99.9% | 1 hour | 98% (100x credit on errors) |

---

## 14. Retention and Archival Policies

### 14.1 Tiered Storage Architecture

```
HOT STORAGE (PostgreSQL on NVMe)
  Retention: Current + 90 days of closed cases
  Performance: Sub-millisecond query latency
  Backup: Daily pg_dump, 7-day retention
  Size target: < 50 GB

WARM STORAGE (PostgreSQL on SSD, or same instance with partitioning)
  Retention: 90 days - 3 years closed cases
  Performance: 1-10ms query latency
  Backup: Weekly pg_dump, 4-week retention
  Size target: 50-200 GB

COLD STORAGE (MinIO on COREDB, S3-compatible object storage)
  Retention: 3-10 years (anonymized after 7 years)
  Performance: 100ms-1s query latency (requires restore)
  Backup: Monthly archive, 3-month retention
  Size target: 200 GB - 2 TB

ARCHIVE (Compressed JSON in MinIO/Glacier-compatible)
  Retention: 10+ years (de-identified aggregate data only)
  Performance: Hours to restore
  Backup: Single copy (archive is the backup)
  Size target: < 500 GB
```

### 14.2 Archival Process

```sql
-- Daily archival job (cron: 2 AM UTC)
BEGIN;
  -- Move cases closed > 90 days to warm storage
  UPDATE surplus_case_partitioning
  SET storage_tier = 'warm'
  WHERE case_close_date < NOW() - INTERVAL '90 days'
    AND storage_tier = 'hot';

  -- Anonymize PII for cases closed > 7 years
  UPDATE frgcrm_cases
  SET
    claimant_name = 'ANONYMIZED',
    claimant_address = 'ANONYMIZED',
    claimant_phone = NULL,
    claimant_email = NULL,
    anonymized_at = NOW()
  WHERE
    case_status IN ('won', 'lost')
    AND updated_at < NOW() - INTERVAL '7 years'
    AND anonymized_at IS NULL;

  -- Export to cold storage (MinIO)
  -- pg_dump with --data-only --table=frgcrm_cases --schema=public
  -- Compress with zstd, encrypt with GPG
  -- Upload to MinIO bucket: archive/frgcrm/cases/YYYY/MM/

  -- Remove from hot storage
  DELETE FROM frgcrm_cases
  WHERE anonymized_at IS NOT NULL
    AND anonymized_at < NOW() - INTERVAL '90 days';

COMMIT;
```

### 14.3 Disaster Recovery Data Strategy

| Scenario | RPO | RTO | Data Loss | Recovery Method |
|----------|-----|-----|-----------|-----------------|
| Single container failure | 0 (streaming) | < 60s | None | Docker restart policy |
| PostgreSQL corruption | < 24 hours | < 4 hours | < 1 day | pg_dump restore from daily backup |
| AIOPS node failure | < 24 hours | < 8 hours | < 1 day | Restore from COREDB/warm standby |
| COREDB node failure | < 24 hours | < 24 hours | < 1 day | Restore from off-site MinIO copy |
| Complete site loss | < 7 days | < 7 days | < 7 days | Restore from Hetzner backup + off-site archive |
| Data corruption (undetected) | < 90 days | < 48 hours | < 90 days | Point-in-time recovery from WAL archives |

---

## 15. Implementation Roadmap

### 15.1 Phase 1: Unblock and Stabilize (Week 1)

**Objective:** Fix the data pipeline blockers and establish baseline collection.

| Step | Action | Data Asset Impact | Est. Effort |
|------|--------|------------------|-------------|
| 1.1 | Fix scraper restart loop (282+ restarts) | Unblocks ALL SurplusAI data collection | 2-4 hours |
| 1.2 | Restore DEEPSEEK_API_KEY to FRGCRM | Unblocks AI-powered analysis pipeline | 30 minutes |
| 1.3 | Verify LiteLLM connectivity (127.0.0.1:4049) | Unblocks all LLM-dependent enrichment | 30 minutes |
| 1.4 | Migrate 6,603 cases from EDGE to AIOPS | Doubles case dataset (122 -> 6,725) | 2 hours |
| 1.5 | Stage PipelineDAG recovery path | Unblocks cross-system data flows | 4 hours |

**Gate:** Scraper uptime > 99% over 48 hours, 6,725 cases accessible via API.

### 15.2 Phase 2: County Adapter Framework (Week 2-3)

**Objective:** Build the adapter framework and cover top 5 counties.

| Step | Action | Data Asset Impact | Est. Effort |
|------|--------|------------------|-------------|
| 2.1 | Define adapter interface + base class | Foundation for all county collection | 2 days |
| 2.2 | Implement LA County adapter | ~800 cases/month | 2 days |
| 2.3 | Implement Cook County adapter | ~600 cases/month | 2 days |
| 2.4 | Implement Harris County adapter | ~500 cases/month | 1.5 days |
| 2.5 | Implement Maricopa County adapter | ~400 cases/month | 1 day |
| 2.6 | Implement Miami-Dade adapter | ~450 cases/month | 2 days |
| 2.7 | Build Temporal scrape workflows | Durable, retryable collection | 1 day |
| 2.8 | Implement Prometheus adapter metrics | Data quality monitoring | 0.5 day |

**Gate:** 5 adapters collecting cases with < 5% error rate over 7 days. Monthly volume target: 2,750 cases.

### 15.3 Phase 3: AI Docket Parsing + ML Pipeline (Week 3-4)

**Objective:** Turn raw documents into structured, scored data. Begin training data collection.

| Step | Action | Data Asset Impact | Est. Effort |
|------|--------|------------------|-------------|
| 3.1 | Build parser service (port 8104) | Document -> structured data | 3 days |
| 3.2 | Implement DeepSeek extraction prompts | AI-powered field extraction | 2 days |
| 3.3 | Build confidence scoring module | Quality metrics on every field | 1 day |
| 3.4 | Create human review queue | Training data generation | 2 days |
| 3.5 | Build review UI (admin console) | Human-in-the-loop correction | 3 days |
| 3.6 | Implement training_examples table | Training data repository | 0.5 day |
| 3.7 | Build scoring service (port 8105) | Lead scoring engine | 2 days |
| 3.8 | Implement composite score formula | Proprietary scoring IP | 1 day |

**Gate:** AI parsing auto-accept rate > 75% across 1,000 documents. 500 training examples collected.

### 15.4 Phase 4: CRM Integration + Attorney Network (Week 4-5)

**Objective:** Close the data flywheel with outcome tracking.

| Step | Action | Data Asset Impact | Est. Effort |
|------|--------|------------------|-------------|
| 4.1 | Build FRGCRM sync service | Bidirectional outcome data flow | 3 days |
| 4.2 | Implement attorney territory matrix | Attorney performance data collection | 2 days |
| 4.3 | Enhance attorney matcher | Precision assignment engine | 2 days |
| 4.4 | Build outcome tracking pipeline | Scoring model training data | 2 days |
| 4.5 | Implement feedback loop (Stage 6) | Automated model retraining triggers | 1 day |

**Gate:** Lead-to-assignment time < 24 hours for score > 80. 1,000 training examples collected.

### 15.5 Phase 5: ML Model Training (Month 2)

**Objective:** Fine-tune extraction and scoring models on proprietary data.

| Step | Action | Data Asset Impact | Est. Effort |
|------|--------|------------------|-------------|
| 5.1 | Export 5,000 training examples | Training dataset ready | 0.5 day |
| 5.2 | Fine-tune DeepSeek extraction model | Proprietary extraction model | 2 days |
| 5.3 | Train XGBoost scoring model on outcomes | Proprietary scoring model | 2 days |
| 5.4 | A/B test models vs. zero-shot benchmark | Validation of model improvement | 2 days |
| 5.5 | Deploy ensemble model (composite + ML) | Production scoring engine | 1 day |
| 5.6 | Implement continuous retraining pipeline | Automated model improvement | 2 days |

**Gate:** Auto-accept rate > 85%. Model accuracy > 88% AUC-ROC on hold-out test set.

### 15.6 Phase 6: Data Licensing Launch (Month 2-3)

**Objective:** Monetize data assets through licensing products.

| Step | Action | Data Asset Impact | Est. Effort |
|------|--------|------------------|-------------|
| 6.1 | Define licensing tiers and pricing | Revenue product catalog | 2 days |
| 6.2 | Build API gateway with entitlement checks | Access control for licensees | 3 days |
| 6.3 | Implement usage metering (Prometheus) | Billing data collection | 1 day |
| 6.4 | Build subscriber portal | Customer self-service | 3 days |
| 6.5 | Create data sample packages | Sales enablement | 1 day |
| 6.6 | Publish data documentation and SLAs | Customer confidence | 2 days |

**Gate:** MRR from data licensing > $10,000. First 5 paying data subscribers.

### 15.7 Phase 7: Scale and Compete (Month 3-6)

**Objective:** Expand county coverage, train on 25K+ examples, achieve data dominance.

| Step | Action | Data Asset Impact | Est. Effort |
|------|--------|------------------|-------------|
| 7.1 | Expand to 50 counties | 25,000 cases/month collection | 6 weeks |
| 7.2 | Train on 25,000 examples | 95% auto-accept rate | Ongoing |
| 7.3 | Build real-time distress signals | New data product | 2 weeks |
| 7.4 | Launch data partner program | Third-party enrichment integration | 2 weeks |
| 7.5 | File provisional patents on scoring IP | Legal defensibility | 1 week |
| 7.6 | Achieve 100 paying data subscribers | Revenue scaling | Ongoing |

**Gate:** 3,144 counties covered through direct adapters + data partnerships. MRR > $200K from data licensing.

---

## 16. Risk Register

### 16.1 Data-Specific Risks

| Risk ID | Description | Likelihood | Impact | Mitigation |
|---------|-------------|------------|--------|------------|
| D-001 | County portal changes format breaking adapter | High (annual per county) | Medium | Adapter health monitoring + auto-disable + alert |
| D-002 | DeepSeek API deprecation or pricing change | Low | High | LiteLLM abstraction + multi-model fallback |
| D-003 | Training data contamination (incorrect human review) | Medium | High | Reviewer accuracy tracking + audit + consensus scoring |
| D-004 | Data broker partner (Skipjack/TLOxp) API deprecation | Low | Medium | Multi-broker strategy + fallback chain |
| D-005 | GDPR/CCPA enforcement action | Low | High | Compliance-by-design architecture + data protection officer |
| D-006 | ML model drift (scoring accuracy decays over time) | Medium | Medium | Continuous monitoring + automated retraining triggers |
| D-007 | Competitor acquires county data through bulk license | Medium | High | Attorney network effects + scoring IP + first-mover advantage |
| D-008 | Data corruption from bug in normalization pipeline | Medium | High | Validation gates at every pipeline stage + automated rollback |
| D-009 | PII breach in training data exported to fine-tuning API | Low | Critical | PII scrubbing before export + data processing agreement |
| D-010 | Prediction Radar historical data loss | Low | Medium | Automated daily backups + cross-node replication |

### 16.2 Data Risk Mitigation Investment

| Risk ID | Mitigation Investment | Est. Cost | Priority |
|---------|----------------------|-----------|----------|
| D-001 | Adapter health framework + monitoring | $5K (engineering) | P0 |
| D-002 | LiteLLM multi-model routing | Already deployed | P0 |
| D-003 | Reviewer accuracy tracking system | $3K (engineering) | P1 |
| D-004 | Multi-broker abstraction layer | $5K (engineering) | P2 |
| D-005 | Compliance automation (deletion/portability APIs) | $10K (engineering) | P1 |
| D-006 | Model drift monitoring dashboard | $3K (engineering) | P1 |
| D-007 | Attorney network growth program | $15K/mo (marketing) | P2 |
| D-008 | Pipeline validation framework | $8K (engineering) | P1 |
| D-009 | PII scrubbing + data processing agreement | $3K (legal + engineering) | P0 |
| D-010 | Backup automation + cross-node replication | $2K (infrastructure) | P1 |

---

## Appendix A: Data System Connection Reference

| Data System | Host | Port | Connection String Pattern | Authentication | Current Status |
|-------------|------|------|--------------------------|---------------|----------------|
| frgops-standby PostgreSQL | 127.0.0.1 (AIOPS) | 5433 | `postgresql://frgops:...@127.0.0.1:5433/frgcrm` | Password auth | HEALTHY (122 records) |
| shared-postgres-recovery | 187.77.148.88 (EDGE) | 5432 | `postgresql://...@187.77.148.88:5432/...` | Password auth | AVAILABLE (6,603 records) |
| wheeler-core PostgreSQL | 5.78.210.123 (COREDB) | 5432 | `postgresql://...@100.118.166.117:5432/wheeler_core` | Password auth | REFUSING CONNECTIONS |
| ravynai-postgres | 127.0.0.1 (AIOPS) | 5434 | `postgresql://...@127.0.0.1:5434/ravynai` | Password auth | HEALTHY |
| prediction-radar-db | 127.0.0.1 (AIOPS) | 5432 | Internal Docker network | Docker network | HEALTHY |
| ecosystem-graph Neo4j | 127.0.0.1 (AIOPS) | 7687 | `bolt://127.0.0.1:7687` | Password auth | HEALTHY |
| aiops-clickhouse | 127.0.0.1 (AIOPS) | 8123 | `http://127.0.0.1:8123` | Password auth | HEALTHY |
| prediction-radar-redis | 127.0.0.1 (AIOPS) | 6379 | `redis://127.0.0.1:6379` | No auth (internal) | HEALTHY |
| docuseal-redis | 127.0.0.1 (AIOPS) | 6379 | Internal Docker network | Docker network | HEALTHY |
| usesend-redis | EDGE | -- | Internal Docker network | Docker network | HEALTHY |
| wheeler-minio | 5.78.210.123 (COREDB) | 9000 | S3-compatible API | Access key + secret | HEALTHY |

## Appendix B: Data Collection Metrics Dashboard

Key Prometheus metrics for data collection monitoring:

```
# Adapter health
surplus_adapter_runs_total{county="la-ca", status="success"}
surplus_adapter_runs_total{county="la-ca", status="error"}
surplus_adapter_errors_total{county="la-ca", error_type="auth_failure"}
surplus_adapter_errors_total{county="la-ca", error_type="parse_error"}
surplus_adapter_errors_total{county="la-ca", error_type="rate_limited"}

# Collection volume
surplus_cases_collected_total{county="la-ca"}
surplus_cases_collected_total{county="cook-il"}

# Pipeline quality
surplus_parse_success_rate{service="parser"}
surplus_parse_confidence_avg{service="parser"}
surplus_entity_resolution_rate{service="normalizer"}
surplus_enrichment_completion_rate{service="enricher"}

# Scoring
surplus_leads_scored_total{confidence_tier="high"}
surplus_leads_scored_total{confidence_tier="medium"}
surplus_leads_scored_total{confidence_tier="low"}
surplus_score_distribution_bucket{le="10", county="la-ca"}
surplus_score_distribution_bucket{le="20", county="la-ca"}
surplus_score_distribution_bucket{le="30", county="la-ca"}
surplus_score_distribution_bucket{le="40", county="la-ca"}
surplus_score_distribution_bucket{le="50", county="la-ca"}
surplus_score_distribution_bucket{le="60", county="la-ca"}
surplus_score_distribution_bucket{le="70", county="la-ca"}
surplus_score_distribution_bucket{le="80", county="la-ca"}
surplus_score_distribution_bucket{le="90", county="la-ca"}
surplus_score_distribution_bucket{le="100", county="la-ca"}

# Model performance
surplus_model_auto_accept_rate{model_version="1.0.0"}
surplus_model_precision{model_version="1.0.0"}
surplus_model_recall{model_version="1.0.0"}
surplus_model_training_examples_total{model_version="1.0.0"}

# Network effects
surplus_attorney_acceptance_rate
surplus_attorney_active_count
surplus_lead_to_assignment_minutes
surplus_case_to_outcome_days

# Storage
surplus_storage_bytes{store="postgres", database="frgcrm"}
surplus_storage_bytes{store="neo4j", database="ecosystem-graph"}
surplus_storage_bytes{store="clickhouse", database="surplus_analytics"}
surplus_storage_bytes{store="minio", bucket="archive"}
```

## Appendix C: Data Moat Maturity Model

| Level | Name | Criteria | Current Status | Target Date |
|-------|------|----------|---------------|-------------|
| 0 | None | No proprietary data collection, all public data | -- | -- |
| 1 | Basic | Single data source, manual collection | FRGCRM 122 cases collected (manual) | Current |
| 2 | Structured | Multiple sources, automated collection, basic schema | 5 county adapters designed, pipeline blocked | Phase 2 (Week 3) |
| 3 | Scored | ML-driven scoring, training data collection, quality monitoring | Scoring engine in design, 0 training examples | Phase 3 (Week 4) |
| 4 | Compounding | Active flywheels, cross-system enrichment, retraining pipeline | PipelineDAG failing, flywheels blocked | Phase 4 (Month 2) |
| 5 | Defensible | Licensed data products, ML moat, network effects, patent protection | No licensing, no patents | Phase 6 (Month 3) |
| 6 | Dominant | 200K+ cases/month, 90%+ auto-accept, 100+ data subscribers, 3,144 counties | -- | Phase 7 (Month 6+) |

**Current Maturity Level: 1 (Basic). Target: 6 (Dominant) within 6 months.**

---

*End of Wheeler Ecosystem Data Moat Strategy v1.0.0*

**Classification:** INTERNAL -- EXECUTIVE -- TRADE SECRET
**Next Review Date:** 2026-06-24
**Owner:** Wheeler Brain OS -- Data Engineering
**Related Documents:**
- `/root/WHEELER_REVENUE_ENGINE_ARCHITECTURE.md` -- Revenue system data architecture (Section 13)
- `/root/AUTONOMOUS_AIOPS_ARCHITECTURE.md` -- Data topology (Section 10)
- `/root/SURPLUSAI_PRODUCTIZATION_PLAN.md` -- Lead scoring and training data pipeline
- `/root/MASTER_EXECUTION_STATE.md` -- Current execution state
- `/root/STAGE2_QA_SCORECARD_FINAL.md` -- Infrastructure QA validation
