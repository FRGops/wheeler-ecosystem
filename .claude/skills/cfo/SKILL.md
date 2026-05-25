---
name: cfo
description: AI CFO Financial Command Center — full ecosystem financial health assessment, cost/revenue synthesis, capital allocation review, and executive financial briefing.
trigger: cfo, financial overview, financial health check, ai cfo, cfo report, financial status
---

# Skill: AI CFO

Full financial health assessment. Synthesizes from all 40 financial agents. Produces executive briefing.

## Execution

Run all data collection in parallel, then synthesize:

```bash
# 1. Docker health
docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null | head -20
docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}' 2>/dev/null | head -20

# 2. PM2 health
pm2 jlist 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
online = sum(1 for p in data if p.get('pm2_env',{}).get('status')=='online')
total = len(data)
print(f'PM2: {online}/{total} online')
for p in data:
    mem = p.get('monit',{}).get('memory',0)/1024/1024
    name = p.get('name','?')
    status = p.get('pm2_env',{}).get('status','?')
    print(f'  {name}: {status} ({mem:.0f}MB)')
"

# 3. AI spend (LiteLLM)
curl -s http://127.0.0.1:4049/spend/logs?limit=50 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    entries = data if isinstance(data, list) else data.get('data', [])
    total = sum(float(e.get('spend',0) or e.get('cost',0)) for e in entries)
    models = {}
    for e in entries:
        m = e.get('model','?')
        models[m] = models.get(m,0) + float(e.get('spend',0) or e.get('cost',0))
    print(f'AI Spend (last 50 requests): \${total:.4f}')
    for m, s in sorted(models.items(), key=lambda x: -x[1]):
        print(f'  {m}: \${s:.4f}')
except: print('LiteLLM unreachable or no data')
" 2>/dev/null

# 4. System resources
free -h | head -2
df -h / | tail -1
uptime

# 5. Cost estimate
echo "=== MONTHLY COST ESTIMATE ==="
echo "Hetzner CPX51: ~\$50-100"
echo "AI/API (DeepSeek+Claude+OpenAI): ~\$50-100"
echo "SaaS subscriptions: ~\$50"
echo "Domains: ~\$20"
echo "TOTAL ESTIMATED BURN: ~\$200-300/mo"
echo "REVENUE: \$0 (pre-revenue, Stripe test mode)"
echo "RUNWAY: depends on cash reserves"
```

## Synthesis

After collecting all data, produce:

```
WHEELER CFO DAILY BRIEFING — [DATE]
──────────────────────────────────────
FINANCIAL HEALTH SCORE: XX/100

COST HEALTH (25%):  [score] — [summary]
REVENUE HEALTH (25%): [score] — $0 (pre-revenue)
CASH HEALTH (25%):   [score] — [summary]
EFFICIENCY (15%):    [score] — [summary]
RISK HEALTH (10%):   [score] — [summary]

ACTIVE ALERTS:
🔴 P0: [count]
🟡 P1: [count]
🔵 P2: [count]

TOP 3 ACTIONS:
1. Fix COREDB connection (P0 — blocks FRG revenue)
2. Activate Stripe live mode (P0 — enables all revenue)
3. Fix PipelineDAG 6 stages (P0 — unblocks 6,603 cases)

DOCKER: X/Y healthy | PM2: X/Y online
AI SPEND 24H: $X | MONTH PROJECTED: $X
INFRA COST: ~$X/mo | BURN RATE: ~$X/mo
```

## Integration
- Live dashboard: http://127.0.0.1:8180/
- All financial agents: /root/.claude/agents/
- Full architecture: /root/WHEELER_FINANCIAL_OS_REPORT.md
