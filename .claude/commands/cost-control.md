# /cost-control — AI and Infrastructure Cost Audit

Analyze AI API usage, model routing efficiency, compute costs, and identify optimization opportunities with dollar estimates.

## Execution (ALL in parallel)

```bash
# 1. Check LiteLLM proxy for usage stats
curl -s http://127.0.0.1:4000/global/activity 2>/dev/null | python3 -m json.tool 2>/dev/null | head -50

# 2. Docker resource usage (CPU/memory by container)
docker stats --no-stream --format '{{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}} MEM' 2>/dev/null

# 3. PM2 memory usage
pm2 jlist 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
total_mem = sum(p['monit']['memory'] for p in data)
for p in sorted(data, key=lambda x: x['monit']['memory'], reverse=True)[:10]:
    print(f'{p[\"name\"]:35s} {p[\"monit\"][\"memory\"]/1024/1024:6.1f}MB')
print(f'{\"TOTAL\":35s} {total_mem/1024/1024:6.1f}MB')
" 2>/dev/null

# 4. Disk usage by Docker
docker system df -v 2>/dev/null | head -40

# 5. Idle container detection
# Containers using < 0.1% CPU over 24h are flagged
docker stats --no-stream --format '{{.Name}} {{.CPUPerc}}' 2>/dev/null | grep '0.00%'

# 6. Check for unused Docker images (> 30 days old)
docker images --format '{{.Repository}}:{{.Tag}} {{.CreatedAt}} {{.Size}}' 2>/dev/null

# 7. PM2 process that could be consolidated
pm2 list 2>/dev/null | grep -E 'online.*[0-9]+h' | awk '{print $4, $NF}'
```

## Cost Categories

| Category | Check | Optimization |
|----------|-------|-------------|
| **AI API** | Model routing (DeepSeek vs Claude), cache hit rate | Route to cheaper model when quality allows |
| **Compute** | Idle containers, oversized instances | Rightsize, consolidate services |
| **Storage** | Old images, large volumes, unrotated logs | Prune, rotate, tier to cheaper storage |
| **Network** | Cross-region traffic, public bandwidth | Keep traffic within private network |
| **Memory** | Overallocated PM2 processes | Reduce --max-memory-restart thresholds |

## Output Format

```
╔══════════════════════════════════════════════╗
║   Cost Control Audit — <timestamp>           ║
╚══════════════════════════════════════════════╝

AI API USAGE (est. monthly):
  DeepSeek:    $<est> (<N> requests)
  Claude:      $<est> (<N> requests)
  Cache hits:  <pct>% (saving $<est>)

COMPUTE:
  Docker: <N> containers, <CPU> CPU, <MEM> memory
  PM2:    <N> processes, <MEM> total
  Idle:   <N> containers/processes using < 1% CPU

STORAGE:
  Docker images:  <size> (<N> unused, <size> reclaimable)
  Volumes:        <size>
  Logs:           <size> (PM2 + Docker + system)

──────────────────────────────────────────────
SAVINGS OPPORTUNITIES:
  [$$$] <opportunity> — est. $<amount>/month
  [$$]  <opportunity> — est. $<amount>/month
  [$]   <opportunity> — est. $<amount>/month

TOTAL POTENTIAL SAVINGS: $<sum>/month
──────────────────────────────────────────────
```
