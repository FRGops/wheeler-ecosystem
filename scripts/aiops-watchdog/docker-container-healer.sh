#!/usr/bin/env bash
#===============================================================================
# docker-container-healer.sh
# Wheeler Autonomous AI Ops — Docker Container Health Restorer
#
# Detects unhealthy Docker containers and applies graduated remediation:
#   1. First detection: log and flag
#   2. Unhealthy for >5 minutes: docker restart
#   3. Still unhealthy 5 min after restart: escalate to human
#
# Safety rules:
#   - NEVER restarts database containers (postgres, redis, neo4j, qdrant)
#   - NEVER restarts production apps (frcrm-api, prediction-radar, open-webui)
#   - Safe to restart: monitoring, exporters, agents, sidecars
#
# Usage:
#   ./docker-container-healer.sh                     # Standard run
#   ./docker-container-healer.sh --dry-run           # Report only
#   ./docker-container-healer.sh --force             # Override safety gates
#   ./docker-container-healer.sh --status            # Show current unhealthy state
#   ./docker-container-healer.sh --help              # This text
#
# State: /var/log/wheeler/docker-healer-state.json
# Log: /var/log/wheeler-docker-container-healer.log
#===============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
HEAL_LOG="/var/log/wheeler-docker-container-healer.log"
STATE_FILE="/var/log/wheeler/docker-healer-state.json"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date +%s)"
DRY_RUN=false
FORCE=false

# ---- Thresholds ----
UNHEALTHY_MIN_WAIT=300          # 5 minutes before attempting restart
POST_RESTART_GRACE=300          # 5 minutes grace after restart before escalating
MAX_RESTART_ATTEMPTS=2          # Max restarts before escalation

# ---- Database containers - NEVER restart ----
DATABASE_CONTAINERS=(
    "postgres"
    "redis"
    "neo4j"
    "qdrant"
)

# ---- Production-critical containers - NEVER restart ----
PRODUCTION_CRITICAL_CONTAINERS=(
    "frcrm-api"
    "prediction-radar-app-api"
    "prediction-radar-app-web"
    "open-webui"
)

# ---- Safe-to-restart container substrings ----
SAFE_TO_RESTART_SUBSTRINGS=(
    "exporter"
    "monitoring"
    "agent"
    "watchdog"
    "bridge"
    "relay"
    "sidecar"
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

# ---- State management ----
init_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"containers":{}}' > "$STATE_FILE"
    fi
}

read_state() {
    cat "$STATE_FILE" 2>/dev/null || echo '{"containers":{}}'
}

write_state() {
    local new_state="$1"
    echo "$new_state" > "$STATE_FILE"
}

update_container_state() {
    local container="$1"
    local status="$2"    # unhealthy_first_seen, restart_attempted, escalated
    local ts="$3"

    local state
    state="$(read_state)"
    local updated
    updated="$(echo "$state" | python3 -c "
import json,sys
state = json.load(sys.stdin)
state.setdefault('containers', {})
state['containers']['$container'] = {'status': '$status', 'timestamp': $ts, 'updated': '${TIMESTAMP}'}
json.dump(state, sys.stdout)
" 2>/dev/null || echo "$state")"
    write_state "$updated"
}

get_container_state() {
    local container="$1"
    read_state | python3 -c "
import json,sys
try:
    state = json.load(sys.stdin)
    c = state.get('containers', {}).get('$container', {})
    print(json.dumps(c))
except:
    print('{}')
" 2>/dev/null || echo '{}'
}

# ---- Safety checks ----
is_database() {
    local name="$1"
    for p in "${DATABASE_CONTAINERS[@]}"; do
        if [[ "$name" == *"$p"* ]]; then
            return 0
        fi
    done
    return 1
}

is_production_critical() {
    local name="$1"
    for p in "${PRODUCTION_CRITICAL_CONTAINERS[@]}"; do
        if [[ "$name" == "$p" ]]; then
            return 0
        fi
    done
    # Also match prefix patterns
    for p in "${PRODUCTION_CRITICAL_CONTAINERS[@]}"; do
        if [[ "$name" == "$p"* ]]; then
            return 0
        fi
    done
    return 1
}

