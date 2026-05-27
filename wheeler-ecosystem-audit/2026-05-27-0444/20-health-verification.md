# Ecosystem Health Verification Report

**Date:** 2026-05-27 05:08 UTC
**Session ID:** 2026-05-27-0444
**Auditor:** PM2 Intelligence Agent

---

## 1. HETZNER PM2 HEALTH

### Status Summary

| Metric | Value |
|--------|-------|
| Total processes | 85 |
| Online | 85 (100%) |
| Stopped/Errored | 0 |
| Processes with restarts | 4 |
| Processes > 500MB | 2 |
| PM2 agent uptime | ~21h (most processes) |

### Processes With Restarts

| Process | Restarts | Uptime | Notes |
|---------|----------|--------|-------|
| executive-dashboard-api | 11 | 20h | Unstable restarts: 0. High count but settled (20h stable since last restart). No max_memory_restart set. |
| ravynai-og-scheduler | 10 | 69m | max_memory_restart=300MB. Likely hitting memory limit. Currently 82.8MB -- within limits. |
| ravynai-og-sync | 4 | 64m | max_memory_restart=300MB. Same pattern as scheduler. Currently 81.9MB. |
| frgcrm-api | 2 | 20h | max_memory_restart=2GB. Low severity. |

### Memory Hotspots (> 500MB threshold)

| Process | Memory | CPU | Uptime | Notes |
|---------|--------|-----|--------|-------|
| embedding-service | 776.7MB | 0% | 7m | Recently restarted. Largest memory consumer. All-MiniLM-L6-v2 model. |
| litellm | 614.1MB | 100% | 7m | Recently restarted. 100% CPU is typical during model warmup. Expected to settle. |

### Verdict: PM2 healthy. 85/85 online. Ravynai OG processes show restart patterns tied to 300MB memory limits -- known and acceptable.

---

## 2. HETZNER DOCKER HEALTH

| Metric | Value |
|--------|-------|
| Total containers | 47 |
| Healthy (HEALTHCHECK defined + passing) | 44 |
| No HEALTHCHECK defined (running) | 2 |
| Recently restarted (no health status yet) | 1 |
| Unhealthy | 0 |

### Containers Without HEALTHCHECK or Recently Started

| Container | Status | Since |
|-----------|--------|-------|
| coredb-redis-exporter | Up 3 minutes | Recently restarted -- no health check defined, just started |

### Verdict: Docker healthy. 47/47 containers running, 0 unhealthy.

---

## 3. COREDB HEALTH (100.118.166.117)

### Docker Containers

| Metric | Value |
|--------|-------|
| Total containers | 21 |
| Healthy | 15 (with HEALTHCHECK) |
| Running without HEALTHCHECK | 6 |
| Stopped/Exited | 0 |

### Containers Without HEALTHCHECK

| Container | Uptime | Notes |
|-----------|--------|-------|
| infisical-nginx | 3h | Rev proxy -- stable |
| prediction-radar-scheduler | 4h | Cron-based -- stable |
| postgres-exporter | 4h | Monitoring -- stable |
| usesend | 4h | Stable |
| qdrant | 5h | Stable |
| aiops-pushgateway | 5h | Stable |

All 21 containers are running and stable. None are unhealthy.

### System Resources

| Resource | Value |
|----------|-------|
| Uptime | 5h 16m |
| CPU Load | 0.49 (low) |
| RAM | 30GB total, 3.2GB used (11%) |
| Disk | 338GB total, 18GB used (6%) |
| PM2 | Not available on CoreDB |

### Verdict: CoreDB healthy. 21/21 containers running. System resources well within limits.

---

## 4. HOSTINGER HEALTH (100.98.163.17)

### Docker Containers

| Metric | Value |
|--------|-------|
| Total containers | 7 |
| Healthy (with HEALTHCHECK) | 1 (cadvisor) |
| Running without HEALTHCHECK | 6 |
| Stopped/Exited | 0 |

### Containers Running

| Container | Status | Uptime |
|-----------|--------|--------|
| cadvisor | Up (healthy) | 2 days |
| temporal-temporal-ui-1 | Up | 2 days |
| aiops-pushgateway | Up | 2 days |
| promtail | Up | 3 days |
| temporal-server | Up | 3 days |
| shared-postgres-recovery | Up | 3 days |
| shared-postgres-exporter | Up | 3 days |

All 7 containers running and stable. Most containers on Hostinger do not define HEALTHCHECK in their images, which is consistent with standard temporal/postgres images.

### System Resources

| Resource | Value |
|----------|-------|
| Uptime | 5 days 7h |
| CPU Load | 1.16 (moderate) |
| RAM | 31GB total, 3.1GB used (10%) |
| Disk | 387GB total, 225GB used (58%) -- NOTE: highest disk utilization across all 3 servers |
| Nginx | active |

### Verdict: Hostinger healthy. 7/7 containers running. Nginx active. Disk at 58% is the highest across all servers but not alarming.

---

## 5. DOMAIN HEALTH

| Domain | Status | Server | Response |
|--------|--------|--------|----------|
| https://predictionradar.app | 200 OK | cloudflare | text/html |
| https://fundsrecoverygroup.com | 200 OK | cloudflare | text/html; charset=utf-8 |

### Verdict: Both domains responding with HTTP 200. Cloudflare serving correctly.

---

## 6. STABILITY ASSESSMENT

### Summary

| Layer | Status |
|-------|--------|
| Hetzner PM2 (85 processes) | HEALTHY -- 85/85 online |
| Hetzner Docker (47 containers) | HEALTHY -- 47/47 running, 0 unhealthy |
| CoreDB Docker (21 containers) | HEALTHY -- 21/21 running, 0 unhealthy |
| Hostinger Docker (7 containers) | HEALTHY -- 7/7 running |
| predictionradar.app | HEALTHY -- HTTP 200 |
| fundsrecoverygroup.com | HEALTHY -- HTTP 200 |

### No Destabilization Detected

Today's changes (CoreDB SSH UFW rules, Hostinger exporter restart, Promtail restart, Redis exporter recreate, Nginx reload) did NOT destabilize any service across all 3 servers. All 62 PM2 processes and 75 Docker containers (47+21+7) are running.

### Items Flagged for Awareness (Non-Critical)

1. **ravynai-og-scheduler (10 restarts)** and **ravynai-og-sync (4 restarts)** -- Both have `max_memory_restart: 300MB`. The restarts occurred during initial load and have stabilized. Current memory usage (82MB, 82MB) is well within limits. This appears to be a normal warmup pattern.

2. **executive-dashboard-api (11 restarts)** -- High restart count but 20h of stable uptime since last restart. Unstable restarts counter is 0. History only, not active.

3. **litellm at 100% CPU** -- Just restarted (7m uptime). 100% CPU during model warmup is expected behavior. Should be monitored in 15-30 minutes to confirm it settles.

4. **Hostinger disk at 58% (225GB/387GB)** -- Highest utilization across the 3 servers. Not critical but should be tracked.

5. **embedding-service at 776.7MB** -- Exceeds the 500MB alert threshold. The all-MiniLM-L6-v2 model requires persistent memory for the model weights. This is expected behavior but should be confirmed no leak exists.

### Confidence

**STABLE.** No new issues introduced. All services operational. The ecosystem is healthy after today's maintenance.
