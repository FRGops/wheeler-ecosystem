# PHASE 3 -- DOCKER OPTIMIZATION PLAN

**Generated:** 2026-05-23
**Scope:** AIOPS (5.78.140.118), COREDB (5.78.210.123), EDGE (187.77.148.88)
**Principle:** READ-ONLY AUDIT -- templates and scripts only; no modifications applied.

---

## EXECUTIVE SUMMARY

This plan covers 36+ running containers across three servers. Key findings:

| Priority | Issue | Server | Impact |
|----------|-------|--------|--------|
| CRITICAL | temporal-server at 83% CPU with no resource cap | EDGE | Risk of starving host |
| CRITICAL | usesend-redis at 44% CPU with no resource cap | EDGE | Abnormal -- likely runaway |
| CRITICAL | temporal-temporal-1 has 15 restarts in its lifecycle | EDGE | Flapping container |
| HIGH | langflow consuming 788 MiB RAM, no limit | AIOPS | 2.52% of host RAM ungoverned |
| HIGH | clickhouse consuming 873 MiB RAM, no limit | AIOPS | 2.79% of host RAM ungoverned |
| HIGH | COREDB monitoring stack (4 containers) -- stopped/dead | COREDB | Monitoring gap |
| MEDIUM | 4 containers on AIOPS have NO log rotation (portainer, dockge, uptime-kuma, etc.) | AIOPS | Unbounded disk growth |
| MEDIUM | COREDB -- ALL 3 running containers have NO log rotation | COREDB | Unbounded disk growth |
| MEDIUM | 1 orphaned volume on AIOPS | AIOPS | Wasted 1.35 GB volume space |
| LOW | Staging skeleton compose files under /opt/stacks/ -- all bind port 8080 | AIOPS | Confusion risk |
| LOW | langflow has 2 images (1.0.19: 2.79GB + latest: 5.5GB) doubling space | AIOPS | Wasteful |

---

## SECTION 1: SERVER-BY-SERVER AUDIT

---

### 1.1 AIOPS (5.78.140.118)

**Host:** 30.6 GiB RAM, 338GB disk (52GB used, 17%)
**Running containers:** 25
**Docker system df:** 29 images (33.65GB), 25 active containers, 14 volumes (1.35GB)

#### 1.1.1 Top CPU Consumers

| Container | CPU% | Notes |
|-----------|------|-------|
| aiops-clickhouse | 3.94% | High PIDs (692) -- expected for OLAP DB |
| promtail | 1.56% | Log collector -- acceptable |
| loki | 1.18% | Log aggregator -- acceptable |
| netdata | 1.05% | 201 PIDs -- expected for monitoring agent |
| docuseal-redis | 0.80% | Low mem, notable CPU for a cache |
| aiops-grafana | 0.78% | Dashboard rendering -- acceptable |

#### 1.1.2 Top RAM Consumers

| Container | RAM Used | Limit | Recommendation |
|-----------|----------|-------|----------------|
| aiops-clickhouse | 873.8 MiB | none | Add 2.0-3.0 GiB limit |
| langflow | 788.6 MiB | none | Add 1.5-2.0 GiB limit |
| aiops-healthchecks | 258.8 MiB | none | Add 512 MiB limit |
| prediction-radar-app-api | 257.6 MiB | 1 GiB | Limit OK, usage OK |
| aiops-superset | 190.6 MiB | none | Add 512 MiB limit |
| docuseal | 170.4 MiB | none | Add 512 MiB limit |
| dockge | 160.8 MiB | none | Add 256 MiB limit |
| aiops-grafana | 140.5 MiB | none | Add 256 MiB limit |
| uptime-kuma | 114.9 MiB | none | Add 256 MiB limit |
| aiops-changedetection | 110.5 MiB | none | Add 256 MiB limit |
| loki | 88.5 MiB | none | Add 256 MiB limit |

#### 1.1.3 Restart Counts

All 25 running containers have restart count = 0. No flapping observed.

#### 1.1.4 Health Status

No unhealthy containers detected.

#### 1.1.5 Orphaned Volumes

One orphaned volume found:
- `monitoring_uptime-kuma-data` -- leftover from a removed monitoring uptime-kuma stack (the current monitoring stack uses different volume names)

#### 1.1.6 Orphaned Images

None found (`docker images -f dangling=true` returned empty).

#### 1.1.7 Port Exposure

