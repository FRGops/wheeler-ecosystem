---
trigger: /rule54-gate
description: ABA Rule 5.4 compliance gate — verify 0 fee-splitting violations in attorney marketplace. Restructure non-compliant arrangements. Zero tolerance.
---

# /rule54-gate — ABA Rule 5.4 Fee Structure Compliance Gate

ABA Model Rule 5.4 prohibits sharing legal fees with non-lawyers and restricts non-lawyer ownership/influence over attorney professional judgment. Violation risks attorney disbarment + Wheeler liability for aiding unauthorized practice.

## Execution (Parallel Wave)

```
Agent(subagent_type="marketplace-compliance")        # Primary: audit all fee structures
Agent(subagent_type="attorney-network-compliance")   # Verify attorney independence
Agent(subagent_type="legal-ops")                     # Coordinate outside ethics counsel review
Agent(subagent_type="no-false-greens-legal")         # Independent fee structure audit
```

## Verification Checklist

```
RULE 5.4 COMPLIANCE GATE             [  ] PASS / [  ] FAIL

1. Fee Structure Audit:
   ├── Total attorney relationships: [___]
   ├── Fee arrangements audited:     [___]  (must be 100%)
   ├── Non-compliant arrangements:   [___]  (must be 0)
   └── Outside counsel reviewed:     [___]  (must be 100%)

2. Prohibited Structures (ANY = FAIL):
   ├── Wheeler shares in legal fees:          [  ] None
   ├── Non-lawyer directs attorney judgment:  [  ] None
   ├── Non-lawyer owns law firm interest:     [  ] None
   ├── Fee tied to case outcome (non-attorney):[  ] None
   └── Referral fee as % of recovery:         [  ] None

3. Permitted Structures Verified:
   ├── Flat referral/marketing fees:          [  ] Market-rate, fixed
   ├── SaaS/platform subscription fees:       [  ] Separated from legal fees
   ├── Attorney independent judgment:         [  ] Contractually protected
   └── Client consent to structure:           [  ] Documented

4. State-Specific Rule 5.4 Variants:
   ├── CA: No non-lawyer ownership           [  ] Compliant
   ├── FL: Strict fee split prohibition       [  ] Compliant
   ├── NY: Referral fee restrictions          [  ] Compliant
   ├── NJ: Categorical fee split ban          [  ] Compliant
   └── DC: Limited non-lawyer ownership OK    [  ] Compliant (if applicable)

5. Attorney Independence:
   ├── Attorneys free to reject cases:        [  ] Yes
   ├── Attorneys control legal strategy:      [  ] Yes
   ├── No Wheeler influence on settlements:   [  ] Yes
   └── Malpractice insurance maintained:      [  ] Yes
```

## Business Model Options (Attorney-reviewed)

| Model | Description | Rule 5.4 Risk |
|-------|-------------|---------------|
| A | SaaS platform fee only | Low |
| B | Fixed marketing fee per lead | Low-Med |
| C | Admin service fee (non-legal) | Medium |
| D | % of recovery (direct) | PROHIBITED |
| E | Non-lawyer ownership of law firm | PROHIBITED |
| F | Revenue share with law firm | PROHIBITED (most states) |

## Gate Logic

```
ALL CHECKS PASS → GATE OPEN — fee structures verified compliant
ANY CHECK FAILS → GATE CLOSED — affected attorney relationships frozen
                  until outside ethics counsel confirms compliant restructure
```

Reference: /root/legal-compliance-os/ATTORNEY_MARKETPLACE_COMPLIANCE.md
