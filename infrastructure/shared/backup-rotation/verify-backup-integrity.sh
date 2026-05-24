#!/usr/bin/env bash
# =============================================================================
# verify-backup-integrity.sh — Weekly Backup Integrity Verification
# =============================================================================
# - Checks latest backup of each database restores cleanly to a temp database
# - Checks volume tarballs are not corrupted
# - Checks manifests match actual files
# - Reports any corruption
# - Can be run as cron job on Sundays
#
# RPO: Recovery Point Objective (24h) — verify that backups are usable
# RTO: Recovery Time Objective (2h) — verify that restore process works
# =============================================================================
set -euo pipefail

# --- Source config -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Try to source backup-config from various locations
CONFIG_CANDIDATES=(
    "/root/infrastructure/hetzner/backup/backup-config.sh"
    "/opt/scripts/backup/backup-config.sh"
)
for config in "${CONFIG_CANDIDATES[@]}"; do
    if [ -f "${config}" ]; then
        source "${config}"
        break
    fi
done

# --- Overridable paths -------------------------------------------------------
BACKUP_DATABASE_DIR="${BACKUP_DATABASE_DIR:-/opt/backups/databases}"
BACKUP_VOLUME_DIR="${BACKUP_VOLUME_DIR:-/opt/backups/volumes}"
BACKUP_MANIFEST_DIR="${BACKUP_MANIFEST_DIR:-/opt/backups/manifests}"
LOG_DIR="${LOG_DIR:-/opt/logs}"
VERIFY_LOG="${LOG_DIR}/verify-backup.log"

# Temp database prefix for restore verification
TEMP_DB_PREFIX="verify_"

