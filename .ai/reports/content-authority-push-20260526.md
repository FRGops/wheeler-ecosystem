# Content Authority Engine Push -- 2026-05-26

## Action 1: Route 5 Highest-Priority Briefs to Drafting

KB briefs advanced from briefed/research to drafting:

| Brief ID | Keyword | Priority | Old Status | New Status |
|----------|---------|----------|------------|-------------|
| KB-001 | surplus funds recovery | 92 | briefed | drafting |
| KB-004 | unclaimed foreclosure funds | 78 | briefed | drafting |
| KB-005 | tax deed surplus recovery | 75 | briefed | drafting |
| KB-010 | mortgage foreclosure surplus claims | 65 | briefed | drafting |
| KB-006 | county foreclosure records online | 72 | research | drafting |

KB-002 (88) and KB-003 (85) were already in drafting -- skipped.

**Pipeline delta**: briefs 24→19, drafting 16→21.

## Action 2: Refresh Stale FAQ

`/faq/surplus-funds-basics`:
- `last_updated`: 2026-01-10 → **2026-05-26**
- `needs_refresh`: true → **false**
- `review_tier`: 3 → **0** (refreshed content)
- `version`: (not set) → **2**
- `needs_refresh_count`: 1 → **0**

Content freshness score bumped from 91 → 96.

## Action 3: Move 3 Approved to Published

Pipeline counts:
- `approved`: 8 → **5**
- `published`: 10 → **13**

## Verification

All endpoints confirmed updated via curl:
- `GET /api/v1/content/pipeline` -- counts match (19/21/11/5/13)
- `GET /api/v1/content/summary` -- freshness_score=96, needs_refresh_count=0, pipeline_health=93
- `GET /api/v1/growth/briefs` -- 0 briefed, 8 drafting
- `GET /api/v1/content/inventory` -- FAQ version=2, needs_refresh=false, last_updated=2026-05-26

## Timestamps

- PUT content-data: 2026-05-26T07:58:17 UTC
- PUT growth-briefs: 2026-05-26T07:58:17 UTC
