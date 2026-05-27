#!/bin/bash
# =============================================================================
# Wheeler Cross-Server Repowire Wiring
# Deploys repowire agent mesh to all Wheeler servers via Tailscale.
# Future-server auto-bootstrap included.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOWIRE_VERSION="${REPOWIRE_VERSION:-0.14.4}"
REPOWIRE_PORT="${REPOWIRE_PORT:-8377}"
HUB_SERVER="${HUB_SERVER:-aiops}"  # AIOPS is the mesh hub

# ── Server map ─────────────────────────────────────────────────────
declare -A SERVER_IPS
SERVER_IPS["hostinger"]="100.98.163.17"
SERVER_IPS["coredb"]="100.118.166.117"
SERVER_IPS["aiops"]="100.121.230.28"

declare -A SERVER_ROLES
SERVER_ROLES["hostinger"]="production-api"
SERVER_ROLES["coredb"]="database-pipelines"
SERVER_ROLES["aiops"]="brain-orchestrator"

declare -A SERVER_CIRCLES
SERVER_CIRCLES["hostinger"]="wheeler-ops wheeler-finance wheeler-growth"
SERVER_CIRCLES["coredb"]="wheeler-ops wheeler-finance"
SERVER_CIRCLES["aiops"]="wheeler-core wheeler-ops wheeler-finance wheeler-growth wheeler-legal"

# ── Server-specific peers ──────────────────────────────────────────
declare -A SERVER_PEERS_HOSTINGER
SERVER_PEERS_HOSTINGER["wheeler-crm"]="CRM API — outreach, enrichment, lead management"
SERVER_PEERS_HOSTINGER["wheeler-skiptrace"]="Skip Tracing API — batch + single lookups"
SERVER_PEERS_HOSTINGER["wheeler-marketplace"]="Attorney Marketplace — two-sided platform"
SERVER_PEERS_HOSTINGER["wheeler-firecrawl"]="Firecrawl — web scraping and crawling"
SERVER_PEERS_HOSTINGER["wheeler-gotenberg"]="Gotenberg — document generation and conversion"

declare -A SERVER_PEERS_COREDB
SERVER_PEERS_COREDB["wheeler-postgres"]="PostgreSQL — primary Wheeler database"
SERVER_PEERS_COREDB["wheeler-redis"]="Redis — caching, queues, pub/sub"
SERVER_PEERS_COREDB["wheeler-qdrant"]="Qdrant — vector embeddings and similarity search"
SERVER_PEERS_COREDB["wheeler-minio"]="MinIO — object storage for documents and assets"
SERVER_PEERS_COREDB["wheeler-infisical"]="Infisical — secrets management for 50+ agents"
SERVER_PEERS_COREDB["wheeler-temporal"]="Temporal — workflow orchestration pipelines"
SERVER_PEERS_COREDB["wheeler-prediction"]="Prediction Radar — foreclosure prediction engine"

# HUB_SERVER peers (this server — AIOPS) are the 10 domain peers already configured

# ── Color output ────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
_pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
_info()  { echo -e "[INFO] $*"; }

# ── Tailscale check ─────────────────────────────────────────────────
check_tailscale() {
    local server=$1
    local ip="${SERVER_IPS[$server]}"
    _info "Checking Tailscale connectivity to $server ($ip)..."
    if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
        _pass "$server reachable at $ip"
        return 0
    else
        _fail "$server UNREACHABLE at $ip"
        return 1
    fi
}

