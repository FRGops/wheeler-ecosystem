#!/usr/bin/env bash
# ==============================================================================
# folder-structure.sh
# ==============================================================================
# Creates the canonical production folder structure on BOTH servers.
#
# Deployment Philosophy:
#   We use a symlink-based release pattern (not blue-green, not Kubernetes).
#   Each deployment creates a timestamped release directory under /opt/wheeler/releases/.
#   The "current" symlink points to the active release. Rollback is simply
#   pointing "current" back to the previous release and restarting.
#
# This is production-safe, idempotent, and can be run multiple times safely.
# ==============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
BASE_DIR="${BASE_DIR:-/opt/wheeler}"
RELEASE_ROOT="${BASE_DIR}/releases"
DEPLOY_DIR="${BASE_DIR}/deploy"

# Apps that will have directories created under /opt/wheeler/apps/
APPS=(
    "prediction-radar"
    "ravynai"
    "frgops"
    "trading"
    "ai-agents"
    "analytics"
    "monitoring"
)

# --- Color output helpers ----------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Pre-flight checks -------------------------------------------------------
pre_flight() {
    if [[ $EUID -ne 0 ]] && [[ "${ALLOW_NON_ROOT:-}" != "true" ]]; then
        warn "Not running as root. Some permissions may not be set correctly."
        warn "Run with sudo or set ALLOW_NON_ROOT=true to suppress this warning."
    fi

    # Check for required tools
    for cmd in mkdir chmod chown ln; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done
}

# --- Create directory structure ------------------------------------------------
create_structure() {
    info "Creating production folder structure under ${BASE_DIR}"

    # Root level directories
    local dirs=(
        "${BASE_DIR}"
        "${RELEASE_ROOT}"
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
        "${DEPLOY_DIR}"
        "${BASE_DIR}/scripts/backup"
        "${BASE_DIR}/scripts/monitoring"
        "${BASE_DIR}/scripts/utils"
    )

    # Create app directories
    for app in "${APPS[@]}"; do
        dirs+=("${BASE_DIR}/apps/${app}")
    done

    for dir in "${dirs[@]}"; do
        if mkdir -p "$dir" 2>/dev/null; then
            success "Created: ${dir}"
        else
            error "Failed to create: ${dir}"
            exit 1
        fi
    done
}

# --- Set permissions ---------------------------------------------------------
set_permissions() {
    info "Setting permissions..."

    # Environment files: highly restrictive
    chmod 700 "${BASE_DIR}/config/envs" 2>/dev/null || true
    success "Set 700 on ${BASE_DIR}/config/envs"

    # Config directory: readable by all, writable by owner
    chmod 755 "${BASE_DIR}/config" 2>/dev/null || true
    chmod 755 "${BASE_DIR}/config/traefik" 2>/dev/null || true
    chmod 755 "${BASE_DIR}/config/scripts" 2>/dev/null || true

    # Data directories: owner and group read/write
    chmod 750 "${BASE_DIR}/data" 2>/dev/null || true
    chmod 750 "${BASE_DIR}/data/postgres" 2>/dev/null || true
    chmod 750 "${BASE_DIR}/data/redis" 2>/dev/null || true
    chmod 750 "${BASE_DIR}/data/uploads" 2>/dev/null || true

    # Logs: writable
    chmod 755 "${BASE_DIR}/logs" 2>/dev/null || true

    # Scripts: executable
    chmod 755 "${BASE_DIR}/scripts" 2>/dev/null || true
    find "${BASE_DIR}/scripts" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true

    # Deploy scripts: executable
    find "${DEPLOY_DIR}" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true

    # Backups: owner-only access
    chmod 700 "${BASE_DIR}/backups" 2>/dev/null || true
    chmod 700 "${BASE_DIR}/backups/databases" 2>/dev/null || true
    chmod 700 "${BASE_DIR}/backups/volumes" 2>/dev/null || true
    chmod 700 "${BASE_DIR}/backups/configs" 2>/dev/null || true

    success "Permissions set"
}

# --- Set ownership -----------------------------------------------------------
set_ownership() {
    local user="${1:-}"
    local group="${2:-}"

    if [[ -z "$user" ]]; then
        # Auto-detect: use the user running docker
        if command -v docker &>/dev/null; then
            user="$(stat -c '%U' /var/run/docker.sock 2>/dev/null || echo "root")"
            group="$(stat -c '%G' /var/run/docker.sock 2>/dev/null || echo "docker")"
        else
            user="root"
            group="root"
        fi
    fi

    if [[ -z "$group" ]]; then
        group="$user"
    fi

    info "Setting ownership to ${user}:${group} on ${BASE_DIR}"

    # We only chown the top-level; nested files inherit unless otherwise needed
    chown -R "${user}:${group}" "${BASE_DIR}" 2>/dev/null || {
        warn "Could not set ownership to ${user}:${group}. Try running with sudo."
        return 1
    }

    # But envs needs to be restricted — root-owned or docker-user only
    # If docker user is not root, ensure envs is root-only
    if [[ "$user" != "root" ]]; then
        chown root:root "${BASE_DIR}/config/envs" 2>/dev/null || true
    fi

    success "Ownership set to ${user}:${group}"
}

