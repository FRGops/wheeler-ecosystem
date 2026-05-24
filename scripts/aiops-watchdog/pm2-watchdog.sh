#!/usr/bin/env bash
#===============================================================================
# pm2-watchdog.sh
# Wheeler Autonomous AI Ops Platform - PM2 Process Health Monitor
#
# Monitors all PM2 processes for:
#   - Process status (online, stopped, errored)
#   - Restart count threshold (>5 alerts)
#   - Memory usage (>500MB alerts)
#   - CPU usage (>50% alerts)
#   - Env var integrity (DEEPSEEK_API_KEY presence where needed)
#
# Usage:
#   ./pm2-watchdog.sh                    # Standard output (alerts + summary)
#   ./pm2-watchdog.sh --json             # JSON health report only
#   ./pm2-watchdog.sh --alerts-only      # Alerts only, no summary
#   ./pm2-watchdog.sh --help             # This help text
#
# Output: JSON health report + alerts to stdout
# Severity levels: INFO, WARN, HIGH, CRITICAL
#===============================================================================
set -euo pipefail

# ---- Constants ----
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ALERTS=()
PASS=0
FAIL=0
WARN=0

# ---- Thresholds ----
RESTART_WARN_THRESHOLD=5         # Alert if restart count > this
MEMORY_WARN_BYTES=$((500 * 1024 * 1024))  # 500MB in bytes
CPU_WARN_PERCENT=50.0

# ---- Processes that need DEEPSEEK_API_KEY ----
# These are known AI agent processes that require the key
DEEPSEEK_REQUIRED_PROCESSES=(
    "design-agent-svc"
    "horizon-agent-svc"
    "paperless-agent-svc"
    "ravyn-agent-svc"
    "surplusai-scraper-agent-svc"
    "voice-agent-svc"
    "frgcrm-agent-svc"
    "insforge-agent-svc"
    "prediction-radar-agent-svc"
)

# ---- Help ----
show_help() {
    sed -ne '/^#===-/,/^#===/p' "$0" | head -n -1 | sed 's/^#//'
    exit 0
}

# ---- Output helpers ----
alert() {
    local severity="$1"
    local message="$2"
    local entry="[${severity}] [${TIMESTAMP}] [pm2-watchdog] ${message}"
    ALERTS+=("${entry}")
    echo "${entry}" >&2
}

json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

