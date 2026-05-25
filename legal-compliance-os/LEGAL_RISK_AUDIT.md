# WHEELER ECOSYSTEM — PHASE 1 LEGAL RISK AUDIT

**Document ID:** WHEELER-LEGAL-RISK-AUDIT-001  
**Classification:** CONFIDENTIAL — ATTORNEY-CLIENT PRIVILEGED  
**Date:** 2026-05-25  
**Author:** Wheeler Autonomous AI Ops — Legal Compliance Architecture Division  
**Status:** PHASE 1 — PRELIMINARY RISK IDENTIFICATION

---

## DISCLAIMER ⚠️

**THIS DOCUMENT IS NOT LEGAL ADVICE.** This audit identifies potential legal risk areas based on publicly available statutes, regulatory guidance, and enforcement trends. It does not constitute legal advice, create an attorney-client relationship, or replace the judgment of qualified licensed attorneys in each relevant jurisdiction. Wheeler Ecosystem MUST engage licensed counsel in each state where it operates before implementing any compliance program, drafting any agreement, or making any business decision based on this audit. Nothing in this document should be construed as a recommendation to engage in any specific conduct. Each section marked with ⚖️ requires independent attorney review.

**This document may be protected by attorney-client privilege and/or work product doctrine if prepared at the direction of legal counsel. Consult with the Wheeler Ecosystem General Counsel regarding privilege status.**

---

## TABLE OF CONTENTS

1. Executive Summary
2. Business Unit Risk Profiles
3. Risk Area Detailed Analysis
4. Total Risk Inventory
5. Attorney Review Flags
6. Appendix: Statutes and Regulatory Framework Reference

---

## 1. EXECUTIVE SUMMARY

### 1.1 Overall Risk Posture Assessment

| Dimension | Rating | Commentary |
|-----------|--------|-----------|
| **Overall Risk Posture** | **HIGH** | Multiple business lines operate in heavily regulated or gray-legal areas without evident compliance infrastructure |
| **Regulatory Exposure** | **CRITICAL** | TCPA, state debt collection, finder's fee, and UPL statutes carry individual penalties of $500-$1,500+ per violation; class action exposure |
| **Jurisdictional Complexity** | **CRITICAL** | Operating across all 50 states with different laws on finder's fees, solicitation, data scraping, and attorney referrals |
| **Litigation Risk** | **HIGH** | Lead generation, data scraping, and claimant outreach create class action exposure under TCPA, CFAA, and state consumer laws |
| **Regulatory Trend Direction** | **ADVERSE** | FTC aggressive on AI-related consumer harm, CCPA enforcement ramping, state privacy laws proliferating, TCPA scrutiny increasing |
| **Current Compliance Maturity** | **LOW** | No evidence of dedicated compliance function, policies, or controls |
| **Remediation Urgency** | **IMMEDIATE** | Cease certain operations pending attorney review recommended |

### 1.2 Entity Structure Risk

```
Wheeler Ecosystem (Holding Company)
├── Funds Recovery Group (FRG)        ← HIGHEST RISK: finder's fee regulatory maze
├── SurplusAI                         ← HIGH RISK: AI-generated content, data scraping
├── Ravyn Capital                     ← MEDIUM RISK: securities/investment regulations
├── Prediction Radar                  ← MEDIUM RISK: data aggregation, lead scoring
├── AI Ops Platform                   ← LOW RISK: internal infrastructure tool
├── Wheeler Brain OS                  ← LOW RISK: internal orchestration system
├── Attorney Marketplace              ← HIGH RISK: referral fees, UPL, platform liability
├── Lead Acquisition Systems          ← CRITICAL RISK: TCPA, CAN-SPAM, state solicitation
├── Data Scraping/Intelligence        ← HIGH RISK: CFAA, ToS breach, computer crime
└── SaaS/API Monetization             ← MEDIUM RISK: terms, data licensing, SLAs
```

### 1.3 Top 5 Critical Findings

1. **Finder's Fee Regulatory Maze (FRG):** Surplus funds recovery arrangements are regulated differently in every state. Some states prohibit finder's fees entirely (e.g., North Carolina), others require specific licensing (e.g., California real estate broker license), and many have specific disclosure requirements. Operating without state-by-state legal review creates existential regulatory risk.

2. **TCPA Class Action Exposure (Lead Acquisition):** Lead acquisition programs using automated text messaging, predictive dialers, or auto-dialers face $500-$1,500 per violation statutory damages. Class actions in this space routinely settle for $10M-$100M+. The TCPA's definition of "autodialer" remains broad post-Facebook ruling.

3. **Unauthorized Practice of Law (UPL) Risk (SurplusAI, Attorney Marketplace):** AI-generated legal document preparation, automated legal advice, or attorney-claimant matching services may constitute unauthorized practice of law. State bars aggressively prosecute UPL, typically as misdemeanor criminal offenses.

4. **Data Scraping Liability (Data Scraping/Intelligence):** Scraping county court websites raises claims under the Computer Fraud and Abuse Act (CFAA), state computer crime statutes, and breach of contract (ToS) claims. Recent Supreme Court precedent (Van Buren) narrowed CFAA but state claims remain potent.

5. **Multi-State Privacy Compliance Gap:** No evidence of CCPA/CPRA compliance program, opt-out mechanisms, privacy policy disclosures, or data inventory. With 12+ state comprehensive privacy laws now effective, cumulative non-compliance risk is substantial.

---

## 2. BUSINESS UNIT RISK PROFILES

### 2.1 Funds Recovery Group (FRG)

| Attribute | Assessment |
|-----------|-----------|
| **Risk Profile** | **CRITICAL** |
| **Revenue Model** | Finder's fee % of surplus funds recovered for claimants |
| **Key Statutes** | State finder's fee laws, real estate broker licensing, debt adjustment acts, consumer credit laws, state unfair/deceptive practices acts |
| **Regulatory Bodies** | State Attorney General offices, state real estate commissions, state banking departments, FTC, CFPB (potential jurisdiction) |
| **Primary Risk** | Finder's fees for surplus funds recovery are unlicensed real estate brokerage in many states |
| **Class Action Exposure** | HIGH — disgorgement of fees, statutory damages |
| **Criminal Exposure** | POTENTIAL — unauthorized practice of law, unlicensed real estate activity |

**Key Risk Factors:**

- **State-by-State Prohibition/Regulation:** At least 12 states have specific statutes regulating or prohibiting finder's fees in surplus funds/foreclosure contexts (CA, FL, NY, TX, IL, NC, OH, PA, GA, MI, WA, CO — partial list). Operating in all 50 states without state-specific analysis is high-risk.
- **Real Estate Broker Licensing:** Many states require a real estate broker license to arrange for the recovery of funds from real estate transactions (including surplus funds). Penalties for unlicensed activity include cease and desist orders, fines, and in some states, criminal prosecution.
- **Debt Adjustment Laws:** Some states classify surplus funds recovery arrangements as debt adjustment/debt management, which is heavily regulated or prohibited.
- **Finder's Fee Percentage:** Fee structure (typically 25-40%) may be deemed unconscionable under state law or constitute excessive contingent fees.
- **Vulnerable Consumer Population:** Claimants are often financially distressed, elderly, or unsophisticated — triggering enhanced consumer protection scrutiny under FTC Act Section 5 and state UDAP statutes.
- **Contingent Fee Structure:** Contingent fee arrangements for non-attorneys may violate state rules governing fee splitting with attorneys (if attorney involved).
- **Records/Notice Requirements:** Many states require specific notice to claimants, specific contract terms, and cooling-off periods.

⚖️ **ATTORNEY REVIEW REQUIRED:** State-by-state analysis of finder's fee legality for surplus funds recovery. This is the single highest-priority legal work item.

### 2.2 SurplusAI

