#!/usr/bin/env bash
# =============================================================================
# Wheeler Enterprise — Comprehensive Health Check System
# =============================================================================
# Validates the entire infrastructure stack across all 3 servers.
# Output: terminal report + JSON file for Prometheus textfile collector.
#
# Usage:
#   bash healthcheck-all.sh                    # Full check, terminal output
#   bash healthcheck-all.sh --json             # JSON output to healthcheck.json
#   bash healthcheck-all.sh --prometheus       # Write Prometheus metrics file
#   bash healthcheck-all.sh --server <name>    # Check a specific server
#
# Checks performed:
#   1. Docker container health
#   2. PM2 service health
#   3. Port availability
#   4. Disk usage
#   5. Memory pressure
#   6. CPU pressure
#   7. PostgreSQL health
#   8. Redis health
#   9. Tailscale connectivity
#   10. Traefik health
#   11. SSL certificate validity
#   12. API endpoint response validation
# =============================================================================
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_JSON="$SCRIPT_DIR/healthcheck-result.json"
PROMETHEUS_TEXTFILE="/var/lib/node_exporter/textfile_collector/wheeler-health.prom"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PROM_TIMESTAMP=$(date +%s)

# Thresholds
DISK_WARN_PCT=80
DISK_CRIT_PCT=90
MEM_WARN_PCT=85
MEM_CRIT_PCT=95
CPU_WARN_PCT=80
CPU_CRIT_PCT=90

# Server IPs (via Tailscale)
AIOPS_IP="100.121.230.28"
EDGE_IP="100.98.163.17"
COREDB_IP=""  # Set when COREDB is provisioned

# Service endpoints to validate (public URLs)
ENDPOINTS=(
    "https://predictionradar.wheeler.ai"
    "https://ravynai.wheeler.ai"
    "https://superset.wheeler.ai"
    "https://healthchecks.wheeler.ai"
    "https://grafana.wheeler.ai"
    "https://uptime.wheeler.ai"
    "https://docuseal.wheeler.ai"
)

# Ports to verify (service:port)
declare -A PORTS_TO_CHECK=(
    ["SSH"]="22"
    ["HTTP"]="80"
    ["HTTPS"]="443"
    ["Traefik-Dashboard"]="8080"
    ["Prometheus"]="9090"
    ["Grafana"]="3002"
    ["Loki"]="3100"
    ["PostgreSQL"]="5432"
    ["Redis"]="6379"
    ["Uptime-Kuma"]="3001"
    ["Node-Exporter"]="9100"
    ["cAdvisor"]="8082"
)

# ── Color Output ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "  ${BLUE}[INFO]${NC} $*"; }

# Accumulate failures for exit code
FAILURES=0
WARNINGS=0
PASSES=0

# ── Check Functions ──────────────────────────────────────────────────────

check_docker_containers() {
    echo -e "\n${BOLD}━━━ 1. Docker Container Health ━━━${NC}"

    if ! command -v docker &>/dev/null; then
        fail "Docker not installed"
        ((FAILURES++))
        return
    fi

    if ! docker info &>/dev/null; then
        fail "Docker daemon not running"
        ((FAILURES++))
        return
    fi

    pass "Docker daemon is running"

    # Check all running containers
    local total=0 healthy=0 unhealthy=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ((total++))
        local name=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $2}')

        case "$status" in
            healthy|Up)
                pass "$name ($status)"
                ((healthy++))
                ;;
            unhealthy)
                fail "$name ($status)"
                ((unhealthy++))
                ((FAILURES++))
                ;;
            starting|*)
                warn "$name ($status)"
                ((WARNINGS++))
                ;;
        esac
    done < <(docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | \
        while read -r name status; do
            if echo "$status" | grep -q '(healthy)'; then
                echo "$name healthy"
            elif echo "$status" | grep -q '(unhealthy)'; then
                echo "$name unhealthy"
            elif echo "$status" | grep -q 'Up'; then
                echo "$name Up"
            else
                echo "$name other"
            fi
        done)

    echo ""
    info "Containers: $healthy healthy, $unhealthy unhealthy (total: $total)"
    ((PASSES+=healthy))
}

