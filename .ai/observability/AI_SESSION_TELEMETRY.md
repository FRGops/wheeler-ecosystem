# AI Session Telemetry

## Purpose
Track every AI coding session for observability, governance, and continuous improvement. Never track secret values.

## Tracked Fields

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | Unique session identifier |
| `branch` | string | Git branch used |
| `worktree` | string | Worktree path (if any) |
| `tool` | string | Primary tool (claude-code, aider, opencode, roo) |
| `model` | string | Primary model (deepseek-v4, claude-opus-4-7, etc.) |
| `task_classification` | string | micro / small / medium / large / critical |
| `agent_workflow` | string | Which agent workflow was used |
| `files_changed` | number | Count of files modified |
| `lines_changed` | string | +additions / -deletions |
| `gates_run` | array | List of quality gates executed |
| `gates_passed` | number | Count of gates passed |
| `gates_failed` | number | Count of gates failed |
| `failed_commands` | number | Count of command failures |
| `dependency_changes` | boolean | Did dependencies change? |
| `secret_safety_status` | string | clean / warning / blocked |
| `deepseek_routing_touched` | boolean | Was DeepSeek routing modified? |
| `deployment_touched` | boolean | Was deployment performed? |
| `readiness_score` | number | 0-100 score |
| `duration_seconds` | number | Session duration (if known) |

## What We Do NOT Track
- Actual secrets, tokens, or keys
- Contents of .env files
- Personal information
- Production credentials
- Full command output (only success/failure)
- User identity beyond session metadata

## Schema Location
See `AGENT_ACTIVITY_LOG_SCHEMA.md` for the JSON schema.
