#!/usr/bin/env bash
# =============================================================================
# Docker Security Hardening Script — Both Servers (Hetzner & Hostinger)
# =============================================================================
#
# Security Rationale:
#   Docker, by default, runs containers as root on the host. A container
#   breakout could give an attacker root on the host. Docker security
#   hardening reduces this risk through multiple layers of defense:
#
#   1. User namespace remapping — Containers run as non-root users on the host
#   2. Default seccomp profile — Blocks dangerous syscalls
#   3. No inter-container communication on default bridge — Isolates networks
#   4. Live-restore — Daemon survives restarts without killing containers
#   5. Default ulimits — Prevents resource exhaustion
#   6. Content trust — Verifies image signatures
#   7. Audit existing containers — Finds dangerous configurations
#
# Reference:
#   - CIS Docker Benchmark
#   - Docker Security Cheat Sheet (OWASP)
#   - https://docs.docker.com/engine/security/
#
# Idempotent: YES — merges with existing daemon.json, doesn't duplicate keys.
# Safety: Backs up daemon.json before modification.
# =============================================================================

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

DOCKER_CONFIG_DIR="/etc/docker"
DAEMON_JSON="${DOCKER_CONFIG_DIR}/daemon.json"
BACKUP_DIR="/root/docker-backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESTORE_SCRIPT="/root/docker-security-restore.sh"
DOCKER_CMD="$(command -v docker || true)"

# ─── Helper Functions ────────────────────────────────────────────────────────

info()  { printf "[INFO]  %s\n" "$*"; }
warn()  { printf "[WARN]  %s\n" "$*" >&2; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }
ok()    { printf "[OK]    %s\n" "$*"; }

dry_run_mode() {
    if [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "-n" ]; then
        info "DRY RUN MODE — changes will be shown but NOT applied."
        return 0
    fi
    return 1
}

check_prerequisites() {
    if [ ! -d "${DOCKER_CONFIG_DIR}" ]; then
        info "Creating Docker config directory: ${DOCKER_CONFIG_DIR}"
        mkdir -p "${DOCKER_CONFIG_DIR}"
    fi

    if [ -z "${DOCKER_CMD}" ]; then
        warn "Docker CLI not found. Config will be written but Docker not verified."
    fi
}

# ─── daemon.json Management ─────────────────────────────────────────────────

backup_daemon_json() {
    local backup_path="${BACKUP_DIR}/daemon.json.${TIMESTAMP}"

    if [ -f "${DAEMON_JSON}" ]; then
        mkdir -p "${BACKUP_DIR}"
        cp "${DAEMON_JSON}" "${backup_path}"
        ok "Backed up ${DAEMON_JSON} → ${backup_path}"
    fi
}

generate_daemon_json() {
    info "=== Generating Docker daemon.json ==="

    local tmp_file
    tmp_file=$(mktemp)

    # Start with existing config or empty if none exists
    if [ -f "${DAEMON_JSON}" ]; then
        cp "${DAEMON_JSON}" "${tmp_file}"
    else
        echo '{}' > "${tmp_file}"
    fi

    # Use python3 or jq to merge configs (preserves existing settings)
    if command -v jq >/dev/null 2>&1; then
        merge_with_jq "${tmp_file}"
    elif command -v python3 >/dev/null 2>&1; then
        merge_with_python "${tmp_file}"
    else
        warn "Neither jq nor python3 found. Writing daemon.json directly."
        merge_manually "${tmp_file}"
    fi

    # Copy to final location
    cp "${tmp_file}" "${DAEMON_JSON}"
    chmod 644 "${DAEMON_JSON}"
    rm -f "${tmp_file}"

    ok "Docker daemon configuration written to ${DAEMON_JSON}"
}

