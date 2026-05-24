# Wheeler Brain OS — Self-Healing Framework

**Version:** 2.0.0 | **Date:** 2026-05-24

## Self-Healing Architecture

```
DETECT ──► DIAGNOSE ──► REMEDIATE ──► VERIFY
   │            │             │            │
   ▼            ▼             ▼            ▼
Monitoring   Agent         Skill         Agent
alerts       analysis      execution     verification
```

## Healing Categories

### 1. Process Recovery (PM2)
- **Detect:** PM2 process status = stopped/errored
- **Diagnose:** pm2-recovery skill — check logs, env vars, memory
- **Remediate:** `env -i delete+start` pattern (never just restart)
- **Verify:** Check process online, port listening, API responding
- **Owner:** pm2-recovery skill + pm2-intelligence agent

### 2. Docker Recovery
- **Detect:** Container health check failing or container stopped
- **Diagnose:** docker-health skill — check logs, bindings, resources
- **Remediate:** Restart container, verify health check passes
- **Verify:** HEALTHCHECK status = healthy
- **Owner:** docker-health skill + docker-intelligence agent

### 3. Configuration Drift Correction
- **Detect:** drift-detection agent finds deviation from baseline
- **Diagnose:** Compare current vs known-good config
- **Remediate:** Restore known-good config (with approval)
- **Verify:** Re-run drift detection — clean
- **Owner:** drift-detection agent

### 4. Secret Rotation
- **Detect:** secrets-scan skill finds exposed or stale secrets
- **Diagnose:** Identify all services using the secret
- **Remediate:** Rotate secret, update all consumers, verify
- **Verify:** Re-run secrets-scan — clean
- **Owner:** secrets-scan skill + security-intelligence agent

### 5. Backup Verification
- **Detect:** backup-verification daemon finds missing/stale backups
- **Diagnose:** Identify which backups are missing
- **Remediate:** Trigger backup creation
- **Verify:** Re-run verification — pass
- **Owner:** backup-verification process

### 6. Ecosystem-Wide Health Recovery
- **Detect:** /slay skill runs 20-endpoint health audit
- **Diagnose:** Identify all broken services
- **Remediate:** Fix each broken service using domain-specific recovery
- **Verify:** Re-run /slay — all 20 endpoints healthy
- **Owner:** /slay skill

## Automated Recovery Rules

| Condition | Action | Auto? |
|---|---|---|
| PM2 process stopped | env -i delete+start | Semi (requires pm2-recovery skill) |
| Docker container unhealthy | Restart container | Semi |
| Memory > 85% | Alert + identify top consumers | No (advisory) |
| Disk > 80% | Alert + log rotation | No (advisory) |
| SSL cert < 30 days | Alert | No (manual renewal) |
| Secret exposed in logs | Rotate immediately | Semi (auto-rotate, manual verify) |
| UFW rule drift | Alert + recommend restore | No (advisory) |
| Docker bind changed to 0.0.0.0 | Alert CRITICAL | No (requires investigation) |

## Safety Constraints

- No autonomous destructive actions (rm, drop, reset)
- No autonomous deployment rollback without verification
- No autonomous secret generation without backup
- All healing actions logged to Loki
- All healing actions verified by no-false-greens-qa
