# WHEELER ECOSYSTEM — AI GOVERNANCE POLICY

**Document ID:** WHEELER-AIGOV-001
**Version:** 1.0.0
**Effective Date:** 2026-05-25
**Review Date:** 2026-08-25 (next quarterly review)
**Classification:** Internal — CONFIDENTIAL
**Owner:** AI Governance Board
**Status:** ACTIVE

---

## EXECUTIVE SUMMARY

Wheeler Ecosystem is an AI-native company operating in a heavily regulated legal/financial domain. AI is embedded in every layer of the organization — from infrastructure self-healing and predictive analytics to legal document assembly and attorney matching. This policy establishes the governance framework that enables Wheeler to deploy AI aggressively while maintaining legal compliance, ethical integrity, and human accountability.

The central governance challenge is the tension between rapid AI deployment and the obligations of a legal services ecosystem. This policy resolves that tension through: (1) a risk-tiered framework where governance scales with risk, (2) explicit prohibited actions that no AI may perform, (3) mandatory human review gates at all critical decision points, (4) comprehensive transparency and disclosure requirements, and (5) clear accountability and decision rights.

**This document is a governance framework, not legal advice. Items requiring attorney review are marked with ⚖️ ATTORNEY REVIEW REQUIRED.**

---

## TABLE OF CONTENTS