| Attribute | Assessment |
|-----------|-----------|
| **Risk Profile** | **HIGH** |
| **Revenue Model** | SaaS subscriptions, lead scoring fees, data access fees |
| **Key Statutes** | FTC Act Section 5 (AI guidance), state AI laws, UPL statutes, FDCPA (if used for debt collection), FCRA (potential if lead scoring = consumer reporting) |
| **Regulatory Bodies** | FTC, state bars, state AGs, CFPB (potential), future federal AI regulator |
| **Primary Risk** | AI-generated surplus fund analysis = legal advice = UPL |
| **Class Action Exposure** | MEDIUM-HIGH |

**Key Risk Factors:**

- **AI as Legal Advice:** AI-generated assessments of surplus funds claims, legal rights, or recommended actions may constitute unauthorized practice of law if not supervised by licensed attorneys.
- **FCRA Risk:** If AI lead scoring evaluates consumer "creditworthiness, character, or reputation" for a "legitimate business need," it may constitute a consumer report under FCRA, requiring compliance including accuracy, dispute, and adverse action notice obligations.
- **Artificial Intelligence Liability:** FTC guidance on AI (2023-2025) emphasizes that AI-driven decisions must be accurate, fair, and explainable. Misleading consumers about AI capabilities violates Section 5.
- **Algorithmic Bias:** AI models trained on historical court data may perpetuate racial, economic, or geographic biases in lead scoring, creating fair lending (if applicable) and UDAP exposure.
- **Data Accuracy:** Errors in AI analysis that cause consumers to take incorrect legal action create tort liability for negligence and potential consumer fraud claims.

⚖️ **ATTORNEY REVIEW REQUIRED:** Whether SurplusAI constitutes the unauthorized practice of law. Whether lead scoring system constitutes a "consumer reporting agency" under FCRA.

### 2.3 Ravyn Capital

| Attribute | Assessment |
|-----------|-----------|
| **Risk Profile** | **MEDIUM** |
| **Revenue Model** | Real estate investment, property appreciation, rental income |
| **Key Statutes** | Securities Act (if syndicating), state real estate laws, landlord-tenant laws, fair housing laws |
| **Regulatory Bodies** | SEC (if securities involved), state real estate commissions, HUD |
| **Primary Risk** | Securities law compliance if raising capital from passive investors |
| **Class Action Exposure** | MEDIUM (securities) |

**Key Risk Factors:**

- **Securities Laws:** If Ravyn Capital raises money from passive investors for real estate acquisitions, the offerings must comply with federal and state securities laws (Reg D, state blue sky laws). Failure = rescission offers, investor lawsuits, SEC penalties.
- **Accredited Investor Verification:** If relying on accredited investor exemptions, proper verification under Rule 506(c) is required.
- **Property Management Liability:** Landlord-tenant laws, habitability requirements, security deposit regulations vary by jurisdiction.
- **Fair Housing Act:** Property acquisitions, tenant selection, and marketing must comply with federal and state fair housing laws.

⚖️ **ATTORNEY REVIEW REQUIRED:** Securities law compliance for any capital raising from passive investors.

### 2.4 Prediction Radar

| Attribute | Assessment |
|-----------|-----------|
| **Risk Profile** | **MEDIUM** |
| **Revenue Model** | Data subscriptions, API access, lead sales |
| **Key Statutes** | FCRA (potential), state data broker laws, CCPA/CPRA |
| **Regulatory Bodies** | FTC, state AGs, CFPB (potential) |
| **Primary Risk** | Classification as a "consumer reporting agency" |
| **Class Action Exposure** | MEDIUM |

**Key Risk Factors:**

- **FCRA Applicability:** If Prediction Radar assembles or evaluates consumer information for third parties to use for eligibility decisions (credit, insurance, housing, employment), it may be a consumer reporting agency. The key question is what subscribers do with the data.
- **Data Broker Regulations:** Several states (VT, CA, OR, TX, etc.) now have data broker registration laws. Failure to register = penalties and potential business disruption.
- **Accuracy Obligations:** Even if not FCRA-covered, inaccurate data that causes consumer harm creates tort liability under negligence and defamation theories.

⚖️ **ATTORNEY REVIEW REQUIRED:** FCRA applicability analysis. State data broker registration requirements.

### 2.5 AI Ops Platform & Wheeler Brain OS

| Attribute | Assessment |
|-----------|-----------|
| **Risk Profile** | **LOW** |
| **Revenue Model** | Internal tool (no direct revenue) |
| **Key Statutes** | N/A (internal infrastructure) |
| **Regulatory Bodies** | N/A |
| **Primary Risk** | Negligent operation causing downstream harm |
| **Class Action Exposure** | LOW |

**Key Risk Factors:**

- Internal orchestration tools primarily pose operational, not legal, risk.
- If the AI Ops Platform makes decisions about consumer-facing processes (e.g., automated lead triage), it could create vicarious liability.
- Security vulnerabilities in the platform could expose other business units to data breach liability.

### 2.6 Attorney Marketplace

| Attribute | Assessment |
|-----------|-----------|
| **Risk Profile** | **HIGH** |
| **Revenue Model** | Attorney referral fees, subscription, per-connection fees |
| **Key Statutes** | ABA Model Rules 5.4, 7.2, 7.3; state bar rules on referral fees; Section 230 CDA |
| **Regulatory Bodies** | State bar associations, FTC |
| **Primary Risk** | Illegal referral fees and improper attorney advertising |
| **Class Action Exposure** | MEDIUM |

**Key Risk Factors:**

- **ABA Model Rule 7.2:** Lawyers may not give anything of value to a person for recommending the lawyer's services. Fee-splitting with non-lawyers (including a marketplace platform) is prohibited by Rule 5.4 in virtually every state.
- **ABA Model Rule 5.4:** A lawyer or law firm shall not share legal fees with a non-lawyer. This is a near-universal prohibition. Platform-based per-connection or percentage fees likely violate this rule.
- **ABA Model Rule 7.3:** Direct solicitation of prospective clients is subject to strict limitations, including labeling requirements and prohibitions on harassment.
- **State Bar Advertising Rules:** Attorney advertising is heavily regulated at the state level. Mandatory disclaimers, filing requirements, and content restrictions apply.
- **Section 230 Immunity:** The marketplace may have Section 230 immunity for third-party attorney content, but this immunity is narrowing (FOSTA-SESTA, state law exceptions).
- **UPL Risk:** If the marketplace facilitates "matchmaking" that involves legal advice, recommends specific legal strategies, or vets legal claims, it may cross into UPL.

⚖️ **ATTORNEY REVIEW REQUIRED:** All fee arrangements with attorneys. Compliance of marketplace structure with ABA Model Rules and each state's bar rules. Section 230 immunity analysis.

### 2.7 Lead Acquisition Systems

| Attribute | Assessment |
|-----------|-----------|
| **Risk Profile** | **CRITICAL** |
| **Revenue Model** | Lead generation and sales to business units/third parties |
| **Key Statutes** | TCPA, CAN-SPAM, state telemarketing laws, state mini-TCPA (FL, OK, MD), telemarketing sales rule |
| **Regulatory Bodies** | FCC, FTC, state AGs, private plaintiffs' bar |
| **Primary Risk** | TCPA class action — $500-$1,500 per text/call with no cap |
| **Class Action Exposure** | **CRITICAL** |
| **Criminal Exposure** | POTENTIAL (criminal telemarketing fraud if deceptive) |

**Key Risk Factors:**

