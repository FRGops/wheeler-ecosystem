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
