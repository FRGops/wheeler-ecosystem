---
name: secret-rotation-20260524
description: Internal DB/Redis passwords rotated 2026-05-24 — FRGpassword1! replaced with unique 48-char hex passwords per system
metadata: 
  node_type: memory
  type: project
  originSessionId: cf1e5c0f-ee3a-43ab-aadd-f99343ec85e0
---

All internal database and Redis passwords rotated on 2026-05-24. Previously, `FRGpassword1!` was reused across Redis (COREDB), prediction-radar postgres (AIOPS), and wheeler postgres (COREDB). Each now has a unique 48-char hex password.

**Why:** Passwords were hardcoded in compose files and reused across systems. Now separated into .env files with unique values.

**How to apply:** When adding new services that need COREDB access, use the existing rotated passwords from the .env files rather than creating new credentials. The canonical .env locations:
- COREDB postgres/redis: `/opt/wheeler-core/.env` on 100.118.166.117
- usesend: `/opt/apps/usesend/.env` on 100.121.230.28
- wheeler postgres: `/opt/wheeler/apps/frgcrm/api/.env` on 100.121.230.28
- prediction-radar: `/opt/apps/prediction-radar-app/.env` on 100.121.230.28
