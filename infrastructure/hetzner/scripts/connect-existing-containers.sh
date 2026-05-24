#!/usr/bin/env bash
# =============================================================================
# Connect Existing Containers to Docker Networks — Zero Downtime
# =============================================================================
# Connects already-running containers to the new Docker bridge networks
# created by networks.sh. This is critical for Phase 2 migration because:
#
#   1. Phase 1 containers are running with --net=bridge or default network
#   2. We cannot restart them all at once (would cause downtime)
#   3. Docker allows hot-plugging containers into networks (no restart needed)
#   4. After attaching to the new network, containers can communicate via DNS
#
# HOW IT WORKS:
#   docker network connect <network> <container>
#
# This is a zero-downtime operation — the container keeps serving traffic
# while being connected to the new network.
#
# IMPORTANT:
#   - Run this script AFTER creating the new networks (networks.sh create)
#   - Run this script BEFORE restarting containers with new compose files
#   - After this script, you can deploy the new compose files, which will
#     recreate containers already on the correct networks
#   - Old containers on bridge networks continue working during migration
#
# USAGE:
#   ./connect-existing-containers.sh [--dry-run] [--verbose]
#
# OPTIONS:
#   --dry-run   Show what would be done without making changes
#   --verbose   Show detailed network connectivity info per container
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header()  { echo -e "\n${CYAN}════════════════════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"; }

DRY_RUN=false
VERBOSE=false

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--dry-run] [--verbose]"
      echo ""
      echo "Connects running containers to Docker networks for Phase 2 migration."
      echo ""
      echo "Options:"
      echo "  --dry-run   Show what would be done without making changes"
      echo "  --verbose   Show detailed network connectivity info"
      exit 0
      ;;
    *)
      err "Unknown option: $1"
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Container-to-Network Mapping
# -----------------------------------------------------------------------------
# Maps service containers to their target Docker networks based on the
# Phase 2 architecture. Each container is connected to its primary
# internal network AND (if public) the traefik-public network.
#
# Format: container_name:network1,network2,...
# Services that ARE routed through Traefik get traefik-public.
# Services that are INTERNAL ONLY only get their service network.
#
# This mapping uses the SERVICE PLACEMENT MATRIX from ARCHITECTURE.md.
declare -A CONTAINER_NETWORKS

# Traefik — special case, should already be on traefik-public
CONTAINER_NETWORKS["traefik"]="traefik-public"

# Prediction Radar (public)
CONTAINER_NETWORKS["prediction-radar-web"]="prediction-radar,traefik-public"
CONTAINER_NETWORKS["prediction-radar-api"]="prediction-radar,traefik-public"
CONTAINER_NETWORKS["prediction-radar-worker"]="prediction-radar"
CONTAINER_NETWORKS["prediction-radar-scheduler"]="prediction-radar"
CONTAINER_NETWORKS["prediction-radar-db"]="prediction-radar"
CONTAINER_NETWORKS["prediction-radar-redis"]="prediction-radar"

# RavynAI
CONTAINER_NETWORKS["ravynai-api"]="ravynai,traefik-public"
CONTAINER_NETWORKS["ravynai-worker"]="ravynai"
CONTAINER_NETWORKS["ravynai-db"]="ravynai"
CONTAINER_NETWORKS["ravynai-redis"]="ravynai"

# Analytics
CONTAINER_NETWORKS["superset"]="analytics,traefik-public"
CONTAINER_NETWORKS["superset-db"]="analytics"
CONTAINER_NETWORKS["clickhouse"]="analytics"

# Monitoring (public: Grafana, Uptime Kuma; internal: others)
CONTAINER_NETWORKS["grafana"]="monitoring,traefik-public"
CONTAINER_NETWORKS["prometheus"]="monitoring"
CONTAINER_NETWORKS["node-exporter"]="monitoring"
CONTAINER_NETWORKS["cadvisor"]="monitoring"
CONTAINER_NETWORKS["alertmanager"]="monitoring"
CONTAINER_NETWORKS["uptime-kuma"]="monitoring,traefik-public"
CONTAINER_NETWORKS["postgres-exporter"]="monitoring"
CONTAINER_NETWORKS["redis-exporter"]="monitoring"
CONTAINER_NETWORKS["netdata"]="monitoring"

# Management (Tailscale-only via Traefik route)
CONTAINER_NETWORKS["portainer"]="management,traefik-public"
CONTAINER_NETWORKS["dockge"]="management,traefik-public"

# Automation
CONTAINER_NETWORKS["changedetection"]="automation,traefik-public"
CONTAINER_NETWORKS["browser-automation"]="automation"

