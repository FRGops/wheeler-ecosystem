---
name: execute
description: Autonomous Execution Engine — generate execution plans, recommend next actions, route tasks to agents, escalate blockers, monitor progress, optimize workflows. The COO agent that keeps the Wheeler ecosystem moving.
metadata:
  type: skill
  version: "1.0.0"
  author: Wheeler Brain OS
  tags:
    - execution
    - automation
    - coordination
    - operations
---

# Autonomous Execution Engine

The engine that turns plans into action. Full architecture at `/root/AUTONOMOUS_EXECUTION_ENGINE.md`.

## Subcommands

### `/execute plan <goal>`
Generate a full execution plan from a strategic goal.

**Process:**
1. Gather ecosystem state (Docker, PM2, revenue, alerts, agent availability)
2. Decompose goal into task tree with phases and dependencies
3. Estimate effort for each task
4. Match tasks to best-fit agents using the routing matrix
5. Identify critical path and risks
6. Output formatted execution plan with timeline

**Output:** Task tree, Gantt timeline, agent assignments, risk register, success criteria.

### `/execute next`
Recommend the top 3 next actions right now.

**Process:**
1. Snapshot ecosystem state
2. Score all pending tasks through prioritization engine
3. Filter by agent availability and dependencies
4. Rank by composite score (revenue × leverage × urgency)
5. Output top 3 with justification, time estimate, agent assignment

### `/execute status`
Show execution status of all active work.

**Process:**
1. Load all active plans and tasks
2. Check completion status of each
3. Calculate burndown/burnup
4. Track velocity trends
5. Flag at-risk tasks (behind schedule, blocked, unassigned)
6. Show agent workload distribution

### `/execute route <task>`
Route a task to the right agent.

**Routing matrix:**

| Domain | Agent |
|--------|-------|
| Infrastructure | infra-intelligence, wheeler-infra-agent |
| Docker | docker-intelligence, docker-expert |
| PM2 | pm2-intelligence |
| Revenue | revenue-intelligence |
| Deployment | deployment-intelligence, wheeler-deploy-agent |
| Security | security-intelligence, wheeler-security-agent |
| Monitoring | monitoring-intelligence |
| Database | wheeler-db-agent |
| Cross-server | multi-server-coordination |
| General | general-purpose, claude |

**Process:**
1. Classify task by domain, type, priority, urgency
2. Look up routing matrix
3. Assemble context handoff (relevant state, constraints, success criteria)
4. Dispatch to target agent via Agent tool
5. Register task in execution tracker

### `/execute unblock`
Identify and escalate blocked tasks.

**Blocker classification:**

| Severity | SLA | Escalation |
|----------|-----|------------|
| P0 | 30 min | War room + CEO notification |
| P1 | 4 hours | Domain lead + AI Chief of Staff |
| P2 | 24 hours | Agent reassignment |
| P3 | 1 week | Sprint backlog |

**Process:**
1. Scan all active tasks for blocked status
2. Classify by severity and aging
3. Identify correct resolver (agent or human)
4. Escalate if SLA breached
5. Track resolution

### `/execute review`
Weekly execution review.

**Process:**
1. Aggregate completion data (tasks done, in progress, blocked)
2. Agent productivity metrics (throughput, accuracy, cost)
3. Blocker statistics (count, resolution time, recurrence)
4. Workflow efficiency analysis
5. Trend analysis (velocity, cycle time, WIP)
6. Generate formatted weekly report

### `/execute optimize`
Analyze and suggest workflow optimizations.

**Process:**
1. Analyze workflow efficiency metrics
2. Identify patterns:
   - Recurring blocker types → root cause fix
   - Underutilized agents → reassign or retire
   - Repetitive task sequences → automation candidate
   - Long cycle times → decomposition opportunity
3. Recommend optimizations with expected ROI
4. Track optimization impact over time

## Action Scoring Formula
```
action_score = (revenue_impact × 0.25) + (operational_leverage × 0.20)
             + (urgency × 0.20) + (automation_potential × 0.15)
             + (time_to_value × 0.10) + (risk_reduction × 0.10)
```

## Integration Points
- **Feeds from:** AI Chief of Staff (priorities), Prioritization Engine (scores), KPI System (metrics)
- **Feeds to:** Executive Dashboard (status), CEO Command Console (briefings)
- **Coordinates:** All 53 agents through agent-coordination
- **Depends on:** Neo4j memory graph (state persistence), .claude.json agent registry (routing)
