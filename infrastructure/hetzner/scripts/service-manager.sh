#!/usr/bin/env bash
# ==============================================================================
# service-manager.sh — Unified Service Management (Hetzner CPX51)
# ==============================================================================
#
# Manages all services running on the Hetzner CPX51 primary server.
# Handles Docker Compose commands with proper project names, health checks,
# and provides a unified interface for operations.
#
# Usage:
#   ./service-manager.sh <action> [service]
#
# Actions:
#   start     Start a service (docker compose up -d)
#   stop      Stop a service (docker compose down)
#   restart   Restart a service (stop + start)
#   status    Show status of all services or one
#   logs      Show recent logs for a service
#   health    Run health checks
#   update    Pull latest images and restart
#   ps        List running containers
#   stats     Show resource usage for service containers
#
# Services (Hetzner):
#   prediction-radar, ravynai, trading, ai-agents, analytics, monitoring,
#   postgres, redis, messaging, traefik, management
#
# Examples:
#   ./service-manager.sh status                # All services
#   ./service-manager.sh status prediction-radar  # Single service
#   ./service-manager.sh logs ravynai --tail 100
#   ./service-manager.sh restart traefik
#   ./service-manager.sh health monitoring
#   ./service-manager.sh stats                 # All containers
# ==============================================================================

set -euo pipefail

# --- Globals -----------------------------------------------------------------
BASE_DIR="${BASE_DIR:-/opt/wheeler}"
DEPLOY_DIR="${BASE_DIR}/deploy"
COMPOSE_BASE="${DEPLOY_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "\n${CYAN}── $* ──${NC}\n"; }

# --- Service registry --------------------------------------------------------
# Maps service names to their Docker Compose project names and directories
declare -A SERVICES
SERVICES=(
    ["prediction-radar"]="prediction-radar"
    ["ravynai"]="ravynai"
    ["trading"]="trading"
    ["ai-agents"]="ai-agents"
    ["analytics"]="analytics"
    ["monitoring"]="monitoring"
    ["postgres"]="data"
    ["redis"]="data"
    ["messaging"]="messaging"
    ["traefik"]="traefik"
    ["management"]="management"
)

# Health check endpoints for each service
declare -A HEALTH_URLS
HEALTH_URLS=(
    ["prediction-radar"]="http://localhost:8000/health"
    ["ravynai"]="http://localhost:8007/health"
    ["ai-agents"]="http://localhost:8001/health"
    ["analytics"]="http://localhost:8088/health"
    ["monitoring"]="http://localhost:3002/api/health"
    ["traefik"]="http://localhost:8080/ping"
)

# Health check commands (for services without HTTP endpoints)
declare -A HEALTH_CMDS
HEALTH_CMDS=(
    ["postgres"]="pg_isready -h localhost -p 5432"
    ["redis"]="redis-cli -h localhost ping"
    ["messaging"]="curl -s http://localhost:8222/ | grep -q 'NATS'"
)

# --- Find the compose directory for a service ---------------------------------
get_compose_dir() {
    local service="$1"
    local project="${SERVICES[$service]:-}"

    if [[ -z "$project" ]]; then
        echo ""
        return 1
    fi

    # Look for the release directory via symlink
    local app_deploy_dir="${DEPLOY_DIR}/${service}"
    if [[ -L "${app_deploy_dir}/current" ]]; then
        readlink "${app_deploy_dir}/current"
        return 0
    fi

    # Fallback: check if there's a direct compose path
    if [[ -d "${BASE_DIR}/apps/${service}" ]]; then
        echo "${BASE_DIR}/apps/${service}"
        return 0
    fi

    echo ""
    return 1
}

# --- Action: Start -----------------------------------------------------------
cmd_start() {
    local service="$1"

    local compose_dir
    compose_dir=$(get_compose_dir "$service") || {
        error "No deployment found for ${service}. Deploy it first."
        return 1
    }

    if [[ ! -f "${compose_dir}/docker-compose.yml" ]]; then
        error "No docker-compose.yml in ${compose_dir}"
        return 1
    fi

    local project="${SERVICES[$service]}"

    info "Starting ${service} (project: ${project})..."
    cd "$compose_dir"
    docker compose --project-name "$project" up -d 2>&1

    # Check result
    if docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up"; then
        success "${service} started successfully"
    else
        error "${service} failed to start. Check logs."
        docker compose --project-name "$project" ps 2>&1
        return 1
    fi
}

