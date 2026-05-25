---
name: legal-compliance-os
description: Wheeler Legal/Compliance OS — full compliance orchestration: audit, risk scoring, remediation, verification across all 8 domains with 30-agent army. Target: 100/100 compliance readiness.
trigger: legal-compliance-os, compliance os, deploy compliance, legal os, compliance army
---

# Skill: /legal-compliance-os — Compliance OS Orchestration

Orchestrates the full Wheeler Legal/Compliance OS across 8 domains, 30 agents, and 10 business units. Audits compliance posture, identifies gaps, orchestrates remediation, and independently verifies results.

## Phase 1: Compliance Audit (Parallel Wave)

Launch all 8 domain audits simultaneously. Each agent returns a domain score + findings list.

### 1a. Risk Posture Audit
```
Agent(subagent_type="risk-scoring")
```
Returns: Overall risk score (0-100), top 10 risks, risk trend, Monte Carlo exposure estimate.
Reference: /root/legal-compliance-os/PRIORITY_RISK_MATRIX.md

### 1b. Regulatory Gap Analysis
```
Agent(subagent_type="compliance-mapping")
```
Returns: Gap inventory by regulatory domain, severity scores, remediation priorities.
Reference: /root/legal-compliance-os/COMPLIANCE_GAP_REPORT.md

### 1c. State-by-State Compliance
```
Agent(subagent_type="state-rules")
```
Returns: 50-state status (Tier 1/2/3 distribution), active restrictions, regulatory changes.
Reference: /root/legal-compliance-os/STATE_COMPLIANCE_MATRIX.md

### 1d. Data Privacy Posture
```
Agent(subagent_type="data-privacy")
```
Returns: Classification coverage, DSAR SLA, consent health, privacy control status.
Reference: /root/legal-compliance-os/DATA_PRIVACY_GOVERNANCE.md

### 1e. Outreach Compliance (TCPA/CAN-SPAM)
```
Agent(subagent_type="sms-email-compliance")
Agent(subagent_type="client-consent")
```
Returns: Consent health, DNC compliance, opt-out processing, active campaign audit.
Reference: /root/legal-compliance-os/OUTREACH_COMPLIANCE_FRAMEWORK.md

### 1f. Attorney Marketplace Compliance
```
Agent(subagent_type="marketplace-compliance")
Agent(subagent_type="attorney-network-compliance")
```
Returns: Rule 5.4 compliance, attorney standing, state coverage, fee structure audit.
Reference: /root/legal-compliance-os/ATTORNEY_MARKETPLACE_COMPLIANCE.md

### 1g. AI Governance
```
Agent(subagent_type="ai-governance")
```
Returns: AI risk tier compliance, human review gate status, prohibited action log.
Reference: /root/legal-compliance-os/AI_GOVERNANCE_POLICY.md

### 1h. Contract Governance
```
Agent(subagent_type="contract-automation")
```
Returns: Template status, contract lifecycle health, approval queue, expiration alerts.
Reference: /root/legal-compliance-os/CONTRACT_GOVERNANCE_SYSTEM.md

## Phase 2: Independent Verification

After all domain audits, launch the adversarial verifier:
```
Agent(subagent_type="no-false-greens-legal")
```
This agent independently challenges ALL compliance claims against actual evidence. Reports directly to CEO/Board.
Reference: /root/legal-compliance-os/WHEELER_LEGAL_COMPLIANCE_OS_REPORT.md

## Phase 3: Score Aggregation

Compute the Composite Compliance Score from domain scores:

```
COMPLIANCE SCORECARD [0-100]
├── TCPA/Outreach:     [  /20] — consent, DNC, opt-out
├── UPL Boundaries:    [  /20] — attorney review gates
├── State Compliance:  [  /15] — state-by-state coverage
├── Data Privacy:      [  /15] — controls, DSAR, consent
├── Attorney Market:   [  /10] — Rule 5.4, vetting
├── AI Governance:     [  /10] — risk tiers, human review
├── Contract Gov:      [  /5]  — templates, lifecycle
├── Audit Trail:       [  /5]  — completeness, immutability
TOTAL:                 [__/100]

Rating: 95-100 = A+ | 85-94 = A | 70-84 = B | <70 = CRITICAL
```

## Phase 4: Remediation (Sequential)

Sort findings by severity (Critical → High → Medium → Low). For each:

```
1. DIAGNOSE: Domain agent identifies root cause
2. REMEDIATE: Domain agent + relevant specialist agent implement fix
3. VERIFY: no-false-greens-legal agent independently verifies fix
4. DOCUMENT: audit-trail agent logs remediation evidence
```

### Critical Finding Remediation (P0 - 24h SLA)
- TCPA consent gap: sms-email-compliance BLOCKs outreach → client-consent verifies consent → no-false-greens-legal confirms
- UPL boundary crossed: ai-governance SHUT DOWNs AI → marketplace-compliance verifies attorney gates → no-false-greens-legal confirms
- Attorney Rule 5.4 violation: marketplace-compliance restructures fees → legal-ops coordinates outside counsel → no-false-greens-legal confirms

