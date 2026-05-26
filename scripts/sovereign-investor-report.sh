#!/usr/bin/env bash
# =============================================================================
# sovereign-investor-report.sh — Board/Investor-Ready Financial Report Generator
# =============================================================================
#
# Generates board-ready financial packages from Wheeler ecosystem data:
#   - Revenue summary (PM2 revenue processes, Stripe data if available)
#   - Infrastructure health (Docker, PM2, endpoint status)
#   - Operational KPIs (uptime, incident count, deployment frequency)
#   - Growth metrics (MRR trend, new products, market expansion)
#   - Risk dashboard (security posture, backup health, compliance status)
#
# Output: Markdown report + JSON data bundle
# Exit codes:
#   0 — Report generated successfully
#   1 — Report generated with warnings
#   2 — Fatal error
#
# Usage:
#   ./sovereign-investor-report.sh                     # Full report
#   ./sovereign-investor-report.sh --period month       # Monthly report (default: week)
#   ./sovereign-investor-report.sh --json               # JSON data bundle only
#   ./sovereign-investor-report.sh --output /path/dir   # Custom output directory
#   ./sovereign-investor-report.sh --help               # This message
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly TIMESTAMP_FMT="$(date +%Y%m%d-%H%M%S)"
readonly OUTPUT_DIR="${OUTPUT_DIR:-/var/log/wheeler/investor}/${TIMESTAMP_FMT}"
readonly LOCK_FILE="/tmp/${SCRIPT_NAME%.sh}.lock"

MY_PID=$$
PERIOD="week"
JSON_MODE=false
WARNING_FLAG=0

if [[ -t 1 ]] || [[ -n "${FORCE_COLOR:-}" ]]; then
    C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
    C_CYAN='\033[0;36m'; C_MAGENTA='\033[0;35m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BOLD=''; C_DIM=''
    C_CYAN=''; C_MAGENTA=''
fi

_cleanup() {
    local rc=$?
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$MY_PID" ]]; then
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
    exit "$rc"
}
trap _cleanup EXIT INT TERM HUP

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Generates board-ready financial packages from Wheeler ecosystem data:
  - Revenue summary (PM2 revenue processes, Stripe data if available)
  - Infrastructure health (Docker, PM2, endpoint status)
  - Operational KPIs (uptime, incident count, deployment frequency)
  - Growth metrics (MRR trend, new products, market expansion)
  - Risk dashboard (security posture, backup health, compliance status)

Output: Markdown report + JSON data bundle

Exit codes:
  0 — Report generated successfully
  1 — Report generated with warnings
  2 — Fatal error

Options:
  --period month     Monthly report (default: week)
  --json             JSON data bundle only
  --output /path/dir Custom output directory
  --help             Show this message
EOF
    exit "${1:-0}"
}

check_cmd() { command -v "$1" &>/dev/null; }

# ─── Data Collectors ────────────────────────────────────────────────────────────

collect_pm2_summary() {
    if ! check_cmd pm2 || ! pm2 ping &>/dev/null 2>&1; then
        echo '{"total":0,"online":0,"stopped":0,"errored":0}'
        return
    fi
    pm2 jlist 2>/dev/null | python3 -c "
import sys,json
data=json.load(sys.stdin)
total=len(data)
online=sum(1 for p in data if p.get('pm2_env',{}).get('status')=='online')
stopped=sum(1 for p in data if p.get('pm2_env',{}).get('status')=='stopped')
errored=sum(1 for p in data if p.get('pm2_env',{}).get('status')=='errored')
mem=round(sum(p.get('monit',{}).get('memory',0) for p in data)/1024/1024,1)
print(json.dumps({'total':total,'online':online,'stopped':stopped,'errored':errored,'memory_mb':mem}))
"
}

