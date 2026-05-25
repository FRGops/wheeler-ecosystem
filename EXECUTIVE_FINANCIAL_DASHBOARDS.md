# Wheeler Executive Financial Dashboards
## Bloomberg-Terminal Style Financial Command Center

**Date**: 2026-05-25
**Status**: Architecture designed — implementation when Executive Dashboard (:8180) financial panels are built

---

## Dashboard Design System

### Visual Language
- **Background**: #0a0a0a (deep black — Bloomberg terminal aesthetic)
- **Primary Accent**: #00ff88 (green — positive, growth, money)
- **Alert Red**: #ff4444 (critical alerts, negative movements)
- **Warning Amber**: #ffaa00 (watch items, approaching thresholds)
- **Data Blue**: #4488ff (neutral data, links, interactive elements)
- **Text**: #e0e0e0 (light grey — readable on dark)
- **Secondary Text**: #888888 (muted — labels, metadata)
- **Font**: Monospace (JetBrains Mono or similar — data density)

### Design Principles
1. **Glanceable**: Critical information visible without scrolling
2. **Drillable**: Click any number to see underlying data
3. **Actionable**: Every panel answers a question or prompts an action
4. **Trustworthy**: Every number traceable to source system
5. **Real-time**: Auto-refreshing (5-min for critical, hourly for full)

---

## Dashboard Suite

### 1. CFO Command Dashboard (:8180/finance)

**Primary executive view — one screen, full financial picture.**

```
┌──────────────────────────────────────────────────────────────┐
│ WHEELER FINANCIAL OS — CFO COMMAND                   [LIVE]  │
├────────────────┬────────────────┬────────────────┬───────────┤
│ 💰 MRR         │ 📈 ARR         │ 💵 CASH        │ 🔥 BURN   │
│ $12,450        │ $149,400       │ $48,200        │ $8.40/day │
│ +8.2% MoM ▲    │ run-rate       │ 19.1 mo runway │ -2.1% ▼   │
├────────────────┴────────────────┴────────────────┴───────────┤
│ REVENUE TREND (30-Day)                COST BREAKDOWN (MTD)   │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░              ████████ Infra  $94    │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░              ██████   AI    $73     │
│ Min: $380  Max: $520  Avg: $445       ████     SaaS  $47    │
│                                       ██       Other $18    │
├──────────────────────────────────────────────────────────────┤
│ 🔴 P0: [0 active]  🟡 P1: Stripe webhook rate 94.7% (<95%) │
├───────────────────────────┬──────────────────────────────────┤
│ TOP PRODUCTS BY MRR       │ COST BY CATEGORY                 │
│ 1. SurplusAI:   $4,200    │ Infrastructure:    $94/mo       │
│ 2. PredRadar:   $3,800    │ AI/API:            $73/mo       │
│ 3. FRG CRM:     $2,100    │ SaaS Tools:        $47/mo       │
│ 4. Attny Mkt:   $1,450    │ Domains:           $18/mo       │
│ 5. AI Ops:        $900    │ Total Burn:       $232/mo       │
├───────────────────────────┴──────────────────────────────────┤
│ KEY METRICS                                                  │
│ NDR: 108% ▲ │ LTV:CAC 4.2:1 │ Gross Margin: 72% │ Ro40: 38  │
└──────────────────────────────────────────────────────────────┘
```

### 2. Treasury Dashboard (:8180/finance/treasury)

```
┌──────────────────────────────────────────────────────────────┐
│ TREASURY COMMAND                                      [LIVE] │
├──────────────────────────────────────────────────────────────┤
│ CASH POSITION                 LIQUIDITY GAUGES               │
│ Available:    $48,200         Runway:  ████████████ 19.1 mo │
│ Pending:      $2,400          Ratio:   ████████████  2.4    │
│ Reserved:    -$8,000          Health:  ████████████ 85/100  │
│ Net Cash:    $42,600                                       │
├──────────────────────────────────────────────────────────────┤
│ 13-WEEK CASH FLOW PROJECTION                                 │
│ Week 1: $42,600 ████████████████                            │
│ Week 2: $42,350 ████████████████                            │
│ Week 4: $41,800 ████████████████                            │
│ Week 8: $40,100 ████████████████                            │
│ Week 13:$37,200 ████████████████                            │
│ Min cash: $36,800 (Week 12) — No crunch risk                │
├──────────────────────────────────────────────────────────────┤
│ UPCOMING PAYMENTS (Next 30 Days)                             │
│ May 28 — Hetzner CPX51:      ~$80    [auto]                 │
│ Jun 01 — Anthropic Invoice:  ~$45    [manual]                │
│ Jun 15 — Domain Renewal:     $18     [auto]                  │
└──────────────────────────────────────────────────────────────┘
```

### 3. AI Cost Dashboard (:8180/finance/ai-costs)

