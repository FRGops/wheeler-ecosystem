# Marketplace Architecture -- Wheeler Ecosystem Multi-Sided Platform

**Classification:** EXECUTIVE CONFIDENTIAL
**Version:** 1.0
**Date:** 2026-05-24
**Ecosystem Context:** Stage 2 Hardening Complete (QA Scorecard 100/100 A+)
**Author:** Wheeler Autonomous Enforcement Agent -- Marketplace Division
**Related Documents:**
- `/root/ATTORNEY_MARKETPLACE_ARCHITECTURE.md` -- Attorney marketplace primary architecture (extends this doc)
- `/root/WHEELER_REVENUE_ENGINE_ARCHITECTURE.md` -- Ecosystem-wide revenue architecture
- `/root/SURPLUSAI_PRODUCTIZATION_PLAN.md` -- SurplusAI productization and attorney assignment engine
- `/root/DEPLOYMENT_SYSTEM.md` -- Deployment and rollback patterns
- `/root/.claude/projects/-root/memory/pm2-env-i-pattern.md` -- PM2 env var management

---

## Table of Contents

1. Executive Summary
2. Multi-Sided Marketplace Overview
3. Marketplace 1: Attorney Marketplace (Primary)
4. Marketplace 2: Partner Marketplace
5. Marketplace 3: Referral Marketplace
6. Marketplace 4: Workflow Marketplace
7. Marketplace 5: AI Automation Marketplace
8. Cross-Marketplace Integration Layer
9. Shared Database Schemas
10. API Gateway and Routing
11. Revenue Engine and Payout Architecture
12. Trust and Safety Platform
13. Implementation Phases
14. PM2 Service Configuration
15. Directory Structure
16. Key Metrics and Success Criteria
17. Risk Register

---

## 1. Executive Summary

### 1.1 The Vision

The Wheeler ecosystem operates five interconnected marketplaces that together form a multi-sided platform for legal, financial, and AI services. Each marketplace serves a distinct participant group while sharing a common infrastructure layer for identity, payments, document workflow, and AI intelligence.

The marketplaces are:

| # | Marketplace | Primary Participants | Existing Infrastructure | Revenue Model |
|---|-------------|---------------------|------------------------|---------------|
| 1 | **Attorney Marketplace** | Claimants, Attorneys, FRG | Docuseal :3010, Usesend :3007, FRGCRM :8082, LiteLLM :4049, DeepSeek | Transaction fees, subscriptions, listing fees |
| 2 | **Partner Marketplace** | Real estate agents, Title companies, Financial advisors, FRG | FRGCRM :8082, Docuseal :3010, Usesend :3007 | Commission splits, referral fees, subscriptions |
| 3 | **Referral Marketplace** | Attorneys (referring), Attorneys (receiving), Claimants | FRGCRM :8082, Neo4j :7687, Docuseal :3010 | Revenue share on cross-jurisdiction referrals |
| 4 | **Workflow Marketplace** | n8n workflow developers, Legal/financial firms | n8n :5678 (planned), Temporal :7233, Neo4j :7687 | Template sales, custom workflow dev, subscriptions |
| 5 | **AI Automation Marketplace** | AI developers, Legal/financial firms, Claude Code agents | LiteLLM :4049, DeepSeek, Claude Code, Command Center :8100 | Agent subscriptions, usage-based billing, template sales |

**Strategic Impact:**
- Current attorney capacity: 4 attorneys, manual assignment, <50 cases/month
- Phase 1 target: 20 attorneys, 200+ cases/month, partner onboarding MVP
- Phase 2 target: 50+ attorneys, 15+ partners, workflow templates live, referral network active
- Full build target: 200+ attorneys, 100+ partners, 50+ workflow templates, 20+ AI agent products, 2000+ cases/month

### 1.2 Design Principles

**Build on Existing Services:** Every marketplace reuses live infrastructure. No service is built until its dependencies are verified operational.

**Liquidity First:** Each marketplace has a bootstrap strategy that creates initial transaction volume before opening to broad participation. Chicken-and-egg is solved sequentially, not simultaneously.

**Revenue-Bearing From Day One:** No marketplace is built as a speculative platform. Each marketplace generates measurable revenue from its first launch phase.

**Zero-Trust Security:** All marketplace services bind to 127.0.0.1. External access routes through Cloudflare + Traefik with WAF, rate limiting, and auth. Tailscale-only for admin interfaces.

**No-False-Greens Compliance:** Every marketplace deployment passes the QA scorecard at 100/100 before promotion. All Docker images pinned. All PM2 processes stable.

### 1.3 Infrastructure Footprint

The entire marketplace platform runs across three existing nodes without additional hardware:

| Node | Role | IP | Services |
|------|------|-----|----------|
| AIOPS | Application + AI | 100.121.230.28 | Marketplace APIs, workers, LiteLLM, DeepSeek, n8n, Temporal, FRGCRM |
| COREDB | Data + Storage | 100.118.166.117 | PostgreSQL, Redis, MinIO, Neo4j |
| EDGE | Gateway | 100.98.163.17 | Traefik, frontend SPAs, Docuseal, Usesend |

---

## 2. Multi-Sided Marketplace Overview

### 2.1 Architecture Diagram

```
                               ┌─────────────────────────────────────┐
                               │         CLOUDFLARE / TRAEFIK         │
                               │   fundsrecoverygroup.com/api/market  │
                               └────────────┬────────────────────────┘
                                            │
              ┌─────────────────────────────┼─────────────────────────────┐
              │                             │                             │
              ▼                             ▼                             ▼
   ┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
   │ ATTORNEY            │     │ PARTNER             │     │ REFERRAL            │
   │ MARKETPLACE         │     │ MARKETPLACE         │     │ MARKETPLACE         │
   ├─────────────────────┤     ├─────────────────────┤     ├─────────────────────┤
   │ Onboarding          │     │ RE Agent Directory  │     │ Cross-Jurisdiction  │
   │ Case Routing        │     │ Title Company List  │     │ Referral Network    │
   │ Revenue Sharing     │     │ Financial Advisor   │     │ Multi-Party Splits  │
   │ Performance Scoring │     │ Directory           │     │ Claimant Referrals  │
   │ Document Workflow   │     │ Commission Tracking  │     │ Referral Fee Escrow │
   │ Attorney Portal     │     │ Partner Portal      │     │ Referral Portal     │
   └──────────┬──────────┘     └──────────┬──────────┘     └──────────┬──────────┘
              │                             │                             │
              └─────────────────────────────┼─────────────────────────────┘
                                            │
              ┌─────────────────────────────┼─────────────────────────────┐
              │                             │                             │
              ▼                             ▼                             ▼
   ┌─────────────────────┐     ┌─────────────────────┐
   │ WORKFLOW            │     │ AI AUTOMATION       │
   │ MARKETPLACE         │     │ MARKETPLACE         │
   ├─────────────────────┤     ├─────────────────────┤
   │ n8n Templates       │     │ Claude Code Agents  │
   │ Pre-Built Packages  │     │ AI Workflows        │
   │ Custom Development  │     │ Managed Subscriptions│
   │ Workflow Registry   │     │ Agent Templates      │
   │ Workflow Analytics  │     │ Usage Analytics      │
   └──────────┬──────────┘     └──────────┬──────────┘
              │                             │
              └─────────────────────────────┘
                                            │
              ┌─────────────────────────────┼─────────────────────────────┐
              │                             │                             │
              ▼                             ▼                             ▼
   ┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
   │ SHARED IDENTITY     │     │ SHARED PAYMENTS     │     │ SHARED INTELLIGENCE  │
   ├─────────────────────┤     ├─────────────────────┤     ├─────────────────────┤
   │ Unified Auth (JWT)  │     │ Stripe Connect      │     │ LiteLLM :4049       │
   │ Profile Service     │     │ Payout Engine       │     │ DeepSeek AI         │
   │ KYC/KYB Verification│     │ Revenue Splits      │     │ Neo4j :7687         │
   │ Role Management     │     │ 1099-NEC Generation │     │ Event Bus Relay     │
   └─────────────────────┘     └─────────────────────┘     └─────────────────────┘
```

### 2.2 Service Placement

| Service | Node | Port | PM2/Docker | Dependencies |
|---------|------|------|-----------|-------------|
| Attorney Marketplace API | AIOPS | 8120 | PM2 | COREDB:5432, LiteLLM:4049, DeepSeek |
| Attorney Frontend (Dashboard) | EDGE | 8121 | PM2 | Marketplace API:8120, Docuseal:3010 |
| Attorney Onboarding Worker | AIOPS | 8122 | PM2 | COREDB:5432, SendGrid, Docuseal:3010 |
| License Verification Worker | AIOPS | 8123 | PM2 | DeepSeek, LiteLLM:4049, COREDB:5432 |
| Revenue Share Engine | AIOPS | 8124 | PM2 | COREDB:5432, Stripe API |
| Document Automation Worker | AIOPS | 8125 | PM2 | Docuseal:3010, COREDB:5432 |
| Communications Worker | AIOPS | 8126 | PM2 | SendGrid, Discord Webhooks |
| Partner Marketplace API | AIOPS | 8130 | PM2 | COREDB:5432, Stripe Connect |
| Partner Portal Frontend | EDGE | 8131 | PM2 | Partner API:8130 |
| Partner Commission Worker | AIOPS | 8132 | PM2 | COREDB:5432, Stripe |
| Referral Marketplace API | AIOPS | 8140 | PM2 | COREDB:5432, Neo4j:7687 |
| Referral Portal Frontend | EDGE | 8141 | PM2 | Referral API:8140 |
| Referral Fee Escrow Worker | AIOPS | 8142 | PM2 | COREDB:5432, Stripe |
| Workflow Marketplace API | AIOPS | 8150 | PM2 | COREDB:5432, n8n:5678 |
| Workflow Portal Frontend | EDGE | 8151 | PM2 | Workflow API:8150 |
| AI Automation Marketplace API | AIOPS | 8160 | PM2 | COREDB:5432, LiteLLM:4049 |
| AI Automation Portal Frontend | EDGE | 8161 | PM2 | AI Marketplace API:8160 |
| AI Agent Subscription Worker | AIOPS | 8162 | PM2 | LiteLLM:4049, Stripe |
| n8n Workflow Engine | AIOPS | 5678 | Docker | COREDB:5432, Redis:6379 |
| Unified Payout Engine | AIOPS | 8170 | PM2 | Stripe, COREDB:5432 |
| Trust and Safety Service | AIOPS | 8180 | PM2 | COREDB:5432, Neo4j:7687 |

### 2.3 Shared Infrastructure Layers

**Identity Layer (Shared across all 5 marketplaces):**
- Unified JWT authentication (email magic link for participants, API key for system)
- Profile service with role-based access (attorney, partner, referrer, developer, admin)
- KYC/KYB verification queue (manual + AI-assisted via DeepSeek)
- Cross-marketplace reputation score (aggregated from all marketplace activities)

**Payment Layer (Shared across all 5 marketplaces):**
- Stripe Connect for marketplace payout processing
- Unified payout engine at :8170 handles all commission, fee, and subscription payments
- 1099-NEC generation for all payees exceeding $600/year
- Revenue split calculation engine (supports 2-party, 3-party, and N-party splits)
- Escrow service for deferred payments (referral fees, conditional commissions)

**Intelligence Layer (Shared across all 5 marketplaces):**
- LiteLLM :4049 provides DeepSeek access for all AI features
- Neo4j :7687 stores the relationship graph (participants, transactions, referrals)
- Event bus relay distributes marketplace events across all services
- n8n :5678 orchestrates cross-marketplace workflows
- Temporal :7233 provides durable workflow execution for complex multi-step processes

---

## 3. Marketplace 1: Attorney Marketplace (Primary)

### 3.1 Relationship to Existing Architecture

The Attorney Marketplace extends the architecture defined in `/root/ATTORNEY_MARKETPLACE_ARCHITECTURE.md`. That document covers the full database schema (attorneys, bar licenses, practice areas, case assignments, performance scores, revenue sharing, documents, communications, governance), API design, AI routing engine, state license verification, portal/dashboard design, PM2 configuration, deployment sequence, and security compliance.

This section adds the multi-sided marketplace dimensions -- network effects, liquidity strategy, and cross-marketplace integration -- to the existing architecture.

### 3.2 Participants

| Side | Participants | Existing State | Activation Strategy |
|------|-------------|----------------|---------------------|
| Supply | Attorneys (active) | 4 (Bigham, Morris, Farah, Walker) | Seed with existing 4, onboard 20 via outreach |
| Supply | Attorneys (pipeline) | 0 | Bar association partnerships, digital ads, referral from existing attorneys |
| Demand | Claimants (FRG leads) | 122 migrated cases, 6,603 on Hostinger | Activate SurplusAI scraper, begin claimant outreach |
| Demand | Claimants (incoming) | 0/day (scraper blocked) | Fix scraper restart loop (P1 blocker) |
| Platform | FRG (operator) | Operational at :8082 | FRGCRM API provides the transaction layer |

### 3.3 Network Effects

**Cross-Side (Attorneys <-> Claimants):**
- More attorneys in more states -> more claimant matches -> more closures -> more revenue -> attracts more attorneys
- More claimants -> higher case volume -> attorneys earn more -> attracts more attorneys -> more capacity for claimants

**Same-Side (Attorney <-> Attorney):**
- Network effects are WEAK on the supply side (attorneys compete for cases)
- Network effects become POSITIVE through the referral marketplace (Section 5) where attorneys refer overflow cases to each other and earn referral fees

**Same-Side (Claimant <-> Claimant):**
- Weak direct network effects, but more claimants = more data = better AI routing = better outcomes = more claimants

**Platform Effects:**
- More data (cases + outcomes) -> better AI scoring -> better attorney matching -> higher recovery rates -> more revenue
- More attorneys -> more performance data -> better tier differentiation -> premium listing revenue

### 3.4 Liquidity Bootstrap Strategy

The Attorney Marketplace does NOT have a chicken-and-egg problem because demand (claimants) exists independently of supply (attorneys). The bootstrap strategy exploits this asymmetry:

**Phase 1: Demand-Side Priming (Existing)**
- 6,725 total case records already exist in the ecosystem
- 122 cases migrated to AIOPS frgops-standby :5433
- 6,603 cases on Hostinger shared-postgres-recovery waiting for migration
- SurplusAI scraper (when fixed) will generate new leads continuously
- Initial liquidity = 122 cases + 4 attorneys

**Phase 2: Supply-Side Recruitment**
- Recruit 20 attorneys in top-10 surplus fund states (CA, TX, FL, IL, NY, AZ, OH, GA, PA, MI)
- Offer 70/30 split (attorney/firm) -- better than industry standard 60/40
- No onboarding fees, no monthly listing fees in Phase 1
- Value proposition: "We bring you pre-qualified claimants. You handle the legal work."

**Phase 3: Self-Sustaining Flywheel**
- Attorneys refer other attorneys (referral bonuses)
- Case closure data drives AI routing accuracy
- Top performers get premium placement (gratis in Phase 1, paid in Phase 3+)
- Claimant word-of-mouth from successful recoveries

### 3.5 Revenue Model

| Revenue Stream | Description | Split | Phase |
|---------------|-------------|-------|-------|
| Case Transaction Fee | Per-case fee on successful recovery | 70% attorney, 25% FRG, 5% marketplace | Phase 2+ |
| Premium Attorney Listing | Featured placement in search results | $199/mo | Phase 3+ |
| Performance Tier Bonus | PLATINUM attorneys get priority routing | N/A (earned, not paid) | Phase 2+ |
| Document Processing | Docuseal e-signature fees | $2.50/document or included in plan | Phase 3+ |
| API Access | Lead feed API for large firms | $997/mo (Enterprise tier) | Phase 3+ |

### 3.6 Trust and Safety

| Mechanism | Implementation | Automated |
|-----------|---------------|-----------|
| Bar License Verification | DeepSeek-assisted verification + state bar API | Semi-automated |
| Malpractice Insurance | Document upload + verification via Docuseal | Semi-automated |
| Performance Tiering | Composite score (7 factors) -> PLATINUM/GOLD/SILVER/BRONZE | Fully automated |
| Quality Reviews | Incident-triggered investigations with admin workflow | Admin-assisted |
| Conflict of Interest | Multi-field matching (claimant name + property + county) | Automated |
| Suspension/Offboarding | Automated triggers for license expiry, compliance failure | Rule-based |
| Audit Trail | Full JSONB audit log for every action | Fully automated |

---

## 4. Marketplace 2: Partner Marketplace

### 4.1 Purpose

The Partner Marketplace extends the ecosystem beyond attorneys to include real estate agents, title companies, and financial advisors who participate in the surplus fund recovery value chain. These partners provide referral sources, ancillary services, and distribution channels that increase case volume and recovery rates.

### 4.2 Participants

| Side | Participants | Value Proposition | Existing State |
|------|-------------|-------------------|----------------|
| Supply | Real Estate Agents | Earn referral fees for identifying surplus fund leads from property sales | None |
| Supply | Title Companies | Access to closing data, identify surplus scenarios before they arise | None |
| Supply | Financial Advisors | Refer clients with unclaimed funds, earn finder's fees | None |
| Demand | Attorneys (from Marketplace 1) | Additional lead sources beyond FRG direct acquisition | Attorney marketplace active |
| Demand | FRG (platform operator) | Increased case volume through partner network | FRGCRM operational |
| Platform | Wheeler Ecosystem | Revenue share on each successful referral | Infrastructure ready |

### 4.3 Network Effects

**Cross-Side (Partners <-> Attorneys):**
- More partners (RE agents, title cos) -> more lead sources -> more cases for attorneys -> attorneys earn more -> attracts more attorneys -> more capacity -> partners earn more -> attracts more partners

**Same-Side Effects:**
- Partners compete for referral fees on the same leads (weak positive: competition drives quality)
- No significant same-side effect for attorneys (they already compete for cases)

**Cross-Marketplace Effects:**
- Partner Marketplace feeds leads INTO Attorney Marketplace (demand side)
- Partner Marketplace creates demand for Referral Marketplace (Section 5) when attorneys overflow
- Partner Marketplace data feeds AI scoring models in Attorney Marketplace

### 4.4 Liquidity Bootstrap Strategy

The Partner Marketplace has a MODERATE chicken-and-egg problem: partners want to see earning potential before joining; attorneys want to see lead volume before committing.

**Phase 1: Supply-Side Priming (Direct Recruitment)**
- Recruit 5 real estate agents from top surplus fund counties (LA County, Cook County, Harris County)
- Recruit 2 title companies with existing FRG relationships
- Offer 10% finder's fee on successful recovery (paid from FRG's 30% share)
- No fees for partners in Phase 1

**Phase 2: Lead Validation**
- Run 30-day pilot with initial 5+2 partners
- Track: leads submitted, conversion rate, average recovery, partner earnings
- Publish case studies: "Partner Jane Doe earned $X in Y months"
- Use case studies for recruitment marketing

**Phase 3: Self-Sustaining**
- Partner earnings create organic referrals ("I know another agent who'd want this")
- Tier system: BRONZE/SILVER/GOLD/PLATINUM based on lead quality and conversion
- Premium placement for top partners
- Monthly partner newsletter with leaderboard

### 4.5 Revenue Model

| Revenue Stream | Description | Split | Phase |
|---------------|-------------|-------|-------|
| Partner Finder's Fee | Percentage of FRG's fee attributed to partner-introduced leads | 10-15% of FRG's 30% (3-4.5% of total) | Phase 2+ |
| Partner Subscription | Premium tier for partners with enhanced tracking and analytics | $49/mo | Phase 3+ |
| Lead Marketplace | Partners can purchase additional lead categories | $0.50-2.00/lead | Phase 3+ |
| Title Company Integration | API access for automated lead ingestion | $199/mo | Phase 3+ |

### 4.6 Trust and Safety

| Mechanism | Implementation | Automated |
|-----------|---------------|-----------|
| License Verification | RE license, title company license verification via state databases | Semi-automated |
| Lead Quality Scoring | Conversion rate tracking, duplicate detection, stale lead flagging | Automated |
| Commission Transparency | Full audit trail of referral source -> case -> payout | Fully automated |
| Anti-Spam Controls | Rate limiting on lead submission, duplicate detection | Automated |
| Partner Tiering | Quality-based tier system with graduated commission rates | Automated |
| Dispute Resolution | Escalation workflow for commission disputes | Admin-assisted |

### 4.7 Technical Architecture

```
Partner Marketplace (:8130)
    │
    ├── POST /api/v2/partners/register
    │       Register as partner (self-service)
    │       Body: { type (re_agent | title | financial_advisor), license_info, firm }
    │
    ├── POST /api/v2/partners/{id}/submit-lead
    │       Submit a lead for attorney matching
    │       Body: { claimant_name, property_address, county, case_number, estimated_surplus }
    │       Response: { lead_id, match_status, estimated_value }
    │
    ├── GET /api/v2/partners/{id}/dashboard
    │       Partner dashboard: leads submitted, conversion rate, earnings
    │
    ├── GET /api/v2/partners/{id}/commissions
    │       Commission history and pending payouts
    │
    ├── GET /api/v2/partners/leaderboard
    │       Partner ranking by conversion value, lead quality, volume
    │
    ├── POST /api/v2/partners/{id}/tier-upgrade
    │       Request tier upgrade (requires meeting volume/quality thresholds)
    │
    └── WEBHOOK /api/v2/webhooks/lead-status
            Notify partner when their submitted lead changes status
            Events: matched, contacted, represented, closed, paid
```

### 4.8 Partner Marketplace Database Schema

```sql
-- ============================================================
-- PARTNER PROFILES
-- ============================================================

CREATE TYPE partner_type AS ENUM (
    'real_estate_agent',
    'title_company',
    'financial_advisor',
    'insurance_agent',
    'mortgage_broker',
    'other'
);

CREATE TABLE marketplace.partners (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id                 VARCHAR(64) UNIQUE,          -- Stripe Connect account ID
    partner_type                partner_type NOT NULL,
    firm_name                   VARCHAR(256),
    first_name                  VARCHAR(128) NOT NULL,
    last_name                   VARCHAR(128) NOT NULL,
    email                       VARCHAR(256) NOT NULL,
    phone                       VARCHAR(32),
    license_number              VARCHAR(128),                -- RE license, insurance license, etc.
    license_state               CHAR(2),
    license_verification_status VARCHAR(32) DEFAULT 'unverified',
        -- unverified | pending | verified | failed
    license_verified_at         TIMESTAMPTZ,
    firm_ein                    VARCHAR(16),
    firm_address                JSONB,                       -- {line1, line2, city, state, zip}
    onboarding_status           VARCHAR(32) NOT NULL DEFAULT 'draft',
        -- draft | pending_verification | verified | active | suspended | offboarded
    onboarding_completed_at     TIMESTAMPTZ,
    terms_accepted_at           TIMESTAMPTZ,
    agreement_docuseal_id       UUID,                        -- Signed agreement in Docuseal
    stripe_connect_account_id   VARCHAR(64),
    commission_tier             VARCHAR(16) DEFAULT 'standard',
        -- standard | silver | gold | platinum
    commission_rate_percent     NUMERIC(5,2) DEFAULT 10.00, -- Percentage of FRG's fee
    referral_code               VARCHAR(32) UNIQUE,          -- Unique referral code for tracking
    payout_preference           VARCHAR(16) DEFAULT 'stripe',
        -- stripe | bank_transfer | check
    bank_account_info           JSONB,                       -- Encrypted bank details
    tax_id_last_four            VARCHAR(4),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- PARTNER LEADS
-- ============================================================

CREATE TABLE marketplace.partner_leads (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id                  UUID NOT NULL REFERENCES marketplace.partners(id),
    lead_source                 VARCHAR(64) NOT NULL,
        -- direct_submission | api | referral_link | bulk_upload
    lead_type                   VARCHAR(64) NOT NULL,
        -- surplus_fund | foreclosure | probate | tax_sale | general_claimant
    claimant_first_name         VARCHAR(128) NOT NULL,
    claimant_last_name          VARCHAR(128) NOT NULL,
    claimant_phone              VARCHAR(32),
    claimant_email              VARCHAR(256),
    claimant_address            JSONB,                       -- {line1, line2, city, state, zip}
    property_address            VARCHAR(512),
    property_county             VARCHAR(128),
    property_state              CHAR(2),
    property_parcel_number      VARCHAR(128),
    case_number                 VARCHAR(128),
    court_name                  VARCHAR(256),
    estimated_surplus_amount    NUMERIC(12,2),
    estimated_commission_value  NUMERIC(10,2),               -- Estimated partner commission
    status                      VARCHAR(32) NOT NULL DEFAULT 'submitted',
        -- submitted | matched | contacted | represented | closed_paid | closed_unpaid | expired
    matched_attorney_id         UUID REFERENCES marketplace.attorneys(id),
    matched_assignment_id       UUID REFERENCES marketplace.case_assignments(id),
    matched_at                  TIMESTAMPTZ,
    closed_amount               NUMERIC(12,2),               -- Actual surplus recovered
    commission_amount           NUMERIC(10,2),               -- Actual commission paid
    commission_paid_at          TIMESTAMPTZ,
    stripe_transfer_id          VARCHAR(128),
    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_partner_leads_partner ON marketplace.partner_leads(partner_id, status);
CREATE INDEX idx_partner_leads_status ON marketplace.partner_leads(status, created_at);
CREATE INDEX idx_partner_leads_attorney ON marketplace.partner_leads(matched_attorney_id);

-- ============================================================
-- PARTNER COMMISSION TRACKING
-- ============================================================

CREATE TABLE marketplace.partner_commissions (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id                  UUID NOT NULL REFERENCES marketplace.partners(id),
    lead_id                     UUID NOT NULL REFERENCES marketplace.partner_leads(id),
    commission_type             VARCHAR(32) NOT NULL DEFAULT 'finder_fee',
        -- finder_fee | referral_bonus | tier_bonus | override
    gross_amount                NUMERIC(12,2) NOT NULL,       -- Total FRG fee on the case
    commission_percent          NUMERIC(5,2) NOT NULL,        -- Partner's commission percentage
    commission_amount           NUMERIC(10,2) NOT NULL,       -- Calculated amount
    status                      VARCHAR(32) NOT NULL DEFAULT 'calculated',
        -- calculated | approved | paid | failed | reversed
    calculated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_at                 TIMESTAMPTZ,
    paid_at                     TIMESTAMPTZ,
    stripe_transfer_id          VARCHAR(128),
    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_partner_commissions_status ON marketplace.partner_commissions(partner_id, status);

-- ============================================================
-- PARTNER PERFORMANCE SCORING
-- ============================================================

CREATE TABLE marketplace.partner_performance (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id                  UUID NOT NULL REFERENCES marketplace.partners(id) ON DELETE CASCADE,
    score_date                  DATE NOT NULL DEFAULT CURRENT_DATE,
    period_type                 VARCHAR(16) NOT NULL DEFAULT 'rolling_90',
        -- rolling_30 | rolling_90 | rolling_365 | all_time

    -- Component scores (0-100)
    lead_volume_score           NUMERIC(5,2),    -- Number of leads submitted
    lead_quality_score          NUMERIC(5,2),    -- Conversion rate of submitted leads
    avg_lead_value_score        NUMERIC(5,2),    -- Average estimated surplus amount
    conversion_rate             NUMERIC(5,2),    -- % of leads that converted to paid cases
    timeliness_score            NUMERIC(5,2),    -- How quickly leads are submitted post-event
    accuracy_score              NUMERIC(5,2),    -- Data accuracy of lead submissions

    composite_score             NUMERIC(5,2) GENERATED ALWAYS AS (
        COALESCE(lead_volume_score, 0) * 0.20 +
        COALESCE(lead_quality_score, 0) * 0.30 +
        COALESCE(avg_lead_value_score, 0) * 0.15 +
        COALESCE(conversion_rate, 0) * 0.20 +
        COALESCE(timeliness_score, 0) * 0.10 +
        COALESCE(accuracy_score, 0) * 0.05
    ) STORED,

    tier                        VARCHAR(16) GENERATED ALWAYS AS (
        CASE
            WHEN composite_score >= 85 THEN 'PLATINUM'
            WHEN composite_score >= 70 THEN 'GOLD'
            WHEN composite_score >= 50 THEN 'SILVER'
            WHEN composite_score IS NOT NULL THEN 'BRONZE'
            ELSE 'UNRATED'
        END
    ) STORED,

    leads_in_period             INTEGER DEFAULT 0,
    converted_in_period         INTEGER DEFAULT 0,
    total_commission_earned     NUMERIC(12,2) DEFAULT 0,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(partner_id, score_date, period_type)
);
```

