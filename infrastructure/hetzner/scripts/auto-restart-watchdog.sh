#!/usr/bin/env bash
# ==============================================================================
# auto-restart-watchdog.sh — Auto-restart monitor for Docker containers
# ==============================================================================
#
# Watches Docker events for unexpected container deaths and automatically
# restarts them. Runs as a systemd service (auto-restart-watchdog.service).
#
# Behavior:
#   - Watches the Docker event stream for container "die" events
#   - Ignores containers stopped manually (via docker stop or compose down)
#   - If a container dies unexpectedly:
#     1. Logs the event with timestamp and exit code
#     2. Waits 5 seconds
#     3. Attempts restart via docker compose or docker start
#     4. If 3 failures occur within 10 minutes → sends alert
#   - Records all restart history to /opt/wheeler/logs/watchdog.log
#
# Alert Mechanisms:
#   - Log file (always)
#   - Slack webhook (if configured)
#   - Exit code 0 = all quiet, exit code 1+ = incidents tracked
#
# Configuration:
#   Export these environment variables or set in the systemd service file:
#     WATCHDOG_SLACK_WEBHOOK=   # Slack webhook URL for alerts
#     WATCHDOG_ALERT_EMAIL=      # Email for alerts (requires mail command)
#     WATCHDOG_CHECK_INTERVAL=1  # Seconds between event poll (default: 1)
#     WATCHDOG_RETRY_DELAY=5     # Seconds to wait before restart (default: 5)
#     WATCHDOG_MAX_RETRIES=3     # Max restarts in window (default: 3)
#     WATCHDOG_RETRY_WINDOW=600  # Retry window in seconds (default: 600 / 10min)
#     WATCHDOG_DRY_RUN=false     # If true, log but don't restart
# ==============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
SLACK_WEBHOOK="${WATCHDOG_SLACK_WEBHOOK:-}"
ALERT_EMAIL="${WATCHDOG_ALERT_EMAIL:-}"
CHECK_INTERVAL="${WATCHDOG_CHECK_INTERVAL:-1}"
RETRY_DELAY="${WATCHDOG_RETRY_DELAY:-5}"
MAX_RETRIES="${WATCHDOG_MAX_RETRIES:-3}"
RETRY_WINDOW="${WATCHDOG_RETRY_WINDOW:-600}"  # 10 minutes
DRY_RUN="${WATCHDOG_DRY_RUN:-false}"

LOG_FILE="${WATCHDOG_LOG_FILE:-/opt/wheeler/logs/watchdog.log}"
HISTORY_FILE="${WATCHDOG_HISTORY_FILE:-/opt/wheeler/logs/watchdog-history.jsonl}"
PID_FILE="/tmp/auto-restart-watchdog.pid"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Logging -----------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')

    mkdir -p "$(dirname "$LOG_FILE")"
    echo "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
    echo "${timestamp} [${level}] ${message}"
}

log_json() {
    local event="$1"
    local container="$2"
    local exit_code="$3"
    local action="$4"
    local detail="${5:-}"

    mkdir -p "$(dirname "$HISTORY_FILE")"
    local entry
    entry=$(cat <<ENTRY
{"timestamp":"$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')","event":"${event}","container":"${container}","exit_code":${exit_code},"action":"${action}","detail":"${detail}"}
ENTRY
)
    echo "$entry" >> "$HISTORY_FILE"

    # Keep only last 10000 entries
    tail -n 10000 "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
}

# --- Alerting ----------------------------------------------------------------
send_alert() {
    local container="$1"
    local exit_code="$2"
    local message="$3"
    local hostname
    hostname=$(hostname)

    # Slack alert
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        local payload
        payload=$(cat <<PAYLOAD
{
  "text": "🚨 *Watchdog Alert — ${hostname}*",
  "blocks": [
    {
      "type": "header",
      "text": {"type": "plain_text", "text": "🚨 Container Watchdog Alert"}
    },
    {
      "type": "section",
      "fields": [
        {"type": "mrkdwn", "text": "*Server:*\\n${hostname}"},
        {"type": "mrkdwn", "text": "*Container:*\\n${container}"},
        {"type": "mrkdwn", "text": "*Exit Code:*\\n${exit_code}"},
        {"type": "mrkdwn", "text": "*Action:*\\n${message}"}
      ]
    },
    {
      "type": "context",
      "elements": [
        {"type": "mrkdwn", "text": "Watchdog auto-restart system | $(date -u '+%Y-%m-%d %H:%M:%S UTC')"}
      ]
    }
  ]
}
PAYLOAD
)
        curl -s -X POST -H 'Content-type: application/json' \
            --data "$payload" "$SLACK_WEBHOOK" &>/dev/null || true
    fi

    # Email alert
    if [[ -n "$ALERT_EMAIL" ]] && command -v mail &>/dev/null; then
        echo "Watchdog Alert on ${hostname}
Container: ${container}
Exit Code: ${exit_code}
Message: ${message}
Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

This is an automated alert from the Wheeler AIOps container watchdog." \
            | mail -s "[WATCHDOG] ${container} alert on ${hostname}" "$ALERT_EMAIL" 2>/dev/null || true
    fi

    log "ALERT" "Sent alert for ${container}: ${message} (exit code: ${exit_code})"
}