Containers with world-exposed (0.0.0.0) ports that should be considered for binding to localhost or a Docker network only:

| Container | Port Mapping | Risk |
|-----------|-------------|------|
| frgops-standby | 0.0.0.0:5433->5432 | **Postgres exposed to world** |
| aiops-ravynai-postgres | 0.0.0.0:5434->5432 | **Postgres exposed to world** |
| docuseal | 0.0.0.0:3010->3000 | App port |
| langflow | 0.0.0.0:7860->7860 | App port |
| prediction-radar-app-web | 0.0.0.0:8098->80 | App port (via Traefik -- could be internal) |
| aiops-superset | 0.0.0.0:8088->8088 | App port |
| aiops-clickhouse | 0.0.0.0:8123->8123 | **Database port exposed** |
| aiops-grafana | 0.0.0.0:3002->3000 | App port |
| aiops-prometheus | 0.0.0.0:9090->9090 | Metrics -- should be internal |
| netdata | 0.0.0.0:19999->19999 | Monitoring -- should be internal |
| portainer | 0.0.0.0:9000->9000 | Management -- **high security risk** |
| dockge | 0.0.0.0:5001->5001 | Management |
| uptime-kuma | 0.0.0.0:3001->3001 | Monitoring dashboard |

Properly bound to localhost: loki (127.0.0.1:3100), promtail (127.0.0.1:9080).

#### 1.1.8 Logging Config

| Status | Count | Containers |
|--------|-------|------------|
| Properly rotated (10m/3) | 20 | Most app containers |
| Extended limits (25m/5) | 1 | netdata |
| NO LIMITS AT ALL | 4 | **portainer, dockge-test-nginx, dockge, uptime-kuma** |

#### 1.1.9 Log Disk Usage (top offenders)

| Container Log Dir | Size |
|-------------------|------|
| frgops-standby | 18 MB |
| aiops-grafana | 15 MB |
| netdata | 9.7 MB |
| hostinger-health-exporter | 2.5 MB |
| loki | 1.8 MB |

#### 1.1.10 Image Size Assessment

| Image | Size | Issue |
|-------|------|-------|
| langflowai/langflow:latest | 5.5 GB | Duplicate of 1.0.19 (2.79GB) -- remove unused tag |
| prediction-radar-app-api:latest | 4.17 GB | Custom build -- expected |
| langflowai/langflow:1.0.19 | 2.79 GB | In use -- keep |
| ghcr.io/dgtlmoon/changedetection.io:latest | 1.47 GB | Heavy base image |
| grafana/grafana:latest | 1.45 GB | Plugin bloat |
| apache/superset:4.1.1 | 1.34 GB | Expected |
| clickhouse/clickhouse-server:24.3 | 1.26 GB | Expected |

**Reclaimable space:** 5.485 GB (image layers) + 3.351 GB (build cache) + 1 orphaned volume

#### 1.1.11 Existing Docker Compose Files

```
/opt/apps/changedetection/docker-compose.yml      -- aiops-changedetection
/opt/apps/monitoring/docker-compose.yml           -- prometheus, grafana, health-exporter
/opt/apps/healthchecks/docker-compose.yml         -- aiops-healthchecks
/opt/apps/prediction-radar-app/docker-compose.yml -- Full Prediction Radar suite
/opt/apps/langflow/docker-compose.yml             -- langflow
/opt/apps/analytics/docker-compose.yml            -- clickhouse + superset
/opt/apps/docuseal/docker-compose.yml             -- docuseal + redis
/opt/apps/ravynai-opportunity-graph/docker-compose.yml -- ravynai
/opt/stacks/dockerecosystemmanager/compose.yaml   -- dockge alias (skeleton)
```

**Note:** `/opt/stacks/*/compose.yaml` files are all identical skeleton nginx containers (port 8080). These appear to be staging placeholders, not active deployments. They should be cleaned or annotated to prevent confusion.

#### 1.1.12 Existing Resource Limits

Only 4 of 25 containers have explicit resource limits:

| Container | Memory Limit | CPU Limit |
|-----------|-------------|-----------|
| prediction-radar-app-api | 1 GiB | 1.0 CPU |
| prediction-radar-app-db | 2 GiB | none |
| prediction-radar-app-redis | 512 MiB | none |
| aiops-ravynai-app | 1 GiB | 1.0 CPU |

---

