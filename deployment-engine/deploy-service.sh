#!/usr/bin/env bash
# =============================================================================
# deploy-service.sh — Master Service Deployer
# =============================================================================
# Usage: ./deploy-service.sh <service-name> <environment> <version>
#
# Master orchestrator that:
#   1. Detects service type (docker, pm2, static, systemd)
#   2. Runs preflight-check.sh
#   3. Runs pre-deploy backup
#   4. Delegates to type-specific deployer
#   5. Runs post-deploy-healthcheck.sh
#   6. Auto-rollback if health check fails
#   7. Logs to /var/log/wheeler/deploy/{service}/{timestamp}.log
#
# Exit Codes:
#   0  Deployment successful
#   1  Validation / preflight error
#   2  Deployment failed (no rollback attempted)
#   3  Deployment failed but rollback succeeded
#   4  Deployment failed and rollback also failed
#   5  Health check failed after deploy
# =============================================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

readonly DEPLOY_SERVICE_VERSION="1.0.0"

# ─── Signal & Error Handling ─────────────────────────────────────────────────

enable_error_tracing
enable_signal_handlers

# Track whether rollback was attempted
ROLLBACK_ATTEMPTED=false
ROLLBACK_EXIT=0

# Cleanup: ensure we report final status
_final_status() {
    if [[ "${ROLLBACK_ATTEMPTED}" == "true" ]]; then
        if [[ "${ROLLBACK_EXIT}" -eq 0 ]]; then
            log_warn "Deployment failed, but rollback succeeded. Service should be at previous state."
        else
            log_fatal "CRITICAL: Deployment failed AND rollback failed! Manual intervention required!"
        fi
    fi
}
register_cleanup "_final_status"

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
deploy-service.sh — Master Service Deployer v${DEPLOY_SERVICE_VERSION}

Usage: $(basename "$0") <service-name> <environment> <version>

Deploys a service to the specified environment, with preflight checks,
backup, health verification, and automatic rollback on failure.

Arguments:
  service-name   Name of the service to deploy (e.g. wheeler-api, revenue-api)
  environment    Target environment (production, staging, dev)
  version        Version tag to deploy (semver, git SHA, or 'latest')

Options:
  --force        Skip confirmation prompts
  --no-rollback  Do not attempt rollback on failure
  --dry-run      Show what would happen without making changes

Examples:
  $(basename "$0") wheeler-api production v2.5.0
  $(basename "$0") frontend-app staging latest --force
  $(basename "$0") ml-workers dev abc1234 --dry-run

Servers:
  EDGE NODE    Hostinger / 187.77.148.88  — Traefik, Nginx, frontend apps
  AIOPS NODE   Hetzner   / 5.78.140.118   — APIs, AI workers, PM2 services
  COREDB NODE  Hetzner   / 5.78.210.123   — PostgreSQL, Redis, MinIO, Qdrant
EOF
    exit 1
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

FORCE_DEPLOY=false
NO_ROLLBACK=false
DRY_RUN=false
SERVICE_NAME=""
ENVIRONMENT=""
VERSION=""

parse_args() {
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                FORCE_DEPLOY=true
                YES=true
                shift
                ;;
            --no-rollback)
                NO_ROLLBACK=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    SERVICE_NAME="${positional[0]:-}"
    ENVIRONMENT="${positional[1]:-}"
    VERSION="${positional[2]:-}"

    if [[ -z "${SERVICE_NAME}" ]]; then
        log_error "Missing required argument: <service-name>"
        usage
    fi
    if [[ -z "${ENVIRONMENT}" ]]; then
        log_error "Missing required argument: <environment>"
        usage
    fi
    if [[ -z "${VERSION}" ]]; then
        log_error "Missing required argument: <version>"
        usage
    fi
}

# ─── Service Type Detection ──────────────────────────────────────────────────

