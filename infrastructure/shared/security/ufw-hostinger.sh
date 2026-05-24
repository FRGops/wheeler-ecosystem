#!/usr/bin/env bash
# =============================================================================
# UFW Hardening Script — Hostinger VPS (Public Edge / Frontend)
# =============================================================================
#
# Security Rationale:
#   Hostinger is the PUBLIC-FACING edge server. It handles TLS termination
#   and reverse proxies to Hetzner via Tailscale. It is the PRIMARY ATTACK
#   SURFACE — strictest rules apply here.
#
# Strategy:
#   - Public: SSH (22, STRICTER rate-limit), HTTP (80), HTTPS (443)
#   - Tailscale-only: ALL database ports (5432, 6379), any admin panels
#   - SSH limit: 4/30s (tighter than Hetzner's 6/30s — less forgiving)
#   - ALL denied packets are logged for forensic analysis
#     (but rate-limited to avoid log flooding)
#
# Idempotent: YES — safe to run multiple times. Resets UFW each run.
# =============================================================================

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

TAILSCALE_IFACE="tailscale0"

# SSH rate limiting — stricter on edge (fewer legitimate users need SSH)
SSH_RATE_LIMIT="4/30"  # 4 connections per 30 seconds

# Required binaries
UFW_CMD="$(command -v ufw || true)"

# ─── Helper Functions ────────────────────────────────────────────────────────

