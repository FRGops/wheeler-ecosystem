#!/usr/bin/env bash
#===============================================================================
# docker-watchdog.sh
# Wheeler Autonomous AI Ops Platform - Docker Container Health Monitor
#
# Monitors all Docker containers for:
#   - Container status (running, healthy, exited, dead)
#   - Bind address drift (flags 0.0.0.0 binds except SSH:22)
#   - Restart loop detection (>3 restarts in 10 minutes)
#   - :latest image tag usage
#
# Usage:
#   ./docker-watchdog.sh                  # Standard output (alerts + summary)
#   ./docker-watchdog.sh --json           # JSON health report only
#   ./docker-watchdog.sh --alerts-only    # Alerts only, no summary
#   ./docker-watchdog.sh --help           # This help text
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

# ---- Config ----
RESTART_THRESHOLD=3              # Max acceptable restarts in window
RESTART_WINDOW_MINUTES=10        # Lookback window for restart detection
MEMORY_WARN_MB=500               # Memory warning threshold per container

# ---- Help ----
show_help() {
    sed -ne '/^#===-/,/^#===/p' "$0" | head -n -1 | sed 's/^#//'
    exit 0
}

# ---- Output helpers ----
alert() {
    local severity="$1"
    local message="$2"
    local entry="[${severity}] [${TIMESTAMP}] [docker-watchdog] ${message}"
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

check_docker_available() {
    if ! docker info >/dev/null 2>&1; then
        alert "CRITICAL" "Docker daemon is not accessible"
        echo '{"status":"error","message":"Docker daemon not accessible"}'
        exit 1
    fi
}

check_container_health() {
    local container="$1"
    local status_line
    status_line="$(docker inspect --format '{{.State.Status}}|{{.State.Health.Status}}|{{.Name}}|{{range $p := .NetworkSettings.Ports}}{{if $p}}{{$p.HostIp}}:{{$p.HostPort}} {{end}}{{end}}|{{range $m := .Mounts}}{{$m.Source}}:{{$m.Destination}} {{end}}|{{.Config.Image}}' "${container}" 2>/dev/null)" || {
        alert "HIGH" "Container ${container}: cannot inspect"
        ((FAIL++))
        return 1
    }

    local state health name ports mounts image
    IFS='|' read -r state health name ports mounts image <<< "${status_line}"
    name="${name#/}"

    # Determine overall health
    local container_ok=true
    local container_alerts=()

    if [[ "${state}" != "running" ]]; then
        container_alerts+=("state=${state}")
        container_ok=false
    fi

    if [[ -n "${health}" && "${health}" != "<nil>" && "${health}" != "healthy" ]]; then
        container_alerts+=("health=${health}")
        container_ok=false
    fi

    # Check restart count
    local restart_count
    restart_count="$(docker inspect --format '{{.RestartCount}}' "${container}" 2>/dev/null || echo 0)"
    if [[ -n "${restart_count}" && "${restart_count}" -gt "${RESTART_THRESHOLD}" ]]; then
        local finished_at
        finished_at="$(docker inspect --format '{{.State.FinishedAt}}' "${container}" 2>/dev/null || echo "")"
        container_alerts+=("restarts=${restart_count} (threshold=${RESTART_THRESHOLD})")
        container_ok=false
    fi

    # Check bind addresses - flag non-127.0.0.1 except SSH:22
    local flagged_binds=""
    if [[ -n "${ports}" && "${ports}" != "''" ]]; then
        # Parse each port binding
        while IFS=' ' read -ra bindings; do
            for bind in "${bindings[@]}"; do
                local addr port
                addr="${bind%%:*}"
                port="${bind##*:}"
                if [[ "${addr}" != "127.0.0.1" && "${addr}" != "" ]]; then
                    # Allow only SSH:22 on 0.0.0.0
                    if [[ "${addr}" == "0.0.0.0" && "${port}" == "22" ]]; then
                        continue
                    fi
                    # Allow Tailscale IPs
                    if [[ "${addr}" == "100."* && "${addr}" == *".230.28" ]]; then
                        continue
                    fi
                    flagged_binds+=" ${bind}"
                fi
            done
        done <<< "${ports}"
    fi

    if [[ -n "${flagged_binds}" ]]; then
        container_alerts+=("non-loopback-bind:${flagged_binds}")
        container_ok=false
    fi

    # Check for :latest image tag
    local image_warn=""
    if [[ "${image}" == *":latest" ]]; then
        image_warn="latest-tag:${image}"
        container_ok=false
    fi

    # Check restart loop (if container restarted recently)
    if [[ -n "${restart_count}" && "${restart_count}" -gt 0 ]]; then
        local last_start
        last_start="$(docker inspect --format '{{.State.StartedAt}}' "${container}" 2>/dev/null || echo "")"
        if [[ -n "${last_start}" ]]; then
            local last_start_epoch now_epoch diff_minutes
            last_start_epoch="$(date -d "${last_start}" +%s 2>/dev/null || echo 0)"
            now_epoch="$(date +%s)"
            if [[ "${last_start_epoch}" -gt 0 ]]; then
                diff_minutes="$(( (now_epoch - last_start_epoch) / 60 ))"
                if [[ "${diff_minutes}" -lt "${RESTART_WINDOW_MINUTES}" && "${restart_count}" -gt "${RESTART_THRESHOLD}" ]]; then
                    container_alerts+=("restart-loop:${restart_count} restarts in ${diff_minutes}m")
                fi
            fi
        fi
    fi

    # Output result
    if ${container_ok}; then
        ((PASS++))
        echo "OK|${name}|${state}|${health:-healthy}|${ports}|${image}"
    else
        ((FAIL++))
        local alert_msg="Container ${name}: $(IFS='; '; echo "${container_alerts[*]}")"
        if [[ -n "${image_warn}" ]]; then
            alert "WARN" "Container ${name}: ${image_warn}"
        fi
        if echo "${container_alerts[*]}" | grep -q "restart-loop"; then
            alert "CRITICAL" "${alert_msg}"
        elif echo "${container_alerts[*]}" | grep -q "non-loopback-bind"; then
            alert "HIGH" "${alert_msg}"
        elif [[ "${state}" != "running" ]]; then
            alert "HIGH" "${alert_msg}"
        elif [[ -n "${health}" && "${health}" != "<nil>" && "${health}" != "healthy" ]]; then
            alert "HIGH" "${alert_msg}"
        else
            alert "WARN" "${alert_msg}"
        fi
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

    check_docker_available

    local containers
    containers="$(docker ps -a --format '{{.Names}}' 2>/dev/null | sort)"

    if [[ -z "${containers}" ]]; then
        alert "WARN" "No Docker containers found"
        if [[ "${mode}" == "json" ]]; then
            echo '{"status":"warn","message":"No containers found","timestamp":"'"${TIMESTAMP}"'","alerts":[]}'
        fi
        exit 0
    fi

    local results=()
    while IFS= read -r cname; do
        [[ -z "${cname}" ]] && continue
        result="$(check_container_health "${cname}")"
        results+=("${result}")
    done <<< "${containers}"

    local total=$((PASS + FAIL))
    local score=100
    if [[ "${total}" -gt 0 ]]; then
        score=$(( (PASS * 100) / total ))
    fi

    # === OUTPUT ===
    case "${mode}" in
        json)
            echo '{'
            echo '  "script": "docker-watchdog",'
            echo '  "timestamp": "'"${TIMESTAMP}"'",'
            echo '  "summary": {'
            echo '    "total": '"${total}"','
            echo '    "pass": '"${PASS}"','
            echo '    "fail": '"${FAIL}"','
            echo '    "warn": '"${WARN}"','
            echo '    "score": '"${score}"''
            echo '  },'
            echo '  "containers": ['
            local first=true
            for r in "${results[@]}"; do
                ${first} || echo ','
                first=false
                IFS='|' read -r status name state health ports image <<< "${r}"
                if [[ "${status}" == "OK" ]]; then
                    echo '  {"name":"'"${name}"'","status":"OK","state":"'"${state}"'","health":"'"${health}"'","ports":"'"${ports}"'","image":"'"${image}"'"}'
                fi
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
            echo " Docker Health Watchdog Report"
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

            # Print simple table
            printf "%-35s %-10s %-10s %-30s\n" "CONTAINER" "STATE" "HEALTH" "IMAGE"
            printf "%-35s %-10s %-10s %-30s\n" "-----------------------------------" "----------" "----------" "------------------------------"
            for r in "${results[@]}"; do
                IFS='|' read -r status name state health ports image <<< "${r}"
                if [[ "${status}" == "OK" ]]; then
                    printf "%-35s %-10s %-10s %-30s\n" "${name}" "${state}" "${health}" "${image}"
                fi
            done

            if [[ "${score}" -lt 100 ]]; then
                echo ""
                echo "UNHEALTHY CONTAINERS DETECTED"
                echo "Run --json for machine-parsable output."
                echo "Run port-watchdog.sh for network drift analysis."
            fi
            echo ""
            echo "Result: $([ "${score}" -eq 100 ] && echo 'PASS' || echo 'ISSUES FOUND')"
            ;;
    esac

    # Exit code: 0 if healthy, 1 if issues
    [[ "${FAIL}" -eq 0 && "${WARN}" -eq 0 ]]
}

main "$@"
