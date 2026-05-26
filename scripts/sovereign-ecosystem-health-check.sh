#!/usr/bin/env bash
# =============================================================================
# sovereign-ecosystem-health-check.sh — Full Wheeler Ecosystem Health Audit
# =============================================================================
#
# Verifies every layer of the sovereign ecosystem:
#   - 42 Docker containers (docker ps, HEALTHCHECK status)
#   - 20 PM2 processes (status, uptime, restarts)
#   - 8 databases (PostgreSQL, Redis, Neo4j, MinIO, ClickHouse connections)
#   - Tailscale mesh (3 nodes reachable)
#   - Nginx gateway (all routes responding)
#   - LiteLLM proxy (:4049 health)
#   - All revenue-critical endpoints
#
# Output: JSON health report + terminal summary
# Exit codes:
#   0 -- 100% healthy, all checks pass
#   1 -- One or more critical failures
#   2 -- Usage error
#
# Environment:
#   FORCE_COLOR          Set to any value to force color even if not a tty
#   CHECK_TIMEOUT        HTTP check timeout in seconds (default: 5)
#   LOCK_FILE            Override lock file path
#   WHEELER_NONINTERACTIVE  Set to skip prompts
#
# Usage:
#   ./sovereign-ecosystem-health-check.sh              # Full health audit
#   ./sovereign-ecosystem-health-check.sh --json       # Machine-readable JSON
#   ./sovereign-ecosystem-health-check.sh --quick      # Skip slow checks
#   ./sovereign-ecosystem-health-check.sh --help       # This message
#
# Examples:
#   ./sovereign-ecosystem-health-check.sh
#   ./sovereign-ecosystem-health-check.sh --json | jq '.summary'
#   ./sovereign-ecosystem-health-check.sh --quick --json > /tmp/health.json
#   CHECK_TIMEOUT=10 ./sovereign-ecosystem-health-check.sh
# =============================================================================

set -euo pipefail

# ─── Lock file / cleanup ──────────────────────────────────────────────────────

readonly LOCK_FILE="${LOCK_FILE:-/tmp/sovereign-health-check.lock}"
readonly MY_PID=$$

_cleanup() {
    local rc=$?
    # Release lock: remove the lock directory if we own it
    if [[ -d "$LOCK_FILE" ]] && [[ "$(cat "${LOCK_FILE}/pid" 2>/dev/null)" == "$MY_PID" ]]; then
        rm -rf "$LOCK_FILE" 2>/dev/null || true
    fi
    # Clean any temp files we created
    if [[ -n "${TMPDIR:-}" ]] && [[ -d "$TMPDIR" ]]; then
        rm -rf "$TMPDIR" 2>/dev/null || true
    fi
    exit "$rc"
}
trap _cleanup EXIT INT TERM HUP

# Acquire lock: stale lock detection before honoring existing lock
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    # Lock directory exists — check if it's stale (owner PID dead)
    if [[ -f "$LOCK_FILE/pid" ]]; then
        local locked_pid
        locked_pid=$(cat "${LOCK_FILE}/pid" 2>/dev/null)
        if [[ -n "$locked_pid" ]] && ! kill -0 "$locked_pid" 2>/dev/null; then
            # Stale lock — original PID is dead, reclaim it
            rm -rf "$LOCK_FILE" 2>/dev/null
            if ! mkdir "$LOCK_FILE" 2>/dev/null; then
                echo "ERROR: Cannot acquire lock (race after stale removal)" >&2
                exit 2
            fi
        else
            echo "ERROR: Another instance is running (lock held by PID ${locked_pid:-unknown})" >&2
            exit 2
        fi
    else
        # Lock directory exists but no PID file — stale, reclaim it
        rm -rf "$LOCK_FILE" 2>/dev/null
        if ! mkdir "$LOCK_FILE" 2>/dev/null; then
            echo "ERROR: Cannot acquire lock (race after stale removal)" >&2
            exit 2
        fi
    fi
fi
echo "$MY_PID" > "${LOCK_FILE}/pid" 2>/dev/null || true

# Temp directory for this run
readonly TMPDIR="$(mktemp -d /tmp/sovereign-health-XXXXXX 2>/dev/null || echo "/tmp/sovereign-health-$$")"
mkdir -p "$TMPDIR"

# ─── Constants ─────────────────────────────────────────────────────────────────

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo '/root/scripts')"
readonly START_EPOCH="$(date +%s 2>/dev/null || echo "0")"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")"
readonly CHECK_TIMEOUT="${CHECK_TIMEOUT:-5}"
readonly MAX_RETRIES=2
readonly CURL_OPTS=(--max-time "$CHECK_TIMEOUT" --connect-timeout 3 --silent --show-error --output /dev/null --write-out '%{http_code}')
readonly CURL_OPTS_VERBOSE=(--max-time "$CHECK_TIMEOUT" --connect-timeout 3 --silent --show-error)

