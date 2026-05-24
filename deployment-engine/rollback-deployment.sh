#!/usr/bin/env bash
# =============================================================================
# rollback-deployment.sh — Deployment Rollback (Delegates to Rollback Engine)
# =============================================================================
# Usage: ./rollback-deployment.sh <service-name> <environment> [--version <tag>]
#
# Wraps the rollback engine (/root/rollback-engine/rollback.sh) with:
#   - Deployment-engine-specific logging context
#   - Deploy ID tracking through the rollback
#   - Post-rollback health verification via verify-deployment.sh
#   - Consolidated audit trail in /var/log/wheeler/
#
# Exit Codes:
#   0  Rollback fully successful (including health verification)
#   1  Rollback engine reported failure
#   2  No backup found to rollback to
#   3  Invalid arguments
#   4  Post-rollback health verification failed
# =============================================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

readonly ROLLBACK_DEPLOY_VERSION="1.0.0"

# Path to the external rollback engine
readonly ROLLBACK_ENGINE_SCRIPT="/root/rollback-engine/rollback.sh"

# ─── Signal & Error Handling ─────────────────────────────────────────────────

enable_error_tracing
enable_signal_handlers

# Track rollback state for cleanup reporting
ROLLBACK_RESULT=""
ROLLBACK_START_TIME=""

_rollback_cleanup() {
    if [[ -n "${ROLLBACK_RESULT:-}" ]]; then
        local elapsed=""
        if [[ -n "${ROLLBACK_START_TIME:-}" ]]; then
            local now
            now=$(date +%s)
            elapsed=$((now - ROLLBACK_START_TIME))
        fi
        log_info "Rollback outcome: ${ROLLBACK_RESULT} (elapsed: ${elapsed:-unknown}s)"
    fi
}
register_cleanup "_rollback_cleanup"

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
rollback-deployment.sh — Deployment Rollback v${ROLLBACK_DEPLOY_VERSION}

Usage: $(basename "$0") <service-name> <environment> [OPTIONS]

Rolls back a service deployment to the most recent known-good backup.
Delegates to the rollback engine at ${ROLLBACK_ENGINE_SCRIPT}.

Arguments:
  service-name   Name of the service to roll back
  environment    Target environment (production, staging, dev)

Options:
  --version TAG  Roll back to a specific version tag (default: latest backup)
  --force        Skip confirmation prompts
  --dry-run      Show what would happen without making changes
  --no-verify    Skip post-rollback health verification

Examples:
  $(basename "$0") wheeler-api production
  $(basename "$0") changedetection staging --version v1.4.0 --force
  $(basename "$0") frontend-app dev --dry-run

Servers:
  EDGE NODE    Hostinger / 187.77.148.88  — Traefik, Nginx, frontend apps
  AIOPS NODE   Hetzner   / 5.78.140.118   — APIs, AI workers, PM2 services
  COREDB NODE  Hetzner   / 5.78.210.123   — PostgreSQL, Redis, MinIO, Qdrant
EOF
    exit 3
}

# ─── Argument Parsing ────────────────────────────────────────────────────────

VERSION_TAG=""
FORCE_MODE=false
DRY_RUN=false
NO_VERIFY=false
SERVICE_NAME=""
ENVIRONMENT=""

parse_args() {
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                VERSION_TAG="$2"
                shift 2
                ;;
            --force)
                FORCE_MODE=true
                YES=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-verify)
                NO_VERIFY=true
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

    if [[ -z "${SERVICE_NAME}" ]]; then
        log_error "Missing required argument: <service-name>"
        usage
    fi
    if [[ -z "${ENVIRONMENT}" ]]; then
        log_error "Missing required argument: <environment>"
        usage
    fi
}

# ─── Logging Context ─────────────────────────────────────────────────────────

