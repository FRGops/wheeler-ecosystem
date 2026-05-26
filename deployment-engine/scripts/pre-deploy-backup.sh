#!/usr/bin/env bash
# =============================================================================
# pre-deploy-backup.sh — Backup-First Enforcement Gate
# =============================================================================
# Usage: ./pre-deploy-backup.sh <service-name>
#
# Mandatory pre-deployment backup gate. Called by deploy-service.sh BEFORE
# any deployment action. If this script cannot verify a backup, deployment
# MUST be aborted.
#
# Workflow:
#   1. Run `pm2 save` to snapshot current PM2 state
#   2. Backup service config from deployment-engine/services/<name>/
#   3. Create timestamped backup in /root/deployment-engine/backups/
#   4. Export current PM2 env for the service
#   5. Verify backup integrity (files exist, non-zero size)
#   6. Return exit 0 ONLY if backup is verified
#
# Exit Codes:
#   0  Backup created and verified
#   1  Backup failed (integrity check failed)
#   2  Invalid arguments
#   3  PM2 not available (warning, but can continue)
#   4  Backup directory not writable
# =============================================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly LOG_DIR="/root/deployment-engine/logs"
readonly LOG_FILE="${LOG_DIR}/backup.log"
readonly BACKUP_BASE="/root/deployment-engine/backups"
readonly SERVICES_DIR="/root/deployment-engine/services"

# ─── Logging ─────────────────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"

log_msg() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date +%Y%m%dT%H%M%S)"
    echo "[${ts}] [${level}] pre-deploy-backup: ${msg}" | tee -a "$LOG_FILE"
}

log_info()  { log_msg "INFO" "$@"; }
log_warn()  { log_msg "WARN" "$@"; }
log_error() { log_msg "ERROR" "$@"; }
log_ok()    { log_msg "OK" "$@"; }

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
pre-deploy-backup.sh — Backup-First Enforcement Gate

Usage: pre-deploy-backup.sh <service-name>

Creates a verified backup of the specified service configuration
and current PM2 state before any deployment action.

Arguments:
  service-name   Name of the service about to be deployed

Exit Codes:
  0  Backup created and verified — safe to proceed with deploy
  1  Backup FAILED — deploy MUST be aborted
  2  Invalid arguments
EOF
    exit 2
}

# ─── Preflight ───────────────────────────────────────────────────────────────

preflight() {
    local svc="$1"
    local issues=0

    log_info "Preflight checks for service: ${svc}"

    # Verify backup directory is writable
    if ! mkdir -p "$BACKUP_BASE" 2>/dev/null; then
        log_error "Cannot create backup directory: ${BACKUP_BASE}"
        return 1
    fi

    if [[ ! -w "$BACKUP_BASE" ]]; then
        log_error "Backup directory not writable: ${BACKUP_BASE}"
        return 1
    fi

    # Warn if service config directory does not exist
    if [[ ! -d "${SERVICES_DIR}/${svc}" ]]; then
        log_warn "Service config directory not found: ${SERVICES_DIR}/${svc}"
        log_warn "Will still backup PM2 state and proceed"
    fi

    return 0
}

# ─── PM2 State Snapshot ──────────────────────────────────────────────────────

snapshot_pm2_state() {
    local backup_dir="$1"

    if ! command -v pm2 &>/dev/null; then
        log_warn "PM2 not available — skipping PM2 state snapshot"
        return 0
    fi

    log_info "Snapshotting PM2 state via 'pm2 save'..."

    # Run pm2 save to update the dump file
    if pm2 save 2>/dev/null; then
        log_info "pm2 save: OK"
    else
        log_warn "pm2 save returned non-zero (may be OK if no processes)"
    fi

    # Copy the PM2 dump file
    local pm2_dump="${HOME}/.pm2/dump.pm2"
    if [[ -f "$pm2_dump" ]]; then
        cp -a "$pm2_dump" "${backup_dir}/pm2-dump.pm2"
        local dump_size
        dump_size=$(stat --format=%s "${backup_dir}/pm2-dump.pm2" 2>/dev/null || echo 0)
        log_info "PM2 dump backed up: ${dump_size} bytes"
    else
        log_warn "PM2 dump file not found at ${pm2_dump}"
    fi

    # Also export full PM2 list as JSON for human readability
    if command -v jq &>/dev/null; then
        pm2 jlist 2>/dev/null > "${backup_dir}/pm2-jlist.json" || true
        log_info "PM2 jlist exported to pm2-jlist.json"
    fi

    return 0
}

