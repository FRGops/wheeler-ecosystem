#!/usr/bin/env bash
# ==============================================================================
# onboarding.sh — New Developer Onboarding Script
# ==============================================================================
#
# Automates the process of onboarding a new developer to the Wheeler AIOps
# infrastructure. Run this on the provisioning/management station.
#
# What it does:
#   1. Adds the developer's SSH public key to both servers
#   2. Creates a system user on both servers
#   3. Sets up Tailscale access (sends invite)
#   4. Installs common tooling (docker, tmux, etc. if missing)
#   5. Sets up the tmux development workflow
#   6. Shows the quick-reference card
#
# Usage:
#   ./onboarding.sh <username> --ssh-key <public-key-file>
#
# Options:
#   <username>              Developer's username (system account name)
#   --ssh-key <file>        SSH public key file to authorize
#   --roles <roles>         Comma-separated: dev,ops,admin (default: dev)
#   --tailscale-tag         Tailscale tag for ACL (e.g., tag:developer)
#   --email <email>         Developer email (for Tailscale invite)
#   --hetzner-host <host>   Hetzner SSH host (from ~/.ssh/config)
#   --hostinger-host <host>  Hostinger SSH host (from ~/.ssh/config)
#   --dry-run               Preview changes
#
# Examples:
#   ./onboarding.sh alice --ssh-key ~/keys/alice.pub --email alice@wheeler.io
#   ./onboarding.sh bob --ssh-key bob.pub --roles ops --dry-run
# ==============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
HETZNER_HOST="${HETZNER_HOST:-hetzner}"
HOSTINGER_HOST="${HOSTINGER_HOST:-hostinger}"
TAILSCALE_TAG="${TAILSCALE_TAG:-tag:developer}"
DEFAULT_ROLES="dev"
BASE_DIR="${BASE_DIR:-/opt/wheeler}"

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
header()  { echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}\n${BLUE}  $*${NC}\n${BLUE}═══════════════════════════════════════════════${NC}\n"; }

# --- Pre-flight checks -------------------------------------------------------
pre_flight() {
    step "Running pre-flight checks..."

    # Check required tools
    local required_tools=("ssh" "ssh-keygen")
    local missing=()
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    # Check that we can reach the servers
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$HETZNER_HOST" "echo connected" &>/dev/null; then
        warn "Cannot connect to Hetzner (${HETZNER_HOST}). Is SSH configured?"
        warn "Continuing with Hostinger-only setup..."
        HETZNER_REACHABLE=false
    else
        HETZNER_REACHABLE=true
        success "Hetzner reachable at ${HETZNER_HOST}"
    fi

    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOSTINGER_HOST" "echo connected" &>/dev/null; then
        warn "Cannot connect to Hostinger (${HOSTINGER_HOST}). Is SSH configured?"
        HOSTINGER_REACHABLE=false
    else
        HOSTINGER_REACHABLE=true
        success "Hostinger reachable at ${HOSTINGER_HOST}"
    fi

    if [[ "$HETZNER_REACHABLE" == "false" ]] && [[ "$HOSTINGER_REACHABLE" == "false" ]]; then
        error "Cannot reach any server. Check SSH configuration."
        exit 1
    fi

    success "Pre-flight checks passed"
}

# --- Read SSH key ------------------------------------------------------------
read_ssh_key() {
    local key_file="$1"

    if [[ ! -f "$key_file" ]]; then
        error "SSH public key file not found: ${key_file}"
        exit 1
    fi

    # Validate it's a public key
    if ! ssh-keygen -l -f "$key_file" &>/dev/null; then
        error "File does not appear to be a valid SSH public key: ${key_file}"
        error "Expected format: ssh-ed25519 AAAA... or ssh-rsa AAAA..."
        exit 1
    fi

    cat "$key_file"
}

