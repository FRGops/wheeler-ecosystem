#!/usr/bin/env bash
# =============================================================================
# Wheeler Deployment Engine — verify-deployment.sh
# =============================================================================
# Comprehensive deployment verification covering HTTP health, PM2 status,
# Docker container status, port listening, and recent log errors.
#
# Usage:
#   ./verify-deployment.sh <service-name> <environment>
#   ./verify-deployment.sh wheeler-api production
#   ./verify-deployment.sh --json wheeler-api production
#
# Exit Codes:
#   0 - All checks passed (healthy)
#   1 - One or more checks failed (unhealthy)
#   2 - Invalid arguments
#   3 - Dependency unreachable
# =============================================================================

set -euo pipefail

# ─── Source common utilities ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# ─── Script Configuration ────────────────────────────────────────────────────
readonly SCRIPT_NAME="verify-deployment.sh"
readonly SCRIPT_VERSION="1.0.0"

# ─── Parse flags ─────────────────────────────────────────────────────────────
OUTPUT_JSON=false
JSON_OUTPUT_FILE=""
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
        *)
            break
            ;;
    esac
done

# ─── Arguments ───────────────────────────────────────────────────────────────
SERVICE_NAME="${1:-}"
ENVIRONMENT="${2:-}"

# ─── Results tracking ────────────────────────────────────────────────────────
declare -A VERIFY_RESULTS
declare -a VERIFY_ERRORS
VERIFY_PASS_COUNT=0
VERIFY_FAIL_COUNT=0

# ─── Usage ───────────────────────────────────────────────────────────────────
_verify_usage() {
    cat <<EOF

${_C_BOLD}Usage:${_C_RESET} ./${SCRIPT_NAME} [--json] <service-name> <environment>

${_C_BOLD}Arguments:${_C_RESET}
  service-name   Name of the service to verify
  environment    Target environment (production, staging, dev)

${_C_BOLD}Options:${_C_RESET}
  --json              Output results as JSON to stdout
  --output, -o FILE   Write JSON results to FILE

${_C_BOLD}Exit Codes:${_C_RESET}
  0  All checks passed (healthy)
  1  One or more checks failed (unhealthy)
  2  Invalid arguments

${_C_BOLD}Examples:${_C_RESET}
  ./verify-deployment.sh wheeler-api production
  ./verify-deployment.sh --json changedetection staging
EOF
    exit 2
}

# ─── Record result ───────────────────────────────────────────────────────────
record_result() {
    local check="$1"
    local passed="$2"
    local detail="${3:-}"

    VERIFY_RESULTS["$check"]="$passed"
    VERIFY_RESULTS["${check}_detail"]="$detail"

    if [[ "$passed" == "true" ]]; then
        VERIFY_PASS_COUNT=$((VERIFY_PASS_COUNT + 1))
        log_info "  [PASS] ${check}: ${detail}"
    else
        VERIFY_FAIL_COUNT=$((VERIFY_FAIL_COUNT + 1))
        VERIFY_ERRORS+=("${check}: ${detail}")
        log_error "  [FAIL] ${check}: ${detail}"
    fi
}

# ─── Check 1: PM2 process status ─────────────────────────────────────────────
check_pm2_status() {
    log_info "--- Checking PM2 process status ---"

    if ! command -v pm2 &>/dev/null; then
        record_result "pm2_process" "skipped" "PM2 not installed (non-PM2 service)"
        return
    fi

    if ! pm2 ping &>/dev/null 2>&1; then
        record_result "pm2_process" "skipped" "PM2 daemon not running"
        return
    fi

    # Check if service exists in PM2
    if ! pm2 list 2>/dev/null | grep -q "$SERVICE_NAME"; then
        record_result "pm2_process" "skipped" "Service not managed by PM2"
        return
    fi

    local info
    info=$(get_pm2_process_info "$SERVICE_NAME")
    local status
    status=$(echo "$info" | jq -r '.pm2_env.status // "unknown"')

    if [[ "$status" == "online" ]]; then
        local instances restarts uptime cpu mem
        instances=$(echo "$info" | jq -r '.pm2_env.instances // "1"')
        restarts=$(echo "$info" | jq -r '.pm2_env.restart_time // 0')
        uptime=$(echo "$info" | jq -r '.pm2_env.pm_uptime // 0')
        cpu=$(echo "$info" | jq -r '.monit.cpu // 0')
        mem=$(echo "$info" | jq -r '.monit.memory // 0')

        local uptime_sec
        uptime_sec=$(( ( $(date +%s%3N 2>/dev/null || echo "0") - uptime ) / 1000 ))

        record_result "pm2_process" "true" \
            "status=${status} instances=${instances} restarts=${restarts} uptime=${uptime_sec}s cpu=${cpu}% mem=${mem}MB"
    else
        record_result "pm2_process" "false" \
            "status=${status}"
    fi
}

