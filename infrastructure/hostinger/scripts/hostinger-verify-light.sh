#!/usr/bin/env bash
###############################################################################
# HOSTINGER VPS — VERIFY LIGHTWEIGHT STATUS
# ============================================
# Verification script to confirm the Hostinger VPS is running lean and correctly.
#
# CHECKS:
#   1. No heavy services running (Phase 1 migration validation)
#   2. Resource usage within limits (CPU < 50%, RAM < 60%)
#   3. All configured routes return HTTP 200
#   4. Tailscale connectivity to Hetzner backend
#   5. Only expected ports (80, 443) are publicly listening
#   6. Docker container health
#   7. Disk space warning (>20% free)
#   8. Certificate expiry check
#
# EXIT CODES:
#   0 — All checks pass (or only warnings)
#   1 — Critical checks failed
#
# USAGE:
#   sudo ./hostinger-verify-light.sh [--strict] [--verbose]
#
#   --strict   Fail on warnings, not just errors
#   --verbose  Show detailed output for each check
###############################################################################

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

HETZNER_TS_IP="100.121.230.28"
HOSTINGER_TS_IP="100.98.163.17"
DOMAIN="wheeler.ai"

# Resource thresholds (for a 4-8 vCPU / 8-16 GB VPS)
CPU_THRESHOLD=50     # Max acceptable CPU usage (%)
RAM_THRESHOLD=60     # Max acceptable RAM usage (%)
DISK_THRESHOLD=80    # Max acceptable disk usage (%)
CONNECTION_THRESHOLD=500  # Max concurrent TCP connections

# Expected public listening ports (must only be 80 and 443)
EXPECTED_PUBLIC_PORTS="80 443"

# Heavy services that should have been migrated to Hetzner
HEAVY_SERVICES=(
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
  "healthchecks"  # migrated to Hetzner
)

# Expected light services
LIGHT_SERVICES=(
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

# Routes to test (local and Hetzner-proxied)
# Format: "hostname:expected_status"
LOCAL_ROUTES=(
  "frgops.wheeler.ai:200"
  "chatwoot.wheeler.ai:200"
  "n8n.wheeler.ai:200"
  "docuseal.wheeler.ai:200"
  "litellm.wheeler.ai:200"
  "minio.wheeler.ai:200"
)

HETZNER_ROUTES=(
  "predictionradar.wheeler.ai:200"
  "ravynai.wheeler.ai:200"
  "superset.wheeler.ai:200"
  "healthchecks.wheeler.ai:200"
  "changedetect.wheeler.ai:200"
  "grafana.wheeler.ai:200"
  "uptime.wheeler.ai:200"
)

# ── Globals ────────────────────────────────────────────────────────────────────

STRICT=false
VERBOSE=false
PASSES=0
WARNINGS=0
FAILURES=0
TEST_COUNT=0

# ── Colors ────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()     { echo -e "${BLUE}[INFO]${NC}    $*"; }
ok()       { echo -e "${GREEN}[PASS]${NC}   $*"; ((PASSES++)); ((TEST_COUNT++)); }
warn()     { echo -e "${YELLOW}[WARN]${NC}   $*"; ((WARNINGS++)); ((TEST_COUNT++)); }
error()    { echo -e "${RED}[FAIL]${NC}   $*"; ((FAILURES++)); ((TEST_COUNT++)); }
verbose()  { if $VERBOSE; then echo "         $*"; fi; }
header()   { echo ""; echo "─── $* ───"; echo ""; }

# ── Argument Parsing ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)  STRICT=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --help)
      echo "Usage: $0 [--strict] [--verbose]"
      exit 0
      ;;
    *) error "Unknown option: $1"; exit 1 ;;
  esac
done

# ══════════════════════════════════════════════════════════════════════════════
# VERIFICATION FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

# ── Check 1: No Heavy Services ────────────────────────────────────────────────

