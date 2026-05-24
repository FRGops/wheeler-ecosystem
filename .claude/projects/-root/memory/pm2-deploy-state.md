---
name: pm2-deploy-state
description: Current PM2 deployment state across Wheeler ecosystem as of 2026-05-23 after full remediation and cleanup governance audit
metadata: 
  node_type: memory
  type: project
  originSessionId: ef69c29a-1e70-48f3-89c2-b19a998c2325
---

Wheeler PM2 deployment is fully remediated and stable after security audit hardening + cleanup governance audit on 2026-05-23.

## AIOPS (5.78.140.118) — 17 online, 1 stopped
- backup-verification: stopped (daily cron at 6am — intentional)
- surplusai-portal-frontend: REMOVED (migrated to EDGE — see below)

## EDGE (187.77.148.88) — 1 online (surplusai-portal-frontend) + other PM2 services
- surplusai-portal-frontend: online, PM2-managed on port 3003, proxies API to AIOPS via Tailscale (100.121.230.28:8103)

## Services Fixed This Session (cleanup governance audit)
| Service | Server | Original Issue | Fix |
|---|---|---|---|
| surplusai-portal-frontend | AIOPS → EDGE | Wrong-server workload, unmanaged bare process on EDGE | Migrated to EDGE, PM2-managed, API proxy fixed (localhost:8100→Tailscale:8103) |
| node-exporter (Docker) | EDGE | 610 restarts, port 9100 conflict | Removed Docker container; native node_exporter (pid 867) already serves port 9100 |
| temporal-temporal-1 | EDGE | Exited (sqlite), stale | Removed dead container |
| prediction-radar-app-worker/scheduler | EDGE | Exited (137), stale after migration to AIOPS | Removed dead containers |
| usesend/usesend-redis/usesend-storage | EDGE | Exited, defunct stack | Removed dead containers |
| nginx-test | AIOPS | Idle, no ports | Removed dead container |
| /opt/openclaw-dashboard/runtime/.env | AIOPS + EDGE | 66 days stale | Archived with chmod 600 |

## Previous Fixes (security audit hardening session)
| Service | Server | Original Issue | Fix |
|---|---|---|---|
| surplusai-portal-api | EDGE | 4108 restarts, crash loop | Restart with --update-env |
| ravyn-deal-room-api | EDGE | 608 restarts, STOPPED | Restart |
| temporal-pipeline-worker | EDGE | 591 restarts, no Temporal server | Fixed Temporal DB=postgres12, re-added to PM2 |
| temporal-pipeline-scheduler | EDGE | Missing from PM2 | Re-added to PM2 |
| frgcrm-api | EDGE | Missing from PM2 | Re-added via ecosystem.config.js, single-worker mode |
| event-bus-relay | AIOPS | NOAUTH Redis | Added REDIS_PASSWORD to ecosystem.config.js, pm2 delete+start |
| war-room-server | AIOPS | ERRORED (missing psycopg2) | Restart resolved |

## Critical Learnings
- **pm2 restart --update-env does NOT re-read ecosystem.config.js** — must pm2 delete + pm2 start to pick up config file env changes
- **Temporal auto-setup does not support DB=sqlite** — requires postgres12, mysql8, or cassandra
- **EDGE PostgreSQL** is at shared-postgres-recovery on 127.0.0.1:5432 (frgops/frgops_secure_2026)
- **COREDB Redis** requires auth: REDIS_PASSWORD=FRGpassword1!, reachable via Tailscale at 100.118.166.117:6379
- **Multiple docker compose files for Temporal** — active one is /root/services/temporal/docker-compose.temporal.yml (network_mode: host)
- **Temporal server and worker must be restarted together** — worker crash-loops without server, server dies without proper DB config
- **surplusai-portal-frontend API proxy was broken on both servers** — next.config.js rewrote to localhost:8100 but nothing listens there. Fixed to Tailscale IP 100.121.230.28:8103 on EDGE
- **Next.js rewrites only apply when no local route matches** — /api/health and /api/admin/* are handled by Next.js route handlers; everything else proxies to Python backend
- **Audit "wrong-server" detection has ~71% false-positive rate** — 10/14 findings were intentional local-dependency patterns (app-local DBs/caches co-located with their apps)

## Security Hardening Applied
- EDGE SSH: PasswordAuthentication no, PermitRootLogin prohibit-password
- All servers: .env files chmod 600
- All servers: UFW deny rules for exposed DB ports, allow only Tailscale+localhost
- AIOPS: .env.bak/.env.audit-backup deleted, kalshi_private_key.pem chmod 600
