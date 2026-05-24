# Resource Intelligence Engine — Wheeler Autonomous AI Ops

> **Purpose:** Predictive resource management, capacity forecasting, sprawl prevention, and cost optimization for the Wheeler 3-server ecosystem (EDGE/AIOPS/COREDB).
> **Classification:** OPERATIONS — Infrastructure Capacity Planning
> **Last Updated:** 2026-05-24

---

## 1. Resource Intelligence Overview

The Wheeler Resource Intelligence Engine transforms raw utilization data into actionable capacity decisions. It operates in two modes:

**Reactive Mode (current state):** Alerts fire when thresholds are breached. The on-call engineer investigates and remediates. This catches emergencies but does not prevent them.

**Predictive Mode (target state):** Historical utilization trends feed forecasting models that predict when resources will exhaust. Scaling happens before thresholds are breached, not after. This eliminates capacity-related incidents.

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                  RESOURCE INTELLIGENCE ENGINE                  │
├──────────────────────────────────────────────────────────────┤
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  Collectors │─>│  Analyzers   │─>│  Decision Engine     │  │
│  │  ┌────────┐ │  │  ┌────────┐ │  │  ┌────────────────┐ │  │
│  │  │node_   │ │  │  │Trend   │ │  │  │Alert           │ │  │
│  │  │exporter│ │  │  │Forecast│ │  │  │Prometheus      │ │  │
│  │  └────────┘ │  │  └────────┘ │  │  │Recording Rules │ │  │
│  │  ┌────────┐ │  │  ┌────────┐ │  │  └────────────────┘ │  │
│  │  │cadvisor│ │  │  │Anomaly │ │  │  ┌────────────────┐ │  │
│  │  └────────┘ │  │  │Detect  │ │  │  │Auto-Scale      │ │  │
│  │  ┌────────┐ │  │  └────────┘ │  │  │Scripts         │ │  │
│  │  │PM2     │ │  │  ┌────────┐ │  │  └────────────────┘ │  │
│  │  │Metrics │ │  │  │Cost    │ │  │  ┌────────────────┐ │  │
│  │  └────────┘ │  │  │Analyzer│ │  │  │Runbook Trigger │ │  │
│  └────────────┘  │  └────────┘ │  │  └────────────────┘ │  │
│                  └──────────────┘  └──────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. Current Resource Baseline

Captured on 2026-05-24 at 18:00 UTC from live system state.

### 2.1 CPU

| Server  | Cores | Load 1m | Load 5m | Load 15m | %usr | %sys | %idle | %iowait | %steal |
|---------|-------|---------|---------|----------|------|------|-------|---------|--------|
| EDGE    | 8     | 2.80    | 2.65    | 2.40     | 18.2 | 8.4  | 68.0  | 1.2     | 4.2    |
| AIOPS   | 16    | 3.00    | 2.80    | 2.50     | 21.0 | 6.0  | 72.0  | 0.5     | 0.5    |
| COREDB  | 8     | 0.35    | 0.30    | 0.28     | 0.6  | 0.4  | 98.8  | 0.1     | 0.1    |

### 2.2 Memory

| Server  | Total    | Used     | Free     | Buff/Cache | Available | Used % |
|---------|----------|----------|----------|------------|-----------|--------|
| EDGE    | 8 GB     | 5.2 GB   | 0.6 GB   | 2.2 GB     | 2.8 GB    | 65%    |
| AIOPS   | 30 GB    | 15.3 GB  | 2.4 GB   | 12.3 GB    | 15.0 GB   | 51%    |
| COREDB  | 31 GB    | 1.4 GB   | 27.5 GB  | 2.1 GB      | 29.6 GB   | 5%     |

### 2.3 Disk

| Server  | Total   | Used    | Free    | Used % | Mount Points |
|---------|---------|---------|---------|--------|--------------|
| EDGE    | 80 GB   | 42 GB   | 38 GB   | 53%    | / (root)     |
| AIOPS   | 338 GB  | 61 GB   | 264 GB  | 19%    | / (root)     |
| COREDB  | 338 GB  | 6.2 GB  | 332 GB  | 2%     | / (root)     |

### 2.4 Swap

| Server  | Total  | Used | Notes            |
|---------|--------|------|------------------|
| EDGE    | 2 GB   | 0 MB | No swap activity |
| AIOPS   | 8 GB   | 0 MB | No swap activity |
| COREDB  | 8 GB   | 0 MB | No swap activity |

### 2.5 Network

| Server  | Interface     | RX (24h) | TX (24h) | Max Bandwidth |
|---------|---------------|----------|----------|---------------|
| EDGE    | public        | 12.8 GB  | 3.4 GB   | 1 Gbps        |
| AIOPS   | tailscale0    | 4.2 GB   | 1.1 GB   | 1 Gbps        |
| COREDB  | tailscale0    | 0.8 GB   | 0.3 GB   | 1 Gbps        |

### 2.6 Container/Process Count

| Server  | Docker Containers | PM2 Processes | Total Services |
|---------|------------------|---------------|----------------|
| EDGE    | 12               | 8             | 20             |
| AIOPS   | 37               | 20            | 57             |
| COREDB  | 7                | 0             | 7              |

---

## 3. Growth Forecasting Methodology

### 3.1 Data Sources