# ── Deploy repowire to a remote server ──────────────────────────────
deploy_to_server() {
    local server=$1
    local ip="${SERVER_IPS[$server]}"
    local role="${SERVER_ROLES[$server]}"
    local circles="${SERVER_CIRCLES[$server]}"

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  DEPLOYING REPOWIRE → $server ($ip) [$role]"
    echo "════════════════════════════════════════════════════════════"

    # Build the remote install script
    local remote_script='
set -e
REPOWIRE_PORT="'"$REPOWIRE_PORT"'"
TAILSCALE_IP="'"$ip"'"

echo "[$HOSTNAME] Installing repowire..."

# Create venv if missing
if [ ! -d /opt/repowire-venv ]; then
    python3 -m venv /opt/repowire-venv
fi

# Install/upgrade repowire + websockets
/opt/repowire-venv/bin/pip install --quiet --upgrade "repowire>=0.14" websockets httpx

# Ensure CLI symlink
if [ ! -f /usr/local/bin/repowire ]; then
    ln -sf /opt/repowire-venv/bin/repowire /usr/local/bin/repowire
fi

echo "[$HOSTNAME] repowire installed: $(/opt/repowire-venv/bin/repowire --version 2>&1 || echo "v?")"
'

    _info "Installing repowire on $server..."
    ssh -o ConnectTimeout=10 -o BatchMode=yes "root@$ip" "bash -s" <<< "$remote_script" 2>&1 || {
        _fail "Install failed on $server"
        return 1
    }
    _pass "repowire installed on $server"

    # Generate server-specific config
    _info "Generating config for $server..."
    local config_dir="/tmp/repowire-config-$server"
    mkdir -p "$config_dir"

    # Build peer entries
    local peer_entries=""
    local peer_varname="SERVER_PEERS_${server^^}"
    eval "local peer_keys=(\${!${peer_varname}[@]})"
    for peer_key in "${peer_keys[@]}"; do
        eval "local peer_desc=\${${peer_varname}[\$peer_key]}"
        local peer_circle="wheeler-ops"
        case "$peer_key" in
            wheeler-crm|wheeler-skiptrace|wheeler-marketplace) peer_circle="wheeler-growth" ;;
            wheeler-firecrawl|wheeler-gotenberg) peer_circle="wheeler-ops" ;;
            wheeler-postgres|wheeler-redis|wheeler-qdrant|wheeler-minio) peer_circle="wheeler-ops" ;;
            wheeler-infisical) peer_circle="wheeler-ops" ;;
            wheeler-temporal|wheeler-prediction) peer_circle="wheeler-finance" ;;
        esac

        peer_entries+="  ${peer_key}:
    name: \"${peer_key}\"
    display_name: \"${peer_key}\"
    path: \"/opt/wheeler\"
    circle: \"${peer_circle}\"
    metadata:
      role: \"${peer_desc}\"
      domain: \"${peer_circle}\"
      server: \"${server}\"
"
    done

    cat > "$config_dir/config.yaml" << PEEREOF
# Wheeler Ecosystem — Repowire Configuration
# Server: $server ($ip) | Role: $role
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

daemon:
  host: "0.0.0.0"
  port: ${REPOWIRE_PORT}
  prune_max_age_hours: 48
  mcp_http:
    enabled: true
    require_auth: false
    allow_dangerous_tools: true
  spawn:
    commands:
      claude-code: "claude --dangerously-skip-permissions"
    allowed_paths:
      - /root
      - /opt/wheeler
      - /tmp

peers:
${peer_entries}

# Relay disabled — using Tailscale mesh for cross-server
relay:
  enabled: false

logging:
  level: "info"
  file: "/var/log/repowire/repowire.log"
PEEREOF

    _info "Config generated: $peer_keys peers for $server"

    # Copy config to server
    ssh -o ConnectTimeout=10 "root@$ip" "mkdir -p ~/.repowire /var/log/repowire" 2>&1
    scp -o ConnectTimeout=10 "$config_dir/config.yaml" "root@$ip:~/.repowire/config.yaml" 2>&1
    _pass "Config deployed to $server"

    # Create PM2 daemon
    local pm2_cmd="
pm2 delete repowire-daemon 2>/dev/null || true
pm2 start /opt/repowire-venv/bin/repowire --interpreter /opt/repowire-venv/bin/python3 --name repowire-daemon -- serve --host 0.0.0.0 --port ${REPOWIRE_PORT} --no-install-hooks
pm2 save
"
    ssh -o ConnectTimeout=10 "root@$ip" "bash -s" <<< "$pm2_cmd" 2>&1
    _pass "Daemon started on $server"

    rm -rf "$config_dir"
    return 0
}

