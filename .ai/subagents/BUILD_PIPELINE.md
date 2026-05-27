# Autonomous Build Pipeline — Wheeler Coding OS v2.2

## Auto-Approve Lock (v2.2 — NON-NEGOTIABLE)

**All tools auto-approve. All phases auto-proceed. No human waits. No ExitPlanMode. No AskUserQuestion.**

The pipeline is fully autonomous. The model must never call EnterPlanMode, ExitPlanMode, or AskUserQuestion. Build directly, deploy agents directly, and auto-progress through all phases without pausing for human confirmation.

## Overview

Every build task flows through a 7-phase autonomous pipeline. Each phase has designated agents, quality gates, and handoff protocols. The pipeline auto-progresses through phases — you can walk away and the build continues to 100% completion.

```
PROMPT → [INTELLIGENCE] → DISCOVER → PLAN → ARCHITECT → IMPLEMENT → TEST → REVIEW+SECURITY → VERIFY+FINAL BOSS → DONE
```

**7 phases (was 9)** — REVIEW and SECURITY run in parallel (zero data dependency). VERIFY and FINAL BOSS run in parallel (FINAL BOSS reviews code, VERIFY tests it). This eliminates two serial phase gates, saving 3-6 minutes per build.

## Dynamic Agent Pool (AUTO-DISCOVERY)

Agent selection is **keyword-based, not hardcoded**. The UserPromptSubmit intelligence hook detects capability domains from the prompt, and the model maps those domains to available agents. **New agents auto-participate** — add a new security agent, and it automatically matches security-related prompts.

### How It Works
1. Intelligence hook scans prompt for domain keywords (`.ai/capabilities/DYNAMIC_CAPABILITY_MATCHER.md`)
2. Matched domains are injected as context: "Deploy agents from: security, backend-api, database"
3. Model resolves domain recommendations to actual available agents
4. New agents matching domain keywords → auto-recommended. Zero manual config.

### Adding a New Agent (zero config needed)
- Agent name/description contains domain keywords → auto-matches
- Example: new `network-security-scanner` agent contains "security" → automatically deployed for security tasks
- No files to edit. No registry to update. It just works.

### Adding a New Domain (one line)
- Add a `"domain:keyword1|keyword2"` entry to the domain list in `userprompt-intelligence.sh`
- New domain is instantly active

## Phase 0: INTELLIGENCE (Auto-Detection)

Fires on every UserPromptSubmit. Classifies the task and determines pipeline routing.

### Classification Rules

| Signal | Classification |
|--------|---------------|
| "fix"/"bug"/"broken"/"crash" | Bug Fix |
| "add"/"create"/"build"/"implement"/"new" | Feature |
| "refactor"/"clean up"/"simplify"/"reorganize" | Refactor |
| "optimize"/"faster"/"slow"/"performance" | Optimization |
| "investigate"/"explore"/"understand"/"what" | Investigation |
| "deploy"/"release"/"ship"/"production" | Deploy |

### Size Detection

| Signals | Size | Pipeline Depth | Max Agents |
|---------|------|---------------|------------|
| 1 file, < 20 lines, single action | Micro | IMPLEMENT → REVIEW | 1 |
| 1-3 files, < 100 lines | Small | PLAN → IMPLEMENT → REVIEW | 2 |
| 3-10 files, < 500 lines | Medium | DISCOVER → PLAN → IMPLEMENT → TEST → REVIEW | 4 |
| 10-25 files, < 2000 lines | Large | Full pipeline (all 7 phases) | 6 |
| Production/security impact | Critical | Full pipeline + human gates | As needed |

### Tech Stack Auto-Detection

| Signal | Pipeline Adjustment |
|--------|-------------------|
| .tsx/.ts/.jsx/.js | TypeScript/React agents |
| .py | Python/pytest agents |
| Dockerfile/docker-compose | Docker-expert agent |
| prisma/schema | Database agent |
| .tf/terraform | DevOps Safety agent |
| nginx/ssl | Security Secrets agent |

