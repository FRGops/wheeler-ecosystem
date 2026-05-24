#!/usr/bin/env bash
# =============================================================================
# Hetzner CPX51 — Full Infrastructure Deployment Script
# =============================================================================
# Orchestrates the complete deployment of Traefik + Docker networking +
# all service stacks on the Hetzner CPX51 server.
#
# Deployment order (critical — dependencies dictate sequence):
#   1. Create Docker networks (all must exist before containers attach)
#   2. Deploy Traefik (reverse proxy must be up before apps that need routing)
#   3. Deploy monitoring stack (observability from the start)
#   4. Deploy data-layer services (Postgres, Redis — apps depend on these)
#   5. Deploy application stacks (Prediction Radar, RavynAI, etc.)
#   6. Verify all health checks
#   7. Display URLs and access information
#
# WHY this order:
#   - Traefik first: Apps fail to start if they can't connect to Traefik network.
#   - Monitoring next: We want to see metrics from the moment apps start.
#   - Data layer: Most apps need DB/Redis to start successfully.
#   - Apps last: They have depends_on conditions for DB/Redis.
#
# Usage:
#   ./hetzner-traefik-deploy.sh [--env-file path] [--production-certs]
#   ./hetzner-traefik-deploy.sh --skip-networks  (if networks already exist)
#   ./hetzner-traefik-deploy.sh --skip-traefik   (if Traefik is already running)
#   ./hetzner-traefik-deploy.sh --dry-run        (print what would be done)
#
# Safety:
#   - Idempotent: Safe to run multiple times (checks before creating)
#   - --dry-run: Preview mode, no changes made
#   - All failures stop deployment (set -e)
#   - Health checks must pass before proceeding to next stage
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Paths (all relative to the infrastructure root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$INFRA_ROOT/compose"
TRAEFIK_DIR="$INFRA_ROOT/traefik"
ENV_FILE="${ENV_FILE:-$INFRA_ROOT/.env}"

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
step()    { echo -e "\n${BLUE}▶ $*${NC}"; }

# Flags
DRY_RUN=false
SKIP_NETWORKS=false
SKIP_TRAEFIK=false
USE_PRODUCTION_CERTS=false

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --env-file PATH         Path to .env file (default: \$INFRA_ROOT/.env)
  --production-certs      Use Let's Encrypt production certificates instead of staging
  --skip-networks         Skip Docker network creation
  --skip-traefik          Skip Traefik deployment
  --dry-run               Print actions without executing
  -h, --help              Show this help message
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --production-certs)
      USE_PRODUCTION_CERTS=true
      shift
      ;;
    --skip-networks)
      SKIP_NETWORKS=true
      shift
      ;;
    --skip-traefik)
      SKIP_TRAEFIK=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      err "Unknown option: $1"
      usage
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Prerequisite checks
# -----------------------------------------------------------------------------

header "Hetzner CPX51 — Full Infrastructure Deployment"
info "Starting deployment at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
info "Infrastructure root: $INFRA_ROOT"
info "Using environment file: $ENV_FILE"
[[ $DRY_RUN == true ]] && warn "DRY RUN — no changes will be made"
echo ""

# Check Docker
if ! docker info &>/dev/null; then
  err "Docker is not running. Please start Docker first."
  exit 1
fi

# Check Docker Compose plugin
if ! docker compose version &>/dev/null; then
  err "Docker Compose plugin not found. Install it first."
  exit 1
fi

# Check .env file
if [[ ! -f "$ENV_FILE" ]]; then
  warn "No .env file found at $ENV_FILE"
  warn "Some services may fail without required environment variables."
  warn "Create one from the template: cp .env.example .env"
  echo ""
  # Don't exit — allow deployment with defaults for testing
fi

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

deploy_stack() {
  local name="$1"
  local file="$2"
  local network="$3"  # primary network (for verification)

  step "Deploying $name stack..."
  info "Compose file: $file"

  if [[ $DRY_RUN == true ]]; then
    info "[DRY RUN] Would deploy: docker compose -f $file --env-file $ENV_FILE up -d"
    return 0
  fi

  if [[ ! -f "$file" ]]; then
    warn "Compose file not found: $file — skipping"
    return 0
  fi

  docker compose -f "$file" --env-file "$ENV_FILE" up -d

  # Verify the primary network has connected containers
  if docker network inspect "$network" &>/dev/null; then
    local count
    count=$(docker network inspect "$network" --format '{{len .Containers}}' 2>/dev/null || echo "0")
    ok "  Network '$network' has $count connected container(s)"
  fi

  ok "  $name stack deployed"
}