1. [AI GOVERNANCE PRINCIPLES](#1-ai-governance-principles)
2. [AI USE CASE REGISTRY](#2-ai-use-case-registry)
3. [PROHIBITED AI ACTIONS](#3-prohibited-ai-actions)
4. [HUMAN REVIEW REQUIREMENTS](#4-human-review-requirements)
5. [AI MODEL GOVERNANCE](#5-ai-model-governance)
6. [AI TRANSPARENCY & DISCLOSURE](#6-ai-transparency--disclosure)
7. [BIAS, FAIRNESS & ETHICS](#7-bias-fairness--ethics)
8. [AI SECURITY](#8-ai-security)
9. [AI GOVERNANCE OPERATING MODEL](#9-ai-governance-operating-model)
10. [COMPLIANCE MAPPING](#10-compliance-mapping)
11. [APPENDICES](#appendices)

---

## 1. AI GOVERNANCE PRINCIPLES

### 1.1 Core Principles

**Principle 1 — Human Accountability**: AI assists, humans decide. No AI makes final legal, financial, or high-stakes decisions autonomously. Every AI system has a named human accountable for its outputs.

**Principle 2 — Transparency**: When AI is involved in any interaction with claimants, attorneys, regulators, or the public, its involvement is disclosed. No impersonation of human judgment or identity.

**Principle 3 — Explainability**: AI decisions that affect individuals must be explainable in plain language. The logic, data, and factors leading to any outcome affecting a claimant or attorney must be reproducible and communicable.

**Principle 4 — Fairness**: AI must not discriminate based on protected characteristics including race, color, religion, national origin, sex, age, disability, genetic information, or any other protected class under federal, state, or local law.

**Principle 5 — Privacy**: AI must respect data minimization, purpose limitation, and individual privacy rights. Personal information used by AI systems must be justified, minimized, and protected.

**Principle 6 — Security**: AI systems must be secured against adversarial attacks, data poisoning, model inversion, prompt injection, and unauthorized access.

**Principle 7 — Reliability**: AI must be tested, monitored, and have defined failure modes. Systems must degrade gracefully and alert humans when operating outside normal parameters.

**Principle 8 — Contestability**: Individuals affected by AI decisions must have a mechanism to contest those decisions and obtain meaningful human review.

**Principle 9 — Accountability**: Clear ownership for AI system outcomes. Every AI system has an assigned owner, and every high-stakes AI output requires human sign-off.

**Principle 10 — Proportionality**: Governance rigor scales with risk. Low-risk AI automation receives lighter governance; high-risk AI receives intensive oversight. One size does not fit all.

### 1.2 AI Risk Tier Framework

| Tier | Risk Level | Definition | Examples | Governance Requirements |
|------|-----------|------------|----------|------------------------|
| **Tier 0** | No AI | Manual processes, deterministic rules, no machine learning or LLM involvement | Static configuration files, cron jobs, hardcoded business rules | None |
| **Tier 1** | Low Risk | Infrastructure monitoring, operational alerts, system health checks. No individual impact. | Prometheus alerts, PM2 health checks, log analysis, disk usage monitoring | Automated with human override. No individual rights affected. |
| **Tier 2** | Moderate Risk | Internal analytics, performance measurement, internal recommendations. Indirect individual impact possible. | Lead scoring (internal), performance analytics, capacity routing suggestions, internal reporting | Human-in-the-loop sampling. Quarterly audit. |
| **Tier 3** | High Risk | Systems that materially affect individuals' legal or financial interests with human review built in. | Document assembly, outreach content generation, claim-to-funds matching, attorney suggestions | Mandatory human review before any external action. Full audit trail. |
| **Tier 4** | Critical Risk | Systems that could cause significant harm if wrong, even with human review. Strategic recommendations. | Legal strategy recommendations, financial decisions, voice AI claimant conversations, settlement range analysis | Mandatory human approval + independent second review + appeal mechanism. Real-time monitoring. |
| **Tier 5** | Prohibited | Actions that no AI may perform under any circumstances. | See [Section 3 — Prohibited AI Actions](#3-prohibited-ai-actions) | Hard technical and policy block. |

### 1.3 Risk Classification Process

All AI systems must be classified into a risk tier before deployment. Classification is performed by the AI Review Committee (see [Section 9](#9-ai-governance-operating-model)). Reclassification occurs when:
- System capabilities materially change
- New data sources are added
- Regulatory requirements change
- Post-incident review determines misclassification

---

## 2. AI USE CASE REGISTRY

### 2.1 Registry Management

The AI Use Case Registry is the authoritative inventory of all AI systems in the Wheeler Ecosystem. Every system that uses machine learning, large language models, natural language processing, predictive analytics, or any form of artificial intelligence must be registered. Registration is a prerequisite for deployment.

**Registry Fields**:
- **ID**: Unique identifier (AI-NNN)
- **System Name**: Human-readable name
- **Owner**: Responsible individual
- **Capabilities**: Specific functions performed
- **Data Used**: Data sources and types
- **Decisions**: What decisions the AI makes or influences
- **Risk Tier**: 0-5 as defined in Section 1.2
- **Human Review**: Type and frequency of required human review
- **Audit Trail**: Audit mechanism and retention period
- **Status**: Active / Planned / Paused / Decommissioned / Prohibited

### 2.2 Complete AI System Inventory

| ID | System | Capabilities | Data Used | Decisions | Risk Tier | Human Review | Audit Trail | Status |
|----|--------|------------|-----------|-----------|-----------|-------------|-------------|--------|
| AI-001 | SurplusAI Lead Scoring | Scores surplus fund leads by recovery probability | Court records, property data, historical outcomes | Influences outreach priority and resource allocation | Tier 2 | Sampling review (quarterly) | Logged — decisions, scores, factors | Active |
| AI-002 | SurplusAI Document Assembly | Generates claim documents from templates and claimant data | Claimant data, court forms, case metadata, document templates | Drafts documents for attorney review and signature | Tier 3 | Mandatory attorney review before filing | Full audit — version history, reviewer, changes | Active |
| AI-003 | Wheeler Brain OS — Health Check | Monitors service health, detects anomalies, triggers remediation | Prometheus metrics, Docker container state, PM2 process state, system logs | Auto-restarts unhealthy services, alerts on-call | Tier 1 | Human override available, post-action notification | Logged — all actions timestamped | Active |
| AI-004 | Wheeler Brain OS — Automated Remediation | Executes predefined remediation playbooks for common failure modes | System metrics, error logs, health check results, runbook definitions | Chooses and executes remediation steps | Tier 1 | Human override, automatic rollback on failure | Full audit — decision tree, action taken, outcome | Active |
| AI-005 | Wheeler Brain OS — Drift Detection | Detects configuration drift and security posture changes | Infrastructure configuration, security group definitions, deployment manifests | Alerts on drift, recommends remediation | Tier 1 | Human review of recommendations | Logged | Active |
| AI-006 | Voice AI — Claimant Outreach | AI voice agent makes outbound calls to potential claimants | Claimant contact data, consent records, approved scripts | Conducts scripted conversations, captures responses | Tier 4 | Mandatory human review of all scripts before deployment | Full recording — all calls recorded and logged | Planned |
| AI-007 | Attorney Marketplace Matching | Matches claimants to attorneys based on case type and geography | Claimant location, case type, attorney practice areas, capacity, performance data | Suggests ranked attorney matches for claimant | Tier 3 | Human confirmation of match before connection | Logged — match criteria, options presented, selection | Active |
| AI-008 | Prediction Radar — Real Estate | Predictive analytics for real estate market timing and valuation | Public property records, market data, economic indicators | Generates market timing signals and valuation estimates | Tier 2 | Analyst review of model outputs | Logged — predictions, confidence, factors | Active |
| AI-009 | Prediction Radar — Lead Value | Predictive scoring of lead value and conversion probability | Lead source, behavior data, historical conversion data | Ranks leads by predicted value | Tier 2 | Periodic validation against actuals | Logged — scores and features | Active |
| AI-010 | Outreach Email Generation | Generates personalized email sequences for lead engagement | Lead profile, engagement history, approved templates, content library | Drafts email copy for review | Tier 3 | Mandatory compliance review before sending | Full audit — drafts, reviewer, changes, send decision | Active |
| AI-011 | Outreach SMS Generation | Generates SMS messages for lead communication | Lead profile, consent status, approved message templates | Drafts SMS copy for review | Tier 3 | Mandatory compliance review before sending | Full audit — drafts, reviewer, changes | Active |
| AI-012 | AI Ops — Self-Healing Engine | Autonomous infrastructure repair: restart services, clear caches, rotate containers | System metrics, error patterns, remediation playbooks | Executes repairs within defined guardrails | Tier 1 | Alert + rollback on failure, escalation on repeated failure | Full audit — diagnosis, action, result | Active |
| AI-013 | AI Ops — Capacity Planning | Predicts infrastructure capacity needs from usage trends | CPU/memory/disk metrics, traffic patterns, growth trends | Recommends scaling actions | Tier 2 | Human approval required for scaling | Logged | Active |
| AI-014 | Revenue Optimization — Pricing | AI-driven pricing recommendations for services | Market rates, competitor data, demand signals, historical pricing | Suggests price adjustments | Tier 2 | Human approval required for changes | Logged — model inputs, recommendation, decision | Active |
| AI-015 | Cost Optimization — Infrastructure | Identifies cost reduction opportunities in cloud/infrastructure spend | Cloud billing data, resource utilization, pricing models | Recommends resource rightsizing or reservation changes | Tier 2 | Human review and approval required | Logged | Active |
| AI-016 | Financial Forecasting | AI-driven financial projections and scenario modeling | Historical financial data, market conditions, growth metrics | Generates forecast scenarios for planning | Tier 2 | CFO review of forecasts | Logged | Active |
| AI-017 | CEO Command Console — Summaries | AI-generated executive summaries from operational data | All system metrics, financial data, health status | Generates daily/weekly summaries for leadership | Tier 1 | CEO review before external distribution | Logged — sources and generation parameters | Active |
| AI-018 | CEO Command Console — Recommendations | AI-generated strategic recommendations from data analysis | Cross-system data, market intelligence, performance metrics | Suggests strategic actions for CEO consideration | Tier 3 | CEO decision required, AI does not act | Full audit — data, analysis, recommendation, decision | Active |
| AI-019 | Document Analysis — Discovery | AI-assisted analysis of legal documents for relevant information | Legal documents, court filings, discovery materials | Identifies relevant passages, summarizes content | Tier 3 | Attorney verification of AI findings | Full audit — documents analyzed, findings, verified by | Active |
| AI-020 | Claimant Identification | Identifies potential claimants from public records and data sources | Court records, property records, public databases | Generates list of potential claimants for review | Tier 2 | Human review of list before outreach | Logged — sources, match criteria, results | Active |
| AI-021 | Attorney Capacity Routing | Routes cases to attorneys based on capacity, expertise, and performance | Attorney caseload, case type, performance metrics, availability | Suggests optimal case routing | Tier 3 | Human confirmation of routing decision | Logged — routing factors, options, decision | Active |
| AI-022 | Content Generation — Marketing | AI-generated marketing and educational content | Brand guidelines, approved topics, content library, audience data | Generates draft content for marketing | Tier 2 | Marketing review before publication | Logged — generation parameters, reviewer | Active |
| AI-023 | Sentiment Analysis — Claimant Feedback | Analyzes claimant sentiment from communications | Communication logs, survey responses, call transcripts | Identifies satisfaction trends and flags concerns | Tier 2 | Escalation of flagged concerns to human | Logged | Active |
| AI-024 | Compliance Monitoring — AI Ops | Monitors AI system behavior for policy violations | AI system logs, decision records, access logs | Flags potential policy violations for investigation | Tier 1 | Human investigator review of flags | Full audit — all monitoring actions logged | Active |
| AI-025 | Fraud Detection — Claim Review | AI analysis of claims for potential fraud indicators | Claim data, historical fraud patterns, verification results | Flags claims for enhanced human review | Tier 3 | Mandatory human investigation of flagged claims | Full audit — flags, evidence, investigation outcome | Planned |
| AI-026 | Settlement Range Analysis | AI analysis of historical settlement data to suggest ranges | Settlement data, case characteristics, jurisdictional factors | Suggests settlement ranges for attorney consideration | Tier 4 | Attorney review + independent verification | Full audit | Planned |
| AI-027 | Document Redaction — PII | AI-assisted identification and redaction of PII in legal documents | Legal documents, PII patterns, redaction rules | Identifies and suggests redactions | Tier 3 | Human verification of all redactions | Full audit | Planned |
| AI-028 | Court Date Prediction | Predictive analysis of court timeline and duration | Court schedules, case type, jurisdiction, judge history | Estimates case timeline for planning | Tier 2 | Human use of estimates, no automated reliance | Logged | Planned |
| AI-029 | Attorney Performance Analytics | AI-driven analysis of attorney performance metrics | Case outcomes, client satisfaction, efficiency metrics | Generates performance insights for internal use | Tier 2 | Human review before any performance decisions | Logged | Active |
| AI-030 | Lead Scoring — Refinement | Continuous improvement of lead scoring from outcome feedback | Lead scores, actual outcomes, conversion data | Refines scoring algorithm based on outcomes | Tier 2 | Quarterly model validation | Logged — model versions, performance metrics | Active |
| AI-031 | Claude Code Agent Army | 50+ autonomous AI agents for infrastructure, development, and operations | System state, codebase, configuration, operational data | Executes defined operational and development tasks | Tier 1 | Human override, defined scope, no external actions | Full audit — all agent actions logged | Active |
| AI-032 | AI Ops Watchdog | Automated health monitoring and reporting with trend analysis | Cross-system health metrics, historical baselines, alert history | Generates health reports, identifies trends, predicts issues | Tier 1 | Alert escalation, no autonomous action | Logged | Active |
| AI-033 | Rate Limiting — AI API | AI-driven rate limit management for API services | API usage patterns, quota consumption, error rates | Adjusts rate limits within configured bounds | Tier 1 | Override available, boundaries enforced | Logged | Active |

### 2.3 Registration Process

1. **Pre-Development**: Any new AI system or capability must be pre-registered with the AI Review Committee
2. **Risk Classification**: Committee assigns risk tier within 5 business days
3. **Full Registration**: Complete registry entry within 10 business days of classification
4. **Pre-Deployment Review**: Tier 3+ systems require deployment approval
5. **Post-Deployment Audit**: All systems audited within 30 days of activation
6. **Periodic Review**: Annual recertification for all Tier 2+ systems

---

## 3. PROHIBITED AI ACTIONS

### 3.1 Absolute Prohibitions

The following AI actions are **PROHIBITED WITHOUT EXCEPTION**. These prohibitions are enforced through technical controls, policy, and contractual provisions. Any violation requires immediate escalation to the AI Governance Board and may result in disciplinary action up to and including termination.

| ID | Prohibition | Rationale | Enforcement |
|----|-------------|-----------|-------------|
| P-01 | Providing legal advice without attorney review and approval | Unauthorized practice of law (UPL) violations in all 50 states | Technical block on AI outputs containing legal conclusions + policy |
| P-02 | Signing or filing legal documents autonomously | Only licensed attorneys may sign or file legal documents | Technical block on signature/document submission APIs |
| P-03 | Making binding financial commitments or contractual offers | AI cannot form contracts or make financial commitments | Technical block on payment/contracting systems |
| P-04 | Making representations about case outcomes or recovery amounts | Creates unrealistic expectations, potential fraud liability | Content filter + human review gate |
| P-05 | Communicating with courts or government agencies | Only licensed attorneys may communicate with courts | Technical block on court/government communication systems |
| P-06 | Making decisions about individual rights, eligibility, or legal status | Due process and individual rights require human determination | Policy + human review gate |
| P-07 | Determining attorney-client relationship scope or terms | Attorney-client relationship requires mutual informed consent | Policy + human-only workflow |
| P-08 | Waiving any legal rights on behalf of claimants or Wheeler | Rights waivers require knowing and voluntary action by the rights holder | Technical block + policy |
| P-09 | Accessing or using PII without authorization and logging | Privacy law compliance, breach risk | Access controls + mandatory logging |
| P-10 | Deploying new AI capabilities without governance review | Uncontrolled AI deployment creates unacceptable risk | CI/CD gate requiring governance approval |
| P-11 | AI impersonating a human (any context) | Fraud, deception, regulatory violations | Disclosure requirement in all AI interactions |
| P-12 | AI impersonating an attorney | Unauthorized practice of law, fraud | Technical content block + policy |
| P-13 | AI generating testimonials or fake reviews | FTC regulations, fraud liability | Content filter + human review |
| P-14 | AI making decisions about attorney pricing or fee arrangements | Fee arrangements require attorney agreement and regulatory compliance | Policy + human-only workflow |
| P-15 | AI modifying or deleting audit trails | Audit integrity is essential for compliance and accountability | Technical block — immutable audit logs |

### 3.2 Conditional Prohibitions (Requiring Governance Board Exception)

These actions are prohibited by default but may be permitted with explicit AI Governance Board approval:

| ID | Action | Conditions for Exception |
|----|--------|------------------------|
| CP-01 | AI-initiated changes to production infrastructure above defined thresholds | Written CTO approval, rollback plan, monitoring, post-action review |
| CP-02 | AI access to new categories of personal data | DPA amendment, privacy impact assessment, data minimization plan |
| CP-03 | AI fine-tuning on Wheeler proprietary data | Security review, data sanitization, access controls, versioning |
| CP-04 | AI system integration with external third-party systems | Security review, data flow mapping, contractual safeguards |
| CP-05 | AI deployment in a new regulatory jurisdiction | Regulatory analysis, local counsel review, compliance plan |

### 3.3 Prohibition Violation Protocol

1. **Detection**: Automated monitoring or human report identifies potential violation
2. **Immediate Containment**: System owner halts affected AI system within 30 minutes
3. **Escalation**: Report to AI Governance Board within 24 hours
4. **Investigation**: Root cause analysis completed within 5 business days
5. **Remediation**: Corrective actions implemented within 10 business days
6. **Prevention**: Systemic controls updated to prevent recurrence
7. **Disclosure**: Legal determines whether external disclosure is required

---

## 4. HUMAN REVIEW REQUIREMENTS

### 4.1 Mandatory Human Review Gates

AI systems at or above Tier 3 must pass through defined human review gates before their outputs affect individuals or external systems.

**Gate G-01 — Document Review Gate**
- **Applies to**: AI-002 (Document Assembly), AI-019 (Document Analysis), AI-027 (Document Redaction)
- **Requirement**: Any AI-generated legal document, filing, or court submission MUST be reviewed by a licensed attorney before use, filing, or delivery
- **Documentation**: Reviewer must document review timestamp, changes made, and approval decision
- **Retention**: Review records retained for the life of the matter + 7 years
- **Penalty for Bypass**: Automatic system suspension + governance review

**Gate G-02 — Outreach Content Gate**
- **Applies to**: AI-010 (Email Generation), AI-011 (SMS Generation), AI-006 (Voice AI Scripts), AI-022 (Marketing Content)
- **Requirement**: Any AI-generated SMS, email, voice script, or marketing content MUST be reviewed by compliance before deployment to production
- **Documentation**: Reviewer must document compliance check, any modifications, and approval
- **Retention**: Content versions + review records retained minimum 3 years
- **Penalty for Bypass**: Content blocked + compliance investigation

**Gate G-03 — Scoring Threshold Gate**
- **Applies to**: AI-001 (Lead Scoring), AI-009 (Lead Value), AI-025 (Fraud Detection)
- **Requirement**: Any AI score that triggers an adverse action, denial, exclusion, or high-priority flag requires human review before action
- **Thresholds**: Defined per system and reviewed quarterly
- **Documentation**: Reviewer must document understanding of score factors and agreement with action
- **Retention**: Score records + review decisions retained 5 years

**Gate G-04 — Autonomous Action Gate**
- **Applies to**: AI-003, AI-004, AI-005, AI-012, AI-032, AI-031 (all Tier 1 infrastructure systems)
- **Requirement**: AI may act autonomously within defined guardrails. Any action that exceeds thresholds (e.g., restart limit exceeded, cost impact >$100, repeated failure) requires human confirmation
- **Guardrails**: Defined per system and version-controlled
- **Escalation**: Automatic escalation to on-call human when guardrail is exceeded
- **Retention**: All autonomous actions logged with decision factors

**Gate G-05 — Model Change Gate**
- **Applies to**: All Tier 3+ systems, any model change affecting Tier 2+ scoring
- **Requirement**: Any model update, fine-tuning, prompt change, or algorithm modification requires approval from AI Review Committee (Tier 2+) or AI Governance Board (Tier 3+)
- **Documentation**: Change rationale, A/B test results (if applicable), risk assessment
- **Retention**: Model version history, change approvals, performance comparisons

**Gate G-06 — New Use Case Gate**
- **Applies to**: Any new AI system or capability
- **Requirement**: Pre-deployment governance review and risk classification
- **Documentation**: AI Impact Assessment (Appendix E), risk tier assignment, implementation plan
- **Decision**: AI Governance Board approval required for Tier 3+

### 4.2 Escalation Rules

| Scenario | Tier | Escalation Path | Response Time |
|----------|------|-----------------|---------------|
| AI system exception or error affecting operations | Tier 1 | Automated escalation to on-call engineer | Real-time (immediate notification) |
| AI system exception or error affecting individuals | Tier 2 | Engineering lead + compliance | 2 hours |
| AI output fails quality check | Tier 3 | System owner + reviewer notified | 4 hours |
| AI output reaches error threshold | Tier 3 | System paused, engineering + compliance review | 1 hour |
| AI detects anomaly requiring human judgment | Tier 3-4 | Assigned human reviewer | 30 minutes |
| Potential PII breach via AI system | Tier 3+ | CISO + Legal + Compliance | Immediate (<15 minutes) |
| AI system exhibiting unexpected behavior | Any | On-call engineer, system owner | 1 hour |
| AI system making out-of-policy decisions | Any | AI Governance Board, Legal | 24 hours |
| Model performance degradation >20% | Tier 2+ | Engineering lead + model owner | 4 hours |
| Litigation hold triggered related to AI output | Any | Legal + Compliance + system freeze | 2 hours |

### 4.3 Human Reviewer Qualifications

| Review Gate | Minimum Qualifications | Training Requirements |
|-------------|----------------------|----------------------|
| Document Review (G-01) | Licensed attorney in relevant jurisdiction | AI governance training, annual refresher |
| Outreach Content (G-02) | Compliance officer or legal professional | AI ethics training, content review certification |
| Scoring Threshold (G-03) | Operations manager or compliance officer | AI system understanding, fairness training |
| Autonomous Action (G-04) | SRE or infrastructure engineer | System-specific training, incident response |
| Model Change (G-05) | Engineering lead + compliance (dual) | AI governance, model validation training |
| New Use Case (G-06) | AI Governance Board member | Full governance training |

### 4.4 Human Review Quality Assurance

- Random sampling of 5% of all human reviews for quality checking
- Quarterly inter-rater reliability analysis for Tier 3+ systems
- Annual reviewer competency assessment
- Reviewer fatigue management: maximum 20 reviews per day per reviewer for Tier 3+ systems
- Reviewer independence: reviewers must not have a personal stake in the outcome they are reviewing

---

## 5. AI MODEL GOVERNANCE

### 5.1 Model Inventory

| Model ID | Provider/Origin | Purpose | Training Data | Wheeler Data Exposure | Access Level | Risk Tier |
|----------|---------------|---------|-------------|----------------------|-------------|-----------|
| LLM-001 | Claude (Anthropic) via LiteLLM | Wheeler Brain OS agents — reasoning, orchestration, analysis, decision support | Anthropic proprietary — NOT trained on Wheeler data | Potentially via prompts; no training | Internal API | Low (Tier 1-3 by use case) |
| LLM-002 | Claude (Anthropic) via API | Document assembly, content generation, analysis | Anthropic proprietary — NOT trained on Wheeler data | Potentially via prompts; no training | Internal API | Medium (Tier 3-4 by use case) |
| LLM-003 | [Third-party LLM] — Outreach | Content generation for outreach sequences | Provider proprietary | Prompt data only; no training | Internal API | Medium (Tier 3) |
| ML-001 | SurplusAI Matching Algorithm | Claim-to-funds matching | Proprietary — court records, historical matches, property data | Court records, match outcomes | Internal | Medium (Tier 2-3) |
| ML-002 | Lead Scoring Model | Lead quality and conversion scoring | Historical lead data, conversion outcomes, behavioral signals | Lead data, conversion history | Internal | Medium (Tier 2) |
| ML-003 | Prediction Radar — Real Estate | Real estate valuation and timing | Public property records, market indices, economic data | None (public data only) | Internal | Low (Tier 2) |
| ML-004 | Fraud Detection Model | Pattern recognition for claim fraud | Historical claims, fraud patterns, verification outcomes | Claim data, fraud flags | Restricted | High (Tier 3) |
| ML-005 | Voice AI — NLP Model | Voice conversation understanding and generation | Provider proprietary + conversation data (future) | Conversation transcripts (future) | Internal | High (Tier 4) |
| ML-006 | Capacity Router — Attorney | Attorney capacity and routing optimization | Attorney schedules, case assignments, performance data | Attorney data, case routing | Internal | Medium (Tier 3) |

### 5.2 Training Data Governance

#### 5.2.1 Data Sources and Usage

| Data Category | Used for Training? | Data Sensitivity | Governance Controls |
|--------------|-------------------|-----------------|---------------------|
| Court records (public) | Yes — Matching, scoring, prediction | Public — low sensitivity | Source attribution, terms of service compliance |
| Property records (public) | Yes — Prediction, scoring | Public — low sensitivity | Source attribution |
| Historical claim outcomes | Yes — Scoring, matching | Internal — medium sensitivity | Access controls, anonymization, data retention limits |
| Lead data | Yes — Scoring models | Internal — medium sensitivity | Purpose limitation, consent check, anonymization |
| Claimant PII | **NEVER for training** ⚖️ | Highly sensitive | **Absolute prohibition** — see Section 5.2.3 |
| Attorney data | Yes — Routing, matching | Internal — medium sensitivity | Access controls, opt-out available |
| Conversation transcripts | Future — Voice AI improvement | Highly sensitive | **Not yet permitted** — requires DPA amendment and consent framework ⚖️ |
| System/operational logs | Yes — Anomaly detection, health | Internal — low sensitivity | Aggregated, no PII in logs |
| Financial data | Yes — Forecasting, optimization | Internal — high sensitivity | Aggregated, access controls, audit trail |
| Marketing/content engagement | Yes — Content optimization | Internal — low sensitivity | Aggregated, anonymized |

#### 5.2.2 Data Provenance Requirements

- All training data sources must be documented with: source, collection date, license/terms, update frequency, data dictionary
- Data lineage must be traceable from source to model
- Any data obtained from third parties must have contractual right to use for ML training
- Public records data must comply with source terms of service ⚖️ ATTORNEY REVIEW REQUIRED — some court records portals prohibit automated scraping or ML training

#### 5.2.3 PII and Sensitive Data — Absolute Prohibitions

**Claimant PII must NEVER be used for AI training.** This includes:
- Names, addresses, phone numbers, email addresses
- Social Security numbers, tax IDs, financial account numbers
- Health information, medical records
- Biometric data
- Protected class information
- Any information that could identify an individual

**Exception Process**: Any proposed use of PII for AI training requires:
1. ⚖️ ATTORNEY REVIEW of data protection laws (CCPA, state privacy laws, HIPAA if applicable)
2. Privacy Impact Assessment
3. Explicit consent mechanism for data subjects
4. AI Governance Board approval
5. Data Protection Agreement (DPA) amendment if using third-party processor

#### 5.2.4 Opt-Out Mechanism

- Individuals must be able to opt out of their data being used for AI training
- Opt-out does not affect service delivery — data used for operational purposes only
- Opt-out mechanism: Privacy Policy → Data Rights → "Do Not Use My Data for AI Training"
- Opt-out honored within 30 days
- Annual review of opt-out effectiveness

### 5.3 Prompt Governance

#### 5.3.1 Prompt Management Standards

All AI system prompts must adhere to the following standards:

1. **Version Control**: Every prompt must be version-controlled in a git repository with change history
2. **Approval Requirements**:
   - Tier 1-2 prompts: Engineering lead approval sufficient
   - Tier 3+ prompts: AI Review Committee approval required
   - Emergency prompt changes (security fix): Post-hoc approval within 48 hours
3. **Required Prompt Components**:
   - **Role**: Clear definition of AI's role and boundaries
   - **Context**: Relevant background and constraints
   - **Task**: Specific instruction of what to do
   - **Input**: Defined input format and data sources
   - **Output**: Defined output format and structure
   - **Constraints**: Explicit boundaries (what NOT to do)
   - **Prohibited Content**: Explicit list of prohibited outputs
   - **Escalation**: When to defer to human
4. **Prompt Injection Testing**: All Tier 3+ prompts must pass injection/jailbreak testing before deployment
5. **Audit Trail**: All prompt changes logged with: author, date, change description, approver, A/B test results (if applicable)

#### 5.3.2 Prompt Change Classification

| Change Type | Example | Approval Required | Documentation |
|-------------|---------|-------------------|--------------|
| Minor (no behavior change) | Formatting, typo fix | Self-approve | Git log |
| Moderate (behavior change) | Tone adjustment, additional constraint | Engineering lead | Brief change description |
| Major (capability change) | New feature, removed guardrail | AI Review Committee | Full change request + impact assessment |
| Emergency (security fix) | Injection vulnerability fix | Post-hoc approval | Incident report + fix description |

### 5.4 Model Validation & Testing

#### 5.4.1 Testing Requirements by Tier

| Test Type | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|-----------|--------|--------|--------|--------|
| Unit testing | Required | Required | Required | Required |
| Integration testing | Required | Required | Required | Required |
| Accuracy testing | Sampling | Required | Required | Required |
| Bias testing | — | Annual | Quarterly | Pre-deployment + quarterly |
| Adversarial testing | — | — | Required | Required |
| Performance regression | Required | Required | Required | Required |
| A/B testing framework | — | Recommended | Required | Required |
| Rollback testing | Required | Required | Required | Required |
| Explainability audit | — | — | Required | Required |
| Stress/load testing | Required | Required | Required | Required |

#### 5.4.2 Model Validation Process

1. **Pre-Training Validation**: Data quality check, bias assessment, data provenance verification
2. **Training Validation**: Holdout set evaluation, cross-validation, overfitting check
3. **Pre-Deployment Validation**: Production-like testing, A/B test (Tier 3+), security testing
4. **Post-Deployment Monitoring**: Continuous performance tracking, drift detection, alerting
5. **Periodic Revalidation**: Quarterly for Tier 3+, bi-annual for Tier 2, annual for Tier 1

#### 5.4.3 Acceptance Criteria

| Metric | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|--------|--------|--------|--------|--------|
| Accuracy (primary metric) | >80% | >85% | >90% | >95% |
| False positive rate | <10% | <5% | <2% | <1% |
| False negative rate | <10% | <5% | <2% | <1% |
| Bias (disparate impact ratio) | N/A | >0.80 | >0.85 | >0.90 |
| Explainability score | N/A | N/A | >70% | >85% |
| Injection resistance | N/A | N/A | >95% | >99% |

#### 5.4.4 Rollback Procedure

- Every AI model must have a documented rollback procedure tested before deployment
- Rollback trigger: performance degradation >20%, bias detection alert, security incident, regulatory directive
- Rollback target: previous model version or known-good fallback
- Rollback time target: <15 minutes for Tier 3+, <1 hour for Tier 2
- Post-rollback: root cause analysis within 5 business days, remediation within 10 business days

---

## 6. AI TRANSPARENCY & DISCLOSURE

### 6.1 Internal Transparency

#### 6.1.1 AI Usage Logging

Every AI system interaction that affects individuals, produces outputs, or makes decisions must be logged with:

- **Timestamp**: Exact time of interaction (UTC)
- **System ID**: Which AI system (from Use Case Registry)
- **Input Summary**: What was provided to the AI (no raw PII in logs)
- **Output Summary**: What the AI produced
- **Human Reviewer**: Name and review decision (if applicable)
- **Action Taken**: What happened as a result (e.g., filed, sent, discarded, escalated)
- **Decision Factors**: Key factors that influenced the AI output (explainability record)

**Log Retention**:
- Tier 1-2: 90 days
- Tier 3: 3 years
- Tier 4: 7 years
- Any logs related to litigation hold: Until hold is released

#### 6.1.2 AI Decision Register

- Maintain a searchable, auditable register of significant AI decisions
- Updated in real-time for Tier 3+ systems
- Accessible to: AI Governance Board, Legal, Compliance, system owners
- Searchable by: system, date, decision type, affected individual, reviewer

#### 6.1.3 Monthly AI Usage Report

The AI Review Committee produces a monthly report including:
- All AI systems: status, usage volume, performance metrics
- Tier 3+ systems: detailed output statistics, human review rates, override rates
- Incidents: count, severity, resolution status
- Model changes: list of all approved changes
- Bias monitoring: results of any bias tests conducted
- Audit findings: summary of AI compliance audits
- Recommendations: proposed policy changes or new use cases

### 6.2 External Disclosure

#### 6.2.1 To Claimants

"Wheeler uses technology, including artificial intelligence, to help identify surplus funds and match you with attorneys. These tools assist our team in processing information more efficiently. All legal decisions — including case evaluation, document preparation, and representation — are made by licensed attorneys, not by AI. You have the right to request human review of any AI-assisted decision about your case."

**Disclosure Placement**:
- Website privacy policy
- Claimant intake forms
- First communication (voice or written)
- Annual notification

#### 6.2.2 To Attorneys

"Wheeler uses AI-assisted tools to support case matching, document assembly, and operational efficiency. These tools are designed to augment, not replace, your professional judgment. You retain complete professional responsibility for all legal work performed on behalf of your clients. AI-generated drafts and recommendations must be independently verified before use. Wheeler's AI systems do not make legal decisions, provide legal advice, or determine case strategy."

**Disclosure Placement**:
- Attorney onboarding materials
- Terms of service
- Platform notifications when AI-generated content is used

#### 6.2.3 To Regulators

Full disclosure upon request including:
- Complete AI Use Case Registry
- Risk tier classifications and rationale
- Human review documentation for Tier 3+ systems
- Bias testing results
- Incident reports and remediation
- Model governance documentation

#### 6.2.4 In Privacy Policy (CCPA/CPRA Compliance)

The Privacy Policy must disclose: ⚖️ ATTORNEY REVIEW REQUIRED
- Categories of AI systems used
- Types of data processed by AI
- Purpose of AI processing
- Automated decision-making disclosures (CCPA §1798.185(a)(16))
- Right to opt out of automated decision-making
- Right to access information about AI decisions
- Contact information for AI-related inquiries

### 6.3 Prohibited Deceptions

The following are strictly prohibited:
1. **No AI impersonating a human**: Any AI interaction must be clearly identified as AI-generated or AI-assisted
2. **No AI pretending to be an attorney**: AI must never represent itself as a licensed attorney
3. **No AI-generated documents without attorney review marking**: All AI-drafted documents must carry a disclosure of AI assistance and attorney review status
4. **No AI-generated testimonials or fake reviews**: Violates FTC guidelines ⚖️ ATTORNEY REVIEW REQUIRED
5. **No dark patterns**: AI must not use manipulative interface design to obtain consent or drive decisions

### 6.4 AI-Generated Content Labeling

| Content Type | Label Required | Label Text | Placement |
|-------------|---------------|------------|-----------|
| AI-drafted legal document | Yes | "AI-Assisted Draft — Reviewed by [Attorney Name] on [Date]" | Header or footer of document |
| AI-generated email/SMS | Yes | "This message was drafted with AI assistance and reviewed by our team." | Within message body |
| AI voice call | Yes | "This call is from Wheeler's AI assistant. [If applicable:] You are being recorded." | Beginning of call |
| AI-marketing content | Yes | "AI-Assisted Content" | Near content |
| AI-generated summary | No (internal only) | Not required | N/A |
| AI-recommended match | Yes | "AI-Assisted Match — Confirmed by [Human Name]" | Match notification |

---

## 7. BIAS, FAIRNESS & ETHICS

### 7.1 Protected Characteristics

AI must not discriminate based on any characteristic protected under applicable law:

**Federal Protected Classes** (per Civil Rights Act, ADEA, ADA, GINA):
- Race, color, national origin
- Religion
- Sex (including pregnancy, sexual orientation, gender identity)
- Age (40 and over)
- Disability (physical or mental)
- Genetic information (including family medical history)
- Citizenship status
- Military/veteran status

**State-Level Protections** (varies by jurisdiction — ⚖️ ATTORNEY REVIEW REQUIRED for each state Wheeler operates in):
- Marital status
- Sexual orientation and gender identity (explicit in some states)
- Arrest or conviction record (some states)
- Political affiliation (some states)
- Domestic violence victim status (some states)
- Reproductive health decisions (some states)

**Additional Wheeler Policy Protections**:
- Socioeconomic status
- Education level (unless directly relevant to legal capacity)
- Geography (unless directly relevant to jurisdiction)
- Language preference (reasonable accommodations required)

### 7.2 Bias Testing Framework

#### 7.2.1 Testing Requirements

| Test Type | Description | Frequency | Tier 2 | Tier 3 | Tier 4 |
|-----------|-------------|-----------|--------|--------|--------|
| Disparate Impact Analysis | Statistical analysis of outcomes across protected groups | Tier 3+: Quarterly; Tier 2: Annually | Annual | Quarterly | Quarterly |
| Proxy Analysis | Detection of proxies for protected characteristics | Pre-deployment + annually | Annually | Pre-deployment + quarterly | Pre-deployment + quarterly |
| Intersectional Analysis | Analysis of outcomes at intersection of multiple protected characteristics | Pre-deployment + annually | — | Pre-deployment + annually | Pre-deployment + quarterly |
| Calibration Testing | Does model calibration differ across groups? | Pre-deployment + annually | Annually | Quarterly | Quarterly |
| Labeling Audit | Are training labels biased? | Annually | Annually | Quarterly | Pre-deployment |
| Feedback Loop Test | Does model create self-fulfilling bias? | Annually | — | Annually | Pre-deployment |

#### 7.2.2 Bias Metrics and Thresholds

| Metric | Definition | Acceptable Threshold | Action if Exceeded |
|--------|-----------|---------------------|-------------------|
| Disparate Impact Ratio (DIR) | Ratio of favorable outcomes for protected vs. reference group | ≥ 0.80 / ≤ 1.25 | Model paused, root cause analysis, remediation required before resuming |
| Standardized Mean Difference | Effect size of group difference in scores | < 0.25 SD | Investigation required |
| Equal Opportunity Difference | Difference in true positive rates across groups | < 0.05 | Model tuning required |
| Predictive Parity | Equal positive predictive values across groups | Within 5% | Investigation required |

#### 7.2.3 Bias Remediation Steps

When bias is detected above acceptable thresholds:
1. **Immediate**: Tier 3+ model paused within 4 hours
2. **Analysis**: Root cause identified within 5 business days
3. **Remediation**: Corrective action (retraining, threshold adjustment, post-processing) within 15 business days
4. **Validation**: Re-testing confirms bias is within thresholds
5. **Monitoring**: Enhanced monitoring for 90 days post-remediation
6. **Documentation**: Full report to AI Governance Board

### 7.3 Fairness in Practice

#### 7.3.1 Lead Scoring (AI-001, AI-009)
- **Risk**: Lead scores may systematically disadvantage certain demographic groups if training data reflects historical biases in court filings or property ownership patterns
- **Controls**:
  - Proxy analysis for race, gender, age even if not directly collected
  - Annual disparate impact analysis
  - Score distribution monitoring by geographic area (as proxy for demographic analysis)
  - ⚖️ ATTORNEY REVIEW: Whether score-based prioritization could create fair lending or fair housing concerns if leads involve housing-related claims

#### 7.3.2 Attorney Matching (AI-007, AI-021)
- **Risk**: Matching algorithm may favor or disfavor attorneys based on protected characteristics
- **Controls**:
  - Attorney demographic monitoring (voluntary self-identification)
  - Exposure analysis: Are all attorneys getting fair case type distribution?
  - Blind features: Remove protected characteristics and strong proxies from matching algorithm
  - Annual bias audit with intersectional analysis
  - Attorney right to request explanation of match decisions

#### 7.3.3 Document Assembly (AI-002)
- **Risk**: Generated documents may contain language that treats claimants differently based on demographics
- **Controls**:
  - Mandatory attorney review of all generated documents
  - Random sampling for language bias testing
  - Template bias review during creation
  - Output monitoring for differential language patterns

#### 7.3.4 Claimant Identification (AI-020)
- **Risk**: Identification algorithm may systematically miss or include certain demographic groups
- **Controls**:
  - Coverage analysis: Are all geographic and demographic areas being identified proportionally?
  - Regular algorithm audit for disparate impact
  - ⚖️ ATTORNEY REVIEW: Whether failure to identify certain groups creates consumer protection liability

#### 7.3.5 Voice AI (AI-006 — Planned)
- **Risk**: Voice AI may handle different dialects, accents, or speech patterns differently
- **Controls**:
  - Accent and dialect testing before deployment
  - Language and dialect coverage requirements
  - Real-time quality monitoring during calls
  - Escalation protocol for communication difficulties
  - Regular bias audit of call outcomes

### 7.4 Ethical Considerations Specific to Wheeler

#### 7.4.1 Vulnerable Population Protections

Surplus funds claimants are often vulnerable populations who require enhanced protections:

| Vulnerability Factor | Population | Enhanced Protection |
|---------------------|------------|-------------------|
| Age (elderly) | Claimants >65 | Enhanced human review, simplified language, fraud prevention checks |
| Cognitive impairment | Claimants with diminished capacity | Mandatory guardian/family member involvement |
| Recent foreclosure | Financially distressed claimants | Cooling-off period, financial counseling resources |
| Deceased estates | Bereaved families | Sensitivity protocols, extended response times, family liaison |
| Limited English proficiency | LEP claimants | Translation services, language-concordant communications |
| Low income | Financially vulnerable | Fee transparency, consumer protection disclosures |
| Incarcerated individuals | Current/former inmates | Justice-involved protocols, reentry support resources |

#### 7.4.2 Ethical Use Standards

- **No exploitation of information asymmetry**: AI must not use data advantages to pressure or mislead claimants
- **No undue influence**: AI must not create false urgency, false scarcity, or exaggerated benefits
- **No manipulation of vulnerable individuals**: Communications must be clear, honest, and respectful
- **Right to understanding**: Claimants must be able to understand AI-involved processes in plain language
- **Right to human interaction**: Claimants may request to speak with a human at any time
- **Beneficence**: AI systems should be designed to benefit claimants, not just Wheeler
- **Non-maleficence**: AI must not cause harm, even indirectly

#### 7.4.3 Ethics Review Board

- Standing Ethics Advisory Panel of external members (legal ethicist, community advocate, AI ethics researcher)
- Quarterly review of AI ethics compliance
- Ad hoc review of novel ethical questions
- Whistleblower channel for ethics concerns (anonymous option)

---

## 8. AI SECURITY

### 8.1 Threat Model

#### 8.1.1 Threat Landscape

| Threat | Target Systems | Likelihood | Impact | Risk Level |
|--------|---------------|------------|--------|------------|
| **Prompt Injection / Jailbreak** | LLM-based systems (Brain OS, Document Assembly, Outreach) | High | High — unauthorized outputs, data exposure | **Critical** |
| **Data Extraction via Inversion** | ML models trained on proprietary data | Medium | High — training data reconstruction | **High** |
| **Model Poisoning** | Retrained/fine-tuned models | Low | High — corrupted model outputs | **High** |
| **Adversarial Inputs** | Scoring/matching models | Medium | Medium — incorrect scores or matches | **Medium** |
| **Model Theft / IP** | Proprietary models and prompts | Medium | High — loss of competitive advantage | **High** |
| **API Abuse** | All AI service endpoints | High | Medium — cost, availability, data exposure | **Medium** |
| **Supply Chain** | Third-party models, libraries, providers | Medium | High — compromised dependency | **High** |
| **Insider Threat** | Internal AI systems | Low | High — data exfiltration, model sabotage | **High** |
| **Denial of Service** | AI API endpoints | Medium | Medium — availability impact | **Medium** |
| **Data Poisoning — Feedback** | Models using real-time feedback | Medium | Medium — model drift toward adversary goals | **Medium** |

#### 8.1.2 Threat Mitigation Matrix

| Threat | Primary Mitigations | Secondary Mitigations |
|--------|-------------------|---------------------|
| Prompt Injection | Input sanitization, output validation, role constraints, prompt boundaries | Human review for Tier 3+, injection testing before deployment |
| Data Extraction | Differential privacy, output restrictions, access controls | No PII in training data, response size limits |
| Model Poisoning | Training data validation, integrity checks, versioning | Rollback capability, anomaly detection during training |
| Adversarial Inputs | Input validation, rate limiting, anomaly detection | Ensemble methods, confidence thresholds |
| Model Theft | Access controls, API authentication, rate limiting | Model watermarking, usage monitoring |
| API Abuse | Authentication, rate limiting, quota management | Cost alerts, usage anomaly detection |
| Supply Chain | Vendor assessment, dependency scanning, integrity verification | SBOM maintenance, monitored deployment |
| Insider Threat | Access controls, audit logging, least privilege | Separation of duties, activity monitoring |
| DoS | Rate limiting, auto-scaling, DDoS protection | Cost controls, circuit breakers |

### 8.2 Security Controls

#### 8.2.1 Input Sanitization

- All inputs to LLM systems must be sanitized for prompt injection patterns
- Sanitization rules must be version-controlled and tested
- Sanitization bypass attempts must be logged and alerted
- Tier 3+ systems: Additional input validation layer

#### 8.2.2 Output Validation

- All outputs from Tier 3+ systems must be validated before delivery
- Validation includes: pattern matching for prohibited content, data format verification, consistency checks
- Outputs containing legal conclusions or financial figures require additional verification
- Output anomaly detection: unexpected output patterns trigger escalation

#### 8.2.3 API Security

| Control | All AI APIs | Tier 3+ Endpoints | Tier 4 Endpoints |
|---------|-------------|-------------------|-----------------|
| Authentication | Required (API key or OAuth) | Required | Required |
| Authorization | Scope-based | Scope + system-level | Scope + system + individual |
| Rate limiting | Per-key, per-endpoint | Stricter limits | Strictest limits |
| Request logging | All requests | All requests + payload sampling | Full payload logging |
| Encryption in transit | TLS 1.3 | TLS 1.3 | TLS 1.3 |
| Encryption at rest | — | Required | Required |
| IP allowlisting | Recommended | Required | Required |

#### 8.2.4 Access Controls

| Role | Can Query AI Systems | Can View Training Data | Can Modify Models | Can Modify Prompts | Can Deploy Changes |
|------|---------------------|----------------------|------------------|-------------------|-------------------|
| AI System User (standard) | Assigned systems only | No | No | No | No |
| AI Reviewer | Assigned systems + view outputs | No | No | No | No |
| AI Developer | Relevant systems | Masked only | Development only | Dev only | No |
| Engineering Lead | All systems | Masked only | Approval required | Approval required | Approval required |
| CTO / VP Engineering | All systems | Approval required | Approval required | Approval required | Approval required |
| Compliance / Legal | All systems (read) | Approval required | No | No | No |
| Auditor | Read-only logs | Read-only (audit trail) | No | No | No |

#### 8.2.5 Audit Logging Requirements

- All AI API calls logged with: timestamp, caller identity, endpoint, input hash, output hash, duration, status
- Logs are immutable (append-only) — no modification or deletion permitted
- Logs retained per retention schedule (Section 6.1.1)
- Log integrity verification: daily hash chain validation
- Centralized logging with SIEM integration
- Anomaly detection on log patterns

### 8.3 Incident Response — AI Specific

#### 8.3.1 AI Incident Classification

| Severity | Definition | Examples | Response Time |
|----------|-----------|----------|---------------|
| **P0 — Critical** | Active harm or regulatory violation | PII exposure via AI, AI giving legal advice, autonomous prohibited action | Immediate (<15 min) |
| **P1 — High** | Significant system failure or policy violation | Model producing biased outputs at scale, successful prompt injection producing harmful output | 1 hour |
| **P2 — Medium** | Degradation or minor policy violation | Model accuracy drop, unexpected behavior, minor prompt injection | 4 hours |
| **P3 — Low** | Minor issue or potential concern | Performance degradation <20%, anomalous but not harmful output | 24 hours |
| **P4 — Informational** | Observation with no immediate action needed | Suspicious pattern, potential future risk | Next business cycle |

#### 8.3.2 AI Incident Response Protocol (See also Appendix A)

1. **Detection**: Automated monitoring or human report
2. **Triage**: Severity classification within 15 minutes for P0, 1 hour for others
3. **Containment**: Affected system(s) isolated/paused — target <30 minutes for P0
4. **Investigation**: Root cause analysis — P0 within 8 hours, P1 within 24 hours
5. **Remediation**: Fix implemented — P0 within 24 hours, P1 within 5 days
6. **Post-Mortem**: Written report within 5 business days (P0/P1) or 10 business days (P2)
7. **Disclosure**: Legal determines external disclosure requirements

#### 8.3.3 AI-Specific Containment Procedures

- **Prompt injection detected**: Isolate affected model instance, rotate API keys if needed
- **PII exposure**: Isolate system, preserve evidence, notify CISO/Legal immediately
- **Model corruption**: Rollback to last known-good version
- **Policy violation by AI**: Quarantine all outputs since last known-good state
- **External disclosure event**: Legal leads on regulatory and claimant notifications

### 8.4 Vulnerability Disclosure

- **Internal**: AI vulnerability reporting via security incident process (see above)
- **External**: Responsible disclosure policy published on Wheeler website for security researchers
- **Bug Bounty**: Consideration for Tier 3+ AI systems based on risk assessment
- **Scope**: Vulnerabilities in AI systems, prompt injections, data exposure, model manipulation
- **Out of Scope**: Social engineering of Wheeler employees, physical attacks, denial of service

---

## 9. AI GOVERNANCE OPERATING MODEL

### 9.1 Governance Bodies

#### 9.1.1 AI Governance Board

**Charter**: Highest AI governance authority in Wheeler Ecosystem

**Composition**:
- CEO (Chair)
- CTO
- General Counsel / Head of Legal
- Chief Compliance Officer
- Chief Information Security Officer
- Chief Privacy Officer (or equivalent)
- At least one external independent member (AI ethicist or legal tech governance expert)

**Meeting Cadence**: Quarterly (minimum) + ad hoc for emergencies

**Responsibilities**:
- Approve AI Governance Policy and amendments
- Approve new Tier 3+ AI use cases
- Review and act on AI incidents (P0-P1)
- Approve policy exceptions with defined sunset dates
- Review AI governance maturity and recommend improvements
- Annual AI governance effectiveness assessment
- Escalation point for unresolved AI ethics concerns

**Decision-Making**: Consensus-based. If consensus cannot be reached, CEO makes final decision with written rationale.

#### 9.1.2 AI Review Committee

**Charter**: Operational AI governance body

**Composition**:
- Engineering Lead (Chair)
- Legal/Compliance representative
- Privacy Officer
- AI System Owner (rotating)
- Data Protection Officer

**Meeting Cadence**: Monthly + async review queue

**Responsibilities**:
- Risk classification of new AI systems
- Review and approve Tier 2+ model and prompt changes
- Review monthly AI usage report
- Conduct bias test reviews
- Review AI audit findings and recommend improvements
- Prepare quarterly report for AI Governance Board
- Approve Tier 1-2 new use cases (notify Board)

#### 9.1.3 AI Ethics Advisor

**Role**: External independent advisor

**Qualifications**: AI ethics expertise, legal ethics understanding (preferably with experience in legal services AI)

**Appointment**: 2-year renewable term

**Responsibilities**:
- Available for consultation on novel AI use cases
- Independent opinion on ethics questions
- Identify blind spots in governance framework
- Advise on emerging AI ethics standards and regulations
- Participate in quarterly AI Governance Board meetings

### 9.2 Decision Rights Matrix

| Decision | AI Governance Board | CTO | Legal/Compliance | Engineering Lead | AI Review Committee |
|----------|-------------------|-----|-----------------|-----------------|---------------------|
| New AI use case (Tier 1-2) | Notify | Approve | Review/Approve | Implement | Approve classification |
| New AI use case (Tier 3) | Approve | Recommend | Approve | Implement | Recommend classification |
| New AI use case (Tier 4) | Approve | Recommend | Approve | Implement | Recommend classification |
| New AI use case (Prohibited/Tier 5) | Hard block | — | — | — | — |
| Model update (Tier 1-2) | Notify | Approve | Notify (if data change) | Implement | Review |
| Model update (Tier 3+) | Notify | Recommend | Approve | Implement | Approve |
| Prompt change (Tier 1-2) | — | Notify | — | Implement | Notify |
| Prompt change (Tier 3+) | — | Notify | Approve | Implement | Review |
| Prompt change (emergency) | Notify | Approve | Notify | Implement | Post-hoc review |
| AI Incident (P0-P1) | Notify | Lead response | Co-lead response | Support | Support |
| AI Incident (P2) | Notify | Notify | Notify | Lead | Review |
| Policy exception | Approve | Recommend | Recommend | — | Review |
| Annual governance assessment | Lead | Participate | Participate | Participate | Participate |

### 9.3 Policy Version Control

| Version | Date | Author | Summary of Changes | Approval |
|---------|------|--------|-------------------|----------|
| 1.0.0 | 2026-05-25 | AI Governance Board | Initial Policy | AI Governance Board |

**Review Cycle**:
- Full review: Quarterly (by AI Governance Board)
- Interim updates: As needed (new regulations, incident lessons, new AI capabilities)
- Emergency amendments: CEO can approve urgent amendments with Board ratification within 30 days

**Policy Exception Process**:
1. Written exception request submitted to AI Governance Board
2. Board reviews at next scheduled meeting (or emergency meeting if urgent)
3. Exception must include: rationale, duration (with sunset date), compensating controls, risk assessment
4. Board may approve with conditions, reject, or modify
5. Exceptions expire automatically on sunset date unless renewed
6. Exception register maintained and reported quarterly

### 9.4 AI Governance Maturity Model

Wheeler AI governance will mature through defined stages:

| Stage | Characteristics | Target |
|-------|----------------|--------|
| **Stage 1: Foundation** (Current) | Policy established, basic controls, manual review processes | Achieved with Version 1.0 |
| **Stage 2: Operationalized** (6 months) | Automated compliance monitoring, integrated review gates, training completed | Target: Nov 2026 |
| **Stage 3: Proactive** (12 months) | Predictive risk monitoring, automated bias testing, continuous validation | Target: May 2027 |
| **Stage 4: Optimized** (18-24 months) | Self-healing governance, real-time compliance, industry leadership | Target: 2028 |

### 9.5 Training and Awareness

| Role | Required Training | Frequency |
|------|------------------|-----------|
| All employees | AI Governance Awareness — what AI does, how it's governed, reporting concerns | Annual |
| AI system users | System-specific training + AI ethics | Onboarding + annual |
| AI system developers | AI governance policy, prompt engineering security, bias awareness | Onboarding + annual |
| Human reviewers | Review protocols, bias recognition, escalation procedures | Onboarding + quarterly refresher |
| Engineering leadership | Full AI governance policy, decision rights, incident response | Onboarding + annual |
| Governance board members | AI governance best practices, regulatory landscape, fiduciary duties | Initial + semi-annual |

---

## 10. COMPLIANCE MAPPING

### 10.1 Regulatory Framework for AI

| Regulation | Applicability to Wheeler AI | Key Requirements | Current Status | Required Actions |
|-----------|---------------------------|-----------------|---------------|------------------|
| **EU AI Act** | If processing EU data or deploying in EU market | Risk classification (prohibited/high/limited/minimal), conformity assessment, transparency obligations, human oversight, accuracy/robustness requirements | Monitor — Not currently operating in EU | ⚖️ ATTORNEY REVIEW: Assess if any claimant data involves EU persons. If Wheeler expands to EU, require full conformity assessment before launch. |
| **Colorado AI Act (CAIA)** | If Wheeler operates in CO with high-risk AI systems affecting Colorado residents | Risk management framework, bias testing and reporting, consumer disclosure, right to appeal, annual impact assessments | Monitor — Assess CO operations | ⚖️ ATTORNEY REVIEW: Determine if Wheeler has sufficient CO nexus. If so, Tier 3+ systems require CO-specific impact assessments. |
| **NYC Local Law 144** | If Wheeler hires employees in NYC using AI for hiring decisions | Required bias audit of automated employment decision tools | Likely N/A | Confirm no AI is used in NYC hiring decisions. |
| **CCPA/CPRA** | AI that processes California resident personal information or performs automated decision-making | Right to opt out of automated decision-making, right to access information about AI decisions, disclosure of AI data processing in privacy policy | ⚖️ ATTORNEY REVIEW | Update privacy policy with AI-specific disclosures. Implement opt-out mechanism for automated decision-making. |
| **FTC Act Section 5** | AI that could be unfair or deceptive | Prohibition on deceptive AI practices (Section 5(a)), prohibition on unfair practices, AI transparency guidance | ⚖️ ATTORNEY REVIEW | Audit all AI claims and representations. Ensure no deceptive AI practices. Review FTC AI guidance for compliance. |
| **White House AI Executive Order** | If Wheeler is a federal contractor or operates critical infrastructure | Safety testing requirements, transparency reporting, watermarking of AI-generated content | Monitor | Assess whether Wheeler constitutes critical infrastructure. Prepare transparency reporting capability. |
| **State UPL Rules (all 50 states)** | AI providing any legal service or appearing to provide legal advice | AI is not licensed to practice law. AI-generated legal work requires attorney supervision. No AI can represent itself as an attorney. | ⚖️ ATTORNEY REVIEW — CRITICAL | Full state-by-state UPL analysis required. Enforcement varies significantly. Prohibited AI actions (Section 3) provide baseline but state-specific nuances may require additional controls. |
| **ABA Formal Opinion 512** | AI use by Wheeler's attorney network | Lawyers must: (1) maintain competence in technology, (2) protect client confidentiality, (3) supervise AI use, (4) ensure ethical billing for AI-assisted work | ⚖️ ATTORNEY REVIEW | Ensure Wheeler's attorney network receives AI competency guidance. Provide confidentiality safeguards for attorney-AI interactions. |
| **HIPAA** | If Wheeler handles protected health information (PHI) | HIPAA applies if Wheeler is a covered entity or business associate. If applicable: BAAs, security rule, privacy rule, breach notification. | ⚖️ ATTORNEY REVIEW | Assess whether any AI system processes PHI. Surplus funds claims rarely involve PHI unless medical records are part of case. |
| **GLBA / Reg P** | If Wheeler engages in financial activities | Privacy notices, opt-out rights for nonpublic personal information | Likely N/A | Confirm no financial institution nexus. |
| **ADA / Section 508** | AI systems accessible to individuals with disabilities | Accessibility requirements for digital services, effective communication, reasonable accommodations | ⚖️ ATTORNEY REVIEW | Assess website and claimant portal AI features for ADA compliance. Voice AI must accommodate speech disabilities. |
| **CAN-SPAM Act** | AI-generated email outreach for claimants | Commercial email requirements: accurate header, clear subject, opt-out mechanism, valid physical address | ⚖️ ATTORNEY REVIEW on outreach | Ensure all AI-generated email includes required disclosures and unsubscribe mechanism. |
| **TCPA / Telephone Consumer Protection Act** | Voice AI calls to claimants | Prior express written consent for autodialed calls, do-not-call compliance, identification requirements | ⚖️ ATTORNEY REVIEW — CRITICAL | Critical compliance requirement for AI-006 Voice AI. Must have consent framework before deployment. |
| **State Data Privacy Laws** (VA, CO, CT, UT, others) | If Wheeler processes personal data of residents | Varying requirements: data access, deletion, portability, opt-out of profiling and automated decisions | Monitor | ⚖️ ATTORNEY REVIEW for each state Wheeler operates in. |
| **PCI DSS** | If AI systems process payment card data | If regulated, must restrict data collection, processing, and storage | Likely N/A | Confirm no AI system processes payment card data. |

### 10.2 Compliance Gap Assessment

| Area | Current State | Target State | Gap | Priority | Remediation Plan |
|------|--------------|-------------|-----|----------|-----------------|
| AI Use Case Inventory | Documented in policy | Complete, version-controlled registry with regular audits | Partial — needs full completion and integration with change management | High | Complete within 30 days |
| Risk Classification | Manual classification | Formal classification with documented rationale | Needs formalization and independence | High | Implement classification template and independent review |
| Bias Testing | No systematic bias testing | Quarterly for Tier 3+, annual for Tier 2 | **Critical gap** | **Critical** | ⚖️ ATTORNEY REVIEW: Need bias testing framework, tooling, and baseline measurements within 90 days |
| Human Review Gates | Informal processes | Defined gates with documentation and logging | Needs implementation and integration | High | Deploy review gate tooling within 60 days |
| Prompt Version Control | Git-based for some systems | All prompts version-controlled with approval workflow | Needs standardization | Medium | Migrate all prompts to standard workflow within 60 days |
| Training Completion | Ad hoc | Mandatory governance training for all relevant roles | **Significant gap** | High | Develop and deploy training within 90 days |
| External Disclosure | Privacy policy | Comprehensive AI disclosures for all constituencies | Needs development | Medium | Draft and publish disclosures within 60 days |
| Model Validation | System-specific | Standardized validation framework | Needs development | Medium | Develop validation framework within 90 days |
| Security Testing | Basic | Comprehensive AI-specific security testing | Needs enhancement | High | Implement prompt injection testing and adversarial testing within 60 days |
| Incident Response | General IR | AI-specific IR playbook and trained responders | Needs development | High | Develop AI IR playbook within 45 days |

### 10.3 Regulatory Monitoring

- **Dedicated resource**: Legal or compliance team member responsible for AI regulatory monitoring
- **Monitoring scope**: Federal and state AI legislation, regulatory guidance, enforcement actions, industry standards
- **Update cadence**: Monthly regulatory brief to AI Review Committee
- **Emergency notification**: Any regulation with immediate impact on Wheeler AI operations escalated within 48 hours
- **External counsel**: Retain AI regulatory counsel for complex or novel regulatory questions ⚖️

---

## APPENDICES

### Appendix A: AI Incident Response Protocol

#### A.1 Overview

This protocol applies to any incident involving an AI system in the Wheeler Ecosystem. It supplements the general incident response process with AI-specific procedures.

#### A.2 Incident Detection

Sources:
- Automated monitoring alerts
- Human review flags
- System performance degradation
- User/claimant/attorney complaints
- Compliance audit findings
- Regulatory inquiry

#### A.3 Incident Triage (First 15 Minutes)

1. **Confirm incident**: Verify the AI system involved, the behavior observed, and whether it is ongoing
2. **Assess severity**: Classify as P0-P4 (see Section 8.3.1)
3. **Initial containment**: Isolate affected system(s)
4. **Notification**: Alert on-call responders per severity
5. **Documentation**: Begin incident log

#### A.4 Containment Actions by Incident Type

| Incident Type | Immediate Containment | Evidence Preservation | Escalation |
|---------------|----------------------|---------------------|------------|
| PII exposure | Isolate system, block data access | Preserve all logs, outputs, system state | CISO + Legal + CEO |
| Prohibited action | System shutdown | Preserve model state, inputs, outputs | CTO + Legal + CEO |
| Prompt injection | Isolate model instance, rotate API keys | Capture injection payload, preserve logs | CTO + Security |
| Model corruption | Rollback to last-known-good version | Preserve corrupted model version | Engineering Lead + CTO |
| Bias/discrimination | Pause affected system | Preserve recent outputs and decisions | Legal + Compliance + CEO |
| Regulatory violation | Pause affected system, preserve evidence | Full system state | Legal + CEO |
| Accuracy failure | Assess scope, reduce confidence threshold if applicable | Preserve inputs and outputs | Engineering Lead |

#### A.5 Investigation Checklist

- [ ] What AI system(s) involved?
- [ ] What was the trigger/cause?
- [ ] When did it start? When was it detected?
- [ ] What data was involved?
- [ ] What outputs were produced?
- [ ] Who/what was affected (individuals, systems)?
- [ ] Was a prohibited action taken? Which one?
- [ ] What was the failure in controls?
- [ ] What similar systems might be at risk?
- [ ] What evidence has been preserved?

#### A.6 Post-Incident Activities

- **Root Cause Analysis**: Written report within 5 business days (P0/P1) or 10 business days (P2)
- **Control Enhancement**: Implement additional controls within 15 business days
- **Policy Review**: Determine if policy changes needed
- **Training Update**: Incorporate lessons into training
- **Board Report**: P0/P1 incidents reported to AI Governance Board at next meeting
- **Regulatory Disclosure**: Legal determines within 48 hours if external disclosure required

#### A.7 Incident Classification Register

| Date | ID | System | Severity | Summary | Root Cause | Resolution | Status |
|------|----|--------|----------|---------|------------|------------|--------|

---

### Appendix B: AI System Decommissioning Procedure

#### B.1 Triggers for Decommissioning

- System is replaced by a newer system
- System is no longer needed
- System fails to meet governance requirements after remediation attempts
- Regulatory requirement makes system non-compliant
- Security vulnerability cannot be remediated
- Governance Board orders decommissioning

#### B.2 Decommissioning Steps

1. **Impact Assessment**: What depends on this system? What data does it hold? What integrations exist?
2. **Migration Plan**: Data migration, replacement system, transition period
3. **Data Disposition**: Determine retention, archival, or deletion requirements
4. **Notice**: Notify affected parties (internal users, integrated systems, potentially affected individuals)
5. **Decommission Window**: Schedule during maintenance window with rollback plan
6. **System Shutdown**: Graceful shutdown, revoke access, remove from service discovery
7. **Data Handling**: Per data disposition plan (archive or delete)
8. **Documentation**: Update AI Use Case Registry (Status = Decommissioned)
9. **Post-Decommission Monitoring**: Verify no residual system activity for 30 days
10. **Final Report**: Document lessons learned, data disposition confirmation

#### B.3 Data Retention After Decommissioning

| Data Type | Retention After Decommission | Rationale |
|-----------|------------------------------|-----------|
| Audit logs | Per retention schedule (Section 6.1.1) | Legal and compliance requirements |
| Model artifacts | 1 year (unless litigation hold) | Regulatory review potential |
| Training data | Per data retention policy | Privacy requirements |
| Personal data | Delete or anonymize within 90 days | Privacy law requirements |
| System configuration | 1 year | Rollback contingency |
| Incident records | Per incident retention policy | Legal requirements |

---

### Appendix C: AI Vendor Assessment Questionnaire

Use this questionnaire when evaluating third-party AI vendors or services.

#### C.1 Vendor Information

- [ ] Vendor name, location, ownership
- [ ] Description of AI service/product
- [ ] Deployment model (SaaS, on-premise, hybrid)
- [ ] Data residency options
- [ ] Subprocessors and subcontractors

#### C.2 Model and Data

- [ ] What model(s) does the vendor use?
- [ ] Who trained the models?
- [ ] What data was used for training?
- [ ] Is any of Wheeler's data used for model training?
- [ ] Can Wheeler opt out of training data use?
- [ ] Is the model fine-tuned per customer? If so, what data is used?

#### C.3 Security

- [ ] SOC 2 Type II report (or equivalent)
- [ ] Encryption: in transit (TLS 1.2+) and at rest (AES-256)
- [ ] Access controls and authentication
- [ ] Audit logging capabilities
- [ ] Incident response process
- [ ] Penetration testing frequency
- [ ] Bug bounty program

#### C.4 Compliance

- [ ] Data Processing Agreement (DPA) available
- [ ] GDPR / CCPA compliance
- [ ] Data retention and deletion capabilities
- [ ] Data portability
- [ ] Subprocessor list and agreements
- [ 】 Compliance certifications (ISO 27001, SOC 2, FedRAMP, etc.)

#### C.5 AI-Specific

- [ ] Bias testing and mitigation practices
- [ ] Explainability / interpretability capabilities
- [ ] Model performance monitoring
- [ ] Content filtering and safety mechanisms
- [ ] Human review or override capabilities
- [ ] Model versioning and rollback
- [ ] Rate limiting and abuse prevention

#### C.6 Contractual

- [ ] SLA for availability and performance
- [ ] Data ownership and license terms
- [ ] Liability and indemnification for AI errors
- [ ] Right to audit
- [ ] Termination and data return/deletion
- [ ] Notice period for model or service changes

#### C.7 Assessment Outcome

- [ ] **Approved**: Vendor meets all requirements
- [ ] **Conditionally Approved**: With conditions (list below)
- [ ] **Not Approved**: Does not meet requirements
- [ ] **Further Review Needed**: Additional information required

---

### Appendix D: AI Training Data Checklist

Use this checklist before any data is used for AI training.

#### D.1 Source Verification

- [ ] Data source identified and documented
- [ ] Source terms of service permit ML training ⚖️
- [ ] Data collection methodology documented
- [ ] Data freshness / update frequency documented
- [ ] Data completeness assessment completed
- [ ] Data accuracy assessment completed

#### D.2 Privacy Review

- [ ] Does data contain PII?
  - If YES: STOP — PII may not be used for training (see Section 5.2.3)
  - If NO: Proceed
- [ ] Does data contain sensitive information (financial, health, biometric)?
  - If YES: ⚖️ ATTORNEY REVIEW REQUIRED
- [ ] Can data be anonymized or aggregated?
- [ ] Is there a lawful basis for processing?

#### D.3 Bias Assessment

- [ ] Data composition analysis: demographic, geographic, temporal coverage
- [ ] Identified potential biases in data source
- [ ] Historical bias assessment (does data reflect past discrimination?)
- [ ] Label quality review (are labels accurate and unbiased?)
- [ ] Missing data analysis (is data missing systematically?)

#### D.4 Legal Review

- [ ] Copyright/IP clearance for training data
- [ ] Contractual restrictions reviewed
- [ ] Regulatory restrictions reviewed
- [ ] Data use complies with privacy policies and notices
- [ ] Consent obtained if required
- [ ] Opt-out mechanism available

#### D.5 Technical Review

- [ ] Data quality meets minimum thresholds
- [ ] Data format is standardized
- [ ] Data versioning in place
- [ ] Data lineage documented
- [ ] Data storage meets security requirements
- [ ] Data retention schedule defined
- [ ] Data deletion capability confirmed

#### D.6 Approval

| Role | Approval Status | Date | Notes |
|------|----------------|------|-------|
| Data Owner | ___ / ___ | ___ | ___ |
| Privacy Officer | ___ / ___ | ___ | ___ |
| Legal / Compliance | ___ / ___ | ___ | ___ |
| Engineering Lead | ___ / ___ | ___ | ___ |
| AI Review Committee | ___ / ___ | ___ | ___ |

---

### Appendix E: AI Impact Assessment Template

#### E.1 System Overview

- **System Name**: _______________
- **System ID**: _______________
- **Owner**: _______________
- **Description**: _______________
- **Purpose / Intended Use**: _______________
- **Deployment Date**: _______________

#### E.2 Risk Assessment

**Risk Tier Classification**: [Tier 0-5]
**Classification Rationale**: _______________
**Classification Date**: _______________
**Classified By**: _______________

**Risk Factors**:

| Risk Factor | Assessment | Mitigation |
|-------------|-----------|------------|
| Does the system affect individuals? | Yes/No | |
| Does the system make or influence legal decisions? | Yes/No | |
| Does the system process PII or sensitive data? | Yes/No | |
| Could system errors cause significant harm? | Yes/No | |
| Is human review built in? | Yes/No | |
| Are there appeal mechanisms? | Yes/No | |
| Could the system be used for unintended purposes? | Yes/No | |
| Are there regulatory requirements? | Yes/No | |

#### E.3 Data Assessment

- **Data sources**: _______________
- **Data categories**: _______________
- **Data sensitivity**: _______________
- **Data minimization**: _______________
- **Retention period**: _______________
- **Data sharing (third parties)**: _______________

#### E.4 Fairness Assessment

- **Bias testing required?**: Yes/No
- **Protected groups affected**: _______________
- **Disparate impact risk**: _______________
- **Mitigation measures**: _______________

#### E.5 Transparency Assessment

- **External disclosure required?**: Yes/No
- **Disclosure text**: _______________
- **User notification mechanism**: _______________
- **Opt-out available?**: Yes/No

#### E.6 Human Oversight

- **Human review required?**: Yes/No
- **Review gate type**: _______________
- **Reviewer qualifications**: _______________
- **Override capability**: _______________
- **Escalation path**: _______________

#### E.7 Security Assessment

- **Security threats identified**: _______________
- **Security controls implemented**: _______________
- **Penetration testing completed?**: Yes/No
- **Adversarial testing completed?**: Yes/No

#### E.8 Approvals

| Role | Decision | Date | Signature |
|------|----------|------|-----------|
| System Owner | ___ / ___ | ___ | ___ |
| Engineering Lead | ___ / ___ | ___ | ___ |
| Legal / Compliance | ___ / ___ | ___ | ___ |
| AI Governance Board (Tier 3+) | ___ / ___ | ___ | ___ |

---

### Appendix F: Glossary of AI Governance Terms

| Term | Definition |
|------|------------|
| **Adversarial Attack** | Inputs designed to cause an AI system to produce incorrect or harmful outputs |
| **Automated Decision-Making** | Decisions made by AI without human intervention |
| **Bias** | Systematic error in AI systems that creates unfair outcomes for certain groups |
| **CCPA/CPRA** | California Consumer Privacy Act and California Privacy Rights Act — state privacy laws with automated decision-making provisions |
| **Contestability** | The ability for individuals to challenge AI decisions and obtain human review |
| **Data Minimization** | Collecting and processing only the minimum data necessary for a specific purpose |
| **Data Provenance** | The documented history of where data originated and how it was transformed |
| **Disparate Impact** | When a neutral AI system has a disproportionately negative effect on a protected group |
| **Disparate Treatment** | When an AI system explicitly treats protected groups differently |
| **Explainability** | The ability to explain in plain language how an AI system reached a particular decision |
| **Guardrails** | Defined boundaries within which an AI system may operate autonomously |
| **Human-in-the-Loop** | Human oversight of AI decisions with the ability to intervene |
| **Human-on-the-Loop** | Human monitoring of AI decisions with ability to override after the fact |
| **LLM (Large Language Model)** | AI model trained on vast text data that can generate and understand human language |
| **Model Drift** | Degradation of model performance over time due to changes in data or environment |
| **Model Inversion** | Attack technique that attempts to reconstruct training data from model outputs |
| **PII (Personally Identifiable Information)** | Information that can identify an individual, such as name, address, SSN |
| **Prompt Injection** | Attack technique where specially crafted inputs cause LLMs to ignore their instructions |
| **Proportionality** | The principle that governance rigor should scale with risk level |
| **Protected Class** | A group of people protected from discrimination under law |
| **Risk Tier** | Classification level determining governance requirements for an AI system |
| **UPL (Unauthorized Practice of Law)** | The illegal practice of law by a non-attorney or entity |
| **UPL Rules** | State-specific regulations defining who may practice law and what constitutes legal practice |

---

## DOCUMENT CONTROL

| Field | Value |
|-------|-------|
| Document ID | WHEELER-AIGOV-001 |
| Version | 1.0.0 |
| Effective Date | 2026-05-25 |
| Next Review Date | 2026-08-25 |
| Owner | AI Governance Board |
| Author | AI Governance Officer |
| Classification | Internal — CONFIDENTIAL |
| Status | ACTIVE |
| Approving Body | AI Governance Board |

## APPROVALS

| Role | Name | Signature | Date |
|------|------|-----------|------|
| CEO | _______________ | _______________ | _______ |
| CTO | _______________ | _______________ | _______ |
| General Counsel | _______________ | _______________ | _______ |
| Chief Compliance Officer | _______________ | _______________ | _______ |
| CISO | _______________ | _______________ | _______ |

**This document is a governance framework, not legal advice. Items requiring attorney review are identified with the ⚖️ ATTORNEY REVIEW REQUIRED mark. All such items should be reviewed by qualified legal counsel before implementation.**

---

*End of AI Governance Policy — Wheeler Ecosystem v1.0.0*
