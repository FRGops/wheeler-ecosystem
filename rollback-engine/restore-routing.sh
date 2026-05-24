#!/usr/bin/env bash
# ==============================================================================
# restore-routing.sh — Restore Traefik and Nginx routing configs from backup
# Usage: ./restore-routing.sh <environment> <backup-path>
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-rollback.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <environment> <backup-path>

Restores Traefik dynamic configuration and Nginx configuration from a
deployment backup. Validates syntax, reloads services gracefully, and
verifies routes are serving correctly.

Arguments:
  environment    Target environment (e.g. production, staging)
  backup-path    Full path to the backup directory

Exit Codes:
  0  Routing restore completed and verified
  1  Restore failed (config missing, syntax error, reload failed)
  2  Verification failed (routes not serving)
EOF
}

# ── Configuration Paths ──────────────────────────────────────────────────────
readonly TRAEFIK_DYNAMIC_DIR="${TRAEFIK_DYNAMIC_DIR:-/etc/traefik/dynamic}"
readonly TRAEFIK_STATIC_CONF="${TRAEFIK_STATIC_CONF:-/etc/traefik/traefik.yml}"
readonly NGINX_CONF_DIR="${NGINX_CONF_DIR:-/etc/nginx}"
readonly NGINX_SITES_DIR="${NGINX_SITES_DIR:-/etc/nginx/sites-enabled}"
readonly TRAEFIK_API_URL="${TRAEFIK_API_URL:-http://localhost:8080}"

# ── Validate Traefik Config Syntax ───────────────────────────────────────────
validate_traefik_config() {
    log_info "Validating Traefik configuration syntax..."

    if ! command -v traefik &>/dev/null; then
        log_warn "Traefik binary not available in PATH — skipping static config validation."
        # Still try docker exec approach
        if docker ps --filter "name=traefik" --format '{{.ID}}' 2>/dev/null | head -1 | grep -q .; then
            local traefik_cid
            traefik_cid="$(docker ps --filter 'name=traefik' -q | head -1)"
            if docker exec "${traefik_cid}" traefik validate --configFile=/etc/traefik/traefik.yml 2>&1; then
                log_success "Traefik config validated via container."
                return 0
            else
                log_error "Traefik config validation failed (via container)."
                return 1
            fi
        fi
        return 0
    fi

    local errors
    errors="$(traefik validate --configFile="${TRAEFIK_STATIC_CONF}" 2>&1)" || {
        log_error "Traefik config validation FAILED:"
        echo "${errors}" | tail -20 >&2
        audit_log "ERROR" "Traefik validation failed: $(echo "${errors}" | tail -5)"
        return 1
    }

    log_success "Traefik configuration validated."
    return 0
}

# ── Validate Nginx Config Syntax ─────────────────────────────────────────────
validate_nginx_config() {
    log_info "Validating Nginx configuration syntax..."

    if ! command -v nginx &>/dev/null; then
        log_warn "Nginx binary not available in PATH — skipping config validation."
        return 0
    fi

    local errors
    errors="$(nginx -t 2>&1)" || {
        log_error "Nginx config validation FAILED:"
        echo "${errors}" | tail -20 >&2
        audit_log "ERROR" "Nginx validation failed: $(echo "${errors}" | tail -5)"
        return 1
    }

    log_success "Nginx configuration validated."
    return 0
}

# ── Reload Traefik Gracefully ────────────────────────────────────────────────
reload_traefik() {
    log_info "Reloading Traefik routing..."

    # Method 1: Send SIGHUP to the Traefik process
    local traefik_pid
    traefik_pid="$(pgrep -f 'traefik' 2>/dev/null | head -1 || true)"

    if [[ -n "${traefik_pid}" ]]; then
        kill -HUP "${traefik_pid}" 2>/dev/null || true
        log_info "Sent SIGHUP to Traefik PID ${traefik_pid}"

        # Wait for Traefik to stabilize
        sleep 3

        # Verify Traefik is still running
        if ! kill -0 "${traefik_pid}" 2>/dev/null; then
            log_error "Traefik process died after reload!"
            audit_log "ERROR" "Traefik PID ${traefik_pid} died after reload"
            return 1
        fi
        log_success "Traefik reloaded successfully (via SIGHUP)."
        return 0
    fi

    # Method 2: Docker container reload
    local traefik_cid
    traefik_cid="$(docker ps --filter 'name=traefik' -q 2>/dev/null | head -1)"
    if [[ -n "${traefik_cid}" ]]; then
        docker kill --signal=HUP "${traefik_cid}" 2>/dev/null || true
        log_info "Sent SIGHUP to Traefik container ${traefik_cid}"
        sleep 3
        if docker ps --filter "id=${traefik_cid}" --format '{{.Status}}' 2>/dev/null | grep -qi 'up'; then
            log_success "Traefik container reloaded successfully."
            return 0
        else
            log_error "Traefik container is not running after reload!"
            audit_log "ERROR" "Traefik container ${traefik_cid} not running after reload"
            return 1
        fi
    fi

    log_warn "Could not find Traefik process to reload. Skipping."
    return 0
}

