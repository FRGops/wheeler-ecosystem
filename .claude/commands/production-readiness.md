# /production-readiness — Production Readiness Gate

20-point production readiness assessment. Returns a go/no-go with specific blockers and recommendations.

## Execution

### Checklist (20 Points)

Run these checks in parallel:

**Backups & Recovery (4 pts)**
```
□ Automated backups configured and running
□ Backup restoration tested in last 30 days
□ Off-site backup copy exists
□ RPO < 1 hour, RTO < 4 hours
```

**Monitoring & Alerting (4 pts)**
```
□ Health checks configured and passing
□ Resource monitoring active (CPU, memory, disk, network)
□ Alerting configured for critical failures
□ Dashboard accessible to on-call team
```

**Security (4 pts)**
```
□ Secrets scan clean (no keys/tokens in code)
□ Dependencies audited (no critical CVEs)
□ Network properly firewalled (UFW active)
□ Database ports bound to 127.0.0.1
```

**Reliability (4 pts)**
```
□ Restart policy configured (unless-stopped or always)
□ Healthcheck with appropriate interval/timeout
□ Resource limits set (memory/CPU)
□ Graceful shutdown handling
```

**Operations (4 pts)**
```
□ Runbook exists and is current
□ Rollback procedure documented and tested
□ Logging configured with appropriate retention
□ Incident response plan in place
```

### Run Verification
```bash
# Auto-check what we can
bash /opt/wheeler-ecosystem/capabilities/safety-gates/gate-check.sh production-readiness

# Manual checks required
echo "Manual verification needed for:"
echo "  - Backup restoration test"
echo "  - Runbook currency"
echo "  - Incident response drill completion"
```

## Output Format

```
╔══════════════════════════════════════════════╗
║   Production Readiness — <service/component> ║
╚══════════════════════════════════════════════╝

SCORE: <N>/20 (<pct>%)

BACKUPS:      <score>/4 [PASS/FAIL]
MONITORING:   <score>/4 [PASS/FAIL]
SECURITY:     <score>/4 [PASS/FAIL]
RELIABILITY:  <score>/4 [PASS/FAIL]
OPERATIONS:   <score>/4 [PASS/FAIL]

──────────────────────────────────────────────
BLOCKERS:
  <list of specific items that must be fixed>

WARNINGS:
  <list of items to address soon>

──────────────────────────────────────────────
DECISION: [GO / NO-GO — <N> blockers / CONDITIONAL — fix warnings within <time>]
```
