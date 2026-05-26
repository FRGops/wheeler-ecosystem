#!/usr/bin/env bash
# =============================================================================
# sovereign-kpi-dashboard.sh — Wheeler Ecosystem KPI Dashboard
# =============================================================================
#
# Collects and displays Key Performance Indicators across the Wheeler ecosystem:
#   - PM2 process health (29 processes)
#   - Docker container health (45 containers)
#   - System resources (disk, memory, CPU load)
#   - Service endpoint status (dashboard, Grafana, LiteLLM, revenue APIs)
#   - Revenue process status (FRGCRM, SurplusAI, InsForge)
#   - Git repository activity
#
# Output: Terminal KPI dashboard + JSON report
# Exit codes:
#   0 — KPI collection complete
#   1 — One or more critical KPI thresholds breached
#   2 — Usage error
#
# Usage:
#   ./sovereign-kpi-dashboard.sh                    # Full KPI dashboard
#   ./sovereign-kpi-dashboard.sh --json             # Machine-readable JSON
#   ./sovereign-kpi-dashboard.sh --quick            # Skip slow checks
#   ./sovereign-kpi-dashboard.sh --help             # This message
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly START_EPOCH="$(date +%s)"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly LOG_DIR="${LOG_DIR:-/var/log/wheeler/kpi}"
readonly LOCK_FILE="${LOCK_FILE:-/tmp/sovereign-kpi-dashboard.lock}"
readonly CHECK_TIMEOUT="${CHECK_TIMEOUT:-5}"

MY_PID=$$
TMPDIR=""
JSON_MODE=false
QUICK_MODE=false
CRITICAL_BREACHES=0
declare -a JSON_RESULTS=()

if [[ -t 1 ]] || [[ -n "${FORCE_COLOR:-}" ]]; then
    C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'
    C_MAGENTA='\033[0;35m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
    C_CYAN=''; C_MAGENTA=''; C_BOLD=''; C_DIM=''
fi

_cleanup() {
    local rc=$?
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$MY_PID" ]]; then
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
    if [[ -n "${TMPDIR:-}" ]] && [[ -d "$TMPDIR" ]]; then
        rm -rf "$TMPDIR" 2>/dev/null || true
    fi
    exit "$rc"
}
trap _cleanup EXIT INT TERM HUP

usage() {
    sed -n '/^# =====/,/^# =====/p' "$0" | head -30 | sed 's/^# //'
    exit "${1:-0}"
}

check_cmd() { command -v "$1" &>/dev/null; }

kpi_json() {
    local category="$1" name="$2" value="$3" status="${4:-ok}" threshold="${5:-}"
    local esc_name esc_value
    esc_name=$(printf '%s' "$name" | sed 's/["\]/\\&/g; s/[[:cntrl:]]/ /g')
    esc_value=$(printf '%s' "$value" | sed 's/["\]/\\&/g; s/[[:cntrl:]]/ /g')
    JSON_RESULTS+=("{\"category\":\"${category}\",\"name\":\"${esc_name}\",\"value\":\"${esc_value}\",\"status\":\"${status}\",\"threshold\":\"${threshold}\"}")
}

kpi_display() {
    local status="$1" label="$2" value="$3"
    local icon
    case "$status" in
        ok)    icon="${C_GREEN}[OK]${C_RESET}" ;;
        warn)  icon="${C_YELLOW}[WARN]${C_RESET}" ;;
        crit)  icon="${C_RED}[CRIT]${C_RESET}"; ((CRITICAL_BREACHES++)) || true ;;
    esac
    if [[ "$JSON_MODE" == "false" ]]; then
        printf "  %b %-50s %s\n" "$icon" "$label" "$value"
    fi
}

_http_code() {
    curl -s -o /dev/null -w '%{http_code}' --max-time "$CHECK_TIMEOUT" "$1" 2>/dev/null || echo "000"
}

# ─── Argument Parsing ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)  JSON_MODE=true; shift ;;
        --quick) QUICK_MODE=true; shift ;;
        --help)  usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

