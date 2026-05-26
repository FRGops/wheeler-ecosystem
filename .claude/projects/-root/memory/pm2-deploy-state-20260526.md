---
name: pm2-deploy-state-20260526
description: "Canonical 28-process PM2 baseline — 28/28 online, 0 restarts, resurrect chain verified, pm2-logrotate configured (2026-05-26)"
metadata: 
  node_type: memory
  type: project
  originSessionId: b8a59dc1-7438-47d2-b512-f987dadd80da
---

# PM2 Deploy State — 2026-05-26

**28/28 online, 0 restarts, 0 secret leaks, 0 :latest images, 20/20 health**

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

## Resurrect Chain (survives reboot)

- pm2-root systemd: **enabled** (boots on system start)
- dump.pm2: 27 processes saved (pm2-logrotate is a PM2 module, persists separately)
- pm2-logrotate module: configured (10M max, retain 30, compress, rotate at midnight)

## Verified

- /slay audit: 20/20 health, 0 secret leaks, 0 :latest, network clean
- Functional healthcheck: 20/20 passed
- All critical endpoints responding
- PM2 resurrect tested: processes restore from dump.pm2
- Disk: 75G/338G (23%)
