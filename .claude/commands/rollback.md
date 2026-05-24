# /rollback — Safe Rollback Procedure

Execute a rollback to the last known good state. Follows the rollback-first principle: every change must have a tested rollback path.

## Execution

### Phase 1: Identify Last Safe State
```bash
# Check backups
ls -lt /opt/wheeler-ecosystem/backups/ 2>/dev/null | head -10
ls -lt /root/backups/ 2>/dev/null | head -10

# Check git reflog for deploy markers
git -C /opt/wheeler-ecosystem reflog -10 2>/dev/null

# Check Docker image history
docker images --format '{{.Repository}}:{{.Tag}} {{.CreatedAt}}' 2>/dev/null | head -10
```

### Phase 2: Execute Rollback
```bash
# Use Wheeler rollback tool
bash /opt/wheeler-ecosystem/bin/wheeler-rollback <component> <target-version>
```

Manual rollback steps (if tool unavailable):
1. Stop current service/container
2. Restore configuration from backup
3. Start previous version
4. Verify health
5. Monitor for 2 minutes

### Phase 3: Verify Recovery
```bash
# Run health checks
bash /opt/wheeler-ecosystem/monitoring/docker-healthcheck.sh 2>/dev/null
bash /opt/wheeler-ecosystem/monitoring/pm2-healthcheck.sh 2>/dev/null

# Verify service is responding
# (service-specific checks)
```

### Phase 4: Report
- What was rolled back
- From version → To version
- Reason for rollback
- Duration of outage
- Verification results

## Output Format

```
ROLLBACK: <component>
FROM: <bad-version>
TO:   <good-version>
──────────────────────────────────────
REASON: <why rollback was needed>
──────────────────────────────────────
STEPS:
  [✓] Stop current
  [✓] Restore backup: <backup-file>
  [✓] Start previous version
  [✓] Health check: <result>
  [✓] Monitor: <duration> — stable
──────────────────────────────────────
RESULT: [SUCCESS / FAILED]
OUTAGE: <duration>
NEXT: <follow-up actions needed>
```
