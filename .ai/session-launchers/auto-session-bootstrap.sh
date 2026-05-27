#!/usr/bin/env bash
# Auto-Session Bootstrap — called by SessionStart hook
# Boots the Wheeler AI Coding OS. Fails open. Never prints secrets.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
PREFLIGHT="$REPO_ROOT/.ai/session-launchers/preflight-ai-session.sh"

echo "============================================"
echo " Wheeler AI Coding OS — Auto-Bootstrap"
echo " Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"

# Verify critical files exist
CRITICAL_FILES=(
  "CLAUDE.md"
  "AGENTS.md"
  ".ai/INDEX.md"
  ".ai/model-routing/DEEPSEEK_V4_PRIMARY_POLICY.md"
  ".ai/model-routing/MODEL_ROUTING_DECISION_MATRIX.md"
  ".ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md"
  ".ai/subagents/BUILD_PIPELINE.md"
  ".ai/autonomy/AUTONOMOUS_BUILD_PIPELINE.md"
  ".ai/capabilities/DYNAMIC_CAPABILITY_MATCHER.md"
)

MISSING=0
for f in "${CRITICAL_FILES[@]}"; do
  if [ -f "$REPO_ROOT/$f" ]; then
    echo "  [OK] $f"
  else
    echo "  [MISSING] $f"
    MISSING=$((MISSING + 1))
  fi
done

if [ "$MISSING" -gt 0 ]; then
  echo ""
  echo "WARNING: $MISSING critical file(s) missing."
  echo "The Wheeler AI Coding OS may not be fully initialized."
  echo "Run the finalization pass to complete setup."
fi

echo ""

# Run preflight if available
if [ -f "$PREFLIGHT" ] && [ -x "$PREFLIGHT" ]; then
  bash "$PREFLIGHT" || echo "Preflight completed with warnings"
else
  echo "Preflight script not found — skipping"
fi

# ── Repo Listener auto-start ──
REPO_LISTENER="/root/scripts/repo-listener.sh"
if [ -f "$REPO_LISTENER" ] && [ -x "$REPO_LISTENER" ]; then
  if command -v pm2 &>/dev/null; then
    if pm2 list 2>/dev/null | grep -q "repo-listener"; then
      echo "  [OK] repo-listener (PM2 daemon) — real-time repo detection active"
    else
      pm2 start "$REPO_LISTENER" --name repo-listener --interpreter bash -- --daemon 2>/dev/null && \
        echo "  [OK] repo-listener started" || echo "  [WARN] repo-listener start failed"
    fi
  fi
fi

# ── Run capability discovery scanner ──
CAPABILITY_SCANNER="$REPO_ROOT/.claude/hooks/capability-scanner.sh"
if [ -f "$CAPABILITY_SCANNER" ] && [ -x "$CAPABILITY_SCANNER" ]; then
  echo ""
  bash "$CAPABILITY_SCANNER" || true
fi

# ── Wheeler Jarvis Command Center health pulse ──
WHEELER_BIN="$HOME/WheelerCommandCenter/bin/wheeler"
if [ -x "$WHEELER_BIN" ]; then
  echo ""
  echo "  ───── WHEELER JARVIS COMMAND CENTER ─────"
  export WHEELER_HOME="$HOME/WheelerCommandCenter"
  export PATH="$WHEELER_HOME/bin:$PATH"
  { "$WHEELER_BIN" health 2>/dev/null || true; } | head -35
  echo "  Type /wheeler for the command center"
  echo "  ─────────────────────────────────────────"
fi

echo ""
echo "============================================"
echo " Bootstrap complete — session ready"
echo " Model routing:      .ai/model-routing/"
echo " Agent deployment:   .ai/subagents/"
echo " Build pipeline:     .ai/subagents/BUILD_PIPELINE.md"
echo " Dynamic discovery:  .ai/capabilities/"
echo " Response contract:  .ai/prompts/"
echo "============================================"
