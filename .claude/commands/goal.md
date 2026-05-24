# /goal — High-Level Goal Decomposition

Decompose a high-level goal into executable tasks routed through Wheeler Board OS and the superpowers framework.

## Execution

When invoked, perform these steps in parallel:

### Phase 1: Goal Analysis (parallel)
1. **Goal classification** — Identify domain: infrastructure, security, development, operations, business, data
2. **Board routing** — Route to the correct Wheeler Board OS seat using the routing table in CLAUDE.md
3. **Capability check** — Which skills, agents, and tools are needed?

### Phase 2: Decomposition
Break the goal into:
- **Milestones** (ordered, with dependencies)
- **Tasks per milestone** (each estimable, testable)
- **Acceptance criteria** per milestone
- **Required agents/skills** per task
- **Parallelization opportunities** (use superpowers dispatching-parallel-agents)
- **Risk assessment** per milestone
- **Rollback path** if applicable

### Phase 3: Execution Plan
- Timeline estimate
- Resource requirements
- Safety gates to pass
- Verification criteria
- Who/what needs to be notified

## Output Format

```
GOAL: <goal statement>
ROUTED TO: <board seat/domain>
──────────────────────────────────────

MILESTONE 1: <name> [estimated: Xh]
  Tasks:
    □ <task> → agent: <name>, skill: <name>
    □ <task> → agent: <name>, skill: <name> [PARALLEL with above]
  Acceptance: <criteria>
  Risks: <risk list>

MILESTONE 2: <name> [depends on: M1]
  ...

──────────────────────────────────────
SAFETY GATES: <gates to clear>
ROLLBACK: <rollback approach>
VERIFICATION: <how to prove completion>
```
