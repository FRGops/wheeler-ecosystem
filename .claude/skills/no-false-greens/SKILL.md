---
name: no-false-greens
description: "Zero False Green policy: verification must include actual command output, exit codes, timestamps. Never claim success without evidence. Separate facts from assumptions. Pattern for self-auditing."
trigger: no false green, zero false green, verify, false green, evidence, prove it, verification check, audit claims
---

# Skill: Zero False Green Policy

Never claim a task is complete without verifiable evidence. This skill provides the enforcement pattern.

## Verification Evidence Standard

Every claim of completion must include:
```
TASK: <what was done>
──────────────────────────────────────
VERIFICATION:
  Command:  <exact command run>
  Exit:     <0 or non-zero>
  Output:   <key lines from output>
  Time:     <timestamp>
  Evidence: [CONFIRMED — output shown / ASSUMED — verified indirectly / UNABLE — state reason]
──────────────────────────────────────
STATUS: [VERIFIED / UNVERIFIED — reason / BLOCKED — reason]
```

## Self-Audit Questions

Before reporting "done," ask:
1. Did I actually run the verification command? (not just think about it)
2. Did the exit code match what I claim?
3. Can I show the output that proves success?
4. Am I assuming side effects worked without checking?
5. Did I test the golden path? Edge cases?
6. Did I check for regressions?

## Blocked Phrases

These trigger a false-green audit — replace with evidence:
| Instead of | Show |
|-----------|------|
| "Should work" | Exit code and output |
| "Tests pass" | Test runner output |
| "Looks good" | What specifically? |
| "No errors" | Log grep showing no errors |
| "Fixed" | Before/after comparison |
| "Done" | Verification evidence |

## Evidence Quality Levels

| Level | Criteria | Example |
|-------|----------|---------|
| **CONFIRMED** | Command run, exit 0, output shown | `curl -s http://localhost/health → {"status":"ok"}` |
| **INFERRED** | Evidence from indirect source | "PM2 shows online, implies service started" |
| **ASSUMED** | No evidence, reasoning only | "The config looks correct" |
| **NONE** | No verification attempted | — |

## Integration

Use with `/no-false-greens` slash command for automated audit of recent claims.
Use with `zero-false-green-auditor` agent for adversarial review.

## Output Format

```
ZERO FALSE GREEN AUDIT:
──────────────────────────────────────
TASK: <description>
  Evidence Level: [CONFIRMED / INFERRED / ASSUMED / NONE]
  Command: <cmd>
  Exit: <code>
  Verified: [YES / PARTIAL / NO]

──────────────────────────────────────
POLICY COMPLIANCE: [COMPLIANT / <N> VIOLATIONS]
```
