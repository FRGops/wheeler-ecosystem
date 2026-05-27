---
name: pm2-daemon-secret-cleanup-20260526
description: "PM2 daemon secret leak fixed via systemd drop-in — secrets now flow through .env files only, jlist clean (2026-05-26)"
metadata: 
  node_type: memory
  type: project
  originEpoch: 2026-05-26
  originSessionId: b6f7e595-0ff3-41ea-a0aa-b7c6c56c9d88
---

# PM2 Daemon Secret Cleanup — 2026-05-26

## The Discovery

`pm2 jlist` revealed 11 processes carrying ANTHROPIC_AUTH_TOKEN and DEEPSEEK_API_KEY in their `pm2_env.env` even after `env -i delete+start` remediation. The leak kept returning because the PM2 daemon itself inherited these secrets from the systemd unit environment (which inherits from the root shell).

Root cause: `pm2-root.service` was started from a root shell that had secrets in `~/.zshrc` / `~/.bashrc`. Those secrets flowed into the PM2 daemon process environment. When PM2 spawns child processes, it merges its own environment into theirs -- so even `env -i` deletes were re-contaminated on daemon restart or resurrect.

## The Fix

**File:** `/etc/systemd/system/pm2-root.service.d/clean-env.conf`

```ini
[Service]
UnsetEnvironment=ANTHROPIC_AUTH_TOKEN
UnsetEnvironment=DEEPSEEK_API_KEY
UnsetEnvironment=ANTHROPIC_API_KEY
UnsetEnvironment=LITELLM_MASTER_KEY
UnsetEnvironment=HCLOUD_TOKEN
UnsetEnvironment=ANTHROPIC_BASE_URL
UnsetEnvironment=ANTHROPIC_MODEL
UnsetEnvironment=ANTHROPIC_DEFAULT_SONNET_MODEL
UnsetEnvironment=ANTHROPIC_DEFAULT_OPUS_MODEL
UnsetEnvironment=ANTHROPIC_DEFAULT_HAIKU_MODEL
```

This tells systemd to strip those env vars from the PM2 daemon's environment before launching it. The drop-in pattern means the main unit file at `/etc/systemd/system/pm2-root.service` is untouched -- clean upgrades.

After applying:
```bash
systemctl daemon-reload
systemctl restart pm2-root
```

This restarts all 32 PM2 processes with a clean daemon environment. After restart, `pm2 jlist` shows 0 secret leaks.

## Why It's Safe

Processes that need secrets get them from their own sources, not from the PM2 daemon env:

| Process | Secret Source |
|---------|--------------|
| litellm | `/opt/apps/litellm/.env` (hardcoded path in ecosystem.config.js) |
| frgcrm-api | `.env.shared` sibling file |
| All agent services | `.env.shared` or `.env` in app directory |
| execution-dashboard | `.env` in app directory |
| eligibility-api, frg-site, dashboard | `.env` or config files in app directory |

No process reads ANTHROPIC_AUTH_TOKEN or DEEPSEEK_API_KEY from `process.env` -- they all load via dotenv or explicit env file paths. Stripping from the daemon environment causes zero functional impact while eliminating the credential spray.

## What Changed

| Artifact | Change |
|----------|--------|
| `/etc/systemd/system/pm2-root.service.d/clean-env.conf` | **Created** -- systemd drop-in with 10 UnsetEnvironment directives |
| `/root/.claude/skills/slay/SKILL.md` (Phase 1b) | **Updated** -- secret leaks classified as P0 (hardcoded in config) vs P1 (daemon-inherited) |
| `/usr/local/bin/70-wheeler.sh` | **Updated** -- added `wheeler-secrets-audit` command (pm2 jlist scan wrapper) |
| PM2 daemon | **Restarted** -- `systemctl daemon-reload && systemctl restart pm2-root` |
| pm2-deploy-state | **Updated** -- 32-process baseline, jlist scan: CLEAN |

## Classification of Leak Severity

| Tier | Source | Example | Remediation |
|------|--------|---------|-------------|
| P0 | Hardcoded in ecosystem.config.js `env:{}` | `ANTHROPIC_AUTH_TOKEN` written directly in config | `env -i delete+start` -- fixed once, stays fixed |
| P1 | Daemon-inherited (this fix) | Secret in root shell, picked up by PM2 daemon | Systemd drop-in `UnsetEnvironment=` -- daemon restart fixes all |
| P2 | `process.env.VAR` reference in config | `process.env.API_KEY \|\| ""` in env block | Rewrite to use dotenv -- already documented in pm2-process-env-leak.md |

## Verification

```bash
# Check jlist is clean
pm2 jlist | python3 -c "
import json, sys
real = ['API_KEY','AUTH_TOKEN','PASSWORD','MASTER_KEY','HCLOUD_TOKEN']
for p in json.load(sys.stdin):
    env = p.get('pm2_env',{}).get('env',{})
    found = {k for k in env if any(s in k.upper() for s in real)}
    if found: print(f'LEAK: {p[\"name\"]}: {sorted(found)}')
"
# Expected output: (nothing -- 0 leaks)
```

## Related References

- [PM2 process.env Leak Pattern](pm2-process-env-leak.md) -- P2 leak via process.env in config
- [PM2 env -i Delete+Start Pattern](pm2-env-i-pattern.md) -- P0 remediation pattern
- [PM2 Deploy State 2026-05-26](pm2-deploy-state-20260526.md) -- current baseline
- [/slay skill](.claude/skills/slay/SKILL.md) -- Phase 1b now classifies leaks as P0 vs P1