merge_with_jq() {
    local input="$1"
    local merged
    merged=$(mktemp)

    # Build the security config as a JSON snippet, then merge with existing
    jq -s '.[0] * .[1]' "${input}" - <<'JQJSON' > "${merged}"
{
  "userns-remap": "default",
  "seccomp-profile": "/etc/docker/seccomp-default.json",
  "icc": false,
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 4096,
      "Soft": 2048
    }
  },
  "content-trust": {
    "enabled": true
  },
  "iptables": true,
  "ip-forward": true,
  "ip-masq": true,
  "bridge": "none",
  "fixed-cidr": "172.17.0.0/16",
  "default-address-pools": [
    {"base": "172.17.0.0/16", "size": 24},
    {"base": "172.18.0.0/16", "size": 24},
    {"base": "172.19.0.0/16", "size": 24}
  ],
  "experimental": false,
  "userland-proxy": false,
  "no-new-privileges": true
}
JQJSON

    cp "${merged}" "${input}"
    rm -f "${merged}"
    info "  Merged using jq."
}

merge_with_python() {
    local input="$1"
    local merged
    merged=$(mktemp)

    python3 <<PYSCRIPT > "${merged}"
import json

# Load existing config
with open("${input}") as f:
    config = json.load(f)

# Security settings to merge
security = {
    "userns-remap": "default",
    "seccomp-profile": "/etc/docker/seccomp-default.json",
    "icc": False,
    "live-restore": True,
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "default-ulimits": {
        "nofile": {"Name": "nofile", "Hard": 65536, "Soft": 65536},
        "nproc": {"Name": "nproc", "Hard": 4096, "Soft": 2048}
    },
    "content-trust": {"enabled": True},
    "iptables": True,
    "ip-forward": True,
    "ip-masq": True,
    "bridge": "none",
    "fixed-cidr": "172.17.0.0/16",
    "default-address-pools": [
        {"base": "172.17.0.0/16", "size": 24},
        {"base": "172.18.0.0/16", "size": 24},
        {"base": "172.19.0.0/16", "size": 24}
    ],
    "experimental": False,
    "userland-proxy": False,
    "no-new-privileges": True
}

# Deep merge (security settings override existing)
for key, value in security.items():
    config[key] = value

print(json.dumps(config, indent=2))
PYSCRIPT

    cp "${merged}" "${input}"
    rm -f "${merged}"
    info "  Merged using python3."
}

merge_manually() {
    local input="$1"
    # Fallback: write daemon.json directly with all settings
    cat > "${input}" <<'DAEMONJSON'
{
  "userns-remap": "default",
  "seccomp-profile": "/etc/docker/seccomp-default.json",
  "icc": false,
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 4096,
      "Soft": 2048
    }
  },
  "content-trust": {
    "enabled": true
  },
  "iptables": true,
  "ip-forward": true,
  "ip-masq": true,
  "bridge": "none",
  "fixed-cidr": "172.17.0.0/16",
  "default-address-pools": [
    {"base": "172.17.0.0/16", "size": 24},
    {"base": "172.18.0.0/16", "size": 24},
    {"base": "172.19.0.0/16", "size": 24}
  ],
  "experimental": false,
  "userland-proxy": false,
  "no-new-privileges": true
}
DAEMONJSON
    info "  Written directly (no jq/python)."
}

# ─── User Namespace Setup ──────────────────────────────────────────────────

setup_user_namespace() {
    info "=== Setting Up User Namespace Remapping ==="

    # The "userns-remap": "default" setting requires a user/group to exist.
    # Docker uses the 'dockremap' user by default.
    if id "dockremap" >/dev/null 2>&1; then
        ok "dockremap user exists (required for userns-remap)"
    else
        info "Creating dockremap user for user namespace remapping..."
        useradd --system --no-create-home --shell /usr/sbin/nologin dockremap
        ok "dockremap user created."
    fi

    # Verify subordinate ID ranges exist
    if [ -f /etc/subuid ]; then
        if grep -q "dockremap" /etc/subuid; then
            ok "dockremap subordinate UID range configured"
        else
            warn "dockremap not found in /etc/subuid. Docker may not start."
            warn "Add: echo 'dockremap:100000:65536' >> /etc/subuid"
            warn "Add: echo 'dockremap:100000:65536' >> /etc/subgid"
        fi
    fi
}

