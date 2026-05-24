#!/usr/bin/env bash
# ==============================================================================
# restore-docker.sh — Restore a Docker-managed service from a deployment backup
# Usage: ./restore-docker.sh <service-name> <environment> <backup-path>
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-rollback.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <service-name> <environment> <backup-path>

Restores a Docker-managed service from a deployment backup. Stops the current
container gracefully, restores the previous docker-compose file and volumes,
and starts with the previous configuration. Monitors container health until
healthy or timeout.

Arguments:
  service-name   Name of the Docker service (e.g. litellm, openclaw)
  environment    Target environment (e.g. production, staging)
  backup-path    Full path to the backup directory

Exit Codes:
  0  Restore completed and container is healthy
  1  Restore failed (config missing, container failed to stop/start)
  2  Verification failed (container unhealthy after timeout)
EOF
}

# ── Docker availability check ────────────────────────────────────────────────
check_docker_available() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        log_error "Docker daemon is not running or current user lacks permissions."
        return 1
    fi
    log_info "Docker daemon is reachable."
    return 0
}

check_docker_compose_available() {
    if command -v docker-compose &>/dev/null; then
        echo "docker-compose"
        return 0
    fi
    if docker compose version &>/dev/null 2>&1; then
        echo "docker compose"
        return 0
    fi
    log_error "Neither docker-compose nor 'docker compose' is available."
    return 1
}

# ── Stop current container gracefully ────────────────────────────────────────
stop_current_container() {
    local service_name="$1"
    local compose_cmd="$2"
    local compose_file="/opt/services/${service_name}/docker-compose.yml"
    local compose_file_alt="/opt/services/${service_name}/docker-compose.yaml"

    local found_compose=""
    if [[ -f "${compose_file}" ]]; then
        found_compose="${compose_file}"
    elif [[ -f "${compose_file_alt}" ]]; then
        found_compose="${compose_file_alt}"
    fi

    # Determine project name
    local project_name="${service_name}-${environment:-prod}"

    if [[ -n "${found_compose}" ]]; then
        log_info "Stopping containers via ${compose_cmd} (project: ${project_name})..."

        # Capture container logs before stopping
        local log_dir="/var/log/rollbacks/${service_name}"
        mkdir -p "${log_dir}"
        local log_file="${log_dir}/pre-rollback-$(now_compact).log"

        if command -v docker &>/dev/null; then
            docker ps --filter "name=${service_name}" --format '{{.ID}}' 2>/dev/null | while IFS= read -r cid; do
                [[ -z "${cid}" ]] && continue
                docker logs --tail 500 "${cid}" > "${log_dir}/container-${cid}-$(now_compact).log" 2>&1 || true
            done
        fi

        # Graceful stop
        if ! ${compose_cmd} -f "${found_compose}" -p "${project_name}" down --timeout 30 2>&1; then
            log_warn "Graceful compose down had issues. Force stopping..."
            docker ps --filter "name=${service_name}" -q 2>/dev/null | xargs -r docker stop --time 10 2>/dev/null || true
            docker ps --filter "name=${service_name}" -q 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true
        fi
    else
        # No compose file — find and stop by container name
        log_info "No compose file found. Stopping containers by name filter: ${service_name}"

        docker ps --filter "name=${service_name}" -q 2>/dev/null | xargs -r docker stop --time 30 2>/dev/null || true
        docker ps --filter "name=${service_name}" -q 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true
    fi

    audit_log "INFO" "Stopped containers for ${service_name}"

    # Verify all containers are stopped
    local running
    running="$(docker ps --filter "name=${service_name}" -q 2>/dev/null || true)"
    if [[ -n "${running}" ]]; then
        log_warn "Some containers still running after stop: ${running}"
        docker stop --time 5 ${running} 2>/dev/null || true
        docker rm -f ${running} 2>/dev/null || true
    fi

    log_success "All containers for ${service_name} stopped."
    return 0
}

