#!/usr/bin/env bash
###############################################################################
# HOSTINGER VPS — EDGE DEPLOYMENT SCRIPT
# ==========================================
# Deploys the full Hostinger edge stack in the correct order:
#   1. Prune (clean up old/unused resources)
#   2. Create shared Docker networks
#   3. Deploy Traefik (public edge router)
#   4. Deploy essential services (FRGops stack)
#   5. Deploy automation services (n8n + webhooks)
#   6. Deploy AI services (LiteLLM + MinIO)
#   7. Verify all health checks pass
#   8. Test routes to Hetzner backend
#   9. Show resource usage
#
# USAGE:
#   sudo ./hostinger-edge-deploy.sh [--skip-prune] [--skip-verify]
#
# PREREQUISITES:
#   - Docker and Docker Compose v2 installed
#   - Tailscale connected (verify with `tailscale status`)
#   - .env file present in the hostinger directory with all required vars
#   - Cloudflare API token with DNS:Edit permission
#
# ROLLBACK:
#   If deployment fails, run:
#     docker compose -f compose/frgops-essential.yml down
#     docker compose -f compose/automation-edge.yml down
#     docker compose -f compose/ai-edge.yml down
#     docker compose -f traefik/docker-compose.yml down
#
# RESOURCE WARNING:
#   This stack is designed for 4-8 vCPU / 8-16 GB RAM VPS.
#   If your VPS is smaller, reduce memory limits in compose files first.
###############################################################################

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOSTINGER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$HOSTINGER_DIR/compose"
TRAEFIK_DIR="$HOSTINGER_DIR/traefik"
SCRIPTS_DIR="$HOSTINGER_DIR/scripts"
ENV_FILE="$HOSTINGER_DIR/.env"

# Hetzner Tailscale IP (for route testing)
HETZNER_TS_IP="100.121.230.28"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Argument Parsing ───────────────────────────────────────────────────────────

SKIP_PRUNE=false
SKIP_VERIFY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-prune) SKIP_PRUNE=true; shift ;;
    --skip-verify) SKIP_VERIFY=true; shift ;;
    --help)
      echo "Usage: $0 [--skip-prune] [--skip-verify]"
      echo ""
      echo "  --skip-prune    Skip the initial cleanup/prune step"
      echo "  --skip-verify   Skip the final verification step"
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      echo "Usage: $0 [--skip-prune] [--skip-verify]"
      exit 1
      ;;
  esac
done

# ── Pre-flight Checks ─────────────────────────────────────────────────────────

