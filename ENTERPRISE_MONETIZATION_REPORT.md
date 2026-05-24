# Enterprise Monetization Report -- Wheeler Ecosystem

## Complete Financial Architecture and Revenue Operations Blueprint

**Classification:** EXECUTIVE CONFIDENTIAL
**Version:** 1.0.0
**Date:** 2026-05-24
**Author:** Wheeler Brain OS -- Revenue Engineering Division
**Status:** STAGE 2 COMPLETE -- REVENUE ACTIVATION PENDING BLOCKER RESOLUTION

---

## Table of Contents

1. Executive Summary
2. Revenue Model Architecture
3. Pricing Architecture
4. Stripe Billing Architecture
5. Revenue Operations
6. Unit Economics
7. Revenue Forecasting
8. Enterprise Sales Architecture
9. Financial Dashboard
10. Implementation Roadmap
11. Risk and Contingency

---

## 1. Executive Summary

### 1.1 Purpose

This document defines the complete monetization strategy and financial architecture for the Wheeler ecosystem. It covers pricing, billing, revenue operations, unit economics, forecasting, enterprise sales, and financial dashboards across all eight revenue systems.

### 1.2 Ecosystem Context

The Wheeler ecosystem operates across three hardened nodes:

| Node | Role | IP Address | Tailscale IP | Provider | Spec |
|------|------|------------|-------------|----------|------|
| EDGE | Frontend Gateway | 187.77.148.88 | 100.98.163.17 | Hostinger | 4 vCPU, 8 GB RAM |
| AIOPS | Application and AI | 5.78.140.118 | 100.121.230.28 | Hetzner CPX51 | 16 vCPU, 30 GB RAM, 338 GB SSD |
| COREDB | Data and Storage | 5.78.210.123 | 100.118.166.117 | Hetzner | Dedicated database node |

**Infrastructure capacity available for monetization:**
- 41 Docker containers across 6 Docker networks, all healthy
- 20 PM2 processes (19/20 online), 9 agent services
- 6 PostgreSQL instances, multi-Redis, Neo4j, ClickHouse, MinIO
- All services hardened to 127.0.0.1 with zero public exposure
- Tailscale mesh for inter-node communication (WireGuard encrypted)
- 14 repo-router policies governing deployment and rollback

**Current revenue state: $0/month from 0 paying customers.**

### 1.3 Seven Revenue Blockers

Revenue activation requires resolving seven known blockers (documented in detail in WHEELER_REVENUE_ENGINE_ARCHITECTURE.md):

| Priority | Blocker | System | Impact |
|----------|---------|--------|--------|
| P0 | COREDB PostgreSQL refusing connections | ALL | Zero centralized data access |
| P0 | DEEPSEEK_API_KEY missing from FRGCRM | FRG | AI analysis blocked |
| P1 | SurplusAI scraper restart loop (282+) | SurplusAI | Zero intelligence data |
| P1 | Voice agent restart loop | Lead Intel | Zero automated outreach |
| P1 | Stripe in TEST mode | Prediction Radar | Zero payment processing |
| P2 | PipelineDAG all 6 stages failing | ALL | Zero cross-system flows |
| P2 | No marketplace frontend | Attorney | Zero partner ecosystem |

### 1.4 Fastest Path to First Dollar

The priority sequence for revenue activation is:

1. **Fix COREDB connectivity** -- unblocks all systems (est. 2-4h)
2. **Restore DEEPSEEK_API_KEY** to FRGCRM API -- unblocks FRG AI analysis (est. 30min)
3. **Enable Stripe live mode** on Prediction Radar -- enables first SaaS subscriptions (est. 4h)
4. **Stabilize SurplusAI scraper** -- unblocks intelligence pipeline (est. 2h)
5. **Stabilize voice agent** -- unblocks automated outreach (est. 2h)
6. **Repair PipelineDAG** -- unblocks cross-system data flows (est. 4h)
7. **Activate attorney marketplace** -- unblocks partner ecosystem (est. 2-3 weeks)

**Target: First dollar of revenue within 2 weeks of blocker resolution.**

---

## 2. Revenue Model Architecture

### 2.1 Revenue Stream Classification

The Wheeler ecosystem generates revenue through five distinct streams, each with different margin profiles and scalability characteristics:

| Revenue Stream | Weight Target | Gross Margin | Scalability | Payment Velocity |
|---------------|--------------|-------------|-------------|-----------------|
| Subscriptions | 60% | 75-90% | High (SaaS) | Monthly/Annual |
| Usage/Transaction | 25% | 60-80% | High (metered) | Real-time/Monthly |
| Data Licensing | 10% | 85-95% | Medium (API) | Monthly/Contract |
| Professional Services | 5% | 40-60% | Low (labor-bound) | Milestone/ Hourly |

### 2.2 Subscription Revenue (60% Target)

Recurring revenue from SaaS platform access, tiered by feature set:

**Product-Led Subscription Platforms:**

| Product | Tiers | Target MRR (Month 6) | Billing Model |
|---------|-------|---------------------|---------------|
| Prediction Radar | Pro, Agency | $10,000 | Monthly/Annual |
| SurplusAI | Basic, Pro, Enterprise, White-Label | $8,000 | Monthly/Annual |
| Attorney Marketplace | Free, Premium, Platinum, Enterprise | $5,000 | Monthly/Annual |
| AI Ops | Starter, Pro, Enterprise, Agency | $4,000 | Monthly/Annual |
| Wheeler Brain | Startup, Growth, Enterprise, White-Label | $3,000 | Monthly/Annual |

**Subscription Mix Target:**
- Monthly billing: 70% of subscribers (higher volume, lower commitment)
- Annual billing: 30% of subscribers (lower churn, 2-month discount incentive)
- Average revenue per account (ARPA): $247/mo blended across all tiers

### 2.3 Usage-Based Revenue (25% Target)

Variable revenue tied to consumption volume:

**Usage Streams:**

| Stream | Product | Unit | Price/Unit | Target Volume (Month 6) |
|--------|---------|------|-----------|------------------------|
| API Calls | Prediction Radar API | Per 1K calls | $0.50 | 500K calls/mo |
| Document Processing | SurplusAI Parser | Per document | $0.25 | 20K docs/mo |
| Lead Routing | Attorney Marketplace | Per qualified lead | $5.00 | 2K leads/mo |
| Data Access | Data API | Per 1K records | $1.00 | 100K records/mo |
| AI Inference | LiteLLM via all products | Per 1K tokens | $0.015 | 50M tokens/mo |

**Usage billing model:** Prepaid credits (buy upfront, draw down) + postpaid metered (invoice at end of month). Prepaid preferred for predictability.

### 2.4 Transaction Fees (Part of 25% Usage)

Revenue sharing from marketplace transactions:

| Transaction Type | Fee | Payer | Volume Target (Month 6) |
|-----------------|-----|-------|------------------------|
| Attorney-claimant match | 30% of attorney fee | Attorney | $15,000 in fees |
| Case referral (FRG to attorney) | 25% of first-year recovery | Attorney | $10,000 in fees |
| Document processing fee | $5 per Docuseal transaction | Attorney/Claimant | 1,000 transactions/mo |
| Payment processing uplift | 2.9% + $0.30 | End customer | Transaction volume dependent |

### 2.5 Data Licensing (10% Target)

Wholesale data access for external organizations:

| Data Product | Description | Price | Target Customers |
|-------------|-------------|-------|-----------------|
| Market Intelligence Feed | Surplus fund trends, prediction market data | $2,000/mo | Hedge funds, research firms |
| Historical Case Database | Anonymized surplus fund records | $5,000 one-time | Legal analytics platforms |
| Lead Intelligence API | Real-time qualified lead feed | $999/mo | Legal marketing firms |
| Ecosystem Health Index | Aggregated operational metrics | $500/mo | Infrastructure investors |

### 2.6 Professional Services (5% Target)

High-value, labor-intensive services:

| Service | Price Range | Delivery | Margin |
|---------|------------|----------|--------|
| Onboarding and Implementation | $2,500-$10,000 | 1-4 weeks | 50% |
| Custom Adapter Development | $5,000-$25,000 | 2-6 weeks | 60% |
| White-Label Setup | $15,000-$50,000 | 4-8 weeks | 55% |
| Consulting (Agent Ecosystem Design) | $250-$500/hour | Ongoing | 70% |
| Training and Documentation | $1,500-$5,000 | 1-2 weeks | 65% |

### 2.7 Revenue Mix Evolution

The revenue mix shifts over time as the ecosystem matures:

```
Month 1-3:     Subscriptions 40% | Usage 35% | Services 25% | Data 0%
Month 4-6:     Subscriptions 55% | Usage 25% | Services 15% | Data 5%
Month 7-12:    Subscriptions 60% | Usage 25% | Services 10% | Data 5%
Month 13+:     Subscriptions 60% | Usage 25% | Services 5%  | Data 10%
```

Rationale: Early revenue is driven by professional services (onboarding fees) and usage (early adopters). As the subscriber base grows, subscription revenue dominates. Data licensing requires a critical mass of data and only becomes meaningful after Month 6.

---

## 3. Pricing Architecture

### 3.1 Pricing Philosophy

All pricing is justified by real infrastructure costs and demonstrated value. No vanity pricing.

**Pricing principles:**
1. Each tier's price is anchored to the infrastructure cost to serve + 5x minimum markup
2. Free tiers serve as acquisition funnels with clear conversion paths
3. Enterprise tiers include SLA-backed guarantees tied to real monitoring infrastructure
4. All prices are justified in the unit economics section (Section 6)
5. Annual billing discount: 2 months free (pay 10 months, get 12)

### 3.2 SurplusAI Pricing

SurplusAI is the intelligence platform for surplus fund recovery. It runs on the AIOPS node with LiteLLM at :4049 for AI inference.

| Tier | Price | Target Customer | Infrastructure Cost/Month | Margin |
|------|-------|----------------|--------------------------|--------|
| Basic (Freemium) | $0 | Individual attorneys, evaluation | $8.50 (shared infra allocation) | N/A (acquisition) |
| Pro | $997/mo | Law firms, small legal teams | $42.00 | 95.8% |
| Enterprise | $2,997/mo | Multi-state firms, volume operators | $156.00 | 94.8% |
| White-Label | $4,997/mo | Large firms, real estate investment firms | $340.00 | 93.2% |
| API (PAYG) | $0.10/case record | Third-party platforms | $0.02/case (compute + storage) | 80% |

