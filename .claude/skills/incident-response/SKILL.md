---
name: incident-response
description: "Structured incident response: severity classification (P0-P4), affected service identification, log analysis, root cause analysis, fix implementation, verification, post-mortem template."
trigger: incident response, incident, outage, production issue, service down, emergency, post mortem, postmortem
---

# Skill: Incident Response

Structured incident response workflow. Integrates with wheeler-incident-command.

## Severity Classification

| Level | Definition | Response Time | Example |
|-------|-----------|---------------|---------|
| **P0** | Production down, revenue impact, data loss | Immediate (< 5 min) | Database unreachable, API returning 500 |
| **P1** | Major feature broken, significant user impact | < 15 min | Login broken, payments failing |
| **P2** | Minor feature degraded, workaround available | < 1 hour | Dashboard slow, non-critical endpoint erroring |
| **P3** | Cosmetic, no user impact | < 4 hours | UI glitch, documentation issue |
| **P4** | Internal tooling, informational | Next business day | Dev environment issue |

## Response Workflow

### 1. Detect (T+0)
```
Source: Monitoring alert / user report / health check failure
Action: Acknowledge alert, assess initial severity
```

### 2. Assess (T+2 min)
```bash
# Parallel diagnostic commands
docker ps --format '{{.Names}} {{.Status}}' | grep -v healthy
pm2 list | grep -v online
tail -100 /var/log/syslog | grep -iE 'error|fail|critical|oom'
```

### 3. Contain (T+5 min)
```
- Stop the bleeding first
- Enable maintenance mode if needed
- Rate limit / circuit break / failover
- Save logs before they rotate
```

### 4. Diagnose (T+10 min)
```
Use systematic debugging:
1. Read exact error
2. Identify wrong assumption
3. Find minimal reproduction
4. Trace to root cause
```

### 5. Fix (T+varies)
```
- Fix root cause, not symptom
- Apply fix
- Verify with evidence
- Monitor for 5 min
```

### 6. Recover (T+fix+5 min)
```
- Confirm service restored
- Verify health checks passing
- Check for regressions
- Update status page
```

### 7. Post-Mortem (within 24h)
```
Template:
- Incident title and severity
- Timeline (detection → resolution)
- Root cause (technical)
- Contributing factors
- Fix applied
- Prevention plan
- Action items with owners and due dates
```

## Integration

- Use `/fix` for systematic debugging
- Use `/rollback` if fix fails
- Use `/docker-health` and `/pm2-health` for service status
- Use `wheeler-incident-command` playbooks in /opt/wheeler-incident-command/

## Output Format

```
INCIDENT: <id> — <title>
──────────────────────────────────────
SEVERITY:  [P0/P1/P2/P3/P4]
STATUS:    [DETECTED / ASSESSING / CONTAINING / FIXING / RECOVERED]
SERVICE:   <name>
DURATION:  <elapsed>
──────────────────────────────────────
CURRENT:   <action being taken>
NEXT:      <next step>
OWNER:     <name>
──────────────────────────────────────
```
