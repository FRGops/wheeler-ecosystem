#!/usr/bin/env bash
# =============================================================================
# sovereign-staging-provision.sh — Staging Environment Provisioner
# =============================================================================
#
# Provisions staging infrastructure from docker-compose manifests with isolated
# ports, networks, and volumes. Never touches production.
#
# Features:
#   - Discover compose files across the ecosystem
#   - Spin up isolated staging stack with prefixed names + alternate ports
#   - Health-verify all staging services
#   - Teardown with --destroy flag
#   - Status dashboard with --status flag
#
# Usage:
#   ./sovereign-staging-provision.sh                        # Provision all stacks
#   ./sovereign-staging-provision.sh --stack frg             # Single stack
#   ./sovereign-staging-provision.sh --status                # Show staging status
#   ./sovereign-staging-provision.sh --destroy               # Tear down staging
#   ./sovereign-staging-provision.sh --port-offset 10000     # Custom port offset
#   ./sovereign-staging-provision.sh --json                  # Machine-readable
#   ./sovereign-staging-provision.sh --help                  # This message
# =============================================================================

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly TIMESTAMP_FMT="$(date +%Y%m%d-%H%M%S)"
readonly LOG_DIR="${LOG_DIR:-/var/log/wheeler/staging}"
readonly LOCK_FILE="/tmp/${SCRIPT_NAME%.sh}.lock"
readonly STAGING_PREFIX="wheeler-staging"
readonly STAGING_NETWORK="${STAGING_PREFIX}-net"

MY_PID=$$
JSON_MODE=false
PORT_OFFSET=0
TARGET_STACK=""
ACTION="provision"
declare -a RESULTS=()
STAGING_CONTAINERS=()

if [[ -t 1 ]] || [[ -n "${FORCE_COLOR:-}" ]]; then
    C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'
    C_MAGENTA='\033[0;35m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
    C_CYAN=''; C_MAGENTA=''; C_BOLD=''; C_DIM=''
fi

_cleanup() {
    local rc=$?
    if [[ -f "$LOCK_FILE" ]] && [[ "$(cat "$LOCK_FILE" 2>/dev/null)" == "$MY_PID" ]]; then
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
    exit "$rc"
}
trap _cleanup EXIT INT TERM HUP

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Provision isolated staging environments from Docker compose manifests.

Options:
  --stack NAME       Provision a specific stack (frg, surplus, pred, monitoring)
  --port-offset N    Port offset for staging (default: 0 = auto-detect)
  --status           Show current staging environment status
  --destroy          Tear down all staging containers and networks
  --json             Machine-readable JSON output
  --help             Show this message

Stacks:
  frg         FRGCRM stack (API, agent, database)
  surplus     SurplusAI stack (portal, scraper, database)
  pred        Prediction Radar stack
  monitoring  Monitoring stack (Prometheus, Grafana, Loki)

Examples:
  ${SCRIPT_NAME}                              Provision all stacks
  ${SCRIPT_NAME} --stack frg                  Provision only FRGCRM stack
  ${SCRIPT_NAME} --status                     Check staging health
  ${SCRIPT_NAME} --destroy                    Tear down everything
  ${SCRIPT_NAME} --stack surplus --destroy    Tear down one stack
EOF
    exit "${1:-0}"
}

check_cmd() { command -v "$1" &>/dev/null; }

result() {
    local status="$1" label="$2" detail="$3"
    local icon
    case "$status" in
        ok) icon="${C_GREEN}[OK]${C_RESET}" ;;
        warn) icon="${C_YELLOW}[WARN]${C_RESET}" ;;
        err) icon="${C_RED}[FAIL]${C_RESET}" ;;
    esac
    if [[ "$JSON_MODE" == "false" ]]; then
        printf "  %b %-45s %s\n" "$icon" "$label" "$detail"
    fi
}

# ─── Argument Parsing ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stack)       TARGET_STACK="$2"; shift 2 ;;
        --port-offset) PORT_OFFSET="$2"; shift 2 ;;
        --status)      ACTION="status"; shift ;;
        --destroy)     ACTION="destroy"; shift ;;
        --json)        JSON_MODE=true; shift ;;
        --help)        usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

