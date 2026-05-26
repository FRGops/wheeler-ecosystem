#!/usr/bin/env bash
# =============================================================================
# backup-neo4j.sh — Neo4j Graph Database Backup for Wheeler Ecosystem
# =============================================================================
# Uses neo4j-admin dump via docker exec to create a consistent backup of
# the Neo4j database running in the "ecosystem-graph" container.
#
# Output: /root/backups/neo4j/neo4j-<timestamp>.dump
# Retention: last 7 daily backups
# Log: /root/backups/neo4j/backup.log
#
# Exit codes:
#   0 - Backup successful
#   1 - Container not running
#   2 - Dump command failed
#   3 - File copy failed
#   4 - Verification failed
# =============================================================================
set -o pipefail
set -o nounset

readonly CONTAINER_NAME="ecosystem-graph"
readonly BACKUP_ROOT="/root/backups/neo4j"
readonly TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
readonly RETENTION_DAILY=7
readonly DUMP_FILENAME="neo4j-${TIMESTAMP}.dump"
readonly CONTAINER_TMP="/tmp"

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
    log_info "Neo4j Backup Started"
    log_info "Container: ${CONTAINER_NAME}"
    log_info "Backup root: ${BACKUP_ROOT}"
    log_info "=============================================="
}

# ---- Check container is running ----
check_container() {
    log_info "Checking container status: ${CONTAINER_NAME}"

    if ! docker ps --format '{{.Names}}' | grep -qxF "${CONTAINER_NAME}"; then
        log_error "Container '${CONTAINER_NAME}' is not running"
        log_error "Available containers: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
        return 1
    fi

    local status
    status="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null)"
    log_info "Container status: ${status}"

    if [[ "${status}" != "running" ]]; then
        log_error "Container is in state '${status}', expected 'running'"
        return 1
    fi

    # Verify neo4j-admin is available
    if ! docker exec "${CONTAINER_NAME}" which neo4j-admin &>/dev/null; then
        log_error "neo4j-admin not found in container"
        return 1
    fi

    log_info "Container check passed"
    return 0
}

# ---- Run neo4j-admin dump inside container ----
run_dump() {
    log_info "Running neo4j-admin database dump neo4j..."

    # Clean any previous temp dump files in container
    docker exec "${CONTAINER_NAME}" bash -c "rm -f ${CONTAINER_TMP}/neo4j-*.dump" 2>/dev/null || true

    local dump_output
    dump_output="$(docker exec "${CONTAINER_NAME}" neo4j-admin database dump neo4j --to-path="${CONTAINER_TMP}" 2>&1)"
    local rc=$?

    log_info "neo4j-admin output: ${dump_output}"

    if [[ ${rc} -ne 0 ]]; then
        log_error "neo4j-admin dump failed with exit code ${rc}"
        log_error "Output: ${dump_output}"
        return 2
    fi

    # Verify the dump file was created inside the container
    local container_dump
    container_dump="$(docker exec "${CONTAINER_NAME}" bash -c "ls -t ${CONTAINER_TMP}/neo4j-*.dump 2>/dev/null | head -1")"
    if [[ -z "${container_dump}" ]]; then
        log_error "No dump file created in container at ${CONTAINER_TMP}"
        return 2
    fi

    local container_size
    container_size="$(docker exec "${CONTAINER_NAME}" stat -c%s "${container_dump}" 2>/dev/null || echo 0)"
    log_info "Dump created in container: ${container_dump} (${container_size} bytes)"

    return 0
}

