#!/usr/bin/env bash
#===============================================================================
# exposure-watchdog.sh
# Wheeler Autonomous AI Ops Platform - Exposure Drift Scanner
#
# Scans for security exposure drift:
#   - UFW rule count vs baseline
#   - Public-facing port detection
#   - Nginx config for unexpected upstreams
#   - Admin panels accessible without auth
#
# Usage:
#   ./exposure-watchdog.sh                  # Standard output
#   ./exposure-watchdog.sh --json           # JSON report
#   ./exposure-watchdog.sh --alerts-only    # Alerts only
#   ./exposure-watchdog.sh --help           # This help text
#
# Output: Exposure report + alerts to stdout
# Severity levels: INFO, WARN, HIGH, CRITICAL
#===============================================================================
set -euo pipefail

# ---- Constants ----
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ALERTS=()
WARN=0
CRIT=0

# ---- Expected UFW rule count ----
# Known-good UFW rule count after Stage 2 cleanup (2026-05-24):
# Reduced from 95 to 64 rules
UFW_BASELINE_RULES=64
UFW_RULE_TOLERANCE=5  # Allow some variance for dynamic rules

# ---- Admin panels that should NOT be internet-exposed ----
ADMIN_PATHS=(
    "/admin"
    "/admin/"
    "/admin/login"
    "/login"
    "/dashboard"
    "/panel"
    "/grafana"
    "/prometheus"
    "/alertmanager"
    "/pgadmin"
    "/phpmyadmin"
    "/rabbitmq"
    "/redis-admin"
    "/superset"
    "/flower"
    "/api"
    "/swagger"
    "/docs"
    "/redoc"
)