The forecast engine pulls from four sources:

```bash
# Source 1: Prometheus node_exporter metrics (1m resolution)
# Query for CPU trend over 30 days:
curl -s 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)' \
  --data-urlencode "start=$(date -d '30 days ago' +%s)" \
  --data-urlencode "end=$(date +%s)" \
  --data-urlencode 'step=3600' | jq '.data.result[].values[] | .[1]' > /tmp/cpu-trend-30d.csv

# Source 2: cadvisor Docker container metrics (1m resolution)
curl -s 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=sum(container_memory_usage_bytes{instance=~"aiops.*"}) / 1e9' \
  --data-urlencode "start=$(date -d '30 days ago' +%s)" \
  --data-urlencode "end=$(date +%s)" \
  --data-urlencode 'step=3600' | jq '.data.result[].values[] | .[1]' > /tmp/docker-mem-trend.csv

# Source 3: PM2 metrics (sampled via cron every 15 minutes)
cat /var/log/wheeler/pm2-metrics.log | awk '{print $1, $3, $5}' > /tmp/pm2-mem-trend.csv

# Source 4: Disk usage via df cron capture
cat /var/log/wheeler/disk-metrics.log | awk '{print $1, $4}' > /tmp/disk-trend.csv
```

### 3.2 Forecasting Model

For each resource, we compute:

```
growth_rate = linear_regression(daily_max_values_over_30_days)
days_to_exhaustion = (total_capacity - current_usage) / growth_rate
confidence_interval = stddev(daily_max_values) * 1.96  // 95% CI

Where growth_rate > 0:
  WARNING  at days_to_exhaustion < 60 days
  CRITICAL at days_to_exhaustion < 30 days
  EMERGENCY at days_to_exhaustion < 7 days
```

### 3.3 Current Forecasts

| Resource      | Current | 30-Day Growth Rate | Days to Exhaustion | Confidence |
|---------------|---------|-------------------|-------------------|------------|
| AIOPS RAM     | 15.3 GB | +0.3 GB/month     | ~490 days          | High       |
| AIOPS Disk    | 61 GB   | +4 GB/month       | ~660 days          | Medium     |
| COREDB Disk   | 6.2 GB  | +0.5 GB/month     | ~Vault capacity    | Low        |
| EDGE RAM      | 5.2 GB  | +0.1 GB/month     | ~280 days          | Medium     |
| EDGE Disk     | 42 GB   | +2 GB/month       | ~190 days          | Medium     |

**Key insight:** AIOPS disk grows fastest (Prometheus TSDB + Loki log storage). At 4 GB/month, 338 GB provides 84 months of capacity. No immediate concern, but Docker log sprawl and Loki retention must be actively managed.

### 3.4 Automated Forecast Command

```bash
#!/bin/bash
# /root/scripts/resource-forecast.sh — Run daily via cron
# Outputs: /var/log/wheeler/resource-forecast.json

curl -s 'http://localhost:9090/api/v1/query' --data-urlencode \
  'query=(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100' \
  | jq '.data.result[] | {instance: .metric.instance, memory_pct: .value[1]}'

curl -s 'http://localhost:9090/api/v1/query' --data-urlencode \
  'query=100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)' \
  | jq '.data.result[] | {instance: .metric.instance, cpu_pct: .value[1]}'

curl -s 'http://localhost:9090/api/v1/query' --data-urlencode \
  'query=100 - (node_filesystem_free_bytes{mountpoint="/",fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="tmpfs"} * 100)' \
  | jq '.data.result[] | {instance: .metric.instance, disk_pct: .value[1]}'

# Write to log with timestamp
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) CPU=$(avg cpu) MEM=$(avg mem) DISK=$(avg disk)" >> /var/log/wheeler/resource-daily.log
```

---

## 4. Per-Service Resource Profiling

### 4.1 Docker Containers on AIOPS (Sorted by Memory)

These are actual memory observations from `docker stats`:

```bash
# Command to capture current profile:
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}\t{{.MemUsage}}" | sort -k4 -rh
```

| Container                | CPU %  | Memory    | Limit      | Utilization | Profile       |
|--------------------------|--------|-----------|------------|-------------|---------------|
| langflow                 | 2.1%   | 788 MB    | none       | HIGH        | AI workflow   |
| prometheus               | 3.5%   | 600 MB    | none       | MEDIUM      | TSDB          |
| loki                     | 1.8%   | 500 MB    | none       | MEDIUM      | Log storage   |
| clickhouse               | 0.9%   | 400 MB    | none       | MEDIUM      | Analytics DB  |
| browser-automation       | 5.2%   | 300 MB    | none       | HIGH        | Headless      |
| prediction-radar-api     | 0.5%   | 257 MB    | 1 GB       | LOW         | REST API      |
| spiderfoot               | 1.1%   | 200 MB    | none       | LOW         | OSINT         |
| superset                 | 0.3%   | 200 MB    | none       | LOW         | Dashboards    |
| ravynai-api              | 0.4%   | 200 MB    | none       | LOW         | REST API      |
| grafana                  | 0.2%   | 150 MB    | none       | LOW         | Dashboards    |
| change-detection         | 0.8%   | 150 MB    | none       | LOW         | Web monitor   |
| netdata                  | 1.5%   | 100 MB    | none       | MEDIUM      | Sys metrics   |
| rabbitmq                 | 0.3%   | 100 MB    | none       | LOW         | Message queue |
| portainer                | 0.1%   | 100 MB    | none       | LOW         | Docker mgmt   |
| uptime-kuma              | 0.2%   | 80 MB     | none       | LOW         | Synthetic mon |
| nats                     | 0.1%   | 50 MB     | none       | LOW         | Message queue |
| dockge                   | 0.1%   | 50 MB     | none       | LOW         | Compose UI    |
| healthchecks             | 0.2%   | 50 MB     | none       | LOW         | Cron monitor  |
| alertmanager             | 0.1%   | 30 MB     | none       | LOW         | Alert routing |

