#!/usr/bin/env bash
# ==============================================================================
# restore-env.sh — Restore .env files from a deployment backup
# Usage: ./restore-env.sh <service-name> <environment> <backup-path>
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-rollback.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <service-name> <environment> <backup-path>

Restores .env files from a deployment backup. Preserves the current .env as
.env.failed-{timestamp} before restoring.

Arguments:
  service-name   Name of the service (e.g. api-gateway, litellm)
  environment    Target environment (e.g. production, staging)
  backup-path    Full path to the backup directory

Exit Codes:
  0  Restore completed successfully and validation passed
  1  Restore failed (env file missing from backup, validation error)
  2  Validation of the restored env failed
EOF
}

# ── Required Environment Variables per Service Type ─────────────────────────
# Format: associative-array-like mapping of service-name:env-name to required vars
declare -A REQUIRED_VARS

register_required_vars() {
    local key="$1"; shift
    REQUIRED_VARS["${key}"]="$*"
}

# API Gateway
register_required_vars "api-gateway:production" "PORT NODE_ENV DATABASE_URL REDIS_URL JWT_SECRET LOG_LEVEL"
register_required_vars "api-gateway:staging"    "PORT NODE_ENV DATABASE_URL JWT_SECRET LOG_LEVEL"

# LiteLLM
register_required_vars "litellm:production"     "LITELLM_PORT LITELLM_MASTER_KEY OPENAI_API_KEY DEEPSEEK_API_KEY DATABASE_URL"
register_required_vars "litellm:staging"        "LITELLM_PORT LITELLM_MASTER_KEY DATABASE_URL"

# AI Workers
register_required_vars "ai-worker:production"   "LITELLM_ENDPOINT LITELLM_API_KEY MODEL_NAME LOG_LEVEL"
register_required_vars "ai-worker:staging"      "LITELLM_ENDPOINT LITELLM_API_KEY MODEL_NAME LOG_LEVEL"

# OpenClaw
register_required_vars "openclaw:production"    "OPENCLAW_PORT DATABASE_URL AUTH_TOKEN"
register_required_vars "openclaw:staging"       "OPENCLAW_PORT DATABASE_URL AUTH_TOKEN"

