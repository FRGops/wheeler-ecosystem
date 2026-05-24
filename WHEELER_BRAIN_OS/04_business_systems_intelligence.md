# Wheeler Brain OS -- Business Systems Intelligence Map

**Generated:** 2026-05-24  
**Scope:** AIOPS (100.121.230.28) and COREDB (100.118.166.117)  
**Status:** All 40+ containers healthy across both hosts

---

## 1. DASHBOARD INVENTORY

### 1.1 AIOPS Dashboards (proxied via nginx at 100.121.230.28:443)

All dashboards require basic auth + SSL + Tailscale-only access (CGNAT range). Rate limited: 30 req/min standard, 10 req/min admin.

| Subdomain | Proxy Target | Service | Purpose | Health |
|-----------|-------------|---------|---------|--------|
| `grafana.aiops` | `127.0.0.1:3002` | Grafana v11.5.1 | AI Ops monitoring dashboards | healthy |
| `prometheus.aiops` | `127.0.0.1:9090` | Prometheus | Metric collection & alerting | healthy (200) |
| `kuma.aiops` / `status.aiops` | `127.0.0.1:3001` | Uptime Kuma | Uptime monitoring | healthy |
| `netdata.aiops` | `127.0.0.1:19999` | Netdata | Real-time system metrics | healthy |
| `superset.aiops` | `127.0.0.1:8088` | Apache Superset | BI / analytics dashboards | healthy |
| `healthchecks.aiops` | `127.0.0.1:3130` | Healthchecks.io | Cron job monitoring | healthy |
| `langflow.aiops` | `127.0.0.1:7860` | Langflow | AI workflow builder | healthy |
| `changes.aiops` | `127.0.0.1:5000` | Changedetection.io | Website change monitoring | healthy |
| `loki.aiops` | `127.0.0.1:3100` | Loki | Log aggregation | healthy |
| `docuseal.aiops` | `127.0.0.1:3010` | DocuSeal | Document signing | healthy |
| `prediction-radar.aiops` | `127.0.0.1:8098` | Prediction Radar Web | Market prediction app | healthy |
| `openwebui.aiops` | `127.0.0.1:3000` | Open WebUI | LLM chat interface | healthy |
| `crm.aiops` | `127.0.0.1:3007` | usesend / FRG CRM | Client management | healthy |
| `clickhouse.aiops` | `127.0.0.1:8123` | ClickHouse | Analytics database | healthy |
| `1panel.aiops` | `127.0.0.1:8090` | 1Panel | Server admin panel | healthy |
| `grafana-core.aiops` | `100.118.166.117:3000` | Core Grafana | Core-DB monitoring (proxied) | healthy |
| `prometheus-core.aiops` | `100.118.166.117:9090` | Core Prometheus | Core-DB metrics (proxied) | healthy |

### 1.2 COREDB Dashboards (direct IP bindings, no nginx proxy)

| URL | Service | Port | Purpose |
|-----|---------|------|---------|
| `http://100.118.166.117:3000` | Grafana (wheeler-grafana) | 3000 | Core infrastructure monitoring |
| `http://100.118.166.117:9090` | Prometheus (wheeler-prometheus) | 9090 | Core metrics collection |
| `http://100.118.166.117:3001` | Uptime Kuma (wheeler-uptime-kuma) | 3001 | Core uptime monitoring |

### 1.3 Prediction-Radar Internal Dashboards (docker internal network only)

| Container | Internal Port | Service |
|-----------|--------------|---------|
| prediction-radar-grafana | 3000 | Prediction Radar metrics |
| prediction-radar-prometheus | 9090 | Radar metrics collection |
| prediction-radar-alertmanager | 9093 | Radar alert routing |
| prediction-radar-uptime-kuma | 3001 | Radar-specific uptime |
| prediction-radar-dashboard-v2 | 3000 | Radar v2 dashboard |

### 1.4 Temporal (Workflow Engine)

| Container | Port | Purpose |
|-----------|------|---------|
| temporal-server | `127.0.0.1:7233` | Temporal server (gRPC) |
| temporal-ui | `127.0.0.1:8089` | Temporal Web UI |

---

## 2. REVENUE / BUSINESS SYSTEMS MAP

### 2.1 SurplusAI Portal
- **Container:** None running (service may be PM2-managed on Hostinger)
- **Database:** Uses `frgops-standby` PostgreSQL at `127.0.0.1:5433`
- **LLM:** Uses LiteLLM on AIOPS, DEEPSEEK_API_KEY configured
- **JWT Auth:** Custom JWT secret configured
- **Status:** Configured in `.env` but no active Docker container

### 2.2 Prediction Radar (Complete Revenue Stack)

