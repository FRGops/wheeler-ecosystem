#!/usr/bin/env bash
#===============================================================================
# resource-watchdog.sh
# Wheeler Autonomous AI Ops Platform - System Resource Monitor
#
# Monitors system resources:
#   - Disk usage (warn >80%, critical >90%)
#   - RAM usage (warn >85%)
#   - CPU load average (warn >80% of cores)
#   - Swap usage
#   - Docker disk usage
#
# Usage:
#   ./resource-watchdog.sh                  # Standard output (alerts + summary)
#   ./resource-watchdog.sh --json           # JSON resource report only
#   ./resource-watchdog.sh --alerts-only    # Alerts only, no summary
#   ./resource-watchdog.sh --help           # This help text
#
# Output: JSON resource report + alerts to stdout
# Severity levels: INFO, WARN, HIGH, CRITICAL
#===============================================================================
set -euo pipefail

# ---- Constants ----
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ALERTS=()
WARN=0
CRIT=0

# ---- Thresholds ----
DISK_WARN_PCT=80
DISK_CRIT_PCT=90
RAM_WARN_PCT=85
CPU_WARN_PCT=80

# ---- Help ----
show_help() {
    sed -ne '/^#===-/,/^#===/p' "$0" | head -n -1 | sed 's/^#//'
    exit 0
}

# ---- Output helpers ----
alert() {
    local severity="$1"
    local message="$2"
    local entry="[${severity}] [${TIMESTAMP}] [resource-watchdog] ${message}"
    ALERTS+=("${entry}")
    echo "${entry}" >&2
    case "${severity}" in
        WARN) ((WARN++)) ;;
        HIGH|CRITICAL) ((CRIT++)) ;;
    esac
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

