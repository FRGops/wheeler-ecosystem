# Wheeler Contract Governance System (WCO)

**Document ID:** WCO-GOV-001
**Version:** 1.0.0
**Effective Date:** 2026-05-25
**Owner:** Office of General Counsel (retained/reviewed)
**Classification:** Confidential — Attorney-Client Privileged Work Product

---

> **DISCLAIMER:** This document is a governance framework and does not constitute legal advice. Every section marked with ⚖️ ATTORNEY REVIEW REQUIRED indicates a point where licensed legal counsel must review and approve specific language, procedures, or determinations. This framework is designed to be reviewed by a licensed attorney before operational use. Wheeler Ecosystem LLC and its subsidiaries disclaim all liability arising from use of this framework without attorney guidance.

---

## TABLE OF CONTENTS

1. [TEMPLATE INVENTORY](#1-template-inventory)
2. [DOCUMENT GOVERNANCE FRAMEWORK](#2-document-governance-framework)
3. [CONTRACT LIFECYCLE MANAGEMENT](#3-contract-lifecycle-management)
4. [SPECIFIC CLAUSE LIBRARY](#4-specific-clause-library)
5. [COMPLIANCE CHECKLIST](#5-compliance-checklist)
6. [GOVERNANCE CALENDAR](#6-governance-calendar)
7. [TECHNOLOGY REQUIREMENTS](#7-technology-requirements)
8. [APPENDICES](#8-appendices)

---

## 1. TEMPLATE INVENTORY

### 1.1 Risk Tier Classification

| Tier | Classification | Definition | Attorney Review | Max Commitment |
|------|---------------|------------|-----------------|----------------|
| **Tier 1** | Critical | Required before any operations in the business unit | ⚖️ Mandatory | None without sign-off |
| **Tier 2** | High Priority | Required before scaling beyond pilot/prototype | ⚖️ Required | $50,000 or 12 months |
| **Tier 3** | Standard | Required for operational maturity | ⚖️ Recommended | $10,000 or data-only |

---

### 1.2 Tier 1 — Critical (Must Have Before Operations)

#### 1.2.1 Claimant Retainer / Assignment Agreement

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-CA-001 |
| **Tier** | 1 — Critical |
| **Business Units** | Funds Recovery Group (FRG) |
| **Purpose** | Engage claimants in funds recovery cases; define scope of representation, fee structure, and assignment of rights |
| **Delivery** | Print + e-signature (DocuSign) |

**Key Clauses:**
- Scope of engagement (specific claim/asset identified with particularity)
- Fee structure (contingency percentage, flat fee, or hybrid)
- Cost advancement and reimbursement
- Cancellation / rescission rights (state law compliance)
- Power of attorney for court filings and administrative claims
- Confidentiality of claimant information
- Governing law (state-specific)
- Dispute resolution (arbitration with carve-out for fee disputes)

**Required Fields/Inputs:**
```
[Claimant Full Legal Name]
[Claimant Contact Information]
[Claim/Asset Description]
[Estimated Claim Value]
[Fee Structure - % or Fixed]
[Governing State]
[Signatory Authority Statement]
```

**Approval Chain:**
1. FRG Business Unit Lead
2. Compliance Officer
3. ⚖️ Licensed Attorney (review of disclosures, state bar compliance)
4. Executive Director FRG

**Version Control:** WCO-CA-001-v{MAJOR}.{MINOR}.{PATCH}
- MAJOR: Substantive legal changes
- MINOR: Formatting, field adjustments, state-specific addenda
- PATCH: Clerical corrections, typographical fixes

**⚠️ ATTORNEY REVIEW REQUIRED:**
- All fee structure language
- Power of attorney grant
- Cancellation right disclosures
- Assignment of claims language
- State-specific bar compliance

---

#### 1.2.2 Attorney Engagement Agreement

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-ATTY-001 |
| **Tier** | 1 — Critical |
| **Business Units** | Attorney Marketplace, Funds Recovery Group |
| **Purpose** | Engage licensed attorneys as independent contractors or co-counsel |
| **Delivery** | E-signature required |

**Key Clauses:**
- Scope of representation (matter-specific; no blanket authorization)
- Fee arrangement (hourly, flat, contingency, or hybrid)
- Client communication standards (response times, reporting cadence)
- File retention and return upon termination
- Malpractice insurance requirements (minimum $1M/$3M)
- Conflicts check obligation
- Termination rights (client, attorney, marketplace)
- Fee splitting compliance (state bar rules)
- IOLTA/IOTA trust accounting obligations

**Required Fields/Inputs:**
```
[Attorney Name and Bar Number]
[State(s) of Licensure]
[Practice Area(s)]
[Matter/Claim Description]
[Fee Arrangement Type and Amount]
[Insurance Carrier and Policy Limits]
[Trust Account Information (if applicable)]
```

**Approval Chain:**
1. Marketplace Business Unit Lead
2. Compliance Officer
3. ⚖️ Licensed Attorney (mandatory)
4. CEO or COO (for fee arrangements > $100K)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Fee splitting provisions (state-specific bar rules)
- Malpractice insurance adequacy
- Trust account (IOLTA) compliance language
- Scope of representation limitations
- State ethical wall / imputation provisions

---

#### 1.2.3 SaaS Terms of Service

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-SAAS-001 |
| **Tier** | 1 — Critical |
| **Business Units** | SurplusAI, Prediction Radar, AI Ops Platform, SaaS/API Monetization |
| **Purpose** | Standardized terms for all Wheeler SaaS products |
| **Delivery** | Click-through + browsewrap (banner notice) |

**Key Clauses:**
- Acceptance (click-through affirmative act required)
- Account registration and security obligations
- Acceptable use policy (prohibited activities enumerated)
- Service level commitments (uptime, support response)
- Limitations of liability (cap = fees paid in preceding 12 months)
- Data rights (customer owns data; Wheeler gets license to operate)
- Payment terms (Net 30, auto-renewal, late fees)
- Termination (for cause + convenience with notice)
- Dispute resolution (mandatory arbitration, class action waiver)
- Governing law (Delaware, or state of customer domicile)
- AI output disclaimer (no guarantees of accuracy, not legal/financial advice)

**Required Fields/Inputs:**
```
[Product/Service Name]
[Subscription Tiers and Pricing]
[Data Processing Scope (if personal data)]
[Service Level Objectives]
[Contact for Legal Notices]
```

**Approval Chain:**
1. Product Business Unit Lead
2. Compliance Officer
3. ⚖️ Attorney (limitation of liability, arbitration clause)
4. CEO (for material departures from standard terms)

**Version Control:** WCO-SAAS-001-v{MAJOR}.{MINOR}.{PATCH}

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Limitation of liability cap adequacy
- Arbitration clause enforceability (per state/FAA)
- Class action waiver validity
- AI output disclaimer (state-specific requirements)
- Autorenewal compliance (state auto-renewal laws)

---

#### 1.2.4 Privacy Policy

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-PRIV-001 |
| **Tier** | 1 — Critical |
| **Business Units** | ALL business units |
| **Purpose** | Disclose data collection, use, sharing, and retention practices |
| **Delivery** | Website footer link + sign-up flow disclosure |

**Key Clauses:**
- Categories of personal information collected
- Sources of collection
- Business/commercial purpose for collection
- Third-party sharing (categories of recipients)
- Data retention schedule
- Consumer rights (access, deletion, correction, portability, opt-out)
- CCPA/CPRA compliance (Notice at Collection, Do Not Sell/Share)
- GDPR compliance (legal basis, international transfers, DPO contact)
- Cookie policy (with consent mechanism)
- "Sale/Share" opt-out mechanism
- Contact information and response timelines

**Required Fields/Inputs:**
```
[Business Name and Contact]
[List of Data Categories Collected]
[Third-Party Recipient Categories]
[Data Retention Periods]
[Applicable Jurisdictions (CA, EU, UK, etc.)]
[DPO Contact (if applicable)]
[Children's Data? Yes/No]
```

**Approval Chain:**
1. Compliance Officer
2. ⚖️ Attorney (mandatory)
3. CEO (for material changes)

**Version Control:** WCO-PRIV-001-v{MAJOR}.{MINOR}.{PATCH}
- MAJOR: Regulatory change (new privacy law)
- MINOR: Data practice changes
- PATCH: Contact/policy hyperlink updates

**⚠️ ATTORNEY REVIEW REQUIRED:**
- CCPA/CPRA notice-at-collection adequacy
- GDPR Article 13/14 disclosure completeness
- International transfer mechanism (SCCs, adequacy decision)
- "Sale" or "Share" definition applicability
- Sensitive personal information handling
- Children's privacy (COPPA)

---

### 1.3 Tier 2 — High Priority (Required Before Scaling)

#### 1.3.1 API License Agreement

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-API-001 |
| **Tier** | 2 — High Priority |
| **Business Units** | SurplusAI, Prediction Radar, SaaS/API Monetization |
| **Purpose** | License API access to third-party developers and integrators |
| **Delivery** | Click-through + signed (for enterprise tiers) |

**Key Clauses:**
- License grant (non-exclusive, non-transferable, revocable)
- Rate limits and throttling (specific to tier)
- Data usage restrictions (no re-licensing, no competitive use)
- Attribution requirements
- Indemnification (one-way: developer indemnifies Wheeler)
- API key management and security
- Developer dashboard access
- Usage analytics and reporting
- Suspension rights (abuse, non-payment, legal requirement)
- Termination (30-day cure period)
- Sunset / deprecation policy (12-month notice for breaking changes)

**Required Fields/Inputs:**
```
[Developer/Company Name]
[API Product Name]
[Tier and Rate Limits]
[Data License Scope (read/write/both)]
[Indemnification Cap]
```

**Approval Chain:**
1. Product Business Unit Lead
2. Compliance Officer
3. ⚖️ Attorney (recommended)
4. COO (for enterprise-tier agreements)

**⚠️ ATTORNEY REVIEW RECOMMENDED:**
- Indemnification scope and cap
- Sunset/deprecation obligations
- Data re-license restrictions
- API key liability allocation

---

#### 1.3.2 Referral / Partner Agreement

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-REF-001 |
| **Tier** | 2 — High Priority |
| **Business Units** | Attorney Marketplace, Lead Acquisition, Funds Recovery Group |
| **Purpose** | Define referral fee structures and compliance obligations for referral partners |
| **Delivery** | E-signature |

**Key Clauses:**
- Referral fee structure (flat fee, percentage, or tiered)
- Payment triggers (when fee is earned and payable)
- Compliance obligations (TCPA, CAN-SPAM, state bar rules)
- Non-circumvention (no direct solicitation of referred parties)
- Term and termination (30-day for convenience, immediate for cause)
- Confidentiality (partner information, fee structures)
- No guarantee of acceptance (Wheeler retains right to reject referrals)
- Independent contractor status (no agency, no employment)

**Required Fields/Inputs:**
```
[Partner Name and Contact]
[Referral Type (leads, claims, attorneys)]
[Fee Structure]
[Compliance Certifications]
[Term]
[Non-Circumvention Radius/Scope]
```

**Approval Chain:**
1. Business Unit Lead
2. Compliance Officer
3. ⚖️ Attorney (for bar-regulated referrals)
4. COO (for > $50K annual commission potential)

**⚠️ ATTORNEY REVIEW RECOMMENDED:**
- Fee splitting compliance (state bar rules)
- TCPA/CAN-SPAM compliance language
- Non-circumvention enforceability
- Independent contractor classification

---

#### 1.3.3 Data Processing Agreement (DPA)

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-DPA-001 |
| **Tier** | 2 — High Priority |
| **Business Units** | ALL (where customer personal data is processed) |
| **Purpose** | Satisfy GDPR Art. 28, CCPA/CPRA, and other regulatory processing requirements |
| **Delivery** | Signed counterpart (accepted via dashboard click-through for SaaS) |

**Key Clauses:**
- Processor obligations (process only on documented instructions)
- Data subject rights handling (timeline, notification, assistance)
- Sub-processor list and notification/objection process
- Security measures (technical and organizational — schedule)
- Breach notification (72 hours for GDPR, "without undue delay" for CCPA)
- International transfer mechanism (SCCs, DPF, adequacy decision)
- Data deletion/return upon termination
- Audit rights (customer or qualified third party)
- Liability (processor indemnification for breach of DPA obligations)
- Data Processing Exhibit (categories, processing purposes, retention)

**Required Fields/Inputs:**
```
[Customer Name]
[Categories of Data Subjects]
[Categories of Personal Data]
[Processing Purposes]
[Sub-processors (initial list)]
[International Transfers (countries)]
[Security Measures Reference]
```

**Approval Chain:**
1. DPO (or Compliance Officer)
2. ⚖️ Attorney (mandatory)
3. Information Security Officer (security measures approval)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- SCCs or adequacy decisions for international transfers
- Sub-processor objection timeline
- Audit right scope and cost allocation
- Liability allocation between controller/processor
- Regulatory jurisdiction variations (EU vs UK vs CH vs US states)

---

#### 1.3.4 Independent Contractor Agreement

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-IC-001 |
| **Tier** | 2 — High Priority |
| **Business Units** | ALL |
| **Purpose** | Engage individual contractors (attorneys, finders, researchers, developers) |
| **Delivery** | E-signature |

**Key Clauses:**
- Scope of work (SOW attached or described)
- Independent contractor classification (with IRS 20-factor checklist acknowledgment)
- Intellectual property assignment ("work made for hire" + assignment)
- Confidentiality obligations
- Non-solicitation (employees and clients, 12-month)
- Payment terms and invoicing
- No benefits, no workers' compensation (contractor acknowledgment)
- Indemnification (contractor indemnifies Wheeler)
- Termination (30-day notice either party)
- Survival (IP, confidentiality, indemnification)

**Required Fields/Inputs:**
```
[Contractor Name and Entity]
[Scope of Work Description]
[Payment Terms]
[IP Assignment Scope]
[Confidentiality Duration]
[Insurance Requirements]
```

**Approval Chain:**
1. Hiring Manager
2. Compliance Officer (classification review)
3. ⚖️ Attorney (mandatory for attorney contractors)
4. Finance (for > $100K annual value)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Independent contractor vs employee classification
- IP assignment enforceability
- Non-solicitation scope and duration
- Attorney-specific ethical obligations

---

### 1.4 Tier 3 — Standard (Operational Needs)

#### 1.4.1 NDA / Mutual Confidentiality Agreement

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-NDA-001 |
| **Tier** | 3 — Standard |
| **Business Units** | ALL |
| **Purpose** | Protect confidential information in negotiations, vendor relationships, and partnerships |
| **Delivery** | E-signature |

**Key Clauses:**
- Definition of confidential information (broad + exclusions)
- Mutual or one-way (default mutual; one-way for vendor evaluations)
- Term of confidentiality (3 years; 5 years for trade secrets)
- Permitted disclosures (employees, advisors, regulators, legal process)
- Return or destruction upon request
- No license (confidential information does not convey IP rights)
- No reverse engineering (for technical disclosures)

**Required Fields/Inputs:**
```
[Disclosing Party]
[Receiving Party]
[Purpose Description]
[Term of Confidentiality]
[Governing Law]
```

**Approval Chain:**
1. Business Unit Lead
2. Compliance Officer (if sensitive data involved)

**⚠️ ATTORNEY REVIEW NOT REQUIRED** for standard form. Review required for any modifications.

---

#### 1.4.2 Vendor Agreement

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-VENDOR-001 |
| **Tier** | 3 — Standard |
| **Business Units** | ALL |
| **Purpose** | Standard procurement terms for third-party vendors and service providers |
| **Delivery** | E-signature |

**Key Clauses:**
- Scope of services (detailed description or SOW)
- Service levels and performance metrics
- Payment terms (Net 30, no auto-renewal)
- Insurance requirements ($1M general liability, $1M professional liability)
- Data security requirements (minimum SOC 2 Type II)
- Audit rights
- Limitations of liability (mutual, cap = 12 months fees)
- Termination (30-day convenience, 5-day for cause)
- Confidentiality (flow-down from Wheeler's obligations)

**Required Fields/Inputs:**
```
[Vendor Name and Entity]
[Services Description]
[Service Level Agreements]
[Insurance Certifications]
[Data Classification (if handling Wheeler data)]
[Contract Value and Term]
```

**Approval Chain:**
1. Procurement Lead
2. Compliance Officer (if data processing involved)
3. Information Security (if vendor handles PHI/PII)

**⚠️ ATTORNEY REVIEW REQUIRED** if:
- Vendor handles PHI/PII/PCI data
- Contract value > $250K
- Custom services (not COTS)
- Offshoring/subcontracting involved

---

#### 1.4.3 Lead Purchase Agreement

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-LEAD-001 |
| **Tier** | 3 — Standard |
| **Business Units** | Lead Acquisition, Attorney Marketplace |
| **Purpose** | Purchase leads from third-party lead generators |
| **Delivery** | E-signature |

**Key Clauses:**
- Data quality warranties (accuracy, recency, consent)
- Compliance representations and warranties (TCPA, CAN-SPAM, CCPA)
- Indemnification (one-way: seller indemnifies Wheeler for non-compliance)
- Lead scoring methodology (if applicable)
- Exclusivity (if any)
- Minimum volume commitments
- Quality scoring and rejection thresholds
- Remediation (replacements for non-compliant leads)
- Termination (immediate for compliance breach)
- Audit rights (Wheeler may audit lead source and consent records)

**Required Fields/Inputs:**
```
[Lead Source/Vendor Name]
[Lead Type and Volume]
[Lead Scoring/Quality Metrics]
[Price per Lead or Block]
[Consent Verification Method]
[Data Categories Purchased]
```

**Approval Chain:**
1. Lead Acquisition Lead
2. Compliance Officer (TCPA/CCPA review)
3. ⚖️ Attorney (recommended for > $100K annual spend)
4. CFO (for > $250K annual spend)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- TCPA compliance representations
- Indemnification adequacy
- CCPA "sale" of personal information implications
- Lead consent verification standards

---

#### 1.4.4 Skip Trace Service Agreement

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-SKIP-001 |
| **Tier** | 3 — Standard |
| **Business Units** | Funds Recovery Group, Data Scraping/Intelligence |
| **Purpose** | Engage skip tracing vendors for asset and person location services |
| **Delivery** | E-signature |

**Key Clauses:**
- FCRA compliance (vendor certifies not a consumer reporting agency)
- Data accuracy warranties
- Permissible purpose certification (Wheeler certifies lawful purpose)
- Data usage restrictions (no re-sale, no credit decisions)
- Prohibited data elements (no SSNs, no account numbers)
- Indemnification (vendor indemnifies for FCRA violations)
- Audit rights (Wheeler may audit data sources and methods)
- Termination (immediate for FCRA non-compliance)

**Required Fields/Inputs:**
```
[Service Provider Name]
[Data Types Provided]
[Permissible Purpose(s)]
[Volume/Frequency]
[Fee Structure]
```

**Approval Chain:**
1. Business Unit Lead
2. Compliance Officer (FCRA review)
3. ⚖️ Attorney (mandatory for FCRA compliance)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- FCRA compliance language (all provisions)
- Permissible purpose certification
- Data accuracy standards
- Prohibited data elements

---

#### 1.4.5 Document Preparation Disclosure

| Field | Detail |
|-------|--------|
| **Template ID** | WCO-DOC-001 |
| **Tier** | 3 — Standard |
| **Business Units** | Funds Recovery Group, Attorney Marketplace |
| **Purpose** | Disclose non-attorney document preparation services; avoid unauthorized practice of law |
| **Delivery** | Print + e-signature (before any document preparation) |

**Key Clauses:**
- Non-attorney disclosure (Wheeler is not a law firm)
- UPL disclaimer (no legal advice, no case evaluation)
- Scope of services (document preparation only)
- Client acknowledgment (signature required)
- Acknowledged right to consult independent attorney
- No guarantee of outcome
- Fee disclosure (separate from legal fees)
- State-specific UPL disclaimers

**Required Fields/Inputs:**
```
[Customer/Claimant Name]
[Document Type(s) Prepared]
[State of Service]
[Acknowledgment Signature]
```

**Approval Chain:**
1. Business Unit Lead
2. Compliance Officer
3. ⚖️ Attorney (mandatory — state-specific UPL analysis)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- State-specific UPL safe harbor compliance
- Scope of "document preparation" vs. "legal advice"
- Fee structure (no fee splitting implications)
- Disclosure prominence and timing

---

### 1.5 Template Inventory Summary Table

| Template ID | Name | Tier | Attorney Review | Max Commitment (without review) |
|-------------|------|------|----------------|--------------------------------|
| WCO-CA-001 | Claimant Retainer/Assignment | 1 — Critical | ⚖️ Mandatory | None |
| WCO-ATTY-001 | Attorney Engagement | 1 — Critical | ⚖️ Mandatory | None |
| WCO-SAAS-001 | SaaS Terms of Service | 1 — Critical | ⚖️ Mandatory | None |
| WCO-PRIV-001 | Privacy Policy | 1 — Critical | ⚖️ Mandatory | None |
| WCO-API-001 | API License Agreement | 2 — High Priority | ⚖️ Recommended | $50K / 12 mo |
| WCO-REF-001 | Referral/Partner Agreement | 2 — High Priority | ⚖️ Required (bar) | $50K / 12 mo |
| WCO-DPA-001 | Data Processing Agreement | 2 — High Priority | ⚖️ Mandatory | None (regulatory) |
| WCO-IC-001 | Independent Contractor | 2 — High Priority | ⚖️ Mandatory (attys) | $100K / 12 mo |
| WCO-NDA-001 | NDA / Confidentiality | 3 — Standard | Not required* | — |
| WCO-VENDOR-001 | Vendor Agreement | 3 — Standard | Conditional | $250K or data risk |
| WCO-LEAD-001 | Lead Purchase Agreement | 3 — Standard | ⚖️ Recommended | $100K annually |
| WCO-SKIP-001 | Skip Trace Agreement | 3 — Standard | ⚖️ Mandatory | None (FCRA) |
| WCO-DOC-001 | Document Prep Disclosure | 3 — Standard | ⚖️ Mandatory | None |

\* Standard NDA form only. Any modifications to WCO-NDA-001 require ⚖️ attorney review.

---

## 2. DOCUMENT GOVERNANCE FRAMEWORK

### 2.1 Version Control System

#### 2.1.1 Template ID Naming Convention

```
WCO-{TYPE}-{SEQ}[-{SUFFIX}]-v{MAJOR}.{MINOR}.{PATCH}
```

| Component | Description |
|-----------|-------------|
| `WCO` | Wheeler Contract Organization (fixed prefix) |
| `{TYPE}` | Document type code: CA, ATTY, SAAS, PRIV, API, REF, DPA, IC, NDA, VENDOR, LEAD, SKIP, DOC |
| `{SEQ}` | Three-digit sequence number (001, 002, ...) |
| `{SUFFIX}` | Optional: `-AMEND`, `-ADDENDUM`, `-STATE` (state-specific variant) |
| `v{MAJOR}` | Substantive legal or structural change |
| `v{MINOR}` | Non-substantive addition, field change, formatting |
| `v{PATCH}` | Typographical, clerical, or hyperlink correction |

**Examples:**
- `WCO-CA-001-v1.2.0` — Claimant Agreement, version 1.2.0
- `WCO-CA-001-CA-ADDENDUM-v1.0.0` — California-specific addendum to Claimant Agreement
- `WCO-SAAS-001-AMEND-v2.1.3` — Amendment to SaaS Terms, version 2.1.3

#### 2.1.2 Repository Structure

```
/root/legal-compliance-os/
  templates/
    tier1-critical/
      WCO-CA-001-claimant-retainer/
        WCO-CA-001-v1.0.0.md          # Current active version
        WCO-CA-001-v1.0.0.pdf          # Executable version (watermarked)
        WCO-CA-001-v0.9.0.md           # Archived previous version
        WCO-CA-001_CHANGELOG.md        # Per-template changelog
        WCO-CA-001_REVIEW_LOG.md       # Attorney review history
      WCO-ATTY-001-attorney-engagement/
      WCO-SAAS-001-terms-of-service/
      WCO-PRIV-001-privacy-policy/
    tier2-high/
      WCO-API-001-api-license/
      WCO-REF-001-referral/
      WCO-DPA-001-data-processing/
      WCO-IC-001-contractor/
    tier3-standard/
      WCO-NDA-001-nda/
      WCO-VENDOR-001-vendor/
      WCO-LEAD-001-lead-purchase/
      WCO-SKIP-001-skip-trace/
      WCO-DOC-001-doc-prep-disclosure/
  governance/
    WCO-GOV-001-v1.0.0.md               # This document
    WCO-GOV-001_APPROVAL-MATRIX.md       # Signature authority thresholds
    WCO-GOV-001_COMPLIANCE-CALENDAR.md   # Annual compliance calendar
  clause-library/
    limitation-of-liability-clauses.md
    indemnification-clauses.md
    data-protection-clauses.md
    dispute-resolution-clauses.md
    ...
  changelog/
    WCO-MASTER-CHANGELOG.md              # Repository-wide change log
```

#### 2.1.3 Version Control Rules

1. **Templates are immutable once approved.** No edits to a published version. Create a new version.
2. **Changelog required for every version change.** Must record: date, author, nature of change, approval reference.
3. **Git-based storage** with signed commits for all template changes.
4. **Branch protection:** `main` branch requires pull request with:
   - Tier 1: 2 approvers (including ⚖️ attorney)
   - Tier 2: 2 approvers
   - Tier 3: 1 approver (Compliance Officer minimum)
5. **Tags** applied to each release: `v1.0.0`, `v1.1.0`, etc.

---

### 2.2 Approval Workflow

#### 2.2.1 Standard Approval Flow (All Tiers)

```
                    ┌──────────────┐
                    │  DRAFT       │
                    │  (Author)    │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
            ┌───────┤ L1 REVIEW   ├──────────┐
            │       │ BU Lead     │  REJECT   │
            │       └──────┬───────┘          │
            │     APPROVED │                  │
            │              ▼                  │
            │       ┌──────────────┐          │
            │       │ L2 REVIEW   │          │
            │       │ Compliance  │          │
            │       └──────┬───────┘          │
            │     APPROVED │                  │
            │              ▼                  │
            │       ┌──────────────┐          │
            │       │ L3 REVIEW   │          │
            │       │ ⚖️ Attorney │          │
            │       └──────┬───────┘          │
            │     APPROVED │                  │
            │              ▼                  │
            │       ┌──────────────┐          │
            │       │ L4 REVIEW   │          │
            │       │ Executive   │          │
            │       └──────┬───────┘          │
            │     APPROVED │                  │
            │              ▼                  │
            │       ┌──────────────┐          │
            │       │ PUBLISH     │          │
            │       │ (Versioned) │          │
            │       └──────────────┘          │
            │                                 │
            └─────────────────────────────────┘
```

#### 2.2.2 Level Thresholds

| Level | Role | Tier 1 | Tier 2 | Tier 3 |
|-------|------|--------|--------|--------|
| L1 | Business Unit Lead | Required | Required | Required |
| L2 | Compliance Officer | Required | Required | Recommended |
| L3 | ⚖️ Licensed Attorney | Required | See §1.5 | Conditional |
| L4 | CEO / COO | $100K+ | $250K+ | $500K+ |

#### 2.2.3 Approval Evidence

Each approval level must document:
- Approver name and title
- Date and time
- Version reviewed (specific template ID + version)
- Approval outcome (approved / approved with conditions / rejected)
- Conditions or required changes (if any)
- Digital signature or verified email record

---

### 2.3 Execution Workflow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  TEMPLATE    │     │  NEGOTIATION │     │  EXECUTION   │
│  SELECTION   │ ──► │  & CUSTOM   │ ──► │  & SIGNING   │
│  (Auto via   │     │  (Controlled │     │  (DocuSign / │
│   Deal Desk) │     │   Redlines)  │     │   Wet Ink)   │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                                                  ▼
                                          ┌──────────────┐
                                          │  ARCHIVE &   │
                                          │  OBLIGATIONS │
                                          │  TRACKING    │
                                          │  (Repository) │
                                          └──────────────┘
```

#### 2.3.1 Execution Methods

| Method | Use Case | Security Requirements |
|--------|----------|----------------------|
| **DocuSign / HelloSign** | All Tier 2 and Tier 3 agreements; Tier 1 where counterparty accepts | ESIGN Act compliant, 2FA for signatory |
| **Wet Signature (ink)** | Tier 1 where e-signature not accepted; court filings; notarization required | Witness required for certain documents; PDF scan + originals to secure storage |
| **Click-through (in-app)** | SaaS ToS, API license, privacy policy acceptance | IP logging, timestamp, consent record stored |
| **Counterpart execution** | Multi-party agreements | Each counterpart = separate original; all constitute one agreement |

#### 2.3.2 Signature Authority Thresholds

| Role | Tier 1 | Tier 2 | Tier 3 |
|------|--------|--------|--------|
| CEO | Unlimited | Unlimited | Unlimited |
| COO | $250K | $500K | $1M |
| CFO | $100K | $250K | $500K |
| BU Lead | — | $50K | $100K |
| Product Manager | — | — | $25K |
| Compliance Officer | — | $50K (DPA only) | $50K |

**Branch approval required** when value exceeds individual authority — next level up must co-sign.

---

### 2.4 Audit Trail Requirements

#### 2.4.1 Minimum Audit Fields

Every versioned document and contract must maintain an immutable audit trail recording:

| Field | Description | Example |
|-------|-------------|---------|
| `event_id` | Unique event identifier | WCO-AUDIT-20260525-001 |
| `timestamp` | ISO 8601 UTC | 2026-05-25T14:30:00Z |
| `actor` | Individual who performed action | jdoe@wheeler.io |
| `action` | Action performed | `created`, `modified`, `approved`, `rejected`, `executed`, `terminated` |
| `document_id` | Template or contract ID | WCO-CA-001-v1.0.0 |
| `document_title` | Human-readable name | Claimant Retainer Agreement — Smith Claim |
| `previous_version` | Prior version (if applicable) | WCO-CA-001-v1.0.0 |
| `new_version` | New version (if applicable) | WCO-CA-001-v1.1.0 |
| `changes_summary` | Description of changes | "Added CA-specific cancellation disclosure" |
| `approval_reference` | Link to approval record | WCO-APPR-20260525-001 |
| `ip_address` | Originating IP | 203.0.113.42 |

#### 2.4.2 Audit Storage

- **Immutable store**: Git repository (signed commits) for template changes
- **Encrypted database** for executed contracts (AES-256 at rest)
- **Cloud audit log** (AWS CloudTrail or equivalent) for system access
- **Retention**: Audit trail retained for life of contract + 7 years
- **Quarterly audit review**: Compliance Officer reviews a random 10% sample

---

### 2.5 Document Retention Policy

#### 2.5.1 Retention Schedules

| Document Type | Minimum Retention | Destruction Method | Notes |
|---------------|-------------------|--------------------|-------|
| Executed contracts | Life + 7 years | Secure shredding + cryptographic deletion | Accounting/statute of limitations |
| Signed NDAs | 3 years after termination | Secure shredding | Statute of limitations |
| Privacy policies (historical) | Indefinite (archive) | N/A | Regulatory reference |
| Templates (superseded) | Indefinite (archive) | N/A | Legal reference |
| Approval records | Life of contract + 7 years | Cryptographic deletion | Audit requirement |
| Audit logs | 7 years | Cryptographic deletion | Regulatory compliance |
| Correspondence/negotiation | 3 years after execution | Secure deletion | May be relevant to disputes |

#### 2.5.2 Storage Locations

| Classification | Primary Storage | Backup | Access Control |
|---------------|----------------|--------|----------------|
| Templates (active) | Git repo (`main` branch) | GitHub | Tier-based R/O + PR-based write |
| Templates (archived) | Git repo (tags) | GitHub | Tier-based R/O |
| Executed contracts | Encrypted S3/GCS bucket | Cross-region replication | Role-based (see §2.5.3) |
| Audit logs | Immutable log store | S3 Glacier | Compliance + InfoSec only |
| Attorney-review work product | Encrypted, segregated | Restricted replication | ⚖️ Attorney + GC only |

#### 2.5.3 Access Control Matrix

| Role | Templates (R) | Templates (W) | Executed Contracts | Audit Logs |
|------|---------------|---------------|--------------------|------------|
| CEO | Full | L4 approval | Full | Full |
| COO | Full | L4 approval | Full | Full |
| CFO | Full | — | Financial only | Read-only |
| BU Lead | BU-specific | L1 submission | BU-specific | — |
| Compliance Officer | Full | L2 approval | Full | Full |
| ⚖️ Attorney | Full | L3 approval | Full (subject) | — |
| IC/Employees | Assigned | — | Assigned | — |
| External Auditor | — | — | By scope | By scope |

#### 2.5.4 Destruction Protocol

1. Retention period verified against §2.5.1 schedule
2. Destruction request submitted to Compliance Officer
3. Compliance Officer confirms no legal hold or active dispute
4. ⚖️ Attorney signs off (if established legal hold exists, retention continues)
5. Physical documents: cross-cut shredding + incineration certificate
6. Digital documents: cryptographic deletion (key rotation + overwrite)
7. Destruction certificate generated and retained permanently

---

### 2.6 Risk Scoring System

#### 2.6.1 Risk Score Calculation

```
Risk Score = (Legal Risk × 3) + (Financial Exposure × 2) + (Regulatory Risk × 3) + (Operational Complexity × 1)
```

| Factor | Weight | Scale 1–10 |
|--------|--------|------------|
| Legal Risk | ×3 | Likelihood and severity of litigation |
| Financial Exposure | ×2 | Maximum dollar exposure |
| Regulatory Risk | ×3 | Number and strictness of applicable regulations |
| Operational Complexity | ×1 | Difficulty of performance/monitoring |

**Score Ranges:**
- 10–29: Low risk (standard automated processing)
- 30–49: Moderate risk (Compliance Officer sign-off)
- 50–79: High risk (Attorney + Executive sign-off)
- 80–100: Critical (full board or GC approval required)

#### 2.6.2 Template Risk Scores

| Template ID | Legal Risk | Financial Exposure | Regulatory Risk | Operational Complexity | **Total** | **Classification** |
|-------------|-----------|-------------------|-----------------|----------------------|-----------|--------------------|
| WCO-CA-001 | 9 | 8 | 7 | 6 | **65** | High Risk |
| WCO-ATTY-001 | 9 | 7 | 9 | 5 | **68** | High Risk |
| WCO-SAAS-001 | 7 | 6 | 5 | 4 | **49** | Moderate Risk |
| WCO-PRIV-001 | 6 | 5 | 9 | 3 | **54** | High Risk |
| WCO-API-001 | 5 | 5 | 4 | 4 | **38** | Moderate Risk |
| WCO-REF-001 | 6 | 5 | 7 | 4 | **46** | Moderate Risk |
| WCO-DPA-001 | 6 | 5 | 9 | 5 | **52** | High Risk |
| WCO-IC-001 | 7 | 6 | 5 | 3 | **46** | Moderate Risk |
| WCO-NDA-001 | 3 | 2 | 1 | 1 | **17** | Low Risk |
| WCO-VENDOR-001 | 4 | 5 | 4 | 4 | **35** | Moderate Risk |
| WCO-LEAD-001 | 7 | 6 | 8 | 4 | **52** | High Risk |
| WCO-SKIP-001 | 8 | 7 | 9 | 5 | **58** | High Risk |
| WCO-DOC-001 | 7 | 5 | 7 | 3 | **48** | Moderate Risk |

---

## 3. CONTRACT LIFECYCLE MANAGEMENT

### 3.1 Pre-Contract Phase

```
┌─────────────────────────────────────────────────────────┐
│                  PRE-CONTRACT                            │
├─────────────┬───────────────┬─────────────┬──────────────┤
│  1. NEED    │   2. TIER     │   3. TEMPLATE  │  4. ROUTE  │
│  IDENTIFIED │  ASSESSMENT   │   SELECTION    │ APPROVAL   │
│             │               │                │            │
│ BU identifies│ Determine     │ Match need to │ Route via  │
│ need for    │ risk tier     │ WCO template  │ approval   │
│ agreement   │ using §2.6    │ inventory     │ workflow   │
│             │ scoring       │ (§1)          │ (§2.2)     │
└─────────────┴───────────────┴─────────────┴──────────────┘
```

**Checklist:**
- [ ] Business need documented
- [ ] Counterparty identified and vetted (sanctions screening, OFAC)
- [ ] Risk score calculated
- [ ] Appropriate template selected (deviations require justification)
- [ ] Approval routing initiated
- [ ] ⚖️ Attorney involvement determined based on risk score

---

### 3.2 Negotiation Phase

#### 3.2.1 Controlled Redlining

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  BASELINE    │───►│  REDLINE 1   │───►│  REDLINE 2   │
│  (Template)  │    │  (Counter-   │    │  (Wheeler    │
│              │    │   party)     │    │   Response)  │
└──────────────┘    └──────────────┘    └──────┬───────┘
                                                │
                                        ┌───────▼───────┐
                                        │     N ROUNDS  │
                                        │  (Iterate)    │
                                        └───────┬───────┘
                                                │
                                        ┌───────▼───────┐
                                        │  FINAL        │
                                        │  (Approved    │
                                        │   Redline)    │
                                        └───────┬───────┘
                                                │
                                        ┌───────▼───────┐
                                        │  CLEAN COPY   │
                                        │  (Executable) │
                                        └───────────────┘
```

#### 3.2.2 Fallback Positions

Each template should document fallback positions for key clauses:

| Clause | Preferred Position | Fallback 1 | Fallback 2 | ⚖️ Must Escalate |
|--------|-------------------|------------|------------|------------------|
| Liability Cap | Fees paid (12 mo) | Fees paid (24 mo) | 1× contract value | Uncapped liability |
| Indemnification | Mutual | One-way (Wheeler indemnified) | N/A | Counterparty indemnifies Wheeler for IP |
| Governing Law | Delaware | Counterparty state | JAMS arbitration | No Delaware carve-out |
| Arbitration | JAMS, Delaware | AAA, counterparty state | Litigation only | No venue provision |

#### 3.2.3 Negotiation Authority

| Role | Deviation Authority | ⚖️ Escalation Required |
|------|-------------------|----------------------|
| BU Lead | Fallback 1 | Fallback 2 or beyond |
| Compliance Officer | Fallback 2 | Any regulatory deviation |
| COO | Any deviation except liability cap | Reducing Wheeler's liability cap |
| CEO | Unlimited | N/A |
| ⚖️ Attorney | Any legal provision | N/A |

---

### 3.3 Execution Phase

#### 3.3.1 Authorized Signatories

See also: [Signature Authority Thresholds](#231-execution-methods-table) in §2.3.1.

**Quarterly refresh:** List of authorized signatories reviewed and updated by Compliance Officer every quarter.

#### 3.3.2 Execution Checklist

- [ ] Counterparty identity verified (EIN/SSN, business registry, OFAC)
- [ ] Signature authority confirmed against thresholds
- [ ] Required approvals obtained (L1–L4 as applicable)
- [ ] Final clean copy compared against approved redline
- [ ] Execution method determined (e-signature vs wet ink)
- [ ] ⚖️ Attorney sign-off obtained (if required by tier)
- [ ] Executed copy stored in contract repository
- [ ] Counterparty provided with fully executed copy
- [ ] Obligations entered into tracking system

---

### 3.4 Performance Phase

#### 3.4.1 Obligation Tracking

| Obligation Type | Monitoring Method | Frequency | Owner |
|----------------|-------------------|-----------|-------|
| Payment terms | Automated (billing system) | Per invoice | Finance |
| Data processing | Compliance review | Quarterly | Data Protection Officer |
| Service levels | Automated monitoring | Real-time | Engineering/Ops |
| Insurance | Certificate tracking | Quarterly | Risk Management |
| Confidentiality | No monitoring (breach-driven) | On incident | Compliance |
| Reporting | Calendar-based | Per contract | BU Lead |

#### 3.4.2 Renewal and Expiration Management

- **90 days before expiration**: System flags renewal date
- **60 days before**: BU Lead decides renew / renegotiate / let expire
- **45 days before**: ⚖️ Attorney review if renegotiation involves material changes
- **30 days before**: Counterparty notified of intent
- **Auto-renewal**: Must be affirmatively confirmed by BU Lead (no silent auto-renewal)
- **Expiration log**: All expired contracts recorded with disposition

#### 3.4.3 Compliance Monitoring

- **Quarterly compliance review** for all active Tier 1 and Tier 2 contracts
- **Annual compliance review** for Tier 3 contracts
- **Triggered review** upon: regulatory change, breach notice, assignment, or amendment

---

### 3.5 Termination Phase

#### 3.5.1 Termination Types

| Type | Notice Period | Cure Period | Documentation |
|------|---------------|-------------|---------------|
| Termination for Convenience | Per contract (default 30 days) | N/A | Written notice |
| Termination for Cause (curable) | Per contract (default 5 days) | 30 days | Written notice + cure opportunity |
| Termination for Cause (material breach) | Immediate | None | Written notice + evidence |
| Termination for Insolvency | Immediate | None | Written notice + proof |

#### 3.5.2 Termination Checklist

- [ ] Notice given per contract requirements
- [ ] Data return/deletion initiated (with certificate)
- [ ] Final invoice/payment processed
- [ ] Confidential information returned or destroyed
- [ ] Access revoked (systems, facilities, data)
- [ ] Survival clauses identified and preserved
- [ ] Termination recorded in contract repository
- [ ] Obligation tracking system updated to "Terminated"
- [ ] ⚖️ Attorney review if dispute anticipated

#### 3.5.3 Survival Clauses

[See §4.10 for standard survival durations](#410-survival-of-terms)

---

## 4. SPECIFIC CLAUSE LIBRARY

> **IMPORTANT:** This clause library provides standardized language and guidance. All clauses must be reviewed and approved by ⚖️ licensed counsel before inclusion in any binding agreement. Clause language below is a FRAMEWORK, not a final legal text.

### 4.1 Limitation of Liability

#### 4.1.1 Tiered Liability Caps

| Contract Type | Standard Cap | Negotiated Cap | ⚖️ No Cap |
|---------------|-------------|----------------|-----------|
| SaaS/API | Fees paid in preceding 12 months | Fees paid in 24 months | Never |
| Professional Services | 1× service fees | 2× service fees | Never |
| Data/Analytics | Fees paid in 12 months or $50K (whichever less) | $250K | Never |
| Referral/Lead | Fees paid in 6 months | Fees paid in 12 months | Never |
| Enterprise/Strategic | $1M | $5M | Board approval + GC |

#### 4.1.2 Exclusions from Liability Cap

Standard exclusions from the liability cap (these are uncapped):
- Breach of confidentiality
- Breach of data protection obligations
- Indemnification obligations
- IP infringement
- Gross negligence or willful misconduct
- Fraud or fraudulent misrepresentation

#### 4.1.3 Disclaimer of Consequential Damages

Standard provision disclaiming: lost profits, lost revenue, lost data, loss of goodwill, cost of substitute services, business interruption, and indirect/special/incidental/punitive damages.

**⚠️ STATE-SPECIFIC NOTES:**
- Some states (NJ, CT, LA) restrict disclaimer of consequential damages
- Punitive damages disclaimers may not be enforceable in all states
- AI output limitations may face additional scrutiny

---

### 4.2 Indemnification

#### 4.2.1 Indemnification Matrix

| Scenario | Direction | Standard | Negotiated |
|----------|-----------|----------|------------|
| IP infringement by Wheeler | Wheeler indemnifies customer | Yes | Yes |
| IP infringement by customer | Customer indemnifies Wheeler | Yes | Yes |
| Data breach by Wheeler | Wheeler indemnifies customer | Yes | Yes |
| Data breach by customer | Customer indemnifies Wheeler | Recommended | Yes |
| FCRA/TCPA violation by vendor | Vendor indemnifies Wheeler | Yes | Yes |
| Lead source compliance failure | Seller indemnifies buyer | Yes | Yes |
| Third-party claims against Wheeler | Customer indemnifies Wheeler | No | Rare |

#### 4.2.2 Indemnification Procedure

1. Indemnified party gives prompt written notice (but failure does not relieve indemnitor unless prejudiced)
2. Indemnitor has right to assume defense with counsel of its choice
3. Indemnified party may participate at its own expense
4. Settlement requires indemnified party's written consent (not to be unreasonably withheld)
5. Indemnitor may not settle in a manner that admits fault or imposes injunctive relief without consent

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Defense control provisions
- Settlement consent rights
- IP indemnity exclusions (open source, modifications, combinations)
- Survival of indemnification post-termination

---

### 4.3 Data Protection and Security

#### 4.3.1 Standard Data Protection Clause

**Minimum requirements (all vendors processing Wheeler data):**
- SOC 2 Type II certification (or equivalent)
- Encryption at rest (AES-256) and in transit (TLS 1.2+)
- Access controls (least privilege, MFA, terminated access within 24 hours)
- Incident response plan with 24-hour notification
- Background checks for personnel with data access
- Annual penetration testing
- Data breach insurance ($2M minimum)

#### 4.3.2 Data Processing Addendum

For full DPA language, see WCO-DPA-001 (§1.3.3).

**Key data protection terms that MUST appear in every contract handling personal data:**
- [ ] Data Processing Addendum attached or incorporated
- [ ] Sub-processor list and notification requirement
- [ ] Data subject rights assistance
- [ ] Breach notification procedures and timing
- [ ] Data deletion/return upon termination
- [ ] International transfer mechanism (SCCs, DPF)
- [ ] Audit rights (or SOC 2 report access)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Cross-border data transfer mechanisms
- Sub-processor liability allocation
- Audit right scope and frequency
- Data breach notification timing (regulatory requirements vary)

---

### 4.4 Confidentiality

#### 4.4.1 Standard NDA Terms (WCO-NDA-001)

| Element | Standard Term |
|---------|---------------|
| Definition | All information disclosed, marked or unmarked if reasonably identifiable as confidential |
| Exclusions | Public domain (not by breach), independently developed, received from third party without restriction, disclosed with written approval |
| Obligations | Hold confidential, use only for purpose, limit access to need-to-know, protect with reasonable care |
| Permitted disclosures | Employees and advisors (bound by NDA), legal process (with prompt notice), regulators |
| Term | 3 years (5 years for trade secrets) |
| Return/destruction | Upon request, with certification |

#### 4.4.2 Mutual vs. One-Way

| Default | When to Use |
|---------|-------------|
| Mutual | Partnerships, strategic alliances, M&A discussions |
| One-way (Wheeler discloses) | Vendor evaluations, contractor engagements |
| One-way (counterparty discloses) | Customer evaluations (rare) |

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Definition of confidential information (too narrow risks exclusion of critical data)
- Exclusions (independently developed — need tracking mechanisms)
- Legal process exception (notice timing and cooperation obligations)
- Return/destruction (practicality for electronic systems)

---

### 4.5 Intellectual Property

#### 4.5.1 IP Ownership Framework

| Scenario | Wheeler Owns | Customer/Partner Owns | Shared |
|----------|-------------|----------------------|--------|
| SaaS platform (code) | All pre-existing + improvements | — | — |
| Customer data | — | All customer data | — |
| Aggregated/anonymized analytics | Yes (de-identified) | — | — |
| Custom development (paid) | Per agreement | Typically customer | — |
| AI model outputs | Per agreement/Terms | Typically user | — |
| Feedback/suggestions | Yes (irrevocable license) | — | — |
| Joint development | — | — | Per JDA terms |

#### 4.5.2 Standard IP Clause

**Key provisions:**
- Wheeler retains all rights to pre-existing IP, platform, and improvements
- Customer retains all rights to its data and content
- Customer grants Wheeler license to operate the service (host, display, process)
- Wheeler may use anonymized/aggregated data for product improvement
- Customer feedback is assigned to Wheeler
- No transfer of IP rights from Wheeler (license only)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- AI training data rights (customer data used for model training?)
- Aggregated data definition (re-identification risk)
- Feedback assignment (AI training implications)
- Open source license compatibility

---

### 4.6 Dispute Resolution

#### 4.6.1 Dispute Resolution Ladder

```
┌─────────────────────────────────────────────────────────┐
│                   DISPUTE RESOLUTION                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. NEGOTIATION                                         │
│     └─ Escalation: BU Lead → Compliance → CEO           │
│        Deadline: 30 days                                │
│                                                         │
│  2. MEDIATION (optional, recommended)                   │
│     └─ JAMS or AAA mediation rules                      │
│        Deadline: 60 days                                │
│        Split mediator fees equally                      │
│                                                         │
│  3. ARBITRATION (standard)  OR  LITIGATION (enterprise) │
│     └─ JAMS / AAA rules                                 │
│        Single arbitrator (under $500K)                  │
│        Panel of 3 ($500K+)                              │
│        Location: Delaware or per agreement              │
│        Governing law: Delaware (unless specified)        │
│        Class action waiver (standard)                   │
│                                                         │
│  4. APPEAL                                              │
│     └─ Expanded panel (3 arbitrators)                   │
│        Limited to errors of law                         │
│                                                         │
│  5. EQUITABLE RELIEF                                    │
│     └─ Any court with jurisdiction                      │
│        For IP breach, confidentiality breach,            │
│        or where monetary damages inadequate             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

#### 4.6.2 Arbitration vs. Litigation

| Factor | Arbitration | Litigation |
|--------|------------|------------|
| Cost | Higher for small claims | Higher for large claims |
| Speed | Faster (6–12 months) | Slower (18–36 months) |
| Discovery | Limited | Broad |
| Appeal | Very limited | Full |
| Privacy | Confidential | Public record |
| Precedent | None | Binding |
| Class actions | Can be waived | Cannot be waived unilaterally |

**Default:** Arbitration (SaaS, mass-market agreements)
**Enterprise exception:** Litigation (enterprise agreements with > $1M annual value)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Class action waiver enforceability (SCOTUS precedent-dependent)
- Arbitration clause delegation clause
- State-specific unconscionability risks
- JAMS/AAA rule version and cost allocation

---

### 4.7 Force Majeure

#### 4.7.1 Standard Force Majeure Events

- Acts of God (natural disasters, extreme weather)
- War, terrorism, civil unrest
- Government action (embargoes, sanctions, orders)
- Pandemics and public health emergencies
- Internet/telecommunications failures (beyond party's control)
- Cybersecurity attacks (DDoS, ransomware)
- Power outages (beyond party's control)
- Labor strikes and shortages

#### 4.7.2 Key Provisions

- **Suspension of performance** during force majeure event
- **Notice obligation**: Prompt written notice (within 5 days of onset)
- **Mitigation obligation**: Reasonable efforts to resume performance
- **Duration limit**: If force majeure exceeds 60 consecutive days, either party may terminate
- **Excluded events**: Economic hardship, market changes, increased costs, equipment failure, software bugs (not force majeure)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Pandemic inclusion (post-COVID standard)
- Cyberattack inclusion (increasingly standard, but scope matters)
- Duration limit — shorter for time-sensitive agreements
- Force majeure does not excuse payment obligations (standard provision)

---

### 4.8 Assignment and Change of Control

#### 4.8.1 Assignment Provisions by Contract Type

| Contract Type | Wheeler May Assign | Counterparty May Assign |
|---------------|-------------------|------------------------|
| SaaS (mass-market) | Freely (with notice) | With consent (not unreasonably withheld) |
| SaaS (enterprise) | To affiliate or acquirer | With consent |
| Professional Services | With consent (not unreasonably withheld) | With consent |
| Referral/Partner | Freely | With consent |
| DPA | To sub-processor (with notice) | With consent |
| NDA | To successor-in-interest | To successor-in-interest |

**Change of control trigger:** Merger, acquisition, sale of substantially all assets, change in controlling ownership.

**Effect of assignment:** Assignee bound in writing to all terms; assigning party remains liable unless expressly released.

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Anti-assignment provisions and UCC Article 2 implications
- Change of control definition (percentage threshold)
- Competitive assignment restrictions
- Governmental entity assignment (anti-assignment statutes)

---

### 4.9 Termination

#### 4.9.1 Termination for Convenience vs. For Cause

| Type | Notice Period | Consequences |
|------|---------------|--------------|
| Convenience (Wheeler) | 30 days | No fees/penalties; prorated refund of prepaid fees |
| Convenience (counterparty) | 30 days | No fees/penalties; prorated refund of prepaid fees |
| Cause — non-payment | 10 days | Immediate upon cure failure |
| Cause — material breach | 30 days (cure) | Immediate upon cure failure |
| Cause — IP breach | 5 days | Immediate if infringement confirmed |
| Cause — regulatory violation | 5 days | Immediate |
| Cause — insolvency | Immediate | Immediate |

#### 4.9.2 Effect of Termination

- License rights terminate
- Confidential information returned or destroyed
- Data returned or deleted as per DPA
- Accrued payment obligations remain
- Survival clauses remain in effect

---

### 4.10 Survival of Terms

| Clause | Survival Period | Rationale |
|--------|----------------|-----------|
| Payment obligations | Until satisfied | {Accounts payable} |
| Confidentiality | Term of confidentiality per NDA clause | Trade secret protection |
| Data protection | Until data destroyed | Regulatory requirement |
| Indemnification | 3 years post-termination | Discovery delay |
| Limitation of liability | 3 years post-termination | Claims may arise after termination |
| IP provisions | Perpetual | Ownership is permanent |
| Dispute resolution | Perpetual | Governing law for post-termination disputes |
| Audit rights | 1 year post-termination | Practical limitation |

---

### 4.11 Entire Agreement / Integration

**Standard language:** "This Agreement constitutes the entire agreement between the parties and supersedes all prior agreements, understandings, negotiations, and representations, whether written or oral, relating to its subject matter."

**Exceptions:**
- Exhibits, schedules, and addenda explicitly incorporated
- Pre-existing NDAs remain in effect (if specified)
- Order forms and SOWs prevail over general terms (document hierarchy)

**Modification:** Only by written amendment signed by both parties (no oral modifications, no clickwrap modifications without notice).

**Waiver:** No waiver of any term is effective unless in writing; no waiver constitutes a continuing waiver.

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Pre-existing agreement conflict resolution
- Order form vs. MSA conflict priority
- Course of dealing and course of performance implications (UCC 1-303)

---

### 4.12 Severability

**Standard language:** "If any provision of this Agreement is held invalid or unenforceable, the remainder remains in full force and effect, and the invalid provision shall be modified to the minimum extent necessary to make it enforceable while reflecting the parties' original intent."

**Reformation hierarchy:**
1. Automatic severance (remove invalid provision)
2. Judicial reformation (court modifies provision)
3. Negotiated replacement (parties agree on substitute)
4. Dispute resolution (if parties cannot agree on replacement)

---

### 4.13 Notices

| Type | Method | Timing | Address |
|------|--------|--------|---------|
| Legal notices (termination, breach, indemnification) | Certified mail, return receipt, or overnight courier | Deemed received upon delivery | To legal department, with email confirmation |
| Operational notices (product changes, scheduled maintenance) | Email | Deemed upon sending | To designated operational contacts |
| Billing notices | Email + portal | Deemed upon sending | To billing contacts |
| General correspondence | Email | Deemed upon sending | To designated representatives |

---

## 5. COMPLIANCE CHECKLIST

### 5.1 Per-Contract-Type Compliance Matrix

| Template ID | UDAAP | State Bar | CCPA/CPRA | GDPR | FCRA | TCPA | CAN-SPAM | TILA/RESPA | FTC Cooling-Off | UPL |
|-------------|-------|-----------|-----------|------|------|------|----------|-------------|----------------|-----|
| WCO-CA-001 | ✓ | ⚖️ | — | — | — | — | — | — | ✓ | ⚖️ |
| WCO-ATTY-001 | ✓ | ⚖️ | — | — | — | — | — | — | — | ⚖️ |
| WCO-SAAS-001 | ✓ | — | ✓ | ✓ | — | — | — | — | — | — |
| WCO-PRIV-001 | ✓ | — | ⚖️ | ⚖️ | — | — | — | — | — | — |
| WCO-API-001 | ✓ | — | ✓ | ✓ | — | — | — | — | — | — |
| WCO-REF-001 | ✓ | ⚖️ | ✓ | ✓ | — | ⚖️ | ⚖️ | — | — | — |
| WCO-DPA-001 | — | — | ⚖️ | ⚖️ | — | — | — | — | — | — |
| WCO-IC-001 | — | ⚖️ | — | — | — | — | — | — | — | — |
| WCO-NDA-001 | — | — | — | — | — | — | — | — | — | — |
| WCO-VENDOR-001 | — | — | ✓ | ✓ | — | — | — | — | — | — |
| WCO-LEAD-001 | ✓ | — | ⚖️ | — | — | ⚖️ | ⚖️ | — | — | — |
| WCO-SKIP-001 | ✓ | — | ✓ | — | ⚖️ | — | — | — | — | — |
| WCO-DOC-001 | ✓ | — | — | — | — | — | — | — | ⚖️ | ⚖️ |

**Key:**
- ✓ = Standard compliance obligation
- ⚖️ = ⚖️ Attorney review required for this regulation
- — = Not typically applicable

---

### 5.2 Regulatory Detail

#### 5.2.1 Consumer Contracts: UDAAP Compliance

**Applicable to:** WCO-CA-001, WCO-SAAS-001, WCO-PRIV-001, WCO-API-001, WCO-REF-001, WCO-LEAD-001, WCO-SKIP-001, WCO-DOC-001

**Checklist:**
- [ ] No deceptive acts or practices (misleading statements, omissions)
- [ ] No unfair acts or practices (substantial injury not outweighed by benefits)
- [ ] Clear and conspicuous disclosure of material terms
- [ ] No abusive acts (taking unreasonable advantage of consumer lack of understanding)
- [ ] Fees disclosed in dollar amounts (not just percentages)
- [ ] Cancellation rights clearly stated
- [ ] Renewal/autorenewal terms disclosed (state-specific)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- UDAAP scope is fact-specific — each marketing practice must be reviewed
- State UDAAP variations (some states have broader protections than FTC Act)
- COVID-era and emergency declarations may impose additional consumer protections

---

#### 5.2.2 Attorney Agreements: State Bar Rules

**Applicable to:** WCO-CA-001, WCO-ATTY-001, WCO-REF-001, WCO-IC-001

**Checklist:**
- [ ] Fee arrangement in writing (Model Rule 1.5, state equivalent)
- [ ] Fee splitting disclosed and consented (Model Rule 1.5(e))
- [ ] No referral fees without services (Model Rule 7.2(b))
- [ ] Conflicts check performed (Model Rule 1.7–1.9)
- [ ] Communication of scope (Model Rule 1.2)
- [ ] Trust account compliance (Model Rule 1.15)
- [ ] Termination rights (Model Rule 1.16)
- [ ] Advertising/solicitation compliance (Model Rule 7.1–7.5)
- [ ] Multijurisdictional practice (Model Rule 5.5)

**⚠️ ATTORNEY REVIEW REQUIRED (COMPREHENSIVE):**
- State bar rules vary significantly — template must include state-specific addenda
- Fee splitting with non-attorneys must be handled through structured means (not direct percentage)
- Attorney marketplace model must be vetted for UPL, fee splitting, and referral fee compliance
- Non-attorney document preparation must be carefully firewalled from legal advice

---

#### 5.2.3 Data Agreements: CCPA/CPRA

**Applicable to:** WCO-SAAS-001, WCO-PRIV-001, WCO-API-001, WCO-REF-001, WCO-DPA-001, WCO-VENDOR-001, WCO-LEAD-001, WCO-SKIP-001

**Checklist:**
- [ ] Notice at Collection provided (CCPA §1798.100(b))
- [ ] Right to Know disclosed (categories, specific pieces)
- [ ] Right to Delete disclosed (with exceptions)
- [ ] Right to Correct disclosed
- [ ] Right to Opt-Out of Sale/Share disclosed
- [ ] Right to Limit Use of Sensitive PI disclosed
- [ ] Non-discrimination for exercising rights
- [ ] Service provider contract terms (CCPA §1798.100(d))
- [ ] Data retention schedule

**⚠️ ATTORNEY REVIEW REQUIRED:**
- "Sale" and "Share" definitions under CPRA (broad — includes many common data practices)
- Service provider vs. contractor vs. third-party classification
- Contractors under CPRA have expanded obligations
- Sensitive PI definition and use limitations
- Automated decisionmaking disclosures (effective 2023+)

---

#### 5.2.4 Data Agreements: GDPR

**Applicable to:** WCO-SAAS-001, WCO-PRIV-001, WCO-API-001, WCO-REF-001, WCO-DPA-001, WCO-VENDOR-001

**Checklist:**
- [ ] Lawful basis for processing established (Art. 6)
- [ ] Consent (if relied upon) meets Art. 7 standard
- [ ] Privacy information provided per Art. 13/14
- [ ] Data subject rights procedures (Art. 15–22)
- [ ] DPA in place with all processors (Art. 28)
- [ ] International transfer mechanism (Art. 44–49)
- [ ] Data Protection Officer appointed (if required, Art. 37)
- [ ] Data breach notification procedures (Art. 33–34)
- [ ] Data Protection Impact Assessment completed (Art. 35)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Legitimate interest balancing test documentation
- International transfer mechanism (SCCs — validity post-Schrems II)
- Representative in EU/UK (Art. 27)
- Processor binding sub-processor obligations
- Data subject rights response timelines

---

#### 5.2.5 Financial Agreements: FCRA

**Applicable to:** WCO-SKIP-001

**Checklist:**
- [ ] Vendor certifies it is NOT a consumer reporting agency (CRA)
- [ ] Data is NOT used for credit, employment, insurance, or housing decisions
- [ ] Permissible purpose certified (15 U.S.C. §1681b)
- [ ] Data accuracy procedures documented
- [ ] No SSNs, account numbers, or consumer report data
- [ ] Identity verification procedures adequate
- [ ] Consumer dispute procedures (if any data could be construed as consumer report)

**⚠️ ATTORNEY REVIEW REQUIRED (COMPREHENSIVE):**
- FCRA civil liability (actual damages, punitive, attorney fees)
- Risk of being deemed a CRA (if data is used for eligibility decisions)
- State consumer reporting laws (may be more restrictive)
- Data broker registration laws (VT, CA, OR, TX, others)

---

#### 5.2.6 Marketing Agreements: TCPA

**Applicable to:** WCO-REF-001, WCO-LEAD-001

**Checklist:**
- [ ] Prior express written consent for autodialed/robocalls to cell phones (TCPA §227(b))
- [ ] Prior express consent for text messages
- [ ] Prior written consent for prerecorded calls to residential lines
- [ ] Do-Not-Call list scrubbing (company-specific + national DNC)
- [ ] Calling time restrictions (8am–9pm local time)
- [ ] Caller ID transmission (Truth in Caller ID Act)
- [ ] Opt-out mechanism (immediate, honored within 30 days)
- [ ] Lead source consent verification (vendor must document and warrant)
- [ ] Revocable consent tracking

**⚠️ ATTORNEY REVIEW REQUIRED:**
- TCPA strict liability (no scienter requirement)
- Lead generation consent (bifurcated consent requirements for multiple buyers)
- State-court TCPA interpretations (may differ from FCC)
- One-to-one consent rule (1:1 consent = one seller per consent)
- Revocation of consent — how tracked and honored

---

#### 5.2.7 Marketing Agreements: CAN-SPAM

**Applicable to:** WCO-REF-001, WCO-LEAD-001

**Checklist:**
- [ ] From line accurately identifies sender
- [ ] Subject line not deceptive
- [ ] Physical postal address included
- [ ] Unsubscribe mechanism clear and conspicuous
- [ ] Unsubscribe honored within 10 business days
- [ ] Commercial email clearly identified as advertisement (if applicable)
- [ ] Third-party sending compliance (vendor warrants)

**⚠️ ATTORNEY REVIEW RECOMMENDED:**
- CAN-SPAM preemption limits (some state anti-spam laws not preempted)
- Affirmative consent documentation requirements
- CAN-SPAM does not prohibit all unsolicited email (but better practice to have consent)

---

#### 5.2.8 FTC Cooling-Off Rule

**Applicable to:** WCO-CA-001, WCO-DOC-001

**Checklist:**
- [ ] Door-to-door sales disclosure (if applicable)
- [ ] Three-day cancellation right disclosed
- [ ] Notice of cancellation form provided
- [ ] In-home solicitation compliance (where applicable)
- [ ] Telemarketing sales rule compliance (if sold via phone)

**⚠️ ATTORNEY REVIEW REQUIRED:**
- Cooling-off rule applies to sales > $25 made at buyer's home or certain temporary locations
- Telemarketing sales rule requires written cancellation disclosure
- State-specific cooling-off periods (some states longer than 3 days)

---

#### 5.2.9 Unauthorized Practice of Law (UPL)

**Applicable to:** WCO-DOC-001, WCO-CA-001, WCO-ATTY-001

**Checklist:**
- [ ] No legal advice provided (document preparation only)
- [ ] No case evaluation or opinion
- [ ] No selection of legal forms on behalf of customer
- [ ] No representation in court or administrative proceedings
- [ ] No fee splitting with non-attorneys for legal services
- [ ] Customer directed to consult with attorney for legal advice
- [ ] Clear disclosure of non-attorney status
- [ ] State-specific UPL statutes reviewed

**⚠️ ATTORNEY REVIEW REQUIRED (COMPREHENSIVE):**
- UPL is state-law specific — what is permissible in one state may be UPL in another
- Document preparation services face increasing regulatory scrutiny
- AI-assisted document preparation raises novel UPL questions
- Fee structures must avoid appearance of legal fee splitting
- Court appearance representation requires licensed attorney

---

## 6. GOVERNANCE CALENDAR

### 6.1 Quarterly Activities (Every 90 Days)

| Activity | Owner | Due Date |
|----------|-------|----------|
| Review all Tier 1 templates for regulatory changes | ⚖️ Attorney | Q-end |
| Review all Tier 2 templates for regulatory changes | Compliance Officer | Q-end |
| Sample audit of 10% of active contracts (random) | Compliance Officer | Q-end |
| Update authorized signatory list | Compliance Officer + CEO | Q-end |
| Review and refresh risk scores (§2.6) | Compliance Officer | Q-end |
| Review pending approvals older than 30 days | Compliance Officer | Q-end |
| Update clause library with new case law/regs | ⚖️ Attorney | Q-end |
| Verify ⚖️ attorney engagement remains current | CEO | Q-end |

### 6.2 Monthly Activities

| Activity | Owner | Due Date |
|----------|-------|----------|
| Audit executed contracts for compliance issues | Compliance Officer | 15th |
| Review / close pending approvals over 14 days old | BU Leads | 20th |
| Obligation tracking check (upcoming deadlines) | Contract Admin | 25th |
| Renewal/expiration report review (90-day window) | BU Leads | 1st |
| New contract intake review | Compliance Officer | Weekly |

### 6.3 Weekly Activities

| Activity | Owner |
|----------|-------|
| Review new pending approvals | Compliance Officer |
| Monitor auto-renewal opt-outs | Contract Admin |
| Address any compliance flags from executed contracts | Compliance Officer |

### 6.4 Trigger-Based Activities

| Trigger | Action | Deadline | Owner |
|---------|--------|----------|-------|
| New federal/state privacy law | Update privacy policy + DPA + affected templates | 30 days | ⚖️ Attorney + Compliance |
| New state bar rule/opinion re: technology/marketplace | Update attorney + referral agreements | 30 days | ⚖️ Attorney |
| Data breach at Wheeler or vendor | Review vendor contracts, update security requirements | 7 days | InfoSec + Compliance |
| New business line or product launch | Create required templates (Tier 1 before launch) | Before launch | BU Lead + Compliance |
| Regulatory enforcement action (similar industry) | Review and assess impact on Wheeler templates | 14 days | ⚖️ Attorney |
| Counterparty insolvency | Review terminated-contract obligations, data return | 7 days | Compliance |
| Contract dispute or litigation | Preserve all related documents, initiate legal hold | Immediate | ⚖️ Attorney |

---

## 7. TECHNOLOGY REQUIREMENTS

### 7.1 Contract Repository

| Requirement | Specification | Priority |
|-------------|---------------|----------|
| Centralized storage | Single source of truth for all executed contracts | Critical |
| Full-text search | Search across all contracts and metadata | Critical |
| Access control | Role-based (see §2.5.3) | Critical |
| Version history | Immutable change log for all documents | Critical |
| Metadata extraction | Auto-extract parties, dates, value, key clauses | High |
| API access | REST API for integration with other systems | High |
| Bulk upload/download | ZIP export with metadata | Medium |
| Optical character recognition | Scanned documents searchable | Medium |
| Legal hold management | Flag documents subject to litigation hold | Medium |

**Recommended Options:**
- **Best-in-class**: Ironclad, DocuSign CLM, Icertis
- **Bootstrap**: Git-based (templates) + Google Drive/DocuSign (executed contracts) + Airtable (obligation tracking)
- **Open source**: Documenso (e-signature), Paperless-ngx (document management)

---

### 7.2 E-Signature Integration

| Requirement | Specification | Priority |
|-------------|---------------|----------|
| ESIGN Act compliant | Electronic Signatures in Global and National Commerce Act | Critical |
| EU eIDAS compliant | For EU counterparties | High |
| 2FA for signatories | SMS or authenticator app | High |
| Audit trail | IP, timestamp, browser, device fingerprint | Critical |
| Template library | Pre-built templates with merge fields | Critical |
| Bulk send | Multiple counterparties, same document | High |
| Reminders | Automated reminders for unsigned documents | Medium |
| In-person signing | Tablet/kiosk mode for physical locations | Medium |
| Wet signature tracking | Track physical signature location and date | Medium |

**Recommended Options:**
- **Primary**: DocuSign (enterprise, most court-tested)
- **Alternative**: HelloSign (simpler, lower cost)
- **Open Source**: Documenso (self-hosted option)

---

### 7.3 Version Control (Templates)

| Requirement | Specification | Priority |
|-------------|---------------|----------|
| Git-based storage | All templates in git repository | Critical |
| Branch protection | `main` requires PR + approvals per §2.2 | Critical |
| Signed commits | GPG or SSH key signing | Critical |
| Tags for releases | Semantic versioning per §2.1.3 | Critical |
| CI/CD for PDF generation | Template → PDF on merge to `main` | High |
| Diff tracking | Visual diff between versions | High |
| Changelog automation | Auto-generate from commit messages | Medium |

**Implementation:** Store in `/root/legal-compliance-os/templates/` with the structure in §2.1.2.

---

### 7.4 Approval Workflow Automation

| Requirement | Specification | Priority |
|-------------|---------------|----------|
| Sequential routing | L1 → L2 → L3 → L4 flow | Critical |
| Conditional routing | Skip levels based on risk score | Critical |
| Escalation | Reminder → manager → re-assign | High |
| SLA tracking | Time in each approval stage | High |
| Delegation | Temporary approval authority | Medium |
| Mobile approval | Approve from mobile device | Medium |
| Parallel routing | Multiple L1 reviewers simultaneously | Medium |

**Recommended Options:**
- **Integrated**: DocuSign CLM or Ironclad (combined contract + approval)
- **Standalone**: Jira Service Management, Asana, Monday.com
- **Lightweight**: Google Forms + Sheets + AppSheet

---

### 7.5 Obligation Tracking and Alerting

| Requirement | Specification | Priority |
|-------------|---------------|----------|
| Obligation registry | Each contract obligation as a tracked item | Critical |
| Auto-population | Extract obligations from executed contracts | High |
| Renewal alerts | 90/60/45/30 day alerts | Critical |
| Expiration alerts | 60/30 day alerts | Critical |
| Compliance deadline alerts | Per contract obligations | High |
| Dashboard | At-a-glance compliance status | High |
| Report export | CSV/PDF for compliance reporting | Medium |

**Implementation (bootstrap):**
```
Obligation tracking spreadsheet:
- Contract ID
- Obligation type (payment, report, renewal, compliance, data)
- Owner
- Due date
- Status (pending, in-progress, completed, overdue)
- Notes
- Document link
```

---

### 7.6 Audit Log (Immutable)

| Requirement | Specification | Priority |
|-------------|---------------|----------|
| Append-only | No deletion or modification of audit events | Critical |
| Timestamped | NTP-synchronized, ISO 8601 UTC | Critical |
| Actor identification | User ID + IP address | Critical |
| Event types | Create, read, update, delete, approve, reject, execute | Critical |
| Searchable | Full-text search on audit events | High |
| Exportable | JSON/CSV export | Medium |
| Retention | 7 years minimum | Critical |
| Alerting | Anomaly detection on audit events | Medium |

**Implementation Options:**
- **Cloud-native**: AWS CloudTrail, Azure Monitor, GCP Audit Logs
- **Database**: PostgreSQL with append-only table (trigger-based, no update grants)
- **Blockchain-based**: Amazon QLDB or similar immutable ledger

---

### 7.7 Technology Architecture (Recommended)

```
┌────────────────────────────────────────────────────────────────────┐
│                        TECHNOLOGY ARCHITECTURE                      │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐ │
│  │  TEMPLATE REPO  │    │  CONTRACT REPO   │    │  OBLIGATION      │ │
│  │  (Git + CI/CD)  │    │  (DocuSign CLM   │    │  TRACKER         │ │
│  │                 │    │   or Ironclad)   │    │  (Airtable/      │ │
│  │  Templates      │    │                  │    │   API-based)     │ │
│  │  Clause Library │    │  Executed        │    │                  │ │
│  │  Governance     │    │  Contracts       │    │  Renewal Alerts  │ │
│  │  Documents      │    │  Audit Log       │    │  Compliance      │ │
│  └────────┬────────┘    └────────┬─────────┘    └────────┬─────────┘ │
│           │                     │                        │          │
│           └──────────┬──────────┴────────────┐            │          │
│                      │                       │            │          │
│              ┌───────▼───────┐        ┌──────▼──────┐               │
│              │   APPROVAL    │        │  E-SIGNATURE │               │
│              │   WORKFLOW    │        │  (DocuSign/  │               │
│              │   (Automated) │        │   HelloSign) │               │
│              └───────────────┘        └─────────────┘               │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    INTEGRATION LAYER                          │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐ │   │
│  │  │ Slack    │  │ Email    │  │ Calendar │  │ Accounting   │ │   │
│  │  │ (Alerts) │  │ (Notifs) │  │ (Renewals)│ │ (Invoicing)  │ │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────────┘ │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 8. APPENDICES

### Appendix A: Glossary

| Term | Definition |
|------|------------|
| Agreement | A binding legal document between two or more parties |
| Amendment | A formal change to an existing agreement |
| BU | Business Unit — one of the 10 Wheeler operating units |
| Clause Library | Standardized legal provisions maintained for reuse |
| Counterpart | A duplicate original of a signed agreement |
| DPA | Data Processing Agreement — satisfies GDPR Art. 28 |
| DPO | Data Protection Officer |
| FCRA | Fair Credit Reporting Act |
| MSA | Master Services Agreement |
| OFAC | Office of Foreign Assets Control (sanctions screening) |
| Redline | Tracked changes showing modifications to a document |
| SOW | Statement of Work — defines specific services under an MSA |
| TCPA | Telephone Consumer Protection Act |
| UDAAP | Unfair, Deceptive, or Abusive Acts or Practices |
| UPL | Unauthorized Practice of Law |
| WCO | Wheeler Contract Organization (document prefix) |

---

### Appendix B: Template Status Tracker

| Template ID | Status | Current Version | Last Reviewed | Next Review | ⚖️ Attorney | 
|-------------|--------|----------------|---------------|-------------|-------------|
| WCO-CA-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-ATTY-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-SAAS-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-PRIV-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-API-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-REF-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-DPA-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-IC-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-NDA-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-VENDOR-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-LEAD-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-SKIP-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |
| WCO-DOC-001 | 🔴 DRAFT | v0.0.1 | — | — | Not engaged |

---

### Appendix C: Change Log

| Date | Version | Author | Change Description | Approval |
|------|---------|--------|--------------------|----------|
| 2026-05-25 | v1.0.0 | CONTRACT SYSTEMS ENGINEER | Initial governance framework creation | N/A — initial draft |

---

### Appendix D: Related Documents

| Document ID | Title | Location |
|-------------|-------|----------|
| WCO-GOV-001-APPROVAL-MATRIX | Signature Authority Thresholds | `/root/legal-compliance-os/governance/WCO-GOV-001_APPROVAL-MATRIX.md` |
| WCO-GOV-001-COMPLIANCE-CALENDAR | Annual Compliance Calendar | `/root/legal-compliance-os/governance/WCO-GOV-001_COMPLIANCE-CALENDAR.md` |
| WCO-GOV-001 | This Document | `/root/legal-compliance-os/CONTRACT_GOVERNANCE_SYSTEM.md` |
| [Template Files] | Per-template documents | `/root/legal-compliance-os/templates/tier{1-3}/*/` |
| [Clause Library] | Standardized clauses | `/root/legal-compliance-os/clause-library/*.md` |
| [Master Changelog] | Repository-wide changes | `/root/legal-compliance-os/changelog/WCO-MASTER-CHANGELOG.md` |

---

> **END OF DOCUMENT WCO-GOV-001-v1.0.0**
>
> This framework is a governance tool, not legal advice. All ⚖️-flagged sections must be reviewed by a licensed attorney before operational use. The Wheeler Ecosystem Contract Governance System shall be reviewed quarterly and updated as regulations, business needs, and case law evolve.
