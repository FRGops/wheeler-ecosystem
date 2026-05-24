#!/usr/bin/env bash
# ==============================================================================
# deploy-system.sh — System-level deployment: folder structure + prerequisites
# ==============================================================================
#
# This script sets up the foundational directory structure that all applications
# and deployments depend on. It is the FIRST thing run on a new server.
#
# Usage:
#   ./deploy-system.sh [--owner <user>] [--group <group>] [--base-dir <path>] [--dry-run]
#
# Philosophy:
#   We treat infrastructure as code. This script should be run on both servers
#   (Hetzner CPX51 and Hostinger VPS) during initial provisioning. It is
#   idempotent — safe to run repeatedly.
#
# ==============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
BASE_DIR="${BASE_DIR:-/opt/wheeler}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Source helpers ----------------------------------------------------------
# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Pre-flight checks -------------------------------------------------------
pre_flight() {
    info "Running pre-flight checks..."

    # Must be root for system-level operations
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo."
        error "System-level setup requires permissions to create users, install packages, and set file ownership."
        exit 1
    fi

    # Check for required tools
    local required_tools=(
        "mkdir:coreutils"
        "chmod:coreutils"
        "chown:coreutils"
        "ln:coreutils"
        "docker:docker"
        "groupadd:shadow-utils"
        "useradd:shadow-utils"
    )

    local missing=()
    for entry in "${required_tools[@]}"; do
        local cmd="${entry%%:*}"
        local pkg="${entry##*:}"
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd (from $pkg)")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required commands:"
        for m in "${missing[@]}"; do
            echo "  - $m"
        done
        exit 1
    fi

    # Verify Docker is running
    if ! docker info &>/dev/null; then
        error "Docker is not running or not accessible. Start Docker first."
        exit 1
    fi

    success "Pre-flight checks passed"
}

# --- Create docker group and user if needed ----------------------------------
setup_user() {
    info "Setting up docker group and application user..."

    # Create docker group if it doesn't exist
    if ! getent group docker &>/dev/null; then
        groupadd --system docker
        success "Created docker group"
    else
        info "Docker group already exists"
    fi

    # Create the application user (wheeler) if it doesn't exist
    if ! id "wheeler" &>/dev/null; then
        useradd --system --create-home --shell /bin/bash \
            --groups docker \
            --comment "Wheeler AIOps Application User" \
            wheeler
        success "Created wheeler user and added to docker group"
    else
        info "wheeler user already exists, ensuring docker group membership"
        usermod -aG docker wheeler
    fi

    # Also ensure current SSH user is in docker group (if different from wheeler)
    local ssh_user
    ssh_user=$(who am i | awk '{print $1}' || echo "")
    if [[ -n "$ssh_user" ]] && [[ "$ssh_user" != "root" ]] && [[ "$ssh_user" != "wheeler" ]]; then
        usermod -aG docker "$ssh_user" 2>/dev/null || true
        info "Added ${ssh_user} to docker group"
    fi

    success "User and group setup complete"
}

# --- Check and fix Docker configuration --------------------------------------
check_docker_config() {
    info "Checking Docker configuration..."

    # Ensure Docker uses json-file logging with rotation (not ELK/Loki)
    local docker_daemon="/etc/docker/daemon.json"
    if [[ ! -f "$docker_daemon" ]]; then
        info "Creating Docker daemon configuration with log rotation..."
        cat > "$docker_daemon" <<'DOCKER_EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false,
  "ip-forward": true,
  "iptables": true,
  "default-address-pools": [
    {"base": "172.30.0.0/16", "size": 24}
  ]
}
DOCKER_EOF
        success "Created Docker daemon config"
        info "NOTE: You must restart Docker for changes to take effect: systemctl restart docker"
    else
        info "Docker daemon config exists at ${docker_daemon}"
        # Check if log rotation is configured
        if grep -q '"max-file"' "$docker_daemon" 2>/dev/null; then
            success "Docker log rotation is configured"
        else
            warn "Docker log rotation may not be configured. Check ${docker_daemon}"
        fi
    fi
}

