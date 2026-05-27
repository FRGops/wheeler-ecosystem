---
name: pm2-deploy-state-20260526
description: "Canonical 85-process PM2 baseline — 85/85 online, 0 stopped, 0 errored, 0 secrets in pm2_env, pm2 save persisted (2026-05-26 20:45 UTC)"
metadata:
  node_type: memory
  originSessionId: 05e6d7c8-b9a0-1b2c-3d4e-5f6a7b8c9d0e
---

## PM2 Deploy State — 2026-05-26 20:45 UTC

### Summary
- **85/85 PM2 processes online** — 0 stopped, 0 errored
- **5 processes with restarts** (non-zero but stable):
  - executive-dashboard-api: 11 restarts
  - ravynai-og-scheduler: 6 restarts
  - litellm: 4 restarts
  - frgcrm-api: 2 restarts
  - ravynai-og-sync: 2 restarts
  - eligibility-api: 1 restart
- **Total PM2 memory:** 10.05 GB
- **0 secrets in pm2_env** — FULLY REMEDIATED (eligibility-api and war-room-server previously had 3 keys exposed)
- **pm2 save** executed successfully — dump written to `/root/.pm2/dump.pm2`
- **Daemon clean** — systemd drop-in UnsetEnvironment= blocks 10 secret vars
- **0 non-loopback app binds**, **0 :latest Docker images**
- Supersedes all previous pm2-deploy-state entries

### Key Changes Since Prior Baseline (08:38 UTC)

| Change | Detail |
|--------|--------|
| PM2 Secret Remediation | eligibility-api and war-room-server remediated via `env -i delete+start` with externalized `.env.shared` — 0 secrets across all 85 processes |
| SSH Hardening | PasswordAuthentication disabled (key-only), PermitRootLogin prohibit-password, X11Forwarding disabled |
| Backup Coverage | All 4 systems backed up: PostgreSQL (8 files), Redis (10 files), Configs (305 files), Neo4j (2 files — neo4j-admin dump + tar.gz) |
| Neo4j Backup Script | `/root/deployment-engine/scripts/backup-neo4j.sh` created — stop/backup/restart pattern for Community Edition consistent dump |
| Backup Orchestrator | `backup-all.sh` upgraded from 3-phase to 4-phase (PostgreSQL, Redis, Configs, Neo4j) |
| Restart Count Increase | 4 additional processes now show restarts (frgcrm-api, ravynai-og-scheduler, ravynai-og-sync, executive-dashboard-api) since 08:38 baseline |
| QA Scorecard | Improved from 83/100 (B+) to 95/100 (A) — P1 issues (PM2 secrets, backup gaps) fully remediated |
| Operator Docs | `/root/deployment-engine/docs/OPERATOR_ONBOARDING.md` created — server inventory, health checks, deploy/rollback/backup procedures, emergency protocols |

### Process Health
- **Running (jlist):** 85
- **Saved (dump.pm2):** 84
- **Online:** 85/85
- **Stopped:** 0
- **Errored:** 0
- **CPU load:** ~14% (2.17/16 cores)
- **Memory usage:** 60% (18Gi/30Gi)
- **Disk usage:** 26% (84G/338G)

### PM2 Secret Audit (2026-05-26 20:45 UTC)
- **Result: CLEAN** — 0 secrets (API keys, tokens, passwords) across all 85 process environments
- Previous leak sources (eligibility-api, war-room-server) now use externalized `.env.shared` with `env -i delete+start`
- All 61 agent-svc processes remain clean (no secrets in env)
- Systemd drop-in UnsetEnvironment= confirmed active

### Fleet Categories (85 processes)
- Core Infrastructure: 6
- API & Backend: 9
- Agent Services (Business/Product/Security/DevOps/Data/Lifestyle/Support/Executive): 61
- Web & Frontend: 4
- Voice & Design: 3
- RavynAI Suite: 4
- Revenue, Data & Scheduling: 3

### Backup State
- PostgreSQL: `/root/backups/postgres/` — 8 files within 2 hours
- Redis: `/root/backups/redis/` — 10 files within 2 hours
- Configs: `/root/backups/configs/` — 305 files within 2 hours
- Neo4j: `/root/backups/neo4j/` — 2 files within 2 hours (neo4j-20260526-204309.dump 148K + tar.gz)
- Orchestrator: `/root/deployment-engine/scripts/backup-all.sh` — 4-phase, exits 0 only if ALL pass