- **TCPA:** Automated calls/texts to cell phones without prior express written consent violate the TCPA. Each violation = $500-$1,500 statutory damages. Class actions routinely involve millions of calls/texts.
- **Prior Express Written Consent:** Lead acquisition through data partners, list purchases, or affiliate networks rarely obtains valid TCPA consent (consent must be clear, specific, and not obtained through lead aggregation).
- **Lead Generator Liability:** Companies that purchase leads are jointly liable for consent defects. The FCC has made clear that lead generators cannot obtain valid consent on behalf of unknown sellers.
- **State Mini-TCPA Laws:** Florida (2021), Oklahoma (2022), Maryland (2023), and others have enacted mini-TCPA laws with even stricter requirements — Florida allows $1,500 per violation with no federal preemption.
- **CAN-SPAM:** Commercial emails must include opt-out mechanisms, accurate header information, and truthful subject lines. Non-compliance = $50,120 per email.
- **DNC Registry:** Telemarketing calls to numbers on the National Do Not Call Registry violate the TCPA and TSR, with penalties of up to $43,792 per call.
- **Consent Revocation:** Consumers can revoke consent at any time through any reasonable means. Systems must honor revocation promptly.
- **SMS Aggregator/CARRIER Compliance:** Mobile carriers (CTIA) enforce messaging policies. High complaint rates = carrier blocking.
- **AI-Generated Call/Text Content:** FTC guidance confirms that AI-generated telemarketing calls/texts must comply with all TCPA/TSR requirements.

⚖️ **ATTORNEY REVIEW REQUIRED:** TCPA consent audit is URGENT. All lead sources, consent collection mechanisms, and call/text processes must be reviewed by TCPA counsel. Immediate cease of any SMS/auto-dialing programs recommended until consent validated.

### 2.8 Data Scraping / Intelligence

| Attribute | Assessment |
|-----------|-----------|
| **Risk Profile** | **HIGH** |
| **Revenue Model** | Data aggregation for internal use and API/sale |
| **Key Statutes** | CFAA, state computer crime laws, state trespass laws, breach of contract, copyright, state data broker laws |
| **Regulatory Bodies** | DOJ (criminal CFAA), state AGs, private plaintiffs |
| **Primary Risk** | CFAA and state computer crime claims from county/court websites |
| **Class Action Exposure** | MEDIUM-LOW |
| **Criminal Exposure** | POTENTIAL (state computer crime laws are criminal statutes) |

**Key Risk Factors:**

- **CFAA (18 U.S.C. 1030):** Accessing a computer without authorization or exceeding authorized access. Supreme Court narrowed in *Van Buren v. United States* (2021) — "exceeds authorized access" does not cover using information obtained permissibly for improper purposes. However, violating website ToS may still create liability if ToS restrictions constitute authorization limits.
- **State Computer Crime Laws:** Many states have broader computer crime statutes than the federal CFAA. Conviction can carry felony penalties.
- **Website Terms of Service:** Most county/court websites prohibit automated scraping/bots. Breach of contract claims do not require authorization questions — just prove contract formation and breach.
- **Trespass to Chattels:** Common law claim for unauthorized use of computer systems. Some states recognize this as a viable claim against scrapers.
- **Copyright in Court Records:** While court records are generally public domain, the compilation/database may have copyright protection. Systematic scraping of copyrighted databases can create infringement liability.
- **Rate Limiting/IP Blocking Evasion:** If scraping uses proxy rotation, IP spoofing, or bot detection circumvention, it may create additional criminal exposure under CFAA (exceeding authorization by accessing restricted areas) and fraud statutes.
- **Data Accuracy/Reliability:** Aggregated court data that is incorrect or stale creates liability if relied upon by consumers or attorneys.
- **Public Records Access Laws:** Some state open records laws may provide alternative access routes. Failure to use lawful alternatives undermines legal arguments for scraping.

⚖️ **ATTORNEY REVIEW REQUIRED:** CFAA risk assessment for each target website. ToS review. State computer crime law analysis by state. Assessment of whether public records request alternatives exist.

### 2.9 SaaS/API Monetization

| Attribute | Assessment |
|-----------|-----------|
| **Risk Profile** | **MEDIUM** |
| **Revenue Model** | Subscription fees, API usage fees, data licensing |
| **Key Statutes** | Contract law, UCC, state data broker laws, CCPA/CPRA |
| **Regulatory Bodies** | State AGs, FTC |
| **Primary Risk** | Inadequate contractual protections (limitation of liability, indemnification, data rights) |
| **Class Action Exposure** | LOW |

**Key Risk Factors:**

- **Standard SaaS Legal Issues:** Limitation of liability clauses, warranty disclaimers, indemnification obligations, SLA commitments, termination rights.
- **Data Licensing:** If APIs provide access to scraped data, licensing terms must address authorized use, redistribution restrictions, and pass-through compliance obligations.
- **Third-Party Claims:** Data provided through APIs that originates from scraping creates chain-of-title issues. API customers may face third-party claims, leading to indemnification demands on Wheeler.

⚖️ **ATTORNEY REVIEW REQUIRED:** SaaS terms of service. Data license agreements. API terms of use.

---

## 3. RISK AREA DETAILED ANALYSIS

### 3.1 Business Models — Finder's Fees / Revenue Recognition

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| Finder's fee as unlicensed brokerage | State real estate license laws | Disgorgement of fees, fines, criminal charges | CRITICAL |
| Fee unconscionability | State UDAP, UCC § 2-302 | Fee reduction, class action | HIGH |
| Contingent fee with attorneys | ABA Rule 5.4 | Bar discipline, fee forfeiture | HIGH |
| Revenue recognition timing | ASC 606/GAAP | Financial restatement, SEC if public | MEDIUM |
| Finder's fee caps | State finder's fee statutes | Fee limitation, customer refunds | HIGH |

**Detailed Analysis:**

- **State Real Estate License Laws (⚖️):** Finder's fees for surplus funds recovery may require a real estate license in most states. For example: California requires a real estate broker license (Cal. Bus. & Prof. Code § 10131) for "soliciting borrowers or lenders for real estate loans" or "negotiating loans on real property." Florida requires a real estate license for assisting others in "cashing in on surplus funds from tax deeds" (Florida Bar guidance). Penalties for unlicensed activity include cease and desist orders (Florida: $5,000 per violation), criminal misdemeanor charges (California: up to 6 months jail), and disgorgement of all fees.

- **Finder's Fee Statutes:** Several states have specific statutes capping/regulating finder's fees in foreclosure surplus contexts:
  - Florida: Chapter 717 (Unclaimed Property Act) requires specific disclosures, limits fees, and requires written contracts with 5-day cancellation rights.
  - California: Civil Code § 2946.1 regulates finder's fees for surplus funds after trustee's sale — requires specific notice, 10-day cancellation period, and caps fees.
  - Texas: Property Code § 34.04 requires court approval of fee arrangements for surplus funds recovery.
  - North Carolina: GS § 45-21.36A — finder's fees for surplus funds are prohibited.

- **FTC/CFPB Scrutiny:** The FTC has pursued actions against companies charging excessive fees to consumers for assistance with government benefits or fund recovery. The CFPB's UDAAP authority (Unfair, Deceptive, or Abusive Acts or Practices) could apply if consumers are confused about their rights or the value of services provided.

- **Total Fee Analysis:** If fees are 25-40% of recovered surplus, and the service involves minimal actual work (automated lead generation, document templates), regulator scrutiny is heightened. Compare to typical attorney contingent fees (33-40% in litigation) but attorneys bear substantial litigation risk and are regulated by ethical rules.

### 3.2 Lead Acquisition — TCPA, CAN-SPAM, State Solicitation

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| Auto-dialed texts/calls without prior express written consent | TCPA 47 U.S.C. § 227 | $500-$1,500 per violation, no cap | CRITICAL |
| Lead list purchases (consent chain broken) | FCC TCPA orders | Same as above — buyer liable for seller's consent defects | CRITICAL |
| DNC registry violations | TCPA, TSR 16 CFR 310 | $43,792 per call (TSR) | CRITICAL |
| State mini-TCPA violations | FL § 501.059, OK § 15-759.3, MD § 14-3801 | $1,500 per violation (FL), no federal preemption | CRITICAL |
| Commercial email without opt-out | CAN-SPAM 15 U.S.C. § 7701 | $50,120 per email | HIGH |
| AI-generated telemarketing messages | FTC TSR, FCC TCPA | Same TCPA/TSR penalties | HIGH |
| Affiliate/partner lead sourcing (vicarious liability) | FTC v. Dish Network, 9th Cir. | Vicarious liability for third-party compliance | HIGH |

