# Wheeler Ecosystem DATA PRIVACY GOVERNANCE FRAMEWORK

**Version:** 1.0.0
**Date:** 2026-05-25
**Classification:** INTERNAL -- WHEELER CONFIDENTIAL
**Status:** DRAFT -- ⚖️ ATTORNEY REVIEW REQUIRED
**Governing Authority:** Wheeler Architecture Review Board (WARB)
**Data Protection Officer (DPO):** Human Operator (to be formally designated)

---

## TABLE OF CONTENTS

1. [DATA INVENTORY & CLASSIFICATION](#1-data-inventory--classification)
2. [REGULATORY LANDSCAPE](#2-regulatory-landscape)
3. [PRIVACY PROGRAM FRAMEWORK](#3-privacy-program-framework)
4. [DATA GOVERNANCE CONTROLS](#4-data-governance-controls)
5. [VENDOR/THIRD-PARTY DATA GOVERNANCE](#5-vendorthird-party-data-governance)
6. [INCIDENT RESPONSE](#6-incident-response)
7. [COMPLIANCE MONITORING](#7-compliance-monitoring)
8. [PRIVACY BY DESIGN](#8-privacy-by-design)

---

## 1. DATA INVENTORY & CLASSIFICATION

### 1.1 Classification Schema

| Tier | Label | Description | Examples | Protection Level |
|------|-------|-------------|----------|-----------------|
| Tier 0 | Public | Lawfully public, no restrictions | Published court opinions, public property records, county foreclosure notices | Standard -- no special controls |
| Tier 1 | Internal | Business records, non-sensitive | Aggregated analytics, de-identified trends, system metrics, employee directory (non-sensitive fields) | Access control -- authenticated only |
| Tier 2 | Confidential | Business-sensitive, competitive | Lead scoring algorithms, attorney performance metrics, pricing models, business strategy docs, ML model weights | Strict access control -- need-to-know |
| Tier 3 | Sensitive PII | Personally identifiable, regulated | Names + addresses + phone numbers, email addresses, dates of birth, IP addresses | Encryption + access logging + purpose limitation |
| Tier 4 | Restricted PII | Highly sensitive, heavily regulated | SSN (full or partial), bank account numbers, driver's license numbers, full financial statements, credit card numbers (if stored) | Encryption at rest + transit, access audit trail, data masking, field-level encryption |
| Tier 5 | Regulated Special | Sector-specific regulation | FCRA-covered consumer report data, attorney-client privileged communications, biometric data, protected health information (HIPAA) | Maximum controls, legal hold capable, strict purpose limitation |

### 1.2 Data Tier Assignment Rules

| Rule | Description |
|------|-------------|
| R1 | Any data containing a field from Tier 4 inherits Tier 4 classification for the entire record |
| R2 | Aggregated/de-identified data derived from Tier 3-5 data drops to Tier 1 if de-identification meets re-identification risk threshold (see Section 1.3) |
| R3 | Data in motion inherits the highest classification of any constituent field |
| R4 | Derived/computed data (scores, predictions, inferences) retains the tier of the source data |
| R5 | Logs that may contain Tier 3+ data are classified at minimum Tier 3 |
| R6 | When in doubt, classify at the higher tier |

### 1.3 De-Identification Standard

For a dataset to be considered de-identified and eligible for Tier 1 classification:

- **Safe Harbor Method:** Removal of all 18 HIPAA-identified direct identifiers (applied analogously for non-health data)
- **Expert Determination:** Statistical determination that re-identification risk is <0.01%
- **Pseudonymization:** Direct identifiers replaced with pseudonyms; key stored separately with access controls equivalent to original tier
- ⚖️ ATTORNEY REVIEW REQUIRED: Determination that de-identification meets applicable state law standards (CCPA, CPA, etc.)

### 1.4 Per-System Data Map

---

#### SYSTEM 1: Court Records (Raw Scrape)

| Attribute | Detail |
|-----------|--------|
| **Data Collected** | Case numbers, property addresses, surplus amounts, sale dates, court names, counties, states, case status, plaintiff/defendant names, docket entries, filing dates, judgment amounts |
| **Classification Tier** | Tier 0-3 (Tier 0 for case metadata, Tier 3 when claimant names + addresses co-occur) |
| **Legal Basis** | Public records exception; legitimate interest (CCPA 1798.105(d)); First Amendment access to court records |
| **Storage Location** | PostgreSQL 16 -- frgops-standby (AIOPS :5433), shared-postgres-recovery (EDGE :5432) |
| **Retention Period** | Indefinite for public records (see Section 4.1 for specific schedule) |
| **Access Controls** | Database authentication only; application-layer access via API; no direct DB access from outside server |
| **Encryption Status** | At rest: AES-256 (disk-level); In transit: TLS not currently enforced on inter-node replication ⚖️ ATTORNEY REVIEW REQUIRED |
| **Third-Party Sharing** | None currently; attorney network (SurplusAI matching) receives case-level access |
| **Cross-Border Transfer** | No -- all data stored on Hetzner/Hostinger (Germany/EU + US) |
| **Applicable Regulations** | CCPA/CPRA (CA residents), state public records laws, state data breach laws |

---

#### SYSTEM 2: Claimant PII (Active)

| Attribute | Detail |
|-----------|--------|
| **Data Collected** | Full name, current and historical addresses, phone numbers (landline, mobile), email addresses, date of birth, SSN (partial/full in specific cases), bankruptcy status, language preference, responsiveness score |
| **Classification Tier** | Tier 3-4 (Tier 4 if SSN or bank account present) |
| **Legal Basis** | Contract necessity (services performed for claimant); legitimate interest (locating claimants for fund disbursement); ⚖️ ATTORNEY REVIEW REQUIRED for SSN processing |
| **Storage Location** | PostgreSQL 16 -- frgops-standby (AIOPS :5433); Neo4j (knowledge graph, limited fields) |
| **Retention Period** | Duration of representation + 5 years (see Section 4.1) |
| **Access Controls** | Role-based access (RBAC); caseworker-level granularity; access logging required |
| **Encryption Status** | At rest: AES-256 (disk-level); Planned: column-level encryption for SSN/financial fields; In transit: TLS 1.3 (target) |
| **Third-Party Sharing** | Skip tracing vendors (planned -- requires DPA), payment processors (Stripe), contracted attorneys |
| **Cross-Border Transfer** | Potential EU->US transfer if Hetzner Germany node stores EU-resident data ⚖️ ATTORNEY REVIEW REQUIRED |
| **Applicable Regulations** | CCPA/CPRA, VCDPA, CPA, CTDPA, UCPA, state data breach laws, GLBA (if financial info), FCRA (if skip tracing data used for eligibility) |

---

#### SYSTEM 3: Attorney Data

| Attribute | Detail |
|-----------|--------|
| **Data Collected** | Name, bar number(s), state licensure, firm affiliation, practice areas, contact info, historical case volume, win rates, average recovery amount, average days-to-close, fee structure, capacity score, client satisfaction metrics |
| **Classification Tier** | Tier 2-3 (Tier 2 for performance metrics, Tier 3 for contact PII) |
| **Legal Basis** | Contract necessity (marketplace participation); legitimate interest (attorney matching/rating); ⚖️ ATTORNEY REVIEW REQUIRED for public performance display |
| **Storage Location** | PostgreSQL 16 -- frgops-standby (AIOPS :5433); Neo4j 5.26 (ecosystem-graph) |
| **Retention Period** | Duration of marketplace participation + 3 years |
| **Access Controls** | Attorney self-access to own profile; internal access need-to-know; aggregated metrics available to matching engine |
| **Encryption Status** | At rest: AES-256 (disk-level); In transit: TLS 1.3 (target) |
| **Third-Party Sharing** | Bar association APIs (verification), no other third-party sharing currently |
| **Cross-Border Transfer** | No |
| **Applicable Regulations** | CCPA/CPRA (CA attorneys), state data breach laws, state bar regulatory rules |

---

#### SYSTEM 4: Skip Tracing Data

| Attribute | Detail |
|-----------|--------|
| **Data Collected** | Third-party consumer data: name aliases, address history, phone numbers, email addresses, social media presence indicators, bankruptcy status, property ownership records |
| **Classification Tier** | Tier 3-5 (Tier 5 if FCRA-covered consumer report data) |
| **Legal Basis** | Legitimate interest (locating claimants); permissible purpose under FCRA (if FCRA-covered); ⚖️ ATTORNEY REVIEW REQUIRED to determine FCRA applicability |
| **Storage Location** | PostgreSQL 16 -- frgops-standby (AIOPS :5433) (planned enrichment pipeline) |
| **Retention Period** | 90 days post-case-close or as required by data vendor agreement |
| **Access Controls** | Strict role-based access; purpose-limited use; no bulk export without approval |
| **Encryption Status** | At rest: AES-256; In transit: TLS 1.3 (target); Vendor data subject to vendor-side controls |
| **Third-Party Sharing** | Skipjack/TLOxp (planned data partners -- requires DPA and FCRA compliance), other data brokers (planned) |
| **Cross-Border Transfer** | Subject to vendor data residency terms |
| **Applicable Regulations** | **FCRA (primary)**, CCPA/CPRA, VCDPA, CPA, CTDPA, UCPA, state data breach laws, FTC Act Section 5 |

---

#### SYSTEM 5: CRM Data

| Attribute | Detail |
|-----------|--------|
| **Data Collected** | Lead records, contact history, communication logs, conversion status, payment history, case notes, document metadata, outreach attempts, response outcomes, preferred communication channel |
| **Classification Tier** | Tier 2-3 (Tier 2 for business records, Tier 3 for communication content with PII) |
| **Legal Basis** | Contract necessity; legitimate interest (business operations); consent (marketing communications) |
| **Storage Location** | PostgreSQL 16 -- various nodes; application-layer CRM interfaces (SurplusAI, FRGCRM) |
| **Retention Period** | Lead data: convert or archive at 180 days cold; Active customer data: duration of relationship + 5 years |
| **Access Controls** | Role-based access; caseworker-scoped data visibility; access logging |
| **Encryption Status** | At rest: AES-256 (disk-level); In transit: TLS 1.3 (target) |
| **Third-Party Sharing** | None currently; potential for marketing automation integration (requires DPA) |
| **Cross-Border Transfer** | No |
| **Applicable Regulations** | CCPA/CPRA, CAN-SPAM (email marketing), TCPA (phone/text outreach), state data breach laws |

---

#### SYSTEM 6: AI Training / Retrieval Data

| Attribute | Detail |
|-----------|--------|
| **Data Collected** | Court records used for model training/fine-tuning; RAG corpus documents; training examples (case outcomes, attorney assignments, scoring features); model inference logs |
| **Classification Tier** | Tier 0-4 (varies by source; de-identified training data targets Tier 1 after de-identification) |
| **Legal Basis** | Legitimate interest (model development); ⚖️ ATTORNEY REVIEW REQUIRED for training on Tier 3-4 data; CCPA potential opt-out right for training on personal data |
| **Storage Location** | PostgreSQL 16 -- surplus_training_examples (planned, AIOPS :5433); model artifacts on filesystem; vector embeddings in application layer |
| **Retention Period** | Training data: 5 years; Model artifacts: lifecycle of model + 2 years; Inference logs: 90 days |
| **Access Controls** | Infrastructure-level access only; training pipeline runs in isolated environment; no direct access from application layer |
| **Encryption Status** | At rest: AES-256; In transit: TLS 1.3; Model artifacts: encryption at rest |
| **Third-Party Sharing** | Anthropic API (Claude), OpenAI API, DeepSeek API (via LiteLLM :4049) -- each subject to API terms; ⚖️ ATTORNEY REVIEW REQUIRED for API provider data usage policies |
| **Cross-Border Transfer** | Yes -- API calls to Anthropic/OpenAI/DeepSeek may be processed in US or other jurisdictions ⚖️ ATTORNEY REVIEW REQUIRED |
| **Applicable Regulations** | CCPA/CPRA (potential training opt-out), FTC Act Section 5 (AI fairness/deception), state AI governance laws (emerging), Colorado AI Act (if applicable), EU AI Act (if EU-resident data) |

---

#### SYSTEM 7: Application/Access/API Logs

| Attribute | Detail |
|-----------|--------|
| **Data Collected** | Application logs, access logs, API request/response logs, authentication logs, error logs, performance traces, audit trails |
| **Classification Tier** | Tier 1-3 (Tier 1 for system metrics; Tier 3 if logs contain PII such as IP addresses, user identifiers, or request bodies with personal data) |
| **Legal Basis** | Legitimate interest (security monitoring, debugging, compliance audit); legal obligation (retain for regulatory compliance) |
| **Storage Location** | ClickHouse (:8123, AIOPS), Loki (observability stack), Prometheus (metrics), log files on application servers (rotated) |
| **Retention Period** | ClickHouse/Loki: rolling 30-day window; Audit logs: 3 years (see Section 4.5); Application logs: 90 days |
| **Access Controls** | Role-based access; logging system access restricted to SRE/DevOps; automated alerting on log anomalies |
| **Encryption Status** | At rest: AES-256 (disk-level); In transit: TLS 1.3 (internal) |
| **Third-Party Sharing** | None; logs are internal only |
| **Cross-Border Transfer** | No |
| **Applicable Regulations** | State data breach laws (if logs contain PII and are breached), ECPA/Stored Communications Act |

---

#### SYSTEM 8: Generated Legal Documents

| Attribute | Detail |
|-----------|--------|
| **Data Collected** | Generated legal documents (claim packages, court filings, representation agreements, settlement documents, demand letters), document metadata, version history, attorney-client communications |
| **Classification Tier** | Tier 2-5 (Tier 2 for document metadata; Tier 3-4 for PII in documents; **Tier 5 for attorney-client privileged communications**) |
| **Legal Basis** | Contract necessity (legal representation); legal obligation (court filing requirements); attorney-client privilege |
| **Storage Location** | Application-layer storage; PostgreSQL metadata; filesystem document store; planned MinIO object store |
| **Retention Period** | Duration of representation + 10 years (statute of repose for legal malpractice claims -- ⚖️ ATTORNEY REVIEW REQUIRED) |
| **Access Controls** | Strict role-based access; case-specific only; no cross-case access; privileged document tagging required |
| **Encryption Status** | At rest: AES-256; In transit: TLS 1.3; Privileged documents: additional access controls |
| **Third-Party Sharing** | Court filing portals (e-filing), service of process vendors (if used) |
| **Cross-Border Transfer** | No |
| **Applicable Regulations** | CCPA/CPRA (litigation exemption may apply -- ⚖️ ATTORNEY REVIEW REQUIRED), attorney-client privilege law, state bar ethical rules, ECPA |

---

#### SYSTEM 9: Payment / Financial Data

| Attribute | Detail |
|-----------|--------|
| **Data Collected** | Stripe transaction records, bank account details (routing + account numbers for disbursement), disbursement records, payment history, fee records, refund records, invoice data |
| **Classification Tier** | Tier 4 (bank account details, routing numbers); Tier 3 (transaction records with PII) |
| **Legal Basis** | Contract necessity (payment processing); legal obligation (tax/financial recordkeeping); GLBA applicability review required |
| **Storage Location** | Stripe (third-party); PostgreSQL (transaction metadata only -- no raw financial instrument numbers); Payment Radar DB |
| **Retention Period** | Transaction records: 7 years (IRS requirement); Bank account details: until account closed + 60 days; Disbursement records: 10 years ⚖️ ATTORNEY REVIEW REQUIRED |
| **Access Controls** | **Never store full payment instrument data in application databases**; Stripe handles PCI-scoped data; application stores only last-4 and token; access limited to finance/ops roles |
| **Encryption Status** | At rest: AES-256 (disk-level + Stripe-managed); In transit: TLS 1.3; PCI DSS compliance via Stripe (Scope: SAQ A) |
| **Third-Party Sharing** | Stripe (payment processor -- DPA in place); potential: bank partners (ACH disbursement), accounting platforms |
| **Cross-Border Transfer** | Stripe data processing subject to Stripe's data processing terms |
| **Applicable Regulations** | **GLBA (if applicable)** ⚖️ ATTORNEY REVIEW REQUIRED, PCI DSS (via Stripe), CCPA/CPRA, state data breach laws, IRS tax recordkeeping requirements, state escheatment/unclaimed property laws |

---

#### SYSTEM 10: Marketing / Outreach Data

| Attribute | Detail |
|-----------|--------|
| **Data Collected** | Email marketing lists, SMS/phone outreach lists, outreach history, conversion tracking, consent records (opt-in/opt-out), communication preferences, campaign analytics, A/B testing data |
| **Classification Tier** | Tier 2-3 (Tier 2 for campaign analytics; Tier 3 for individual contact data with preferences) |
| **Legal Basis** | Consent (opt-in for email/SMS); legitimate interest (existing customer outreach); ⚖️ ATTORNEY REVIEW REQUIRED for TCPA consent documentation |
| **Storage Location** | PostgreSQL (consent records); application-layer storage; planned marketing automation platform |
| **Retention Period** | Consent records: indefinite (proof of consent); Marketing contact data: 2 years since last engagement; Opt-out records: permanent (suppression list) |
| **Access Controls** | Role-based access; marketing team only; suppression list access strictly audited |
| **Encryption Status** | At rest: AES-256; In transit: TLS 1.3 |
| **Third-Party Sharing** | Email delivery service (planned -- requires DPA); SMS gateway (planned -- requires DPA) |
| **Cross-Border Transfer** | Subject to email/SMS provider terms |
| **Applicable Regulations** | **CAN-SPAM Act** (email), **TCPA** (SMS/phone -- strict liability), CCPA/CPRA (opt-out of sale/share), state telemarketing laws, state data breach laws |

---

### 1.5 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA FLOW MAP                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  COUNTY COURTS ──────► SCRAPER ADAPTERS ──────► RAW STORAGE          │
│  (Public Records)         (18 adapters)        (PostgreSQL frgops)   │
│                              │                        │               │
│                              ▼                        ▼               │
│                        PARSING PIPELINE ──────► ENRICHMENT LAYER      │
│                        (Court-specific            (Skip tracing,     │
│                         format normalization)      Phone append)     │
│                              │                        │               │
│                              ▼                        ▼               │
│   ┌─────────────────── SCORING ENGINE ──────► SCORED LEADS ──────┐   │
│   │                    (ML inference)           (PostgreSQL)      │   │
│   │                                                               │   │
│   ▼                         ▼                        ▼            │   │
│ ATTORNEY NETWORK     CLAIMANT OUTREACH      AI TRAINING DATA      │   │
│ (Matching engine)    (SMS/Phone/Email)      (Model fine-tune)     │   │
│      │                     │                        │            │   │
│      ▼                     ▼                        ▼            │   │
│ PAYMENT ────────────► STRIPE ──────────────► DISBURSEMENT         │   │
│ PROCESSING                │                   RECORDS             │   │
│                           ▼                                       │   │
│                    LEDGER / ACCOUNTING                             │   │
│                    (PostgreSQL + external)                        │   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.6 Privacy Risk Heat Map

| System | Volume | Sensitivity | Regulatory Risk | Overall Risk |
|--------|--------|-------------|-----------------|--------------|
| Court Records | HIGH | MEDIUM | LOW | MEDIUM |
| Claimant PII (Active) | MEDIUM | HIGH | HIGH | **HIGH** |
| Attorney Data | MEDIUM | MEDIUM | LOW | MEDIUM |
| Skip Tracing Data | MEDIUM | VERY HIGH | **CRITICAL** | **CRITICAL** |
| CRM Data | HIGH | MEDIUM | MEDIUM | MEDIUM |
| AI Training Data | MEDIUM | HIGH | HIGH | **HIGH** |
| Logs | VERY HIGH | LOW-MEDIUM | MEDIUM | MEDIUM |
| Legal Documents | MEDIUM | VERY HIGH | **CRITICAL** | **CRITICAL** |
| Payment Data | LOW | HIGH | **CRITICAL** | **CRITICAL** |
| Marketing Data | HIGH | MEDIUM | HIGH | **HIGH** |

---

## 2. REGULATORY LANDSCAPE

### 2.1 Applicable US State Privacy Laws

Wheeler ecosystem currently operates in and processes data from residents of multiple US states. The following comprehensive state privacy laws may apply based on processing activities.

| State | Law | Effective | Thresholds Met? | Key Obligations | Private Right of Action? |
|-------|-----|-----------|----------------|-----------------|--------------------------|
| California | CCPA/CPRA | 2020/2023 | ⚖️ ASSESS | Right to know, delete, opt-out, correct, limit sensitive data; DPIA; annual risk assessment | YES -- data breach ($100-$750 per incident) |
| Virginia | VCDPA | 2023-01 | ⚖️ ASSESS | Right to know, delete, opt-out, access, correct, portability; DPIA; data protection assessment | No |
| Colorado | CPA | 2023-07 | ⚖️ ASSESS | Same as VCDPA + opt-out for profiling; DPIA; universal opt-out mechanism (2024) | No |
| Connecticut | CTDPA | 2023-07 | ⚖️ ASSESS | Same as VCDPA + opt-out for profiling | No |
| Utah | UCPA | 2023-12 | ⚖️ ASSESS | Right to know, delete, opt-out, access, portability (limited) | No |
| Iowa | ICDPA | 2025-01 | ⚖️ ASSESS | Right to know, delete, opt-out, access | No |
| Indiana | ICPA | 2026-01 | ⚖️ ASSESS | Right to know, delete, opt-out, access, portability; DPIA | No |
| Tennessee | TIPA | 2025-07 | ⚖️ ASSESS | Right to know, delete, opt-out, access, correct; DPIA; affirmative defense for compliance programs | No |
| Montana | MCDPA | 2024-10 (large)/2025-10 (all) | ⚖️ ASSESS | Right to know, delete, opt-out, access, portability; DPIA | No |
| Oregon | OCPA | 2024-07 | ⚖️ ASSESS | Right to know, delete, opt-out, access, portability, correct; DPIA | No |
| Texas | TDPSA | 2024-07 | ⚖️ ASSESS | Right to know, delete, opt-out, access, correct; DPIA | No |
| Delaware | DPDPA | 2025-01 | ⚖️ ASSESS | Right to know, delete, opt-out, access, correct, portability; DPIA | No |
| New Jersey | NJDPA | 2025-01 | ⚖️ ASSESS | Right to know, delete, opt-out, access, correct, portability; DPIA | No |
| New Hampshire | NHDPA | 2025-01 | ⚖️ ASSESS | Right to know, delete, opt-out, access, correct, portability; DPIA | No |
| Kentucky | KCDPA | 2026-01 | ⚖️ ASSESS | Right to know, delete, opt-out, access, correct, portability; DPIA | No |
| Nebraska | NDPA | 2025-01 | ⚖️ ASSESS | Right to know, delete, opt-out, access, portability | No |
| Maryland | MODPA | 2026-10 | ⚖️ ASSESS | Right to know, delete, opt-out, access, correct, portability; DPIA; **expands definition of sensitive data** | YES -- data breach ($100-$750 per incident) |
| Minnesota | MCDPA | 2025-07 | ⚖️ ASSESS | Right to know, delete, opt-out, access, correct, portability; DPIA; private right of action for data breach | YES -- data breach |

#### Applicability Thresholds (Subject to Change)

The Wheeler ecosystem must assess applicability against each state's thresholds:

- **CCPA:** >$25M gross revenue OR buys/sells PII of >100,000 CA residents OR derives 50%+ revenue from PII sharing
- **VCDPA/CPA/CTDPA/UCPA:** Control/process personal data of >100,000 consumers OR derive >50% revenue from data sale and process >25,000 consumers
- ⚖️ ATTORNEY REVIEW REQUIRED: Formal applicability determination for each state

#### CCPA/CPRA Special Considerations

| Requirement | Status | Notes |
|-------------|--------|-------|
| Notice at Collection | ⚖️ NOT IMPLEMENTED | Required at or before data collection point |
| Privacy Policy | ⚖️ NOT IMPLEMENTED | See Section 3.2 for template |
| Right to Know | ⚖️ NOT IMPLEMENTED | Must respond within 45 days |
| Right to Delete | ⚖️ NOT IMPLEMENTED | Subject to litigation/public records exceptions |
| Right to Opt-Out of Sale/Share | ⚖️ NOT IMPLEMENTED | "Share" includes cross-context behavioral advertising |
| Right to Correct | ⚖️ NOT IMPLEMENTED | 45-day response window |
| Right to Limit Sensitive Data | ⚖️ NOT IMPLEMENTED | Tier 3-4 data likely qualifies |
| Opt-Out Signal Processing | ⚖️ NOT IMPLEMENTED | GPC signal required for 2024+ |
| Data Protection Impact Assessments | ⚖️ NOT IMPLEMENTED | Required for high-risk processing |
| Annual Risk Assessments | ⚖️ NOT IMPLEMENTED | Required for processing sensitive data |
| Cybersecurity Audit (CPRA) | ⚖️ NOT IMPLEMENTED | Required every 2 years |

### 2.2 Federal Laws

#### FTC Act Section 5 (Unfair/Deceptive Practices)

| Aspect | Detail |
|--------|--------|
| **Applicability** | All Wheeler business activities |
| **Key Requirement** | Privacy claims must match privacy practices; no deceptive data collection/use |
| **Enforcement** | FTC -- civil penalties up to $50,120 per violation per day |
| **Risk Areas** | AI-generated content without disclosure, data use inconsistent with privacy policy, failure to honor opt-out requests |
| **Compliance Action** | ⚖️ Privacy policy audit complete by Q3 2026; AI disclosure review |

#### FCRA (Fair Credit Reporting Act) -- Skip Tracing

| Aspect | Detail |
|--------|--------|
| **Applicability** | ⚖️ CRITICAL ASSESSMENT NEEDED -- If skip tracing data constitutes a "consumer report" used for eligibility determinations |
| **Key Requirements** | Permissible purpose; user certification; adverse action notices; disclosure if consumer report used for denial; annual certifications to CRA |
| **Enforcement** | FTC, CFPB, state AGs, private right of action (statutory damages $100-$1,000 per violation, punitive, attorneys' fees) |
| **Risk Areas** | Using skip tracing data for attorney matching eligibility; using data without permissible purpose; failing to provide adverse action notice |
| **Compliance Action** | ⚖️ Formal FCRA applicability analysis by Q3 2026; if applicable, implement FCRA compliance program |

#### GLBA (Gramm-Leach-Bliley Act) -- Financial Data

| Aspect | Detail |
|--------|--------|
| **Applicability** | ⚖️ ASSESS -- If Wheeler is "significantly engaged" in financial activities (disbursement services, payment processing) |
| **Key Requirements** | Privacy notice (annual); opt-out for sharing with non-affiliates; Safeguards Rule (information security program); data disposal rule |
| **Enforcement** | FTC, federal banking agencies, state AGs, private right of action in some states |
| **Risk Areas** | Collecting bank account details for disbursement; payment processing operations |
| **Compliance Action** | ⚖️ GLBA applicability determination; if applicable, implement Safeguards Rule compliance program |

#### HIPAA (Health Insurance Portability and Accountability Act)

| Aspect | Detail |
|--------|--------|
| **Applicability** | **LOW** -- Wheeler does not currently process health data; ⚖️ CONFIRM no health-related data in court records or claimant data |
| **Contingency** | If Wheeler collects any health-related data (medical records in case files, health information from claimants), HIPAA compliance required |
| **Compliance Action** | Monitor data sources for any health information; document exclusion |

#### CAN-SPAM Act -- Email Marketing

| Aspect | Detail |
|--------|--------|
| **Applicability** | All commercial email sent by Wheeler |
| **Key Requirements** | Accurate from/subject lines; clear identification as advertisement; physical postal address; opt-out mechanism (honor within 10 business days); no opt-out fees |
| **Enforcement** | FTC, DOJ, state AGs, ISPs -- civil penalties up to $51,744 per violation |
| **Risk Areas** | Attorney outreach emails without opt-out; claimant communications without postal address |
| **Compliance Action** | Email template review; opt-out mechanism testing; consent records audit |

#### TCPA (Telephone Consumer Protection Act) -- Phone/SMS Outreach

| Aspect | Detail |
|--------|--------|
| **Applicability** | All phone calls and text messages to consumers |
| **Key Requirements** | Prior express written consent for autodialed/robocalls and SMS; do-not-call list compliance; time-of-day restrictions (8am-9pm); identification requirements; opt-out mechanism |
| **Enforcement** | FCC, FTC, state AGs, **private right of action** ($500-$1,500 per violation, strict liability) |
| **Risk Areas** | Autodialed outreach to claimants without consent; SMS outreach without opt-out; calling numbers on DNC list |
| **Compliance Action** | ⚖️ CRITICAL: TCPA compliance audit by Q3 2026; consent documentation review; DNC list scrubbing procedure; call/SMS vendor compliance verification |

#### ECPA / Stored Communications Act

| Aspect | Detail |
|--------|--------|
| **Applicability** | Email and electronic communications stored by Wheeler systems |
| **Key Requirements** | Prohibits unauthorized access to stored electronic communications; limits provider disclosure of communications |
| **Risk Areas** | Employee access to claimant communications; law enforcement requests for stored communications |
| **Compliance Action** | Access control policies for communication data; law enforcement response procedure (warrant required for content <180 days) |

### 2.3 Sector-Specific Laws

#### State Data Breach Notification Laws

| Category | Detail |
|----------|--------|
| **Applicability** | All 50 states + DC + Puerto Rico + US Virgin Islands + Guam + Northern Mariana Islands |
| **Trigger** | Unauthorized acquisition of personal information (definition varies by state) |
| **Timeline** | "Without unreasonable delay" (most states); specific deadlines: 30 days (FL, CO, OH, others); 45 days (CA); 60 days (NY, WA, others) |
| **Content Requirements** | Vary by state -- generally: nature of breach, data involved, steps to protect data, contact information, credit monitoring offer (some states) |
| **Enforcement** | State AGs, private right of action (some states including CA, MD, MN, NY) |
| **Multi-State Breach** | Must comply with ALL applicable state laws; AG notification for 500+ residents (most states) |
| **Compliance Action** | ⚖️ Develop multi-state breach notification template library; maintain state-specific requirements matrix |

#### State Biometric Information Privacy Laws

| State | Law | Status |
|-------|-----|--------|
| Illinois | BIPA (740 ILCS 14) | **STRICT** -- Private right of action; $1,000 negligent/$5,000 intentional per violation; notice + consent required; retention schedule |
| Texas | BOLA (Bus. & Com. Code §503.001) | Notice + consent + retention/disposal; enforcement by AG |
| Washington | RCW 19.375 | Notice + consent + data protection; enforcement by AG |
| **Applicability** | ⚖️ ASSESS -- Wheeler does not currently collect biometric data; confirm no biometric systems in use (voice recording? facial recognition?) |
| **Compliance Action** | Document no biometric data collection; if voice recordings in outreach, assess BIPA applicability |

#### State Social Security Number Protection Laws

| States | Requirements |
|--------|--------------|
| CA, CT, IL, MI, MN, NM, NY, OR, TX, VA, WA, WI + others | Prohibit public posting of SSNs; restrict transmission of SSNs over internet without encryption; limit SSN collection; require redaction of SSNs in public records; establish SSN confidentiality procedures |
| **Applicability** | **HIGH** -- Wheeler processes claimant SSNs in specific cases |
| **Compliance Action** | SSN collection minimization policy; SSN encryption requirement (column-level); SSN handling procedure; ⚖️ ATTORNEY REVIEW REQUIRED for state-specific SSN requirements |

#### State Data Disposal Laws

| States | Requirements |
|--------|--------------|
| CA (SB 1386), TX, NY, WA, OR, AZ, NC, RI + 30+ others | Require proper disposal of records containing personal information: shredding, erasure, or destruction such that data is unreadable |
| **Applicability** | All Wheeler disposal activities |
| **Compliance Action** | Implement data disposal policy (see Section 4.2); vendor disposal requirements; disposal certification procedure |

#### FTC Safeguards Rule

| Aspect | Detail |
|--------|--------|
| **Applicability** | Applicable if Wheeler is a "financial institution" under GLBA ⚖️ ASSESS |
| **Key Requirements** | Written information security program; designated CISO; risk assessment; incident response plan; annual reporting to board; vendor oversight; periodic penetration testing and vulnerability scanning |
| **Compliance Action** | ⚖️ Determine applicability; if applicable, gap analysis and implementation plan (target: Q4 2026) |

### 2.4 International Laws (Contingent)

| Regulation | Trigger | Status |
|-----------|---------|--------|
| GDPR (EU) | Processing data of EU data subjects -- possible if Hetzner Germany node stores data | ⚖️ ASSESS |
| UK GDPR | Processing data of UK data subjects | Contingent on UK operations |
| LGPD (Brazil) | Processing data of Brazilian data subjects | Contingent on Brazil operations |
| PIPEDA (Canada) | Processing data of Canadian data subjects for commercial activity | Contingent on Canada operations |
| **Compliance Action** | ⚖️ Data residency audit; determine if any EU/UK/other international resident data is processed |

---

## 3. PRIVACY PROGRAM FRAMEWORK

### 3.1 Privacy Principles (OECD/FIPPS-Based)

```
┌────────────────────────────────────────────────────────────────────┐
│                  WHEELER PRIVACY PRINCIPLES                         │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  1. NOTICE / AWARENESS                                             │
│     ┌─ Privacy Policy (public)                                     │
│     ├─ Just-in-Time Notices (at collection points)                 │
│     ├─ Layered Notices (summary + full)                            │
│     └─ AI Processing Disclosures                                   │
│                                                                    │
│  2. CHOICE / CONSENT                                               │
│     ┌─ Opt-In: Tier 4-5 data, sensitive uses, marketing            │
│     ├─ Opt-Out: Data sale/share, profiling                         │
│     ├─ Consent Management Platform (CMP)                           │
│     └─ Consent Records (who, what, when, how)                      │
│                                                                    │
│  3. ACCESS / PARTICIPATION                                         │
│     ┌─ Data Subject Access Request (DSAR) Procedure                │
│     ├─ Data Portability (JSON, CSV)                                │
│     └─ Correction Requests                                         │
│                                                                    │
│  4. INTEGRITY / SECURITY                                           │
│     ┌─ Data Accuracy (reasonable steps)                            │
│     ├─ Security Safeguards (administrative, technical, physical)   │
│     ├─ Data Minimization (collect only what's needed)              │
│     └─ Purpose Limitation (use only for stated purpose)            │
│                                                                    │
│  5. ENFORCEMENT / REDRESS                                          │
│     ┌─ Complaint Handling Procedure                                │
│     ├─ Dispute Resolution Mechanism                                │
│     ├─ Regulatory Cooperation                                      │
│     └─ Internal Accountability                                     │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 3.2 Privacy Policy Requirements

#### Current State Audit

| Item | Status | Priority |
|------|--------|----------|
| Public-facing privacy policy exists | &#x274C; NOT FOUND | P0 |
| CCPA-compliant notice at collection | &#x274C; NOT IMPLEMENTED | P0 |
| State-specific disclosures | &#x274C; NOT IMPLEMENTED | P1 |
| Cookie policy (if web-facing) | &#x274C; NOT FOUND | P1 |
| AI-specific disclosures (automated decision-making) | &#x274C; NOT IMPLEMENTED | P1 |
| Data processing disclosures for claimants | &#x274C; NOT IMPLEMENTED | P0 |
| Attorney data processing disclosures | &#x274C; NOT IMPLEMENTED | P1 |
| Consent records for marketing TCPA/CAN-SPAM | &#x274C; NOT FOUND | P0 |
| Privacy policy versioning and change history | &#x274C; NOT IMPLEMENTED | P2 |

#### CCPA/CPRA-Compliant Privacy Policy Template Sections

A compliant privacy policy must include all of the following sections:

1. **Introduction**: Who Wheeler is, what this policy covers, effective date
2. **Information We Collect**: Categories of personal information collected (use CCPA categories: identifiers, customer records, protected class, commercial information, biometric, internet/electronic activity, geolocation, sensory data, employment, education, inferences)
3. **Sources of Personal Information**: Direct collection, court records, public databases, data brokers, attorneys, service providers
4. **Purposes for Collection**: Legal representation, fund disbursement, attorney matching, AI model development, marketing (if applicable)
5. **Business Purposes for Sharing**: Auditing, security, debugging, internal research, servicing accounts
6. **Sale or Share of Personal Information**: Disclosure of whether Wheeler sells or shares personal information (CCPA "share" includes cross-context behavioral advertising)
7. **Sensitive Personal Information**: Categories collected and purposes
8. **Data Retention**: General retention criteria
9. **Your Rights**:
   - Right to Know (categories and specific pieces)
   - Right to Delete
   - Right to Opt-Out of Sale/Share
   - Right to Correct
   - Right to Limit Use of Sensitive Personal Information
   - Right to Non-Discrimination
10. **How to Exercise Your Rights**: DSAR submission methods (web form, email, toll-free number)
11. **Verification Process**: How identity is verified for access/deletion requests
12. **Authorized Agent**: Process for authorized agent requests
13. **Opt-Out Signal**: Recognition of GPC (Global Privacy Control) or similar signals
14. **Third-Party Data Sharing**: Categories of third parties data is shared with
15. **Data Security**: General security measures
16. **Children's Privacy**: If no data from under 16 collected, affirmatively state so
17. **Changes to Policy**: How changes will be communicated
18. **Contact Information**: DPO/Privacy contact, methods of contact
19. **Effective Date**: Last updated date

#### State-Specific Disclosures Required

| State | Additional Disclosure Requirement |
|-------|----------------------------------|
| California | Right to Limit sensitive data; "Shine the Light" (SB 27); Financial incentive notice |
| Colorado | Profiling opt-out; universal opt-out mechanism notice; data protection assessment availability |
| Connecticut | Profiling opt-out |
| Virginia | None beyond VCDPA requirements |
| Oregon | Right to obtain list of specific third parties data shared with |
| Texas | None beyond TDPSA requirements |
| All | State-specific DSAR contact if required |

#### AI-Specific Disclosures

| Requirement | Guidance |
|-------------|----------|
| Automated Decision-Making | Disclose if AI/automated systems make decisions that produce legal or similarly significant effects (case scoring, attorney matching) |
| Opt-Out of Profiling | Colorado, Connecticut, Oregon require opt-out for profiling in furtherance of decisions producing legal or similarly significant effects |
| Explainability | Provide meaningful information about the logic, significance, and consequences of automated decision-making |
| Human Review | Offer human review option for automated decisions (recommended) |
| Training Data | If personal data used for AI training, disclose categories of data and purposes |
| ⚖️ ATTORNEY REVIEW REQUIRED | AI disclosure language and applicability of profiling regulations |

### 3.3 Data Subject Rights Procedure

#### DSAR Workflow

```
┌────────────┐     ┌────────────┐     ┌────────────┐     ┌────────────┐     ┌────────────┐
│  INTAKE    │────►│ VERIFY     │────►│  SEARCH    │────►│  REVIEW    │────►│  RESPOND   │
│  (Day 0)   │     │  (Day 1-3) │     │  (Day 4-20)│     │  (Day 21-35)│     │  (Day 36-45)│
└────────────┘     └────────────┘     └────────────┘     └────────────┘     └────────────┘
```

| Phase | Description | Owner | Max Duration |
|-------|-------------|-------|--------------|
| **INTAKE** | Receive DSAR via web form, email, phone, or mail; acknowledge receipt; log in DSAR tracking system; assign unique reference number | Privacy Team | 1 business day |
| **VERIFY** | Verify identity of requestor: match against at least 2 data points (name, email, phone, case number); if insufficient, request additional information | Privacy Team | 3 business days (can extend by up to 30 days if identity verification fails) |
| **SEARCH** | Search all systems for data belonging to requestor: PostgreSQL databases (frgops, shared-postgres, Neo4j, ClickHouse), application databases, logs, document stores, third-party systems (Stripe -- via API) | Engineering + Privacy | 15-20 business days |
| **REVIEW** | Review search results for: applicability (is this the requestor's data?), exceptions (litigation hold, public records exception, attorney-client privilege), redactions (third-party data mixed with requestor data) | Privacy Team + ⚖️ Attorney | 15 business days |
| **RESPOND** | Prepare response (report of categories, specific pieces of data, or deletion confirmation); deliver via secure portal or encrypted email; close DSAR with documentation | Privacy Team | 45 days total (CCPA) |

#### DSAR Response Timeline by State

| Right | Jurisdiction | Response Deadline | Extension |
|-------|-------------|------------------|-----------|
| Right to Know | CCPA (CA) | 45 days | +45 days (with notice) |
| Right to Know | VCDPA (VA), CPA (CO), CTDPA (CT), UCPA (UT) | 45 days | +45 days (reasonable) |
| Right to Delete | CCPA | 45 days | +45 days |
| Right to Delete | VCDPA, CPA, CTDPA, UCPA | 45 days | +45 days |
| Right to Correct | CCPA, VCDPA, CPA, CTDPA | 45 days | +45 days |
| Right to Opt-Out | All | 15 business days (CCPA immediately) | None |

#### Exceptions and Exemptions

| Exemption | Applicability | Notes |
|-----------|--------------|-------|
| Public Records Exception | Court records, foreclosure filings | CCPA does not restrict government records that are publicly available |
| Litigation Hold | Active legal matters | Do not delete data subject to litigation hold |
| Attorney-Client Privilege | Attorney communications, privileged documents | Do not disclose privileged communications |
| Compliance with Legal Obligation | Data retention required by law | Retain as required by applicable law |
| Internal Research | De-identified research data | May not apply if data can be re-identified |
| Security/ Fraud Prevention | Data used to prevent fraud | May retain if deletion would impair security |
| ⚖️ ATTORNEY REVIEW REQUIRED | All exemptions applied | Document legal basis for each exception claimed |

#### Identity Verification Standards

| Data Tier | Verification Standard | Acceptable Verification Methods |
|-----------|----------------------|---------------------------------|
| Tier 0-1 | Minimal verification | Email confirmation sufficient |
| Tier 2 | Moderate verification | Email + knowledge of account details |
| Tier 3 | Standard verification | Email + phone + knowledge of 2+ data points |
| Tier 4-5 | Enhanced verification | Email + phone + government ID + knowledge of specific data points in account |

### 3.4 Consent Management

| Element | Standard | Implementation |
|---------|----------|---------------|
| Consent Record | Who, what, when, how, version | Store in PostgreSQL with timestamp + policy version + method of consent |
| Opt-In (Tier 4-5) | Affirmative, unambiguous action | Checkbox (not pre-checked); recorded action |
| Opt-Out (Sale/Share) | Easy to exercise, no friction | Web form, email, phone; GPC signal processing |
| Opt-Out (Marketing) | Same mechanism as opt-in | Unsubscribe link in ALL commercial emails; STOP reply for SMS |
| Consent Withdrawal | As easy as giving consent | Same method; no penalties |
| Documentation Retention | 5 years post-last-interaction | Immutable consent log |
| ⚖️ ATTORNEY REVIEW REQUIRED | TCPA consent documentation | Written agreement, clear disclosure, recorded call consent if applicable |

### 3.5 Privacy Notice Inventory

| Notice Type | Location | Status | Priority |
|-------------|----------|--------|----------|
| Website Privacy Policy | Public website | &#x274C; NOT CREATED | P0 |
| Data Collection Notice | At data collection points (web forms, intake) | &#x274C; NOT CREATED | P0 |
| Attorney Privacy Notice | Attorney onboarding portal | &#x274C; NOT CREATED | P1 |
| Claimant Privacy Notice | Claimant communications | &#x274C; NOT CREATED | P0 |
| Employee Privacy Notice | Internal systems | &#x274C; NOT CREATED (if applicable) | P2 |
| Cookie/Consent Banner | Public website | &#x274C; NOT CREATED | P1 |
| AI Processing Notice | AI-assisted decision points | &#x274C; NOT CREATED | P1 |
| SMS/Phone Consent Notice | Voice/SMS outreach scripts | &#x274C; NOT CREATED | P0 |
| Vendor Privacy Notice | Vendor onboarding | &#x274C; NOT CREATED | P1 |
| Breach Notification | Incident response | &#x274C; NOT CREATED | P0 |

---

## 4. DATA GOVERNANCE CONTROLS

### 4.1 Data Retention Schedule

| Data Category | Retention Period | Legal Basis | Destruction Method | ⚖️ Review |
|---------------|-----------------|-------------|-------------------|-----------|
| Court records (raw scrape) | Indefinite (public records exception) | Public availability; CCPA 1798.105(d)(1) exception | N/A -- publicly available source data | ⚖️ ATTORNEY REVIEW REQUIRED |
| Court records (enriched/parsed) | Duration of business need + 5 years | Legitimate interest; business operations | Secure deletion (shred + overwrite) | ⚖️ ATTORNEY REVIEW REQUIRED |
| Claimant PII (active representation) | Duration of representation + 5 years | Contract necessity; statute of limitations (fraud, contract: 2-6 yrs typical) + 1yr buffer | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Claimant PII (closed, no representation) | 3 years from last contact | Legitimate interest (potential re-engagement); 3yr CCPA lookback | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| SSN / Financial account numbers | Duration of active need + 60 days | Purpose limitation; data minimization | Cryptographic erasure + secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Attorney data (active) | Duration of marketplace participation + 3 years | Contract necessity; Legitimate interest (performance history) | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Attorney data (former participant) | 3 years post-departure | Legitimate interest (historical performance records) | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Skip tracing data | 90 days post-case-close or per vendor agreement | Purpose limitation | Secure deletion or vendor-managed deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Payment/transaction records | 7 years | IRS revenue recordkeeping (IRC §6001) | Secure deletion after 7-year hold | ⚖️ ATTORNEY REVIEW REQUIRED |
| Bank account details (disbursement) | Until account closed + 60 days | Purpose limitation; contract necessity | Cryptographic erasure + secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Lead data (cold -- no engagement) | 180 days | Legitimate interest (opportunity to engage) | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Lead data (converted to customer) | Per customer retention schedule above | N/A | N/A | ⚖️ ATTORNEY REVIEW REQUIRED |
| CRM communication logs | Duration of relationship + 3 years | Contract necessity; legitimate interest | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Application logs | 90 days (rolling) | Security monitoring; troubleshooting | Log rotation + secure overwrite | ⚖️ ATTORNEY REVIEW REQUIRED |
| Audit logs | 3 years | Compliance; legal obligation | Append-only; secure deletion at end of retention | ⚖️ ATTORNEY REVIEW REQUIRED |
| AI training data (de-identified) | 5 years | Legitimate interest (model improvement) | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| AI training data (with PII) | Duration of business need only | Purpose limitation | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Model inference logs | 90 days | Security monitoring; model debugging | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Legal documents (active matter) | Duration of matter + 10 years | Statute of repose (legal malpractice: 1-6 yrs + buffer); attorney recordkeeping rules | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Legal documents (closed matter) | 10 years from close | Statute of repose; bar recordkeeping rules | Secure deletion with certificate | ⚖️ ATTORNEY REVIEW REQUIRED |
| Marketing consents / opt-outs | Indefinite | Proof of consent; permanent suppression | Never delete consent/opt-out records | ⚖️ ATTORNEY REVIEW REQUIRED |
| Marketing outreach data | 2 years since last engagement | Legitimate interest | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Contracts / agreements | 10 years post-termination | Statute of limitations (written contract: 3-10 yrs) | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Employee/contractor records | Duration of relationship + 7 years | IRS; EEOC; state employment law | Secure deletion | ⚖️ ATTORNEY REVIEW REQUIRED |

#### Retention Override Rules

| Rule | Description |
|------|-------------|
| **Legal Hold Override** | All retention schedules are suspended for data subject to litigation hold, regulatory investigation, or audit hold |
| **DSAR Override** | Data scheduled for deletion must be retained if a pending DSAR or dispute exists |
| **Minimum Retention** | No data should be retained for less than 30 days (except temporary/cache data) |
| **Auto-Deletion** | Scheduled deletion must be automated where possible; manual deletion requires documented approval |

### 4.2 Data Deletion Policy

#### Hard Delete vs. Soft Delete Standards

| Delete Type | Definition | When Used | Verification |
|-------------|-----------|-----------|-------------|
| **Soft Delete** | Record marked as deleted in database (is_deleted flag); data remains recoverable for defined period | User-initiated deletes; accidental deletes; DSAR deletes with rollback window (30 days) | Verify flag set; data still present but excluded from queries |
| **Hard Delete** | Data permanently removed from database; overwritten; no recovery possible | After soft-delete retention period expires; data subject deletion requests (post-rollback); retention schedule expiry | Query confirms data unrecoverable; verify backup also deleted (after backup retention) |
| **Cryptographic Erasure** | Encryption key destroyed; ciphertext becomes permanently unreadable | Tier 4-5 data; cloud storage where physical deletion is impossible | Verify key destruction certificate; key access audit confirms keys deleted |
| **Physical Destruction** | Media physically destroyed (shred, degauss, incinerate) | Decommissioned hardware; damaged media; offsite backup tapes | Chain of custody + destruction certificate |

#### Deletion Verification Procedure

1. **Pre-Deletion Audit**: Generate inventory of records matching deletion criteria
2. **Approval**: Privacy Team Lead approves deletion batch (exception: automated DSAR deletes)
3. **Execution**: Perform deletion per Hard/Soft/Crypto standard
4. **Verification Query**: Run confirmatory query (expect 0 matching records)
5. **Backup Deletion**: Remove from active backups (after backup retention period)
6. **Certificate Generation**: Generate Deletion Certificate (see template below)
7. **Third-Party Verification**: If data shared with vendors, obtain vendor deletion confirmation
8. **Documentation**: File Deletion Certificate in deletion log

#### Deletion Certificate Template

```
╔═══════════════════════════════════════════════════════════════╗
║              DATA DELETION CERTIFICATE                        ║
║              Wheeler Ecosystem                                ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║ Reference No:   WHEELER-DEL-{YYYY}-{NNNN}                     ║
║ Requestor:      {DSAR Ref / Retention Schedule / Other}       ║
║ Data Type:      {Description of data deleted}                 ║
║ Records Count:  {NNN records deleted}                         ║
║ Systems:        {Database tables / file paths / systems}      ║
║ Deletion Type:  {Hard Delete / Crypto Erase / Physical}       ║
║ Executed By:    {Operator Name / Agent ID}                    ║
║ Witnessed By:   {Second Party}                                ║
║ Execution Date: {YYYY-MM-DD HH:MM TZ}                         ║
║ Verification:   {Query / confirmation result}                 ║
║ Third-Party:    {If applicable: vendor, deletion confirmed}   ║
║ Notes:          {Any exceptions, issues, or notes}            ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

Signatures:
Executor: ___________________    Date: ____________
Witness:  ___________________    Date: ____________
```

#### Backup Deletion Considerations

| Backup Type | Retention | Deletion Strategy |
|-------------|-----------|-------------------|
| Daily snapshots (PostgreSQL) | 7 days rolling | Automatically overwritten; no action needed for DSAR deletes (data may persist up to 7 days) |
| Weekly snapshots (PostgreSQL) | 4 weeks rolling | Automatically overwritten; communicate 28-day persist window to data subjects |
| Monthly snapshots (PostgreSQL) | 12 months rolling | Automatically overwritten; data may persist up to 12 months |
| Log backups (ClickHouse) | 30 days | Rolling deletion; no separate action needed |
| Offline backups | Per retention policy | Manual deletion on schedule; track in deletion certificate |

### 4.3 Access Control Matrix

#### Role-Based Access Control (RBAC) Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ACCESS CONTROL MATRIX                                 │
├───────────────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬────────────┤
│ Role / System │Case  │CRM   │Atty  │Skip  │ AI   │Logs  │Fin   │Documents  │
│               │Data  │Data  │Data  │Trace │Train │      │Data  │           │
├───────────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼────────────┤
│ Caseworker    │  R/W │  R/W │  R   │  R   │  --  │  --  │  R*  │  R/W*     │
│ Attorney      │  R*  │  R*  │ R/W* │  --  │  --  │  --  │  R*  │  R/W*     │
│ Supervisor    │  R/W │  R/W │  R/W │  R   │  --  │  --  │  R   │  R/W      │
│ Ops/DevOps    │  --  │  --  │  --  │  --  │  --  │  R/W │  --  │  --       │
│ Data/AI Eng   │  R*  │  R*  │  R*  │  R*  │  R/W │  R   │  --  │  R*       │
│ Privacy Team  │  R   │  R   │  R   │  R   │  R   │  R   │  R   │  R        │
│ Finance       │  R*  │  R   │  --  │  --  │  --  │  --  │  R/W │  R        │
│ Compliance    │  R   │  R   │  R   │  R   │  R   │  R   │  R   │  R        │
│ Admin/Super   │  ALL │  ALL │  ALL │  ALL │  ALL │  ALL │  ALL │  ALL      │
│                     │(PAM / Break-Glass Only)                               │
├───────────────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴────────────┤
│ R  = Read              R/W  = Read + Write       --  = No Access            │
│ R* = Scoped (case-scoped, own profile, etc.)                                │
│ ALL = Full access (requires PAM elevation with approval)                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Principle of Least Privilege (POLP) Rules

| Rule | Description |
|------|-------------|
| **Need-to-Know** | Access granted only to data necessary for job function |
| **Time-Bound** | Temporary access grants have automatic expiry (max 7 days) |
| **Location-Bound** | Access from authorized network locations only (Tailscale VPN + 127.0.0.1 binds) |
| **Device-Bound** | Access from authorized/managed devices only (planned) |
| **Audit-All** | All access events logged; all privileged access logged and reviewed |
| **Default-Deny** | No access by default; explicit grant required |
| **Review Cadence** | Quarterly access review for all roles |

#### Access Review Cadence

| Review Type | Frequency | Scope | Owner |
|-------------|-----------|-------|-------|
| User Access Review | Quarterly | All human users; role assignments; active vs. terminated | HR + IT |
| Service Account Review | Quarterly | All automated accounts; API keys; token ages | Engineering |
| Privileged Access Review | Monthly | Admin/superuser role assignments; PAM usage | Security |
| Vendor Access Review | Semi-Annual | Vendor accounts; third-party API access; DPA status | Procurement |
| De-provisioning Audit | Monthly | Terminated users; expired contractors; unused accounts | IT |

#### Privileged Access Management (PAM)

| Requirement | Standard |
|-------------|----------|
| **Just-In-Time Access** | Privileged access granted only for specific task duration; auto-revoked |
| **Approval Workflow** | Admin/superuser access requires manager + security approval |
| **Session Recording** | All privileged sessions logged and recorded (planned: audit logging) |
| **Credential Vaulting** | Privileged credentials stored in secrets manager (not shared) |
| **Multi-Factor Authentication (MFA)** | Required for ALL privileged access |
| **Emergency Override** | Break-glass procedure (see below) |

#### Break-Glass Emergency Access Procedure

```
┌─────────────────────────────────────────────────────────────────┐
│                  BREAK-GLASS ACCESS PROCEDURE                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  TRIGGER: Production outage, security incident,                  │
│           data loss event, or other emergency requiring           │
│           immediate elevated access                              │
│                                                                   │
│  STEP 1:  Notify Security Team + Manager on Call                 │
│           (verbal notification acceptable in active outage)      │
│                                                                   │
│  STEP 2:  Access break-glass account via PAM system              │
│           (credential is sealed; breaking seal generates alert)  │
│                                                                   │
│  STEP 3:  Perform emergency actions                              │
│                                                                   │
│  STEP 4:  Within 1 hour of incident stabilization:               │
│           a) Submit written justification for break-glass use    │
│           b) Change break-glass credentials (re-seal)            │
│           c) Begin incident post-mortem                          │
│                                                                   │
│  STEP 5:  Within 24 hours:                                       │
│           a) Security team reviews session logs                  │
│           b) Determine if any data was accessed inappropriately  │
│           c) Update break-glass procedure based on lessons       │
│                                                                   │
│  ALERTS TRIGGERED:                                               │
│   ├─ Slack/Discord #security-alerts: break-glass access granted   │
│   ├─ Email to Security Lead + CTO: break-glass justification req │
│   └─ Audit log entry (immutable): timestamp, user, actions       │
│                                                                   │
│  ACCESS AUTO-REVOKED: 4 hours max (unless re-approved)           │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 4.4 Encryption Standards

| Data State | Algorithm | Standard | Implementation Status |
|------------|-----------|----------|-----------------------|
| **At Rest (Disk)** | AES-256 | XTS-AES-256 (Linux LUKS/dm-crypt) | IMPLEMENTED -- Hetzner + Hostinger |
| **At Rest (Database)** | AES-256 | Postgres TDE (pg_tde or disk-level) | DISK-LEVEL ONLY -- column-level encryption planned for Tier 4 fields |
| **At Rest (Backups)** | AES-256 | GPG symmetric or cloud KMS | IMPLEMENTED -- pg_dump encrypted |
| **In Transit (External)** | TLS 1.3 | HTTPS / HSTS | TARGET -- verify all external endpoints enforce TLS 1.3 |
| **In Transit (Internal)** | TLS 1.3 | mTLS (mutual TLS) for inter-service | NOT IMPLEMENTED -- internal traffic on 127.0.0.1 (network-layer segmented) |
| **In Transit (Database)** | TLS 1.3 | Postgres SSL/TLS | ⚠️ PARTIAL -- verify replication TLS |
| **Column-Level (Tier 4)** | AES-256-GCM | pgcrypto / cloud KMS envelope encryption | NOT IMPLEMENTED -- P0 for SSN/financial data |
| **Backup Encryption** | AES-256 | GPG symmetric key | IMPLEMENTED |
| **Key at Rest (KEK)** | AES-256 | Cloud KMS or HSM | NOT IMPLEMENTED -- keys on filesystem ⚖️ ATTORNEY REVIEW REQUIRED |

#### Key Management

| Requirement | Standard | Target Date |
|-------------|----------|-------------|
| Key hierarchy (KEK -> DEK) | Envelope encryption with separate KEK | Q4 2026 |
| Key rotation schedule | DEK: annually; KEK: every 3 years | Q4 2026 |
| Key access logging | All key access logged | Q4 2026 |
| HSM or cloud KMS | AWS KMS / Azure Key Vault / HashiCorp Vault | Q4 2026 |
| Key escrow | Disaster recovery key escrow in tamper-evident packaging | Q4 2026 |
| Key destruction | Cryptographic erasure procedure | Q4 2026 |

### 4.5 Audit Logging

#### Logged Events

| Event Category | Events Logged | Retention | Mandatory |
|----------------|--------------|-----------|-----------|
| **Access** | All access to Tier 3-5 data; failed authentication; privilege escalation; role/permission changes | 3 years | YES |
| **Modification** | Create, update, delete of any Tier 3-5 record; schema changes; configuration changes | 3 years | YES |
| **Deletion** | All hard/soft deletes; bulk delete operations; drop table/truncate | 3 years | YES |
| **Export** | Data exports, bulk downloads, API calls returning >100 records, report generation | 3 years | YES |
| **Permission Changes** | Role assignment/revocation; ACL modifications; new user creation; user termination | 3 years | YES |
| **Authentication** | Login success/failure; MFA events; password changes; session creation/expiry | 1 year | YES |
| **Privileged Operations** | Break-glass access; admin actions; system-level changes; root/sudo usage | 3 years | YES |

#### Log Specifications

| Attribute | Standard |
|-----------|----------|
| **Format** | JSON structured logging with schema version |
| **Minimum Fields** | timestamp, event_type, user_id, session_id, source_ip, action, resource, status (success/failure), details |
| **Time Synchronization** | All servers NTP-synchronized; UTC timestamps |
| **Immutability** | Append-only log system; WORM-compliant storage; no modification or deletion of logs |
| **Centralization** | All logs shipped to centralized log aggregator (ClickHouse + Loki) |
| **Integrity Checking** | SHA-256 hash chain or equivalent tamper detection |
| **Alerting** | Automated alerting on anomalous access patterns (see Section 4.5.3) |

#### Audit Log Alerting Rules

| Alert Rule | Trigger | Severity | Response |
|------------|---------|----------|----------|
| Bulk Access Anomaly | Single user accesses >100 Tier 3-5 records in 5 minutes | HIGH | Investigate within 1 hour |
| After-Hours Access | Tier 3-5 access outside business hours (8pm-6am local) without prior approval | MEDIUM | Review within 24 hours |
| Failed Authentication Spike | >10 failed auth attempts in 5 minutes for same user/IP | HIGH | Lock account; investigate |
| Privilege Escalation | Any role change to admin/superuser role | CRITICAL | Immediate investigation |
| Data Export Alert | Any data export of Tier 3-5 data | MEDIUM | Log export reason; periodic review |
| Deletion Anomaly | Bulk delete of >10 records outside scheduled deletion | CRITICAL | Investigate within 1 hour |
| New User Creation | Any new user account creation | MEDIUM | Verify within 24 hours |
| De-activated User Activity | Activity from de-provisioned/suspended account | CRITICAL | Immediate investigation |

#### Audit Log Review Cadence

| Review Type | Frequency | Scope | Owner |
|-------------|-----------|-------|-------|
| Automated Alert Triage | Continuous | All alerts triggered | Security Team (on-call) |
| Weekly Summary Review | Weekly | All alert events from past week; false positive review | Privacy Team |
| Monthly Audit Report | Monthly | Access patterns; privilege changes; export activity; deletion activity | Privacy + Security |
| Quarterly Deep Dive | Quarterly | Full audit log analysis; pattern identification; control effectiveness | Internal Audit / External Auditor |
| Annual Penetration Test | Annual | Audit log completeness; tamper resistance; coverage gaps | External Pen Test Firm |

---

## 5. VENDOR / THIRD-PARTY DATA GOVERNANCE

### 5.1 Vendor Risk Tiering

| Tier | Classification | Data Access | Examples | Assessment Requirements |
|------|---------------|-------------|----------|------------------------|
| Tier 1 (Critical) | HIGH RISK | Access to Tier 3-5 data | Skip tracing providers, Stripe, SMS gateways, email delivery, AI API providers, data brokers | SOC 2 Type II + DPA + PIA + Security Questionnaire + Subprocessor List + Annual Re-Assessment |
| Tier 2 (Significant) | MEDIUM RISK | Access to Tier 2 data, or indirect access to Tier 3+ | CRM vendors, analytics tools, cloud hosting (Hetzner/Hostinger), Neo4j/ClickHouse vendors, monitoring tools | DPA + Security Questionnaire + Annual Re-Assessment |
| Tier 3 (Standard) | LOW RISK | Access to Tier 0-1 data only, or no data access | Office productivity tools, communication platforms (Slack/Discord -- business communications), marketing analytics (aggregate only) | Standard terms + Data Processing Agreement if applicable |

### 5.2 Vendor Assessment Requirements

#### Tier 1 (Critical) Vendor Assessment Checklist

| Requirement | Details | Frequency |
|-------------|---------|-----------|
| SOC 2 Type II Report | Review for relevant trust services criteria (Security, Confidentiality, Availability, Privacy) | Annual |
| Data Processing Agreement (DPA) | Signed DPA with CCPA/CPRA addendum and state-specific addenda | Initial + material change |
| Privacy Impact Assessment (PIA) | Assess data categories, processing purposes, risks, mitigations | Initial + material change |
| Subprocessor Disclosure | Complete list of all subprocessors with notice and consent rights | Initial + annual update |
| Cross-Border Transfer Assessment | Identify data residency; assess transfer mechanisms (SCCs, DPF) | Initial + law change |
| Security Questionnaire | SIG Lite or equivalent (50+ questions covering security, access, encryption, incident response) | Initial + biennial |
| Vendor Penetration Test Report | Review of vendor's latest penetration test results (if available) | Annual |
| Business Continuity / DR Review | Vendor's BCP/DR plan and actual test results | Initial + biennial |
| Insurance Certificate | Cyber liability insurance ($5M+ recommended) | Annual |
| Right to Audit Clause | Contractual right to audit vendor's relevant controls (or SOC 2 as alternative) | Contract negotiation |
| Deletion Confirmation | Procedure for vendor to delete Wheeler data upon termination | Initial + on termination |

#### Tier 2 (Significant) Vendor Assessment Checklist

| Requirement | Details | Frequency |
|-------------|---------|-----------|
| DPA | Signed DPA with applicable state addenda | Initial |
| Security Questionnaire | SIG Lite or 25+ relevant questions | Initial + biennial |
| SOC 2 Type II Report | Request; not required vendor selection criterion | Initial |
| Business Continuity | Confirm BCP exists | Initial |

#### Tier 3 (Standard) Vendor Assessment

| Requirement | Details |
|-------------|---------|
| Standard Terms of Service | Review for data handling clauses |
| DPA | Signed if vendor processes any Wheeler data |

### 5.3 Vendor Inventory

| Vendor | Service | Data Accessed | Risk Tier | DPA Status | SOC 2 | Last Assessment | Next Assessment |
|--------|---------|---------------|-----------|------------|-------|-----------------|-----------------|
| Stripe | Payment processing | Transaction metadata, last-4 card, bank account (routing + token), PII for identity verification | Tier 1 | ⚖️ REVIEW CURRENT DPA | SOC 2 Type II available | ⚖️ INVENTORY | Q3 2026 |
| Hetzner | Cloud hosting | Infrastructure; may have access to disk-level data if physical access | Tier 3 (see note) | ⚖️ REVIEW | SOC 2 Type II not typical for IaaS | ⚖️ INVENTORY | Q3 2026 |
| Hostinger | Cloud hosting | Infrastructure | Tier 3 | ⚖️ REVIEW | SOC 2 not typical | ⚖️ INVENTORY | Q3 2026 |
| Anthropic (Claude API) | AI model inference | Prompt content (no training on API data per policy); limited to prompts sent | Tier 1 | ⚖️ REQUIRED | SOC 2 Type II available | ⚖️ INVENTORY | Q3 2026 |
| OpenAI (API) | AI model inference | Prompt content (opt-out of training by default for API); limited to prompts sent | Tier 1 | ⚖️ REQUIRED | SOC 2 Type II available | ⚖️ INVENTORY | Q3 2026 |
| DeepSeek (via LiteLLM) | AI model inference | Prompt content | Tier 1 | ⚖️ REQUIRED | Unknown | ⚖️ INVENTORY | Q3 2026 |
| LiteLLM | AI routing proxy | Prompt content (transient) | Tier 1 | N/A (self-hosted) | N/A | N/A | N/A |
| PostgreSQL (Postgres) | Database engine | All data stored in databases | N/A (self-managed) | N/A | N/A | N/A | N/A |
| Redis | Caching / queue | Transient data; may contain PII | N/A (self-managed) | N/A | N/A | N/A | N/A |
| Neo4j | Graph database | Entity relationship data | N/A (self-managed) | N/A | N/A | N/A | N/A |
| ClickHouse | Analytics database | Aggregated/raw data for analytics | N/A (self-managed) | N/A | N/A | N/A | N/A |
| Docker Inc. | Container runtime | Infrastructure only | Tier 3 | Review ToS | N/A | ⚖️ INVENTORY | Q3 2026 |
| GitHub (if used) | Code repository | Source code (no production data) | Tier 2 | ⚖️ REQUIRED | SOC 2 Type II available | ⚖️ INVENTORY | Q3 2026 |
| Discord / Slack (if used) | Communication | Business communications (no production PII) | Tier 3 | ⚖️ REVIEW ToS | SOC 2 Type II available | ⚖️ INVENTORY | Q3 2026 |
| Skipjack/TLOxp (PLANNED) | Skip tracing / data broker | Consumer data, PII | Tier 1 | ⚖️ REQUIRED (pre-contract) | ⚖️ REQUEST | Pre-contract assessment | Pre-contract |
| Email delivery service (PLANNED) | Email marketing/delivery | Email addresses, communication content, engagement data | Tier 1 | ⚖️ REQUIRED (pre-contract) | ⚖️ REQUEST SOC 2 | Pre-contract assessment | Pre-contract |
| SMS gateway (PLANNED) | SMS outreach | Phone numbers, SMS content, delivery records | Tier 1 | ⚖️ REQUIRED (pre-contract) | ⚖️ REQUEST SOC 2 | Pre-contract assessment | Pre-contract |

### 5.4 Vendor Contract Requirements

All Wheeler vendor contracts must include (at minimum):

| Clause | Required For | Standard Provision |
|--------|-------------|-------------------|
| Data Processing Terms | All vendors processing Wheeler data | Define data categories, processing purposes, duration, nature, and scope |
| Confidentiality | All vendors | Binding confidentiality obligations on vendor and its employees/contractors |
| Security Measures | Tier 1-2 vendors | Minimum security standards (encryption, access controls, incident response) |
| Data Breach Notification | Tier 1-2 vendors | Must notify Wheeler within 24-72 hours of discovering a breach affecting Wheeler data |
| Subprocessor Control | Tier 1 vendors | Right to approve subprocessors; notice of changes; right to terminate if subprocessor not approved |
| Data Deletion / Return | All vendors | Upon termination, vendor must delete or return all Wheeler data with certification |
| Audit Rights | Tier 1 vendors | Right to audit vendor's relevant controls (or SOC 2 as substitute) |
| Indemnification | All vendors | Vendor indemnifies Wheeler for breach of data protection obligations |
| Limitation of Liability | All | Carve-out for data protection breaches from general liability cap |
| Compliance with Laws | All vendors | Vendor must comply with applicable data protection laws |
| Cross-Border Transfer | Tier 1 vendors | Adequate transfer mechanism (SCCs, DPF, etc.) |
| Term and Termination | All | Right to terminate for material data protection breach |
| ⚖️ ATTORNEY REVIEW REQUIRED | All vendor contracts | Legal review of data protection clauses |

---

## 6. INCIDENT RESPONSE

### 6.1 Data Breach Response Plan

#### Incident Classification

| Severity | Definition | Examples | Response Team | Notification Timeline |
|----------|-----------|----------|---------------|---------------------|
| **P0 (Critical)** | Unauthorized access to Tier 4-5 data; confirmed breach of >10,000 individuals | Database compromise with SSNs/financial data; ransomware; insider data theft | Full Incident Response Team (Security, Privacy, Legal, Executive) | Immediate containment; regulator notification within state-specific deadlines |
| **P1 (High)** | Unauthorized access to Tier 2-3 data; suspected breach; >1,000 individuals affected | Exposed API with PII; misconfigured S3 bucket; lost laptop with encrypted data | Security + Privacy + Legal | 24-hour initial assessment; notification per state timeline |
| **P2 (Medium)** | Unauthorized access to Tier 0-1 data; isolated incident; <1,000 individuals | Exposed non-sensitive log data; single account compromise | Security + Privacy | 72-hour assessment; notification if state law requires |
| **P3 (Low)** | Potential exposure, no confirmed access; near-miss | Phishing attempt without compromise; misconfiguration caught internally before exposure | Security Team | Informational; no notification required |

#### Incident Response Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DATA BREACH RESPONSE WORKFLOW                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  DETECTION                                                            │
│  ├─ Automated alert (IDS/IPS, audit log anomaly, EDR)               │
│  ├─ User report (employee, contractor, partner)                     │
│  ├─ External notification (law enforcement, researcher, journalist) │
│  ├─ Vendor notification                                              │
│  └─ Bug bounty / vulnerability disclosure                           │
│         │                                                            │
│         ▼                                                            │
│  TRIAGE (within 1 hour)                                              │
│  ├─ Severity classification (P0-P3)                                 │
│  ├─ Initial containment decision                                    │
│  ├─ Incident commander assigned                                     │
│  └─ Incident number created                                         │
│         │                                                            │
│         ▼                                                            │
│  CONTAINMENT (P0-P1: within 4 hours)                                │
│  ├─ Disconnect affected systems from network                        │
│  ├─ Revoke compromised credentials                                  │
│  ├─ Block malicious IPs / traffic patterns                          │
│  ├─ Isolate affected data stores                                    │
│  ├─ Preserve forensic evidence (snapshot memory, disk images)       │
│  └─ Engage law enforcement if applicable (criminal activity)        │
│         │                                                            │
│         ▼                                                            │
│  INVESTIGATION (P0: 48 hours; P1: 1 week)                           │
│  ├─ Forensic analysis (full disk + memory capture)                  │
│  ├─ Determine data accessed / exfiltrated                           │
│  ├─ Identify affected individuals and data types                   │
│  ├─ Determine root cause                                           │
│  ├─ Identify attacker attribution (if possible)                    │
│  └─ Document chain of custody                                       │
│         │                                                            │
│         ▼                                                            │
│  NOTIFICATION (per state deadlines)                                  │
│  ├─ Identify affected residents by state                            │
│  ├─ Prepare state-specific notification letters                     │
│  ├─ Notify affected individuals                                     │
│  ├─ Notify state AGs / regulators                                   │
│  ├─ Notify credit bureaus (if SSNs affected)                       │
│  ├─ Notify law enforcement (if criminal)                           │
│  ├─ Notify cyber insurance carrier                                 │
│  └─ Offer credit monitoring / identity protection (if required)     │
│         │                                                            │
│         ▼                                                            │
│  REMEDIATION                                                         │
│  ├─ Patch vulnerability / fix root cause                            │
│  ├─ Restore from clean backup                                       │
│  ├─ Change all related secrets / credentials                        │
│  ├─ Reconnect systems with enhanced monitoring                     │
│  ├─ Verify no attacker persistence                                 │
│  └─ Validate remediation effectiveness                             │
│         │                                                            │
│         ▼                                                            │
│  POST-INCIDENT                                                       │
│  ├─ Complete incident report (within 30 days)                      │
│  ├─ Conduct post-mortem / lessons learned session                  │
│  ├─ Update incident response plan                                  │
│  ├─ Update risk register                                           │
│  ├─ Implement preventive controls                                  │
│  ├─ Update training materials                                      │
│  └─ Report to executive team / board (if material)                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Breach Notification Timeline by State

| Timeline | States |
|----------|--------|
| **"Without unreasonable delay"** | Most states (including CA, NY, TX, FL, IL, PA, OH, MI, GA, NC, NJ, VA, WA, AZ, MA, IN, TN, MO, MD, WI, CO, MN, SC, AL, LA, KY, OR, OK, CT, IA, MS, AR, KS, NV, NM, NE, ID, WV, NH, ME, MT, RI, DE, SD, ND, VT, WY, HI, AK) |
| **30 days** | Colorado, Florida, Ohio, Vermont |
| **45 days** | California (AG notification -- after notification to individuals) |
| **60 days** | New York (Department of Financial Services -- DFS-regulated entities) |
| **72 hours** | GDPR (if EU data subjects affected) |
| ⚖️ ATTORNEY REVIEW REQUIRED | Verify all state-specific notification triggers and deadlines |

#### Notification Content Requirements (Common Elements)

| Element | Description | Required In |
|---------|-------------|-------------|
| Description of breach | Nature of the incident, date discovered, date occurred (if known) | Most states |
| Data types involved | Categories of personal information accessed or acquired | All states |
| Steps to protect data | Actions individual should take (credit freeze, fraud alerts, monitoring) | Most states |
| Contact information | Phone number, email, website for inquiries | All states |
| Credit monitoring offer | Most states require 12-24 months free credit monitoring if SSN/financial data breached | CA, NY, TX, FL, MA, MD, CT + others |
| Toll-free number | Must maintain for 60+ days | CA, NY, TX, FL, IL + others |
| Sample notice | Must file copy of notice with state AG | CA, NY, MA, MD + others |
| Timing of notification | Date notice was sent | CA, NY, MD, CO + others |
| Law enforcement delay | Notification delayed if law enforcement determines it would impede investigation | All states |

#### Law Enforcement Engagement Criteria

| Criteria | Action |
|----------|--------|
| Criminal activity confirmed or suspected | Contact FBI, Secret Service, or local cybercrime task force within 24 hours |
| Extortion / ransomware | Contact FBI Cyber Division; preserve evidence; do not pay ransom without FBI consultation |
| Insider threat | Contact law enforcement if criminal charges will be pursued; consult employment attorney for internal actions |
| Unknown attacker | Document and preserve evidence; consult law enforcement before any system restoration that may destroy evidence |
| Child exploitation / terrorism | Immediate law enforcement notification; preserve scene |

#### Forensic Investigation Procedure

| Phase | Action | Tool / Method |
|-------|--------|--------------|
| Preservation | Create forensic images of affected systems (bit-for-bit copies); preserve memory dump | dd, FTK Imager, LiME, Volatility |
| Chain of Custody | Document every person who handles evidence; hash verification at each transfer | SHA-256, chain of custody form |
| Analysis | Identify entry vector; scope of access; data exfiltration; persistence mechanisms | Autopsy, Sleuth Kit, Wireshark, SIEM |
| Timeline Reconstruction | Correlate logs, system events, and user activity to build incident timeline | Splunk, ELK, custom scripting |
| Data Impact Assessment | Identify all records accessed; categorize by tier; determine notification obligations | Database audit logs, file access logs |
| Attribution | Identify attacker (if possible); preserve evidence for prosecution | Threat intelligence, C2 analysis |
| Reporting | Produce forensic report suitable for legal, regulatory, and insurance purposes | Standardized forensic report template |

### 6.2 Breach Register Template

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                         DATA BREACH REGISTER                                 ║
║                         Wheeler Ecosystem                                    ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║ Incident ID:    WHEELER-BR-{YYYY}-{NNNN}                                     ║
║ Severity:       {P0 / P1 / P2 / P3}                                          ║
║ Status:         {Open / Contained / Investigating / Closed}                   ║
║                                                                              ║
║ ┌─────────────────────────────────────────────────────────────────────────┐ ║
║ │ 1. INCIDENT DETAILS                                                      │ ║
║ ├─────────────────────────────────────────────────────────────────────────┤ ║
║ │ Date Discovered:     {YYYY-MM-DD HH:MM TZ}                               │ ║
║ │ Date Occurred:       {YYYY-MM-DD HH:MM TZ or "Unknown"}                  │ ║
║ │ Date Contained:      {YYYY-MM-DD HH:MM TZ}                               │ ║
║ │ Date Closed:         {YYYY-MM-DD HH:MM TZ}                               │ ║
║ │ Discovered By:       {Automated alert / User / External / Vendor}        │ ║
║ │ Incident Type:       {Unauthorized access / Misconfiguration / Lost      │ ║
║ │                       device / Insider threat / Phishing / Ransomware /  │ ║
║ │                       Physical theft / Other (specify)}                  │ ║
║ │ Root Cause:          {Description of how breach occurred}                │ ║
║ │                                                                           │ ║
║ │ 2. DATA AFFECTED                                                          │ ║
║ ├─────────────────────────────────────────────────────────────────────────┤ ║
║ │ Data Categories:     {Tier 0-5; list specific categories}                │ ║
║ │ Data Elements:       {Specific fields: SSN, name, address, etc.}        │ ║
║ │ Records Affected:    {NNN}                                                │ ║
║ │ Individuals Affected: {NNN}                                               │ ║
║ │ Systems Involved:    {Database(s), application(s), file share(s)}         │ ║
║ │ Data Format:         {Structured database / Unstructured files / Logs}    │ ║
║ │                                                                           │ ║
║ │ 3. GEOGRAPHY                                                              │ ║
║ ├─────────────────────────────────────────────────────────────────────────┤ ║
║ │ States of Affected Individuals: {List of states}                          │ ║
║ │ Countries Affected:      {If international}                               │ ║
║ │ Data Stored In:          {Server location / cloud region}                 │ ║
║ │                                                                           │ ║
║ │ 4. NOTIFICATION STATUS                                                    │ ║
║ ├─────────────────────────────────────────────────────────────────────────┤ ║
║ │ Affected Individuals Notified:    {Date / Not required / Pending}         │ ║
║ │ State AGs Notified:               {List states and dates}                 │ ║
║ │ Federal Regulators Notified:      {List regulator and date}               │ ║
║ │ Law Enforcement Notified:         {Agency and date}                       │ ║
║ │ Credit Bureaus Notified:          {Date / Not required}                   │ ║
║ │ Cyber Insurance Notified:         {Date / Not required}                   │ ║
║ │ Media / Public Notice:            {Date / Not required}                   │ ║
║ │                                                                           │ ║
║ │ 5. REMEDIATION                                                            │ ║
║ ├─────────────────────────────────────────────────────────────────────────┤ ║
║ │ Containment Actions:  {What was done to stop the breach}                 │ ║
║ │ Remediation Actions:  {What was done to fix root cause}                  │ ║
║ │ Preventive Controls:  {What was implemented to prevent recurrence}       │ ║
║ │ Credentials Rotated:  {Which credentials were rotated}                   │ ║
║ │                                                                           │ ║
║ │ 6. DOCUMENTATION                                                          │ ║
║ ├─────────────────────────────────────────────────────────────────────────┤ ║
║ │ Forensic Report Ref: {Report ID / location}                               │ ║
║ │ Incident Report Ref: {Report ID / location}                               │ ║
║ │ Post-Mortem Date:    {YYYY-MM-DD}                                         │ ║
║ │ Lessons Learned:     {Key findings and action items}                      │ ║
║ │                                                                           │ ║
║ │ 7. REGULATORY OUTCOME                                                     │ ║
║ ├─────────────────────────────────────────────────────────────────────────┤ ║
║ │ Regulatory Fines:       {Amount or "None"}                                │ ║
║ │ Regulatory Actions:     {Consent order, settlement, monitoring, etc.}     │ ║
║ │ Litigation Filed:       {Y/N -- case reference}                           │ ║
║ │ Insurance Claim Filed:  {Y/N -- outcome}                                  │ ║
║ │                                                                           │ ║
║ └─────────────────────────────────────────────────────────────────────────┘ ║
║                                                                              ║
║ Prepared By: ___________________    Date: ____________                       ║
║ Reviewed By: ___________________    Date: ____________                       ║
║ Approved By: ___________________    Date: ____________                       ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

## 7. COMPLIANCE MONITORING

### 7.1 Privacy Metrics Dashboard

| Metric | Target | Measurement | Frequency | Owner |
|--------|--------|-------------|-----------|-------|
| **DSAR Volume** | Track total + by type (know/delete/opt-out/correct) | Count from DSAR tracking system | Monthly | Privacy Team |
| **DSAR Response Time** | 100% within statutory deadline (45 days) | Average, median, p95, p99 response time in days | Monthly | Privacy Team |
| **DSAR Compliance Rate** | 100% on-time response | On-time / total * 100 | Monthly | Privacy Team |
| **Consent Opt-Out Rate** | Track trend | Opt-outs / total data subjects | Monthly | Privacy + Marketing |
| **Data Deletion Requests** | 100% completed within 45 days | Completed / received * 100 | Monthly | Privacy Team |
| **Access Violations** | 0 critical violations | Count by severity (P0/P1/P2/P3) | Real-time dashboard | Security Team |
| **Vendor Compliance** | 100% Tier 1 vendors assessed annually | Assessed / total * 100 | Quarterly | Procurement |
| **Vendor DPA Status** | 100% executed DPAs for Tier 1-2 | Executed / required * 100 | Quarterly | Procurement |
| **Policy Acknowledgment** | 100% of employees/contractors | Acknowledged / total * 100 | Quarterly | HR + Privacy |
| **Training Completion** | 100% annually | Completed / total * 100 | Quarterly | HR + Privacy |
| **Privacy Impact Assessments** | 100% for qualifying projects | Completed / required * 100 | Quarterly | Privacy Team |
| **Incident Response Time** | P0: <1hr to contain; P1: <4hrs | Time from detection to containment | Per incident | Security Team |
| **Access Reviews Completed** | 100% on schedule | Completed / scheduled * 100 | Quarterly | IT + Security |
| **Encryption Coverage** | 100% Tier 3-5 data encrypted at rest + transit | Encrypted / total * 100 | Quarterly | Engineering |
| **Breach Count** | 0 | Count of confirmed breaches | Real-time | Security Team |
| **Cookie Consent Rate** | Track trend | Accepted / total visits * 100 (if website) | Monthly | Marketing |
| **Third-Party Data Sharing** | Track all instances | Count of active data sharing arrangements | Quarterly | Privacy Team |

### 7.2 Annual Compliance Calendar

#### Q1 (January -- March)

| Activity | Owner | Deliverable |
|----------|-------|-------------|
| Privacy Policy Review and Update | Privacy Team + ⚖️ Attorney | Updated privacy policy; version bump; changelog |
| Vendor Re-Assessment (Annual) | Procurement + Security | Tier 1 vendor SOC 2 reviews; DPA updates; security questionnaire refresh |
| Compliance Horizon Scan (Q1) | Privacy Team | Regulatory developments report; identify new obligations |
| Data Mapping Update | Engineering + Privacy | Update system data map; verify accuracy |
| Consent Management Audit | Privacy + Marketing | Consent records review; opt-out suppression list verification |
| Cyber Insurance Renewal | Risk Management | Application review; coverage adequacy assessment |
| Breach Register Review | Privacy + Security | Review breach register; verify closed incidents |

#### Q2 (April -- June)

| Activity | Owner | Deliverable |
|----------|-------|-------------|
| Access Review (Q2) | IT + Security | User access listing; role assignment audit; de-provisioning confirmation |
| Data Mapping Update (Semi-Annual) | Engineering + Privacy | Data flow verification; new systems added |
| DSAR Process Tabletop | Privacy Team | DSAR workflow walkthrough; identify bottlenecks |
| Cookie/Consent Banner Audit (if applicable) | Marketing + Privacy | Verify GPC signal processing; consent preference audit |
| AI Governance Review | AI Governance + Privacy | Training data audit; model fairness assessment; AI disclosure review |
| State Law Applicability Refresh | ⚖️ Attorney | Re-assess state applicability as new laws become effective |
| Vulnerability Scan (External) | Security | External perimeter scan; public-facing system audit |

#### Q3 (July -- September)

| Activity | Owner | Deliverable |
|----------|-------|-------------|
| Data Breach Tabletop Exercise | Security + Privacy + Executive | Simulated breach scenario; test response plan; debrief report |
| Privacy Training (Annual) | HR + Privacy | All-staff privacy training; role-specific modules for data handlers |
| Data Retention Audit | Engineering + Privacy | Verify auto-deletion schedules; audit manual deletion; retention schedule compliance |
| Penetration Test (Annual) | External Pen Test Firm | Full-scope penetration test; application + infrastructure + API |
| Vendor Re-Assessment (Q3) | Procurement + Security | Tier 1 vendor mid-year check; new vendor assessments |
| Cybersecurity Audit (CPRA) | External Auditor | CPRA-required biennial cybersecurity audit (if applicable) |
| Incident Response Plan Review | Security + Privacy | IR plan update; lessons learned from tabletop; contact list refresh |

#### Q4 (October -- December)

| Activity | Owner | Deliverable |
|----------|-------|-------------|
| Annual Compliance Audit | Internal Audit + External Auditor | Full compliance audit against all applicable laws |
| Risk Assessment Update | Risk Management + Privacy | Enterprise risk register update; new risk identification; control effectiveness assessment |
| Regulatory Horizon Scan (Annual) | ⚖️ Attorney + Privacy | Upcoming state/federal laws for next year; legislative tracker |
| Access Review (Q4) | IT + Security | Full access review; privileged access audit; user certification |
| Data Protection Impact Assessment Review | Privacy Team | Review all PIAs; identify new high-risk processing requiring PIA |
| Annual Report to Executive / Board | DPO / Privacy Team | Annual privacy program report; metrics; incidents; compliance status; budget for next year |
| Policy Review and Update | Privacy Team + ⚖️ Attorney | All privacy policies reviewed; version bump; acknowledgment campaign |
| Training Completion Verification | HR + Privacy | Verify 100% annual training completion; escalate non-completers |
| Budget Planning | DPO + Finance | Next year privacy program budget; tooling; personnel; vendor costs |
| Privacy Program Roadmap (Next Year) | DPO | Strategic priorities; key initiatives; resource plan |

### 7.3 Compliance Reporting Structure

```
┌────────────────────────────────────────────────────────────────────┐
│                  COMPLIANCE REPORTING STRUCTURE                      │
├────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ├── DAILY                                                          │
│  │    ├─ Automated security alerts review                           │
│  │    ├─ DSAR intake check                                          │
│  │    └─ Breach detection monitoring                                │
│  │                                                                   │
│  ├── WEEKLY                                                         │
│  │    ├─ Security alert summary                                     │
│  │    ├─ DSAR status update                                         │
│  │    ├─ Access violation log review                                │
│  │    └─ Privacy metrics snapshot (if automated)                    │
│  │                                                                   │
│  ├── MONTHLY                                                        │
│  │    ├─ Privacy metrics dashboard                                  │
│  │    ├─ DSAR compliance report                                     │
│  │    ├─ Consent/opt-out metrics                                    │
│  │    ├─ Deletion request completions                               │
│  │    ├─ Access review completion status                            │
│  │    ├─ Vendor compliance summary                                  │
│  │    └─ Report to CISO / Privacy Lead                              │
│  │                                                                   │
│  ├── QUARTERLY                                                      │
│  │    ├─ Access review certification                                │
│  │    ├─ Vendor risk assessment update                              │
│  │    ├─ Training completion report                                 │
│  │    ├─ Policy acknowledgment report                               │
│  │    ├─ Data Protection Impact Assessment status                   │
│  │    ├─ Risk register update                                       │
│  │    └─ Report to Architecture Review Board (WARB)                 │
│  │                                                                   │
│  ├── ANNUAL                                                         │
│  │    ├─ Full compliance audit report                               │
│  │    ├─ Privacy program effectiveness evaluation                   │
│  │    ├─ Risk assessment report                                     │
│  │    ├─ Third-party/vendor risk report                             │
│  │    ├─ Incident response test results                             │
│  │    ├─ Penetration test results                                   │
│  │    ├─ Regulatory developments report                             │
│  │    ├─ Budget and resource plan for next year                     │
│  │    └─ Report to Executive / Board of Directors                   │
│  │                                                                   │
│  └── PER-INCIDENT                                                   │
│       ├─ Initial incident notification (real-time)                  │
│       ├─ Incident investigation report (within 30 days)             │
│       └─ Post-incident remediation report (within 60 days)          │
│                                                                      │
└────────────────────────────────────────────────────────────────────┘
```

---

## 8. PRIVACY BY DESIGN

### 8.1 Development Lifecycle Integration

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  PRIVACY-BY-DESIGN DEVELOPMENT LIFECYCLE                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐ │
│  │REQUIRE-  │   │  DESIGN  │   │  DEVELOP │   │  TEST    │   │ DEPLOY   │ │
│  │MENTS     │   │          │   │          │   │          │   │ & OPERATE│ │
│  ├──────────┤   ├──────────┤   ├──────────┤   ├──────────┤   ├──────────┤ │
│  │ □ Privacy│   │ □ PIA    │   │ □ Code   │   │ □ Privacy│   │ □ Privacy│ │
│  │   impact │   │   trigger│   │   review │   │   test   │   │   check  │ │
│  │   check  │   │   assess │   │   (data  │   │   cases  │   │   in CI/ │ │
│  │ □ Data   │   │ □ Privacy│   │   access,│   │ □ Data   │   │   CD     │ │
│  │   minimi-│   │   notice │   │   minimi-│   │   flow   │   │ □ Access │ │
│  │   zation │   │   update │   │   zation │   │   audit  │   │   review │ │
│  │   review │   │   needed?│   │   check  │   │ □ Securi-│   │ □ Env    │ │
│  │ □ Legal │   │ □ Data   │   │ □ Encryp-│   │   ty scan│   │   config │ │
│  │   basis │   │   flow   │   │   tion req│   │ □ Temp-  │   │   audit  │ │
│  │   ident-│   │   diagram│   │ □ Consent│   │   late   │   │ □ Monitor│ │
│  │   ified  │   │ □ Consent│   │   capture│   │   review │   │   config │ │
│  │         │   │   design  │   │   (if    │   │ □ Pene-  │   │ □ Docu-  │ │
│  │         │   │ □ Data    │   │   needed)│   │   tration│   │   ment   │ │
│  │         │   │   flow    │   │ □ Access │   │   test   │   │   update │ │
│  │         │   │   map     │   │   control│   │          │   │          │ │
│  │         │   │   update  │   │   design │   │          │   │          │ │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Privacy Review Gate (Feature Development)

| Gate | Trigger | Review Criteria | Gatekeeper | Outcome |
|------|---------|----------------|------------|---------|
| **G1: Requirements** | All new features or significant changes | Does feature process personal data? What tier? Is there a legal basis? Can data be minimized? | Product Manager + Privacy Team | Pass / Pass with conditions / Fail (redesign) |
| **G2: Design** | Architecture design complete | PIA required? Data flow documented? Consent/notice designed? Default privacy settings? | Privacy Team | Pass / Pass with conditions / Fail (redesign) |
| **G3: Pre-Release** | Before production deployment | Code review includes privacy checks; test cases cover privacy scenarios; access controls implemented; encryption verified | Engineering Lead + Privacy Team | Pass / Block (fix before deploy) |
| **G4: Post-Launch** | 30 days after production deployment | Privacy metrics review; no unexpected data collection; consent/opt-out functioning; access logs clean | Privacy Team | Verify / Remediate / Rollback |

### 8.3 Data Protection Impact Assessment (DPIA) Trigger Criteria

A DPIA is required if the processing activity involves any of the following:

| Trigger | Examples | Assessment Required By |
|---------|----------|-----------------------|
| **Systematic evaluation of individuals** | Automated scoring/ranking of claimants; attorney performance scoring; AI-driven case prioritization | ⚖️ ATTORNEY REVIEW REQUIRED |
| **Large-scale processing of Tier 3-4 data** | Processing >10,000 claimant records; >5,000 Tier 4 records | Privacy Team |
| **Processing of Tier 5 data** | Any FCRA-covered data; biometric data; attorney-client privileged data | Privacy Team + ⚖️ Attorney |
| **Systematic monitoring of publicly accessible areas** | Any monitoring or surveillance of public court systems on large scale | Privacy Team |
| **Profiling/vulnerable data subjects** | Processing data of known vulnerable populations (elderly, financially distressed) | Privacy Team + ⚖️ Attorney |
| **Use of new technologies** | AI/ML training on personal data; novel scraping techniques; automated decision systems | Privacy Team + Engineering |
| **Cross-system data matching** | Combining datasets from different sources that increases privacy risk | Privacy Team |
| **Data sharing with new third parties** | New vendor data sharing arrangements | Procurement + Privacy |
| **Cross-border data transfer** | Transfer of data to jurisdictions with different privacy frameworks | ⚖️ Attorney + Privacy |
| **Changes to privacy controls** | Modifications to existing privacy controls that reduce protection | Privacy Team |

#### DPIA Process

```
┌─────────────────────────────────────────────────────────────────────┐
│               DPIA PROCESS FLOW                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  STEP 1: SCREENING                                                   │
│  ├─ Is DPIA required? (check trigger criteria above)                │
│  └─ If YES, initiate full DPIA                                      │
│                                                                      │
│  STEP 2: DESCRIBE PROCESSING                                        │
│  ├─ Nature, scope, context, purposes of processing                  │
│  ├─ Data categories, sources, recipients                            │
│  ├─ Data flow mapping                                               │
│  └─ Legal basis identification                                      │
│                                                                      │
│  STEP 3: ASSESS NECESSITY & PROPORTIONALITY                         │
│  ├─ Is processing necessary for stated purpose?                     │
│  ├─ Can purpose be achieved with less data?                         │
│  ├─ Are there less privacy-intrusive alternatives?                  │
│  └─ Is data accurate and up-to-date?                                │
│                                                                      │
│  STEP 4: IDENTIFY & ASSESS RISKS                                    │
│  ├─ Identify privacy risks to individuals                           │
│  ├─ Assess likelihood and severity of each risk                     │
│  ├─ Consider risks from re-identification, unauthorized access,     │
│  │   data quality, unexpected use, etc.                             │
│  └─ Document risk scoring                                           │
│                                                                      │
│  STEP 5: IDENTIFY MITIGATIONS                                       │
│  ├─ Technical controls (encryption, access controls, anonymization) │
│  ├─ Organizational controls (training, policies, contracts)         │
│  ├─ Legal controls (DPAs, consent, legal bases)                     │
│  └─ Residual risk assessment after controls                         │
│                                                                      │
│  STEP 6: REVIEW & APPROVE                                           │
│  ├─ Privacy Team review                                             │
│  ├─ ⚖️ Attorney review (if high risk)                                │
│  ├─ WARB approval (if significant architecture impact)              │
│  ├─ DPO sign-off                                                    │
│  └─ Document final DPIA                                             │
│                                                                      │
│  STEP 7: INTEGRATE & MONITOR                                        │
│  ├─ Integrate mitigations into project plan                         │
│  ├─ Monitor ongoing compliance                                      │
│  ├─ Schedule DPIA review (annually or on material change)           │
│  └─ Close DPIA cycle                                                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 8.4 Privacy Requirements in Technical Specifications

All technical specifications for features processing personal data must include:

| Requirement | Specification Detail |
|-------------|---------------------|
| **Data Fields** | Complete list of all data fields collected, stored, processed, or transmitted |
| **Data Classification** | Tier assignment for each field |
| **Legal Basis** | Identified legal basis for each processing purpose |
| **Purpose Limitation** | Stated purpose for data collection; prohibition on use for other purposes |
| **Data Minimization** | Justification that each field is necessary; demonstrate no excessive collection |
| **Consent Design** | Consent collection mechanism (if consent-based); consent record fields |
| **Opt-Out Implementation** | Opt-out mechanism (if applicable); how opt-out signal is propagated to all systems and vendors |
| **DSAR Support** | How DSAR search, retrieve, and delete will be implemented for this feature |
| **Access Controls** | Role-based access design; principle of least privilege mapping |
| **Encryption Requirements** | At-rest encryption; in-transit encryption; key management approach |
| **Audit Logging** | What events are logged; log format; log retention; log immutability |
| **Data Retention** | Retention schedule; auto-deletion trigger; deletion verification |
| **Third-Party Data Sharing** | Categories of third parties; purpose; legal basis; contract requirements |
| **Data Flow Diagram** | End-to-end data flow: collection -> storage -> processing -> sharing -> deletion |
| **Privacy Notices** | Notice content; timing of notice; method of delivery |
| **Default Privacy Settings** | Most privacy-protective settings as default; no opt-out required for privacy |
| **Error Handling** | How errors are handled to prevent data exposure in error messages; no PII in logs |
| **Testing Requirements** | Privacy test cases; data flow validation; consent/opt-out testing |

### 8.5 Automated Privacy Testing in CI/CD Pipeline

| Test | Tool / Method | Gate | Frequency |
|------|--------------|------|-----------|
| **Hardcoded Secrets Detection** | git-secrets, truffleHog, Gitleaks | Pre-commit hook | Every commit |
| **Dependency Vulnerability Scan** | Snyk, Dependabot, Trivy, Grype | CI pipeline | Every PR |
| **Static Application Security Testing (SAST)** | Semgrep, SonarQube, CodeQL | CI pipeline | Every PR |
| **Data Flow Analysis** | Custom rules / Semgrep | CI pipeline | Every PR (target) |
| **PII in Logs Detection** | Custom regex / Semgrep | CI pipeline + log monitoring | Every PR + continuous |
| **Infrastructure as Code (IaC) Scan** | Checkov, tfsec | CI pipeline | Every infra PR |
| **Container Image Scan** | Trivy, Clair | CI pipeline | Every build |
| **Dynamic Application Security Testing (DAST)** | ZAP, Burp Suite | Pre-release | Major releases |
| **Access Control Tests** | Integration tests | CI pipeline | Every release |
| **Consent/Opt-Out Flow Tests** | Integration tests | CI pipeline | Every release |
| **DSAR Flow Tests** | Integration tests | CI pipeline | Every release |
| **Encryption Validation** | Custom test | CI pipeline | Every release |
| **Penetration Test** | External firm | Annual + major changes | Annual |
| **Privacy Impact Assessment** | Manual + automated triggers | Design gate | Every qualifying project |

### 8.6 Default Privacy Settings Table

| Setting | Default | Rationale |
|---------|---------|-----------|
| Data collection for AI training | OFF (opt-in) | Privacy-first; user must consent |
| Data sharing with third parties | OFF (opt-in) | Prohibited unless necessary for core service |
| Marketing communications | OFF (opt-in) | Require affirmative consent |
| Profile enrichment (skip tracing) | OFF (opt-in) | Require consent except for FSRA-permissible purposes |
| Automated decision-making disclosure | ON (displayed) | Transparent by default |
| Data retention (maximum) | As short as legally possible | Minimize risk |
| Data minimization | Collect minimum required | No excessive collection |
| Privacy notice display | Pre-collection | Notice before data collection |
| Cookie consent (website) | OFF (opt-in) | Privacy-first; no tracking without consent |
| GPC signal processing | ON (honored) | Comply with state law requirements |

---

## APPENDICES

### Appendix A: Glossary

| Term | Definition |
|------|-----------|
| CCPA/CPRA | California Consumer Privacy Act as amended by California Privacy Rights Act |
| DPA | Data Processing Agreement |
| DPIA | Data Protection Impact Assessment |
| DSAR | Data Subject Access Request |
| FCRA | Fair Credit Reporting Act |
| FIPPS | Fair Information Privacy Principles |
| GLBA | Gramm-Leach-Bliley Act |
| GPC | Global Privacy Control |
| HSM | Hardware Security Module |
| PAM | Privileged Access Management |
| PIA | Privacy Impact Assessment |
| POLP | Principle of Least Privilege |
| RBAC | Role-Based Access Control |
| SCC | Standard Contractual Clauses (EU) |
| TCPA | Telephone Consumer Protection Act |
| TDE | Transparent Data Encryption |
| WARB | Wheeler Architecture Review Board |

### Appendix B: Document Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-05-25 | Wheeler Data Privacy Architect | Initial framework |

### Appendix C: Review and Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Data Privacy Architect | Wheeler AI Agent | 2026-05-25 | AI-Generated |
| Chief Compliance Officer (Designate) | [HUMAN OPERATOR] | ⚖️ PENDING | [PENDING] |
| ⚖️ Attorney Review | [EXTERNAL COUNSEL] | ⚖️ PENDING | [PENDING] |
| Wheeler Architecture Review Board | WARB | ⚖️ PENDING | [PENDING] |
| Chief Executive | [HUMAN OPERATOR] | ⚖️ PENDING | [PENDING] |

---

## CRITICAL ACTION ITEMS (PRIORITY ORDERED)

| Priority | Action Item | Owner | Target Date | Section Reference |
|----------|-------------|-------|-------------|-------------------|
| **P0** | ⚖️ Determine FCRA applicability for skip tracing data | Attorney | Q3 2026 | 2.2 |
| **P0** | ⚖️ Determine GLBA applicability for payment/disbursement operations | Attorney | Q3 2026 | 2.2 |
| **P0** | ⚖️ Draft and publish public-facing CCPA-compliant Privacy Policy | Privacy + Attorney | Q3 2026 | 3.2 |
| **P0** | ⚖️ Implement DSAR intake, verification, and response workflow | Engineering + Privacy | Q3 2026 | 3.3 |
| **P0** | ⚖️ Implement TCPA consent documentation and DNC list scrubbing for phone/SMS outreach | Marketing + Attorney | Q3 2026 | 2.2 |
| **P0** | ⚖️ Implement CCPA Notice at Collection on all data collection points | Engineering + Privacy | Q3 2026 | 3.2 |
| **P0** | Implement column-level encryption for Tier 4 fields (SSN, bank accounts) | Engineering | Q4 2026 | 4.4 |
| **P0** | ⚖️ Review and update all vendor DPAs (Stripe, Anthropic, OpenAI, DeepSeek, GitHub) | Procurement + Attorney | Q3 2026 | 5.3 |
| **P1** | ⚖️ Conduct formal state applicability assessment for all 18 state privacy laws | Attorney | Q3 2026 | 2.1 |
| **P1** | Implement automated DSAR search across all data systems | Engineering | Q4 2026 | 3.3 |
| **P1** | Implement audit logging for all Tier 3-5 data access | Engineering | Q4 2026 | 4.5 |
| **P1** | Implement quarterly access review automation | Engineering + Security | Q4 2026 | 4.3 |
| **P1** | Implement automated data retention/deletion schedules | Engineering | Q4 2026 | 4.1 |
| **P1** | Develop multi-state breach notification template library | Privacy + Attorney | Q4 2026 | 6.1 |
| **P1** | Implement privacy-check gates in CI/CD pipeline | Engineering | Q4 2026 | 8.5 |
| **P1** | Implement GPC signal processing for CCPA opt-out | Engineering | Q4 2026 | 3.2 |
| **P2** | Implement key management system (HSM or cloud KMS) | Engineering | Q1 2027 | 4.4 |
| **P2** | Implement mTLS for inter-service communication | Engineering | Q1 2027 | 4.4 |
| **P2** | Conduct first Data Breach Tabletop Exercise | Security + Privacy | Q3 2026 | 7.2 |
| **P2** | Complete DPIA for all existing high-risk processing activities | Privacy + Attorney | Q4 2026 | 8.3 |
| **P2** | Implement comprehensive privacy metrics dashboard | Engineering + Privacy | Q1 2027 | 7.1 |
| **P2** | ⚖️ Audit existing data processing for potential FCRA-covered activities | Attorney | Q3 2026 | 2.2 |
| **P3** | Conduct formal GDPR applicability assessment | Privacy + Attorney | Q4 2026 | 2.4 |
| **P3** | Implement cookie consent management platform (if website) | Engineering + Marketing | Q1 2027 | 3.2 |
| **P3** | Implement AI explainability for automated decision systems | Engineering + AI | Q2 2027 | 3.2 |
| **P3** | Conduct first annual penetration test | External Pen Test Firm | Q3 2026 | 7.2 |

---

**END OF DOCUMENT**

---

*This document is a governance framework and does not constitute legal advice. All items marked with ⚖️ ATTORNEY REVIEW REQUIRED must be reviewed by qualified legal counsel before implementation. The Wheeler Ecosystem operates across multiple jurisdictions with varying legal requirements; this framework establishes baseline controls and identifies areas requiring legal determination.*
