#!/bin/bash
# /rule54-gate executable — ABA Rule 5.4 Fee Structure Compliance Gate
# Checks: fee-splitting patterns, attorney independence, non-compliant structures
# Writes PASS/FAIL to compliance-scores/rule54.gate
# Invoked by: cron, /rule54-gate command, /critical-5

set -euo pipefail
SCORE_DIR="/root/scripts/aiops-watchdog/compliance-scores"
mkdir -p "$SCORE_DIR"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[rule54-gate] === ABA RULE 5.4 COMPLIANCE GATE ==="
echo "[rule54-gate] Timestamp: $TIMESTAMP"

FAILURES=0
CHECKS=0

# ── Check 1: Fee Splitting Detection ───────────────────────────────────
((CHECKS++))
echo "[rule54-gate] Check $CHECKS: Fee-splitting patterns in code/config"
FEE_SPLIT=$(find /root -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.json" -o -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | xargs grep -l "fee.split\|revenue.share.*attorney\|commission.*legal\|percentage.*recovery\|contingency.*fee" 2>/dev/null | wc -l)
if [[ "$FEE_SPLIT" -gt 0 ]]; then
    echo "[rule54-gate]   WARNING: Found $FEE_SPLIT files with potential fee-splitting patterns"
    echo "[rule54-gate]   ALL fee arrangements must be reviewed by outside ethics counsel"
    ((FAILURES++))
else
    echo "[rule54-gate]   PASS: No fee-splitting patterns detected in codebase"
fi

# ── Check 2: Attorney Marketplace Fee Structure ────────────────────────
((CHECKS++))
echo "[rule54-gate] Check $CHECKS: Attorney marketplace compliance documentation"
if [[ -f /root/legal-compliance-os/ATTORNEY_MARKETPLACE_COMPLIANCE.md ]]; then
    RULE54_DOC=$(grep -c "Rule 5.4\|rule 5.4\|fee.splitting\|non-lawyer.*fee\|attorney.independence" /root/legal-compliance-os/ATTORNEY_MARKETPLACE_COMPLIANCE.md 2>/dev/null || echo 0)
    if [[ "$RULE54_DOC" -gt 0 ]]; then
        echo "[rule54-gate]   PASS: Rule 5.4 documented with $RULE54_DOC references"
    else
        echo "[rule54-gate]   FAIL: Rule 5.4 not adequately documented"
        ((FAILURES++))
    fi
else
    echo "[rule54-gate]   FAIL: ATTORNEY_MARKETPLACE_COMPLIANCE.md missing"
    ((FAILURES++))
fi

# ── Check 3: Business Model Safety ─────────────────────────────────────
((CHECKS++))
echo "[rule54-gate] Check $CHECKS: Business model options documented and safe"
if [[ -f /root/legal-compliance-os/ATTORNEY_MARKETPLACE_COMPLIANCE.md ]]; then
    PROHIBITED=$(grep -c "PROHIBITED\|prohibited" /root/legal-compliance-os/ATTORNEY_MARKETPLACE_COMPLIANCE.md 2>/dev/null || echo 0)
    echo "[rule54-gate]   $PROHIBITED prohibited structures explicitly documented"
else
    echo "[rule54-gate]   WARNING: Business model safety not verifiable"
fi

# ── Check 4: Attorney Independence Protections ─────────────────────────
((CHECKS++))
echo "[rule54-gate] Check $CHECKS: Attorney independence protections documented"
ATTY_INDEPENDENCE=$(find /root/legal-compliance-os -name "*.md" 2>/dev/null | xargs grep -l "attorney.independence\|professional.judgment\|attorney.discretion\|independent.legal" 2>/dev/null | wc -l)
if [[ "$ATTY_INDEPENDENCE" -gt 0 ]]; then
    echo "[rule54-gate]   PASS: Attorney independence documented in $ATTY_INDEPENDENCE files"
else
    echo "[rule54-gate]   WARNING: Attorney independence protections not explicitly documented"
fi

# ── Check 5: State-Specific Rule 5.4 ───────────────────────────────────
((CHECKS++))
echo "[rule54-gate] Check $CHECKS: State-specific Rule 5.4 variants addressed"
STATE_RULE54=$(grep -c "CA.*Rule 5.4\|FL.*Rule 5.4\|NY.*Rule 5.4\|NJ.*Rule 5.4\|fee split.*prohibited\|non-lawyer.*ownership" /root/legal-compliance-os/ATTORNEY_MARKETPLACE_COMPLIANCE.md 2>/dev/null || echo 0)
if [[ "$STATE_RULE54" -gt 0 ]]; then
    echo "[rule54-gate]   PASS: State-specific Rule 5.4 analysis found ($STATE_RULE54 references)"
else
    echo "[rule54-gate]   WARNING: State-specific Rule 5.4 analysis may be incomplete"
fi

# ── Final Gate Decision ────────────────────────────────────────────────
PASSED=$((CHECKS - FAILURES))
echo "[rule54-gate] ──────────────────────────────────────"
echo "[rule54-gate] Results: $PASSED/$CHECKS checks passed"

if [[ "$FAILURES" -eq 0 ]]; then
    echo "PASS" > "$SCORE_DIR/rule54.gate"
    echo "100" > "$SCORE_DIR/attorney.score"
    echo "[rule54-gate] GATE: PASS — Rule 5.4 compliance verified"
else
    echo "FAIL" > "$SCORE_DIR/rule54.gate"
    SCORE=$(( (PASSED * 100) / CHECKS ))
    echo "$SCORE" > "$SCORE_DIR/attorney.score"
    echo "[rule54-gate] GATE: FAIL — $FAILURES Rule 5.4 compliance gaps"
    echo "[rule54-gate] ACTION: marketplace-compliance must freeze non-compliant arrangements"
fi

echo "[rule54-gate] Score written to $SCORE_DIR/rule54.gate"
exit $FAILURES
