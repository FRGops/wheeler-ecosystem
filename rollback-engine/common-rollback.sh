#!/usr/bin/env bash
# ==============================================================================
# common-rollback.sh — Shared rollback utility functions
# Usage: source ./common-rollback.sh
# ==============================================================================
set -euo pipefail

# ── Global Constants ─────────────────────────────────────────────────────────
readonly BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/deployments}"
readonly LOG_DIR="${LOG_DIR:-/var/log/rollbacks}"
readonly ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
readonly ALERT_EMAIL="${ALERT_EMAIL:-}"
readonly TEAM_CHANNEL="${TEAM_CHANNEL:-#deployments}"
readonly HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"
readonly HEALTH_RETRY_INTERVAL="${HEALTH_RETRY_INTERVAL:-5}"

# ── Color Codes ──────────────────────────────────────────────────────────────
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# ── Logging Functions ────────────────────────────────────────────────────────

log_info() {
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET}  ${ts}  $*" >&2
}

log_warn() {
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET}  ${ts}  $*" >&2
}

log_error() {
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} ${ts}  $*" >&2
}

log_success() {
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}    ${ts}  $*" >&2
}

# ── Audit Trail ──────────────────────────────────────────────────────────────

init_audit_log() {
    local service_name="$1"
    local environment="$2"
    local log_file="${LOG_DIR}/${service_name}-${environment}-$(date -u +"%Y%m%dT%H%M%SZ").log"

    mkdir -p "${LOG_DIR}"
    exec 3>"${log_file}"  # fd 3 is the audit log
    echo "ROLLBACK_AUDIT_LOG=${log_file}" >&3

    log_info "Audit log initialized: ${log_file}"
    (
        echo "================================================================"
        echo "Rollback Audit Log"
        echo "Service:     ${service_name}"
        echo "Environment: ${environment}"
        echo "Started:     $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "User:        $(whoami)"
        echo "Host:        $(hostname -f)"
        echo "================================================================"
        echo ""
    ) >&3
}

audit_log() {
    local level="$1"; shift
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "[${level}] ${ts}  $*" >&3 2>/dev/null || true
}

close_audit_log() {
    local exit_code="$1"
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    (
        echo ""
        echo "================================================================"
        echo "Rollback Finished: ${ts}"
        echo "Exit Code:         ${exit_code}"
    ) >&3 2>/dev/null || true

    exec 3>&- 2>/dev/null || true
}

# ── Backup Discovery ─────────────────────────────────────────────────────────

# find_latest_backup <service-name> <environment>
# Echoes the path to the latest backup directory. Returns 0 on success, 1 if
# no backup is found.
find_latest_backup() {
    local service_name="$1"
    local environment="$2"
    local backup_dir="${BACKUP_ROOT}/${service_name}/${environment}"

    if [[ ! -d "${backup_dir}" ]]; then
        log_error "No backup directory found at ${backup_dir}"
        return 1
    fi

    # Backups are timestamped directories: YYYY-MM-DDTHHMMSSZ
    local latest
    latest="$(find "${backup_dir}" -maxdepth 1 -type d \
        -name '20[0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z' \
        -printf '%f\n' 2>/dev/null \
        | sort -r \
        | head -1)"

    if [[ -z "${latest}" ]]; then
        log_error "No valid backup found for ${service_name}/${environment}"
        return 1
    fi

    echo "${backup_dir}/${latest}"
    return 0
}

# find_backup_by_version <service-name> <environment> <version-tag>
# Echoes the path to a backup with a specific version tag.
find_backup_by_version() {
    local service_name="$1"
    local environment="$2"
    local version_tag="$3"
    local backup_dir="${BACKUP_ROOT}/${service_name}/${environment}"

    if [[ ! -d "${backup_dir}" ]]; then
        log_error "No backup directory found at ${backup_dir}"
        return 1
    fi

    # Look for a VERSION file inside timestamped directories
    while IFS= read -r -d '' candidate; do
        local version_file="${candidate}/VERSION"
        if [[ -f "${version_file}" ]]; then
            local stored_version
            stored_version="$(head -1 "${version_file}")"
            if [[ "${stored_version}" == "${version_tag}" ]]; then
                echo "${candidate}"
                return 0
            fi
        fi
    done < <(find "${backup_dir}" -maxdepth 1 -type d \
        -name '20[0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z' \
        -print0 2>/dev/null | sort -rz)

    log_error "No backup found with version tag: ${version_tag}"
    return 1
}

