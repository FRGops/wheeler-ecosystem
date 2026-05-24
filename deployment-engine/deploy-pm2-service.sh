#!/usr/bin/env bash
# =============================================================================
# Wheeler Deployment Engine — deploy-pm2-service.sh
# =============================================================================
# Handles PM2-based service deployments with graceful reload, health checks,
# auto-rollback, restart loop detection, and resource monitoring.
#
# Usage:
#   ./deploy-pm2-service.sh <service-name> <environment>
#   ./deploy-pm2-service.sh wheeler-api production
#   ./deploy-pm2-service.sh --force revenue-api staging
#
# Exit Codes:
#   0 - Deployment successful
#   1 - PM2 daemon not running
#   2 - Pre-deploy checks failed
#   3 - Deployment failed (rolled back)
#   4 - Health check failed (rolled back)
#   5 - Rollback failed
#   6 - Restart loop detected
# =============================================================================

set -euo pipefail

# ─── Source common utilities ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# ─── Script Configuration ────────────────────────────────────────────────────
readonly SCRIPT_NAME="deploy-pm2-service.sh"
readonly SCRIPT_VERSION="1.0.0"
readonly MAX_RESTARTS="${MAX_RESTARTS:-5}"         # Max restarts in window before loop detection
readonly RESTART_WINDOW_SEC="${RESTART_WINDOW_SEC:-60}"  # Window for restart loop detection
readonly GRACEFUL_TIMEOUT_MS="${GRACEFUL_TIMEOUT_MS:-25000}"

# ─── Parse flags ─────────────────────────────────────────────────────────────
FORCE_CONFIRM="${FORCE_CONFIRM:-}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f) FORCE_CONFIRM=1; shift ;;
        *) break ;;
    esac
done

# ─── Arguments ───────────────────────────────────────────────────────────────
SERVICE_NAME="${1:-}"
ENVIRONMENT="${2:-}"

# ─── Usage ───────────────────────────────────────────────────────────────────
_pm2_usage() {
    cat <<EOF

${_C_BOLD}Usage:${_C_RESET} ./${SCRIPT_NAME} [--force] <service-name> <environment>

${_C_BOLD}Arguments:${_C_RESET}
  service-name   PM2 service name (as shown in 'pm2 list')
  environment    Target environment (production, staging, dev)

${_C_BOLD}Examples:${_C_RESET}
  ./deploy-pm2-service.sh wheeler-api production
  ./deploy-pm2-service.sh --force revenue-api staging
EOF
    exit 1
}

# ─── Validate ────────────────────────────────────────────────────────────────
validate_pm2_args() {
    if [[ -z "$SERVICE_NAME" ]]; then
        _pm2_usage
    fi
    if [[ -z "$ENVIRONMENT" ]]; then
        _pm2_usage
    fi
    validate_environment "$ENVIRONMENT" || exit 1
    validate_service_name "$SERVICE_NAME" || exit 1
}

# ─── Check PM2 daemon ────────────────────────────────────────────────────────
ensure_pm2_daemon() {
    if ! check_pm2_daemon; then
        log_fatal "PM2 daemon is not running. Cannot deploy PM2 service."
        exit 1
    fi
}

# ─── Get service process info ────────────────────────────────────────────────
get_pm2_process_info() {
    local name="$1"
    pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${name}\")" 2>/dev/null || echo "{}"
}

# ─── PM2 process backup ─────────────────────────────────────────────────────
backup_pm2_state() {
    log_info "Backing up PM2 process state..."

    # Save PM2 process list
    pm2 save 2>/dev/null || {
        log_warn "PM2 save failed (daemon may not have existing processes)"
    }

    # Backup PM2 dump file
    local dump_file="${HOME}/.pm2/dump.pm2"
    local backup_file="${BACKUP_BASE}/$(timestamp_file)_pm2_dump_${SERVICE_NAME}.pm2"

    if [[ -f "$dump_file" ]]; then
        mkdir -p "$BACKUP_BASE"
        cp -a "$dump_file" "$backup_file"
        log_info "PM2 dump backed up to: ${backup_file}"
    else
        log_warn "No PM2 dump file found to backup"
    fi

    # Record current process info for rollback
    if pm2 list 2>/dev/null | grep -q "$SERVICE_NAME"; then
        log_info "Recording current process state for rollback..."
        local state_file="/tmp/wheeler_pm2_prerollback_${SERVICE_NAME}.json"
        get_pm2_process_info "$SERVICE_NAME" > "$state_file"
        log_info "Pre-deploy state saved to: ${state_file}"
    fi
}

