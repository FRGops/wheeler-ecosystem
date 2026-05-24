# PHASE 5 -- REDIS OPTIMIZATION PLAN

**Date**: 2026-05-23
**Status**: READ-ONLY AUDIT -- Config generation only

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Audit Methodology](#2-audit-methodology)
3. [Instance Audit: COREDB -- wheeler-redis](#3-instance-audit-coredb----wheeler-redis)
4. [Instance Audit: AIOPS -- docuseal-redis](#4-instance-audit-aiops----docuseal-redis)
5. [Instance Audit: AIOPS -- prediction-radar-app-redis](#5-instance-audit-aiops----prediction-radar-app-redis)
6. [Instance Audit: EDGE -- usesend-redis](#6-instance-audit-edge----usesend-redis)
7. [Cross-Instance Risk Matrix](#7-cross-instance-risk-matrix)
8. [Configuration Templates](#8-configuration-templates)
9. [Safe Apply / Rollback Procedure](#9-safe-apply--rollback-procedure)
10. [Monitoring Recommendations](#10-monitoring-recommendations)

---

## 1. Executive Summary

Four Redis 7.x instances were audited across three servers. All instances exhibit
a common pattern of **zero memory governance**: no `maxmemory` configured, no
eviction policy set, and reliance on OS-level OOM killer as the sole backstop.
Three of four instances have **severe memory fragmentation** (ratios of 4.20 to
11.71), wasting significant RSS relative to logical data size.

### Top 5 Critical Findings

| # | Severity | Finding | Instances Affected |
|---|----------|---------|---------------------|
| 1 | CRITICAL | No maxmemory set on any instance -- unbounded growth risk | All 4 |
| 2 | CRITICAL | Memory fragmentation ratio 8.63-11.71 on 2 instances -- excessive RSS waste | wheeler-redis, prediction-radar |
| 3 | HIGH | docuseal-redis: 1,349 dead Sidekiq jobs consuming memory with no TTL cleanup | docuseal-redis |
| 4 | HIGH | usesend-redis: 10,028 Bull stream events accumulating without pruning | usesend-redis |
| 5 | MEDIUM | wheeler-redis AOF file growing (4.9MB) despite only 266 changes since last save | wheeler-redis |

### Quick Wins

| Action | Impact | Risk |
|--------|--------|------|
| Set `maxmemory` on all instances | Prevents OOM | Low |
| Enable `activedefrag` on high-fragmentation instances | Recovers wasted RSS | Low |
| Add TTL to docuseal dead-letter queue entries | Frees ~1.35K stale entries | Low |
| Cap Bull stream lengths on usesend-redis | Prevents unbounded stream growth | Low |

---

## 2. Audit Methodology

### Connection

```
ssh -o ConnectTimeout=5 root@<IP>
docker exec <container> redis-cli [--no-auth-warning | -a <password>] <command>
```

### Commands Executed per Instance

| Category | Command |
|----------|---------|
| Memory | `INFO memory` |
| Keyspace | `INFO keyspace` |
| Clients | `INFO clients` |
| Stats | `INFO stats` |
| Persistence | `INFO persistence` |
| CPU | `INFO cpu` |
| Eviction policy | `CONFIG GET maxmemory-policy` `CONFIG GET maxmemory` |
| Slow log | `SLOWLOG GET 25` |
| Replication | `INFO replication` |
| Key enumeration | `KEYS *`, `--bigkeys`, per-key TTL/TYPE |

---

## 3. Instance Audit: COREDB -- wheeler-redis

### 3.1 Identity

| Attribute | Value |
|-----------|-------|
| Server | 5.78.210.123 (COREDB) |
| Container | wheeler-redis |
| Image | redis:7.4.9 |
| Auth | Required (password via `--requirepass`) |
| Role | LiteLLM token cache / health check |

### 3.2 Memory Profile

```
used_memory_human:         1.37M
used_memory_rss_human:    11.51M
maxmemory_human:           0B    (UNLIMITED)
mem_fragmentation_ratio:   8.63  (SEVERE)
evicted_keys:              0
```

**Analysis**: RSS is 8.4x logical memory. For 1.37M of real data, 11.51M RSS
is consumed. This is primarily allocator fragmentation (`allocator_rss_ratio:
2.76`) combined with RSS overhead (`rss_overhead_ratio: 1.51`). With only 30GB
total host memory, this is not immediately dangerous but represents poor
efficiency. The container has no resource limits (`Memory: 0`).

### 3.3 Keyspace

```
Database  Keys  Expires  Avg TTL    Content
db6       8     8        ~39s       LiteLLM tokens + max_parallel_requests
```

All keys live in db6 (non-default). Every key has a short TTL (~39 seconds).
This is a pure ephemeral token cache. Keys are LiteLLM internal health-check
tokens and rate-limiting state:

- `{api_key:litellm-internal-health-check}:tokens`
- `{team:litellm-internal-health-check}:tokens`
- `{api_key:litellm-internal-health-check}:max_parallel_requests`
- 4x SHA256-like hex strings (temporary operation tokens)

### 3.4 Client Activity

```
connected_clients:  16
blocked_clients:     0
pubsub_clients:      1
```

16 connected clients with 1 pubsub subscriber. No blocking operations.

### 3.5 Cache Performance

```
keyspace_hits:      4,671
keyspace_misses:      871
Hit rate:           84.3%
```

Respectable hit rate for a short-TTL token cache.

### 3.6 Persistence

```
aof_enabled:              1
aof_current_size:         4,899,392  (4.9MB)
rdb_changes_since_last_save: 266
rdb_last_bgsave_status:   ok
rdb_saves:                35
```

AOF is enabled AND growing. The AOF file has reached 4.9MB despite only 266
changes since the last RDB save. This is because AOF logs every write command --
for a TTL-based ephemeral cache, AOF is unnecessary overhead. The container was
started with `--appendonly yes`.

### 3.7 CPU

```
used_cpu_sys:   16.8s
used_cpu_user:  65.1s
```

Minimal CPU footprint. No slow log entries.

### 3.8 Configuration Gaps

| Setting | Current | Risk |
|---------|---------|------|
| maxmemory | 0 (unlimited) | OOM if keys multiply |
| maxmemory-policy | noeviction | Irrelevant without maxmemory |
| activedefrag | disabled | Fragmentation at 8.63 |
| Databases | default (16) | Only db6 used -- waste |
| AOF | enabled | Unnecessary for ephemeral cache |

### 3.9 Recommendations

1. **Disable AOF**: This is a pure ephemeral cache. AOF writes 4.9MB for
   short-lived keys that expire within 39 seconds. Switch to RDB-only with
   `save ""` (disable RDB saves too, unless needed for restarts).

2. **Set maxmemory to 64MB**: Reasonable headroom for token growth (currently
   1.37M, 64MB allows ~47x growth).

3. **Set maxmemory-policy to allkeys-lru**: If memory pressure occurs, evict
   least recently used tokens.

4. **Enable activedefrag**: Memory fragmentation at 8.63 suggests jemalloc
   fragmentation from frequent TTL expirations.

5. **Reduce databases to 1**: Only db6 is used. Set `databases 1` and migrate
   keys to db0 (or keep 16 -- minimal RAM cost of ~10KB per unused db).

---

## 4. Instance Audit: AIOPS -- docuseal-redis

### 4.1 Identity

| Attribute | Value |
|-----------|-------|
| Server | 5.78.140.118 (AIOPS) |
| Container | docuseal-redis |
| Image | redis:7-alpine |
| Auth | None |
| Role | DocuSeal Sidekiq job queue + stats |

### 4.2 Memory Profile

```
used_memory_human:         2.13M
used_memory_rss_human:     9.75M
maxmemory_human:           0B    (UNLIMITED)
mem_fragmentation_ratio:   4.65  (HIGH)
evicted_keys:              0
```

RSS is 4.6x logical memory. 2.13M of data consumes 9.75M RSS. The container
has no resource limits, and the host has 30GB total with 17GB used.

### 4.3 Keyspace

```
Database  Keys  Expires  Avg TTL         Content
db0       12    7        varies          Sidekiq queue + stats
```

Key breakdown:

| Key | Type | TTL | Description |
|-----|------|-----|-------------|
| `queues` | set | -1 | Registered queue names |
| `processes` | set | -1 | Active worker processes (2) |
| `dead` | zset | -1 | **1,349 dead jobs** (no TTL!) |
| `stat:processed` | string | -1 | Lifetime processed count |
| `stat:failed` | string | -1 | Lifetime failed count |
| `stat:processed:YYYY-MM-DD` | string | ~5yr | Daily processed count (3 keys) |
| `stat:failed:YYYY-MM-DD` | string | ~5yr | Daily failed count (3 keys) |
| `a1aabb190a9a:1:5086a7444c37` | hash | 58s | Active worker heartbeat |

**Critical finding**: The `dead` zset contains 1,349 failed
`ProcessSubmitterCompletionJob` entries, all with `NoMethodError` (undefined
method 'submitters' or 'value' for nil). These jobs have `retry_count: 13` and
have been continuously retried since approximately May 13. They will never
succeed (nil object errors) but persist indefinitely because no TTL or max size
is configured. Each entry is a JSON blob averaging ~400 bytes.

### 4.4 Client Activity

```
connected_clients:  8
blocked_clients:    5  (BLOCKED -- waiting on BRPOP)
```

5 blocked clients is significant for an 8-connection instance. These are
Sidekiq workers executing `BRPOP` on the `default` queue, waiting for jobs that
never arrive because the dead set is full of failed-but-not-removed jobs
that keep being re-enqueued.

### 4.5 Cache Performance

```
keyspace_hits:      35,175
keyspace_misses:    35,212
Hit rate:           49.9%
```

Very poor hit rate -- this is characteristic of a queue workload (workers
polling for jobs that don't exist, BRPOP timeouts, etc.), not a caching
workload.

### 4.6 Persistence

```
aof_enabled:              0
rdb_last_bgsave_status:   ok
rdb_saves:                583       (HIGH fork count)
rdb_changes_since_last_save: 176
```

RDB-only. 583 saves for a small dataset (only 12 keys) is excessive. The
default `save` configuration (save 900 1, save 300 10, save 60 10000) triggers
frequently for queue workloads with high write rates.

### 4.7 Configuration Gaps

| Setting | Current | Risk |
|---------|---------|------|
| maxmemory | 0 (unlimited) | OOM on queue backlog |
| maxmemory-policy | noeviction | Irrelevant without maxmemory |
| activedefrag | disabled | Fragmentation at 4.65 |
| Dead set TTL | None | 1,349 unrecoverable jobs forever |
| RDB save frequency | Default (every write) | Unnecessary forks for queue data |

### 4.8 Recommendations

1. **Clean up dead set**: Delete or archive the 1,349 dead jobs. They are
   unrecoverable (nil object errors) and will never succeed.

2. **Set maxmemory to 128MB**: Queue workloads can spike. 128MB gives ample
   headroom for job bursts while protecting the host.

3. **Set maxmemory-policy to allkeys-lru**: If memory pressure occurs.

4. **Enable activedefrag**: Moderate fragmentation at 4.65.

5. **Reduce RDB save frequency**: For queue workloads, consider:
   ```
   save 900 1
   save 3600 10
   ```
   Or switch to AOF with periodic rewrite for better durability of in-flight
   jobs.

6. **Consider AOF for durability**: If in-flight jobs must survive restarts,
   AOF is preferred for queue workloads since RDB snapshots can lose recent
   enqueues.

---

## 5. Instance Audit: AIOPS -- prediction-radar-app-redis

### 5.1 Identity

| Attribute | Value |
|-----------|-------|
| Server | 5.78.140.118 (AIOPS) |
| Container | prediction-radar-app-redis |
| Image | redis:7 |
| Auth | None |
| Role | Prediction Radar app cache (appears idle) |

### 5.2 Memory Profile

```
used_memory_human:         988.29K
used_memory_rss_human:     10.88M
maxmemory_human:           0B    (UNLIMITED)
mem_fragmentation_ratio:   11.71 (SEVERE)
evicted_keys:              0
```

The worst fragmentation ratio across all instances (11.71). 988K of actual data
consumes 10.88M RSS. This is `allocator_rss_ratio: 3.64` compounded by
`rss_overhead_ratio: 1.66`. This instance has a Docker memory limit of 512MB --
the only instance with any resource constraint.

### 5.3 Keyspace

```
Database  Keys  Expires  Content
db0       0     0        EMPTY
```

**This instance is 100% idle**. DBSIZE returns 0. No keys, no expires, no
nothing.

### 5.4 Client Activity

```
connected_clients:  1
blocked_clients:    0
```

Single idle client connection.

### 5.5 Cache Performance

```
keyspace_hits:      0
keyspace_misses:    0
```

Zero cache activity. `total_commands_processed: 11,664` suggests connection
setup/teardown overhead but no data operations.

### 5.6 Persistence

```
aof_enabled:              1
aof_current_size:         88  (essentially empty)
rdb_saves:                0   (never saved)
```

AOF is enabled but the file is only 88 bytes (header/metadata only). Zero RDB
saves have occurred.

### 5.7 Configuration Gaps

| Setting | Current | Risk |
|---------|---------|------|
| maxmemory | 0 | Mitigated by 512MB Docker limit |
| maxmemory-policy | noeviction | Irrelevant |
| activedefrag | disabled | Fragmentation 11.71 |
| Purpose | Unclear | 10.88M RSS for nothing |

### 5.8 Recommendations

1. **Investigate purpose**: Determine if this instance is still needed. If the
   Prediction Radar app is deprecated or migrated, remove the container.

2. **If kept, reduce memory**: Set `maxmemory 32MB -- 64MB` and enable
   `activedefrag`.

3. **Disable AOF**: No data exists to persist.

4. **Consider removing the container entirely** if the app no longer uses it.
   This frees 10.88M RSS and simplifies the AIOPS footprint.

---

## 6. Instance Audit: EDGE -- usesend-redis

### 6.1 Identity

| Attribute | Value |
|-----------|-------|
| Server | 187.77.148.88 (EDGE) |
| Container | usesend-redis |
| Image | redis (version not tagged) |
| Auth | None |
| Role | Bull job queue for UseSend application |

### 6.2 Memory Profile

```
used_memory_human:         2.92M
used_memory_rss_human:    12.12M
maxmemory_human:           0B    (UNLIMITED)
mem_fragmentation_ratio:   4.20  (MODERATE-HIGH)
evicted_keys:              0
```

RSS at 4.15x logical memory. 2.92M of queue data consumes 12.12M RSS. Docker
stats show 18.62MB container memory. Host has 31GB total with 5.7GB used.

### 6.3 Keyspace -- Bull Queue Topology

```
Database  Keys  Expires  Avg TTL    Content
db0       52    1        13850s     Bull queues (5 active)
```

**All 52 keys are Bull queue keys**. Five distinct queues:

| Queue | Keys Found | Notable |
|-------|------------|---------|
| `webhook-dispatch` | 3 (meta, stalled-check) | Active in slowlog, 94-198ms evalsha calls |
| `campaign-scheduler` | 17 (active, delayed, repeat, failed, events, marker) | 1 active job, 10,028 stream events aggregated |
| `domain-verification` | 28 (repeat jobs x17, failed x9, others) | 19 failed jobs, hourly repeat schedule, 17 future timestamps |
| `ses-webhook` | 1 (meta) | Idle/minimal |
| `contact-bulk-add` | 1 (meta) | Idle/minimal |
| `campaign-batch` | 1 (meta) | Idle/minimal |

**Stream analysis**:

| Key | Type | Size |
|-----|------|------|
| `bull:campaign-scheduler:events` | stream | **10,028** entries |
| `bull:domain-verification:events` | stream | **1,626** entries |
| `bull:domain-verification:failed` | zset | 19 members |
| `bull:campaign-scheduler:failed` | zset | 9 members |
| `bull:domain-verification:repeat` | zset | 1 member |
| `bull:campaign-scheduler:repeat` | zset | 1 member |

Bull uses Redis streams for event tracking, and without `MAXLEN`
truncation, these streams grow indefinitely. The `campaign-scheduler:events`
stream at 10,028 entries is the largest single consumer of memory.

**Repeatable job timestamps** (domain-verification-hourly): 17 timestamps
ranging from `1779249600000` to `1779318000000`. These are future-scheduled
repeat jobs spanning approximately 19 hours.

### 6.4 Client Activity

```
connected_clients:  3
blocked_clients:    1  (BZPOPMIN on bull:webhook-dispatch:marker)
```

One blocked client is a Bull worker waiting on the `webhook-dispatch` queue
marker.

### 6.5 Cache Performance

```
keyspace_hits:      27,276
keyspace_misses:    57,655
Hit rate:           32.1%
```

Very poor hit rate, typical for Bull queue workloads. The evalsha operations
in the slowlog show Bull's Lua scripts checking multiple queue keys with many
"key not found" patterns, especially for paused/empty queues.

### 6.6 Slow Log Analysis

All 25 entries are from the past 30 minutes, showing **consistent** Bull
evalsha activity on `webhook-dispatch`. Execution times:

- Fastest: 94,418 microseconds (94ms)
- Slowest: 198,870 microseconds (199ms)
- Average: ~98ms

The slow evalsha calls are Bull's `moveToFinished` or `moveToActive` Lua
scripts that check 11 keys atomically. The consistent 94-100ms range suggests
CPU-bound operations rather than intermittent spikes. Two operations (`DEL
bull:webhook-dispatch:pc`) are significantly faster at ~95ms.

### 6.7 Persistence

```
aof_enabled:              0
rdb_last_bgsave_status:   ok
rdb_saves:                36
```

RDB-only. 36 saves is reasonable.

### 6.8 Configuration Gaps

| Setting | Current | Risk |
|---------|---------|------|
| maxmemory | 0 (unlimited) | Stream growth unbounded |
| maxmemory-policy | noeviction | Would REJECT writes under eviction |
| Stream maxlen | Not set | campaign-scheduler events at 10,028 and growing |
| Failed job TTL | None | 19+9 failed jobs persist forever |
| Slow evalsha | 94-198ms | No timeout configured |
| activedefrag | disabled | Fragmentation at 4.20 |
| lazyfree-lazy-eviction | not set | Blocking eviction could impact latency |

### 6.9 Recommendations

1. **Set maxmemory to 256MB**: Bull queue workloads can accumulate events.
   256MB provides headroom while protecting the host.

2. **Set maxmemory-policy to allkeys-lru OR volatile-lru**: If using TTLs on
   all keys, `volatile-lru` is safer. But `allkeys-lru` is preferred for
   Bull queues since not all keys may have TTLs.

3. **Cap Bull stream MAXLEN**: The application should be updated to call
   `stream.add` with `MAXLEN ~ 1000` for event streams, or a periodic
   cleanup job should trim streams. Alternatively, set:
   ```
   # In application code:
   queueEvents.on('completed', ({ jobId }) => { ... })
   // Keep only last 1000 events:
   client.xtrim('bull:campaign-scheduler:events', 'MAXLEN', '~', 1000)
   ```

4. **Enable activedefrag**: Moderate fragmentation.

5. **Enable lazyfree-lazy-eviction yes**: Non-blocking eviction for Bull
   workloads where eviction latency matters.

6. **Set latency-monitor-threshold 100**: Track operations exceeding 100ms
   (already happening in slowlog).

7. **Configure Bull queue cleanup**:
   - Set `removeOnComplete: 100` for completed jobs
   - Set `removeOnFail: 100` for failed jobs
   - Or add a periodic cleanup of the failed zsets

8. **Investigate domain-verification failed entries**: 19 failed domain
   verification jobs with no TTL. Clean up or add TTL.

---

## 7. Cross-Instance Risk Matrix

| Risk | wheeler-redis | docuseal-redis | prediction-radar | usesend-redis |
|------|:---:|:---:|:---:|:---:|
| OOM (no maxmemory) | MEDIUM | MEDIUM | LOW | MEDIUM |
| Memory fragmentation | **CRITICAL** (8.63) | HIGH (4.65) | **CRITICAL** (11.71) | HIGH (4.20) |
| Unbounded queue growth | N/A | HIGH (dead set) | N/A | HIGH (streams) |
| Unnecessary persistence | HIGH (AOF) | LOW | HIGH (AOF) | LOW |
| Stale/poison data | LOW | **CRITICAL** (1349 dead jobs) | LOW | MODERATE (19 failed) |
| No container limits | YES | YES | PARTIAL (512MB) | YES |

### Overall Fleet Health

| Metric | Value |
|--------|-------|
| Total instances audited | 4 |
| With maxmemory set | 0 |
| With eviction policy configured | 0 |
| With activedefrag enabled | 0 |
| With replication | 0 |
| With container memory limits | 1 (prediction-radar, 512MB) |
| Requiring immediate intervention | 2 (dead set cleanup, stream capping) |

---

## 8. Configuration Templates

Generated configuration files at `/root/templates/redis/`:

| File | Target |
|------|--------|
| `wheeler-redis.conf` | COREDB wheeler-redis |
| `docuseal-redis.conf` | AIOPS docuseal-redis |
| `prediction-radar-redis.conf` | AIOPS prediction-radar-app-redis |
| `usesend-redis.conf` | EDGE usesend-redis |

Each config is a complete Redis 7.x configuration file with inline comments
explaining every change from defaults. See individual files for details.

### Summary of Recommended Settings

| Setting | wheeler-redis | docuseal-redis | prediction-radar | usesend-redis |
|---------|:---:|:---:|:---:|:---:|
| maxmemory | 64mb | 128mb | 32mb | 256mb |
| maxmemory-policy | allkeys-lru | allkeys-lru | allkeys-lru | allkeys-lru |
| activedefrag | yes | yes | yes | yes |
| active-defrag-threshold-lower | 10 | 10 | 10 | 10 |
| active-defrag-threshold-upper | 50 | 50 | 50 | 50 |
| lazyfree-lazy-eviction | yes | yes | yes | yes |
| appendonly | **no** | **yes** | **no** | no |
| auto-aof-rewrite-percentage | -- | 100 | -- | -- |
| save | "" | 900 1 3600 10 | "" | 900 1 3600 10 |
| databases | 1 | 16 | 16 | 16 |
| tcp-keepalive | 300 | 300 | 300 | 300 |
| timeout | 300 | 0 | 300 | 0 |
| slowlog-log-slower-than | 10000 | 10000 | 10000 | 50000 |
| latency-monitor-threshold | 100 | 100 | 100 | 100 |
| client-output-buffer-limit | 64mb 32mb 60 | 64mb 32mb 60 | 64mb 32mb 60 | 64mb 32mb 60 |
| hz | 10 | 10 | 10 | 10 |
| stop-writes-on-bgsave-error | yes | no | yes | no |

---

## 9. Safe Apply / Rollback Procedure

Script: `/root/templates/redis/safe-apply-redis-tuning.sh`

### Procedure Summary

1. **Pre-flight checks**:
   - Verify container is running
   - Verify redis-cli connectivity
   - Take RDB snapshot (`BGSAVE`)
   - Export current CONFIG to backup file

2. **Apply changes** (using `CONFIG SET` for runtime, no restart needed for most):
   - Set maxmemory
   - Set maxmemory-policy
   - Enable activedefrag
   - Set lazyfree-lazy-eviction
   - Adjust save/AOF settings

3. **Verify**:
   - `CONFIG GET` each changed setting
   - `INFO memory` to confirm fragmentation trending down
   - Wait 60 seconds, re-check

4. **Rollback** (if issues detected):
   - Restore all CONFIG from backup
   - Re-verify

### Important Notes

- All changes are runtime-only via `CONFIG SET`. Container restarts will
  revert them unless the config file is mounted into the container.
- For permanent changes, the generated `.conf` files should be mounted
  into the container at `/usr/local/etc/redis/redis.conf`.
- The `safe-apply-redis-tuning.sh` script handles the runtime apply only.
  Permanent config requires Docker container recreation with volume mount.

---

## 10. Monitoring Recommendations

### Critical Metrics to Monitor Post-Changes

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| `used_memory` / `maxmemory` ratio | `INFO memory` | > 80% |
| `evicted_keys` delta | `INFO stats` | > 0 in 5 minutes |
| `mem_fragmentation_ratio` | `INFO memory` | > 2.0 |
| `keyspace_misses / (hits+misses)` | `INFO stats` | > 80% miss rate |
| `blocked_clients` | `INFO clients` | > 10 |
| `rejected_connections` | `INFO stats` | > 0 |
| `aof_delayed_fsync` | `INFO persistence` | > 0 |
| `instantaneous_ops_per_sec` | `INFO stats` | > 2x baseline |
| `slowlog_len` | `SLOWLOG LEN` | > 100 in 10 minutes |

### Prometheus Metrics (if available)

```yaml
# redis_exporter scrape config
- job_name: redis
  static_configs:
    - targets:
      - '5.78.210.123:6379'   # wheeler-redis
      - '5.78.140.118:6379'   # docuseal-redis
      - '5.78.140.118:6380'   # prediction-radar-redis
      - '187.77.148.88:6379'  # usesend-redis
```

### Grafana Dashboard Panels

1. Memory usage vs maxmemory (gauge)
2. Evictions/sec (counter rate)
3. Cache hit rate (timeseries, 5m avg)
4. Fragmentation ratio (gauge)
5. Connected/blocked clients (timeseries)
6. Slow log count (counter)
7. Ops/sec (timeseries)
8. AOF size / RDB save status (stat)

---

## Appendix A: Raw Audit Data

Full raw audit output is archived in the session transcript. Key data points
have been extracted into the instance sections above.

## Appendix B: Generated Files

```
/root/docs/REDIS_OPTIMIZATION_PLAN.md           -- This document
/root/templates/redis/wheeler-redis.conf         -- Optimized config for COREDB
/root/templates/redis/docuseal-redis.conf        -- Optimized config for AIOPS (docuseal)
/root/templates/redis/prediction-radar-redis.conf-- Optimized config for AIOPS (prediction-radar)
/root/templates/redis/usesend-redis.conf          -- Optimized config for EDGE (usesend)
/root/templates/redis/safe-apply-redis-tuning.sh  -- Safe apply + rollback script
```

---

**Audit completed**: 2026-05-23
**Next phase**: Apply tuning changes in maintenance window, monitor for 72 hours,
then commit configs to container definitions.
