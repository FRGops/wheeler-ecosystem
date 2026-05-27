#!/usr/bin/env bash
# =============================================================================
# repowire/build-orchestrator.sh — Wheeler Build Pipeline Repowire Orchestrator
# =============================================================================
# Wires the repowire P2P agent mesh (:8377) into every phase of the Wheeler
# 7-gate autonomous build pipeline (BUILD_PIPELINE.md).
#
# Integrated phases (8-phase pipeline):
#   DISCOVER -> PLAN -> ARCHITECT -> IMPLEMENT -> TEST -> REVIEW+SECURITY -> VERIFY+FINAL BOSS
#
# For each phase, the orchestrator broadcasts to the appropriate repowire
# circles and peers so the entire agent mesh has build awareness.
#
# Usage (standalone CLI):
#   ./build-orchestrator.sh pre-build  "<task_name>"           — pre-build intent + conflict check
#   ./build-orchestrator.sh phase      "<phase>" "<status>" [detail] — notify phase lifecycle
#   ./build-orchestrator.sh register-agent "<name>" "<circle>" [role]  — register agent as peer
#   ./build-orchestrator.sh complete   "<score>" [unverified_list]     — broadcast final scorecard
#   ./build-orchestrator.sh auto-wire  "<repo_path>" [repo_name]       — create peer config for new repo
#   ./build-orchestrator.sh check-mesh                                  — verify mesh reachability
#   ./build-orchestrator.sh status                                      — print build+mach state
#
# Usage (sourced):
#   source build-orchestrator.sh
#   build_orchestrator_pre_build "feat/add-stripe-webhook"
#   build_orchestrator_phase "DISCOVER" "pass" "3 agents deployed"
#   build_orchestrator_register_agent "lead-intelligence" "wheeler-growth"
#   build_orchestrator_complete "100" "none"
#
# Design principles:
#   FAIL-OPEN:   repowire unreachable? Log and continue. Never blocks a build.
#   IDEMPOTENT:  safe to source twice, safe to call same phase twice.
#   SELF-LOGGING: activity to /var/log/repowire/build-orchestrator.log
#   STATE-LOCKED: /var/lib/repowire/build-orchestrator/ — JSON state per build
# =============================================================================

set -euo pipefail

# ─── Configuration (overridable via environment) ─────────────────────────────
REPOWIRE_API="${REPOWIRE_API:-http://127.0.0.1:8377}"
LOGFILE="${LOGFILE:-/var/log/repowire/build-orchestrator.log}"
STATE_DIR="${STATE_DIR:-/var/lib/repowire/build-orchestrator}"
ORCHESTRATOR_PEER="${ORCHESTRATOR_PEER:-wheeler-orchestrator}"
CURL_TIMEOUT="${CURL_TIMEOUT:-5}"
CURL_RETRIES="${CURL_RETRIES:-2}"
BUILD_ID=""

# Guards against double-sourcing
_BO_LOADED="${_BO_LOADED:-0}"

# ─── Phase-to-Circle Mapping (from BUILD_PIPELINE.md + agent-coordination.md) ─
#
# Each pipeline phase maps to a set of repowire circles that should be notified.
# The circles are defined in bridge.py and include both domain-specific and
# cross-cutting peers.
declare -A PHASE_CIRCLES
PHASE_CIRCLES[DISCOVER]="wheeler-core"
PHASE_CIRCLES[PLAN]="wheeler-core,wheeler-deploy"
PHASE_CIRCLES[ARCHITECT]="wheeler-core,wheeler-ops,wheeler-db"
PHASE_CIRCLES[IMPLEMENT]="wheeler-core"
PHASE_CIRCLES[TEST]="wheeler-core,wheeler-monitoring,wheeler-ops"
PHASE_CIRCLES[REVIEW]="wheeler-core,wheeler-security"
PHASE_CIRCLES[SECURITY]="wheeler-security,wheeler-compliance"
PHASE_CIRCLES[VERIFY]="wheeler-core,wheeler-monitoring,wheeler-deploy"
PHASE_CIRCLES[FINAL]="wheeler-core,wheeler-ops,wheeler-security,wheeler-deploy,wheeler-finance,wheeler-growth,wheeler-legal"

# Ordered pipeline sequence (for auto-progression display)
PIPELINE_SEQ=("DISCOVER" "PLAN" "ARCHITECT" "IMPLEMENT" "TEST" "REVIEW" "SECURITY" "VERIFY" "FINAL")

# ─── Circle-to-Peer resolution (for targeted notifications) ─────────────────
# Maps a circle name to a representative peer for direct notify calls.
declare -A CIRCLE_REP
CIRCLE_REP[wheeler-core]="wheeler-orchestrator"
CIRCLE_REP[wheeler-ops]="wheeler-infra"
CIRCLE_REP[wheeler-security]="wheeler-security"
CIRCLE_REP[wheeler-deploy]="wheeler-deploy"
CIRCLE_REP[wheeler-finance]="wheeler-financial"
CIRCLE_REP[wheeler-growth]="wheeler-growth"
CIRCLE_REP[wheeler-legal]="wheeler-compliance"
CIRCLE_REP[wheeler-db]="wheeler-db"
CIRCLE_REP[wheeler-monitoring]="wheeler-monitoring"
CIRCLE_REP[wheeler-revenue]="wheeler-revenue"