# Node definitions
readonly AIOPS_IP="5.78.140.118"
readonly COREDB_IP="5.78.210.123"
readonly EDGE_IP="187.77.148.88"

# Tailscale IPs
readonly AIOPS_TS="100.69.230.72"
readonly COREDB_TS="100.77.160.79"
readonly EDGE_TS="100.89.73.62"

# Hostnames
readonly AIOPS_HOST="aiops.wheeler.internal"
readonly COREDB_HOST="coredb.wheeler.internal"
readonly EDGE_HOST="edge.wheeler.internal"

# ─── State ──────────────────────────────────────────────────────────────────────

PASS=0
FAIL=0
WARN=0
SKIP=0
declare -a RESULTS=()
declare -a JSON_RESULTS=()
JSON_MODE=false
QUICK_MODE=false
COMPOSITE_SCORE=1000
IS_ROOT=false
HAD_FATAL=false

# ─── Color definitions ─────────────────────────────────────────────────────────

if [[ -t 1 ]] || [[ -n "${FORCE_COLOR:-}" ]]; then
    C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'
    C_MAGENTA='\033[0;35m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
    C_CYAN=''; C_MAGENTA=''; C_BOLD=''; C_DIM=''
fi

# ─── Help ───────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Comprehensive health check for the Wheeler sovereign ecosystem.
Verifies Tailscale mesh, Docker containers, PM2 processes, databases,
Nginx gateway, revenue-critical endpoints, monitoring stack, and security posture.

Options:
  --json       Output machine-readable JSON only
  --quick      Skip slow checks (database queries, external HTTP)
  --help       Show this message and exit

Environment Variables:
  FORCE_COLOR          Force ANSI color output even when not a tty
  CHECK_TIMEOUT        HTTP request timeout in seconds (default: 5)
  LOCK_FILE            Override the lock file path

Examples:
  ${SCRIPT_NAME}                          Full health audit with terminal output
  ${SCRIPT_NAME} --json | jq .            JSON output for machine consumption
  ${SCRIPT_NAME} --quick --json           Fast check, JSON output
  CHECK_TIMEOUT=10 ${SCRIPT_NAME}         Increase HTTP timeout to 10s
  ${SCRIPT_NAME} --json > report.json     Save report to file

Exit Codes:
  0  100% healthy — all checks passed
  1  One or more critical failures detected
  2  Usage error or lock contention

Log File:
  Results are written to /var/log/wheeler/health/health-report-*.json
  when JSON mode is active or failures are detected.

Checks Performed:
  1. TAILSCALE MESH    — 3 nodes reachability, self IP
  2. DOCKER            — Container counts, health, :latest audit, networks
  3. PM2 PROCESSES     — 20 process status, restart counts, uptime
  4. LITELLM PROXY     — Health endpoint, model routing
  5. DATABASES         — PostgreSQL(5), Redis, Neo4j, MinIO, ClickHouse
  6. NGINX GATEWAY     — Config syntax, process, routes
  7. REVENUE ENDPOINTS — FRGCRM, SurplusAI, scraper, voice, etc.
  8. MONITORING STACK  — Prometheus, Grafana, Loki, Alertmanager, n8n
  9. SECURITY POSTURE  — UFW, port exposure, secrets in ps
EOF
    exit "$1"
}

# ─── Helpers ────────────────────────────────────────────────────────────────────

section() {
    local title="$1"
    if [[ "$JSON_MODE" == "false" ]]; then
        echo ""
        echo -e "${C_BOLD}${C_BLUE}━━━ ${title} ━━━${C_RESET}"
    fi
}

pass()  { ((PASS++)) || true; }
fail()  { ((FAIL++)) || true; }
warn()  { ((WARN++)) || true; }
skip()  { ((SKIP++)) || true; }

result_human() {
    local status="$1" label="$2" detail="$3"
    local icon line
    case "$status" in
        PASS) icon="[OK]";;
        FAIL) icon="[FAIL]";;
        WARN) icon="[WARN]";;
        SKIP) icon="[SKIP]";;
    esac
    line=$(printf "  %-6s %-55s %s" "$icon" "$label" "$detail")
    RESULTS+=("$line")
    if [[ "$JSON_MODE" == "false" ]]; then
        case "$status" in
            PASS) echo -e "${C_GREEN}${line}${C_RESET}" ;;
            FAIL) echo -e "${C_RED}${line}${C_RESET}"   ;;
            WARN) echo -e "${C_YELLOW}${line}${C_RESET}";;
            SKIP) echo -e "${C_DIM}${line}${C_RESET}"   ;;
        esac
    fi
}

result_json_entry() {
    local status="$1" label="$2" detail="$3" category="${4:-general}"
    # Properly escape JSON special characters
    local esc_label esc_detail
    esc_label=$(printf '%s' "$label" | sed -e 's/["\]/\\&/g' -e 's/[[:cntrl:]]/ /g')
    esc_detail=$(printf '%s' "$detail" | sed -e 's/["\]/\\&/g' -e 's/[[:cntrl:]]/ /g')
    JSON_RESULTS+=("{\"category\":\"${category}\",\"name\":\"${esc_label}\",\"status\":\"${status}\",\"detail\":\"${esc_detail}\"}")
}

