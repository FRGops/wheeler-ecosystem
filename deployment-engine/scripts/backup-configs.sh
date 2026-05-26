#!/usr/bin/env bash
# =============================================================================
# backup-configs.sh — Configuration Backup for Wheeler Ecosystem
# =============================================================================
# Backs up:
#   1. /root/deployment-engine/ configs, scripts, state
#   2. /root/wheeler-command-center/ configs, bin, inventory, dashboards
#   3. PM2 process list snapshot (pm2 save)
#   4. Ecosystem config files
#   5. Claude configs
# Output: /root/backups/configs/configs-<timestamp>.tar.gz
# Retention: last 14 daily config backups
# Log: /root/backups/configs/backup.log
# =============================================================================
set -o pipefail
set -o nounset

readonly BACKUP_ROOT="/root/backups/configs"
readonly TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
readonly BACKUP_FILE="${BACKUP_ROOT}/configs-${TIMESTAMP}.tar.gz"
readonly RETENTION_KEEP=14

# ---- Paths to back up ----
readonly SOURCES=(
    "/root/deployment-engine"
    "/root/wheeler-command-center"
    "/root/scripts"
    "/root/infrastructure"
)

# ---- Exclusion patterns for tar ----
readonly EXCLUDE_PATTERNS=(
    "node_modules"
    ".git"
    "__pycache__"
    "*.pyc"
    ".npm"
    ".cache"
    "logs"
    "*.log"
    "backups"
)

# ---- Logging ----
log_file="${BACKUP_ROOT}/backup.log"
log() {
    local level="$1"; shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "${msg}" | tee -a "${log_file}"
}
log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# ---- Setup ----
setup() {
    mkdir -p "${BACKUP_ROOT}"
    # Rotate log if >1MB
    if [[ -f "${log_file}" ]] && [[ "$(stat -c%s "${log_file}" 2>/dev/null || echo 0)" -gt 1048576 ]]; then
        mv "${log_file}" "${log_file}.old"
    fi
    touch "${log_file}"
    log_info "=============================================="
    log_info "Configuration Backup Started"
    log_info "Backup root: ${BACKUP_ROOT}"
    log_info "Output file: ${BACKUP_FILE}"
    log_info "=============================================="
}

# ---- Build tar exclude args ----
build_excludes() {
    local args=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        args+=(--exclude="${pattern}")
    done
    echo "${args[@]}"
}

# ---- PM2 snapshot save ----
backup_pm2_snapshot() {
    log_info "Saving PM2 process list snapshot..."

    local pm2_dir="${BACKUP_ROOT}/pm2-${TIMESTAMP}"
    mkdir -p "${pm2_dir}"

    # Save PM2 process list
    if pm2 save --force 2>/dev/null; then
        log_info "PM2 save successful"
    else
        log_warn "pm2 save failed — daemon may not be running"
    fi

    # Copy dump.pm2 if it exists
    if [[ -f /root/.pm2/dump.pm2 ]]; then
        cp /root/.pm2/dump.pm2 "${pm2_dir}/dump.pm2"
        log_info "Copied PM2 dump.pm2"
    else
        log_warn "/root/.pm2/dump.pm2 not found"
    fi

    # Copy ecosystem configs
    local ecosystem_files
    ecosystem_files=$(find /root /opt -maxdepth 4 \( -name "ecosystem.config.js" -o -name "ecosystem.config.cjs" -o -name "ecosystem.*.config.js" \) 2>/dev/null || true)
    if [[ -n "${ecosystem_files}" ]]; then
        while IFS= read -r ef; do
            local safe_name
            safe_name="$(echo "${ef#/}" | tr '/' '_')"
            cp "${ef}" "${pm2_dir}/${safe_name}"
            log_info "Copied ecosystem config: ${ef}"
        done <<< "${ecosystem_files}"
    fi
}

# ---- Create config tar.gz ----
create_config_archive() {
    log_info "Creating configuration archive..."

    local excludes
    excludes=$(build_excludes)

    # Build list of existing source dirs
    local existing_sources=()
    for src in "${SOURCES[@]}"; do
        if [[ -d "${src}" ]] || [[ -f "${src}" ]]; then
            existing_sources+=("${src}")
            log_info "  Including: ${src}"
        else
            log_warn "  Source not found, skipping: ${src}"
        fi
    done

    if [[ ${#existing_sources[@]} -eq 0 ]]; then
        log_error "No source directories found to back up"
        return 1
    fi

    # shellcheck disable=SC2086
    if tar -czf "${BACKUP_FILE}" ${excludes} "${existing_sources[@]}" 2>>"${log_file}"; then
        local size
        size="$(du -h "${BACKUP_FILE}" | cut -f1)"
        log_info "SUCCESS: Config archive created (${size})"
        return 0
    else
        log_error "tar command failed"
        return 1
    fi
}

# ---- Verify archive integrity ----
verify_archive() {
    log_info "Verifying archive integrity..."
    if gunzip -t "${BACKUP_FILE}" 2>/dev/null; then
        if tar -tzf "${BACKUP_FILE}" >/dev/null 2>&1; then
            local file_count
            file_count=$(tar -tzf "${BACKUP_FILE}" 2>/dev/null | wc -l)
            log_info "Archive verified: ${file_count} entries"
            return 0
        fi
    fi
    log_error "Archive verification FAILED"
    return 1
}

# ---- Retention cleanup ----
apply_retention() {
    log_info "Applying retention: keep last ${RETENTION_KEEP} config backups"

    local files
    mapfile -t files < <(find "${BACKUP_ROOT}" -maxdepth 1 -name 'configs-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    local count=0
    for f in "${files[@]}"; do
        count=$((count + 1))
        if [[ ${count} -gt ${RETENTION_KEEP} ]]; then
            log_info "  REMOVE (past retention): $(basename "${f}")"
            rm -f "${f}"
        fi
    done

    # Clean up old PM2 snapshot dirs (>30 days)
    find "${BACKUP_ROOT}" -maxdepth 1 -name 'pm2-*' -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null || true

    log_info "Retention cleanup complete. Keeping ${count} backups (limit: ${RETENTION_KEEP})"
}

# ---- Main ----
main() {
    local overall_ok=true

    setup

    # 1. PM2 snapshot
    log_info "PHASE 1: PM2 Snapshot"
    if ! backup_pm2_snapshot; then
        log_warn "PM2 snapshot had warnings — continuing"
    fi

    # 2. Create config archive
    log_info "PHASE 2: Configuration Archive"
    if ! create_config_archive; then
        log_error "Config archive creation FAILED"
        overall_ok=false
    else
        # 3. Verify
        log_info "PHASE 3: Verification"
        if ! verify_archive; then
            log_error "Archive verification FAILED"
            overall_ok=false
        fi
    fi

    # 4. Retention
    log_info "PHASE 4: Retention"
    apply_retention

    # Summary
    log_info "=============================================="
    log_info "Configuration Backup Complete"
    if ${overall_ok}; then
        log_info "  Status: SUCCESS"
        log_info "  Archive: ${BACKUP_FILE}"
        log_info "  Size: $(du -h "${BACKUP_FILE}" 2>/dev/null | cut -f1)"
    else
        log_error "  Status: FAILED (check log for details)"
    fi
    log_info "  Backup dir: ${BACKUP_ROOT}"
    log_info "  Total size: $(du -sh "${BACKUP_ROOT}" 2>/dev/null | cut -f1)"
    log_info "=============================================="

    ${overall_ok} && return 0 || return 1
}

main "$@"