# ─── Agent-to-Domain mapping (from agent-coordination.md routing table) ─────
# This maps the first word/domain of agent types to their repowire circle.
# Agent coordination's routing table determines the domain from task type.
declare -A AGENT_DOMAIN_CIRCLE
AGENT_DOMAIN_CIRCLE[docker]="wheeler-ops"
AGENT_DOMAIN_CIRCLE[infra]="wheeler-ops"
AGENT_DOMAIN_CIRCLE[pm2]="wheeler-ops"
AGENT_DOMAIN_CIRCLE[network]="wheeler-ops"
AGENT_DOMAIN_CIRCLE[security]="wheeler-security"
AGENT_DOMAIN_CIRCLE[deploy]="wheeler-deploy"
AGENT_DOMAIN_CIRCLE[rollback]="wheeler-deploy"
AGENT_DOMAIN_CIRCLE[revenue]="wheeler-finance"
AGENT_DOMAIN_CIRCLE[cost]="wheeler-finance"
AGENT_DOMAIN_CIRCLE[financial]="wheeler-finance"
AGENT_DOMAIN_CIRCLE[monitoring]="wheeler-monitoring"
AGENT_DOMAIN_CIRCLE[observability]="wheeler-monitoring"
AGENT_DOMAIN_CIRCLE[github]="wheeler-core"
AGENT_DOMAIN_CIRCLE[database]="wheeler-db"
AGENT_DOMAIN_CIRCLE[db]="wheeler-db"
AGENT_DOMAIN_CIRCLE[ceo]="wheeler-core"
AGENT_DOMAIN_CIRCLE[executive]="wheeler-core"
AGENT_DOMAIN_CIRCLE[business]="wheeler-core"
AGENT_DOMAIN_CIRCLE[lead]="wheeler-growth"
AGENT_DOMAIN_CIRCLE[foreclosure]="wheeler-growth"
AGENT_DOMAIN_CIRCLE[county]="wheeler-growth"
AGENT_DOMAIN_CIRCLE[market]="wheeler-growth"
AGENT_DOMAIN_CIRCLE[seo]="wheeler-growth"
AGENT_DOMAIN_CIRCLE[competitor]="wheeler-growth"
AGENT_DOMAIN_CIRCLE[real-estate]="wheeler-growth"
AGENT_DOMAIN_CIRCLE[strategic]="wheeler-core"
AGENT_DOMAIN_CIRCLE[ai]="wheeler-core"
AGENT_DOMAIN_CIRCLE[predictive]="wheeler-core"
AGENT_DOMAIN_CIRCLE[vector]="wheeler-ops"
AGENT_DOMAIN_CIRCLE[embedding]="wheeler-ops"
AGENT_DOMAIN_CIRCLE[rag]="wheeler-core"
AGENT_DOMAIN_CIRCLE[memory]="wheeler-core"
AGENT_DOMAIN_CIRCLE[knowledge]="wheeler-core"
AGENT_DOMAIN_CIRCLE[compliance]="wheeler-legal"
AGENT_DOMAIN_CIRCLE[legal]="wheeler-legal"
AGENT_DOMAIN_CIRCLE[research]="wheeler-core"
AGENT_DOMAIN_CIRCLE[quality]="wheeler-ops"
AGENT_DOMAIN_CIRCLE[autonomous]="wheeler-core"

# ─── Helper: Ensure log + state dirs ────────────────────────────────────────
_bo_ensure_dirs() {
    mkdir -p "$(dirname "${LOGFILE}")" 2>/dev/null || true
    mkdir -p "${STATE_DIR}" 2>/dev/null || true
}

# ─── Logging ─────────────────────────────────────────────────────────────────
_bo_log() {
    local level="$1"
    shift
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local msg="${ts} [${level}] [${ORCHESTRATOR_PEER}] $*"
    echo "${msg}" >> "${LOGFILE}" 2>/dev/null || true
    if [[ -n "${_BO_STANDALONE:-}" ]]; then
        echo "${msg}" >&2
    fi
}

_bo_info()  { _bo_log "INFO"  "$@"; }
_bo_warn()  { _bo_log "WARN"  "$@"; }
_bo_error() { _bo_log "ERROR" "$@"; }
_bo_ok()    { _bo_log "OK"    "$@"; }