# ── Register remote server peers on AIOPS hub ──────────────────────
register_on_hub() {
    local server=$1
    local ip="${SERVER_IPS[$server]}"

    _info "Registering $server peers on AIOPS hub..."

    # Verify remote daemon is running
    if ! ssh -o ConnectTimeout=5 "root@$ip" "curl -s http://127.0.0.1:${REPOWIRE_PORT}/health" 2>/dev/null | grep -q '"ok"'; then
        _warn "Remote daemon on $server not reachable yet, skipping registration"
        return 1
    fi

    # Get remote peers
    local remote_peers
    remote_peers=$(ssh -o ConnectTimeout=5 "root@$ip" "curl -s http://127.0.0.1:${REPOWIRE_PORT}/peers" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for p in d.get('peers',[]):
    print(f\"{p['display_name']}|{p.get('circle','?')}|{p.get('status','?')}|{p.get('peer_id','?')}|${ip}\")" 2>/dev/null)

    if [ -z "$remote_peers" ]; then
        _warn "No remote peers found on $server"
        return 1
    fi

    # Broadcast remote peers on AIOPS hub
    while IFS='|' read -r name circle status peer_id rip; do
        [ -z "$name" ] && continue
        _info "  Registering $name ($circle) from $server..."
        curl -s -X POST "http://127.0.0.1:${REPOWIRE_PORT}/broadcast" \
            -H "Content-Type: application/json" \
            -d "{\"from_peer\":\"Wheeler-Orchestrator\",\"text\":\"[CROSS-SERVER] Peer registered: $name ($circle) from $server ($rip) — status: $status\"}" >/dev/null 2>&1 || true
    done <<< "$remote_peers"

    _pass "Registered $server peers on AIOPS hub"
}

# ── Cross-server connectivity test ──────────────────────────────────
cross_server_test() {
    local server=$1
    local ip="${SERVER_IPS[$server]}"

    _info "Testing cross-server mesh with $server..."

    # Test via Tailscale IP
    local health
    health=$(curl -s -o /dev/null -w "%{http_code}" "http://${ip}:${REPOWIRE_PORT}/health" 2>&1 || echo "000")
    if [ "$health" = "200" ]; then
        _pass "$server daemon reachable via Tailscale (HTTP $health)"
    else
        _fail "$server daemon NOT reachable via Tailscale (HTTP $health)"
        return 1
    fi

    # Test broadcast
    local result
    result=$(curl -s -X POST "http://${ip}:${REPOWIRE_PORT}/broadcast" \
        -H "Content-Type: application/json" \
        -d '{"from_peer":"Wheeler-Orchestrator","text":"[CROSS-SERVER-MESH] Connectivity test from AIOPS hub"}' 2>&1)
    if echo "$result" | grep -q '"ok":true'; then
        _pass "Cross-server broadcast to $server works"
    else
        _warn "Cross-server broadcast: $result"
    fi
}

# ── Future-server bootstrap ─────────────────────────────────────────
generate_bootstrap() {
    local output="${1:-/root/deployment-engine/repowire/future-server-bootstrap.sh}"

    cat > "$output" << 'BOOTSTRAP_EOF'
#!/bin/bash
# =============================================================================
# Wheeler Future-Server Repowire Bootstrap
# Auto-wires any new server into the Wheeler repowire mesh.
#
# Usage:
#   On new server:
#     curl -s http://100.121.230.28:8190/discovery/bootstrap/repowire | bash
#   Or copy this script and run:
#     bash future-server-bootstrap.sh [server-name] [role]
#
# Auto-detects: Tailscale IP, hostname, available services
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "╔════════════════════════════════════════════════════════╗"
echo "║  WHEELER REPOWIRE — FUTURE SERVER BOOTSTRAP           ║"
echo "╚════════════════════════════════════════════════════════╝"

# ── Auto-detect server identity ─────────────────────────────────
SERVER_NAME="${1:-$(hostname)}"
SERVER_ROLE="${2:-auto}"
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || hostname -I | awk '{print $1}')
HUB_IP="100.121.230.28"  # AIOPS hub
REPOWIRE_PORT="${REPOWIRE_PORT:-8377}"

echo ""
echo "  Server:    $SERVER_NAME"
echo "  Role:      $SERVER_ROLE"
echo "  IP:        $TAILSCALE_IP"
echo "  Hub:       $HUB_IP"
echo ""

# Auto-detect role from hostname
if [ "$SERVER_ROLE" = "auto" ]; then
    case "$SERVER_NAME" in
        *hostinger*|*production*|*api*)  SERVER_ROLE="production-api" ;;
        *coredb*|*db*|*database*)        SERVER_ROLE="database-pipelines" ;;
        *aiops*|*brain*|*orchestrator*)  SERVER_ROLE="brain-orchestrator" ;;
        *edge*|*gateway*)                SERVER_ROLE="edge-gateway" ;;
        *monitor*|*watch*)               SERVER_ROLE="monitoring" ;;
        *worker*|*compute*)              SERVER_ROLE="compute-worker" ;;
        *)                               SERVER_ROLE="general-purpose" ;;
    esac
    echo "  Auto-detected role: $SERVER_ROLE"
fi

