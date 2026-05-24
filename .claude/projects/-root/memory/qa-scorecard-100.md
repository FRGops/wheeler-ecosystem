---
name: qa-scorecard-100
description: Wheeler ecosystem Stage 2 QA scorecard reached 100/100 A+ on 2026-05-24; all domains at A+; scorecard at /root/STAGE2_QA_SCORECARD_FINAL.md
metadata: 
  node_type: memory
  type: project
  originSessionId: 8ed32f72-2c5b-44e5-b809-25c0a26ed4ee
---

Wheeler ecosystem QA audit achieved 100/100 A+ on 2026-05-24. Scorecard: `/root/STAGE2_QA_SCORECARD_FINAL.md`.

**Score trajectory:** D+ (67) → A (93.6) → A+ (95.3) → A+ (99) → **A+ (100/100)**

**Why:** Full security hardening completed across 7 domains. The final 1-point gap (PM2 jlist parent-env secret exposure) was closed by discovering that PM2 captures env only at spawn time, and using `env -i delete + start` to eliminate all 5 parent-env secret types from PM2's stored state. Runtime secrets remain available to apps via the pm2-env-wrapper.sh pattern.

**Key architectural findings:**
- PM2 `filter_env` in v7.0.1 is a BLACKLIST (removes listed vars), not a whitelist
- PM2 `restart` reuses stored `pm2_env.env` — pollution survives `env -i restart`
- Only `delete` + `env -i start` creates truly clean process env
- Daemon auto-restarts preserve stored state (clean stays clean)
- `pm2-env-wrapper.sh` loads secrets at runtime via `exec`; PM2 never re-reads `/proc/PID/environ`

**Current state (verified 2026-05-24 07:42 UTC):**
- PM2 jlist: 0 real secrets across all 19 processes
- Docker: 0 `:latest` images
- Health: 20/20 endpoints passing
- All services on 127.0.0.1; only nginx on Tailscale IP
- Gateway: 5 security headers, TLS auto-renewal, auth + rate limiting
- Cron: backup verification, restore testing, TLS renewal, health checks

[[pm2-env-i-pattern]]