detect_service_type() {
    local svc="$1"
    local type=""

    # 1. Check service catalog first
    if command -v jq &>/dev/null; then
        type=$(get_service_runtime "$svc" 2>/dev/null || true)
    fi

    # 2. Auto-detect docker-compose files
    if [[ -z "$type" ]]; then
        if [[ -f "${WHEELER_BASE}/${svc}/docker-compose.yml" ]] || \
           [[ -f "${WHEELER_BASE}/${svc}/docker-compose.yaml" ]]; then
            type="docker"
        fi
    fi

    # 3. Auto-detect PM2 ecosystem files
    if [[ -z "$type" ]]; then
        if [[ -f "${WHEELER_BASE}/${svc}/ecosystem.config.js" ]] || \
           [[ -f "${WHEELER_BASE}/${svc}/ecosystem.config.json" ]] || \
           [[ -f "/etc/pm2/ecosystem.${svc}.config.js" ]]; then
            type="pm2"
        fi
    fi

    # 4. Check if it's a known PM2 process
    if [[ -z "$type" ]]; then
        if command -v pm2 &>/dev/null && pm2 jlist 2>/dev/null | jq -e ".[] | select(.name == \"${svc}\")" &>/dev/null; then
            type="pm2"
        fi
    fi

    # 5. Check if it's a known Docker container
    if [[ -z "$type" ]]; then
        if command -v docker &>/dev/null && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${svc}$"; then
            type="docker"
        fi
    fi

    # 6. Fallback: check for static files
    if [[ -z "$type" ]]; then
        if [[ -d "${WHEELER_BASE}/${svc}/public" ]] || [[ -d "${WHEELER_BASE}/${svc}/dist" ]]; then
            type="static"
        fi
    fi

    # 7. Still unknown
    if [[ -z "$type" ]]; then
        type="unknown"
    fi

    echo "$type"
}

# ─── Log Directory Setup ─────────────────────────────────────────────────────

SERVICE_LOG_FILE=""

setup_deploy_logging() {
    local svc="$1"
    local ts
    ts="$(timestamp_file)"
    local log_dir="${DEPLOY_LOG_DIR}/deploy/${svc}"

    mkdir -p "$log_dir"

    SERVICE_LOG_FILE="${log_dir}/${ts}.log"
    export SERVICE_LOG_FILE

    if [[ -n "${SERVICE_LOG_FILE:-}" ]] && [[ ! -f "$SERVICE_LOG_FILE" ]]; then
        : > "$SERVICE_LOG_FILE"
    fi

    log_info "Deploy log file: ${SERVICE_LOG_FILE}"
}

# ─── Dry Run Helpers ─────────────────────────────────────────────────────────

dry_run_msg() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "[DRY-RUN] $*"
        return 0
    fi
    return 1
}

# ─── Deploy Delegates ────────────────────────────────────────────────────────

deploy_docker_service() {
    local svc="$1"
    local env="$2"
    local tag="$3"

    local deploy_cmd="${SCRIPT_DIR}/deploy-docker-service.sh"
    if [[ ! -x "$deploy_cmd" ]]; then
        log_error "Docker deploy script not found or not executable: ${deploy_cmd}"
        return 1
    fi

    if dry_run_msg "Would run: ${deploy_cmd} ${svc} ${env} ${tag}"; then
        return 0
    fi

    "$deploy_cmd" "$svc" "$env" "$tag"
}

deploy_pm2_service() {
    local svc="$1"
    local env="$2"

    local deploy_cmd="${SCRIPT_DIR}/deploy-pm2-service.sh"
    if [[ ! -x "$deploy_cmd" ]]; then
        log_error "PM2 deploy script not found or not executable: ${deploy_cmd}"
        return 1
    fi

    if dry_run_msg "Would run: ${deploy_cmd} ${svc} ${env}"; then
        return 0
    fi

    "$deploy_cmd" "$svc" "$env"
}