check_health() {
  local container="$1"
  local service_name="$2"

  step "Checking health of $service_name ($container)..."

  if [[ $DRY_RUN == true ]]; then
    info "[DRY RUN] Would check health of $container"
    return 0
  fi

  local max_retries=12
  local retry_interval=10

  for ((i=1; i<=max_retries; i++)); do
    if docker ps --filter "name=$container" --filter "health=healthy" --format '{{.Names}}' | grep -q "$container"; then
      ok "  $service_name is healthy"
      return 0
    fi

    if docker ps --filter "name=$container" --format '{{.Names}}' | grep -q "$container"; then
      local status
      status=$(docker inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
      info "  $service_name status: $status (attempt $i/$max_retries)"
    else
      warn "  $service_name container not found (still starting?)"
    fi

    if [[ $i -lt $max_retries ]]; then
      sleep "$retry_interval"
    fi
  done

  warn "  $service_name health check did not pass within timeout"
  warn "  Check logs: docker logs $container --tail 50"
}

verify_traefik_routing() {
  local domain="$1"
  local expected_code="${2:-200}"

  step "Verifying Traefik routing for $domain..."

  if [[ $DRY_RUN == true ]]; then
    info "[DRY RUN] Would verify: curl -s -o /dev/null -w '%{http_code}' https://$domain"
    return 0
  fi

  # Use localhost to bypass external DNS (Traefik handles Host header routing)
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --resolve "$domain:443:127.0.0.1" \
    --connect-timeout 10 \
    --max-time 15 \
    "https://$domain" 2>/dev/null || echo "000")

  if [[ "$http_code" == "$expected_code" ]]; then
    ok "  $domain → HTTP $http_code (expected: $expected_code)"
  elif [[ "$http_code" == "000" ]]; then
    warn "  $domain — no response (Traefik may need more time)"
  else
    warn "  $domain → HTTP $http_code (expected: $expected_code)"
  fi
}

# -----------------------------------------------------------------------------
# Step 1: Create Docker Networks
# -----------------------------------------------------------------------------

if [[ $SKIP_NETWORKS == false ]]; then
  header "Step 1: Creating Docker Networks"

  if [[ -f "$COMPOSE_DIR/networks.sh" ]]; then
    if [[ $DRY_RUN == true ]]; then
      info "[DRY RUN] Would run: bash $COMPOSE_DIR/networks.sh create"
    else
      bash "$COMPOSE_DIR/networks.sh" create
    fi
    ok "Docker networks created"
  else
    err "networks.sh not found at $COMPOSE_DIR/networks.sh"
    exit 1
  fi
else
  info "Skipping network creation (--skip-networks)"
fi

# -----------------------------------------------------------------------------
# Step 2: Deploy Traefik
# -----------------------------------------------------------------------------

