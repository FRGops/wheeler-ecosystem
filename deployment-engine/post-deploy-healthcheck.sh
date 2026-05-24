#!/usr/bin/env bash
# =============================================================================
# Wheeler Deployment Engine — post-deploy-healthcheck.sh
# =============================================================================
# Post-deployment health monitoring for a configurable monitoring window.
# Waits for service readiness, checks HTTP health, monitors logs for errors,
# validates resource usage, and checks all dependency connections.
#
# Usage:
#   ./post-deploy-healthcheck.sh <service-name> <environment>
#   ./post-deploy-healthcheck.sh --json wheeler-api production
#   ./post-deploy-healthcheck.sh --timeout 120 wheeler-api production
#
# Exit Codes:
#   0 - Service is healthy
#   1 - Service is unhealthy
#   2 - Service health is degraded (warnings present)
#   3 - Invalid arguments
# =============================================================================

set -euo pipefail

# ─── Source common utilities ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# ─── Script Configuration ────────────────────────────────────────────────────
readonly SCRIPT_NAME="post-deploy-healthcheck.sh"
readonly SCRIPT_VERSION="1.0.0"

# ─── Parse flags ─────────────────────────────────────────────────────────────
OUTPUT_JSON=false
JSON_OUTPUT_FILE=""
HEALTH_TIMEOUT="${DEFAULT_HEALTH_TIMEOUT}"  # seconds
MONITOR_WINDOW=60    # seconds to monitor after readiness
STABILITY_CHECKS=3    # number of consecutive passes needed

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --output|-o)
            JSON_OUTPUT_FILE="$2"
            shift 2
            ;;
        --timeout|-t)
            HEALTH_TIMEOUT="$2"
            shift 2
            ;;
        --monitor-window)
            MONITOR_WINDOW="$2"
            shift 2
            ;;
        --stability-checks)
            STABILITY_CHECKS="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# ─── Arguments ───────────────────────────────────────────────────────────────
SERVICE_NAME="${1:-}"
ENVIRONMENT="${2:-}"

# ─── Results tracking ────────────────────────────────────────────────────────
declare -A HC_RESULTS
HC_PASS=0
HC_FAIL=0
HC_WARN=0

# ─── Usage ───────────────────────────────────────────────────────────────────
_healthcheck_usage() {
    cat <<EOF

${_C_BOLD}Usage:${_C_RESET} ./${SCRIPT_NAME} [OPTIONS] <service-name> <environment>

${_C_BOLD}Arguments:${_C_RESET}
  service-name   Name of the service to health-check
  environment    Target environment (production, staging, dev)

${_C_BOLD}Options:${_C_RESET}
  --json                  Output health status as JSON to stdout
  --output, -o FILE       Write JSON health report to FILE
  --timeout, -t SECONDS   Max wait time for service readiness (default: ${DEFAULT_HEALTH_TIMEOUT}s)
  --monitor-window SEC    Post-readiness monitoring duration (default: 60s)
  --stability-checks N    Number of consecutive health passes required (default: 3)

${_C_BOLD}Exit Codes:${_C_RESET}
  0  Service is healthy
  1  Service is unhealthy
  2  Service health is degraded (warnings)
  3  Invalid arguments

${_C_BOLD}Examples:${_C_RESET}
  ./post-deploy-healthcheck.sh wheeler-api production
  ./post-deploy-healthcheck.sh --json --timeout 120 revenue-api staging
  ./post-deploy-healthcheck.sh --monitor-window 120 --stability-checks 5 wheeler-api production
EOF
    exit 3
}

# ─── Record health result ────────────────────────────────────────────────────
hc_pass() { HC_RESULTS["$1"]="pass"; HC_RESULTS["${1}_detail"]="$2"; HC_PASS=$((HC_PASS + 1)); }
hc_fail() { HC_RESULTS["$1"]="fail"; HC_RESULTS["${1}_detail"]="$2"; HC_FAIL=$((HC_FAIL + 1)); }
hc_warn() { HC_RESULTS["$1"]="warn"; HC_RESULTS["${1}_detail"]="$2"; HC_WARN=$((HC_WARN + 1)); }
hc_skip() { HC_RESULTS["$1"]="skip"; HC_RESULTS["${1}_detail"]="$2"; }

