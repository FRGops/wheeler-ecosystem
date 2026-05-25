# ATTORNEY MARKETPLACE COMPLIANCE FRAMEWORK
## Wheeler Ecosystem — Phase 6 Deliverable

**Document ID:** WHEELER-ATTORNEY-MARKETPLACE-CMP-001  
**Classification:** CONFIDENTIAL — ATTORNEY-CLIENT PRIVILEGED  
**Date:** 2026-05-25  
**Author:** Wheeler AI Ops — Attorney Marketplace Compliance Architecture Division  
**Status:** PHASE 6 — COMPLIANCE FRAMEWORK  
**Version:** 1.0  

---

## DISCLAIMER — CRITICAL ⚠️

**THIS DOCUMENT IS NOT LEGAL ADVICE. IT DOES NOT CREATE AN ATTORNEY-CLIENT RELATIONSHIP.** This framework identifies compliance requirements, risks, and recommended structures for an attorney marketplace platform. Every section marked with ⚖️ ATTORNEY REVIEW REQUIRED must be reviewed and approved by qualified licensed counsel in each relevant jurisdiction before implementation. State bar rules vary significantly, are subject to change, and carry severe penalties (including criminal charges) for violations. This document provides a compliance architecture framework for discussion with legal counsel — it is not a substitute for independent legal advice.

---

## TABLE OF CONTENTS