# ---- Known allowed upstreams (nginx) ----
ALLOWED_UPSTREAMS=(
    "127.0.0.1:3000"
    "127.0.0.1:3001"
    "127.0.0.1:3002"
    "127.0.0.1:3010"
    "127.0.0.1:3100"
    "127.0.0.1:3130"
    "127.0.0.1:5000"
    "127.0.0.1:5433"
    "127.0.0.1:5434"
    "127.0.0.1:7233"
    "127.0.0.1:7474"
    "127.0.0.1:7687"
    "127.0.0.1:7860"
    "127.0.0.1:8003"
    "127.0.0.1:8007"
    "127.0.0.1:8085"
    "127.0.0.1:8088"
    "127.0.0.1:8089"
    "127.0.0.1:8095"
    "127.0.0.1:8098"
    "127.0.0.1:8100"
    "127.0.0.1:8123"
    "127.0.0.1:9090"
    "127.0.0.1:9091"
    "127.0.0.1:9092"
    "127.0.0.1:9093"
    "127.0.0.1:4200"
    "127.0.0.1:5050"
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
    local entry="[${severity}] [${TIMESTAMP}] [exposure-watchdog] ${message}"
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

check_ufw_rules() {
    if ! command -v ufw &>/dev/null; then
        alert "INFO" "UFW not installed - skipping firewall check"
        return
    fi

    local rule_count
    rule_count="$(ufw status numbered 2>/dev/null | grep -c '^\[' || true)"

    if [[ "${rule_count}" -eq 0 ]]; then
        alert "HIGH" "UFW appears to have 0 rules - firewall may be inactive"
        return
    fi

    local lower_bound=$(( UFW_BASELINE_RULES - UFW_RULE_TOLERANCE ))
    local upper_bound=$(( UFW_BASELINE_RULES + UFW_RULE_TOLERANCE ))

    if [[ "${rule_count}" -lt "${lower_bound}" || "${rule_count}" -gt "${upper_bound}" ]]; then
        alert "WARN" "UFW rule count changed: ${rule_count} (baseline: ${UFW_BASELINE_RULES}, tolerance: +/-${UFW_RULE_TOLERANCE})"
    else
        echo "PASS: UFW rules at ${rule_count} (baseline: ${UFW_BASELINE_RULES})"
    fi
}

check_nginx_upstreams() {
    local config_dirs=(
        "/etc/nginx/conf.d"
        "/etc/nginx/sites-enabled"
        "/etc/nginx/sites-available"
    )

    local found_upstreams=()
    local found_unexpected=false

    for dir in "${config_dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            continue
        fi
        while IFS= read -r file; do
            [[ -z "${file}" ]] && continue
            # Extract proxy_pass targets
            while IFS= read -r line; do
                local upstream
                upstream="$(echo "${line}" | grep -oP 'proxy_pass\s+\Khttps?://[^;]+' || true)"
                if [[ -n "${upstream}" ]]; then
                    # Strip protocol and path
                    upstream="$(echo "${upstream}" | sed 's|https\?://||' | sed 's|/.*$||')"
                    found_upstreams+=("${upstream}")

                    # Check if it's in allowed list
                    local allowed=false
                    for a in "${ALLOWED_UPSTREAMS[@]}"; do
                        if [[ "${upstream}" == "${a}" || "${upstream}" == *"${a}"* ]]; then
                            allowed=true
                            break
                        fi
                    done
                    if ! ${allowed}; then
                        alert "HIGH" "Unexpected nginx upstream: ${upstream} (in ${file})"
                        found_unexpected=true
                    fi
                fi
            done < <(cat "${file}" 2>/dev/null || true)
        done < <(find "${dir}" -type f -name "*.conf" 2>/dev/null || true)
    done

    if ! ${found_unexpected}; then
        if [[ ${#found_upstreams[@]} -gt 0 ]]; then
            echo "PASS: All nginx upstreams are known (${#found_upstreams[@]} total)"
        else
            echo "INFO: No nginx proxy_pass upstreams found (or nginx not configured)"
        fi
    fi
}

check_admin_access() {
    # Check for admin panels accessible via localhost without auth
    local endpoints=(
        "http://127.0.0.1:3001"   # Uptime Kuma
        "http://127.0.0.1:3002"   # Grafana
        "http://127.0.0.1:8088"   # Superset
        "http://127.0.0.1:8089"   # Temporal UI
        "http://127.0.0.1:8095"   # Ecosystem Guardian
        "http://127.0.0.1:8100"   # War Room
        "http://127.0.0.1:8003"   # Command Center
        "http://127.0.0.1:9090"   # Prometheus
        "http://127.0.0.1:9093"   # Alertmanager
    )

    local accessible=()
    for ep in "${endpoints[@]}"; do
        local http_code
        http_code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 "${ep}" 2>/dev/null || true)"
        if [[ -n "${http_code}" && "${http_code}" != "000" ]]; then
            # Check if it's an auth page or open
            local body
            body="$(curl -s --connect-timeout 2 --max-time 3 "${ep}" 2>/dev/null || true)"
            # If the response is not a login/auth page and not a 401/403, flag it
            if [[ "${http_code}" != "401" && "${http_code}" != "403" && "${http_code}" != "302" ]]; then
                local has_login
                has_login="$(echo "${body}" | grep -ci "login\|signin\|password\|auth" 2>/dev/null || true)"
                if [[ "${has_login}" -lt 2 ]]; then
                    accessible+=("${ep} (HTTP ${http_code})")
                fi
            fi
        fi
    done

    if [[ ${#accessible[@]} -gt 0 ]]; then
        for a_item in "${accessible[@]}"; do
            alert "WARN" "Potentially accessible admin panel: ${a_item}"
        done
    else
        echo "PASS: All admin panels appear to require authentication"
    fi
}

check_public_ports() {
    # Check if any known admin ports are accessible on 0.0.0.0
    local admin_ports=("3001" "3002" "8088" "8089" "8095" "8100" "8003" "9090" "9093" "7860")

    local current_listeners
    current_listeners="$(ss -tlnp 2>/dev/null)" || return

    for port in "${admin_ports[@]}"; do
        if echo "${current_listeners}" | grep -q "0.0.0.0:${port} "; then
            alert "CRITICAL" "Admin port ${port} bound to 0.0.0.0 - potential public exposure"
        elif echo "${current_listeners}" | grep -q "\*:${port} "; then
            alert "HIGH" "Admin port ${port} bound to *:* - potential public exposure"
        fi
    done
}

check_docker_exposure() {
    # Check containers bound to 0.0.0.0
    if ! docker info >/dev/null 2>&1; then
        return
    fi

    local containers_with_exposure=()
    while IFS= read -r line; do
        local name ports
        name="$(echo "${line}" | awk '{print $1}')"
        ports="$(echo "${line}" | awk '{$1=""; print $0}')"
        if echo "${ports}" | grep -qP '(?<!127\.)0\.0\.0\.0'; then
            containers_with_exposure+=("${name}: ${ports}")
        fi
    done < <(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null || true)

    if [[ ${#containers_with_exposure[@]} -gt 0 ]]; then
        for c in "${containers_with_exposure[@]}"; do
            # Check if it's just SSH on 22
            if echo "${c}" | grep -qv ":22->"; then
                alert "HIGH" "Container with 0.0.0.0 bind: ${c}"
            fi
        done
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
    echo "Running checks..."
    check_ufw_rules
    check_nginx_upstreams
    check_admin_access
    check_public_ports
    check_docker_exposure

    case "${mode}" in
        json)
            echo '{'
            echo '  "script": "exposure-watchdog",'
            echo '  "timestamp": "'"${TIMESTAMP}"'",'
            echo '  "summary": {'
            echo '    "alerts": '"${#ALERTS[@]}"','
            echo '    "warnings": '"${WARN}"','
            echo '    "critical": '"${CRIT}"''
            echo '  },'
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
            echo ""
            echo "========================================"
            echo " Exposure Watchdog Report"
            echo " Timestamp: ${TIMESTAMP}"
            echo "========================================"
            echo ""
            if [[ ${#ALERTS[@]} -gt 0 ]]; then
                echo "Alerts (${#ALERTS[@]}):"
                for a in "${ALERTS[@]}"; do
                    echo "  ${a}"
                done
            else
                echo "No exposure issues detected."
            fi
            echo ""
            echo "Result: $([ ${#ALERTS[@]} -eq 0 ] && echo 'PASS (Clean)' || echo 'ISSUES FOUND')"
            ;;
    esac

    [[ ${#ALERTS[@]} -eq 0 ]]
}

main "$@"