# ─── Health Check 1: Service Readiness ───────────────────────────────────────
check_readiness() {
    local svc="$1"
    local timeout="$2"

    log_section "Service Readiness (timeout: ${timeout}s)"

    local port
    port=$(get_service_port "$svc")

    # 1a. Wait for port to be listening
    if [[ -n "$port" ]] && [[ "$port" != "null" ]] && [[ "$port" != "N/A" ]]; then
        log_info "Waiting for port ${port} to be listening..."
        local waited=0
        while [[ $waited -lt $timeout ]]; do
            if check_port_listening "$port"; then
                log_success "Port ${port} is listening"
                break
            fi
            sleep 2
            waited=$((waited + 2))
            if [[ $((waited % 10)) -eq 0 ]]; then
                log_debug "Still waiting for port ${port}... (${waited}s elapsed)"
            fi
        done

        if ! check_port_listening "$port"; then
            hc_fail "port_listening" "Port ${port} not listening after ${timeout}s"
            return 1
        fi
        hc_pass "port_listening" "Port ${port} bound and listening"
    else
        hc_skip "port_listening" "No port configured"
    fi

    # 1b. Wait for HTTP 200
    if [[ -n "$port" ]] && [[ "$port" != "null" ]] && [[ "$port" != "N/A" ]]; then
        local health_endpoint
        health_endpoint=$(get_health_endpoint "$svc")
        health_endpoint="${health_endpoint:-/health}"

        local health_url="http://127.0.0.1:${port}${health_endpoint}"

        if wait_for_health "$health_url" "$timeout" "$DEFAULT_HEALTH_INTERVAL"; then
            hc_pass "http_health" "HTTP 200 from ${health_url}"
        else
            hc_fail "http_health" "No HTTP 200 from ${health_url} after ${timeout}s"
            return 1
        fi
    else
        hc_skip "http_health" "No port configured"
    fi

    # 1c. Check PM2/Docker process status
    local runtime
    runtime=$(get_service_runtime "$svc")

    case "$runtime" in
        pm2)
            if command -v pm2 &>/dev/null && pm2 ping &>/dev/null 2>&1; then
                local status
                status=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${svc}\") | .pm2_env.status" 2>/dev/null || echo "unknown")
                if [[ "$status" == "online" ]]; then
                    hc_pass "process_status" "PM2 process online: ${svc}"
                else
                    hc_fail "process_status" "PM2 process status: ${status} for ${svc}"
                fi
            fi
            ;;
        docker)
            if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
                local container_id
                container_id=$(docker ps -q --filter "name=${svc}" 2>/dev/null || echo "")
                if [[ -n "$container_id" ]]; then
                    hc_pass "process_status" "Docker container running: ${container_id}"
                else
                    hc_fail "process_status" "Docker container not running: ${svc}"
                fi
            fi
            ;;
    esac

    return 0
}

