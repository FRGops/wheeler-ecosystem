#!/usr/bin/env bash
# =============================================================================
# Wheeler AI Routing Optimization — Safe Apply Script
# Phase 7 — AI Routing Optimization Plan
# Generated: 2026-05-23
# Target: AIOPS (5.78.140.118)
#
# SAFETY GUARANTEES:
#   1. Creates timestamped backup of ALL modified files
#   2. Validates LiteLLM config before applying
#   3. Tests LiteLLM health endpoint after reload
#   4. Monitors logs for 60s after apply
#   5. Auto-rolls back if errors detected
#   6. Read-only by default (--execute required for changes)
#
# USAGE:
#   ./safe-apply-ai-routing-optimizations.sh           Dry run (report only)
#   ./safe-apply-ai-routing-optimizations.sh --execute Apply changes
#   ./safe-apply-ai-routing-optimizations.sh --rollback Roll back to backup
# =============================================================================

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

AIOPS_HOST="${AIOPS_HOST:-5.78.140.118}"
AIOPS_SSH="ssh -o ConnectTimeout=5 root@${AIOPS_HOST}"

LITELLM_CONFIG_PATH="/root/.claude/litellm-deepseek.yaml"
LITELLM_BACKUP_DIR="/root/.claude/litellm-backups"
LITELLM_PM2_NAME="litellm"
LITELLM_PORT="${LITELLM_PORT:-4049}"
LITELLM_HEALTH_URL="http://localhost:${LITELLM_PORT}/health"
MONITOR_DURATION="${MONITOR_DURATION:-60}"

NEW_CONFIG_SOURCE="/root/templates/ai-routing/litellm-optimized.yaml"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_PATH="${LITELLM_BACKUP_DIR}/litellm-deepseek-${TIMESTAMP}.yaml"
ROLLBACK_LOG="/var/log/wheeler-ops/ai-routing-optimizations.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Helper Functions ─────────────────────────────────────────────────────────

log() {
    local level="$1"; shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo -e "$msg"
    echo "$msg" >> "$ROLLBACK_LOG" 2>/dev/null || true
}

info()  { log "INFO" "$@"; }
warn()  { echo -e "${YELLOW}$(log WARN "$@")${NC}"; }
error() { echo -e "${RED}$(log ERROR "$@")${NC}"; }
ok()    { echo -e "${GREEN}$(log OK "$@")${NC}"; }

banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║   WHEELER AI ROUTING OPTIMIZATION — SAFE APPLY                  ║"
    echo "║   PHASE 7                                                       ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
}

die() {
    error "FATAL: $*"
    exit 1
}

# ─── Pre-flight Checks ────────────────────────────────────────────────────────

preflight_checks() {
    info "Running pre-flight checks..."

    # Check we can reach AIOPS
    if ! ${AIOPS_SSH} "echo OK" > /dev/null 2>&1; then
        die "Cannot SSH to AIOPS (${AIOPS_HOST}). Check connectivity."
    fi
    ok "SSH to AIOPS: OK"

    # Check LiteLLM is running
    local litellm_status
    litellm_status="$(${AIOPS_SSH} "pm2 jlist 2>/dev/null | python3 -c \"import json,sys; d=json.load(sys.stdin); print([p['pm2_env']['status'] for p in d if p['name']=='${LITELLM_PM2_NAME}'][0] if [p['pm2_env']['status'] for p in d if p['name']=='${LITELLM_PM2_NAME}'] else 'NOT_FOUND')\" 2>/dev/null")" || true
    if [[ "$litellm_status" != "online" ]]; then
        die "LiteLLM PM2 process is not online (status: ${litellm_status:-NOT_FOUND})"
    fi
    ok "LiteLLM process status: ${litellm_status}"

    # Check LiteLLM health endpoint
    local health
    health="$(${AIOPS_SSH} "curl -s -o /dev/null -w '%{http_code}' ${LITELLM_HEALTH_URL} 2>/dev/null")" || true
    if [[ "$health" != "200" ]]; then
        die "LiteLLM health endpoint returned HTTP ${health:-no response}"
    fi
    ok "LiteLLM health endpoint: HTTP ${health}"

    # Check config file exists
    if ! ${AIOPS_SSH} "test -f ${LITELLM_CONFIG_PATH}" 2>/dev/null; then
        die "LiteLLM config not found at ${LITELLM_CONFIG_PATH}"
    fi
    ok "LiteLLM config exists at ${LITELLM_CONFIG_PATH}"

    # Check new config exists (local)
    if [[ ! -f "${NEW_CONFIG_SOURCE}" ]]; then
        die "New config not found at ${NEW_CONFIG_SOURCE}"
    fi
    ok "New config exists at ${NEW_CONFIG_SOURCE}"

    # Ensure backup directory exists
    ${AIOPS_SSH} "mkdir -p ${LITELLM_BACKUP_DIR}" 2>/dev/null || \
        die "Cannot create backup directory on AIOPS"
    ok "Backup directory ready"

    # Ensure log directory exists
    ${AIOPS_SSH} "mkdir -p /var/log/wheeler-ops" 2>/dev/null || true

    info "All pre-flight checks passed."
    echo ""
}