result() {
    local status="$1" label="$2" detail="$3" category="${4:-general}"
    result_human "$status" "$label" "$detail"
    result_json_entry "$status" "$label" "$detail" "$category"
    case "$status" in
        PASS) ((PASS++)) || true ;;
        FAIL) ((FAIL++)) || true ;;
        WARN) ((WARN++)) || true ;;
        SKIP) ((SKIP++)) || true ;;
    esac
}

check_cmd() {
    command -v "$1" &>/dev/null
}

# Retry a curl check up to MAX_RETRIES times with exponential backoff
curl_check_retry() {
    local url="$1" label="$2" category="$3" expected="${4:-200}"
    local http_code="000"
    local attempt=0
    local delay=1
    while [[ "$attempt" -le "$MAX_RETRIES" ]]; do
        http_code=$(curl "${CURL_OPTS[@]}" -- "$url" 2>/dev/null || echo "000")
        if [[ "$http_code" == "$expected" ]] || [[ "$http_code" != "000" ]]; then
            break
        fi
        attempt=$((attempt + 1))
        if [[ "$attempt" -le "$MAX_RETRIES" ]]; then
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done
    if [[ "$http_code" == "$expected" ]]; then
        result "PASS" "$label" "HTTP ${http_code}" "$category"
    elif [[ "$http_code" == "000" ]]; then
        result "FAIL" "$label" "Connection refused or timeout after $((MAX_RETRIES+1)) tries" "$category"
    else
        result "FAIL" "$label" "Expected ${expected}, got ${http_code}" "$category"
    fi
}

curl_check() {
    # Calls curl_check_retry with defaults; single-try alias
    curl_check_retry "$@"
}

# Check if docker daemon is responding
_docker_alive() {
    docker info --format '{{.ServerVersion}}' &>/dev/null 2>&1
}

# Check if PM2 daemon is responding
_pm2_alive() {
    pm2 ping &>/dev/null 2>&1
}

# Check if running as root (some checks require it)
_check_root() {
    if [[ "$(id -u 2>/dev/null || echo 1000)" -eq 0 ]]; then
        IS_ROOT=true
    fi
}

# ─── Argument Parsing ───────────────────────────────────────────────────────────

_check_root
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)    JSON_MODE=true; shift ;;
        --quick)   QUICK_MODE=true; shift ;;
        --help)    usage 0 ;;
        *)
            echo "Unknown option: $1" >&2
            usage 2
            ;;
    esac
done

# Validate CHECK_TIMEOUT is a positive integer
if ! [[ "$CHECK_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$CHECK_TIMEOUT" -lt 1 ]]; then
    echo "ERROR: CHECK_TIMEOUT must be a positive integer, got '${CHECK_TIMEOUT}'" >&2
    exit 2
fi

