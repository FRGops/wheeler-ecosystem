# Agent Activity Log Schema

## JSONL Format

Each agent action is one line:

```json
{
  "timestamp": "2026-05-26T01:15:00Z",
  "session_id": "session-20260526-0115",
  "agent": "deepseek-implementer",
  "action": "file_edit",
  "target": "src/app.ts",
  "lines_added": 12,
  "lines_removed": 3,
  "success": true,
  "duration_ms": 450
}
```

## Fields

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `timestamp` | yes | ISO 8601 | When the action occurred |
| `session_id` | yes | string | Session identifier |
| `agent` | yes | string | Agent name from deployment matrix |
| `action` | yes | string | file_edit, file_create, bash_run, test_run, review, escalate |
| `target` | no | string | File or resource acted upon |
| `lines_added` | no | number | Lines added (for edits) |
| `lines_removed` | no | number | Lines removed (for edits) |
| `success` | yes | boolean | Did the action succeed? |
| `duration_ms` | no | number | Action duration in milliseconds |
| `error` | no | string | Error message (if failed) — never include secrets |

## Privacy Rules

- Never log command arguments that may contain secrets
- Never log environment variable values
- Never log file contents — only paths and line counts
- Truncate error messages at 500 characters
