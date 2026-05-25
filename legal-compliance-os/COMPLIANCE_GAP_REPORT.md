# WHEELER ECOSYSTEM — PHASE 1 COMPLIANCE GAP REPORT

**Document ID:** WHEELER-COMPLIANCE-GAP-001  
**Classification:** CONFIDENTIAL — ATTORNEY-CLIENT PRIVILEGED  
**Date:** 2026-05-25  
**Author:** Wheeler AI Ops — Legal Compliance Architecture Division  
**Status:** PHASE 1 — GAP IDENTIFICATION  

---

## DISCLAIMER ⚠️

**THIS DOCUMENT IS NOT LEGAL ADVICE.** This gap report identifies compliance deficiencies based on a Phase 1 audit. It does not constitute legal advice or a complete assessment. Independent licensed counsel must review and validate all findings before implementation. See LEGAL_RISK_AUDIT.md full disclaimer.

---

## TABLE OF CONTENTS

1. Executive Summary
2. Compliance Gap Severity Index
3. Domain-by-Domain Gap Analysis
4. Missing Policies, Procedures, and Controls
5. Missing Documentation and Agreements
6. Missing Technical Controls
7. Remediation Roadmap
8. Resource Estimation

---

## 1. EXECUTIVE SUMMARY

### 1.1 Overall Compliance Posture

| Domain | Current State | Required State | Gap Score (1-10) | Priority |
|--------|--------------|----------------|-------------------|----------|
| TCPA/Telemarketing | No consent infrastructure, no DNC scanning, no opt-out system | Prior express written consent for all automated communications | 10/10 | P0-CRITICAL |
| State Finder's Fee Laws | No state-by-state analysis, uniform contracts nationally | State-specific contracts, disclosures, and licensing | 10/10 | P0-CRITICAL |
| UPL/AI Legal Content | AI generates content without attorney supervision | Attorney review of all AI outputs, disclaimers, UPL analysis | 9/10 | P0-CRITICAL |
| Attorney Fee Arrangements | Unknown marketplace fee structure | ABA Rule 5.4/7.2 compliance, state bar registration | 10/10 | P0-CRITICAL |
| CCPA/State Privacy | No privacy program, policy, or controls | Full CCPA/VCDPA/CPA/CTDPA/TDPSA compliance program | 9/10 | P0-CRITICAL |
| Data Scraping Compliance | Active scraping without legal review | CFAA/ToS/state law compliance program | 9/10 | P1-HIGH |
| FCRA Compliance | Lead scoring system operational | Consumer reporting agency compliance (if applicable) | 8/10 | P1-HIGH |
| Cybersecurity/Data Security | No documented security program | Written Information Security Program (WISP) | 8/10 | P1-HIGH |
| Data Breach Response | No incident response plan | Written IR plan, 50-state notification compliance | 8/10 | P1-HIGH |
| Claimant Contracts | Uniform contracts used nationally | State-specific contracts with required disclosures | 8/10 | P1-HIGH |
| SaaS/API Terms | Missing or inadequate | Comprehensive SaaS terms, data license agreements | 7/10 | P2-MEDIUM |
| Money Transmitter Compliance | Unknown fund flow compliance | State money transmitter licensing or clear exemption | 7/10 | P2-MEDIUM |
| CAN-SPAM Compliance | Unknown email practices | CAN-SPAM compliant email program | 7/10 | P2-MEDIUM |
| E-Signature Compliance | Unknown signature workflows | ESIGN/UETA compliant processes | 6/10 | P2-MEDIUM |
| State Data Broker Registration | Unknown registration status | Registration in VT, CA, OR, TX, FL, etc. | 6/10 | P2-MEDIUM |
| Client Disclosure Requirements | Unknown adequacy of disclosures | FTC-mandated and state-specific disclosures | 7/10 | P1-HIGH |
| Payment Card/PCI DSS | Unknown card processing practices | PCI DSS compliance | 5/10 | P3-LOW |
| Employee/Agent Training | No compliance training program | Role-based compliance training, annual refresher | 8/10 | P1-HIGH |
| Records Retention | No retention schedule | Document retention policy, destruction procedures | 7/10 | P2-MEDIUM |
| Vendor/Partner Due Diligence | No vendor compliance program | Vendor risk assessment, contractual compliance flow-down | 8/10 | P1-HIGH |

### 1.2 Gap Severity Distribution

| Severity | Count | GPA Equivalent |
|----------|-------|----------------|
| 9-10 (Critical Gap) | 5 | F |
| 7-8 (Major Gap) | 9 | D |
| 5-6 (Moderate Gap) | 5 | C |
| 1-4 (Minor Gap) | 1 | B |
| 0 (No Gap) | 0 | A |
| **Average Gap Score** | **7.6/10** | **Failing** |

---

## 2. COMPLIANCE GAP SEVERITY INDEX

### 2.1 Scoring Methodology

| Score | Classification | Definition |
|-------|---------------|------------|
| 1-3 | Minor Gap | Enhancement opportunity, low risk |
| 4-5 | Moderate Gap | Gap exists but partial controls in place |
| 6-7 | Major Gap | Significant gap, substantial risk exposure |
| 8-9 | Severe Gap | Critical compliance component absent |
| 10 | Total Gap | No compliance infrastructure exists |

### 2.2 Ranking (Highest to Lowest Gap Score)

