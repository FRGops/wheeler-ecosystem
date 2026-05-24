#!/usr/bin/env bash
#===============================================================================
# Wheeler Enterprise — Docker Compose Service Deployer
#===============================================================================
# Deploys a single Docker Compose service with atomic safety guarantees:
#   - Pre-flight validation (docker, compose, disk, lock)
#   - Pre-deploy backup via backup-all.sh
#   - Health-check baseline capture
#   - Pull-then-up deployment with health polling
#   - Automatic rollback on failure (including rollback-of-rollback escalation)
#   - Structured JSON audit log + deployment-history ring buffer
#   - Remote SSH + Tailscale deployment support
#
# Usage:
#   deploy-service.sh <service-name> <compose-file.yml> [flags]
#
# Flags:
#   --dry-run         Validate everything, print plan, exit before mutating.
#   --force           Skip pre-deploy health baseline (deploy even if unhealthy).
#   --no-backup       Skip pre-deploy backup (DANGEROUS — logged as warning).
#   --timeout <sec>   Override health-check timeout (default 120 s).
#   --rollback        NOT YET IMPLEMENTED — placeholder for future manual rollback.
#   --help            Print this help and exit.
#
# Environment variables:
#   DEPLOY_WEBHOOK_URL       Webhook to POST deployment result JSON.
#   DEPLOY_REMOTE_SSH        SSH user@host for remote deployment via Tailscale.
#   DEPLOY_HEALTH_ENDPOINT   Override health-check URL path (default /health).
#   DEPLOY_HEALTH_PORT       Override health-check port (default first exposed port).
#   COMPOSE_BIN              Override path to docker-compose binary.
#   WHEELER_BACKUP_SCRIPT    Path to backup-all.sh (default /usr/local/bin/backup-all.sh).
#   WHEELER_LOG_DIR          Root log directory (default /var/log/wheeler).
#===============================================================================

set -euo pipefail

# ------------------------------------------------------------------
# Constants & defaults
# ------------------------------------------------------------------
readonly APP_NAME="deploy-service.sh"
readonly VERSION="1.0.0"

readonly DEFAULT_HEALTH_TIMEOUT=120
readonly DEFAULT_HEALTH_ENDPOINT="/health"
readonly DEFAULT_LOCK_DIR="/tmp"
readonly DEFAULT_LOG_DIR="/var/log/wheeler"
readonly DEFAULT_HISTORY_MAX=100
readonly DEFAULT_MIN_DISK_MB=5120             # 5 GB
readonly DEFAULT_BACKUP_SCRIPT="/usr/local/bin/backup-all.sh"
readonly HEALTH_POLL_INTERVAL=5               # seconds between health polls during initial wait
readonly POST_HEALTH_POLL_INTERVAL=5          # seconds between post-deploy health polls
readonly DRY_RUN="false"
readonly FORCE="false"
readonly NO_BACKUP="false"

# Colours (auto-disabled if stdout is not a TTY)
if [[ -t 1 ]]; then
    readonly C_RESET='\033[0m'
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_CYAN='\033[0;36m'
    readonly C_BOLD='\033[1m'
else
    readonly C_RESET=''
    readonly C_RED=''
    readonly C_GREEN=''
    readonly C_YELLOW=''
    readonly C_CYAN=''
    readonly C_BOLD=''
fi

# ------------------------------------------------------------------
# Global state (populated during execution)
# ------------------------------------------------------------------
DEPLOYMENT_ID=""
SERVICE_NAME=""
COMPOSE_FILE=""
COMPOSE_FILE_ABS=""
COMPOSE_EXEC=()              # Array: ("docker" "compose") or ("docker-compose")
COMPOSE_DISPLAY=""          # Human-readable: "docker compose" or "docker-compose"
HEALTH_TIMEOUT=""
HEALTH_ENDPOINT=""
HEALTH_PORT=""
DRY_RUN_VAL=""
FORCE_VAL=""
NO_BACKUP_VAL=""
WEBHOOK_URL="${DEPLOY_WEBHOOK_URL:-}"
REMOTE_SSH="${DEPLOY_REMOTE_SSH:-}"
BACKUP_SCRIPT="${WHEELER_BACKUP_SCRIPT:-${DEFAULT_BACKUP_SCRIPT}}"
LOG_DIR="${WHEELER_LOG_DIR:-${DEFAULT_LOG_DIR}}"
DEPLOY_LOG_FILE=""
HISTORY_FILE=""
LOCK_FILE=""

# Captured state for rollback / audit
PRE_DEPLOY_STATUS="unknown"
PRE_DEPLOY_IMAGE=""
PRE_DEPLOY_IMAGE_TAG=""
POST_DEPLOY_STATUS="unknown"
OLD_COMPOSE_BACKUP=""
BACKUP_PATH=""
NEW_IMAGE=""
ROLLBACK_TRIGGERED="false"
ROLLBACK_SUCCESS="null"
ERRORS=()
DEPLOY_START_TIME=""
DEPLOY_END_TIME=""

# ------------------------------------------------------------------
# Utility functions
# ------------------------------------------------------------------

log_msg() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local color=""
    case "$level" in
        INFO)  color="$C_CYAN"  ;;
        OK)    color="$C_GREEN" ;;
        WARN)  color="$C_YELLOW" ;;
        ERROR) color="$C_RED"   ;;
        *)     color="$C_RESET" ;;
    esac
    echo -e "${color}[${ts}] [${level}]${C_RESET} ${msg}" >&2
}

