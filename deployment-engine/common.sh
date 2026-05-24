#!/usr/bin/env bash
# =============================================================================
# Wheeler Deployment Engine — Shared Utilities
# =============================================================================
# This file is sourced by all deployment-engine scripts.
# Provides logging, validation, backup, and health-check utilities.
#
# Usage: source "$(dirname "$0")/common.sh"
# =============================================================================

set -euo pipefail

# ─── Script Identification ───────────────────────────────────────────────────
readonly COMMON_SH_VERSION="1.0.0"
readonly COMMON_SH_LOADED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Prevent double-sourcing
if [[ -n "${_COMMON_SH_SOURCED:-}" ]]; then
    return 0
fi
readonly _COMMON_SH_SOURCED=1

# ─── Paths & Constants ──────────────────────────────────────────────────────

# Base directory for Wheeler install
readonly WHEELER_BASE="${WHEELER_BASE:-/opt/wheeler}"

# Deployment log file (configurable via env)
readonly DEPLOY_LOG_DIR="${DEPLOY_LOG_DIR:-/var/log/wheeler}"
readonly DEPLOY_LOG_FILE="${DEPLOY_LOG_DIR}/deploy.log"

# Backup directory
readonly BACKUP_BASE="${BACKUP_BASE:-${WHEELER_BASE}/backups}"

# Config directory
readonly CONFIG_BASE="${CONFIG_BASE:-${WHEELER_BASE}/configs}"

# Timeout defaults
readonly DEFAULT_HEALTH_TIMEOUT="${DEFAULT_HEALTH_TIMEOUT:-60}"
readonly DEFAULT_HEALTH_INTERVAL="${DEFAULT_HEALTH_INTERVAL:-3}"
readonly DEFAULT_STARTUP_GRACE="${DEFAULT_STARTUP_GRACE:-10}"

# ─── Color Output Configuration ─────────────────────────────────────────────

# Check if we should use colors (auto-detect terminal, but allow override)
if [[ -t 1 ]] || [[ -n "${FORCE_COLOR:-}" ]]; then
    readonly _C_RESET='\033[0m'
    readonly _C_BOLD='\033[1m'
    readonly _C_DIM='\033[2m'
    readonly _C_RED='\033[31m'
    readonly _C_GREEN='\033[32m'
    readonly _C_YELLOW='\033[33m'
    readonly _C_BLUE='\033[34m'
    readonly _C_MAGENTA='\033[35m'
    readonly _C_CYAN='\033[36m'
    readonly _C_WHITE='\033[37m'
else
    readonly _C_RESET=''
    readonly _C_BOLD=''
    readonly _C_DIM=''
    readonly _C_RED=''
    readonly _C_GREEN=''
    readonly _C_YELLOW=''
    readonly _C_BLUE=''
    readonly _C_MAGENTA=''
    readonly _C_CYAN=''
    readonly _C_WHITE=''
fi

# ─── Logging Functions ──────────────────────────────────────────────────────

# Ensure log directory exists (lazy init on first log call)
_init_log_dir() {
    if [[ ! -d "$DEPLOY_LOG_DIR" ]]; then
        mkdir -p "$DEPLOY_LOG_DIR" 2>/dev/null || true
    fi
}

# Core logging function
# Usage: _log <level> <message> [color_code]
_log() {
    local level="$1"
    local message="$2"
    local color="${3:-}"
    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Build formatted message
    local formatted="${timestamp} [${level}] ${message}"

    # Write to stdout with optional color
    echo -e "${color:-}${formatted}${_C_RESET}" >&2

    # Also append to deploy log file
    _init_log_dir
    echo "$formatted" >> "$DEPLOY_LOG_FILE" 2>/dev/null || true
}

log_info()    { _log "INFO"    "$1" "${_C_GREEN}"; }
log_warn()    { _log "WARN"    "$1" "${_C_YELLOW}"; }
log_error()   { _log "ERROR"   "$1" "${_C_RED}"; }
log_debug()   { _log "DEBUG"   "$1" "${_C_DIM}"; }
log_success() { _log "SUCCESS" "$1" "${_C_GREEN}${_C_BOLD}"; }
log_fatal()   { _log "FATAL"   "$1" "${_C_RED}${_C_BOLD}"; }

