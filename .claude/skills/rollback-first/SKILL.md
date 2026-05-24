---
name: rollback-first
description: "Rollback-first mentality: before any change, identify rollback path. Back up current state, document rollback steps, verify rollback works. Integration with wheeler-rollback."
trigger: rollback first, rollback plan, before change, change safety, safe change, undo plan
---

# Skill: Rollback-First

Every change must have a tested rollback path before execution. This skill enforces that discipline.

## Rollback-First Protocol

### Before ANY Change

1. **Identify current state** — version, config, data snapshot
2. **Back up current state** — automated or manual
3. **Document rollback steps** — specific, testable commands
4. **Estimate rollback duration** — how long to recover?
5. **Verify rollback works** — test if possible without risk

### For Docker Changes
```bash
# Before docker compose up -d
docker compose ps  # capture current state
docker compose down --no-volumes  # stop (preserve volumes)
# Backup any config files changed
# Rollback: docker compose up -d (previous version)
```

### For PM2 Changes
```bash
# Before pm2 restart/reload
pm2 save  # snapshot current state
# Rollback: pm2 resurrect
```

### For Database Changes
```bash
# Before migration
pg_dump -h 127.0.0.1 -p 5433 -U frgops frgcrm > /root/backups/pre_migrate_$(date +%Y%m%d_%H%M%S).sql
# Rollback: psql < backup.sql
```

### For Config Changes
```bash
# Before editing any config
cp <config-file> <config-file>.backup-$(date +%Y%m%d-%H%M%S)
# Rollback: cp <backup> <config-file> && restart service
```

## Rollback Verification

After documenting the rollback plan, verify:
1. Can the rollback be executed by someone else at 3am?
2. Are all dependencies considered (DB, cache, queue)?
3. Is the backup accessible and restorable?
4. How do we know the rollback succeeded?

## Wheeler Rollback Integration
```bash
# Automated rollback for Wheeler-managed services
bash /opt/wheeler-ecosystem/bin/wheeler-rollback <component>
```

## Output Format

```
ROLLBACK PLAN: <change description>
──────────────────────────────────────
CURRENT STATE: <version/config>
BACKUP: <path or "none taken — READ ONLY change">
──────────────────────────────────────
ROLLBACK STEPS:
  1. <command>
  2. <command>
  3. <command>
DURATION: <estimated>
VERIFIED: [TESTED / UNTESTED — reason]
──────────────────────────────────────
READY TO PROCEED: [YES / NO — <reason>]
```
