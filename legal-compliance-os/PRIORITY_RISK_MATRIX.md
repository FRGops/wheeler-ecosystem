# WHEELER ECOSYSTEM — PHASE 1 PRIORITY RISK MATRIX

**Document ID:** WHEELER-RISK-MATRIX-001  
**Classification:** CONFIDENTIAL — ATTORNEY-CLIENT PRIVILEGED  
**Date:** 2026-05-25  
**Author:** Wheeler AI Ops — Legal Compliance Architecture Division  
**Status:** PHASE 1 — RISK PRIORITIZATION  

---

## DISCLAIMER ⚠️

**THIS DOCUMENT IS NOT LEGAL ADVICE.** See LEGAL_RISK_AUDIT.md for full disclaimer. All risk ratings are preliminary and must be validated by licensed counsel.

---

## TABLE OF CONTENTS

1. Risk Rating Methodology
2. 5x5 Risk Matrix — Heat Map
3. Top 20 Risks — Detailed Assessment
4. Risk Owner Assignment Matrix
5. Aggregated Cost of Non-Compliance
6. Key to Terms and Abbreviations

---

## 1. RISK RATING METHODOLOGY

### 1.1 Likelihood Scale

| Score | Label | Definition |
|-------|-------|------------|
| 5 | Almost Certain | Event is expected to occur within 12 months in most circumstances |
| 4 | Likely | Event will probably occur within 12-24 months |
| 3 | Possible | Event might occur within 24-36 months |
| 2 | Unlikely | Event is not expected but could occur in 3-5 years |
| 1 | Rare | Event may occur only in exceptional circumstances |

### 1.2 Impact Scale

| Score | Label | Definition |
|-------|-------|------------|
| 5 | Catastrophic | Business failure, criminal prosecution, >$50M liability, imprisonment |
| 4 | Major | Major regulatory action, $10M-$50M liability, class action, cease-and-desist |
| 3 | Moderate | Regulatory investigation, $1M-$10M liability, significant operational disruption |
| 2 | Minor | $100K-$1M liability, minor regulatory action, limited operational impact |
| 1 | Insignificant | <$100K, minor compliance correction, no operational impact |

### 1.3 Risk Score = Likelihood x Impact

| Score Range | Risk Level | Action Required |
|-------------|------------|-----------------|
| 20-25 | CRITICAL | Immediate remediation — cease operations if necessary |
| 15-19 | HIGH | Urgent remediation within 30 days |
| 10-14 | MEDIUM | Remediation within 90 days |
| 5-9 | LOW | Monitor and remediate within 1 year |
| 1-4 | NEGLIGIBLE | Accept or monitor |

### 1.4 Combined Risk Score Range

The combined maximum risk score is 25 (5x5). The heat map below uses the following convention:

- **20-25** = [CRITICAL]
- **15-19** = [HIGH]
- **10-14** = [MEDIUM]
- **5-9** = [LOW]
- **1-4** = [NEGLIGIBLE]

---

## 2. 5x5 RISK MATRIX — HEAT MAP

```
                     IMPACT
              1         2         3         4         5
          INSIGNIF.   MINOR    MODERATE   MAJOR   CATASTROPHIC
          +--------------------------------------------------
    5     |          |          |          |  R1  R2 | R3  R4
   ALMOST |          |          |          |  R5  R6 | R7
   CERTAIN|          |          |          |  R7  R8 |
          |    ----- | -------- | -------- | -------- | --------
L    4    |          |          |  R9      | R10 R11  | R12 R13
I   LIKELY|          |          |  R15     | R14      |
K          |    ----- | -------- | -------- | -------- | --------
E    3    |          |  R16     | R17 R18  | R19      |
L   POSSIB|          |          |          |          |
I          |    ----- | -------- | -------- | -------- | --------
H    2    |          |  R20     |          |          |
O   UNLIK |          |          |          |          |
O          |    ----- | -------- | -------- | -------- | --------
D    1    |          |          |          |          |
    RARE  |          |          |          |          |
          +--------------------------------------------------
```

**Heat Map Legend:**

```
[CRITICAL] 20-25  = ████████████████████ (red)
[HIGH]     15-19  = ████████████████     (orange)
[MEDIUM]   10-14  = ████████████         (yellow)
[LOW]       5-9   = ██████               (green)
[NEGLIGIBLE] 1-4  = ██                   (blue)
```

### 2.1 Risk Plot Positions (Matrix Coordinates)

