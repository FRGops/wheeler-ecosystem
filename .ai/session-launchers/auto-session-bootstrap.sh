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

echo "============================================"
echo " Bootstrap complete — session ready"
echo " Model routing matrix: .ai/model-routing/"
echo " Agent deployment matrix: .ai/subagents/"
echo " Response contract: .ai/prompts/"
echo "============================================"
