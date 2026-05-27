#!/usr/bin/env bash
# ==============================================================================
# Wheeler Docker Wiring — repowire agent mesh integration for Docker fleet
#
# Translates Docker container lifecycle events into repowire mesh notifications
# so that agents (wheeler-infra, wheeler-security, wheeler-ops) can respond.
#
# Architecture:
#   Docker daemon ─(events)──> docker-wiring.sh ──(HTTP)──> repowire :8377
#                                                                │
#                                           ┌────────────────────┼──────────────┐
#                                           ▼                    ▼              ▼
#                                     wheeler-infra      wheeler-security   wheeler-ops
#                                     (start/die/oom)    (die/oom)         (unhealthy)
#
# PM2:  wheeler-docker-wiring   |   depends on: repowire-daemon
#
# Commands:
#   docker-wiring.sh daemon     — Listen to Docker events and notify mesh
#   docker-wiring.sh sync-all   — Broadcast all running containers as fleet inventory
#   docker-wiring.sh health     — Quick health check
# ==============================================================================

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
REPOWIRE_API="${REPOWIRE_API:-http://127.0.0.1:8377}"
FROM_PEER="${FROM_PEER:-wheeler-docker}"
LOCK_FILE="/tmp/wheeler-docker-wiring.lock"
SCRIPT_NAME="docker-wiring"
REPOWIRE_TIMEOUT=5
EVENT_RETRY_DELAY=3
HEALTHCHECK_INTERVAL=30
MAX_RESTART_BACKOFF=60
VERSION="1.0.0"

# Rate limiting: skip duplicate events for same container within this window (seconds)
RATE_LIMIT_WINDOW=30

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $*"; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] ERROR: $*" >&2; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] WARN: $*" >&2; }

# Declare associative arrays for rate limiting
declare -A _last_event

_rate_limited() {
    local key="$1"
    local now
    now=$(date +%s)
    local last="${_last_event[$key]:-0}"
    if (( now - last < RATE_LIMIT_WINDOW )); then
        return 0  # true = rate limited
    fi
    _last_event["$key"]=$now
    return 1  # false = not rate limited
}

# ── repowire API helpers ─────────────────────────────────────────────────────

_repowire_http() {
    local endpoint="$1"
    local payload_file="$2"
    local resp
    resp=$(curl -s -S -m "$REPOWIRE_TIMEOUT" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "@${payload_file}" \
        "${REPOWIRE_API}${endpoint}" 2>&1) || {
        local rc=$?
        if [ "$rc" -eq 7 ] || [ "$rc" -eq 28 ]; then
            # Connection refused or timeout — daemon is down
            return 1
        fi
        warn "repowire POST ${endpoint} failed (exit=$rc): $(echo "$resp" | head -c 200)"
        return 1
    }
    # Check for success response — repowire returns {"ok":true} or {"status":"ok"}
    if echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ok = d.get('ok', False) or d.get('status', '') in ('ok', 'queued')
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        return 0
    fi
    warn "repowire POST ${endpoint} bad response: $(echo "$resp" | head -c 200)"
    return 1
}

# Broadcast a message to all repowire peers via /broadcast.
# Builds JSON payload with python3 (avoids bash escaping issues) and POSTs via curl.
_broadcast() {
    local text="$1"
    local tmpfile
    tmpfile=$(mktemp /tmp/wheeler-docker-broadcast-XXXXXX.json)

    python3 - "$FROM_PEER" "$text" > "$tmpfile" <<'PYEOF'
import json, sys
payload = {"from_peer": sys.argv[1], "text": sys.argv[2]}
print(json.dumps(payload, ensure_ascii=False))
PYEOF

    if _repowire_http "/broadcast" "$tmpfile"; then
        log "broadcast: $(echo "$text" | tr '\n' ' ' | head -c 100)"
        rm -f "$tmpfile"
        return 0
    fi
    rm -f "$tmpfile"
    return 1
}

_repowire_healthy() {
    curl -s -S -m "$REPOWIRE_TIMEOUT" "${REPOWIRE_API}/health" >/dev/null 2>&1
}

# ── Event handlers ───────────────────────────────────────────────────────────
# All events are broadcast so any connected repowire peer can filter.
# Messages carry routing tags for peer-side filtering:
#   [INFRA]     — infrastructure lifecycle (start/die/oom)
#   [SECURITY]  — security-relevant events (die/oom with context)
#   [OPS]       — operations alerts (unhealthy health checks)

_handle_start() {
    local container_name="$1" container_id="$2" image="$3"
    if _rate_limited "start:$container_name"; then
        return
    fi
    local msg="[INFRA] DOCKER START: ${container_name} (${image:0:30}) | container_id=${container_id}"
    _broadcast "$msg"
}

