# AGENTS.md — Rules for All Coding Agents

This file applies to ALL coding agents operating in this repository: Claude Code, DeepSeek V4, Aider, OpenCode, Roo Code, and any future tools.

## UNIVERSAL RULES

### 1. Follow Repo Rules
Read and follow `CLAUDE.md` before any coding work. All agent-agnostic rules apply to you.

### 2. Use Model Routing Matrix
Route yourself to the right task type. Reference `.ai/model-routing/MODEL_ROUTING_DECISION_MATRIX.md`:
- If you're DeepSeek V4: handle bounded implementation tasks. Escalate architecture decisions.
- If you're Claude Code: handle architecture, reviews, and governance. Don't waste tokens on repetitive edits.
- If you're OpenCode: handle parallel terminal work.
- If you're Roo Code: handle IDE-automated workflows.

### 3. Follow Subagent Templates
When operating as a specific agent role, follow the template in `.ai/subagents/`. Each template defines: allowed actions, forbidden actions, quality gates, report format, escalation conditions.

### 4. Obey Change Budget
| Task Size | Max Files | Max Lines | Max Agents |
|-----------|-----------|-----------|------------|
| Micro | 1 | 20 | 1 |
| Small | 3 | 100 | 1 |
| Medium | 10 | 500 | 3 |
| Large | 25 | 2000 | 5 |
| Critical | Any | Any | As needed |

Never exceed the budget without escalation.

### 5. Use Quality Gates
Run available quality gates before claiming completion. Minimum:
- Code compiles/builds
- Tests pass
- Lint clean
- No secrets in diff
- DeepSeek routing untouched

### 6. Report Using Response Contract
Every task completion must follow the 14-point response contract in `.ai/prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md`.

### 7. Never Fake 100/100
- Don't claim success without evidence.
- Don't hide failures.
- Don't round up scores.
- Label unverified items as UNVERIFIED.

## DEEPSEEK V4 PROTECTION (ALL AGENTS)
- **NEVER** modify: ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ANTHROPIC_MODEL, DEEPSEEK_API_KEY, LITELLM_MASTER_KEY.
- **NEVER** read: .env files, secrets/.
- **NEVER** edit: ~/.zshrc, ~/.bashrc, ~/.profile.
- If a task requires any of these: STOP and escalate.

## HUMAN APPROVAL GATES (ALL AGENTS)
Stop and request human approval for:
- Production deploys
- Database migrations
- Secrets management
- Shell profile changes
- DeepSeek routing changes
- Auth/security/payment changes
- Major dependency upgrades
- Cloud infrastructure changes

## USEFUL PATHS
- Index: `.ai/INDEX.md`
- Model routing: `.ai/model-routing/`
- Agent templates: `.ai/subagents/`
- Quality gates: `.ai/quality-gates/`
- Runbooks: `.ai/runbooks/`
- Session launchers: `.ai/session-launchers/`
- Response contract: `.ai/prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md`