**Containers (14 total, all healthy):**
- `prediction-radar-app-web` -- Public web frontend (`127.0.0.1:8098`)
- `prediction-radar-app-api` -- API server
- `prediction-radar-app-worker` -- Background job worker
- `prediction-radar-app-scheduler` -- Scheduled job runner
- `prediction-radar-app-db` -- Application database (PostgreSQL)
- `prediction-radar-app-db-backup-1` -- Automated database backup
- `prediction-radar-app-redis` -- Redis cache/queue
- `prediction-radar-fincept` -- Financial data ingestion
- `prediction-radar-crowdsec` -- WAF / security
- `prediction-radar-fail2ban` -- Brute force protection

**Revenue Configuration (Stripe):**
- Stripe Publishable Key, Secret Key, Webhook Secret
- Stripe Price IDs:
  - `STRIPE_PRICE_AGENCY` -- Agency tier
  - `STRIPE_PRICE_FORENSIC` -- Forensic tier
  - `STRIPE_PRICE_PROMPTS_PRO` -- Prompts Pro addon
  - `STRIPE_PRICE_SIGNALS_PRO` -- Signals Pro addon
  - `STRIPE_PRICE_MARKETING` -- Marketing tier
  - `STRIPE_PRICE_PRO` -- Pro tier
  - `STRIPE_PRICE_ENTERPRISE` -- Enterprise tier
- `MATIC_USD_PRICE_APPROX` -- MATIC price approximation
- FRGOPS Stripe webhook secret for cross-service billing
- Multiple Stripe webhook endpoints configured

**External Integrations (from .env):**
- Polymarket CLOB API (trading)
- Alpaca API (trading)
- Alpha Vantage API (market data)
- CoinGecko API (crypto prices)
- Brave API (search)
- CME FedWatch API (economic data)

### 2.3 FRG CRM / usesend
- **Container:** `usesend` at `127.0.0.1:3007` and `100.121.230.28:3007`
- **Proxy:** `crm.aiops` subdomain
- **Status:** Healthy
- **Note:** Bound to both Tailscale IP and 127.0.0.1

### 2.4 DocuSeal (Document Operations)
- **Container:** `docuseal` at `127.0.0.1:3010`
- **Redis:** `docuseal-redis` (dedicated)
- **Status:** Healthy
- **Proxy:** `docuseal.aiops` subdomain

### 2.5 RavynAI
- **Container:** `aiops-ravynai-app` at `127.0.0.1:8007`
- **Database:** `aiops-ravynai-postgres` at `127.0.0.1:5434`
- **Status:** Healthy

### 2.6 Hostinger Health Exporter
- **Container:** `hostinger-health-exporter` at `127.0.0.1:9091`
- **Purpose:** Exports Hostinger server health metrics to Prometheus for cross-server visibility

---

## 3. MONITORING & ALERTING SYSTEMS

### 3.1 AIOPS Monitoring Stack

| Component | Container | Port | Status |
|-----------|-----------|------|--------|
| Prometheus | aiops-prometheus | 127.0.0.1:9090 | healthy (200) |
| Alertmanager | aiops-alertmanager | 127.0.0.1:9093 | healthy |
| Grafana | aiops-grafana | 127.0.0.1:3002 | healthy (200) |
| Loki | aiops-loki | 127.0.0.1:3100 | healthy (ready) |
| Pushgateway | aiops-pushgateway | 127.0.0.1:9092 | healthy |
| Promtail | promtail | -- | healthy |
| Webhook Relay | aiops-webhook-relay | 127.0.0.1:8085 | healthy |

### 3.2 COREDB Monitoring Stack

| Component | Container | Port | Status |
|-----------|-----------|------|--------|
| Prometheus | wheeler-prometheus | 100.118.166.117:9090 | healthy |
| Grafana | wheeler-grafana | 100.118.166.117:3000 | healthy |
| Loki | wheeler-loki | 127.0.0.1:3100 | healthy |
| Promtail | promtail | -- | healthy |
| Node Exporter | node-exporter | -- | healthy |
| Redis Exporter | redis-exporter | -- | healthy |
| Postgres Exporter | postgres-exporter | -- | healthy |

### 3.3 Alert Rules (aiops-prometheus)

**Alert Group: `wheeler-critical` (30s evaluation interval)**

| Alert | Expression | For | Severity | Description |
|-------|-----------|-----|----------|-------------|
| ServiceDown | `up == 0` | 2m | critical | Any scraped target unreachable |
| PostgreSQLDown | `pg_up == 0` | 2m | critical | COREDB PostgreSQL down |
| RedisDown | `redis_up == 0` | 2m | critical | COREDB Redis down |
| ContainerDown | `time() - container_last_seen > 120` | 2m | critical | Container not reporting |
| HighMemoryUsage | memory > 85% limit | 5m | warning | Container memory pressure |
| DiskSpaceLow | disk free < 10% | 10m | warning | Node disk space critical |

