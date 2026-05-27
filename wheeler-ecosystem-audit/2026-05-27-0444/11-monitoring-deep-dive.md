# Monitoring Deep Dive
**Date:** 2026-05-27 04:44 UTC
**Scope:** Full Wheeler ecosystem monitoring stack audit
**AIOPS Host:** 5.78.140.118 (Hetzner)
**CoreDB:** 100.118.166.117 (Hetzner)
**Hostinger:** 100.98.163.17

---

## 1. PROMETHEUS TARGETS: 12/12 UP

| Health | Job | Instance | Location | Type | Errors |
|--------|-----|----------|----------|------|--------|
| UP | aiops-cadvisor | aiops-cadvisor:8080 | hetzner | cadvisor | - |
| UP | aiops-node | aiops-node-exporter:9100 | hetzner | node | - |
| UP | coredb-node | 100.118.166.117:9100 | hetzner | node | - |
| UP | coredb-postgres | coredb-postgres-exporter:9187 | hetzner | postgres | - |
| UP | coredb-redis | coredb-redis-exporter:9121 | hetzner | redis | REDIS DOWN |
| UP | edge-cadvisor | 100.98.163.17:9099 | hostinger | cadvisor | - |
| UP | edge-docker | 100.98.163.17:9100 | hostinger | docker_host | - |
| UP | hetzner-aiops | localhost:9090 | ? | prometheus | - |
| UP | hostinger-health | hostinger-health-exporter:9091 | hostinger | health_exporter | - |
| UP | hostinger-node | 100.98.163.17:9100 | hostinger | node | - |
| UP | hostinger-services | 100.98.163.17:8002 | hostinger | agent_service | - |
| UP | pushgateway | pushgateway:9091 | hetzner | pushgateway | - |

**Scrape config file:** Docker volume at `/etc/prometheus/prometheus.yml` in aiops-prometheus container