1. [REGULATORY FRAMEWORK](#1-regulatory-framework)
2. [BUSINESS MODEL STRUCTURING](#2-business-model-structuring)
3. [ATTORNEY VETTING & ONBOARDING](#3-attorney-vetting--onboarding)
4. [REFERRAL COMPLIANCE](#4-referral-compliance)
5. [CAPACITY ROUTING & PERFORMANCE](#5-capacity-routing--performance)
6. [CLIENT-ATTORNEY RELATIONSHIP GOVERNANCE](#6-client-attorney-relationship-governance)
7. [CONFLICT CHECKS & ETHICS WALLS](#7-conflict-checks--ethics-walls)
8. [MULTI-STATE OPERATIONS](#8-multi-state-operations)
9. [COMPLIANCE OPERATIONS](#9-compliance-operations)
10. [RISK MITIGATION TABLE](#10-risk-mitigation-table)
11. [IMPLEMENTATION ROADMAP](#11-implementation-roadmap)
12. [APPENDICES](#12-appendices)

---

## 1. REGULATORY FRAMEWORK

### 1.1 ABA Model Rules (Foundation)

The American Bar Association's Model Rules of Professional Conduct form the foundation of attorney regulation in 49 states (California being the sole exception, with its own Rules of Professional Conduct). Every state adopts the Model Rules with variations. The following rules are directly implicated by an attorney marketplace platform:

#### Rule 5.4: Professional Independence of a Lawyer — FEE SPLITTING PROHIBITION

| Element | Rule Text | Marketplace Implication |
|---------|-----------|------------------------|
| 5.4(a) | Lawyer shall not share legal fees with a non-lawyer | **Wheeler cannot receive a percentage of attorney fees.** This is the single most critical prohibition. Any fee arrangement where Wheeler's compensation is tied to the legal fee charged to the client risks violation. |
| 5.4(b) | Lawyer shall not form a partnership with a non-lawyer if any part of the work is the practice of law | Wheeler cannot hold itself out as a partner or joint venture with attorneys for legal services. |
| 5.4(c) | Lawyer shall not permit a non-lawyer to direct or regulate the lawyer's professional judgment | Wheeler cannot direct attorney strategy, case handling, or settlement decisions. |
| 5.4(d)(1)-(3) | Exceptions: death benefits, retirement plans, law firm compensation plans | Not applicable to marketplace business model — these exceptions cover law firm internal arrangements. |

**PERMISSIBLE EXCEPTIONS (limited):**
- **Rule 5.4(a)(4): Court-approved fee awards** — If a court orders fees to be paid to a non-lawyer, that is permissible. Not relevant to marketplace model.
- **Rule 5.4(a)(5): Non-lawyer employees of law firm** — Bonuses based on firm profitability are allowed. Wheeler is not a law firm employee.

**⚠️ THE CORE COMPLIANCE CHALLENGE:**
ABA Formal Opinion 94-388 (and multiple state opinions) hold that referral services, lead generation platforms, and lawyer directories that charge on a per-case or percentage basis likely violate Rule 5.4. The fee must be:
1. A fixed fee for services rendered, NOT contingent on outcome; OR
2. A flat periodic fee (subscription model); OR
3. Paid by the client (claimant) directly, not from attorney fees; OR
4. An approved cost per lead (with proper disclosure).

> **⚖️ ATTORNEY REVIEW REQUIRED:** The specific fee structure must be evaluated under each state's interpretation of Rule 5.4. Some states (New York, Florida, California) have stricter interpretations. An ethics opinion from qualified counsel in each operating state is strongly recommended before launch.

---

#### Rule 5.5: Unauthorized Practice of Law; Multijurisdictional Practice

| Element | Rule Text | Marketplace Implication |
|---------|-----------|------------------------|
| 5.5(a) | Lawyer shall not practice law in a jurisdiction where not licensed | Attorneys on the platform must be licensed in the state where the surplus funds are held (court jurisdiction). |
| 5.5(b) | Lawyer shall not establish an office or regular presence in a jurisdiction where not licensed | Remote practice is permissible under certain conditions; regular physical presence is not. |
| 5.5(c)-(d) | Safe harbors for temporary practice (co-counsel with local lawyer, arbitration, mediation, pro hac vice) | Attorneys can appear pro hac vice in some states, but this requires local counsel and court approval. |

**Wheeler's UPL Risk: The marketplace itself must not engage in UPL.**
- Wheeler provides matching/connection services — generally not UPL
- Wheeler provides administrative support — generally not UPL
- Wheeler provides AI-generated legal analysis — **POTENTIALLY UPL** without attorney supervision
- Wheeler drafts legal documents — **UPL** without attorney supervision

> **⚖️ ATTORNEY REVIEW REQUIRED:** Each state defines UPL differently. Some states (Virginia, North Carolina, New York) have broad definitions that could encompass AI-driven legal content generation. A state-by-state UPL analysis is required.

---

#### Rule 7.1: Communications Concerning a Lawyer's Services

| Requirement | Application |
|-------------|-------------|
| Communications must be truthful and not misleading | All Wheeler marketing materials, attorney profiles, and platform communications must be factual and not create false expectations. |
| No false or misleading statements about lawyer's services | Attorney profiles must be verified for accuracy. Objective claims (years of practice, bar admission, case counts) are preferred. |
| Material omissions are prohibited | Cannot omit information that would make the communication misleading overall. |

**Platform Implications:**
- Attorney profiles must be factually accurate and verified
- Settlement/outcome data must be presented with proper context and disclaimers
- Client testimonials are subject to Rule 7.1 and state-specific restrictions (some states restrict or prohibit testimonials entirely)

> **⚖️ ATTORNEY REVIEW REQUIRED:** Each state's specific implementation of Rule 7.1 varies. Florida, New York, and Texas have particularly detailed advertising regulations that must be addressed individually.

---

#### Rule 7.2: Advertising

| Element | Rule Text | Marketplace Implication |
|---------|-----------|------------------------|
| 7.2(a) | Subject to Rules 7.1 and 7.3, lawyers may advertise services through written, recorded, or electronic communication | Wheeler attorney profiles and listings **are advertising** of the attorney's services. |
| 7.2(b) | Lawyer shall not give anything of value to a person for recommending the lawyer's services | **CRITICAL:** This is the "no referral fees" rule. Wheeler cannot charge for "recommending" or "referring" a specific attorney. |
| 7.2(b)(1) | Exception: lawyer may pay the reasonable cost of advertisements or communications | **THE KEY EXCEPTION:** Wheeler can charge attorneys for advertising services. The fee must be for the **advertising itself** (listing on the platform), not for the result (a signed client). |
| 7.2(b)(2) | Exception: lawyer may pay the usual charges of a qualified legal referral service | **Varies by state.** Many states have specific requirements for "qualified" referral services, including non-profit status, random rotation, or bar association affiliation. |
| 7.2(b)(3)-(5) | Other exceptions: pro bono matching, bar association dues, networking | Not generally applicable to commercial marketplace. |
| 7.2(c) | Lawyer must retain copy of advertisement for 2 years after dissemination | Wheeler must support attorney compliance with records retention for all marketing materials. |

**THE CRITICAL DISTINCTION:**

| Arrangement | ABA Rule Status | Risk Level |
|-------------|-----------------|------------|
| Attorney pays Wheeler flat monthly fee for directory listing | Permissible under 7.2(b)(1) | LOW — established model |
| Attorney pays Wheeler per-lead fee | Permissible under 7.2(b)(1) if structured properly | MODERATE — must not be per-referral |
| Attorney pays Wheeler percentage of fees | Likely violates 5.4(a) AND 7.2(b) | CRITICAL — DO NOT IMPLEMENT |
| Claimant pays Wheeler finder's fee | Not covered by Model Rules (not attorney regulation); governed by consumer protection laws | MODERATE — state consumer law analysis required |

> **⚖️ ATTORNEY REVIEW REQUIRED:** The line between "paying for advertising" (permitted) and "paying for a recommendation" (prohibited) is fact-specific and state-dependent. Written ethics opinions should be obtained.

---

#### Rule 7.3: Solicitation of Clients

| Element | Prohibition | Marketplace Implication |
|---------|-------------|------------------------|
| 7.3(a) | "Targeted" communication directed to a specific person known to need legal services concerning that matter | If Wheeler identifies a specific claimant with surplus funds and contacts them to offer attorney matching, this is a **solicitation** under the rule. |
| 7.3(b) | In-person, live telephone, or real-time electronic contact for solicitation | Automated outbound calls, robocalls, text messaging campaigns likely violate this rule even if they only "offer" to connect with an attorney. |
| 7.3(c) | Written solicitation must include "Advertising Material" label | All written communications to claimants must be clearly labeled. |
| 7.3(d) | 30-day ban on soliciting accident victims | Not directly applicable to surplus funds, but important for any broader legal marketplace expansion. |
| 7.3(e) | Filings with state authorities required in some states | Some states require copies of solicitation materials to be filed with the bar. |

**⚠️ SOLICITATION IS THE SECOND HIGHEST RISK AREA after fee-splitting.**
- Claimant outreach must be structured as **informational** about their surplus funds, not as solicitation of legal services
- Wheeler should frame communications as "notice of available funds" (which is factual and non-legal) rather than "we can connect you with a lawyer"
- ⚖️ ATTORNEY REVIEW REQUIRED for ALL claimant outreach scripts, templates, and workflows

---

#### Rule 7.4: Communication of Fields of Practice

| Requirement | Application |
|-------------|-------------|
| Lawyer may communicate areas of practice | Subject to truthfulness requirements |
| "Specialist" claims require certification | Unless state has specialization certification program and attorney is certified |
| Patent and admiralty practice have specific rules | Not applicable to surplus funds practice |

**Platform Implication:** Wheeler must verify that attorneys' stated practice areas are accurate and not misleading. "Specialist" or "expert" designations require state bar certification verification.

---

#### Rule 1.5: Fees

| Element | Requirement | Marketplace Implication |
|---------|-------------|------------------------|
| 1.5(a) | Fee must be reasonable | Platform should not encourage or facilitate unreasonable fees. Attorney fee arrangements must be independently reviewed. |
| 1.5(b) | Scope of representation and fee basis must be communicated in writing | Wheeler must ensure written fee agreements are in place between attorney and client. |
| 1.5(c) | Contingent fee agreement must be in writing, signed by client, state method of calculation | If attorneys use contingent fees, Wheeler must support compliant documentation. |
| 1.5(d) | Prohibited contingent fees: domestic relations, criminal cases | Not applicable to surplus funds recovery, but important for any practice area expansion. |

**Platform Fee Disclosure Requirements:**
- Wheeler's fees must be disclosed separately from attorney fees
- Client (claimant) must understand how Wheeler is compensated
- If Wheeler is paid from the recovery (assignment model), the amount must be clearly stated in a separate, signed agreement

> **⚖️ ATTORNEY REVIEW REQUIRED:** Fee reasonableness is a fact-intensive inquiry. Wheeler should not set or influence attorney fee amounts. Fee arrangements are solely between attorney and client.

---

#### Rules 1.7-1.11: Conflicts of Interest

| Rule | Scope | Marketplace Implication |
|------|-------|------------------------|
| 1.7 | Concurrent conflicts (directly adverse or material limitation) | Wheeler must facilitate conflict checks before routing to an attorney. |
| 1.8 | Specific conflicts (business transactions with client, etc.) | Wheeler's agreements with claimants must avoid creating conflicts for attorneys. |
| 1.9 | Duties to former clients | Attorneys must screen for former client conflicts. |
| 1.10 | Imputed conflicts (entire firm) | If one attorney in a firm has a conflict, the whole firm is conflicted. |
| 1.11 | Special conflicts for former government lawyers | Applicable if platform includes former government attorneys. |

**Platform Role:** Wheeler should facilitate but NOT perform conflict checks. The conflict check is a legal determination that requires attorney judgment. Wheeler can:
- Collect conflict information from claimants (names of adverse parties, co-owners)
- Provide structured conflict check forms
- Transmit information to attorneys for their independent conflict analysis
- Maintain a basic "obvious conflict" database (attorneys who have previously represented an adverse party on the same matter)

> **⚖️ ATTORNEY REVIEW REQUIRED:** The extent of Wheeler's role in conflict checking must be evaluated. Performing too much of the analysis could constitute UPL. Performing too little creates malpractice risk.

---

#### Rule 1.6: Confidentiality of Information

| Element | Requirement | Marketplace Implication |
|---------|-------------|------------------------|
| 1.6(a) | Lawyer shall not reveal information relating to representation of a client unless client gives informed consent | Claimant information shared with an attorney becomes subject to Rule 1.6 once the attorney-client relationship is formed. |
| 1.6(b)-(c) | Exceptions: prevent death/bodily harm, comply with court order, resolve ethics complaints | Limited exceptions do not include commercial purposes. |
| 1.6, Comment 3 | The confidentiality obligation applies broadly — includes all information relating to representation | Wheeler's access to client information must be limited and contractually controlled. |

**Platform Security Requirements:**
- Wheeler data systems that handle claimant information shared with attorneys must maintain attorney-client privilege protections
- Data segmentation: separate pre-engagement information (not privileged) from post-engagement information (privileged)
- Access controls: Wheeler personnel should not have access to attorney-client privileged communications without express authorization
- Written agreements must establish Wheeler's role as a technology vendor/administrative support provider, not as a party to privileged communications

> **⚖️ ATTORNEY REVIEW REQUIRED:** Data sharing agreements between Wheeler and attorneys must address confidentiality obligations, privilege protection, and data breach notification.

---

#### Rule 1.15: Safekeeping Property (Trust Accounting / IOLTA)

| Element | Requirement | Marketplace Implication |
|---------|-------------|------------------------|
| 1.15(a) | Client and third-party funds must be held in trust accounts separate from lawyer's own property | Wheeler must NOT comingle client funds with operating funds. |
| 1.15(b) | Lawyer must promptly notify client of receipt of funds | Wheeler's systems should support this notification, not supplant it. |
| 1.15(c) | Disputed funds must be kept separate until resolution | Disbursement holds must be supported by platform. |
| 1.15(d) | Trust accounts must be maintained in compliance with state rules | IOLTA requirements vary by state. |

**BRIGHT LINE RULES:**
- **Wheeler NEVER handles client trust funds.** All settlement proceeds, fee payments, and disbursements flow through attorney IOLTA accounts.
- Wheeler's fee is paid by the attorney (from the attorney's operating account) or by the claimant directly — never from IOLTA.
- Platform should never ask for or store IOLTA account credentials.

> **⚖️ ATTORNEY REVIEW REQUIRED:** Payment flows must be structured to avoid Wheeler ever having custody of client funds, which could trigger money transmitter licensing requirements.

---

### 1.2 UNAUTHORIZED PRACTICE OF LAW (UPL) — THE EXISTENTIAL RISK

UPL is a criminal offense in most states (typically a misdemeanor, felony in some cases for repeated violations). It is the single highest-risk area for Wheeler's marketplace operations.

#### What Constitutes UPL

| Activity | UPL Status | Wheeler Implication |
|----------|------------|---------------------|
| Giving legal advice | DEFINITIVE UPL | Wheeler cannot advise claimants on legal rights, claim validity, or strategy |
| Drafting legal documents without attorney supervision | DEFINITIVE UPL | All documents drafted by AI or staff must be reviewed and signed by licensed attorney |
| Selecting legal forms or strategies | LIKELY UPL | Wheeler cannot recommend specific legal documents or strategies |
| Representing another in court | DEFINITIVE UPL | Wheeler personnel cannot appear in court |
| Holding oneself out as authorized to practice law | DEFINITIVE UPL | All communications must clearly state Wheeler is not a law firm |
| Conducting legal research and analysis | LIKELY UPL | AI-driven legal analysis requires attorney review |
| Negotiating legal claims | DEFINITIVE UPL | Wheeler cannot negotiate with claimants, courts, or adverse parties |
| Interpreting statutes or case law for a specific claimant | LIKELY UPL | Fact-specific legal interpretation requires attorney review |
| Providing factual information about surplus funds | GENERALLY NOT UPL | Educational content, general explanations are permissible |
| Connecting claimants with attorneys | GENERALLY NOT UPL | Matching services are not legal practice |
| Providing administrative/clerical support to attorneys | GENERALLY NOT UPL | Document organization, calendar management, data entry |
| Marketing attorney services | GENERALLY NOT UPL | Subject to advertising rules (Rules 7.1-7.4), not UPL rules |

#### The AI UPL Risk — SPECIFIC AND EXTREME

AI-generated content in a legal context creates novel UPL risks:

| AI Activity | UPL Risk | Required Safeguard |
|-------------|----------|-------------------|
| AI generates form documents | HIGH | Attorney must review and approve each document before delivery to claimant |
| AI explains legal concepts to claimant | HIGH | Attorney supervision required; all AI outputs must be reviewed |
| AI analyzes claim value | EXTREME | Attorney must independently evaluate and accept/reject AI analysis |
| AI drafts demand letters | HIGH | Attorney review; attorney signature |
| AI summarizes case law | EXTREME | Attorney must verify all citations and legal conclusions |
| AI generates attorney marketing copy | MODERATE | Subject to advertising rules; attorney approval required |
| AI matches claimants to attorneys | LOW-MODERATE | Objective criteria only; no legal judgment involved |

> **⚖️ ATTORNEY REVIEW REQUIRED:** A state-specific UPL analysis for AI-driven marketplace operations must be obtained. Several states (NY, CA, IL, FL) have active discussions about AI and UPL. The ABA's 2024 AI Task Force recommendations should be reviewed.

#### BRIGHT LINE RULES FOR WHEELER AI OPERATIONS

1. **NO AI CONTENT GENERATED FOR CLAIMANTS** without prior attorney review and approval
2. **NO AI LEGAL ANALYSIS** delivered directly to claimants
3. **NO AI-DRIVEN CLAIM EVALUATION** used in claimant-facing communications
4. **ALL AI OUTPUTS** labeled "PREPARED WITH AI ASSISTANCE — REVIEWED BY [ATTORNEY NAME]"
5. **AI MATCHING ALGORITHMS** use objective criteria (state, practice area, capacity) only — no legal judgment
6. **COMPLETE AUDIT TRAIL** of all AI outputs and attorney review actions
7. **ATTORNEY-IN-THE-LOOP** requirement: every document, communication, or analysis delivered to a claimant must have a named, licensed attorney who has reviewed and approved it

---

### 1.3 State Variations

Each state adopts the ABA Model Rules with modifications. The following table provides a high-level summary of key variations by state. Detailed state profiles are maintained in `/root/legal-compliance-os/STATE_COMPLIANCE_MATRIX.md`.

#### Critical State Regulatory Profiles

| State | Model Basis | Fee-Splitting (5.4) | Advertising (7.1-7.3) | UPL Definition | Referral Services | ⚖️ |
|-------|-------------|---------------------|----------------------|----------------|-------------------|-----|
| **California** | Non-Model (CA Rules) | STRICTEST: CA Rule 1.5-1.6 extremely restrictive; non-lawyer fee sharing virtually prohibited | Must file all ads with CA Bar within 5 days of dissemination | Very broad; AI-generated content likely UPL | Must be CA Bar certified or non-profit | ⚖️ |
| **New York** | NY Model Rules | DR 1-107 allows non-lawyer fee sharing if written and client consents (unique exception) | 22 NYCRR 1200.8 — strict; all ads filed with Attorney General | Broad; NY has prosecuted internet-based UPL | NY Jud. Law Section 495 — restrictions on lawyer referral services | ⚖️ |
| **Florida** | Florida Model Rules | 4-5.4: Strict; no fee sharing with non-lawyers | 4-7.1: Very aggressive enforcement; mandatory pre-approval for ads | Florida Bar very active on UPL enforcement | Florida Bar Certification required for referral services | ⚖️ |
| **Texas** | TX Model Rules | 5.04: Prohibited with very narrow exceptions | 7.01-7.07: Required filing with State Bar | Moderate | Texas has specific rules for lawyer referral services | ⚖️ |
| **Illinois** | IL Model Rules | 5.4: Standard Model Rule prohibition | 7.1-7.3: Model-based with IL modifications | Moderate | ARDC oversees referral services | ⚖️ |
| **Ohio** | OH Model Rules | 5.4: Standard prohibition | 7.1-7.3: Model-based | Moderate | Ohio has specific referral service rules | ⚖️ |
| **Pennsylvania** | PA Model Rules | 5.4: Standard prohibition | 7.1-7.3: Model-based | Broad definition | Specific rules for for-profit referral services | ⚖️ |
| **Georgia** | GA Model Rules | 5.4: Standard prohibition | 7.1-7.3: Model-based | Narrower definition | State Bar regulates referral services | ⚖️ |
| **Michigan** | MI Model Rules (modified) | 5.4: Standard prohibition | 7.1-7.3: Model-based with MI modifications | Moderate | Michigan has unique referral service rules | ⚖️ |
| **New Jersey** | NJ Model Rules | 5.4: Standard prohibition | 7.1-7.3: Model-based | Strict UPL enforcement | NJ rules on referral services | ⚖️ |

> **⚖️ ATTORNEY REVIEW REQUIRED:** The above is a summary only. A comprehensive state-by-state analysis is maintained in `/root/legal-compliance-os/STATE_COMPLIANCE_MATRIX.md` and must be reviewed by in-state counsel for each jurisdiction where Wheeler operates.

---

## 2. BUSINESS MODEL STRUCTURING

### 2.1 The Fee Structure Problem

ABA Model Rule 5.4 prohibits sharing legal fees with non-lawyers. The Wheeler marketplace requires a revenue model that complies with this prohibition while remaining economically viable.

#### Option Analysis

| Option | Description | Fee Flow | Rule 5.4 Risk | Other Risks | Recommended? |
|--------|-------------|----------|---------------|-------------|--------------|
| **A: Marketing/Advertising** | Flat monthly or periodic fee for attorney directory listing | Attorney → Wheeler (fixed fee) | LOW — per Rule 7.2(b)(1) | Low — well-established model | YES — Foundation |
| **B: Administrative Services** | Per-case administrative fee for case management platform, document management, scheduling | Attorney → Wheeler (per-case fee, fixed amount) | LOW — fee is for services, not outcome-based | Low — legal tech/support model | YES — Foundation |
| **C: Per-Lead Fee** | Attorney pays per qualified lead (contact information of potential client) | Attorney → Wheeler (per-contact fee) | MODERATE — must be structured as advertising cost, not referral fee | Risk: regulator may view as disguised recommendation | YES — With safeguards |
| **D: Outcome-Based Fee** | Attorney pays percentage of legal fee or recovery | Attorney → Wheeler or directly from recovery | CRITICAL — likely per se violation of 5.4(a) | High — UPL, money transmitter, state bar discipline | NOT RECOMMENDED |
| **E: Claimant Assignment** | Claimant assigns percentage of recovery to Wheeler | Claimant → Wheeler (from recovery, outside attorney fee) | MODERATE — does not involve attorney sharing fees | High — state assignment laws, consumer protection, unconscionability | CONDITIONAL — Where state permits |
| **F: Hybrid** | Combination of above | Varies | VARIES per component | Each component must be independently compliant | CONDITIONAL — Requires comprehensive review |

#### RECOMMENDED STRUCTURE: Option A + B Foundation (Marketing + Administrative Services)

**Phase 1 — Core Model:**
1. **Attorney Subscription Fee (Option A):** Attorneys pay a fixed monthly or annual fee for a verified directory listing on the Wheeler Attorney Marketplace
2. **Platform Access Fee (Option B):** Attorneys pay a fixed per-case fee for access to Wheeler's case management, document automation, and deadline tracking platform

**Phase 2 — Enhanced Model (where state law permits):**
3. **Qualified Lead Fee (Option C):** Attorneys pay a fixed fee per qualified lead, with transparency about the fee structure to both attorneys and claimants. Fee must be the same regardless of whether the lead converts to a client.

**Phase 3 — Assignment Model (where state law permits):**
4. **Claimant Assignment (Option E):** Claimant voluntarily assigns a portion of their surplus recovery to Wheeler under a separate assignment agreement. Attorney does not share fees with Wheeler.

> **⚖️ ATTORNEY REVIEW REQUIRED:** The recommended structure must be reviewed by counsel in each state of operation. Some states may prohibit one or more of the recommended options. An ethics opinion should be obtained for the Phase 1 structure before launch.

### 2.2 Revenue Recognition & Payment Flow

#### How Wheeler Gets Paid

| Fee Type | Payer | Amount | Timing | Trust Accounting Issue? |
|----------|-------|--------|--------|------------------------|
| Attorney subscription fee | Attorney | Fixed monthly/annual | Upfront, recurring | No — attorney operating account |
| Platform access fee | Attorney | Fixed per-case | At case opening or monthly | No — attorney operating account |
| Qualified lead fee | Attorney | Fixed per-lead | At time of lead delivery | No — attorney operating account |
| Claimant assignment fee | Claimant | Percentage of recovery | At disbursement from settlement | YES — must be separately contracted |

#### CRITICAL PAYMENT RULES

1. **NEVER handle IOLTA funds.** Wheeler must never receive funds directly from an attorney's trust account.
2. **NEVER take fees from settlement proceeds** without a separate, signed assignment agreement from the claimant.
3. **NEVER accept a percentage-based fee from an attorney** for any service.
4. **ALWAYS document the specific service provided** for each fee charged (not "attorney referral" but "platform access" or "lead generation").
5. **ALWAYS maintain separate accounting** for Wheeler fees vs. attorney fees vs. claimant recovery.
6. **ALWAYS disclose to claimant** how Wheeler is compensated, in plain language, before the claimant engages an attorney.

#### Trust Accounting and Money Transmission

| Scenario | Money Transmitter Licensing Required? | Trust Accounting Impact |
|----------|---------------------------------------|------------------------|
| Wheeler collects attorney subscription fee | NO — not handling client funds | Not trust funds |
| Wheeler collects platform access fee from attorney | NO — not handling client funds | Not trust funds |
| Wheeler collects lead fee from attorney | NO — not handling client funds | Not trust funds |
| Wheeler receives portion of settlement for disbursement to others | YES — likely money transmission | High — IOLTA implication |
| Wheeler receives assignment fee directly from claimant | DEPENDS — varies by state if one-time vs. regular transmission | Should go through attorney's IOLTA for disbursement |
| Wheeler handles funds belonging to claimants or adverse parties | YES — almost certainly money transmission | Must never happen |

> **⚖️ ATTORNEY REVIEW REQUIRED:** Money transmitter licensing analysis for each state where Wheeler operates. The safest approach: Wheeler's fee is always paid by the attorney from the attorney's operating account. Assignment fees are paid by claimant via check or ACH directly to Wheeler (not through IOLTA).

---

### 2.3 Consumer Protection & Disclosure Requirements

| Disclosure | Required By | Content | Format |
|------------|-------------|---------|--------|
| Non-Attorney Status | All states, FTC | "Wheeler is not a law firm. We do not provide legal services or legal advice." | Clear, conspicuous, on all platforms and communications |
| No Endorsement | ABA Rule 7.2, state equivalents | "Wheeler does not recommend or endorse any specific attorney. Claimants have the right to choose their own attorney." | Written disclosure before attorney matching |
| Fee Disclosure | FTC, state consumer protection | "Wheeler receives compensation from participating attorneys for [specific service]. This may affect which attorneys are listed." | Written disclosure before engagement |
| No Guarantee | FTC, state consumer protection | "Results vary. Wheeler does not guarantee any outcome in any case." | Written disclosure on all marketing materials |
| Claimant Rights | State surplus fund laws | "You have the right to pursue your surplus funds claim without using an attorney or this marketplace." | Written disclosure at first contact |

---

## 3. ATTORNEY VETTING & ONBOARDING

### 3.1 Licensing Verification

Every attorney on the platform must be verified for active, good-standing licensure in every jurisdiction where they accept cases.

#### Verification Requirements

| Credential | Verification Method | Frequency | Responsible Party |
|------------|-------------------|-----------|------------------|
| State Bar Admission | NCBE / State Bar API direct verification | Initial + Quarterly | Wheeler Compliance |
| Good Standing | State Bar API / Certificate of Good Standing | Initial + Quarterly | Wheeler Compliance |
| No Disciplinary History | State Bar public discipline database | Initial + Quarterly | Wheeler Compliance |
| Malpractice Insurance | Certificate of Insurance from carrier | Initial + Annual | Wheeler Compliance |
| Practice Area Competency | Self-certification + case history review | Initial | Wheeler Compliance + Attorney |
| Federal Court Admission (if applicable) | PACER / individual district court verification | Initial | Wheeler Compliance |
| Pro Hac Vice History | Court records in relevant states | Per-case | Attorney Self-Certify + Wheeler Verify |

#### Automated Verification Systems

**Minimum Technical Requirements:**
- Integration with NCBE (National Conference of Bar Examiners) API for multi-state license verification
- State bar API integrations for real-time status checks (priority: high-volume states first)
- Automated disciplinary alert system (LEXIS Nexis, state bar RSS feeds, or equivalent)
- Automated renewal reminders (90/60/30 days before license expiration)
- Escalation workflow for verification failures

**Bar API Coverage:**

| State | API Available | Automated Verification? | Notes |
|-------|--------------|----------------------|-------|
| California | Yes (CA Bar) | Implement | Best-in-class API |
| New York | Yes (NY Bar) | Implement | Requires registration |
| Florida | Yes (FL Bar) | Implement | Fee-based API |
| Texas | Yes (TX Bar) | Implement | Available via Bar website |
| Illinois | Yes (ARDC) | Implement | Good automated tools |
| All Others | Varies | Manual + NCBE | Use NCBE for states without direct API |

> **⚖️ ATTORNEY REVIEW REQUIRED:** Verification of out-of-state pro hac vice admissions requires case-specific legal analysis. The platform's verification to claimants should state "Verified licensed in [state]" not "Verified competent" — competence verification is not appropriate for a marketplace.

---

### 3.2 State Coverage Matrix

| State | Attorneys Available | Active Cases | Coverage Status | Recruitment Priority | ⚖️ Notes |
|-------|-------------------|-------------|-----------------|---------------------|----------|
| Alabama | TBD | TBD | NOT COVERED | HIGH — active surplus funds courts | ⚖️ Review AL fee rules |
| Alaska | TBD | TBD | NOT COVERED | LOW — low volume | ⚖️ |
| Arizona | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Arkansas | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| California | TBD | TBD | ⚠️ HIGH PRIORITY | CRITICAL — largest surplus market | ⚖️ CA strictest rules |
| Colorado | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Connecticut | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Delaware | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Florida | TBD | TBD | ⚠️ HIGH PRIORITY | CRITICAL — large foreclosure market | ⚖️ FL aggressive enforcement |
| Georgia | TBD | TBD | ⚠️ HIGH PRIORITY | HIGH — large surplus market | ⚖️ |
| Hawaii | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Idaho | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Illinois | TBD | TBD | ⚠️ HIGH PRIORITY | HIGH — major market | ⚖️ |
| Indiana | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Iowa | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Kansas | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Kentucky | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Louisiana | TBD | TBD | NOT COVERED | MEDIUM — civil law system | ⚖️ Unique legal system |
| Maine | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Maryland | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Massachusetts | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Michigan | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Minnesota | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Mississippi | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Missouri | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Montana | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Nebraska | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Nevada | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| New Hampshire | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| New Jersey | TBD | TBD | ⚠️ HIGH PRIORITY | HIGH — large surplus market | ⚖️ |
| New Mexico | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| New York | TBD | TBD | ⚠️ HIGH PRIORITY | CRITICAL — largest market | ⚖️ NY strict advertising |
| North Carolina | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| North Dakota | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Ohio | TBD | TBD | ⚠️ HIGH PRIORITY | HIGH — major foreclosure market | ⚖️ |
| Oklahoma | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Oregon | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Pennsylvania | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Rhode Island | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| South Carolina | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| South Dakota | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Tennessee | TBD | TBD | ⚠️ HIGH PRIORITY | HIGH — active surplus market | ⚖️ |
| Texas | TBD | TBD | ⚠️ HIGH PRIORITY | CRITICAL — largest foreclosure market | ⚖️ |
| Utah | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Vermont | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Virginia | TBD | TBD | ⚠️ HIGH PRIORITY | HIGH — active market | ⚖️ |
| Washington | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| West Virginia | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Wisconsin | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |
| Wyoming | TBD | TBD | NOT COVERED | LOW | ⚖️ |
| Washington DC | TBD | TBD | NOT COVERED | MEDIUM | ⚖️ |

---

### 3.3 Onboarding Requirements

#### Minimum Documentation Requirements

| Document | Purpose | Verification Method | Retention Period |
|----------|---------|-------------------|-----------------|
| State Bar License | Proof of licensure | API verification + copy | Duration of engagement + 5 years |
| Certificate of Good Standing | Active status | State Bar API | Duration of engagement |
| Malpractice Insurance Certificate | Minimum coverage ($250K/$500K recommended) | Carrier verification | Current copy always on file |
| W-9 | Tax identification | IRS TIN matching | As required by IRS |
| ACH/Wire Instructions | Payment processing | Banking verification | Duration of engagement |
| Engagement Agreement (with Wheeler) | Contract for platform services | Executed copy | 7 years post-termination |
| Conflict Check Acknowledgment | Attorney confirms no waiver of duties | Signed acknowledgment | Duration of engagement |
| Confidentiality Agreement | Protection of platform information | Signed agreement | Perpetual (survives termination) |
| Technology Competency Certification | Compliance with ABA Rule 1.1, Comment 8 | Self-certification + training completion | Annual renewal |
| State-Specific Addenda | Compliance with state-specific rules | Signed addendum | Per state of practice |

#### Technology Competency Certification (ABA Rule 1.1, Comment 8)

ABA Model Rule 1.1, Comment 8 requires attorneys to "keep abreast of changes in the law and its practice, including the benefits and risks associated with relevant technology." Wheeler's onboarding must include:

1. **Training module** on Wheeler platform tools and features
2. **Security training** on data protection, password management, phishing awareness
3. **Certification** that attorney understands technology requirements and risks
4. **Annual refresher** on platform updates and new security requirements

---

### 3.4 Attorney Right to Withdraw / Removal

| Circumstance | Action | Notification | Impact on Existing Cases |
|-------------|--------|--------------|------------------------|
| License suspension | IMMEDIATE REMOVAL from platform | Within 24 hours | Attorney must notify existing clients; Wheeler facilitates transition |
| Disbarment | IMMEDIATE REMOVAL + report to bar | Within 24 hours | Emergency reassignment protocol triggered |
| Expired license | Suspension until renewal | 30/60/90 day warnings | No new cases; existing cases continue if still covered |
| Malpractice lapse | Suspension until proof of coverage | 14-day warning | No new cases; existing cases continue |
| Voluntary withdrawal | Platform removal at end of notice period | 30-day notice | Transition plan required |
| Discipline (minor) | Review — may restrict or warn | Case-by-case | Determined on review |
| Multiple client complaints | Investigation — possible suspension | Within 7 days | Determined on investigation |

---

## 4. REFERRAL COMPLIANCE

### 4.1 Referral vs. Recommendation vs. Advertising

The distinction between these three concepts is critical to compliance:

| Concept | Definition | ABA Rule | Permitted? |
|---------|-----------|----------|------------|
| **Advertisement** | A communication that offers or promotes a lawyer's services to the general public | Rule 7.2 | YES — attorney can pay for advertising |
| **Referral** | Directing a specific individual to a specific lawyer for legal services | Rule 7.2(b) | PROHIBITED — cannot pay for a "recommendation" |
| **Recommendation** | Endorsement of a specific lawyer's services | Rule 7.2(b) | PROHIBITED — cannot give value for a recommendation |
| **Qualified Referral Service** | A service that refers potential clients to lawyers, subject to regulation | Varies by state | CONDITIONAL — must meet state requirements |

#### Wheeler's Classification Strategy

Wheeler should structure its service as a **legal matching platform / attorney directory** (advertising model), NOT a referral service. Key distinctions:

| Feature | Referral Service | Directory/Matching Platform | Wheeler's Position |
|---------|-----------------|---------------------------|-------------------|
| Selection basis | Subjective recommendation | Objective criteria | **Objective criteria only** |
| Fee structure | Per-referral or percentage | Flat fee or subscription | **Flat fee / subscription / per-lead** |
| Attorney inclusion | Selective panel | All qualified attorneys | **All qualified attorneys may list** |
| Client choice | Assigned | Client chooses | **Claimant chooses from matches** |
| Regulation | Qualified referral service rules | Advertising rules | **Advertising rules apply** |

**Critical Policy:**
- Wheeler must NEVER claim to "recommend" or "refer" attorneys
- Wheeler's matching must be based on OBJECTIVE criteria (state, practice area, availability)
- Claimants must ALWAYS have the right to choose their own attorney outside the platform
- All marketing must clearly describe Wheeler as a "matching service" or "directory" not a "referral service"

> **⚖️ ATTORNEY REVIEW REQUIRED:** Some states (e.g., Florida, New York, California) have specific requirements for "lawyer referral services" that may apply even to directory/matching models. Analysis under each state's definition of "referral service" is essential.

---

### 4.2 Structuring Compliant Referrals (Matching)

#### Objective Matching Criteria

| Criterion | Description | Compliance Status |
|-----------|-------------|------------------|
| State licensure | Match to attorneys licensed in the state where surplus funds held | SAFE — objective |
| Practice area | Attorney confirmed experience with surplus funds recovery | SAFE — objective |
| Case capacity | Attorney has indicated availability to take new cases | SAFE — objective |
| Geographic proximity | Attorney located in same region as court | SAFE — objective |
| Language | Attorney speaks claimant's language | SAFE — objective |
| Fee arrangement type | Attorney offers contingency/ hourly/flat fee | SAFE — objective |
| Client satisfaction score | Aggregated, anonymous satisfaction metrics | MODERATE — must not be legal quality rating |
| Years of experience | Years since bar admission | SAFE — objective, but avoid "expert" claims |

#### PROHIBITED Matching Criteria

| Criterion | Reason for Prohibition | Alternative |
|-----------|----------------------|-------------|
| "Best" or "Top-rated" claims | Legal quality judgment — misleading | Display objective metrics only |
| Financial arrangement (fee percentage paid to Wheeler) | Disguised referral fee | Fixed fee regardless of match result |
| Attorney's past settlement amounts in similar cases | Potentially misleading advertising (Rule 7.1) | Display with proper context and disclaimers |
| Attorney's win rate | Potentially misleading (Rule 7.1) | Not recommended for display |
| Subjective attorney ratings | Imply endorsement | Use objective, verifiable metrics only |

#### Matching Disclosure Requirements

Every match result must include the following disclosures:

```
NOTICE: Wheeler is not a law firm and does not provide legal services or legal advice.
The attorneys listed are independent professionals. Wheeler does not recommend or endorse
any specific attorney. You have the right to choose your own attorney, whether or not
they are listed on the Wheeler platform. Wheeler receives compensation from participating
attorneys for [marketing services / platform access]. This compensation may affect which
attorneys appear in search results.
```

> **⚖️ ATTORNEY REVIEW REQUIRED:** The specific language of all matching disclosures must be reviewed for compliance with each state's rules.

---

### 4.3 Fee Limitations Summary

| Fee Type | Permissibility | Rule Basis | Conditions | ⚖️ |
|----------|---------------|-----------|------------|-----|
| Flat monthly attorney subscription | ✅ PERMITTED | Rule 7.2(b)(1) | Fee is for advertising, not recommendation | ⚖️ |
| Flat annual attorney subscription | ✅ PERMITTED | Rule 7.2(b)(1) | Same as above | ⚖️ |
| Per-lead fee (same price per lead) | ✅ PERMITTED with caution | Rule 7.2(b)(1) | Must NOT be contingent on lead converting to client | ⚖️ |
| Per-case platform fee (flat amount) | ⚠️ CONDITIONAL | Rule 7.2(b)(1) / administrative services | Must be for actual services, not tied to outcome | ⚖️ |
| Percentage of attorney fee | ❌ PROHIBITED (likely) | Rule 5.4(a) | Fee splitting with non-lawyer | ⚖️ |
| Percentage of case recovery from attorney | ❌ PROHIBITED (likely) | Rule 5.4(a) | Fee splitting with non-lawyer | ⚖️ |
| Claimant assignment (percentage) | ⚠️ CONDITIONAL | Not attorney regulation (consumer/assignment law) | Requires separate agreement; varies by state | ⚖️ |
| Tiered pricing (higher fee = better placement) | ❌ PROHIBITED (likely) | Rule 7.2(b), Rule 5.4 | Paid recommendation | ⚖️ |

> **⚖️ ATTORNEY REVIEW REQUIRED:** EVERY fee structure listed as "conditional" or "prohibited" requires individual state-by-state analysis. Ethics opinions from qualified local counsel are strongly recommended.

---

## 5. CAPACITY ROUTING & PERFORMANCE

### 5.1 Capacity Management

#### Attorney Capacity Declaration

Attorneys must declare their capacity to accept new cases. This is an objective limit, not a subjective recommendation.

| Capacity Parameter | Description | Verification |
|-------------------|-------------|--------------|
| Case load limit | Maximum active surplus funds cases (self-declared) | Self-certified; flag if consistently exceeded |
| Weekly lead limit | Maximum new leads accepted per week | System-enforced |
| Response time SLA | Maximum hours to respond to claimant (self-declared) | System-monitored |
| Jurisdictional capacity | Which states/regions attorney can handle | Bar-verified |

#### Automated Routing Logic

```
IF claimant.claim_state IN attorney.licensed_states
AND attorney.active_cases < attorney.case_limit
AND attorney.lead_queue < attorney.daily_lead_limit
THEN include_attorney_in_match_pool(attorney)

ORDER match_pool BY:
  1. Surplus funds case count (more experience → higher)
  2. Geographic proximity (within state → higher)
  3. Claimant language match → higher
  4. Random rotation (to prevent preferential treatment)

DISPLAY top N matches to claimant (randomized within matched group)
```

#### Emergency Re-Assignment

| Trigger | Action | Timeline |
|---------|--------|----------|
| Attorney withdrawal | Alert compliance team; reconnect claimant to new attorney | Within 48 hours |
| Attorney discipline/suspension | IMMEDIATE pause; reassign all pending cases | Within 24 hours |
| Attorney illness/death | Emergency protocol; family/estate notification + case transfer | Within 72 hours |
| Attorney capacity overflow | Block new leads; re-route to other qualified attorneys | Real-time |

---

### 5.2 Performance Monitoring (Compliance Constraints)

#### What Wheeler CAN Monitor

| Metric | Data Source | Compliance Status |
|--------|-------------|------------------|
| Case volume and aging | Attorney self-report + court docket | SAFE — administrative |
| Status of case (filed, pending, resolved) | Attorney update in platform | SAFE — administrative |
| Response time to claimant communications | Platform messaging system | SAFE — administrative |
| Court deadline compliance | Attorney self-report + docket check | SAFE — administrative (deadline visibility) |
| Client satisfaction (process survey) | Claimant survey (non-legal questions) | SAFE — not evaluating legal quality |
| Document submission timeliness | Platform document upload tracking | SAFE — administrative |
| License and insurance status | Bar API + carrier verification | SAFE — compliance monitoring |

#### What Wheeler CANNOT Monitor

| Metric | Reason | Alternative |
|--------|--------|-------------|
| Quality of legal analysis | UPL-adjacent; interference with professional judgment (Rule 5.4(c)) | None — must NOT evaluate |
| Settlement amount adequacy | Interference with professional judgment | Attorney's independent decision |
| Litigation strategy evaluation | Interference with professional judgment (Rule 5.4(c)) | None — must NOT evaluate |
| Whether attorney should settle | Practice of law / interference | Attorney's independent decision |
| Legal research quality | UPL-adjacent | None — must NOT evaluate |
| Whether to appeal a ruling | Practice of law / interference | Attorney's independent decision |

#### THE BRIGHT LINE ON PERFORMANCE EVALUATION

> Wheeler monitors **administrative and process metrics** only. Wheeler does not evaluate **legal quality, strategy, or outcomes**. Any system or individual that crosses this line risks engaging in UPL or interfering with the attorney-client relationship.

---

### 5.3 Attorney Performance Dashboard (Compliance View)

The following metrics are appropriate for an attorney-facing dashboard:

| Dashboard Section | Metrics | Who Sees | Compliance Check |
|-------------------|---------|----------|-----------------|
| Case Volume | Active cases, pending cases, resolved cases (30/60/90d) | Attorney + Wheeler Admin | SAFE |
| Aging | Average case age, oldest case, cases over 180 days | Attorney + Wheeler Admin | SAFE |
| Status Distribution | Filed, discovery, settlement, trial, resolved | Attorney + Wheeler Admin | SAFE |
| Response Time | Average hours to first response to claimant | Attorney + Wheeler Admin | SAFE |
| Client Satisfaction | Survey completion rate, aggregate satisfaction (process only) | Attorney only | SAFE — never public |
| Compliance Flags | License expiry, insurance expiry, pending warnings | Attorney + Wheeler Admin | SAFE |
| New Leads | Leads offered, accepted, declined | Attorney + Wheeler Admin | SAFE |

#### Metrics NOT included on Dashboard

| Excluded Metric | Reason Excluded |
|-----------------|----------------|
| Attorney "quality score" | Legal quality judgment |
| Settlement amount comparison | Outcome-based evaluation |
| Win/loss record | Potentially misleading under Rule 7.1 |
| Client testimonial star rating | Subject to state advertising restrictions |
| Comparative rankings | Implies endorsement / recommendation |

---

## 6. CLIENT-ATTORNEY RELATIONSHIP GOVERNANCE

### 6.1 Engagement Process

The engagement process must clearly establish that:
1. **Wheeler facilitates the connection** — Wheeler matches the claimant with an attorney
2. **The attorney-client relationship is between the attorney and the claimant** — Wheeler is not a party
3. **The attorney's engagement agreement controls** — Not Wheeler's terms
4. **Wheeler provides administrative support** — Technology, scheduling, document management

#### Process Flow

```
Step 1: Claimant identifies surplus funds claim on Wheeler platform
        ↕ (Factual information — NOT legal advice)
Step 2: Wheeler presents qualified attorneys (objective matching)
        ↕ (Disclosure: Wheeler does not recommend any attorney)
Step 3: Claimant reviews attorney profiles and selects attorney(s)
        ↕ (Claimant choice — Wheeler does not assign)
Step 4: Wheeler facilitates introduction
        ↕ (Wheeler provides contact information / connection)
Step 5: Attorney and claimant enter engagement agreement
        ↕ (Attorney's form — NOT Wheeler's form)
Step 6: Attorney-client relationship established
        ↕ (Wheeler is NOT a party)
Step 7: Wheeler provides administrative support to attorney
        ↕ (Technology, scheduling, document management)
```

#### ⚠️ CRITICAL RULES FOR THE ENGAGEMENT PROCESS

1. **NEVER let a claimant believe Wheeler is their lawyer**
2. **ALWAYS have the claimant sign a separate engagement letter with the attorney**
3. **NEVER use Wheeler's terms of service as the engagement agreement**
4. **ALWAYS make it clear the claimant can fire their attorney and choose another**
5. **NEVER offer legal advice during the engagement process**
6. **ALWAYS document that the claimant has been informed of their rights**

---

### 6.2 Required Disclosures

#### Disclosure Checklist (Claimant-Facing)

| # | Disclosure | Timing | Method | Verified? |
|---|-----------|--------|--------|-----------|
| 1 | Wheeler is not a law firm | First contact | Written + verbal | Click-through acknowledgment |
| 2 | Wheeler does not provide legal advice | First contact / matching | Written | Click-through acknowledgment |
| 3 | Attorney is independent | Before engagement | Written in matching results | Acknowledged |
| 4 | Claimant right to choose | Before engagement | Written | Acknowledged |
| 5 | Wheeler compensation structure | Before engagement | Written | Signed disclosure |
| 6 | No guarantee of outcome | All marketing & matching | Written | Conspicuous |
| 7 | Claimant right to proceed without attorney | First contact | Written | Acknowledged |
| 8 | Privacy / data practices | First contact | Privacy policy | Click-through |
| 9 | Complaint process | On request | Written | Available |
| 10 | State-specific disclosures (if any) | Per state requirement | Written | ⚖️ ATTORNEY REVIEW REQUIRED |

---

### 6.3 Interference Prohibition

ABA Model Rule 5.4(c) states: "A lawyer shall not permit a person who recommends, employs, or pays the lawyer to render legal services for another to direct or regulate the lawyer's professional judgment in rendering such legal services."

#### Wheeler's Obligations Under Rule 5.4(c)

| Action | Permitted? | Reasoning |
|--------|-----------|-----------|
| Suggest legal strategy to attorney | ❌ NO | Direct interference with professional judgment |
| Require attorney to use specific forms | ❌ NO | Interference with professional judgment |
| Set deadlines for legal work | ⚠️ CONDITIONAL | Administrative deadlines (court dates) are permitted; strategic deadlines are not |
| Require status updates | ✅ YES | Administrative — does not direct judgment |
| Monitor case progress | ✅ YES | Administrative — does not direct judgment |
| Recommend use of certain expert witnesses | ❌ NO | Strategic decision — attorney's judgment |
| Set settlement authority parameters | ❌ NO | Core legal decision — attorney and client only |
| Provide technology tools | ✅ YES | Administrative support — no judgment interference |
| Generate draft documents for review | ⚠️ CONDITIONAL | Permitted if attorney retains final review and approval authority |

#### Platform Policies to Enforce Non-Interference

1. **No case strategy inputs**: Platform must not allow Wheeler staff to input case strategy notes or recommendations
2. **Attorney independence acknowledgment**: Signed by attorney at onboarding and included in Wheeler-attorney agreement
3. **Claimant independence acknowledgment**: Claimant acknowledges that Wheeler does not control or direct attorney
4. **Communication boundaries**: All substantive legal communications are between attorney and client; Wheeler has view-only access as needed

> **⚖️ ATTORNEY REVIEW REQUIRED:** The non-interference provisions in Wheeler's attorney agreement must be reviewed for enforceability and compliance with state rules.

---

### 6.4 Attorney-Client Privilege & Confidentiality

#### Privilege Flow

| Stage | Privilege Status | Wheeler's Role |
|-------|------------------|---------------|
| Pre-engagement / Claimant intake | NOT privileged (no attorney-client relationship) | Wheeler collects information; confidentiality under privacy policy, not privilege |
| Matching process | NOT privileged | Wheeler transmits objective data to attorney |
| Initial consultation | BECOMES privileged once relationship forms | Wheeler facilitates connection but should not be present |
| Active representation | PRIVILEGED | Wheeler has limited, authorized access to administrative data only |
| Post-resolution | Privilege continues indefinitely | Wheeler's records may contain privileged information; must be protected |

#### Data Access Controls

| Data Category | Wheeler Access | Attorney Access | Claimant Access | Security Requirements |
|---------------|---------------|-----------------|-----------------|----------------------|
| Claimant contact info | ✅ Full | ✅ Full | ✅ Full | Encryption at rest and transit |
| Case details (non-privileged) | ✅ Limited | ✅ Full | ✅ Full | Role-based access control |
| Attorney-client communications | ❌ NO | ✅ Full | ✅ Full | End-to-end encryption |
| Legal documents | ✅ With attorney authorization | ✅ Full | ✅ Full | Access logging |
| Billing/fee information | ✅ Limited | ✅ Full | ✅ Full | Segregated from case data |
| Settlement information | ✅ Attorney-authorized disclosure only | ✅ Full | ✅ Full | Strict access controls |

> **⚠️ CRITICAL: Data Segregation Architecture Required**
> The platform must maintain strict data segregation between:
> 1. Public/non-privileged data (attorney profiles, general information)
> 2. Pre-engagement data (claimant intake, matching results)
> 3. Post-engagement privileged data (case communications, legal documents)
> 4. Administrative data (billing, compliance, platform usage)

---

## 7. CONFLICT CHECKS & ETHICS WALLS

### 7.1 Conflict Check Process

| Step | Responsible Party | Description | Legal Significance |
|------|------------------|-------------|-------------------|
| 1. Claimant intake | Wheeler | Collect: claimant name, adverse parties, property owners, co-owners, related entities | Data collection — no legal judgment |
| 2. Basic conflict screening (Wheeler level) | Wheeler | Check claimant name against basic conflict database (attorneys who have flagged conflicts) | Administrative — not a full conflict check |
| 3. Full conflict check | Attorney | Attorney performs state-bar-level conflict check using their own systems | LEGAL — attorney's professional responsibility |
| 4. Conflict waiver (if needed) | Attorney + Claimant | If conflict exists, attorney must obtain informed consent in writing | LEGAL — attorney's professional responsibility |
| 5. Wheeler acknowledgment | Wheeler | Full confirmation of clear result recorded in platform | Administrative record-keeping |

#### Wheeler's Conflict Role: FACILITATION ONLY

| Task | Permitted? | Rationale |
|------|-----------|-----------|
| Collect conflict information from claimant | ✅ YES | Factual gathering — not legal work |
| Provide structured conflict check form | ✅ YES | Administrative form — not legal advice |
| Maintain basic "same party / same matter" database | ✅ YES | Objective data — no legal judgment required |
| Run automated name matching | ✅ YES | Algorithmic matching — no legal judgment |
| Determine whether a conflict exists | ❌ NO | Legal judgment — attorney's responsibility |
| Advise claimant or attorney on conflict resolution | ❌ NO | Legal advice — attorney's responsibility |
| Draft conflict waiver letters | ❌ NO | Legal drafting — attorney's responsibility |
| Decide whether conflict is waivable | ❌ NO | Legal judgment — attorney's responsibility |

> **⚠️ CRITICAL RULE:** Wheeler facilitates conflict checks by providing information to attorneys. Wheeler does not determine whether a conflict exists or is waivable. Those are legal determinations requiring attorney judgment.

---

### 7.2 Confidentiality & Ethics Walls

#### Information Segmentation

| Segment | Contents | Access | Privilege Status |
|---------|----------|--------|-----------------|
| Segment A (Public) | Attorney profiles, general legal information, blog content | Public | No privilege |
| Segment B (Claimant Profile) | Name, contact, claim state, property address, claimant preferences | Wheeler + Attorney (as authorized) | Pre-engagement — not privileged |
| Segment C (Case Data) | Case details, deadlines, documents (with attorney authorization) | Attorney + Claimant; Wheeler (limited) | Privileged post-engagement |
| Segment D (Communications) | Attorney-client messages, phone logs (metadata only) | Attorney + Claimant; Wheeler (metadata only) | Privileged |
| Segment E (Attorney Admin) | Billing, compliance, capacity, performance data | Wheeler + Attorney | Not privileged — business records |

#### Wheeler Ethics Wall Policy

1. **No Wheeler employee reads attorney-client privileged communications** without specific, written authorization from both attorney and client
2. **Wheeler's platform infrastructure provides no backdoor access** to communication channels
3. **All privileged content is encrypted end-to-end** between attorney and client (Wheeler does not hold decryption keys)
4. **Audit logging** of all access to Segments C and D data
5. **Quarterly access review** to ensure no unauthorized access to privileged materials
6. **Breach notification** within 24 hours of any detected unauthorized access to privileged materials

---

## 8. MULTI-STATE OPERATIONS

### 8.1 State Coverage Requirements

| Requirement | Detail | Verification |
|-------------|--------|--------------|
| Attorney licensure per state | Attorney must be active, good-standing member of bar in state where court sits | State bar API verification |
| Pro hac vice admission | Attorney not licensed in the forum state must obtain court permission | Court order verification |
| Local counsel requirement | Some states require local counsel for out-of-state attorneys | State-by-state rule check |
| Multi-jurisdictional practice (MJP) | Rule 5.5 provides temporary practice allowances (limited) | As permitted by state |

#### Pro Hac Vice Requirements by State

| State | Local Counsel Required? | Pro Hac Vice Fee | Timelines | Notes |
|-------|------------------------|------------------|-----------|-------|
| Alabama | YES | Varies | 14-30 days | Local counsel must be active AL attorney |
| Alaska | NO (but preferred) | Varies | 10-30 days | |
| Arizona | NO | $100 | 10 days | |
| Arkansas | YES | Varies | 10-30 days | |
| California | YES | $500 | 30 days | Strict pro hac vice rules |
| Colorado | YES | Varies | 10-30 days | |
| Connecticut | YES | Varies | 10 days | |
| Delaware | YES | Varies | Varies | Strict local counsel requirement |
| Florida | YES | $100 | 30 days | Must file motion with court |
| Georgia | YES | Varies | 30 days | |
| ... | (Complete for all 50 states) | | | |

> **⚖️ ATTORNEY REVIEW REQUIRED:** Pro hac vice rules vary by court and case type within states. A comprehensive pro hac vice guide must be maintained by local counsel.

---

### 8.2 State Bar Advertising Rules Quick Reference

| State | Ad Filing Required? | Pre-Approval? | Record Retention | Special Restrictions | ⚖️ |
|-------|--------------------|---------------|------------------|---------------------|-----|
| Alabama | No | No | 2 years | Must include "Alabama State Bar" disclaimer if claiming specialization | ⚖️ |
| Alaska | No | No | 2 years | | ⚖️ |
| Arizona | No | No | 2 years | Must include "No representation made" disclaimer | ⚖️ |
| Arkansas | Yes (some ads) | No | 3 years | | ⚖️ |
| California | Yes (within 5 days of dissemination) | No | 2 years | Must state "California Board of Legal Specialization" for certified specialists; SBN required in all ads | ⚖️ |
| Colorado | Yes | No | 3 years | Disclaimers required for certain practice areas | ⚖️ |
| Connecticut | Yes | No | 2 years | | ⚖️ |
| Delaware | Yes | No | 2 years | | ⚖️ |
| Florida | YES — aggressive | YES — mandatory pre-approval | 3 years | STRICTEST: all ads must be pre-approved; extensive content restrictions; must include "The hiring of a lawyer is an important decision" statement | ⚖️ |
| Georgia | No | No | 2 years | | ⚖️ |
| Hawaii | No | No | 2 years | | ⚖️ |
| Idaho | Yes | No | 2 years | | ⚖️ |
| Illinois | Yes | No | 2 years + rule amendments | Must include "Lawyer referral service" disclosure if appropriate | ⚖️ |
| Indiana | No | No | 2 years | | ⚖️ |
| Iowa | Yes | No | 5 years | | ⚖️ |
| Kansas | No | No | 2 years | | ⚖️ |
| Kentucky | Yes | No | 5 years | | ⚖️ |
| Louisiana | No | No | 2 years | | ⚖️ |
| Maine | No | No | 2 years | | ⚖️ |
| Maryland | Yes | No | 3 years | | ⚖️ |
| Massachusetts | No | No | 2 years | | ⚖️ |
| Michigan | No | No | 2 years | | ⚖️ |
| Minnesota | Yes | No | 2 years | | ⚖️ |
| Mississippi | No | No | 2 years | | ⚖️ |
| Missouri | No | No | 2 years | | ⚖️ |
| Montana | No | No | 2 years | | ⚖️ |
| Nebraska | No | No | 2 years | | ⚖️ |
| Nevada | Yes | No | 3 years | | ⚖️ |
| New Hampshire | No | No | 2 years | | ⚖️ |
| New Jersey | Yes (for some ads) | No | 2 years | Strict rules for solicitation; certification disclaimers | ⚖️ |
| New Mexico | No | No | 2 years | | ⚖️ |
| New York | Yes (filed with Attorney General) | No | 3 years | VERY strict: extensive content requirements; must include "Attorney Advertising" label; pre-recorded ads require filing; all communications subject to detailed rules in 22 NYCRR 1200.8 | ⚖️ |
| North Carolina | No | No | 3 years | | ⚖️ |
| North Dakota | No | No | 2 years | | ⚖️ |
| Ohio | No | No | 2 years | | ⚖️ |
| Oklahoma | Yes | No | 3 years | | ⚖️ |
| Oregon | No | No | 2 years | | ⚖️ |
| Pennsylvania | No | No | 2 years | Must include "Ads" label; specific disclaimers | ⚖️ |
| Rhode Island | No | No | 2 years | | ⚖️ |
| South Carolina | Yes | No | 3 years | | ⚖️ |
| South Dakota | No | No | 2 years | | ⚖️ |
| Tennessee | Yes | No | 2 years | | ⚖️ |
| Texas | Yes (filed with State Bar) | No | 4 years | Must include "Attorney Advertising. Not a solicitation." for certain communications; filed ads require State Bar number | ⚖️ |
| Utah | No | No | 2 years | | ⚖️ |
| Vermont | No | No | 2 years | | ⚖️ |
| Virginia | Yes | No | 3 years | | ⚖️ |
| Washington | No | No | 2 years | | ⚖️ |
| West Virginia | No | No | 2 years | | ⚖️ |
| Wisconsin | Yes | No | 2 years | | ⚖️ |
| Wyoming | No | No | 2 years | | ⚖️ |
| Washington DC | No | No | 2 years | | ⚖️ |

> **⚖️ ATTORNEY REVIEW REQUIRED:** The above table is based on published rules but is NOT a substitute for individual state bar review. Each state's advertising rules change, and some states have pending rule amendments. Local counsel must verify current requirements for each state of operation.

---

### 8.3 State-Specific Operational Requirements

#### High-Risk States — Enhanced Compliance Requirements

| State | Enhanced Requirement | Compliance Action | Timeline |
|-------|---------------------|-------------------|----------|
| **California** | CA Rule 1.5-1.6 — virtually prohibits non-lawyer fee sharing; strict UPL enforcement | Retain CA ethics counsel; obtain formal opinion; CA-specific terms and disclosures | Before CA launch |
| **Florida** | ALL advertising must be pre-approved by Florida Bar; aggressive UPL enforcement | Retain FL ethics counsel; submit all ads for pre-approval; 30+ day lead time for new ads | Before FL launch |
| **New York** | Advertising filing with NY Attorney General; NY Jud. Law 495 restrictions on referral services | Retain NY counsel; file all ads; structure to avoid "referral service" classification | Before NY launch |
| **Texas** | Ads filed with TX State Bar; specific required disclaimers; 4-year retention | Retain TX counsel; file ads; implement TX-specific disclaimers | Before TX launch |
| **Illinois** | ARDC regulation; required disclosures for referral services | Retain IL counsel; implement IL-specific disclosures | Before IL launch |
| **Ohio** | Supreme Court regulation of referral services; specific OH-specific requirements | Retain OH counsel; ensure compliance with OH referral service rules | Before OH launch |
| **Pennsylvania** | PA-specific referral service rules; ad disclaimer requirements | Retain PA counsel; comply with PA referral service rules | Before PA launch |
| **Georgia** | State Bar referral service oversight | Retain GA counsel; register or ensure exemption from referral service regulation | Before GA launch |
| **New Jersey** | Strict UPL enforcement; NJ-specific advertising rules | Retain NJ counsel; implement NJ-specific compliance | Before NJ launch |

---

## 9. COMPLIANCE OPERATIONS

### 9.1 Daily Compliance Checks

| Check | Method | Responsible | Escalation |
|-------|--------|-------------|------------|
| Attorney license status (automated) | State Bar API / NCBE API check for all active attorneys | Automated / Wheeler Compliance | Failed check → immediate alert to compliance team |
| Disciplinary action alerts | State bar RSS feeds / LEXIS Nexis alerts | Automated | New discipline → immediate review |
| Pending case status updates | Attorney self-report in platform | Attorney | Missed update > 7 days → compliance warning |
| New claimant complaints | In-platform complaint form monitoring | Wheeler Compliance | Complaint → within 24 hours |
| System security alerts | SIEM / intrusion detection | Automated / Wheeler Security | Security incident → immediate escalation per IR plan |
| Data access audit anomalies | Log analysis / UEBA | Automated | Unauthorized access attempt → immediate lockdown |

#### Automated Attorney License Verification Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  DAILY COMPLIANCE ENGINE                 │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  09:00 — Run license check for all active attorneys      │
│          │                                               │
│          ├─ State Bar API (direct integration states)     │
│          ├─ NCBE Bar API (multi-state verification)      │
│          └─ Manual check (states without API)            │
│          │                                               │
│          └─ Results:                                      │
│               ├─ ALL PASS → log, no action               │
│               ├─ LICENSE EXPIRED → suspend, notify       │
│               ├─ LICENSE SUSPENDED → remove, notify, IR  │
│               └─ ERROR/NO DATA → flag for manual review  │
│                                                          │
│  14:00 — Run disciplinary alert check                     │
│          │                                               │
│          └─ Results: → Update attorney compliance record  │
│                                                          │
│  17:00 — Daily compliance report generated               │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

### 9.2 Monthly Compliance Tasks

| Task | Description | Responsible | Documentation | ⚖️ |
|------|-------------|-------------|---------------|-----|
| Attorney performance review | Administrative metrics review (response time, case aging, status updates) | Wheeler Compliance | Monthly compliance memo | ⚖️ NO legal quality evaluation |
| Client complaint review | Review all claimant complaints; identify patterns | Wheeler Compliance | Complaint log + analysis | ⚖️ |
| State rule update monitoring | Review state bar rule changes in operating states | Wheeler Compliance + Outside Counsel | Regulatory change log | ⚖️ ATTORNEY REVIEW REQUIRED |
| New state coverage assessment | Evaluate any new states for market entry | Wheeler Strategy + Compliance | Market entry compliance memo | ⚖️ ATTORNEY REVIEW REQUIRED |
| Platform compliance audit | Automated audit of compliance controls | Wheeler Compliance | Compliance audit report | ⚖️ |
| Fee structure review | Confirm no changes to fee arrangements have created compliance issues | Wheeler Compliance + Legal | Fee compliance review | ⚖️ ATTORNEY REVIEW REQUIRED |

---

### 9.3 Quarterly Compliance Tasks

| Task | Description | Responsible | Documentation | ⚖️ |
|------|-------------|-------------|---------------|-----|
| Full attorney re-verification | Complete license check, good standing, malpractice insurance, discipline check for ALL attorneys | Wheeler Compliance | Attorney verification report | ⚖️ |
| State coverage gap analysis | Compare current attorney roster with active case states; identify gaps | Wheeler Compliance | Coverage analysis report | ⚖️ |
| Compliance training | Internal compliance training for Wheeler staff handling attorney/claimant data | Wheeler Compliance Lead | Training records | ⚖️ |
| Ad material review | Review all active attorney ads and platform marketing for compliance | Wheeler Compliance + Outside Counsel | Ad compliance review | ⚖️ ATTORNEY REVIEW REQUIRED |
| Outside counsel regulatory update | Quarterly call with outside counsel to review regulatory changes | Wheeler Legal + Outside Counsel | Regulatory update memo | ⚖️ ATTORNEY REVIEW REQUIRED |
| Data access audit | Review all privileged data access logs; verify no unauthorized access | Wheeler Security + Compliance | Data access audit report | ⚖️ |

---

### 9.4 Annual Compliance Tasks

| Task | Description | Responsible | Documentation | ⚖️ |
|------|-------------|-------------|---------------|-----|
| Full marketplace compliance audit | Comprehensive audit of all compliance controls, policies, and procedures | External Compliance Auditor | Full audit report | ⚖️ ATTORNEY REVIEW REQUIRED |
| Fee structure legal review | Legal review of all fee arrangements with current counsel | Outside Counsel | Fee structure legal opinion | ⚖️ ATTORNEY REVIEW REQUIRED |
| Privacy/security assessment | Comprehensive privacy and security assessment (SOC 2 Type II or equivalent) | External Auditor | SOC 2 / security assessment report | ⚖️ |
| Independent ethics opinion | Obtain formal ethics opinion from licensed counsel in each high-risk state (CA, FL, NY, TX at minimum) | Outside Counsel (per state) | Formal ethics opinions | ⚖️ ATTORNEY REVIEW REQUIRED |
| Surplus funds rulebook update | Review and update surplus funds legal rules (see SURPLUS_FUNDS_RULEBOOK.md) | Wheeler Legal + Outside Counsel | Updated rulebook | ⚖️ ATTORNEY REVIEW REQUIRED |
| State compliance matrix update | Full update of STATE_COMPLIANCE_MATRIX.md | Wheeler Compliance + Outside Counsel | Updated matrix | ⚖️ ATTORNEY REVIEW REQUIRED |
| Platform compliance features review | Evaluate whether platform needs new compliance features | Wheeler Product + Compliance | Compliance feature roadmap | ⚖️ |

---

## 10. RISK MITIGATION TABLE

### 10.1 Risk Register

| ID | Risk | Severity | Probability | Risk Score | Legal Exposure | Mitigation | Status | ⚖️ |
|----|------|----------|------------|------------|---------------|-----------|--------|-----|
| R-001 | UPL — AI drafting legal documents without attorney review | CRITICAL | HIGH | 25/25 | Criminal charges (misdemeanor/felony per state); cease-and-desist; damages | Human attorney review gate on all AI-generated documents; AI outputs labeled with attorney review requirement; full audit trail | 🔴 NOT MITIGATED | ⚖️ ATTORNEY REVIEW REQUIRED |
| R-002 | Fee splitting — disguised referral fee (Rule 5.4(a)) | CRITICAL | HIGH | 25/25 | Bar discipline; disgorgement of fees; civil liability; criminal charges (some states) | Flat-fee admin services model; outside counsel opinion on fee structure; no percentage-based fees from attorneys | 🔴 NOT MITIGATED | ⚖️ ATTORNEY REVIEW REQUIRED |
| R-003 | Solicitation violation (Rule 7.3) — outbound claimant contact | CRITICAL | HIGH | 25/25 | Bar discipline; damages; cease-and-desist; advertising restrictions | All outbound communications reviewed by compliance; "informational" framing; attorney-in-the-loop for solicitation content | 🔴 NOT MITIGATED | ⚖️ ATTORNEY REVIEW REQUIRED |
| R-004 | Attorney advertising rule violation (Rules 7.1-7.2, state variations) | HIGH | HIGH | 20/25 | Bar discipline; mandatory ad retraction; fines; investigation | State-specific ad template compliance; pre-approval where required (FL); ongoing monitoring | 🔴 NOT MITIGATED | ⚖️ ATTORNEY REVIEW REQUIRED |
| R-005 | Client confusion about Wheeler's role | HIGH | HIGH | 20/25 | UPL allegations; consumer fraud; FTC action | Clear, conspicuous disclosures at every touchpoint; "Wheeler is not a law firm" on all pages | 🟡 PARTIALLY MITIGATED | ⚖️ |
| R-006 | Attorney loses license mid-case | HIGH | MEDIUM | 16/25 | Client harm; malpractice liability (Wheeler not directly liable but reputational) | Active license monitoring; emergency reassignment protocol; compliance alerts | 🟡 PARTIALLY MITIGATED | ⚖️ |
| R-007 | Data breach of privileged communications | HIGH | MEDIUM | 16/25 | Attorneys-client privilege waiver, malpractice claims; state privacy penalties; reputational | End-to-end encryption; strict data segmentation; access controls; breach response plan | 🟡 PARTIALLY MITIGATED | ⚖️ |
| R-008 | Multi-jurisdictional practice violation (Rule 5.5) | HIGH | MEDIUM | 16/25 | UPL charges; court sanctions; case dismissal | Strict state-based routing; pro hac vice tracking; attorney self-certification of MJP compliance | 🟡 PARTIALLY MITIGATED | ⚖️ ATTORNEY REVIEW REQUIRED |
| R-009 | Conflict of interest — attorney fails to identify conflict | HIGH | MEDIUM | 16/25 | Malpractice; bar discipline; case disqualification | Wheeler facilitates conflict info collection but attorney bears final responsibility; conflict check documentation required | 🟡 PARTIALLY MITIGATED | ⚖️ |
| R-010 | Trust accounting violation — mishandling of funds | CRITICAL | LOW | 10/25 | Disbarment (attorney); money transmitter liability (Wheeler) | Wheeler NEVER touches IOLTA funds; fees always from attorney operating account or direct claimant payment outside IOLTA | 🟡 PARTIALLY MITIGATED | ⚖️ |
| R-011 | State-by-state regulatory sweep — coordinated multistate enforcement | HIGH | LOW-MEDIUM | 12/25 | Multi-state cease-and-desist; fines; cost of defense | Proactive compliance; licensed counsel in each state; voluntary bar consultations | 🟡 PARTIALLY MITIGATED | ⚖️ ATTORNEY REVIEW REQUIRED |
| R-012 | ABA rule change / state bar rule modernization for tech platforms | MODERATE | MEDIUM | 12/25 | Need to restructure business model; temporary operational disruption | Trade association membership; regulatory monitoring; flexible platform architecture | 🟢 MONITORING | ⚖️ |

### 10.2 Risk Response Matrix

| Risk Score | Severity | Required Response | Timeline | Owner |
|------------|----------|-------------------|----------|-------|
| 20-25 | CRITICAL | IMMEDIATE MITIGATION: Do not launch without resolution | Before launch | CEO + Outside Counsel |
| 15-19 | HIGH | STRUCTURAL MITIGATION: Must have controls in place before scaling | Before expansion | General Counsel + Compliance |
| 10-14 | MODERATE | ACTIVE MONITORING: Controls in place, reviewed quarterly | Quarterly reviews | Compliance Lead |
| 5-9 | LOW | PERIODIC REVIEW: Monitor for changes | Annual review | Compliance Team |
| 1-4 | MINOR | ACCEPT: Document risk and monitor | Best-effort monitoring | Operations |

---

## 11. IMPLEMENTATION ROADMAP

### 11.1 Phase 0: Foundation (Pre-Marketplace)

| Task | Deliverable | Owner | Timeline | ⚖️ |
|------|------------|-------|----------|-----|
| Retain outside counsel with legal ethics / attorney marketplace expertise | Engagement letter | CEO | Month 1 | ⚖️ ATTORNEY REVIEW REQUIRED |
| Obtain state-specific ethics opinions for top 5 target states (CA, FL, NY, TX, IL) | Formal ethics opinions | Outside Counsel | Months 2-4 | ⚖️ ATTORNEY REVIEW REQUIRED |
| Draft platform disclaimer and disclosure templates | Approved disclosure library | Outside Counsel | Month 2 | ⚖️ ATTORNEY REVIEW REQUIRED |
| Draft Wheeler-attorney agreement | Signed agreement template | Outside Counsel | Month 2 | ⚖️ ATTORNEY REVIEW REQUIRED |
| Implement bar license verification API integration | Automated verification system | Engineering + Compliance | Month 3 | |
| Build conflict check facilitation module | Platform feature | Engineering | Month 3 | |
| Implement data segregation architecture | Secure platform architecture | Engineering + Security | Month 3 | ⚖️ |

### 11.2 Phase 1: Controlled Launch (2-3 States)

| Task | Deliverable | Owner | Timeline | ⚖️ |
|------|------------|-------|----------|-----|
| Launch in 2-3 low-to-moderate risk states (e.g., OH, CO, GA) | Operational marketplace | CEO + Operations | Month 4 | ⚖️ |
| Onboard 10-15 verified attorneys | Attorney roster | Attorney Recruitment | Month 4 | |
| Implement daily compliance checks | Automated compliance system | Compliance | Month 4 | |
| Implement monthly compliance reviews | Compliance review process | Compliance | Month 4 | |
| Begin collecting compliance data and metrics | Compliance data | Compliance | Month 4 | |

### 11.3 Phase 2: Core Market Expansion (10 States)

| Task | Deliverable | Owner | Timeline | ⚖️ |
|------|------------|-------|----------|-----|
| Expand to top 10 states (incl. CA, FL, NY, TX) | Multi-state marketplace | CEO + Operations | Months 5-7 | ⚖️ ATTORNEY REVIEW REQUIRED per state |
| Obtain state-specific ethics opinions for expansion states | Ethics opinions | Outside Counsel | Months 5-7 | ⚖️ ATTORNEY REVIEW REQUIRED |
| Onboard additional attorneys per state coverage needs | Expanded attorney roster | Attorney Recruitment | Months 5-7 | |
| Implement state-specific compliance templates | State-specific docs | Compliance | Months 5-7 | ⚖️ |
| Begin SOC 2 Type I readiness assessment | SOC 2 readiness | Security + Compliance | Month 6 | |

### 11.4 Phase 3: National Platform (All 50 States)

| Task | Deliverable | Owner | Timeline | ⚖️ |
|------|------------|-------|----------|-----|
| Full 50-state coverage | National marketplace | CEO + Operations | Months 8-12 | ⚖️ ATTORNEY REVIEW REQUIRED per state |
| Full compliance program operational | Comprehensive compliance | Compliance | Month 10 | ⚖️ |
| SOC 2 Type II certification | SOC 2 report | Security + Compliance | Month 12 | |
| Inaugural annual compliance audit | Full audit report | External Auditor | Month 12 | ⚖️ ATTORNEY REVIEW REQUIRED |
| First independent ethics opinion cycle (all high-risk states) | Formal opinions | Outside Counsel | Month 12 | ⚖️ ATTORNEY REVIEW REQUIRED |

---

## 12. APPENDICES

### Appendix A: Key State Bar Rules Citations

| State | Fee Splitting Rule | Advertising Rule | UPL Statute | Referral Service Rule |
|-------|-------------------|-----------------|-------------|----------------------|
| California | CA Rule 1.5-1.6 | CA Rule 7.1-7.5 | CA Bus. & Prof. Code Sections 6125-6135 | CA Rule 7.2-7.4 |
| New York | NY Rule 5.4 | 22 NYCRR 1200.8 | NY Jud. Law Sec. 478-479 | NY Jud. Law Sec. 495 |
| Florida | FL Rule 4-5.4 | FL Rule 4-7.1 | FL Statute 454.23 | FL Rule 4-7.2 |
| Texas | TX Rule 5.04 | TX Rule 7.01-7.07 | TX Gov. Code Sec. 81.101-81.104 | TX Rule 7.03 |
| Illinois | IL Rule 5.4 | IL Rule 7.1-7.3 | 705 ILCS 205/1 | IL Supreme Court Rules 721-724 |

### Appendix B: ACA (Attorney Compliance Acknowledgment) Template

The Attorney Compliance Acknowledgment is signed by each attorney upon onboarding:

```
I, [Attorney Name], Bar Number [Number], licensed in [State(s)], acknowledge and agree:

1. I am an independent legal professional and not an employee, agent, or partner of Wheeler.
2. I retain full independent professional judgment in all legal matters.
3. I am solely responsible for:
   a. My ethical obligations under my state's Rules of Professional Conduct
   b. Conflict checking and resolution
   c. Compliance with advertising and solicitation rules
   d. My trust accounting and IOLTA compliance
   e. Communication and fee arrangements with my clients
4. I will not share any portion of my legal fees with Wheeler.
5. Wheeler's platform services are administrative/technology services, not legal services.
6. I will maintain current malpractice insurance as required by [State] rules.
7. I will notify Wheeler immediately of any change in my bar status, disciplinary action, or malpractice coverage.
8. I will maintain the confidentiality of all client information as required by applicable ethics rules.

Signed: ________________________   Date: ________
```

### Appendix C: Claimant Disclosure Template

Presented to claimants at first contact with the platform:

```
IMPORTANT INFORMATION ABOUT WHEELER MARKETPLACE

Wheeler is NOT a law firm. We do not provide legal services or legal advice.
We are a technology platform that connects people with attorneys.

- Each attorney on our platform is an independent legal professional, NOT an employee of Wheeler
- Your attorney-client relationship is with the attorney, NOT with Wheeler
- You have the RIGHT to choose your own attorney — you are not required to use any attorney on our platform
- You may choose to pursue your claim WITHOUT an attorney
- You may fire your attorney and hire a different one at any time
- Wheeler does not guarantee any outcome in your case
- Wheeler receives compensation from participating attorneys for [marketing services / platform services]
- Your information will be shared with attorneys for the purpose of evaluating whether they can assist you

You should carefully review any engagement agreement provided by an attorney before signing.
If you have questions about your legal rights or the engagement agreement, ask your attorney.

CONSULT AN INDEPENDENT ATTORNEY BEFORE SIGNING ANY DOCUMENTS.
```

### Appendix D: State Bar Contact Directory (Compliance Team)

| State | Bar Association | Discipline/Complaint Contact | Advertising Filing | UPL Reporting |
|-------|----------------|------------------------------|-------------------|---------------|
| [All 50 states + DC] | [Name + URL] | [Phone + email] | [Filing address/portal] | [Phone + email] |

> **Note:** Maintained as a separate operational document within the compliance team. Updated quarterly.

### Appendix E: Related Documents

| Document | Location | Description |
|----------|----------|-------------|
| State Compliance Matrix | `/root/legal-compliance-os/STATE_COMPLIANCE_MATRIX.md` | State-by-state regulatory analysis for surplus funds recovery |
| Surplus Funds Rulebook | `/root/legal-compliance-os/SURPLUS_FUNDS_RULEBOOK.md` | Comprehensive guide to surplus funds legal framework |
| Compliance Gap Report | `/root/legal-compliance-os/COMPLIANCE_GAP_REPORT.md` | Phase 1 gap identification and remediation roadmap |
| Legal Risk Audit | `/root/legal-compliance-os/LEGAL_RISK_AUDIT.md` | Full legal risk assessment across all Wheeler operations |
| Contract Governance System | `/root/legal-compliance-os/CONTRACT_GOVERNANCE_SYSTEM.md` | Contract management and governance framework |

---

## DOCUMENT GOVERNANCE

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-05-25 | Wheeler AI Ops — Attorney Marketplace Compliance Architecture Division | Initial framework |

**Review Schedule:** Quarterly legal review by outside counsel.  
**Next Review:** 2026-08-25  
**Owner:** Wheeler General Counsel (to be appointed)  

---

*END OF DOCUMENT — ATTORNEY MARKETPLACE COMPLIANCE FRAMEWORK v1.0*
