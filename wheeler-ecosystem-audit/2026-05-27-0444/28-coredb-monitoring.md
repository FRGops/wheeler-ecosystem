# 28 - CoreDB Monitoring Integration

**Date:** 2026-05-27
**Status:** COMPLETE - All CoreDB targets UP, container alerts active

## Problem

CoreDB (Tailscale `100.118.166.117`) had zero container-level monitoring. Existing targets only covered node-level metrics (node_exporter, postgres-exporter, redis-exporter). A container EXITED for 7 hours with zero alerting because cadvisor was not deployed on CoreDB and no container-level alerts existed.

## Actions Taken

### 1. Deployed cadvisor on CoreDB

Deployed `gcr.io/cadvisor/cadvisor:latest` bound to the Tailscale IP for direct scraping from the Hetzner Prometheus:

```
docker run -d --name cadvisor --restart unless-stopped \
  --privileged --device /dev/kmsg \
  -p 100.118.166.117:8080:8080 \
  gcr.io/cadvisor/cadvisor:latest
```

### 2. Fixed postgres-exporter port binding

The postgres-exporter was running in bridge mode (`wheeler-core_default` network) with **no host port mapping** -- it was only accessible within the Docker network on CoreDB. Recreated the container with an explicit Tailscale IP port binding:

```
-p 100.118.166.117:9187:9187
```

### 3. Updated Prometheus targets (all to Tailscale IP)

Changed all CoreDB targets from DNS-based hostnames to explicit Tailscale IP addresses for reliable cross-host scraping:

| Job | Old Target | New Target | Status |
|-----|-----------|------------|--------|
| coredb-node | `100.118.166.117:9100` | (unchanged) | UP |
| coredb-postgres | `coredb-postgres-exporter:9187` | `100.118.166.117:9187` | UP |
| coredb-redis | `coredb-redis-exporter:9121` | `100.118.166.117:9121` | UP |
| coredb-cadvisor | (NEW) | `100.118.166.117:8080` | UP |

**Config files:**
- `/opt/apps/monitoring/prometheus.yml` -- scrape configs, all CoreDB targets by Tailscale IP
- `/opt/apps/monitoring/alert-rules.yml` -- CoreDB-specific alert rules added

### 4. Added CoreDB-specific alert rules

Two new alerts in the `wheeler-critical` group:

- **CoreDBContainerDown** (critical) -- Fires when `container_last_seen` exceeds 180s for any CoreDB container. Catches the exact scenario that went undetected (container EXITED for hours with no alerting).
- **CoreDBHighContainerMemory** (warning) -- Fires when any CoreDB container exceeds 85% memory limit.

## Monitoring Architecture

```
CoreDB (100.118.166.117)
  |
  |-- node-exporter:9100 (host networking)
  |-- redis-exporter:9121 (host networking)
  |-- postgres-exporter:9187 (bridge + Tailscale IP binding)
  |-- cadvisor:8080 (Tailscale IP binding)
  |
  v
Hetzner Prometheus (localhost:9090)
  |-- scrape interval: 30s
  |-- evaluates alert rules every 30s
  v
Alertmanager -> webhook-relay -> Discord
```

## Verification

```
TARGETS (all UP):
up       coredb-cadvisor    100.118.166.117:8080
up       coredb-node        100.118.166.117:9100
up       coredb-postgres    100.118.166.117:9187
up       coredb-redis       100.118.166.117:9121

CONTAINERS TRACKED: 75
MEMORY USAGE: 28.9 GB total

ALERTS:
inactive  CoreDBContainerDown
inactive  CoreDBHighContainerMemory
```

## What Was Fixed vs. What Was Discovered

### Fixed
1. No cadvisor on CoreDB -> Deployed and scraping (75 containers tracked)
2. postgres-exporter unreachable from Hetzner -> Added Tailscale IP port binding
3. No CoreDB container alerts -> Added CoreDB-specific alert rules
4. DNS-based targets (fragile) -> Switched to explicit Tailscale IP for all CoreDB targets

### Discovered
1. **Inode trap with Docker bind mounts**: Editing `prometheus.yml` or `alert-rules.yml` with tools that create new inodes (sed -i, Edit tool) breaks Docker bind mounts -- the container still sees the OLD file. Fix: use Python `open(file, 'w')` + `write()` which truncates in-place, preserving the inode.
2. **postgres-exporter was in bridge mode without host port mapping**: It was accessible only within CoreDB's Docker network. The Hetzner Prometheus showed it as UP (via DNS resolution through an unexplained path), but this was fragile. Fixed by explicitly binding to the Tailscale IP.
3. **redis-exporter and node-exporter use host networking**: They bind directly to the CoreDB host's network interfaces, making them directly reachable via Tailscale IP without Docker port publishing.

## Alert Response

If `CoreDBContainerDown` fires:

1. `ssh coredb "docker ps"` -- list all containers, check for EXITED
2. `ssh coredb "docker logs <container>" --tail 50` -- investigate failure
3. Restart with `ssh coredb "docker restart <container>"` or investigate root cause
4. Check cadvisor: `ssh coredb "docker ps --filter name=cadvisor"` -- ensure cadvisor is running

## Files Changed

- `/opt/apps/monitoring/prometheus.yml` -- coredb-cadvisor job added, all CoreDB targets use Tailscale IP
- `/opt/apps/monitoring/alert-rules.yml` -- CoreDBContainerDown and CoreDBHighContainerMemory alerts added
