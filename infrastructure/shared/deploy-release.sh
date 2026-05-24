#!/usr/bin/env bash
# ==============================================================================
# deploy-release.sh — Release-based deployment script
# ==============================================================================
#
# Release-based deployment with health-gated rollback.
#
# Usage:
#   ./deploy-release.sh <app-name> <git-ref> [options]
#
# Options:
#   --rollback    Roll back to the previous release
#   --dry-run     Show what would be done without making changes
#   --force       Skip pre-flight checks (use with caution)
#   --skip-build  Use existing images, don't rebuild
#   --env-file    Specify an alternative .env file
#
# Examples:
#   ./deploy-release.sh prediction-radar main
#   ./deploy-release.sh ravynai v2.1.0
#   ./deploy-release.sh frgops feat/new-ui
#   ./deploy-release.sh prediction-radar main --rollback
#   ./deploy-release.sh --dry-run trading main
#
# Release Pattern (not blue-green, not Kubernetes):
#   Each deployment creates a timestamped release directory.
#   The "current" symlink points to the active release.
#   The "previous" symlink points to the previous release for rollback.
#   This is simpler than blue-green (which needs extra capacity) while
#   providing instant rollback capability.
#
# Rollback safety:
#   Every deployment step is checkpointed. If the health check fails after
#   bringing up the new release, the system automatically rolls back to the
#   previous release using the same health-gated process.
# ==============================================================================

set -euo pipefail

# --- Globals -----------------------------------------------------------------
BASE_DIR="${BASE_DIR:-/opt/wheeler}"
DEPLOY_DIR="${BASE_DIR}/deploy"
RELEASE_ROOT="${BASE_DIR}/releases"
REPO_BASE="${BASE_DIR}/repos"
HISTORY_LOG="${DEPLOY_DIR}/history.log"
TIMESTAMP=$(date -u '+%Y%m%d-%H%M%S')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output
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

# --- Annotated app configuration ---------------------------------------------
# Each app entry defines:
#   repo_url     - Git repository URL
#   compose_file - Docker compose file within the repo
#   health_url   - URL for health check (empty = skip HTTP health check)
#   health_cmd   - Alternative health check command (checked first)
#   project_name - Docker Compose project name
#   port         - Primary port for health checks
#   depends_on   - Apps that must be healthy first
#   env_required - Environment variables that must be set
#   server       - Which server this deploys to (hetzner|hostinger)
#
declare -A APP_CONFIG

# Helper: define app config
# Usage: define_app <name> <repo> <compose> <health_url> <health_cmd> <project> <port> <depends> <env_vars> <server>
define_app() {
    local name="$1"
    APP_CONFIG["${name}_repo_url"]="$2"
    APP_CONFIG["${name}_compose_file"]="$3"
    APP_CONFIG["${name}_health_url"]="$4"
    APP_CONFIG["${name}_health_cmd"]="$5"
    APP_CONFIG["${name}_project_name"]="$6"
    APP_CONFIG["${name}_port"]="$7"
    APP_CONFIG["${name}_depends_on"]="$8"
    APP_CONFIG["${name}_env_required"]="$9"
    APP_CONFIG["${name}_server"]="${10}"
}

# --- Application Definitions -------------------------------------------------
# These map to the service placement matrix in ARCHITECTURE.md

# HETZNER CPX51 APPS
define_app "prediction-radar" \
    "git@github.com:wheeler-io/prediction-radar.git" \
    "docker-compose.yml" \
    "http://localhost:8000/health" \
    "" \
    "prediction-radar" \
    "8000" \
    "postgres redis messaging" \
    "DATABASE_URL REDIS_URL SECRET_KEY" \
    "hetzner"

define_app "ravynai" \
    "git@github.com:wheeler-io/ravynai.git" \
    "docker-compose.yml" \
    "http://localhost:8007/health" \
    "" \
    "ravynai" \
    "8007" \
    "postgres redis messaging" \
    "DATABASE_URL REDIS_URL ANTHROPIC_API_KEY" \
    "hetzner"