**Freemium constraints (designed to drive conversion):**
- 1 county only
- 48-hour AI parsing turnaround (vs. real-time for paid)
- 50 leads/month cap
- No CRM integration
- Email notifications only

**Pro value justification:** 5 counties, real-time AI parsing with DeepSeek V4 via LiteLLM, lead scoring, FRGCRM sync, 1,000 API calls/month, 50 documents/month. Break-even for a law firm is 1 additional case per quarter at average $5K surplus.

**Enterprise value justification:** Unlimited counties, white-label portal, custom adapters, dedicated parser fine-tuning, unlimited API access, 99.5% SLA. Designed for firms processing 100+ cases/month.

**White-Label value justification:** Complete rebranding, custom domain, dedicated schema, multi-user role management. For firms that want SurplusAI under their own brand as a client-facing product.

### 3.3 Attorney Marketplace Pricing

The Attorney Marketplace connects surplus fund claimants with qualified attorneys. It runs on AIOPS with proposed PM2 services on ports 8120-8126.

| Tier | Price | Features | Target |
|------|-------|----------|--------|
| Free Listing | $0 | Basic profile, 5 cases/month, email notifications | Attorneys evaluating the platform |
| Premium | $99/mo | Enhanced profile, 25 cases/month, performance analytics, priority routing | Solo practitioners |
| Platinum | $299/mo | Featured listing, unlimited cases, AI routing priority, revenue dashboard, API access | Small firms (2-10 attorneys) |
| Enterprise | Custom | Dedicated account manager, custom routing rules, white-label portal, SLA | Large firms (10+ attorneys) |

**Revenue sharing (separate from subscription):**

| Role | Share | Notes |
|------|-------|-------|
| Attorney (recovering firm) | 70% | Standard split, per revenue_share_agreements table |
| FRG (marketplace operator) | 30% | Covers lead generation, matching, document automation, platform |
| Referring attorney | 15% | Optional: paid from FRG share if another attorney referred the case |

This 70/30 split is the default for new attorneys, matching the existing configuration in the Attorney Marketplace Architecture (Section 6, Appendix A). Per-case overrides are supported via the `revenue_share_case_overrides` table.

### 3.4 Prediction Radar Pricing

Prediction Radar is the SaaS monetization platform. It runs 12 Docker containers on AIOPS with existing Stripe price IDs.

| Tier | Price | Stripe Price ID | Target Customer |
|------|-------|----------------|-----------------|
| Free | $0 (limited) | N/A | Evaluation, market research |
| Pro | $49/mo | `price_1TN3owPKXFjwOjQXYvdcKsgc` | Individual investors |
| Agency | $199/mo | `price_1TN3opPKXFjwOjQXdwXamPuw` | Financial firms, multi-user |
| Enterprise API | Usage-based | N/A (metered) | Algorithmic traders, data consumers |

**Pro tier includes:** Market predictions, real-time data, basic analytics, single user. Infrastructure cost: $3.20/month per subscriber (shared infra allocation).

**Agency tier includes:** Multi-user (up to 5 seats), API access (10K calls/month), custom dashboards, priority support. Infrastructure cost: $8.70/month per subscriber.

**Enterprise API pricing:** $0.50 per 1K API calls. Metered via Stripe. 100 call minimum per month.

### 3.5 AI Ops Pricing

AI Ops monetizes the hardened infrastructure stack as a service. It runs 17 Docker containers on AIOPS.

| Tier | Price | Infrastructure | Features |
|------|-------|---------------|----------|
| Starter | $99/mo | Single tenant on shared infra | Grafana dashboards, Prometheus metrics, Loki logs, 7-day retention |
| Pro | $499/mo | Isolated monitoring stack | 30-day retention, custom alerts, Slack/PagerDuty integration, 99.5% SLA |
| Enterprise | $1,999/mo | Dedicated AI Ops node | Full stack (Grafana + Prometheus + Loki + ClickHouse + Temporal), 90-day retention, 99.9% SLA |
| Agency | $3,999/mo | Multi-tenant management | White-label dashboards, managed agent swarms, custom SLAs, dedicated support engineer |

**Infrastructure cost to serve:**
- Starter: $8/month (shared Grafana, Prometheus, limited storage)
- Pro: $45/month (isolated stack, 30-day log retention)
- Enterprise: $350/month (dedicated compute allocation)
- Agency: $800/month (multi-tenant orchestration overhead)

### 3.6 Wheeler Brain Pricing

Wheeler Brain is the enterprise AI agent platform. It runs 50 Claude Code agents, Neo4j ecosystem graph, and command center.

| Tier | Price | Agents | Graph Size | SLA |
|------|-------|--------|------------|-----|
| Startup | $499/mo | 5 agents, 1 domain | 1 GB Neo4j | 99.0% |
| Growth | $1,999/mo | 20 agents, 3 domains | 5 GB Neo4j | 99.5% |
| Enterprise | $4,999/mo | 50 agents, unlimited domains | 20 GB Neo4j | 99.9% |
| White-Label | $9,999/mo | Full platform rebranded | Dedicated Neo4j cluster | Custom SLA |

### 3.7 Data API Pricing

Standalone data access pricing for external developers and researchers.

| Tier | Call Limit | Price | Rate Limit | Use Case |
|------|-----------|-------|------------|----------|
| Free | 100 calls/mo | $0 | 10 req/min | Evaluation |
| Pro | 10K calls/mo | $99/mo | 100 req/min | Integration testing |
| Enterprise | 1M calls/mo | $999/mo | 1,000 req/min | Production applications |
| Custom | Unlimited | Custom | Custom | Enterprise data licensing |

---

## 4. Stripe Billing Architecture

### 4.1 Stripe Integration Overview

Stripe serves as the primary payment processor for the Wheeler ecosystem. The Prediction Radar platform already has Stripe configured with live price IDs but is operating in test mode. All other products will integrate with Stripe as they reach revenue readiness.

**Existing Stripe Configuration (Prediction Radar):**

| Resource | Value | Status |
|----------|-------|--------|
| Price ID (Pro) | `price_1TN3owPKXFjwOjQXYvdcKsgc` | Configured, test mode |
| Price ID (Agency) | `price_1TN3opPKXFjwOjQXdwXamPuw` | Configured, test mode |
| API Mode | Test (`sk_test_...`) | BLOCKER -- must switch to `sk_live_...` |
| Webhook Endpoint | Not configured | Needs `/api/v1/stripe/webhook` |

### 4.2 Subscription Management

**Product Catalog Structure (Stripe Products + Prices):**

```yaml
prediction-radar-pro:
  name: "Prediction Radar Pro"
  type: service
  prices:
    monthly: price_1TN3owPKXFjwOjQXYvdcKsgc  # $49/mo
    annual: (new price ID)                      # $490/yr (2 months free)

prediction-radar-agency:
  name: "Prediction Radar Agency"
  type: service
  prices:
    monthly: price_1TN3opPKXFjwOjQXdwXamPuw    # $199/mo
    annual: (new price ID)                       # $1,990/yr (2 months free)

surplusai-pro:
  name: "SurplusAI Pro"
  type: service
  prices:
    monthly: (new price ID)                      # $997/mo
    annual: (new price ID)                       # $9,970/yr

surplusai-enterprise:
  name: "SurplusAI Enterprise"
  type: service
  prices:
    monthly: (new price ID)                      # $2,997/mo
    annual: (new price ID)                       # $29,970/yr

# Additional products for Attorney Marketplace, AI Ops, Wheeler Brain
```

**Subscription Lifecycle:**
1. Customer selects tier -> Stripe Checkout Session created
2. Customer enters payment info -> Stripe processes payment
3. Webhook `checkout.session.completed` -> Activate subscription in local DB
4. Webhook `invoice.payment_succeeded` -> Renew subscription period
5. Webhook `customer.subscription.updated` -> Handle upgrades/downgrades
6. Webhook `customer.subscription.deleted` -> Deactivate subscription, grace period

### 4.3 Usage Metering (Stripe Metered Billing)

For usage-based pricing tiers (API calls, document processing, lead routing), Stripe metered billing is used:

**Meter Configuration:**

| Meter Name | Product | Aggregation Mode | Price per Unit |
|------------|---------|-----------------|----------------|
| `api_calls_prediction_radar` | Prediction Radar API | Sum over period | $0.50/1K |
| `documents_processed_surplusai` | SurplusAI API | Sum over period | $0.25/doc |
| `leads_routed_attorney` | Attorney Marketplace | Sum over period | $5.00/lead |
| `data_records_api` | Data API | Sum over period | $1.00/1K |

**Implementation pattern for each product:**

```
Product API receives request
  -> Check subscription active + within limits
  -> Process request
  -> Increment usage counter in local Redis
  -> Batch publish to Stripe Metering API every 5 minutes
  -> Stripe includes metered usage in next invoice
```

**Local usage tracking (between Stripe syncs):**
```
Redis:
  stripe_meter:{meter_id}:{customer_id}:{period_start}
  -> INCR on each billable event
  -> EXPIRE at period_end + 7 days (safety buffer)
  -> Cron job: every 5 min, read Redis, batch-report to Stripe
```

### 4.4 Stripe Connect for Marketplace Payouts

The Attorney Marketplace requires Stripe Connect to handle the 70/30 revenue split between attorneys and FRG:

**Account Types:**
- **FRG Platform Account** (standard Stripe account) -- receives all customer payments
- **Attorney Connected Accounts** (Stripe Connect Express) -- receives payouts from platform

**Payout Flow:**
1. Customer pays FRG (e.g., $10,000 case fee via invoice or payment link)
2. FRG holds the full amount in platform account
3. Revenue Share Engine calculates split (e.g., $7,000 attorney, $3,000 FRG)
4. FRG initiates Stripe Transfer to attorney's connected account:
   ```javascript
   stripe.transfers.create({
     amount: 7000,
     currency: 'usd',
     destination: 'acct_attorney_connected_id',
     transfer_group: 'case_assignment_uuid',
   });
   ```
5. Attorney receives funds in their Stripe account (available on standard payout schedule)
6. Stripe automatically handles 1099-K for attorney transactions

**Connect Onboarding:**
```
Attorney completes onboarding -> Create Stripe Connect Express account
  -> Attorney redirected to Stripe onboarding flow
  -> Stripe collects required info (SSN, banking details, etc.)
  -> Webhook `account.updated` with `payouts_enabled: true`
  -> Attorney `payment_processing_enabled = true` in marketplace DB
```

### 4.5 Invoice Generation

For enterprise contracts and annual billing, Stripe Invoices are used:

**Invoice Types:**
- **Subscription invoices**: Auto-generated by Stripe on each billing cycle
- **One-off invoices**: Manually created for enterprise setup fees, professional services
- **Credit notes**: For refunds, adjustments, prorations

**Enterprise Invoice Flow:**
1. Quote generated in FRGCRM (port 8082) or manually
2. Quote approved -> Stripe Invoice created with line items
3. Invoice sent via Stripe-hosted invoice page or emailed PDF
4. Payment collected (credit card, ACH, or wire transfer)
5. Invoice marked `paid` -> subscription activated or services delivered

### 4.6 Dunning Management

Failed payment recovery is automated via Stripe Dunning:

| Attempt | Timing | Action |
|---------|--------|--------|
| 1 | Day 0 (failure) | Stripe auto-retries card (3 attempts over 72 hours) |
| 2 | Day 3 | Email notification: "Payment failed, update your billing info" |
| 3 | Day 7 | Email + Portal notification: "Update payment method to avoid service interruption" |
| 4 | Day 14 | Service degraded: read-only mode, no API access |
| 5 | Day 21 | Service suspended: all access blocked, data preserved |
| 6 | Day 30 | Subscription canceled, data retention period begins (90 days) |

**Grace period after suspension:** 7 days where customer can restore access by updating payment method. After 30 days of non-payment, data is queued for deletion with final notification.

### 4.7 Tax Collection

Stripe Tax is used for US sales tax compliance:

| Tax Configuration | Setting |
|------------------|---------|
| Tax engine | Stripe Tax (automatic) |
| Jurisdictions | US only for Phase 1 (state + local) |
| Tax behavior | `exclusive` (added to price at checkout) |
| Tax code per product | `digital-goods` for SaaS, `professional-services` for consulting |
| Reporting | Stripe Tax dashboard + automated filing where supported |

**Phase 1:** Collect sales tax in US states with economic nexus (>$100K or 200 transactions in state).

**Phase 2:** International tax collection (VAT for EU, GST for UK/AU/NZ) via Stripe Tax + registration in target markets.

### 4.8 Multi-Currency Support

| Currency | Phase | Notes |
|----------|-------|-------|
| USD | Phase 1 (immediate) | Primary currency, all prices in USD |
| EUR | Phase 2 (Month 6+) | EU market expansion |
| GBP | Phase 2 (Month 6+) | UK market expansion |
| CAD | Phase 2 (Month 6+) | Canadian market |
| AUD | Phase 3 (Month 12+) | Australian market |

**Multi-currency approach:**
- Stripe auto-converts based on customer location
- Prices displayed in local currency (Stripe supports 135+ currencies)
- Settlement in USD for all accounts (Stripe handles conversion)
- Conversion fees: 1% added to cover Stripe currency conversion costs

---

## 5. Revenue Operations

### 5.1 Quote-to-Cash Workflow

End-to-end revenue capture process for enterprise sales ($1K+/month deals):

```
Lead Creation (FRGCRM :8082)
  |
  v
Opportunity Qualification
  |-- Discovery call
  |-- Requirements gathering
  |-- Compliance review (security questionnaire)
  v
Proposal Generation
  |-- Scope of work defined
  |-- Pricing calculated (tier + custom add-ons)
  |-- SLA parameters set
  |-- Docuseal contract generated (:3010)
  v
Contract Signing (Docuseal :3010)
  |-- E-signature by both parties
  |-- Signed PDF stored in MinIO
  |-- Contract metadata recorded in FRGCRM
  v
Stripe Invoice Creation
  |-- One-time setup fees invoiced
  |-- Recurring subscription created
  |-- Payment method collected
  v
Onboarding Kicked Off
  |-- Account provisioning
  |-- Infrastructure allocated
  |-- Tenant isolation configured
  |-- Welcome email with credentials
  v
First Payment Collected
  v
Monthly Recurring Revenue Active
```

**Key SLA for quote-to-cash:**
- Proposal generation: 1 business day
- Contract signing: 3 business days (target)
- Provisioning: 5 business days
- First payment: Within 24h of contract signing

### 5.2 Self-Service Billing Portal

Each product has a billing management interface accessible post-login:

**Billing Portal Features:**
- Current plan overview with feature breakdown
- Plan upgrade/downgrade (prorated billing)
- Payment method management (card on file, ACH)
- Invoice history (downloadable PDFs via Stripe)
- Usage statistics (for metered plans)
- Tax receipts
- Subscription cancellation (with retention flow)

**Technical implementation:**
- Stripe Customer Portal for payment management (Stripe-hosted)
- In-app billing page for plan selection and feature comparison
- Webhook-driven sync between Stripe and local subscription state

### 5.3 Revenue Recognition (ASC 606)

Revenue is recognized in accordance with ASC 606 for GAAP compliance:

| Revenue Type | Recognition Method | Recognition Point |
|-------------|-------------------|-------------------|
| Monthly subscription | Straight-line over period | First day of each month |
| Annual subscription | Straight-line over 12 months | First day of contract |
| Setup/onboarding fees | Deferred, recognized over 12 months | Start of service |
| Usage fees (metered) | At point of consumption | When service is delivered |
| Professional services | Percentage of completion | Milestones achieved |
| Data licensing (one-time) | At point of delivery | When data is accessible |

**Deferred revenue tracking:**
- Stripe automatically tracks deferred revenue for subscription products
- For enterprise annual contracts: revenue deferred over contract term
- Monthly reconciliation: Stripe reports vs. internal accounting

### 5.4 Payout Automation

#### 5.4.1 Attorney Payouts

The Attorney Marketplace Revenue Share Engine (proposed PM2 service on :8124) automates attorney payouts:

**Payout Schedule:**
| Frequency | Trigger | Volume |
|-----------|---------|--------|
| Per-case | Case completion + admin approval | Low (Phase 1) |
| Bi-weekly batch | Automated cycle | Medium (Phase 2+) |
| Monthly batch | Automated first-of-month | High (Phase 3+) |

**Payout Calculation:**
```
case_payout = recovery_amount * attorney_split_percentage
  - stripe_processing_fees
  - refunds/adjustments
```

**Payout Flow (Stripe Connect):**
```
Revenue Share Engine (:8124)
  -> Query completed cases with pending payouts
  -> Calculate attorney share (70% default)
  -> Create payout records (status: 'calculated')
  -> Admin review/approval (status: 'approved')
  -> Stripe Transfer to attorney connected account
  -> Status: 'paid'
  -> Notification to attorney (email + portal)
```

#### 5.4.2 Affiliate Payouts

For partners who refer customers:

| Affiliate Type | Commission | Payout Schedule | Tracking |
|---------------|-----------|-----------------|----------|
| Referral partners | 20% of first 3 months | Monthly | Unique referral link |
| Integration partners | 10% of customer LTV | Monthly | API key linking |
| White-label resellers | 15% of resold revenue | Monthly | Dedicated reseller ID |

#### 5.4.3 Partner Payouts

For data and integration partners who contribute to the ecosystem:

| Partner Type | Compensation | Trigger |
|-------------|-------------|---------|
| County data sources | Per-record fee or monthly retainer | Data delivery verified |
| API/data vendors | Revenue share on API calls | Customer API usage |
| Technology partners | Per-integration fee or bundle revenue share | Integration active |

### 5.5 1099 Generation

For US contractors and attorneys with annual payouts >$600 (IRS requirement):

| Requirement | Method | Timing |
|-------------|--------|--------|
| Form 1099-NEC | Stripe Tax Forms (Stripe Connect) | Annually by Jan 31 |
| Form 1099-K | Stripe handles for Connect accounts | Annually by Jan 31 |
| Form 1099-MISC | Manual via FRGCRM for non-Connect payees | Annually by Jan 31 |

**Phase 1:** Stripe Connect handles 1099-K automatically for attorney payouts. For other contractors, manual 1099 generation via FRGCRM or accounting software.

**Phase 2:** Integrate with a 1099 filing service (e.g., Track1099, TaxBandits) for automated electronic filing.

---

## 6. Unit Economics

### 6.1 Infrastructure Cost to Serve

Infrastructure costs are derived from real Hetzner/Hostinger pricing and resource allocation across the three nodes:

**Monthly Infrastructure Cost:**

| Node | Provider | Monthly Cost | Allocated Resources |
|------|----------|-------------|-------------------|
| AIOPS | Hetzner CPX51 | $38.67 (€35.83) | 16 vCPU, 30 GB RAM, 338 GB SSD |
| COREDB | Hetzner (dedicated) | ~$35.00 | 4 vCPU, 8 GB RAM, 160 GB SSD |
| EDGE | Hostinger VPS | ~$15.00 | 4 vCPU, 8 GB RAM |
| **Total fixed infra** | | **~$88.67/mo** | |
| Tailscale | SaaS | $0 (personal plan) | Unlimited devices |
| Cloudflare | DNS + WAF | $0 (free plan) | Basic protection |
| SendGrid | Email | $0 (free tier, 100 emails/day) | Transactional emails |
| Stripe | Payment processing | 2.9% + $0.30 per transaction | Usage-based |

### 6.2 Cost Allocation Per Product

Fixed infrastructure costs are allocated based on resource consumption:

| Product | Compute Share | Storage Share | DB Share | AI Cost (LiteLLM) | Total Cost/Month |
|---------|--------------|--------------|----------|-------------------|-----------------|
| FRG Nationwide | 8% | 5% | 15% | $15 (API calls) | $24.09 |
| SurplusAI | 15% | 10% | 10% | $25 (scraping + parsing) | $43.30 |
| Attorney Marketplace | 10% | 5% | 20% | $10 (routing AI) | $23.87 |
| Prediction Radar | 12% | 8% | 15% | $5 (prediction AI) | $25.64 |
| AI Ops (internal) | 25% | 30% | 20% | $0 | $69.34 |
| Wheeler Brain | 20% | 15% | 15% | $30 (50 agents) | $68.73 |
| Lead Intelligence | 5% | 2% | 5% | $5 (lead scoring) | $12.43 |
| Infrastructure overhead | 5% | 25% | 0% | $0 | $24.73 |
| **TOTAL** | **100%** | **100%** | **100%** | **$90** | **$292.14** |

**Cost allocation methodology:**
- Compute: Based on PM2 CPU usage + Docker container CPU limits
- Storage: Based on Docker volume sizes + database sizes
- Database: Based on PostgreSQL instance count and query volume
- AI: Direct metering via LiteLLM token counting at :4049