# --- Create user on server ---------------------------------------------------
create_user_on_server() {
    local server="$1"
    local username="$2"
    local ssh_key="$3"
    local roles="$4"

    step "Setting up user ${username} on ${server}..."

    # The remote script to run
    local remote_setup=$(cat <<REMOTE
set -e

# 1. Create user if not exists
if ! id "${username}" &>/dev/null; then
    useradd --create-home --shell /bin/bash \
        --groups docker,sudo \
        --comment "Wheeler AIOps Developer" \
        "${username}"
    echo "Created user: ${username}"
else
    echo "User ${username} already exists"
    # Ensure docker group membership
    usermod -aG docker "${username}" 2>/dev/null || true
fi

# 2. Set up SSH directory
USER_HOME=\$(eval echo ~${username})
mkdir -p "\${USER_HOME}/.ssh"
chmod 700 "\${USER_HOME}/.ssh"

# 3. Add SSH key
echo "${ssh_key}" >> "\${USER_HOME}/.ssh/authorized_keys"
sort -u "\${USER_HOME}/.ssh/authorized_keys" -o "\${USER_HOME}/.ssh/authorized_keys"
chmod 600 "\${USER_HOME}/.ssh/authorized_keys"
chown -R "${username}:${username}" "\${USER_HOME}/.ssh"
echo "SSH key installed"

# 4. Create user-specific directories
mkdir -p "${BASE_DIR}/logs"
chmod 755 "${BASE_DIR}/logs" 2>/dev/null || true

# 5. Copy quick reference to home directory
echo "Installation complete for ${username}"
echo "Roles: ${roles}"
REMOTE
)

    ssh "$server" "bash -s" <<< "$remote_setup"

    success "User ${username} configured on ${server}"
}

