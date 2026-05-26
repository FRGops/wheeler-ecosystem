# Wheeler Always-On Autonomous Agentic Coding OS — Manual

## Current State: 100/100 A+ (2026-05-26)

**Multi-tool routing**: Fully operational.
- **Claude Code** (2.1.150): active — architecture, reviews, governance
- **DeepSeek V4**: active (via proxy) — primary implementer
- **Aider** (0.86.2): active — bounded implementation, refactoring
- **OpenCode**: install script available — `bash .ai/session-launchers/install-multi-tool-routing.sh`
- **Roo Code**: IDE-side — configured in routing matrix

**Hooks**: Wired and active in `.claude/settings.json` — SessionStart, PreToolUse, PostToolUse, Stop.

## What This Is

The Wheeler AI Coding OS is a governance and automation layer that wraps every AI coding session in this repository. It ensures:
- DeepSeek V4 routing is protected and never accidentally modified
- Every task is classified and routed to the right agent/model
- Preflight/postflight checks run automatically
- Quality gates prevent false greens
- Human approval is required for dangerous operations
- Every session produces verifiable evidence

## How It Activates

### Fully Automatic (Zero Manual Steps)

The Wheeler AI Coding OS boots itself. You open Claude Code in this repo (or any Wheeler ecosystem repo with this config), and it just works:

1. **SessionStart hook fires** → orchestrator health check + Wheeler OS auto-bootstrap
2. **Auto-bootstrap** verifies: CLAUDE.md, AGENTS.md, .ai/INDEX.md, DeepSeek policy, hooks
3. **Preflight runs** → branch safety, DeepSeek env presence, agent locks, available gates
4. **Session is live** → task classification and agent routing are ready

**No commands. No setup. No remembering.** The OS is always on.

### Emergency Manual Override (only if hooks are broken)

If hooks are somehow disabled, you can manually invoke:
```bash
bash .ai/session-launchers/preflight-ai-session.sh   # verify environment
bash .ai/session-launchers/postflight-ai-session.sh   # verify after work
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