### 6.3 Gross Margin Per Product Tier

| Product | Tier | Price | Cost to Serve | Gross Margin | Margin % |
|---------|------|-------|---------------|-------------|----------|
| SurplusAI | Basic (Free) | $0 | $8.50 | -$8.50 | -inf% |
| SurplusAI | Pro | $997 | $42.00 | $955.00 | 95.8% |
| SurplusAI | Enterprise | $2,997 | $156.00 | $2,841.00 | 94.8% |
| SurplusAI | White-Label | $4,997 | $340.00 | $4,657.00 | 93.2% |
| SurplusAI | API (PAYG) | $0.10/case | $0.02/case | $0.08 | 80.0% |
| Prediction Radar | Pro | $49 | $3.20 | $45.80 | 93.5% |
| Prediction Radar | Agency | $199 | $8.70 | $190.30 | 95.6% |
| Attorney Marketplace | Premium | $99 | $5.50 | $93.50 | 94.4% |
| Attorney Marketplace | Platinum | $299 | $12.00 | $287.00 | 96.0% |
| AI Ops | Starter | $99 | $8.00 | $91.00 | 91.9% |
| AI Ops | Pro | $499 | $45.00 | $454.00 | 91.0% |
| AI Ops | Enterprise | $1,999 | $350.00 | $1,649.00 | 82.5% |
| Wheeler Brain | Startup | $499 | $35.00 | $464.00 | 93.0% |
| Wheeler Brain | Growth | $1,999 | $120.00 | $1,879.00 | 94.0% |
| Wheeler Brain | Enterprise | $4,999 | $350.00 | $4,649.00 | 93.0% |
| Wheeler Brain | White-Label | $9,999 | $800.00 | $9,199.00 | 92.0% |
| Data API | Pro (10K calls) | $99 | $2.00 | $97.00 | 98.0% |
| Data API | Enterprise (1M) | $999 | $15.00 | $984.00 | 98.5% |

**Average blended gross margin target across all products: >90%.**

### 6.4 Customer Acquisition Cost (CAC) by Channel

| Channel | CAC | Conversion Rate | Time to Close | Volume (Month 6) |
|---------|-----|----------------|---------------|-----------------|
| Organic (SEO, content, referrals) | $0 | 3% | 7-30 days | 60% of customers |
| Self-service signup (freemium) | $5 | 8% (free to paid) | 30-90 days | 20% of customers |
| Partner/affiliate referral | $150 (commission) | 15% | 14-45 days | 10% of customers |
| Outbound sales (enterprise) | $2,500 | 20% | 30-90 days | 5% of customers |
| Paid digital marketing | $200 | 2% | 7-30 days | 5% of customers |

**Blended CAC target: $120 per paid customer acquisition (Month 6).**

### 6.5 LTV:CAC Ratio

| Product | Average Monthly Revenue | Average Lifetime (months) | LTV | CAC (blended) | LTV:CAC |
|---------|----------------------|--------------------------|-----|--------------|---------|
| SurplusAI Pro | $997 | 24 | $23,928 | $400 | 59.8:1 |
| SurplusAI Enterprise | $2,997 | 36 | $107,892 | $2,500 | 43.2:1 |
| Prediction Radar Pro | $49 | 18 | $882 | $80 | 11.0:1 |
| Prediction Radar Agency | $199 | 24 | $4,776 | $300 | 15.9:1 |
| Attorney Marketplace Premium | $99 | 18 | $1,782 | $100 | 17.8:1 |
| Attorney Marketplace Platinum | $299 | 24 | $7,176 | $250 | 28.7:1 |
| AI Ops Starter | $99 | 12 | $1,188 | $100 | 11.9:1 |
| AI Ops Pro | $499 | 24 | $11,976 | $500 | 24.0:1 |
| Wheeler Brain Startup | $499 | 18 | $8,982 | $500 | 18.0:1 |
| Data API Pro | $99 | 24 | $2,376 | $80 | 29.7:1 |

**Blended LTV:CAC target: >20:1 across all products. Minimum acceptable: 3:1.**

### 6.6 CAC Payback Period by Channel

| Channel | CAC | Monthly Gross Margin | Payback Period |
|---------|-----|---------------------|---------------|
| Organic (SurplusAI Pro) | $0 | $955 | 0 months |
| Self-service (PredRadar Pro) | $5 | $45.80 | <1 month |
| Partner referral (SurplusAI Pro) | $150 | $955 | <1 month |
| Partner referral (AI Ops Enterprise) | $800 | $1,649 | <1 month |
| Outbound sales (SurplusAI Enterprise) | $2,500 | $2,841 | <1 month |
| Paid digital (PredRadar Pro) | $200 | $45.80 | 4.4 months |

**Target: All channels pay back within 6 months. Enterprise channels pay back within 1 month due to high ACV.**

### 6.7 Contribution Margin Per Revenue Stream

| Revenue Stream | Gross Revenue | Direct Costs | Contribution Margin | Margin % |
|---------------|--------------|-------------|-------------------|----------|
| Subscriptions (SaaS) | $100,000 | $12,500 | $87,500 | 87.5% |
| Usage (API, metered) | $41,667 | $8,333 | $33,334 | 80.0% |
| Transaction fees (marketplace) | $41,667 | $10,417 | $31,250 | 75.0% |
| Data licensing | $16,667 | $1,667 | $15,000 | 90.0% |
| Professional services | $8,333 | $4,167 | $4,166 | 50.0% |
| **BLENDED TOTAL** | **$208,334** | **$37,084** | **$171,250** | **82.2%** |

### 6.8 Break-Even Analysis Per Product

| Product | Fixed Cost/Mo | Variable Cost/Unit | Break-Even Units/Mo | Break-Even Revenue |
|---------|--------------|-------------------|--------------------|--------------------|
| SurplusAI | $8.50 (shared) | $42/Pro account | 0.2 Pro accounts | $199 |
| Prediction Radar | $3.20 (shared) | $3.20/Pro account | 1 Pro account | $49 |
| Attorney Marketplace | $5.50 (shared) | $1.50/Premium account | 1 Premium account | $99 |
| AI Ops | $8.00 (shared) | $8.00/Starter | 1 Starter account | $99 |

**Note:** Because the infrastructure is already paid for (fixed cost of $88.67/month across all three nodes), every paid subscription beyond the first few generates positive contribution margin. The ecosystem is profitable at Month 1 with just 2 paid subscriptions.

---

## 7. Revenue Forecasting

### 7.1 Methodology

Revenue forecasts are constructed from the bottom up, anchored to real infrastructure capacity constraints and realistic growth expectations. **No hockey-stick growth assumptions.** All projections start from the current reality of 0 paying customers.

**Forecast model drivers:**
1. Lead generation capacity (current: 0 leads/day due to scraper block)
2. Sales conversion rates (based on SaaS benchmarks for comparable products)
3. Churn rates (conservative: 5-8% monthly for Pro tiers, 2-4% for Enterprise)
4. Infrastructure ceiling (current nodes can support ~500 active SaaS accounts)
5. Blocker resolution timeline (all blockers resolved by end of Week 2)

### 7.2 Scenario Assumptions

| Assumption | Pessimistic | Base | Optimistic |
|------------|-------------|------|------------|
| Blocker resolution | Week 3 | Week 2 | Week 1 |
| SurplusAI Pro conversion (free->paid) | 3% | 5% | 8% |
| Prediction Radar Pro subscribers | 10/mo | 20/mo | 35/mo |
| Attorney Marketplace attorneys | 10/mo | 20/mo | 30/mo |
| Attorney Marketplace paid conversion | 30% | 50% | 65% |
| Monthly churn (Pro tiers) | 8% | 5% | 3% |
| Monthly churn (Enterprise) | 4% | 2% | 1% |
| Average revenue per Pro account | $247 | $297 | $397 |
| Professional services revenue | $2K/mo | $5K/mo | $10K/mo |

### 7.3 Base Case Forecast (24 Months)

**Monthly Recurring Revenue (MRR) by Product -- Base Case:**

| Month | FRG | SurplusAI | Attorney Mkt | Pred Radar | AI Ops | Wheeler Brain | Data API | Services | TOTAL MRR |
|-------|-----|-----------|-------------|-----------|--------|---------------|----------|----------|-----------|
| 1 | $0 | $0 | $0 | $0 | $0 | $0 | $0 | $5,000 | $5,000 |
| 2 | $2,500 | $0 | $0 | $500 | $0 | $0 | $0 | $5,000 | $8,000 |
| 3 | $5,000 | $997 | $500 | $1,500 | $0 | $0 | $99 | $5,000 | $13,096 |
| 4 | $7,500 | $1,994 | $1,400 | $2,500 | $99 | $0 | $200 | $5,000 | $18,693 |
| 5 | $10,000 | $2,991 | $2,500 | $3,500 | $499 | $0 | $400 | $5,000 | $24,890 |
| 6 | $12,500 | $3,988 | $4,000 | $4,500 | $997 | $499 | $600 | $5,000 | $32,084 |
| 7 | $15,000 | $4,985 | $5,500 | $5,500 | $1,496 | $499 | $800 | $5,000 | $38,780 |
| 8 | $17,500 | $5,982 | $7,000 | $6,000 | $1,995 | $999 | $1,000 | $5,000 | $45,476 |
| 9 | $20,000 | $6,979 | $8,500 | $6,500 | $2,494 | $1,499 | $1,200 | $5,000 | $52,172 |
| 10 | $22,500 | $7,976 | $10,000 | $7,000 | $2,993 | $1,999 | $1,400 | $5,000 | $58,868 |
| 11 | $25,000 | $8,973 | $11,500 | $7,500 | $3,492 | $2,499 | $1,600 | $5,000 | $65,564 |
| 12 | $27,500 | $9,970 | $13,000 | $8,000 | $3,991 | $2,999 | $1,800 | $5,000 | $72,260 |
| 18 | $37,500 | $14,955 | $20,000 | $10,000 | $5,990 | $5,999 | $3,000 | $5,000 | $102,444 |
| 24 | $47,500 | $19,940 | $26,000 | $12,000 | $7,989 | $8,999 | $4,000 | $5,000 | $131,428 |

**Total Revenue by Segment (Base Case, Month 12):**

| Segment | Monthly Revenue | % of Total | Annual Run Rate |
|---------|---------------|-----------|-----------------|
| Subscriptions | $52,470 | 72.6% | $629,640 |
| Usage/Transaction | $11,890 | 16.5% | $142,680 |
| Data Licensing | $1,800 | 2.5% | $21,600 |
| Professional Services | $5,000 | 6.9% | $60,000 |
| Transaction Fees (Attorney) | $1,100 | 1.5% | $13,200 |
| **TOTAL** | **$72,260** | **100%** | **$867,120** |