# ─── Main ───────────────────────────────────────────────────────────────────────

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  WHEELER SOVEREIGN ECOSYSTEM HEALTH CHECK${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  ${TIMESTAMP}${C_RESET}"
    [[ "$IS_ROOT" == "false" ]] && echo -e "${C_YELLOW}  Note: Not running as root — some checks may be limited${C_RESET}"
    [[ "$QUICK_MODE" == "true" ]] && echo -e "${C_DIM}  Quick mode: skipping slow checks${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 1. TAILSCALE MESH — Verify all 3 nodes reachable
# ═══════════════════════════════════════════════════════════════════════════════

section "1. TAILSCALE MESH"

if check_cmd tailscale; then
    # Check tailscale status; handle daemon not running
    TS_STATUS=$(tailscale status --json 2>/dev/null || echo "{}")
    TS_ONLINE=$(echo "$TS_STATUS" | grep -c '"Online":true' 2>/dev/null || echo "0")

    # Check AIOPS self
    if tailscale status 2>/dev/null | grep -q -- "$AIOPS_TS"; then
        result "PASS" "AIOPS (${AIOPS_TS})" "Tailscale connected" "tailscale"
    else
        # Could be different IP; just check that tailscale is running
        if tailscale status 2>/dev/null | grep -q "$(hostname 2>/dev/null || echo '')"; then
            result "PASS" "AIOPS (local)" "Tailscale connected (IP may differ)" "tailscale"
        else
            result "FAIL" "AIOPS (${AIOPS_TS})" "Not found in Tailscale status" "tailscale"
        fi
    fi

    # Ping COREDB via Tailscale
    if ping -c 1 -W 2 -- "$COREDB_TS" &>/dev/null; then
        result "PASS" "COREDB (${COREDB_TS})" "Ping OK" "tailscale"
    else
        result "FAIL" "COREDB (${COREDB_TS})" "Unreachable via Tailscale" "tailscale"
        result "WARN" "COREDB SSH" "Use Hetzner web console for recovery" "tailscale"
    fi

    # Ping EDGE via Tailscale
    if ping -c 1 -W 2 -- "$EDGE_TS" &>/dev/null; then
        result "PASS" "EDGE (${EDGE_TS})" "Ping OK" "tailscale"
    else
        result "FAIL" "EDGE (${EDGE_TS})" "Unreachable via Tailscale" "tailscale"
    fi

    # Get tailscale IPs
    TS_IPS=$(tailscale ip -4 2>/dev/null || echo "unknown")
    result "PASS" "Local Tailscale IP" "${TS_IPS}" "tailscale"
else
    result "WARN" "Tailscale binary" "Not found — cannot verify mesh" "tailscale"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 2. DOCKER CONTAINERS — Check all 42 across compose stacks
# ═══════════════════════════════════════════════════════════════════════════════

section "2. DOCKER CONTAINERS"

if check_cmd docker && _docker_alive; then
    # Count running containers; handle daemon-down gracefully
    TOTAL_CONTAINERS=$(docker ps -q 2>/dev/null | wc -l)
    ALL_CONTAINERS=$(docker ps -a -q 2>/dev/null | wc -l)
    HEALTHY_CONTAINERS=$(docker ps --filter "health=healthy" -q 2>/dev/null | wc -l)
    UNHEALTHY_CONTAINERS=$(docker ps --filter "health=unhealthy" -q 2>/dev/null | wc -l)
    STARTING_CONTAINERS=$(docker ps --filter "health=starting" -q 2>/dev/null | wc -l)

    result "PASS" "Total containers (running/all)" "${TOTAL_CONTAINERS}/${ALL_CONTAINERS}" "docker"

    if [[ "$UNHEALTHY_CONTAINERS" -gt 0 ]]; then
        result "FAIL" "Unhealthy containers" "${UNHEALTHY_CONTAINERS} containers have unhealthy HEALTHCHECK" "docker"
    else
        result "PASS" "Container HEALTHCHECK status" "All healthy (${HEALTHY_CONTAINERS})" "docker"
    fi

    # Check containers in "restarting" state (edge case)
    RESTARTING=$(docker ps -a --filter "status=restarting" -q 2>/dev/null | wc -l)
    if [[ "$RESTARTING" -gt 0 ]]; then
        result "FAIL" "Restarting containers" "${RESTARTING} containers in restarting state" "docker"
        docker ps -a --filter "status=restarting" --format "{{.Names}}" 2>/dev/null | while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            result "FAIL" "  → ${name}" "Restarting — crash loop detected" "docker"
        done
    fi

    # Check all containers are running (not exited)
    EXITED=$(docker ps -a --filter "status=exited" -q 2>/dev/null | wc -l)
    if [[ "$EXITED" -gt 0 ]]; then
        result "FAIL" "Exited containers" "${EXITED} containers in exited state" "docker"
        docker ps -a --filter "status=exited" --format "{{.Names}}" 2>/dev/null | while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            result "FAIL" "  → ${name}" "Exited — needs investigation" "docker"
        done
    else
        result "PASS" "Exited containers" "0 exited" "docker"
    fi

    # Check :latest tag usage (security risk)
    LATEST_COUNT=$(docker ps --format "{{.Image}}" 2>/dev/null | grep -c ":latest" || true)
    if [[ "$LATEST_COUNT" -gt 0 ]]; then
        result "WARN" "Containers using :latest tag" "${LATEST_COUNT} containers — pin to semantic versions" "docker"
    else
        result "PASS" "No :latest tags" "All images pinned" "docker"
    fi

    # Check Docker networks
    for net in he_net coredb_net edge_net frg_net surplus_net monitoring; do
        if docker network ls --format "{{.Name}}" 2>/dev/null | grep -qF "$net"; then
            result "PASS" "Docker network: ${net}" "Exists" "docker"
        else
            result "WARN" "Docker network: ${net}" "Not found on this node" "docker"
        fi
    done

    # Check compose stack files exist
    COMPOSE_DIRS=("/root" "/root/docker" "/opt/wheeler")
    COMPOSE_FILES=(
        "docker-compose.yml" "frg-compose.yml" "surplus-compose.yml"
        "pred-compose.yml" "monitoring-compose.yml" "paperless-compose.yml"
        "agent-compose.yml" "voice-compose.yml" "command-compose.yml"
        "eventbus-compose.yml" "insforge-compose.yml" "design-compose.yml"
    )
    FOUND_COMPOSE=0
    for dir in "${COMPOSE_DIRS[@]}"; do
        for file in "${COMPOSE_FILES[@]}"; do
            if [[ -f "${dir}/${file}" ]]; then
                ((FOUND_COMPOSE++))
                break 2
            fi
        done
    done
    if [[ "$FOUND_COMPOSE" -gt 0 ]]; then
        result "PASS" "Compose stacks" "Found compose files" "docker"
    else
        result "WARN" "Compose stacks" "No compose files found in standard locations" "docker"
    fi
elif check_cmd docker; then
    result "WARN" "Docker daemon" "Binary found but daemon not responding" "docker"
else
    result "WARN" "Docker binary" "Not found on this node" "docker"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 3. PM2 PROCESSES — Check all 20 processes
# ═══════════════════════════════════════════════════════════════════════════════

section "3. PM2 PROCESSES"

if check_cmd pm2 && _pm2_alive; then
    PM2_LIST=$(pm2 jlist 2>/dev/null || echo "[]")
    # Validate JSON before parsing
    PM2_COUNT=$(echo "$PM2_LIST" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "0")

    result "PASS" "PM2 processes" "${PM2_COUNT} managed" "pm2"

    # Check specific PM2 processes
    declare -A PM2_PROCESSES=(
        ["litellm"]="4049:AI Proxy"
        ["frgcrm-api"]="8082:FRG CRM API"
        ["frgcrm-agent"]="8003:FRG CRM Agent"
        ["surplusai-portal-api"]="8103:SurplusAI Portal API"
        ["surplusai-scraper"]="8007:SurplusAI Scraper"
        ["voice-agent"]="8008:Voice Agent"
        ["paperless-agent"]="8009:Paperless Agent"
        ["horizon-agent"]="8006:Horizon Agent"
        ["insforge-agent"]="8013:INS Forge Agent"
        ["design-agent"]="8020:Design Agent"
        ["prediction-radar-agent"]="8011:Prediction Radar"
        ["ravyn-agent"]="8005:Ravyn Agent"
        ["ecosystem-guardian"]="—:Ecosystem Guardian"
        ["command-center"]="8100:Command Center"
        ["war-room"]="8091:War Room"
        ["openclaw-dashboard"]="8110:OpenCLAW Dashboard"
        ["event-bus-relay"]="6399:Event Bus Relay"
        ["voice-outreach"]="8095:Voice Outreach"
        ["surplusai-portal-frontend"]="3003:Portal Frontend"
        ["sre-commander"]="8092:SRE Commander"
    )

    # Write PM2 list to temp file for faster repeated access
    echo "$PM2_LIST" > "${TMPDIR}/pm2_jlist.json"

    for proc in "${!PM2_PROCESSES[@]}"; do
        IFS_BACKUP="$IFS"
        IFS=":"
        read -r port desc <<< "${PM2_PROCESSES[$proc]}" || true
        IFS="$IFS_BACKUP"

        # Get process status from pm2 list using cached file
        STATUS=$(python3 -c "
import sys,json
with open('${TMPDIR}/pm2_jlist.json') as f:
    data=json.load(f)
for p in data:
    if p.get('name') == '${proc}':
        print(p.get('pm2_env',{}).get('status','unknown'))
        break
" 2>/dev/null || echo "unknown")

        RESTARTS=$(python3 -c "
import sys,json
with open('${TMPDIR}/pm2_jlist.json') as f:
    data=json.load(f)
for p in data:
    if p.get('name') == '${proc}':
        print(p.get('pm2_env',{}).get('restart_time',0))
        break
" 2>/dev/null || echo "0")

        UPTIME=$(python3 -c "
import sys,json,time
with open('${TMPDIR}/pm2_jlist.json') as f:
    data=json.load(f)
for p in data:
    if p.get('name') == '${proc}':
        started = p.get('pm2_env',{}).get('created_at',0)
        if started:
            print(f'{int((time.time()*1000 - started)/1000)}s')
        else:
            print('N/A')
        break
" 2>/dev/null || echo "N/A")

        # Handle all PM2 states: online, stopped, errored, restarting, etc.
        if [[ "$STATUS" == "online" ]]; then
            if [[ "$RESTARTS" -gt 100 ]]; then
                result "WARN" "PM2 ${proc}" "online, ${RESTARTS} restarts (elevated)" "pm2"
            elif [[ "$RESTARTS" -gt 10 ]]; then
                result "WARN" "PM2 ${proc}" "online, ${RESTARTS} restarts" "pm2"
            else
                result "PASS" "PM2 ${proc} (:${port})" "online, ${RESTARTS} restarts, up ${UPTIME}" "pm2"
            fi
        elif [[ "$STATUS" == "stopped" ]]; then
            result "FAIL" "PM2 ${proc} (:${port})" "stopped — needs restart" "pm2"
        elif [[ "$STATUS" == "restarting" ]]; then
            result "WARN" "PM2 ${proc} (:${port})" "restarting — transient state" "pm2"
        elif [[ "$STATUS" == "errored" ]]; then
            result "FAIL" "PM2 ${proc} (:${port})" "errored — crash loop probable" "pm2"
        else
            result "FAIL" "PM2 ${proc} (:${port})" "status: ${STATUS}" "pm2"
        fi
    done
elif check_cmd pm2; then
    result "SKIP" "PM2" "Binary found but daemon not responding" "pm2"
else
    result "SKIP" "PM2" "Not available on this node" "pm2"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 4. LITELLM PROXY — Central AI model routing
# ═══════════════════════════════════════════════════════════════════════════════

section "4. LITELLM PROXY"

curl_check "http://127.0.0.1:4049/health" "LiteLLM health endpoint" "litellm"
curl_check "http://127.0.0.1:4049/" "LiteLLM root" "litellm"

# Check model routing
if curl "${CURL_OPTS_VERBOSE[@]}" -- "http://127.0.0.1:4049/models" &>/dev/null; then
    result "PASS" "LiteLLM models endpoint" "Responding" "litellm"
else
    result "FAIL" "LiteLLM models endpoint" "Not responding" "litellm"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 5. DATABASES — Check connectivity to all 8 databases
# ═══════════════════════════════════════════════════════════════════════════════

section "5. DATABASES"

_local_db_check() {
    local host="$1" port="$2" label="$3"
    # Use /dev/tcp if available (bash built-in)
    if timeout 2 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
        result "PASS" "${label} (:${port})" "Port open" "database"
        return 0
    elif nc -z -w 2 "$host" "$port" 2>/dev/null; then
        result "PASS" "${label} (:${port})" "Port open (nc)" "database"
        return 0
    else
        return 1
    fi
}

# Postgres checks (quick mode skips psql auth, just checks port)
for db_label in "FRGCRM" "SurplusAI" "Prediction Radar" "Agent DB" "Paperless"; do
    DB_HOST="127.0.0.1"
    DB_PORT=""
    case "$db_label" in
        "FRGCRM")            DB_PORT="5432" ;;
        "SurplusAI")         DB_PORT="5433" ;;
        "Prediction Radar")  DB_PORT="5434" ;;
        "Agent DB")          DB_PORT="5435" ;;
        "Paperless")         DB_PORT="5436" ;;
    esac

    if [[ "$QUICK_MODE" == "true" ]]; then
        # Quick mode: port check only
        if _local_db_check "$DB_HOST" "$DB_PORT" "PostgreSQL: ${db_label}"; then
            :
        else
            result "FAIL" "PostgreSQL: ${db_label} (:${DB_PORT})" "Port closed" "database"
        fi
    else
        # Full check: try psql connection then fall back to port
        if check_cmd psql; then
            if PGPASSWORD="" psql -h "$DB_HOST" -p "$DB_PORT" -U postgres -c "SELECT 1" &>/dev/null; then
                result "PASS" "PostgreSQL: ${db_label} (:${DB_PORT})" "Connected" "database"
            elif _local_db_check "$DB_HOST" "$DB_PORT" "PostgreSQL: ${db_label}"; then
                result "WARN" "PostgreSQL: ${db_label} (:${DB_PORT})" "Port open but login failed" "database"
            else
                result "FAIL" "PostgreSQL: ${db_label} (:${DB_PORT})" "Port not reachable" "database"
            fi
        else
            # Fallback to port check
            if _local_db_check "$DB_HOST" "$DB_PORT" "PostgreSQL: ${db_label}"; then
                :
            else
                result "FAIL" "PostgreSQL: ${db_label} (:${DB_PORT})" "Port closed" "database"
            fi
        fi
    fi
