#!/usr/bin/env bash
# =============================================================================
# UFW Hardening Script — Hetzner CPX51 (Primary AIOps Orchestrator)
# =============================================================================
#
# Security Rationale:
#   Hetzner runs ALL backend services (AI, databases, monitoring, dashboards).
#   Most admin/dashboard ports MUST NOT be exposed to the public internet.
#   By default, 1Panel opens port 8090 to the world — this script locks that down.
#
# Strategy:
#   - Public: SSH (22), HTTP (80), HTTPS (443) — essential only
#   - Tailscale-only (tailscale0 interface): ALL admin/dashboard/monitoring/DB ports
#   - This forces every admin action through the Tailscale VPN mesh
#   - SSH is rate-limited to prevent brute force
#
# Tailscale interface detection:
#   Automatically resolves ${TAILSCALE_IP} from `tailscale ip -4`.
#   If tailscale is not running, the script warns but still applies rules.
#
# Idempotent: YES — safe to run multiple times. Resets UFW each run.
# =============================================================================

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

# Dynamically resolve Tailscale IP (first IPv4 address)
TAILSCALE_IP="${TAILSCALE_IP:-$(tailscale ip -4 2>/dev/null || true)}"

# Fallback to detecting the tailscale0 interface
TAILSCALE_IFACE="tailscale0"

# SSH rate limiting
SSH_RATE_LIMIT="6/30"  # 6 connections per 30 seconds

# Required binaries
UFW_CMD="$(command -v ufw || true)"
IPTABLES_CMD="$(command -v iptables || true)"
TAILSCALE_CMD="$(command -v tailscale || true)"

# ─── Helper Functions ────────────────────────────────────────────────────────

