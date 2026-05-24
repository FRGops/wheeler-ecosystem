#!/usr/bin/env bash
# ==============================================================================
# Wheeler Enterprise — Server Role Enforcement Script
# ==============================================================================
#
# Usage:
#   bash enforce-roles.sh [--server <edge|aiops|coredb>] [--fix] [--report] [--json]
#
# Description:
#   Validates that the current server is complying with its assigned role
#   in the three-server Wheeler architecture (EDGE, AIOPS, COREDB).
#   Checks Docker containers, port bindings, labels, volume placement, and
#   generates audit reports.
#
# Exit codes:
#   0 — All checks passed, no violations
#   1 — WARNING-level violations found
#   2 — CRITICAL-level violations found
#   3 — Script error (missing dependencies, cannot detect role, etc.)
#
# Dependencies:
#   - docker (for container inspection)
#   - ss or netstat (for port checking)
#   - jq (for JSON output, optional — falls back to grep if missing)
#   - tailscale (for IP detection)
#   - hostname (for role detection)
#
# Author: Wheeler Infrastructure Team
# Version: 1.0.0
# Last Updated: 2026-05-23
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

# ------------------------------------------------------------------------------
# Constants & Configuration
# ------------------------------------------------------------------------------

readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly HOSTNAME="$(hostname -s)"

# Log and metrics directories
readonly LOG_DIR="/var/log/wheeler"
readonly METRICS_DIR="/var/lib/node_exporter/textfile_collector"
readonly REPORT_FILE="${LOG_DIR}/role-audit.json"
readonly METRICS_FILE="${METRICS_DIR}/role-compliance.prom"
readonly LOCK_FILE="/tmp/wheeler-enforce-roles.lock"

# Tailscale subnet
readonly TS_SUBNET="100.64.0.0/10"

# Docker image name patterns (case-insensitive grep patterns)
# These are used to identify forbidden container types per role.
readonly DB_IMAGE_PATTERNS=(
    "postgres" "postgis" "pgvector" "timescaledb" "cockroachdb" "yugabyte"
    "redis" "valkey" "keydb" "dragonfly"
    "clickhouse" "clickhouse-server"
    "mongo" "mongod" "percona-server-mongodb"
    "mysql" "mariadb" "percona" "percona-server"
    "elasticsearch" "opensearch"
    "couchdb" "couchbase" "rethinkdb"
    "neo4j" "arangodb" "orientdb" "dgraph"
    "influxdb" "timescaledb"
    "sqlite" "sqlite3"
    "pgbouncer" "pgpool" "odyssey" "pgcat"
    "cassandra" "scylla"
    "meilisearch" "typesense" "algolia"
)

readonly AI_ML_IMAGE_PATTERNS=(
    "litellm" "langflow" "langchain" "langserve"
    "ollama" "vllm" "localai" "local-ai"
    "tensorflow" "tensorflow-serving"
    "pytorch" "torchserve"
    "cuda" "nvidia-cuda" "cudnn"
    "transformers" "huggingface" "text-generation-inference" "tgi"
    "onnx" "onnxruntime"
    "gguf" "ggml" "llama.cpp" "llamacpp"
    "stable-diffusion" "sd-webui" "automatic1111" "comfyui"
    "sentence-transformers" "text-embeddings-inference"
    "qdrant" "weaviate" "milvus" "chroma" "chromadb"
    "embedding" "embeddings-model"
    "open-interpreter" "aider" "gpt-pilot"
    "crewa" "crewai" "autogen"
    "whisper" "whisperx" "faster-whisper"
)

readonly APP_SERVER_IMAGE_PATTERNS=(
    "node:" "nodejs" "node.js"
    "python:" "pypy"
    "golang:" "golangci"
    "rust:" "rustlang"
    "openjdk" "amazoncorretto" "eclipse-temurin"
    "ruby:" "jruby"
    "php:" "php-fpm"
    "dotnet" "dotnet-sdk" "aspnet"
    "express" "fastify" "hono" "nitro"
    "fastapi" "flask" "django" "litestar"
    "gin-" "echo-" "fiber"
    "nginx" "nginx-fpm" "unit"
    "apache" "httpd" "caddy" "traefik"
    "haproxy" "envoy" "kong"
)

readonly CI_CD_IMAGE_PATTERNS=(
    "jenkins" "jenkins-agent"
    "github-actions" "actions-runner" "github-runner"
    "gitlab-runner" "gitlab-ci"
    "drone" "drone-runner"
    "concourse" "concourse-worker"
    "woodpecker" "woodpecker-agent"
)

readonly MONITORING_UI_IMAGE_PATTERNS=(
    "grafana" "grafana-enterprise"
    "prometheus" "prom/prometheus"
    "kibana" "kibana-oss"
    "chronograf"
)

# Port definitions by role
# EDGE: ports that are allowed open to 0.0.0.0
readonly EDGE_PUBLIC_PORTS=("22" "80" "443")
# COREDB: database ports (allowed on COREDB, should NEVER be on EDGE, should be Tailscale-only on AIOPS)
readonly DB_PORTS=("5432" "6379" "6432" "9000" "6333" "6334" "8123" "9000" "9001" "9187" "9121")

# ------------------------------------------------------------------------------
# Color Output (auto-detects TTY)
# ------------------------------------------------------------------------------

if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly YELLOW='\033[1;33m'
    readonly GREEN='\033[0;32m'
    readonly CYAN='\033[0;36m'
    readonly MAGENTA='\033[0;35m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly YELLOW=''
    readonly GREEN=''
    readonly CYAN=''
    readonly MAGENTA=''
    readonly BOLD=''
    readonly NC=''
fi

# ------------------------------------------------------------------------------
# Global State
# ------------------------------------------------------------------------------

# Detected or specified server role
DETECTED_ROLE=""

# Arrays for collecting violations
declare -a CRITICAL_VIOLATIONS=()
declare -a WARNING_VIOLATIONS=()
declare -a INFO_ITEMS=()

# Container tracking
declare -A CONTAINER_STATUS=()   # key=container_name, value=status (ok|critical|warning|info)
declare -A CONTAINER_VIOLATIONS=() # key=container_name, value=violation description
declare -A CONTAINER_IMAGE=()    # key=container_name, value=image name
declare -A CONTAINER_LABEL_ROLE=() # key=container_name, value=com.wheeler.role label or "unlabeled"

# Port tracking
declare -a OPEN_PORT_RECORDS=()

# Fix suggestions (only populated with --fix)
declare -a FIX_COMMANDS=()

# JSON report data (built incrementally if --report)
JSON_REPORT=""

# ------------------------------------------------------------------------------
# Usage & Help
# ------------------------------------------------------------------------------

usage() {
    cat <<EOF
${BOLD}Wheeler Enterprise — Server Role Enforcement${NC}

Usage: ${SCRIPT_NAME} [OPTIONS]

${BOLD}Options:${NC}
  --server <edge|aiops|coredb>  Force a specific server role (skip auto-detection)
  --fix                         Generate fix commands for violations (DOES NOT execute)
  --report                      Generate detailed compliance report (terminal + JSON)
  --json                        Output JSON report to stdout (implies --report)
  --quiet                       Suppress non-error output (exit code only)
  --no-lock                     Skip lock file check (use when lock file is stale)
  -h, --help                    Show this help message

${BOLD}Exit Codes:${NC}
  0  All clear — no violations
  1  WARNING-level violations found
  2  CRITICAL-level violations found
  3  Script error (missing dependencies, can't detect role)

${BOLD}Examples:${NC}
  ${SCRIPT_NAME}                                    # Detect role, run all checks
  ${SCRIPT_NAME} --server coredb                    # Force COREDB role checks
  ${SCRIPT_NAME} --report                           # Full audit with report
  ${SCRIPT_NAME} --server edge --fix --report       # EDGE role check with fix suggestions

${BOLD}Documentation:${NC}
  Policy: server-role-policies.md (same directory as this script)
EOF
}

# ------------------------------------------------------------------------------
# Logging Functions
# ------------------------------------------------------------------------------

log_info() {
    echo -e "${GREEN}[INFO]${NC}  $(date -u +%H:%M:%S) ${*}"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC}  $(date -u +%H:%M:%S) ${*}" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date -u +%H:%M:%S) ${*}" >&2
}