# ─── Check 2: Docker container status ────────────────────────────────────────
check_docker_status() {
    log_info "--- Checking Docker container status ---"

    if ! command -v docker &>/dev/null; then
        record_result "docker_container" "skipped" "Docker not installed (non-Docker service)"
        return
    fi

    if ! docker info &>/dev/null 2>&1; then
        record_result "docker_container" "skipped" "Docker daemon not running"
        return
    fi

    # Look for container by name
    local container_id
    container_id=$(docker ps -q --filter "name=${SERVICE_NAME}" 2>/dev/null || echo "")

    if [[ -z "$container_id" ]]; then
        record_result "docker_container" "skipped" "No running container found for ${SERVICE_NAME}"
        return
    fi

    # Check state and health
    local state health started_at
    state=$(docker inspect -f '{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown")
    health=$(docker inspect -f '{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "none")
    started_at=$(docker inspect -f '{{.State.StartedAt}}' "$container_id" 2>/dev/null || echo "unknown")

    if [[ "$state" == "running" ]]; then
        if [[ "$health" == "healthy" || "$health" == "none" ]]; then
            record_result "docker_container" "true" \
                "state=${state} health=${health} started=${started_at}"
        elif [[ "$health" == "starting" ]]; then
            record_result "docker_container" "true" \
                "state=${state} health=${health} (still starting)"
        else
            record_result "docker_container" "false" \
                "state=${state} health=${health} started=${started_at}"
        fi
    else
        record_result "docker_container" "false" \
            "state=${state} (not running)"
    fi
}

# ─── Check 3: Port listening ─────────────────────────────────────────────────
check_port_listening_check() {
    log_info "--- Checking port listening ---"

    local port
    port=$(get_service_port "$SERVICE_NAME")

    if [[ -z "$port" ]] || [[ "$port" == "null" ]] || [[ "$port" == "N/A" ]]; then
        record_result "port_listening" "skipped" "No port configured for this service"
        return
    fi

    if check_port_listening "$port"; then
        local process_info
        process_info=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1 | awk '{print $NF}' || echo "unknown")
        record_result "port_listening" "true" "port=${port} bound"
    else
        record_result "port_listening" "false" "port=${port} NOT listening"
    fi
}

# ─── Check 4: HTTP health endpoint ───────────────────────────────────────────
check_http_endpoint() {
    log_info "--- Checking HTTP health endpoint ---"

    local port
    port=$(get_service_port "$SERVICE_NAME")

    if [[ -z "$port" ]] || [[ "$port" == "null" ]] || [[ "$port" == "N/A" ]]; then
        record_result "http_health" "skipped" "No port configured"
        return
    fi

    local health_endpoint
    health_endpoint=$(get_health_endpoint "$SERVICE_NAME")
    health_endpoint="${health_endpoint:-/health}"

    local url="http://127.0.0.1:${port}${health_endpoint}"

    local http_code
    http_code=$(curl -s -o /tmp/wheeler_health_response_${SERVICE_NAME}.txt -w "%{http_code}" \
        --max-time 10 --connect-timeout 5 "${url}" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" || "$http_code" == "204" ]]; then
        local response_body
        response_body=$(head -c 500 /tmp/wheeler_health_response_${SERVICE_NAME}.txt 2>/dev/null || echo "")
        record_result "http_health" "true" "HTTP ${http_code} ${url}"
        log_debug "Health response: $(echo "$response_body" | head -c 200)"
    else
        record_result "http_health" "false" "HTTP ${http_code} ${url}"
        # Show error response
        if [[ -f /tmp/wheeler_health_response_${SERVICE_NAME}.txt ]]; then
            log_error "Response body: $(head -c 500 /tmp/wheeler_health_response_${SERVICE_NAME}.txt)"
        fi
    fi

    rm -f /tmp/wheeler_health_response_${SERVICE_NAME}.txt
}

# ─── Check 5: Recent log errors ──────────────────────────────────────────────
check_recent_logs() {
    log_info "--- Checking recent logs (last 60s) ---"

    local runtime
    runtime=$(get_service_runtime "$SERVICE_NAME")

    local error_count=0
    local sample_errors=""

    case "$runtime" in
        pm2)
            if command -v pm2 &>/dev/null && pm2 ping &>/dev/null 2>&1; then
                # Get recent PM2 logs
                local log_lines
                log_lines=$(pm2 logs "$SERVICE_NAME" --lines 100 --nostream 2>/dev/null || echo "")

                # Count error-level lines
                error_count=$(echo "$log_lines" | grep -c -iE '(error|fatal|critical|exception|panic)' 2>/dev/null || echo "0")
                sample_errors=$(echo "$log_lines" | grep -iE '(error|fatal|critical|exception|panic)' | tail -5 2>/dev/null || echo "")
            fi
            ;;
        docker)
            if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
                local container_id
                container_id=$(docker ps -q --filter "name=${SERVICE_NAME}" 2>/dev/null || echo "")
                if [[ -n "$container_id" ]]; then
                    local since_time
                    since_time=$(date -u -d '60 seconds ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo "")
                    local log_lines
                    log_lines=$(docker logs --since "$since_time" "$container_id" 2>&1 || echo "")
                    error_count=$(echo "$log_lines" | grep -c -iE '(error|fatal|critical|exception|panic)' 2>/dev/null || echo "0")
                    sample_errors=$(echo "$log_lines" | grep -iE '(error|fatal|critical|exception|panic)' | tail -5 2>/dev/null || echo "")
                fi
            fi
            ;;
        systemd)
            if command -v journalctl &>/dev/null; then
                local log_lines
                log_lines=$(journalctl -u "$SERVICE_NAME" --since "60 seconds ago" --no-pager 2>/dev/null || echo "")
                error_count=$(echo "$log_lines" | grep -c -iE '(error|fatal|critical|exception)' 2>/dev/null || echo "0")
                sample_errors=$(echo "$log_lines" | grep -iE '(error|fatal|critical|exception)' | tail -5 2>/dev/null || echo "")
            fi
            ;;
        *)
            record_result "recent_logs" "skipped" "Unknown runtime: ${runtime}"
            return
            ;;
    esac

    if [[ "$error_count" -eq 0 ]]; then
        record_result "recent_logs" "true" "No recent errors found in logs"
    elif [[ "$error_count" -le 5 ]]; then
        record_result "recent_logs" "true" "${error_count} errors in recent logs (within acceptable range)"
        if [[ -n "$sample_errors" ]]; then
            log_debug "Sample errors:"
            echo "$sample_errors" | while read -r line; do log_debug "  ${line}"; done
        fi
    else
        record_result "recent_logs" "false" "${error_count} errors in recent logs"
        if [[ -n "$sample_errors" ]]; then
            log_warn "Sample recent errors:"
            echo "$sample_errors" | while read -r line; do log_warn "  ${line}"; done
        fi
    fi
}