is_safe_container() {
    local name="$1"
    for s in "${SAFE_TO_RESTART_SUBSTRINGS[@]}"; do
        if [[ "$name" == *"$s"* ]]; then
            return 0
        fi
    done
    return 1
}

# ---- Check if a container has HEALTHCHECK defined ----
has_healthcheck() {
    local container="$1"
    local hc
    hc="$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || true)"
    [[ -n "$hc" && "$hc" != "<nil>" ]]
}

# ---- Check container health ----
get_container_health() {
    local container="$1"
    docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown"
}

# ---- Graduated remediation ----
handle_unhealthy() {
    local container="$1"
    local health="$2"

    log "WARN" "Container $container is $health"

    # Safety checks
    if is_database "$container"; then
        log "INFO" "$container is a database — logging only, no auto-heal"
        update_container_state "$container" "database_skipped" "$NOW_EPOCH"
        return 0
    fi

    if is_production_critical "$container"; then
        log "WARN" "$container is production-critical — logging only, no auto-heal"
        update_container_state "$container" "production_skipped" "$NOW_EPOCH"
        return 0
    fi

    # Read container's tracked state
    local cstate
    cstate="$(get_container_state "$container")"
    local tracked_status
    local tracked_ts
    tracked_status="$(echo "$cstate" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null || echo '')"
    tracked_ts="$(echo "$cstate" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('timestamp',0))" 2>/dev/null || echo 0)"

    case "$tracked_status" in
        "")
            # First detection: log and track
            log "INFO" "First detection of unhealthy state for $container — will monitor"
            update_container_state "$container" "unhealthy_first_seen" "$NOW_EPOCH"
            ;;

        "unhealthy_first_seen")
            # Already tracked. Check if it's been long enough
            local elapsed=$(( NOW_EPOCH - tracked_ts ))
            if [[ "$elapsed" -ge "$UNHEALTHY_MIN_WAIT" ]]; then
                log "HIGH" "$container has been unhealthy for ${elapsed}s (threshold: ${UNHEALTHY_MIN_WAIT}s) — attempting restart"
                if $DRY_RUN; then
                    log "DRYRUN" "Would restart container $container"
                    update_container_state "$container" "dry_run_restart" "$NOW_EPOCH"
                    return 0
                fi

                # Check if it's safe to restart
                if ! is_safe_container "$container" && ! $FORCE; then
                    log "WARN" "$container is not in safe-to-restart list — escalating"
                    update_container_state "$container" "escalated_unsafe" "$NOW_EPOCH"
                    return 1
                fi

                # Attempt restart
                if docker restart "$container" 2>/dev/null; then
                    log "OK" "Docker restart issued for $container"
                    update_container_state "$container" "restart_attempted" "$NOW_EPOCH"
                else
                    log "HIGH" "Docker restart FAILED for $container"
                    update_container_state "$container" "restart_failed" "$NOW_EPOCH"
                    return 1
                fi
            else
                log "INFO" "$container unhealthy for ${elapsed}s — waiting for ${UNHEALTHY_MIN_WAIT}s threshold"
            fi
            ;;

        "restart_attempted")
            # Check if restart helped
            local elapsed=$(( NOW_EPOCH - tracked_ts ))
            if [[ "$elapsed" -ge "$POST_RESTART_GRACE" ]]; then
                # Re-check health
                local new_health
                new_health="$(get_container_health "$container")"
                if [[ "$new_health" == "healthy" || "$new_health" == "starting" ]]; then
                    log "OK" "$container recovered after restart (health=$new_health)"
                    update_container_state "$container" "recovered" "$NOW_EPOCH"
                    return 0
                else
                    log "CRITICAL" "$container still unhealthy ${elapsed}s after restart — escalation needed"
                    update_container_state "$container" "escalated" "$NOW_EPOCH"
                    return 1
                fi
            else
                log "INFO" "$container was restarted ${elapsed}s ago — waiting for grace period (${POST_RESTART_GRACE}s)"
            fi
            ;;

        "escalated"|"escalated_unsafe")
            log "CRITICAL" "$container previously escalated — human intervention required"
            ;;

        *)
            # Unknown state — reset
            log "INFO" "Unknown tracked state '$tracked_status' for $container — resetting"
            update_container_state "$container" "unhealthy_first_seen" "$NOW_EPOCH"
            ;;
    esac
}

