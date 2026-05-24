#!/usr/bin/env bash
# =============================================================================
# Wheeler Deployment Engine — deploy-docker-service.sh
# =============================================================================
# Handles Docker-based service deployments with zero-downtime container
# replacement, pre-deploy backup, health checks, and auto-rollback.
#
# Usage:
#   ./deploy-docker-service.sh <service-name> <environment> <image-tag>
#   ./deploy-docker-service.sh changedetection production 2026.05.1
#   ./deploy-docker-service.sh --force traefik staging latest
#
# Exit Codes:
#   0 - Deployment successful
#   1 - Pre-deploy checks failed
#   2 - Image pull failed
#   3 - Container start failed
#   4 - Health check failed (rolled back)
#   5 - Rollback failed
# =============================================================================

set -euo pipefail

# ─── Source common utilities ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# ─── Script Configuration ────────────────────────────────────────────────────
readonly SCRIPT_NAME="deploy-docker-service.sh"
readonly SCRIPT_VERSION="1.0.0"
readonly DOCKER_COMPOSE_CMD="${DOCKER_COMPOSE_CMD:-docker compose}"

# ─── Parse flags ─────────────────────────────────────────────────────────────
FORCE_CONFIRM="${FORCE_CONFIRM:-}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f) FORCE_CONFIRM=1; shift ;;
        *) break ;;
    esac
done

# ─── Arguments ───────────────────────────────────────────────────────────────
SERVICE_NAME="${1:-}"
ENVIRONMENT="${2:-}"
IMAGE_TAG="${3:-}"

# ─── Usage ───────────────────────────────────────────────────────────────────
_docker_usage() {
    cat <<EOF

${_C_BOLD}Usage:${_C_RESET} ./${SCRIPT_NAME} [--force] <service-name> <environment> <image-tag>

${_C_BOLD}Arguments:${_C_RESET}
  service-name   Docker service name (as defined in docker-compose.yml)
  environment    Target environment (production, staging, dev)
  image-tag      Docker image tag to deploy

${_C_BOLD}Examples:${_C_RESET}
  ./deploy-docker-service.sh changedetection production 2026.05.1
  ./deploy-docker-service.sh --force healthchecks staging latest
EOF
    exit 1
}

# ─── Validate ────────────────────────────────────────────────────────────────
validate_docker_args() {
    if [[ -z "$SERVICE_NAME" ]]; then
        log_error "Missing argument: service-name"
        _docker_usage
    fi
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Missing argument: environment"
        _docker_usage
    fi
    if [[ -z "$IMAGE_TAG" ]]; then
        log_error "Missing argument: image-tag"
        _docker_usage
    fi
    validate_environment "$ENVIRONMENT" || exit 1
}

# ─── Get service directory ───────────────────────────────────────────────────
get_service_dir() {
    local dirs=(
        "${WHEELER_BASE}/${SERVICE_NAME}"
        "${WHEELER_BASE}/wheeler-autonomous-ops/${SERVICE_NAME}"
        "${WHEELER_BASE}/wheeler-intelligence-platform/${SERVICE_NAME}"
        "/opt/wheeler/${SERVICE_NAME}"
    )
    for dir in "${dirs[@]}"; do
        if [[ -f "${dir}/docker-compose.yml" ]] || [[ -f "${dir}/docker-compose.${ENVIRONMENT}.yml" ]]; then
            echo "$dir"
            return 0
        fi
    done
    log_error "Could not find docker-compose.yml for service: ${SERVICE_NAME}"
    exit 1
}