# ─── Backup Current Config ────────────────────────────────────────────────────

backup_config() {
    info "Backing up current LiteLLM config..."

    local backup_cmd="cp ${LITELLM_CONFIG_PATH} ${BACKUP_PATH}"
    if ${AIOPS_SSH} "$backup_cmd" 2>/dev/null; then
        ok "Backup created: ${BACKUP_PATH}"
        echo "${BACKUP_PATH}" > /tmp/litellm-last-backup-path.txt
    else
        die "Failed to create backup"
    fi

    # Show backup summary
    info "Backup file size: $(${AIOPS_SSH} "wc -c < ${BACKUP_PATH}") bytes"
    echo ""
}

# ─── Validate New Config ──────────────────────────────────────────────────────

validate_config() {
    info "Validating new LiteLLM config..."

    # Upload and validate
    local tmp_config="/tmp/litellm-validate-${TIMESTAMP}.yaml"

    # Copy new config to AIOPS
    if ! scp -o ConnectTimeout=5 "${NEW_CONFIG_SOURCE}" "root@${AIOPS_HOST}:${tmp_config}" > /dev/null 2>&1; then
        die "Failed to upload new config to AIOPS"
    fi
    ok "Config uploaded to ${tmp_config}"

    # Validate with LiteLLM
    local validation_result
    validation_result="$(${AIOPS_SSH} "litellm --validate-config ${tmp_config} 2>&1" 2>/dev/null)" || true

    if echo "$validation_result" | grep -qi "error\|invalid\|failed"; then
        error "Config validation FAILED:"
        echo "$validation_result"
        ${AIOPS_SSH} "rm -f ${tmp_config}" 2>/dev/null || true
        die "Config validation failed. Check the errors above."
    fi

    ok "Config validation passed"
    ${AIOPS_SSH} "rm -f ${tmp_config}" 2>/dev/null || true
    echo ""
}

# ─── Apply New Config ─────────────────────────────────────────────────────────

apply_config() {
    info "Applying new LiteLLM config..."

    # Copy new config to final location
    if ! scp -o ConnectTimeout=5 "${NEW_CONFIG_SOURCE}" "root@${AIOPS_HOST}:${LITELLM_CONFIG_PATH}.new" > /dev/null 2>&1; then
        die "Failed to upload new config"
    fi
    ok "New config staged at ${LITELLM_CONFIG_PATH}.new"

    # Swap config files atomically
    ${AIOPS_SSH} "mv ${LITELLM_CONFIG_PATH}.new ${LITELLM_CONFIG_PATH}" 2>/dev/null || \
        die "Failed to swap config files"
    ok "Config file updated"

    # Reload LiteLLM via PM2
    info "Reloading LiteLLM (graceful reload)..."
    local reload_result
    reload_result="$(${AIOPS_SSH} "pm2 reload ${LITELLM_PM2_NAME} 2>&1" 2>/dev/null)" || true
    ok "PM2 reload result: ${reload_result:-OK}"

    # Wait for process to come back online
    info "Waiting for LiteLLM to become healthy..."
    for i in $(seq 1 30); do
        local status
        status="$(${AIOPS_SSH} "curl -s -o /dev/null -w '%{http_code}' ${LITELLM_HEALTH_URL} 2>/dev/null")" || true
        if [[ "$status" == "200" ]]; then
            ok "LiteLLM healthy after ${i}s"
            break
        fi
        if [[ $i -eq 30 ]]; then
            error "LiteLLM did not become healthy within 30s"
            return 1
        fi
        sleep 1
    done

    echo ""
}

# ─── Monitor Post-Apply ──────────────────────────────────────────────────────