| Risk ID | Risk Description | Likelihood | Impact | Score | Level | Cell (L x I) |
|---------|-----------------|-----------|--------|-------|-------|--------------|
| R1 | TCPA — Automated SMS without consent (Lead Acquisition) | 5 | 4 | 20 | CRITICAL | (5,4) |
| R2 | TCPA — Lead list consent chain broken (Lead Acquisition) | 5 | 4 | 20 | CRITICAL | (5,4) |
| R3 | State mini-TCPA violations (Lead Acquisition) | 5 | 5 | 25 | CRITICAL | (5,5) |
| R4 | Finder's fee as unlicensed brokerage (FRG) | 5 | 5 | 25 | CRITICAL | (5,5) |
| R5 | UPL — AI-generated legal content (SurplusAI) | 5 | 4 | 20 | CRITICAL | (5,4) |
| R6 | Attorney fee splitting (Attorney Marketplace) | 5 | 4 | 20 | CRITICAL | (5,4) |
| R7 | 50-state finder's fee prohibition risk (FRG) | 5 | 5 | 25 | CRITICAL | (5,5) |
| R8 | Privacy compliance — no program (All) | 5 | 4 | 20 | CRITICAL | (5,4) |
| R9 | Data scraping CFAA liability (Data Scraping) | 4 | 3 | 12 | MEDIUM | (4,3) |
| R10 | DNC registry violations (Lead Acquisition) | 4 | 4 | 16 | HIGH | (4,4) |
| R11 | CAN-SPAM commercial email violations (Lead Acquisition) | 4 | 4 | 16 | HIGH | (4,4) |
| R12 | FCRA — lead scoring as consumer report (SurplusAI/Prediction Radar) | 4 | 5 | 20 | CRITICAL | (4,5) |
| R13 | State computer crime — data scraping (Data Scraping) | 4 | 5 | 20 | CRITICAL | (4,5) |
| R14 | Failure to disclose material contract terms (FRG) | 4 | 4 | 16 | HIGH | (4,4) |
| R15 | Unconscionable fee provisions (FRG) | 4 | 3 | 12 | MEDIUM | (4,3) |
| R16 | State data broker registration failure (Prediction Radar) | 3 | 2 | 6 | LOW | (3,2) |
| R17 | Data breach notification failure (All) | 3 | 3 | 9 | LOW | (3,3) |
| R18 | No cybersecurity program (All) | 3 | 3 | 9 | LOW | (3,3) |
| R19 | Unlicensed money transmission (FRG) | 3 | 4 | 12 | MEDIUM | (3,4) |
| R20 | SaaS terms — inadequate limitation of liability (SaaS/API) | 2 | 2 | 4 | NEGL. | (2,2) |

### 2.2 ASCII Heat Map — Full Grid View

```
           | Insignif |  Minor   | Moderate |  Major   | Catastr  |
           |   (1)    |   (2)    |   (3)    |   (4)    |   (5)    |
-----------+----------+----------+----------+----------+----------+
Almost     |          |          |          |R1=20 R2= |R3=25 R4= |
Certain    |          |          |          |R5=20 R6= |R7=25     |
  (5)      |          |          |          |R8=20     |          |
           | [  1-4 ] | [  5-9 ] | [ 10-14] | [ 15-19] | [ 20-25] |
           |          |          |          | CRITICAL | CRITICAL |
-----------+----------+----------+----------+----------+----------+
Likely     |          |          |R9=12     |R10=16    |R12=20    |
  (4)      |          |          |          |R11=16    |R13=20    |
           |          |          |          |R14=16    |          |
           | [  1-4 ] | [  5-9 ] | [ 10-14] | [ 15-19] | [ 20-25] |
           |          |          | MEDIUM   |   HIGH   | CRITICAL |
-----------+----------+----------+----------+----------+----------+
Possible   |          |R16=6     |R17=9     |R19=12    |          |
  (3)      |          |          |R18=9     |          |          |
           |          |          |          |          |          |
           | [  1-4 ] | [  5-9 ] | [ 10-14] | [ 15-19] | [ 20-25] |
           |          |   LOW    | MEDIUM   |   HIGH   | CRITICAL |
-----------+----------+----------+----------+----------+----------+
Unlikely   |          |R20=4     |          |          |          |
  (2)      |          |          |          |          |          |
           |          |          |          |          |          |
           | [  1-4 ] | [  5-9 ] | [ 10-14] | [ 15-19] | [ 20-25] |
           |NEGLIG.   |   LOW    | MEDIUM   |   HIGH   | CRITICAL |
-----------+----------+----------+----------+----------+----------+
Rare       |          |          |          |          |          |
  (1)      |          |          |          |          |          |
           |          |          |          |          |          |
           | [  1-4 ] | [  5-9 ] | [ 10-14] | [ 15-19] | [ 20-25] |
           |NEGLIG.   |   LOW    | MEDIUM   |   HIGH   | CRITICAL |
-----------+----------+----------+----------+----------+----------+
```

---

## 3. TOP 20 RISKS — DETAILED ASSESSMENT

