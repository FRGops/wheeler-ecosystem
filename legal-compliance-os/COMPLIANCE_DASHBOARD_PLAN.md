# Phase 8: Compliance Dashboard Plan

**Status:** Draft | **Owner:** Compliance Dashboard Architect | **Version:** 2.0 | **Date:** 2026-05-25

---

## 1. DASHBOARD ARCHITECTURE

### 1.1 Design Principles

1. **Single Source of Truth** — Every metric derives from one authoritative data source. No duplicated calculations.
2. **Role-Based Views** — Each audience sees only what they need, with drill-down to raw data for power users.
3. **Real-Time Where Possible, Batched Where Practical** — P1/P2 data is real-time; P3/P4 can be cached up to 1 hour.
4. **Audit-Ready** — Every dashboard interaction is logged. Every metric has a provenance chain (source, transformation, timestamp).
5. **Mobile-First Alerting** — Critical alerts must render on a smartwatch notification. Dashboards degrade gracefully to mobile viewports.

### 1.2 Dashboard Hierarchy

```
COMPLIANCE COMMAND CENTER (Executive View)
├── LEGAL RISK DASHBOARD
│   ├── Overall Risk Score (0-100)
│   ├── Risk Trend (30/60/90 day)
│   ├── Top 10 Active Risks
│   ├── Risk Heat Map (5x5 probability x impact)
│   ├── Regulatory Change Monitor
│   └── Litigation/Dispute Tracker
├── STATE COMPLIANCE DASHBOARD
│   ├── 50-State Coverage Map (color-coded by tier)
│   ├── State-by-State Status Cards
│   ├── Regulatory Change Alerts
│   └── State Expansion Readiness
├── CONTRACT GOVERNANCE DASHBOARD
│   ├── Contract Status Overview (funnel: draft->review->approved->executed->active->expired)
│   ├── Expiring/Upcoming Renewals (30/60/90 day lookahead)
│   ├── Approval Queue with Aging
│   ├── Template Version Status
│   └── Obligation Tracking
├── PRIVACY & DATA DASHBOARD
│   ├── Data Inventory Health
│   ├── DSAR Tracker
│   ├── Consent Management Status
│   ├── Vendor Risk Status
│   ├── Breach Incident Log
│   └── Privacy Control Compliance %
├── OUTREACH COMPLIANCE DASHBOARD
│   ├── Consent Health (by channel)
│   ├── Opt-Out Rate Monitor
│   ├── DNC Compliance Status
│   ├── Message Approval Queue
│   ├── Complaint Tracker
│   └── Channel Compliance Scorecard
├── ATTORNEY MARKETPLACE DASHBOARD
│   ├── Attorney Roster Health (licenses, insurance)
│   ├── State Coverage Map
│   ├── Active Case Load
│   ├── Compliance Flag Tracker
│   ├── Referral Compliance Status
│   └── Performance Overview (anonymized, admin metrics only)
├── AI GOVERNANCE DASHBOARD
│   ├── AI System Inventory
│   ├── Risk Tier Distribution
│   ├── Human Review Completion Rate
│   ├── Model Version Status
│   ├── AI Incident Log
│   └── Bias Audit Calendar
├── AUDIT & TASK DASHBOARD
│   ├── Audit Trail Completeness Score
│   ├── Open Compliance Tasks (Kanban board)
│   ├── Remediation Progress
│   ├── Policy Review Calendar
│   └── Training Compliance
└── GOVERNANCE HEALTH DASHBOARD
    ├── Overall Compliance Score (0-100)
    ├── Policy Version Status
    ├── Governance Gap Register
    ├── Regulatory Horizon Scan
    └── Board Report Ready Status
```

### 1.3 Navigation Structure

```
Top Nav: [Command Center] [Risk] [States] [Contracts] [Privacy] [Outreach] [Attorneys] [AI Gov] [Audit] [Governance]
User Menu: [My Tasks] [Alerts] [Reports] [Settings] [Admin]
Search: Global compliance search (contracts, policies, attorneys, tasks)
```

### 1.4 Section Navigation (Within Each Dashboard)

Each dashboard has three tabs:
- **Overview** — Summary metrics, key alerts, health score
- **Details** — Full data table with filters, sort, export
- **History** — Trend charts, audit log, change history

---

## 2. KEY METRICS & KPIs

### 2.1 Overall Compliance Health Score (Composite)

**Formula:** Weighted average of sub-scores:

| Component | Weight | Data Source |
|-----------|--------|-------------|
| Legal Risk Management | 20% | Risk Register |
| State Compliance Coverage | 15% | State Matrix |
| Contract Governance | 10% | Contract System |
| Data Privacy | 15% | Privacy Platform |
| Outreach Compliance | 15% | Outreach Platform |
| Attorney Marketplace | 10% | Attorney DB |
| AI Governance | 10% | AI Audit Log |
| Audit Trail | 5% | Audit System |

**Scoring:** 0-100, where 100 = fully compliant. Sub-scores are normalized to 0-100 before weighting.

### 2.2 Detailed KPI Definitions

#### Legal Risk KPIs

| ID | Metric | Formula | Source | Frequency | Target | Warning | Critical | Owner |
|----|--------|---------|--------|-----------|--------|---------|----------|-------|
| LRS-001 | Legal Risk Score | 100 - (sum of active risk severity scores / max possible severity x 100) | Risk Register | Weekly | >= 85 | 70-84 | < 70 | CLO |
| LRS-002 | Risk Mitigation Velocity | (risks closed this period / risks identified this period) x 100 | Risk Register | Monthly | >= 80% | 60-79% | < 60% | CLO |
| LRS-003 | High-Severity Risk Count | Count of active risks with severity >= 4 | Risk Register | Daily | 0 | 1-3 | > 3 | CLO |
| LRS-004 | Risk Register Freshness | % of risks reviewed within 30 days | Risk Register | Weekly | 100% | 85-99% | < 85% | Risk Owner |
| LRS-005 | Regulatory Alert Response Time | Median hours from alert publication to assessment | Regulatory Feed | Weekly | < 48h | 48-120h | > 120h | CLO |
| LRS-006 | Outside Counsel Spend vs Budget | (actual YTD / budgeted YTD) x 100 | Financial System | Monthly | 90-110% | 110-120% | > 120% or < 80% | GC |
| LRS-007 | Litigation Caseload | Active cases by severity tier | Case Management | Weekly | < 5 Tier-1 | 5-10 Tier-1 | > 10 Tier-1 | GC |
| LRS-008 | Insurance Coverage Gap | % of required coverage lines active | Insurance Portal | Quarterly | 100% | 95-99% | < 95% | Risk Mgr |

#### State Compliance KPIs

| ID | Metric | Formula | Source | Frequency | Target | Warning | Critical | Owner |
|----|--------|---------|--------|-----------|--------|---------|----------|-------|
| STC-001 | State Compliance Coverage % | (Tier1 x 1.0 + Tier2 x 0.7 + Tier3 x 0.3) / total states x 100 | State Matrix | Monthly | >= 90% | 75-89% | < 75% | Compliance Dir |
| STC-002 | State License Validation | % of required state licenses active and current | License DB | Daily | 100% | 95-99% | < 95% | Legal Ops |
| STC-003 | Regulatory Filing Compliance | % of required state filings submitted on time | Filing Tracker | Monthly | 100% | 90-99% | < 90% | Compliance |
| STC-004 | State Expansion Readiness | % of readiness checklist complete for target states | Expansion Tracker | Weekly | >= 90% | 70-89% | < 70% | Strategy |
| STC-005 | Multi-State Notice Compliance | % of states where business registrations are current | Secretary of State APIs | Monthly | 100% | 95-99% | < 95% | Legal Ops |
| STC-006 | Regulatory Change Impacted States | Count of states with active regulatory changes | Regulatory Feed | Weekly | <= 3 | 4-7 | > 7 | Compliance |
| STC-007 | State Audit Response Time | Median days to respond to state info request | Audit Log | Quarterly | < 10 days | 10-20 days | > 20 days | Compliance |

#### Contract Governance KPIs

| ID | Metric | Formula | Source | Frequency | Target | Warning | Critical | Owner |
|----|--------|---------|--------|-----------|--------|---------|----------|-------|
| CON-001 | Contract Lifecycle Velocity | Median days from draft to execution | Contract System | Monthly | < 14 days | 14-30 days | > 30 days | Legal Ops |
| CON-002 | Contract Expiry Awareness | % of contracts with renewal alert set >= 60 days before expiry | Contract System | Weekly | 100% | 90-99% | < 90% | Legal Ops |
| CON-003 | Approval Queue Aging | % awaiting approval > 5 business days | Contract System | Daily | < 5% | 5-15% | > 15% | Legal Ops |
| CON-004 | Template Compliance | % of active contracts using current approved template | Contract System | Monthly | 100% | 95-99% | < 95% | Legal Ops |
| CON-005 | Obligation Fulfillment | % of contractual obligations met on time | Obligation Tracker | Weekly | >= 95% | 85-94% | < 85% | Contract Mgr |
| CON-006 | Contract Amendment Rate | % of contracts with amendments this quarter | Contract System | Quarterly | < 10% | 10-20% | > 20% | Legal Ops |
| CON-007 | Electronic Signature Compliance | % of e-signed contracts with valid audit trail | Signature Platform | Monthly | 100% | 95-99% | < 95% | Legal Ops |
| CON-008 | Vendor Contract Risk Score | Average risk score of active vendor contracts (1-5) | Vendor Risk | Monthly | <= 2.0 | 2.1-3.0 | > 3.0 | Procurement |
| CON-009 | Contract Repository Completeness | % of expected contracts documented in system | Contract System | Monthly | 100% | 90-99% | < 90% | Legal Ops |
| CON-010 | Auto-Renewal Exposure | Count of contracts with auto-renewal within 90 days | Contract System | Weekly | <= 3 | 4-7 | > 7 | Legal Ops |

#### Privacy & Data Protection KPIs

| ID | Metric | Formula | Source | Frequency | Target | Warning | Critical | Owner |
|----|--------|---------|--------|-----------|--------|---------|----------|-------|
| PRV-001 | Data Classification Completeness | % of data assets classified by tier | Data Inventory | Monthly | 100% | 90-99% | < 90% | DPO |
| PRV-002 | DSAR Response SLA | % of DSARs responded to within regulatory deadline | DSAR Tracker | Weekly | 100% | 90-99% | < 90% | Privacy Ops |
| PRV-003 | DSAR Backlog | Count of DSARs past regulatory deadline | DSAR Tracker | Daily | 0 | 1-5 | > 5 | Privacy Ops |
| PRV-004 | Consent Health Score | % of active consent records valid and current | CMP | Daily | >= 95% | 85-94% | < 85% | Privacy |
| PRV-005 | Vendor Risk Assessment Coverage | % of data-processing vendors with current assessment | Vendor Risk | Monthly | 100% | 85-99% | < 85% | DPO |
| PRV-006 | Breach Incident Response Time | Median hours from detection to containment | Incident Log | Weekly | < 1h | 1-4h | > 4h | CISO |
| PRV-007 | Privacy Control Implementation | % of required privacy controls implemented and verified | Control Matrix | Monthly | >= 95% | 80-94% | < 80% | DPO |
| PRV-008 | Data Retention Compliance | % of data assets with retention schedule applied | Data Inventory | Monthly | 100% | 90-99% | < 90% | Privacy |
| PRV-009 | Third-Party Data Sharing Disclosure | % of data-sharing relationships with current disclosure | Data Map | Quarterly | 100% | 90-99% | < 90% | DPO |
| PRV-010 | PIA Coverage | % of new projects/features with PIA completed | PIA Tracker | Monthly | 100% | 85-99% | < 85% | Privacy |
| PRV-011 | Cross-Border Transfer Compliance | % of cross-border data transfers with valid mechanism | Transfer Register | Monthly | 100% | 90-99% | < 90% | DPO |
| PRV-012 | CCPA/CPRA Compliance Score | Composite of CCPA required metrics | Privacy Platform | Monthly | >= 95% | 80-94% | < 80% | Privacy |

#### Outreach Compliance KPIs

| ID | Metric | Formula | Source | Frequency | Target | Warning | Critical | Owner |
|----|--------|---------|--------|-----------|--------|---------|----------|-------|
| OTC-001 | Consent Health by Channel | % of active outreach consents valid per channel | CMP | Daily | >= 95% | 85-94% | < 85% | Outreach Mgr |
| OTC-002 | Opt-Out Processing Time | Median time from opt-out receipt to full suppression | Outreach System | Real-time | < 1 min | 1-60 min | > 60 min | Ops |
| OTC-003 | Opt-Out Rate Trend | 7-day rolling average opt-out rate | Outreach System | Daily | < 2% | 2-5% | > 5% | Compliance |
| OTC-004 | DNC Scrub Recency | Hours since last DNC list scrub | Outreach System | Daily | < 24h | 24-72h | > 72h | Ops |
| OTC-005 | DNC Match Rate | % of outbound contacts matching DNC list (should be 0) | Outreach System | Daily | 0% | 0.1-0.5% | > 0.5% | Compliance |
| OTC-006 | Campaign Compliance Rate | % of active campaigns passing pre-launch compliance check | Approval System | Weekly | 100% | 95-99% | < 95% | Compliance |
| OTC-007 | Complaint Rate | Complaints per 10,000 contacts | Outreach System | Weekly | < 1 | 1-3 | > 3 | Outreach Mgr |
| OTC-008 | Message Approval Queue | % of messages pending approval > 4 hours | Approval System | Daily | < 5% | 5-15% | > 15% | Compliance |
| OTC-009 | Channel Compliance Scorecard | Composite score per channel (email, SMS, phone, direct mail) | Assessment | Monthly | >= 90% | 75-89% | < 75% | Compliance |
| OTC-010 | TCPA Consent Validity | % of TCPA-covered consents with proper disclosure and timestamp | CMP | Weekly | 100% | 95-99% | < 95% | Compliance |
| OTC-011 | SMS/MMS Compliance Rate | % of messages with opt-out language | Audit | Weekly | 100% | 95-99% | < 95% | Marketing |
| OTC-012 | CAN-SPAM Compliance Rate | % of commercial email with valid physical address, opt-out | Audit | Weekly | 100% | 95-99% | < 95% | Marketing |