check_no_heavy_services() {
  header "CHECK 1: No Heavy Services"

  local found_heavy=false
  for service in "${HEAVY_SERVICES[@]}"; do
    # Check Docker containers
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi "$service"; then
      error "Heavy service RUNNING: $(docker ps --format '{{.Names}}' | grep -i "$service")"
      found_heavy=true
    fi
    # Also check stopped containers (might need cleanup)
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qi "$service"; then
      verbose "Heavy service exists (stopped): $(docker ps -a --format '{{.Names}}' | grep -i "$service")"
    fi
  done

  # Check for Docker networks from heavy stacks
  for network in prediction-radar ravynai analytics monitoring osint trading messaging management; do
    if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "$network"; then
      warn "Leftover network from heavy stack: $network"
    fi
  done

  # Check for Docker volumes from heavy stacks
  for vol_pattern in prediction ravynai clickhouse superset spiderfoot; do
    if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "$vol_pattern"; then
      warn "Leftover volume from heavy stack: $(docker volume ls --format '{{.Name}}' | grep "$vol_pattern")"
    fi
  done

  if ! $found_heavy; then
    ok "No heavy services running.  Phase 1 migration confirmed."
  fi
}

# ── Check 2: Resource Usage ──────────────────────────────────────────────────

check_resource_usage() {
  header "CHECK 2: Resource Usage"

  # CPU
  local cpu_idle
  cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk -F',' '{print $4}' | awk '{print $1}')
  local cpu_used
  cpu_used=$(echo "100 - $cpu_idle" | bc -l | xargs printf "%.0f")
  if (( $(echo "$cpu_used < $CPU_THRESHOLD" | bc -l) )); then
    ok "CPU usage: ${cpu_used}% (threshold: <${CPU_THRESHOLD}%)"
  else
    warn "CPU usage: ${cpu_used}% (threshold: <${CPU_THRESHOLD}%) — check for runaway processes"
  fi
  verbose "  CPU idle: ${cpu_idle}%"

  # RAM
  local mem_total mem_used mem_percent
  mem_total=$(free -m | awk '/^Mem:/{print $2}')
  mem_used=$(free -m | awk '/^Mem:/{print $3}')
  mem_percent=$(free | awk '/^Mem:/{printf "%.0f", ($3/$2)*100}')
  if [[ "$mem_percent" -lt $RAM_THRESHOLD ]]; then
    ok "RAM usage: ${mem_percent}% (${mem_used}MB / ${mem_total}MB) (threshold: <${RAM_THRESHOLD}%)"
  else
    warn "RAM usage: ${mem_percent}% (${mem_used}MB / ${mem_total}MB) (threshold: <${RAM_THRESHOLD}%)"
  fi

  # Swap
  local swap_total swap_used
  swap_total=$(free -m | awk '/^Swap:/{print $2}')
  swap_used=$(free -m | awk '/^Swap:/{print $3}')
  if [[ "$swap_total" -gt 0 ]]; then
    if [[ "$swap_used" -gt 0 ]]; then
      warn "Swap is active: ${swap_used}MB / ${swap_total}MB — indicates memory pressure"
    else
      ok "Swap: ${swap_total}MB available, 0MB used"
    fi
  else
    info "No swap configured."
  fi

  # Disk
  local disk_used_percent
  disk_used_percent=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
  local disk_avail
  disk_avail=$(df -h / | tail -1 | awk '{print $4}')
  if [[ "$disk_used_percent" -lt $DISK_THRESHOLD ]]; then
    ok "Disk usage: ${disk_used_percent}% (${disk_avail} available) (threshold: <${DISK_THRESHOLD}%)"
  else
    warn "Disk usage: ${disk_used_percent}% (${disk_avail} available) (threshold: <${DISK_THRESHOLD}%)"
  fi

  # Docker containers
  local container_count
  container_count=$(docker ps -q | wc -l)
  info "Running containers: $container_count"

  # TCP connections (rough edge server load indicator)
  local tcp_conns
  tcp_conns=$(ss -tun | grep -c ESTAB 2>/dev/null || echo 0)
  if [[ "$tcp_conns" -lt $CONNECTION_THRESHOLD ]]; then
    ok "TCP connections: $tcp_conns (threshold: <${CONNECTION_THRESHOLD})"
  else
    warn "TCP connections: $tcp_conns (threshold: <${CONNECTION_THRESHOLD}) — high connection count"
  fi

  # Load average
  local load_1m load_5m load_15m cpus
  read -r load_1m load_5m load_15m < /proc/loadavg
  cpus=$(nproc)
  local load_percent
  load_percent=$(echo "$load_1m * 100 / $cpus" | bc)
  if (( $(echo "$load_percent < 70" | bc -l) )); then
    ok "Load average: ${load_1m} / ${load_5m} / ${load_15m} (${cpus} CPUs, ${load_percent}% of 1m load)"
  else
    warn "Load average: ${load_1m} / ${load_5m} / ${load_15m} (${cpus} CPUs, ${load_percent}% of 1m load)"
  fi
}