| Rank | Area | Gap Score | Business Unit | Immediate Action Required |
|------|------|-----------|---------------|--------------------------|
| 1 | TCPA Consent Infrastructure | 10/10 | Lead Acquisition | CEASE ALL AUTOMATED OUTREACH |
| 2 | State Finder's Fee Compliance | 10/10 | FRG | CEASE OPERATIONS IN NON-ANALYZED STATES |
| 3 | Attorney Fee Arrangements | 10/10 | Attorney Marketplace | CEASE ATTORNEY PAYMENTS |
| 4 | Privacy Compliance Program | 9/10 | All Business Units | IMPLEMENT IMMEDIATELY |
| 5 | UPL/AI Content Compliance | 9/10 | SurplusAI | CEASE AI CONTENT TO CONSUMERS |
| 6 | Data Scraping Legal Review | 9/10 | Data Scraping | REVIEW ALL TARGET SITES |
| 7 | Claimant Contract Compliance | 8/10 | FRG | STATE-BY-STATE CONTRACT REVIEW |
| 8 | FCRA Compliance | 8/10 | SurplusAI, Prediction Radar | FCRA APPLICABILITY ANALYSIS |
| 9 | Cybersecurity Program | 8/10 | All Business Units | IMPLEMENT WISP |
| 10 | Data Breach Response Plan | 8/10 | All Business Units | IMPLEMENT IR PLAN |
| 11 | Vendor Compliance Management | 8/10 | All Business Units | IMPLEMENT VENDOR PROGRAM |
| 12 | Employee Compliance Training | 8/10 | All Business Units | DEVELOP TRAINING PROGRAM |
| 13 | State Mini-TCPA Compliance | 7/10 | Lead Acquisition | STATE-SPECIFIC COMPLIANCE |
| 14 | Client Disclosure Compliance | 7/10 | FRG | DISCLOSURE AUDIT |
| 15 | SaaS Terms of Service | 7/10 | SaaS/API Monetization | DRAFT COMPREHENSIVE TOS |
| 16 | Money Transmitter Compliance | 7/10 | FRG (Payment Flows) | FUND FLOW ANALYSIS |
| 17 | CAN-SPAM Compliance | 7/10 | Lead Acquisition | EMAIL PROGRAM AUDIT |
| 18 | Records Retention Program | 7/10 | All Business Units | IMPLEMENT RETENTION SCHEDULE |
| 19 | E-Signature Compliance | 6/10 | FRG, All | WORKFLOW REVIEW |
| 20 | Data Broker Registration | 6/10 | Prediction Radar, SurplusAI | REGISTRATION ANALYSIS |

---

## 3. DOMAIN-BY-DOMAIN GAP ANALYSIS

### 3.1 TCPA/Telemarketing Compliance

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| Consent collection | No documented consent process | Prior express written consent for all automated calls/texts | COMPLETE ABSENCE | 10/10 |
| Consent recording | No consent database | Auditable consent records with timestamp, source, content | COMPLETE ABSENCE | 10/10 |
| Opt-out mechanism | No STOP/opt-out system | Real-time opt-out processing, DNC list management | COMPLETE ABSENCE | 10/10 |
| Lead source validation | No lead source vetting | Affiliate compliance program, consent chain verification | COMPLETE ABSENCE | 10/10 |
| Calling time compliance | Unknown calling practices | 8AM-9PM local time restrictions | COMPLETE ABSENCE | 10/10 |
| DNC registry | No DNC screening | National DNC registry subscription and scrubbing | COMPLETE ABSENCE | 10/10 |
| State mini-TCPA compliance | No state-specific analysis | FL, OK, MD compliance programs | COMPLETE ABSENCE | 10/10 |
| A2P 10DLC registration | Unknown carrier registration status | TCR registration, campaign approval | UNKNOWN | 7/10 |
| Monitoring/auditing | No monitoring program | Call/text recording, compliance audits | COMPLETE ABSENCE | 10/10 |
| **AVERAGE** | | | | **9.6/10** |

**Specific Gaps:**

1. **GAP-TCPA-01:** No prior express written consent obtained or recorded for any SMS or call campaign
2. **GAP-TCPA-02:** No auditable consent records (no database, no timestamp, no source tracking)
3. **GAP-TCPA-03:** No STOP keyword processing infrastructure (no opt-out handling)
4. **GAP-TCPA-04:** No DNC registry subscription or scrubbing process
5. **GAP-TCPA-05:** No lead source/affiliate TCPA compliance program
6. **GAP-TCPA-06:** No calling time zone compliance controls
7. **GAP-TCPA-07:** No state-specific mini-TCPA compliance (Florida, Oklahoma, Maryland)
8. **GAP-TCPA-08:** No CTIA/carrier compliance program
9. **GAP-TCPA-09:** No TCPA documentation or written policies

### 3.2 State Finder's Fee Compliance — FRG

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| State-by-state legal analysis | Not performed | Comprehensive 50-state survey | COMPLETE ABSENCE | 10/10 |
| State-specific contracts | Uniform national contracts | 50-state compliant contracts | COMPLETE ABSENCE | 10/10 |
| Real estate license | Not obtained | State licenses where required | COMPLETE ABSENCE | 10/10 |
| Finder's fee disclosures | Unknown adequacy | State-specific disclosure requirements | COMPLETE ABSENCE | 10/10 |
| Cooling-off/cancellation rights | Not in contracts | 3/5/10-day state-specific rights | COMPLETE ABSENCE | 10/10 |
| Fee cap compliance | Unknown fee structure | State fee caps (varied by state) | COMPLETE ABSENCE | 10/10 |
| Court approval process | Not established | Where required by state law | COMPLETE ABSENCE | 10/10 |
| Attorney involvement compliance | Unknown | Non-lawyer fee receipt restrictions | COMPLETE ABSENCE | 10/10 |
| **AVERAGE** | | | | **10/10** |

