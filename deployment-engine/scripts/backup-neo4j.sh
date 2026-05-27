#!/usr/bin/env bash
# =============================================================================
# backup-neo4j.sh — Neo4j Graph Database Backup for Wheeler Ecosystem
# =============================================================================
# Neo4j Community Edition requires the database to be stopped before dumping
# via neo4j-admin. This script uses the stop/backup/restart pattern:
#   1. Stop the ecosystem-graph container
#   2. Run a temp container with data volume to execute neo4j-admin dump
#   3. Restart the ecosystem-graph container
#   4. Rename the dump to include timestamp
#
# Downtime: typically 10-15 seconds (container stop + dump + restart)
#
# Output: /root/backups/neo4j/neo4j-<timestamp>.dump
# Retention: last 7 daily backups
# Log: /root/backups/neo4j/backup.log
#
# Exit codes:
#   0 - Backup successful
#   1 - Container not found or not running
#   2 - Container stop failed
#   3 - Dump command failed
#   4 - Container restart failed
#   5 - Verification failed
# =============================================================================
set -o pipefail
set -o nounset

readonly CONTAINER_NAME="ecosystem-graph"
readonly BACKUP_ROOT="/root/backups/neo4j"
readonly TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
readonly RETENTION_DAILY=7
readonly DUMP_FILENAME="neo4j-${TIMESTAMP}.dump"
readonly DATA_DIR="/opt/stacks/ecosystem-graph/data"

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
    log_info "Data directory: ${DATA_DIR}"
    log_info "=============================================="
}

# ---- Get container image for the temp dump container ----
get_image() {
    docker inspect -f '{{.Config.Image}}' "${CONTAINER_NAME}" 2>/dev/null
}

# ---- Check container exists and is running ----
check_container() {
    log_info "Checking container: ${CONTAINER_NAME}"

    if ! docker ps -a --format '{{.Names}}' | grep -qxF "${CONTAINER_NAME}"; then
        log_error "Container '${CONTAINER_NAME}' does not exist"
        return 1
    fi

    local status
    status="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null)"
    log_info "Container status: ${status}"

    if [[ "${status}" != "running" ]]; then
        log_error "Container is in state '${status}', expected 'running'"
        return 1
    fi

    # Verify data directory exists
    if [[ ! -d "${DATA_DIR}" ]]; then
        log_error "Data directory not found: ${DATA_DIR}"
        return 1
    fi

    log_info "Container check passed"
    return 0
}

# ---- Stop the Neo4j container ----
stop_container() {
    log_info "Stopping container ${CONTAINER_NAME}..."

    local stop_output
    stop_output="$(docker stop -t 30 "${CONTAINER_NAME}" 2>&1)"
    local rc=$?

    if [[ ${rc} -ne 0 ]]; then
        log_error "Failed to stop container (exit code ${rc})"
        log_error "Output: ${stop_output}"
        return 2
    fi

    # Verify it stopped
    local status
    status="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null)"
    if [[ "${status}" != "exited" ]]; then
        log_error "Container did not stop (status: ${status})"
        return 2
    fi

    log_info "Container stopped successfully"
    return 0
}

# ---- Run neo4j-admin dump using a temp container ----
run_dump() {
    local image
    image="$(get_image)"
    if [[ -z "${image}" ]]; then
        log_error "Could not determine container image"
        return 3
    fi
    log_info "Using image: ${image}"

    # Use a named temp container (not --rm) so we can docker cp from it.
    # The neo4j image runs as neo4j user internally; dump to /tmp in container (writable by neo4j).
    local temp_container="neo4j-backup-temp-${TIMESTAMP}"

    log_info "Creating temp container: ${temp_container}"

    docker run -d --name "${temp_container}" \
        -v "${DATA_DIR}:/data" \
        "${image}" \
        sleep 300 2>/dev/null

    if ! docker ps --format '{{.Names}}' | grep -qxF "${temp_container}"; then
        log_error "Failed to create temp container"
        return 3
    fi

    log_info "Running neo4j-admin database dump inside temp container..."

    local dump_output
    dump_output="$(docker exec "${temp_container}" neo4j-admin database dump neo4j --to-path=/tmp 2>&1)"
    local rc=$?

    log_info "neo4j-admin output: ${dump_output}"

    if [[ ${rc} -ne 0 ]]; then
        log_error "neo4j-admin dump failed with exit code ${rc}"
        log_error "Full output: ${dump_output}"
        docker rm -f "${temp_container}" 2>/dev/null || true
        return 3
    fi

    # Copy dump from temp container to host
    local container_dump_file
    container_dump_file="$(docker exec "${temp_container}" bash -c "ls -t /tmp/neo4j-*.dump 2>/dev/null | head -1")"
    if [[ -z "${container_dump_file}" ]]; then
        # Try the default name: neo4j.dump
        if docker exec "${temp_container}" test -f /tmp/neo4j.dump 2>/dev/null; then
            container_dump_file="/tmp/neo4j.dump"
        else
            log_error "No dump file found in temp container /tmp/"
            docker exec "${temp_container}" ls -la /tmp/ 2>&1 | log_info "Container /tmp listing:"
            docker rm -f "${temp_container}" 2>/dev/null || true
            return 3
        fi
    fi

    log_info "Copying from temp container: ${temp_container}:${container_dump_file} -> ${BACKUP_ROOT}/${DUMP_FILENAME}"
    docker cp "${temp_container}:${container_dump_file}" "${BACKUP_ROOT}/${DUMP_FILENAME}" 2>/dev/null

    local cp_rc=$?
    docker rm -f "${temp_container}" 2>/dev/null || true

    if [[ ${cp_rc} -ne 0 ]]; then
        log_error "docker cp failed with exit code ${cp_rc}"
        return 3
    fi

    # Verify the local dump file exists and has valid size
    if [[ ! -f "${BACKUP_ROOT}/${DUMP_FILENAME}" ]]; then
        log_error "Dump file not found after copy: ${BACKUP_ROOT}/${DUMP_FILENAME}"
        return 3
    fi

    local final_size
    final_size="$(stat -c%s "${BACKUP_ROOT}/${DUMP_FILENAME}" 2>/dev/null || echo 0)"

    if [[ ${final_size} -lt 1000 ]]; then
        log_error "Dump file too small (${final_size} bytes) -- likely corrupted"
        rm -f "${BACKUP_ROOT}/${DUMP_FILENAME}"
        return 5
    fi

    local size_human
    size_human="$(du -h "${BACKUP_ROOT}/${DUMP_FILENAME}" | cut -f1)"
    log_info "Dump created successfully: ${BACKUP_ROOT}/${DUMP_FILENAME} (${size_human})"

    return 0
}