### 1.2 COREDB (5.78.210.123)

**Host:** 30.6 GiB RAM, 338GB disk (6.2GB used, 2%)
**Running containers:** 3 active (7 total configured)
**Docker system df:** 7 images (4.017GB), 3 active containers, 7 volumes (129.8MB)

**IMPORTANT NOTE:** The monitoring stack (wheeler-uptime-kuma, wheeler-loki, wheeler-grafana, wheeler-prometheus) defined in `/opt/wheeler-monitoring/docker-compose.yml` is currently STOPPED. Only the core stack (`/opt/wheeler-core/docker-compose.yml`) is running: postgres, redis, minio.

#### 1.2.1 Top CPU Consumers (when monitoring stack was running)

| Container | CPU% | Notes |
|-----------|------|-------|
| wheeler-loki | 0.84% | Monitoring -- currently stopped |
| wheeler-grafana | 0.76% | Monitoring -- currently stopped |
| wheeler-redis | 0.33% | Core service |

#### 1.2.2 Top RAM Consumers

| Container | RAM Used | Limit | Recommendation |
|-----------|----------|-------|----------------|
| wheeler-grafana | 123.3 MiB | none | Stopped -- N/A |
| wheeler-uptime-kuma | 106 MiB | none | Stopped -- N/A |
| wheeler-minio | 68.4 MiB | none | Add 256 MiB limit |
| wheeler-loki | 61.0 MiB | none | Stopped -- N/A |
| wheeler-prometheus | 38.2 MiB | none | Stopped -- N/A |
| wheeler-postgres | 20.3 MiB | none | Add 512 MiB limit |
| wheeler-redis | 4.4 MiB | none | Add 128 MiB limit |

#### 1.2.3 Restart Counts

All containers: 0 restarts. No flapping.

#### 1.2.4 Health Status

No unhealthy containers.

#### 1.2.5 Orphaned Volumes / Images

None found.

#### 1.2.6 Port Exposure

| Container | Port Mapping | Risk |
|-----------|-------------|------|
| wheeler-postgres | 0.0.0.0:5432->5432 | **Postgres exposed to world** |
| wheeler-redis | 0.0.0.0:6379->6379 | **Redis exposed to world** |
| wheeler-minio | 0.0.0.0:9000-9001->9000-9001 | **Object storage exposed to world** |

All three running containers expose ports to 0.0.0.0. These should either be firewalled at the host level, bound to 127.0.0.1, or placed behind a reverse proxy with authentication.

#### 1.2.7 Logging Config

**CRITICAL: ALL 3 running containers have NO log rotation configured.**

| Container | Log Driver | Max Size | Max File |
|-----------|-----------|----------|----------|
| wheeler-postgres | json-file | **none** | **none** |
| wheeler-redis | json-file | **none** | **none** |
| wheeler-minio | json-file | **none** | **none** |

Current disk usage for container logs (with only 3 running):
- wheeler-loki: 2.6 MB (container stopped but log file persists)
- wheeler-grafana: 1.9 MB
- wheeler-postgres: 588 KB
- Others: < 100 KB

#### 1.2.8 Existing Resource Limits

**None.** All 3 running containers run without memory or CPU constraints.

#### 1.2.9 Docker Compose Files

```
/opt/wheeler-monitoring/docker-compose.yml   -- grafana, prometheus, loki, uptime-kuma (STOPPED)
/opt/wheeler-core/docker-compose.yml         -- postgres, redis, minio (RUNNING)
```

Both compose files lack logging configuration and resource limits.

---

### 1.3 EDGE (187.77.148.88)

**Host:** 31.34 GiB RAM
**Running containers:** 11
**Docker system df:** 37 images, ~90+ compose files across the filesystem (many for staging/test)

#### 1.3.1 Top CPU Consumers

| Container | CPU% | Severity | Notes |
|-----------|------|----------|-------|
| **temporal-server** | **83.04%** | **CRITICAL** | Single core pinned -- no CPU limit |
| **usesend-redis** | **44.03%** | **CRITICAL** | Abnormal for Redis -- investigate |
| temporal-temporal-1 | 28.45% | HIGH | Temporal worker, 15 restarts |
| shared-postgres-recovery | 0.76% | OK | Acceptable for database |
| private-ai-webui | 0.60% | OK | ML model idle |

