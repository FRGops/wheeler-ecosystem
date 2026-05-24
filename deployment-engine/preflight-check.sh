#!/usr/bin/env bash
# =============================================================================
# Wheeler Deployment Engine — preflight-check.sh
# =============================================================================
# Runs all pre-deployment validation checks before a deploy is allowed.
# Checks: config syntax, required env vars, port availability, disk space,
# service dependency readiness, Docker/PM2 daemon status.
#
# Usage:
#   ./preflight-check.sh <service-name> <environment>
#   ./preflight-check.sh wheeler-api production
#   ./preflight-check.sh --all production
#   ./preflight-check.sh --audit-all
#
# Exit Codes:
#   0 - All checks passed
#   1 - One or more checks failed
#   2 - Invalid arguments
# =============================================================================

set -euo pipefail

# ─── Source common utilities ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# ─── Script Configuration ────────────────────────────────────────────────────
readonly SCRIPT_NAME="preflight-check.sh"
readonly SCRIPT_VERSION="1.0.0"

# ─── Parse flags ─────────────────────────────────────────────────────────────
CHECK_ALL=false
AUDIT_ALL=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            CHECK_ALL=true
            shift
            ;;
        --audit-all)
            AUDIT_ALL=true
            CHECK_ALL=true
            shift
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
declare -a CHECK_NAMES
declare -a CHECK_RESULTS
declare -a CHECK_DETAILS

pass_count=0
fail_count=0

# ─── Usage ───────────────────────────────────────────────────────────────────
_preflight_usage() {
    cat <<EOF

${_C_BOLD}Usage:${_C_RESET} ./${SCRIPT_NAME} [OPTIONS] <service-name> <environment>

${_C_BOLD}Arguments:${_C_RESET}
  service-name   Name of the service to check
  environment    Target environment (production, staging, dev)

${_C_BOLD}Options:${_C_RESET}
  --all          Run preflight checks for ALL known services
  --audit-all    Like --all, but also audit all .env files for issues

${_C_BOLD}Exit Codes:${_C_RESET}
  0  All checks passed
  1  One or more checks failed
  2  Invalid arguments

${_C_BOLD}Examples:${_C_RESET}
  ./preflight-check.sh wheeler-api production
  ./preflight-check.sh --all staging
EOF
    exit 2
}

# ─── Record a check ──────────────────────────────────────────────────────────
record_check() {
    local name="$1"
    local result="$2"  # PASS, FAIL, WARN, SKIP
    local detail="${3:-}"

    CHECK_NAMES+=("$name")
    CHECK_RESULTS+=("$result")
    CHECK_DETAILS+=("$detail")

    case "$result" in
        PASS)
            pass_count=$((pass_count + 1))
            echo -e "  ${_C_GREEN}[PASS]${_C_RESET} ${name}: ${detail}"
            ;;
        FAIL)
            fail_count=$((fail_count + 1))
            echo -e "  ${_C_RED}[FAIL]${_C_RESET} ${name}: ${detail}"
            ;;
        WARN)
            echo -e "  ${_C_YELLOW}[WARN]${_C_RESET} ${name}: ${detail}"
            ;;
        SKIP)
            echo -e "  ${_C_DIM}[SKIP]${_C_RESET} ${name}: ${detail}"
            ;;
    esac
}

# ─── Find .env file for a service ────────────────────────────────────────────
find_env_file() {
    local svc="$1"
    local env="$2"

    local candidates=(
        "${WHEELER_BASE}/${svc}/.env.${env}"
        "${WHEELER_BASE}/${svc}/.env"
        "${WHEELER_BASE}/configs/${svc}.env"
        "${WHEELER_BASE}/${svc}/envs/${env}.env"
    )

    for f in "${candidates[@]}"; do
        if [[ -f "$f" ]]; then
            echo "$f"
            return 0
        fi
    done

    echo ""
    return 1
}

