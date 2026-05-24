#!/usr/bin/env bash
###############################################################################
# HOSTINGER VPS — AGGRESSIVE PRUNE SCRIPT
# ==========================================
# Resource-constrained edge VPS cleanup.
#
# This script is INTENTIONALLY AGGRESSIVE.  On a 8-16GB VPS running 15+
# containers, every MB of disk and RAM matters.  This script:
#   1. Removes ALL unused Docker images, stopped containers, unused volumes
#   2. Cleans apt cache, journal logs, temp files
#   3. Verifies only expected services are running
#   4. Shows disk space before/after
#
# EXPECTED SERVICES (post-cleanup):
#   - traefik-edge (Traefik v3)
#   - frgops-postgres, frgops-redis
#   - frgops, frgcrm, chatwoot, docuseal
#   - n8n-edge, webhook-receiver
#   - litellm-edge, minio-edge
#   - Optional: crowdsec-agent, crowdsec-bouncer
#
# HEAVY SERVICES THAT SHOULD NOT BE HERE:
#   - prediction-radar (API, web, worker, scheduler, db, redis)
#   - ravynai (api, worker, db)
#   - superset, clickhouse
#   - changedetection, healthchecks
#   - spiderfoot, browser-automation
#   - trading-engine, realtime-feed
#   - nats, rabbitmq
#   - grafana, prometheus, netdata (on host, not Docker)
#   - portainer, dockge
#   - postgres (main AIOps), redis (AIOps)
###############################################################################

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

# List of expected/authorized container names (regex patterns)
# Any running container NOT matching these will be flagged.
AUTHORIZED_CONTAINERS=(
  "traefik-edge"
  "frgops-postgres"
  "frgops-redis"
  "frgops"
  "frgcrm"
  "chatwoot"
  "docuseal"
  "n8n-edge"
  "webhook-receiver"
  "litellm-edge"
  "minio-edge"
  "crowdsec-agent"
  "crowdsec-bouncer"
)

# Paths
DOCKER_COMPOSE_DIR="/root/infrastructure/hostinger"
SCRIPT_NAME=$(basename "$0")
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# ── Color Output ───────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Pre-flight Checks ─────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (or with sudo)."
  exit 1
fi

if ! command -v docker &>/dev/null; then
  error "Docker is not installed.  Nothing to prune."
  exit 1
fi

# ── Functions ──────────────────────────────────────────────────────────────────

check_disk_space() {
  local label="$1"
  info "Disk space ${label}:"
  df -h / | tail -1 | awk '{printf "  Total: %s  Used: %s  Avail: %s  Use%%: %s\n", $2, $3, $4, $5}'
  echo ""
}

show_memory_usage() {
  info "Memory usage:"
  free -h | grep -E "^Mem:|^Swap:"
  echo ""
}

count_containers() {
  docker ps -q | wc -l
}

verify_heavy_services_stopped() {
  local heavy_services=(
    "prediction-radar"
    "ravynai"
    "clickhouse"
    "superset"
    "changedetection"
    "spiderfoot"
    "browser-automation"
    "trading"
    "nats"
    "rabbitmq"
    "portainer"
    "dockge"
  )

  local found=false
  for service in "${heavy_services[@]}"; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "$service"; then
      warn "HEAVY SERVICE STILL RUNNING: $(docker ps --format '{{.Names}}' | grep -i "$service")"
      found=true
    fi
  done

  if ! $found; then
    ok "No heavy services detected.  Phase 1 migration is complete."
  fi
  echo ""
}

