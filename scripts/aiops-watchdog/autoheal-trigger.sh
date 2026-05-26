#!/usr/bin/env bash
#===============================================================================
# autoheal-trigger.sh
# Wheeler Autonomous AI Ops — Self-Healing Trigger Daemon
#
# Runs after ecosystem-health.sh. Reads health-report.json, matches failures
# against known patterns, applies canonical fixes, and verifies results.
#
# Severity-based action matrix:
#   INFO    — log only, no action
#   WARN    — auto-heal if pattern matches proven playbook
#   HIGH    — auto-heal with post-fix verification
#   CRITICAL — alert + attempt auto-heal, escalate if fails
#   EMERGENCY — full incident response, no auto-heal
#
# Usage:
#   ./autoheal-trigger.sh                     # Standard run
#   ./autoheal-trigger.sh --dry-run           # Report what would be done
#   ./autoheal-trigger.sh --force             # Override all safety gates
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HEALTH_REPORT="${SCRIPT_DIR}/health-report.json"
HEAL_LOG="/var/log/wheeler-autoheal.log"
DRY_RUN=false
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --force)   FORCE=true ;;
        --help)    sed -ne '/^#===-/,/^#===/p' "$0" | head -n -1 | sed 's/^#//'; exit 0 ;;
    esac
done

log() {
    local level="$1"; shift
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$level] $*" | tee -a "$HEAL_LOG"
}

heal_pm2_crash() {
    local process="$1"
    log "INFO" "Attempting PM2 restart for: $process"

    # Check if this is a known agent service with an ecosystem.config.js
    local config_dir=""
    for base in /opt/apps /opt/openclaw-dashboard; do
        if [ -f "${base}/${process}/ecosystem.config.js" ]; then
            config_dir="${base}/${process}"
            break
        fi
    done

    if [ -z "$config_dir" ]; then
        log "WARN" "No config found for $process — cannot auto-heal"
        return 1
    fi

    if $DRY_RUN; then
        log "DRYRUN" "Would restart $process from $config_dir with env -i"
        return 0
    fi

    # Canonical: env -i delete+start
    pm2 delete "$process" 2>/dev/null || true
    sleep 2

    cd "$config_dir"
    if env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" NODE_ENV=production pm2 start ecosystem.config.js 2>/dev/null; then
        pm2 save --force 2>/dev/null
        log "OK" "PM2 restart succeeded for $process"
        return 0
    else
        log "HIGH" "PM2 restart FAILED for $process"
        return 1
    fi
}

heal_docker_restart() {
    local container="$1"
    log "INFO" "Attempting Docker restart for: $container"

    if $DRY_RUN; then
        log "DRYRUN" "Would restart container $container"
        return 0
    fi

    if docker restart "$container" 2>/dev/null; then
        sleep 5
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            log "OK" "Docker restart succeeded for $container"
            return 0
        fi
    fi
    log "HIGH" "Docker restart FAILED for $container"
    return 1
}

heal_port_drift() {
    log "WARN" "Port drift detected — running exposure assessment"
    if $DRY_RUN; then
        log "DRYRUN" "Would run exposure audit"
        return 0
    fi
    # Trigger enforcement watchdog immediately
    bash /opt/wheeler-ecosystem/enforcement/wheeler-lockdown-watchdog.sh 2>/dev/null || true
    # Log for review — port drift often needs human verification
    log "HIGH" "Port drift requires human review — see /var/log/wheeler-watchdog.log"
    return 0
}

heal_high_resource() {
    local resource="$1"
    log "WARN" "High resource usage: $resource"
    if $DRY_RUN; then
        log "DRYRUN" "Would run docker system prune and log analysis"
        return 0
    fi
    docker system prune -f 2>/dev/null || true
    log "INFO" "Ran docker system prune to free space"
    return 0
}

heal_repo_engine() {
    local issue="$1"
    log "INFO" "Attempting repo-engine auto-heal for: $issue"

    if $DRY_RUN; then
        log "DRYRUN" "Would restart repo-engine PM2 daemon"
        return 0
    fi

    # Check if repo-engine PM2 is running
    if ! pm2 jlist 2>/dev/null | jq -e '.[] | select(.name == "repo-engine" and .pm2_env.status == "online")' > /dev/null 2>&1; then
        log "HIGH" "repo-engine daemon down — restarting"
        pm2 delete repo-engine 2>/dev/null || true
        sleep 2
        cd /opt/wheeler-ecosystem/repo-router
        if env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
           pm2 start repo-engine-ecosystem.config.js 2>/dev/null; then
            pm2 save --force 2>/dev/null
            log "OK" "repo-engine restarted"
        else
            log "CRITICAL" "repo-engine restart FAILED"
            return 1
        fi
    fi

    # Run self-heal script if available
    if [ -x /opt/wheeler-ecosystem/repo-router/scripts/repo-engine-selfheal.sh ]; then
        bash /opt/wheeler-ecosystem/repo-router/scripts/repo-engine-selfheal.sh 2>&1 | tee -a "$HEAL_LOG" || true
    fi

    # Fix git remotes if missing
    if [ -x /opt/wheeler-ecosystem/repo-router/scripts/fix-git-remotes.sh ]; then
        bash /opt/wheeler-ecosystem/repo-router/scripts/fix-git-remotes.sh 2>&1 | tee -a "$HEAL_LOG" || true
    fi

    return 0
}

