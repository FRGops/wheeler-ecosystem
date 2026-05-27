#!/usr/bin/env bash
# =============================================================================
# repowire/deploy-hooks.sh — Repowire Agent Mesh Deploy Hooks
# =============================================================================
# Integrates the repowire P2P agent mesh into the Wheeler 7-gate deployment
# pipeline. Sourced by deploy scripts (deploy-service.sh, deploy-pm2-service.sh,
# deploy-productization-fleet.sh) or run standalone as a CLI hook.
#
# Usage (standalone):
#   ./deploy-hooks.sh check-mesh          — verify mesh health
#   ./deploy-hooks.sh broadcast <msg>     — broadcast to wheeler-core circle
#   ./deploy-hooks.sh notify <peer> <msg> — notify a specific peer
#   ./deploy-hooks.sh gate <N> <svc> <status> — gate lifecycle hook
#   ./deploy-hooks.sh deploy-start <svc> <ver>   — notify deploy started
#   ./deploy-hooks.sh deploy-ok    <svc> <ver>   — notify deploy succeeded
#   ./deploy-hooks.sh deploy-fail <svc> <ver> [reason] — notify deploy failed
#   ./deploy-hooks.sh status                  — print mesh + deployment state
#
# Usage (sourced):
#   source deploy-hooks.sh          # idempotent — provides repowire_hook_* fns
#   repowire_hook_gate 1 "svc" "pass"
#
# Design:
#   - Fail-open: any repowire failure is logged but never blocks the deploy
#   - Idempotent: sourcing twice or calling hooks twice produces no side effects
#   - Self-logging: all activity to /var/log/repowire/deploy-hooks.log
#   - Environment-configurable via REPOWIRE_API, LOGFILE, PEER_NAME
# =============================================================================

set -euo pipefail

# ─── Configuration (overridable via environment) ─────────────────────────────
REPOWIRE_API="${REPOWIRE_API:-http://127.0.0.1:8377}"
LOGFILE="${LOGFILE:-/var/log/repowire/deploy-hooks.log}"
PEER_NAME="${PEER_NAME:-wheeler-deploy}"
CIRCLE_NAME="${CIRCLE_NAME:-wheeler-core}"
CURL_TIMEOUT="${CURL_TIMEOUT:-5}"
CURL_RETRIES="${CURL_RETRIES:-2}"

# Guards against double-sourcing
_REPOWIRE_HOOKS_LOADED="${_REPOWIRE_HOOKS_LOADED:-0}"

# ─── Logging ─────────────────────────────────────────────────────────────────

_rh_log() {
    local level="$1"
    shift
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local msg="${ts} [${level}] [${PEER_NAME}] $*"
    echo "${msg}" >> "${LOGFILE}" 2>/dev/null || true
    # Also echo to stderr if this is a standalone invocation (not sourced)
    # Use a heuristic: if _RH_STANDALONE is set, echo to stderr
    if [[ -n "${_RH_STANDALONE:-}" ]]; then
        echo "${msg}" >&2
    fi
}

_rh_info()  { _rh_log "INFO"  "$@"; }
_rh_warn()  { _rh_log "WARN"  "$@"; }
_rh_error() { _rh_log "ERROR" "$@"; }
_rh_ok()    { _rh_log "OK"    "$@"; }

# ─── HTTP helpers (fail-open) ───────────────────────────────────────────────

