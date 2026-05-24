# Hostinger Internal Services Inventory
**Server:** wheeler-aiops-01 | **Date:** 2026-05-24

---

## 1. Service Taxonomy

Every service on the server classified by exposure level and Tailscale candidacy.

### Currently Public (should be Tailscale-only)

| Port | Service | Current State | Target State |
|------|---------|---------------|--------------|
| 8090 | 1Panel Server Admin | **0.0.0.0:8090** (CRITICAL) | Tailscale-only |
| 3002 | Grafana | **0.0.0.0:3002** | Tailscale-only |
| 8088 | Apache Superset | **0.0.0.0:8088** | Tailscale-only |
| 3001 | Uptime-Kuma | **0.0.0.0:3001** | Tailscale-only |
| 19999 | Netdata | **0.0.0.0:19999** | Tailscale-only |
| 5000 | Changedetection.io | **0.0.0.0:5000** | Tailscale-only |
| 3130 | Healthchecks.io | **0.0.0.0:3130** | Tailscale-only |
| 8123 | ClickHouse HTTP | **0.0.0.0:8123** (UFW tailscale0 only but Docker on 0.0.0.0) | 127.0.0.1 only |
| 7860 | Langflow | **0.0.0.0:7860** | Tailscale-only |
| 3010 | Docuseal | **0.0.0.0:3010** | Tailscale-only |
| 3100 | Loki | **0.0.0.0:3100** | Tailscale-only or 127.0.0.1 |
| 9080 | Promtail | **0.0.0.0:9080** | 127.0.0.1 (only loki needs it) |
| 9100 | node_exporter | **0.0.0.0:9100** | 127.0.0.1 (Prometheus scrapes locally) |
| 9090 | Prometheus | **0.0.0.0:9090** (UFW DENY protects it) | 127.0.0.1 |
| 8007 | surplusai-scraper-agent-svc | **0.0.0.0:8007** | 127.0.0.1 (internal agent) |
| 8005 | ravyn-agent-svc | **0.0.0.0:8005** (host-network container) | 127.0.0.1 |
| 8089 | temporal-ui | **0.0.0.0:8089** (host-network container) | 127.0.0.1 |
| 8098 | prediction-radar-web | **0.0.0.0:8098** | Possibly public, verify |
| 3007 | next-server (surplusai-portal-frontend v1) | **0.0.0.0:3007** | Tailscale-only (if still needed) |

### Currently Safe (already localhost-only)

| Port | Service | Binding |
|------|---------|---------|
| 5434 | aiops-ravynai-postgres | 127.0.0.1 only |
| 5433 | frgops-standby (PostgreSQL) | 127.0.0.1 only |
| 3000 | open-webui | 127.0.0.1 only |
| 4049 | litellm (LLM proxy) | 127.0.0.1 only |
| 6399 | event-bus-relay | 127.0.0.1 only |
| 8003 | frgcrm-agent-svc | 127.0.0.1 only |
| 8006 | horizon-agent-svc | 127.0.0.1 only |
| 8008 | voice-agent-svc | 127.0.0.1 only |
| 8009 | paperless-agent-svc | 127.0.0.1 only |
| 8011 | prediction-radar-agent-svc | 127.0.0.1 only |
| 8013 | insforge-agent-svc | 127.0.0.1 only |
| 8020 | design-agent-svc | 127.0.0.1 only |
| 8082 | frgcrm-api | 127.0.0.1 only |
| 8091 | war-room-server | 127.0.0.1 only |
| 8095 | voice-outreach-service | 127.0.0.1 only |
| 8103 | surplusai-portal-api | 127.0.0.1 only |
| 8110 | openclaw-dashboard | 127.0.0.1 only |
| 7233-7243 | temporal-server | 127.0.1.1 only |
| 6933-6939 | temporal-server | 127.0.1.1 only |
| 8090 | 1panel (system service) | 127.0.0.1 only |

### Docker-Internal (no host ports)

