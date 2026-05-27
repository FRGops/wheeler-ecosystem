#!/usr/bin/env bash
#===============================================================================
# ecosystem-health.sh
# Wheeler Autonomous AI Ops Platform - Master Watchdog Orchestrator
#
# Runs all 6 watchdog scripts sequentially, aggregates results into a
# single health score (0-100), generates a consolidated JSON report, and
# optionally triggers a webhook alert on failures.
#
# Usage:
#   ./ecosystem-health.sh                         # Full output with color
#   ./ecosystem-health.sh --quiet                 # Score + alerts only
#   ./ecosystem-health.sh --webhook URL           # Post results to webhook
#   ./ecosystem-health.sh --json                  # JSON report to stdout
#   ./ecosystem-health.sh --help                  # This help text
#
# Exit codes:
#   0 - All healthy (score >= 90)
#   1 - Non-critical issues (score >= 70)
#   2 - Critical issues (score < 70)
#===============================================================================
set -euo pipefail

# ---- Constants ----
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REPORT_FILE="${SCRIPT_DIR}/health-report.json"

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Watchdog scripts
WATCHDOGS=(
    "docker-watchdog.sh"
    "pm2-watchdog.sh"
    "port-watchdog.sh"
    "resource-watchdog.sh"
    "exposure-watchdog.sh"
    "repo-watchdog.sh"
)

# Weights for each subsystem (must sum to 100)
declare -A WEIGHTS
WEIGHTS["docker-watchdog.sh"]=25
WEIGHTS["pm2-watchdog.sh"]=20
WEIGHTS["port-watchdog.sh"]=20
WEIGHTS["resource-watchdog.sh"]=15
WEIGHTS["exposure-watchdog.sh"]=10
WEIGHTS["repo-watchdog.sh"]=10

# ---- Help ----
show_help() {
    sed -ne '/^#===-/,/^#===/p' "$0" | head -n -1 | sed 's/^#//'
    exit 0
}

# ---- Output helpers ----
echo_color() {
    local color="$1"
    local text="$2"
    echo -e "${color}${text}${NC}"
}

echo_progress() {
    echo -e "${CYAN}[PROGRESS]${NC} $1" >&2
}

# ---- Scoring ----
calculate_score() {
    local pass="$1"
    local total="$2"
    if [[ "${total}" -eq 0 ]]; then
        echo 100
    else
        echo $(( (pass * 100) / total ))
    fi
}

get_color_for_score() {
    local score="$1"
    if [[ "${score}" -ge 90 ]]; then
        echo "GREEN"
    elif [[ "${score}" -ge 70 ]]; then
        echo "YELLOW"
    else
        echo "RED"
    fi
}

ansi_color_for_score() {
    local score="$1"
    if [[ "${score}" -ge 90 ]]; then
        echo "${GREEN}"
    elif [[ "${score}" -ge 70 ]]; then
        echo "${YELLOW}"
    else
        echo "${RED}"
    fi
}

# ---- Webhook notification ----
send_webhook() {
    local webhook_url="$1"
    local report_file="$2"

    if [[ -z "${webhook_url}" ]]; then
        return
    fi

    echo_progress "Sending webhook alert to ${webhook_url}"

    local status
    status="$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "User-Agent: Wheeler-Watchdog/1.0" \
        -d @"${report_file}" \
        --connect-timeout 10 \
        --max-time 30 \
        "${webhook_url}" 2>/dev/null || echo "000")"

    if [[ "${status}" =~ ^2[0-9][0-9]$ ]]; then
        echo_progress "Webhook sent successfully (HTTP ${status})"
    else
        echo -e "${YELLOW}[WARN]${NC} Webhook returned HTTP ${status}" >&2
    fi
}

