---
name: pm2-restart-canonical
description: PM2 restart procedures now have a canonical Claude Code skill at capabilities/skills/pm2-recovery/SKILL.md
metadata: 
  node_type: memory
  type: reference
  originSessionId: 08edff32-d5eb-41c5-b29c-23671200d591
---

The PM2 restart procedures are now codified as a reusable Claude Code skill.

**Canonical source**: `/opt/wheeler-ecosystem/capabilities/skills/pm2-recovery/SKILL.md`
**Active skill**: `/root/.claude/skills/pm2-recovery/SKILL.md`
**Trigger keywords**: pm2 recovery, pm2 crash, pm2 restart, pm2 fix, recover pm2, pm2 down, process crashed

The skill encodes:
- verify→act→verify pattern from [[pm2_restart_pattern]]
- DEEPSEEK_API_KEY root cause check from [[pm2-restart-patterns]]
- env var delete+start (not restart) rule from [[pm2-restart-pattern-20260523]]
- Docker HEALTHCHECK localhost vs 127.0.0.1 trap
- Memory exhaustion diagnosis
- Port conflict resolution
- Post-recovery verification (pm2 save, log check, uptime confirmation)

To use: `/pm2-health` (slash command) or invoke the `pm2-recovery` skill directly.
