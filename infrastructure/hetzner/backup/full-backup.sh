#!/usr/bin/env bash
# =============================================================================
# full-backup.sh — Full Backup Orchestrator (Hetzner CPX51)
# =============================================================================
# Runs database-backup.sh first, then volume-backup.sh.
# Creates a unified backup manifest JSON with all paths and sizes.
# Pushes manifest + backups to remote storage via rsync.
# Pings healthchecks.io on success/failure.
# Uses flock to prevent concurrent runs.
# =============================================================================
set -euo pipefail

# --- Source config -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/backup-config.sh" ]; then
    source "${SCRIPT_DIR}/backup-config.sh"
else
    echo "FATAL: backup-config.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

# --- Lock file (prevent concurrent runs) -------------------------------------
LOCK_FILE="${BACKUP_LOCK_FILE:-/var/run/aiops-full-backup.lock}"

acquire_lock() {
    exec 200>"${LOCK_FILE}"
    if ! flock -n 200; then
        echo "[ERROR] Another backup is already running (lock held by ${LOCK_FILE})"
        exit 1
    fi
    # The lock is automatically released when the script exits (FD 200 is closed)
}

release_lock() {
    # flock releases when FD is closed
    if [ -f "${LOCK_FILE}" ]; then
        rm -f "${LOCK_FILE}" 2>/dev/null || true
    fi
}

# --- Logging -----------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "${message}" | tee -a "${BACKUP_LOG}"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# --- Healthcheck ping --------------------------------------------------------
healthcheck_ping() {
    local status="$1"
    local message="$2"

    if [ -n "${HEALTHCHECK_URL}" ]; then
        local ping_url="${HEALTHCHECK_URL}${status}"
        if [ -n "${message}" ]; then
            curl -fsS -m 10 --data-raw "${message}" "${ping_url}" >/dev/null 2>&1 || true
        else
            curl -fsS -m 10 "${ping_url}" >/dev/null 2>&1 || true
        fi
    fi
}

# --- Ensure directories exist ------------------------------------------------
setup_directories() {
    mkdir -p "${BACKUP_DATABASE_DIR}"
    mkdir -p "${BACKUP_VOLUME_DIR}"
    mkdir -p "${BACKUP_MANIFEST_DIR}"
    mkdir -p "${LOG_DIR}"
}

# --- Create unified JSON manifest --------------------------------------------
create_unified_manifest() {
    local timestamp
    timestamp="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    local manifest_file="${BACKUP_MANIFEST_DIR}/manifest_$(date '+%Y%m%d_%H%M%S').json"
    local latest_link="${BACKUP_MANIFEST_DIR}/manifest_latest.json"

    log_info "Creating unified backup manifest: $(basename "${manifest_file}")"

    # Collect database backup info
    local db_backups_json="{"
    local db_first=true
    for db in "${DATABASES[@]}"; do
        local latest_db
        latest_db="$(find "${BACKUP_DATABASE_DIR}" -maxdepth 1 -name "*_${db}.dump" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
        if [ -n "${latest_db}" ] && [ -f "${latest_db}" ]; then
            local fsize
            fsize="$(stat -c%s "${latest_db}" 2>/dev/null || stat -f%z "${latest_db}" 2>/dev/null)"
            if [ "${db_first}" = false ]; then
                db_backups_json+=","
            fi
            db_backups_json+="\"${db}\": {\"path\": \"${latest_db}\", \"size_bytes\": ${fsize}, \"timestamp\": \"$(date -r "${latest_db}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)\"}"
            db_first=false
        fi
    done
    db_backups_json+="}"

    # Collect volume backup info
    local vol_backups_json="{"
    local vol_first=true
    local vol_backups
    mapfile -t vol_backups < <(find "${BACKUP_VOLUME_DIR}" -maxdepth 1 -name '*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -20 | cut -d' ' -f2-)
    for vol_backup in "${vol_backups[@]}"; do
        local fname
        fname="$(basename "${vol_backup}")"
        local vol_name="${fname#*_}"
        vol_name="${vol_name%.tar.gz}"
        local fsize
        fsize="$(stat -c%s "${vol_backup}" 2>/dev/null || stat -f%z "${vol_backup}" 2>/dev/null)"
        if [ "${vol_first}" = false ]; then
            vol_backups_json+=","
        fi
        vol_backups_json+="\"${vol_name}\": {\"path\": \"${vol_backup}\", \"size_bytes\": ${fsize}, \"timestamp\": \"$(date -r "${vol_backup}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)\"}"
        vol_first=false
    done
    vol_backups_json+="}"

    # Compile full manifest
    cat > "${manifest_file}" <<-EOF
{
  "manifest_version": "1.0",
  "server": "hetzner-cpx51",
  "hostname": "$(hostname)",
  "backup_timestamp": "${timestamp}",
  "backup_date": "$(date '+%Y-%m-%d')",
  "backup_time": "$(date '+%H:%M:%S')",
  "databases": ${db_backups_json},
  "volumes": ${vol_backups_json},
  "retention": {
    "daily": ${RETENTION_DAILY_COUNT},
    "weekly": ${RETENTION_WEEKLY_COUNT},
    "monthly": ${RETENTION_MONTHLY_COUNT}
  },
  "healthcheck_url": "${HEALTHCHECK_URL}"
}
EOF

    # Update latest symlink
    ln -sf "${manifest_file}" "${latest_link}" 2>/dev/null || cp "${manifest_file}" "${latest_link}"

    log_info "Unified manifest created: $(basename "${manifest_file}")"

    # Return the manifest path for use in rsync
    echo "${manifest_file}"
}

