#!/usr/bin/env bash
#===============================================================================
# restart-loop-healer.sh
# Wheeler Autonomous AI Ops — PM2 Restart Loop Detector + Healer
#
# Detects PM2 processes that are actively crash-looping (high restarts in a
# short window) and applies known fixes or escalates.
#
# Restart loop detection logic:
#   1. Find processes with >5 total restarts
#   2. Check if they've restarted within the last 5 minutes (actively looping)
#   3. If actively looping AND a known fix exists, auto-apply
#   4. If actively looping with unknown cause, restart once and alert
#   5. NEVER touch production-critical processes (frcrm-api, prediction-radar, etc.)
#
# Usage:
#   ./restart-loop-healer.sh                     # Standard run with auto-heal
#   ./restart-loop-healer.sh --dry-run           # Report only, no actions
#   ./restart-loop-healer.sh --force             # Override safety gates
#   ./restart-loop-healer.sh --help              # This text
#
# Log: /var/log/wheeler-restart-loop-healer.log
#===============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
HEAL_LOG="/var/log/wheeler-restart-loop-healer.log"
DRY_RUN=false
FORCE=false
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- Thresholds ----
RESTART_TOTAL_THRESHOLD=5       # Total restart count to be suspicious
RESTART_ACTIVE_WINDOW=300       # Seconds since last start to be "actively looping"
KNOWN_FIX_WAIT=10               # Seconds to wait after fix before verification

# ---- Production-critical PM2 processes - NEVER auto-restart ----
PRODUCTION_CRITICAL_PM2=(
    "frcrm-api"
    "prediction-radar-agent-svc"
    "open-webui"
)

# ---- Containers that are production-critical - NEVER auto-restart ----
PRODUCTION_CRITICAL_CONTAINERS=(
    "frcrm-api"
    "prediction-radar-app-api"
    "prediction-radar-app-web"
    "open-webui"
)

# ---- Database containers - NEVER auto-restart ----
DATABASE_CONTAINERS=(
    "postgres"
    "redis"
    "neo4j"
    "qdrant"
)

# ---- Known fixes indexed by process name ----
declare -A KNOWN_FIXES
KNOWN_FIXES["ravynai-og-scheduler"]="Check scheduler loop: pm2 logs ravynai-og-scheduler --lines 30 | grep -i error; if grep -q rate_limit; then echo 'Rate limited — scheduling backoff needed'; fi"
KNOWN_FIXES["executive-dashboard-api"]="Check port/DB connectivity: pm2 logs executive-dashboard-api --lines 20 | grep -iE 'error|refused|timeout'"
KNOWN_FIXES["litellm"]="Check DeepSeek API key and config: pm2 logs litellm --lines 30 | grep -iE 'auth|key|error'"
KNOWN_FIXES["repo-engine"]="Check git remote connectivity: /opt/wheeler-ecosystem/repo-router/scripts/fix-git-remotes.sh"

# ---- Severity-based safe-to-restart categories ----
SAFE_TO_RESTART_SUBSTRINGS=(
    "agent-svc"
    "watchdog"
    "sync"
    "exporter"
    "monitoring"
    "backup"
    "scheduler"
    "collector"
    "bridge"
    "relay"
)

# ---- Help ----
show_help() {
    sed -ne '/^#===-/,/^#===/p' "$0" | head -n -1 | sed 's/^#//'
    exit 0
}

# ---- Logging ----
log() {
    local level="$1"; shift
    echo "[${TIMESTAMP}] [${level}] [${SCRIPT_NAME}] $*" | tee -a "$HEAL_LOG"
}

is_production_critical_pm2() {
    local name="$1"
    for p in "${PRODUCTION_CRITICAL_PM2[@]}"; do
        if [[ "$name" == "$p" ]]; then
            return 0
        fi
    done
    return 1
}

is_production_critical_docker() {
    local name="$1"
    for p in "${PRODUCTION_CRITICAL_CONTAINERS[@]}"; do
        if [[ "$name" == "$p" ]]; then
            return 0
        fi
    done
    # Also match substrings like prediction-radar-app-*
    for p in "${PRODUCTION_CRITICAL_CONTAINERS[@]}"; do
        if [[ "$name" == "$p"* ]]; then
            return 0
        fi
    done
    return 1
}

is_database_container() {
    local name="$1"
    for p in "${DATABASE_CONTAINERS[@]}"; do
        if [[ "$name" == *"$p"* ]]; then
            return 0
        fi
    done
    return 1
}

is_safe_to_restart() {
    local name="$1"
    for s in "${SAFE_TO_RESTART_SUBSTRINGS[@]}"; do
        if [[ "$name" == *"$s"* ]]; then
            return 0
        fi
    done
    return 1
}

# ---- Find actively crash-looping PM2 processes ----
find_loopers() {
    python3 -c "
import json, sys, time

now = time.time()
window = ${RESTART_ACTIVE_WINDOW}
threshold = ${RESTART_TOTAL_THRESHOLD}

try:
    procs = json.load(sys.stdin)
except Exception:
    sys.exit(1)

loopers = []
for p in procs:
    name = p.get('name', '')
    status = p.get('pm2_env', {}).get('status', '')
    restarts = p.get('pm2_env', {}).get('restart_time', 0)
    pm_uptime = p.get('pm2_env', {}).get('pm_uptime', 0)
    pm_uptime_sec = pm_uptime / 1000 if pm_uptime else 0

    # Active loop: high restarts AND recently started (within window)
    actively_looping = False
    if restarts > threshold and pm_uptime_sec > 0:
        uptime_seconds = now - pm_uptime_sec
        if uptime_seconds < window:
            actively_looping = True

    if actively_looping:
        uptime_sec = int(now - pm_uptime_sec)  # actual uptime in seconds
        loopers.append({
            'name': name,
            'status': status,
            'restarts': restarts,
            'uptime_seconds': uptime_sec,
            'start_epoch': int(pm_uptime_sec)
        })

print(json.dumps(loopers))
" 2>/dev/null || echo "[]"
}