The temporal-server consuming 83% of a single core continuously with no resource cap is a serious risk. If this spikes, it can starve other processes on the host.

usesend-redis at 44% CPU is abnormal for a Redis instance. Possible causes: runaway Lua script, excessive client connections, or keyspace notifications loop.

#### 1.3.2 Top RAM Consumers

| Container | RAM Used | Limit | Recommendation |
|-----------|----------|-------|----------------|
| private-ai-webui | 664.9 MiB | 1.465 GiB | Limit is adequate; usage 44% |
| shared-postgres-recovery | 175.4 MiB | none | Add 512 MiB limit |
| usesend-storage | 158.8 MiB | none | Add 512 MiB limit |
| usesend | 130.8 MiB | none | Add 512 MiB limit |
| temporal-server | 93.6 MiB | none | Add 512 MiB limit |

#### 1.3.3 Restart Counts

| Container | Restarts | Severity | Action |
|-----------|----------|----------|--------|
| **temporal-temporal-1** | **15** | **CRITICAL** | Investigate crash loop immediately |
| All others | 0 | OK | -- |

The temporal-temporal-1 container has restarted 15 times over its lifetime. This indicates a crash loop or repeated OOM kills. Replace the `unless-stopped` restart policy with `on-failure:5` and investigate the root cause.

#### 1.3.4 Health Status

No unhealthy containers detected. However, there are no HEALTHCHECK instructions configured on any container.

#### 1.3.5 Orphaned Volumes / Images

Not fully assessed (analysis deferred). With 37 images and 11 running containers, there are likely significant reclaimable images. The EDGE server has a large number of compose files (~90+), many for test/staging environments, which suggests many images are unused.

#### 1.3.6 Port Exposure

| Container | Port Mapping | Risk |
|-----------|-------------|------|
| temporal-temporal-ui-1 | 0.0.0.0:8080->8080 | Temporal UI |
| private-ai-webui | 0.0.0.0:3015->8080 | LLM WebUI |
| shared-postgres-recovery | **127.0.0.1:5432** | CORRECT -- localhost only |
| usesend | 0.0.0.0:3007->3000 | App port |
| usesend-storage | 0.0.0.0:9003-9004->9001-9002 | Minio -- should be internal |

shared-postgres-recovery is correctly bound to 127.0.0.1. Other services use 0.0.0.0 bindings.

#### 1.3.7 Logging Config

EDGE has the best logging configuration of all three servers:

| Container | Driver | Max Size | Max File |
|-----------|--------|----------|----------|
| temporal-temporal-1 | json-file | 50m | 3 |
| temporal-temporal-ui-1 | json-file | 50m | 3 |
| temporal-server | json-file | 50m | 3 |
| private-ai-webui | json-file | 10m | 3 |
| shared-postgres-recovery | json-file | 50m | 3 |
| prediction-radar-app-scheduler | json-file | 100m | 3 |
| prediction-radar-app-worker | json-file | 100m | 3 |
| shared-postgres-exporter | json-file | 50m | 3 |
| usesend | json-file | 50m | 3 |
| usesend-storage | json-file | 50m | 3 |
| usesend-redis | json-file | 50m | 3 |

All containers have log rotation configured. However, some max-sizes (100m) are unnecessarily large and could fill disk quickly on a busy system.

#### 1.3.8 Log Disk Usage (top offenders)

| Container Log Dir | Size |
|-------------------|------|
| shared-postgres-recovery | 7.1 MB |
| prediction-radar-app-worker | 5.6 MB |
| usesend | 512 KB |
| temporal-server | 304 KB |

#### 1.3.9 Existing Resource Limits

| Container | Memory Limit | CPU Limit | Restart Policy |
|-----------|-------------|-----------|----------------|
| private-ai-webui | 1.465 GiB | 0.75 CPU | unless-stopped |
| prediction-radar-app-scheduler | 512 MiB | none | on-failure |
| prediction-radar-app-worker | 1 GiB | none | on-failure |
| temporal-server | none | none | **no** |
| temporal-temporal-1 | none | none | unless-stopped |
| temporal-temporal-ui-1 | none | none | unless-stopped |
| shared-postgres-recovery | none | none | unless-stopped |
| shared-postgres-exporter | none | none | always |
| usesend | none | none | always |
| usesend-storage | none | none | always |
| usesend-redis | none | none | always |

**CRITICAL:** temporal-server has `RestartPolicy: no` -- if it crashes due to CPU exhaustion, it will NOT restart.

