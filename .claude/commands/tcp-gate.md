---
trigger: /tcp-gate
description: TCPA consent gate — verify 100% of active SMS recipients have valid PEWC. BLOCK outreach if gate fails. Zero tolerance.
---

# /tcp-gate — TCPA Consent Enforcement Gate

Verify every active SMS/voice outreach has valid prior express written consent (PEWC). This is the single highest financial exposure risk — TCPA statutory damages have no cap.

## Execution (Parallel Wave)

```
Agent(subagent_type="sms-email-compliance")    # Primary: audit all active consent records
Agent(subagent_type="client-consent")           # Verify consent tier, expiration, revocation status
Agent(subagent_type="no-false-greens-legal")    # Adversarial: sample and challenge consent claims
```

## Verification Checklist

```
TCPA CONSENT GATE CHECKLIST         [  ] PASS / [  ] FAIL

1. Active SMS Recipients:           [___]
   ├── With valid PEWC:             [___]  (must be 100%)
   ├── With expired consent:        [___]  (must be 0)
   ├── With revoked consent:        [___]  (must be 0)
   └── Missing consent record:      [___]  (must be 0)

2. Consent Tier Verification:
   ├── Tier 4+ (SMS) has PEWC:      [  ] 100% verified
   ├── Tier 5 (Voice AI) has PEWC:  [  ] 100% verified
   └── Lower tiers not receiving
       Tier 4/5 channels:           [  ] Verified

3. DNC Compliance:
   ├── National DNC scrub active:   [  ] Yes
   ├── Internal DNC sync active:    [  ] Yes
   └── Reassigned number check:     [  ] Yes

4. Opt-Out Processing:
   ├── Opt-out → suppression <60s:  [  ] Yes
   ├── All-channel suppression:     [  ] Yes
   └── Opt-out audit trail:         [  ] Complete

5. Consent Documentation:
   ├── Timestamp recorded:          [  ] Yes
   ├── Scope captured:              [  ] Yes
   ├── IP/capture method logged:    [  ] Yes
   └── Ready for litigation hold:   [  ] Yes
```

## Gate Logic (ENFORCEMENT — BLOCK authority)

```
ALL CHECKS PASS → GATE OPEN — outreach permitted
ANY CHECK FAILS → GATE CLOSED — sms-email-compliance BLOCKs all outreach
                  until independent verification confirms 100% compliance
```

## Automation

```bash
# Daily consent audit (runs via cron at 07:00)
# Agent: sms-email-compliance
# Verify: client-consent cross-references all active records
# Escalate: Any gap → P0 alert → CEO, CLO, CISO
```

Reference: /root/legal-compliance-os/OUTREACH_COMPLIANCE_FRAMEWORK.md
