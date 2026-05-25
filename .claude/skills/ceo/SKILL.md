---
name: ceo
description: CEO Command Console — daily brief, morning routine, end-of-day review, weekly/monthly cadence, emergency mode, decision framework for the Wheeler ecosystem operator
metadata:
  type: skill
  version: "1.0.0"
  author: Wheeler Brain OS
  tags:
    - executive
    - operations
    - decision
    - cadence
---

# CEO Operating System

The daily/weekly/monthly/quarterly operating cadence for running the Wheeler ecosystem. Full operating system at `/root/CEO_OPERATING_SYSTEM.md`.

## Subcommands

### `/ceo brief`
2-minute executive brief. Fastest way to get the ecosystem pulse.

**Output:** Health score, revenue status, active alerts, top 3 priorities, blocker count.

### `/ceo daily`
Full morning routine (30 min).

**Process:**
1. Ecosystem health check (Docker, PM2, revenue, alerts)
2. AI Chief of Staff briefing review
3. Revenue pulse (MRR, leads, transactions)
4. Blocker scan
5. Day planning — confirm top 3 priorities

### `/ceo eod`
End of day review (10 min).

**Process:**
1. What got done today
2. What moved forward on revenue
3. What's blocked for tomorrow
4. Agent task completion report
5. Quick health check

### `/ceo weekly [planning|review]`
Weekly operating cadence.

- `planning` (Monday): Full ecosystem audit, weekly priorities, revenue review, sprint kickoff
- `review` (Friday): Deployments shipped, metrics review, retrospective, next week preview

### `/ceo monthly`
Monthly strategy review.

**Process:**
1. Revenue trend analysis
2. Product roadmap check
3. Infrastructure capacity planning
4. Agent fleet audit
5. Cost optimization review
6. Next month priorities

### `/ceo decide <topic>`
Decision framework for a specific topic.

**Process:**
1. Classify decision type (revenue, security, architecture, product, operations)
2. Apply relevant framework:
   - Revenue: Impact × Probability × Time-to-revenue
   - Security: Risk × Exposure × Mitigation cost
   - Architecture: Leverage × Maintenance × Lock-in risk
   - Product: Market size × Build cost × Strategic fit
3. Recommend with confidence level
4. Document decision + rationale

### `/ceo emergency`
Enter emergency mode.

**Triggers:** Revenue down >10%, primary SaaS unreachable, security breach, data loss, payment failure.

**Process:**
1. Acknowledge — drop all non-emergency work
2. Triage — classify severity and scope
3. Assign — route to best agent + human oversight
4. Track — real-time status updates
5. Resolve — verify fix, document root cause
6. Exit — post-mortem, return to normal cadence

## Emergency Mode Triggers
| Condition | Severity | Response |
|-----------|----------|----------|
| Revenue down >10% DoD | P1 | Immediate — all hands |
| Prediction Radar unreachable | P1 | Immediate — 4h SLA |
| Security breach detected | P0 | Immediate — isolate + investigate |
| Data loss event | P0 | Immediate — restore from backup |
| Payment processing failure | P1 | Immediate — 2h SLA |
| COREDB/AIOPS server down | P1 | Immediate — 4h SLA |

## Decision Delegation Matrix

| Decision Type | AI Agent Can Recommend | Human Must Decide |
|--------------|----------------------|-------------------|
| Routine health checks | Yes — automated | No |
| Standard deployments | Yes — deploy agent | No (if gates pass) |
| Security trade-offs | No | Yes — always |
| Pricing changes | No | Yes — always |
| Architecture changes | Advisory only | Yes |
| Product direction | Advisory only | Yes |
| Emergency incident | Triage + assign | Yes — P0/P1 only |
| Code review | Yes | Spot check |

## Energy Management

**High-energy blocks (do these when fresh):** Strategic decisions, product architecture, revenue strategy, complex debugging, security architecture.

**Low-energy blocks (do these when tired):** Documentation review, health checks, routine deployments, code review, monitoring review.

**Never do these (delegate to AI):** Routine health verification (use /slay), log scanning (Loki + agents), metric collection (Prometheus + agents), backup verification (cron + agents).
