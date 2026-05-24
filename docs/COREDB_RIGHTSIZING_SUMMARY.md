# COREDB Rightsizing Summary

**Server**: wheeler-core-db-01
**Date**: 2026-05-23

---

## Current vs. Target

| Dimension | Current (CPX51) | Target (CX31) | Ratio |
|-----------|-----------------|---------------|-------|
| **vCPUs** | 16 | 8 | 50% |
| **RAM** | 30 GB | 16 GB | 53% |
| **Disk** | 360 GB | 160 GB | 44% |
| **Price** | ~74/month | ~40/month | 54% |

## Actual Utilization (as of 2026-05-23)

| Metric | Used | % of Current | % of Target |
|--------|------|-------------|-------------|
| **CPU** | 0.9% avg | 5.6% | 11.3% |
| **RAM** | 2.4 GB | 8.0% | 15.0% |
| **Disk** | 9.6 GB | 2.7% | 6.0% |
| **Docker volume data** | 570 MB | -- | -- |

## Cost Savings

| Period | Savings |
|--------|---------|
| Monthly | **34/month** |
| Annual | **408/year** |

## Resource Headroom After Migration

Even after halving the server, the application will have substantial headroom:

- **CPU**: 8 vCPUs available vs. 0.9% actual usage. Even under 10x peak load, well within capacity.
- **RAM**: 16 GB available vs. 2.4 GB used. Over 13 GB free for spikes and caching.
- **Disk**: 160 GB available vs. 9.6 GB used. PostgreSQL data (447 MB) could grow 300x before filling the disk.

## Workload Profile

18 Docker containers on a single host, all low-utilization:

| Layer | Containers | Notes |
|-------|-----------|-------|
| **Core** | postgres, redis, minio | Primary data stores |
| **Temporal** | server, ui | Workflow engine |
| **Monitoring** | grafana, prometheus, loki, uptime-kuma | Observability stack |
| **Exporters** | node-exporter, postgres-exporter, redis-exporter | Metrics collection |
| **Apps** | prediction-radar (2), temporal-pipeline (2), usesend | Business applications |
| **Logging** | promtail | Log shipping to Loki |

None of these services are CPU-bound. PostgreSQL and Redis operate entirely in memory at this data scale (447 MB + 55 MB).

## IP and Connectivity Impact

- **Public IP changes**: Yes -- 5.78.210.123 will be replaced
- **Active configs referencing old IP**: Zero. No docker-compose, .env, .conf, or other active configuration files hardcode the public IP. All inter-service communication uses Docker internal DNS or Tailscale mesh addresses.
- **Tailscale**: Auto-healing. The new server will register as wheeler-core-db-01 with a new tailnet IP. Other nodes will discover it automatically.
- **DNS**: Usesend uses `email.frgops.io` (DNS-based, not IP-based). No DNS changes required unless other subdomains point to the old IP.

## Risk Assessment

| Risk | Likelihood | Severity | Mitigation |
|------|-----------|----------|------------|
| Snapshot corruption | Low | High | Off-server backup of volumes and database dumps before shutdown |
| Docker network mismatch after restore | Low | Medium | Network creation commands in checklist; fallback to volume restore |
| Tailscale re-auth required | Low | Low | Tailscale key persists on disk; node is pre-authorized |
| UFW rules lost | Low | Medium | Rules captured to local file; recreate commands in checklist |
| PostgreSQL data inconsistency | Very Low | High | Fresh pg_dump taken immediately before shutdown |
| Temporal namespace/schema issues | Low | Medium | Temporal uses PostgreSQL backend; data integrity is snapshot-guaranteed |
| Application references to old IP | None | N/A | No active configs hardcode the public IP |
| Under-provisioning after migration | Very Low | Low | 11-15% target utilization leaves 6-9x headroom |

## Migration Method

**Hetzner Cloud Snapshot** -- the simplest, most reliable approach for this workload:
1. Gracefully stop all Docker containers and Docker daemon
2. Create a snapshot of the CPX51 server
3. Deploy a new CX31 server from the snapshot
4. Change server type in-place is NOT possible between CPX and CX series (different CPU architectures: dedicated vs. shared vCPU)

Alternative considered: data-only migration (rsync volumes, re-pull images, re-run compose). Rejected because the snapshot preserves everything in one step -- OS configs, Docker images, volumes, UFW rules, crontab, SSH keys. Given the small data size (570 MB), a fresh migration would be comparable in time but with more room for error.

## Estimated Downtime

| Phase | Duration |
|-------|----------|
| Shutdown | 5 min |
| Snapshot + server creation | 10-15 min |
| Startup + verification | 10-15 min |
| **Total** | **25-40 min** |

Docker images do NOT need to be re-pulled -- the snapshot preserves `/var/lib/docker`.

## Go/No-Go Verdict

**GO** -- with conditions.

This is a low-risk, high-reward migration. The server is massively over-provisioned (using 3-8% of its resources) with no active configuration dependency on the public IP. The snapshot-based migration path is well-tested and preserves all state.

Preconditions:
1. Fresh backup taken and verified
2. Off-server copy of volumes and database dumps
3. Maintenance window with stakeholder notification
4. Operator has Hetzner Cloud console or hcloud CLI access

If any precondition fails, delay and re-assess.

---

*Checklist with step-by-step commands: COREDB_MIGRATION_CHECKLIST.md*
