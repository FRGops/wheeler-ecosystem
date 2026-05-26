#!/usr/bin/env bash
# Preflight AI Session — safe read-only checks before coding
# NEVER prints secrets. NEVER modifies model routing. NEVER deploys.

set -euo pipefail

SESSION_ID="session-$(date +%Y%m%d-%H%M%S)"
REPORT_DIR=".ai/reports/sessions"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"

echo "============================================"
echo " Wheeler AI Coding OS — Preflight Check"
echo " Session: $SESSION_ID"
echo " Time:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"
echo ""

# 1. Branch
echo "--- Branch ---"
BRANCH=$(git branch --show-current 2>/dev/null || echo "not-a-git-repo")
echo "Branch: $BRANCH"
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  echo "WARNING: On $BRANCH branch. Consider creating a feature/AI branch."
  echo "  git checkout -b ai/your-task-$(date +%Y%m%d-%H%M)"
fi
echo ""

# 2. Working tree
echo "--- Working Tree ---"
if git diff --quiet 2>/dev/null; then
  echo "Status: clean"
else
  echo "Status: dirty (modified files exist)"
  git diff --stat 2>/dev/null | head -20
fi
echo ""

# 3. DeepSeek presence (no values)
echo "--- DeepSeek V4 Protection ---"
for var in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL DEEPSEEK_API_KEY LITELLM_MASTER_KEY; do
  if [ -n "${!var+x}" ]; then
    echo "  $var=present"
  else
    echo "  $var=MISSING"
  fi
done
echo ""

# 4. Required .ai files
echo "--- Required Files ---"
REQUIRED_FILES=(
  ".ai/INDEX.md"
  ".ai/model-routing/MODEL_ROUTING_DECISION_MATRIX.md"
  ".ai/model-routing/DEEPSEEK_V4_PRIMARY_POLICY.md"
  ".ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md"
)
for f in "${REQUIRED_FILES[@]}"; do
  if [ -f "$REPO_ROOT/$f" ]; then
    echo "  $f: found"
  else
    echo "  $f: MISSING"
  fi
done
echo ""

# 5. Agent locks
echo "--- Agent Locks ---"
if [ -d "$REPO_ROOT/.ai/agent-locks" ]; then
  LOCK_COUNT=$(find "$REPO_ROOT/.ai/agent-locks" -type f 2>/dev/null | wc -l)
  if [ "$LOCK_COUNT" -gt 0 ]; then
    echo "  Found $LOCK_COUNT lock(s):"
    find "$REPO_ROOT/.ai/agent-locks" -type f 2>/dev/null | head -10
  else
    echo "  No stale locks"
  fi
else
  echo "  Lock directory not found (ok on first run)"
fi
echo ""

# 6. Package manager
echo "--- Package Manager ---"
for pm in node npm pnpm yarn bun python3; do
  if command -v "$pm" &>/dev/null; then
    echo "  $pm: $( $pm --version 2>/dev/null | head -1 || echo 'available' )"
  fi
done
echo ""

# 7. Session report directory
echo "--- Session Tracking ---"
mkdir -p "$REPO_ROOT/$REPORT_DIR"
echo "  Report dir: $REPORT_DIR (created if missing)"
echo "  Session ID: $SESSION_ID"
echo ""

# 8. Available quality gates
echo "--- Available Quality Gates ---"
if [ -d "$REPO_ROOT/.ai/quality-gates" ]; then
  find "$REPO_ROOT/.ai/quality-gates" -type f -name "*.sh" 2>/dev/null | while read -r gate; do
    echo "  $(basename "$gate")"
  done
else
  echo "  No quality gates directory found"
fi
echo ""

echo "============================================"
echo " Preflight complete — safe to proceed"
echo " Session ID: $SESSION_ID"
echo "============================================"

# Write session marker
echo "$SESSION_ID" > "$REPO_ROOT/$REPORT_DIR/.current-session"