# --- Restart tracking --------------------------------------------------------
declare -A FAILURE_COUNTS
declare -A FIRST_FAILURE_TIME

# Check if a container has exceeded the retry threshold
check_threshold() {
    local container="$1"
    local now
    now=$(date +%s)
    local first_fail="${FIRST_FAILURE_TIME[$container]:-0}"
    local count="${FAILURE_COUNTS[$container]:-0}"

    # Reset if outside the window
    if [[ $((now - first_fail)) -gt $RETRY_WINDOW ]]; then
        FAILURE_COUNTS["$container"]=1
        FIRST_FAILURE_TIME["$container"]=$now
        return 0  # OK to restart
    fi

    if [[ "$count" -ge "$MAX_RETRIES" ]]; then
        return 1  # Threshold exceeded
    fi

    return 0  # OK to restart
}

# --- Determine if container was stopped manually -----------------------------
was_manual_stop() {
    local container_id="$1"

    # Check if the container was stopped by "docker stop" or "docker compose"
    # We look at the container's exit reason via docker inspect
    local exit_reason
    exit_reason=$(docker inspect "$container_id" --format '{{.State.Error}}' 2>/dev/null || echo "")

    local exit_code
    exit_code=$(docker inspect "$container_id" --format '{{.State.ExitCode}}' 2>/dev/null || echo "0")

    # Exit code 0 + no error usually means intentional stop
    if [[ "$exit_code" == "0" ]] && [[ -z "$exit_reason" ]]; then
        return 0  # Was manual
    fi

    # Check if docker compose is running a down/stop for this project
    # This is heuristic; best effort
    if [[ -f "/var/run/docker-compose-${container_id}.lock" ]]; then
        return 0  # Manual
    fi

    return 1  # Unexpected
}

# --- Restart a container -----------------------------------------------------
restart_container() {
    local container_name="$1"
    local container_id="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would restart container: ${container_name} (${container_id})"
        log_json "dry_restart" "$container_name" "0" "dry_run" "DRY_RUN mode"
        return 0
    fi

    log "INFO" "Attempting restart of ${container_name}..."

    # Wait before restart
    sleep "$RETRY_DELAY"

    # Strategy 1: Try docker compose (preferred — preserves project context)
    local compose_project
    compose_project=$(docker inspect "$container_id" \
        --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo "")

    if [[ -n "$compose_project" ]]; then
        local compose_service
        compose_service=$(docker inspect "$container_id" \
            --format '{{index .Config.Labels "com.docker.compose.service"}}' 2>/dev/null || echo "")

        if [[ -n "$compose_service" ]]; then
            log "INFO" "Restarting via docker compose: ${compose_project} ${compose_service}"
            docker compose --project-name "$compose_project" up -d --no-deps "$compose_service" 2>&1 | while IFS= read -r line; do
                log "INFO" "compose: ${line}"
            done
            log_json "restart" "$container_name" "0" "docker_compose" "project=${compose_project} service=${compose_service}"
            return 0
        fi
    fi

    # Strategy 2: Simple docker restart
    log "INFO" "Restarting via docker start: ${container_name}"
    if docker start "$container_id" 2>&1; then
        log_json "restart" "$container_name" "0" "docker_start" ""
        return 0
    else
        log_json "restart_failed" "$container_name" "1" "docker_start_failed" ""
        return 1
    fi
}