### 3.4 Alert Routing (Alertmanager)

```
global: resolve_timeout 5m
route:
  receiver: discord-critical
  group_by: [alertname, severity]
  group_wait: 10s
  group_interval: 30s
  repeat_interval: 1h
  routes:
    - severity: critical  -> discord-critical (repeat 15m)
    - severity: warning   -> discord-warning (repeat 1h)

receivers:
  discord-critical: webhook -> http://webhook-relay:8080/alert (send_resolved)
  discord-warning:  webhook -> http://webhook-relay:8080/alert (send_resolved)
```

### 3.5 Uptime Monitoring

| Instance | Container | URL | Scope |
|----------|-----------|-----|-------|
| AIOPS Uptime Kuma | uptime-kuma | `kuma.aiops` / `status.aiops` | All AIOPS services |
| Prediction Radar Uptime | prediction-radar-uptime-kuma | internal network | Radar-specific endpoints |
| COREDB Uptime Kuma | wheeler-uptime-kuma | 100.118.166.117:3001 | Core infrastructure |
| Backup Kuma | uptime-kuma-backup | internal | Secondary uptime monitoring |

### 3.6 System Metrics

- **Netdata:** Real-time system metrics at `netdata.aiops`
- **Netdata Backup:** `netdata-backup` (standby monitoring)
- **Hostinger Health Exporter:** Cross-server metrics at `127.0.0.1:9091`

---

## 4. INFRASTRUCTURE & DATA LAYER

### 4.1 Database Systems

| Database | Container | Port | Host | Purpose |
|----------|-----------|------|------|---------|
| PostgreSQL | wheeler-postgres | 100.118.166.117:5432 | COREDB | Core application data |
| PostgreSQL (standby) | frgops-standby | 127.0.0.1:5433 | AIOPS | Portal/FRG CRM data |
| PostgreSQL (Ravyn) | aiops-ravynai-postgres | 127.0.0.1:5434 | AIOPS | RavynAI data |
| PostgreSQL (Radar) | prediction-radar-app-db | internal | AIOPS | Prediction Radar data |
| Redis | wheeler-redis | 100.118.166.117:6379 | COREDB | Core caching/queue |
| Redis (Radar) | prediction-radar-app-redis | internal | AIOPS | Radar caching/queue |
| Redis (DocuSeal) | docuseal-redis | internal | AIOPS | DocuSeal caching |
| ClickHouse | aiops-clickhouse | 127.0.0.1:8123 | AIOPS | Analytics/events |
| MinIO | wheeler-minio | internal | COREDB | Object storage |

### 4.2 Core-DB Internal Network

| Container | IP (172.19.0.x) | Purpose |
|-----------|-----------------|---------|
| wheeler-loki | 172.19.0.2 | Log aggregation |
| wheeler-prometheus | 172.19.0.4 | Metrics |
| wheeler-grafana | 172.19.0.5 | Dashboards |

| Container | IP (172.18.0.x) | Purpose |
|-----------|-----------------|---------|
| wheeler-minio | 172.18.0.2 | Object storage |
| wheeler-redis | 172.18.0.3 | Caching |
| wheeler-postgres | 172.18.0.4 | Database |

### 4.3 Workflow Engine

- **Temporal Server:** `temporal-server` on AIOPS (127.0.0.1:7233)
- **Temporal UI:** `temporal-ui` (127.0.0.1:8089)
- **COREDB Workers:** `temporal-pipeline-worker`, `temporal-pipeline-scheduler` (on COREDB)

---

## 5. BACKUPS & DISASTER RECOVERY

### 5.1 Backup Containers

| Container | Host | Purpose |
|-----------|------|---------|
| prediction-radar-app-db-backup-1 | AIOPS | Automated DB backup for Prediction Radar |
| uptime-kuma-backup | AIOPS | Uptime Kuma state backup |
| netdata-backup | AIOPS | Netdata configuration backup |

### 5.2 Backup Scripts & Artifacts

| Path | Description |
|------|-------------|
| `/opt/wheeler-ecosystem/scripts/backup-ecosystem.sh` | Full ecosystem backup: configs, docker-compose, PM2 state, wheeler-ecosystem |
| `/opt/wheeler-ecosystem/scripts/backup-verify.sh` | Backup integrity verification |
| `/opt/wheeler-ecosystem/backups/stage2-ops-gateway/20260524-042812/hostinger-nginx-backup.tar.gz` | Nginx configuration backup |
| `/opt/wheeler-ecosystem/docs/backup-rollback-guide.md` | Backup and rollback procedure documentation |