preflight_checks() {
  info "Running pre-flight checks..."

  # Must be root
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (or with sudo)."
    exit 1
  fi

  # Docker must be installed
  if ! command -v docker &>/dev/null; then
    error "Docker is not installed.  Install Docker first."
    exit 1
  fi

  # Docker Compose v2 must be available
  if ! docker compose version &>/dev/null; then
    error "Docker Compose v2 is not available.  Install docker compose plugin."
    exit 1
  fi

  # .env file must exist
  if [[ ! -f "$ENV_FILE" ]]; then
    warn ".env file not found at $ENV_FILE"
    warn "Creating template .env file..."
    cat > "$ENV_FILE" << 'ENVEOF'
# =============================================================================
# HOSTINGER VPS — ENVIRONMENT VARIABLES
# =============================================================================
# REQUIRED: Cloudflare API token for Let's Encrypt DNS-01 challenge
CF_API_TOKEN=your_cloudflare_api_token_here

# REQUIRED: Database passwords
FRGOPS_DB_PASSWORD=change_me_now
FRGOPS_SECRET_KEY_BASE=change_me_now
FRGCRM_SECRET_KEY_BASE=change_me_now
CHATWOOT_SECRET_KEY_BASE=change_me_now
DOCUSEAL_SECRET_KEY_BASE=change_me_now

# REQUIRED: n8n encryption key
N8N_ENCRYPTION_KEY=change_me_now

# REQUIRED: LiteLLM
LITELLM_PROXY_KEY=sk-litellm-proxy-key
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GEMINI_API_KEY=

# REQUIRED: MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=change_me_now

# OPTIONAL: Traefik dashboard auth
DASHBOARD_USERS=admin:$(openssl passwd -apr1)

# OPTIONAL: Webhook receiver
WEBHOOK_RECEIVER_SECRET=
WEBHOOK_RECEIVER_IMAGE=ghcr.io/wheeler-ai/webhook-receiver:latest
ENVEOF
    echo ""
    warn "EDIT $ENV_FILE with real values before running this script."
    echo ""
    exit 1
  fi

  # Source the .env file
  set -a
  source "$ENV_FILE"
  set +a

  # Validate required variables
  local required_vars=(
    "CF_API_TOKEN"
    "FRGOPS_DB_PASSWORD"
  )

  local missing=false
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" || "${!var}" == "change_me_now" || "${!var}" == "your_cloudflare_api_token_here" ]]; then
      error "Required env var '$var' is missing or still set to default."
      missing=true
    fi
  done

  if $missing; then
    error "Fix the .env file and re-run."
    exit 1
  fi

  # Tailscale must be connected
  if ! command -v tailscale &>/dev/null || ! tailscale status &>/dev/null; then
    warn "Tailscale is not connected.  Hetzner routes WILL fail."
    warn "Continuing with local services only..."
  fi

  ok "Pre-flight checks passed."
  echo ""
}

# ── Step 1: Prune ─────────────────────────────────────────────────────────────

step_prune() {
  info "=== STEP 1: PRUNE UNUSED RESOURCES ==="
  if "$SKIP_PRUNE"; then
    info "Skipping prune (--skip-prune flag set)."
  else
    bash "$SCRIPTS_DIR/hostinger-prune.sh" || true
  fi
  echo ""
}

# ── Step 2: Create Networks ───────────────────────────────────────────────────

step_networks() {
  info "=== STEP 2: CREATE SHARED DOCKER NETWORKS ==="

  # traefik-public — ALL services that Traefik routes to must be on this network
  if docker network inspect traefik-public &>/dev/null; then
    ok "Network 'traefik-public' already exists."
  else
    docker network create \
      --driver bridge \
      --subnet 172.20.0.0/24 \
      --label "app=traefik-edge" \
      --label "managed-by=hostinger-edge-deploy" \
      traefik-public
    ok "Created network 'traefik-public' (172.20.0.0/24)."
  fi
  echo ""
}

# ── Step 3: Deploy Traefik ────────────────────────────────────────────────────

step_traefik() {
  info "=== STEP 3: DEPLOY TRAEFIK (PUBLIC EDGE ROUTER) ==="

  cd "$TRAEFIK_DIR"
  docker compose --env-file "$ENV_FILE" up -d --remove-orphans
  cd "$HOSTINGER_DIR"

  ok "Traefik deployed.  Checking health..."

  # Wait for Traefik to be healthy
  local retries=0
  local max_retries=12  # 2 minutes total
  while [[ $retries -lt $max_retries ]]; do
    if docker ps --format '{{.Status}}' --filter "name=traefik-edge" 2>/dev/null | grep -q "(healthy)"; then
      ok "Traefik is healthy."
      break
    fi
    sleep 10
    ((retries++))
  done

  if [[ $retries -eq $max_retries ]]; then
    warn "Traefik health check timed out.  Check docker logs: docker logs traefik-edge"
  fi

  echo ""
}

# ── Step 4: Deploy FRGops Stack ──────────────────────────────────────────────