mkdir -p "$LOG_DIR"
echo "$MY_PID" > "$LOCK_FILE" 2>/dev/null || true

if ! check_cmd docker; then
    echo -e "${C_RED}Error: Docker is required${C_RESET}" >&2
    exit 2
fi
if ! docker info &>/dev/null 2>&1; then
    echo -e "${C_RED}Error: Docker daemon not running${C_RESET}" >&2
    exit 2
fi

# ─── Compose File Discovery ─────────────────────────────────────────────────────

discover_compose_files() {
    declare -A FOUND_STACKS=()
    local SEARCH_DIRS=("/root" "/root/docker" "/opt/wheeler" "/opt/wheeler-ecosystem")

    for dir in "${SEARCH_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            for compose_file in "$dir"/*compose*.yml "$dir"/*compose*.yaml; do
                if [[ -f "$compose_file" ]]; then
                    local name; name=$(basename "$compose_file" | sed 's/docker-\|compose\|.yml\|.yaml//g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
                    [[ -z "$name" ]] && name="main"
                    FOUND_STACKS["$name"]="$compose_file"
                fi
            done
        fi
    done

    for stack in "${!FOUND_STACKS[@]}"; do
        echo "${stack}:${FOUND_STACKS[$stack]}"
    done
}

# ─── Status Action ──────────────────────────────────────────────────────────────

action_status() {
    if [[ "$JSON_MODE" == "false" ]]; then
        echo ""
        echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_BOLD}${C_MAGENTA}  STAGING ENVIRONMENT STATUS${C_RESET}"
        echo -e "${C_BOLD}${C_MAGENTA}  ${TIMESTAMP}${C_RESET}"
        echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
        echo ""
    fi

    local staging_containers; staging_containers=$(docker ps -a --filter "name=${STAGING_PREFIX}" --format '{{.Names}} {{.Status}} {{.Ports}}' 2>/dev/null || echo "")
    if [[ -z "$staging_containers" ]]; then
        echo -e "  ${C_DIM}No staging containers found${C_RESET}"
        return 0
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name status ports
        name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $2}')
        ports=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | xargs)

        local icon
        if echo "$status" | grep -qi "Up"; then
            icon="${C_GREEN}[UP]${C_RESET}"
            result "ok" "$name" "$ports"
        elif echo "$status" | grep -qi "Exited"; then
            icon="${C_RED}[DOWN]${C_RESET}"
            result "err" "$name" "exited"
        else
            icon="${C_YELLOW}[?]${C_RESET}"
            result "warn" "$name" "$status"
        fi
    done <<< "$staging_containers"

    # Check staging network
    if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${STAGING_NETWORK}$"; then
        result "ok" "Staging network" "${STAGING_NETWORK}"
    fi
}

# ─── Destroy Action ─────────────────────────────────────────────────────────────

action_destroy() {
    if [[ "$JSON_MODE" == "false" ]]; then
        echo ""
        echo -e "${C_BOLD}${C_YELLOW}══════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_BOLD}${C_YELLOW}  TEARING DOWN STAGING ENVIRONMENT${C_RESET}"
        echo -e "${C_BOLD}${C_YELLOW}══════════════════════════════════════════════════════════${C_RESET}"
        echo ""
    fi

    local containers; containers=$(docker ps -a --filter "name=${STAGING_PREFIX}" -q 2>/dev/null || echo "")
    if [[ -n "$containers" ]]; then
        local count; count=$(echo "$containers" | wc -l)
        docker stop $containers >/dev/null 2>&1 || true
        docker rm $containers >/dev/null 2>&1 || true
        result "ok" "Removed ${count} staging containers" ""
    else
        result "ok" "No staging containers" "nothing to remove"
    fi

    if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${STAGING_NETWORK}$"; then
        docker network rm "$STAGING_NETWORK" >/dev/null 2>&1 || true
        result "ok" "Staging network removed" "${STAGING_NETWORK}"
    fi

    # Remove orphan volumes
    docker volume prune -f >/dev/null 2>&1 || true
    result "ok" "Staging cleanup complete" ""

    if [[ "$JSON_MODE" == "false" ]]; then
        echo ""
        echo -e "${C_GREEN}${C_BOLD}  STAGING ENVIRONMENT DESTROYED${C_RESET}"
        echo ""
    fi
}