_handle_die() {
    local container_name="$1" container_id="$2" exit_code="$3" image="$4"
    if _rate_limited "die:$container_name"; then
        return
    fi
    local msg="[INFRA][SECURITY] DOCKER DIED: ${container_name} (${image:0:30}) | container_id=${container_id} exit_code=${exit_code}"
    _broadcast "$msg"
}

_handle_oom() {
    local container_name="$1" container_id="$2" image="$3"
    if _rate_limited "oom:$container_name"; then
        return
    fi
    local msg="[INFRA][SECURITY] DOCKER OOM: ${container_name} (${image:0:30}) | container_id=${container_id} | P1 — killed by OOM killer"
    _broadcast "$msg"
}

_handle_unhealthy() {
    local container_name="$1" container_id="$2" image="$3"
    if _rate_limited "unhealthy:$container_name"; then
        return
    fi
    local msg="[OPS] DOCKER UNHEALTHY: ${container_name} (${image:0:30}) | container_id=${container_id} | health check failing — investigate immediately"
    _broadcast "$msg"
}

# ── Event stream processor ───────────────────────────────────────────────────

_process_event() {
    local line="$1"

    # Extract event fields
    local action container_name image exit_code

    action=$(echo "$line" | python3 -c "
import sys, json
try:
    e = json.load(sys.stdin)
    print(e.get('Action', ''))
except Exception:
    print('')
" 2>/dev/null) || return

    container_name=$(echo "$line" | python3 -c "
import sys, json
try:
    e = json.load(sys.stdin)
    attrs = e.get('Actor', {}).get('Attributes', {})
    print(attrs.get('name', ''))
except Exception:
    print('')
" 2>/dev/null) || return

    container_id=$(echo "$line" | python3 -c "
import sys, json
try:
    e = json.load(sys.stdin)
    print(e.get('Actor', {}).get('ID', '')[:12])
except Exception:
    print('')
" 2>/dev/null) || container_id="unknown"

    image=$(echo "$line" | python3 -c "
import sys, json
try:
    e = json.load(sys.stdin)
    attrs = e.get('Actor', {}).get('Attributes', {})
    print(attrs.get('image', ''))
except Exception:
    print('')
" 2>/dev/null) || image=""

    exit_code=$(echo "$line" | python3 -c "
import sys, json
try:
    e = json.load(sys.stdin)
    attrs = e.get('Actor', {}).get('Attributes', {})
    print(attrs.get('exitCode', ''))
except Exception:
    print('')
" 2>/dev/null) || exit_code=""

    # Skip exec events — we only want container lifecycle events
    if echo "$action" | grep -qE '^exec_'; then
        return
    fi

    # Skip empty names (system containers, etc.)
    if [ -z "$container_name" ]; then
        return
    fi

    # Dispatch by action
    case "$action" in
        start)
            _handle_start "$container_name" "$container_id" "$image"
            ;;
        die)
            _handle_die "$container_name" "$container_id" "$exit_code" "$image"
            ;;
        oom)
            _handle_oom "$container_name" "$container_id" "$image"
            ;;
        health_status*)
            # health_status events look like "health_status: healthy" or "health_status: unhealthy"
            if echo "$action" | grep -q "unhealthy"; then
                _handle_unhealthy "$container_name" "$container_id" "$image"
            fi
            ;;
        *)
            # Silently ignore other events
            ;;
    esac
}

# ── sync-all: broadcast current fleet inventory ──────────────────────────────

_cmd_sync_all() {
    log "=== FLEET INVENTORY SYNC ==="

    local total_containers healthy_count unhealthy_count
    total_containers=$(docker ps -q | wc -l)

    # Count healthy vs unhealthy containers
    healthy_count=$(docker ps --filter "health=healthy" -q | wc -l || echo 0)
    unhealthy_count=$(docker ps --filter "health=unhealthy" -q | wc -l || echo 0)

    # Group containers by compose project for a structured inventory
    local project_summary
    project_summary=$(docker ps --format '{{.Names}}' 2>/dev/null | \
        sed 's/^\([a-z]*-[a-z]*\)-.*/\1/' | \
        sort | uniq -c | sort -rn | \
        awk '{sum+=$1; printf "%sx %s, ", $1, $2} END {print ""}' | \
        sed 's/, $//')

    local msg="[INFRA] DOCKER FLEET SYNC: ${total_containers} running | ${healthy_count} healthy | ${unhealthy_count} unhealthy | groups: ${project_summary}"

    if _broadcast "$msg"; then
        log "sync-all complete: ${total_containers} containers registered"
    else
        err "sync-all FAILED — repowire unreachable at ${REPOWIRE_API}"
        return 1
    fi
}

# ── Daemon: main event loop ──────────────────────────────────────────────────