# Log a section header
log_section() {
    local title="$1"
    local line
    line="$(printf '─%.0s' {1..60})"
    echo -e "${_C_CYAN}${_C_BOLD}${line}${_C_RESET}" >&2
    echo -e "${_C_CYAN}${_C_BOLD}  ${title}${_C_RESET}" >&2
    echo -e "${_C_CYAN}${_C_BOLD}${line}${_C_RESET}" >&2
    _init_log_dir
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [SECTION] ${title}" >> "$DEPLOY_LOG_FILE" 2>/dev/null || true
}

# Log a key=value pair (for structured logging)
log_kv() {
    local key="$1"
    local value="$2"
    _log "CONFIG" "${key}=${value}" "${_C_BLUE}"
}

# ─── Error Handling ──────────────────────────────────────────────────────────

# Trap handler for ERR signal
_on_error() {
    local exit_code=$?
    local line_no=$1
    log_error "Command failed at line ${line_no} (exit code: ${exit_code})"
    log_error "Working directory: $(pwd)"
    log_error "Script: ${0}"
}

# Enable error tracing (call at start of each script)
enable_error_tracing() {
    set -o errtrace
    trap '_on_error ${LINENO}' ERR
}

# ─── Signal Handling ─────────────────────────────────────────────────────────

# Array to hold cleanup functions
declare -a _CLEANUP_HOOKS=()

# Register a cleanup function to run on exit or signal
# Usage: register_cleanup "my_cleanup_function"
register_cleanup() {
    _CLEANUP_HOOKS+=("$1")
}

# Run all registered cleanup hooks
_run_cleanup_hooks() {
    log_info "Running cleanup hooks..."
    for hook in "${_CLEANUP_HOOKS[@]}"; do
        if declare -f "$hook" &>/dev/null; then
            log_debug "Running cleanup: ${hook}"
            "$hook" || log_warn "Cleanup hook '${hook}' returned non-zero"
        fi
    done
}

# Signal handler for SIGINT, SIGTERM
_on_signal() {
    local signal="$1"
    log_warn "Received signal: ${signal} — initiating graceful shutdown"
    _run_cleanup_hooks
    log_info "Exiting due to signal: ${signal}"
    exit 130
}

# Enable signal handling (call at start of each script)
enable_signal_handlers() {
    trap '_on_signal SIGINT' SIGINT
    trap '_on_signal SIGTERM' SIGTERM
    trap '_run_cleanup_hooks' EXIT
}

# ─── Argument Validation ─────────────────────────────────────────────────────

# Print usage for a script, then exit
# Usage: usage "<usage_string>" "<description>"
usage() {
    local usage_str="$1"
    local description="${2:-}"
    echo ""
    echo -e "${_C_BOLD}Usage:${_C_RESET} ${usage_str}" >&2
    if [[ -n "$description" ]]; then
        echo "" >&2
        echo -e "${_C_DIM}${description}${_C_RESET}" >&2
    fi
    exit 1
}

# Validate that a required argument is non-empty
# Usage: require_arg "<arg_value>" "<arg_name>"
require_arg() {
    local value="$1"
    local name="$2"
    if [[ -z "$value" ]]; then
        log_error "Missing required argument: ${name}"
        return 1
    fi
}

# Validate service name format (letters, numbers, hyphens only)
# Usage: validate_service_name "<name>"
validate_service_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
        log_error "Invalid service name: '${name}'. Must start with a letter and contain only letters, numbers, and hyphens."
        return 1
    fi
    if [[ ${#name} -gt 64 ]]; then
        log_error "Service name too long: ${#name} characters (max 64)"
        return 1
    fi
}

# Validate environment name
# Usage: validate_environment "<env>"
validate_environment() {
    local env="$1"
    case "$env" in
        production|staging|dev|ci|e2e)
            return 0
            ;;
        *)
            log_error "Invalid environment: '${env}'. Must be one of: production, staging, dev, ci, e2e"
            return 1
            ;;
    esac
}

# Validate version string (semver or git SHA)
# Usage: validate_version "<version>"
validate_version() {
    local version="$1"
    # Accept semver (1.2.3) or git SHA (7-40 hex chars) or 'latest'
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
       [[ "$version" =~ ^[a-f0-9]{7,40}$ ]] || \
       [[ "$version" == "latest" ]]; then
        return 0
    fi
    log_error "Invalid version: '${version}'. Expected semver (1.2.3), git SHA, or 'latest'."
    return 1
}

# ─── Required Variables Check ────────────────────────────────────────────────