#### Attorney Marketplace KPIs

| ID | Metric | Formula | Source | Frequency | Target | Warning | Critical | Owner |
|----|--------|---------|--------|-----------|--------|---------|----------|-------|
| ATT-001 | Attorney License Compliance | % of marketplace attorneys with valid, current bar membership | Bar Verification | Daily | 100% | 95-99% | < 95% | Legal Ops |
| ATT-002 | Attorney Insurance Coverage | % of attorneys with required professional liability insurance | Insurance DB | Monthly | 100% | 95-99% | < 95% | Legal Ops |
| ATT-003 | State Coverage Gap | Count of target states with no attorney coverage | Attorney DB | Weekly | 0 | 1-5 | > 5 | Marketplace Mgr |
| ATT-004 | Attorney Caseload Balance | % with caseload within target range | Case Management | Weekly | >= 80% | 60-79% | < 60% | Ops |
| ATT-005 | Compliance Flag Rate | % of attorneys with active compliance flags | Attorney DB | Daily | < 2% | 2-5% | > 5% | Compliance |
| ATT-006 | Referral Compliance Rate | % of referrals complying with jurisdiction rules | Referral Tracker | Weekly | 100% | 95-99% | < 95% | Legal Ops |
| ATT-007 | Attorney Onboarding Compliance | % completing compliance onboarding within 14 days | Onboarding | Weekly | 100% | 85-99% | < 85% | Legal Ops |
| ATT-008 | CLE Compliance Rate | % of attorneys meeting CLE requirements | CLE Tracker | Quarterly | 100% | 90-99% | < 90% | Legal Ops |
| ATT-009 | Trust Account Compliance | % with compliant trust accounting (IOLTA) | Trust Account | Monthly | 100% | 95-99% | < 95% | Compliance |
| ATT-010 | Conflict of Interest Check | % of new matters with completed conflict check | Conflict System | Daily | 100% | 95-99% | < 95% | Legal Ops |
| ATT-011 | Attorney Discipline Monitoring | Count with active disciplinary actions | Bar API | Daily | 0 | 1-3 | > 3 | Compliance |
| ATT-012 | Client Communication Compliance | % meeting JD/ABA guidelines | Audit | Monthly | >= 95% | 85-94% | < 85% | Compliance |

#### AI Governance KPIs

| ID | Metric | Formula | Source | Frequency | Target | Warning | Critical | Owner |
|----|--------|---------|--------|-----------|--------|---------|----------|-------|
| AIG-001 | AI System Inventory Completeness | % of known AI systems registered in inventory | AI Register | Monthly | 100% | 90-99% | < 90% | CTO |
| AIG-002 | AI Risk Tier Distribution | % properly risk-tiered (T1/T2/T3/T4) | AI Register | Monthly | 100% | 90-99% | < 90% | AI Gov |
| AIG-003 | Human Review Completion Rate | % of Tier 3+ AI outputs with completed human review | AI Audit Log | Weekly | 100% | 95-99% | < 95% | AI Gov |
| AIG-004 | Model Version Currency | % of production models on current approved version | Model Registry | Weekly | 100% | 90-99% | < 90% | CTO |
| AIG-005 | AI Incident Response Time | Median hours from detection to resolution | AI Incident Log | Weekly | < 4h | 4-24h | > 24h | CTO |
| AIG-006 | Bias Audit Completion Rate | % of scheduled bias audits completed on time | Audit Calendar | Quarterly | 100% | 85-99% | < 85% | AI Ethics |
| AIG-007 | Prompt Change Audit Compliance | % of prompt changes with documented review | Prompt Registry | Weekly | 100% | 90-99% | < 90% | AI Gov |
| AIG-008 | AI Training Data Compliance | % of training datasets with documented provenance | Data Register | Monthly | 100% | 90-99% | < 90% | CTO |
| AIG-009 | AI Explainability Coverage | % of high-risk AI decisions with explainability artifact | AI Audit Log | Monthly | >= 90% | 75-89% | < 75% | AI Ethics |
| AIG-010 | AI Vendor Assessment Coverage | % of third-party AI vendors assessed | Vendor Risk | Monthly | 100% | 85-99% | < 85% | CISO |
| AIG-011 | AI Gov Board Meeting Compliance | % of required governance board meetings held | Calendar | Quarterly | 100% | 80-99% | < 80% | AI Gov |
| AIG-012 | AI Monitoring Alert Freshness | % of monitoring alerts acknowledged within SLA | Alert System | Daily | >= 95% | 80-94% | < 80% | AI Ops |

#### Audit & Task KPIs

| ID | Metric | Formula | Source | Frequency | Target | Warning | Critical | Owner |
|----|--------|---------|--------|-----------|--------|---------|----------|-------|
| AUD-001 | Audit Trail Completeness | % of required audit events logged with complete metadata | Audit System | Daily | 100% | 95-99% | < 95% | CISO |
| AUD-002 | Open Compliance Tasks | Count of overdue compliance tasks | Task System | Daily | 0 | 1-10 | > 10 | Compliance Dir |
| AUD-003 | Remediation Progress | % of remediation items completed vs target date | Remediation Tracker | Weekly | >= 90% | 75-89% | < 75% | Compliance |
| AUD-004 | Policy Review Compliance | % of policies reviewed within required cadence | Policy Register | Monthly | 100% | 85-99% | < 85% | Compliance |
| AUD-005 | Training Compliance Rate | % of required compliance training completed on time | LMS | Monthly | >= 95% | 85-94% | < 85% | HR/Compliance |
| AUD-006 | Evidence Collection Readiness | % of audit evidence requests fulfilled within 48 hours | Evidence System | Quarterly | 100% | 85-99% | < 85% | Compliance |
| AUD-007 | Finding Remediation Velocity | Median days from audit finding to closure | Audit System | Quarterly | < 30 days | 30-60 days | > 60 days | Compliance |
| AUD-008 | Internal Audit Completion | % of planned internal audits completed on schedule | Audit Calendar | Quarterly | 100% | 85-99% | < 85% | Internal Audit |
| AUD-009 | Stakeholder Acknowledgment Rate | % of policy acknowledgments received within 14 days | Policy System | Monthly | >= 95% | 80-94% | < 80% | Compliance |
| AUD-010 | Access Review Completion | % of required user access reviews completed on time | IAM | Quarterly | 100% | 90-99% | < 90% | CISO |

#### Governance Health KPIs

| ID | Metric | Formula | Source | Frequency | Target | Warning | Critical | Owner |
|----|--------|---------|--------|-----------|--------|---------|----------|-------|
| GOV-001 | Policy Inventory Currency | % of policies with review date within past 12 months | Policy Register | Monthly | 100% | 85-99% | < 85% | Compliance |
| GOV-002 | Governance Gap Closure Rate | % of identified gaps closed within target timeline | Gap Register | Monthly | >= 80% | 60-79% | < 60% | Compliance Dir |
| GOV-003 | Governance Gap Count | Count of open governance gaps | Gap Register | Weekly | 0 | 1-5 | > 5 | Compliance Dir |
| GOV-004 | Regulatory Horizon Scan Coverage | % of regulatory changes assessed for impact | Horizon Scan | Monthly | 100% | 80-99% | < 80% | Compliance |
| GOV-005 | Board Report Generation Time | Median hours to generate monthly board compliance report | Reporting System | Monthly | < 4h | 4-8h | > 8h | Compliance |
| GOV-006 | Committee Meeting Attendance | % of required members attending scheduled meetings | Calendar | Quarterly | >= 80% | 60-79% | < 60% | Governance |
| GOV-007 | Policy Exception Rate | % of active policy exceptions | Policy Register | Monthly | < 5% | 5-10% | > 10% | Compliance |
| GOV-008 | Regulatory Filing Timeliness | % of regulatory filings submitted before deadline | Filing Tracker | Monthly | 100% | 90-99% | < 90% | Compliance |
| GOV-009 | Material Change Disclosure | % of material changes disclosed within required timeframe | Disclosure Tracker | Weekly | 100% | 90-99% | < 90% | Legal |
| GOV-010 | Whistleblower Program Health | % of reports investigated within 30 days | Case Management | Quarterly | 100% | 85-99% | < 85% | Ethics |

---

## 3. DASHBOARD VIEWS

### View 1: CEO Compliance Command Center

**URL:** /compliance/command-center
**Audience:** CEO, Board, Executive Team
**Refresh:** Daily (on-demand available)

```
+================================================================================+
|  COMPLIANCE COMMAND CENTER                  Last refreshed: 2026-05-25 08:00   |
+================================================================================+
|                                                                                 |
|  +---------------------------+  +-------------------------------------------+  |
|  | COMPLIANCE HEALTH         |  | TOP 5 RISKS                              |  |
|  |   92/100 (+2 vs last wk)  |  | 1. [RED]  TCPA consent gap - SMS         |  |
|  |   [=====92=====-    ]     |  | 2. [AMB]  CA Prop 22 compliance review   |  |
|  |   Score: Excellent        |  | 3. [AMB]  Attorney license renewal (3)   |  |
|  |                           |  | 4. [GRN]  DSAR SLA (100% on-time)        |  |
|  +---------------------------+  | 5. [GRN]  Data retention schedule (95%) |  |
|                                 +-------------------------------------------+  |
|  +---------------------------+  +-------------------------------------------+  |
|  | COMPLIANCE TREND (30d)    |  | STATE MAP (50-state)                      |  |
|  | 100 |    /\               |  |   [WA][OR][CA][AZ]...                    |  |
|  |  90 |   /  \  /\         |  |   Green: Tier 1 (28)                      |  |
|  |  80 |  /    \/  \  /\    |  |   Yellow: Tier 2 (15)                     |  |
|  |  70 | /          \/   \  |  |   Red: Tier 3 (7)                         |  |
|  |     +------------------  |  |   [Click state for detail]                 |  |
|  |   M1  M2  M3  M4  M5     |  |                                           |  |
|  +---------------------------+  +-------------------------------------------+  |
|                                 +-------------------------------------------+  |
|  +---------------------------+  | QUICK STATS                               |  |
|  | ACTIVE INCIDENTS          |  | Active Contracts:   142                  |  |
|  | P1: 1 [TCPA] [Details>]  |  | Attorneys OK:       47/51               |  |
|  | P2: 3 [View All>]        |  | DSARs Pending:      2 (0 overdue)       |  |
|  | P3: 7 [View All>]        |  | AI Review Rate:     98%                  |  |
|  +---------------------------+  | Open Tasks:         12 (3 overdue)       |  |
|                                 | Opt-Out Rate:       1.2% (normal)       |  |
|  +---------------------------+  +-------------------------------------------+  |
|  | REGULATORY ALERTS (7d)    |                                               |
|  | [NEW] CCPA amendments eff |                                               |
|  | [NEW] NY SHIELD Act update|                                               |
|  | [UPD] GDPR fine guidance  |                                               |
|  +---------------------------+                                               |
|                                                                                 |
|  [Generate Board Report] [Export PDF] [Share Dashboard] [Configure Alerts]     |
+================================================================================+
```

### View 2: Legal Risk Command Center

**URL:** /compliance/risk
**Audience:** CLO, Legal Team, Risk Committee
**Refresh:** Real-time (P1/P2), Daily (P3/P4)

