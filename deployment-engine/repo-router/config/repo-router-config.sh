#!/usr/bin/env bash
# =============================================================================
# Repo Router - Configuration
# Source: config/repo-router-config.sh
# Description: Central configuration for the Wheeler Repo Router system.
#              Sourced by orchestrator/repo-router.sh at startup.
# =============================================================================

# ---------------------------------------------------------------------------
# Node identification - the router must know which node it runs on
# ---------------------------------------------------------------------------
NODE_TYPE="${NODE_TYPE:-aiops}"  # aiops | hostinger | coredb
NODE_HOSTNAME="${NODE_HOSTNAME:-$(hostname)}"
NODE_IP="${NODE_IP:-127.0.0.1}"

# ---------------------------------------------------------------------------
# Repo Router base paths
# ---------------------------------------------------------------------------
REPO_ROUTER_BASE="/root/deployment-engine/repo-router"
REPO_ROUTER_TEMPLATES="${REPO_ROUTER_BASE}/templates"
REPO_ROUTER_ENFORCEMENT="${REPO_ROUTER_BASE}/enforcement"
REPO_ROUTER_CONFIG="${REPO_ROUTER_BASE}/config"
REPO_ROUTER_ORCHESTRATOR="${REPO_ROUTER_BASE}/orchestrator"
REPO_ROUTER_LOGS="/var/log/repo-router"
REPO_ROUTER_STATE="${REPO_ROUTER_CONFIG}/router-state.json"

# ---------------------------------------------------------------------------
# Enforcement file paths
# ---------------------------------------------------------------------------
PORT_ALLOCATION_TABLE="${REPO_ROUTER_ENFORCEMENT}/port-allocation-table.json"
ROUTE_REGISTRY="${REPO_ROUTER_ENFORCEMENT}/route-registry.json"

# ---------------------------------------------------------------------------
# Deployment path constants
# ---------------------------------------------------------------------------
DEPLOY_BASE="/opt"
DEPLOY_DOCKER_COMPOSE="/usr/local/bin/docker-compose"
DEPLOY_PM2_CONFIG="ecosystem.config.js"
DEPLOY_NGINX_AVAILABLE="/etc/nginx/sites-available"
DEPLOY_NGINX_ENABLED="/etc/nginx/sites-enabled"

# AI Ops deployment directories
AIOPS_DEPLOY_PATH="${DEPLOY_BASE}/aiops"
SURPLUSAI_PATH="${AIOPS_DEPLOY_PATH}/surplusai"
PRIVATE_AI_PATH="${AIOPS_DEPLOY_PATH}/private-ai"
PREDICTION_RADAR_PATH="${AIOPS_DEPLOY_PATH}/prediction-radar"
HEALTHCHECKS_PATH="${AIOPS_DEPLOY_PATH}/healthchecks"
CHANGEDETECTION_PATH="${AIOPS_DEPLOY_PATH}/changedetection"
LANGFLOW_PATH="${AIOPS_DEPLOY_PATH}/langflow"
N8N_PATH="${AIOPS_DEPLOY_PATH}/n8n"
GRAFANA_PATH="${AIOPS_DEPLOY_PATH}/grafana"
PROMETHEUS_PATH="${AIOPS_DEPLOY_PATH}/prometheus"
LOKI_PATH="${AIOPS_DEPLOY_PATH}/loki"

# Hostinger deployment directories
HOSTINGER_DEPLOY_PATH="${DEPLOY_BASE}/hostinger"
FRGCRM_PATH="${HOSTINGER_DEPLOY_PATH}/frgcrm"
OPENCLAW_PATH="${HOSTINGER_DEPLOY_PATH}/openclaw"
REVENUE_AUTOMATION_PATH="${HOSTINGER_DEPLOY_PATH}/revenue-automation"

# Core DB deployment directories
COREDB_DEPLOY_PATH="${DEPLOY_BASE}/coredb"
POSTGRES_PATH="${COREDB_DEPLOY_PATH}/postgres"
REDIS_PATH="${COREDB_DEPLOY_PATH}/redis"
MINIO_PATH="${COREDB_DEPLOY_PATH}/minio"
RABBITMQ_PATH="${COREDB_DEPLOY_PATH}/rabbitmq"

# ---------------------------------------------------------------------------
# Network constants
# ---------------------------------------------------------------------------
# Internal bind address (all services bind to localhost by default)
BIND_INTERNAL="127.0.0.1"

# Tailscale CGNAT range
TAILSCALE_CGNAT="100.64.0.0/10"

# AI Ops node details
AIOPS_HOST="${AIOPS_HOST:-10.0.0.10}"
AIOPS_DOMAIN="${AIOPS_DOMAIN:-aiops.wheeler.internal}"
AIOPS_TAILSCALE_HOST="${AIOPS_TAILSCALE_HOST:-aiops-node.tailnet-abc123.ts.net}"

# Hostinger node details
HOSTINGER_HOST="${HOSTINGER_HOST:-10.0.0.20}"
HOSTINGER_DOMAIN="${HOSTINGER_DOMAIN:-hostinger.wheeler.internal}"
HOSTINGER_TAILSCALE_HOST="${HOSTINGER_TAILSCALE_HOST:-hostinger-node.tailnet-abc123.ts.net}"