# ---- JSON generation ----
generate_report_json() {
    local timestamp="$1"
    local overall_score="$2"
    local overall_status="$3"
    local subsystems_json="$4"
    local alerts_json="$5"

    python3 -c "
import json, sys

report = {
    'ecosystem_health': {
        'script': 'ecosystem-health',
        'timestamp': '${timestamp}',
        'version': '1.0.0',
        'platform': 'Wheeler Autonomous AI Ops',
    },
    'summary': {
        'overall_score': ${overall_score},
        'status': '${overall_status}',
        'classification': 'healthy' if ${overall_score} >= 90 else ('degraded' if ${overall_score} >= 70 else 'critical'),
    },
    'subsystems': ${subsystems_json},
    'alerts': ${alerts_json},
}

json.dump(report, sys.stdout, indent=2)
print()
"
}

# ---- Prometheus metrics output (optional) ----
generate_metrics() {
    local overall_score="$1"
    local subsystems_json="$2"

    echo "# HELP wheeler_ecosystem_health_score Overall ecosystem health score (0-100)"
    echo "# TYPE wheeler_ecosystem_health_score gauge"
    echo "wheeler_ecosystem_health_score ${overall_score}"

    echo "${subsystems_json}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data:
    name = item.get('name', 'unknown')
    score = item.get('score', 0)
    pass_count = item.get('pass', 0)
    fail_count = item.get('fail', 0)
    total = item.get('total', 0)
    safe_name = name.replace('.sh', '').replace('-', '_')
    print(f'# HELP wheeler_{safe_name}_score Subsystem health score')
    print(f'# TYPE wheeler_{safe_name}_score gauge')
    print(f'wheeler_{safe_name}_score {score}')
    print(f'# HELP wheeler_{safe_name}_checks_total Total checks')
    print(f'# TYPE wheeler_{safe_name}_checks_total gauge')
    print(f'wheeler_{safe_name}_checks_total {total}')
    print(f'# HELP wheeler_{safe_name}_checks_failed Failed checks')
    print(f'# TYPE wheeler_{safe_name}_checks_failed gauge')
    print(f'wheeler_{safe_name}_checks_failed {fail_count}')
"
}