#### 1.3.10 Image Size Assessment

37 images on disk. Notable large ones:

| Image | Size | Status |
|-------|------|--------|
| ghcr.io/open-webui/open-webui:main | 6.7 GB | Likely unused |
| dash:latest | 1.85 GB | Unknown purpose |
| prediction-radar-app-fincept-terminal:latest | 1.28 GB | Custom build |
| ghcr.io/flaresolverr/flaresolverr:latest | 986 MB | Anti-bot proxy |
| temporalio/admin-tools:latest | 938 MB | Likely unused |
| temporalio/auto-setup:latest | 788 MB | Likely unused |

Many images from unused compose files are candidates for pruning.

---

## SECTION 2: RECOMMENDATIONS MATRIX

### 2.1 Resource Limits

| Server | Container | Current RAM | Rec. RAM Limit | Rec. CPU Limit | Priority |
|--------|-----------|-------------|----------------|----------------|----------|
| AIOPS | aiops-clickhouse | 873.8 MiB | 3.0 GiB | 4.0 CPUs | HIGH |
| AIOPS | langflow | 788.6 MiB | 2.0 GiB | 2.0 CPUs | HIGH |
| AIOPS | prediction-radar-app-api | 257.6 MiB | 1.0 GiB (existing) | 1.0 (existing) | OK |
| AIOPS | aiops-healthchecks | 258.8 MiB | 512 MiB | 0.5 CPUs | MEDIUM |
| AIOPS | aiops-superset | 190.6 MiB | 1.0 GiB | 1.0 CPUs | MEDIUM |
| AIOPS | docuseal | 170.4 MiB | 512 MiB | 0.5 CPUs | MEDIUM |
| AIOPS | dockge | 160.8 MiB | 256 MiB | 0.5 CPUs | MEDIUM |
| AIOPS | aiops-grafana | 140.5 MiB | 512 MiB | 1.0 CPUs | MEDIUM |
| AIOPS | uptime-kuma | 114.9 MiB | 256 MiB | 0.5 CPUs | MEDIUM |
| AIOPS | aiops-changedetection | 110.5 MiB | 512 MiB | 0.5 CPUs | MEDIUM |
| AIOPS | loki | 88.5 MiB | 256 MiB | 0.5 CPUs | LOW |
| AIOPS | prediction-radar-app-db | 29.1 MiB | 2.0 GiB (existing) | -- | OK |
| AIOPS | prediction-radar-app-redis | 4.4 MiB | 512 MiB (existing) | -- | OK |
| AIOPS | aiops-ravynai-app | 29.4 MiB | 1.0 GiB (existing) | 1.0 (existing) | OK |
| COREDB | wheeler-postgres | 20.3 MiB | 1.0 GiB | 2.0 CPUs | HIGH |
| COREDB | wheeler-redis | 4.4 MiB | 256 MiB | 0.5 CPUs | HIGH |
| COREDB | wheeler-minio | 68.4 MiB | 512 MiB | 1.0 CPUs | HIGH |
| COREDB | wheeler-grafana | 123.3 MiB | 512 MiB | 1.0 CPUs | MEDIUM |
| COREDB | wheeler-uptime-kuma | 106 MiB | 256 MiB | 0.5 CPUs | MEDIUM |
| COREDB | wheeler-loki | 61.0 MiB | 256 MiB | 0.5 CPUs | LOW |
| COREDB | wheeler-prometheus | 38.2 MiB | 512 MiB | 0.5 CPUs | LOW |
| EDGE | temporal-server | 93.6 MiB | 1.0 GiB | 2.0 CPUs | CRITICAL |
| EDGE | temporal-temporal-1 | 604 KiB | 512 MiB | 1.0 CPUs | CRITICAL |
| EDGE | usesend-redis | 18.8 MiB | 256 MiB | 0.5 CPUs | CRITICAL |
| EDGE | shared-postgres-recovery | 175.4 MiB | 1.0 GiB | 2.0 CPUs | HIGH |
| EDGE | usesend | 130.8 MiB | 512 MiB | 1.0 CPUs | HIGH |
| EDGE | usesend-storage | 158.8 MiB | 512 MiB | 0.5 CPUs | HIGH |
| EDGE | private-ai-webui | 664.9 MiB | 1.5 GiB (existing) | 1.0 CPUs | OK |
| EDGE | prediction-radar-app-scheduler | 47.1 MiB | 512 MiB (existing) | -- | OK |
| EDGE | prediction-radar-app-worker | 38.5 MiB | 1.0 GiB (existing) | -- | OK |