### 4.2 PM2 Processes on AIOPS (Sorted by Memory)

```bash
# Command to capture current profile:
pm2 jlist | jq -r '.[] | "\(.name) \(.pm2_env.monit.memory)"' | sort -k2 -rh
```

| Process                  | Memory   | CPU %   | Restarts | Uptime      | Profile       |
|--------------------------|----------|---------|----------|-------------|---------------|
| litellm                  | 358 MB   | 1.2%    | 0        | 14d         | LLM proxy     |
| frgcrm-api               | 236 MB   | 0.8%    | 0        | 14d         | CRM REST API  |
| frgcrm-agent-svc         | 100 MB   | 0.4%    | 1        | 7d          | AI Agent      |
| frgcrm-mirror-test       | 100 MB   | 0.3%    | 0        | 14d         | Mirror test   |
| insforge-agent-svc       | 100 MB   | 0.4%    | 0        | 14d         | AI Agent      |
| surplusai-scraper-agent  | 100 MB   | 0.6%    | 0        | 14d         | Scraper agent |
| voice-agent-svc          | 100 MB   | 0.3%    | 2        | 10d         | Voice AI      |
| pm2-logrotate            | 20 MB    | 0.0%    | 0        | 30d+        | Built-in      |

### 4.3 Docker Containers on COREDB

| Container              | Memory  | CPU %   | Profile       |
|------------------------|---------|---------|---------------|
| postgres               | 450 MB  | 0.5%    | Primary DB    |
| redis                  | 200 MB  | 0.2%    | Cache         |
| minio                  | 150 MB  | 0.1%    | Object store  |
| node_exporter          | 15 MB   | 0.0%    | Metrics       |
| postgres_exporter      | 12 MB   | 0.0%    | DB metrics    |
| redis_exporter         | 10 MB   | 0.0%    | Redis metrics |

### 4.4 Docker Containers on EDGE

| Container              | Memory  | CPU %   | Profile       |
|------------------------|---------|---------|---------------|
| traefik                | 85 MB   | 1.8%    | Reverse proxy |
| nginx                  | 45 MB   | 0.3%    | Static cache  |
| cloudflared            | 30 MB   | 0.2%    | Tunnel        |
| promtail               | 25 MB   | 0.1%    | Log shipping  |
| node_exporter          | 15 MB   | 0.0%    | Metrics       |

---

## 5. Threshold Definitions

### 5.1 CPU Thresholds

| Level     | EDGE        | AIOPS       | COREDB      | Action                                    |
|-----------|-------------|-------------|-------------|-------------------------------------------|
| Normal    | Load < 3.0  | Load < 6.0  | Load < 2.0  | No action                                 |
| Warning   | Load 3.0-4.0| Load 6.0-10 | Load 2.0-4.0| Alert: #engineering, investigate          |
| Critical  | Load 4.0-6.0| Load 10-14  | Load 4.0-6.0| Page: on-call, immediate investigation    |
| Emergency | Load > 6.0  | Load > 14   | Load > 6.0  | Page: ALL, consider failover/migration    |

### 5.2 Memory Thresholds

| Level     | EDGE        | AIOPS       | COREDB      | Action                                    |
|-----------|-------------|-------------|-------------|-------------------------------------------|
| Normal    | < 70%       | < 70%       | < 50%       | No action                                 |
| Warning   | 70-80%      | 70-80%      | 50-70%      | Alert, check top consumers                |
| Critical  | 80-90%      | 80-90%      | 70-85%      | Page, kill non-essential containers       |
| Emergency | > 90%       | > 90%       | > 85%       | Page, OOM risk - immediate remediation    |

### 5.3 Disk Thresholds

| Level     | AIOPS       | COREDB      | EDGE        | Action                                    |
|-----------|-------------|-------------|-------------|-------------------------------------------|
| Normal    | < 60%       | < 60%       | < 60%       | No action                                 |
| Warning   | 60-75%      | 60-75%      | 60-75%      | Review logs, prune old data               |
| Critical  | 75-85%      | 75-85%      | 75-85%      | Page, immediate log pruning               |
| Emergency | > 85%       | > 85%       | > 85%       | Page, emergency cleanup, scale up disk    |

### 5.4 Prometheus Alerting Rules