# --- Action: Stop ------------------------------------------------------------
cmd_stop() {
    local service="$1"
    local project="${SERVICES[$service]:-}"
    local timeout="${2:-30}"

    if [[ -z "$project" ]]; then
        error "Unknown service: ${service}"
        return 1
    fi

    info "Stopping ${service} (project: ${project})..."

    if docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up\|Running"; then
        docker compose --project-name "$project" down --timeout "$timeout" 2>&1 || {
            warn "Graceful stop failed, forcing..."
            docker compose --project-name "$project" down --timeout 0 2>&1
        }
        success "${service} stopped"
    else
        info "${service} is not running"
    fi
}

# --- Action: Restart ---------------------------------------------------------
cmd_restart() {
    local service="$1"

    info "Restarting ${service}..."
    cmd_stop "$service" 10
    sleep 2
    cmd_start "$service"

    # Run health check after restart
    cmd_health "$service" || {
        warn "Health check after restart failed for ${service}"
    }
}

# --- Action: Status ----------------------------------------------------------
cmd_status() {
    local service="${1:-}"

    if [[ -n "$service" ]]; then
        # Single service
        local project="${SERVICES[$service]:-}"
        if [[ -z "$project" ]]; then
            error "Unknown service: ${service}"
            return 1
        fi

        header "${service} (project: ${project})"
        docker compose --project-name "$project" ps 2>/dev/null || {
            warn "No containers found for ${service}"
        }
    else
        # All services
        header "All Services — Hetzner CPX51"
        echo ""

        for service_name in "${!SERVICES[@]}"; do
            local project="${SERVICES[$service_name]}"
            local status_text
            status_text=$(docker compose --project-name "$project" ps --format '{{.Name}} {{.Status}}' 2>/dev/null || echo "Not deployed")

            if echo "$status_text" | grep -q "Up"; then
                echo -e "  ${GREEN}✓${NC} ${service_name} (${project})"
            elif echo "$status_text" | grep -q "Not deployed"; then
                echo -e "  ${YELLOW}─${NC} ${service_name} (${project}) — not deployed"
            elif echo "$status_text" | grep -q "Exit\|Paused"; then
                echo -e "  ${RED}✗${NC} ${service_name} (${project}) — not running"
            else
                echo -e "  ${YELLOW}?${NC} ${service_name} (${project})"
            fi
        done

        echo ""
        header "Container Details"
        # Show all running containers managed by our projects
        for project in "${SERVICES[@]}"; do
            docker compose --project-name "$project" ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
        done 2>/dev/null | sort -u
    fi
}

# --- Action: Logs ------------------------------------------------------------
cmd_logs() {
    local service="$1"
    shift
    local tail_lines="${1:-50}"
    local follow="${2:-}"

    local project="${SERVICES[$service]:-}"
    if [[ -z "$project" ]]; then
        error "Unknown service: ${service}"
        return 1
    fi

    if [[ "$follow" == "--follow" ]] || [[ "$follow" == "-f" ]]; then
        docker compose --project-name "$project" logs --tail "$tail_lines" --follow 2>/dev/null
    else
        docker compose --project-name "$project" logs --tail "$tail_lines" 2>/dev/null
    fi
}

# --- Action: Health ----------------------------------------------------------
cmd_health() {
    local service="$1"

    header "Health Check: ${service}"

    # Check if service has containers running
    local project="${SERVICES[$service]:-}"
    if [[ -z "$project" ]]; then
        error "Unknown service: ${service}"
        return 1
    fi

    if ! docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up"; then
        error "${service}: Not running"
        return 1
    fi

    # Try health check URL
    local url="${HEALTH_URLS[$service]:-}"
    if [[ -n "$url" ]]; then
        local http_code
        http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            success "${service}: HEALTHY (HTTP ${http_code})"
            return 0
        else
            error "${service}: UNHEALTHY (HTTP ${http_code})"
            return 1
        fi
    fi

    # Try health check command
    local cmd="${HEALTH_CMDS[$service]:-}"
    if [[ -n "$cmd" ]]; then
        if eval "$cmd" 2>/dev/null; then
            success "${service}: HEALTHY (cmd)"
            return 0
        else
            error "${service}: UNHEALTHY (cmd failed)"
            return 1
        fi
    fi

    # No specific health check — containers are up
    success "${service}: Running (no specific health check)"
    return 0
}

