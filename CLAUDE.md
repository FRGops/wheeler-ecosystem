# Wheeler Always-On Autonomous Agentic Coding OS

## AUTO-BOOTSTRAP (FULLY AUTOMATED — ZERO MANUAL STEPS)

Every Claude Code session in this repository — and all repos in the Wheeler ecosystem — automatically boots the Wheeler AI Coding OS on session start. No manual commands. No setup. It just works.

The SessionStart hook (wired in `.claude/settings.json`) fires automatically and:
1. Verifies all critical OS files exist (CLAUDE.md, AGENTS.md, .ai/INDEX.md, DeepSeek policy)
2. Runs preflight: branch safety, DeepSeek env presence, agent locks, available gates
3. Prints session context: branch, session ID, routing matrix path, response contract path

**You never need to run anything manually. The OS boots itself.**

## AUTONOMOUS BUILD PIPELINE (THE MASTERPIECE)

Every build task automatically flows through a 7-phase autonomous pipeline. The UserPromptSubmit intelligence hook classifies each prompt, determines the required pipeline depth, and auto-deploys the right agents for each phase. You can walk away — the build continues to 100% completion.

```
PROMPT → [INTELLIGENCE] → DISCOVER → PLAN → ARCHITECT → IMPLEMENT → TEST → REVIEW → SECURITY → VERIFY → FINAL BOSS → DONE
```

Full specification: `.ai/subagents/BUILD_PIPELINE.md`

### Phase Auto-Progression
Phases auto-proceed without human intervention. Only pause for:
- Large/Critical PLAN phase (ExitPlanMode for approval)
- Production deploys (always human)
- Secrets/DeepSeek routing changes (always human)
- Database migrations (always human)
- Blocker encountered (escalate with description)

### Pipeline Depth by Task Size

| Task Size | Phases | Max Parallel Agents |
|-----------|--------|-------------------|
| Micro | IMPLEMENT → REVIEW | 1 |
| Small | PLAN → IMPLEMENT → TEST → REVIEW | 2 |
| Medium | DISCOVER → PLAN → IMPLEMENT → TEST → REVIEW → SECURITY → FINAL BOSS | 4 |
| Large | Full 7-phase pipeline | 6 |
| Critical | Full pipeline + human gates | As needed |

## ECOSYSTEM INTEGRATION MESH (IMMUTABLE — ANTI-DUPLICATION)

The Wheeler ecosystem spans **3 servers** connected via Tailscale mesh. Before building ANY new service, capability, or module, you MUST check the ecosystem registry to avoid duplicating work that already exists on another server.

### Server Map

| Server | Tailscale IP | Role | What Lives Here |
|--------|-------------|------|-----------------|
| **hostinger** | 100.98.163.17 | Production API Gateway | CRM API, Outreach Engine, Enrichment Pipeline, Skip Tracing, Attorney Marketplace, Firecrawl, Gotenberg |
| **aiops** (this server) | 100.121.230.28 | Brain & Orchestrator | 85+ PM2 processes, 45 Docker containers, Monitoring, AI/LLM, Scrapers, Escheat Watchdog, Agent Army |
| **coredb** | 100.118.166.117 | Database & Pipelines | PostgreSQL, Redis, Qdrant, MinIO, Infisical Secrets, Prediction Radar, Temporal Pipelines |

### Mandatory Pre-Build Check (BEFORE DISCOVERY PHASE)

**BEFORE creating any new service, module, or capability:**
1. Query the Ecosystem Discovery API: `curl -s -X POST http://localhost:8190/discovery/prebuild-check -H "Content-Type: application/json" -d '{"capability": "<what you are building>", "description": "<one sentence description>"}' | python3 -m json.tool`
2. If `should_build` is **false**: STOP. The capability already exists. Read the `integration_points` and integrate with the existing service instead.
3. If `should_build` is **true**: Proceed, but deploy to the `recommended_target` server.

**CLI tool**: `python3 /opt/wheeler/ecosystem-registry/scripts/prebuild-check.py "<capability>" --json`

### Server Deployment Targets

| If you're building... | Deploy to... | Reason |
|----------------------|-------------|--------|
| CRM APIs, Outreach, Skip Tracing | **hostinger** | Production API surface with Nginx + domain routing |
| AI Agents, Monitoring, Scrapers | **aiops** | Brain node with LLM infra + observability stack |
| Databases, Secrets, Pipelines | **coredb** | Dedicated DB server with Infisical |

### Cross-Server API Call Pattern

```
Any server → Tailscale IP → INTERNAL_API_KEY header → target service
```

Example: AIOPS calling hostinger's skip tracing API:
```
curl -H "Authorization: Bearer $INTERNAL_API_KEY" http://100.98.163.17:8082/api/skip-trace/health
```

### Ecosystem Discovery API (:8190)