# Data
CONTAINER_NETWORKS["postgres"]="data"
CONTAINER_NETWORKS["redis"]="data"

# AI Agents
CONTAINER_NETWORKS["agent-api"]="ai-agents,traefik-public"
CONTAINER_NETWORKS["agent-runner-1"]="ai-agents"
CONTAINER_NETWORKS["ai-agents-redis"]="ai-agents"

# Healthchecks
CONTAINER_NETWORKS["healthchecks"]="monitoring,traefik-public"

# Trading
CONTAINER_NETWORKS["trading-redis"]="trading"
CONTAINER_NETWORKS["trading-feed-ingestor"]="trading"
CONTAINER_NETWORKS["trading-strategy-1"]="trading"
CONTAINER_NETWORKS["trading-order-manager"]="trading"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

container_is_running() {
  local container="$1"
  docker ps --filter "name=^/${container}$" --format '{{.Names}}' | grep -qx "$container"
}

container_has_network() {
  local container="$1"
  local network="$2"
  docker inspect "$container" --format '{{range $net, $v := .NetworkSettings.Networks}}{{$net}}{{"\n"}}{{end}}' 2>/dev/null | grep -qx "$network"
}

connect_container() {
  local container="$1"
  local network="$2"

  if container_has_network "$container" "$network"; then
    if [[ $VERBOSE == true ]]; then
      info "  $container already connected to $network — skipping"
    fi
    return 0
  fi

  if [[ $DRY_RUN == true ]]; then
    info "[DRY RUN] Would connect $container → $network"
    return 0
  fi

  info "  Connecting $container → $network"
  if docker network connect "$network" "$container" 2>/dev/null; then
    ok "  $container connected to $network"
  else
    err "  Failed to connect $container to $network"
    return 1
  fi
}

