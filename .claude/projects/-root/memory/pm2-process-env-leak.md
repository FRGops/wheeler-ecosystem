---
name: pm2-process-env-leak
description: "PM2 ecosystem.config.js `process.env.VAR || \"\"` pattern leaks shell secrets into stored PM2 env"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ecc0cddd-b2c8-4d99-9436-6f3f2f3937ac
---

Never use `process.env.VAR || ""` inside `env: {}` in ecosystem.config.js. PM2 evaluates this at start time against the current shell environment and stores the resolved value permanently in `pm2_env.env`. Even after `env -i delete+start`, if the ecosystem config references process.env, the next start re-captures whatever is in the starting shell.

**Why:** The 2026-05-24 /slay audit found 4 processes (revenue-metrics-collector, executive-dashboard-api, aiops-saas-api, wheeler-brain-api) with actual secret values in PM2 jlist. The root cause was ecosystem.config.js files using `process.env.VAR || ""` to set defaults. Even though `env -i` was used for restart, the `process.env.X` references re-evaluated and captured the shell's LITELLM_MASTER_KEY (which was still in the environment).

**How to apply:** Always use hardcoded defaults in ecosystem.config.js `env: {}` blocks. Never reference `process.env` there. Secrets must be loaded by the application at runtime via .env files, dotenv, or a secrets manager — never via PM2 env. The canonical `env -i delete+start` pattern only works if the ecosystem config doesn't re-import shell env.

**Fix pattern:**
1. Edit ecosystem.config.js: replace `VAR: process.env.VAR || ""` with nothing (remove the line)
2. `pm2 delete <name>`
3. `env -i HOME=/root PATH="..." NODE_ENV=production pm2 start ecosystem.config.js --only <name>`
4. `pm2 save --force`
5. Verify with: `pm2 jlist | python3 -c "..."` — check both key names AND values

**Related:** [[pm2-env-i-pattern]] [[pm2-restart-canonical]]
