---
name: pm2-restart-pattern-20260523
description: PM2 env var changes require env -i delete+start (not restart); restart reuses stored pm2_env.env; --update-env injects shell secrets
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 6dba188d-26c9-4049-8064-8d37dafc0cb9
---

When changing environment variables in a PM2 ecosystem.config.js, `pm2 restart --update-env` is unreliable AND dangerous. The safe pattern is:

1. `env -i HOME=/root PATH="..." PM2_HOME=/root/.pm2 pm2 delete <name>` — remove from PM2 process list
2. `env -i HOME=/root PATH="..." PM2_HOME=/root/.pm2 pm2 start ecosystem.config.js --only <name>` — start fresh with clean env
3. Verify stability: check `restarts: 0` and uptime > 60s
4. `pm2 save --force` — persist the new clean state

**Why `env -i` is required:** Without it, `pm2 start` sends the CLI's shell environment to the PM2 daemon, injecting all secrets (DEEPSEEK_API_KEY, ANTHROPIC_AUTH_TOKEN, REDIS_PASSWORD, HCLOUD_TOKEN, LITELLM_MASTER_KEY) into the process's stored `pm2_env.env`. This re-creates the jlist secret exposure that was eliminated in the 100/100 audit.

**Why `restart` doesn't work for config changes:** PM2 caches env vars from the initial start in `pm2_env.env`. A `restart` reuses the cached env — CLI flags don't override it. Only `delete` + fresh `start` guarantees the new env is picked up.

**Why `--update-env` is dangerous:** It merges the CLI's current shell environment into the stored env, injecting secrets from `.bashrc`-sourced files like `/root/.config/wheeler/secrets.env`.

**How to apply:** Any time you edit an ecosystem.config.js `env:` block, use the env -i delete+start pattern. For simple `pm2 restart` (no env changes, process is already clean), a plain restart is fine — it preserves the existing clean state.

See also: [[pm2-env-i-pattern]], [[pm2-restart]]

## Related: Docker health check `localhost` trap

When writing `healthcheck:` blocks, use `127.0.0.1` not `localhost`. Many containers have `/etc/hosts` mapping `localhost` to both `127.0.0.1` and `::1` (IPv6). If the app binds only IPv4 (`0.0.0.0`), `wget`/`curl` may resolve `localhost` to `::1` and get "Connection refused" even though the service is running.

## Related: PM2 `DATABASE_URL` investigation pattern

When a PM2 process crashes in a restart loop:
1. `pm2 logs <name> --lines 50 --nostream` — get the crash error
2. `pm2 env <id>` — check environment variables (look for DB URLs, API keys)
3. Compare with working sibling processes (`pm2 env <other-id>`) to find mismatches
4. Check the ecosystem.config.js for hardcoded env values vs .env file loading