done

# Redis check
_local_db_check "127.0.0.1" "6379" "Redis" || result "FAIL" "Redis (:6379)" "Port closed" "database"

# Neo4j check
_local_db_check "127.0.0.1" "7687" "Neo4j" || result "FAIL" "Neo4j (:7687)" "Port closed" "database"

# MinIO check (future)
_local_db_check "127.0.0.1" "9000" "MinIO" || result "WARN" "MinIO (:9000)" "Not yet deployed (Phase 2)" "database"

# ClickHouse check (future)
_local_db_check "127.0.0.1" "8123" "ClickHouse" || result "WARN" "ClickHouse (:8123)" "Not yet deployed (Phase 2)" "database"

# ═══════════════════════════════════════════════════════════════════════════════
# 6. NGINX GATEWAY — Check all routes
# ═══════════════════════════════════════════════════════════════════════════════

section "6. NGINX GATEWAY"

# Check nginx config syntax
if check_cmd nginx; then
    if nginx -t 2>&1 | grep -q "syntax is ok"; then
        result "PASS" "Nginx config" "Syntax OK" "nginx"
    else
        result "FAIL" "Nginx config" "Syntax error" "nginx"
    fi
fi

# Check nginx process
if pgrep -x nginx &>/dev/null; then
    result "PASS" "Nginx process" "Running" "nginx"