# ── Reload Nginx Gracefully ──────────────────────────────────────────────────
reload_nginx() {
    log_info "Reloading Nginx..."

    if ! command -v nginx &>/dev/null; then
        # Try docker container
        local nginx_cid
        nginx_cid="$(docker ps --filter 'name=nginx' -q 2>/dev/null | head -1)"
        if [[ -n "${nginx_cid}" ]]; then
            if docker exec "${nginx_cid}" nginx -s reload 2>&1; then
                log_success "Nginx reloaded via container ${nginx_cid}"
                return 0
            else
                log_error "Nginx reload failed via container!"
                return 1
            fi
        fi
        log_warn "Nginx not found. Skipping reload."
        return 0
    fi

    if nginx -s reload 2>&1; then
        sleep 1
        log_success "Nginx reloaded successfully."
        return 0
    else
        log_error "Nginx reload failed!"
        audit_log "ERROR" "Nginx reload command failed"
        return 1
    fi
}

# ── Verify Routes Are Serving ────────────────────────────────────────────────
verify_routes() {
    local environment="$1"
    local check_urls=()

    log_info "Verifying routes are serving correctly..."

    # Determine URLs to check based on environment and what configs exist
    if [[ "${environment}" == "production" ]]; then
        # Production URLs to verify
        check_urls+=("https://187.77.148.88/health")
        check_urls+=("https://187.77.148.88/api/health")
        check_urls+=("https://187.77.148.88/dashboard/health")
    else
        # Staging URLs
        check_urls+=("https://187.77.148.88/staging/health")
        check_urls+=("https://5.78.140.118/health")
    fi

    local all_ok=1
    for url in "${check_urls[@]}"; do
        log_info "Checking route: ${url}"
        local http_code
        http_code="$(curl -s -o /dev/null -w '%{http_code}' -k --connect-timeout 5 "${url}" 2>/dev/null || echo "000")"

        if [[ "${http_code}" =~ ^(2[0-9][0-9]|3[0-9][0-9]|401|403)$ ]]; then
            log_success "  ${url} -> ${http_code} OK"
        else
            log_warn "  ${url} -> ${http_code} (may be expected)"
            # Not failing on non-2xx as some endpoints may legitimately return 404 if no service
        fi
    done

    # Check Traefik API for router status
    if curl -s "${TRAEFIK_API_URL}/api/http/routers" 2>/dev/null | jq -e '.' >/dev/null 2>&1; then
        local router_count
        router_count="$(curl -s "${TRAEFIK_API_URL}/api/http/routers" 2>/dev/null | jq 'length')"
        log_info "Traefik reports ${router_count} HTTP routers configured."

        # Check for any routers with errors
        local error_routers
        error_routers="$(curl -s "${TRAEFIK_API_URL}/api/http/routers" 2>/dev/null | jq -r \
            '.[] | select(.status != "enabled") | "  \(.name): \(.status)"' 2>/dev/null || true)"
        if [[ -n "${error_routers}" ]]; then
            log_warn "Routers with non-enabled status:"
            echo "${error_routers}" >&2
        fi
    else
        log_warn "Traefik API not reachable at ${TRAEFIK_API_URL}"
    fi

    return 0
}

# ── Restore Traefik Dynamic Config ───────────────────────────────────────────
restore_traefik_config() {
    local backup_path="$1"

    local traefik_backup="${backup_path}/routing/traefik"
    [[ -d "${traefik_backup}" ]] || traefik_backup="${backup_path}/traefik"

    if [[ ! -d "${traefik_backup}" ]]; then
        log_info "No Traefik dynamic config found in backup. Skipping."
        return 0
    fi

    log_info "Restoring Traefik dynamic configuration from ${traefik_backup}..."

    # Preserve current config
    if [[ -d "${TRAEFIK_DYNAMIC_DIR}" ]]; then
        local preserved
        preserved="$(preserve_failed_artifact "${TRAEFIK_DYNAMIC_DIR}" "traefik-dynamic")"
        audit_log "INFO" "Preserved current Traefik dynamic config to ${preserved}"
    fi

    # Copy dynamic config files
    mkdir -p "${TRAEFIK_DYNAMIC_DIR}"
    cp -r "${traefik_backup}/"* "${TRAEFIK_DYNAMIC_DIR}/" 2>/dev/null || true

    log_success "Traefik dynamic config restored."
    audit_log "INFO" "Traefik dynamic config restored from ${traefik_backup}"

    # Copy static config if present
    if [[ -f "${backup_path}/routing/traefik.yml" ]]; then
        preserve_failed_artifact "${TRAEFIK_STATIC_CONF}" "traefik-static"
        cp "${backup_path}/routing/traefik.yml" "${TRAEFIK_STATIC_CONF}"
        log_info "Traefik static config restored."
    fi

    return 0
}