_daemon_loop() {
    log "Wheeler Docker Wiring v${VERSION}"
    log "repowire API: ${REPOWIRE_API}"
    log "from_peer: ${FROM_PEER}"
    log "monitoring Docker events..."

    local backoff=1
    local consecutive_failures=0

    while true; do
        # Check if repowire is healthy before subscribing
        if ! _repowire_healthy; then
            consecutive_failures=$((consecutive_failures + 1))
            local delay=$(( backoff > MAX_RESTART_BACKOFF ? MAX_RESTART_BACKOFF : backoff ))
            warn "repowire not reachable at ${REPOWIRE_API} (attempt ${consecutive_failures}) — retry in ${delay}s"
            sleep "$delay"
            backoff=$((backoff * 2))
            continue
        fi

        # Reset backoff on successful connection
        if [ "$consecutive_failures" -gt 0 ]; then
            log "repowire connection restored after ${consecutive_failures} retries"
        fi
        consecutive_failures=0
        backoff=1

        # Subscribe to Docker events — this blocks until the pipe breaks
        docker events \
            --filter 'type=container' \
            --filter 'event=start' \
            --filter 'event=die' \
            --filter 'event=oom' \
            --filter 'event=health_status' \
            --format '{{json .}}' 2>&1 | while IFS= read -r line; do

            # PM2 restart signal check — parent might have sent SIGTERM
            if [ ! -f "$LOCK_FILE" ]; then
                log "lock file removed — shutting down event consumer"
                exit 0
            fi

            if [ -z "$line" ]; then
                continue
            fi

            _process_event "$line"
        done

        # If we get here, the docker events stream ended (docker restart, etc.)
        warn "Docker event stream disconnected — reconnecting in ${EVENT_RETRY_DELAY}s..."
        sleep "$EVENT_RETRY_DELAY"
    done
}

# ── Health check ─────────────────────────────────────────────────────────────

_health_check() {
    # Check if we're running
    if [ -f "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
        if kill -0 "$pid" 2>/dev/null; then
            echo "STATUS: running (pid=$pid)"
        else
            echo "STATUS: stale lock file (pid=$pid not running)"
            rm -f "$LOCK_FILE"
        fi
    else
        echo "STATUS: not running"
    fi

    # Check repowire connectivity
    if _repowire_healthy; then
        echo "REPOWIRE: reachable at ${REPOWIRE_API}"
    else
        echo "REPOWIRE: UNREACHABLE at ${REPOWIRE_API}"
    fi

    # Docker status
    local docker_running
    docker_running=$(docker ps -q | wc -l)
    echo "DOCKER: ${docker_running} containers running"
}

# ── Signal handling ──────────────────────────────────────────────────────────

_cleanup() {
    log "Shutting down..."
    rm -f "$LOCK_FILE"
    log "Goodbye."
    exit 0
}

_cmd_daemon() {
    # Ensure single instance
    if [ -f "$LOCK_FILE" ]; then
        local existing_pid
        existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
            err "Already running (pid=$existing_pid). Use 'stop' first or remove $LOCK_FILE"
            exit 1
        fi
        warn "Stale lock file found — removing"
        rm -f "$LOCK_FILE"
    fi

    trap _cleanup SIGTERM SIGINT EXIT

    # Write lock file
    echo "$$" > "$LOCK_FILE"
    log "PID $$ — lock file written to $LOCK_FILE"

    _daemon_loop
}

_cmd_stop() {
    if [ -f "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "Sending SIGTERM to pid $pid"
            kill "$pid" 2>/dev/null || true
            sleep 1
            rm -f "$LOCK_FILE"
            log "Stopped."
        else
            warn "PID $pid not running — cleaning up lock"
            rm -f "$LOCK_FILE"
        fi
    else
        warn "Not running (no lock file found)"
    fi
}

_cmd_help() {
    echo "Wheeler Docker Wiring v${VERSION}"
    echo ""
    echo "USAGE:"
    echo "  $0 daemon       — Start Docker event monitor daemon"
    echo "  $0 sync-all     — Broadcast current fleet inventory to mesh"
    echo "  $0 health       — Check daemon and connectivity health"
    echo "  $0 stop         — Stop the running daemon"
    echo ""
    echo "ENVIRONMENT:"
    echo "  REPOWIRE_API    — repowire endpoint (default: http://127.0.0.1:8377)"
    echo "  FROM_PEER       — source peer name (default: wheeler-docker)"
    echo ""
    echo "PM2 DEPLOYMENT:"
    echo "  pm2 start $0 --interpreter bash --name wheeler-docker-wiring -- daemon"
    echo "  pm2 start $0 --interpreter bash --name wheeler-docker-sync -- sync-all"
}

# ── Entry point ──────────────────────────────────────────────────────────────

case "${1:-daemon}" in
    daemon)
        _cmd_daemon
        ;;

    sync-all)
        _cmd_sync_all
        ;;

    health|status)
        _health_check
        ;;

    stop)
        _cmd_stop
        ;;

    --help|-h|help)
        _cmd_help
        ;;

    *)
        echo "Unknown command: $1"
        echo "Usage: $0 {daemon|sync-all|health|stop|help}"
        exit 1
        ;;
esac