### RISK R1: TCPA — Automated SMS/Calls Without Prior Express Written Consent

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **20/25 — CRITICAL** |
| **Likelihood** | 5 (Almost Certain) — Active SMS/call campaigns without auditable consent |
| **Impact** | 4 (Major) — $500-$1,500 per violation, class action $10M-$100M+ |
| **Business Unit** | Lead Acquisition Systems |
| **Key Statutes** | TCPA 47 U.S.C. § 227, FCC Orders |
| **Risk Owner** | Lead Acquisition Director / CTO |
| **Mitigation Strategy** | 1. IMMEDIATE: Cease all automated SMS/call outreach. 2. Implement consent management platform (CMP). 3. Audit all existing leads for valid consent *chain*. 4. Design compliant consent collection for all channels. 5. Implement opt-out processing infrastructure (STOP keyword, DNC list) BEFORE restarting campaigns. 6. Register A2P 10DLC campaigns with TCR. |
| **Timeline** | Stop-gap: IMMEDIATE. Full implementation: 8-12 weeks |
| **Cost of Remediation** | $75K-$200K (consent platform, SMS infrastructure, legal review) |
| **Cost of Non-Compliance** | **$10M-$100M+** (single class action — 100K texts x $10-$30 avg settlement per text = $1M-$3M per campaign cycle; worst case statutory: $500 x 1M texts = $500M) |

---

### RISK R2: TCPA — Lead List/Consent Chain Broken

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **20/25 — CRITICAL** |
| **Likelihood** | 5 (Almost Certain) — Industry practice of buying leads creates near-certain consent defects |
| **Impact** | 4 (Major) — Same $500-$1,500 per violation, joint and several liability |
| **Business Unit** | Lead Acquisition Systems |
| **Key Statutes** | TCPA, FCC Declaratory Ruling 2023 (lead generators cannot obtain consent for unknown sellers) |
| **Risk Owner** | Lead Acquisition Director |
| **Mitigation Strategy** | 1. IMMEDIATELY: Audit all lead sources and consent collection practices. 2. Discontinue all lead purchases from third-party aggregators. 3. Implement direct-to-consumer consent collection with point-of-sale TCPA disclosures. 4. Require TCPA compliance flow-down in all lead source contracts. 5. Implement lead source compliance scoring. |
| **Timeline** | Audit: 2 weeks. Transition to direct consent: 4-8 weeks |
| **Cost of Remediation** | $50K-$150K (lead source restructuring, compliance analytics) |
| **Cost of Non-Compliance** | **$5M-$50M** (vicarious liability for all downstream text/call campaigns) |

---

### RISK R3: State Mini-TCPA Violations

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **25/25 — CRITICAL (HIGHEST POSSIBLE)** |
| **Likelihood** | 5 (Almost Certain) — State mini-TCPAs do not require ATDS; any call/text to covered numbers |
| **Impact** | 5 (Catastrophic) — $1,500/violation (Florida), no federal preemption, no ATDS requirement |
| **Business Unit** | Lead Acquisition Systems |
| **Key Statutes** | Florida Telephone Solicitation Act § 501.059, Oklahoma § 15-759.3, Maryland § 14-3801 |
| **Risk Owner** | Lead Acquisition Director / Compliance Officer |
| **Mitigation Strategy** | 1. IMMEDIATELY: Implement state-level call/text filtering. 2. Obtain prior express written consent for FL/OK/MD numbers meeting stricter state standards. 3. Monitor for new mini-TCPA states (CA, NY, PA considering legislation). 4. Implement geo-fencing for prohibited states. |
| **Timeline** | Cease outreach to FL/OK/MD numbers: IMMEDIATE. Compliance: 4-6 weeks |
| **Cost of Remediation** | $30K-$80K (state-specific compliance, geo-fencing technology) |
| **Cost of Non-Compliance** | **$1,500 per text to FL numbers + class action. Estimated FL-only exposure: 15% of US leads x potential settlement.** |

---

### RISK R4: Finder's Fee as Unlicensed Real Estate Brokerage

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **25/25 — CRITICAL (HIGHEST POSSIBLE)** |
| **Likelihood** | 5 (Almost Certain) — FRG operates without real estate licenses in any state |
| **Impact** | 5 (Catastrophic) — Disgorgement of ALL fees, criminal charges in some states, cease and desist |
| **Business Unit** | Funds Recovery Group |
| **Key Statutes** | State real estate license laws (CA Bus. & Prof. Code § 10131, FL real estate license law, etc.) |
| **Risk Owner** | FRG Director / CEO |
| **Mitigation Strategy** | 1. IMMEDIATELY: Engage 50-state real estate counsel for comprehensive analysis. 2. Determine which states require licenses, finder's fee permits, or prohibit the activity. 3. Obtain licenses in required states. 4. Restructure business model for prohibited states (attorney-only, referral, or exit). 5. Implement state-specific compliance for each operating jurisdiction. |
| **Timeline** | 50-state analysis: 4-8 weeks. Licensing: 2-6 months per state. Restructuring: 3-6 months |
| **Cost of Remediation** | $80K-$150K (legal analysis) + $25K-$100K per state licensing (fees, exams, bonds) |
| **Cost of Non-Compliance** | **$500K-$10M per state** (disgorgement of fees + fines) + **criminal prosecution risk** in CA, FL, NC, NY |

---