# ── Check 3: Verify Routes ───────────────────────────────────────────────────

test_route() {
  local host="$1"
  local expected_status="$2"
  local description="$3"

  local actual_status
  actual_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${host}" 2>/dev/null || echo "000")

  if [[ "$actual_status" == "$expected_status" || "$actual_status" == "3"* ]]; then
    # Accept 200 or 3xx redirects
    ok "  $host → HTTP $actual_status (expected $expected_status or 3xx)"
    return 0
  elif [[ "$actual_status" == "000" ]]; then
    warn "  $host → UNREACHABLE (timeout or connection refused)"
    return 1
  elif [[ "$actual_status" == "4"* ]]; then
    warn "  $host → HTTP $actual_status (client error — expected $expected_status)"
    return 1
  elif [[ "$actual_status" == "5"* ]]; then
    warn "  $host → HTTP $actual_status (server error — expected $expected_status)"
    return 1
  else
    warn "  $host → HTTP $actual_status (unexpected — expected $expected_status)"
    return 1
  fi
}

check_routes() {
  header "CHECK 3: Route Connectivity"

  info "Testing local routes..."

  if [[ ${#LOCAL_ROUTES[@]} -eq 0 ]]; then
    warn "No local routes configured for testing."
  fi

  local local_success=0
  for route in "${LOCAL_ROUTES[@]}"; do
    local host="${route%%:*}"
    local expected="${route##*:}"
    if test_route "$host" "$expected" "local"; then
      ((local_success++))
    fi
  done

  if [[ "$local_success" -eq "${#LOCAL_ROUTES[@]}" ]]; then
    ok "All ${#LOCAL_ROUTES[@]} local routes passed."
  elif [[ "$local_success" -gt 0 ]]; then
    warn "${local_success}/${#LOCAL_ROUTES[@]} local routes passed."
  else
    warn "No local routes pass.  Check Traefik and service health."
  fi

  echo ""
  info "Testing Hetzner-proxied routes..."

  # First check Tailscale connectivity
  if ! curl -sf --max-time 3 "http://${HETZNER_TS_IP}:3001" &>/dev/null; then
    warn "Cannot reach Hetzner backend via Tailscale.  Skipping Hetzner route tests."
    return
  fi

  local hetzner_success=0
  for route in "${HETZNER_ROUTES[@]}"; do
    local host="${route%%:*}"
    local expected="${route##*:}"
    if test_route "$host" "$expected" "hetzner"; then
      ((hetzner_success++))
    fi
  done

  if [[ "$hetzner_success" -eq "${#HETZNER_ROUTES[@]}" ]]; then
    ok "All ${#HETZNER_ROUTES[@]} Hetzner routes passed."
  elif [[ "$hetzner_success" -gt 0 ]]; then
    warn "${hetzner_success}/${#HETZNER_ROUTES[@]} Hetzner routes passed."
  else
    info "No Hetzner routes pass (services may be stopped — expected during migration)."
  fi
}

# ── Check 4: Tailscale Connectivity ──────────────────────────────────────────

check_tailscale() {
  header "CHECK 4: Tailscale Connectivity"

  if ! command -v tailscale &>/dev/null; then
    error "Tailscale is not installed."
    return
  fi

  if ! tailscale status &>/dev/null; then
    error "Tailscale is not running."
    return
  fi

  # Show status summary
  local ts_status
  ts_status=$(tailscale status --json 2>/dev/null || tailscale status 2>/dev/null)
  verbose "$ts_status"

  # Check our own IP
  local our_ip
  our_ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
  if [[ "$our_ip" != "unknown" ]]; then
    ok "Tailscale is connected.  Our IP: $our_ip"
    if [[ "$our_ip" == "${HOSTINGER_TS_IP}" ]]; then
      verbose "  IP matches expected Hostinger IP"
    else
      verbose "  Expected IP: ${HOSTINGER_TS_IP}"
    fi
  else
    warn "Could not determine Tailscale IP."
  fi

  # Check connectivity to Hetzner
  if ping -c 1 -W 2 "$HETZNER_TS_IP" &>/dev/null; then
    ok "Hetzner reachable via Tailscale ping (${HETZNER_TS_IP})"
  else
    warn "Hetzner NOT reachable via Tailscale ping (${HETZNER_TS_IP})"
  fi
}

# ── Check 5: Public Ports ───────────────────────────────────────────────────

check_public_ports() {
  header "CHECK 5: Public Port Exposure"

  # Get all listening TCP ports
  local listening_ports
  listening_ports=$(ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || true)

  verbose "All listening TCP ports:"
  verbose "$listening_ports"
  echo ""

  # Check that only 80 and 443 are publicly exposed
  # (We consider ports bound to 0.0.0.0 or :: as "public")
  local public_ports
  public_ports=$(echo "$listening_ports" | grep -E "0\.0\.0\.0:|\[::\]:" | awk '{print $4}' | cut -d: -f2 | sort -n | uniq || true)

  info "Publicly exposed ports: $(echo "$public_ports" | tr '\n' ' ')"

  for port in $public_ports; do
    if echo "$EXPECTED_PUBLIC_PORTS" | grep -qw "$port"; then
      ok "  Port $port — expected (Traefik)"
    else
      error "  Port $port — UNEXPECTED public exposure! Check the service listening on this port."
    fi
  done
}

# ── Check 6: Docker Container Health ────────────────────────────────────────

check_container_health() {
  header "CHECK 6: Docker Container Health"

  local running_containers
  running_containers=$(docker ps --format '{{.Names}}' 2>/dev/null || true)

  if [[ -z "$running_containers" ]]; then
    warn "No containers are running."
    return
  fi

  # Check each expected light service
  info "Checking expected edge services..."
  for svc in "${LIGHT_SERVICES[@]}"; do
    if echo "$running_containers" | grep -q "$svc"; then
      local status
      status=$(docker ps --format '{{.Status}}' --filter "name=$svc" 2>/dev/null)
      if echo "$status" | grep -qi "healthy"; then
        ok "  $svc — healthy"
      elif echo "$status" | grep -qi "unhealthy"; then
        error "  $svc — UNHEALTHY! Check logs: docker logs $svc --tail 50"
      else
        warn "  $svc — running (status: $status)"
      fi
    else
      warn "  $svc — not running"
    fi
  done

  # Check for any unknown containers
  echo ""
  info "Checking for unknown containers..."
  while IFS= read -r container; do
    local found=false
    for expected in "${LIGHT_SERVICES[@]}"; do
      if [[ "$container" == "$expected" ]]; then
        found=true
        break
      fi
    done
    if ! $found; then
      warn "  Unknown container running: $container"
    fi
  done <<< "$running_containers"
}

# ── Check 7: Certificate Expiry ──────────────────────────────────────────────

check_certificates() {
  header "CHECK 7: TLS Certificate Expiry"

  if ! command -v openssl &>/dev/null; then
    warn "openssl not available.  Skipping certificate check."
    return
  fi

  # Check certs for each domain
  local domains=(
    "frgops.wheeler.ai"
    "chatwoot.wheeler.ai"
    "n8n.wheeler.ai"
    "litellm.wheeler.ai"
  )

  for domain in "${domains[@]}"; do
    local expiry
    local days_left
    expiry=$(echo | openssl s_client -servername "$domain" -connect "127.0.0.1:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)

    if [[ -z "$expiry" ]]; then
      warn "  $domain — could not check certificate (Traefik may not have issued it yet)"
      continue
    fi

    days_left=$(( ($(date -d "$expiry" +%s) - $(date +%s)) / 86400 ))

    if [[ "$days_left" -gt 30 ]]; then
      ok "  $domain — ${days_left} days until expiry (${expiry})"
    elif [[ "$days_left" -gt 7 ]]; then
      warn "  $domain — ${days_left} days until expiry (renew soon)"
    else
      error "  $domain — ${days_left} days until expiry! (${expiry})"
    fi
  done
}

# ── Check 8: Docker Log Size ─────────────────────────────────────────────────

check_log_sizes() {
  header "CHECK 8: Docker Log Sizes"

  local log_dir="/var/lib/docker/containers"
  if [[ ! -d "$log_dir" ]]; then
    warn "Docker log directory not found.  Skipping log size check."
    return
  fi

  # Size of Docker container logs
  local log_size_mb
  log_size_mb=$(du -sm "$log_dir" 2>/dev/null | cut -f1 || echo 0)

  if [[ "$log_size_mb" -gt 1000 ]]; then
    warn "Docker logs: ${log_size_mb}MB — large!  Consider running prune script."
  elif [[ "$log_size_mb" -gt 500 ]]; then
    warn "Docker logs: ${log_size_mb}MB — moderate.  Monitor growth."
  else
    ok "Docker logs: ${log_size_mb}MB — acceptable."
  fi

  # Check each container's log size
  if $VERBOSE; then
    info "Per-container log sizes:"
    for container in $(docker ps --format '{{.ID}}' 2>/dev/null); do
      local name cid size
      name=$(docker inspect --format '{{.Name}}' "$container" 2>/dev/null | tr -d '/')
      cid=$(docker inspect --format '{{.Id}}' "$container" 2>/dev/null | cut -c1-12)
      size=$(find "$log_dir/$cid" -name "*.log" -exec ls -lh {} \; 2>/dev/null | awk '{print $5}' | head -1 || echo "0B")
      verbose "  $name: $size"
    done
  fi
}


# ══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "========================================================================"
echo " HOSTINGER VPS — LIGHTWEIGHT VERIFICATION"
echo " Date: $(date)"
echo " Mode: $([ "$STRICT" ] && echo "STRICT" || echo "NORMAL") $([ "$VERBOSE" ] && echo "+ VERBOSE" || echo "")"
echo "========================================================================"
echo ""

# Run all checks
check_no_heavy_services
check_resource_usage
check_tailscale
check_public_ports
check_container_health
check_routes
check_certificates
check_log_sizes

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "========================================================================"
echo " VERIFICATION SUMMARY"
echo "========================================================================"
echo ""
echo "  Tests:    $TEST_COUNT"
echo "  Passed:   ${PASSES}"
echo "  Warnings: ${WARNINGS}"
echo "  Failed:   ${FAILURES}"
echo ""

if [[ "$FAILURES" -gt 0 ]]; then
  echo -e "${RED}  ❌  ${FAILURES} FAILURE(S) DETECTED${NC}"
  echo ""
  echo "  Investigate and fix failures before considering deployment complete."
  echo "  Use --verbose for more details."
  exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
  if $STRICT; then
    echo -e "${RED}  ⚠️   ${WARNINGS} WARNING(S) (strict mode — treated as failures)${NC}"
    echo ""
    exit 1
  else
    echo -e "${YELLOW}  ⚠️   ${WARNINGS} WARNING(S) — review recommended${NC}"
    echo ""
    echo "  Re-run with --strict to treat warnings as failures."
  fi
else
  echo -e "${GREEN}  ✅  ALL CHECKS PASSED${NC}"
fi

echo ""
echo "========================================================================"

exit 0
