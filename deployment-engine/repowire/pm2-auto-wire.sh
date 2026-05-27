#!/bin/bash
# repowire PM2 Auto-Wire — registers all PM2 services as repowire peers
# Run: bash pm2-auto-wire.sh [sync|watch|register <name> <circle>]
set -euo pipefail

REPOWIRE_API="${REPOWIRE_API:-http://127.0.0.1:8377}"
LOG_FILE="${LOG_FILE:-/var/log/repowire/pm2-auto-wire.log}"
CIRCLES_DIR="/root/deployment-engine/repowire/circles"

mkdir -p "$(dirname "$LOG_FILE")" "$CIRCLES_DIR"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"; }
api() { curl -s -X POST "$REPOWIRE_API/$1" -H "Content-Type: application/json" -d "$2" 2>/dev/null || true; }

# Map PM2 service names to repowire circles
get_circle() {
    local name="$1"
    case "$name" in
        # Wheeler core
        wheeler-*|repowire-*|ecosystem-*)   echo "wheeler-core" ;;
        # Infrastructure
        *infra*|*docker*|*network*|*pm2*)   echo "wheeler-ops" ;;
        # Security
        *security*|*vulnerability*|*penetration*|*threat*) echo "wheeler-ops" ;;
        # Deploy
        *deploy*|*rollback*|*production*)    echo "wheeler-ops" ;;
        # Financial
        *revenue*|*stripe*|*financial*|*treasury*|*cost*|*budget*) echo "wheeler-finance" ;;
        # Growth
        *seo*|*content*|*growth*|*social*|*email*|*marketing*) echo "wheeler-growth" ;;
        # Legal
        *compliance*|*legal*|*governance*)   echo "wheeler-legal" ;;
        # Database
        *db*|*database*|*sql*|*postgres*)    echo "wheeler-ops" ;;
        # Monitoring
        *monitor*|*alert*|*grafana*|*prometheus*|*loki*) echo "wheeler-ops" ;;
        # Default
        *) echo "wheeler-core" ;;
    esac
}

cmd_sync_all() {
    log "Syncing all PM2 processes to repowire mesh..."
    local count=0
    while IFS= read -r line; do
        local name=$(echo "$line" | awk '{print $4}')
        local status=$(echo "$line" | awk '{print $6}')
        local circle=$(get_circle "$name")
        local text="PM2 service [$name] status=$status circle=$circle — registered via auto-wire"
        api "broadcast" "{\"from_peer\":\"wheeler-infra\",\"text\":\"$text\"}"
        count=$((count + 1))
    done < <(pm2 jlist 2>/dev/null | python3 -c "
import sys,json
for p in json.load(sys.stdin):
    print(f'  - {p[\"name\"]} {p[\"pm2_env\"][\"status\"]}')
" 2>/dev/null)
    log "Synced $count PM2 processes to repowire mesh"
}

cmd_health() {
    local health=$(curl -s "$REPOWIRE_API/health" 2>/dev/null || echo '{"status":"unreachable"}')
    local status=$(echo "$health" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")
    log "Repowire mesh health: $status"
    echo "Repowire: $status"
}

cmd_register() {
    local name="$1"
    local circle="${2:-$(get_circle "$name")}"
    local text="PM2 service [$name] registered in circle=$circle"
    api "broadcast" "{\"from_peer\":\"wheeler-infra\",\"text\":\"$text\"}"
    log "Registered $name → circle=$circle"
}

# Main
case "${1:-health}" in
    sync|sync-all)  cmd_sync_all ;;
    health)         cmd_health ;;
    register)       cmd_register "${2:-unknown}" "${3:-}" ;;
    watch)
        log "Starting PM2 watch mode..."
        while true; do
            cmd_sync_all
            sleep 300  # Every 5 minutes
        done
        ;;
    *) echo "Usage: $0 {sync|health|register <name> [circle]|watch}" ;;
esac