### RISK R5: Unauthorized Practice of Law — AI-Generated Legal Content

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **20/25 — CRITICAL** |
| **Likelihood** | 5 (Almost Certain) — AI generates content interpreting legal rights/procedures |
| **Impact** | 4 (Major) — Criminal charges (misdemeanor in most states), injunction, reputational damage |
| **Business Unit** | SurplusAI |
| **Key Statutes** | State UPL statutes (all 50 states + DC), ABA Model Rule 5.5 |
| **Risk Owner** | SurplusAI Director / General Counsel |
| **Mitigation Strategy** | 1. IMMEDIATELY: Cease consumer-facing AI legal content until attorney review implemented. 2. Engage legal ethics/UPL counsel for state-by-state analysis. 3. Implement attorney-in-the-loop review for all AI outputs. 4. Add prominent disclaimers ("This is not legal advice"). 5. Restrict AI outputs to legal information, not legal advice. 6. Consider Arizona/Utah regulatory sandbox if applicable. |
| **Timeline** | Cease: IMMEDIATE. Human-in-the-loop: 4-8 weeks. Full program: 8-12 weeks |
| **Cost of Remediation** | $60K-$120K (UPL counsel, attorney review system, disclaimers) |
| **Cost of Non-Compliance** | **$10K-$50K per violation (state UPL), criminal misdemeanor, business-ending injunction** |

---

### RISK R6: Attorney Fee Splitting — Marketplace Structure

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **20/25 — CRITICAL** |
| **Likelihood** | 5 (Almost Certain) — Marketplace fee structure likely involves revenue from attorney fees |
| **Impact** | 4 (Major) — Bar discipline, referral attorney disbarment, fee forfeiture, marketplace shutdown |
| **Business Unit** | Attorney Marketplace |
| **Key Statutes** | ABA Model Rule 5.4 (fee sharing with non-lawyers), Rule 7.2 (payment for referrals) |
| **Risk Owner** | Attorney Marketplace Director / General Counsel |
| **Mitigation Strategy** | 1. IMMEDIATELY: Cease all payments to/receipts from attorneys pending review. 2. Legal ethics counsel review of marketplace fee model. 3. Restructure to ABA-compliant model: flat fee for listings (not per-referral), advertising rates, or qualified lawyer referral service structure. 4. Register as lawyer referral service in each state (if required). 5. Implement attorney vetting and credential verification. |
| **Timeline** | Cease: IMMEDIATE. Restructure: 6-12 weeks |
| **Cost of Remediation** | $75K-$150K (legal ethics counsel, state bar registrations, structural changes) |
| **Cost of Non-Compliance** | **Loss of attorney partners via disbarment risk, marketplace shutdown via bar action, fee forfeiture claims** |

---

### RISK R7: Finder's Fees Prohibited by Specific State Laws

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **25/25 — CRITICAL (HIGHEST POSSIBLE)** |
| **Likelihood** | 5 (Almost Certain) — At least NC and potentially other states have explicit prohibitions |
| **Impact** | 5 (Catastrophic) — Criminal charges, mandatory disgorgement, cease and desist |
| **Business Unit** | Funds Recovery Group |
| **Key Statutes** | NC GS § 45-21.36A, state-specific surplus fund recovery laws |
| **Risk Owner** | FRG Director / General Counsel |
| **Mitigation Strategy** | 1. IMMEDIATELY: 50-state analysis to identify all states with prohibition/restriction. 2. Cease operations in all states where finder's fees are prohibited. 3. Restructure for prohibited states (referral to consumer to attorney only). 4. Monitor legislative changes in remaining states. |
| **Timeline** | State-specific analysis: 4-8 weeks. State exits: withing 24 hours of identification |
| **Cost of Remediation** | $40K-$80K (legal analysis, state exit costs) |
| **Cost of Non-Compliance** | **Criminal prosecution (NC class 2 misdemeanor), disgorgement of all NC fees, AG investigation** |

---

### RISK R8: No Privacy Compliance Program (CCPA + 12 State Laws)

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **20/25 — CRITICAL** |
| **Likelihood** | 5 (Almost Certain) — No privacy policy, no data rights mechanism, no data inventory |
| **Impact** | 4 (Major) — $2,500-$7,500 per violation (CCPA), state AG enforcement, private right of action for breaches |
| **Business Unit** | All Business Units |
| **Key Statutes** | CCPA/CPRA, VCDPA, CPA, CTDPA, OCPA, TDPSA, plus 6+ additional state laws effective 2024-2026 |
| **Risk Owner** | CEO / General Counsel (or CISO) |
| **Mitigation Strategy** | 1. IMMEDIATELY: Engage privacy counsel. 2. Conduct data inventory/mapping. 3. Draft and publish privacy policy (CCPA-compliant). 4. Implement consumer privacy rights request mechanism (access, delete, correct, opt-out). 5. Implement notice at collection. 6. Draft service provider agreements. 7. Register as data broker in applicable states. |
| **Timeline** | Privacy policy: 2-4 weeks. Data inventory: 4-6 weeks. Rights portal: 6-10 weeks. Full program: 12-16 weeks |
| **Cost of Remediation** | $100K-$250K (privacy counsel, technology, operational implementation) |
| **Cost of Non-Compliance** | **$2,500-$7,500 per violation (no cap — CCPA), $7,500 per violation (Colorado), AG investigations, private class action for data breaches** |