Running on AIOPS as PM2 `ecosystem-discovery`. Endpoints:
- `GET /discovery/health` — API health + server count
- `GET /discovery/services?server=hostinger` — services by server
- `GET /discovery/capability/{name}` — find capability by name
- `GET /discovery/capabilities` — list all 12+ capability domains
- `POST /discovery/prebuild-check` — "should I build this?"

Registry: `/opt/wheeler/ecosystem-registry/registry.json` — comprehensive catalog of every service across all 3 servers.

## CORE RULES

### DeepSeek V4 Protection (IMMUTABLE)
- **NEVER** modify ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ANTHROPIC_MODEL, DEEPSEEK_API_KEY, or LITELLM_MASTER_KEY.
- **NEVER** edit ~/.zshrc, ~/.bashrc, ~/.profile, or ~/.bash_profile.
- **NEVER** read .env files or secrets/.
- If a task requires touching these: STOP and escalate to human.

### Task Classification (AUTOMATIC)
Task classification is now automatic via the UserPromptSubmit intelligence hook. Manual classification is a fallback:
- **Micro**: 1 file, < 20 lines
- **Small**: 1-3 files, < 100 lines
- **Medium**: 3-10 files, < 500 lines
- **Large**: 10-25 files, < 2000 lines
- **Critical**: Any size, production/security impact

### Agent Auto-Deployment (MANDATORY)
When a build task is detected, deploy agents according to `.ai/subagents/BUILD_PIPELINE.md`:
- DISCOVER: Explore agents (2-3 parallel) for codebase understanding
- PLAN: Plan agent + architecture-critic for adversarial review
- ARCHITECT: code-architect + type-design-analyzer
- IMPLEMENT: general-purpose agents (parallel where independent)
- TEST: test-engineer agent + manual verification
- REVIEW: Code Reviewer + code-simplifier + silent-failure-hunter + type-design-analyzer (all parallel)
- SECURITY: security-auditor + automated secrets scan
- VERIFY: devops-smoke-tester + production-readiness-agent + zero-false-green-auditor
- FINAL BOSS: Code Reviewer (final sweep + scorecard)

### Agent Communication Protocol
- Each phase outputs a handoff summary: what was done, key decisions, files changed, known issues
- Independent agents in the same phase: deploy in parallel (single message, multiple Agent() calls)
- Agents NEVER edit the same file simultaneously
- Each agent reports back before the phase proceeds
- Failed agents retry with clearer instructions (max 2 retries)

### Skills Auto-Detection
| Task Context | Auto-Loaded Skill |
|-------------|------------------|
| PM2 issues, crashes, restarts | `/slay` |
| Configuration, hooks, settings | `/update-config` |
| Multi-agent builds | `/superpowers` |
| GitHub, git operations | gh CLI auto-detected |
| Docker operations | docker-expert agent |

### Plugin Auto-Utilization
| Context | Plugin Used |
|---------|------------|
| Code review needed | code-review, code-simplifier |
| Feature development | feature-dev (code-architect, code-explorer) |
| PR review | pr-review-toolkit (all 4 sub-agents) |
| Code modernization | code-modernization (all 4 sub-agents) |
| Security audit | security-guidance |

### Preflight/Postflight (AUTOMATIC)
- **Preflight**: Runs on SessionStart — verifies branch, env var presence, agent locks.
- **Postflight**: Runs on Stop — verifies diff, dependency safety, DeepSeek protection, gates.

### Quality Gates (EVIDENCE-BASED)
Every completion claim requires evidence:
- Tests passing? Show the output.
- Lint clean? Show the output.
- No secrets? Run pattern scan.
- DeepSeek untouched? Verify.
- Live endpoint? Show the curl result.
- Agent results? Show the handoff summary.

### No False Greens (ZERO TOLERANCE)
- Never claim 100/100 unless ALL validations pass.
- Never say "live" unless you hit a live endpoint/UI.
- Never say "deployed" unless a deploy command/log proves it.
- Label unknowns as UNVERIFIED.
- Zero-false-green-auditor runs in VERIFY phase for independent validation.

### Walk-Away Autonomy
- The build pipeline auto-progresses through phases
- Agents auto-deploy when their phase triggers
- Progress is tracked in the conversation and agent activity log
- You can walk away at any point — the pipeline continues to completion
- Builds pause only at explicit human approval gates (production, secrets, DB migrations)

## FILE REFERENCES
- Index: `.ai/INDEX.md`
- Build Pipeline: `.ai/subagents/BUILD_PIPELINE.md` (the autonomous masterpiece)
- Agent deployment: `.ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md`
- Model routing: `.ai/model-routing/MODEL_ROUTING_DECISION_MATRIX.md`
- DeepSeek policy: `.ai/model-routing/DEEPSEEK_V4_PRIMARY_POLICY.md`
- Response contract: `.ai/prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md`
- Preflight: `.ai/autonomy/PREFLIGHT_CHECKLIST.md`
- Postflight: `.ai/autonomy/POSTFLIGHT_CHECKLIST.md`
- Autonomous pipeline: `.ai/autonomy/AUTONOMOUS_BUILD_PIPELINE.md`
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