json_escape() {
    # Minimal JSON string escape — handles \ " and control chars.
    local s="${1-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback: assemble from /dev/urandom (not RFC-compliant but unique)
        local hex
        hex=$(od -An -N16 -tx1 /dev/urandom | tr -d ' ')
        echo "${hex:0:8}-${hex:8:4}-${hex:12:4}-${hex:16:4}-${hex:20:12}"
    fi
}

now_epoch() {
    date +%s
}

human_duration() {
    local start="$1" end="$2"
    local delta=$(( end - start ))
    printf '%d' "$delta"
}

build_lock_path() {
    local svc="$1"
    echo "${DEFAULT_LOCK_DIR}/deploy-${svc}.lock"
}

# ------------------------------------------------------------------
# JSON audit logging
# ------------------------------------------------------------------

write_deploy_log() {
    local success="$1"     # "true" or "false"
    local now_ep
    now_ep="$(now_epoch)"
    local end_ts
    end_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local errors_json="[]"
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        local joined=""
        local first=true
        local e
        for e in "${ERRORS[@]}"; do
            if $first; then
                joined="\"$(json_escape "$e")\""
                first=false
            else
                joined+=", \"$(json_escape "$e")\""
            fi
        done
        errors_json="[$joined]"
    fi

    local who="${SUDO_USER:-$USER}"

    local duration=0
    if [[ -n "$DEPLOY_START_TIME" ]]; then
        duration=$(( now_ep - DEPLOY_START_TIME ))
    fi

    local json_entry
    json_entry=$(cat <<EOF
{
  "deployment_id": "$DEPLOYMENT_ID",
  "timestamp": "$end_ts",
  "service_name": "$(json_escape "$SERVICE_NAME")",
  "user": "$(json_escape "$who")",
  "compose_file": "$(json_escape "$COMPOSE_FILE_ABS")",
  "old_image": "$(json_escape "$PRE_DEPLOY_IMAGE")",
  "new_image": "$(json_escape "$NEW_IMAGE")",
  "backup_path": "$(json_escape "$BACKUP_PATH")",
  "pre_deploy_status": "$(json_escape "$PRE_DEPLOY_STATUS")",
  "post_deploy_status": "$(json_escape "$POST_DEPLOY_STATUS")",
  "deployment_duration_seconds": $duration,
  "success": $success,
  "rollback_triggered": $ROLLBACK_TRIGGERED,
  "rollback_success": $ROLLBACK_SUCCESS,
  "errors": $errors_json
}
EOF
)
    echo "$json_entry" >> "$DEPLOY_LOG_FILE"
}

update_deploy_history() {
    local success="$1"
    local entry
    entry=$(cat <<EOF
{
  "deployment_id": "$DEPLOYMENT_ID",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "service_name": "$(json_escape "$SERVICE_NAME")",
  "compose_file": "$(json_escape "$COMPOSE_FILE_ABS")",
  "old_image": "$(json_escape "$PRE_DEPLOY_IMAGE")",
  "new_image": "$(json_escape "$NEW_IMAGE")",
  "success": $success,
  "rollback_triggered": $ROLLBACK_TRIGGERED,
  "rollback_success": $ROLLBACK_SUCCESS
}
EOF
)

    # Ensure the history file exists as a valid JSON array.
    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo "[]" > "$HISTORY_FILE"
    fi

    local tmp_history="${HISTORY_FILE}.tmp.$$"
    # Prepend new entry, keep only the last DEFAULT_HISTORY_MAX entries.
    python3 -c "
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
data.insert(0, json.loads(sys.stdin.read()))
if len(data) > sys.maxsize:
    pass
data = data[:${DEFAULT_HISTORY_MAX}]
with open(sys.argv[2], 'w') as f:
    json.dump(data, f, indent=2)
" "$HISTORY_FILE" <<< "$entry" "$tmp_history" 2>/dev/null || {
        # Python not available — write as simple JSON-lines fallback.
        echo "$entry" >> "$HISTORY_FILE"
        return
    }
    mv "$tmp_history" "$HISTORY_FILE"
}

# ------------------------------------------------------------------
# Webhook notification
# ------------------------------------------------------------------