emit_alerts_json() {
    if [[ ${#ALERTS[@]} -eq 0 ]]; then
        echo '[]'
        return
    fi
    local first=true
    echo '['
    for a in "${ALERTS[@]}"; do
        ${first} || echo ','
        first=false
        echo "  $(json_escape "${a}")"
    done
    echo ']'
}

# ---- Checks ----

check_pm2_available() {
    if ! command -v pm2 &>/dev/null; then
        alert "CRITICAL" "pm2 command not found"
        echo '{"status":"error","message":"pm2 command not found"}'
        exit 1
    fi
    if ! pm2 ping >/dev/null 2>&1; then
        alert "CRITICAL" "PM2 daemon is not reachable"
        echo '{"status":"error","message":"PM2 daemon not reachable"}'
        exit 1
    fi
}

check_env_key() {
    local proc_name="$1"
    local required_key="$2"

    # Check if the process has the key in its environment
    local env_data
    env_data="$(pm2 env "${proc_name}" 2>/dev/null || true)"
    if [[ -z "${env_data}" ]]; then
        return 1
    fi
    if echo "${env_data}" | grep -q "${required_key}"; then
        return 0
    fi
    return 1
}

check_process() {
    local process_json="$1"
    local name status restart_count memory cpu pm_id

    name="$(echo "${process_json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("name","unknown"))' 2>/dev/null)"
    status="$(echo "${process_json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("pm2_env",{}).get("status","unknown"))' 2>/dev/null)"
    restart_count="$(echo "${process_json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("pm2_env",{}).get("restart_time",0))' 2>/dev/null)"
    memory="$(echo "${process_json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("monit",{}).get("memory",0))' 2>/dev/null)"
    cpu="$(echo "${process_json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("monit",{}).get("cpu",0))' 2>/dev/null)"
    pm_id="$(echo "${process_json}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("pm_id","?"))' 2>/dev/null)"

    [[ -z "${name}" || "${name}" == "unknown" ]] && name="unknown"
    [[ -z "${status}" || "${status}" == "unknown" ]] && status="unknown"
    restart_count="${restart_count:-0}"
    memory="${memory:-0}"
    cpu="${cpu:-0}"

    local proc_ok=true
    local issues=()

    # Status check
    if [[ "${status}" != "online" ]]; then
        issues+=("status=${status}")
        proc_ok=false
    fi

    # Restart count check
    if [[ "${restart_count}" -gt "${RESTART_WARN_THRESHOLD}" ]]; then
        issues+=("restarts=${restart_count} (threshold=${RESTART_WARN_THRESHOLD})")
        proc_ok=false
    fi

    # Memory check
    if [[ "${memory}" -gt "${MEMORY_WARN_BYTES}" ]]; then
        local mem_mb=$(( memory / 1024 / 1024 ))
        issues+=("memory=${mem_mb}MB (threshold=$(( MEMORY_WARN_BYTES / 1024 / 1024 ))MB)")
        proc_ok=false
    fi

    # CPU check
    local cpu_int
    cpu_int="${cpu%.*}"
    if [[ -n "${cpu_int}" && "${cpu_int}" -gt 50 ]]; then
        issues+=("cpu=${cpu}% (threshold=${CPU_WARN_PERCENT}%)")
        proc_ok=false
    fi

    # Env var integrity check for AI agent processes
    local key_found=true
    for required_proc in "${DEEPSEEK_REQUIRED_PROCESSES[@]}"; do
        if [[ "${name}" == "${required_proc}" ]]; then
            if check_env_key "${name}" "DEEPSEEK_API_KEY"; then
                : # key found - ok
            else
                issues+=("missing-env:DEEPSEEK_API_KEY")
                proc_ok=false
                key_found=false
            fi
            break
        fi
    done

    # Alert generation
    if ! ${proc_ok}; then
        local issue_str
        issue_str="$(IFS='; '; echo "${issues[*]}")"

        if [[ "${status}" == "errored" ]]; then
            alert "CRITICAL" "PM2 ${name} (pm_id=${pm_id}): ${issue_str}"
        elif [[ "${status}" == "stopped" ]]; then
            alert "WARN" "PM2 ${name} (pm_id=${pm_id}): ${issue_str}"
        elif [[ "${restart_count}" -gt "${RESTART_WARN_THRESHOLD}" ]]; then
            alert "HIGH" "PM2 ${name} (pm_id=${pm_id}): ${issue_str}"
        elif [[ "${memory}" -gt "${MEMORY_WARN_BYTES}" ]]; then
            alert "WARN" "PM2 ${name}: memory ${issue_str}"
        elif [[ "${cpu_int}" -gt 50 ]]; then
            alert "WARN" "PM2 ${name}: cpu ${issue_str}"
        elif ! ${key_found}; then
            alert "HIGH" "PM2 ${name}: ${issue_str}"
        else
            alert "WARN" "PM2 ${name}: ${issue_str}"
        fi
    fi

    # Return result string
    local mem_mb=$(( memory / 1024 / 1024 ))
    local status_label
    if ${proc_ok}; then
        status_label="OK"
        ((PASS++))
    else
        status_label="ISSUE"
        ((FAIL++))
    fi
    echo "${status_label}|${name}|${pm_id}|${status}|${restart_count}|${mem_mb}MB|${cpu}%"
}

# ---- Main ----
main() {
    local mode="standard"
    for arg in "$@"; do
        case "${arg}" in
            --help|-h) show_help ;;
            --json) mode="json" ;;
            --alerts-only) mode="alerts" ;;
        esac
    done

    check_pm2_available

    local jlist
    jlist="$(pm2 jlist 2>/dev/null)" || {
        alert "CRITICAL" "Failed to get PM2 process list"
        exit 1
    }

    local process_count
    process_count="$(echo "${jlist}" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"

    if [[ "${process_count}" -eq 0 ]]; then
        alert "WARN" "No PM2 processes found"
        if [[ "${mode}" == "json" ]]; then
            echo '{"status":"warn","message":"No processes found","timestamp":"'"${TIMESTAMP}"'","alerts":[]}'
        fi
        exit 0
    fi

    local results=()
    for i in $(seq 0 $(( process_count - 1 ))); do
        local proc_json
        proc_json="$(echo "${jlist}" | python3 -c "
