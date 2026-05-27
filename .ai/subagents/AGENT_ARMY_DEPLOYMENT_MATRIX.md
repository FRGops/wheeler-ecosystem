# Agent Army Deployment Matrix v2.2 — Always-On

## Army Always-On Enforcement (v2.2 — NON-NEGOTIABLE)

**Every prompt deploys agents. No exceptions. No opt-out. No suppression.**

| Enforcement Rule | Detail |
|-----------------|--------|
| Minimum agents per prompt | 2 (NEVER less) |
| Agent tool call | REQUIRED on every response |
| Skipping agents | POLICY VIOLATION — escalate |
| No-build prompts | Deploy Explore + general-purpose for situational awareness |
| Suppression gate | REMOVED (was only blocker) |
| Non-compliance | 3-strike escalation → chief-of-staff → human

## Autonomous Pipeline Integration

This matrix works with `.ai/subagents/BUILD_PIPELINE.md`. Every build task flows through the pipeline phases, and each phase auto-deploys agents based on the rules below. The UserPromptSubmit intelligence hook classifies tasks and arms the pipeline automatically.

## Task Size → Pipeline + Agent Count

| Task Size | Files | Lines | Phases | Max Parallel Agents | Review Level |
|-----------|-------|-------|--------|-------------------|-------------|
| Micro | 1 | < 20 | 2 (IMPLEMENT→REVIEW+SECURITY) | 2 (MINIMUM) | Self |
| Small | 1-3 | < 100 | 4 (PLAN→IMPLEMENT→TEST→REVIEW+SECURITY) | 2 | Peer |
| Medium | 3-10 | < 500 | 6 (DISCOVER→PLAN→IMPLEMENT→TEST→REVIEW+SEC→VERIFY+FINAL) | 4 | Final Boss |
| Large | 10-25 | < 2000 | 7 (full pipeline) | 6 | Final Boss + Human |
| Critical | Any | Any | Full + human gates | As needed | Final Boss + Human |

**v2.1 Phase Merge**: REVIEW+SECURITY run in single parallel dispatch. VERIFY+FINAL BOSS run in single parallel dispatch. 9 phases → 7.

## Phase → Agent Deployment Map

### DISCOVER Phase (Medium+)

| Agent | Role | Parallel |
|-------|------|----------|
| Explore × 2-3 | Read-only codebase search from different angles | Yes |
| code-modernization:legacy-analyst | Structural/behavioral understanding (legacy systems) | Yes |
| code-modernization:business-rules-extractor | Domain logic extraction (business systems) | Yes |

### PLAN Phase (Small+)

| Agent | Role | Parallel |
|-------|------|----------|
| Plan | Architecture design, step-by-step plan | — |
| code-modernization:architecture-critic | Adversarial review — flags over-engineering, missed requirements | After Plan |
| AskUserQuestion | Clarify ambiguities | Conditional |

### ARCHITECT Phase (Large+)

| Agent | Role | Parallel |
|-------|------|----------|
| feature-dev:code-architect | Detailed component/API/schema design | — |
| feature-dev:code-explorer | Deep architecture mapping | Yes |
| pr-review-toolkit:type-design-analyzer | Type design review | Yes |

### IMPLEMENT Phase (Always)

| Task Type | Primary Agent | Secondary Agent | Max Files/Agent |
|-----------|--------------|----------------|-----------------|
| **Backend API** | general-purpose | general-purpose (parallel module) | 5 |
| **Frontend UI** | general-purpose | general-purpose (parallel component) | 5 |
| **Database** | general-purpose | wheeler-db-agent | 5 |
| **DevOps** | general-purpose | docker-expert | 5 |
| **Multi-service** | general-purpose × 2-3 (parallel by service) | — | 5 per service |
| **Bug Fix (simple)** | general-purpose | — | 3 |
| **Bug Fix (complex)** | general-purpose | Explore (root cause) | 5 |
| **Refactor** | general-purpose | Explore (impact analysis) | 5 |
| **Documentation** | general-purpose | — | 3 |

