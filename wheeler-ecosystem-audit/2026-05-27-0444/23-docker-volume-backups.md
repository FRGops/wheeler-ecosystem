# 23 - Docker Volume Backups (CoreDB)

**Date:** 2026-05-27
**Operator:** Wheeler DB Agent
**Host:** wheeler-core-db-01 (100.118.166.117, `ssh coredb`)
**Audit ID:** 2026-05-27-0444

## Summary

All 9 Docker volumes on CoreDB now have automated weekly backup coverage. Previously had zero coverage. Total backup footprint: 138 MB compressed.

## Volume Inventory and Backup Status

| # | Volume | Container | Raw Size | Compressed | Archived | Status |
|---|--------|-----------|----------|------------|----------|--------|
| 1 | wheeler-core_postgres_data | wheeler-postgres | 549 MB | 107 MB | Yes | Redundant with pg_dump |
| 2 | wheeler-monitoring_grafana_data | wheeler-grafana | 53 MB | 22 MB | Yes | Covered |
| 3 | wheeler-monitoring_prometheus_data | wheeler-prometheus | 35 MB | 7.7 MB | Yes | Covered |
| 4 | wheeler-core_redis_data | wheeler-redis | 52 MB | 2.9 MB | Yes | Covered |
| 5 | wheeler-core_minio_data | wheeler-minio | 136 KB | 4.8 KB | Yes | Covered |
| 6 | wheeler-monitoring_uptime_kuma_data | wheeler-uptime-kuma | 288 KB | 8.0 KB | Yes | Covered |
| 7 | wheeler-monitoring_loki_data | wheeler-loki | 72 KB | 765 B | Yes | Covered |
| 8 | prediction-radar-app_prediction_radar_db | (no running container) | 4 KB | 92 B | Yes | Empty/unused |
| 9 | prediction-radar-app_prediction_radar_redis | (no running container) | 4 KB | 93 B | Yes | Empty/unused |

**Total:** 138 MB (compressed) across all 9 volumes.

## Backup Script

**Path:** `/root/scripts/backup-docker-volumes.sh` (on CoreDB)

### Design
- Uses `docker run --rm -v <volume>:/source:ro` pattern -- read-only mount, no container interruption
- Alpine container for minimal footprint
- All volumes backed up to `/root/backups/docker-volumes/<volume>-<YYYYMMDD>.tar.gz`
- 7-day retention: `find ... -mtime +7 -delete`
- Full logging to `/var/log/docker-volume-backup.log`
- Supports single-volume test mode: `./backup-docker-volumes.sh <volume-name>`

### Test Results
- Tested on `wheeler-monitoring_grafana_data` before full run -- completed in 3 seconds, 22 MB archive
- Full run: 9/9 volumes backed up successfully in ~24 seconds, zero failures
- All 9 archives independently verified with `tar tzf`

## Crontab Schedule

```
0 3 * * * /opt/backups/backup-postgres.sh              # PostgreSQL logical backup (daily)
0 4 * * 0 /root/scripts/backup-docker-volumes.sh        # Docker volume backup (Sunday weekly)
*/5 * * * * /opt/wheeler-ecosystem/enforcement/wheeler-lockdown-watchdog.sh
```

Docker volume backup runs Sunday at 4am, 1 hour after the PostgreSQL backup at 3am.

## Safety Analysis

| Safety Dimension | Status | Notes |
|-----------------|--------|-------|
| Container interruption | NONE | Read-only mounts, no stop/start |
| Data consistency | GOOD | PostgreSQL has its own logical backup (pg_dump); volume backup for DR |
| Backup isolation | GOOD | Separate directory from live data |
| Archive integrity | VERIFIED | All 9 archives confirmed readable via `tar tzf` |

## Archive Verification

All 9 archives were tested with `tar tzf` and returned valid contents:

- **wheeler-core_postgres_data:** 15,397 entries (full PostgreSQL data directory)
- **wheeler-monitoring_grafana_data:** 468 entries (plugins, dashboards, search index)
- **wheeler-monitoring_prometheus_data:** 78 entries (TSDB blocks, WAL)
- **wheeler-core_redis_data:** 6 entries (dump.rdb, AOF files)
- **wheeler-core_minio_data:** 32 entries (minio metadata)
- **wheeler-monitoring_loki_data:** 21 entries (chunks, compactor, index)
- **wheeler-monitoring_uptime_kuma_data:** 7 entries (SQLite DB, WAL)
- **prediction-radar volumes:** 1 entry each (empty directories)

## Known Gaps

1. **No off-site backup:** Backups stored on CoreDB local disk only. Consider `rsync` or `restic` push to remote storage.
2. **PostgreSQL volume backup is redundant** with the existing pg_dump logical backup at 3am daily. Included for disaster recovery (complete volume restore scenario).
3. **7-day retention:** Adequate for weekly cycle. Adjust if longer history is needed.
4. **Prediction Radar volumes** are empty (4 KB placeholder, no running containers). Retained in script for completeness; safe to exclude in future.

## Restoration Procedure

In the event of data loss:

```bash
# Restore a single volume from backup
docker run --rm \
  -v <volume-name>:/target \
  -v /root/backups/docker-volumes:/backup:ro \
  alpine \
  tar xzf "/backup/<volume-name>-<YYYYMMDD>.tar.gz" -C /target

# Then restart the associated container
docker restart <container-name>
```

## Files

- `/root/scripts/backup-docker-volumes.sh` - Backup script (115 lines, executable)
- `/root/backups/docker-volumes/` - Backup archive directory
- `/var/log/docker-volume-backup.log` - Backup execution log
- Existing: `/opt/backups/backup-postgres.sh` - PostgreSQL logical backup (unchanged)