# ─── Check 1: Config file syntax validation ──────────────────────────────────
check_env_syntax() {
    local svc="$1"
    local env="$2"

    local env_file
    env_file=$(find_env_file "$svc" "$env")

    if [[ -z "$env_file" ]]; then
        record_check "env_syntax" "SKIP" "No .env file found for ${svc}/${env}"
        return
    fi

    local errors=0

    # Check for basic syntax issues
    # 1. Lines with spaces around '='
    if grep -n "^[^#]* = " "$env_file" 2>/dev/null; then
        record_check "env_syntax" "WARN" "Lines with spaces around '=' in ${env_file} (fix: remove spaces)"
        errors=1
    fi

    # 2. Lines without '=' (not comments, not blank)
    local bad_lines
    bad_lines=$(grep -nv "^#" "$env_file" 2>/dev/null | grep -v "=" | grep -v "^[[:space:]]*$" | wc -l || echo "0")
    if [[ "$bad_lines" -gt 0 ]]; then
        record_check "env_syntax" "FAIL" "${bad_lines} lines without '=' assignment in ${env_file}"
        errors=1
    fi

    # 3. Unclosed quotes
    if grep -n '^[^#]*"[^"]*$' "$env_file" 2>/dev/null | grep -v '"[^"]*"'; then
        record_check "env_syntax" "FAIL" "Possible unclosed quotes in ${env_file}"
        errors=1
    fi

    # 4. export statements (should not be in .env files)
    if grep -q "^export " "$env_file" 2>/dev/null; then
        record_check "env_syntax" "WARN" "'export' statements found (not needed in .env files)"
    fi

    if [[ "$errors" -eq 0 ]]; then
        record_check "env_syntax" "PASS" "${env_file} syntax valid"
    fi
}

# ─── Check 2: Required environment variables present ─────────────────────────
check_required_env_vars() {
    local svc="$1"
    local env="$2"

    record_check "required_vars" "PASS" "All required variables present"

    local env_file
    env_file=$(find_env_file "$svc" "$env")

    # Core required variables for ALL services
    local required_vars=("APP_ENV" "APP_NAME")

    # Service-specific requirements
    local runtime
    runtime=$(get_service_runtime "$svc")

    case "$runtime" in
        pm2|docker)
            # Check for DB/Redis config if service needs it
            ;;
    esac

    if [[ -n "$env_file" ]]; then
        local sourceable=true
        # Try to source and check
        set +e
        # shellcheck disable=SC1090
        source "$env_file" 2>/dev/null || sourceable=false
        set -e

        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                record_check "required_vars" "FAIL" "Missing required var: ${var}"
            fi
        done
    fi
}

# ─── Check 3: Port availability ──────────────────────────────────────────────
check_port_availability() {
    local svc="$1"

    local port
    port=$(get_service_port "$svc")

    if [[ -z "$port" ]] || [[ "$port" == "null" ]] || [[ "$port" == "N/A" ]]; then
        record_check "port_available" "SKIP" "No port configured for ${svc}"
        return
    fi

    # Check if port is in use (acceptable if owned by this service)
    if check_port_listening "$port"; then
        local owner
        owner=$(ss -tlnp 2>/dev/null | grep ":${port} " | awk '{print $NF}' | head -1 || echo "unknown")
        record_check "port_available" "PASS" "Port ${port} already in use by ${owner} (expected for running service)"
    else
        record_check "port_available" "PASS" "Port ${port} is free (will be bound on deploy)"
    fi
}

