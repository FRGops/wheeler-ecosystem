---
name: posttooluse-hook-fix-20260526
description: "PostToolUse hooks fixed to parse stdin JSON for tool_name instead of reading $1 positional arg — Claude Code hook protocol (2026-05-26)"
metadata:
  node_type: memory
  type: project
  originEpoch: 2026-05-26
  originSessionId: session-20260526-065224
---

# PostToolUse Hook Fix — 2026-05-26

## The Bug

Both PostToolUse hooks (`posttooluse-log.sh` and `posttooluse-repo-detect.sh`) were reading `TOOL_NAME="$1"` — a positional argument. Claude Code passes tool data via stdin JSON, not as CLI arguments. The hooks were functionally dead: `"$1"` was always empty, so `posttooluse-log.sh` always logged `tool=unknown` and `posttooluse-repo-detect.sh` never detected GitHub URLs.

## The Fix

Both hooks now read stdin and parse `tool_name` from JSON using Python:

```bash
INPUT=$(cat 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
```

## Files Changed

| File | Lines | Change |
|------|-------|--------|
| `/root/.claude/hooks/posttooluse-log.sh` | 19 | Stdin JSON parsing for `tool_name`; logs `[TIMESTAMP] tool=TOOL_NAME` to agent-activity.log |
| `/root/.claude/hooks/posttooluse-repo-detect.sh` | 48 | Stdin JSON parsing; tool_name filter (WebFetch/WebSearch only); URL extraction from `tool_input` JSON; writes to `/root/.ai/repo-drop-zone.txt` |

## Verification

- `posttooluse-log.sh` now correctly appends tool entries to `.ai/reports/agent-activity.log`
- `posttooluse-repo-detect.sh` only triggers on WebFetch/WebSearch, extracts github.com URLs from tool_input, normalizes (strips trailing slash, .git suffix), and appends to drop zone
- Both exit safely (exit 0) on any parse error — no crash if stdin is empty or malformed

## Safety

- Both hooks log metadata only (tool name, URLs) — never tool arguments or secret values
- Repo detection deduplicates via set() before writing
- Drop zone uses a file-based approach (listener poll for deduplication)