---

### RISK R9: Data Scraping — CFAA Liability

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **12/25 — MEDIUM** |
| **Likelihood** | 4 (Likely) — Active scraping of county/court websites |
| **Impact** | 3 (Moderate) — Civil damages ($1K-$10K/violation), potential criminal charges if aggregated >$5K |
| **Business Unit** | Data Scraping / Intelligence |
| **Key Statutes** | CFAA 18 U.S.C. § 1030 |
| **Risk Owner** | Data Scraping Director / Engineering Lead |
| **Mitigation Strategy** | 1. Legal review of ToS for all target websites. 2. Implement cease-and-desist response protocol. 3. Respect robots.txt and access controls. 4. Consider public records request program as alternative. 5. Ensure no circumvention of technical barriers (IP blocking, authentication). |
| **Timeline** | ToS review: 2-4 weeks. C&D protocol: 1 week. Full program: 6-8 weeks |
| **Cost of Remediation** | $40K-$80K (legal review, policy development) |
| **Cost of Non-Compliance** | **Civil lawsuit per target website, criminal CFAA charges if technical barriers circumvented, state AG investigation** |

---

### RISK R10: DNC Registry Violations

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **16/25 — HIGH** |
| **Likelihood** | 4 (Likely) — No evidence of DNC scrubbing process |
| **Impact** | 4 (Major) — $43,792 per call (FTC TSR), plus TCPA private right of action |
| **Business Unit** | Lead Acquisition Systems |
| **Key Statutes** | TCPA DNC provisions, Telemarketing Sales Rule 16 CFR 310 |
| **Risk Owner** | Lead Acquisition Director |
| **Mitigation Strategy** | 1. Subscribe to National DNC Registry. 2. Implement DNC scrubbing process (real-time before each call campaign). 3. Document DNC compliance for each campaign. 4. Implement DNC safe-harbor compliance (written procedures, training, periodic scrubbing, internal DNC list). |
| **Timeline** | DNC subscription: <1 week. Scrubbing process: 1-2 weeks |
| **Cost of Remediation** | $15K-$40K (DNC subscription + scrubbing integration) |
| **Cost of Non-Compliance** | **$43,792 per call (FTC TSR) + $500-$1,500 per call (TCPA private action)** |

---

### RISK R11: CAN-SPAM Email Violations

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **16/25 — HIGH** |
| **Likelihood** | 4 (Likely) — Email marketing likely without full CAN-SPAM compliance |
| **Impact** | 4 (Major) — $50,120 per email violation |
| **Business Unit** | Lead Acquisition Systems |
| **Key Statutes** | CAN-SPAM Act 15 U.S.C. § 7701 |
| **Risk Owner** | Marketing Director / Lead Acquisition Director |
| **Mitigation Strategy** | 1. Audit all email marketing programs for CAN-SPAM compliance. 2. Ensure accurate header information. 3. Ensure non-deceptive subject lines. 4. Implement prominent opt-out mechanism in every message. 5. Process opt-outs within 10 business days. 6. Include valid physical postal address. 7. Contractually require compliance from email service providers. 8. Document all transactional/relationship exemptions. |
| **Timeline** | Audit: 1-2 weeks. Remediation: 2-4 weeks |
| **Cost of Remediation** | $20K-$50K (email compliance audit, ESP configuration) |
| **Cost of Non-Compliance** | **$50,120 per email (FTC enforcement). For a campaign of 100K emails: $5B theoretical max (actual enforcement targets high-volume senders with $1M-$10M penalties)** |

---

### RISK R12: FCRA — Lead Scoring as Consumer Report

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **20/25 — CRITICAL** |
| **Likelihood** | 4 (Likely) — Lead scoring evaluates consumer characteristics for eligibility decisions |
| **Impact** | 5 (Catastrophic) — Class action, FTC enforcement, operational restructuring if CRA determination made |
| **Business Unit** | SurplusAI, Prediction Radar |
| **Key Statutes** | FCRA 15 U.S.C. § 1681 et seq. |
| **Risk Owner** | SurplusAI Director / Prediction Radar Director |
| **Mitigation Strategy** | 1. IMMEDIATELY: FCRA applicability analysis by consumer reporting counsel. 2. If CRA determination: implement full FCRA compliance (accuracy, dispute resolution, user certifications, purpose limitations). 3. If not CRA: document analysis and implement subscriber use restrictions. 4. Implement data accuracy and verification procedures. 5. Add contractual prohibitions on using data for FCRA-covered decisions. |
| **Timeline** | FCRA analysis: 2-4 weeks. If CRA, full implementation: 8-16 weeks |
| **Cost of Remediation** | $30K-$80K (FCRA analysis) + $150K-$300K (if FCRA compliance needed) |
| **Cost of Non-Compliance** | **$100K-$1M per violation (FCRA willful non-compliance = class action), FTC consent decree, business model disruption** |

---