# ─── Determine compose files ─────────────────────────────────────────────────
get_compose_files() {
    local service_dir="$1"
    local files=()

    # Base compose file
    if [[ -f "${service_dir}/docker-compose.yml" ]]; then
        files+=("${service_dir}/docker-compose.yml")
    fi

    # Environment-specific override
    if [[ -f "${service_dir}/docker-compose.${ENVIRONMENT}.yml" ]]; then
        files+=("${service_dir}/docker-compose.${ENVIRONMENT}.yml")
    fi

    # Shared env file
    if [[ -f "${service_dir}/.env.docker.${ENVIRONMENT}" ]]; then
        export ENV_FILE="${service_dir}/.env.docker.${ENVIRONMENT}"
    elif [[ -f "${service_dir}/.env" ]]; then
        export ENV_FILE="${service_dir}/.env"
    fi

    local compose_file_args=""
    for f in "${files[@]}"; do
        compose_file_args="${compose_file_args} -f ${f}"
    done

    echo "$compose_file_args"
}

# ─── Get current image tag for rollback purposes ─────────────────────────────
get_current_image_tag() {
    local service_dir="$1"
    local compose_files
    compose_files=$(get_compose_files "$service_dir")

    ${DOCKER_COMPOSE_CMD} ${compose_files} images -q "${SERVICE_NAME}" 2>/dev/null || echo "unknown"
}

# ─── Docker image pull ───────────────────────────────────────────────────────
pull_image() {
    local service_dir="$1"

    log_info "Pulling Docker image for: ${SERVICE_NAME}:${IMAGE_TAG}"

    # Extract image name from compose file
    local image_name
    image_name=$(${DOCKER_COMPOSE_CMD} -f "${service_dir}/docker-compose.yml" config 2>/dev/null | \
        grep -A1 "image:" | grep -v "^--$" | head -1 | awk '{print $2}' || echo "")

    if [[ -z "$image_name" ]]; then
        # Try to construct from service name
        image_name="${DOCKER_REGISTRY:-registry.wheeler.dev}/${SERVICE_NAME}:${IMAGE_TAG}"
    else
        # Replace the tag portion
        image_name="${image_name%:*}:${IMAGE_TAG}"
    fi

    log_info "Pulling image: ${image_name}"

    if ! docker pull "${image_name}"; then
        log_error "Failed to pull Docker image: ${image_name}"
        return 1
    fi

    log_success "Docker image pulled: ${image_name}"
    return 0
}

# ─── Backup Docker volumes ───────────────────────────────────────────────────
backup_docker_state() {
    local service_dir="$1"
    local backup_dir="${BACKUP_BASE}/$(timestamp_file)_${SERVICE_NAME}_predeploy"

    mkdir -p "$backup_dir"

    log_info "Backing up Docker state to: ${backup_dir}"

    # Backup compose files
    for f in "${service_dir}"/docker-compose*.yml; do
        if [[ -f "$f" ]]; then
            cp -a "$f" "${backup_dir}/$(basename "$f").backup"
        fi
    done

    # Backup env files
    for f in "${service_dir}"/.env*; do
        if [[ -f "$f" ]]; then
            cp -a "$f" "${backup_dir}/$(basename "$f").backup"
        fi
    done

    # Backup named volumes
    local volumes
    volumes=$(docker volume ls -q --filter "name=${SERVICE_NAME}" 2>/dev/null || true)
    for vol in $volumes; do
        log_info "Backing up Docker volume: ${vol}"
        docker run --rm \
            -v "${vol}:/volume_data" \
            -v "${backup_dir}:/backup" \
            alpine tar czf "/backup/volume_${vol}.tar.gz" -C /volume_data . 2>/dev/null || \
            log_warn "Volume backup failed for ${vol} (may be empty)"
    done

    # Checksums
    (cd "$backup_dir" && sha256sum -- * > checksums.sha256 2>/dev/null) || true

    echo "$backup_dir" > /tmp/wheeler_last_docker_backup
    log_success "Docker state backup complete"
}

