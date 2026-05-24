---
name: aiops-control-plane-operator
description: "AI Ops control plane operations: Docker management, PM2 management, monitoring stack, LiteLLM proxy, Claude Code configuration, ecosystem orchestration."
trigger: aiops operator, ai ops, control plane, aiops operations, aiops management, aiops setup
---

# Skill: AI Ops Control Plane Operator

Operations guide for wheeler-aiops-01 — the ecosystem control plane.

## Control Plane Responsibilities

- **Source of truth**: Capability layer, inventory, configs
- **Orchestration**: PM2 process management, Docker container orchestration
- **Monitoring**: Prometheus, Grafana, Loki, Uptime Kuma, Netdata
- **AI Gateway**: LiteLLM proxy for model routing
- **Security**: Firewall management, secrets vault, SSH hardening
- **Sync hub**: Push/pull capabilities to/from other nodes

## Key Services

### Docker (26 containers)
```bash
# Health overview
docker ps --format 'table {{.Names}}\t{{.Status}}'

# Critical containers
docker ps --filter "name=frgops-standby" --format '{{.Status}}'
docker ps --filter "name=aiops-grafana" --format '{{.Status}}'
docker ps --filter "name=aiops-prometheus" --format '{{.Status}}'

# Restart policy verification
docker inspect $(docker ps -q) --format '{{.Name}}: {{.HostConfig.RestartPolicy.Name}}'
```

### PM2 (17 processes)
```bash
# Health overview
pm2 list

# Critical processes
pm2 list | grep -E 'litellm|frgcrm-api|ecosystem-guardian'

# Log check
pm2 logs --nostream --lines 20 litellm
```

### LiteLLM Proxy
```bash
# Health
curl -s http://127.0.0.1:4000/health/readiness

# Model list
curl -s http://127.0.0.1:4000/v1/models | python3 -m json.tool

# Config
cat /root/.claude/litellm-deepseek.yaml
```

### Tailscale
```bash
tailscale status
# Must show: srv1476866, wheeler-core-db-01, wheelers-macbook-pro
```

## Common Operations

| Operation | Command |
|-----------|---------|
| Full health check | `/daily-health` |
| Docker audit | `/docker-health` |
| PM2 audit | `/pm2-health` |
| DB lockdown check | `/db-lockdown` |
| Network check | `/private-network` |
| Capability sync (push) | `wheeler-capabilities-sync --push all` |
| Capability sync (pull from Hostinger) | `wheeler-capabilities-sync --pull hostinger` |
| Backup ecosystem | `bash /opt/wheeler-ecosystem/scripts/backup-ecosystem.sh` |
| Restore ecosystem | `bash /opt/wheeler-ecosystem/scripts/restore-ecosystem.sh` |

## Incident Response

If AI Ops goes down:
1. Services continue running on other nodes (independent operation)
2. Monitoring gap — check Hostinger and Core-DB directly
3. Restore: PM2 resurrect → Docker restart → Tailscale reconnect
4. Sync capabilities from backup: `wheeler-capabilities-restore`

## AI Ops Full Profile
- All 19 slash commands
- All 18 skills
- All agents
- Admin MCP profile
- Full sync tooling
- Backup/restore automation
