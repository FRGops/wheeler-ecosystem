---
trigger: /tcp-check
description: TCPA compliance audit — verify consent, DNC scrub, opt-out processing, reassigned number checks. Critical: TCPA class actions have no statutory damage cap.
---

# /tcp-check — TCPA Compliance Verification

Audit SMS/phone outreach compliance. TCPA statutory damages: $500-$1,500 PER VIOLATION. Class actions can reach $500M+.

## Execution

### Step 1: Consent Audit
Verify that every phone number in active outreach has valid Prior Express Written Consent (PEWC):
- Consent record exists and is complete (18 metadata fields)
- Consent tier matches outreach type (Tier 4 for SMS marketing)
- Consent not expired (Tier 4-5: refresh every 6 months)
- Consent language matches what was actually agreed to

### Step 2: DNC Compliance
- National DNC Registry: last scrub date (must be <31 days)
- Internal DNC: verify all opt-outs processed
- State DNC lists: coverage check for active states
- Reassigned number database: last check date

### Step 3: Active Campaign Audit
- Every active SMS campaign: consent verified, DNC scrubbed, content approved
- Opt-out mechanism: present and functional in every message
- Time zone compliance: messages sent between 8am-9pm local
- Sender identification: clearly identifies Wheeler

### Step 4: Risk Assessment
- Total active SMS recipients without verified PEWC: _____ (target: 0)
- Opt-out processing SLA compliance: _____ (target: <1 minute)
- State mini-TCPA exposure: FL, OK, WA checked

### Agent Dispatch
```
Agent(subagent_type="sms-email-compliance")  # Primary TCPA audit
Agent(subagent_type="client-consent")        # Consent verification
Agent(subagent_type="risk-scoring")          # TCPA risk quantification
Agent(subagent_type="no-false-greens-legal") # Independent verification
```

## Target: 100/100 = Zero TCPA Exposure