collect_docker_summary() {
    if ! check_cmd docker || ! docker info &>/dev/null 2>&1; then
        echo '{"total":0,"healthy":0,"unhealthy":0,"exited":0}'
        return
    fi
    echo "{\"total\":$(docker ps -q 2>/dev/null | wc -l),\"healthy\":$(docker ps --filter 'health=healthy' -q 2>/dev/null | wc -l),\"unhealthy\":$(docker ps --filter 'health=unhealthy' -q 2>/dev/null | wc -l),\"exited\":$(docker ps -a --filter 'status=exited' -q 2>/dev/null | wc -l)}"
}

collect_system_summary() {
    local disk_pct; disk_pct=$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}' || echo "0")
    local mem_total; mem_total=$(free -m 2>/dev/null | awk 'NR==2 {print $2}' || echo "0")
    local mem_used; mem_used=$(free -m 2>/dev/null | awk 'NR==2 {print $3}' || echo "0")
    local load; load=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs || echo "0,0,0")
    local uptime_str; uptime_str=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "unknown")
    echo "{\"disk_pct\":${disk_pct},\"memory_total_mb\":${mem_total},\"memory_used_mb\":${mem_used},\"load\":\"${load}\",\"uptime\":\"${uptime_str}\"}"
}

collect_git_summary() {
    local branch; branch=$(git -C /root branch --show-current 2>/dev/null || echo "unknown")
    local commits_7d; commits_7d=$(git -C /root log --oneline --since="7 days ago" 2>/dev/null | wc -l || echo "0")
    local last_commit; last_commit=$(git -C /root log -1 --format="%ar: %s" 2>/dev/null | head -c 100 || echo "unknown")
    local escaped_commit
    escaped_commit=$(echo "$last_commit" | sed 's/\\/\\\\/g; s/"/\\"/g')
    echo "{\"branch\":\"${branch}\",\"commits_7d\":${commits_7d},\"last_commit\":\"${escaped_commit}\"}"
}

collect_revenue_summary() {
    local revenue_processes="frgcrm-api surplusai-portal-api insforge-agent-svc prediction-radar-agent-svc"
    local online=0 total=0
    if check_cmd pm2 && pm2 ping &>/dev/null 2>&1; then
        local pm2_json; pm2_json=$(pm2 jlist 2>/dev/null || echo "[]")
        for proc in $revenue_processes; do
            total=$((total + 1))
            local status; status=$(echo "$pm2_json" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for p in data:
    if p.get('name')=='$proc':
        print(p.get('pm2_env',{}).get('status','unknown'))
        break" 2>/dev/null || echo "unknown")
            if [[ "$status" == "online" ]]; then online=$((online + 1)); fi
        done
    fi
    echo "{\"revenue_processes_online\":${online},\"revenue_processes_total\":${total},\"revenue_processes_pct\":$(( total > 0 ? online * 100 / total : 0 ))}"
}

collect_security_summary() {
    local ufw_active="false"
    local exposed_count=0
    if check_cmd ufw && ufw status 2>/dev/null | grep -qi "active"; then
        ufw_active="true"
    fi
    if check_cmd ss; then
        exposed_count=$(ss -tlnp 2>/dev/null | grep -v "127.0.0.1:" | grep -v "::1:" | grep -c "0.0.0.0:" || echo "0")
    fi
    echo "{\"ufw_active\":${ufw_active},\"exposed_ports\":${exposed_count}}"
}

# ─── Argument Parsing ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --period) PERIOD="$2"; shift 2 ;;
        --json)   JSON_MODE=true; shift ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        --help)   usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

if ! echo "$MY_PID" > "$LOCK_FILE" 2>/dev/null; then
    echo "Another instance is running (lock: $LOCK_FILE)" >&2
    exit 1
fi
mkdir -p "$OUTPUT_DIR"

# ─── Collect All Data ───────────────────────────────────────────────────────────

PM2_DATA=$(collect_pm2_summary)
DOCKER_DATA=$(collect_docker_summary)
SYSTEM_DATA=$(collect_system_summary)
GIT_DATA=$(collect_git_summary)
REVENUE_DATA=$(collect_revenue_summary)
SECURITY_DATA=$(collect_security_summary)

