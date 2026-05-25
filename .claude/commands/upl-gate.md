---
trigger: /upl-gate
description: UPL enforcement gate — verify 0 AI-generated legal documents without attorney review. SHUT DOWN AI legal content if gate fails. Criminal exposure in most states.
---

# /upl-gate — Unauthorized Practice of Law Enforcement Gate

UPL is criminal in most states. AI-generated documents without attorney review = UPL risk. This gate MUST be closed before any AI system generates legal-adjacent content.

## Execution (Parallel Wave)

```
Agent(subagent_type="ai-governance")               # Primary: audit AI document pipeline
Agent(subagent_type="claims-workflow-compliance")   # Verify attorney review gate on all docs
Agent(subagent_type="marketplace-compliance")       # UPL boundary definitions by state
Agent(subagent_type="no-false-greens-legal")        # Adversarial: attempt to bypass review gate
```

## Verification Checklist

```
UPL ENFORCEMENT GATE CHECKLIST       [  ] PASS / [  ] FAIL

1. AI Document Inventory:
   ├── Total AI-generated docs:      [___]
   ├── With attorney review:         [___]  (must be 100%)
   ├── Without attorney review:      [___]  (must be 0)
   └── Review metadata complete:     [___]  (reviewer, timestamp, changes)

2. Review Gate Integrity:
   ├── Gate bypassable by non-lawyer:[  ] No (must be NO)
   ├── Attorney credentials verified:[  ] Yes
   ├── Review logged in audit trail: [  ] Yes
   └── Gate applies to ALL doc types:[  ] Yes

3. AI System Boundaries:
   ├── AI identified as AI:          [  ] Yes, always
   ├── AI provides legal advice:     [  ] No (must be NO)
   ├── AI signs/filed documents:     [  ] No (must be NO)
   └── Wheeler-as-law-firm language: [  ] None (must be NONE)

4. Document Types Covered:
   ├── Claim filings:                 [  ] Attorney-reviewed
   ├── Legal analysis:                [  ] Attorney-reviewed
   ├── Court correspondence:          [  ] Attorney-reviewed
   ├── Settlement offers:             [  ] Attorney-reviewed
   └── Attorney referral docs:        [  ] Attorney-reviewed

5. Marketing/Communications:
   ├── "Not a law firm" disclosure:  [  ] On all materials
   ├── No AI-as-attorney implication: [  ] Verified
   └── Attorney ad rules (ABA 7.1+): [  ] Compliant
```

## Gate Logic (ENFORCEMENT — SHUT DOWN authority)

```
ALL CHECKS PASS → GATE OPEN — AI systems may operate within defined boundaries
ANY CHECK FAILS → GATE CLOSED — ai-governance SHUT DOWNs AI legal content generation
                  until no-false-greens-legal confirms 0 bypass vectors
```

## Bright Lines (NEVER Cross — criminal exposure)

1. AI NEVER provides legal advice
2. AI NEVER signs or files legal documents
3. AI-generated documents ALWAYS have attorney review
4. Wheeler NEVER presents itself as a law firm
5. Claimants ALWAYS know they can choose their own attorney

Reference: /root/legal-compliance-os/AI_GOVERNANCE_POLICY.md