```
┌──────────────────────────────────────────────────────────────┐
│ AI COST COMMAND                                       [LIVE] │
├──────────────────────────────────────────────────────────────┤
│ TODAY'S AI SPEND: $2.47           MONTH PROJECTED: $73.12    │
│ YESTERDAY: $2.31 (+6.9%)         BUDGET: $75.00 (97.5%)     │
├──────────────────────────────────────────────────────────────┤
│ SPEND BY MODEL (Today)        SPEND BY APPLICATION (Today)   │
│ ████████ DeepSeek Chat $0.82  ████████ SurplusAI    $0.92   │
│ ██████   Claude Sonnet $0.76  ██████   Agent Fleet  $0.68   │
│ ████     Claude Opus   $0.51  ████     PredRadar    $0.41   │
│ ███      Claude Haiku  $0.28  ███      FRG CRM      $0.32   │
│ █        DeepSeek Reas $0.10  █        Other        $0.14   │
├──────────────────────────────────────────────────────────────┤
│ EFFICIENCY METRICS                                           │
│ Prompt Cache Hit Rate:  73% ▲     Target: >70%     🟢       │
│ Cost per Agent Call:    $0.03     Target: <$0.05   🟢       │
│ Cost per $1 Revenue:    $0.06     Target: <$0.10   🟢       │
├──────────────────────────────────────────────────────────────┤
│ 🟡 P2: Claude Opus usage increased 40% this week            │
│ 🟢 Optimization: 3 prompts cached this week (+$4.20/mo est.)│
└──────────────────────────────────────────────────────────────┘
```

### 4. Profitability Dashboard (:8180/finance/profitability)

```
┌──────────────────────────────────────────────────────────────┐
│ PROFITABILITY COMMAND                                 [LIVE] │
├──────────────────────────────────────────────────────────────┤
│ P&L SUMMARY (Month to Date)                                  │
│ Revenue       $12,450  ████████████████████████████████      │
│ COGS          -$3,486  ██████████                            │
│ Gross Profit   $8,964  ██████████████████████████    72.0%   │
│ OpEx          -$6,230  ██████████████████                    │
│ Op Income     $2,734  ████████                       22.0%   │
│ Other           -$50  ▏                                      │
│ Net Income    $2,684  ████████                       21.6%   │
├──────────────────────────────────────────────────────────────┤
│ PER-PRODUCT MARGIN                    UNIT ECONOMICS         │
│ SurplusAI:    ████████████ 68% GM    ARPU:      $89/mo      │
│ PredRadar:    ██████████████ 78% GM   LTV:       $2,136      │
│ FRG CRM:      ██████████ 58% GM       CAC:       $480        │
│ Attny Mkt:    ████████████████ 85% GM LTV:CAC:   4.5:1       │
│ AI Ops:       ██████ 42% GM ⚠️        Payback:   5.4 mo      │
├──────────────────────────────────────────────────────────────┤
│ ⚠️ AI Ops margin below 50% target — investigate AI costs     │
└──────────────────────────────────────────────────────────────┘
```

### 5. KPI Command Center (:8180/finance/kpis)

```
┌──────────────────────────────────────────────────────────────┐
│ KPI COMMAND CENTER                                    [LIVE] │
├──────────────────────────────────────────────────────────────┤
│ REVENUE KPIs          │ GROWTH KPIs          │ UNIT ECONOMICS│
│ MRR:     $12,450  🟢  │ MoM Growth: 8.2%  🟢 │ LTV:CAC 4.5 🟢│
│ ARR:    $149,400  🟢  │ YoY Growth: 145%  🟢 │ Payback 5.4 🟢│
│ ARPU:       $89  🟡  │ Net New:  $1,240  🟢 │ CAE:    1.3  🟢│
│                        │ Quick Ratio: 4.8  🟢 │                 │
├────────────────────────┼─────────────────────┼─────────────────┤
│ RETENTION KPIs         │ EFFICIENCY KPIs     │ AI EFFICIENCY   │
│ Logo Churn: 1.8%  🟢  │ Gross Mgn: 72%   🟢 │ AI/$Rev: $0.06🟢│
│ Gross Churn:2.1%  🟢  │ Op Margin: 22%   🟢 │ AI/Task:  $0.03🟢│
│ Net Churn:-1.3%   🟢  │ Rule of 40: 38   🟡 │ Auto Rate: 67%🟡│
│ NDR:       108%   🟢  │ Burn Mult: 0.8   🟢 │                  │
│ GDR:        95%   🟢  │ Magic Num: 1.3   🟢 │                  │
├──────────────────────────────────────────────────────────────┤
│ COMPOSITE KPI HEALTH: 87/100 — 22 green, 4 yellow, 0 red    │
│ ⚠️ Rule of 40 at 38 (target 40) — focus on margin expansion │
└──────────────────────────────────────────────────────────────┘
```

---

## Technical Implementation

- **Framework**: Static HTML + auto-refreshing JavaScript
- **Data Source**: All 40 financial agents via curl/API
- **Refresh Rate**: Critical panels 5min, full dashboard 60min
- **Export**: PDF (board packages), CSV (analysis), PNG (quick shares)
- **Responsive**: Desktop-first, tablet-functional, phone-critical-only
- **Alerts**: WebSocket for real-time P0/P1 alert push

---

## Integration

- **Serves**: Executive Dashboard (:8180)
- **Design**: financial-dashboard agent
- **Data**: All 40 financial agents
- **Review**: AI CFO validates accuracy before display
