#!/usr/bin/env bash
# =============================================================================
# restore-volume.sh — Docker Volume Restore Script (Hetzner CPX51)
# =============================================================================
# Usage: ./restore-volume.sh <volume_name> [timestamp|latest]
#   <volume_name>     - Docker volume to restore
#   [timestamp]       - Specific backup timestamp or "latest" (default)
#
# Safety: Stops affected containers, backs up existing volume first,
#          clears volume, extracts backup tarball, restarts containers,
#          verifies with health checks.
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

# --- Logging -----------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "${message}" | tee -a "${RESTORE_LOG}"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# --- Usage -------------------------------------------------------------------
usage() {
    cat <<-EOF
Usage: $(basename "$0") <volume_name> [timestamp|latest] [--force]

Restore a Docker named volume from backup tarball.

Arguments:
  volume_name   Docker volume to restore (required)
  timestamp     Backup timestamp in YYYYMMDD_HHMMSS format (optional)
                Use "latest" for the most recent backup (default)

Flags:
  --force       Skip confirmation prompts
  --dry-run     Show what would be done without doing it
  --help        Show this help message

Examples:
  $(basename "$0") monitoring_grafana-data latest
  $(basename "$0") prediction-radar_db-data 20250101_030000 --force
EOF
    exit 0
}