---

## 5. Marketplace 3: Referral Marketplace

### 5.1 Purpose

The Referral Marketplace enables attorney-to-attorney referrals across jurisdictions and practice areas. When an attorney receives a case outside their licensed jurisdiction or practice specialty, they can refer it to another attorney in the network and earn a referral fee. This marketplace also tracks claimant referrals -- when a claimant refers another potential claimant.

### 5.2 Participants

| Side | Participants | Value Proposition | Existing State |
|------|-------------|-------------------|----------------|
| Supply | Attorneys (referring) | Earn referral fees (20-35%) on cases they cannot handle | Attorney marketplace active |
| Demand | Attorneys (receiving) | Access to pre-qualified cases outside their normal acquisition channels | Attorney marketplace active |
| Supply | Claimants (referring) | Earn finder's fee or reduced legal fees for referring other claimants | None |
| Platform | Wheeler Ecosystem | Transaction fee on each successful referral | Infrastructure ready |

### 5.3 Network Effects

**Cross-Side (Referring Attorneys <-> Receiving Attorneys):**
- More referring attorneys -> more referral case volume -> receiving attorneys get more cases -> attract more receiving attorneys -> more capacity -> attract more referring attorneys
- Key insight: EVERY attorney is BOTH a referrer and a recipient at different times (e.g., a California attorney refers a Texas case while receiving a family law case from a colleague)

**Cross-Marketplace Effects:**
- Attorney Marketplace (Section 3) creates overflow cases that feed into Referral Marketplace
- Referral Marketplace reduces attorney churn (attorneys stay for overflow referral income)
- Referral data creates the Neo4j relationship graph that improves AI matching

### 5.4 Liquidity Bootstrap Strategy

The Referral Marketplace has a LOW chicken-and-egg problem because initial liquidity comes from Attorney Marketplace overflow:

**Phase 1: Overflow-Only Referrals (Built-in Demand)**
- Attorney Marketplace routing engine identifies cases where no primary attorney is available (at capacity, wrong jurisdiction)
- These cases are automatically offered as referrals to the Attorney Marketplace network
- First 10 referrals are free (no platform fee) to establish the pattern
- Default referral fee: 25% of attorney's fee to referring attorney

**Phase 2: Active Referral Network**
- Attorneys can proactively list cases they want to refer out
- Attorneys can list case types they want to receive
- Matching engine pairs referrers with recipients
- Referral fee range: 15-35% (market-driven, set by referring attorney)

**Phase 3: Claimant Referral Program**
- Claimants with successful recoveries can refer other claimants
- Referral reward: $100-500 or 1% reduction in legal fees
- Referral code tracking via Usesend :3007 email campaigns

### 5.5 Revenue Model

| Revenue Stream | Description | Split | Phase |
|---------------|-------------|-------|-------|
| Referral Transaction Fee | Per-referral fee | 2% of case value (capped at $500) | Phase 2+ |
| Referral Fee Escrow | Held fee during case resolution | 0.5% processing fee | Phase 2+ |
| Premium Referral Listing | Featured placement in referral directory | $99/mo | Phase 3+ |
| Cross-Jurisdiction Network | Multi-state referral network access | Included in attorney subscription | Phase 3+ |

### 5.6 Trust and Safety

| Mechanism | Implementation | Automated |
|-----------|---------------|-----------|
| Attorney Verification | Bar license verification (reuses existing system) | Semi-automated |
| Referral Fee Escrow | Fees held in escrow until case resolution | Fully automated |
| Referral Agreement | Docuseal-generated referral fee agreement | Automated via Docuseal :3010 |
| Dispute Resolution | Escalation to admin with full audit trail | Admin-assisted |
| Quality Scoring | Referring attorney rated on referral quality | Automated |
| Anti-Circumvention | Tracking to prevent direct deals outside platform | Rule-based monitoring |
| Claimant Protection | Referral cannot increase claimant's legal costs | Automated check |

### 5.7 Technical Architecture

```
Referral Marketplace (:8140)
    │
    ├── POST /api/v3/referrals/create
    │       Create a referral (attorney refers case to another attorney)
    │       Body: { referring_attorney_id, receiving_attorney_id, case_assignment_id,
    │               referral_fee_percent, notes }
    │       Response: { referral_id, status, escrow_id }
    │
    ├── GET /api/v3/referrals/available
    │       List cases available for referral (attorney perspective)
    │       Query: practice_area, state, county, fee_range
    │       Response: [{ case_id, estimated_value, fee_percent, jurisdiction }]
    │
    ├── GET /api/v3/referrals/receiving-attorneys
    │       Find attorneys who want to receive referrals
    │       Query: state, practice_area, capacity
    │
    ├── POST /api/v3/referrals/{id}/accept
    │       Accept a referral (receiving attorney)
    │       Response: { status, docuseal_agreement_url }
    │
    ├── POST /api/v3/referrals/{id}/decline
    │       Decline a referral
    │       Response: { status, referred_to_next_candidate }
    │
    ├── GET /api/v3/referrals/attorney/{id}/outgoing
    │       Outgoing referrals (cases I referred to others)
    │
    ├── GET /api/v3/referrals/attorney/{id}/incoming
    │       Incoming referrals (cases referred to me)
    │
    ├── GET /api/v3/referrals/claimant/{id}
    │       Claimant referral tracking
    │       Response: { referrals_made, rewards_earned, pending_rewards }
    │
    ├── POST /api/v3/referrals/claimant/create
    │       Claimant refers another claimant
    │       Body: { referring_claimant_id, referred_name, referred_phone, referred_email }
    │       Response: { referral_id, reward_estimate }
    │
    ├── POST /api/v3/escrow/{id}/release
    │       Release escrowed referral fee (triggered on case closure)
    │       Response: { status, stripe_transfer_id }
    │
    └── GET /api/v3/referrals/network-graph
            Retrieve referral relationship graph from Neo4j
            Response: { nodes: [{attorney_id, name, cases_referred, fees_earned}],
                        edges: [{from, to, count, total_value}] }
```

### 5.8 Referral Marketplace Database Schema

```sql
-- ============================================================
-- ATTORNEY REFERRALS
-- ============================================================

CREATE TABLE marketplace.attorney_referrals (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referring_attorney_id       UUID NOT NULL REFERENCES marketplace.attorneys(id),
    receiving_attorney_id       UUID NOT NULL REFERENCES marketplace.attorneys(id),
    case_assignment_id          UUID NOT NULL REFERENCES marketplace.case_assignments(id),
    referral_type               VARCHAR(32) NOT NULL DEFAULT 'jurisdiction_overflow',
        -- jurisdiction_overflow | capacity_overflow | specialty_overflow
        -- practice_area_mismatch | proactive_listing | claimant_request
    referral_reason             TEXT,
    fee_percent                 NUMERIC(5,2) NOT NULL,        -- % of receiving attorney's fee
    fee_type                    VARCHAR(16) NOT NULL DEFAULT 'percent_of_recovery',
        -- percent_of_recovery | flat_fee | percent_of_fee
    flat_fee_amount             NUMERIC(10,2),                -- If flat_fee type

    status                      VARCHAR(32) NOT NULL DEFAULT 'pending',
        -- pending | accepted | declined | active | completed | cancelled | disputed
    offered_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    accepted_at                 TIMESTAMPTZ,
    declined_at                 TIMESTAMPTZ,
    decline_reason              TEXT,
    completed_at                TIMESTAMPTZ,

    -- Fee tracking
    receiving_attorney_fee      NUMERIC(12,2),                -- What receiving attorney earned
    referring_attorney_fee      NUMERIC(12,2),                -- Referral fee paid to referring attorney
    frg_platform_fee            NUMERIC(10,2),                -- Platform transaction fee
    total_case_value            NUMERIC(12,2),                -- Total recovery

    -- Escrow tracking
    escrow_id                   UUID REFERENCES marketplace.referral_escrow(id),
    escrow_status               VARCHAR(16) DEFAULT 'not_required',

    -- Document tracking
    referral_agreement_docuseal_id UUID,                      -- Signed agreement in Docuseal
    agreement_signed_at         TIMESTAMPTZ,

    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_attorney_referrals_referring ON marketplace.attorney_referrals(referring_attorney_id, status);
CREATE INDEX idx_attorney_referrals_receiving ON marketplace.attorney_referrals(receiving_attorney_id, status);
CREATE INDEX idx_attorney_referrals_status ON marketplace.attorney_referrals(status, offered_at);

-- ============================================================
-- REFERRAL ESCROW
-- ============================================================

CREATE TABLE marketplace.referral_escrow (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referral_id                 UUID REFERENCES marketplace.attorney_referrals(id),
    escrow_type                 VARCHAR(32) NOT NULL DEFAULT 'referral_fee',
        -- referral_fee | partner_commission | multi_party_split
    total_amount                NUMERIC(12,2) NOT NULL,
    current_balance             NUMERIC(12,2) NOT NULL,

    -- Distribution plan
    distributions               JSONB NOT NULL DEFAULT '[]',
        -- [{"party_id": "UUID", "party_type": "attorney|partner|referrer",
        --   "amount": 500.00, "percent": 25.00, "status": "pending"}]

    status                      VARCHAR(32) NOT NULL DEFAULT 'funded',
        -- funded | partially_distributed | fully_distributed | released | disputed
    funded_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fully_distributed_at        TIMESTAMPTZ,
    stripe_transfer_ids         JSONB,                        -- Array of Stripe transfer IDs

    -- Dispute handling
    disputed_at                 TIMESTAMPTZ,
    dispute_reason              TEXT,
    dispute_resolution          TEXT,
    dispute_resolved_at         TIMESTAMPTZ,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- CLAIMANT REFERRALS
-- ============================================================

CREATE TABLE marketplace.claimant_referrals (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referring_claimant_id       UUID,                          -- Links to FRGCRM claimant
    referring_case_id           UUID,                          -- The case that identified this claimant
    referred_first_name         VARCHAR(128) NOT NULL,
    referred_last_name          VARCHAR(128) NOT NULL,
    referred_phone              VARCHAR(32),
    referred_email              VARCHAR(256),
    referred_relationship       VARCHAR(64),                   -- family | friend | neighbor | business
    referral_source             VARCHAR(32) DEFAULT 'claimant_portal',
        -- claimant_portal | email_campaign | sms | in_person
    referral_code               VARCHAR(32),                   -- Unique tracking code

    status                      VARCHAR(32) NOT NULL DEFAULT 'submitted',
        -- submitted | contacted | converted | reward_pending | reward_paid | expired
    converted_case_id           UUID REFERENCES marketplace.case_assignments(id),
    reward_type                 VARCHAR(32) DEFAULT 'cash',
        -- cash | fee_reduction | donation
    reward_amount               NUMERIC(10,2),
    reward_paid_at              TIMESTAMPTZ,
    reward_stripe_transfer_id   VARCHAR(128),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_claimant_referrals_referrer ON marketplace.claimant_referrals(referring_claimant_id);

-- ============================================================
-- MULTI-PARTY REVENUE SPLITS
-- ============================================================

CREATE TABLE marketplace.multi_party_splits (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_type                 VARCHAR(32) NOT NULL,
        -- case_assignment | partner_lead | referral | workflow_sale | ai_subscription
    source_id                   UUID NOT NULL,
    total_amount                NUMERIC(12,2) NOT NULL,

    -- N-party split definition
    split_type                  VARCHAR(16) NOT NULL DEFAULT 'percentage',
        -- percentage | fixed_amount | tiered
    parties                     JSONB NOT NULL,
        -- [{"party_id": "UUID", "party_type": "...", "role": "...",
        --   "percentage": 25.00, "amount": null, "status": "pending"}]

    status                      VARCHAR(32) NOT NULL DEFAULT 'pending_distribution',
        -- pending_distribution | distributing | distributed | disputed

    -- Processing
    distribution_batch_id       UUID,                          -- Links to payout batch
    distributed_at              TIMESTAMPTZ,
    stripe_batch_transfer_id    VARCHAR(128),

    -- Audit
    calculation_log             JSONB,                         -- Full calculation trace
    approved_by                 UUID REFERENCES admin.users(id),
    approved_at                 TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## 6. Marketplace 4: Workflow Marketplace

### 6.1 Purpose

The Workflow Marketplace enables legal and financial professionals to discover, purchase, and deploy pre-built n8n workflow templates for common processes. It also offers custom workflow development services for organizations with unique requirements.

### 6.2 Participants

| Side | Participants | Value Proposition | Existing State |
|------|-------------|-------------------|----------------|
| Supply | Workflow Developers | Earn revenue from template sales and custom development | None |
| Demand | Legal/Financial Firms | Instant automation without hiring developers | n8n planned for :5678 |
| Demand | Attorneys (from Marketplace 1) | Automate case management, document workflows | Attorney marketplace active |
| Demand | Partners (from Marketplace 2) | Automate lead submission, commission tracking | Partner marketplace planned |
| Platform | Wheeler Ecosystem | Transaction fee on each sale, subscription revenue | Infrastructure ready |

### 6.3 Existing Infrastructure

| Component | Status | Purpose |
|-----------|--------|---------|
| n8n :5678 | TO BE DEPLOYED | Workflow execution engine |
| Temporal :7233 | HEALTHY | Durable workflow orchestration |
| Neo4j :7687 | HEALTHY | Workflow dependency graph |
| Docuseal :3010 | HEALTHY | Document workflow templates |
| Usesend :3007 | HEALTHY | Email campaign workflows |
| FRGCRM :8082 | ONLINE | CRM workflow triggers |
| LiteLLM :4049 | HEALTHY | AI workflow nodes |

### 6.4 Workflow Template Catalog

**Legal Workflows (Phase 1 Priority):**

| Template | Description | n8n Nodes | Price | Est. Dev Time |
|----------|-------------|-----------|-------|---------------|
| Case Intake Automation | Auto-create FRGCRM case from form submission, send Welcome email, assign attorney | Webhook, FRGCRM, SendGrid, Delay | $49 | 1 day |
| Document Signature Loop | Generate Docuseal agreement, send for signature, track status, notify on completion | Docuseal API, Webhook, SendGrid | $39 | 1 day |
| Deadline Calendar Sync | Extract court deadlines from documents, create calendar events, send reminders | DeepSeek, Google Calendar, SendGrid | $79 | 2 days |
| Claimant Outreach Sequence | Multi-touch email/SMS sequence for new claimants, track responses, route hot leads | Usesend, Twilio, FRGCRM, Router | $59 | 2 days |
| Partner Commission Calculator | Calculate partner commissions on case closure, create Stripe payout, send notification | Webhook, CRON, Stripe, SendGrid | $49 | 1 day |
| Performance Score Updater | Weekly batch performance score calculation, update tiers, send scorecards | CRON, PostgreSQL, SendGrid | $39 | 1 day |

**Financial Workflows (Phase 2):**

| Template | Description | Price |
|----------|-------------|-------|
| Revenue Report Generator | Monthly revenue aggregation by attorney/partner/state, generate PDF report | $49 |
| Payout Batch Processor | Bulk payout calculation and Stripe transfer creation | $79 |
| Subscription Invoice Generator | Automated Stripe invoice creation and dunning for SaaS subscribers | $39 |
| 1099-NEC Preparation | Annual contractor earning aggregation and form generation | $99 |

**AI Workflows (Phase 2):**

| Template | Description | Price |
|----------|-------------|-------|
| Lead Scoring Pipeline | Auto-score new leads via DeepSeek, route high-value leads to priority queue | $99 |
| Document Classification | Classify uploaded documents by type, extract key fields, route to correct folder | $79 |
| Sentiment Analysis | Analyze claimant communication sentiment, flag urgent/high-risk cases | $59 |
| Intelligent Attorney Matching | Score and rank attorneys for each case based on performance and capacity | $129 |

### 6.5 Network Effects

**Cross-Side (Developers <-> Consumers):**
- More workflow templates -> more value for consumers -> more consumers -> more revenue for developers -> attracts more developers -> more templates

**Same-Side (Developer <-> Developer):**
- Positive: template quality improves through competition and ratings
- Positive: developers can build on each other's templates (composable workflows)
- Community features (forums, shared snippets) create knowledge network effects

**Cross-Marketplace Effects:**
- Workflow Marketplace creates operational efficiency for all other marketplaces
- Attorney Marketplace cases trigger workflows; workflows create better outcomes -> more attorneys
- Templates become a distribution channel (developer makes a template -> user discovers Wheeler ecosystem)

### 6.6 Liquidity Bootstrap Strategy

**Phase 1: Platform-Curated Templates (Seed Supply)**
- Wheeler team builds first 10 templates (legal workflows)
- Templates are FREE for first 30 days to drive adoption
- Bundle with attorney and partner marketplace onboarding
- Target: 10 templates, 50 downloads in first month

**Phase 2: Developer Onboarding**
- Open template submission with 70/30 revenue split (developer/platform)
- Template review process (quality, security, documentation standards)
- Recruit 5 initial developers from the n8n community
- Developer incentives: featured placement, free marketplace subscription

**Phase 3: Marketplace Self-Sustaining**
- Developer community grows organically (earnings attract new developers)
- Template ratings and reviews drive quality
- Custom development requests create premium revenue stream
- Enterprise license for full template catalog

### 6.7 Revenue Model

| Revenue Stream | Description | Split | Phase |
|---------------|-------------|-------|-------|
| Template Sale | One-time template purchase | 70% developer, 25% platform, 5% processing | Phase 2+ |
| Template Subscription | All-access pass to template catalog | 60% developers (pooled by usage), 35% platform, 5% processing | Phase 3+ |
| Custom Development | Custom workflow building | 80% developer, 15% platform, 5% processing | Phase 2+ |
| Template Hosting | Hosted n8n execution (no self-hosting) | $49/mo (platform) | Phase 3+ |
| Enterprise License | White-label template catalog | $499/mo (platform) | Phase 3+ |

### 6.8 Trust and Safety

| Mechanism | Implementation | Automated |
|-----------|---------------|-----------|
| Template Review | Security and quality review before publishing | Semi-automated (code scan + human review) |
| Sandbox Testing | Templates tested in isolated n8n environment | Automated |
| User Ratings | 1-5 star rating with mandatory review for <3 stars | Automated |
| Version Control | Template versioning with rollback capability | Automated |
| Dependency Scanning | Check template dependencies for known vulnerabilities | Automated |
| Usage Analytics | Track template failures, errors, performance | Automated |
| Developer Verification | KYC for payout eligibility | Semi-automated |

### 6.9 Technical Architecture

```
Workflow Marketplace (:8150)
    │
    ├── GET /api/v4/templates
    │       Browse workflow templates
    │       Query: category, price_range, rating, sort, page, limit
    │
    ├── GET /api/v4/templates/{id}
    │       Template detail page
    │       Response: { name, description, category, price, rating, downloads,
    │                   screenshots, n8n_workflow_json, requirements }
    │
    ├── POST /api/v4/templates
    │       Submit a new template (developer)
    │       Body: { name, description, category, price, n8n_workflow_json,
    │               screenshots, requirements, documentation }
    │
    ├── POST /api/v4/templates/{id}/purchase
    │       Purchase a template
    │       Body: { payment_method_id }
    │       Response: { download_url, license_key, n8n_import_instructions }
    │
    ├── POST /api/v4/templates/{id}/deploy
    │       Deploy template to user's n8n instance
    │       Response: { workflow_id, status, n8n_endpoint }
    │
    ├── POST /api/v4/custom-workflows/request
    │       Request custom workflow development
    │       Body: { requirements, budget_range, timeline, attachments }
    │       Response: { request_id, estimated_quotes, status }
    │
    ├── POST /api/v4/custom-workflows/{id}/bid
    │       Developer bids on custom workflow request
    │
    ├── GET /api/v4/developers/{id}/dashboard
    │       Developer dashboard: sales, earnings, ratings, downloads
    │
    ├── GET /api/v4/templates/{id}/analytics
    │       Template analytics: downloads, failures, avg rating (template owner only)
    │
    └── WEBHOOK /api/v4/webhooks/template-installed
            Callback when user successfully installs a template
