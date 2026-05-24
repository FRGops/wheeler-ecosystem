# Attorney Marketplace Architecture — Wheeler Ecosystem

**Classification:** EXECUTIVE CONFIDENTIAL
**Version:** 1.0
**Date:** 2026-05-24
**Ecosystem Context:** Stage 2 Hardening Complete (QA Scorecard 100/100 A+)
**Author:** Wheeler Autonomous Enforcement Agent — Attorney Marketplace Division

---

## 1. Executive Summary

The Wheeler ecosystem generates surplus fund leads through SurplusAI, Prediction Radar, and Chatwoot, then routes claimants to attorneys who recover funds on a contingency basis. Currently, four attorneys (Bigham, Morris, Farah, Walker) are manually configured in FRGCRM, and assignment is handled by human operators with no automated capacity tracking, performance scoring, or routing logic. PipelineDAG contains an AttorneyMatcher stage that is broken and non-functional.

This document defines the complete architecture for an automated attorney marketplace spanning attorney onboarding, state licensing verification, intelligent routing, revenue sharing, performance scoring, document workflow automation, and marketplace governance. The marketplace transforms attorney management from a manual bottleneck into a scalable, AI-powered matching engine capable of supporting hundreds of attorneys across all 50 states.

**Strategic Impact:**
- Current attorney capacity: 4 attorneys, manual assignment, <50 cases/month
- Phase 1 target capacity: 20 attorneys, semi-automated routing, 200+ cases/month
- Full build target capacity: 200+ attorneys, fully automated marketplace, 2000+ cases/month
- Revenue multiplier: Each additional qualified attorney increases addressable claim volume proportionally

---

## 2. System Architecture Overview

### 2.1 High-Level Architecture

```
                           ┌─────────────────────────────────┐
                           │         CLOUDFLARE               │
                           │   fundsrecoverygroup.com/api/*   │
                           └────────────┬────────────────────┘
                                        │
                                   ┌────▼────┐
                                   │ TRAEFIK  │
                                   │ (EDGE)   │
                                   └────┬────┘
                                        │
              ┌─────────────────────────┼─────────────────────────┐
              │                         │                         │
         ┌────▼────┐             ┌──────▼──────┐          ┌──────▼──────┐
         │FRGCRM   │             │ AIOPS NODE  │          │ COREDB NODE │
         │API+Agent│             │  (Hetzner)  │          │  (Hetzner)  │
         │ :8082   │             │             │          │             │
         └────┬────┘             │ ┌─────────┐ │          │ ┌─────────┐ │
              │                  │ │LiteLLM  │ │          │ │Postgres │ │
         ┌────▼────┐             │ │ :4049   │ │          │ │ :5432   │ │
         │Docuseal │             │ └─────────┘ │          │ └─────────┘ │
         │ :3010   │             │ ┌─────────┐ │          │ ┌─────────┐ │
         └─────────┘             │ │DeepSeek │ │          │ │ Redis   │ │
                                 │ │API      │ │          │ │ :6379   │ │
         ┌──────────────┐        │ └─────────┘ │          │ └─────────┘ │
         │ Attorney     │◄──────►│ ┌─────────┐ │          │ ┌─────────┐ │
         │ Marketplace  │        │ │n8n      │ │          │ │MinIO    │ │
         │ Service      │        │ │ :5678   │ │          │ │ :9000   │ │
         │ (NEW)        │        │ └─────────┘ │          │ └─────────┘ │
         └──────┬───────┘       │ ┌─────────┐ │          └──────────────┘
                │               │ │Discord  │ │
                │               │ │Webhooks │ │
                │               │ └─────────┘ │
                │               │ ┌─────────┐ │
                │               │ │Temporal │ │
                │               │ │ :7233   │ │
                │               │ └─────────┘ │
                │               └─────────────┘
                │
          ┌─────▼──────────────────────────────────────┐
          │           TAILSCALE MESH                    │
          │    100.x.x.x — Secure Internal Routing      │
          └─────────────────────────────────────────────┘
```

### 2.2 Service Placement

| Service | Node | Port | PM2/Docker | Dependencies |
|---------|------|------|-----------|-------------|
| Attorney Marketplace API | AIOPS | 8120 | PM2 | COREDB:5432, LiteLLM:4049, DeepSeek API |
| Attorney Frontend (Dashboard) | EDGE | 8121 | PM2 | Marketplace API:8120, Docuseal:3010 |
| Attorney Onboarding Worker | AIOPS | 8122 | PM2 | COREDB:5432, SendGrid SMTP, Docuseal:3010 |
| License Verification Worker | AIOPS | 8123 | PM2 | DeepSeek API, LiteLLM:4049, COREDB:5432 |
| Revenue Share Engine | AIOPS | 8124 | PM2 | COREDB:5432, Stripe API |
| Document Automation Worker | AIOPS | 8125 | PM2 | Docuseal:3010, COREDB:5432 |
| Communications Worker | AIOPS | 8126 | PM2 | SendGrid SMTP, Discord Webhooks |
| n8n Workflow Triggers | AIOPS | (n8n) | Docker | Marketplace API:8120 |

### 2.3 Database Placement Strategy

The attorney marketplace requires its own schema within the COREDB PostgreSQL instance once it is operational. During Phase 1, a local PostgreSQL instance on AIOPS serves as the primary data store to avoid the COREDB connectivity issue. Data migration to COREDB occurs as part of Phase 2 handoff.

**Phase 1 (Local AIOPS PostgreSQL):**
- Database: `attorney_marketplace`
- User: `attorney_mkt`
- Backup included in standard AIOPS pg_dump rotation

**Phase 2+ (COREDB PostgreSQL):**
- Database: `attorney_marketplace` (migrated)
- Schema: `marketplace` — all tables under dedicated schema
- Connection via COREDB_RW credentials (attorney MKT read/write pool)

---

## 3. Database Schema

### 3.1 Core Tables