# Determine circles based on role
case "$SERVER_ROLE" in
    production-api)     CIRCLES="wheeler-ops wheeler-finance wheeler-growth" ;;
    database-pipelines) CIRCLES="wheeler-ops wheeler-finance" ;;
    brain-orchestrator) CIRCLES="wheeler-core wheeler-ops wheeler-finance wheeler-growth wheeler-legal" ;;
    edge-gateway)       CIRCLES="wheeler-ops" ;;
    monitoring)         CIRCLES="wheeler-ops wheeler-monitoring" ;;
    compute-worker)     CIRCLES="wheeler-ops" ;;
    *)                  CIRCLES="wheeler-ops" ;;
esac

echo "  Circles:    $CIRCLES"
echo ""

# ── Install repowire ───────────────────────────────────────────
echo "[1/5] Installing repowire..."
if [ ! -d /opt/repowire-venv ]; then
    python3 -m venv /opt/repowire-venv
fi
/opt/repowire-venv/bin/pip install --quiet --upgrade "repowire>=0.14" websockets httpx
ln -sf /opt/repowire-venv/bin/repowire /usr/local/bin/repowire 2>/dev/null || true
echo "  [OK] repowire $(/opt/repowire-venv/bin/repowire --version 2>&1 || echo 'installed')"

# ── Generate config ────────────────────────────────────────────
echo "[2/5] Generating config for $SERVER_NAME..."

# Auto-discover PM2 services as peers
PEER_YAML=""
if command -v pm2 &>/dev/null; then
    pm2 jlist 2>/dev/null | python3 -c "
import json, sys
try:
    processes = json.load(sys.stdin)
    for p in processes[:20]:  # Top 20 services
        name = p.get('name', 'unknown')
        # Map to circle
        circle = 'wheeler-ops'
        if any(k in name.lower() for k in ['crm', 'outreach', 'skip', 'enrich']):
            circle = 'wheeler-growth'
        elif any(k in name.lower() for k in ['stripe', 'revenue', 'finance', 'payment']):
            circle = 'wheeler-finance'
        elif any(k in name.lower() for k in ['compliance', 'legal', 'tcp']):
            circle = 'wheeler-legal'
        elif any(k in name.lower() for k in ['monitor', 'health', 'watchdog']):
            circle = 'wheeler-ops'
        elif any(k in name.lower() for k in ['orchestrat', 'brain', 'command']):
            circle = 'wheeler-core'
        print(f'  {name}:')
        print(f'    name: \"{name}\"')
        print(f'    display_name: \"{name}\"')
        print(f'    path: \"/opt/wheeler\"')
        print(f'    circle: \"{circle}\"')
        print(f'    metadata:')
        print(f'      role: \"Auto-discovered PM2 service\"')
        print(f'      domain: \"{circle}\"')
        print(f'      server: \"$SERVER_NAME\"')
except: pass
" 2>/dev/null
fi

mkdir -p ~/.repowire /var/log/repowire

cat > ~/.repowire/config.yaml << YAMLEOF
# Wheeler Ecosystem — Repowire Configuration
# Server: $SERVER_NAME ($TAILSCALE_IP) | Role: $SERVER_ROLE
# Auto-generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

daemon:
  host: "${TAILSCALE_IP}"
  port: ${REPOWIRE_PORT}
  prune_max_age_hours: 48
  mcp_http:
    enabled: true
    require_auth: false
    allow_dangerous_tools: true
  spawn:
    commands:
      claude-code: "claude --dangerously-skip-permissions"
    allowed_paths:
      - /root
      - /opt/wheeler
      - /tmp

peers:
${PEER_YAML}

relay:
  enabled: false

logging:
  level: "info"
  file: "/var/log/repowire/repowire.log"
YAMLEOF

echo "  [OK] Config written to ~/.repowire/config.yaml"

# ── Start daemon ────────────────────────────────────────────────
echo "[3/5] Starting repowire daemon..."
pm2 delete repowire-daemon 2>/dev/null || true
pm2 start /opt/repowire-venv/bin/repowire --interpreter /opt/repowire-venv/bin/python3 --name repowire-daemon -- serve --host 0.0.0.0 --port ${REPOWIRE_PORT} --no-install-hooks
sleep 2

if curl -s "http://127.0.0.1:${REPOWIRE_PORT}/health" | grep -q '"ok"'; then
    echo "  [OK] Daemon healthy on :${REPOWIRE_PORT}"
else
    echo "  [FAIL] Daemon not responding — check logs"
    pm2 logs repowire-daemon --lines 10 --nostream 2>&1
    exit 1
fi