**Specific Gaps:**

1. **GAP-FRG-01:** No 50-state legal analysis of finder's fee legality for surplus funds
2. **GAP-FRG-02:** No state-specific contract templates
3. **GAP-FRG-03:** No real estate broker licenses where required
4. **GAP-FRG-04:** No state-specific disclosure compliance
5. **GAP-FRG-05:** No cancellation/cooling-off rights in contracts
6. **GAP-FRG-06:** No fee cap compliance analysis
7. **GAP-FRG-07:** No court approval process for fee arrangements
8. **GAP-FRG-08:** No entity structure optimized for regulatory compliance

### 3.3 Unauthorized Practice of Law (UPL) — SurplusAI / AI Content

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| AI content attorney review | No attorney supervision | Licensed attorney review of all AI outputs | COMPLETE ABSENCE | 9/10 |
| UPL analysis | Not performed | AI content constitutes legal info vs. legal advice analysis | COMPLETE ABSENCE | 10/10 |
| Disclaimers | Unknown adequacy | Clear, prominent disclaimers AI is not legal advice | COMPLETE ABSENCE | 9/10 |
| AI accuracy controls | No accuracy program | Hallucination detection, fact-checking, citation verification | COMPLETE ABSENCE | 9/10 |
| State-specific UPL compliance | Not analyzed | 50-state UPL analysis | COMPLETE ABSENCE | 10/10 |
| Document generation safeguards | Unknown | Document prep vs. UPL line analysis | COMPLETE ABSENCE | 9/10 |
| **AVERAGE** | | | | **9.3/10** |

**Specific Gaps:**

1. **GAP-UPL-01:** No licensed attorney supervision of AI-generated legal content
2. **GAP-UPL-02:** No state-by-state UPL analysis for SurplusAI outputs
3. **GAP-UPL-03:** No AI hallucination/misinformation detection program
4. **GAP-UPL-04:** No disclaimers regarding AI ≠ legal advice (or inadequate disclaimers)
5. **GAP-UPL-05:** No automated document preparation UPL analysis
6. **GAP-UPL-06:** No consumer-facing AI transparency disclosures (FTC requirement)

### 3.4 Attorney Fee Arrangements — Attorney Marketplace

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| ABA Rule 5.4 compliance | Unknown | No fee sharing with non-lawyers | COMPLETE ABSENCE | 10/10 |
| ABA Rule 7.2 compliance | Unknown | No payment for referrals | COMPLETE ABSENCE | 10/10 |
| ABA Rule 7.3 compliance | Unknown | Solicitation restrictions | COMPLETE ABSENCE | 10/10 |
| State bar registration | Not registered | Lawyer referral service registration | COMPLETE ABSENCE | 10/10 |
| Attorney vetting | Unknown | Background checks, bar verification | COMPLETE ABSENCE | 10/10 |
| Fee disclosure to consumers | Unknown | Required disclosures about marketplace operation | COMPLETE ABSENCE | 10/10 |
| **AVERAGE** | | | | **10/10** |

**Specific Gaps:**

1. **GAP-MKT-01:** No ABA Rule 5.4/7.2/7.3 compliance analysis for marketplace fee structure
2. **GAP-MKT-02:** No state bar referral service registration (likely requires registration in most states)
3. **GAP-MKT-03:** No attorney vetting/credential verification process
4. **GAP-MKT-04:** No consumer-facing disclosures about marketplace/attorney relationship
5. **GAP-MKT-05:** No written agreements defining marketplace-attorney relationship
6. **GAP-MKT-06:** No Section 230 compliance analysis for marketplace content

### 3.5 Privacy Compliance — All Business Units

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| Privacy policy | Unknown if exists | Comprehensive privacy policy covering all data practices | COMPLETE ABSENCE | 9/10 |
| Notice at collection | No notice | Real-time notice when PI collected | COMPLETE ABSENCE | 9/10 |
| Data inventory/mapping | No data inventory | Complete data flow mapping | COMPLETE ABSENCE | 10/10 |
| Consumer rights mechanism | No rights infrastructure | Access, delete, correct, opt-out, portability | COMPLETE ABSENCE | 10/10 |
| CCPA/CPRA compliance | No compliance program | Full CPRA program | COMPLETE ABSENCE | 9/10 |
| State privacy law compliance | No compliance program | VA, CO, CT, OR, TX, etc. | COMPLETE ABSENCE | 9/10 |
| Data broker registration | Not registered | State data broker registration | COMPLETE ABSENCE | 8/10 |
| Service provider agreements | No SPAs | Written agreements with all data processors | COMPLETE ABSENCE | 9/10 |
| Sensitive data controls | No controls | Special handling for financial, court-derived data | COMPLETE ABSENCE | 9/10 |
| **AVERAGE** | | | | **9.1/10** |

**Specific Gaps:**

