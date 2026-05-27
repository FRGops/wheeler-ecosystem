#!/usr/bin/env bash
# =============================================================================
# infra-wiring.sh  —  Wheeler-Repowire Infrastructure Wiring
#
# Bridges the 114 PM2 processes and all infrastructure state into the repowire
# agent mesh.  Maintains a local PM2 service registry, pushes state-change
# events (crashes, restarts, deployments) into the mesh via broadcast/notify,
# and integrates with the wheeler-healer for autonomous crash notification.
#
# ARCHITECTURE NOTE:
#   repowire peers are running Claude Code sessions (not individual services).
#   The 10 domain peers (wheeler-orchestrator, wheeler-infra, etc.) are
#   defined in ~/.repowire/config.yaml and are the actual mesh participants.
#   This script tracks PM2 service state in a local registry and broadcasts
#   events into the mesh — it does NOT create individual peers per service.
#
# Part of:  deployment-engine/repowire/
# Requires: repowire daemon on http://127.0.0.1:8377, curl, python3
#
# Commands:
#   register    <service-name> [circle]  — Track a PM2 service in registry
#   deregister  <service-name>           — Remove from registry
#   health                               — Repowire health + PM2 registry status
#   sync-all                             — Sync ALL running PM2 services
#   notify-crash <service-name> <status> — Push crash event into mesh
#   notify-mesh  <message>               — Broadcast to all mesh peers
# =============================================================================
set -euo pipefail

REPOWIRE_API="http://127.0.0.1:8377"
SELF_NAME="wheeler-infra"
REGISTRY="/opt/wheeler/repowire-pm2-registry.json"
LOCKFILE="/tmp/infra-wiring.lock"

# ── Colour helpers (quiet when piped / cron) ────────────────────────────────
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; RST='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; CYAN=''; RST=''
fi
ok()   { echo -e "  ${GREEN}OK${RST}  $*"; }
warn() { echo -e "  ${YELLOW}WARN${RST} $*"; }
fail() { echo -e "  ${RED}FAIL${RST} $*"; }
info() { echo -e "  ${CYAN}INFO${RST} $*"; }

# ── Lock (prevent concurrent sync-all) ──────────────────────────────────────
acquire_lock() {
    exec 9>"$LOCKFILE"
    flock -n 9 || { fail "Another instance is running (lock: $LOCKFILE)"; exit 1; }
}
release_lock() { flock -u 9 2>/dev/null || true; }
trap release_lock EXIT

# ── Daemon check ────────────────────────────────────────────────────────────
daemon_alive() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$REPOWIRE_API/health" 2>/dev/null || echo "000")
    [[ "$code" == "200" ]]
}

die_if_daemon_down() {
    if ! daemon_alive; then
        fail "repowire daemon is not responding at $REPOWIRE_API/health"
        echo "  Start it with:  pm2 start repowire-daemon"
        exit 1
    fi
}

# ── Circle detection ────────────────────────────────────────────────────────
# Maps service names to the 10 domain circles from ~/.repowire/config.yaml.
# Order matters: more specific patterns first, fallback to wheeler-ops.
detect_circle() {
    local lower
    lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')

    # Core infrastructure
    if echo "$lower" | grep -qE '^repowire|^wheeler-brain|^command-center|^ecosystem-'; then
        echo "wheeler-core"; return
    fi
    # Financial / revenue
    if echo "$lower" | grep -qE 'stripe|revenue|financial|treasury|frgops-stripe'; then
        echo "wheeler-finance"; return
    fi
    # Growth / marketing
    if echo "$lower" | grep -qE 'seo|content-?marketing|social-?media|link-?building|email-?marketing|conversion-?optimization|campaign'; then
        echo "wheeler-growth"; return
    fi
    # Security
    if echo "$lower" | grep -qE 'security|penetration-?test|vulnerability|threat-?intel|compliance|rls-?auditor'; then
        echo "wheeler-security"; return
    fi
    # Database / data
    if echo "$lower" | grep -qE '^database|^data-?warehouse|^data-?quality|^data-?pipeline|^etl-|^warehouse|neo4j|qdrant|pgvector'; then
        echo "wheeler-db"; return
    fi
    # Monitoring
    if echo "$lower" | grep -qE 'monitoring|prometheus|grafana|gatus|uptime|alert'; then
        echo "wheeler-monitoring"; return
    fi
    # Deployment
    if echo "$lower" | grep -qE 'deployment|rollback|repo-engine|repo-listener'; then
        echo "wheeler-deploy"; return
    fi
    # Legal / compliance
    if echo "$lower" | grep -qE 'compliance|fcra|tcpa|ccpa|surplus|esi-?check|rule54'; then
        echo "wheeler-legal"; return
    fi
    # Revenue ops
    if echo "$lower" | grep -qE 'frgcrm|frgops|surplusai|eligibility|crm-?sync'; then
        echo "wheeler-revenue"; return
    fi
    # Agent services — infer domain from the first word
    if echo "$lower" | grep -qE 'agent-svc$'; then
        local base
        base=$(echo "$lower" | sed 's/-agent-svc$//')
        detect_circle "$base"
        return
    fi
    # Scrapers, voice, outreach — operational
    if echo "$lower" | grep -qE 'scraper|crawlee|scraper-fleet|miami|county-|voice|outreach'; then
        echo "wheeler-ops"; return
    fi
    echo "wheeler-ops"
}

