#!/usr/bin/env bash
# =============================================================================
# Fail2ban Hardening Script — Hetzner CPX51 (Primary AIOps Orchestrator)
# =============================================================================
#
# Security Rationale:
#   Fail2ban provides an additional layer of defense by dynamically blocking
#   IPs that exhibit malicious behavior. While UFW is static (rules don't
#   change), Fail2ban responds to attacks in real-time.
#
# Strategy:
#   - sshd jail: 3 failures = 1 hour ban (catches brute force quickly)
#   - traefik-auth jail: watches Traefik access logs for 401/403/429 responses
#     (catches API abuse, auth scraping, path traversal attempts)
#   - recidive jail: 1 week ban for repeat offenders (IPs that keep getting
#     banned across multiple jails — persistent threats)
#   - Custom Traefik filter that parses the Traefik access log format
#
# Requirements:
#   - Fail2ban installed (apt-get install fail2ban)
#   - Traefik access logs enabled (--access.log=true or in traefik.yml)
#   - Log file: /var/log/traefik/access.log (customize if different)
#
# Idempotent: YES — creates/replaces jail.local and filter configs.
# =============================================================================

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

F2B_CONF_DIR="/etc/fail2ban"
F2B_JAIL_LOCAL="${F2B_CONF_DIR}/jail.local"
F2B_FILTER_DIR="${F2B_CONF_DIR}/filter.d"
TRAEFIK_FILTER="${F2B_FILTER_DIR}/traefik-auth.conf"
TRAEFIK_LOG_PATH="/var/log/traefik/access.log"

# ─── Helper Functions ────────────────────────────────────────────────────────

