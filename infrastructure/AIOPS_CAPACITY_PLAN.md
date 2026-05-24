# AIOPS Capacity Plan

> **Purpose:** Validate that AIOPS (Hetzner CPX51, 100.121.230.28) can absorb all EDGE (Hostinger) migrations without risking stability.
> **Policy Reference:** server-role-policies.md v1.0.0 — AIOPS is "The Brain": all compute workloads, AI, APIs, workers, orchestration, monitoring.

## Current Utilization

| Resource | Used | Total | Free | Utilization |
|----------|------|-------|------|-------------|
| CPU | 21.3% us + 14.2% sy | 16 vCPUs | ~65% idle | 35.5% total |
| Load Avg (1m) | 2.06 | 16 cores | — | Light load |
| RAM | 17.1 GB | 31 GB | 14.2 GB | 54.8% |
| Disk | 52 GB | 338 GB | 286 GB | 15.5% |
| Docker Containers | 24 | — | — | — |
| PM2 Apps | 17 | — | — | — |

### Current Docker Containers (Top Memory Consumers)

```
CONTAINER                    MEM USAGE     LIMIT        NOTE
prediction-radar-api         257 MB        1 GB         Prediction Radar REST API
langflow                     788 MB        — (no limit) AI workflow builder
superset                     ~200 MB       —            Apache Superset
clickhouse                   ~400 MB       —            ClickHouse analytics
ravynai-api                  ~200 MB       —            RavynAI REST API
prometheus                   ~600 MB       —            TSDB (40 GB on disk)
grafana                      ~150 MB       —            Dashboards
loki                         ~500 MB       —            Log aggregation (50 GB on disk)
portainer                    ~100 MB       —            Docker management
nats                         ~50 MB        —            Message broker
rabbitmq                     ~100 MB       —            Message broker
change-detection             ~150 MB       —            Website monitoring
healthchecks                 ~50 MB        —            Cron monitoring
spiderfoot                   ~200 MB       —            OSINT tool
browser-automation           ~300 MB       —            Headless browser
uptime-kuma                  ~80 MB        —            Synthetic monitoring
netdata                      ~100 MB       —            System metrics
dockge                       ~50 MB        —            Compose UI
alertmanager                 ~30 MB        —            Alert routing
... (~5 more small containers)
```

### Current PM2 Apps

```
APP NAME                       MEM      SCRIPT
pm2-logrotate                  ~20 MB   (built-in)
litellm                        358 MB   LiteLLM proxy (MAJOR — keep)
frgcrm-api                     236 MB   FRG CRM REST API
frgcrm-agent-svc               ~100 MB  FRG CRM AI Agent
frgcrm-mirror-test              ~100 MB  FRG CRM Mirror Test
insforge-agent-svc              ~100 MB  InsForge AI Agent
surplusai-scraper-agent-svc    ~100 MB  SurplusAI Scraper Agent
voice-agent-svc                 ~100 MB  Voice AI Agent
... (~9 more small PM2 apps)
```

### Docker Networks on AIOPS

```
NETWORK              SUBNET           PURPOSE
traefik-public       172.20.0.0/24    Traefik internal + public apps
prediction-radar     172.21.0.0/24    API, Web, Worker, Scheduler, DB, Redis
analytics            172.22.0.0/24    Superset + ClickHouse
ravynai              172.25.0.0/24    API, Worker, DB
ai-agents            172.24.0.0/24    Agent Runtimes
trading              172.26.0.0/24    Trading workers, Feed handlers
messaging            172.27.0.0/24    NATS, RabbitMQ
automation           172.28.0.0/24    ChangeDetection, BrowserAuto
data                 172.29.0.0/24    PostgreSQL, Redis
monitoring           172.35.0.0/24    Prometheus, Grafana, Loki, Alertmanager, UptimeKuma, Netdata
management           172.36.0.0/24    Portainer, Dockge
osint                172.37.0.0/24    Spiderfoot
```

---

## After-Migration Projections

These are the services currently on EDGE that must move to AIOPS. All estimates are conservative (upper-bound for safety).

