# Phase 5: Outreach Compliance Framework

**Document Classification**: INTERNAL — Attorney-Client Privileged / Work Product
**Version**: 1.0
**Effective Date**: 2026-05-25
**Owner**: Wheeler Ecosystem — Outreach Compliance Architect
**Review Cycle**: Quarterly + upon regulatory change

> **LEGAL DISCLAIMER**: This document is a compliance framework and operational guide. It does NOT constitute legal advice. All legal conclusions herein are marked with ⚖️ and require independent review by qualified legal counsel before reliance. Wheeler Ecosystem must engage outside counsel admitted in each jurisdiction where outreach occurs.

---

## Table of Contents

1. [Regulatory Framework](#1-regulatory-framework)
2. [Consent Management System](#2-consent-management-system)
3. [Opt-Out & Suppression](#3-opt-out--suppression)
4. [Message Approval Workflow](#4-message-approval-workflow)
5. [Channel-Specific Compliance](#5-channel-specific-compliance)
6. [State-by-State Outreach Restrictions Quick Reference](#6-state-by-state-outreach-restrictions-quick-reference)
7. [Monitoring & Enforcement](#7-monitoring--enforcement)
8. [Technology Requirements](#8-technology-requirements)
9. [Compliant Outreach Playbooks](#9-compliant-outreach-playbooks)
10. [Training & Governance](#10-training--governance)
11. [Incident Response & Litigation Preparedness](#11-incident-response--litigation-preparedness)
12. [Vendor & Partner Compliance](#12-vendor--partner-compliance)

---

## 1. REGULATORY FRAMEWORK

### 1.1 TCPA (Telephone Consumer Protection Act) — THE BIGGEST RISK

**Overview**: The TCPA (47 U.S.C. Section 227) is the single highest litigation risk for Wheeler Ecosystem outreach operations. Statutory damages of $500-$1,500 per violation, no cap, coupled with class action exposure, make TCPA compliance existential.

#### 1.1.1 Autodialer (ATDS) Definition

**Federal standard (post-Facebook v. Duguid, 2021)** :
- To qualify as an Automatic Telephone Dialing System (ATDS), a system must "use a random or sequential number generator" to store or produce phone numbers and dial them.
- ⚖️ Most SMS platforms, predictive dialers, and power dialers used in modern outreach do NOT meet this definition IF they dial from a predefined list of numbers without random/sequential number generation.
- ⚖️ However, the FCC has not issued definitive post-Duguid guidance. Circuit courts are split. Conservative interpretation: assume any system that can dial automatically or from a list could be deemed an ATDS.

**State law divergence**:
- **Florida (FTSA)**: Florida's Telephone Solicitation Act explicitly defines ATDS more broadly than Duguid — includes any system that "automatically selects or dials telephone numbers." ⚖️ THIS IS A TRAP FOR NATIONAL OPERATIONS. A system that is TCPA-compliant federally may violate the FTSA.
- **Oklahoma**: Similar broad definitions.
- **Other states**: Monitor for copycat legislation.

**Wheeler Policy**: ⚖️ TREAT ALL AUTOMATED OUTREACH SYSTEMS AS ATDS UNTIL OUTSIDE COUNSEL CONFIRMS OTHERWISE. Assume the most restrictive standard (FTSA-level) for system design.

#### 1.1.2 Prior Express Written Consent (PEWC)

**Required when**: Telemarketing calls/texts to cell phones using ATDS or prerecorded/artificial voice messages.

**Elements of valid PEWC**:
1. **Clear and conspicuous disclosure** — That by providing consent, the consumer authorizes the caller to deliver telemarketing calls/texts using an autodialer or prerecorded voice.
2. **No condition of purchase** — Consent cannot be required as a condition of purchasing any good or service.
3. **Specific identification** — Must identify the specific entity being authorized to call (no "lead gen" consent passing).
4. **Consumer's telephone number** — The specific number being consented to.
5. **Consumer's signature** — Electronic signature acceptable (E-SIGN Act compliant).
6. **Written agreement** — The consent must be in writing (electronic OK).

**Consent language template (SMS)** :

> By providing your mobile number and clicking [Submit], you consent to receive autodialed SMS/text messages from Wheeler Ecosystem regarding your surplus funds claim at the number provided. Consent is not required as a condition of receiving information about your claim. Msg & data rates may apply. Reply HELP for help, STOP to cancel.

**Consent language template (Voice AI)** :

> By providing your phone number and signing below, you consent to receive autodialed calls and prerecorded messages from Wheeler Ecosystem regarding your surplus funds claim at the number provided. You understand that consent is not required as a condition of receiving information about your claim.

**Consent language template (Email Marketing)** :

> I agree to receive commercial email communications from Wheeler Ecosystem regarding surplus funds recovery services. I understand I may unsubscribe at any time.

#### 1.1.3 DNC (Do Not Call) Registry

**Requirements**:
- **National DNC Registry scrubbing**: All phone numbers must be scrubbed against the National DNC Registry before any telemarketing call or text.
- **Frequency**: Scrub at least every 31 days (FCC regulation). ⚖️ Best practice: scrub daily.
- **Internal DNC list**: Wheeler must maintain its own internal DNC list of consumers who have requested not to be contacted. This list is SEPARATE from the National DNC Registry and must be honored immediately.
- **Retention**: DNC records must be maintained for 5 years.
- **Exceptions**: Prior express written consent overrides DNC status for that specific caller. Existing business relationship exception for non-telemarketing calls.
- **Safe harbor**: Wheeler can avoid liability if it demonstrates that (a) it has established and implemented written DNC procedures, (b) it trains personnel in DNC requirements, (c) it maintains and records DNC requests, and (d) any violation was an error despite compliance with procedures.

#### 1.1.4 Revocation of Consent

**Rule**: Consumers may revoke consent at any time "by any reasonable means."

**What counts as revocation**:
- Saying "stop calling" during a live call
- Sending "STOP" in reply to an SMS
- Emailing a request to stop contact
- Telling a representative during any interaction
- ⚖️ Courts have broadly interpreted "any reasonable means." Assume ANY expression of desire to stop contact is a valid revocation.

**Wheeler Protocol**:
- All revocation requests must be processed in real time (automated for SMS, same-day for manual channels).
- Revocation is cross-channel — stop all outreach, not just the channel through which revocation was received.
- Confirmation of opt-out must be sent (for SMS/email channels).
- No further outreach permitted after revocation EXCEPT: one final confirmation message confirming opt-out, and legally required communications (e.g., statutory notices).

#### 1.1.5 Reassigned Numbers

**Risk**: The TCPA treats calls to reassigned numbers as calls to the NEW subscriber without consent. ⚖️ Liability attaches if Wheeler does not know and should not know the number has been reassigned.

**Safe harbor**:
- **One-call safe harbor**: Wheeler may make ONE call to a reassigned number without liability if it had consent from the prior subscriber.
- **Reassigned Number Database (RND)**: Wheeler must use the FCC's Reassigned Number Database or an approved commercial alternative.
- **Frequency**: Check before each campaign or at a minimum every 30 days.

**Wheeler Protocol**:
- New number acquisition: Reassigned number check required.
- Before any call/SMS campaign: RND scrub required.
- No call or text to any number that has been reassigned within the past 18 months (or longer if data available).

#### 1.1.6 State Mini-TCPA Laws

| State | Law | Key Provisions | Risk Level |
|-------|-----|----------------|------------|
| Florida | FTSA (Fla. Stat. 501.059) | Broader ATDS than TCPA; private right of action; $500-$1,500 per violation; no cap; 4-year statute of limitations | ⚖️ CRITICAL |
| Oklahoma | Okla. Stat. tit. 15, Section 775-778 | Broader autodialer restrictions | HIGH |
| Washington | RCW 80.36.390 | Prohibits use of ATDS without prior express consent; broad interpretation | HIGH |
| California | Cal. Pub. Util. Code Section 2871-2876 | State-level restrictions; aggressive AG | HIGH |
| Michigan | MCL 484.110-484.140 | Registration required for telemarketers | MEDIUM |
| Indiana | IC 24-4.7-1-1 et seq. | Restrictions on automated calls | MEDIUM |
| Missouri | RS Mo. 407.1095-407.1115 | State ATDS restrictions | MEDIUM |
| Texas | Tex. Bus. & Com. Code 302.001-302.052 | Registration required; restrictions on automated calls | MEDIUM |

**Wheeler Policy**: ⚖️ Engage outside counsel for state-specific analysis in ALL states where outreach occurs. Do not rely on federal TCPA compliance alone.

---

### 1.2 CAN-SPAM Act (Email)

**Overview**: The Controlling the Assault of Non-Solicited Pornography And Marketing Act (15 U.S.C. Sections 7701-7713) governs commercial email.

#### 1.2.1 Key Requirements

| Requirement | Detail | Verification Method |
|-------------|--------|---------------------|
| Accurate header info | From, To, Reply-To must accurately identify sender | Pre-send template review |
| Non-deceptive subject line | Subject must not be misleading | Pre-send template review |
| Identify as advertisement | If commercial — clear and conspicuous disclosure (does NOT need to say "AD" specifically, but must be identifiable) | Pre-send template review |
| Physical postal address | Valid physical address of sender | Template check |
| Opt-out mechanism | Functional email or web-based opt-out; must be easy to find and use | Monthly functional test |
| Honor opt-outs | Process within 10 business days | Weekly audit |

#### 1.2.2 Key CAN-SPAM Distinctions

- **No private right of action**: Only FTC, state AGs, and ISP can sue. ⚖️ However, state AG enforcement is increasing. Also, CAN-SPAM does not preempt state laws prohibiting falsification of email headers (fraud/deception claims survive).
- **Transactional vs. Commercial**: Transactional/relationship emails have fewer restrictions. Wheeler must classify each email correctly.
- **Primary purpose test**: If the primary purpose is commercial, CAN-SPAM applies in full. If transactional with a commercial component, mixed message rules apply.

#### 1.2.3 Wheeler Email Classification

| Email Type | Classification | CAN-SPAM Fully Applicable? | Opt-Out Required? |
|------------|---------------|---------------------------|-------------------|
| Claim status notification | Transactional | No | No |
| Document request follow-up | Transactional | No | No |
| Surplus funds recovery service pitch | Commercial | Yes | Yes |
| Attorney network enrollment invitation | Commercial | Yes | Yes |
| Newsletter / educational content | Commercial (mixed) | Usually yes | Yes |
| Legal/statutory notice | Non-commercial | No | No |

---

### 1.3 State Solicitation Laws

#### 1.3.1 Surplus Funds Claimant Solicitation

Many states specifically regulate the solicitation of foreclosure surplus funds claimants. ⚖️ This is a specialized area of law requiring state-by-state analysis.

**Common restrictions**:
- **Bar on direct solicitation**: Some states prohibit direct solicitation of foreclosure surplus claimants within a certain period after foreclosure (e.g., 30-90 days).
- **Finder's fee restrictions**: Limits on fees that can be charged for surplus funds recovery services.
- **Disclosure requirements**: Affirmative disclosure that the claimant may be entitled to funds without paying a third party (sometimes called "claimant's rights disclosure").
- **Contract requirements**: Specific language, cooling-off periods, right to rescind.

#### 1.3.2 Attorney Advertising Rules (ABA Model Rules 7.1-7.5)

**Applicability**: Outreach to attorneys for the attorney marketplace network must comply with state bar advertising rules.

**Key restrictions**:
- **Truthfulness**: No false or misleading communications (Rule 7.1).
- **Identification as advertisement**: Some states require "Advertisement" label on written communications (Rule 7.2).
- **Solicitation restrictions**: Rule 7.3 prohibits in-person solicitation of prospective clients for pecuniary gain. ⚖️ This may apply to Wheeler's outreach to attorneys if the goal is to generate business.
- **Referral fee disclosures**: Rule 7.2(b)(4) — disclosure of referral arrangements.
- **State-specific**: Some states PROHIBIT solicitation of attorneys for referral relationships. ⚖️ ATTORNEY REVIEW REQUIRED per state.

**Wheeler Policy**: ⚖️ No attorney outreach program may launch without prior review by outside counsel for compliance with bar advertising rules in each state where targeted attorneys are licensed.

#### 1.3.3 Finder's Fee / Lead Generation Regulations

- **Nationwide Multistate Licensing System (NMLS)**: If Wheeler is involved in mortgage-related surplus funds, NMLS registration may be required.
- **State-specific finder's fee licensing**: Several states require licensing for finder's fee arrangements (CA, FL, NY, others).
- **Truth in Lending Act (TILA)**: If surplus funds recovery involves any extension of credit.
- **Real Estate Settlement Procedures Act (RESPA)**: If surplus funds relate to real estate transactions.

---

### 1.4 FTC Telemarketing Sales Rule (TSR)

**Applicability**: The TSR (16 CFR Part 310) applies if Wheeler engages in "telemarketing" — defined as "a plan, program, or campaign which is conducted to induce the purchase of goods or services" by use of one or more telephones.

**Key requirements**:
- **Call time restrictions**: Calls only between 8:00 AM and 9:00 PM (consumer's local time).
- **Call abandonment rate**: No more than 3% of calls answered by a person may be abandoned (if using predictive dialer).
- **Disclosure requirements**: At the beginning of the call: seller's identity, that the call is a sales call, nature of goods/services.
- **Prohibited representations**: No false or misleading statements about goods, services, investment opportunities, etc.
- **Payment restrictions**: Prohibited methods for certain payment types.
- **Caller ID transmission**: Accurate caller ID information required.

**Wheeler Policy**: ⚖️ If any Voice AI or live agent outreach includes the "inducement of purchase of goods or services," TSR compliance is required. Informational outreach about existing claims may not trigger TSR.

---

### 1.5 WhatsApp / OTT Messaging

**WhatsApp Business Policy** (as of 2026):
- **No unsolicited promotional messages**: WhatsApp prohibits sending promotional messages to users who have not opted in to receive messages from the business.
- **Opt-in required**: User must explicitly opt in to receive messages. Purchased lists, scraped numbers, or transferred opt-ins are not valid.
- **Template message approval**: All outbound messages must use pre-approved templates for first message in a conversation. Free-form messaging allowed only within 24-hour customer service window after user-initiated contact.
- **Opt-out mechanism**: Required. Users must be able to block or opt out.
- **Commerce Policy**: Specific rules for selling products/services through WhatsApp.

**Wheeler Policy**:
- WhatsApp outreach only with verified opt-in.
- No purchased or scraped WhatsApp numbers.
- Template messages must be pre-approved per WhatsApp Business requirements.
- All templates reviewed by compliance before submission to WhatsApp.

---

### 1.6 FCRA (Fair Credit Reporting Act) — Skip Tracing

**Critical Issue**: The data obtained through skip tracing (phone numbers, addresses, employment information, asset information) may constitute a "consumer report" under the FCRA (15 U.S.C. Section 1681).

**Definition**: A "consumer report" includes any communication of information bearing on a consumer's creditworthiness, credit standing, credit capacity, character, general reputation, personal characteristics, or mode of living, used or expected to be used for eligibility purposes.

**Permissible purposes (Section 604)** :
- Credit transaction involving the consumer
- Employment purposes (with written authorization)
- Insurance underwriting
- Government license eligibility
- **Legitimate business need** — for a business transaction initiated by the consumer, or to review an account to determine collection activity

**⚖️ Risk Analysis**:
- Skip tracing for locating surplus funds claimants may qualify as a "legitimate business need" under a looser reading.
- However, if skip tracing is used to identify potential claimants who have NOT initiated any transaction with Wheeler, the permissible purpose is weaker.
- If skip tracing data is used to determine whether to contact a claimant (or the method of contact), this could be a "consumer report" being used for eligibility purposes.

**Wheeler Policy**:
- ⚖️ Engage outside counsel for a definitive FCRA analysis before any skip tracing program launches.
- If skip tracing data constitutes a consumer report: (a) certify permissible purpose for each use, (b) maintain FCRA-compliant disposal procedures, (c) provide adverse action notices if data leads to denial of service.
- If skip tracing vendors provide data that qualifies as a consumer report, Wheeler must ensure vendors comply with FCRA furnisher obligations.
- Document the legal basis for each skip tracing data element used.

---

## 2. CONSENT MANAGEMENT SYSTEM

### 2.1 Consent Tiers

| Tier | Channel | Consent Level | Proof Required | Refresh Cadence |
|------|---------|--------------|----------------|-----------------|
| 0 | Direct mail | Implied (public record) | Address from public record | N/A |
| 1 | Email (informational) | Opt-out | Business relationship or legitimate interest | Annual |
| 2 | Email (marketing) | Opt-in | Affirmative consent record (timestamp, IP, channel) | Annual |
| 3 | SMS (informational) | Prior express consent | Written or verbal consent | 6 months |
| 4 | SMS (marketing) | Prior express WRITTEN consent | Signed consent + IP + timestamp + consent language version | 6 months |
| 5 | Voice AI / Robocall | Prior Express Written Consent (PEWC) — highest standard | Full consent record + call recording + E-SIGN compliant signature | 90 days |
| N/A | WhatsApp | Opt-in (per WhatsApp Business Policy) | WhatsApp opt-in event + user phone number | Per WhatsApp policy |

### 2.2 Consent Capture Requirements

#### 2.2.1 Consent Language Elements

All consent language must include, at minimum:

1. **Plain language**: No legal jargon. Readable at 8th grade level or below.
2. **Specific identification**: Name of the specific entity being authorized (Wheeler Ecosystem, LLC or specific DBA).
3. **Purpose disclosure**: The specific types of communications being authorized (SMS, calls, email).
4. **Technology disclosure**: If autodialer or prerecorded voice will be used (TCPA requirement).
5. **Non-condition language**: Statement that consent is not required as a condition of receiving the service or information.
6. **Opt-out information**: How to revoke consent.
7. **Msg & data rates may apply** (for SMS — carrier requirement).

#### 2.2.2 Consent Capture Methods

| Method | Metadata Captured | Compliance Sufficiency | Notes |
|--------|------------------|------------------------|-------|
| Web form with checkbox | Timestamp, IP address, browser fingerprint, consent language version, form URL | HIGH — PEWC-compliant if properly implemented | Preferred method for Tier 4+ |
| SMS keyword opt-in (e.g., "JOIN" to short code) | Timestamp, originating number, keyword, campaign ID | HIGH for SMS-specific consent; may not meet PEWC for voice | Carrier audit trail available |
| Paper form with wet signature | Signed form, date, witness | HIGH — best evidence | Storage and retrieval overhead |
| Voice recording | Audio recording, timestamp, caller ID | MEDIUM-HIGH — requires two-party consent in 11 states | ⚖️ STATE LAW TRAP — see two-party consent states |
| Email opt-in (reply to opt-in message) | Email header, timestamp | MEDIUM — weaker proof of specific scope | Acceptable for Tier 1-2 only |
| Call center agent notes | Agent notes, timestamp | LOW — insufficient for PEWC | Do NOT rely on for TCPA-sensitive channels |
| Third-party consent transfer | Varies | LOW — high risk of invalidity | ⚖️ High litigation risk; use only with vendor compliance certification |

#### 2.2.3 Metadata Storage Requirements

Every consent record must store:

| Field | Required | Format | Example |
|-------|----------|--------|---------|
| Consumer identifier | Yes | UUID or hashed identifier | `cns_8f3a2b...` |
| Channel(s) consented | Yes | Enum array | `["sms", "voice"]` |
| Telephone number(s) | Yes (if SMS/voice) | E.164 format | `+12065551234` |
| Email address(es) | Yes (if email) | Email format | `jdoe@example.com` |
| Consent language version | Yes | Version string | `v2.3-20260501` |
| Full consent text at time of capture | Yes | Text | (Full disclosure text) |
| Timestamp of consent | Yes | ISO 8601 UTC | `2026-05-25T14:30:00Z` |
| IP address of consent | Yes | IPv4/IPv6 | `203.0.113.42` |
| Capture method | Yes | Enum | `web_form`, `sms_keyword`, `paper_form` |
| Campaign/source identifier | Yes | String | `camp_claimant_q2_2026` |
| Proof of consent artifact | Yes | URL or reference | `s3://consent-proofs/8f3a2b.pdf` |
| Expiration/refresh date | Yes | ISO 8601 date | `2026-11-25` |
| Revocation status | Yes | Boolean + timestamp | `false` |
| Consent origin (self/third-party) | Yes | Enum | `self`, `vendor_trusted` |

### 2.3 Consent Management Platform (CMP) Requirements

**Functional requirements**:
1. **Centralized repository**: Single source of truth for all consent records across all channels.
2. **Consent version control**: Changes to consent terms trigger re-consent workflow for existing consents.
3. **Real-time consent verification**: API-based check before any outreach (response time < 100ms).
4. **Opt-out processing**: Immediate cross-channel propagation of opt-outs.
5. **Audit trail**: Complete, immutable, timestamped log of all consent lifecycle events.
6. **Data portability**: Export of all consent data in machine-readable format.
7. **Consent refresh automation**: Automated workflow for consents nearing expiration.
8. **Integration adapter layer**: Pre-built integrations with SMS gateways, email platforms, voice AI platforms, WhatsApp API.

**Security requirements**:
- Consent data encrypted at rest (AES-256) and in transit (TLS 1.3).
- Access controls: role-based with audit logging.
- SOC 2 Type II compliance or equivalent.
- Backup with RPO < 1 hour, RTO < 4 hours.

---

## 3. OPT-OUT & SUPPRESSION

### 3.1 Universal Opt-Out Rule

**Principle**: One opt-out = ALL channels suppressed for that individual.

**Processing SLA**:
- Within-system: Immediate (real-time)
- Cross-system propagation: Within 15 minutes
- Confirmation: Required for SMS and email channels within 5 minutes
- Audit log update: Real-time

**Opt-Out Confirmation Messages**:

> You have been unsubscribed from all Wheeler Ecosystem communications. No further messages will be sent. If you change your mind, you may re-subscribe at [URL]. For questions, contact [phone].

> STOPPED — You will receive no further messages from Wheeler Ecosystem. Reply HELP for help. (Standard SMS short code response)

### 3.2 Suppression Lists — Master Registry

| List # | List Name | Source | Update Cadence | Legal Basis | Retention |
|--------|-----------|--------|----------------|-------------|-----------|
| 1 | Internal DNC | Wheeler opt-outs, opt-out requests | Real-time | TCPA 47 CFR 64.1200(d) | 5 years |
| 2 | National DNC Registry | DoNotCall.gov | Every 31 days minimum | TCPA 47 USC 227(c) | Per scrubbed campaign |
| 3 | State DNC Lists | State registries | Monthly | State law | Per scrubbed campaign |
| 4 | Reassigned Numbers Database | FCC RND or approved vendor | Before every campaign | TCPA reassigned number safe harbor | Per scrubbed campaign |
| 5 | Litigation List | Court records, PACER | Weekly | Constitutional/statutory limits on contacting litigants | Ongoing |
| 6 | Attorney-Represented | Consumer disclosure, attorney notification | Real-time upon notification | Ethical rules on contacting represented parties | Ongoing |
| 7 | Deceased List | Social Security DMF, state records, obituaries | Monthly | State solicitation restrictions | 5 years |
| 8 | Bankruptcy List | PACER, bankruptcy filings | Weekly | Automatic stay (11 USC 362) | Until discharge or case closing |
| 9 | Minor List | Self-report, data verification | Upon discovery | FTC TSR, state laws | Until age of majority |
| 10 | Cease & Desist | Direct requests, attorney letters | Real-time | Common law, state statutes | Permanent |
| 11 | Fraud/Sensitive List | Known scam targets, vulnerable adults | Upon identification | FTC TSR, state elder protection laws | Ongoing |
| 12 | Competitor List | Self-identified competitors | Upon identification | Business practice | Ongoing |
| 13 | Prior Customer Dispute | Complaint records, BBB, AG complaints | Upon identification | Litigation risk reduction | 7 years |
| 14 | State-Specific Suppression | Per state AG guidance, specific state DO NOT CONTACT registries | Per state requirement | State law | Per state requirement |

### 3.3 Suppression Workflow

```
                          ┌─────────────────────┐
                          │  OUTREACH REQUEST    │
                          │  (campaign/individual)│
                          └──────────┬──────────┘
                                     │
                                     ▼
                          ┌─────────────────────┐
                          │  STEP 1: PRE-SCRUB   │
                          │  All 14 suppression  │
                          │  lists (automated)   │
                          └──────────┬──────────┘
                                     │
                          ┌──────────┴──────────┐
                          │                     │
                          ▼                     ▼
                   ┌──────────────┐    ┌──────────────┐
                   │  HIT FOUND   │    │  NO HIT      │
                   └──────┬───────┘    └──────┬───────┘
                          │                   │
                          ▼                   ▼
                   ┌──────────────┐    ┌──────────────┐
                   │  SUPPRESS    │    │  PROCEED TO  │
                   │  DO NOT      │    │  STEP 2      │
                   │  CONTACT     │    │              │
                   └──────────────┘    └──────┬───────┘
                                              │
                                              ▼
                                   ┌─────────────────────┐
                                   │  STEP 2: CONSENT    │
                                   │  CHECK (per tier)   │
                                   └──────────┬──────────┘
                                              │
                                   ┌──────────┴──────────┐
                                   │                     │
                                   ▼                     ▼
                            ┌──────────────┐    ┌──────────────┐
                            │  CONSENT     │    │  NO CONSENT  │
                            │  VALID       │    │  OR EXPIRED  │
                            └──────┬───────┘    └──────┬───────┘
                                   │                   │
                                   ▼                   ▼
                            ┌──────────────┐    ┌──────────────┐
                            │  SEND        │    │  SUPPRESS    │
                            │  OUTREACH    │    │  (do not send)│
                            └──────┬───────┘    └──────────────┘
                                   │
                                   ▼
                            ┌──────────────┐
                            │  STEP 3: LOG  │
                            │  ALL SEND    │
                            │  DECISIONS   │
                            └──────────────┘

  POST-SEND MONITORING:
  ─► Listen for opt-out replies
  ─► Check for bounce/error codes
  ─► Update suppression lists in real time
  ─► Cross-channel propagate any opt-outs
  ─► Generate daily suppression activity report
```

**Audit Log Requirements for Each Suppression Decision**:

| Field | Required |
|-------|----------|
| Consumer identifier | Yes |
| Outreach campaign ID | Yes |
| Channel | Yes |
| Suppression lists checked | Yes (list of list IDs checked) |
| Suppression hits (if any) | Yes (list IDs + match details) |
| Consent record referenced | Yes (consent record ID or null) |
| Decision (send/suppress) | Yes |
| Decision timestamp | Yes |
| System/API that made decision | Yes |
| Human override (if any) | Yes (if applicable, must include reason + approver) |

---

## 4. MESSAGE APPROVAL WORKFLOW

### 4.1 Template Governance

**Scope**: All outreach templates, scripts, and message sequences across all channels.

| Requirement | Detail | Enforcement |
|-------------|--------|-------------|
| Pre-approval | All templates approved before first use | System gate: unapproved template cannot be sent |
| Versioning | Any change = new version = re-approval; version history maintained | System gate: template edits create new version |
| Dynamic fields | Approved field list only; no free-form personalization | System validation at send time |
| A/B testing | Both variants pre-approved | System gate: test variants must be approved |
| AI-generated content | Human review mandatory before any use | System gate: AI-drafted content goes to review queue |
| Expiration | Templates expire 12 months after approval | Automated notification to compliance for review |
| Deactivation | Templates can be deactivated by compliance at any time | System gate: deactivated templates cannot be sent |

### 4.2 Approval Chain

| Tier | Channel/Content Type | Approvers | SLA | Escalation Path |
|------|---------------------|-----------|-----|-----------------|
| Tier 1 | Informational: claim status, document follow-up, service notifications | Compliance Officer | 24 hours | Compliance Manager |
| Tier 2 | Marketing: newsletters, service promotion, general outreach | Compliance Officer + Legal Counsel | 48 hours | GC |
| Tier 3 | Solicitation: direct solicitation of surplus funds claimants | Compliance Officer + Legal Counsel + ⚖️ Outside Counsel | 5 business days | GC + Outside Counsel Partner |
| Tier 4 | Financial/Legal Claims: specific financial offers, litigation referrals, claims purchase offers | Compliance Officer + Legal Counsel + ⚖️ Outside Counsel + Executive (CEO/COO) | 10 business days | Board of Directors |

### 4.3 Template Submission Requirements

Each template submission must include:

1. **Template content** — Full text with all dynamic fields clearly marked.
2. **Channel** — SMS, email, voice AI script, direct mail, WhatsApp, ad creative.
3. **Target audience** — Claimant, attorney, lead, partner.
4. **Tier classification** — Per Section 4.2.
5. **Consent tier required** — Per Section 2.1.
6. **State restrictions** — List of states where this template will be used, with any state-specific modifications.
7. **Dynamic field mapping** — Each field: definition, source system, validation rules, character limits.
8. **Legal disclosures** — All required disclosures included and positioned per regulatory requirements.
9. **Opt-out mechanism** — How the recipient can opt out.
10. **Version history** — If this is an update to an existing template, change log.

### 4.4 Template Format — Compliance Review Checklist

- [ ] Subject line not deceptive (email) / First 160 characters not misleading (SMS)
- [ ] Sender/From accurately identifies Wheeler
- [ ] Physical postal address included (email)
- [ ] Advertisement identified if commercial
- [ ] Opt-out mechanism present and functional
- [ ] Dynamic fields restricted to approved list
- [ ] No urgency/manipulation language ("act now," "limited time," "expiring")
- [ ] No false or misleading representations about claim amount or likelihood
- [ ] Required legal disclosures present (state-specific)
- [ ] Plain language (8th grade reading level or below)
- [ ] No spoofing or deceptive header information
- [ ] Call time restrictions noted (if SMS/voice)
- [ ] ⚖️ Attorney review conducted for solicitation templates
- [ ] ⚖️ State-specific restrictions checked
- [ ] Consent tier verified as adequate

---

## 5. CHANNEL-SPECIFIC COMPLIANCE

### 5.1 SMS Compliance Checklist

- [ ] **Consent verified**: Prior express written consent obtained, stored with full metadata, and not expired.
- [ ] **Number source validated**: Consumer provided phone number directly. No purchased, scraped, or third-party sourced numbers without verified individual consent.
- [ ] **National DNC scrub**: Completed within 31 days of send.
- [ ] **Reassigned number database check**: Completed before send.
- [ ] **State DNC scrub**: Completed for all applicable states.
- [ ] **Internal suppression list check**: Completed — no active opt-out, DNC, or other suppression.
- [ ] **Opt-out mechanism**: Clear and functional. "Reply STOP to opt out" included in first message; opt-out language in subsequent messages per carrier requirements.
- [ ] **Sender identification**: Sender ID / short code / toll-free number accurately identifies Wheeler.
- [ ] **Message content pre-approved**: Current approved version in template system.
- [ ] **Call time restrictions**: Sent between 8:00 AM and 9:00 PM recipient's local time zone.
- [ ] **No misleading content**: Claim amounts, timelines, or representations are accurate and not exaggerated.
- [ ] **Disclosures present**: Msg & data rates may apply; carrier liability disclaimer.
- [ ] **Frequency caps**: Maximum messages per week per campaign (recommended: 2-4 messages/week per campaign; MAX 6/week total across all campaigns).
- [ ] **Audit trail**: Complete record of send, delivery, opt-outs, and errors.
- [ ] **Toll-free number / short code compliant**: For toll-free SMS: brand registered with The Campaign Registry, campaign approved. For short codes: CTIA compliance, carrier-approved.
- [ ] **10DLC compliance**: If using 10-digit long code, must be registered with The Campaign Registry with approved campaign.

### 5.2 Email Compliance Checklist

- [ ] **Accurate header information**: From, To, Reply-To, routing information accurately identify sender.
- [ ] **Non-deceptive subject line**: Subject line accurately reflects message content.
- [ ] **Advertisement identification**: If commercial email, clearly and conspicuously identified as advertisement (can be in body — no specific "AD" label required by CAN-SPAM, but must be recognizable).
- [ ] **Physical postal address**: Valid physical address of Wheeler included in every commercial email.
- [ ] **Opt-out mechanism**: Clear, conspicuous, and functionally operable.
- [ ] **Opt-out processing**: Processed within 10 business days. Confirmation message sent.
- [ ] **Suppression list checked**: Before send.
- [ ] **Consent tier verified**: Appropriate for content type (Section 2.1).
- [ ] **Transactional vs. commercial correctly classified**: Per Section 1.2.3.
- [ ] **List hygiene**: Hard bounces suppressed. Spam complaint addresses suppressed.
- [ ] **Sending infrastructure**: DKIM, SPF, DMARC configured. Dedicated sending IP or reputable shared pool.
- [ ] **Unsubscribe link**: Operational in all commercial emails. One-click unsubscribe preferred.
- [ ] **Pre-send spam check**: Score below threshold (recommended: < 3.0 on SpamAssassin or equivalent).

### 5.3 Voice AI Compliance Checklist

- [ ] **PEWC obtained**: Prior Express Written Consent on file for TELEMARKETING calls (if applicable). For purely informational calls, prior express consent sufficient.
- [ ] **ATDS analysis**: ⚖️ Legal analysis completed for the specific dialing system. Documented for litigation defense.
- [ ] **Opening disclosure**: Within first seconds: (1) caller identity — "This is [name] calling from Wheeler Ecosystem," (2) purpose of call, (3) opt-out mechanism — "To stop receiving calls, press 9 or say 'stop'."
- [ ] **Call recording notice**: In two-party consent states, notice must be given AT START OF CALL. ⚖️ Two-party consent states: CA, CT, FL, IL, MD, MA, MI, MT, NV, NH, PA, WA (11+ states — verify current list).
- [ ] **Real-time opt-out**: Voice command ("stop," "unsubscribe") and keypress (press 9 or 0) must be recognized and honored during the call. Immediate disconnection from automated sequence.
- [ ] **DNC check**: Completed before call.
- [ ] **Reassigned number check**: Completed before call.
- [ ] **State-specific restrictions**: Checked (especially FL FTSA).
- [ ] **Human escalation**: Option to speak with a live representative must be provided.
- [ ] **AI disclosure**: If the voice agent is AI (not a human), disclosure required. ⚖️ State AI transparency laws are emerging (CA, TX, others).
- [ ] **Call time restrictions**: 8 AM - 9 PM recipient's local time.
- [ ] **Call frequency caps**: Recommended: maximum 1 call per day, 3 calls per week, 10 calls per month per number. FCC guidance: calls that are "harassing" violate TCPA regardless of consent.
- [ ] **Caller ID**: Accurate outbound caller ID (not spoofed). STIR/SHAKEN compliant.
- [ ] **Abandonment rate**: If predictive dialer used, abandonment rate under 3% per TSR (if telemarketing).
- [ ] **Audit trail**: Full recording of all calls retained per record retention policy.

### 5.4 WhatsApp Compliance Checklist

- [ ] **Opt-in obtained**: User specifically opted in to receive WhatsApp messages from Wheeler. Opt-in is per WhatsApp Business Policy requirements.
- [ ] **Opt-in source verified**: Not purchased, scraped, or transferred without consent.
- [ ] **WhatsApp Business Account**: Verified business account with approved display name.
- [ ] **Template messages**: All outbound messages use pre-approved templates for first message. Free-form messaging only within 24-hour customer service window.
- [ ] **Templates approved by WhatsApp**: All templates submitted and approved through WhatsApp Business API.
- [ ] **WhatsApp Commerce Policy**: If selling or promoting services, ensure compliance with Commerce Policy (no restricted items, accurate representations).
- [ ] **Opt-out mechanism**: Clear opt-out instruction. WhatsApp Business API supports opt-out handling.
- [ ] **Message frequency**: Reasonable frequency. No spamming.
- [ ] **Media/content restrictions**: No inappropriate content per WhatsApp's Community and Commerce Policies.
- [ ] **User privacy**: No sharing of user WhatsApp data with third parties without consent.
- [ ] **Data retention**: WhatsApp message data retained per Wheeler policy and WhatsApp's terms.
- [ ] **Audit trail**: Complete message delivery, read receipts (if enabled), and opt-out tracking.

### 5.5 Direct Mail Compliance Checklist

- [ ] **Address from public record**: Verified from public records (property records, tax records, court filings) — Tier 0 implied consent.
- [ ] **State restrictions checked**: Some states restrict solicitation of surplus funds claimants via mail.
- [ ] **Content pre-approved**: Template approved per Tier 1-2 (depending on content).
- [ ] **Deceased list scrub**: No deceased individuals.
- [ ] **Bankruptcy list scrub**: No individuals under automatic stay.
- [ ] **Litigation list scrub**: No active litigants.
- [ ] **Attorney-represented list scrub**: No individuals known to be represented.
- [ ] **Opt-out mechanism**: Method to opt out of future mailings included (phone number, website, reply card).
- [ ] **No deceptive content**: Claim amounts, timelines, or representations accurate.
- [ ] **Disclosures present**: Required state-specific disclosures.
- [ ] **Return address**: Accurate return address for returned mail processing.
- [ ] **Do not mail indicator**: If recipient returns mail or requests no further mail, add to suppression.

### 5.6 Retargeting Ads Compliance Checklist

- [ ] **Privacy policy**: Clear disclosure of data collection and use for ad retargeting.
- [ ] **Opt-out mechanism**: Method to opt out of retargeting (per-platform opt-out mechanisms).
- [ ] **Platform policies**: Compliance with Meta (Facebook/Instagram), Google, and other platform-specific retargeting policies.
- [ ] **Sensitive data restriction**: No use of sensitive data for ad targeting (health, financial hardship, protected classes).
- [ ] **Claimant data use restriction**: ⚖️ Use of surplus funds claimant data for retargeting may raise FCRA and state law concerns.
- [ ] **Deceptive ads**: No false or misleading ad content.
- [ ] **State privacy laws**: CCPA/CPRA compliance for California residents; other state privacy laws (VA, CO, CT, UT, etc.).

---

## 6. STATE-BY-STATE OUTREACH RESTRICTIONS QUICK REFERENCE

### 6.1 Master Table

| State | SMS Allowed? | Email Allowed? | Direct Mail Allowed? | Voice AI Allowed? | Special Restrictions | Risk Tier |
|-------|-------------|----------------|---------------------|-------------------|---------------------|-----------|
| AL | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing registration | MEDIUM |
| AK | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| AZ | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing registration | MEDIUM |
| AR | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| CA | ⚖️ Conditional | Yes | Yes | ⚖️ HIGH RISK | CCPA/CPRA; strict state DNC; aggressive AG; two-party consent for recording; BIPA risk for voice AI; Prop 24 | ⚖️ CRITICAL |
| CO | Yes (with consent) | Yes | Yes | Yes (with consent) | CPA privacy law; state DNC | MEDIUM |
| CT | Yes (with consent) | Yes | Yes | Yes (with consent) | Privacy law; two-party consent for recording | MEDIUM |
| DE | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| FL | ⚖️ HIGH RISK | Yes | Yes | ⚖️ CRITICAL | FTSA — broadest ATDS definition; private right of action; $500-$1,500 per violation; 4-year statute of limitations; DNC requirements; ⚖️ ATTORNEY REVIEW REQUIRED | ⚖️ CRITICAL |
| GA | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW-MEDIUM |
| HI | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| ID | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| IL | ⚖️ Conditional | Yes | Yes | ⚖️ HIGH RISK | BIPA — if any biometric data in voice AI; aggressive consumer protection laws; two-party consent for recording; state DNC | ⚖️ HIGH |
| IN | Yes (with consent) | Yes | Yes | Yes (with consent) | Telemarketing registration; automated call restrictions | MEDIUM |
| IA | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| KS | Yes (with consent) | Yes | Yes | Yes (with consent) | Telemarketing registration; automated call restrictions | MEDIUM |
| KY | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| LA | Yes (with consent) | Yes | Yes | Yes (with consent) | Telemarketing registration | MEDIUM |
| ME | Yes (with consent) | Yes | Yes | Yes (with consent) | State-specific privacy law effective 2025; strict DNC | MEDIUM-HIGH |
| MD | Yes (with consent) | Yes | Yes | Yes (with consent) | Two-party consent for recording; state DNC | MEDIUM |
| MA | Yes (with consent) | Yes | Yes | Yes (with consent) | Two-party consent for recording; strict AG enforcement; state DNC | MEDIUM-HIGH |
| MI | Yes (with consent) | Yes | Yes | Yes (with consent) | Two-party consent for recording; telemarketing registration | MEDIUM |
| MN | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules; state DNC | MEDIUM |
| MS | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| MO | Yes (with consent) | Yes | Yes | Yes (with consent) | Automated call restrictions; telemarketing registration | MEDIUM |
| MT | Yes (with consent) | Yes | Yes | Yes (with consent) | Two-party consent for recording | MEDIUM |
| NE | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| NV | Yes (with consent) | Yes | Yes | Yes (with consent) | Two-party consent for recording; state DNC | MEDIUM |
| NH | Yes (with consent) | Yes | Yes | Yes (with consent) | Two-party consent for recording | MEDIUM |
| NJ | Yes (with consent) | Yes | Yes | Yes (with consent) | State-specific telemarketing laws; no surcharge law | MEDIUM |
| NM | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| NY | ⚖️ Conditional | Yes | Yes | ⚖️ HIGH RISK | Aggressive AG; CCPA-style bill pending; Do Not Call laws; specific surplus funds solicitation rules may apply; ⚖️ ATTORNEY REVIEW RECOMMENDED | ⚖️ HIGH |
| NC | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules; state DNC | MEDIUM |
| ND | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| OH | Yes (with consent) | Yes | Yes | Yes (with consent) | Telemarketing registration; state DNC | MEDIUM |
| OK | Yes (with consent) | Yes | Yes | ⚖️ HIGH RISK | Broad autodialer restrictions; DNC requirements; ⚖️ ATTORNEY REVIEW RECOMMENDED | ⚖️ HIGH |
| OR | Yes (with consent) | Yes | Yes | Yes (with consent) | State DNC; privacy law | MEDIUM |
| PA | Yes (with consent) | Yes | Yes | Yes (with consent) | Two-party consent for recording; telemarketing registration | MEDIUM |
| RI | Yes (with consent) | Yes | Yes | Yes (with consent) | State DNC | LOW-MEDIUM |
| SC | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| SD | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| TN | Yes (with consent) | Yes | Yes | Yes (with consent) | State DNC | MEDIUM |
| TX | Yes (with consent) | Yes | Yes | Yes (with consent) | Telemarketing registration; automated call restrictions; state DNC | MEDIUM |
| UT | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules; privacy law | MEDIUM |
| VT | Yes (with consent) | Yes | Yes | Yes (with consent) | State DNC | LOW-MEDIUM |
| VA | Yes (with consent) | Yes | Yes | Yes (with consent) | VCDPA privacy law; state DNC | MEDIUM |
| WA | ⚖️ Conditional | Yes | Yes | ⚖️ HIGH RISK | My Health My Data Act (broad "consumer health data" definition); two-party consent for recording; aggressive AG enforcement; ⚖️ ATTORNEY REVIEW RECOMMENDED | ⚖️ HIGH |
| WV | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| WI | Yes (with consent) | Yes | Yes | Yes (with consent) | State DNC | LOW-MEDIUM |
| WY | Yes (with consent) | Yes | Yes | Yes (with consent) | General telemarketing rules | LOW |
| DC | Yes (with consent) | Yes | Yes | Yes (with consent) | District-specific rules; telemarketing registration | MEDIUM |

### 6.2 High-Risk States — Detailed Analysis

#### Florida — ⚖️ CRITICAL RISK

**Florida Telephone Solicitation Act (FTSA)** — Fla. Stat. Section 501.059:

- **Broader ATDS definition** than federal TCPA: "an automated system for the selection or dialing of telephone numbers." Does NOT require random/sequential number generation per Duguid.
- **Private right of action**: Individual and class action available.
- **Damages**: $500 per violation (negligent), $1,500 per violation (willful/knowing). No cap.
- **Statute of limitations**: 4 years (vs. TCPA's 4 years, but courts may apply different rules).
- **DNC requirements**: Separate state DNC registry with additional requirements.
- **Content requirements**: Specific disclosure requirements for telemarketing calls.
- **Risk**: The FTSA is the most aggressive state telemarketing law in the country. Multiple class action firms actively litigate FTSA claims.

**Wheeler Policy**:
- ⚖️ No SMS or Voice AI outreach to Florida residents without separate legal analysis and written sign-off from outside counsel.
- If outreach is conducted in Florida, consent must meet FTSA standards (which exceed TCPA standards).
- Monthly legal monitoring for FTSA developments.

#### California — ⚖️ CRITICAL RISK

- **CCPA/CPRA**: Strongest state privacy law. Broad consumer rights, private right of action for data breaches.
- **AG enforcement**: Aggressive enforcement across consumer protection, privacy, and telemarketing.
- **Two-party consent**: Recording of calls requires consent of ALL parties. ⚖️ Voice AI calls must include recording notice and obtain consent for recording.
- **Proposition 24 (CPRA)**: Additional privacy requirements effective 2023+.
- **Invasion of privacy claims**: California courts recognize strong privacy torts.
- **Specific surplus funds regulations**: May exist — ⚖️ ATTORNEY REVIEW REQUIRED.

#### Illinois — ⚖️ HIGH RISK

- **BIPA (Biometric Information Privacy Act)**: If any Voice AI system processes biometric data (voiceprints, facial recognition), BIPA applies. Private right of action. $1,000-$5,000 per violation. Class actions common.
- **Two-party consent**: Call recording consent from all parties required.
- **Consumer protection**: Aggressive enforcement by AG and private plaintiffs.

#### Washington — ⚖️ HIGH RISK

- **My Health My Data Act**: Extremely broad definition of "consumer health data" that could include surplus funds claim status, financial hardship, or court proceeding involvement. ⚖️ This law is NEW and untested — conservative interpretation recommended.
- **Two-party consent for recording**.
- **State DNC with aggressive enforcement**.

#### New York — ⚖️ HIGH RISK

- **Aggressive AG**: AG James has pursued telemarketing and consumer protection cases aggressively.
- **Surplus funds regulations**: NY may have specific surplus funds recovery solicitation rules. ⚖️ ATTORNEY REVIEW REQUIRED.
- **Do Not Call laws**: State-specific DNC requirements.

#### Oklahoma — ⚖️ HIGH RISK

- **Broad state telemarketing restrictions**: Autodialer and DNC restrictions.
- **Surplus funds**: May have specific claimant protections.

### 6.3 State-Specific Surplus Funds Solicitation Bans

**⚠️ CRITICAL**: Several states have specific laws or AG guidance restricting or prohibiting the solicitation of foreclosure surplus funds claimants. This list is indicative only — ⚖️ ATTORNEY REVIEW REQUIRED for each state:

- States with known restrictions on surplus funds solicitation: FL, NY, CA, IL, TX, OH (verify current status).
- Common restrictions: No solicitation within [X] days of foreclosure, disclosure that claimant can recover without paying a third party, contract cooling-off period, fee limitations.
- **Wheeler Policy**: ⚖️ No surplus funds claimant outreach in any state without affirmative legal analysis confirming permissibility.

---

## 7. MONITORING & ENFORCEMENT

### 7.1 Key Performance Indicators (KPIs)

| Metric | Channel(s) | Target | Threshold | Alert Trigger |
|--------|-----------|--------|-----------|---------------|
| Delivery rate | SMS, Email | > 97% | < 95% | Amber: < 95%; Red: < 90% |
| Opt-out rate per campaign | All | < 0.5% | > 1.0% | Investigation at > 0.5% |
| Spam complaint rate | Email | < 0.1% | > 0.08% | Amber: > 0.08%; Red: > 0.1% (Google/Yahoo threshold) |
| Block rate | SMS | < 2% | > 5% | Investigation at > 3% |
| Call answer rate | Voice AI | > 40% | < 25% | Investigation at < 25% |
| TCPA complaints received | All | 0 | Any | Any complaint = immediate escalation |
| State AG complaints | All | 0 | Any | Any complaint = legal hold + immediate escalation |
| FTC complaints | All | 0 | Any | Any complaint = immediate escalation |
| CTIA/carrier complaints | SMS | 0 per month | > 3 | Amber: > 1; Red: > 3 |
| Bounce rate (hard) | Email | < 2% | > 5% | Investigation at > 3% |
| Opt-out processing time | All | < 1 hour | > 24 hours | Amber: > 4 hours; Red: > 24 hours |
| Suppression list age | All | < 7 days | > 31 days | Red: > 31 days (DNC violation risk) |
| Consent validation rate | All | 100% | < 100% | Any send without valid consent = immediate stop |

### 7.2 Audit Schedule

| Audit Type | Frequency | Scope | Performed By | Report To |
|------------|-----------|-------|-------------|-----------|
| Opt-out processing audit | Weekly | Sample of 100 opt-out events: verify processing time, cross-channel propagation, confirmation sent | Compliance Officer | Compliance Manager |
| Suppression list integrity audit | Weekly | Verify all 14 suppression lists are current and integrated | Compliance Officer | Compliance Manager |
| Consent validity audit | Monthly | Sample of active consents: verify metadata completeness, consent language version, expiration dates | Compliance Officer | GC |
| Template compliance review | Monthly | All active templates reviewed for regulatory compliance and accuracy | Compliance Officer + Legal | GC |
| DNC registry scrub audit | Monthly | Verify national + state DNC scrubs completed within 31 days | Compliance Officer | Operations Director |
| Channel compliance audit | Quarterly | Deep audit of one channel: full trace from consent to send to opt-out | Compliance Officer + Legal + Outside Counsel | GC + CEO |
| Vendor compliance audit | Quarterly | Verify all outreach vendors are contractually compliant | Compliance Officer | GC |
| Third-party compliance audit | Annually | Outside counsel-led full outreach compliance audit | Outside Counsel | Board of Directors |
| Technology compliance review | Annually | CMP, suppression, and outreach systems compliance review | CTO + Compliance Officer | GC + CEO |

### 7.3 Violation Response Protocol

```
  PHASE 1: DISCOVERY
  ─► Internal detection (monitoring alert, employee report)
  ─► External detection (consumer complaint, AG inquiry, lawsuit service)
  ─► Automated detection (compliance system flag)
     │
     ▼
  PHASE 2: IMMEDIATE CONTAINMENT (Within 1 Hour)
  ─► Cease all affected outreach immediately
  ─► Isolate affected campaign(s), channel(s), segment(s)
  ─► Preserve all evidence (logs, records, recordings)
  ─► Notify: Compliance Officer ─► Legal Counsel ─► GC
  ─► Place litigation hold on all relevant data
     │
     ▼
  PHASE 3: INVESTIGATION (Within 24-72 Hours)
  ─► Determine root cause
  ─► Identify scope: affected consumers, messages, time period
  ─► Assess legal exposure (per-violation count × $500-$1,500)
  ─► Identify regulatory reporting obligations
  ─► Document findings
     │
     ▼
  PHASE 4: REMEDIATION (Within 1 Week)
  ─► Fix root cause (system, process, training)
  ─► Remediate affected consumers (notification, cure, compensation if appropriate)
  ─► Re-train relevant personnel
  ─► Update procedures to prevent recurrence
  ─► Verify fix
     │
     ▼
  PHASE 5: REGULATORY ASSESSMENT (Within 1 Week)
  ─► ⚖️ Determine disclosure obligations to FTC, FCC, state AGs
  ─► ⚖️ Assess litigation risk (class action potential)
  ─► Prepare regulatory response if required
  ─► ⚖️ Engage outside counsel for litigation assessment
     │
     ▼
  PHASE 6: DISCLOSURE DECISION (Within 2 Weeks)
  ─► ⚖️ GC + CEO + Outside Counsel decide on disclosure
  ─► If disclosure required: prepare notification, file, manage public response
  ─► Document decision rationale
     │
     ▼
  PHASE 7: CLOSURE
  ─► Final incident report
  ─► Board notification (if required)
  ─► Compliance program enhancement
  ─► Lessons learned
```

### 7.4 Complaint Handling

| Complaint Source | Response SLA | Handling Procedure | Reporting |
|-----------------|-------------|-------------------|-----------|
| Direct consumer complaint (phone, email, web) | 24 hours | Log → Investigate → Respond → Update suppression → Close | Weekly complaint summary to compliance |
| SMS STOP/HELP reply | Real-time | Automated opt-out processing | Daily opt-out report |
| CTIA/carrier complaint | 48 hours | Log → Investigate carrier report → Respond to carrier → Remediate | Immediate escalation to GC |
| FTC complaint | 5 business days | Log → Investigate → Prepare response → GC review → Respond | Legal hold + GC notification |
| State AG complaint | 5 business days | Log → Legal hold → Investigate → ⚖️ Outside counsel engaged → Respond | Immediate escalation to GC + CEO |
| Lawsuit service | 1 hour | Legal hold → GC notification → ⚖️ Outside counsel engaged → DO NOT RESPOND directly | Immediate escalation to GC + CEO |
| BBB complaint | 10 business days | Log → Investigate → Respond → Close | Monthly summary |
| Platform complaint (Meta, Google, WhatsApp) | Per platform SLA | Log → Investigate → Respond per platform guidelines | Immediate escalation to compliance |

---

## 8. TECHNOLOGY REQUIREMENTS

### 8.1 Core Systems Architecture

```
                          ┌─────────────────────────────┐
                          │   CONSENT MANAGEMENT PLATFORM │
                          │   (Centralized repository)    │
                          │   - Consent records           │
                          │   - Consent version control   │
                          │   - Opt-out processing        │
                          │   - Audit log                 │
                          └──────────┬──────────────────┘
                                     │ API
                                     ▼
              ┌────────────────────────────────────────┐
              │         COMPLIANCE GATEWAY             │
              │   (Real-time consent + suppression check)│
              │   - Pre-send verification API          │
              │   - Suppression list aggregation       │
              │   - DNC scrub orchestration             │
              │   - Audit log production                │
              └──────┬──────────┬──────────┬───────────┘
                     │          │          │
              ┌──────┴──┐ ┌────┴────┐ ┌───┴────────┐
              │ SMS     │ │ Email  │ │ Voice AI   │
              │ Gateway │ │ Gateway │ │ Platform   │
              └─────────┘ └─────────┘ └────────────┘
                     │          │          │
              ┌──────┴──────────┴──────────┴───────────┐
              │         SUPPRESSION LAYER              │
              │   - Internal DNC (real-time)           │
              │   - National DNC (31-day scrub)        │
              │   - State DNC integration              │
              │   - Reassigned Number DB               │
              │   - All special lists (litigation,     │
              │     bankruptcy, deceased, etc.)        │
              └────────────────────────────────────────┘
```

### 8.2 System Requirements by Component

#### 8.2.1 Consent Management Platform (CMP)

| Requirement | Specification | Priority |
|-------------|--------------|----------|
| Consent record capacity | 10M+ records | Critical |
| Record API latency | < 100ms P95 | Critical |
| Opt-out propagation | Real-time, all connected channels | Critical |
| Consent versioning | Full version history with effective dates | Critical |
| Audit logging | Immutable, append-only, timestamped | Critical |
| Data encryption | AES-256 at rest, TLS 1.3 in transit | Critical |
| Access controls | RBAC with MFA | Critical |
| SOC 2 Type II | Certified or in-process | High |
| Backup RPO | < 1 hour | Critical |
| Backup RTO | < 4 hours | Critical |
| Integration adapters | SMS gateway(s), email platform, voice AI platform, WhatsApp API, CRM | High |
| Consent refresh automation | Automated workflow for expiring consents | Medium |

#### 8.2.2 Compliance Gateway

| Requirement | Specification | Priority |
|-------------|--------------|----------|
| Pre-send verification | Real-time API check: consent + suppression before each send | Critical |
| Suppression list aggregation | Unified query across all 14+ suppression lists | Critical |
| DNC scrub orchestration | Automated orchestration of national + state DNC scrubs | Critical |
| Reassigned Number DB integration | Automated check before SMS/voice sends | Critical |
| Decision logging | Complete record of every send decision with rationale | Critical |
| Throughput | 10,000+ verifications per second | High |
| Redundancy | Active-active, multi-region | High |

#### 8.2.3 Third-Party System Compliance Gates

Each outreach platform (SMS gateway, email service provider, voice AI platform, WhatsApp API) must have:

| Requirement | Specification |
|-------------|--------------|
| Compliance gate integration | API call to Compliance Gateway before each send |
| Channel-specific compliance rules | Platform-enforced rules per channel checklist (Section 5) |
| Template enforcement | Only pre-approved templates can be sent |
| Opt-out processing | Platform must process opt-outs and propagate to CMP |
| Audit logging | Platform must produce complete send/delivery/opt-out logs |
| Time zone enforcement | Platform must enforce 8 AM - 9 PM send time in recipient's time zone |
| Rate limiting | Platform must enforce frequency caps |
| Data retention | Platform must retain all send records per Wheeler data retention policy |

### 8.3 Data Retention Requirements

| Data Type | Retention Period | Rationale | Disposal Method |
|-----------|-----------------|-----------|-----------------|
| Consent records | Duration of relationship + 7 years | Statute of limitations; regulatory audits | Secure deletion |
| Opt-out records | 5 years minimum | TCPA requirement (47 CFR 64.1200(d)) | Secure deletion |
| Send records | 4 years minimum | TCPA statute of limitations; 5 years recommended | Secure deletion |
| Call recordings | 4 years minimum | TCPA / state law evidence preservation | Secure deletion |
| Audit logs | 7 years | Litigation hold readiness; regulatory audits | Secure deletion |
| Suppression list exports | Per scrubbed campaign + 4 years | Evidence of compliance | Secure deletion |
| DNC registry certifications | 5 years | TCPA safe harbor documentation | Secure deletion |
| Complaint records | 7 years | Litigation defense; regulatory audits | Secure deletion |

### 8.4 Technology Vendor Vetting

Each outreach technology vendor must be vetted for:

- **Compliance certifications**: SOC 2 Type II minimum; HIPAA if applicable; PCI DSS if processing payments.
- **TCPA compliance features**: Consent verification, DNC scrubbing, opt-out processing, time zone enforcement, frequency capping.
- **Data security**: Encryption (at rest and in transit), access controls, breach notification procedures, data processing agreement (DPA).
- **Data ownership**: Wheeler owns all data. Vendor cannot use Wheeler's data for its own purposes.
- **Audit rights**: Wheeler has the right to audit vendor's compliance controls.
- **Indemnification**: Vendor indemnifies Wheeler for vendor's compliance failures.
- **Vendor compliance monitoring**: Quarterly review of vendor compliance status; annual vendor audit.
- **Contractual compliance pass-through**: All regulatory requirements flow down to vendors via contract.

---

## 9. COMPLIANT OUTREACH PLAYBOOKS

### 9.1 Playbook 1: Cold Claimant Outreach (SMS)

**Risk Level**: ⚖️ CRITICAL — ATTORNEY REVIEW REQUIRED before any SMS outreach program launches.

```
  ┌──────────────────────────────────────────────────────────┐
  │ PRE-FLIGHT CHECKLIST                                      │
  ├──────────────────────────────────────────────────────────┤
  │ [ ] 1. ⚖️ ATTORNEY REVIEW COMPLETED for this campaign    │
  │ [ ] 2. Consent status checked for each number            │
  │ [ ] 3. National DNC scrub completed (within 31 days)     │
  │ [ ] 4. State DNC scrubs completed (per state)            │
  │ [ ] 5. Reassigned number DB check completed              │
  │ [ ] 6. Internal suppression list checked                 │
  │ [ ] 7. State solicitation rules verified (per state)     │
  │ [ ] 8. Message template approved (Tier 3 or higher)      │
  │ [ ] 9. Opt-out mechanism confirmed functional            │
  │ [ ] 10. Sender ID compliant (branded, not misleading)    │
  │ [ ] 11. Call time restrictions set (8 AM - 9 PM)         │
  │ [ ] 12. Frequency caps set (max 4/week)                  │
  │ [ ] 13. Audit trail configured and tested                │
  │ [ ] 14. Monitoring alerts configured                     │
  └──────────────────────────────────────────────────────────┘

  SEQUENCE:
  DAY 0: Introductory SMS — Identify Wheeler, reason for contact, opt-out mechanism
  DAY 3: Follow-up SMS — Additional information, CTA
  DAY 7: Final SMS — Summary, CTA, final opt-out reminder
  
  IF opt-out received at any point: STOP immediately.
  IF no response: Do not continue beyond 3 messages unless re-consented.

  POST-CAMPAIGN:
  ─► Log all sends, deliveries, bounces, opt-outs
  ─► Update suppression lists with any new opt-outs
  ─► Generate compliance report
  ─► Review opt-out rate (flag if > 0.5%)
```

### 9.2 Playbook 2: Cold Claimant Outreach (Email)

**Risk Level**: HIGH — ATTORNEY REVIEW RECOMMENDED.

```
  PRE-FLIGHT CHECKLIST:
  [ ] 1. Suppression list checked (all 14 lists)
  [ ] 2. CAN-SPAM compliance verified (Section 1.2)
  [ ] 3. State rules checked (per state)
  [ ] 4. Message template approved (Tier 2 or higher)
  [ ] 5. Opt-out link functional (tested)
  [ ] 6. Physical address included
  [ ] 7. Advertisement identified (if commercial)
  [ ] 8. DKIM/SPF/DMARC configured and passing
  [ ] 9. Pre-send spam check passed (< 3.0)
  [ ] 10. Audit trail configured

  SEQUENCE:
  DAY 0: Introduction email — Identify Wheeler, reason for contact, opt-out link
  DAY 3: Follow-up email — Additional information, CTA
  DAY 7: Final follow-up — Summary, CTA, final opt-out reminder

  POST-CAMPAIGN:
  ─► Process opt-outs within 10 business days
  ─► Suppress hard bounces
  ─► Generate compliance report
  ─► Review spam complaint rate (flag if > 0.08%)
```

### 9.3 Playbook 3: Cold Claimant Outreach (Direct Mail)

**Risk Level**: MODERATE — Compliance review recommended.

```
  PRE-FLIGHT CHECKLIST:
  [ ] 1. Address verified from public record
  [ ] 2. Deceased list checked
  [ ] 3. Bankruptcy list checked
  [ ] 4. State restrictions checked (per state)
  [ ] 5. Content pre-approved (Tier 1-2)
  [ ] 6. Required disclosures present (state-specific)
  [ ] 7. Return address accurate
  [ ] 8. Opt-out method included
  [ ] 9. No deceptive content
  [ ] 10. Audit trail configured

  EXECUTION:
  ─► Send via USPS (or approved mail house)
  ─► Track returned mail
  ─► Process opt-out requests (add to internal DNC)

  POST-CAMPAIGN:
  ─► Log all sends and returns
  ─► Update suppression lists
  ─► Generate compliance report
```

### 9.4 Playbook 4: Warm Lead Nurture (Multi-Channel)

**Risk Level**: HIGH — Automated sequences require pre-approved templates.

```
  PRE-FLIGHT CHECKLIST:
  [ ] 1. Consent tier verified for EACH channel used
  [ ] 2. Consent status confirmed VALID and not expired
  [ ] 3. Suppression lists checked (all 14)
  [ ] 4. All sequence templates pre-approved
  [ ] 5. Each channel checklist completed (Section 5)
  [ ] 6. Cross-channel opt-out confirmed functional
  [ ] 7. Sequence logic documented
  [ ] 8. Human escalation path defined
  [ ] 9. Monitoring alerts configured

  SEQUENCE (example 10-day nurture):
  DAY  0: Email 1 — Welcome, introduction, value proposition
  DAY  3: Email 2 — Educational content, case studies
  DAY  5: SMS (tier 3+ consent) — Brief reminder, CTA
  DAY  7: Email 3 — Testimonial, urgency (appropriate), CTA
  DAY 10: Call (tier 4+ consent) — Live agent or Voice AI follow-up

  RULES:
  ─► Each step must independently check consent + suppression before send
  ─► Any opt-out at any point = stop entire sequence, all channels
  ─► Sequence intervals must respect frequency caps per channel
  ─► Personalization limited to pre-approved dynamic fields only
  ─► State-specific rules applied at each step

  POST-CAMPAIGN:
  ─► Log all touches, responses, opt-outs
  ─► Analyze sequence performance
  ─► Compliance report generated
```

### 9.5 Playbook 5: Attorney Outreach

**Risk Level**: ⚖️ HIGH — ATTORNEY REVIEW REQUIRED per state.

```
  ⚖️ CRITICAL GATE: ATTORNEY OUTREACH MAY BE REGULATED BY STATE BAR RULES IN EACH STATE WHERE TARGETED ATTORNEYS ARE LICENSED.

  PRE-FLIGHT CHECKLIST:
  [ ] 1. ⚖️ STATE BAR RULES REVIEWED for each state (or documented assumption)
  [ ] 2. ⚖️ ATTORNEY REVIEW COMPLETED for campaign
  [ ] 3. Message content approved (Tier 3 minimum)
  [ ] 4. No false/misleading representations (ABA Rule 7.1)
  [ ] 5. Advertisement identified if required by state bar
  [ ] 6. No in-person solicitation (ABA Rule 7.3)
  [ ] 7. Referral arrangement disclosed (if applicable)
  [ ] 8. Suppression lists checked
  [ ] 9. Opt-out mechanism functional
  [ ] 10. Audit trail configured

  EXECUTION:
  ─► Email preferred (less restrictive than phone/mail for attorney solicitation)
  ─► No cold calls to attorneys unless permitted by state bar rules
  ─► Content must be truthful, non-deceptive, and not coercive

  POST-CAMPAIGN:
  ─► Log all sends and responses
  ─► Process opt-outs
  ─► Compliance report
```

### 9.6 Playbook 6: Voice AI Outreach (Telemarketing)

**Risk Level**: ⚖️ CRITICAL — ATTORNEY REVIEW REQUIRED before any Voice AI program launches.

```
  ⚖️ CRITICAL GATE: VOICE AI OUTREACH CARRIES THE HIGHEST TCPA RISK. DO NOT LAUNCH WITHOUT COMPLETE LEGAL REVIEW.

  PRE-FLIGHT CHECKLIST:
  [ ] 1. ⚖️ ATTORNEY REVIEW COMPLETED (including TCPA + state mini-TCPA analysis)
  [ ] 2. PEWC obtained and verified for each number
  [ ] 3. ATDS analysis documented (for the specific dialing system)
  [ ] 4. National DNC scrub completed
  [ ] 5. State DNC scrubs completed
  [ ] 6. Reassigned number DB check completed
  [ ] 7. Internal suppression list checked
  [ ] 8. Opening disclosure script approved (identity, purpose, opt-out)
  [ ] 9. Call recording notice included (two-party consent states)
  [ ] 10. Real-time opt-out mechanism tested (voice + keypress)
  [ ] 11. Human escalation path confirmed operational
  [ ] 12. AI disclosure included (if AI agent)
  [ ] 13. Call time restrictions configured (8 AM - 9 PM)
  [ ] 14. Frequency caps configured (max 1/day, 3/week)
  [ ] 15. Caller ID accurate (STIR/SHAKEN)
  [ ] 16. Audit trail configured (full call recording)
  [ ] 17. Monitoring alerts configured

  EXECUTION:
  ─► All calls begin with opening disclosure
  ─► Real-time opt-out monitoring during call
  ─► If opt-out received: disconnect, log, suppress immediately

  POST-CAMPAIGN:
  ─► Log all calls (completed, abandoned, opted out)
  ─► Process opt-outs
  ─► Generate compliance report
  ─► Review call answer rate and opt-out rate
```

---

## 10. TRAINING & GOVERNANCE

### 10.1 Training Requirements

| Role | Training Content | Frequency | Method | Certification Required? |
|------|-----------------|-----------|--------|------------------------|
| All Outreach Personnel | TCPA basics, CAN-SPAM basics, consent handling, opt-out processing, complaint handling | Upon hire + annually | Online course + quiz | Yes (80%+ score) |
| Outreach Managers | All above + state-specific rules, vendor compliance management, escalation procedures | Upon hire + annually | Online course + quiz + case studies | Yes (85%+ score) |
| Compliance Team | Full regulatory framework, audit procedures, violation response, litigation preparedness | Upon hire + semiannually | In-depth training + mock exercises | Yes (90%+ score) |
| Legal Counsel | Regulatory updates (quarterly), litigation trends, enforcement actions | Quarterly | Legal update briefings | Not applicable |
| Technology Team | System compliance requirements, integration testing, audit log verification | Upon hire + annually | Technical training | Yes (80%+ score) |
| Executive Leadership | Compliance risk overview, regulatory exposure, governance responsibilities | Annually | Executive briefing | Not applicable |
| Vendors/Partners | Channel-specific compliance requirements (per contract) | Upon onboarding + annually | Contract compliance certification | Yes (contractual) |

### 10.2 Training Content — Minimum Topics

1. **TCPA Deep Dive** (3 hours): ATDS definition, PEWC requirements, DNC registry, consent revocation, reassigned numbers, damages exposure, state mini-TCPA laws.
2. **CAN-SPAM Act** (1 hour): Commercial vs. transactional, opt-out requirements, header accuracy, enforcement.
3. **State Law Overview** (2 hours): High-risk states (FL, CA, IL, WA, NY, OK), specific state restrictions, state-by-state reference (Section 6).
4. **Consent Management** (1 hour): Consent tiers, capture methods, metadata requirements, consent lifecycle, refresh procedures.
5. **Opt-Out and Suppression** (1 hour): Universal opt-out rule, suppression list management, workflow, audit requirements.
6. **Complaint Handling** (1 hour): Complaint types, response SLAs, escalation paths, documentation.
7. **Channel-Specific Compliance** (2 hours): Each channel checklist (Section 5), common pitfalls, platform-specific requirements.
8. **Incident Response** (1.5 hours): Violation response protocol (Section 7.3), role assignments, communication templates, drill participation.
9. **Recordkeeping and Audit** (1 hour): Record retention requirements, audit participation, evidence preservation.

### 10.3 Governance Structure

```
  ┌─────────────────────────────────────────────────┐
  │            BOARD OF DIRECTORS                    │
  │   Annual compliance review; material breach      │
  │   notification                                   │
  └─────────────────────┬───────────────────────────┘
                        │
  ┌─────────────────────┴───────────────────────────┐
  │            CHIEF EXECUTIVE OFFICER              │
  │   Ultimate responsibility; resource allocation  │
  └─────────────────────┬───────────────────────────┘
                        │
  ┌─────────────────────┴───────────────────────────┐
  │            GENERAL COUNSEL                       │
  │   Legal oversight; outside counsel engagement;  │
  │   regulatory response; litigation management    │
  └─────────────────────┬───────────────────────────┘
                        │
  ┌─────────────────────┴───────────────────────────┐
  │            COMPLIANCE OFFICER                    │
  │   Day-to-day compliance management; audits;     │
  │   training; monitoring; escalation              │
  └──────┬──────────────────────┬───────────────────┘
         │                      │
  ┌──────┴──────┐    ┌─────────┴──────────┐
  │ OPERATIONS  │    │  TECHNOLOGY        │
  │ TEAM        │    │  TEAM              │
  │ Campaign    │    │  System compliance │
  │ execution;  │    │  integration;      │
  │ vendor mgmt │    │  audit tools;      │
  │ data entry  │    │  data security     │
  └─────────────┘    └────────────────────┘
```

### 10.4 Governance Meeting Cadence

| Meeting | Attendees | Frequency | Agenda |
|---------|-----------|-----------|--------|
| Compliance Stand-Up | Compliance Officer, Operations Lead, Tech Lead | Weekly | KPIs, ongoing issues, opt-out trends, upcoming campaigns |
| Compliance Review Board | Compliance Officer, Legal Counsel, GC | Bi-weekly | Violations, complaints, regulatory changes, campaign approvals |
| Outreach Compliance Steering | GC, CEO, COO, Compliance Officer | Monthly | Strategic compliance direction, risk assessment, resource needs, material violations |
| Board Compliance Update | GC, CEO, Board | Quarterly | Compliance program status, material incidents, regulatory changes, audit results |
| Annual Compliance Review | All stakeholders | Annually | Full program review, third-party audit results, next-year planning |

---

## 11. INCIDENT RESPONSE & LITIGATION PREPAREDNESS

### 11.1 Pre-Litigation Preparedness

**Document Retention for Litigation Defense**:

Maintain the following in a litigation-ready format:

1. **Consent records**: Complete, retrievable, and verifiable for each consumer contacted.
2. **Opt-out records**: Proof that opt-outs were honored, including timestamps.
3. **DNC scrub certifications**: Evidence of regular national and state DNC scrubs.
4. **Reassigned number database check records**: Evidence of pre-call/number checks.
5. **Template approval records**: Approved versions, dates, and approval chain documentation.
6. **Training records**: Personnel training completion and scores.
7. **Audit records**: All internal and external audit reports.
8. **Complaint records**: All complaints received and response documentation.
9. **Call recordings**: If voice AI, complete recordings of all calls.
10. **System logs**: Compliance Gateway decision logs for all sends.

**Legal Hold Protocol**:
- Upon notification of actual or threatened litigation: immediate legal hold on all relevant data.
- Legal hold notice distributed to all relevant personnel and vendors.
- Automated data preservation triggered in all systems.
- Hold lifted only upon written authorization from GC.

### 11.2 TCPA Lawsuit Response

```
  STEP 1: SERVICE OF PROCESS
  ─► Notify GC immediately
  ─► DO NOT RESPOND to plaintiff or counsel
  ─► Initiate legal hold
  ─► ⚖️ Engage outside TCPA counsel within 24 hours

  STEP 2: INITIAL ASSESSMENT (Within 72 Hours)
  ─► Identify the specific communication(s) at issue
  ─► Identify the consumer's consent record (if any)
  ─► Identify the system(s) used for the communication
  ─► Identify the ATDS nature of the system
  ─► Assess: was consent obtained? Was DNC scrubbed? Was opt-out honored?

  STEP 3: DEFENSE STRATEGY
  ─► Common TCPA defenses:
    • Consent obtained (PEWC)
    • System is not an ATDS (per Duguid)
    • Number was not reassigned (or one-call safe harbor applies)
    • Prior business relationship
    • DNC safe harbor (written procedures + training + recording)
    • Call was not "telemarketing"
  ─► ⚖️ Counsel will determine strategy based on facts

  STEP 4: SETTLEMENT ASSESSMENT
  ─► Statutory damages: $500-$1,500 per violation
  ─► Class action exposure: potentially catastrophic
  ─► Settlement cost vs. defense cost analysis
  ─► Insurance coverage assessment (cyber/E&O/general liability may cover TCPA)

  STEP 5: REGULATORY COORDINATION
  ─► FTC, FCC, or state AG notification assessment
  ─► Coordinate regulatory response with litigation strategy

  STEP 6: REMEDIATION
  ─► Fix root cause identified in litigation
  ─► Enhance compliance program
  ─► Document lessons learned
```

### 11.3 Insurance Coverage

| Insurance Type | TCPA Coverage? | Recommended Limit | Notes |
|----------------|---------------|-------------------|-------|
| General Liability | Typically NO | N/A | TCPA violations often excluded |
| Professional Liability (E&O) | Possibly | $5M+ | Review policy for TCPA exclusion |
| Cyber/Privacy Liability | Possibly | $5M+ | May cover some TCPA claims; review carefully |
| Directors & Officers (D&O) | No (defense costs only) | $5M+ | Covers securities claims from TCPA materiality |

**Recommended**: Engage insurance broker to identify specific TCPA coverage availability. Many carriers exclude TCPA claims entirely. Named insured coverage for TCPA is becoming harder to obtain.

---

## 12. VENDOR & PARTNER COMPLIANCE

### 12.1 Vendor Compliance Requirements

All vendors handling outreach, data, or consumer communications must:

1. **Contractual TCPA compliance**: Vendor agrees to comply with TCPA and all applicable state laws.
2. **Consent verification**: Vendor must verify consent before each communication (via Wheeler's Compliance Gateway).
3. **Suppression list integration**: Vendor must check Wheeler's suppression lists before each communication.
4. **Opt-out processing**: Vendor must process opt-outs in real time and propagate to Wheeler's CMP.
5. **Audit trail**: Vendor must produce complete, immutable logs of all communications.
6. **Data security**: Vendor must maintain SOC 2 Type II (or equivalent) and execute DPA.
7. **Indemnification**: Vendor indemnifies Wheeler for vendor's non-compliance.
8. **Audit rights**: Wheeler has the right to audit vendor's compliance controls annually.
9. **Breach notification**: Vendor must notify Wheeler within 24 hours of any data breach or compliance incident.
10. **Subcontractor restrictions**: Vendor may not subcontract Wheeler's outreach without prior written approval.

### 12.2 Partner Compliance Requirements

Partners (referral sources, data vendors, co-marketing partners) must:

1. **Consent origin verification**: If partner provides consumer data, partner must certify the consent basis for each data element.
2. **Data use restrictions**: Partner data may only be used for specified purposes.
3. **FCRA compliance**: If partner provides skip tracing or consumer report data, partner must certify FCRA compliance.
4. **No pass-through consent**: Partner cannot provide consent on behalf of Wheeler for Wheeler's independent outreach.
5. **Complaint coordination**: Partner must notify Wheeler of any complaints related to Wheeler's outreach.
6. **Audit rights**: Wheeler may audit partner's data collection and consent practices.

### 12.3 Data Vendor Vetting

For vendors providing consumer data (lead generation, skip tracing, data enrichment):

| Vendor Type | Key Compliance Risks | Vetting Requirements |
|-------------|---------------------|---------------------|
| Lead generation | Consent validity, TCPA compliance, data origin | Consent audit, TCPA compliance certification, sample verification |
| Skip tracing | FCRA compliance, data accuracy, permissible purpose | FCRA analysis, permissible purpose documentation, data quality audit |
| Data enrichment | Data accuracy, data source legality, consent for use | Data source verification, consent chain documentation |
| Reassigned number DB | Accuracy, update frequency, coverage | Database methodology review, accuracy testing, benchmark comparison |

---

## APPENDIX A: KEY CONTACTS & ESCALATION

| Role | Responsibility | Contact |
|------|--------------|---------|
| Compliance Officer | Day-to-day compliance management | [To be assigned] |
| General Counsel | Legal oversight, regulatory response | [To be assigned] |
| Outside TCPA Counsel | TCPA litigation, regulatory defense | [To be engaged] |
| Outside State Regulatory Counsel | State-specific analysis | [To be engaged per state] |
| CMP Administrator | Consent management platform operations | [To be assigned] |
| Outreach Operations Lead | Campaign execution, vendor management | [To be assigned] |
| DNC/PACER Scrub Administrator | Suppression list management | [To be assigned] |

## APPENDIX B: REGULATORY REFERENCES

| Regulation | Citation | Key Provisions |
|------------|----------|----------------|
| TCPA | 47 U.S.C. Section 227 | Autodialer restrictions, DNC registry, consent requirements, statutory damages |
| FCC TCPA Rules | 47 CFR Part 64.1200 | Consent requirements, DNC safe harbor, call abandonment, identification requirements |
| CAN-SPAM Act | 15 U.S.C. Sections 7701-7713 | Commercial email requirements, opt-out, header accuracy |
| FTC Telemarketing Sales Rule | 16 CFR Part 310 | Telemarketing restrictions, call times, disclosures, payment restrictions |
| FCRA | 15 U.S.C. Sections 1681-1681x | Consumer reports, permissible purpose, adverse action, furnisher obligations |
| Florida FTSA | Fla. Stat. Section 501.059 | Florida-specific ATDS definition, private right of action, damages |
| ABA Model Rules | Rules 7.1-7.5 | Attorney advertising, solicitation, communication standards |
| E-SIGN Act | 15 U.S.C. Sections 7001-7031 | Electronic signature validity for consent |
| CTIA Messaging Principles | CTIA Short Code Monitoring Program | SMS best practices, carrier compliance, opt-out requirements |

## APPENDIX C: CONSENT AND OPT-OUT RECORD — DATA DICTIONARY

| Field | Type | Required | Example | Validation |
|-------|------|----------|---------|------------|
| `consumer_id` | UUID v4 | Yes | `cns_a1b2c3d4-e5f6-7890-abcd-ef1234567890` | Valid UUID |
| `channels` | Enum[] | Yes | `["sms", "voice"]` | Must be from approved list |
| `phone_number` | String | Conditional | `+12065551234` | E.164 format, checked for SMS/voice |
| `email` | String | Conditional | `user@example.com` | Valid email, checked for email |
| `consent_version` | String | Yes | `v2.3-20260501` | Match template version |
| `consent_text` | Text | Yes | (Full disclosure text) | Must include all required elements |
| `timestamp` | ISO 8601 | Yes | `2026-05-25T14:30:00Z` | Must be UTC |
| `ip_address` | String | Conditional | `203.0.113.42` | Valid IP, required for web capture |
| `capture_method` | Enum | Yes | `web_form` | From approved methods list |
| `campaign_id` | String | Yes | `camp_claimant_q2_2026` | Non-empty |
| `proof_url` | URL | Conditional | `s3://consent-proofs/a1b2c3.pdf` | Required for paper/voice capture |
| `expiration_date` | Date | Yes | `2026-11-25` | Calculated per tier cadence |
| `revoked` | Boolean | Yes | `false` | Default false |
| `revoked_at` | ISO 8601 | Conditional | `2026-06-01T10:00:00Z` | Required if revoked = true |
| `revocation_channel` | Enum | Conditional | `sms_stop` | Required if revoked = true |
| `consent_origin` | Enum | Yes | `self` | `self` or `vendor_trusted` |
| `vendor_id` | String | Conditional | `vendor_leadgen_co` | Required if consent_origin != self |
| `notes` | Text | No | `Consumer requested SMS-only consent` | Internal use only |

---

## APPENDIX D: COMPLIANCE AUDIT TEMPLATE — CAMPAIGN REVIEW

**Campaign**: ____________________ **Channel**: ____________________ **Date**: ____________________

| # | Control | Status (Pass/Fail/NA) | Evidence | Notes |
|---|---------|----------------------|----------|-------|
| 1 | Consent verified for all targets | | | |
| 2 | National DNC scrub completed (≤31 days) | | | |
| 3 | State DNC scrubs completed | | | |
| 4 | Reassigned number DB check completed | | | |
| 5 | Internal suppression check completed | | | |
| 6 | Special lists checked (litigation, bankruptcy, deceased, etc.) | | | |
| 7 | State-specific restrictions verified | | | |
| 8 | Message template approved (correct tier) | | | |
| 9 | Opt-out mechanism functional | | | |
| 10 | Sender identification accurate | | | |
| 11 | Call time restrictions configured | | | |
| 12 | Frequency caps set | | | |
| 13 | Required disclosures present | | | |
| 14 | Audit trail configured | | | |
| 15 | Monitoring alerts configured | | | |

**Overall Assessment**: ☐ Pass ☐ Conditional Pass ☐ Fail

**Reviewer**: ____________________ **Date**: ____________________
**Approver**: ____________________ **Date**: ____________________

---

## DOCUMENT GOVERNANCE

| Version | Date | Author | Change Description |
|---------|------|--------|-------------------|
| 1.0 | 2026-05-25 | Outreach Compliance Architect | Initial release — Phase 5 Outreach Compliance Framework |

**Review Schedule**:
- Next review: 2026-08-25 (Q3 review)
- Regulatory change trigger: Any material change in TCPA, CAN-SPAM, FCRA, or state mini-TCPA laws
- Incident trigger: Any TCPA lawsuit, regulatory inquiry, or material compliance failure

**Distribution**: INTERNAL — Wheeler Ecosystem leadership, compliance team, legal counsel, outreach operations, and technology team. This document contains privileged legal analysis. Do not distribute outside Wheeler Ecosystem without GC approval.

---

*End of Phase 5: Outreach Compliance Framework*