# ---- Main ----
main() {
    local mode="standard"
    local webhook_url=""
    local quiet=false
    local critical_count=0 warn_count=0 info_count=0

    for arg in "$@"; do
        case "${arg}" in
            --help|-h) show_help ;;
            --quiet) quiet=true ;;
            --json) mode="json" ;;
            --metrics) mode="metrics" ;;
            --webhook=*) webhook_url="${arg#*=}" ;;
            --webhook)
                # Next arg is URL - warning: brittle with mixing flags
                ;;
        esac
    done

    # Handle --webhook URL
    local args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[$i]}" == "--webhook" && $((i+1)) -lt ${#args[@]} ]]; then
            webhook_url="${args[$((i+1))]}"
        fi
    done

    if ! ${quiet}; then
        echo ""
        echo_color "${BOLD}" "============================================"
        echo_color "${BOLD}" "  Wheeler AI Ops - Ecosystem Health Scan"
        echo_color "${BOLD}" "  ${TIMESTAMP}"
        echo_color "${BOLD}" "============================================"
        echo ""
    fi

    # Verify all watchdog scripts exist and are executable
    local missing=0
    for wd in "${WATCHDOGS[@]}"; do
        if [[ ! -x "${SCRIPT_DIR}/${wd}" ]]; then
            echo -e "${RED}[ERROR]${NC} Watchdog script not found/executable: ${SCRIPT_DIR}/${wd}" >&2
            ((missing++))
        fi
    done
    if [[ "${missing}" -gt 0 ]]; then
        echo -e "${RED}[FATAL]${NC} ${missing} watchdog scripts missing. Run chmod +x on all scripts." >&2
        exit 2
    fi

    # Run all watchdogs and collect results
    local subsystems_json=""
    local all_alerts="[]"
    local overall_pass=0
    local overall_total=0
    local weighted_score=0
    local subsystems=()

    for wd in "${WATCHDOGS[@]}"; do
        local wd_name="${wd%.sh}"
        local weight="${WEIGHTS[${wd}]:-10}"

        if ! ${quiet}; then
            echo_progress "Running ${wd}..."
        fi

        # Run sub-watchdog for alerts only; we compute scores directly
        local json_output alerts
        json_output="$("${SCRIPT_DIR}/${wd}" --json 2>/dev/null)" || true
        if [[ -z "${json_output}" ]]; then
            json_output='{"alerts":[]}'
        fi
        alerts="$(echo "${json_output}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get("alerts",[])))' 2>/dev/null || echo '[]')"

        # Compute score directly from live ecosystem state
        local total=0 pass=0 fail=0 score=0

        case "${wd_name}" in
            docker-watchdog)
                total=$(docker ps -a --format '{{.Names}}' 2>/dev/null | wc -l)
                healthy=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)
                pass=$healthy
                fail=$(( total - healthy ))
                # Check for 0.0.0.0 binds
                public_binds=$(docker ps --format '{{.Ports}}' 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+:\d+' | grep -v '127\.0\.0\.1' | grep -v '100\.' | wc -l | tr -d ' ' || echo 0)
                # Compute without ternary (bash doesn't support it)
                if [[ $total -gt 0 ]]; then score=$(( healthy * 100 / total )); else score=0; fi
                [[ ${public_binds//[[:space:]]/} -gt 0 ]] 2>/dev/null && score=$(( score - 20 ))
                [[ $score -lt 0 ]] && score=0
                ;;
            pm2-watchdog)
                total=$(pm2 jlist 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null | tr -d ' \n' || echo 0)
                online=$(pm2 jlist 2>/dev/null | python3 -c 'import json,sys; print(sum(1 for p in json.load(sys.stdin) if p["pm2_env"]["status"]=="online" and p["name"]!="frgcrm-agent-svc"))' 2>/dev/null | tr -d ' \n' || echo 0)
                pass=$online
                fail=$(( total - online ))
                loops=$(pm2 jlist 2>/dev/null | python3 -c 'import json,sys; print(sum(1 for p in json.load(sys.stdin) if p["pm2_env"].get("restart_time",0)>5))' 2>/dev/null | tr -d ' \n' || echo 0)
                if [[ $total -gt 0 ]]; then score=$(( online * 100 / total )); else score=0; fi
                [[ $loops -gt 0 ]] && score=$(( score - 30 ))
                [[ $score -lt 0 ]] && score=0
                ;;
            port-watchdog)
                unexpected=$(ss -tlnp 2>/dev/null | grep '0.0.0.0' | grep -v ':22 ' | grep -v '127\.' | grep -cv '100\.' | tr -d ' \n' || echo 0)
                total=1
                if [[ ${unexpected:-0} -eq 0 ]]; then
                    pass=1; score=100
                else
                    fail=1; score=$(( 100 - unexpected * 20 ))
                    [[ $score -lt 0 ]] && score=0
                fi
                ;;
            resource-watchdog)
                total=4
                disk_pct=$(df -h / 2>/dev/null | awk 'NR==2{gsub(/%/,""); print $5}' | tr -d ' \n')
                if [[ ${disk_pct:-0} -lt 80 ]]; then pass=$(( pass + 1 )); else fail=$(( fail + 1 )); fi
                ram_pct=$(free 2>/dev/null | awk '/^Mem:/{printf "%.0f", $3*100/$2}' | tr -d ' \n')
                if [[ ${ram_pct:-0} -lt 85 ]]; then pass=$(( pass + 1 )); else fail=$(( fail + 1 )); fi
                load5=$(awk '{print $2}' /proc/loadavg 2>/dev/null | cut -d. -f1 | tr -d ' \n')
                cores=$(nproc 2>/dev/null | tr -d ' \n' || echo 1)
                if [[ ${load5:-0} -lt $(( cores * 80 / 100 )) ]]; then pass=$(( pass + 1 )); else fail=$(( fail + 1 )); fi
                swap_pct=$(free 2>/dev/null | awk '/^Swap:/{if($2>0) printf "%.0f", $3*100/$2; else print 0}' | tr -d ' \n')
                if [[ ${swap_pct:-0} -lt 20 ]]; then pass=$(( pass + 1 )); else fail=$(( fail + 1 )); fi
                score=$(( pass * 100 / total ))
                ;;
            exposure-watchdog)
                total=1
                exposed=$(docker ps --format '{{.Ports}}' 2>/dev/null | grep -oP '0\.0\.0\.0:\d+' | grep -v ':22' | wc -l | tr -d ' \n' || echo 0)
                if [[ ${exposed:-0} -eq 0 ]]; then
                    pass=1; score=100
                else
                    fail=1; score=$(( 100 - exposed * 30 ))
                    [[ $score -lt 0 ]] && score=0
                fi
                ;;
            repo-watchdog)
                # Score from repo-watchdog JSON output
                local repo_json repo_score
                repo_json=$("${SCRIPT_DIR}/repo-watchdog.sh" --json 2>/dev/null || echo '{"score":100}')
                repo_score=$(echo "$repo_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("score",100))' 2>/dev/null || echo 100)
                total=7; pass=0; fail=0; score=${repo_score:-100}
                # Count alerts from JSON
                local alert_count
                alert_count=$(echo "$repo_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("alerts",[])))' 2>/dev/null || echo 0)
                pass=$(( total - alert_count ))
                fail=$(( alert_count ))
                [[ $pass -lt 0 ]] && pass=0
                ;;
        esac

        # Clamp
        [[ $score -gt 100 ]] && score=100
        [[ $score -lt 0 ]] && score=0

        overall_pass=$(( overall_pass + pass ))
        overall_total=$(( overall_total + total + fail ))
        weighted_score=$(( weighted_score + (score * weight) ))

        local subsystem_entry
        subsystem_entry="$(python3 -c "
import json
entry = {
    'name': '${wd_name}',
    'weight': ${weight},
    'total': ${total},
    'pass': ${pass},
    'fail': ${fail},
    'score': ${score},
}
print(json.dumps(entry))
" 2>/dev/null)"

        subsystems+=("${subsystem_entry}")

        # Merge alerts via stdin to avoid shell quoting issues
        all_alerts="$(echo "${alerts}" | python3 -c "
import json, sys
try:
    current = json.loads('${all_alerts}')
    new = json.load(sys.stdin)
    if isinstance(new, list):
        current.extend(new)
    print(json.dumps(current))
except Exception:
    print(json.dumps([]))
" 2>/dev/null || echo '[]')"

        if ! ${quiet}; then
            local color
            if [[ "${score}" -ge 90 ]]; then color="${GREEN}"
            elif [[ "${score}" -ge 70 ]]; then color="${YELLOW}"
            else color="${RED}"; fi
            echo -e "  ${color}${wd_name}: ${score}/100${NC}"
        fi
    done

    # Calculate overall score
    local overall_score=0
    if [[ ${#WATCHDOGS[@]} -gt 0 ]]; then
        overall_score=$(( weighted_score / 100 ))
    fi

    # Assemble subsystems JSON
    subsystems_json="["
    local first=true
    for s in "${subsystems[@]}"; do
        ${first} || subsystems_json+=","
        first=false
        subsystems_json+="${s}"
    done
    subsystems_json+="]"

    # Determine status
    local overall_status
    if [[ "${overall_score}" -ge 90 ]]; then
        overall_status="HEALTHY"
    elif [[ "${overall_score}" -ge 70 ]]; then
        overall_status="DEGRADED"
    else
        overall_status="CRITICAL"
    fi

    # Generate and write report
    local final_report
    final_report="$(generate_report_json "${TIMESTAMP}" "${overall_score}" "${overall_status}" "${subsystems_json}" "${all_alerts}")"
    echo "${final_report}" > "${REPORT_FILE}"

    # Send webhook if configured
    if [[ -n "${webhook_url}" ]]; then
        send_webhook "${webhook_url}" "${REPORT_FILE}"
    fi

    # === OUTPUT ===
    local overall_color
    overall_color="$(ansi_color_for_score "${overall_score}")"

    case "${mode}" in
        json)
            cat "${REPORT_FILE}"
            ;;
        metrics)
            generate_metrics "${overall_score}" "${subsystems_json}"
            ;;
        standard|*)
            if ! ${quiet}; then
                echo ""
                echo_color "${BOLD}" "============================================"
                echo -e "${BOLD}  Overall Score: ${overall_color}${overall_score}/100${NC}"
                echo -e "${BOLD}  Status:        ${overall_color}${overall_status}${NC}"
                echo_color "${BOLD}" "============================================"
                echo ""

                # Count alerts by severity
                critical_count=0; warn_count=0; info_count=0
                critical_count="$(echo "${all_alerts}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for a in d if "CRITICAL" in str(a) or "HIGH" in str(a)))' 2>/dev/null || echo 0)"
                warn_count="$(echo "${all_alerts}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for a in d if "WARN" in str(a)))' 2>/dev/null || echo 0)"
                info_count="$(echo "${all_alerts}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for a in d if "INFO" in str(a)))' 2>/dev/null || echo 0)"

                if [[ "${critical_count}" -gt 0 ]]; then
                    echo -e "${RED}  High severity alerts: ${critical_count}${NC}"
                fi
                if [[ "${warn_count}" -gt 0 ]]; then
                    echo -e "${YELLOW}  Warnings: ${warn_count}${NC}"
                fi
                if [[ "${info_count}" -gt 0 ]]; then
                    echo -e "${CYAN}  Info: ${info_count}${NC}"
                fi
                if [[ "${critical_count}" -eq 0 && "${warn_count}" -eq 0 ]]; then
                    echo -e "${GREEN}  No alerts. All subsystems nominal.${NC}"
                fi
                echo ""

                # Subsystem summary table
                printf "  %-30s %-8s %-8s %-6s\n" "SUBSYSTEM" "PASS" "FAIL" "SCORE"
                printf "  %-30s %-8s %-8s %-6s\n" "------------------------------" "--------" "--------" "------"
                for s in "${subsystems[@]}"; do
                    local s_name s_pass s_fail s_score
                    s_name="$(echo "${s}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["name"])' 2>/dev/null)"
                    s_pass="$(echo "${s}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["pass"])' 2>/dev/null)"
                    s_fail="$(echo "${s}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["fail"])' 2>/dev/null)"
                    s_score="$(echo "${s}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["score"])' 2>/dev/null)"
                    local s_color
                    if [[ "${s_score}" -ge 90 ]]; then s_color="${GREEN}"
                    elif [[ "${s_score}" -ge 70 ]]; then s_color="${YELLOW}"
                    else s_color="${RED}"; fi
                    echo -e "  ${s_color}%-30s %-8s %-8s %-6s${NC}" "${s_name}" "${s_pass}" "${s_fail}" "${s_score}"
                done
                echo ""
                echo "  Report saved: ${REPORT_FILE}"

                # Alert details
                if [[ "${critical_count}" -gt 0 || "${warn_count}" -gt 0 ]]; then
                    echo ""
                    echo_color "${BOLD}" "============================================"
                    echo_color "${BOLD}" "  Alert Details"
                    echo_color "${BOLD}" "============================================"
                    echo ""
                    local alert_index=0
                    while IFS= read -r alert_line; do
                        [[ -z "${alert_line}" ]] && continue
                        # Color-code by severity
                        if echo "${alert_line}" | grep -q "CRITICAL\|HIGH"; then
                            echo -e "  ${RED}${alert_line}${NC}"
                        elif echo "${alert_line}" | grep -q "WARN"; then
                            echo -e "  ${YELLOW}${alert_line}${NC}"
                        else
                            echo -e "  ${CYAN}${alert_line}${NC}"
                        fi
                    done < <(echo "${all_alerts}" | python3 -c '
import json, sys
alerts = json.load(sys.stdin)
for a in alerts:
    print(a)
' 2>/dev/null || true)
                fi

                echo ""
                echo "========================================"
                echo -e " Report:    ${REPORT_FILE}"
                echo -e " Webhook:   ${webhook_url:-not configured}"
                echo "========================================"
            fi

            # When quiet, only show score and summary
            if ${quiet}; then
                echo "${overall_score}|${overall_status}|P:${overall_pass}/T:${overall_total}|A:$(( critical_count + warn_count ))"
            fi
            ;;
    esac

    # Exit with appropriate code
    if [[ "${overall_score}" -ge 90 ]]; then
        exit 0
    elif [[ "${overall_score}" -ge 70 ]]; then
        exit 1
    else
        exit 2
    fi
}

main "$@"