```
+================================================================================+
|  LEGAL RISK COMMAND CENTER                      Owner: CLO | Updated: Real-time|
+================================================================================+
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | RISK HEAT MAP (5x5)           |  | RISK TREND (90 day)                    | |
|  | Impact \ Probability          |  |   # Risks Open                         | |
|  |       | VL | L | M | H | VH  |  | 30 |    /\                             | |
|  | Very H|    |   |   | X | XX  |  | 25 |   /  \    /\                      | |
|  | High  |    |   |   | 2 |  3  |  | 20 |  /    \  /  \    /\               | |
|  | Med   |    |   | X | X |     |  | 15 | /      \/    \  /  \              | |
|  | Low   |    |   |   |   |     |  | 10 |/            \/    \               | |
|  | Very L|    |   |   |   |     |  |   -+---------------------------------  | |
|  |       +----+---+---+---+--- |  |   Jan Feb Mar Apr May                   | |
|  | [Click cell for risk list]  |  |   [Toggle: Open/Closed/Severity]        | |
|  +--------------------------------+  +---------------------------------------+ |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | TOP 10 ACTIVE RISKS            |  | REGULATORY CHANGE MONITOR              | |
|  | Severity | Risk | Owner | Age  |  | Date | Regulation | Impact | Status   | |
|  | P1-Crit  | TCPA  | Comp  | 12d |  | 05-24 | CCPA amd   | High   | Assess  | |
|  | P1-Crit  | Data  | CISO  | 5d  |  | 05-22 | NY SHIELD  | Med    | Review  | |
|  | P2-High  | AI Bi | AI Et | 3d  |  | 05-20 | GDPR fin   | Low    | Monitor | |
|  | ...      | ...   | ...   | ... |  | 05-18 | TX AI law  | High   | Implem  | |
|  | [View All >]                     |  | [Subscribe to Feed] [Configure]    | |
|  +--------------------------------+  +---------------------------------------+ |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | LITIGATION/DISPUTE TRACKER     |  | OUTSIDE COUNSEL ENGAGEMENT            | |
|  | Case | Status | Counsel | Next |  | Firm | Matter | Budget | Status       | |
|  | Disc | Active | Smith   | 06-01 |  | A&O  | Merger | $120k  | Active       | |
|  | IP   | Discov | Jones   | 06-15 |  | L&W  | IP     | $85k   | Active       | |
|  | Empl | Mediat | Brown   | TBD   |  | Gund | Empl   | $45k   | Winding down | |
|  | [New Case] [View All >]          |  | [Engage New] [Budget vs Actual >]    | |
|  +--------------------------------+  +---------------------------------------+ |
+================================================================================+
```

### View 3: State Compliance Map

**URL:** /compliance/states
**Audience:** Compliance Team, Strategy, Legal Ops
**Refresh:** Daily

```
+================================================================================+
|  STATE COMPLIANCE MAP                                     Updated: 2026-05-25 |
+================================================================================+
|                                                                                 |
|  +-----------------------------------------------------------------------+     |
|  |                      UNITED STATES COMPLIANCE MAP                     |     |
|  |                                                                       |     |
|  |   [WA] [OR] [ID] [MT] [ND] [MN] [WI] [MI] [NY] [VT] [NH] [ME]      |     |
|  |   [CA] [NV] [UT] [CO] [WY] [SD] [IA] [IL] [IN] [OH] [PA] [NJ] [MA] |     |
|  |   [AZ] [NM] [KS] [NE] [MO] [KY] [WV] [VA] [MD] [DE] [CT] [RI]      |     |
|  |   [AK] [HI] [OK] [AR] [TN] [NC] [SC] [GA] [AL] [MS] [LA] [FL]      |     |
|  |                                                                       |     |
|  |   Color Key: Green = Tier 1 (28)  Yellow = Tier 2 (15)  Red = Tier 3 (7)|  |
|  |   [Hover/Click for state detail]                                         |  |
|  +-----------------------------------------------------------------------+     |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | STATE DETAIL: CALIFORNIA       |  | EXPANSION READINESS                    | |
|  | Tier: 1 (Full Compliance)      |  | Target State | Checklist | ETA        | |
|  | Key Statutes: CCPA, Prop 22    |  | Texas (T2)   | 7/10      | 2026-07   | |
|  | Active Restrictions: 2         |  | Florida (T3) | 4/10      | 2026-09   | |
|  | Attorney Coverage: 8           |  | Ohio (T2)    | 10/10     | READY!     | |
|  | Open Cases: 12                 |  | [View All Target States >]            | |
|  | Compliance Score: 94/100       |  | [Configure Expansion Criteria]        | |
|  | Last Review: 2026-05-20        |  |                                       | |
|  | [View Full State Report >]     |  |                                       | |
|  +--------------------------------+  +---------------------------------------+ |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | STATE COMPARISON               |  | REGULATORY CHANGE ALERTS BY STATE      | |
|  | Select states to compare:      |  | State | Regulation | Effective | Status | |
|  | [CA] [NY] [TX] [FL] [Compare] |  | CA    | CCPA amend | 2026-07   | Impact | |
|  | Metric     | CA | NY | TX | FL|  | NY    | SHIELD upd | 2026-08   | Impact | |
|  | Compliance | 94 | 91 | 78 | 72|  | TX    | AI Gov law | 2026-09   | Assess | |
|  | Attorneys  | 8  | 6  | 4  | 2 |  | CO    | Privacy    | 2026-07   | Monitor| |
|  | Open Cases | 12 | 8  | 5  | 3 |  | [Subscribe to State Alerts]            | |
|  +--------------------------------+  +---------------------------------------+ |
+================================================================================+
```

### View 4: Contract Operations Center

**URL:** /compliance/contracts
**Audience:** Legal Ops, Procurement, Contract Managers
**Refresh:** Hourly

```
+================================================================================+
|  CONTRACT OPERATIONS CENTER                              Updated: 2026-05-25   |
+================================================================================+
|                                                                                 |
|  +-----------------------------------------------------------------------+     |
|  | CONTRACT PIPELINE FUNNEL                                               |     |
|  |                                                                       |     |
|  |   Draft (12) ---> Review (8) ---> Approve (5) ---> Exec (3) --->     |     |
|  |     12 pending    8 in review     5 waiting        3 unsigned         |     |
|  |                                                                       |     |
|  |   Active (142) >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> Expired (8)      |     |
|  |                                                                       |     |
|  +-----------------------------------------------------------------------+     |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | EXPIRATION CALENDAR (90 day)   |  | APPROVAL QUEUE                        | |
|  | Next 30 Days:                  |  | Contract | Requestor | Days | Action  | |
|  | [Vendor A] 2026-06-15 [Alert] |  | C-142    | J. Smith   | 12d  | [Apprv]| |
|  | [Vendor B] 2026-06-22 [Alert] |  | C-143    | L. Jones   | 8d   | [Apprv]| |
|  | [Vendor C] 2026-07-01         |  | C-144    | M. Brown   | 5d   | [Apprv]| |
|  | [View All 30/60/90]           |  | C-145    | A. Davis   | 3d   | [Apprv]| |
|  +--------------------------------+  | [Bulk Approve] [Reassign Queue]      | |
|                                      +---------------------------------------+ |
|  +--------------------------------+  +---------------------------------------+ |
|  | TEMPLATE VERSION STATUS        |  | OBLIGATION TRACKING                    | |
|  | Template | Version | In Use    |  | Contract | Obligation | Due | Status  | |
|  | SOW      | v3.2    | 45        |  | C-101    | Deliverable| 06-01 | [OK]  | |
|  | MSA      | v4.1    | 38        |  | C-102    | Report     | 06-05 | [OK]  | |
|  | NDA      | v2.0    | 52        |  | C-103    | Payment    | 06-10 | [Flag] | |
|  | Vendor   | v1.5    | 7         |  | C-104    | Renewal    | 06-15 | [Warn] | |
|  | [Update Template] [Version History] | [View All Obligations] [Alert Settings]| |
|  +--------------------------------+  +---------------------------------------+ |
+================================================================================+
```

### View 5: Privacy & Data Command Center

**URL:** /compliance/privacy
**Audience:** DPO, Privacy Team, CISO
**Refresh:** Real-time

```
+================================================================================+
|  PRIVACY & DATA COMMAND CENTER                       Owner: DPO | Real-time    |
+================================================================================+
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | DATA INVENTORY TREE MAP        |  | DSAR DASHBOARD                        | |
|  |                                 |  |   Last 30 Days                       | |
|  |  +------+ +-------+ +--------+ |  | Received:   12                        | |
|  |  | PII   | | Fin   | | Health | |  | In Progress: 3 (2 on-track)         | |
|  |  | 45%   | | 22%   | | 12%    | |  | Completed:   9                       | |
|  |  +------+ +-------+ +--------+ |  | Overdue:     0                        | |
|  |  +------+ +-------+             |  | SLA:         100%                    | |
|  |  | Empl  | | Tech  |             |  | [View All DSARs >] [New DSAR]      | |
|  |  | 13%   | | 8%    |             |  |                                     | |
|  |  [By Classification Tier]       |  | Avg Response Time: 12h               | |
|  |  Restricted: 12% | Conf: 38%    |  | Regulatory Deadline: 45 days         | |
|  |  Internal: 35%  | Public: 15%   |  | [DSAR Workflow] [Auto-Escalate]      | |
|  +--------------------------------+  +---------------------------------------+ |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | CONSENT HEALTH GAUGE           |  | VENDOR RISK MATRIX                    | |
|  |                                 |  | High Risk: 3  Med Risk: 8            | |
|  |  Email:  [========98%==  ] 98%|  | Low Risk: 22 Unassessed: 2            | |
|  |  SMS:    [=====92%===   ] 92% |  |                         |             | |
|  |  Phone:  [=====89%==    ] 89% |  | Vendor | Risk | Assess | Due          | |
|  |  Direct: [=====95%===   ] 95% |  | DataCo | High | 2026-04 | Overdue [>] | |
|  |  Web:    [=====97%==    ] 97% |  | AdsInc | Med  | 2026-05 | Due soon [>]| |
|  |  [All Channels: 94%]          |  | CloudX | Low  | 2026-06 | [Assess]   | |
|  +--------------------------------+  +---------------------------------------+ |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | BREACH INCIDENT TIMELINE       |  | PRIVACY CONTROL SCORECARD              | |
|  | 2026-05-20: Phishing attempt   |  | Control              | Status | Score  | |
|  |   [Contained] [No data lost]   |  | Data Classification  | [OK]   | 100%   | |
|  | 2026-04-15: Vendor incident    |  | Access Controls      | [OK]   | 95%    | |
|  |   [Resolved] [3 records]       |  | Encryption at Rest   | [WARN] | 88%    | |
|  | 2026-03-01: No incidents       |  | Retention Schedule   | [OK]   | 92%    | |
|  | [Report Incident] [View Log >] |  | Breach Response      | [OK]   | 100%   | |
|  +--------------------------------+  | PIA Process          | [WARN] | 85%    | |
|                                      | Overall: 93% [Target: 95%]            | |
|                                      +---------------------------------------+ |
+================================================================================+
```

### View 6: Outreach Compliance Monitor

**URL:** /compliance/outreach
**Audience:** Compliance, Marketing Ops, Outreach Manager
**Refresh:** Real-time

```
+================================================================================+
|  OUTREACH COMPLIANCE MONITOR                         Owner: Compliance | Live  |
+================================================================================+
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | CONSENT STATUS BY CHANNEL      |  | OPT-OUT RATE MONITOR (7d rolling)     | |
|  |                                 |  |                                        | |
|  | Email    ||||||||||||| 45K     |  |  5% |                                 | |
|  | SMS      ||||||||||    32K     |  |  4% |            /\       [ALERT]      | |
|  | Phone    |||||||        18K    |  |  3% |    /\     /  \                   | |
|  | Direct   |||||           12K   |  |  2% |   /  \   /    \    /\            | |
|  | Web      ||||||||||||| 48K     |  |  1% |  /    \ /      \  /  \           | |
|  |                                 |  |  0% +-------------------------------- | |
|  | Green=Valid Yellow=Expiring Red=Expired | Mon Tue Wed Thu Fri Sat Sun | |
|  | [Refresh by Channel]            |  | Current: 1.8% | Threshold: 2%         | |
|  +--------------------------------+  +---------------------------------------+ |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | DNC COMPLIANCE STATUS          |  | CAMPAIGN COMPLIANCE STATUS            | |
|  | Last Scrub: 2026-05-24 23:00   |  | Campaign  | Channel | Check | Status  | |
|  | DNC Records: 2,450,321         |  | Spring Prom| Email   | Pass  | [GREEN]| |
|  | Purged This Cycle: 8,422       |  | Text Blast | SMS     | Pass  | [GREEN]| |
|  | Contacts Scanned: 52,000       |  | Call Camp  | Phone   | WARN  | [YELLOW]| |
|  | Match Rate: 0.02% [OK]         |  | Direct Mai | Mail    | FAIL  | [RED]  | |
|  | [Manual Scrub] [Configure Auto]|  | [Approve] [Flag All] [Compliance Log]| |
|  +--------------------------------+  +---------------------------------------+ |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | COMPLAINT FEED                 |  | CHANNEL HEALTH SCORECARD               | |
|  | Severity | Source | Status     |  | Channel | Score | Trend | Issues       | |
|  | [LOW]    | Email  | Responded |  | Email   | 96%   | OK    | None         | |
|  | [MED]    | Phone  | Invest.   |  | SMS     | 92%   | OK    | Opt-out rate | |
|  | [HIGH]   | SMS    | Escalated |  | Phone   | 88%   | Down  | DNC match    | |
|  | [LOW]    | Web    | Closed    |  | Direct  | 95%   | OK    | None         | |
|  | [View All] [Settings]          |  | Web     | 97%   | OK    | None         | |
|  +--------------------------------+  +---------------------------------------+ |
+================================================================================+
```

### View 7: Attorney Marketplace Monitor

**URL:** /compliance/attorneys
**Audience:** Legal Ops, Marketplace Manager, Compliance
**Refresh:** Daily

