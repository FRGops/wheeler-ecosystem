#!/usr/bin/env bash
# =============================================================================
# deploy-ssh-keys.sh — Cross-Server SSH Key Deployment
# =============================================================================
# Usage: ./deploy-ssh-keys.sh [--dry-run] [--target <coredb|edge|all>]
#
# Deploys the Wheeler cross-server SSH key to COREDB and EDGE servers.
# Uses Tailscale IPs as primary path, public IPs as fallback.
# If unreachable, prints manual deployment instructions.
#
# Exit Codes:
#   0  All targets reached and keys deployed
#   1  Partial failure (some targets deployed, some failed)
#   2  Total failure (no targets reachable)
#   3  Invalid arguments
# =============================================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="/root/deployment-engine/logs"
readonly LOG_FILE="${LOG_DIR}/ssh-deploy.log"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# ─── Server Definitions ─────────────────────────────────────────────────────

# COREDB (Hetzner 5.78.210.123)
readonly COREDB_TAILSCALE_IP="100.118.166.117"
readonly COREDB_PUBLIC_IP="5.78.210.123"
readonly COREDB_SSH_USER="ron"

# EDGE (Hostinger 187.77.148.88)
readonly EDGE_PUBLIC_IP="187.77.148.88"
readonly EDGE_SSH_USER="ron"

# Local key to deploy
readonly CROSS_KEY_PRIV="/root/.ssh/wheeler-cross-server"
readonly CROSS_KEY_PUB="/root/.ssh/wheeler-cross-server.pub"

readonly SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=no"
readonly SSH_OPTS_BATCH="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes"

# ─── Logging ─────────────────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"

log_msg() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date +%Y-%m-%dT%H:%M:%S)"
    echo "[${ts}] [${level}] deploy-ssh-keys: ${msg}" | tee -a "$LOG_FILE"
}

log_info()  { log_msg "INFO" "$@"; }
log_warn()  { log_msg "WARN" "$@"; }
log_error() { log_msg "ERROR" "$@"; }
log_ok()    { log_msg "OK" "$@"; }

# ─── Preflight ───────────────────────────────────────────────────────────────

preflight() {
    log_info "Running preflight checks..."

    if [[ ! -f "$CROSS_KEY_PUB" ]]; then
        log_error "Public key not found: ${CROSS_KEY_PUB}"
        return 1
    fi

    if [[ ! -f "$CROSS_KEY_PRIV" ]]; then
        log_error "Private key not found: ${CROSS_KEY_PRIV}"
        return 1
    fi

    local key_type
    key_type=$(ssh-keygen -l -f "$CROSS_KEY_PUB" 2>/dev/null | awk '{print $4}' || true)
    log_info "Key type: ${key_type}"
    log_info "Public key fingerprint: $(ssh-keygen -l -f "$CROSS_KEY_PUB" 2>/dev/null)"
    log_info "Preflight OK"
    return 0
}

# ─── Connectivity Check ──────────────────────────────────────────────────────

check_tailscale() {
    if command -v tailscale &>/dev/null && tailscale status &>/dev/null 2>&1; then
        log_info "Tailscale is running"
        return 0
    else
        log_warn "Tailscale is NOT running or not installed"
        return 1
    fi
}

check_host_reachable() {
    local label="$1"
    local ip="$2"
    local port="${3:-22}"

    log_info "Checking connectivity to ${label} (${ip}:${port})..."

    # Try TCP connect first (faster than SSH for firewall detection)
    if timeout 5 bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null; then
        log_ok "${label} (${ip}:${port}) — TCP reachable"
        return 0
    else
        log_warn "${label} (${ip}:${port}) — TCP NOT reachable (firewall or network)"
        return 1
    fi
}

check_ssh_auth() {
    local label="$1"
    local ip="$2"
    local user="$3"

    log_info "Checking SSH auth to ${label} (${user}@${ip})..."

    if ssh ${SSH_OPTS_BATCH} -i "$CROSS_KEY_PRIV" "${user}@${ip}" "hostname" 2>/dev/null; then
        log_ok "${label} — SSH authenticated with cross-server key"
        return 0
    else
        log_warn "${label} — SSH auth FAILED (key not authorized or password required)"
        return 1
    fi
}

# ─── Key Deployment ──────────────────────────────────────────────────────────