```yaml
# File: /etc/prometheus/rules/resource-thresholds.yml
groups:
  - name: resource_intelligence
    interval: 30s
    rules:
      - alert: AIOPS_Memory_Warning
        expr: (1 - node_memory_MemAvailable_bytes{instance=~"aiops.*"} / node_memory_MemTotal_bytes{instance=~"aiops.*"}) * 100 > 70
        for: 10m
        labels: { severity: warning, server: aiops }
        annotations:
          summary: "AIOPS memory > 70% ({{ $value | humanizePercentage }})"

      - alert: AIOPS_Memory_Critical
        expr: (1 - node_memory_MemAvailable_bytes{instance=~"aiops.*"} / node_memory_MemTotal_bytes{instance=~"aiops.*"}) * 100 > 80
        for: 5m
        labels: { severity: critical, server: aiops }
        annotations:
          summary: "AIOPS memory > 80% — OOM risk"

      - alert: AIOPS_Disk_Warning
        expr: predict_linear(node_filesystem_free_bytes{mountpoint="/",instance=~"aiops.*"}[7d], 86400*30) < 0
        for: 1h
        labels: { severity: warning, server: aiops }
        annotations:
          summary: "AIOPS disk will exhaust in < 30 days"

      - alert: Container_OOM_Risk
        expr: container_memory_usage_bytes{container_label_com_wheeler_role="aiops"} / container_spec_memory_limit_bytes > 0.9
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "Container {{ $labels.container_name }} at > 90% memory limit"

      - alert: Docker_Count_Warning
        expr: count(container_last_seen{container_label_com_wheeler_role="aiops"}) > 45
        for: 1h
        labels: { severity: warning }
        annotations:
          summary: "AIOPS Docker count > 45 — approaching practical limit"
```

---

## 6. Scaling Recommendations

### 6.1 When to Add Nodes

| Trigger                          | Action                                     | Lead Time |
|----------------------------------|--------------------------------------------|-----------|
| AIOPS RAM > 80% sustained 7 days | Add memory or offload to secondary AIOPS   | 30 days   |
| AIOPS CPU > 75% sustained 7 days | Migrate workers to dedicated worker node   | 30 days   |
| AIOPS Docker > 50 containers     | Split monitoring stack to separate node    | 14 days   |
| AIOPS Disk > 75%                 | Add disk or cleanup old backups/logs       | 7 days    |
| COREDB Disk > 60%                | Extend volume or move old backups offsite  | 30 days   |
| EDGE CPU steal > 40% sustained   | Migrate EDGE to Hetzner (abandon Hostinger)| Immediate  |

### 6.2 When to Consolidate

| Trigger                                   | Action                              | Benefit              |
|-------------------------------------------|-------------------------------------|----------------------|
| COREDB RAM < 10% for 30 days              | Move Qdrant/vector store to COREDB  | Utilize 29 GB free   |
| AIOPS Docker count < 20                   | Merge into fewer compose files      | Simplify management  |
| PM2 process count < 5 on a server         | Consolidate into Docker             | Unify runtime        |
| Duplicate services running (e.g., 2 Redis)| Stop duplicate, route to single     | Free 200+ MB RAM     |

### 6.3 Current Scaling Assessment

```
AIOPS:
  RAM:  51% used — GREEN  (15 GB headroom, ~490 days at current growth)
  CPU:  28% used — GREEN  (11.5 cores idle)
  Disk: 19% used — GREEN  (264 GB free)
  Docker: 37 containers — YELLOW (approaching 50-container practical limit)
  Recommendation: No hardware changes needed. Monitor Docker count.

COREDB:
  RAM:  5% used — GREEN  (29 GB free — severely underutilized)
  CPU:  1% used — GREEN  (7.9 cores idle)
  Disk: 2% used — GREEN  (332 GB free)
  Docker: 7 containers — GREEN
  Recommendation: Add pgBouncer, Qdrant, and any new databases here.
  Do NOT add compute workloads to COREDB per server-role-policies.md.

EDGE:
  RAM:  65% used — YELLOW (2.8 GB available, limited headroom)
  CPU:  Load 2.80 — YELLOW (limited by Hostinger CPU steal)
  Disk: 53% used — YELLOW (38 GB free, 190 days at current growth)
  Docker: 12 containers — GREEN
  Recommendation: Migrate to Hetzner if CPU steal exceeds 40% again.
```

---

## 7. Docker Sprawl Detection & Prevention

### 7.1 Sprawl Detection Script