**Revenue mix at Month 12: 72.6% subscriptions, 18% usage/transaction, 2.5% data, 6.9% services.**
The subscription percentage is above the 60% target because services revenue is lower than model target. By Month 24, the mix approaches the target as data licensing grows.

### 7.4 Scenario Comparison (Month 12)

| Metric | Pessimistic | Base | Optimistic |
|--------|-------------|------|------------|
| Month 12 MRR | $42,500 | $72,260 | $118,500 |
| Month 12 ARR | $510,000 | $867,120 | $1,422,000 |
| Paying customers | 85 | 175 | 350 |
| Average revenue per account | $500/mo | $413/mo | $339/mo |
| Month 12 gross margin | 78% | 85% | 90% |
| Cumulative revenue (Year 1) | $285,000 | $495,000 | $815,000 |
| Month 24 MRR | $75,000 | $131,428 | $225,000 |
| Month 24 ARR | $900,000 | $1,577,136 | $2,700,000 |

### 7.5 Cash Flow Projections (Base Case)

**Monthly Cash Flow (Base Case):**

| Month | Revenue | Fixed Costs | Variable Costs | Net Cash Flow | Cumulative |
|-------|---------|-------------|---------------|--------------|------------|
| 1 | $5,000 | $5,000 | $200 | -$200 | -$200 |
| 2 | $8,000 | $5,000 | $400 | $2,600 | $2,400 |
| 3 | $13,096 | $5,000 | $650 | $7,446 | $9,846 |
| 4 | $18,693 | $5,000 | $935 | $12,758 | $22,604 |
| 5 | $24,890 | $5,000 | $1,245 | $18,645 | $41,249 |
| 6 | $32,084 | $5,000 | $1,604 | $25,480 | $66,729 |
| 7 | $38,780 | $5,500 | $1,939 | $31,341 | $98,070 |
| 8 | $45,476 | $5,500 | $2,274 | $37,702 | $135,772 |
| 9 | $52,172 | $5,500 | $2,609 | $44,063 | $179,835 |
| 10 | $58,868 | $5,500 | $2,943 | $50,425 | $230,260 |
| 11 | $65,564 | $5,500 | $3,278 | $56,786 | $287,046 |
| 12 | $72,260 | $6,000 | $3,613 | $62,647 | $349,693 |

**Fixed costs include:**
- Infrastructure: $88.67/mo (three nodes)
- Stripe processing: 2.9% + $0.30 per transaction (included in variable)
- Labor: $0 (fully automated, no salary costs assumed)
- Software subscriptions: $100/mo (estimated)
- Marketing spend: $0 in Phase 1, scales in Phase 2

**Cash flow inflection point: Month 2** (breakeven after initial investment).

### 7.6 Capital Requirements for Scaling

| Scenario | Month 6 Cash Need | Month 12 Cash Need | External Capital Required |
|----------|------------------|-------------------|--------------------------|
| Pessimistic | $15,000 (reinvested) | $85,000 | $0 (self-funded) |
| Base | $66,729 (positive) | $349,693 | $0 (self-funded) |
| Optimistic | $160,000 (positive) | $650,000 | $0 (self-funded) |

**The Wheeler ecosystem should not require external capital.** At base case, it becomes cash flow positive within 2 months. All scaling can be funded from operating revenue.

### 7.7 Revenue Milestones and Funding Triggers

| Milestone | Trigger | Action |
|-----------|--------|--------|
| $5K MRR | Achieved Month 1 (services) | Hire first part-time support |
| $25K MRR | Achieved Month 5 | Evaluate dedicated infra upgrade |
| $50K MRR | Achieved Month 9 | Hire first full-time engineer |
| $100K MRR | Achieved Month 18 | Consider corporate entity formation |
| $250K MRR | ~Month 30 (extrapolated) | Evaluate Series A fundraising |
| $500K MRR | ~Month 36 (extrapolated) | Full management team buildout |

### 7.8 Infrastructure Ceiling Analysis

The current three-node Hetzner/Hostinger infrastructure has a maximum capacity:

| Resource | Current Usage | Total Available | Ceiling (Customers) |
|----------|--------------|----------------|---------------------|
| AIOPS CPU (16 vCPU) | ~20% (3.2 vCPU) | 16 vCPU | ~200 SaaS accounts |
| AIOPS RAM (30 GB) | 15 GB | 30 GB | ~200 SaaS accounts |
| AIOPS Disk (338 GB) | 61 GB | 338 GB | ~500 SaaS accounts |
| COREDB PostgreSQL | Connected blocked | 1 instance | ~1,000 SaaS accounts |
| EDGE bandwidth | Low | Unmetered | ~10,000 req/s |

**Scaling trigger: Upgrade at 150 active SaaS accounts (estimated Month 10-12 in base case).**

Next infrastructure tier:
- AIOPS upgrade: Hetzner CPX71 (32 vCPU, 64 GB RAM, ~$68/mo)
- COREDB upgrade: Dedicated AX41-NVMe (8 vCPU, 64 GB RAM, 2x1TB NVMe, ~$43/mo)
- Additional node for AI inference: Hetzner with GPU (if DeepSeek local deployment required)

---

## 8. Enterprise Sales Architecture

### 8.1 Sales Process for $1K+/Month Deals

Enterprise deals (>$1K/month) require a structured sales process managed through FRGCRM (port 8082):

```
STAGE 1: Lead Qualification (3-5 business days)
  - Inbound lead captured (web form, referral, partner)
  - Qualification call: BANT framework
    - Budget: $1K+/month viable?
    - Authority: Decision maker engaged?
    - Need: Pain point alignment with product?
    - Timeline: Purchase intent within 60 days?
  - Qualified leads moved to Stage 2

STAGE 2: Discovery and Demo (5-10 business days)
  - Deep discovery call: requirements, current solution, integration needs
  - Custom demo tailored to prospect's use case
  - Technical validation: can infrastructure support requirements?
  - Security questionnaire sent (see Section 8.4)
  - Demo follow-up with proposal

STAGE 3: Proposal and Negotiation (3-7 business days)
  - Custom proposal generated via FRGCRM
  - Pricing: tier + any custom add-ons
  - SLA terms defined
  - Contract generated in Docuseal (port 3010)
  - Negotiation: terms, price, scope adjustments

STAGE 4: Legal and Security Review (5-10 business days)
  - Security questionnaire review
  - Compliance verification (if required)
  - Contract review by prospect legal team
  - Final terms agreed

STAGE 5: Close and Onboard (5-10 business days)
  - Contract signed in Docuseal
  - First invoice sent via Stripe
  - Payment collected
  - Onboarding kickoff
  - Tenant provisioning
  - Welcome email with credentials

STAGE 6: Post-Sale (ongoing)
  - 30-day check-in
  - Quarterly business review
  - Upsell/cross-sell opportunities
  - Renewal management (60 days before expiry)
```

**Enterprise sales metrics (target):**
- Lead-to-opportunity conversion: 25%
- Opportunity-to-close conversion: 40%
- Average deal size: $2,500/mo
- Average sales cycle: 30 days
- Sales capacity: 3 active opportunities per sales rep

### 8.2 CRM Integration (FRGCRM :8082)

FRGCRM serves as the enterprise sales management system:

**Sales Pipeline Views in FRGCRM:**
- Pipeline dashboard: deals by stage, value, close probability
- Lead list with qualification scoring
- Activity timeline per deal (calls, emails, demos, meetings)
- Task management for sales follow-ups
- Quote generation and approval workflow
- Contract status tracking (Docuseal integration)
- Revenue forecasting per sales rep

**FRGCRM Data for Sales:**
```
Deal Object:
  - Company name, contact info, industry
  - Deal value (MRR), deal type (new/upgrade/renewal)
  - Sales stage (1-6), close probability (%)
  - Assigned sales rep, expected close date
  - Product(s) interested in (SurplusAI, PredRadar, etc.)
  - Key contacts (decision maker, technical evaluator, legal)
  - Notes and activity log
  - Document attachments (proposal, contract, SOW)
  - Historical interactions (email, call logs)
```

### 8.3 Contract Management and E-Signatures (Docuseal :3010)

Docuseal runs on AIOPS at port 3010 and handles all enterprise contract workflows:

**Contract Types:**
| Type | Description | Docuseal Template |
|------|-------------|-------------------|
| SaaS Subscription Agreement | Standard terms for subscription services | `saas-agreement-template` |
| Enterprise Master Services Agreement | Custom terms for enterprise clients | `msa-enterprise-template` |
| Statement of Work | Scope, deliverables, timeline | `sow-template` |
| Data Processing Addendum | GDPR/CCPA compliance terms | `dpa-template` |
| Service Level Agreement | Uptime, response time, credits | `sla-template` |
| Non-Disclosure Agreement | Mutual protection of confidential info | `nda-template` |

**Contract Workflow:**
1. Quote approved in FRGCRM
2. Contract generated via Docuseal API from template
3. Contract sent to prospect for e-signature
4. Docuseal webhook on completion updates FRGCRM deal status
5. Signed PDF stored in MinIO (COREDB port 9000)
6. Signed contract URL recorded in FRGCRM deal record
7. Subscription activated in Stripe
8. Onboarding initiated

**Esignature compliance:** Docuseal provides ESIGN Act / eIDAS compliant signatures with full audit trail.

### 8.4 Enterprise SLA Framework

SLA terms for paid tiers are backed by real monitoring infrastructure (Prometheus at :9090, Grafana at :3002):

| Tier | Uptime SLA | Support Hours | Response Time (P1) | Resolution Time (P1) | Service Credits |
|------|-----------|--------------|-------------------|---------------------|----------------|
| Free | Best effort | N/A | N/A | N/A | N/A |
| Pro | 99.5% | Business hours (9-5 ET) | 4 hours | 24 hours | 5% per hour below SLA |
| Enterprise | 99.9% | 24/7 | 1 hour | 8 hours | 10% per hour below SLA |
| White-Label | 99.95% | 24/7 + dedicated | 30 minutes | 4 hours | 15% per hour below SLA |

**SLA measurement:**
- Uptime measured via Uptime Kuma (port 3001) and Prometheus (port 9090)
- Monthly calculation: (total minutes - downtime minutes) / total minutes * 100
- Exclusion: scheduled maintenance (notified 7 days in advance), ISP outages, force majeure
- Credits applied as account credit on next invoice

