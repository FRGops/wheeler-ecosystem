---
name: agent-workflow-builder
description: "Build agent workflows: define agent types needed, their prompts, tools required, dependency graph, parallelization opportunities, verification gates, aggregate output format."
trigger: build workflow, agent workflow, create workflow, workflow design, agent pipeline, multi agent, orchestrate agents
---

# Skill: Agent Workflow Builder

Design and build multi-agent workflows for complex tasks. Uses the superpowers dispatching-parallel-agents pattern.

## Workflow Design Process

### Step 1: Task Decomposition
Break the complex task into sub-tasks:
```
TASK: <overall goal>
SUB-TASKS:
  1. <sub-task> — [INDEPENDENT / DEPENDS ON: <N>]
  2. <sub-task> — [INDEPENDENT / DEPENDS ON: <N>]
  3. <sub-task> — [INDEPENDENT / DEPENDS ON: <N>]
```

### Step 2: Agent Selection
For each sub-task, select the best agent:

| Sub-task Type | Recommended Agent |
|---------------|------------------|
| Code exploration | Explore agent |
| Implementation | general-purpose agent |
| Planning/architecture | Plan agent |
| Code review | engineering-code-reviewer, code-reviewer |
| Security audit | wheeler-security-agent |
| Infrastructure ops | docker-expert, engineering-sre |
| Database work | wheeler-db-agent, database-rls-auditor |
| Verification | zero-false-green-auditor, devops-smoke-tester |
| Debugging | engineering-sre, systematic-debugging |
| Documentation | general-purpose agent |

### Step 3: Dependency Graph
```
PARALLEL BATCH 1 (no dependencies):
  Agent A → <sub-task-1>
  Agent B → <sub-task-2>

PARALLEL BATCH 2 (depends on Batch 1):
  Agent C → <sub-task-3> (needs output from A)
  Agent D → <sub-task-4> (needs output from B)

FINAL:
  Aggregate results → verify → report
```

### Step 4: Prompt Engineering
Each agent prompt must include:
- Clear task description
- File paths and line numbers where applicable
- What we already know (context)
- Expected output format
- Verification criteria

### Step 5: Verification Gates
```
After each batch:
  □ Agent output matches expected format
  □ No errors in agent execution
  □ Output is actionable (not vague)

After final aggregation:
  □ All sub-tasks complete
  □ Results are consistent (no conflicts)
  □ Verification evidence provided
```

## Workflow Template

```markdown
# Workflow: <name>

## Goal
<one-sentence goal>

## Sub-tasks & Agents

### Batch 1 (Parallel)
| Agent | Task | Expected Output |
|-------|------|----------------|
| <name> | <task> | <output> |
| <name> | <task> | <output> |

### Batch 2 (Parallel, depends on Batch 1)
| Agent | Task | Depends On | Expected Output |
|-------|------|-----------|----------------|

## Aggregation
- How to combine results
- How to resolve conflicts
- Final output format

## Verification
- What must be true for workflow to be "done"
- Evidence required
```
