# /no-false-greens — Zero False Green Policy Enforcement

Enforce the Zero False Green policy: never claim success without evidence. Every verification must include actual command output, exit codes, and timestamps.

## Execution

### Audit Current Claims
Check recent changes and verify:
1. Were all claimed verifications actually run?
2. Did exit codes match claims?
3. Were assumptions separated from facts?

### Verification Requirements

Every claim of success MUST include:
```
Command:  <exact command that was run>
Exit:     <exit code>
Output:   <relevant output snippet>
Time:     <timestamp>
Evidence: [CONFIRMED / ASSUMED / UNABLE TO VERIFY]
```

### Self-Audit Checklist

Before reporting task complete:
```
□ I ran the verification command (not just thought about it)
□ The exit code was 0
□ I can see the output confirming success
□ I've checked for errors/warnings in the output
□ I'm not assuming side effects worked
□ I've tested the golden path
□ I've checked for regressions
□ I can state what SPECIFICALLY proves this works
```

### Blocked Claims

These phrases trigger a false-green audit:
- "Should work" — verify it does
- "Tests pass" — show the test output
- "Looks good" — what specific evidence?
- "No errors" — did you check ALL logs?
- "Fixed" — show the before/after

### Verification Evidence Template

```
TASK: <description>
──────────────────────────────────────
VERIFICATION:
  Command: <cmd>
  Exit code: <0 or non-zero>
  Output: <key lines>
  Evidence quality: [CONFIRMED / INFERRED / NONE]
──────────────────────────────────────
STATUS: [VERIFIED / UNVERIFIED — <reason> / BLOCKED — <reason>]
```

## Output Format

```
╔══════════════════════════════════════════════╗
║   Zero False Green Audit — <timestamp>       ║
╚══════════════════════════════════════════════╝

RECENT CLAIMS AUDITED: <N>
  Confirmed:  <N>
  Assumed:    <N> [NEEDS VERIFICATION]
  False:      <N> [NEEDS CORRECTION]

──────────────────────────────────────────────
VIOLATIONS:
  <list any unverified claims with task context>

──────────────────────────────────────────────
POLICY STATUS: [COMPLIANT / <N> VIOLATIONS]
```
