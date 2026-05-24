#!/usr/bin/env bash
# ==============================================================================
# deploy-all.sh — Full-stack deployment orchestrator
# ==============================================================================
#
# Orchestrates a complete stack deployment in dependency order. Each layer
# must be fully healthy before proceeding to the next.
#
# Usage:
#   ./deploy-all.sh [--dry-run] [--ref <git-ref>] [--skip <app>] [--only <app>]
#                   [--env <file>] [--server <hetzner|hostinger>]
#
# Examples:
#   ./deploy-all.sh                              # Deploy all with default refs
#   ./deploy-all.sh --dry-run                     # Preview what would deploy
#   ./deploy-all.sh --ref main                    # Deploy all from main
#   ./deploy-all.sh --skip monitoring             # Skip monitoring
#   ./deploy-all.sh --only prediction-radar       # Only deploy one app
#   ./deploy-all.sh --server hostinger            # Deploy only Hostinger apps
#
# Deployment Order (Dependency Chain):
#   Layer 1:  Shared Infrastructure (networks, volumes)
#   Layer 2:  Databases (Postgres, Redis)
#   Layer 3:  Message Queues (NATS/RabbitMQ)
#   Layer 4:  Backend Services (APIs, workers)
#   Layer 5:  Frontend Services (web apps)
#   Layer 6:  Monitoring & Analytics
#   Layer 7:  Traefik / Reverse Proxy (last — so upstream routes exist)
#
# This ordering ensures that when a frontend starts up and tries to connect
# to its API, the API is already running and healthy.
# ==============================================================================

set -euo pipefail

# --- Globals -----------------------------------------------------------------
BASE_DIR="${BASE_DIR:-/opt/wheeler}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy-release.sh"
HISTORY_LOG="${BASE_DIR}/deploy/history.log"
DEPLOY_REF="${DEPLOY_REF:-main}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
step()    { echo -e "${CYAN}[STEP]${NC}  $*"; }
header()  { echo -e "\n${MAGENTA}═══════════════════════════════════════════════${NC}"; echo -e "${MAGENTA}  $*${NC}"; echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}\n"; }

# --- Application dependency layers -------------------------------------------
# These map to the ARCHITECTURE.md service placement matrix

LAYER_1_NETWORKING="traefik management"          # Shared infrastructure
LAYER_2_DATA="postgres redis"                     # Databases
LAYER_3_MESSAGING="messaging"                     # Message queues
LAYER_4_BACKEND="prediction-radar ravynai trading ai-agents"  # Backend services
LAYER_5_FRONTEND=""                               # Frontend (separate layer)
LAYER_6_MONITORING="analytics monitoring"         # Analytics + monitoring
LAYER_7_PROXY=""                                  # Traefik already in layer 1

# Hostinger-specific apps (deployed separately)
HOSTINGER_APPS="frgops n8n"

# All apps in dependency order
ALL_LAYERS=(
    "LAYER_1_NETWORKING"
    "LAYER_2_DATA"
    "LAYER_3_MESSAGING"
    "LAYER_4_BACKEND"
    "LAYER_6_MONITORING"
)

# Server-specific config
HETZNER_APPS="prediction-radar ravynai trading ai-agents analytics monitoring postgres redis messaging traefik management"

# --- State tracking ----------------------------------------------------------
DEPLOY_RESULTS=()  # Array of "app:status" strings
START_TIME=""
SKIP_APPS=()
ONLY_APPS=()
DEPLOY_SERVER=""

# --- Server detection ---------------------------------------------------------
detect_server() {
    local hostname
    hostname=$(hostname)

    if echo "$hostname" | grep -qi "hetzner\|cpx51\|primary"; then
        echo "hetzner"
    elif echo "$hostname" | grep -qi "hostinger\|vps\|edge"; then
        echo "hostinger"
    else
        echo "unknown"
    fi
}

# --- Determine which apps to deploy on this server ---------------------------
get_apps_for_server() {
    local server="$1"

    if [[ "$server" == "hetzner" ]]; then
        echo "$HETZNER_APPS"
    elif [[ "$server" == "hostinger" ]]; then
        echo "$HOSTINGER_APPS"
    else
        # Deploy everything (might fail, but try)
        echo "$HETZNER_APPS $HOSTINGER_APPS"
    fi
}

