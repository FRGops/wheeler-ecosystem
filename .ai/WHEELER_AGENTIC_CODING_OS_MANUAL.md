# Wheeler Always-On Autonomous Agentic Coding OS — Manual

## What This Is

The Wheeler AI Coding OS is a governance and automation layer that wraps every AI coding session in this repository. It ensures:
- DeepSeek V4 routing is protected and never accidentally modified
- Every task is classified and routed to the right agent/model
- Preflight/postflight checks run automatically
- Quality gates prevent false greens
- Human approval is required for dangerous operations
- Every session produces verifiable evidence

## How It Activates

### Automatic (via Hooks)
When Claude Code starts in this repo:
1. SessionStart hook fires → runs `auto-session-bootstrap.sh`
2. Bootstrap verifies critical files exist
3. Preflight checks DeepSeek presence, branch safety, agent locks
4. Session is ready for classified, routed work

### Manual
```bash
# Start a new AI session
bash .ai/session-launchers/start-next-safe-ai-session.sh

# Start a complex mission
bash .ai/session-launchers/start-ai-mission.sh "feature-name"

# Run preflight only
bash .ai/session-launchers/preflight-ai-session.sh

# Run postflight only
bash .ai/session-launchers/postflight-ai-session.sh
```

## Daily Workflow

1. **Session starts** → auto-bootstrap verifies OS health
2. **Task received** → classify (micro/small/medium/large/critical)
3. **Route** → pick agent(s) using deployment matrix
4. **Execute** → within change budget, on AI branch
5. **Verify** → run quality gates
6. **Postflight** → verify DeepSeek untouched, no secrets, no production changes
7. **Report** → complete 14-point response contract

## Key Files

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Boot instructions for Claude Code |
| `AGENTS.md` | Rules for all coding agents |
| `.ai/INDEX.md` | Master index of all OS files |
| `.ai/model-routing/` | Which model for which task |
| `.ai/subagents/` | Agent role templates |
| `.ai/quality-gates/` | Validation scripts |
| `.ai/runbooks/` | Recovery procedures |
| `.ai/session-launchers/` | Session management scripts |
| `.ai/prompts/` | Reusable prompt templates |

## Safety Guarantees

1. **DeepSeek V4 is never touched** — preflight and postflight both verify
2. **Secrets are never printed** — only presence/missing status
3. **Production is never deployed** — without explicit human approval
4. **Shell profiles are never modified** — blocked by PreToolUse hook
5. **Main is never force-pushed** — blocked by hooks and policy

## Emergency

If something goes wrong:
1. `.ai/runbooks/ROLLBACK_RUNBOOK.md` — how to undo
2. `.ai/runbooks/AI_SESSION_RECOVERY_RUNBOOK.md` — session gone wrong
3. `.ai/runbooks/BROKEN_DEEPSEEK_ROUTING_DO_NOT_TOUCH_RUNBOOK.md` — routing issues