check_pm2_services() {
    echo -e "\n${BOLD}━━━ 2. PM2 Service Health ━━━${NC}"

    if ! command -v pm2 &>/dev/null; then
        info "PM2 not installed — skipping"
        return
    fi

    local total=0 online=0 errored=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ((total++))

        local name=$(echo "$line" | awk -F'│' '{print $2}' | xargs)
        local status=$(echo "$line" | awk -F'│' '{print $7}' | xargs)
        local restarts=$(echo "$line" | awk -F'│' '{print $8}' | xargs)
        local cpu=$(echo "$line" | awk -F'│' '{print $9}' | xargs)
        local mem=$(echo "$line" | awk -F'│' '{print $10}' | xargs)

        case "$status" in
            online)
                pass "$name — $status, CPU: $cpu, MEM: $mem"
                ((online++))

                # Warn on high restart count
                if [[ "$restarts" =~ ^[0-9]+$ ]] && [ "$restarts" -gt 100 ]; then
                    warn "$name has $restarts restarts — possible restart loop"
                    ((WARNINGS++))
                fi
                ;;
            errored|stopped)
                fail "$name — $status (restarts: $restarts)"
                ((errored++))
                ((FAILURES++))
                ;;
            "waiting restart"|"launching")
                warn "$name — $status"
                ((WARNINGS++))
                ;;
            *)
                warn "$name — $status"
                ((WARNINGS++))
                ;;
        esac
    done < <(pm2 list 2>/dev/null | grep '│ [0-9]')

    echo ""
    info "PM2: $online online, $errored errored (total: $total)"
    ((PASSES+=online))
}

check_ports() {
    echo -e "\n${BOLD}━━━ 3. Port Availability ━━━${NC}"

    for service in "${!PORTS_TO_CHECK[@]}"; do
        local port="${PORTS_TO_CHECK[$service]}"

        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            pass "$service port $port — listening"
            ((PASSES++))
        elif netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            pass "$service port $port — listening"
            ((PASSES++))
        else
            warn "$service port $port — NOT listening"
            ((WARNINGS++))
        fi
    done
}