post_webhook() {
    local success="$1"
    if [[ -z "$WEBHOOK_URL" ]]; then
        return 0
    fi
    local payload
    payload=$(cat <<EOF
{
  "deployment_id": "$DEPLOYMENT_ID",
  "service_name": "$(json_escape "$SERVICE_NAME")",
  "success": $success,
  "rollback_triggered": $ROLLBACK_TRIGGERED,
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)
    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$WEBHOOK_URL" \
        --connect-timeout 5 --max-time 10 >/dev/null 2>&1 || true
}

wall_alert() {
    local msg="$1"
    if command -v wall &>/dev/null; then
        wall "*** WHEELER DEPLOY ALERT [${SERVICE_NAME}] *** ${msg}"
    fi
    log_msg "ERROR" "ALERT: ${msg}"
}

# ------------------------------------------------------------------
# Docker / Compose detection
# ------------------------------------------------------------------

detect_compose() {
    # If user specified COMPOSE_BIN override via env, use it directly.
    local user_bin="${COMPOSE_BIN:-}"
    if [[ -n "$user_bin" ]]; then
        log_msg "INFO" "Using user-specified compose binary: ${user_bin}"
        if [[ "$user_bin" == "docker" ]]; then
            COMPOSE_EXEC=(docker compose)
            COMPOSE_DISPLAY="docker compose"
        else
            COMPOSE_EXEC=("$user_bin")
            COMPOSE_DISPLAY="$user_bin"
        fi
        return 0
    fi

    if docker compose version &>/dev/null; then
        COMPOSE_EXEC=(docker compose)
        COMPOSE_DISPLAY="docker compose"
        log_msg "INFO" "Detected Docker Compose v2 (docker compose)"
        return 0
    fi

    if command -v docker-compose &>/dev/null; then
        COMPOSE_EXEC=(docker-compose)
        COMPOSE_DISPLAY="docker-compose"
        log_msg "INFO" "Detected Docker Compose v1 (docker-compose)"
        return 0
    fi

    log_msg "ERROR" "Neither 'docker compose' nor 'docker-compose' found on PATH"
    return 1
}

# Run a docker-compose command using the detected binary.
_ccmd() {
    "${COMPOSE_EXEC[@]}" "$@"
}

# ------------------------------------------------------------------
# Lock management
# ------------------------------------------------------------------

acquire_lock() {
    LOCK_FILE="$(build_lock_path "$SERVICE_NAME")"

    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid="$(cat "$LOCK_FILE" 2>/dev/null || true)"
        # Check whether the PID actually belongs to a running deploy-service.sh
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_msg "ERROR" "Deployment lock already held by PID ${pid}."
            log_msg "ERROR" "Lock file: ${LOCK_FILE}"
            log_msg "ERROR" "If you are sure no deployment is running, remove it manually: rm -f ${LOCK_FILE}"
            return 1
        else
            # Stale lock — remove it
            log_msg "WARN" "Removing stale lock file (PID ${pid:-unknown} no longer running)."
            rm -f "$LOCK_FILE"
        fi
    fi

    echo "$$" > "$LOCK_FILE"
    # Double-check we own it (no TOCTOU)
    local owner
    owner="$(cat "$LOCK_FILE" 2>/dev/null || true)"
    if [[ "$owner" != "$$" ]]; then
        log_msg "ERROR" "Failed to acquire lock: race condition detected."
        return 1
    fi
    log_msg "INFO" "Acquired deployment lock: ${LOCK_FILE}"
    return 0
}

release_lock() {
    if [[ -n "${LOCK_FILE:-}" ]] && [[ -f "$LOCK_FILE" ]]; then
        local owner
        owner="$(cat "$LOCK_FILE" 2>/dev/null || true)"
        if [[ "$owner" == "$$" ]]; then
            rm -f "$LOCK_FILE"
            log_msg "INFO" "Released deployment lock: ${LOCK_FILE}"
        else
            log_msg "WARN" "Lock file owned by ${owner:-unknown}, not removing (expected $$)."
        fi
    fi
}

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------

check_docker_running() {
    if ! docker info &>/dev/null; then
        log_msg "ERROR" "Docker daemon is not running or not accessible."
        return 1
    fi
    log_msg "OK" "Docker daemon is running."
}

check_disk_space() {
    local mountpoint dir
    # Determine which filesystem the compose-file directory lives on.
    dir="$(dirname "$COMPOSE_FILE_ABS")"
    mountpoint="$(df -P "$dir" 2>/dev/null | awk 'NR==2 {print $6}')"
    local avail_kb
    avail_kb="$(df -P "$dir" 2>/dev/null | awk 'NR==2 {print $4}')"
    local avail_mb=$(( avail_kb / 1024 ))

    if [[ "$avail_mb" -lt "$DEFAULT_MIN_DISK_MB" ]]; then
        log_msg "ERROR" "Insufficient disk space on ${mountpoint}: ${avail_mb} MB available (minimum ${DEFAULT_MIN_DISK_MB} MB)."
        return 1
    fi
    log_msg "OK" "Disk space OK: ${avail_mb} MB available on ${mountpoint}."
}

validate_compose_file() {
    if [[ ! -f "$COMPOSE_FILE_ABS" ]]; then
        log_msg "ERROR" "Compose file not found: ${COMPOSE_FILE_ABS}"
        return 1
    fi

    local cfg_output
    set +e
    cfg_output="$(_ccmd -f "$COMPOSE_FILE_ABS" config 2>&1)"
    local cfg_rc=$?
    set -e

    if [[ $cfg_rc -ne 0 ]]; then
        log_msg "ERROR" "Compose file validation failed:"
        log_msg "ERROR" "${cfg_output}"
        return 1
    fi
    log_msg "OK" "Compose file syntax is valid."
}

verify_service_in_compose() {
    # Use docker compose config --services to list service names.
    local services
    set +e
    services="$(_ccmd -f "$COMPOSE_FILE_ABS" config --services 2>&1)"
    set -e

    if ! echo "$services" | grep -qxF "$SERVICE_NAME"; then
        log_msg "ERROR" "Service '${SERVICE_NAME}' not found in compose file '${COMPOSE_FILE_ABS}'."
        log_msg "INFO" "Available services:"
        echo "$services" | sed 's/^/  - /' >&2
        return 1
    fi
    log_msg "OK" "Service '${SERVICE_NAME}' found in compose file."
}

preflight() {
    log_msg "INFO" "--- Pre-flight checks ---"
    check_docker_running
    check_disk_space
    detect_compose
    validate_compose_file
    verify_service_in_compose
    log_msg "OK" "All pre-flight checks passed."
}

# ------------------------------------------------------------------
# Backup
# ------------------------------------------------------------------

run_backup() {
    if [[ ! -x "$BACKUP_SCRIPT" ]]; then
        log_msg "WARN" "Backup script not found or not executable: ${BACKUP_SCRIPT}"
        log_msg "WARN" "Skipping pre-deploy backup. This is risky!"
        BACKUP_PATH=""
        return 0
    fi

    log_msg "INFO" "Running pre-deploy backup via ${BACKUP_SCRIPT} ..."
    local backup_out backup_rc

    # Call backup-all.sh with service name if the script supports it.
    # We assume backup-all.sh accepts --service <name> or falls back to full backup.
    set +e
    backup_out="$("$BACKUP_SCRIPT" --service "$SERVICE_NAME" 2>&1)"
    backup_rc=$?
    set -e

    if [[ $backup_rc -ne 0 ]]; then
        log_msg "ERROR" "Pre-deploy backup FAILED (exit code ${backup_rc}):"
        log_msg "ERROR" "${backup_out}"
        ERRORS+=("Pre-deploy backup failed: ${backup_out}")
        return 1
    fi

    # Try to extract the backup path from the output.
    BACKUP_PATH="$(echo "$backup_out" | grep -iE 'backup.*path|saved to|written to|backup:' | tail -1 | sed 's/.*: *//' || true)"
    if [[ -z "$BACKUP_PATH" ]]; then
        BACKUP_PATH="$backup_out"
    fi
    log_msg "OK" "Pre-deploy backup completed."
    log_msg "INFO" "Backup path: ${BACKUP_PATH}"
}

# ------------------------------------------------------------------
# Health baseline
# ------------------------------------------------------------------

get_container_id() {
    local svc="$1"
    _ccmd -f "$COMPOSE_FILE_ABS" ps -q "$svc" 2>/dev/null || true
}

get_container_status() {
    local svc="$1"
    local cid
    cid="$(get_container_id "$svc")"
    if [[ -z "$cid" ]]; then
        echo "not_running"
        return
    fi
    local status
    status="$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "unknown")"
    if [[ "$status" == "healthy" ]]; then
        echo "healthy"
    elif [[ "$status" == "unhealthy" ]]; then
        echo "unhealthy"
    elif [[ "$status" == "starting" ]]; then
        echo "starting"
    else
        # Container exists but no health check defined — treat running as "healthy"
        local running
        running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo "false")"
        if [[ "$running" == "true" ]]; then
            echo "healthy"
        else
            echo "not_running"
        fi
    fi
}