deploy_key_to_host() {
    local label="$1"
    local ip="$2"
    local user="$3"

    log_info "Deploying SSH key to ${label} (${user}@${ip})..."

    local pubkey
    pubkey="$(cat "$CROSS_KEY_PUB")"

    # Method 1: Try ssh-copy-id
    if command -v ssh-copy-id &>/dev/null; then
        log_info "Attempting ssh-copy-id to ${label}..."
        if ssh-copy-id -i "$CROSS_KEY_PUB" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "${user}@${ip}" 2>&1 | tee -a "$LOG_FILE"; then
            log_ok "${label} — ssh-copy-id succeeded"
            return 0
        else
            log_warn "ssh-copy-id to ${label} failed, trying manual method..."
        fi
    fi

    # Method 2: Manual key append via ssh
    log_info "Attempting manual key append to ${label}..."
    if cat "$CROSS_KEY_PUB" | ssh ${SSH_OPTS} -i "$CROSS_KEY_PRIV" "${user}@${ip}" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo 'Key deployed'" 2>&1 | tee -a "$LOG_FILE"; then
        log_ok "${label} — Manual key append succeeded"
        return 0
    else
        log_error "${label} — Manual key append FAILED"
        return 1
    fi
}

verify_key_deployment() {
    local label="$1"
    local ip="$2"
    local user="$3"

    log_info "Verifying key deployment on ${label}..."

    if check_ssh_auth "$label" "$ip" "$user"; then
        log_ok "${label} — Key deployment VERIFIED"
        return 0
    else
        log_error "${label} — Key deployment verification FAILED"
        return 1
    fi
}

# ─── Manual Instructions ─────────────────────────────────────────────────────

print_manual_instructions() {
    local label="$1"
    local ip="$2"
    local user="$3"
    local pubkey
    pubkey="$(cat "$CROSS_KEY_PUB")"

    log_warn "==========================================================="
    log_warn "MANUAL DEPLOYMENT REQUIRED for ${label}"
    log_warn "==========================================================="
    log_warn "The cross-server SSH key could not be automatically deployed."
    log_warn ""
    log_warn "INSTRUCTIONS:"
    log_warn "1. Open a terminal on the ${label} server (${ip})"
    log_warn "2. Or use a separate SSH session if you have an existing key:"
    log_warn "   ssh ${user}@${ip}"
    log_warn ""
    log_warn "3. On the ${label} server, run:"
    log_warn "   mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    log_warn "   cat >> ~/.ssh/authorized_keys"
    log_warn "   chmod 600 ~/.ssh/authorized_keys"
    log_warn ""
    log_warn "4. Verify from this server:"
    log_warn "   ssh -i ${CROSS_KEY_PRIV} ${user}@${ip} hostname"
    log_warn "==========================================================="
}

# ─── Target: COREDB ──────────────────────────────────────────────────────────

deploy_coredb() {
    local result=0
    log_info "========== COREDB Deployment =========="

    # Check connectivity via Tailscale
    if check_host_reachable "COREDB (Tailscale)" "$COREDB_TAILSCALE_IP"; then
        log_info "COREDB reachable via Tailscale (${COREDB_TAILSCALE_IP})"
        if deploy_key_to_host "COREDB" "$COREDB_TAILSCALE_IP" "$COREDB_SSH_USER"; then
            verify_key_deployment "COREDB" "$COREDB_TAILSCALE_IP" "$COREDB_SSH_USER" || result=1
            return $result
        fi
    fi

    # Fallback: public IP
    log_info "Trying COREDB public IP fallback..."
    if check_host_reachable "COREDB (Public)" "$COREDB_PUBLIC_IP"; then
        log_info "COREDB reachable via public IP (${COREDB_PUBLIC_IP})"
        if deploy_key_to_host "COREDB" "$COREDB_PUBLIC_IP" "$COREDB_SSH_USER"; then
            verify_key_deployment "COREDB" "$COREDB_PUBLIC_IP" "$COREDB_SSH_USER" || result=1
            return $result
        fi
    fi

    # Neither path works — print manual instructions
    log_error "COREDB not reachable via Tailscale or public IP"
    print_manual_instructions "COREDB" "$COREDB_TAILSCALE_IP" "$COREDB_SSH_USER"
    return 1
}

# ─── Target: EDGE ────────────────────────────────────────────────────────────

