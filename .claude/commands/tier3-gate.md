---
trigger: /tier3-gate
description: Tier 3 state operations gate — verify 0 active FRG claims in CA, FL, LA, MA, NJ, NY without attorney-driven structure. Pause operations if gate fails.
---

# /tier3-gate — Tier 3 State Operations Gate

Tier 3 states (CA, FL, LA, MA, NJ, NY) have heightened regulatory requirements for surplus funds recovery — including restrictions on finder's fees, attorney involvement mandates, and aggressive UPL enforcement. Operating without attorney-driven structure in these states creates existential regulatory risk.

## Execution (Parallel Wave)

```
Agent(subagent_type="state-rules")                 # Primary: Tier 3 regulatory audit
Agent(subagent_type="surplus-funds-compliance")    # Active claims audit in Tier 3
Agent(subagent_type="claims-workflow-compliance")  # Verify attorney structure per claim
Agent(subagent_type="no-false-greens-legal")       # Independent Tier 3 activity verification
```

## Tier 3 State Definitions

| State | Key Restriction | Required Structure |
|-------|----------------|-------------------|
| CA | Finder's fee prohibition, strict UPL | Attorney of record required |
| FL | Strict UPL, no non-attorney filings | Attorney of record required |
| LA | Civil law jurisdiction, unique rules | LA-licensed attorney required |
| MA | Aggressive AG enforcement | Attorney-driven model |
| NJ | Categorical fee split ban | Attorney of record required |
| NY | Strict referral fee limits | NY-licensed attorney required |

## Verification Checklist

```
TIER 3 STATE OPERATIONS GATE         [  ] PASS / [  ] FAIL

State: CALIFORNIA
├── Active claims:                   [___]  (target: 0 without attorney structure)
├── Attorney of record per claim:    [  ] 100%  [  ] Partial  [  ] None ⚠
├── Fee structure CA-compliant:      [  ] Yes  [  ] No ⚠
├── Marketing within CA rules:       [  ] Yes  [  ] No ⚠
└── Status:                          [  ] CLEAR  [  ] PAUSED  [  ] VIOLATING ⚠

State: FLORIDA
├── Active claims:                   [___]  (target: 0 without attorney structure)
├── Attorney of record per claim:    [  ] 100%  [  ] Partial  [  ] None ⚠
├── Fee structure FL-compliant:      [  ] Yes  [  ] No ⚠
├── Marketing within FL rules:       [  ] Yes  [  ] No ⚠
└── Status:                          [  ] CLEAR  [  ] PAUSED  [  ] VIOLATING ⚠

State: LOUISIANA
├── Active claims:                   [___]  (target: 0 without attorney structure)
├── LA-licensed attorney per claim:  [  ] 100%  [  ] Partial  [  ] None ⚠
├── Civil law compliance verified:   [  ] Yes  [  ] No ⚠
├── Marketing within LA rules:       [  ] Yes  [  ] No ⚠
└── Status:                          [  ] CLEAR  [  ] PAUSED  [  ] VIOLATING ⚠

State: MASSACHUSETTS
├── Active claims:                   [___]  (target: 0 without attorney structure)
├── Attorney of record per claim:    [  ] 100%  [  ] Partial  [  ] None ⚠
├── AG enforcement history reviewed: [  ] Yes  [  ] No
├── Marketing within MA rules:       [  ] Yes  [  ] No ⚠
└── Status:                          [  ] CLEAR  [  ] PAUSED  [  ] VIOLATING ⚠

State: NEW JERSEY
├── Active claims:                   [___]  (target: 0 without attorney structure)
├── Attorney of record per claim:    [  ] 100%  [  ] Partial  [  ] None ⚠
├── Fee split structure NJ-compliant:[  ] Yes  [  ] No ⚠
├── Marketing within NJ rules:       [  ] Yes  [  ] No ⚠
└── Status:                          [  ] CLEAR  [  ] PAUSED  [  ] VIOLATING ⚠

State: NEW YORK
├── Active claims:                   [___]  (target: 0 without attorney structure)
├── NY-licensed attorney per claim:  [  ] 100%  [  ] Partial  [  ] None ⚠
├── Referral fee NY-compliant:       [  ] Yes  [  ] No ⚠
├── Marketing within NY rules:       [  ] Yes  [  ] No ⚠
└── Status:                          [  ] CLEAR  [  ] PAUSED  [  ] VIOLATING ⚠
```

## Gate Logic (ENFORCEMENT)

```
ALL 6 STATES CLEAR → GATE OPEN — Tier 3 operations may proceed with attorney structure
ANY STATE VIOLATING → GATE CLOSED — surplus-funds-compliance + state-rules PAUSE all
                      active claims in that state. Claims workflow blocked until
                      attorney-driven structure verified by no-false-greens-legal.

ALL 6 STATES PAUSED/VIOLATING → Catastrophic — escalate to CEO, CLO, Board.
                                All FRG operations frozen until outside counsel
                                provides state-specific restructure plan.
```

## Restart Conditions (per state)

Before resuming operations in any Tier 3 state:
1. Outside counsel engaged for that specific state
2. Attorney-driven structure designed + reviewed by ethics counsel
3. Fee structure verified as state-compliant
4. State-specific marketing/outreach rules documented
5. Attorney of record identified for active claims
6. no-false-greens-legal independently verifies all 5 conditions

Reference: /root/legal-compliance-os/STATE_COMPLIANCE_MATRIX.md