```
+================================================================================+
|  ATTORNEY MARKETPLACE MONITOR                    Owner: Legal Ops | Daily      |
+================================================================================+
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | ATTORNEY ROSTER HEALTH         |  | STATE COVERAGE MAP (Mini)             | |
|  | Total Attorneys: 51            |  | Coverage by State:                   | |
|  | Green (Good Standing): 47      |  | Full: 28 states     Gap: 5 states   | |
|  | Yellow (Warning): 3            |  | Partial: 17 states  None: 0         | |
|  | Red (Critical): 1              |  | [View Gap Details] [Recruit]        | |
|  | License Compliance: 94% [ALERT]|  | Top Gap States:                      | |
|  | Insurance Compliance: 96%      |  | ND: 0 attorneys (explore)            | |
|  | [View Full Roster >]           |  | WV: 1 attorney (recruit)            | |
|  +--------------------------------+  | WY: 0 attorneys (explore)            | |
|                                      +---------------------------------------+ |
|  +--------------------------------+  +---------------------------------------+ |
|  | ACTIVE CASE LOAD DISTRIBUTION  |  | COMPLIANCE FLAG TRACKER               | |
|  | # Attorneys                    |  | Attorney  | Flag        | Days Open  | |
|  |  15|   ***                      |  | J. Adams  | License exp | 15         | |
|  |  10|   *****                    |  | S. Brown  | CLE overdue | 8          | |
|  |   5|   ******* **              |  | M. Davis  | Insur lapse | 3          | |
|  |   0|--+--+--+--+--+--+------ |  | L. Wilson | Disc matter | 12         | |
|  |    0  5 10 15 20 25 30 Cases  |  | [Resolve Flag] [Escalate] [View All]  | |
|  | Overloaded (30+): 2           |  | Flags by Type: License:1 | CLE:1     | |
|  | Underutilized (<5): 8          |  | Ins:1 | Disc:1                        | |
|  +--------------------------------+  +---------------------------------------+ |
|  +--------------------------------+  +---------------------------------------+ |
|  | REFERRAL COMPLIANCE TRACKER    |  | DISCIPLINARY ALERT FEED               | |
|  | Referral | Rules | Status      |  | [2026-05-24] Bar complaint filed:     | |
|  | R-142    | Compliant | [OK]   |  |   Attorney A-042 (M. Davis)           | |
|  | R-143    | Non-comp  | [FLAG] |  |   Status: Under investigation          | |
|  | R-144    | Compliant | [OK]   |  | [2026-05-20] CLE non-compliance:       | |
|  | [View All] [Fix Non-Compliant]|  |   Attorney A-038 (S. Brown)           | |
|  +--------------------------------+  | [Alert Settings] [Subscribe]           | |
|  +--------------------------------+  +---------------------------------------+ |
|  | PERFORMANCE OVERVIEW (Admin)   |                                           |
|  | Avg Case Resolution: 45 days   |                                           |
|  | Client Satisfaction: 4.2/5     |                                           |
|  | Referral Conversion: 68%       |                                           |
|  | [Anonymized Report >]          |                                           |
|  +--------------------------------+                                           |
+================================================================================+
```

### View 8: AI Governance Monitor

**URL:** /compliance/ai-governance
**Audience:** CTO, AI Ethics, AI Gov Board
**Refresh:** Real-time

```
+================================================================================+
|  AI GOVERNANCE MONITOR                               Owner: CTO | Real-time    |
+================================================================================+
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | AI SYSTEM INVENTORY            |  | RISK TIER DISTRIBUTION                | |
|  | Total AI Systems: 18           |  |                                       | |
|  | Production: 14                 |  | Tier 1 (Minimal): 8  [=====45%===]   | |
|  | Development: 4                 |  | Tier 2 (Limited): 6  [====33%===]    | |
|  | By Risk Tier:                   |  | Tier 3 (High):    3  [===17%==]      | |
|  | T1: 8 | T2: 6 | T3: 3 | T4: 1|  | Tier 4 (Critical): 1 [==5%===]      | |
|  | [View Full Inventory] [Register]| | [Drill Down by Tier]                  | |
|  +--------------------------------+  +---------------------------------------+ |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | HUMAN REVIEW COMPLETION        |  | MODEL VERSION STATUS                  | |
|  | Tier 3+ Reviews Required: 42   |  | Model | Current | Latest | Status     | |
|  | Completed: 41                   |  | GPT-4 | v2.1    | v2.3   | UPDATE [>] | |
|  | Pending: 1                      |  | Claude| v3.5    | v4.0   | UPDATE [>] | |
|  | Completion Rate: 97.6% [WARN]  |  | Custom| v1.8    | v1.8   | CURRENT   | |
|  | [View Pending Reviews]          |  | Embed | v3.2    | v3.2   | CURRENT   | |
|  | Average Review Time: 2.4h      |  | [Update All] [Schedule Updates]      | |
|  +--------------------------------+  +---------------------------------------+ |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | AI INCIDENT LOG                |  | BIAS AUDIT CALENDAR                   | |
|  | Date | System | Sev | Status   |  | Q2 2026                               | |
|  | 05-24| Chatbot| Low | Resolved |  | May:  NLP model fairness assessment    | |
|  | 05-22| Classif| Med | Invest.  |  | May:  RecSys demographic parity check  | |
|  | 05-18| Embed  | Low | Resolved |  | Jun:  LLM output bias scan             | |
|  | 05-15| Chatbot| Med | Resolved |  | Jun:  CV model accuracy by demo group  | |
|  | [Report Incident] [View Log >] |  | [Schedule Audit] [Previous Results >]  | |
|  | SLA: 100% within 4h           |  +---------------------------------------+ |
|  +--------------------------------+                                           |
+================================================================================+
```

### View 9: Audit & Remediation Tracker

**URL:** /compliance/audit
**Audience:** Compliance, Internal Audit, CISO
**Refresh:** Real-time

```
+================================================================================+
|  AUDIT & REMEDIATION TRACKER                       Owner: Compliance | Real-time|
+================================================================================+
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | AUDIT TRAIL COMPLETENESS       |  | COMPLIANCE TASK BOARD (Kanban)        | |
|  | System          | Score | Trend|  | Backlog | In Prog | Review | Complete  | |
|  | Risk Register   | 100%  | OK   |  | [Task1] | [Task4] | [Task8]| [Task11] | |
|  | Contract System | 98%   | OK   |  | [Task2] | [Task5] | [Task9]| [Task12] | |
|  | Consent Platform| 100%  | OK   |  | [Task3] | [Task6] |[Task10]| [Task13] | |
|  | Audit System    | 95%   | WARN |  |         | [Task7] |        |          | |
|  | AI Audit Log    | 100%  | OK   |  | 3 tasks | 4 tasks | 3 tasks| 4 tasks  | |
|  | Overall: 98.6%  | Target: 100% |  | [Add Task] [Reassign] [Export Board]  | |
|  +--------------------------------+  | Overdue: 3 [View All]                 | |
|                                      +---------------------------------------+ |
|  +--------------------------------+  +---------------------------------------+ |
|  | REMEDIATION PROGRESS           |  | POLICY REVIEW CALENDAR                | |
|  | Phase | Tasks | Done | %       |  | Policy            | Due | Status      | |
|  | Phase 1| 12    | 12   | 100%   |  | Data Privacy      | 06-01| [On Track] | |
|  | Phase 2| 15    | 12   | 80%    |  | AI Acceptable Use | 06-15| [AT RISK]  | |
|  | Phase 3| 10    | 5    | 50%    |  | Code of Conduct   | 06-30| [Scheduled]| |
|  | Phase 4| 8     | 0    | 0%     |  | Vendor Management | 07-15| [Scheduled]| |
|  | Overall:    65% (target: 90%)  |  | Info Security     | 07-30| [Scheduled]| |
|  | [Focus on Phase 2 >]           |  | [View All Policies] [Schedule Review] | |
|  +--------------------------------+  | Overdue: 0 | Due this month: 2        | |
|                                      +---------------------------------------+ |
|  +--------------------------------+  +---------------------------------------+ |
|  | TRAINING COMPLIANCE TRACKER    |  | EVIDENCE COLLECTION                   | |
|  | Course               | Rate    |  | Audit        | Evid | Status          | |
|  | Data Privacy Training| 92%     |  | SOC 2 Type II| 45/50| In Progress [>]| |
|  | Security Awareness  | 88% [W] |  | ISO 27001    | 30/35| In Progress [>]| |
|  | AI Ethics Training  | 75% [C] |  | State Audit  | 12/12| Complete [OK]   | |
|  | HIPAA Overview      | 100%    |  | Client Audit | 8/8  | Complete [OK]   | |
|  | [Assign Training] [View All]  |  | [Upload Evidence] [Request Evidence]  | |
|  +--------------------------------+  +---------------------------------------+ |
+================================================================================+
```

### View 10: Governance Health Dashboard

**URL:** /compliance/governance
**Audience:** Compliance Dir, Board, Governance Committee
**Refresh:** Weekly

```
+================================================================================+
|  GOVERNANCE HEALTH DASHBOARD                         Owner: Compliance | Weekly |
+================================================================================+
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | POLICY INVENTORY               |  | GOVERNANCE GAP REGISTER               | |
|  | Policy | Ver | Reviewed | Due  |  | Gap ID | Description | Owner | Status  | |
|  | Data Pr| 3.2 | 2026-04 | 2027  |  | G-001  | AI oversight | CTO   | Open    | |
|  | Sec Pol| 2.1 | 2025-11 | 2026  |  | G-002  | Vendor monit | CISO  | In Prog | |
|  | AI Use | 1.0 | N/A     | OVER  |  | G-003  | State filing | Compl | Open    | |
|  | Code   | 5.0 | 2026-01 | 2027  |  | G-004  | Training gap | HR    | Closed  | |
|  | Vendor | 1.5 | 2025-08 | 2026  |  | G-005  | Consent arch | Priv  | In Prog | |
|  | [Add Policy] [View All 24 >]  |  | [Open Gaps: 3] [Closure Rate: 78%]  | |
|  | Currency: 87% [Target: 100%]  |  | [View Gap Details] [Close Gap]      | |
|  | Overdue Reviews: 2            |  |                                       | |
|  +--------------------------------+  +---------------------------------------+ |
|                                                                                 |
|  +--------------------------------+  +---------------------------------------+ |
|  | REGULATORY HORIZON SCAN        |  | BOARD REPORT GENERATION               | |
|  | Regulation | Eff Date | Impact |  | Current Period: 2026-05               | |
|  | CCPA Amend | 2026-07 | High   |  | Status: [Data Collection] 45%         | |
|  | TX AI Gov  | 2026-09 | Medium |  | Last Generated: 2026-04-30            | |
|  | EU AI Act  | 2026-12 | High   |  | Time to Generate: 3.2h                | |
|  | CO Privacy | 2026-07 | Medium |  | [Generate Now] [Schedule Auto]        | |
|  | NY SHIELD  | 2026-08 | Low    |  | [View Last Report] [Configure Format]  | |
|  | [Assess All] [Subscribe]      |  +---------------------------------------+ |
|  +--------------------------------+                                           |
|  +--------------------------------+  +---------------------------------------+ |
|  | MEETING CALENDAR               |  | GOVERNANCE SCORE BREAKDOWN            | |
|  | Committee | Date | Agenda |Att |  |                                       | |
|  | AI Gov Brd| 06-05 | [Link] | 8  |  Policies:   87% [====87%===  ]        | |
|  | Compl Comm| 06-12 | [Link] | 5  |  Gaps:       78% [===78%===== ]        | |
|  | Risk Comm | 06-19 | [Link] | 7  |  Horizon:    80% [===80%===== ]        | |
|  | Audit Comm| 06-26 | [Link] | 4  |  Reporting:  85% [===85%===== ]        | |
|  | [Schedule] [Minutes] [Actions]|  |  Meetings:   90% [===90%===== ]        | |
|  +--------------------------------+  |  Overall:    84% [===84%===== ]        | |
|                                      +---------------------------------------+ |
+================================================================================+
```

---

## 4. ALERTING & NOTIFICATIONS

### 4.1 Alert Severity Levels

| Level | Label | Response Time | Notification Channels | Escalation |
|-------|-------|---------------|----------------------|------------|
| P1 | Critical | Immediate (< 15 min) | Phone + SMS + Email + Dashboard | CEO after 30 min no response |
| P2 | High | Urgent (< 4 hours) | SMS + Email + Dashboard | Dept Head after 2h no response |
| P3 | Medium | Normal (< 24 hours) | Email + Dashboard | Owner's Manager after 24h |
| P4 | Low | Informational | Dashboard + Weekly Digest | None |

### 4.2 Alert Severity Matrix

```
    +-------------------+-------------------+-------------------+
    | Immediacy         | Impact Level      | Severity          |
    +-------------------+-------------------+-------------------+
    | Regulatory deadline within 24h | Fine/Legal liability | P1 |
    | Active data breach           | Customer harm         | P1 |
    | License lapse (active)       | Business prohibition  | P1 |
    | TCPA violation detected      | Class action risk     | P1 |
    | Attorney discipline active   | Reputation + license  | P1 |
    | Consent gap > 10%            | Regulatory risk       | P2 |
    | DSAR deadline within 24h     | Regulatory fine       | P2 |
    | Opt-out rate spike           | Compliance threshold  | P2 |
    | Policy review overdue        | Governance gap        | P3 |
    | Contract expiring <30 days   | Business continuity   | P3 |
    | Training compliance < 80%    | Audit finding         | P3 |
    | Regulatory update published  | Awareness             | P4 |
    +-------------------+-------------------+-------------------+
```

