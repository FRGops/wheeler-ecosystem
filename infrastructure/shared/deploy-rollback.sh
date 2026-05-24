#!/usr/bin/env bash
# ==============================================================================
# deploy-rollback.sh — Manual rollback script
# ==============================================================================
#
# Performs a controlled rollback of an application to its previous release.
# Shows deployment history, asks for confirmation, and performs health-gated
# rollback similar to the automatic rollback in deploy-release.sh.
#
# Usage:
#   ./deploy-rollback.sh <app-name> [--dry-run] [--force]
#   ./deploy-rollback.sh <app-name> --to <release-timestamp>
#
# Examples:
#   ./deploy-rollback.sh prediction-radar
#   ./deploy-rollback.sh ravynai --dry-run
#   ./deploy-rollback.sh frgops --force
#   ./deploy-rollback.sh prediction-radar --to 20250115-143022
#
# When to use manual rollback vs automatic:
#   - Automatic: deploy-release.sh handles this when health checks fail
#   - Manual: Use this when you discover a problem AFTER a successful deploy
#     (e.g., performance regression, data inconsistency, bug reports)
# ==============================================================================

set -euo pipefail

# --- Globals -----------------------------------------------------------------
BASE_DIR="${BASE_DIR:-/opt/wheeler}"
DEPLOY_DIR="${BASE_DIR}/deploy"
RELEASE_ROOT="${BASE_DIR}/releases"
HISTORY_LOG="${DEPLOY_DIR}/history.log"

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
step()    { echo -e "${CYAN}[STEP]${NC}  $*"; }

# --- Display deployment history ----------------------------------------------
show_history() {
    local app="$1"

    echo ""
    echo "=============================================="
    echo "  DEPLOYMENT HISTORY — ${app}"
    echo "=============================================="
    echo ""

    if [[ ! -f "$HISTORY_LOG" ]]; then
        warn "No deployment history found at ${HISTORY_LOG}"
        return 1
    fi

    # Filter history for this app, show last 15 entries
    grep " | ${app} | " "$HISTORY_LOG" | tail -15 | while IFS='  |  ' read -r date rest; do
        # Format nicely
        echo "  $rest"
    done

    # If the above doesn't match (pipe-separated), try raw format
    if ! grep -q " | ${app} | " "$HISTORY_LOG" 2>/dev/null; then
        # Fallback: show full history
        tail -20 "$HISTORY_LOG"
    fi

    echo ""
}

# --- Find releases -----------------------------------------------------------
find_releases() {
    local app="$1"
    ls -d "${RELEASE_ROOT}/"*-"${app}" 2>/dev/null | sort -r || true
}

# --- Show current state ------------------------------------------------------
show_current_state() {
    local app="$1"
    local app_deploy_dir="${DEPLOY_DIR}/${app}"

    echo ""
    echo "Current deployment state for ${app}:"
    echo "----------------------------------------"

    if [[ -L "${app_deploy_dir}/current" ]]; then
        local current
        current=$(readlink "${app_deploy_dir}/current")
        local current_base
        current_base=$(basename "$current")
        echo "  CURRENT:  ${current_base}  (${current})"
    else
        echo "  CURRENT:  (none)"
    fi

    if [[ -L "${app_deploy_dir}/previous" ]]; then
        local previous
        previous=$(readlink "${app_deploy_dir}/previous")
        local previous_base
        previous_base=$(basename "$previous")
        echo "  PREVIOUS: ${previous_base}  (${previous})"
    else
        echo "  PREVIOUS: (none)"
    fi

    # Show running containers
    local project="${app//-/_}"  # Simple project name derivation
    # Try common project names
    for pn in "$app" "${app//-/_}" "${app//-/}"; do
        if docker compose --project-name "$pn" ps 2>/dev/null | grep -q "Up"; then
            echo ""
            echo "  Running containers (project: ${pn}):"
            docker compose --project-name "$pn" ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
            break
        fi
    done

    echo ""
    echo "  Available releases:"
    local releases
    releases=$(find_releases "$app")
    if [[ -n "$releases" ]]; then
        local count=0
        for rel in $releases; do
            count=$((count + 1))
            local rel_base
            rel_base=$(basename "$rel")
            local marker="  "
            if [[ -L "${app_deploy_dir}/current" ]] && [[ "$(readlink "${app_deploy_dir}/current")" == "$rel" ]]; then
                marker="→ "
            elif [[ -L "${app_deploy_dir}/previous" ]] && [[ "$(readlink "${app_deploy_dir}/previous")" == "$rel" ]]; then
                marker="  "
            fi
            echo "  ${marker}${rel_base}"
            if [[ $count -ge 10 ]]; then
                echo "  ... (and $(echo "$releases" | wc -l) - ${count} more)"
                break
            fi
        done
    else
        echo "  (no releases found)"
    fi
}