1. **GAP-PRIV-01:** No privacy policy (or inadequate policy)
2. **GAP-PRIV-02:** No data inventory/mapping of personal information collected, used, shared
3. **GAP-PRIV-03:** No consumer rights request mechanism (access, delete, correct, opt-out)
4. **GAP-PRIV-04:** No CCPA/CPRA compliance program
5. **GAP-PRIV-05:** No compliance with VA VCDPA, CO CPA, CT CTDPA, OR OCPA, TX TDPSA
6. **GAP-PRIV-06:** No data broker registration (CA, VT, OR, TX, FL — applicable states)
7. **GAP-PRIV-07:** No service provider agreements with vendors/processors
8. **GAP-PRIV-08:** No sensitive personal information handling procedures

### 3.6 Data Scraping — Legal Compliance

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| Website ToS review | Not reviewed | ToS for all target websites reviewed | COMPLETE ABSENCE | 9/10 |
| CFAA risk assessment | Not performed | Authorization boundaries analysis | COMPLETE ABSENCE | 9/10 |
| State computer crime analysis | Not performed | 50-state exposure analysis | COMPLETE ABSENCE | 9/10 |
| Cease-and-desist protocol | No protocol | Response plan for ToS/C&D demands | COMPLETE ABSENCE | 8/10 |
| Robot.txt compliance | Unknown | Respect robots.txt and access controls | COMPLETE ABSENCE | 8/10 |
| Alternative legal access | Not explored | FOIA/public records request program | COMPLETE ABSENCE | 8/10 |
| **AVERAGE** | | | | **8.5/10** |

**Specific Gaps:**

1. **GAP-SCRAPE-01:** No legal review of ToS for any target website
2. **GAP-SCRAPE-02:** No CFAA/state computer crime risk assessment
3. **GAP-SCRAPE-03:** No cease-and-desist response protocol
4. **GAP-SCRAPE-04:** No robots.txt compliance program
5. **GAP-SCRAPE-05:** No public records request alternative program
6. **GAP-SCRAPE-06:** No data accuracy/verification program for scraped data

### 3.7 Cybersecurity / Data Security

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| Written Information Security Program (WISP) | No WISP | Documented security program | COMPLETE ABSENCE | 8/10 |
| Risk assessment | Not performed | Annual security risk assessment | COMPLETE ABSENCE | 8/10 |
| Access controls | Unknown adequacy | Least privilege, MFA, access reviews | COMPLETE ABSENCE | 8/10 |
| Encryption standards | Unknown | Data-at-rest and in-transit encryption | COMPLETE ABSENCE | 8/10 |
| Incident response plan | No IR plan | Documented IR procedures | COMPLETE ABSENCE | 8/10 |
| Vendor security assessment | No vendor program | Vendor security due diligence | COMPLETE ABSENCE | 8/10 |
| Employee security training | No training program | Annual security awareness training | COMPLETE ABSENCE | 8/10 |
| **AVERAGE** | | | | **8.0/10** |

**Specific Gaps:**

1. **GAP-SEC-01:** No written information security program (may be required by FTC Safeguards Rule)
2. **GAP-SEC-02:** No security risk assessment performed
3. **GAP-SEC-03:** No documented access control policy
4. **GAP-SEC-04:** No data encryption policy (may be required by state privacy laws)
5. **GAP-SEC-05:** No incident response plan
6. **GAP-SEC-06:** No vendor security assessment program
7. **GAP-SEC-07:** No employee security awareness training

### 3.8 FCRA Compliance — Lead Scoring / Data Products

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| FCRA applicability analysis | Not performed | Legal analysis of whether systems create consumer reports | COMPLETE ABSENCE | 10/10 |
| User purpose monitoring | No monitoring | Tracking how subscribers use lead scoring data | COMPLETE ABSENCE | 8/10 |
| Accuracy procedures | No accuracy program | Reasonable procedures to ensure maximum possible accuracy | COMPLETE ABSENCE | 8/10 |
| Dispute process | No dispute process | Consumer dispute investigation and response | COMPLETE ABSENCE | 8/10 |
| Adverse action notices | No adverse action process | Notice to consumers if data used for adverse decisions | COMPLETE ABSENCE | 8/10 |
| Certification with users | No user certifications | Certifications of permissible purpose | COMPLETE ABSENCE | 8/10 |
| **AVERAGE** | | | | **8.3/10** |

**Specific Gaps:**

1. **GAP-FCRA-01:** No FCRA applicability analysis for SurplusAI/Prediction Radar
2. **GAP-FCRA-02:** No monitoring of subscriber use of data products
3. **GAP-FCRA-03:** No accuracy/dispute procedures for consumer data
4. **GAP-FCRA-04:** No user certification/permissible purpose program
5. **GAP-FCRA-05:** No adverse action notification process

### 3.9 Claimant Contracts — FRG

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| State-specific compliance | Uniform contracts | State-specific contracts meeting all requirements | COMPLETE ABSENCE | 8/10 |
| Required disclosures | Unknown | Fee, cancellation, attorney relationship, alternatives | COMPLETE ABSENCE | 8/10 |
| Cooling-off/cancellation | Not included | 3/5/10-day right to cancel | COMPLETE ABSENCE | 8/10 |
| Unconscionability review | Not performed | Fee reasonableness, contract fairness | COMPLETE ABSENCE | 8/10 |
| Assignment vs. POA structure | Unknown | Proper legal mechanism for fee recovery | COMPLETE ABSENCE | 8/10 |
| Language accessibility | Unknown | Limited English proficiency requirements | COMPLETE ABSENCE | 7/10 |
| **AVERAGE** | | | | **7.8/10** |

