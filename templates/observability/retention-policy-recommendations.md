# Wheeler Ecosystem — Retention Policy Recommendations
**Phase 11: Observability Performance Plan  |  2026-05-23**

---

## 1. Prometheus Metrics Retention

| Server | Current | Recommended | CLI Flag |
|--------|---------|-------------|----------|
| AIOPS | **15d (default)** | **30d** | `--storage.tsdb.retention.time=30d` |
| AIOPS | **Unlimited size** | **5GB cap** | `--storage.tsdb.retention.size=5GB` |
| COREDB | DOWN | **30d / 2GB** | After restore |

**Rationale:**
- 30 days enables month-over-month trend analysis
- 5GB cap prevents disk exhaustion (currently using 195MB with 22min of data; projects to ~12.5GB at full 30d if linear, but with WAL compression likely 3-5GB)
- `retention.size` acts as safety valve: if data grows faster than expected, oldest is dropped first

**Estimated storage per server:**
- AIOPS (3,090 series, 15s intervals): ~200MB/day → ~6GB/30d with compression
- COREDB (estimated 500-1,000 series, 15s intervals): ~50MB/day → ~1.5GB/30d

---

## 2. Loki Log Retention

| Server | Current | Recommended | Config Key |
|--------|---------|-------------|------------|
| AIOPS | 90 days | **60 days** | `table_manager.retention_period: 1440h` |

**Rationale:**
- 90 days of logs across 3 servers, each scraping docker containers, syslog, auth, nginx, traefik, AI agents, and PM2 logs will grow significantly
- At estimated 100-500MB/month per server: 90d = 900MB-4.5GB; 60d = 600MB-3GB
- Reducing from 90d to 60d frees 33% storage headroom without losing meaningful forensic capability
- For compliance logs (COREDB audit), use a separate Loki instance or S3 cold storage with 365d retention

**Promtail batch tuning (per server):**
- `batchsize: 524288` (512KB) — reduces memory pressure on busy servers
- `batchwait: 2s` — slight increase reduces network chattiness

---

## 3. Grafana Data Retention

| Data Type | Recommended | Implementation |
|-----------|-------------|----------------|
| Dashboard snapshots | 0 days (disabled) | `[snapshots] external_enabled = false` |
| Alert state history | 120 hours (5 days) | `[unified_alerting]` — DB table cleanup |
| Annotations | 90 days | Grafana UI → Data Sources → Annotations |
| Query history | 30 days | `[query_history]` — native cleanup |

---

## 4. Netdata Retention

| Tier | Resolution | Duration | Storage Budget |
|------|-----------|----------|----------------|
| Tier 0 | 1 second | 2 hours | 512 MB |
| Tier 1 | 1 minute | 48 hours | 256 MB |
| **Total** | | | **~768 MB** |

**Recommendation:** No change. Netdata is effectively a real-time buffer; Prometheus handles long-term metrics. Current 48-hour window is adequate for troubleshooting.

---

## 5. System Logs Retention

### 5.1 logrotate (Host-Level Logs)

| Log Category | Rotation | Retention | Max Size |
|-------------|----------|-----------|----------|
| Application logs (surplusai, frgcrm, canary) | Daily | 14 days | 100 MB |
| PM2 logs | Daily | 7 days | 50 MB |
| Nginx/Traefik logs | Daily | 14 days | 100 MB |
| System logs (syslog, auth, kern, ufw) | Daily | 7 days | 50 MB |
| Docker container logs | Daily | 7 days | 50 MB |

**Total projected log footprint per server:**
- EDGE (current unmanaged ~2GB) → **~500MB** after rotation (75% reduction)
- AIOPS (current 216MB) → **~150MB** (30% reduction)

### 5.2 journald Caps

| Server | Current Size | Cap | Reduction |
|--------|-------------|-----|-----------|
| EDGE | **843.7 MB** | 500 MB | 41% |
| AIOPS | 93.5 MB | 200 MB | -111% (under cap, growth reserved) |
| COREDB | 26.7 MB | 200 MB | -649% (under cap) |

---

## 6. Docker Container Log Rotation

Add to `/etc/docker/daemon.json` (all servers):

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Then: `systemctl restart docker`

This caps container logs at 10MB per file x 3 files = 30MB per container.
At 25-30 containers on AIOPS: ~750-900MB max for all container logs.

---

## 7. ClickHouse Data Retention

| Data Type | Recommended | TTL Syntax |
|-----------|-------------|------------|
| Raw analytics data | 30 days | `TTL event_time + INTERVAL 30 DAY` |
| Aggregated data | 365 days | `TTL event_time + INTERVAL 365 DAY` |
| Materialized views | 30 days | Match source table TTL |

**Note:** ClickHouse TTLs must be configured per-table. Identify which tables are analytics vs. aggregated and apply appropriate TTLs.

---

## 8. Summary: Storage Budget

| Component | Current | Recommended | Delta |
|-----------|---------|-------------|-------|
| Prometheus metrics (AIOPS) | ~196 MB * | ~6 GB (30d) | +5.8 GB |
| Prometheus metrics (COREDB) | 0 MB | ~1.5 GB (30d) | +1.5 GB |
| Loki logs (AIOPS) | 13.8 MB * | ~3 GB (60d) | +3.0 GB |
| Netdata cache (AIOPS) | 746 MB | 768 MB | +22 MB |
| Netdata cache (EDGE) | 339 MB | 339 MB | 0 |
| Grafana data (AIOPS) | 52 MB | 100 MB | +48 MB |
| System logs (EDGE) | ~2,000 MB | ~500 MB | -1,500 MB |
| System logs (AIOPS) | 216 MB | ~150 MB | -66 MB |
| Docker logs (AIOPS) | ~450 MB | ~900 MB | +450 MB |
| **TOTAL** | **~4,013 MB** | **~13.3 GB** | **+9.2 GB** |

*Note: AIOPS Prometheus and Loki were recently restarted; current sizes are not representative of full-retention state.

**Projected impact on AIOPS disk:** 52GB → ~61GB (still only 18% of 338GB)
**Projected impact on EDGE disk:** Net reduction of ~1GB in log storage

---

## 9. Implementation Order

1. **Apply log rotation first** (fastest win, lowest risk) — EDGE recovers ~1.5GB
2. **Apply journald caps** — immediate space savings on EDGE
3. **Apply Prometheus retention** — prevents unbounded growth
4. **Apply Loki retention reduction** — preemptive before data accumulates
5. **Apply ClickHouse TTLs** — depends on table schema analysis
6. **Restore COREDB monitoring** — see Phase 11-A in main plan
