# AGENTS.md — Rules for All Coding Agents

This file applies to ALL coding agents operating in this repository: Claude Code, DeepSeek V4, Aider, OpenCode, Roo Code, and any future tools.

## UNIVERSAL RULES

### 1. Follow Repo Rules
Read and follow `CLAUDE.md` before any coding work. All agent-agnostic rules apply to you.

### 2. Know Your Phase
The Autonomous Build Pipeline (`.ai/subagents/BUILD_PIPELINE.md`) defines 7 phases. Every agent operates within a specific phase. Know which phase you're in and what's expected:
- **DISCOVER**: Read-only research — do not write code
- **PLAN**: Design only — do not implement
- **ARCHITECT**: Detailed design — types, schemas, contracts
- **IMPLEMENT**: Write code — bounded, precise, complete
- **TEST**: Write and run tests — verify correctness
- **REVIEW**: Find issues — report, don't silently fix
- **SECURITY**: Audit — report vulnerabilities, verify secrets clean
- **VERIFY**: End-to-end checks — build, deploy, health
- **FINAL BOSS**: Comprehensive sweep — final scorecard

### 3. Follow Phase Handoff Protocol
When you complete a phase, output a handoff summary:
```
## Phase Handoff: [YOUR_PHASE] → [NEXT_PHASE]
### What was done
### Key decisions
### Files changed
### Known issues / Caveats
### Unresolved
```

### 4. Obey Change Budget
| Task Size | Max Files | Max Lines | Max Agents |
|-----------|-----------|-----------|------------|
| Micro | 1 | 20 | 1 |
| Small | 3 | 100 | 2 |
| Medium | 10 | 500 | 4 |
| Large | 25 | 2000 | 6 |
| Critical | Any | Any | As needed |

Never exceed the budget without escalation.

### 5. Never Overlap File Ownership
Two agents must never edit the same file in the same phase. Check which files your peer agents own before writing.

### 6. Use Quality Gates
Run available quality gates before claiming completion. Minimum:
- Code compiles/builds
- Tests pass (show output)
- Lint clean (show output)
- No secrets in diff
- DeepSeek routing untouched

### 7. Report Using Response Contract
Every task completion must follow the 14-point response contract in `.ai/prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md`.

### 8. Never Fake 100/100
- Don't claim success without evidence
- Don't hide failures
- Don't round up scores
- Label unverified items as UNVERIFIED
- Zero-false-green-auditor will catch you

### 9. Auto-Deploy Rules
- You are auto-deployed by the UserPromptSubmit intelligence hook
- You receive task context from the previous phase's handoff
- You know your phase, budget, and boundaries
- Report back when done — the pipeline auto-proceeds

### 10. Escalation Rules
Escalate (pause pipeline) when:
- You encounter a blocker you cannot resolve
- A task requires touching DeepSeek routing
- A task requires reading .env files or secrets/
- A task requires shell profile modification
- You need human approval for a gated action
- A dependency blocks your work

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

## PIPELINE PHASE REFERENCE

### Phase: DISCOVER
- **You are**: Explore agent or legacy-analyst
- **Your job**: Find all relevant files, map dependencies, identify risks
- **Do NOT**: Write or modify code
- **Output**: List of affected files, dependency graph, risk areas

### Phase: PLAN
- **You are**: Plan agent or code-architect
- **Your job**: Design the implementation approach
- **Do NOT**: Write implementation code
- **Output**: Step-by-step plan, file list, test strategy

### Phase: IMPLEMENT
- **You are**: general-purpose agent
- **Your job**: Write the code as designed
- **Boundaries**: Only your assigned files, within budget
- **Output**: Working, tested code

### Phase: TEST
- **You are**: test-engineer or general-purpose
- **Your job**: Write tests, run them, verify coverage
- **Output**: Test results with evidence

### Phase: REVIEW
- **You are**: Code Reviewer, code-simplifier, silent-failure-hunter, etc.
- **Your job**: Find issues, report them clearly
- **Do NOT**: Rewrite code (findings are auto-fixed after review)
- **Output**: Categorized findings (critical/high/medium/low)

### Phase: SECURITY
- **You are**: security-auditor
- **Your job**: Find vulnerabilities, verify secrets clean, check DeepSeek routing
- **Output**: Security report, remediation steps

### Phase: VERIFY
- **You are**: devops-smoke-tester, production-readiness-agent, zero-false-green-auditor
- **Your job**: Build, deploy check, health check, verify ALL claims
- **Output**: Verification report with evidence

## USEFUL PATHS
- Index: `.ai/INDEX.md`
- Build Pipeline: `.ai/subagents/BUILD_PIPELINE.md`
- Agent Deployment: `.ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md`
- Model routing: `.ai/model-routing/`
- Quality gates: `.ai/quality-gates/`
- Runbooks: `.ai/runbooks/`
- Session launchers: `.ai/session-launchers/`
- Response contract: `.ai/prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md`
- Agent coordination: agent-coordination agent (prevents duplicate work)