**Support escalation matrix:**
```
P1 (System Down):  Immediate escalation to on-call engineer
P2 (Degraded):     4-hour response, next-business-day resolution target
P3 (Minor Issue):  Next-business-day response
P4 (Question):     3-business-day response
```

### 8.5 Security Questionnaire / Compliance Package

Enterprise prospects require security due diligence. The compliance package includes:

**Standard Security Package Contents:**
1. SOC 2 Type II Report (target: completed by Month 12)
2. Penetration test results (annual, first test at Month 6)
3. Data flow diagram (ecosystem-level, per-product)
4. Infrastructure architecture diagram (three-node topology)
5. Encryption standards document (AES-256 at rest, TLS 1.3 in transit)
6. Access control policy (Tailscale mesh, 127.0.0.1 binds, .env files chmod 600)
7. Incident response plan (see INCIDENT_RESPONSE_FRAMEWORK.md)
8. Business continuity / disaster recovery plan
9. Data retention and deletion policy
10. Subprocessor list (Hetzner, Hostinger, Stripe, DeepSeek, Tailscale, Cloudflare)

**Automated compliance evidence collection:**
- PM2 process health: Self-healing, monitored via `pm2 jlist` and ecosystem guardian
- Docker container health: HEALTHCHECK on all containers, monitored via docker ps
- Network exposure: Daily ss/netstat audit ensuring zero 0.0.0.0 binds
- Secret exposure: Weekly pm2 jlist scan for plaintext secrets
- Image pinning: Daily check for zero `:latest` Docker tags
- Backup verification: Daily automated checks within 26-hour recency window

### 8.6 Proof-of-Concept Program

For enterprise prospects requiring validation before commitment:

**POC Structure:**
| Element | Detail |
|---------|--------|
| Duration | 14 days (standard), 30 days (complex) |
| Scope | Pre-defined use cases with success criteria |
| Support | Dedicated onboarding engineer |
| Data | Sandbox environment on shared infrastructure |
| Conversion | 60% of POCs convert to paid (target) |

**POC Success Criteria Examples:**

SurplusAI POC:
- Process 100+ cases from prospect's county of interest
- Demonstrate AI parsing accuracy >80% auto-accept rate
- Show lead scoring with at least 5 qualified leads generated
- Integration demo: webhook delivery to prospect's CRM

Prediction Radar POC:
- 14 days of real-time predictions with >60% accuracy
- API integration test (100 calls/day)
- Custom dashboard demo in Grafana

**POC-to-paid conversion incentives:**
- POC setup fee ($500) credited toward first invoice
- Discounted first 3 months (15% off standard pricing)
- Grandfathered pricing for first 12 months

---

## 9. Financial Dashboard

### 9.1 Real-Time MRR/ARR Tracking

Financial dashboards render in Superset (port 8088) connected to the consolidated billing database.

**MRR Dashboard Metrics:**

| Metric | Definition | Calculation | Update Frequency |
|--------|-----------|-------------|-----------------|
| MRR | Monthly Recurring Revenue | Sum of all active subscription amounts | Real-time (Stripe webhook) |
| ARR | Annualized MRR | MRR * 12 | Real-time |
| New MRR | Revenue from new customers | Sum of first-month subscription value | Daily |
| Expansion MRR | Revenue from upgrades | Difference in subscription value after change | Daily |
| Churned MRR | Revenue lost from cancellations | Sum of canceled subscription values | Daily |
| Contraction MRR | Revenue lost from downgrades | Difference in subscription value after change | Daily |
| Net New MRR | New + Expansion - Churned - Contraction | Calculated from components | Daily |
| MRR Growth Rate | Month-over-month MRR change | (Current MRR - Previous MRR) / Previous MRR * 100 | Monthly |

**Dashboard Layout (Superset :8088):**
```
+------------------------------------------------------------------+
|  MRR Trend (Area Chart, 12-month rolling)                        |
|  [Line: Total MRR, Stacked areas: FRG/SurplusAI/PredRadar/etc]   |
+------------------------------------------------------------------+
|  MRR Breakdown (Pie Chart)     |  Key Metrics (Big Numbers)      |
|  - By product                  |  MRR: $72,260                   |
|  - By tier                     |  ARR: $867,120                  |
|  - By customer segment         |  Net New MRR: +$5,800           |
+--------------------------------+  MRR Growth: +8.7% MoM          |
|  MRR Waterfall (Bar Chart)     |  Active Subscriptions: 175      |
|  New | Expansion | Churned     |  Average Revenue: $413          |
+------------------------------------------------------------------+
```

### 9.2 Churn and Retention Cohorts

**Churn Dashboard Metrics:**

| Metric | Definition | Target |
|--------|-----------|--------|
| Monthly Logo Churn | % of customers who cancel | <5% |
| Monthly Revenue Churn | % of MRR lost to cancellations | <3% |
| Net Revenue Retention | Revenue from existing customers after expansion/contraction | >110% |
| Gross Revenue Retention | Revenue retained excluding expansions | >95% |
| 12-Month Retention | % of customers still active after 12 months | >55% |

**Cohort Analysis (Superset :8088):**
```
+------------------------------------------------------------------+
|  Retention Cohort Table (grid, months since acquisition)         |
|  Rows: acquisition month (Jan, Feb, Mar...)                      |
|  Columns: Month 1, Month 2, Month 3, ... Month 12               |
|  Values: % of cohort still active                                |
+------------------------------------------------------------------+
|  Survival Curve (Line Chart)                                     |
|  Lines: Pro tier, Enterprise tier, by product                   |
+------------------------------------------------------------------+
|  Churn Reason Breakdown (Bar Chart)                              |
|  Categories: price, feature gap, no longer needed, etc.          |
+------------------------------------------------------------------+
```

**Retention levers by churn reason:**
- Price sensitivity: Offer annual discount, downgrade tier recommendation
- Feature gap: Product roadmap communication, beta access
- No longer needed: Usage analysis, show value delivered, win-back campaign
- Poor experience: Account review, dedicated support remediation

### 9.3 Revenue by Product, Segment, Geography

**Product Breakdown (Superset :8088):**

```
+------------------------------------------------------------------+
|  Revenue by Product (Stacked Bar Chart, monthly)                  |
|  FRG Nationwide | SurplusAI | Attorney Mkt | Pred Radar | ...    |
+------------------------------------------------------------------+
|  Revenue by Customer Segment (Pie Chart)                         |
|  Enterprise (>$2K/mo) | Mid-Market ($500-$2K) | SMB (<$500)     |
+------------------------------------------------------------------+
|  Revenue by Geography (Choropleth Map)                           |
|  US states colored by revenue concentration                     |
+------------------------------------------------------------------+
```

**Segment definitions:**
- **Enterprise** (>$2K/mo): SurplusAI Enterprise, AI Ops Enterprise, Wheeler Brain, White-Label
- **Mid-Market** ($500-$2K/mo): SurplusAI Pro, AI Ops Pro, Wheeler Brain Growth
- **SMB** (<$500/mo): Prediction Radar, Attorney Marketplace Premium, Data API Pro

**Target revenue distribution (Month 12):**
- Enterprise: 45% of revenue (highest ACV, lowest churn)
- Mid-Market: 35% of revenue (growth segment)
- SMB: 20% of revenue (high volume, acquisition funnel)

### 9.4 Cash Flow and Runway Monitoring

**Cash Dashboard (Superset :8088):**

```
+------------------------------------------------------------------+
|  Cash Balance (Area Chart, daily)                                |
|  Shows: incoming revenue, outgoing expenses, net balance         |
+------------------------------------------------------------------+
|  Runway Calculation (Big Number + Trend)                         |
|  Current Cash: $349,693                                          |
|  Monthly Burn: $9,613                                            |
|  Runway: 36 months                                               |
+------------------------------------------------------------------+
|  Cash Flow Statement (Table, monthly)                            |
|  Operating Revenue | Operating Expenses | Capex | Net Cash Flow  |
+------------------------------------------------------------------+
```

**Key cash metrics tracked:**
- Cash balance (current + projected)
- Monthly burn rate (fixed + variable costs)
- Runway in months
- Days sales outstanding (DSO) for invoiced customers
- Payment success rate (Stripe dunning metrics)

### 9.5 Investor-Grade Financial Reporting

**Monthly Investor Reporting Package (generated via Superset + API):**

1. **Executive Summary** (1 page)
   - MRR, ARR, growth rate
   - Key wins and losses
   - Notable customer stories

2. **Revenue Analysis** (2 pages)
   - Revenue by product, tier, geography
   - Cohort retention analysis
   - Net revenue retention by segment

3. **Unit Economics** (1 page)
   - CAC by channel
   - LTV:CAC ratio
   - Payback period

4. **Cash Flow** (1 page)
   - Cash position and runway
   - Monthly burn rate
   - Capital efficiency ratio (ARR / total capital raised)

5. **Operational Metrics** (1 page)
   - System uptime (via Uptime Kuma :3001, Prometheus :9090)
   - Service health (59/61 as of May 24)
   - Customer support metrics (response time, satisfaction)

**Automated report delivery:**
```
Superset API (:8088) -> Scheduled export (PDF, first of month)
  -> Stored in MinIO (COREDB :9000)
  -> Sent to investor distribution list via SendGrid
```

---

## 10. Implementation Roadmap

### 10.1 Phase 0: Blocker Resolution (Week 1-2)

**Objective: Remove all P0/P1 blockers preventing first dollar of revenue.**

| Step | Action | Owner | Timeline | Success Criteria |
|------|--------|-------|----------|-----------------|
| 0.1 | Fix COREDB PostgreSQL connectivity | Infrastructure | 2-4h | AIOPS connects to COREDB:5432 |
| 0.2 | Restore DEEPSEEK_API_KEY to FRGCRM | Devops | 30min | FRGCRM API at :8082 returns AI analysis |
| 0.3 | Enable Stripe live mode on Prediction Radar | Devops | 4h | Test transaction processes in production mode |
| 0.4 | Stabilize SurplusAI scraper agent | Agent team | 2h | Scraper PM2 shows 0 restarts after 24h |
| 0.5 | Stabilize voice agent | Agent team | 2h | Voice PM2 shows 0 restarts after 24h |
| 0.6 | Repair PipelineDAG | Engineering | 4h | All 6 stages passing |

**Gate: All Stage 2 metrics at 100/100 + P0/P1 blockers resolved.**

