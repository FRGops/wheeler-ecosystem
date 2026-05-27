# PM2 Restart Root Cause Fix

**Date:** 2026-05-27
**Report:** 25-pm2-restart-root-cause-fix
**Severity:** P1 (2 processes crash-looping, all 4 now stable)

---

## Problem 1 (CRITICAL): ravynai-og-scheduler (10 restarts) + ravynai-og-sync (4 restarts)

### Root Cause

Two compounding issues:

**Issue A -- Wrong DATABASE_URL (PRIMARY ROOT CAUSE)**

The shared env file at `/opt/apps/.env.shared` defines a global `DATABASE_URL` pointing to the COREDB `wheeler_core` database:
```
DATABASE_URL=postgresql://wheeler:4be38d4d3...@100.118.166.117:5432/wheeler_core
```

The PM2 wrapper script (`/opt/wheeler-ecosystem/scripts/pm2-env-wrapper.sh`) loads this shared file FIRST and skips vars that are already set. Since the ravynai-og ecosystem configs did NOT define a `DATABASE_URL` in their `env:` block, the shared file's DATABASE_URL was loaded instead of the app-local `.env` value (`postgresql://ravynai:ravynai@postgres:5432/ravynai`).

This caused both processes to connect to the **wrong database** (COREDB `wheeler_core` instead of the local PostGIS `ravynai` database on port 5434).

**Issue B -- Missing database schema (SECONDARY)**

The correct ravynai database (`aiops-ravynai-postgres` at 127.0.0.1:5434) had **never received Prisma migrations**. The `properties` table -- and all other application tables -- did not exist. Only PostGIS/Tiger geocoder extension tables were present (37 tables across `public`, `tiger`, `topology` schemas).

The Prisma client was generated from a schema that expects `createdAt` on the `properties` table, but the table itself never existed in the database.

### Fix Applied

1. **PostgreSQL listen_addresses fix:** Changed from `localhost` to `*` via `ALTER SYSTEM SET listen_addresses = '*'` and restarted the container (`docker restart aiops-ravynai-postgres`) so the database accepts TCP connections from outside the container.

2. **Prisma database push:** Ran `prisma db push --accept-data-loss --skip-generate` against the correct database, creating all 24 application tables (`properties`, `property_owners`, `mailing_addresses`, `assessment_records`, `sale_records`, `mortgage_records`, `lien_records`, `tax_records`, `foreclosure_events`, `tax_sale_events`, `court_cases`, `court_registry_funds`, `permit_records`, `code_violations`, `opportunity_signals`, `strategy_scores`, `leads`, `county_sources`, `ingestion_runs`, `data_quality_issues`, `audit_logs`, `source_freshness`, and relation tables).

3. **Ecosystem config DATABASE_URL override:** Added explicit `DATABASE_URL` to the `env:` block of both `ravynai-og-scheduler` and `ravynai-og-sync` in `/opt/apps/ravynai-opportunity-graph/ecosystem.config.js`:
   ```javascript
   env: {
     NODE_ENV: "production",
     INTERVAL_MS: "3600000",
     DATABASE_URL: "postgresql://ravynai:ravynai@127.0.0.1:5434/ravynai",
   },
   ```
   This ensures the PM2 wrapper skips the shared env's `DATABASE_URL` since it's already set.

4. **PM2 delete+start:** Used `pm2 delete` + `pm2 start` (not `restart`) to clear cached environment variables and load fresh config.

### Verification

- **ravynai-og-scheduler** (PID 181): `Pipeline run completed successfully {"durationMs":148,"totalRuns":1}` at 05:32:18 UTC. Zero pipeline errors. Zero restarts since fix.
- **ravynai-og-sync** (PID 182): `Sync cycle completed successfully {"durationMs":111,"consecutiveFailures":0}` at 05:32:19 UTC. The `createdAt` error is gone. The only remaining error is `FRGCRM sync errors: 1` from the existing `ra_properties` table issue in the FRGCRM upstream -- a separate concern that does not cause crash-looping.

---

## Problem 2 (MEDIUM): executive-dashboard-api (11 restarts)

### Assessment: STABLE, No Active Issue

- Current uptime: **20 hours** (created 2026-05-26 08:34 UTC)
- Error log: **Empty** -- no errors recorded
- Out log: Normal HTTP 200 responses for `/health` and `/` endpoints
- Current status: Online, 0 unstable restarts

The 11 restarts occurred during the initial 1-2 hours after deploy (~21 hours ago). The process has been running cleanly for the past 20 hours with no crashes, errors, or log anomalies. No action required.

---

## Problem 3 (LOW): frgcrm-api (2 restarts)

### Assessment: STABLE, No Active Issue

- Current uptime: **20 hours** (created 2026-05-26 08:49 UTC)
- Error log: Contains SQLAlchemy connection pool timeouts (`surplusai_cursor_lookup_failed`) -- transient connection issues to the external SurplusAI system. These are handled gracefully by the application (jobs still report "executed successfully").
- Out log: Normal HTTP 200 responses for API endpoints
- Current status: Online, 0 unstable restarts

The 2 restarts occurred during the initial deploy window. The process is handling API requests and background jobs normally. The `surplusai_cursor_lookup_failed` warnings are application-level issues related to an external dependency being unavailable, not a crash-loop condition.

---

## Summary

| Process | Previous Restarts | Current Status | Root Cause |
|---------|-------------------|---------------|------------|
| ravynai-og-scheduler | 10 | Online (0 since fix) | Wrong DATABASE_URL + missing schema |
| ravynai-og-sync | 4 | Online (0 since fix) | Wrong DATABASE_URL + missing schema |
| executive-dashboard-api | 11 | Online (stable 20h) | Old startup issues, now stable |
| frgcrm-api | 2 | Online (stable 20h) | Transient connection issues, now stable |

All 4 processes are now online and stable with 0 active restarts.

## Files Modified
- `/opt/apps/ravynai-opportunity-graph/ecosystem.config.js` -- Added `DATABASE_URL` to ravynai-og-scheduler and ravynai-og-sync env blocks

## System Changes
- Postgres listen_addresses changed from `localhost` to `*` (ALTER SYSTEM + container restart)
- Prisma db push created 24 application tables in ravynai database
- PM2 process list saved (`pm2 save`)