# ---- Status display ----
show_status() {
    echo "Docker Container Healer State"
    echo "=============================="
    echo ""

    local state
    state="$(read_state)"
    local containers
    containers="$(echo "$state" | python3 -c "
import json,sys
state = json.load(sys.stdin)
for name, info in state.get('containers', {}).items():
    print(f\"{name}|{info.get('status','?')}|{info.get('timestamp',0)}|{info.get('updated','?')}\")
" 2>/dev/null || true)"

    if [[ -z "$containers" ]]; then
        echo "  No containers tracked."
        return
    fi

    printf "  %-40s %-25s %-12s %s\n" "CONTAINER" "STATUS" "SINCE" "UPDATED"
    printf "  %-40s %-25s %-12s %s\n" "----------------------------------------" "-------------------------" "------------" "-----------------------------"
    while IFS='|' read -r name status ts updated; do
        [[ -z "$name" ]] && continue
        local since_str
        if [[ "$ts" -gt 0 ]]; then
            local elapsed=$(( NOW_EPOCH - ts ))
            since_str="${elapsed}s ago"
        else
            since_str="N/A"
        fi
        printf "  %-40s %-25s %-12s %s\n" "$name" "$status" "$since_str" "$updated"
    done <<< "$containers"

    echo ""
    echo "Unhealthy containers currently:"
    docker ps --filter "health=unhealthy" --format '  {{.Names}} ({{.Status}})' 2>/dev/null || echo "  (none)"
}

# ---- Main ----
main() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run)  DRY_RUN=true ;;
            --force)    FORCE=true ;;
            --status)   show_status; exit 0 ;;
            --help)     show_help ;;
        esac
    done

    init_state

    log "INFO" "Docker container healer starting $(if $DRY_RUN; then echo '(DRY RUN)'; fi)"

    # Find all unhealthy containers
    local unhealthy_containers
    unhealthy_containers="$(docker ps --filter "health=unhealthy" --format '{{.Names}}' 2>/dev/null || true)"

    if [[ -z "$unhealthy_containers" ]]; then
        log "INFO" "No unhealthy Docker containers detected"
        exit 0
    fi

    # Also check for "starting" state that's been stuck
    local starting_containers
    starting_containers="$(docker ps --filter "health=starting" --format '{{.Names}}' 2>/dev/null || true)"

    local escalated=0
    local healed=0

    # Process unhealthy containers
    while IFS= read -r container; do
        [[ -z "$container" ]] && continue
        handle_unhealthy "$container" "unhealthy" || ((escalated++))
    done <<< "$unhealthy_containers"

    # Process stuck-in-starting containers (>30 seconds = problematic)
    if [[ -n "$starting_containers" ]]; then
        while IFS= read -r container; do
            [[ -z "$container" ]] && continue
            # Check how long it's been starting
            local started_at
            started_at="$(docker inspect --format '{{.State.StartedAt}}' "$container" 2>/dev/null || echo "")"
            if [[ -n "$started_at" ]]; then
                local started_epoch
                started_epoch="$(date -d "$started_at" +%s 2>/dev/null || echo 0)"
                if [[ "$started_epoch" -gt 0 ]]; then
                    local starting_elapsed=$(( NOW_EPOCH - started_epoch ))
                    if [[ "$starting_elapsed" -gt 30 ]]; then
                        log "WARN" "$container has been 'starting' for ${starting_elapsed}s — treating as unhealthy"
                        handle_unhealthy "$container" "stuck_starting" || ((escalated++))
                    fi
                fi
            fi
        done <<< "$starting_containers"
    fi

    # Summary
    if [[ "$escalated" -gt 0 ]]; then
        log "INFO" "Docker container healer complete — escalated=$escalated"
        return 1
    fi
    log "INFO" "Docker container healer complete — no escalations"
    return 0
}

main "$@"
