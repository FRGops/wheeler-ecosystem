#!/usr/bin/env bash
# Always-On Policy Check — verifies the Wheeler AI Coding OS is wired for auto-activation
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
FAILS=0

echo "============================================"
echo " Always-On Policy Check"
echo "============================================"

# Check CLAUDE.md boots the OS
echo "--- CLAUDE.md ---"
if grep -q "AUTO-BOOTSTRAP" "$REPO_ROOT/CLAUDE.md" 2>/dev/null; then
  echo "  PASS: Auto-bootstrap section present"
else
  echo "  FAIL: No auto-bootstrap section"
  FAILS=$((FAILS + 1))
fi

# Check AGENTS.md applies to all agents
echo "--- AGENTS.md ---"
if grep -q "ALL coding agents" "$REPO_ROOT/AGENTS.md" 2>/dev/null; then
  echo "  PASS: Applies to all agents"
else
  echo "  FAIL: Missing universal scope"
  FAILS=$((FAILS + 1))
fi

# Check hooks exist
echo "--- Hooks ---"
for hook in sessionstart-autobootstrap pretooluse-safety posttooluse-log stop-postflight; do
  if [ -f "$REPO_ROOT/.claude/hooks/${hook}.sh" ]; then
    echo "  PASS: ${hook}.sh"
  else
    echo "  FAIL: ${hook}.sh missing"
    FAILS=$((FAILS + 1))
  fi
done

# Check session launchers exist
echo "--- Session Launchers ---"
for script in preflight-ai-session postflight-ai-session auto-session-bootstrap; do
  if [ -f "$REPO_ROOT/.ai/session-launchers/${script}.sh" ]; then
    echo "  PASS: ${script}.sh"
  else
    echo "  FAIL: ${script}.sh missing"
    FAILS=$((FAILS + 1))
  fi
done

# Check DeepSeek protection
echo "--- DeepSeek Protection ---"
if grep -q "NEVER.*modify.*ANTHROPIC_BASE_URL" "$REPO_ROOT/CLAUDE.md" 2>/dev/null; then
  echo "  PASS: DeepSeek protection in CLAUDE.md"
else
  echo "  FAIL: Missing DeepSeek protection"
  FAILS=$((FAILS + 1))
fi

echo ""
echo "============================================"
if [ "$FAILS" -gt 0 ]; then
  echo " RESULT: $FAILS policy gap(s) found"
  exit 1
else
  echo " RESULT: Always-on policy intact"
  exit 0
fi
