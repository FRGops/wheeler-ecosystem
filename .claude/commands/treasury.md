# /treasury — Treasury Intelligence Command

Display cash position, liquidity forecast, and treasury health metrics.

## Execution

Launch the `treasury-intelligence` agent with supporting data from `cashflow-forecasting`:

1. Cash position: available, pending, reserved, net
2. Burn rate: daily, monthly, trend
3. Runway: months of cash at current burn rate
4. 13-week cash flow projection
5. Upcoming payments (next 30 days)
6. Liquidity ratios and health score
7. Stripe balance (when live)

## Output
- Treasury Health Score
- Cash position summary
- Runway analysis
- 13-week cash flow projection
- Upcoming payment calendar
- Active treasury alerts
- Recommendation: any action needed (build reserves, prepare for large payment, etc.)
