---
name: pm2-recovery
description: "PM2 crash recovery procedure: diagnose crash cause (logs, env vars, memory), check DEEPSEEK_API_KEY, restart safely with verify-act-verify pattern, save PM2 state."
trigger: pm2 recovery, pm2 crash, pm2 restart, pm2 fix, recover pm2, pm2 down, process crashed
---

# Skill: PM2 Recovery

Safe PM2 crash recovery following the verify→act→verify pattern. Never restart blindly — diagnose first.

## Common Root Causes (check in order)

1. **DEEPSEEK_API_KEY missing/expired** — Most common cause of multi-process failures
2. **Memory exhaustion** — Process exceeded memory limit
3. **Port conflict** — Another process bound to required port
4. **Database connection** — PostgreSQL unreachable or auth failed
5. **Config change** — Env var or config file changed without restart

## Recovery Procedure

### Phase 1: Diagnose
```bash
# Check status
pm2 list

# Check logs (last 50 lines)
pm2 logs --nostream --lines 50 <process-name>

# Check env vars
pm2 env <process-id> | grep -E 'API_KEY|SECRET|DATABASE_URL|REDIS'

# Check memory
pm2 jlist | python3 -c "import json,sys;[print(f'{p[\"name\"]}: {p[\"monit\"][\"memory\"]/1024/1024:.1f}MB') for p in json.load(sys.stdin)]"
```

### Phase 2: Fix Root Cause
```
If DEEPSEEK_API_KEY issue:
  1. Verify key is valid
  2. Update in ~/.config/wheeler/secrets.env
  3. Source secrets.env
  4. pm2 delete <process> && pm2 start ecosystem.config.js --only <process>
     (NOT pm2 restart — env changes require delete+start)

If memory issue:
  1. Increase --max-memory-restart in ecosystem.config.js
  2. Or fix memory leak in application code

If port conflict:
  1. Identify competing process: ss -tulpn | grep <port>
  2. Resolve conflict
```

### Phase 3: Verify Recovery
```bash
# Confirm process online
pm2 list | grep <process-name> | grep online

# Check for immediate re-crash
sleep 5
pm2 list | grep <process-name> | grep -E 'online|errored'

# Check logs for errors
pm2 logs --nostream --lines 20 <process-name> | grep -i error

# Save PM2 state
pm2 save
```

## Safety Rules

- NEVER `pm2 kill` without saving state first
- NEVER `pm2 restart` when env vars changed — use delete+start
- NEVER restart a process that restarted > 5 times in 10 minutes — diagnose first
- ALWAYS check DEEPSEEK_API_KEY before restarting multiple stopped processes
- ALWAYS `pm2 save` after successful recovery

## Output Format

```
PM2 RECOVERY: <process-name>
──────────────────────────────────────
DIAGNOSIS: <root cause>
FIX: <action taken>
VERIFICATION:
  Status: [online/errored/stopped]
  Memory: <MB>
  Uptime: <time>
  Errors in logs: [none/found — <details>]
──────────────────────────────────────
RESULT: [RECOVERED / NEEDS MORE WORK / ESCALATE]
```