# Check that required environment variables are set
# Usage: check_required_vars "VAR1" "VAR2" "VAR3"
check_required_vars() {
    local missing=()
    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing[*]}"
        log_error "Please set these variables before running this script."
        return 1
    fi
    log_debug "All required vars present: $*"
    return 0
}

# Check that required commands are available
# Usage: check_required_cmds "curl" "jq" "docker"
check_required_cmds() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        log_error "Please install them before running this script."
        return 1
    fi
    log_debug "All required commands available: $*"
    return 0
}

# ─── Backup Functions ────────────────────────────────────────────────────────

# Backup configuration files before deployment
# Usage: backup_configs "<service_name>" "<environment>"
backup_configs() {
    local service_name="$1"
    local environment="$2"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="${BACKUP_BASE}/${timestamp}_${service_name}_predeploy"

    log_section "Pre-Deploy Backup: ${service_name} (${environment})"

    mkdir -p "$backup_dir"

    local backup_count=0

    # 1. Backup application configs (if they exist)
    local config_src="${WHEELER_BASE}/${service_name}"
    if [[ -d "$config_src" ]]; then
        log_info "Backing up: ${config_src}"

        # Backup .env files (excluding secrets if possible)
        if [[ -f "${config_src}/.env" ]]; then
            cp -a "${config_src}/.env" "${backup_dir}/dotenv.backup"
            backup_count=$((backup_count + 1))
        fi
        if [[ -f "${config_src}/.env.${environment}" ]]; then
            cp -a "${config_src}/.env.${environment}" "${backup_dir}/dotenv_${environment}.backup"
            backup_count=$((backup_count + 1))
        fi

        # Backup ecosystem config
        if [[ -f "${config_src}/ecosystem.config.js" ]]; then
            cp -a "${config_src}/ecosystem.config.js" "${backup_dir}/ecosystem.config.js.backup"
            backup_count=$((backup_count + 1))
        fi

        # Backup docker-compose
        if [[ -f "${config_src}/docker-compose.yml" ]]; then
            cp -a "${config_src}/docker-compose.yml" "${backup_dir}/docker-compose.yml.backup"
            backup_count=$((backup_count + 1))
        fi

        # Backup custom configs directory
        if [[ -d "${config_src}/configs" ]]; then
            cp -a "${config_src}/configs" "${backup_dir}/configs"
            backup_count=$((backup_count + 1))
        fi
    fi

    # 2. Backup PM2 state (if PM2 is available)
    if command -v pm2 &>/dev/null; then
        log_info "Backing up PM2 process list..."
        pm2 save 2>/dev/null || log_warn "pm2 save failed (may not be running)"
        if [[ -f "${HOME}/.pm2/dump.pm2" ]]; then
            cp -a "${HOME}/.pm2/dump.pm2" "${backup_dir}/pm2_dump.pm2"
            backup_count=$((backup_count + 1))
        fi
    fi

    # 3. Backup Docker volumes (if Docker is available)
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        local docker_volumes
        docker_volumes=$(docker volume ls -q --filter "name=${service_name}" 2>/dev/null || true)
        for vol in $docker_volumes; do
            log_info "Backing up Docker volume: ${vol}"
            docker run --rm -v "${vol}:/volume_data" -v "${backup_dir}:/backup" \
                alpine tar czf "/backup/volume_${vol}.tar.gz" -C /volume_data . 2>/dev/null || \
                log_warn "Failed to backup Docker volume: ${vol}"
            backup_count=$((backup_count + 1))
        done
    fi

    # 4. Create checksums
    if [[ "$backup_count" -gt 0 ]]; then
        (cd "$backup_dir" && sha256sum -- * > checksums.sha256 2>/dev/null) || true
        log_success "Backup completed: ${backup_dir} (${backup_count} items)"
    else
        log_warn "No configs found to backup for service: ${service_name}"
    fi

    # 5. Write backup manifest
    cat > "${backup_dir}/MANIFEST.txt" <<EOF
Backup Manifest
===============
Service:     ${service_name}
Environment: ${environment}
Timestamp:   ${timestamp}
Node:        $(hostname -f 2>/dev/null || hostname)
Backup Dir:  ${backup_dir}
Item Count:  ${backup_count}
EOF

    # Store backup path for later reference
    echo "$backup_dir" > /tmp/wheeler_last_backup_path

    return 0
}

# ─── Service Info Functions ──────────────────────────────────────────────────

