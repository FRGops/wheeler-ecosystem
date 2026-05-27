#!/bin/bash
# Repowire Auto-Wire for Builds — source this in any build to auto-join the mesh
# Usage: source /root/deployment-engine/repowire/auto-wire-build.sh
# Then: rw_broadcast "BUILD STARTED: $TASK_NAME"
#       rw_notify "wheeler-deploy" "Phase PLAN completed"
#       rw_build_done 100/100

REPOWIRE_API="${REPOWIRE_API:-http://127.0.0.1:8377}"
RW_LOG="/var/log/repowire/builds.log"
RW_PEER="${RW_PEER:-builder-$(date +%s)}"
RW_BUILD_ID="${RW_BUILD_ID:-build-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$(dirname "$RW_LOG")"

_rw_api() {
    curl -s -X POST "$REPOWIRE_API/$1" -H "Content-Type: application/json" -d "$2" 2>/dev/null || true
}

rw_broadcast() {
    local msg="$1"
    echo "[repowire] BROADCAST: $msg"
    _rw_api "broadcast" "{\"from_peer\":\"$RW_PEER\",\"text\":\"[$RW_BUILD_ID] $msg\"}"
    echo "[$(date -Iseconds)] $RW_BUILD_ID BROADCAST: $msg" >> "$RW_LOG"
}

rw_notify() {
    local target="$1"
    local msg="$2"
    echo "[repowire] NOTIFY $target: $msg"
    _rw_api "notify" "{\"from_peer\":\"$RW_PEER\",\"to_peer\":\"$target\",\"text\":\"[$RW_BUILD_ID] $msg\"}"
    echo "[$(date -Iseconds)] $RW_BUILD_ID NOTIFY $target: $msg" >> "$RW_LOG"
}

rw_phase() {
    local phase="$1"
    local status="${2:-started}"
    rw_broadcast "Phase $phase: $status"
}

rw_build_done() {
    local result="${1:-UNKNOWN}"
    rw_broadcast "BUILD COMPLETE: $result"
    echo "[$(date -Iseconds)] $RW_BUILD_ID COMPLETE: $result" >> "$RW_LOG"
}

rw_health() {
    curl -s "$REPOWIRE_API/health" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','down'))" 2>/dev/null || echo "down"
}

echo "[repowire] Auto-wired build $RW_BUILD_ID (peer: $RW_PEER)"
rw_broadcast "BUILD STARTED — peer $RW_PEER joined mesh"