```sql
-- Schema: marketplace (Phase 2+) / public (Phase 1)

-- ============================================================
-- ATTORNEY ONBOARDING & PROFILES
-- ============================================================

CREATE TABLE marketplace.attorneys (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id                 VARCHAR(64) UNIQUE,          -- Stripe Connect account ID or similar
    prefix                      VARCHAR(16),                 -- Mr., Ms., Dr., etc.
    first_name                  VARCHAR(128) NOT NULL,
    middle_name                 VARCHAR(128),
    last_name                   VARCHAR(128) NOT NULL,
    suffix                      VARCHAR(32),                 -- Jr., III, etc.
    firm_name                   VARCHAR(256),
    firm_ein                    VARCHAR(16),                 -- Employer Identification Number
    firm_website                VARCHAR(512),
    firm_address_line1          VARCHAR(256),
    firm_address_line2          VARCHAR(256),
    firm_city                   VARCHAR(128),
    firm_state                  CHAR(2),
    firm_zip                    VARCHAR(16),
    firm_phone                  VARCHAR(32),
    firm_email                  VARCHAR(256) NOT NULL,
    personal_email              VARCHAR(256),
    phone                       VARCHAR(32),
    avatar_url                  VARCHAR(512),
    bio                         TEXT,
    years_of_experience         SMALLINT,
    law_school                  VARCHAR(256),
    onboarding_status           VARCHAR(32) NOT NULL DEFAULT 'draft',
        -- draft | pending_verification | verified | active | suspended | offboarded
    onboarding_completed_at     TIMESTAMPTZ,
    terms_accepted_at           TIMESTAMPTZ,
    revenue_share_agreement_id  UUID REFERENCES docuseal.documents(id),
    malpractice_insurance_provider  VARCHAR(256),
    malpractice_policy_number       VARCHAR(128),
    malpractice_coverage_amount     NUMERIC(12,2),
    malpractice_expiration_date     DATE,
    malpractice_verified            BOOLEAN DEFAULT FALSE,
    background_check_status      VARCHAR(32) DEFAULT 'not_started',
        -- not_started | in_progress | cleared | flagged
    payment_processing_enabled   BOOLEAN DEFAULT FALSE,
    stripe_connect_account_id    VARCHAR(64),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by                  UUID REFERENCES admin.users(id),
    updated_by                  UUID REFERENCES admin.users(id)
);

CREATE TABLE marketplace.attorney_bar_licenses (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attorney_id                 UUID NOT NULL REFERENCES marketplace.attorneys(id) ON DELETE CASCADE,
    state                       CHAR(2) NOT NULL,
    bar_number                  VARCHAR(64) NOT NULL,
    license_type                VARCHAR(64) DEFAULT 'active',
        -- active | inactive | retired | suspended | disbarred | deceased
    verification_status         VARCHAR(32) DEFAULT 'unverified',
        -- unverified | pending | verified | failed | expired
    verification_source         VARCHAR(64),  -- statebar.gov API or manual
    verified_at                 TIMESTAMPTZ,
    verified_by                 UUID REFERENCES admin.users(id),
    next_verification_due       DATE,
    last_verification_result    JSONB,
    pro_hac_vice_eligible       BOOLEAN DEFAULT FALSE,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(attorney_id, state)
);

CREATE TABLE marketplace.attorney_practice_areas (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attorney_id                 UUID NOT NULL REFERENCES marketplace.attorneys(id) ON DELETE CASCADE,
    practice_area               VARCHAR(64) NOT NULL,
        -- surplus_funds_collection | foreclosure | probate | tax_deed | bankruptcy | civil_litigation | real_estate
    expertise_level             VARCHAR(32) DEFAULT 'intermediate',
        -- beginner | intermediate | expert
    years_practicing            SMALLINT,
    counties                    TEXT[],       -- Array of county names where they practice this area
    states                      CHAR(2)[],    -- States where they practice this area
    is_primary                  BOOLEAN DEFAULT FALSE,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(attorney_id, practice_area, state)
);

CREATE TABLE marketplace.attorney_availability (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attorney_id                 UUID NOT NULL REFERENCES marketplace.attorneys(id) ON DELETE CASCADE,
    status                      VARCHAR(32) NOT NULL DEFAULT 'accepting',
        -- accepting | at_capacity | paused | vacation | unavailable
    max_active_cases            INTEGER NOT NULL DEFAULT 10,
    current_active_cases        INTEGER NOT NULL DEFAULT 0,
    max_monthly_intake          INTEGER NOT NULL DEFAULT 5,
    current_monthly_intake      INTEGER NOT NULL DEFAULT 0,
    preferred_communication     VARCHAR(32) DEFAULT 'email',
        -- email | phone | portal | sms
    available_days              SMALLINT[],  -- Array of day-of-week (0=Sun, 6=Sat)
    available_hours_start       TIME,        -- e.g. 09:00
    available_hours_end         TIME,        -- e.g. 17:00
    timezone                    VARCHAR(64) DEFAULT 'America/New_York',
    notes                       TEXT,
    effective_from              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_until             TIMESTAMPTZ,  -- NULL = indefinite
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(attorney_id, effective_from)
);

-- ============================================================
-- CASE ASSIGNMENT & ROUTING
-- ============================================================

CREATE TABLE marketplace.case_assignments (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    frgcrm_case_id              UUID,          -- Link to FRGCRM case/lead record (nullable until FRGCRM fixed)
    surplusai_claim_id          UUID,          -- Link to SurplusAI claim (nullable)
    attorney_id                 UUID REFERENCES marketplace.attorneys(id),
    assigned_by                 UUID REFERENCES admin.users(id),   -- NULL if auto-assigned
    assignment_method           VARCHAR(32) NOT NULL,
        -- manual | rule_based | ai_ranked | round_robin | performance_weighted | reassignment
    routing_score               NUMERIC(5,2),  -- AI routing confidence score 0-100
    status                      VARCHAR(32) NOT NULL DEFAULT 'pending',
        -- pending | offered | accepted | declined | timed_out | active | completed | reassigned | cancelled
    offered_at                  TIMESTAMPTZ,
    accepted_at                 TIMESTAMPTZ,
    declined_at                 TIMESTAMPTZ,
    decline_reason              TEXT,
    timeout_at                  TIMESTAMPTZ,
    timeout_duration_hours      INTEGER DEFAULT 48,
    active_at                   TIMESTAMPTZ,
    completed_at                TIMESTAMPTZ,
    reassigned_from             UUID REFERENCES marketplace.case_assignments(id),
    reassigned_to               UUID REFERENCES marketplace.case_assignments(id),
    reassignment_reason         TEXT,
    locked_by                   UUID REFERENCES admin.users(id),  -- Manual override locks assignment
    locked_at                   TIMESTAMPTZ,
    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE marketplace.assignment_candidates (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id               UUID NOT NULL REFERENCES marketplace.case_assignments(id) ON DELETE CASCADE,
    attorney_id                 UUID NOT NULL REFERENCES marketplace.attorneys(id),
    rank                        SMALLINT NOT NULL,           -- 1 = top candidate
    score                       NUMERIC(5,2),                 -- Composite score 0-100
    breakdown                   JSONB,                        -- Score breakdown by factor
        -- {
        --   "license_match": 100,
        --   "county_experience": 85,
        --   "case_type_match": 90,
        --   "performance_score": 78,
        --   "capacity_score": 95,
        --   "location_score": 80,
        --   "recency_score": 70
        -- }
    selection_method            VARCHAR(32),                  -- How this candidate was selected
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- PERFORMANCE SCORING
-- ============================================================

CREATE TABLE marketplace.performance_scores (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attorney_id                 UUID NOT NULL REFERENCES marketplace.attorneys(id) ON DELETE CASCADE,
    score_date                  DATE NOT NULL DEFAULT CURRENT_DATE,
    period_type                 VARCHAR(16) NOT NULL DEFAULT 'rolling_90',
        -- rolling_30 | rolling_90 | rolling_365 | all_time | quarterly | yearly

    -- Component scores (0-100)
    case_acceptance_rate        NUMERIC(5,2),    -- Percentage of offered cases accepted
    time_to_first_contact       NUMERIC(5,2),    -- Average hours to first contact (lower is better, inverted)
    case_completion_rate        NUMERIC(5,2),    -- Percentage of active cases completed
    average_recovery_percentage NUMERIC(5,2),    -- Average % of claim value recovered
    client_satisfaction_rating  NUMERIC(3,2),    -- 1.0-5.0 from client surveys
    document_accuracy_rate      NUMERIC(5,2),    -- % of documents filed without errors
    court_deadline_compliance   NUMERIC(5,2),    -- % of deadlines met

    -- Composite
    composite_score             NUMERIC(5,2) GENERATED ALWAYS AS (
        CASE
            WHEN case_acceptance_rate IS NULL THEN NULL
            ELSE (
                COALESCE(case_acceptance_rate, 0) * 0.15 +
                COALESCE(time_to_first_contact, 0) * 0.10 +
                COALESCE(case_completion_rate, 0) * 0.20 +
                COALESCE(average_recovery_percentage, 0) * 0.25 +
                COALESCE(client_satisfaction_rating, 0) * 20 * 0.10 +
                COALESCE(document_accuracy_rate, 0) * 0.10 +
                COALESCE(court_deadline_compliance, 0) * 0.10
            )
        END
    ) STORED,

    tier                        VARCHAR(16) GENERATED ALWAYS AS (
        CASE
            WHEN composite_score >= 90 THEN 'PLATINUM'
            WHEN composite_score >= 75 THEN 'GOLD'
            WHEN composite_score >= 60 THEN 'SILVER'
            WHEN composite_score IS NOT NULL THEN 'BRONZE'
            ELSE 'UNRATED'
        END
    ) STORED,

    cases_in_period             INTEGER DEFAULT 0,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(attorney_id, score_date, period_type)
);

-- ============================================================
-- REVENUE SHARING
-- ============================================================

CREATE TABLE marketplace.revenue_share_agreements (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attorney_id                 UUID NOT NULL REFERENCES marketplace.attorneys(id),
    agreement_type              VARCHAR(32) NOT NULL DEFAULT 'standard',
        -- standard | per_case | per_case_type | tiered
    default_split_percentage    NUMERIC(5,2) NOT NULL,       -- Firm's share (e.g. 70.00 = 70% to attorney)
    frg_split_percentage        NUMERIC(5,2) NOT NULL,       -- FRG's share (e.g. 30.00)
    docuseal_document_id        UUID,                         -- Signed agreement in Docuseal
    effective_date              DATE NOT NULL DEFAULT CURRENT_DATE,
    expiration_date             DATE,
    termination_date            DATE,
    termination_reason          VARCHAR(256),
    status                      VARCHAR(32) DEFAULT 'active',
        -- draft | active | terminated | expired
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE marketplace.revenue_share_case_overrides (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agreement_id                UUID NOT NULL REFERENCES marketplace.revenue_share_agreements(id),
    case_assignment_id          UUID NOT NULL REFERENCES marketplace.case_assignments(id),
    practice_area               VARCHAR(64),
    override_split_percentage   NUMERIC(5,2),   -- Per-case override of default split
    override_frg_split          NUMERIC(5,2),
    reason                      TEXT,
    approved_by                 UUID REFERENCES admin.users(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE marketplace.revenue_share_payouts (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attorney_id                 UUID NOT NULL REFERENCES marketplace.attorneys(id),
    agreement_id                UUID NOT NULL REFERENCES marketplace.revenue_share_agreements(id),
    case_assignment_id          UUID REFERENCES marketplace.case_assignments(id),
    payout_type                 VARCHAR(32) NOT NULL DEFAULT 'case_completion',
        -- case_completion | monthly_batch | bonus | adjustment
    gross_amount                NUMERIC(12,2) NOT NULL,
    frg_fee_amount              NUMERIC(12,2) NOT NULL,
    attorney_amount             NUMERIC(12,2) NOT NULL,
    stripe_transfer_id          VARCHAR(128),
    stripe_payout_id            VARCHAR(128),
    status                      VARCHAR(32) NOT NULL DEFAULT 'calculated',
        -- calculated | approved | paid | failed | reversed
    calculated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_at                 TIMESTAMPTZ,
    paid_at                     TIMESTAMPTZ,
    payment_method              VARCHAR(32) DEFAULT 'stripe_connect',
    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- DOCUMENT WORKFLOW
-- ============================================================

CREATE TABLE marketplace.case_documents (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_assignment_id          UUID NOT NULL REFERENCES marketplace.case_assignments(id),
    document_type               VARCHAR(64) NOT NULL,
        -- representation_agreement | retainer | court_filing | demand_letter | settlement | release | other
    docuseal_template_id        UUID,         -- Docuseal template used
    docuseal_submission_id      UUID,         -- Docuseal submission tracking
    status                      VARCHAR(32) NOT NULL DEFAULT 'pending',
        -- pending | generated | sent | signed | completed | rejected | void
    generated_at                TIMESTAMPTZ,
    sent_at                     TIMESTAMPTZ,
    signed_by_claimant_at       TIMESTAMPTZ,
    signed_by_attorney_at       TIMESTAMPTZ,
    completed_at                TIMESTAMPTZ,
    document_url                VARCHAR(1024),
    version                     SMALLINT DEFAULT 1,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- COMMUNICATIONS
-- ============================================================

CREATE TABLE marketplace.communication_log (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_assignment_id          UUID REFERENCES marketplace.case_assignments(id),
    attorney_id                 UUID NOT NULL REFERENCES marketplace.attorneys(id),
    direction                   VARCHAR(8) NOT NULL,          -- outbound | inbound
    channel                     VARCHAR(32) NOT NULL,
        -- email | portal_message | sms | phone | discord | system_notification
    subject                     VARCHAR(512),
    body                        TEXT,
    status                      VARCHAR(32) DEFAULT 'sent',
        -- queued | sent | delivered | read | failed | bounced
    sendgrid_message_id         VARCHAR(128),                  -- If sent via SendGrid
    external_ref                VARCHAR(256),
    sent_at                     TIMESTAMPTZ,
    read_at                     TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- MARKETPLACE GOVERNANCE & AUDIT
-- ============================================================

CREATE TABLE marketplace.audit_log (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type                 VARCHAR(64) NOT NULL,
    entity_id                   UUID NOT NULL,
    action                      VARCHAR(64) NOT NULL,
    changes                     JSONB,                         -- {field: {old: ..., new: ...}}
    performed_by                UUID,                          -- NULL = system action
    performed_by_type           VARCHAR(32) DEFAULT 'admin',   -- admin | system | attorney | claimant
    ip_address                  INET,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE marketplace.quality_reviews (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attorney_id                 UUID NOT NULL REFERENCES marketplace.attorneys(id),
    review_type                 VARCHAR(32) NOT NULL,
        -- performance_improvement_plan | compliance_review | ethics_review | complaint_investigation
    status                      VARCHAR(32) NOT NULL DEFAULT 'open',
        -- open | in_progress | resolved | escalated
    severity                    VARCHAR(16) DEFAULT 'medium',
        -- low | medium | high | critical
    description                 TEXT NOT NULL,
    findings                    TEXT,
    resolution                  TEXT,
    action_taken                VARCHAR(64),
        -- warning | pip | suspension | offboarding | no_action
    action_effective_date       DATE,
    reviewed_by                 UUID REFERENCES admin.users(id),
    reviewed_at                 TIMESTAMPTZ,
    resolved_at                 TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_attorney_status ON marketplace.attorneys(onboarding_status);
CREATE INDEX idx_attorney_bar_state ON marketplace.attorney_bar_licenses(state, verification_status);
CREATE INDEX idx_attorney_avail_status ON marketplace.attorney_availability(status);
CREATE INDEX idx_case_assignments_attorney ON marketplace.case_assignments(attorney_id, status);
CREATE INDEX idx_case_assignments_status ON marketplace.case_assignments(status, offered_at);
CREATE INDEX idx_performance_attorney_date ON marketplace.performance_scores(attorney_id, score_date DESC);
CREATE INDEX idx_payouts_attorney_status ON marketplace.revenue_share_payouts(attorney_id, status);
CREATE INDEX idx_audit_entity ON marketplace.audit_log(entity_type, entity_id, created_at DESC);
CREATE INDEX idx_comm_log_attorney ON marketplace.communication_log(attorney_id, created_at DESC);
```

