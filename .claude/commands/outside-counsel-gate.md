---
trigger: /outside-counsel-gate
description: Outside counsel engagement gate — verify licensed counsel engaged across all 5 critical domains (TCPA, ethics, UPL, privacy, securities). No domain uncovered.
---

# /outside-counsel-gate — Outside Counsel Engagement Gate

Wheeler operates across 50 states in highly regulated domains. Operating without qualified outside counsel in critical areas = negligent risk management. This gate verifies coverage across all 5 required domains.

## Execution (Parallel Wave)

```
Agent(subagent_type="legal-ops")               # Primary: counsel engagement coordination
Agent(subagent_type="vendor-risk")              # Verify law firm credentials + conflicts
Agent(subagent_type="no-false-greens-legal")    # Verify engagement documentation exists
```

## Required Coverage Matrix

```
OUTSIDE COUNSEL COVERAGE             [  ] 5/5   [  ] 4/5   [  ] <4/5 ⚠

Domain 1: TCPA / Telemarketing Compliance
├── Firm:        [________________]
├── Lead Partner: [________________]
├── Engagement:  [  ] Executed  [  ] Pending  [  ] Not started
├── Budget:      $[__________]/year
├── Scope:       Class action defense, PEWC compliance, DNC, state mini-TCPA
└── Status:      [  ] Active  [  ] Sourcing  [  ] Gap ⚠

Domain 2: Legal Ethics / Professional Responsibility
├── Firm:        [________________]
├── Lead Partner: [________________]
├── Engagement:  [  ] Executed  [  ] Pending  [  ] Not started
├── Budget:      $[__________]/year
├── Scope:       Rule 5.4, Rule 5.5 (UPL), advertising rules, fee structures
└── Status:      [  ] Active  [  ] Sourcing  [  ] Gap ⚠

Domain 3: UPL / State-by-State Practice Rules
├── Firm:        [________________]
├── Lead Partner: [________________]
├── Engagement:  [  ] Executed  [  ] Pending  [  ] Not started
├── Budget:      $[__________]/year
├── Scope:       50-state UPL analysis, attorney marketplace structure, AI boundaries
└── Status:      [  ] Active  [  ] Sourcing  [  ] Gap ⚠

Domain 4: Data Privacy / Cybersecurity
├── Firm:        [________________]
├── Lead Partner: [________________]
├── Engagement:  [  ] Executed  [  ] Pending  [  ] Not started
├── Budget:      $[__________]/year
├── Scope:       18 state privacy laws, GDPR, breach response, DSAR, vendor DPA
└── Status:      [  ] Active  [  ] Sourcing  [  ] Gap ⚠

Domain 5: Securities / Capital Raise
├── Firm:        [________________]
├── Lead Partner: [________________]
├── Engagement:  [  ] Executed  [  ] Pending  [  ] Not started
├── Budget:      $[__________]/year
├── Scope:       Reg D, Reg CF, investor disclosures, Blue Sky, SAFE/convertible notes
└── Status:      [  ] Active  [  ] Sourcing  [  ] Gap ⚠
```

## Engagement Verification (per domain)

```
For each domain:
├── Engagement letter executed:       [  ] Yes
├── Scope of work defined:            [  ] Yes
├── Matter number assigned:           [  ] Yes
├── Budget approved:                  [  ] Yes
├── Conflict check completed:         [  ] Yes
├── Primary contact assigned:         [  ] Yes
├── Communication cadence set:        [  ] Yes
└── Privilege protocol established:   [  ] Yes
```

## Gate Logic

```
5/5 DOMAINS COVERED + ENGAGEMENTS EXECUTED → GATE OPEN
ANY DOMAIN UNCOVERED → GATE CLOSED — cannot claim adequate legal coverage
                       legal-ops escalates to CEO + Board
```

## Attorney-Client Privilege Protocol

All outside counsel communications must:
1. Use dedicated privileged communication channels
2. Include "ATTORNEY-CLIENT PRIVILEGED" header
3. Be segregated from business records
4. Follow outside counsel's privilege preservation procedures