mkdir -p "$LOG_DIR"
TMPDIR="$(mktemp -d "/tmp/kpi-dashboard-XXXXXX")"
echo "$MY_PID" > "$LOCK_FILE" 2>/dev/null || true

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  WHEELER ECOSYSTEM KPI DASHBOARD${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  ${TIMESTAMP}${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 1. PM2 PROCESS KPIs
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo -e "${C_BOLD}${C_BLUE}━━━ 1. PM2 PROCESSES ━━━${C_RESET}"
fi

if check_cmd pm2; then
    PM2_JSON=$(pm2 jlist 2>/dev/null || echo "[]")
    PM2_TOTAL=$(echo "$PM2_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    PM2_ONLINE=$(echo "$PM2_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
print(sum(1 for p in data if p.get('pm2_env',{}).get('status')=='online'))" 2>/dev/null || echo "0")
    PM2_STOPPED=$(echo "$PM2_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
print(sum(1 for p in data if p.get('pm2_env',{}).get('status')=='stopped'))" 2>/dev/null || echo "0")
    PM2_ERRORED=$(echo "$PM2_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
print(sum(1 for p in data if p.get('pm2_env',{}).get('status')=='errored'))" 2>/dev/null || echo "0")
    PM2_MAX_RESTARTS=$(echo "$PM2_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
restarts=[p.get('pm2_env',{}).get('restart_time',0) for p in data]
print(max(restarts) if restarts else 0)" 2>/dev/null || echo "0")
    PM2_MEM_MB=$(echo "$PM2_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
mem=sum(p.get('monit',{}).get('memory',0) for p in data)
print(round(mem/1024/1024,1) if mem else 0)" 2>/dev/null || echo "0")
    PM2_CPU_PCT=$(echo "$PM2_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
cpu=sum(p.get('monit',{}).get('cpu',0) for p in data)
print(round(cpu,1) if cpu else 0)" 2>/dev/null || echo "0")

    kpi_display "ok"   "Total PM2 processes"         "${PM2_TOTAL}"
    kpi_json "pm2" "total_processes" "$PM2_TOTAL" "ok" ">=20"
    if [[ "$PM2_ONLINE" -eq "$PM2_TOTAL" ]]; then
        kpi_display "ok"   "Processes online"            "${PM2_ONLINE}/${PM2_TOTAL}"
        kpi_json "pm2" "online_processes" "$PM2_ONLINE" "ok" "=total"
    elif [[ "$PM2_STOPPED" -gt 0 ]] || [[ "$PM2_ERRORED" -gt 0 ]]; then
        kpi_display "crit" "Processes online"            "${PM2_ONLINE}/${PM2_TOTAL} (${PM2_STOPPED} stopped, ${PM2_ERRORED} errored)"
        kpi_json "pm2" "online_processes" "$PM2_ONLINE" "crit" "=total"
    else
        kpi_display "warn" "Processes online"            "${PM2_ONLINE}/${PM2_TOTAL}"
        kpi_json "pm2" "online_processes" "$PM2_ONLINE" "warn" "=total"
    fi

    if [[ "$PM2_MAX_RESTARTS" -gt 100 ]]; then
        kpi_display "crit" "Max process restarts"       "${PM2_MAX_RESTARTS}"
    elif [[ "$PM2_MAX_RESTARTS" -gt 10 ]]; then
        kpi_display "warn" "Max process restarts"       "${PM2_MAX_RESTARTS}"
    else
        kpi_display "ok"   "Max process restarts"       "${PM2_MAX_RESTARTS}"
    fi
    kpi_json "pm2" "max_restarts" "$PM2_MAX_RESTARTS" "$([[ $PM2_MAX_RESTARTS -gt 100 ]] && echo crit || echo ok)" "<10"

    kpi_display "ok"   "Total PM2 memory"            "${PM2_MEM_MB} MB"
    kpi_json "pm2" "total_memory_mb" "$PM2_MEM_MB" "ok" ""
    kpi_display "ok"   "Total PM2 CPU"               "${PM2_CPU_PCT}%"
    kpi_json "pm2" "total_cpu_pct" "$PM2_CPU_PCT" "ok" ""
else
    kpi_display "crit" "PM2 daemon"                   "Unavailable"
    kpi_json "pm2" "daemon" "unavailable" "crit" ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 2. DOCKER CONTAINER KPIs
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ 2. DOCKER CONTAINERS ━━━${C_RESET}"
fi

if check_cmd docker && docker info &>/dev/null 2>&1; then
    DOCKER_TOTAL=$(docker ps -q 2>/dev/null | wc -l)
    DOCKER_ALL=$(docker ps -a -q 2>/dev/null | wc -l)
    DOCKER_HEALTHY=$(docker ps --filter "health=healthy" -q 2>/dev/null | wc -l)
    DOCKER_UNHEALTHY=$(docker ps --filter "health=unhealthy" -q 2>/dev/null | wc -l)
    DOCKER_EXITED=$(docker ps -a --filter "status=exited" -q 2>/dev/null | wc -l)
    DOCKER_RESTARTING=$(docker ps -a --filter "status=restarting" -q 2>/dev/null | wc -l)

    kpi_display "ok"   "Running containers"           "${DOCKER_TOTAL}/${DOCKER_ALL}"
    kpi_json "docker" "running_containers" "$DOCKER_TOTAL" "ok" ">=40"

    if [[ "$DOCKER_UNHEALTHY" -gt 0 ]]; then
        kpi_display "crit" "Healthy containers"          "${DOCKER_HEALTHY} healthy, ${DOCKER_UNHEALTHY} UNHEALTHY"
        kpi_json "docker" "healthy_containers" "$DOCKER_HEALTHY" "crit" "=total"
    else
        kpi_display "ok"   "Healthy containers"          "${DOCKER_HEALTHY}"
        kpi_json "docker" "healthy_containers" "$DOCKER_HEALTHY" "ok" "=total"
    fi

    if [[ "$DOCKER_EXITED" -gt 0 ]]; then
        kpi_display "warn" "Exited containers"           "${DOCKER_EXITED}"
        kpi_json "docker" "exited_containers" "$DOCKER_EXITED" "warn" "=0"
    fi

    if [[ "$DOCKER_RESTARTING" -gt 0 ]]; then
        kpi_display "crit" "Restarting containers"       "${DOCKER_RESTARTING} in crash loop"
        kpi_json "docker" "restarting_containers" "$DOCKER_RESTARTING" "crit" "=0"
    fi
else
    kpi_display "crit" "Docker daemon"                "Unavailable"
    kpi_json "docker" "daemon" "unavailable" "crit" ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 3. SYSTEM RESOURCE KPIs
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ 3. SYSTEM RESOURCES ━━━${C_RESET}"
fi

DISK_PCT=$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}' || echo "0")
DISK_TOTAL=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "unknown")
DISK_USED=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}' || echo "unknown")
DISK_AVAIL=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}' || echo "unknown")

MEM_TOTAL=$(free -m 2>/dev/null | awk 'NR==2 {print $2}' || echo "0")
MEM_USED=$(free -m 2>/dev/null | awk 'NR==2 {print $3}' || echo "0")
MEM_PCT=$(( MEM_TOTAL > 0 ? MEM_USED * 100 / MEM_TOTAL : 0 ))

LOAD_1M=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs || echo "0")
LOAD_5M=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | awk -F',' '{print $2}' | xargs || echo "0")
LOAD_15M=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | awk -F',' '{print $3}' | xargs || echo "0")
CPU_COUNT=$(nproc 2>/dev/null || echo "1")

if [[ "$DISK_PCT" -gt 90 ]]; then
    kpi_display "crit" "Disk usage (/)"              "${DISK_USED}/${DISK_TOTAL} (${DISK_PCT}%)"
elif [[ "$DISK_PCT" -gt 80 ]]; then
    kpi_display "warn" "Disk usage (/)"              "${DISK_USED}/${DISK_TOTAL} (${DISK_PCT}%)"
else
    kpi_display "ok"   "Disk usage (/)"              "${DISK_USED}/${DISK_TOTAL} (${DISK_PCT}%)"
fi
kpi_json "system" "disk_usage_pct" "$DISK_PCT" "$([[ $DISK_PCT -gt 90 ]] && echo crit || echo ok)" "<80"
kpi_json "system" "disk_total" "$DISK_TOTAL" "ok" ""
kpi_json "system" "disk_available" "$DISK_AVAIL" "ok" ""

if [[ "$MEM_PCT" -gt 90 ]]; then
    kpi_display "crit" "Memory usage"                "${MEM_USED}MB/${MEM_TOTAL}MB (${MEM_PCT}%)"
else
    kpi_display "ok"   "Memory usage"                "${MEM_USED}MB/${MEM_TOTAL}MB (${MEM_PCT}%)"
fi
kpi_json "system" "memory_usage_pct" "$MEM_PCT" "$([[ $MEM_PCT -gt 90 ]] && echo crit || echo ok)" "<90"
kpi_json "system" "memory_total_mb" "$MEM_TOTAL" "ok" ""

LOAD_RATIO=$(python3 -c "print(round(${LOAD_1M:-0}/${CPU_COUNT:-1}, 2))" 2>/dev/null || echo "0")
LOAD_CHECK=$(python3 -c "
r = ${LOAD_RATIO:-0}
print('crit' if r > 2.0 else 'warn' if r > 1.0 else 'ok')" 2>/dev/null || echo "ok")
kpi_display "$LOAD_CHECK" "System load (1m/5m/15m)"     "${LOAD_1M} / ${LOAD_5M} / ${LOAD_15M} (${CPU_COUNT} cores, ratio: ${LOAD_RATIO})"
kpi_json "system" "load_1m" "$LOAD_1M" "$LOAD_CHECK" "<${CPU_COUNT}"
kpi_json "system" "cpu_cores" "$CPU_COUNT" "ok" ""

# ═══════════════════════════════════════════════════════════════════════════════
# 4. SERVICE ENDPOINT KPIs
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$QUICK_MODE" != "true" ]]; then
    if [[ "$JSON_MODE" == "false" ]]; then
        echo ""
        echo -e "${C_BOLD}${C_BLUE}━━━ 4. SERVICE ENDPOINTS ━━━${C_RESET}"
    fi

    declare -A ENDPOINTS=(
        ["Executive Dashboard"]="http://127.0.0.1:8180/health:200"
        ["Grafana"]="http://127.0.0.1:3002/api/health:200"
        ["LiteLLM Proxy"]="http://127.0.0.1:4049/health:401"
        ["FRGCRM API"]="http://127.0.0.1:8082/health:200"
        ["SurplusAI API"]="http://127.0.0.1:8103/health:200"
        ["Command Center"]="http://127.0.0.1:8100/api/health:200"
        ["War Room"]="http://127.0.0.1:8091/api/health:200"
        ["OpenCLAW Dashboard"]="http://127.0.0.1:8110:200"
        ["Prometheus"]="http://127.0.0.1:9090/-/ready:200"
        ["Loki"]="http://127.0.0.1:3100/ready:200"
        ["Alertmanager"]="http://127.0.0.1:9093/-/ready:200"
    )

    for svc in "${!ENDPOINTS[@]}"; do
        IFS=":" read -r url expected <<< "${ENDPOINTS[$svc]}"
        http_code=$(_http_code "$url")
        if [[ "$http_code" == "$expected" ]] || [[ "$http_code" == "200" && "$expected" == "401" ]]; then
            kpi_display "ok"   "${svc}"                      "HTTP ${http_code}"
            kpi_json "services" "${svc}" "HTTP ${http_code}" "ok" ""
        elif [[ "$http_code" == "000" ]]; then
            kpi_display "crit" "${svc}"                      "Connection refused"
            kpi_json "services" "${svc}" "down" "crit" ""
        else
            kpi_display "warn" "${svc}"                      "HTTP ${http_code} (expected ${expected})"
            kpi_json "services" "${svc}" "HTTP ${http_code}" "warn" ""
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 5. REVENUE PROCESS KPIs
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ 5. REVENUE PROCESSES ━━━${C_RESET}"
fi

REVENUE_PROCESSES=("frgcrm-api:FRGCRM API" "surplusai-portal-api:SurplusAI API" "insforge-agent-svc:InsForge")
if check_cmd pm2; then
    for entry in "${REVENUE_PROCESSES[@]}"; do
        IFS=":" read -r proc_name proc_label <<< "$entry"
        status=$(echo "$PM2_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for p in data:
    if p.get('name')=='$proc_name':
        print(p.get('pm2_env',{}).get('status','unknown'))
        break" 2>/dev/null || echo "unknown")
        if [[ "$status" == "online" ]]; then
            kpi_display "ok"   "${proc_label}"              "online"
            kpi_json "revenue" "${proc_label}" "online" "ok" ""
        elif [[ "$status" == "unknown" ]]; then
            kpi_display "warn" "${proc_label}"              "not found in PM2"
            kpi_json "revenue" "${proc_label}" "missing" "warn" ""
        else
            kpi_display "crit" "${proc_label}"              "${status}"
            kpi_json "revenue" "${proc_label}" "${status}" "crit" ""
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 6. GIT ACTIVITY KPIs
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ 6. GIT ACTIVITY ━━━${C_RESET}"
fi

GIT_RECENT_COMMITS=$(git -C /root log --oneline --since="24 hours ago" 2>/dev/null | wc -l || echo "0")
GIT_BRANCH=$(git -C /root branch --show-current 2>/dev/null || echo "unknown")
GIT_UNTRACKED=$(git -C /root status --porcelain 2>/dev/null | grep "^??" | wc -l || echo "0")
GIT_MODIFIED=$(git -C /root status --porcelain 2>/dev/null | grep -v "^??" | wc -l || echo "0")
GIT_LAST_COMMIT=$(git -C /root log -1 --format="%ar: %s" 2>/dev/null | head -c 80 || echo "unknown")

kpi_display "ok"   "Current branch"             "${GIT_BRANCH}"
kpi_json "git" "branch" "$GIT_BRANCH" "ok" ""
kpi_display "ok"   "Commits (24h)"              "${GIT_RECENT_COMMITS}"
kpi_json "git" "commits_24h" "$GIT_RECENT_COMMITS" "ok" ""
kpi_display "ok"   "Last commit"                "${GIT_LAST_COMMIT}"
kpi_json "git" "last_commit" "$GIT_LAST_COMMIT" "ok" ""

if [[ "$GIT_MODIFIED" -gt 0 ]]; then
    kpi_display "warn" "Modified files"             "${GIT_MODIFIED}"
    kpi_json "git" "modified_files" "$GIT_MODIFIED" "warn" "=0"
fi
if [[ "$GIT_UNTRACKED" -gt 0 ]]; then
    kpi_display "warn" "Untracked files"            "${GIT_UNTRACKED}"
    kpi_json "git" "untracked_files" "$GIT_UNTRACKED" "warn" "=0"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

END_EPOCH=$(date +%s)
DURATION=$(( END_EPOCH - START_EPOCH ))
KPI_TOTAL=$(echo "${JSON_RESULTS[@]}" | wc -w)

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  KPI SUMMARY${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    printf "  KPIs collected: %s | Duration: %ss | Breaches: %s\n" "$KPI_TOTAL" "$DURATION" "$CRITICAL_BREACHES"
    echo ""
    if [[ "$CRITICAL_BREACHES" -eq 0 ]]; then
        echo -e "${C_GREEN}  ALL KPIs WITHIN THRESHOLDS${C_RESET}"
    else
        echo -e "${C_RED}  ${CRITICAL_BREACHES} CRITICAL KPI THRESHOLD BREACHES DETECTED${C_RESET}"
    fi
    echo ""
fi

# JSON output
if [[ ${#JSON_RESULTS[@]} -gt 0 ]]; then
    printf -v joined '%s,' "${JSON_RESULTS[@]}"
    joined="${joined%,}"
fi

JSON_OUTPUT=$(cat <<EOJSON
{
  "timestamp": "${TIMESTAMP}",
  "duration_seconds": ${DURATION},
  "critical_breaches": ${CRITICAL_BREACHES},
  "kpi_count": ${KPI_TOTAL},
  "kpis": [${joined:-}]
}
EOJSON
)

if [[ "$JSON_MODE" == "true" ]]; then
    echo "$JSON_OUTPUT"
fi

report_file="${LOG_DIR}/kpi-report-$(date +%Y%m%d-%H%M%S).json"
echo "$JSON_OUTPUT" > "$report_file" 2>/dev/null || true

if [[ "$CRITICAL_BREACHES" -gt 0 ]]; then
    exit 1
fi
exit 0
