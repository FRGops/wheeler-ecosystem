#!/usr/bin/env bash
# =============================================================================
# health-check-endpoints.sh — Unified Health Check for All Services
# =============================================================================
# Checks health endpoints for every service in the stack and reports status
# in a unified table. Can output JSON for machine consumption.
#
# Usage:
#   ./health-check-endpoints.sh                          # Table output
#   ./health-check-endpoints.sh --json                   # JSON output
#   ./health-check-endpoints.sh --json --pretty           # Pretty JSON
#   ./health-check-endpoints.sh --check <service-name>    # Single service
#   ./health-check-endpoints.sh --cron                   # Cron mode (lightweight)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
HETZNER_TS="100.121.230.28"
HOSTINGER_TS="100.98.163.17"
TIMEOUT=5  # seconds per check
SLEEP_BETWEEN=0.2  # seconds between checks (avoid hammering)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Flags
OUTPUT_JSON=false
PRETTY_JSON=false
SINGLE_CHECK=""
CRON_MODE=false

# ---------------------------------------------------------------------------
# PARSE ARGUMENTS
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --json) OUTPUT_JSON=true ;;
    --pretty) PRETTY_JSON=true ;;
    --cron) CRON_MODE=true ;;
    --check=*) SINGLE_CHECK="${arg#*=}" ;;
    --help)
      echo "Usage: $0 [--json] [--pretty] [--cron] [--check=<name>]"
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# SERVICE DEFINITIONS
# ---------------------------------------------------------------------------
# Format: "Name|URL|Type|ExpectedStatus|Keyword"
# Type: http, tcp
SERVICES=(
  # ---- HETZNER CPX51 (via public endpoints through Hostinger Traefik) ----
  "Prediction Radar API|https://predictionradar.wheeler.ai/health|http|200|"
  "Prediction Radar Web|https://predictionradar.wheeler.ai|http|200|"
  "RavynAI API|https://ravynai.wheeler.ai/health|http|200|"
  "Superset|https://superset.wheeler.ai/health|http|200|"
  "Healthchecks.io|https://healthchecks.wheeler.ai|http|200|"
  "ChangeDetection|https://changedetect.wheeler.ai|http|200|"
  "Grafana|https://grafana.wheeler.ai/api/health|http|200|"
  "Uptime Kuma|https://uptime.wheeler.ai|http|200|"

  # ---- HOSTINGER VPS (public endpoints) ----
  "FRGops|https://frgops.wheeler.ai|http|200|"
  "Chatwoot|https://chatwoot.wheeler.ai|http|200|"
  "n8n|https://n8n.wheeler.ai/healthz|http|200|"
  "Docuseal|https://docuseal.wheeler.ai|http|200|"
  "LiteLLM|https://litellm.wheeler.ai/health|http|200|"
  "MinIO|https://minio.wheeler.ai|http|200|"

  # ---- TAILSCALE-ONLY (internal ports) ----
  "Prometheus|http://${HETZNER_TS}:9090/-/healthy|http|200|"
  "AlertManager|http://${HETZNER_TS}:9093/-/healthy|http|200|"
  "Netdata|http://${HETZNER_TS}:19999/api/v1/info|http|200|"

  # ---- TCP PORT CHECKS (databases, cache, messaging) ----
  "Postgres AIOps|${HETZNER_TS}:5432|tcp|0|"
  "Postgres Radar|${HETZNER_TS}:5433|tcp|0|"
  "Postgres RavynAI|${HETZNER_TS}:5434|tcp|0|"
  "Redis AIOps|${HETZNER_TS}:6379|tcp|0|"
  "Redis Radar|${HETZNER_TS}:6380|tcp|0|"
  "NATS|${HETZNER_TS}:4222|tcp|0|"
  "Postgres FRGops|${HOSTINGER_TS}:5432|tcp|0|"
)

# ---------------------------------------------------------------------------
# HEALTH CHECK FUNCTIONS
# ---------------------------------------------------------------------------

