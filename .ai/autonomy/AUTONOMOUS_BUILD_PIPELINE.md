# Autonomous Build Pipeline — End-to-End Autonomy Framework

## Principle: Walk Away and It Builds

The Wheeler Coding OS autonomous build pipeline runs builds to 100% completion without human intervention. You describe what you want, the intelligence layer classifies it, the pipeline deploys agents, and phases auto-progress. You only need to be present for explicit human approval gates (production deploys, secrets, DB migrations).

## Architecture

```
UserPromptSubmit
       │
       ▼
┌──────────────────┐
│ INTELLIGENCE HOOK │  ← Auto-classifies task, arms pipeline
└──────┬───────────┘
       │ additionalContext injected
       ▼
┌──────────────────┐
│   CLAUDE CODE    │  ← Reads classification, follows pipeline
└──────┬───────────┘
       │
       ▼
┌──────────────────────────────────────────────┐
│            AUTONOMOUS BUILD PIPELINE          │
│                                              │
│  DISCOVER → PLAN → ARCHITECT → IMPLEMENT     │
│     → TEST → REVIEW → SECURITY → VERIFY      │
│              → FINAL BOSS → DONE              │
│                                              │
│  Each phase: agents auto-deployed, gates      │
│  auto-checked, handoffs auto-generated        │
└──────────────────────────────────────────────┘
```

## Fully Wired Integration Points

### 1. UserPromptSubmit Hook (`.claude/hooks/userprompt-intelligence.sh`)
- Fires on EVERY user prompt
- Classifies: task type, size, tech stack, build intent, army mode
- Injects pipeline routing as `additionalContext`
- Non-invasive — adds context, doesn't block

### 2. SessionStart Hook (`.claude/hooks/sessionstart-autobootstrap.sh`)
- Boots the OS automatically
- Verifies critical files, runs preflight
- Prints session context

### 3. PostToolUse Hooks
- `posttooluse-log.sh`: Logs all tool usage
- `posttooluse-repo-detect.sh`: Detects repo changes

### 4. Stop Hook (`.claude/hooks/stop-postflight.sh`)
- Runs postflight: diff audit, dependency safety, DeepSeek protection
- Generates session report

### 5. PreToolUse Hook (`.claude/hooks/pretooluse-safety.sh`)
- Blocks destructive operations
- Prevents secrets access, DeepSeek routing changes

### 6. CLAUDE.md + AGENTS.md
- Full pipeline specification
- Agent deployment matrix
- Quality gates and response contract

### 7. BUILD_PIPELINE.md
- 9-phase specification with agent assignments
- Handoff protocols
- Auto-progression rules

### 8. AGENT_ARMY_DEPLOYMENT_MATRIX.md
- Phase → Agent mapping
- Task type → Agent routing
- Anti-patterns blocked

## Extensibility: Adding Future Phases/Agents

### Adding a New Pipeline Phase
1. Add phase definition to `.ai/subagents/BUILD_PIPELINE.md`
2. Add agent assignments to `.ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md`
3. Update phase order in `CLAUDE.md` if needed
4. Add gate criteria
5. Update auto-progression rules

### Adding a New Agent to the Fleet
1. Add agent entry to `.ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md`
2. Assign to pipeline phase(s)
3. Define: allowed tools, forbidden actions, output format
4. Create agent template in `.ai/subagents/` if specialized
5. Add to task-type routing table

### Adding a New Skill
1. Create skill directory in `.claude/skills/<name>/`
2. Add `SKILL.md` with instructions
3. Register in `.ai/skills/AGENT_SKILLS_REGISTRY.md`
4. Add auto-detection pattern to `userprompt-intelligence.sh`

### Adding a New Plugin Integration
1. Enable plugin in `.claude/settings.json` → `enabledPlugins`
2. Add to auto-utilization table in `CLAUDE.md` and `BUILD_PIPELINE.md`

## Current Pipeline State