# Map circle to domain peer name (from ~/.repowire/config.yaml)
circle_to_domain_peer() {
    case "${1:-}" in
        wheeler-core)     echo "wheeler-orchestrator" ;;
        wheeler-ops)      echo "wheeler-infra" ;;
        wheeler-finance)  echo "wheeler-financial" ;;
        wheeler-growth)   echo "wheeler-growth" ;;
        wheeler-legal)    echo "wheeler-compliance" ;;
        wheeler-security) echo "wheeler-security" ;;
        wheeler-db)       echo "wheeler-db" ;;
        wheeler-monitoring) echo "wheeler-monitoring" ;;
        wheeler-deploy)   echo "wheeler-deploy" ;;
        wheeler-revenue)  echo "wheeler-revenue" ;;
        *)                echo "" ;;
    esac
}

# ── HTTP helpers ────────────────────────────────────────────────────────────

repowire_post() {
    local path="$1" data="$2"
    curl -s -X POST "$REPOWIRE_API$path" \
        -H "Content-Type: application/json" \
        -d "$data" --max-time 5 2>/dev/null
}

repowire_get() {
    local path="$1"
    curl -s --max-time 5 "$REPOWIRE_API$path" 2>/dev/null || echo '{}'
}

# ── Local PM2 Registry ──────────────────────────────────────────────────────
# JSON file at /opt/wheeler/repowire-pm2-registry.json tracking all PM2
# services known to the infrastructure layer.

init_registry() {
    if [[ ! -f "$REGISTRY" ]]; then
        mkdir -p "$(dirname "$REGISTRY")"
        echo '{"version":2,"pm2_services":{},"generated_at":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'> "$REGISTRY"
    fi
}