### RISK R13: State Computer Crime Laws — Data Scraping

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **20/25 — CRITICAL** |
| **Likelihood** | 4 (Likely) — Active scraping across multiple states |
| **Impact** | 5 (Catastrophic) — Felony criminal charges in some states (CA, NY, TX, VA) |
| **Business Unit** | Data Scraping / Intelligence |
| **Key Statutes** | CA Penal Code § 502, NY Penal Law § 156.05, TX Penal Code § 33.02, VA Code § 18.2-152.6 |
| **Risk Owner** | Data Scraping Director / General Counsel |
| **Mitigation Strategy** | 1. Immediate state-by-state analysis of computer crime laws in all states where target websites are located. 2. Cease scraping in states with the broadest/best laws. 3. Implement technical compliance program to avoid unauthorized access. 4. Consider public records request program as lawful alternative. 5. Develop relationship with court administrators for authorized data access. |
| **Timeline** | State analysis: 2-4 weeks. Restructuring: 4-8 weeks |
| **Cost of Remediation** | $40K-$100K (state law analysis, compliance restructuring) |
| **Cost of Non-Compliance** | **Felony criminal prosecution (state prison), asset forfeiture, AG investigation, civil claims** |

---

### RISK R14: Failure to Disclose Material Contract Terms

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **16/25 — HIGH** |
| **Likelihood** | 4 (Likely) — Uniform contracts likely lack state-specific disclosures |
| **Impact** | 4 (Major) — FTC enforcement, state AG actions, contract voidability, restitution |
| **Business Unit** | Funds Recovery Group |
| **Key Statutes** | FTC Act § 5, state UDAP statutes |
| **Risk Owner** | FRG Director / General Counsel |
| **Mitigation Strategy** | 1. Engage consumer protection counsel for disclosure requirements. 2. Draft state-specific contract templates with all required disclosures. 3. Ensure prominent display of fee structure, cancellation rights, and alternative options. 4. Implement contract execution procedures that verify disclosure receipt. |
| **Timeline** | Disclosure analysis: 3-6 weeks. New contracts: 6-10 weeks |
| **Cost of Remediation** | $40K-$100K (legal + operations) |
| **Cost of Non-Compliance** | **FTC/AG enforcement action, restitution to all consumers, civil penalties, class action** |

---

### RISK R15: Unconscionable Fee Provisions

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **12/25 — MEDIUM** |
| **Likelihood** | 4 (Likely) — 25-40% fee structure for form-based services raises scrutiny |
| **Impact** | 3 (Moderate) — Fee reduction/disgorgement, limited class action |
| **Business Unit** | Funds Recovery Group |
| **Key Statutes** | UCC § 2-302, state common law unconscionability |
| **Risk Owner** | FRG Director / General Counsel |
| **Mitigation Strategy** | 1. Fee structure reasonableness analysis against state benchmarks. 2. Reduce fees if necessary to market-competitive rates. 3. Ensure clear disclosure of fee versus value provided. 4. Document actual services performed to justify fee. 5. Implement fee cap based on state requirements. |
| **Timeline** | Fee analysis: 2-4 weeks. Restructuring: 4-8 weeks |
| **Cost of Remediation** | $20K-$50K (analysis, potential fee restructuring) |
| **Cost of Non-Compliance** | **Disgorgement of fees, contract voidance, class action, reputational damage** |

---

### RISK R16: State Data Broker Registration Failure

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **6/25 — LOW** |
| **Likelihood** | 3 (Possible) — Likely qualifies as data broker in multiple states |
| **Impact** | 2 (Minor) — Registration penalties ($100/day to $10K/violation) |
| **Business Unit** | Prediction Radar, SurplusAI |
| **Key Statutes** | VT data broker law, CA SB 806, OR, TX data broker laws |
| **Risk Owner** | Prediction Radar Director / Privacy Officer |
| **Mitigation Strategy** | 1. Determine data broker status in all applicable states. 2. File registrations in required states. 3. Implement annual renewal procedures. 4. Maintain data broker disclosures. |
| **Timeline** | Determination: 1-2 weeks. Registrations: 2-4 weeks |
| **Cost of Remediation** | $10K-$30K (registrations + ongoing compliance) |
| **Cost of Non-Compliance** | **$10K per violation CA, $100/day VT, state AG enforcement** |

---

### RISK R17: Data Breach Notification Failure

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **9/25 — LOW** |
| **Likelihood** | 3 (Possible) — Business likely holds PII with limited security controls |
| **Impact** | 3 (Moderate) — Regulatory fines, class action for delayed/no notification |
| **Business Unit** | All Business Units |
| **Key Statutes** | 50-state breach notification laws |
| **Risk Owner** | CISO / General Counsel |
| **Mitigation Strategy** | 1. Implement incident response plan. 2. Develop 50-state breach notification decision tree. 3. Implement breach detection controls. 4. Retain breach counsel on retainer. 5. Conduct tabletop exercises. |
| **Timeline** | IR plan: 4-6 weeks. Full program: 8-12 weeks |
| **Cost of Remediation** | $30K-$80K (IR plan, breach counsel retainer, tabletop) |
| **Cost of Non-Compliance** | **$100-$1,000 per affected individual (state penalties + class action) + FTC consent decree (20 years)** |