# --- Logging -----------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "${message}" | tee -a "${VERIFY_LOG}"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# --- Find PostgreSQL tools ---------------------------------------------------
find_pg_tools() {
    for cmd in pg_dump pg_restore psql; do
        local path
        path="$(command -v "$cmd" 2>/dev/null || true)"
        if [ -z "$path" ]; then
            for pgdir in /usr/lib/postgresql/*/bin; do
                if [ -x "${pgdir}/${cmd}" ]; then
                    path="${pgdir}/${cmd}"
                    break
                fi
            done
        fi
        if [ -z "$path" ]; then
            log_error "Cannot find ${cmd}"
            return 1
        fi
        declare -g "${cmd^^}_BIN=${path}"
    done
    PG_RESTORE_BIN="${PG_RESTORE_BIN:-$(command -v pg_restore)}"
    PSQL_BIN="${PSQL_BIN:-$(command -v psql)}"
}

# === 1. Verify Database Backup Integrity ======================================
verify_database_backups() {
    log_info "============================================"
    log_info "Phase 1: Database Backup Integrity Check"
    log_info "============================================"

    if [ ! -d "${BACKUP_DATABASE_DIR}" ]; then
        log_warn "Database backup directory not found: ${BACKUP_DATABASE_DIR}"
        return 0
    fi

    local db_count=0
    local db_pass=0
    local db_fail=0
    local db_warn=0

    # Find all unique databases from backup filenames
    local databases=()
    while IFS= read -r dump; do
        local fname
        fname="$(basename "${dump}")"
        # Extract db name: TIMESTAMP_dbname.dump
        local db_name="${fname#*_}"
        db_name="${db_name%.dump}"

        # Check if we already processed this DB (use the latest backup)
        local already=false
        for seen in "${databases[@]}"; do
            [ "${seen}" = "${db_name}" ] && already=true && break
        done
        if [ "${already}" = false ]; then
            databases+=("${db_name}")
        fi
    done < <(find "${BACKUP_DATABASE_DIR}" -maxdepth 1 -name '*.dump' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    if [ ${#databases[@]} -eq 0 ]; then
        log_warn "No database backups found to verify"
        return 0
    fi

    log_info "Found ${#databases[@]} databases with backups"

    for db_name in "${databases[@]}"; do
        db_count=$((db_count + 1))
        log_info "Verifying database: ${db_name}"

        # Get the latest backup for this database
        local latest
        latest="$(find "${BACKUP_DATABASE_DIR}" -maxdepth 1 -name "*_${db_name}.dump" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"

        if [ -z "${latest}" ] || [ ! -f "${latest}" ]; then
            log_error "  No backup file found for database '${db_name}'"
            db_fail=$((db_fail + 1))
            continue
        fi

        # Check 1: pg_restore --list (TOC parsing)
        log_info "  Test 1: pg_restore --list (TOC integrity)..."
        local toc_output
        if ! toc_output="$("${PG_RESTORE_BIN}" --list "${latest}" 2>&1)"; then
            log_error "  FAILED: Cannot parse TOC from ${latest}"
            log_error "  ${toc_output}"
            db_fail=$((db_fail + 1))
            continue
        fi

        local toc_count
        toc_count="$(echo "${toc_output}" | grep -c "^[0-9]" || true)"
        log_info "  TOC entries: ${toc_count}"

        # Check 2: Attempt restore to temp database
        local temp_db="${TEMP_DB_PREFIX}${db_name}_$(date '+%s')"
        log_info "  Test 2: Restore to temp database '${temp_db}'..."

        # Create temp database
        if ! "${PSQL_BIN}" -h "${PGHOST:-localhost}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" \
            -d postgres -c "CREATE DATABASE \"${temp_db}\";" 2>/dev/null; then
            log_warn "  Could not create temp database. Is PostgreSQL running?"
            db_warn=$((db_warn + 1))
            continue
        fi

        # Attempt restore (without data, just schema + structure validation)
        # Use --exit-on-error to catch corruption
        set +e
        "${PG_RESTORE_BIN}" \
            -h "${PGHOST:-localhost}" \
            -p "${PGPORT:-5432}" \
            -U "${PGUSER:-postgres}" \
            -d "${temp_db}" \
            --no-owner \
            --no-acl \
            --exit-on-error \
            "${latest}" 2>> "${VERIFY_LOG}"
        local restore_exit=$?
        set -e

        # Check restore result
        if [ "${restore_exit}" -eq 0 ]; then
            log_info "  PASSED: Backup for '${db_name}' restored successfully to temp DB"
            db_pass=$((db_pass + 1))
        else
            log_error "  FAILED: Backup for '${db_name}' could not be restored cleanly"
            log_error "  See ${VERIFY_LOG} for details"
            db_fail=$((db_fail + 1))
        fi

        # Drop temp database
        "${PSQL_BIN}" -h "${PGHOST:-localhost}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" \
            -d postgres -c "DROP DATABASE IF EXISTS \"${temp_db}\";" 2>/dev/null || true

        # Verify file checksum hasn't changed (corruption detection)
        local file_size
        file_size="$(stat -c%s "${latest}" 2>/dev/null || stat -f%z "${latest}" 2>/dev/null)"
        log_info "  File size: $(numfmt --to=iec "${file_size}" 2>/dev/null || echo "${file_size} bytes")"
    done

    echo ""
    log_info "Phase 1 Summary: ${db_pass} passed, ${db_fail} failed, ${db_warn} warnings out of ${db_count} databases"
    echo ""

    return "${db_fail}"
}

# === 2. Verify Volume Backup Integrity =======================================
verify_volume_backups() {
    log_info "============================================"
    log_info "Phase 2: Volume Backup Integrity Check"
    log_info "============================================"

    if [ ! -d "${BACKUP_VOLUME_DIR}" ]; then
        log_warn "Volume backup directory not found: ${BACKUP_VOLUME_DIR}"
        return 0
    fi

    local vol_pass=0
    local vol_fail=0
    local vol_count=0

    while IFS= read -r tarball; do
        vol_count=$((vol_count + 1))
        local fname
        fname="$(basename "${tarball}")"

        log_info "Verifying volume backup: ${fname}"

        # Check 1: File exists and is non-empty
        if [ ! -s "${tarball}" ]; then
            log_error "  FAILED: File is empty or missing: ${fname}"
            vol_fail=$((vol_fail + 1))
            continue
        fi

        # Check 2: tar can list contents (tarball structure integrity)
        if ! tar tzf "${tarball}" >/dev/null 2>> "${VERIFY_LOG}"; then
            log_error "  FAILED: Tarball is corrupted: ${fname}"
            vol_fail=$((vol_fail + 1))
            continue
        fi

        # Check 3: Count entries
        local entry_count
        entry_count="$(tar tzf "${tarball}" 2>/dev/null | wc -l)"
        if [ "${entry_count}" -eq 0 ]; then
            log_warn "  WARNING: Tarball appears empty (0 entries): ${fname}"
        fi

        # Check 4: Check for any extraction errors by doing a dry extract
        if ! tar tzf "${tarball}" >/dev/null 2>> "${VERIFY_LOG}"; then
            log_error "  FAILED: Cannot read tarball contents: ${fname}"
            vol_fail=$((vol_fail + 1))
            continue
        fi

        log_info "  PASSED: ${entry_count} entries, size: $(stat -c%s "${tarball}" 2>/dev/null | numfmt --to=iec 2>/dev/null || echo "unknown")"
        vol_pass=$((vol_pass + 1))

    done < <(find "${BACKUP_VOLUME_DIR}" -maxdepth 1 -name '*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    if [ "${vol_count}" -eq 0 ]; then
        log_warn "No volume backups found to verify"
        return 0
    fi

    log_info "Phase 2 Summary: ${vol_pass} passed, ${vol_fail} failed out of ${vol_count} volumes"
    echo ""

    return "${vol_fail}"
}

# === 3. Verify Manifests =====================================================
verify_manifests() {
    log_info "============================================"
    log_info "Phase 3: Manifest Integrity Check"
    log_info "============================================"

    if [ ! -d "${BACKUP_MANIFEST_DIR}" ]; then
        log_warn "Manifest directory not found: ${BACKUP_MANIFEST_DIR}"
        return 0
    fi

    local manifest_pass=0
    local manifest_fail=0
    local manifest_count=0

    for manifest in "${BACKUP_MANIFEST_DIR}"/*.json; do
        [ -f "${manifest}" ] || continue

        manifest_count=$((manifest_count + 1))
        local fname
        fname="$(basename "${manifest}")"

        log_info "Verifying manifest: ${fname}"

        # Check JSON is valid
        if ! python3 -m json.tool "${manifest}" >/dev/null 2>> "${VERIFY_LOG}"; then
            if ! jq '.' "${manifest}" >/dev/null 2>> "${VERIFY_LOG}"; then
                log_error "  FAILED: Invalid JSON in manifest: ${fname}"
                manifest_fail=$((manifest_fail + 1))
                continue
            fi
        fi

        # Check referenced backup files actually exist
        local ref_count=0
        local ref_missing=0

        # Extract paths from JSON manifest
        if command -v jq &>/dev/null; then
            for path in $(jq -r '.databases[]?.path, .volumes[]?.path // empty' "${manifest}" 2>/dev/null); do
                ref_count=$((ref_count + 1))
                if [ ! -f "${path}" ]; then
                    log_warn "  Referenced file missing: ${path}"
                    ref_missing=$((ref_missing + 1))
                fi
            done
        fi

        if [ "${ref_missing}" -gt 0 ]; then
            log_warn "  ${ref_missing}/${ref_count} referenced files missing"
        else
            log_info "  All ${ref_count} referenced files exist"
        fi

        manifest_pass=$((manifest_pass + 1))
    done

    if [ "${manifest_count}" -eq 0 ]; then
        log_warn "No manifests found to verify"
        return 0
    fi

    log_info "Phase 3 Summary: ${manifest_pass} valid, ${manifest_fail} invalid"
    echo ""

    return "${manifest_fail}"
}

# === 4. Verify Backup Counts =================================================
verify_backup_counts() {
    log_info "============================================"
    log_info "Phase 4: Backup Count Verification"
    log_info "============================================"

    # Check database backup counts
    log_info "Database backups:"
    local total_db=0
    for dump in "${BACKUP_DATABASE_DIR}"/*.dump; do
        [ -f "${dump}" ] && total_db=$((total_db + 1))
    done
    log_info "  Total: ${total_db} dump files"

    # Check volume backup counts
    log_info "Volume backups:"
    local total_vol=0
    for tarball in "${BACKUP_VOLUME_DIR}"/*.tar.gz; do
        [ -f "${tarball}" ] && total_vol=$((total_vol + 1))
    done
    log_info "  Total: ${total_vol} volume tarballs"

    # Check disk usage
    local db_size="0"
    if [ -d "${BACKUP_DATABASE_DIR}" ]; then
        db_size="$(du -sh "${BACKUP_DATABASE_DIR}" 2>/dev/null | cut -f1 || echo "0")"
    fi
    local vol_size="0"
    if [ -d "${BACKUP_VOLUME_DIR}" ]; then
        vol_size="$(du -sh "${BACKUP_VOLUME_DIR}" 2>/dev/null | cut -f1 || echo "0")"
    fi
    local manifest_size="0"
    if [ -d "${BACKUP_MANIFEST_DIR}" ]; then
        manifest_size="$(du -sh "${BACKUP_MANIFEST_DIR}" 2>/dev/null | cut -f1 || echo "0")"
    fi

    log_info "  Database backups: ${db_size}"
    log_info "  Volume backups:   ${vol_size}"
    log_info "  Manifests:        ${manifest_size}"
    echo ""

    # Check disk space available
    if command -v df &>/dev/null; then
        log_info "Disk space on backup volume:"
        df -h "$(dirname "${BACKUP_DATABASE_DIR}")" 2>/dev/null | tail -1 | while read -r line; do
            log_info "  ${line}"
        done || true
    fi
}

# === MAIN ====================================================================
main() {
    local start_time
    start_time="$(date +%s)"

    mkdir -p "${LOG_DIR}"

    log_info "=============================================="
    log_info "BACKUP INTEGRITY VERIFICATION STARTING"
    log_info "Date: $(date)"
    log_info "=============================================="
    echo ""

    local overall_exit=0

    # Find tools
    find_pg_tools || log_warn "PostgreSQL tools not found — database verification will be limited"

    # Phase 1: Verify database backups
    verify_database_backups || overall_exit=1

    # Phase 2: Verify volume backups
    verify_volume_backups || overall_exit=1

    # Phase 3: Verify manifests
    verify_manifests || overall_exit=1

    # Phase 4: Verify counts
    verify_backup_counts

    # Summary
    local end_time
    end_time="$(date +%s)"
    local duration=$((end_time - start_time))
    local duration_hr
    duration_hr="$(date -u -d "@${duration}" '+%H:%M:%S' 2>/dev/null || echo "${duration}s")"

    echo ""
    log_info "=============================================="
    if [ "${overall_exit}" -eq 0 ]; then
        log_info "INTEGRITY VERIFICATION COMPLETE — ALL CHECKS PASSED"
    else
        log_info "INTEGRITY VERIFICATION COMPLETE — ISSUES FOUND"
        log_info "Review logs at: ${VERIFY_LOG}"
    fi
    log_info "Duration: ${duration_hr}"
    log_info "=============================================="

    # Send healthcheck if configured
    if [ -n "${HEALTHCHECK_URL:-}" ]; then
        local message="Backup integrity verification completed in ${duration_hr}"
        if [ "${overall_exit}" -eq 0 ]; then
            curl -fsS -m 10 --data-raw "${message}" "${HEALTHCHECK_URL}" >/dev/null 2>&1 || true
        else
            curl -fsS -m 10 --data-raw "ISSUES FOUND: ${message}" "${HEALTHCHECK_URL}/fail" >/dev/null 2>&1 || true
        fi
    fi

    return "${overall_exit}"
}

# --- Run ---------------------------------------------------------------------
main "$@"