# ─── Service Config Backup ───────────────────────────────────────────────────

backup_service_config() {
    local svc="$1"
    local backup_dir="$2"
    local items=0

    log_info "Backing up service config for: ${svc}"

    local svc_dir="${SERVICES_DIR}/${svc}"
    if [[ ! -d "$svc_dir" ]]; then
        log_warn "No service config directory at ${svc_dir} — nothing to backup from services/"
        return 0
    fi

    # Copy the entire service config directory
    cp -a "$svc_dir" "${backup_dir}/service-config"
    items=$((items + 1))
    log_info "Copied service config directory: ${svc_dir}"

    # Also check for ecosystem configs
    if [[ -f "/etc/pm2/ecosystem.${svc}.config.js" ]]; then
        cp -a "/etc/pm2/ecosystem.${svc}.config.js" "${backup_dir}/ecosystem.${svc}.config.js"
        items=$((items + 1))
        log_info "Backed up ecosystem config: /etc/pm2/ecosystem.${svc}.config.js"
    fi

    log_info "Service config backup complete: ${items} items"
    return 0
}

# ─── PM2 Environment Export ──────────────────────────────────────────────────

export_pm2_env() {
    local svc="$1"
    local backup_dir="$2"

    if ! command -v pm2 &>/dev/null; then
        log_warn "PM2 not available — skipping env export"
        return 0
    fi

    log_info "Exporting PM2 environment for service: ${svc}"

    # Find the PM2 process ID/name for this service
    local pm2_id
    pm2_id=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name == \"${svc}\") | .pm2_env.pm_id" 2>/dev/null || true)

    if [[ -z "$pm2_id" || "$pm2_id" == "null" ]]; then
        log_warn "Service '${svc}' not found in PM2 process list — no env to export"
        # Still export full env list for context
        pm2 jlist 2>/dev/null > "${backup_dir}/pm2-full-jlist.json" 2>/dev/null || true
        return 0
    fi

    # Export the env for this specific PM2 process (secrets redacted)
    if pm2 env "$pm2_id" 2>/dev/null | sed -E 's/(KEY|SECRET|TOKEN|PASSWORD|CREDENTIALS)=.+/\\1=[REDACTED]/gi' > "${backup_dir}/pm2-env-${svc}.txt"; then
        local env_size
        env_size=$(stat --format=%s "${backup_dir}/pm2-env-${svc}.txt" 2>/dev/null || echo 0)
        log_info "PM2 env exported for ${svc} (pm_id=${pm2_id}, secrets redacted): ${env_size} bytes"
    else
        log_warn "pm2 env ${pm2_id} failed — may have no stored env"
        echo "PM2 env export failed for pm_id=${pm2_id}" > "${backup_dir}/pm2-env-${svc}.txt"
    fi

    return 0
}

# ─── Backup Integrity Verification ───────────────────────────────────────────

