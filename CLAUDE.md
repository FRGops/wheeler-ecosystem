# Wheeler Always-On Autonomous Agentic Coding OS

## AUTO-BOOTSTRAP

Every Claude Code session in this repository automatically boots the Wheeler AI Coding OS. The SessionStart hook invokes `.ai/session-launchers/auto-session-bootstrap.sh` which runs the preflight checklist.

## CORE RULES

### DeepSeek V4 Protection (IMMUTABLE)
- **NEVER** modify ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ANTHROPIC_MODEL, DEEPSEEK_API_KEY, or LITELLM_MASTER_KEY.
- **NEVER** edit ~/.zshrc, ~/.bashrc, ~/.profile, or ~/.bash_profile.
- **NEVER** read .env files or secrets/.
- If a task requires touching these: STOP and escalate to human.

### Task Classification (MANDATORY)
Every task MUST be classified before work begins:
- **Micro**: 1 file, < 20 lines
- **Small**: 1-3 files, < 100 lines
- **Medium**: 3-10 files, < 500 lines
- **Large**: 10-25 files, < 2000 lines
- **Critical**: Any size, production/security impact

### Agent Routing (MANDATORY)
Route intelligently based on `.ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md`:
- DeepSeek V4: bounded implementation, tests, small refactors
- DeepSeek Reasoner: complex debugging, architecture reasoning
- Claude Code: architecture, final boss review, high-stakes decisions
- OpenCode: parallel terminal builds, multi-worktree sessions
- Roo Code: IDE auto-approve workflows
- Human: production deploy, DB migrations, secrets, shell profiles, DeepSeek routing

### Preflight/Postflight (MANDATORY)
- **Preflight**: Run before significant work — verifies branch, env var presence, agent locks.
- **Postflight**: Run after work — verifies diff, dependency safety, DeepSeek protection, gates.

### Quality Gates
Every completion claim requires evidence:
- Tests passing? Show the output.
- Lint clean? Show the output.
- No secrets? Run pattern scan.
- DeepSeek untouched? Verify.
- Live endpoint? Show the curl result.

### No False Greens
- Never claim 100/100 unless ALL validations pass.
- Never say "live" unless you hit a live endpoint/UI.
- Never say "deployed" unless a deploy command/log proves it.
- Label unknowns as UNVERIFIED.

## FILE REFERENCES
- Index: `.ai/INDEX.md`
- Model routing: `.ai/model-routing/MODEL_ROUTING_DECISION_MATRIX.md`
- Agent deployment: `.ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md`
- Response contract: `.ai/prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md`
- Preflight: `.ai/autonomy/PREFLIGHT_CHECKLIST.md`
- Postflight: `.ai/autonomy/POSTFLIGHT_CHECKLIST.md`
- Runbooks: `.ai/runbooks/`
- Session launchers: `.ai/session-launchers/`

## RESPONSE CONTRACT
Every coding/build response must end with the 14-point contract defined in `.ai/prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md`.

## HUMAN APPROVAL GATES
These ALWAYS require human approval:
- Production deploy
- Database migrations
- Secrets management
- Shell profile modifications
- DeepSeek routing changes
- Auth/security/payment flow changes
- Major dependency upgrades
- Cloud infrastructure changes
- GitHub secrets

## BRANCH POLICY
- Never push directly to main/master.
- Create AI branches: `ai/feature-name-YYYYMMDD-HHMM`.
- Work in git worktrees for parallel tasks.
- Never force push to main/master.