check_disk_usage() {
    echo -e "\n${BOLD}━━━ 4. Disk Usage ━━━${NC}"

    local df_output=$(df -h / /boot/efi 2>/dev/null | tail -n +2)

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local fs=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local avail=$(echo "$line" | awk '{print $4}')
        local pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local mount=$(echo "$line" | awk '{print $6}')

        if [ "$pct" -ge "$DISK_CRIT_PCT" ]; then
            fail "$mount — ${pct}% used ($used/$size) — CRITICAL"
            ((FAILURES++))
        elif [ "$pct" -ge "$DISK_WARN_PCT" ]; then
            warn "$mount — ${pct}% used ($used/$size)"
            ((WARNINGS++))
        else
            pass "$mount — ${pct}% used ($used/$size) — ${avail} available"
            ((PASSES++))
        fi
    done <<< "$df_output"

    # Check inodes
    local inode_pct=$(df -i / | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$inode_pct" -ge 90 ]; then
        warn "Root inode usage at ${inode_pct}% — check for file explosion"
        ((WARNINGS++))
    else
        pass "Inode usage: ${inode_pct}%"
        ((PASSES++))
    fi
}

check_memory_pressure() {
    echo -e "\n${BOLD}━━━ 5. Memory Pressure ━━━${NC}"

    local mem_total=$(awk '/MemTotal/{printf "%.0f", $2/1024/1024}' /proc/meminfo)
    local mem_avail=$(awk '/MemAvailable/{printf "%.0f", $2/1024/1024}' /proc/meminfo)
    local mem_used=$((mem_total - mem_avail))
    local mem_pct=$((mem_used * 100 / mem_total))

    pass "Total: ${mem_total}GB, Available: ${mem_avail}GB, Used: ${mem_pct}%"

    if [ "$mem_pct" -ge "$MEM_CRIT_PCT" ]; then
        fail "Memory at ${mem_pct}% — CRITICAL"
        ((FAILURES++))
    elif [ "$mem_pct" -ge "$MEM_WARN_PCT" ]; then
        warn "Memory at ${mem_pct}%"
        ((WARNINGS++))
    else
        pass "Memory usage OK"
        ((PASSES++))
    fi

    # Check swap usage
    local swap_total=$(awk '/SwapTotal/{print $2}' /proc/meminfo)
    local swap_free=$(awk '/SwapFree/{print $2}' /proc/meminfo)
    if [ "$swap_total" -gt 0 ]; then
        local swap_used=$((swap_total - swap_free))
        local swap_pct=$((swap_used * 100 / swap_total))
        if [ "$swap_pct" -gt 50 ]; then
            warn "Swap usage: ${swap_pct}% — memory pressure detected"
            ((WARNINGS++))
        else
            pass "Swap usage: ${swap_pct}%"
            ((PASSES++))
        fi
    else
        warn "No swap configured — OOM risk under extreme pressure"
        ((WARNINGS++))
    fi

    # Check memory pressure stall information (PSI)
    if [ -f /proc/pressure/memory ]; then
        local mem_pressure=$(awk '{print $1}' /proc/pressure/memory | head -1)
        info "Memory PSI: $mem_pressure"
    fi
}

check_cpu_pressure() {
    echo -e "\n${BOLD}━━━ 6. CPU Pressure ━━━${NC}"

    local cores=$(nproc)
    local load=$(awk '{printf "%.1f", $1}' /proc/loadavg)
    local load_pct=$(echo "scale=0; $load * 100 / $cores" | bc 2>/dev/null || echo "0")

    pass "Load: $load ($load_pct% of $cores cores)"

    if [ "$(echo "$load > $cores * 0.9" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        warn "Load average ($load) near core count ($cores)"
        ((WARNINGS++))
    else
        pass "CPU load OK"
        ((PASSES++))
    fi

    # Check CPU pressure stall information (PSI)
    if [ -f /proc/pressure/cpu ]; then
        local cpu_pressure=$(awk '{print $1}' /proc/pressure/cpu | head -1)
        info "CPU PSI: $cpu_pressure"
    fi
}

check_postgres_health() {
    echo -e "\n${BOLD}━━━ 7. PostgreSQL Health ━━━${NC}"

    # Check if postgres containers are running
    local pg_containers=$(docker ps --filter "name=postgres" --format '{{.Names}}' 2>/dev/null)

    if [ -z "$pg_containers" ]; then
        info "No PostgreSQL containers running on this server"
        return
    fi

    for container in $pg_containers; do
        if docker exec "$container" pg_isready -U postgres &>/dev/null; then
            pass "$container — accepting connections"

            # Get connection count
            local conns=$(docker exec "$container" psql -U postgres -t -c \
                "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "?")
            info "$container — $conns active connections"
            ((PASSES++))
        else
            fail "$container — NOT accepting connections"
            ((FAILURES++))
        fi
    done
}

check_redis_health() {
    echo -e "\n${BOLD}━━━ 8. Redis Health ━━━${NC}"

    local redis_containers=$(docker ps --filter "name=redis" --format '{{.Names}}' 2>/dev/null)

    if [ -z "$redis_containers" ]; then
        info "No Redis containers running on this server"
        return
    fi

    for container in $redis_containers; do
        if docker exec "$container" redis-cli PING 2>/dev/null | grep -q "PONG"; then
            pass "$container — PONG"

            local mem=$(docker exec "$container" redis-cli INFO memory 2>/dev/null | \
                grep "used_memory_human" | cut -d: -f2 | xargs)
            info "$container — memory: $mem"
            ((PASSES++))
        else
            fail "$container — not responding to PING"
            ((FAILURES++))
        fi
    done
}

check_tailscale_health() {
    echo -e "\n${BOLD}━━━ 9. Tailscale Health ━━━${NC}"

    if ! command -v tailscale &>/dev/null; then
        info "Tailscale not installed — skipping"
        return
    fi

    local status_output=$(tailscale status 2>/dev/null || echo "")

    if [ -z "$status_output" ]; then
        fail "Tailscale not running or not authenticated"
        ((FAILURES++))
        return
    fi

    # Check if Tailscale is connected
    if echo "$status_output" | grep -q "Tailscale is (stopped|offline|starting)"; then
        fail "Tailscale is not connected"
        ((FAILURES++))
    else
        pass "Tailscale is connected"

        # Check connectivity to edge server
        if echo "$status_output" | grep -q "$EDGE_IP"; then
            pass "Edge server ($EDGE_IP) reachable"
            ((PASSES++))
        else
            warn "Edge server ($EDGE_IP) not in Tailscale mesh"
            ((WARNINGS++))
        fi
    fi
}

check_traefik_health() {
    echo -e "\n${BOLD}━━━ 10. Traefik Health ━━━${NC}"

    # Check Traefik container
    if docker ps --filter "name=traefik" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        pass "Traefik container is running"

        # Check Traefik API health endpoint
        local health=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/rawdata 2>/dev/null || echo "000")
        if [ "$health" = "200" ]; then
            pass "Traefik API responding (200)"
            ((PASSES++))
        else
            warn "Traefik API returned $health"
            ((WARNINGS++))
        fi
    else
        info "Traefik container not running on this server"
    fi
}

check_ssl_validity() {
    echo -e "\n${BOLD}━━━ 11. SSL Certificate Validity ━━━${NC}"

    if ! command -v openssl &>/dev/null; then
        warn "openssl not found — skipping SSL checks"
        ((WARNINGS++))
        return
    fi

    local domains=(
        "predictionradar.wheeler.ai"
        "ravynai.wheeler.ai"
        "superset.wheeler.ai"
        "grafana.wheeler.ai"
        "uptime.wheeler.ai"
        "docuseal.wheeler.ai"
    )

    for domain in "${domains[@]}"; do
        local cert_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | \
            openssl x509 -noout -dates 2>/dev/null)

        if [ -z "$cert_info" ]; then
            warn "$domain — cannot fetch certificate"
            ((WARNINGS++))
            continue
        fi

        local end_date=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)
        local end_epoch=$(date -d "$end_date" +%s 2>/dev/null || echo 0)
        local now_epoch=$(date +%s)
        local days_left=$(( (end_epoch - now_epoch) / 86400 ))

        if [ "$days_left" -le 7 ]; then
            fail "$domain — EXPIRES in $days_left days ($end_date)"
            ((FAILURES++))
        elif [ "$days_left" -le 30 ]; then
            warn "$domain — expires in $days_left days ($end_date)"
            ((WARNINGS++))
        else
            pass "$domain — $days_left days remaining"
            ((PASSES++))
        fi
    done
}