```

### 6.10 Workflow Marketplace Database Schema

```sql
-- ============================================================
-- WORKFLOW TEMPLATES
-- ============================================================

CREATE TABLE marketplace.workflow_templates (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    developer_id                UUID NOT NULL REFERENCES marketplace.workflow_developers(id),
    name                        VARCHAR(256) NOT NULL,
    slug                        VARCHAR(256) UNIQUE NOT NULL,
    description                 TEXT,
    short_description           VARCHAR(512),
    category                    VARCHAR(64) NOT NULL,
        -- legal_intake | document_automation | deadline_tracking
        -- claimant_outreach | commission_calc | reporting
        -- ai_scoring | classification | notification | financial
    tags                        TEXT[],
    price_cents                 INTEGER NOT NULL DEFAULT 0,     -- 0 = free
    subscription_eligible       BOOLEAN DEFAULT FALSE,          -- Included in subscription?
    n8n_workflow_json           JSONB NOT NULL,                  -- The actual n8n workflow definition
    n8n_workflow_version        VARCHAR(32),

    -- Media
    thumbnail_url               VARCHAR(512),
    screenshots                 TEXT[],                          -- Array of URLs
    documentation_url           VARCHAR(512),
    demo_video_url              VARCHAR(512),

    -- Requirements
    required_n8n_version        VARCHAR(32),
    required_nodes              TEXT[],                          -- Required n8n node packages
    dependencies                JSONB,                           -- External API requirements

    -- Status
    status                      VARCHAR(32) NOT NULL DEFAULT 'draft',
        -- draft | pending_review | approved | rejected | published | deprecated | archived
    review_status               VARCHAR(32) DEFAULT 'not_submitted',
        -- not_submitted | under_review | changes_requested | approved | rejected
    review_notes                TEXT,
    reviewed_by                 UUID REFERENCES admin.users(id),
    reviewed_at                 TIMESTAMPTZ,
    published_at                TIMESTAMPTZ,
    deprecated_at               TIMESTAMPTZ,
    deprecation_reason          TEXT,
    version                     INTEGER NOT NULL DEFAULT 1,

    -- Metrics
    download_count              INTEGER DEFAULT 0,
    active_install_count        INTEGER DEFAULT 0,
    average_rating              NUMERIC(3,2) DEFAULT 0,
    rating_count                INTEGER DEFAULT 0,
    failure_rate                NUMERIC(5,4) DEFAULT 0,          -- Percentage of executions that failed

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_workflow_templates_category ON marketplace.workflow_templates(category, status);
CREATE INDEX idx_workflow_templates_developer ON marketplace.workflow_templates(developer_id);
CREATE INDEX idx_workflow_templates_status ON marketplace.workflow_templates(status);
CREATE INDEX idx_workflow_templates_rating ON marketplace.workflow_templates(average_rating DESC);

-- ============================================================
-- WORKFLOW DEVELOPERS
-- ============================================================

CREATE TABLE marketplace.workflow_developers (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                     UUID REFERENCES admin.users(id),
    display_name                VARCHAR(128) NOT NULL,
    email                       VARCHAR(256) NOT NULL,
    bio                         TEXT,
    avatar_url                  VARCHAR(512),
    website                     VARCHAR(512),
    github_profile              VARCHAR(256),
    n8n_community_handle        VARCHAR(128),

    -- Verification
    verification_status         VARCHAR(32) DEFAULT 'unverified',
        -- unverified | pending | verified | suspended
    kyc_completed               BOOLEAN DEFAULT FALSE,
    stripe_connect_account_id   VARCHAR(64),
    tax_info_collected          BOOLEAN DEFAULT FALSE,

    -- Revenue
    total_earnings_cents        INTEGER DEFAULT 0,
    pending_earnings_cents      INTEGER DEFAULT 0,
    lifetime_payouts_cents      INTEGER DEFAULT 0,
    revenue_share_percent       NUMERIC(5,2) DEFAULT 70.00,      -- Developer's share

    -- Metrics
    template_count              INTEGER DEFAULT 0,
    total_downloads             INTEGER DEFAULT 0,
    average_rating              NUMERIC(3,2) DEFAULT 0,
    response_rate               NUMERIC(5,2),                    -- % of support questions answered
    response_time_hours         NUMERIC(8,2),                    -- Average response time

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TEMPLATE PURCHASES AND INSTALLATIONS
-- ============================================================

CREATE TABLE marketplace.template_purchases (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id                 UUID NOT NULL REFERENCES marketplace.workflow_templates(id),
    purchaser_type              VARCHAR(32) NOT NULL,            -- attorney | partner | firm | developer
    purchaser_id                UUID NOT NULL,                   -- Polymorphic reference
    purchase_type               VARCHAR(16) NOT NULL DEFAULT 'one_time',
        -- one_time | subscription | enterprise_license
    price_paid_cents            INTEGER NOT NULL,
    platform_fee_cents          INTEGER NOT NULL,
    developer_earnings_cents    INTEGER NOT NULL,
    license_key                 VARCHAR(128) UNIQUE,
    status                      VARCHAR(32) NOT NULL DEFAULT 'active',
        -- active | expired | revoked | refunded
    refunded_at                 TIMESTAMPTZ,
    refund_reason               TEXT,
    n8n_workflow_id             VARCHAR(128),                    -- ID in user's n8n instance
    installation_status         VARCHAR(32) DEFAULT 'not_installed',
        -- not_installed | installing | installed | failed | uninstalled
    installed_at                TIMESTAMPTZ,
    last_used_at                TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_template_purchases_template ON marketplace.template_purchases(template_id);
CREATE INDEX idx_template_purchases_purchaser ON marketplace.template_purchases(purchaser_type, purchaser_id);

-- ============================================================
-- TEMPLATE RATINGS AND REVIEWS
-- ============================================================

CREATE TABLE marketplace.template_reviews (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id                 UUID NOT NULL REFERENCES marketplace.workflow_templates(id),
    purchase_id                 UUID NOT NULL REFERENCES marketplace.template_purchases(id),
    rating                      SMALLINT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    title                       VARCHAR(256),
    review_text                 TEXT,
    pros                        TEXT,
    cons                        TEXT,
    verified_purchase           BOOLEAN DEFAULT TRUE,
    helpful_count               INTEGER DEFAULT 0,
    status                      VARCHAR(32) DEFAULT 'published',
        -- published | flagged | hidden | removed
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(purchase_id)
);

-- ============================================================
-- CUSTOM WORKFLOW REQUESTS
-- ============================================================

CREATE TABLE marketplace.custom_workflow_requests (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_type              VARCHAR(32) NOT NULL,            -- attorney | partner | firm
    requester_id                UUID NOT NULL,
    title                       VARCHAR(256) NOT NULL,
    description                 TEXT NOT NULL,
    use_case                    TEXT,
    preferred_technologies      TEXT[],
    budget_range_min_cents      INTEGER,
    budget_range_max_cents      INTEGER,
    desired_timeline            VARCHAR(64),                     -- urgent | standard | flexible
    attachments                 TEXT[],                           -- Reference docs/files
    status                      VARCHAR(32) NOT NULL DEFAULT 'open',
        -- open | reviewing | bidding | in_progress | completed | cancelled
    awarded_to                  UUID REFERENCES marketplace.workflow_developers(id),
    awarded_at                  TIMESTAMPTZ,
    final_price_cents           INTEGER,
    completed_at                TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## 7. Marketplace 5: AI Automation Marketplace

### 7.1 Purpose

The AI Automation Marketplace enables the distribution and monetization of Claude Code agent templates, AI workflow products, and managed agent subscriptions. It transforms the Wheeler Brain OS's 50-agent ecosystem into a product platform that legal and financial professionals can leverage without building their own AI infrastructure.

### 7.2 Participants

| Side | Participants | Value Proposition | Existing State |
|------|-------------|-------------------|----------------|
| Supply | AI Developers | Monetize Claude Code agent templates and AI workflows | Wheeler has 50 internal agents |
| Demand | Legal/Financial Firms | Instant AI capabilities without hiring ML engineers | None |
| Demand | Attorneys | Automate case research, document review, compliance monitoring | Attorney marketplace active |
| Demand | Partners | AI-powered lead scoring, market analysis | Partner marketplace planned |
| Platform | Wheeler Ecosystem | Infrastructure, LiteLLM access, subscription management | LiteLLM :4049, DeepSeek API |

### 7.3 Existing Infrastructure

| Component | Status | Purpose |
|-----------|--------|---------|
| LiteLLM :4049 | HEALTHY | AI model gateway (DeepSeek V4 Flash) |
| DeepSeek API | CONFIGURED | Primary LLM for all AI features |
| Claude Code Agents | 50 AGENTS | Internal agent templates (reusable patterns) |
| Command Center :8100 | ONLINE | Agent orchestration and management |
| Neo4j :7687 | HEALTHY | Agent knowledge graph |
| Temporal :7233 | HEALTHY | Agent workflow orchestration |
| n8n :5678 | PLANNED | AI workflow triggers and integrations |

### 7.4 Agent Template Catalog

**Legal Agent Templates (Phase 1):**

| Template | Description | Base Agent | Price |
|----------|-------------|------------|-------|
| Contract Review Agent | Analyze contracts for risks, obligations, compliance issues | Claude Code | $199/mo |
| Case Research Agent | Research relevant case law, statutes, and regulations | Claude Code | $149/mo |
| Document Discovery Agent | Process discovery documents, identify relevant evidence | Claude Code | $299/mo |
| Compliance Monitoring Agent | Monitor regulatory changes, flag compliance gaps | Claude Code | $249/mo |
| Deadline Tracking Agent | Extract and monitor court deadlines across all cases | Claude Code | $99/mo |
| Legal Brief Drafting Agent | Draft legal briefs from case facts and research | Claude Code | $299/mo |

**Financial Agent Templates (Phase 1):**

| Template | Description | Price |
|----------|-------------|-------|
| Market Intelligence Agent | Monitor market signals, generate daily briefings | $199/mo |
| Risk Assessment Agent | Score investment opportunities by risk factors | $149/mo |
| Portfolio Analysis Agent | Analyze portfolio composition and performance | $99/mo |
| Due Diligence Agent | Automate due diligence document review | $299/mo |

**Wheeler-Branded AI Products (Phase 2):**

| Product | Description | Price | Powered By |
|---------|-------------|-------|------------|
| SurplusAI Intelligence | Automated surplus fund lead generation and scoring | $997/mo | SurplusAI scraper + DeepSeek |
| Prediction Radar Pro | AI-powered market predictions and signals | $49/mo Pro, $199/mo Agency | Prediction Radar + DeepSeek |
| Attorney AI Assistant | Full-suite AI for attorneys (case research + docs + deadlines) | $499/mo | 5+ agent templates bundled |
| Lead Intelligence Pro | Automated lead qualification and routing | $997/mo | Horizon agent + DeepSeek |

### 7.5 Network Effects

**Cross-Side (Developers <-> Subscribers):**
- More agent templates -> more use cases -> more subscribers -> more revenue for developers -> attracts more developers -> more specialized templates

**Same-Side (Agent <-> Agent):**
- Strong positive: agents can be chained together (e.g., Research Agent -> Brief Drafting Agent -> Review Agent)
- Agent composition creates exponentially more value than individual agents
- Template marketplace with API hooks enables agent-to-agent communication patterns

**Cross-Marketplace Effects:**
- AI Marketplace templates integrate with all other marketplaces
- Attorney AI Assistant directly improves attorney performance (-> higher tier -> more fees)
- Partner AI tools improve lead quality (-> better conversion -> more revenue)

### 7.6 Liquidity Bootstrap Strategy

The AI Automation Marketplace has the strongest existing supply-side advantage: Wheeler already operates 50 Claude Code agents. This eliminates the chicken-and-egg problem on the supply side.

**Phase 1: Internal Templates as Products**
- Package 5 internal Wheeler agents as commercial products (redact internal references, add documentation, create onboarding)
- Offer 30-day free trial to first 20 attorneys in the Attorney Marketplace
- Use LiteLLM usage data to price accurately (cost + margin)
- Target: 5 templates, 10 subscribers, $5K MRR in first month

**Phase 2: External Developer Onboarding**
- Open agent template submission (similar to workflow marketplace pattern)
- Developer receives 70% of subscription revenue for their templates
- Template review process: security audit, quality review, documentation standards
- Claude Code agent SDK documentation and template starter kit

**Phase 3: Managed Agent Subscriptions**
- "Agent as a Service" -- Wheeler hosts and manages AI agents for clients
- Includes LiteLLM access, agent updates, monitoring, support
- Tiered pricing based on agent count and usage volume

### 7.7 Revenue Model

| Revenue Stream | Description | Split | Phase |
|---------------|-------------|-------|-------|
| Agent Template Subscription | Monthly subscription per agent template | 70% developer, 25% platform, 5% processing | Phase 2+ |
| Bundled AI Products | Multi-agent subscriptions (e.g., Attorney AI Assistant) | Platform (80%), developers (20% pooled) | Phase 2+ |
| Managed Agent Hosting | Hosted agent execution (no self-hosting) | Platform (100%) | Phase 2+ |
| Usage-Based AI | Pay-per-inference for high-volume users | $0.001-0.01/inference | Phase 3+ |
| Custom Agent Development | Bespoke agent building for enterprise clients | 80% developer, 20% platform | Phase 2+ |
| LiteLLM Proxy Access | External access to LiteLLM gateway | $99/mo (100K tokens incl.) | Phase 3+ |

### 7.8 Trust and Safety

| Mechanism | Implementation | Automated |
|-----------|---------------|-----------|
| Agent Sandboxing | Agents run in isolated environments with resource limits | Automated |
| Prompt Injection Protection | Input sanitization, output validation for all agent templates | Automated |
| Data Privacy Controls | Configurable data retention, PII redaction options | Automated |
| Agent Monitoring | Execution logging, cost tracking, anomaly detection | Automated |
| Template Review | Security audit and quality review before publishing | Semi-automated |
| Usage Limits | Per-subscriber rate limiting to prevent abuse | Automated |
| Audit Trail | Full execution history per subscriber | Automated |

### 7.9 Technical Architecture

```
AI Automation Marketplace (:8160)
    │
    ├── GET /api/v5/agents
    │       Browse AI agent templates and products
    │       Query: category, price_range, rating, sort, page, limit
    │
    ├── GET /api/v5/agents/{id}
    │       Agent detail page
    │       Response: { name, description, category, price, rating,
    │                   subscribers, capabilities, requirements }
    │
    ├── POST /api/v5/agents/{id}/subscribe
    │       Subscribe to an agent template
    │       Body: { payment_method_id, tier }
    │       Response: { subscription_id, status, api_endpoint,
    │                   api_key, agent_dashboard_url }
    │
    ├── POST /api/v5/agents
    │       Submit an agent template (developer)
    │       Body: { name, description, category, price, agent_definition,
    │               screenshots, documentation, capabilities }
    │
    ├── POST /api/v5/agents/{id}/execute
    │       Execute an agent task (subscriber)
    │       Body: { input, parameters, context }
    │       Response: { execution_id, status, output, tokens_used, cost }
    │
    ├── GET /api/v5/agents/{id}/usage
    │       Usage analytics for subscribed agent
    │       Response: { executions, tokens, cost, avg_response_time }
    │
    ├── POST /api/v5/bundles/{id}/subscribe
    │       Subscribe to a bundled AI product
    │       Response: { all_agent_endpoints, shared_context, dashboard_url }
    │
    ├── POST /api/v5/custom-agents/request
    │       Request custom agent development
    │       Body: { requirements, use_cases, data_access_needed, budget }
    │
    └── GET /api/v5/developers/{id}/dashboard
            Developer dashboard: subscribers, revenue, usage, ratings
```

### 7.10 AI Automation Marketplace Database Schema

```sql
-- ============================================================
-- AI AGENT TEMPLATES
-- ============================================================

CREATE TABLE marketplace.ai_agent_templates (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    developer_id                UUID REFERENCES marketplace.ai_developers(id),
    name                        VARCHAR(256) NOT NULL,
    slug                        VARCHAR(256) UNIQUE NOT NULL,
    description                 TEXT,
    short_description           VARCHAR(512),
    category                    VARCHAR(64) NOT NULL,
        -- legal_research | document_review | compliance | deadlines
        -- financial_analysis | risk_assessment | market_intelligence
        -- lead_scoring | communication | custom
    tags                        TEXT[],
    capabilities                JSONB,            -- { "capability": "description", ... }

    -- Pricing
    price_cents_per_month       INTEGER NOT NULL DEFAULT 0,
    usage_included_tokens       INTEGER DEFAULT 100000,          -- Monthly included tokens
    additional_token_rate       NUMERIC(10,8),                   -- Per-token cost beyond included
    subscription_available      BOOLEAN DEFAULT TRUE,

    -- Agent definition
    agent_type                  VARCHAR(64) NOT NULL DEFAULT 'claude_code',
        -- claude_code | custom_python | langchain | crewai
    agent_definition            JSONB NOT NULL,                  -- Agent configuration
    system_prompt_template      TEXT,                            -- System prompt (redacted for listing)
    required_tools              TEXT[],                          -- API tools the agent needs
    litemll_model               VARCHAR(64) DEFAULT 'deepseek-chat',
    max_tokens_per_execution    INTEGER DEFAULT 32000,
    context_window              INTEGER DEFAULT 128000,

    -- Media and docs
    thumbnail_url               VARCHAR(512),
    screenshots                 TEXT[],
    documentation_url           VARCHAR(512),
    demo_video_url              VARCHAR(512),
    setup_guide                 TEXT,

    -- Status
    status                      VARCHAR(32) NOT NULL DEFAULT 'draft',
        -- draft | pending_review | approved | rejected | published | deprecated | archived
    reviewed_by                 UUID REFERENCES admin.users(id),
    reviewed_at                 TIMESTAMPTZ,
    published_at                TIMESTAMPTZ,
    version                     INTEGER NOT NULL DEFAULT 1,

    -- Metrics
    subscriber_count            INTEGER DEFAULT 0,
    total_executions            INTEGER DEFAULT 0,
    total_tokens_used           BIGINT DEFAULT 0,
    average_rating              NUMERIC(3,2) DEFAULT 0,
    rating_count                INTEGER DEFAULT 0,
    average_execution_time_ms   INTEGER DEFAULT 0,
    success_rate                NUMERIC(5,4) DEFAULT 1.0000,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ai_agent_templates_category ON marketplace.ai_agent_templates(category, status);
CREATE INDEX idx_ai_agent_templates_rating ON marketplace.ai_agent_templates(average_rating DESC);

-- ============================================================
-- AGENT SUBSCRIPTIONS
-- ============================================================

CREATE TABLE marketplace.agent_subscriptions (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_template_id           UUID NOT NULL REFERENCES marketplace.ai_agent_templates(id),
    subscriber_type             VARCHAR(32) NOT NULL,            -- attorney | partner | firm
    subscriber_id               UUID NOT NULL,
    subscription_tier           VARCHAR(32) NOT NULL DEFAULT 'standard',
        -- standard | pro | enterprise
    status                      VARCHAR(32) NOT NULL DEFAULT 'active',
        -- active | trialing | past_due | canceled | expired
    current_period_start        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    current_period_end          TIMESTAMPTZ,
    canceled_at                 TIMESTAMPTZ,

    -- Usage tracking
    tokens_used_this_period     BIGINT DEFAULT 0,
    executions_this_period      INTEGER DEFAULT 0,
    overage_tokens              BIGINT DEFAULT 0,
    overage_charges_cents       INTEGER DEFAULT 0,

    -- API access
    api_key_hash                VARCHAR(256),                    -- Hashed API key for agent access
    webhook_url                 VARCHAR(512),                    -- Callback URL for async results

    -- Billing
    stripe_subscription_id      VARCHAR(128),
    stripe_price_id             VARCHAR(128),
    price_cents_per_month       INTEGER NOT NULL,
    next_billing_date           DATE,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_agent_subscriptions_agent ON marketplace.agent_subscriptions(agent_template_id, status);
CREATE INDEX idx_agent_subscriptions_subscriber ON marketplace.agent_subscriptions(subscriber_type, subscriber_id);

-- ============================================================
-- AGENT EXECUTION LOGS
-- ============================================================

CREATE TABLE marketplace.agent_execution_logs (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id             UUID NOT NULL REFERENCES marketplace.agent_subscriptions(id),
    agent_template_id           UUID NOT NULL REFERENCES marketplace.ai_agent_templates(id),
    execution_type              VARCHAR(32) NOT NULL DEFAULT 'interactive',
        -- interactive | scheduled | webhook | batch
    input_summary               VARCHAR(512),                    -- Truncated input description
    output_summary              VARCHAR(512),                    -- Truncated output description
    tokens_used                 INTEGER NOT NULL DEFAULT 0,
    execution_time_ms           INTEGER NOT NULL DEFAULT 0,
    model_used                  VARCHAR(64),
    status                      VARCHAR(32) NOT NULL DEFAULT 'completed',
        -- completed | failed | cancelled | timeout
    error_message               TEXT,
    cost_cents                  NUMERIC(10,6) DEFAULT 0,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_agent_execution_logs_subscription ON marketplace.agent_execution_logs(subscription_id, created_at DESC);
CREATE INDEX idx_agent_execution_logs_agent ON marketplace.agent_execution_logs(agent_template_id, created_at DESC);

-- ============================================================
-- AI DEVELOPERS
-- ============================================================

CREATE TABLE marketplace.ai_developers (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                     UUID REFERENCES admin.users(id),
    display_name                VARCHAR(128) NOT NULL,
    email                       VARCHAR(256) NOT NULL,
    bio                         TEXT,
    avatar_url                  VARCHAR(512),
    github_profile              VARCHAR(256),
    claude_code_experience      VARCHAR(64),                     -- beginner | intermediate | expert

    verification_status         VARCHAR(32) DEFAULT 'unverified',
    kyc_completed               BOOLEAN DEFAULT FALSE,
    stripe_connect_account_id   VARCHAR(64),

    total_earnings_cents        INTEGER DEFAULT 0,
    pending_earnings_cents      INTEGER DEFAULT 0,
    revenue_share_percent       NUMERIC(5,2) DEFAULT 70.00,

    agent_count                 INTEGER DEFAULT 0,
    total_subscribers           INTEGER DEFAULT 0,
    average_rating              NUMERIC(3,2) DEFAULT 0,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## 8. Cross-Marketplace Integration Layer

### 8.1 Shared Identity and Profile Service

All five marketplaces share a unified identity system. A participant can have multiple roles (e.g., an attorney who is also a partner and a workflow developer).

```sql
-- ============================================================
-- SHARED IDENTITY
-- ============================================================

CREATE TABLE marketplace.identities (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email                       VARCHAR(256) UNIQUE NOT NULL,
    phone                       VARCHAR(32),
    password_hash               VARCHAR(256),                    -- For email+password login
    auth_type                   VARCHAR(32) NOT NULL DEFAULT 'magic_link',
        -- magic_link | email_password | google_oauth | api_key
    email_verified              BOOLEAN DEFAULT FALSE,
    phone_verified              BOOLEAN DEFAULT FALSE,
    mfa_enabled                 BOOLEAN DEFAULT FALSE,
    mfa_secret                  VARCHAR(256),                    -- TOTP secret

    -- Unified profile
    display_name                VARCHAR(256),
    avatar_url                  VARCHAR(512),
    preferred_language          VARCHAR(8) DEFAULT 'en',
    timezone                    VARCHAR(64) DEFAULT 'America/New_York',

    -- Roles (an identity can have multiple)
    roles                       TEXT[] NOT NULL DEFAULT '{}',
        -- attorney | partner | referrer | workflow_developer | ai_developer | claimant | admin

    -- Cross-marketplace reputation
    overall_rating              NUMERIC(3,2),                    -- Weighted average across all marketplaces
    total_transactions          INTEGER DEFAULT 0,
    total_revenue_cents         BIGINT DEFAULT 0,
    account_age_days            INTEGER DEFAULT 0,
    trust_score                 NUMERIC(5,2),                    -- Internal trust score 0-100

    -- Status
    status                      VARCHAR(32) NOT NULL DEFAULT 'active',
        -- active | suspended | deactivated | banned
    suspension_reason           TEXT,
    last_login_at               TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Cross-reference table linking identities to marketplace-specific profiles
CREATE TABLE marketplace.identity_links (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    identity_id                 UUID NOT NULL REFERENCES marketplace.identities(id),
    marketplace                 VARCHAR(32) NOT NULL,
        -- attorney | partner | referral | workflow | ai
    profile_id                  UUID NOT NULL,                    -- Polymorphic reference
    profile_type                VARCHAR(32) NOT NULL,             -- Table name
    role                        VARCHAR(64),                      -- Role within that marketplace
    joined_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(identity_id, marketplace)
);
```

### 8.2 Unified Payout Engine

The unified payout engine at :8170 handles all financial transactions across all five marketplaces:

```sql
-- ============================================================
-- UNIFIED PAYOUT ENGINE
-- ============================================================

CREATE TYPE payout_source_type AS ENUM (
    'case_assignment',      -- Attorney Marketplace: case completion
    'partner_lead',         -- Partner Marketplace: lead conversion
    'attorney_referral',    -- Referral Marketplace: referral fee
    'claimant_referral',    -- Referral Marketplace: claimant referral reward
    'template_sale',        -- Workflow Marketplace: template purchase
    'custom_workflow',      -- Workflow Marketplace: custom development
    'agent_subscription',   -- AI Marketplace: agent subscription
    'agent_usage',          -- AI Marketplace: usage overage
    'ai_product_sale',      -- AI Marketplace: bundled product
    'frg_platform_fee'      -- Platform: transaction fee retained by FRG
);

CREATE TABLE marketplace.unified_payouts (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payout_type                 payout_source_type NOT NULL,
    source_id                   UUID NOT NULL,                    -- Polymorphic reference to source
    source_table                VARCHAR(64) NOT NULL,             -- Table name of source

    -- Amounts
    gross_amount                NUMERIC(12,2) NOT NULL,
    platform_fee                NUMERIC(10,2) NOT NULL,           -- Wheeler ecosystem fee
    processing_fee              NUMERIC(8,2) DEFAULT 0,          -- Stripe/payment processing
    net_amount                  NUMERIC(12,2) NOT NULL,           -- Amount for distribution

    -- Distribution
    distributions               JSONB NOT NULL,
        -- [{"identity_id": "UUID", "role": "attorney|partner|developer|referrer|platform",
        --   "amount": 500.00, "percent": 25.00, "status": "pending"}]

    status                      VARCHAR(32) NOT NULL DEFAULT 'pending',
        -- pending | approved | processing | completed | failed | reversed
    batch_id                    UUID REFERENCES marketplace.payout_batches(id),

    -- Stripe tracking
    stripe_transfer_ids         JSONB,                            -- Array of Stripe transfer IDs
    stripe_payout_ids           JSONB,                            -- Array of Stripe payout IDs

    -- Timing
    approved_at                 TIMESTAMPTZ,
    processing_at               TIMESTAMPTZ,
    completed_at                TIMESTAMPTZ,
    failed_at                   TIMESTAMPTZ,
    failure_reason              TEXT,

    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE marketplace.payout_batches (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_type                  VARCHAR(32) NOT NULL,
        -- weekly_payouts | monthly_payouts | manual_batch | emergency
    period_start                DATE NOT NULL,
    period_end                  DATE NOT NULL,
    total_gross                 NUMERIC(14,2) DEFAULT 0,
    total_fees                  NUMERIC(12,2) DEFAULT 0,
    total_net                   NUMERIC(14,2) DEFAULT 0,
    payout_count                INTEGER DEFAULT 0,
    status                      VARCHAR(32) NOT NULL DEFAULT 'calculating',
        -- calculating | ready_for_approval | approved | processing | completed | failed
    approved_by                 UUID REFERENCES admin.users(id),
    approved_at                 TIMESTAMPTZ,
    processed_at                TIMESTAMPTZ,
    completed_at                TIMESTAMPTZ,
    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 1099-NEC TRACKING
-- ============================================================

CREATE TABLE marketplace.tax_records (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    identity_id                 UUID NOT NULL REFERENCES marketplace.identities(id),
    tax_year                    SMALLINT NOT NULL,
    total_payouts_cents         BIGINT NOT NULL DEFAULT 0,
    total_transactions          INTEGER NOT NULL DEFAULT 0,
    platform_fees_paid_cents    BIGINT NOT NULL DEFAULT 0,
    needs_1099                  BOOLEAN GENERATED ALWAYS AS (total_payouts_cents >= 60000) STORED,
         -- $600 threshold for 1099-NEC
    1099_generated              BOOLEAN DEFAULT FALSE,
    1099_generated_at           TIMESTAMPTZ,
    1099_docuseal_id            UUID,
    1099_delivered              BOOLEAN DEFAULT FALSE,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(identity_id, tax_year)
);
```

### 8.3 Neo4j Ecosystem Graph Integration

The Neo4j instance at :7687 powers cross-marketplace relationship discovery and AI routing.

```cypher
// Graph schema for marketplace relationships

// Participants
CREATE CONSTRAINT participant_id IF NOT EXISTS
FOR (p:Participant) REQUIRE p.identity_id IS UNIQUE;

// Relationship types
// (:Participant)-[:IS_ATTORNEY]->(:AttorneyProfile)
// (:Participant)-[:IS_PARTNER]->(:PartnerProfile)
// (:Participant)-[:IS_DEVELOPER]->(:WorkflowDeveloper)
// (:Participant)-[:IS_AI_DEVELOPER]->(:AIDeveloper)

// Transaction relationships
// (:AttorneyProfile)-[:REFERRED_CASE]->(:Case)-[:ASSIGNED_TO]->(:AttorneyProfile)
// (:PartnerProfile)-[:SUBMITTED_LEAD]->(:Lead)-[:CONVERTED_TO]->(:Case)
// (:Participant)-[:PURCHASED]->(:WorkflowTemplate)
// (:Participant)-[:SUBSCRIBED]->(:AgentTemplate)

// Cross-marketplace queries enabled by graph:
// 1. Find all attorneys who are also workflow developers (cross-marketplace power users)
// 2. Find partners who submitted leads that became referrals (partner -> referral chain)
// 3. Find AI template subscribers who also purchased workflow templates (upsell opportunities)
// 4. Trust network: find participants with >N successful transactions across all marketplaces
```

### 8.4 Cross-Marketplace Referral Flows

The marketplaces are designed to feed each other:

```
Attorney Marketplace (Primary)
    │
    ├── Overflow cases (attorney at capacity) ─────> Referral Marketplace
    │                                                   │
    ├── Attorneys need AI tools ──────────────> AI Automation Marketplace
    │                                                   │
    ├── Attorneys use workflow templates ──────> Workflow Marketplace
    │
    └── Attorneys refer partners ─────────────> Partner Marketplace
                                                    │
                                                    └── Partner leads ──> Attorney Marketplace
                                                                              │
                                                                              └── More overflow ──> Referral Marketplace

Workflow Marketplace
    │
    └── Workflow users discover Wheeler ecosystem ──> Attorney Marketplace
                                                       │
                                                       └── Case completion ──> Revenue shared across all touchpoints
```

### 8.5 Event Bus Integration

The existing event bus relay distributes cross-marketplace events:

```json
{
  "marketplace.case.assigned": {
    "description": "A case was assigned to an attorney",
    "consumers": ["attorney-marketplace", "referral-marketplace", "workflow-marketplace"],
    "payload": {
      "case_id": "UUID",
      "attorney_id": "UUID",
      "assignment_method": "ai_ranked",
      "routing_score": 87.5
    }
  },
  "marketplace.case.completed": {
    "description": "A case was completed (recovery made)",
    "consumers": ["attorney-marketplace", "partner-marketplace", "referral-marketplace", "payout-engine"],
    "payload": {
      "case_id": "UUID",
      "recovery_amount": 15000.00,
      "attorney_id": "UUID",
      "partner_id": "UUID?",
      "referral_id": "UUID?"
    }
  },
  "marketplace.partner.lead.converted": {
    "description": "A partner-submitted lead converted to a case",
    "consumers": ["partner-marketplace", "payout-engine"],
    "payload": {
      "partner_id": "UUID",
      "lead_id": "UUID",
      "case_id": "UUID"
    }
  },
  "marketplace.referral.completed": {
    "description": "An attorney referral resulted in a closed case",
    "consumers": ["referral-marketplace", "payout-engine", "neo4j-graph"],
    "payload": {
      "referral_id": "UUID",
      "referring_attorney_id": "UUID",
      "receiving_attorney_id": "UUID",
      "fee_amount": 500.00
    }
  },
  "marketplace.template.purchased": {
    "description": "A workflow template was purchased",
    "consumers": ["workflow-marketplace", "payout-engine"],
    "payload": {
      "template_id": "UUID",
      "developer_id": "UUID",
      "purchaser_id": "UUID",
      "price": 49.00
    }
  },
  "marketplace.ai.subscription.activated": {
    "description": "An AI agent subscription was activated",
    "consumers": ["ai-marketplace", "payout-engine", "litellm-proxy"],
    "payload": {
      "subscription_id": "UUID",
      "agent_template_id": "UUID",
      "subscriber_id": "UUID"
    }
  }
}
```

---

## 9. API Gateway and Routing

### 9.1 Traefik Routing Configuration

All marketplace APIs route through Traefik on the EDGE node:

```yaml
# Traefik dynamic configuration for marketplace services
http:
  routers:
    attorney-marketplace-api:
      rule: "Host(`fundsrecoverygroup.com`) && PathPrefix(`/api/marketplace/attorney`)"
      service: attorney-marketplace-api
      middlewares:
        - rate-limit
        - auth-headers
        - cors-marketplace

    partner-marketplace-api:
      rule: "Host(`fundsrecoverygroup.com`) && PathPrefix(`/api/marketplace/partner`)"
      service: partner-marketplace-api
      middlewares:
        - rate-limit
        - auth-headers
        - cors-marketplace

    referral-marketplace-api:
      rule: "Host(`fundsrecoverygroup.com`) && PathPrefix(`/api/marketplace/referral`)"
      service: referral-marketplace-api
      middlewares:
        - rate-limit
        - auth-headers
        - cors-marketplace

    workflow-marketplace-api:
      rule: "Host(`fundsrecoverygroup.com`) && PathPrefix(`/api/marketplace/workflow`)"
      service: workflow-marketplace-api
      middlewares:
        - rate-limit
        - auth-headers
        - cors-marketplace

    ai-marketplace-api:
      rule: "Host(`fundsrecoverygroup.com`) && PathPrefix(`/api/marketplace/ai`)"
      service: ai-marketplace-api
      middlewares:
        - rate-limit
        - auth-headers
        - cors-marketplace

    unified-payout-api:
      rule: "Host(`fundsrecoverygroup.com`) && PathPrefix(`/api/marketplace/payout`)"
      service: unified-payout-engine
      middlewares:
        - rate-limit
        - admin-auth

  services:
    attorney-marketplace-api:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8120"

    partner-marketplace-api:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8130"

    referral-marketplace-api:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8140"

    workflow-marketplace-api:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8150"

    ai-marketplace-api:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8160"

    unified-payout-engine:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8170"
```

---

## 10. Implementation Phases

### 10.1 Phase 1: Attorney Marketplace Foundation (Weeks 1-4)

**Goal:** Replace manual attorney management with database-backed marketplace core.

**Deliverables:**
- [ ] PostgreSQL database `marketplace` schema on AIOPS local PG or COREDB
- [ ] Attorney tables (profiles, bar licenses, practice areas, availability)
- [ ] Case assignment tables with full status workflow
- [ ] PM2 service: Attorney Marketplace API (:8120) -- basic CRUD
- [ ] Seed data: 4 existing attorneys (Bigham, Morris, Farah, Walker)
- [ ] Admin API endpoints for attorney management
- [ ] Case assignment status workflow (pending -> offered -> accepted -> active -> completed)
- [ ] Basic audit log
- [ ] Migration path from FRGCRM hardcoded list to marketplace database

**Liquidity Milestone:** 4 active attorneys, 50+ cases tracked in system.

### 10.2 Phase 2: Attorney Self-Service + Partner Onboarding (Weeks 5-8)

**Goal:** Attorneys register themselves; partner marketplace launched with initial partners.

**Deliverables:**
- [ ] Attorney self-service registration with bar license submission
- [ ] Docuseal revenue sharing agreement generation (:3010)
- [ ] Semi-automated bar license verification (DeepSeek-assisted)
- [ ] Attorney onboarding flow complete
- [ ] Partner Marketplace API (:8130) -- partner registration, lead submission, commission tracking
- [ ] Partner tables and database schema
- [ ] 5 real estate agent + 2 title company partners onboarded
- [ ] Partner portal frontend (:8131) -- basic dashboard
- [ ] Partner lead submission workflow
- [ ] PM2 services: Attorney Onboarding Worker (:8122), License Verification Worker (:8123)

**Liquidity Milestone:** 15+ active attorneys, 5+ partners, first partner-led case conversion.

### 10.3 Phase 3: AI Routing + Revenue Sharing + Referral Marketplace (Weeks 9-12)

**Goal:** Automated AI routing, revenue sharing payouts, and referral network launch.

**Deliverables:**
- [ ] AI routing engine (DeepSeek via LiteLLM :4049) with fallback chain
- [ ] Performance scoring engine (7-factor composite -> PLATINUM/GOLD/SILVER/BRONZE)
- [ ] Revenue share agreements with configurable splits
- [ ] Stripe Connect integration for attorney payments
- [ ] Automated payout calculation and processing
- [ ] Referral Marketplace API (:8140) -- referral creation, matching, escrow
- [ ] Referral tables and database schema
- [ ] Attorney-to-attorney referral workflow
- [ ] Multi-party revenue split engine
- [ ] n8n deployment (:5678) with initial workflow templates
- [ ] PM2 services: Revenue Share Engine (:8124), Referral Marketplace API (:8140)

**Liquidity Milestone:** 30+ attorneys, 80% auto-routing rate, first referral completed, first payout processed.

### 10.4 Phase 4: Portals + Document Automation + Workflow Marketplace (Weeks 13-16)

**Goal:** Full participant portals, automated document workflows, and workflow template marketplace.

**Deliverables:**
- [ ] Attorney portal frontend (:8121) -- full dashboard, cases, revenue, documents
- [ ] Partner portal frontend (:8131) -- lead tracking, commissions, analytics
- [ ] Referral portal frontend (:8141) -- incoming/outgoing referrals, escrow tracking
- [ ] Document automation via Docuseal (:3010) for all document types
- [ ] Document generation, signature workflow, and status tracking
- [ ] Workflow Marketplace API (:8150)
- [ ] Workflow template catalog with n8n integration
- [ ] 10 platform-curated workflow templates
- [ ] Template purchase and deployment workflow
- [ ] Email magic link auth for all portals
- [ ] PM2 services: Attorney Frontend (:8121), Document Automation Worker (:8125), Workflow Marketplace API (:8150)

**Liquidity Milestone:** 50+ attorneys, 15+ partners, 10 workflow templates, 25+ template downloads.

### 10.5 Phase 5: AI Automation Marketplace + Unified Payout Engine (Weeks 17-20)

**Goal:** AI agent templates commercialized; unified payout engine across all marketplaces.

**Deliverables:**
- [ ] AI Automation Marketplace API (:8160)
- [ ] 5 internal Wheeler agents packaged as commercial products
- [ ] Agent template submission and review workflow
- [ ] Agent subscription and usage tracking
- [ ] LiteLLM usage metering per subscriber
- [ ] Unified Payout Engine (:8170)
- [ ] Payout batch processing across all marketplaces
- [ ] 1099-NEC tracking and generation
- [ ] Cross-marketplace revenue reports
- [ ] AI portal frontend (:8161)
- [ ] PM2 services: AI Marketplace API (:8160), AI Agent Subscription Worker (:8162), Unified Payout Engine (:8170)

**Liquidity Milestone:** 10 agent subscribers, 5 published agent templates, unified payouts processing $10K+/month.

### 10.6 Phase 6: Governance + Trust & Safety + Full Automation (Weeks 21-24)

**Goal:** Complete governance framework, trust and safety automation, self-sustaining liquidity.

**Deliverables:**
- [ ] Trust and Safety Service (:8180)
- [ ] Cross-marketplace reputation scoring
- [ ] Automated dispute resolution workflows
- [ ] Quality review and enforcement across all marketplaces
- [ ] Suspension/banning with cross-marketplace effect propagation
- [ ] Full audit trail for all marketplace transactions
- [ ] Anti-fraud detection (sybil attacks, fake reviews, commission gaming)
- [ ] Enterprise admin dashboard
- [ ] Compliance reporting (monthly automated)
- [ ] Data privacy controls across all participant types

**Liquidity Milestone:** 200+ attorneys, 100+ partners, 50+ workflow templates, 20+ agent templates, $50K+/month cross-marketplace transaction volume.

### 10.7 Implementation Dependency Graph

```
Phase 1: Attorney Foundation
    │
    ├── BLOCKS ──> Phase 2: Attorney Self-Service + Partner Onboarding
    │                          │
    │                          ├── BLOCKS ──> Phase 3: AI Routing + Revenue + Referrals
    │                          │                  │
    │                          │                  ├── BLOCKS ──> Phase 4: Portals + Doc Automation + Workflows
    │                          │                  │                  │
    │                          │                  │                  ├── BLOCKS ──> Phase 5: AI Marketplace + Unified Payouts
    │                          │                  │                  │                  │
    │                          │                  │                  │                  └── BLOCKS ──> Phase 6: Governance + Trust
    │                          │                  │                  │
    │                          │                  └── BLOCKS ──> Phase 5 (payout engine needs revenue share from Phase 3)
    │                          │
    │                          └── BLOCKS ──> Phase 4 (partner portal needs Phase 2 data)
    │
    └── Phase 1 must reach 4-attorney liquidity before Phase 2 begins
```

---

## 11. PM2 Service Configuration

```javascript
// ecosystem.config.js — All Marketplace Services
module.exports = {
  apps: [
    // ============================================================
    // ATTORNEY MARKETPLACE (Section 3)
    // ============================================================
    {
      name: 'attorney-marketplace-api',
      cwd: '/opt/wheeler/apps/attorney-marketplace/api',
      script: 'dist/server.js',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        PORT: 8120,
        NODE_ENV: 'production',
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        LITELLM_URL: 'http://127.0.0.1:4049',
        DOCUSEAL_URL: 'http://127.0.0.1:3010',
        SENDGRID_API_KEY: '${SENDGRID_API_KEY}',
        DISCORD_WEBHOOK_URL: '${MARKETPLACE_DISCORD_WEBHOOK}',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        STRIPE_WEBHOOK_SECRET: '${STRIPE_WEBHOOK_SECRET}',
        JWT_SECRET: '${MARKETPLACE_JWT_SECRET}',
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
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        SENDGRID_API_KEY: '${SENDGRID_API_KEY}',
        DOCUSEAL_URL: 'http://127.0.0.1:3010',
      },
    },
    {
      name: 'attorney-license-worker',
      cwd: '/opt/wheeler/apps/attorney-marketplace/workers/license',
      script: 'dist/license-worker.js',
      instances: 1,
      cron_restart: '0 6 * * 0',
      env: {
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        LITELLM_URL: 'http://127.0.0.1:4049',
      },
    },
    {
      name: 'attorney-revenue-engine',
      cwd: '/opt/wheeler/apps/attorney-marketplace/workers/revenue',
      script: 'dist/revenue-engine.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        STRIPE_WEBHOOK_SECRET: '${STRIPE_WEBHOOK_SECRET}',
      },
    },
    {
      name: 'attorney-document-worker',
      cwd: '/opt/wheeler/apps/attorney-marketplace/workers/document',
      script: 'dist/document-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
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
        DISCORD_WEBHOOK_URL: '${MARKETPLACE_DISCORD_WEBHOOK}',
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
      },
    },
    {
      name: 'attorney-portal-frontend',
      cwd: '/opt/wheeler/apps/attorney-marketplace/frontend',
      script: 'node_modules/.bin/serve',
      args: '-s build -l 8121',
      instances: 1,
      env: {
        REACT_APP_API_URL: 'https://fundsrecoverygroup.com/api/marketplace/attorney',
        REACT_APP_DOCUSEAL_URL: 'https://docuseal.fundsrecoverygroup.tech',
        NODE_ENV: 'production',
      },
    },

    // ============================================================
    // PARTNER MARKETPLACE (Section 4)
    // ============================================================
    {
      name: 'partner-marketplace-api',
      cwd: '/opt/wheeler/apps/partner-marketplace/api',
      script: 'dist/server.js',
      instances: 1,
      env: {
        PORT: 8130,
        NODE_ENV: 'production',
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        DOCUSEAL_URL: 'http://127.0.0.1:3010',
        SENDGRID_API_KEY: '${SENDGRID_API_KEY}',
        JWT_SECRET: '${MARKETPLACE_JWT_SECRET}',
        LOG_LEVEL: 'info',
      },
      max_restarts: 5,
      min_uptime: '30s',
    },
    {
      name: 'partner-commission-worker',
      cwd: '/opt/wheeler/apps/partner-marketplace/workers/commission',
      script: 'dist/commission-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
      },
    },
    {
      name: 'partner-portal-frontend',
      cwd: '/opt/wheeler/apps/partner-marketplace/frontend',
      script: 'node_modules/.bin/serve',
      args: '-s build -l 8131',
      instances: 1,
      env: {
        REACT_APP_API_URL: 'https://fundsrecoverygroup.com/api/marketplace/partner',
        NODE_ENV: 'production',
      },
    },

    // ============================================================
    // REFERRAL MARKETPLACE (Section 5)
    // ============================================================
    {
      name: 'referral-marketplace-api',
      cwd: '/opt/wheeler/apps/referral-marketplace/api',
      script: 'dist/server.js',
      instances: 1,
      env: {
        PORT: 8140,
        NODE_ENV: 'production',
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        NEO4J_URL: 'bolt://127.0.0.1:7687',
        NEO4J_USER: 'neo4j',
        NEO4J_PASSWORD: '${NEO4J_PASSWORD}',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        DOCUSEAL_URL: 'http://127.0.0.1:3010',
        JWT_SECRET: '${MARKETPLACE_JWT_SECRET}',
        LOG_LEVEL: 'info',
      },
      max_restarts: 5,
      min_uptime: '30s',
    },
    {
      name: 'referral-escrow-worker',
      cwd: '/opt/wheeler/apps/referral-marketplace/workers/escrow',
      script: 'dist/escrow-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
      },
    },
    {
      name: 'referral-portal-frontend',
      cwd: '/opt/wheeler/apps/referral-marketplace/frontend',
      script: 'node_modules/.bin/serve',
      args: '-s build -l 8141',
      instances: 1,
      env: {
        REACT_APP_API_URL: 'https://fundsrecoverygroup.com/api/marketplace/referral',
        NODE_ENV: 'production',
      },
    },

    // ============================================================
    // WORKFLOW MARKETPLACE (Section 6)
    // ============================================================
    {
      name: 'workflow-marketplace-api',
      cwd: '/opt/wheeler/apps/workflow-marketplace/api',
      script: 'dist/server.js',
      instances: 1,
      env: {
        PORT: 8150,
        NODE_ENV: 'production',
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        N8N_URL: 'http://127.0.0.1:5678',
        N8N_API_KEY: '${N8N_API_KEY}',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        JWT_SECRET: '${MARKETPLACE_JWT_SECRET}',
        LOG_LEVEL: 'info',
      },
      max_restarts: 5,
      min_uptime: '30s',
    },
    {
      name: 'workflow-portal-frontend',
      cwd: '/opt/wheeler/apps/workflow-marketplace/frontend',
      script: 'node_modules/.bin/serve',
      args: '-s build -l 8151',
      instances: 1,
      env: {
        REACT_APP_API_URL: 'https://fundsrecoverygroup.com/api/marketplace/workflow',
        NODE_ENV: 'production',
      },
    },

    // ============================================================
    // AI AUTOMATION MARKETPLACE (Section 7)
    // ============================================================
    {
      name: 'ai-marketplace-api',
      cwd: '/opt/wheeler/apps/ai-marketplace/api',
      script: 'dist/server.js',
      instances: 1,
      env: {
        PORT: 8160,
        NODE_ENV: 'production',
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        LITELLM_URL: 'http://127.0.0.1:4049',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        STRIPE_WEBHOOK_SECRET: '${STRIPE_WEBHOOK_SECRET}',
        JWT_SECRET: '${MARKETPLACE_JWT_SECRET}',
        LOG_LEVEL: 'info',
      },
      max_restarts: 5,
      min_uptime: '30s',
    },
    {
      name: 'ai-agent-subscription-worker',
      cwd: '/opt/wheeler/apps/ai-marketplace/workers/subscriptions',
      script: 'dist/subscription-worker.js',
      instances: 1,
      env: {
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        LITELLM_URL: 'http://127.0.0.1:4049',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
      },
    },
    {
      name: 'ai-marketplace-portal-frontend',
      cwd: '/opt/wheeler/apps/ai-marketplace/frontend',
      script: 'node_modules/.bin/serve',
      args: '-s build -l 8161',
      instances: 1,
      env: {
        REACT_APP_API_URL: 'https://fundsrecoverygroup.com/api/marketplace/ai',
        NODE_ENV: 'production',
      },
    },

    // ============================================================
    // CROSS-MARKETPLACE SERVICES (Section 8)
    // ============================================================
    {
      name: 'unified-payout-engine',
      cwd: '/opt/wheeler/apps/marketplace-shared/payout-engine',
      script: 'dist/payout-engine.js',
      instances: 1,
      env: {
        PORT: 8170,
        NODE_ENV: 'production',
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        STRIPE_SECRET_KEY: '${STRIPE_SECRET_KEY}',
        STRIPE_WEBHOOK_SECRET: '${STRIPE_WEBHOOK_SECRET}',
        LOG_LEVEL: 'info',
      },
      max_restarts: 5,
      min_uptime: '30s',
    },
    {
      name: 'marketplace-trust-safety',
      cwd: '/opt/wheeler/apps/marketplace-shared/trust-safety',
      script: 'dist/trust-safety.js',
      instances: 1,
      env: {
        PORT: 8180,
        NODE_ENV: 'production',
        DB_URL: 'postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace',
        NEO4J_URL: 'bolt://127.0.0.1:7687',
        NEO4J_USER: 'neo4j',
        NEO4J_PASSWORD: '${NEO4J_PASSWORD}',
        LITELLM_URL: 'http://127.0.0.1:4049',
        LOG_LEVEL: 'info',
      },
      max_restarts: 5,
      min_uptime: '30s',
    },
  ],
};
```

---

## 12. Directory Structure

```
/opt/wheeler/apps/
├── attorney-marketplace/         # Marketplace 1
│   ├── api/                      # PM2 :8120
│   ├── workers/
│   │   ├── onboarding/           # PM2 :8122
│   │   ├── license/              # PM2 :8123
│   │   ├── revenue/              # PM2 :8124
│   │   ├── document/             # PM2 :8125
│   │   └── communications/       # PM2 :8126
│   ├── frontend/                 # PM2 :8121
│   └── migrations/
│
├── partner-marketplace/          # Marketplace 2
│   ├── api/                      # PM2 :8130
│   ├── workers/
│   │   └── commission/           # PM2 :8132
│   ├── frontend/                 # PM2 :8131
│   └── migrations/
│
├── referral-marketplace/         # Marketplace 3
│   ├── api/                      # PM2 :8140
│   ├── workers/
│   │   └── escrow/               # PM2 :8142
│   ├── frontend/                 # PM2 :8141
│   └── migrations/
│
├── workflow-marketplace/         # Marketplace 4
│   ├── api/                      # PM2 :8150
│   ├── frontend/                 # PM2 :8151
│   └── migrations/
│
├── ai-marketplace/               # Marketplace 5
│   ├── api/                      # PM2 :8160
│   ├── workers/
│   │   └── subscriptions/        # PM2 :8162
│   ├── frontend/                 # PM2 :8161
│   └── migrations/
│
└── marketplace-shared/           # Cross-marketplace
    ├── identity/                 # Shared auth service
    ├── payout-engine/            # PM2 :8170
    ├── trust-safety/             # PM2 :8180
    ├── event-bus/                # Marketplace event definitions
    ├── schemas/                   # Shared database migrations
    └── lib/                      # Shared libraries
        ├── stripe-connect.js
        ├── docuseal-client.js
        ├── litellm-client.js
        ├── neo4j-client.js
        ├── n8n-client.js
        └── sendgrid-client.js
```

---

## 13. Key Metrics and Success Criteria

### 13.1 Phase Completion Metrics

| Phase | Metric | Target |
|-------|--------|--------|
| Phase 1 | Attorneys in marketplace | >=4 (all existing) |
| Phase 1 | Case assignments tracked | 100% in system |
| Phase 2 | Self-service attorney registrations | >=5/month |
| Phase 2 | Active partners | >=7 (5 RE agents + 2 title cos) |
| Phase 3 | Auto-routed cases | >=80% |
| Phase 3 | First referral completed | >=1 |
| Phase 3 | First automated payout | >=1 |
| Phase 4 | Portal adoption (active attorneys) | >=80% |
| Phase 4 | Workflow templates published | >=10 |
| Phase 4 | Template downloads | >=25 |
| Phase 4 | Partner portal adoption (active partners) | >=80% |
| Phase 5 | AI agent subscriptions | >=10 |
| Phase 5 | Published agent templates | >=5 |
| Phase 5 | Unified payout volume | >=$10K/month |
| Phase 6 | Cross-marketplace trust score active | 100% of participants |
| Phase 6 | Automated dispute resolution | 80% resolved without admin |

### 13.2 Business Impact Metrics

| Metric | Current (Manual) | Phase 3 Target | Phase 6 Target |
|--------|-----------------|----------------|----------------|
| Active attorneys | 4 | 30 | 200+ |
| Active partners | 0 | 15 | 100+ |
| Workflow templates | 0 | 10 | 50+ |
| AI agent templates | 0 | 5 | 20+ |
| Cases/month | <50 | 200 | 2000+ |
| Cross-marketplace referrals/month | 0 | 10 | 200+ |
| Template sales/month | 0 | 25 | 500+ |
| AI agent MRR | $0 | $2K | $20K+ |
| Total marketplace revenue/month | $0 | $10K+ | $50K+ |
| Assignment time | Hours-days | <1 hour | <5 minutes |
| Partner lead conversion rate | N/A | 10% | 20%+ |
| Referral acceptance rate | N/A | 60% | 75%+ |

### 13.3 Gate Criteria: Phase-to-Phase

**Phase 1 -> Phase 2 Gate:**
1. 4 attorneys in marketplace database
2. Case assignment workflow functional (create -> offer -> accept/reject -> complete)
3. Basic audit log capturing all changes
4. PM2 services :8120, :8122, :8123 healthy with <5 restarts/24h

**Phase 2 -> Phase 3 Gate:**
1. 15+ active attorneys with verified bar licenses
2. 5+ partners actively submitting leads
3. Partner lead submission -> conversion pipeline proven with 1+ case
4. Docuseal integration working for agreement signing
5. All Phase 1 gates still passing

**Phase 3 -> Phase 4 Gate:**
1. 30+ active attorneys
2. 80%+ auto-routing rate (AI or rule-based)
3. First successful automated payout via Stripe Connect
4. First attorney-to-attorney referral completed
5. Multi-party split calculation engine tested
6. All Phase 2 gates still passing

**Phase 4 -> Phase 5 Gate:**
1. 50+ active attorneys
2. 15+ active partners
3. 10 workflow templates published
4. 25+ template downloads
5. Attorney portal adoption >80%
6. n8n instance healthy with <5 workflow failures/week
7. All Phase 3 gates still passing

**Phase 5 -> Phase 6 Gate:**
1. 10+ AI agent subscribers with active subscriptions
2. 5 published agent templates with reviews
3. Unified payout engine processing $10K+/month across all marketplaces
4. LiteLLM usage metering per subscriber verified
5. All Phase 4 gates still passing

---

## 14. Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-----------|--------|------------|
| COREDB remains unreachable | Medium | Critical -- no centralized marketplace data | Phase 1 on local AIOPS PostgreSQL; migration path when COREDB is available |
| Attorney liquidity insufficient for referral network | Medium | High -- referral marketplace stalls | Overflow-only referrals in Phase 3; hand-pick attorneys in high-volume states |
| Partner lead quality too low (spam, bad data) | Medium | High -- partner trust erodes | Mandatory partner verification; lead quality scoring; rate limiting on submissions |
| Workflow templates have security vulnerabilities | Low | High -- n8n instance compromised | Mandatory security review before publishing; sandboxed testing; automated vulnerability scanning |
| AI agent subscription churn after free trial | High | Medium -- revenue instability | Usage analytics to identify at-risk subscribers; proactive engagement; tiered pricing with retention incentives |
| Cross-marketplace fraud (commission gaming) | Low | Critical -- trust destruction | Trust and safety service (:8180) with anomaly detection; mandatory audit trail; dispute resolution workflow |
| Stripe Connect payout failures | Low | High -- participant trust lost | Retry logic; manual payout trigger; clear error reporting; multi-method fallback |
| n8n version upgrades break published templates | Medium | Medium -- template catalog degrades | Version-pinned template definitions; n8n upgrade testing in staging; template compatibility matrix |
| Attorneys game performance scoring | Low | Medium -- unfair rankings | Human review of outlier scores; audit trail; cap per-case score impact |
| AI agent prompt injection from subscriber input | Low | Critical -- data breach | Input sanitization; output validation; prompt hardening; execution isolation |
| Marketplace adoption slows after Phase 2 | Medium | Medium -- revenue targets slip | Partner referral incentives; attorney referral bonuses; case study marketing; free tier for workflow templates |
| Legal compliance: fee splitting rules vary by state | Medium | High -- regulatory risk | Configurable revenue splits per jurisdiction; compliance dashboard; state-specific agreement templates in Docuseal |

---

## 15. Environment Variables

```bash
# Marketplace database (shared across all marketplace services)
MARKETPLACE_DB_PASSWORD=<generated-random-hex-64>
MARKETPLACE_DB_URL=postgresql://marketplace_rw:${MARKETPLACE_DB_PASSWORD}@127.0.0.1:5432/marketplace

# Authentication
MARKETPLACE_JWT_SECRET=<generated-random-hex-64>

# External services (reused from ecosystem)
STRIPE_SECRET_KEY=<stripe-secret-key>
STRIPE_WEBHOOK_SECRET=<stripe-webhook-secret>
SENDGRID_API_KEY=<existing-sendgrid-api-key>
DOCUSEAL_URL=http://127.0.0.1:3010
LITELLM_URL=http://127.0.0.1:4049
NEO4J_PASSWORD=<neo4j-password>
N8N_API_KEY=<n8n-api-key>

# Notifications
MARKETPLACE_DISCORD_WEBHOOK=<discord-webhook-url-for-marketplace-events>

# Prediction Radar Stripe price IDs (for AI marketplace subscriptions)
STRIPE_PRICE_PRO=price_1TN3owPKXFjwOjQXYvdcKsgc
STRIPE_PRICE_AGENCY=price_1TN3opPKXFjwOjQXdwXamPuw
```

---

## 16. Appendices

### Appendix A: Port Map (All Marketplace Services)

| Port | Service | Marketplace | Bind |
|------|---------|-------------|------|
| 8120 | Attorney Marketplace API | Attorney | 127.0.0.1 |
| 8121 | Attorney Portal Frontend | Attorney | 127.0.0.1 |
| 8122 | Attorney Onboarding Worker | Attorney | 127.0.0.1 |
| 8123 | License Verification Worker | Attorney | 127.0.0.1 |
| 8124 | Revenue Share Engine | Attorney | 127.0.0.1 |
| 8125 | Document Automation Worker | Attorney | 127.0.0.1 |
| 8126 | Communications Worker | Attorney | 127.0.0.1 |
| 8130 | Partner Marketplace API | Partner | 127.0.0.1 |
| 8131 | Partner Portal Frontend | Partner | 127.0.0.1 |
| 8132 | Partner Commission Worker | Partner | 127.0.0.1 |
| 8140 | Referral Marketplace API | Referral | 127.0.0.1 |
| 8141 | Referral Portal Frontend | Referral | 127.0.0.1 |
| 8142 | Referral Escrow Worker | Referral | 127.0.0.1 |
| 8150 | Workflow Marketplace API | Workflow | 127.0.0.1 |
| 8151 | Workflow Portal Frontend | Workflow | 127.0.0.1 |
| 8160 | AI Marketplace API | AI | 127.0.0.1 |
| 8161 | AI Marketplace Frontend | AI | 127.0.0.1 |
| 8162 | AI Subscription Worker | AI | 127.0.0.1 |
| 8170 | Unified Payout Engine | Cross | 127.0.0.1 |
| 8180 | Trust and Safety Service | Cross | 127.0.0.1 |

### Appendix B: Existing Services Referenced

| Service | Running | Port | Role in Marketplace |
|---------|---------|------|---------------------|
| Docuseal | HEALTHY | :3010 | Document signing for all marketplaces |
| Usesend | HEALTHY | :3007 | Email campaigns for partner/claimant referrals |
| FRGCRM | ONLINE | :8082 | Case management integration |
| LiteLLM | ONLINE | :4049 | AI model gateway (DeepSeek access) |
| DeepSeek API | CONFIGURED | via LiteLLM | AI routing, scoring, verification |
| Neo4j | HEALTHY | :7687 | Cross-marketplace relationship graph |
| Temporal | HEALTHY | :7233 | Durable workflow orchestration |
| Stripe (Prediction Radar) | INTEGRATED | External | Payment processing (prices: Pro price_1TN3owPKXFjwOjQXYvdcKsgc, Agency price_1TN3opPKXFjwOjQXdwXamPuw) |
| n8n | PLANNED | :5678 | Workflow execution engine |
| Command Center | ONLINE | :8100 | Agent orchestration for AI marketplace |

### Appendix C: Cross-Reference to Related Documents

| Document | Relevance |
|----------|-----------|
| `/root/ATTORNEY_MARKETPLACE_ARCHITECTURE.md` | Full attorney marketplace schema, API design, AI routing engine, portal design, implementation details. This document extends that architecture with multi-sided marketplace dimensions. |
| `/root/WHEELER_REVENUE_ENGINE_ARCHITECTURE.md` | Ecosystem-wide revenue systems, infrastructure mapping, payment architecture. Sections 4 (FRG), 6 (Attorney Marketplace), 8 (Prediction Radar) directly inform marketplace design. |
| `/root/SURPLUSAI_PRODUCTIZATION_PLAN.md` | Attorney assignment engine (Section 7), lead scoring (Section 5), county adapter framework (Section 3). The SurplusAI platform feeds leads into the Attorney Marketplace. |
| `/root/DEPLOYMENT_SYSTEM.md` | Deployment and rollback procedures for all marketplace services. |
| `/root/.claude/projects/-root/memory/pm2-env-i-pattern.md` | PM2 env var update pattern (delete+start, not restart). Required for all marketplace service deployments. |
| `/root/STAGE2_QA_SCORECARD_FINAL.md` | QA validation criteria. All marketplace deployments must pass 100/100 scorecard. |

---

*End of Document -- Marketplace Architecture v1.0*

**Next Review Date:** 2026-06-24
**Owner:** Wheeler Autonomous Enforcement Agent -- Marketplace Division
**Related Deliverables:**
- Attorney Marketplace API (:8120) + Frontend (:8121) -- Phases 1-2
- Partner Marketplace API (:8130) + Frontend (:8131) -- Phase 2
- Referral Marketplace API (:8140) + Frontend (:8141) -- Phase 3
- Workflow Marketplace API (:8150) + Frontend (:8151) -- Phase 4
- AI Automation Marketplace API (:8160) + Frontend (:8161) -- Phase 5
- Unified Payout Engine (:8170) -- Phase 5
- Trust and Safety Service (:8180) -- Phase 6
- n8n Workflow Engine (:5678) -- Phase 3