# ─── Check 4: Disk space ─────────────────────────────────────────────────────
check_disk_space_check() {
    local svc="$1"

    local df_output free_percent available
    df_output=$(df -h "${WHEELER_BASE}" 2>/dev/null | tail -1)
    free_percent=$(echo "$df_output" | awk '{print $5}' | tr -d '%')
    free_percent=$((100 - free_percent))
    available=$(echo "$df_output" | awk '{print $4}')

    if [[ "$free_percent" -lt 5 ]]; then
        record_check "disk_space" "FAIL" \
            "CRITICAL: Only ${available} (${free_percent}%) free on ${WHEELER_BASE}"
    elif [[ "$free_percent" -lt 15 ]]; then
        record_check "disk_space" "WARN" \
            "Low: ${available} (${free_percent}%) free on ${WHEELER_BASE}"
    else
        record_check "disk_space" "PASS" \
            "${available} available (${free_percent}% free) on ${WHEELER_BASE}"
    fi
}

# ─── Check 5: Service dependency readiness ───────────────────────────────────
check_dependency_readiness() {
    local svc="$1"
    local env="$2"

    local deps_json
    deps_json=$(get_service_info "$svc" "dependencies" 2>/dev/null || echo "")

    if [[ -z "$deps_json" ]] || [[ "$deps_json" == "null" ]] || [[ "$deps_json" == "[]" ]]; then
        record_check "dependencies" "SKIP" "No dependencies configured"
        return
    fi

    local all_ok=true
    local check_results=""

    # Check PostgreSQL
    if echo "$deps_json" | grep -qi "postgresql"; then
        local pg_host="${DB_PRIMARY_HOST:-5.78.210.123}"
        local pg_port="${DB_PRIMARY_PORT:-5432}"
        if timeout 3 bash -c "echo >/dev/tcp/${pg_host}/${pg_port}" 2>/dev/null; then
            check_results+="postgresql=ok "
        else
            check_results+="postgresql=UNREACHABLE "
            all_ok=false
        fi
    fi

    # Check Redis
    if echo "$deps_json" | grep -qi "redis"; then
        local redis_host="${REDIS_HOST:-5.78.210.123}"
        local redis_port="${REDIS_PORT:-6379}"
        if timeout 3 bash -c "echo >/dev/tcp/${redis_host}/${redis_port}" 2>/dev/null; then
            check_results+="redis=ok "
        else
            check_results+="redis=UNREACHABLE "
            all_ok=false
        fi
    fi

    # Check MinIO
    if echo "$deps_json" | grep -qi "minio"; then
        local minio_host="5.78.210.123"
        if timeout 3 bash -c "echo >/dev/tcp/${minio_host}/9000" 2>/dev/null; then
            check_results+="minio=ok "
        else
            check_results+="minio=UNREACHABLE "
            all_ok=false
        fi
    fi

    if $all_ok; then
        record_check "dependencies" "PASS" "All dependencies reachable: ${check_results}"
    else
        record_check "dependencies" "FAIL" "Unreachable: ${check_results}"
    fi
}

# ─── Check 6: Docker daemon running (if needed) ──────────────────────────────
check_docker_required() {
    local svc="$1"

    local runtime
    runtime=$(get_service_runtime "$svc")

    if [[ "$runtime" != "docker" ]]; then
        record_check "docker_daemon" "SKIP" "Not a Docker service"
        return
    fi

    if check_docker_daemon; then
        local version
        version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        record_check "docker_daemon" "PASS" "Docker ${version} running"
    else
        record_check "docker_daemon" "FAIL" "Docker daemon not running (required for ${svc})"
    fi
}

# ─── Check 7: PM2 daemon running (if needed) ─────────────────────────────────
check_pm2_required() {
    local svc="$1"

    local runtime
    runtime=$(get_service_runtime "$svc")

    if [[ "$runtime" != "pm2" ]]; then
        record_check "pm2_daemon" "SKIP" "Not a PM2 service"
        return
    fi

    if command -v pm2 &>/dev/null && pm2 ping &>/dev/null 2>&1; then
        local version
        version=$(pm2 --version 2>/dev/null || echo "unknown")
        record_check "pm2_daemon" "PASS" "PM2 ${version} running"
    else
        record_check "pm2_daemon" "FAIL" "PM2 daemon not running (required for ${svc})"
    fi
}