log_critical() {
    echo -e "${RED}${BOLD}[CRIT]${NC}  $(date -u +%H:%M:%S) ${*}" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $(date -u +%H:%M:%S) ${*}" >&2
    fi
}

banner() {
    local role="${1}"
    local role_upper
    role_upper="$(echo "${role}" | tr '[:lower:]' '[:upper:]')"

    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  Wheeler Enterprise — Server Role Enforcement               ║${NC}"
    echo -e "${BOLD}${CYAN}║  Role: ${MAGENTA}${role_upper}${CYAN}                                              ║${NC}"
    echo -e "${BOLD}${CYAN}║  Host: ${MAGENTA}$(hostname)${CYAN}   Time: ${MAGENTA}${TIMESTAMP}${CYAN}     ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ------------------------------------------------------------------------------
# Utility Functions
# ------------------------------------------------------------------------------

# Check if a command is available
cmd_exists() {
    command -v "${1}" &>/dev/null
}

# Check if a string matches any pattern in a list (case-insensitive)
matches_any_pattern() {
    local haystack="${1}"
    shift
    local -a patterns=("${@}")

    local lower_haystack
    lower_haystack="$(echo "${haystack}" | tr '[:upper:]' '[:lower:]')"

    for pattern in "${patterns[@]}"; do
        if [[ "${lower_haystack}" == *"${pattern}"* ]]; then
            return 0
        fi
    done
    return 1
}

# Check if a port/proto combo is listening on a specific address
# Usage: port_listening_on <port> <proto> <address_pattern>
# Returns 0 if the port is found listening on an address matching the pattern
port_listening_on() {
    local port="${1}"
    local proto="${2}"  # tcp or udp
    local addr_pattern="${3}"

    if cmd_exists ss; then
        # ss output format: LISTEN  0  128  0.0.0.0:22  0.0.0.0:*
        ss -tlnp 2>/dev/null | awk -v p="${port}" -v proto="${proto}" -v pat="${addr_pattern}" '
            $1 ~ /^LISTEN/ {
                # Split the local address field
                split($4, addr_part, ":")
                listen_addr = addr_part[1]
                listen_port = addr_part[2]
                if (listen_port == p && listen_addr ~ pat) {
                    print $0
                    found = 1
                }
            }
            END { if (found != 1) exit 1 }
        ' && return 0 || return 1
    elif cmd_exists netstat; then
        netstat -tlnp 2>/dev/null | awk -v p="${port}" -v proto="${proto}" -v pat="${addr_pattern}" '
            $1 ~ /^'"${proto}"'/ {
                split($4, addr_part, ":")
                listen_addr = addr_part[1]
                listen_port = addr_part[2]
                if (listen_port == p && listen_addr ~ pat) {
                    print $0
                    found = 1
                }
            }
            END { if (found != 1) exit 1 }
        ' && return 0 || return 1
    else
        # Neither ss nor netstat available — can't check ports
        return 2
    fi
}

# Get all listening ports with their bind addresses as structured records
# Output format (one per line): "proto|port|bind_addr|process"
get_all_listening_ports() {
    if cmd_exists ss; then
        ss -tlnp 2>/dev/null | awk '
            /^LISTEN/ {
                proto = "tcp"
                split($4, addr_port, ":")
                # Handle IPv6 addresses with colons — last element is the port
                port = addr_port[length(addr_port)]
                # Reconstruct the address part
                addr = ""
                for (i = 1; i < length(addr_port); i++) {
                    if (i > 1) addr = addr ":"
                    addr = addr addr_port[i]
                }
                # Extract process name from the last field
                process = $NF
                gsub(/users:\(\(\"/, "", process)
                gsub(/\"\).*/, "", process)
                if (process == "" || process == "-") process = "unknown"
                printf "%s|%s|%s|%s\n", proto, port, addr, process
            }
        '
    elif cmd_exists netstat; then
        netstat -tlnp 2>/dev/null | awk '
            /^tcp/ || /^tcp6/ {
                proto = "tcp"
                split($4, addr_port, ":")
                port = addr_port[length(addr_port)]
                addr = ""
                for (i = 1; i < length(addr_port); i++) {
                    if (i > 1) addr = addr ":"
                    addr = addr addr_port[i]
                }
                process = $NF
                gsub(/.*\//, "", process)
                if (process == "" || process == "-") process = "unknown"
                printf "%s|%s|%s|%s\n", proto, port, addr, process
            }
        '
    fi
}

# Get the public IP of the server
get_public_ip() {
    # Try Tailscale first
    if cmd_exists tailscale; then
        tailscale ip -4 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -v '^100\.' | head -1 || true
    fi
    # Fallback: use hostname -I and filter out local/Tailscale
    hostname -I 2>/dev/null | tr ' ' '\n' | grep -vE '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|100\.|127\.|172\.17\.)' | head -1 || true
}

# Get the Tailscale IP of the server
get_tailscale_ip() {
    if cmd_exists tailscale; then
        tailscale ip -4 2>/dev/null | grep '^100\.' | head -1 || true
    fi
}

# Escape a string for JSON
json_escape() {
    local s="${1}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    echo "${s}"
}

# Add a violation to the appropriate array
add_violation() {
    local severity="${1}"  # critical | warning | info
    local source="${2}"    # e.g., container:name, port:5432, volume:name
    local message="${3}"

    case "${severity}" in
        critical)
            CRITICAL_VIOLATIONS+=("[${source}] ${message}")
            ;;
        warning)
            WARNING_VIOLATIONS+=("[${source}] ${message}")
            ;;
        info)
            INFO_ITEMS+=("[${source}] ${message}")
            ;;
    esac
}

# Add a fix suggestion
add_fix() {
    local command="${1}"
    local description="${2}"

    if [[ "${SHOW_FIXES:-false}" == "true" ]]; then
        FIX_COMMANDS+=("$(printf '%-12s | %s' "${description}" "${command}")")
    fi
}

# ------------------------------------------------------------------------------
# Prerequisite Checks
# ------------------------------------------------------------------------------

check_prerequisites() {
    local missing=()

    if ! cmd_exists docker; then
        missing+=("docker (container inspection)")
    fi
    if ! cmd_exists ss && ! cmd_exists netstat; then
        missing+=("ss or netstat (port checking) — install iproute2 or net-tools")
    fi
    if ! cmd_exists hostname; then
        missing+=("hostname")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies:"
        for m in "${missing[@]}"; do
            echo "  - ${m}"
        done
        return 1
    fi

    # Docker daemon check
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running or not accessible."
        log_error "Check that dockerd is running and your user is in the docker group."
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Role Detection
# ------------------------------------------------------------------------------

detect_role_from_hostname() {
    local hn="${1}"
    local hn_lower
    hn_lower="$(echo "${hn}" | tr '[:upper:]' '[:lower:]')"

    if [[ "${hn_lower}" == *"edge"* ]]; then
        echo "edge"
    elif [[ "${hn_lower}" == *"aiops"* ]] || [[ "${hn_lower}" == *"ai-ops"* ]] || [[ "${hn_lower}" == *"brain"* ]]; then
        echo "aiops"
    elif [[ "${hn_lower}" == *"coredb"* ]] || [[ "${hn_lower}" == *"core-db"* ]] || [[ "${hn_lower}" == *"db"* ]] || [[ "${hn_lower}" == *"vault"* ]]; then
        echo "coredb"
    else
        echo ""
    fi
}

detect_role_from_tailscale_ip() {
    local ts_ip="${1}"

    if [[ -z "${ts_ip}" ]]; then
        echo ""
        return
    fi

    # Map known Tailscale IPs to roles
    case "${ts_ip}" in
        "100.64.0.2") echo "edge" ;;
        "100.64.0.3") echo "aiops" ;;
        "100.64.0.4") echo "coredb" ;;
        *)
            # Unknown IP — try to infer from common conventions
            # .2 is usually edge, .3 is usually aiops, .4+ is usually coredb
            local last_octet
            last_octet="$(echo "${ts_ip}" | awk -F. '{print $NF}')"
            if [[ "${last_octet}" == "2" ]]; then
                echo "edge"
            elif [[ "${last_octet}" == "3" ]]; then
                echo "aiops"
            elif [[ "${last_octet}" -ge 4 ]]; then
                echo "coredb"
            else
                echo ""
            fi
            ;;
    esac
}