# --- Confirm rollback --------------------------------------------------------
confirm_rollback() {
    local app="$1"
    local target="$2"

    echo ""
    warn "=============================================="
    warn "  YOU ARE ABOUT TO ROLLBACK ${app}"
    warn "=============================================="
    echo ""
    echo "  Current release: $(basename "$(readlink "${DEPLOY_DIR}/${app}/current" 2>/dev/null || echo "none")")"
    echo "  Target release:  $(basename "$target")"
    echo ""
    echo "  This will:"
    echo "    1. Stop all running containers for ${app}"
    echo "    2. Point the 'current' symlink to the target release"
    echo "    3. Start containers from the target release"
    echo "    4. Run health checks (up to 60s)"
    echo "    5. Log the rollback in history"
    echo ""
    read -r -p "  Type the app name to confirm rollback: " confirmation

    if [[ "$confirmation" != "$app" ]]; then
        error "Confirmation failed. Rollback cancelled."
        return 1
    fi

    echo ""
    return 0
}

# --- Perform the rollback ----------------------------------------------------
do_rollback() {
    local app="$1"
    local target="$2"
    local project="$3"

    step "Step 1: Stopping current release..."
    cd "$(readlink "${DEPLOY_DIR}/${app}/current" 2>/dev/null || echo "${target}")" 2>/dev/null || true
    docker compose --project-name "$project" down --timeout 30 2>&1 || {
        warn "Failed to stop containers gracefully, forcing..."
        docker compose --project-name "$project" down --timeout 0 2>&1 || true
    }
    success "Current release stopped"

    step "Step 2: Updating symlinks..."
    # Move current to previous
    if [[ -L "${DEPLOY_DIR}/${app}/current" ]]; then
        local old_current
        old_current=$(readlink "${DEPLOY_DIR}/${app}/current")
        if [[ -d "$old_current" ]]; then
            ln -sfn "$old_current" "${DEPLOY_DIR}/${app}/previous" 2>/dev/null || true
        fi
    fi

    # Point current to target
    ln -sfn "$target" "${DEPLOY_DIR}/${app}/current"
    success "Symlinks updated"
    info "  current  -> ${target}"

    step "Step 3: Starting target release..."
    cd "$target"
    if [[ ! -f "docker-compose.yml" ]]; then
        error "No docker-compose.yml in target release. Aborting."
        return 1
    fi

    docker compose --project-name "$project" up -d 2>&1
    success "Target release started"

    step "Step 4: Running health checks..."
    # Health check using the same logic as deploy-release.sh
    local health_url=""
    local health_cmd=""
    local max_retries=30

    # Determine health check based on app
    case "$app" in
        prediction-radar)
            health_url="http://localhost:8000/health"
            ;;
        ravynai)
            health_url="http://localhost:8007/health"
            ;;
        frgops)
            health_url="http://localhost:3000/health"
            ;;
        trading)
            health_cmd="docker compose --project-name trading ps --filter status=running --services | grep -q ."
            ;;
        postgres)
            health_cmd="pg_isready -h localhost -p 5432"
            ;;
        redis)
            health_cmd="redis-cli -h localhost ping"
            ;;
        traefik)
            health_url="http://localhost:8080/ping"
            ;;
        n8n)
            health_url="http://localhost:5678/healthz"
            ;;
        analytics)
            health_url="http://localhost:8088/health"
            ;;
        monitoring)
            health_url="http://localhost:3002/api/health"
            ;;
        ai-agents)
            health_url="http://localhost:8001/health"
            ;;
        messaging)
            health_cmd="curl -s http://localhost:8222/ | grep -q 'NATS'"
            ;;
    esac

    local healthy=false
    if [[ -n "$health_cmd" ]]; then
        for ((i=1; i<=max_retries; i++)); do
            if eval "$health_cmd" 2>/dev/null; then
                healthy=true
                break
            fi
            sleep 2
        done
    elif [[ -n "$health_url" ]]; then
        for ((i=1; i<=max_retries; i++)); do
            local http_code
            http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$health_url" 2>/dev/null || echo "000")
            if [[ "$http_code" = "200" ]]; then
                healthy=true
                break
            fi
            sleep 2
        done
    else
        # No health check defined, just check containers are up
        sleep 5
        if docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up"; then
            healthy=true
        fi
    fi

    if [[ "$healthy" == "true" ]]; then
        success "Rollback health checks passed!"
        return 0
    else
        error "Rollback health checks FAILED!"
        return 1
    fi
}

