# Wheeler Ecosystem -- Test Inventory & Service Matrix

> **Principal QA Architect | Production Documentation**
> Last updated: 2026-05-23
> READ-ONLY reference. Do not execute commands against live servers from this document.

---

## Table of Contents

1. [Section 1: Master Service Inventory](#section-1-master-service-inventory)
2. [Section 2: Service Dependency Matrix](#section-2-service-dependency-matrix)
3. [Section 3: Health Check Quick Reference](#section-3-health-check-quick-reference)

---

## Section 1: Master Service Inventory

### Legend

| Icon | Meaning |
|------|---------|
| :white_check_mark: | Healthy / Passing |
| :warning: | Degraded / Warning |
| :x: | Down / Failing |
| `---` | Not applicable |

### Classification Types

| Type | Description |
|------|-------------|
| `frontend` | User-facing web application (Next.js/React) |
| `API` | Backend REST/GraphQL service (FastAPI/Node) |
| `worker` | Async job processor / background task runner |
| `database` | Persistent relational data store |
| `queue` | Message broker / cache / pub-sub |
| `AI service` | LLM gateway, agent platform, ML inference |
| `monitoring` | Observability -- metrics, logs, dashboards, uptime |
| `storage` | Object / blob / file storage |
| `proxy/routing` | Reverse proxy, load balancer, CDN, mesh VPN |

---

### 1.1 -- Proxy / Routing Layer

| # | Service | Type | Current Server | Target Server | Process Manager | Port | Health Route | Test Command | Expected Result | Dependency Tests | Pass/Fail Criteria |
|---|---------|------|---------------|---------------|-----------------|------|-------------|--------------|-----------------|-------------------|-------------------|
| 1 | **Nginx** | proxy/routing | EDGE (Hostinger) | EDGE (Hostinger) | systemd | 80, 443 | `/nginx_status` | `curl -sf -o /dev/null -w "%{http_code}" http://localhost:80/nginx_status` | HTTP 200 | None (entry point) | Status 200; config test `nginx -t` passes |
| 2 | **Traefik** | proxy/routing | EDGE (Hostinger) | EDGE (Hostinger) | Docker | 8080, 8443 | `/ping` | `curl -sf http://localhost:8080/ping` | HTTP 200, plain-text "OK" | Docker daemon up | Status 200; dashboard reachable at `:8080/dashboard/` |
| 3 | **Cloudflare** | proxy/routing | External | External | --- | 443 | `---` | `curl -sI https://fundsrecoverygroup.com \| head -1` | HTTP/2 200 via CF | EDGE Nginx serving origin | Response contains `cf-ray` header; no 5xx from origin |

---

### 1.2 -- Frontend Applications (EDGE Node)

| # | Service | Type | Current Server | Target Server | Process Manager | Port | Health Route | Test Command | Expected Result | Dependency Tests | Pass/Fail Criteria |
|---|---------|------|---------------|---------------|-----------------|------|-------------|--------------|-----------------|-------------------|-------------------|
| 4 | **fundsrecoverygroup.com** | frontend | EDGE (Hostinger) | EDGE (Hostinger) | PM2 | 3000 | `/api/health` | `curl -sf http://localhost:3000/api/health \| jq .status` | `"ok"` | Nginx routing, Cloudflare DNS | JSON `{"status":"ok"}`; response < 500ms |
| 5 | **FRGCRM (frontend)** | frontend | EDGE (Hostinger) | EDGE (Hostinger) | PM2 | 3001 | `/api/health` | `curl -sf http://localhost:3001/api/health \| jq .status` | `"ok"` | Nginx, FRGCRM API (AIOPS) | JSON `{"status":"ok"}`; renders login page |
| 6 | **SurplusAI (portal)** | frontend | EDGE (Hostinger) | EDGE (Hostinger) | PM2 | 3002 | `/api/health` | `curl -sf http://localhost:3002/api/health \| jq .status` | `"ok"` | Nginx, SurplusAI API (AIOPS) | JSON `{"status":"ok"}`; renders login page |
| 7 | **Attorney Marketplace (portal)** | frontend | EDGE (Hostinger) | EDGE (Hostinger) | PM2 | 3004 | `/api/health` | `curl -sf http://localhost:3004/api/health \| jq .status` | `"ok"` | Nginx, Attorney Mkt API (AIOPS) | JSON `{"status":"ok"}`; renders login page |

---

### 1.3 -- API Services (AIOPS Node)

| # | Service | Type | Current Server | Target Server | Process Manager | Port | Health Route | Test Command | Expected Result | Dependency Tests | Pass/Fail Criteria |
|---|---------|------|---------------|---------------|-----------------|------|-------------|--------------|-----------------|-------------------|-------------------|
| 8 | **FRGCRM API** | API | AIOPS (Hetzner) | AIOPS (Hetzner) | PM2 | 8000 | `/health` | `curl -sf http://localhost:8000/health \| jq .status` | `"healthy"` | PostgreSQL, Redis | JSON `{"status":"healthy","database":"up","redis":"up"}`; response < 300ms |
| 9 | **SurplusAI API** | API | AIOPS (Hetzner) | AIOPS (Hetzner) | PM2 | 8001 | `/health` | `curl -sf http://localhost:8001/health \| jq .status` | `"healthy"` | PostgreSQL, Redis, LiteLLM | JSON `{"status":"healthy","db":"up","llm_gateway":"up"}`; response < 300ms |
| 10 | **Wheeler Brain OS API** | API / AI service | AIOPS (Hetzner) | AIOPS (Hetzner) | PM2 | 8002 | `/health` | `curl -sf http://localhost:8002/health \| jq .status` | `"healthy"` | PostgreSQL, Redis, LiteLLM, OpenClaw | JSON `{"status":"healthy","agents":<int>,"llm":"connected"}`; response < 500ms |
| 11 | **Prediction Radar API** | API / worker | AIOPS (Hetzner) | AIOPS (Hetzner) | PM2 | 8003 | `/health` | `curl -sf http://localhost:8003/health \| jq .status` | `"healthy"` | PostgreSQL, Redis | JSON `{"status":"healthy","db":"up","cache":"up"}`; response < 300ms |
| 12 | **Attorney Marketplace API** | API | AIOPS (Hetzner) | AIOPS (Hetzner) | PM2 | 8004 | `/health` | `curl -sf http://localhost:8004/health \| jq .status` | `"healthy"` | PostgreSQL, Redis | JSON `{"status":"healthy","db":"up","cache":"up"}`; response < 300ms |

---

### 1.4 -- AI & Agent Services (AIOPS Node)

| # | Service | Type | Current Server | Target Server | Process Manager | Port | Health Route | Test Command | Expected Result | Dependency Tests | Pass/Fail Criteria |
|---|---------|------|---------------|---------------|-----------------|------|-------------|--------------|-----------------|-------------------|-------------------|
| 13 | **LiteLLM / DeepSeek Gateway** | AI service | AIOPS (Hetzner) | AIOPS (Hetzner) | PM2 | 4000 | `/health` | `curl -sf http://localhost:4000/health \| jq .status` | `"ok"` or `"healthy"` | Upstream LLM provider reachable (DeepSeek API) | JSON healthy; `/v1/models` returns model list; latency < 2s to upstream |
| 14 | **OpenClaw (Agent Framework)** | AI service / worker | AIOPS (Hetzner) | AIOPS (Hetzner) | PM2 | 8005 | `/health` | `curl -sf http://localhost:8005/health \| jq .status` | `"healthy"` | PostgreSQL, Redis, LiteLLM | JSON `{"status":"healthy","broker":"connected","llm":"reachable"}`; response < 500ms |

---

### 1.5 -- Data & Storage Layer (COREDB Node)

| # | Service | Type | Current Server | Target Server | Process Manager | Port | Health Route | Test Command | Expected Result | Dependency Tests | Pass/Fail Criteria |
|---|---------|------|---------------|---------------|-----------------|------|-------------|--------------|-----------------|-------------------|-------------------|
| 15 | **PostgreSQL** | database | COREDB (Hetzner) | COREDB (Hetzner) | systemd / Docker | 5432 | TCP connect | `pg_isready -h localhost -p 5432 -U postgres -d wheeler` | `accepting connections` | COREDB disk > 20% free | `pg_isready` exit code 0; replication lag < 5s |
| 16 | **Redis** | queue / cache | COREDB (Hetzner) | COREDB (Hetzner) | systemd / Docker | 6379 | `PING` | `redis-cli -h localhost -p 6379 PING` | `PONG` | None (self-contained) | Response `PONG`; used memory < maxmemory |
| 17 | **MinIO (API)** | storage | COREDB (Hetzner) | COREDB (Hetzner) | Docker | 9000 | `/minio/health/live` | `curl -sf http://localhost:9000/minio/health/live` | HTTP 200 | COREDB disk available | HTTP 200; bucket list via `mc ls local` succeeds |
| 18 | **MinIO (Console)** | storage | COREDB (Hetzner) | COREDB (Hetzner) | Docker | 9001 | Web UI | `curl -sf -o /dev/null -w "%{http_code}" http://localhost:9001` | HTTP 200 | MinIO API (port 9000) healthy | HTTP 200; login page renders |

---

### 1.6 -- Monitoring & Observability

| # | Service | Type | Current Server | Target Server | Process Manager | Port | Health Route | Test Command | Expected Result | Dependency Tests | Pass/Fail Criteria |
|---|---------|------|---------------|---------------|-----------------|------|-------------|--------------|-----------------|-------------------|-------------------|
| 19 | **Grafana** | monitoring | EDGE (Hostinger) | EDGE (Hostinger) | Docker | 3030 | `/api/health` | `curl -sf http://localhost:3030/api/health` | HTTP 200, JSON body `{"database":"ok"}` | Prometheus data source, Loki data source | HTTP 200; dashboards load; data sources green |
| 20 | **Prometheus** | monitoring | AIOPS (Hetzner) | AIOPS (Hetzner) | systemd / Docker | 9090 | `/-/healthy` | `curl -sf http://localhost:9090/-/healthy` | HTTP 200 (plain-text "Prometheus Server is Healthy.") | All scrape targets reachable | HTTP 200; scrape duration < 10s; `up` metric = 1 for all targets |
| 21 | **Loki** | monitoring | AIOPS (Hetzner) | AIOPS (Hetzner) | Docker | 3100 | `/ready` | `curl -sf http://localhost:3100/ready` | HTTP 200 (plain-text "Ready") | COREDB MinIO (if using S3 backend) | HTTP 200; log streams queryable via LogQL |
| 22 | **Uptime Kuma** | monitoring | EDGE (Hostinger) | EDGE (Hostinger) | PM2 | 3031 | `/` (dashboard) | `curl -sf -o /dev/null -w "%{http_code}" http://localhost:3031` | HTTP 200 | None (standalone) | HTTP 200; all configured monitors show green status |

---

### 1.7 -- Infrastructure / Orchestration (All Nodes)

| # | Service | Type | Current Server | Target Server | Process Manager | Port | Health Route | Test Command | Expected Result | Dependency Tests | Pass/Fail Criteria |
|---|---------|------|---------------|---------------|-----------------|------|-------------|--------------|-----------------|-------------------|-------------------|
| 23 | **PM2** | process mgr | EDGE + AIOPS | EDGE + AIOPS | systemd | --- | `pm2 list` | `pm2 jlist \| jq 'map(select(.pm2_env.status != "online"))'` | Empty array (all processes online) | Systemd unit active | `pm2 ping` returns `pong`; zero stopped/errored processes |
| 24 | **Docker** | container runtime | ALL | ALL | systemd | --- | `docker info` | `docker info --format '{{.ServerVersion}}' 2>/dev/null` | Version string returned (e.g. `24.0.7`) | None | `docker info` exit code 0; daemon responding |
| 25 | **Tailscale** | proxy/routing (mesh VPN) | ALL | ALL | systemd | --- | `tailscale status` | `tailscale status --json \| jq '.Self.Online'` | `true` | None | All 3 nodes visible in `tailscale status`; direct connections (no DERP relay) |

---

## Section 2: Service Dependency Matrix

Rows depend on columns. `D` = direct (hard) dependency, `T` = transitive (soft) dependency, `---` = no relationship.

### 2.1 -- Dependency Matrix (All Services)

| Service \ Depends On → | Nginx | Traefik | CF | FRG FE | FRGCRM FE | SAI FE | AM FE | FRGCRM API | SAI API | WBOS API | PR API | AM API | LiteLLM | OpenClaw | PG | Redis | MinIO | Grafana | Prom | Loki | UK | PM2 | Docker | TS |
|-------------------------|-------|---------|-----|--------|-----------|--------|-------|------------|---------|----------|--------|--------|---------|----------|-----|-------|-------|---------|------|------|----|-----|--------|----|
| **Nginx**               |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- | --- |  ---  | --- |
| **Traefik**             |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- | --- |   D   | --- |
| **Cloudflare**          |   D   |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- | --- |  ---  | --- |
| **fundsrecoverygroup**  |   D   |   ---   |  D  |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **FRGCRM (frontend)**   |   D   |   ---   |  T  |  ---   |    ---    |  ---   |  ---  |     D      |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **SurplusAI (portal)**  |   D   |   ---   |  T  |  ---   |    ---    |  ---   |  ---  |    ---     |    D    |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **Attorney Mkt (FE)**   |   D   |   ---   |  T  |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |    D    |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **FRGCRM API**          |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    |  D  |   D   |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **SurplusAI API**       |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |    D    |   ---    |  D  |   D   |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **Wheeler Brain OS API**|  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |    D    |    D     |  D  |   D   |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **Prediction Radar API**|  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    |  D  |   D   |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **Attorney Mkt API**    |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    |  D  |   D   |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **LiteLLM / DeepSeek**  |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **OpenClaw**            |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |    D    |   ---    |  D  |   D   |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **PostgreSQL**          |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- | --- |   D   |  D  |
| **Redis**               |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- | --- |   D   |  D  |
| **MinIO**               |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- | --- |   D   |  D  |
| **Grafana**             |   D   |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    |  T  |  ---  |  ---  |   ---   |   D  |   D  | --- | --- |   D   |  D  |
| **Prometheus**          |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |     T      |    T    |    T     |   T    |    T    |    T    |    T     |  T  |   T   |  ---  |   ---   |  --- |  --- | --- | --- |   D   |  D  |
| **Loki**                |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |   T   |   ---   |  --- |  --- | --- | --- |   D   |  D  |
| **Uptime Kuma**         |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- |  D  |   D   |  D  |
| **PM2**                 |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- | --- |  ---  | --- |
| **Docker**              |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- | --- |  ---  | --- |
| **Tailscale**           |  ---  |   ---   | --- |  ---   |    ---    |  ---   |  ---  |    ---     |   ---   |   ---    |  ---   |  ---   |   ---   |   ---    | --- |  ---  |  ---  |   ---   |  --- |  --- | --- | --- |  ---  | --- |

### 2.2 -- Abbreviated Service Names Reference

| Abbreviation | Full Service Name |
|-------------|-------------------|
| CF | Cloudflare |
| FRG FE | fundsrecoverygroup.com |
| FRGCRM FE | FRGCRM (frontend) |
| SAI FE | SurplusAI (portal) |
| AM FE | Attorney Marketplace (portal) |
| SAI API | SurplusAI API |
| WBOS API | Wheeler Brain OS API |
| PR API | Prediction Radar API |
| AM API | Attorney Marketplace API |
| PG | PostgreSQL |
| UK | Uptime Kuma |
| TS | Tailscale |

### 2.3 -- Critical Dependency Chains

```
Cloudflare ──> Nginx ──> Frontends (FRG, FRGCRM, SurplusAI, AttorneyMkt)
                    ──> Grafana
              ──> Traefik (alternate routing)

Frontends ──> Respective API backends (AIOPS)

APIs ──> PostgreSQL (COREDB)
     ──> Redis (COREDB)
     ──> LiteLLM (SurplusAI, WheelerBrainOS)
     ──> OpenClaw (WheelerBrainOS only)

LiteLLM ──> External DeepSeek API
OpenClaw ──> LiteLLM ──> PostgreSQL ──> Redis

Prometheus ──> All API services (scrapes /metrics)
Grafana ──> Prometheus ──> Loki
Loki ──> MinIO (optional S3 backend)

PM2 ──> Manages: FRGCRM FE, SAI FE, AM FE, FRGCRM API, SAI API,
         WBOS API, PR API, AM API, LiteLLM, OpenClaw, Uptime Kuma

Tailscale ──> Mesh between all 3 nodes (EDGE ◄─► AIOPS ◄─► COREDB)
```

---

## Section 3: Health Check Quick Reference

### Top 10 Critical Health Checks (in priority order)

Run these in sequence. If any check fails, halt and investigate before proceeding.

| Priority | Check | Server | Command | Expected | If Fails... |
|----------|-------|--------|---------|----------|-------------|
| **P1** | Tailscale mesh up (all 3 nodes) | ALL | `tailscale status` | All 3 nodes listed; no DERP relay | Inter-node communication broken; nothing else will work correctly |
| **P2** | PostgreSQL accepting connections | COREDB | `pg_isready -h localhost -p 5432 -U postgres` | `accepting connections` | All APIs down; no data access |
| **P3** | Redis responding | COREDB | `redis-cli -h localhost -p 6379 PING` | `PONG` | Session/cache loss; queue backlogs |
| **P4** | LiteLLM gateway healthy | AIOPS | `curl -sf http://localhost:4000/health` | HTTP 200, JSON healthy | All AI features offline (SurplusAI, BrainOS, OpenClaw) |
| **P5** | MinIO object storage healthy | COREDB | `curl -sf http://localhost:9000/minio/health/live` | HTTP 200 | File uploads, document storage, Loki backend down |
| **P6** | All PM2 processes online | AIOPS | `pm2 jlist \| jq '[.[] \| select(.pm2_env.status != "online")] \| length'` | `0` | Check individual failed services; restart or investigate logs |
| **P7** | Nginx serving traffic | EDGE | `curl -sf -o /dev/null -w "%{http_code}" http://localhost:80/nginx_status` | `200` | All public sites unreachable; check nginx error log |
| **P8** | Cloudflare proxying correctly | EDGE (external) | `curl -sI https://fundsrecoverygroup.com \| head -1` | `HTTP/2 200` | DNS or CDN issue; check Cloudflare dashboard |
| **P9** | PROMETHEUS scraping healthy | AIOPS | `curl -sf http://localhost:9090/-/healthy` | HTTP 200 | Monitoring blind spot; Grafana dashboards stale |
| **P10** | Uptime Kuma dashboard reachable | EDGE | `curl -sf -o /dev/null -w "%{http_code}" http://localhost:3031` | `200` | Uptime monitoring down; no alerting for other failures |

### Quick Smoke Test (Bash One-Liner)

```bash
# Run from AIOPS node (Tailscale connected to all three)
echo "=== TAILSCALE ===" && tailscale status --json | jq '.Self.Online' && \
echo "=== POSTGRES ===" && pg_isready -h <coredb-tailscale-ip> -p 5432 -U postgres && \
echo "=== REDIS ===" && redis-cli -h <coredb-tailscale-ip> -p 6379 PING && \
echo "=== LITELLM ===" && curl -sf http://localhost:4000/health | jq . && \
echo "=== MINIO ===" && curl -sf http://<coredb-tailscale-ip>:9000/minio/health/live && \
echo "=== PM2 ===" && pm2 jlist | jq 'map(select(.pm2_env.status != "online")) | if length == 0 then "ALL ONLINE" else . end' && \
echo "=== NGINX ===" && curl -sf -o /dev/null -w "HTTP %{http_code}\n" http://<edge-tailscale-ip>:80/nginx_status && \
echo "=== PROMETHEUS ===" && curl -sf http://localhost:9090/-/healthy
```

> **Note:** Replace `<coredb-tailscale-ip>` and `<edge-tailscale-ip>` with actual Tailscale 100.x.x.x IPs of the respective nodes.

### Port Allocation Summary (Quick Reference)

| Port Range | Server | Services |
|------------|--------|----------|
| 80, 443 | EDGE | Nginx (HTTP/HTTPS public) |
| 3000--3005 | EDGE | Frontend apps (PM2-managed Node/Next.js) |
| 3030--3031 | EDGE | Grafana, Uptime Kuma |
| 4000 | AIOPS | LiteLLM / DeepSeek Gateway |
| 5432 | COREDB | PostgreSQL |
| 6379 | COREDB | Redis |
| 8000--8005 | AIOPS | API services + OpenClaw (PM2-managed FastAPI) |
| 8080, 8443 | EDGE | Traefik (internal routing) |
| 9000, 9001 | COREDB | MinIO API + Console |
| 9090 | AIOPS | Prometheus |
| 3100 | AIOPS | Loki |
| Tailscale 100.x | ALL | Mesh VPN (all inter-node traffic) |

---

### Document Maintenance

| Role | Responsibility |
|------|---------------|
| **Author** | Principal QA Architect, Wheeler Ecosystem |
| **Review Cycle** | Quarterly, or after any server topology change |
| **Related Documents** | `API_READINESS_MATRIX.md`, `DOMAIN_ROUTING_MAP.md`, `REVENUE_APP_INVENTORY.md` |
| **Conventions** | Standard ports; health routes follow FastAPI convention `/health` and Next.js convention `/api/health` |