## Phase 5: Continuous Monitoring (ARMED)

Continuous compliance monitoring is active via CronCreate:

| Job | Cron | Action |
|-----|------|--------|
| Daily Compliance Audit | `17 7 * * *` | `/compliance-100` — full ecosystem audit |
| Daily TCPA Gate | `47 7 * * *` | `/tcp-gate` — consent enforcement verification |
| 6-Hour UPL Gate | `3 */6 * * *` | `/upl-gate` — AI legal content boundary check |
| Bi-Daily Attorney Check | `13 */12 * * *` | License standing + independent verification |
| Weekly State Scan | `23 9 * * 0` | `Agent(subagent_type='state-rules')` — 50-state regulatory change scan |

Health aggregator: `/root/scripts/compliance-health-aggregator.sh`
Health report: `/root/scripts/aiops-watchdog/compliance-health.json`

## Immediate Actions (5 Critical — Scored for Readiness)

### Action 1: Cease automated SMS outreach until TCPA compliance verified
- **Agent Owner**: sms-email-compliance
- **Verification**: client-consent verifies all PEWC records
- **Independent Audit**: no-false-greens-legal samples consent records
- **Readiness Gate**: 100% of active SMS recipients have valid PEWC

### Action 2: Cease AI-generated legal content without attorney review
- **Agent Owner**: ai-governance
- **Verification**: claims-workflow-compliance verifies 100% attorney review on existing docs
- **Independent Audit**: no-false-greens-legal attempts to bypass review gate
- **Readiness Gate**: 0 AI-generated legal documents without attorney review

### Action 3: Restructure attorney marketplace payments to comply with Rule 5.4
- **Agent Owner**: marketplace-compliance
- **Verification**: legal-ops coordinates outside counsel review
- **Independent Audit**: no-false-greens-legal audits fee structures
- **Readiness Gate**: All fee arrangements independently verified as Rule 5.4 compliant

### Action 4: Engage outside counsel (TCPA, ethics, UPL, privacy, securities)
- **Agent Owner**: legal-ops
- **Verification**: Engagement letters executed, matters opened, budgets set
- **Independent Audit**: no-false-greens-legal verifies engagement documentation
- **Readiness Gate**: Outside counsel engaged in all 5 domains with active matters

### Action 5: Pause FRG operations in Tier 3 states until attorney restructure
- **Agent Owner**: state-rules (monitoring) + surplus-funds-compliance (enforcement)
- **Verification**: claims-workflow-compliance verifies no Tier 3 claims processing
- **Independent Audit**: no-false-greens-legal verifies Tier 3 state activity freeze
- **Readiness Gate**: 0 active claims in CA, FL, LA, MA, NJ, NY without attorney-driven structure

## Success Condition

```
100/100 = Wheeler Legal/Compliance OS fully operational:
  ✅ All 30 agents deployed and monitoring
  ✅ 12 deliverables current and maintained
  ✅ 5 critical actions verified complete
  ✅ Zero false greens on compliance claims
  ✅ Compliance dashboard at target thresholds
  ✅ Independent verification confirms no critical findings
  ✅ Weekly compliance cadence operational
  ✅ Board-ready compliance reporting active
```

## Enforcement Gate Commands

Each critical action has a dedicated executable gate command:

| Command | Action | Enforcement |
|---------|--------|-------------|
| `/critical-5` | All 5 critical actions orchestrated | Master orchestration |
| `/tcp-gate` | TCPA consent verification | BLOCK outreach on fail |
| `/upl-gate` | UPL boundary enforcement | SHUT DOWN AI on fail |
| `/rule54-gate` | Rule 5.4 fee compliance | Freeze payments on fail |
| `/outside-counsel-gate` | Counsel engagement verification | Escalate on gap |
| `/tier3-gate` | Tier 3 state operations | Pause claims on violation |
| `/compliance-100` | Full 100/100 readiness audit | Score + remediate |
| `/tcp-check` | TCPA compliance audit | Advisory |
| `/upl-check` | UPL compliance audit | Advisory |

## Reference
- /root/legal-compliance-os/ — All 13 compliance deliverables (~900KB)
- /root/.claude/agents/legal-*.md — 30 agent definitions
- /root/.claude/commands/compliance.md — Quick reference commands (10 commands wired)
- /root/.claude/commands/critical-5.md — 5 critical action orchestration
- /root/.claude/commands/tcp-gate.md — TCPA enforcement gate
- /root/.claude/commands/upl-gate.md — UPL enforcement gate
- /root/.claude/commands/rule54-gate.md — Rule 5.4 compliance gate
- /root/.claude/commands/outside-counsel-gate.md — Counsel engagement gate
- /root/.claude/commands/tier3-gate.md — Tier 3 state operations gate
- /root/scripts/compliance-health-aggregator.sh — Health score aggregator
- /root/legal-compliance-os/WHEELER_LEGAL_COMPLIANCE_OS_REPORT.md — Master capstone
- /root/legal-compliance-os/COMPLIANCE_DASHBOARD_PLAN.md — Dashboard blueprint (v2.0)