# --- Handle failed rollback --------------------------------------------------
handle_failed_rollback() {
    local app="$1"
    local target="$2"
    local project="$3"

    error "=============================================="
    error "  ROLLBACK FAILED — Attempting recovery"
    error "=============================================="

    # Try to restore the original current release
    local app_deploy_dir="${DEPLOY_DIR}/${app}"

    # Stop the broken target
    cd "$target" 2>/dev/null || true
    docker compose --project-name "$project" down --timeout 0 2>&1 || true

    # Restore previous (which was the original current)
    if [[ -L "${app_deploy_dir}/previous" ]]; then
        local restore_target
        restore_target=$(readlink "${app_deploy_dir}/previous")

        if [[ -d "$restore_target" ]]; then
            warn "Restoring original release: ${restore_target}"
            ln -sfn "$restore_target" "${app_deploy_dir}/current"

            cd "$restore_target"
            if [[ -f "docker-compose.yml" ]]; then
                docker compose --project-name "$project" up -d 2>&1

                # Check if it's healthy
                sleep 5
                if docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up"; then
                    success "Original release restored successfully"
                    log_history "$app" "ROLLBACK_FAILED" "RECOVERED" "$restore_target" "Rollback to target failed, restored original"
                    return 0
                fi
            fi
        fi
    fi

    error "CRITICAL: Could not restore any working release!"
    error "Manual intervention required for ${app}"
    log_history "$app" "ROLLBACK_FAILED" "CRITICAL" "unknown" "Both rollback target and original failed"
    return 1
}

# --- Log rollback ------------------------------------------------------------
log_rollback() {
    local app="$1"
    local target="$2"
    local status="$3"
    local message="${4:-}"

    local entry
    entry="$(date -u '+%Y-%m-%d %H:%M:%S') | ${app} | ROLLBACK | ${status} | ${target} | ${message}"

    mkdir -p "$(dirname "$HISTORY_LOG")"
    echo "$entry" >> "$HISTORY_LOG"
    tail -n 500 "$HISTORY_LOG" > "${HISTORY_LOG}.tmp" && mv "${HISTORY_LOG}.tmp" "$HISTORY_LOG"

    info "[HISTORY] Rollback recorded"
}

# --- Dry run -----------------------------------------------------------------
dry_run() {
    local app="$1"

    echo ""
    echo "=============================================="
    echo "  DRY RUN — Rollback ${app}"
    echo "=============================================="
    echo ""
    echo "Would execute:"
    echo "  1. Show deployment history for ${app}"
    echo "  2. Show current state (current/previous symlinks, running containers)"
    echo "  3. Ask for confirmation"
    echo "  4. Stop current release containers"
    echo "  5. Update symlinks: current -> previous"
    echo "  6. Start previous release containers"
    echo "  7. Run health checks (up to 60s)"
    echo "  8. On success: log rollback record"
    echo "  9. On failure: restore original release, alert"
    echo ""
    info "Run without --dry-run to execute."

    exit 0
}

# --- Pre-rollback validation -------------------------------------------------
pre_rollback_checks() {
    local app="$1"
    local target="$2"

    step "Pre-rollback validation..."

    # Check target exists
    if [[ ! -d "$target" ]]; then
        error "Target release directory does not exist: ${target}"
        return 1
    fi

    # Check target has docker-compose.yml
    if [[ ! -f "${target}/docker-compose.yml" ]]; then
        error "Target release has no docker-compose.yml: ${target}"
        return 1
    fi

    # Check Docker is running
    if ! docker info &>/dev/null; then
        error "Docker is not running"
        return 1
    fi

    # Check target has .env (warn if not)
    if [[ ! -f "${target}/.env" ]] && [[ ! -L "${target}/.env" ]]; then
        warn "Target release has no .env file. Environment may not be configured."
    fi

    success "Pre-rollback validation passed"
    return 0
}

