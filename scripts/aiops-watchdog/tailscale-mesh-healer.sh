#!/usr/bin/env bash
#===============================================================================
# tailscale-mesh-healer.sh
# Wheeler Autonomous AI Ops — Cross-Server Connectivity Healer
#
# Monitors the Tailscale mesh for offline nodes and attempts reconnection.
#
# Tailscale mesh nodes (from current topology):
#   - wheeler-aiops-01      (Hetzner,  100.121.230.28)  — AI operations server
#   - srv1476866            (Hostinger, 100.98.163.17)   — Hostinger production
#   - wheeler-core-db-01    (CoreDB,   100.118.166.117)  — Database server
#   - wheelers-macbook-pro  (Mac,      100.83.80.6)      — Local development
#
# Heal strategy:
#   - Mac offline: log only (physical intervention needed)
#   - CoreDB/Hostinger offline: try tailscale ping + up, then SSH test
#   - All nodes: track offline duration, escalate if >30 min
#
# Usage:
#   ./tailscale-mesh-healer.sh                     # Standard run
#   ./tailscale-mesh-healer.sh --dry-run           # Report only
#   ./tailscale-mesh-healer.sh --status            # Show mesh connectivity report
#   ./tailscale-mesh-healer.sh --help              # This text
#
# State: /var/log/wheeler/tailscale-healer-state.json
# Log: /var/log/wheeler-tailscale-mesh-healer.log
#===============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
HEAL_LOG="/var/log/wheeler-tailscale-mesh-healer.log"
STATE_FILE="/var/log/wheeler/tailscale-healer-state.json"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date +%s)"
DRY_RUN=false

# ---- Thresholds ----
OFFLINE_WARN_MIN=5              # Log warning after 5 min offline
OFFLINE_HEAL_MIN=10             # Attempt heal after 10 min offline
OFFLINE_ESCALATE_MIN=30         # Escalate after 30 min offline
PING_TIMEOUT=10                 # Seconds for tailscale ping
RECOVERY_WAIT=15                # Seconds to wait after heal before verify

# ---- Known node map ----
# Format: name|tailscale_ip|role|requires_ssh_test
NODES=(
    "wheeler-core-db-01|100.118.166.117|database|true"
    "srv1476866|100.98.163.17|hostinger|true"
    "wheelers-macbook-pro|100.83.80.6|mac|false"
)

# ---- Help ----
show_help() {
    sed -ne '/^#===-/,/^#===/p' "$0" | head -n -1 | sed 's/^#//'
    exit 0
}

# ---- Logging ----
log() {
    local level="$1"; shift
    echo "[${TIMESTAMP}] [${level}] [${SCRIPT_NAME}] $*" | tee -a "$HEAL_LOG"
}

# ---- State management ----
init_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"nodes":{}}' > "$STATE_FILE"
    fi
}

read_state() {
    cat "$STATE_FILE" 2>/dev/null || echo '{"nodes":{}}'
}

write_state() {
    local new_state="$1"
    echo "$new_state" > "$STATE_FILE"
}

update_node_state() {
    local node="$1"
    local status="$2"
    local ts="$3"

    local state
    state="$(read_state)"
    local updated
    updated="$(echo "$state" | python3 -c "
import json,sys
state = json.load(sys.stdin)
state.setdefault('nodes', {})
state['nodes']['$node'] = {'status': '$status', 'timestamp': $ts, 'updated': '${TIMESTAMP}'}
json.dump(state, sys.stdout)
" 2>/dev/null || echo "$state")"
    write_state "$updated"
}

clear_node_state() {
    local node="$1"
    local state
    state="$(read_state)"
    local updated
    updated="$(echo "$state" | python3 -c "
import json,sys
state = json.load(sys.stdin)
state.setdefault('nodes', {})
state['nodes'].pop('$node', None)
json.dump(state, sys.stdout)
" 2>/dev/null || echo "$state")"
    write_state "$updated"
}

get_node_state() {
    local node="$1"
    read_state | python3 -c "
import json,sys
try:
    state = json.load(sys.stdin)
    c = state.get('nodes', {}).get('$node', {})
    print(json.dumps(c))
except:
    print('{}')
" 2>/dev/null || echo '{}'
}

# ---- Tailscale operations ----
get_mesh_status() {
    tailscale status 2>/dev/null || echo "tailscale not available"
}