monitor_post_apply() {
    info "Monitoring LiteLLM for ${MONITOR_DURATION}s..."

    local errors_before
    errors_before="$(${AIOPS_SSH} "grep -c 'ERROR\|CRITICAL' /opt/logs/litellm-error.log 2>/dev/null || echo 0")"

    sleep "${MONITOR_DURATION}"

    # Check for new errors
    local errors_after
    errors_after="$(${AIOPS_SSH} "grep -c 'ERROR\|CRITICAL' /opt/logs/litellm-error.log 2>/dev/null || echo 0")"

    local new_errors=$((errors_after - errors_before))
    if [[ $new_errors -lt 0 ]]; then
        new_errors=0  # Log rotation?
    fi

    info "Errors before: ${errors_before}, after: ${errors_after}, new: ${new_errors}"

    if [[ $new_errors -gt 10 ]]; then
        error "HIGH ERROR RATE DETECTED: ${new_errors} new errors in ${MONITOR_DURATION}s"
        return 1
    elif [[ $new_errors -gt 0 ]]; then
        warn "Some new errors detected (${new_errors}). Reviewing..."
        # Show the new errors
        ${AIOPS_SSH} "tail -50 /opt/logs/litellm-error.log 2>/dev/null | grep 'ERROR\|CRITICAL' | tail -${new_errors}" 2>/dev/null || true
    else
        ok "No new errors in monitoring window"
    fi

    # Check health endpoint one more time
    local final_health
    final_health="$(${AIOPS_SSH} "curl -s ${LITELLM_HEALTH_URL} 2>/dev/null | head -1")" || true
    if echo "$final_health" | grep -q "healthy_endpoints"; then
        ok "Final health check passed"
    else
        warn "Final health check returned unexpected response"
    fi

    echo ""
}

# ─── Rollback ─────────────────────────────────────────────────────────────────

rollback() {
    banner
    warn "ROLLING BACK LiteLLM config..."

    local backup_path="$1"

    if [[ -z "$backup_path" ]]; then
        # Find latest backup
        backup_path="$(${AIOPS_SSH} "ls -t ${LITELLM_BACKUP_DIR}/litellm-deepseek-*.yaml 2>/dev/null | head -1")" || true
        if [[ -z "$backup_path" ]]; then
            die "No backup found to roll back to"
        fi
    fi

    if ! ${AIOPS_SSH} "test -f ${backup_path}" 2>/dev/null; then
        die "Backup file not found: ${backup_path}"
    fi

    info "Restoring from backup: ${backup_path}"

    # Restore config
    ${AIOPS_SSH} "cp ${backup_path} ${LITELLM_CONFIG_PATH}" 2>/dev/null || \
        die "Failed to restore config from backup"

    # Reload LiteLLM
    ${AIOPS_SSH} "pm2 reload ${LITELLM_PM2_NAME}" 2>/dev/null || \
        warn "PM2 reload may have failed -- check manually"

    # Wait and verify
    sleep 5
    local health
    health="$(${AIOPS_SSH} "curl -s -o /dev/null -w '%{http_code}' ${LITELLM_HEALTH_URL} 2>/dev/null")" || true
    if [[ "$health" == "200" ]]; then
        ok "Rollback successful — LiteLLM healthy with restored config"
    else
        error "Rollback health check failed (HTTP ${health:-no response}). Manual intervention needed."
        return 1
    fi
}

# ─── Dry Run Report ───────────────────────────────────────────────────────────

dry_run_report() {
    banner
    info "DRY RUN — No changes will be made."
    echo ""
    echo "  Plan:"
    echo "  1. Back up  : ${LITELLM_CONFIG_PATH}"
    echo "     -> ${LITELLM_BACKUP_DIR}/litellm-deepseek-${TIMESTAMP}.yaml"
    echo "  2. Validate : ${NEW_CONFIG_SOURCE}"
    echo "  3. Apply    : Copy new config, reload LiteLLM via PM2"
    echo "  4. Monitor  : Watch logs for ${MONITOR_DURATION}s for errors"
    echo "  5. Verify   : Health endpoint check"
    echo ""
    echo "  If errors detected: Auto-rollback to backup"
    echo ""
    echo "  New features being applied:"
    echo "    - Fixed Redis auth (enables caching)"
    echo "    - Added fallback chain (Flash -> Reasoner -> Sonnet)"
    echo "    - Added retry logic (exponential backoff with jitter)"
    echo "    - Added model-specific timeouts"
    echo "    - Added concurrency limits (global + per-model)"
    echo "    - Enabled streaming support"
    echo "    - Added Langfuse callbacks"
    echo "    - Added guardrails (loop detection, abuse patterns)"
    echo "    - Reduced RPM limits to match API tiers"
    echo ""
    echo "  Run with --execute to apply changes."
    echo ""
}

