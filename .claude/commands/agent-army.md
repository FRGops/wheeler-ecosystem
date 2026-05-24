# /agent-army — Agent Army Deployment

Deploy specialized Claude Code agents for complex multi-step tasks. Uses the superpowers dispatching-parallel-agents pattern.

## Execution

### Step 1: Task Classification
Classify the task to determine which agents to deploy:

| Task Type | Primary Agents | Support Agents |
|-----------|---------------|----------------|
| Infrastructure/deploy | docker-expert, devops-smoke-tester | engineering-sre |
| Security audit | database-rls-auditor, engineering-sre | zero-false-green-auditor |
| Code review | engineering-code-reviewer, zero-false-green-auditor | — |
| Database | database-rls-auditor, docker-expert | engineering-sre |
| Debugging | engineering-sre, zero-false-green-auditor | docker-expert |
| Production issue | engineering-sre, docker-expert | devops-smoke-tester |
| Architecture | engineering-code-reviewer, docker-expert | engineering-sre |
| General development | engineering-code-reviewer, zero-false-green-auditor | — |

### Step 2: Agent Dispatch Rules

```
1. INDEPENDENT tasks → dispatch ALL agents in ONE message (parallel)
2. SEQUENTIAL tasks → dispatch in order, each depends on previous
3. MIXED → dispatch independent groups in parallel messages, chain groups sequentially
```

### Step 3: Agent Prompt Quality

Every agent prompt must include:
- **What** to do (specific, not vague)
- **Why** it matters (context)
- **Where** to look (file paths, line numbers)
- **What we already know** (prior findings)
- **What output format** to return

### Step 4: Result Aggregation
```
Collect all agent outputs:
1. Remove duplicates
2. Resolve conflicts (trust specific over general)
3. Synthesize into single response
4. Verify with zero-false-green standards
```

### Available Wheeler Agents
```
Core:
  wheeler-infra-agent     — Docker, PM2, networking, systemd
  wheeler-security-agent  — Secrets, firewall, SSH, vulns
  wheeler-deploy-agent    — Safe deploys, canary, rollback
  wheeler-db-agent        — PostgreSQL management
  wheeler-mac-agent       — Mac Command Center
  wheeler-worker-agent    — Worker node operations

From Hostinger (mirrored):
  docker-expert           — Docker specialist
  zero-false-green-auditor— Verification specialist
  devops-smoke-tester     — Post-deploy smoke testing
  database-rls-auditor    — Database security
  engineering-sre         — SRE operations
  engineering-code-reviewer— Code quality
```

## Output Format

```
╔══════════════════════════════════════════════╗
║   Agent Army Deployment — <task-id>          ║
╚══════════════════════════════════════════════╝

TASK: <description>
CLASSIFICATION: <type>
──────────────────────────────────────
DEPLOYED AGENTS:
  [PARALLEL BATCH 1]
    <agent-1> — <purpose>
    <agent-2> — <purpose>
    <agent-3> — <purpose>
  [PARALLEL BATCH 2 — depends on batch 1]
    <agent-4> — <purpose>

──────────────────────────────────────
AGGREGATED RESULT:
  <synthesized output>

──────────────────────────────────────
VERIFIED: [YES / PARTIAL — <reason> / NO — <reason>]
```
