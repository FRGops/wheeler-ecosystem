# /fix — Systematic Debugging Workflow

Apply the superpowers systematic-debugging pattern to diagnose and fix issues. Never guess — follow evidence.

## Execution

### Step 1: Read the Actual Error
```
- Get the exact error message (not a paraphrase)
- Check logs: docker logs, pm2 logs, journalctl, app logs
- Capture full stack trace if available
- Note timestamps — correlate with deployments or config changes
```

### Step 2: Identify the Wrong Assumption
```
- What did we expect to happen?
- What actually happened?
- What changed recently? (git log, docker events, config diffs)
- Check PM2 env vars (DEEPSEEK_API_KEY pattern)
- Check Docker HEALTHCHECK (localhost vs 127.0.0.1 trap)
```

### Step 3: Find Minimal Reproduction
```
- Can we reproduce it in isolation?
- What's the smallest input that triggers it?
- Is it environment-specific or code-specific?
```

### Step 4: Fix Root Cause, Not Symptom
```
- Address the underlying issue
- Don't paper over with retries or fallbacks unless justified
- Consider: is this a config issue, code bug, or infrastructure problem?
```

### Step 5: Verify the Fix
```
- Run the exact reproduction case — does it still fail?
- Check for regressions in related functionality
- Monitor logs for 2 minutes after fix
- Run health check
```

## Output Format

```
ERROR: <exact error message>
SOURCE: <log file or command output>
──────────────────────────────────────
WRONG ASSUMPTION: <what we thought vs reality>
ROOT CAUSE: <underlying issue>
FIX: <what was changed>
──────────────────────────────────────
VERIFICATION:
  Command: <verification command>
  Result:  <output>
  Exit:    <code>
  Status:  [FIXED / NEEDS MORE WORK]
```