# --- Main --------------------------------------------------------------------
main() {
    local APP=""
    local TARGET_TIMESTAMP=""
    local DRY_RUN_FLAG=false
    local FORCE=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN_FLAG=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --to)
                TARGET_TIMESTAMP="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 <app-name> [options]"
                echo ""
                echo "Options:"
                echo "  --dry-run        Show what would be done"
                echo "  --force          Skip confirmation prompt"
                echo "  --to <timestamp> Rollback to a specific release (e.g., 20250115-143022)"
                echo "                   Default: previous release"
                echo ""
                echo "Examples:"
                echo "  $0 prediction-radar                # Rollback to previous release"
                echo "  $0 ravynai --to 20250115-143022    # Rollback to specific release"
                echo "  $0 frgops --dry-run                # Preview without changes"
                exit 0
                ;;
            *)
                if [[ -z "$APP" ]]; then
                    APP="$1"
                else
                    error "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$APP" ]]; then
        error "Usage: $0 <app-name> [options]"
        error "Run $0 --help for details."
        exit 1
    fi

    if [[ "$DRY_RUN_FLAG" == "true" ]]; then
        dry_run "$APP"
        return 0
    fi

    # Validate app has a deployment directory
    local app_deploy_dir="${DEPLOY_DIR}/${APP}"
    if [[ ! -d "$app_deploy_dir" ]] && [[ ! -L "${app_deploy_dir}/current" ]]; then
        error "No deployment found for ${app_deploy_dir}"
        error "Has this application been deployed yet?"
        exit 1
    fi

    echo "=============================================="
    echo "  ROLLBACK — ${APP}"
    echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "=============================================="

    show_history "$APP"
    show_current_state "$APP"

    # Determine rollback target
    local TARGET=""
    if [[ -n "$TARGET_TIMESTAMP" ]]; then
        # User specified a specific release
        TARGET="${RELEASE_ROOT}/${TARGET_TIMESTAMP}-${APP}"
        if [[ ! -d "$TARGET" ]]; then
            error "Specified release not found: ${TARGET}"
            # Try to find it
            local found
            found=$(ls -d "${RELEASE_ROOT}/"*"${TARGET_TIMESTAMP}*" 2>/dev/null | head -1 || true)
            if [[ -n "$found" ]]; then
                info "Did you mean: ${found}?"
            fi
            exit 1
        fi
        info "Rollback target: ${TARGET}"
    else
        # Use the previous symlink
        if [[ ! -L "${app_deploy_dir}/previous" ]]; then
            error "No previous release symlink found."
            error "Use --to <timestamp> to specify a specific release."
            error ""
            error "Available releases:"
            find_releases "$APP" | head -10 || true
            exit 1
        fi
        TARGET=$(readlink "${app_deploy_dir}/previous")
        info "Rollback target (previous): ${TARGET}"
    fi

    # Derive project name
    local PROJECT="${APP}"

    # Pre-rollback checks
    if ! pre_rollback_checks "$APP" "$TARGET"; then
        exit 1
    fi

    # Confirmation
    if [[ "$FORCE" != "true" ]]; then
        if ! confirm_rollback "$APP" "$TARGET"; then
            warn "Rollback cancelled by user."
            exit 0
        fi
    else
        warn "FORCE mode: skipping confirmation."
    fi

    # Execute rollback
    echo ""
    if do_rollback "$APP" "$TARGET" "$PROJECT"; then
        log_rollback "$APP" "$TARGET" "SUCCESS"
        success "Rollback of ${APP} completed successfully!"
        echo ""
        info "Current release: $(basename "$(readlink "${app_deploy_dir}/current")")"
    else
        log_rollback "$APP" "$TARGET" "FAILED"
        error "Rollback failed!"
        handle_failed_rollback "$APP" "$TARGET" "$PROJECT" || true
        exit 1
    fi
}

main "$@"