# Check HTTP endpoint
check_http() {
  local url="$1"
  local expected_status="$2"
  local keyword="$3"

  local start_time
  start_time=$(date +%s%N)

  local http_code
  local response_body

  # Perform HTTP request with timeout
  if [ -n "$keyword" ]; then
    # Check for keyword in response
    response_body=$(curl -sf --max-time "$TIMEOUT" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    http_code="$response_body"
    # Can't check keyword with just status code, so we do a separate call
    if [ "$http_code" = "$expected_status" ] || [ "$expected_status" = "0" ]; then
      body=$(curl -sf --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "")
      if echo "$body" | grep -q "$keyword"; then
        http_code="$expected_status"
      else
        http_code="999"  # Keyword not found
      fi
    fi
  else
    http_code=$(curl -sf --max-time "$TIMEOUT" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
  fi

  local end_time
  end_time=$(date +%s%N)
  local duration_ms=$(( (end_time - start_time) / 1000000 ))

  # Determine status
  if [ "$http_code" = "000" ]; then
    echo "DOWN|${duration_ms}ms|Connection failed"
  elif [ "$http_code" = "999" ]; then
    echo "DEGRADED|${duration_ms}ms|Keyword not found"
  elif [ "$expected_status" != "0" ] && [ "$http_code" != "$expected_status" ]; then
    echo "DEGRADED|${duration_ms}ms|Expected $expected_status, got $http_code"
  else
    echo "UP|${duration_ms}ms|HTTP $http_code"
  fi
}

# Check TCP endpoint
check_tcp() {
  local host="$1"
  local port="$2"

  local start_time
  start_time=$(date +%s%N)

  if timeout "$TIMEOUT" bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
    local end_time
    end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    echo "UP|${duration_ms}ms|TCP connected"
  else
    echo "DOWN|${TIMEOUT}s|TCP connection refused"
  fi
}

# Check docker container status
check_docker_container() {
  local container_name="$1"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
    local status
    status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")
    if [ "$status" = "running" ]; then
      echo "UP"
    else
      echo "DEGRADED ($status)"
    fi
  else
    echo "DOWN (not found)"
  fi
}

# ---------------------------------------------------------------------------
# PERFORM ALL CHECKS
# ---------------------------------------------------------------------------
perform_checks() {
  local results=()

  for service in "${SERVICES[@]}"; do
    IFS='|' read -r name target type expected_code keyword <<< "$service"

    # Filter if single check mode
    if [ -n "$SINGLE_CHECK" ] && ! echo "$name" | grep -qi "$SINGLE_CHECK"; then
      continue
    fi

    local status=""
    local detail=""

    if [ "$type" = "http" ]; then
      IFS='|' read -r status detail <<< "$(check_http "$target" "$expected_code" "$keyword")"
    elif [ "$type" = "tcp" ]; then
      IFS=':' read -r host port <<< "$target"
      IFS='|' read -r status detail <<< "$(check_tcp "$host" "$port")"
    fi

    results+=("$name|$status|$detail")
    sleep "$SLEEP_BETWEEN"
  done

  # Return results via global array
  CHECK_RESULTS=("${results[@]}")
}

# ---------------------------------------------------------------------------
# OUTPUT: TABLE FORMAT
# ---------------------------------------------------------------------------
output_table() {
  echo ""
  echo -e "${BOLD}==============================================================${NC}"
  echo -e "${BOLD}  Wheeler AIOps — Health Check Report${NC}"
  echo -e "${BOLD}  $(date '+%Y-%m-%d %H:%M:%S UTC')${NC}"
  echo -e "${BOLD}==============================================================${NC}"
  echo ""

  local total=0
  local up=0
  local degraded=0
  local down=0

  # Group by status
  echo -e "${BOLD}Services:${NC}"
  printf "  %-25s %-10s %s\n" "SERVICE" "STATUS" "DETAIL"
  echo "  --------------------------------------------------------------"

  for result in "${CHECK_RESULTS[@]}"; do
    IFS='|' read -r name status detail <<< "$result"
    total=$((total + 1))

    local status_display=""
    case "$status" in
      UP)
        status_display="${GREEN}UP${NC}"
        up=$((up + 1))
        ;;
      DEGRADED)
        status_display="${YELLOW}DEGRADED${NC}"
        degraded=$((degraded + 1))
        ;;
      DOWN)
        status_display="${RED}DOWN${NC}"
        down=$((down + 1))
        ;;
    esac

    printf "  %-25s %-10b %s\n" "$name" "$status_display" "$detail"
  done

  # Summary
  echo ""
  echo -e "${BOLD}Summary:${NC}"
  echo -e "  ${GREEN}UP:${NC} $up  ${YELLOW}DEGRADED:${NC} $degraded  ${RED}DOWN:${NC} $down  TOTAL: $total"

  # Overall status
  if [ $down -gt 0 ]; then
    echo -e "  ${BOLD}Overall: ${RED}CRITICAL${NC} — $down service(s) are DOWN${NC}"
  elif [ $degraded -gt 0 ]; then
    echo -e "  ${BOLD}Overall: ${YELLOW}DEGRADED${NC} — $degraded service(s) degraded${NC}"
  else
    echo -e "  ${BOLD}Overall: ${GREEN}HEALTHY${NC} — All services operational${NC}"
  fi

  # Resource summary
  echo ""
  echo -e "${BOLD}System Resources:${NC}"
  if command -v free &>/dev/null; then
    echo -e "  Memory:  $(free -h | awk '/^Mem:/ {print $3 " used / " $2 " total"}')"
  fi
  if command -v df &>/dev/null; then
    echo -e "  Disk:    $(df -h / | awk 'NR==2 {print $3 " used / " $2 " total (" $5 " used)"}')"
  fi
  if command -v uptime &>/dev/null; then
    echo -e "  Load:    $(uptime | awk -F'load average:' '{print $2}')"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# OUTPUT: JSON FORMAT