setup_rollback_logging() {
    local svc="$1"
    local ts
    ts="$(timestamp_file)"
    local log_dir="${DEPLOY_LOG_DIR}/rollback/${svc}"
    mkdir -p "$log_dir"

    ROLLBACK_LOG_FILE="${log_dir}/${ts}.log"
    export ROLLBACK_LOG_FILE

    log_info "Rollback log: ${ROLLBACK_LOG_FILE}"

    # Also write to a common rollback audit log
    local audit_log="${DEPLOY_LOG_DIR}/rollback-audit.log"
    mkdir -p "$(dirname "$audit_log")"
    echo "$(timestamp_iso) | ROLLBACK_START | ${svc} | ${env} | deploy_id=${DEPLOY_ID} | version=${VERSION_TAG:-latest} | node=$(hostname -f 2>/dev/null || hostname)" >> "$audit_log"
}

write_audit_result() {
    local svc="$1"
    local env="$2"
    local result="$3"
    local audit_log="${DEPLOY_LOG_DIR}/rollback-audit.log"
    mkdir -p "$(dirname "$audit_log")"
    echo "$(timestamp_iso) | ROLLBACK_${result} | ${svc} | ${env} | deploy_id=${DEPLOY_ID}" >> "$audit_log"
}

# ─── Delegate to Rollback Engine ─────────────────────────────────────────────

delegate_to_rollback_engine() {
    local svc="$1"
    local env="$2"

    # Verify the rollback engine exists and is executable
    if [[ ! -x "$ROLLBACK_ENGINE_SCRIPT" ]]; then
        log_error "Rollback engine script not found or not executable: ${ROLLBACK_ENGINE_SCRIPT}"
        log_error "Expected at: ${ROLLBACK_ENGINE_SCRIPT}"
        return 1
    fi

    log_section "Delegating to Rollback Engine"
    log_kv "rollback_engine" "$ROLLBACK_ENGINE_SCRIPT"
    log_kv "rollback_engine_version" "$(head -20 "$ROLLBACK_ENGINE_SCRIPT" | grep 'readonly ROLLBACK_VERSION' | cut -d'"' -f2 || echo 'unknown')"

    # Build the command
    local cmd=("$ROLLBACK_ENGINE_SCRIPT" "$svc" "$env")

    if [[ -n "${VERSION_TAG:-}" ]]; then
        cmd+=("--version" "$VERSION_TAG")
    fi
    if [[ "$FORCE_MODE" == "true" ]]; then
        cmd+=("--force")
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        cmd+=("--dry-run")
    fi

    log_info "Executing: ${cmd[*]}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY-RUN] Would execute: ${cmd[*]}"
        return 0
    fi

    # Execute the rollback engine
    local rollback_exit_code=0
    "${cmd[@]}" || rollback_exit_code=$?

    case "$rollback_exit_code" in
        0)
            log_success "Rollback engine completed successfully."
            ROLLBACK_RESULT="SUCCESS"
            return 0
            ;;
        1)
            log_error "Rollback engine reported failure (exit code 1)."
            ROLLBACK_RESULT="FAILED"
            return 1
            ;;
        2)
            log_error "Rollback engine: no backup found (exit code 2)."
            ROLLBACK_RESULT="NO_BACKUP"
            return 2
            ;;
        *)
            log_error "Rollback engine exited with unexpected code: ${rollback_exit_code}"
            ROLLBACK_RESULT="UNKNOWN(${rollback_exit_code})"
            return 1
            ;;
    esac
}

# ─── Post-Rollback Health Verification ───────────────────────────────────────