# Get service info from the service catalog
# Usage: get_service_info "<service_name>" "<field>"
# Fields: type, runtime, port, health_endpoint, node, dependencies
get_service_info() {
    local service_name="$1"
    local field="${2:-type}"

    # Default service catalog (can be overridden by external file)
    local catalog_file="${WHEELER_BASE}/infrastructure/shared/service-catalog.json"

    if [[ -f "$catalog_file" ]]; then
        jq -r ".services[\"${service_name}\"].${field} // empty" "$catalog_file" 2>/dev/null || echo ""
    else
        # Fallback: hardcoded catalog for core services
        case "${service_name}" in
            traefik)
                case "$field" in
                    type) echo "reverse-proxy" ;;
                    runtime) echo "docker" ;;
                    port) echo "80" ;;
                    health_endpoint) echo "/ping" ;;
                    node) echo "edge" ;;
                    *) echo "" ;;
                esac
                ;;
            nginx)
                case "$field" in
                    type) echo "static-cache" ;;
                    runtime) echo "docker" ;;
                    port) echo "8080" ;;
                    health_endpoint) echo "/nginx-health" ;;
                    node) echo "edge" ;;
                    *) echo "" ;;
                esac
                ;;
            wheeler-hub|ops-dashboard|admin-panel|client-portal|status-page)
                case "$field" in
                    type) echo "frontend" ;;
                    runtime) echo "pm2" ;;
                    health_endpoint) echo "/api/health" ;;
                    node) echo "edge" ;;
                    *) echo "" ;;
                esac
                ;;
            wheeler-api)
                case "$field" in
                    type) echo "api" ;;
                    runtime) echo "pm2" ;;
                    port) echo "4000" ;;
                    health_endpoint) echo "/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            revenue-api)
                case "$field" in
                    type) echo "api" ;;
                    runtime) echo "pm2" ;;
                    port) echo "4001" ;;
                    health_endpoint) echo "/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            webhook-gateway)
                case "$field" in
                    type) echo "webhook" ;;
                    runtime) echo "pm2" ;;
                    port) echo "4002" ;;
                    health_endpoint) echo "/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            admin-api)
                case "$field" in
                    type) echo "api" ;;
                    runtime) echo "pm2" ;;
                    port) echo "4003" ;;
                    health_endpoint) echo "/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            graphql-gateway)
                case "$field" in
                    type) echo "graphql" ;;
                    runtime) echo "pm2" ;;
                    port) echo "4004" ;;
                    health_endpoint) echo "/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            litellm-proxy)
                case "$field" in
                    type) echo "llm-proxy" ;;
                    runtime) echo "pm2" ;;
                    port) echo "5000" ;;
                    health_endpoint) echo "/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            openclaw-engine)
                case "$field" in
                    type) echo "ai-engine" ;;
                    runtime) echo "pm2" ;;
                    port) echo "5001" ;;
                    health_endpoint) echo "/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            ml-workers)
                case "$field" in
                    type) echo "ml-worker" ;;
                    runtime) echo "pm2" ;;
                    port) echo "" ;;
                    health_endpoint) echo "" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            inference-api)
                case "$field" in
                    type) echo "ml-inference" ;;
                    runtime) echo "pm2" ;;
                    port) echo "5003" ;;
                    health_endpoint) echo "/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            orchestrator)
                case "$field" in
                    type) echo "orchestrator" ;;
                    runtime) echo "pm2" ;;
                    port) echo "6000" ;;
                    health_endpoint) echo "/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            autoheal-engine|alert-engine|cost-monitor|eco-health-eng)
                case "$field" in
                    type) echo "ops-service" ;;
                    runtime) echo "pm2" ;;
                    health_endpoint) echo "/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            changedetection|healthchecks)
                case "$field" in
                    type) echo "monitoring" ;;
                    runtime) echo "docker" ;;
                    health_endpoint) echo "/api/health" ;;
                    node) echo "aiops" ;;
                    *) echo "" ;;
                esac
                ;;
            postgresql)
                case "$field" in
                    type) echo "database" ;;
                    runtime) echo "systemd" ;;
                    port) echo "5432" ;;
                    node) echo "coredb" ;;
                    *) echo "" ;;
                esac
                ;;
            redis)
                case "$field" in
                    type) echo "cache" ;;
                    runtime) echo "systemd" ;;
                    port) echo "6379" ;;
                    node) echo "coredb" ;;
                    *) echo "" ;;
                esac
                ;;
            minio)
                case "$field" in
                    type) echo "object-storage" ;;
                    runtime) echo "systemd" ;;
                    port) echo "9000" ;;
                    node) echo "coredb" ;;
                    *) echo "" ;;
                esac
                ;;
            qdrant)
                case "$field" in
                    type) echo "vector-db" ;;
                    runtime) echo "docker" ;;
                    port) echo "6333" ;;
                    node) echo "coredb" ;;
                    *) echo "" ;;
                esac
                ;;
            grafana|prometheus|loki|tempo|alertmanager)
                case "$field" in
                    type) echo "observability" ;;
                    runtime) echo "docker" ;;
                    node) echo "coredb" ;;
                    *) echo "" ;;
                esac
                ;;
            *)
                echo ""
                ;;
        esac
    fi
}

