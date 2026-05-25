---
trigger: /compliance
description: Legal/Compliance OS Command Center — invoke the 30-agent compliance army: audit, verify, remediate. Covers TCPA, UPL, privacy, contracts, outreach, attorney marketplace, AI governance.
---

# /compliance — Legal/Compliance OS Command

Deploy the Wheeler Legal/Compliance OS agent army. 30 specialized agents across 8 squads covering all 10 business units.

## Enforcement Gates (5 Critical Actions)

```
/critical-5           — Execute ALL 5 critical actions with verification
/tcp-gate             — TCPA consent enforcement gate (BLOCK authority)
/upl-gate             — UPL enforcement gate (SHUT DOWN authority)
/rule54-gate          — ABA Rule 5.4 fee structure compliance gate
/outside-counsel-gate — Outside counsel engagement verification gate
/tier3-gate           — Tier 3 state operations pause gate
```

## Audit & Assessment Commands

```
/compliance-100       — Target: 100/100 compliance readiness (full audit + remediation)
/tcp-check            — TCPA compliance audit workflow
/upl-check            — UPL compliance audit with bright lines
```

## Quick Dispatch

```
/compliance audit      — Full compliance audit (all 8 domains, 8 agents parallel)
/compliance risk       — Risk posture assessment + top 20 risks
/compliance state      — 50-state compliance matrix check
/compliance privacy    — Data privacy compliance audit
/compliance outreach   — Outreach (TCPA/CAN-SPAM) compliance check
/compliance attorneys  — Attorney marketplace compliance
/compliance ai         — AI governance compliance
/compliance contracts  — Contract governance status
/compliance dashboard  — Compliance KPI dashboard
/compliance wire       — Wire a specific compliance control
/compliance falsegreen — Hunt for false green compliance claims
```

## Continuous Monitoring (Cron — Armed)

| Job | Frequency | Action |
|-----|-----------|--------|
| Daily Compliance Audit | 07:17 | `/compliance-100` full ecosystem audit |
| Daily TCPA Gate Check | 07:47 | `/tcp-gate` consent enforcement verification |
| 6-Hour UPL Gate Check | Every 6h | `/upl-gate` AI legal content boundary enforcement |
| Bi-Daily Attorney Check | Every 12h | License standing + independent verification |
| Weekly State Scan | Sunday 09:23 | 50-state regulatory change detection |

## Agent Army Structure

| Squad | Agents | Domain |
|-------|--------|--------|
| Squad 1 (5) | legal-ops, compliance-mapping, state-rules, surplus-funds-compliance, risk-scoring | Legal Risk & Compliance |
| Squad 2 (5) | contract-automation, document-review, saas-terms, privacy-policy, api-terms | Contract & Document |
| Squad 3 (4) | data-privacy, data-licensing, cybersecurity-compliance, records-retention | Data & Privacy |
| Squad 4 (3) | marketing-compliance, sms-email-compliance, client-consent | Outreach & Marketing |
| Squad 5 (3) | attorney-network-compliance, claims-workflow-compliance, marketplace-compliance | Attorney Marketplace |
| Squad 6 (5) | ai-governance, audit-trail, vendor-risk, fraud-prevention, kyc-identity | Governance & Oversight |
| Squad 7 (3) | securities-compliance, real-estate-compliance, government-contracting-compliance | Specialized |
| Squad 8 (2) | dispute-management, no-false-greens-legal | Quality Assurance |

## Execution

For audit tasks, dispatch agents in parallel using the superpowers pattern. For remediation, chain sequentially (audit → fix → verify).

### Audit Flow
```
Agent(subagent_type="risk-scoring")            # Risk posture
Agent(subagent_type="compliance-mapping")      # Gap analysis
Agent(subagent_type="state-rules")             # State compliance
Agent(subagent_type="data-privacy")            # Privacy status
Agent(subagent_type="sms-email-compliance")    # Outreach status
Agent(subagent_type="marketplace-compliance")  # Marketplace status
Agent(subagent_type="ai-governance")           # AI governance status
Agent(subagent_type="no-false-greens-legal")   # Independent verification
```

### Remediation Flow
```
AUDIT FINDING → risk-scoring (prioritize) → domain agent (fix) → no-false-greens-legal (verify)
```

## Critical Safety Model

| Agent | Authority | Scope |
|-------|-----------|-------|
| sms-email-compliance | BLOCK | Halt all outreach if TCPA gap detected |
| ai-governance | SHUT DOWN | Stop AI legal content if UPL boundary crossed |
| no-false-greens-legal | ADVERSARIAL | Report directly to CEO, not CLO |
| marketplace-compliance | ENFORCEMENT | Freeze attorney payments if Rule 5.4 violated |
| state-rules | ENFORCEMENT | Pause Tier 3 state operations |

## Reference
- /root/legal-compliance-os/ — All 13 compliance deliverables
- /root/.claude/agents/legal-*.md — 30 agent definitions
- /root/.claude/commands/critical-5.md — 5 critical action orchestration
- /root/.claude/skills/legal-compliance-os/SKILL.md — Full orchestration skill
- /root/legal-compliance-os/WHEELER_LEGAL_COMPLIANCE_OS_REPORT.md — Master capstone
- /root/legal-compliance-os/COMPLIANCE_DASHBOARD_PLAN.md — Dashboard blueprint