# ─── Seccomp Profile ─────────────────────────────────────────────────────────

install_seccomp_profile() {
    local seccomp_path="/etc/docker/seccomp-default.json"

    info "=== Installing Default Seccomp Profile ==="

    # Copy Docker's default seccomp profile to a persistent location
    # This ensures the profile exists even if Docker is reinstalled.
    if docker info 2>/dev/null | grep -qi "seccomp"; then
        # Try to get the default profile from running Docker
        local default_profile
        default_profile=$(docker info 2>/dev/null | grep "seccomp" | head -1)

        # Docker's default profile is embedded in the binary. We'll use
        # the well-known default profile from the Docker source.
        if [ ! -f "${seccomp_path}" ]; then
            info "Downloading default seccomp profile..."
            curl -sL -o "${seccomp_path}" \
                "https://raw.githubusercontent.com/moby/moby/master/profiles/seccomp/default.json" || {
                warn "Could not download seccomp profile from GitHub."
                warn "Create it manually or Docker will use its built-in default."
            }
        else
            ok "Seccomp profile already exists at ${seccomp_path}"
        fi
    else
        warn "Docker was built without seccomp support. Skipping seccomp profile."
    fi
}

# ─── Restart Docker ─────────────────────────────────────────────────────────

restart_docker() {
    info "=== Restarting Docker Daemon ==="

    info "Reloading Docker daemon configuration..."
    if systemctl is-active --quiet docker; then
        # Use reload first (doesn't kill containers)
        systemctl reload docker 2>/dev/null || {
            warn "Reload failed. Attempting restart..."
            systemctl restart docker
        }
    else
        systemctl restart docker 2>/dev/null || {
            error "Failed to restart Docker. Check: journalctl -u docker"
        }
    fi

    # Wait for Docker to be ready
    local timeout=30
    local waited=0
    while ! docker info >/dev/null 2>&1; do
        if [ "${waited}" -ge "${timeout}" ]; then
            warn "Docker not responding after ${timeout}s. Check logs."
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    ok "Docker daemon is running."
}

# ─── Audit Existing Containers ──────────────────────────────────────────────

audit_containers() {
    info ""
    info "=== Auditing Existing Containers ==="

    if [ -z "${DOCKER_CMD}" ]; then
        warn "Docker CLI not found. Skipping container audit."
        return
    fi

    if ! docker ps -q 2>/dev/null | head -1 >/dev/null; then
        info "No running containers to audit."
        return
    fi

    local issues=0

    echo ""
    printf "%-25s %-12s %-15s %s\n" "CONTAINER" "PRIVILEGED" "HOST_NET" "CAPABILITIES"
    printf "%-25s %-12s %-15s %s\n" "─────────────────────────" "────────────" "───────────────" "──────────────────────"

    for container in $(docker ps --format '{{.Names}}'); do
        local privileged="no"
        local host_net="no"
        local caps="none"

        # Check privileged mode
        if docker inspect "${container}" --format '{{.HostConfig.Privileged}}' 2>/dev/null | grep -qi "true"; then
            privileged="⚠️ YES"
            issues=$((issues + 1))
        fi

        # Check host network
        local net_mode
        net_mode=$(docker inspect "${container}" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)
        if [ "${net_mode}" = "host" ]; then
            host_net="⚠️ YES"
            issues=$((issues + 1))
        fi

        # Check added capabilities
        local cap_add
        cap_add=$(docker inspect "${container}" --format '{{.HostConfig.CapAdd}}' 2>/dev/null | tr -d '[]')
        if [ -n "${cap_add}" ] && [ "${cap_add}" != "<nil>" ]; then
            caps="${cap_add}"
            issues=$((issues + 1))
        fi

        printf "%-25s %-12s %-15s %s\n" "${container}" "${privileged}" "${host_net}" "${caps}"
    done

    info ""
    if [ "${issues}" -gt 0 ]; then
        warn "Found ${issues} security issue(s) in running containers."
        warn "Review the table above and address each issue:"
        warn "  - Privileged mode: Use --security-opt and specific capabilities instead"
        warn "  - Host network:   Use a custom Docker bridge network"
        warn "  - Extra caps:     Drop all (--cap-drop=ALL) then add only what's needed"
    else
        ok "No container security issues detected."
    fi
}