# ─── Main ───────────────────────────────────────────

log "INFO" "Auto-heal trigger starting $(if $DRY_RUN; then echo '(DRY RUN)'; fi)"

if [ ! -f "$HEALTH_REPORT" ]; then
    log "WARN" "No health report found at $HEALTH_REPORT — running ecosystem-health.sh"
    if ! $DRY_RUN; then
        bash "${SCRIPT_DIR}/ecosystem-health.sh" --quiet 2>/dev/null || true
    fi
    if [ ! -f "$HEALTH_REPORT" ]; then
        log "CRITICAL" "Cannot generate health report — aborting auto-heal"
        exit 1
    fi
fi

# Parse health report
OVERALL_SCORE=$(python3 -c "
import json
with open('${HEALTH_REPORT}') as f:
    d = json.load(f)
print(d.get('summary',{}).get('overall_score', 0))
" 2>/dev/null || echo "0")

log "INFO" "Health score: ${OVERALL_SCORE}/100"

if [ "${OVERALL_SCORE}" -ge 90 ]; then
    log "INFO" "Ecosystem healthy (${OVERALL_SCORE}/100) — no healing needed"
    exit 0
fi

# Process each subsystem
python3 -c "
import json
with open('${HEALTH_REPORT}') as f:
    d = json.load(f)
subsystems = d.get('subsystems', [])
for s in subsystems:
    if s.get('score', 100) < 90:
        name = s.get('name', 'unknown')
        score = s.get('score', 0)
        fail = s.get('fail', 0)
        print(f'{name}|{score}|{fail}')
" 2>/dev/null | while IFS='|' read -r name score fail; do
    [ -z "$name" ] && continue
    log "WARN" "Subsystem ${name}: score=${score}/100, failures=${fail}"

    case "$name" in
        pm2-watchdog)
            # Find stopped/crashed PM2 processes
            pm2 jlist 2>/dev/null | python3 -c "
import json, sys
for p in json.load(sys.stdin):
    if p['pm2_env']['status'] != 'online':
        print(p['name'])
" 2>/dev/null | while read -r proc; do
                [ -z "$proc" ] && continue
                log "HIGH" "PM2 process $proc is not online — attempting restart"
                heal_pm2_crash "$proc" || log "CRITICAL" "Auto-heal failed for $proc"
            done
            ;;
        docker-watchdog)
            docker ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -v "Up" | while read -r container status; do
                [ -z "$container" ] && continue
                log "HIGH" "Docker container $container status: $status — attempting restart"
                heal_docker_restart "$container" || log "CRITICAL" "Auto-heal failed for $container"
            done
            ;;
        port-watchdog)
            heal_port_drift
            ;;
        resource-watchdog)
            heal_high_resource "system"
            ;;
        repo-watchdog)
            heal_repo_engine "watchdog-alert"
            ;;
        *)
            log "INFO" "No auto-heal pattern for subsystem: $name"
            ;;
    esac
done

# Re-run health check to verify
if ! $DRY_RUN; then
    sleep 3
    log "INFO" "Running post-heal verification..."
    bash "${SCRIPT_DIR}/ecosystem-health.sh" --quiet 2>/dev/null || true

    NEW_SCORE=$(python3 -c "
import json
with open('${HEALTH_REPORT}') as f:
    d = json.load(f)
print(d.get('summary',{}).get('overall_score', 0))
" 2>/dev/null || echo "0")

    log "INFO" "Post-heal score: ${NEW_SCORE}/100 (was ${OVERALL_SCORE}/100)"
    if [ "${NEW_SCORE}" -ge 90 ]; then
        log "OK" "Ecosystem restored to healthy (${NEW_SCORE}/100)"
    elif [ "${NEW_SCORE}" -gt "${OVERALL_SCORE}" ]; then
        log "INFO" "Ecosystem improved (${OVERALL_SCORE} → ${NEW_SCORE})"
    else
        log "HIGH" "Ecosystem did not improve — human review needed"
    fi
fi

log "INFO" "Auto-heal trigger complete"
