#!/usr/bin/env bash
# Stop Hook — Postflight + session summary
# Fails open. Never deploys. Never pushes.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
POSTFLIGHT_SCRIPT="$PROJECT_ROOT/.ai/session-launchers/postflight-ai-session.sh"

echo "[Wheeler OS] Stop hook fired — running postflight"

if [ -f "$POSTFLIGHT_SCRIPT" ] && [ -x "$POSTFLIGHT_SCRIPT" ]; then
  bash "$POSTFLIGHT_SCRIPT" || echo "[Wheeler OS] Postflight completed with warnings (non-fatal)"
else
  echo "[Wheeler OS] Postflight script not found — skipping"
fi

echo "[Wheeler OS] Session stop hook complete"

# Always succeed (fail-open)
exit 0
