#!/usr/bin/env bash
# =============================================================================
# CrowdSec Hardening Script — Both Servers (Hetzner & Hostinger)
# =============================================================================
#
# Security Rationale:
#   CrowdSec is a modern, community-driven IPS (Intrusion Prevention System).
#   Unlike Fail2ban (which only knows about YOUR server's logs), CrowdSec
#   shares threat intelligence across a global community. If someone attacks
#   1000 other servers and then hits yours, CrowdSec already knows they're bad.
#
# Architecture:
#   - CrowdSec AGENT: installed on both servers, reads local logs
#   - CrowdSec BOUNCER: Traefik bouncer stops malicious IPs at the reverse proxy
#   - CrowdSec CENTRAL: optional API for cross-server signal sharing
#
# Traffic flow:
#   Internet → Traefik → CrowdSec Bouncer → (block/reject) → Backend
#                         ↓
#                   CrowdSec Agent (reads Traefik logs)
#                         ↓
#                   CrowdSec Central API (global signal sharing)
#
# Idempotent: YES — checks for existing install before proceeding.
# =============================================================================

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

# Set to your CrowdSec Central API enrollment key (if using)
CROWDSEC_ENROLL_KEY="${CROWDSEC_ENROLL_KEY:-}"

# CrowdSec version to install
CROWDSEC_VERSION="latest"

# Log sources to monitor
declare -a LOG_SOURCES=(
    "/var/log/auth.log"
    "/var/log/traefik/access.log"
    "/var/log/syslog"
)

# Bouncer configuration
TRAEFIK_BOUNCER_KEY="${TRAEFIK_BOUNCER_KEY:-$(openssl rand -hex 32)}"

# Notification methods (comma-separated: slack,email,splunk,webhook)
NOTIFICATION_METHODS="${NOTIFICATION_METHODS:-email}"

# Server role: "hetzner" or "hostinger"
SERVER_ROLE="${SERVER_ROLE:-$(hostname | grep -qi 'hetzner' && echo 'hetzner' || echo 'hostinger')}"

# ─── Helper Functions ────────────────────────────────────────────────────────

info()  { printf "[INFO]  %s\n" "$*"; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }
ok()    { printf "[OK]    %s\n" "$*"; }

check_prerequisites() {
    local missing=0
    for cmd in curl openssh-server systemctl; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            warn "Missing prerequisite: ${cmd}"
            missing=$((missing + 1))
        fi
    done

    if [ "${missing}" -gt 0 ]; then
        error "Install missing prerequisites and re-run."
    fi

    # Detect OS
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        info "Detected OS: ${ID} ${VERSION_ID}"
    fi
}

dry_run_mode() {
    if [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "-n" ]; then
        info "DRY RUN MODE — commands will be shown but NOT executed."
        return 0
    fi
    return 1
}

is_installed() {
    command -v cscli >/dev/null 2>&1 && command -v crowdsec >/dev/null 2>&1
}

# ─── Installation ───────────────────────────────────────────────────────────

install_crowdsec_agent() {
    info "=== Installing CrowdSec Agent ==="

    if is_installed; then
        local cs_version
        cs_version=$(cscli version 2>/dev/null | head -1)
        info "CrowdSec already installed: ${cs_version}"
        info "Skipping installation."
        return 0
    fi

    info "Downloading and installing CrowdSec..."
    info "Using official CrowdSec install script."

    # Official CrowdSec installation method
    if curl -s https://install.crowdsec.net | bash; then
        info "CrowdSec repository added successfully."
    else
        error "Failed to add CrowdSec repository. Check network connectivity."
    fi

    # Install the agent package
    apt-get update -qq
    apt-get install -y -qq crowdsec || {
        error "Failed to install crowdsec package."
    }

    ok "CrowdSec agent installed successfully."
}

install_traefik_bouncer() {
    info "=== Installing Traefik Bouncer ==="

    if dpkg -l | grep -q crowdsec-traefik-bouncer; then
        info "crowdsec-traefik-bouncer already installed."
        return 0
    fi

    apt-get install -y -qq crowdsec-traefik-bouncer || {
        error "Failed to install crowdsec-traefik-bouncer."
    }

    ok "crowdsec-traefik-bouncer installed."
}

# ─── Configuration ──────────────────────────────────────────────────────────

