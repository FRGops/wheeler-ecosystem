# Hooks Install and Rollback Guide

## How to Install Project-Level Hooks

Project-level hooks live in `.claude/settings.json` in the repo root. They **merge** with your user-level `~/.claude/settings.json` — they do NOT overwrite it.

### Installation

1. Open or create `.claude/settings.json` in your project root
2. Copy the `hooks` block from `.ai/claude/PROJECT_HOOKS_TEMPLATE_SETTINGS.json`
3. Merge it into your existing settings (if any)

```json
{
  "hooks": {
    "SessionStart": [...],
    "PreToolUse": [...],
    "PostToolUse": [...],
    "Stop": [...]
  }
}
```

### How Hooks Work

| Hook | When | Purpose |
|------|------|---------|
| SessionStart | Session begins | Auto-bootstrap Wheeler OS |
| PreToolUse | Before each tool | Block destructive/unsafe operations |
| PostToolUse | After each tool | Log activity |
| Stop | Session ends | Run postflight checks |

### Safety: All Hooks Fail Open

If any hook script fails or times out, the session continues. Hooks are **advisory** — they warn but never block the session start/stop.

The PreToolUse hook is the exception — it can block specific dangerous tool calls.

## Rollback — How to Disable Hooks

### Option 1: Remove project hooks
```bash
# Remove hooks section from project settings
# Edit .claude/settings.json and delete the "hooks" key
```

### Option 2: Disable via env var
```bash
export CLAUDE_CODE_DISABLE_HOOKS=1
```

### Option 3: Remove hook scripts
```bash
mv .claude/hooks .claude/hooks.disabled
```

### Verify Hooks Are Disabled
Check that no hook scripts fire on session start/stop.

## DeepSeek Protection
**None of these hooks modify DeepSeek routing, env vars, or proxy configs.** They only read presence of env vars (not values) for verification purposes.