# --- Install developer tooling on server ------------------------------------
install_tooling() {
    local server="$1"
    local username="$2"

    step "Installing developer tooling on ${server}..."

    local tooling_script=$(cat <<'REMOTE'
set -e

TOOLS=""
command -v tmux &>/dev/null || TOOLS="$TOOLS tmux"
command -v htop &>/dev/null || TOOLS="$TOOLS htop"
command -v curl &>/dev/null || TOOLS="$TOOLS curl"
command -v vim &>/dev/null || TOOLS="$TOOLS vim"
command -v git &>/dev/null || TOOLS="$TOOLS git"
command -v jq &>/dev/null || TOOLS="$TOOLS jq"
command -v tree &>/dev/null || TOOLS="$TOOLS tree"
command -v netstat &>/dev/null || TOOLS="$TOOLS net-tools"
command -v dig &>/dev/null || TOOLS="$TOOLS dnsutils"

if [[ -n "$TOOLS" ]]; then
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq $TOOLS
        echo "Installed: $TOOLS"
    elif command -v yum &>/dev/null; then
        yum install -y -q $TOOLS
        echo "Installed: $TOOLS"
    else
        echo "No package manager found. Install manually: $TOOLS"
    fi
else
    echo "All tools already installed"
fi

# Install tmux plugin manager (TPM) for a better tmux experience
if [[ ! -d ~/.tmux/plugins/tpm ]] 2>/dev/null; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm 2>/dev/null || true
fi

# Create a basic .bashrc addition
BASHRC_ADDITIONS='
# Wheeler AIOps Aliases
alias dc="docker compose"
alias dps="docker ps --format \"table {{.Names}}\t{{.Status}}\t{{.Ports}}\""
alias dlogs="docker logs --tail 50 -f"
alias deploy-status="./service-manager.sh status"
alias deploy-logs="./service-manager.sh logs"
alias health-all="./service-manager.sh health"
'

echo "$BASHRC_ADDITIONS" >> ~/.bashrc 2>/dev/null || true
REMOTE

    ssh "$server" "sudo -u ${username} bash -s" <<< "$tooling_script" 2>/dev/null || {
        warn "Some tooling installation may have failed on ${server}"
    }
}

# --- Install tmux dev workflow -----------------------------------------------
install_tmux_workflow() {
    local server="$1"
    local username="$2"

    step "Setting up tmux workflow on ${server}..."

    # Copy the tmux-dev-workflow.sh to the server
    local tmux_script_path
    tmux_script_path=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tmux-dev-workflow.sh

    if [[ -f "$tmux_script_path" ]]; then
        scp "$tmux_script_path" "${server}:/home/${username}/tmux-dev-workflow.sh" 2>/dev/null || {
            warn "Could not copy tmux script to ${server}"
            return
        }
        ssh "$server" "chown ${username}:${username} /home/${username}/tmux-dev-workflow.sh && chmod 755 /home/${username}/tmux-dev-workflow.sh" 2>/dev/null || true

        # Create an alias
        ssh "$server" "echo \"alias wheeler-tmux='~/tmux-dev-workflow.sh --attach'\" >> /home/${username}/.bashrc" 2>/dev/null || true

        success "tmux workflow installed on ${server}"
    else
        warn "tmux-dev-workflow.sh not found at ${tmux_script_path}"
    fi
}

# --- Tailscale invite --------------------------------------------------------
send_tailscale_invite() {
    local email="$1"

    if [[ -z "$email" ]]; then
        warn "No email provided. Skipping Tailscale invite."
        warn "  Send invite manually: tailscale invite <email>"
        return
    fi

    if ! command -v tailscale &>/dev/null; then
        warn "Tailscale CLI not available locally."
        warn "  Send invite from the server: ssh ${HETZNER_HOST} 'tailscale invite ${email}'"
        return
    fi

    step "Sending Tailscale invite to ${email}..."
    if tailscale invite "$email" 2>&1; then
        success "Tailscale invite sent to ${email}"
    else
        warn "Could not send Tailscale invite. Send manually: tailscale invite ${email}"
    fi
}

# --- Run remote docker setup -------------------------------------------------
ensure_docker_access() {
    local server="$1"
    local username="$2"

    step "Ensuring Docker access for ${username} on ${server}..."

    ssh "$server" "usermod -aG docker ${username} && echo 'Docker group membership confirmed'" 2>/dev/null || {
        warn "Could not modify docker group on ${server}"
    }
}

# --- Show onboarding summary -------------------------------------------------
show_summary() {
    local username="$1"
    local roles="$2"
    local email="$3"

    echo ""
    echo "=============================================="
    echo "  ONBOARDING SUMMARY — ${username}"
    echo "=============================================="
    echo ""

    echo "  Username:   ${username}"
    echo "  Roles:      ${roles}"
    echo "  Email:      ${email:-"(not provided)"}"
    echo ""

    if [[ "$HETZNER_REACHABLE" == "true" ]]; then
        echo "  Hetzner:    ✓ Configured at ${HETZNER_HOST}"
        echo "  SSH:        ssh ${username}@${HETZNER_HOST}"
    else
        echo "  Hetzner:    ✗ Not reachable"
    fi

    if [[ "$HOSTINGER_REACHABLE" == "true" ]]; then
        echo "  Hostinger:  ✓ Configured at ${HOSTINGER_HOST}"
        echo "  SSH:        ssh ${username}@${HOSTINGER_HOST}"
    else
        echo "  Hostinger:  ✗ Not reachable"
    fi

    echo ""
    echo "  Next steps for ${username}:"
    echo "    1. Add SSH config to ~/.ssh/config:"
    echo "       Host hetzner"
    echo "           HostName <hetzner-ip>"
    echo "           User ${username}"
    echo "           IdentityFile ~/.ssh/id_ed25519"
    echo ""
    echo "       Host hostinger"
    echo "           HostName <hostinger-ip>"
    echo "           User ${username}"
    echo "           IdentityFile ~/.ssh/id_ed25519"
    echo ""
    echo "    2. Install Tailscale on their machine"
    echo "    3. Accept the Tailscale invite"
    echo "    4. Connect: ssh hetzner"
    echo "    5. Run the tmux workflow: ./tmux-dev-workflow.sh --attach"
    echo ""

    if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../../shared/QUICK-REFERENCE.md" ]]; then
        info "Quick reference card available at: shared/QUICK-REFERENCE.md"
    fi
}

# --- Dry run -----------------------------------------------------------------
dry_run() {
    local username="$1"
    local key_file="$2"
    local roles="$3"
    local email="$4"

    echo ""
    echo "=============================================="
    echo "  DRY RUN — Onboarding ${username}"
    echo "=============================================="
    echo ""
    echo "  Would perform:"
    echo ""
    echo "  1. Read SSH key from: ${key_file}"
    echo "  2. Create user '${username}' on:"
    echo "     - Hetzner CPX51 (${HETZNER_HOST})"
    echo "     - Hostinger VPS (${HOSTINGER_HOST})"
    echo "  3. Install SSH key on both servers"
    echo "  4. Add to docker group on both servers"
    echo "  5. Install tools: tmux, htop, curl, vim, git, jq, tree"
    echo "  6. Install tmux development workflow"
    echo "  7. Send Tailscale invite to: ${email:-"(none)"}"
    echo "  8. Print onboarding summary"
    echo ""
    echo "  Roles: ${roles}"
    echo "  SSH key: $(ssh-keygen -l -f "$key_file" 2>/dev/null || echo "invalid")"
    echo ""
    echo "Run without --dry-run to execute."

    exit 0
}

# --- Main --------------------------------------------------------------------
main() {
    local USERNAME=""
    local SSH_KEY_FILE=""
    local ROLES="$DEFAULT_ROLES"
    local EMAIL=""
    local DRY_RUN_FLAG=false

    HETZNER_REACHABLE=false
    HOSTINGER_REACHABLE=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ssh-key)
                SSH_KEY_FILE="$2"
                shift 2
                ;;
            --roles)
                ROLES="$2"
                shift 2
                ;;
            --email)
                EMAIL="$2"
                shift 2
                ;;
            --tailscale-tag)
                TAILSCALE_TAG="$2"
                shift 2
                ;;
            --hetzner-host)
                HETZNER_HOST="$2"
                shift 2
                ;;
            --hostinger-host)
                HOSTINGER_HOST="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN_FLAG=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 <username> --ssh-key <key-file> [options]"
                echo ""
                echo "Options:"
                echo "  --ssh-key <file>     SSH public key file (required)"
                echo "  --roles <roles>      Comma-separated: dev,ops,admin (default: dev)"
                echo "  --email <email>      Developer email for Tailscale invite"
                echo "  --tailscale-tag <t>  Tailscale tag (default: tag:developer)"
                echo "  --hetzner-host <h>   SSH host for Hetzner (default: hetzner)"
                echo "  --hostinger-host <h> SSH host for Hostinger (default: hostinger)"
                echo "  --dry-run            Preview without making changes"
                echo ""
                echo "Example:"
                echo "  $0 alice --ssh-key ~/keys/alice.pub --email alice@wheeler.io"
                exit 0
                ;;
            *)
                if [[ -z "$USERNAME" ]]; then
                    USERNAME="$1"
                else
                    error "Unknown argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$USERNAME" ]]; then
        error "Username is required."
        echo "Usage: $0 <username> --ssh-key <key-file>"
        exit 1
    fi

    if [[ -z "$SSH_KEY_FILE" ]]; then
        error "SSH key file is required (--ssh-key)."
        echo "Usage: $0 <username> --ssh-key <key-file>"
        exit 1
    fi

    # Read and validate SSH key
    local SSH_KEY
    SSH_KEY=$(read_ssh_key "$SSH_KEY_FILE")

    if [[ "$DRY_RUN_FLAG" == "true" ]]; then
        dry_run "$USERNAME" "$SSH_KEY_FILE" "$ROLES" "$EMAIL"
        return 0
    fi

    header "Onboarding ${USERNAME} to Wheeler AIOps"

    pre_flight

    # Create user on both servers
    if [[ "$HETZNER_REACHABLE" == "true" ]]; then
        create_user_on_server "$HETZNER_HOST" "$USERNAME" "$SSH_KEY" "$ROLES"
        install_tooling "$HETZNER_HOST" "$USERNAME"
        install_tmux_workflow "$HETZNER_HOST" "$USERNAME"
        ensure_docker_access "$HETZNER_HOST" "$USERNAME"
    fi

    if [[ "$HOSTINGER_REACHABLE" == "true" ]]; then
        create_user_on_server "$HOSTINGER_HOST" "$USERNAME" "$SSH_KEY" "$ROLES"
        install_tooling "$HOSTINGER_HOST" "$USERNAME"
        install_tmux_workflow "$HOSTINGER_HOST" "$USERNAME"
        ensure_docker_access "$HOSTINGER_HOST" "$USERNAME"
    fi

    # Send Tailscale invite
    send_tailscale_invite "$EMAIL"

    # Summary
    show_summary "$USERNAME" "$ROLES" "$EMAIL"

    success "Onboarding of ${USERNAME} complete!"
}

main "$@"