# --- Deploy a single app with status tracking --------------------------------
deploy_app() {
    local app="$1"
    local ref="$2"
    local dry_run="${3:-false}"

    # Check if app is in skip list
    for skip in "${SKIP_APPS[@]}"; do
        if [[ "$skip" == "$app" ]]; then
            info "[SKIP] ${app} (in skip list)"
            DEPLOY_RESULTS+=("${app}:skipped")
            return 0
        fi
    done

    # Check if only list is set and app is in it
    if [[ ${#ONLY_APPS[@]} -gt 0 ]]; then
        local found=false
        for only in "${ONLY_APPS[@]}"; do
            if [[ "$only" == "$app" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            info "[SKIP] ${app} (not in --only list)"
            DEPLOY_RESULTS+=("${app}:skipped")
            return 0
        fi
    fi

    step "Deploying ${app} @ ${ref}..."

    if [[ "$dry_run" == "true" ]]; then
        if [[ -x "$DEPLOY_SCRIPT" ]]; then
            bash "$DEPLOY_SCRIPT" "$app" "$ref" --dry-run
        fi
        DEPLOY_RESULTS+=("${app}:would-deploy")
        return 0
    fi

    if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
        error "Deploy script not found or not executable: ${DEPLOY_SCRIPT}"
        DEPLOY_RESULTS+=("${app}:failed")
        return 1
    fi

    local start
    start=$(date +%s)

    # Execute the deployment
    if bash "$DEPLOY_SCRIPT" "$app" "$ref"; then
        local duration=$(( $(date +%s) - start ))
        success "${app} deployed successfully (${duration}s)"
        DEPLOY_RESULTS+=("${app}:success:${duration}s")
        return 0
    else
        local duration=$(( $(date +%s) - start ))
        error "${app} deployment FAILED (${duration}s)"
        DEPLOY_RESULTS+=("${app}:failed:${duration}s")
        return 1
    fi
}

# --- Deploy a layer of apps ---------------------------------------------------
deploy_layer() {
    local layer_name="$1"
    local ref="$2"
    local dry_run="${3:-false}"
    shift 3
    local apps=("$@")

    header "Layer: ${layer_name}"
    info "Apps in this layer: ${apps[*]}"

    local layer_failures=0

    for app in "${apps[@]}"; do
        if ! deploy_app "$app" "$ref" "$dry_run"; then
            layer_failures=$((layer_failures + 1))
        fi
    done

    if [[ $layer_failures -gt 0 ]]; then
        if [[ "$dry_run" != "true" ]]; then
            warn "${layer_failures} app(s) failed in layer ${layer_name}"
            warn "Continuing to next layer (apps may have interdependencies)"
        fi
    else
        success "Layer '${layer_name}' complete"
    fi

    # Brief pause between layers for stability
    if [[ "$dry_run" != "true" ]]; then
        sleep 2
    fi
}

# --- Pre-flight checks -------------------------------------------------------
pre_flight_checks() {
    step "Running orchestrator pre-flight checks..."

    # Check deploy script exists
    if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
        error "Deploy script not found: ${DEPLOY_SCRIPT}"
        exit 1
    fi

    # Check Docker
    if ! docker info &>/dev/null; then
        error "Docker is not running"
        exit 1
    fi

    # Check disk space
    local available_space
    available_space=$(df --output=avail /opt 2>/dev/null | tail -1 || echo "0")
    if [[ "$available_space" -lt 5000000 ]]; then  # 5GB in KB
        warn "Low disk space on /opt: $(( available_space / 1024 / 1024 )) GB available"
    fi

    # Check memory
    local mem_available
    mem_available=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo "0")
    if [[ "$mem_available" -lt 1000000 ]]; then  # 1GB in KB
        warn "Low memory: $(( mem_available / 1024 )) MB available"
    fi

    success "Pre-flight checks passed"
    return 0
}

# --- Print deployment report --------------------------------------------------
print_report() {
    local total_time="$1"
    local exit_code="$2"

    echo ""
    echo "=============================================="
    echo "  DEPLOYMENT SUMMARY REPORT"
    echo "=============================================="
    echo ""

    local successes=0
    local failures=0
    local skipped=0
    local would_deploy=0

    for result in "${DEPLOY_RESULTS[@]}"; do
        local app="${result%%:*}"
        local status="${result#*:}"
        status="${status%%:*}"
        local detail="${result#*:*:}"

        case "$status" in
            success)
                successes=$((successes + 1))
                echo -e "  ${GREEN}✓${NC} ${app} (${detail})"
                ;;
            failed)
                failures=$((failures + 1))
                echo -e "  ${RED}✗${NC} ${app} (${detail})"
                ;;
            skipped)
                skipped=$((skipped + 1))
                echo -e "  ${YELLOW}─${NC} ${app} (skipped)"
                ;;
            would-deploy)
                would_deploy=$((would_deploy + 1))
                echo -e "  ${BLUE}~${NC} ${app} (would deploy)"
                ;;
        esac
    done

    echo ""
    echo "----------------------------------------------"
    echo "  Total time:  ${total_time}"
    echo "  Successful:  ${successes}"
    echo "  Failed:      ${failures}"
    echo "  Skipped:     ${skipped}"
    echo "  Would-deploy: ${would_deploy}"
    echo "  Exit code:   ${exit_code}"
    echo "----------------------------------------------"

    if [[ $failures -gt 0 ]]; then
        echo ""
        warn "Some deployments failed. Check logs above for details."
        echo "  Failed apps:"
        for result in "${DEPLOY_RESULTS[@]}"; do
            if [[ "$result" == *":failed"* ]]; then
                echo "    - ${result%%:*}"
            fi
        done
    fi

    echo ""
}

