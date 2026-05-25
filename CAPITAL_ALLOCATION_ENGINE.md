# Wheeler Capital Allocation Engine
## ROI-Scored Investment Prioritization & Strategic Resource Deployment

**Date**: 2026-05-25
**Status**: Framework deployed — operational when revenue/capital available

---

## Engine Overview

The Capital Allocation Engine ranks every potential use of capital (time, money, attention) and produces a prioritized investment queue. No dollar is spent without being scored against alternatives.

---

## Investment Scoring Model

Every potential investment is scored on 6 dimensions (0-100):

| Dimension | Weight | What It Measures |
|-----------|--------|-----------------|
| ROI Potential | 25% | Expected financial return within 12 months |
| Strategic Value | 25% | Long-term competitive advantage created |
| Revenue Impact | 20% | Direct/indirect revenue generation |
| Operational Leverage | 15% | Efficiency gained (more output per input) |
| Risk Level | 10% | Inverse of execution/financial risk |
| Maintenance Burden | 5% | Ongoing cost to maintain (lower = better) |

### Decision Matrix

| Score Range | Decision | Action |
|-------------|----------|--------|
| 80-100 | STRONG BUY | Allocate immediately |
| 65-79 | BUY | Allocate when cash allows |
| 50-64 | HOLD | Reconsider next quarter |
| 35-49 | CAUTION | Only if strategic necessity |
| <35 | PASS | Do not allocate |

---

## Current Investment Queue (May 2026)

Ranked by urgency and ROI at Wheeler's current pre-revenue stage:

| Rank | Investment | Category | Cost | Score | Est. ROI |
|------|-----------|----------|------|-------|----------|
| 1 | Fix COREDB connection | Infrastructure | $0 | 95 | ∞ (unblocks FRG revenue) |
| 2 | Activate Stripe live mode | Growth | $0 | 92 | ∞ (enables all revenue) |
| 3 | Fix PipelineDAG (6 stages) | Operations | $0 | 88 | ∞ (unblocks 6,603 cases) |
| 4 | Fix 3 errored revenue PM2 | Infrastructure | $0 | 85 | High (enables metrics) |
| 5 | Right-size Docker containers | Infrastructure | $0 | 72 | $20-50/mo savings |
| 6 | Optimize AI model routing | AI/Tech | $0 | 70 | 30-60% AI cost reduction |
| 7 | Build dunning engine | Growth | Dev time | 60 | Churn reduction |
| 8 | Grafana revenue dashboards | Ops | Dev time | 55 | Revenue visibility |
| 9 | Apply for tech grants | Strategic | $0 | 50 | Non-dilutive capital |

---

## Capital Allocation by Business Stage

### Stage 1: Pre-Revenue (Current)
```
100% → Operating Business
  ├── 70% → Fix what's broken (COREDB, PipelineDAG, Stripe, PM2)
  ├── 20% → Build revenue-generating products
  └── 10% → Maintain existing infrastructure
```

### Stage 2: Early Revenue ($1K-$10K MRR)
```
80% → Operating Business (growth + optimization)
10% → Cash Reserve (build to 6 months)
10% → Founder (first distributions)
```

### Stage 3: Growth ($10K-$50K MRR)
```
60% → Operating Business
20% → Cash Reserve + External Investments
10% → Strategic (small acquisitions, partnerships)
10% → Founder distributions
```

### Stage 4: Scale ($50K+ MRR)
```
50% → Operating Business
30% → External Investments + Acquisitions
15% → Founder distributions
5% → Philanthropy / Legacy
```

---

## ROI Tracking Framework

Every investment tracked through its lifecycle:

```
Phase 1: PROPOSED
├── Investment thesis documented
├── Score assigned (Capital Allocation model)
├── Approval: AI CFO recommends, human approves

Phase 2: COMMITTED
├── Resources allocated
├── Success criteria defined
├── Timeline established

Phase 3: ACTIVE
├── 30-day check-in: on track?
├── 60-day check-in: early returns visible?
├── 90-day check-in: projected vs. actual ROI

Phase 4: COMPLETED
├── Actual ROI calculated
├── Lessons documented
├── Scoring model updated based on accuracy

Phase 5: TERMINATED (if applicable)
├── Why did it fail?
├── What would we do differently?
├── Sunk cost acknowledged, not chased
```

---

## Build vs. Buy Decision Framework

For each make-or-buy decision:

```
BUILD if:
├── Core to competitive advantage
├── Build cost < 1 year of subscription
├── Strategic control matters
└── No good off-the-shelf alternative exists

BUY if:
├── Not core to competitive advantage
├── Subscription < build cost / 12 months
├── Time-to-value is critical
└── Vendor is reliable and well-funded

PARTNER if:
├── Mutual benefit and aligned incentives
├── Faster than building, cheaper than buying
└── Partner brings capabilities we can't replicate
```

---

## Integration

- **Scoring Engine**: `capital-allocation.md` agent
- **ROI Tracking**: `roi-optimization.md` agent
- **Decision Authority**: AI CFO recommends → Human approves
- **Oversight**: `financial-governance.md` agent verifies compliance
- **Reporting**: Monthly capital allocation review → Board package
