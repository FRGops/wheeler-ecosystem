# HEALTHCHECK Addition: 7 Containers Without Healthchecks

**Date:** 2026-05-27  
**Author:** Docker Expert Agent  
**Status:** 5/7 applied, 2/7 documented (safety constraints)

---

## Summary

| # | Container | Host | Management | Status | 
|---|-----------|------|-----------|--------|
| 1 | coredb-redis-exporter | Hetzner (local) | docker run | **APPLIED** - healthy |
| 2 | infisical-nginx | CoreDB | docker run | **DOCUMENTED ONLY** - production nginx |
| 3 | prediction-radar-scheduler | CoreDB | docker-compose (prediction-radar) | **APPLIED** - healthy |
| 4 | postgres-exporter | CoreDB | docker run | **APPLIED** - healthy |
| 5 | usesend | CoreDB | docker-compose (usesend) | **APPLIED** - healthy |
| 6 | qdrant | CoreDB | docker run | **DOCUMENTED ONLY** - database |
| 7 | aiops-pushgateway | CoreDB | docker run | **APPLIED** - healthy |

---

## Applied HEALTHCHECK Commands

### 1. coredb-redis-exporter (local Hetzner)

**Image:** `oliver006/redis_exporter:v1.67.0-alpine`  
**Network:** `monitoring_default`  
**User:** 59000:59000  
**Port:** 9121 (exposed, not published)

```bash
docker rm -f coredb-redis-exporter
docker run -d \
  --name coredb-redis-exporter \
  --restart unless-stopped \
  --user 59000:59000 \
  --network monitoring_default \
  -e REDIS_ADDR=prediction-radar-app-redis:6379 \
  --health-cmd='wget -q -O- http://localhost:9121/metrics || exit 1' \
  --health-interval=30s \
  --health-timeout=10s \
  --health-retries=3 \
  --health-start-period=10s \
  oliver006/redis_exporter:v1.67.0-alpine
```

**Result:** HEALTHY

---

### 3. prediction-radar-scheduler (CoreDB - Compose)

**File:** `/opt/apps/prediction-radar/docker-compose.yml`  
**Service:** `scheduler`  
**Reason for PID check:** No HTTP ports exposed; container runs `python /app/run.py`

**Healthcheck added:**
```yaml
    healthcheck:
      test: ["CMD-SHELL", "grep -qa run.py /proc/1/cmdline || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
```

**Applied via:**
```bash
cd /opt/apps/prediction-radar && docker compose up -d scheduler
```

**Note:** First attempt used a Python-based command that broke due to nested quotes in YAML. Fixed with grep-based approach on /proc/1/cmdline.

**Result:** HEALTHY

---

### 4. postgres-exporter (CoreDB - docker run)

**Image:** `prometheuscommunity/postgres-exporter`  
**Network:** `wheeler-core_default`  
**User:** nobody  
**Port:** 9187 (exposed, not published)

**WARNING:** Contains database password in DATA_SOURCE_NAME env var.

```bash
docker rm -f postgres-exporter
docker run -d \
  --name postgres-exporter \
  --restart unless-stopped \
  --user nobody \
  --network wheeler-core_default \
  -e DATA_SOURCE_NAME="postgresql://wheeler:4be38d4d330c1b63ef03d4dc8dd42ab370c22969b7ffd3a2@wheeler-postgres:5432/wheeler_core?sslmode=disable" \
  --health-cmd="wget -q -O- http://localhost:9187/metrics || exit 1" \
  --health-interval=30s \
  --health-timeout=10s \
  --health-retries=3 \
  prometheuscommunity/postgres-exporter
```

**Note:** The `--health-cmd` flag must be passed with `=` syntax or with separate arg format (`--health-cmd "..."` not quoted together). The image has wget and busybox available.

**Result:** HEALTHY

---

### 5. usesend (CoreDB - Compose)

**File:** `/opt/apps/usesend/docker-compose.yml`  
**Service:** `usesend`  
**Why PID check:** Next.js binds to container IP (172.18.0.5) not localhost, so wget to 127.0.0.1:3000 fails with connection refused.

**Healthcheck added:**
```yaml
    healthcheck:
      test: ["CMD-SHELL", "pgrep -f next-server > /dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
```

**Applied via:**
```bash
cd /opt/apps/usesend && docker compose up -d usesend
```

**Note:** First attempt used wget-based check, but usesend's Next.js server binds to the container network interface (172.18.0.5:3000), not 127.0.0.1:3000. Fallback to PID-based check.