---

### RISK R18: No Cybersecurity Program

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **9/25 — LOW** |
| **Likelihood** | 3 (Possible) — No documented security program found |
| **Impact** | 3 (Moderate) — FTC enforcement, state AG action, breach amplification |
| **Business Unit** | All Business Units |
| **Key Statutes** | FTC Act § 5, FTC Safeguards Rule (if applicable), state security laws (NY SHIELD, etc.) |
| **Risk Owner** | CTO / CISO |
| **Mitigation Strategy** | 1. Draft Written Information Security Program (WISP). 2. Conduct security risk assessment. 3. Implement administrative, technical, and physical safeguards. 4. Assign security program ownership. 5. Implement vendor security assessment process. |
| **Timeline** | WISP: 3-6 weeks. Risk assessment: 4-6 weeks. Full program: 12-16 weeks |
| **Cost of Remediation** | $80K-$200K (WISP, risk assessment, security controls) |
| **Cost of Non-Compliance** | **FTC 20-year consent decree (cost: $5M-$50M compliance, monitoring, audits), breach costs amplified** |

---

### RISK R19: Unlicensed Money Transmission

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **12/25 — MEDIUM** |
| **Likelihood** | 3 (Possible) — FRG may handle surplus fund flows requiring transmission |
| **Impact** | 4 (Major) — Criminal charges, disgorgement, fines up to $10K/day per state |
| **Business Unit** | Funds Recovery Group (Payment Flows) |
| **Key Statutes** | 50-state money transmitter laws |
| **Risk Owner** | FRG Director / CFO |
| **Mitigation Strategy** | 1. Fund flow legal analysis to determine if Wheeler is a money transmitter. 2. If yes: obtain money transmitter licenses or restructure. 3. Alternative: use third-party escrow service (avoiding transmission). 4. Alternative: attorney-managed trust account (IOLTA). |
| **Timeline** | Fund flow analysis: 2-4 weeks. Restructuring: 6-12 weeks |
| **Cost of Remediation** | $40K-$100K (legal analysis + potential restructuring) |
| **Cost of Non-Compliance** | **Criminal prosecution per state, disgorgement, fines, business disruption** |

---

### RISK R20: SaaS Terms — Inadequate Limitation of Liability

| Attribute | Detail |
|-----------|--------|
| **Risk Score** | **4/25 — NEGLIGIBLE** |
| **Likelihood** | 2 (Unlikely) — SaaS products are newer, lower revenue |
| **Impact** | 2 (Minor) — Contract damages, third-party claims |
| **Business Unit** | SaaS/API Monetization |
| **Key Statutes** | Contract law, UCC |
| **Risk Owner** | SaaS Director / General Counsel |
| **Mitigation Strategy** | 1. Draft comprehensive SaaS terms of service. 2. Include mutual limitation of liability (cap = 12 months fees), exclusion of consequential damages. 3. Include warranty disclaimers (UCC 2-316). 4. Define data ownership/usage rights. 5. Include SLA with credits and exclusions. |
| **Timeline** | Terms draft: 4-6 weeks |
| **Cost of Remediation** | $25K-$50K (tech transactions attorney) |
| **Cost of Non-Compliance** | **Uncapped liability exposure (potentially full damages from data errors), competitive disadvantage** |

---

## 4. RISK OWNER ASSIGNMENT MATRIX

| Risk ID | Risk | Primary Owner | Secondary Owner | Reporting Cadence |
|---------|------|---------------|-----------------|-------------------|
| R1 | TCPA — SMS without consent | Lead Acquisition Director | CTO | Weekly during remediation |
| R2 | TCPA — Lead consent chain | Lead Acquisition Director | Compliance Officer | Weekly during remediation |
| R3 | State mini-TCPA violations | Lead Acquisition Director | Compliance Officer | Weekly during remediation |
| R4 | Finder's fee — unlicensed brokerage | FRG Director | General Counsel | Weekly during remediation |
| R5 | UPL — AI content | SurplusAI Director | General Counsel | Weekly during remediation |
| R6 | Attorney fee splitting | Marketplace Director | General Counsel | Weekly during remediation |
| R7 | Finder's fee — state prohibition | FRG Director | General Counsel | Weekly during remediation |
| R8 | Privacy — no program | General Counsel | CTO | Monthly |
| R9 | CFAA — scraping liability | Data Scraping Director | General Counsel | Monthly |
| R10 | DNC registry violations | Lead Acquisition Director | Compliance Officer | Monthly |
| R11 | CAN-SPAM violations | Marketing Director | Compliance Officer | Monthly |
| R12 | FCRA — lead scoring | SurplusAI Director | Prediction Radar Director | Monthly |
| R13 | State computer crime — scraping | Data Scraping Director | General Counsel | Monthly |
| R14 | Contract disclosure failure | FRG Director | General Counsel | Quarterly after remediation |
| R15 | Unconscionable fees | FRG Director | General Counsel | Quarterly after remediation |
| R16 | Data broker registration | Prediction Radar Director | Privacy Officer | Quarterly |
| R17 | Data breach notification | CISO | General Counsel | Quarterly after remediation |
| R18 | No cybersecurity program | CTO/CISO | General Counsel | Quarterly after remediation |
| R19 | Unlicensed money transmission | CFO | General Counsel | Monthly |
| R20 | SaaS terms inadequate | SaaS Director | General Counsel | Quarterly after remediation |