**Implementation Rules:**
- One agent per independent file/module — never overlap file ownership
- Each agent gets explicit file boundaries: "edit files X, Y, Z only"
- Agents must not exceed change budget
- If an agent hits a blocker, it escalates — no silent failures
- Sequential agents when outputs depend on each other
- Parallel agents when tasks are truly independent

### TEST Phase (Always)

| Agent | Scope | When |
|-------|-------|------|
| code-modernization:test-engineer | Unit + integration tests | Small+ |
| general-purpose | E2E/curl tests for endpoints | API changes |
| general-purpose | Playwright/browser tests | UI changes |
| Manual verification | Run test command, verify output | Always |

**Minimum Test Requirements:**
- Micro: Existing tests pass + manual run of changed code
- Small: Unit test for new/changed function
- Medium: Unit + integration tests
- Large: Unit + integration + E2E smoke test
- Critical: Full test suite + manual review + regression suite

### REVIEW Phase (Always)

| Agent | Focus | When | Parallel |
|-------|-------|------|----------|
| `Code Reviewer` | Correctness, security, maintainability, performance | Always | Yes |
| `code-simplifier` | Clarity, consistency, simplification | Always | Yes |
| `pr-review-toolkit:silent-failure-hunter` | Error handling, catch blocks, fallbacks | Medium+ | Yes |
| `pr-review-toolkit:type-design-analyzer` | Type design quality | Types changed | Yes |
| `pr-review-toolkit:comment-analyzer` | Comment accuracy, rot detection | Comments added | Yes |

**All REVIEW agents deploy in parallel** — single message, multiple Agent() calls. Each reports independently. Findings are aggregated and auto-fixed before proceeding.

### REVIEW+SECURITY Phase (Always — merged, all parallel)

| Agent | Focus | When | Parallel |
|-------|-------|------|----------|
| `Code Reviewer` | Correctness, security, maintainability, performance | Always | Yes |
| `code-simplifier` | Clarity, consistency, simplification | Always | Yes |
| `pr-review-toolkit:silent-failure-hunter` | Error handling, catch blocks, fallbacks | Medium+ | Yes |
| `pr-review-toolkit:type-design-analyzer` | Type design quality | Types changed | Yes |
| `pr-review-toolkit:comment-analyzer` | Comment accuracy, rot detection | Comments added | Yes |
| `code-modernization:security-auditor` | OWASP, CWE, CVEs, injection, secrets | Always | Yes |
| Automated secrets scan | `git diff \| grep -E 'API_KEY\|TOKEN\|SECRET\|PASSWORD'` | Always | Yes |
| DeepSeek routing check | Verify ANTHROPIC_* vars untouched | Always | Yes |

**All 8 agents deploy in parallel** — single message, multiple Agent() calls. Zero data dependency between review and security (both inspect same diff).

### VERIFY+FINAL BOSS Phase (Medium+ — merged, all parallel)

| Agent | Focus | Parallel |
|-------|-------|----------|
| `devops-smoke-tester` | Build verification, deployment checks, Docker health | Yes |
| `production-readiness-agent` | Health checks, security, monitoring, backups | Yes |
| `zero-false-green-auditor` | Independent verification of ALL claims | Yes |
| `ecosystem-health-scoring` | Health score computation (service changes) | Yes |
| `Code Reviewer` (FINAL BOSS) | Final comprehensive sweep + scorecard | Yes |

**All 5 agents deploy in parallel** — single message. FINAL BOSS reviews code, VERIFY agents test it. No dependency.

## Model Tier Routing (v2.1 — speed-optimized)

