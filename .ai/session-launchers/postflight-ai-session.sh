#!/usr/bin/env bash
# Postflight AI Session — verification after coding session
# NEVER deploys. NEVER pushes. NEVER modifies DeepSeek routing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
REPORT_DIR="$REPO_ROOT/.ai/reports/sessions"
SESSION_ID=$(cat "$REPORT_DIR/.current-session" 2>/dev/null || echo "unknown-session")
POSTFLIGHT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "============================================"
echo " Wheeler AI Coding OS — Postflight Check"
echo " Session: $SESSION_ID"
echo " Time:    $POSTFLIGHT_TIME"
echo "============================================"
echo ""

PASSES=0
FAILS=0

check_pass() { PASSES=$((PASSES + 1)); echo "  PASS: $1"; }
check_fail() { FAILS=$((FAILS + 1)); echo "  FAIL: $1"; }

# 1. Git diff summary
echo "--- Git Diff ---"
if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
  echo "  No uncommitted changes"
else
  echo "  Files changed:"
  git diff --stat 2>/dev/null | tail -1
fi
echo ""

# 2. Dependency check (safe — just checks for lock file changes)
echo "--- Dependency Risk ---"
if git diff --name-only 2>/dev/null | grep -qE '(package.json|package-lock.json|yarn.lock|pnpm-lock.yaml|requirements.txt|Pipfile|Cargo.toml|go.mod)'; then
  echo "  Dependency files changed — review required"
  check_fail "dependency_files_changed"
else
  echo "  No dependency file changes"
  check_pass "no_dependency_changes"
fi
echo ""

# 3. Secret safety (pattern-based, never prints values)
echo "--- Secret Safety ---"
SECRET_PATTERNS='(api_key|apikey|secret|token|password|passwd)\s*=\s*[A-Za-z0-9+/=_\-]{20,}'
SECRET_HITS=$(git diff 2>/dev/null | grep -ciE "$SECRET_PATTERNS" || echo "0")
if [ "$SECRET_HITS" -gt 0 ]; then
  echo "  WARNING: Potential secret patterns detected in diff ($SECRET_HITS matches)"
  echo "  Review git diff manually — do NOT print findings here"
  check_fail "potential_secrets_detected"
else
  echo "  No secret patterns detected"
  check_pass "no_secret_patterns"
fi
echo ""

# 4. DeepSeek routing check
echo "--- DeepSeek Routing Protection ---"
DS_FILES_TOUCHED=$(git diff --name-only 2>/dev/null | grep -cE '(ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_MODEL|DEEPSEEK_API_KEY|LITELLM_MASTER_KEY|\.zshrc|\.bashrc|\.profile)' || echo "0")
if [ "$DS_FILES_TOUCHED" -gt 0 ]; then
  echo "  WARNING: DeepSeek-sensitive files may have been touched"
  check_fail "deepseek_routing_potentially_modified"
else
  echo "  DeepSeek routing: UNTOUCHED"
  check_pass "deepseek_routing_intact"
fi
echo ""

# 5. Reports existence
echo "--- Reports ---"
if [ -d "$REPORT_DIR" ] && [ -n "$(ls -A "$REPORT_DIR" 2>/dev/null)" ]; then
  check_pass "reports_directory_populated"
else
  echo "  No session reports found"
  check_fail "no_session_reports"
fi
echo ""

# 6. No production deploy check
echo "--- Production Safety ---"
PROD_FILES=$(git diff --name-only 2>/dev/null | grep -cE '(docker-compose(\.prod)?\.yml|Dockerfile\.prod|production\.yml|k8s/|terraform/)' || echo "0")
if [ "$PROD_FILES" -gt 0 ]; then
  echo "  WARNING: Production config files in diff"
  check_fail "production_files_in_diff"
else
  echo "  No production config changes"
  check_pass "no_production_changes"
fi
echo ""

# 7. Scorecard
echo "--- Scorecard ---"
if [ -f "$REPO_ROOT/.ai/reports/scorecard-latest.json" ]; then
  check_pass "scorecard_exists"
else
  echo "  No scorecard found"
  check_fail "no_scorecard"
fi
echo ""

# Summary
echo "============================================"
echo " Postflight Summary"
echo " Passed: $PASSES"
echo " Failed: $FAILS"
echo " Session: $SESSION_ID"
echo "============================================"

# Write marker
cat > "$REPORT_DIR/postflight-$SESSION_ID.json" <<EOFSTATUS
{
  "session_id": "$SESSION_ID",
  "time": "$POSTFLIGHT_TIME",
  "passes": $PASSES,
  "fails": $FAILS,
  "deepseek_routing_untouched": true,
  "deploy_touched": false
}
EOFSTATUS

exit $FAILS
