#!/usr/bin/env bash
# ==============================================================================
# restore-pm2.sh — Restore a PM2-managed service from a deployment backup
# Usage: ./restore-pm2.sh <service-name> <environment> <backup-path>
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-rollback.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <service-name> <environment> <backup-path>

Restores a PM2-managed service from a deployment backup. Stops the current
process gracefully, restores the previous ecosystem config and process dump,
and restarts with the previous configuration.

Arguments:
  service-name   Name of the PM2 process (e.g. api-gateway)
  environment    Target environment (e.g. production, staging)
  backup-path    Full path to the backup directory

Exit Codes:
  0  Restore completed and PM2 process verified online
  1  Restore failed (config missing, process failed to stop)
  2  Verification failed (process offline, restart loop detected)
EOF
}

# ── Check if PM2 is available ────────────────────────────────────────────────
check_pm2_available() {
    if ! command -v pm2 &>/dev/null; then
        log_error "PM2 is not installed or not in PATH"
        return 1
    fi
    # Verify PM2 daemon is running
    if ! pm2 ping &>/dev/null; then
        log_error "PM2 daemon is not running. Start it with 'pm2 resurrect' or 'pm2 start'"
        return 1
    fi
    log_info "PM2 daemon is reachable."
    return 0
}

# ── Gracefully stop the current PM2 process ──────────────────────────────────
stop_current_process() {
    local process_name="$1"

    # Check if process exists
    if ! pm2 jlist 2>/dev/null | jq -e --arg name "${process_name}" \
        '.[] | select(.name == $name)' >/dev/null 2>&1; then
        log_warn "Process '${process_name}' is not currently running in PM2."
        audit_log "INFO" "Process ${process_name} not found in PM2, skipping stop."
        return 0
    fi

    log_info "Stopping PM2 process: ${process_name}"

    # Graceful stop with timeout
    pm2 stop "${process_name}" 2>&1 | head -5
    audit_log "INFO" "Issued stop command for ${process_name}"

    # Wait for graceful shutdown
    local wait_time=0
    local max_wait=30
    while pm2 jlist 2>/dev/null | jq -e --arg name "${process_name}" \
        '.[] | select(.name == $name and .pm2_env.status == "stopped")' >/dev/null 2>&1; do
        log_info "Process stopped after ${wait_time}s"
        audit_log "INFO" "Process ${process_name} stopped after ${wait_time}s"
        return 0
    done

    # Check if it is still running; if so, force kill
    while [[ ${wait_time} -lt ${max_wait} ]]; do
        if pm2 jlist 2>/dev/null | jq -e --arg name "${process_name}" \
            '.[] | select(.name == $name and .pm2_env.status == "stopped")' >/dev/null 2>&1; then
            log_info "Process stopped after ${wait_time}s"
            audit_log "INFO" "Process ${process_name} stopped after ${wait_time}s"
            return 0
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done

    log_warn "Graceful stop timed out, sending SIGKILL..."
    pm2 kill "${process_name}" 2>/dev/null || true
    sleep 2

    # Final check
    if ! pm2 jlist 2>/dev/null | jq -e --arg name "${process_name}" \
        '.[] | select(.name == $name and .pm2_env.status != "stopped")' >/dev/null 2>&1; then
        pm2 delete "${process_name}" 2>/dev/null || true
        log_info "Force-deleted process: ${process_name}"
        audit_log "WARN" "Force-deleted process ${process_name} after graceful stop timeout"
    else
        log_info "Process ${process_name} stopped."
    fi

    return 0
}