define_app "trading" \
    "git@github.com:wheeler-io/trading-engine.git" \
    "docker-compose.yml" \
    "" \
    "docker compose --project-name trading ps --filter status=running --services | wc -l" \
    "trading" \
    "" \
    "postgres redis messaging" \
    "DATABASE_URL NATS_URL TRADING_API_KEY" \
    "hetzner"

define_app "ai-agents" \
    "git@github.com:wheeler-io/ai-agents.git" \
    "docker-compose.yml" \
    "http://localhost:8001/health" \
    "" \
    "ai-agents" \
    "8001" \
    "postgres redis messaging" \
    "DATABASE_URL ANTHROPIC_API_KEY OPENAI_API_KEY" \
    "hetzner"

define_app "analytics" \
    "git@github.com:wheeler-io/analytics-stack.git" \
    "docker-compose.yml" \
    "http://localhost:8088/health" \
    "" \
    "analytics" \
    "8088" \
    "postgres redis" \
    "SUPERSET_SECRET_KEY CLICKHOUSE_PASSWORD" \
    "hetzner"

define_app "monitoring" \
    "git@github.com:wheeler-io/monitoring-stack.git" \
    "docker-compose.yml" \
    "http://localhost:3002/api/health" \
    "" \
    "monitoring" \
    "3002" \
    "" \
    "GRAFANA_ADMIN_PASSWORD" \
    "hetzner"

define_app "postgres" \
    "git@github.com:wheeler-io/infrastructure.git" \
    "docker-compose/databases/postgres.yml" \
    "" \
    "pg_isready -h localhost -p 5432" \
    "data" \
    "5432" \
    "" \
    "POSTGRES_PASSWORD" \
    "hetzner"

define_app "redis" \
    "git@github.com:wheeler-io/infrastructure.git" \
    "docker-compose/databases/redis.yml" \
    "" \
    "redis-cli -h localhost ping" \
    "data" \
    "6379" \
    "" \
    "REDIS_PASSWORD" \
    "hetzner"

define_app "messaging" \
    "git@github.com:wheeler-io/infrastructure.git" \
    "docker-compose/databases/messaging.yml" \
    "" \
    "curl -s http://localhost:8222/ | grep -q 'NATS'" \
    "messaging" \
    "4222" \
    "" \
    "NATS_TOKEN" \
    "hetzner"

define_app "management" \
    "git@github.com:wheeler-io/infrastructure.git" \
    "docker-compose/management/portainer.yml" \
    "http://localhost:9443" \
    "" \
    "management" \
    "9443" \
    "" \
    "" \
    "hetzner"

# HOSTINGER VPS APPS
define_app "frgops" \
    "git@github.com:wheeler-io/frgops.git" \
    "docker-compose.yml" \
    "http://localhost:3000/health" \
    "" \
    "frgops" \
    "3000" \
    "postgres-hostinger redis-hostinger" \
    "DATABASE_URL SESSION_SECRET" \
    "hostinger"

define_app "n8n" \
    "git@github.com:wheeler-io/n8n-deploy.git" \
    "docker-compose.yml" \
    "http://localhost:5678/healthz" \
    "" \
    "automation" \
    "5678" \
    "postgres-hostinger" \
    "N8N_ENCRYPTION_KEY" \
    "hostinger"

define_app "traefik" \
    "git@github.com:wheeler-io/infrastructure.git" \
    "docker-compose/traefik/traefik.yml" \
    "http://localhost:8080/ping" \
    "" \
    "traefik" \
    "8080" \
    "" \
    "CLOUDFLARE_EMAIL CLOUDFLARE_API_KEY" \
    "both"

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

# --- Logging -----------------------------------------------------------------
log_history() {
    local app="$1"
    local ref="$2"
    local status="$3"  # SUCCESS, FAILED, ROLLED_BACK
    local release_dir="$4"
    local message="${5:-}"

    local entry="$(date -u '+%Y-%m-%d %H:%M:%S') | ${app} | ${ref} | ${status} | ${release_dir} | ${message}"

    mkdir -p "$(dirname "$HISTORY_LOG")"
    echo "$entry" >> "$HISTORY_LOG"

    # Keep only last 500 entries
    tail -n 500 "$HISTORY_LOG" > "${HISTORY_LOG}.tmp" && mv "${HISTORY_LOG}.tmp" "$HISTORY_LOG"

    info "[HISTORY] ${entry}"
}