# ── Backup Integrity ─────────────────────────────────────────────────────────

# verify_backup_integrity <backup-path> <service-type>
# Checks that a backup contains all expected files based on service type.
verify_backup_integrity() {
    local backup_path="$1"
    local service_type="$2"

    log_info "Verifying backup integrity: ${backup_path}"

    if [[ ! -d "${backup_path}" ]]; then
        log_error "Backup path does not exist: ${backup_path}"
        return 1
    fi

    # Every backup must have a MANIFEST file
    local manifest="${backup_path}/MANIFEST"
    if [[ ! -f "${manifest}" ]]; then
        log_error "MANIFEST file missing from backup: ${backup_path}"
        return 1
    fi

    # Verify all files listed in the manifest exist
    local missing=0
    while IFS= read -r line; do
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        local rel_path="${line%% *}"  # first word is the relative path
        if [[ ! -e "${backup_path}/${rel_path}" ]]; then
            log_error "Manifest entry missing: ${rel_path}"
            missing=1
        fi
    done < "${manifest}"

    if [[ ${missing} -ne 0 ]]; then
        log_error "Backup integrity check FAILED for ${backup_path}"
        return 1
    fi

    # Checksum validation if a checksum file exists
    local checksum_file="${backup_path}/SHA256SUMS"
    if [[ -f "${checksum_file}" ]]; then
        log_info "Validating SHA256 checksums..."
        if ! (cd "${backup_path}" && sha256sum -c --quiet SHA256SUMS 2>&1); then
            log_error "Checksum validation FAILED for ${backup_path}"
            return 1
        fi
        log_success "Checksums validated."
    fi

    log_success "Backup integrity verified: ${backup_path}"
    return 0
}

# ── Service Type Detection ───────────────────────────────────────────────────

# get_service_type <service-name> <environment>
# Echoes one of: docker, pm2, static
get_service_type() {
    local service_name="$1"
    local environment="$2"

    # Priority 1: explicit marker file placed during deployment
    local marker="/opt/services/${service_name}/.service-type"
    if [[ -f "${marker}" ]]; then
        cat "${marker}"
        return 0
    fi

    # Priority 2: check for docker-compose files
    if [[ -f "/opt/services/${service_name}/docker-compose.yml" ]] || \
       [[ -f "/opt/services/${service_name}/docker-compose.yaml" ]]; then
        echo "docker"
        return 0
    fi

    # Priority 3: check PM2
    if [[ -f "/opt/services/${service_name}/ecosystem.config.js" ]] || \
       [[ -f "/opt/services/${service_name}/ecosystem.config.cjs" ]]; then
        echo "pm2"
        return 0
    fi

    # Priority 4: check for process.json / pm2 process list
    if pm2 jlist 2>/dev/null | jq -e --arg name "${service_name}" \
        '.[] | select(.name == $name)' >/dev/null 2>&1; then
        echo "pm2"
        return 0
    fi

    # Priority 5: check for Traefik/Nginx static service marker
    if [[ -f "/opt/services/${service_name}/.static-marker" ]]; then
        echo "static"
        return 0
    fi

    # Priority 6: check Traefik config directory for route definitions
    if grep -qr "service.*${service_name}" /etc/traefik/dynamic/ 2>/dev/null; then
        echo "static"
        return 0
    fi

    # Fallback: assume static
    log_warn "Could not determine service type for ${service_name}, defaulting to static"
    echo "static"
    return 0
}

# ── Rollback Event Logging ───────────────────────────────────────────────────