### Routing Decision

Based on classification, the intelligence layer outputs:
- `PIPELINE_DEPTH`: which phases are needed
- `PRIMARY_AGENTS`: agent types for implementation
- `REVIEW_LEVEL`: Self / Peer / Final Boss / Final Boss + Human
- `AUTO_APPROVE`: whether phases auto-progress without human intervention
- `ARMY_MODE`: true/false (parallel agents)

## Phase 1: DISCOVER

**Goal**: Understand the codebase context before touching anything.

### When to run
- Medium+ tasks (3+ files affected)
- Unfamiliar codebase areas
- Multi-service changes

### Agents deployed
- **Primary**: `Explore` (read-only search, 2-3 parallel instances for different search angles)
- **Legacy/Analysis**: `code-modernization:legacy-analyst` (for existing systems)
- **Business Logic**: `code-modernization:business-rules-extractor` (if business rules involved)

### Output required
- Files that will be affected (with paths)
- Dependencies between files
- Existing patterns/conventions to follow
- Risk areas identified
- Estimated change budget

### Gate: Discovery complete
- [ ] All affected files identified
- [ ] Dependencies mapped
- [ ] Risk areas flagged
- [ ] Change budget estimated within task size limits

### Auto-progression
Proceeds to PLAN automatically when discovery is complete. No human approval needed for medium+ tasks.

## Phase 2: PLAN

**Goal**: Design the implementation approach.

### When to run
- Small+ tasks (not micro)
- Any architectural decision needed
- Multi-file coordination required

### Agents deployed
- **Primary**: `Plan` (architecture design)
- **Architecture**: `feature-dev:code-architect` (detailed design)
- **Review**: `code-modernization:architecture-critic` (adversarial review of plan)

### Output required
- Step-by-step implementation plan
- Files to create/modify with specific changes
- Data flow design
- Test strategy
- Rollback plan

### Gate: Plan ready
- [ ] Architecture critic approved (no over-engineering, no missed requirements)
- [ ] All affected files enumerated
- [ ] Test strategy defined
- [ ] Rollback plan exists

### Auto-progression
Presents plan summary. If AUTO_APPROVE is true, proceeds to IMPLEMENT. If complex, asks user for plan approval via ExitPlanMode.

## Phase 3: ARCHITECT

**Goal**: Detailed component/schema/API design before coding.

### When to run
- Large+ tasks
- New APIs or services
- Database schema changes
- Cross-service integration

### Agents deployed
- **Primary**: `feature-dev:code-architect`
- **Database**: `wheeler-db-agent` (if schema changes)
- **API Design**: `feature-dev:code-explorer` (API contract design)
- **Review**: `pr-review-toolkit:type-design-analyzer` (type design review)

### Output required
- API contracts (request/response schemas)
- Database migration plan
- Component tree (for frontend)
- Type definitions

### Gate: Architecture ready
- [ ] API contracts defined
- [ ] Types reviewed (no design issues)
- [ ] Database migrations planned (if applicable)
- [ ] Component boundaries clear

## Phase 4: IMPLEMENT

**Goal**: Write the actual code. This is where the bulk of coding happens.

### When to run
- Always (every task)

### Agents deployed (parallel where possible)

| Task Type | Primary | Secondary | Tertiary |
|-----------|---------|-----------|----------|
| Backend API | general-purpose | general-purpose (tests) | — |
| Frontend UI | general-purpose | general-purpose | — |
| Database | general-purpose | wheeler-db-agent | — |
| DevOps | general-purpose | docker-expert | — |
| Multi-service | general-purpose × 3 (parallel) | — | — |

### Build rules
- One agent per independent file/module
- Never deploy 2 agents to edit the same file
- Each agent gets clear boundaries: "edit files X, Y, Z only"
- Agents must not exceed change budget
- if an agent hits a blocker, it escalates — do not silently fail