# Registry helper
get_required_vars() {
    local service="$1"
    local env="$2"
    local key="${service}:${env}"
    echo "${REQUIRED_VARS[${key}]:-}"
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
    local env_file="/opt/services/${service_name}/.env"

    init_audit_log "${service_name}" "${environment}"
    audit_log "INFO" "restore-env.sh starting for ${service_name}/${environment}"

    log_info "Restoring .env for ${service_name}/${environment} from ${backup_path}"

    # ── 1. Validate backup path ──────────────────────────────────────────
    if [[ ! -d "${backup_path}" ]]; then
        log_error "Backup path does not exist: ${backup_path}"
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "Env restore - backup path not found: ${backup_path}"
        close_audit_log 1
        exit 1
    fi

    local backup_env="${backup_path}/env/${service_name}.env"
    if [[ ! -f "${backup_env}" ]]; then
        # Try alternate location
        backup_env="${backup_path}/${service_name}.env"
    fi
    if [[ ! -f "${backup_env}" ]]; then
        log_error "No .env file found in backup: searched ${backup_path}/env/ and ${backup_path}/"
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "Env restore - .env missing from backup"
        close_audit_log 1
        exit 1
    fi

    log_info "Backup env file: ${backup_env}"

    # ── 2. Preserve current .env as failed ───────────────────────────────
    local preserved
    if [[ -f "${env_file}" ]]; then
        preserved="$(preserve_failed_artifact "${env_file}" "env")"
        log_info "Current .env preserved."
        audit_log "INFO" "Preserved current .env as ${preserved}"
    else
        log_warn "No current .env file to preserve at ${env_file}"
        audit_log "WARN" "No current .env file at ${env_file}"
    fi

    # ── 3. Diff old vs restored (report changes only, no values) ─────────
    if [[ -f "${env_file}" ]] && [[ -f "${backup_env}" ]]; then
        log_info "=== Environment Variable Changes (keys only, values redacted) ==="

        # Extract keys from current env
        local current_keys
        current_keys="$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "${env_file}" 2>/dev/null \
            | cut -d= -f1 | sort -u || true)"

        # Extract keys from backup env
        local backup_keys
        backup_keys="$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "${backup_env}" 2>/dev/null \
            | cut -d= -f1 | sort -u || true)"

        # Added keys (in backup but not in current)
        local added
        added="$(comm -13 <(echo "${current_keys}") <(echo "${backup_keys}") || true)"
        if [[ -n "${added}" ]]; then
            log_info "  Added variables:"
            echo "${added}" | while IFS= read -r key; do
                [[ -z "${key}" ]] && continue
                log_info "    + ${key}"
                audit_log "DIFF" "ADDED: ${key}"
            done
        fi

        # Removed keys (in current but not in backup)
        local removed
        removed="$(comm -23 <(echo "${current_keys}") <(echo "${backup_keys}") || true)"
        if [[ -n "${removed}" ]]; then
            log_warn "  Removed variables:"
            echo "${removed}" | while IFS= read -r key; do
                [[ -z "${key}" ]] && continue
                log_warn "    - ${key}"
                audit_log "DIFF" "REMOVED: ${key}"
            done
        fi

        # Changed keys (in both, values differ)
        local common_keys
        common_keys="$(comm -12 <(echo "${current_keys}") <(echo "${backup_keys}") || true)"
        while IFS= read -r key; do
            [[ -z "${key}" ]] && continue
            local current_val backup_val
            # Use grep -m1 to get the first occurrence (avoids multi-line values)
            current_val="$(grep -m1 "^${key}=" "${env_file}" 2>/dev/null | cut -d= -f2- || true)"
            backup_val="$(grep -m1 "^${key}=" "${backup_env}" 2>/dev/null | cut -d= -f2- || true)"
            if [[ "${current_val}" != "${backup_val}" ]]; then
                log_info "  Changed: ${key} (value redacted)"
                audit_log "DIFF" "CHANGED: ${key}"
            fi
        done <<< "${common_keys}"
    fi

    # ── 4. Validate restored env syntax ──────────────────────────────────
    log_info "Validating restored env file syntax..."

    local syntax_ok=0
    local line_no=0
    while IFS= read -r line; do
        line_no=$((line_no + 1))
        [[ -z "${line}" ]] && continue
        # Skip comment lines
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        # Must match VAR=VALUE or VAR="VALUE" or VAR='VALUE' or export VAR=VALUE
        if ! [[ "${line}" =~ ^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=.*$ ]]; then
            log_warn "Syntax issue at line ${line_no}: ${line:0:80}"
            audit_log "WARN" "Env syntax issue line ${line_no}: ${line:0:80}"
            # Non-fatal warning
        fi
    done < "${backup_env}"

    # ── 5. Validate required variables ───────────────────────────────────
    local required_vars
    required_vars="$(get_required_vars "${service_name}" "${environment}")"

    if [[ -n "${required_vars}" ]]; then
        log_info "Checking required variables..."
        local missing_vars=()
        for var in ${required_vars}; do
            if ! grep -qE "^${var}=" "${backup_env}" 2>/dev/null; then
                missing_vars+=("${var}")
            fi
        done

        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            log_error "Missing required variables in restored env: ${missing_vars[*]}"
            audit_log "ERROR" "Missing required vars: ${missing_vars[*]}"
            send_rollback_alert "${service_name}" "${environment}" "FAILED" \
                "Env validation failed - missing required vars: ${missing_vars[*]}"
            close_audit_log 2
            exit 2
        fi
        log_success "All required variables present."
    else
        log_warn "No required variable definition found for ${service_name}:${environment}"
    fi

    # ── 6. Perform the restore ───────────────────────────────────────────
    log_info "Copying backup env to ${env_file}..."
    mkdir -p "$(dirname "${env_file}")"

    # Copy with restricted permissions
    cp "${backup_env}" "${env_file}"
    chmod 600 "${env_file}"
    log_success ".env restored to ${env_file}"

    audit_log "INFO" ".env restored from ${backup_env}"

    # ── 7. Log completion (never log values) ─────────────────────────────
    local var_count
    var_count="$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*=' "${env_file}" 2>/dev/null || echo 0)"
    log_info "Restored env contains ${var_count} variables."

    send_rollback_alert "${service_name}" "${environment}" "SUCCESS" \
        "Env restored successfully (${var_count} vars)"

    close_audit_log 0
    return 0
}

main "$@"