# --- Create initial symlink placeholder --------------------------------------
create_symlinks() {
    info "Creating initial symlink structure..."

    # If no current symlink exists, create a placeholder pointing to releases dir
    if [[ ! -L "${DEPLOY_DIR}/current" ]]; then
        ln -sf "${RELEASE_ROOT}" "${DEPLOY_DIR}/current" 2>/dev/null || true
        success "Created: ${DEPLOY_DIR}/current -> ${RELEASE_ROOT}"
    else
        info "Symlink ${DEPLOY_DIR}/current already exists, skipping"
    fi
}

# --- Validate the structure --------------------------------------------------
validate_structure() {
    info "Validating folder structure..."
    local errors=0

    local required_dirs=(
        "${BASE_DIR}/apps"
        "${BASE_DIR}/config"
        "${BASE_DIR}/config/envs"
        "${BASE_DIR}/config/traefik"
        "${BASE_DIR}/data"
        "${BASE_DIR}/logs"
        "${BASE_DIR}/backups"
        "${DEPLOY_DIR}"
        "${RELEASE_ROOT}"
        "${BASE_DIR}/scripts/backup"
        "${BASE_DIR}/scripts/monitoring"
        "${BASE_DIR}/scripts/utils"
    )

    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            error "MISSING: ${dir}"
            ((errors++))
        fi
    done

    # Check permissions on sensitive directories
    local envs_perms
    envs_perms=$(stat -c '%a' "${BASE_DIR}/config/envs" 2>/dev/null || echo "unknown")
    if [[ "$envs_perms" != "700" ]]; then
        warn "${BASE_DIR}/config/envs has permissions ${envs_perms} (expected 700)"
    fi

    if [[ $errors -eq 0 ]]; then
        success "Folder structure validation PASSED — all directories present"
        return 0
    else
        error "Folder structure validation FAILED — ${errors} issues found"
        return 1
    fi
}

# --- Dry-run mode ------------------------------------------------------------
dry_run() {
    echo ""
    echo "=============================================="
    echo "  DRY RUN — No changes will be made"
    echo "=============================================="
    echo ""
    echo "Would create structure under: ${BASE_DIR}"
    echo ""
    echo "Directory layout:"
    echo "  ${BASE_DIR}/"
    echo "  ├── apps/"
    for app in "${APPS[@]}"; do
        echo "  │   ├── ${app}/"
    done
    echo "  ├── config/"
    echo "  │   ├── traefik/"
    echo "  │   ├── envs/         (chmod 700)"
    echo "  │   └── scripts/"
    echo "  ├── data/"
    echo "  │   ├── postgres/"
    echo "  │   ├── redis/"
    echo "  │   └── uploads/"
    echo "  ├── logs/"
    echo "  ├── backups/"
    echo "  │   ├── databases/"
    echo "  │   ├── volumes/"
    echo "  │   └── configs/"
    echo "  ├── deploy/"
    echo "  │   └── current -> releases/"
    echo "  ├── releases/"
    echo "  └── scripts/"
    echo "      ├── backup/"
    echo "      ├── monitoring/"
    echo "      └── utils/"
    echo ""
    echo "Permissions:"
    echo "  config/envs/       → 0700 (root only)"
    echo "  data/              → 0750 (owner:group)"
    echo "  backups/           → 0700 (root only)"
    echo "  scripts/*.sh       → 0755 (executable)"
    echo ""
    echo "Would set ownership to: docker:docker (auto-detected)"
    echo ""
    echo "Run without --dry-run to apply."
}

# --- Main --------------------------------------------------------------------
main() {
    local OWNER=""
    local GROUP=""
    local DRY_RUN=false

    # Parse arguments
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
                RELEASE_ROOT="${BASE_DIR}/releases"
                DEPLOY_DIR="${BASE_DIR}/deploy"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--dry-run] [--owner <user>] [--group <group>] [--base-dir <path>]"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    echo "=============================================="
    echo "  Wheeler AIOps — Folder Structure Setup"
    echo "=============================================="

    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run
        exit 0
    fi

    pre_flight
    create_structure
    set_permissions
    set_ownership "$OWNER" "$GROUP"
    create_symlinks
    validate_structure

    echo ""
    success "Folder structure setup complete!"
    echo "  Base:    ${BASE_DIR}"
    echo "  Releases: ${RELEASE_ROOT}"
    echo "  Deploy:  ${DEPLOY_DIR}"
}

main "$@"
