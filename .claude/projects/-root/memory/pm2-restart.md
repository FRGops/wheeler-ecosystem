---
name: pm2-restart
description: Safe PM2 restart procedures for Wheeler ecosystem services across AIOPS and EDGE nodes (current as of 2026-05-23 post-cleanup governance)
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6a038ea9-403e-48ad-a871-bce68bc6c6a6
---

**Why:** PM2 manages all Wheeler backend services on AIOPS (5.78.140.118) and frontends on EDGE (187.77.148.88). Unsafe restarts can cause downtime, restart loops, or false-green health checks.

**How to apply:** Before restarting any PM2 service, baseline with `pm2 jlist`, restart with `pm2 restart <name> --update-env`, then re-verify. Never restart during active migrations.

## Service restart commands

### AIOPS Node (5.78.140.118) — 18 online, 1 stopped

**Routine restart (preserves existing env, clean→clean):**
```
pm2 restart <name>
```

**Never use `--update-env`** — it injects the CLI's shell environment including all secrets (DEEPSEEK_API_KEY, ANTHROPIC_AUTH_TOKEN, etc.) into PM2's stored state. This re-creates the jlist secret exposure that was eliminated in the 100/100 audit.

**For ecosystem config changes (script, args, env block):**
```
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 delete <name>
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 start /path/to/ecosystem.config.js --only <name>
```
`pm2 restart` does NOT re-read ecosystem config files; only delete+start does.

**Intentionally stopped:**
- backup-verification (daily cron at 6am)

### EDGE Node (187.77.148.88) — 1 online

```
pm2 restart surplusai-portal-frontend --update-env
```

Note: Most EDGE services run outside PM2 (Docker, systemd, or raw processes). The 19 previously stopped PM2 entries were intentionally decommissioned and removed.

## Safe restart procedure
1. `pm2 jlist | python3 -c "..."` — capture baseline (status, restarts, uptime)
2. **Routine restart**: `pm2 restart <name>` (preserves stored env, safe for clean processes)
3. **Config change**: `env -i pm2 delete <name> && env -i pm2 start <config> --only <name>`
4. Wait 5 seconds
5. `pm2 status` — verify status is "online"
6. Verify no restart count spike (> 10 in current uptime = restart loop)
7. After any delete+start: `pm2 save --force` to persist clean state to dump.pm2

**Critical: restart vs delete+start**
- `pm2 restart` reuses stored `pm2_env.env` — safe for routine restarts
- `pm2 restart --update-env` injects CLI environment → **NEVER use, pollutes with secrets**
- `pm2 delete` + `pm2 start` wipes stored env and reads config fresh → required for config changes
- `env -i` prefix strips the CLI's shell env → required for delete+start to prevent secret injection

See also: [[pm2-env-i-pattern]]

## Danger signs
- Restarts > 10 in current uptime = CRITICAL restart loop
- Total restarts > 50 = WARN
- CPU > 80% = WARN
- Memory > 1GB or > 80% of max_memory_restart = WARN
- Status "errored" or "stopped" = CRITICAL
- PID 0 = process failed to start

## Previous Incidents (for pattern recognition)
- **2026-05-23**: 3 processes (frgcrm-api, surplusai-scraper, voice-agent) in restart loops — root cause DEEPSEEK_API_KEY missing from PM2 env. Fixed by adding key to ecosystem.config.js
- **2026-05-23**: event-bus-relay ERRORED — NOAUTH Redis. Fixed by adding REDIS_PASSWORD to env, pm2 delete+start
- **2026-05-23**: surplusai-portal-api 4108 restarts on EDGE — resolved with --update-env restart
- **2026-05-23**: frgcrm-frontend, surplusai-frontend, attorney-frontend removed from EDGE PM2 — all migrated to Docker/systemd