# ─── JSON helpers (no python3 dependency in hot path) ───────────────────────
_bo_json_escape() {
    # Escape a string for JSON. Handle basic cases.
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

_bo_make_payload() {
    # Build a JSON payload string for POST requests.
    # Usage: _bo_make_payload "key1" "val1" "key2" "val2" ...
    local keys=("$@")
    local parts=()
    local i
    for ((i=0; i<${#keys[@]}; i+=2)); do
        local key="${keys[$i]}"
        local val="${keys[$((i+1))]:-}"
        parts+=("\"${key}\":\"$(_bo_json_escape "${val}")\"")
    done
    # Join with commas
    local first=1
    for part in "${parts[@]}"; do
        if [[ "${first}" -eq 1 ]]; then
            printf '{%s' "${part}"
            first=0
        else
            printf ',%s' "${part}"
        fi
    done
    printf '}'
}

# ─── HTTP helpers (fail-open, matching deploy-hooks.sh patterns) ────────────
_BO_LAST_RESP=""
_BO_LAST_CODE=0

# Call repowire API. Returns 0 on success, 1 on failure.
# Never blocks — logs and returns 1 if daemon unreachable.
_bo_api() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    local args=(-sS --connect-timeout "${CURL_TIMEOUT}" --max-time 10)

    _BO_LAST_RESP=""
    _BO_LAST_CODE=0

    if [[ -n "${data}" ]]; then
        args+=(-H "Content-Type: application/json" -d "${data}")
    fi

    local attempt
    for ((attempt=1; attempt<=CURL_RETRIES; attempt++)); do
        _BO_LAST_RESP="$(curl "${args[@]}" -X "${method}" "${REPOWIRE_API}${path}" 2>/dev/null || true)"
        _BO_LAST_CODE="$?"
        if [[ "${_BO_LAST_CODE}" -eq 0 ]] && [[ -n "${_BO_LAST_RESP}" ]]; then
            return 0
        fi
        if [[ "${attempt}" -lt "${CURL_RETRIES}" ]]; then
            sleep 1
        fi
    done

    _bo_warn "API call to ${method} ${path} failed after ${CURL_RETRIES} attempt(s) (curl exit ${_BO_LAST_CODE})"
    return 1
}

# ─── State file management ───────────────────────────────────────────────────
# Each build gets a state file: ${STATE_DIR}/active.json
# The state file tracks: build_id, task_name, phases{}, agents[], circles, start_time

_bo_state_path() {
    # Returns the active build state path. If BUILD_ID is set, use it;
    # otherwise use "active" for the current/latest build.
    if [[ -n "${BUILD_ID}" ]]; then
        echo "${STATE_DIR}/${BUILD_ID}.json"
    else
        echo "${STATE_DIR}/active.json"
    fi
}

_bo_state_read() {
    local state_path
    state_path="$(_bo_state_path)"
    if [[ ! -f "${state_path}" ]]; then
        echo ""
        return 1
    fi
    cat "${state_path}" 2>/dev/null || echo ""
}

_bo_state_write() {
    local state_path
    state_path="$(_bo_state_path)"
    cat > "${state_path}" 2>/dev/null || true
}

_bo_state_init() {
    local task_name="$1"
    local build_id
    build_id="build-$(date -u +%Y%m%d%H%M%S)-$$"
    BUILD_ID="${build_id}"

    _bo_ensure_dirs

    # Write build-specific state file
    local build_state_path="${STATE_DIR}/${build_id}.json"
    cat > "${build_state_path}" <<STATEEOF
{
  "build_id": "${build_id}",
  "task_name": "$(_bo_json_escape "${task_name}")",
  "start_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phases": {},
  "agents": [],
  "circles_notified": [],
  "status": "active",
  "hostname": "$(hostname)",
  "mesh_peer": "${ORCHESTRATOR_PEER}"
}
STATEEOF

    # Also update active.json so subsequent CLI calls find the state
    cp "${build_state_path}" "${STATE_DIR}/active.json"
    _bo_info "Initialized build state: build_id=${build_id} task=${task_name} state=${build_state_path} (-> active.json)"
    echo "${build_id}"
}

_bo_state_update() {
    # Updates a field in the active state JSON
    local key="$1"
    local value="$2"
    local state_path
    state_path="$(_bo_state_path)"

    if [[ ! -f "${state_path}" ]]; then
        _bo_warn "No active state to update (${state_path} missing)"
        return 1
    fi

    local tmp
    tmp="$(mktemp)" 2>/dev/null || tmp="/tmp/bo-state-$$.tmp"

    # Use a safe python3 one-liner for JSON manipulation
    python3 -c "
import json, sys
try:
    with open('${state_path}') as f:
        data = json.load(f)
    data['${key}'] = json.loads('${value}') if ('${value}' == 'true' or '${value}' == 'false' or '${value}' == 'null' or (isinstance(${value}, (int, float)) if False else True)) else '${value}'
except:
    data = {}
    data['${key}'] = '${value}'
with open('${state_path}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || python3 -c "
import json, sys
with open('${state_path}') as f:
    data = json.load(f)
data['${key}'] = '${value}'
with open('${state_path}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

    rm -f "${tmp}" 2>/dev/null || true
}

_bo_state_phase_update() {
    local phase="$1"     # e.g. DISCOVER, PLAN, IMPLEMENT, etc.
    local status="$2"    # start | pass | fail | skip
    local detail="${3:-}"

    local state_path
    state_path="$(_bo_state_path)"

    if [[ ! -f "${state_path}" ]]; then
        _bo_warn "No active state to update phase (${state_path} missing)"
        return 1
    fi

    python3 -c "
import json, sys
with open('${state_path}') as f:
    data = json.load(f)
data['phases']['${phase}'] = {
    'status': '${status}',
    'detail': '${detail}',
    'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
}
with open('${state_path}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
}

_bo_state_add_agent() {
    local agent_name="$1"
    local agent_circle="${2:-}"
    local state_path
    state_path="$(_bo_state_path)"

    if [[ ! -f "${state_path}" ]]; then
        return 1
    fi

    python3 -c "
import json, sys
with open('${state_path}') as f:
    data = json.load(f)
agents = data.get('agents', [])
# Don't add duplicates
for a in agents:
    if a.get('name') == '${agent_name}':
        sys.exit(0)
agents.append({
    'name': '${agent_name}',
    'circle': '${agent_circle}',
    'registered_at': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
})
data['agents'] = agents
with open('${state_path}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
}

_bo_state_mark_complete() {
    local score="$1"
    local unverified="${2:-none}"
    local status="${3:-complete}"
    local state_path
    state_path="$(_bo_state_path)"

    if [[ ! -f "${state_path}" ]]; then
        return 1
    fi

    python3 -c "
import json, sys
with open('${state_path}') as f:
    data = json.load(f)
data['status'] = '${status}'
data['score'] = '${score}'
data['unverified'] = '${unverified}'
data['end_time'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('${state_path}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
}

# ─── Build Phase Validation ─────────────────────────────────────────────────
_bo_valid_phase() {
    local phase="$1"
    local p
    for p in "${PIPELINE_SEQ[@]}"; do
        if [[ "${p}" == "${phase}" ]]; then
            return 0
        fi
    done
    return 1
}

_bo_valid_phase_status() {
    local s="$1"
    case "${s}" in
        start|pass|fail|skip) return 0 ;;
        *) return 1 ;;
    esac
}

# ─── Resolve circles to comma-separated peer names for direct notify ────────
_bo_circles_to_peers() {
    local circles="$1"
    local peers=""
    local IFS=','
    local c
    for c in ${circles}; do
        local rep="${CIRCLE_REP[${c}]:-}"
        if [[ -n "${rep}" ]]; then
            if [[ -z "${peers}" ]]; then
                peers="${rep}"
            else
                peers="${peers},${rep}"
            fi
        fi
    done
    echo "${peers}"
}

# ─── API: get /peers ─────────────────────────────────────────────────────────
_bo_get_peers() {
    if ! _bo_api "GET" "/peers"; then
        echo "[]"
        return 1
    fi
    echo "${_BO_LAST_RESP}"
}

# ─── API: POST /broadcast ────────────────────────────────────────────────────
_bo_broadcast() {
    local text="$1"
    local payload
    payload="$(_bo_make_payload "from_peer" "${ORCHESTRATOR_PEER}" "text" "${text}")"

    if _bo_api "POST" "/broadcast" "${payload}"; then
        _bo_ok "Broadcast: ${text}"
        return 0
    else
        _bo_warn "Broadcast failed (daemon down?): ${text}"
        return 1
    fi
}

# ─── API: POST /notify ───────────────────────────────────────────────────────
_bo_notify() {
    local target="$1"
    local text="$2"
    local payload
    payload="$(_bo_make_payload "from_peer" "${ORCHESTRATOR_PEER}" "to_peer" "${target}" "text" "${text}")"

    if _bo_api "POST" "/notify" "${payload}"; then
        _bo_ok "Notify ${target}: ${text}"
        return 0
    else
        _bo_warn "Notify to ${target} failed (daemon down?): ${text}"
        return 1
    fi
}

# ─── API: POST /schedules ────────────────────────────────────────────────────
_bo_create_schedule() {
    local name="$1"
    local cron="$2"
    local text="$3"
    local target="${4:-wheeler-monitoring}"
    local payload
    payload="$(_bo_make_payload \
        "name" "${name}" \
        "cron_expression" "${cron}" \
        "prompt" "${text}" \
        "target_peer" "${target}" \
    )"

    if _bo_api "POST" "/schedules" "${payload}"; then
        _bo_ok "Schedule created: ${name} (${cron} -> ${target})"
        return 0
    else
        _bo_warn "Schedule creation failed: ${name}"
        return 1
    fi
}

# ============================================================================
# PUBLIC FUNCTIONS — called by build pipeline and other agents
# ============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# build_orchestrator_pre_build — Pre-build hook
# ─────────────────────────────────────────────────────────────────────────────
# Before any build starts:
#   1. Broadcast build intent to wheeler-core circle
#   2. Check /peers for conflicting builds (same domain, "busy" status)
#   3. Initialize state file
#   4. Create lock to prevent parallel conflicting builds
#
# Usage: build_orchestrator_pre_build "task-name" ["description"]
# Returns: 0 if safe to proceed, 1 if conflicting build detected
#          (still does NOT block — just warns and returns)
# ─────────────────────────────────────────────────────────────────────────────
build_orchestrator_pre_build() {
    local task_name="${1:-unknown-task}"
    local description="${2:-}"

    _bo_info "=== PRE-BUILD HOOK ==="
    _bo_info "Task: ${task_name} | Description: ${description}"

    # 1. Check mesh health (fail-open — log only)
    local mesh_ok=0
    if ! _bo_api "GET" "/health"; then
        _bo_warn "Pre-build: repowire daemon unreachable — proceeding without mesh notification"
        mesh_ok=1
    else
        local mesh_status
        mesh_status="$(echo "${_BO_LAST_RESP}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('status', 'unknown'))
except: print('unknown')" 2>/dev/null || echo "unknown")"
        _bo_info "Pre-build: mesh status=${mesh_status}"
    fi

    # 2. Check for conflicting builds (/peers for busy agents in wheeler-core)
    local conflict_found=0
    local conflict_detail=""
    if [[ "${mesh_ok}" -eq 0 ]]; then
        local peers_json
        peers_json="$(_bo_get_peers)" || peers_json="[]"

        if [[ "${peers_json}" != "[]" ]]; then
            conflict_detail="$(echo "${peers_json}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('peers', [])
    busy = [p for p in items if p.get('status') == 'busy']
    if not busy:
        print('')
        sys.exit(0)
    names = [p.get('name', p.get('display_name', '?')) for p in busy]
    circles = set(p.get('circle', '?') for p in busy)
    print(f\"Conflicting busy peers: {', '.join(names)} in circles: {', '.join(sorted(circles))}\")
except: print('')" 2>/dev/null || echo "")"

            if [[ -n "${conflict_detail}" ]]; then
                conflict_found=1
                _bo_warn "Pre-build: CONFLICT DETECTED — ${conflict_detail}"
            else
                _bo_info "Pre-build: no conflicting busy peers found"
            fi
        fi
    fi

    # 3. Initialize build state
    local build_id
    build_id="$(_bo_state_init "${task_name}")"
    _bo_info "Pre-build: build_id=${build_id}"

    # 4. Broadcast build intent to wheeler-core
    if [[ "${mesh_ok}" -eq 0 ]]; then
        local broadcast_msg=">> BUILD START: ${task_name} on $(hostname) | build_id=${build_id}"
        if [[ -n "${description}" ]]; then
            broadcast_msg="${broadcast_msg} | ${description}"
        fi
        if [[ "${conflict_found}" -eq 1 ]]; then
            broadcast_msg="${broadcast_msg} | WARNING: conflicting busy peers detected: ${conflict_detail}"
        fi
        _bo_broadcast "${broadcast_msg}"

        # Also notify the deploy peer directly for pipeline tracking
        _bo_notify "wheeler-deploy" "Build STARTED: ${task_name} (${build_id})"
    fi

    _bo_info "Pre-build: task=${task_name} build_id=${build_id} conflict=${conflict_found}"
    echo "${build_id}"
    return "${conflict_found}"
}

# ─────────────────────────────────────────────────────────────────────────────
# build_orchestrator_phase — Phase notification hook
# ─────────────────────────────────────────────────────────────────────────────
# Called as each build phase completes. Broadcasts to the appropriate circles
# and notifies the representative peer for each circle.
#
# Usage: build_orchestrator_phase <PHASE_NAME> <status> [detail]
#   PHASE_NAME: DISCOVER | PLAN | ARCHITECT | IMPLEMENT | TEST | REVIEW | SECURITY | VERIFY | FINAL
#   status:     start | pass | fail | skip
#   detail:     Optional human-readable detail (e.g. "3 agents, 5 files")
# ─────────────────────────────────────────────────────────────────────────────
build_orchestrator_phase() {
    local phase="${1^^}"    # uppercase
    local status="${2:-pass}"
    local detail="${3:-}"

    # Validate
    if ! _bo_valid_phase "${phase}"; then
        _bo_warn "Phase '${phase}' is not a valid pipeline phase. Valid: ${PIPELINE_SEQ[*]}"
        return 1
    fi
    if ! _bo_valid_phase_status "${status}"; then
        _bo_warn "Phase status '${status}' is not valid. Valid: start | pass | fail | skip"
        return 1
    fi

    _bo_info "=== PHASE NOTIFICATION: ${phase} [${status}] ==="

    # Update state
    _bo_state_phase_update "${phase}" "${status}" "${detail}"

    # Resolve circles for this phase
    local circles="${PHASE_CIRCLES[${phase}]:-wheeler-core}"
    _bo_info "Phase ${phase} notifying circles: ${circles}"

    # Build the message
    local phase_icon=""
    case "${status}" in
        start)  phase_icon=">>" ;;
        pass)   phase_icon="OK" ;;
        fail)   phase_icon="FAIL" ;;
        skip)   phase_icon="--" ;;
    esac

    local msg="${phase_icon} BUILD PHASE: ${phase} [${status}]"
    if [[ -n "${detail}" ]]; then
        msg="${msg} — ${detail}"
    fi
    if [[ -n "${BUILD_ID}" ]]; then
        msg="${msg} | build=${BUILD_ID}"
    fi

    # Broadcast to wheeler-core always, plus phase-specific circles
    # (wheeler-core is already in most phase circle lists; handle separately)
    case "${status}" in
        pass|start)
            _bo_broadcast "${msg}"
            ;;
        fail)
            _bo_broadcast "!! BUILD PHASE FAILED: ${phase} — ${detail}"
            # Notify security directly on pipeline failures
            _bo_notify "wheeler-security" "Phase FAIL: ${phase} — ${detail} | build=${BUILD_ID:-unknown}"
            _bo_notify "wheeler-deploy" "Phase FAIL: ${phase} — ${detail} | build=${BUILD_ID:-unknown}"
            ;;
        skip)
            _bo_notify "wheeler-deploy" "Phase SKIP: ${phase} — ${detail:-no reason given}"
            ;;
    esac

    # Targeted notify to each circle representative in the phase's circle set
    local IFS=','
    local c
    for c in ${circles}; do
        local rep="${CIRCLE_REP[${c}]:-}"
        if [[ -n "${rep}" ]]; then
            _bo_notify "${rep}" "Phase ${phase}: ${status} — ${detail:-no detail}" || true
        fi
    done

    _bo_info "Phase ${phase} notification complete"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# build_orchestrator_register_agent — Register agent as repowire peer
# ─────────────────────────────────────────────────────────────────────────────
# When an agent is deployed during a build, register it in the appropriate
# repowire circle so the mesh knows about it.
#
# Usage: build_orchestrator_register_agent <agent_name> [circle] [role_desc]
#   circle:  Auto-detected from AGENT_DOMAIN_CIRCLE if not provided.
#            Derived by matching the first keyword of the agent name.
#   role_desc: Short description (default: "Wheeler build agent")
#
# This creates a peer config entry in the state file for the build.
# NOTE: repowire peers are typically configured via YAML or bridge, not
# dynamically created via HTTP. This function:
#   - Records the agent in the build state
#   - Notifies the appropriate circle about the agent being deployed
#   - Creates a bridge-compatible config snippet in the state dir
# ─────────────────────────────────────────────────────────────────────────────
build_orchestrator_register_agent() {
    local agent_name="${1:-unknown-agent}"
    local circle="${2:-}"
    local role_desc="${3:-Wheeler build agent}"

    # Auto-detect circle from agent name if not provided
    if [[ -z "${circle}" ]]; then
        local agent_lower
        agent_lower="$(echo "${agent_name}" | tr '[:upper:]' '[:lower:]')"
        # Extract the first keyword from the agent name (before first - or _ or space)
        local keyword
        keyword="$(echo "${agent_lower}" | sed -E 's/^([a-zA-Z]+)[-_ ].*/\1/' 2>/dev/null || echo "${agent_lower}")"
        circle="${AGENT_DOMAIN_CIRCLE[${keyword}]:-wheeler-core}"
        _bo_info "Auto-detected circle for agent '${agent_name}': keyword='${keyword}' -> circle='${circle}'"
    fi

    _bo_info "=== REGISTER AGENT: ${agent_name} -> circle=${circle} ==="

    # Record in build state
    _bo_state_add_agent "${agent_name}" "${circle}"

    # Notify the target circle about the deployed agent
    local rep="${CIRCLE_REP[${circle}]:-wheeler-orchestrator}"
    _bo_notify "${rep}" "Agent DEPLOYED: ${agent_name} in circle ${circle} — ${role_desc}"

    # Generate a bridge-compatible config snippet for the agent
    # This can be consumed by bridge.py to add new peers
    local agent_config_dir="${STATE_DIR}/agents"
    mkdir -p "${agent_config_dir}" 2>/dev/null || true

    local config_file="${agent_config_dir}/${agent_name}.json"
    if [[ ! -f "${config_file}" ]]; then
        cat > "${config_file}" <<AGENTCONF
{
  "agent_name": "${agent_name}",
  "circle": "${circle}",
  "role_desc": "$(_bo_json_escape "${role_desc}")",
  "registered_by": "${ORCHESTRATOR_PEER}",
  "registered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build_id": "${BUILD_ID:-unknown}",
  "display_name": "${agent_name}",
  "backend": "claude-code",
  "status": "online"
}
AGENTCONF
        _bo_info "Agent config written: ${config_file}"
    else
        _bo_info "Agent config already exists (idempotent): ${config_file}"
    fi

    # Broadcast agent deployment to wheeler-core
    _bo_broadcast "Agent DEPLOYED: ${agent_name} (circle=${circle}) during build ${BUILD_ID:-unknown}"

    _bo_ok "Agent ${agent_name} registered in circle ${circle}"
    echo "${agent_name} -> ${circle}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# build_orchestrator_complete — Build completion broadcast
# ─────────────────────────────────────────────────────────────────────────────
# Called when the build pipeline finishes. Broadcasts the final scorecard
# to ALL circles.
#
# Usage: build_orchestrator_complete <score> [unverified_list] [status]
#   score:           "100" | "85" | "0" etc
#   unverified_list: Comma-separated items not verified, or "none"
#   status:          "complete" | "blocker" | "partial"
# ─────────────────────────────────────────────────────────────────────────────
build_orchestrator_complete() {
    local score="${1:-0}"
    local unverified="${2:-none}"
    local status="${3:-complete}"

    _bo_info "=== BUILD COMPLETE ==="
    _bo_info "Score: ${score} | Unverified: ${unverified} | Status: ${status}"

    # Update state
    _bo_state_mark_complete "${score}" "${unverified}" "${status}"

    # Build phases summary from state
    local phases_summary=""
    local state_path
    state_path="$(_bo_state_path)"
    if [[ -f "${state_path}" ]]; then
        phases_summary="$(python3 -c "
import json, sys
with open('${state_path}') as f:
    data = json.load(f)
phases = data.get('phases', {})
summary = []
for p in ['DISCOVER','PLAN','ARCHITECT','IMPLEMENT','TEST','REVIEW','SECURITY','VERIFY','FINAL']:
    if p in phases:
        s = phases[p].get('status', '?').ljust(5)
        d = phases[p].get('detail', '')[:60]
        summary.append(f'{p}: {s} {d}')
    else:
        summary.append(f'{p}: --')
return '\n'.join(summary)
" 2>/dev/null || echo "PHASE SUMMARY UNAVAILABLE")"
    fi

    # Build final scorecard message
    local scorecard
    scorecard="$(cat <<SCORECARD

═══════════════════════════════════════
BUILD COMPLETE — build=${BUILD_ID:-unknown}
Status: ${status} | Score: ${score}/100
Unverified: ${unverified}
Host: $(hostname) | Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)

PHASE RESULTS:
${phases_summary:+${phases_summary}}

Agent configs: ${STATE_DIR}/agents/
═══════════════════════════════════════
SCORECARD
)"

    # Broadcast to ALL circles
    local all_circles
    all_circles="$(echo "${PHASE_CIRCLES[*]}" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')"

    _bo_broadcast "BUILD RESULT: ${status} | score=${score}/100 | build=${BUILD_ID:-unknown}"

    case "${status}" in
        complete)
            _bo_broadcast "BUILD COMPLETE: Score ${score}/100. Unverified: ${unverified}"
            _bo_notify "wheeler-deploy" "Build COMPLETE: score=${score}/100 unverified=${unverified}"
            if [[ "${score}" -ge 100 ]]; then
                _bo_broadcast "100/100 BUILD — all gates green. Deploy pipeline may proceed."
                _bo_notify "wheeler-deploy" "100/100 BUILD READY — all quality gates passed"
            fi
            ;;
        blocker)
            _bo_broadcast "BUILD BLOCKED: Score ${score}/100 — blocker requires human attention"
            _bo_notify "wheeler-security" "Build BLOCKED: score=${score}/100 — needs human review"
            _bo_notify "wheeler-deploy" "Build BLOCKED: score=${score}/100"
            ;;
        partial)
            _bo_broadcast "BUILD PARTIAL: Score ${score}/100 — ${unverified}"
            _bo_notify "wheeler-deploy" "Build PARTIAL: score=${score}/100 unverified=${unverified}"
            ;;
    esac

    # Write final scorecard to state dir for audit trail
    local scorecard_file="${STATE_DIR}/scorecard-${BUILD_ID:-final}.txt"
    echo "${scorecard}" > "${scorecard_file}" 2>/dev/null || true
    _bo_info "Scorecard written: ${scorecard_file}"

    _bo_ok "Build complete status broadcast. Scorecard at ${scorecard_file}"
    echo "${scorecard}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# build_orchestrator_auto_wire — Auto-wire new repo as repowire peer