# ---------------------------------------------------------------------------
output_json() {
  local first=true

  if [ "$PRETTY_JSON" = true ]; then
    echo "{"
    echo '  "timestamp": "'$(date -u '+%Y-%m-%dT%H:%M:%SZ')'",'
    echo '  "hostname": "'$(hostname)'",'
    echo '  "services": ['
  else
    echo -n '{"timestamp":"'$(date -u '+%Y-%m-%dT%H:%M:%SZ')'","hostname":"'$(hostname)'","services":['
  fi

  for result in "${CHECK_RESULTS[@]}"; do
    IFS='|' read -r name status detail <<< "$result"

    if [ "$first" = true ]; then
      first=false
    else
      if [ "$PRETTY_JSON" = true ]; then
        echo ","
      else
        echo -n ","
      fi
    fi

    if [ "$PRETTY_JSON" = true ]; then
      echo '    {'
      echo '      "name": "'$name'",'
      echo '      "status": "'$status'",'
      echo '      "detail": "'$detail'"'
      echo -n '    }'
    else
      echo -n '{"name":"'$name'","status":"'$status'","detail":"'$detail'"}'
    fi
  done

  # Calculate summary
  local up=0 degraded=0 down=0
  for result in "${CHECK_RESULTS[@]}"; do
    IFS='|' read -r _ status _ <<< "$result"
    case "$status" in
      UP) up=$((up + 1)) ;;
      DEGRADED) degraded=$((degraded + 1)) ;;
      DOWN) down=$((down + 1)) ;;
    esac
  done

  if [ "$PRETTY_JSON" = true ]; then
    echo ''
    echo '  ],'
    echo '  "summary": {'
    echo '    "up": '$up','
    echo '    "degraded": '$degraded','
    echo '    "down": '$down','
    echo '    "total": '$((${#CHECK_RESULTS[@]}))''
    echo '  }'
    echo '}'
  else
    echo '],"summary":{"up":'$up',"degraded":'$degraded',"down":'$down',"total":'${#CHECK_RESULTS[@]}'}}'
  fi
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
main() {
  if [ "$CRON_MODE" = true ]; then
    # Cron mode — minimal output, just report if anything is down
    perform_checks
    local down_count=0
    for result in "${CHECK_RESULTS[@]}"; do
      IFS='|' read -r name status _ <<< "$result"
      if [ "$status" = "DOWN" ]; then
        echo "DOWN: $name"
        down_count=$((down_count + 1))
      fi
    done
    exit $down_count
  fi

  perform_checks

  if [ "$OUTPUT_JSON" = true ]; then
    output_json
  else
    output_table
  fi
}

main