### 2.2 Restart Policy Recommendations

| Current | Issue | Recommendation |
|---------|-------|----------------|
| temporal-server: `no` | Will not restart on crash | Change to `on-failure:5` |
| temporal-temporal-1: `unless-stopped` | 15 restarts -- crash loop | Change to `on-failure:10` + investigate root cause |
| usesend/usesend-storage/usesend-redis: `always` | Overly aggressive | Change to `unless-stopped` |
| shared-postgres-exporter: `always` | Overly aggressive | Change to `unless-stopped` |
| prediction-radar-app-api: `on-failure:5` | OK | Keep as-is |
| Others: `unless-stopped` | OK | Keep as-is |

### 2.3 Health Check Additions

Containers currently lacking HEALTHCHECK:

**AIOPS:**
- langflow -- add HTTP check on :7860/health
- dockge -- add HTTP check
- portainer -- add HTTP check on :9000
- uptime-kuma -- add HTTP check on :3001
- aiops-prometheus -- add HTTP check on :9090/-/healthy
- aiops-clickhouse -- add HTTP check on :8123/ping
- loki -- add HTTP check on :3100/ready
- promtail -- add HTTP check on :9080/ready

**COREDB (when monitoring stack is running):**
- wheeler-postgres -- add `pg_isready` check
- wheeler-redis -- add `redis-cli ping` check
- wheeler-loki -- add HTTP check on :3100/ready

**EDGE:**
- temporal-server -- add gRPC health check on :7233
- usesend -- add HTTP check
- usesend-redis -- add `redis-cli ping`
- shared-postgres-recovery -- add `pg_isready` check

---

## SECTION 3: GENERATED TEMPLATES

Templates optimized for each server are available at:

```
/root/templates/docker/
  AIOPS-optimized-docker-compose.yml
  COREDB-optimized-docker-compose.yml
  COREDB-optimized-monitoring-docker-compose.yml
  EDGE-optimized-docker-compose.yml
  apply-docker-optimizations.sh
```

These templates include:
- Resource limits (mem_limit / cpus) for all containers
- Restart policy corrections
- Health check additions
- Logging driver configuration (`json-file` with `max-size: 10m`, `max-file: 3`)
- Port binding recommendations (localhost vs 0.0.0.0)

---

## SECTION 4: SAFE APPLY SCRIPT

The script at `/root/templates/docker/apply-docker-optimizations.sh` provides a safe, incremental approach:

1. **Backup:** Creates timestamped backups of all existing compose files
2. **Dry-run:** Uses `docker compose config` to validate new compose files before deployment
3. **Per-server deployment:** Each server is handled independently
4. **Rollback:** If any deployment fails, reverts to backups
5. **Verify:** Runs `docker ps` and `docker stats --no-stream` after deployment to confirm health

The script is **non-destructive** -- it deploys alongside existing configurations, not overwriting them, and only applies changes when confirmed.

---

## SECTION 5: QUICK WINS (Non-Disruptive)

These actions can be performed without restarting containers:

### 5.1 Immediate (no restart needed)

```bash
# AIOPS: Prune build cache (3.35 GB reclaimable)
ssh root@5.78.140.118 "docker builder prune -f"

# AIOPS: Remove orphaned volume
ssh root@5.78.140.118 "docker volume rm monitoring_uptime-kuma-data"

# AIOPS: Remove duplicate langflow image (5.5 GB)
ssh root@5.78.140.118 "docker rmi langflowai/langflow:latest"

# EDGE: Prune unused images (estimated 10+ GB reclaimable)
ssh root@187.77.148.88 "docker image prune -a --filter 'until=168h' -f"
```

### 5.2 Requires Small Changes (restart container only)

```bash
# AIOPS: Add log rotation to portainer, dockge, uptime-kuma
# (Update compose file and run: docker compose up -d <service>)

# COREDB: Add log rotation to all 3 running containers
# (Update compose file and run: docker compose up -d)
```

---