# Call repowire API. Returns 0 if call succeeded, 1 if daemon unreachable.
# Captures HTTP response body in _rh_LAST_RESP and HTTP code in _rh_LAST_CODE.
_rh_api() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    local args=(-sS --connect-timeout "${CURL_TIMEOUT}" --max-time 10)

    _rh_LAST_RESP=""
    _rh_LAST_CODE=""

    if [[ -n "${data}" ]]; then
        args+=(-H "Content-Type: application/json" -d "${data}")
    fi

    local attempt
    for ((attempt=1; attempt<=CURL_RETRIES; attempt++)); do
        local curl_exit=0
        _rh_LAST_RESP="$(curl "${args[@]}" -X "${method}" "${REPOWIRE_API}${path}" 2>/dev/null)" || curl_exit=$?
        _rh_LAST_CODE="${curl_exit}"
        if [[ "${_rh_LAST_CODE}" -eq 0 ]] && [[ -n "${_rh_LAST_RESP}" ]]; then
            return 0
        fi
        if [[ "${attempt}" -lt "${CURL_RETRIES}" ]]; then
            sleep 1
        fi
    done

    _rh_warn "API call to ${method} ${path} failed after ${CURL_RETRIES} attempt(s) (curl exit ${_rh_LAST_CODE})"
    return 1
}

# ─── Public Hook Functions ───────────────────────────────────────────────────

# check-mesh: Verify repowire mesh health before deploy.
# Returns 0 if mesh is healthy, 1 if unreachable (never blocks deploy).
repowire_hook_check_mesh() {
    _rh_info "Checking repowire mesh health..."

    # 1. Hit /health
    if ! _rh_api "GET" "/health"; then
        _rh_warn "Mesh check: daemon unreachable at ${REPOWIRE_API} — deploying without mesh notification"
        return 1
    fi

    local status
    status="$(echo "${_rh_LAST_RESP}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")"

    # 2. Query /peers
    local peer_count=0
    local peer_list=""
    if _rh_api "GET" "/peers"; then
        peer_count="$(echo "${_rh_LAST_RESP}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        print(len(data))
    elif isinstance(data, dict):
        print(len(data.get('peers', [])))
    else:
        print(0)
except Exception:
    print(0)
" 2>/dev/null || echo "0")"
        peer_list="$(echo "${_rh_LAST_RESP}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('peers', [])
    names = [p.get('name', p.get('display_name', '?')) for p in items]
    print(', '.join(names))
except Exception:
    print('')
" 2>/dev/null || echo "unknown")"
    fi

    _rh_info "Mesh status=${status} peers=${peer_count} list=[${peer_list}]"
    return 0
}

# broadcast: Send a message to the wheeler-core circle.
# Usage: repowire_hook_broadcast "message text"
repowire_hook_broadcast() {
    local text="$1"
    local payload
    payload="$(python3 -c "
import json
print(json.dumps({'from_peer': '${PEER_NAME}', 'text': '${text}'}))
" 2>/dev/null)"

    if _rh_api "POST" "/broadcast" "${payload}"; then
        _rh_ok "Broadcast: ${text}"
        return 0
    else
        _rh_warn "Broadcast failed (daemon down?): ${text}"
        return 1
    fi
}

# notify: Send a notification to a specific peer.
# Usage: repowire_hook_notify "target-peer" "message text"
repowire_hook_notify() {
    local target="$1"
    local text="$2"
    local payload
    payload="$(python3 -c "
import json
print(json.dumps({'from_peer': '${PEER_NAME}', 'to_peer': '${target}', 'text': '${text}'}))
" 2>/dev/null)"

    if _rh_api "POST" "/notify" "${payload}"; then
        _rh_ok "Notify ${target}: ${text}"
        return 0
    else
        _rh_warn "Notify to ${target} failed (daemon down?): ${text}"
        return 1
    fi
}

