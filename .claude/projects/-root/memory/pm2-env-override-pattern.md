---
name: pm2-env-override-pattern
description: "ecosystem.config.js env:{} block overrides .env files — never put secrets in env:{} blocks"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: fd60059c-19e3-49a8-a6f0-6f7f465319eb
---

PM2 `env:{}` blocks take precedence over wrapper-loaded `.env` files.
The `pm2-env-wrapper.sh` checks `[ -z "${!key+x}" ]` and skips vars already set —
so any var in the config's `env:{}` wins over `.env.shared` or `.env`.

**Why:** On 2026-05-24, surplusai-portal-api had a 43-restart crashloop because
`env:{DATABASE_URL: '...old_password...'}` overrode the correct rotated password
in `/opt/apps/surplusai-portal/.env`. The wrapper silently skipped DATABASE_URL.
PM2 also passes `args` as a single token, so `uvicorn main:app --host ...` fails
with `exec: ... not found` — use a run.sh wrapper instead of inline args.

**How to apply:** When a PM2 process fails with DB auth errors:
1. Check `ecosystem.config.js` env:{} for hardcoded DATABASE_URL/API_KEY
2. Remove any secret-like value from env:{} — let .env files provide them
3. Use `env -i pm2 delete + start` (never restart) to clear stored env
4. Verify with `pm2 jlist` that no secrets appear in stored state