# --- Process a container die event -------------------------------------------
handle_container_die() {
    local container_id="$1"
    local exit_code="$2"

    # Get container name
    local container_name
    container_name=$(docker inspect "$container_id" \
        --format '{{.Name}}' 2>/dev/null | sed 's/^\///' || echo "unknown")

    if [[ -z "$container_name" ]] || [[ "$container_name" == "unknown" ]]; then
        return 0  # Container already removed
    fi

    log "WARN" "Container died: ${container_name} (exit code: ${exit_code})"

    # Check if this was a manual stop
    if was_manual_stop "$container_id"; then
        log "INFO" "Container ${container_name} was stopped manually. Not restarting."
        log_json "manual_stop" "$container_name" "$exit_code" "ignored" "Manual stop detected"
        return 0
    fi

    # Check restart policy
    local restart_policy
    restart_policy=$(docker inspect "$container_id" \
        --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "")

    if [[ "$restart_policy" == "always" ]] || [[ "$restart_policy" == "unless-stopped" ]]; then
        log "INFO" "Container ${container_name} has restart policy '${restart_policy}'. Docker will handle it."
        # Still track it — Docker's restart policy may not fire correctly for some exit codes
    fi

    # Update failure tracking
    local now
    now=$(date +%s)
    local first_fail="${FIRST_FAILURE_TIME[$container_name]:-0}"

    if [[ $first_fail -eq 0 ]]; then
        FIRST_FAILURE_TIME["$container_name"]=$now
        FAILURE_COUNTS["$container_name"]=1
    else
        # Check if we're still within the window
        if [[ $((now - first_fail)) -le $RETRY_WINDOW ]]; then
            FAILURE_COUNTS["$container_name"]=$((FAILURE_COUNTS["$container_name"] + 1))
        else
            # Window expired, reset
            FIRST_FAILURE_TIME["$container_name"]=$now
            FAILURE_COUNTS["$container_name"]=1
        fi
    fi

    local current_count="${FAILURE_COUNTS[$container_name]}"
    log "INFO" "Failure count for ${container_name}: ${current_count}/${MAX_RETRIES} in retry window"

    # Check threshold
    if ! check_threshold "$container_name"; then
        local msg="Container ${container_name} has failed ${current_count} times in ${RETRY_WINDOW}s. Exceeded threshold (${MAX_RETRIES}). Escalating."
        log "ERROR" "${msg}"
        log_json "threshold_exceeded" "$container_name" "$exit_code" "escalated" "${current_count} failures in window"
        send_alert "$container_name" "$exit_code" "${msg} — manual intervention required"
        return 1
    fi

    # Restart
    if restart_container "$container_name" "$container_id"; then
        log "INFO" "Successfully restarted ${container_name}"
        # If we had previous failures but this succeeded, reduce count
        if [[ "${FAILURE_COUNTS[$container_name]:-0}" -gt 1 ]]; then
            FAILURE_COUNTS["$container_name"]=$((FAILURE_COUNTS["$container_name"] - 1))
        fi
    else
        log "ERROR" "Failed to restart ${container_name}"
        send_alert "$container_name" "$exit_code" "Restart attempt failed"
    fi
}

# --- Cleanup on exit ---------------------------------------------------------
cleanup() {
    log "INFO" "Watchdog shutting down..."
    rm -f "$PID_FILE"
    exit 0
}

# --- Main watchdog loop ------------------------------------------------------
main() {
    local OPT_CHECK_INTERVAL="$CHECK_INTERVAL"

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interval)
                OPT_CHECK_INTERVAL="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--interval <seconds>] [--dry-run]"
                echo ""
                echo "Runs the container auto-restart watchdog."
                echo "Designed to run as a systemd service."
                echo ""
                echo "Options:"
                echo "  --interval <s>  Event poll interval (default: ${CHECK_INTERVAL}s)"
                echo "  --dry-run       Log actions but don't restart"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    # Trap signals
    trap cleanup SIGINT SIGTERM SIGHUP

    # Write PID file
    echo $$ > "$PID_FILE"

    log "INFO" "=============================================="
    log "INFO" "  Auto-Restart Watchdog Starting"
    log "INFO" "  PID: $$"
    log "INFO" "  Interval: ${OPT_CHECK_INTERVAL}s"
    log "INFO" "  Max retries: ${MAX_RETRIES} per ${RETRY_WINDOW}s window"
    log "INFO" "  Dry run: ${DRY_RUN}"
    log "INFO" "=============================================="

    # Log startup
    log_json "startup" "watchdog" "0" "started" "PID: $$, interval: ${OPT_CHECK_INTERVAL}s"

    # Main event loop
    # Use "docker events --filter" to get only die events
    docker events \
        --filter 'event=die' \
        --filter 'type=container' \
        --format '{{.ID}}|{{.Status}}|{{.Actor.Attributes.exitCode}}' 2>&1 | while IFS='|' read -r container_id status exit_code_str; do

        # Parse exit code
        local exit_code="${exit_code_str:-0}"

        # Ignore exit code 0 which is typically graceful shutdown
        if [[ "$exit_code" == "0" ]]; then
            continue
        fi

        log "INFO" "Die event: container=${container_id} exit_code=${exit_code}"

        # Handle the event
        handle_container_die "$container_id" "$exit_code" || true
    done

    # The docker events command will exit if Docker restarts. We should restart too.
    log "WARN" "Docker events stream ended. Restarting watchdog..."
    exec "$0" "$@"
}

main "$@"
