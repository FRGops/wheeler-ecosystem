#!/usr/bin/env bash
# ==============================================================================
# service-manager.sh — Unified Service Management (Hostinger VPS / Edge)
# ==============================================================================
#
# Manages all services running on the Hostinger VPS edge server.
# Follows the same pattern as the Hetzner service manager but scoped to
# the lighter service set hosted on the edge.
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
# Services (Hostinger):
#   frgops, n8n, traefik, minio, webhooks, litellm, docuseal, chatwoot
#
# Examples:
#   ./service-manager.sh status               # All edge services
#   ./service-manager.sh status frgops         # Single service
#   ./service-manager.sh logs n8n --tail 100
#   ./service-manager.sh health traefik
#   ./service-manager.sh restart minio
# ==============================================================================

set -euo pipefail

# --- Globals -----------------------------------------------------------------
BASE_DIR="${BASE_DIR:-/opt/wheeler}"
DEPLOY_DIR="${BASE_DIR}/deploy"

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
# Maps service names to Docker Compose project names
declare -A SERVICES
SERVICES=(
    ["frgops"]="frgops"
    ["n8n"]="automation"
    ["traefik"]="traefik"
    ["minio"]="storage"
    ["webhooks"]="webhooks"
    ["litellm"]="ai-proxy"
    ["docuseal"]="frgops"
    ["chatwoot"]="frgops"
)

# Health check endpoints for each service
declare -A HEALTH_URLS
HEALTH_URLS=(
    ["frgops"]="http://localhost:3000/health"
    ["n8n"]="http://localhost:5678/healthz"
    ["traefik"]="http://localhost:8080/ping"
    ["minio"]="http://localhost:9001/minio/health/live"
    ["litellm"]="http://localhost:4000/health"
    ["docuseal"]="http://localhost:3000/health"
    ["chatwoot"]="http://localhost:3000/health"
)

# Health check commands (for services without HTTP endpoints)
declare -A HEALTH_CMDS
HEALTH_CMDS=(
    ["webhooks"]="ss -tlnp | grep -q ':9000'"
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

    # Fallback: apps directory
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
        error "No deployment found for ${service}."
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

    if docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up"; then
        success "${service} started"
    else
        error "${service} failed to start"
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
    cmd_health "$service" || true
}

# --- Action: Status ----------------------------------------------------------
cmd_status() {
    local service="${1:-}"

    if [[ -n "$service" ]]; then
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
        header "All Services — Hostinger VPS (Edge)"
        echo ""

        for service_name in "${!SERVICES[@]}"; do
            local project="${SERVICES[$service_name]}"
            local status_text
            status_text=$(docker compose --project-name "$project" ps --format '{{.Name}} {{.Status}}' 2>/dev/null || echo "Not deployed")

            if echo "$status_text" | grep -q "Up"; then
                echo -e "  ${GREEN}✓${NC} ${service_name} (${project})"
            else
                echo -e "  ${YELLOW}─${NC} ${service_name} — not deployed"
            fi
        done

        echo ""
        header "Container Details"
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

    local project="${SERVICES[$service]:-}"
    if [[ -z "$project" ]]; then
        error "Unknown service: ${service}"
        return 1
    fi

    docker compose --project-name "$project" logs --tail "$tail_lines" 2>/dev/null
}

# --- Action: Health ----------------------------------------------------------
cmd_health() {
    local service="$1"
    local project="${SERVICES[$service]:-}"

    header "Health Check: ${service}"

    if [[ -z "$project" ]]; then
        error "Unknown service: ${service}"
        return 1
    fi

    if ! docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up"; then
        error "${service}: Not running"
        return 1
    fi

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

    local cmd="${HEALTH_CMDS[$service]:-}"
    if [[ -n "$cmd" ]]; then
        if eval "$cmd" 2>/dev/null; then
            success "${service}: HEALTHY"
            return 0
        else
            error "${service}: UNHEALTHY"
            return 1
        fi
    fi

    success "${service}: Running (no specific check)"
    return 0
}

# --- Action: Update ----------------------------------------------------------
cmd_update() {
    local service="$1"
    local compose_dir
    compose_dir=$(get_compose_dir "$service") || {
        error "No deployment found for ${service}."
        return 1
    }

    local project="${SERVICES[$service]}"
    info "Updating ${service}..."

    cd "$compose_dir"
    docker compose --project-name "$project" pull 2>&1
    docker compose --project-name "$project" up -d --force-recreate 2>&1
    docker image prune -f 2>/dev/null || true

    if docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up"; then
        success "${service} updated"
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
        [[ -z "$project" ]] && { error "Unknown: ${service}"; return 1; }
        docker compose --project-name "$project" ps 2>/dev/null || true
    else
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
        [[ -z "$project" ]] && { error "Unknown: ${service}"; return 1; }
        local cids
        cids=$(docker compose --project-name "$project" ps -q 2>/dev/null || true)
        [[ -n "$cids" ]] && docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' $cids 2>/dev/null || true
    else
        docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' 2>/dev/null || true
    fi
}

# --- List services -----------------------------------------------------------
list_services() {
    echo ""
    echo "Available services (Hostinger VPS):"
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
    echo "  logs     <service>   Show logs"
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
        start|stop|restart|health|update|logs)
            local service="${1:-}"
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

            case "$action" in
                start)   cmd_start "$service" ;;
                stop)    cmd_stop "$service" ;;
                restart) cmd_restart "$service" ;;
                health)  cmd_health "$service" ;;
                update)  cmd_update "$service" ;;
                logs)    cmd_logs "$service" "$@" ;;
            esac
            ;;
        status)
            cmd_status "${1:-}"
            ;;
        ps)
            cmd_ps "${1:-}"
            ;;
        stats)
            cmd_stats "${1:-}"
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