| Incoming Service | CPU Est | RAM Est | Disk Est | Where Placed | Feasible? |
|---|---|---|---|---|---|
| **private-ai-webui** | 1.5 cores sustained, 3.0 spike | 1.5 GB | 2 GB (models) | `ai-agents` network (172.24.0.0/24) | YES — 14 vCPUs idle, 14.2 GB RAM free |
| **temporal-server** | 0.5 cores | 512 MB | 1 GB | `automation` network (172.28.0.0/24) or new `temporal` network | YES — minor |
| **prediction-radar-worker** (currently EDGE) | 0.3 cores | 256 MB | 0 (already uses AIOPS DB) | `prediction-radar` network (172.21.0.0/24) | YES — already co-located infra |
| **prediction-radar-scheduler** (currently EDGE) | 0.2 cores | 128 MB | 0 (already uses AIOPS DB) | `prediction-radar` network (172.21.0.0/24) | YES — already co-located infra |
| **usesend-app** | 0.3 cores | 256 MB | 0 (connects to COREDB) | New `usesend` network or `ai-agents` network | YES — lightweight |
| **n8n-engine** | 0.5 cores | 384 MB | 0.5 GB (SQLite workflows) | `automation` network (172.28.0.0/24) | YES — minor |
| **litellm-dedup** | N/A | N/A | N/A | Merge into existing PM2 litellm — deduplicate, not add | YES — zero new resources |
| **TOTAL INCOMING** | **~3.3 cores peak** | **~3.0 GB** | **~3.5 GB** | | **All feasible** |

### Post-Migration Projected Utilization

| Resource | Pre-Migration | After Migration | Headroom Remaining |
|----------|---------------|-----------------|---------------------|
| CPU cores used | ~5.7 of 16 (35.5%) | ~9.0 of 16 (56%) | **7 cores (~44%)** |
| RAM used | 17.1 GB | ~20.1 GB (65%) | **~10.9 GB (35%)** |
| Disk used | 52 GB (15.5%) | ~55.5 GB (16.5%) | **~282 GB (83.5%)** |
| Docker containers | 24 | ~30 | Well under 50-container practical limit |
| PM2 apps | 17 | 17 (no change — dedup litellm) | — |

**Conclusion: AIOPS has sufficient capacity. Post-migration utilization (~56% CPU, ~65% RAM) is within safe operating range with 35%+ headroom.**

---

## Docker Resource Limits Needed

Per server-role-policies.md, all Docker containers must have `com.wheeler.role=aiops` label and explicit resource limits. The following cgroup limits must be applied to incoming containers:

### Incoming Containers

```yaml
# private-ai-webui (heaviest incoming service)
services:
  private-ai-webui:
    deploy:
      resources:
        limits:
          cpus: "2.0"        # Allow up to 2 cores for model inference spikes
          memory: 2048M      # 2GB hard limit — prevents OOM on 31GB host
        reservations:
          cpus: "0.5"
          memory: 512M
    labels:
      - "com.wheeler.role=aiops"
      - "com.wheeler.service=private-ai-webui"
      - "com.wheeler.tier=backend"

  temporal-server:
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 768M       # 50% buffer above observed 512MB
        reservations:
          cpus: "0.25"
          memory: 256M
    labels:
      - "com.wheeler.role=aiops"
      - "com.wheeler.service=temporal-server"
      - "com.wheeler.tier=backend"

  prediction-radar-worker:
    deploy:
      resources:
        limits:
          cpus: "0.75"
          memory: 384M
        reservations:
          cpus: "0.1"
          memory: 128M
    labels:
      - "com.wheeler.role=aiops"
      - "com.wheeler.service=prediction-radar-worker"
      - "com.wheeler.tier=backend"

  prediction-radar-scheduler:
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 256M
        reservations:
          cpus: "0.05"
          memory: 64M
    labels:
      - "com.wheeler.role=aiops"
      - "com.wheeler.service=prediction-radar-scheduler"
      - "com.wheeler.tier=backend"

  usesend-app:
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 384M
        reservations:
          cpus: "0.1"
          memory: 128M
    labels:
      - "com.wheeler.role=aiops"
      - "com.wheeler.service=usesend-app"
      - "com.wheeler.tier=backend"

  n8n-engine:
    deploy:
      resources:
        limits:
          cpus: "0.75"
          memory: 512M
        reservations:
          cpus: "0.1"
          memory: 128M
    labels:
      - "com.wheeler.role=aiops"
      - "com.wheeler.service=n8n-engine"
      - "com.wheeler.tier=backend"
```

### Existing Containers Needing Limits (Currently Unlimited)

These AIOPS containers lack explicit resource limits and risk OOM:

| Container | Current Limit | Recommended Limit | Risk |
|-----------|---------------|-------------------|------|
| langflow | none | 1536M (1.5GB) | HIGH — 788MB observed, could spike |
| clickhouse | none | 1024M (1GB) | MEDIUM — analytics queries can spike |
| prometheus | none | 2048M (2GB) | MEDIUM — TSDB compaction spikes RAM |
| loki | none | 1536M (1.5GB) | MEDIUM — log ingestion bursts |
| superset | none | 512M | LOW |
| ravynai-api | none | 512M | LOW |
| browser-automation | none | 768M | MEDIUM — Puppeteer/Playwright spikes |
| spiderfoot | none | 512M | LOW |

