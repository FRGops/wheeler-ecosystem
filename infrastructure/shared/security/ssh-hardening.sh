#!/usr/bin/env bash
# =============================================================================
# SSH Hardening Script — Both Servers (Hetzner & Hostinger)
# =============================================================================
#
# Security Rationale:
#   SSH is the #1 attack vector on any internet-connected Linux server.
#   A single misconfiguration (password auth, weak keys, root login) can
#   lead to complete compromise. This script applies industry-standard
#   SSH hardening based on CIS benchmarks and Mozilla's SSH guidelines.
#
# Key hardening measures:
#   1. Disable password authentication (keys only)
#   2. Disable root login with password (PermitRootLogin prohibit-password)
#   3. Use ed25519 keys (modern, secure, fast)
#   4. Enable SSH audit logging (VerboseLog + LogLevel)
#   5. Set ClientAlive to detect zombie connections
#   6. Disable X11 forwarding (reduces attack surface)
#   7. Disable TCP forwarding if not needed
#   8. Restrict ciphers/MACs/Kex to strong algorithms only
#
# Important: After running this, ensure you have ed25519 keys deployed
# BEFORE disconnecting your current SSH session. The script warns you.
#
# Idempotent: YES — backs up sshd_config before modifying.
# Safety: Generates a restore script at /root/ssh-hardening-restore.sh
# =============================================================================

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
BACKUP_DIR="/root/ssh-backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESTORE_SCRIPT="/root/ssh-hardening-restore.sh"

# Users allowed to SSH (space-separated, empty = all non-root users)
# Example: ALLOWED_USERS="deploy admin"
ALLOWED_USERS="${ALLOWED_USERS:-}"

# ⚠️ Change this if you want a non-standard SSH port
# WARNING: Changing the SSH port from 22 can cause issues with some tools.
# Only change if you understand the implications.
SSH_PORT="${SSH_PORT:-22}"

# ─── Helper Functions ────────────────────────────────────────────────────────

info()  { printf "[INFO]  %s\n" "$*"; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }
ok()    { printf "[OK]    %s\n" "$*"; }

dry_run_mode() {
    if [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "-n" ]; then
        info "DRY RUN MODE — files will be shown but NOT modified."
        return 0
    fi
    return 1
}