else
    result "FAIL" "Nginx process" "Not running" "nginx"
fi

# Check gateway routes (via localhost nginx or traefik)
for route in "/" "/health" "/api/health" "/frgcrm" "/surplusai" "/prediction-radar"; do
    if curl "${CURL_OPTS[@]}" -- "http://127.0.0.1:80${route}" &>/dev/null; then
        result "PASS" "Gateway route ${route}" "Responding" "nginx"
    else
        result "WARN" "Gateway route ${route}" "Not responding (may be expected)" "nginx"
    fi
done

# Check Traefik (if present)
if curl "${CURL_OPTS[@]}" -- "http://127.0.0.1:8080/api/version" &>/dev/null; then
    result "PASS" "Traefik dashboard" "Responding" "nginx"
else
    result "WARN" "Traefik dashboard" "Not responding (may not be deployed)" "nginx"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 7. REVENUE-CRITICAL ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

section "7. REVENUE-CRITICAL ENDPOINTS"

# FRGCRM API
curl_check "http://127.0.0.1:8082/health"  "FRGCRM API (/health)" "revenue"

# SurplusAI Portal API
curl_check "http://127.0.0.1:8103/health" "SurplusAI Portal API (/health)" "revenue"

# SurplusAI Scraper
if curl "${CURL_OPTS[@]}" -- "http://127.0.0.1:8007/health" &>/dev/null; then
    result "PASS" "SurplusAI Scraper (:8007)" "Health endpoint responding" "revenue"
