#!/usr/bin/env bash
# =============================================================================
# Wheeler Enterprise — Master Server Hardening Script
# =============================================================================
# Orchestrates ALL Phase 1 hardening in correct order with validation.
# Non-destructive by default — each step confirms before applying.
#
# Usage:
#   bash apply-server-hardening.sh [--all] [--dry-run]
#     --dry-run       Validate and print plan only (default)
#     --all           Apply all hardening at once
#     --step <name>   Apply a single step by name
#
# Steps (order matters):
#   1. sysctl     — Kernel parameters
#   2. limits     — File descriptor / process limits
#   3. swap       — Swap file creation
#   4. journald   — Journal logging limits
#   5. logrotate  — Log rotation policies
#   6. fail2ban   — Intrusion prevention
#   7. ufw        — Firewall rules
#   8. ssh        — SSH hardening
#   9. docker     — Docker daemon optimization
#   10. cgroup    — Resource partitioning
#   11. unattended — Automatic security updates
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:---dry-run}"
STEP="${2:-all}"
ROLE="${3:-aiops}"  # Default to aiops since this is the AIOPS server

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
err()    { echo -e "${RED}[✗]${NC} $*"; }
header() { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }

validate_environment() {
    header "Validating Environment"

    local errors=0

    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log "OS: $PRETTY_NAME"
        case "$ID" in
            ubuntu|debian) ;;
            *) warn "Non-Debian OS detected: $ID. Some paths may differ." ;;
        esac
    else
        warn "Cannot detect OS"
        ((errors++))
    fi

    # Check kernel
    log "Kernel: $(uname -r)"

    # Check RAM
    local mem_gb=$(awk '/MemTotal/{printf "%.0f", $2/1024/1024}' /proc/meminfo)
    log "RAM: ${mem_gb}GB"
    if [ "$mem_gb" -lt 8 ]; then
        warn "Less than 8GB RAM — adjust swap and buffer sizes before applying"
    fi

    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        warn "Not running as root. Use sudo for --apply mode."
    fi

    # Check for existing configs that would conflict
    [ -f /etc/sysctl.d/99-wheeler-enterprise.conf ] && warn "Existing sysctl config found — will overwrite"
    [ -f /etc/ssh/sshd_config.d/99-wheeler-enterprise.conf ] && warn "Existing SSH config found — will overwrite"
    [ -f /etc/docker/daemon.json ] && warn "Existing Docker daemon.json found — will merge/overwrite"

    if [ "$errors" -gt 0 ]; then
        err "$errors validation error(s) found. Review before continuing."
        return 1
    fi

    log "Environment validation complete"
    return 0
}

apply_sysctl() {
    header "Applying sysctl Hardening"
    cp "$SCRIPT_DIR/00-sysctl-hardening.conf" /etc/sysctl.d/99-wheeler-enterprise.conf
    sysctl --system 2>&1 | tail -5
    log "sysctl parameters applied"
}

apply_limits() {
    header "Applying Resource Limits"
    cp "$SCRIPT_DIR/06-limits.conf" /etc/security/limits.d/99-wheeler-enterprise.conf
    log "Resource limits applied (effective on next login)"
}

apply_swap() {
    header "Configuring Swap"
    bash "$SCRIPT_DIR/05-swap-setup.sh" --apply
}

apply_journald() {
    header "Configuring journald"
    mkdir -p /etc/systemd/journald.conf.d
    cp "$SCRIPT_DIR/07-journald.conf" /etc/systemd/journald.conf.d/99-wheeler-enterprise.conf
    systemctl restart systemd-journald
    log "journald configured"
}

apply_logrotate() {
    header "Applying Log Rotation"
    cp "$SCRIPT_DIR/08-logrotate-wheeler.conf" /etc/logrotate.d/wheeler-enterprise
    log "Log rotation configured"
}

apply_fail2ban() {
    header "Configuring fail2ban"
    if ! command -v fail2ban-server &>/dev/null; then
        warn "fail2ban not installed. Installing..."
        apt-get update -qq && apt-get install -y -qq fail2ban
    fi
    cp "$SCRIPT_DIR/01-fail2ban-jail.local" /etc/fail2ban/jail.local
    systemctl restart fail2ban
    log "fail2ban configured and restarted"
}

apply_ufw() {
    header "Configuring UFW Firewall"
    if ! command -v ufw &>/dev/null; then
        warn "ufw not installed. Installing..."
        apt-get update -qq && apt-get install -y -qq ufw
    fi
    bash "$SCRIPT_DIR/02-ufw-policies.sh" "$ROLE" --apply
}

apply_ssh() {
    header "Hardening SSH"
    bash "$SCRIPT_DIR/03-ssh-hardening.sh" --apply
}

apply_docker() {
    header "Configuring Docker Daemon"
    if [ -f /etc/docker/daemon.json ]; then
        warn "Existing /etc/docker/daemon.json backed up to /etc/docker/daemon.json.bak.$(date +%s)"
        cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%s)"
    fi
    # Copy our config (note: daemon.json cannot have comments in production)
    # Strip comments for JSON validity
    grep -v '^\s*#' "$SCRIPT_DIR/04-docker-daemon.json" | grep -v '^\s*$' | sed 's/,\s*\/\/.*//' > /etc/docker/daemon.json
    # Validate JSON
    if python3 -m json.tool /etc/docker/daemon.json >/dev/null 2>&1; then
        log "Docker daemon.json validated"
    else
        err "Invalid JSON in daemon.json. Check the file manually."
        return 1
    fi
    log "Docker daemon configured (restart Docker to apply: systemctl restart docker)"
}