# ─── Get resource usage ──────────────────────────────────────────────────────
get_resource_usage() {
    local name="$1"
    local info
    info=$(get_pm2_process_info "$name")

    if [[ "$info" == "{}" ]] || [[ -z "$info" ]]; then
        echo "cpu=0 memory=0"
        return
    fi

    local cpu mem
    cpu=$(echo "$info" | jq -r '.monit.cpu // 0' 2>/dev/null || echo "0")
    mem=$(echo "$info" | jq -r '.monit.memory // 0' 2>/dev/null || echo "0")
    echo "cpu=${cpu} memory=${mem}"
}

# ─── Record resource baseline ────────────────────────────────────────────────
record_resource_baseline() {
    if pm2 list 2>/dev/null | grep -q "$SERVICE_NAME"; then
        log_section "Pre-Deploy Resource Baseline"
        local resources
        resources=$(get_resource_usage "$SERVICE_NAME")
        log_info "Current resource usage — ${resources}"
        echo "$resources" > "/tmp/wheeler_resource_baseline_${SERVICE_NAME}"
    else
        log_info "No existing process — no baseline to record"
    fi
}

# ─── Check restart loop ──────────────────────────────────────────────────────
check_restart_loop() {
    local name="$1"

    # Get restart count for this process
    local restarts
    restarts=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${name}\") | .pm2_env.restart_time // 0" 2>/dev/null || echo "0")

    log_info "Process restart count: ${restarts}"

    if [[ "$restarts" -gt "$MAX_RESTARTS" ]]; then
        log_warn "Restart count (${restarts}) exceeds threshold (${MAX_RESTARTS})"

        # Check the timing of recent restarts
        local uptime_ms
        uptime_ms=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${name}\") | .pm2_env.pm_uptime // 0" 2>/dev/null || echo "0")
        local now_ms
        now_ms=$(date +%s%3N 2>/dev/null || echo "0")

        if [[ "$uptime_ms" -gt 0 ]]; then
            local uptime_sec=$(( (now_ms - uptime_ms) / 1000 ))
            if [[ "$uptime_sec" -lt "$RESTART_WINDOW_SEC" ]]; then
                log_fatal "RESTART LOOP DETECTED: ${name} restarted ${restarts} times, uptime only ${uptime_sec}s (window: ${RESTART_WINDOW_SEC}s)"
                send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "CRITICAL" \
                    "Restart loop detected: ${restarts} restarts within ${RESTART_WINDOW_SEC}s window"
                return 1
            fi
        fi
    fi

    log_debug "No restart loop detected (restarts: ${restarts}, threshold: ${MAX_RESTARTS})"
    return 0
}

# ─── Graceful reload ─────────────────────────────────────────────────────────
pm2_graceful_reload() {
    log_section "Graceful PM2 Reload: ${SERVICE_NAME}"

    # Check if service exists in PM2
    if pm2 list 2>/dev/null | grep -q "$SERVICE_NAME"; then
        log_info "Service exists — performing graceful reload..."

        # Reload with environment update
        if pm2 reload "$SERVICE_NAME" --update-env 2>/dev/null; then
            log_success "PM2 reload initiated for: ${SERVICE_NAME}"
        else
            log_error "PM2 reload command failed for: ${SERVICE_NAME}"
            return 1
        fi

        # Wait for processes to be online
        sleep 5

        # Verify process is running
        local status
        status=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${SERVICE_NAME}\") | .pm2_env.status" 2>/dev/null || echo "stopped")

        if [[ "$status" == "online" ]]; then
            log_success "PM2 process online: ${SERVICE_NAME}"
        else
            log_error "PM2 process status is '${status}' after reload for: ${SERVICE_NAME}"

            # Check for restart loop
            check_restart_loop "$SERVICE_NAME" && {
                log_warn "Process may be starting. Waiting additional 10s..."
                sleep 10
            }

            status=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${SERVICE_NAME}\") | .pm2_env.status" 2>/dev/null || echo "stopped")
            if [[ "$status" != "online" ]]; then
                log_error "PM2 process still not online after wait"
                return 1
            fi
        fi
    else
        # First start — the service doesn't exist in PM2 yet
        log_info "Service not found in PM2 — attempting first start..."

        local service_dir="${WHEELER_BASE}/${SERVICE_NAME}"
        local ecosystem_file="${service_dir}/ecosystem.config.js"

        if [[ -f "$ecosystem_file" ]]; then
            log_info "Starting via ecosystem file: ${ecosystem_file}"
            if [[ -n "${DOPPLER_TOKEN:-}" ]]; then
                doppler run -- pm2 start "$ecosystem_file" --env "$ENVIRONMENT" --only "$SERVICE_NAME"
            else
                pm2 start "$ecosystem_file" --env "$ENVIRONMENT" --only "$SERVICE_NAME"
            fi
        else
            log_info "No ecosystem file found. Trying to start ${SERVICE_NAME} directly..."
            pm2 start "$SERVICE_NAME" --env "$ENVIRONMENT" || {
                log_error "Failed to start service: ${SERVICE_NAME}"
                return 1
            }
        fi

        sleep 3
    fi

    # Final status check
    local final_status
    final_status=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${SERVICE_NAME}\") | .pm2_env.status" 2>/dev/null || echo "unknown")

    log_kv "PM2 Status" "$final_status"
    return 0
}

