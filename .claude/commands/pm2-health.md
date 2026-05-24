# /pm2-health — PM2 Process Health Audit

Comprehensive PM2 health check across all processes. Includes the DEEPSEEK_API_KEY root cause check and crash pattern analysis.

## Execution (ALL in parallel)

```bash
# 1. All processes
pm2 list 2>/dev/null

# 2. Process details (memory, CPU, uptime, restarts)
pm2 jlist 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data:
    print(f'{p[\"name\"]:35s} mem={p[\"monit\"][\"memory\"]/1024/1024:6.1f}MB cpu={p[\"monit\"][\"cpu\"]:5.1f}% uptime={p[\"pm2_env\"][\"pm_uptime\"]} restarts={p[\"pm2_env\"][\"restart_time\"]} status={p[\"pm2_env\"][\"status\"]}')
" 2>/dev/null

# 3. Restart count (flag high restart counts)
pm2 list 2>/dev/null | grep -E '[0-9]+' | awk '{if ($NF ~ /^[0-9]+$/ && $NF > 5) print "[WARN] High restart count:", $0}'

# 4. Log sizes
du -sh /root/.pm2/logs/*.log 2>/dev/null | sort -rh | head -20

# 5. DEEPSEEK_API_KEY check (common root cause of PM2 crashes)
pm2 list 2>/dev/null | grep -E 'errored|stopped' | while read line; do
  name=$(echo "$line" | awk '{print $4}')
  env_check=$(pm2 env 2>/dev/null | grep DEEPSEEK_API_KEY || echo "not set")
  echo "[CHECK] $name — DEEPSEEK_API_KEY: $env_check"
done

# 6. PM2 saved state
pm2 save 2>/dev/null && echo "PM2 state saved for resurrection"
```

## Known Failure Patterns

| Pattern | Root Cause | Fix |
|---------|-----------|-----|
| Multiple processes stopped together | DEEPSEEK_API_KEY missing/expired | Restore API key, delete+start not restart |
| High memory growth | Memory leak in agent service | Restart with --max-memory-restart |
| Frequent restarts | Crash loop | Check logs, fix root cause before restart |
| Docker HEALTHCHECK mismatch | localhost vs 127.0.0.1 | Align healthcheck binding |

## Output Format

```
╔══════════════════════════════════════════════╗
║   PM2 Health Audit — <timestamp>             ║
╚══════════════════════════════════════════════╝

PROCESSES: <N> online, <N> stopped, <N> errored
──────────────────────────────────────────────
TOP MEMORY:
  <name>: <MB>

HIGH RESTART COUNT (>5):
  <name>: <count> restarts — [CHECK LOGS]

LOG SIZES:
  <largest logs>

DEEPSEEK_API_KEY CHECK:
  [PASS/FAIL — <N> processes missing key]

──────────────────────────────────────────────
OVERALL: [HEALTHY / NEEDS ATTENTION / CRITICAL]
RECOMMENDATION: <action if issues found>
```
