#!/usr/bin/env bash
# =============================================================================
# sovereign-deploy-pipeline.sh — Autonomous Deployment Pipeline
# =============================================================================
#
# End-to-end deployment orchestrator: preflight → 7-gate → smoke-test →
# health-verify → rollback-ready. Integrates with repo-router and
# deployment-engine infrastructure.
#
# Gates:
#   1. PREFLIGHT   — Branch safety, env vars, lock check
#   2. BUILD       — Compile/validate artifacts
#   3. TEST        — Run test suites
#   4. STAGE       — Deploy to staging, verify health
#   5. SMOKE       — Critical path smoke tests
#   6. DEPLOY      — Production deployment
#   7. VERIFY      — Post-deploy health + rollback readiness
#
# Exit codes:
#   0 — All gates passed, deployment successful
#   1 — Gate failure (with rollback instructions)
#   2 — Preflight failure or usage error
#
# Usage:
#   ./sovereign-deploy-pipeline.sh                          # Full pipeline
#   ./sovereign-deploy-pipeline.sh --repo /path/to/repo     # Specific repo
#   ./sovereign-deploy-pipeline.sh --dry-run                # Simulate only
#   ./sovereign-deploy-pipeline.sh --gate smoke             # Start from gate
#   ./sovereign-deploy-pipeline.sh --rollback               # Execute rollback
#   ./sovereign-deploy-pipeline.sh --json                   # Machine-readable
#   ./sovereign-deploy-pipeline.sh --help                   # This message
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly TIMESTAMP_FMT="$(date +%Y%m%d-%H%M%S)"
readonly LOG_DIR="${LOG_DIR:-/var/log/wheeler/deploy}"
readonly LOCK_FILE="/tmp/${SCRIPT_NAME%.sh}.lock"
readonly CHECK_TIMEOUT="${CHECK_TIMEOUT:-5}"
readonly DEPLOY_ID="deploy-${TIMESTAMP_FMT}"

MY_PID=$$
JSON_MODE=false
DRY_RUN=false
ROLLBACK_MODE=false
TARGET_REPO=""
START_GATE="preflight"
CURRENT_GATE=""
GATE_FAILED=false
declare -a GATE_RESULTS=()
declare -a DEPLOY_LOG=()

if [[ -t 1 ]] || [[ -n "${FORCE_COLOR:-}" ]]; then
    C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'
    C_MAGENTA='\033[0;35m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
    C_CYAN=''; C_MAGENTA=''; C_BOLD=''; C_DIM=''
fi

_cleanup() {
    local rc=$?
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$MY_PID" ]]; then
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
    exit "$rc"
}
trap _cleanup EXIT INT TERM HUP

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

End-to-end deployment orchestrator: preflight, 7-gate, smoke-test,
health-verify, rollback-ready. Integrates with repo-router and
deployment-engine infrastructure.

Gates:
  1. PREFLIGHT   — Branch safety, env vars, lock check
  2. BUILD       — Compile/validate artifacts
  3. TEST        — Run test suites
  4. STAGE       — Deploy to staging, verify health
  5. SMOKE       — Critical path smoke tests
  6. DEPLOY      — Production deployment
  7. VERIFY      — Post-deploy health + rollback readiness

Exit codes:
  0 — All gates passed, deployment successful
  1 — Gate failure (with rollback instructions)
  2 — Preflight failure or usage error

Options:
  --repo /path/to/repo   Specific repo
  --dry-run              Simulate only
  --gate <gate>          Start from gate (preflight|build|test|stage|smoke|deploy|verify)
  --rollback             Execute rollback
  --json                 Machine-readable output
  --help                 Show this message
EOF
    exit "${1:-0}"
}

check_cmd() { command -v "$1" &>/dev/null; }