info()  { printf "[INFO]  %s\n" "$*"; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

check_prerequisites() {
    if [ ! -d "${F2B_CONF_DIR}" ]; then
        error "Fail2ban does not appear to be installed. Run: apt-get install fail2ban"
    fi

    if [ ! -d "${F2B_FILTER_DIR}" ]; then
        error "Fail2ban filter directory missing: ${F2B_FILTER_DIR}"
    fi

    info "Fail2ban detected at ${F2B_CONF_DIR}"
}

# ─── Configuration Files ─────────────────────────────────────────────────────

write_jail_local() {
    info "Writing ${F2B_JAIL_LOCAL}..."

    cat > "${F2B_JAIL_LOCAL}" <<'FAIL2BAN'
# =============================================================================
# Fail2ban Jail Configuration — Hetzner CPX51
# =============================================================================
#
# This file is managed by fail2ban-hetzner.sh — do not edit manually.
# Changes will be overwritten on next run.

[DEFAULT]
# Default ban action: use ufw (consistent with our firewall setup)
banaction = ufw

# Ignore internal Tailscale IPs (never ban ourselves or our other server)
ignoreip = 127.0.0.1/8 ::1 100.64.0.0/10 10.0.0.0/8

# Default time windows
findtime  = 600    # 10 minutes — time window for counting failures
maxretry  = 3      # 3 failures within findtime = ban
bantime   = 3600   # 1 hour initial ban

# Notification
destemail = root@localhost
sendername = fail2ban-hetzner
action = %(action_mwl)s

# ─────────────────────────────────────────────────────────────────────────────
# SSH Jail
# ─────────────────────────────────────────────────────────────────────────────
# Rationale: SSH is the primary admin access method. Brute force is the #1
# attack vector. 3 failed attempts in 10 minutes = 1 hour ban. Legitimate
# users with key-based auth will never trigger this (key failure does not
# count as a failed auth attempt unless specifically configured).
[sshd]
enabled   = true
port      = ssh
filter    = sshd
logpath   = /var/log/auth.log
maxretry  = 3
bantime   = 3600
findtime  = 600

# ─────────────────────────────────────────────────────────────────────────────
# Traefik Auth Jail
# ─────────────────────────────────────────────────────────────────────────────
# Rationale: Traefik is the entry point for ALL web services. Attackers will
# probe for:
#   - 401 Unauthorized (trying default creds on dashboards)
#   - 403 Forbidden  (path traversal attempts blocked by middleware)
#   - 429 Too Many Requests (we already rate-limit, but repeat offenders)
# This jail catches all of these and bans repeat offenders.
[traefik-auth]
enabled   = true
port      = http,https
filter    = traefik-auth
logpath   = /var/log/traefik/access.log
maxretry  = 10    # Allow some 401s (bots will try a few times)
bantime   = 7200  # 2 hours — longer than SSH because Traefik is public
findtime  = 600

# ─────────────────────────────────────────────────────────────────────────────
# Recidive Jail
# ─────────────────────────────────────────────────────────────────────────────
# Rationale: Some IPs keep coming back after their ban expires. The recidive
# jail catches IPs that have been banned multiple times across any jail and
# escalates to a much longer ban. This is your last line of defense against
# persistent attackers.
[recidive]
enabled   = true
filter    = recidive
logpath   = /var/log/fail2ban.log
maxretry  = 3      # Banned 3 times across any jail
bantime   = 604800 # 1 WEEK — persistent threats get long bans
findtime  = 86400  # Look back 1 day for repeat bans
FAIL2BAN

    info "  jail.local written successfully."
}

write_traefik_filter() {
    info "Writing ${TRAEFIK_FILTER}..."

    cat > "${TRAEFIK_FILTER}" <<'TRAEFIK_FILTER'
# =============================================================================
# Fail2ban Filter: traefik-auth
# =============================================================================
#
# Parses Traefik access logs for authentication failures and request abuses.
#
# Traefik log format (default combined):
#   <remote_addr> - - [<timestamp>] "<method> <path> <proto>" <status> <size> "<referer>" "<user-agent>" <duration> <frontend> <backend> <latency>
#
# This filter matches:
#   - 401 Unauthorized — failed auth or missing credentials
#   - 403 Forbidden   — blocked by IP whitelist middleware or rate limiter
#   - 429 Too Many Requests — already rate-limited (repeat offense)
#
[Definition]

# Match lines with 401, 403, or 429 status codes
failregex = ^<HOST> .* "(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS) .*" (401|403|429) .*$

# Ignore common scanners that we don't care about (optional)
ignoreregex =

# Date pattern for Traefik logs
datepattern = {^LN-BEG}
TRAEFIK_FILTER

    info "  Traefik auth filter written successfully."
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
    info "=== Verifying Fail2ban Jails ==="
    sleep 1  # Give fail2ban a moment to load configs

    local jails
    jails=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*:\s*//')

    for expected in "sshd" "traefik-auth" "recidive"; do
        if echo "${jails}" | grep -qi "${expected}"; then
            info "[PASS] Jail '${expected}' is active"
        else
            warn "[FAIL] Jail '${expected}' is NOT active"
        fi
    done

    # Verify the Traefik filter loads correctly
    if fail2ban-client get traefik-auth filter 2>/dev/null | grep -qi "traefik-auth"; then
        info "[PASS] Traefik filter loaded successfully"
    else
        warn "[WARN] Could not verify Traefik filter — check: fail2ban-client get traefik-auth filter"
    fi

    info ""
    info "Manual verification commands:"
    info "  fail2ban-client status              # List all jails"
    info "  fail2ban-client status sshd         # SSH jail details"
    info "  fail2ban-client status traefik-auth # Traefik jail details"
    info "  fail2ban-client set sshd unbanip <IP>  # Unban an IP"
}

# ─── Dry Run ─────────────────────────────────────────────────────────────────

dry_run_files() {
    info "DRY RUN — would create the following files:"
    info "  ${F2B_JAIL_LOCAL}"
    info "  ${TRAEFIK_FILTER}"
    info ""
    info "Content preview for ${F2B_JAIL_LOCAL}:"
    info "  [sshd] enabled=true maxretry=3 bantime=3600 findtime=600"
    info "  [traefik-auth] enabled=true maxretry=10 bantime=7200 findtime=600"
    info "  [recidive] enabled=true maxretry=3 bantime=604800 findtime=86400"
    info ""
    info "Content preview for ${TRAEFIK_FILTER}:"
    info "  failregex = ^<HOST> .* \"(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS) .*\" (401|403|429) .*$"
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
        dry_run_files
        exit 0
    fi

    info "=== Hetzner Fail2ban Hardening ==="

    # Write configuration files
    write_jail_local
    write_traefik_filter

    # Create Traefik log directory if it doesn't exist
    local traefik_log_dir
    traefik_log_dir="$(dirname "${TRAEFIK_LOG_PATH}")"
    if [ ! -d "${traefik_log_dir}" ]; then
        info "Creating Traefik log directory: ${traefik_log_dir}"
        mkdir -p "${traefik_log_dir}"
    fi

    # Ensure Traefik log file exists (fail2ban needs at least an empty file)
    if [ ! -f "${TRAEFIK_LOG_PATH}" ]; then
        info "Creating empty Traefik log file: ${TRAEFIK_LOG_PATH}"
        touch "${TRAEFIK_LOG_PATH}"
    fi

    # Restart fail2ban to pick up new configs
    restart_fail2ban

    # Verify
    verify_jails

    info ""
    info "=== Hetzner Fail2ban hardening complete ==="
    info "Next steps:"
    info "  1. Ensure Traefik is configured with --access.log=true"
    info "  2. Verify logs: tail -f /var/log/fail2ban.log"
    info "  3. Test by intentionally failing SSH: ssh invalid@<server>"
}

main "$@"
