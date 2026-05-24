---
name: pm2-env-i-pattern
description: PM2 env -i delete+start pattern for eliminating secrets from pm2 jlist; restart reuses stored env
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 8ed32f72-2c5b-44e5-b809-25c0a26ed4ee
---

PM2 `restart` reuses stored `pm2_env.env` — if polluted, secrets persist regardless of CLI flags. Only `delete` + `env -i start` creates clean processes. Daemon auto-restarts (crash recovery) preserve stored env, so clean→clean.

**Why:** PM2 captures env once at spawn from ecosystem config `env:` block + parent CLI env. Restart re-applies stored env, not CLI env. Delete wipes stored state. The `pm2-env-wrapper.sh` provides secrets at runtime via `exec` without PM2 ever storing them.

**How to apply:**
```bash
# Fix polluted process:
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 delete <name>
env -i HOME=/root PATH="..." PM2_HOME=/root/.pm2 pm2 start <ecosystem.config.js> --only <name>

# Never: env -i pm2 restart <name>  ← still uses stored env
# Safe:   pm2 restart <name>         ← preserves existing clean state
```