**Specific Gaps:**

1. **GAP-CONTRACT-01:** No state-specific contract templates
2. **GAP-CONTRACT-02:** No consumer protection disclosure compliance
3. **GAP-CONTRACT-03:** No cancellation/cooling-off provisions
4. **GAP-CONTRACT-04:** No unconscionability analysis
5. **GAP-CONTRACT-05:** No legal analysis of assignment vs. POA structure
6. **GAP-CONTRACT-06:** No language accessibility procedures

### 3.10 SaaS/API Terms of Service

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| Limitation of liability | Unknown | Mutual limitation (cap = fees paid, exclude consequential) | COMPLETE ABSENCE | 7/10 |
| Warranty disclaimers | Unknown | Disclaimer of implied warranties (UCC 2-316) | COMPLETE ABSENCE | 7/10 |
| Data rights/ownership | Unknown | Customer owns data, Wheeler owns aggregated data | COMPLETE ABSENCE | 7/10 |
| API usage limits | Unknown | Rate limits, volume caps, throttling terms | COMPLETE ABSENCE | 7/10 |
| Indemnification | Unknown | Mutual IP indemnification | COMPLETE ABSENCE | 7/10 |
| Termination rights | Unknown | Termination for breach, data export rights | COMPLETE ABSENCE | 7/10 |
| SLA/credits | Unknown | Uptime commitments, service credits, exclusions | COMPLETE ABSENCE | 6/10 |
| **AVERAGE** | | | | **6.9/10** |

**Specific Gaps:**

1. **GAP-SaaS-01:** No comprehensive terms of service (or inadequate terms)
2. **GAP-SaaS-02:** No data licensing agreement for API data products
3. **GAP-SaaS-03:** No limitation of liability or warranty disclaimers
4. **GAP-SaaS-04:** No SLA with service credits/exclusions
5. **GAP-SaaS-05:** No data ownership/usage rights defined

### 3.11 Payment/Money Transmitter Compliance

| Dimension | Current State | Required State | Gap | Severity |
|-----------|--------------|----------------|-----|----------|
| Fund flow analysis | Not performed | Legal review of payment flow for money transmitter implications | COMPLETE ABSENCE | 8/10 |
| Escrow/trust structure | Unknown | Proper escrow or trust arrangement for consumer funds | COMPLETE ABSENCE | 7/10 |
| PCI DSS compliance | Unknown | PCI DSS Level 4 or higher compliance | UNKNOWN | 6/10 |
| NACHA compliance | Unknown | ACH processing rules compliance | UNKNOWN | 6/10 |
| **AVERAGE** | | | | **6.8/10** |

**Specific Gaps:**

1. **GAP-PMT-01:** No legal analysis of whether Wheeler is a money transmitter
2. **GAP-PMT-02:** No escrow/trust structure for surplus funds
3. **GAP-PMT-03:** No PCI DSS compliance verification
4. **GAP-PMT-04:** No NACHA operating rules compliance program

---

## 4. MISSING POLICIES, PROCEDURES, AND CONTROLS

### 4.1 Required Policies (Not Yet Created)

| Policy | Priority | Business Units Affected | Description |
|--------|----------|------------------------|-------------|
| TCPA Compliance Policy | P0-CRITICAL | Lead Acquisition | Consent requirements, opt-out procedures, DNC scrubbing, audit protocols |
| Telemarketing Sales Rule Compliance Policy | P0-CRITICAL | Lead Acquisition | Calling hours, abandonment rate, caller ID, do-not-call procedures |
| Lead Source/Consent Management Policy | P0-CRITICAL | Lead Acquisition | Lead acquisition requirements, consent validation, affiliate compliance |
| Privacy Policy (Consumer-Facing) | P0-CRITICAL | All Business Units | PI categories, collection/use/sharing practices, CCPA rights, contact information |
| Information Security Policy (WISP) | P1-HIGH | All Business Units | Administrative, technical, physical safeguards — FTC Safeguards Rule compliant |
| Data Classification and Handling Policy | P1-HIGH | All Business Units | Classification levels, handling requirements, access controls |
| Records Retention and Destruction Policy | P1-HIGH | All Business Units | Retention schedules, destruction procedures, litigation hold |
| Incident Response Plan | P1-HIGH | All Business Units | Breach detection, containment, notification, recovery |
| AI Governance Policy | P1-HIGH | SurplusAI, Prediction Radar | AI development, testing, deployment, monitoring, content review |
| UPL Compliance Policy | P1-HIGH | SurplusAI, Attorney Marketplace | Attorney supervision, disclaimers, content review |
| Attorney Marketplace Compliance Policy | P1-HIGH | Attorney Marketplace | Fee structure, ABA Rule compliance, state bar registration, attorney vetting |
| FRG Client Intake Compliance Policy | P1-HIGH | FRG | State-specific disclosures, cooling-off, document execution, fee verification |
| Data Scraping Compliance Policy | P1-HIGH | Data Scraping | Target selection, ToS review, authorization boundaries, cease-and-desist protocol |
| FCRA Compliance Policy | P1-HIGH | SurplusAI, Prediction Radar | Consumer reporting status, accuracy, disputes, user certifications |
| Vendor/Third-Party Risk Management Policy | P1-HIGH | All Business Units | Due diligence, contracts, ongoing monitoring |
| Employee/Agency Compliance Training Program | P1-HIGH | All Business Units | Role-based training, annual refresher, testing |
| Data Broker Registration Compliance Policy | P2-MEDIUM | Prediction Radar, SurplusAI | Registration tracking, reporting, renewal in applicable states |
| Social Media/Advertising Compliance Policy | P2-MEDIUM | All Business Units | Truth-in-advertising, disclosures, substantiation |
| Fair Housing Compliance Policy | P3-LOW | Ravyn Capital | Non-discrimination, reasonable accommodation, marketing compliance |