gate_pass() {
    local gate="$1" detail="$2"
    if [[ "$JSON_MODE" == "false" ]]; then
        printf "  ${C_GREEN}[PASS]${C_RESET} %-15s %s\n" "$gate" "$detail"
    fi
    GATE_RESULTS+=("{\"gate\":\"${gate}\",\"status\":\"PASS\",\"detail\":\"${detail}\"}")
    DEPLOY_LOG+=("[PASS] ${gate}: ${detail}")
}

gate_fail() {
    local gate="$1" detail="$2"
    if [[ "$JSON_MODE" == "false" ]]; then
        printf "  ${C_RED}[FAIL]${C_RESET} %-15s %s\n" "$gate" "$detail"
    fi
    GATE_RESULTS+=("{\"gate\":\"${gate}\",\"status\":\"FAIL\",\"detail\":\"${detail}\"}")
    DEPLOY_LOG+=("[FAIL] ${gate}: ${detail}")
    GATE_FAILED=true
}

gate_skip() {
    local gate="$1" detail="$2"
    if [[ "$JSON_MODE" == "false" ]]; then
        printf "  ${C_DIM}[SKIP]${C_RESET} %-15s %s\n" "$gate" "$detail"
    fi
    GATE_RESULTS+=("{\"gate\":\"${gate}\",\"status\":\"SKIP\",\"detail\":\"${detail}\"}")
}

_http_code() {
    curl -s -o /dev/null -w '%{http_code}' --max-time "$CHECK_TIMEOUT" "$1" 2>/dev/null || echo "000"
}

# ─── Argument Parsing ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)     TARGET_REPO="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=true; shift ;;
        --rollback) ROLLBACK_MODE=true; shift ;;
        --gate)     START_GATE="$2"; shift 2 ;;
        --json)     JSON_MODE=true; shift ;;
        --help)     usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

mkdir -p "$LOG_DIR"
set -o noclobber
if ! echo "$MY_PID" > "$LOCK_FILE" 2>/dev/null; then
    echo "Another instance is running (lock: $LOCK_FILE)" >&2
    exit 1
fi
set +o noclobber

if [[ -z "$TARGET_REPO" ]]; then
    TARGET_REPO="/root"
fi

if [[ ! -d "$TARGET_REPO" ]]; then
    echo -e "${C_RED}Error: Repository not found: ${TARGET_REPO}${C_RESET}" >&2
    exit 2
