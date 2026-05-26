#!/usr/bin/env bash
# =============================================================================
# sovereign-revenue-recovery.sh — Revenue Recovery Engine
# =============================================================================
#
# Identifies and recovers missed/delinquent revenue across Wheeler products:
#   - PM2 revenue process health monitoring (FRGCRM, SurplusAI, InsForge)
#   - Revenue endpoint verification (APIs, payment webhooks)
#   - Stripe transaction health (if credentials available)
#   - Automated recovery actions (restart dead processes, alert on anomalies)
#   - Recovery action report with priority ranking
#
# Exit codes:
#   0 — All revenue systems healthy, no recovery needed
#   1 — Revenue systems have issues, recovery actions generated
#   2 — Fatal error or pre-flight check failure
#
# Usage:
#   ./sovereign-revenue-recovery.sh                    # Full recovery scan
#   ./sovereign-revenue-recovery.sh --auto-recover      # Auto-apply safe fixes
#   ./sovereign-revenue-recovery.sh --product frgcrm    # Single product scan
#   ./sovereign-revenue-recovery.sh --json              # Machine-readable
#   ./sovereign-revenue-recovery.sh --help              # This message
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly TIMESTAMP_FMT="$(date +%Y%m%d-%H%M%S)"
readonly OUTPUT_DIR="${OUTPUT_DIR:-/var/log/wheeler/revenue}/${TIMESTAMP_FMT}"
readonly LOCK_FILE="/tmp/${SCRIPT_NAME%.sh}.lock"
readonly CHECK_TIMEOUT="${CHECK_TIMEOUT:-5}"

MY_PID=$$
JSON_MODE=false
AUTO_RECOVER=false
TARGET_PRODUCT=""
ISSUES_FOUND=0
RECOVERED=0
FAILED_RECOVERIES=0
declare -a RECOVERY_ACTIONS=()
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
    exit "$rc"
}
trap _cleanup EXIT INT TERM HUP

usage() {
    sed -n '/^# =====/,/^# =====/p' "$0" | head -30 | sed 's/^# //'
    exit "${1:-0}"
}

check_cmd() { command -v "$1" &>/dev/null; }

recovery_entry() {
    local priority="$1" product="$2" action="$3" detail="$4"
    local icon
    case "$priority" in
        CRITICAL) icon="${C_RED}[CRIT]${C_RESET}"; ((ISSUES_FOUND++)) || true ;;
        HIGH)     icon="${C_RED}[HIGH]${C_RESET}"; ((ISSUES_FOUND++)) || true ;;
        MEDIUM)   icon="${C_YELLOW}[MED]${C_RESET}"; ((ISSUES_FOUND++)) || true ;;
        LOW)      icon="${C_DIM}[LOW]${C_RESET}" ;;
        OK)       icon="${C_GREEN}[OK]${C_RESET}" ;;
    esac
    if [[ "$JSON_MODE" == "false" ]]; then
        printf "  %b %-15s %-40s %s\n" "$icon" "$product" "$action" "$detail"
    fi
    JSON_RESULTS+=("{\"priority\":\"${priority}\",\"product\":\"${product}\",\"action\":\"${action}\",\"detail\":\"${detail}\"}")
}

_http_code() {
    curl -s -o /dev/null -w '%{http_code}' --max-time "$CHECK_TIMEOUT" "$1" 2>/dev/null || echo "000"
}

# ─── Argument Parsing ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto-recover) AUTO_RECOVER=true; shift ;;
        --product)      TARGET_PRODUCT="$2"; shift 2 ;;
        --json)         JSON_MODE=true; shift ;;
        --help)         usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

