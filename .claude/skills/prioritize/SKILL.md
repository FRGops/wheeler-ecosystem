---
name: prioritize
description: Wheeler Prioritization Engine — score tasks across 10 weighted dimensions (Revenue 25%, Leverage 20%, Automation 15%, Scalability 10%, Infra 10%, TTV 10%, Strategic 5%, Maint 3%, Complexity 1%, Alignment 1%). Detect distractions, low ROI, sprawl, duplicates. Manage the execution priority queue.
metadata:
  type: skill
  version: "1.0.0"
  author: Wheeler Brain OS
  tags:
    - prioritization
    - scoring
    - execution
    - planning
---

# Prioritization Engine

Deterministic 10-dimension scoring engine. Full design at `/root/PRIORITIZATION_ENGINE.md`.

## Subcommands

### `/prioritize task <description>`
Score a single task. Prompts for each dimension if not provided.

**Optional flags:** `--effort <hours>` `--revenue <1-10>` `--leverage <1-10>` `--automation <1-10>` `--scalability <1-10>` `--infra <1-10>` `--ttv <1-10>` `--strategic <1-10>` `--maint <1-10>` `--complexity <1-10>` `--alignment <1-10>`

**Algorithm:**
```
composite = (revenue × 0.25) + (leverage × 0.20) + (automation × 0.15)
          + (scalability × 0.10) + (infra × 0.10) + (ttv × 0.10)
          + (strategic × 0.05) + (maint × 0.03)
          + (complexity × 0.01) + (alignment × 0.01)
display = composite × 10
roi = composite / effort_hours × 100
```

**Tiers:** T1 (85-100) Execute Immediately | T2 (70-84) This Week | T3 (50-69) This Month | T4 (30-49) Next | T5 (0-29) Deferred

### `/prioritize list`
Show current priority queue sorted by display score.

### `/prioritize review`
Re-score all active tasks. Auto-demotes tasks sitting in tier >2x estimated TTV. Reports tier transitions.

### `/prioritize distractions`
Identify active distractions using heuristics (D1-D10). Shows static distraction rules (D5-D8) that are always flagged.

### `/prioritize matrix`
Show full prioritization matrix with all dimension scores, tier summary, category distribution, distraction summary, and low ROI tasks.

## Scoring Quick Reference

| Dimension | Weight | Fast Rule |
|-----------|--------|-----------|
| Revenue | 25% | $10K MRR=10, $1K=8, $0=1 |
| Leverage | 20% | 5+ unlocks=10, 1 unlock=6, none=2 |
| Automation | 15% | Full auto=10, partial=6, manual=2 |
| Scalability | 10% | 10x=10, linear=6, bottleneck=2 |
| Infrastructure | 10% | Fixes vuln=10, P2=8, adds=3 |
| Time-to-Value | 10% | <1h=10, 1d=7, 1wk=5 |
| Strategic | 5% | Moat=10, new market=9, neutral=3 |
| Maintenance | 3% | *INVERSE* Set/forget=10, daily=2 |
| Complexity | 1% | *INVERSE* Trivial=10, unknown=1 |
| Alignment | 1% | Core=10, neutral=6, contradicts=1 |

## Distraction Detection Rules

| Rule | Condition | Confidence |
|------|-----------|------------|
| D1 | Score < 30 AND effort > 4h | HIGH |
| D2 | Revenue ≤ 3 AND Leverage ≤ 3 AND Strategic ≤ 3 | HIGH |
| D5 | Research without adoption trigger | HIGH |
| D6 | New agents (53 exist, 0 registered) | HIGH — HARD BLOCK |
| D7 | New infra (utilization < 70%) | HIGH — HARD BLOCK |
| D10 | Effort > 40h AND Revenue ≤ 5 AND Leverage ≤ 5 | HIGH |

## Persistence

Queue state: `/root/.prioritization/queue.json`
Score history: `/root/.prioritization/history.jsonl`
Worksheets: `/root/.prioritization/worksheets/`