### Gate: Implementation complete
- [ ] All files written/modified
- [ ] Code compiles/builds without errors
- [ ] No TODO or placeholder left behind
- [ ] No agent reported failures

### Auto-progression
Proceeds to TEST automatically.

## Phase 5: TEST

**Goal**: Verify correctness with tests.

### When to run
- Any code change (always)
- Micro tasks: self-test only

### Agents deployed
- **Primary**: `code-modernization:test-engineer` (test generation/verification)
- **E2E**: general-purpose (if UI changes, playwright/curl tests)

### Test strategy by task size

| Size | Minimum Tests |
|------|--------------|
| Micro | Existing tests pass |
| Small | Unit test for new/changed function |
| Medium | Unit + integration tests |
| Large | Unit + integration + E2E smoke test |
| Critical | Full test suite + manual review |

### Gate: Tests passing
- [ ] All new tests pass
- [ ] All existing tests pass (no regressions)
- [ ] Test output shown as evidence
- [ ] Edge cases covered

### Auto-progression
Proceeds to REVIEW when all tests pass. If tests fail, returns to IMPLEMENT phase.

## Phase 6: REVIEW+SECURITY (Merged — parallel dispatch)

**Goal**: Code quality, correctness, AND security review in one parallel wave. These have zero data dependency — both inspect the same code diff independently.

### When to run
- Always (every task). Micro: code-simplifier only + automated secrets scan.

### Agents deployed (ALL in parallel — single message, multiple Agent calls)

| Agent | Focus | When |
|-------|-------|------|
| `Code Reviewer` | Correctness, maintainability, security, performance | Always |
| `code-simplifier` | Clarity, consistency, simplification | Always |
| `pr-review-toolkit:silent-failure-hunter` | Error handling, fallbacks, catch blocks | Medium+ |
| `pr-review-toolkit:type-design-analyzer` | Type design quality | When types changed |
| `pr-review-toolkit:comment-analyzer` | Comment accuracy | When comments added |
| `code-modernization:security-auditor` | OWASP, CWE, CVEs, injection, secrets | Always |
| Automated secrets scan | `git diff \| grep -E 'API_KEY\|TOKEN\|SECRET\|PASSWORD'` | Always (parallel) |
| DeepSeek routing check | Verify ANTHROPIC_* vars untouched | Always (parallel) |

### Review levels

| Level | Reviewer | Security | When |
|-------|----------|----------|------|
| Self | Implementer self-reviews | Auto secrets scan | Micro |
| Peer | Single review agent | Auto secrets scan | Small |
| Standard | 2 review agents + security-auditor (parallel) | Full | Medium |
| Final Boss | All review + security agents (parallel) | Full | Large |
| Final Boss + Human | All agents + human approval required | Full | Critical |

### Gate: Review+Security passed
- [ ] Code Reviewer: no critical/high issues
- [ ] Code Simplifier: no simplification opportunities missed
- [ ] Silent Failure Hunter: no unhandled errors (medium+)
- [ ] Type Design: no design issues (if types changed)
- [ ] Security auditor: no findings
- [ ] Secrets scan: clean
- [ ] DeepSeek routing: untouched
- [ ] All findings addressed or acknowledged

### Auto-progression
Proceeds to VERIFY+FINAL BOSS when all review and security checks pass. Findings auto-fixed before progression. Critical/high security findings block progression.

## Phase 7: VERIFY+FINAL BOSS (Merged — parallel dispatch)

**Goal**: End-to-end verification AND comprehensive final review in one parallel wave. The FINAL BOSS reviews code while VERIFY agents test it — no dependency between them.

### When to run
- Medium+ tasks. Any task claiming "done."

### Agents deployed (ALL in parallel — single message, multiple Agent calls)