mkdir -p "$OUTPUT_DIR"
echo "$MY_PID" > "$LOCK_FILE" 2>/dev/null || true

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  WHEELER REVENUE RECOVERY ENGINE${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  ${TIMESTAMP}${C_RESET}"
    [[ "$AUTO_RECOVER" == "true" ]] && echo -e "${C_BOLD}${C_YELLOW}  Auto-recovery: ENABLED${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# PRODUCT DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════════

declare -A REVENUE_PRODUCTS=(
    ["frgcrm"]="FRGCRM:frgcrm-api:8082:/health:Lead Management & CRM"
    ["surplusai"]="SurplusAI:surplusai-portal-api:8103:/health:Surplus Fund Recovery"
    ["insforge"]="InsForge:insforge-agent-svc:8013:/health:Insurance Claims"
    ["predictionradar"]="PredictionRadar:prediction-radar-agent-svc:8011:/health:Foreclosure Prediction"
    ["ravynai"]="RavynAI:ravyn-agent-svc:8005:/health:AI Legal Assistant"
)

# ═══════════════════════════════════════════════════════════════════════════════
# SCAN: PM2 Revenue Process Health
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo -e "${C_BOLD}${C_BLUE}━━━ PM2 REVENUE PROCESSES ━━━${C_RESET}"
fi

PM2_JSON="[]"
if check_cmd pm2 && pm2 ping &>/dev/null 2>&1; then
    PM2_JSON=$(pm2 jlist 2>/dev/null || echo "[]")
else
    recovery_entry "CRITICAL" "PM2" "PM2 daemon unavailable" "Cannot verify any revenue processes"
fi

for product_key in "${!REVENUE_PRODUCTS[@]}"; do
    [[ -n "$TARGET_PRODUCT" && "$product_key" != "$TARGET_PRODUCT" ]] && continue

    IFS=":" read -r product_name pm2_name port health_path description <<< "${REVENUE_PRODUCTS[$product_key]}"

    pm2_status=$(echo "$PM2_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
status='not_found'
for p in data:
    if p.get('name')=='${pm2_name}':
        status=p.get('pm2_env',{}).get('status','unknown')
        break
print(status)" 2>/dev/null || echo "unknown")

    pm2_restarts=$(echo "$PM2_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
restarts=0
for p in data:
    if p.get('name')=='${pm2_name}':
        restarts=p.get('pm2_env',{}).get('restart_time',0)
        break
print(restarts)" 2>/dev/null || echo "0")

    case "$pm2_status" in
        online)
            if [[ "$pm2_restarts" -gt 50 ]]; then
                recovery_entry "HIGH" "$product_name" "High restart count: ${pm2_restarts}" "Investigate crash pattern for ${pm2_name}"
                if [[ "$AUTO_RECOVER" == "true" ]]; then
                    recovery_entry "MEDIUM" "$product_name" "Cannot auto-fix high restarts" "Manual investigation needed"
                    FAILED_RECOVERIES=$((FAILED_RECOVERIES + 1))
                fi
            else
                recovery_entry "OK" "$product_name" "PM2 online (${pm2_restarts} restarts)" "${description}"
            fi
            ;;
        stopped)
            recovery_entry "CRITICAL" "$product_name" "PM2 process stopped: ${pm2_name}" "Revenue process is down"
            if [[ "$AUTO_RECOVER" == "true" ]]; then
                if env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
                    PM2_HOME=/root/.pm2 pm2 start "$pm2_name" 2>/dev/null; then
                    recovery_entry "OK" "$product_name" "Auto-restarted ${pm2_name}" "Recovery successful"
                    RECOVERED=$((RECOVERED + 1))
                else
                    recovery_entry "HIGH" "$product_name" "Auto-restart failed: ${pm2_name}" "Manual intervention required"
                    FAILED_RECOVERIES=$((FAILED_RECOVERIES + 1))
                fi
            fi
            ;;
        errored)
            recovery_entry "CRITICAL" "$product_name" "PM2 process errored: ${pm2_name}" "Crash loop detected"
            if [[ "$AUTO_RECOVER" == "true" ]]; then
                recovery_entry "HIGH" "$product_name" "Errored process needs manual investigation" "Check logs: pm2 logs ${pm2_name}"
                FAILED_RECOVERIES=$((FAILED_RECOVERIES + 1))
            fi
            ;;
        not_found)
            recovery_entry "HIGH" "$product_name" "PM2 process not found: ${pm2_name}" "May not be deployed"
            ;;
        *)
            recovery_entry "MEDIUM" "$product_name" "PM2 status: ${pm2_status}" "Investigate ${pm2_name}"
            ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════
# SCAN: Revenue Endpoint Health
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ REVENUE ENDPOINTS ━━━${C_RESET}"
fi