### 4.2 Required Procedures (Not Yet Created)

| Procedure | Related Policy | Description |
|-----------|---------------|-------------|
| TCPA Consent Recording and Audit Procedure | TCPA Compliance | How consent is obtained, recorded, timestamped, stored, and audited |
| Opt-Out Processing Procedure | TCPA Compliance | How opt-outs are received, processed, honored, and documented |
| DNC Scrub Procedure | TCPA Compliance | How DNC numbers are obtained, loaded, matched, and excluded |
| Lead Source Validation Procedure | Lead Source Policy | How lead sources are vetted, contracted, monitored, and terminated |
| Consumer Privacy Rights Procedure | Privacy Policy | How access, deletion, correction, opt-out requests are received, validated, and fulfilled |
| Data Breach Notification Procedure | Incident Response | How breaches are detected, contained, notified to regulators/consumers |
| AI Content Review Procedure | AI Governance | How AI outputs are reviewed, validated, and approved before consumer-facing use |
| Attorney Vetting Procedure | Attorney Marketplace | How attorneys are credential-verified, background-checked, and monitored |
| Contract Compliance Procedure | FRG Client Intake | How state-specific contract requirements are verified for each engagement |
| Court Approval Procedure | FRG Client Intake | How court approval of fee is obtained where required |
| Website Target Assessment Procedure | Data Scraping Compliance | How target websites are assessed for ToS, robots.txt, and legal risk |

### 4.3 Required Technical Controls (Not Yet Implemented)

| Control | Purpose | Priority |
|---------|---------|----------|
| Consent Management Platform (CMP) | Record and manage consumer consent for TCPA and privacy | P0-CRITICAL |
| DNC Registry Integration | Real-time DNC number scrubbing before calls/texts | P0-CRITICAL |
| Opt-Out Processing System | Real-time STOP keyword response, DNC list updates, opt-out confirmation | P0-CRITICAL |
| Privacy Rights Request Portal | Online mechanism for consumers to submit CCPA/state privacy rights requests | P0-CRITICAL |
| Cookie Consent Mechanism | Notice and choice for online tracking (where applicable) | P1-HIGH |
| Call Recording and Retention System | Record telemarketing calls for TCPA/TSR compliance | P1-HIGH |
| Data Inventory/Mapping Tool | Automated discovery and mapping of personal information across systems | P1-HIGH |
| Data Encryption (at rest and in transit) | Protect personal information from unauthorized access | P1-HIGH |
| Access Control System (RBAC) | Role-based access to personal information | P1-HIGH |
| Logging and Monitoring System | Security event detection and response | P1-HIGH |
| Vulnerability Management Program | Regular scanning, patching, and remediation | P1-HIGH |
| AI Output Review/Filtering System | Automated and human review of AI-generated content | P1-HIGH |
| Lead Source Compliance Scoring System | Automated scoring and monitoring of lead source compliance | P1-HIGH |
| Consumer Age Verification | Verify age for CCPA minors' rights compliance | P1-HIGH |
| SMS Campaign Management Platform | Carrier compliance, A2P 10DLC, consent management, opt-out processing | P1-HIGH |
| Breach Detection and Notification System | Automated breach detection, notification workflow, regulatory filing | P1-HIGH |
| Contract Compliance Verification System | Automated validation of state-specific contract terms | P2-MEDIUM |
| API Rate Limiting and Usage Monitoring | Protect API infrastructure, enforce usage terms | P2-MEDIUM |

---

## 5. MISSING DOCUMENTATION AND AGREEMENTS

### 5.1 Consumer-Facing Documents

| Document | Status | Priority |
|----------|--------|----------|
| Privacy Policy (CCPA-compliant) | NOT CREATED | P0-CRITICAL |
| Notice at Collection (CCPA) | NOT CREATED | P0-CRITICAL |
| FRG Claimant Services Agreement | NOT STATE-SPECIFIC | P0-CRITICAL |
| TCPA Prior Express Written Consent Form | NOT CREATED | P0-CRITICAL |
| Telemarketing Scripts (with required disclosures) | NOT CREATED | P0-CRITICAL |
| AI-Generated Content Disclaimers | NOT CREATED | P1-HIGH |
| Attorney Marketplace Terms of Use (Consumer) | NOT CREATED | P1-HIGH |
| Cancellation/Refund Policy | NOT CREATED | P1-HIGH |
| Consumer Privacy Rights Request Form | NOT CREATED | P1-HIGH |
| Data Subject Access Request Form | NOT CREATED | P1-HIGH |
| Email Commercial Message Disclosures | NOT CREATED | P2-MEDIUM |
| SMS Terms and Conditions | NOT CREATED | P1-HIGH |

### 5.2 Business/Partner Agreements