### 10.2 Phase 1: Revenue Activation (Weeks 2-4)

**Objective: First paying customers onboarded across 2 products.**

| Step | Action | Owner | Timeline | Success Criteria |
|------|--------|-------|----------|-----------------|
| 1.1 | Deploy Prediction Radar subscription flow | Engineering | 5 days | User can sign up, pay, and access SaaS |
| 1.2 | Implement Stripe webhook handler | Engineering | 2 days | Subscriptions created, updated, canceled via webhooks |
| 1.3 | Build self-service billing portal | Engineering | 3 days | Users can manage subscription, payment method |
| 1.4 | Deploy FRG automated claimant matching | Engineering | 3 days | 10+ matches/day generated |
| 1.5 | Launch Prediction Radar to select beta users | Product | 2 days | 10+ paid subscribers |
| 1.6 | Build MRR dashboard in Superset (:8088) | Monitoring | 3 days | MRR/ARR/churn dashboards rendering |
| 1.7 | Configure Stripe dunning | Devops | 1 day | Failed payment recovery automated |

**Gate: $2,500 MRR achieved. Stripe payment flow end-to-end verified.**

### 10.3 Phase 2: Revenue Scaling (Weeks 5-8)

**Objective: Scale to 3+ revenue streams with automated billing operations.**

| Step | Action | Owner | Timeline | Success Criteria |
|------|--------|-------|----------|-----------------|
| 2.1 | Activate SurplusAI Pro subscriptions | Engineering | 5 days | Self-service signup -> payment -> access |
| 2.2 | Deploy Attorney Marketplace Phase 1 | Engineering | 2 weeks | Attorney database, manual assignment improvements |
| 2.3 | Implement Stripe Connect for marketplace | Engineering | 5 days | Attorney payouts via Stripe Connect |
| 2.4 | Build usage metering for API tiers | Engineering | 3 days | Stripe metered billing operational |
| 2.5 | Deploy Revenue Share Engine (:8124) | Engineering | 5 days | Automated payout calculation and approval |
| 2.6 | Build financial dashboards (Superset :8088) | Monitoring | 3 days | All dashboards: MRR, churn, cohorts, cash flow |
| 2.7 | Create investor reporting package | Product | 3 days | Automated monthly PDF report generation |
| 2.8 | Implement multi-currency support | Engineering | 5 days | EUR/GBP pricing activated |

**Gate: $15,000 MRR, 3 active revenue streams, automated billing operations.**

### 10.4 Phase 3: Ecosystem Monetization (Weeks 9-16)

**Objective: Activate all 8 revenue systems with full monetization.**

| Step | Action | Owner | Timeline | Success Criteria |
|------|--------|-------|----------|-----------------|
| 3.1 | Launch AI Ops as product (Starter/Pro tiers) | Product | 2 weeks | 5+ paying AI Ops subscribers |
| 3.2 | Activate Wheeler Brain Enterprise subscriptions | Product | 2 weeks | 3+ enterprise agent subscriptions |
| 3.3 | Deploy Data API with free/paid tiers | Engineering | 1 week | 10+ API subscribers |
| 3.4 | Implement white-label onboarding flow | Engineering | 2 weeks | Custom domain, branding, tenant isolation |
| 3.5 | Launch affiliate/referral program | Product | 1 week | Referral tracking and commission automation |
| 3.6 | Data licensing agreements executed | Business | 4 weeks | 2+ data licensing customers |
| 3.7 | Professional services catalog published | Product | 1 week | Service packages with fixed pricing |
| 3.8 | Full financial automation | Engineering | 2 weeks | Quote-to-cash end-to-end automated |

**Gate: $50,000 MRR, all 8 revenue systems monetized, <5% churn.**

### 10.5 Phase 4: Autonomous Revenue Operations (Month 5+)

**Objective: Revenue operations run autonomously with minimal manual intervention.**

| Step | Action | Owner | Timeline | Success Criteria |
|------|--------|-------|----------|-----------------|
| 4.1 | ASC 606 revenue recognition automation | Finance | 2 weeks | GAAP-compliant deferred revenue tracking |
| 4.2 | 1099 generation automation | Engineering | 2 weeks | Automated IRS filing for attorney payouts |
| 4.3 | Revenue forecasting ML model | ML team | 3 weeks | 80% forecast accuracy at product level |
| 4.4 | Predictive churn detection | ML team | 3 weeks | Churn prediction >70% precision |
| 4.5 | Automated revenue optimization | Engineering | 4 weeks | Dynamic pricing, upgrade prompts, retention offers |
| 4.6 | Infrastructure auto-scaling | Infrastructure | 2 weeks | Services scale on demand based on revenue growth |

**Gate: $100K MRR, autonomous revenue operations, <3% revenue churn.**

---

## 11. Risk and Contingency

### 11.1 Revenue-Specific Risks

| Risk | Probability | Impact | Mitigation | Contingency |
|------|-----------|--------|------------|-------------|
| COREDB remains unreachable beyond Week 2 | Medium | Critical | Phase 1 on local AIOPS PG; COREDB bypass architecture | All data on AIOPS, COREDB used for backup only |
| Stripe live mode reveals integration bugs | Low | High | Test all webhooks in test mode before switching | Rollback to test mode, fix bugs, re-switch |
| DEEPSEEK_API_KEY rate limits at scale | Medium | Medium | LiteLLM caching at :4049; model fallback chain | Use alternative model providers (OpenAI, Anthropic) |
| Payment failures >5% | Low | Medium | Stripe dunning automation; redundant payment methods | Manual payment follow-up for enterprise accounts |
| Attorney payout disputes | Low | High | Clear revenue share agreements in Docuseal; audit trail | Mediation process defined in attorney agreement |
| Subscription cannibalization | Medium | Low | Clear tier differentiation; upgrade paths | Adjust pricing, add features to higher tiers |
| Competitor price wars | Medium | Low | Compete on data quality, not price | Bundle products, increase switching costs |

### 11.2 Revenue Blockers -- Contingency Timeline

| Blocker | Primary Fix | Contingency Fix | Contingency Impact | Max Timeline |
|---------|------------|-----------------|-------------------|-------------|
| COREDB connectivity | Fix pg_hba.conf | Bypass COREDB, run all on AIOPS | $25/mo additional AIOPS storage | 1 week |
| DEEPSEEK_API_KEY missing | env -i delete+start | Hardcode key in ecosystem.config.js (temp) | Security downgrade, rotated weekly | 2 days |
| Stripe test mode | Switch to live keys | Manual invoicing via Stripe Invoices | Slower payment collection | 1 week |
| Scraper restart loop | PM2 delete+start | Rewrite scraper module | 2-3 day delay | 1 week |
| PipelineDAG failures | Stage-by-stage fix | Manual data flows | 80% reduction in throughput | 2 weeks |
| Marketplace frontend | Build from scratch | Use Docuseal + email as interim | Limited functionality | 4 weeks |

### 11.3 Break-Glass Revenue Plan

If primary monetization is delayed beyond 1 month, execute the following emergency revenue play:

**Day 30 Emergency Actions (if MRR < $1,000):**
1. **Professional services push**: Offer Wheeler ecosystem hardening as a service to other companies. Price: $5,000-$15,000 per engagement. Target: legal tech and AI infrastructure companies.
2. **Data export sale**: Package existing case data (anonymized) and sell as one-time data license. Price: $2,500 per dataset.
3. **Prediction Radar fast launch**: Strip down to essential features, manual payment collection via Stripe Invoices, no subscription automation. Price: $29/mo (discount for early adopters).
4. **Consulting retainer**: Offer ongoing AI Ops consulting at $5,000/month retainer to 1-2 clients.

**Day 60 Emergency Actions (if MRR < $5,000):**
1. **White-label fire sale**: Offer white-label SurplusAI at $997/mo (80% discount from list price) to first 5 law firms. Lock in 12-month contract. Collect testimonials.
2. **Data giveaway**: Free data access in exchange for case studies and testimonials.
3. **Partner concierge**: Manually match attorneys to cases via email (no marketplace frontend). Collect 30% referral fee on each match.

### 11.4 Success Criteria Gates

| Gate | Criteria | Timeline Target | Owner |
|------|----------|----------------|-------|
| G0 | All P0/P1 blockers resolved | Week 2 | Infrastructure |
| G1 | First paying customer onboarded | Week 3 | Product |
| G2 | $2,500 MRR achieved | Week 4 | Revenue Engineering |
| G3 | 3 revenue streams active | Week 6 | Product |
| G4 | $15,000 MRR achieved | Week 8 | Revenue Engineering |
| G5 | Automated billing operations | Week 8 | Engineering |
| G6 | $50,000 MRR achieved | Week 16 | Revenue Engineering |
| G7 | All 8 revenue systems monetized | Week 16 | Product |
| G8 | $100,000 MRR achieved | Month 6 | Revenue Engineering |
| G9 | Autonomous revenue operations | Month 6 | Engineering |

**Gate failure protocol:** If a gate is missed by more than 2 weeks, convene the Revenue Engineering Council (all system owners) to reassess strategy, resources, and timeline. Document revised forecast.

---

## Appendix A: Infrastructure Reference for Monetization

### A.1 Payment Processing Endpoints

| Service | Port | Purpose | Revenue System | Status |
|---------|------|---------|---------------|--------|
| Stripe API (Prediction Radar) | External | Payment processing | Prediction Radar | TEST MODE (blocker) |
| FRGCRM API | 8082 | Sales pipeline, CRM | FRG Nationwide | ONLINE (missing key) |
| Docuseal | 3010 | Contract e-signatures | Attorney Marketplace | HEALTHY |
| Superset | 8088 | Financial dashboards | All systems | HEALTHY |
| Command Center | 8100 | Revenue operations hub | Wheeler Brain | ONLINE |
| Prometheus | 9090 | Revenue metrics collection | All systems | HEALTHY |
| Grafana | 3002 | Revenue dashboards | All systems | HEALTHY |
| LiteLLM | 4049 | AI inference (billing data) | All systems | HEALTHY |

### A.2 Stripe Price ID Reference

| Product | Tier | Billing | Price ID | Status |
|---------|------|---------|----------|--------|
| Prediction Radar | Pro | Monthly | `price_1TN3owPKXFjwOjQXYvdcKsgc` | Configured (test mode) |
| Prediction Radar | Agency | Monthly | `price_1TN3opPKXFjwOjQXdwXamPuw` | Configured (test mode) |
| SurplusAI | Pro | Monthly | Needs creation | Not created |
| SurplusAI | Enterprise | Monthly | Needs creation | Not created |
| Attorney Marketplace | Premium | Monthly | Needs creation | Not created |
| Attorney Marketplace | Platinum | Monthly | Needs creation | Not created |
| AI Ops | Starter | Monthly | Needs creation | Not created |
| AI Ops | Pro | Monthly | Needs creation | Not created |

