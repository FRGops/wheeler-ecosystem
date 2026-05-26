#!/usr/bin/env bash
# =============================================================================
# backup-postgres.sh — PostgreSQL Backup for Wheeler Ecosystem
# =============================================================================
# Backs up all non-template databases from:
#   1. frgops-standby (localhost:5433)
#   2. aiops-ravynai-postgres (localhost:5434)
#   3. prediction-radar-app-db (Docker exec)
# Output: /root/backups/postgres/<db>-<timestamp>.sql.gz
# Retention: last 7 daily backups, last 4 weekly (Sunday)
# Log: /root/backups/postgres/backup.log
# =============================================================================
set -o pipefail
set -o nounset

readonly BACKUP_ROOT="/root/backups/postgres"
readonly TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
readonly RETENTION_DAILY=7
readonly RETENTION_WEEKLY=4

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
    touch "${log_file}"
    log_info "=============================================="
    log_info "PostgreSQL Backup Started"
    log_info "Backup root: ${BACKUP_ROOT}"
    log_info "=============================================="
}

# ---- Verify a dump can be read back ----
verify_dump() {
    local dump_path="$1"
    if [[ ! -f "${dump_path}" ]]; then
        log_error "Dump file not found: ${dump_path}"
        return 1
    fi
    local size
    size="$(stat -c%s "${dump_path}" 2>/dev/null || echo 0)"
    if [[ "${size}" -lt 20 ]]; then
        log_error "Dump too small (${size} bytes): ${dump_path}"
        return 1
    fi
    # Verify gzip integrity
    if ! gunzip -t "${dump_path}" 2>/dev/null; then
        log_error "gzip integrity check FAILED: ${dump_path}"
        return 1
    fi
    # For .sql.gz, check first line contains SQL
    if gunzip -c "${dump_path}" 2>/dev/null | head -1 | grep -qE '^--|^CREATE|^SET|^SELECT|BEGIN|START'; then
        log_info "Content verification passed: ${dump_path} (${size} bytes)"
        return 0
    fi
    log_warn "Content header unrecognized — may be custom format: ${dump_path}"
    return 0
}

# ---- Extract POSTGRES_PASSWORD from a Docker container ----
get_container_pg_password() {
    local container="$1"
    docker inspect "${container}" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
        | grep '^POSTGRES_PASSWORD=' | head -1 | cut -d'=' -f2-
}

# ---- Dump a database via localhost pg_dump ----
dump_localhost_db() {
    local host="$1"
    local port="$2"
    local user="$3"
    local db="$4"
    local password="$5"
    local outfile="${BACKUP_ROOT}/${db}-${TIMESTAMP}.sql.gz"

    log_info "Dumping ${db} from ${host}:${port} as ${user}..."

    PGPASSWORD="${password}" pg_dump \
        -h "${host}" \
        -p "${port}" \
        -U "${user}" \
        -d "${db}" \
        --no-owner \
        --no-acl \
        2>>"${log_file}" \
        | gzip > "${outfile}"

    local rc=${PIPESTATUS[0]}
    if [[ ${rc} -ne 0 ]]; then
        log_error "pg_dump failed for ${db} on ${host}:${port} (exit code: ${rc})"
        rm -f "${outfile}"
        return 1
    fi

    if verify_dump "${outfile}"; then
        local size
        size="$(du -h "${outfile}" | cut -f1)"
        log_info "SUCCESS: ${db} -> ${outfile} (${size})"
        return 0
    else
        rm -f "${outfile}"
        return 1
    fi
}

# ---- Dump a single database via Docker exec pg_dump ----
dump_single_docker_db() {
    local container="$1"
    local user="$2"
    local db="$3"
    local outfile="${BACKUP_ROOT}/${db}-${TIMESTAMP}.sql.gz"

    log_info "Dumping ${db} from Docker container ${container} as ${user}..."
    docker exec "${container}" pg_dump -U "${user}" -d "${db}" --no-owner --no-acl 2>>"${log_file}" \
        | gzip > "${outfile}"

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "pg_dump failed for ${db} in ${container}"
        rm -f "${outfile}"
        return 1
    fi

    if verify_dump "${outfile}"; then
        local size
        size="$(du -h "${outfile}" | cut -f1)"
        log_info "SUCCESS: ${db} -> ${outfile} (${size})"
        return 0
    else
        rm -f "${outfile}"
        return 1
    fi
}

