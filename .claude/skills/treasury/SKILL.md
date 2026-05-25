---
name: treasury
description: Treasury intelligence — cash position, burn rate, runway analysis, liquidity forecast, upcoming payments, and financial risk monitoring.
trigger: treasury, cash position, runway, burn rate, liquidity, cash flow, how much money
---

# Skill: Treasury Intelligence

Cash position, runway, and liquidity intelligence for the Wheeler ecosystem.

## Execution

```bash
echo "=== TREASURY INTELLIGENCE ==="
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

echo "=== CASH POSITION ==="
echo "Stripe: TEST MODE (\$0 real balance)"
echo "Bank accounts: Not integrated"
echo "Estimated cash reserves: UNKNOWN (integrate bank/Stripe for real data)"
echo ""

echo "=== BURN RATE ==="
echo "Infrastructure (Hetzner): ~\$50-100/mo = \$1.67-3.33/day"
echo "AI/API (variable):      ~\$50-100/mo = \$1.67-3.33/day"
echo "SaaS subscriptions:      ~\$50/mo    = \$1.67/day"
echo "Domains:                 ~\$20/mo    = \$0.67/day"
echo "─────────────────────────────────────────"
echo "TOTAL DAILY BURN:        ~\$6.67-8.33/day"
echo "TOTAL MONTHLY BURN:      ~\$200-300/mo"
echo ""

echo "=== RUNWAY ==="
echo "Runway = Cash Reserves / Monthly Burn"
echo "At \$200/mo burn: \$1,000 = 5 months | \$5,000 = 25 months | \$10,000 = 50 months"
echo "At \$300/mo burn: \$1,000 = 3.3 months | \$5,000 = 16.7 months | \$10,000 = 33.3 months"
echo "⚠️  Cash reserves UNKNOWN — integrate bank feed for real runway calculation"
echo ""

echo "=== UPCOMING PAYMENTS (ESTIMATED) ==="
echo "Monthly: Hetzner CPX51 (\~\\$50-100) — auto-charged"
echo "Monthly/Variable: Anthropic invoice (\~\\$20-40)"
echo "Monthly/Variable: DeepSeek invoice (\~\\$20-50)"
echo "Annual: Domain renewals (\~\\$200-300/year across all domains)"
echo ""

echo "=== LIQUIDITY HEALTH ==="
echo "Working Capital: UNKNOWN (no AR/AP data)"
echo "Cash Conversion Cycle: N/A (pre-revenue)"
echo "Burn Multiple: N/A (pre-revenue)"
echo ""

echo "=== TREASURY ALERTS ==="
# Check if any large upcoming expenses
echo "No automated treasury alerts configured."
echo "⚠️  Set up bank/Stripe integration for real-time treasury monitoring."

echo ""
echo "=== RECOMMENDATIONS ==="
echo "1. Maintain minimum 6 months of expenses in cash reserve (\$1,200-1,800)"
echo "2. Integrate bank accounts for real cash position tracking"
echo "3. Activate Stripe live mode for revenue collection"
echo "4. Set up automated alerts for: cash <3 months runway, large upcoming payments"
```

## Treasury Health Score

Score (0-100) based on:
- Cash Reserves: /25 (unknown = 0)
- Runway: /25 (unknown = 0)
- Burn Rate Trend: /25 (stable ~$200-300 = 20)
- Liquidity Management: /25 (no automation = 5)
- TOTAL: ~25/100 (NEEDS ATTENTION — integrate bank/Stripe)

## Integration
- Full treasury agent: `/root/.claude/agents/treasury-intelligence.md`
- Master architecture: `/root/WHEELER_FINANCIAL_OS_REPORT.md`