| Agreement | Status | Priority |
|-----------|--------|----------|
| SaaS Terms of Service (SurplusAI, Prediction Radar) | NOT CREATED | P1-HIGH |
| API Terms of Use | NOT CREATED | P1-HIGH |
| Data License Agreements | NOT CREATED | P1-HIGH |
| Attorney Marketplace Participation Agreement | NOT CREATED | P0-CRITICAL |
| Service Provider Agreements (CCPA-mandated) | NOT CREATED | P0-CRITICAL |
| Vendor Data Processing Agreements | NOT CREATED | P1-HIGH |
| Lead Source/Affiliate Agreements | NOT CREATED | P0-CRITICAL |
| Business Associate Agreement (if HIPAA applies) | NOT CREATED | P2-MEDIUM |
| Reseller/Distributor Agreements | NOT CREATED | P2-MEDIUM |
| Non-Disclosure Agreements (standard form) | NOT CREATED | P2-MEDIUM |
| Master Services Agreements | NOT CREATED | P2-MEDIUM |

### 5.3 Internal Governance Documents

| Document | Status | Priority |
|----------|--------|----------|
| Compliance Manual | NOT CREATED | P1-HIGH |
| TCPA Compliance Manual | NOT CREATED | P0-CRITICAL |
| Information Security Program (WISP) | NOT CREATED | P1-HIGH |
| Incident Response Plan | NOT CREATED | P1-HIGH |
| Disaster Recovery/Business Continuity Plan | NOT CREATED | P2-MEDIUM |
| Code of Conduct / Ethics Policy | NOT CREATED | P2-MEDIUM |
| Whistleblower Policy | NOT CREATED | P2-MEDIUM |
| Conflict of Interest Policy | NOT CREATED | P2-MEDIUM |
| Data Privacy Impact Assessment (DPIA) Template | NOT CREATED | P1-HIGH |
| Vendor Risk Assessment Questionnaire | NOT CREATED | P1-HIGH |
| Employee Handbook (Compliance Section) | NOT CREATED | P2-MEDIUM |

---

## 6. REMEDIATION ROADMAP

### 6.1 Phase 0: IMMEDIATE STOP-GAP (Week 1)

| Order | Action | Owner | Dependencies |
|-------|--------|-------|--------------|
| 0.1 | **CEASE all automated SMS/text outreach** until TCPA consent infrastructure validated | CEO/General Counsel | None |
| 0.2 | **CEASE all AI-generated content to consumers** until UPL analysis and attorney review implemented | SurplusAI/Engineering | None |
| 0.3 | **CEASE all attorney payments/fee arrangements** until ABA Rule 5.4/7.2 compliance analysis | Attorney Marketplace | None |
| 0.4 | **PAUSE FRG operations in states without finder's fee analysis** (all 50 states) | FRG Operations | Attorney engagement |
| 0.5 | **ENGAGE outside counsel** for: TCPA, finder's fee (50-state), ABA ethics, UPL, privacy, CFAA | CEO/General Counsel | Budget approval |
| 0.6 | **Preserve all existing records** — do not delete any call logs, texts, emails, contracts, or data | All Business Units | None |

### 6.2 Phase 1: FOUNDATIONS (Weeks 2-4)

| Order | Action | Priority | Estimated Effort |
|-------|--------|----------|------------------|
| 1.1 | 50-state finder's fee legal analysis (outside counsel) | P0 | 80-120 hours attorney time |
| 1.2 | TCPA compliance program design (outside counsel + internal) | P0 | 60-80 hours |
| 1.3 | Privacy compliance program design — CCPA + comprehensive states | P0 | 40-60 hours |
| 1.4 | ABA ethics analysis — marketplace fee structure | P0 | 30-50 hours attorney time |
| 1.5 | UPL analysis for SurplusAI AI-generated content | P0 | 40-60 hours attorney time |
| 1.6 | Draft state-specific FRG claimant contracts (priority states first) | P0 | 40-80 hours attorney time |
| 1.7 | Implement consent management platform (technical) | P0 | 2-4 weeks engineering |
| 1.8 | Draft privacy policy and notice at collection | P0 | 20-30 hours privacy counsel |
| 1.9 | Implement opt-out/STOP processing system | P0 | 1-2 weeks engineering |

### 6.3 Phase 2: BUILD (Weeks 5-8)

| Order | Action | Priority | Estimated Effort |
|-------|--------|----------|------------------|
| 2.1 | Data scraping legal review — all target websites | P1 | 60-80 hours counsel + engineering |
| 2.2 | Written Information Security Program (WISP) | P1 | 30-50 hours |
| 2.3 | FCRA applicability analysis and compliance design | P1 | 30-40 hours attorney time |
| 2.4 | Reduce/refine finder's fee operating states based on Phase 1 analysis | P1 | Ongoing legal + operations |
| 2.5 | Restructure Attorney Marketplace fee model for ABA compliance | P1 | 40-60 hours attorney time |
| 2.6 | Implement AI content review workflow (human-in-the-loop) | P1 | 2-3 weeks engineering |
| 2.7 | Draft SaaS/API terms of service and data license agreements | P1 | 40-60 hours tech transactions attorney |
| 2.8 | State-specific contract implementation (all cleared states) | P1 | 40-60 hours legal + operations |
| 2.9 | Implement consumer privacy rights request portal | P1 | 2-4 weeks engineering |
| 2.10 | Implement DNC registry scrubbing process | P1 | 1-2 weeks engineering + operations |
| 2.11 | Draft data scraping compliance policy and C&D protocol | P1 | 20-30 hours counsel |
| 2.12 | Start state data broker registration filings | P1 | 20-30 hours |