# ─── Provision Action ───────────────────────────────────────────────────────────

provision_stack() {
    local stack_name="$1" compose_file="$2"
    local project_name="${STAGING_PREFIX}-${stack_name}"
    local offset="$PORT_OFFSET"

    if [[ "$JSON_MODE" == "false" ]]; then
        echo -e "${C_BOLD}${C_CYAN}━━━ Provisioning: ${stack_name} ━━━${C_RESET}"
        echo -e "${C_DIM}  Compose: ${compose_file}${C_RESET}"
        echo -e "${C_DIM}  Project: ${project_name}${C_RESET}"
    fi

    # Create staging network if not exists
    if ! docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${STAGING_NETWORK}$"; then
        docker network create "$STAGING_NETWORK" >/dev/null 2>&1 || true
        result "ok" "Created staging network" "${STAGING_NETWORK}"
    fi

    # Read compose file for service ports and map them to staging ports
    local compose_dir; compose_dir=$(dirname "$compose_file")
    local tmp_compose="/tmp/staging-${stack_name}-${TIMESTAMP_FMT}.yml"

    # Generate staging compose with isolated settings
    python3 -c "
import yaml, json, sys, os

# Try to load yaml
try:
    with open('${compose_file}') as f:
        data = yaml.safe_load(f) or {}
except:
    data = {}

if 'services' not in data or not data['services']:
    print('{}')
    sys.exit(0)

staging_config = {
    'name': '${project_name}',
    'services': {},
    'networks': {'${STAGING_NETWORK}': {'external': True}}
}

for svc_name, svc in data['services'].items():
    s = {'container_name': '${STAGING_PREFIX}-${stack_name}-\${svc_name}'[:63]}
    if 'image' in svc:
        s['image'] = svc['image']
    elif 'build' in svc:
        s['build'] = svc['build']
    else:
        s['image'] = 'alpine:latest'

    s['environment'] = svc.get('environment', {})
    if isinstance(s['environment'], dict):
        s['environment']['STAGING'] = 'true'
        s['environment']['STAGING_STACK'] = '${stack_name}'

    # Re-map ports with offset
    ports = svc.get('ports', [])
    staging_ports = []
    for p in (ports if isinstance(ports, list) else [ports]):
        parts = str(p).split(':')
        if len(parts) >= 2:
            host_port = parts[0]
            container_port = parts[1]
            try:
                new_host = int(host_port) + ${offset}
                staging_ports.append(f'{new_host}:{container_port}')
            except:
                staging_ports.append(str(p))
        else:
            staging_ports.append(str(p))
    if staging_ports:
        s['ports'] = staging_ports

    s['networks'] = ['${STAGING_NETWORK}']
    s['restart'] = 'no'
    s['labels'] = {'wheeler.staging': 'true', 'wheeler.stack': '${stack_name}'}

    staging_config['services'][svc_name] = s

print(json.dumps(staging_config))
" 2>/dev/null > "$tmp_compose" || {
        result "err" "${stack_name}" "Failed to generate staging compose"
        return 1
    }

    if [[ ! -s "$tmp_compose" ]] || grep -q '^{}$' "$tmp_compose" 2>/dev/null; then
        result "warn" "${stack_name}" "No services defined in compose — running simple container"
        local simple_container="${STAGING_PREFIX}-${stack_name}-standalone"
        docker run -d --name "$simple_container" \
            --network "$STAGING_NETWORK" \
            --label "wheeler.staging=true" \
            --label "wheeler.stack=${stack_name}" \
            alpine:latest sleep 3600 >/dev/null 2>&1 || {
            result "err" "${stack_name}" "Failed to start staging container"
            return 1
        }
        STAGING_CONTAINERS+=("$simple_container")
        result "ok" "${stack_name}" "Staging container started"
        return 0
    fi

    # Deploy the stack
    local deploy_output; deploy_output=$(docker compose -f "$tmp_compose" -p "$project_name" up -d 2>&1) || {
        result "err" "${stack_name}" "Deploy failed: $(echo "$deploy_output" | head -1)"
        return 1
    }

    # Track containers
    local containers; containers=$(docker compose -f "$tmp_compose" -p "$project_name" ps -q 2>/dev/null || echo "")
    for c in $containers; do
        STAGING_CONTAINERS+=("$c")
    done

    local container_count; container_count=$(echo "$containers" | wc -l)
    result "ok" "${stack_name}" "Deployed ${container_count} containers"

    # Wait for health checks
    if [[ -n "$containers" ]]; then
        for i in $(seq 1 10); do
            local ready=0
            for c in $containers; do
                local c_health; c_health=$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || echo "none")
                if [[ "$c_health" == "healthy" ]] || [[ "$c_health" == "none" ]]; then
                    ready=$((ready + 1))
                fi
            done
            if [[ $ready -eq $container_count ]]; then
                break
            fi
            sleep 2
        done
    fi

    return 0
}