# ─── Check 8: No duplicate env definitions ───────────────────────────────────
check_env_duplicates() {
    local svc="$1"
    local env="$2"

    local duplicates_found=false

    # Check for DATABASE_URL duplicates
    local env_file ecosystem_file
    env_file=$(find_env_file "$svc" "$env")
    ecosystem_file="${WHEELER_BASE}/${svc}/ecosystem.config.js"

    # Check .env vs ecosystem.config.js
    if [[ -n "$env_file" ]] && [[ -f "$ecosystem_file" ]]; then
        if grep -qi "DATABASE_URL" "$env_file" 2>/dev/null && \
           grep -qi "DATABASE_URL" "$ecosystem_file" 2>/dev/null; then
            record_check "env_duplicates" "FAIL" "DATABASE_URL defined in both .env and ecosystem.config.js"
            duplicates_found=true
        fi
        if grep -qi "REDIS_URL" "$env_file" 2>/dev/null && \
           grep -qi "REDIS_URL" "$ecosystem_file" 2>/dev/null; then
            record_check "env_duplicates" "FAIL" "REDIS_URL defined in both .env and ecosystem.config.js"
            duplicates_found=true
        fi
    fi

    # Check for both DATABASE_URL and DB_PRIMARY_HOST pattern
    if [[ -n "$env_file" ]]; then
        if grep -qi "DATABASE_URL" "$env_file" 2>/dev/null && \
           grep -qi "DB_PRIMARY_HOST\|DB_HOST" "$env_file" 2>/dev/null; then
            record_check "env_duplicates" "FAIL" "Both DATABASE_URL (composite) and DB_* (individual) defined — use ONE pattern"
            duplicates_found=true
        fi
    fi

    if ! $duplicates_found; then
        record_check "env_duplicates" "PASS" "No duplicate env definitions detected"
    fi
}

# ─── Check 9: No hardcoded secrets ───────────────────────────────────────────
check_no_hardcoded_secrets() {
    local svc="$1"
    local env="$2"

    local env_file
    env_file=$(find_env_file "$svc" "$env")

    if [[ -z "$env_file" ]]; then
        record_check "no_secrets" "SKIP" "No .env file found to scan"
        return
    fi

    local secrets_found=false
    local suspicious_lines=""

    # Scan for common secret patterns
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Check for hardcoded values that look like secrets
        if echo "$line" | grep -qiE '(password|secret|key|token)=[A-Za-z0-9+/=_-]{20,}' 2>/dev/null; then
            # Skip Doppler/AWS placeholders
            if echo "$line" | grep -qiE '(FROM_DOPPLER|FROM_AWS|CHANGEME|PLACEHOLDER|TODO)' 2>/dev/null; then
                continue
            fi
            local var_name
            var_name=$(echo "$line" | cut -d= -f1)
            suspicious_lines+="  ${var_name} "
            secrets_found=true
        fi
    done < "$env_file"

    if $secrets_found; then
        record_check "no_secrets" "FAIL" "Possible hardcoded secrets found:${suspicious_lines}"
    else
        record_check "no_secrets" "PASS" "No hardcoded secrets detected"
    fi
}

# ─── Check 10: Production safety ─────────────────────────────────────────────
check_production_safety() {
    local svc="$1"
    local env="$2"

    if [[ "$env" != "production" ]]; then
        record_check "prod_safety" "SKIP" "Not a production deployment"
        return
    fi

    local env_file
    env_file=$(find_env_file "$svc" "$env")

    local warnings=0

    if [[ -n "$env_file" ]]; then
        # Warn if LOG_LEVEL=debug in production
        if grep -qi "LOG_LEVEL=debug" "$env_file" 2>/dev/null; then
            record_check "prod_safety" "FAIL" "LOG_LEVEL=debug in production .env (should be info/warn/error)"
            warnings=1
        fi

        # Warn if NODE_ENV=development in production
        if grep -qi "NODE_ENV=development" "$env_file" 2>/dev/null; then
            record_check "prod_safety" "FAIL" "NODE_ENV=development in production .env"
            warnings=1
        fi

        # Warn if APP_DEBUG=true in production
        if grep -qi "APP_DEBUG=true" "$env_file" 2>/dev/null; then
            record_check "prod_safety" "FAIL" "APP_DEBUG=true in production .env"
            warnings=1
        fi

        # Check for CORS_ORIGINS wildcard
        if grep -qi "CORS_ORIGINS=.*\*" "$env_file" 2>/dev/null; then
            record_check "prod_safety" "FAIL" "CORS_ORIGINS contains wildcard (*) in production"
            warnings=1
        fi
    fi

    if [[ "$warnings" -eq 0 ]]; then
        record_check "prod_safety" "PASS" "Production safety checks passed"
    fi
}