# --- Create docker networks --------------------------------------------------
create_docker_networks() {
    info "Creating Docker networks..."

    # Networks for Hetzner (primary server)
    declare -A hetzner_networks=(
        ["traefik-public"]="172.20.0.0/24"
        ["prediction-radar"]="172.21.0.0/24"
        ["analytics"]="172.22.0.0/24"
        ["ai-agents"]="172.24.0.0/24"
        ["ravynai"]="172.25.0.0/24"
        ["trading"]="172.26.0.0/24"
        ["messaging"]="172.27.0.0/24"
        ["automation"]="172.28.0.0/24"
        ["data"]="172.29.0.0/24"
        ["monitoring"]="172.30.0.0/24"
        ["management"]="172.31.0.0/24"
        ["osint"]="172.32.0.0/24"
    )

    # Detect which server we're on
    local hostname
    hostname=$(hostname)

    if echo "$hostname" | grep -qi "hetzner\|cpx51\|primary" 2>/dev/null; then
        # We're on Hetzner — create all internal networks
        info "Detected Hetzner CPX51 — creating full network topology"
        for network in "${!hetzner_networks[@]}"; do
            local subnet="${hetzner_networks[$network]}"
            if ! docker network inspect "$network" &>/dev/null; then
                docker network create \
                    --driver overlay \
                    --attachable \
                    --opt encrypted="" \
                    --subnet="$subnet" \
                    "$network" 2>/dev/null || {
                    # Fall back to bridge if overlay fails
                    docker network create \
                        --driver bridge \
                        --subnet="$subnet" \
                        --label "wheeler.io/network=true" \
                        "$network"
                }
                success "Created Docker network: ${network} (${subnet})"
            else
                info "Docker network already exists: ${network}"
            fi
        done
    elif echo "$hostname" | grep -qi "hostinger\|vps\|edge" 2>/dev/null; then
        # We're on Hostinger — create only the networks we need
        info "Detected Hostinger VPS — creating edge network topology"
        local hostinger_networks=(
            "traefik-public:172.20.0.0/24"
            "frgops:172.33.0.0/24"
            "automation:172.34.0.0/24"
            "ai-proxy:172.35.0.0/24"
            "storage:172.36.0.0/24"
            "webhooks:172.37.0.0/24"
            "static:172.38.0.0/24"
            "data:172.39.0.0/24"
        )
        for entry in "${hostinger_networks[@]}"; do
            local net_name="${entry%%:*}"
            local net_subnet="${entry##*:}"
            if ! docker network inspect "$net_name" &>/dev/null; then
                docker network create \
                    --driver bridge \
                    --subnet="$net_subnet" \
                    --label "wheeler.io/network=true" \
                    "$net_name"
                success "Created Docker network: ${net_name} (${net_subnet})"
            else
                info "Docker network already exists: ${net_name}"
            fi
        done
    else
        # Unknown server — create shared traefik-public network at minimum
        warn "Unknown server type. Creating minimal networks."
        if ! docker network inspect "traefik-public" &>/dev/null; then
            docker network create \
                --driver bridge \
                --subnet="172.20.0.0/24" \
                --label "wheeler.io/network=true" \
                "traefik-public"
            success "Created Docker network: traefik-public"
        fi
    fi

    success "Docker networks configured"
}

# --- Run folder-structure.sh -------------------------------------------------
run_folder_structure() {
    local owner="$1"
    local group="$2"

    info "Creating production folder structure..."

    local fs_script="${SCRIPT_DIR}/folder-structure.sh"
    if [[ -f "$fs_script" ]]; then
        bash "$fs_script" --owner "$owner" --group "$group" --base-dir "$BASE_DIR"
    else
        # Fallback: use inline logic if the script doesn't exist separately
        warn "folder-structure.sh not found alongside deploy-system.sh"
        warn "Running inline folder creation..."
        _inline_folder_structure "$owner" "$group"
    fi
}