step_frgops() {
  info "=== STEP 4: DEPLOY FRGOPS ESSENTIAL STACK ==="

  cd "$COMPOSE_DIR"
  docker compose --env-file "$ENV_FILE" -f frgops-essential.yml up -d --remove-orphans
  cd "$HOSTINGER_DIR"

  ok "FRGops stack deployed.  Waiting for services to become healthy..."

  # Wait for critical services (Postgres + Redis are the foundation)
  local services=("frgops-postgres" "frgops-redis")
  for svc in "${services[@]}"; do
    local retries=0
    while [[ $retries -lt 18 ]]; do  # 3 minutes max per service
      if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$svc"; then
        ok "  $svc is running."
        break
      fi
      sleep 10
      ((retries++))
    done
  done

  echo ""
}

# ── Step 5: Deploy Automation Stack ──────────────────────────────────────────

step_automation() {
  info "=== STEP 5: DEPLOY AUTOMATION EDGE (n8n + Webhooks) ==="

  cd "$COMPOSE_DIR"
  docker compose --env-file "$ENV_FILE" -f automation-edge.yml up -d --remove-orphans
  cd "$HOSTINGER_DIR"

  ok "Automation stack deployed."
  echo ""
}

# ── Step 6: Deploy AI Stack ──────────────────────────────────────────────────

step_ai() {
  info "=== STEP 6: DEPLOY AI EDGE (LiteLLM + MinIO) ==="

  cd "$COMPOSE_DIR"
  docker compose --env-file "$ENV_FILE" -f ai-edge.yml up -d --remove-orphans
  cd "$HOSTINGER_DIR"

  ok "AI stack deployed."
  echo ""
}

# ── Step 7: Verify Health Checks ─────────────────────────────────────────────

step_verify_health() {
  info "=== STEP 7: VERIFY ALL HEALTH CHECKS ==="

  if "$SKIP_VERIFY"; then
    info "Skipping verification (--skip-verify flag set)."
    return
  fi

  local expected_containers=(
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
  )

  local all_healthy=true
  for container in "${expected_containers[@]}"; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$container"; then
      local status
      status=$(docker ps --format '{{.Status}}' --filter "name=$container" 2>/dev/null)
      if echo "$status" | grep -qi "healthy"; then
        ok "  $container — HEALTHY ($status)"
      elif echo "$status" | grep -qi "unhealthy"; then
        error "  $container — UNHEALTHY ($status)"
        all_healthy=false
      else
        warn "  $container — RUNNING (status: $status)"
      fi
    else
      warn "  $container — NOT RUNNING"
      all_healthy=false
    fi
  done

  echo ""
  if $all_healthy; then
    ok "All containers are healthy!"
  else
    warn "Some containers are not healthy.  Check docker logs for details."
    warn "  docker logs <container_name> --tail 50"
  fi

  echo ""
}

# ── Step 8: Test Hetzner Routes ──────────────────────────────────────────────

step_test_hetzner() {
  info "=== STEP 8: TEST ROUTES TO HETZNER BACKEND ==="

  if "$SKIP_VERIFY"; then
    info "Skipping Hetzner route testing (--skip-verify flag set)."
    return
  fi

  # Check Tailscale connectivity to Hetzner
  if ! tailscale status 2>/dev/null | grep -q "$HETZNER_TS_IP"; then
    warn "Cannot reach Hetzner via Tailscale ($HETZNER_TS_IP)."
    warn "Skipping Hetzner route tests."
    echo ""
    return
  fi

  info "Tailscale connectivity to Hetzner confirmed.  Testing HTTP routes..."

  # Use Traefik's internal routing to test (via curl to local Traefik)
  local hetzner_routes=(
    "predictionradar.wheeler.ai:8098"
    "ravynai.wheeler.ai:8007"
    "superset.wheeler.ai:8088"
    "healthchecks.wheeler.ai:3130"
    "changedetect.wheeler.ai:5000"
    "grafana.wheeler.ai:3002"
    "uptime.wheeler.ai:3001"
  )

  for route in "${hetzner_routes[@]}"; do
    local host="${route%%:*}"
    local port="${route##*:}"
    # Test direct Tailscale connection
    if curl -sf --max-time 5 "http://${HETZNER_TS_IP}:${port}" -H "Host: ${host}" &>/dev/null; then
      ok "  $host → Tailscale:${port} — REACHABLE"
    else
      warn "  $host → Tailscale:${port} — UNREACHABLE (expected if service is stopped)"
    fi
  done

  echo ""
}