### 3.2 Supporting Tables for Phase 1 Operations

```sql
-- Simple state bar verification cache (Phase 1, replace with API integration in Phase 2)
CREATE TABLE marketplace.state_bar_lookup_cache (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    state                       CHAR(2) NOT NULL,
    bar_number                  VARCHAR(64) NOT NULL,
    lookup_date                 DATE NOT NULL DEFAULT CURRENT_DATE,
    result_status               VARCHAR(32),                   -- found | not_found | error
    attorney_name               VARCHAR(256),                  -- Name returned from lookup
    license_status              VARCHAR(64),                   -- active/inactive etc.
    raw_response                JSONB,
    looked_up_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(state, bar_number)
);

-- Conflict of interest tracking (simple version)
CREATE TABLE marketplace.conflict_of_interest (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attorney_id                 UUID NOT NULL REFERENCES marketplace.attorneys(id),
    claimant_name               VARCHAR(256),
    claimant_ssn_hash          VARCHAR(128),                   -- SHA-256 hash of SSN, never raw
    property_address            VARCHAR(512),
    property_county             VARCHAR(128),
    property_state              CHAR(2),
    case_number                 VARCHAR(64),
    relationship_type           VARCHAR(64),                   -- former_client | family | business | adverse_party
    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## 4. API Design

### 4.1 RESTful API Endpoints

Base URL: `https://fundsrecoverygroup.com/api/attorney-marketplace/v1`
Internal: `http://127.0.0.1:8120/api/v1`

#### 4.1.1 Attorney Onboarding