# log_rollback_event <service-name> <environment> <from-version> <to-version> ...
#   <event-type> <success|failure> <duration-seconds> [message]
# Writes a structured JSON event to a shared rollback history log and to audit.
log_rollback_event() {
    local service_name="$1"
    local environment="$2"
    local from_version="$3"
    local to_version="$4"
    local event_type="$5"
    local outcome="$6"
    local duration_sec="$7"
    local message="${8:-}"

    local event_log="${BACKUP_ROOT}/rollback-history.jsonl"
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Build JSON event
    local event
    event="$(jq -n \
        --arg ts "${ts}" \
        --arg service "${service_name}" \
        --arg env "${environment}" \
        --arg from_ver "${from_version}" \
        --arg to_ver "${to_version}" \
        --arg type "${event_type}" \
        --arg outcome "${outcome}" \
        --arg duration "${duration_sec}" \
        --arg msg "${message}" \
        --arg host "$(hostname -f)" \
        --arg user "$(whoami)" \
        '{
            timestamp: $ts,
            service: $service,
            environment: $env,
            from_version: $from_ver,
            to_version: $to_ver,
            event_type: $type,
            outcome: $outcome,
            duration_seconds: ($duration | tonumber),
            message: $msg,
            host: $host,
            triggered_by: $user
        }')"

    mkdir -p "$(dirname "${event_log}")"
    echo "${event}" >> "${event_log}"
    audit_log "EVENT" "${event}"
}

# ── Alerting ─────────────────────────────────────────────────────────────────

# send_rollback_alert <service-name> <environment> <status> <details>
# Sends a notification about a rollback event. Uses webhook if configured,
# otherwise sends email if configured. Always logs the event.
send_rollback_alert() {
    local service_name="$1"
    local environment="$2"
    local status="$3"
    local details="$4"
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local emoji
    case "${status}" in
        SUCCESS)  emoji="large_green_circle"  ;;
        FAILED)   emoji="red_circle"           ;;
        WARNING)  emoji="large_yellow_circle"  ;;
        *)        emoji="information_source"   ;;
    esac

    local message
    message="$(cat <<SLACK_MSG