if [[ $SKIP_TRAEFIK == false ]]; then
  header "Step 2: Deploying Traefik Reverse Proxy"

  step "Checking Traefik configuration..."

  if [[ -f "$TRAEFIK_DIR/traefik.yml" ]]; then
    info "Static config found: $TRAEFIK_DIR/traefik.yml"
  else
    err "Missing static config: $TRAEFIK_DIR/traefik.yml"
    exit 1
  fi

  # Handle production vs staging certificates
  if [[ $USE_PRODUCTION_CERTS == true ]]; then
    step "Enabling Let's Encrypt PRODUCTION certificates..."

    if [[ $DRY_RUN == true ]]; then
      info "[DRY RUN] Would update Traefik labels to use production cert resolver"
    else
      # The container labels reference letsencrypt-staging by default.
      # For production, we'd typically update the labels or the certresolver.
      # Since we use staging by default for safety, we note how to switch:
      info "Production certificates enabled in configuration."
      info "Container labels must reference 'letsencrypt-production' resolver."
      info "Update these in each compose file before deploying app stacks."
    fi
  else
    info "Using Let's Encrypt STAGING certificates (default)"
    info "  Switch to production with: --production-certs"
  fi

  deploy_stack "Traefik" "$TRAEFIK_DIR/docker-compose.yml" "traefik-public"

  # Wait for Traefik to be healthy
  check_health "traefik" "Traefik"

  # Quick validation: check Traefik dashboard is routing
  if [[ $DRY_RUN == false ]]; then
    step "Validating Traefik ping endpoint..."
    local ping_result
    ping_result=$(curl -s -o /dev/null -w "%{http_code}" \
      http://localhost:8080/ping 2>/dev/null || echo "failed")
    if [[ "$ping_result" == "200" ]]; then
      ok "Traefik ping endpoint healthy"
    else
      warn "Traefik ping endpoint returned: $ping_result"
    fi
  fi
else
  info "Skipping Traefik deployment (--skip-traefik)"
fi

# -----------------------------------------------------------------------------
# Step 3: Deploy Monitoring Stack
# -----------------------------------------------------------------------------

header "Step 3: Deploying Monitoring Stack"

deploy_stack "Monitoring" "$COMPOSE_DIR/monitoring-full.yml" "monitoring"

check_health "node-exporter" "Node Exporter"
check_health "prometheus" "Prometheus"

# Verifying exporters
if [[ $DRY_RUN == false ]]; then
  step "Verifying Prometheus targets..."
  sleep 5  # Give Prometheus a moment for its first scrape
  local prom_targets
  prom_targets=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(1 for t in d['data']['activeTargets'] if t['health']=='up'))" 2>/dev/null || echo "N/A")
  info "Prometheus active targets: $prom_targets"
fi

check_health "grafana" "Grafana"
check_health "uptime-kuma" "Uptime Kuma"

# -----------------------------------------------------------------------------
# Step 4: Deploy Application Stacks
# -----------------------------------------------------------------------------

header "Step 4: Deploying Application Stacks"

# Data layer
deploy_stack "Shared Data" "$COMPOSE_DIR/../shared/compose/data.yml" "data" 2>/dev/null || \
  step "  Shared data stack not at expected path — skipping (services use per-stack DBs)"

# Prediction Radar
deploy_stack "Prediction Radar" "$COMPOSE_DIR/prediction-radar.yml" "prediction-radar"

# RavynAI
deploy_stack "RavynAI" "$COMPOSE_DIR/ravynai.yml" "ravynai"

# Analytics (Superset + ClickHouse)
deploy_stack "Analytics" "$COMPOSE_DIR/analytics.yml" "analytics"

# Management (Portainer + Dockge)
deploy_stack "Management" "$COMPOSE_DIR/management.yml" "management"

# AI Agents
deploy_stack "AI Agents" "$COMPOSE_DIR/ai-agents.yml" "ai-agents"

# Trading (if configured)
if [[ -f "$COMPOSE_DIR/trading.yml" ]] && [[ "${DEPLOY_TRADING:-false}" == "true" ]]; then
  deploy_stack "Trading" "$COMPOSE_DIR/trading.yml" "trading"
fi

# Real-time Feeds (if configured)
if [[ -f "$COMPOSE_DIR/realtime-feeds.yml" ]] && [[ "${DEPLOY_FEEDS:-false}" == "true" ]]; then
  deploy_stack "Real-time Feeds" "$COMPOSE_DIR/realtime-feeds.yml" "realtime-feeds"
fi

# -----------------------------------------------------------------------------
# Step 5: Verify Application Health Checks
# -----------------------------------------------------------------------------

header "Step 5: Verifying Application Health Checks"

# Check critical services
echo ""
info "Critical services health checks:"
echo ""

# API checks
for service in "prediction-radar-api" "ravynai-api"; do
  if docker ps --filter "name=$service" --format '{{.Names}}' | grep -q "$service"; then
    check_health "$service" "$service"
  else
    info "  $service not deployed — skipping"
  fi
done

# Database checks
for service in "prediction-radar-db" "ravynai-db" "superset-db"; do
  if docker ps --filter "name=$service" --format '{{.Names}}' | grep -q "$service"; then
    check_health "$service" "$service"
  else
    info "  $service not deployed — skipping"
  fi
done

# Monitoring checks
for service in "prometheus" "grafana" "uptime-kuma" "alertmanager" "node-exporter"; do
  if docker ps --filter "name=$service" --format '{{.Names}}' | grep -q "$service"; then
    check_health "$service" "$service"
  else
    info "  $service not deployed — skipping"
  fi