configure_bouncer() {
    local bouncer_cfg="/etc/crowdsec/bouncers/crowdsec-traefik-bouncer.yaml"

    info "=== Configuring Traefik Bouncer ==="

    if [ -f "${bouncer_cfg}" ]; then
        info "Bouncer config already exists at ${bouncer_cfg}"

        # Check if API key is set
        if grep -q 'api_key:' "${bouncer_cfg}" 2>/dev/null; then
            info "Bouncer API key already configured."
            return 0
        fi
    fi

    # Create bouncer in CrowdSec and get API key
    info "Registering bouncer with CrowdSec..."
    local bouncer_key
    bouncer_key=$(cscli bouncers add traefik-bouncer 2>/dev/null | grep -oP 'API key: \K\S+' || echo "${TRAEFIK_BOUNCER_KEY}")

    info "Bouncer API key: ${bouncer_key}"

    # Write bouncer configuration
    cat > "${bouncer_cfg}" <<BOUNCER_CFG
# =============================================================================
# CrowdSec Traefik Bouncer Configuration
# =============================================================================
# Generated by crowdsec-install.sh
# Security: This file contains the API key for CrowdSec bouncer.
# Protect it: chmod 640, owned by root:root

# API key for authenticating with CrowdSec Local API
api_key: ${bouncer_key}

# CrowdSec Local API URL
api_url: http://127.0.0.1:8080

# How long to wait before querying CrowdSec (in milliseconds)
update_frequency: 1000

# Default remediation (what to do when CrowdSec says "block")
default_remediation: ban

# Connection to Traefik middleware
listen_uri: 127.0.0.1:8081

# Logging
log_level: info
log_dir: /var/log/crowdsec-traefik-bouncer

# Forwarded headers trust (only if behind another proxy)
# trusted_ips:
#   - 127.0.0.1/8
#   - ::1/128
BOUNCER_CFG

    # Secure the config file
    chmod 640 "${bouncer_cfg}"
    chown root:root "${bouncer_cfg}"

    ok "Bouncer configured."
}

configure_log_sources() {
    local acquis_cfg="/etc/crowdsec/acquis.yaml"

    info "=== Configuring Log Sources ==="

    # Backup existing config if present
    if [ -f "${acquis_cfg}" ] && [ ! -f "${acquis_cfg}.bak" ]; then
        cp "${acquis_cfg}" "${acquis_cfg}.bak"
        info "Backed up existing acquis.yaml to ${acquis_cfg}.bak"
    fi

    cat > "${acquis_cfg}" <<'ACQUIS'
# =============================================================================
# CrowdSec Acquisition Configuration
# =============================================================================
# Defines which log files CrowdSec should monitor.
# Generated by crowdsec-install.sh

# ─── SSH Authentication Log ────────────────────────────────────────────
filename: /var/log/auth.log
labels:
  type: syslog

# ─── Traefik Access Log (if exists) ────────────────────────────────────
filename: /var/log/traefik/access.log
labels:
  type: traefik

# ─── Syslog (catch-all for other services) ────────────────────────────
filename: /var/log/syslog
labels:
  type: syslog

# ─── Docker Logs (if available) ───────────────────────────────────────
# Uncomment if you want CrowdSec to monitor Docker container logs
# source: docker
# labels:
#   type: docker
ACQUIS

    ok "Log sources configured at ${acquis_cfg}."
}

configure_scenarios() {
    info "=== Importing CrowdSec Scenarios ==="

    # CrowdSec uses scenarios to detect attacks. Install the common ones.
    info "Installing common scenarios and collections..."

    # Collections are bundles of scenarios + parsers for specific services
    local -a collections=(
        "crowdsecurity/sshd"        # SSH brute force
        "crowdsecurity/traefik"    # Traefik-specific (401/403/429)
        "crowdsecurity/http-cve"   # CVE exploit attempts via HTTP
        "crowdsecurity/linux"      # General Linux security
    )

    for collection in "${collections[@]}"; do
        info "  Installing collection: ${collection}"
        cscli collections install "${collection}" 2>/dev/null || \
            warn "  Collection ${collection} may already be installed or unavailable."
    done

    ok "Scenarios configured."
}

