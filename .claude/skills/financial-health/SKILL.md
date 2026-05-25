---
name: financial-health
description: Full ecosystem financial health audit — per-domain deep dive into infrastructure costs, AI spend, vendor costs, treasury, cashflow, and governance compliance.
trigger: financial health, financial audit, financial health check, cost audit deep, money audit, spending audit
---

# Skill: Financial Health Audit

Deep financial health audit across all domains. More detailed than /cfo (which is executive summary).

## Execution (launch in parallel)

### Domain 1: Infrastructure Costs
```bash
echo "=== INFRASTRUCTURE COST ALLOCATION ==="
docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}' 2>/dev/null | while IFS=$'\t' read name cpu mem_pct mem_usage; do
    echo "$name: CPU=$cpu MEM=$mem_pct ($mem_usage)"
done
echo ""
echo "=== DOCKER DISK ==="
docker system df 2>/dev/null
echo ""
echo "=== PM2 MEMORY ==="
pm2 jlist 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
total_mem = sum(p.get('monit',{}).get('memory',0) for p in data)
print(f'Total PM2 memory: {total_mem/1024/1024:.0f}MB across {len(data)} processes')
for p in sorted(data, key=lambda x: -x.get('monit',{}).get('memory',0))[:10]:
    name = p.get('name','?')
    mem = p.get('monit',{}).get('memory',0)/1024/1024
    print(f'  {name}: {mem:.0f}MB')
"
```

### Domain 2: AI Spend
```bash
echo "=== AI TOKEN SPEND (LiteLLM :4049) ==="
# Spend by model
curl -s http://127.0.0.1:4049/spend/logs?limit=200 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    entries = data if isinstance(data, list) else data.get('data', [])
    total = sum(float(e.get('spend',0) or e.get('cost',0)) for e in entries)
    print(f'Total (last 200 requests): \${total:.4f}')
    # Per model
    models = {}
    keys = {}
    for e in entries:
        m = e.get('model','?')
        k = e.get('api_key','?')[:12]
        c = float(e.get('spend',0) or e.get('cost',0))
        models[m] = models.get(m,0) + c
        keys[k] = keys.get(k,0) + c
    print()
    print('By Model:')
    for m, s in sorted(models.items(), key=lambda x: -x[1]):
        print(f'  {m}: \${s:.4f} ({s/total*100:.0f}%)')
    print()
    print('By API Key:')
    for k, s in sorted(keys.items(), key=lambda x: -x[1])[:5]:
        print(f'  {k}...: \${s:.4f} ({s/total*100:.0f}%)')
except Exception as e:
    print(f'LiteLLM unreachable or no data: {e}')
" 2>/dev/null

# Check prompt caching
echo ""
echo "=== PROMPT CACHING ==="
curl -s http://127.0.0.1:4049/global/activity 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(json.dumps(data, indent=2)[:500])
except: print('No activity data')
" 2>/dev/null
```

### Domain 3: System & Vendor
```bash
echo "=== SYSTEM RESOURCES ==="
echo "CPU: $(nproc) cores | $(lscpu 2>/dev/null | grep 'Model name' | cut -d: -f2 | xargs)"
free -h | head -2
df -h / | tail -1
echo "Uptime: $(uptime -p)"

echo ""
echo "=== VENDOR/SaaS ESTIMATE ==="
echo "Hetzner CPX51: ~\$50-100/mo"
echo "AI APIs: ~\$50-100/mo (variable)"
echo "SaaS tools: ~\$50/mo"
echo "Domains: ~\$20/mo (annualized)"
echo "TOTAL: ~\$200-300/mo"
echo "REVENUE: \$0 (pre-revenue)"
```

## Synthesis

After all data collected, produce:

```
FINANCIAL HEALTH AUDIT — [DATE]
═══════════════════════════════════

OVERALL HEALTH: XX/100
  Cost Health:    XX/100
  Revenue Health: 0/100 (pre-revenue)
  Cash Health:    XX/100
  Efficiency:     XX/100
  Risk:           XX/100

COST BREAKDOWN (monthly):
  Infrastructure:  $XX
  AI/API:          $XX
  SaaS/Vendor:     $XX
  Other:           $XX
  TOTAL BURN:      $XX

OPTIMIZATION OPPORTUNITIES (ranked by ROI):
  1. [highest ROI opportunity]
  2. [second]
  3. [third]

ACTIVE ALERTS: [count by severity]

TOP 5 RECOMMENDED ACTIONS:
  1. [action with rationale]
  ...
```
