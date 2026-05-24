#!/usr/bin/env bash
# ==============================================================================
# rollback.sh — Master Rollback Orchestrator
# ==============================================================================
# Usage: ./rollback.sh <service-name> <environment> [--version <tag>] [--force]
#
# Orchestrates a complete service rollback:
#   1. Detects the service type (docker, pm2, static)
#   2. Finds the most recent successful deployment backup
#   3. Calls the appropriate sub-rollback scripts in order
#   4. Verifies rollback health after restore
#   5. Preserves all logs from the failed deployment
#   6. Preserves all backups
#   7. Notifies the team about the rollback event
#   8. Logs a complete rollback audit trail
#
# Exit Codes:
#   0  Rollback fully successful
#   1  Rollback failed (backup not found, script error, service down)
#   2  Verification failed (health checks did not pass after restore)
# ==============================================================================
set -euo pipefail

# ── Script Setup ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-rollback.sh"

readonly ROLLBACK_VERSION="3.1.0"

usage() {
    cat <<EOF
rollback.sh — Master Rollback Orchestrator v${ROLLBACK_VERSION}

Usage: $(basename "$0") <service-name> <environment> [OPTIONS]

Rolls back a service deployment to the most recent known-good backup.

Arguments:
  service-name   Name of the service to roll back (e.g. api-gateway, litellm,
                 openclaw, frontend-app, routing)
  environment    Target environment (e.g. production, staging)

Options:
  --version TAG  Roll back to a specific version tag (default: latest backup)
  --force        Skip confirmation prompts (use with caution!)
  --dry-run      Show what would happen without making changes
  --help, -h     Show this help message

Examples:
  $(basename "$0") api-gateway production
  $(basename "$0") litellm production --version v2.4.1 --force
  $(basename "$0") frontend-app staging --dry-run

Servers:
  EDGE NODE    Hostinger / 187.77.148.88  — Traefik, Nginx, frontend apps
  AIOPS NODE   Hetzner   / 5.78.140.118   — APIs, AI workers, PM2, LiteLLM
  COREDB NODE  Hetzner   / 5.78.210.123   — PostgreSQL, Redis, MinIO, backups
EOF
}

# ── Dry Run Mode ─────────────────────────────────────────────────────────────
DRY_RUN=false

dry_run_log() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "[DRY-RUN] $*"
        return 0
    fi
    return 1
}

# ── Pre-flight Checks ────────────────────────────────────────────────────────
run_preflight() {
    local service_name="$1"
    local environment="$2"

    log_info "Running pre-flight checks..."

    # Check we have the sub-scripts available
    local required_scripts=("restore-env.sh" "restore-pm2.sh" "restore-docker.sh" "restore-routing.sh")
    for script in "${required_scripts[@]}"; do
        if [[ ! -x "${SCRIPT_DIR}/${script}" ]]; then
            log_error "Required sub-script not found or not executable: ${SCRIPT_DIR}/${script}"
            return 1
        fi
    done

    # Check common dependencies
    for cmd in jq curl; do
        if ! command -v "${cmd}" &>/dev/null; then
            log_error "Required command not found: ${cmd}"
            return 1
        fi
    done

    # Check backup root exists
    if [[ ! -d "${BACKUP_ROOT}" ]]; then
        log_error "Backup root directory does not exist: ${BACKUP_ROOT}"
        return 1
    fi

    log_success "Pre-flight checks passed."
    return 0
}