deploy_static_service() {
    local svc="$1"
    local env="$2"
    local tag="$3"

    log_section "Static Service Deploy: ${svc} (${tag})"

    local src_dir="${WHEELER_BASE}/${svc}"
    if [[ ! -d "$src_dir" ]]; then
        log_error "Static service directory not found: ${src_dir}"
        return 1
    fi

    if dry_run_msg "Would deploy static files for ${svc} from ${src_dir}"; then
        return 0
    fi

    log_info "Static service deploy for ${svc}: no action required (served by reverse proxy)"
    return 0
}

# ─── Rollback Trigger ────────────────────────────────────────────────────────

trigger_rollback() {
    local svc="$1"
    local env="$2"

    if [[ "${NO_ROLLBACK}" == "true" ]]; then
        log_warn "Rollback disabled via --no-rollback flag. Skipping."
        return 1
    fi

    ROLLBACK_ATTEMPTED=true

    log_section "AUTO-ROLLBACK: ${svc} (${env})"

    local rollback_cmd="${SCRIPT_DIR}/rollback-deployment.sh"
    if [[ ! -x "$rollback_cmd" ]]; then
        log_error "Rollback script not found: ${rollback_cmd}"
        log_fatal "Cannot rollback! Manual intervention required."
        ROLLBACK_EXIT=1
        return 1
    fi

    if "$rollback_cmd" "$svc" "$env" --force; then
        log_success "Rollback completed successfully."
        ROLLBACK_EXIT=0
        return 0
    else
        log_fatal "Rollback FAILED! Manual intervention required."
        ROLLBACK_EXIT=1
        return 1
    fi
}

# ─── Preflight ───────────────────────────────────────────────────────────────

run_preflight() {
    local svc="$1"
    local env="$2"

    local preflight_cmd="${SCRIPT_DIR}/preflight-check.sh"
    if [[ ! -x "$preflight_cmd" ]]; then
        log_warn "Preflight script not found: ${preflight_cmd}. Skipping preflight checks."
        return 0
    fi

    log_section "Preflight Checks: ${svc} (${env})"

    if dry_run_msg "Would run: ${preflight_cmd} ${svc} ${env}"; then
        return 0
    fi

    if "$preflight_cmd" "$svc" "$env"; then
        log_success "Preflight checks passed."
        return 0
    else
        log_error "Preflight checks FAILED."
        return 1
    fi
}

# ─── Backup ──────────────────────────────────────────────────────────────────

run_backup() {
    local svc="$1"
    local env="$2"

    log_section "Pre-Deploy Backup: ${svc} (${env})"

    if dry_run_msg "Would run backup_configs for ${svc}"; then
        return 0
    fi

    backup_configs "$svc" "$env"
    return $?
}

# ─── Post-Deploy Health Check ────────────────────────────────────────────────

run_post_healthcheck() {
    local svc="$1"
    local env="$2"

    local hc_cmd="${SCRIPT_DIR}/post-deploy-healthcheck.sh"
    if [[ ! -x "$hc_cmd" ]]; then
        log_warn "Post-deploy healthcheck script not found: ${hc_cmd}. Skipping."
        return 0
    fi

    log_section "Post-Deploy Healthcheck: ${svc} (${env})"

    if dry_run_msg "Would run: ${hc_cmd} ${svc} ${env}"; then
        return 0
    fi

    if "$hc_cmd" "$svc" "$env" --timeout 60 --retries 10; then
        log_success "Post-deploy healthcheck PASSED."
        return 0
    else
        log_error "Post-deploy healthcheck FAILED."
        return 1
    fi
}

# ─── Verify Deployment ───────────────────────────────────────────────────────