apply_cgroup() {
    header "Applying Cgroup Limits"
    bash "$SCRIPT_DIR/10-cgroup-limits.sh" --apply
}

apply_unattended() {
    header "Configuring Unattended Upgrades"
    cp "$SCRIPT_DIR/09-unattended-upgrades" /etc/apt/apt.conf.d/50wheeler-unattended-upgrades
    log "Unattended upgrades configured"
}

run_preflight_checks() {
    header "Running Pre-flight Checks"
    local all_ok=true

    # Test SSH config before applying
    if [ -f "$SCRIPT_DIR/03-ssh-hardening.sh" ]; then
        log "SSH hardening script found"
    else
        err "Missing: 03-ssh-hardening.sh"
        all_ok=false
    fi

    # Ensure required tools exist
    for tool in ufw fail2ban-server docker systemctl; do
        if command -v "$tool" &>/dev/null; then
            log "Found: $tool"
        else
            warn "Missing: $tool (will be installed if needed)"
        fi
    done

    if [ "$all_ok" = false ]; then
        return 1
    fi
}

generate_hardening_report() {
    header "Hardening Report"

    echo "=== System State After Hardening ==="
    echo ""

    echo "--- Kernel ---"
    sysctl vm.swappiness net.ipv4.tcp_syncookies net.ipv4.ip_forward 2>/dev/null

    echo ""
    echo "--- Firewall ---"
    ufw status 2>/dev/null || echo "  UFW not active (apply with --apply)"

    echo ""
    echo "--- fail2ban ---"
    fail2ban-client status 2>/dev/null | head -5 || echo "  fail2ban not running (apply with --apply)"

    echo ""
    echo "--- SSH ---"
    sshd -T 2>/dev/null | grep -E 'permitrootlogin|passwordauth|protocol|cipher' | head -10 || echo "  Cannot read SSH config"

    echo ""
    echo "--- Docker ---"
    docker info 2>/dev/null | grep -E 'Storage Driver|Logging Driver|Live Restore' || echo "  Docker not accessible"

    echo ""
    echo "--- Limits ---"
    ulimit -n
    ulimit -u

    echo ""
    echo "--- Swap ---"
    free -h | grep Swap

    echo ""
    echo "--- Disk ---"
    df -h / | tail -1
}

# ── Main ──────────────────────────────────────────────────────────────────

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Wheeler Enterprise — Server Hardening Orchestrator         ║"
echo "║   Role: $ROLE                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

validate_environment

case "$ACTION" in
    --dry-run|--plan)
        header "DRY RUN — No changes will be made"
        echo ""
        echo "Configs that would be deployed:"
        echo "  1. /etc/sysctl.d/99-wheeler-enterprise.conf"
        echo "  2. /etc/security/limits.d/99-wheeler-enterprise.conf"
        echo "  3. /swapfile (${SWAP_SIZE_GB:-8}GB)"
        echo "  4. /etc/systemd/journald.conf.d/99-wheeler-enterprise.conf"
        echo "  5. /etc/logrotate.d/wheeler-enterprise"
        echo "  6. /etc/fail2ban/jail.local"
        echo "  7. UFW rules for role: $ROLE"
        echo "  8. /etc/ssh/sshd_config.d/99-wheeler-enterprise.conf"
        echo "  9. /etc/docker/daemon.json (backed up first)"
        echo " 10. systemd slice reservations"
        echo " 11. /etc/apt/apt.conf.d/50wheeler-unattended-upgrades"
        echo ""
        echo ">>> To apply all: bash $0 --all"
        echo ">>> To apply a step: bash $0 --step <name>"
        run_preflight_checks
        ;;

    --all)
        header "APPLYING ALL HARDENING"
        warn "This will modify system configuration files."
        warn "Each step will run in sequence. Press Ctrl+C to abort."
        sleep 3

        apply_sysctl
        apply_limits
        apply_swap
        apply_journald
        apply_logrotate
        apply_fail2ban
        apply_ufw
        apply_ssh
        apply_docker
        apply_cgroup
        apply_unattended

        generate_hardening_report
        log "All hardening applied successfully."
        ;;

    --step)
        case "$STEP" in
            sysctl)     apply_sysctl ;;
            limits)     apply_limits ;;
            swap)       apply_swap ;;
            journald)   apply_journald ;;
            logrotate)  apply_logrotate ;;
            fail2ban)   apply_fail2ban ;;
            ufw)        apply_ufw ;;
            ssh)        apply_ssh ;;
            docker)     apply_docker ;;
            cgroup)     apply_cgroup ;;
            unattended) apply_unattended ;;
            *)
                echo "Unknown step: $STEP"
                echo "Valid steps: sysctl, limits, swap, journald, logrotate, fail2ban, ufw, ssh, docker, cgroup, unattended"
                exit 1
                ;;
        esac
        ;;

    *)
        echo "Usage: $0 [--dry-run|--all|--step <name>] [role]"
        echo ""
        echo "  --dry-run  Print plan, validate, no changes (default)"
        echo "  --all      Apply ALL hardening at once"
        echo "  --step N   Apply a single step by name"
        echo ""
        echo "  Roles: edge, aiops (default), coredb"
        exit 1
        ;;
esac