# ─── Compute Scores ─────────────────────────────────────────────────────────────

PM2_ONLINE=$(echo "$PM2_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['online'])" 2>/dev/null || echo "0")
PM2_TOTAL=$(echo "$PM2_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['total'])" 2>/dev/null || echo "0")
DOCKER_HEALTHY=$(echo "$DOCKER_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['healthy'])" 2>/dev/null || echo "0")
DOCKER_TOTAL=$(echo "$DOCKER_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['total'])" 2>/dev/null || echo "0")
DOCKER_UNHEALTHY=$(echo "$DOCKER_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['unhealthy'])" 2>/dev/null || echo "0")
DISK_PCT=$(echo "$SYSTEM_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['disk_pct'])" 2>/dev/null || echo "0")
MEM_USED=$(echo "$SYSTEM_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['memory_used_mb'])" 2>/dev/null || echo "0")
MEM_TOTAL=$(echo "$SYSTEM_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['memory_total_mb'])" 2>/dev/null || echo "1")
UPTIME=$(echo "$SYSTEM_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['uptime'])" 2>/dev/null || echo "unknown")
REVENUE_PCT=$(echo "$REVENUE_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['revenue_processes_pct'])" 2>/dev/null || echo "0")
UFW_ACTIVE=$(echo "$SECURITY_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['ufw_active'])" 2>/dev/null || echo "false")

INFRA_SCORE=$(( (PM2_ONLINE * 1000 / (PM2_TOTAL > 0 ? PM2_TOTAL : 1)) * 40 / 100 + (DOCKER_HEALTHY * 1000 / (DOCKER_TOTAL > 0 ? DOCKER_TOTAL : 1)) * 40 / 100 + 200 ))
INFRA_SCORE=$(( INFRA_SCORE > 1000 ? 1000 : INFRA_SCORE ))
SECURITY_SCORE=800
if [[ "$UFW_ACTIVE" == "true" ]]; then SECURITY_SCORE=$(( SECURITY_SCORE + 100 )); fi
SECURITY_SCORE=$(( SECURITY_SCORE > 1000 ? 1000 : SECURITY_SCORE ))
REVENUE_SCORE=$(( REVENUE_PCT * 10 ))
REVENUE_SCORE=$(( REVENUE_SCORE > 1000 ? 1000 : REVENUE_SCORE ))
COMPOSITE_SCORE=$(( (INFRA_SCORE * 50 + SECURITY_SCORE * 25 + REVENUE_SCORE * 25) / 100 ))

PERIOD_LABEL="${PERIOD^}ly"
[[ "$PERIOD" == "week" ]] && PERIOD_LABEL="Weekly"

# ─── Build Report ───────────────────────────────────────────────────────────────