**TCPA Compliance Framework (⚖️):**

The Telephone Consumer Protection Act (47 U.S.C. § 227) prohibits:
1. Making calls/texts using an "automatic telephone dialing system" (ATDS) or artificial/prerecorded voice to a cell phone without "prior express written consent."
2. Making telemarketing calls to a number on the National Do Not Call Registry.
3. Abandoning more than 3% of answered calls (TSR).
4. Calling before 8 AM or after 9 PM (recipient's time).

**Prior Express Written Consent Requirements:**
- Must be in writing
- Must clearly authorize the specific seller to call/text
- Must include the telephone number to be called
- Must include terms surrendering TCPA rights
- Lead generators CANNOT obtain consent for unknown sellers (FCC 2023 order)

**Case Law Exposure:**
- *Facebook v. Duguid* (2021): Supreme Court narrowed ATDS definition to systems that use a "random or sequential number generator." Reducing class action risk but not eliminating it — systems that store and dial from a list may still qualify.
- *Gadelhak v. AT&T* (2020): 7th Circuit — ATDS still includes systems that dial from a stored list if they have the capacity to generate numbers randomly/sequentially.
- **State mini-TCPAs are not preempted:** Florida's law applies to any text/call to a Florida number, with $1,500/violation and no ATDS requirement — just evidence of a call/text.

**Practical Risk Calculation:**
- If Wheeler sends 100,000 texts/month to leads with defective consent
- Average TCPA settlement: $10-$30 per text in class actions
- Estimated annual exposure: $12M-$36M (100,000 × $10-$30 × 12 months)

### 3.3 Client Intake — Consumer Protection

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| Failure to disclose material terms | FTC Act § 5, state UDAP | FTC enforcement, state AG actions, restitution | HIGH |
| Targeting vulnerable consumers | FTC Act § 5, state UDAP | Enhanced penalties, AG scrutiny | HIGH |
| No cancellation/right of rescission | State consumer laws, FTC cooling-off rule | Contract voidability, refund demands | MEDIUM |
| Failure to provide written estimates | Various state laws | Fines, contract voiding | MEDIUM |
| High-pressure sales tactics | FTC TSR, state telemarketing laws | Enhanced damages | MEDIUM |

**Detailed Analysis:**

- **Vulnerable Consumer Population (⚖️):** Surplus funds claimants are often:
  - Elderly homeowners who lost homes to foreclosure
  - Low-income individuals
  - Individuals with limited English proficiency
  - Individuals facing financial distress
  - These characteristics trigger enhanced protections under FTC Act Section 5 (unfair/deceptive practices), state UDAP statutes (many of which have specific protections for elderly or vulnerable consumers), and state laws targeting "homeowner recovery" scams.

- **FTC Cooling-Off Rule:** Applies to in-person sales at consumer's home or temporary locations (hotels, convention centers). Requires:
  - Written notice of 3-day cancellation right
  - Specific cancellation form language
  - Refund within 10 days of cancellation

- **State-Specific Requirements:** Many states require specific disclosures in surplus funds contracts. For example:
  - Florida: Written contract, 5-day cancellation, specific disclosure language regarding attorney involvement
  - California: 10-day cancellation, specific disclosures about free alternatives
  - Texas: Court approval required for fee arrangements

- **UDAAP (CFPB):** While the CFPB focuses on financial products/services, if Wheeler extends credit or payment plans, UDAAP analysis is needed. Unfair or abusive conduct includes taking unreasonable advantage of consumer lack of understanding.

### 3.4 Claimant Contracts — Assignment, POA, Disclosures

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| Unconscionable fee provisions | UCC § 2-302, state common law | Contract voidance, fee disgorgement | HIGH |
| Assignment of surplus rights without notice | State statutory requirements | Invalid assignment, fee loss | HIGH |
| Power of attorney abuse | State POA statutes | Criminal liability, revocation | HIGH |
| Inadequate fee disclosures | State disclosure laws, FTC Act | Restitution, penalties | HIGH |
| No cancellation right | FTC cooling-off rule, state laws | Contract voidability | MEDIUM |
| Contract ambiguity | Contract law | Interpretation against drafter | MEDIUM |
| Mandatory arbitration/class waiver | FAA, state law | Enforceability challenges | MEDIUM |

**Detailed Analysis (⚖️):**

- **Fee Structure Disclosure:** Contracts must clearly disclose:
  - Percentage fee (in 12pt+ bold font)
  - Dollar amount estimate (where possible)
  - Total fee as both percentage and estimated dollar amount
  - Statement that claimant can pursue directly without fee
  - Statement that no attorney representation is provided (if true)
  - Contact information for state bar or consumer protection agency

- **Assignment vs. POA (⚖️):** The legal mechanism for Wheeler to recover fees is critical:
  - **Assignment:** Claimant assigns their right to surplus funds to Wheeler, which then disburses after deducting fees. Some states require court approval for assignments of surplus rights.
  - **Power of Attorney:** Claimant grants POA to Wheeler to act on their behalf in recovering surplus. POA must comply with state POA statutes, including notarization, witness requirements, and specific powers granted.
  - **Service + Fee Agreement:** Wheeler performs services and claimant agrees to pay fee. This is the least risky structure but requires robust enforcement mechanisms.

- **Cooling-Off/Cancellation Rights:** Federal and state laws require:
  - 3-day cancellation (FTC Cooling-Off Rule for in-person)
  - 5-day cancellation (Florida specific)
  - 10-day cancellation (California specific)
  - All cancellation rights must be prominently displayed

- **Unconscionability Risk:** Courts may find a 25-40% fee for surplus recovery unconscionable when:
  - Claimants are unsophisticated
  - The service is primarily form preparation and filing
  - The actual work required is minimal
  - Alternatives (free or lower-cost) exist
  - The contract is adhesion (take-it-or-leave-it)

### 3.5 Attorney Referrals — ABA Model Rules, State Bar Rules

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| Fee splitting with non-lawyers | ABA Rule 5.4 | Bar discipline, disbarment of referring attorneys | CRITICAL |
| Referral fees (non-attorney receiving value) | ABA Rule 7.2 | Bar discipline, fee forfeiture | CRITICAL |
| Improper solicitor (third-party) | ABA Rule 7.3 | Bar discipline, criminal solicitation charges | HIGH |
| Unethical advertising | ABA Rule 7.1, state rules | Bar discipline, fines | HIGH |
| Lawyer referral service regulation | State-specific regulations | Operating unregistered service, penalties | HIGH |
| Compensated attorney matching | ABA Formal Op. 501 (2024) | Violation of ethical rules, litigation funding risk | CRITICAL |

**Detailed Analysis (⚖️):**

- **ABA Model Rule 5.4 — Professional Independence:** "A lawyer or law firm shall not share legal fees with a nonlawyer." This is adopted in virtually every state. If the Attorney Marketplace charges a percentage of legal fees, or per-connection fees to attorneys, it likely constitutes fee sharing.
  - Permitted exceptions: death benefit plans, retirement plans, court-awarded fees, law firm profit-sharing with non-lawyer employees after certain period.
  - **No exception exists for referral platforms.**

- **ABA Model Rule 7.2 — Advertising/Referrals:** "A lawyer shall not give anything of value to a person for recommending the lawyer's services." Exceptions include:
  - Paying reasonable advertising costs (traditional ads, not per-lead)
  - Paying for a "legal service plan" or "qualified lawyer referral service" (narrow definitions)
  - Rule 7.2(b) explicitly prohibits payment for referrals

- **ABA Model Rule 7.3 — Solicitation of Clients:** Direct solicitation of prospective clients for pecuniary gain is restricted. Written solicitations must be labeled "Advertising Material." In-person solicitation is prohibited. Electronic solicitations (email, text) may be treated as written solicitation.

- **State Bar Referral Service Regulations:** Many states regulate lawyer referral services (e.g., California Business & Professions Code § 6155, New York 22 NYCRR Part 1210, Florida Bar Rule 4-7.22). These regulations require:
  - Registration or certification of referral services
  - Non-discriminatory referral practices
  - Prohibition on fees based on a percentage of legal fees
  - Specific disclosures about service operation

- **Legal Service Plans vs. Referral Services:** A properly structured "legal service plan" may fall under a Rule 7.2 exception. Criteria:
  - Plan offers specific, defined legal services for a pre-paid or periodic fee
  - Plan does not restrict attorney selection beyond the plan's network
  - Plan is not a mere conduit for referrals

- **ABA Formal Opinion 501 (2024):** Addresses "online attorney matching services" and confirms that such services must comply with Rules 5.4, 7.1, 7.2, and 7.3. Services that charge attorneys for leads/connections must ensure they do not constitute fee sharing — but the distinction between "per-lead fee" and "fee sharing" is highly fact-dependent.

### 3.6 Data Scraping — CFAA, State Computer Crimes, ToS

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| CFAA civil/criminal liability | 18 U.S.C. § 1030 | Civil damages ($1K-$10K per violation), criminal (felony for aggregating >$5K in 1 year) | HIGH |
| State computer crime laws | State statutes (CA, NY, TX, FL, etc.) | Criminal penalties, civil claims | HIGH |
| Website ToS breach | Contract law | Injunction, damages | MEDIUM |
| Trespass to chattels | Common law | Injunction, damages | MEDIUM |
| Copyright in database compilation | 17 U.S.C. § 101 | DMCA takedown, damages | MEDIUM |
| Anti-circumvention (bot detection bypass) | CFAA, state laws, DMCA § 1201 | Enhanced criminal exposure | HIGH |

**Detailed Analysis (⚖️):**

- **CFAA after *Van Buren* (2021):** Supreme Court held that "exceeds authorized access" means obtaining information from specific areas of a computer that access was not permitted, not using permissibly obtained information for improper purposes. This narrowed CFAA but:
  - Scraping that circumvents IP blocks, uses fake credentials, or exploits technical vulnerabilities remains "without authorization"
  - Scraping after receiving a cease-and-desist letter or after IP blocking is clearly "without authorization"
  - Violating ToS is NOT per se a CFAA violation, but some courts (9th Circuit, *hiQ Labs v. LinkedIn*, 2021) recognize "revocation of authorization" through technical measures

- **State Computer Crime Laws (broader than CFAA):** Examples:
  - **California Penal Code § 502:** "Knowingly accesses and without permission takes... data" — no authorization required, no "exceeds authorized access" limitation. Internet users send requests (access) to servers (computers).
  - **New York Penal Law § 156.05:** Unauthorized use of a computer — broad definition of "computer" and "access"
  - **Texas Penal Code § 33.02:** Breach of computer security — even accessing a system knowing consent was not obtained
  - **Virginia Code § 18.2-152.6:** Computer invasion of privacy — if scraping involves personal information
  - Many state laws are NOT preempted by CFAA and can be enforced by state AGs or through private right of action

- **Website Terms of Service:** County/court websites typically:
  - Prohibit automated access/robots/spiders
  - Limit use to non-commercial purposes
  - Restrict download of bulk data
  - Specify "authorized use" policies
  - Breach of ToS = breach of contract. While not criminal, it creates injunctive risk and damages claims.

- **Copyright in Court Records/Rulings:** While court opinions and docket entries are generally public domain (government edicts doctrine),:
  - Database compilations may have copyright if arranged with sufficient originality
  - Commercial databases (e.g., Lexis, Westlaw) clearly have copyright in their formatting, annotations, and compilation
  - Data extracted from state/county systems that is then republished/sold creates additional copyright concerns

- **Practical Risk Profile:**
  - Cease-and-desist letters are likely from targeted court systems
  - State AG investigations possible if scraping interferes with court operations
  - Federal criminal CFAA charges unlikely for non-malicious scraping but possible under aggressive DOJ
  - Civil CFAA claims from targeted websites are the most probable legal action
  - ToS breach claims are actionable regardless of CFAA outcome

### 3.7 SMS/Email Outreach — Communication Compliance

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| Automated SMS without consent | TCPA, state laws | $500-$1,500 per text, class action | CRITICAL |
| SMS content (advertising/solicitation) | TCPA, CTIA guidelines | Carrier blocking, enforcement | HIGH |
| Email without opt-out | CAN-SPAM | $50,120 per email | HIGH |
| Deceptive email headers/subjects | CAN-SPAM | FTC enforcement | MEDIUM |
| State commercial email laws | CA B&P § 17538, etc. | State-specific penalties | MEDIUM |
| SHAFT content restrictions (CTIA) | CTIA Messaging Principles | Carrier blocking, service disruption | MEDIUM |

**Detailed Analysis:**

- **TCPA SMS Requirements (⚖️):**
  - Prior express written consent required for auto-dialed/automated SMS
  - Consent must be clear, specific, identify the sender, and include a TCPA waiver
  - Opt-in must be recorded and auditable
  - Opt-out (STOP) must be honored immediately
  - Consent cannot be sold/transferred as part of lead lists
  - Each message is a separate violation

- **CTIA (Cellular Telecommunications Industry Association) Guidelines:**
  - Carriers enforce SHAFT content restrictions (Sex, Hate, Alcohol, Firearms, Tobacco)
  - Surplus funds recovery messages may be classified as "financial services" requiring enhanced vetting
  - High complaint rates (>0.3% of messages) trigger carrier blocking
  - Application-to-Person (A2P) 10DLC registration required for business messaging
  - Campaign registration with The Campaign Registry (TCR) required
  - Non-compliance = carrier-level blocking of all messages

- **State Mini-TCPAs (Critical — overlaid on federal TCPA):**
  - **Florida (Telephone Solicitation Act, § 501.059):** Applies to any telephone call or text to a Florida number. Requires prior express written consent for ALL telephonic sales calls. No ATDS requirement. $1,500 per violation. No federal preemption.
  - **Oklahoma (§ 15-759.3):** Similar to Florida. Applies to any unsolicited telemarketing call to an Oklahoma number.
  - **Maryland (§ 14-3801):** Prohibits "telephone spam" — unsolicited calls/texts using autodialer or prerecorded voice.
  - **Trend:** Multiple other states considering mini-TCPA legislation in 2025-2026.

- **CAN-SPAM Requirements:**
  - Transactional/relationship messages: exempt
  - Commercial messages (advertising/solicitation):
    - Cannot use false or misleading header information
    - Cannot use deceptive subject lines
    - Must include valid physical postal address
    - Must include clear opt-out mechanism
    - Opt-out must be honored within 10 business days
    - Messages must be labeled as advertisement (though FTC does not require specific labeling)

### 3.8 AI-Generated Content — Liability, UPL, Hallucination

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| AI = unauthorized practice of law | State UPL statutes | Criminal charges, injunction | CRITICAL |
| AI hallucination/misinformation | FTC Act § 5, state UDAP | FTC enforcement, consumer fraud | HIGH |
| Attorney supervision of AI | ABA Formal Op. 512 (2024) | Bar discipline | HIGH |
| AI-generated document preparation | State UPL laws, ABA opinions | UPL charges | CRITICAL |
| Failure to disclose AI use | FTC guidance, state laws | FTC enforcement, consumer fraud | MEDIUM |
| Algorithmic bias/fairness | FTC Act § 5, FCRA (potential) | FTC enforcement, class action | MEDIUM |
| IP infringement (AI training) | Copyright law, DMCA | Copyright claims | MEDIUM |

**Detailed Analysis (⚖️):**

- **UPL — The Central Risk:** The unauthorized practice of law is a criminal offense in every state. Key distinctions:
  - **Legal Information vs. Legal Advice:** Providing general legal information is permissible; providing specific advice about a person's legal rights or recommending a course of legal action is UPL.
  - **Document Preparation:** Preparing legal documents for others is UPL in many states unless performed under attorney supervision. Automated document generation is particularly scrutinized.
  - **Case Evaluation:** AI analysis of claim value, likelihood of success, or recommended action is UPL.
  - **State Variations:** Some states (e.g., Arizona, Utah) have experimental regulatory sandboxes for alternative legal services. Most states do not.

- **ABA Formal Opinion 512 (2024):** Addresses attorney use of generative AI:
  - Lawyers must provide "competent representation" including understanding AI tools used
  - Lawyers must "supervise" AI output with human review
  - Lawyers must protect client confidentiality when using AI
  - Lawyers must ensure AI-generated content does not contain hallucinations or inaccurate citations
  - Client consent may be required for AI use in some circumstances

- **FTC AI Enforcement Guidance (2023-2025):**
  - FTC has made clear that AI is not a "get out of jail free card"
  - AI-generated claims must be truthful and substantiated
  - Companies are responsible for AI-generated content regardless of whether they built the AI
  - FTC has pursued "AI washing" (misleading claims about AI capabilities)
  - Automated decisions that harm consumers violate Section 5

- **Hallucination/Misinformation Liability:**
  - Tort: Negligent misrepresentation if AI provides inaccurate information that consumers rely on
  - Contract: If SaaS terms promise specific functionality and AI produces errors, breach of contract claims
  - Consumer fraud: State UDAP claims if AI systematically produces misleading analyses

### 3.9 Privacy/Security — CCPA, State Laws, FTC Section 5

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| No CCPA/CPRA compliance | Cal. Civ. Code § 1798.100 et seq. | $2,500-$7,500 per violation (statutory), private right of action for breaches | HIGH |
| No state privacy law compliance | VA, CO, CT, UT, OR, TX, etc. | State AG enforcement, $7,500/violation (some states) | HIGH |
| No privacy policy | CCPA, state laws, CalOPPA | $2,500+/day (CalOPPA), state enforcement | HIGH |
| No data inventory/mapping | CCPA, GDPR (if EU users) | Inability to respond to access/deletion requests | MEDIUM |
| No BAA with covered entities | HIPAA (potential if health data) | $50K-$1.5M per violation tier | MEDIUM |
| Data breach notification gaps | State breach laws (all 50 states) | $100-$1K per affected individual, class action | HIGH |
| No security program | FTC Act § 5, state security laws (NY SHIELD, etc.) | FTC enforcement (20-year consent decrees) | HIGH |

**Detailed Analysis (⚖️):**

- **CCPA/CPRA Compliance Requirements (effective since 2020, amended 2023):**
  - Right to know what personal information is collected/disclosed
  - Right to delete personal information
  - Right to opt out of sale/sharing of personal information
  - Right to non-discrimination for exercising rights
  - Right to correct inaccurate personal information
  - Right to limit use of sensitive personal information
  - Notice at collection required
  - Privacy policy must list all categories of PI collected, sources, purposes, and third-party recipients
  - Service provider agreements required with all data recipients
  - Mandatory annual reporting for high-volume data processors
  - Opt-out mechanism must be "easy for consumers to execute" — minimum of one method required

- **State Comprehensive Privacy Laws (effective dates):**
  | State | Law | Effective | Key Features |
  |-------|-----|-----------|--------------|
  | California | CPRA | 2020/2023 | Broadest — includes sensitive PI, opt-in for minors, private right of action for breaches |
  | Virginia | VCDPA | 2023 | Consent for sensitive data, opt-out for sale/targeted advertising |
  | Colorado | CPA | 2023 | Opt-out for sale/targeted advertising, sensitive data consent |
  | Connecticut | CTDPA | 2023 | Similar to Virginia |
  | Utah | UCPA | 2023 | More business-friendly, narrower definitions |
  | Oregon | OPCPA | 2024 | Broader than Colorado, includes dark patterns prohibition |
  | Texas | TDPSA | 2024 | Applies to small businesses, broad opt-out |
  | Others | Various | 2024-2026 | IA, IN, KY, MT, NH, NJ, TN, etc. |

- **Data Broker Registration Requirements:**
  - **Vermont:** First state to require data broker registration (2019). Annual registration with specific disclosures about data collection practices.
  - **California:** SB 806 (2023) — expanded data broker registration requirements. Civil penalties up to $10,000 per violation.
  - **Oregon, Texas, Florida, others:** Data broker registration laws passed or pending.

- **FTC Section 5 Enforcement Trend:**
  - FTC has brought numerous actions for inadequate security practices
  - *FTC v. Wyndham Worldwide* (3rd Cir. 2015): FTC has authority to regulate cybersecurity under Section 5
  - Safeguards Rule (16 CFR Part 314): Applies to financial institutions — if Wheeler handles consumer financial data (credit card, billing, surplus funds), compliance required
  - Recent FTC orders require companies to implement specific security measures, submit to third-party audits, and provide 20+ years of compliance reporting

- **SurplusAI Special Privacy Issues:**
  - Court records are public, but data derived from court records about individuals may still be "personal information" under state privacy laws
  - If SurplusAI processes personal information about known individuals for lead scoring, consent/opt-out obligations may apply
  - Surplus proceeds information may be considered "financial information" under state financial privacy laws (e.g., California Financial Information Privacy Act)

### 3.10 Marketplace Structure — Platform Liability, Section 230

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| Loss of Section 230 immunity | 47 U.S.C. § 230, FOSTA-SESTA, state laws | Defamation, tort claims against platform | MEDIUM |
| Intermediary/agency liability | Agency law, respondeat superior | Vicarious liability for marketplace actors | MEDIUM |
| Quality control obligations | State bar rules, UDAP | Consumer harm claims | MEDIUM |
| Rating/review liability | Defamation law | Claims from attorneys about negative reviews | LOW |
| Antitrust/competition | Sherman Act, state laws | Tying, exclusion claims | LOW |

**Detailed Analysis (⚖️):**

- **Section 230 Analysis:**
  - 47 U.S.C. § 230(c)(1): "No provider or user of an interactive computer service shall be treated as the publisher or speaker of any information provided by another information content provider."
  - **Scope:** Protects platforms from liability for third-party content (attorney profiles, claims, reviews).
  - **Limitations (increasing):**
    - FOSTA-SESTA (2018): Carve-out for content related to sex trafficking
    - Does not apply to federal criminal law
    - Does not apply to intellectual property claims (IP carve-out in § 230(e))
    - State law exceptions are proliferating (Florida, Texas social media laws — constitutionally challenged but trend is narrowing)
    - Does not apply if platform "creates or develops" content "in whole or in part"
  - **Risk:** If the Attorney Marketplace curates, edits, or recommends attorneys, it loses § 230 immunity. "Neutral platform" status requires minimal content creation.
  - **Risk:** If the marketplace integrates AI-generated recommendations or rankings, those AI outputs are platform content — not third-party content — and § 230 does not apply.

- **Vicarious Liability for Marketplace Participants:**
  - If attorneys on the marketplace engage in misconduct (negligence, fee abuse, fraud), the marketplace could face claims under vicarious liability or negligent referral theories.
  - Background checks and vetting of attorneys reduce negligent referral risk but increase operational responsibility.
  - Without vetting, the marketplace is "just a directory" which reduces liability but also reduces value.

### 3.11 Payment Flows — Money Transmitter, Escrow, Trust Accounting

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| Unlicensed money transmission | State money transmitter laws (all 50 states) | Criminal penalties, fines, disgorgement | HIGH |
| Escrow requirements | State escrow laws, bar rules | IOLTA violations (if attorney-involved), trust accounting violations | HIGH |
| Payment card processing | PCI DSS | Merchant account termination, fines, data breach liability | MEDIUM |
| Automated Clearing House (ACH) | NACHA rules | Fines, bank termination | MEDIUM |
| Third-party payment processing | Contract law, state laws | Processor liability for network activities | MEDIUM |

**Detailed Analysis (⚖️):**

- **Money Transmitter Laws:** If Wheeler holds, controls, or transmits consumer funds:
  - License is required in virtually every state (50 states + DC)
  - Requirements include: net worth minimums ($25K-$1M), surety bonds, regular reporting, background checks, compliance program
  - Penalties for unlicensed transmission: criminal prosecution, cease and desist, disgorgement, fines up to $10K/day
  - **Key question:** Does Wheeler ever hold surplus funds before disbursing to claimants? If yes, money transmitter issues apply.

- **Escrow/Trust Accounting Requirements:**
  - If an attorney is involved, surplus funds may need to be held in an IOLTA (Interest on Lawyers' Trust Accounts) trust account
  - Non-attorneys cannot maintain IOLTA accounts
  - Trust accounting has specific rules: no commingling, no use of client funds for business operations, regular reconciliation
  - State bar rules on trust accounting vary but all require detailed record-keeping

- **Payment Processing Structure Options:**
  - **Direct payment to Wheeler:** Collects full surplus, deducts fee, remits claimant share — HIGHEST regulatory risk (money transmitter, trust accounting)
  - **Attorney collects and disburses:** Attorney receives surplus, pays Wheeler — LOWER regulatory risk but creates dependent relationship with attorney partners
  - **Third-party escrow service:** Independent escrow handles funds — LOW regulatory risk for Wheeler but cost and logistics
  - **Contingent fee direct to attorney:** Claimant pays attorney, attorney pays Wheeler as separate service fee — MODERATE risk (fee-splitting scrutiny)

### 3.12 SaaS Terms — Limitation of Liability, Indemnification

| Sub-Risk | Applicable Law | Exposure | Severity |
|----------|---------------|----------|----------|
| No limitation of liability | Contract law, UCC | Unlimited damages exposure | HIGH |
| Weak indemnification | Contract law | Exposure to third-party claims | MEDIUM |
| Data rights/license ambiguity | Contract law, copyright | Ownership disputes, unauthorized use | MEDIUM |
| SLA without credits/exclusions | Contract law | Breach of contract claims | MEDIUM |
| No termination for breach | Contract law | Inability to terminate problematic customers | MEDIUM |

**Detailed Analysis:**

- **SaaS Terms Essentials (for SurplusAI, Prediction Radar, API offerings):**
  - Limitation of liability (cap at subscription fees paid, exclude consequential damages)
  - Warranty disclaimers (no implied warranties — UCC 2-316 compliance)
  - Service level agreement (uptime guarantees, credits, exclusions)
  - Data ownership (customer owns its data, Wheeler owns aggregated/anonymized data)
  - API usage limits (rate limits, volume caps, throttling)
  - Prohibited uses (no illegal use, no reverse engineering, no competitive use)
  - Termination (for breach, convenience, with data export rights)
  - Indemnification (mutual — for IP infringement, for breach of terms)
  - Information Security (maintain administrative, technical, physical safeguards)
  - Governing law and venue
  - Electronic signature acceptance (ESIGN/UETA compliance)
  - DMCA compliance (safe harbor, takedown procedures)

---

## 4. TOTAL RISK INVENTORY

### 4.1 Inventory by Severity

| ID | Risk Area | Business Unit | Severity | Key Statute(s) |
|----|-----------|---------------|----------|----------------|
| **CRITICAL** |
| R1 | Finder's fee as unlicensed brokerage | FRG | CRITICAL | State real estate license laws |
| R2 | TCPA — automated SMS/calls without consent | Lead Acquisition | CRITICAL | TCPA 47 U.S.C. § 227 |
| R3 | TCPA — lead list consent chain broken | Lead Acquisition | CRITICAL | TCPA, FCC orders |
| R4 | State mini-TCPA violations | Lead Acquisition | CRITICAL | FL § 501.059, OK § 15-759.3, MD § 14-3801 |
| R5 | Unauthorized practice of law (AI content) | SurplusAI | CRITICAL | State UPL statutes |
| R6 | Attorney fee splitting (marketplace fees) | Attorney Marketplace | CRITICAL | ABA Rule 5.4, state equivalents |
| R7 | Finder's fees prohibited by state law | FRG | CRITICAL | State-specific statutes (NC, etc.) |
| R8 | No privacy compliance program | All (data-processors) | CRITICAL | CCPA/CPRA, 12+ state privacy laws |
| **HIGH** |
| R9 | CFAA violations (website scraping) | Data Scraping | HIGH | 18 U.S.C. § 1030 |
| R10 | State computer crime laws (scraping) | Data Scraping | HIGH | State PC codes |
| R11 | DNC registry violations | Lead Acquisition | HIGH | TCPA, TSR 16 CFR 310 |
| R12 | CAN-SPAM violations | Lead Acquisition | HIGH | CAN-SPAM 15 U.S.C. § 7701 |
| R13 | Failure to disclose material terms | FRG, All | HIGH | FTC Act § 5, state UDAP |
| R14 | Unconscionable fee provisions | FRG | HIGH | UCC § 2-302, state common law |
| R15 | FCRA — lead scoring as consumer report | SurplusAI, Prediction Radar | HIGH | FCRA 15 U.S.C. § 1681 |
| R16 | Attorney referral fee violations | Attorney Marketplace | HIGH | ABA Rule 7.2 |
| R17 | Direct solicitation violations | Attorney Marketplace | HIGH | ABA Rule 7.3 |
| R18 | Website ToS breach (scraping) | Data Scraping | HIGH | Contract law |
| R19 | AI hallucination/misinformation liability | SurplusAI | HIGH | FTC Act § 5, state UDAP |
| R20 | Data breach notification failure | All | HIGH | State breach laws |
| R21 | No cybersecurity program | All | HIGH | FTC Act § 5, state laws |
| R22 | Unlicensed money transmission | FRG (payment flow) | HIGH | State money transmitter laws |
| **MEDIUM** |
| R23 | Copyright in database compilation | Data Scraping | MEDIUM | Copyright law |
| R24 | Section 230 immunity erosion | Attorney Marketplace | MEDIUM | 47 U.S.C. § 230, FOSTA-SESTA |
| R25 | Trespass to chattels (scraping) | Data Scraping | MEDIUM | Common law |
| R26 | State data broker registration failure | Prediction Radar, SurplusAI | MEDIUM | State data broker laws |
| R27 | Advertising law violations | All (marketing) | MEDIUM | FTC Act, state advertising laws |
| R28 | AI bias/discrimination | SurplusAI | MEDIUM | FTC Act § 5, fair lending |
| R29 | No privacy policy | All | MEDIUM | CalOPPA, CCPA |
| R30 | SaaS limitation of liability — missing/inadequate | SaaS/API | MEDIUM | Contract law, UCC |
| R31 | Cooling-off rule violations | FRG | MEDIUM | FTC cooling-off rule, state laws |
| R32 | Escrow/trust accounting compliance | FRG (payment flow) | MEDIUM | State escrow laws, bar rules |
| R33 | Multi-state contract compliance | FRG | MEDIUM | State consumer laws |
| R34 | Securities law compliance (capital raising) | Ravyn Capital | MEDIUM | Securities Act, state blue sky |
| R35 | E-signature compliance (ESIGN/UETA) | FRG, All | MEDIUM | ESIGN 15 U.S.C. § 7001, UETA |
| **LOW** |
| R36 | Fair housing compliance | Ravyn Capital | LOW | Fair Housing Act |
| R37 | CARTS/carrier compliance | Lead Acquisition | LOW | CTIA guidelines |
| R38 | PCI DSS compliance | All (payment processing) | LOW | PCI DSS |
| R39 | DMCA compliance | SaaS/API | LOW | DMCA |
| R40 | Antitrust/competition issues | Attorney Marketplace | LOW | Sherman Act |

### 4.2 Total Risk Score

| Category | Count |
|----------|-------|
| CRITICAL | 8 |
| HIGH | 14 |
| MEDIUM | 13 |
| LOW | 5 |
| **TOTAL** | **40** |

---

## 5. ATTORNEY REVIEW FLAGS ⚖️

The following items MUST be reviewed by licensed, experienced counsel. This list is not exhaustive.

### 5.1 Urgent (Cease Operations Pending Review)

| Flag | Description | Jurisdiction | Recommended Counsel Type |
|------|-------------|--------------|------------------------|
| FLAG-001 | Finder's fee legality for surplus funds recovery | All 50 states | Consumer finance regulatory attorney / state-licensed real estate attorney |
| FLAG-002 | TCPA consent audit — all lead sources and calling/texting systems | Federal + all 50 states | TCPA class action defense counsel |
| FLAG-003 | SurplusAI — whether AI-generated content = UPL | All 50 states | Legal ethics / UPL defense counsel |
| FLAG-004 | Attorney Marketplace fee structure compliance with ABA Rules | All 50 states + ABA | Legal ethics counsel / state bar regulatory counsel |
| FLAG-005 | Data scraping CFAA/state computer crime risk assessment | Federal + target states | Cyber law / CFAA defense counsel |

### 5.2 High Priority (Review Within 30 Days)

| Flag | Description | Recommended Counsel Type |
|------|-------------|--------------------------|
| FLAG-006 | Claimant contract templates — state-by-state compliance | Consumer contracts attorney |
| FLAG-007 | FCRA applicability for lead scoring / data products | FCRA / consumer reporting attorney |
| FLAG-008 | Privacy compliance program — CCPA/CPRA + comprehensive state laws | Privacy attorney / CIPP-US |
| FLAG-009 | Data scraping ToS review for all target websites | Internet law / contract attorney |
| FLAG-010 | Lead acquisition consent collection mechanisms | TCPA / direct marketing counsel |
| FLAG-011 | State data broker registration requirements | Privacy / regulatory attorney |
| FLAG-012 | Payment/escrow structure — money transmitter license analysis | Payment systems / banking attorney |
| FLAG-013 | SaaS/API terms of service and data license agreements | Technology transactions attorney |
| FLAG-014 | Securities law compliance for Ravyn Capital capital raising | Securities attorney |

### 5.3 Medium Priority (Review Within 90 Days)

| Flag | Description | Recommended Counsel Type |
|------|-------------|--------------------------|
| FLAG-015 | Multi-state contract and disclosure compliance for FRG | Consumer protection attorney |
| FLAG-016 | AI governance policy — FTC guidance compliance | AI regulatory / FTC defense attorney |
| FLAG-017 | Attorney Marketplace Section 230 immunity analysis | Internet law / platform liability attorney |
| FLAG-018 | E-signature workflow ESIGN/UETA compliance | Technology transactions attorney |
| FLAG-019 | CAN-SPAM compliance for email marketing programs | Direct marketing / advertising attorney |
| FLAG-020 | DMCA compliance for SaaS platform | Technology / IP attorney |

---

## 6. APPENDIX: STATUTES AND REGULATORY FRAMEWORK REFERENCE

### 6.1 Federal Statutes

| Statute | Citation | Relevance |
|---------|----------|-----------|
| Telephone Consumer Protection Act (TCPA) | 47 U.S.C. § 227 | Automated calls/texts, DNC, consent |
| CAN-SPAM Act | 15 U.S.C. § 7701 et seq. | Commercial email |
| Computer Fraud and Abuse Act (CFAA) | 18 U.S.C. § 1030 | Unauthorized computer access |
| Fair Credit Reporting Act (FCRA) | 15 U.S.C. § 1681 et seq. | Consumer reporting, lead scoring |
| FTC Act Section 5 | 15 U.S.C. § 45 | Unfair/deceptive acts or practices |
| Telemarketing Sales Rule (TSR) | 16 CFR Part 310 | Telemarketing, DNC |
| Communications Act | 47 U.S.C. § 151 et seq. | FCC authority |
| Electronic Signatures in Global and National Commerce Act (ESIGN) | 15 U.S.C. § 7001 et seq. | Electronic signatures |
| Section 230 — Communications Decency Act | 47 U.S.C. § 230 | Platform liability |
| Securities Act of 1933 | 15 U.S.C. § 77a et seq. | Capital raising |
| Fair Housing Act | 42 U.S.C. § 3601 et seq. | Housing discrimination |
| Copyright Act | 17 U.S.C. § 101 et seq. | Database compilation, DMCA |
| Gramm-Leach-Bliley Act (GLBA) | 15 U.S.C. § 6801 et seq. | Financial privacy (if applicable) |

### 6.2 State Statutes (Selected)

| Statute | State | Relevance |
|---------|-------|-----------|
| California Consumer Privacy Act (CCPA/CPRA) | CA | Comprehensive privacy |
| California Business & Professions Code § 17200 | CA | Unfair competition |
| California Penal Code § 502 | CA | Computer crimes |
| California Business & Professions Code § 6155 | CA | Lawyer referral services |
| Florida Telephone Solicitation Act | FL | Mini-TCPA |
| Florida Chapter 717 (Unclaimed Property) | FL | Finder's fees |
| New York Penal Law § 156.05 | NY | Computer crimes |
| Texas Property Code § 34.04 | TX | Surplus funds regulation |
| Texas Penal Code § 33.02 | TX | Computer crimes |
| Virginia Code § 18.2-152.6 | VA | Computer invasion of privacy |
| Virginia Consumer Data Protection Act (VCDPA) | VA | Comprehensive privacy |
| Colorado Privacy Act (CPA) | CO | Comprehensive privacy |
| Connecticut Data Privacy Act (CTDPA) | CT | Comprehensive privacy |
| Oregon Consumer Privacy Act (OCPA) | OR | Comprehensive privacy |
| Texas Data Privacy and Security Act (TDPSA) | TX | Comprehensive privacy |

### 6.3 ABA Model Rules (Advisory — adopted with variations by states)

| Rule | Subject | Relevance |
|------|---------|-----------|
| ABA Model Rule 5.4 | Professional Independence — Fee Sharing | Attorney Marketplace |
| ABA Model Rule 5.5 | Unauthorized Practice of Law | SurplusAI, Document Workflows |
| ABA Model Rule 7.1 | Communications Concerning Services | Attorney Advertising |
| ABA Model Rule 7.2 | Advertising — Referrals | Referral Fees |
| ABA Model Rule 7.3 | Direct Contact with Prospective Clients | Solicitation |
| ABA Model Rule 1.5 | Fees | Contingent Fees |
| ABA Formal Opinion 501 (2024) | Online Attorney Matching Services | Marketplace Structure |
| ABA Formal Opinion 512 (2024) | Use of Generative AI | AI-Generated Content |

### 6.4 Regulatory Guidance

| Document | Issuer | Relevance |
|----------|--------|-----------|
| FTC Guidance on AI and Algorithms (2023-2025) | FTC | AI-generated content, bias, accuracy |
| FCC Implementation of the TCPA (2023-2024 Orders) | FCC | Lead generator consent, ATDS definition |
| CFPB UDAAP Examination Manual | CFPB | Consumer protection standards |
| FCC TCPA Omnibus Declaratory Ruling (2023) | FCC | Lead generator consent requirements |
| FTC Safeguards Rule Compliance Guide | FTC | Information security programs |

---

## AMENDMENT AND VERSION CONTROL

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-05-25 | Wheeler AI Ops — Legal Compliance Division | Initial Phase 1 Risk Audit |

---

*End of Document — Wheeler Ecosystem Phase 1 Legal Risk Audit*