# --- Inline folder structure (fallback if folder-structure.sh not available) --
_inline_folder_structure() {
    local owner="$1"
    local group="$2"

    # Call the folder-structure.sh logic directly
    # This is a minimal fallback; prefer using folder-structure.sh
    local dirs=(
        "${BASE_DIR}/apps/prediction-radar"
        "${BASE_DIR}/apps/ravynai"
        "${BASE_DIR}/apps/frgops"
        "${BASE_DIR}/apps/trading"
        "${BASE_DIR}/apps/ai-agents"
        "${BASE_DIR}/apps/analytics"
        "${BASE_DIR}/apps/monitoring"
        "${BASE_DIR}/config/traefik"
        "${BASE_DIR}/config/envs"
        "${BASE_DIR}/config/scripts"
        "${BASE_DIR}/data/postgres"
        "${BASE_DIR}/data/redis"
        "${BASE_DIR}/data/uploads"
        "${BASE_DIR}/logs"
        "${BASE_DIR}/backups/databases"
        "${BASE_DIR}/backups/volumes"
        "${BASE_DIR}/backups/configs"
        "${BASE_DIR}/deploy"
        "${BASE_DIR}/releases"
        "${BASE_DIR}/scripts/backup"
        "${BASE_DIR}/scripts/monitoring"
        "${BASE_DIR}/scripts/utils"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done

    chmod 700 "${BASE_DIR}/config/envs"
    chmod 700 "${BASE_DIR}/backups"
    chmod 755 "${BASE_DIR}/scripts"
    chmod 755 "${BASE_DIR}/logs"
    chown -R "${owner}:${group}" "${BASE_DIR}"

    if [[ ! -L "${BASE_DIR}/deploy/current" ]]; then
        ln -sf "${BASE_DIR}/releases" "${BASE_DIR}/deploy/current"
    fi

    success "Inline folder structure created"
}

# --- Validate everything -----------------------------------------------------
validate_system() {
    info "Validating system setup..."
    local errors=0

    # Check docker group
    if ! getent group docker &>/dev/null; then
        error "docker group does not exist"
        ((errors++))
    fi

    # Check docker socket permissions
    local sock_perm
    sock_perm=$(stat -c '%a' /var/run/docker.sock 2>/dev/null || echo "unknown")
    if [[ "$sock_perm" != "666" ]]; then
        warn "Docker socket permission is ${sock_perm} (expected 666)"
    fi

    # Check base directory exists
    if [[ ! -d "$BASE_DIR" ]]; then
        error "Base directory ${BASE_DIR} does not exist"
        ((errors++))
    fi

    # Check critical subdirectories
    for sub in "${BASE_DIR}/config/envs" "${BASE_DIR}/deploy" "${BASE_DIR}/releases"; do
        if [[ ! -d "$sub" ]]; then
            error "Required directory missing: ${sub}"
            ((errors++))
        fi
    done

    # Check envs directory permissions
    local envs_perms
    envs_perms=$(stat -c '%a' "${BASE_DIR}/config/envs" 2>/dev/null || echo "unknown")
    if [[ "$envs_perms" != "700" ]]; then
        warn "envs directory permissions are ${envs_perms} (should be 700)"
    fi

    if [[ $errors -eq 0 ]]; then
        success "System validation PASSED"
        return 0
    else
        error "System validation FAILED with ${errors} issues"
        return 1
    fi
}

# --- Print summary -----------------------------------------------------------
print_summary() {
    echo ""
    echo "=============================================="
    echo "  DEPLOY SYSTEM SETUP COMPLETE"
    echo "=============================================="
    echo ""
    echo "  Server:      $(hostname)"
    echo "  Base dir:    ${BASE_DIR}"
    echo "  Date:        $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    echo "  Next steps:"
    echo "    1. Deploy environment variables:"
    echo "       ./env-template.sh --init"
    echo "    2. Deploy shared infrastructure:"
    echo "       ./deploy-release.sh shared-infra main"
    echo "    3. Deploy databases:"
    echo "       ./deploy-release.sh postgres main"
    echo "    4. Copy your .env files to ${BASE_DIR}/config/envs/"
    echo "    5. Deploy applications using deploy-release.sh"
    echo ""
    echo "  Quick references:"
    echo "    View Docker networks: docker network ls --filter label=wheeler.io/network=true"
    echo "    Test deployment:      ./deploy-release.sh --dry-run <app> <ref>"
    echo ""

    if [[ -f /var/run/reboot-required ]]; then
        warn "*** System reboot is required (check /var/run/reboot-required) ***"
    fi
}

# --- Main --------------------------------------------------------------------
main() {
    local OWNER="wheeler"
    local GROUP="docker"
    local DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --owner)
                OWNER="$2"
                shift 2
                ;;
            --group)
                GROUP="$2"
                shift 2
                ;;
            --base-dir)
                BASE_DIR="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--dry-run] [--owner <user>] [--group <group>] [--base-dir <path>]"
                echo ""
                echo "Sets up the foundational production folder structure and Docker infrastructure."
                echo "Run this FIRST on every new server before deploying applications."
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    echo "=============================================="
    echo "  Wheeler AIOps — System Deployment"
    echo "=============================================="
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN — Would perform the following:"
        echo "  1. Run pre-flight checks"
        echo "  2. Setup docker group and wheeler user"
        echo "  3. Check Docker daemon configuration"
        echo "  4. Create Docker networks (server-dependent)"
        echo "  5. Create folder structure under ${BASE_DIR}"
        echo "  6. Set permissions and ownership (${OWNER}:${GROUP})"
        echo "  7. Validate everything"
        echo ""
        info "Run without --dry-run to apply."
        exit 0
    fi

    pre_flight
    setup_user
    check_docker_config
    create_docker_networks
    run_folder_structure "$OWNER" "$GROUP"
    validate_system
    print_summary
}

main "$@"