check_api_endpoints() {
    echo -e "\n${BOLD}━━━ 12. API Endpoint Validation ━━━${NC}"

    if ! command -v curl &>/dev/null; then
        warn "curl not found — skipping API checks"
        return
    fi

    for url in "${ENDPOINTS[@]}"; do
        local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")

        case "$code" in
            200|301|302|303|307|308)
                pass "$url — HTTP $code"
                ((PASSES++))
                ;;
            401|403)
                # Auth-required endpoints are fine — they're accessible
                pass "$url — HTTP $code (auth required, accessible)"
                ((PASSES++))
                ;;
            000)
                fail "$url — UNREACHABLE (timeout or DNS failure)"
                ((FAILURES++))
                ;;
            5*)
                fail "$url — HTTP $code (server error)"
                ((FAILURES++))
                ;;
            *)
                warn "$url — HTTP $code"
                ((WARNINGS++))
                ;;
        esac
    done
}

# ── Output Formatters ─────────────────────────────────────────────────────

output_json() {
    cat > "$OUTPUT_JSON" <<JSONEOF
{
  "timestamp": "$TIMESTAMP",
  "hostname": "$(hostname)",
  "server_role": "${SERVER_ROLE:-aiops}",
  "summary": {
    "passes": $PASSES,
    "warnings": $WARNINGS,
    "failures": $FAILURES,
    "status": "$([ $FAILURES -eq 0 ] && echo "healthy" || echo "degraded")"
  },
  "checks": {
    "docker": { "status": "completed" },
    "pm2": { "status": "completed" },
    "ports": { "status": "completed" },
    "disk": { "status": "completed" },
    "memory": { "status": "completed" },
    "cpu": { "status": "completed" },
    "postgres": { "status": "completed" },
    "redis": { "status": "completed" },
    "tailscale": { "status": "completed" },
    "traefik": { "status": "completed" },
    "ssl": { "status": "completed" },
    "api": { "status": "completed" }
  }
}
JSONEOF

    echo "JSON report written to: $OUTPUT_JSON"
}