# ---- Restart the Neo4j container ----
start_container() {
    log_info "Starting container ${CONTAINER_NAME}..."

    local start_output
    start_output="$(docker start "${CONTAINER_NAME}" 2>&1)"
    local rc=$?

    if [[ ${rc} -ne 0 ]]; then
        log_error "Failed to start container (exit code ${rc})"
        log_error "Output: ${start_output}"
        return 4
    fi

    # Wait for container to be healthy (up to 60s)
    log_info "Waiting for Neo4j to become healthy..."
    local waited=0
    local max_wait=60
    while [[ ${waited} -lt ${max_wait} ]]; do
        local health
        health="$(docker inspect -f '{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo 'unknown')"
        if [[ "${health}" == "healthy" ]]; then
            log_info "Neo4j is healthy after ${waited}s"
            return 0
        fi
        if [[ "${health}" == "unhealthy" ]]; then
            log_warn "Neo4j health check reports unhealthy after ${waited}s -- continuing anyway"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    log_warn "Neo4j health check timed out after ${max_wait}s -- state may be starting"
    log_info "Container is running: $(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)"
    return 0
}

# ---- Retention: keep last 7 daily backups ----
cleanup_old_backups() {
    log_info "Cleaning up old backups (retaining last ${RETENTION_DAILY})..."

    local count
    count="$(find "${BACKUP_ROOT}" -maxdepth 1 -name 'neo4j-*.dump' -type f | wc -l)"
    log_info "Found ${count} existing neo4j-*.dump files"

    if [[ ${count} -le ${RETENTION_DAILY} ]]; then
        log_info "Within retention limit (${count} <= ${RETENTION_DAILY}), no cleanup needed"
        return 0
    fi

    local to_delete=$((count - RETENTION_DAILY))
    log_info "Removing ${to_delete} oldest backup(s)..."

    find "${BACKUP_ROOT}" -maxdepth 1 -name 'neo4j-*.dump' -type f -printf '%T@ %p\n' \
        | sort -n \
        | head -n "${to_delete}" \
        | while read -r ts filepath; do
            log_info "Removing old backup: $(basename "${filepath}")"
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
    if [[ -f "${BACKUP_ROOT}/${DUMP_FILENAME}" ]]; then
        log_info "Size: $(du -h "${BACKUP_ROOT}/${DUMP_FILENAME}" | cut -f1)"
    fi
    log_info "Total backups on disk: $(find "${BACKUP_ROOT}" -maxdepth 1 -name 'neo4j-*.dump' -type f | wc -l)"
    log_info "Total storage used: $(du -sh "${BACKUP_ROOT}" 2>/dev/null | cut -f1)"
    log_info "Container status: $(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo 'unknown')"
    log_info "=============================================="
}

# ---- Main ----
main() {
    local overall_ok=true
    local container_stopped=false

    setup

    # Phase 1: Pre-flight check
    check_container || overall_ok=false

    # Phase 2: Stop container
    if ${overall_ok}; then
        stop_container || overall_ok=false
        container_stopped=true
    fi

    # Phase 3: Run dump (container is stopped)
    if ${overall_ok}; then
        run_dump || overall_ok=false
    fi

    # Phase 4: Restart container (ALWAYS attempt, even if dump failed)
    if ${container_stopped}; then
        if start_container; then
            log_info "Container restarted successfully"
        else
            log_error "Container restart failed -- MANUAL INTERVENTION REQUIRED"
            log_error "Run: docker start ${CONTAINER_NAME}"
            overall_ok=false
        fi
    fi

    # Phase 5: Cleanup old backups (only if dump succeeded)
    if ${overall_ok}; then
        cleanup_old_backups
    fi

    # Summary
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