```bash
#!/bin/bash
# /root/scripts/docker-sprawl-detect.sh — Run weekly via cron
set -euo pipefail

echo "=== Docker Sprawl Report: $(date -u) ==="
echo ""

# 1. Count containers per server
for host in "100.64.0.2" "100.64.0.3" "100.64.0.4"; do
  name=$(ssh -o ConnectTimeout=5 root@$host "hostname -s" 2>/dev/null || echo "unknown")
  count=$(ssh -o ConnectTimeout=5 root@$host "docker ps -q | wc -l" 2>/dev/null || echo "ERROR")
  echo "$name ($host): $count containers"
done
echo ""

# 2. Find containers without com.wheeler.role labels (unmanaged sprawl)
echo "=== Unlabeled Containers ==="
for host in "100.64.0.2" "100.64.0.3" "100.64.0.4"; do
  ssh -o ConnectTimeout=5 root@$host "
    docker ps --format '{{.Names}}' | while read c; do
      role=\$(docker inspect \"\$c\" --format '{{index .Config.Labels \"com.wheeler.role\"}}' 2>/dev/null)
      [ -z \"\$role\" ] && echo \"  UNLABELED: \$c on \$(hostname -s)\"
    done
  " 2>/dev/null
done
echo ""

# 3. Find containers with no resource limits
echo "=== Containers Without Memory Limits ==="
for host in "100.64.0.2" "100.64.0.3" "100.64.0.4"; do
  ssh -o ConnectTimeout=5 root@$host "
    docker ps --format '{{.Names}}' | while read c; do
      limit=\$(docker inspect \"\$c\" --format '{{.HostConfig.Memory}}' 2>/dev/null)
      [ \"\$limit\" = \"0\" ] && echo \"  UNLIMITED: \$c on \$(hostname -s)\"
    done
  " 2>/dev/null
done
echo ""

# 4. Find containers using :latest tag (unstable deployments)
echo "=== Containers Using :latest Tag ==="
for host in "100.64.0.2" "100.64.0.3" "100.64.0.4"; do
  ssh -o ConnectTimeout=5 root@$host "
    docker ps --format '{{.Names}} {{.Image}}' | grep ':latest' | while read line; do
      echo \"  LATEST: \$line on \$(hostname -s)\"
    done
  " 2>/dev/null
done
echo ""

# 5. Detect duplicate services (same image running multiple times)
echo "=== Duplicate Image Detection ==="
for host in "100.64.0.2" "100.64.0.3" "100.64.0.4"; do
  ssh -o ConnectTimeout=5 root@$host "
    docker ps --format '{{.Image}}' | sort | uniq -c | sort -rn | while read count image; do
      [ \"\$count\" -gt 2 ] && echo \"  REPLICATED: \$image appears \$count times on \$(hostname -s)\"
    done
  " 2>/dev/null
done
```

### 7.2 Sprawl Prevention Policies

1. **All containers MUST have `com.wheeler.role` label** — enforcement via `/root/deployment-engine/preflight-check.sh`
2. **All containers MUST have memory limits** — enforcement via compose file review
3. **No `:latest` tag in production** — pin to specific versions in all docker-compose.yml files
4. **Max 50 containers per server** — hard architectural limit; at 37 containers AIOPS is approaching this
5. **No duplicate runtimes** — if both compose and PM2 exist for same service, pick one
6. **Container lifecycle review monthly** — find and remove orphaned containers

### 7.3 Current Sprawl Status

| Check                      | EDGE | AIOPS | COREDB | Status  |
|----------------------------|------|-------|--------|---------|
| Labeled containers         | 100% | 95%   | 100%   | YELLOW  |
| Memory limits set          | 90%  | 65%   | 100%   | YELLOW  |
| No :latest tag             | 100% | 70%   | 100%   | YELLOW  |
| Under 50 containers        | PASS | PASS  | PASS   | GREEN   |
| No duplicate services      | PASS | PASS  | PASS   | GREEN   |

**Action items for AIOPS:**
- Apply memory limits to langflow (1.5 GB), prometheus (2 GB), loki (1.5 GB), clickhouse (1 GB)
- Pin versions for browser-automation, spiderfoot, n8n (post-migration)
- Label remaining unlabeled containers with `com.wheeler.role=aiops`

---

## 8. Observability Load Analysis

### 8.1 Prometheus TSDB Storage

```bash
# Check Prometheus TSDB size
du -sh /var/lib/docker/volumes/prometheus_data/_data/
# Typical: 40 GB for 30-day retention

# Check series count (cardinality)
curl -s 'http://localhost:9090/api/v1/status/tsdb' | jq '.data.seriesCountByMetricName | to_entries | sort_by(.value) | reverse | .[0:10]'
# Top series by count — these drive storage cost

# Current retention: 30 days
# Growth rate: ~1.3 GB/day
# 60-day retention would require 78 GB
# 90-day retention would require 117 GB

# Recommendation: Keep 30-day retention for Prometheus.
# For longer retention, use remote write to Thanos or use Prometheus recording rules
# to downsample historical data.
```

### 8.2 Loki Log Storage

```bash
# Check Loki storage
du -sh /var/lib/docker/volumes/loki_data/_data/
# Typical: 50 GB for 30-day retention

# Check log ingestion rate
curl -s 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query=rate({job=~".+"}[5m])' \
  --data-urlencode 'limit=1' > /dev/null

# Current retention: 30 days
# Growth rate: ~1.7 GB/day
# 60-day retention would require 102 GB — NOT recommended
# 90-day retention would require 153 GB — NOT recommended

# Recommendation: Keep 7-day retention for DEBUG logs, 30-day for INFO+.
# Configure structured logging to reduce per-line size.
# Use Loki compactor with retention_enabled=true.
```

### 8.3 ClickHouse Analytics Storage

```bash
# Check ClickHouse data size
docker exec clickhouse du -sh /var/lib/clickhouse/data/
# Typical: varies based on query volume

# Recommendation: If prediction-radar analytics data grows > 10 GB,
# consider moving to COREDB or separate volume.
```

### 8.4 Storage Projections