# ── Check for PM2 restart loops ──────────────────────────────────────────────
detect_restart_loop() {
    local process_name="$1"
    local check_duration="${2:-30}"
    local interval="${3:-5}"
    local elapsed=0

    log_info "Monitoring ${process_name} for restart loops (${check_duration}s)..."

    local initial_restarts
    initial_restarts="$(pm2 jlist 2>/dev/null | jq -r --arg name "${process_name}" \
        '.[] | select(.name == $name) | .pm2_env.restart_time // 0' || echo "0")"

    while [[ ${elapsed} -lt ${check_duration} ]]; do
        sleep "${interval}"
        elapsed=$((elapsed + interval))

        local current_restarts
        current_restarts="$(pm2 jlist 2>/dev/null | jq -r --arg name "${process_name}" \
            '.[] | select(.name == $name) | .pm2_env.restart_time // 0' || echo "0")"

        local new_restarts=$((current_restarts - initial_restarts))

        if [[ ${new_restarts} -ge 3 ]]; then
            log_error "RESTART LOOP DETECTED: ${process_name} restarted ${new_restarts} times in ${elapsed}s"
            audit_log "ERROR" "Restart loop detected: ${process_name} - ${new_restarts} restarts in ${elapsed}s"
            return 1
        fi

        # Also check uptime / status - if status keeps flipping to "errored" or "launching"
        local status
        status="$(pm2 jlist 2>/dev/null | jq -r --arg name "${process_name}" \
            '.[] | select(.name == $name) | .pm2_env.status // "unknown"')"

        case "${status}" in
            online|stopped)  ;;  # OK
            errored)
                log_error "Process ${process_name} is in ERRRORED state"
                audit_log "ERROR" "Process ${process_name} status=${status} during loop check"
                return 1
                ;;
            launching)
                log_warn "Process ${process_name} is still launching..."
                ;;
            *)
                log_warn "Process ${process_name} status: ${status}"
                ;;
        esac
    done

    log_success "No restart loop detected after ${check_duration}s."
    return 0
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    if [[ $# -lt 3 ]]; then
        usage >&2
        exit 1
    fi

    local service_name="$1"
    local environment="$2"
    local backup_path="$3"

    init_audit_log "${service_name}" "${environment}"
    audit_log "INFO" "restore-pm2.sh starting for ${service_name}/${environment}"

    # ── 0. Pre-flight checks ─────────────────────────────────────────────
    check_pm2_available || {
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "PM2 restore - PM2 daemon not available"
        close_audit_log 1
        exit 1
    }

    # ── 1. Validate backup contents ──────────────────────────────────────
    verify_backup_integrity "${backup_path}" "pm2" || {
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "PM2 restore - backup integrity check failed"
        close_audit_log 1
        exit 1
    }

    # Check for ecosystem config in backup
    local backup_ecosystem=""
    if [[ -f "${backup_path}/pm2/ecosystem.config.js" ]]; then
        backup_ecosystem="${backup_path}/pm2/ecosystem.config.js"
    elif [[ -f "${backup_path}/pm2/ecosystem.config.cjs" ]]; then
        backup_ecosystem="${backup_path}/pm2/ecosystem.config.cjs"
    elif [[ -f "${backup_path}/ecosystem.config.js" ]]; then
        backup_ecosystem="${backup_path}/ecosystem.config.js"
    elif [[ -f "${backup_path}/ecosystem.config.cjs" ]]; then
        backup_ecosystem="${backup_path}/ecosystem.config.cjs"
    fi

    # Check for PM2 dump
    local backup_dump=""
    if [[ -f "${backup_path}/pm2/dump.pm2" ]]; then
        backup_dump="${backup_path}/pm2/dump.pm2"
    elif [[ -f "${backup_path}/dump.pm2" ]]; then
        backup_dump="${backup_path}/dump.pm2"
    fi

    if [[ -z "${backup_ecosystem}" ]] && [[ -z "${backup_dump}" ]]; then
        log_error "No PM2 ecosystem config or dump file found in backup"
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "PM2 restore - no config/dump in backup"
        close_audit_log 1
        exit 1
    fi

    log_info "Backup ecosystem: ${backup_ecosystem:-not found}"
    log_info "Backup dump:      ${backup_dump:-not found}"

    # ── 2. Get version info for event log ────────────────────────────────
    local from_version
    from_version="$(get_current_version "${service_name}" "${environment}")"
    local to_version
    to_version="$(get_backup_version "${backup_path}")"

    # ── 3. Stop current process ──────────────────────────────────────────
    stop_current_process "${service_name}" || {
        log_error "Failed to stop current process"
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "PM2 restore - failed to stop process"
        close_audit_log 1
        exit 1
    }

    # ── 4. Preserve current config before restoring ──────────────────────
    local current_ecosystem="/opt/services/${service_name}/ecosystem.config.js"
    if [[ -f "${current_ecosystem}" ]]; then
        preserve_failed_artifact "${current_ecosystem}" "ecosystem"
        audit_log "INFO" "Preserved current ecosystem config"
    fi

    # Also save the current dump just in case
    local current_dump="$HOME/.pm2/dump.pm2"
    if [[ -f "${current_dump}" ]]; then
        preserve_failed_artifact "${current_dump}" "dump"
    fi

    # ── 5. Restore ecosystem config ──────────────────────────────────────
    if [[ -n "${backup_ecosystem}" ]]; then
        log_info "Restoring ecosystem config from backup..."
        mkdir -p "/opt/services/${service_name}"
        cp "${backup_ecosystem}" "/opt/services/${service_name}/ecosystem.config.js"
        audit_log "INFO" "Restored ecosystem config from ${backup_ecosystem}"
    fi

    # ── 6. Restore PM2 dump ──────────────────────────────────────────────
    if [[ -n "${backup_dump}" ]]; then
        log_info "Restoring PM2 dump from backup..."
        mkdir -p "$HOME/.pm2"
        cp "${backup_dump}" "$HOME/.pm2/dump.pm2"
        audit_log "INFO" "Restored PM2 dump from ${backup_dump}"
    fi

    # ── 7. Start the restored process ────────────────────────────────────
    log_info "Starting restored PM2 process: ${service_name}"

    local start_cmd
    if [[ -n "${backup_ecosystem}" ]]; then
        start_cmd="pm2 start /opt/services/${service_name}/ecosystem.config.js --env ${environment}"
    else
        # Resurrect from dump
        start_cmd="pm2 resurrect"
    fi

    if ! ${start_cmd} 2>&1; then
        log_error "Failed to start PM2 process: ${service_name}"
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "PM2 restore - failed to start process"
        close_audit_log 1
        exit 1
    fi
    audit_log "INFO" "Started process: ${start_cmd}"

    # ── 8. Verify PM2 process is online ──────────────────────────────────
    local verify_wait=15
    log_info "Waiting ${verify_wait}s for process to stabilize..."

    local elapsed=0
    local online=0
    while [[ ${elapsed} -lt ${verify_wait} ]]; do
        local status
        status="$(pm2 jlist 2>/dev/null | jq -r --arg name "${service_name}" \
            '.[] | select(.name == $name) | .pm2_env.status // "unknown"')"

        if [[ "${status}" == "online" ]]; then
            online=1
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    if [[ ${online} -eq 0 ]]; then
        # Try to get current status for better error message
        local current_status
        current_status="$(pm2 jlist 2>/dev/null | jq -r --arg name "${service_name}" \
            '.[] | select(.name == $name) | "status=" + .pm2_env.status + " restarts=" + (.pm2_env.restart_time | tostring)' || echo "unknown")"

        log_error "Process ${service_name} is NOT online after restore. Current state: ${current_status}"
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "PM2 restore - process not online after restore: ${current_status}"
        close_audit_log 2
        exit 2
    fi

    log_success "Process ${service_name} is online."

    # Save the running process list for future resurrect
    pm2 save 2>/dev/null || true

    # ── 9. Check for restart loops ───────────────────────────────────────
    if ! detect_restart_loop "${service_name}" 30 5; then
        log_error "Restart loop detected after restore!"
        send_rollback_alert "${service_name}" "${environment}" "WARNING" \
            "PM2 restore - restart loop detected, process may be unstable"
        close_audit_log 2
        exit 2
    fi

    # ── 10. Log success ──────────────────────────────────────────────────
    local duration
    duration=$((SECONDS))
    log_rollback_event "${service_name}" "${environment}" "${from_version}" "${to_version}" \
        "pm2_restore" "success" "${duration}" "PM2 restore completed successfully"

    send_rollback_alert "${service_name}" "${environment}" "SUCCESS" \
        "PM2 restore completed in ${duration}s"

    close_audit_log 0
    return 0
}

main "$@"