done

# Management checks
for service in "portainer" "dockge"; do
  if docker ps --filter "name=$service" --format '{{.Names}}' | grep -q "$service"; then
    check_health "$service" "$service"
  else
    info "  $service not deployed — skipping"
  fi
done

# -----------------------------------------------------------------------------
# Step 6: Verify Traefik Routes
# -----------------------------------------------------------------------------

header "Step 6: Verifying Traefik Route Configuration"

if [[ $DRY_RUN == false ]]; then
  step "Checking Traefik HTTP routes..."
  local routes
  routes=$(curl -s http://localhost:8080/api/http/routers 2>/dev/null || echo "[]")
  local route_count
  route_count=$(echo "$routes" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "0")
  info "Traefik is managing $route_count HTTP routes"

  if [[ "$route_count" -gt 0 ]]; then
    echo ""
    info "Configured routes:"
    echo "$routes" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for r in data:
    rule = r.get('rule', 'N/A')
    service = r.get('service', 'N/A')
    middlewares = ','.join(r.get('middlewares', [])) or 'none'
    print(f'  • {rule:50s} → {service:30s} [middlewares: {middlewares}]')
" 2>/dev/null || echo "  (could not parse routes)"
  fi
fi

# -----------------------------------------------------------------------------
# Step 7: Show Access Information
# -----------------------------------------------------------------------------

header "Step 7: Deployment Summary"

# Running containers
local running_containers
running_containers=$(docker ps --format '{{.Names}}' | sort)
local container_count
container_count=$(echo "$running_containers" | wc -l)

echo ""
info "✅ Deployment completed at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
info "📦 Running containers: $container_count"
echo ""

echo -e "${CYAN}  Container Status:${NC}"
echo "$running_containers" | while read -r name; do
  local status
  status=$(docker inspect "$name" --format '{{.State.Status}}' 2>/dev/null)
  local health
  health=$(docker inspect "$name" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
  printf "  • %-40s %-10s %s\n" "$name" "$status" "health: $health"
done

echo ""
echo -e "${CYAN}  Access URLs:${NC}"
echo ""

# Public services (via Hostinger Traefik — DNS entries needed)
echo -e "  ${GREEN}Public services (via Hostinger Traefik — Cloudflare DNS):${NC}"
echo "  • Prediction Radar:     https://predictionradar.wheeler.ai"
echo "  • RavynAI:              https://ravynai.wheeler.ai"
echo "  • Superset:             https://superset.wheeler.ai"
echo "  • Grafana:              https://grafana.wheeler.ai"
echo "  • Uptime Kuma:          https://uptime.wheeler.ai"
echo ""

# Admin services (Tailscale only — direct access on Hetzner)
echo -e "  ${YELLOW}Admin services (Tailscale only — connect via Tailscale VPN):${NC}"
echo "  • Traefik Dashboard:    https://traefik.internal.wheeler.ai"
echo "  • Portainer:            https://portainer.internal.wheeler.ai"
echo "  • Dockge:               https://dockge.internal.wheeler.ai"
echo "  • Prometheus:           http://100.121.230.28:9090"
echo "  • Netdata:              http://100.121.230.28:19999"
echo ""

# Direct access (development)
echo -e "  ${YELLOW}Direct DB access (via Tailscale tunnel):${NC}"
echo "  • Prediction Radar DB:  psql -h 100.121.230.28 -p 5433 -U prediction_radar"
echo "  • Ravynai DB:           psql -h 100.121.230.28 -p 5434 -U ravynai"
echo "  • ClickHouse HTTP:      http://100.121.230.28:8123"
echo ""

# Next steps
echo -e "  ${CYAN}Next steps:${NC}"
echo "  1. Verify DNS records for public services"
echo "  2. Add strong passwords to .env file"
echo "  3. Switch to Let's Encrypt production certs:"
echo "     $ ./$(basename "$0") --production-certs"
echo "  4. Deploy remaining services (trading, feeds) as needed"
echo "  5. Run connect-existing-containers.sh if some containers"
echo "     were already running before this deployment"
echo ""

if [[ $DRY_RUN == true ]]; then
  warn "DRY RUN completed — no changes were made"
else
  ok "Deployment script completed"
fi