```
POST   /api/v1/attorneys/register
           -- Self-service registration (public)
           Body: { first_name, last_name, firm_name, firm_email, phone, bar_licenses: [{state, bar_number}], practice_areas, terms_accepted }
           Response: { id, onboarding_url, docuseal_agreement_url }
           Notes: Creates attorney in 'draft' status, generates Docuseal agreement, sends verification email

POST   /api/v1/attorneys/{id}/verify-bar-license
           -- Trigger bar license verification
           Response: { verification_status, results: [{state, status, verified_name}] }

POST   /api/v1/attorneys/{id}/verify-malpractice
           -- Submit malpractice insurance info
           Body: { provider, policy_number, coverage_amount, expiration_date, document_url }

POST   /api/v1/attorneys/{id}/complete-onboarding
           -- Admin finalizes onboarding after verification
           Response: { attorney_id, status: 'active', welcome_email_sent }

GET    /api/v1/attorneys/{id}
           -- Full attorney profile
           Response: { id, name, firm, bar_licenses, practice_areas, availability, performance, revenue }

PATCH  /api/v1/attorneys/{id}
           -- Update attorney profile (attorney or admin)
           Body: { fields to update }

GET    /api/v1/attorneys
           -- List/search attorneys (admin)
           Query: status, state, practice_area, county, performance_tier, page, limit
```

#### 4.1.2 Assignment Routing

```
POST   /api/v1/assignments/route
           -- Route a case to the best attorney
           Body: { case_id, state, county, practice_area, claim_amount, claimant_name, language_preference }
           Response: { assignment_id, attorney_id, attorney_name, score, breakdown, offered_at }
           Notes: Uses AI routing engine (DeepSeek via LiteLLM) if available, falls back to rule-based

GET    /api/v1/assignments/{id}
           -- Get assignment details
           Response: { case, attorney, status, timeline, documents }

POST   /api/v1/assignments/{id}/accept
           -- Attorney accepts assignment (via portal or email link)
           Response: { status: 'active', next_steps }

POST   /api/v1/assignments/{id}/decline
           -- Attorney declines with reason
           Body: { reason, suggested_alternative? }
           Response: { status: 'declined', reassignment_initiated }

POST   /api/v1/assignments/{id}/reassign
           -- Admin reassignment
           Body: { new_attorney_id, reason }
           Response: { new_assignment_id }

POST   /api/v1/assignments/{id}/timeout
           -- System-initiated timeout (cron trigger)
           Response: { status: 'timed_out', reassignment_triggered }

POST   /api/v1/assignments/{id}/manual-override
           -- Admin locks assignment to specific attorney
           Body: { attorney_id, reason }
           Response: { assignment_id, locked: true }

GET    /api/v1/assignments/candidates
           -- Preview top candidates for a case without creating assignment
           Query: state, county, practice_area, claim_amount
           Response: { candidates: [{ attorney_id, name, score, breakdown, capacity }] }
```

#### 4.1.3 Capacity & Availability

```
GET    /api/v1/attorneys/{id}/availability
           -- Current availability
           Response: { status, max_cases, current_cases, next_available }

PATCH  /api/v1/attorneys/{id}/availability
           -- Update availability
           Body: { status, max_active_cases, preferred_communication, available_hours }
           Notes: Attorneys can self-update their availability

GET    /api/v1/attorneys/available
           -- Find available attorneys by criteria
           Query: state, county, practice_area, max_cases_load, page, limit
           Response: { attorneys: [...], total_available }
```

#### 4.1.4 Revenue Sharing

```
GET    /api/v1/revenue/attorneys/{id}/summary
           -- Revenue summary for attorney
           Query: period (current_month | ytd | all_time)
           Response: { gross_revenue, frg_fees, attorney_net, pending_payouts, paid_payouts }

GET    /api/v1/revenue/attorneys/{id}/payouts
           -- Payout history
           Query: status, date_from, date_to, page, limit

POST   /api/v1/revenue/payouts/{id}/approve
           -- Admin approves pending payout
           Response: { status: 'approved', stripe_transfer_initiated }

POST   /api/v1/revenue/payouts/{id}/process
           -- Trigger payment via Stripe Connect
           Response: { status: 'paid', stripe_transfer_id, paid_at }

GET    /api/v1/revenue/summary
           -- FRG revenue summary (admin)
           Query: date_from, date_to, group_by (attorney | practice_area | state)
           Response: { total_gross, total_frg_revenue, total_attorney_payouts, breakdown: [...] }
```

#### 4.1.5 Document Automation

```
POST   /api/v1/documents/generate
           -- Generate document from template via Docuseal
           Body: { case_assignment_id, document_type, template_id, template_data: {...} }
           Response: { document_id, docuseal_submission_id, url }

GET    /api/v1/documents/case/{case_assignment_id}
           -- All documents for a case
           Response: { documents: [{ type, status, url, signed_date }] }

POST   /api/v1/documents/{id}/send-for-signature
           -- Send document via Docuseal
           Body: { signer_email, signer_name, message }
           Response: { submission_id, status: 'sent' }
```

#### 4.1.6 Performance & Analytics

```
GET    /api/v1/performance/attorneys/{id}
           -- Attorney performance dashboard data
           Query: period (rolling_30 | rolling_90 | rolling_365)
           Response: { composite, components, tier, trend, peer_comparison }

GET    /api/v1/performance/leaderboard
           -- Attorney ranking
           Query: practice_area, state, limit
           Response: { leaderboard: [{ rank, attorney_id, name, score, tier, cases }] }

POST   /api/v1/performance/attorneys/{id}/refresh
           -- Recalculate performance scores
           Response: { new_scores, computed_from_case_count }
```

#### 4.1.7 Communications

```
POST   /api/v1/communications/send
           -- Send message to attorney
           Body: { attorney_id, case_assignment_id?, channel, subject, body }
           Response: { message_id, status, channel_specific_ids }

GET    /api/v1/communications/attorney/{id}
           -- Get communication history
           Query: case_assignment_id?, channel?, page, limit
```

#### 4.1.8 Governance

```
POST   /api/v1/governance/quality-review
           -- Create quality review
           Body: { attorney_id, review_type, severity, description }
           Response: { review_id, status: 'open' }

PATCH  /api/v1/governance/quality-review/{id}
           -- Update review with findings/resolution
           Body: { findings, resolution, action_taken, action_effective_date }

POST   /api/v1/governance/attorneys/{id}/suspend
           -- Suspend attorney
           Body: { reason, effective_date, duration? }
           Response: { attorney_id, status: 'suspended' }

POST   /api/v1/governance/attorneys/{id}/offboard
           -- Offboard attorney
           Body: { reason, effective_date, reassign_cases_to }
           Response: { attorney_id, status: 'offboarded', reassigned_case_count }
```

### 4.2 Authentication & Authorization

| Role | Scope | Auth Method |
|------|-------|-------------|
| Attorney (self) | Own profile, own cases, own revenue | JWT via portal login (email magic link) |
| FRG Admin | All attorneys, assignments, governance | JWT via FRGCRM admin auth |
| System (internal) | All API endpoints | API key via Tailscale (internal network only) |
| Public | Registration only | Rate-limited, no auth required |

---

## 5. AI-Powered Routing Engine

### 5.1 Architecture

The intelligent routing engine operates as a DeepSeek-powered agent (via LiteLLM proxy at 127.0.0.1:4049) that scores and ranks attorney candidates for each incoming case.

```
Incoming Case
     │
     ▼
┌─────────────────────┐
│ Rule-Based Filter   │─── Eliminate: wrong state, wrong license, at capacity,
│ (Pre-filter)        │    not in county, paused availability, conflict of interest
└─────────┬───────────┘
          │ (qualified candidates)
          ▼
┌─────────────────────┐
│ AI Scoring Agent    │─── DeepSeek call with structured prompt:
│ (DeepSeek via       │    "Score each candidate based on:
│  LiteLLM :4049)     │     - Performance history (weight: 25%)
          │           │     - Practice area expertise (weight: 20%)
          ▼           │     - County experience count (weight: 15%)
┌─────────────────────┐    - Recovery track record (weight: 20%)
│ Weighted Scorer     │    - Current capacity load (weight: 10%)
│ (Local fallback)    │    - Recency of assignment (weight: 10%)"
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ Assignment Creator  │─── Create case_assignment + assignment_candidates
└─────────┬───────────┘    rows, update attorney_availability counters
          │
          ▼
┌─────────────────────┐
│ Notification        │─── Send offer via attorney's preferred channel
│ Dispatcher          │    (email via SendGrid, portal notification, or both)
└─────────────────────┘
```