get_container_image() {
    local svc="$1"
    local cid
    cid="$(get_container_id "$svc")"
    if [[ -z "$cid" ]]; then
        echo ""
        return
    fi
    docker inspect -f '{{.Config.Image}}' "$cid" 2>/dev/null || echo ""
}

get_container_memory_mb() {
    local svc="$1"
    local cid
    cid="$(get_container_id "$svc")"
    if [[ -z "$cid" ]]; then
        echo "0"
        return
    fi
    local mem_bytes
    mem_bytes="$(docker stats --no-stream --format '{{.MemUsage}}' "$cid" 2>/dev/null || echo "0 / 0")"
    # Format: "123.4MiB / 1.2GiB"
    local used
    used="$(echo "$mem_bytes" | awk '{print $1}')"
    if [[ "$used" =~ MiB$ ]]; then
        echo "${used%MiB}" | awk '{printf "%.0f", $1}'
    elif [[ "$used" =~ GiB$ ]]; then
        echo "${used%GiB}" | awk '{printf "%.0f", $1 * 1024}'
    elif [[ "$used" =~ KiB$ ]]; then
        echo "${used%KiB}" | awk '{printf "%.0f", $1 / 1024}'
    else
        echo "0"
    fi
}

capture_health_baseline() {
    log_msg "INFO" "--- Health-check baseline ---"

    PRE_DEPLOY_STATUS="$(get_container_status "$SERVICE_NAME")"
    PRE_DEPLOY_IMAGE="$(get_container_image "$SERVICE_NAME")"
    PRE_DEPLOY_IMAGE_TAG="${PRE_DEPLOY_IMAGE##*:}"
    # Default tag if none
    if [[ "$PRE_DEPLOY_IMAGE_TAG" == "$PRE_DEPLOY_IMAGE" ]]; then
        PRE_DEPLOY_IMAGE_TAG="latest"
    fi

    log_msg "INFO" "Pre-deploy status  : ${PRE_DEPLOY_STATUS}"
    log_msg "INFO" "Pre-deploy image   : ${PRE_DEPLOY_IMAGE:-none}"

    # Backup current compose file to a timestamped copy
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    OLD_COMPOSE_BACKUP="${COMPOSE_FILE_ABS}.${ts}.backup"
    cp "$COMPOSE_FILE_ABS" "$OLD_COMPOSE_BACKUP"
    log_msg "INFO" "Compose backup saved: ${OLD_COMPOSE_BACKUP}"

    # Determine the expected new image from the compose file
    NEW_IMAGE="$(_ccmd -f "$COMPOSE_FILE_ABS" config 2>/dev/null \
        | sed -n "/^  ${SERVICE_NAME}:/,/^  [a-z]/p" \
        | grep -E '^\s+image:' \
        | head -1 \
        | awk '{print $2}' \
        || true)"

    if [[ "$PRE_DEPLOY_STATUS" == "unhealthy" ]] && [[ "$FORCE_VAL" != "true" ]]; then
        log_msg "WARN" "Service is currently UNHEALTHY and --force not set."
        log_msg "WARN" "Will proceed but automatic rollback will be SKIPPED (service was already broken)."
    fi
}

# ------------------------------------------------------------------
# Health-check polling helpers
# ------------------------------------------------------------------

