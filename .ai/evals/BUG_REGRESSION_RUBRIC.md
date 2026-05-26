# Bug Regression Rubric

## Purpose
Ensure bug fixes actually fix the bug and don't introduce regressions.

## Score Ranges

| Score | Rating | Description |
|-------|--------|-------------|
| 90-100 | Verified Fix | Bug reproduced, fix verified, regression tests pass |
| 70-89 | Likely Fix | Fix looks correct, couldn't reproduce original bug |
| 50-69 | Uncertain | Fix seems reasonable but unverified |
| < 50 | Insufficient | Fix is guesswork, needs investigation |

## Required Evidence

### For Score 90+:
1. Bug reproduced before fix (evidence: error log, screenshot, test failure)
2. Root cause identified (not just symptom)
3. Fix applied to root cause
4. Bug no longer reproducible after fix
5. Regression test added that fails without the fix
6. Related code paths reviewed for same pattern

### For Score 70-89:
1. Bug described clearly
2. Fix is logical and targeted
3. Tests pass
4. No obvious regression

### Below 70:
- Cannot reproduce bug
- Fix is speculative
- Multiple possible root causes
- Fix touches many unrelated files

## Automatic Checks
- Test suite passes
- No new linter errors
- Fix doesn't break existing functionality

## What Blocks 100/100
- Cannot reproduce the original bug
- Fix addresses symptom but not root cause
- No regression test
- Related code paths not checked for same bug pattern
