---
name: pm2-deploy-state-20260527
description: Canonical 85-process baseline — 85/85 online, 0 restarts, pm2 save persisted, daemon-env clean (2026-05-27)
metadata:
  type: project
  node_type: memory
  originSessionId: session-20260527-020001
---

# PM2 Deploy State — 2026-05-27

## Current State

- **85 processes** across AIOPS, COREDB, EDGE
- **85/85 online**, 0 stopped, 0 errored
- `pm2 save` persisted to `/root/.pm2/dump.pm2`
- Daemon env clean (systemd drop-in `UnsetEnvironment=` strips secrets)

## PM2 Safe Operations

- Restart: `pm2 restart <name>` (safe for most processes)
- Full recovery: `pm2 resurrect` (restores from dump.pm2)
- Env var change requires: `pm2 delete <name> && pm2 start ecosystem.config.js --env production`
- Never: `pm2 kill` (loses state), `pm2 restart all` (risky at scale)
- Pre-verify with `/slay` skill before any mass restart

## Supersedes

- [[pm2-deploy-state-20260526]] (40-process baseline — expanded to 85)
