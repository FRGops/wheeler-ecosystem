#!/usr/bin/env bash
# Start AI Mission — for complex multi-agent tasks
# Sets up worktree, classifies task, deploys agent army.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
MISSION_NAME="${1:-mission-$(date +%Y%m%d-%H%M)}"
BRANCH_NAME="ai/${MISSION_NAME}"
SESSION_ID="mission-$(date +%Y%m%d-%H%M%S)"

echo "============================================"
echo " Wheeler AI Coding OS — Start AI Mission"
echo " Mission: $MISSION_NAME"
echo " Session: $SESSION_ID"
echo "============================================"

# Create mission branch
git checkout -b "$BRANCH_NAME" 2>/dev/null || echo "Branch $BRANCH_NAME already exists, checking out"
git checkout "$BRANCH_NAME"

# Run preflight
PREFLIGHT="$REPO_ROOT/.ai/session-launchers/preflight-ai-session.sh"
if [ -f "$PREFLIGHT" ] && [ -x "$PREFLIGHT" ]; then
  bash "$PREFLIGHT"
fi

echo ""
echo "--- Mission Brief ---"
echo "Mission:       $MISSION_NAME"
echo "Branch:        $BRANCH_NAME"
echo "Session ID:    $SESSION_ID"
echo ""
echo "Classify this mission (micro/small/medium/large/critical)."
echo "Route agents using: .ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md"
echo "Obey change budget. Run quality gates before completion."
echo ""
echo "Post-mission:"
echo "  1. bash .ai/session-launchers/postflight-ai-session.sh"
echo "  2. Complete 14-point response contract"
echo "  3. Final Boss review (for medium+ missions)"
echo "============================================"