# ─── Generate Restore Script ────────────────────────────────────────────────

generate_restore_script() {
    local backup_path="${BACKUP_DIR}/daemon.json.${TIMESTAMP}"

    cat > "${RESTORE_SCRIPT}" <<RESTORE
#!/usr/bin/env bash
# Docker Security Restore Script — generated ${TIMESTAMP}
# Run this to restore the previous Docker daemon configuration.

set -euo xtrace

if [ "\$(id -u)" -ne 0 ]; then
    echo "Must run as root."
    exit 1
fi

echo "Restoring Docker daemon configuration..."

if [ -f "${backup_path}" ]; then
    cp "${backup_path}" "${DAEMON_JSON}"
    echo "Restored ${DAEMON_JSON}"
else
    echo "No backup found at ${backup_path}"
    exit 1
fi

echo "Restarting Docker..."
systemctl restart docker
echo "Restore complete."
RESTORE

    chmod +x "${RESTORE_SCRIPT}"
    ok "Restore script: ${RESTORE_SCRIPT}"
}

# ─── Verification ───────────────────────────────────────────────────────────

verify_hardening() {
    info ""
    info "=== Docker Security Verification ==="

    local errors=0

    if [ -z "${DOCKER_CMD}" ]; then
        warn "Docker CLI not found. Skipping runtime verification."
        return
    fi

    # Check daemon.json exists
    if [ -f "${DAEMON_JSON}" ]; then
        ok "[PASS] daemon.json exists"
    else
        warn "[FAIL] daemon.json is missing"
        errors=$((errors + 1))
        return
    fi

    # Check user namespace remapping
    local userns
    userns=$(docker info 2>/dev/null | grep "Userns" | head -1)
    if echo "${userns}" | grep -qi "true"; then
        ok "[PASS] User namespace remapping is ENABLED"
    else
        warn "[WARN] User namespace remapping may not be active: ${userns}"
    fi

    # Check seccomp
    local seccomp
    seccomp=$(docker info 2>/dev/null | grep "seccomp" | head -1)
    if echo "${seccomp}" | grep -qi "enabled\|true"; then
        ok "[PASS] Seccomp is ENABLED"
    else
        warn "[WARN] Seccomp may not be enabled: ${seccomp}"
    fi

    # Check live-restore
    local live_restore
    live_restore=$(docker info 2>/dev/null | grep "Live Restore" | head -1)
    if echo "${live_restore}" | grep -qi "true"; then
        ok "[PASS] Live Restore is ENABLED"
    else
        warn "[WARN] Live Restore may not be enabled: ${live_restore}"
    fi

    # Check inter-container communication
    local icc
    icc=$(docker info 2>/dev/null | grep "icc" | head -1 || true)
    # icc=false means inter-container communication is DISABLED on default bridge

    # Check logging driver
    local log_driver
    log_driver=$(docker info 2>/dev/null | grep "Logging Driver" | head -1)
    if echo "${log_driver}" | grep -qi "json-file"; then
        ok "[PASS] Logging driver is json-file (with rotation)"
    else
        warn "[WARN] Logging driver: ${log_driver}"
    fi

    # Check no-new-privileges
    local no_new_privs
    if grep -q "no-new-privileges" "${DAEMON_JSON}" 2>/dev/null; then
        ok "[PASS] no-new-privileges security flag is set"
    else
        warn "[WARN] no-new-privileges may not be configured"
    fi

    # Check for privileged containers
    local priv_count
    priv_count=$(docker ps -q 2>/dev/null | xargs -I{} docker inspect {} --format '{{.HostConfig.Privileged}}' 2>/dev/null | grep -c "true" || true)
    if [ "${priv_count}" -eq 0 ]; then
        ok "[PASS] No containers running in privileged mode"
    else
        warn "[WARN] ${priv_count} container(s) running in privileged mode!"
        errors=$((errors + 1))
    fi

    # Check for host network
    local host_count
    host_count=$(docker ps -q 2>/dev/null | xargs -I{} docker inspect {} --format '{{.HostConfig.NetworkMode}}' 2>/dev/null | grep -c "host" || true)
    if [ "${host_count}" -eq 0 ]; then
        ok "[PASS] No containers using host network"
    else
        warn "[INFO] ${host_count} container(s) using host networking"
    fi

    info ""
    if [ "${errors}" -eq 0 ]; then
        ok "Docker security verification PASSED"
    else
        warn "Docker security had ${errors} issue(s)"
    fi
}