---

## 5. AGGREGATED COST OF NON-COMPLIANCE

### 5.1 Worst-Case Scenario (All Risks Materialize Simultaneously)

| Risk Category | Estimated Maximum Exposure |
|---------------|---------------------------|
| TCPA class actions (consent, DNC, mini-TCPA) | $100M - $500M |
| FRG finder's fee (disgorgement + fines all states) | $10M - $50M |
| UPL criminal charges + injunction (SurplusAI) | $1M - $10M + business closure |
| Attorney Marketplace (bar action, disgorgement) | $5M - $20M |
| FCRA class action (lead scoring) | $10M - $50M |
| Data scraping (CFAA + state criminal + civil) | $2M - $10M |
| Privacy (CCPA class action + state AG enforcement) | $10M - $50M |
| Criminal prosecution (any individual officer) | Prison time + fines |
| **TOTAL WORST-CASE** | **$138M - $690M+** |

### 5.2 Likely Near-Term Exposure (12-24 Months)

| Risk Scenario | Probability | Estimated Cost |
|---------------|-------------|----------------|
| TCPA demand letter or individual lawsuit | 80% | $50K - $500K settlement |
| State AG inquiry (data scraping or consumer complaint) | 40% | $100K - $500K defense |
| FTC investigation or civil investigative demand | 25% | $500K - $2M defense |
| TCPA class action filing | 20% | $2M - $10M settlement |
| State bar inquiry (attorney marketplace) | 30% | $100K - $500K defense |
| Privacy regulator complaint | 25% | $100K - $300K response |
| Data breach notification event | 15% | $100K - $1M response + notification |
| **LIKELY TOTAL NEAR-TERM COST** | | **$1M - $5M (even with partial compliance)** |

### 5.3 Cost of Compliance vs. Cost of Non-Compliance

| Metric | Amount |
|--------|--------|
| Estimated Year 1 Compliance Program Cost | $650K - $1.5M |
| Estimated Annual Ongoing Compliance Cost | $300K - $600K/year |
| Estimated Near-Term Non-Compliance Cost (12-24 months) | $1M - $5M+ |
| Estimated Catastrophic Non-Compliance Cost | $138M - $690M+ |
| **Return on Compliance Investment** | **2:1 to 10:1+ (worst-case: 100:1+)** |

---

## 6. KEY TO TERMS AND ABBREVIATIONS

| Abbreviation | Full Term |
|-------------|-----------|
| ABA | American Bar Association |
| ATDS | Automatic Telephone Dialing System |
| C&D | Cease and Desist |
| CAN-SPAM | Controlling the Assault of Non-Solicited Pornography And Marketing Act |
| CCPA/CPRA | California Consumer Privacy Act / California Privacy Rights Act |
| CFAA | Computer Fraud and Abuse Act |
| CFPB | Consumer Financial Protection Bureau |
| CISO | Chief Information Security Officer |
| CMP | Consent Management Platform |
| CPA | Colorado Privacy Act |
| CRA | Consumer Reporting Agency |
| CTIA | Cellular Telecommunications Industry Association |
| CTDPA | Connecticut Data Privacy Act |
| DNC | Do Not Call |
| ESIGN | Electronic Signatures in Global and National Commerce Act |
| FCRA | Fair Credit Reporting Act |
| FCC | Federal Communications Commission |
| FTC | Federal Trade Commission |
| GLBA | Gramm-Leach-Bliley Act |
| IOLTA | Interest on Lawyers' Trust Accounts |
| LMS | Learning Management System |
| NACHA | National Automated Clearing House Association |
| OCPA | Oregon Consumer Privacy Act |
| PCI DSS | Payment Card Industry Data Security Standard |
| PI/PII | Personal Information / Personally Identifiable Information |
| POA | Power of Attorney |
| RBAC | Role-Based Access Control |
| SPA | Service Provider Agreement |
| TCPA | Telephone Consumer Protection Act |
| TCR | The Campaign Registry |
| TDPSA | Texas Data Privacy and Security Act |
| ToS | Terms of Service |
| TSR | Telemarketing Sales Rule |
| UCC | Uniform Commercial Code |
| UDAP/UDAAP | Unfair, Deceptive (and Abusive) Acts or Practices |
| UETA | Uniform Electronic Transactions Act |
| UPL | Unauthorized Practice of Law |
| VCDPA | Virginia Consumer Data Protection Act |
| WISP | Written Information Security Program |

---

## AMENDMENT AND VERSION CONTROL

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-05-25 | Wheeler AI Ops — Legal Compliance Division | Initial Phase 1 Priority Risk Matrix |

---

*End of Document — Wheeler Ecosystem Phase 1 Priority Risk Matrix*