# ── Phase 1: Discovery ───────────────────────────────────────────────────────
run_discovery() {
    local service_name="$1"
    local environment="$2"
    local version_tag="$3"

    log_info "=== Phase 1: Discovery ==="

    # Detect service type
    local service_type
    service_type="$(get_service_type "${service_name}" "${environment}")"
    log_info "Detected service type: ${service_type}"
    audit_log "INFO" "Service type: ${service_type}"

    # Special case: 'routing' service spans both Traefik and Nginx
    if [[ "${service_name}" == "routing" ]]; then
        service_type="routing"
        log_info "Service 'routing' detected — using routing-specific restore path."
    fi

    # Find the backup to restore
    local backup_path
    if [[ -n "${version_tag}" ]]; then
        backup_path="$(find_backup_by_version "${service_name}" "${environment}" "${version_tag}")" || {
            log_error "Cannot proceed — no backup found for version ${version_tag}"
            return 1
        }
        log_info "Found backup for version ${version_tag}: ${backup_path}"
    else
        backup_path="$(find_latest_backup "${service_name}" "${environment}")" || {
            log_error "Cannot proceed — no backup found for ${service_name}/${environment}"
            return 1
        }
        log_info "Found latest backup: ${backup_path}"
    fi

    audit_log "INFO" "Backup path: ${backup_path}"

    # Verify backup integrity
    if ! verify_backup_integrity "${backup_path}" "${service_type}"; then
        log_error "Backup integrity check failed for ${backup_path}"
        return 1
    fi

    # Get version information
    local from_version
    from_version="$(get_current_version "${service_name}" "${environment}")"
    local to_version
    to_version="$(get_backup_version "${backup_path}")"

    log_info "Rollback: ${from_version} -> ${to_version}"

    # Echo results for the caller to capture
    echo "${service_type}" "${backup_path}" "${from_version}" "${to_version}"
    return 0
}

# ── Phase 2: Execute Rollback ────────────────────────────────────────────────
run_rollback() {
    local service_name="$1"
    local environment="$2"
    local service_type="$3"
    local backup_path="$4"

    log_info "=== Phase 2: Execute Rollback ==="
    audit_log "INFO" "Starting rollback execution for ${service_name} (${service_type})"

    # Step 1: Restore environment files
    log_info "Step 2.1: Restoring .env files..."
    if ! dry_run_log "Would restore .env for ${service_name}"; then
        if ! "${SCRIPT_DIR}/restore-env.sh" "${service_name}" "${environment}" "${backup_path}"; then
            log_error ".env restore failed!"
            return 1
        fi
    fi

    # Step 2: Restore the service itself based on type
    case "${service_type}" in
        docker)
            log_info "Step 2.2: Restoring Docker service..."
            if ! dry_run_log "Would run restore-docker.sh for ${service_name}"; then
                if ! "${SCRIPT_DIR}/restore-docker.sh" "${service_name}" "${environment}" "${backup_path}"; then
                    log_error "Docker restore failed!"
                    return 1
                fi
            fi
            ;;

        pm2)
            log_info "Step 2.2: Restoring PM2 service..."
            if ! dry_run_log "Would run restore-pm2.sh for ${service_name}"; then
                if ! "${SCRIPT_DIR}/restore-pm2.sh" "${service_name}" "${environment}" "${backup_path}"; then
                    log_error "PM2 restore failed!"
                    return 1
                fi
            fi
            ;;

        static)
            log_info "Step 2.2: Restoring static files..."
            if ! dry_run_log "Would restore static files for ${service_name}"; then
                local static_backup="${backup_path}/static"
                if [[ -d "${static_backup}" ]]; then
                    local static_target="/opt/services/${service_name}/html"
                    mkdir -p "${static_target}"
                    cp -r "${static_backup}/"* "${static_target}/"
                    log_success "Static files restored to ${static_target}"
                    audit_log "INFO" "Static files restored from ${static_backup}"
                else
                    log_warn "No static files backup found at ${static_backup}. Skipping."
                fi
            fi
            ;;

        routing)
            log_info "Step 2.2: Restoring routing configuration..."
            if ! dry_run_log "Would run restore-routing.sh for ${environment}"; then
                if ! "${SCRIPT_DIR}/restore-routing.sh" "${environment}" "${backup_path}"; then
                    log_error "Routing restore failed!"
                    return 1
                fi
            fi
            ;;

        *)
            log_error "Unknown service type: ${service_type}"
            return 1
            ;;
    esac

    log_success "Rollback execution completed."
    return 0
}

