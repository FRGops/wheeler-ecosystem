#!/usr/bin/env bash
# Summarize AI sessions safely — no secrets, no deploy, no routing changes
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
REPORT_DIR="$REPO_ROOT/.ai/reports/sessions"

echo "============================================"
echo " AI Session Summary"
echo " Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"
echo ""

# Count sessions
if [ -d "$REPORT_DIR" ]; then
  SESSION_COUNT=$(find "$REPORT_DIR" -name "postflight-*.json" 2>/dev/null | wc -l)
  echo "Total sessions tracked: $SESSION_COUNT"
  echo ""

  if [ "$SESSION_COUNT" -gt 0 ]; then
    echo "Recent sessions:"
    find "$REPORT_DIR" -name "postflight-*.json" -type f 2>/dev/null | sort -r | head -10 | while read -r f; do
      SID=$(basename "$f" .json | sed 's/postflight-//')
      PASSES=$(jq -r '.passes // "N/A"' "$f" 2>/dev/null || echo "N/A")
      FAILS=$(jq -r '.fails // "N/A"' "$f" 2>/dev/null || echo "N/A")
      echo "  $SID — passes=$PASSES fails=$FAILS"
    done
  fi
else
  echo "No session reports directory found."
  echo "Run .ai/session-launchers/postflight-ai-session.sh after each session."
fi

echo ""
echo "============================================"
echo " Session log: $REPORT_DIR/agent-activity.log"
echo "============================================"