registry_add_service() {
    local name="$1" circle="$2" status="$3" restarts="$4"
    init_registry
    local tmp; tmp=$(mktemp)
    python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
data['pm2_services']['$name'] = {
    'circle': '$circle',
    'status': '$status',
    'restarts': $restarts,
    'updated_at': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
}
data['generated_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$tmp', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
    mv "$tmp" "$REGISTRY"
}

registry_remove_service() {
    local name="$1"
    init_registry
    local tmp; tmp=$(mktemp)
    python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
data['pm2_services'].pop('$name', None)
data['generated_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$tmp', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
    mv "$tmp" "$REGISTRY"
}

registry_is_tracked() {
    local name="$1"
    [[ ! -f "$REGISTRY" ]] && return 1
    python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
sys.exit(0 if '$name' in data.get('pm2_services',{}) else 1)
" 2>/dev/null
}

registry_count() {
    [[ ! -f "$REGISTRY" ]] && { echo "0"; return; }
    python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
print(len(data.get('pm2_services',{})))
" 2>/dev/null || echo "0"
}

registry_circles_summary() {
    [[ ! -f "$REGISTRY" ]] && return
    python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
circles = {}
for v in data.get('pm2_services',{}).values():
    c = v.get('circle','?')
    circles[c] = circles.get(c, 0) + 1
for c in sorted(circles):
    print(f'{c}={circles[c]}')
" 2>/dev/null
}

# ── register: track a single PM2 service ────────────────────────────────────

cmd_register() {
    local service_name="$1"
    local circle="${2:-$(detect_circle "$service_name")}"

    init_registry

    if registry_is_tracked "$service_name"; then
        info "Already tracked: $service_name (circle: $circle)"
        return 0
    fi

    registry_add_service "$service_name" "$circle" "registered" "0"
    ok "Tracked: $service_name (circle: $circle)"

    # Broadcast registration event
    if daemon_alive; then
        local msg="[REGISTER] PM2 service '$service_name' registered in circle=$circle"
        repowire_post "/broadcast" \
            "{\"from_peer\":\"$SELF_NAME\",\"text\":\"$msg\"}" >/dev/null 2>&1 || true
    fi
}

# ── deregister: remove from registry ────────────────────────────────────────

cmd_deregister() {
    local service_name="$1"

    if ! registry_is_tracked "$service_name"; then
        info "Not tracked: $service_name (nothing to deregister)"
        return 0
    fi

    registry_remove_service "$service_name"
    ok "Removed from registry: $service_name"

    # Broadcast deregistration event
    if daemon_alive; then
        local msg="[DEREGISTER] PM2 service '$service_name' removed from wheel-infra registry"
        repowire_post "/broadcast" \
            "{\"from_peer\":\"$SELF_NAME\",\"text\":\"$msg\"}" >/dev/null 2>&1 || true
    fi
}

# ── sync-all: reconcile registry with live PM2 state ────────────────────────

cmd_sync_all() {
    acquire_lock
    init_registry

    echo ""
    info "=== PM2 -> Infra Registry Sync ==="
    info "Reconciling registry with live PM2 processes..."
    echo ""

    # Dump live PM2 state to temp file
    local pm2_snap; pm2_snap=$(mktemp)
    pm2 jlist 2>/dev/null | python3 -c "
import json, sys
procs = json.load(sys.stdin)
for p in procs:
    pm = p['pm2_env']
    print(f\"{pm['name']}|{pm['status']}|{pm.get('restart_time', 0)}\")
" > "$pm2_snap" 2>/dev/null || true

    local total=0 added=0 removed=0 changed=0 errors=0

    # ── Phase 1: Register/add all live services ──
    while IFS='|' read -r name status restarts; do
        total=$((total + 1))
        circle=$(detect_circle "$name")

        if registry_is_tracked "$name"; then
            # Already tracked — silent update (no broadcast on every sync)
            registry_add_service "$name" "$circle" "$status" "$restarts"
        else
            registry_add_service "$name" "$circle" "$status" "$restarts"
            added=$((added + 1))
        fi
    done < "$pm2_snap"

    # ── Phase 2: Remove services that no longer exist in PM2 ──
    local live_names; live_names=$(mktemp)
    cut -d'|' -f1 "$pm2_snap" > "$live_names"

    if [[ -f "$REGISTRY" ]]; then
        python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
with open('$live_names') as f:
    live = set(line.strip() for line in f if line.strip())
to_remove = [k for k in data.get('pm2_services',{}) if k not in live]
for k in to_remove:
    data['pm2_services'].pop(k)
if to_remove:
    print('\n'.join(to_remove))
with open('$REGISTRY', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null > "$pm2_snap.removed" || true
        if [[ -s "$pm2_snap.removed" ]]; then
            while IFS= read -r dead_name; do
                removed=$((removed + 1))
            done < "$pm2_snap.removed"
        fi
    fi

    rm -f "$pm2_snap" "$live_names" "$pm2_snap.removed"

    # ── Summary ──
    local count; count=$(registry_count)
    echo ""
    ok "Sync complete"
    info "  Total live PM2:   $total"
    info "  Added to registry: $added"
    info "  Removed (dead):    $removed"
    info "  Registry total:    $count services"
    echo ""
    info "--- Circle distribution ---"
    registry_circles_summary
    echo ""

    # Broadcast summary to mesh
    if daemon_alive; then
        local msg="[SYNC] PM2 registry synced: $count services tracked (${added} new, ${removed} gone) on wheeler-infra"
        repowire_post "/broadcast" \
            "{\"from_peer\":\"$SELF_NAME\",\"text\":\"$msg\"}" >/dev/null 2>&1 || true
        ok "Broadcast sent to mesh"
    fi

    echo "  Registry: $REGISTRY"
}

# ── health: daemon + mesh + registry status ─────────────────────────────────

cmd_health() {
    echo ""
    info "=== Repowire Mesh Health ==="
    echo ""

    if ! daemon_alive; then
        fail "repowire daemon DOWN at $REPOWIRE_API/health"
        echo ""
        info "To restart:  pm2 start repowire-daemon"
        return 1
    fi
    ok "Daemon reachable at $REPOWIRE_API/health"

    # Full health JSON
    local health_json; health_json=$(repowire_get "/health")
    local status; status=$(echo "$health_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
    local version; version=$(echo "$health_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null || echo "?")

    echo ""
    info "Daemon:   $status"
    info "Version:  $version"

    # ACP broker
    echo "$health_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
b=d.get('acp_broker',{})
print(f'  ACP Broker:     status={b.get(\"status\",\"?\")}  configured={b.get(\"configured_peers\",0)} peers')
c=d.get('channel',{})
print(f'  Channel:        status={c.get(\"status\",\"?\")}  configured={c.get(\"configured\",False)}')
" 2>/dev/null

    # Peer list
    echo ""
    info "--- Mesh Peers ---"
    if command -v repowire &>/dev/null; then
        repowire peer list 2>/dev/null || echo "  (unavailable)"
    else
        local peers_json; peers_json=$(repowire_get "/peers")
        echo "$peers_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
peers=d.get('peers',[])
if not peers:
    print('  No peers connected')
else:
    for p in peers:
        print(f'  {p.get(\"display_name\",\"?\")}  status={p.get(\"status\",\"?\")}  circle={p.get(\"circle\",\"?\")}')
" 2>/dev/null
    fi

    # Schedules
    echo ""
    info "--- Scheduled Jobs ---"
    local sched_json; sched_json=$(repowire_get "/schedules")
    echo "$sched_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
scheds=d.get('schedules',[])
if not scheds:
    print('  No schedules configured')
else:
    for s in scheds:
        print(f'  {s.get(\"schedule_id\",\"?\")}  {s.get(\"cron\",\"?\")}  -> {s.get(\"to_peer\",\"?\")}  kind={s.get(\"kind\",\"?\")}')
" 2>/dev/null

    # PM2 Registry
    echo ""
    info "--- PM2 Service Registry ---"
    if [[ -f "$REGISTRY" ]]; then
        python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
svcs = data.get('pm2_services', {})
print(f'  Total services:  {len(svcs)}')
print(f'  Generated at:    {data.get(\"generated_at\",\"?\")}')
print(f'')
print(f'  Circles:')
circles = {}
for k,v in svcs.items():
    c = v.get('circle','?')
    circles[c] = circles.get(c,0)+1
for c in sorted(circles):
    print(f'    {c}: {circles[c]} services')
" 2>/dev/null

        # Top 5 by restarts
        echo ""
        echo "  Top 5 by restart count:"
        python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
svcs = sorted(data.get('pm2_services',{}).items(), key=lambda x: x[1].get('restarts',0), reverse=True)[:5]
if svcs:
    for name, info in svcs:
        r = info.get('restarts',0)
        if r > 0:
            print(f'    {name}: {r} restarts')
else:
    print('    (no restart data)')
" 2>/dev/null
    else
        echo "  Registry not yet created (run sync-all)"
    fi

    echo ""
    ok "Health check complete"
}

# ── notify-crash: push crash event into mesh ────────────────────────────────

cmd_notify_crash() {
    local service_name="$1"
    local crash_status="${2:-stopped}"
    local circle; circle=$(detect_circle "$service_name")
    local timestamp; timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Update registry
    init_registry
    registry_add_service "$service_name" "$circle" "$crash_status" "0"

    # Build notification message
    local msg="[CRASH] PM2 service='$service_name' status=$crash_status at ${timestamp}Z circle=$circle"

    die_if_daemon_down

    # 1. Notify wheeler-infra (self / ops)
    repowire_post "/notify" \
        "{\"from_peer\":\"$SELF_NAME\",\"to_peer\":\"wheeler-infra\",\"text\":\"$msg\"}" \
        >/dev/null 2>&1 || true

    # 2. Notify the circle's domain peer (e.g. wheeler-financial for stripe)
    local domain_peer; domain_peer=$(circle_to_domain_peer "$circle")
    if [[ -n "$domain_peer" && "$domain_peer" != "wheeler-infra" ]]; then
        repowire_post "/notify" \
            "{\"from_peer\":\"$SELF_NAME\",\"to_peer\":\"$domain_peer\",\"text\":\"$msg\"}" \
            >/dev/null 2>&1 || true
    fi

    # 3. Broadcast to all peers
    repowire_post "/broadcast" \
        "{\"from_peer\":\"$SELF_NAME\",\"text\":\"$msg\"}" \
        >/dev/null 2>&1 || true

    ok "Crash notification sent: $service_name ($crash_status)"
    info "  Targets: wheeler-infra${domain_peer:+, $domain_peer} + broadcast"

    # Update registry with crash data
    registry_add_service "$service_name" "$circle" "crashed" "0"
}

# ── notify-mesh: broadcast to all peers ─────────────────────────────────────

cmd_notify_mesh() {
    local message="$1"
    die_if_daemon_down

    local result; result=$(repowire_post "/broadcast" \
        "{\"from_peer\":\"$SELF_NAME\",\"text\":\"$message\"}")

    if echo "$result" | grep -q '"ok":true'; then
        ok "Broadcast sent: ${message:0:120}"
    else
        local detail; detail=$(echo "$result" | head -c 200)
        fail "Broadcast failed: $detail"
    fi
}

# ── help ────────────────────────────────────────────────────────────────────

show_help() {
    cat <<'HELP'
USAGE:
    infra-wiring.sh <command> [args...]

COMMANDS:
    register <service-name> [circle]
        Track a PM2 service in the local registry and notify the mesh.
        Circle auto-detected from service name if omitted.

    deregister <service-name>
        Remove a PM2 service from the registry and notify the mesh.

    health
        Check repowire daemon health, show mesh peers, scheduled jobs,
        and the full PM2 service registry with circle distribution.

    sync-all
        Reconcile the local PM2 registry with all currently-running PM2
        processes.  Adds new services, removes dead ones, broadcasts a
        summary to the mesh.

    notify-crash <service-name> <status>
        Push a crash event into the mesh.  Notifies wheeler-infra and the
        service's circle domain peer, broadcasts to all peers.
        Typical status: stopped, errored, crashed.

    notify-mesh <message>
        Broadcast an arbitrary message to all mesh peers from wheeler-infra.

    help
        Show this help.

EXAMPLES:
    infra-wiring.sh sync-all
    infra-wiring.sh register frgcrm-api wheeler-revenue
    infra-wiring.sh deregister frgcrm-api
    infra-wiring.sh health
    infra-wiring.sh notify-crash frgcrm-api stopped
    infra-wiring.sh notify-mesh "Deploy complete: v2.1 live"

FILES:
    Registry:      /opt/wheeler/repowire-pm2-registry.json
    Config:        ~/.repowire/config.yaml (10 domain peers)
    API:           http://127.0.0.1:8377

INTEGRATION (wheeler-healer):
    Add to /opt/wheeler-healer/healer_core.py in the crash handler:
        subprocess.run([
            "/root/deployment-engine/repowire/infra-wiring.sh",
            "notify-crash", service_name, status
        ])
HELP
}

# ── main ────────────────────────────────────────────────────────────────────

main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        register)
            local svc="${1:-}"
            local circle="${2:-}"
            if [[ -z "$svc" ]]; then
                fail "Usage: infra-wiring.sh register <service-name> [circle]"
                exit 1
            fi
            cmd_register "$svc" "$circle"
            ;;
        deregister)
            local svc="${1:-}"
            if [[ -z "$svc" ]]; then
                fail "Usage: infra-wiring.sh deregister <service-name>"
                exit 1
            fi
            cmd_deregister "$svc"
            ;;
        health)
            cmd_health
            ;;
        sync-all)
            cmd_sync_all
            ;;
        notify-crash)
            local svc="${1:-}"
            local st="${2:-stopped}"
            if [[ -z "$svc" ]]; then
                fail "Usage: infra-wiring.sh notify-crash <service-name> <status>"
                exit 1
            fi
            cmd_notify_crash "$svc" "$st"
            ;;
        notify-mesh)
            local msg="${1:-}"
            if [[ -z "$msg" ]]; then
                fail "Usage: infra-wiring.sh notify-mesh <message>"
                exit 1
            fi
            cmd_notify_mesh "$msg"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            fail "Unknown command: $cmd. Try: infra-wiring.sh help"
            exit 1
            ;;
    esac
}

main "$@"
