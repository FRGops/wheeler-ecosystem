# PHASE 4 -- POSTGRES OPTIMIZATION PLAN

**Generated:** 2026-05-23
**Scope:** All PostgreSQL instances across Wheeler ecosystem (2 servers, 4 containers)
**Status:** READ-ONLY AUDIT -- configurations generated, no databases modified

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [System Profiles](#system-profiles)
3. [Instance: wheeler-postgres (COREDB)](#instance-wheeler-postgres-coredb)
4. [Instance: frgops-standby (AIOPS)](#instance-frgops-standby-aiops)
5. [Instance: prediction-radar-app-db (AIOPS)](#instance-prediction-radar-app-db-aiops)
6. [Instance: aiops-ravynai-postgres (AIOPS)](#instance-aiops-ravynai-postgres-aiops)
7. [Cross-Instance Recommendations](#cross-instance-recommendations)
8. [Generated Artifacts](#generated-artifacts)

---

## Executive Summary

| Instance | Server | Status | Criticality |
|---|---|---|---|
| wheeler-postgres | 5.78.210.123 | Stock defaults, nearly empty DB | LOW |
| frgops-standby | 5.78.140.118 | Well-tuned, good config | LOW |
| prediction-radar-app-db | 5.78.140.118 | Stock defaults, 400+ unused indexes, seq scans on 20+ tables | **HIGH** |
| aiops-ravynai-postgres | 5.78.140.118 | Stock defaults, old version (16.4), PostGIS overhead | MEDIUM |

**Top 3 Critical Findings:**

1. **prediction-radar-app-db runs on 100% stock PostgreSQL 16 defaults** with 128 MB shared_buffers on a 30 GB server. Over 400 indexes have zero scans (bloat). Twenty-plus tables experience sequential scans with zero index usage. Five connections are stuck in "idle in transaction" state -- a likely application transaction leak.

2. **None of the 4 instances have pg_stat_statements installed.** This is the single most important extension for query performance analysis. Without it, slow query identification is blind.

3. **No connection pooling exists anywhere.** All 4 instances accept direct application connections with max_connections=100. On AIOPS with 3 PostgreSQL containers sharing 30 GB RAM, this risks memory exhaustion under load.

---

## System Profiles

### COREDB Server (5.78.210.123)

| Resource | Value |
|---|---|
| Total RAM | 30 GB (24 GB free, 5.7 GB buff/cache) |
| Swap | None |
| CPU Cores | 16 |
| Disk | 338 GB SSD (/dev/sda1), 2% used (6.2 GB) |
| Containers | wheeler-postgres (sole PG instance) |

### AIOPS Server (5.78.140.118)

| Resource | Value |
|---|---|
| Total RAM | 30 GB (17 GB used, 3.3 GB free, 15 GB buff/cache) |
| Available RAM | 13 GB |
| Swap | 8 GB (512 KB used) |
| CPU Cores | 16 |
| Disk | 338 GB SSD (/dev/sda1), 16% used (52 GB) |
| Docker PG memory | aiops-ravynai-postgres: 21.8 MiB / 30.6 GiB |
| PG Containers | frgops-standby, prediction-radar-app-db, aiops-ravynai-postgres (3 total) |

**Critical Note:** AIOPS runs THREE PostgreSQL instances sharing 30 GB RAM. The combined shared_buffers budget must be coordinated. Currently: frgops-standby uses 1 GB, the other two use 128 MB each = 1.25 GB total. The server has 13 GB available, so there is headroom, but it must be allocated intentionally.

---

## Instance: wheeler-postgres (COREDB)

### Audit Summary

| Metric | Value |
|---|---|
| PostgreSQL Version | 16.14 (Debian) |
| Database | wheeler_core |
| DB Size | 7,519 kB (nearly empty) |
| Total Connections | 6 (1 active, 5 idle) |
| User Tables | None with data |
| Cache Hit Ratio | 98.77% (database level) |
| pg_stat_statements | NOT INSTALLED |

### Current Configuration vs. Recommended

| Parameter | Current | Recommended | Rationale |
|---|---|---|---|
| shared_buffers | 128 MB | 7.5 GB | 25% of 30 GB RAM (sole PG instance on host) |
| work_mem | 4 MB | 32 MB | Conservative for expected OLTP workload |
| maintenance_work_mem | 64 MB | 512 MB | Speed up VACUUM/REINDEX when data grows |
| effective_cache_size | 4 GB | 22 GB | 75% of RAM for query planner |
| max_connections | 100 | 50 | Reduce with PgBouncer; 100 is wasteful for 0-6 active conns |
| random_page_cost | 4.0 | 1.1 | SSD storage |
| effective_io_concurrency | 1 | 200 | SSD storage |
| max_wal_size | 1 GB | 4 GB | Reduce checkpoint frequency |
| min_wal_size | 80 MB | 1 GB | Match typical WAL footprint |
| checkpoint_timeout | 5 min | 15 min | Reduce checkpoint I/O spikes |
| wal_buffers | 4 MB (512*8KB) | 16 MB | Standard recommendation for 16.0+ |
| wal_compression | off | on | Reduce WAL I/O |
| idle_in_transaction_session_timeout | 0 (disabled) | 300000 (5 min) | Kill abandoned transactions |
| log_min_duration_statement | -1 (off) | 1000 (1 sec) | Log slow queries |
| track_io_timing | off | on | Required for pg_stat_statements I/O timing |
| shared_preload_libraries | (empty) | pg_stat_statements | Enable slow query analysis |

### WAL / Checkpoint Analysis

```
checkpoints_timed: 397   checkpoints_req: 2
buffers_checkpoint: 965  buffers_clean: 0    buffers_backend: 304
stats_reset: 2026-05-21 22:05  (reset ~2 days ago)
```

- checkpoints_req = 2 vs 397 timed: Excellent ratio. No forced checkpoints indicating WAL pressure.
- buffers_backend (304) vs buffers_checkpoint (965): Moderate backend writes. With actual workload this will increase.
- Stats recently reset; longer observation window needed.

### Vacuum State

No tables with > 1000 dead tuples. Database is effectively empty. Vacuum is healthy but irrelevant at this scale.

### Recommendations

1. **Immediately:** Install pg_stat_statements extension and enable in shared_preload_libraries.
2. **Apply optimized-postgresql.conf** for SSD tuning (25% RAM shared_buffers, cost parameters).
3. **When data grows:** Deploy PgBouncer for connection pooling.
4. **No index work needed** -- database has no user tables with data.

---

## Instance: frgops-standby (AIOPS)

### Audit Summary

| Metric | Value |
|---|---|
| PostgreSQL Version | 16.14 (Alpine) |
| Main Database | frgops |
| Databases | postgres (7 MB), frgops (7.6 MB), template1 (7.2 MB), temporal (15 MB), temporal_visibility (26 MB), frgcrm (18 MB), ravynai (8.6 MB), surplusai (7.2 MB) |
| Total DB Size | ~90 MB across all databases |
| Total Connections | 4 (1 active, 3 idle) |
| User Tables with data | surplusai_* (4 tables, all with 0 n_live_tup -- effectively empty) |
| Cache Hit Ratio | N/A (0 heap reads/hits -- no user table I/O) |
| pg_stat_statements | NOT INSTALLED |

### Current Configuration vs. Recommended

| Parameter | Current | Recommended | Rationale |
|---|---|---|---|
| shared_buffers | 1 GB | 1 GB | Already correct (~25% of available RAM allocation for 3-container host) |
| work_mem | 32 MB | 32 MB | Already correct for OLTP |
| maintenance_work_mem | 256 MB | 512 MB | Minor bump for future VACUUM operations |
| effective_cache_size | 3 GB | 3 GB | Already correct |
| random_page_cost | 1.1 | 1.1 | Already SSD-optimized |
| effective_io_concurrency | 200 | 200 | Already SSD-optimized |
| max_wal_size | 4 GB | 4 GB | Already correct |
| min_wal_size | 1 GB | 1 GB | Already correct |
| checkpoint_timeout | 5 min | 15 min | Reduce checkpoint frequency |
| wal_compression | off | on | Reduce WAL I/O |
| idle_in_transaction_session_timeout | 0 (disabled) | 300000 (5 min) | Kill abandoned transactions |
| log_min_duration_statement | -1 (off) | 1000 | Log slow queries |
| track_io_timing | off | on | Required for I/O timing |
| shared_preload_libraries | (empty) | pg_stat_statements | Enable slow query analysis |

### WAL / Checkpoint Analysis

```
checkpoints_timed: 11815  checkpoints_req: 2
buffers_checkpoint: 807,973  buffers_clean: 536  buffers_backend: 8,543
stats_reset: 2026-05-21 02:05
```

- Stats not reset since ~2 days. 11,815 timed checkpoints in that window at 5-min intervals = ~41 days of uptime. Good.
- checkpoints_req = 2: Nearly zero WAL pressure. Excellent.
- High buffers_backend (8,543): Significant direct backend writes bypassing the background writer. Consider bumping bgwriter_delay or reducing bgwriter_lru_maxpages.
- 536 buffers_clean vs 807,973 buffers_checkpoint: Background writer is underutilized. Tune bgwriter settings.

### Unused Indexes

7 unused indexes found, all on surplusai_* tables which have 0 live tuples:

```
surplusai_claim_scores: surplusai_claim_scores_case_id_model_name_key, surplusai_claim_scores_pkey
surplusai_models: surplusai_models_pkey, surplusai_models_model_name_version_key
surplusai_outcomes: surplusai_outcomes_case_id_actual_outcome_key, surplusai_outcomes_pkey
surplusai_scores_log: surplusai_scores_log_pkey
```

Tables are empty (0 n_live_tup). These indexes were created by DDL but tables never populated. No action needed -- if tables remain unused long-term, consider dropping them entirely.

### Recommendations

1. **Best-configured instance in the fleet.** Only minor tuning needed.
2. Install pg_stat_statements extension.
3. Tune bgwriter: reduce `bgwriter_delay` from 200ms to 100ms, increase `bgwriter_lru_maxpages` from 100 to 400.
4. Increase checkpoint_timeout from 5 min to 15 min.
5. Enable wal_compression.
6. If surplusai_* tables are permanently unused, drop them to reduce catalog bloat.

---

## Instance: prediction-radar-app-db (AIOPS)

### Audit Summary

| Metric | Value |
|---|---|
| PostgreSQL Version | 16.13 (Debian) |
| Database | prediction_radar |
| DB Size | 18 MB |
| Total Connections | 8 (1 active, 2 idle, **5 idle in transaction**) |
| User Tables | 130+ tables across public schema |
| Cache Hit Ratio | 94.71% |
| pg_stat_statements | NOT INSTALLED |

### CRITICAL: 5 Connections in "idle in transaction" State

This is a **transaction leak**. Connections stuck in "idle in transaction" hold locks and prevent VACUUM from cleaning dead tuples. The application creating these connections is not properly committing or rolling back transactions.

**Root Cause Investigation Needed:**
- Check application connection pool configuration
- Verify all code paths call COMMIT/ROLLBACK
- Add idle_in_transaction_session_timeout as safety net

### Top Tables with Sequential Scans (20 tables, ALL with idx_scan=0)

| Table | Seq Scans | Index Scans | Live Tuples | Notes |
|---|---|---|---|---|
| strategy_run_log | 135 | 0 | 0 | No data, but 135 seq scans. App queries empty table repeatedly. |
| market_snapshots | 48 | 0 | 0 | Same pattern |
| compliance_assessments | 7 | 0 | 0 | Same pattern |
| today_picks | 7 | 0 | 0 | Same pattern |
| signal_events | 6 | 0 | 0 | Same pattern |
| probability_assessments | 6 | 0 | 0 | Same pattern |
| historical_outcome_records | 6 | 0 | 0 | Same pattern |
| decision_evaluations | 6 | 0 | 0 | Same pattern |
| review_queue_items | 6 | 0 | 0 | Same pattern |
| restricted_market_rules | 5 | 4 | 4 | Mixed -- some index use |
| agent_registry | 5 | 30 | 15 | Good -- index used, 6:1 ratio |
| resolution_truth_records | 5 | 0 | 0 | Empty table, repeated seq scans |
| causal_events | 5 | 0 | 0 | Same |
| agent_outputs | 5 | 0 | 0 | Same |
| pnl_ledger | 5 | 0 | 0 | Same |
| trade_opportunities | 5 | 0 | 0 | Same |
| invites | 5 | 0 | 0 | Same |
| agent_runs | 5 | 0 | 0 | Same |
| anomaly_events | 5 | 0 | 0 | Same |
| ops_search_index | 5 | 0 | 0 | Same |

**Pattern:** Nearly all tables have n_live_tup=0 (empty). The application is running queries against empty tables, producing sequential scans. This is not a missing-index problem -- it is an **application query pattern problem**. The app queries tables that have no data. When data does exist (agent_registry: 15 live tuples), the index IS used (30 idx scans vs 5 seq scans).

### Unused Indexes -- MASSIVE FINDING

**Over 490 indexes have idx_scan = 0.** Every table in the database has all of its indexes showing zero scans. Key examples:

| Table | Indexes with 0 Scans |
|---|---|
| agent_outputs | 5 indexes (pkey + 4 functional) |
| agent_runs | 5 indexes |
| anomaly_events | 5 indexes |
| compliance_assessments | 7 indexes |
| historical_outcome_records | 6 indexes |
| market_correlations | 5 indexes |
| pnl_ledger | 5 indexes |
| probability_assessments | 6 indexes |
| strategy_run_log | 7 indexes |
| today_picks | 7 indexes |
| trade_decision_audit | 4 indexes |
| ...and 100+ more tables | 2-7 indexes each |

**Total: 490+ unused indexes.** Given the database is 18 MB total, the index overhead itself may exceed the data size. These indexes:
- Slow down INSERT/UPDATE/DELETE operations
- Consume shared_buffers memory
- Increase WAL volume during writes
- Extend VACUUM and ANALYZE time
- Slow down backup/restore

**Recommendation:** This is not a "drop all unused indexes" situation. These may be pre-created DDL indexes for an application that is not yet actively writing data. Instead:
1. Identify which tables are actively being written to
2. Keep indexes on actively-written tables
3. Consider dropping indexes on tables with both 0 n_live_tup AND 0 idx_scan, if the table is confirmed unused
4. Monitor over 2+ weeks before dropping

### Table Bloat

| Table | Live Tuples | Dead Tuples | Dead % | Total Size |
|---|---|---|---|---|
| skill_registry | 7 | 7 | 50.00% | 64 kB |
| deployment_log | 2 | 1 | 33.33% | 32 kB |

skill_registry has 50% dead tuples. A manual VACUUM ANALYZE on this table is warranted. All other tables are clean.

### Current Configuration vs. Recommended

**This instance is running 100% stock PostgreSQL 16 defaults.** This is a critical finding.

| Parameter | Current (Stock) | Recommended | Rationale |
|---|---|---|---|
| shared_buffers | 128 MB | 2 GB | 15% of host RAM allocated for this instance (3 containers on 30 GB) |
| work_mem | 4 MB | 32 MB | Standard OLTP recommendation |
| maintenance_work_mem | 64 MB | 512 MB | Speed up VACUUM/REINDEX on 130+ tables |
| effective_cache_size | 4 GB | 6 GB | Conservative for query planner on 30 GB host |
| random_page_cost | 4.0 | 1.1 | SSD storage |
| effective_io_concurrency | 1 | 200 | SSD storage |
| max_connections | 100 | 50 | Reduce; 8 actual conns observed |
| max_wal_size | 1 GB | 4 GB | Reduce checkpoint frequency |
| min_wal_size | 80 MB | 1 GB | Match WAL footprint |
| checkpoint_timeout | 5 min | 15 min | Reduce checkpoint I/O |
| max_parallel_workers_per_gather | 2 | 4 | Use more CPU for parallel queries |
| max_parallel_workers | 8 | 8 | Already correct |
| wal_compression | off | on | Reduce WAL I/O |
| idle_in_transaction_session_timeout | 0 (disabled) | 300000 (5 min) | **CRITICAL** -- kill abandoned txns |
| log_min_duration_statement | -1 (off) | 1000 | Log slow queries |
| track_io_timing | off | on | Required for query analysis |
| shared_preload_libraries | (empty) | pg_stat_statements | Enable slow query analysis |
| default_statistics_target | 100 | 200 | Better query plans for complex schema (130+ tables) |

### WAL / Checkpoint Analysis

```
checkpoints_timed: 3,815  checkpoints_req: 2
buffers_checkpoint: 87,732  buffers_clean: 128  buffers_backend: 2,188
stats_reset: 2026-05-10 09:07 (13 days ago)
```

- 3,815 timed checkpoints at 5-min intervals = ~13.2 days, matches stats_reset.
- checkpoints_req = 2 out of 3,815: Excellent.
- buffers_backend (2,188) vs buffers_checkpoint (87,732): Backend writes are ~2.5% of checkpoints. Normal.
- buffers_clean = 128: Background writer is almost entirely idle. Tune bgwriter to reduce checkpoint I/O spikes.

### Recommendations (Priority Order)

1. **CRITICAL:** Set `idle_in_transaction_session_timeout = 300000` to kill the 5 abandoned transactions.
2. **CRITICAL:** Investigate application code for transaction leak causing "idle in transaction" connections.
3. **HIGH:** Apply full SSD-optimized config (shared_buffers, random_page_cost, effective_io_concurrency).
4. **HIGH:** Install pg_stat_statements.
5. **MEDIUM:** VACUUM ANALYZE skill_registry table (50% bloat).
6. **MEDIUM:** Enable wal_compression and tune checkpoint_timeout.
7. **LOW:** Audit and potentially drop unused indexes after 2-week monitoring period.
8. **LOW:** Tune default_statistics_target to 200 for the 130+ table schema.

---

## Instance: aiops-ravynai-postgres (AIOPS)

### Audit Summary

| Metric | Value |
|---|---|
| PostgreSQL Version | **16.4** (Debian) -- OLD, 10 minor versions behind |
| Database | ravynai |
| DB Size | 19 MB (+ template_postgis 19 MB) |
| Extensions | PostGIS (tiger, topology schemas present) |
| Total Connections | 6 (1 active, 5 idle) |
| User Tables | spatial_ref_sys (PostGIS) + PostGIS tiger geocoder tables |
| Cache Hit Ratio | 96.11% |
| pg_stat_statements | NOT INSTALLED |

### Version Gap

PostgreSQL 16.4 was released August 2024. Current is 16.14. This instance is missing:
- Multiple security fixes (CVE-2024-10976 through CVE-2025-XXXX)
- Performance improvements in VACUUM, parallel query, and WAL
- Memory leak fixes
- Logical replication improvements

**Recommendation:** Upgrade container image to postgres:16.14.

### Sequential Scans (Tiger Geocoder)

All sequential scans are on PostGIS tiger geocoder tables (addrfeat, faces, edges, state, county, etc.). These are static census reference tables that are infrequently queried. This is expected behavior and NOT a concern.

### Unused Indexes

All unused indexes are on PostGIS tiger/topology schemas. These are standard PostGIS indexes installed by the extension. They will be used when geocoding functions are called. No action needed.

### Current Configuration vs. Recommended

**Also running 100% stock PostgreSQL 16 defaults.**

| Parameter | Current (Stock) | Recommended | Rationale |
|---|---|---|---|
| shared_buffers | 128 MB | 1 GB | Modest allocation since host runs 3 PG instances |
| work_mem | 4 MB | 32 MB | Standard OLTP |
| maintenance_work_mem | 64 MB | 512 MB | PostGIS index maintenance needs more |
| effective_cache_size | 4 GB | 6 GB | Query planner for 30 GB host |
| random_page_cost | 4.0 | 1.1 | SSD storage |
| effective_io_concurrency | 1 | 200 | SSD storage |
| max_wal_size | 1 GB | 4 GB | Reduce checkpoint frequency |
| min_wal_size | 80 MB | 1 GB | Match WAL footprint |
| checkpoint_timeout | 5 min | 15 min | Reduce checkpoint I/O |
| wal_compression | off | on | Reduce WAL I/O |
| idle_in_transaction_session_timeout | 0 (disabled) | 300000 | Safety net |
| log_min_duration_statement | -1 (off) | 1000 | Log slow queries |
| track_io_timing | off | on | Required for query analysis |
| shared_preload_libraries | (empty) | pg_stat_statements | Enable slow query analysis |
| default_statistics_target | 100 | 200 | Better plans for geospatial queries |

### WAL / Checkpoint Analysis

```
checkpoints_timed: 3,817  checkpoints_req: 2
buffers_checkpoint: 23,704  buffers_clean: 91  buffers_backend: 6,064
stats_reset: 2026-05-10 00:59 (13 days ago)
```

- 3,817 timed checkpoints vs 2 requested. Excellent ratio.
- buffers_backend (6,064) is 25% of buffers_checkpoint (23,704): Higher than ideal. Background writer tuning would help.
- buffers_clean = 91: Background writer barely active.

### Recommendations

1. **HIGH:** Upgrade from PostgreSQL 16.4 to 16.14 (security + performance fixes).
2. **HIGH:** Apply SSD-optimized config.
3. **MEDIUM:** Install pg_stat_statements.
4. **LOW:** Tune bgwriter for better backend-write offloading.

---

## Cross-Instance Recommendations

### A. Enable pg_stat_statements on ALL instances

This is the single highest-value action across the fleet. Without it, slow query analysis and index effectiveness monitoring are blind.

```sql
-- On each instance:
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
-- Add to shared_preload_libraries in postgresql.conf:
-- shared_preload_libraries = 'pg_stat_statements'
-- Then restart container
```

Post-restart monitoring queries:
```sql
-- Top 10 slowest queries
SELECT queryid, calls,
  round(total_exec_time::numeric, 2) AS total_ms,
  round(mean_exec_time::numeric, 2) AS avg_ms,
  round((total_exec_time / sum(total_exec_time) OVER()) * 100, 2) AS pct,
  left(query, 200) AS query_preview
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 10;

-- Top 10 most frequent queries
SELECT queryid, calls,
  round(total_exec_time::numeric, 2) AS total_ms,
  round(mean_exec_time::numeric, 2) AS avg_ms,
  left(query, 200) AS query_preview
FROM pg_stat_statements
ORDER BY calls DESC LIMIT 10;

-- Hit ratio by query
SELECT queryid, calls,
  shared_blks_hit, shared_blks_read,
  CASE WHEN (shared_blks_hit + shared_blks_read) = 0 THEN 100
    ELSE round(shared_blks_hit::numeric / (shared_blks_hit + shared_blks_read) * 100, 2)
  END AS cache_hit_pct,
  left(query, 200)
FROM pg_stat_statements
WHERE shared_blks_hit + shared_blks_read > 0
ORDER BY shared_blks_read DESC LIMIT 10;
```

### B. Connection Pooling with PgBouncer

No instance currently uses connection pooling. Recommendation:

```
Application --> PgBouncer (port 6432) --> PostgreSQL (port 5432)
```

Sample PgBouncer configuration (per instance):
```ini
[databases]
* = host=localhost port=5432

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
default_pool_size = 25
max_client_conn = 100
max_db_connections = 25
```

Deployment: Add PgBouncer as a sidecar container or install on each host.

Priority order:
1. prediction-radar-app-db (8 connections, 5 stuck in transaction)
2. wheeler-postgres (future-proofing as primary DB)
3. aiops-ravynai-postgres
4. frgops-standby (already low connection count)

### C. Background Writer Tuning for All Instances

All instances show the background writer is nearly idle while backends do significant writes:

| Instance | buffers_clean | buffers_backend | bgwriter Activity |
|---|---|---|---|
| wheeler-postgres | 0 | 304 | Idle |
| frgops-standby | 536 | 8,543 | Idle |
| prediction-radar-app-db | 128 | 2,188 | Idle |
| aiops-ravynai-postgres | 91 | 6,064 | Idle |

Recommended additions to all configs:
```ini
bgwriter_delay = 100ms            # Default 200ms -- scan more frequently
bgwriter_lru_maxpages = 400       # Default 100 -- write more per round
bgwriter_flush_after = 512kB      # Default 512kB -- keep default
```

### D. Monitoring Schedule

| Check | Frequency | Query |
|---|---|---|
| Cache hit ratio | Daily | `SELECT sum(blks_hit)/sum(blks_hit+blks_read)*100 FROM pg_stat_database WHERE datname=current_database();` |
| Dead tuples | Daily | `SELECT relname, n_dead_tup, n_live_tup FROM pg_stat_user_tables WHERE n_dead_tup > 0 ORDER BY n_dead_tup DESC LIMIT 10;` |
| Unused indexes | Weekly | `SELECT schemaname, relname, indexrelname FROM pg_stat_user_indexes WHERE idx_scan = 0;` |
| Sequential scans | Weekly | `SELECT relname, seq_scan, idx_scan FROM pg_stat_user_tables WHERE seq_scan > 10 ORDER BY seq_scan DESC LIMIT 20;` |
| Connection states | Hourly | `SELECT state, count(*) FROM pg_stat_activity GROUP BY state;` |
| Idle in transaction | Hourly | `SELECT pid, usename, state, query_start, left(query,200) FROM pg_stat_activity WHERE state = 'idle in transaction' AND query_start < now() - interval '5 minutes';` |
| Slow queries | Daily | Report from pg_stat_statements (top 10 by total_exec_time) |
| Checkpoint frequency | Weekly | `SELECT checkpoints_timed, checkpoints_req, stats_reset FROM pg_stat_bgwriter;` |

### E. Vacuum Maintenance Schedule

All instances currently show autovacuum=on, which is correct. Recommended manual vacuum schedule:

| Schedule | Command | Instances |
|---|---|---|
| Weekly (low-traffic window) | `VACUUM ANALYZE` on all databases | All instances |
| Monthly | `REINDEX DATABASE` CONCURRENTLY on user databases | prediction-radar-app-db (490+ indexes) |
| As needed | `VACUUM FULL` on tables > 30% bloat | Monitored, not scheduled |

Automated vacuum tuning for all configs:
```ini
autovacuum_vacuum_scale_factor = 0.1    # Default 0.2 -- trigger sooner
autovacuum_analyze_scale_factor = 0.05  # Default 0.1 -- analyze more often
autovacuum_max_workers = 3              # Default 3
autovacuum_naptime = 30s                # Default 1min -- check more often
```

### F. Combined AIOPS Memory Budget

AIOPS runs 3 PostgreSQL instances sharing 30 GB RAM with 13 GB actually available. The coordinated allocation:

| Instance | shared_buffers | work_mem | maintenance_work_mem | effective_cache_size |
|---|---|---|---|---|
| frgops-standby | 1.0 GB (current) | 32 MB (current) | 512 MB (bumped) | 3.0 GB (current) |
| prediction-radar-app-db | 2.0 GB | 32 MB | 512 MB | 6.0 GB |
| aiops-ravynai-postgres | 1.0 GB | 32 MB | 512 MB | 6.0 GB |
| **Total PG** | **4.0 GB** | -- | **1.5 GB peak** | **15.0 GB** |
| OS + Docker + fs cache | Remaining ~9 GB | -- | -- | -- |

Rationale:
- prediction-radar-app-db gets 2 GB shared_buffers (largest schema, most tables, highest activity)
- frgops-standby keeps its 1 GB (already tuned)
- aiops-ravynai-postgres gets 1 GB (PostGIS overhead)
- Total 4 GB shared_buffers leaves 9 GB headroom for OS cache, Docker overhead, and other containers
- effective_cache_size at 15 GB total is conservative (50% of total RAM) for coordinated instances

---

## Generated Artifacts

| File | Description |
|---|---|
| `/root/docs/POSTGRES_OPTIMIZATION_PLAN.md` | This document |
| `/root/templates/postgres/optimized-wheeler-postgres.conf` | Optimized config for wheeler-postgres |
| `/root/templates/postgres/optimized-frgops-standby.conf` | Minor tuning for frgops-standby |
| `/root/templates/postgres/optimized-prediction-radar-app-db.conf` | Full retune for prediction-radar-app-db |
| `/root/templates/postgres/optimized-aiops-ravynai-postgres.conf` | Full retune for aiops-ravynai-postgres |
| `/root/templates/postgres/safe-apply-postgres-tuning.sh` | Safe apply script with backup and rollback |

### Safe Apply Procedure

1. Copy the appropriate `.conf` file to the target server
2. Run `safe-apply-postgres-tuning.sh` which:
   - Backs up current postgresql.conf
   - Copies optimized config
   - Restarts container
   - Verifies connectivity
   - Provides rollback command if verification fails

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Config change causes container restart failure | Low | Medium | `safe-apply-postgres-tuning.sh` backs up config, provides rollback |
| shared_buffers too large for AIOPS (3 instances) | Low | Medium | Conservative 4 GB total across 3 instances; monitor with `free -h` |
| Dropping unused indexes breaks app | Low | High | NOT recommended immediately; monitor for 2+ weeks before dropping |
| idle_in_transaction_session_timeout kills legitimate long-running txns | Medium | Low | Set to 5 min; adjust upward if legitimate transactions exceed this |
| pg_stat_statements shared_preload_libraries requires restart | N/A | Low | Planned restart; no data loss |

---

## Appendix: Audit Commands Reference

```bash
# Connection stats
docker exec CONTAINER psql -U USER -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state;"

# Database sizes
docker exec CONTAINER psql -U USER -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;"

# Sequential scans
docker exec CONTAINER psql -U USER -c "SELECT schemaname, relname, seq_scan, idx_scan, seq_tup_read, n_live_tup FROM pg_stat_user_tables WHERE seq_scan > 0 ORDER BY seq_scan DESC LIMIT 20;"

# Unused indexes
docker exec CONTAINER psql -U USER -c "SELECT schemaname, relname, indexrelname, idx_scan FROM pg_stat_user_indexes WHERE idx_scan = 0 ORDER BY relname;"

# Table bloat
docker exec CONTAINER psql -U USER -c "SELECT schemaname, relname, n_live_tup, n_dead_tup, round(n_dead_tup::numeric * 100 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct, pg_size_pretty(pg_total_relation_size(relid)) AS total_size FROM pg_stat_user_tables WHERE n_live_tup > 0 ORDER BY n_dead_tup DESC LIMIT 20;"

# PostgreSQL config
echo "SELECT name, setting, unit, context FROM pg_settings WHERE name IN ('shared_buffers','work_mem','maintenance_work_mem','effective_cache_size','wal_level','max_wal_size','checkpoint_timeout','max_connections','random_page_cost','effective_io_concurrency','autovacuum','wal_buffers');" | docker exec -i CONTAINER psql -U USER

# WAL / checkpoint
docker exec CONTAINER psql -U USER -c "SELECT * FROM pg_stat_bgwriter;"

# Vacuum state
docker exec CONTAINER psql -U USER -c "SELECT relname, last_vacuum, last_autovacuum, last_analyze, last_autoanalyze, n_dead_tup FROM pg_stat_user_tables WHERE n_dead_tup > 1000 ORDER BY n_dead_tup DESC LIMIT 20;"

# Cache hit ratio
docker exec CONTAINER psql -U USER -c "SELECT sum(heap_blks_read) as heap_read, sum(heap_blks_hit) as heap_hit, CASE WHEN (sum(heap_blks_hit) + sum(heap_blks_read)) = 0 THEN 0 ELSE round(sum(heap_blks_hit)::numeric / (sum(heap_blks_hit) + sum(heap_blks_read)) * 100, 2) END as cache_hit_ratio FROM pg_statio_user_tables;"

# pg_stat_statements (if installed)
docker exec CONTAINER psql -U USER -c "SELECT total_exec_time, calls, round(mean_exec_time::numeric, 2) as avg_ms, left(query, 150) FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20;"
```