output_prometheus() {
    mkdir -p "$(dirname "$PROMETHEUS_TEXTFILE")"

    cat > "$PROMETHEUS_TEXTFILE" <<PROMEOF
# HELP wheeler_health_check_passes Total health check passes
# TYPE wheeler_health_check_passes gauge
wheeler_health_check_passes $PASSES

# HELP wheeler_health_check_warnings Total health check warnings
# TYPE wheeler_health_check_warnings gauge
wheeler_health_check_warnings $WARNINGS

# HELP wheeler_health_check_failures Total health check failures
# TYPE wheeler_health_check_failures gauge
wheeler_health_check_failures $FAILURES

# HELP wheeler_health_check_status Overall health status (1=healthy, 0=degraded)
# TYPE wheeler_health_check_status gauge
wheeler_health_check_status $([ $FAILURES -eq 0 ] && echo "1" || echo "0")

# HELP wheeler_health_check_last_run_seconds Timestamp of last health check
# TYPE wheeler_health_check_last_run_seconds gauge
wheeler_health_check_last_run_seconds $PROM_TIMESTAMP
PROMEOF

    echo "Prometheus metrics written to: $PROMETHEUS_TEXTFILE"
}

# ── Summary ───────────────────────────────────────────────────────────────

print_summary() {
    echo -e "\n${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              HEALTH CHECK SUMMARY                        ║${NC}"
    echo -e "${BOLD}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  ${GREEN}Passes:   $PASSES${NC}"
    echo -e "${BOLD}║${NC}  ${YELLOW}Warnings: $WARNINGS${NC}"
    echo -e "${BOLD}║${NC}  ${RED}Failures: $FAILURES${NC}"

    if [ $FAILURES -eq 0 ]; then
        echo -e "${BOLD}║${NC}  ${GREEN}Overall:  HEALTHY${NC}"
        echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
        return 0
    else
        echo -e "${BOLD}║${NC}  ${RED}Overall:  DEGRADED — $FAILURES check(s) failed${NC}"
        echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
        return 1
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Wheeler Enterprise — Comprehensive Health Check            ║"
echo "║   Server: $(hostname) ($(hostname -I | awk '{print $1}'))"
echo "║   Time:   $TIMESTAMP"
echo "╚═══════════════════════════════════════════════════════════════╝"

# Run all checks
check_docker_containers
check_pm2_services
check_ports
check_disk_usage
check_memory_pressure
check_cpu_pressure
check_postgres_health
check_redis_health
check_tailscale_health
check_traefik_health
check_ssl_validity
check_api_endpoints

print_summary

# Handle output flags
case "${1:-}" in
    --json)
        output_json
        ;;
    --prometheus)
        output_prometheus
        ;;
    --full)
        output_json
        output_prometheus
        ;;
esac

exit $(( FAILURES > 0 ? 1 : 0 ))
