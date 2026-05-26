# Preflight Checklist

Run before every AI coding session.

## Required Checks

### 1. Branch Safety
- [ ] Current branch: `_______` (not `main`/`master` unless hotfix-approved)
- [ ] Working tree: clean / dirty (document if dirty)

### 2. DeepSeek Protection
- [ ] `DEEPSEEK_API_KEY`: present / missing
- [ ] `ANTHROPIC_BASE_URL`: present / missing
- [ ] `ANTHROPIC_AUTH_TOKEN`: present / missing
- [ ] No shell profiles will be modified

### 3. Required Files
- [ ] `.ai/INDEX.md` exists
- [ ] `.ai/model-routing/MODEL_ROUTING_DECISION_MATRIX.md` exists
- [ ] `.ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md` exists

### 4. Agent Locks
- [ ] No stale agent locks found
- [ ] Check `.ai/agent-locks/` for orphaned locks

### 5. Package Manager
- [ ] Node: `node -v`
- [ ] Package manager identified: npm / pnpm / yarn / bun

### 6. Available Gates
- [ ] `.ai/quality-gates/` exists
- [ ] At least one quality gate script available

### 7. Session Tracking
- [ ] Session report directory exists: `.ai/reports/sessions/`
- [ ] Session ID recorded: `_______________`

## Preflight Script
Run: `bash .ai/session-launchers/preflight-ai-session.sh`

## Blockers
Stop and escalate if:
- On `main`/`master` branch without explicit approval
- `DEEPSEEK_API_KEY` is missing
- Agent lock detected for the same scope
- Working tree has uncommitted production config changes
