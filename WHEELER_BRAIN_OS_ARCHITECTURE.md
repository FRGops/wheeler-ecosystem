# Wheeler Brain OS — System Architecture

**Version:** 2.0.0 | **Date:** 2026-05-24 | **Status:** DEPLOYED

## Architecture Overview

```
LAYER 8: CEO COMMAND CONSOLE ── One-glance ecosystem intelligence
LAYER 7: GOVERNANCE ENGINE ── Reject unsafe, enforce policy
LAYER 6: SELF-HEALING ── Auto-remediate, drift correction
LAYER 5: OBSERVABILITY ── Prometheus + Loki + Grafana + Uptime Kuma
LAYER 4: CONTROL PLANE ── Docker + PM2 + Deploy + Rollback orchestration
LAYER 3: AI DECISION LAYER ── 52 Claude agents, predictions, recommendations
LAYER 2: ECOSYSTEM GRAPH ── Neo4j with 105 nodes, 261 relationships
LAYER 1: INFRASTRUCTURE ── 3 servers, 42 containers, 20 PM2 processes
LAYER 0: NETWORK ── Tailscale mesh, nginx gateway, UFW firewall
```

## Layer Details

### Layer 0: Network
- Tailscale mesh: 4 nodes (aiops, coredb, hostinger, mac)
- Nginx reverse proxy: 100.121.230.28:443 with SSL + basic auth
- UFW: 26 rules, all Docker binds to 127.0.0.1

### Layer 1: Infrastructure
- wheeler-aiops-01: Hetzner CPX51, 30GB RAM, 338GB SSD, 42 Docker containers
- wheeler-coredb-01: Core DB, 16GB RAM, 160GB SSD
- hostinger-vps: Legacy, 8GB RAM, 100GB SSD

### Layer 2: Ecosystem Graph
- Neo4j 5 Enterprise at localhost:7474
- 105 nodes: 52 Agents, 20 Skills, 12 Containers, 9 AgentServices, 9 InfraServices, 3 Servers
- 261 relationships: RUNS_ON, DEPENDS_ON, ROUTES_THROUGH, HOSTED_ON, USES, OBSERVES, MONITORS

### Layer 3: AI Decision Layer
- 52 Claude Code agents in 6 tiers
- All agents route through LiteLLM proxy (:4049)
- Models: deepseek-chat (primary), claude-sonnet-4 (review), claude-opus-4 (complex)

### Layer 4: Control Plane
- PM2: 20 processes managed
- Docker: 42 containers with health checks
- Nginx: Dynamic route management
- Rollback: Backup + restore capability for all services

### Layer 5: Observability
- Prometheus: Metrics at :9090
- Loki: Logs at :3100
- Grafana: Dashboards at :3002
- Uptime Kuma: Uptime at :3001
- Netdata: System at :19999

### Layer 6: Self-Healing
- /slay skill: Full ecosystem audit + auto-remediation
- pm2-recovery: Process crash recovery
- Auto-restart: PM2 autorestart with max 10 retries
- Health checks: Docker HEALTHCHECK on all containers

### Layer 7: Governance
- Agent safety models: READ-ONLY, ADVISORY, PREFLIGHT-GATED, GOVERNANCE, GATEKEEPER
- No agent has unrestricted autonomous execution
- Deploy safety: 7 pre-flight gates
- Security: secrets-scan, firewall audit, SSH hardening

### Layer 8: CEO Console
- Command Center at command.aiops:8100
- Real-time ecosystem health score
- Executive dashboard with KPIs