### 4.3 Complete Alert Rules (35+)

| Alert ID | Alert Name | Condition | Severity | Primary Recipients | Secondary | Channel | Auto-Escalate After |
|----------|-----------|-----------|----------|-------------------|-----------|---------|---------------------|
| AL-001 | TCPA Consent Gap | TCPA-covered consent validity < 95% | P1 | CEO, CLO, CISO | Compliance Dir | Phone+SMS+Email | 30 min |
| AL-002 | Data Breach Detected | Breach incident logged with severity >= High | P1 | CEO, CLO, CISO, CTO | DPO, Legal Ops | Phone+SMS+Email | 15 min |
| AL-003 | Attorney License Lapse | Marketplace attorney license not in good standing | P1 | Legal Ops, Marketplace Mgr | CLO | SMS+Email | 1 hour |
| AL-004 | Attorney Disciplinary Action | Disciplinary filing against marketplace attorney | P1 | CLO, Legal Ops | Compliance Dir | SMS+Email+Phone | 30 min |
| AL-005 | Regulatory Deadline Imminent | Regulatory filing deadline within 24 hours | P1 | Compliance Dir, Legal Ops | CLO | SMS+Email | 2 hours |
| AL-006 | Active Litigation Filed | New Tier 1 litigation case opened | P1 | CLO, CEO | GC | SMS+Email+Phone | 1 hour |
| AL-007 | P1 Risk Detected | New risk with severity = P1 registered | P1 | CLO, Risk Committee | CEO | SMS+Email | 2 hours |
| AL-008 | Insider Threat Detected | Privileged access anomaly | P1 | CISO, CLO, CEO | HR | Phone+SMS+Email | 15 min |
| AL-009 | Opt-Out Rate Spike | 7d rolling opt-out rate > 5% | P2 | Compliance Dir, Ops Dir | CLO | SMS+Email | 2 hours |
| AL-010 | DSAR Deadline Approaching | DSAR response due within 24 hours | P2 | Privacy Officer | DPO | SMS+Email | 4 hours |
| AL-011 | State License Expiring | State license expiring within 30 days | P2 | Legal Ops, Compliance Dir | -- | SMS+Email | 4 hours |
| AL-012 | Consent Health Degraded | Overall consent health < 85% | P2 | Privacy Officer, DPO | Compliance Dir | SMS+Email | 4 hours |
| AL-013 | DNC Scrub Overdue | Last DNC scrub > 72 hours ago | P2 | Ops Dir, Compliance | -- | SMS+Email | 4 hours |
| AL-014 | Vendor High Risk Detected | New vendor assessment = High Risk | P2 | CISO, Procurement | DPO | SMS+Email | 4 hours |
| AL-015 | AI Incident Tier 3+ | AI incident logged for Tier 3+ system | P2 | CTO, AI Ethics | AI Gov Board | SMS+Email | 2 hours |
| AL-016 | Contract Auto-Renewal Alert | Contract with auto-renewal expiring within 14 days | P2 | Legal Ops, Contract Mgr | -- | SMS+Email | 4 hours |
| AL-017 | Cross-Border Data Transfer Risk | New cross-border flow without mechanism | P2 | DPO, CISO | -- | SMS+Email | 4 hours |
| AL-018 | Training Compliance Drop | Training completion rate < 80% | P2 | HR Dir, Compliance Dir | CLO | Email | 24 hours |
| AL-019 | Campaign Compliance Failure | Outreach campaign fails pre-launch check | P2 | Compliance, Marketing Ops | -- | SMS+Email | 4 hours |
| AL-020 | Policy Review Overdue | Policy review past due date by > 30 days | P3 | Policy Owner, Compliance | Compliance Dir | Email | 24 hours |
| AL-021 | Contract Expiring (30 days) | Contract expiration within 30 days | P3 | Contract Owner, Legal Ops | -- | Email | 24 hours |
| AL-022 | Audit Evidence Gap | Evidence collection < 80% for upcoming audit | P3 | Compliance, Internal Audit | CISO | Email | 24 hours |
| AL-023 | AI Model Version Behind | Production model > 2 versions behind latest | P3 | AI Ops, CTO | -- | Email | 24 hours |
| AL-024 | Risk Register Stale | Risk not reviewed within 60 days | P3 | Risk Owner, CLO | -- | Email | 24 hours |
| AL-025 | Vendor Assessment Due | Vendor risk assessment due within 30 days | P3 | Procurement, CISO | DPO | Email | 24 hours |
| AL-026 | DSAR Volume Spike | DSARs in 7 days > 2x normal volume | P3 | Privacy Team, DPO | -- | Email | 24 hours |
| AL-027 | Market Expansion Stalled | Expansion progress < 50% of target | P3 | Strategy, Compliance Dir | CEO | Email | 24 hours |
| AL-028 | Governance Gap Aging | Open governance gap > 90 days | P3 | Compliance Dir, Gap Owner | -- | Email | 24 hours |
| AL-029 | Board Report Not Generated | Monthly report not generated by day 5 of month | P3 | Compliance Dir, CEO | -- | Email | 24 hours |
| AL-030 | Oversight Quorum Risk | Meeting attendance < 60% for 2 consecutive | P3 | Governance, Committee Chair | -- | Email | 24 hours |
| AL-031 | Regulatory Update Published | New regulation in monitored jurisdictions | P4 | Compliance, Legal | -- | Dashboard+Digest | N/A |
| AL-032 | Weekly Digest | Automated weekly compliance health summary | P4 | All stakeholders | -- | Email | N/A |
| AL-033 | Score Change | Score change > 5 points in 30 days | P4 | Compliance Dir, CLO | -- | Dashboard | N/A |
| AL-034 | Training Assigned | New compliance training assigned | P4 | All employees | -- | Email | N/A |
| AL-035 | Benchmark Update | Industry compliance benchmark updated | P4 | Compliance Dir | -- | Dashboard+Digest | N/A |

### 4.4 Alert Routing Rules

```
Alert Manager Configuration:
- P1: Route to `compliance-p1` (Phone, SMS, Email: p1@wheeler.com)
- P2: Route to `compliance-p2` (SMS, Email: alerts@wheeler.com)
- P3: Route to `compliance-p3` (Email: compliance-team@wheeler.com)
- P4: Route to `compliance-digest` (Weekly digest + dashboard notification)

Silencing Rules:
- Maintenance windows: 02:00-04:00 Sunday (suppress P3/P4)
- Holiday schedule: All P3/P4 suppressed on federal holidays
- Aggregation: Similar alerts grouped (max 5 per alert group)
- Deduplication: Same alert ID within 4h window is suppressed

Escalation Paths:
- P1 no acknowledgment within 15 min: Escalate to CEO
- P2 no acknowledgment within 2 hours: Escalate to department VP
- P3 no acknowledgment within 24 hours: Escalate to manager
```

---

## 5. DATA SOURCES & INTEGRATION

### 5.1 Complete Data Source Map

| # | Data Source | System | Data Provided | Integration Method | Refresh Rate | Format | Endpoint |
|---|-------------|--------|--------------|-------------------|-------------|--------|----------|
| 1 | Risk Register | Compliance DB (Postgres :5433) | Risk scores, status, owners, mitigations | Direct DB query | Real-time (CDC) | JSON/Table | `compliance.risks` |
| 2 | State Matrix | STATE_COMPLIANCE_MATRIX.md (manual) | State tiers, requirements, statutes | Manual webform -> API | Monthly | JSON | `/api/v1/states` |
| 3 | Consent Platform | CMP (TBD) | Consent records, opt-outs, timestamps | REST API | Real-time (webhook) | JSON | `/api/v1/consent` |
| 4 | Contract Repository | Contract Management (TBD) | Contract status, dates, parties, obligations | REST API | Hourly | JSON | `/api/v1/contracts` |
| 5 | Attorney Verification | State Bar APIs (multiple) | License status, discipline, standing | REST API | Daily | JSON | Per state |
| 6 | Attorney Database | Attorney DB (Postgres :5433) | Attorney info, caseload, compliance flags | Direct DB query | Real-time | JSON/Table | `attorneys.*` |
| 7 | DSAR Tracker | Privacy Platform (TBD) | DSAR status, deadlines, responses | REST API | Real-time | JSON | `/api/v1/dsar` |
| 8 | Data Inventory | Data Catalog (TBD) | Data assets, classification, retention | REST API | Daily | JSON | `/api/v1/data-inventory` |
| 9 | Outreach System | Outreach Platform (TBD) | Campaign status, contacts, opt-outs, complaints | REST API | Real-time | JSON | `/api/v1/outreach` |
| 10 | DNC Database | DNC Registry (internal) | DNC records, scrub timestamps, match rate | Direct DB | Real-time | JSON/Table | `compliance.dnc_registry` |
| 11 | AI Audit Log | Wheeler Brain OS | AI decisions, human reviews, incidents | Log stream | Real-time (Kafka) | JSON | `topic: ai-audit-log` |
| 12 | AI Model Registry | Model Registry (TBD) | Model versions, risk tiers, deployment status | REST API | Daily | JSON | `/api/v1/models` |
| 13 | Policy Register | Git Repository (policy/) | Policy versions, review dates, acknowledgments | Git Webhook | On-change | Markdown/JSON | GitHub API |
| 14 | Training Platform | LMS (TBD) | Training completion, compliance courses, scores | REST API | Daily | JSON | `/api/v1/lms` |
| 15 | Audit System | Audit DB (Postgres :5433) | Audit events, trail completeness, findings | Direct DB query | Real-time | JSON/Table | `audit.*` |
| 16 | Task/Remediation | Task System (TBD) | Compliance tasks, status, assignments, due dates | REST API | Real-time | JSON | `/api/v1/tasks` |
| 17 | Vendor Risk | Vendor Risk DB (Postgres :5433) | Vendor assessments, scores, status | Direct DB query | Daily | JSON/Table | `compliance.vendors` |
| 18 | Regulatory Feed | Regulatory API (TBD) | Regulatory changes, effective dates, impact | RSS/API | Daily | JSON | `/api/v1/reg-feed` |
| 19 | Litigation Tracker | Case Management (TBD) | Active cases, status, counsel, deadlines | REST API | Daily | JSON | `/api/v1/litigation` |
| 20 | Insurance Repository | Insurance DB (Postgres :5433) | Coverage lines, policies, renewal dates | Direct DB query | Daily | JSON/Table | `compliance.insurance` |
| 21 | HR System | HR Platform (TBD) | Employee onboarding, training, acknowledgments | REST API | Daily | JSON | `/api/v1/hr/compliance` |
| 22 | Governance Gap Register | Compliance DB (Postgres :5433) | Gaps, closure status, owners, target dates | Direct DB query | Real-time | JSON/Table | `compliance.governance_gaps` |
| 23 | Meeting/Committee Tracker | Calendar System (TBD) | Meeting dates, attendance, minutes, action items | REST API | Weekly | JSON | `/api/v1/meetings` |
| 24 | Breach Incident Log | Incident DB (Postgres :5433) | Breach timeline, severity, containment, notification status | Direct DB query | Real-time | JSON/Table | `compliance.breaches` |

### 5.2 Integration Architecture

```
                           +---------------------------+
                           |   Compliance API Layer     |
                           |   (FastAPI / Node.js)     |
                           +---------------------------+
                           |  /api/v1/* endpoints      |
                           |  Auth: JWT / OAuth2       |
                           |  Rate limiting            |
                           +------+--------------------+
                                  |
          +-----------------------+------------------------+
          |                       |                        |
+---------+--------+    +--------+--------+    +----------+--------+
|  Grafana Dashboards|    | Prometheus     |    | Alertmanager      |
|  (:3002)          |    | (:9090)        |    | (:9093)          |
|  - Provisioned    |    | - Custom       |    | - Alert routing  |
|  - Per-audience   |    |   exporters    |    | - Silencing      |
|  - Annotations    |    | - Compliance   |    | - Escalation     |
+-------------------+    |   metrics      |    +-------------------+
                         +----------------+
                                  |
          +-----------------------+------------------------+
          |                       |                        |
+---------+--------+    +--------+--------+    +----------+--------+
|  PostgreSQL      |    | Data Collectors |    | External APIs     |
|  (:5433)         |    | (Python cron)   |    | State Bar APIs    |
|  - Compliance DB |    | - Scrape sources|    | Regulatory Feeds  |
|  - Audit tables  |    | - Transform     |    | LMS Platform      |
|  - Materialized  |    | - Load to DB    |    | CMP Platform      |
|    views         |    | - Emit metrics  |    | Contract System   |
+------------------+    +-----------------+    +-------------------+
```

### 5.3 Compliance DB Schema (Core Tables)