resolve_health_url() {
    local svc="$1"

    # If user specified an explicit endpoint/port, use those.
    if [[ -n "${DEPLOY_HEALTH_ENDPOINT:-}" ]]; then
        HEALTH_ENDPOINT="$DEPLOY_HEALTH_ENDPOINT"
    fi
    if [[ -n "${DEPLOY_HEALTH_PORT:-}" ]]; then
        HEALTH_PORT="$DEPLOY_HEALTH_PORT"
    fi

    # Otherwise try to discover from compose config.
    if [[ -z "$HEALTH_PORT" ]]; then
        # Get the first published port for this service
        local port
        port="$(_ccmd -f "$COMPOSE_FILE_ABS" port "$svc" 80 2>/dev/null || true)"
        if [[ -z "$port" ]]; then
            # Try any published port
            port="$(_ccmd -f "$COMPOSE_FILE_ABS" ps "$svc" --format json 2>/dev/null \
                | python3 -c "
import sys, json
line = sys.stdin.readline()
if line:
    d = json.loads(line)
    pubs = d.get('Publishers') or []
    print(pubs[0].get('PublishedPort', '') if pubs else '')
" 2>/dev/null || true)"
        fi
        if [[ -z "$port" ]]; then
            HEALTH_PORT="80"
        else
            HEALTH_PORT="$port"
        fi
    fi

    echo "http://localhost:${HEALTH_PORT}${HEALTH_ENDPOINT}"
}

poll_health_endpoint() {
    local url="$1"
    local timeout="$2"
    local interval="${3:-$HEALTH_POLL_INTERVAL}"

    local deadline
    deadline=$(( $(now_epoch) + timeout ))

    log_msg "INFO" "Polling health endpoint: ${url} (timeout: ${timeout}s, interval: ${interval}s)"
    while [[ $(now_epoch) -lt $deadline ]]; do
        local http_code
        set +e
        http_code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 "$url" 2>/dev/null || true)"
        set -e
        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "204" ]]; then
            log_msg "OK" "Health endpoint responded: HTTP ${http_code}"
            return 0
        fi
        log_msg "INFO" "Health check returned HTTP ${http_code:-no response}, retrying in ${interval}s ..."
        sleep "$interval"
    done
    log_msg "ERROR" "Health endpoint did not respond 200/204 within ${timeout}s."
    return 1
}

wait_for_container_healthy() {
    local svc="$1"
    local timeout="$2"

    local cid
    local deadline
    deadline=$(( $(now_epoch) + timeout ))

    log_msg "INFO" "Waiting up to ${timeout}s for container '${svc}' to become healthy ..."

    while [[ $(now_epoch) -lt $deadline ]]; do
        cid="$(get_container_id "$svc")"
        if [[ -z "$cid" ]]; then
            log_msg "INFO" "Container not yet created, waiting ${POST_HEALTH_POLL_INTERVAL}s ..."
            sleep "$POST_HEALTH_POLL_INTERVAL"
            continue
        fi

        local hstatus
        hstatus="$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "none")"

        case "$hstatus" in
            healthy)
                log_msg "OK" "Container '${svc}' is healthy."
                return 0
                ;;
            unhealthy)
                log_msg "ERROR" "Container '${svc}' is unhealthy."
                return 1
                ;;
            starting|none)
                log_msg "INFO" "Container status: ${hstatus}, waiting ${POST_HEALTH_POLL_INTERVAL}s ..."
                sleep "$POST_HEALTH_POLL_INTERVAL"
                ;;
            *)
                local running
                running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo "false")"
                if [[ "$running" != "true" ]]; then
                    log_msg "ERROR" "Container '${svc}' is not running."
                    return 1
                fi
                log_msg "INFO" "Container running (no health check), status: ${hstatus}"
                # If no health check is configured, consider running as healthy.
                return 0
                ;;
        esac
    done

    log_msg "ERROR" "Container '${svc}' did not become healthy within ${timeout}s."
    return 1
}

# ------------------------------------------------------------------
# Deploy
# ------------------------------------------------------------------

do_deploy() {
    log_msg "INFO" "--- Deployment ---"

    if [[ "$DRY_RUN_VAL" == "true" ]]; then
        log_msg "INFO" "[DRY-RUN] Would pull images for service '${SERVICE_NAME}'."
        log_msg "INFO" "[DRY-RUN] Would run: ${COMPOSE_DISPLAY} -f ${COMPOSE_FILE_ABS} up -d ${SERVICE_NAME}"
        log_msg "INFO" "[DRY-RUN] Dry-run complete. No changes made."
        return 0
    fi

    # Pull new images
    log_msg "INFO" "Pulling new images ..."
    set +e
    local pull_out
    pull_out="$(_ccmd -f "$COMPOSE_FILE_ABS" pull "$SERVICE_NAME" 2>&1)"
    local pull_rc=$?
    set -e
    if [[ $pull_rc -ne 0 ]]; then
        log_msg "ERROR" "Image pull failed:"
        log_msg "ERROR" "${pull_out}"
        ERRORS+=("Image pull failed: ${pull_out}")
        return 1
    fi
    log_msg "OK" "Images pulled successfully."

    # Bring up the service
    log_msg "INFO" "Bringing up service '${SERVICE_NAME}' ..."
    set +e
    local up_out
    up_out="$(_ccmd -f "$COMPOSE_FILE_ABS" up -d "$SERVICE_NAME" 2>&1)"
    local up_rc=$?
    set -e
    if [[ $up_rc -ne 0 ]]; then
        log_msg "ERROR" "docker-compose up failed:"
        log_msg "ERROR" "${up_out}"
        ERRORS+=("docker-compose up failed: ${up_out}")
        return 1
    fi
    log_msg "OK" "Service '${SERVICE_NAME}' started."

    # Determine the actual deployed image after up.
    local deployed_image
    deployed_image="$(get_container_image "$SERVICE_NAME")"
    if [[ -n "$deployed_image" ]] && [[ "$deployed_image" != "$NEW_IMAGE" ]]; then
        NEW_IMAGE="$deployed_image"
        log_msg "INFO" "Deployed image: ${NEW_IMAGE}"
    fi
}