# ─── Get container health ────────────────────────────────────────────────────
check_container_health() {
    local container_name="$1"
    local max_retries="${2:-30}"
    local interval="${3:-2}"
    local attempt=1

    log_info "Checking container health: ${container_name}"

    while [[ $attempt -le $max_retries ]]; do
        local state
        state=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "not-found")
        local health
        health=$(docker inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")

        case "$state" in
            running)
                case "$health" in
                    healthy|none)
                        log_success "Container healthy: ${container_name} (state=${state}, health=${health})"
                        return 0
                        ;;
                    starting)
                        log_debug "Container starting... (attempt ${attempt}/${max_retries})"
                        ;;
                    *)
                        log_warn "Container health status: ${health} (attempt ${attempt}/${max_retries})"
                        ;;
                esac
                ;;
            not-found)
                log_error "Container not found: ${container_name}"
                return 1
                ;;
            *)
                log_warn "Container state: ${state} (attempt ${attempt}/${max_retries})"
                ;;
        esac

        sleep "$interval"
        attempt=$((attempt + 1))
    done

    log_error "Container health check FAILED for: ${container_name}"
    return 1
}

# ─── Zero-downtime container replacement ─────────────────────────────────────
zero_downtime_replace() {
    local service_dir="$1"
    local compose_files
    compose_files=$(get_compose_files "$service_dir")

    local container_name="${SERVICE_NAME}"

    log_section "Zero-Downtime Docker Deployment"

    # Check if the service is currently running
    local running
    running=$(${DOCKER_COMPOSE_CMD} ${compose_files} ps -q "${SERVICE_NAME}" 2>/dev/null || echo "")

    if [[ -z "$running" ]]; then
        # First deploy — just start
        log_info "No existing container found. Starting new container..."
        ${DOCKER_COMPOSE_CMD} ${compose_files} up -d --no-deps "${SERVICE_NAME}"
    else
        # Scale up to 2 instances, then remove the old one
        log_info "Existing container found. Performing zero-downtime replacement..."

        # Check compose file for scale support
        local has_deploy
        has_deploy=$(${DOCKER_COMPOSE_CMD} ${compose_files} config 2>/dev/null | grep -c "deploy:" || echo "0")

        if [[ "$has_deploy" -gt 0 ]] && ${DOCKER_COMPOSE_CMD} ${compose_files} config 2>/dev/null | grep -q "replicas"; then
            # Compose file supports replicas — scale up then down
            log_info "Using replica-based zero-downtime..."
            ${DOCKER_COMPOSE_CMD} ${compose_files} up -d --no-deps --scale "${SERVICE_NAME}=2" "${SERVICE_NAME}"
            sleep 5

            # Verify at least one new container is healthy
            local new_containers
            new_containers=$(${DOCKER_COMPOSE_CMD} ${compose_files} ps -q "${SERVICE_NAME}" 2>/dev/null | tail -1)
            if [[ -n "$new_containers" ]]; then
                check_container_health "${SERVICE_NAME}" 30 2 || {
                    log_error "New container health check failed"
                    return 1
                }
            fi

            # Scale back to 1 (removes oldest container)
            ${DOCKER_COMPOSE_CMD} ${compose_files} up -d --no-deps --scale "${SERVICE_NAME}=1" "${SERVICE_NAME}"

        else
            # Simple stop + start with delay for health check
            log_info "Using simple stop+start with health verification..."

            # Pull new image first
            pull_image "$service_dir" || return 1

            # Get old container ID for rollback
            local old_container_id
            old_container_id=$(docker ps -q --filter "name=${SERVICE_NAME}" 2>/dev/null || echo "")
            log_info "Old container ID: ${old_container_id}"

            # Pull and recreate
            ${DOCKER_COMPOSE_CMD} ${compose_files} pull "${SERVICE_NAME}" 2>/dev/null || true
            ${DOCKER_COMPOSE_CMD} ${compose_files} up -d --no-deps --force-recreate "${SERVICE_NAME}"

            # Wait for new container
            sleep 5
            check_container_health "${SERVICE_NAME}" 30 2 || {
                log_error "New container failed health check — rolling back"
                if [[ -n "$old_container_id" ]]; then
                    log_info "Restarting old container: ${old_container_id}"
                    docker stop "${SERVICE_NAME}" 2>/dev/null || true
                    docker start "$old_container_id" 2>/dev/null || {
                        log_fatal "Failed to restart old container!"
                        return 1
                    }
                fi
                return 1
            }

            # Remove old container (keep image)
            if [[ -n "$old_container_id" ]]; then
                log_info "Removing old container: ${old_container_id}"
                docker rm "$old_container_id" 2>/dev/null || true
            fi
        fi
    fi

    log_success "Zero-downtime replacement completed"
    return 0
}