# ─── Check 6: Resource usage ─────────────────────────────────────────────────
check_resource_usage() {
    log_info "--- Checking resource usage ---"

    local runtime
    runtime=$(get_service_runtime "$SERVICE_NAME")

    local cpu mem pid
    cpu="0"
    mem="0"

    case "$runtime" in
        pm2)
            if command -v pm2 &>/dev/null && pm2 ping &>/dev/null 2>&1; then
                cpu=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${SERVICE_NAME}\") | .monit.cpu // 0" 2>/dev/null || echo "0")
                mem=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${SERVICE_NAME}\") | .monit.memory // 0" 2>/dev/null || echo "0")
            fi
            ;;
        docker)
            if command -v docker &>/dev/null; then
                local container_id
                container_id=$(docker ps -q --filter "name=${SERVICE_NAME}" 2>/dev/null || echo "")
                if [[ -n "$container_id" ]]; then
                    local stats
                    stats=$(docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}}' "$container_id" 2>/dev/null || echo "0% 0MiB/0MiB")
                    cpu=$(echo "$stats" | awk '{print $1}' | tr -d '%')
                    mem=$(echo "$stats" | awk '{print $2}' | sed 's/MiB.*//')
                fi
            fi
            ;;
    esac

    local cpu_int="${cpu%.*}"
    if [[ "$cpu_int" -gt 90 ]] 2>/dev/null; then
        record_result "resource_usage" "false" "CPU=${cpu}% (exceeds 90%), Memory=${mem}MB"
    elif [[ "$cpu_int" -gt 75 ]] 2>/dev/null; then
        record_result "resource_usage" "true" "CPU=${cpu}% (elevated), Memory=${mem}MB"
    else
        record_result "resource_usage" "true" "CPU=${cpu}%, Memory=${mem}MB"
    fi
}