verify_authorized_containers() {
  local running_containers
  running_containers=$(docker ps --format '{{.Names}}' 2>/dev/null || true)

  if [[ -z "$running_containers" ]]; then
    warn "No containers are running."
    return
  fi

  info "Verifying running containers are authorized..."

  while IFS= read -r container; do
    local authorized=false
    for pattern in "${AUTHORIZED_CONTAINERS[@]}"; do
      if [[ "$container" =~ $pattern ]]; then
        authorized=true
        break
      fi
    done

    if $authorized; then
      ok "  $container (authorized)"
    else
      warn "  $container (UNEXPECTED — investigate)"
    fi
  done <<< "$running_containers"

  echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "========================================================================"
echo " HOSTINGER VPS — AGGRESSIVE PRUNE"
echo " Timestamp: $TIMESTAMP"
echo "========================================================================"
echo ""

# ── Step 1: Show Current State ────────────────────────────────────────────────
info "=== CURRENT STATE ==="
check_disk_space "before"
show_memory_usage
info "Running containers: $(count_containers)"
echo ""

# ── Step 2: Verify Heavy Services ─────────────────────────────────────────────
info "=== VERIFYING HEAVY SERVICES ==="
verify_heavy_services_stopped

# ── Step 3: Docker System Prune (Safe) ────────────────────────────────────────
info "=== DOCKER SYSTEM PRUNE ==="
info "Removing unused containers, networks, and dangling images..."
docker system prune --all --force --volumes 2>&1 || true
echo ""

# ── Step 4: Deep Clean — Remove ALL Unused Images ────────────────────────────
info "=== REMOVING UNUSED DOCKER IMAGES ==="
# Remove all images not associated with any container (running or stopped)
docker image prune --all --force 2>&1 || true

# List remaining images with sizes
info "Remaining Docker images:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null || true
echo ""

# ── Step 5: Remove Stopped Containers (Safety Check) ─────────────────────────
info "=== REMOVING STOPPED CONTAINERS ==="
local stopped_count
stopped_count=$(docker ps -a --filter "status=exited" --filter "status=created" -q | wc -l)
if [[ "$stopped_count" -gt 0 ]]; then
  docker container prune --force 2>&1 || true
  ok "Removed $stopped_count stopped containers."
else
  ok "No stopped containers to remove."
fi
echo ""

# ── Step 6: Remove Unused Volumes ─────────────────────────────────────────────
info "=== REMOVING UNUSED VOLUMES ==="
docker volume prune --force 2>&1 || true
echo ""

# ── Step 7: Remove Unused Networks ────────────────────────────────────────────
info "=== REMOVING UNUSED NETWORKS ==="
docker network prune --force 2>&1 || true
echo ""

# ── Step 8: Clean Build Cache ─────────────────────────────────────────────────
info "=== CLEANING BUILD CACHE ==="
docker builder prune --all --force 2>&1 || true
echo ""

# ── Step 9: System-Level Cleanup ──────────────────────────────────────────────
info "=== SYSTEM-LEVEL CLEANUP ==="

# Clean apt cache
info "Cleaning apt cache..."
apt-get clean -y 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true

# Clean journal logs — keep only the last 100MB
info "Cleaning journal logs (keeping 100M)..."
journalctl --vacuum-size=100M 2>/dev/null || true

# Clean temp files (older than 7 days)
info "Cleaning temp files older than 7 days..."
find /tmp -type f -atime +7 -delete 2>/dev/null || true
find /var/tmp -type f -atime +7 -delete 2>/dev/null || true

# Clean old snap packages (if any)
if command -v snap &>/dev/null; then
  info "Cleaning old snap revisions..."
  snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r snap_name snap_rev; do
    snap remove "$snap_name" --revision="$snap_rev" 2>/dev/null || true
  done
fi

# Clean old kernel headers (keep current only)
if command -v dpkg &>/dev/null; then
  info "Removing old kernel headers..."
  apt-get autoremove --purge -y 2>/dev/null || true
fi

echo ""

# ── Step 10: Verify Expected Services ─────────────────────────────────────────
info "=== VERIFYING EXPECTED SERVICES ==="
verify_authorized_containers

# ── Step 11: Show Final State ────────────────────────────────────────────
info "=== FINAL STATE ==="
check_disk_space "after"
show_memory_usage
info "Running containers: $(count_containers)"
echo ""

# ── Step 12: Report Disk Space Reclaimed ──────────────────────────────────────
info "=== SUMMARY ==="
echo "========================================================================"
echo " PRUNE COMPLETE"
echo " Timestamp: $TIMESTAMP"
echo "========================================================================"
echo ""

# Exit with success
exit 0