import json,sys
data = json.load(sys.stdin)
print(json.dumps(data[${i}]))
" 2>/dev/null)"
        [[ -z "${proc_json}" ]] && continue
        result="$(check_process "${proc_json}")"
        results+=("${result}")
    done

    local total=$((PASS + FAIL))
    local score=100
    if [[ "${total}" -gt 0 ]]; then
        score=$(( (PASS * 100) / total ))
    fi

    # === OUTPUT ===
    case "${mode}" in
        json)
            echo '{'
            echo '  "script": "pm2-watchdog",'
            echo '  "timestamp": "'"${TIMESTAMP}"'",'
            echo '  "summary": {'
            echo '    "total": '"${total}"','
            echo '    "pass": '"${PASS}"','
            echo '    "fail": '"${FAIL}"','
            echo '    "warn": '"${WARN}"','
            echo '    "score": '"${score}"''
            echo '  },'
            echo '  "processes": ['
            local first=true
            for r in "${results[@]}"; do
                ${first} || echo ','
                first=false
                IFS='|' read -r status name pm_id proc_state restarts memory cpu_val <<< "${r}"
                echo '  {"name":"'"${name}"'","pm_id":"'"${pm_id}"'","status":"'"${status}"'","state":"'"${proc_state}"'","restarts":'"${restarts}"',"memory":"'"${memory}"'","cpu":"'"${cpu_val}"'"}'
            done
            echo '  ],'
            echo '  "alerts":'
            emit_alerts_json
            echo '}'
            ;;
        alerts)
            if [[ ${#ALERTS[@]} -gt 0 ]]; then
                for a in "${ALERTS[@]}"; do
                    echo "${a}"
                done
            fi
            ;;
        standard)
            echo "========================================"
            echo " PM2 Health Watchdog Report"
            echo " Timestamp: ${TIMESTAMP}"
            echo "========================================"
            echo ""
            echo "Summary: ${PASS}/${total} healthy (score: ${score}/100)"
            echo ""

            if [[ ${#ALERTS[@]} -gt 0 ]]; then
                echo "Alerts:"
                for a in "${ALERTS[@]}"; do
                    echo "  ${a}"
                done
                echo ""
            fi

            printf "%-42s %-5s %-10s %-9s %-9s %-8s\n" "PROCESS" "ID" "STATE" "RESTARTS" "MEMORY" "CPU"
            printf "%-42s %-5s %-10s %-9s %-9s %-8s\n" "------------------------------------------" "-----" "----------" "---------" "---------" "--------"
            for r in "${results[@]}"; do
                IFS='|' read -r status name pm_id proc_state restarts memory cpu_val <<< "${r}"
                printf "%-42s %-5s %-10s %-9s %-9s %-8s\n" "${name}" "${pm_id}" "${proc_state}" "${restarts}" "${memory}" "${cpu_val}"
            done

            if [[ "${score}" -lt 100 ]]; then
                echo ""
                echo "ISSUES DETECTED - Review alerts above"
                echo "Run --json for machine-parsable output."
            fi
            echo ""
            echo "Result: $([ "${score}" -eq 100 ] && echo 'PASS' || echo 'ISSUES FOUND')"
            ;;
    esac

    [[ "${FAIL}" -eq 0 && "${WARN}" -eq 0 ]]
}

main "$@"