# gate: Gate lifecycle hook — wraps broadcast + notify for a standard gate.
# Usage: repowire_hook_gate <gate-number> <service-name> <status>
#   status: start | pass | fail | skip
repowire_hook_gate() {
    local gate_num="$1"
    local service="$2"
    local status="$3"
    local msg="Gate ${gate_num} [${service}] ${status}"

    _rh_info "Gate ${gate_num} hook: service=${service} status=${status}"

    case "${status}" in
        start)
            repowire_hook_notify "wheeler-deploy" "Gate ${gate_num}: ${service} — started"
            ;;
        pass)
            repowire_hook_broadcast "${CIRCLE_NAME} gate ${gate_num} pass: ${service}"
            repowire_hook_notify "wheeler-deploy" "Gate ${gate_num}: ${service} — passed"
            ;;
        fail)
            repowire_hook_broadcast "${CIRCLE_NAME} gate ${gate_num} FAIL: ${service}"
            repowire_hook_notify "wheeler-deploy" "Gate ${gate_num}: ${service} — FAILED. Mesh peers alerted."
            ;;
        skip)
            repowire_hook_notify "wheeler-deploy" "Gate ${gate_num}: ${service} — skipped"
            ;;
        *)
            _rh_warn "Unknown gate status '${status}' for gate ${gate_num}/${service}"
            return 1
            ;;
    esac
    return 0
}

# deploy-start: Notify mesh that a deploy is beginning.
# Usage: repowire_hook_deploy_start <service> <version>
repowire_hook_deploy_start() {
    local service="$1"
    local version="${2:-unknown}"
    local msg=">> DEPLOY START: ${service} v${version} on $(hostname)"

    _rh_info "${msg}"
    repowire_hook_broadcast "${msg}"
    repowire_hook_notify "wheeler-deploy" "${msg}"
}

# deploy-ok: Notify mesh that a deploy completed successfully.
# Usage: repowire_hook_deploy_ok <service> <version>
repowire_hook_deploy_ok() {
    local service="$1"
    local version="${2:-unknown}"
    local msg=">> DEPLOY OK: ${service} v${version} on $(hostname)"

    _rh_info "${msg}"
    repowire_hook_broadcast "${msg}"
    repowire_hook_notify "wheeler-deploy" "${msg}"
}

# deploy-fail: Notify mesh that a deploy failed.
# Usage: repowire_hook_deploy_fail <service> <version> [reason]
repowire_hook_deploy_fail() {
    local service="$1"
    local version="${2:-unknown}"
    local reason="${3:-unspecified}"
    local msg=">> DEPLOY FAIL: ${service} v${version} on $(hostname) — ${reason}"

    _rh_error "${msg}"
    repowire_hook_broadcast "${msg}"
    repowire_hook_notify "wheeler-deploy" "${msg}"

    # Also notify security peer on failures — they may need to investigate
    repowire_hook_notify "wheeler-security" "Deploy FAIL: ${service} v${version} — ${reason}"
}

# status: Print current mesh + deployment state.
repowire_hook_status() {
    local mesh_status="unreachable"
    local mesh_version="?"
    local peer_count="?"
    local peer_detail=""

    if _rh_api "GET" "/health"; then
        mesh_status="$(echo "${_rh_LAST_RESP}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")"
        mesh_version="$(echo "${_rh_LAST_RESP}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")"
    fi

    if _rh_api "GET" "/peers"; then
        peer_count="$(echo "${_rh_LAST_RESP}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('peers', [])
    print(len(items))
except Exception:
    print('?')
" 2>/dev/null || echo "?")"
        peer_detail="$(echo "${_rh_LAST_RESP}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('peers', [])
    for p in items:
        n = p.get('name', p.get('display_name', '?'))
        s = p.get('status', '?')
        c = p.get('circle', '?')
        print(f'  peer: {n}  status={s}  circle={c}')
except Exception:
    print('')
" 2>/dev/null || true)"
    fi

    echo "===== Repowire Deploy Hooks Status ====="
    echo "Peer name:        ${PEER_NAME}"
    echo "Mesh status:      ${mesh_status}"
    echo "Mesh version:     ${mesh_version}"
    echo "Peers online:     ${peer_count}"
    echo "Log file:         ${LOGFILE}"
    echo "API endpoint:     ${REPOWIRE_API}"
    echo ""
    if [[ -n "${peer_detail}" ]]; then
        echo "Peer details:"
        echo "${peer_detail}"
    fi
    echo "========================================="
}

