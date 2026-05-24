#!/usr/bin/env bash
# =============================================================================
# Wheeler Enterprise — Swap Optimization
# =============================================================================
# Configures a swap file optimized for:
#   - 30GB RAM servers
#   - Mixed workload: databases + Docker containers + Node.js processes
#
# Strategy: 8GB swap file with swappiness=10
#   - 10: almost never swap → keeps hot pages in RAM
#   - But provides safety valve for memory pressure
#   - Prevents OOM killer from killing postgres/redis
#
# Usage: bash 05-swap-setup.sh [--apply] [--size-gb=8]
# =============================================================================
set -euo pipefail

ACTION="${1:---dry-run}"
SWAP_SIZE_GB="${2:-8}"
SWAPFILE="/swapfile"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }

generate_swap_plan() {
    cat <<EOF
=== Wheeler Enterprise Swap Configuration ===
Server RAM: $(free -h | awk '/^Mem:/{print $2}')
Current swap: $(free -h | awk '/^Swap:/{print $2}')

Planned:
  Swap file:     $SWAPFILE
  Swap size:     ${SWAP_SIZE_GB}GB
  Swappiness:    10 (almost never, safety valve only)
  VFS pressure:  50 (reduced dentry/inode cache pressure)

Rationale:
  - 30GB RAM is ample for normal operations
  - Swap acts as an emergency buffer, not active memory
  - swappiness=10 means kernel will aggressively avoid swapping
  - Protects against rare memory pressure spikes from:
    * Concurrent database queries
    * Docker image builds
    * AI model loading (future GPU workloads)
  - Prevents OOM killer from targeting PostgreSQL or Redis first
EOF
}

setup_swap() {
    log "Creating ${SWAP_SIZE_GB}GB swap file at $SWAPFILE..."

    # Check if swap already exists
    if swapon --show | grep -q "$SWAPFILE"; then
        warn "Swap already active at $SWAPFILE. Removing old swap..."
        swapoff "$SWAPFILE" 2>/dev/null || true
    fi

    # Allocate swapfile efficiently using fallocate (instant on ext4/xfs)
    if command -v fallocate &>/dev/null; then
        fallocate -l "${SWAP_SIZE_GB}G" "$SWAPFILE"
    else
        dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
    fi

    # Secure permissions — prevent information leak
    chmod 600 "$SWAPFILE"

    # Format as swap
    mkswap "$SWAPFILE"

    # Enable
    swapon "$SWAPFILE"

    # Persist in fstab
    if ! grep -q "$SWAPFILE" /etc/fstab; then
        echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
        log "Added $SWAPFILE to /etc/fstab"
    fi

    # Set swappiness
    sysctl vm.swappiness=10
    echo "vm.swappiness=10" > /etc/sysctl.d/99-wheeler-swap.conf

    # Reduce VFS cache pressure
    sysctl vm.vfs_cache_pressure=50
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-wheeler-swap.conf

    log "Swap configured successfully:"
    free -h
    swapon --show
}

# ── Main ──────────────────────────────────────────────────────────────────

generate_swap_plan

if [ "$ACTION" = "--apply" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        warn "Must be root. Run with sudo."
        exit 1
    fi
    setup_swap
else
    echo ""
    echo ">>> Dry run. To apply: bash $(basename "$0") --apply [--size-gb=8]"
fi