# Get the port for a service
# Usage: get_service_port "<service_name>"
get_service_port() {
    get_service_info "$1" "port"
}

# Get the health endpoint for a service
# Usage: get_health_endpoint "<service_name>"
get_health_endpoint() {
    get_service_info "$1" "health_endpoint"
}

# Get the runtime type (pm2, docker, systemd)
# Usage: get_service_runtime "<service_name>"
get_service_runtime() {
    get_service_info "$1" "runtime"
}

# ─── Health Check Functions ──────────────────────────────────────────────────

# Check if a port is listening on localhost
# Usage: check_port_listening "<port>" [host]
check_port_listening() {
    local port="$1"
    local host="${2:-127.0.0.1}"

    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ":${port} " && return 0
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} " && return 0
    elif command -v lsof &>/dev/null; then
        lsof -i ":${port}" -sTCP:LISTEN &>/dev/null && return 0
    fi
    return 1
}

# Perform an HTTP health check
# Usage: check_http_health "<url>" [timeout_seconds]
check_http_health() {
    local url="$1"
    local timeout="${2:-10}"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$timeout" \
        --connect-timeout 5 \
        "${url}" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" || "$http_code" == "204" ]]; then
        return 0
    fi
    log_debug "Health check returned HTTP ${http_code} for ${url}"
    return 1
}

# Perform full health check with retries
# Usage: wait_for_health "<url>" [max_retries] [interval_seconds]
wait_for_health() {
    local url="$1"
    local max_retries="${2:-${DEFAULT_HEALTH_TIMEOUT}}"
    local interval="${3:-${DEFAULT_HEALTH_INTERVAL}}"
    local attempt=1

    log_info "Waiting for health check: ${url} (max ${max_retries}s, interval ${interval}s)"

    # Convert timeout to number of retries if given as seconds
    local retries
    retries=$((max_retries / interval))
    [[ $retries -lt 1 ]] && retries=1

    while [[ $attempt -le $retries ]]; do
        if check_http_health "$url" "$interval"; then
            log_success "Health check passed on attempt ${attempt}/${retries}"
            return 0
        fi
        log_debug "Health check attempt ${attempt}/${retries} — waiting ${interval}s..."
        sleep "$interval"
        attempt=$((attempt + 1))
    done

    log_error "Health check FAILED after ${retries} attempts (${max_retries}s timeout)"
    return 1
}

# ─── Alert Functions ─────────────────────────────────────────────────────────

# Send a health alert (logs + optional webhook)
# Usage: send_health_alert "<service_name>" "<environment>" "<status>" "<message>"
send_health_alert() {
    local service_name="$1"
    local environment="$2"
    local status="$3"
    local message="$4"
    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Always log the alert
    case "$status" in
        CRITICAL)
            log_fatal "[ALERT:${status}] ${service_name}/${environment}: ${message}"
            ;;
        WARNING)
            log_warn "[ALERT:${status}] ${service_name}/${environment}: ${message}"
            ;;
        OK)
            log_info "[ALERT:${status}] ${service_name}/${environment}: ${message}"
            ;;
        *)
            log_error "[ALERT:${status}] ${service_name}/${environment}: ${message}"
            ;;
    esac

    # Send webhook if configured
    if [[ -n "${HEALTH_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${HEALTH_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{
                \"timestamp\": \"${timestamp}\",
                \"service\": \"${service_name}\",
                \"environment\": \"${environment}\",
                \"status\": \"${status}\",
                \"message\": \"${message}\",
                \"node\": \"$(hostname -f 2>/dev/null || hostname)\"
            }" &>/dev/null || true
    fi

    # Send to Slack if configured
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        local color
        case "$status" in
            CRITICAL) color="#FF0000" ;;
            WARNING)  color="#FFAA00" ;;
            OK)       color="#36A64F" ;;
            *)        color="#CCCCCC" ;;
        esac
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d "{
                \"attachments\": [{
                    \"color\": \"${color}\",
                    \"title\": \"Deploy Alert: ${status}\",
                    \"text\": \"${message}\",
                    \"fields\": [
                        {\"title\": \"Service\", \"value\": \"${service_name}\", \"short\": true},
                        {\"title\": \"Environment\", \"value\": \"${environment}\", \"short\": true},
                        {\"title\": \"Node\", \"value\": \"$(hostname)\", \"short\": true},
                        {\"title\": \"Time\", \"value\": \"${timestamp}\", \"short\": true}
                    ]
                }]
            }" &>/dev/null || true
    fi
}

