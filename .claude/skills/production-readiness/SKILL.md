---
name: production-readiness
description: "Production readiness assessment: 20-point checklist covering backups, monitoring, alerting, logging, security, resource limits, healthchecks, restart policies, documentation, runbooks, SLOs, incident response, capacity planning."
trigger: production readiness, production ready, prod ready, deploy ready, release ready, go live check, launch check
---

# Skill: Production Readiness

20-point production readiness assessment. Every service must pass this before going to production.

## 20-Point Checklist

### Backups & Recovery (5 pts)
```
□ 1. Automated backups configured and running daily
□ 2. Backup restoration tested in last 30 days
□ 3. Off-site/off-node backup copy exists
□ 4. RPO (Recovery Point Objective) documented and met
□ 5. RTO (Recovery Time Objective) documented and met
```

### Monitoring (4 pts)
```
□ 6. Health checks configured and passing
□ 7. Resource monitoring (CPU, memory, disk, network)
□ 8. Application-level metrics (requests, errors, latency)
□ 9. Dashboard accessible to on-call
```

### Alerting (3 pts)
```
□ 10. Critical failure alerts configured
□ 11. Alert fatigue managed (signal-to-noise ratio)
□ 12. Escalation path documented
```

### Security (4 pts)
```
□ 13. Secrets scan clean
□ 14. Dependencies audited (no critical CVEs)
□ 15. Authentication/authorization properly configured
□ 16. Network properly firewalled
```

### Reliability (4 pts)
```
□ 17. Restart policy configured (unless-stopped)
□ 18. Healthcheck with appropriate interval/timeout/retries
□ 19. Resource limits set (no unbounded growth)
□ 20. Graceful shutdown handling
```

### Operations (bonus)
```
□ Runbook exists and is current
□ Rollback procedure documented
□ Capacity planning done
□ Incident response drill completed
```

## Scoring

| Score | Decision |
|-------|----------|
| 20/20 | **GO** — Production ready |
| 17-19 | **CONDITIONAL GO** — Fix warnings within 1 week |
| 14-16 | **NO-GO** — Address blockers first |
| < 14 | **NOT READY** — Significant work required |

## Automated Checks

Run the Wheeler safety gate for production readiness:
```bash
bash /opt/wheeler-ecosystem/capabilities/safety-gates/gate-check.sh production-readiness
```

## Output Format

```
PRODUCTION READINESS: <service>
──────────────────────────────────────
SCORE: <N>/20 (<pct>%)

BACKUPS:     <score>/5 [PASS/FAIL]
MONITORING:  <score>/4 [PASS/FAIL]
ALERTING:    <score>/3 [PASS/FAIL]
SECURITY:    <score>/4 [PASS/FAIL]
RELIABILITY: <score>/4 [PASS/FAIL]

BLOCKERS: <list or "none">
WARNINGS: <list or "none">

DECISION: [GO / CONDITIONAL / NO-GO / NOT READY]
NEXT REVIEW: <date>
```
