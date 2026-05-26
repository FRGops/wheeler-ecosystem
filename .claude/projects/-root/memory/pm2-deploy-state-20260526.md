---
name: pm2-deploy-state-20260526
description: "Canonical 28-process PM2 baseline — 28/28 online, 0 leaks, 20/20 health, 100/100 A+ (2026-05-26)"
metadata:
  node_type: memory
  type: project
  originSessionId: session-20260526-024918
---

# PM2 Deploy State — 2026-05-26

**28/28 online, 0 restarts, 0 jlist leaks, 0 :latest images, 20/20 health, daemon env clean**

Supersedes [[pm2-deploy-state-20260525]] (was 27/27).

## Fleet

| Process | Memory | Notes |
|---------|--------|-------|
| aiops-saas-api | 48MB | healthy |
| backup-verification | 3MB | healthy |
| command-center | 48MB | healthy |
| design-agent-svc | 110MB | healthy |
| ecosystem-guardian | 61MB | healthy |
| embedding-service | 859MB | healthy (all-MiniLM-L6-v2) |
| event-bus-relay | 58MB | healthy |
| executive-dashboard-api | 48MB | healthy |
| frgcrm-agent-svc | 100MB | healthy |
| frgcrm-api | 269MB | healthy |
| horizon-agent-svc | 107MB | healthy |
| insforge-agent-svc | 75MB | healthy |
| litellm | 356MB | healthy (:4049) |
| openclaw-dashboard | 61MB | healthy |
| paperless-agent-svc | 109MB | healthy |
| pm2-logrotate | 82MB | healthy (module, config: 10M/30retain/compress/midnight) |
| prediction-radar-agent-svc | 111MB | healthy |
| ravyn-agent-svc | 108MB | healthy |
| repo-engine | 3MB | healthy |
| repo-listener | 3MB | healthy |
| revenue-metrics-collector | 49MB | healthy |
| surplusai-portal-api | 103MB | healthy |
| surplusai-scraper-agent-svc | 109MB | healthy |
| voice-agent-svc | 106MB | healthy |
| voice-outreach-service | 53MB | healthy |
| war-room-server | 59MB | healthy |
| wheeler-brain-api | 92MB | healthy |
| wheeler-collectors | 29MB | healthy |
| wheeler-orchestrator | 52MB | healthy |

## Docker

44 containers: 42 healthy, 2 no-healthcheck (fincept + crowdsec, both running fine)

## Daemon (PID 3776088)

PM2 daemon environ: **CLEAN** — 0 secrets. Only HOME, PATH, PM2_HOME, SHELL, USER, standard systemd vars.
secrets.env: **DELETED** — no plaintext credentials at /root/.pm2/

## Resurrect Chain

- pm2-root systemd: **enabled** (boots on system start)
- dump.pm2: **28 processes** saved (pm2-logrotate is module, persists separately)
- pm2-logrotate module: configured (10M max, retain 30, compress, rotate at midnight)

## Permissions

- settings.json + settings.local.json: 14 tool-level permissions (Write, Edit, Read, Agent, TaskCreate/Update/Get/List/Output/Stop, CronCreate/Delete/List, WebFetch, WebSearch)
- Auto-approve working for all coding operations

## Verified (2026-05-26 02:50 UTC)

- PM2 jlist secret scan: 29/29 clean, 0 leaks
- Functional healthcheck: 20/20 passed
- Docker :latest audit: CLEAN
- Network binds: Expected only (SSH :22, nginx :443, Tailscale, systemd-resolved)
- Daemon environ: 0 secrets
- /root/.pm2/secrets.env: DELETED
- Disk: 72G/338G (22%)

## Score: 100/100 A+