show_history() {
    local app="${1:-}"

    if [[ ! -f "$HISTORY_LOG" ]]; then
        warn "No deployment history found at ${HISTORY_LOG}"
        return 0
    fi

    echo ""
    echo "=============================================="
    echo "  DEPLOYMENT HISTORY ${app:+for ${app}}"
    echo "=============================================="
    echo ""

    if [[ -n "$app" ]]; then
        grep " | ${app} | " "$HISTORY_LOG" | tail -20
    else
        tail -30 "$HISTORY_LOG"
    fi

    echo ""
}

# --- Pre-deployment checks ----------------------------------------------------
pre_deploy_checks() {
    local app="$1"
    local ref="$2"

    step "Running pre-deployment checks for ${app}@${ref}..."

    # 1. Check required config exists
    local compose_rel="${APP_CONFIG["${app}_compose_file"]}"
    local project="${APP_CONFIG["${app}_project_name"]}"
    local env_vars="${APP_CONFIG["${app}_env_required"]}"
    local server="${APP_CONFIG["${app}_server"]}"

    if [[ -z "$project" ]]; then
        error "Unknown application: ${app}"
        echo "Available apps: prediction-radar, ravynai, frgops, trading, ai-agents, analytics, monitoring, postgres, redis, messaging, traefik, n8n, management"
        exit 1
    fi

    # 2. Check we are on the correct server
    local current_server
    current_server=$(detect_server)
    if [[ "$server" != "both" ]] && [[ "$server" != "$current_server" ]]; then
        error "Application ${app} should be deployed on ${server}, but this is ${current_server}"
        exit 1
    fi

    # 3. Check required environment variables
    if [[ -n "$env_vars" ]]; then
        local env_file="${BASE_DIR}/config/envs/${app}.env"
        if [[ ! -f "$env_file" ]]; then
            error "Environment file not found: ${env_file}"
            error "Create it from template or use env-template.sh"
            exit 1
        fi

        for var in $env_vars; do
            # Source the env file and check
            if ! grep -q "^${var}=" "$env_file" 2>/dev/null; then
                error "Required env variable ${var} not found in ${env_file}"
                exit 1
            fi
        done
        success "All required environment variables present for ${app}"
    fi

    # 4. Check Docker is running
    if ! docker info &>/dev/null; then
        error "Docker is not running or not accessible"
        exit 1
    fi

    # 5. Check port availability
    local port="${APP_CONFIG["${app}_port"]}"
    if [[ -n "$port" ]]; then
        if ss -tlnp "sport = :${port}" 2>/dev/null | grep -q ":$port "; then
            # Port is in use — check if it's our own container
            local existing_service
            existing_service=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c "${project}" || true)
            if [[ "$existing_service" -eq 0 ]]; then
                warn "Port ${port} is in use by another service. Proceeding anyway."
            fi
        fi
    fi

    success "Pre-deployment checks passed"
}

# --- Clone/update repository -------------------------------------------------
fetch_repo() {
    local app="$1"
    local ref="$2"
    local repo_url="${APP_CONFIG["${app}_repo_url"]}"

    local repo_dir="${REPO_BASE}/${app}"

    step "Fetching repository ${app} (${ref})..."

    mkdir -p "$REPO_BASE"

    if [[ -d "$repo_dir/.git" ]]; then
        info "Updating existing repository..."
        cd "$repo_dir"
        git fetch origin 2>&1 || {
            error "Failed to fetch from origin"
            exit 1
        }
    else
        info "Cloning repository..."
        git clone --depth 1 "$repo_url" "$repo_dir" 2>&1 || {
            error "Failed to clone repository ${repo_url}"
            exit 1
        }
        cd "$repo_dir"
    fi

    # Checkout the desired ref
    git checkout "$ref" 2>&1 || {
        error "Failed to checkout ref: ${ref}"
        exit 1
    }

    # Pull latest if it's a branch
    if [[ "$ref" != "HEAD" ]] && git show-ref --verify --quiet "refs/remotes/origin/${ref}" 2>/dev/null; then
        git merge "origin/${ref}" --ff-only 2>&1 || {
            warn "Could not fast-forward ${ref}. Using local state."
        }
    fi

    local commit_hash
    commit_hash=$(git rev-parse --short HEAD)
    success "Repository at commit ${commit_hash}"

    echo "$commit_hash"
}