show_container_networks() {
  local container="$1"
  local networks
  networks=$(docker inspect "$container" --format '{{range $net, $v := .NetworkSettings.Networks}}{{$net}} {{end}}' 2>/dev/null)
  info "  $container: $networks"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

header "Connecting Existing Containers to Phase 2 Networks"
info "Started at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
[[ $DRY_RUN == true ]] && warn "DRY RUN — no changes will be made"
echo ""

# Check Docker
if ! docker info &>/dev/null; then
  err "Docker is not running."
  exit 1
fi

# Verify target networks exist (list all the unique networks)
declare -A TARGET_NETWORKS
for container in "${!CONTAINER_NETWORKS[@]}"; do
  IFS=',' read -ra networks <<< "${CONTAINER_NETWORKS[$container]}"
  for net in "${networks[@]}"; do
    TARGET_NETWORKS["$net"]=1
  done
done

missing_networks=()
for net in "${!TARGET_NETWORKS[@]}"; do
  if ! docker network inspect "$net" &>/dev/null; then
    missing_networks+=("$net")
  fi
done

if [[ ${#missing_networks[@]} -gt 0 ]]; then
  warn "Some target networks do not exist yet:"
  for net in "${missing_networks[@]}"; do
    err "  - $net"
  done
  echo ""
  err "Create them first: cd .. && bash compose/networks.sh create"
  echo ""
  # Don't exit — let the user decide if they want to continue
  if [[ $DRY_RUN == false ]]; then
    warn "Continuing with existing networks only..."
  fi
fi

# -----------------------------------------------------------------------------
# Phase 1: Scan for containers and show current state
# -----------------------------------------------------------------------------

header "Phase 1: Container Discovery"

total_found=0
total_to_connect=0
declare -A STALE_CONTAINERS

for container in "${!CONTAINER_NETWORKS[@]}"; do
  if container_is_running "$container"; then
    ((total_found++)) || true

    IFS=',' read -ra networks <<< "${CONTAINER_NETWORKS[$container]}"
    missing=0
    for net in "${networks[@]}"; do
      if ! container_has_network "$container" "$net"; then
        ((missing++)) || true
      fi
    done

    if [[ $missing -gt 0 ]]; then
      ((total_to_connect++)) || true
    fi

    if [[ $VERBOSE == true ]]; then
      show_container_networks "$container"
    fi
  else
    STALE_CONTAINERS["$container"]=1
  fi
done

info "Running containers found: $total_found"
info "Containers needing network connection: $total_to_connect"

if [[ ${#STALE_CONTAINERS[@]} -gt 0 ]]; then
  echo ""
  info "Containers not currently running (will be connected when deployed):"
  for container in "${!STALE_CONTAINERS[@]}"; do
    echo "  - $container"
  done
fi

echo ""

if [[ $total_found -eq 0 ]]; then
  info "No existing containers found. Nothing to connect."
  info "Deploy services with the new compose files, and they will"
  info "automatically be placed on the correct networks."
  exit 0
fi

# -----------------------------------------------------------------------------
# Phase 2: Connect containers to their target networks
# -----------------------------------------------------------------------------

header "Phase 2: Connecting Containers to Networks"

connected=0
skipped=0
failed=0

for container in "${!CONTAINER_NETWORKS[@]}"; do
  if ! container_is_running "$container"; then
    continue  # Skip non-running containers
  fi

  echo ""
  info "Processing: $container"

  IFS=',' read -ra networks <<< "${CONTAINER_NETWORKS[$container]}"
  for net in "${networks[@]}"; do
    # Skip if network doesn't exist
    if ! docker network inspect "$net" &>/dev/null; then
      warn "  Network '$net' does not exist — skipping"
      continue
    fi

    if container_has_network "$container" "$net"; then
      ((skipped++)) || true
      continue
    fi

    if connect_container "$container" "$net"; then
      ((connected++)) || true
    else
      ((failed++)) || true
    fi
  done
done

# -----------------------------------------------------------------------------
# Phase 3: Verification
# -----------------------------------------------------------------------------

header "Phase 3: Verification"

echo ""
info "Verifying network connectivity for all containers..."
echo ""

for container in "${!CONTAINER_NETWORKS[@]}"; do
  if ! container_is_running "$container"; then
    continue
  fi

  IFS=',' read -ra networks <<< "${CONTAINER_NETWORKS[$container]}"
  for net in "${networks[@]}"; do
    if ! docker network inspect "$net" &>/dev/null; then
      continue
    fi

    if container_has_network "$container" "$net"; then
      :  # connected successfully
    else
      err "  $container is NOT connected to $net"
    fi
  done
done

# Print final connectivity matrix
echo ""
header "Network Connectivity Matrix"
echo ""

# Collect all containers and networks for matrix display
declare -A ALL_CONTAINERS
declare -A ALL_NETWORKS

for container in "${!CONTAINER_NETWORKS[@]}"; do
  if container_is_running "$container"; then
    ALL_CONTAINERS["$container"]=1
  fi
done

for net in "${!TARGET_NETWORKS[@]}"; do
  if docker network inspect "$net" &>/dev/null; then
    ALL_NETWORKS["$net"]=1
  fi
done

# Print header row
printf "%-40s" "Container \\ Network"
for net in $(echo "${!ALL_NETWORKS[@]}" | tr ' ' '\n' | sort); do
  printf "%-18s" "$net"
done
echo ""

printf "%-40s" "───────────────────────────────────────"
for net in $(echo "${!ALL_NETWORKS[@]}" | tr ' ' '\n' | sort); do
  printf "%-18s" "──────────────────"
done
echo ""

for container in $(echo "${!ALL_CONTAINERS[@]}" | tr ' ' '\n' | sort); do
  printf "%-40s" "$container"
  for net in $(echo "${!ALL_NETWORKS[@]}" | tr ' ' '\n' | sort); do
    if container_has_network "$container" "$net"; then
      printf "${GREEN}%-18s${NC}" "✓ connected"
    else
      # Check if it SHOULD be on this network
      if [[ "${CONTAINER_NETWORKS[$container]}" == *"$net"* ]]; then
        printf "${RED}%-18s${NC}" "✗ MISSING"
      else
        printf "%-18s" "—"
      fi
    fi
  done
  echo ""
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
header "Summary"

info "Operation completed at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

if [[ $DRY_RUN == true ]]; then
  warn "DRY RUN — no connections were made"
  info "Re-run without --dry-run to apply changes"
else
  ok "Containers connected: $connected"
  info "Already connected (skipped): $skipped"

  if [[ $failed -gt 0 ]]; then
    err "Failed connections: $failed"
  fi
fi

echo ""
info "Next steps:"
echo "  1. Deploy the new Traefik reverse proxy:"
echo "     cd ../traefik && docker compose up -d"
echo ""
echo "  2. Deploy service stacks with new compose files:"
echo "     docker compose -f compose/prediction-radar.yml up -d"
echo "     docker compose -f compose/ravynai.yml up -d"
echo "     # ... etc"
echo ""
echo "  3. As each stack is deployed, the old containers on bridge"
echo "     networks will be replaced by new ones on dedicated networks."
echo "     The containers connected here will continue working until"
echo "     they are recreated by the new compose files."
echo ""
warn "Do not remove old containers until new ones are confirmed healthy!"
echo "  Keep old containers running alongside new ones during migration."
echo "  This allows rollback if something goes wrong."
