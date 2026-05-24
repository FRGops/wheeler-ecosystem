# /deploy-safe — Safe Deployment Gate

Execute a deployment through the Wheeler safety gate system. Never deploy without passing all gates.

## Execution

### Phase 1: Pre-Deploy Gates (ALL must pass)

```
□ Backup verified — latest backup < 1 hour old
□ Health check green — all containers healthy, all PM2 online
□ Resource check — >20% disk free, >30% memory available, load < 80% cores
□ No active incidents — check incident log
□ Rollback plan documented — specific steps to undo
□ Secrets scan clean — no new secrets in diff
□ Breaking change check — API compatibility verified
```

Run: `bash /opt/wheeler-ecosystem/capabilities/safety-gates/gate-check.sh pre-deploy`

### Phase 2: Deploy

```
1. Announce deployment (Slack/log)
2. Enable maintenance mode if needed
3. Execute deployment (docker compose up -d / pm2 restart / git pull && build)
4. Wait for health checks to pass
5. Run smoke tests
```

### Phase 3: Post-Deploy Verification

```
□ All containers healthy
□ All PM2 processes online
□ Smoke tests pass
□ Error rate normal (< 5% deviation)
□ Response time normal (< 10% deviation)
□ No new error patterns in logs
```

### Phase 4: Rollback (if any gate fails)

```
1. Stop current deployment
2. Restore previous version: bash /opt/wheeler-ecosystem/bin/wheeler-rollback
3. Verify health
4. Report failure with specific reason
```

## Output Format

```
DEPLOY: <service/component>
VERSION: <old> → <new>
──────────────────────────────────────
PRE-DEPLOY GATES:  [PASS 7/7]
DEPLOY STATUS:     [RUNNING]
POST-DEPLOY:       [VERIFYING...]
──────────────────────────────────────
RESULT: [SUCCESS / ROLLED BACK]
DURATION: <time>
```