# ─── PM2 health check ────────────────────────────────────────────────────────
pm2_health_check() {
    log_section "PM2 Health Check"

    local port
    port=$(get_service_port "$SERVICE_NAME")

    # 1. PM2 process status
    log_info "Checking PM2 process status..."
    local pm2_info
    pm2_info=$(get_pm2_process_info "$SERVICE_NAME")
    local status
    status=$(echo "$pm2_info" | jq -r '.pm2_env.status // "unknown"')

    if [[ "$status" != "online" ]]; then
        log_error "PM2 process not online: ${SERVICE_NAME} (status: ${status})"
        return 1
    fi
    log_success "PM2 process online: ${SERVICE_NAME}"

    local restarts
    restarts=$(echo "$pm2_info" | jq -r '.pm2_env.restart_time // 0')
    local uptime
    uptime=$(echo "$pm2_info" | jq -r '.pm2_env.pm_uptime // 0')
    local instances
    instances=$(echo "$pm2_info" | jq -r '.pm2_env.instances // 1')

    log_kv "Instances" "$instances"
    log_kv "Restarts"  "$restarts"
    log_kv "Uptime ms" "$uptime"

    # 2. HTTP health check (if service has a port)
    if [[ -n "$port" ]] && [[ "$port" != "null" ]] && [[ "$port" != "N/A" ]]; then
        local health_endpoint
        health_endpoint=$(get_health_endpoint "$SERVICE_NAME")
        health_endpoint="${health_endpoint:-/health}"

        local health_url="http://127.0.0.1:${port}${health_endpoint}"
        log_info "Performing HTTP health check: ${health_url}"

        if ! wait_for_health "$health_url" 30 2; then
            log_error "HTTP health check FAILED for: ${SERVICE_NAME}"
            return 1
        fi
    else
        log_info "No port configured for ${SERVICE_NAME} — skipping HTTP health check"
    fi

    # 3. Restart loop check
    if ! check_restart_loop "$SERVICE_NAME"; then
        return 1
    fi

    return 0
}

# ─── Resource comparison ─────────────────────────────────────────────────────
compare_resources() {
    log_section "Post-Deploy Resource Comparison"

    # Get current usage
    local current
    current=$(get_resource_usage "$SERVICE_NAME")

    # Get baseline
    local baseline_file="/tmp/wheeler_resource_baseline_${SERVICE_NAME}"
    local baseline="cpu=0 memory=0"
    if [[ -f "$baseline_file" ]]; then
        baseline=$(cat "$baseline_file")
    fi

    # Parse values
    local cur_cpu cur_mem base_cpu base_mem
    cur_cpu=$(echo "$current" | grep -oP 'cpu=\K[0-9.]+' || echo "0")
    cur_mem=$(echo "$current" | grep -oP 'memory=\K[0-9.]+' || echo "0")
    base_cpu=$(echo "$baseline" | grep -oP 'cpu=\K[0-9.]+' || echo "0")
    base_mem=$(echo "$baseline" | grep -oP 'memory=\K[0-9.]+' || echo "0")

    log_info "Resource comparison (before → after):"
    log_kv "CPU (before)"    "${base_cpu}%"
    log_kv "CPU (after)"     "${cur_cpu}%"
    log_kv "Memory (before)" "${base_mem} MB"
    log_kv "Memory (after)"  "${cur_mem} MB"

    # Warn if significant increase
    if command -v bc &>/dev/null; then
        local cpu_diff
        cpu_diff=$(echo "${cur_cpu} - ${base_cpu}" | bc 2>/dev/null || echo "0")

        if (( $(echo "$cpu_diff > 50" | bc -l 2>/dev/null || echo "0") )); then
            log_warn "CPU usage increased by ${cpu_diff}% after deployment — may indicate a problem"
        fi
    fi
}