# --- Action: Update ----------------------------------------------------------
cmd_update() {
    local service="$1"

    local compose_dir
    compose_dir=$(get_compose_dir "$service") || {
        error "No deployment found for ${service}. Deploy it first."
        return 1
    }

    if [[ ! -f "${compose_dir}/docker-compose.yml" ]]; then
        error "No docker-compose.yml in ${compose_dir}"
        return 1
    fi

    local project="${SERVICES[$service]}"

    info "Updating ${service} — pulling latest images..."

    cd "$compose_dir"
    docker compose --project-name "$project" pull 2>&1

    info "Recreating containers..."
    docker compose --project-name "$project" up -d --force-recreate 2>&1

    info "Cleaning old images..."
    docker image prune -f 2>/dev/null || true

    if docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up"; then
        success "${service} updated successfully"
        cmd_health "$service" || true
    else
        error "${service} update failed"
        return 1
    fi
}

# --- Action: PS --------------------------------------------------------------
cmd_ps() {
    local service="${1:-}"

    if [[ -n "$service" ]]; then
        local project="${SERVICES[$service]:-}"
        if [[ -z "$project" ]]; then
            error "Unknown service: ${service}"
            return 1
        fi
        docker compose --project-name "$project" ps 2>/dev/null || true
    else
        # Show all containers grouped by project
        for project in $(printf "%s\n" "${SERVICES[@]}" | sort -u); do
            local containers
            containers=$(docker compose --project-name "$project" ps 2>/dev/null || true)
            if [[ -n "$containers" ]] && echo "$containers" | grep -qv "NAME"; then
                echo ""
                header "Project: ${project}"
                echo "$containers"
            fi
        done
    fi
}

# --- Action: Stats -----------------------------------------------------------
cmd_stats() {
    local service="${1:-}"

    if [[ -n "$service" ]]; then
        local project="${SERVICES[$service]:-}"
        if [[ -z "$project" ]]; then
            error "Unknown service: ${service}"
            return 1
        fi

        header "Resource Usage: ${service}"

        # Get container IDs for this project
        local container_ids
        container_ids=$(docker compose --project-name "$project" ps -q 2>/dev/null || true)

        if [[ -z "$container_ids" ]]; then
            info "No running containers for ${service}"
            return 0
        fi

        docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}' $(echo "$container_ids") 2>/dev/null || true
    else
        header "Resource Usage — All Containers"
        docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}' 2>/dev/null || true
    fi
}

# --- List available services -------------------------------------------------
list_services() {
    echo ""
    echo "Available services (Hetzner CPX51):"
    echo "----------------------------------------"
    for service in "${!SERVICES[@]}"; do
        echo "  - ${service}"
    done | sort
    echo ""
}

# --- Usage -------------------------------------------------------------------
usage() {
    echo "Usage: $0 <action> [service] [options]"
    echo ""
    echo "Actions:"
    echo "  start    <service>   Start service"
    echo "  stop     <service>   Stop service"
    echo "  restart  <service>   Restart service"
    echo "  status   [service]   Show status"
    echo "  logs     <service>   Show logs (add -f to follow)"
    echo "  health   <service>   Run health check"
    echo "  update   <service>   Pull images and restart"
    echo "  ps       [service]   List containers"
    echo "  stats    [service]   Show resource usage"
    echo ""
    list_services
}

# --- Main --------------------------------------------------------------------
main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    local action="$1"
    shift

    case "$action" in
        start|stop|restart|health|update|logs|ps|stats)
            local service="${1:-}"
            if [[ "$action" != "ps" ]] && [[ "$action" != "stats" ]]; then
                if [[ -z "$service" ]]; then
                    error "Service name required for action: ${action}"
                    list_services
                    exit 1
                fi
                if [[ -z "${SERVICES[$service]:-}" ]]; then
                    error "Unknown service: ${service}"
                    list_services
                    exit 1
                fi
            fi

            case "$action" in
                start)   cmd_start "$service" ;;
                stop)    cmd_stop "$service" ;;
                restart) cmd_restart "$service" ;;
                health)  cmd_health "$service" ;;
                update)  cmd_update "$service" ;;
                logs)    cmd_logs "$service" "$@" ;;
                ps)      cmd_ps "${1:-}" ;;
                stats)   cmd_stats "${1:-}" ;;
            esac
            ;;
        status)
            cmd_status "${1:-}"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            error "Unknown action: ${action}"
            usage
            exit 1
            ;;
    esac
}

main "$@"