# ── Phase 3: Verification ───────────────────────────────────────────────────
run_verification() {
    local service_name="$1"
    local environment="$2"
    local service_type="$3"

    log_info "=== Phase 3: Verification ==="

    case "${service_type}" in
        docker)
            log_info "Verifying Docker container health..."
            if ! dry_run_log "Would verify Docker container health"; then
                # Check container is running
                local containers
                containers="$(docker ps --filter "name=${service_name}" -q 2>/dev/null)"
                if [[ -z "${containers}" ]]; then
                    log_error "No running containers found for ${service_name}"
                    return 1
                fi
                log_success "Container(s) running: ${containers}"

                # Verify health status
                local unhealthy=0
                for cid in ${containers}; do
                    local health
                    health="$(docker inspect "${cid}" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || echo "unknown")"
                    if [[ "${health}" == "unhealthy" ]]; then
                        log_error "Container ${cid} is UNHEALTHY"
                        unhealthy=1
                    elif [[ "${health}" == "healthy" ]]; then
                        log_success "Container ${cid} is healthy"
                    else
                        log_info "Container ${cid} health: ${health}"
                    fi
                done

                if [[ ${unhealthy} -ne 0 ]]; then
                    return 1
                fi
            fi
            ;;

        pm2)
            log_info "Verifying PM2 process..."
            if ! dry_run_log "Would verify PM2 process"; then
                local status
                status="$(pm2 jlist 2>/dev/null | jq -r --arg name "${service_name}" \
                    '.[] | select(.name == $name) | .pm2_env.status // "unknown"')"

                if [[ "${status}" != "online" ]]; then
                    log_error "PM2 process ${service_name} is not online (status: ${status})"
                    return 1
                fi
                log_success "PM2 process ${service_name} is ${status}"

                # Check uptime
                local uptime_ms
                uptime_ms="$(pm2 jlist 2>/dev/null | jq -r --arg name "${service_name}" \
                    '.[] | select(.name == $name) | .pm2_env.pm_uptime // 0')"
                log_info "Process uptime: ${uptime_ms}ms"
            fi
            ;;

        static)
            log_info "Verifying static service..."
            if ! dry_run_log "Would verify static service"; then
                # Check that the static directory exists and has content
                local static_target="/opt/services/${service_name}/html"
                if [[ ! -d "${static_target}" ]] || [[ -z "$(ls -A "${static_target}" 2>/dev/null)" ]]; then
                    log_error "Static directory is empty or missing: ${static_target}"
                    return 1
                fi
                log_success "Static files present at ${static_target}"
            fi
            ;;

        routing)
            log_info "Verifying routing..."
            if ! dry_run_log "Would verify routing"; then
                # Quick route check
                local http_code
                http_code="$(curl -s -o /dev/null -w '%{http_code}' -k --connect-timeout 5 \
                    "http://localhost:8080/api/rawdata" 2>/dev/null || echo "000")"
                if [[ "${http_code}" == "000" ]]; then
                    log_warn "Traefik dashboard not reachable (may be expected)"
                else
                    log_success "Traefik API reachable (${http_code})"
                fi
            fi
            ;;
    esac

    # Run service-specific health endpoints
    local health_urls=()

    # Map service names to their health endpoints
    case "${service_name}" in
        api-gateway)
            health_urls+=("http://localhost:4000/health")
            ;;
        litellm)
            health_urls+=("http://localhost:${LITELLM_PORT:-4001}/health")
            ;;
        openclaw)
            health_urls+=("http://localhost:${OPENCLAW_PORT:-4002}/health")
            ;;
        ai-worker)
            health_urls+=("http://localhost:${AI_WORKER_PORT:-4100}/health")
            ;;
        frontend-app)
            health_urls+=("http://localhost:3000/health")
            ;;
        dashboard)
            health_urls+=("http://localhost:3100/health")
            ;;
    esac

    for url in "${health_urls[@]}"; do
        if ! dry_run_log "Would check health at ${url}"; then
            if ! wait_for_http_health "${url}" 30 3; then
                log_error "Health endpoint ${url} did not respond!"
                return 1
            fi
        fi
    done

    log_success "Verification completed."
    return 0
}