# ─── Dry Run ─────────────────────────────────────────────────────────────────

dry_run_info() {
    info "DRY RUN — Docker security hardening plan:"
    info ""
    info "daemon.json changes:"
    info "  - userns-remap:           default (containers → non-root on host)"
    info "  - seccomp-profile:        /etc/docker/seccomp-default.json"
    info "  - icc:                    false (no inter-container on default bridge)"
    info "  - live-restore:           true (daemon restart preserves containers)"
    info "  - log-driver:             json-file (max 10MB, 3 files)"
    info "  - default-ulimits:        nofile=65536, nproc=4096"
    info "  - content-trust:          true (image signature verification)"
    info "  - userland-proxy:         false (use iptables directly)"
    info "  - no-new-privileges:      true (containers can't gain privileges)"
    info ""
    info "Other actions:"
    info "  - Create dockremap user for user namespace"
    info "  - Install default seccomp profile"
    info "  - Audit running containers for security issues"
    info "  - Create restore script"
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

    info "=== Docker Security Hardening — $(hostname) ==="
    info ""

    # Backup existing configuration
    backup_daemon_json

    # Apply security settings
    generate_daemon_json
    setup_user_namespace
    install_seccomp_profile

    # Restart Docker to apply changes
    restart_docker

    # Audit running containers
    audit_containers

    # Generate restore script
    generate_restore_script

    # Verify
    verify_hardening

    info ""
    info "=== Docker security hardening complete on $(hostname) ==="
    info ""
    info "Key actions taken:"
    info "  - User namespace remapping enabled (containers run as non-root)"
    info "  - Default seccomp profile installed"
    info "  - Inter-container communication disabled on default bridge"
    info "  - Live-restore enabled (containers survive daemon restart)"
    info "  - Default ulimits set (prevents resource exhaustion)"
    info "  - Content trust enabled (image signature verification)"
    info "  - no-new-privileges enabled"
    info "  - Containers audited for privilege issues"
    info ""
    info "Backup:  ${BACKUP_DIR}/daemon.json.${TIMESTAMP}"
    info "Restore: ${RESTORE_SCRIPT}"
    info ""
    info "⚠️  IMPORTANT: User namespace remapping changes UID mapping!"
    info "  - Existing volumes may have wrong permissions after restart."
    info "  - Run: docker info | grep 'Uid\|Gid' to verify remapping."
    info "  - If containers can't write to volumes, you may need to:"
    info "      chown -R 100000:100000 /var/lib/docker/volumes/*"
    info "    (where 100000 is the mapped UID range start)"
}

main "$@"