# --- List available volume backups -------------------------------------------
list_volume_backups() {
    local volume="$1"

    log_info "Available backups for volume '${volume}':"
    echo ""
    printf "  %-25s %-20s %s\n" "TIMESTAMP" "SIZE" "AGE"
    echo "  $(printf '%0.s-' {1..70})"

    local backups
    mapfile -t backups < <(find "${BACKUP_VOLUME_DIR}" -maxdepth 1 -name "*_${volume}.tar.gz" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    if [ ${#backups[@]} -eq 0 ]; then
        log_error "No backups found for volume '${volume}'"
        return 1
    fi

    for backup in "${backups[@]}"; do
        local fname
        fname="$(basename "${backup}")"
        local ts="${fname%%_*}"
        local fsize
        fsize="$(stat -c%s "${backup}" 2>/dev/null || stat -f%z "${backup}" 2>/dev/null)"
        local fsize_hr
        fsize_hr="$(numfmt --to=iec "${fsize}" 2>/dev/null || echo "${fsize} bytes")"
        local fage
        fage="$(date -d "@$(stat -c%Y "${backup}" 2>/dev/null || stat -f%m "${backup}" 2>/dev/null)" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
        printf "  %-25s %-20s %s\n" "${ts}" "${fsize_hr}" "${fage}"
    done
    echo ""
}

# --- Find backup file --------------------------------------------------------
find_backup() {
    local volume="$1"
    local timestamp="$2"

    if [ "${timestamp}" = "latest" ]; then
        local latest
        latest="$(find "${BACKUP_VOLUME_DIR}" -maxdepth 1 -name "*_${volume}.tar.gz" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
        if [ -z "${latest}" ] || [ ! -f "${latest}" ]; then
            log_error "No backup found for volume '${volume}'"
            return 1
        fi
        echo "${latest}"
    else
        local backup_path="${BACKUP_VOLUME_DIR}/${timestamp}_${volume}.tar.gz"
        if [ ! -f "${backup_path}" ]; then
            # Try broader search
            backup_path="$(find "${BACKUP_VOLUME_DIR}" -maxdepth 1 -name "${timestamp}_${volume}.tar.gz" 2>/dev/null | head -1)"
            if [ -z "${backup_path}" ]; then
                log_error "Backup not found: ${timestamp}_${volume}.tar.gz"
                return 1
            fi
        fi
        echo "${backup_path}"
    fi
}

# --- Find containers using a volume ------------------------------------------
find_volume_consumers() {
    local volume="$1"
    docker ps -a --filter "volume=${volume}" --format '{{.Names}}' 2>/dev/null || true
}

# --- Stop containers using the volume ----------------------------------------
stop_containers() {
    local volume="$1"
    local dry_run="${2:-false}"

    local containers
    containers="$(find_volume_consumers "${volume}")"

    if [ -z "${containers}" ]; then
        log_info "No running containers are using volume '${volume}'"
        return 0
    fi

    log_info "Containers using volume '${volume}': ${containers}"

    if [ "${dry_run}" = "true" ]; then
        log_info "[DRY-RUN] Would stop containers: ${containers}"
        return 0
    fi

    for container in ${containers}; do
        log_info "Stopping container: ${container}"
        docker stop "${container}" 2>/dev/null || true
        docker wait "${container}" 2>/dev/null || true
    done
    log_info "All dependent containers stopped"
}

# --- Start containers after restore ------------------------------------------
start_containers() {
    local volume="$1"
    local dry_run="${2:-false}"

    local containers
    containers="$(find_volume_consumers "${volume}")"

    if [ -z "${containers}" ]; then
        return 0
    fi

    log_info "Starting containers: ${containers}"

    if [ "${dry_run}" = "true" ]; then
        log_info "[DRY-RUN] Would start containers: ${containers}"
        return 0
    fi

    for container in ${containers}; do
        docker start "${container}" 2>/dev/null || true
    done
    log_info "Containers started"
}

# --- Backup existing volume (just in case) -----------------------------------
backup_existing_volume() {
    local volume="$1"
    local timestamp="$2"
    local dry_run="${3:-false}"

    # Check if volume exists
    if ! docker volume inspect "${volume}" >/dev/null 2>&1; then
        log_info "Volume '${volume}' does not exist yet — no pre-restore backup needed"
        return 0
    fi

    local backup_path="${BACKUP_VOLUME_DIR}/prerestore_${timestamp}_${volume}.tar.gz"
    log_info "Creating pre-restore backup of existing volume '${volume}'..."

    if [ "${dry_run}" = "true" ]; then
        log_info "[DRY-RUN] Would backup existing volume to: ${backup_path}"
        return 0
    fi

    if docker run --rm \
        -v "${volume}":/source:ro \
        -v "${BACKUP_VOLUME_DIR}":/backup \
        alpine:latest \
        tar czf "/backup/$(basename "${backup_path}")" \
            --ignore-failed-read \
            -C /source \
            . 2>/dev/null; then
        log_info "Pre-restore backup created: ${backup_path}"
    else
        log_warn "Pre-restore backup may be incomplete"
    fi
}

# --- Restore volume from backup ----------------------------------------------
restore_volume() {
    local volume="$1"
    local backup_path="$2"
    local force="${3:-false}"
    local dry_run="${4:-false}"

    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"

    log_info "=============================================="
    log_info "RESTORE: Volume '${volume}' from backup"
    log_info "Backup: ${backup_path}"
    log_info "=============================================="

    # Confirm
    if [ "${force}" != "true" ]; then
        echo ""
        echo "WARNING: You are about to RESTORE Docker volume '${volume}' from backup."
        echo "  Backup file: ${backup_path}"
        echo "  This will REPLACE the existing volume contents."
        echo "  A pre-restore backup will be saved."
        echo ""
        read -r -p "Are you sure you want to continue? [y/N] " response
        if [[ ! "${response}" =~ ^[yY](es)?$ ]]; then
            log_info "Restore cancelled by user"
            exit 0
        fi
    fi

    if [ "${dry_run}" = "true" ]; then
        log_info "[DRY-RUN] Would stop containers using '${volume}'"
        log_info "[DRY-RUN] Would backup existing volume data"
        log_info "[DRY-RUN] Would remove and recreate volume '${volume}'"
        log_info "[DRY-RUN] Would extract backup tarball into volume"
        log_info "[DRY-RUN] Would start containers"
        log_info "[DRY-RUN] Volume restore simulation complete"
        return 0
    fi

    # Step 1: Stop containers using this volume
    log_info "Step 1: Stopping containers using volume..."
    stop_containers "${volume}"
    log_info "Containers stopped"

    # Step 2: Backup existing volume
    log_info "Step 2: Backing up existing volume data..."
    backup_existing_volume "${volume}" "${timestamp}"
    log_info "Pre-restore backup complete"

    # Step 3: Remove and recreate volume
    log_info "Step 3: Removing and recreating volume '${volume}'..."
    docker volume rm "${volume}" 2>/dev/null || true
    docker volume create "${volume}" >/dev/null
    log_info "Volume '${volume}' recreated"

    # Step 4: Extract backup tarball into volume
    log_info "Step 4: Extracting backup data into volume..."
    if docker run --rm \
        -v "${volume}":/target \
        -v "${BACKUP_VOLUME_DIR}":/backup:ro \
        alpine:latest \
        sh -c "tar xzf \"/backup/$(basename "${backup_path}")\" -C /target" 2>/dev/null; then
        log_info "Backup data extracted into volume"
    else
        log_error "Failed to extract backup into volume"
        log_error "Attempting rollback of volume '${volume}'..."
        perform_rollback "${volume}" "${timestamp}"
        exit 1
    fi

    # Step 5: Verify volume has content
    log_info "Step 5: Verifying volume contents..."
    local file_count
    file_count="$(docker run --rm -v "${volume}":/target alpine:latest sh -c "find /target -type f 2>/dev/null | wc -l")"
    log_info "Volume '${volume}' contains ${file_count} files"

    if [ "${file_count}" -eq 0 ]; then
        log_warn "Volume '${volume}' appears empty after restore"
    fi

    # Step 6: Start containers
    log_info "Step 6: Starting containers..."
    start_containers "${volume}"
    log_info "Containers started"

    log_info "=============================================="
    log_info "RESTORE COMPLETE for volume '${volume}'"
    log_info "Backup used: ${backup_path}"
    log_info "=============================================="
}

# --- Rollback volume ---------------------------------------------------------
perform_rollback() {
    local volume="$1"
    local timestamp="$2"

    local rollback_path="${BACKUP_VOLUME_DIR}/prerestore_${timestamp}_${volume}.tar.gz"

    if [ ! -f "${rollback_path}" ]; then
        log_error "Pre-restore backup not found: ${rollback_path}"
        log_error "CRITICAL: Manual intervention required for volume '${volume}'!"
        return 1
    fi

    log_info "ROLLBACK: Restoring pre-restore backup for volume '${volume}'..."

    # Remove and recreate volume
    docker volume rm "${volume}" 2>/dev/null || true
    docker volume create "${volume}" >/dev/null

    # Extract pre-restore backup
    docker run --rm \
        -v "${volume}":/target \
        -v "${BACKUP_VOLUME_DIR}":/backup:ro \
        alpine:latest \
        tar xzf "/backup/$(basename "${rollback_path}")" -C /target

    log_info "Starting containers after rollback..."
    start_containers "${volume}"

    log_info "ROLLBACK COMPLETE for volume '${volume}'"
}

# --- Verify backup integrity -------------------------------------------------
verify_backup_integrity() {
    local backup_path="$1"

    if [ ! -f "${backup_path}" ]; then
        log_error "Backup file not found: ${backup_path}"
        return 1
    fi

    log_info "Verifying backup tarball integrity..."
    if ! tar tzf "${backup_path}" >/dev/null 2>> "${RESTORE_LOG}"; then
        log_error "Backup tarball is CORRUPT: ${backup_path}"
        return 1
    fi

    local file_count
    file_count="$(tar tzf "${backup_path}" 2>/dev/null | wc -l)"
    log_info "Backup integrity OK: ${backup_path} (${file_count} entries)"
    return 0
}

# === MAIN ====================================================================
main() {
    local volume=""
    local timestamp="latest"
    local force="false"
    local dry_run="false"

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --help|-h)
                usage
                ;;
            --force|-f)
                force="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            *)
                if [ -z "${volume}" ]; then
                    volume="$1"
                elif [ "${timestamp}" = "latest" ]; then
                    timestamp="$1"
                else
                    echo "Unknown argument: $1"
                    usage
                fi
                shift
                ;;
        esac
    done

    if [ -z "${volume}" ]; then
        echo "ERROR: Volume name required"
        usage
    fi

    # List backups and find target
    echo ""
    list_volume_backups "${volume}" || exit 1

    local backup_path
    backup_path="$(find_backup "${volume}" "${timestamp}")" || exit 1
    echo ""
    log_info "Selected backup: ${backup_path}"

    # Pre-flight integrity check
    verify_backup_integrity "${backup_path}" || exit 1

    # Perform restore
    restore_volume "${volume}" "${backup_path}" "${force}" "${dry_run}"
}

# --- Run ---------------------------------------------------------------------
main "$@"