---

## PM2 Slot Planning

Current state: 17 PM2 apps on AIOPS. No new PM2 apps from migration — EDGE LiteLLM is deduplicated into existing PM2 `litellm`. However, post-migration load on PM2 apps may increase:

| PM2 App | Current Impact | Post-Migration Impact | Action |
|---------|---------------|----------------------|--------|
| litellm (358MB) | Serves AIOPS + EDGE requests | EDGE requests stop (litellm-edge removed); AIOPS litellm handles all | Verify model routes match EDGE config |
| frgcrm-api (236MB) | Local DB (AIOPS postgres) | Connects to COREDB postgres (via Tailscale) | Update DATABASE_URL after DB migration |
| frgcrm-agent-svc (~100MB) | Calls LiteLLM | No change | — |
| insforge-agent-svc (~100MB) | Calls LiteLLM | No change | — |
| surplusai-scraper-agent-svc (~100MB) | Calls LiteLLM | No change | — |
| voice-agent-svc (~100MB) | Calls LiteLLM | No change | — |

**PM2 memory headroom:** Currently ~1.3 GB for 17 apps. Post-migration stays at 17 apps with slightly increased load on litellm. No PM2 scaling needed.

---

## Risks and Mitigations

### Risk 1: Memory Pressure from AI Models on private-ai-webui
- **Likelihood:** MEDIUM
- **Impact:** private-ai-webui loading large models could OOM and crash other containers
- **Mitigation:** Hard cgroup limit of 2GB. Model weights stored on /data with size monitoring. If model exceeds 2GB, offload to dedicated GPU instance or use API-based inference.
- **Detection:** Prometheus alert `container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9`

### Risk 2: Temporal Database Contention on COREDB PostgreSQL
- **Likelihood:** LOW
- **Impact:** Temporal writes to PostgreSQL frequently (workflow state). If COREDB PostgreSQL is undersized, latency increases.
- **Mitigation:** Monitor COREDB PostgreSQL `pg_stat_activity` for long-running queries. Configure Temporal with connection pooling. Consider separate Temporal DB on AIOPS read-replica (allowed per policy with `com.wheeler.role=read-replica` label).
- **Detection:** pg_stat_statements tracking queries >100ms on COREDB

### Risk 3: Docker Network Collision
- **Likelihood:** LOW
- **Impact:** Network subnet conflict between existing and new containers during compose up.
- **Mitigation:** Audit all existing Docker networks before deploying. New services join existing networks where possible (prediction-radar joins 172.21.0.0/24). New networks use addresses from the 172.28.0.0/16 pool per docker-daemon.json.
- **Detection:** `docker network ls` and `docker network inspect` before each deployment

### Risk 4: Traefik Route Cutover Timing
- **Likelihood:** LOW (if done carefully)
- **Impact:** Brief downtime (~30s) while Traefik configuration reloads to point at AIOPS instead of EDGE.
- **Mitigation:** Use Traefik weighted round-robin: 100% EDGE → 50/50 EDGE/AIOPS → 100% AIOPS. This allows gradual cutover with instant rollback.
- **Detection:** Uptime Kuma synthetic check on each domain; alert if >5s response time or non-200.

### Risk 5: Tailscale Bandwidth Saturation
- **Likelihood:** LOW
- **Impact:** All app-to-database traffic now flows EDGE→AIOPS→COREDB over Tailscale instead of localhost. PostgreSQL wire protocol is chatty.
- **Mitigation:** Connection pooling (pgBouncer) reduces connections 10:1. Redis pipelining. MinIO uses S3 API (HTTP/2 multiplexed). Assess Tailscale bandwidth: CPX51 has 1 Gbps; database traffic estimated <10 Mbps.
- **Detection:** Tailscale `tailscale status` and Prometheus `tailscale_*` metrics

### Risk 6: LangFlow Memory Without Limits
- **Likelihood:** MEDIUM
- **Impact:** LangFlow (788MB observed, no limit) could consume all available RAM during complex workflow builds.
- **Mitigation:** Apply 1.5GB cgroup limit before migrations begin. This is a pre-existing risk, not caused by migrations, but must be addressed to create safe headroom.
- **Detection:** OOM killer logs in `journalctl -k | grep -i oom`