### 5.3 Backup Directories

- `/opt/backups` -- General backups
- `/opt/wheeler-ecosystem/backups/` -- Wheeler ecosystem backups
- `/opt/1panel/backup` -- 1Panel managed backups
- `/opt/wheeler/backups` -- Legacy wheeler backups

### 5.4 Backup Capabilities

- `/opt/wheeler-ecosystem/capabilities/backups` -- Dedicated backup capability module
- `/opt/wheeler-ecosystem/capabilities/sync/wheeler-capabilities-backup` -- Capability sync backup

---

## 6. SECURITY & ACCESS CONTROL

### 6.1 Network Security Posture

- **Tailscale mesh:** All dashboard traffic routed through Tailscale CGNAT (100.x.x.x)
- **Basic auth** on ALL nginx-proxied services
- **Rate limiting:** 30 req/min standard, 10 req/min admin endpoints (with burst)
- **SSL/TLS:** Self-signed certs at `/etc/nginx/ssl/aiops-gateway.{crt,key}`
- **Failed login protection:** prediction-radar-fail2ban + prediction-radar-crowdsec
- **Default catch-all:** Returns "Wheeler AI Ops Gateway -- healthy" (no route leakage)

### 6.2 Port Exposure Summary

| Host | Public Exposure | Notes |
|------|----------------|-------|
| AIOPS (100.121.230.28) | 443 (nginx) | All services proxied with auth |
| COREDB (100.118.166.117) | 3000, 9090, 5432, 6379 | Direct IP bindings via Tailscale |

---

## 7. COMPLETE CONTAINER INVENTORY

### AIOPS (100.121.230.28) -- 40 containers (all healthy)

```
aiops-grafana              aiops-prometheus           aiops-alertmanager
aiops-loki                 aiops-pushgateway           promtail
aiops-webhook-relay        aiops-superset              open-webui
langflow                   aiops-healthchecks          aiops-changedetection
aiops-clickhouse           aiops-ravynai-app           aiops-ravynai-postgres
docuseal                   docuseal-redis               frgops-standby
uptime-kuma                uptime-kuma-backup           netdata
netdata-backup             hostinger-health-exporter    usesend
temporal-server            temporal-ui

prediction-radar-app-web        prediction-radar-app-api
prediction-radar-app-worker     prediction-radar-app-scheduler
prediction-radar-app-db         prediction-radar-app-db-backup-1
prediction-radar-app-redis      prediction-radar-fincept
prediction-radar-grafana        prediction-radar-prometheus
prediction-radar-alertmanager   prediction-radar-uptime-kuma
prediction-radar-dashboard-v2   prediction-radar-crowdsec
prediction-radar-fail2ban
```

### COREDB (100.118.166.117) -- 19 containers (all healthy)

```
wheeler-grafana          wheeler-prometheus         wheeler-uptime-kuma
wheeler-loki             wheeler-postgres           wheeler-redis
wheeler-minio
node-exporter            postgres-exporter          redis-exporter
promtail
temporal-server          temporal-ui                temporal-pipeline-worker
temporal-pipeline-scheduler
aiops-pushgateway        usesend                    prediction-radar-worker
prediction-radar-scheduler
```

---

## 8. KEY FINDINGS & OBSERVATIONS

1. **All systems healthy:** 40 AIOPS + 19 COREDB containers all reporting healthy -- no alerts firing.

2. **Revenue systems concentrated on AIOPS:** Prediction Radar is the primary revenue-generating platform with full Stripe integration (7 price tiers), trading integrations (Polymarket, Alpaca), and multi-layered monitoring.

3. **Dual monitoring stacks:** Both AIOPS and COREDB maintain independent Prometheus/Grafana/Loki stacks. AIOPS nginx proxies the COREDB dashboards for unified access via `*.aiops` subdomains.

4. **Alerting pipeline:** Prometheus -> Alertmanager -> webhook-relay -> Discord. Critical alerts repeat every 15 minutes.

5. **Backup gaps:** Only Prediction Radar DB has automated containerized backup. No apparent automated backup for COREDB PostgreSQL (`wheeler-postgres`), RavynAI PostgreSQL, or ClickHouse data.

6. **SurplusAI Portal:** Configured in `.env` but no active Docker container -- may be PM2-managed on Hostinger host (not on AIOPS).

7. **Temporal distributed:** Temporal server runs on AIOPS, but workers exist on both AIOPS (`prediction-radar-app-worker/scheduler`) and COREDB (`temporal-pipeline-worker/scheduler`).

8. **Security:** Strong defense-in-depth with Tailscale mesh + basic auth + rate limiting + fail2ban/crowdsec on Prediction Radar.