# ─── Health Check 2: Log Monitoring ──────────────────────────────────────────
check_logs() {
    local svc="$1"
    local window_sec="$2"

    log_section "Log Monitoring (last ${window_sec}s)"

    local runtime
    runtime=$(get_service_runtime "$svc")
    local error_count=0
    local warn_count=0

    case "$runtime" in
        pm2)
            if command -v pm2 &>/dev/null; then
                local lines
                lines=$(pm2 logs "$svc" --lines 200 --nostream 2>/dev/null || echo "")
                error_count=$(echo "$lines" | grep -ciE '(error|fatal|critical)' 2>/dev/null || echo "0")
                warn_count=$(echo "$lines" | grep -ciE '(warn|warning)' 2>/dev/null || echo "0")
            fi
            ;;
        docker)
            if command -v docker &>/dev/null; then
                local container_id
                container_id=$(docker ps -q --filter "name=${svc}" 2>/dev/null || echo "")
                if [[ -n "$container_id" ]]; then
                    local lines
                    lines=$(docker logs --since "${window_sec}s" "$container_id" 2>&1 || echo "")
                    error_count=$(echo "$lines" | grep -ciE '(error|fatal|critical|exception|panic)' 2>/dev/null || echo "0")
                    warn_count=$(echo "$lines" | grep -ciE '(warn|warning)' 2>/dev/null || echo "0")
                fi
            fi
            ;;
    esac

    if [[ "$error_count" -eq 0 ]] && [[ "$warn_count" -eq 0 ]]; then
        hc_pass "logs" "No errors or warnings in recent logs"
    elif [[ "$error_count" -gt 10 ]]; then
        hc_fail "logs" "${error_count} errors in recent logs (threshold: 10)"
    elif [[ "$error_count" -gt 0 ]]; then
        hc_warn "logs" "${error_count} errors, ${warn_count} warnings in recent logs"
    else
        hc_pass "logs" "${warn_count} warnings only (no errors)"
    fi
}

# ─── Health Check 3: Resource Usage ──────────────────────────────────────────
check_resources() {
    local svc="$1"

    log_section "Resource Usage"

    local runtime
    runtime=$(get_service_runtime "$svc")

    local cpu="0"
    local mem="0"

    case "$runtime" in
        pm2)
            if command -v pm2 &>/dev/null && pm2 ping &>/dev/null 2>&1; then
                cpu=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${svc}\") | .monit.cpu // 0" 2>/dev/null || echo "0")
                mem=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${svc}\") | .monit.memory // 0" 2>/dev/null || echo "0")
            fi
            ;;
        docker)
            if command -v docker &>/dev/null; then
                local container_id
                container_id=$(docker ps -q --filter "name=${svc}" 2>/dev/null || echo "")
                if [[ -n "$container_id" ]]; then
                    local stats
                    stats=$(docker stats --no-stream --format '{{.CPUPerc}} {{.MemPerc}}' "$container_id" 2>/dev/null || echo "0% 0%")
                    cpu=$(echo "$stats" | awk '{print $1}' | tr -d '%')
                    mem=$(echo "$stats" | awk '{print $2}' | tr -d '%')
                fi
            fi
            ;;
    esac

    local cpu_int="${cpu%.*}"

    log_kv "CPU" "${cpu}%"
    log_kv "Memory" "${mem}%"

    if [[ "$cpu_int" -gt 95 ]] 2>/dev/null; then
        hc_fail "resources" "CPU critically high: ${cpu}%"
        send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "CRITICAL" \
            "Post-deploy CPU=${cpu}% — critically high"
    elif [[ "$cpu_int" -gt 80 ]] 2>/dev/null; then
        hc_warn "resources" "CPU elevated: ${cpu}%"
    else
        hc_pass "resources" "CPU=${cpu}%, Memory=${mem}%"
    fi
}

# ─── Health Check 4: Dependency Reachability ─────────────────────────────────
check_deps_reachable() {
    local svc="$1"

    log_section "Dependency Reachability"

    local deps_json
    deps_json=$(get_service_info "$svc" "dependencies" 2>/dev/null || echo "")

    if [[ -z "$deps_json" ]] || [[ "$deps_json" == "null" ]]; then
        hc_skip "deps_reachable" "No dependencies configured"
        return
    fi

    local all_ok=true

    # Check PostgreSQL
    if echo "$deps_json" | grep -qi "postgresql"; then
        if timeout 3 bash -c "echo >/dev/tcp/5.78.210.123/5432" 2>/dev/null; then
            hc_pass "dep_postgresql" "Reachable"
        else
            hc_fail "dep_postgresql" "UNREACHABLE"
            all_ok=false
        fi
    fi

    # Check Redis
    if echo "$deps_json" | grep -qi "redis"; then
        if timeout 3 bash -c "echo >/dev/tcp/5.78.210.123/6379" 2>/dev/null; then
            hc_pass "dep_redis" "Reachable"
        else
            hc_fail "dep_redis" "UNREACHABLE"
            all_ok=false
        fi
    fi

    # Check MinIO
    if echo "$deps_json" | grep -qi "minio"; then
        if timeout 3 bash -c "echo >/dev/tcp/5.78.210.123/9000" 2>/dev/null; then
            hc_pass "dep_minio" "Reachable"
        else
            hc_fail "dep_minio" "UNREACHABLE"
            all_ok=false
        fi
    fi

    $all_ok || return 1
}