else
    result "FAIL" "SurplusAI Scraper (:8007)" "Health endpoint not responding" "revenue"
fi

# Prediction Radar
curl_check "http://127.0.0.1:8011/health" "Prediction Radar (/health)" "revenue"

# Voice Agent
if curl "${CURL_OPTS[@]}" -- "http://127.0.0.1:8008/health" &>/dev/null 2>&1; then
    result "PASS" "Voice Agent (:8008)" "Health endpoint responding" "revenue"
else
    result "FAIL" "Voice Agent (:8008)" "Not responding — verify Twilio keys" "revenue"
fi

# Command Center
curl_check "http://127.0.0.1:8100/api/health" "Command Center (/api/health)" "revenue"

# War Room
curl_check "http://127.0.0.1:8091/api/health" "War Room (/api/health)" "revenue"

# SRE Commander
curl_check "http://127.0.0.1:8092/health" "SRE Commander (/health)" "revenue"

# ═══════════════════════════════════════════════════════════════════════════════
# 8. MONITORING STACK
# ═══════════════════════════════════════════════════════════════════════════════

section "8. MONITORING STACK"

# Prometheus
curl_check "http://127.0.0.1:9090/-/ready" "Prometheus" "monitoring"

# Grafana
curl_check "http://127.0.0.1:3000/api/health" "Grafana" "monitoring"

# Loki
curl_check "http://127.0.0.1:3100/ready" "Loki" "monitoring"

# Alertmanager
curl_check "http://127.0.0.1:9093/-/ready" "Alertmanager" "monitoring"

# Node Exporter (Tailscale IP)
curl_check "http://100.121.230.28:9100/metrics" "Node Exporter" "monitoring"

# n8n
curl_check "http://127.0.0.1:5678/healthz" "n8n" "monitoring"

# Langflow
if curl "${CURL_OPTS[@]}" -- "http://127.0.0.1:7860/health" &>/dev/null 2>&1; then
    result "PASS" "Langflow (:7860)" "Responding" "monitoring"
else
    result "WARN" "Langflow (:7860)" "Not responding" "monitoring"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 9. SECURITY POSTURE
# ═══════════════════════════════════════════════════════════════════════════════

section "9. SECURITY POSTURE"

# UFW check (requires root for full status)
if check_cmd ufw; then
    UFW_STATUS=$(ufw status verbose 2>/dev/null | head -1 || echo "inactive")
    if echo "$UFW_STATUS" | grep -qi "active"; then
        UFW_COUNT=$(ufw status numbered 2>/dev/null | grep -c "\[" || echo "0")
        result "PASS" "UFW firewall" "Active, ${UFW_COUNT} rules" "security"
    else
        result "FAIL" "UFW firewall" "Inactive!" "security"
    fi
else
    result "WARN" "UFW" "Not available" "security"
fi

# Check for exposed ports (non-127.0.0.1 bindings)
if check_cmd ss; then
    EXPOSED=$(ss -tlnp 2>/dev/null | grep -v "127.0.0.1:" | grep -v "::1:" | grep -v "0.0.0.0:22" | grep "0.0.0.0:" || true)
    if [[ -n "$EXPOSED" ]]; then
        EXPOSED_COUNT=$(echo "$EXPOSED" | wc -l)
        result "WARN" "Exposed ports (not 127.0.0.1)" "${EXPOSED_COUNT} services — review required" "security"
        while IFS= read -r line; do
            PORT_INFO=$(echo "$line" | awk '{print $4}')
            result "WARN" "  → ${PORT_INFO}" "Bound to 0.0.0.0" "security"
        done <<< "$EXPOSED"
    else
        result "PASS" "Port exposure" "All services bound to 127.0.0.1" "security"
    fi
fi

