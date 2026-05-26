#!/usr/bin/env bash
# No-False-Green Check — verifies that no health/completion claims are unsubstantiated
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"

echo "============================================"
echo " No-False-Green Verification"
echo "============================================"

FAILS=0

# Check: CLAUDE.md exists and has required sections
echo "--- Checking CLAUDE.md completeness ---"
if grep -q "DeepSeek V4 Protection" "$REPO_ROOT/CLAUDE.md" 2>/dev/null; then
  echo "  PASS: DeepSeek protection section present"
else
  echo "  FAIL: Missing DeepSeek protection section"
  FAILS=$((FAILS + 1))
fi

# Check: AGENTS.md exists and has required sections
echo "--- Checking AGENTS.md completeness ---"
if grep -q "UNIVERSAL RULES" "$REPO_ROOT/AGENTS.md" 2>/dev/null; then
  echo "  PASS: Universal rules section present"
else
  echo "  FAIL: Missing universal rules section"
  FAILS=$((FAILS + 1))
fi

# Check: No .env files in recent diff
echo "--- Checking for .env in diff ---"
if git diff --name-only 2>/dev/null | grep -qE '\.env$|\.env\.'; then
  echo "  FAIL: .env files in diff"
  FAILS=$((FAILS + 1))
else
  echo "  PASS: No .env files in diff"
fi

# Check: No secrets/ in diff
echo "--- Checking for secrets/ in diff ---"
if git diff --name-only 2>/dev/null | grep -qE '^secrets/'; then
  echo "  FAIL: secrets/ files in diff"
  FAILS=$((FAILS + 1))
else
  echo "  PASS: No secrets/ files in diff"
fi

# Check: Critical files actually exist (not just claimed)
echo "--- Verifying critical file existence ---"
for f in CLAUDE.md AGENTS.md .ai/INDEX.md; do
  if [ -f "$REPO_ROOT/$f" ]; then
    echo "  PASS: $f exists"
  else
    echo "  FAIL: $f claimed but missing"
    FAILS=$((FAILS + 1))
  fi
done

echo ""
echo "============================================"
if [ "$FAILS" -gt 0 ]; then
  echo " RESULT: $FAILS false green(s) detected"
  exit 1
else
  echo " RESULT: No false greens detected"
  exit 0
fi