# ─────────────────────────────────────────────────────────────────────────────
# When the repo-listener detects a new repository (e.g., a new repo cloned
# or created in the ecosystem), this function creates the repowire peer
# configuration so the new repo's build pipeline is mesh-aware.
#
# Usage: build_orchestrator_auto_wire <repo_path> [repo_name] [circle]
#   repo_path: Absolute path to the repo
#   repo_name: Name (default: derived from path basename)
#   circle:    repowire circle (default: auto-detected from repo name)
# ─────────────────────────────────────────────────────────────────────────────
build_orchestrator_auto_wire() {
    local repo_path="${1:-}"
    local repo_name="${2:-}"
    local circle="${3:-}"

    if [[ -z "${repo_path}" ]]; then
        _bo_error "auto-wire: repo_path is required"
        return 1
    fi

    # Derive repo_name from path if not provided
    if [[ -z "${repo_name}" ]]; then
        repo_name="$(basename "${repo_path}")"
    fi

    # Auto-detect circle from repo name patterns
    if [[ -z "${circle}" ]]; then
        local rn_lower
        rn_lower="$(echo "${repo_name}" | tr '[:upper:]' '[:lower:]')"
        case "${rn_lower}" in
            *security*|*audit*|*compliance*)   circle="wheeler-security" ;;
            *deploy*|*release*)                 circle="wheeler-deploy" ;;
            *db*|*database*|*postgres*|*sql*)   circle="wheeler-db" ;;
            *monitor*|*observ*|*alert*)         circle="wheeler-monitoring" ;;
            *finan*|*reven*|*stripe*|*billing*) circle="wheeler-finance" ;;
            *growth*|*market*|*seo*|*lead*)     circle="wheeler-growth" ;;
            *legal*|*compliance*)                circle="wheeler-legal" ;;
            *infra*|*docker*|*k8s*|*ops*)       circle="wheeler-ops" ;;
            *)                                  circle="wheeler-core" ;;
        esac
        _bo_info "Auto-wire: auto-detected circle for repo '${repo_name}' -> ${circle}"
    fi

    _bo_info "=== AUTO-WIRE REPO: ${repo_name} (${repo_path}) -> circle=${circle} ==="

    # Verify the repo path actually exists
    if [[ ! -d "${repo_path}" ]]; then
        _bo_warn "Auto-wire: repo path does not exist: ${repo_path} — creating config anyway (deferred)"
    fi

    # Create peer config file in the agent configs directory
    local agent_config_dir="${STATE_DIR}/agents"
    mkdir -p "${agent_config_dir}" 2>/dev/null || true

    local peer_name="repo-${repo_name}"
    local config_file="${agent_config_dir}/${peer_name}.json"

    cat > "${config_file}" <<REPOCONF
{
  "agent_name": "${peer_name}",
  "circle": "${circle}",
  "role_desc": "Auto-wired repo: ${repo_name} at ${repo_path}",
  "registered_by": "${ORCHESTRATOR_PEER}",
  "registered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "repo_path": "${repo_path}",
  "display_name": "Repo-${repo_name}",
  "backend": "repo",
  "status": "configured"
}
REPOCONF
    _bo_ok "Auto-wire config created: ${config_file}"

    # Create a bridge.py-compatible entry snippet for reference
    local bridge_config_dir="${STATE_DIR}/bridge-peers"
    mkdir -p "${bridge_config_dir}" 2>/dev/null || true

    local bridge_entry="${bridge_config_dir}/${peer_name}.py"
    if [[ ! -f "${bridge_entry}" ]]; then
        cat > "${bridge_entry}" <<BRIDGEENTRY
    "${peer_name}": {
        "display_name": "Repo-${repo_name}",
        "circle": "${circle}",
        "role_desc": "Auto-wired repo: ${repo_name} at ${repo_path}",
    },