for product_key in "${!REVENUE_PRODUCTS[@]}"; do
    [[ -n "$TARGET_PRODUCT" && "$product_key" != "$TARGET_PRODUCT" ]] && continue

    IFS=":" read -r product_name pm2_name port health_path description <<< "${REVENUE_PRODUCTS[$product_key]}"

    url="http://127.0.0.1:${port}${health_path}"
    http_code=$(_http_code "$url")

    if [[ "$http_code" == "200" ]]; then
        recovery_entry "OK" "$product_name" "Endpoint healthy" "HTTP 200 on :${port}${health_path}"
    elif [[ "$http_code" == "000" ]]; then
        recovery_entry "HIGH" "$product_name" "Endpoint unreachable" "Connection refused on :${port}"
        if [[ "$AUTO_RECOVER" == "true" ]]; then
            # Check if PM2 process needs restart
            pm2_status=$(echo "$PM2_JSON" | python3 -c "
import sys,json
for p in json.load(sys.stdin):
    if p.get('name')=='${pm2_name}':
        print(p.get('pm2_env',{}).get('status','unknown'))
        break" 2>/dev/null || echo "not_found")
            if [[ "$pm2_status" == "stopped" ]]; then
                env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
                    PM2_HOME=/root/.pm2 pm2 start "$pm2_name" 2>/dev/null && RECOVERED=$((RECOVERED + 1)) || true
            fi
        fi
    else
        recovery_entry "MEDIUM" "$product_name" "Endpoint HTTP ${http_code}" "Expected 200 on :${port}${health_path}"
    fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# SCAN: Payment Gateway Webhooks
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ PAYMENT GATEWAYS ━━━${C_RESET}"
fi

# Stripe webhook endpoint check
STRIPE_WEBHOOK_URL="http://127.0.0.1:8082/webhooks/stripe"
STRIPE_CODE=$(_http_code "$STRIPE_WEBHOOK_URL" 2>/dev/null || echo "000")
if [[ "$STRIPE_CODE" == "200" ]] || [[ "$STRIPE_CODE" == "405" ]]; then
    recovery_entry "OK" "Stripe" "Webhook endpoint responding" "HTTP ${STRIPE_CODE}"
elif [[ "$STRIPE_CODE" == "000" ]]; then
    recovery_entry "MEDIUM" "Stripe" "Webhook endpoint unreachable" "FRGCRM API may be down"
else
    recovery_entry "LOW" "Stripe" "Webhook HTTP ${STRIPE_CODE}" "Verify webhook configuration"
fi

# Check PM2 revenue-metrics-collector
REVENUE_COLLECTOR=$(echo "$PM2_JSON" | python3 -c "
import sys,json
for p in json.load(sys.stdin):
    if 'revenue' in p.get('name','').lower() or 'stripe' in p.get('name','').lower():
        print(f\"{p['name']}:{p.get('pm2_env',{}).get('status','unknown')}\")
" 2>/dev/null || echo "")
if [[ -n "$REVENUE_COLLECTOR" ]]; then
    recovery_entry "OK" "Revenue Collector" "${REVENUE_COLLECTOR}" "Revenue metrics collection active"
else
    recovery_entry "LOW" "Revenue Collector" "No dedicated collector process" "Consider deploying revenue-metrics-collector"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SCAN: Docker Revenue Containers
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_BLUE}━━━ DOCKER REVENUE SERVICES ━━━${C_RESET}"
fi

if check_cmd docker && docker info &>/dev/null 2>&1; then
    revenue_containers=$(docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -iE "frg|surplus|insforge|prediction|ravyn|stripe|payment|billing" || echo "")
    if [[ -n "$revenue_containers" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            c_name="" c_status=""
            c_name=$(echo "$line" | awk '{print $1}')
            c_status=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
            if echo "$c_status" | grep -qi "unhealthy"; then
                recovery_entry "HIGH" "Docker" "${c_name}" "UNHEALTHY — restart may be needed"
                if [[ "$AUTO_RECOVER" == "true" ]]; then
                    docker restart "$c_name" >/dev/null 2>&1 && RECOVERED=$((RECOVERED + 1)) || FAILED_RECOVERIES=$((FAILED_RECOVERIES + 1))
                fi
            fi
            echo "$c_name $c_status" >> "${OUTPUT_DIR}/revenue-containers.txt"
        done <<< "$revenue_containers"
        container_count=$(echo "$revenue_containers" | wc -l)
        recovery_entry "OK" "Docker" "${container_count} revenue containers" "All revenue containers identified"
    else
        recovery_entry "LOW" "Docker" "No revenue containers found" "Revenue services may be PM2-only"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY + REPORT
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  RECOVERY SCAN SUMMARY${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    echo -e "  Issues found:       ${C_RED}${ISSUES_FOUND}${C_RESET}"
    echo -e "  Auto-recovered:     ${C_GREEN}${RECOVERED}${C_RESET}"
    echo -e "  Failed recoveries:  ${C_RED}${FAILED_RECOVERIES}${C_RESET}"
    echo ""
    if [[ "$ISSUES_FOUND" -eq 0 ]]; then
        echo -e "${C_GREEN}${C_BOLD}  ALL REVENUE SYSTEMS HEALTHY — NO RECOVERY NEEDED${C_RESET}"
    elif [[ "$ISSUES_FOUND" -gt 0 ]] && [[ "$AUTO_RECOVER" == "false" ]]; then
        echo -e "${C_YELLOW}  Run with --auto-recover to attempt automatic fixes${C_RESET}"
    fi
    echo ""
    echo -e "${C_DIM}  Report: ${OUTPUT_DIR}/recovery-report-${TIMESTAMP_FMT}.json${C_RESET}"
    echo ""
fi

# Build JSON report
printf -v joined '%s,' "${JSON_RESULTS[@]}"
joined="${joined%,}"

REPORT_JSON=$(cat <<EOJSON
{
  "timestamp": "${TIMESTAMP}",
  "auto_recover": ${AUTO_RECOVER},
  "issues_found": ${ISSUES_FOUND},
  "recovered": ${RECOVERED},
  "failed_recoveries": ${FAILED_RECOVERIES},
  "actions": [${joined:-}]
}
EOJSON
)

if [[ "$JSON_MODE" == "true" ]]; then
    echo "$REPORT_JSON"
fi

echo "$REPORT_JSON" > "${OUTPUT_DIR}/recovery-report-${TIMESTAMP_FMT}.json"

if [[ "$ISSUES_FOUND" -gt 0 ]]; then
    exit 1
fi
exit 0
