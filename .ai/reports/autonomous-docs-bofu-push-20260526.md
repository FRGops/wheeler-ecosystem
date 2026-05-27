# Autonomous Docs -- BOFU Content Push Handoff

**Date:** 2026-05-26
**Agent:** autonomous-docs
**Trigger:** Growth Engine qualified-to-retained funnel dropoff (77.5%) -- growth-orchestrator recommended 2-3 BOFU case study pages

---

## Action Summary

| Item | Before | After | Delta |
|------|--------|-------|-------|
| Inventory pages | 10 | 13 | +3 |
| Pipeline total | 69 | 72 | +3 |
| BOFU mix | 20% | 22% | +2pp |
| Funnel mix (T/M/B) | -- | 47/31/22 | Set |
| case_spotlights pillar | 1 | 4 | +3 |

## Content Items Added

### 1. $425K NY Surplus Recovery: From Filing to Check in 47 Days
- **URL:** `/case/ny-surplus-425k-recovery`
- **Type:** case_study | **Funnel:** BOFU
- **Keyword:** surplus funds recovery success stories
- **Status:** drafting | **Priority:** high
- **Pillar:** case_spotlights

### 2. From Lead to Claim: A 30-Day Surplus Funds Timeline
- **URL:** `/case/lead-to-claim-30-day-timeline`
- **Type:** case_study | **Funnel:** BOFU
- **Keyword:** how long does surplus funds claim take
- **Status:** briefed | **Priority:** high
- **Pillar:** case_spotlights

### 3. How One Attorney Recovered $1.2M Across 14 Foreclosure Cases
- **URL:** `/case/attorney-1.2m-14-cases`
- **Type:** case_study | **Funnel:** BOFU
- **Keyword:** attorney surplus funds case study
- **Status:** briefed | **Priority:** medium
- **Pillar:** case_spotlights

## Metrics Updated

| Metric | Value |
|--------|-------|
| Pipeline total | 72 |
| BOFU mix pct | 22% |
| Funnel mix TOFU | 47% |
| Funnel mix MOFU | 31% |
| Funnel mix BOFU | 22% |

## Pipeline Status

The 3 new case studies are in pipeline stages (drafting/briefed) and need progression through:
1. **Drafting** (item 1) -- ready for writing assignment
2. **Briefed** (items 2, 3) -- need content brief expansion, then drafting
3. All three target BOFU conversion keywords intended to address the 77.5% qualified-to-retained dropoff

## API Endpoints Used

- `GET http://localhost:8180/api/v1/content/inventory` -- read current state (10 pages, 20% BOFU)
- `PUT http://localhost:8180/api/v1/content/data` -- write updated inventory + metrics (13 pages, 22% BOFU)

## Verification

Inventory confirmed post-write: 13 pages, 4 case_spotlights (was 1), all 3 new items present with correct metadata. Metrics stored server-side.