# ─── Health Check 5: Stability Verification ──────────────────────────────────
check_stability() {
    local svc="$1"
    local checks_needed="$2"

    log_section "Stability Verification (${checks_needed} consecutive passes)"

    local port
    port=$(get_service_port "$svc")

    if [[ -z "$port" ]] || [[ "$port" == "null" ]] || [[ "$port" == "N/A" ]]; then
        hc_skip "stability" "No port configured — cannot verify stability via HTTP"
        return
    fi

    local health_endpoint
    health_endpoint=$(get_health_endpoint "$svc")
    health_endpoint="${health_endpoint:-/health}"

    local health_url="http://127.0.0.1:${port}${health_endpoint}"
    local consecutive=0

    for i in $(seq 1 "$checks_needed"); do
        if check_http_health "$health_url" 5; then
            consecutive=$((consecutive + 1))
            log_debug "Stability check ${i}/${checks_needed}: PASS (${consecutive} consecutive)"
        else
            consecutive=0
            log_warn "Stability check ${i}/${checks_needed}: FAIL (reset consecutive count)"
        fi
        sleep 5
    done

    if [[ "$consecutive" -ge "$checks_needed" ]]; then
        hc_pass "stability" "${consecutive} consecutive health checks passed"
    else
        hc_fail "stability" "Only ${consecutive}/${checks_needed} consecutive passes"
        return 1
    fi
}