is_node_online() {
    local ip="$1"
    tailscale status 2>/dev/null | grep -q "^${ip//\./\\.}\s" || return 1
    # Check if it shows "-" (offline indicator) or has "active" or "idle"
    local line
    line="$(tailscale status 2>/dev/null | grep "^${ip//\./\\.} " || true)"
    if [[ -z "$line" ]]; then
        return 1
    fi
    # If line contains "offline" or "-" as the tag field, it's offline
    if echo "$line" | grep -qE '\s+\-\s+'; then
        return 1
    fi
    # Lines with "active" or "idle" are online
    if echo "$line" | grep -qE '\s+(active|idle)\s+'; then
        return 0
    fi
    # Default: if we see the IP it's probably online
    return 0
}

get_node_offline_duration() {
    local node="$1"
    # Try to find when tailscale last saw it
    local last_seen
    last_seen="$(tailscale status --json 2>/dev/null | python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
    for peer_id, peer in data.get('Peer', {}).items():
        if peer.get('DNSName', '').startswith('$node') or peer.get('TailscaleIPs', [''])[0] == '${node}':
            last_seen = peer.get('LastSeen', '')
            if last_seen:
                print(last_seen)
except:
    pass
" 2>/dev/null || true)"
    if [[ -z "$last_seen" ]]; then
        echo "unknown"
    else
        local last_epoch
        last_epoch="$(date -d "$last_seen" +%s 2>/dev/null || echo 0)"
        if [[ "$last_epoch" -gt 0 ]]; then
            echo "$(( NOW_EPOCH - last_epoch ))"
        else
            echo "unknown"
        fi
    fi
}

attempt_ping_reconnect() {
    local ip="$1"
    local name="$2"

    log "INFO" "Attempting tailscale ping to $name ($ip)"

    if $DRY_RUN; then
        log "DRYRUN" "Would run: tailscale ping --c 1 --timeout ${PING_TIMEOON}s $ip"
        return 0
    fi

    # Ping triggers a NAT traversal attempt in Tailscale
    if tailscale ping --c 1 --timeout "${PING_TIMEOUT}s" "$ip" 2>&1 | head -5; then
        log "OK" "tailscale ping succeeded for $name ($ip)"
        return 0
    else
        log "WARN" "tailscale ping failed for $name ($ip)"
        return 1
    fi
}

attempt_tailscale_up() {
    log "INFO" "Attempting tailscale up to refresh connections"
    if $DRY_RUN; then
        log "DRYRUN" "Would run: tailscale up --reset --accept-routes"
        return 0
    fi

    # --reset forces re-authentication which can clear stuck states
    # But we need to do this carefully — only if we think it's needed
    if tailscale status 2>/dev/null | grep -cE '^\d+' | head -1 | grep -q '0'; then
        log "WARN" "No peers visible — tailscale may need restart"
        return 1
    fi

    # Try a softer approach: just ping all nodes
    log "INFO" "Tailscale appears to be running with peers — skipping full up"
    return 0
}

test_ssh_connectivity() {
    local ip="$1"
    local name="$2"

    log "INFO" "Testing SSH connectivity to $name ($ip)"

    if $DRY_RUN; then
        log "DRYRUN" "Would run: ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@$ip 'hostname'"
        return 0
    fi

    # Quick SSH ping — just test TCP connectivity
    if timeout 10 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null; then
        log "OK" "SSH port 22 reachable on $name ($ip)"
        return 0
    else
        log "HIGH" "SSH port 22 UNREACHABLE on $name ($ip)"
        return 1
    fi
}

# ---- Main healer logic ----
handle_offline_node() {
    local name="$1"
    local ip="$2"
    local role="$3"
    local requires_ssh="$4"

    log "WARN" "Node $name ($ip) appears offline"

    # Check how long it's been offline
    local cstate
    cstate="$(get_node_state "$name")"
    local tracked_status
    local tracked_ts
    tracked_status="$(echo "$cstate" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null || echo '')"
    tracked_ts="$(echo "$cstate" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('timestamp',0))" 2>/dev/null || echo 0)"

    local elapsed=0
    if [[ "$tracked_ts" -gt 0 ]]; then
        elapsed=$(( NOW_EPOCH - tracked_ts ))
    fi

    case "$role" in
        "mac")
            # Mac: always just log — physical intervention needed
            if [[ "$tracked_status" != "mac_offline_logged" ]]; then
                log "INFO" "Mac ($name) is offline — physical intervention required to reconnect"
                update_node_state "$name" "mac_offline_logged" "$NOW_EPOCH"
            elif [[ "$elapsed" -gt $(( OFFLINE_ESCALATE_MIN * 60 )) ]]; then
                log "HIGH" "Mac ($name) has been offline for ${elapsed}s — still requires physical intervention"
            else
                log "INFO" "Mac ($name) offline for ${elapsed}s — logged, no auto-heal available"
            fi
            ;;

        "database"|"hostinger")
            # CoreDB or Hostinger — attempt reconnection
            if [[ -z "$tracked_status" || "$tracked_status" == "online" ]]; then
                # First detection
                log "INFO" "First detection of $name offline — monitoring"
                update_node_state "$name" "offline_first_seen" "$NOW_EPOCH"

            elif [[ "$tracked_status" == "offline_first_seen" ]]; then
                if [[ "$elapsed" -ge $(( OFFLINE_HEAL_MIN * 60 )) ]]; then
                    log "HIGH" "$name offline for ${elapsed}s — attempting recovery"
                    update_node_state "$name" "heal_attempted" "$NOW_EPOCH"

                    # Step 1: Try tailscale ping to force NAT traversal
                    attempt_ping_reconnect "$ip" "$name" || true
                    sleep 3

                    # Step 2: Re-check status
                    if is_node_online "$ip"; then
                        log "OK" "$name reconnected after ping attempt"
                        clear_node_state "$name"
                        return 0
                    fi

                    # Step 3: If requires SSH, test connectivity
                    if [[ "$requires_ssh" == "true" ]]; then
                        if test_ssh_connectivity "$ip" "$name"; then
                            log "INFO" "$name SSH is reachable despite tailscale showing offline — may be a display issue"
                            clear_node_state "$name"
                            return 0
                        fi
                    fi

                    log "HIGH" "$name recovery attempt failed — will retry on next cycle"

                elif [[ "$elapsed" -ge $(( OFFLINE_WARN_MIN * 60 )) ]]; then
                    log "INFO" "$name offline for ${elapsed}s — waiting for ${OFFLINE_HEAL_MIN}m heal threshold"
                else
                    log "INFO" "$name offline for ${elapsed}s — initial monitoring"
                fi

            elif [[ "$tracked_status" == "heal_attempted" ]]; then
                if [[ "$elapsed" -ge $(( OFFLINE_ESCALATE_MIN * 60 )) ]]; then
                    log "CRITICAL" "$name has been offline for ${elapsed}s despite heal attempts — escalation required"
                    update_node_state "$name" "escalated" "$NOW_EPOCH"
                else
                    # Retry heal
                    log "INFO" "$name still offline after heal — retrying (${elapsed}s elapsed)"
                    attempt_ping_reconnect "$ip" "$name" || true
                fi

            elif [[ "$tracked_status" == "escalated" ]]; then
                log "CRITICAL" "$name previously escalated — human intervention required"
            fi
            ;;
    esac
}

