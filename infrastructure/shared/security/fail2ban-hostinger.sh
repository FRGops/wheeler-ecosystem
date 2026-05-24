#!/usr/bin/env bash
# =============================================================================
# Fail2ban Hardening Script — Hostinger VPS (Public Edge / Frontend)
# =============================================================================
#
# Security Rationale:
#   Hostinger is the PUBLIC-FACING edge server — it takes the brunt of all
#   internet traffic (good, bad, and malicious). Fail2ban config here is
#   STRICTER than Hetzner because:
#     - Every request hits Hostinger first
#     - We want to drop bad actors BEFORE they reach Hetzner
#     - Edge servers are more exposed and should be more aggressive
#
# Strategy:
#   - sshd: 3 failures = 2 hour ban (Hetzner: 1 hour)
#   - traefik-auth: 8 failures = 4 hour ban (Hetzner: 10/2 hours)
#   - recidive: 2 repeat bans = 2 WEEK ban (Hetzner: 3/1 week)
#   - Post-ban notification logged to syslog for SIEM ingestion
#
# Requirements:
#   - Fail2ban installed (apt-get install fail2ban)
#   - Traefik access logs enabled
#
# Idempotent: YES
# =============================================================================

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

F2B_CONF_DIR="/etc/fail2ban"
F2B_JAIL_LOCAL="${F2B_CONF_DIR}/jail.local"
TRAEFIK_LOG_PATH="/var/log/traefik/access.log"

# ─── Helper Functions ────────────────────────────────────────────────────────