## SECTION 6: RISK ASSESSMENT

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| temporal-server CPU runaway | High | High | Add CPU limit, monitor, add restart policy |
| usesend-redis CPU anomaly | Medium | Medium | Investigate, add CPU limit |
| COREDB unbounded log growth | High | Low (low disk usage currently) | Add log rotation |
| AIOPS unbounded log growth (4 containers) | Medium | Medium | Add log rotation |
| temporal crash loop (15 restarts) | High | Medium | Change restart policy, investigate |
| Exposed database ports | Medium | Critical | Bind to localhost or firewall |
| Portainer exposed to world | Low | Critical | Move behind reverse proxy with auth |

---

## SECTION 7: IMPLEMENTATION ORDER

### Phase 3a -- Fix Critical Issues (Week 1)

1. EDGE: Add CPU/memory limits to temporal-server and usesend-redis
2. EDGE: Change temporal-server restart policy from `no` to `on-failure:5`
3. EDGE: Investigate temporal-temporal-1 crash loop (15 restarts)
4. COREDB: Add log rotation to all 3 containers

### Phase 3b -- Resource Governance (Week 2)

1. AIOPS: Add resource limits to top RAM consumers (clickhouse, langflow)
2. AIOPS: Add log rotation to 4 containers without it
3. COREDB: Add resource limits to postgres, redis, minio
4. EDGE: Add resource limits to shared-postgres-recovery, usesend

### Phase 3c -- Hardening (Week 3-4)

1. All servers: Review port bindings, bind databases to localhost
2. All servers: Add HEALTHCHECK to containers without it
3. EDGE: Prune unused images and compose files
4. AIOPS: Clean up staging skeleton compose files

---

## APPENDIX A: COMPLETE CONTAINER INVENTORY

### AIOPS (25 containers)

| # | Container Name | Image | Status |
|---|---------------|-------|--------|
| 1 | loki | grafana/loki:main-2e3da9a | Running |
| 2 | promtail | grafana/promtail:latest | Running |
| 3 | docuseal | docuseal/docuseal:latest | Running |
| 4 | docuseal-redis | redis:7-alpine | Running |
| 5 | langflow | langflowai/langflow:1.0.19 | Running |
| 6 | frgops-standby | postgres:16 | Running |
| 7 | hostinger-health-exporter | python:3.12-alpine | Running |
| 8 | prediction-radar-app-web | prediction-radar-app-web:latest | Running |
| 9 | prediction-radar-dashboard-v2 | prediction-radar-app-dashboard-v2:latest | Running |
| 10 | prediction-radar-app-api | prediction-radar-app-api:latest | Running |
| 11 | prediction-radar-app-db | postgres:16 | Running |
| 12 | prediction-radar-app-redis | redis:7 | Running |
| 13 | aiops-ravynai-app | ravynai-opportunity-graph-app:latest | Running |
| 14 | aiops-ravynai-postgres | postgis/postgis:16-3.4 | Running |
| 15 | aiops-superset | apache/superset:4.1.1 | Running |
| 16 | aiops-clickhouse | clickhouse/clickhouse-server:24.3 | Running |
| 17 | aiops-healthchecks | lscr.io/linuxserver/healthchecks:latest | Running |
| 18 | aiops-changedetection | ghcr.io/dgtlmoon/changedetection.io:latest | Running |
| 19 | aiops-grafana | grafana/grafana:latest | Running |
| 20 | aiops-prometheus | prom/prometheus:latest | Running |
| 21 | netdata | netdata/netdata:latest | Running |
| 22 | portainer | portainer/portainer-ce:latest | Running |
| 23 | dockge-test-nginx | nginx:latest | Running |
| 24 | dockge | louislam/dockge:1 | Running |
| 25 | uptime-kuma | louislam/uptime-kuma:1 | Running |

### COREDB (3 active + 4 stopped)

| # | Container Name | Image | Status |
|---|---------------|-------|--------|
| 1 | wheeler-postgres | postgres:16 | Running |
| 2 | wheeler-redis | redis:7 | Running |
| 3 | wheeler-minio | minio/minio:latest | Running |
| 4 | wheeler-grafana | grafana/grafana:latest | Stopped |
| 5 | wheeler-prometheus | prom/prometheus:latest | Stopped |
| 6 | wheeler-loki | grafana/loki:latest | Stopped |
| 7 | wheeler-uptime-kuma | louislam/uptime-kuma:latest | Stopped |

### EDGE (11 containers)