# --- Push to remote storage --------------------------------------------------
push_to_remote() {
    if [ -z "${REMOTE_BACKUP_HOST}" ]; then
        log_info "No REMOTE_BACKUP_HOST configured — skipping remote push"
        return 0
    fi

    log_info "Pushing backups to remote: ${REMOTE_BACKUP_USER}@${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}"

    # Rsync databases
    log_info "Syncing database backups..."
    rsync -avz --delete \
        -e "ssh -p ${REMOTE_SSH_PORT}" \
        "${BACKUP_DATABASE_DIR}/" \
        "${REMOTE_BACKUP_USER}@${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/databases/" 2>&1 | tee -a "${BACKUP_LOG}"

    local db_rsync_exit=$?
    if [ "${db_rsync_exit}" -ne 0 ]; then
        log_warn "Database rsync exited with code ${db_rsync_exit}"
    fi

    # Rsync volumes
    log_info "Syncing volume backups..."
    rsync -avz --delete \
        -e "ssh -p ${REMOTE_SSH_PORT}" \
        "${BACKUP_VOLUME_DIR}/" \
        "${REMOTE_BACKUP_USER}@${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/volumes/" 2>&1 | tee -a "${BACKUP_LOG}"

    local vol_rsync_exit=$?
    if [ "${vol_rsync_exit}" -ne 0 ]; then
        log_warn "Volume rsync exited with code ${vol_rsync_exit}"
    fi

    # Rsync manifests
    log_info "Syncing manifests..."
    rsync -avz \
        -e "ssh -p ${REMOTE_SSH_PORT}" \
        "${BACKUP_MANIFEST_DIR}/" \
        "${REMOTE_BACKUP_USER}@${REMOTE_BACKUP_HOST}:${REMOTE_BACKUP_PATH}/manifests/" 2>&1 | tee -a "${BACKUP_LOG}"

    log_info "Remote push complete"
    return 0
}

# --- Cleanup ---
cleanup() {
    release_lock 2>/dev/null || true
}

# --- Main --------------------------------------------------------------------
main() {
    local start_time
    start_time="$(date +%s)"

    # Trap to ensure lock release
    trap cleanup EXIT

    log_info "=============================================="
    log_info "FULL BACKUP STARTING"
    log_info "Server: Hetzner CPX51"
    log_info "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "=============================================="

    # Acquire lock
    acquire_lock
    log_info "Lock acquired"

    # Setup
    setup_directories

    # Send healthcheck start
    healthcheck_ping "" "Full backup started at $(date)"

    # Step 1: Database backup
    log_info "Step 1/4: Database backup..."
    local db_exit=0
    if ! bash "${SCRIPT_DIR}/database-backup.sh"; then
        db_exit=$?
        log_warn "Database backup had issues (exit: ${db_exit})"
    fi

    # Step 2: Volume backup
    log_info "Step 2/4: Volume backup..."
    local vol_exit=0
    if ! bash "${SCRIPT_DIR}/volume-backup.sh"; then
        vol_exit=$?
        log_warn "Volume backup had issues (exit: ${vol_exit})"
    fi

    # Step 3: Create unified manifest
    log_info "Step 3/4: Creating unified manifest..."
    local manifest_file
    manifest_file="$(create_unified_manifest)"

    # Step 4: Push to remote (if configured)
    log_info "Step 4/4: Remote sync..."
    push_to_remote

    # Calculate total size
    local db_size=0
    if [ -d "${BACKUP_DATABASE_DIR}" ]; then
        db_size="$(du -sb "${BACKUP_DATABASE_DIR}" 2>/dev/null | cut -f1 || echo "0")"
    fi
    local vol_size=0
    if [ -d "${BACKUP_VOLUME_DIR}" ]; then
        vol_size="$(du -sb "${BACKUP_VOLUME_DIR}" 2>/dev/null | cut -f1 || echo "0")"
    fi
    local total_size=$((db_size + vol_size))
    local total_size_hr
    total_size_hr="$(numfmt --to=iec "${total_size}" 2>/dev/null || echo "${total_size} bytes")"

    # Summary
    local end_time
    end_time="$(date +%s)"
    local duration=$((end_time - start_time))
    local duration_hr
    duration_hr="$(date -u -d "@${duration}" '+%H:%M:%S' 2>/dev/null || echo "${duration}s")"

    local overall_status="SUCCESS"
    local overall_exit=0
    if [ "${db_exit}" -ne 0 ] || [ "${vol_exit}" -ne 0 ]; then
        overall_status="PARTIAL_FAILURE"
        overall_exit=1
    fi

    log_info "=============================================="
    log_info "FULL BACKUP COMPLETE [${overall_status}]"
    log_info "Duration: ${duration_hr}"
    log_info "Database backup exit: ${db_exit}"
    log_info "Volume backup exit: ${vol_exit}"
    log_info "Total backup size: ${total_size_hr}"
    log_info "Manifest: ${manifest_file}"
    log_info "=============================================="

    # Healthcheck
    local health_message="Full backup ${overall_status}. Duration: ${duration_hr}. Total size: ${total_size_hr}."
    if [ "${overall_exit}" -eq 0 ]; then
        healthcheck_ping "" "${health_message}"
    else
        healthcheck_ping "/fail" "${health_message}"
    fi

    return "${overall_exit}"
}

# --- Run ---------------------------------------------------------------------
main "$@"