# ─── Check 7: Dependencies reachable ─────────────────────────────────────────
check_dependencies() {
    log_info "--- Checking dependencies ---"

    local deps_json
    deps_json=$(get_service_info "$SERVICE_NAME" "dependencies" 2>/dev/null || echo "")

    if [[ -z "$deps_json" ]] || [[ "$deps_json" == "null" ]]; then
        record_result "dependencies" "skipped" "No dependencies configured in service catalog"
        return
    fi

    # Check PostgreSQL dependency
    if echo "$deps_json" | grep -qi "postgresql"; then
        local pg_host="${DB_PRIMARY_HOST:-5.78.210.123}"
        local pg_port="${DB_PRIMARY_PORT:-5432}"
        if timeout 5 bash -c "echo >/dev/tcp/${pg_host}/${pg_port}" 2>/dev/null; then
            record_result "dependency_postgresql" "true" "${pg_host}:${pg_port} reachable"
        else
            record_result "dependency_postgresql" "false" "${pg_host}:${pg_port} UNREACHABLE"
        fi
    fi

    # Check Redis dependency
    if echo "$deps_json" | grep -qi "redis"; then
        local redis_host="${REDIS_HOST:-5.78.210.123}"
        local redis_port="${REDIS_PORT:-6379}"
        if timeout 5 bash -c "echo >/dev/tcp/${redis_host}/${redis_port}" 2>/dev/null; then
            record_result "dependency_redis" "true" "${redis_host}:${redis_port} reachable"
        else
            record_result "dependency_redis" "false" "${redis_host}:${redis_port} UNREACHABLE"
        fi
    fi

    # Check MinIO dependency
    if echo "$deps_json" | grep -qi "minio"; then
        local minio_host="5.78.210.123"
        local minio_port="9000"
        if timeout 5 bash -c "echo >/dev/tcp/${minio_host}/${minio_port}" 2>/dev/null; then
            record_result "dependency_minio" "true" "${minio_host}:${minio_port} reachable"
        else
            record_result "dependency_minio" "false" "${minio_host}:${minio_port} UNREACHABLE"
        fi
    fi
}