| Agent Type | Model | Rationale |
|-----------|-------|-----------|
| DISCOVER (Explore) | deepseek-chat | Read-only, speed-critical |
| IMPLEMENT (general-purpose) | deepseek-chat | Bulk of coding, need speed |
| TEST (test-engineer) | deepseek-chat | Fast model for test gen |
| REVIEW (code-simplifier, silent-failure, type-design, comment) | deepseek-chat | Simple analysis tasks |
| REVIEW (Code Reviewer) | premium_review | Quality-critical review |
| SECURITY (security-auditor) | premium_review | Quality-critical security |
| VERIFY (smoke-tester, readiness, eco-health) | deepseek-chat | Simple verification |
| VERIFY (zero-false-green) | premium_review | Independent audit needs quality |
| FINAL BOSS | claude-opus-4 | Ultimate quality gate |

## Army Mode Triggers — ALWAYS ON (v2.2)

Army mode is **always active**. Every prompt deploys agents. The trigger list below now defines escalation (when to go ABOVE the minimum):

Deploy 4+ agents (above minimum) when:
- Multi-file feature implementation (3+ files)
- Cross-cutting concern (auth, logging, error handling)
- Database migration + API + frontend changes
- Security audit + remediation
- Production incident response
- Major version upgrade
- New service/module creation

## Solo Mode — DISABLED (v2.2)

Solo mode (1 agent) is **FORBIDDEN**. Minimum 2 agents on EVERY prompt, even micro tasks. If the task is genuinely trivial (typo, comment, lint), deploy 1 Explore agent for context awareness + 1 general-purpose agent for the fix. Never deploy fewer than 2 agents.

## Agent Selection Priority

1. **Task-specific agent first**: Backend API → backend patterns, Frontend → frontend patterns
2. **Fallback to general-purpose**: If no specific agent fits, general-purpose handles it
3. **Research before implementation**: Explore agent first, then implement based on findings
4. **Never delegate understanding**: Provide file paths, line numbers, specific instructions

## Cost & Performance Awareness

- Micro/Small tasks: 1 agent, minimal overhead
- Medium tasks: 2-4 agents across phases, sequential where possible
- Large tasks: 4-6 agents, parallel where independent
- Cancel idle agents promptly
- Don't over-deploy — 2 agents editing 2 files beats 5 agents on a 3-file task

## Anti-Patterns (BLOCKED)

- **0-1 agents for ANY prompt — BLOCKED by army always-on enforcement (v2.2)**
- 5 agents for a 20-line change — blocked by size detection
- 2 agents editing the same file — blocked by parallel coordination
- Agents without clear boundaries — blocked by pre-deployment check
- Agents running unbounded — blocked by change budget enforcement
- Skipping Final Boss on medium+ tasks — blocked by pipeline gate
- Deploying agents and walking away without reviewing ALL outputs
- Responding to user without deploying agents first — POLICY VIOLATION

## Agent Coordination

All multi-agent builds route through `agent-coordination` agent to prevent duplicate work, track activity, and ensure complete coverage. The coordination agent knows which agents are running and what they're working on.

## New Agent Roles (Autonomous Pipeline)

These agent types are now eligible for pipeline deployment:

| Agent | Phase | Tool Access |
|-------|-------|------------|
| agent-coordination | All phases | All tools |
| Explore | DISCOVER | Read, Glob, Grep, Bash |
| Plan | PLAN | All except Edit/Write |
| general-purpose | IMPLEMENT, TEST | All tools |
| Code Reviewer | REVIEW, FINAL BOSS | All tools |
| code-simplifier | REVIEW | All tools |
| silent-failure-hunter | REVIEW | All tools |
| type-design-analyzer | ARCHITECT, REVIEW | All tools |
| security-auditor | SECURITY | Read, Glob, Grep, Bash |
| devops-smoke-tester | VERIFY | All tools |
| production-readiness-agent | VERIFY | All tools |
| zero-false-green-auditor | VERIFY | All tools |
| ecosystem-health-scoring | VERIFY | All tools |