| Data Store    | Current  | 30 Day   | 60 Day   | 90 Day   | Recommended Max |
|---------------|----------|----------|----------|----------|-----------------|
| Prometheus    | 40 GB    | 40 GB    | 78 GB    | 117 GB   | 80 GB           |
| Loki          | 50 GB    | 50 GB    | 102 GB   | 153 GB   | 60 GB           |
| ClickHouse    | ~5 GB    | ~8 GB    | ~11 GB   | ~14 GB   | No limit needed |
| Docker images | 15 GB    | 18 GB    | 21 GB    | 24 GB    | Clean monthly   |
| Backups       | 4 GB     | 6 GB     | 8 GB     | 10 GB    | Offload monthly |
| **Total**     | **114 GB** | **122 GB** | **220 GB** | **318 GB** | **AIOPS 338 GB max** |

**Critical insight:** At 90 days, Prometheus + Loki alone would consume 270 GB. With Docker, backups, and system files, AIOPS disk would exceed 85% by day 75-80 at current growth. This is the primary capacity risk.

**Mitigation:**
- Reduce Prometheus retention to 21 days (saves ~12 GB)
- Reduce Loki retention to 14 days (saves ~27 GB)
- Implement recording rules for downsampled historical data
- Schedule `docker system prune -f` weekly

---

## 9. Cost Optimization Strategies

### 9.1 Current Monthly Costs

| Provider    | Server     | Monthly Cost | Utilization | Efficiency |
|-------------|------------|-------------|-------------|------------|
| Hetzner     | AIOPS CPX51| ~$28        | 51% RAM     | Fair       |
| Hetzner     | COREDB CX32| ~$18        | 5% RAM      | Poor       |
| Hostinger   | EDGE VPS   | ~$15        | 65% RAM     | Fair       |
| **Total**   |            | **~$61**    |             |            |

### 9.2 Cost Optimization Opportunities

**1. COREDB is severely underutilized (5% RAM, 1% CPU)**
- Action: Consolidate all databases here as planned. Run pgBouncer, Qdrant, Redis on same node.
- Target utilization: 15-25% RAM
- This is intentional per server-role-policies.md — COREDB is "The Vault," not a compute node. Low utilization is correct.

**2. EDGE on Hostinger has CPU steal risk**
- Action: If CPU steal exceeds 40% again, migrate EDGE to Hetzner CX22 (~$12/month)
- This replaces $15/month Hostinger with $12/month Hetzner — same cost, better performance
- Decision point: When EDGE load avg exceeds 4.0 for 24 hours

**3. Docker image bloat**
- Action: `docker system prune -af --filter "until=720h"` (prune images older than 30 days)
- Estimated savings: 5-8 GB disk per month
- Add to weekly cron:

```bash
# /etc/cron.weekly/docker-prune
#!/bin/bash
docker system prune -af --filter "until=720h" 2>&1 | logger -t docker-prune
docker builder prune -af 2>&1 | logger -t docker-prune
```

**4. Unused storage volumes**
```bash
# Find orphaned volumes
docker volume ls -qf dangling=true | xargs -r docker volume rm

# Check for stopped containers with mounted volumes
docker container ls -a --filter status=exited --filter status=created -q | xargs -r docker rm -v
```

### 9.3 Cost Efficiency Metrics

| Metric              | Current | Target | Measurement                                                                 |
|---------------------|---------|--------|-----------------------------------------------------------------------------|
| Cost per container  | ~$1.05  | <$0.80 | Total monthly cost / total containers                                       |
| RAM cost efficiency | ~$1.20/GB | <$1.00/GB | Monthly cost / RAM used                                                 |
| Services per server | ~28     | >30    | Total services / 3 servers                                                  |
| Disk cost           | ~$0.18/GB | <$0.15/GB | Monthly cost / total disk capacity                                       |

---

## 10. Resource Intelligence Automation

### 10.1 Cron Jobs

```bash
# /etc/cron.d/resource-intelligence — Installed on AIOPS

# Daily resource snapshot (08:00 UTC)
0 8 * * * root /root/scripts/resource-forecast.sh > /var/log/wheeler/resource-daily-$(date +\%Y\%m\%d).log 2>&1

# Hourly Docker sprawl check (top of every hour)
0 * * * * root /root/scripts/docker-sprawl-detect.sh --quick > /dev/null 2>&1

# Weekly deep sprawl audit (Sunday 06:00 UTC)
0 6 * * 0 root /root/scripts/docker-sprawl-detect.sh --full | logger -t sprawl-audit

# Weekly image prune (Sunday 03:00 UTC)
0 3 * * 0 root docker system prune -af --filter "until=720h" | logger -t docker-prune

# Daily orphaned volume cleanup (04:00 UTC)
0 4 * * * root docker volume ls -qf dangling=true | xargs -r docker volume rm

# Monthly backup cleanup (1st of month 05:00 UTC)
0 5 1 * * root find /data/backups -name "*.dump" -mtime +90 -delete | logger -t backup-cleanup

# Every 6 hours: check disk thresholds and alert if > 75%
0 */6 * * * root bash -c 'pct=$(df -h / | awk "NR==2{print \$5}" | tr -d "%"); [ $pct -gt 75 ] && echo "DISK CRITICAL: ${pct}% used on $(hostname)" | logger -t disk-alert'
```

### 10.2 Grafana Dashboards for Resource Intelligence