| Agent | Focus |
|-------|-------|
| `devops-smoke-tester` | Build verification, deployment checks, Docker health |
| `production-readiness-agent` | Health checks, security, monitoring, backups |
| `zero-false-green-auditor` | Independent verification of ALL claims |
| `ecosystem-health-scoring` | Health score computation (service changes) |
| `Code Reviewer` (FINAL BOSS) | Final comprehensive sweep of ALL changes |

### Verification checks
- [ ] Build succeeds from clean state
- [ ] Service starts without errors
- [ ] Health endpoints respond 200
- [ ] Logs show no errors/crashes
- [ ] Dependent services unaffected
- [ ] No new alerts triggered

### Final Boss checks
- [ ] All previous phase gates passed
- [ ] Response contract completed (14 points)
- [ ] Readiness score computed
- [ ] UNVERIFIED items explicitly listed
- [ ] Next best action recommended
- [ ] Zero False Green Auditor: no false claims detected

### Gate: Verification+Final Boss passed
- [ ] All verifications passed with evidence
- [ ] FINAL BOSS scorecard complete
- [ ] Build is deploy-ready (or explicitly marked not-for-deploy)
- [ ] Score: 100/100 or explicit UNVERIFIED list

### Output: Final Scorecard

```
═══════════════════════════════════════
BUILD COMPLETE — [feature name]
Task: [classification] | Size: [size] | Time: [duration]
Agents deployed: [count] across 7 phases (optimized)

PHASE RESULTS:
  DISCOVER:         [PASS/SKIP/CACHED]
  PLAN:             [PASS/SKIP]
  ARCHITECT:        [PASS/SKIP]
  IMPLEMENT:        [PASS] — [N] files, [+N/-N] lines
  TEST:             [PASS] — [N]/[N] tests
  REVIEW+SECURITY:  [PASS] — [N] findings, 0 vulns
  VERIFY+FINAL:     [PASS] — [evidence]

READINESS: [0-100]
UNVERIFIED: [list or "none"]
NEXT ACTION: [one clear next step]
═══════════════════════════════════════
```

## Auto-Progression Rules

### When phases auto-proceed (no human needed — v2.2 always-on)
- DISCOVER → PLAN: Always auto-proceeds
- PLAN → ARCHITECT: Always auto-proceeds (no ExitPlanMode — EVER)
- ARCHITECT → IMPLEMENT: Always auto-proceeds
- IMPLEMENT → TEST: Always auto-proceeds
- TEST → REVIEW+SECURITY: Auto if all tests pass
- REVIEW+SECURITY → VERIFY+FINAL BOSS: Auto if no critical/security findings
- VERIFY+FINAL BOSS → DONE: Auto when scorecard complete

### When phases pause for human (v2.2 — minimal)
- Production deploy (always requires human)
- Secrets/DeepSeek routing touches (always requires human)
- Database migrations (always requires human)
- Blocker encountered after 5 retry attempts (escalate with structured report)

### Error recovery
- If an agent fails: retry with clearer instructions (up to 2 retries)
- If a gate fails: return to the appropriate phase for fixes
- If a phase is stuck: escalate with specific blocker description
- Never silently skip a phase

### Never-Stop Enforcement (v2.1)
The pipeline must NEVER stop silently before reaching 100/100:

| Phase | Budget | On Exceed |
|-------|--------|-----------|
| DISCOVER | 3 min | Skip with warning, use cached/partial knowledge |
| PLAN | 3 min | Auto-approve draft plan, proceed to IMPLEMENT |
| ARCHITECT | 3 min | Skip for medium tasks (not critical path) |
| IMPLEMENT | 8 min | Escalate with partial work and blocker report |
| TEST | 4 min | Auto-fix failures (retry generate + run, max 3 loops) |
| REVIEW+SECURITY | 5 min | Proceed with findings logged, not resolved |
| VERIFY+FINAL BOSS | 5 min | Mark UNVERIFIED, report score with caveats |