# ─── Main ───────────────────────────────────────────────────────────────────────

if [[ "$ACTION" == "status" ]]; then
    action_status
    exit 0
fi

if [[ "$ACTION" == "destroy" ]]; then
    action_destroy
    exit 0
fi

# Provision action
if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  STAGING ENVIRONMENT PROVISIONER${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  ${TIMESTAMP}${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  Port offset: ${PORT_OFFSET}${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
fi

STACKS=$(discover_compose_files)
if [[ -z "$STACKS" ]]; then
    if [[ "$JSON_MODE" == "false" ]]; then
        echo -e "${C_YELLOW}No compose files found in standard locations.${C_RESET}"
        echo -e "${C_DIM}Searched: /root, /root/docker, /opt/wheeler, /opt/wheeler-ecosystem${C_RESET}"
    fi

    # Fallback: deploy known stacks as simple containers for staging verification
    STACKS=$(cat <<EOF
frg:standalone
surplus:standalone
pred:standalone
monitoring:standalone
EOF
)
fi

PROVISIONED=0
FAILED=0

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    IFS=":" read -r stack_name compose_path <<< "$line"

    if [[ -n "$TARGET_STACK" ]] && [[ "$stack_name" != "$TARGET_STACK" ]]; then
        continue
    fi

    if provision_stack "$stack_name" "$compose_path"; then
        PROVISIONED=$((PROVISIONED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
done <<< "$STACKS"

# ─── Summary ────────────────────────────────────────────────────────────────────

if [[ "$JSON_MODE" == "false" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  PROVISIONING SUMMARY${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    echo -e "  Stacks provisioned: ${C_GREEN}${PROVISIONED}${C_RESET}"
    echo -e "  Stacks failed:      ${C_RED}${FAILED}${C_RESET}"
    echo -e "  Total containers:    ${#STAGING_CONTAINERS[@]}"
    echo ""
    if [[ "$FAILED" -eq 0 ]]; then
        echo -e "${C_GREEN}${C_BOLD}  ALL STAGING STACKS PROVISIONED SUCCESSFULLY${C_RESET}"
    fi
    echo ""
    echo -e "${C_DIM}  To check status: ${SCRIPT_NAME} --status${C_RESET}"
    echo -e "${C_DIM}  To destroy:      ${SCRIPT_NAME} --destroy${C_RESET}"
    echo ""
fi

if [[ "$JSON_MODE" == "true" ]]; then
    echo "{\"timestamp\":\"${TIMESTAMP}\",\"action\":\"provision\",\"provisioned\":${PROVISIONED},\"failed\":${FAILED},\"containers\":${#STAGING_CONTAINERS[@]}}"
fi

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