| Container | Network |
|-----------|---------|
| prediction-radar-app-db (postgres) | prediction-radar-app_default |
| prediction-radar-app-redis (redis) | prediction-radar-app_default |
| prediction-radar-app-api | prediction-radar-app_default |
| prediction-radar-app-scheduler | prediction-radar-app_default |
| prediction-radar-app-worker | prediction-radar-app_default |
| prediction-radar-dashboard-v2 | prediction-radar-app_default |
| docuseal-redis | docuseal_default |
| aiops-ravynai-app | bridge |

---

## 2. Host-Network Mode Containers (Isolation Bypass)

These 3 containers use `network_mode: host`, bypassing Docker's network namespace:

| Container | Ports Bound | Risk |
|-----------|-------------|------|
| temporal-temporal-1 | 127.0.1.1:7233-7235,7243,6933-6935,6939 | LOW (bound to loopback) |
| **temporal-temporal-ui-1** | ***:8089** (all interfaces) | **HIGH** — admin UI on all interfaces |
| **usesend** | ***:8005** (all interfaces) | **HIGH** — on all interfaces |

---

## 3. Truly Public Production Services

These are the only services that need to be reachable from the internet:

| Service | Port | Protocol | Justification |
|---------|------|----------|---------------|
| SSH | 22 | TCP | Emergency access (consider Tailscale-only) |
| nginx | 80 | TCP | HTTP → redirect to HTTPS (or close if no public web) |

**Verdict:** If there is no public-facing website or API on this server, port 80 should be closed and SSH should move to Tailscale-only. This would bring the public surface to **zero open ports**.

---

## 4. Tailscale-Only Candidates

These services are accessed by the operator via `*.aiops` domain names over Tailscale:

| Domain | Service | Current Docker Bind |
|--------|---------|---------------------|
| grafana.aiops | Grafana | 0.0.0.0:3002 → **change to 127.0.0.1:3002** |
| kuma.aiops | Uptime-Kuma | 0.0.0.0:3001 → **change to 127.0.0.1:3001** |
| netdata.aiops | Netdata | 0.0.0.0:19999 → **change to 127.0.0.1:19999** |
| superset.aiops | Superset | 0.0.0.0:8088 → **change to 127.0.0.1:8088** |
| healthchecks.aiops | Healthchecks | 0.0.0.0:3130 → **change to 127.0.0.1:3130** |
| langflow.aiops | Langflow | 0.0.0.0:7860 → **change to 127.0.0.1:7860** |
| changes.aiops | Changedetection | 0.0.0.0:5000 → **change to 127.0.0.1:5000** |
| prometheus.aiops | Prometheus | 0.0.0.0:9090 → **change to 127.0.0.1:9090** |
| loki.aiops | Loki | 0.0.0.0:3100 → **change to 127.0.0.1:3100** |
| docuseal.aiops | Docuseal | 0.0.0.0:3010 → **change to 127.0.0.1:3010** |
| prediction-radar.aiops | Prediction Radar | 0.0.0.0:8098 → verify, possibly 127.0.0.1 |
| openwebui.aiops | Open WebUI | Already 127.0.0.1:3000 |
| 1panel.aiops | 1Panel | Already 127.0.0.1:8090 |

**Key insight:** nginx already proxies ALL of these via `127.0.0.1` upstreams. Re-binding the Docker containers from `0.0.0.0` to `127.0.0.1` breaks nothing for legitimate use — nginx continues to work exactly as before, but the internet can no longer bypass nginx.

---

## 5. Services That Can Be Decommissioned

| Item | Reason |
|------|--------|
| `/opt/wheeler/ecosystem.config.js` | Stale config tree with different port assignments |
| `openclaw-dashboard` PM2 env leak | Captured Claude Code session tokens in PM2 environment |
| Port 80 nginx listener | Dead listener — no server block configured, serves nothing |
| `surplusai-portal-frontend` (port 3003) | Already migrated to EDGE per MEMORY.md, but tailscale0 rule still exists |