:${emoji}: *Rollback ${status}*
*Service:* \`${service_name}\`
*Environment:* \`${environment}\`
*Time:* ${ts}
*Host:* $(hostname -f)
*Details:* ${details}
SLACK_MSG
)"

    audit_log "ALERT" "${status} | ${service_name} | ${environment} | ${details}"

    # Webhook delivery
    if [[ -n "${ALERT_WEBHOOK}" ]]; then
        if curl -s -X POST "${ALERT_WEBHOOK}" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg text "${message}" '{text: $text}')" \
            >/dev/null 2>&1; then
            log_info "Alert sent via webhook."
        else
            log_warn "Failed to send alert via webhook."
        fi
    fi

    # Email delivery
    if [[ -n "${ALERT_EMAIL}" ]]; then
        if echo "${message}" | mail -s "[ROLLBACK ${status}] ${service_name} (${environment})" \
            "${ALERT_EMAIL}" 2>/dev/null; then
            log_info "Alert sent via email to ${ALERT_EMAIL}"
        else
            log_warn "Failed to send alert via email."
        fi
    fi

    # Always log to stdout for journald capture
    echo "${message}"
}

# ── Health Verification Helpers ──────────────────────────────────────────────

# wait_for_http_health <url> <timeout> <retry-interval>
# Polls an HTTP health endpoint until it returns 2xx or timeout expires.
wait_for_http_health() {
    local url="$1"
    local timeout="${2:-60}"
    local interval="${3:-5}"
    local elapsed=0

    log_info "Waiting for health check: ${url} (timeout=${timeout}s)"

    while [[ ${elapsed} -lt ${timeout} ]]; do
        local http_code
        http_code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 "${url}" 2>/dev/null || echo "000")"

        if [[ "${http_code}" =~ ^2[0-9][0-9]$ ]]; then
            log_success "Health check passed (${http_code}) after ${elapsed}s"
            return 0
        fi

        log_info "Health check returned ${http_code}, retrying in ${interval}s... (${elapsed}s elapsed)"
        sleep "${interval}"
        elapsed=$((elapsed + interval))
    done

    log_error "Health check timed out after ${elapsed}s for ${url}"
    return 1
}

# wait_for_tcp_port <host> <port> <timeout> <retry-interval>
wait_for_tcp_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    local interval="${4:-3}"
    local elapsed=0

    log_info "Waiting for TCP ${host}:${port} (timeout=${timeout}s)"

    while [[ ${elapsed} -lt ${timeout} ]]; do
        if timeout 3 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
            log_success "TCP ${host}:${port} is accepting connections (${elapsed}s)"
            return 0
        fi
        sleep "${interval}"
        elapsed=$((elapsed + interval))
    done

    log_error "TCP ${host}:${port} timed out after ${elapsed}s"
    return 1
}

# ── Preserve Failed State ────────────────────────────────────────────────────

# preserve_failed_artifact <source-path> <label>
# Copies a failed artifact (config, env, etc.) to a timestamped backup for
# post-mortem analysis.
preserve_failed_artifact() {
    local source_path="$1"
    local label="$2"
    local ts
    ts="$(date -u +"%Y%m%dT%H%M%SZ")"
    local dest="${source_path}.failed-${label}-${ts}"

    if [[ -f "${source_path}" ]]; then
        cp -a "${source_path}" "${dest}"
        log_info "Preserved failed artifact: ${dest}"
        echo "${dest}"
    elif [[ -d "${source_path}" ]]; then
        cp -a "${source_path}" "${dest}"
        log_info "Preserved failed artifact (dir): ${dest}"
        echo "${dest}"
    else
        log_warn "No artifact to preserve at ${source_path}"
        echo ""
    fi
}

# ── Version Extraction ───────────────────────────────────────────────────────

# get_current_version <service-name> <environment>
# Attempts to determine the currently deployed version.
get_current_version() {
    local service_name="$1"
    local environment="$2"

    # Check VERSION file
    if [[ -f "/opt/services/${service_name}/VERSION" ]]; then
        head -1 "/opt/services/${service_name}/VERSION"
        return 0
    fi

    # Check for a running container tag
    if command -v docker &>/dev/null; then
        local tag
        tag="$(docker ps --format '{{.Image}}' --filter "name=${service_name}" 2>/dev/null | head -1 || true)"
        if [[ -n "${tag}" ]]; then
            echo "${tag}"
            return 0
        fi
    fi

    # Fallback
    echo "unknown"
    return 0
}

# get_backup_version <backup-path>
get_backup_version() {
    local backup_path="$1"
    if [[ -f "${backup_path}/VERSION" ]]; then
        head -1 "${backup_path}/VERSION"
    else
        echo "unknown"
    fi
}

# ── Timestamp Helpers ────────────────────────────────────────────────────────
now_iso()  { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
now_compact() { date -u +"%Y%m%dT%H%M%SZ"; }

# ── Locks ────────────────────────────────────────────────────────────────────

# acquire_rollback_lock <service-name> <environment>
# Prevents concurrent rollbacks on the same service.
acquire_rollback_lock() {
    local service_name="$1"
    local environment="$2"
    local lock_file="/tmp/rollback-${service_name}-${environment}.lock"

    # Use flock with a file descriptor
    exec 4>"${lock_file}"
    if ! flock -n 4; then
        log_error "Another rollback is already in progress for ${service_name}/${environment}"
        return 1
    fi
    log_info "Acquired rollback lock for ${service_name}/${environment}"
    return 0
}

release_rollback_lock() {
    flock -u 4 2>/dev/null || true
    exec 4>&- 2>/dev/null || true
    log_info "Released rollback lock."
}

# ── Finished sourcing marker ─────────────────────────────────────────────────
log_info "common-rollback.sh loaded."