verify_rollback_health() {
    local svc="$1"
    local env="$2"

    if [[ "$NO_VERIFY" == "true" ]]; then
        log_warn "Post-rollback health verification skipped (--no-verify)."
        return 0
    fi

    log_section "Post-Rollback Health Verification"

    local verify_cmd="${SCRIPT_DIR}/verify-deployment.sh"
    if [[ ! -x "$verify_cmd" ]]; then
        log_warn "Verify script not found: ${verify_cmd}. Skipping health verification."
        return 0
    fi

    log_info "Running deployment verification after rollback..."

    # Allow a brief startup grace period for the service
    local grace="${DEFAULT_STARTUP_GRACE:-10}"
    log_info "Waiting ${grace}s for service stabilization..."
    sleep "$grace"

    if "$verify_cmd" "$svc" "$env"; then
        log_success "Post-rollback health verification PASSED."
        return 0
    else
        log_fatal "Post-rollback health verification FAILED!"
        log_fatal "Service may still be unhealthy after rollback!"
        return 1
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"

    local svc="$SERVICE_NAME"
    local env="$ENVIRONMENT"

    ROLLBACK_START_TIME=$(date +%s)

    log_section "Rollback Deployment: ${svc} -> ${env}"
    log_kv "deploy_id" "$DEPLOY_ID"
    log_kv "service" "$svc"
    log_kv "environment" "$env"
    log_kv "version_tag" "${VERSION_TAG:-latest}"
    log_kv "force" "$FORCE_MODE"
    log_kv "dry_run" "$DRY_RUN"
    log_kv "no_verify" "$NO_VERIFY"
    log_kv "rollback_engine" "$ROLLBACK_ENGINE_SCRIPT"
    log_kv "node" "$(hostname -f 2>/dev/null || hostname)"

    # Validate inputs
    validate_service_name "$svc" || exit 3
    validate_environment "$env" || exit 3
    if [[ -n "${VERSION_TAG:-}" ]]; then
        validate_version "$VERSION_TAG" || exit 3
    fi

    # Setup logging context
    setup_rollback_logging "$svc"

    # Confirmation for production rollbacks
    if [[ "$env" == "production" ]] && [[ "$FORCE_MODE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        log_warn "=============================================="
        log_warn "  PRODUCTION ROLLBACK: ${svc}"
        log_warn "  Version: ${VERSION_TAG:-latest backup}"
        log_warn "  Node:    $(hostname -f 2>/dev/null || hostname)"
        log_warn "=============================================="
        confirm_action "Rollback PRODUCTION service '${svc}' to previous version?" || exit 1
    fi

    # ─── Step 1: Delegate to Rollback Engine ────────────────────────────────
    local rollback_result=0
    delegate_to_rollback_engine "$svc" "$env" || rollback_result=$?

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run complete. No changes were made."
        exit 0
    fi

    # Audit: log the result from the rollback engine
    case "$rollback_result" in
        0) write_audit_result "$svc" "$env" "SUCCESS" ;;
        1) write_audit_result "$svc" "$env" "FAILED" ;;
        2) write_audit_result "$svc" "$env" "NO_BACKUP" ;;
        *) write_audit_result "$svc" "$env" "UNKNOWN($rollback_result)" ;;
    esac

    # If rollback engine failed, don't proceed to verification
    if [[ "$rollback_result" -ne 0 ]]; then
        log_fatal "Rollback engine did not complete successfully. Aborting."

        # Send alert
        send_health_alert "$svc" "$env" "CRITICAL" \
            "Rollback FAILED (exit=${rollback_result}). Service may be in unknown state!"

        exit "$rollback_result"
    fi

    # ─── Step 2: Post-Rollback Health Verification ──────────────────────────
    if ! verify_rollback_health "$svc" "$env"; then
        write_audit_result "$svc" "$env" "VERIFY_FAILED"

        send_health_alert "$svc" "$env" "CRITICAL" \
            "Rollback completed but post-rollback health verification FAILED!"

        exit 4
    fi

    write_audit_result "$svc" "$env" "VERIFIED"

    # ─── Success ───────────────────────────────────────────────────────────
    log_section "ROLLBACK SUCCESSFUL"
    log_success "${svc} has been rolled back successfully in ${env}."
    log_kv "deploy_id" "$DEPLOY_ID"
    log_kv "rollback_engine" "$ROLLBACK_ENGINE_SCRIPT"

    send_health_alert "$svc" "$env" "WARNING" \
        "Rollback completed and verified. Service restored to previous version."

    exit 0
}

# ─── Entry Point ─────────────────────────────────────────────────────────────

main "$@"