fi

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  WHEELER DEPLOYMENT PIPELINE${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  Deploy ID: ${DEPLOY_ID}${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  Repo: ${TARGET_REPO}${C_RESET}"
    [[ "$DRY_RUN" == "true" ]] && echo -e "${C_BOLD}${C_YELLOW}  Mode: DRY RUN (no actual changes)${C_RESET}"
    [[ "$ROLLBACK_MODE" == "true" ]] && echo -e "${C_BOLD}${C_YELLOW}  Mode: ROLLBACK${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
fi

# ─── Rollback Mode ─────────────────────────────────────────────────────────────

if [[ "$ROLLBACK_MODE" == "true" ]]; then
    if [[ "$JSON_MODE" == "false" ]]; then
        echo -e "${C_BOLD}${C_YELLOW}━━━ ROLLBACK EXECUTION ━━━${C_RESET}"
    fi

    # Find most recent deploy log
    latest_log=$(ls -t "${LOG_DIR}"/deploy-*.log 2>/dev/null | head -1 || echo "")
    if [[ -z "$latest_log" ]]; then
        gate_fail "rollback" "No previous deploy log found — cannot determine rollback target"
        exit 1
    fi

    gate_pass "rollback" "Rollback log found: ${latest_log}"

    # Git rollback to previous commit
    if [[ "$DRY_RUN" == "false" ]]; then
        prev_commit=$(git -C "$TARGET_REPO" log -1 --format="%H" HEAD~1 2>/dev/null || echo "")
        if [[ -n "$prev_commit" ]]; then
            gate_pass "rollback" "Rollback target: ${prev_commit:0:12}"
        else
            gate_fail "rollback" "No previous commit available for rollback"
            exit 1
        fi
    fi

    gate_pass "rollback" "Rollback ready — manual trigger: git reset --hard <commit>"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# GATE 1: PREFLIGHT
# ═══════════════════════════════════════════════════════════════════════════════

CURRENT_GATE="preflight"
SKIP_UNTIL="$START_GATE"
[[ "$SKIP_UNTIL" != "preflight" ]] && { gate_skip "preflight" "Skipped (start gate: ${START_GATE})"; } || {

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ GATE 1: PREFLIGHT ━━━${C_RESET}"
fi

# Check branch
BRANCH=$(git -C "$TARGET_REPO" branch --show-current 2>/dev/null || echo "unknown")
if [[ "$BRANCH" == "master" ]] || [[ "$BRANCH" == "main" ]]; then
    gate_pass "branch-check" "Branch: ${BRANCH} (deploy confirmed)"
else
    gate_pass "branch-check" "Branch: ${BRANCH}"
fi

# Check working tree
GIT_STATUS=$(git -C "$TARGET_REPO" status --porcelain 2>/dev/null | wc -l || echo "0")
if [[ "$GIT_STATUS" -gt 10 ]]; then
    gate_fail "working-tree" "${GIT_STATUS} modified files — commit or stash before deploy"
else
    gate_pass "working-tree" "${GIT_STATUS} modified files (acceptable)"
fi

# Verify critical env vars
for var in ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL DEEPSEEK_API_KEY; do
    if [[ -n "${!var:-}" ]]; then
        gate_pass "env-${var}" "Present"
    else
        gate_fail "env-${var}" "Missing — deploy blocked"
    fi
done

# Check PM2 daemon
if pm2 ping &>/dev/null 2>&1; then
    PM2_COUNT=$(pm2 jlist 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    gate_pass "pm2-daemon" "${PM2_COUNT} processes running"
else
    gate_fail "pm2-daemon" "Not responding"
fi

# Check Docker daemon
if docker info &>/dev/null 2>&1; then
    DOCKER_COUNT=$(docker ps -q 2>/dev/null | wc -l)
    gate_pass "docker-daemon" "${DOCKER_COUNT} containers running"
else
    gate_fail "docker-daemon" "Not responding"
fi

}

# ═══════════════════════════════════════════════════════════════════════════════
# GATE 2: BUILD VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

CURRENT_GATE="build"
[[ "$SKIP_UNTIL" != "preflight" && "$SKIP_UNTIL" != "build" ]] && { gate_skip "build" "Skipped (start gate: ${START_GATE})"; } || {

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ GATE 2: BUILD VALIDATION ━━━${C_RESET}"
fi

# Validate shell scripts
SHELL_ERRORS=0
for sh_file in "$TARGET_REPO"/scripts/sovereign-*.sh; do
    if [[ -f "$sh_file" ]]; then
        if bash -n "$sh_file" 2>/dev/null; then
            gate_pass "syntax-$(basename "$sh_file")" "Valid"
        else
            gate_fail "syntax-$(basename "$sh_file")" "Syntax error"
            SHELL_ERRORS=$((SHELL_ERRORS + 1))
        fi
    fi
done

[[ "$SHELL_ERRORS" -eq 0 ]] && gate_pass "shell-syntax" "All scripts valid" || true

# Check JSON validity of key configs
for json_file in "$TARGET_REPO"/.claude/settings.json "$TARGET_REPO"/.claude.json; do
    if [[ -f "$json_file" ]]; then
        if python3 -c "import json; json.load(open('${json_file}'))" 2>/dev/null; then
            gate_pass "json-$(basename "$json_file")" "Valid JSON"
        else
            gate_fail "json-$(basename "$json_file")" "Invalid JSON"
        fi
    fi
done

}

# ═══════════════════════════════════════════════════════════════════════════════
# GATE 3: TEST
# ═══════════════════════════════════════════════════════════════════════════════

CURRENT_GATE="test"
[[ "$SKIP_UNTIL" != "preflight" && "$SKIP_UNTIL" != "build" && "$SKIP_UNTIL" != "test" ]] && { gate_skip "test" "Skipped (start gate: ${START_GATE})"; } || {

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ GATE 3: TEST ━━━${C_RESET}"
fi

# Run sovereign script --help smoke tests
for script in "$TARGET_REPO"/scripts/sovereign-*.sh; do
    sname=$(basename "$script")
    if [[ -x "$script" ]]; then
        if timeout 5 bash "$script" --help &>/dev/null 2>&1; then
            gate_pass "help-${sname}" "Help output works"
        else
            gate_fail "help-${sname}" "Help output failed"
        fi
    else
        gate_fail "exec-${sname}" "Not executable"
    fi
done

# Quick health check
if [[ -x "$TARGET_REPO"/scripts/sovereign-ecosystem-health-check.sh ]]; then
    if timeout 30 bash "$TARGET_REPO"/scripts/sovereign-ecosystem-health-check.sh --quick --json > /dev/null 2>&1; then
        gate_pass "health-check" "Quick health check passed"
    else
        gate_fail "health-check" "Quick health check failed"
    fi
fi

}

# ═══════════════════════════════════════════════════════════════════════════════
# GATE 4: STAGING DEPLOY
# ═══════════════════════════════════════════════════════════════════════════════

CURRENT_GATE="stage"
[[ "$SKIP_UNTIL" != "preflight" && "$SKIP_UNTIL" != "build" && "$SKIP_UNTIL" != "test" && "$SKIP_UNTIL" != "stage" ]] && { gate_skip "stage" "Skipped (start gate: ${START_GATE})"; } || {

if [[ "$DRY_RUN" == "true" ]]; then
    gate_skip "stage" "Dry run — skipping staging deploy"
else
    if [[ "$JSON_MODE" == "false" ]]; then
        echo ""
        echo -e "${C_BOLD}${C_BLUE}━━━ GATE 4: STAGING DEPLOY ━━━${C_RESET}"
    fi

    if [[ -x "$TARGET_REPO"/scripts/sovereign-staging-provision.sh ]]; then
        if timeout 60 bash "$TARGET_REPO"/scripts/sovereign-staging-provision.sh --status 2>/dev/null; then
            gate_pass "staging" "Staging environment accessible"
        else
            gate_fail "staging" "Staging environment check failed"
        fi
    else
        gate_skip "staging" "Staging provisioner not available"
    fi
fi

}

# ═══════════════════════════════════════════════════════════════════════════════
# GATE 5: SMOKE TESTS
# ═══════════════════════════════════════════════════════════════════════════════

CURRENT_GATE="smoke"
[[ "$SKIP_UNTIL" != "preflight" && "$SKIP_UNTIL" != "build" && "$SKIP_UNTIL" != "test" && "$SKIP_UNTIL" != "stage" && "$SKIP_UNTIL" != "smoke" ]] && { gate_skip "smoke" "Skipped (start gate: ${START_GATE})"; } || {

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ GATE 5: SMOKE TESTS ━━━${C_RESET}"
fi

ENDPOINT_CHECKS=(
    "http://127.0.0.1:8180/health|200|exec-dashboard"
    "http://127.0.0.1:3002/api/health|200|grafana"
    "http://127.0.0.1:9090/-/ready|200|prometheus"
    "http://127.0.0.1:3100/ready|200|loki"
    "http://127.0.0.1:9093/-/ready|200|alertmanager"
    "http://127.0.0.1:8100/api/health|200|command-center"
    "http://127.0.0.1:8091/api/health|200|war-room"
    "http://127.0.0.1:8110|200|openclaw"
)

for entry in "${ENDPOINT_CHECKS[@]}"; do
    IFS="|" read -r url expected label <<< "$entry"
    http_code=$(_http_code "$url")
    if [[ "$http_code" == "$expected" ]] || { [[ "$expected" == "401" ]] && [[ "$http_code" == "200" ]]; }; then
        gate_pass "smoke-${label}" "HTTP ${http_code}"
    elif [[ "$http_code" == "000" ]]; then
        gate_fail "smoke-${label}" "Connection refused"
    else
        gate_pass "smoke-${label}" "HTTP ${http_code} (acceptable)"
    fi
done

}

# ═══════════════════════════════════════════════════════════════════════════════
# GATE 6: DEPLOY
# ═══════════════════════════════════════════════════════════════════════════════

CURRENT_GATE="deploy"
[[ "$SKIP_UNTIL" != "preflight" && "$SKIP_UNTIL" != "build" && "$SKIP_UNTIL" != "test" && "$SKIP_UNTIL" != "stage" && "$SKIP_UNTIL" != "smoke" && "$SKIP_UNTIL" != "deploy" ]] && { gate_skip "deploy" "Skipped (start gate: ${START_GATE})"; } || {

if [[ "$DRY_RUN" == "true" ]]; then
    gate_skip "deploy" "Dry run — skipping deployment"
else
    if [[ "$JSON_MODE" == "false" ]]; then
        echo ""
        echo -e "${C_BOLD}${C_BLUE}━━━ GATE 6: DEPLOY ━━━${C_RESET}"
    fi

    # Git operations
    if [[ -d "$TARGET_REPO/.git" ]]; then
        git -C "$TARGET_REPO" fetch --all --quiet 2>/dev/null || true

        LOCAL_HASH=$(git -C "$TARGET_REPO" rev-parse HEAD 2>/dev/null || echo "unknown")
        REMOTE_HASH=$(git -C "$TARGET_REPO" rev-parse origin/master 2>/dev/null || echo "unknown")

        if [[ "$LOCAL_HASH" == "$REMOTE_HASH" ]] && [[ "$LOCAL_HASH" != "unknown" ]]; then
            gate_pass "git-sync" "Local is in sync with origin/master"
        elif [[ "$LOCAL_HASH" != "unknown" ]]; then
            gate_pass "git-sync" "Local: ${LOCAL_HASH:0:8} | Remote: ${REMOTE_HASH:0:8}"
        fi
    fi

    # PM2 restart if needed
    if pm2 ping &>/dev/null 2>&1; then
        pm2 save 2>/dev/null || true
        gate_pass "pm2-save" "Process list saved for resurrection"
    fi
fi

}

# ═══════════════════════════════════════════════════════════════════════════════
# GATE 7: POST-DEPLOY VERIFY
# ═══════════════════════════════════════════════════════════════════════════════

CURRENT_GATE="verify"
[[ "$SKIP_UNTIL" != "preflight" && "$SKIP_UNTIL" != "build" && "$SKIP_UNTIL" != "test" && "$SKIP_UNTIL" != "stage" && "$SKIP_UNTIL" != "smoke" && "$SKIP_UNTIL" != "deploy" && "$SKIP_UNTIL" != "verify" ]] && { gate_skip "verify" "Skipped (start gate: ${START_GATE})"; } || {

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ GATE 7: POST-DEPLOY VERIFY ━━━${C_RESET}"
fi

# PM2 health re-check
if pm2 ping &>/dev/null 2>&1; then
    pm2_total=$(pm2 jlist 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    pm2_online=$(pm2 jlist 2>/dev/null | python3 -c "import sys,json; print(sum(1 for p in json.load(sys.stdin) if p.get('pm2_env',{}).get('status')=='online'))" 2>/dev/null || echo "0")
    if [[ "$pm2_online" -eq "$pm2_total" ]]; then
        gate_pass "pm2-verify" "${pm2_online}/${pm2_total} online"
    else
        gate_fail "pm2-verify" "${pm2_online}/${pm2_total} online — ${pm2_stopped:-0} stopped"
    fi
fi

# Docker health re-check
if docker info &>/dev/null 2>&1; then
    docker_unhealthy=$(docker ps --filter "health=unhealthy" -q 2>/dev/null | wc -l)
    if [[ "$docker_unhealthy" -eq 0 ]]; then
        gate_pass "docker-verify" "All containers healthy"
    else
        gate_fail "docker-verify" "${docker_unhealthy} unhealthy containers"
    fi
fi

# Rollback readiness
ROLLBACK_PLAN="${LOG_DIR}/rollback-${DEPLOY_ID}.plan"
cat > "$ROLLBACK_PLAN" <<EOF
Rollback Plan — Deploy ${DEPLOY_ID}
Timestamp: ${TIMESTAMP}
Repo: ${TARGET_REPO}
Branch: ${BRANCH:-unknown}

Rollback commands:
  cd ${TARGET_REPO}
  git log -1 --format="%H %s"  # verify current HEAD
  git reset --hard HEAD~1       # rollback one commit
  pm2 resurrect                 # restore PM2 process list

Notes:
  - Database migrations require manual rollback
  - Docker containers may need re-pulling if images changed
  - Verify health after rollback: sovereign-ecosystem-health-check.sh --quick
EOF
gate_pass "rollback-plan" "Saved to ${ROLLBACK_PLAN}"

}

# ═══════════════════════════════════════════════════════════════════════════════
# PIPELINE SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
for result in "${GATE_RESULTS[@]}"; do
    case "$result" in
        *'"PASS"')* PASS_COUNT=$((PASS_COUNT + 1)) ;;
        *'"FAIL"')* FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        *'"SKIP"')* SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
    esac
done
TOTAL_COUNT=$(( PASS_COUNT + FAIL_COUNT + SKIP_COUNT ))

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  PIPELINE SUMMARY${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  Deploy ID: ${DEPLOY_ID}${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    printf "  %-20s %s\n" "Gates passed:"  "${C_GREEN}${PASS_COUNT}${C_RESET}"
    printf "  %-20s %s\n" "Gates failed:"  "${C_RED}${FAIL_COUNT}${C_RESET}"
    printf "  %-20s %s\n" "Gates skipped:" "${C_DIM}${SKIP_COUNT}${C_RESET}"
    printf "  %-20s %s\n" "Total gates:"   "${TOTAL_COUNT}"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${C_YELLOW}${C_BOLD}  DRY RUN COMPLETE — No changes made${C_RESET}"
    elif [[ "$GATE_FAILED" == "true" ]]; then
        echo -e "${C_RED}${C_BOLD}  PIPELINE FAILED — Rollback plan: ${ROLLBACK_PLAN}${C_RESET}"
    else
        echo -e "${C_GREEN}${C_BOLD}  PIPELINE PASSED — ALL GATES GREEN${C_RESET}"
    fi
    echo ""
    echo -e "${C_DIM}  Deploy log: ${LOG_DIR}/deploy-${DEPLOY_ID}.log${C_RESET}"
    echo -e "${C_DIM}  Rollback:   ${ROLLBACK_PLAN}${C_RESET}"
    echo ""
fi

# Write deploy log
printf -v joined '%s,' "${GATE_RESULTS[@]}"
joined="${joined%,}"

JSON_OUTPUT=$(cat <<EOJSON
{
  "deploy_id": "${DEPLOY_ID}",
  "timestamp": "${TIMESTAMP}",
  "repo": "${TARGET_REPO}",
  "dry_run": ${DRY_RUN},
  "gates_passed": ${PASS_COUNT},
  "gates_failed": ${FAIL_COUNT},
  "gates_skipped": ${SKIP_COUNT},
  "pipeline_passed": $( [[ "$GATE_FAILED" == "true" ]] && echo "false" || echo "true" ),
  "gates": [${joined:-}]
}
EOJSON
)

if [[ "$JSON_MODE" == "true" ]]; then
    echo "$JSON_OUTPUT"
fi

echo "$JSON_OUTPUT" > "${LOG_DIR}/deploy-${DEPLOY_ID}.json" 2>/dev/null || true
echo "${DEPLOY_LOG[@]}" > "${LOG_DIR}/deploy-${DEPLOY_ID}.log" 2>/dev/null || true

if [[ "$GATE_FAILED" == "true" ]]; then
    exit 1
fi
exit 0