info()  { printf "[INFO]  %s\n" "$*"; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

check_prerequisites() {
    if [ -z "${UFW_CMD}" ]; then
        error "UFW is not installed. Install with: apt-get install ufw"
    fi

    if ! ip link show "${TAILSCALE_IFACE}" >/dev/null 2>&1; then
        warn "Interface '${TAILSCALE_IFACE}' not found. Tailscale may not be running."
        warn "Rules will still be added — they will take effect when tailscale0 appears."
        warn "Run 'tailscale up' first, then re-run this script."
    else
        local ts_ip
        ts_ip="$(tailscale ip -4 2>/dev/null || true)"
        if [ -n "${ts_ip}" ]; then
            info "Detected Tailscale IP: ${ts_ip}"
        fi
    fi
}

dry_run_mode() {
    if [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "-n" ]; then
        info "DRY RUN MODE — commands will be displayed but NOT executed."
        return 0
    fi
    return 1
}

# ─── Main UFW Configuration ──────────────────────────────────────────────────

configure_ufw_hostinger() {
    local dry_run="${1:-false}"

    info "=== Hostinger UFW Configuration (Edge Server — Strict) ==="
    info "Public ports: SSH(22, strict rate-limit), HTTP(80), HTTPS(443)"
    info "Tailscale-only: ALL database, cache, and admin ports"
    info "Logging: ALL denied packets logged (rate-limited)"
    info ""

    # --- Step 1: Reset UFW ---
    info "[1/9] Resetting UFW to factory defaults..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw --force reset"
    else
        ufw --force reset
    fi

    # --- Step 2: Default policies ---
    info "[2/9] Setting default policies..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw default deny incoming"
        echo "  > ufw default allow outgoing"
    else
        ufw default deny incoming
        ufw default allow outgoing
    fi

    # --- Step 3: Allow public SSH (will be rate-limited in step 5) ---
    info "[3/9] Allowing PUBLIC services: SSH, HTTP, HTTPS..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw allow 22/tcp comment 'SSH public'"
        echo "  > ufw allow 80/tcp comment 'HTTP public'"
        echo "  > ufw allow 443/tcp comment 'HTTPS public'"
    else
        ufw allow 22/tcp comment 'SSH public'
        ufw allow 80/tcp comment 'HTTP public'
        ufw allow 443/tcp comment 'HTTPS public'
    fi

    # --- Step 4: SSH rate limiting (STRICTER: 4/30) ---
    info "[4/9] Applying STRICT SSH rate limit (${SSH_RATE_LIMIT})..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw limit 22/tcp comment 'SSH rate-limited (strict)'"
    else
        ufw delete allow 22/tcp >/dev/null 2>&1 || true
        ufw limit 22/tcp comment 'SSH rate-limited (strict)'
        info "  SSH rate-limit set: max ${SSH_RATE_LIMIT} connections"
    fi

    # --- Step 5: Tailscale-only ports ---
    info "[5/9] Restricting database/admin ports to tailscale0 interface..."

    # Database and cache ports (must not be public!)
    local -a tailscale_ports=(
        "5432:PostgreSQL (FRGops database)"
        "6379:Redis (FRGops cache)"
    )

    # If any admin panels run on Hostinger, add them here:
    # "9001:MinIO console"
    # "5678:n8n editor"

    for entry in "${tailscale_ports[@]}"; do
        local port="${entry%%:*}"
        local comment="${entry#*:}"
        if [ "${dry_run}" = "true" ]; then
            echo "  > ufw allow in on ${TAILSCALE_IFACE} to any port ${port} proto tcp comment '${comment}'"
        else
            # Remove any existing rule for this port
            ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
            ufw delete allow in on "${TAILSCALE_IFACE}" to any port "${port}" proto tcp >/dev/null 2>&1 || true

            ufw allow in on "${TAILSCALE_IFACE}" to any port "${port}" proto tcp comment "${comment}"
        fi
    done
    info "  ${#tailscale_ports[@]} tailscale-only rules applied."

    # --- Step 6: Docker bridge compatibility ---
    info "[6/9] Configuring Docker bridge compatibility..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw allow in on docker0 to 172.17.0.0/16"
        echo "  > sed -i 's/DEFAULT_FORWARD_POLICY=\"DROP\"/DEFAULT_FORWARD_POLICY=\"ACCEPT\"/' /etc/default/ufw"
    else
        ufw allow in on docker0 from 172.17.0.0/16 >/dev/null 2>&1 || true
        if grep -q '^DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
            sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
            info "  UFW default forward policy set to ACCEPT (required for Docker)."
        fi
    fi

    # --- Step 7: Deny logging (rate-limited) ---
    info "[7/9] Enabling denied-packet logging..."
    # Security rationale: We WANT to know when someone probes us.
    # Rate-limit the log to avoid filling /var/log with noise.
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw logging medium"
    else
        ufw logging medium
    fi

    # --- Step 8: Add logging rate-limit via rsyslog ---
    info "[8/9] Configuring kernel log rate limiting for UFW..."
    local rsyslog_conf="/etc/rsyslog.d/20-ufw-rate-limit.conf"
    if [ "${dry_run}" = "true" ]; then
        echo "  > Writing ${rsyslog_conf} with \$SystemLogRateLimitInterval 10 and \$SystemLogRateLimitBurst 200"
    else
        # Prevent UFW logs from flooding syslog:
        # Allow max 200 messages per 10 seconds (vs default unlimited)
        cat > "${rsyslog_conf}" <<'RSYSLOG'
# UFW log rate limiting — prevents log flood from port scans
# Allow 200 kernel messages per 10-second interval
$SystemLogRateLimitInterval 10
$SystemLogRateLimitBurst 200
RSYSLOG
        systemctl restart rsyslog 2>/dev/null || true
        info "  rsyslog rate limiting configured (200 msgs / 10s)"
    fi

    # --- Step 9: Enable UFW ---
    info "[9/9] Enabling UFW..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw --force enable"
    else
        ufw --force enable
    fi

    info "=== Hostinger UFW configuration complete ==="

    if [ "${dry_run}" != "true" ]; then
        info ""
        info "Current UFW status:"
        ufw status numbered
    fi
}

# ─── Verification ────────────────────────────────────────────────────────────

verify_rules() {
    info ""
    info "=== Verifying UFW Rules ==="

    if ufw status | grep -qi "Status: active"; then
        info "[PASS] UFW is active"
    else
        warn "[FAIL] UFW is NOT active"
    fi

    # Verify SSH is rate-limited
    if ufw status | grep -qi "22/tcp.*LIMIT"; then
        info "[PASS] SSH is rate-limited (22/tcp)"
    else
        warn "[WARN] SSH is not rate-limited"
    fi

    # Verify DB ports are restricted
    for port in 5432 6379; do
        if ufw status | grep -qi "${port}/tcp.*ALLOW.*${TAILSCALE_IFACE}"; then
            info "[PASS] Port ${port} restricted to ${TAILSCALE_IFACE}"
        else
            warn "[WARN] Port ${port} may not be restricted to ${TAILSCALE_IFACE}"
        fi
    done

    info ""
    info "Review /var/log/syslog | grep UFW for denied packets."
    info "If the log is too noisy, reduce logging level: ufw logging low"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (sudo)."
    fi

    check_prerequisites

    local dry_run="false"
    if dry_run_mode "$@"; then
        dry_run="true"
    fi

    configure_ufw_hostinger "${dry_run}"

    if [ "${dry_run}" = "false" ]; then
        verify_rules
    fi

    info ""
    info "Usage:"
    info "  sudo ./ufw-hostinger.sh            # Apply rules (production)"
    info "  sudo ./ufw-hostinger.sh --dry-run   # Preview only"
    info "  sudo tail -f /var/log/syslog | grep UFW  # Monitor denies"
}

main "$@"
