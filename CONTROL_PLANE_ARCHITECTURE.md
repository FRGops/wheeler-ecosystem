# Wheeler Brain OS — Control Plane Architecture

**Version:** 2.0.0 | **Date:** 2026-05-24

## Overview

The Control Plane provides centralized orchestration for all Wheeler ecosystem operations.

### Orchestration Domains

| Domain | Tool | Interface |
|---|---|---|
| Docker | docker CLI, Docker socket | PM2, direct |
| PM2 | pm2 CLI | PM2 daemon |
| Deployments | deploy-safety skill | Claude Code |
| Rollbacks | rollback-first skill | Claude Code |
| Nginx | nginx config, systemctl | Filesystem |
| UFW | ufw CLI | Direct |
| Neo4j | Cypher via HTTP | Port 7474 |
| LiteLLM | REST API | Port 4049 |

### Control Flow

```
Operator Command
    │
    ▼
wheeler-brain-core (intent parsing)
    │
    ├── Read operations → direct agent execution
    │
    └── Write operations → pre-flight gates
            │
            ├── Gate 1: What's the blast radius?
            ├── Gate 2: Is rollback possible?
            ├── Gate 3: Are backups current?
            ├── Gate 4: Are affected services healthy?
            ├── Gate 5: Is this within safety model?
            ├── Gate 6: Is deploy window open?
            └── Gate 7: Has change been approved?
                    │
                    ▼
              Execute via domain agent
                    │
                    ▼
              Verify (no-false-greens-qa)
```

### PM2 Control

- 20 processes managed via `pm2` CLI
- Safe restart pattern: `verify → delete → start → verify`
- All processes use `env -i` for clean environment
- Autorestart: max 10 retries, 5s delay
- Memory limits: 500MB per agent service

### Docker Control

- 42 containers with HEALTHCHECK instructions
- All binds: 127.0.0.1 only (no 0.0.0.0 exposure)
- :latest images flagged by docker-health skill
- Backup containers for: Netdata, Uptime Kuma, Postgres

### Gateway Control

- Nginx at 100.121.230.28:443
- 4 active server blocks (command, clickhouse, usesend, default)
- All routes: SSL + basic_auth or public (default health only)
- Rate limiting: 10 req/s with burst
