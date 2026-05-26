# AI Output Eval Rubric

## Purpose
Evaluate the quality of AI-generated code and responses. Used by the Final Boss Reviewer and for continuous improvement.

## Score Ranges

| Score | Rating | Description |
|-------|--------|-------------|
| 90-100 | Excellent | Correct, secure, well-tested, follows all conventions |
| 75-89 | Good | Correct but minor issues (naming, missing edge case) |
| 60-74 | Adequate | Works but needs refactoring or has gaps |
| 40-59 | Poor | Partially works, significant issues |
| < 40 | Unacceptable | Incorrect, insecure, or broken |

## Evaluation Dimensions

### 1. Correctness (30 points)
- Does the code do what was requested?
- Are edge cases handled?
- Is error handling appropriate?

### 2. Security (25 points)
- No hardcoded secrets
- Input validation present
- No injection vectors (SQL, XSS, command)
- Auth checks in place

### 3. Code Quality (20 points)
- Readable and maintainable
- Follows project conventions
- Appropriate abstractions (not over/under-engineered)
- No dead code

### 4. Testing (15 points)
- Tests exist for new behavior
- Tests cover edge cases
- Tests are meaningful (not just coverage padding)

### 5. Documentation (10 points)
- Complex logic explained
- API contracts documented
- No redundant comments

## Automatic Checks
- Linter: pass/fail
- Type checker: pass/fail
- Test suite: pass/fail
- Secret scan: clean/warning

## Manual Checks
- Architecture review
- Security review
- UX review (if UI)
- Performance review (if applicable)

## What Blocks 100/100
- Any security finding
- Failing test
- Linter error
- Missing error handling on critical path
- Hardcoded values that should be configurable
- Unverified claim in response

## Escalation Triggers
- Security vulnerability found → escalate to human
- Architecture concern → escalate to Final Boss
- Production config touched → escalate to human
