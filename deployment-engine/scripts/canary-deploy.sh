#!/usr/bin/env bash
# =============================================================================
# Canary Deployment Script — Wheeler Deployment Engine
# =============================================================================
# Deploys a new version to a single canary instance first, validates health,
# compares against stable instances, then promotes or rolls back.
#
# Usage:
#   ./canary-deploy.sh <service-name> [canary-percentage] [--auto-promote]
#   ./canary-deploy.sh wheeler-api 25
#   ./canary-deploy.sh revenue-api 30 --auto-promote --dry-run
#
# Workflow:
#   1. Clone current PM2 process as <service>-canary with same config
#   2. Wait for warmup (CANARY_WARMUP_SECONDS)
#   3. Run N consecutive health checks (CANARY_HEALTH_RETRIES)
#   4. Compare health metrics against the stable process:
#      - HTTP status code match
#      - Response time within 20% of stable
#      - Error rate <= stable
#      - Memory usage within 30% of stable
#   5. If healthy: promote canary to full fleet OR mark for promotion
#   6. If unhealthy: auto-rollback the canary instance
#   7. Log all decisions to CANARY_LOG_DIR/canary.log
#
# Exit Codes:
#   0  Canary passed all health checks (promoted or ready for promotion)
#   1  Canary failed health checks (rolled back if auto-rollback enabled)
#   2  Invalid arguments
#   3  PM2 daemon not available
#   4  Service not found in PM2
#   5  Canary health check timed out
#   6  Dry run completed (no changes made)
# =============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="1.0.0"

# ─── Source configuration ────────────────────────────────────────────────────

CANARY_CONFIG="${SCRIPT_DIR}/../configs/canary-defaults.conf"
if [[ -f "$CANARY_CONFIG" ]]; then
    # shellcheck source=../configs/canary-defaults.conf
    source "$CANARY_CONFIG"
fi

# Source common utilities if available
if [[ -f "${SCRIPT_DIR}/../common.sh" ]]; then
    # shellcheck source=../common.sh
    source "${SCRIPT_DIR}/../common.sh"
    HAS_COMMON_SH=true
else
    HAS_COMMON_SH=false
    # Minimal logging if common.sh not available
    _ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
    log_info()    { echo "[$(_ts)] [INFO]    $*" >&2; }
    log_warn()    { echo "[$(_ts)] [WARN]    $*" >&2; }
    log_error()   { echo "[$(_ts)] [ERROR]   $*" >&2; }
    log_success() { echo "[$(_ts)] [SUCCESS] $*" >&2; }
    log_fatal()   { echo "[$(_ts)] [FATAL]   $*" >&2; }
    log_section() { echo ""; echo "===== $* =====" >&2; }
    log_kv()      { echo "[$(_ts)] [CONFIG]  $1=$2" >&2; }
fi

# ─── Paths & State ───────────────────────────────────────────────────────────

readonly CANARY_LOG_FILE="${CANARY_LOG_DIR}/canary.log"
mkdir -p "$CANARY_LOG_DIR" "$CANARY_STATE_DIR"

# ─── Argument Parsing ────────────────────────────────────────────────────────

SERVICE_NAME=""
CANARY_PERCENTAGE=25
AUTO_PROMOTE="${CANARY_AUTO_PROMOTE:-false}"
DRY_RUN=false
FORCE_MODE=false
VERBOSE=false

usage() {
    cat <<EOF
canary-deploy.sh — Canary Deployment Script v${SCRIPT_VERSION}

Usage: $(basename "$0") <service-name> [canary-percentage] [OPTIONS]

Deploys a service to a single canary PM2 instance, validates health against
the stable process, and promotes or rolls back based on health metrics.

Arguments:
  service-name        Name of the PM2 service to canary-deploy
  canary-percentage   Percentage of instances to canary (default: 25, unused in PM2 mode)

Options:
  --auto-promote       Automatically promote canary on health pass
  --dry-run            Simulate without actually deploying
  --force              Skip confirmation prompts
  --verbose            Enable verbose output (show curl responses)
  --help, -h           Show this help message

Examples:
  $(basename "$0") wheeler-api
  $(basename "$0") revenue-api 30 --auto-promote
  $(basename "$0") command-center 50 --dry-run --verbose

Health Comparison Criteria:
  - HTTP status codes: canary must match stable (200 OK)
  - Response time: canary must be within ${CANARY_RESPONSE_TIME_MAX_RATIO}x of stable
  - Error rate: canary error rate must be <= stable error rate
  - Memory usage: canary memory must be within ${CANARY_MEMORY_MAX_RATIO}x of stable
EOF
    exit 2
}

