#!/usr/bin/env bash
# =============================================================================
# Wheeler Enterprise — Cgroup Resource Limits
# =============================================================================
# Sets Docker-aware cgroup limits for critical system services when running
# alongside containers. Prevents Docker from starving SSH, systemd, or
# the OOM killer of CPU/memory during container build storms.
#
# Usage: bash 10-cgroup-limits.sh [--apply]
# =============================================================================
set -euo pipefail

ACTION="${1:---dry-run}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }

# Systemd slice configurations for resource partitioning
# Docker containers run under machine.slice by default
# We protect system.slice (SSH, cron, systemd itself) with reservations

generate_slice_configs() {
    cat <<'EOF'
=== Wheeler Enterprise Cgroup Resource Partitions ===

Two mechanisms to prevent resource starvation:

1. systemd slice reservations — guarantees CPU/memory for system services
2. Docker resource constraints — per-container limits in compose files

== systemd Slice Strategy ==

System slice (SSH, cron, journald, etc.):
  CPU:   2 cores reserved (of 16)
  Mem:   2GB reserved (of 30GB)
  Purpose: Ensure SSH always works even under Docker swarm storms

Machine slice (Docker containers):
  CPU:   Remaining cores
  Mem:   Remaining memory
  Purpose: Bulk of workload

== Files to Deploy ==

/etc/systemd/system/system.slice.d/50-wheeler-reservations.conf

[Slice]
# Reserve 2 CPU cores and 2GB RAM for system services
CPUQuota=200%
MemoryMin=2G
MemoryHigh=4G
MemoryMax=6G
TasksMax=1024

/etc/systemd/system/user.slice.d/50-wheeler-reservations.conf

[Slice]
# Limit user sessions (prevents fork bombs)
CPUQuota=200%
MemoryHigh=4G
MemoryMax=6G
TasksMax=4096

== Per-Container Limits (applied in Docker compose) ==

Critical services get higher limits:
  postgres:    --memory=4g --cpus=2    (COREDB: 8g, 4 cpus)
  redis:       --memory=2g --cpus=1    (COREDB: 4g, 2 cpus)
  grafana:     --memory=1g --cpus=1
  prometheus:  --memory=2g --cpus=1
  traefik:     --memory=512m --cpus=1
  litellm:     --memory=1g --cpus=1
  langflow:    --memory=2g --cpus=2

User-facing services:
  frontend:    --memory=512m --cpus=0.5
  api:         --memory=1g --cpus=1

Monitoring/utility:
  netdata:     --memory=512m --cpus=0.5
  cadvisor:    --memory=512m --cpus=0.5
  node-exporter: --memory=256m --cpus=0.25
  loki:        --memory=1g --cpus=0.5
  promtail:    --memory=256m --cpus=0.25

== OOM Protection (systemd service overrides) ==

SSH daemon:
  /etc/systemd/system/ssh.service.d/50-wheeler-oom.conf
  [Service]
  OOMScoreAdjust=-900    # Almost never killed

PostgreSQL (COREDB server):
  OOMScoreAdjust=-800    # Protected, but less than SSH

Redis (COREDB server):
  OOMScoreAdjust=-700

Docker daemon:
  OOMScoreAdjust=-500    # Middle priority
EOF
}

generate_user_slice() {
    cat <<'EOF'
# /etc/systemd/system/user.slice.d/50-wheeler-reservations.conf
[Slice]
CPUQuota=200%
MemoryHigh=4G
MemoryMax=6G
TasksMax=4096
EOF
}

generate_system_slice() {
    cat <<'EOF'
# /etc/systemd/system/system.slice.d/50-wheeler-reservations.conf
[Slice]
CPUQuota=200%
MemoryMin=2G
MemoryHigh=4G
MemoryMax=6G
TasksMax=1024
EOF
}

# ── Main ──────────────────────────────────────────────────────────────────

echo "=== Wheeler Enterprise Cgroup Resource Limits ==="
echo ""
generate_slice_configs

if [ "$ACTION" = "--apply" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        warn "Must be root. Run with sudo."
        exit 1
    fi

    log "Applying slice reservations..."

    mkdir -p /etc/systemd/system/system.slice.d
    generate_system_slice > /etc/systemd/system/system.slice.d/50-wheeler-reservations.conf

    mkdir -p /etc/systemd/system/user.slice.d
    generate_user_slice > /etc/systemd/system/user.slice.d/50-wheeler-reservations.conf

    # OOM protection for SSH
    mkdir -p /etc/systemd/system/ssh.service.d
    cat > /etc/systemd/system/ssh.service.d/50-wheeler-oom.conf <<'OOM'
[Service]
OOMScoreAdjust=-900
OOM

    systemctl daemon-reload
    log "Cgroup limits applied. systemd daemon reloaded."
else
    echo ""
    echo ">>> Dry run. To apply: bash $(basename "$0") --apply"
fi