# ---- Apply known fix for a process ----
apply_known_fix() {
    local name="$1"
    local fix="${KNOWN_FIXES[$name]:-}"

    if [[ -n "$fix" ]]; then
        log "INFO" "Known fix for $name: $fix"
        if $DRY_RUN; then
            log "DRYRUN" "Would apply known fix for $name"
            return 0
        fi
        # Log the fix suggestion — actual diagnostic requires human review of the output
        log "INFO" "Suggested fix logged for $name — will attempt restart"
    else
        log "INFO" "No known fix for $name — will attempt restart once"
    fi
    return 0
}

# ---- Restart a PM2 process safely ----
safe_pm2_restart() {
    local name="$1"
    log "INFO" "Attempting PM2 restart for $name"

    # Find the ecosystem.config.js
    local config_dir=""
    for base in /opt/apps /opt/openclaw-dashboard; do
        if [ -f "${base}/${name}/ecosystem.config.js" ]; then
            config_dir="${base}/${name}"
            break
        fi
    done

    if $DRY_RUN; then
        if [[ -n "$config_dir" ]]; then
            log "DRYRUN" "Would restart $name from $config_dir"
        else
            log "DRYRUN" "Would restart $name with: pm2 restart $name"
        fi
        return 0
    fi

    # Canonical env -i delete+start pattern
    pm2 delete "$name" 2>/dev/null || true
    sleep 2

    if [[ -n "$config_dir" ]]; then
        cd "$config_dir"
        if env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            NODE_ENV=production pm2 start ecosystem.config.js 2>/dev/null; then
            pm2 save --force 2>/dev/null
            log "OK" "PM2 restart succeeded for $name from $config_dir"
            return 0
        fi
    else
        # Fallback: direct pm2 restart (less clean but works without config)
        if pm2 restart "$name" 2>/dev/null; then
            pm2 save --force 2>/dev/null
            log "OK" "PM2 restart succeeded for $name (direct restart)"
            return 0
        fi
    fi

    log "HIGH" "PM2 restart FAILED for $name"
    return 1
}

# ---- Verify the restart fixed the loop ----
verify_healed() {
    local name="$1"
    sleep "$KNOWN_FIX_WAIT"

    local status
    status="$(pm2 jlist 2>/dev/null | python3 -c "
import json,sys
procs = json.load(sys.stdin)
status = 'not_found'
for p in procs:
    if p.get('name') == '$name':
        status = p.get('pm2_env',{}).get('status','unknown')
        break
print(status)
" 2>/dev/null || echo "unknown")"

    if [[ "$status" == "online" ]]; then
        log "OK" "Verified $name is online after restart"
        return 0
    else
        log "HIGH" "Verification failed for $name: status=$status"
        return 1
    fi
}

# ---- Main ----
main() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --force)   FORCE=true ;;
            --help)    show_help ;;
        esac
    done

    log "INFO" "Restart loop healer starting $(if $DRY_RUN; then echo '(DRY RUN)'; fi)"

    # Get PM2 process list
    local jlist
    jlist="$(pm2 jlist 2>/dev/null)" || {
        log "CRITICAL" "Cannot read PM2 process list"
        exit 1
    }

    # Find actively looping processes
    local loopers_json
    loopers_json="$(echo "$jlist" | find_loopers)"

    local loopers
    loopers="$(echo "$loopers_json" | python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
    for l in data:
        print(f\"{l['name']}|{l['restarts']}|{l['uptime_seconds']}\")
except:
    pass
" 2>/dev/null || true)"

    if [[ -z "$loopers" ]]; then
        log "INFO" "No actively crash-looping PM2 processes detected"
        exit 0
    fi

    # Process each looper
    local healed=0
    local escalated=0
    local skipped=0

    while IFS='|' read -r name restarts uptime_s; do
        [[ -z "$name" ]] && continue
        log "HIGH" "Crash-looping: $name (restarts=$restarts, uptime=${uptime_s}s)"

        # Check if production-critical
        if is_production_critical_pm2 "$name"; then
            log "WARN" "PRODUCTION CRITICAL: $name — logging only, no auto-heal"
            ((skipped++))
            continue
        fi

        # Check safety of restart
        if is_safe_to_restart "$name"; then
            log "INFO" "$name is in safe-to-restart category"
        else
            if ! $FORCE; then
                log "WARN" "$name is not in safe-to-restart category and not production-critical — escalating for human review"
                ((escalated++))
                continue
            fi
        fi

        # Apply known fix if available
        apply_known_fix "$name"

        # Restart
        if safe_pm2_restart "$name"; then
            if verify_healed "$name"; then
                log "HEALED" "Restart loop resolved for $name"
                ((healed++))
            else
                log "FAILED" "Restart loop continued for $name after restart"
                ((escalated++))
            fi
        else
            log "FAILED" "Could not restart $name"
            ((escalated++))
        fi
    done <<< "$loopers"

    # Summary
    log "INFO" "Restart loop healer complete: healed=$healed escalated=$escalated skipped=$skipped"

    if [[ "$escalated" -gt 0 ]]; then
        return 1
    fi
    return 0
}

main "$@"
