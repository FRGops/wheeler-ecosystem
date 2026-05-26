# Postflight Checklist

Run after every AI coding session before considering work complete.

## Required Checks

### 1. Git Status
- [ ] `git diff --stat` reviewed
- [ ] No accidental file changes
- [ ] No secrets in diff (presence check only)

### 2. Dependency Risk
- [ ] New dependencies reviewed (if any)
- [ ] No unauthorized package changes

### 3. Quality Gates
- [ ] All applicable gates run
- [ ] Gate results documented

### 4. Reports
- [ ] Session report created in `.ai/reports/sessions/`
- [ ] Agent activity log updated

### 5. Scorecard
- [ ] Readiness score calculated
- [ ] Failures documented
- [ ] Unverified items labeled as UNVERIFIED

### 6. DeepSeek Protection
- [ ] DeepSeek routing: UNTOUCHED
- [ ] No shell profiles modified
- [ ] No production .env read

### 7. Response Contract
- [ ] Response contract completed (14-point format)

## Postflight Script
Run: `bash .ai/session-launchers/postflight-ai-session.sh`

## Red Flags
Escalate immediately if:
- Secrets detected in diff
- DeepSeek routing modified
- Production config changed without approval
- Database migration run without approval
- Files deployed to production without approval