configure_notifications() {
    local notification_dir="/etc/crowdsec/notifications"
    mkdir -p "${notification_dir}"

    info "=== Configuring Notifications ==="

    # ─── Email Notification ──────────────────────────────────────────
    if echo "${NOTIFICATION_METHODS}" | grep -qi "email"; then
        local email_cfg="${notification_dir}/email.yaml"

        info "Configuring email notifications..."

        cat > "${email_cfg}" <<EMAIL
# Email notification configuration for CrowdSec
# Edit SMTP settings for your environment

name: email_notification
type: email

smtp_host: ${SMTP_HOST:-localhost}
smtp_port: ${SMTP_PORT:-25}
smtp_username: ${SMTP_USERNAME:-}
smtp_password: ${SMTP_PASSWORD:-}
smtp_insecure_skip_verify: false

from: crowdsec@${SERVER_ROLE}.wheeler.ai
to: ${ALERT_EMAIL:-admin@wheeler.ai}

# Send email when a decision is taken (default)
group_wait: 5s
group_threshold: 5
EMAIL

        # Register the notification profile
        local profile_file="/etc/crowdsec/profiles.yaml"
        if [ -f "${profile_file}" ]; then
            if ! grep -q "email_notification" "${profile_file}" 2>/dev/null; then
                cat >> "${profile_file}" <<'PROFILE'

# Email notification profile (added by crowdsec-install.sh)
- name: email_profile
  notifications:
    - email_notification
  on_failure: ignore
  filters:
    - Alert.GetScope() == "Ip"
  decisions:
    - type: ban
      duration: 4h
PROFILE
            fi
        fi
    fi

    # ─── Slack Notification (Optional) ───────────────────────────────
    if echo "${NOTIFICATION_METHODS}" | grep -qi "slack"; then
        local slack_cfg="${notification_dir}/slack.yaml"

        info "Configuring Slack notifications..."

        cat > "${slack_cfg}" <<SLACK
# Slack notification configuration for CrowdSec
# Requires a Slack webhook URL

name: slack_notification
type: slack
webhook_url: ${SLACK_WEBHOOK_URL:-https://hooks.slack.com/services/YOUR/WEBHOOK/HERE}

group_wait: 5s
group_threshold: 5
SLACK
    fi

    ok "Notifications configured for: ${NOTIFICATION_METHODS}"
}

register_with_central() {
    info "=== Registering with CrowdSec Central API ==="

    if [ -z "${CROWDSEC_ENROLL_KEY}" ]; then
        warn "CROWDSEC_ENROLL_KEY not set. Skipping central API enrollment."
        warn "To enroll later: cscli console enroll <enroll_key>"
        return 0
    fi

    # Enroll with CrowdSec Central API for global threat intelligence
    cscli console enroll "${CROWDSEC_ENROLL_KEY}" 2>/dev/null || {
        warn "Central API enrollment failed. Check your enrollment key."
        return 1
    }

    ok "Registered with CrowdSec Central API."
}

# ─── Service Management ───────────────────────────────────────────────────────

start_services() {
    info "=== Starting CrowdSec Services ==="

    systemctl enable crowdsec
    systemctl restart crowdsec
    info "CrowdSec agent started."

    # Enable and start the bouncer
    if systemctl list-unit-files | grep -q crowdsec-traefik-bouncer; then
        systemctl enable crowdsec-traefik-bouncer 2>/dev/null || true
        systemctl restart crowdsec-traefik-bouncer 2>/dev/null || true
        info "CrowdSec Traefik bouncer started."
    fi

    ok "All CrowdSec services running."
}

# ─── Verification ─────────────────────────────────────────────────────────────

verify_installation() {
    info ""
    info "=== Verifying CrowdSec Installation ==="

    local errors=0

    # Check agent status
    if systemctl is-active --quiet crowdsec; then
        ok "[PASS] CrowdSec agent is running"
    else
        warn "[FAIL] CrowdSec agent is NOT running"
        errors=$((errors + 1))
    fi

    # Check bouncer status
    if systemctl list-unit-files 2>/dev/null | grep -q crowdsec-traefik-bouncer; then
        if systemctl is-active --quiet crowdsec-traefik-bouncer; then
            ok "[PASS] CrowdSec Traefik bouncer is running"
        else
            warn "[FAIL] CrowdSec Traefik bouncer is NOT running"
            errors=$((errors + 1))
        fi
    fi

    # Check metrics
    if cscli metrics 2>/dev/null | grep -q "Line"; then
        ok "[PASS] CrowdSec is processing logs"
    else
        warn "[WARN] CrowdSec may not be processing logs yet"
    fi

    # List installed collections
    info ""
    info "Installed collections:"
    cscli collections list 2>/dev/null || warn "Could not list collections"

    # List decisions (active bans)
    info ""
    info "Active decisions (bans):"
    cscli decisions list 2>/dev/null || warn "No active decisions"

    info ""
    if [ "${errors}" -eq 0 ]; then
        ok "CrowdSec verification PASSED"
    else
        warn "CrowdSec verification had ${errors} issue(s)"
    fi
}

# ─── Traefik Middleware Configuration ──────────────────────────────────────────

generate_traefik_middleware() {
    local middleware_file="${1:-/root/infrastructure/shared/security/crowdsec-bouncer-middleware.yml}"

    info "=== Generating Traefik Bouncer Middleware ==="

    if [ -f "${middleware_file}" ]; then
        info "Middleware file already exists at ${middleware_file}"
        return 0
    fi

    mkdir -p "$(dirname "${middleware_file}")"

    cat > "${middleware_file}" <<'MIDDLEWARE'
# =============================================================================
# Traefik CrowdSec Bouncer Middleware
# =============================================================================
# Deploy this middleware in your Traefik dynamic configuration.
# It queries CrowdSec before allowing a request to reach the backend.
#
# Usage in traefik.yml:
#   experimental:
#     plugins:
#       crowdsec-bouncer:
#         moduleName: github.com/maxlerebourc/crowdsec-bouncer-traefik-plugin
#         version: v0.3.0
#
# Usage on a router:
#   router:
#     middlewares:
#       - crowdsec-bouncer@file

http:
  middlewares:
    crowdsec-bouncer:
      plugin:
        crowdsec-bouncer:
          enabled: true
          # URL of the CrowdSec bouncer API
          bouncerUrl: http://127.0.0.1:8081
          # Bouncer API key (must match config in /etc/crowdsec/bouncers/)
          apiKey: "${CROWDSEC_BOUNCER_API_KEY}"
          # Forward original IP even behind proxy
          trustedIps:
            - 127.0.0.1/8
            - ::1/128
          # Log level: trace, debug, info, warn, error
          logLevel: info
MIDDLEWARE

    ok "Traefik middleware file generated at ${middleware_file}"
    info "Edit ${middleware_file} to set the correct apiKey before deploying."
}

# ─── Dry Run ──────────────────────────────────────────────────────────────────

dry_run_info() {
    info "DRY RUN — CrowdSec installation plan:"
    info "  1. Install CrowdSec agent via official script"
    info "  2. Install crowdsec-traefik-bouncer package"
    info "  3. Configure log sources (auth.log, traefik access log, syslog)"
    info "  4. Import security scenarios (SSH, Traefik, HTTP CVE, Linux)"
    info "  5. Register with CrowdSec Central API (if key provided)"
    info "  6. Configure notifications (email/slack)"
    info "  7. Generate Traefik middleware configuration"
    info ""
    info "Run without --dry-run to execute."
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (sudo)."
    fi

    check_prerequisites

    if dry_run_mode "$@"; then
        dry_run_info
        exit 0
    fi

    info "=== CrowdSec Hardening — ${SERVER_ROLE} ==="
    info ""

    # Step-by-step installation and configuration
    install_crowdsec_agent
    install_traefik_bouncer
    configure_log_sources
    configure_scenarios
    configure_bouncer
    configure_notifications
    register_with_central
    start_services
    generate_traefik_middleware

    # Verification
    verify_installation

    info ""
    info "=== CrowdSec hardening complete on ${SERVER_ROLE} ==="
    info ""
    info "Next steps:"
    info "  1. Verify Traefik bouncer is working: cscli metrics"
    info "  2. Test with: curl -H 'User-Agent: crowdsec_test' http://localhost"
    info "  3. Monitor bans: cscli decisions list"
    info "  4. Add Traefik middleware to your routers"
    info "  5. Unban an IP: cscli decisions delete --ip <IP>"
    info ""
    info "Bouncer API key (save this): ${TRAEFIK_BOUNCER_KEY}"
    info "To re-run, set TRAEFIK_BOUNCER_KEY to keep the same key."
}

main "$@"
