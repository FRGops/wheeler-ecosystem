# /incident-response — Incident Response Workflow

Structured incident response from detection through resolution and post-mortem. Integrates with wheeler-incident-command.

## Execution

### Phase 1: Assess (30 seconds)
```
SEVERITY:
  P0 — Production down, revenue impact, data loss
  P1 — Major feature broken, significant user impact
  P2 — Minor feature degraded, workaround available
  P3 — Cosmetic, no user impact
  P4 — Internal tooling, informational

AFFECTED SERVICES:
  - Identify from: docker ps, pm2 list, tailscale status
  - Determine blast radius: what depends on the affected service?
```

### Phase 2: Triage (2 minutes)
```bash
# Parallel log gathering
docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -v healthy
pm2 list 2>/dev/null | grep -v online
tail -100 /var/log/syslog 2>/dev/null | grep -iE 'error|fail|critical|oom|kill'
dmesg --level=err,warn 2>/dev/null | tail -20

# Service-specific logs
docker logs --tail 50 <affected-container> 2>&1
pm2 logs --nostream --lines 50 <affected-process> 2>/dev/null
```

### Phase 3: Contain & Mitigate
```
1. Stop the bleeding first (rate limiting, failover, circuit breaker)
2. Do NOT restart blindly — capture state first
3. Save logs before they rotate
4. Communicate status to stakeholders
```

### Phase 4: Root Cause Analysis
```
Use /fix systematic debugging pattern:
1. Read exact error
2. Identify wrong assumption
3. Find minimal reproduction
4. Fix root cause (not symptom)
5. Verify fix
```

### Phase 5: Recovery
```
1. Apply fix
2. Verify service health
3. Monitor for 5 minutes
4. Confirm no regression
5. Update status page
```

### Phase 6: Post-Mortem
```
INCIDENT: <title>
SEVERITY: <P0-P4>
DURATION: <start> → <resolved> (<total>)
──────────────────────────────────────
TIMELINE:
  <time> — detected by <source>
  <time> — diagnosed as <root cause>
  <time> — mitigated by <action>
  <time> — resolved by <fix>

ROOT CAUSE: <specific technical cause>
CONTRIBUTING FACTORS: <what made it worse>
FIX: <what was changed>
PREVENTION: <what will prevent recurrence>
──────────────────────────────────────
ACTION ITEMS:
  □ <action> — owner: <name>, due: <date>
  □ <action> — owner: <name>, due: <date>
```

## Output Format

```
╔══════════════════════════════════════════════╗
║   INCIDENT RESPONSE — <incident-id>          ║
╚══════════════════════════════════════════════╝

STATUS:     [DETECTED / TRIAGING / MITIGATING / RESOLVED]
SEVERITY:  [P0/P1/P2/P3/P4]
SERVICE:   <affected service>
DURATION:  <elapsed>
──────────────────────────────────────────────
CURRENT ACTION: <what's happening now>
NEXT STEP:      <immediate next action>
──────────────────────────────────────────────
```
