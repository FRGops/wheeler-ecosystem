#!/usr/bin/env bash
# =============================================================================
# volume-backup.sh — Docker Volume Backup Script (Hetzner CPX51)
# =============================================================================
# Backs up Docker named volumes as compressed tarballs.
# For each non-ephemeral volume: docker run a temp container, tar+gzip to
# /opt/backups/volumes/. Skips volumes marked as cache/tmp.
# Runs backups in parallel (background per volume).
# Verifies tarball integrity.
# Retention: 7 daily.
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

# --- Ensure required directories exist ---------------------------------------
setup_directories() {
    mkdir -p "${BACKUP_VOLUME_DIR}"
    mkdir -p "${LOG_DIR}"
    mkdir -p "${BACKUP_TEMP_DIR}"
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

# --- Get list of named Docker volumes ----------------------------------------
get_all_volumes() {
    docker volume ls --format '{{.Name}}' 2>/dev/null || return 1
}

# --- Check if a volume should be backed up -----------------------------------
should_backup_volume() {
    local volume="$1"

    # Check if volume is in the explicit skip list
    for skip_vol in "${VOLUMES_SKIP[@]}"; do
        if [ "${volume}" = "${skip_vol}" ]; then
            return 1
        fi
    done

    # Check volume labels for hints about ephemeral/cache usage
    local labels
    labels="$(docker volume inspect "${volume}" --format '{{json .Labels}}' 2>/dev/null || echo "{}")"

    # Skip if volume is explicitly labeled as ephemeral
    if echo "${labels}" | grep -qi "ephemeral\|cache\|tmp\|temp\|scratch" 2>/dev/null; then
        log_info "Skipping volume '${volume}' (labeled as ephemeral/cache)"
        return 1
    fi

    # Skip if volume is in the configured skip list
    for skip in "${VOLUMES_SKIP[@]}"; do
        if [ "${volume}" = "${skip}" ]; then
            return 1
        fi
    done

    return 0
}

# --- Backup a single volume (run in background) ------------------------------
backup_volume() {
    local volume="$1"
    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local backup_path="${BACKUP_VOLUME_DIR}/${timestamp}_${volume}.tar.gz"
    local backup_info_path="${backup_path}.info"

    log_info "[${volume}] Starting volume backup → $(basename "${backup_path}")"

    # Verify volume exists
    if ! docker volume inspect "${volume}" >/dev/null 2>&1; then
        log_warn "[${volume}] Volume does not exist — skipping"
        return 0
    fi

    # Get volume details
    local mountpoint
    mountpoint="$(docker volume inspect "${volume}" --format '{{.Mountpoint}}' 2>/dev/null || echo "unknown")"
    log_info "[${volume}] Mountpoint: ${mountpoint}"

    # Get volume size before backup (approximate)
    local vol_size
    vol_size="$(docker run --rm -v "${volume}":/vol alpine:latest sh -c "du -sh /vol 2>/dev/null | cut -f1" 2>/dev/null || echo "unknown")"
    log_info "[${volume}] Volume size: ${vol_size}"

    # Back up the volume using a temporary Alpine container
    # Using alpine for minimal footprint — it mounts the volume and tars its contents
    if ! docker run --rm \
        -v "${volume}":/source:ro \
        -v "${BACKUP_VOLUME_DIR}":/backup \
        alpine:latest \
        tar czf "/backup/$(basename "${backup_path}")" \
            --ignore-failed-read \
            --warning=no-file-changed \
            -C /source \
            . 2>/dev/null; then
        log_error "[${volume}] Backup command failed"
        rm -f "${backup_path}"
        return 1
    fi

    # Verify the tarball exists and has content
    if [ ! -f "${backup_path}" ] || [ ! -s "${backup_path}" ]; then
        log_error "[${volume}] Backup file is empty or missing"
        rm -f "${backup_path}"
        return 1
    fi

    # Verify tarball integrity
    log_info "[${volume}] Verifying tarball integrity..."
    if ! verify_tarball "${backup_path}"; then
        log_error "[${volume}] Tarball integrity check FAILED"
        rm -f "${backup_path}"
        return 1
    fi

    # Get file size
    local file_size
    file_size="$(stat -c%s "${backup_path}" 2>/dev/null || stat -f%z "${backup_path}" 2>/dev/null)"
    local file_size_hr
    file_size_hr="$(numfmt --to=iec "${file_size}" 2>/dev/null || echo "${file_size} bytes")"
    log_info "[${volume}] Backup completed: ${file_size_hr}"

    # Write backup info file
    cat > "${backup_info_path}" <<-EOF
volume=${volume}
timestamp=${timestamp}
backup_path=${backup_path}
mountpoint=${mountpoint}
size_before_backup=${vol_size}
file_size_bytes=${file_size}
file_size_human=${file_size_hr}
verification=PASSED
EOF

    log_info "[${volume}] Successfully backed up"
    return 0
}

# --- Verify tarball integrity ------------------------------------------------
verify_tarball() {
    local tarball="$1"

    if [ ! -f "${tarball}" ]; then
        log_error "Tarball not found: ${tarball}"
        return 1
    fi

    # Test the tarball by listing its contents (doesn't extract)
    if ! tar tzf "${tarball}" >/dev/null 2>> "${BACKUP_LOG}"; then
        log_error "Tarball corruption detected: ${tarball}"
        return 1
    fi

    # Count files in tarball
    local file_count
    file_count="$(tar tzf "${tarball}" 2>/dev/null | wc -l)"
    log_info "Tarball integrity OK: ${tarball} (${file_count} entries)"

    return 0
}

# --- Create backup manifest --------------------------------------------------
create_manifest() {
    local manifest_path="${BACKUP_VOLUME_DIR}/manifest.txt"

    log_info "Creating volume backup manifest at ${manifest_path}"

    {
        echo "============================================"
        echo "Hetzner CPX51 Volume Backup Manifest"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Host: $(hostname)"
        echo "============================================"
        echo ""
        echo "Backup Directory: ${BACKUP_VOLUME_DIR}"
        echo ""

        local total_size=0
        local count=0

        for tarball in $(find "${BACKUP_VOLUME_DIR}" -maxdepth 1 -name '*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-); do
            local fname
            fname="$(basename "${tarball}")"
            local fsize
            fsize="$(stat -c%s "${tarball}" 2>/dev/null || stat -f%z "${tarball}" 2>/dev/null)"
            local fsize_hr
            fsize_hr="$(numfmt --to=iec "${fsize}" 2>/dev/null || echo "${fsize} bytes")"
            local fdate
            fdate="$(date -d "@$(stat -c%Y "${tarball}" 2>/dev/null || stat -f%m "${tarball}" 2>/dev/null)" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"

            # Verify integrity as we go
            local integrity="OK"
            if ! tar tzf "${tarball}" >/dev/null 2>&1; then
                integrity="CORRUPT"
            fi

            echo "  ${fname}  |  ${fsize_hr}  |  ${fdate}  |  [${integrity}]"
            total_size=$((total_size + fsize))
            count=$((count + 1))
        done

        echo ""
        echo "Total Backups: ${count}"
        echo "Total Size: $(numfmt --to=iec "${total_size}" 2>/dev/null || echo "${total_size} bytes")"
        echo "============================================"
    } > "${manifest_path}"

    log_info "Volume manifest created: ${count} backups"
}

# --- Apply retention (7 daily for volumes) -----------------------------------
apply_retention() {
    local keep_count="${RETENTION_DAILY_COUNT:-7}"

    log_info "Applying volume retention (keeping ${keep_count} most recent per volume)..."

    # Group backups by volume name (strip timestamp prefix)
    local current_backups
    mapfile -t current_backups < <(find "${BACKUP_VOLUME_DIR}" -maxdepth 1 -name '*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    declare -A volume_backups
    for backup in "${current_backups[@]}"; do
        local fname
        fname="$(basename "${backup}")"
        # Extract volume name: format is TIMESTAMP_volumename.tar.gz
        local vol_name="${fname#*_}"
        vol_name="${vol_name%.tar.gz}"
        volume_backups["${vol_name}"]+="${backup} "
    done

    for vol_name in "${!volume_backups[@]}"; do
        local count=0
        for backup in ${volume_backups["${vol_name}"]}; do
            count=$((count + 1))
            if [ "${count}" -gt "${keep_count}" ]; then
                log_info "Removing old volume backup: $(basename "${backup}")"
                rm -f "${backup}" "${backup}.info" 2>/dev/null || true
            fi
        done
    done

    log_info "Volume retention cleanup complete"
}

# --- Main --------------------------------------------------------------------
main() {
    local start_time
    start_time="$(date +%s)"

    log_info "=============================================="
    log_info "Volume Backup Starting"
    log_info "Server: Hetzner CPX51"
    log_info "=============================================="

    setup_directories

    # Get all named volumes
    local all_volumes=()
    mapfile -t all_volumes < <(get_all_volumes)
    log_info "Found ${#all_volumes[@]} total volumes"

    # Filter and backup in parallel
    local pids=()
    local volumes_to_backup=()
    local vol_index=0

    for volume in "${all_volumes[@]}"; do
        # Skip anonymous volumes (they have long hex names)
        if [[ "${volume}" =~ ^[a-f0-9]{64}$ ]]; then
            log_info "Skipping anonymous volume: ${volume}"
            continue
        fi

        if should_backup_volume "${volume}"; then
            volumes_to_backup+=("${volume}")

            # Backup in background
            (
                backup_volume "${volume}"
            ) &
            pids+=($!)
            log_info "Started backup of volume '${volume}' (PID $!)"
        else
            log_info "Skipping volume '${volume}' (cache/ephemeral/excluded)"
        fi
    done

    # Wait for all background jobs
    local success_count=0
    local fail_count=0
    local i=0

    for pid in "${pids[@]}"; do
        set +e
        wait "${pid}"
        local result=$?
        set -e

        if [ "${result}" -eq 0 ]; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
        i=$((i + 1))
    done

    # Create manifest
    create_manifest

    # Apply retention
    apply_retention

    # Summary
    local end_time
    end_time="$(date +%s)"
    local duration=$((end_time - start_time))
    local duration_hr
    duration_hr="$(date -u -d "@${duration}" '+%H:%M:%S' 2>/dev/null || echo "${duration}s")"

    log_info "=============================================="
    log_info "Volume Backup Complete"
    log_info "Duration: ${duration_hr}"
    log_info "Attempted: ${#volumes_to_backup[@]}, Successful: ${success_count}, Failed: ${fail_count}"
    log_info "=============================================="

    return $((fail_count > 0 ? 1 : 0))
}

# --- Run ---------------------------------------------------------------------
main "$@"