# ---- Copy dump from container to host ----
copy_dump() {
    log_info "Copying dump from container to ${BACKUP_ROOT}/${DUMP_FILENAME}..."

    # Find the dump file in the container
    local container_dump
    container_dump="$(docker exec "${CONTAINER_NAME}" bash -c "ls -t ${CONTAINER_TMP}/neo4j-*.dump 2>/dev/null | head -1")"

    if [[ -z "${container_dump}" ]]; then
        log_error "No dump file found in container to copy"
        return 3
    fi

    # Copy from container to host
    if ! docker cp "${CONTAINER_NAME}:${container_dump}" "${BACKUP_ROOT}/${DUMP_FILENAME}" 2>/dev/null; then
        log_error "docker cp failed"
        return 3
    fi

    # Clean up the container temp file
    docker exec "${CONTAINER_NAME}" bash -c "rm -f ${CONTAINER_TMP}/neo4j-*.dump" 2>/dev/null || true

    # Verify the local file exists and has content
    if [[ ! -f "${BACKUP_ROOT}/${DUMP_FILENAME}" ]]; then
        log_error "Local dump file not found after copy: ${BACKUP_ROOT}/${DUMP_FILENAME}"
        return 3
    fi

    local local_size
    local_size="$(stat -c%s "${BACKUP_ROOT}/${DUMP_FILENAME}" 2>/dev/null || echo 0)"

    if [[ ${local_size} -lt 1000 ]]; then
        log_error "Dump file too small (${local_size} bytes) — likely corrupted"
        rm -f "${BACKUP_ROOT}/${DUMP_FILENAME}"
        return 4
    fi

    local local_size_human
    local_size_human="$(du -h "${BACKUP_ROOT}/${DUMP_FILENAME}" | cut -f1)"
    log_info "Dump copied successfully: ${BACKUP_ROOT}/${DUMP_FILENAME} (${local_size_human})"

    return 0
}

# ---- Retention: keep last 7 daily backups ----
cleanup_old_backups() {
    log_info "Cleaning up old backups (retaining last ${RETENTION_DAILY})..."

    local count
    count="$(find "${BACKUP_ROOT}" -maxdepth 1 -name 'neo4j-*.dump' -type f | wc -l)"
    log_info "Found ${count} existing dump files"

    if [[ ${count} -le ${RETENTION_DAILY} ]]; then
        log_info "Within retention limit (${count} <= ${RETENTION_DAILY}), no cleanup needed"
        return 0
    fi

    local to_delete=$((count - RETENTION_DAILY))
    log_info "Removing ${to_delete} oldest backup(s)..."

    # List dump files sorted by modification time (oldest first), delete the excess
    find "${BACKUP_ROOT}" -maxdepth 1 -name 'neo4j-*.dump' -type f -printf '%T@ %p\n' \
        | sort -n \
        | head -n "${to_delete}" \
        | while read -r ts filepath; do
            log_info "Removing old backup: ${filepath}"
            rm -f "${filepath}"
        done

    local remaining
    remaining="$(find "${BACKUP_ROOT}" -maxdepth 1 -name 'neo4j-*.dump' -type f | wc -l)"
    log_info "Cleanup complete: ${remaining} backups retained"
}

# ---- Summary ----
print_summary() {
    log_info "=============================================="
    log_info "Neo4j Backup Summary"
    log_info "=============================================="
    log_info "Backup file: ${BACKUP_ROOT}/${DUMP_FILENAME}"
    log_info "Size: $(du -h "${BACKUP_ROOT}/${DUMP_FILENAME}" | cut -f1)"
    log_info "Total backups on disk: $(find "${BACKUP_ROOT}" -maxdepth 1 -name 'neo4j-*.dump' -type f | wc -l)"
    log_info "Total storage used: $(du -sh "${BACKUP_ROOT}" 2>/dev/null | cut -f1)"
    log_info "=============================================="
}

# ---- Main ----
main() {
    local overall_ok=true

    setup

    check_container || overall_ok=false
    if ${overall_ok}; then
        run_dump || overall_ok=false
    fi
    if ${overall_ok}; then
        copy_dump || overall_ok=false
    fi
    if ${overall_ok}; then
        cleanup_old_backups
    fi

    if ${overall_ok}; then
        print_summary
        log_info "RESULT: PASSED"
        return 0
    else
        log_error "RESULT: FAILED"
        return 1
    fi
}

main "$@"