| # | Container Name | Image | Status |
|---|---------------|-------|--------|
| 1 | temporal-temporal-1 | temporalio/auto-setup:latest | Running (15 restarts) |
| 2 | temporal-temporal-ui-1 | temporalio/ui:latest | Running |
| 3 | temporal-server | temporalio/server:latest | Running |
| 4 | private-ai-webui | ghcr.io/open-webui/open-webui:main (6.7GB) | Running |
| 5 | shared-postgres-recovery | postgres:15 | Running |
| 6 | prediction-radar-app-scheduler | prediction-radar-app-scheduler:latest | Running |
| 7 | prediction-radar-app-worker | prediction-radar-app-worker:latest | Running |
| 8 | shared-postgres-exporter | quay.io/prometheuscommunity/postgres-exporter:latest | Running |
| 9 | usesend | usesend/usesend:latest | Running |
| 10 | usesend-storage | minio/minio:latest | Running |
| 11 | usesend-redis | redis:7 | Running |

---

## APPENDIX B: CONTAINER LOG DISK USAGE (FULL)

### AIOPS
```
 18.0 MB  frgops-standby
 15.0 MB  aiops-grafana
  9.7 MB  netdata
  2.5 MB  hostinger-health-exporter
  1.8 MB  loki
  1.6 MB  aiops-changedetection
  948 KB  dockge-test-nginx
  820 KB  aiops-superset
  728 KB  uptime-kuma
  472 KB  docuseal-redis
  404 KB  aiops-prometheus
  404 KB  prediction-radar-app-api
  312 KB  prediction-radar-app-web
  300 KB  aiops-ravynai-postgres
  192 KB  promtail
```

### COREDB
```
  2.6 MB  wheeler-loki (stopped, log persisted)
  1.9 MB  wheeler-grafana (stopped, log persisted)
  588 KB  wheeler-postgres
   88 KB  wheeler-prometheus (stopped, log persisted)
   76 KB  wheeler-uptime-kuma (stopped, log persisted)
   76 KB  wheeler-redis
   44 KB  wheeler-minio
```

### EDGE
```
  7.1 MB  shared-postgres-recovery
  5.6 MB  prediction-radar-app-worker
  512 KB  usesend
  304 KB  temporal-server
  256 KB  prediction-radar-app-scheduler
   88 KB  usesend-storage
   80 KB  usesend-redis
   52 KB  private-ai-webui
   48 KB  temporal-temporal-ui-1
   44 KB  shared-postgres-exporter
   40 KB  temporal-temporal-1
```

---

## APPENDIX C: CHECKLIST FOR EXECUTION

- [ ] Phase 3a.1 -- EDGE temporal-server: add `mem_limit: 1g`, `cpus: "2.0"`, restart `on-failure:5`
- [ ] Phase 3a.2 -- EDGE usesend-redis: add `mem_limit: 256m`, `cpus: "0.5"`, investigate CPU anomaly
- [ ] Phase 3a.3 -- EDGE temporal-temporal-1: change to `on-failure:10`, investigate 15 restarts
- [ ] Phase 3a.4 -- COREDB: add logging `max-size: 10m, max-file: 3` to all 3 containers
- [ ] Phase 3b.1 -- AIOPS: add `mem_limit: 3g`, `cpus: "4.0"` to clickhouse
- [ ] Phase 3b.2 -- AIOPS: add `mem_limit: 2g`, `cpus: "2.0"` to langflow
- [ ] Phase 3b.3 -- AIOPS: add log rotation to portainer, dockge, dockge-test-nginx, uptime-kuma
- [ ] Phase 3b.4 -- COREDB: add `mem_limit` to postgres (1g), redis (256m), minio (512m)
- [ ] Phase 3b.5 -- EDGE: add resource limits to shared-postgres-recovery, usesend, usesend-storage
- [ ] Phase 3c.1 -- All servers: review port bindings (0.0.0.0 vs 127.0.0.1)
- [ ] Phase 3c.2 -- All servers: add HEALTHCHECK instructions
- [ ] Phase 3c.3 -- EDGE: prune unused images (`docker image prune -a`)
- [ ] Phase 3c.4 -- AIOPS: cleanup staging skeleton files under /opt/stacks/
- [ ] Phase 3c.5 -- AIOPS: remove orphaned volume `monitoring_uptime-kuma-data`
- [ ] Phase 3c.6 -- AIOPS: remove duplicate langflow:latest image
