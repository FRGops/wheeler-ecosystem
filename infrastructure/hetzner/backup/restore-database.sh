#!/usr/bin/env bash
# =============================================================================
# restore-database.sh — Database Restore Script (Hetzner CPX51)
# =============================================================================
# Usage: ./restore-database.sh <db_name> [timestamp|latest]
#   <db_name>         - Database to restore (prediction_radar, ravynai, etc.)
#   [timestamp]       - Specific backup timestamp (YYYYMMDD_HHMMSS) or
#                       "latest" for most recent (default: latest)
#
# Safety: Creates pre-restore snapshot, drops & recreates database,
#          pg_restore with verbose, rolls back on failure.
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
Usage: $(basename "$0") <db_name> [timestamp|latest]

Restore a PostgreSQL database from backup.

Arguments:
  db_name       Database to restore (required)
                Valid options: prediction_radar, ravynai, healthchecks, superset
  timestamp     Backup timestamp in YYYYMMDD_HHMMSS format (optional)
                Use "latest" for the most recent backup (default)

Examples:
  $(basename "$0") prediction_radar latest
  $(basename "$0") ravynai 20250101_030000
  $(basename "$0") healthchecks latest --force

Flags:
  --force       Skip confirmation prompts
  --dry-run     Show what would be done without actually doing it
  --help        Show this help message
EOF
    exit 0
}

# --- Find the backup file ----------------------------------------------------
find_backup() {
    local db="$1"
    local timestamp="$2"

    if [ "${timestamp}" = "latest" ]; then
        local latest
        latest="$(find "${BACKUP_DATABASE_DIR}" -maxdepth 1 -name "*_${db}.dump" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
        if [ -z "${latest}" ] || [ ! -f "${latest}" ]; then
            log_error "No backup found for database '${db}'"
            return 1
        fi
        echo "${latest}"
    else
        local backup_path="${BACKUP_DATABASE_DIR}/${timestamp}_${db}.dump"
        if [ ! -f "${backup_path}" ]; then
            # Try without full path
            backup_path="$(find "${BACKUP_DATABASE_DIR}" -maxdepth 1 -name "${timestamp}_${db}.dump" 2>/dev/null | head -1)"
            if [ -z "${backup_path}" ]; then
                log_error "Backup not found: ${timestamp}_${db}.dump"
                log_error "Available backups for '${db}':"
                ls -1 "${BACKUP_DATABASE_DIR}/"*"_${db}.dump" 2>/dev/null | while read -r f; do
                    log_error "  $(basename "${f}")"
                done
                return 1
            fi
        fi
        echo "${backup_path}"
    fi
}