# ─── Log shipping setup ──────────────────────────────────────────────────────
setup_log_shipping() {
    log_info "Verifying log driver configuration..."
    local driver
    driver=$(docker inspect -f '{{.HostConfig.LogConfig.Type}}' "${SERVICE_NAME}" 2>/dev/null || echo "unknown")
    log_info "Container log driver: ${driver}"
}

# ─── Rollback ────────────────────────────────────────────────────────────────
docker_rollback() {
    log_section "Docker Rollback"

    local backup_dir
    backup_dir=$(cat /tmp/wheeler_last_docker_backup 2>/dev/null || echo "")

    if [[ -z "$backup_dir" ]] || [[ ! -d "$backup_dir" ]]; then
        log_error "No backup directory found for rollback"
        return 1
    fi

    local service_dir
    service_dir=$(get_service_dir)

    # Restore compose files from backup
    log_info "Restoring docker-compose files from backup..."
    for f in "${backup_dir}"/docker-compose*.yml.backup; do
        if [[ -f "$f" ]]; then
            local target="${service_dir}/$(basename "$f" .backup)"
            cp -a "$f" "$target"
            log_info "Restored: ${target}"
        fi
    done

    # Restart with old config
    local compose_files
    compose_files=$(get_compose_files "$service_dir")
    log_info "Restarting service with restored configuration..."
    ${DOCKER_COMPOSE_CMD} ${compose_files} up -d --no-deps --force-recreate "${SERVICE_NAME}"

    # Verify rollback
    sleep 5
    if check_container_health "${SERVICE_NAME}" 20 2; then
        log_success "Docker rollback successful"
        return 0
    else
        log_fatal "Docker rollback FAILED — container not healthy after restore"
        return 1
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    enable_error_tracing
    enable_signal_handlers

    validate_docker_args

    if ! check_docker_daemon; then
        log_fatal "Docker daemon is not running. Cannot deploy Docker service."
        exit 1
    fi

    local service_dir
    service_dir=$(get_service_dir)
    log_info "Service directory: ${service_dir}"

    log_section "Docker Deployment: ${SERVICE_NAME} → ${ENVIRONMENT}"
    log_kv "Service"       "$SERVICE_NAME"
    log_kv "Environment"   "$ENVIRONMENT"
    log_kv "Image Tag"     "$IMAGE_TAG"
    log_kv "Service Dir"   "$service_dir"
    log_kv "Node"          "$(hostname)"

    # 1. Pre-deploy backup
    backup_docker_state "$service_dir" || {
        log_error "Docker state backup failed"
        exit 2
    }

    # 2. Pull image
    pull_image "$service_dir" || {
        log_error "Image pull failed"
        exit 2
    }

    # 3. Zero-downtime deploy
    if ! zero_downtime_replace "$service_dir"; then
        log_fatal "Zero-downtime deployment FAILED"
        send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "CRITICAL" \
            "Docker zero-downtime deploy failed for tag ${IMAGE_TAG}"

        # Attempt rollback
        if docker_rollback; then
            log_success "Docker auto-rollback successful"
            exit 3
        else
            log_fatal "Docker auto-rollback FAILED!"
            exit 5
        fi
    fi

    # 4. Setup log shipping
    setup_log_shipping

    # 5. Success
    log_success "Docker deployment completed: ${SERVICE_NAME}:${IMAGE_TAG} on ${ENVIRONMENT}"
    send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "OK" \
        "Docker deployment successful: tag ${IMAGE_TAG}"

    return 0
}

# ─── Entry Point ─────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