verify_backup_integrity() {
    local backup_dir="$1"
    local svc="$2"
    local errors=0

    log_info "Verifying backup integrity at: ${backup_dir}"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory does not exist: ${backup_dir}"
        return 1
    fi

    # Count all files in backup (recursive)
    local file_count
    file_count=$(find "$backup_dir" -type f | wc -l)
    log_info "Files in backup: ${file_count}"

    if [[ "$file_count" -eq 0 ]]; then
        log_error "Backup directory is EMPTY — no files backed up"
        return 1
    fi

    # Check every file for non-zero size (warn only on zero-size, error on missing)
    local zero_files=0
    while IFS= read -r -d '' file; do
        local size
        size=$(stat --format=%s "$file" 2>/dev/null || echo 0)
        if [[ "$size" -eq 0 ]]; then
            log_warn "Zero-size file: ${file}"
            zero_files=$((zero_files + 1))
        fi
        if [[ ! -f "$file" ]]; then
            log_error "File vanished during verification: ${file}"
            errors=$((errors + 1))
        fi
    done < <(find "$backup_dir" -type f -print0 2>/dev/null)

    if [[ "$zero_files" -gt 0 ]]; then
        log_warn "${zero_files} files have zero size — backup may be incomplete"
    fi

    # Generate checksums for verification traceability
    if command -v sha256sum &>/dev/null; then
        (cd "$backup_dir" && find . -type f -exec sha256sum {} \; > checksums.sha256 2>/dev/null) || true
        log_info "Checksums generated: checksums.sha256"
    fi

    # Write backup manifest
    cat > "${backup_dir}/BACKUP_MANIFEST.txt" <<MANIFEST
Backup Manifest
===============
Service:        ${svc}
Timestamp:      ${TIMESTAMP}
Backup Path:    ${backup_dir}
File Count:     ${file_count}
Zero-Size Files: ${zero_files}
Integrity:      ${errors}
Host:           $(hostname -f 2>/dev/null || hostname)
PM2 Online:     $(pm2 jlist 2>/dev/null | jq '[.[] | select(.pm2_env.status == "online")] | length' || echo "N/A")
PM2 Total:      $(pm2 jlist 2>/dev/null | jq 'length' || echo "N/A")
MANIFEST

    if [[ "$errors" -gt 0 ]]; then
        log_error "Backup integrity verification FAILED: ${errors} errors"
        return 1
    fi

    # Consider backup valid if at least 1 non-zero file exists
    local non_zero
    non_zero=$((file_count - zero_files))
    if [[ "$non_zero" -lt 1 ]]; then
        log_error "All backup files are zero-size — backup is invalid"
        return 1
    fi

    log_ok "Backup integrity VERIFIED: ${file_count} files, ${non_zero} non-zero"
    return 0
}

# ─── Summary ─────────────────────────────────────────────────────────────────

print_summary() {
    local svc="$1"
    local backup_dir="$2"
    local success="$3"

    log_info ""
    log_info "========== BACKUP SUMMARY =========="
    log_info "Service:     ${svc}"
    log_info "Timestamp:   ${TIMESTAMP}"
    log_info "Backup dir:  ${backup_dir}"
    log_info "Log file:    ${LOG_FILE}"

    if [[ -d "$backup_dir" ]]; then
        log_info "Contents:"
        find "$backup_dir" -type f -exec ls -lh {} \; 2>/dev/null | while read -r line; do
            log_info "  ${line}"
        done || true
    fi

    if [[ "$success" == "true" ]]; then
        log_ok "BACKUP VERIFIED — Safe to proceed with deployment"
    else
        log_error "BACKUP FAILED — Deployment MUST be aborted"
    fi
    log_info "======================================"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    local svc="${1:-}"

    if [[ -z "$svc" ]]; then
        log_error "Missing required argument: <service-name>"
        usage
    fi

    if [[ "$svc" == "--help" || "$svc" == "-h" ]]; then
        usage
    fi

    local backup_dir="${BACKUP_BASE}/${svc}-${TIMESTAMP}"

    log_info "========================================="
    log_info "Pre-Deploy Backup Gate — Started"
    log_info "Service:     ${svc}"
    log_info "Timestamp:   ${TIMESTAMP}"
    log_info "Backup dir:  ${backup_dir}"
    log_info "========================================="

    # Phase 0: Preflight
    if ! preflight "$svc"; then
        log_error "Preflight FAILED. Aborting."
        print_summary "$svc" "$backup_dir" "false"
        exit 4
    fi

    # Create backup directory
    mkdir -p "$backup_dir"

    # Phase 1: PM2 state snapshot
    if ! snapshot_pm2_state "$backup_dir"; then
        log_warn "PM2 state snapshot had issues, continuing..."
    fi

    # Phase 2: Service config backup
    backup_service_config "$svc" "$backup_dir"

    # Phase 3: PM2 env export
    export_pm2_env "$svc" "$backup_dir"

    # Phase 4: Verify integrity
    if verify_backup_integrity "$backup_dir" "$svc"; then
        print_summary "$svc" "$backup_dir" "true"
        exit 0
    else
        print_summary "$svc" "$backup_dir" "false"
        exit 1
    fi
}

main "$@"
