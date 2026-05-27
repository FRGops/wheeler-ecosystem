#!/usr/bin/env bash
# SessionStart Hook — Auto-bootstrap Wheeler AI Coding OS
# Fails open (never blocks session start). Never prints secrets.
# Never modifies DeepSeek routing.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
BOOTSTRAP_SCRIPT="$PROJECT_ROOT/.ai/session-launchers/auto-session-bootstrap.sh"

echo "[Wheeler OS] SessionStart hook fired"

# Run auto-bootstrap if present
if [ -f "$BOOTSTRAP_SCRIPT" ] && [ -x "$BOOTSTRAP_SCRIPT" ]; then
  bash "$BOOTSTRAP_SCRIPT" || echo "[Wheeler OS] Bootstrap completed with warnings (non-fatal)"
else
  echo "[Wheeler OS] Bootstrap script not found or not executable — skipping"
fi

# ── PM2 state persistence (v2.2) ──
pm2 save --force --silent 2>/dev/null && echo "  [OK] PM2 state saved for session" || echo "  [WARN] PM2 save skipped (non-fatal)"

# Always succeed (fail-open)
exit 0