BRIDGEENTRY
        _bo_info "Bridge config snippet created: ${bridge_entry}"
    fi

    # Notify the mesh
    _bo_broadcast "Repo AUTO-WIRED: ${repo_name} (circle=${circle}) — build pipeline now mesh-aware"

    # If there's a repowire config in the repo itself, create a reference
    local repowire_dir="${repo_path}/.repowire"
    mkdir -p "${repowire_dir}" 2>/dev/null || true

    local repowire_config="${repowire_dir}/config.json"
    if [[ ! -f "${repowire_config}" ]]; then
        cat > "${repowire_config}" <<REPOCONFIG
{
  "peer_name": "${peer_name}",
  "circle": "${circle}",
  "mesh_url": "${REPOWIRE_API}",
  "orchestrator": "${ORCHESTRATOR_PEER}",
  "auto_wired": true,
  "auto_wired_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build_pipeline": "${repo_path}/.ai/subagents/BUILD_PIPELINE.md",
  "integration_ref": "/root/deployment-engine/repowire/INTEGRATION.md"
}
REPOCONFIG
        _bo_info "Repo-scoped repowire config created: ${repowire_config}"
    fi

    echo "${peer_name} -> ${circle}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# build_orchestrator_check_mesh — Verify mesh reachability
# ─────────────────────────────────────────────────────────────────────────────
build_orchestrator_check_mesh() {
    _bo_info "Checking repowire mesh health..."

    if ! _bo_api "GET" "/health"; then
        _bo_warn "Mesh check: daemon unreachable at ${REPOWIRE_API}"
        return 1
    fi

    local status version
    status="$(echo "${_BO_LAST_RESP}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")"
    version="$(echo "${_BO_LAST_RESP}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")"

    local peer_count=0
    local peer_list=""
    if _bo_api "GET" "/peers"; then
        peer_count="$(echo "${_BO_LAST_RESP}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('peers', [])
    print(len(items))
except: print(0)" 2>/dev/null || echo "0")"
        peer_list="$(echo "${_BO_LAST_RESP}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('peers', [])
    names = [p.get('name', p.get('display_name', '?')) for p in items]
    print(', '.join(names))
except: print('')" 2>/dev/null || true)"
    fi

    _bo_info "Mesh status=${status} v${version} peers=${peer_count} list=[${peer_list}]"
    echo "Mesh: ${status} v${version} | Peers: ${peer_count} | List: ${peer_list}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# build_orchestrator_status — Full status dump
# ─────────────────────────────────────────────────────────────────────────────
build_orchestrator_status() {
    local mesh_status="unreachable"
    local mesh_version="?"
    local peer_count="?"
    local peer_detail=""
    local active_build=""

    # Mesh status
    if _bo_api "GET" "/health"; then
        mesh_status="$(echo "${_BO_LAST_RESP}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")"
        mesh_version="$(echo "${_BO_LAST_RESP}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")"
    fi

    # Peers
    if _bo_api "GET" "/peers"; then
        peer_count="$(echo "${_BO_LAST_RESP}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('peers', [])
    print(len(items))
except: print('?')" 2>/dev/null || echo "?")"
        peer_detail="$(echo "${_BO_LAST_RESP}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('peers', [])
    for p in items:
        n = p.get('name', p.get('display_name', '?'))
        s = p.get('status', '?')
        c = p.get('circle', '?')
        print(f'  peer: {n}  status={s}  circle={c}')
except: print('')" 2>/dev/null || true)"
    fi

    # Active build state
    if [[ -f "${STATE_DIR}/active.json" ]]; then
        active_build="$(python3 -c "
import json
with open('${STATE_DIR}/active.json') as f:
    d = json.load(f)
print(f'  Build: {d.get(\"build_id\",\"?\")}')
print(f'  Task:  {d.get(\"task_name\",\"?\")}')
print(f'  Status: {d.get(\"status\",\"?\")}')
print(f'  Score: {d.get(\"score\",\"?\")}')
phases = d.get('phases', {})
for p in ['DISCOVER','PLAN','ARCHITECT','IMPLEMENT','TEST','REVIEW','SECURITY','VERIFY','FINAL']:
    if p in phases:
        print(f'  Phase {p}: {phases[p].get(\"status\",\"?\")}')
agents = d.get('agents', [])
if agents:
    print(f'  Agents deployed: {len(agents)}')
    for a in agents:
        print(f'    - {a.get(\"name\",\"?\")} ({a.get(\"circle\",\"?\")})')
" 2>/dev/null || echo "  (unable to parse)")"
    fi

    # Registered agent configs
    local agent_count=0
    if [[ -d "${STATE_DIR}/agents" ]]; then
        agent_count="$(find "${STATE_DIR}/agents" -name '*.json' 2>/dev/null | wc -l)"
    fi

    # Schedules
    local schedules=""
    if _bo_api "GET" "/schedules"; then
        schedules="$(echo "${_BO_LAST_RESP}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('schedules', [])
    for s in items:
        print(f'  {s.get(\"name\",\"?\")}: cron={s.get(\"cron\",\"?\")} target={s.get(\"to_peer\",\"?\")}')
except: print('')" 2>/dev/null || true)"
    fi

    # Print report
    echo "===== Repowire Build Orchestrator Status ====="
    echo "Peer name:        ${ORCHESTRATOR_PEER}"
    echo "Mesh status:      ${mesh_status}"
    echo "Mesh version:     ${mesh_version}"
    echo "Peers online:     ${peer_count}"
    echo "Log file:         ${LOGFILE}"
    echo "State dir:        ${STATE_DIR}"
    echo "API endpoint:     ${REPOWIRE_API}"
    echo ""
    if [[ -n "${active_build}" ]]; then
        echo "Active Build:"
        echo "${active_build}"
        echo ""
    else
        echo "Active Build:    (none)"
        echo ""
    fi
    if [[ -n "${peer_detail}" ]]; then
        echo "Mesh Peers:"
        echo "${peer_detail}"
        echo ""
    fi
    echo "Agent configs:    ${agent_count} registered"
    if [[ -n "${schedules}" ]]; then
        echo "Schedules:"
        echo "${schedules}"
    fi
    echo "=============================================="
}

# ─── Ensure log + state dirs exist on load ──────────────────────────────────
_bo_ensure_dirs

# ─── Mark as loaded (prevents double-sourcing issues) ───────────────────────
_BO_LOADED=1

# =============================================================================
# STANDALONE CLI — invoked when script is executed directly (not sourced)
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _BO_STANDALONE=1
    _bo_ensure_dirs

    # If REPOWIRE_API is provided as first arg in form --api=http://..., parse it
    if [[ "${1:-}" =~ ^--api= ]]; then
        REPOWIRE_API="${1#--api=}"
        shift
    fi

    _bo_info "build-orchestrator.sh invoked as CLI (args: $*)"

    cmd="${1:-help}"
    shift || true

    case "${cmd}" in
        pre-build)
            task_name="${1:-}"
            description="${2:-}"
            if [[ -z "${task_name}" ]]; then
                echo "Usage: $0 pre-build <task-name> [description]" >&2
                exit 1
            fi
            build_orchestrator_pre_build "${task_name}" "${description}"
            exit $?
            ;;
        phase)
            phase="${1:-}"
            status="${2:-pass}"
            detail="${3:-}"
            if [[ -z "${phase}" ]]; then
                echo "Usage: $0 phase <PHASE> <status> [detail]" >&2
                echo "  PHASE: DISCOVER|PLAN|ARCHITECT|IMPLEMENT|TEST|REVIEW|SECURITY|VERIFY|FINAL" >&2
                echo "  status: start|pass|fail|skip" >&2
                exit 1
            fi
            build_orchestrator_phase "${phase}" "${status}" "${detail}"
            exit $?
            ;;
        register-agent|register_agent|register)
            agent_name="${1:-}"
            circle="${2:-}"
            role_desc="${3:-Wheeler build agent}"
            if [[ -z "${agent_name}" ]]; then
                echo "Usage: $0 register-agent <agent-name> [circle] [role-desc]" >&2
                exit 1
            fi
            build_orchestrator_register_agent "${agent_name}" "${circle}" "${role_desc}"
            exit $?
            ;;
        complete|finish)
            score="${1:-0}"
            unverified="${2:-none}"
            status="${3:-complete}"
            build_orchestrator_complete "${score}" "${unverified}" "${status}"
            exit $?
            ;;
        auto-wire|autowire)
            repo_path="${1:-}"
            repo_name="${2:-}"
            circle="${3:-}"
            if [[ -z "${repo_path}" ]]; then
                echo "Usage: $0 auto-wire <repo-path> [repo-name] [circle]" >&2
                exit 1
            fi
            build_orchestrator_auto_wire "${repo_path}" "${repo_name}" "${circle}"
            exit $?
            ;;
        check-mesh|check_mesh|health)
            build_orchestrator_check_mesh
            exit $?
            ;;
        status)
            build_orchestrator_status
            exit 0
            ;;
        create-schedule|schedule)
            sched_name="${1:-}"
            sched_cron="${2:-}"
            sched_text="${3:-}"
            sched_target="${4:-wheeler-monitoring}"
            if [[ -z "${sched_name}" ]] || [[ -z "${sched_cron}" ]] || [[ -z "${sched_text}" ]]; then
                echo "Usage: $0 create-schedule <name> <cron> <prompt-text> [target-peer]" >&2
                echo "  Example: $0 create-schedule \"my-daily-check\" \"0 9 * * *\" \"Run daily health check\" wheeler-monitoring" >&2
                exit 1
            fi
            _bo_create_schedule "${sched_name}" "${sched_cron}" "${sched_text}" "${sched_target}"
            exit $?
            ;;
        help|--help|-h)
            echo "Wheeler Repowire Build Orchestrator — P2P Build Pipeline Integration"
            echo ""
            echo "Integrates the repowire agent mesh (:8377) with the Wheeler 7-gate"
            echo "autonomous build pipeline. Fail-open: never blocks a build."
            echo ""
            echo "USAGE:"
            echo "  $0 pre-build <task> [desc]           — pre-build intent + conflict check"
            echo "  $0 phase <PHASE> <status> [detail]    — phase lifecycle notification"
            echo "  $0 register-agent <name> [circle] [role] — register agent as mesh peer"
            echo "  $0 complete <score> [unverified] [status] — broadcast final scorecard"
            echo "  $0 auto-wire <path> [name] [circle]   — create peer config for new repo"
            echo "  $0 check-mesh                         — verify mesh reachability"
            echo "  $0 create-schedule <name> <cron> <text> [target] — add autonomous schedule"
            echo "  $0 status                             — full mesh + build state"
            echo ""
            echo "PHASES:  DISCOVER PLAN ARCHITECT IMPLEMENT TEST REVIEW SECURITY VERIFY FINAL"
            echo "STATUS:  start | pass | fail | skip"
            echo ""
            echo "CIRCLES: wheeler-core wheeler-ops wheeler-security wheeler-deploy"
            echo "         wheeler-finance wheeler-growth wheeler-legal wheeler-db wheeler-monitoring"
            echo ""
            echo "ENVIRONMENT:"
            echo "  REPOWIRE_API      (default: http://127.0.0.1:8377)"
            echo "  LOGFILE           (default: /var/log/repowire/build-orchestrator.log)"
            echo "  STATE_DIR         (default: /var/lib/repowire/build-orchestrator)"
            echo "  ORCHESTRATOR_PEER (default: wheeler-orchestrator)"
            echo "  CURL_TIMEOUT      (default: 5)"
            echo "  CURL_RETRIES      (default: 2)"
            echo ""
            echo "SOURCING:"
            echo "  source $0"
            echo "  build_orchestrator_pre_build \"feat/add-stripe\""
            echo "  build_orchestrator_phase \"DISCOVER\" \"pass\" \"3 agents, 5 files\""
            echo "  build_orchestrator_register_agent \"lead-intelligence\" \"wheeler-growth\""
            echo "  build_orchestrator_complete \"100\" \"none\""
            echo ""
            echo "DOCS:"
            echo "  Build pipeline:   /root/.ai/subagents/BUILD_PIPELINE.md"
            echo "  Repowire bridge:  /root/deployment-engine/repowire/bridge.py"
            echo "  Integration ref:  /root/deployment-engine/repowire/INTEGRATION.md"
            echo "  Log file:         ${LOGFILE}"
            echo "  State dir:        ${STATE_DIR}"
            exit 0
            ;;
        *)
            echo "Unknown command: ${cmd}"
            echo "Usage: $0 <command> [args]"
            echo "Commands: pre-build, phase, register-agent, complete, auto-wire, check-mesh, create-schedule, status, help"
            exit 1
            ;;
    esac
fi
