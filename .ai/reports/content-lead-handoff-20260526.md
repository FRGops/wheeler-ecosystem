**Agent**: content-lead
**Status**: active
**Cycle**: daily
**Pipeline**: [24] briefs → [16] drafting → [11] in review → [8] approved → [5] published
**SLA Health**: [90.6%] — [3] stages exceeding SLA
**Pillar Balance**: surplus_funds (3), foreclosure_guides (2), legal_education (1), data_studies (1), case_spotlights (1), faq_hubs (1), industry_news (1) — Pillar Balance Score: 88/100
**Review Gates**: Tier 0 [2], Tier 1 [5], Tier 2 [1], Tier 3 [2], Tier 4 [0]
**Content Refresh**: [1] pages flagged, [0] updated this cycle
**Bottlenecks**: 
  - Briefs (SLA 24h): 2 overdue — delay at top of funnel causes cascading slides downstream
  - Drafting (SLA 48h): 2 overdue — drafting throughput below target; avg time-to-publish trending at 8.4 days
  - In Review (SLA 72h): 2 overdue — review queue at 11 deep with 2 past SLA; consider parallel reviewer deployment
  - Total overdue: 6 items across 3 stages

**Escalations**:
  - `/faq/surplus-funds-basics` needs refresh — published 2025-11-20, last updated 2026-01-10 (6 months since last update, 18 months since publish). Currently Tier 3, TOFU, low conversions (2/30d). Recommend assign to drafting queue this cycle.
  - metrics/content_refresh_queue discrepancy — metrics endpoint reports refresh queue of 3, but inventory endpoint flags only 1 page with `needs_refresh: true`. Audit needed to reconcile the gap.
  - published count mismatch — pipeline shows 5 in published stage vs. summary reports 10 total published. Likely 5 pre-pipeline published assets; verify inventory completeness.

**EEAT Compliance**: 98.5% — within threshold (target >98%)
**Fact Check Pass Rate**: 96.2% — within threshold (target >95%)
**Review Gate Compliance**: 100% — all gates passing
**Pipeline Velocity**: 5.2 pages/week
**Avg Time to Publish**: 8.4 days
**Funnel Mix**: TOFU 48% / MOFU 32% / BOFU 20% — healthy BOFU conversion-to-content ratio (BOFU pages avg 13.5 conversions/30d vs. TOFU avg 4.3)
**Freshness Score**: 91/100
**Pipeline Health**: 87/100
