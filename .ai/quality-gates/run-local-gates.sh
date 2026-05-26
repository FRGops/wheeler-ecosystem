#!/usr/bin/env bash
# Run Local Gates — executes all available quality gate scripts
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
GATES_DIR="$REPO_ROOT/.ai/quality-gates"

TOTAL=0
PASSED=0
FAILED=0

echo "============================================"
echo " Running Local Quality Gates"
echo "============================================"
echo ""

SELF=$(basename "$0")

for gate in "$GATES_DIR"/*.sh; do
  [ -f "$gate" ] || continue
  GATE_NAME=$(basename "$gate")
  # Skip self to avoid infinite recursion
  [ "$GATE_NAME" = "$SELF" ] && continue
  TOTAL=$((TOTAL + 1))

  echo "--- $GATE_NAME ---"
  if bash "$gate" 2>&1; then
    PASSED=$((PASSED + 1))
    echo "  RESULT: PASS"
  else
    FAILED=$((FAILED + 1))
    echo "  RESULT: FAIL"
  fi
  echo ""
done

echo "============================================"
echo " Gates Summary"
echo " Total:  $TOTAL"
echo " Passed: $PASSED"
echo " Failed: $FAILED"
echo "============================================"

exit $FAILED