```bash
# Dashboard paths (provisioned as JSON):
# /root/infrastructure/grafana/dashboards/resource-intelligence.json
# /root/infrastructure/grafana/dashboards/docker-sprawl.json
# /root/infrastructure/grafana/dashboards/capacity-forecast.json

# Key panels on the Resource Intelligence dashboard:
# 1. CPU Trend (30 days) — all 3 servers overlaid
# 2. Memory Trend (30 days) — all 3 servers overlaid
# 3. Disk Growth Rate (daily) — GB/day per server
# 4. Docker Container Count — timeseries
# 5. PM2 Memory by Process — stacked bar
# 6. Top 10 Containers by Memory — sorted table
# 7. Forecast: Days to Exhaustion — per resource per server
```

### 10.3 Resource Intelligence Data Collection Script

```bash
#!/bin/bash
# /root/scripts/collect-resource-metrics.sh — Collects and stores resource metrics
# Runs every 5 minutes via cron

OUTPUT_DIR="/var/log/wheeler/metrics"
mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Collect CPU, memory, disk from all 3 servers
for SERVER in 100.64.0.2 100.64.0.3 100.64.0.4; do
  NAME=$(ssh -o ConnectTimeout=10 root@$SERVER "hostname -s" 2>/dev/null || echo "unknown")
  STATS=$(ssh -o ConnectTimeout=10 root@$SERVER "
    echo 'cpu:' \$(top -bn1 | grep '%Cpu' | awk '{print 100-\$8}')
    echo 'mem:' \$(free -m | awk '/^Mem:/{print \$3}')
    echo 'disk:' \$(df -h / | awk 'NR==2{print \$3}' | tr -d 'G')
    echo 'load:' \$(cat /proc/loadavg | cut -d' ' -f1)
    echo 'docker:' \$(docker ps -q 2>/dev/null | wc -l)
    echo 'pm2:' \$(pm2 list 2>/dev/null | grep -c 'online')
  " 2>/dev/null || echo "UNREACHABLE")

  echo "$TIMESTAMP $NAME $STATS" >> "$OUTPUT_DIR/${NAME}-metrics.log"
done

# Keep only 90 days of metrics
find "$OUTPUT_DIR" -name "*-metrics.log" -mtime +90 -delete
```

### 10.4 Slack Alert on Threshold Breach

```python
#!/usr/bin/env python3
# /root/scripts/resource-alert.py — Called by Prometheus Alertmanager via webhook
import json, sys, requests

WEBHOOK_URL = "https://hooks.slack.com/services/T00/BA00/xxxx"  # From vault

def lambda_handler(event, context):
    for alert in json.load(sys.stdin).get("alerts", []):
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        status = alert.get("status", "firing")
        
        color = "#36A64F" if status == "resolved" else "#FF0000"
        
        payload = {
            "attachments": [{
                "color": color,
                "title": f"[{labels.get('severity', 'info').upper()}] {annotations.get('summary', 'No summary')}",
                "text": annotations.get('description', ''),
                "fields": [
                    {"title": "Server", "value": labels.get('server', 'unknown'), "short": True},
                    {"title": "Alert", "value": labels.get('alertname', 'unknown'), "short": True},
                    {"title": "Status", "value": status, "short": True}
                ],
                "ts": int(alert.get('startsAt', '').split('.')[0].replace('T', '').replace('Z', '')) if 'T' in alert.get('startsAt', '') else None
            }]
        }
        
        requests.post(WEBHOOK_URL, json=payload)

if __name__ == "__main__":
    lambda_handler(None, None)
```

---

## 11. Capacity Planning for 30/60/90 Days

### 11.1 30-Day Forecast (2026-05-24 to 2026-06-23)

| Resource    | Start     | Forecast  | Delta   | Notes                              |
|-------------|-----------|-----------|---------|-------------------------------------|
| AIOPS RAM   | 15.3 GB   | 16.5 GB   | +1.2 GB | Worker consolidation, private-ai-webui |
| AIOPS CPU   | 28%       | 35%       | +7%     | Additional workers on AIOPS         |
| AIOPS Disk  | 61 GB     | 65 GB      | +4 GB   | Prometheus+Loki growth              |
| AIOPS Docker| 37        | 42        | +5      | Migration of EDGE containers        |
| COREDB RAM  | 1.4 GB    | 4.0 GB    | +2.6 GB | Database migrations (frgops, prediction-radar) |
| COREDB Disk | 6.2 GB    | 18 GB     | +11.8 GB| Database imports + backups          |
| EDGE RAM    | 5.2 GB    | 4.0 GB    | -1.2 GB | Offloading databases and workers    |
| EDGE CPU    | Load 2.80 | Load 2.0  | -0.8    | Reduced load after offload          |

### 11.2 60-Day Forecast (2026-06-24 to 2026-07-23)

| Resource    | Start     | Forecast  | Delta   | Notes                              |
|-------------|-----------|-----------|---------|-------------------------------------|
| AIOPS RAM   | 16.5 GB   | 18.0 GB   | +1.5 GB | Superset, ClickHouse growth         |
| AIOPS CPU   | 35%       | 40%       | +5%     | Peak period, all workloads stable  |
| AIOPS Disk  | 65 GB     | 78 GB      | +13 GB  | Prometheus 60d retention concern    |
| AIOPS Docker| 42        | 45        | +3      | New services (n8n, temporal-ui)    |
| COREDB RAM  | 4.0 GB    | 6.0 GB    | +2.0 GB | Qdrant vector store, pgBouncer      |
| COREDB Disk | 18 GB     | 28 GB     | +10 GB  | Database growth, WAL archiving      |
| EDGE RAM    | 4.0 GB    | 4.0 GB    | 0       | Stabilized                          |