# --- Print pre-deployment plan -----------------------------------------------
print_plan() {
    local server="$1"
    local ref="$2"
    shift 2
    local apps=("$@")

    echo ""
    echo "=============================================="
    echo "  DEPLOYMENT PLAN"
    echo "=============================================="
    echo ""
    echo "  Server:      ${server} ($(hostname))"
    echo "  Git ref:     ${ref}"
    echo "  Timestamp:   $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""

    if [[ ${#ONLY_APPS[@]} -gt 0 ]]; then
        echo "  Only apps:   ${ONLY_APPS[*]}"
    fi
    if [[ ${#SKIP_APPS[@]} -gt 0 ]]; then
        echo "  Skip apps:   ${SKIP_APPS[*]}"
    fi

    echo ""
    echo "  Deployment order:"
    echo "  ────────────────────────────────────────────"

    local -A layer_map=(
        ["LAYER_1_NETWORKING"]="Layer 1: Networking & Infrastructure"
        ["LAYER_2_DATA"]="Layer 2: Databases"
        ["LAYER_3_MESSAGING"]="Layer 3: Message Queues"
        ["LAYER_4_BACKEND"]="Layer 4: Backend Services"
        ["LAYER_6_MONITORING"]="Layer 5: Analytics & Monitoring"
    )

    for layer_var in "${ALL_LAYERS[@]}"; do
        local layer_name="${layer_map[$layer_var]:-${layer_var}}"
        local -n layer_apps="$layer_var"
        local layer_apps_list=()

        for app in $layer_apps; do
            # Filter by server
            local server_apps
            server_apps=$(get_apps_for_server "$server")
            if echo "$server_apps" | grep -qw "$app"; then
                # Check skip/only
                local include=true
                for skip in "${SKIP_APPS[@]}"; do
                    if [[ "$skip" == "$app" ]]; then include=false; fi
                done
                if [[ ${#ONLY_APPS[@]} -gt 0 ]]; then
                    include=false
                    for only in "${ONLY_APPS[@]}"; do
                        if [[ "$only" == "$app" ]]; then include=true; fi
                    done
                fi
                if [[ "$include" == "true" ]]; then
                    layer_apps_list+=("$app")
                fi
            fi
        done

        if [[ ${#layer_apps_list[@]} -gt 0 ]]; then
            echo "    ${layer_name}:"
            for app in "${layer_apps_list[@]}"; do
                echo "      - ${app} @ ${ref}"
            done
        fi
    done

    echo ""
    echo "  Total apps to deploy: ${#apps[@]}"
    echo ""
}

# --- Deploy server-specific apps ---------------------------------------------
deploy_server_apps() {
    local server="$1"
    local ref="$2"
    local dry_run="${3:-false}"

    # Get apps for this server
    local -a apps_to_deploy=()

    for layer_var in "${ALL_LAYERS[@]}"; do
        local -n layer_apps="$layer_var"
        for app in $layer_apps; do
            local server_apps
            server_apps=$(get_apps_for_server "$server")
            if echo "$server_apps" | grep -qw "$app"; then
                apps_to_deploy+=("$app")
            fi
        done
    done

    if [[ ${#apps_to_deploy[@]} -eq 0 ]]; then
        warn "No apps to deploy on ${server}"
        return 0
    fi

    # Print plan
    print_plan "$server" "$ref" "${apps_to_deploy[@]}"

    if [[ "$dry_run" == "true" ]]; then
        return 0
    fi

    # Deploy layer by layer
    for layer_var in "${ALL_LAYERS[@]}"; do
        local layer_name
        case "$layer_var" in
            LAYER_1_NETWORKING) layer_name="Networking & Infrastructure" ;;
            LAYER_2_DATA)       layer_name="Databases" ;;
            LAYER_3_MESSAGING)  layer_name="Message Queues" ;;
            LAYER_4_BACKEND)    layer_name="Backend Services" ;;
            LAYER_6_MONITORING) layer_name="Analytics & Monitoring" ;;
            *)                  layer_name="$layer_var" ;;
        esac

        local -n layer_apps="$layer_var"
        local -a layer_list=()

        for app in $layer_apps; do
            local server_apps
            server_apps=$(get_apps_for_server "$server")
            if echo "$server_apps" | grep -qw "$app"; then
                layer_list+=("$app")
            fi
        done

        if [[ ${#layer_list[@]} -gt 0 ]]; then
            deploy_layer "$layer_name" "$ref" "$dry_run" "${layer_list[@]}"
        fi
    done
}

# --- Main --------------------------------------------------------------------
main() {
    local DRY_RUN=false
    local REF="$DEPLOY_REF"
    local CUSTOM_ENV_FILE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --ref)
                REF="$2"
                shift 2
                ;;
            --skip)
                SKIP_APPS+=("$2")
                shift 2
                ;;
            --only)
                ONLY_APPS+=("$2")
                shift 2
                ;;
            --server)
                DEPLOY_SERVER="$2"
                shift 2
                ;;
            --env)
                CUSTOM_ENV_FILE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --dry-run            Preview the deployment plan"
                echo "  --ref <git-ref>      Git ref to deploy (default: main)"
                echo "  --skip <app>         Skip an application"
                echo "  --only <app>         Deploy only one application"
                echo "  --server <type>      Force server type (hetzner|hostinger)"
                echo "  --env <file>         Custom environment file"
                echo ""
                echo "Examples:"
                echo "  $0                                # Deploy all apps"
                echo "  $0 --dry-run                      # Preview only"
                echo "  $0 --ref production               # Deploy from 'production' branch"
                echo "  $0 --skip monitoring               # Skip monitoring layer"
                echo "  $0 --only prediction-radar        # Only deploy prediction-radar"
                echo "  $0 --server hostinger              # Only Hostinger apps"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    START_TIME=$(date +%s)

    echo "=============================================="
    echo "  WHEELER AIOPS — Full-Stack Deployment"
    echo "=============================================="
    echo ""

    # Detect or force server type
    local server
    if [[ -n "$DEPLOY_SERVER" ]]; then
        server="$DEPLOY_SERVER"
        info "Server type: ${server} (forced)"
    else
        server=$(detect_server)
        info "Server type: ${server} (auto-detected from hostname: $(hostname))"
    fi

    # Pre-flight checks (skip in dry run)
    if [[ "$DRY_RUN" == "false" ]]; then
        pre_flight_checks
    fi

    # Check for custom env file
    if [[ -n "$CUSTOM_ENV_FILE" ]] && [[ -f "$CUSTOM_ENV_FILE" ]]; then
        info "Using custom environment file: ${CUSTOM_ENV_FILE}"
        # shellcheck disable=SC1090
        source "$CUSTOM_ENV_FILE"
    fi

    # Detect if this is the right server for the selected apps
    if [[ ${#ONLY_APPS[@]} -gt 0 ]]; then
        for only_app in "${ONLY_APPS[@]}"; do
            local app_on_server
            app_on_server=$(get_apps_for_server "$server")
            if ! echo "$app_on_server" | grep -qw "$only_app"; then
                warn "${only_app} is not typically deployed on ${server}"
            fi
        done
    fi

    # Deploy
    deploy_server_apps "$server" "$REF" "$DRY_RUN"

    local end_time
    end_time=$(date +%s)
    local total_duration=$(( end_time - START_TIME ))
    local duration_min=$(( total_duration / 60 ))
    local duration_sec=$(( total_duration % 60 ))
    local duration_str="${duration_min}m ${duration_sec}s"

    # Determine exit code
    local exit_code=0
    for result in "${DEPLOY_RESULTS[@]}"; do
        if [[ "$result" == *":failed"* ]]; then
            exit_code=1
            break
        fi
    done

    print_report "$duration_str" "$exit_code"

    if [[ "$exit_code" -eq 0 ]]; then
        success "Full-stack deployment completed successfully!"
    else
        error "Full-stack deployment completed with failures."
        warn "Review the report above and check individual app logs."
        warn "Run: ./service-manager.sh logs <app-name>"
    fi

    return $exit_code
}

main "$@"
