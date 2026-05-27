---
name: agent-prompt-templates-20260526
description: "6 agent prompt templates deployed in wheeler-command-center configs/prompts/ — agent-infra.md (45 lines) and agent-security.md (46 lines) rebuilt as full dispatch templates (2026-05-26)"
metadata:
  node_type: memory
  type: project
  originEpoch: 2026-05-26
  originSessionId: session-20260526-065224
---

# Agent Prompt Templates — 2026-05-26

## Location

`/root/wheeler-command-center/configs/prompts/`

## Files

| File | Lines | Description |
|------|-------|-------------|
| `agent-infra.md` | 45 | Full dispatch template: identity, capabilities, 6-step execution protocol, output format with health score, verification standards |
| `agent-security.md` | 46 | Full dispatch template: identity, capabilities, 7-step execution protocol, severity-classified output (P0/P1/P2), verification rules |
| `agent-deployment-validation.md` | 24 | Deployment gate enforcement — 10 validation gates, rollback readiness, production deploy rules |
| `agent-monitoring.md` | 23 | Endpoint health probing — 11 service endpoints, latency thresholds, PM2/Altermanager/Prometheus integration |
| `agent-production-stability.md` | 29 | Production health scoring — 7 stability signals, scoring scale (0-100), no auto-intervention rule |
| `agent-repo-audit.md` | 22 | Repo evaluation — 8-step audit checklist, no auto-deploy rule, honest risk flagging |

## Dispatch Mechanism

Templates are loaded via `wheeler-agent` function in `/root/wheeler-command-center/configs/shell/70-wheeler.sh`:

```
wheeler-agent <template> [task description]
```

The function validates template names against a strict regex (`^[a-zA-Z0-9_-]+$`) to prevent path traversal. Templates are dispatched by printing the prompt template with the task description appended.

## Template Structure

The two rebuilt templates (agent-infra, agent-security) follow a consistent structure:
1. **Identity** — Agent role and purpose
2. **Capabilities** — Tools and scope
3. **Task Context** — `{{TASK}}` placeholder for substitution
4. **Execution Protocol** — Step-by-step numbered instructions with specific commands
5. **Output Format** — Predefined markdown table schema
6. **Verification** — Evidence rules, failure handling, scoring
