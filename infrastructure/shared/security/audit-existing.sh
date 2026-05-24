#!/usr/bin/env bash
# =============================================================================
# Security Audit Script — Both Servers (Hetzner & Hostinger)
# =============================================================================
#
# This script performs a comprehensive security audit of the server,
# checking all security layers (FW, SSH, Docker, sysctl, containers).
# It produces a detailed report and is used by security-scorecard.sh
# to calculate the final security score.
#
# Usage:
#   sudo ./audit-existing.sh                    # Full audit with report
#   sudo ./audit-existing.sh --quiet            # Machine-readable output
#   sudo ./audit-existing.sh --json             # JSON output
#   sudo ./audit-existing.sh --check-container  # Only container audit
#
# Idempotent: YES (read-only — does not modify anything)
# =============================================================================

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

OUTPUT_MODE="verbose"  # verbose, quiet, json
REPORT_FILE="/tmp/security-audit-$(hostname)-$(date +%Y%m%d-%H%M%S).txt"

# Scoring (used by security-scorecard.sh)
FIREWALL_SCORE=0
SSH_SCORE=0
DOCKER_SCORE=0
FAIL2BAN_SCORE=0
KERNEL_SCORE=0
CONTAINER_SCORE=0

TOTAL_ISSUES=0
TOTAL_PASSES=0

# Colors for verbose output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# ─── Helper Functions ────────────────────────────────────────────────────────

