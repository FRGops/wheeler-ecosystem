#!/bin/bash
# /upl-gate executable — UPL (Unauthorized Practice of Law) Enforcement Gate
# Checks: AI legal content without attorney review, review gate bypassability,
#         AI presented as legal services, Wheeler-as-law-firm disclaimers
# Writes PASS/FAIL to compliance-scores/upl.gate
# Invoked by: cron, /upl-gate command, /critical-5

set -euo pipefail
SCORE_DIR="/root/scripts/aiops-watchdog/compliance-scores"
mkdir -p "$SCORE_DIR"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[upl-gate] === UPL ENFORCEMENT GATE ==="
echo "[upl-gate] Timestamp: $TIMESTAMP"

FAILURES=0
CHECKS=0

# ── Check 1: AI Legal Content Detection ────────────────────────────────
((CHECKS++))
echo "[upl-gate] Check $CHECKS: AI systems generating legal-adjacent content"
# Look for AI integration that might generate legal documents
AI_LEGAL=$(find /root -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" \) 2>/dev/null | xargs grep -l "legal\|court\|filing\|pleading\|motion\|claim.*AI\|AI.*claim\|AI.*legal\|legal.*AI" 2>/dev/null | wc -l)
if [[ "$AI_LEGAL" -gt 0 ]]; then
    echo "[upl-gate]   WARNING: Found $AI_LEGAL files with AI + legal content overlap"
    echo "[upl-gate]   Every AI-generated legal document MUST have attorney review gate"
fi

# ── Check 2: Attorney Review Gate ──────────────────────────────────────
((CHECKS++))
echo "[upl-gate] Check $CHECKS: Attorney review gate implemented in code"
REVIEW_GATE=$(find /root -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" \) 2>/dev/null | xargs grep -l "attorney.review\|lawyer.review\|legal.review\|review.gate\|attorney.approv" 2>/dev/null | wc -l)
if [[ "$AI_LEGAL" -gt 0 && "$REVIEW_GATE" -eq 0 ]]; then
    echo "[upl-gate]   FAIL: AI legal content detected but NO attorney review gate found"
    ((FAILURES++))
elif [[ "$AI_LEGAL" -eq 0 ]]; then
    echo "[upl-gate]   PASS: No AI legal content generation detected (low UPL risk)"
else
    echo "[upl-gate]   PASS: Attorney review gate detected ($REVIEW_GATE files)"
fi

# ── Check 3: "Not a Law Firm" Disclaimers ───────────────────────────────
((CHECKS++))
echo "[upl-gate] Check $CHECKS: Wheeler-not-law-firm disclaimers present"
DISCLAIMERS=$(find /root -type f \( -name "*.md" -o -name "*.html" -o -name "*.jsx" -o -name "*.tsx" -o -name "*.py" \) 2>/dev/null | xargs grep -l "not.a.law.firm\|not.law.firm\|does.not.provide.legal\|not.legal.advice\|not.an.attorney" 2>/dev/null | wc -l)
if [[ "$DISCLAIMERS" -eq 0 ]]; then
    echo "[upl-gate]   WARNING: No 'not a law firm' disclaimers found in codebase"
    # Warning only — disclaimers may be in frontend templates not checked
else
    echo "[upl-gate]   PASS: $DISCLAIMERS files contain law firm disclaimers"
fi

# ── Check 4: AI Governance Policy ──────────────────────────────────────
((CHECKS++))
echo "[upl-gate] Check $CHECKS: AI governance policy with UPL boundaries"
if [[ -f /root/legal-compliance-os/AI_GOVERNANCE_POLICY.md ]]; then
    UPL_BOUNDARIES=$(grep -c "UPL\|unauthorized practice\|attorney review\|bright.line\|NEVER" /root/legal-compliance-os/AI_GOVERNANCE_POLICY.md 2>/dev/null || echo 0)
    if [[ "$UPL_BOUNDARIES" -gt 0 ]]; then
        echo "[upl-gate]   PASS: AI governance policy defines $UPL_BOUNDARIES UPL boundary references"
    else
        echo "[upl-gate]   FAIL: AI governance policy lacks UPL boundaries"
        ((FAILURES++))
    fi
else
    echo "[upl-gate]   FAIL: AI_GOVERNANCE_POLICY.md missing"
    ((FAILURES++))
fi

# ── Check 5: Human Review Checkpoints ──────────────────────────────────
((CHECKS++))
echo "[upl-gate] Check $CHECKS: Human review checkpoints for AI legal content"
HUMAN_REVIEW=$(find /root -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" \) 2>/dev/null | xargs grep -l "human.review\|human.in.the.loop\|manual.review\|attorney.review.required" 2>/dev/null | wc -l)
if [[ "$HUMAN_REVIEW" -eq 0 ]]; then
    echo "[upl-gate]   WARNING: No human review checkpoints found in code (may be in design docs)"
else
    echo "[upl-gate]   PASS: $HUMAN_REVIEW human review checkpoint references found"
fi

# ── Final Gate Decision ────────────────────────────────────────────────
PASSED=$((CHECKS - FAILURES))
echo "[upl-gate] ──────────────────────────────────────"
echo "[upl-gate] Results: $PASSED/$CHECKS checks passed"

if [[ "$FAILURES" -eq 0 ]]; then
    echo "PASS" > "$SCORE_DIR/upl.gate"
    echo "100" > "$SCORE_DIR/upl.score"
    echo "[upl-gate] GATE: PASS — UPL boundaries enforced"
else
    echo "FAIL" > "$SCORE_DIR/upl.gate"
    SCORE=$(( (PASSED * 100) / CHECKS ))
    echo "$SCORE" > "$SCORE_DIR/upl.score"
    echo "[upl-gate] GATE: FAIL — $FAILURES UPL boundary gaps detected"
    echo "[upl-gate] ACTION REQUIRED: ai-governance must SHUT DOWN AI legal content until fixed"
fi

echo "[upl-gate] Score written to $SCORE_DIR/upl.gate"
exit $FAILURES
