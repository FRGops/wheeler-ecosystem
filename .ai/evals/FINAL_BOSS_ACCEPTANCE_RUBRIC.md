# Final Boss Acceptance Rubric

## Purpose
The ultimate quality gate. Every significant change must pass this review before merge.

## Verdict Options

| Verdict | Meaning |
|---------|---------|
| APPROVED | All gates pass, safe to merge |
| CHANGES REQUESTED | Issues found, not blocking but must fix |
| BLOCKED | Critical issue, do not merge |

## Gate Checklist

### Gate 1: Build & Compile (pass/fail)
- [ ] Project builds without errors
- [ ] No TypeScript/type errors
- [ ] No missing imports

### Gate 2: Tests (pass/fail)
- [ ] All existing tests pass
- [ ] New tests added for new behavior
- [ ] No skipped tests without reason
- [ ] Coverage acceptable

### Gate 3: Lint & Format (pass/fail)
- [ ] Linter clean
- [ ] Formatter applied
- [ ] No console.log/debugger left in

### Gate 4: Security (pass/fail)
- [ ] No secrets in diff
- [ ] No .env files in diff
- [ ] No secrets/ in diff
- [ ] Input validation on new endpoints
- [ ] Auth checks on protected routes

### Gate 5: DeepSeek Protection (pass/fail)
- [ ] Model routing configs untouched
- [ ] No shell profile changes
- [ ] Env vars unchanged

### Gate 6: Production Safety (pass/fail)
- [ ] No production config changes (without approval)
- [ ] No unauthorized migration
- [ ] No deployment scripts triggered

### Gate 7: Documentation (pass/fail)
- [ ] New endpoints documented
- [ ] Breaking changes noted
- [ ] README updated if needed

### Gate 8: Response Contract (pass/fail)
- [ ] All 14 fields completed
- [ ] No unverified claims
- [ ] No false "100/100"

## Automatic Blockers
Any of these = BLOCKED immediately:
- Security finding (secret, injection, auth bypass)
- DeepSeek routing modified
- Production config changed without approval
- Test suite broken
- .env or secrets/ in diff

## Confidence Levels
- **High**: Reviewed every file, ran tests, verified behavior
- **Medium**: Reviewed key files, tests pass, some trust in agent
- **Low**: Cursory review, limited verification — CHANGES REQUESTED