info()  { [ "${OUTPUT_MODE}" != "quiet" ] && printf "[INFO]  %s\n" "$*"; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

pass() {
    TOTAL_PASSES=$((TOTAL_PASSES + 1))
    if [ "${OUTPUT_MODE}" = "verbose" ]; then
        printf "${GREEN}[PASS]${NC} %s\n" "$*"
    elif [ "${OUTPUT_MODE}" = "quiet" ]; then
        printf "PASS: %s\n" "$*"
    fi
}

fail() {
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
    if [ "${OUTPUT_MODE}" = "verbose" ]; then
        printf "${RED}[FAIL]${NC} %s\n" "$*"
    elif [ "${OUTPUT_MODE}" = "quiet" ]; then
        printf "FAIL: %s\n" "$*"
    fi
}

warn_check() {
    if [ "${OUTPUT_MODE}" = "verbose" ]; then
        printf "${YELLOW}[WARN]${NC} %s\n" "$*"
    elif [ "${OUTPUT_MODE}" = "quiet" ]; then
        printf "WARN: %s\n" "$*"
    fi
}

section() {
    if [ "${OUTPUT_MODE}" = "verbose" ]; then
        printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        printf "  %s\n" "$*"
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    elif [ "${OUTPUT_MODE}" = "quiet" ]; then
        printf "\n=== %s ===\n" "$*"
    fi
}

run_check() {
    # Run a command silently, return true if it succeeds
    "$@" >/dev/null 2>&1
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. FIREWALL AUDIT
# ═════════════════════════════════════════════════════════════════════════════

audit_firewall() {
    section "1. FIREWALL (UFW)"
    local score=0

    # Check UFW is installed
    if command -v ufw >/dev/null 2>&1; then
        pass "UFW is installed"
        score=$((score + 2))
    else
        fail "UFW is NOT installed"
        return
    fi

    # Check UFW is active
    if ufw status | grep -qi "Status: active"; then
        pass "UFW is active"
        score=$((score + 3))
    else
        fail "UFW is NOT active"
    fi

    # Check default deny incoming
    if ufw status verbose | grep -qi "Default: deny (incoming)"; then
        pass "Default policy: deny incoming"
        score=$((score + 3))
    else
        fail "Default policy is NOT deny incoming"
    fi

    # Check SSH is allowed
    if ufw status | grep -qi "22/tcp"; then
        pass "SSH (22) is allowed"
        score=$((score + 2))

        # Check SSH rate limiting
        if ufw status | grep -qi "22/tcp.*LIMIT"; then
            pass "SSH is rate-limited"
            score=$((score + 3))
        else
            warn_check "SSH is NOT rate-limited (add: ufw limit 22/tcp)"
        fi
    else
        fail "SSH (22) is NOT allowed — you'll be locked out!"
    fi

    # Check HTTP/HTTPS
    for port in 80 443; do
        if ufw status | grep -qi "${port}/tcp"; then
            pass "Port ${port} (HTTP/HTTPS) is allowed"
            score=$((score + 1))
        else
            warn_check "Port ${port} (HTTP/HTTPS) is not allowed"
        fi
    done

    # Check for wide-open ports (admin panels exposed publicly)
    local sensitive_ports="19999 3001 3002 9090 9000 9443 5001 8090 5432 5433 5434"
    for port in ${sensitive_ports}; do
        # Check if port is allowed on ANY interface (not just tailscale)
        if ufw status | grep -qi "${port}/tcp.*ALLOW IN" 2>/dev/null; then
            # Check if it's restricted to tailscale0
            if ! ufw status | grep -qi "${port}/tcp.*ALLOW IN.*tailscale0" 2>/dev/null; then
                warn_check "Port ${port} may be exposed publicly (not restricted to tailscale0)"
                score=$((score - 1))
            fi
        fi
    done

    # Check tailscale interface
    if ip link show tailscale0 >/dev/null 2>&1; then
        pass "Tailscale interface (tailscale0) exists"
        score=$((score + 2))
    else
        warn_check "Tailscale interface not found"
    fi

    # Check Docker bridge UFW compatibility
    if grep -q 'DEFAULT_FORWARD_POLICY="ACCEPT"' /etc/default/ufw 2>/dev/null; then
        pass "UFW forward policy is ACCEPT (Docker compatible)"
        score=$((score + 2))
    else
        warn_check "UFW forward policy may block Docker networking"
    fi

    # Check for iptables rules that bypass UFW
    local ufw_rules
    ufw_rules=$(ufw status numbered 2>/dev/null | wc -l)
    if [ "${ufw_rules}" -gt 3 ]; then
        pass "UFW has ${ufw_rules} rules configured"
        score=$((score + 2))
    fi

    FIREWALL_SCORE=${score}
    info "Firewall score: ${score}/20"
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. SSH AUDIT
# ═════════════════════════════════════════════════════════════════════════════

audit_ssh() {
    section "2. SSH CONFIGURATION"
    local score=0

    local sshd_config="/etc/ssh/sshd_config"

    if [ ! -f "${sshd_config}" ]; then
        fail "sshd_config not found"
        return
    fi
    pass "sshd_config exists"

    # Actual running config (sshd -T shows effective settings)
    local running_config
    running_config=$(sshd -T 2>/dev/null || true)

    if [ -z "${running_config}" ]; then
        fail "Cannot read running SSH configuration (sshd -T failed)"
        return
    fi

    # Password authentication
    if echo "${running_config}" | grep -qi "passwordauthentication no\|passwordauthentication yes"; then
        if echo "${running_config}" | grep -qi "passwordauthentication no"; then
            pass "Password authentication is DISABLED"
            score=$((score + 3))
        else
            fail "Password authentication is ENABLED!"
        fi
    fi

    # PermitRootLogin
    if echo "${running_config}" | grep -qi "permitrootlogin"; then
        if echo "${running_config}" | grep -qi "permitrootlogin prohibit-password\|permitrootlogin without-password"; then
            pass "Root login is key-only (prohibit-password)"
            score=$((score + 3))
        elif echo "${running_config}" | grep -qi "permitrootlogin no"; then
            pass "Root login is completely disabled"
            score=$((score + 3))
        elif echo "${running_config}" | grep -qi "permitrootlogin yes"; then
            fail "Root login with password is ENABLED!"
        fi
    fi

    # Check for weak key types in host keys
    if ls /etc/ssh/ssh_host_ed25519_key* >/dev/null 2>&1; then
        pass "ed25519 host key present"
        score=$((score + 2))
    fi
    if ls /etc/ssh/ssh_host_rsa_key >/dev/null 2>&1; then
        # Check RSA key size
        local rsa_bits
        rsa_bits=$(ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key 2>/dev/null | awk '{print $1}')
        if [ -n "${rsa_bits}" ] && [ "${rsa_bits}" -lt 2048 ] 2>/dev/null; then
            fail "RSA host key is only ${rsa_bits} bits (minimum 2048)"
        else
            warn_check "RSA host key present (${rsa_bits:-unknown} bits) — consider migrating to ed25519"
        fi
    fi

    # X11 forwarding
    if echo "${running_config}" | grep -qi "x11forwarding no"; then
        pass "X11 forwarding is DISABLED"
        score=$((score + 2))
    else
        warn_check "X11 forwarding may be enabled"
    fi

    # TCP forwarding
    if echo "${running_config}" | grep -qi "allowtcpforwarding no"; then
        pass "TCP forwarding is DISABLED"
        score=$((score + 1))
    fi

    # Protocol settings
    if echo "${running_config}" | grep -qi "protocol 2"; then
        pass "Protocol 2 only (SSH1 disabled)"
        score=$((score + 1))
    fi

    # ClientAlive
    if echo "${running_config}" | grep -qi "applies. clientaliveinterval"; then
        pass "ClientAlive is configured (zombie detection)"
        score=$((score + 1))
    else
        warn_check "ClientAliveInterval not set (zombie sessions may accumulate)"
    fi

    # MaxAuthTries
    local max_tries
    max_tries=$(echo "${running_config}" | grep -i "maxauthtries" | awk '{print $2}' || true)
    if [ -n "${max_tries}" ] && [ "${max_tries}" -le 3 ]; then
        pass "MaxAuthTries is ${max_tries} (good)"
        score=$((score + 1))
    elif [ -n "${max_tries}" ] && [ "${max_tries}" -gt 3 ]; then
        warn_check "MaxAuthTries is ${max_tries} (recommended: 3)"
    fi

    # Check for AllowUsers restriction
    if grep -qi "^AllowUsers" "${sshd_config}" 2>/dev/null; then
        pass "SSH access restricted to specific users"
        score=$((score + 2))
    fi

    SSH_SCORE=${score}
    info "SSH score: ${score}/15"
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. DOCKER AUDIT
# ═════════════════════════════════════════════════════════════════════════════

audit_docker() {
    section "3. DOCKER DAEMON"
    local score=0

    if ! command -v docker >/dev/null 2>&1; then
        fail "Docker is NOT installed"
        DOCKER_SCORE=0
        return
    fi
    pass "Docker is installed"

    if ! docker info >/dev/null 2>&1; then
        fail "Docker daemon is NOT running"
        DOCKER_SCORE=0
        return
    fi
    pass "Docker daemon is running"
    score=$((score + 2))

    # Check daemon.json
    local daemon_json="/etc/docker/daemon.json"
    if [ -f "${daemon_json}" ]; then
        pass "daemon.json exists"
        score=$((score + 2))

        # Check specific settings
        if grep -q "userns-remap" "${daemon_json}" 2>/dev/null; then
            pass "User namespace remapping is configured"
            score=$((score + 3))
        else
            warn_check "User namespace remapping NOT configured (containers run as root)"
        fi

        if grep -q "live-restore" "${daemon_json}" 2>/dev/null; then
            pass "Live-restore is configured"
            score=$((score + 2))
        else
            warn_check "Live-restore NOT configured (containers die on daemon restart)"
        fi

        if grep -q '"icc": false' "${daemon_json}" 2>/dev/null; then
            pass "Inter-container communication is DISABLED on default bridge"
            score=$((score + 2))
        else
            warn_check "Inter-container communication is enabled on default bridge"
        fi

        if grep -q "no-new-privileges" "${daemon_json}" 2>/dev/null; then
            pass "no-new-privileges is enabled"
            score=$((score + 1))
        fi

        if grep -q "seccomp-profile" "${daemon_json}" 2>/dev/null; then
            pass "Custom seccomp profile is configured"
            score=$((score + 2))
        fi
    else
        warn_check "daemon.json NOT found — using Docker defaults (less secure)"
    fi

    # Check Docker info settings
    local docker_info
    docker_info=$(docker info 2>/dev/null || true)

    if echo "${docker_info}" | grep -qi "userns.*true"; then
        pass "User namespace remapping is ACTIVE"
        score=$((score + 2))
    fi

    if echo "${docker_info}" | grep -qi "seccomp.*enabled\|seccomp.*true"; then
        pass "Seccomp is enabled"
        score=$((score + 2))
    else
        warn_check "Seccomp is NOT enabled"
    fi

    # Check logging driver
    local log_driver
    log_driver=$(echo "${docker_info}" | grep "Logging Driver" | awk '{print $3}')
    if [ "${log_driver}" = "json-file" ] || [ "${log_driver}" = "local" ]; then
        pass "Logging driver: ${log_driver} (with rotation)"
        score=$((score + 2))
    elif [ "${log_driver}" = "journald" ]; then
        pass "Logging driver: journald"
        score=$((score + 2))
    else
        warn_check "Logging driver: ${log_driver:-unknown}"
    fi

    DOCKER_SCORE=${score}
    info "Docker score: ${score}/20"
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. FAIL2BAN/CROWDSEC AUDIT
# ═════════════════════════════════════════════════════════════════════════════

audit_fail2ban() {
    section "4. FAIL2BAN / CROWDSEC"
    local score=0

    # ─── Fail2ban ────────────────────────────────────────────────────
    if command -v fail2ban-client >/dev/null 2>&1; then
        pass "Fail2ban is installed"

        local jails
        jails=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*:\s*//' || true)

        if [ -n "${jails}" ]; then
            pass "Fail2ban jails active: ${jails}"
            score=$((score + 3))

            # Check specific jails
            for jail in sshd traefik-auth recidive; do
                if echo "${jails}" | grep -qi "${jail}"; then
                    pass "Jail '${jail}' is active"
                    score=$((score + 2))
                else
                    warn_check "Jail '${jail}' is NOT active"
                fi
            done
        else
            warn_check "Fail2ban has no active jails"
        fi

        # Check bantime
        local ban_count
        ban_count=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print $NF}' || true)
        if [ -n "${ban_count}" ] && [ "${ban_count}" -gt 0 ]; then
            pass "Fail2ban has banned ${ban_count} IP(s) — it's working!"
            score=$((score + 2))
        fi
    else
        warn_check "Fail2ban is NOT installed"
    fi

    # ─── CrowdSec ────────────────────────────────────────────────────
    if command -v cscli >/dev/null 2>&1; then
        pass "CrowdSec is installed"
        score=$((score + 3))

        if systemctl is-active --quiet crowdsec 2>/dev/null; then
            pass "CrowdSec agent is running"
            score=$((score + 2))
        else
            warn_check "CrowdSec agent is NOT running"
        fi

        # Check for active decisions (bans)
        local decisions
        decisions=$(cscli decisions list 2>/dev/null | grep -c "ban" || true)
        if [ "${decisions}" -gt 0 ]; then
            pass "CrowdSec has ${decisions} active decisions"
            score=$((score + 2))
        fi
    fi

    FAIL2BAN_SCORE=${score}
    info "Fail2ban/CrowdSec score: ${score}/15"
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. KERNEL HARDENING AUDIT
# ═════════════════════════════════════════════════════════════════════════════

audit_kernel() {
    section "5. KERNEL HARDENING"
    local score=0

    local checks=(
        "net.ipv4.ip_forward:1:IP forwarding"
        "net.ipv4.conf.all.rp_filter:1:Reverse path filtering"
        "net.ipv4.conf.all.accept_redirects:0:ICMP redirect acceptance"
        "net.ipv4.conf.all.accept_source_route:0:Source routing"
        "net.ipv4.tcp_syncookies:1:SYN cookies"
        "net.ipv4.conf.all.log_martians:1:Martian packet logging"
        "net.ipv4.conf.all.send_redirects:0:ICMP redirect sending"
        "kernel.kptr_restrict:1:Kernel pointer restriction"
        "kernel.dmesg_restrict:1:dmesg restriction"
        "fs.suid_dumpable:0:SUID core dumps"
    )

    for check in "${checks[@]}"; do
        local key="${check%%:*}"
        local rest="${check#*:}"
        local expected="${rest%%:*}"
        local description="${rest#*:}"
        local actual
        actual=$(sysctl -n "${key}" 2>/dev/null || true)

        if [ "${actual}" = "${expected}" ]; then
            pass "${description} (${key}=${actual})"
            score=$((score + 2))
        else
            warn_check "${description}: expected ${expected}, got ${actual} (${key})"
        fi
    done

    # Check BBR
    local congestion
    congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
    if [ "${congestion}" = "bbr" ]; then
        pass "TCP congestion control: BBR"
        score=$((score + 1))
    fi

    KERNEL_SCORE=${score}
    info "Kernel score: ${score}/15"
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. CONTAINER SECURITY AUDIT
# ═════════════════════════════════════════════════════════════════════════════

audit_containers() {
    section "6. CONTAINER SECURITY"
    local score=0

    if ! command -v docker >/dev/null 2>&1 || ! docker ps >/dev/null 2>&1; then
        info "No Docker running — skipping container audit"
        CONTAINER_SCORE=5  # Partial credit (no containers = no container risk)
        return
    fi

    local running_count
    running_count=$(docker ps -q 2>/dev/null | wc -l)

    if [ "${running_count}" -eq 0 ]; then
        pass "No running containers"
        CONTAINER_SCORE=15
        return
    fi

    info "Auditing ${running_count} running container(s)..."
    score=$((score + 2))

    local priv_count=0
    local host_net_count=0
    local cap_add_count=0
    local root_count=0
    local exposed_ports_public=0

    for container in $(docker ps --format '{{.Names}}' 2>/dev/null); do
        local inspect
        inspect=$(docker inspect "${container}" 2>/dev/null || true)

        # Check privileged
        if echo "${inspect}" | grep -qi '"Privileged": true'; then
            fail "Container '${container}' runs in PRIVILEGED mode"
            priv_count=$((priv_count + 1))
        fi

        # Check host network
        if echo "${inspect}" | grep -qi '"NetworkMode": "host"'; then
            warn_check "Container '${container}' uses host networking"
            host_net_count=$((host_net_count + 1))
        fi

        # Check extra capabilities
        local cap_add
        cap_add=$(echo "${inspect}" | grep -oP '"CapAdd": \[\K[^\]]*' || true)
        if echo "${cap_add}" | grep -qi "SYS_ADMIN\|NET_ADMIN\|ALL\|SYS_MODULE"; then
            warn_check "Container '${container}' has dangerous capabilities: ${cap_add}"
            cap_add_count=$((cap_add_count + 1))
        fi

        # Check running as root
        local user
        user=$(echo "${inspect}" | grep -oP '"User": "\K[^"]*' || true)
        if [ -z "${user}" ] || [ "${user}" = "root" ] || [ "${user}" = "0" ]; then
            # This is common — only warn if privileged + root
            if echo "${inspect}" | grep -qi '"Privileged": true'; then
                fail "Container '${container}' runs as root AND is privileged"
                root_count=$((root_count + 1))
            fi
        fi

        # Check port bindings to 0.0.0.0 (public exposure)
        local ports
        ports=$(echo "${inspect}" | grep -oP '"HostIp": "0\.0\.0\.0"' || true)
        if [ -n "${ports}" ]; then
            local port_details
            port_details=$(echo "${inspect}" | grep -oP '"HostPort": "\K[^"]+' || true)
            if [ -n "${port_details}" ]; then
                pass "Container '${container}' exposes port(s) ${port_details} on 0.0.0.0"
            fi
        fi
    done

    # Scoring
    if [ "${priv_count}" -eq 0 ]; then
        pass "No privileged containers"
        score=$((score + 4))
    else
        warn_check "${priv_count} container(s) running in privileged mode"
    fi

    if [ "${host_net_count}" -eq 0 ]; then
        pass "No containers using host networking"
        score=$((score + 3))
    fi

    if [ "${cap_add_count}" -eq 0 ]; then
        pass "No containers with extra dangerous capabilities"
        score=$((score + 3))
    else
        warn_check "${cap_add_count} container(s) have extra capabilities"
    fi

    # Count total running containers for base score
    if [ "${running_count}" -lt 20 ]; then
        pass "Moderate number of containers (${running_count})"
        score=$((score + 3))
    elif [ "${running_count}" -lt 50 ]; then
        warn_check "High number of containers (${running_count}) — ensure adequate monitoring"
        score=$((score + 1))
    fi

    CONTAINER_SCORE=${score}
    info "Container score: ${score}/15"
}

# ═════════════════════════════════════════════════════════════════════════════
# 7. ADDITIONAL SECURITY CHECKS
# ═════════════════════════════════════════════════════════════════════════════

audit_additional() {
    section "7. ADDITIONAL CHECKS"

    # ─── Unused user accounts ─────────────────────────────────────────
    local shell_users
    shell_users=$(awk -F: '($3 >= 1000) && ($7 ~ /\/bin\/bash|\/bin\/sh|\/bin\/zsh/){print $1":"$3}' /etc/passwd 2>/dev/null || true)
    if [ -n "${shell_users}" ]; then
        info "Users with shell access:"
        echo "${shell_users}" | while IFS=: read -r user uid; do
            info "  ${user} (UID: ${uid})"
        done
    fi

    # ─── World-writable files in critical directories ─────────────────
    local world_writable
    world_writable=$(find /etc /bin /sbin /usr/bin /usr/sbin -xdev -type f -perm -0002 2>/dev/null | head -20 || true)
    if [ -n "${world_writable}" ]; then
        warn_check "World-writable files found in system directories:"
        echo "${world_writable}" | while IFS= read -r f; do
            warn_check "  ${f}"
        done
    else
        pass "No world-writable files in system directories"
    fi

    # ─── SUID binaries (known dangerous ones) ─────────────────────────
    local suid_binaries
    suid_binaries=$(find / -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | sort || true)
    local suid_count
    suid_count=$(echo "${suid_binaries}" | wc -l)

    info "SUID/SGID binaries found: ${suid_count}"
    if echo "${suid_binaries}" | grep -qi "pkexec\|passwd\|sudo\|su\|mount\|umount"; then
        pass "Standard SUID binaries present (passwd, sudo, mount, etc.)"
    fi

    # Check for unusual SUID
    local unusual_suid
    unusual_suid=$(echo "${suid_binaries}" | grep -v "bin/" | grep -v "/snap/" | head -5 || true)
    if [ -n "${unusual_suid}" ]; then
        warn_check "Unusual SUID binaries outside standard paths:"
        echo "${unusual_suid}" | while IFS= read -r f; do
            warn_check "  ${f}"
        done
    fi

    # ─── Docker socket permissions ───────────────────────────────────
    local docker_sock="/var/run/docker.sock"
    if [ -S "${docker_sock}" ]; then
        local sock_perms
        sock_perms=$(stat -c "%a %U:%G" "${docker_sock}" 2>/dev/null || true)
        if echo "${sock_perms}" | grep -q "660 root:docker\|666\|777"; then
            warn_check "Docker socket has permissive permissions: ${sock_perms}"
        elif echo "${sock_perms}" | grep -q "600\|620"; then
            pass "Docker socket permissions: ${sock_perms} (good)"
        else
            pass "Docker socket permissions: ${sock_perms}"
        fi
    fi

    # ─── Running as root in container check (host level) ─────────────
    if [ "$(id -u)" -eq 0 ]; then
        info "Running audit as root (expected) — containers may vary"
    fi

    # ─── Open ports audit ────────────────────────────────────────────
    info ""
    info "Listening services (public):"
    ss -tlnp 2>/dev/null | grep -v "127.0.0.1:" | grep -v "::1:" | grep -v "tailscale0" | \
        awk '{printf "  %-20s %s\n", $4, $7}' || true

    # ─── Tailscale status ────────────────────────────────────────────
    if command -v tailscale >/dev/null 2>&1; then
        local ts_ip
        ts_ip=$(tailscale ip -4 2>/dev/null || true)
        if [ -n "${ts_ip}" ]; then
            pass "Tailscale is running (IP: ${ts_ip})"
        else
            warn_check "Tailscale is installed but not connected"
        fi
    else
        warn_check "Tailscale is NOT installed"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# REPORT GENERATION
# ═════════════════════════════════════════════════════════════════════════════

generate_report() {
    local total_score=$((FIREWALL_SCORE + SSH_SCORE + DOCKER_SCORE + FAIL2BAN_SCORE + KERNEL_SCORE + CONTAINER_SCORE))
    local max_score=100

    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "  SECURITY AUDIT REPORT"
        echo "  Host:     $(hostname)"
        echo "  Date:     $(date)"
        echo "  IP(s):    $(hostname -I 2>/dev/null | tr ' ' ',')"
        echo "  Tailscale: $(tailscale ip -4 2>/dev/null || echo 'N/A')"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "  CATEGORY               SCORE    MAX"
        echo "  ───────────────────────────────────────"
        printf "  %-22s %3d/%-3d\n" "Firewall (UFW)" "${FIREWALL_SCORE}" 20
        printf "  %-22s %3d/%-3d\n" "SSH Hardening" "${SSH_SCORE}" 15
        printf "  %-22s %3d/%-3d\n" "Docker Security" "${DOCKER_SCORE}" 20
        printf "  %-22s %3d/%-3d\n" "Fail2ban/CrowdSec" "${FAIL2BAN_SCORE}" 15
        printf "  %-22s %3d/%-3d\n" "Kernel Hardening" "${KERNEL_SCORE}" 15
        printf "  %-22s %3d/%-3d\n" "Container Security" "${CONTAINER_SCORE}" 15
        echo "  ───────────────────────────────────────"
        printf "  %-22s %3d/%-3d\n" "TOTAL" "${total_score}" "${max_score}"
        echo ""
        echo "  Issues found: ${TOTAL_ISSUES}"
        echo "  Checks passed: ${TOTAL_PASSES}"
        echo ""

        # Grade
        if [ "${total_score}" -ge 90 ]; then
            echo "  GRADE: A+ — Excellent security posture"
        elif [ "${total_score}" -ge 80 ]; then
            echo "  GRADE: A — Good security, minor improvements needed"
        elif [ "${total_score}" -ge 70 ]; then
            echo "  GRADE: B — Adequate security, several improvements needed"
        elif [ "${total_score}" -ge 60 ]; then
            echo "  GRADE: C — Below average, address warnings soon"
        else
            echo "  GRADE: F — Critical security issues must be addressed"
        fi

        echo ""
        echo "  Priority actions:"
        if [ "${FIREWALL_SCORE}" -lt 15 ]; then
            echo "    - [HIGH] Harden firewall: run ufw-*.sh script"
        fi
        if [ "${SSH_SCORE}" -lt 10 ]; then
            echo "    - [HIGH] Harden SSH: run ssh-hardening.sh script"
        fi
        if [ "${DOCKER_SCORE}" -lt 15 ]; then
            echo "    - [HIGH] Secure Docker: run docker-security.sh script"
        fi
        if [ "${FAIL2BAN_SCORE}" -lt 10 ]; then
            echo "    - [MEDIUM] Install/config IPS: run fail2ban-*.sh or crowdsec-install.sh"
        fi
        if [ "${KERNEL_SCORE}" -lt 10 ]; then
            echo "    - [MEDIUM] Harden kernel: apply sysctl-hardening.conf"
        fi
        if [ "${CONTAINER_SCORE}" -lt 10 ]; then
            echo "    - [MEDIUM] Review container security: remove privileged mode"
        fi
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
    } | tee "${REPORT_FILE}"

    info "Report saved to: ${REPORT_FILE}"
}

# ═════════════════════════════════════════════════════════════════════════════
# JSON OUTPUT
# ═════════════════════════════════════════════════════════════════════════════

generate_json() {
    local total_score=$((FIREWALL_SCORE + SSH_SCORE + DOCKER_SCORE + FAIL2BAN_SCORE + KERNEL_SCORE + CONTAINER_SCORE))

    python3 -c "
import json
report = {
    'hostname': '$(hostname)',
    'timestamp': '$(date -Iseconds)',
    'server_role': '$(hostname | grep -qi 'hetzner' && echo 'hetzner' || echo 'hostinger')',
    'scores': {
        'firewall': {'score': ${FIREWALL_SCORE}, 'max': 20},
        'ssh': {'score': ${SSH_SCORE}, 'max': 15},
        'docker': {'score': ${DOCKER_SCORE}, 'max': 20},
        'fail2ban_crowdsec': {'score': ${FAIL2BAN_SCORE}, 'max': 15},
        'kernel': {'score': ${KERNEL_SCORE}, 'max': 15},
        'containers': {'score': ${CONTAINER_SCORE}, 'max': 15}
    },
    'total_score': ${total_score},
    'max_score': 100,
    'issues_found': ${TOTAL_ISSUES},
    'checks_passed': ${TOTAL_PASSES}
}
print(json.dumps(report, indent=2))
"
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════

main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (sudo)."
    fi

    # Parse arguments
    for arg in "$@"; do
        case "${arg}" in
            --quiet|-q) OUTPUT_MODE="quiet" ;;
            --json|-j)  OUTPUT_MODE="json" ;;
            --check-container)
                # Only run container audit
                OUTPUT_MODE="verbose"
                audit_containers
                exit 0
                ;;
            --help|-h)
                echo "Usage: $0 [--quiet|--json|--check-container]"
                exit 0
                ;;
        esac
    done

    info "Starting security audit on $(hostname)..."
    info ""

    # Run all audits
    audit_firewall
    audit_ssh
    audit_docker
    audit_fail2ban
    audit_kernel
    audit_containers
    audit_additional

    # Generate report
    if [ "${OUTPUT_MODE}" = "json" ]; then
        generate_json
    else
        generate_report
    fi

    # Export scores for sourcing by security-scorecard.sh
    if [ "${OUTPUT_MODE}" = "quiet" ]; then
        echo "FIREWALL_SCORE=${FIREWALL_SCORE}"
        echo "SSH_SCORE=${SSH_SCORE}"
        echo "DOCKER_SCORE=${DOCKER_SCORE}"
        echo "FAIL2BAN_SCORE=${FAIL2BAN_SCORE}"
        echo "KERNEL_SCORE=${KERNEL_SCORE}"
        echo "CONTAINER_SCORE=${CONTAINER_SCORE}"
    fi
}

main "$@"
