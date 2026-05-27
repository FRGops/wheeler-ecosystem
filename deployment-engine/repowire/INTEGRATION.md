# Wheeler-Repowire Integration Reference

## Architecture
```
Wheeler 154 Agents → repowire-bridge (PM2 #128) → repowire-daemon (PM2 #127, :8377)
                                                  → Dashboard (:8377/dashboard)
                                                  → MCP HTTP (:8377/mcp)
                                                  → Schedules (4 autonomous jobs)
```

## PM2 Services
| ID  | Name            | Purpose |
|-----|-----------------|---------|
| 127 | repowire-daemon  | Mesh daemon — peer registry, message routing, schedules |
| 128 | repowire-bridge  | Wheeler bridge — health monitoring, orchestration, announcements |

## Domain Peers (10)
wheeler-orchestrator, wheeler-infra, wheeler-security, wheeler-deploy,
wheeler-financial, wheeler-db, wheeler-monitoring, wheeler-growth,
wheeler-compliance, wheeler-revenue

## Autonomous Schedules
| Name                     | Cron          | Target              |
|--------------------------|---------------|---------------------|
| wheeler-daily-health     | 57 8 * * *    | wheeler-monitoring  |
| wheeler-hourly-fleet     | 13 * * * *    | wheeler-infra       |
| wheeler-revenue-pulse    | 23 */6 * * *  | wheeler-revenue     |
| wheeler-security-sweep   | 37 6,18 * * * | wheeler-security    |

## Key Commands
- repowire peer list
- repowire peer new <path>
- repowire broadcast "message"
- curl http://127.0.0.1:8377/health
- curl http://127.0.0.1:8377/schedules
- pm2 logs repowire-daemon
- pm2 logs repowire-bridge

## Agent Communication Flow
1. Claude Code agent → repowire ask <target> <question>
2. Daemon routes ask to target peer via WebSocket
3. Target peer receives ask, processes, sends ack
4. Ack delivered back to asking peer

## Config: ~/.repowire/config.yaml | Logs: /var/log/repowire/