# ── Phase 4: Preservation ───────────────────────────────────────────────────
run_preservation() {
    local service_name="$1"
    local environment="$2"

    log_info "=== Phase 4: Preserve Logs and Backups ==="

    if dry_run_log "Would preserve failed deployment artifacts"; then
        return 0
    fi

    local preservation_dir="${BACKUP_ROOT}/rollback-preservations/${service_name}/${environment}/$(now_compact)"
    mkdir -p "${preservation_dir}"

    # Preserve PM2 logs if applicable
    if command -v pm2 &>/dev/null; then
        if pm2 jlist 2>/dev/null | jq -e --arg name "${service_name}" \
            '.[] | select(.name == $name)' >/dev/null 2>&1; then
            log_info "Preserving PM2 logs for ${service_name}..."
            pm2 logs "${service_name}" --nostream --lines 200 2>/dev/null \
                > "${preservation_dir}/pm2-logs.txt" || true
        fi
    fi

    # Preserve Docker logs if applicable
    if command -v docker &>/dev/null; then
        docker ps -a --filter "name=${service_name}" --format '{{.ID}}' 2>/dev/null | while IFS= read -r cid; do
            [[ -z "${cid}" ]] && continue
            docker logs --tail 500 "${cid}" > "${preservation_dir}/docker-logs-${cid}.txt" 2>&1 || true
        done
    fi

    # Preserve systemd/journald logs for the service
    if command -v journalctl &>/dev/null; then
        journalctl -u "${service_name}" --no-pager -n 200 2>/dev/null \
            > "${preservation_dir}/journald-logs.txt" 2>/dev/null || true
    fi

    # Preserve a snapshot of current system state
    {
        echo "=== Preservation Snapshot $(now_iso) ==="
        echo ""
        echo "--- Disk Usage ---"
        df -h
        echo ""
        echo "--- Memory ---"
        free -h
        echo ""
        echo "--- Load ---"
        uptime
        echo ""
        echo "--- PM2 List ---"
        pm2 jlist 2>/dev/null | jq -C '.' || echo "(PM2 not available)"
        echo ""
        echo "--- Docker PS ---"
        docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null || echo "(Docker not available)"
    } > "${preservation_dir}/system-snapshot.txt" 2>/dev/null

    log_success "Preservation artifacts saved to ${preservation_dir}"
    audit_log "INFO" "Preservation artifacts saved to ${preservation_dir}"

    echo "${preservation_dir}"
    return 0
}

# ── Phase 5: Notification ────────────────────────────────────────────────────
run_notification() {
    local service_name="$1"
    local environment="$2"
    local from_version="$3"
    local to_version="$4"
    local duration="$5"
    local outcome="$6"
    local message="${7:-}"

    log_info "=== Phase 5: Notification ==="

    if dry_run_log "Would send rollback notification"; then
        return 0
    fi

    local details="${message:-Rollback from ${from_version} to ${to_version} completed in ${duration}s}"

    case "${outcome}" in
        SUCCESS)
            send_rollback_alert "${service_name}" "${environment}" "SUCCESS" "${details}"
            ;;
        FAILED)
            send_rollback_alert "${service_name}" "${environment}" "FAILED" "${details}"
            ;;
        *)
            send_rollback_alert "${service_name}" "${environment}" "WARNING" "${details}"
            ;;
    esac

    return 0
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    local service_name=""
    local environment=""
    local version_tag=""
    local force_mode=false

    # ── Parse arguments ──────────────────────────────────────────────────
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                version_tag="$2"
                shift 2
                ;;
            --force)
                force_mode=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
            *)
                if [[ -z "${service_name}" ]]; then
                    service_name="$1"
                elif [[ -z "${environment}" ]]; then
                    environment="$1"
                else
                    log_error "Unexpected argument: $1"
                    usage >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # ── Validate arguments ───────────────────────────────────────────────
    if [[ -z "${service_name}" ]] || [[ -z "${environment}" ]]; then
        log_error "Both service-name and environment are required."
        usage >&2
        exit 1
    fi

    # Validate environment name
    case "${environment}" in
        production|prod|staging|dev|development) ;;
        *)
            log_error "Invalid environment: ${environment} (use production, staging, dev)"
            exit 1
            ;;
    esac

    # ── Banner ───────────────────────────────────────────────────────────
    cat <<BANNER >&2

  ╔═════════════════════════════════════════════════════════════╗
  ║             ROLLBACK  ENGINE  v${ROLLBACK_VERSION}                      ║
  ║  Service:     ${service_name}                        ║
  ║  Environment: ${environment}                        ║
  ║  Version:     ${version_tag:-latest backup}          ║
  ║  Mode:        ${DRY_RUN:+DRY RUN}${DRY_RUN:-LIVE}    ║
  ╚═════════════════════════════════════════════════════════════╝

