# Run Autonomous Agent Army to 100/100

## How to Activate

Simply describe your task naturally. The UserPromptSubmit intelligence hook auto-detects build intent and arms the autonomous pipeline. No special command needed — the OS knows when to deploy the army.

For explicit army deployment:
```
Deploy the Wheeler Agent Army for: [describe the mission]
```

Or use the walk-away trigger:
```
Build [feature] — walk-away mode. Take it to 100%.
```

## What Happens

The Autonomous Build Pipeline (`.ai/subagents/BUILD_PIPELINE.md`) activates:

```
INTELLIGENCE → DISCOVER → PLAN → ARCHITECT → IMPLEMENT → TEST → REVIEW → SECURITY → VERIFY → FINAL BOSS → DONE
```

Each phase auto-deploys the right agents, auto-checks gates, auto-progresses.

## Deployment Rules

1. **Phase-based**: Agents deploy per phase, not all at once
2. **Parallel where independent**: Multiple agents in same phase deploy together
3. **No overlap**: No two agents edit the same file
4. **Handoff protocol**: Each phase passes structured context to the next
5. **Auto-progression**: Phases proceed without human input (except explicit gates)
6. **Final Boss sweep**: Comprehensive review catches everything

## Agent Count by Task Size

| Size | Phases | Max Parallel Agents |
|------|--------|-------------------|
| Micro | 2 | 1 |
| Small | 4 | 2 |
| Medium | 6 | 4 |
| Large | 7 (full) | 6 |
| Critical | 7 + human | As needed |

## Walk-Away Mode

When the intelligence hook detects walk-away intent, the pipeline runs to 100% completion without further human input. You can close your laptop — the build continues.

**Only these gates pause the pipeline:**
- Production deploy (always human)
- Database migrations (always human)
- Secrets management (always human)
- Shell profile changes (always human)
- DeepSeek routing changes (always human)

## Army Composition by Phase

### DISCOVER
- Explore × 2-3 (parallel, different search angles)
- legacy-analyst (if existing system)
- business-rules-extractor (if domain logic)

### PLAN
- Plan agent (architecture design)
- architecture-critic (adversarial review)

### ARCHITECT (Large+)
- code-architect (detailed design)
- type-design-analyzer (type review)

### IMPLEMENT
- general-purpose × N (parallel by independent module)

### TEST
- test-engineer (unit/integration)
- general-purpose (E2E/smoke)

### REVIEW (all parallel)
- Code Reviewer
- code-simplifier
- silent-failure-hunter
- type-design-analyzer
- comment-analyzer

### SECURITY
- security-auditor
- Automated secrets scan

### VERIFY (parallel)
- devops-smoke-tester
- production-readiness-agent
- zero-false-green-auditor

### FINAL BOSS
- Code Reviewer (comprehensive final sweep)

## Output

Every build ends with:
```
═══════════════════════════════════════
BUILD COMPLETE — [feature name]
PHASE RESULTS: [all phases with PASS/SKIP]
READINESS: [0-100]
UNVERIFIED: [list or none]
NEXT ACTION: [one clear step]
═══════════════════════════════════════
```

Plus the 14-point response contract from `.ai/prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md`.

## DeepSeek Protection (IMMUTABLE)
Active on all builds. Do not touch ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ANTHROPIC_MODEL, DEEPSEEK_API_KEY, LITELLM_MASTER_KEY.

## No False Greens (ZERO TOLERANCE)
Every claim requires evidence. Zero-false-green-auditor independently verifies.