# --- Check tool availability -------------------------------------------------
check_tools() {
    local missing=0
    for cmd in pg_restore psql pg_dump docker; do
        if ! command -v "${cmd}" &>/dev/null; then
            # Check in PostgreSQL version directories
            local found=false
            for pgdir in /usr/lib/postgresql/*/bin; do
                if [ -x "${pgdir}/${cmd}" ]; then
                    found=true
                    break
                fi
            done
            if ! $found; then
                log_error "Required tool not found: ${cmd}"
                missing=1
            fi
        fi
    done

    if [ "${missing}" -ne 0 ]; then
        log_error "Missing required tools. Please install them."
        exit 1
    fi
}

# --- List available backups for a database -----------------------------------
list_backups() {
    local db="$1"
    log_info "Available backups for '${db}':"
    echo ""
    printf "  %-25s %-20s %s\n" "TIMESTAMP" "SIZE" "AGE"
    echo "  $(printf '%0.s-' {1..70})"

    local backups
    mapfile -t backups < <(find "${BACKUP_DATABASE_DIR}" -maxdepth 1 -name "*_${db}.dump" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    if [ ${#backups[@]} -eq 0 ]; then
        log_error "No backups found for '${db}'"
        return 1
    fi

    for backup in "${backups[@]}"; do
        local fname
        fname="$(basename "${backup}")"
        local ts="${fname%_*}"  # Extract timestamp prefix
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

# --- Get Docker containers that depend on this database ----------------------
get_dependent_services() {
    local db="$1"

    # Map databases to their dependent Docker services
    case "${db}" in
        prediction_radar)
            echo "prediction-radar_api prediction-radar_web prediction-radar_worker prediction-radar_scheduler"
            ;;
        ravynai)
            echo "ravynai_api ravynai_worker"
            ;;
        healthchecks)
            echo "healthchecks_app"
            ;;
        superset)
            echo "superset_app superset_worker"
            ;;
        *)
            echo ""
            ;;
    esac
}

# --- Stop dependent services -------------------------------------------------
stop_services() {
    local db="$1"
    local dry_run="${2:-false}"

    local services
    services="$(get_dependent_services "${db}")"

    if [ -z "${services}" ]; then
        log_info "No dependent Docker services identified for '${db}'"
        return 0
    fi

    log_info "Stopping dependent services: ${services}"

    if [ "${dry_run}" = "true" ]; then
        log_info "[DRY-RUN] Would stop containers: ${services}"
        return 0
    fi

    for service in ${services}; do
        log_info "Stopping container: ${service}"
        # Try docker compose first, then plain docker
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${service}$"; then
            docker stop "${service}" 2>/dev/null || docker kill "${service}" 2>/dev/null || true
            docker wait "${service}" 2>/dev/null || true
            log_info "Container '${service}' stopped"
        else
            log_info "Container '${service}' not running — skipping"
        fi
    done
}

# --- Start dependent services ------------------------------------------------
start_services() {
    local db="$1"
    local dry_run="${2:-false}"

    local services
    services="$(get_dependent_services "${db}")"

    if [ -z "${services}" ]; then
        return 0
    fi

    log_info "Starting dependent services: ${services}"

    if [ "${dry_run}" = "true" ]; then
        log_info "[DRY-RUN] Would start containers: ${services}"
        return 0
    fi

    # Start each container (docker compose up -d service_name or docker start)
    for service in ${services}; do
        log_info "Starting container: ${service}"
        docker start "${service}" 2>/dev/null || {
            log_warn "Could not start '${service}' via docker start, trying docker compose..."
            # Try docker compose in the relevant directory
            local compose_dir
            for dir in "${COMPOSE_DIRS_HETZNER[@]}"; do
                if [ -f "${dir}/docker-compose.yml" ] || [ -f "${dir}/compose.yml" ]; then
                    (cd "${dir}" && docker compose up -d 2>/dev/null) && break
                fi
            done
        } || true
    done
}

# --- Verify app health after restore -----------------------------------------
verify_app_health() {
    local db="$1"
    log_info "Verifying application health after restore..."

    # Give services a moment to start
    sleep 5

    # Verify database connectivity
    if ! "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${db}" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Database connectivity check FAILED for '${db}'"
        return 1
    fi
    log_info "Database '${db}' is accepting connections"

    # Check table count (at least some tables should exist)
    local table_count
    table_count="$("${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${db}" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema');" 2>/dev/null || echo "0")"
    log_info "Database '${db}' has ${table_count} tables"

    if [ "${table_count}" -eq 0 ] && [ "${db}" != "postgres" ]; then
        log_warn "Database '${db}' has 0 tables — this may indicate an incomplete restore"
    fi

    # Try HTTP health check for known services
    case "${db}" in
        prediction_radar)
            for i in 1 2 3; do
                if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
                    log_info "Prediction Radar health check PASSED"
                    return 0
                fi
                sleep 5
            done
            log_warn "Prediction Radar health check did not pass (may need manual verification)"
            ;;
        ravynai)
            for i in 1 2 3; do
                if curl -sf http://localhost:8007/health >/dev/null 2>&1; then
                    log_info "RavynAI health check PASSED"
                    return 0
                fi
                sleep 5
            done
            log_warn "RavynAI health check did not pass (may need manual verification)"
            ;;
        healthchecks)
            for i in 1 2 3; do
                if curl -sf http://localhost:3130 >/dev/null 2>&1; then
                    log_info "Healthchecks health check PASSED"
                    return 0
                fi
                sleep 5
            done
            log_warn "Healthchecks health check did not pass (may need manual verification)"
            ;;
        superset)
            for i in 1 2 3; do
                if curl -sf http://localhost:8088/health >/dev/null 2>&1; then
                    log_info "Superset health check PASSED"
                    return 0
                fi
                sleep 5
            done
            log_warn "Superset health check did not pass (may need manual verification)"
            ;;
        *)
            log_info "No specific health check for '${db}' — database connectivity verified"
            ;;
    esac

    return 0
}

# --- Run migrations if needed ------------------------------------------------
run_migrations() {
    local db="$1"
    local dry_run="${2:-false}"

    case "${db}" in
        prediction_radar)
            log_info "Running Prediction Radar migrations..."
            if [ "${dry_run}" = "true" ]; then
                log_info "[DRY-RUN] Would run: docker exec prediction-radar_api python manage.py migrate"
                return 0
            fi
            if docker exec prediction-radar_api python manage.py migrate 2>/dev/null; then
                log_info "Prediction Radar migrations completed"
            else
                log_warn "Prediction Radar migrations failed (may need manual intervention)"
            fi
            ;;
        ravynai)
            log_info "Running RavynAI migrations..."
            if [ "${dry_run}" = "true" ]; then
                log_info "[DRY-RUN] Would run: docker exec ravynai_api python manage.py migrate"
                return 0
            fi
            if docker exec ravynai_api python manage.py migrate 2>/dev/null; then
                log_info "RavynAI migrations completed"
            else
                log_warn "RavynAI migrations failed (may need manual intervention)"
            fi
            ;;
        *)
            log_info "No automated migrations for '${db}'"
            ;;
    esac
}

# --- Create pre-restore snapshot ---------------------------------------------
create_pre_restore_snapshot() {
    local db="$1"
    local snapshot_path="$2"
    local dry_run="${3:-false}"

    log_info "Creating pre-restore snapshot of '${db}'..."

    if [ "${dry_run}" = "true" ]; then
        log_info "[DRY-RUN] Would create snapshot at: ${snapshot_path}"
        return 0
    fi

    # Verify database exists before snapshot
    if ! "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname='${db}';" 2>/dev/null | grep -q 1; then
        log_warn "Database '${db}' does not exist — no pre-restore snapshot needed (will be created fresh)"
        return 0
    fi

    # pg_dump the current state
    if "${PG_DUMP_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" \
        -d "${db}" -F c -v --no-owner --no-acl \
        -f "${snapshot_path}" 2>> "${RESTORE_LOG}"; then
        log_info "Pre-restore snapshot created: ${snapshot_path}"
    else
        log_warn "Pre-restore snapshot may be incomplete (exit code: $?)"
    fi
}

# --- Main restore function ---------------------------------------------------
restore_database() {
    local db="$1"
    local backup_path="$2"
    local force="${3:-false}"
    local dry_run="${4:-false}"

    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local snapshot_path="${BACKUP_DATABASE_DIR}/prerestore_${timestamp}_${db}.dump"
    local rollback_needed=false

    log_info "=============================================="
    log_info "RESTORE: Database '${db}' from backup"
    log_info "Backup: ${backup_path}"
    log_info "Timestamp: ${timestamp}"
    log_info "=============================================="

    # Confirm unless --force
    if [ "${force}" != "true" ]; then
        echo ""
        echo "WARNING: You are about to RESTORE database '${db}' from backup."
        echo "  Backup file: ${backup_path}"
        echo "  This will DROP and recreate the database."
        echo "  A pre-restore snapshot will be saved at: ${snapshot_path}"
        echo ""
        read -r -p "Are you sure you want to continue? [y/N] " response
        if [[ ! "${response}" =~ ^[yY](es)?$ ]]; then
            log_info "Restore cancelled by user"
            exit 0
        fi
    fi

    if [ "${dry_run}" = "true" ]; then
        log_info "[DRY-RUN] Would stop dependent services for '${db}'"
        log_info "[DRY-RUN] Would create pre-restore snapshot at: ${snapshot_path}"
        log_info "[DRY-RUN] Would drop and recreate database '${db}'"
        log_info "[DRY-RUN] Would restore from: ${backup_path}"
        log_info "[DRY-RUN] Would run migrations for '${db}'"
        log_info "[DRY-RUN] Would restart services for '${db}'"
        log_info "[DRY-RUN] Would verify app health for '${db}'"
        log_info "[DRY-RUN] Restore simulation complete"
        return 0
    fi

    # Step 1: Stop dependent services
    log_info "Step 1: Stopping dependent services..."
    stop_services "${db}"
    log_info "Services stopped"

    # Step 2: Create pre-restore snapshot
    log_info "Step 2: Creating pre-restore snapshot..."
    create_pre_restore_snapshot "${db}" "${snapshot_path}"
    log_info "Pre-restore snapshot complete"

    # Step 3: Drop and recreate database
    log_info "Step 3: Dropping and recreating database '${db}'..."
    "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres <<-EOF
        -- Terminate all connections to the database
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '${db}' AND pid <> pg_backend_pid();

        -- Drop and recreate
        DROP DATABASE IF EXISTS "${db}";
        CREATE DATABASE "${db}";
EOF

    local drop_exit=$?
    if [ "${drop_exit}" -ne 0 ]; then
        log_error "Failed to drop/recreate database '${db}'"
        log_error "Attempting rollback..."
        rollback_needed=true
        perform_rollback "${db}" "${snapshot_path}" "${dry_run}"
        exit 1
    fi
    log_info "Database '${db}' dropped and recreated"

    # Step 4: Restore from backup
    log_info "Step 4: Restoring '${db}' from backup..."
    set +e
    "${PG_RESTORE_BIN}" \
        -h "${PGHOST}" \
        -p "${PGPORT}" \
        -U "${PGUSER}" \
        -d "${db}" \
        -v \
        --no-owner \
        --no-acl \
        --exit-on-error \
        "${backup_path}" 2>> "${RESTORE_LOG}"
    local restore_exit=$?
    set -e

    if [ "${restore_exit}" -ne 0 ]; then
        log_error "pg_restore FAILED for '${db}' (exit code: ${restore_exit})"
        log_error "Initiating rollback..."
        rollback_needed=true
        perform_rollback "${db}" "${snapshot_path}" "${dry_run}"
        exit 1
    fi
    log_info "Restore completed successfully"

    # Step 5: Analyze database
    log_info "Running ANALYZE on restored database..."
    "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${db}" -c "ANALYZE;" 2>/dev/null || true

    # Step 6: Run migrations
    log_info "Step 5: Running database migrations..."
    run_migrations "${db}"

    # Step 7: Restart services
    log_info "Step 6: Restarting services..."
    start_services "${db}"

    # Step 8: Verify health
    log_info "Step 7: Verifying application health..."
    if verify_app_health "${db}"; then
        log_info "Health verification PASSED for '${db}'"
    else
        log_warn "Health verification had issues — manual check recommended"
    fi

    log_info "=============================================="
    log_info "RESTORE COMPLETE for '${db}'"
    log_info "Backup used: ${backup_path}"
    log_info "Pre-restore snapshot: ${snapshot_path}"
    log_info "=============================================="
}

# --- Rollback function -------------------------------------------------------
perform_rollback() {
    local db="$1"
    local snapshot_path="$2"
    local dry_run="${3:-false}"

    log_info "=============================================="
    log_info "ROLLBACK: Restoring pre-restore snapshot"
    log_info "=============================================="

    if [ ! -f "${snapshot_path}" ]; then
        log_error "Pre-restore snapshot not found: ${snapshot_path}"
        log_error "Manual intervention required!"
        return 1
    fi

    if [ "${dry_run}" = "true" ]; then
        log_info "[DRY-RUN] Would restore from snapshot: ${snapshot_path}"
        return 0
    fi

    log_info "Dropping and recreating '${db}' for rollback..."
    "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres <<-EOF
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '${db}' AND pid <> pg_backend_pid();
        DROP DATABASE IF EXISTS "${db}";
        CREATE DATABASE "${db}";
EOF

    log_info "Restoring from pre-restore snapshot..."
    "${PG_RESTORE_BIN}" \
        -h "${PGHOST}" \
        -p "${PGPORT}" \
        -U "${PGUSER}" \
        -d "${db}" \
        -v \
        --no-owner \
        --no-acl \
        --exit-on-error \
        "${snapshot_path}" 2>> "${RESTORE_LOG}"

    local rollback_exit=$?
    if [ "${rollback_exit}" -ne 0 ]; then
        log_error "Rollback FAILED (exit code: ${rollback_exit})"
        log_error "CRITICAL: Manual intervention required for database '${db}'!"
        return 1
    fi

    log_info "Starting services after rollback..."
    start_services "${db}"

    log_info "ROLLBACK COMPLETE for '${db}'"
    return 0
}

# --- Verify backup integrity (pre-flight check) -------------------------------
verify_backup_integrity() {
    local backup_path="$1"

    if [ ! -f "${backup_path}" ]; then
        log_error "Backup file not found: ${backup_path}"
        return 1
    fi

    log_info "Pre-flight integrity check of backup..."
    if ! pg_restore --list "${backup_path}" >/dev/null 2>> "${RESTORE_LOG}"; then
        log_error "Backup integrity check FAILED — backup file may be corrupt"
        return 1
    fi

    log_info "Pre-flight integrity check PASSED"
    return 0
}

# === MAIN ====================================================================
main() {
    local db=""
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
                if [ -z "${db}" ]; then
                    db="$1"
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

    # Validate database name
    local valid_db=false
    for valid in "${DATABASES[@]}"; do
        if [ "${db}" = "${valid}" ]; then
            valid_db=true
            break
        fi
    done

    if [ -z "${db}" ] || [ "${valid_db}" != "true" ]; then
        echo "ERROR: Valid database name required"
        echo "Valid options: ${DATABASES[*]}"
        echo ""
        usage
    fi

    # Check tools
    check_tools

    # List available backups and find the one to restore
    echo ""
    list_backups "${db}"

    local backup_path
    backup_path="$(find_backup "${db}" "${timestamp}")"
    echo ""
    log_info "Selected backup: ${backup_path}"

    # Pre-flight integrity check
    verify_backup_integrity "${backup_path}" || exit 1

    # Perform restore
    restore_database "${db}" "${backup_path}" "${force}" "${dry_run}"
}

# --- Run ---------------------------------------------------------------------
main "$@"
