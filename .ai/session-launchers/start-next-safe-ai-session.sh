#!/usr/bin/env bash
# Start Next Safe AI Session
# Creates a new AI branch, runs preflight, and prints session context.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
SESSION_ID="session-$(date +%Y%m%d-%H%M%S)"
BRANCH_NAME="ai/session-$(date +%Y%m%d-%H%M)"

echo "============================================"
echo " Wheeler AI Coding OS — Start Safe Session"
echo " Session: $SESSION_ID"
echo "============================================"

# Check if on main/master
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "Creating AI branch: $BRANCH_NAME"
  git checkout -b "$BRANCH_NAME"
  echo "Branch created: $BRANCH_NAME"
else
  echo "Already on branch: $CURRENT_BRANCH"
fi

echo ""

# Run preflight
PREFLIGHT="$REPO_ROOT/.ai/session-launchers/preflight-ai-session.sh"
if [ -f "$PREFLIGHT" ] && [ -x "$PREFLIGHT" ]; then
  bash "$PREFLIGHT"
else
  echo "WARNING: Preflight script not found"
fi

echo ""
echo "--- Session Context ---"
echo "Branch:        $(git branch --show-current)"
echo "Session ID:    $SESSION_ID"
echo "Task classify: .ai/model-routing/MODEL_ROUTING_DECISION_MATRIX.md"
echo "Agent matrix:  .ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md"
echo "Response:      .ai/prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md"
echo ""
echo "When done, run: bash .ai/session-launchers/postflight-ai-session.sh"
echo "For no-false-green: bash .ai/quality-gates/no-false-green-check.sh"
echo "============================================"
