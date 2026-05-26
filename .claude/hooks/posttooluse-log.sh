#!/usr/bin/env bash
# PostToolUse Hook — Log tool activity safely
# Appends to agent activity log. Never prints secrets.

LOG_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")/.ai/reports"
LOG_FILE="$LOG_DIR/agent-activity.log"

mkdir -p "$LOG_DIR"

TOOL_NAME="$1"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Log only safe metadata (tool name, time — no args to avoid leaking secrets)
echo "[$TIMESTAMP] tool=$TOOL_NAME" >> "$LOG_FILE"

exit 0