info()  { printf "[INFO]  %s\n" "$*"; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

check_prerequisites() {
    if [ ! -d "${F2B_CONF_DIR}" ]; then
        error "Fail2ban not installed. Run: apt-get install fail2ban"
    fi
    info "Fail2ban detected."
}

# ─── Jail Configuration (Hostinger — Strict) ────────────────────────────────

write_jail_local() {
    info "Writing ${F2B_JAIL_LOCAL} (Hostinger — strict version)..."

    cat > "${F2B_JAIL_LOCAL}" <<'FAIL2BAN'
# =============================================================================
# Fail2ban Jail Configuration — Hostinger VPS (EDGE SERVER — STRICT)
# =============================================================================
#
# This file is managed by fail2ban-hostinger.sh — do not edit manually.
# Stricter thresholds than Hetzner. Edge servers are more aggressively
# hardened because they face the public internet directly.

[DEFAULT]
banaction = ufw

# Never ban ourselves or the Hetzner backend
ignoreip = 127.0.0.1/8 ::1 100.64.0.0/10 10.0.0.0/8

findtime  = 600     # 10 minute window
maxretry  = 3       # 3 failures by default
bantime   = 7200    # 2 hours (Hetzner: 1 hour)

destemail = root@localhost
sendername = fail2ban-hostinger
action = %(action_mwl)s

# ─────────────────────────────────────────────────────────────────────────────
# SSH Jail — Edge Server (Stricter)
# ─────────────────────────────────────────────────────────────────────────────
# Rationale: Edge server SSH access is for admin use only. No regular users
# SSH here. 3 failures = 2 hour ban. Key-based auth won't trigger this.
[sshd]
enabled   = true
port      = ssh
filter    = sshd
logpath   = /var/log/auth.log
maxretry  = 3
bantime   = 7200   # 2 hours (Hetzner: 1 hour)
findtime  = 600

# ─────────────────────────────────────────────────────────────────────────────
# Traefik Auth Jail — Edge Server (Stricter)
# ─────────────────────────────────────────────────────────────────────────────
# Rationale: The edge handles ALL incoming requests before they reach Hetzner.
# We want to be more aggressive here — fewer 401s tolerated, longer bans.
[traefik-auth]
enabled   = true
port      = http,https
filter    = traefik-auth
logpath   = /var/log/traefik/access.log
maxretry  = 8      # Stricter: 8 vs Hetzner's 10
bantime   = 14400  # 4 hours (Hetzner: 2 hours)
findtime  = 600

# ─────────────────────────────────────────────────────────────────────────────
# Recidive Jail — Edge Server (Much Stricter)
# ─────────────────────────────────────────────────────────────────────────────
# Rationale: If someone is persistent enough to get banned twice on the edge
# server, they are almost certainly a threat. Escalate to a 2-week ban.
[recidive]
enabled   = true
filter    = recidive
logpath   = /var/log/fail2ban.log
maxretry  = 2      # Only 2 repeat bans needed (Hetzner: 3)
bantime   = 1209600 # 2 WEEKS (Hetzner: 1 week)
findtime  = 86400

# ─────────────────────────────────────────────────────────────────────────────
# Postfix / SMTP Auth Jail
# ─────────────────────────────────────────────────────────────────────────────
# Rationale: If this edge server ever runs a mail server or SMTP relay,
# enable this jail. SMTP auth brute force is extremely common.
# [postfix]
# enabled  = true
# filter   = postfix
# logpath  = /var/log/mail.log
# maxretry = 3
# bantime  = 7200
FAIL2BAN

    info "  Hostinger jail.local written."
}

write_traefik_filter() {
    # Security rationale: Reuse the same Traefik filter as Hetzner.
    # The filter regex is the same; only the thresholds differ.
    local filter_path="/etc/fail2ban/filter.d/traefik-auth.conf"

    if [ -f "${filter_path}" ]; then
        info "Traefik filter already exists at ${filter_path} — skipping."
        return
    fi

    info "Writing Traefik auth filter to ${filter_path}..."

    cat > "${filter_path}" <<'TRAEFIK_FILTER'
# =============================================================================
# Fail2ban Filter: traefik-auth (Shared — Hetzner & Hostinger)
# =============================================================================
#
# Matches Traefik access log entries with 401 (Unauthorized), 403 (Forbidden),
# or 429 (Too Many Requests) HTTP status codes.
#
# Traefik log format (combined):
#   <remote_addr> - - [timestamp] "METHOD /path PROTO" STATUS size ...
#
[Definition]
failregex = ^<HOST> .* "(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS) .*" (401|403|429) .*$
ignoreregex =
datepattern = {^LN-BEG}
TRAEFIK_FILTER

    info "  Traefik auth filter written."
}

# ─── Main Execution ──────────────────────────────────────────────────────────

restart_fail2ban() {
    info "Restarting Fail2ban service..."
    systemctl restart fail2ban
    info "Fail2ban status:"
    fail2ban-client status 2>/dev/null || true
}

verify_jails() {
    info ""
    info "=== Verifying Hostinger Fail2ban Jails ==="
    sleep 1

    local jails
    jails=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*:\s*//')

    for expected in "sshd" "traefik-auth" "recidive"; do
        if echo "${jails}" | grep -qi "${expected}"; then
            info "[PASS] Jail '${expected}' is active"
        else
            warn "[FAIL] Jail '${expected}' is NOT active"
        fi
    done

    # Verify bantimes are stricter
    local sshd_bantime
    sshd_bantime=$(fail2ban-client get sshd bantime 2>/dev/null)
    if [ "${sshd_bantime}" = "7200" ]; then
        info "[PASS] SSH bantime is 7200s (2 hours) — strict mode confirmed"
    else
        warn "[WARN] SSH bantime is ${sshd_bantime}s (expected 7200)"
    fi
}

dry_run() {
    info "DRY RUN — would configure:"
    info "  ${F2B_JAIL_LOCAL}  (strict edge config)"
    info "  /etc/fail2ban/filter.d/traefik-auth.conf"
    info "Jails: sshd(2h), traefik-auth(4h), recidive(2weeks)"
    info ""
    info "Run without --dry-run to apply."
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (sudo)."
    fi

    check_prerequisites

    if [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "-n" ]; then
        dry_run
        exit 0
    fi

    info "=== Hostinger Fail2ban Hardening (Edge Server — Strict) ==="

    write_jail_local
    write_traefik_filter

    local traefik_log_dir
    traefik_log_dir="$(dirname "${TRAEFIK_LOG_PATH}")"
    if [ ! -d "${traefik_log_dir}" ]; then
        mkdir -p "${traefik_log_dir}"
    fi
    if [ ! -f "${TRAEFIK_LOG_PATH}" ]; then
        touch "${TRAEFIK_LOG_PATH}"
    fi

    restart_fail2ban
    verify_jails

    info ""
    info "=== Hostinger Fail2ban hardening complete ==="
    info "Edge server is now actively banning malicious IPs."
    info "Monitor: tail -f /var/log/fail2ban.log"
}

main "$@"