### 5.2 AI Prompt Template

```
SYSTEM: You are an attorney routing specialist for Funds Recovery Group.
Score each candidate on a 0-100 scale for the given surplus funds case.

CONTEXT:
- Case: {claimant_name} in {county}, {state}
- Practice area: {practice_area}
- Claim amount: ${claim_amount}
- Language: {language}

CANDIDATES:
{candidate_list with fields: name, performance_scores, practice_areas, county_experience, capacity}

SCORING WEIGHTS:
- License match (PASS/FAIL): If fail, score = 0
- Performance history: 25%
- Practice area match: 20%
- County experience: 15%
- Recovery track record: 20%
- Capacity headroom: 10%
- Assignment recency (prefer less recently assigned): 10%

OUTPUT JSON:
{{
  "candidates": [
    {{
      "attorney_id": "...",
      "composite_score": 87,
      "breakdown": {{
        "license_match": 100,
        "performance_history": 82,
        "practice_area_match": 90,
        "county_experience": 75,
        "recovery_track_record": 88,
        "capacity_headroom": 95,
        "recency_bonus": 80
      }},
      "reasoning": "Strong match: 8 years experience in {county} foreclosure cases,
                    platinum tier with 92% completion rate, currently at 4/10 cases"
    }}
  ]
}}
```

### 5.3 Fallback Chain

| Priority | Method | Trigger | Performance |
|----------|--------|---------|-------------|
| 1 | AI DeepSeek routing | LiteLLM responds within 10s | Best quality, ~2s response |
| 2 | Rule-based weighted scoring | AI unavailable or timeout | Good quality, instant |
| 3 | Round-robin performance-weighted | No qualified candidates from rules | Fair distribution |
| 4 | Manual assignment by admin | All automated methods fail | Human judgment |

---

## 6. State Licensing Intelligence

### 6.1 Integration Architecture

State bar license verification operates in three tiers, with increasing sophistication across phases.

**Phase 1: Manual + Semi-Automated**
- Attorney submits bar number during registration
- Admin verifies manually via state bar websites
- Verification status tracked in `attorney_bar_licenses` table
- Estimated 15 minutes per verification

**Phase 2: Automated Web Scraping**
- LandingAI-style scraper agents (reuse SurplusAI scraper pattern)
- Target known state bar lookup URLs for all 50 states
- Cache results in `state_bar_lookup_cache` table
- Re-verify every 90 days via cron job
- Coverage: states with public lookup tools (approximately 42 states)

```python
# Pseudocode for license verification worker
STATE_BAR_URLS = {
    'AL': 'https://www.alabar.org/...',
    'AK': 'https://www.akbar.org/...',
    # ... all 50 states
}

def verify_license(state, bar_number):
    url = STATE_BAR_URLS[state]
    # Scrape bar lookup page, submit bar_number
    # Parse response for attorney name + license status
    # Return {found: bool, name: str, status: str}
```

**Phase 3: API Integration (Preferred)**
- Direct API integration where available (e.g., Texas Bar, California Bar)
- Third-party services for comprehensive coverage:
    - Janis (janislegal.com) — multi-state API
    - State Bar APIs (approximately 15 states offer direct API access)
- Real-time verification on registration + scheduled daily reverification
- Webhook hooks for license status changes where available

### 6.2 License Verification Schedule

| Frequency | Action | Responsible Service |
|-----------|--------|-------------------|
| On registration | Full verification of all submitted licenses | License Verification Worker (:8123) |
| Daily | Check expiration dates, flag upcoming expirations | Cron job |
| Weekly | Re-verify active licenses (batch of ~50/week) | Cron job |
| Monthly | Full reverification of all active licenses | Cron job |
| On license alert | Immediate reverification (from webhook or alert) | Event trigger |

### 6.3 Pro Hac Vice Tracking

For multi-state practice, track pro hac vice admissions for each case:

```sql
CREATE TABLE marketplace.pro_hac_vice_records (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_assignment_id  UUID NOT NULL REFERENCES marketplace.case_assignments(id),
    attorney_id         UUID NOT NULL REFERENCES marketplace.attorneys(id),
    jurisdiction_state  CHAR(2) NOT NULL,
    filing_court        VARCHAR(256),
    case_number         VARCHAR(128),
    local_counsel_id    UUID REFERENCES marketplace.attorneys(id),
    filing_status       VARCHAR(32) DEFAULT 'pending',
    order_granted_date  DATE,
    expiration_date     DATE,
    document_url        VARCHAR(1024),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## 7. Attorney Portal & Dashboard

### 7.1 Portal Architecture

The attorney portal is a lightweight single-page application served from EDGE (port 8121) via Traefik, proxying to the AIOPS API. It communicates exclusively with `https://fundsrecoverygroup.com/api/attorney-marketplace/v1/*`.

**Tech Stack:**
- Frontend: Lightweight React SPA (or Vue.js for smaller bundle)
- Auth: Email magic link via SendGrid (JWT expiry: 24h, refresh: 7d)
- Styling: Tailwind CSS (consistent with ecosystem)
- Hosting: PM2 on EDGE node behind Traefik

### 7.2 Dashboard Views

**Home Dashboard:**
- Active case count with status breakdown
- Pending offers (with timer before auto-decline)
- Revenue summary (current month, past month, YTD)
- Performance snapshot (composite score, tier, trend arrow)
- Upcoming deadlines (next 7 days)
- Recent communications (last 5 messages)

**Cases View:**
- Filterable table: status, county, claim amount, assigned date
- Click-through to case detail: claimant info, documents, timeline
- Action buttons: Accept, Decline, Message, Upload Document
- Case timeline visualization (assigned -> accepted -> documents -> filing -> recovery -> closed)

**Revenue View:**
- Current period earnings breakdown
- Pending payouts with estimated payment dates
- Paid payout history with Stripe transaction IDs
- YTD comparison chart
- 1099 download (when available)

**Profile View:**
- Personal information (editable)
- Bar licenses with verification status
- Practice areas with county selection
- Availability settings
- Communication preferences
- Malpractice insurance (upload/renew)

**Documents View:**
- All case documents grouped by case
- Signature status (pending/signed/completed)
- Download links
- Bulk document request (for court filings)

### 7.3 Notification Channels

| Event | Channel | Format | Priority |
|-------|---------|--------|----------|
| New case offer | Email (SendGrid) + Portal badge | "New surplus funds case in {county}, {state}" | High |
| Offer accepted | Portal notification | "Case #{case_id} accepted, next steps" | Medium |
| Offer declining | Email (sendGrid) | "Case #{case_id} declined, reassigned" | Low |
| Document pending signature | Email + Portal | "Representation agreement ready to sign" | High |
| Court deadline approaching | Email + SMS | "Filing deadline: {date} for {case_id}" | Urgent |
| Payout processed | Email | "${amount} deposited to your account" | Medium |
| Performance review | Email | "Monthly performance scorecard ready" | Low |
| License expiring | Email | "Bar license in {state} expires {date}" | Medium |
| System notification | Portal only | Varies | Low |

---

## 8. Integration Points with Existing Infrastructure

### 8.1 FRGCRM Integration

The attorney marketplace replaces and extends the manual attorney management in FRGCRM:

| Current FRGCRM (Manual) | Marketplace (Automated) | Migration Strategy |
|-------------------------|------------------------|---------------------|
| Attorney list hardcoded | Attorney database with profiles | Seed from FRGCRM on Phase 1 deploy |
| Manual assignment | AI + rule-based routing | FRGCRM sends `POST /assignments/route` |
| No capacity tracking | Real-time capacity in `attorney_availability` | Auto-decrement on assignment, auto-increment on completion |
| No performance tracking | `performance_scores` table with composite | Historical data entry from FRGCRM logs |

**FRGCRM Integration API:** Once FRGCRM is operational, it integrates via:
```
FRGCRM -> POST /api/v1/assignments/route (with case data)
         GET /api/v1/assignments/{id} (poll for acceptance)
         POST /api/v1/communications/send (notify attorney)
```

### 8.2 PipelineDAG Integration