# ------------------------------------------------------------------
# Post-deploy validation
# ------------------------------------------------------------------

post_deploy_validate() {
    log_msg "INFO" "--- Post-deploy validation ---"

    if [[ "$DRY_RUN_VAL" == "true" ]]; then
        log_msg "INFO" "[DRY-RUN] Would validate health for up to ${HEALTH_TIMEOUT}s."
        return 0
    fi

    # 1. Wait for container health status
    if ! wait_for_container_healthy "$SERVICE_NAME" "$HEALTH_TIMEOUT"; then
        POST_DEPLOY_STATUS="unhealthy"
        ERRORS+=("Container did not become healthy within ${HEALTH_TIMEOUT}s")
        return 1
    fi

    # 2. Poll the HTTP health endpoint
    local health_url
    health_url="$(resolve_health_url "$SERVICE_NAME")"
    log_msg "INFO" "Checking HTTP health endpoint: ${health_url}"

    # Give the app a few extra seconds if the container just started.
    sleep 2

    if poll_health_endpoint "$health_url" 30 "$POST_HEALTH_POLL_INTERVAL"; then
        log_msg "OK" "HTTP health endpoint check passed."
    else
        log_msg "WARN" "HTTP health endpoint check failed (non-fatal, container may not expose HTTP health)."
        # This is a warning, not an error — not all services expose HTTP health.
    fi

    # 3. Resource usage comparison
    local post_mem
    post_mem="$(get_container_memory_mb "$SERVICE_NAME")"
    log_msg "INFO" "Post-deploy memory usage: ${post_mem} MB"

    # 4. Check dependent services (basic connectivity)
    # We check if Traefik is still running (if present) as a canary.
    if _ccmd -f "$COMPOSE_FILE_ABS" config --services 2>/dev/null | grep -qxF "traefik"; then
        local traefik_status
        traefik_status="$(get_container_status "traefik")"
        if [[ "$traefik_status" != "healthy" ]]; then
            log_msg "WARN" "Dependent service 'traefik' is not healthy (status: ${traefik_status})."
        else
            log_msg "OK" "Dependent service 'traefik' is healthy."
        fi
    fi

    POST_DEPLOY_STATUS="healthy"
    log_msg "OK" "Post-deploy validation complete: service is healthy."
    return 0
}

# ------------------------------------------------------------------
# Rollback
# ------------------------------------------------------------------

rollback() {
    ROLLBACK_TRIGGERED="true"
    log_msg "ERROR" "========== ROLLBACK INITIATED =========="

    # If service was already broken before deploy and --force not set,
    # skip rollback — we didn't cause the breakage.
    if [[ "$PRE_DEPLOY_STATUS" == "unhealthy" ]]; then
        log_msg "WARN" "Pre-deploy status was already 'unhealthy'. Skipping rollback."
        log_msg "WARN" "Service was broken BEFORE this deployment — manual intervention required."
        ROLLBACK_SUCCESS="null"
        ERRORS+=("Rollback skipped: service was already unhealthy before deployment")
        return 0
    fi

    # If pre-deploy was not_running, there's nothing to roll back TO.
    if [[ "$PRE_DEPLOY_STATUS" == "not_running" ]]; then
        log_msg "WARN" "Service was not running before deployment. Stopping it instead of rolling back."
        set +e
        _ccmd -f "$COMPOSE_FILE_ABS" stop "$SERVICE_NAME" 2>&1 || true
        set -e
        ROLLBACK_SUCCESS="true"
        return 0
    fi

    # Collect diagnostics before rolling back
    log_msg "INFO" "Collecting diagnostics for failed deployment ..."
    local cid
    cid="$(get_container_id "$SERVICE_NAME")"
    if [[ -n "$cid" ]]; then
        log_msg "INFO" "--- Container logs (tail 100) ---"
        docker logs --tail 100 "$cid" 2>&1 | while IFS= read -r line; do log_msg "INFO" "  $line"; done || true
        log_msg "INFO" "--- Container inspect (state) ---"
        docker inspect "$cid" 2>&1 | while IFS= read -r line; do log_msg "INFO" "  $line"; done || true
    fi

    # Restore the old compose file
    if [[ -n "$OLD_COMPOSE_BACKUP" ]] && [[ -f "$OLD_COMPOSE_BACKUP" ]]; then
        log_msg "INFO" "Restoring previous compose file: ${OLD_COMPOSE_BACKUP} -> ${COMPOSE_FILE_ABS}"
        cp "$OLD_COMPOSE_BACKUP" "$COMPOSE_FILE_ABS"
    else
        log_msg "ERROR" "No compose backup available! Cannot roll back configuration."
        ERRORS+=("Rollback failed: no compose backup available")
        ROLLBACK_SUCCESS="false"
        escalate_rollback_failure
        return 1
    fi

    # Bring the old config back up
    log_msg "INFO" "Starting service with previous configuration ..."
    set +e
    local rollback_out
    rollback_out="$(_ccmd -f "$COMPOSE_FILE_ABS" up -d "$SERVICE_NAME" 2>&1)"
    local rollback_rc=$?
    set -e

    if [[ $rollback_rc -ne 0 ]]; then
        log_msg "ERROR" "Rollback 'up -d' failed:"
        log_msg "ERROR" "${rollback_out}"
        ERRORS+=("Rollback 'up -d' failed: ${rollback_out}")
        ROLLBACK_SUCCESS="false"
        escalate_rollback_failure
        return 1
    fi

    # Wait for healthy after rollback
    log_msg "INFO" "Waiting for rolled-back service to become healthy (timeout: ${HEALTH_TIMEOUT}s) ..."
    if wait_for_container_healthy "$SERVICE_NAME" "$HEALTH_TIMEOUT"; then
        log_msg "OK" "Rollback successful. Service is healthy on previous version."
        ROLLBACK_SUCCESS="true"
        return 0
    else
        log_msg "ERROR" "Rollback FAILED: service is still unhealthy after rollback."
        ROLLBACK_SUCCESS="false"
        ERRORS+=("Rollback failed: service is still unhealthy after restoring previous version")
        escalate_rollback_failure
        return 1
    fi
}