# ── Restore volumes ──────────────────────────────────────────────────────────
restore_volumes() {
    local backup_path="$1"
    local service_name="$2"

    local volume_backup="${backup_path}/volumes"
    if [[ ! -d "${volume_backup}" ]]; then
        log_info "No volume backup found at ${volume_backup}, skipping volume restore."
        return 0
    fi

    log_info "Restoring volumes from ${volume_backup}..."

    for volume_dir in "${volume_backup}"/*/; do
        [[ ! -d "${volume_dir}" ]] && continue
        local volume_name
        volume_name="$(basename "${volume_dir}")"

        log_info "Restoring volume: ${volume_name}"

        # Check if the volume exists
        if docker volume inspect "${volume_name}" &>/dev/null 2>&1; then
            # Mount the volume in a temporary container and copy data
            docker run --rm \
                -v "${volume_name}:/target" \
                -v "$(realpath "${volume_dir}"):/source:ro" \
                alpine:latest \
                sh -c "cp -a /source/. /target/" 2>&1 | tail -5 || {
                log_warn "Partial failure restoring volume ${volume_name}"
                audit_log "WARN" "Volume restore partial failure: ${volume_name}"
            }
        else
            log_warn "Volume '${volume_name}' does not exist in Docker. Creating and populating..."
            docker volume create "${volume_name}" 2>/dev/null || true
            docker run --rm \
                -v "${volume_name}:/target" \
                -v "$(realpath "${volume_dir}"):/source:ro" \
                alpine:latest \
                sh -c "cp -a /source/. /target/" 2>&1 | tail -5 || {
                log_warn "Partial failure restoring volume ${volume_name}"
            }
        fi

        audit_log "INFO" "Restored volume: ${volume_name}"
    done

    log_success "Volume restore completed."
    return 0
}

# ── Monitor container health ─────────────────────────────────────────────────
monitor_container_health() {
    local service_name="$1"
    local timeout="${2:-${HEALTH_TIMEOUT}}"
    local interval="${3:-${HEALTH_RETRY_INTERVAL}}"
    local elapsed=0

    log_info "Monitoring container health for ${service_name} (timeout=${timeout}s)..."

    while [[ ${elapsed} -lt ${timeout} ]]; do
        local containers
        containers="$(docker ps --filter "name=${service_name}" --format '{{.ID}}' 2>/dev/null)"

        if [[ -z "${containers}" ]]; then
            log_error "No running containers found for ${service_name} at ${elapsed}s"
            sleep "${interval}"
            elapsed=$((elapsed + interval))
            continue
        fi

        local all_healthy=1
        while IFS= read -r cid; do
            [[ -z "${cid}" ]] && continue

            # Check if container has a health check defined
            local has_healthcheck
            has_healthcheck="$(docker inspect "${cid}" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || echo "unknown")"

            if [[ "${has_healthcheck}" == "none" ]]; then
                # No health check defined. Container is running, consider it healthy.
                log_info "Container ${cid} has no health check defined. Treating as healthy (running)."
                continue
            fi

            local health_status
            health_status="$(docker inspect "${cid}" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")"

            case "${health_status}" in
                healthy)
                    log_info "Container ${cid} is healthy at ${elapsed}s"
                    ;;
                starting)
                    log_info "Container ${cid} health: starting... (${elapsed}s)"
                    all_healthy=0
                    ;;
                unhealthy)
                    log_error "Container ${cid} is UNHEALTHY at ${elapsed}s"
                    all_healthy=0
                    # Dump health check log
                    docker inspect "${cid}" --format '{{json .State.Health}}' 2>/dev/null | jq '.' || true
                    ;;
                *)
                    log_warn "Container ${cid} health: ${health_status} at ${elapsed}s"
                    ;;
            esac
        done <<< "${containers}"

        if [[ ${all_healthy} -eq 1 ]]; then
            log_success "All containers healthy after ${elapsed}s."
            return 0
        fi

        sleep "${interval}"
        elapsed=$((elapsed + interval))
    done

    log_error "Health check timed out after ${elapsed}s for ${service_name}"
    return 1
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    if [[ $# -lt 3 ]]; then
        usage >&2
        exit 1
    fi

    local service_name="$1"
    local environment="$2"
    local backup_path="$3"

    init_audit_log "${service_name}" "${environment}"
    audit_log "INFO" "restore-docker.sh starting for ${service_name}/${environment}"

    local start_time=${SECONDS}

    # ── 0. Pre-flight checks ─────────────────────────────────────────────
    check_docker_available || {
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "Docker restore - Docker daemon not available"
        close_audit_log 1
        exit 1
    }

    local compose_cmd
    compose_cmd="$(check_docker_compose_available)" || {
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "Docker restore - docker-compose not available"
        close_audit_log 1
        exit 1
    }

    # ── 1. Validate backup ───────────────────────────────────────────────
    verify_backup_integrity "${backup_path}" "docker" || {
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "Docker restore - backup integrity check failed"
        close_audit_log 1
        exit 1
    }

    # Check for docker-compose file in backup
    local backup_compose=""
    if [[ -f "${backup_path}/docker/docker-compose.yml" ]]; then
        backup_compose="${backup_path}/docker/docker-compose.yml"
    elif [[ -f "${backup_path}/docker/docker-compose.yaml" ]]; then
        backup_compose="${backup_path}/docker/docker-compose.yaml"
    elif [[ -f "${backup_path}/docker-compose.yml" ]]; then
        backup_compose="${backup_path}/docker-compose.yml"
    elif [[ -f "${backup_path}/docker-compose.yaml" ]]; then
        backup_compose="${backup_path}/docker-compose.yaml"
    fi

    if [[ -z "${backup_compose}" ]]; then
        log_error "No docker-compose file found in backup"
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "Docker restore - no docker-compose file in backup"
        close_audit_log 1
        exit 1
    fi

    log_info "Backup compose file: ${backup_compose}"

    # ── 2. Get version info ──────────────────────────────────────────────
    local from_version
    from_version="$(get_current_version "${service_name}" "${environment}")"
    local to_version
    to_version="$(get_backup_version "${backup_path}")"

    # ── 3. Preserve current docker-compose ───────────────────────────────
    local current_compose="/opt/services/${service_name}/docker-compose.yml"
    if [[ -f "${current_compose}" ]]; then
        preserve_failed_artifact "${current_compose}" "docker-compose"
        audit_log "INFO" "Preserved current docker-compose file"
    fi

    local current_compose_alt="/opt/services/${service_name}/docker-compose.yaml"
    if [[ -f "${current_compose_alt}" ]]; then
        preserve_failed_artifact "${current_compose_alt}" "docker-compose"
    fi

    # ── 4. Stop current containers ───────────────────────────────────────
    if ! stop_current_container "${service_name}" "${compose_cmd}"; then
        log_error "Failed to stop containers"
        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "Docker restore - failed to stop containers"
        close_audit_log 1
        exit 1
    fi

    # ── 5. Restore docker-compose file ───────────────────────────────────
    log_info "Restoring docker-compose file..."
    mkdir -p "/opt/services/${service_name}"

    # Determine target filename (.yml vs .yaml) from backup
    local target_compose
    if [[ "${backup_compose}" == *.yml ]]; then
        target_compose="/opt/services/${service_name}/docker-compose.yml"
    else
        target_compose="/opt/services/${service_name}/docker-compose.yaml"
    fi

    cp "${backup_compose}" "${target_compose}"
    audit_log "INFO" "Restored docker-compose to ${target_compose}"

    # Restore any .env file alongside compose
    if [[ -f "${backup_path}/docker/.env" ]]; then
        cp "${backup_path}/docker/.env" "/opt/services/${service_name}/.env"
        chmod 600 "/opt/services/${service_name}/.env"
        audit_log "INFO" "Restored docker .env file"
    fi

    # ── 6. Restore volumes if needed ─────────────────────────────────────
    restore_volumes "${backup_path}" "${service_name}"

    # ── 7. Start container with previous config ──────────────────────────
    log_info "Starting containers with restored config (project: ${service_name}-${environment})..."

    # Pull images explicitly if tag is known
    if [[ "${to_version}" != "unknown" ]]; then
        log_info "Pulling image tag: ${to_version}"
        docker pull "${to_version}" 2>&1 | tail -3 || log_warn "Failed to pull ${to_version}, will try with what is available"
    fi

    if ! ${compose_cmd} -f "${target_compose}" -p "${service_name}-${environment}" up -d --remove-orphans 2>&1; then
        log_error "Failed to start containers!"
        # Preserve logs
        docker ps -a --filter "name=${service_name}" --format '{{.ID}}' 2>/dev/null | while IFS= read -r cid; do
            [[ -z "${cid}" ]] && continue
            docker logs --tail 500 "${cid}" > "/var/log/rollbacks/${service_name}/startup-failure-${cid}-$(now_compact).log" 2>&1 || true
        done

        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "Docker restore - failed to start containers"
        close_audit_log 1
        exit 1
    fi

    audit_log "INFO" "Containers started with restored config"

    # ── 8. Monitor health until healthy ──────────────────────────────────
    local health_timeout=120
    if ! monitor_container_health "${service_name}" "${health_timeout}" 5; then
        log_error "Container health check failed!"

        # Preserve failed container logs
        local log_dir="/var/log/rollbacks/${service_name}"
        mkdir -p "${log_dir}"
        docker ps -a --filter "name=${service_name}" --format '{{.ID}}' 2>/dev/null | while IFS= read -r cid; do
            [[ -z "${cid}" ]] && continue
            preserve_failed_artifact "/var/log/rollbacks/${service_name}/container-${cid}.log" "health-fail"
            docker logs --tail 1000 "${cid}" > "/var/log/rollbacks/${service_name}/health-failure-${cid}-$(now_compact).log" 2>&1 || true
        done

        send_rollback_alert "${service_name}" "${environment}" "FAILED" \
            "Docker restore - health check failed after ${health_timeout}s"
        close_audit_log 2
        exit 2
    fi

    # ── 9. Log success ──────────────────────────────────────────────────
    local duration
    duration=$((SECONDS - start_time))
    log_rollback_event "${service_name}" "${environment}" "${from_version}" "${to_version}" \
        "docker_restore" "success" "${duration}" "Docker restore completed successfully"

    send_rollback_alert "${service_name}" "${environment}" "SUCCESS" \
        "Docker restore completed in ${duration}s"

    close_audit_log 0
    return 0
}

main "$@"