# ─── Confirmation & Safety ───────────────────────────────────────────────────

# Prompt for confirmation before destructive action
# Usage: confirm_action "<description>" || exit 1
confirm_action() {
    local description="$1"

    # Skip confirmation if --force or --yes flag is set
    if [[ -n "${FORCE_CONFIRM:-}" ]] || [[ -n "${YES:-}" ]]; then
        log_info "Confirmation bypassed (--force/--yes): ${description}"
        return 0
    fi

    echo -e "${_C_YELLOW}${_C_BOLD}WARNING:${_C_RESET} ${description}" >&2
    echo -ne "${_C_YELLOW}Are you sure you want to continue? [y/N]: ${_C_RESET}" >&2
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            log_warn "Action cancelled by user."
            return 1
            ;;
    esac
}

# ─── System Checks ───────────────────────────────────────────────────────────

# Check available disk space (warn if below threshold)
# Usage: check_disk_space "<path>" [threshold_percent]
check_disk_space() {
    local path="${1:-/opt/wheeler}"
    local threshold="${2:-10}"  # Warn if less than 10% free

    local df_output
    df_output=$(df -h "$path" 2>/dev/null | tail -1) || {
        log_warn "Could not check disk space for: ${path}"
        return 0
    }

    local used_percent
    used_percent=$(echo "$df_output" | awk '{print $5}' | tr -d '%')
    local available
    available=$(echo "$df_output" | awk '{print $4}')

    local free_percent=$((100 - used_percent))

    if [[ "$free_percent" -lt "$threshold" ]]; then
        log_warn "Low disk space on ${path}: ${available} available (${free_percent}% free, threshold ${threshold}%)"
        return 1
    fi

    log_debug "Disk space OK on ${path}: ${available} available (${free_percent}% free)"
    return 0
}

# Check Docker daemon is running
# Usage: check_docker_daemon
check_docker_daemon() {
    if ! command -v docker &>/dev/null; then
        log_warn "Docker is not installed"
        return 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        log_error "Docker daemon is not running or not accessible"
        return 1
    fi
    log_debug "Docker daemon is running"
    return 0
}

# Check PM2 daemon is running
# Usage: check_pm2_daemon
check_pm2_daemon() {
    if ! command -v pm2 &>/dev/null; then
        log_warn "PM2 is not installed"
        return 1
    fi
    if ! pm2 ping &>/dev/null 2>&1; then
        log_warn "PM2 daemon is not running or not accessible"
        return 1
    fi
    log_debug "PM2 daemon is running"
    return 0
}

# Check if a command exists
# Usage: has_command "<cmd>"
has_command() {
    command -v "$1" &>/dev/null
}

# ─── Utility Functions ───────────────────────────────────────────────────────

# Get current timestamp in ISO 8601
timestamp_iso() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# Get current timestamp for filenames
timestamp_file() {
    date +%Y%m%d_%H%M%S
}

# Generate a unique deployment ID
generate_deploy_id() {
    echo "deploy-$(date +%Y%m%d%H%M%S)-$(head -c4 /dev/urandom | xxd -p 2>/dev/null || echo '0000')"
}

# Export a deployment ID for this run
export DEPLOY_ID="${DEPLOY_ID:-$(generate_deploy_id)}"

# ─── Initialization ──────────────────────────────────────────────────────────

log_debug "common.sh v${COMMON_SH_VERSION} loaded (depoy_id: ${DEPLOY_ID})"
log_debug "Host: $(hostname -f 2>/dev/null || hostname), User: ${USER:-unknown}, PID: $$"
log_debug "Wheeler base: ${WHEELER_BASE}, Log: ${DEPLOY_LOG_FILE}"

# Return 0 on source
return 0