# ─── Output JSON ─────────────────────────────────────────────────────────────
output_health_json() {
    local overall
    if [[ "$HC_FAIL" -eq 0 ]] && [[ "$HC_WARN" -eq 0 ]]; then
        overall="healthy"
    elif [[ "$HC_FAIL" -eq 0 ]] && [[ "$HC_WARN" -gt 0 ]]; then
        overall="degraded"
    else
        overall="unhealthy"
    fi

    local json
    json=$(jq -n \
        --arg service "$SERVICE_NAME" \
        --arg environment "$ENVIRONMENT" \
        --arg status "$overall" \
        --arg node "$(hostname -f 2>/dev/null || hostname)" \
        --arg timestamp "$(timestamp_iso)" \
        --arg deploy_id "${DEPLOY_ID:-unknown}" \
        --arg pass "$HC_PASS" \
        --arg fail "$HC_FAIL" \
        --arg warn "$HC_WARN" \
        --arg health_timeout "$HEALTH_TIMEOUT" \
        --arg monitor_window "$MONITOR_WINDOW" \
        '{
            service: $service,
            environment: $environment,
            status: $status,
            node: $node,
            timestamp: $timestamp,
            deploy_id: $deploy_id,
            config: {
                health_timeout_s: ($health_timeout | tonumber),
                monitor_window_s: ($monitor_window | tonumber)
            },
            summary: {
                passed: ($pass | tonumber),
                failed: ($fail | tonumber),
                warnings: ($warn | tonumber)
            },
            checks: {}
        }')

    # Add check results
    for check in "${!HC_RESULTS[@]}"; do
        if [[ ! "$check" =~ _detail$ ]]; then
            local status="${HC_RESULTS[$check]}"
            local detail="${HC_RESULTS[${check}_detail]:-}"
            json=$(echo "$json" | jq \
                --arg check "$check" \
                --arg status "$status" \
                --arg detail "$detail" \
                '.checks[$check] = {status: $status, detail: $detail}')
        fi
    done

    if [[ -n "$JSON_OUTPUT_FILE" ]]; then
        echo "$json" | jq '.' > "$JSON_OUTPUT_FILE"
        log_info "Health report written to: ${JSON_OUTPUT_FILE}"
    fi

    if $OUTPUT_JSON; then
        echo "$json" | jq '.'
    fi

    # Also output to stdout for CI/CD usage (compact)
    echo "$json" | jq -c '.' > "/tmp/wheeler_health_${SERVICE_NAME}.json"
    log_info "Health status: ${overall} (pass=${HC_PASS} fail=${HC_FAIL} warn=${HC_WARN})"
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    enable_error_tracing
    enable_signal_handlers

    # Validate args
    if [[ -z "$SERVICE_NAME" ]]; then
        log_error "Missing argument: service-name"
        _healthcheck_usage
    fi
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Missing argument: environment"
        _healthcheck_usage
    fi
    validate_environment "$ENVIRONMENT" || exit 3
    validate_service_name "$SERVICE_NAME" || exit 3

    # Validate numeric args
    if ! [[ "$HEALTH_TIMEOUT" =~ ^[0-9]+$ ]]; then
        log_error "Invalid timeout: ${HEALTH_TIMEOUT} (must be a positive integer)"
        exit 3
    fi

    log_section "Post-Deploy Health Check"
    log_kv "Service"           "$SERVICE_NAME"
    log_kv "Environment"       "$ENVIRONMENT"
    log_kv "Node"              "$(hostname)"
    log_kv "Timeout"           "${HEALTH_TIMEOUT}s"
    log_kv "Monitor Window"    "${MONITOR_WINDOW}s"
    log_kv "Stability Checks"  "$STABILITY_CHECKS"
    log_kv "Deploy ID"         "${DEPLOY_ID:-unknown}"
    log_kv "Start Time"        "$(timestamp_iso)"

    # ── Phase 1: Service Readiness ──────────────────────────────────────────
    if ! check_readiness "$SERVICE_NAME" "$HEALTH_TIMEOUT"; then
        log_fatal "Service did not become ready within ${HEALTH_TIMEOUT}s"
        if $OUTPUT_JSON || [[ -n "$JSON_OUTPUT_FILE" ]]; then
            output_health_json
        fi
        send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "CRITICAL" \
            "Service failed to become ready within ${HEALTH_TIMEOUT}s"
        exit 1
    fi

    # ── Phase 2: Initial Health Assessment ──────────────────────────────────
    check_resources "$SERVICE_NAME"
    check_logs "$SERVICE_NAME" "$MONITOR_WINDOW"
    check_deps_reachable "$SERVICE_NAME"

    # ── Phase 3: Stability Verification ─────────────────────────────────────
    check_stability "$SERVICE_NAME" "$STABILITY_CHECKS"

    # ── Summary ─────────────────────────────────────────────────────────────
    log_section "Health Check Summary"
    echo -e "  ${_C_GREEN}Passed:   ${HC_PASS}${_C_RESET}"
    echo -e "  ${_C_YELLOW}Warnings: ${HC_WARN}${_C_RESET}"
    echo -e "  ${_C_RED}Failed:   ${HC_FAIL}${_C_RESET}"

    # Output JSON if requested
    if $OUTPUT_JSON || [[ -n "$JSON_OUTPUT_FILE" ]]; then
        output_health_json
    fi

    # Determine exit code
    if [[ "$HC_FAIL" -gt 0 ]]; then
        log_fatal "Health check FAILED — ${HC_FAIL} failures detected"
        send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "CRITICAL" \
            "Post-deploy health check failed: ${HC_FAIL} failures"
        exit 1
    elif [[ "$HC_WARN" -gt 0 ]]; then
        log_warn "Health check DEGRADED — ${HC_WARN} warnings (service may still be functional)"
        send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "WARNING" \
            "Post-deploy health check degraded: ${HC_WARN} warnings"
        exit 2
    else
        log_success "Health check PASSED — service is healthy"
        send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "OK" \
            "Post-deploy health check passed"
        exit 0
    fi
}

# ─── Entry Point ─────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