parse_args() {
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto-promote)
                AUTO_PROMOTE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    SERVICE_NAME="${positional[0]:-}"
    if [[ -n "${positional[1]:-}" ]]; then
        CANARY_PERCENTAGE="${positional[1]}"
    fi

    if [[ -z "$SERVICE_NAME" ]]; then
        log_error "Missing required argument: <service-name>"
        usage
    fi

    # Validate canary percentage is a number between 1-100
    if ! [[ "$CANARY_PERCENTAGE" =~ ^[0-9]+$ ]] || \
       [[ "$CANARY_PERCENTAGE" -lt 1 ]] || \
       [[ "$CANARY_PERCENTAGE" -gt 100 ]]; then
        log_error "Canary percentage must be between 1 and 100, got: ${CANARY_PERCENTAGE}"
        exit 2
    fi
}

# ─── Logging ─────────────────────────────────────────────────────────────────

canary_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local entry="${timestamp} [CANARY:${level}] [${SERVICE_NAME}] ${message}"

    echo "$entry" >> "$CANARY_LOG_FILE"

    case "$level" in
        INFO)    log_info "$message" ;;
        WARN)    log_warn "$message" ;;
        ERROR)   log_error "$message" ;;
        SUCCESS) log_success "$message" ;;
        FATAL)   log_fatal "$message" ;;
        *)       echo "$entry" >&2 ;;
    esac
}

# ─── PM2 Helpers ─────────────────────────────────────────────────────────────

check_pm2_available() {
    if ! command -v pm2 &>/dev/null; then
        canary_log "FATAL" "PM2 CLI not found. Canary deployment requires PM2."
        exit 3
    fi
    if ! pm2 ping &>/dev/null 2>&1; then
        canary_log "FATAL" "PM2 daemon is not running."
        exit 3
    fi
}

get_pm2_info() {
    local name="$1"
    pm2 jlist 2>/dev/null | jq -r ".[] | select(.name==\"${name}\")" 2>/dev/null || echo "{}"
}

get_pm2_status() {
    local name="$1"
    get_pm2_info "$name" | jq -r '.pm2_env.status // "unknown"'
}

get_pm2_port() {
    local name="$1"
    # Try to get port from PM2 env
    local port
    port=$(get_pm2_info "$name" | jq -r '.pm2_env.PORT // .pm2_env.port // ""' 2>/dev/null)
    if [[ -z "$port" ]] || [[ "$port" == "null" ]]; then
        # Fallback: check service catalog
        if [[ "${HAS_COMMON_SH}" == "true" ]]; then
            port=$(get_service_port "$name" 2>/dev/null || echo "")
        fi
    fi
    echo "${port:-0}"
}

get_pm2_pid() {
    local name="$1"
    get_pm2_info "$name" | jq -r '.pid // 0'
}

get_pm2_memory() {
    local name="$1"
    get_pm2_info "$name" | jq -r '.monit.memory // 0'
}

get_pm2_cpu() {
    local name="$1"
    get_pm2_info "$name" | jq -r '.monit.cpu // 0'
}

get_pm2_restarts() {
    local name="$1"
    get_pm2_info "$name" | jq -r '.pm2_env.restart_time // 0'
}

# ─── HTTP Health Check ───────────────────────────────────────────────────────

# Perform a single HTTP health check and return timing + status code
# Output: "http_code=<code> time_total=<seconds>"
check_http_with_timing() {
    local url="$1"
    local timeout="${2:-${CANARY_CURL_MAX_TIME}}"
    local connect_timeout="${3:-${CANARY_CURL_CONNECT_TIMEOUT}}"

    local curl_output
    curl_output=$(curl -s -o /dev/null -w "http_code=%{http_code} time_total=%{time_total}" \
        --max-time "$timeout" \
        --connect-timeout "$connect_timeout" \
        "$url" 2>/dev/null) || {
        echo "http_code=000 time_total=0"
        return 1
    }

    echo "$curl_output"
    return 0
}