# ---- Dump a database via Docker exec ----
dump_docker_db() {
    local container="$1"
    local user="$2"
    local db="$3"
    local outfile="${BACKUP_ROOT}/${db}-${TIMESTAMP}.sql.gz"

    log_info "Dumping ${db} from Docker container ${container} as ${user}..."

    # List databases in container
    local databases
    if ! databases=$(docker exec "${container}" psql -U "${user}" -d postgres -tAc \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres' ORDER BY datname;" 2>/dev/null); then
        # Fallback: try listing from template1
        databases=$(docker exec "${container}" psql -U "${user}" -d template1 -tAc \
            "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>/dev/null || true)
    fi

    if [[ -z "${databases}" ]]; then
        log_warn "No user databases found in container ${container}"
        return 0
    fi

    local all_ok=true
    while IFS= read -r db_name; do
        [[ -z "${db_name}" ]] && continue
        local db_outfile="${BACKUP_ROOT}/${db_name}-${TIMESTAMP}.sql.gz"

        log_info "  Dumping database: ${db_name} from ${container}"

        if docker exec "${container}" pg_dump -U "${user}" -d "${db_name}" --no-owner --no-acl 2>>"${log_file}" \
            | gzip > "${db_outfile}"; then
            if verify_dump "${db_outfile}"; then
                local size
                size="$(du -h "${db_outfile}" | cut -f1)"
                log_info "  SUCCESS: ${db_name} -> ${db_outfile} (${size})"
            else
                log_error "  Verification failed: ${db_name}"
                rm -f "${db_outfile}"
                all_ok=false
            fi
        else
            log_error "  pg_dump failed for ${db_name} in ${container}"
            rm -f "${db_outfile}"
            all_ok=false
        fi
    done <<< "${databases}"

    ${all_ok} && return 0 || return 1
}

# ---- Retention cleanup ----
apply_retention() {
    log_info "Applying retention: keep ${RETENTION_DAILY} daily, ${RETENTION_WEEKLY} weekly (Sunday)"

    # Get list of all backup files sorted newest first
    local all_files
    mapfile -t all_files < <(find "${BACKUP_ROOT}" -maxdepth 1 -name '*.sql.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    local count=0
    local weeklies_kept=0

    for f in "${all_files[@]}"; do
        count=$((count + 1))
        local fname
        fname="$(basename "${f}")"

        # Check if this is a Sunday backup (from filename: YYYYMMDD)
        local date_part
        date_part="$(echo "${fname}" | grep -oP '\d{8}' | head -1 || true)"
        local is_sunday=false
        if [[ -n "${date_part}" ]]; then
            local dow
            dow="$(date -d "${date_part}" '+%u' 2>/dev/null || echo "0")"
            [[ "${dow}" == "7" ]] && is_sunday=true
        fi

        if ${is_sunday} && [[ ${weeklies_kept} -lt ${RETENTION_WEEKLY} ]]; then
            weeklies_kept=$((weeklies_kept + 1))
            log_info "  KEEP (weekly #${weeklies_kept}): ${fname}"
            continue
        fi

        if [[ ${count} -gt ${RETENTION_DAILY} ]]; then
            log_info "  REMOVE (past retention): ${fname}"
            rm -f "${f}"
        else
            log_info "  KEEP (daily #${count}): ${fname}"
        fi
    done

    log_info "Retention cleanup complete"
}

# ---- Main ----
main() {
    local overall_ok=true
    local success_count=0
    local fail_count=0
    local skip_count=0

    setup

    # ---- 1. frgops-standby (localhost:5433) ----
    log_info "PHASE 1: frgops-standby (localhost:5433)"
    local frgops_password
    frgops_password="$(get_container_pg_password "frgops-standby" || echo "")"
    if pg_isready -h localhost -p 5433 -q 2>/dev/null; then
        # Discover databases
        local frgops_dbs
        frgops_dbs=$(PGPASSWORD="${frgops_password}" psql -h localhost -p 5433 -U frgops -d postgres -tAc \
            "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres' ORDER BY datname;" 2>/dev/null || true)
        if [[ -n "${frgops_dbs}" ]]; then
            while IFS= read -r db; do
                [[ -z "${db}" ]] && continue
                if dump_localhost_db "localhost" "5433" "frgops" "${db}" "${frgops_password}"; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                    overall_ok=false
                fi
            done <<< "${frgops_dbs}"
        else
            log_warn "No user databases found on localhost:5433 (password extraction may have failed)"
            skip_count=$((skip_count + 1))
        fi
    else
        log_warn "localhost:5433 not reachable — skipping frgops-standby"
        skip_count=$((skip_count + 1))
    fi

    # ---- 2. aiops-ravynai-postgres (via Docker exec — port 5434 not responding on host) ----
    log_info "PHASE 2: aiops-ravynai-postgres (Docker exec)"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^aiops-ravynai-postgres$'; then
        # Discover databases via docker exec
        local ravynai_dbs
        ravynai_dbs=$(docker exec aiops-ravynai-postgres psql -U ravynai -d postgres -tAc \
            "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres' ORDER BY datname;" 2>/dev/null || true)
        if [[ -n "${ravynai_dbs}" ]]; then
            while IFS= read -r db; do
                [[ -z "${db}" ]] && continue
                if dump_single_docker_db "aiops-ravynai-postgres" "ravynai" "${db}"; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                    overall_ok=false
                fi
            done <<< "${ravynai_dbs}"
        else
            log_warn "No user databases found in aiops-ravynai-postgres"
            skip_count=$((skip_count + 1))
        fi
    else
        log_warn "aiops-ravynai-postgres container not running — skipping"
        skip_count=$((skip_count + 1))
    fi

    # ---- 3. prediction-radar-app-db (Docker exec) ----
    log_info "PHASE 3: prediction-radar-app-db (Docker exec)"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^prediction-radar-app-db$'; then
        if dump_docker_db "prediction-radar-app-db" "prediction_radar" "prediction_radar"; then
            local radar_files
            radar_files=$(find "${BACKUP_ROOT}" -maxdepth 1 -name "prediction_radar-${TIMESTAMP}.sql.gz" 2>/dev/null | wc -l)
            if [[ ${radar_files} -gt 0 ]]; then
                success_count=$((success_count + radar_files))
            else
                skip_count=$((skip_count + 1))
            fi
        else
            fail_count=$((fail_count + 1))
            overall_ok=false
        fi
    else
        log_warn "prediction-radar-app-db container not running — skipping"
        skip_count=$((skip_count + 1))
    fi

    # ---- Retention ----
    apply_retention

    # ---- Summary ----
    log_info "=============================================="
    log_info "PostgreSQL Backup Complete"
    log_info "  Successful: ${success_count}"
    log_info "  Failed:     ${fail_count}"
    log_info "  Skipped:    ${skip_count}"
    log_info "  Backup dir: ${BACKUP_ROOT}"
    log_info "  Total size: $(du -sh "${BACKUP_ROOT}" 2>/dev/null | cut -f1)"
    log_info "=============================================="

    ${overall_ok} && return 0 || return 1
}

main "$@"