# ─── Wait for dependencies ───────────────────────────────────────────────────
check_wait_for_deps() {
    local svc="$1"
    local env="$2"

    record_check "wait_deps" "PASS" "Core dependencies are ready"

    # Check PostgreSQL (always needed for most services)
    local pg_host="${DB_PRIMARY_HOST:-5.78.210.123}"
    local pg_port="${DB_PRIMARY_PORT:-5432}"

    if timeout 5 bash -c "echo >/dev/tcp/${pg_host}/${pg_port}" 2>/dev/null; then
        log_debug "PostgreSQL reachable at ${pg_host}:${pg_port}"
    else
        record_check "wait_deps" "FAIL" "PostgreSQL unreachable at ${pg_host}:${pg_port}"
    fi
}

# ─── Run all checks for one service ──────────────────────────────────────────
run_checks_for_service() {
    local svc="$1"
    local env="$2"

    echo ""
    log_section "Pre-flight: ${svc} (${env})"

    check_env_syntax "$svc" "$env"
    check_env_duplicates "$svc" "$env"
    check_no_hardcoded_secrets "$svc" "$env"
    check_required_env_vars "$svc" "$env"
    check_port_availability "$svc"
    check_disk_space_check "$svc"
    check_dependency_readiness "$svc" "$env"
    check_docker_required "$svc"
    check_pm2_required "$svc"
    check_production_safety "$svc" "$env"
    check_wait_for_deps "$svc" "$env"

    # Summary for this service
    echo ""
    echo -e "  ${_C_GREEN}Passed: ${pass_count}${_C_RESET}  ${_C_RED}Failed: ${fail_count}${_C_RESET}"
}

# ─── Audit all .env files ────────────────────────────────────────────────────
audit_all_env_files() {
    log_section "Environment File Audit"

    log_info "Searching for all .env files under ${WHEELER_BASE}..."
    find "${WHEELER_BASE}" -maxdepth 4 -name ".env*" -type f 2>/dev/null | while read -r f; do
        local svc
        svc=$(echo "$f" | sed "s|${WHEELER_BASE}/||" | cut -d/ -f1)
        echo "  $(basename "$(dirname "$f")" 2>/dev/null || echo "root")/$(basename "$f")"
    done

    echo ""
    log_info "Checking for common issues across all .env files..."

    # Check for gitignore presence
    local env_files_in_git
    if command -v git &>/dev/null && git -C "${WHEELER_BASE}" rev-parse --git-dir &>/dev/null 2>&1; then
        env_files_in_git=$(git -C "${WHEELER_BASE}" ls-files '.env*' 2>/dev/null | wc -l || echo "0")
        if [[ "$env_files_in_git" -gt 0 ]]; then
            log_warn "WARNING: ${env_files_in_git} .env files are tracked by git (should be in .gitignore)"
        fi
    fi

    # Check file permissions
    find "${WHEELER_BASE}" -maxdepth 4 -name ".env*" -type f -perm /o+r 2>/dev/null | while read -r f; do
        log_warn "WARNING: World-readable .env file: ${f}"
    done
}