# Perform verbose health check (show response body)
check_http_verbose() {
    local url="$1"
    local timeout="${2:-${CANARY_CURL_MAX_TIME}}"

    curl -s -w "\n---\nhttp_code=%{http_code}\ntime_total=%{time_total}\n" \
        --max-time "$timeout" \
        --connect-timeout "${CANARY_CURL_CONNECT_TIMEOUT}" \
        "$url" 2>/dev/null
}

# ─── Health Scoring ──────────────────────────────────────────────────────────

# Compute a health score (0.0 – 1.0) for the canary vs stable comparison
# Takes: canary_http_code stable_http_code canary_time stable_time canary_mem stable_mem canary_restarts stable_restarts
compute_health_score() {
    local c_code="$1"
    local s_code="$2"
    local c_time="$3"
    local s_time="$4"
    local c_mem="$5"
    local s_mem="$6"
    local c_restarts="$7"
    local s_restarts="$8"

    local score=0
    local checks=0

    # 1. HTTP status code check
    checks=$((checks + 1))
    if [[ "$c_code" == "200" || "$c_code" == "204" ]]; then
        score=$(echo "$score + 1" | bc -l 2>/dev/null || echo "$score")
        canary_log "INFO" "  [check $checks/5] HTTP status: PASS (canary=${c_code})"
    else
        canary_log "WARN" "  [check $checks/5] HTTP status: FAIL (canary=${c_code}, expected 200/204)"
    fi

    # 2. Response time comparison (canary must be within 20% of stable)
    checks=$((checks + 1))
    if command -v bc &>/dev/null; then
        local ratio
        if [[ "$s_time" != "0" ]] && [[ -n "$s_time" ]]; then
            ratio=$(echo "scale=4; $c_time / $s_time" | bc 2>/dev/null || echo "999")
        else
            ratio="0"
        fi

        local max_ratio="${CANARY_RESPONSE_TIME_MAX_RATIO}"
        if (( $(echo "$ratio <= $max_ratio" | bc -l 2>/dev/null || echo "0") )); then
            score=$(echo "$score + 1" | bc -l 2>/dev/null || echo "$score")
            canary_log "INFO" "  [check $checks/5] Response time: PASS (canary=${c_time}s, stable=${s_time}s, ratio=${ratio}, max=${max_ratio})"
        else
            # Partial score: the closer to threshold the better
            local partial
            partial=$(echo "scale=4; $max_ratio / $ratio" | bc -l 2>/dev/null || echo "0")
            if (( $(echo "$partial > 1" | bc -l 2>/dev/null || echo "0") )); then
                partial="1.0"
            fi
            score=$(echo "$score + $partial" | bc -l 2>/dev/null || echo "$score")
            canary_log "WARN" "  [check $checks/5] Response time: FAIL (canary=${c_time}s, stable=${s_time}s, ratio=${ratio} > max=${max_ratio}, partial=${partial})"
        fi
    else
        # No bc available — pass by default for this check
        score=$(echo "$score + 1" | bc -l 2>/dev/null || echo "$((score + 1))")
        canary_log "WARN" "  [check $checks/5] Response time: SKIP (bc not available)"
    fi

    # 3. Error rate comparison (restarts as proxy — canary must be <= stable)
    checks=$((checks + 1))
    if [[ "$c_restarts" -le "$s_restarts" ]]; then
        score=$(echo "$score + 1" | bc -l 2>/dev/null || echo "$score")
        canary_log "INFO" "  [check $checks/5] Error rate (restarts): PASS (canary=${c_restarts}, stable=${s_restarts})"
    else
        canary_log "WARN" "  [check $checks/5] Error rate (restarts): FAIL (canary=${c_restarts} > stable=${s_restarts})"
    fi

    # 4. Memory usage comparison (canary must be within 30% of stable)
    checks=$((checks + 1))
    if command -v bc &>/dev/null; then
        local mem_ratio
        if [[ "$s_mem" != "0" ]] && [[ -n "$s_mem" ]]; then
            mem_ratio=$(echo "scale=4; $c_mem / $s_mem" | bc 2>/dev/null || echo "999")
        else
            mem_ratio="0"
        fi

        local max_mem_ratio="${CANARY_MEMORY_MAX_RATIO}"
        if (( $(echo "$mem_ratio <= $max_mem_ratio" | bc -l 2>/dev/null || echo "0") )); then
            score=$(echo "$score + 1" | bc -l 2>/dev/null || echo "$score")
            canary_log "INFO" "  [check $checks/5] Memory: PASS (canary=${c_mem}MB, stable=${s_mem}MB, ratio=${mem_ratio}, max=${max_mem_ratio})"
        else
            local mem_partial
            mem_partial=$(echo "scale=4; $max_mem_ratio / $mem_ratio" | bc -l 2>/dev/null || echo "0")
            if (( $(echo "$mem_partial > 1" | bc -l 2>/dev/null || echo "0") )); then
                mem_partial="1.0"
            fi
            score=$(echo "$score + $mem_partial" | bc -l 2>/dev/null || echo "$score")
            canary_log "WARN" "  [check $checks/5] Memory: FAIL (canary=${c_mem}MB, stable=${s_mem}MB, ratio=${mem_ratio} > max=${max_mem_ratio}, partial=${mem_partial})"
        fi
    else
        score=$(echo "$score + 1" | bc -l 2>/dev/null || echo "$((score + 1))")
        canary_log "WARN" "  [check $checks/5] Memory: SKIP (bc not available)"
    fi

    # 5. Process status check (must be online)
    checks=$((checks + 1))
    local canary_status
    canary_status=$(get_pm2_status "${SERVICE_NAME}${CANARY_NAME_SUFFIX}")
    if [[ "$canary_status" == "online" ]]; then
        score=$(echo "$score + 1" | bc -l 2>/dev/null || echo "$score")
        canary_log "INFO" "  [check $checks/5] Process status: PASS (${canary_status})"
    else
        canary_log "WARN" "  [check $checks/5] Process status: FAIL (${canary_status})"
    fi

    # Normalize to 0-1 range
    local final
    final=$(echo "scale=4; $score / $checks" | bc -l 2>/dev/null || echo "0")
    echo "$final"
}