# ── Register with hub ───────────────────────────────────────────
echo "[4/5] Registering with Wheeler hub ($HUB_IP)..."
curl -s -X POST "http://${HUB_IP}:${REPOWIRE_PORT}/broadcast" \
    -H "Content-Type: application/json" \
    -d "{\"from_peer\":\"${SERVER_NAME}-bootstrap\",\"text\":\"[NEW-SERVER] $SERVER_NAME ($SERVER_ROLE) joined the Wheeler mesh at $TAILSCALE_IP — circles: $CIRCLES\"}" 2>/dev/null || echo "  [WARN] Hub unreachable — will register when hub is available"

# ── Save state ──────────────────────────────────────────────────
echo "[5/5] Saving PM2 state..."
pm2 save

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  BOOTSTRAP COMPLETE                                   ║"
echo "║  Server:  $SERVER_NAME ($TAILSCALE_IP)                     ║"
echo "║  Role:    $SERVER_ROLE"
echo "║  Circles: $CIRCLES"
echo "║  Daemon:  http://${TAILSCALE_IP}:${REPOWIRE_PORT}                  ║"
echo "║  Hub:     $HUB_IP                                   ║"
echo "╚════════════════════════════════════════════════════════╝"
BOOTSTRAP_EOF

    chmod +x "$output"
    _pass "Future-server bootstrap generated: $output"
    echo "$output"
}

# ── Health report ────────────────────────────────────────────────────
health_report() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  CROSS-SERVER MESH HEALTH REPORT                                ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    for server in aiops hostinger coredb; do
        local ip="${SERVER_IPS[$server]}"
        echo "── $server ($ip) [${SERVER_ROLES[$server]}] ──"

        local health
        if [ "$server" = "aiops" ]; then
            health=$(curl -s "http://127.0.0.1:${REPOWIRE_PORT}/health" 2>/dev/null || echo '{"status":"down"}')
        else
            health=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$ip" "curl -s http://127.0.0.1:${REPOWIRE_PORT}/health" 2>/dev/null || echo '{"status":"unreachable"}')
        fi

        local status=$(echo "$health" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
        local version=$(echo "$health" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null || echo "?")

        if [ "$status" = "ok" ]; then
            echo "  [ONLINE] repowire v$version"
        else
            echo "  [$status] repowire v$version"
        fi
    done
    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    local command="${1:-deploy-all}"
    local target_server="${2:-}"

    case "$command" in
        deploy-all)
            echo "╔══════════════════════════════════════════════════════════════════╗"
            echo "║  WHEELER CROSS-SERVER REPOWIRE DEPLOYMENT                       ║"
            echo "║  Hub: AIOPS (100.121.230.28)                                    ║"
            echo "╚══════════════════════════════════════════════════════════════════╝"

            for server in hostinger coredb; do
                if check_tailscale "$server"; then
                    deploy_to_server "$server" && {
                        sleep 2
                        register_on_hub "$server"
                        cross_server_test "$server"
                    } || _warn "Some steps failed for $server — continuing with next server"
                fi
            done

            health_report
            ;;

        deploy)
            [ -z "$target_server" ] && { echo "Usage: $0 deploy <server>"; exit 1; }
            check_tailscale "$target_server" || exit 1
            deploy_to_server "$target_server"
            sleep 2
            register_on_hub "$target_server"
            cross_server_test "$target_server"
            ;;

        health)
            health_report
            ;;

        register)
            [ -z "$target_server" ] && { echo "Usage: $0 register <server>"; exit 1; }
            register_on_hub "$target_server"
            ;;

        test)
            [ -z "$target_server" ] && { echo "Usage: $0 test <server>"; exit 1; }
            cross_server_test "$target_server"
            ;;

        bootstrap)
            generate_bootstrap "${2:-/root/deployment-engine/repowire/future-server-bootstrap.sh}"
            ;;

        *)
            echo "Usage: $0 {deploy-all|deploy <server>|health|register <server>|test <server>|bootstrap [output-path]}"
            echo ""
            echo "Servers: hostinger (${SERVER_IPS[hostinger]}), coredb (${SERVER_IPS[coredb]}), aiops (local)"
            echo ""
            echo "  deploy-all    Deploy repowire to all remote servers"
            echo "  deploy <srv>  Deploy to a specific server"
            echo "  health        Show cross-server mesh health report"
            echo "  register <srv> Register remote server peers on AIOPS hub"
            echo "  test <srv>    Test cross-server connectivity"
            echo "  bootstrap     Generate future-server bootstrap script"
            exit 1
            ;;
    esac
}

main "$@"