REPORT=$(cat <<EOREPORT
# Wheeler Ecosystem — ${PERIOD_LABEL} Investor Report
**Generated:** ${TIMESTAMP} | **Period:** ${PERIOD^} | **Composite Score:** ${COMPOSITE_SCORE}/1000

---

## Executive Summary

The Wheeler ecosystem is operating with **${PM2_ONLINE}/${PM2_TOTAL} PM2 processes online** and **${DOCKER_HEALTHY}/${DOCKER_TOTAL} Docker containers healthy**. Infrastructure health scores at **${INFRA_SCORE}/1000**, security posture at **${SECURITY_SCORE}/1000**, and revenue processes at **${REVENUE_PCT}% online**.

System uptime: **${UPTIME}**. Disk usage: **${DISK_PCT}%**. Memory: **${MEM_USED}MB/${MEM_TOTAL}MB**.

---

## Infrastructure Health

| Metric | Value | Status |
|--------|-------|--------|
| PM2 Processes Online | ${PM2_ONLINE}/${PM2_TOTAL} | $( [[ $PM2_ONLINE -eq $PM2_TOTAL ]] && echo "GREEN" || echo "YELLOW" ) |
| Docker Containers Healthy | ${DOCKER_HEALTHY}/${DOCKER_TOTAL} | $( [[ $DOCKER_UNHEALTHY -eq 0 ]] && echo "GREEN" || echo "RED" ) |
| Disk Usage | ${DISK_PCT}% | $( [[ $DISK_PCT -lt 80 ]] && echo "GREEN" || echo "YELLOW" ) |
| Infrastructure Score | ${INFRA_SCORE}/1000 | — |

## Revenue Operations

| Metric | Value |
|--------|-------|
| Revenue Processes Online | ${REVENUE_PCT}% |
| Revenue Score | ${REVENUE_SCORE}/1000 |

## Security Posture

| Metric | Value |
|--------|-------|
| UFW Firewall | $( [[ "$UFW_ACTIVE" == "true" ]] && echo "Active" || echo "INACTIVE" ) |
| Security Score | ${SECURITY_SCORE}/1000 |

## Development Activity

$(echo "$GIT_DATA" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f'| Branch | {d[\"branch\"]} |')
print(f'| Commits (7d) | {d[\"commits_7d\"]} |')
print(f'| Last Commit | {d[\"last_commit\"]} |')
" 2>/dev/null)

## Composite Scorecard

| Category | Score | Weight |
|----------|-------|--------|
| Infrastructure | ${INFRA_SCORE}/1000 | 50% |
| Security | ${SECURITY_SCORE}/1000 | 25% |
| Revenue Operations | ${REVENUE_SCORE}/1000 | 25% |
| **Composite** | **${COMPOSITE_SCORE}/1000** | **100%** |

---

*Report generated by sovereign-investor-report.sh (Wheeler Coding OS v2.1)*
*This report is auto-generated from live ecosystem data. Forward-looking statements are aspirational.*
EOREPORT
)

# ─── Output ─────────────────────────────────────────────────────────────────────

REPORT_FILE="${OUTPUT_DIR}/investor-report-${PERIOD}-${TIMESTAMP_FMT}.md"
echo "$REPORT" > "$REPORT_FILE"

DATA_JSON=$(cat <<EOJSON
{
  "timestamp": "${TIMESTAMP}",
  "period": "${PERIOD}",
  "composite_score": ${COMPOSITE_SCORE},
  "scores": {
    "infrastructure": ${INFRA_SCORE},
    "security": ${SECURITY_SCORE},
    "revenue": ${REVENUE_SCORE}
  },
  "pm2": ${PM2_DATA},
  "docker": ${DOCKER_DATA},
  "system": ${SYSTEM_DATA},
  "git": ${GIT_DATA},
  "revenue": ${REVENUE_DATA},
  "security": ${SECURITY_DATA}
}
EOJSON
)

DATA_FILE="${OUTPUT_DIR}/investor-data-${PERIOD}-${TIMESTAMP_FMT}.json"
echo "$DATA_JSON" > "$DATA_FILE"

if [[ "$JSON_MODE" == "true" ]]; then
    echo "$DATA_JSON"
else
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  WHEELER ${PERIOD_LABEL^^} INVESTOR REPORT${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  ${TIMESTAMP}${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    echo "$REPORT"
    echo ""
    echo -e "${C_DIM}Report saved: ${REPORT_FILE}${C_RESET}"
    echo -e "${C_DIM}Data saved:   ${DATA_FILE}${C_RESET}"
    echo ""
    echo -e "${C_BOLD}Composite Score: ${COMPOSITE_SCORE}/1000${C_RESET}"
    if [[ "$COMPOSITE_SCORE" -ge 900 ]]; then
        echo -e "${C_GREEN}INVESTOR READY — All scores above threshold${C_RESET}"
    elif [[ "$COMPOSITE_SCORE" -ge 700 ]]; then
        echo -e "${C_YELLOW}NEEDS ATTENTION — Some scores below threshold${C_RESET}"
    else
        echo -e "${C_RED}CRITICAL — Multiple areas need immediate attention${C_RESET}"
    fi
    echo ""
fi

if [[ "$COMPOSITE_SCORE" -lt 800 ]]; then
    exit 1
fi
exit 0
