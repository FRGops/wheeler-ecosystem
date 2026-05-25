---
name: chief-of-staff
description: AI Chief of Staff — daily priorities, weekly planning, blocker escalation, operational forecasting for the Wheeler ecosystem
metadata:
  type: skill
  version: "1.0.0"
  author: Wheeler Brain OS
  tags:
    - execution
    - planning
    - coordination
    - operations
---

# AI Chief of Staff

Central execution coordination for the Wheeler ecosystem. Transforms strategy into daily action.

## Subcommands

### `/chief-of-staff daily`
Generate today's prioritized action items from live ecosystem state.

**Process:**
1. Pull health data: Docker (docker ps), PM2 (pm2 jlist), revenue (:8170), alerts (:9093)
2. Score all active tasks through the prioritization engine
3. Rank top 5 by composite score (revenue × leverage × urgency)
4. Flag blockers aging >24h
5. Recommend agent assignments
6. Output formatted daily brief

### `/chief-of-staff weekly`
Generate weekly execution plan with sprint backlog.

**Process:**
1. Retrospective: planned vs done last week
2. Velocity calculation from task completion data
3. Backlog grooming: re-score pending tasks
4. Sprint backlog selection based on capacity
5. Dependency map: what blocks what
6. Risk register update
7. Agent capacity planning

### `/chief-of-staff review`
Review progress against current plan.

**Process:**
1. Load current sprint/plan
2. Check completion status of each item
3. Identify slipped tasks and root causes
4. Recommend course corrections
5. Update velocity metrics

### `/chief-of-staff escalate`
Identify and escalate blocked items.

**Process:**
1. Scan all active tasks for blocked status
2. Classify by severity (P1/P2/P3) and aging
3. Route to correct resolver
4. Generate escalation report with recommended actions

### `/chief-of-staff forecast`
Predict next-week bottlenecks and risks.

**Process:**
1. Analyze historical bottleneck patterns
2. Check current trajectory of active tasks
3. Identify resource constraints (agent capacity, dependencies)
4. Flag at-risk deliverables
5. Recommend preemptive actions

## Data Sources
- PM2 process list (pm2 jlist)
- Docker container status (docker ps)
- Revenue metrics collector (:8170)
- Executive dashboard API (:8180)
- Prometheus metrics (:9090)
- Alertmanager alerts (:9093)
- Uptime Kuma status (:3001)
- AI Ops watchdog health report

## Coordination
This skill coordinates with:
- `prioritize` — task scoring engine
- `execute` — autonomous execution engine
- `kpi` — KPI tracking system
- `ceo` — CEO operating system
- `govern` — execution governance