```sql
-- Core compliance schema
CREATE SCHEMA IF NOT EXISTS compliance;

-- 1. Risk Register
CREATE TABLE compliance.risks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    severity INTEGER CHECK (severity BETWEEN 1 AND 5),
    probability INTEGER CHECK (probability BETWEEN 1 AND 5),
    risk_score INTEGER GENERATED ALWAYS AS (severity * probability) STORED,
    status VARCHAR(20) CHECK (status IN ('identified','assessed','mitigating','monitoring','closed')),
    owner VARCHAR(100),
    category VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_reviewed_at TIMESTAMPTZ,
    mitigation_plan TEXT,
    closure_notes TEXT
);

-- 2. State Compliance Matrix
CREATE TABLE compliance.states (
    state_code CHAR(2) PRIMARY KEY,
    state_name VARCHAR(50),
    tier INTEGER CHECK (tier BETWEEN 1 AND 3),
    compliance_score NUMERIC(5,2),
    attorney_count INTEGER DEFAULT 0,
    open_cases INTEGER DEFAULT 0,
    key_statutes TEXT[],
    business_registration_expires DATE,
    last_reviewed_at TIMESTAMPTZ,
    expansion_readiness INTEGER CHECK (expansion_readiness BETWEEN 0 AND 100)
);

-- 3. Contracts
CREATE TABLE compliance.contracts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_number VARCHAR(50) UNIQUE,
    title VARCHAR(255),
    counterparty VARCHAR(255),
    contract_type VARCHAR(50),
    status VARCHAR(20) CHECK (status IN ('draft','review','approval','executed','active','expired','terminated')),
    template_version VARCHAR(20),
    executed_at DATE,
    effective_at DATE,
    expires_at DATE,
    auto_renew BOOLEAN DEFAULT FALSE,
    renewal_alert_set BOOLEAN DEFAULT FALSE,
    obligation_count INTEGER DEFAULT 0,
    obligation_fulfilled INTEGER DEFAULT 0,
    approval_chain JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. DSAR Requests
CREATE TABLE compliance.dsar_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_name VARCHAR(255),
    requester_email VARCHAR(255),
    request_type VARCHAR(50) CHECK (request_type IN ('access','deletion','correction','portability','opt-out','objection')),
    status VARCHAR(20) CHECK (status IN ('received','verifying','in_progress','completed','overdue','rejected')),
    received_at TIMESTAMPTZ DEFAULT NOW(),
    deadline TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    response_summary TEXT,
    assigned_to VARCHAR(100)
);

-- 5. Attorney Marketplace
CREATE TABLE compliance.attorneys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attorney_id VARCHAR(50) UNIQUE,
    full_name VARCHAR(255),
    bar_state CHAR(2),
    bar_number VARCHAR(50),
    license_status VARCHAR(20) CHECK (license_status IN ('active','inactive','suspended','expired','disciplinary')),
    last_verified_at TIMESTAMPTZ,
    insurance_valid_until DATE,
    cle_due_date DATE,
    trust_account_compliant BOOLEAN,
    active_cases INTEGER DEFAULT 0,
    compliance_flags JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. AI Governance
CREATE TABLE compliance.ai_systems (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    system_name VARCHAR(255),
    description TEXT,
    risk_tier INTEGER CHECK (risk_tier BETWEEN 1 AND 4),
    model_version VARCHAR(50),
    latest_version VARCHAR(50),
    human_review_required BOOLEAN DEFAULT FALSE,
    last_bias_audit_at TIMESTAMPTZ,
    production_status VARCHAR(20) CHECK (production_status IN ('dev','staging','production','deprecated')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. AI Audit Log
CREATE TABLE compliance.ai_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ai_system_id UUID REFERENCES compliance.ai_systems(id),
    decision_type VARCHAR(100),
    input_hash VARCHAR(64),
    output_summary TEXT,
    human_reviewed BOOLEAN DEFAULT FALSE,
    human_reviewer VARCHAR(100),
    human_reviewed_at TIMESTAMPTZ,
    risk_tier INTEGER,
    incident_flag BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Outreach Compliance
CREATE TABLE compliance.outreach_campaigns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_name VARCHAR(255),
    channel VARCHAR(20) CHECK (channel IN ('email','sms','phone','direct_mail','web')),
    status VARCHAR(20) CHECK (status IN ('draft','pending_approval','active','paused','completed','cancelled')),
    consent_health NUMERIC(5,2),
    opt_out_rate NUMERIC(5,2),
    complaint_count INTEGER DEFAULT 0,
    compliance_check_status VARCHAR(20) CHECK (compliance_check_status IN ('pending','passed','failed','waived')),
    approved_by VARCHAR(100),
    launched_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Policies
CREATE TABLE compliance.policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_name VARCHAR(255),
    version VARCHAR(20),
    category VARCHAR(50),
    status VARCHAR(20) CHECK (status IN ('draft','active','under_review','superseded','archived')),
    last_reviewed_at TIMESTAMPTZ,
    review_cadence_days INTEGER,
    next_review_due DATE GENERATED ALWAYS AS (last_reviewed_at + INTERVAL '1 day' * review_cadence_days) STORED,
    owner VARCHAR(100),
    acknowledgment_required BOOLEAN DEFAULT TRUE,
    acknowledgment_rate NUMERIC(5,2)
);

-- 10. Governance Gaps
CREATE TABLE compliance.governance_gaps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gap_id VARCHAR(20) UNIQUE,
    description TEXT,
    category VARCHAR(50),
    severity VARCHAR(10) CHECK (severity IN ('critical','high','medium','low')),
    owner VARCHAR(100),
    status VARCHAR(20) CHECK (status IN ('open','in_progress','closed','waived')),
    opened_at TIMESTAMPTZ DEFAULT NOW(),
    target_close_date DATE,
    closed_at TIMESTAMPTZ,
    closure_notes TEXT
);

-- 11. Compliance Tasks
CREATE TABLE compliance.tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255),
    description TEXT,
    priority VARCHAR(10) CHECK (priority IN ('P1','P2','P3','P4')),
    status VARCHAR(20) CHECK (status IN ('backlog','in_progress','in_review','complete')),
    assignee VARCHAR(100),
    due_date DATE,
    completed_at TIMESTAMPTZ,
    related_object_type VARCHAR(50),
    related_object_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. Compliance Audit Trail
CREATE TABLE compliance.audit_trail (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(50),
    actor VARCHAR(100),
    action VARCHAR(255),
    resource_type VARCHAR(50),
    resource_id VARCHAR(100),
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Materialized view for compliance health score
CREATE MATERIALIZED VIEW compliance.health_score AS
SELECT
    'overall' AS metric,
    ROUND(
        (COALESCE(risk_score, 0) * 0.20) +
        (COALESCE(state_score, 0) * 0.15) +
        (COALESCE(contract_score, 0) * 0.10) +
        (COALESCE(privacy_score, 0) * 0.15) +
        (COALESCE(outreach_score, 0) * 0.15) +
        (COALESCE(attorney_score, 0) * 0.10) +
        (COALESCE(ai_score, 0) * 0.10) +
        (COALESCE(audit_score, 0) * 0.05)
    , 2) AS score,
    NOW() AS calculated_at
FROM compliance.sub_scores;
```

### 5.4 Data Quality Requirements

| Requirement | Standard | Validation | Remediation |
|-------------|----------|-----------|-------------|
| Completeness | No NULL required fields | Check on write | Reject or default |
| Timeliness | Within refresh SLA | Timestamp comparison | Alert on staleness |
| Accuracy | Source-of-truth verified | Cross-reference | Flag for review |
| Consistency | Same metric same value across views | Cross-dashboard comparison | Synchronize at source |
| Auditability | Full provenance chain | Lineage tracking | Log all transformations |

---

## 6. TECHNOLOGY STACK RECOMMENDATION

### 6.1 Option A: Wheeler Stack (Recommended for Phase 1)

| Component | Technology | Existing Instance | Purpose |
|-----------|-----------|-------------------|---------|
| Database | PostgreSQL 16 | `:5433` (wheeler-db) | Compliance data warehouse |
| Metrics | Prometheus | `:9090` | Metric collection from exporters |
| Visualization | Grafana | `:3002` | Dashboards and alerting |
| Alerting | Alertmanager | `:9093` | Alert routing and notification |
| API Layer | FastAPI (Python) | New microservice | REST API for dashboard data |
| Data Collection | Python cron jobs | Wheeler Brain OS agents | Scheduled ETL from sources |
| Authentication | OAuth2 / JWT | Wheeler SSO | Role-based access control |
| Secrets | HashiCorp Vault | New deployment | API keys, DB credentials |
| Logging | ELK/Loki | Existing stack | Audit trail, debugging |
| GitOps | GitHub + ArgoCD | Existing | Infrastructure as Code |

**Total Estimated Cost:** Infrastructure only (existing resources). Estimated engineering: 4-6 weeks (Phase 1-2).

### 6.2 Option B: Dedicated Compliance Platform

| Platform | Pricing | Strengths | Weaknesses |
|----------|---------|-----------|------------|
| Vanta | $10-15K/yr | SOC 2, ISO 27001 | Limited state compliance |
| Drata | $12-18K/yr | Great integrations | Less customization |
| Secureframe | $15-25K/yr | Auditor reports | Expensive for custom metrics |
| Hyperproof | $10-20K/yr | Risk management | Steeper learning curve |
| LogicGate | $20-50K/yr | Enterprise GRC | Overkill for current stage |

### 6.3 Recommendation: Hybrid Approach

```
Phase 1 (Weeks 1-4): Build on Wheeler Stack
  - Leverage existing Postgres, Grafana, Prometheus
  - Fast custom dashboards for immediate needs
  - Low incremental cost

Phase 2 (Months 2-3): Evaluate Dedicated Platform
  - If compliance program scales beyond 200+ metrics
  - If auditor requires certified platform
  - If regulatory complexity (multi-state, multi-country) demands it

Phase 3 (Months 4-6): Integrate or Migrate
  - Connect dedicated platform as data source to Grafana
  - Or migrate fully if platform covers all needs
  - Keep Wheeler Brain OS agents for custom automation
```

### 6.4 Infrastructure Requirements

| Resource | Specification | Quantity | Purpose |
|----------|--------------|----------|---------|
| Application Server | 2 vCPU, 4 GB RAM | 2 | FastAPI + data collectors |
| Database | 4 vCPU, 8 GB RAM | Shared (existing) | PostgreSQL compliance schema |
| Storage | 50 GB SSD | Shared | Compliance data |
| Grafana | Shared instance | 1 | New compliance folder/datasource |
| Prometheus | Shared instance | 1 | New compliance exporters |
| Secret Management | 1 vCPU, 2 GB RAM | 1 (if new) | Vault for API keys |

---

## 7. IMPLEMENTATION ROADMAP

### 7.1 Phase 1: Foundation (Weeks 1-2)

**Goal:** Stand up compliance data infrastructure and CEO-facing dashboard.

**Week 1 - Data Infrastructure:**
- [ ] Create compliance schema in PostgreSQL (core 12 tables)
- [ ] Build FastAPI compliance API layer (`/api/v1/compliance/*`)
- [ ] Deploy data collectors for existing sources (risk register, contract registry)
- [ ] Set up Prometheus compliance exporters
- [ ] Configure Grafana compliance data source

**Week 2 - CEO Dashboard + P1 Alerts:**
- [ ] Build CEO Compliance Command Center dashboard (View 1)
- [ ] Implement Compliance Health Score calculation (materialized view)
- [ ] Configure P1 alert rules in Alertmanager (AL-001 through AL-008)
- [ ] Set up SMS/Phone notification channels
- [ ] Implement role-based access control
- [ ] Deploy first version to production

**Deliverables:**
- Working compliance database with 12 tables
- CEO Command Center dashboard at `:3002/d/compliance/ceo`
- P1 alerting active (phone + SMS + email)
- API documentation at `/api/v1/compliance/docs`

**Risk Mitigation:**
- If FastAPI resource constrained: Use Node/Express on existing app server
- If Grafana licensing issue: Use Metabase as backup
- If SMS provider not available: Start with email + dashboard only

### 7.2 Phase 2: Core Dashboards (Weeks 3-4)

**Week 3 - State + Contract Dashboards:**
- [ ] Build State Compliance Map dashboard (View 3)
- [ ] Integrate state bar APIs for attorney verification
- [ ] Build Contract Operations Center dashboard (View 4)
- [ ] Implement state compliance scoring algorithm
- [ ] Onboard state compliance matrix data

**Week 4 - Privacy + Outreach Dashboards:**
- [ ] Build Privacy & Data Command Center (View 5)
- [ ] Implement DSAR tracking workflow
- [ ] Build Outreach Compliance Monitor (View 6)
- [ ] Integrate consent platform API
- [ ] Configure P2 alert rules (AL-009 through AL-019)

**Deliverables:**
- State Compliance Map (interactive US map)
- Contract Operations Center with pipeline funnel
- Privacy Command Center with DSAR workflow
- Outreach Compliance Monitor with real-time opt-out tracking
- P2 alerting active (SMS + email)

### 7.3 Phase 3: Advanced Dashboards (Weeks 5-6)

**Week 5 - Attorney + AI Governance:**
- [ ] Build Attorney Marketplace Monitor (View 7)
- [ ] Integrate state bar API multi-state verification
- [ ] Build AI Governance Monitor (View 8)
- [ ] Integrate Wheeler Brain OS AI audit log
- [ ] Configure bias audit calendar

**Week 6 - Audit + Governance:**
- [ ] Build Audit & Remediation Tracker (View 9)
- [ ] Build Governance Health Dashboard (View 10)
- [ ] Implement task Kanban board
- [ ] Implement policy review calendar
- [ ] Configure P3/P4 alert rules (AL-020 through AL-035)