The PipelineDAG AttorneyMatcher stage is replaced by the marketplace routing engine:

```
Old PipelineDAG Flow:
LeadIngestion -> CaseScorer -> AttorneyMatcher (BROKEN) -> ClaimantOutreach -> ...

New PipelineDAG Flow:
LeadIngestion -> CaseScorer -> MarketplaceRouter (NEW) -> ClaimantOutreach -> ...
                                   │
                                   ▼
                          POST /api/v1/assignments/route
                          ┌───────────────────────────┐
                          │ Marketplace Router:        │
                          │ 1. Rule-based pre-filter   │
                          │ 2. AI scoring (DeepSeek)   │
                          │ 3. Assignment creation     │
                          │ 4. Offer notification      │
                          │ 5. Wait for acceptance     │
                          │ 6. Return assignment_id    │
                          └───────────────────────────┘
```

### 8.3 Docuseal Integration

Docuseal (LIVE at :3010) handles all document e-signatures:

```
Document Types (Templates):
1. Representation Agreement (per case)
2. Revenue Sharing Agreement (per attorney, once)
3. Pro Hac Vice Motion (per case, when needed)
4. Settlement Authorization (per case)
5. Release of Claims (per case)

Integration Flow:
Marketplace API -> POST to Docuseal API -> Generate document -> Send for signature -> Webhook callback
    :8120                :3010              Docuseal UI       Via email         -> Update case_documents
```

### 8.4 LiteLLM + DeepSeek Integration

All AI calls route through the existing LiteLLM proxy at `127.0.0.1:4049`:

```
DeepSeek API <─> LiteLLM (:4049) <─> Marketplace Routing Engine (:8120)
                  │
                  ├─ Attorney scoring (primary use)
                  ├─ License verification text parsing
                  ├─ Document template variable extraction
                  └─ Communication drafting assistance
```

### 8.5 SendGrid Integration

Transactional emails for the marketplace reuse the existing SendGrid SMTP infrastructure (usesend at :3007 or direct SendGrid API):

```
Email Types:
1. Welcome Email — Onboarding complete, attorney activated
2. Case Offer — New case assignment notification
3. Document for Signature — Via Docuseal (Docuseal sends its own emails)
4. Milestone Updates — Case progress notifications
5. Revenue Notifications — Payout processed
6. License Alerts — Expiration warnings
7. Performance Reports — Monthly scorecards
```

### 8.6 Discord Webhook Integration

Operational events publish to the ecosystem Discord:

```json
{
  "channel": "attorney-marketplace",
  "events": [
    "New attorney registered — pending verification (attorney_name)",
    "Bar license verification failed for attorney_id — state: CA",
    "Case #123 assigned to attorney_name — routing_score: 87.5",
    "Offer declined — attorney_name — reason: at_capacity",
    "Payout processed — attorney_name — $1,234.56",
    "Attorney performance tier change — name: GOLD -> PLATINUM",
    "Quality review opened — attorney_name — severity: high"
  ]
}
```

### 8.7 n8n Workflow Integration

n8n handles automated workflow triggers:

| Workflow | Trigger | Actions |
|----------|---------|---------|
| New Case Assignment | Webhook from PipelineDAG | Route to attorney, send offer notification, create Timeline event |
| Offer Acceptance | Webhook from portal | Update FRGCRM case status, create Docuseal agreement, send welcome packet |
| Document Signed | Docuseal webhook | Update case_documents, send milestone notification, trigger next workflow step |
| License Expiring | Weekly cron | Send reminder email, flag admin review, pause if expired |
| Weekly Performance Digest | Weekly cron | Calculate performance scores, send digest email, update Discord |
| Monthly Payout Batch | Monthly cron | Calculate all pending payouts, create Stripe transfers, notify attorneys |

---

## 9. Implementation Phases

### 9.1 Phase 1: Attorney Database + Manual Assignment Improvements (Weeks 1-2)

**Goal:** Replace hardcoded attorney list with database-backed profiles; improve manual assignment workflow.

**Deliverables:**
- [x] PostgreSQL database `attorney_marketplace` on AIOPS local PG
- [x] `attorneys`, `attorney_bar_licenses`, `attorney_practice_areas`, `attorney_availability` tables
- [x] `case_assignments` table with status tracking
- [x] PM2 service: Attorney Marketplace API (:8120) — basic CRUD endpoints
- [x] Seed data: Bigham, Morris, Farah, Walker from current FRGCRM config
- [x] Admin API endpoints: CRUD attorneys, list attorneys, manual assign case
- [x] Case assignment status workflow (pending -> offered -> accepted -> active -> completed)
- [x] Basic audit log for assignment changes
- [x] Migration: export attorney data from FRGCRM into marketplace schema

**Integration:** Direct API calls from FRGCRM admin panel for attorney selection (dropdown from marketplace DB instead of hardcoded list).

**Exit Criteria:** Admin can create, read, update, delete attorneys. Case assignments tracked in database with full status history. 4 existing attorneys migrated.

### 9.2 Phase 2: Self-Service Onboarding + License Verification (Weeks 3-5)

**Goal:** Attorneys can register themselves; bar license verification is at least semi-automated.

**Deliverables:**
- [ ] Attorney self-service registration endpoint (public, rate-limited)
- [ ] Docuseal revenue sharing agreement generation + signing
- [ ] Attorney onboarding flow: register -> verify email -> submit bar licenses -> sign agreement -> await admin approval
- [ ] State bar lookup cache table and scraping worker for top-10 states by volume
- [ ] Admin verification dashboard (pending attorneys list, verify/reject actions)
- [ ] Malpractice insurance upload and verification workflow
- [ ] Welcome email via SendGrid on activation
- [ ] PM2 service: License Verification Worker (:8123)
- [ ] PM2 service: Onboarding Worker (:8122)

**Integration:** Docuseal template for revenue sharing agreement. SendGrid for verification and welcome emails. SurplusAI scraper pattern reused for state bar lookups.

**Exit Criteria:** Attorney can register from public URL, submit credentials, sign agreement via Docuseal, and be activated by admin. Bar license verification works for at least 10 states.

### 9.3 Phase 3: Automated Routing + Capacity Tracking (Weeks 6-8)

**Goal:** Cases are automatically routed to the best attorney based on capacity, expertise, and performance.

**Deliverables:**
- [ ] AI routing engine with DeepSeek via LiteLLM (primary scorer)
- [ ] Rule-based routing fallback (pre-filter + weighted score)
- [ ] Round-robin performance-weighted fallback
- [ ] Assignment candidate ranking endpoint
- [ ] Capacity auto-management (decrement on assignment, increment on completion)
- [ ] Offer timeout and reassignment (configurable: 48h default)
- [ ] Attorney availability self-management (portal or email)
- [ ] Manual override and reassignment APIs
- [ ] Candidate preview endpoint (what-if scoring without creating assignment)
- [ ] Conflict of interest checking (exact name + county match)

**Integration:** PipelineDAG AttorneyMatcher stage replaced with marketplace routing API. FRGCRM reads assignment status. n8n workflow for offer timeout monitoring.

**Exit Criteria:** Case enters system -> marketplace routes to optimal attorney -> attorney notified -> acceptance or timeout -> reassignment if needed. 95% of cases assigned within 1 hour.

### 9.4 Phase 4: Revenue Sharing + Performance Scoring (Weeks 9-11)

**Goal:** Automated revenue sharing calculations, performance-based tiering, and payout processing.

**Deliverables:**
- [ ] Revenue share agreement table with configurable splits
- [ ] Per-case and per-case-type split overrides
- [ ] Automated payout calculation on case completion
- [ ] Stripe Connect integration for attorney payments
- [ ] Payout approval workflow (calculated -> approved -> paid)
- [ ] Performance scoring engine (7 components, weighted composite)
- [ ] Performance tier system (PLATINUM/GOLD/SILVER/BRONZE)
- [ ] Automated score recalculation (daily cron + on-demand)
- [ ] Performance leaderboard
- [ ] Revenue reporting dashboard (admin)
- [ ] PM2 service: Revenue Share Engine (:8124)

**Integration:** Stripe Connect for payment processing. n8n for monthly payout batch workflow. Discord for revenue milestone alerts.