BANNER

    # ── Initialize audit log ─────────────────────────────────────────────
    init_audit_log "${service_name}" "${environment}"
    audit_log "INFO" "Rollback started. Version=${ROLLBACK_VERSION} Force=${force_mode} DryRun=${DRY_RUN}"

    local overall_start=${SECONDS}

    # ── Pre-flight ───────────────────────────────────────────────────────
    if ! run_preflight "${service_name}" "${environment}"; then
        log_error "Pre-flight checks failed. Aborting."
        close_audit_log 1
        exit 1
    fi

    # ── Confirmation (unless forced) ─────────────────────────────────────
    if [[ "${force_mode}" != "true" ]] && [[ "${DRY_RUN}" != "true" ]]; then
        echo ""
        log_warn "About to roll back '${service_name}' in '${environment}'."
        log_warn "This will restore the service to a previous version."
        echo ""
        read -r -p "Type 'ROLLBACK' to confirm: " confirm
        if [[ "${confirm}" != "ROLLBACK" ]]; then
            log_info "Rollback cancelled by user."
            close_audit_log 0
            exit 0
        fi
    fi

    # ── Acquire lock ─────────────────────────────────────────────────────
    if ! acquire_rollback_lock "${service_name}" "${environment}"; then
        log_error "Failed to acquire rollback lock. Is another rollback running?"
        close_audit_log 1
        exit 1
    fi

    # ── Phase 1: Discovery ───────────────────────────────────────────────
    local discovery_output
    discovery_output="$(run_discovery "${service_name}" "${environment}" "${version_tag}")" || {
        log_error "Discovery phase failed."
        log_rollback_event "${service_name}" "${environment}" "unknown" "unknown" \
            "rollback" "failure" "$((SECONDS - overall_start))" "Discovery failed"
        run_notification "${service_name}" "${environment}" "unknown" "unknown" \
            "$((SECONDS - overall_start))" "FAILED" "Discovery phase failed"
        release_rollback_lock
        close_audit_log 1
        exit 1
    }

    IFS=' ' read -r service_type backup_path from_version to_version <<< "${discovery_output}"

    audit_log "INFO" "Discovery: type=${service_type} backup=${backup_path} from=${from_version} to=${to_version}"

    # ── Phase 2: Execute Rollback ────────────────────────────────────────
    if ! run_rollback "${service_name}" "${environment}" "${service_type}" "${backup_path}"; then
        log_error "Rollback execution failed."
        local fail_duration=$((SECONDS - overall_start))
        log_rollback_event "${service_name}" "${environment}" "${from_version}" "${to_version}" \
            "rollback" "failure" "${fail_duration}" "Execution phase failed"
        run_notification "${service_name}" "${environment}" "${from_version}" "${to_version}" \
            "${fail_duration}" "FAILED" "Rollback execution failed after ${fail_duration}s"
        release_rollback_lock
        close_audit_log 1
        exit 1
    fi

    # ── Phase 3: Verification ────────────────────────────────────────────
    local verify_ok=true
    if ! run_verification "${service_name}" "${environment}" "${service_type}"; then
        log_error "Verification failed! Service may be in a degraded state."
        verify_ok=false
    fi

    # ── Phase 4: Preservation ────────────────────────────────────────────
    local preservation_dir
    preservation_dir="$(run_preservation "${service_name}" "${environment}")"
    log_info "Preservation directory: ${preservation_dir}"

    # ── Phase 5: Notification ────────────────────────────────────────────
    local total_duration=$((SECONDS - overall_start))

    if [[ "${verify_ok}" == "true" ]]; then
        log_rollback_event "${service_name}" "${environment}" "${from_version}" "${to_version}" \
            "rollback" "success" "${total_duration}" "Rollback completed successfully"

        run_notification "${service_name}" "${environment}" "${from_version}" "${to_version}" \
            "${total_duration}" "SUCCESS" \
            "Rollback completed in ${total_duration}s. Preservation at: ${preservation_dir}"

        log_success "=== ROLLBACK SUCCESSFUL (${total_duration}s) ==="
        release_rollback_lock
        close_audit_log 0
        exit 0
    else
        log_rollback_event "${service_name}" "${environment}" "${from_version}" "${to_version}" \
            "rollback" "failure" "${total_duration}" "Verification failed"

        run_notification "${service_name}" "${environment}" "${from_version}" "${to_version}" \
            "${total_duration}" "FAILED" \
            "Rollback completed but verification failed. Service may be degraded. Preservation at: ${preservation_dir}"

        log_error "=== ROLLBACK COMPLETED WITH VERIFICATION FAILURES ==="
        release_rollback_lock
        close_audit_log 2
        exit 2
    fi
}

# ── Run ──────────────────────────────────────────────────────────────────────
main "$@"
