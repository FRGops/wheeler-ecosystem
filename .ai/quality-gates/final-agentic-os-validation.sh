#!/usr/bin/env bash
# Final Agentic OS Validation Script
# Verifies all critical files exist. Exits nonzero if critical pieces missing.
# NEVER reads secrets. NEVER modifies DeepSeek routing.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")"
REPORT_FILE="$REPO_ROOT/.ai/reports/final-agentic-os-validation-report.md"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

PASS=0
FAIL=0
WARN=0

check_file() {
  local file="$1"
  local critical="${2:-false}"
  if [ -f "$REPO_ROOT/$file" ]; then
    echo "  [PASS] $file"
    PASS=$((PASS + 1))
  else
    if [ "$critical" = "true" ]; then
      echo "  [FAIL] $file — CRITICAL"
      FAIL=$((FAIL + 1))
    else
      echo "  [WARN] $file — non-critical"
      WARN=$((WARN + 1))
    fi
  fi
}

echo "============================================"
echo " Final Agentic OS Validation"
echo " Time: $TIMESTAMP"
echo "============================================"

# Critical files (must exist)
echo ""
echo "--- Critical Files ---"
check_file "CLAUDE.md" true
check_file "AGENTS.md" true
check_file ".ai/INDEX.md" true
check_file ".ai/model-routing/DEEPSEEK_V4_PRIMARY_POLICY.md" true
check_file ".ai/model-routing/MODEL_ROUTING_DECISION_MATRIX.md" true
check_file ".ai/model-routing/ESCALATION_POLICY.md" true
check_file ".ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md" true
check_file ".ai/subagents/ORCHESTRATOR_AGENT.md" true
check_file ".ai/subagents/FINAL_BOSS_REVIEWER_AGENT.md" true
check_file ".ai/autonomy/HUMAN_APPROVAL_GATES.md" true
check_file ".ai/prompts/DEFAULT_FUTURE_AGENT_RESPONSE_CONTRACT.md" true
check_file ".ai/runbooks/ROLLBACK_RUNBOOK.md" true
check_file ".ai/runbooks/BROKEN_DEEPSEEK_ROUTING_DO_NOT_TOUCH_RUNBOOK.md" true

# Important files (should exist, not blocking)
echo ""
echo "--- Important Files ---"
check_file ".ai/session-launchers/preflight-ai-session.sh" false
check_file ".ai/session-launchers/postflight-ai-session.sh" false
check_file ".ai/session-launchers/auto-session-bootstrap.sh" false
check_file ".ai/session-launchers/start-next-safe-ai-session.sh" false
check_file ".ai/session-launchers/start-ai-mission.sh" false
check_file ".ai/session-launchers/summarize-ai-sessions.sh" false
check_file ".ai/quality-gates/final-agentic-os-validation.sh" false
check_file ".ai/autonomy/ARMY_MODE_POLICY.md" false
check_file ".ai/autonomy/AUTONOMY_LEVELS.md" false
check_file ".ai/autonomy/PREFLIGHT_CHECKLIST.md" false
check_file ".ai/autonomy/POSTFLIGHT_CHECKLIST.md" false

echo ""
echo "--- Subagent Templates ---"
for agent in DEEPSEEK_IMPLEMENTER BACKEND_API FRONTEND_UI TEST_QA DEVOPS_SAFETY SECURITY_SECRETS DATABASE DOCS_PLAYBOOK DEPENDENCY_RISK OBSERVABILITY PERFORMANCE ACCESSIBILITY SEO_CONVERSION; do
  check_file ".ai/subagents/${agent}_AGENT.md" false
done

echo ""
echo "--- CI/CD ---"
check_file ".github/workflows/ai-quality-gates.yml" false
check_file ".github/workflows/secret-safety.yml" false
check_file ".github/workflows/dependency-review.yml" false
check_file ".ai/ci/CI_SECURITY_HARDENING_PLAN.md" false

echo ""
echo "--- MCP & Skills ---"
check_file ".ai/mcp/MCP_GOVERNANCE_POLICY.md" false
check_file ".ai/mcp/MCP_SERVER_ALLOWLIST.md" false
check_file ".ai/mcp/MCP_SERVER_DENYLIST.md" false
check_file ".ai/skills/AGENT_SKILLS_REGISTRY.md" false
check_file ".ai/skills/SKILL_CREATION_TEMPLATE.md" false

echo ""
echo "--- Observability ---"
check_file ".ai/observability/AI_SESSION_TELEMETRY.md" false
check_file ".ai/observability/AGENT_ACTIVITY_LOG_SCHEMA.md" false
check_file ".ai/observability/READINESS_SCORE_SCHEMA.md" false

echo ""
echo "--- Evals ---"
for rubric in AI_OUTPUT_EVAL CODE_QUALITY FINAL_BOSS_ACCEPTANCE BUG_REGRESSION UI_UX_ACCEPTANCE API_ACCEPTANCE DEVOPS_ACCEPTANCE; do
  check_file ".ai/evals/${rubric}_RUBRIC.md" false
done

echo ""
echo "--- Runbooks ---"
check_file ".ai/runbooks/AI_SESSION_RECOVERY_RUNBOOK.md" false
check_file ".ai/runbooks/BROKEN_BUILD_RUNBOOK.md" false
check_file ".ai/runbooks/BROKEN_CI_RUNBOOK.md" false

echo ""
echo "--- Hook Scripts ---"
check_file ".claude/hooks/sessionstart-autobootstrap.sh" false
check_file ".claude/hooks/pretooluse-safety.sh" false
check_file ".claude/hooks/posttooluse-log.sh" false
check_file ".claude/hooks/stop-postflight.sh" false

echo ""
echo "--- Prompts ---"
check_file ".ai/prompts/FINALIZE_ANY_BUILD_TASK_100.md" false
check_file ".ai/prompts/RUN_AUTONOMOUS_AGENT_ARMY_100.md" false
check_file ".ai/prompts/SAFE_PARALLEL_TERMINALS_100.md" false
check_file ".ai/prompts/FINAL_BOSS_REVIEW_PROMPT_100.md" false
check_file ".ai/prompts/DEEPSEEK_IMPLEMENTATION_TICKET_PROMPT_100.md" false
check_file ".ai/prompts/PRODUCTION_SAFETY_REVIEW_PROMPT_100.md" false

# Summary
echo ""
echo "============================================"
echo " Validation Summary"
echo " Passed:  $PASS"
echo " Failed:  $FAIL (critical)"
echo " Warnings: $WARN (non-critical)"
echo "============================================"

# Write report
mkdir -p "$(dirname "$REPORT_FILE")"
cat > "$REPORT_FILE" <<EOFREPORT
# Final Agentic OS Validation Report

**Generated**: $TIMESTAMP
**Repository**: $REPO_ROOT

## Results

| Category | Passed | Failed | Warnings |
|----------|--------|--------|----------|
| Critical | $((PASS - WARN)) | $FAIL | — |
| Non-Critical | — | — | $WARN |

## Verdict

EOFREPORT

if [ "$FAIL" -gt 0 ]; then
  echo "**RESULT: FAILED** — $FAIL critical file(s) missing. Do not claim 100/100." >> "$REPORT_FILE"
  echo ""
  echo "RESULT: FAILED — $FAIL critical file(s) missing."
  exit 1
else
  echo "**RESULT: PASSED** — All critical files present. Ready for scoring." >> "$REPORT_FILE"
  echo ""
  echo "RESULT: PASSED — All critical files present."
  exit 0
fi