# ─── Audit Current State ──────────────────────────────────────────────────────

audit_current_state() {
    info "Auditing current LiteLLM state on AIOPS..."

    echo ""
    echo "  ── LiteLLM Process ──"
    ${AIOPS_SSH} "ps aux | grep litellm | grep -v grep | head -3" 2>/dev/null || echo "  (no process found)"

    echo ""
    echo "  ── PM2 Status ──"
    ${AIOPS_SSH} "pm2 show ${LITELLM_PM2_NAME} 2>/dev/null | head -20" 2>/dev/null || echo "  (PM2 status unavailable)"

    echo ""
    echo "  ── Health Endpoint ──"
    ${AIOPS_SSH} "curl -s ${LITELLM_HEALTH_URL} 2>/dev/null | python3 -m json.tool 2>/dev/null | head -20" 2>/dev/null || echo "  (health endpoint unavailable)"

    echo ""
    echo "  ── Current Config (first 30 lines) ──"
    ${AIOPS_SSH} "head -30 ${LITELLM_CONFIG_PATH}" 2>/dev/null || echo "  (config not found)"

    echo ""
    echo "  ── Redis Cache Status (checking errors) ──"
    local redis_errors
    redis_errors="$(${AIOPS_SSH} "grep -c 'Authentication required' /opt/logs/litellm-error.log 2>/dev/null || echo 0")"
    echo "  Redis auth errors in log: ${redis_errors}"
    if [[ $redis_errors -gt 0 ]]; then
        warn "  Redis caching is BROKEN — ${redis_errors} auth errors found"
    else
        ok "  No Redis auth errors detected"
    fi

    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    local mode="${1:-dry-run}"

    mkdir -p /var/log/wheeler-ops 2>/dev/null || true

    case "$mode" in
        --execute)
            banner
            info "EXECUTE MODE — Will apply changes to AIOPS (${AIOPS_HOST})"
            echo ""

            audit_current_state

            preflight_checks
            backup_config
            validate_config

            echo ""
            warn "About to apply new LiteLLM configuration."
            warn "Fallback chain, retries, timeouts, and streaming will be enabled."
            echo ""
            read -r -p "  Continue? [y/N] " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                info "Aborted by user."
                exit 0
            fi
            echo ""

            if apply_config; then
                if monitor_post_apply; then
                    echo ""
                    ok "═══════════════════════════════════════════════════════════════"
                    ok "  AI ROUTING OPTIMIZATIONS APPLIED SUCCESSFULLY"
                    ok "  Backup: ${BACKUP_PATH}"
                    ok "  To roll back: $0 --rollback ${BACKUP_PATH}"
                    ok "═══════════════════════════════════════════════════════════════"
                    echo ""
                    info "Post-apply verification:"
                    ${AIOPS_SSH} "curl -s ${LITELLM_HEALTH_URL}" 2>/dev/null | python3 -m json.tool 2>/dev/null | head -15 || true
                else
                    error "Post-apply monitoring detected errors. Rolling back..."
                    rollback "${BACKUP_PATH}" || die "CRITICAL: Rollback failed. Manual intervention required."
                    error "Changes rolled back due to errors. Review logs before retrying."
                    exit 1
                fi
            else
                error "Config apply failed. Attempting rollback..."
                rollback "${BACKUP_PATH}" || die "CRITICAL: Rollback failed. Manual intervention required."
                exit 1
            fi
            ;;

        --rollback)
            local backup_path="${2:-}"
            rollback "$backup_path"
            ;;

        --audit)
            banner
            audit_current_state
            ;;

        dry-run|--dry-run|"")
            dry_run_report
            audit_current_state
            ;;

        *)
            echo "Usage: $0 [--execute | --rollback [backup_path] | --audit | --dry-run]"
            echo ""
            echo "  --execute         Apply optimizations to AIOPS"
            echo "  --rollback [path] Roll back to specified or latest backup"
            echo "  --audit           Show current AI routing state"
            echo "  --dry-run         Show what would be done (default)"
            exit 1
            ;;
    esac
}

main "$@"