**Deliverables:**
- Attorney Marketplace Monitor with live license verification
- AI Governance Monitor with human review tracking
- Audit & Remediation Tracker with Kanban
- Governance Health Dashboard with gap register
- All alert levels active

### 7.4 Phase 4: Automation (Weeks 7-8)

**Week 7 - Data Pipeline Automation:**
- [ ] Automate data collection for all 24 sources
- [ ] Implement CDC (Change Data Capture) for Postgres sources
- [ ] Build data quality monitoring dashboard
- [ ] Implement automated state bar API queries
- [ ] Build consent platform webhook receiver

**Week 8 - Alerting + API Polish:**
- [ ] Semantic alert deduplication and aggregation
- [ ] Escalation paths fully tested
- [ ] API rate limiting and caching layer
- [ ] Grafana alert annotations on dashboards
- [ ] Weekly digest email automation

**Deliverables:**
- Full automation of all data pipelines
- Production-ready alerting with all escalation paths
- Comprehensive API with caching
- Weekly compliance digest

### 7.5 Phase 5: Refinement (Weeks 9-12)

**Week 9 - User Testing:**
- [ ] CEO/Executive dashboard review session
- [ ] Compliance team workflow validation
- [ ] Legal team feedback collection
- [ ] Engineering/CTO AI governance review
- [ ] Performance benchmark and optimization

**Week 10 - Mobile + Responsive:**
- [ ] Mobile-responsive dashboard layouts
- [ ] P1 alert mobile push notifications
- [ ] Touch-friendly interactive map
- [ ] Reduced data mode for low-bandwidth

**Week 11 - Integration:**
- [ ] Embed compliance widgets in Executive Dashboard (:8180)
- [ ] Cross-link compliance dashboards with Grafana (:3002)
- [ ] Add compliance status to Uptime Kuma (:3001)
- [ ] Automated board report PDF generation
- [ ] CSV/Excel export for all dashboard views

**Week 12 - Hardening + Documentation:**
- [ ] Security audit of dashboard access
- [ ] Penetration testing of API endpoints
- [ ] Full system documentation
- [ ] Runbook for compliance dashboard operations
- [ ] Training for dashboard administrators

**Deliverables:**
- All 10 dashboard views in production
- Mobile responsive
- Executive dashboard integration
- Board report auto-generation
- Full documentation and runbooks

---

## 8. MOCKUPS (ASCII ART)

### 8.1 CEO Compliance Command Center (Full Detail)

```
+================================================================================+
|  WHEELER COMPLIANCE COMMAND CENTER                    Welcome, Sarah [Logout]  |
+================================================================================+
| [Command Center] [Risk] [States] [Contracts] [Privacy] [Outreach] [Attys] [AI] |
| [Audit] [Governance]  |  Search compliance...  |  [Alerts (4)] [Settings]     |
+================================================================================+
|                                                                                 |
| +----------------------------+  +-------------------------------------------+  |
| | COMPLIANCE HEALTH SCORE    |  | COMPLIANCE SUB-SCORES                    |  |
| |                            |  |                                           |  |
| |        [=========]         |  | Legal Risk:    [==========84%====    ] 84 |  |
| |        [ 92 / 100 ]        |  | State Comp:    [============92%==    ] 92 |  |
| |        [=========]         |  | Contracts:     [===========88%===    ] 88 |  |
| |       EXCELLENT            |  | Privacy:       [=============93%=    ] 93 |  |
| |                            |  | Outreach:      [=============91%=    ] 91 |  |
| |  [+2 vs last week]         |  | Attorneys:     [==========85%====    ] 85 |  |
| |  [Trend: Improving]        |  | AI Governance: [=============90%=    ] 90 |  |
| |                            |  | Audit Trail:   [===========89%===    ] 89 |  |
| +----------------------------+  +-------------------------------------------+  |
|                                                                                 |
| +----------------------------+  +-------------------------------------------+  |
| | TOP 5 RISKS                |  | STATE COVERAGE MAP (Mini)                |  |
| |                            |  |                                           |  |
| | Severity | Risk         |  |  |   [WA][OR][CA]...[NY][MA]                |  |
| | [CRIT] TCPA Consent Gap |  |  |   [TX]...[FL]                            |  |
| | [HIGH] CA Prop 22 Review|  |  | Green: 28 | Yellow: 15 | Red: 7         |  |
| | [HIGH] Atty License (3) |  |  | [Click to expand >]                     |  |
| | [MED ] Data Retention   |  |  | Top Tier 3 States:                      |  |
| | [MED ] AI Bias Audit Due|  |  | - ND (0% compliance)                    |  |
| | [View All 18 Risks >]   |  |  | - WV (32% compliance)                   |  |
| +----------------------------+  | - WY (28% compliance)                   |  |
|                                 +-------------------------------------------+  |
| +----------------------------+                                               |
| | COMPLIANCE TREND (30 day)  |  +-------------------------------------------+  |
| |  100 - /\  /\              |  | QUICK STATS                              |  |
| |   95 -/  \/  \  /\  /\    |  | Active Contracts:            142         |  |
| |   90 -       \/  \/  \---|  | Attorneys in Good Standing:  47/51       |  |
| |   85 +--------------------+|  | DSARs Pending:               2 (0 overdue)|  |
| |      W1  W2  W3  W4  W5   |  | AI Review Rate:              97.6%      |  |
| |      [7d] [30d] [90d]     |  | Open Compliance Tasks:       12          |  |
| +----------------------------+  | Overdue Tasks:               3           |  |
|                                 | Policy Reviews Overdue:     2           |  |
| +----------------------------+  | Opt-Out Rate (7d rolling):   1.8%       |  |
| | ACTIVE INCIDENTS           |  | DNC Last Scrub:              23h ago    |  |
| |                            |  | Remediation Progress:        65%        |  |
| | [P1] TCPA Consent Gap (1)  |  +-------------------------------------------+  |
| | [P2] Compliance Issues (3) |                                               |
| | [P3] Low Severity    (7)   |  +-------------------------------------------+  |
| | [View All Incidents >]     |  | REGULATORY ALERTS (Last 7 Days)          |  |
| +----------------------------+  | [NEW] CCPA amendments effective 2026-07  |  |
|                                 | [NEW] NY SHIELD Act update               |  |
| +----------------------------+  | [NEW] TX AI Governance Law               |  |
| | BOARD REPORT: 45% complete   |  | [UPD] GDPR fine guidance                |  |
| | [Generate Now] [Schedule]   |  | [View All] [Subscribe] [Configure]      |  |
| +----------------------------+  +-------------------------------------------+  |
+================================================================================+
```

### 8.2 State Compliance Map (Interactive Detail)

```
+================================================================================+
|  STATE COMPLIANCE MAP               Data: State Matrix | Updated: Daily        |
+================================================================================+
|                                                                                 |
|  +-----------------------------------------------------------------------+     |
|  |                         UNITED STATES COMPLIANCE MAP                  |     |
|  |                                                                       |     |
|  |                  MAP LEGEND:                                          |     |
|  |     [GREEN] Tier 1 - Full Compliance (28 states)                      |     |
|  |     [YELLOW] Tier 2 - Partial Compliance (15 states)                  |     |
|  |     [RED] Tier 3 - Non-Compliant / Not Active (7 states)              |     |
|  |                                                                       |     |
|  |           [AK]                                                    [ME]|     |
|  |   [WA] [ID] [MT] [ND] [MN] [WI] [MI] [NY] [VT] [NH]                 |     |
|  |   [OR] [NV] [WY] [SD] [IA] [IL] [IN] [OH] [PA] [NJ] [CT] [MA] [RI]  |     |
|  |   [CA] [UT] [CO] [NE] [MO] [KY] [WV] [VA] [MD] [DE]                 |     |
|  |   [AZ] [NM] [KS] [AR] [TN] [NC] [SC]                                 |     |
|  |   [OK] [LA] [MS] [AL] [GA]                                           |     |
|  |   [HI] [TX] [FL]                                                     |     |
|  |                                                                       |     |
|  |   [Hover for tooltip] [Click for state detail] [Zoom: +/-]           |     |
|  +-----------------------------------------------------------------------+     |
|                                                                                 |
|  STATE DETAIL PANEL (California selected)                                       |
|  +-----------------------------------------------------------------------+     |
|  | CALIFORNIA | TIER 1 | Score: 94/100 | Last Reviewed: 2026-05-20      |     |
|  | Key Statutes: CCPA/CPRA, Prop 22, CalOPPA                             |     |
|  | Pending: AI Training Transparency Act (effective 2026-08)             |     |
|  | Privacy Controls: 95% | Attorney Coverage: 8 | Open Cases: 12        |     |
|  | Alerts: CCPA amendments effective 2026-07 - impact assessment needed  |     |
|  | [View Full Report] [Download Compliance Package] [Flag for Review]    |     |
|  +-----------------------------------------------------------------------+     |
+================================================================================+
```

### 8.3 Risk Heat Map (5x5 Interactive Detail)

```
+================================================================================+
|  RISK HEAT MAP                                    Source: Risk Register | Live  |
+================================================================================+
|                                                                                 |
|  +-----------------------------------------------------------------------+     |
|  |                    IMPACT                                                  | |
|  |               Very Low    Low     Medium     High     Very High            | |
|  |              +--------+--------+--------+--------+--------+              | |
|  | Very High    |        |        |        |  [R8]  | [R1][R3]|  5         | |
|  |              |        |        |        |  [R12] | [R7]    |            | |
|  |              +--------+--------+--------+--------+--------+              | |
|  | High         |        |        | [R14]  | [R2]   | [R5]    |  4         | |
|  |              |        |        | [R18]  | [R9]   |         |            | |
|  |              +--------+--------+--------+--------+--------+              | |
|  | Medium       |        |        | [R10]  | [R6]   |         |  3         | |
|  |              |        |        | [R15]  |        |         |            | |
|  |              +--------+--------+--------+--------+--------+              | |
|  | Low          |        | [R16]  | [R11]  |        |         |  2         | |
|  |              |        | [R17]  |        |        |         |            | |
|  |              +--------+--------+--------+--------+--------+              | |
|  | Very Low     |        |        | [R13]  |        |         |  1         | |
|  |              +--------+--------+--------+--------+--------+              | |
|  |                 1        2        3        4        5                   | |
|  | Probability                                                             | |
|  |                                                                         | |
|  | [Click any cell to view risks] | Color: Green=Tolerable Yellow=Moderate | |
|  |                                | Red=High  Dark Red=Extreme             | |
|  | Current Filter: All Risks (18)                                          | |
|  | [Filter by Category] [Filter by Owner] [Filter by Status]               | |
|  +-----------------------------------------------------------------------+ |
|                                                                                 |
|  +----------------------------+  +-------------------------------------------+  |
|  | TOP RISKS BY SEVERITY      |  | RISK BREAKDOWN BY CATEGORY               |  |
|  | R-001 TCPA Gap        [P1] |  | Regulatory: 5 (28%) Privacy: 4 (22%)    |  |
|  | R-002 Prop 22        [P1] |  | Operational: 3 (17%) Tech: 3 (17%)      |  |
|  | R-003 Data Breach    [P1] |  | Financial: 2 (11%) Reputational: 1 (5%) |  |
|  | R-004 AI Bias        [P2] |  | [Drill Down by Category]                |  |
|  | R-005 License Lapse  [P2] |  +-------------------------------------------+  |
|  | [View All][Add][Export]   |                                               |
|  +----------------------------+                                              |
+================================================================================+
```

### 8.4 Privacy Command Center (Full Detail)

```
+================================================================================+
|  PRIVACY COMMAND CENTER                           Owner: DPO | Real-time       |
+================================================================================+
|                                                                                 |
|  +----------------------------+  +-------------------------------------------+  |
|  | DATA INVENTORY BY TIER     |  | DSAR WORKFLOW PIPELINE                   |  |
|  |                            |  |                                           |  |
|  | [=========] 45% PII       |  | Received -> Verifying -> In Prog -> Done  |  |
|  | [=====] 22% Financial     |  |    12         2            1        9     |  |
|  | [===] 12% Health          |  | SLA: 100% | Avg Response: 12h | Overdue: 0 |  |
|  | [===] 13% Employee        |  | [New DSAR] [View All] [Export]             |  |
|  | [==] 8% Technical         |  | DSAR Detail: DSAR-2026-089 (Access)       |  |
|  | Classification: 100%      |  | Status: Data Collection (12/15 systems)   |  |
|  | Retention: 92%            |  | [Update] [Escalate] [Mark Complete]       |  |
|  +----------------------------+  +-------------------------------------------+  |
|                                                                                 |
|  +----------------------------+  +-------------------------------------------+  |
|  | CONSENT HEALTH BY CHANNEL  |  | VENDOR RISK SUMMARY                      |  |
|  | Email: 98% | SMS: 92%     |  | High: 3 | Med: 8 | Low: 22 | Unassessed: 2|  |
|  | Phone: 89% | Direct: 95%   |  | [View Vendor Risk Matrix] [Assess Now]   |  |
|  | Web: 97%   | Overall: 94%  |  +-------------------------------------------+  |
|  +----------------------------+                                               |
|                                                                                 |
|  +----------------------------+  +-------------------------------------------+  |
|  | BREACH INCIDENT TIMELINE   |  | PRIVACY CONTROL SCORECARD                 |  |
|  | May 20: Phishing [Contained]|  | Data Class: 100% | Access: 95%           |  |
|  | Apr 15: Vendor [Resolved]  |  | Encrypt: 88% | Retention: 92%            |  |
|  | Mar 01: No incidents       |  | Breach Resp: 100% | PIA: 85% | Consent: 94%|  |
|  | [Report Incident] [Log >]  |  | Vendor Oversight: 82%                     |  |
|  +----------------------------+  | OVERALL: 93% [Target: 95%]               |  |
|                                 +-------------------------------------------+  |
+================================================================================+
```

