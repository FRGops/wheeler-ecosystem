---
name: cost-control
description: "Cost optimization: AI API usage analysis, model routing efficiency, compute resource optimization, idle resource detection, storage optimization. Produces savings recommendations with dollar estimates."
trigger: cost control, cost audit, reduce costs, cost optimization, spending audit, AI costs, cloud costs
---

# Skill: Cost Control

Analyze infrastructure and AI costs. Identify optimization opportunities with dollar estimates. Integrates with wheeler-ai-cost-governance.

## Audit Categories

### AI API Costs
```bash
# Check LiteLLM proxy for usage data
curl -s http://127.0.0.1:4000/global/activity 2>/dev/null | python3 -m json.tool 2>/dev/null | head -50

# Check model routing efficiency
# DeepSeek ($0.14/1M input) vs Claude ($3/1M input)
# Route appropriate tasks to cheaper models
```

### Compute Costs
```bash
# Find idle containers (< 0.1% CPU)
docker stats --no-stream --format '{{.Name}} {{.CPUPerc}} {{.MemUsage}}' 2>/dev/null | grep '0.00%'

# Find oversized PM2 processes
pm2 jlist 2>/dev/null | python3 -c "
import json, sys
for p in json.load(sys.stdin):
    mem = p['monit']['memory']/1024/1024
    if mem > 500:
        print(f'{p[\"name\"]}: {mem:.0f}MB — check if overallocated')
"

# Check for services that could be consolidated
```

### Storage Costs
```bash
# Docker cleanup potential
docker system df 2>/dev/null

# Old images (> 30 days)
docker images --format '{{.Repository}}:{{.Tag}} {{.CreatedAt}} {{.Size}}' 2>/dev/null

# Large log files
find /root/.pm2/logs -name "*.log" -size +100M 2>/dev/null
find /var/log -name "*.log" -size +100M 2>/dev/null
```

### Idle Resources
```bash
# Containers running but not serving traffic
# Services with zero recent activity
# Unused volumes
docker volume ls -q 2>/dev/null | while read vol; do
  usage=$(docker run --rm -v "$vol:/vol" alpine du -sh /vol 2>/dev/null)
  echo "$vol: $usage"
done
```

## Optimization Recommendations

| Priority | Action | Est. Savings/mo |
|----------|--------|----------------|
| HIGH | Route non-critical AI tasks to DeepSeek | $50-200 |
| HIGH | Remove unused Docker images/volumes | $5-20 |
| MEDIUM | Rightsize PM2 memory limits | $10-30 |
| MEDIUM | Rotate logs aggressively | $2-10 |
| LOW | Consolidate microservices | $10-40 |

## Output Format

```
COST CONTROL AUDIT: <timestamp>
──────────────────────────────────────
AI API (est. monthly):
  DeepSeek:  $<est> (<N> requests, <pct>% of total)
  Claude:    $<est> (<N> requests, <pct>% of total)
  Cache hit: <pct>% (saving $<est>)

COMPUTE:
  Active:    <N> containers, <N> PM2 processes
  Idle:      <N> (<pct>% of total)
  Rightsize: <N> candidates

STORAGE:
  Docker: <size> (<size> reclaimable)
  Logs:   <size>
  Volumes:<N> (<N> unused)

──────────────────────────────────────
SAVINGS OPPORTUNITIES (monthly):
  [$$$] <N> high impact   — est. $<amount>
  [$$]  <N> medium impact  — est. $<amount>
  [$]   <N> low impact     — est. $<amount>
  ─────────────────────────
  TOTAL: $<sum>/month potential
──────────────────────────────────────
```
