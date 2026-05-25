# /cfo — AI CFO Financial Command Center

Trigger the AI CFO agent to produce a full financial health assessment. Synthesizes data from all 40 financial agents into an executive briefing.

## Execution

Launch the `ai-cfo` agent with a request for a comprehensive financial health report. The agent will:

1. Pull latest data from Wave 1 agents (infrastructure costs, AI spend, resource allocation)
2. Pull latest data from Wave 2 agents (treasury, cashflow, budget status)
3. Pull latest data from Wave 3 agents (revenue, billing, subscriptions — when live)
4. Compute the composite Financial Health Score (Cost 25%, Revenue 25%, Cash 25%, Efficiency 15%, Risk 10%)
5. Generate the CEO Daily Brief format with: key metrics, active alerts, top 3 recommended actions

## Output
- Financial Health Score with trend
- Cost breakdown (infrastructure, AI, SaaS, other)
- Revenue summary (when live: MRR, churn, growth)
- Cash position and runway
- Active P0/P1 alerts
- Top 3 recommended actions