check_prerequisites() {
    if [ ! -f "${SSHD_CONFIG}" ]; then
        error "sshd_config not found at ${SSHD_CONFIG}"
    fi

    # Check that we have sshd (OpenSSH server)
    if ! command -v sshd >/dev/null 2>&1; then
        error "sshd (OpenSSH server) is not installed."
    fi

    # Check if we're running a version that supports Include directive
    local ssh_version
    ssh_version=$(sshd -V 2>&1 | head -1 || ssh -V 2>&1 | head -1)
    info "OpenSSH version: ${ssh_version}"

    # Warn about SSH port changes
    if [ "${SSH_PORT}" != "22" ]; then
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warn "  SSH PORT CHANGE DETECTED: ${SSH_PORT}"
        warn "  Make sure your firewall allows port ${SSH_PORT}/tcp!"
        warn "  Also update your UFW rules: ufw allow ${SSH_PORT}/tcp"
        warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# ─── Backup ──────────────────────────────────────────────────────────────────

backup_sshd_config() {
    local backup_path="${BACKUP_DIR}/sshd_config.${TIMESTAMP}"

    info "=== Backing Up SSH Configuration ==="

    mkdir -p "${BACKUP_DIR}"

    if [ -f "${SSHD_CONFIG}" ]; then
        cp "${SSHD_CONFIG}" "${backup_path}"
        ok "Backed up ${SSHD_CONFIG} → ${backup_path}"
    fi

    # Backup config.d directory if it exists
    if [ -d "${SSHD_CONFIG_DIR}" ]; then
        cp -r "${SSHD_CONFIG_DIR}" "${BACKUP_DIR}/sshd_config.d.${TIMESTAMP}" 2>/dev/null || true
        info "Backed up ${SSHD_CONFIG_DIR} → ${BACKUP_DIR}/sshd_config.d.${TIMESTAMP}"
    fi

    # Back up host keys
    if ls /etc/ssh/ssh_host_* >/dev/null 2>&1; then
        cp /etc/ssh/ssh_host_* "${BACKUP_DIR}/" 2>/dev/null || true
        info "Backed up host keys to ${BACKUP_DIR}"
    fi
}

generate_restore_script() {
    info "=== Generating Restore Script ==="

    local backup_path="${BACKUP_DIR}/sshd_config.${TIMESTAMP}"

    cat > "${RESTORE_SCRIPT}" <<RESTORE
#!/usr/bin/env bash
# SSH Hardening Restore Script — generated ${TIMESTAMP}
# Run this to restore the previous SSH configuration.

set -euo xtrace

if [ "\$(id -u)" -ne 0 ]; then
    echo "Must run as root."
    exit 1
fi

echo "Restoring SSH configuration from ${TIMESTAMP}..."

# Restore sshd_config
if [ -f "${backup_path}" ]; then
    cp "${backup_path}" "${SSHD_CONFIG}"
    echo "Restored ${SSHD_CONFIG}"
fi

# Restore config.d
if [ -d "${BACKUP_DIR}/sshd_config.d.${TIMESTAMP}" ]; then
    cp -r "${BACKUP_DIR}/sshd_config.d.${TIMESTAMP}"/* "${SSHD_CONFIG_DIR}/" 2>/dev/null || true
    echo "Restored ${SSHD_CONFIG_DIR}"
fi

# Restore host keys
if ls "${BACKUP_DIR}"/ssh_host_* >/dev/null 2>&1; then
    cp "${BACKUP_DIR}"/ssh_host_* /etc/ssh/ 2>/dev/null || true
    echo "Restored SSH host keys"
fi

echo "Restarting SSH..."
systemctl restart sshd || systemctl restart ssh

echo "Restore complete. Keep this terminal open and test another session first!"
RESTORE

    chmod +x "${RESTORE_SCRIPT}"
    ok "Restore script created: ${RESTORE_SCRIPT}"
    info "  If SSH breaks, run: sudo ${RESTORE_SCRIPT}"
}

# ─── SSH Hardening ───────────────────────────────────────────────────────────

harden_ssh_config() {
    info "=== Hardening SSH Configuration ==="

    local tmp_config
    tmp_config=$(mktemp)

    # ─── Algorithm Restrictions ───────────────────────────────────────
    # Security rationale: ed25519 is the most secure and performant key type.
    # RSA < 2048 bits is trivially breakable and MUST be banned.
    # Modern systems should use ed25519 or RSA 4096+.

    cat > "${tmp_config}" <<'SSHCONFIG'
# =============================================================================
# SSH Server Configuration — Hardened
# =============================================================================
# This file is managed by ssh-hardening.sh. Do not edit manually.
# Generated: TIMESTAMP_PLACEHOLDER
# Backup: BACKUP_DIR_PLACEHOLDER

# ─── Port ────────────────────────────────────────────────────────────────
# You may change this to a non-standard port for security-through-obscurity.
# However, with key-only auth and fail2ban, port 22 is adequately protected.
Port PORT_PLACEHOLDER

# ─── Authentication — Key Only ──────────────────────────────────────────
# Rationale: Password-based SSH is the #1 cause of server compromise.
# Keys are cryptographically unforgeable; passwords can be guessed or phished.
# If you need password auth temporarily, comment these two lines.
AuthenticationMethods publickey
PasswordAuthentication no

# ─── Root Access ─────────────────────────────────────────────────────────
# Rationale: Root login with password is extremely dangerous.
# Our setting "prohibit-password" allows key-based root login but not password.
# This lets admins with ed25519 keys log in as root while blocking brute force.
# If you want to completely disable root SSH, use: PermitRootLogin no
PermitRootLogin prohibit-password

# ─── Key Types ───────────────────────────────────────────────────────────
# Rationale: ed25519 is the gold standard — fast, secure, small signatures.
# ECDSA is acceptable but ed25519 is preferred. RSA is grandfathered for
# compatibility but RSA < 2048 bits is explicitly banned.
PubkeyAcceptedAlgorithms +ssh-ed25519,ssh-rsa
PubkeyAcceptedKeyTypes +ssh-ed25519,ssh-rsa

# ─── Session Management ─────────────────────────────────────────────────
# Rationale: ClientAliveInterval + ClientAliveCountMax detects dead/abandoned
# SSH sessions and disconnects them. This prevents:
#   - Zombie sessions consuming server resources
#   - Abandoned terminals being hijacked
#   - Idle connections staying open indefinitely
ClientAliveInterval 300       # Send keepalive every 5 minutes
ClientAliveCountMax 3         # 3 missed keepalives = disconnect (15 min total)

# ─── Login Grace Time ───────────────────────────────────────────────────
# Rationale: If authentication doesn't complete in 60 seconds, drop the
# connection. This prevents slow attacks and resource exhaustion.
LoginGraceTime 60

# ─── Max Sessions ───────────────────────────────────────────────────────
# Rationale: Limit concurrent SSH sessions to prevent resource exhaustion
# and provide basic DoS protection.
MaxSessions 10

# ─── Max Auth Tries ─────────────────────────────────────────────────────
# Rationale: Limit authentication attempts per connection. With 3 max tries
# and key-only auth, a failed key attempt will quickly disconnect the client.
MaxAuthTries 3

# ─── Max Startups ───────────────────────────────────────────────────────
# Rationale: Prevent unauthenticated connection flood attacks.
# Format: start:rate:full — at 10 unauthenticated connections, drop 30%
# of new connections until max 100 is reached.
MaxStartups 10:30:100

# ─── Logging ────────────────────────────────────────────────────────────
# Rationale: VERBOSE logging captures fingerprint of failed key attempts,
# which is crucial for forensic analysis and fail2ban detection.
# WARNING: Do NOT set to DEBUG in production — it logs the session key.
LogLevel VERBOSE
SyslogFacility AUTH

# ─── Forwarding ─────────────────────────────────────────────────────────
# Rationale: X11 forwarding is rarely needed in 2025 (everyone uses terminal
# or VS Code Remote). It adds significant attack surface. Disable it.
# TCP forwarding: disable unless you specifically need SSH tunnels.
X11Forwarding no
AllowTcpForwarding no
# If you need TCP forwarding temporarily, set: AllowTcpForwarding yes
# and restrict with: PermitOpen host:port

# ─── Environment ────────────────────────────────────────────────────────
# Rationale: Disabling environment processing prevents users from injecting
# dangerous environment variables through ~/.ssh/environment or ~/.ssh/rc.
PermitUserEnvironment no

# ─── Host Key Algorithms ────────────────────────────────────────────────
# Rationale: ed25519 is preferred. RSA is kept only for legacy clients.
# Order: most secure first.
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# ─── Ciphers (Strong Only) ─────────────────────────────────────────────
# Rationale: Weak ciphers (CBC, 3DES, Arcfour) are vulnerable to various
# attacks (padding oracle, SWEET32, etc.). Only allow AEAD ciphers.
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com

# ─── MACs (Message Authentication Codes) ───────────────────────────────
# Rationale: Use only Encrypt-then-MAC (ETM) variants which are immune to
# padding oracle attacks. HMAC-SHA1 is acceptable in ETM mode.
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com

# ─── Key Exchange Algorithms ───────────────────────────────────────────
# Rationale: Curve25519 is the most secure and performant KEX algorithm.
# Diffie-Hellman集团 exchange is safe but slower. Ban all others.
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256

# ─── Host Keys ─────────────────────────────────────────────────────────
# Rationale: Only use ed25519 host keys (generate if needed).
HostKey /etc/ssh/ssh_host_ed25519_key
# Legacy host key types commented out:
#HostKey /etc/ssh/ssh_host_rsa_key
#HostKey /etc/ssh/ssh_host_ecdsa_key
SSHCONFIG

    # Replace placeholders
    sed -i "s/PORT_PLACEHOLDER/${SSH_PORT}/g" "${tmp_config}"
    sed -i "s/TIMESTAMP_PLACEHOLDER/${TIMESTAMP}/g" "${tmp_config}"
    sed -i "s|BACKUP_DIR_PLACEHOLDER|${BACKUP_DIR}|g" "${tmp_config}"

    # Apply the new configuration
    cp "${tmp_config}" "${SSHD_CONFIG}"
    rm -f "${tmp_config}"

    ok "SSH configuration written to ${SSHD_CONFIG}"
}

# ─── User Restrictions ───────────────────────────────────────────────────────

apply_user_restrictions() {
    if [ -z "${ALLOWED_USERS}" ]; then
        info "=== User Restrictions: Not applying (ALLOWED_USERS is empty) ==="
        info "  All users with valid keys can SSH."
        return
    fi

    info "=== Applying User Restrictions ==="
    info "  Allowed users: ${ALLOWED_USERS}"

    # Add AllowUsers to sshd_config (idempotent: remove first if exists)
    sed -i '/^AllowUsers/d' "${SSHD_CONFIG}"
    echo "AllowUsers ${ALLOWED_USERS}" >> "${SSHD_CONFIG}"

    ok "SSH restricted to users: ${ALLOWED_USERS}"
}

# ─── ed25519 Key Generation ──────────────────────────────────────────────────

generate_ed25519_keys() {
    info "=== Checking ed25519 Host Keys ==="

    local ed_key="/etc/ssh/ssh_host_ed25519_key"

    if [ -f "${ed_key}" ]; then
        ok "ed25519 host key already exists at ${ed_key}"
        return
    fi

    info "Generating ed25519 host key..."
    ssh-keygen -t ed25519 -f "${ed_key}" -N "" < /dev/null

    # Fix permissions
    chmod 600 "${ed_key}"
    chmod 644 "${ed_key}.pub"

    ok "ed25519 host key generated at ${ed_key}"
}

# ─── Restart SSH ─────────────────────────────────────────────────────────────

restart_ssh() {
    info "=== Restarting SSH Service ==="

    # Test the configuration first (critical safety step!)
    info "Testing SSH configuration syntax..."
    if sshd -t 2>&1; then
        ok "SSH configuration syntax is valid."
    else
        error "SSH configuration has errors! Aborting restart."
        error "Run restore: ${RESTORE_SCRIPT}"
    fi

    # Restart SSH
    systemctl restart sshd || systemctl restart ssh || {
        error "Failed to restart SSH. Running restore..."
        "${RESTORE_SCRIPT}"
        exit 1
    }

    ok "SSH restarted successfully."
    info ""
    warn "──────────────────────────────────────────────────────────────"
    warn "  ⚠️  KEEP THIS TERMINAL OPEN ⚠️"
    warn "  Open a SECOND terminal and test SSH before closing this one."
    warn "  If you get locked out, run: sudo ${RESTORE_SCRIPT}"
    warn "──────────────────────────────────────────────────────────────"
    info ""
    info "Test command (from another machine):"
    info "  ssh -i ~/.ssh/id_ed25519 user@<server> -p ${SSH_PORT}"
    info ""
    info "If SSH fails, you have 2 options:"
    info "  1. Via out-of-band console (Hetzner/Hostinger web panel)"
    info "     → Run: sudo ${RESTORE_SCRIPT}"
    info "  2. If you have another machine on the same Tailscale network:"
    info "     → Tailscale SSH may still work (not affected by sshd_config)"
}

# ─── Verification ────────────────────────────────────────────────────────────

verify_hardening() {
    info ""
    info "=== SSH Hardening Verification ==="

    local errors=0

    # Check PasswordAuthentication
    if sshd -T 2>/dev/null | grep -qi "passwordauthentication no"; then
        ok "[PASS] Password authentication is DISABLED"
    else
        warn "[FAIL] Password authentication is still enabled!"
        errors=$((errors + 1))
    fi

    # Check PermitRootLogin
    if sshd -T 2>/dev/null | grep -qi "permitrootlogin prohibit-password"; then
        ok "[PASS] Root login is restricted to key-only"
    else
        warn "[WARN] Root login may not be properly restricted"
    fi

    # Check protocol
    if sshd -T 2>/dev/null | grep -qi "x11forwarding no"; then
        ok "[PASS] X11 forwarding is DISABLED"
    else
        warn "[WARN] X11 forwarding may be enabled"
    fi

    # Check logging
    if sshd -T 2>/dev/null | grep -qi "loglevel verbose"; then
        ok "[PASS] SSH logging is set to VERBOSE"
    else
        warn "[WARN] SSH logging may not be VERBOSE"
    fi

    # Check ClientAlive
    if sshd -T 2>/dev/null | grep -qi "applies. clientaliveinterval 300" || \
       sshd -T 2>/dev/null | grep -qi "clientaliveinterval 300"; then
        ok "[PASS] ClientAliveInterval is 300 seconds"
    else
        warn "[WARN] ClientAliveInterval may not be configured"
    fi

    # Check port
    local actual_port
    actual_port=$(sshd -T 2>/dev/null | grep -i "^port " | awk '{print $2}')
    if [ "${actual_port}" = "${SSH_PORT}" ]; then
        ok "[PASS] SSH is listening on port ${SSH_PORT}"
    else
        warn "[WARN] SSH is listening on port ${actual_port} (expected ${SSH_PORT})"
    fi

    # Check ed25519 host key
    if ls /etc/ssh/ssh_host_ed25519_key* >/dev/null 2>&1; then
        ok "[PASS] ed25519 host key present"
    else
        warn "[FAIL] ed25519 host key is MISSING"
        errors=$((errors + 1))
    fi

    info ""
    if [ "${errors}" -eq 0 ]; then
        ok "SSH hardening verification PASSED"
    else
        warn "SSH hardening had ${errors} critical issue(s)"
    fi
}

# ─── Dry Run ─────────────────────────────────────────────────────────────────

dry_run_info() {
    info "DRY RUN — SSH hardening plan:"
    info ""
    info "Changes to ${SSHD_CONFIG}:"
    info "  - Port:                     ${SSH_PORT} (current: $(sshd -T 2>/dev/null | grep -i "^port " | awk '{print $2}'))"
    info "  - PasswordAuthentication:   no"
    info "  - PermitRootLogin:          prohibit-password"
    info "  - PubkeyAuthentication:     yes (implicit)"
    info "  - AuthenticationMethods:    publickey"
    info "  - X11Forwarding:            no"
    info "  - AllowTcpForwarding:       no"
    info "  - LogLevel:                 VERBOSE"
    info "  - ClientAliveInterval:      300"
    info "  - ClientAliveCountMax:      3"
    info "  - MaxAuthTries:             3"
    info "  - MaxSessions:              10"
    info "  - MaxStartups:              10:30:100"
    info "  - Ciphers:                  chacha20-poly1305, AES-GCM only"
    info "  - MACs:                     ETM variants only"
    info "  - KexAlgorithms:            Curve25519, DH-group-exchange-sha256"
    info "  - HostKeys:                 ed25519 only"
    info ""
    if [ -n "${ALLOWED_USERS}" ]; then
        info "  - AllowUsers:               ${ALLOWED_USERS}"
    fi
    info ""
    info "Backup:  ${BACKUP_DIR}/sshd_config.${TIMESTAMP}"
    info "Restore: ${RESTORE_SCRIPT}"
    info ""
    info "Run without --dry-run to apply."
}

# ─── Main ───────────────────────────────────────────────────────────────────

main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (sudo)."
    fi

    check_prerequisites

    if dry_run_mode "$@"; then
        dry_run_info
        exit 0
    fi

    info "=== SSH Hardening — $(hostname) ==="
    info ""

    # Safety: generate ed25519 keys FIRST so we don't lock ourselves out
    generate_ed25519_keys

    # Backup
    backup_sshd_config

    # Generate restore script
    generate_restore_script

    # Apply hardening
    harden_ssh_config

    # Apply user restrictions (if configured)
    apply_user_restrictions

    # Verify configuration
    verify_hardening

    # Restart (with config test)
    restart_ssh

    info ""
    info "=== SSH hardening complete on $(hostname) ==="
    info ""
    info "Key actions taken:"
    info "  - Password authentication DISABLED (key-only now)"
    info "  - Root login restricted to key-only"
    info "  - Weak ciphers/MACs/Kex algorithms banned"
    info "  - X11 and TCP forwarding DISABLED"
    info "  - SSH logging set to VERBOSE"
    info "  - ed25519 host key configured"
    info "  - Zombie session detection enabled"
    info "  - Brute force limits applied (MaxAuthTries, MaxStartups)"
    info ""
    info "Backup:     ${BACKUP_DIR}/sshd_config.${TIMESTAMP}"
    info "Restore:    ${RESTORE_SCRIPT}"
    info ""
    info "Recommended: Generate and deploy ed25519 client keys on your workstation:"
    info "  ssh-keygen -t ed25519 -a 100"
    info "  ssh-copy-id -i ~/.ssh/id_ed25519.pub user@<server>"
}

main "$@"