# --- Build release directory -------------------------------------------------
build_release() {
    local app="$1"
    local commit_hash="$2"

    local release_dir="${RELEASE_ROOT}/${TIMESTAMP}-${app}"
    local repo_dir="${REPO_BASE}/${app}"
    local compose_rel="${APP_CONFIG["${app}_compose_file"]}"

    step "Building release directory: ${release_dir}..."

    mkdir -p "$release_dir"

    # Copy application source (excluding .git and node_modules)
    rsync -a \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='vendor' \
        --exclude='.venv' \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        --exclude='.env' \
        "${repo_dir}/" "${release_dir}/"

    # Copy compose file(s) to root of release for consistency
    if [[ -f "${repo_dir}/${compose_rel}" ]]; then
        cp "${repo_dir}/${compose_rel}" "${release_dir}/docker-compose.yml"
    fi

    # Also copy any override files
    local compose_dir
    compose_dir=$(dirname "${repo_dir}/${compose_rel}")
    if ls "${compose_dir}/docker-compose.override."* 2>/dev/null; then
        cp "${compose_dir}/docker-compose.override."* "${release_dir}/" 2>/dev/null || true
    fi

    # Link shared data directories
    _link_shared_data "$app" "$release_dir"

    # Link the environment file
    local env_file="${BASE_DIR}/config/envs/${app}.env"
    if [[ -f "$env_file" ]]; then
        ln -sf "$env_file" "${release_dir}/.env"
        success "Linked env file for ${app}"
    else
        warn "No env file found at ${env_file}. Create one before starting the service."
    fi

    success "Release directory ready: ${release_dir}"
    echo "$release_dir"
}

# --- Link shared data directories into release --------------------------------
_link_shared_data() {
    local app="$1"
    local release_dir="$2"

    # Determine which shared data directories this app needs
    # Convention: /opt/wheeler/data/<app>/  gets linked into release
    local app_shared_data="${BASE_DIR}/data/${app}"

    if [[ -d "$app_shared_data" ]]; then
        mkdir -p "${release_dir}/data"
        ln -sfn "$app_shared_data" "${release_dir}/data/shared"
        success "Linked shared data: ${app_shared_data}"
    fi
}