# ─── Ensure log directory exists ─────────────────────────────────────────────
mkdir -p "$(dirname "${LOGFILE}")" 2>/dev/null || true

# ─── When sourced: mark loaded, register no cleanup (stateless) ─────────────
_REPOWIRE_HOOKS_LOADED=1

# =============================================================================
# Standalone CLI — runs when this script is executed directly, not sourced
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _RH_STANDALONE=1

    _ensure_logfile() {
        mkdir -p "$(dirname "${LOGFILE}")" 2>/dev/null || true
    }
    _ensure_logfile

    _rh_info "deploy-hooks.sh invoked as CLI (args: $*)"

    case "${1:-help}" in
        check-mesh)
            repowire_hook_check_mesh
            exit 0
            ;;
        broadcast)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 broadcast <message>" >&2
                exit 1
            fi
            repowire_hook_broadcast "$2"
            exit 0
            ;;
        notify)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
                echo "Usage: $0 notify <target-peer> <message>" >&2
                exit 1
            fi
            repowire_hook_notify "$2" "$3"
            exit 0
            ;;
        gate)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]] || [[ -z "${4:-}" ]]; then
                echo "Usage: $0 gate <gate-number> <service> <status>" >&2
                echo "  status: start | pass | fail | skip" >&2
                exit 1
            fi
            repowire_hook_gate "$2" "$3" "$4"
            exit 0
            ;;
        deploy-start)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 deploy-start <service> [version]" >&2
                exit 1
            fi
            repowire_hook_deploy_start "$2" "${3:-unknown}"
            exit 0
            ;;
        deploy-ok|deploy-complete)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 ${1} <service> [version]" >&2
                exit 1
            fi
            repowire_hook_deploy_ok "$2" "${3:-unknown}"
            exit 0
            ;;
        deploy-fail|deploy-failed)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 ${1} <service> [version] [reason]" >&2
                exit 1
            fi
            repowire_hook_deploy_fail "$2" "${3:-unknown}" "${4:-unspecified}"
            exit 0
            ;;
        status)
            repowire_hook_status
            exit 0
            ;;
        help|--help|-h)
            echo "Wheeler Repowire Deploy Hooks — Agent Mesh Integration"
            echo ""
            echo "Usage:"
            echo "  $0 check-mesh                  — verify mesh health"
            echo "  $0 broadcast <msg>              — broadcast to circle"
            echo "  $0 notify <peer> <msg>          — notify specific peer"
            echo "  $0 gate <N> <svc> <status>      — gate lifecycle hook"
            echo "  $0 deploy-start <svc> [ver]     — notify deploy started"
            echo "  $0 deploy-ok <svc> [ver]        — notify deploy succeeded"
            echo "  $0 deploy-fail <svc> [ver] [reason] — notify deploy failed"
            echo "  $0 status                       — print mesh state"
            echo ""
            echo "Environment variables:"
            echo "  REPOWIRE_API  (default: http://127.0.0.1:8377)"
            echo "  LOGFILE       (default: /var/log/repowire/deploy-hooks.log)"
            echo "  PEER_NAME     (default: wheeler-deploy)"
            echo "  CIRCLE_NAME   (default: wheeler-core)"
            echo "  CURL_TIMEOUT  (default: 5)"
            echo "  CURL_RETRIES  (default: 2)"
            echo ""
            echo "Sourcing:"
            echo "  source $0"
            echo "  repowire_hook_check_mesh"
            echo "  repowire_hook_broadcast \"msg\""
            echo "  repowire_hook_gate 1 \"svc\" \"pass\""
            exit 0
            ;;
        *)
            echo "Unknown command: ${1}"
            echo "Usage: $0 <command> [args]"
            echo "Commands: check-mesh, broadcast, notify, gate, deploy-start, deploy-ok, deploy-fail, status, help"
            exit 1
            ;;
    esac
fi
