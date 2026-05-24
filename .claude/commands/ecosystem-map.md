# /ecosystem-map — Wheeler Ecosystem Topology Map

Generate a complete topology map of the Wheeler ecosystem: all nodes, services, network links, and data flows.

## Execution (ALL in parallel)

```bash
# 1. Node inventory
echo "=== NODES ==="
tailscale status 2>/dev/null
cat /opt/wheeler-ecosystem/inventory/servers.json 2>/dev/null | python3 -m json.tool

# 2. Services per node (this node)
echo "=== THIS NODE SERVICES ==="
echo "Docker containers:"
docker ps --format '{{.Names}} {{.Image}} {{.Ports}}' 2>/dev/null
echo ""
echo "PM2 processes:"
pm2 list 2>/dev/null

# 3. Network topology
echo "=== NETWORK ==="
tailscale status 2>/dev/null
echo ""
echo "Docker networks:"
docker network ls 2>/dev/null
echo ""
echo "Private routes:"
ip route show 2>/dev/null | grep -E '10\.|172\.|100\.'

# 4. Data flows (from inventory)
cat /opt/wheeler-ecosystem/inventory/deployments.json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for key, val in data.items():
        if isinstance(val, dict):
            print(f'{key}:')
            for k, v in val.items():
                print(f'  {k}: {v}')
except: pass
" 2>/dev/null

# 5. Dependency graph
echo "=== DEPENDENCIES ==="
cat /opt/wheeler-ecosystem/inventory/services.json 2>/dev/null | python3 -m json.tool 2>/dev/null | head -50
```

## Output Format

```
╔══════════════════════════════════════════════╗
║   Wheeler Ecosystem Topology — <timestamp>   ║
╚══════════════════════════════════════════════╝

NODES (Tailscale Mesh):
  ┌─────────────────────────────────────────┐
  │ wheeler-aiops-01 (AI Ops)               │
  │   IP: 100.121.230.28 / 5.78.140.118     │
  │   Role: Control Plane                    │
  │   Services: <N> Docker, <N> PM2          │
  ├─────────────────────────────────────────┤
  │ srv1476866 (Hostinger)                   │
  │   IP: 100.98.163.17                      │
  │   Role: Production                        │
  │   Services: FRG Ecosystem, InsForge      │
  ├─────────────────────────────────────────┤
  │ wheeler-core-db-01 (Worker)              │
  │   IP: 100.118.166.117 / 10.0.0.2         │
  │   Role: Data/Compute                      │
  │   Services: PG, Redis, MinIO, Temporal   │
  ├─────────────────────────────────────────┤
  │ wheelers-macbook-pro (Mac)               │
  │   IP: 100.83.80.6                        │
  │   Role: Command Center                    │
  │   Status: <online/idle/offline>          │
  └─────────────────────────────────────────┘

DATA FLOWS:
  AI Ops ←→ Hostinger (Tailscale, app traffic)
  AI Ops ←→ Core-DB  (Tailscale + private 10.0.0.x)
  AI Ops ←→ Mac      (Tailscale, intermittent)
  Core-DB → AI Ops   (Prometheus metrics, Loki logs)

APPROVED PUBLIC PORTS (this node):
  <port> — <service> [APPROVED / NEEDS REVIEW]
```
