#!/usr/bin/env bash
# =============================================================================
# Wheeler Enterprise — SSH Hardening Script
# =============================================================================
# Applies enterprise SSH security baseline. Non-destructive — backs up
# existing sshd_config before modifying.
#
# Usage: bash 03-ssh-hardening.sh [--apply] [--dry-run]
# =============================================================================
set -euo pipefail

ACTION="${1:---dry-run}"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_D="/etc/ssh/sshd_config.d"
BACKUP_DIR="/root/infrastructure/backups/ssh/$(date +%Y%m%d-%H%M%S)"
WHEELER_CONF="$SSHD_CONFIG_D/99-wheeler-enterprise.conf"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }

generate_sshd_config() {
    cat <<'SSHDCONF'
# =============================================================================
# Wheeler Enterprise SSH Hardening
# File: /etc/ssh/sshd_config.d/99-wheeler-enterprise.conf
# =============================================================================

# ── Protocol & Crypto ───────────────────────────────────────────────────
# Only SSH Protocol 2 (Protocol 1 has known vulnerabilities)
Protocol 2

# Strong ciphers only — no CBC, no SHA1, no weak ECDH
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com

# Strong MACs only — SHA2-512 and SHA2-256, no MD5, no SHA1
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Strong KEX algorithms — no diffie-hellman-group1-sha1, no weak curves
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512

# Host keys: ED25519 preferred, RSA 4096 fallback
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# ── Authentication ──────────────────────────────────────────────────────
# Disable root password login — key-based only
PermitRootLogin prohibit-password

# Disable password authentication entirely — keys only
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no

# Disable empty passwords
PermitEmptyPasswords no

# Maximum authentication attempts before disconnect
MaxAuthTries 3

# Maximum concurrent unauthenticated connections (throttle brute-force)
MaxStartups 10:30:100

# Login grace time — disconnect if not authenticated within 30s
LoginGraceTime 30

# ── User Access Control ─────────────────────────────────────────────────
# Only allow specific users (configure per server)
# AllowUsers root ansible-deploy monitoring-agent

# Only allow specific groups
# AllowGroups ssh-users wheel

# Disable .rhosts and .shosts (legacy trust mechanisms)
IgnoreRhosts yes
HostbasedAuthentication no

# ── Session Hardening ───────────────────────────────────────────────────
# Disable TCP forwarding (prevents SSH tunneling)
AllowTcpForwarding no

# Disable X11 forwarding (not needed on servers)
X11Forwarding no

# Disable agent forwarding (prevents key hijacking)
AllowAgentForwarding no

# Disable stream-local forwarding
AllowStreamLocalForwarding no

# Disable gateway ports
GatewayPorts no

# Disable tunnel devices
PermitTunnel no

# ── Connection Hardening ────────────────────────────────────────────────
# Client alive interval — detect dead connections
ClientAliveInterval 300
ClientAliveCountMax 2

# TCP keepalive
TCPKeepAlive yes

# Maximum sessions per connection
MaxSessions 10

# ── Logging ─────────────────────────────────────────────────────────────
# Verbose logging for fail2ban integration
LogLevel VERBOSE

# ── SFTP ────────────────────────────────────────────────────────────────
# Use internal-sftp for better security and performance
Subsystem sftp internal-sftp

# ── Host Certificate Trust (optional, for Tailscale SSH) ─────────────────
# TrustUserCAKeys /etc/ssh/tailscale_user_ca.pub
SSHDCONF
}

if [ "$ACTION" = "--help" ] || [ "$ACTION" = "-h" ]; then
    echo "Usage: $(basename "$0") [--apply] [--dry-run]"
    echo ""
    echo "  --dry-run  Print config only, do not apply (default)"
    echo "  --apply    Apply hardening to /etc/ssh/sshd_config.d/"
    exit 0
fi

# Always show what we'd deploy
echo "=== Wheeler Enterprise SSH Hardening ==="
echo ""
generate_sshd_config

if [ "$ACTION" = "--apply" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        warn "Must be root. Re-run with sudo."
        exit 1
    fi

    log "Backing up current sshd config to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp -a "$SSHD_CONFIG" "$BACKUP_DIR/" 2>/dev/null || true
    cp -a "$SSHD_CONFIG_D" "$BACKUP_DIR/" 2>/dev/null || true

    log "Writing $WHEELER_CONF"
    mkdir -p "$SSHD_CONFIG_D"
    generate_sshd_config > "$WHEELER_CONF"
    chmod 644 "$WHEELER_CONF"

    log "Validating sshd config..."
    if sshd -t; then
        log "Config valid. Restart sshd to apply."
        log "Run: systemctl restart sshd"
        log ""
        log "!!! WARNING: Keep an active SSH session open when restarting sshd !!!"
        log "!!! A broken sshd config will lock you out !!!"
    else
        warn "SSHD config validation FAILED. Restoring backup."
        cp "$BACKUP_DIR/sshd_config" "$SSHD_CONFIG" 2>/dev/null || true
        rm -f "$WHEELER_CONF"
        exit 1
    fi
else
    echo ""
    echo ">>> Dry run. To apply: bash $(basename "$0") --apply"
fi