| Phase | Status | Agents | Auto-Progression |
|-------|--------|--------|-----------------|
| INTELLIGENCE | ✅ WIRED | userprompt-intelligence.sh | Always |
| DISCOVER | ✅ DEFINED | Explore × 3, legacy-analyst, business-rules-extractor | Auto |
| PLAN | ✅ DEFINED | Plan, architecture-critic | Conditional (Large→human) |
| ARCHITECT | ✅ DEFINED | code-architect, code-explorer, type-design-analyzer | Auto |
| IMPLEMENT | ✅ DEFINED | general-purpose × N | Auto |
| TEST | ✅ DEFINED | test-engineer, general-purpose | Auto |
| REVIEW | ✅ DEFINED | Code Reviewer, code-simplifier, silent-failure-hunter, type-design-analyzer, comment-analyzer | Auto |
| SECURITY | ✅ DEFINED | security-auditor, automated scans | Auto |
| VERIFY | ✅ DEFINED | devops-smoke-tester, production-readiness-agent, zero-false-green-auditor | Auto |
| FINAL BOSS | ✅ DEFINED | Code Reviewer (comprehensive) | Auto |

## Agentic Workflow — End-to-End Example

### Prompt: "Add user authentication to the API"

```
1. INTELLIGENCE HOOK FIRES
   → Classifies: feature, medium, typescript-react
   → Arms: 6-phase pipeline, 4 max agents, Final Boss review

2. DISCOVER PHASE (auto)
   → Explore agent: finds auth middleware, existing user model, API routes
   → Explore agent: finds test patterns, config, env vars
   → Output: 12 affected files, 3 risk areas

3. PLAN PHASE (auto)
   → Plan agent: designs JWT auth, middleware, login/signup routes
   → Architecture critic: flags over-engineering risk
   → Plan refined, proceeds

4. IMPLEMENT PHASE (auto)
   → Agent 1: auth middleware (2 files)
   → Agent 2: login/signup routes (2 files)
   → Agent 3: tests (1 file)
   → All 3 agents run in parallel
   → All report success

5. TEST PHASE (auto)
   → test-engineer: runs test suite, 15/15 pass
   → Output: test results with evidence

6. REVIEW PHASE (auto)
   → Code Reviewer + code-simplifier + silent-failure-hunter + type-design-analyzer (parallel)
   → 2 medium findings, 1 low finding
   → Findings auto-fixed

7. SECURITY PHASE (auto)
   → security-auditor: checks OWASP, injection vectors
   → Secrets scan: clean
   → DeepSeek routing: untouched

8. VERIFY PHASE (auto)
   → devops-smoke-tester: build passes, service starts
   → zero-false-green-auditor: all claims verified

9. FINAL BOSS (auto)
   → Code Reviewer: comprehensive sweep
   → Score: 100/100 A+
   → Response contract complete
```

## Future-Proofing Guarantees

1. **New agents auto-integrate**: Add to matrix, they're discovered by the pipeline
2. **New phases append cleanly**: The pipeline is a linear chain — add phases at any point
3. **Skills auto-detect**: New skills register detection patterns in the intelligence hook
4. **Plugins auto-utilize**: Context-based plugin selection scales with new plugins
5. **Phase independence**: Each phase is self-contained with clear input/output contracts
6. **Agent replaceability**: Any agent can be swapped for a better one without pipeline changes

## Fully Agentic — What This Means

- **Every build phase has agents**: No phase is manual
- **Agents communicate**: Handoff protocol passes context between phases
- **Agents coordinate**: agent-coordination prevents duplicate work
- **Agents verify each other**: REVIEW phase checks IMPLEMENT phase, VERIFY checks everything
- **Agents self-correct**: Failed gates loop back to the appropriate phase
- **Agents report**: Every phase produces a handoff, every agent reports results

## Zero Human Intervention (Except Where Required)

| Action | Human Needed? |
|--------|--------------|
| Task classification | No — auto-detected |
| Agent deployment | No — auto-deployed per phase |
| Phase progression | No — auto-progresses |
| Test execution | No — automated |
| Code review | No — agents review in parallel |
| Security audit | No — automated scan + agent audit |
| Verification | No — agents verify |
| Production deploy | YES — always human |
| Database migration | YES — always human |
| Secrets access | YES — always human |
| DeepSeek routing change | YES — always human |
| Shell profile change | YES — always human |