# ── Step 9: Show Resource Usage ───────────────────────────────────────────────

step_resources() {
  info "=== STEP 9: RESOURCE USAGE ==="

  echo ""
  info "--- Container Resources ---"
  docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || true

  echo ""
  info "--- Host Resources ---"
  echo "CPU:"
  top -bn1 | grep "Cpu(s)" | awk '{print "  User: " $2 "  System: " $4 "  Idle: " $8}'
  echo "Memory:"
  free -h | grep -E "^Mem:" | awk '{printf "  Total: %s  Used: %s  Free: %s  Available: %s\n", $2, $3, $4, $7}'
  echo "Disk:"
  df -h / | tail -1 | awk '{printf "  Total: %s  Used: %s  Avail: %s  Use%%: %s\n", $2, $3, $4, $5}'
  echo "Docker:"
  echo "  $(docker ps -q | wc -l) running containers"
  echo "  $(docker images -q | wc -l) images"
  echo "  $(docker volume ls -q | wc -l) volumes"
  echo ""

  # Warning if resource usage is high
  local mem_used_percent
  mem_used_percent=$(free | grep Mem | awk '{printf "%.0f", ($3/$2)*100}')
  if [[ "$mem_used_percent" -gt 80 ]]; then
    warn "Memory usage is at ${mem_used_percent}% — consider reducing container memory limits."
  elif [[ "$mem_used_percent" -gt 60 ]]; then
    warn "Memory usage is at ${mem_used_percent}% — monitor closely."
  else
    ok "Memory usage at ${mem_used_percent}% — within acceptable range."
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "========================================================================"
echo " HOSTINGER VPS — EDGE DEPLOYMENT"
echo " Date: $(date)"
echo "========================================================================"
echo ""

# Run all steps
preflight_checks
step_prune
step_networks
step_traefik
step_frgops
step_automation
step_ai
step_verify_health
step_test_hetzner
step_resources

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "========================================================================"
echo " DEPLOYMENT COMPLETE"
echo "========================================================================"
echo ""
info "Traefik dashboard:  https://traefik.wheeler.ai (Tailscale/internal only)"
info "FRGops:             https://frgops.wheeler.ai"
info "FRGCRM:             https://frgcrm.wheeler.ai"
info "Chatwoot:           https://chatwoot.wheeler.ai"
info "n8n:                https://n8n.wheeler.ai"
info "Docuseal:           https://docuseal.wheeler.ai"
info "LiteLLM:            https://litellm.wheeler.ai"
info "MinIO:              https://minio.wheeler.ai"
info "Webhooks:           https://webhooks.wheeler.ai"
echo ""
info "Hetzner-proxied services (via Tailscale):"
info "  Prediction Radar: https://predictionradar.wheeler.ai"
info "  RavynAI:          https://ravynai.wheeler.ai"
info "  Superset:         https://superset.wheeler.ai"
info "  Healthchecks:     https://healthchecks.wheeler.ai"
info "  ChangeDetection:  https://changedetect.wheeler.ai"
info "  Grafana:          https://grafana.wheeler.ai"
info "  Uptime Kuma:      https://uptime.wheeler.ai"
echo ""
info "Management commands:"
info "  View logs:        docker logs <container_name> --tail 50"
info "  Restart all:      cd $HOSTINGER_DIR && ./scripts/hostinger-edge-deploy.sh"
info "  Stop all:         cd $HOSTINGER_DIR && ./scripts/hostinger-edge-down.sh"
info "  Prune:            cd $HOSTINGER_DIR && ./scripts/hostinger-prune.sh"
echo ""
echo "========================================================================"

exit 0