# --- Pre-deploy hooks --------------------------------------------------------
run_pre_deploy_hooks() {
    local app="$1"
    local release_dir="$2"

    local hooks_dir="${BASE_DIR}/scripts/pre-deploy.d"
    if [[ ! -d "$hooks_dir" ]]; then
        return 0
    fi

    step "Running pre-deploy hooks..."

    for hook in "${hooks_dir}"/*.sh; do
        if [[ -x "$hook" ]]; then
            info "Running hook: $(basename "$hook")..."
            if ! bash "$hook" "$app" "$release_dir" 2>&1; then
                error "Pre-deploy hook failed: ${hook}"
                return 1
            fi
        fi
    done
}

# --- Stop old version --------------------------------------------------------
stop_old_version() {
    local app="$1"
    local project="${APP_CONFIG["${app}_project_name"]}"

    step "Stopping old version of ${app} (project: ${project})..."

    # Check if anything is running for this project
    if docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up\|running"; then
        info "Running containers found, stopping..."
        docker compose --project-name "$project" down --remove-orphans 2>&1 || {
            warn "Failed to gracefully stop containers. Attempting force stop..."
            docker compose --project-name "$project" down --timeout 0 2>&1
        }
        success "Old version stopped"
    else
        info "No running containers for ${project}"
    fi
}

# --- Start new version -------------------------------------------------------
start_new_version() {
    local app="$1"
    local release_dir="$2"
    local compose_file="${release_dir}/docker-compose.yml"

    step "Starting new version of ${app}..."

    if [[ ! -f "$compose_file" ]]; then
        error "docker-compose.yml not found in release: ${compose_file}"
        exit 1
    fi

    cd "$release_dir"
    docker compose --project-name "${APP_CONFIG["${app}_project_name"]}" \
        -f "$compose_file" \
        up -d --build 2>&1

    success "New version started"
}

# --- Health check loop -------------------------------------------------------
health_check() {
    local app="$1"
    local max_retries="${HEALTH_CHECK_RETRIES:-30}"
    local sleep_seconds="${HEALTH_CHECK_INTERVAL:-2}"
    local health_url="${APP_CONFIG["${app}_health_url"]}"
    local health_cmd="${APP_CONFIG["${app}_health_cmd"]}"
    local port="${APP_CONFIG["${app}_port"]}"

    step "Running health check (up to $((max_retries * sleep_seconds))s)..."

    # Wait for container to be running first
    local project="${APP_CONFIG["${app}_project_name"]}"
    local attempt=0
    while [[ $attempt -lt 10 ]]; do
        if docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up"; then
            break
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    if [[ $attempt -ge 10 ]]; then
        error "Containers did not start within 10 seconds"
        return 1
    fi

    # Run health check command if defined
    if [[ -n "$health_cmd" ]]; then
        info "Running health check command: ${health_cmd}"
        local cmd_success=false
        for ((i=1; i<=max_retries; i++)); do
            if eval "$health_cmd" 2>/dev/null; then
                cmd_success=true
                break
            fi
            sleep "$sleep_seconds"
        done

        if [[ "$cmd_success" != "true" ]]; then
            error "Health check command failed after ${max_retries} attempts"
            return 1
        fi
        success "Health check command passed"
        return 0
    fi

    # HTTP health check
    if [[ -n "$health_url" ]]; then
        info "Checking HTTP health endpoint: ${health_url}"
        local http_success=false
        for ((i=1; i<=max_retries; i++)); do
            local http_code
            http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$health_url" 2>/dev/null || echo "000")

            if [[ "$http_code" = "200" ]]; then
                http_success=true
                break
            fi

            if [[ $((i % 5)) -eq 0 ]]; then
                info "  Health check attempt ${i}/${max_retries} (HTTP ${http_code})..."
            fi

            sleep "$sleep_seconds"
        done

        if [[ "$http_success" != "true" ]]; then
            error "HTTP health check failed. Last response code: ${http_code}"
            return 1
        fi
        success "HTTP health check passed (HTTP 200)"
        return 0
    fi

    # No health check defined — check that containers are up and stable
    info "No health check defined. Checking container uptime..."
    sleep 5
    if docker compose --project-name "$project" ps 2>/dev/null | grep -q "Up"; then
        # Check that no container has restarted in the last 10 seconds
        local recent_restarts
        recent_restarts=$(docker compose --project-name "$project" ps 2>/dev/null | grep -c "Restarting" || true)
        if [[ "$recent_restarts" -gt 0 ]]; then
            warn "Some containers are restarting. This may indicate a problem."
            return 1
        fi
        success "All containers running and stable"
        return 0
    fi

    error "No containers are running after deployment"
    return 1
}

# --- Update symlinks ---------------------------------------------------------
update_symlinks() {
    local app="$1"
    local release_dir="$2"

    step "Updating deployment symlinks..."

    local app_deploy_dir="${DEPLOY_DIR}/${app}"
    mkdir -p "$app_deploy_dir"

    # Move the current "current" to "previous"
    if [[ -L "${app_deploy_dir}/current" ]]; then
        local current_target
        current_target=$(readlink "${app_deploy_dir}/current")
        if [[ -d "$current_target" ]]; then
            ln -sfn "$current_target" "${app_deploy_dir}/previous" 2>/dev/null || true
            success "Previous -> ${current_target}"
        fi
    fi

    # Update current symlink
    ln -sfn "$release_dir" "${app_deploy_dir}/current"
    success "Current -> ${release_dir}"
}

# --- Rollback ----------------------------------------------------------------
rollback() {
    local app="$1"
    local release_dir="$2"

    warn "=============================================="
    warn "  AUTOMATIC ROLLBACK INITIATED for ${app}"
    warn "=============================================="

    local app_deploy_dir="${DEPLOY_DIR}/${app}"

    # Stop the failed release
    step "Stopping failed release..."
    cd "$release_dir" 2>/dev/null || true
    docker compose --project-name "${APP_CONFIG["${app}_project_name"]}" down --timeout 30 2>&1 || true

    # Restore previous symlink
    if [[ -L "${app_deploy_dir}/previous" ]]; then
        local previous_target
        previous_target=$(readlink "${app_deploy_dir}/previous")

        if [[ -d "$previous_target" ]]; then
            step "Restoring previous release: ${previous_target}"

            ln -sfn "$previous_target" "${app_deploy_dir}/current"

            # Start previous version
            cd "$previous_target"
            if [[ -f "docker-compose.yml" ]]; then
                docker compose --project-name "${APP_CONFIG["${app}_project_name"]}" \
                    up -d 2>&1 || {
                    error "Rollback start failed! Manual intervention required."
                    return 2
                }

                # Health check the rolled-back version
                if health_check "$app"; then
                    success "Rollback successful — running previous version"
                    log_history "$app" "ROLLBACK" "SUCCESS" "$previous_target" "Rolled back from failed release ${release_dir}"
                    return 0
                else
                    error "CRITICAL: Rollback also failed! Previous release is broken."
                    error "Manual intervention required immediately."
                    log_history "$app" "ROLLBACK" "CRITICAL_FAILURE" "$previous_target" "Previous release also unhealthy"
                    return 3
                fi
            fi
        fi
    fi

    error "No previous release found to roll back to!"
    log_history "$app" "ROLLBACK" "FAILED" "" "No previous release"
    return 1
}

# --- Post-deploy cleanup ----------------------------------------------------
cleanup_old_releases() {
    local app="$1"
    local keep="${KEEP_RELEASES:-3}"

    step "Cleaning up old releases (keeping ${keep})..."

    # Find release directories for this app
    local releases
    releases=$(ls -d "${RELEASE_ROOT}/"*-"${app}" 2>/dev/null | sort -r || true)

    local count=0
    for release in $releases; do
        count=$((count + 1))
        if [[ $count -gt $keep ]]; then
            # Skip if it's the current or previous symlink target
            local current_target=""
            local previous_target=""
            [[ -L "${DEPLOY_DIR}/${app}/current" ]] && current_target=$(readlink "${DEPLOY_DIR}/${app}/current")
            [[ -L "${DEPLOY_DIR}/${app}/previous" ]] && previous_target=$(readlink "${DEPLOY_DIR}/${app}/previous")

            if [[ "$release" == "$current_target" ]] || [[ "$release" == "$previous_target" ]]; then
                info "Skipping active release: ${release}"
                continue
            fi

            info "Removing old release: ${release}"
            rm -rf "$release"
        fi
    done

    success "Cleanup complete"
}

# --- Dry run mode -----------------------------------------------------------
dry_run() {
    local app="$1"
    local ref="$2"

    echo ""
    echo "=============================================="
    echo "  DRY RUN — Deploy ${app}@${ref}"
    echo "=============================================="
    echo ""
    echo "Would execute:"
    echo "  1. Pre-deploy checks (env vars, port availability, Docker status)"
    echo "  2. Fetch repository ${app} at ref ${ref}"
    echo "  3. Build release dir: ${RELEASE_ROOT}/${TIMESTAMP}-${app}/"
    echo "  4. Run pre-deploy hooks"
    echo "  5. Stop old version of ${app}"
    echo "  6. Start new version from release dir"
    echo "  7. Health check loop (up to 60 seconds)"
    echo "  8. On success: update symlinks, log history, clean old releases"
    echo "  9. On failure: automatic rollback to previous version"
    echo ""
    echo "Release pattern: symlink-based"
    echo "  current -> /opt/wheeler/releases/${TIMESTAMP}-${app}/"
    echo "  previous -> /opt/wheeler/releases/<last-release>/"
    echo ""
    echo "Run without --dry-run to execute."

    exit 0
}

# --- Main --------------------------------------------------------------------
main() {
    local APP=""
    local REF=""
    local DO_ROLLBACK=false
    local DRY_RUN_FLAG=false
    local FORCE=false
    local SKIP_BUILD=false
    local ENV_FILE=""

    # Parse positional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rollback)
                DO_ROLLBACK=true
                shift
                ;;
            --dry-run)
                DRY_RUN_FLAG=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 <app-name> <git-ref> [options]"
                echo ""
                echo "Options:"
                echo "  --rollback      Roll back to the previous release"
                echo "  --dry-run       Show what would be done"
                echo "  --force         Skip pre-flight checks"
                echo "  --skip-build    Use existing Docker images"
                echo "  --env-file      Alternative .env file path"
                echo ""
                echo "Apps: prediction-radar, ravynai, frgops, trading, ai-agents,"
                echo "      analytics, monitoring, postgres, redis, messaging,"
                echo "      traefik, n8n, management"
                exit 0
                ;;
            *)
                if [[ -z "$APP" ]]; then
                    APP="$1"
                elif [[ -z "$REF" ]]; then
                    REF="$1"
                else
                    error "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$APP" ]]; then
        error "Usage: $0 <app-name> <git-ref> [options]"
        exit 1
    fi

    if [[ -z "$REF" ]]; then
        REF="main"
    fi

    if [[ "$DRY_RUN_FLAG" == "true" ]]; then
        dry_run "$APP" "$REF"
        return 0
    fi

    local project="${APP_CONFIG["${app}_project_name"]}"
    if [[ -z "$project" ]]; then
        error "Unknown application: ${APP}"
        exit 1
    fi

    echo "=============================================="
    echo "  DEPLOYING: ${APP} @ ${REF}"
    echo "  Timestamp: ${TIMESTAMP}"
    echo "  Server:    $(hostname)"
    echo "=============================================="
    echo ""

    # Handle rollback mode
    if [[ "$DO_ROLLBACK" == "true" ]]; then
        warn "Running in ROLLBACK mode for ${APP}"
        local app_deploy_dir="${DEPLOY_DIR}/${APP}"
        if [[ -L "${app_deploy_dir}/current" ]]; then
            local current_target
            current_target=$(readlink "${app_deploy_dir}/current")
            cd "$current_target" 2>/dev/null || true
            docker compose --project-name "$project" down 2>&1 || true

            if [[ -L "${app_deploy_dir}/previous" ]]; then
                local prev_target
                prev_target=$(readlink "${app_deploy_dir}/previous")
                ln -sfn "$prev_target" "${app_deploy_dir}/current"
                cd "$prev_target"
                docker compose --project-name "$project" up -d 2>&1

                if health_check "$APP"; then
                    success "Rollback to ${prev_target} successful"
                    log_history "$APP" "ROLLBACK" "SUCCESS" "$prev_target"
                else
                    error "Rollback health check failed!"
                fi
            fi
        fi
        exit 0
    fi

    # -- Normal deployment flow --

    [[ "$FORCE" != "true" ]] && pre_deploy_checks "$APP" "$REF"

    local commit_hash
    commit_hash=$(fetch_repo "$APP" "$REF")

    local release_dir
    release_dir=$(build_release "$APP" "$commit_hash")

    run_pre_deploy_hooks "$APP" "$release_dir" || {
        error "Pre-deploy hooks failed. Aborting."
        exit 1
    }

    stop_old_version "$APP"

    if ! start_new_version "$APP" "$release_dir"; then
        error "Failed to start new version."
        rollback "$APP" "$release_dir" || true
        exit 1
    fi

    if health_check "$APP"; then
        update_symlinks "$APP" "$release_dir"
        log_history "$APP" "$REF" "SUCCESS" "$release_dir"
        cleanup_old_releases "$APP"
        success "Deployment of ${APP}@${REF} completed successfully!"
    else
        error "Health check FAILED for ${APP}@${REF}"
        log_history "$APP" "$REF" "FAILED" "$release_dir" "Health check failed"
        rollback "$APP" "$release_dir" || true
        exit 1
    fi

    echo ""
    info "Deployment finished at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
}

main "$@"
