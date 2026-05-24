#!/usr/bin/env bash
# =============================================================================
# Docker Network Creation Script — Hetzner CPX51
# =============================================================================
# Creates all the Docker overlay/bridge networks for service isolation.
# Each network uses a dedicated /24 subnet for:
#   1. Predictable IP allocation
#   2. Easy firewall rule creation (subnet-based)
#   3. No overlap between networks (prevents routing confusion)
#   4. Clean observability (you know which subnet = which service tier)
#
# Network Architecture:
#   traefik-public  (172.20.x)  — Ingress network, all public-routed containers
#   prediction-radar (172.21.x) — Full-stack ML prediction platform
#   analytics       (172.22.x)  — Superset + ClickHouse (analytics)
#   monitoring      (172.23.x)  — Prometheus, Grafana, Netdata, Uptime Kuma
#   ai-agents       (172.24.x)  — AI agent runtimes (Python, LangChain, etc.)
#   ravynai         (172.25.x)  — RavynAI ecosystem
#   trading         (172.26.x)  — Trading engine workers + feed handlers
#   messaging       (172.27.x)  — NATS, RabbitMQ, Redis Pub/Sub
#   automation      (172.28.x)  — ChangeDetection, Browser Automation, n8n
#   data            (172.29.x)  — Shared Postgres, Redis
#   management      (172.30.x)  — Portainer, Dockge, 1Panel
#
# Usage:
#   ./networks.sh [create|remove|inspect]
#
# Safety:
#   - Idempotent: checks if network exists before creating
#   - Non-destructive: never removes a network with connected containers
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Color output helpers
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -----------------------------------------------------------------------------
# Network definitions:  (name, subnet, gateway, description)
# -----------------------------------------------------------------------------
NETWORKS=(
  "traefik-public:172.20.0.0/24:172.20.0.1:Ingress network — all publicly-routed containers connect here"
  "prediction-radar:172.21.0.0/24:172.21.0.1:Prediction Radar full stack (web, api, worker, db, redis)"
  "analytics:172.22.0.0/24:172.22.0.1:Analytics — Superset + ClickHouse"
  "monitoring:172.23.0.0/24:172.23.0.1:Monitoring — Prometheus, Grafana, Netdata, Uptime Kuma"
  "ai-agents:172.24.0.0/24:172.24.0.1:AI Agent runtimes (LangChain, CrewAI, etc.)"
  "ravynai:172.25.0.0/24:172.25.0.1:RavynAI ecosystem (api, worker, db)"
  "trading:172.26.0.0/24:172.26.0.1:Trading engine — feed ingest, strategy workers, order mgmt"
  "messaging:172.27.0.0/24:172.27.0.1:Messaging — NATS, RabbitMQ, Redis Pub/Sub"
  "automation:172.28.0.0/24:172.28.0.1:Automation — ChangeDetection, Browser Automation"
  "data:172.29.0.0/24:172.29.0.1:Shared data — Postgres (AIOps), Redis (AIOps)"
  "management:172.30.0.0/24:172.30.0.1:Management — Portainer, Dockge, 1Panel"
)

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

create_networks() {
  local created=0
  local skipped=0

  info "Creating Docker bridge networks..."

  for netdef in "${NETWORKS[@]}"; do
    IFS=':' read -r name subnet gateway description <<< "$netdef"

    if docker network inspect "$name" &>/dev/null; then
      warn "Network '$name' already exists — skipping"
      ((skipped++)) || true
      continue
    fi

    info "  Creating '$name' ($subnet) — $description"
    docker network create \
      --driver bridge \
      --subnet "$subnet" \
      --gateway "$gateway" \
      --label "managed=hetzner-infra" \
      --label "purpose=${description}" \
      --label "subnet=${subnet}" \
      "$name"

    ok "  Network '$name' created (subnet: $subnet)"
    ((created++)) || true
  done

  echo ""
  info "Summary: created=$created, skipped=$skipped, total=${#NETWORKS[@]}"
}

remove_networks() {
  local removed=0
  local skipped=0

  warn "Removing Docker networks..."
  warn "This will FAIL for networks with connected containers."

  # Remove in reverse order (management first, traefik-public last)
  for netdef in "${NETWORKS[@]}"; do
    IFS=':' read -r name subnet gateway description <<< "$netdef"

    if ! docker network inspect "$name" &>/dev/null; then
      warn "  Network '$name' does not exist — skipping"
      ((skipped++)) || true
      continue
    fi

    # Check for connected containers
    local connected
    connected=$(docker network inspect "$name" --format '{{json .Containers}}' 2>/dev/null || echo "{}")
    if [ "$connected" != "{}" ] && [ "$connected" != "null" ]; then
      err "  Network '$name' has connected containers — skipping (disconnect containers first)"
      ((skipped++)) || true
      continue
    fi

    info "  Removing network '$name' ($subnet)"
    docker network rm "$name" > /dev/null
    ok "  Network '$name' removed"
    ((removed++)) || true
  done

  echo ""
  warn "Summary: removed=$removed, skipped=$skipped"
}

inspect_networks() {
  info "Current Docker networks:"
  echo ""
  printf "%-22s %-18s %-18s %s\n" "NAME" "SUBNET" "GATEWAY" "CONTAINERS"
  printf "%-22s %-18s %-18s %s\n" "----" "------" "-------" "----------"

  for netdef in "${NETWORKS[@]}"; do
    IFS=':' read -r name subnet gateway description <<< "$netdef"

    if docker network inspect "$name" &>/dev/null; then
      local containers
      containers=$(docker network inspect "$name" --format '{{len .Containers}}' 2>/dev/null || echo "0")
      printf "%-22s %-18s %-18s %s\n" "$name" "$subnet" "$gateway" "$containers"
    else
      printf "%-22s %-18s %-18s %s\n" "$name" "(not created)" "-" "-"
    fi
  done

  echo ""
  info "Total defined networks: ${#NETWORKS[@]}"

  # Show non-standard networks (manually created)
  local extra
  extra=$(docker network ls --format '{{.Name}}' | grep -v -E '^(bridge|host|none)$' | while read -r n; do
    local found=false
    for netdef in "${NETWORKS[@]}"; do
      IFS=':' read -r name _ _ <<< "$netdef"
      if [ "$n" = "$name" ]; then found=true; break; fi
    done
    $found || echo "$n"
  done)

  if [ -n "$extra" ]; then
    warn "Extra networks (not managed by this script):"
    echo "$extra" | while read -r n; do echo "  - $n"; done
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

# Ensure Docker is running
if ! docker info &>/dev/null; then
  err "Docker is not running. Please start Docker first."
  exit 1
fi

case "${1:-create}" in
  create)
    create_networks
    ;;
  remove)
    remove_networks
    ;;
  inspect)
    inspect_networks
    ;;
  *)
    echo "Usage: $0 {create|remove|inspect}"
    echo ""
    echo "  create   — Create all networks (idempotent)"
    echo "  remove   — Remove all networks (only if no containers attached)"
    echo "  inspect  — Show network status"
    exit 1
    ;;
esac
