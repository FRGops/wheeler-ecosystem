# Wheeler AI Coding OS — Commands Cheatsheet

## Session Management
```bash
# Start a safe AI session (creates branch, runs preflight)
bash .ai/session-launchers/start-next-safe-ai-session.sh

# Start a named mission
bash .ai/session-launchers/start-ai-mission.sh "my-feature"

# Run preflight checks only
bash .ai/session-launchers/preflight-ai-session.sh

# Run postflight checks only
bash .ai/session-launchers/postflight-ai-session.sh

# Summarize all sessions
bash .ai/session-launchers/summarize-ai-sessions.sh
```

## Quality Gates
```bash
# Full agentic OS validation
bash .ai/quality-gates/final-agentic-os-validation.sh

# All gates must pass for 100/100
bash .ai/quality-gates/run-local-gates.sh

# No-false-green verification
bash .ai/quality-gates/no-false-green-check.sh

# Always-on policy check
bash .ai/quality-gates/always-on-policy-check.sh
```

## Git Safety
```bash
# Create AI branch (never work on main)
git checkout -b ai/feature-name-$(date +%Y%m%d-%H%M)

# Create isolated worktree for parallel work
git worktree add /tmp/wheeler-task -b ai/task-name

# Remove worktree when done
git worktree remove /tmp/wheeler-task
```

## DeepSeek Protection
```bash
# Verify DeepSeek routing is intact (presence only)
for var in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL DEEPSEEK_API_KEY LITELLM_MASTER_KEY; do
  [ -n "${!var+x}" ] && echo "$var=present" || echo "$var=MISSING"
done
```

## Hooks Management
```bash
# Disable hooks temporarily
export CLAUDE_CODE_DISABLE_HOOKS=1

# Disable hooks by moving scripts
mv .claude/hooks .claude/hooks.disabled

# Re-enable hooks
mv .claude/hooks.disabled .claude/hooks
```

## Rollback
```bash
# Revert last commit (safe — creates revert commit)
git revert HEAD

# Restore CLAUDE.md from backup
cp CLAUDE.md.backup-* CLAUDE.md

# Discard unstaged changes
git checkout .
```

## Model Routing Reference
| Task | Use |
|------|-----|
| Bounded implementation | DeepSeek V4 / Aider |
| Complex debugging | DeepSeek Reasoner |
| Architecture, review | Claude Code |
| Parallel terminals | OpenCode |
| IDE automation | Roo Code |
| Production, secrets, auth | HUMAN REQUIRED |

## Task Size Budget
| Size | Files | Lines | Agents |
|------|-------|-------|--------|
| Micro | 1 | < 20 | 1 |
| Small | 1-3 | < 100 | 1 |
| Medium | 3-10 | < 500 | 3 |
| Large | 10-25 | < 2000 | 5 |
| Critical | Any | Any | As needed |