deploy_edge() {
    local result=0
    log_info "========== EDGE Deployment =========="

    if check_host_reachable "EDGE (Public)" "$EDGE_PUBLIC_IP"; then
        log_info "EDGE reachable via public IP (${EDGE_PUBLIC_IP})"
        if deploy_key_to_host "EDGE" "$EDGE_PUBLIC_IP" "$EDGE_SSH_USER"; then
            verify_key_deployment "EDGE" "$EDGE_PUBLIC_IP" "$EDGE_SSH_USER" || result=1
            return $result
        fi
    fi

    # Unreachable — print manual instructions
    log_error "EDGE not reachable"
    print_manual_instructions "EDGE" "$EDGE_PUBLIC_IP" "$EDGE_SSH_USER"
    return 1
}

# ─── Connectivity Report ─────────────────────────────────────────────────────

print_connectivity_report() {
    log_info ""
    log_info "========== CONNECTIVITY REPORT =========="
    log_info "Timestamp: ${TIMESTAMP}"
    log_info ""

    # Local SSH keys
    log_info "Local SSH keys:"
    ls -la /root/.ssh/id_* /root/.ssh/wheeler-* 2>/dev/null | while read -r line; do
        log_info "  ${line}"
    done || true

    # Tailscale status
    log_info ""
    log_info "Tailscale mesh:"
    if command -v tailscale &>/dev/null; then
        tailscale status 2>/dev/null | while read -r line; do
            log_info "  ${line}"
        done || log_info "  (tailscale not running)"
    else
        log_info "  (tailscale not installed)"
    fi

    # Ping tests
    log_info ""
    log_info "Ping tests:"
    for target in "$COREDB_TAILSCALE_IP" "$COREDB_PUBLIC_IP" "$EDGE_PUBLIC_IP"; do
        if ping -c 1 -W 2 "$target" &>/dev/null; then
            log_info "  ${target}: REACHABLE (ICMP)"
        else
            log_info "  ${target}: BLOCKED/UNREACHABLE"
        fi
    done

    # Port tests
    log_info ""
    log_info "Port 22 (SSH) tests:"
    for target in "$COREDB_TAILSCALE_IP" "$COREDB_PUBLIC_IP" "$EDGE_PUBLIC_IP"; do
        if timeout 5 bash -c "echo >/dev/tcp/${target}/22" 2>/dev/null; then
            log_info "  ${target}:22 OPEN"
        else
            log_info "  ${target}:22 CLOSED/FILTERED"
        fi
    done

    log_info ""
    log_info "Public key to deploy:"
    log_info "  $(ssh-keygen -l -f "$CROSS_KEY_PUB" 2>/dev/null)"
    log_info "========== END REPORT =========="
    log_info ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    local target="${1:-all}"
    local dry_run=false
    local exit_code=0
    local deployed=()
    local failed=()

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            --target)
                target="$2"
                shift 2
                ;;
            all|coredb|edge)
                target="$1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    log_info "========================================="
    log_info "SSH Key Deployment — Started at ${TIMESTAMP}"
    log_info "Target: ${target}"
    log_info "Dry run: ${dry_run}"
    log_info "========================================="

    # Preflight
    if ! preflight; then
        log_error "Preflight FAILED. Aborting."
        print_connectivity_report
        exit 3
    fi

    # Check Tailscale
    check_tailscale

    # Print connectivity report
    if [[ "$dry_run" == "true" ]]; then
        print_connectivity_report
        log_info "Dry run complete. No keys deployed."
        exit 0
    fi

    # Deploy to COREDB
    if [[ "$target" == "all" || "$target" == "coredb" ]]; then
        if deploy_coredb; then
            deployed+=("COREDB")
        else
            failed+=("COREDB")
        fi
    fi

    # Deploy to EDGE
    if [[ "$target" == "all" || "$target" == "edge" ]]; then
        if deploy_edge; then
            deployed+=("EDGE")
        else
            failed+=("EDGE")
        fi
    fi

    # Summary
    log_info ""
    log_info "========== DEPLOYMENT SUMMARY =========="
    log_info "Deployed:  ${deployed[*]:-none}"
    log_info "Failed:    ${failed[*]:-none}"
    log_info "========================================="

    # Print full connectivity report at end
    print_connectivity_report

    if [[ ${#deployed[@]} -gt 0 && ${#failed[@]} -eq 0 ]]; then
        log_ok "All targets deployed successfully."
        exit_code=0
    elif [[ ${#deployed[@]} -gt 0 && ${#failed[@]} -gt 0 ]]; then
        log_warn "Partial deployment: some targets failed."
        exit_code=1
    else
        log_error "No targets deployed. Manual intervention required."
        exit_code=2
    fi

    exit $exit_code
}

main "$@"
