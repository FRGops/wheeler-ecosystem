#!/usr/bin/env bash
# =============================================================================
# database-backup.sh — PostgreSQL Backup Script (Hetzner CPX51)
# =============================================================================
# Backs up: prediction_radar, ravynai, healthchecks, superset
# Format: pg_dump custom format (compressed, parallel-restore capable)
# Output: /opt/backups/databases/YYYYMMDD_HHMMSS_dbname.dump
# Retention: 7 daily, 4 weekly (Sunday), 3 monthly (1st of month)
# =============================================================================
set -euo pipefail

# --- Source config ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/backup-config.sh" ]; then
    source "${SCRIPT_DIR}/backup-config.sh"
else
    echo "FATAL: backup-config.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

# --- Ensure required directories exist ---------------------------------------
setup_directories() {
    mkdir -p "${BACKUP_DATABASE_DIR}"
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

# --- Healthcheck ping --------------------------------------------------------
healthcheck_ping() {
    local status="$1"  # "" for start, "/fail" for failure
    local message="$2"

    if [ -n "${HEALTHCHECK_URL}" ]; then
        local ping_url="${HEALTHCHECK_URL}${status}"
        if [ -n "$message" ]; then
            curl -fsS -m 10 --data-raw "${message}" "${ping_url}" >/dev/null 2>&1 || true
        else
            curl -fsS -m 10 "${ping_url}" >/dev/null 2>&1 || true
        fi
    fi
}

# --- Find PostgreSQL tools ---------------------------------------------------
find_pg_tools() {
    # Try common locations for pg_dump and pg_restore
    for cmd in pg_dump pg_restore psql; do
        local path
        path="$(command -v "$cmd" 2>/dev/null || true)"
        if [ -z "$path" ]; then
            # Search in PostgreSQL version directories
            for pgdir in /usr/lib/postgresql/*/bin; do
                if [ -x "${pgdir}/${cmd}" ]; then
                    path="${pgdir}/${cmd}"
                    break
                fi
            done
        fi
        if [ -z "$path" ]; then
            log_error "Cannot find ${cmd} — is PostgreSQL client installed?"
            return 1
        fi
        declare -g "${cmd^^}_BIN=${path}"
    done

    PG_DUMP_BIN="${PG_DUMP_BIN:-$(command -v pg_dump)}"
    PG_RESTORE_BIN="${PG_RESTORE_BIN:-$(command -v pg_restore)}"
    PSQL_BIN="${PSQL_BIN:-$(command -v psql)}"
}

# --- Verify database connectivity -------------------------------------------
check_db_connectivity() {
    log_info "Checking PostgreSQL connectivity..."
    "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres -c "SELECT 1;" >/dev/null 2>&1 || {
        log_error "Cannot connect to PostgreSQL at ${PGHOST}:${PGPORT} as ${PGUSER}"
        return 1
    }
    log_info "PostgreSQL connection OK"
}

# --- Verify database exists --------------------------------------------------
check_database_exists() {
    local db="$1"
    "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname='${db}';" 2>/dev/null | grep -q 1
}

# --- Backup a single database ------------------------------------------------
backup_database() {
    local db="$1"
    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local backup_path="${BACKUP_DATABASE_DIR}/${timestamp}_${db}.dump"
    local backup_info_path="${backup_path}.info"

    log_info "Starting backup of database: ${db} → ${backup_path}"

    # Verify database exists
    if ! check_database_exists "${db}"; then
        log_warn "Database '${db}' does not exist — skipping"
        return 0
    fi

    # Get database size before backup
    local db_size
    db_size="$("${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres -tAc \
        "SELECT pg_size_pretty(pg_database_size('${db}'));" 2>/dev/null || echo "unknown")"
    log_info "Database '${db}' size: ${db_size}"

    # Perform the dump in custom format (compressed, parallel-restore capable)
    "${PG_DUMP_BIN}" \
        -h "${PGHOST}" \
        -p "${PGPORT}" \
        -U "${PGUSER}" \
        -d "${db}" \
        -F c \          # custom format (compressed, parallel restore)
        -v \            # verbose
        --no-owner \    # don't dump ownership (safer for restore)
        --no-acl \      # skip ACLs (handled separately)
        -f "${backup_path}" 2>> "${BACKUP_LOG}"

    local dump_exit=$?
    if [ $dump_exit -ne 0 ]; then
        log_error "pg_dump failed for database '${db}' (exit code: ${dump_exit})"
        rm -f "${backup_path}"
        return 1
    fi

    # Verify dump integrity
    log_info "Verifying dump integrity for '${db}'..."
    verify_dump_integrity "${backup_path}" || {
        log_error "Integrity check FAILED for ${backup_path}"
        rm -f "${backup_path}"
        return 1
    }

    # Get backup file size
    local file_size
    file_size="$(stat -c%s "${backup_path}" 2>/dev/null || stat -f%z "${backup_path}" 2>/dev/null)"
    local file_size_hr
    file_size_hr="$(numfmt --to=iec "${file_size}" 2>/dev/null || echo "${file_size} bytes")"
    log_info "Backup of '${db}' completed: ${file_size_hr} (${file_size} bytes)"

    # Write backup info file
    cat > "${backup_info_path}" <<-EOF
database=${db}
timestamp=${timestamp}
backup_path=${backup_path}
file_size_bytes=${file_size}
file_size_human=${file_size_hr}
pg_dump_exit_code=${dump_exit}
verification=PASSED
EOF

    log_info "Successfully backed up '${db}'"
    return 0
}

# --- Verify dump integrity ---------------------------------------------------
verify_dump_integrity() {
    local dump_path="$1"

    if [ ! -f "${dump_path}" ]; then
        log_error "Dump file not found: ${dump_path}"
        return 1
    fi

    # pg_restore --list reads the TOC without actually restoring
    # This validates the dump file header and structure
    if ! "${PG_RESTORE_BIN}" --list "${dump_path}" >/dev/null 2>> "${BACKUP_LOG}"; then
        log_error "Integrity verification failed: pg_restore --list could not parse ${dump_path}"
        return 1
    fi

    # Also check the dump is not empty (has at least some TOC entries)
    local toc_count
    toc_count="$("${PG_RESTORE_BIN}" --list "${dump_path}" 2>/dev/null | grep -c "^[0-9]" || true)"
    if [ "${toc_count}" -eq 0 ]; then
        log_warn "Dump ${dump_path} has 0 TOC entries — possible empty database"
        # Not necessarily a failure; some databases may legitimately be empty
    fi

    log_info "Integrity verified: ${dump_path} (${toc_count} TOC entries)"
    return 0
}

# --- Create backup manifest --------------------------------------------------
create_manifest() {
    local manifest_path="${BACKUP_DATABASE_DIR}/manifest.txt"

    log_info "Creating backup manifest at ${manifest_path}"

    {
        echo "============================================"
        echo "Hetzner CPX51 Database Backup Manifest"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Host: $(hostname)"
        echo "PostgreSQL Host: ${PGHOST}:${PGPORT}"
        echo "============================================"
        echo ""
        echo "Backup Directory: ${BACKUP_DATABASE_DIR}"
        echo ""

        local total_size=0
        local count=0

        # Sort by timestamp (newest first)
        for dump in $(find "${BACKUP_DATABASE_DIR}" -maxdepth 1 -name '*.dump' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-); do
            local fname
            fname="$(basename "${dump}")"
            local fsize
            fsize="$(stat -c%s "${dump}" 2>/dev/null || stat -f%z "${dump}" 2>/dev/null)"
            local fsize_hr
            fsize_hr="$(numfmt --to=iec "${fsize}" 2>/dev/null || echo "${fsize} bytes")"
            local fdate
            fdate="$(date -d "@$(stat -c%Y "${dump}" 2>/dev/null || stat -f%m "${dump}" 2>/dev/null)" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"

            echo "  ${fname}  |  ${fsize_hr}  |  ${fdate}"
            total_size=$((total_size + fsize))
            count=$((count + 1))
        done

        echo ""
        echo "Total Backups: ${count}"
        echo "Total Size: $(numfmt --to=iec "${total_size}" 2>/dev/null || echo "${total_size} bytes")"
        echo "============================================"
    } > "${manifest_path}"

    log_info "Manifest created: ${count} backups, total $(numfmt --to=iec "${total_size}" 2>/dev/null || echo "${total_size} bytes")"
}

# --- Apply retention policy --------------------------------------------------
apply_retention() {
    log_info "Applying retention policy..."

    local keep_count="${RETENTION_DAILY_COUNT:-7}"
    local keep_weekly="${RETENTION_WEEKLY_COUNT:-4}"
    local keep_monthly="${RETENTION_MONTHLY_COUNT:-3}"

    # For each database, apply rotation
    for db in "${DATABASES[@]}"; do
        # Skip databases that don't exist
        if ! ls "${BACKUP_DATABASE_DIR}/"*"_${db}.dump" >/dev/null 2>&1; then
            continue
        fi

        log_info "Rotating backups for database: ${db}"

        # --- Monthly retention (1st of month) ---
        local monthly_keep=0
        for dump in $(find "${BACKUP_DATABASE_DIR}" -maxdepth 1 -name "*_${db}.dump" \
            -newer "${BACKUP_DATABASE_DIR}/"-mtime -90 2>/dev/null | sort -r); do
            local dump_date
            dump_date="$(date -r "${dump}" '+%d" 2>/dev/null || echo "01")"
            local dom
            dom="$(echo "${dump_date}" | cut -d' ' -f1)"
            if [ "${dom}" = "01" ]; then
                monthly_keep=$((monthly_keep + 1))
                if [ "${monthly_keep}" -gt "${keep_monthly}" ]; then
                    log_info "Removing monthly backup (past retention): $(basename "${dump}")"
                    rm -f "${dump}" "${dump}.info" 2>/dev/null || true
                fi
            fi
        done

        # --- Weekly retention (Sunday) ---
        local weekly_keep=0
        for dump in $(find "${BACKUP_DATABASE_DIR}" -maxdepth 1 -name "*_${db}.dump" \
            -mtime -28 2>/dev/null | sort -r); do
            local dump_dow
            dump_dow="$(date -r "${dump}" '+%u' 2>/dev/null || echo "7")"
            if [ "${dump_dow}" = "7" ]; then
                weekly_keep=$((weekly_keep + 1))
                if [ "${weekly_keep}" -gt "${keep_weekly}" ]; then
                    log_info "Removing weekly backup (past retention): $(basename "${dump}")"
                    rm -f "${dump}" "${dump}.info" 2>/dev/null || true
                fi
            fi
        done

        # --- Daily retention ---
        # Keep only the most recent N daily backups (excluding weekly/monthly which are preserved above)
        local all_dumps
        mapfile -t all_dumps < <(find "${BACKUP_DATABASE_DIR}" -maxdepth 1 -name "*_${db}.dump" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

        local daily_count=0
        for dump in "${all_dumps[@]}"; do
            daily_count=$((daily_count + 1))
            if [ "${daily_count}" -gt "${keep_count}" ]; then
                local dump_dow
                dump_dow="$(date -r "${dump}" '+%u' 2>/dev/null || echo "0")"
                local dump_dom
                dump_dom="$(date -r "${dump}" '+%d' 2>/dev/null || echo "99")"
                # Don't delete Sunday weekly backups or 1st-of-month monthly backups
                if [ "${dump_dow}" = "7" ] || [ "${dump_dom}" = "01" ]; then
                    continue
                fi
                log_info "Removing daily backup (past retention): $(basename "${dump}")"
                rm -f "${dump}" "${dump}.info" 2>/dev/null || true
            fi
        done
    done

    log_info "Retention cleanup complete"
}

# --- Cleanup old temp files --------------------------------------------------
cleanup_temp() {
    if [ -d "${BACKUP_TEMP_DIR}" ]; then
        find "${BACKUP_TEMP_DIR}" -type f -mtime +1 -delete 2>/dev/null || true
    fi
}

# --- Main --------------------------------------------------------------------
main() {
    local start_time
    start_time="$(date +%s)"

    log_info "=============================================="
    log_info "Database Backup Starting"
    log_info "Server: Hetzner CPX51 (${HOSTNAME})"
    log_info "Host: ${PGHOST}:${PGPORT}"
    log_info "=============================================="

    # Send healthcheck start ping
    healthcheck_ping "" "Database backup started at $(date)"

    # Setup
    setup_directories
    find_pg_tools
    check_db_connectivity || {
        healthcheck_ping "/fail" "Database backup failed: cannot connect to PostgreSQL"
        exit 1
    }

    # Backup each database
    local exit_code=0
    local success_count=0
    local fail_count=0

    for db in "${DATABASES[@]}"; do
        if backup_database "${db}"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
            exit_code=1
        fi
    done

    # Create manifest
    create_manifest

    # Apply retention
    apply_retention

    # Cleanup
    cleanup_temp

    # Summary
    local end_time
    end_time="$(date +%s)"
    local duration=$((end_time - start_time))
    local duration_hr
    duration_hr="$(date -u -d "@${duration}" '+%H:%M:%S' 2>/dev/null || echo "${duration}s")"

    log_info "=============================================="
    log_info "Database Backup Complete"
    log_info "Duration: ${duration_hr}"
    log_info "Successful: ${success_count}, Failed: ${fail_count}"
    log_info "=============================================="

    # Send healthcheck
    if [ "${exit_code}" -eq 0 ]; then
        healthcheck_ping "" "Database backup completed successfully in ${duration_hr}. ${success_count} databases backed up."
    else
        healthcheck_ping "/fail" "Database backup completed with ${fail_count} failure(s) in ${duration_hr}"
    fi

    return "${exit_code}"
}

# --- Run ---------------------------------------------------------------------
main "$@"