**Stuckness breaker**: If the SAME phase repeats 3+ times:
1. Log the recurring failure with full context
2. Try an alternative approach (different agent, different model)
3. On 5th attempt: escalate to human with structured blocker

**Terminal states** (pipeline must reach one):
- (a) 100/100 complete — all gates green
- (b) Score < 100 with explicit UNVERIFIED items listed
- (c) Structured blocker report escalated to human

## Agent Communication Protocol

### Handoff Format
When a phase completes, its output is summarized and passed to the next phase:

```
## Phase Handoff: [FROM_PHASE] → [TO_PHASE]

### What was done
[Summary of work completed]

### Key decisions
[Decisions made that affect downstream work]

### Files changed
[Specific file list with brief description of each change]

### Known issues / Caveats
[Anything the next phase should watch for]

### Unresolved
[Items requiring attention in later phases]
```

### Parallel Agent Coordination
- Independent agents in the same phase: run in parallel (single message with multiple Agent() calls)
- Dependent agents: run sequentially (output of A feeds into B)
- Agents NEVER edit the same file simultaneously
- Each agent reports back before the phase proceeds

### Agent Selection Hierarchy
1. Task-type-specific agent first (backend API → Backend API Agent template)
2. If no specific agent exists → general-purpose
3. If domain-specific knowledge needed → Explore for research, then general-purpose for implementation
4. Never delegate understanding — provide file paths, line numbers, and specific instructions

## Continuous Build Mode

### What it enables
- Walk away during a build — the pipeline continues
- Multi-phase builds run without prompt-by-prompt approval
- Agents auto-deploy when their phase triggers
- Progress tracked across all phases

### How to activate
- Implicit: any prompt classified as Medium+ triggers the full pipeline
- Explicit: `/build-autonomous <task description>`
- The intelligence hook detects build intent and arms the pipeline

### How it reports
- Phase completion notifications in chat
- Final scorecard at build end
- Agent activity logged to `.ai/reports/agent-activity.log`
- Session report generated on Stop

## Skills Auto-Detection

| Task Context | Auto-Loaded Skill |
|-------------|------------------|
| PM2 issues, crashes, restarts | `/slay` |
| Configuration, hooks, settings | `/update-config` |
| Multi-agent builds | `/superpowers` |
| GitHub, git operations | (gh CLI auto-detected) |
| Docker operations | `docker-expert` agent |
| Database queries/migrations | `wheeler-db-agent` agent |

## Plugin Auto-Utilization

| Context | Plugin Used |
|---------|------------|
| Code review needed | `code-review`, `code-simplifier` |
| Feature development | `feature-dev` (code-architect, code-explorer) |
| PR review | `pr-review-toolkit` (all 4 sub-agents) |
| Code modernization | `code-modernization` (all 4 sub-agents) |
| TypeScript/React | `typescript-lsp`, `frontend-design` |
| Python | `pyright-lsp` |
| Security | `security-guidance` |
| Session tracking | `session-report` |

## Zero-Gap Coverage Map

| Gap | Solution |
|-----|----------|
| No tests written | TEST phase is mandatory for all tasks |
| No security review | SECURITY phase mandatory, automated scan always runs |
| Silent failures swallowed | silent-failure-hunter in REVIEW phase |
| Bad type design | type-design-analyzer in ARCHITECT/REVIEW phases |
| False green claims | zero-false-green-auditor in VERIFY phase |
| Comment rot | comment-analyzer in REVIEW phase |
| Over-engineered code | architecture-critic in PLAN phase |
| Missing business logic | business-rules-extractor in DISCOVER phase |
| Stale documentation | autonomous-docs agent triggered on significant changes |
| Agent conflicts | agent-coordination agent prevents duplicate work |
| Skipped checks | Pipeline gates auto-enforce — can't skip phases |
| Orphaned work | All agents report back before phase proceeds |