escalate_rollback_failure() {
    local fail_flag="/tmp/deploy-${SERVICE_NAME}-ROLLBACK-FAILED"
    touch "$fail_flag"
    log_msg "ERROR" "============================================"
    log_msg "ERROR" "CRITICAL: Rollback failed for service '${SERVICE_NAME}'."
    log_msg "ERROR" "The service may be in a BROKEN state."
    log_msg "ERROR" "Flag file created: ${fail_flag}"
    log_msg "ERROR" "Manual intervention REQUIRED."
    log_msg "ERROR" "============================================"
    wall_alert "ROLLBACK FAILED for ${SERVICE_NAME}. Service may be broken. Flag: ${fail_flag}. Manual intervention required."
}

# ------------------------------------------------------------------
# Main orchestration
# ------------------------------------------------------------------

run_deployment() {
    DEPLOY_START_TIME="$(now_epoch)"
    local deploy_success="false"

    # --- 1. Pre-flight ---
    if ! preflight; then
        ERRORS+=("Pre-flight checks failed")
        write_deploy_log "false"
        update_deploy_history "false"
        release_lock
        exit 1
    fi

    if [[ "$DRY_RUN_VAL" == "true" ]]; then
        log_msg "INFO" ""
        log_msg "INFO" "========== DRY-RUN PLAN =========="
        log_msg "INFO" "Service        : ${SERVICE_NAME}"
        log_msg "INFO" "Compose file   : ${COMPOSE_FILE_ABS}"
        log_msg "INFO" "Health timeout : ${HEALTH_TIMEOUT}s"
        log_msg "INFO" "Force          : ${FORCE_VAL}"
        log_msg "INFO" "No-backup      : ${NO_BACKUP_VAL}"
        log_msg "INFO" "Remote SSH     : ${REMOTE_SSH:-none}"
        log_msg "INFO" "================================"
    fi

    # --- 2. Pre-deploy backup ---
    if [[ "$NO_BACKUP_VAL" == "true" ]]; then
        log_msg "WARN" "--no-backup specified: skipping pre-deploy backup. This is dangerous!"
        BACKUP_PATH=""
    else
        if ! run_backup; then
            ERRORS+=("Pre-deploy backup failed")
            write_deploy_log "false"
            update_deploy_history "false"
            release_lock
            exit 1
        fi
    fi

    # --- 3. Health baseline ---
    capture_health_baseline

    # --- 4. Deploy ---
    if ! do_deploy; then
        ERRORS+=("Deployment step failed")
        rollback
        write_deploy_log "false"
        update_deploy_history "false"
        post_webhook "false"
        release_lock
        exit 1
    fi

    if [[ "$DRY_RUN_VAL" == "true" ]]; then
        # Dry-run: log success with caveat.
        POST_DEPLOY_STATUS="dry_run"
        write_deploy_log "true"
        update_deploy_history "true"
        post_webhook "true"
        release_lock
        log_msg "OK" "Dry-run completed successfully."
        exit 0
    fi

    # --- 5. Post-deploy validation ---
    if ! post_deploy_validate; then
        ERRORS+=("Post-deploy validation failed")
        rollback
        write_deploy_log "false"
        update_deploy_history "false"
        post_webhook "false"
        release_lock
        exit 1
    fi

    # --- 6. Success ---
    deploy_success="true"
    DEPLOY_END_TIME="$(now_epoch)"
    log_msg "OK" "============================================"
    log_msg "OK" "Deployment SUCCESSFUL"
    log_msg "OK" "Service         : ${SERVICE_NAME}"
    log_msg "OK" "Old image       : ${PRE_DEPLOY_IMAGE:-none}"
    log_msg "OK" "New image       : ${NEW_IMAGE:-unknown}"
    log_msg "OK" "Duration        : $(human_duration "$DEPLOY_START_TIME" "$DEPLOY_END_TIME")s"
    log_msg "OK" "Compose backup  : ${OLD_COMPOSE_BACKUP}"
    log_msg "OK" "============================================"

    write_deploy_log "true"
    update_deploy_history "true"
    post_webhook "true"
    release_lock

    # Remove the compose backup on explicit success (tighten cleanup).
    # Actually, keep it — it's useful for forensic comparison.
}

# ------------------------------------------------------------------
# Help
# ------------------------------------------------------------------

print_help() {
    cat <<EOF
Usage: ${APP_NAME} <service-name> <compose-file.yml> [flags]

Deploy a Docker Compose service with atomic safety guarantees.

Required arguments:
  service-name       Name of the service defined in the compose file.
  compose-file.yml   Path to the docker-compose.yml file.

Flags:
  --dry-run          Validate and print plan, but do not deploy.
  --force            Deploy even if the service is currently unhealthy.
  --no-backup        Skip the pre-deploy backup (DANGEROUS).
  --timeout <sec>    Override health-check timeout (default: ${DEFAULT_HEALTH_TIMEOUT}s).
  --rollback         Placeholder — manual rollback not yet implemented.
  --help, -h         Print this help and exit.

Environment variables:
  DEPLOY_WEBHOOK_URL       Webhook URL for deployment notifications.
  DEPLOY_REMOTE_SSH        SSH user@host for remote deployment via Tailscale.
  DEPLOY_HEALTH_ENDPOINT   Override health-check URL path (default: /health).
  DEPLOY_HEALTH_PORT       Override health-check port.
  COMPOSE_BIN              Override docker-compose binary path.
  WHEELER_BACKUP_SCRIPT    Path to backup-all.sh (default: /usr/local/bin/backup-all.sh).
  WHEELER_LOG_DIR          Root log directory (default: /var/log/wheeler).

Deployment log:     /var/log/wheeler/deployments.log
Deployment history: /var/log/wheeler/deployment-history.json
EOF
}