**Exit Criteria:** Attorneys receive automated payouts on case completion. Performance scores calculated and updated daily. Admin can view revenue reports by attorney, practice area, and state.

### 9.5 Phase 5: Full Attorney Dashboard + Communication Layer (Weeks 12-14)

**Goal:** Complete attorney portal with case management, document workflow, and communications.

**Deliverables:**
- [ ] Attorney portal frontend (React SPA on EDGE :8121)
- [ ] Email magic link authentication
- [ ] Home dashboard: active cases, revenue, performance, deadlines
- [ ] Cases view with status filters, detail pages, timeline
- [ ] Revenue view: earnings, payouts, 1099 access
- [ ] Profile management: contact info, licenses, practice areas, availability
- [ ] Document view: per-case document list with signature status
- [ ] Secure communication inbox (portal messages + email archive)
- [ ] Document generation: representation agreements, court filings
- [ ] Docuseal integration for all signature workflows
- [ ] Deadline calendar with automated reminders
- [ ] PM2 service: Attorney Frontend (:8121)
- [ ] PM2 service: Document Automation Worker (:8125)
- [ ] PM2 service: Communications Worker (:8126)

**Integration:** Docuseal for all document generation and signatures. SendGrid for email notifications. Traefik + Cloudflare for portal routing.

**Exit Criteria:** Attorney can manage entire case lifecycle from portal: view offers, accept/decline, manage documents, communicate, track revenue, and view performance.

### 9.6 Phase 6: Marketplace Governance + Quality Enforcement (Weeks 15-16)

**Goal:** Full governance framework for quality assurance, compliance, and lifecycle management.

**Deliverables:**
- [ ] Quality review creation and tracking
- [ ] Performance improvement plan (PIP) workflow
- [ ] Automated suspension/offboarding triggers (license expired, low performance, compliance failure)
- [ ] Suspension and offboarding workflows with case reassignment
- [ ] Full audit trail for every action (200+ event types)
- [ ] Conflict of interest advanced checking (claimant name variation, property adjacency)
- [ ] Ethics compliance monitoring (deadline compliance, communication timeliness)
- [ ] Data privacy controls (attorney PII encryption, claimant PII access logging)
- [ ] Automated compliance reporting (monthly)
- [ ] Governance dashboard for admin

**Integration:** Discord for critical alerts (suspension, ethics violation). n8n for automated compliance report generation.

**Exit Criteria:** Complete governance lifecycle: quality review -> action -> resolution. Automatic enforcement of standards. Full audit trail. Compliance reports generated monthly.

---

## 10. PM2 Service Configuration

```javascript
// ecosystem.config.js — Attorney Marketplace Services
module.exports = {
  apps: [
    {
      name: 'attorney-marketplace-api',
      cwd: '/opt/wheeler/apps/attorney-marketplace/api',
      script: 'dist/server.js',       // or 'main.py' if Python
      instances: 2,
      exec_mode: 'cluster',
      env: {
        PORT: 8120,
        NODE_ENV: 'production',
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
        LITELLM_URL: 'http://127.0.0.1:4049',
        DOCUSEAL_URL: 'http://127.0.0.1:3010',
        SENDGRID_API_KEY: '${SENDGRID_API_KEY}',
        DISCORD_WEBHOOK_URL: '${ATTORNEY_DISCORD_WEBHOOK}',
        STRIPE_SECRET_KEY: '${STRIPE_STRIPE_SECRET_KEY}',
        STRIPE_WEBHOOK_SECRET: '${STRIPE_WEBHOOK_SECRET}',
        JWT_SECRET: '${ATTORNEY_JWT_SECRET}',
        LOG_LEVEL: 'info',
      },
      max_restarts: 5,
      min_uptime: '30s',
      kill_timeout: 10000,
    },
    {
      name: 'attorney-onboarding-worker',
      cwd: '/opt/wheeler/apps/attorney-marketplace/workers/onboarding',
      script: 'dist/onboarding-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
        SENDGRID_API_KEY: '${SENDGRID_API_KEY}',
        DOCUSEAL_URL: 'http://127.0.0.1:3010',
      },
    },
    {
      name: 'attorney-license-worker',
      cwd: '/opt/wheeler/apps/attorney-marketplace/workers/license',
      script: 'dist/license-worker.js',
      instances: 1,
      cron_restart: '0 6 * * 0',     // Weekly reverification
      env: {
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
        LITELLM_URL: 'http://127.0.0.1:4049',
      },
    },
    {
      name: 'attorney-revenue-engine',
      cwd: '/opt/wheeler/apps/attorney-marketplace/workers/revenue',
      script: 'dist/revenue-engine.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
        STRIPE_SECRET_KEY: '${STRIPE_STRIPE_SECRET_KEY}',
        STRIPE_WEBHOOK_SECRET: '${STRIPE_WEBHOOK_SECRET}',
      },
    },
    {
      name: 'attorney-document-worker',
      cwd: '/opt/wheeler/apps/attorney-marketplace/workers/document',
      script: 'dist/document-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
        DOCUSEAL_URL: 'http://127.0.0.1:3010',
      },
    },
    {
      name: 'attorney-communications-worker',
      cwd: '/opt/wheeler/apps/attorney-marketplace/workers/communications',
      script: 'dist/communications-worker.js',
      instances: 1,
      env: {
        SENDGRID_API_KEY: '${SENDGRID_API_KEY}',
        DISCORD_WEBHOOK_URL: '${ATTORNEY_DISCORD_WEBHOOK}',
        DB_URL: 'postgresql://attorney_mkt:${ATTORNEY_DB_PASSWORD}@127.0.0.1:5432/attorney_marketplace',
      },
    },
    {
      name: 'attorney-portal-frontend',
      cwd: '/opt/wheeler/apps/attorney-marketplace/frontend',
      script: 'node_modules/.bin/serve',
      args: '-s build -l 8121',
      instances: 1,
      env: {
        REACT_APP_API_URL: 'https://fundsrecoverygroup.com/api/attorney-marketplace/v1',
        REACT_APP_DOCUSEAL_URL: 'https://docuseal.fundsrecoverygroup.tech',
        NODE_ENV: 'production',
      },
    },
  ],
};
```

---

## 11. Security & Compliance

### 11.1 Data Privacy

| Data Class | Encryption | Access Control | Retention |
|------------|-----------|---------------|-----------|
| Attorney PII (name, address, SSN/EIN) | AES-256 at rest, TLS in transit | Attorney (self) + FRG Admin | Duration of agreement + 3 years |
| Bar license numbers | AES-256 at rest | Attorney (self) + FRG Admin + License Worker | Duration of agreement + 3 years |
| Claimant PII | AES-256 at rest, SHA-256 hashed SSN | Case attorney + FRG Admin | Per client agreement terms |
| Revenue data (amounts, splits) | AES-256 at rest | Attorney (self) + FRG Admin + Revenue Engine | 7 years (tax compliance) |
| Communication content | AES-256 at rest | Participants + FRG Admin | 3 years |

### 11.2 API Security

- All external endpoints behind Cloudflare + Traefik (DDoS/WAF protection)
- JWT authentication for attorney portal (email magic link, 24h expiry, refresh token)
- API key authentication for internal service-to-service calls (via Tailscale)
- Rate limiting: 10 req/min for public registration endpoint, 100 req/min for authenticated endpoints
- CORS restricted to: `https://fundsrecoverygroup.com`, `https://attorney.fundsrecoverygroup.tech`
- Request logging with IP, user agent, and action for audit trail

### 11.3 Compliance Requirements