# Process listing security (check for secrets in cmdline)
if check_cmd ps; then
    SECRET_CMDS=$(ps aux 2>/dev/null | grep -iE "DEEPSEEK_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|TWILIO|DATABASE_URL|REDIS_URL|SECRET_KEY|PASSWORD" | grep -v grep | grep -v "sovereign-ecosystem-health" || true)
    if [[ -n "$SECRET_CMDS" ]]; then
        result "FAIL" "Secrets in process listing" "Secrets visible in ps output!" "security"
        while IFS= read -r line; do
            CMD_SHORT=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | head -c 80)
            result "FAIL" "  → ${CMD_SHORT}..." "Redact secrets from cmdline" "security"
        done <<< "$SECRET_CMDS"
    else
        result "PASS" "Secrets in process listing" "No secrets visible" "security"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

TOTAL=$((PASS + FAIL + WARN + SKIP))
# Base: full weight for passed checks, partial weight for warnings
COMPOSITE_SCORE=$(( (PASS * 1000 + WARN * 300) / (TOTAL > 0 ? TOTAL : 1) ))
# Proportional failure penalty (up to 400 points, scaled by failure share)
FAIL_DEDUCT=$(( (FAIL * 400) / (TOTAL > 0 ? TOTAL : 1) ))
COMPOSITE_SCORE=$(( COMPOSITE_SCORE - FAIL_DEDUCT ))
# Clamp
COMPOSITE_SCORE=$(( COMPOSITE_SCORE > 1000 ? 1000 : COMPOSITE_SCORE ))
COMPOSITE_SCORE=$(( COMPOSITE_SCORE < 0 ? 0 : COMPOSITE_SCORE ))

END_EPOCH=$(date +%s 2>/dev/null || echo "$START_EPOCH")
DURATION=$((END_EPOCH - START_EPOCH))
DURATION=$(( DURATION > 0 ? DURATION : 0 ))

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  HEALTH CHECK SUMMARY${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    printf "  %-20s %s\n" "Total checks:"   "${TOTAL}"
    printf "  %-20s %s\n" "Passed:"         "${C_GREEN}${PASS}${C_RESET}"
    printf "  %-20s %s\n" "Failed:"         "${C_RED}${FAIL}${C_RESET}"
    printf "  %-20s %s\n" "Warnings:"       "${C_YELLOW}${WARN}${C_RESET}"
    printf "  %-20s %s\n" "Skipped:"        "${C_DIM}${SKIP}${C_RESET}"
    printf "  %-20s %s\n" "Duration:"       "${DURATION}s"
    echo ""
    printf "  %-20s " "Composite score:"
    if [[ "$COMPOSITE_SCORE" -ge 800 ]]; then
        echo -e "${C_GREEN}${COMPOSITE_SCORE}/1000${C_RESET}"
    elif [[ "$COMPOSITE_SCORE" -ge 600 ]]; then
        echo -e "${C_YELLOW}${COMPOSITE_SCORE}/1000${C_RESET}"
    else
        echo -e "${C_RED}${COMPOSITE_SCORE}/1000${C_RESET}"
    fi
    echo ""

    if [[ "$FAIL" -eq 0 ]]; then
        echo -e "${C_GREEN}  ECOSYSTEM HEALTH: ALL CHECKS PASSED${C_RESET}"
    else
        echo -e "${C_RED}  ECOSYSTEM HEALTH: ${FAIL} FAILURES DETECTED${C_RESET}"
    fi
    echo ""
fi

# ─── JSON Output ───────────────────────────────────────────────────────────────

# Always write JSON to log
if [[ "$JSON_MODE" == "true" ]] || [[ "$FAIL" -gt 0 ]] || [[ "$WARN" -gt 0 ]]; then
    # Build JSON safely: join all entries with commas
    joined_json=""
    if [[ ${#JSON_RESULTS[@]} -gt 0 ]]; then
        printf -v joined_json '%s,' "${JSON_RESULTS[@]}"
        joined_json="${joined_json%,}"
    fi

    JSON_OUTPUT=$(cat <<EOJSON
{
  "timestamp": "${TIMESTAMP}",
  "duration_seconds": ${DURATION},
  "composite_score": ${COMPOSITE_SCORE},
  "summary": {
    "total": ${TOTAL},
    "passed": ${PASS},
    "failed": ${FAIL},
    "warnings": ${WARN},
    "skipped": ${SKIP}
  },
  "checks": [
    ${joined_json}
  ]
}
EOJSON
)
    if [[ "$JSON_MODE" == "true" ]]; then
        echo "$JSON_OUTPUT"
    fi
    # Write to log
    health_log_dir="/var/log/wheeler/health"
    mkdir -p "$health_log_dir" 2>/dev/null || true
    if [[ -d "$health_log_dir" ]]; then
        echo "$JSON_OUTPUT" > "${health_log_dir}/health-report-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "unknown").json" 2>/dev/null || true
    fi
fi

# ─── Exit code ─────────────────────────────────────────────────────────────────

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