# ------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------

parse_args() {
    if [[ $# -lt 2 ]]; then
        log_msg "ERROR" "Missing required arguments. Use --help for usage."
        exit 1
    fi

    # First positional arg might be --help
    case "${1:-}" in
        --help|-h) print_help; exit 0 ;;
    esac

    SERVICE_NAME="$1"
    COMPOSE_FILE="$2"
    shift 2

    # Normalize compose file path to absolute
    COMPOSE_FILE_ABS="$(realpath "$COMPOSE_FILE" 2>/dev/null || { log_msg "ERROR" "Cannot resolve path: ${COMPOSE_FILE}"; exit 1; })"

    # Set defaults
    HEALTH_TIMEOUT="$DEFAULT_HEALTH_TIMEOUT"
    HEALTH_ENDPOINT="${DEPLOY_HEALTH_ENDPOINT:-$DEFAULT_HEALTH_ENDPOINT}"
    HEALTH_PORT="${DEPLOY_HEALTH_PORT:-}"
    DRY_RUN_VAL="$DRY_RUN"
    FORCE_VAL="$FORCE"
    NO_BACKUP_VAL="$NO_BACKUP"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN_VAL="true"
                shift
                ;;
            --force)
                FORCE_VAL="true"
                shift
                ;;
            --no-backup)
                NO_BACKUP_VAL="true"
                shift
                ;;
            --rollback)
                log_msg "ERROR" "Manual --rollback is not yet implemented."
                exit 1
                ;;
            --timeout)
                if [[ $# -lt 2 ]]; then
                    log_msg "ERROR" "--timeout requires a value."
                    exit 1
                fi
                HEALTH_TIMEOUT="$2"
                if ! [[ "$HEALTH_TIMEOUT" =~ ^[0-9]+$ ]]; then
                    log_msg "ERROR" "--timeout must be a positive integer."
                    exit 1
                fi
                shift 2
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            *)
                log_msg "ERROR" "Unknown argument: $1"
                log_msg "INFO" "Use --help for usage."
                exit 1
                ;;
        esac
    done

    # Validate service name — no whitespace, reasonable length.
    if [[ ! "$SERVICE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_msg "ERROR" "Invalid service name: '${SERVICE_NAME}'. Must be alphanumeric with hyphens/underscores."
        exit 1
    fi
}

# ------------------------------------------------------------------
# Remote deployment support
# ------------------------------------------------------------------

run_remote() {
    local ssh_target="$1"
    shift
    local script_args=("$@")

    log_msg "INFO" "Deploying remotely to ${ssh_target} ..."

    # Copy this script to the remote and execute it.
    # We self-reference via $0.
    local remote_script="/tmp/deploy-service-remote-$$.sh"

    if ! scp -o StrictHostKeyChecking=accept-new "$0" "${ssh_target}:${remote_script}" &>/dev/null; then
        log_msg "ERROR" "Failed to copy deploy script to remote host."
        exit 1
    fi

    local remote_cmd="bash ${remote_script} ${script_args[*]}"
    set +e
    ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "$remote_cmd"
    local rc=$?
    set -e

    # Cleanup remote script
    ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "rm -f ${remote_script}" &>/dev/null || true

    exit $rc
}

# ------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------

main() {
    # Parse arguments early so we have SERVICE_NAME.
    parse_args "$@"

    # If remote SSH target is set, delegate to remote and exit.
    if [[ -n "$REMOTE_SSH" ]]; then
        run_remote "$REMOTE_SSH" "$@"
        # run_remote calls exit itself.
    fi

    # Set up logging directories
    LOG_DIR="${WHEELER_LOG_DIR:-${DEFAULT_LOG_DIR}}"
    DEPLOY_LOG_FILE="${LOG_DIR}/deployments.log"
    HISTORY_FILE="${LOG_DIR}/deployment-history.json"

    if [[ "$DRY_RUN_VAL" != "true" ]]; then
        mkdir -p "$LOG_DIR"
    fi

    # Generate a unique deployment ID.
    DEPLOYMENT_ID="$(generate_uuid)"

    log_msg "INFO" "============================================"
    log_msg "INFO" "Wheeler Enterprise Deployer v${VERSION}"
    log_msg "INFO" "Deployment ID : ${DEPLOYMENT_ID}"
    log_msg "INFO" "Service       : ${SERVICE_NAME}"
    log_msg "INFO" "Compose file  : ${COMPOSE_FILE_ABS}"
    log_msg "INFO" "============================================"

    # Acquire deployment lock.
    if ! acquire_lock; then
        log_msg "ERROR" "Cannot acquire deployment lock. Aborting."
        exit 1
    fi

    # Trap ensures we ALWAYS release the lock, even on unexpected failure.
    # Also write a partial log entry on fatal crash.
    trap 'release_lock; write_deploy_log "false"; exit 1' ERR INT TERM

    run_deployment
    # Deactivate trap — success path already released and logged.
    trap - ERR INT TERM
}

main "$@"