detect_role_from_containers() {
    # Heuristic: look at existing Docker labels to determine intended role
    # This is the least reliable method, used only as a fallback

    local role_counts_edge=0
    local role_counts_aiops=0
    local role_counts_coredb=0

    local labels
    labels="$(docker ps --format '{{.Labels}}' 2>/dev/null | tr ',' '\n' | grep 'com.wheeler.role=' || true)"

    while IFS='=' read -r _ role_value; do
        case "${role_value}" in
            edge) role_counts_edge=$((role_counts_edge + 1)) ;;
            aiops) role_counts_aiops=$((role_counts_aiops + 1)) ;;
            coredb) role_counts_coredb=$((role_counts_coredb + 1)) ;;
        esac
    done <<< "${labels}"

    if [[ "${role_counts_edge}" -gt "${role_counts_aiops}" ]] && [[ "${role_counts_edge}" -gt "${role_counts_coredb}" ]]; then
        echo "edge"
    elif [[ "${role_counts_aiops}" -gt "${role_counts_edge}" ]] && [[ "${role_counts_aiops}" -gt "${role_counts_coredb}" ]]; then
        echo "aiops"
    elif [[ "${role_counts_coredb}" -gt "${role_counts_edge}" ]] && [[ "${role_counts_coredb}" -gt "${role_counts_aiops}" ]]; then
        echo "coredb"
    else
        echo ""
    fi
}

determine_role() {
    local forced_role="${1:-}"

    # 1. --server flag takes highest precedence
    if [[ -n "${forced_role}" ]]; then
        case "${forced_role}" in
            edge|aiops|coredb)
                DETECTED_ROLE="${forced_role}"
                log_info "Role forced via --server flag: ${DETECTED_ROLE}"
                return 0
                ;;
            *)
                log_error "Invalid role '${forced_role}'. Must be: edge, aiops, or coredb"
                return 1
                ;;
        esac
    fi

    # 2. Try hostname
    local role_from_hostname
    role_from_hostname="$(detect_role_from_hostname "${HOSTNAME}")"
    if [[ -n "${role_from_hostname}" ]]; then
        DETECTED_ROLE="${role_from_hostname}"
        log_info "Role detected from hostname '${HOSTNAME}': ${DETECTED_ROLE}"
        return 0
    fi

    # 3. Try Tailscale IP
    local ts_ip
    ts_ip="$(get_tailscale_ip)"
    if [[ -n "${ts_ip}" ]]; then
        local role_from_ts
        role_from_ts="$(detect_role_from_tailscale_ip "${ts_ip}")"
        if [[ -n "${role_from_ts}" ]]; then
            DETECTED_ROLE="${role_from_ts}"
            log_info "Role detected from Tailscale IP '${ts_ip}': ${DETECTED_ROLE}"
            return 0
        fi
    fi

    # 4. Try Docker labels (least reliable)
    local role_from_containers
    role_from_containers="$(detect_role_from_containers)"
    if [[ -n "${role_from_containers}" ]]; then
        DETECTED_ROLE="${role_from_containers}"
        log_info "Role detected from Docker container labels: ${DETECTED_ROLE}"
        log_warn "Container-label-based detection is less reliable. Use --server flag for certainty."
        return 0
    fi

    # 5. Cannot determine role
    log_error "Cannot determine server role."
    log_error "Tried: hostname (${HOSTNAME}), Tailscale IP ($(get_tailscale_ip)), Docker labels"
    log_error "Please specify role explicitly with: ${SCRIPT_NAME} --server <edge|aiops|coredb>"
    return 1
}

# ------------------------------------------------------------------------------
# Lock File Management
# ------------------------------------------------------------------------------

acquire_lock() {
    if [[ "${SKIP_LOCK:-false}" == "true" ]]; then
        return 0
    fi

    # Create lock directory if it doesn't exist
    mkdir -p "$(dirname "${LOCK_FILE}")"

    # Try to acquire lock
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid="$(cat "${LOCK_FILE}" 2>/dev/null || echo '')"
        if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
            log_warn "Another instance of ${SCRIPT_NAME} is running (PID: ${lock_pid})"
            log_warn "If this is stale, remove ${LOCK_FILE} or use --no-lock"
            return 1
        else
            log_warn "Removing stale lock file from PID ${lock_pid}"
            rm -f "${LOCK_FILE}"
        fi
    fi

    echo $$ > "${LOCK_FILE}"
    # Ensure lock file is removed on exit
    trap 'rm -f "${LOCK_FILE}"' EXIT
    return 0
}

# ------------------------------------------------------------------------------
# Docker Container Inspection
# ------------------------------------------------------------------------------

# Get list of running containers with name and image
get_running_containers() {
    docker ps --format '{{.Names}}|{{.Image}}|{{.Labels}}|{{.Mounts}}'
}

# Get Docker volume sizes in bytes
get_volume_sizes() {
    docker system df -v 2>/dev/null | awk '
        /^Local Volumes space usage:/ { in_section = 1; next }
        in_section && /^[a-f0-9]/ { printf "%s|%s\n", $1, $3 }
        /^Build cache/ { exit }
    ' || true
}

# Get container volume mount details
get_container_mounts() {
    local container_name="${1}"
    docker inspect "${container_name}" --format '{{range .Mounts}}{{.Type}}|{{.Source}}|{{.Destination}}|{{.Name}} {{end}}' 2>/dev/null || true
}

# Get the image for a container
get_container_image() {
    local container_name="${1}"
    docker inspect "${container_name}" --format '{{.Config.Image}}' 2>/dev/null || echo "unknown"
}

