#!/usr/bin/env bash
# =============================================================================
# backup-redis.sh — Redis Backup for Wheeler Ecosystem
# =============================================================================
# Backs up all running Redis Docker containers:
#   - node-service-redis (6379)
#   - prediction-radar-app-redis
#   - docuseal-redis
# Strategy: Trigger BGSAVE, then docker cp the RDB dump file.
# Output: /root/backups/redis/<instance>-<timestamp>.rdb
# Retention: last 7 copies per instance
# Log: /root/backups/redis/backup.log
# =============================================================================
set -o pipefail
set -o nounset

readonly BACKUP_ROOT="/root/backups/redis"
readonly TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
readonly RETENTION_KEEP=7

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
    log_info "Redis Backup Started"
    log_info "Backup root: ${BACKUP_ROOT}"
    log_info "=============================================="
}

# ---- Trigger BGSAVE and verify completion ----
trigger_bgsave() {
    local container="$1"

    log_info "Triggering BGSAVE on ${container}..."

    # Check last save time before
    local before
    before=$(docker exec "${container}" redis-cli LASTSAVE 2>/dev/null || echo "0")

    # Trigger BGSAVE
    if ! docker exec "${container}" redis-cli BGSAVE >/dev/null 2>&1; then
        log_warn "BGSAVE command failed on ${container} — trying SAVE instead"
        if ! docker exec "${container}" redis-cli SAVE >/dev/null 2>&1; then
            log_error "Both BGSAVE and SAVE failed on ${container}"
            return 1
        fi
        log_info "SAVE completed on ${container}"
        return 0
    fi

    # Wait for BGSAVE to complete (poll LASTSAVE)
    local waited=0
    while [[ ${waited} -lt 60 ]]; do
        local after
        after=$(docker exec "${container}" redis-cli LASTSAVE 2>/dev/null || echo "0")
        if [[ "${after}" != "${before}" ]] && [[ "${after}" != "0" ]]; then
            log_info "BGSAVE completed on ${container} (waited ${waited}s)"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    log_error "BGSAVE did not complete on ${container} within 60s"
    return 1
}

# ---- Copy RDB from container ----
copy_rdb() {
    local container="$1"
    local rdb_dir rdb_file

    # Get RDB location from Redis config
    rdb_dir=$(docker exec "${container}" redis-cli CONFIG GET dir 2>/dev/null | tail -1 || echo "/data")
    rdb_file=$(docker exec "${container}" redis-cli CONFIG GET dbfilename 2>/dev/null | tail -1 || echo "dump.rdb")

    local src_path="${rdb_dir}/${rdb_file}"
    local dst_path="${BACKUP_ROOT}/${container}-${TIMESTAMP}.rdb"

    log_info "Copying RDB from ${container}:${src_path} -> ${dst_path}"

    if docker cp "${container}:${src_path}" "${dst_path}" 2>/dev/null; then
        local size
        size="$(stat -c%s "${dst_path}" 2>/dev/null || echo 0)"
        if [[ "${size}" -gt 0 ]]; then
            local size_hr
            size_hr="$(du -h "${dst_path}" | cut -f1)"
            log_info "SUCCESS: ${container} RDB saved (${size_hr})"
            return 0
        else
            log_error "RDB file is empty: ${dst_path}"
            rm -f "${dst_path}"
            return 1
        fi
    else
        log_error "docker cp failed for ${container}:${src_path}"
        return 1
    fi
}

# ---- Backup a single Redis container ----
backup_redis_instance() {
    local container="$1"

    log_info "--- Backing up Redis: ${container} ---"

    # Check container is running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
        log_warn "Container ${container} is not running — skipping"
        return 2  # 2 = skipped
    fi

    # Check Redis is responsive
    if ! docker exec "${container}" redis-cli PING 2>/dev/null | grep -q PONG; then
        log_warn "Redis not responsive in ${container} — skipping"
        return 2
    fi

    # Check keyspace to see if there's data worth backing up
    local keys_total
    keys_total=$(docker exec "${container}" redis-cli INFO keyspace 2>/dev/null | grep -oP 'keys=\K[0-9]+' | paste -sd+ | bc 2>/dev/null || echo "0")
    log_info "Keyspace: ${keys_total:-0} total keys"

    # Trigger BGSAVE
    if ! trigger_bgsave "${container}"; then
        log_error "Failed to trigger BGSAVE on ${container}"
        return 1
    fi

    # Copy RDB
    if ! copy_rdb "${container}"; then
        log_error "Failed to copy RDB from ${container}"
        return 1
    fi

    return 0
}

# ---- Retention cleanup ----
apply_retention() {
    log_info "Applying retention: keep last ${RETENTION_KEEP} backups per instance"

    # Get unique instance names from backup files
    local instances
    instances=$(find "${BACKUP_ROOT}" -maxdepth 1 -name '*.rdb' -printf '%f\n' 2>/dev/null \
        | sed 's/-[0-9]\{8\}-[0-9]\{6\}\.rdb$//' | sort -u)

    for instance in ${instances}; do
        local files
        mapfile -t files < <(find "${BACKUP_ROOT}" -maxdepth 1 -name "${instance}-*.rdb" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

        local count=0
        for f in "${files[@]}"; do
            count=$((count + 1))
            if [[ ${count} -gt ${RETENTION_KEEP} ]]; then
                log_info "  REMOVE (past retention): $(basename "${f}")"
                rm -f "${f}"
            fi
        done
        log_info "  ${instance}: keeping ${count} backups (limit: ${RETENTION_KEEP})"
    done
}

# ---- Main ----
main() {
    local overall_ok=true
    local success_count=0
    local fail_count=0
    local skip_count=0

    setup

    # Discover running Redis containers
    local redis_containers
    redis_containers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'redis' | grep -v 'exporter' || true)

    if [[ -z "${redis_containers}" ]]; then
        log_warn "No Redis containers running — nothing to back up"
        log_info "Redis Backup Complete (nothing to do)"
        return 0
    fi

    log_info "Found Redis containers: $(echo ${redis_containers} | tr '\n' ' ')"

    for container in ${redis_containers}; do
        backup_redis_instance "${container}"
        local rc=$?
        case ${rc} in
            0) success_count=$((success_count + 1)) ;;
            1) fail_count=$((fail_count + 1)); overall_ok=false ;;
            2) skip_count=$((skip_count + 1)) ;;
        esac
    done

    # Retention
    apply_retention

    # Summary
    log_info "=============================================="
    log_info "Redis Backup Complete"
    log_info "  Successful: ${success_count}"
    log_info "  Failed:     ${fail_count}"
    log_info "  Skipped:    ${skip_count}"
    log_info "  Backup dir: ${BACKUP_ROOT}"
    log_info "  Total size: $(du -sh "${BACKUP_ROOT}" 2>/dev/null | cut -f1)"
    log_info "=============================================="

    ${overall_ok} && return 0 || return 1
}

main "$@"