### What each job monitors:
- **aiops-cadvisor** -- Container-level CPU/memory/network/disk for all Docker containers on AIOPS Hetzner
- **aiops-node** -- Host-level CPU/memory/disk/network for AIOPS Hetzner server
- **coredb-node** -- Host-level metrics for CoreDB server (100.118.166.117:9100)
- **coredb-postgres** -- PostgreSQL health, connections, wal, replication lag (CoreDB)
- **coredb-redis** -- Redis health (currently FAILING -- cannot connect to Redis)
- **edge-cadvisor** -- Container-level metrics for Hostinger Docker host
- **edge-docker** -- Host-level metrics for Hostinger (same IP, same node_exporter, different job label)
- **hetzner-aiops** -- Prometheus self-metrics (scrapes itself)
- **hostinger-health** -- Custom health check exporter on AIOPS (proxied? container)
- **hostinger-node** -- Host-level metrics for Hostinger (duplicate of edge-docker with different labels)
- **hostinger-services** -- Agent service health on Hostinger
- **pushgateway** -- Accepts pushed custom metrics (PM2, certs, dead man's switch)

---

## 2. ACTIVE ALERTS (FIRING / PENDING)

### CRITICAL: RedisDown -- FIRING since 2026-05-27T00:01:00 (>5 hours)
- **Alert:** `redis_up == 0` for >120s
- **Severity:** critical
- **Root cause:** coredb-redis-exporter container cannot connect to its Redis instance
- **Evidence in logs:** "Couldn't connect to redis instance" repeating every ~30s
- **Impact:** No Redis health monitoring; Redis itself may be degraded
- **Action needed:** Verify Redis connection string in redis-exporter config or Redis container health

### PENDING: ContainerDown -- PENDING since 2026-05-27T04:58:30
- **Alert:** `time() - container_last_seen > 120` for >120s
- **Severity:** critical
- **Container:** `/system.slice/frg-nginx-watchdog.service` on hostinger cadvisor
- **Likely cause:** systemd service that has stopped or been removed -- not a Docker container

### Alert Rule Summary (from /etc/prometheus/alert-rules.yml)

| Rule | Severity | Duration | State | Purpose |
|------|----------|----------|-------|---------|
| ServiceDown | critical | 120s | inactive | Generic `up == 0` for any scraped target |
| PostgreSQLDown | critical | 120s | inactive | PG health check via pg_up |
| RedisDown | critical | 120s | **FIRING** | Redis health check via redis_up |
| HighMemoryUsage | warning | 300s | inactive | Container memory >85% of limit |
| ContainerDown | critical | 120s | **PENDING** | Containers not seen for >120s |
| DiskSpaceLow | warning | 600s | inactive | Root filesystem <10% free |
| PM2ProcessDown | critical | 120s | inactive | PM2 process not in "online" status |
| PM2RestartLoop | critical | 120s | inactive | PM2 restarts >0.05/sec over 5min |
| PM2HighMemory | warning | 300s | inactive | PM2 process >1000MB |
| NodeExporterDown | critical | 180s | inactive | Any node_exporter job down |
| CertExpirySoon | warning | 3600s | inactive | SSL cert <14 days remaining |
| CertExpiryCritical | critical | 3600s | inactive | SSL cert <5 days remaining |
| DeadMansSwitch | critical | 120s | inactive | No heartbeat >300s |
| OOMKillDetected | critical | 60s | inactive | OOM killer activity detected |
| FilesystemFillup | warning | 300s | inactive | Predicted disk full in 24h |

---

## 3. CUSTOM METRICS (PUSHGATEWAY)

### PM2 Metrics -- PUSHED (89 processes, all online)
- `pm2_status`, `pm2_restarts`, `pm2_memory_mb`, `pm2_cpu_percent` all being pushed
- All 85 PM2 processes return `status=online`
- FRGCRM-API has 2 restarts, executive-dashboard-api has 11, ravynai-og-scheduler has 10, ravynai-og-sync has 4
- PM2ProcessDown and PM2RestartLoop alerts can fire on these metrics -- this is working correctly

### SSL Cert Metrics -- 1 domain only
- Only `eligibility.predictionradar.app` (89 days remaining) is being tracked
- **GAP:** All other domains (predictionradar.app, fundsrecoverygroup.com, and all subdomains) are NOT monitored for cert expiry
- CertExpiry rules exist but will never fire for unmonitored domains

### Dead Man's Switch -- WORKING
- `dead_mans_switch_last_heartbeat` metric is being pushed
- Value is 1779858061 (current Unix timestamp), so heartbeat is alive
- Alert rule `DeadMansSwitch` will fire if heartbeat stops for >300s

---

## 4. LOKI / LOG SHIPPING -- BROKEN

- **Loki HTTP ready:** Yes (HTTP 200 on :3100)
- **Loki labels:** EMPTY -- no log streams being received
- **Promtail error:** Cannot resolve hostname `loki:3100` via Docker DNS (127.0.0.11:53)
- **Root cause:** Promtail config uses `loki` as hostname but the container is named `aiops-loki`. Docker DNS does not resolve `loki` to `aiops-loki`.
- **Impact:** Zero logs being shipped. Loki is running but empty. No log-based alerting possible.
- **Severity:** P1 -- This is a fundamental blind spot for any log-based investigations

**Fix required:** Change promtail config from `http://loki:3100` to `http://aiops-loki:3100`

---

## 5. GRAFANA -- NO DATASOURCES, NO DASHBOARDS

- **Grafana running:** Yes, HTTP 302 on :3002 (login page works)
- **Provisioning datasources directory:** EXISTS but EMPTY (`/etc/grafana/provisioning/datasources/` has only `.` and `..`)
- **Provisioning dashboards directory:** Does not exist
- **No datasources configured** via provisioning (may exist in grafana.db from UI, but not verifiable without auth)
- **Comparison:** prediction-radar-grafana instance HAS provisioning (`/etc/grafana/provisioning/datasources/prometheus.yml`)
- **Default dashboards available** at `/usr/share/grafana/public/dashboards/` but not provisioned
- **grafana.db exists** at `/var/lib/grafana/grafana.db` (1.5MB) -- may have UI-created dashboards
- **Impact:** Grafana is a blank monitoring UI with no pre-built views. Operational visibility relies entirely on Prometheus query console.

---

## 6. UPTIMEKUMA -- ONLY 3 MONITORS

| ID | Name | URL | Active | Status |
|----|------|-----|--------|--------|
| 1 | 1Panel-Wheelerops | http://5.78.140.118:8090/wheelerops | YES | Failing intermittently (timeouts) |
| 2 | FRG | https://fundsrecoverygroup.com | YES | OK |
| 6 | Dockge | http://5.78.140.118:5001 | YES | Failing intermittently (timeouts) |

**Active monitors:** 3 out of 3 total (no inactive monitors)

**Critical GAPS in uptime monitoring:**

- **predictionradar.app** -- NOT MONITORED (main domain + all subdomains: app., api., eligibility., etc.)
- **aiops-superset** (:8088) -- NOT MONITORED
- **langflow** (:7860) -- NOT MONITORED
- **open-webui** (:3000) -- NOT MONITORED
- **docuseal** (:3010) -- NOT MONITORED
- **usesend** (:3007) -- NOT MONITORED
- **temporal-server** (:7233) -- NOT MONITORED
- **temporal-ui** (:8089) -- NOT MONITORED
- **aiops-healthchecks** (:3130) -- NOT MONITORED
- **netdata** (:19999) -- NOT MONITORED
- **changedetection** (:5000) -- NOT MONITORED
- **ravynai-app** (:8007) -- NOT MONITORED
- **ecosystem-graph (Neo4j)** -- NOT MONITORED
- **prometheus** (:9090) -- NOT MONITORED (ironic)
- **grafana** (:3002) -- NOT MONITORED
- **alertmanager** (:9093) -- NOT MONITORED

**17 services running without uptime monitoring.**

UptimeKuma runs in HA mode with a `uptime-kuma-backup` container (on `:3001` without host port, both share same DB).

---

## 7. NETDATA -- RUNNING, 0 ALARMS

- Netdata v2.10 running on :19999
- Zero alarms triggered
- No integration with Prometheus -- operates as standalone dashboard
- Not monitored by UptimeKuma

---

## 8. HEALTHCHECKS (CRON MONITORING) -- RUNNING

- Container `aiops-healthchecks` on :3130
- Cannot reach API due to ALLOWED_HOSTS restriction (Django security)
- Cannot verify what cron checks are configured without proper HTTP_HOST header
- Backups are running (prediction-radar-app-db-backup-1 creates SQL dumps daily)
- `uptime-kuma-backup` and `netdata-backup` containers exist but purpose unclear (likely data volumes)

---

## 9. BLIND SPOTS -- COMPLETE CATALOG

### BLIND SPOT 1: Redis Health (CRITICAL - ACTIVE)
- **Details:** RedisDown alert has been firing for >5 hours
- **Impact:** No Redis monitoring. If Redis is down, session caching, rate limiting, and queue systems may be affected
- **Remediation:** Fix redis-exporter connection string

### BLIND SPOT 2: Log Shipping (CRITICAL - ACTIVE)
- **Details:** Promtail cannot reach Loki -- DNS resolution issue
- **Impact:** Zero log aggregation. No log-based alerting, no log correlation for incident response
- **Remediation:** Fix promtail config endpoint from `loki` to `aiops-loki`

### BLIND SPOT 3: Grafana Visualization Layer
- **Details:** No provisioned datasources, no provisioned dashboards
- **Impact:** No visual monitoring surface. Operational teams have no dashboards
- **Remediation:** Add Prometheus and Loki datasource provisioning YAML, create baseline dashboards

### BLIND SPOT 4: predictionradar.app Uptime
- **Details:** Zero uptime monitors for predictionradar.app domain or any subdomain
- **Impact:** Undetected outages of the core revenue-facing application
- **Remediation:** Add UptimeKuma monitors for all predictionradar.app endpoints

### BLIND SPOT 5: SSL Certificate Expiry
- **Details:** Only 1 domain (eligibility.predictionradar.app) tracked. All other domains untracked.
- **Impact:** Expired certs = service outages that could have been prevented
- **Remediation:** Push cert metrics for predictionradar.app, fundsrecoverygroup.com, and all subdomains

### BLIND SPOT 6: Backup Failure Alerts
- **Details:** Daily DB backups run (verified from logs) but no monitoring metric or alert for backup failure
- **Impact:** Silent backup failures would not be detected until data loss occurs
- **Remediation:** Push backup success/fail metric to pushgateway, add alert rule

### BLIND SPOT 7: CoreDB Missing Container Metrics
- **Details:** CoreDB has node_exporter and database exporters but NO cadvisor
- **Impact:** No container-level CPU/memory/disk visibility for CoreDB
- **Remediation:** Deploy cadvisor on CoreDB

### BLIND SPOT 8: Docker Daemon Health
- **Details:** No Docker engine metrics scraped anywhere
- **Impact:** Docker daemon crashes or hangs not detectable
- **Remediation:** Add Docker daemon metrics endpoint (requires Docker socket exposure or docker_exporter)

### BLIND SPOT 9: No Blackbox/Synthetic Monitoring
- **Details:** No `blackbox_exporter` deployed for HTTP/TCP/ICMP probes
- **Impact:** No external-service-mindset probing; Prometheus scrapes from local Docker network
- **Remediation:** Deploy blackbox_exporter, add probe targets for all public services

### BLIND SPOT 10: Missing Service-Specific Metrics
- **Details:** No scrape targets for ClickHouse, Grafana, Loki, Temporal, Langflow, Superset, etc.
- **Impact:** These services could be degraded without metrics-based detection
- **Remediation:** Add scrape targets for services that expose /metrics endpoints

### BLIND SPOT 11: Docker Volume Disk Usage
- **Details:** Node_exporter tracks host filesystem but not Docker volume mount points
- **Impact:** Volume-specific disk fills (e.g., postgres data directory) not separately alertable
- **Remediation:** Monitor Docker volumes via cadvisor or custom volume-exporter

### BLIND SPOT 12: Hostinger Container Health
- **Details:** frg-nginx-watchdog.service showing ContainerDown (pending) on hostinger
- **Impact:** May indicate a systemd service stopped; need investigation
- **Remediation:** Verify frg-nginx-watchdog.service status on Hostinger

---

## 10. RECOMMENDED ACTIONS (PRIORITIZED)

### P0 -- Fix immediately
1. **Fix RedisDown** -- Reconfigure coredb-redis-exporter connection string
   ```
   docker exec coredb-redis-exporter env | grep REDIS
   docker logs coredb-redis-exporter --tail 50
   ```

2. **Fix Promtail DNS** -- Change `loki:3100` to `aiops-loki:3100` in promtail config
   ```
   docker exec promtail cat /etc/promtail/promtail.yaml | grep -i loki
   # Then edit and restart: docker restart promtail
   ```

### P1 -- Fix within 24 hours
3. **Add Grafana datasource provisioning** -- Create YAML at `/etc/grafana/provisioning/datasources/prometheus.yml`
   ```yaml
   apiVersion: 1
   datasources:
     - name: Prometheus
       type: prometheus
       url: http://aiops-prometheus:9090
       access: proxy
       isDefault: true
     - name: Loki
       type: loki
       url: http://aiops-loki:3100
       access: proxy
   ```

4. **Add UptimeKuma monitors for predictionradar.app** (via UptimeKuma API or UI):
   - `https://predictionradar.app`
   - `https://app.predictionradar.app`
   - `https://api.predictionradar.app`
   - `https://eligibility.predictionradar.app`

### P2 -- Fix within 1 week
5. **Deploy SSL cert exporter** to check all domains (predictionradar.app wildcard, fundsrecoverygroup.com)

6. **Add backup success/fail pushgateway metric** to the backup-verification PM2 process

7. **Add UptimeKuma monitors for all internal services:**
   - `http://5.78.140.118:3000` (Open WebUI)
   - `http://5.78.140.118:8088` (Superset)
   - `http://5.78.140.118:7860` (Langflow)
   - `http://5.78.140.118:3010` (Docuseal)
   - `http://5.78.140.118:3007` (Usesend)
   - `http://5.78.140.118:8089` (Temporal UI)
   - `http://5.78.140.118:3130` (Healthchecks)
   - `http://5.78.140.118:5000` (ChangeDetection)
   - `http://5.78.140.118:8007` (RavynAI)

### P3 -- Fix within 1 month
8. **Deploy blackbox_exporter** for synthetic monitoring
9. **Create Grafana dashboards** (system overview, container overview, PM2, alerts)
10. **Add CoreDB cadvisor** for container-level monitoring of CoreDB
11. **Add Docker daemon metrics** via docker_exporter or Prometheus Docker SD
12. **Add ClickHouse and other service-specific scrape targets**

---

## 11. MONITORING COVERAGE SCORECARD

| Category | Status | Score |
|----------|--------|-------|
| Prometheus targets | 12/12 UP | 100% |
| Node metrics (3 servers) | all covered | 100% |
| Container metrics | Hetzner + Hostinger, missing CoreDB | 66% |
| Database metrics (PG) | CoreDB covered, missing Hostinger | 50% |
| Redis monitoring | Target UP but connection FAILING | 0% (broken) |
| PM2 process metrics | All 89 processes pushed | 100% |
| SSL cert expiry | 1 of ~10 domains | 10% |
| Uptime monitoring (UptimeKuma) | 3 of ~20 services | 15% |
| Log aggregation (Loki) | Running but NO logs flowing | 0% (broken) |
| Grafana visualization | Running, no dashboards provisioned | 0% |
| Backup monitoring | No metrics, no alerts | 0% |
| Blackbox/synthetic probing | Not deployed | 0% |
| Dead man's switch | Working | 100% |

**Overall Monitoring Health: ~42%** (degraded by 3 critical failures: RedisDown, Loki dead, Grafana blank)

---

## 12. COMMANDS TO ADD MISSING MONITORS

### Add UptimeKuma monitors (via websocket API -- use `docker exec` with API key or UI)
UptimeKuma uses a WebSocket API. To add monitors programmatically, generate an API key in the UptimeKuma UI under Settings > API Keys.

### Add Prometheus scrape target (edit prometheus config and reload)
```bash
# Example: Add a blackbox exporter scrape config to /etc/prometheus/prometheus.yml
docker exec aiops-prometheus sh -c "cat >> /etc/prometheus/prometheus.yml << 'CONF'

  - job_name: 'blackbox-http'
    scrape_interval: 30s
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - https://predictionradar.app
        - https://fundsrecoverygroup.com
        - https://app.predictionradar.app
        - https://api.predictionradar.app
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
CONF
docker exec aiops-prometheus kill -HUP 1"
```

### Add PM2 metric pushgateway (already working -- no action needed)
### Fix RedisDown
```bash
docker exec coredb-redis-exporter sh -c "echo 'REDIS_ADDR=redis:6379' > /env && kill 1"
# Or check the actual redis container name and network
docker network ls | grep coredb
docker inspect coredb-redis-exporter --format '{{json .Config.Env}}' | tr ',' '\n'
```

### Fix promtail DNS
```bash
# Check current config and fix
docker exec promtail cat /etc/promtail/promtail.yaml
# If 'loki' appears as hostname, rebuild container with correct config
# or use docker exec to edit and docker restart promtail
```

---

*Report generated by Monitoring Intelligence agent during ecosystem audit 2026-05-27-0444*