---

## 9. ROLES & PERMISSIONS

### 9.1 Role Definitions

| Role | Description | Can View | Can Edit | Can Admin |
|------|-------------|----------|----------|-----------|
| **Compliance Admin** | Full system administration | All dashboards + settings | All data, alerts, config | Users, roles, integrations |
| **CEO/Executive** | High-level oversight | Command Center, Risk, Governance AI | Acknowledge P1 alerts | N/A |
| **CLO/General Counsel** | Legal risk oversight | Risk, Contracts, Litigation | Risk register, contracts | Alert thresholds (legal) |
| **Compliance Director** | Day-to-day compliance | All dashboards | Tasks, policies, state matrix | Alert rules, task templates |
| **DPO/Privacy Officer** | Privacy & data protection | Privacy, DSAR, Consent, Vendor | DSAR workflow, PIAs | Privacy control thresholds |
| **Compliance Analyst** | Compliance data entry | All dashboards (read) | Tasks, evidence upload | N/A |
| **Legal Ops** | Attorney & contract management | Attorneys, Contracts | Attorney records, contracts | N/A |
| **CTO/Engineering** | AI & technical compliance | AI Governance, Privacy (tech) | AI system registry | AI governance thresholds |
| **CISO** | Security & audit compliance | Audit, Privacy (security) | Audit findings | Audit trail config |
| **Outreach Manager** | Marketing compliance | Outreach, Consent | Campaign compliance | Outreach thresholds |
| **Internal Audit** | Independent review | All dashboards (read-only) | Audit findings, evidence | N/A |
| **Board Member** | Governance oversight | Command Center, Governance | N/A | N/A |
| **External Auditor** | Audit evidence review | Audit, Evidence (read-only) | N/A | N/A |

### 9.2 Access Control Matrix

```
+---------------------+---+---+---+---+---+---+---+---+---+---+---+---+
| Dashboard / Feature | A1 | A2 | A3 | A4 | A5 | A6 | A7 | A8 | A9 | A10|
+---------------------+---+---+---+---+---+---+---+---+---+---+---+---+
| Command Center      | RW | R  | R  | R  | R  | R  | R  | R  | R  | R  |
| Risk Dashboard      | RW | R  | RW | RW | R  | R  | R  | R  | R  | -  |
| State Map           | RW | R  | R  | RW | R  | R  | R  | -  | R  | -  |
| Contracts           | RW | R  | RW | RW | R  | R  | RW | -  | -  | -  |
| Privacy             | RW | -  | R  | RW | RW | R  | -  | R  | R  | -  |
| Outreach            | RW | -  | R  | RW | R  | R  | -  | -  | -  | RW |
| Attorneys           | RW | -  | RW | R  | -  | R  | RW | -  | -  | -  |
| AI Governance       | RW | R  | R  | R  | -  | -  | -  | RW | -  | -  |
| Audit & Tasks       | RW | R  | RW | RW | R  | RW | R  | R  | RW | R  |
| Governance Health   | RW | R  | RW | RW | R  | R  | R  | R  | R  | R  |
| Alert Configuration | RW | -  | R  | RW | R  | -  | -  | R  | R  | -  |
| User Management     | RW | -  | -  | -  | -  | -  | -  | -  | -  | -  |
| API Access          | RW | -  | -  | R  | R  | R  | -  | R  | -  | -  |
| Export/Reports      | RW | R  | RW | RW | RW | RW | RW | R  | R  | R  |
+---------------------+---+---+---+---+---+---+---+---+---+---+---+---+

A1=Admin  A2=CEO  A3=CLO  A4=CompDir  A5=DPO  A6=Analyst
A7=LegalOps  A8=CTO  A9=CISO  A10=OutreachMgr
R=Read  RW=Read+Write  -=No Access
```

---

## 10. NON-FUNCTIONAL REQUIREMENTS

### 10.1 Performance

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Dashboard load time | < 3 seconds | Lighthouse / Custom |
| API response time (P50) | < 200ms | APM (Datadog/Prometheus) |
| API response time (P99) | < 1 second | APM |
| Concurrent users | 50 simultaneous | Load testing |
| Data freshness (P1 metrics) | < 1 minute | Timestamp comparison |
| Data freshness (P2/P3) | < 1 hour | Timestamp comparison |
| Export generation | < 30 seconds | Timer |
| Alert notification delivery | < 30 seconds | End-to-end monitoring |

### 10.2 Availability

| Component | Target | Maintenance Window |
|-----------|--------|-------------------|
| Dashboard UI | 99.9% uptime | Sunday 02:00-04:00 |
| API Layer | 99.9% uptime | Rolling deployment |
| Database | 99.95% uptime | HA PostgreSQL |
| Alerting | 99.99% uptime | Redundant channels |
| Data Collectors | 99.5% uptime | 1-hour daily window |

### 10.3 Security

| Requirement | Standard | Implementation |
|-------------|----------|---------------|
| Authentication | OAuth 2.0 / OIDC | Wheeler SSO integration |
| Authorization | Role-based (RBAC) | JWT claims + middleware |
| API Security | TLS 1.3 + API keys | All traffic encrypted |
| Audit Logging | All data access logged | Immutable audit table |
| Data Encryption | AES-256 at rest | PostgreSQL TDE |
| Secrets Management | HashiCorp Vault | API keys, DB passwords |
| Session Management | 30min timeout + refresh | Redis session store |
| Rate Limiting | 100 req/min per user | Nginx + API middleware |
| CORS | Whitelist domains | Grafana origin only |
| Penetration Testing | Annual | Third-party |

### 10.4 Compliance of the Compliance System

The compliance dashboard itself must comply with:
- **SOC 2 Type II** -- Access controls, change management, availability monitoring
- **Data Residency** -- All compliance data stored within US (or relevant jurisdiction)
- **Retention** -- Dashboard audit logs retained for 7 years
- **Confidentiality** -- Attorney data, contract terms, risk information classified as Internal/Restricted
- **Backup** -- Compliance DB backed up daily with 30-day retention

---

## 11. SUCCESS CRITERIA

### 11.1 Launch Criteria (Phase 1 Complete)

- [ ] Compliance database schema deployed with core 12 tables
- [ ] CEO Command Center dashboard functional and accurate
- [ ] Compliance Health Score calculating correctly
- [ ] P1 alerts delivering within 30 seconds
- [ ] At least 80% of risk register data loaded
- [ ] At least 90% of state matrix data loaded
- [ ] API layer deployed and documented
- [ ] Role-based access implemented for 3+ roles
- [ ] All dashboards load within 3 seconds
- [ ] Executive team has reviewed and approved

### 11.2 Success Metrics (90 Days Post-Launch)

| Metric | Target |
|--------|--------|
| Executive dashboard weekly active users | > 5 |
| Compliance team daily active users | > 10 |
| Dashboard load time (P95) | < 2 seconds |
| Alert accuracy (no false positives) | > 95% |
| Data source freshness compliance | > 95% |
| Board report generation time | < 4 hours |
| User satisfaction score | > 4.0 / 5.0 |
| Audit evidence collection time reduction | > 50% |
| Compliance task completion rate increase | > 30% |
| Regulatory deadline missed reduction | > 80% |

### 11.3 Ongoing Governance

| Activity | Frequency | Owner |
|----------|-----------|-------|
| Dashboard metrics accuracy audit | Weekly | Compliance Director |
| Alert rule review and tuning | Bi-weekly | Compliance + CISO |
| New data source onboarding review | Monthly | Compliance Director |
| User access review | Monthly | Compliance Admin |
| Dashboard usage analytics review | Monthly | Product Owner |
| Performance optimization review | Quarterly | Engineering |
| Security review | Quarterly | CISO |
| Full compliance program review | Annually | Board |

---

## APPENDIX A: GLOSSARY

| Term | Definition |
|------|------------|
| CCPA/CPRA | California Consumer Privacy Act / California Privacy Rights Act |
| CDC | Change Data Capture -- real-time database change streaming |
| CLE | Continuing Legal Education -- attorney education requirements |
| CLO | Chief Legal Officer |
| CMP | Consent Management Platform |
| DNC | Do Not Call -- telemarketing exclusion registry |
| DPO | Data Protection Officer |
| DSAR | Data Subject Access Request -- GDPR/CCPA right to access personal data |
| GDPR | General Data Protection Regulation (EU) |
| IOLTA | Interest on Lawyer Trust Accounts -- attorney trust accounting |
| PIA | Privacy Impact Assessment |
| RBAC | Role-Based Access Control |
| TCPA | Telephone Consumer Protection Act -- US telemarketing law |
| Tier 1/2/3 | State compliance classification (1=fully compliant, 3=non-compliant) |

## APPENDIX B: REFERENCE ARCHITECTURE DIAGRAM

```
+====================================================================+
|                    COMPLIANCE DASHBOARD SYSTEM                      |
+====================================================================+
|                                                                     |
|  +-------------------+      +-------------------+                   |
|  |   GRAFANA UI      |      |   CUSTOM REACT    |                   |
|  |   (:3002)         |      |   DASHBOARDS       |                   |
|  |   (Grafana)       |      |   (if needed)      |                   |
|  +--------+----------+      +--------+----------+                   |
|           |                          |                              |
|           +-----------+--------------+                              |
|                       |                                             |
|              +--------+--------+                                    |
|              |  FASTAPI        |                                    |
|              |  /api/v1/*      |                                    |
|              |  Auth: JWT      |                                    |
|              |  Rate Limit:100 |                                    |
|              +--------+--------+                                    |
|                       |                                             |
|          +------------+------------+                                |
|          |            |            |                                |
|  +-------+------+ +--+-------+ +--+--------+                       |
|  | PROMETHEUS    | | POSTGRES | | ALERTMANAGER |                    |
|  |  (:9090)      | | (:5433)  | | (:9093)      |                   |
|  | - Compliance  | | - Risks  | | - P1: Phone  |                   |
|  | - Exporters   | | - States | | - P2: SMS    |                   |
|  | - Grafana src | | - Attys  | | - P3: Email  |                   |
|  +---------------+ | - Audit  | | - P4: Digest  |                   |
|                    | - Tasks  | +---------------+                   |
|                    | + more   |                                     |
|                    +----------+                                     |
|                             |                                        |
|              +--------------+--------------+                        |
|              |              |              |                        |
|  +-----------+--+  +--------+---+  +------+--------+               |
|  | DATA          |  | EXTERNAL   |  | WHEELER BRAIN |               |
|  | COLLECTORS    |  | APIS       |  | OS (AI Audit) |               |
|  | (Python cron) |  | - State Bar|  | - Agent logs  |               |
|  | - Scrape      |  | - Reg Feed |  | - Decisions   |               |
|  | - Transform   |  | - LMS      |  +---------------+               |
|  | - Load        |  | - CMP      |                                  |
|  +---------------+  +-----------+                                   |
|                                                                     |
| +===================================================================+
| | DATA FLOW: Source -> Collector -> DB -> API -> Dashboard         | |
| | ALERT FLOW: DB/Prometheus -> Alertmanager -> Notification Channels| |
| +===================================================================+
```

## APPENDIX C: IMPLEMENTATION CHECKLIST (Phase 1)

```
Phase 1 Foundation (Weeks 1-2)
======================================================================
Week 1: Data Infrastructure
[ ] Create file: docker-compose.compliance.yml
[ ] Deploy: Compliance DB schema (12 tables)
[ ] Deploy: FastAPI service
[ ] Create file: compliance-data-collector.py (initial sources)
[ ] Deploy: Prometheus compliance exporter
[ ] Configure: Grafana datasource (Postgres + Prometheus)
[ ] Create: /root/legal-compliance-os/scripts/seed_data.sql
[ ] Create: /root/legal-compliance-os/api/main.py
[ ] Create: /root/legal-compliance-os/api/requirements.txt

Week 2: CEO Dashboard + P1 Alerts
[ ] Create: Grafana dashboard JSON (CEO Command Center)
[ ] Implement: Health Score materialized view
[ ] Configure: Alertmanager P1 routes
[ ] Configure: SMS/Phone notification channel
[ ] Test: P1 alert delivery
[ ] Create: API documentation
[ ] Deploy: Production version
[ ] Test: Dashboard load time (< 3s)
[ ] Sign-off: CEO dashboard review
```

---

**End of Phase 8: Compliance Dashboard Plan**

*Next Steps:*
1. Review with CLO and Compliance Director
2. Prioritize Phase 1 Foundation (Week 1-2)
3. Assign engineering resources for FastAPI + Grafana implementation
4. Begin data source onboarding (risk register, state matrix, contract data)
5. Schedule weekly compliance dashboard sync