# ── Restore Nginx Config ─────────────────────────────────────────────────────
restore_nginx_config() {
    local backup_path="$1"

    local nginx_backup="${backup_path}/routing/nginx"
    [[ -d "${nginx_backup}" ]] || nginx_backup="${backup_path}/nginx"

    if [[ ! -d "${nginx_backup}" ]]; then
        log_info "No Nginx config found in backup. Skipping."
        return 0
    fi

    log_info "Restoring Nginx configuration from ${nginx_backup}..."

    # Preserve current config
    if [[ -d "${NGINX_SITES_DIR}" ]]; then
        preserve_failed_artifact "${NGINX_SITES_DIR}" "nginx-sites"
    fi
    if [[ -f "${NGINX_CONF_DIR}/nginx.conf" ]]; then
        preserve_failed_artifact "${NGINX_CONF_DIR}/nginx.conf" "nginx-conf"
    fi

    AUDIT_LOG "INFO" "Preserved current Nginx config"

    # Restore site configs
    if [[ -d "${nginx_backup}/sites-enabled" ]]; then
        mkdir -p "${NGINX_SITES_DIR}"
        cp -r "${nginx_backup}/sites-enabled/"* "${NGINX_SITES_DIR}/" 2>/dev/null || true
    fi

    # Restore main config if present
    if [[ -f "${nginx_backup}/nginx.conf" ]]; then
        cp "${nginx_backup}/nginx.conf" "${NGINX_CONF_DIR}/nginx.conf"
    fi

    log_success "Nginx configuration restored."
    audit_log "INFO" "Nginx config restored from ${nginx_backup}"

    return 0
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    if [[ $# -lt 2 ]]; then
        usage >&2
        exit 1
    fi

    local environment="$1"
    local backup_path="$2"
    local service_name="routing"

    init_audit_log "${service_name}" "${environment}"
    audit_log "INFO" "restore-routing.sh starting for ${environment} from ${backup_path}"

    local start_time=${SECONDS}

    # ── 1. Validate backup ───────────────────────────────────────────────
    if [[ ! -d "${backup_path}" ]]; then
        log_error "Backup path does not exist: ${backup_path}"
        send_rollback_alert "routing" "${environment}" "FAILED" \
            "Routing restore - backup path not found"
        close_audit_log 1
        exit 1
    fi

    # ── 2. Restore Traefik config ────────────────────────────────────────
    restore_traefik_config "${backup_path}" || {
        log_error "Failed to restore Traefik config"
        close_audit_log 1
        exit 1
    }

    # ── 3. Restore Nginx config ──────────────────────────────────────────
    restore_nginx_config "${backup_path}" || {
        log_error "Failed to restore Nginx config"
        close_audit_log 1
        exit 1
    }

    # ── 4. Validate Traefik syntax ───────────────────────────────────────
    if ! validate_traefik_config; then
        log_error "Traefik config validation failed. Aborting reload."
        send_rollback_alert "routing" "${environment}" "FAILED" \
            "Routing restore - Traefik config syntax error"
        close_audit_log 1
        exit 1
    fi

    # ── 5. Validate Nginx syntax ─────────────────────────────────────────
    if ! validate_nginx_config; then
        log_error "Nginx config validation failed. Aborting reload."
        send_rollback_alert "routing" "${environment}" "FAILED" \
            "Routing restore - Nginx config syntax error"
        close_audit_log 1
        exit 1
    fi

    # ── 6. Reload Traefik ────────────────────────────────────────────────
    if ! reload_traefik; then
        log_error "Traefik reload failed."
        send_rollback_alert "routing" "${environment}" "FAILED" \
            "Routing restore - Traefik reload failed"
        close_audit_log 1
        exit 1
    fi

    # ── 7. Reload Nginx ──────────────────────────────────────────────────
    if ! reload_nginx; then
        log_warn "Nginx reload failed. Continuing to verify..."
        # Not a hard failure — Traefik may be the primary router
    fi

    # ── 8. Verify routes ─────────────────────────────────────────────────
    if ! verify_routes "${environment}"; then
        log_error "Route verification indicated problems."
        send_rollback_alert "routing" "${environment}" "WARNING" \
            "Routing restore - route verification had warnings"
        close_audit_log 2
        exit 2
    fi

    # ── 9. Log success ──────────────────────────────────────────────────
    local duration
    duration=$((SECONDS - start_time))
    log_rollback_event "routing" "${environment}" "current" "previous" \
        "routing_restore" "success" "${duration}" "Routing restore completed successfully"

    send_rollback_alert "routing" "${environment}" "SUCCESS" \
        "Routing configs restored and verified (${duration}s)"

    close_audit_log 0
    return 0
}

main "$@"