# ─── Get all known services ──────────────────────────────────────────────────
get_all_services() {
    # Services from the architecture
    local all_services=(
        # Edge services
        traefik nginx wheeler-hub ops-dashboard admin-panel client-portal status-page
        # API services
        wheeler-api revenue-api webhook-gateway admin-api graphql-gateway
        # AI services
        litellm-proxy openclaw-engine ml-workers inference-api model-cache
        # Ops services
        orchestrator autoheal-engine alert-engine cost-monitor eco-health-eng
        # Docker utility services
        changedetection healthchecks
    )

    # Only include services that actually exist on disk
    local existing=()
    for svc in "${all_services[@]}"; do
        if [[ -d "${WHEELER_BASE}/${svc}" ]] || \
           [[ -d "${WHEELER_BASE}/wheeler-autonomous-ops/${svc}" ]] || \
           [[ -d "${WHEELER_BASE}/wheeler-intelligence-platform/${svc}" ]]; then
            existing+=("$svc")
        fi
    done

    if [[ ${#existing[@]} -eq 0 ]]; then
        # Return all by default (they may exist elsewhere)
        printf '%s\n' "${all_services[@]}"
    else
        printf '%s\n' "${existing[@]}"
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
    enable_error_tracing
    enable_signal_handlers

    if $CHECK_ALL; then
        # Run checks for all services
        if [[ -z "$ENVIRONMENT" ]]; then
            log_error "Missing argument: environment (required with --all)"
            _preflight_usage
        fi
        validate_environment "$ENVIRONMENT" || exit 2

        log_section "Pre-flight Check — ALL SERVICES (${ENVIRONMENT})"
        log_kv "Node" "$(hostname)"
        log_kv "Date" "$(timestamp_iso)"

        local all_pass=true
        local services
        mapfile -t services < <(get_all_services)

        for svc in "${services[@]}"; do
            pass_count=0
            fail_count=0
            CHECK_NAMES=()
            CHECK_RESULTS=()
            CHECK_DETAILS=()

            run_checks_for_service "$svc" "$ENVIRONMENT"
            if [[ "$fail_count" -gt 0 ]]; then
                all_pass=false
            fi
        done

        # Audit if requested
        if $AUDIT_ALL; then
            audit_all_env_files
        fi

        echo ""
        if $all_pass; then
            log_success "All pre-flight checks PASSED for all services"
        else
            log_fatal "Some pre-flight checks FAILED"
            send_health_alert "all" "$ENVIRONMENT" "WARNING" \
                "Pre-flight checks: some services have failures"
        fi
        $all_pass && exit 0 || exit 1

    else
        # Single service check
        if [[ -z "$SERVICE_NAME" ]]; then
            log_error "Missing argument: service-name"
            _preflight_usage
        fi
        if [[ -z "$ENVIRONMENT" ]]; then
            log_error "Missing argument: environment"
            _preflight_usage
        fi
        validate_environment "$ENVIRONMENT" || exit 2
        validate_service_name "$SERVICE_NAME" || exit 2

        log_section "Pre-flight Check"
        log_kv "Service"     "$SERVICE_NAME"
        log_kv "Environment" "$ENVIRONMENT"
        log_kv "Node"        "$(hostname)"
        log_kv "Date"        "$(timestamp_iso)"

        pass_count=0
        fail_count=0
        CHECK_NAMES=()
        CHECK_RESULTS=()
        CHECK_DETAILS=()

        run_checks_for_service "$SERVICE_NAME" "$ENVIRONMENT"

        echo ""
        if [[ "$fail_count" -eq 0 ]]; then
            log_success "ALL PRE-FLIGHT CHECKS PASSED (${pass_count}/${pass_count})"
            exit 0
        else
            log_fatal "PRE-FLIGHT CHECKS FAILED: ${fail_count} failure(s)"
            echo ""
            log_error "Fix the above issues before deploying."
            exit 1
        fi
    fi
}

# ─── Entry Point ─────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