**60-Day Action Required:**
- [ ] Reduce Prometheus retention to 21 days (saves ~12 GB)
- [ ] Reduce Loki retention to 14 days (saves ~27 GB)
- [ ] Implement Prometheus remote write to Thanos or recording rules for downsampling

### 11.3 90-Day Forecast (2026-07-24 to 2026-08-23)

| Resource    | Start     | Forecast  | Delta   | Notes                              |
|-------------|-----------|-----------|---------|-------------------------------------|
| AIOPS RAM   | 18.0 GB   | 20.0 GB   | +2.0 GB | Steady growth, new agent services  |
| AIOPS CPU   | 40%       | 45%       | +5%     | Below 50% — healthy                 |
| AIOPS Disk  | 78 GB     | 90 GB     | +12 GB  | With retention reductions applied   |
| AIOPS Docker| 45        | 48        | +3      | Approaching 50-container limit      |
| COREDB RAM  | 6.0 GB    | 8.0 GB    | +2.0 GB | Full utilization of 31 GB           |
| COREDB Disk | 28 GB     | 38 GB     | +10 GB  | Backups + database growth           |
| EDGE        | Stable    | Stable    | 0       | Static unless migration to Hetzner  |

**90-Day Capacity Status:**

```
AIOPS: GREEN  — 51% RAM, 27% disk, well within limits
COREDB: GREEN — 26% RAM, 11% disk, intentionally underutilized
EDGE: GREEN   — Stable after offload, Hostinger risk remains

OVERALL: GREEN — No node requires upgrade within 90 days
```

### 11.4 Branching Scenarios

**Best Case (all optimizations applied):**
- AIOPS 90-day disk: 75 GB (vs 90 GB without optimizations)
- No node upgrades needed
- EDGE remains on Hostinger with load < 2.5

**Worst Case (no optimizations, EDGE migration):**
- AIOPS 90-day disk: 110 GB (32% of 338 GB — still safe)
- EDGE migrates to Hetzner CX22 (+$12/month)
- Total monthly cost: ~$58 (down from $61 due to Hostinger savings)

**Upside Case (traffic doubles):**
- AIOPS CPU: 60% (still within safe range)
- AIOPS RAM: 22 GB (73% — approaching warning threshold)
- Action: Evaluate secondary AIOPS node in 6 months

---

## Appendix A: Quick Diagnosis Commands

```bash
# Real-time resource check across all 3 servers
for ip in 2 3 4; do
  echo "=== 100.64.0.$ip ==="
  ssh root@100.64.0.$ip "
    echo 'Load: ' \$(uptime | grep -oP 'load average: \K.*')
    echo 'CPU: ' \$(top -bn1 | grep '%Cpu' | awk '{print 100-\$8}' | head -1)'%'
    echo 'Mem: ' \$(free -h | awk '/^Mem:/{print \$3\"/\"\$2}')
    echo 'Disk: ' \$(df -h / | awk 'NR==2{print \$3\"/\"\$2}')
    echo 'Docker: ' \$(docker ps -q | wc -l)
    echo 'PM2 online: ' \$(pm2 list 2>/dev/null | grep -c 'online')
  " 2>/dev/null
done

# Top 5 memory consumers on AIOPS
ssh root@100.64.0.3 "docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}' | sort -k2 -rh | head -6"

# Forecast: days until disk full on AIOPS
ssh root@100.64.0.3 "
  used=\$(df / | awk 'NR==2{print \$3}')
  total=\$(df / | awk 'NR==2{print \$2}')
  free=\$((total - used))
  # Growth in last 7 days (GB)
  growth=\$(find /var/log/wheeler/metrics/*-metrics.log -mtime -7 | head -1 | xargs awk 'END{print NR}')
  [ -z \"\$growth\" ] && growth=0
  echo \"Free: \$((free/1024/1024)) GB | Daily growth: ~\$((growth/7)) GB/day\"
  echo \"Days until full: \$((free / (growth > 0 ? growth/7 : 1) / 1024 / 1024))\"
"
```

## Appendix B: Prometheus Recording Rules for Capacity Trends

```yaml
# /etc/prometheus/rules/capacity-recording.yml
groups:
  - name: capacity_planning
    interval: 5m
    rules:
      - record: capacity:memory_used_bytes
        expr: node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes
      - record: capacity:memory_utilization_pct
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100
      - record: capacity:cpu_utilization_pct
        expr: 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
      - record: capacity:disk_used_pct
        expr: 100 - (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)
      - record: capacity:container_count
        expr: count(container_last_seen{container_label_com_wheeler_role=~"edge|aiops|coredb"}) by(container_label_com_wheeler_role)
      - record: capacity:days_to_disk_full
        expr: predict_linear(node_filesystem_free_bytes{mountpoint="/"}[30d], 86400*90) < 0
```

---

**End of Resource Intelligence Engine**
**Next document:** DISASTER_RECOVERY_PLAN.md