### 6.4 Phase 3: OPERATIONALIZE (Weeks 9-16)

| Order | Action | Priority | Estimated Effort |
|-------|--------|----------|------------------|
| 3.1 | Implement compliance training program for all employees/agents | P1 | 2-4 weeks content + LMS |
| 3.2 | Implement vendor risk assessment program | P1 | 3-4 weeks |
| 3.3 | Implement data breach incident response plan and test | P1 | 3-4 weeks |
| 3.4 | Implement call recording and retention system | P1 | 2-3 weeks engineering |
| 3.5 | Conduct security risk assessment | P1 | 4-6 weeks external assessor |
| 3.6 | Implement data encryption program | P1 | 2-4 weeks engineering |
| 3.7 | Implement access control system (RBAC) | P1 | 2-3 weeks engineering |
| 3.8 | File state data broker registrations | P1 | Ongoing |
| 3.9 | Finalize SaaS/API terms, data license agreements | P2 | 20-30 hours attorney |
| 3.10 | Implement records retention/destruction program | P2 | 3-4 weeks |
| 3.11 | Draft employee handbook (compliance sections) | P2 | 20-30 hours |

### 6.5 Phase 4: SUSTAIN (Week 17+)

| Order | Action | Frequency |
|-------|--------|-----------|
| 4.1 | Quarterly compliance review and risk assessment update | Quarterly |
| 4.2 | Annual privacy law compliance update (tracking new state laws) | Annually |
| 4.3 | Annual security risk assessment | Annually |
| 4.4 | Annual penetration testing | Annually |
| 4.5 | TCPA compliance auditing (sample call/text monitoring) | Monthly |
| 4.6 | Employee compliance training refresher | Annually |
| 4.7 | Vendor compliance reassessment | Annually |
| 4.8 | Privacy rights request tracking and reporting | Continuous |
| 4.9 | State legislative tracking (new state laws) | Continuous |
| 4.10 | Outside counsel engagement for emerging risks | As needed |

---

## 7. RESOURCE ESTIMATION

### 7.1 Estimated Budget (Year 1)

| Category | Estimate | Notes |
|----------|----------|-------|
| Outside Legal Counsel | $250,000 - $500,000 | TCPA specialist, privacy (CIPP), ethics, UPL, securities, CFAA |
| Privacy Compliance Technology | $50,000 - $150,000 | CMP, DSAR portal, data mapping, cookie consent |
| TCPA Compliance Technology | $75,000 - $200,000 | Consent platform, DNC scrubbing, call recording, SMS platform |
| Security Program Implementation | $100,000 - $300,000 | WISP, risk assessment, pen testing, encryption implementation |
| Compliance Staff | $150,000 - $300,000 | Compliance officer hire (or fractional) |
| Training Program | $25,000 - $75,000 | Content development, LMS, annual rollout |
| **Total Year 1 Estimate** | **$650,000 - $1,525,000** | |
| **Cost of Non-Compliance (Single TCPA Class Action)** | **$10,000,000 - $100,000,000+** | For reference — statutory damages, no cap |

### 7.2 Personnel Requirements

| Role | Type | Timeline |
|------|------|----------|
| General Counsel / Chief Compliance Officer | Full-time or fractional executive | Month 1 |
| TCPA Compliance Specialist | Full-time or consultant | Month 1 |
| Privacy Counsel (CIPP-US) | Outside counsel → fractional in-house | Month 1 |
| Information Security Officer | Full-time or fractional executive | Month 2 |
| Compliance Manager (Operations) | Full-time | Month 2 |
| Data Protection Officer (if required by state law) | Full-time or fractional | Month 3 |
| Compliance Training Coordinator | Part-time or project-based | Month 2 |

---

## 8. CRITICAL DEPENDENCIES AND RISKS

### 8.1 Key Dependencies

| Dependency | Risk if Not Met | Fallback |
|------------|-----------------|----------|
| Engagement of qualified outside counsel | Audit findings cannot be validated | Extended pause of operations |
| CEO buy-in for compliance budget | Compliance program cannot be implemented | Prioritize highest-risk items |
| Engineering resources for technical controls | Manual workarounds, increased operational risk | Contract compliance system integrator |
| Executive decision on operating states (after 50-state analysis) | Continued legal exposure in high-risk states | Limit operations to low-risk states only |

### 8.2 Residual Risks After Phase 1 Implementation

| Risk | Description | Acceptable? |
|------|-------------|-------------|
| TCPA class action for past calls/texts | Remediation cannot undo past violations | NO — engage TCPA counsel re exposure |
| Scraping claims for past scraping activities | Legal review cannot retroactively authorize scraping | NO — coordinate with CFAA counsel |
| Pre-existing contract liability | Contracts signed before remediation may not meet requirements | MEDIUM — prioritize re-papering |
| New state laws during remediation | Legislative landscape changes during implementation | MONITOR — allocate 10% contingency |

---

## AMENDMENT AND VERSION CONTROL

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-05-25 | Wheeler AI Ops — Legal Compliance Division | Initial Phase 1 Compliance Gap Report |

---

*End of Document — Wheeler Ecosystem Phase 1 Compliance Gap Report*