# ─── PM2 rollback ────────────────────────────────────────────────────────────
pm2_rollback() {
    log_section "PM2 Rollback"

    log_info "Rolling back PM2 service: ${SERVICE_NAME}"

    # Try to restore from PM2 dump
    local latest_dump
    latest_dump=$(ls -t "${BACKUP_BASE}"/*_pm2_dump_${SERVICE_NAME}.pm2 2>/dev/null | head -1)

    if [[ -n "$latest_dump" ]] && [[ -f "$latest_dump" ]]; then
        log_info "Restoring PM2 state from: ${latest_dump}"
        cp "$latest_dump" "${HOME}/.pm2/dump.pm2"
        pm2 resurrect 2>/dev/null || {
            log_warn "PM2 resurrect failed — will try direct restart"
        }
    fi

    # Reload with previous state
    if pm2 list 2>/dev/null | grep -q "$SERVICE_NAME"; then
        log_info "Reloading ${SERVICE_NAME}..."
        pm2 reload "$SERVICE_NAME" --update-env 2>/dev/null || {
            log_error "PM2 reload during rollback failed"
            pm2 restart "$SERVICE_NAME" 2>/dev/null || {
                log_error "PM2 restart during rollback also failed"
                return 1
            }
        }
    else
        log_warn "Service ${SERVICE_NAME} not found in PM2 — attempting resurrect"
        pm2 resurrect 2>/dev/null || {
            log_error "PM2 resurrect failed"
            return 1
        }
    fi

    sleep 5

    # Verify after rollback
    local status
    status=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${SERVICE_NAME}\") | .pm2_env.status" 2>/dev/null || echo "unknown")

    if [[ "$status" == "online" ]]; then
        log_success "PM2 rollback successful — ${SERVICE_NAME} is online"
        pm2 save
        return 0
    else
        log_fatal "PM2 rollback FAILED — ${SERVICE_NAME} status: ${status}"
        return 1
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    enable_error_tracing
    enable_signal_handlers

    validate_pm2_args
    ensure_pm2_daemon

    log_section "PM2 Deployment: ${SERVICE_NAME} → ${ENVIRONMENT}"
    log_kv "Service"     "$SERVICE_NAME"
    log_kv "Environment" "$ENVIRONMENT"
    log_kv "Node"        "$(hostname)"
    log_kv "Deploy ID"   "$DEPLOY_ID"

    # Confirm production
    if [[ "$ENVIRONMENT" == "production" ]] && [[ -z "$FORCE_CONFIRM" ]]; then
        confirm_action "Deploying PM2 service to PRODUCTION: ${SERVICE_NAME}" || exit 1
    fi

    # 1. Pre-deploy backup
    backup_pm2_state

    # 2. Record resource baseline
    record_resource_baseline

    # 3. Graceful reload
    if ! pm2_graceful_reload; then
        log_fatal "PM2 graceful reload FAILED"
        send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "CRITICAL" \
            "PM2 graceful reload failed"

        if pm2_rollback; then
            log_success "PM2 auto-rollback successful"
            exit 3
        else
            log_fatal "PM2 auto-rollback FAILED!"
            exit 5
        fi
    fi

    # 4. Health check
    if ! pm2_health_check; then
        log_fatal "PM2 health check FAILED after deploy"
        send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "CRITICAL" \
            "PM2 health check failed after deployment"

        if pm2_rollback; then
            log_success "PM2 auto-rollback successful"
            exit 4
        else
            log_fatal "PM2 auto-rollback FAILED!"
            exit 5
        fi
    fi

    # 5. Resource comparison
    compare_resources

    # 6. Save PM2 state
    pm2 save 2>/dev/null || log_warn "PM2 save failed (non-critical)"

    log_success "PM2 deployment completed: ${SERVICE_NAME} on ${ENVIRONMENT}"
    send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "OK" \
        "PM2 deployment successful"

    return 0
}

# ─── Entry Point ─────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
