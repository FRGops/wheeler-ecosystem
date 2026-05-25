---
trigger: /critical-5
description: Execute all 5 immediate critical compliance actions — TCPA gate, UPL gate, Rule 5.4 restructure, outside counsel engagement, Tier 3 state pause. Zero tolerance for incomplete verification.
---

# /critical-5 — 5 Critical Immediate Actions

Execute, verify, and independently audit all 5 Wheeler Legal/Compliance OS immediate critical actions.
Target: 100/100 readiness on all 5 actions.

## Execution Flow

### Parallel Wave 1: Dispatch All 5 Action Owners

```
Agent(subagent_type="sms-email-compliance")     # Action 1: TCPA consent gate
Agent(subagent_type="ai-governance")            # Action 2: AI legal content gate
Agent(subagent_type="marketplace-compliance")   # Action 3: Rule 5.4 fee restructure
Agent(subagent_type="legal-ops")                # Action 4: Outside counsel coordination
Agent(subagent_type="state-rules")              # Action 5: Tier 3 state pause
```

### Wave 2: Domain Verification (Parallel — one verifier per action)

```
Agent(subagent_type="client-consent")            # Verify Action 1: All PEWC records valid
Agent(subagent_type="claims-workflow-compliance") # Verify Action 2: 0 AI docs without review
Agent(subagent_type="attorney-network-compliance") # Verify Action 3: Fee structures compliant
Agent(subagent_type="no-false-greens-legal")     # Verify Action 4: Engagement docs exist
Agent(subagent_type="surplus-funds-compliance")  # Verify Action 5: 0 Tier 3 active claims
```

### Wave 3: Independent Adversarial Audit

```
Agent(subagent_type="no-false-greens-legal")  # Challenge ALL claims. Report to CEO.
Agent(subagent_type="risk-scoring")            # Re-score residual risk
Agent(subagent_type="audit-trail")             # Log complete verification trail
```

## Readiness Scorecard

```
CRITICAL ACTION READINESS [100/100 Required]

Action 1: TCPA Consent Gate
├── Active SMS recipients with valid PEWC: [___/___] ___%
├── DNC scrubbing operational:          [  ] Yes [  ] No
├── Opt-out processing SLA:             [  ] <1min [  ] >1min
├── Reassigned number checking active:  [  ] Yes [  ] No
└── Score: [__/20]

Action 2: UPL Gate (AI Legal Content)
├── AI docs with attorney review gate:  [___/___] ___%
├── Review gate bypassable:             [  ] Yes [  ] No ⚠
├── AI presented as legal services:     [  ] Yes [  ] No ⚠
├── Wheeler-as-law-firm disclaimers:    [  ] Present [  ] Missing ⚠
└── Score: [__/20]

Action 3: Rule 5.4 Fee Structure
├── Fee arrangements audited:           [___/___] ___%
├── Attorney independence preserved:    [  ] Yes [  ] No ⚠
├── Non-attorney profit sharing:        [  ] None [  ] Detected ⚠
├── Fee disclosure to clients:          [  ] Complete [  ] Missing
└── Score: [__/20]

Action 4: Outside Counsel Engagement
├── TCPA counsel engaged:               [  ] Yes [  ] No
├── Ethics counsel engaged:             [  ] Yes [  ] No
├── UPL counsel engaged:                [  ] Yes [  ] No
├── Privacy counsel engaged:            [  ] Yes [  ] No
├── Securities counsel engaged:         [  ] Yes [  ] No
└── Score: [__/20]

Action 5: Tier 3 State Pause
├── CA active claims:                   [___] (target: 0)
├── FL active claims:                   [___] (target: 0)
├── LA active claims:                   [___] (target: 0)
├── MA active claims:                   [___] (target: 0)
├── NJ active claims:                   [___] (target: 0)
├── NY active claims:                   [___] (target: 0)
└── Score: [__/20]

TOTAL: [___/100]
```

## Gate Logic

- **100/100**: All 5 actions verified complete → CLEAR for scaled operations
- **80-99**: Critical gaps remain → DO NOT scale; remediate gaps
- **<80**: Catastrophic exposure → SHUT DOWN affected operations

## Independent Verification Required

The `no-false-greens-legal` agent reports directly to CEO, not CLO.
Every claim must be verified against direct evidence.
Zero tolerance for false greens.