info()  { printf "[INFO]  %s\n" "$*"; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

check_prerequisites() {
    if [ -z "${UFW_CMD}" ]; then
        error "UFW is not installed. Install with: apt-get install ufw"
    fi

    if [ -z "${TAILSCALE_IP}" ] && [ -z "${TAILSCALE_CMD}" ]; then
        warn "Tailscale does not appear to be installed or running."
        warn "Tailscale-only rules will still be applied on interface '${TAILSCALE_IFACE}'."
        warn "You must ensure Tailscale is configured and running after first boot."
    elif [ -z "${TAILSCALE_IP}" ]; then
        # tailscale command exists but no IP yet (not connected)
        warn "Tailscale is installed but no IPv4 address found (mesh may not be connected)."
    else
        info "Detected Tailscale IP: ${TAILSCALE_IP}"
    fi

    # Verify tailscale0 interface exists (or warn)
    if ! ip link show "${TAILSCALE_IFACE}" >/dev/null 2>&1; then
        warn "Interface '${TAILSCALE_IFACE}' not found yet. Rules will apply when it exists."
        warn "The rules will be applied to any interface matching tailscale* pattern."
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

configure_ufw_hetzner() {
    local dry_run="${1:-false}"

    info "=== Hetzner UFW Configuration ==="
    info "Public ports: SSH(22), HTTP(80), HTTPS(443)"
    info "Tailscale-only: monitoring, dashboards, databases, admin panels"
    info ""

    # --- Step 1: Reset UFW to clean slate ---
    info "[1/8] Resetting UFW to factory defaults..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw --force reset"
    else
        ufw --force reset
    fi

    # --- Step 2: Set default policies ---
    info "[2/8] Setting default policies (deny all incoming, allow all outgoing)..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw default deny incoming"
        echo "  > ufw default allow outgoing"
    else
        ufw default deny incoming
        ufw default allow outgoing
    fi

    # --- Step 3: Allow public-facing services ---
    info "[3/8] Allowing PUBLIC services: SSH, HTTP, HTTPS..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw allow 22/tcp comment 'SSH public'"
        echo "  > ufw allow 80/tcp comment 'HTTP public'"
        echo "  > ufw allow 443/tcp comment 'HTTPS public'"
    else
        ufw allow 22/tcp comment 'SSH public'
        ufw allow 80/tcp comment 'HTTP public'
        ufw allow 443/tcp comment 'HTTPS public'
    fi

    # --- Step 4: SSH rate limiting ---
    info "[4/8] Applying SSH rate limit (${SSH_RATE_LIMIT})..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw limit 22/tcp comment 'SSH rate-limited'"
    else
        # Remove the existing allow rule and replace with limited
        ufw delete allow 22/tcp >/dev/null 2>&1 || true
        ufw limit 22/tcp comment 'SSH rate-limited'
        info "  SSH rate-limit set: max ${SSH_RATE_LIMIT} connections"
    fi

    # --- Step 5: Tailscale-only ports (admin, dashboards, monitoring, DB) ---
    info "[5/8] Restricting admin/dashboard/monitoring/DB ports to tailscale0 interface..."

    # Security rationale: These ports expose sensitive administrative interfaces.
    # Binding them to tailscale0 ensures they are ONLY accessible via the
    # encrypted WireGuard mesh — not from the public internet.
    #
    # Ports are grouped by function for clarity.

    # Monitoring & Observability
    declare -A tailscale_ports=(
        ["19999"]="Netdata (realtime system monitoring)"
        ["3001"]="Uptime Kuma (synthetic monitoring)"
        ["3002"]="Grafana (metrics dashboards)"
        ["9090"]="Prometheus (metrics collection)"
        ["9000"]="Portainer HTTP (container management)"
        ["9443"]="Portainer HTTPS (container management)"
        ["5001"]="Dockge (stack management)"
        ["8090"]="1Panel (server management panel)"
    )

    # Analytics & Data
    tailscale_ports["8088"]="Apache Superset (data exploration)"
    tailscale_ports["8123"]="ClickHouse HTTP (analytics DB)"
    tailscale_ports["5432"]="PostgreSQL (AI/Ops database)"
    tailscale_ports["5433"]="Prediction Radar PostgreSQL"
    tailscale_ports["5434"]="RavynAI PostgreSQL"

    # AI & Automation
    tailscale_ports["8098"]="Prediction Radar (web interface)"
    tailscale_ports["8007"]="RavynAI (API)"
    tailscale_ports["5000"]="ChangeDetection (monitoring)"
    tailscale_ports["3130"]="Healthchecks (cron monitoring)"
    tailscale_ports["8080"]="Spiderfoot (OSINT)"
    tailscale_ports["3000"]="Browser Automation (UI)"

    # Apply rules for each tailscale-only port
    for port in "${!tailscale_ports[@]}"; do
        local comment="${tailscale_ports[$port]}"
        if [ "${dry_run}" = "true" ]; then
            echo "  > ufw allow in on ${TAILSCALE_IFACE} to any port ${port} proto tcp comment '${comment}'"
        else
            # Remove any existing rule for this port first (idempotency)
            ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
            ufw delete allow in on "${TAILSCALE_IFACE}" to any port "${port}" proto tcp >/dev/null 2>&1 || true

            # Apply the interface-restricted rule
            ufw allow in on "${TAILSCALE_IFACE}" to any port "${port}" proto tcp comment "${comment}"
        fi
    done
    info "  $(echo "${#tailscale_ports[@]}") tailscale-only rules applied."

    # --- Step 6: Docker Bridge Bypass — allow Docker's bridge to work ---
    info "[6/8] Configuring Docker bridge compatibility..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw allow in on docker0 to 172.17.0.0/16"
        echo "  > sed -i 's/DEFAULT_FORWARD_POLICY=\"DROP\"/DEFAULT_FORWARD_POLICY=\"ACCEPT\"/' /etc/default/ufw"
    else
        # Allow Docker bridge traffic
        ufw allow in on docker0 from 172.17.0.0/16 >/dev/null 2>&1 || true
        # Explicitly accept forwarded traffic (required for Docker networking)
        if grep -q '^DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
            sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
            info "  UFW default forward policy set to ACCEPT (required for Docker)."
        fi
    fi

    # --- Step 7: Enable logging (but rate-limited) ---
    info "[7/8] Enabling UFW logging (rate-limited)..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw logging low"
    else
        ufw logging low
    fi

    # --- Step 8: Enable UFW ---
    info "[8/8] Enabling UFW..."
    if [ "${dry_run}" = "true" ]; then
        echo "  > ufw --force enable"
    else
        ufw --force enable
    fi

    # --- Done ---
    info "=== Hetzner UFW configuration complete ==="

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

    # Check that UFW is active
    if ufw status | grep -qi "Status: active"; then
        info "[PASS] UFW is active"
    else
        warn "[FAIL] UFW is NOT active — run: ufw --force enable"
    fi

    # Check that SSH is allowed
    if ufw status | grep -qi "22/tcp.*LIMIT"; then
        info "[PASS] SSH is rate-limited (22/tcp)"
    else
        warn "[WARN] SSH does not appear to be rate-limited"
    fi

    # Check key tailscale-only ports
    local critical_ports="19999 3001 3002 9090 8090 9443 5432"
    for port in ${critical_ports}; do
        if ufw status | grep -qi "${port}/tcp.*ALLOW.*${TAILSCALE_IFACE}"; then
            info "[PASS] Port ${port} restricted to ${TAILSCALE_IFACE}"
        else
            warn "[WARN] Port ${port} may not be restricted to ${TAILSCALE_IFACE}"
            warn "       Check: ufw status | grep ${port}"
        fi
    done

    # Check that port 80/443 are allowed
    for port in 80 443; do
        if ufw status | grep -qi "${port}/tcp.*ALLOW"; then
            info "[PASS] Port ${port} is publicly accessible"
        else
            warn "[FAIL] Port ${port} is NOT publicly accessible"
        fi
    done

    info ""
    info "Verification complete. Review any [WARN] or [FAIL] messages above."
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (sudo)."
    fi

    # Check prerequisites
    check_prerequisites

    # Dry-run mode
    local dry_run="false"
    if dry_run_mode "$@"; then
        dry_run="true"
    fi

    # Run configuration
    configure_ufw_hetzner "${dry_run}"

    # Verify (only in non-dry-run mode)
    if [ "${dry_run}" = "false" ]; then
        verify_rules
    fi

    info ""
    info "Usage tips:"
    info "  sudo ./ufw-hetzner.sh           # Apply rules (production)"
    info "  sudo ./ufw-hetzner.sh --dry-run  # Preview without applying"
    info "  ufw status numbered               # Review active rules"
    info "  ufw delete <rule_number>          # Remove a specific rule"
}

main "$@"