# Check if a container has a specific label
container_has_label() {
    local container_name="${1}"
    local label_key="${2}"

    local label_value
    label_value="$(docker inspect "${container_name}" --format "{{ index .Config.Labels \"${label_key}\" }}" 2>/dev/null || true)"

    [[ -n "${label_value}" ]] && [[ "${label_value}" != "<no value>" ]]
}

# Get a container's label value
container_get_label() {
    local container_name="${1}"
    local label_key="${2}"

    docker inspect "${container_name}" --format "{{ index .Config.Labels \"${label_key}\" }}" 2>/dev/null || echo ""
}

# ------------------------------------------------------------------------------
# Check: Forbidden Containers
# ------------------------------------------------------------------------------

check_forbidden_containers_edge() {
    log_info "Checking for forbidden containers on EDGE..."

    local container_data
    container_data="$(get_running_containers)"

    if [[ -z "${container_data}" ]]; then
        log_info "  No running Docker containers found."
        return 0
    fi

    while IFS='|' read -r cname cimage clabels cmounts; do
        CONTAINER_IMAGE["${cname}"]="${cimage}"
        local cimage_lower
        cimage_lower="$(echo "${cimage}" | tr '[:upper:]' '[:lower:]')"

        # Check database images
        if matches_any_pattern "${cimage_lower}" "${DB_IMAGE_PATTERNS[@]}"; then
            local violation_msg="Database container '${cname}' (${cimage}) on EDGE — CRITICAL security risk"
            CONTAINER_STATUS["${cname}"]="critical"
            CONTAINER_VIOLATIONS["${cname}"]="Database image on EDGE"
            add_violation "critical" "container:${cname}" "${violation_msg}"
            add_fix "docker rm -f ${cname} && docker rmi ${cimage}" "Remove DB container"
        fi

        # Check AI/ML images
        if matches_any_pattern "${cimage_lower}" "${AI_ML_IMAGE_PATTERNS[@]}"; then
            local violation_msg="AI/ML container '${cname}' (${cimage}) on EDGE — CRITICAL security risk"
            CONTAINER_STATUS["${cname}"]="critical"
            CONTAINER_VIOLATIONS["${cname}"]="AI/ML image on EDGE"
            add_violation "critical" "container:${cname}" "${violation_msg}"
            add_fix "docker rm -f ${cname} && docker rmi ${cimage}" "Remove AI/ML container"
        fi

        # Check CI/CD images
        if matches_any_pattern "${cimage_lower}" "${CI_CD_IMAGE_PATTERNS[@]}"; then
            local violation_msg="CI/CD container '${cname}' (${cimage}) on EDGE — not allowed"
            CONTAINER_STATUS["${cname}"]="warning"
            CONTAINER_VIOLATIONS["${cname}"]="CI/CD image on EDGE"
            add_violation "warning" "container:${cname}" "${violation_msg}"
            add_fix "docker rm -f ${cname} && docker rmi ${cimage}" "Remove CI/CD container"
        fi

        # Check for application servers (nginx is allowed, others aren't)
        if [[ "${cimage_lower}" != *"nginx"* ]] && [[ "${cimage_lower}" != *"traefik"* ]]; then
            if matches_any_pattern "${cimage_lower}" "${APP_SERVER_IMAGE_PATTERNS[@]}"; then
                local violation_msg="Application server container '${cname}' (${cimage}) on EDGE — not allowed"
                CONTAINER_STATUS["${cname}"]="warning"
                CONTAINER_VIOLATIONS["${cname}"]="App server on EDGE"
                add_violation "warning" "container:${cname}" "${violation_msg}"
                add_fix "docker rm -f ${cname} && docker rmi ${cimage}" "Remove app server container"
            fi
        fi

    done <<< "${container_data}"
}

check_forbidden_containers_aiops() {
    log_info "Checking for forbidden containers on AIOPS..."

    local container_data
    container_data="$(get_running_containers)"

    if [[ -z "${container_data}" ]]; then
        log_info "  No running Docker containers found."
        return 0
    fi

    while IFS='|' read -r cname cimage clabels cmounts; do
        CONTAINER_IMAGE["${cname}"]="${cimage}"
        local cimage_lower
        cimage_lower="$(echo "${cimage}" | tr '[:upper:]' '[:lower:]')"

        # Check for PRIMARY database containers
        if matches_any_pattern "${cimage_lower}" "${DB_IMAGE_PATTERNS[@]}"; then
            # Check if it's labeled as a read-replica (which IS allowed on AIOPS)
            local role_label
            role_label="$(container_get_label "${cname}" "com.wheeler.role")"
            local primary_label
            primary_label="$(container_get_label "${cname}" "com.wheeler.primary")"

            if [[ "${role_label}" == "read-replica" ]]; then
                CONTAINER_STATUS["${cname}"]="ok"
                log_info "  Database container '${cname}' (${cimage}) is labeled as read-replica — allowed"
                if [[ -z "${primary_label}" ]]; then
                    add_violation "info" "container:${cname}" \
                        "Read replica '${cname}' missing com.wheeler.primary label (should point to COREDB IP)"
                fi
            else
                # It's a database but NOT labeled read-replica — CRITICAL
                local violation_msg="PRIMARY database '${cname}' (${cimage}) on AIOPS — databases must run on COREDB"
                CONTAINER_STATUS["${cname}"]="critical"
                CONTAINER_VIOLATIONS["${cname}"]="Primary DB on AIOPS"
                add_violation "critical" "container:${cname}" "${violation_msg}"
                add_fix "# Migrate to COREDB:\n# 1. pg_dump on AIOPS\n# 2. scp dump to COREDB\n# 3. pg_restore on COREDB\n# 4. docker rm -f ${cname}" \
                    "Migrate primary DB to COREDB"
            fi
        fi

        # Check for blockchain nodes (warning)
        if [[ "${cimage_lower}" == *"bitcoin"* ]] || [[ "${cimage_lower}" == *"ethereum"* ]] || \
           [[ "${cimage_lower}" == *"solana"* ]] || [[ "${cimage_lower}" == *"ipfs"* ]] || \
           [[ "${cimage_lower}" == *"blockchain"* ]]; then
            add_violation "info" "container:${cname}" \
                "Blockchain node '${cname}' (${cimage}) on AIOPS — resource-intensive, review necessity"
        fi

    done <<< "${container_data}"
}

check_forbidden_containers_coredb() {
    log_info "Checking for forbidden containers on COREDB..."

    local container_data
    container_data="$(get_running_containers)"

    if [[ -z "${container_data}" ]]; then
        log_info "  No running Docker containers found."
        return 0
    fi

    while IFS='|' read -r cname cimage clabels cmounts; do
        CONTAINER_IMAGE["${cname}"]="${cimage}"
        local cimage_lower
        cimage_lower="$(echo "${cimage}" | tr '[:upper:]' '[:lower:]')"

        # Check for web servers / reverse proxies — NEVER on COREDB (except MinIO console)
        if [[ "${cimage_lower}" == *"traefik"* ]] || [[ "${cimage_lower}" == *"nginx"* ]] || \
           [[ "${cimage_lower}" == *"caddy"* ]] || [[ "${cimage_lower}" == *"apache"* ]] || \
           [[ "${cimage_lower}" == *"httpd"* ]] || [[ "${cimage_lower}" == *"haproxy"* ]]; then
            # minio is OK (it has a web console but it's a DB service)
            if [[ "${cimage_lower}" != *"minio"* ]]; then
                local violation_msg="Web server '${cname}' (${cimage}) on COREDB — CRITICAL: no public-facing services on data tier"
                CONTAINER_STATUS["${cname}"]="critical"
                CONTAINER_VIOLATIONS["${cname}"]="Web server on COREDB"
                add_violation "critical" "container:${cname}" "${violation_msg}"
                add_fix "docker rm -f ${cname} && docker rmi ${cimage}" "Remove web server from COREDB"
            fi
        fi

        # Check for AI/ML images on COREDB
        if matches_any_pattern "${cimage_lower}" "${AI_ML_IMAGE_PATTERNS[@]}"; then
            # pgvector is OK (it's in PostgreSQL, not a separate container)
            if [[ "${cimage_lower}" != *"pgvector"* ]]; then
                local violation_msg="AI/ML container '${cname}' (${cimage}) on COREDB — AI runs on AIOPS only"
                CONTAINER_STATUS["${cname}"]="critical"
                CONTAINER_VIOLATIONS["${cname}"]="AI/ML on COREDB"
                add_violation "critical" "container:${cname}" "${violation_msg}"
                add_fix "docker rm -f ${cname} && docker rmi ${cimage}" "Remove AI/ML from COREDB"
            fi
        fi

        # Check for application servers on COREDB
        if matches_any_pattern "${cimage_lower}" "${APP_SERVER_IMAGE_PATTERNS[@]}"; then
            # No app servers on COREDB
            local violation_msg="Application server '${cname}' (${cimage}) on COREDB — no app code on data tier"
            CONTAINER_STATUS["${cname}"]="critical"
            CONTAINER_VIOLATIONS["${cname}"]="App server on COREDB"
            add_violation "critical" "container:${cname}" "${violation_msg}"
            add_fix "docker rm -f ${cname} && docker rmi ${cimage}" "Remove app server from COREDB"
        fi

        # Check for CI/CD on COREDB
        if matches_any_pattern "${cimage_lower}" "${CI_CD_IMAGE_PATTERNS[@]}"; then
            local violation_msg="CI/CD container '${cname}' (${cimage}) on COREDB — no CI on data tier"
            CONTAINER_STATUS["${cname}"]="critical"
            CONTAINER_VIOLATIONS["${cname}"]="CI/CD on COREDB"
            add_violation "critical" "container:${cname}" "${violation_msg}"
            add_fix "docker rm -f ${cname} && docker rmi ${cimage}" "Remove CI/CD from COREDB"
        fi

        # Check for monitoring UIs on COREDB (exporters OK, UIs not)
        if matches_any_pattern "${cimage_lower}" "${MONITORING_UI_IMAGE_PATTERNS[@]}"; then
            local violation_msg="Monitoring UI '${cname}' (${cimage}) on COREDB — only exporters, no dashboards on data tier"
            CONTAINER_STATUS["${cname}"]="warning"
            CONTAINER_VIOLATIONS["${cname}"]="Monitoring UI on COREDB"
            add_violation "warning" "container:${cname}" "${violation_msg}"
            add_fix "docker rm -f ${cname} && docker rmi ${cimage}" "Remove monitoring UI from COREDB"
        fi

        # Check for orchestration tools on COREDB
        if [[ "${cimage_lower}" == *"n8n"* ]] || [[ "${cimage_lower}" == *"temporal"* ]] || \
           [[ "${cimage_lower}" == *"airflow"* ]] || [[ "${cimage_lower}" == *"prefect"* ]]; then
            local violation_msg="Orchestration container '${cname}' (${cimage}) on COREDB — orchestration runs on AIOPS"
            CONTAINER_STATUS["${cname}"]="critical"
            CONTAINER_VIOLATIONS["${cname}"]="Orchestration on COREDB"
            add_violation "critical" "container:${cname}" "${violation_msg}"
            add_fix "docker rm -f ${cname} && docker rmi ${cimage}" "Remove orchestration from COREDB"
        fi

    done <<< "${container_data}"
}

# ------------------------------------------------------------------------------
# Check: Port Bindings
# ------------------------------------------------------------------------------

check_ports_edge() {
    log_info "Checking port bindings on EDGE..."

    local port_records
    port_records="$(get_all_listening_ports)"

    if [[ -z "${port_records}" ]]; then
        log_warn "  Could not retrieve port information (ss/netstat not available)."
        return 0
    fi

    while IFS='|' read -r proto port bind_addr process; do
        OPEN_PORT_RECORDS+=("${proto}|${port}|${bind_addr}|${process}")

        # Check if this port is bound to 0.0.0.0 (public)
        if [[ "${bind_addr}" == "0.0.0.0" ]] || [[ "${bind_addr}" == "*" ]] || [[ "${bind_addr}" == "::" ]]; then
            # On EDGE, only ports 22, 80, 443 are allowed on 0.0.0.0
            local is_allowed=false
            for allowed_port in "${EDGE_PUBLIC_PORTS[@]}"; do
                if [[ "${port}" == "${allowed_port}" ]]; then
                    is_allowed=true
                    break
                fi
            done

            if [[ "${is_allowed}" == "false" ]]; then
                local violation_msg="Port ${port}/${proto} (${process}) is bound to 0.0.0.0 on EDGE — only 22, 80, 443 allowed"
                add_violation "critical" "port:${port}" "${violation_msg}"
                add_fix "# Update compose file to bind to Tailscale IP or 127.0.0.1:\n#   ports:\n#     - '127.0.0.1:${port}:${port}'" \
                    "Fix public port binding"
            fi
        fi

        # Check for database ports on EDGE
        for db_port in "${DB_PORTS[@]}"; do
            if [[ "${port}" == "${db_port}" ]]; then
                local violation_msg="Database port ${port}/${proto} (${process}) found on EDGE — databases must not run on EDGE"
                add_violation "critical" "port:${port}" "${violation_msg}"
                break
            fi
        done

    done <<< "${port_records}"
}

check_ports_aiops() {
    log_info "Checking port bindings on AIOPS..."

    local port_records
    port_records="$(get_all_listening_ports)"

    if [[ -z "${port_records}" ]]; then
        log_warn "  Could not retrieve port information (ss/netstat not available)."
        return 0
    fi

    while IFS='|' read -r proto port bind_addr process; do
        OPEN_PORT_RECORDS+=("${proto}|${port}|${bind_addr}|${process}")

        # Database ports (5432, 6379) must NOT be bound to 0.0.0.0 on AIOPS
        if [[ "${port}" == "5432" ]] || [[ "${port}" == "6379" ]] || [[ "${port}" == "6432" ]]; then
            if [[ "${bind_addr}" == "0.0.0.0" ]] || [[ "${bind_addr}" == "*" ]] || [[ "${bind_addr}" == "::" ]]; then
                local violation_msg="Database port ${port}/${proto} bound to ${bind_addr} on AIOPS — must bind to Tailscale IP or 127.0.0.1"
                add_violation "critical" "port:${port}" "${violation_msg}"
                add_fix "# Update compose to bind to Tailscale IP:\n#   ports:\n#     - '100.64.0.3:${port}:${port}'" \
                    "Fix DB port binding"
            fi
        fi

        # Check for any public (0.0.0.0) port bindings that aren't SSH
        if [[ "${bind_addr}" == "0.0.0.0" ]] || [[ "${bind_addr}" == "*" ]] || [[ "${bind_addr}" == "::" ]]; then
            if [[ "${port}" != "22" ]]; then
                local violation_msg="Port ${port}/${proto} (${process}) bound to 0.0.0.0 on AIOPS — no public exposure allowed"
                add_violation "warning" "port:${port}" "${violation_msg}"
                add_fix "# Bind to Tailscale IP instead of 0.0.0.0:\n#   ports:\n#     - '100.64.0.3:${port}:${port}'" \
                    "Fix public port binding"
            fi
        fi

    done <<< "${port_records}"
}

check_ports_coredb() {
    log_info "Checking port bindings on COREDB..."

    local port_records
    port_records="$(get_all_listening_ports)"

    if [[ -z "${port_records}" ]]; then
        log_warn "  Could not retrieve port information (ss/netstat not available)."
        return 0
    fi

    while IFS='|' read -r proto port bind_addr process; do
        OPEN_PORT_RECORDS+=("${proto}|${port}|${bind_addr}|${process}")

        # On COREDB, NOTHING should be bound to 0.0.0.0
        if [[ "${bind_addr}" == "0.0.0.0" ]] || [[ "${bind_addr}" == "*" ]] || [[ "${bind_addr}" == "::" ]]; then
            # Even SSH should be on Tailscale only for COREDB
            local violation_msg="Port ${port}/${proto} (${process}) bound to ${bind_addr} on COREDB — ALL services must bind to Tailscale IP only"
            add_violation "critical" "port:${port}" "${violation_msg}"
            add_fix "# Update compose to bind to Tailscale IP (100.64.0.4):\n#   ports:\n#     - '100.64.0.4:${port}:${port}'" \
                "Remove public port binding"
        fi

        # Check that bind address is either Tailscale IP or 127.0.0.1
        local ts_ip
        ts_ip="$(get_tailscale_ip)"
        if [[ -n "${ts_ip}" ]]; then
            if [[ "${bind_addr}" != "${ts_ip}" ]] && [[ "${bind_addr}" != "127.0.0.1" ]] && \
               [[ "${bind_addr}" != "::1" ]] && [[ "${bind_addr}" != "localhost" ]] && \
               [[ "${bind_addr}" != "0.0.0.0" ]] && [[ "${bind_addr}" != "*" ]] && [[ "${bind_addr}" != "::" ]]; then
                # Bound to some other interface — might be the public IP, which is also bad
                add_violation "warning" "port:${port}" \
                    "Port ${port}/${proto} bound to ${bind_addr} (not Tailscale IP ${ts_ip} or localhost) — verify this is intentional"
            fi
        fi

    done <<< "${port_records}"
}

# ------------------------------------------------------------------------------
# Check: Docker Labels
# ------------------------------------------------------------------------------

check_docker_labels() {
    log_info "Checking Docker labels for role compliance..."

    local container_data
    container_data="$(get_running_containers)"

    if [[ -z "${container_data}" ]]; then
        log_info "  No running Docker containers found."
        return 0
    fi

    local unlabeled_count=0
    local labeled_count=0
    local mislabeled_count=0

    while IFS='|' read -r cname cimage clabels cmounts; do
        # Extract com.wheeler.role label
        local role_label
        role_label="$(echo "${clabels}" | tr ',' '\n' | grep '^com.wheeler.role=' | cut -d= -f2- || true)"

        if [[ -z "${role_label}" ]]; then
            # No role label — warning
            CONTAINER_LABEL_ROLE["${cname}"]="unlabeled"
            unlabeled_count=$((unlabeled_count + 1))
            if [[ "${CONTAINER_STATUS[${cname}]:-ok}" == "ok" ]]; then
                CONTAINER_STATUS["${cname}"]="warning"
                CONTAINER_VIOLATIONS["${cname}"]="Missing com.wheeler.role label"
            fi
            add_violation "warning" "container:${cname}" \
                "Container '${cname}' (${cimage}) has no com.wheeler.role label — add labeling to compose file"
            add_fix "docker update --label com.wheeler.role=${DETECTED_ROLE} ${cname}" \
                "Add role label"
        else
            CONTAINER_LABEL_ROLE["${cname}"]="${role_label}"
            labeled_count=$((labeled_count + 1))

            # Check if the label matches the server's actual role
            if [[ "${role_label}" != "${DETECTED_ROLE}" ]]; then
                # Special case: read-replica on AIOPS is OK
                if [[ "${DETECTED_ROLE}" == "aiops" ]] && [[ "${role_label}" == "read-replica" ]]; then
                    CONTAINER_STATUS["${cname}"]="ok"
                else
                    mislabeled_count=$((mislabeled_count + 1))
                    if [[ "${CONTAINER_STATUS[${cname}]:-ok}" != "critical" ]]; then
                        CONTAINER_STATUS["${cname}"]="warning"
                        CONTAINER_VIOLATIONS["${cname}"]="Role label mismatch: labeled '${role_label}', server is '${DETECTED_ROLE}'"
                    fi
                    add_violation "warning" "container:${cname}" \
                        "Container '${cname}' labeled role='${role_label}' but server role is '${DETECTED_ROLE}'"
                fi
            fi

            # Check for other required labels
            local service_label
            service_label="$(echo "${clabels}" | tr ',' '\n' | grep '^com.wheeler.service=' | cut -d= -f2- || true)"
            if [[ -z "${service_label}" ]]; then
                add_violation "info" "container:${cname}" \
                    "Container '${cname}' missing com.wheeler.service label (recommended)"
            fi
        fi
    done <<< "${container_data}"

    log_info "  Label summary: ${labeled_count} labeled, ${unlabeled_count} unlabeled, ${mislabeled_count} mislabeled"
}

# ------------------------------------------------------------------------------
# Check: Volume Placement
# ------------------------------------------------------------------------------

check_volumes_edge() {
    log_info "Checking Docker volume placement on EDGE..."

    local container_data
    container_data="$(get_running_containers)"

    if [[ -z "${container_data}" ]]; then
        return 0
    fi

    while IFS='|' read -r cname cimage clabels cmounts; do
        # Get individual mounts
        local mounts
        mounts="$(get_container_mounts "${cname}")"

        if [[ -z "${mounts}" ]]; then
            continue
        fi

        for mount_entry in ${mounts}; do
            local mount_type mount_source mount_dest mount_name
            mount_type="$(echo "${mount_entry}" | cut -d'|' -f1)"
            mount_source="$(echo "${mount_entry}" | cut -d'|' -f2)"
            mount_dest="$(echo "${mount_entry}" | cut -d'|' -f3)"
            mount_name="$(echo "${mount_entry}" | cut -d'|' -f4)"

            # On EDGE, check for large bind mounts or volumes (>1GB)
            if [[ -d "${mount_source}" ]]; then
                local dir_size_bytes
                dir_size_bytes="$(du -sb "${mount_source}" 2>/dev/null | awk '{print $1}' || echo 0)"

                # 1 GB = 1073741824 bytes
                if [[ "${dir_size_bytes}" -gt 1073741824 ]]; then
                    local dir_size_gb
                    dir_size_gb="$(echo "scale=2; ${dir_size_bytes} / 1073741824" | bc 2>/dev/null || echo '>1')"
                    add_violation "critical" "volume:${cname}" \
                        "Volume '${mount_source}' (${dir_size_gb}GB) on EDGE exceeds 1GB limit — data volumes must not live on EDGE"
                    add_fix "# Migrate data to COREDB MinIO:\n#   mc cp -r ${mount_source}/ myminio/uploads/" \
                        "Migrate data volume"
                fi
            fi
        done
    done <<< "${container_data}"
}

check_volumes_coredb() {
    log_info "Checking volume placement on COREDB..."

    local container_data
    container_data="$(get_running_containers)"

    if [[ -z "${container_data}" ]]; then
        return 0
    fi

    while IFS='|' read -r cname cimage clabels cmounts; do
        local mounts
        mounts="$(get_container_mounts "${cname}")"

        if [[ -z "${mounts}" ]]; then
            continue
        fi

        for mount_entry in ${mounts}; do
            local mount_type mount_source mount_dest mount_name
            mount_type="$(echo "${mount_entry}" | cut -d'|' -f1)"
            mount_source="$(echo "${mount_entry}" | cut -d'|' -f2)"
            mount_dest="$(echo "${mount_entry}" | cut -d'|' -f3)"
            mount_name="$(echo "${mount_entry}" | cut -d'|' -f4)"

            # On COREDB, database data volumes should be on /data partition, not root
            if [[ -d "${mount_source}" ]]; then
                if [[ "${mount_source}" != "/data"* ]] && [[ "${mount_source}" != "/mnt/"* ]]; then
                    # Check if this looks like a data directory (contains DB files)
                    if [[ "${mount_dest}" == "/var/lib/postgresql"* ]] || \
                       [[ "${mount_dest}" == "/data"* ]] || \
                       [[ "${mount_dest}" == "/bitnami"* ]] || \
                       [[ "${mount_dest}" == *"data"* ]]; then
                        add_violation "warning" "volume:${cname}" \
                            "Database volume '${mount_source}' (container '${cname}') is not on /data partition — risk of filling root FS"
                        add_fix "# Move volume to /data:\n#   docker stop ${cname} && mv ${mount_source} /data/volumes/ && update compose mount source" \
                            "Move volume to /data"
                    fi
                fi
            fi
        done
    done <<< "${container_data}"
}

# ------------------------------------------------------------------------------
# Check: UFW/Firewall (Tailscale requirement)
# ------------------------------------------------------------------------------

check_tailscale_connectivity() {
    log_info "Checking Tailscale connectivity..."

    if ! cmd_exists tailscale; then
        add_violation "critical" "system:tailscale" \
            "Tailscale is not installed — required for secure inter-server communication"
        return 1
    fi

    local ts_status
    ts_status="$(tailscale status 2>/dev/null || echo 'ERROR')"

    if [[ "${ts_status}" == "ERROR" ]]; then
        add_violation "critical" "system:tailscale" \
            "Tailscale is not running — required for secure inter-server communication"
        return 1
    fi

    local ts_ip
    ts_ip="$(get_tailscale_ip)"
    if [[ -z "${ts_ip}" ]]; then
        add_violation "critical" "system:tailscale" \
            "No Tailscale IPv4 address assigned — check tailscale status"
        return 1
    fi

    log_info "  Tailscale is running. IP: ${ts_ip}"
    return 0
}

# ------------------------------------------------------------------------------
# JSON Report Generation
# ------------------------------------------------------------------------------

generate_json_report() {
    log_info "Generating JSON report..."

    local ts_ip
    ts_ip="$(get_tailscale_ip)"

    # Build violations JSON arrays
    local critical_json="["
    local sep=""
    for v in "${CRITICAL_VIOLATIONS[@]}"; do
        critical_json+="${sep}\"$(json_escape "${v}")\""
        sep=","
    done
    critical_json+="]"

    local warning_json="["
    sep=""
    for v in "${WARNING_VIOLATIONS[@]}"; do
        warning_json+="${sep}\"$(json_escape "${v}")\""
        sep=","
    done
    warning_json+="]"

    local info_json="["
    sep=""
    for v in "${INFO_ITEMS[@]}"; do
        info_json+="${sep}\"$(json_escape "${v}")\""
        sep=","
    done
    info_json+="]"

    # Build containers JSON array
    local containers_json="["
    sep=""
    for cname in "${!CONTAINER_IMAGE[@]}"; do
        local cimage="${CONTAINER_IMAGE[${cname}]}"
        local cstatus="${CONTAINER_STATUS[${cname}]:-ok}"
        local cviolation="${CONTAINER_VIOLATIONS[${cname}]:-}"
        local clabel="${CONTAINER_LABEL_ROLE[${cname}]:-unlabeled}"

        containers_json+="${sep}{"
        containers_json+="\"name\":\"$(json_escape "${cname}")\","
        containers_json+="\"image\":\"$(json_escape "${cimage}")\","
        containers_json+="\"status\":\"${cstatus}\","
        containers_json+="\"label_role\":\"${clabel}\","
        containers_json+="\"violation\":\"$(json_escape "${cviolation}")\""
        containers_json+="}"
        sep=","
    done
    containers_json+="]"

    # Build ports JSON array
    local ports_json="["
    sep=""
    for rec in "${OPEN_PORT_RECORDS[@]}"; do
        local p_proto p_port p_addr p_proc
        p_proto="$(echo "${rec}" | cut -d'|' -f1)"
        p_port="$(echo "${rec}" | cut -d'|' -f2)"
        p_addr="$(echo "${rec}" | cut -d'|' -f3)"
        p_proc="$(echo "${rec}" | cut -d'|' -f4)"

        ports_json+="${sep}{"
        ports_json+="\"proto\":\"${p_proto}\","
        ports_json+="\"port\":${p_port},"
        ports_json+="\"bind_address\":\"${p_addr}\","
        ports_json+="\"process\":\"$(json_escape "${p_proc}")\""
        ports_json+="}"
        sep=","
    done
    ports_json+="]"

    # Build fix commands JSON array
    local fixes_json="["
    sep=""
    for f in "${FIX_COMMANDS[@]}"; do
        local f_desc f_cmd
        f_desc="$(echo "${f}" | cut -d'|' -f1 | xargs)"
        f_cmd="$(echo "${f}" | cut -d'|' -f2-)"
        fixes_json+="${sep}{"
        fixes_json+="\"description\":\"$(json_escape "${f_desc}")\","
        fixes_json+="\"command\":\"$(json_escape "${f_cmd}")\""
        fixes_json+="}"
        sep=","
    done
    fixes_json+="]"

    # Determine overall severity
    local overall_severity="ok"
    if [[ ${#CRITICAL_VIOLATIONS[@]} -gt 0 ]]; then
        overall_severity="critical"
    elif [[ ${#WARNING_VIOLATIONS[@]} -gt 0 ]]; then
        overall_severity="warning"
    elif [[ ${#INFO_ITEMS[@]} -gt 0 ]]; then
        overall_severity="info"
    fi

    JSON_REPORT="$(cat <<JSONEOF
{
  "audit_time": "${TIMESTAMP}",
  "server": {
    "hostname": "$(json_escape "${HOSTNAME}")",
    "role": "${DETECTED_ROLE}",
    "tailscale_ip": "${ts_ip:-none}",
    "public_ip": "$(get_public_ip)"
  },
  "summary": {
    "overall_severity": "${overall_severity}",
    "critical_count": ${#CRITICAL_VIOLATIONS[@]},
    "warning_count": ${#WARNING_VIOLATIONS[@]},
    "info_count": ${#INFO_ITEMS[@]},
    "total_containers": ${#CONTAINER_IMAGE[@]},
    "unlabeled_containers": $(echo "${CONTAINER_LABEL_ROLE[@]}" | tr ' ' '\n' | grep -c 'unlabeled' || echo 0)
  },
  "containers": ${containers_json},
  "open_ports": ${ports_json},
  "violations": {
    "critical": ${critical_json},
    "warning": ${warning_json},
    "info": ${info_json}
  },
  "fix_suggestions": ${fixes_json}
}
JSONEOF
)"

    # Write to file
    mkdir -p "${LOG_DIR}"
    echo "${JSON_REPORT}" > "${REPORT_FILE}"
    log_info "JSON report written to ${REPORT_FILE}"
}

# ------------------------------------------------------------------------------
# Prometheus Metrics Export
# ------------------------------------------------------------------------------

export_prometheus_metrics() {
    log_info "Exporting Prometheus metrics..."

    mkdir -p "${METRICS_DIR}"

    local ts_ip
    ts_ip="$(get_tailscale_ip)"

    cat > "${METRICS_FILE}" <<PROMEOF
# HELP wheeler_role_audit_last_run_seconds Timestamp of last role audit
# TYPE wheeler_role_audit_last_run_seconds gauge
wheeler_role_audit_last_run_seconds $(date +%s)

# HELP wheeler_role_server_role Detected server role (0=edge, 1=aiops, 2=coredb)
# TYPE wheeler_role_server_role gauge
wheeler_role_server_role{role="${DETECTED_ROLE}",hostname="${HOSTNAME}",tailscale_ip="${ts_ip:-none}"} $(case "${DETECTED_ROLE}" in edge) echo 0;; aiops) echo 1;; coredb) echo 2;; *) echo -1;; esac)

# HELP wheeler_role_violations Number of role compliance violations by severity
# TYPE wheeler_role_violations gauge
wheeler_role_violations{severity="critical"} ${#CRITICAL_VIOLATIONS[@]}
wheeler_role_violations{severity="warning"} ${#WARNING_VIOLATIONS[@]}
wheeler_role_violations{severity="info"} ${#INFO_ITEMS[@]}

# HELP wheeler_containers_total Total number of running Docker containers
# TYPE wheeler_containers_total gauge
wheeler_containers_total ${#CONTAINER_IMAGE[@]}

# HELP wheeler_containers_unlabeled Number of containers missing com.wheeler.role label
# TYPE wheeler_containers_unlabeled gauge
wheeler_containers_unlabeled $(for c in "${!CONTAINER_LABEL_ROLE[@]}"; do [[ "${CONTAINER_LABEL_ROLE[${c}]}" == "unlabeled" ]] && echo 1; done | wc -l)

# HELP wheeler_containers_misplaced Number of containers on wrong server
# TYPE wheeler_containers_misplaced gauge
wheeler_containers_misplaced $(for c in "${!CONTAINER_LABEL_ROLE[@]}"; do [[ "${CONTAINER_LABEL_ROLE[${c}]}" != "unlabeled" && "${CONTAINER_LABEL_ROLE[${c}]}" != "${DETECTED_ROLE}" && "${CONTAINER_LABEL_ROLE[${c}]}" != "read-replica" ]] && echo 1; done | wc -l)

# HELP wheeler_audit_success Whether the audit ran successfully (1=yes, 0=no)
# TYPE wheeler_audit_success gauge
wheeler_audit_success 1
PROMEOF

    log_info "Prometheus metrics written to ${METRICS_FILE}"
}

# ------------------------------------------------------------------------------
# Terminal Report Output
# ------------------------------------------------------------------------------

print_terminal_report() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  COMPLIANCE REPORT — ${DETECTED_ROLE^^} SERVER${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Summary section
    echo -e "${BOLD}┌── Summary ──────────────────────────────────────────────────┐${NC}"
    printf "  %-40s ${CYAN}%s${NC}\n" "Server Role:" "${DETECTED_ROLE}"
    printf "  %-40s ${CYAN}%s${NC}\n" "Hostname:" "$(hostname)"
    printf "  %-40s ${CYAN}%s${NC}\n" "Tailscale IP:" "$(get_tailscale_ip)"
    printf "  %-40s ${CYAN}%s${NC}\n" "Containers checked:" "${#CONTAINER_IMAGE[@]}"
    printf "  %-40s ${CYAN}%s${NC}\n" "Open ports found:" "${#OPEN_PORT_RECORDS[@]}"
    printf "  %-40s ${RED}%s${NC}\n" "Critical violations:" "${#CRITICAL_VIOLATIONS[@]}"
    printf "  %-40s ${YELLOW}%s${NC}\n" "Warnings:" "${#WARNING_VIOLATIONS[@]}"
    printf "  %-40s ${GREEN}%s${NC}\n" "Info items:" "${#INFO_ITEMS[@]}"
    echo -e "${BOLD}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Container status
    if [[ ${#CONTAINER_IMAGE[@]} -gt 0 ]]; then
        echo -e "${BOLD}┌── Container Status ─────────────────────────────────────────┐${NC}"
        printf "  ${BOLD}%-25s %-30s %-10s${NC}\n" "CONTAINER" "IMAGE" "STATUS"
        echo "  ──────────────────────────────────────────────────────────────"
        # Sort containers: critical first, then warning, then ok
        for cname in "${!CONTAINER_IMAGE[@]}"; do
            local cimage="${CONTAINER_IMAGE[${cname}]}"
            local cstatus="${CONTAINER_STATUS[${cname}]:-ok}"
            local status_color="${GREEN}"
            case "${cstatus}" in
                critical) status_color="${RED}${BOLD}" ;;
                warning)  status_color="${YELLOW}" ;;
            esac
            # Truncate image name if too long
            local cimage_short="${cimage:0:28}"
            if [[ ${#cimage} -gt 28 ]]; then cimage_short+=".."; fi
            printf "  %-25s %-30s ${status_color}%-10s${NC}\n" \
                "${cname:0:24}" "${cimage_short}" "${cstatus}"
        done
        echo -e "${BOLD}└──────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    # Critical violations
    if [[ ${#CRITICAL_VIOLATIONS[@]} -gt 0 ]]; then
        echo -e "${RED}${BOLD}┌── CRITICAL Violations ──────────────────────────────────────┐${NC}"
        for v in "${CRITICAL_VIOLATIONS[@]}"; do
            echo -e "  ${RED}${BOLD}[CRIT]${NC} ${v}"
        done
        echo -e "${RED}${BOLD}└──────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    # Warnings
    if [[ ${#WARNING_VIOLATIONS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}┌── WARNINGS ──────────────────────────────────────────────────┐${NC}"
        for v in "${WARNING_VIOLATIONS[@]}"; do
            echo -e "  ${YELLOW}[WARN]${NC} ${v}"
        done
        echo -e "${YELLOW}${BOLD}└──────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    # Info items
    if [[ ${#INFO_ITEMS[@]} -gt 0 ]]; then
        echo -e "${BOLD}┌── INFO ─────────────────────────────────────────────────────┐${NC}"
        for v in "${INFO_ITEMS[@]}"; do
            echo -e "  ${CYAN}[INFO]${NC} ${v}"
        done
        echo -e "${BOLD}└──────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    # Fix suggestions
    if [[ "${SHOW_FIXES:-false}" == "true" ]] && [[ ${#FIX_COMMANDS[@]} -gt 0 ]]; then
        echo -e "${MAGENTA}${BOLD}┌── Fix Suggestions (DO NOT EXECUTE BLINDLY) ────────────────┐${NC}"
        echo -e "  ${MAGENTA}Review each command before running. Some are destructive.${NC}"
        echo ""
        for f in "${FIX_COMMANDS[@]}"; do
            local f_desc f_cmd
            f_desc="$(echo "${f}" | cut -d'|' -f1 | xargs)"
            f_cmd="$(echo "${f}" | cut -d'|' -f2-)"
            echo -e "  ${BOLD}Action:${NC} ${f_desc}"
            echo -e "  ${CYAN}Command:${NC}"
            echo "    ${f_cmd}"
            echo ""
        done
        echo -e "${MAGENTA}${BOLD}└──────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    # Overall verdict
    if [[ ${#CRITICAL_VIOLATIONS[@]} -gt 0 ]]; then
        echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}${BOLD}  VERDICT: FAILED — ${#CRITICAL_VIOLATIONS[@]} CRITICAL violation(s)${NC}"
        echo -e "${RED}${BOLD}  Fix critical violations before deploying to this server.${NC}"
        echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    elif [[ ${#WARNING_VIOLATIONS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}${BOLD}  VERDICT: WARNINGS — ${#WARNING_VIOLATIONS[@]} issue(s) to address${NC}"
        echo -e "${YELLOW}${BOLD}  Schedule fixes within 7 days.${NC}"
        echo -e "${YELLOW}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    else
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}${BOLD}  VERDICT: PASSED — Role compliant${NC}"
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    fi
    echo ""
}

# ------------------------------------------------------------------------------
# Main Orchestration
# ------------------------------------------------------------------------------

main() {
    local forced_role=""
    local do_report=false
    local do_json_output=false
    local quiet_mode=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --server)
                forced_role="${2}"
                shift 2
                ;;
            --fix)
                SHOW_FIXES="true"
                shift
                ;;
            --report)
                do_report=true
                shift
                ;;
            --json)
                do_json_output=true
                do_report=true
                shift
                ;;
            --quiet)
                quiet_mode=true
                shift
                ;;
            --no-lock)
                SKIP_LOCK="true"
                shift
                ;;
            --debug)
                DEBUG=1
                export DEBUG
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: ${1}"
                usage
                exit 3
                ;;
        esac
    done

    # Banner (suppress in quiet mode or JSON mode)
    if [[ "${quiet_mode}" != "true" ]] && [[ "${do_json_output}" != "true" ]]; then
        echo -e "${BOLD}Wheeler Enterprise — Server Role Enforcement${NC}"
        echo ""
    fi

    # Check prerequisites
    if ! check_prerequisites; then
        log_critical "Prerequisite check failed. Cannot continue."
        exit 3
    fi

    # Acquire lock (prevent concurrent runs)
    if ! acquire_lock; then
        log_error "Could not acquire lock. Another audit may be running."
        exit 3
    fi

    # Determine server role
    if ! determine_role "${forced_role}"; then
        exit 3
    fi

    # Print banner
    if [[ "${quiet_mode}" != "true" ]] && [[ "${do_json_output}" != "true" ]]; then
        banner "${DETECTED_ROLE}"
    fi

    # --------------------------------------------------------------------------
    # Phase 1: Container Inspection
    # --------------------------------------------------------------------------
    if [[ "${quiet_mode}" != "true" ]]; then
        echo -e "${BOLD}── Phase 1: Container Inspection ──${NC}"
    fi

    case "${DETECTED_ROLE}" in
        edge)   check_forbidden_containers_edge ;;
        aiops)  check_forbidden_containers_aiops ;;
        coredb) check_forbidden_containers_coredb ;;
    esac

    # --------------------------------------------------------------------------
    # Phase 2: Port Binding Checks
    # --------------------------------------------------------------------------
    if [[ "${quiet_mode}" != "true" ]]; then
        echo ""
        echo -e "${BOLD}── Phase 2: Port Binding Checks ──${NC}"
    fi

    case "${DETECTED_ROLE}" in
        edge)   check_ports_edge ;;
        aiops)  check_ports_aiops ;;
        coredb) check_ports_coredb ;;
    esac

    # --------------------------------------------------------------------------
    # Phase 3: Docker Label Compliance
    # --------------------------------------------------------------------------
    if [[ "${quiet_mode}" != "true" ]]; then
        echo ""
        echo -e "${BOLD}── Phase 3: Docker Label Compliance ──${NC}"
    fi

    check_docker_labels

    # --------------------------------------------------------------------------
    # Phase 4: Volume Placement
    # --------------------------------------------------------------------------
    if [[ "${quiet_mode}" != "true" ]]; then
        echo ""
        echo -e "${BOLD}── Phase 4: Volume Placement ──${NC}"
    fi

    case "${DETECTED_ROLE}" in
        edge)   check_volumes_edge ;;
        coredb) check_volumes_coredb ;;
        aiops)
            log_info "  AIOPS volume checks: ensuring no backup volumes >10GB..."
            # Check for backup volumes on AIOPS
            local backup_dirs=("/var/backups" "/backup" "/data/backups" "/tmp/backups")
            for bd in "${backup_dirs[@]}"; do
                if [[ -d "${bd}" ]]; then
                    local dir_size
                    dir_size="$(du -sb "${bd}" 2>/dev/null | awk '{print $1}' || echo 0)"
                    # 10 GB = 10737418240 bytes
                    if [[ "${dir_size}" -gt 10737418240 ]]; then
                        local dir_size_gb
                        dir_size_gb="$(echo "scale=2; ${dir_size} / 1073741824" | bc 2>/dev/null || echo '>10')"
                        add_violation "warning" "volume:backups" \
                            "Backup directory '${bd}' is ${dir_size_gb}GB — backups should be on COREDB, not AIOPS"
                        add_fix "# Sync to COREDB MinIO:\n#   mc mirror ${bd}/ myminio/backups/ && rm -rf ${bd}/*" \
                            "Migrate backups to COREDB"
                    fi
                fi
            done
            ;;
    esac

    # --------------------------------------------------------------------------
    # Phase 5: System Checks
    # --------------------------------------------------------------------------
    if [[ "${quiet_mode}" != "true" ]]; then
        echo ""
        echo -e "${BOLD}── Phase 5: System Checks ──${NC}"
    fi

    check_tailscale_connectivity

    # --------------------------------------------------------------------------
    # Report Generation
    # --------------------------------------------------------------------------
    if [[ "${do_report}" == "true" ]]; then
        if [[ "${quiet_mode}" != "true" ]]; then
            echo ""
            echo -e "${BOLD}── Generating Reports ──${NC}"
        fi

        generate_json_report
        export_prometheus_metrics

        if [[ "${do_json_output}" == "true" ]]; then
            # Output JSON to stdout
            echo "${JSON_REPORT}"
        else
            print_terminal_report
        fi
    else
        # Always export Prometheus metrics (for monitoring)
        export_prometheus_metrics

        # Terminal summary (unless quiet)
        if [[ "${quiet_mode}" != "true" ]]; then
            print_terminal_report
        fi
    fi

    # --------------------------------------------------------------------------
    # Determine Exit Code
    # --------------------------------------------------------------------------
    if [[ ${#CRITICAL_VIOLATIONS[@]} -gt 0 ]]; then
        exit 2
    elif [[ ${#WARNING_VIOLATIONS[@]} -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# ------------------------------------------------------------------------------
# Entry Point
# ------------------------------------------------------------------------------

# Ensure required directories exist
mkdir -p "${LOG_DIR}"
mkdir -p "${METRICS_DIR}"

# Run main
main "${@}"
