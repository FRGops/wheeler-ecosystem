#!/usr/bin/env bash
# PostToolUse Hook — Log tool activity safely
# Appends to agent activity log. Never prints secrets.

LOG_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")/.ai/reports"
LOG_FILE="$LOG_DIR/agent-activity.log"

mkdir -p "$LOG_DIR"

# Read stdin JSON and extract tool_name (Claude Code hook protocol)
INPUT=$(cat 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Log only safe metadata (tool name, time — no args to avoid leaking secrets)
echo "[$TIMESTAMP] tool=$TOOL_NAME" >> "$LOG_FILE"

exit 0