# ─── Output JSON ─────────────────────────────────────────────────────────────
output_json_results() {
    local overall
    if [[ "$VERIFY_FAIL_COUNT" -eq 0 ]]; then
        overall="healthy"
    else
        overall="unhealthy"
    fi

    # Build JSON
    local json
    json=$(jq -n \
        --arg service "$SERVICE_NAME" \
        --arg environment "$ENVIRONMENT" \
        --arg status "$overall" \
        --arg node "$(hostname -f 2>/dev/null || hostname)" \
        --arg timestamp "$(timestamp_iso)" \
        --arg deploy_id "${DEPLOY_ID:-unknown}" \
        --arg pass "$VERIFY_PASS_COUNT" \
        --arg fail "$VERIFY_FAIL_COUNT" \
        '{
            service: $service,
            environment: $environment,
            status: $status,
            node: $node,
            timestamp: $timestamp,
            deploy_id: $deploy_id,
            summary: {
                passed: ($pass | tonumber),
                failed: ($fail | tonumber)
            },
            checks: {}
        }')

    # Add individual checks
    for check in "${!VERIFY_RESULTS[@]}"; do
        if [[ ! "$check" =~ _detail$ ]]; then
            local passed="${VERIFY_RESULTS[$check]}"
            local detail="${VERIFY_RESULTS[${check}_detail]:-}"
            json=$(echo "$json" | jq \
                --arg check "$check" \
                --arg passed "$passed" \
                --arg detail "$detail" \
                '.checks[$check] = {passed: $passed, detail: $detail}')
        fi
    done

    # Add errors array
    if [[ ${#VERIFY_ERRORS[@]} -gt 0 ]]; then
        local errors_json="["
        local first=true
        for err in "${VERIFY_ERRORS[@]}"; do
            if $first; then
                errors_json+="\"${err}\""
                first=false
            else
                errors_json+=",\"${err}\""
            fi
        done
        errors_json+="]"
        json=$(echo "$json" | jq --argjson errors "$errors_json" '. + {errors: $errors}')
    fi

    # Output
    if [[ -n "$JSON_OUTPUT_FILE" ]]; then
        echo "$json" | jq '.' > "$JSON_OUTPUT_FILE"
        log_info "JSON results written to: ${JSON_OUTPUT_FILE}"
    fi

    if $OUTPUT_JSON; then
        echo "$json" | jq '.'
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    enable_error_tracing
    enable_signal_handlers

    # Validate args
    if [[ -z "$SERVICE_NAME" ]]; then
        log_error "Missing argument: service-name"
        _verify_usage
    fi
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Missing argument: environment"
        _verify_usage
    fi
    validate_environment "$ENVIRONMENT" || exit 2

    log_section "Deployment Verification: ${SERVICE_NAME} (${ENVIRONMENT})"
    log_kv "Service"     "$SERVICE_NAME"
    log_kv "Environment" "$ENVIRONMENT"
    log_kv "Node"        "$(hostname)"
    log_kv "Deploy ID"   "${DEPLOY_ID:-unknown}"
    echo ""

    # Run all checks
    check_pm2_status
    check_docker_status
    check_port_listening_check
    check_http_endpoint
    check_recent_logs
    check_resource_usage
    check_dependencies

    # Summary
    echo ""
    log_section "Verification Summary"
    echo -e "  ${_C_GREEN}Passed: ${VERIFY_PASS_COUNT}${_C_RESET}"
    echo -e "  ${_C_RED}Failed: ${VERIFY_FAIL_COUNT}${_C_RESET}"
    echo ""

    # Output JSON if requested
    if $OUTPUT_JSON || [[ -n "$JSON_OUTPUT_FILE" ]]; then
        output_json_results
    fi

    # Return appropriate exit code
    if [[ "$VERIFY_FAIL_COUNT" -eq 0 ]]; then
        log_success "VERIFICATION PASSED — ${SERVICE_NAME} is healthy"
        return 0
    else
        log_fatal "VERIFICATION FAILED — ${SERVICE_NAME} has ${VERIFY_FAIL_COUNT} failing checks"
        send_health_alert "$SERVICE_NAME" "$ENVIRONMENT" "CRITICAL" \
            "Verification failed: ${VERIFY_FAIL_COUNT} checks failed"
        return 1
    fi
}

# ─── Entry Point ─────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