# ─── Canary Instance Management ──────────────────────────────────────────────

clone_canary_instance() {
    local svc="$1"

    log_section "Cloning Canary Instance: ${svc} -> ${svc}${CANARY_NAME_SUFFIX}"

    # Check stable process exists
    local stable_info
    stable_info=$(get_pm2_info "$svc")
    if [[ "$stable_info" == "{}" ]] || [[ -z "$stable_info" ]]; then
        canary_log "FATAL" "Service '${svc}' not found in PM2 process list."
        exit 4
    fi

    local stable_status
    stable_status=$(echo "$stable_info" | jq -r '.pm2_env.status // "unknown"')
    canary_log "INFO" "Stable process status: ${stable_status}"

    local canary_name="${svc}${CANARY_NAME_SUFFIX}"

    # Check if canary already exists and clean it up
    if pm2 list 2>/dev/null | grep -q "$canary_name"; then
        canary_log "WARN" "Existing canary instance found: ${canary_name}. Deleting..."
        if [[ "$DRY_RUN" == "false" ]]; then
            pm2 delete "$canary_name" 2>/dev/null || true
            sleep 2
        fi
    fi

    # Get the script path from stable process
    local script_path
    script_path=$(echo "$stable_info" | jq -r '.pm2_env.pm_exec_path // ""')

    if [[ -z "$script_path" ]] || [[ "$script_path" == "null" ]]; then
        canary_log "FATAL" "Cannot determine script path for stable process '${svc}'."
        exit 4
    fi

    canary_log "INFO" "Stable process script: ${script_path}"

    # Get the args from stable process
    local args
    args=$(echo "$stable_info" | jq -r '.pm2_env.args // [] | if type=="array" then join(" ") else . end' 2>/dev/null || echo "")

    # Get the cwd from stable process
    local cwd
    cwd=$(echo "$stable_info" | jq -r '.pm2_env.pm_cwd // ""')

    # Get the interpreter (node, python, etc.)
    local interpreter
    interpreter=$(echo "$stable_info" | jq -r '.pm2_env.exec_interpreter // ""')

    # Get instances count for percentage calculation
    local instances
    instances=$(echo "$stable_info" | jq -r '.pm2_env.instances // 1')

    canary_log "INFO" "Stable process config — script=${script_path}, cwd=${cwd}, instances=${instances}"

    if [[ "$DRY_RUN" == "true" ]]; then
        canary_log "INFO" "[DRY-RUN] Would clone ${svc} as ${canary_name} with same config"
        return 0
    fi

    # Start the canary instance
    # We use the same script path and working directory but with a different name
    # and a port offset to avoid conflicts
    local stable_port
    local canary_port=""
    stable_port=$(get_pm2_port "$svc")
    if [[ -n "$stable_port" ]] && [[ "$stable_port" != "0" ]] && [[ "$stable_port" != "null" ]]; then
        canary_port=$((stable_port + CANARY_PORT_OFFSET))
        canary_log "INFO" "Canary port mapping: ${stable_port} -> ${canary_port} (offset: ${CANARY_PORT_OFFSET})"
    fi

    # Start canary with the same interpreter, script, and working directory.
    # Use env prefix (not PM2 --env) to pass PORT to the process.
    canary_log "INFO" "Starting canary instance: ${canary_name} (cwd=${cwd})"

    if [[ -n "$interpreter" ]] && [[ "$interpreter" != "null" ]]; then
        env PORT="${canary_port}" pm2 start "$script_path" \
            --name "$canary_name" \
            --cwd "$cwd" \
            --interpreter "$interpreter" \
            2>&1 || {
            canary_log "FATAL" "Failed to start canary instance: ${canary_name}"
            return 1
        }
    else
        env PORT="${canary_port}" pm2 start "$script_path" \
            --name "$canary_name" \
            --cwd "$cwd" \
            2>&1 || {
            canary_log "FATAL" "Failed to start canary instance: ${canary_name}"
            return 1
        }
    fi

    sleep 3

    # Verify canary started
    local canary_status
    canary_status=$(get_pm2_status "$canary_name")
    canary_log "INFO" "Canary instance status: ${canary_status}"

    if [[ "$canary_status" != "online" ]]; then
        canary_log "ERROR" "Canary instance did not come online (status: ${canary_status})"
        return 1
    fi

    canary_log "SUCCESS" "Canary instance cloned: ${canary_name}"
    return 0
}