# Core DB node details
COREDB_HOST="${COREDB_HOST:-10.0.0.30}"
COREDB_DOMAIN="${COREDB_DOMAIN:-coredb.wheeler.internal}"
COREDB_TAILSCALE_HOST="${COREDB_TAILSCALE_HOST:-coredb-node.tailnet-abc123.ts.net}"

# Default ports for common services
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
LOKI_PORT=3100
ALERTMANAGER_PORT=9093
NODE_EXPORTER_PORT=9100
POSTGRES_PORT=5432
REDIS_PORT=6379
MINIO_PORT=9000
PGBOUNCER_PORT=6432

# ---------------------------------------------------------------------------
# Threshold constants
# ---------------------------------------------------------------------------
# Risk scores (0-100)
RISK_THRESHOLD_SAFE=30
RISK_THRESHOLD_MODERATE=60
RISK_THRESHOLD_HIGH=85

# Pipeline phase timeouts (seconds)
PHASE_TIMEOUT_INTAKE=120
PHASE_TIMEOUT_SCAN=300
PHASE_TIMEOUT_BUILD=600
PHASE_TIMEOUT_DEPLOY=300
PHASE_TIMEOUT_HEALTH=60
PHASE_TIMEOUT_ROLLBACK=120

# Health check thresholds
HEALTH_CHECK_RETRIES=3
HEALTH_CHECK_INTERVAL=5
HEALTH_CHECK_TIMEOUT=10

# Drift detection thresholds
DRIFT_MAX_IMAGE_AGE_DAYS=7
DRIFT_MAX_CONFIG_AGE_DAYS=30
DRIFT_WARN_PORT_CHANGES=2

# QA score thresholds
QA_SCORE_PASS=80
QA_SCORE_PERFECT=100

# ---------------------------------------------------------------------------
# Feature flags
# ---------------------------------------------------------------------------
FEATURE_AUTO_DEPLOY="${FEATURE_AUTO_DEPLOY:-true}"
FEATURE_AUTO_ROLLBACK="${FEATURE_AUTO_ROLLBACK:-true}"
FEATURE_DRIFT_DETECTION="${FEATURE_DRIFT_DETECTION:-true}"
FEATURE_HEALTH_GATE="${FEATURE_HEALTH_GATE:-true}"
FEATURE_ZT_VALIDATION="${FEATURE_ZT_VALIDATION:-true}"
FEATURE_QA_GATE="${FEATURE_QA_GATE:-true}"
FEATURE_SLACK_NOTIFY="${FEATURE_SLACK_NOTIFY:-false}"
FEATURE_PROMETHEUS_METRICS="${FEATURE_PROMETHEUS_METRICS:-true}"
FEATURE_TAILSCALE_ONLY="${FEATURE_TAILSCALE_ONLY:-false}"
FEATURE_STRICT_MODE="${FEATURE_STRICT_MODE:-false}"

# ---------------------------------------------------------------------------
# Color output constants
# ---------------------------------------------------------------------------
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Log a message with timestamp and level
log_message() {
    local level="$1"
    local message="$2"
    local color=""
    case "$level" in
        INFO)    color="${GREEN}" ;;
        WARN)    color="${YELLOW}" ;;
        ERROR)   color="${RED}" ;;
        DEBUG)   color="${DIM}" ;;
        FATAL)   color="${RED}${BOLD}" ;;
        PHASE)   color="${CYAN}${BOLD}" ;;
        *)       color="${NC}" ;;
    esac
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}]${NC} ${message}"
}

# Check if a required command is available
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_message "FATAL" "Required command not found: ${cmd}"
        exit 1
    fi
}

# Check if a required file exists
require_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_message "FATAL" "Required file not found: ${file}"
        exit 1
    fi
}

# Load JSON file and validate
load_json() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_message "ERROR" "JSON file not found: ${file}"
        return 1
    fi
    if ! command -v jq &>/dev/null; then
        log_message "ERROR" "jq is required but not installed"
        return 1
    fi
    if ! jq '.' "$file" &>/dev/null; then
        log_message "ERROR" "Invalid JSON in: ${file}"
        return 1
    fi
    return 0
}

# Verify port is available
check_port_available() {
    local port="$1"
    local host="${2:-127.0.0.1}"
    if ss -tlnp "sport = :${port}" 2>/dev/null | grep -q "${host}:${port}"; then
        return 1
    fi
    return 0
}

# Verify binding to 127.0.0.1
check_bind_is_internal() {
    local port="$1"
    if ss -tlnp "sport = :${port}" 2>/dev/null | grep -q "0.0.0.0:${port}"; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Validate environment on source
# ---------------------------------------------------------------------------
require_command "jq"
require_command "ss" 2>/dev/null || true

mkdir -p "${REPO_ROUTER_LOGS}"

log_message "INFO" "Repo Router configuration loaded"
log_message "INFO" "Node type: ${NODE_TYPE} | Hostname: ${NODE_HOSTNAME}"
log_message "INFO" "State file: ${REPO_ROUTER_STATE}"
log_message "INFO" "Feature flags: strict=${FEATURE_STRICT_MODE} auto-deploy=${FEATURE_AUTO_DEPLOY} drift-scan=${FEATURE_DRIFT_DETECTION}"
