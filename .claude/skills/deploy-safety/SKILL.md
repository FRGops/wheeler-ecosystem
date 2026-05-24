---
name: deploy-safety
description: "Pre-deployment safety gate: runs backup verification, health check, resource check, dependency check, breaking change detection. Either gives green light or lists specific blockers."
trigger: deploy safety, safe deploy, deployment gate, pre-deploy, before deploy, deploy check
---

# Skill: Deploy Safety Gate

Pre-deployment safety gate that must pass before any production deployment. Returns GO or lists specific NO-GO blockers.

## Gate Checklist

### Gate 1: Backup Verification
```bash
# Check backups exist and are recent
find /opt/wheeler-ecosystem/backups -mtime -1 -type f 2>/dev/null | wc -l
find /root/backups -mtime -1 -type f 2>/dev/null | wc -l
```
Requirement: ≥ 1 backup in last 24 hours.

### Gate 2: Health Check
```bash
# All containers healthy
docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -v healthy
# All PM2 online
pm2 list 2>/dev/null | grep -E 'stopped|errored'
```
Requirement: Zero unhealthy containers, zero stopped/errored PM2 processes.

### Gate 3: Resource Check
```bash
# Disk > 20% free
df -h / | awk 'NR==2{gsub(/%/,""); if($5>80) print "FAIL: disk at "$5"%"; else print "PASS: disk at "$5"%"}'
# Memory > 30% available
free | awk 'NR==2{if($7/$2<0.3) print "FAIL: memory low"; else print "PASS: memory OK"}'
# Load < 80% of cores
```

### Gate 4: No Active Incidents
Check incident log for unresolved P0/P1 incidents.

### Gate 5: Secrets Scan Clean
```bash
bash /opt/wheeler-ecosystem/security/secret-scan.sh
```
Requirement: Zero new CRITICAL or HIGH findings vs baseline.

### Gate 6: Breaking Change Detection
- API schema changes: backwards compatible?
- Database migrations: reversible?
- Config changes: documented?
- Dependency major version bumps: tested?

### Gate 7: Rollback Plan
- Specific rollback steps documented
- Rollback tested in last 30 days
- Rollback duration estimated

## Output Format

```
╔══════════════════════════════════════════════╗
║   Deploy Safety Gate — <component>           ║
║   <version-old> → <version-new>              ║
╚══════════════════════════════════════════════╝

GATES:
  [✓] Backup verified       (<N> backups in 24h)
  [✓] Health check green     (0 issues)
  [✓] Resources sufficient   (disk <pct>%, mem <pct>%)
  [✓] No active incidents
  [✓] Secrets scan clean
  [✓] No breaking changes
  [✓] Rollback plan ready

──────────────────────────────────────────────
DECISION: [GO / NO-GO — <N> blocked gates]
BLOCKERS: <list or "none">
──────────────────────────────────────────────
```