check_disk() {
    local results=()
    local has_issues=false

    while IFS= read -r line; do
        local filesystem size used avail use_pct mount
        filesystem="$(echo "${line}" | awk '{print $1}')"
        size="$(echo "${line}" | awk '{print $2}')"
        used="$(echo "${line}" | awk '{print $3}')"
        avail="$(echo "${line}" | awk '{print $4}')"
        use_pct="$(echo "${line}" | awk '{print $5}' | tr -d '%')"
        mount="$(echo "${line}" | awk '{print $6}')"

        # Skip tmpfs, devtmpfs, overlay, squashfs
        case "${mount}" in
            /dev|/sys*|/proc*|/run*|/etc/*) continue ;;
        esac
        case "${filesystem}" in
            tmpfs|devtmpfs|overlay|squashfs|shm) continue ;;
        esac

        local severity=""
        local message=""

        if [[ "${use_pct}" -ge "${DISK_CRIT_PCT}" ]]; then
            severity="CRITICAL"
            message="Disk ${mount} at ${use_pct}% usage (critical threshold: ${DISK_CRIT_PCT}%)"
            has_issues=true
        elif [[ "${use_pct}" -ge "${DISK_WARN_PCT}" ]]; then
            severity="WARN"
            message="Disk ${mount} at ${use_pct}% usage (warn threshold: ${DISK_WARN_PCT}%)"
            has_issues=true
        fi

        if [[ -n "${severity}" ]]; then
            alert "${severity}" "${message}"
        fi

        results+=("${filesystem}|${size}|${used}|${avail}|${use_pct}|${mount}")
    done < <(df -h 2>/dev/null | tail -n +2)

    echo "${results[@]}"
}

check_ram() {
    local mem_info
    mem_info="$(free 2>/dev/null)" || {
        alert "WARN" "Cannot read memory info"
        return
    }

    local total_kb used_kb
    total_kb="$(echo "${mem_info}" | awk '/^Mem:/{print $2}')"
    used_kb="$(echo "${mem_info}" | awk '/^Mem:/{print $3}')"
    local use_pct=0
    if [[ -n "${total_kb}" && "${total_kb}" -gt 0 ]]; then
        use_pct=$(( used_kb * 100 / total_kb ))
    fi

    if [[ "${use_pct}" -ge "${RAM_WARN_PCT}" ]]; then
        alert "HIGH" "RAM at ${use_pct}% usage (threshold: ${RAM_WARN_PCT}%)"
    fi

    # Check swap
    local swap_total swap_used swap_pct=0
    swap_total="$(echo "${mem_info}" | awk '/^Swap:/{print $2}')"
    swap_used="$(echo "${mem_info}" | awk '/^Swap:/{print $3}')"
    if [[ -n "${swap_total}" && "${swap_total}" -gt 0 ]]; then
        swap_pct=$(( swap_used * 100 / swap_total ))
        if [[ "${swap_pct}" -gt 10 ]]; then
            alert "WARN" "Swap at ${swap_pct}% usage (${swap_used}kB/${swap_total}kB)"
        fi
    fi
}

check_cpu() {
    local cpu_count
    cpu_count="$(nproc 2>/dev/null || echo 1)"

    local load_1 load_5 load_15
    read -r load_1 load_5 load_15 _ < /proc/loadavg 2>/dev/null || {
        alert "WARN" "Cannot read CPU load"
        return
    }

    # Compare 5-min load to core count
    local load_int="${load_5%.*}"
    local threshold=$(( cpu_count * CPU_WARN_PCT / 100 ))
    if [[ "${load_int}" -ge "${threshold}" ]]; then
        alert "WARN" "CPU load average ${load_5} (${load_1}/${load_5}/${load_15}) exceeds ${CPU_WARN_PCT}% of ${cpu_count} cores (threshold: ${threshold})"
    fi
}

check_docker_disk() {
    if ! docker info >/dev/null 2>&1; then
        alert "INFO" "Docker not available - skipping Docker disk check"
        return
    fi

    local df_output
    df_output="$(docker system df 2>/dev/null)" || return

    # Check for high usage
    local images_size containers_size volumes_size build_cache_size total_reclaimable
    images_size="$(echo "${df_output}" | awk '/^Images/{print $2" "$3}' || echo "0B")"
    containers_size="$(echo "${df_output}" | awk '/^Containers/{print $2" "$3}' || echo "0B")"
    volumes_size="$(echo "${df_output}" | awk '/^Volumes/{print $2" "$3}' || echo "0B")"
    build_cache_size="$(echo "${df_output}" | awk '/^Build Cache/{print $2" "$3}' || echo "0B")"

    # Check for reclaimable space
    total_reclaimable="$(echo "${df_output}" | grep -i "reclaimable" | head -1 || echo "")"
    if echo "${total_reclaimable}" | grep -qiE "[0-9]+(\.[0-9]+)?GB"; then
        alert "WARN" "Docker reclaimable space detected: ${total_reclaimable}"
    fi
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

    # Run all checks
    check_cpu
    check_ram
    check_disk >/dev/null 2>&1
    check_docker_disk

    # Gather data for output
    local cpu_count
    cpu_count="$(nproc 2>/dev/null || echo 1)"
    local mem_info
    mem_info="$(free -h 2>/dev/null || echo "")"
    local mem_total mem_used mem_pct
    mem_total="$(echo "${mem_info}" | awk '/^Mem:/{print $2}')"
    mem_used="$(echo "${mem_info}" | awk '/^Mem:/{print $3}')"
    local mem_kb_total mem_kb_used
    mem_kb_total="$(free 2>/dev/null | awk '/^Mem:/{print $2}')"
    mem_kb_used="$(free 2>/dev/null | awk '/^Mem:/{print $3}')"
    mem_pct=0
    [[ -n "${mem_kb_total}" && "${mem_kb_total}" -gt 0 ]] && mem_pct=$(( mem_kb_used * 100 / mem_kb_total ))

    local load_1 load_5 load_15
    read -r load_1 load_5 load_15 _ < /proc/loadavg 2>/dev/null || load_1=load_5=load_15="?"

    local disk_data="{}"
    disk_data="$(df -h 2>/dev/null | tail -n +2 | awk '{print "{\"filesystem\":\""$1"\",\"size\":\""$2"\",\"used\":\""$3"\",\"avail\":\""$4"\",\"use_pct\":"$5"\",\"mount\":\""$6"\"}"}' | python3 -c '
import json,sys
lines = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))
' 2>/dev/null || echo '[]')"

    local docker_df=""
    docker_df="$(docker system df 2>/dev/null | head -10 || echo "")"
    local docker_df_json="{}"
    if [[ -n "${docker_df}" ]]; then
        docker_df_json="$(echo "${docker_df}" | python3 -c '
import json,sys
lines = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(lines))
' 2>/dev/null || echo '{}')"
    fi

    case "${mode}" in
        json)
            echo '{'
            echo '  "script": "resource-watchdog",'
            echo '  "timestamp": "'"${TIMESTAMP}"'",'
            echo '  "cpu": {'
            echo '    "cores": '"${cpu_count}"','
            echo '    "load_1m": "'"${load_1}"'",'
            echo '    "load_5m": "'"${load_5}"'",'
            echo '    "load_15m": "'"${load_15}"'"'
            echo '  },'
            echo '  "memory": {'
            echo '    "total": "'"${mem_total}"'",'
            echo '    "used": "'"${mem_used}"'",'
            echo '    "usage_pct": '"${mem_pct}"''
            echo '  },'
            echo '  "disk": '"${disk_data}"','
            echo '  "docker_df": '"${docker_df_json}"','
            echo '  "alerts_count": '"${#ALERTS[@]}"','
            echo '  "alerts":'
            emit_alerts_json
            echo '}'
            ;;
        alerts)
            if [[ ${#ALERTS[@]} -gt 0 ]]; then
                for a in "${ALERTS[@]}"; do
                    echo "${a}"
                done
            else
                echo "No resource alerts"
            fi
            ;;
        standard)
            echo "========================================"
            echo " System Resource Watchdog Report"
            echo " Timestamp: ${TIMESTAMP}"
            echo "========================================"
            echo ""
            echo "CPU:  ${cpu_count} cores  load: ${load_1} / ${load_5} / ${load_15}"
            echo "RAM:  ${mem_used} used / ${mem_total} total (${mem_pct}%)"
            echo ""
            if [[ "${mem_pct}" -ge "${RAM_WARN_PCT}" ]]; then
                echo "  >>> RAM usage exceeds ${RAM_WARN_PCT}% threshold <<<"
            fi
            echo ""
            echo "Disk:"
            df -h 2>/dev/null | head -1
            df -h 2>/dev/null | tail -n +2 | while IFS= read -r line; do
                local use_pct mount
                use_pct="$(echo "${line}" | awk '{print $5}' | tr -d '%')"
                mount="$(echo "${line}" | awk '{print $6}')"
                case "${mount}" in
                    /dev|/sys*|/proc*|/run*) continue ;;
                esac
                case "$(echo "${line}" | awk '{print $1}')" in
                    tmpfs|devtmpfs|overlay|squashfs|shm) continue ;;
                esac
                local tag=""
                if [[ -n "${use_pct}" && "${use_pct}" -ge "${DISK_CRIT_PCT}" ]]; then
                    tag="  *** CRITICAL ***"
                elif [[ -n "${use_pct}" && "${use_pct}" -ge "${DISK_WARN_PCT}" ]]; then
                    tag="  ** WARN **"
                fi
                echo "${line}${tag}"
            done
            echo ""
            echo "Docker Disk:"
            if command -v docker &>/dev/null && docker info >/dev/null 2>&1; then
                docker system df 2>/dev/null || echo "  (unavailable)"
            else
                echo "  (Docker not available)"
            fi
            echo ""
            if [[ ${#ALERTS[@]} -gt 0 ]]; then
                echo "Alerts:"
                for a in "${ALERTS[@]}"; do
                    echo "  ${a}"
                done
            fi
            echo ""
            echo "Result: $([ "${#ALERTS[@]}" -eq 0 ] && echo 'PASS' || echo 'ISSUES FOUND')"
            ;;
    esac

    [[ "${#ALERTS[@]}" -eq 0 ]]
}

main "$@"