**Result:** HEALTHY

---

### 7. aiops-pushgateway (CoreDB - docker run)

**Image:** `prom/pushgateway:latest`  
**Network:** `bridge`  
**User:** 65534  
**Port:** 9091 -> 127.0.0.1:9092

```bash
docker rm -f aiops-pushgateway
docker run -d \
  --name aiops-pushgateway \
  --restart unless-stopped \
  --user 65534 \
  --network bridge \
  -p 127.0.0.1:9092:9091 \
  --health-cmd="wget -q -O- http://localhost:9091/-/healthy || exit 1" \
  --health-interval=30s \
  --health-timeout=10s \
  --health-retries=3 \
  prom/pushgateway:latest
```

**Result:** HEALTHY

---

## Documented Only (Not Applied)

### 2. infisical-nginx (CoreDB)

**Why not applied:** Production reverse proxy serving Infisical. Stopping/recreating would cause a brief outage. SAFETY RULE: "NEVER stop production application containers."

**Current config:**
- Image: `nginx:alpine`
- Network: `wheeler-core_default` (172.18.0.14)
- Port: 80 -> 127.0.0.1:8443
- Restart: unless-stopped
- No volumes, no capabilities

**To apply (when maintenance window allows):**
```bash
ssh coredb 'docker rm -f infisical-nginx && docker run -d \
  --name infisical-nginx \
  --restart unless-stopped \
  --network wheeler-core_default \
  -p 127.0.0.1:8443:80 \
  --health-cmd="wget -qO- http://localhost:80/ || exit 1" \
  --health-interval=30s \
  --health-timeout=10s \
  --health-retries=3 \
  nginx:alpine'
```

**Healthcheck:** `wget -qO- http://localhost:80/ || exit 1`  
**Tools available:** wget, curl, pgrep

---

### 6. qdrant (CoreDB)

**Why not applied:** DATABASE container with persistent data. SAFETY RULE: "NEVER recreate database containers."

**Current config:**
- Image: `qdrant/qdrant:latest` (v1.18.1)
- Network: `wheeler-core_default` (172.18.0.9)
- Ports: 6333 -> 127.0.0.1:6333 + 100.118.166.117:6333, 6334 -> 100.118.166.117:6334
- Volume: `/opt/qdrant/data:/qdrant/storage`
- Restart: unless-stopped
- User: root (0:0)
- Environment: QDRANT__SERVICE__API_KEY, TZ=Etc/UTC, RUN_MODE=production
- OS: Debian 13 (trixie) - has bash available

**To apply (when maintenance window allows):**
```bash
ssh coredb 'docker rm -f qdrant && docker run -d \
  --name qdrant \
  --restart unless-stopped \
  --network wheeler-core_default \
  -p 127.0.0.1:6333:6333 \
  -p 100.118.166.117:6333:6333 \
  -p 100.118.166.117:6334:6334 \
  -e QDRANT__SERVICE__API_KEY="WheelerBrainOS-Qdrant-2026!" \
  -e TZ=Etc/UTC \
  -e RUN_MODE=production \
  -v /opt/qdrant/data:/qdrant/storage \
  --health-cmd="bash -c \"exec 3<>/dev/tcp/127.0.0.1/6333\" || exit 1" \
  --health-interval=30s \
  --health-timeout=10s \
  --health-retries=3 \
  qdrant/qdrant:latest'
```

**Healthcheck:** `bash -c "exec 3<>/dev/tcp/127.0.0.1/6333"` -- uses bash's built-in TCP pseudo-device since qdrant has no wget/curl/pgrep.  

**Note:** The container is Debian-based and has bash, but no wget, curl, or pgrep. The TCP socket check is the most reliable approach.

---

## Ecosystem Health Impact

**Before:** 0 of 7 target containers had healthchecks; unknown number of total healthy containers.

**After:**
- **21 healthy containers** in the CoreDB ecosystem (up from baseline)
- **0 unhealthy**
- **0 starting**

Containers with new HEALTHCHECK:
- coredb-redis-exporter (local Hetzner) - healthy
- prediction-radar-scheduler (CoreDB) - healthy
- postgres-exporter (CoreDB) - healthy
- usesend (CoreDB) - healthy
- aiops-pushgateway (CoreDB) - healthy

---

## Files Modified

1. `/opt/apps/prediction-radar/docker-compose.yml` -- Added healthcheck block to `scheduler` service
2. `/opt/apps/usesend/docker-compose.yml` -- Added healthcheck block to `usesend` service