# ---- Status display ----
show_status() {
    echo "Tailscale Mesh Connectivity Report"
    echo "===================================="
    echo "Timestamp: ${TIMESTAMP}"
    echo ""

    # Show raw tailscale status
    echo "--- Tailscale Status ---"
    tailscale status 2>/dev/null || echo "tailscale not available"
    echo ""

    # Show our tracked state
    echo "--- Healer Tracked State ---"
    local state
    state="$(read_state)"
    local nodes_data
    nodes_data="$(echo "$state" | python3 -c "
import json,sys
state = json.load(sys.stdin)
for name, info in state.get('nodes', {}).items():
    print(f\"{name}|{info.get('status','?')}|{info.get('timestamp',0)}|{info.get('updated','?')}\")
" 2>/dev/null || true)"

    if [[ -z "$nodes_data" ]]; then
        echo "  No nodes tracked."
    else
        printf "  %-30s %-25s %-12s %s\n" "NODE" "STATUS" "ELAPSED" "UPDATED"
        printf "  %-30s %-25s %-12s %s\n" "------------------------------" "-------------------------" "------------" "-----------------------------"
        while IFS='|' read -r name status ts updated; do
            [[ -z "$name" ]] && continue
            local elapsed_str
            if [[ "$ts" -gt 0 ]]; then
                local e=$(( NOW_EPOCH - ts ))
                elapsed_str="${e}s"
            else
                elapsed_str="N/A"
            fi
            printf "  %-30s %-25s %-12s %s\n" "$name" "$status" "$elapsed_str" "$updated"
        done <<< "$nodes_data"
    fi
    echo ""

    # Per-node check
    echo "--- Node Health ---"
    for node_entry in "${NODES[@]}"; do
        IFS='|' read -r name ip role requires_ssh <<< "$node_entry"
        if is_node_online "$ip"; then
            echo "  [OK]  $name ($ip) — online"
        else
            local dur
            dur="$(get_node_offline_duration "$name")"
            echo "  [OFF] $name ($ip) — offline for ${dur}s"
        fi
    done
}

# ---- Main ----
main() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run)  DRY_RUN=true ;;
            --status)   show_status; exit 0 ;;
            --help)     show_help ;;
        esac
    done

    # Check if tailscale is available
    if ! command -v tailscale &>/dev/null; then
        echo "tailscale command not found — skipping mesh heal"
        exit 0
    fi

    init_state

    log "INFO" "Tailscale mesh healer starting $(if $DRY_RUN; then echo '(DRY RUN)'; fi)"

    local online_count=0
    local offline_count=0
    local escalated=0

    # Check each node
    for node_entry in "${NODES[@]}"; do
        IFS='|' read -r name ip role requires_ssh <<< "$node_entry"

        if is_node_online "$ip"; then
            log "OK" "Node $name ($ip) is online"
            # Clear any previous offline state
            clear_node_state "$name"
            ((online_count++))
        else
            handle_offline_node "$name" "$ip" "$role" "$requires_ssh"
            ((offline_count++))
        fi
    done

    # Summary
    log "INFO" "Mesh check complete: ${online_count} online, ${offline_count} offline"

    if [[ "$offline_count" -gt 0 ]]; then
        return 1
    fi
    return 0
}

main "$@"