run_verification() {
    local svc="$1"
    local env="$2"

    local verify_cmd="${SCRIPT_DIR}/verify-deployment.sh"
    if [[ ! -x "$verify_cmd" ]]; then
        log_warn "Verify script not found: ${verify_cmd}. Skipping."
        return 0
    fi

    log_section "Deployment Verification: ${svc} (${env})"

    if dry_run_msg "Would run: ${verify_cmd} ${svc} ${env}"; then
        return 0
    fi

    if "$verify_cmd" "$svc" "$env"; then
        log_success "Deployment verification PASSED."
        return 0
    else
        log_warn "Deployment verification returned warnings."
        return 0
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"

    local svc="$SERVICE_NAME"
    local env="$ENVIRONMENT"
    local version="$VERSION"

    # Validate inputs
    log_section "Deploy Service: ${svc} -> ${env} @ ${version}"
    log_kv "deploy_id" "$DEPLOY_ID"
    log_kv "service" "$svc"
    log_kv "environment" "$env"
    log_kv "version" "$version"
    log_kv "force" "$FORCE_DEPLOY"
    log_kv "no_rollback" "$NO_ROLLBACK"
    log_kv "dry_run" "$DRY_RUN"
    log_kv "node" "$(hostname -f 2>/dev/null || hostname)"

    validate_service_name "$svc" || exit 1
    validate_environment "$env" || exit 1
    validate_version "$version" || exit 1

    # Setup per-service logging
    setup_deploy_logging "$svc"

    # Detect service type
    local svc_type
    svc_type=$(detect_service_type "$svc")
    log_kv "service_type" "$svc_type"

    if [[ "$svc_type" == "unknown" ]]; then
        log_error "Could not determine service type for: ${svc}"
        log_error "Ensure the service has a docker-compose.yml, ecosystem.config.js, or is in the service catalog."
        exit 1
    fi

    # Confirmation for production
    if [[ "$env" == "production" ]]; then
        if [[ "$FORCE_DEPLOY" != "true" ]]; then
            confirm_action "Deploy ${svc} to PRODUCTION (version: ${version})" || exit 1
        else
            log_warn "Deploying to PRODUCTION with --force (confirmation bypassed)"
        fi
    fi

    # ─── Phase 1: Preflight ────────────────────────────────────────────────
    if ! run_preflight "$svc" "$env"; then
        log_fatal "Preflight checks failed. Deployment aborted."
        exit 2
    fi

    # ─── Phase 2: Backup ───────────────────────────────────────────────────
    if ! run_backup "$svc" "$env"; then
        log_warn "Backup had warnings but continuing. Manual backup may be needed."
    fi

    # ─── Phase 3: Deploy ───────────────────────────────────────────────────
    local deploy_result=0

    case "$svc_type" in
        docker)
            deploy_docker_service "$svc" "$env" "$version" || deploy_result=$?
            ;;
        pm2)
            deploy_pm2_service "$svc" "$env" || deploy_result=$?
            ;;
        static)
            deploy_static_service "$svc" "$env" "$version" || deploy_result=$?
            ;;
        systemd)
            log_warn "Systemd service deployment not fully automated. Restarting service..."
            if ! dry_run_msg "Would restart systemd service: ${svc}"; then
                sudo systemctl restart "$svc" 2>/dev/null || {
                    log_error "Failed to restart systemd service: ${svc}"
                    deploy_result=1
                }
            fi
            ;;
        *)
            log_error "Unhandled service type: ${svc_type}"
            deploy_result=1
            ;;
    esac

    if [[ "$deploy_result" -ne 0 ]]; then
        log_fatal "Deployment command failed (exit code: ${deploy_result})"
        if trigger_rollback "$svc" "$env"; then
            exit 3
        else
            exit 4
        fi
    fi

    # ─── Phase 4: Post-Deploy Health Check ─────────────────────────────────
    if ! run_post_healthcheck "$svc" "$env"; then
        log_fatal "Post-deploy healthcheck FAILED. Triggering rollback..."
        if trigger_rollback "$svc" "$env"; then
            exit 3
        else
            exit 4
        fi
    fi

    # ─── Phase 5: Verification ─────────────────────────────────────────────
    run_verification "$svc" "$env"

    # ─── Success ───────────────────────────────────────────────────────────
    log_section "DEPLOYMENT SUCCESSFUL"
    log_success "${svc} deployed to ${env} at version ${version}"

    send_health_alert "$svc" "$env" "OK" "Deployment successful: ${version} (${DEPLOY_ID})"

    exit 0
}

# ─── Entry Point ─────────────────────────────────────────────────────────────

main "$@"
