---
name: coredb-credential-rotation-complete-20260527
description: COREDB PostgreSQL credential rotation completed 2026-05-27 — FRGpassword1! fully removed, all 7 dependent containers reconciled, 0 containers with old password
metadata:
  type: project
  node_type: memory
  originSessionId: session-20260527-012330
---

# COREDB Credential Rotation — Completed 2026-05-27

PostgreSQL rotation from May 24 was incomplete: the .env file was updated to the hex password but the container was never recreated, so it still accepted `FRGpassword1!`. This has now been fully remediated.

**Why:** The .env at `/opt/wheeler-core/.env` had `POSTGRES_PASSWORD=4be38d4d330c1b63ef03d4dc8dd42ab370c22969b7ffd3a2` since May 24, but Docker Compose reads env vars at container creation time — not at runtime. `docker compose up -d --force-recreate postgres` was needed.

**How to apply:** When rotating credentials for Docker Compose services, always force-recreate after updating .env files. Also scan ALL containers for hardcoded passwords in their own docker-compose files (usesend, prediction-radar-scheduler, postgres-exporter all had hardcoded `FRGpassword1!`).

## What Was Fixed

| Service | Issue | Fix |
|---------|-------|-----|
| wheeler-postgres | .env updated but container not recreated | `docker compose up -d --force-recreate postgres` |
| usesend | Hardcoded `FRGpassword1!` in DATABASE_URL | sed replace in docker-compose.yml + force-recreate |
| prediction-radar-scheduler | Hardcoded `FRGpassword1!` in DATABASE_URL | sed replace in docker-compose.yml + rm+recreate |
| postgres-exporter | No compose file, started via `docker run` with old password | Stopped, removed, recreated with hex password |

## Verification Results

- Remote PostgreSQL: old password REJECTED, new hex password WORKS
- Redis: already using hex password (3214d972d5...)
- MinIO: already using hex password (71a5aedade...)
- Temporal: .env already had hex password, recovered after PG restart
- All 18 containers running, 0 containers with `FRGpassword1!`
- 3 SSH keys deployed to COREDB authorized_keys

## Remaining Issue

Hetzner Cloud Firewall (ID 11033456) blocks Tailscale SSH (100.118.166.117:22). SSH works via public IP (5.78.210.123) only. The firewall needs a rule allowing Tailscale IP range (100.64.0.0/10) for SSH.