### A.3 Billing Database Schema (Core Tables)

```sql
-- Revenue tracking schema (in wheeler_core on COREDB, or local AIOPS PG)
CREATE SCHEMA IF NOT EXISTS revenue;

CREATE TABLE revenue.products (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code            VARCHAR(64) UNIQUE NOT NULL,
    name            VARCHAR(256) NOT NULL,
    description     TEXT,
    stripe_product_id VARCHAR(128),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE revenue.price_tiers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id      UUID NOT NULL REFERENCES revenue.products(id),
    tier_code       VARCHAR(64) NOT NULL,
    tier_name       VARCHAR(128) NOT NULL,
    price_cents     INTEGER NOT NULL,
    billing_interval VARCHAR(16) NOT NULL DEFAULT 'month',
        -- month | year | one_time
    stripe_price_id VARCHAR(128),
    features        JSONB,
    active          BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(product_id, tier_code, billing_interval)
);

CREATE TABLE revenue.subscriptions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id         UUID NOT NULL,
    price_tier_id       UUID NOT NULL REFERENCES revenue.price_tiers(id),
    status              VARCHAR(32) NOT NULL DEFAULT 'active',
        -- active | trialing | past_due | canceled | expired
    stripe_subscription_id  VARCHAR(128),
    current_period_start    TIMESTAMPTZ,
    current_period_end      TIMESTAMPTZ,
    trial_end               TIMESTAMPTZ,
    canceled_at             TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE revenue.usage_records (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES revenue.subscriptions(id),
    meter_name      VARCHAR(64) NOT NULL,
    quantity        INTEGER NOT NULL,
    recorded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE revenue.invoices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES revenue.subscriptions(id),
    stripe_invoice_id VARCHAR(128),
    amount_cents    INTEGER NOT NULL,
    status          VARCHAR(32) NOT NULL DEFAULT 'open',
        -- open | paid | void | uncollectible
    paid_at         TIMESTAMPTZ,
    invoice_pdf_url VARCHAR(512),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE revenue.payouts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payee_type      VARCHAR(32) NOT NULL,
        -- attorney | affiliate | partner
    payee_id        UUID NOT NULL,
    gross_amount_cents  INTEGER NOT NULL,
    fee_cents           INTEGER NOT NULL,
    net_amount_cents    INTEGER NOT NULL,
    status          VARCHAR(32) NOT NULL DEFAULT 'calculated',
        -- calculated | approved | paid | failed | reversed
    stripe_transfer_id  VARCHAR(128),
    paid_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### A.4 Key Monitoring Metrics for Revenue Operations

| Metric | Source | Collection | Dashboard | Alert Threshold |
|--------|--------|-----------|-----------|-----------------|
| Stripe payment success rate | Stripe API | Real-time (webhook) | Revenue Dashboard | <95% success rate |
| Subscription churn events | Stripe API + DB | Real-time (webhook) | Churn Dashboard | >5% monthly churn |
| Failed payment count | Stripe API | Real-time (webhook) | Dunning Dashboard | >10 failures/day |
| MRR change | Calculation | Daily | MRR Dashboard | Negative MRR growth |
| API usage (metered) | Redis counters | 5-minute batch | Usage Dashboard | >80% of plan limit |
| New signups | Application DB | Real-time | Growth Dashboard | 0 signups/48h |
| Payout success rate | Stripe API | Real-time | Payout Dashboard | <90% success |
| Invoice DSO | Calculation | Weekly | Cash Dashboard | >45 days DSO |

---

## Appendix B: Revenue Engine Agent Configuration

The Wheeler Brain OS operates a dedicated Revenue Intelligence agent that monitors and optimizes revenue operations:

```markdown
# Revenue Intelligence Agent Specification

## Purpose
Monitor, analyze, and optimize all revenue streams across the Wheeler ecosystem.

## Data Sources
- Stripe API (subscriptions, invoices, payouts, usage)
- FRGCRM (port 8082) (sales pipeline, deals)
- Superset (port 8088) (dashboard data)
- Prometheus (port 9090) (infrastructure metrics)
- LiteLLM (port 4049) (AI usage billing)
- Neo4j ecosystem graph (port 7687) (entity relationships)

## Responsibilities
1. Daily revenue reconciliation (stripe vs. local DB)
2. Churn analysis and retention recommendations
3. Pricing optimization recommendations
4. Sales pipeline health monitoring
5. Revenue forecast updates
6. Cross-system revenue attribution
7. Anomaly detection (unusual billing patterns)
8. Investor reporting preparation

## Output
- Weekly revenue health report (email to stakeholders)
- Real-time dashboards in Superset (port 8088)
- Alerts via Discord for revenue anomalies
- Monthly investor-ready financial package
```

---

## Appendix C: Revenue Operations Runbook

### C.1 Daily Revenue Checks

```bash
# 1. Check Stripe payment health
curl -s https://api.stripe.com/v1/balance \
  -H "Authorization: Bearer ${STRIPE_SECRET_KEY}" | jq '.available[0].amount'

# 2. Verify subscription sync
# Query Superset API for subscription count
curl -s http://127.0.0.1:8088/api/v1/query/ \
  -H "Authorization: Bearer ${SUPERSET_TOKEN}" \
  -d '{"sql": "SELECT COUNT(*) FROM revenue.subscriptions WHERE status = 'active'"}' | jq .

# 3. Check for failed payments (last 24h)
curl -s https://api.stripe.com/v1/invoices?status=open&created.gte=$(date -d '-1 day' +%s) \
  -H "Authorization: Bearer ${STRIPE_SECRET_KEY}" | jq '.data | length'

# 4. Verify all revenue services online
pm2 jlist | jq '[.[] | select(.name | test("frgcrm|prediction|surplusai|attorney")) | {name: .name, status: .pm2_env.status}]'
```

### C.2 Weekly Revenue Reconciliation

```bash
# 1. Compare Stripe MRR vs. local DB MRR
# Run reconciliation script
/opt/apps/revenue-ops/scripts/reconcile-mrr.sh

# 2. Verify no unpaid invoices >30 days old
curl -s https://api.stripe.com/v1/invoices?status=open&created.gte=$(date -d '-30 days' +%s) \
  -H "Authorization: Bearer ${STRIPE_SECRET_KEY}" | jq '.data[] | {id, amount_due, created}'

# 3. Review payout queue
psql -h 127.0.0.1 -p 5432 -d revenue_db -c \
  "SELECT COUNT(*), status FROM revenue.payouts GROUP BY status;"

# 4. Update revenue forecast
# Trigger forecast recalculation
curl -X POST http://127.0.0.1:8100/api/v1/revenue/forecast/refresh
```

### C.3 Monthly Revenue Close

```yaml
Day 1:
  - Finalize previous month's MRR
  - Run ASC 606 deferred revenue calculation
  - Generate monthly investor report (Superset PDF export)
  - Send invoices for annual subscribers up for renewal

Day 5:
  - Process all approved payouts (attorneys, affiliates)
  - Reconcile Stripe fees and taxes
  - Update revenue recognition entries

Day 10:
  - Run churn analysis for previous month
  - Update cohort retention tables
  - Revenue forecast for current month

Day 15:
  - Review professional services pipeline
  - Audit data licensing agreements for compliance

Day 20:
  - Mid-month MRR check against forecast
  - Adjust forecast if needed

Day 25:
  - Begin next month's billing preparation
  - Review upcoming renewals and expirations
```

### C.4 Emergency Procedures

**Revenue System Outage:**
```
1. P1 alert: "Revenue system X is down" -> Check PM2/Docker status
2. Immediate restore: pm2 restart <service> or docker restart <container>
3. If not restored in 5 minutes: Execute rollback
4. Verify payment processing not disrupted
5. Post-mortem and fix within 24 hours
```

**Stripe API Failure:**
```
1. Check Stripe status dashboard (status.stripe.com)
2. If Stripe-side: Enable manual invoice processing
   - Create invoices via Stripe Dashboard
   - Collect payments via Stripe Invoices (email payment links)
3. Queue failed subscription events for retry
4. Restore automated processing when Stripe recovers
```

**Mass Payment Failure:**
```
1. Halt all outgoing payouts
2. Check Stripe Connect account balances
3. Verify platform account has sufficient funds
4. If insufficient: Prioritize attorney payouts (highest business impact)
5. Notify affected payees with expected resolution timeline
6. Resume payouts in batches after root cause fixed
```

---

## Appendix D: Glossary

| Term | Definition |
|------|-----------|
| ACV | Annual Contract Value |
| ARPA | Average Revenue Per Account |
| ARR | Annualized Recurring Revenue (MRR * 12) |
| ASC 606 | Revenue recognition accounting standard |
| BANT | Budget, Authority, Need, Timeline (sales qualification) |
| DAC | Days Sales Outstanding (average days to collect payment) |
| LTV | Customer Lifetime Value |
| CAC | Customer Acquisition Cost |
| MRR | Monthly Recurring Revenue |
| NRR | Net Revenue Retention |
| PAYG | Pay As You Go (usage-based pricing) |
| POC | Proof of Concept (pre-sale evaluation) |
| SLA | Service Level Agreement |
| SOW | Statement of Work |

---

*End of Enterprise Monetization Report v1.0.0*

**Next Review Date:** 2026-06-24
**Owner:** Wheeler Brain OS -- Revenue Engineering Division
**Related Documents:**
- `/root/WHEELER_REVENUE_ENGINE_ARCHITECTURE.md` -- Revenue system architecture and blockers
- `/root/SURPLUSAI_PRODUCTIZATION_PLAN.md` -- SurplusAI product tiers and implementation plan
- `/root/ATTORNEY_MARKETPLACE_ARCHITECTURE.md` -- Marketplace architecture and revenue sharing
- `/root/STAGE2_QA_SCORECARD_FINAL.md` -- Infrastructure QA validation (100/100)
- `/root/MASTER_EXECUTION_STATE.md` -- Current execution state
- `/root/DEPLOYMENT_SYSTEM.md` -- Deployment and rollback architecture
- `/root/.claude/agents/revenue-intelligence.md` -- Revenue Intelligence agent specification