# ─── Health Check Execution ──────────────────────────────────────────────────

run_canary_health_checks() {
    local svc="$1"

    log_section "Canary Health Checks: ${svc}${CANARY_NAME_SUFFIX}"

    local canary_name="${svc}${CANARY_NAME_SUFFIX}"
    local stable_port
    stable_port=$(get_pm2_port "$svc")
    local canary_port=$((stable_port + CANARY_PORT_OFFSET))

    # Determine health endpoint
    local health_endpoint="${CANARY_HEALTH_ENDPOINT}"
    if [[ "${HAS_COMMON_SH}" == "true" ]]; then
        local svc_health
        svc_health=$(get_health_endpoint "$svc" 2>/dev/null || echo "")
        if [[ -n "$svc_health" ]]; then
            health_endpoint="$svc_health"
        fi
    fi

    local stable_url="http://127.0.0.1:${stable_port}${health_endpoint}"
    local canary_url="http://127.0.0.1:${canary_port}${health_endpoint}"

    canary_log "INFO" "Stable URL:  ${stable_url}"
    canary_log "INFO" "Canary URL:  ${canary_url}"
    canary_log "INFO" "Health retries: ${CANARY_HEALTH_RETRIES}, Interval: ${CANARY_HEALTH_INTERVAL}s, Warmup: ${CANARY_WARMUP_SECONDS}s"

    # Warmup period
    canary_log "INFO" "Waiting ${CANARY_WARMUP_SECONDS}s for canary warmup..."
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep "$CANARY_WARMUP_SECONDS"
    fi

    local health_scores=()
    local all_passed=true

    for (( attempt=1; attempt<=CANARY_HEALTH_RETRIES; attempt++ )); do
        log_info "Health check attempt ${attempt}/${CANARY_HEALTH_RETRIES}"

        if [[ "$DRY_RUN" == "true" ]]; then
            canary_log "INFO" "[DRY-RUN] Would run health check ${attempt}/${CANARY_HEALTH_RETRIES}"
            health_scores+=("1.0")
            continue
        fi

        # Check stable process
        local stable_result
        stable_result=$(check_http_with_timing "$stable_url" || echo "http_code=000 time_total=0")
        local s_code s_time
        s_code=$(echo "$stable_result" | grep -oP 'http_code=\K[0-9]+' || echo "000")
        s_time=$(echo "$stable_result" | grep -oP 'time_total=\K[0-9.]+' || echo "0")

        # Check canary process
        local canary_result
        canary_result=$(check_http_with_timing "$canary_url" || echo "http_code=000 time_total=0")
        local c_code c_time
        c_code=$(echo "$canary_result" | grep -oP 'http_code=\K[0-9]+' || echo "000")
        c_time=$(echo "$canary_result" | grep -oP 'time_total=\K[0-9.]+' || echo "0")

        # Get memory and restart stats
        local c_mem s_mem c_restarts s_restarts
        c_mem=$(get_pm2_memory "$canary_name")
        s_mem=$(get_pm2_memory "$svc")
        c_restarts=$(get_pm2_restarts "$canary_name")
        s_restarts=$(get_pm2_restarts "$svc")

        canary_log "INFO" "Attempt ${attempt}: stable(${s_code}, ${s_time}s, ${s_mem}MB, ${s_restarts}r) canary(${c_code}, ${c_time}s, ${c_mem}MB, ${c_restarts}r)"

        # Verbose output
        if [[ "$VERBOSE" == "true" ]]; then
            log_info "Stable response:"
            check_http_verbose "$stable_url" || true
            log_info "Canary response:"
            check_http_verbose "$canary_url" || true
        fi

        # Compute health score
        local score
        score=$(compute_health_score "$c_code" "$s_code" "$c_time" "$s_time" "$c_mem" "$s_mem" "$c_restarts" "$s_restarts")
        health_scores+=("$score")

        canary_log "INFO" "Attempt ${attempt} health score: ${score} (threshold: ${CANARY_PROMOTE_THRESHOLD})"

        # Check if this attempt passed
        if (( $(echo "$score < $CANARY_PROMOTE_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
            all_passed=false
        fi

        # Wait before next check (unless it's the last one)
        if [[ "$attempt" -lt "$CANARY_HEALTH_RETRIES" ]]; then
            sleep "$CANARY_HEALTH_INTERVAL"
        fi
    done

    # Compute average health score
    local total=0
    local count=${#health_scores[@]}
    for s in "${health_scores[@]}"; do
        total=$(echo "$total + $s" | bc -l 2>/dev/null || echo "$total")
    done
    local avg_score
    avg_score=$(echo "scale=4; $total / $count" | bc -l 2>/dev/null || echo "0")

    canary_log "INFO" "Average health score across ${count} checks: ${avg_score}"

    # Write state file
    local state_file="${CANARY_STATE_DIR}/${svc}-canary-state.json"
    cat > "$state_file" <<STATE_EOF
{
  "service": "${svc}",
  "canary_name": "${canary_name}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "health_scores": [$(IFS=,; echo "${health_scores[*]}")],
  "average_score": ${avg_score},
  "threshold": ${CANARY_PROMOTE_THRESHOLD},
  "all_passed": ${all_passed},
  "verdict": "$([[ "$all_passed" == "true" ]] && echo "pass" || echo "fail")"
}
STATE_EOF
    canary_log "INFO" "State file written: ${state_file}"

    if [[ "$all_passed" == "true" ]]; then
        canary_log "SUCCESS" "Canary health checks PASSED (avg score: ${avg_score}, threshold: ${CANARY_PROMOTE_THRESHOLD})"
        return 0
    else
        canary_log "ERROR" "Canary health checks FAILED (avg score: ${avg_score}, threshold: ${CANARY_PROMOTE_THRESHOLD})"
        return 1
    fi
}

# ─── Promotion ───────────────────────────────────────────────────────────────

promote_canary() {
    local svc="$1"

    log_section "Promoting Canary: ${svc}${CANARY_NAME_SUFFIX}"

    local canary_name="${svc}${CANARY_NAME_SUFFIX}"

    if [[ "$DRY_RUN" == "true" ]]; then
        canary_log "INFO" "[DRY-RUN] Would promote canary ${canary_name} to replace ${svc}"
        return 0
    fi

    # Promotion strategy for PM2:
    # 1. Stop the stable process
    # 2. Rename canary to stable name
    # 3. (Optional) Scale to match original instance count
    canary_log "INFO" "Stopping stable process: ${svc}"
    pm2 stop "$svc" 2>/dev/null || {
        canary_log "WARN" "Failed to stop stable process gracefully, forcing..."
        pm2 delete "$svc" 2>/dev/null || true
    }
    sleep 2

    canary_log "INFO" "Promoting canary: ${canary_name} -> ${svc}"
    pm2 restart "$canary_name" --name "$svc" 2>/dev/null || {
        # If restart with rename fails, try delete + start
        canary_log "WARN" "Restart with rename failed. Trying delete + start approach..."
        local script_path
        script_path=$(get_pm2_info "$canary_name" | jq -r '.pm2_env.pm_exec_path // ""')
        pm2 delete "$canary_name" 2>/dev/null || true
        pm2 start "$script_path" --name "$svc" 2>/dev/null || {
            canary_log "FATAL" "Failed to promote canary!"
            return 1
        }
    }

    sleep 3

    # Verify promoted process is online
    local promoted_status
    promoted_status=$(get_pm2_status "$svc")
    if [[ "$promoted_status" == "online" ]]; then
        canary_log "SUCCESS" "Canary promoted successfully. Service ${svc} is online."
        pm2 save 2>/dev/null || true
        canary_log "INFO" "PM2 state saved."
    else
        canary_log "FATAL" "Canary promotion failed — ${svc} status: ${promoted_status}"
        return 1
    fi

    # Clean up canary state file
    rm -f "${CANARY_STATE_DIR}/${svc}-canary-state.json"

    return 0
}

# ─── Rollback ────────────────────────────────────────────────────────────────

rollback_canary() {
    local svc="$1"
    local reason="${2:-health check failure}"

    log_section "Rolling Back Canary: ${svc}${CANARY_NAME_SUFFIX}"

    local canary_name="${svc}${CANARY_NAME_SUFFIX}"

    canary_log "WARN" "Rollback reason: ${reason}"

    if [[ "$DRY_RUN" == "true" ]]; then
        canary_log "INFO" "[DRY-RUN] Would delete canary instance ${canary_name}"
        return 0
    fi

    # Get canary info for logging
    local canary_info
    canary_info=$(get_pm2_info "$canary_name")
    canary_log "INFO" "Canary process details: $(echo "$canary_info" | jq -c '{name: .name, status: .pm2_env.status, pid: .pid, restarts: .pm2_env.restart_time, memory: .monit.memory, cpu: .monit.cpu}' 2>/dev/null || echo '{}')"

    # Delete the canary instance
    if pm2 delete "$canary_name" 2>/dev/null; then
        canary_log "SUCCESS" "Canary instance deleted: ${canary_name}"
    else
        canary_log "ERROR" "Failed to delete canary instance: ${canary_name}"
        # Force kill by PID as fallback
        local canary_pid
        canary_pid=$(get_pm2_pid "$canary_name")
        if [[ -n "$canary_pid" ]] && [[ "$canary_pid" != "0" ]]; then
            canary_log "WARN" "Force killing canary PID: ${canary_pid}"
            kill -9 "$canary_pid" 2>/dev/null || true
        fi
    fi

    # Verify stable process is still healthy
    local stable_status
    stable_status=$(get_pm2_status "$svc")
    if [[ "$stable_status" == "online" ]]; then
        canary_log "SUCCESS" "Stable process ${svc} is still online — no impact from canary rollback."
    else
        canary_log "ERROR" "Stable process ${svc} status: ${stable_status} — may have been affected!"
        log_fatal "MANUAL INTERVENTION MAY BE REQUIRED for ${svc}"
    fi

    # Write failure state
    local state_file="${CANARY_STATE_DIR}/${svc}-canary-state.json"
    cat > "$state_file" <<STATE_EOF
{
  "service": "${svc}",
  "canary_name": "${canary_name}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "rolled_back",
  "reason": "${reason}",
  "stable_status": "${stable_status}"
}
STATE_EOF

    canary_log "INFO" "Rollback state written: ${state_file}"
    return 0
}

# ─── Notification ────────────────────────────────────────────────────────────

notify_canary_result() {
    local svc="$1"
    local result="$2"
    local score="${3:-0}"

    if [[ -z "${CANARY_WEBHOOK_URL:-}" ]]; then
        return 0
    fi

    local color
    case "$result" in
        passed)  color="36A64F" ;;
        failed)  color="FF0000" ;;
        promoted) color="36A64F" ;;
        *)       color="FFAA00" ;;
    esac

    curl -s -X POST "${CANARY_WEBHOOK_URL}" \
        -H "Content-Type: application/json" \
        -d "{
            \"attachments\": [{
                \"color\": \"${color}\",
                \"title\": \"Canary Deployment: ${result}\",
                \"text\": \"Service: ${svc}\nScore: ${score}\nNode: $(hostname)\nTime: $(date -u +%Y-%m-%dT%H:%M:%SZ)\",
                \"fields\": [
                    {\"title\": \"Service\", \"value\": \"${svc}\", \"short\": true},
                    {\"title\": \"Result\", \"value\": \"${result}\", \"short\": true},
                    {\"title\": \"Health Score\", \"value\": \"${score}\", \"short\": true},
                    {\"title\": \"Node\", \"value\": \"$(hostname)\", \"short\": true}
                ]
            }]
        }" &>/dev/null || true
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"

    local svc="$SERVICE_NAME"
    local canary_name="${svc}${CANARY_NAME_SUFFIX}"

    log_section "Canary Deployment: ${svc}"
    log_kv "service" "$svc"
    log_kv "canary_name" "$canary_name"
    log_kv "canary_percentage" "$CANARY_PERCENTAGE"
    log_kv "auto_promote" "$AUTO_PROMOTE"
    log_kv "auto_rollback" "$CANARY_AUTO_ROLLBACK"
    log_kv "dry_run" "$DRY_RUN"
    log_kv "warmup" "${CANARY_WARMUP_SECONDS}s"
    log_kv "health_retries" "$CANARY_HEALTH_RETRIES"
    log_kv "health_interval" "${CANARY_HEALTH_INTERVAL}s"
    log_kv "promote_threshold" "$CANARY_PROMOTE_THRESHOLD"
    log_kv "node" "$(hostname -f 2>/dev/null || hostname)"

    canary_log "INFO" "=========================================="
    canary_log "INFO" "Canary deployment started for: ${svc}"
    canary_log "INFO" "=========================================="

    # Preflight: PM2 availability
    check_pm2_available

    # Validate service exists
    if ! pm2 list 2>/dev/null | grep -q "$svc"; then
        canary_log "FATAL" "Service '${svc}' not found in PM2. Cannot canary deploy."
        canary_log "INFO" "Available PM2 processes:"
        pm2 jlist 2>/dev/null | jq -r '.[].name' | while read -r p; do
            echo "  - $p" >&2
        done
        exit 4
    fi

    # ─── Phase 1: Clone canary instance ─────────────────────────────────────
    if ! clone_canary_instance "$svc"; then
        canary_log "FATAL" "Failed to clone canary instance."
        if [[ "$DRY_RUN" == "true" ]]; then
            exit 6
        fi
        exit 1
    fi

    # ─── Phase 2: Health checks ─────────────────────────────────────────────
    local health_result=0
    run_canary_health_checks "$svc" || health_result=$?

    # ─── Phase 3: Promote or rollback ────────────────────────────────────────
    if [[ "$health_result" -eq 0 ]]; then
        canary_log "SUCCESS" "Canary health checks PASSED!"

        if [[ "$AUTO_PROMOTE" == "true" ]]; then
            if promote_canary "$svc"; then
                canary_log "SUCCESS" "Canary promoted to full deployment."
                notify_canary_result "$svc" "promoted" "1.0"
                exit 0
            else
                canary_log "FATAL" "Canary promotion failed!"
                exit 1
            fi
        else
            canary_log "SUCCESS" "Canary is healthy but auto-promote is disabled."
            canary_log "SUCCESS" "To promote: $(basename "$0") ${svc} --auto-promote"
            canary_log "SUCCESS" "Or manually: pm2 restart ${canary_name} --name ${svc}"
            notify_canary_result "$svc" "passed" "1.0"
            exit 0
        fi
    else
        canary_log "ERROR" "Canary health checks FAILED!"

        if [[ "$CANARY_AUTO_ROLLBACK" == "true" ]]; then
            rollback_canary "$svc" "health check failure"
            notify_canary_result "$svc" "failed" "0.0"
            canary_log "INFO" "Canary deployment complete — rolled back. Stable process unaffected."
            exit 1
        else
            canary_log "WARN" "Auto-rollback disabled. Canary instance ${canary_name} is still running."
            canary_log "WARN" "Manual cleanup: pm2 delete ${canary_name}"
            notify_canary_result "$svc" "failed" "0.0"
            exit 1
        fi
    fi
}

# ─── Entry Point ─────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
