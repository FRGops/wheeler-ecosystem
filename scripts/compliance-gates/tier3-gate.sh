#!/bin/bash
# /tier3-gate executable — Tier 3 State Operations Pause Gate
# Checks: Active claims in CA, FL, LA, MA, NJ, NY without attorney-driven structure
# Writes PASS/FAIL to compliance-scores/tier3.gate
# Invoked by: cron, /tier3-gate command, /critical-5

set -euo pipefail
SCORE_DIR="/root/scripts/aiops-watchdog/compliance-scores"
mkdir -p "$SCORE_DIR"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[tier3-gate] === TIER 3 STATE OPERATIONS GATE ==="
echo "[tier3-gate] Timestamp: $TIMESTAMP"

TIER3_STATES=("CA" "FL" "LA" "MA" "NJ" "NY")
STATES_CLEAR=0
STATES_VIOLATING=0

# ── Tier 3 State Definitions ───────────────────────────────────────────
declare -A TIER3_RESTRICTIONS
TIER3_RESTRICTIONS=(
    ["CA"]="Finder fee prohibition, strict UPL — Attorney of record required"
    ["FL"]="Strict UPL, no non-attorney filings — Attorney of record required"
    ["LA"]="Civil law jurisdiction, unique rules — LA-licensed attorney required"
    ["MA"]="Aggressive AG enforcement — Attorney-driven model required"
    ["NJ"]="Categorical fee split ban — Attorney of record required"
    ["NY"]="Strict referral fee limits — NY-licensed attorney required"
)

for state in "${TIER3_STATES[@]}"; do
    echo "[tier3-gate] ── $state: ${TIER3_RESTRICTIONS[$state]} ──"

    VIOLATIONS=0

    # Check 1: Any operational config referencing this state?
    STATE_REFS=$(find /root -type f \( -name "*.py" -o -name "*.js" -o -name "*.json" -o -name "*.yml" -o -name "*.env" -o -name "*.config*" \) 2>/dev/null | xargs grep -l "\"$state\"\|'$state'\|\b$state\b" 2>/dev/null | grep -v "legal-compliance-os\|node_modules\|\.git" | wc -l)

    if [[ "$STATE_REFS" -gt 10 ]]; then
        echo "[tier3-gate]   WARNING: $STATE_REFS operational files reference $state"
        echo "[tier3-gate]   VERIFY: No active claims without attorney-driven structure"
    else
        echo "[tier3-gate]   Low operational references to $state ($STATE_REFS files)"
    fi

    # Check 2: State-specific compliance documented?
    if grep -q "$state" /root/legal-compliance-os/STATE_COMPLIANCE_MATRIX.md 2>/dev/null; then
        echo "[tier3-gate]   State compliance matrix entry: Found"
    else
        echo "[tier3-gate]   FAIL: $state not in compliance matrix"
        ((VIOLATIONS++))
    fi

    # Check 3: Attorney requirement documented?
    if grep -qi "$state.*attorney\|attorney.*$state" /root/legal-compliance-os/ATTORNEY_REQUIREMENT_MAP.md 2>/dev/null; then
        echo "[tier3-gate]   Attorney requirement documented: Yes"
    else
        echo "[tier3-gate]   WARNING: Attorney requirement for $state not clearly documented"
    fi

    if [[ "$VIOLATIONS" -eq 0 ]]; then
        echo "[tier3-gate]   STATUS: DOCUMENTED — requires attorney-driven structure"
        ((STATES_CLEAR++))
    else
        echo "[tier3-gate]   STATUS: VIOLATING — $VIOLATIONS compliance gaps"
        ((STATES_VIOLATING++))
    fi
done

# ── Final Gate Decision ────────────────────────────────────────────────
echo "[tier3-gate] ──────────────────────────────────────"
echo "[tier3-gate] Results: $STATES_CLEAR/${#TIER3_STATES[@]} states documented, $STATES_VIOLATING with gaps"

if [[ "$STATES_VIOLATING" -eq 0 ]]; then
    echo "PASS" > "$SCORE_DIR/tier3.gate"
    echo "[tier3-gate] GATE: CONDITIONAL PASS — All 6 Tier 3 states have documented requirements"
    echo "[tier3-gate] ⚠ HUMAN VERIFICATION REQUIRED: Confirm 0 active claims without attorney structure"
else
    echo "FAIL" > "$SCORE_DIR/tier3.gate"
    echo "[tier3-gate] GATE: FAIL — $STATES_VIOLATING Tier 3 states have compliance gaps"
    echo "[tier3-gate] ACTION: state-rules + surplus-funds-compliance must pause operations in violating states"
fi

echo "[tier3-gate] Score written to $SCORE_DIR/tier3.gate"
exit $STATES_VIOLATING
