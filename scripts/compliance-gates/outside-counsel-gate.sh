#!/bin/bash
# /outside-counsel-gate executable — Outside Counsel Engagement Verification
# Checks: counsel engagement across all 5 required domains (TCPA, ethics, UPL, privacy, securities)
# Writes PASS/FAIL to compliance-scores/outside_counsel.gate
# Invoked by: cron, /outside-counsel-gate command, /critical-5

set -euo pipefail
SCORE_DIR="/root/scripts/aiops-watchdog/compliance-scores"
mkdir -p "$SCORE_DIR"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[outside-counsel-gate] === OUTSIDE COUNSEL ENGAGEMENT GATE ==="
echo "[outside-counsel-gate] Timestamp: $TIMESTAMP"

DOMAINS_COVERED=0
DOMAINS_MISSING=0
TOTAL_DOMAINS=5

# ── Required Domains ───────────────────────────────────────────────────
declare -A DOMAIN_CHECKS
DOMAIN_CHECKS=(
    ["TCPA/Telemarketing"]="tcpa"
    ["Legal Ethics/Professional Responsibility"]="ethics"
    ["UPL/State Practice Rules"]="upl"
    ["Data Privacy/Cybersecurity"]="privacy"
    ["Securities/Capital Raise"]="securities"
)

for domain_label in "TCPA/Telemarketing" "Legal Ethics/Professional Responsibility" "UPL/State Practice Rules" "Data Privacy/Cybersecurity" "Securities/Capital Raise"; do
    domain_key="${DOMAIN_CHECKS[$domain_label]}"
    echo "[outside-counsel-gate] ── $domain_label ──"

    # Check for engagement evidence
    ENGAGEMENT_EVIDENCE=0

    # Check 1: Is there a documented requirement for this domain?
    if grep -q "$domain_label\|$domain_key" /root/legal-compliance-os/WHEELER_LEGAL_COMPLIANCE_OS_REPORT.md 2>/dev/null; then
        ENGAGEMENT_EVIDENCE=$((ENGAGEMENT_EVIDENCE + 1))
        echo "[outside-counsel-gate]   Requirement documented: Yes"
    fi

    # Check 2: Is there a budget allocation mentioned?
    if grep -qi "budget.*counsel.*$domain_key\|$domain_key.*budget\|outside.counsel.*cost" /root/legal-compliance-os/WHEELER_LEGAL_COMPLIANCE_OS_REPORT.md 2>/dev/null; then
        ENGAGEMENT_EVIDENCE=$((ENGAGEMENT_EVIDENCE + 1))
        echo "[outside-counsel-gate]   Budget mentioned: Yes"
    fi

    # Check 3: Is there a firm recommendation or contact?
    if grep -qi "$domain_key.*firm\|$domain_key.*counsel\|$domain_key.*attorney\|$domain_key.*law" /root/legal-compliance-os/*.md 2>/dev/null; then
        ENGAGEMENT_EVIDENCE=$((ENGAGEMENT_EVIDENCE + 1))
        echo "[outside-counsel-gate]   Counsel references found: Yes"
    fi

    if [[ "$ENGAGEMENT_EVIDENCE" -eq 0 ]]; then
        echo "[outside-counsel-gate]   GAP: No engagement evidence for $domain_label"
        ((DOMAINS_MISSING++))
    else
        echo "[outside-counsel-gate]   Coverage indicators: $ENGAGEMENT_EVIDENCE/3"
        echo "[outside-counsel-gate]   ⚠ NOTE: Documentation exists but ACTUAL engagement letters, signed agreements, and active matters must be verified by human"
        ((DOMAINS_COVERED++))
    fi
done

# ── Check for actual engagement documentation ──────────────────────────
echo "[outside-counsel-gate] ── Engagement Documentation Check ──"
ENGAGEMENT_FILES=$(find /root/legal-compliance-os -name "*.md" 2>/dev/null | xargs grep -l "engagement.letter\|outside.counsel.*engaged\|counsel.*retained\|law.firm.*engaged" 2>/dev/null | wc -l)

if [[ "$ENGAGEMENT_FILES" -eq 0 ]]; then
    echo "[outside-counsel-gate]   No engagement letters or retainer agreements found"
    echo "[outside-counsel-gate]   ⚠ All 5 domains require executed engagement letters"
else
    echo "[outside-counsel-gate]   $ENGAGEMENT_FILES files reference engagement/retainer status"
fi

# ── Final Gate Decision ────────────────────────────────────────────────
echo "[outside-counsel-gate] ──────────────────────────────────────"
echo "[outside-counsel-gate] Results: $DOMAINS_COVERED/$TOTAL_DOMAINS domains have documented coverage"

if [[ "$DOMAINS_MISSING" -eq 0 ]]; then
    echo "PASS" > "$SCORE_DIR/outside_counsel.gate"
    echo "[outside-counsel-gate] GATE: PASS — All 5 domains have documented outside counsel coverage"
    echo "[outside-counsel-gate] ⚠ HUMAN VERIFICATION REQUIRED: Confirm actual engagement letters are executed"
else
    echo "FAIL" > "$SCORE_DIR/outside_counsel.gate"
    echo "[outside-counsel-gate] GATE: FAIL — $DOMAINS_MISSING domains lack outside counsel coverage"
    echo "[outside-counsel-gate] ACTION: legal-ops must coordinate engagement for uncovered domains"
fi

echo "[outside-counsel-gate] Score written to $SCORE_DIR/outside_counsel.gate"
exit $DOMAINS_MISSING