- **IRS 1099-NEC:** Annual filing for attorney payouts >$600. Revenue engine must track cumulative annual payouts per attorney and trigger 1099 generation.
- **State Bar Ethics Rules:** Each state has specific rules about:
  - Fee splitting with non-lawyers (FRG must comply with each state's rules)
  - Attorney advertising (FRG lead generation practices)
  - Client solicitation (waiting periods, communication restrictions)
- **Data Privacy:** Attorney PII governed by applicable state privacy laws. Claimant PII governed by FRG privacy policy.

---

## 12. Key Metrics & Success Criteria

### 12.1 Phase Completion Metrics

| Phase | Metric | Target |
|-------|--------|--------|
| Phase 1 | Attorneys in database | >=4 (all existing) |
| Phase 1 | Case assignments tracked | 100% |
| Phase 2 | Self-service registrations | >=5 attorneys/month |
| Phase 2 | License verification time | <24h |
| Phase 3 | Auto-routed cases | >=90% |
| Phase 3 | Time-to-assignment | <1 hour |
| Phase 3 | Offer acceptance rate | >=60% |
| Phase 4 | Automated payouts | 100% of completed cases |
| Phase 4 | Performance scores computed | Daily automated |
| Phase 5 | Portal adoption | >=80% of active attorneys |
| Phase 5 | Document auto-generation | >=95% of cases |
| Phase 6 | Quality reviews completed | Monthly per attorney |
| Phase 6 | Audit trail completeness | 100% |

### 12.2 Business Impact Metrics

| Metric | Current (Manual) | Phase 3 Target | Phase 6 Target |
|--------|-----------------|----------------|----------------|
| Active attorneys | 4 | 20 | 200+ |
| Cases/month | <50 | 200 | 2000+ |
| Assignment time | Hours-days | <1 hour | <5 minutes |
| Attorney capacity utilization | Unknown | 70-80% | 85-90% |
| Average recovery rate | Unknown | 10% improvement | 25% improvement |
| Revenue per case | Manual tracking | Automated | Real-time |

---

## 13. Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-----------|--------|------------|
| COREDB remains unreachable through Phases 1-2 | Medium | Critical — no centralized data | Phase 1 on local AIOPS PostgreSQL; migration path to COREDB when available |
| State bar lookup automation fails for key states | Medium | High — slows onboarding | Manual verification fallback; prioritize top 10 states by volume |
| Stripe Connect payout failures | Low | High — lost attorney trust | Retry logic; manual payout trigger; clear error reporting |
| Attorneys game performance scoring | Medium | Medium — unfair rankings | Human review of outlier scores; audit trail; cap per-case score impact |
| Conflict of interest missed | Low | Critical — ethics violation | Multi-field matching (name, property, county); admin review for flagged cases |
| AI routing bias toward specific attorneys | Low | Medium — uneven case distribution | Load balancing override in routing algorithm; regular bias audits |
| Attorney churn after onboarding investment | Medium | Medium — wasted onboarding cost | Quality screening during onboarding; performance tier benefits to retain top attorneys |

---

## 14. Directory Structure

```
/opt/wheeler/apps/attorney-marketplace/
├── api/                          # PM2 service :8120
│   ├── src/
│   │   ├── server.js             # Express/Fastify server
│   │   ├── routes/
│   │   │   ├── attorneys.js      # CRUD + search
│   │   │   ├── assignments.js    # Routing + status
│   │   │   ├── revenue.js        # Payouts + reporting
│   │   │   ├── documents.js      # Docuseal integration
│   │   │   ├── communications.js # Messages + notifications
│   │   │   ├── performance.js    # Scoring + leaderboard
│   │   │   ├── governance.js     # Reviews + enforcement
│   │   │   └── public.js         # Registration (rate-limited)
│   │   ├── services/
│   │   │   ├── routing-engine.js     # AI + rule-based routing
│   │   │   ├── scoring-service.js    # Performance score calculation
│   │   │   ├── capacity-service.js   # Availability management
│   │   │   ├── docuseal-service.js   # Docuseal API client
│   │   │   ├── sendgrid-service.js   # Email service
│   │   │   ├── stripe-service.js     # Payment processing
│   │   │   └── discord-service.js    # Webhook notifications
│   │   ├── models/               # Database models/ORM
│   │   ├── middleware/
│   │   │   ├── auth.js           # JWT + API key auth
│   │   │   ├── audit.js          # Audit logging
│   │   │   ├── rate-limit.js     # Rate limiting
│   │   │   └── validate.js       # Request validation
│   │   └── utils/
│   │       ├── logger.js
│   │       └── config.js         # Environment config
│   ├── package.json
│   └── ecosystem.config.js       # PM2 config (per-service)
├── workers/
│   ├── onboarding/               # PM2 service :8122
│   ├── license/                  # PM2 service :8123
│   ├── revenue/                  # PM2 service :8124
│   ├── document/                 # PM2 service :8125
│   └── communications/           # PM2 service :8126
├── frontend/                     # PM2 service :8121
│   ├── src/
│   │   ├── pages/
│   │   │   ├── Dashboard.jsx
│   │   │   ├── Cases.jsx
│   │   │   ├── Revenue.jsx
│   │   │   ├── Profile.jsx
│   │   │   ├── Documents.jsx
│   │   │   └── Communications.jsx
│   │   ├── components/
│   │   ├── services/
│   │   └── utils/
│   └── package.json
├── migrations/
│   ├── 001_initial_schema.sql
│   ├── 002_seed_attorneys.sql
│   └── 003_add_governance.sql
├── scripts/
│   ├── deploy.sh
│   ├── seed-test-data.sh
│   └── verify-health.sh
└── README.md
```

---

## 15. Deployment Sequence

### 15.1 Phase 1 Deployment

```bash
# 1. Create database
sudo -u postgres psql -c "CREATE DATABASE attorney_marketplace;"
sudo -u postgres psql -c "CREATE USER attorney_mkt WITH PASSWORD '$(openssl rand -hex 32)';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE attorney_marketplace TO attorney_mkt;"

# 2. Run schema migration
psql -U attorney_mkt -d attorney_marketplace -f /opt/wheeler/apps/attorney-marketplace/migrations/001_initial_schema.sql

# 3. Seed existing attorneys
psql -U attorney_mkt -d attorney_marketplace -f /opt/wheeler/apps/attorney-marketplace/migrations/002_seed_attorneys.sql

# 4. Deploy PM2 services
cd /opt/wheeler/apps/attorney-marketplace/api
npm install && npm run build
pm2 start ecosystem.config.js --only attorney-marketplace-api

# 5. Harden to localhost
pm2 describe attorney-marketplace-api  # confirm running on 127.0.0.1:8120

# 6. Save PM2 state
pm2 save

# 7. Configure Traefik route
# Add router to Traefik dynamic config:
# - Rule: Host(`fundsrecoverygroup.com`) && PathPrefix(`/api/attorney-marketplace`)
# - Middleware: rate-limit, auth-headers
# - Service: http://127.0.0.1:8120

# 8. Run health check
curl -s http://127.0.0.1:8120/api/v1/health | jq .
```

### 15.2 Environment Variables

```bash
# Required environment variables
ATTORNEY_DB_PASSWORD=<generated-random-hex>
ATTORNEY_JWT_SECRET=<generated-random-hex>
ATTORNEY_DISCORD_WEBHOOK=<discord-webhook-url>
SENDGRID_API_KEY=<existing-sendgrid-key>
STRIPE_STRIPE_SECRET_KEY=<stripe-secret-key>
STRIPE_WEBHOOK_SECRET=<stripe-webhook-secret>
```

---

## Appendix A: Existing Attorney Seed Data

```sql
INSERT INTO marketplace.attorneys (id, first_name, last_name, firm_name, firm_email, onboarding_status)
VALUES
    (gen_random_uuid(), 'John', 'Bigham', 'Bigham Law Firm', 'john@bighamlaw.com', 'active'),
    (gen_random_uuid(), 'James', 'Morris', 'Morris Legal Group', 'james@morrislegal.com', 'active'),
    (gen_random_uuid(), 'Sarah', 'Farah', 'Farah & Associates', 'sarah@farahassociates.com', 'active'),
    (gen_random_uuid(), 'Michael', 'Walker', 'Walker Law Office', 'michael@walkerlawoffice.com', 'active');

-- Default revenue share: 70% attorney, 30% FRG
INSERT INTO marketplace.revenue_share_agreements (attorney_id, default_split_percentage, frg_split_percentage, status)
SELECT id, 70.00, 30.00, 'active' FROM marketplace.attorneys;
```

---

*End of Document — Attorney Marketplace Architecture v1.0*
