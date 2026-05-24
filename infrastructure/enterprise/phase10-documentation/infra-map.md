# Wheeler Enterprise — Infrastructure Map

**Version:** 1.0.0 | **Last Updated:** 2026-05-23 | **Owner:** SRE Team
**Purpose:** Quick-reference lookup for on-call engineers. Find any service, port, volume, or endpoint in under 30 seconds.

---

## 1. Server Inventory

```
┌──────────┬──────────────────┬──────────────┬──────────────┬──────────────────────────────┐
│ Server   │  Public IP       │  Tailscale IP │  Specs        │  Role                        │
├──────────┼──────────────────┼──────────────┼──────────────┼──────────────────────────────┤
│ EDGE     │  187.77.148.88   │  100.98.163.17│  4-8 vCPU    │  Public reverse proxy        │
│          │  (Hostinger)     │              │  8-16 GB RAM  │  Frontend apps               │
│          │                  │              │  100 GB NVMe  │  LiteLLM proxy               │
│          │                  │              │  1 Gbps net   │  Light data tier             │
├──────────┼──────────────────┼──────────────┼──────────────┼──────────────────────────────┤
│ AIOPS    │  5.78.140.118    │  100.121.230.│  16 vCPU     │  Primary orchestrator        │
│          │  (Hetzner CPX51) │  28          │  32 GB RAM    │  AI services, analytics,     │
│          │                  │              │  360 GB NVMe  │  monitoring, agents,         │
│          │                  │              │  1 Gbps net   │  primary DBs                 │
├──────────┼──────────────────┼──────────────┼──────────────┼──────────────────────────────┤
│ COREDB   │  5.78.210.123    │  (tbd)       │  8 vCPU      │  Dedicated database server   │
│          │  (Hetzner CX32)  │              │  16 GB RAM    │  Vector store, object store  │
│          │                  │              │  160 GB NVMe  │  Backup target               │
│          │                  │              │  1 Gbps net   │  Zero public exposure        │
└──────────┴──────────────────┴──────────────┴──────────────┴──────────────────────────────┘
```

---

## 2. Service Catalog

### 2.1 Docker Services

```
Service Name              Server   Port     Purpose                          Dependencies
───────────────────────── ──────── ───────  ───────────────────────────────  ───────────────────
traefik-edge              EDGE     80,443   Public reverse proxy + TLS       DNS, Let's Encrypt
traefik-internal          AIOPS    80,443   Internal routing + mTLS          traefik-edge (upstream)
prediction-radar-api      AIOPS    8000     Prediction Radar REST API        pred-radar-db, pred-radar-redis
prediction-radar-web      AIOPS    8098     Prediction Radar UI              pred-radar-api
prediction-radar-worker   AIOPS    -        Background forecast compute      pred-radar-db, pred-radar-api
prediction-radar-sched    AIOPS    -        Scheduled forecast runner        pred-radar-db
prediction-radar-db       AIOPS    5433     Prediction Radar PostgreSQL      -
prediction-radar-redis    AIOPS    6379     Prediction Radar cache           -
ravynai-api               AIOPS    8007     RavynAI REST API                 ravynai-db, LiteLLM
ravynai-worker            AIOPS    -        Async AI processing              ravynai-db, LiteLLM, NATS
ravynai-db                AIOPS    5434     RavynAI PostgreSQL               -
superset                  AIOPS    8088     Apache Superset dashboards       clickhouse, AIOPS-pg
clickhouse                AIOPS    8123     ClickHouse HTTP interface        -
clickhouse-native         AIOPS    9000     ClickHouse native protocol       -
change-detection          AIOPS    5000     Website change monitoring        -
healthchecks              AIOPS    3130     Cron job monitoring              AIOPS-pg
spiderfoot                AIOPS    8080     OSINT automation tool            -
browser-automation        AIOPS    3000     Headless browser service         -
ai-agent-runtimes         AIOPS    8001+    Custom AI agent executors        LiteLLM, NATS, AIOPS-pg
trading-workers           AIOPS    -        Trading engine workers            NATS, AIOPS-pg, AIOPS-redis
feed-handlers             AIOPS    -        Realtime data feed ingestion      NATS, clickhouse
nats                      AIOPS    4222     NATS message broker              -
rabbitmq                  AIOPS    5672     RabbitMQ message broker           -
prometheus                AIOPS    9090     Metrics collection + alerting     All exporters
grafana                   AIOPS    3002     Dashboard visualization           prometheus, loki
loki                      AIOPS    3100     Log aggregation                  promtail (all servers)
alertmanager              AIOPS    9093     Alert routing + notification     prometheus
uptime-kuma               AIOPS    3001     Synthetic monitoring             -
netdata                   AIOPS    19999    Real-time system metrics          -
portainer                 AIOPS    9443     Docker container management       Docker socket
dockge                    AIOPS    5001     Docker compose UI manager         Docker socket
postgres-aio-main         AIOPS    5432     Primary AI + API database        -
redis-aio-main            AIOPS    6379     Primary cache + pub/sub          -
litellm-proxy             EDGE     4000     AI model proxy + router           Model provider APIs
frgops-app                EDGE     3000     FRGops/FRGCRM application         frgops-pg, frgops-redis
chatwoot                  EDGE     3000     Customer engagement platform      frgops-pg
n8n                       EDGE     5678     Workflow automation               frgops-pg
docuseal                  EDGE     3000     Document signing platform         frgops-pg
minio-edge                EDGE     9001     Light object storage              -
webhook-receiver          EDGE     9000     Inbound webhook processor         NATS
postgres-frgops           EDGE     5432     FRGops dedicated database         -
redis-frgops              EDGE     6379     FRGops cache                     -
postgres-coredb           COREDB   5432     Core business data                -
redis-coredb              COREDB   6379     Shared cache                     -
minio-coredb              COREDB   9000     S3-compatible object store        -
qdrant                    COREDB   6333     Vector embedding database         -
```

### 2.2 PM2 Services (All on AIOPS)

```
PM2 App Name                     Script                  Purpose                     Restarts  Auto-restart
──────────────────────────────── ──────────────────────  ─────────────────────────  ────────  ───────────
pm2-logrotate                    (built-in module)       PM2 log rotation daemon     -         Yes
frgcrm-agent-svc                 frgcrm-agent-svc.js     FRG CRM AI Agent Service    -         Yes
frgcrm-api                       frgcrm-api.js           FRG CRM REST API            -         Yes
frgcrm-mirror-test               frgcrm-mirror-test.js   FRG CRM Mirror Test         -         Yes
insforge-agent-svc               insforge-agent-svc.js   InsForge AI Agent           -         Yes
surplusai-scraper-agent-svc      surplusai-scraper.js    SurplusAI Scraper Agent     -         Yes
voice-agent-svc                  voice-agent-svc.js      Voice AI Agent Service      -         Yes
```

### 2.3 System Services (All Servers)

```
Service         Purpose                        Critical?  Restart Command
──────────────  ─────────────────────────────  ────────   ──────────────────────────
ufw             Host firewall                  YES        ufw reload
fail2ban        Intrusion prevention           YES        systemctl restart fail2ban
docker          Container runtime              YES        systemctl restart docker
tailscale       Mesh networking                YES        systemctl restart tailscaled
ssh             Remote admin access            YES        systemctl restart sshd
rsyslog         System logging                 NO         systemctl restart rsyslog
cron            Scheduled tasks                YES        systemctl restart cron
node_exporter   Prometheus system metrics      YES        systemctl restart node_exporter
unattended-upg  Auto security patches          NO         systemctl restart unattended-upgrades
autoheal        Self-healing daemon (60s)      YES        systemctl restart wheeler-autoheal
```

---

## 3. Port Assignment Master Table

```
Port   Proto  Server          Service                     Public   Access Notes
─────  ─────  ──────────────  ──────────────────────────  ───────  ─────────────────────
22     tcp    ALL             SSH                         No       Tailscale 100.64.0.0/10 only
25     tcp    AIOPS           SMTP (outbound)              No       SendGrid relay
53     udp    ALL             DNS (outbound)               N/A      Cloudflare/Tailscale DNS
80     tcp    EDGE,AIOPS      HTTP → HTTPS redirect        Yes      Traefik auto-redirect
123    udp    ALL             NTP (outbound)               N/A      Time sync
443    tcp    EDGE,AIOPS      HTTPS (TLS termination)      Yes      Traefik + Let's Encrypt
3000   tcp    EDGE            FRGops/Chatwoot/Docuseal     Via CF   Traefik routes to localhost:3000
3000   tcp    AIOPS           API port (agent runtimes)    No       Tailscale only
3001   tcp    AIOPS           Uptime Kuma                  Via CF   Traefik → uptime.wheeler.ai
3002   tcp    AIOPS           Grafana                      Via CF   Traefik → grafana.wheeler.ai
3100   tcp    AIOPS           Loki (HTTP)                  No       Internal + Tailscale
3130   tcp    AIOPS           Healthchecks                 Via CF   Traefik → healthchecks.wheeler.ai
4000   tcp    EDGE            LiteLLM Proxy                Via CF   Traefik → litellm.wheeler.ai
4000   tcp    AIOPS           LiteLLM (internal path)      No       Tailscale only
4222   tcp    AIOPS           NATS                         No       Internal Docker network
5000   tcp    AIOPS           ChangeDetection              Via CF   Traefik → changedetect.wheeler.ai
5001   tcp    AIOPS           Dockge                       No       Tailscale only
5432   tcp    ALL             PostgreSQL                   No       Internal + Tailscale
5433   tcp    AIOPS           Prediction Radar DB          No       Internal Docker network
5434   tcp    AIOPS           RavynAI DB                   No       Internal Docker network
5672   tcp    AIOPS           RabbitMQ                     No       Internal Docker network
5678   tcp    EDGE            n8n                          Via CF   Traefik → n8n.wheeler.ai
6333   tcp    COREDB          Qdrant Vector DB             No       Tailscale only
6379   tcp    ALL             Redis                        No       Internal + Tailscale
8000   tcp    AIOPS           Prediction Radar API         No       Tailscale only
8007   tcp    AIOPS           RavynAI API                  Via CF   Traefik → ravynai.wheeler.ai
8001+  tcp    AIOPS           AI Agent Runtimes            No       Internal Docker network
8080   tcp    AIOPS           Traefik Dashboard            No       Tailscale only
8080   tcp    AIOPS           Spiderfoot                   No       Tailscale only
8082   tcp    ALL             cAdvisor                     No       Internal + Tailscale
8088   tcp    AIOPS           Superset                     Via CF   Traefik → superset.wheeler.ai
8098   tcp    AIOPS           Prediction Radar Web         Via CF   Traefik → predictionradar.wheeler.ai
8123   tcp    AIOPS           ClickHouse HTTP              No       Tailscale only
9000   tcp    COREDB          ClickHouse Native / MinIO    No       Tailscale only
9001   tcp    EDGE,COREDB     MinIO Console                No       Tailscale only
9090   tcp    AIOPS           Prometheus                   No       Tailscale only
9093   tcp    AIOPS           Alertmanager                 No       Internal Docker network
9100   tcp    ALL             Node Exporter                No       Tailscale only
9121   tcp    ALL             Redis Exporter               No       Tailscale only
9187   tcp    ALL             PostgreSQL Exporter          No       Tailscale only
9323   tcp    ALL             Docker Engine Metrics        No       localhost only
9443   tcp    AIOPS           Portainer                    No       Tailscale only
15672  tcp    AIOPS           RabbitMQ Management          No       Tailscale only
19999  tcp    AIOPS           Netdata                      No       Tailscale only
```

---

## 4. Volume Inventory

```
Volume Name                    Server   Estimated Size   Used By                  Backup Frequency
────────────────────────────── ───────  ───────────────  ───────────────────────  ────────────────
prediction-radar_postgres      AIOPS    ~20 GB           Prediction Radar DB       Daily
prediction-radar_redis         AIOPS    ~2 GB            Prediction Radar cache    Weekly
ravynai_postgres               AIOPS    ~15 GB           RavynAI DB                Daily
ravynai_redis                  AIOPS    ~1 GB            RavynAI cache             Weekly
superset_data                  AIOPS    ~5 GB            Superset metadata         Daily
clickhouse_data                AIOPS    ~30 GB           ClickHouse analytics      Weekly
grafana_data                   AIOPS    ~2 GB            Grafana dashboards+config  Daily
prometheus_data                AIOPS    ~40 GB           Prometheus TSDB            Weekly
loki_data                      AIOPS    ~50 GB           Loki log storage           Weekly
uptime_kuma_data               AIOPS    ~500 MB          Uptime Kuma config         Daily
portainer_data                 AIOPS    ~200 MB          Portainer config           Weekly
change_detection_data          AIOPS    ~2 GB            ChangeDetection state      Weekly
healthchecks_data              AIOPS    ~500 MB          Healthchecks state         Daily
traefik_certs                  EDGE     ~50 MB           Traefik ACME certs         Daily
traefik_certs                  AIOPS    ~50 MB           Traefik ACME certs         Daily
frgops_postgres                EDGE     ~10 GB           FRGops/FRGCRM DB           Daily
frgops_redis                   EDGE     ~1 GB            FRGops cache               Weekly
minio_data                     COREDB   ~50 GB           Object storage             Daily
qdrant_data                    COREDB   ~10 GB           Vector embeddings          Daily
postgres_coredb                COREDB   ~30 GB           Core business data         Daily
redis_coredb                   COREDB   ~2 GB            Shared cache               Weekly
nats_data                      AIOPS    ~1 GB            NATS message persistence   Weekly
rabbitmq_data                  AIOPS    ~2 GB            RabbitMQ persistence       Weekly
```

---

## 5. Network Map (Docker Networks)

```
EDGE Server (187.77.148.88):
─────────────────────────────
  traefik-public:      172.20.0.0/24    (Traefik + all frontend apps)
  frgops:              172.30.0.0/24    (FRGops, Chatwoot, Docuseal)
  ai-proxy:            172.31.0.0/24    (LiteLLM Proxy)
  automation:          172.32.0.0/24    (n8n)
  storage:             172.33.0.0/24    (MinIO edge)
  webhooks:            172.34.0.0/24    (Webhook receiver)

AIOPS Server (5.78.140.118):
─────────────────────────────
  traefik-public:      172.20.0.0/24    (Traefik internal + public apps)
  prediction-radar:    172.21.0.0/24    (API, Web, Worker, Scheduler, DB, Redis)
  analytics:           172.22.0.0/24    (Superset + ClickHouse)
  ravynai:             172.25.0.0/24    (API, Worker, DB)
  ai-agents:           172.24.0.0/24    (Agent Runtimes)
  trading:             172.26.0.0/24    (Trading workers, Feed handlers)
  messaging:           172.27.0.0/24    (NATS, RabbitMQ)
  automation:          172.28.0.0/24    (ChangeDetection, BrowserAuto)
  data:                172.29.0.0/24    (PostgreSQL, Redis)
  monitoring:          172.35.0.0/24    (Prometheus, Grafana, Loki, Alertmanager, UptimeKuma, Netdata)
  management:          172.36.0.0/24    (Portainer, Dockge)
  osint:               172.37.0.0/24    (Spiderfoot)

COREDB Server (5.78.210.123):
─────────────────────────────
  data:                172.29.0.0/24    (PostgreSQL, Redis)
  storage:             172.33.0.0/24    (MinIO)
  vectors:             172.38.0.0/24    (Qdrant)
  monitoring:          172.35.0.0/24    (Node Exporter, PG Exporter, Redis Exporter)

Docker bridge config (all servers):
  bip:                 172.26.0.1/16
  Address pool 1:      172.27.0.0/16 (size /24)
  Address pool 2:      172.28.0.0/16 (size /24)
  DNS:                 100.100.100.100 (Tailscale MagicDNS), 1.1.1.1, 8.8.8.8
```

---

## 6. DNS Records

```
All records managed via Cloudflare DNS. TTL: 300s. Proxy: ON (orange cloud).

Record  Name                              Type   Value              Purpose
──────  ────────────────────────────────  ────   ─────────────────  ─────────────────────
@       wheeler.ai                       A      187.77.148.88       Root domain → EDGE
@       *.wheeler.ai                     A      187.77.148.88       Wildcard → EDGE
CNAME   predictionradar.wheeler.ai       CNAME  wheeler.ai          Prediction Radar
CNAME   ravynai.wheeler.ai               CNAME  wheeler.ai          RavynAI
CNAME   superset.wheeler.ai              CNAME  wheeler.ai          Apache Superset
CNAME   grafana.wheeler.ai               CNAME  wheeler.ai          Grafana
CNAME   uptime.wheeler.ai                CNAME  wheeler.ai          Uptime Kuma
CNAME   status.wheeler.ai                CNAME  wheeler.ai          Status page
CNAME   healthchecks.wheeler.ai          CNAME  wheeler.ai          Healthchecks.io
CNAME   changedetect.wheeler.ai          CNAME  wheeler.ai          ChangeDetection
CNAME   docuseal.wheeler.ai              CNAME  wheeler.ai          Docuseal
CNAME   frgops.wheeler.ai                CNAME  wheeler.ai          FRGops
CNAME   chatwoot.wheeler.ai              CNAME  wheeler.ai          Chatwoot
CNAME   n8n.wheeler.ai                   CNAME  wheeler.ai          n8n
CNAME   litellm.wheeler.ai               CNAME  wheeler.ai          LiteLLM Proxy
CNAME   netdata.wheeler.ai               CNAME  wheeler.ai          Netdata

Internal DNS (Tailscale MagicDNS):
  edge.wheeler-enterprise.ts.net     → 100.98.163.17
  aiops.wheeler-enterprise.ts.net    → 100.121.230.28
  coredb.wheeler-enterprise.ts.net   → (provisioning)
```

---

## 7. Certificate Inventory

```
Domain                            Provider        Expiry          Auto-Renew   Notes
───────────────────────────────── ──────────────  ──────────────  ──────────   ─────
*.wheeler.ai                      Let's Encrypt   Auto-renewed    Yes          Wildcard via Traefik ACME
wheeler.ai                        Let's Encrypt   Auto-renewed    Yes          SAN on wildcard
*.internal.wheeler.ai             Let's Encrypt   Auto-renewed    Yes          AIOPS internal Traefik

Monitoring:
  ├ Uptime Kuma checks every 30s → SSL expiry alert at 30 days
  ├ Prometheus alert SSLCertExpiring (7 days CRITICAL, 30 days WARNING)
  └ Manual check: bash healthcheck-all.sh (SSL validity section)

Manual Renewal Procedure:
  1. SSH to EDGE via Tailscale
  2. docker exec traefik traefik cert renew --dry-run (check)
  3. docker exec traefik traefik cert renew --force (force if needed)
  4. docker restart traefik (if config changed)
```

---

## 8. Environment Variables Catalog

### 8.1 Global / Cross-Cutting

```
Variable                    Used By                  Secret?   Purpose
─────────────────────────── ───────────────────────  ───────   ───────────────────────
TAILSCALE_AUTH_KEY          tailscale (all)          YES       Tailscale auth key
GRAFANA_ADMIN_PASSWORD      grafana                  YES       Grafana admin login
SLACK_WEBHOOK_URL           alertmanager             YES       Alert Slack webhook
SENDGRID_API_KEY            alertmanager, apps       YES       Email sending via SendGrid
PAGERDUTY_ROUTING_KEY       alertmanager             YES       PagerDuty integration
WHEELER_ENV                 all apps                 NO        Environment: production/staging
SERVER_ROLE                 all servers              NO        Role: edge/aiops/coredb
LOG_FORMAT                  all apps                 NO        json/text log format
NODE_ENV                    PM2 apps                 NO        production
```

### 8.2 Database Credentials

```
Variable                    Used By                  Secret?   Default Value (Hint)
─────────────────────────── ───────────────────────  ───────   ───────────────────────
POSTGRES_PASSWORD_AIOPS     postgres-aio-main        YES       (set per env)
POSTGRES_USER_AIOPS         postgres-aio-main        NO        wheeler_admin
POSTGRES_DB_AIOPS           postgres-aio-main        NO        wheeler
POSTGRES_PASSWORD_FRGOPS    postgres-frgops          YES       (set per env)
POSTGRES_PASSWORD_COREDB    postgres-coredb           YES       (set per env)
REDIS_PASSWORD_AIOPS        redis-aio-main           YES       (set per env)
REDIS_PASSWORD_FRGOPS       redis-frgops             YES       (set per env)
REDIS_PASSWORD_COREDB       redis-coredb             YES       (set per env)
CLICKHOUSE_PASSWORD         clickhouse               YES       (set per env)
```

### 8.3 AI Provider API Keys

```
Variable                    Used By                  Secret?   Provider
─────────────────────────── ───────────────────────  ───────   ────────────
DEEPSEEK_API_KEY            LiteLLM, agents          YES       DeepSeek
ANTHROPIC_API_KEY           LiteLLM, agents          YES       Anthropic
OPENAI_API_KEY              LiteLLM, agents          YES       OpenAI
LITELLM_MASTER_KEY          LiteLLM Proxy            YES       LiteLLM admin
LANGFUSE_PUBLIC_KEY         LangFlow, agents         YES       LangFuse tracing
LANGFUSE_SECRET_KEY         LangFlow, agents         YES       LangFuse tracing
```

### 8.4 Docker Compose Environment

```
Variable                    Used By                  Secret?   Purpose
─────────────────────────── ───────────────────────  ───────   ───────────────────────
COMPOSE_PROJECT_NAME        docker compose           NO        Project naming prefix
DOCKER_HOST                 docker commands          NO        Docker socket path
TRAEFIK_ACME_EMAIL          traefik                  NO        Let's Encrypt registration
CLOUDFLARE_EMAIL            cert management          NO        DNS management
CLOUDFLARE_API_TOKEN        cert management          YES       Cloudflare API token
```

---

## 9. Cron Job Inventory

```
Schedule        Server   Command / Script                          Purpose
──────────────  ───────  ────────────────────────────────────────  ────────────────────
*/1 * * * *     ALL      /root/infrastructure/autoheal.sh          Self-healing daemon
*/5 * * * *     ALL      /root/infrastructure/enterprise/phase4-healthcheck/healthcheck-all.sh --prometheus
                                                                   Health check → Prometheus
0 3 * * *       AIOPS    /root/infrastructure/enterprise/phase6-backup/backup-databases.sh
                                                                   Daily database backup
0 3 * * *       AIOPS    /root/infrastructure/enterprise/phase6-backup/backup-volumes.sh
                                                                   Daily volume backup
0 4 * * *       AIOPS    /root/infrastructure/enterprise/phase6-backup/backup-offsite.sh
                                                                   Off-site backup sync
0 6 * * *       ALL      /usr/sbin/logrotate /etc/logrotate.d/wheeler-enterprise
                                                                   Log rotation
*/30 * * * *    AIOPS    /root/infrastructure/enterprise/phase4-healthcheck/healthcheck-all.sh --json
                                                                   Health report generation
0 */6 * * *     ALL      unattended-upgrades (apt)                 Security auto-updates
0 0 1 * *       AIOPS    /root/infrastructure/enterprise/phase6-backup/backup-verify.sh
                                                                   Monthly backup verification
0 2 * * 0       AIOPS    docker system prune -af --volumes          Weekly Docker cleanup
0 0 * * *       ALL      certbot renew --quiet (fallback)          Certificate renewal (fallback)
```

---

## 10. Health Check Endpoints

### 10.1 Public Endpoints (HTTP/HTTPS)

```
Service                    Health URL                                    Expected   Timeout
─────────────────────────  ────────────────────────────────────────────  ────────   ───────
Traefik Dashboard          http://localhost:8080/api/rawdata              200        5s
FRGops                     https://frgops.wheeler.ai/api/health           200        10s
Chatwoot                   https://chatwoot.wheeler.ai/health             200        10s
n8n                        https://n8n.wheeler.ai/healthz                 200        10s
Docuseal                   https://docuseal.wheeler.ai/health             200        10s
LiteLLM                    https://litellm.wheeler.ai/health              200        5s
Prediction Radar           https://predictionradar.wheeler.ai/health      200        10s
RavynAI                    https://ravynai.wheeler.ai/health              200        10s
Superset                   https://superset.wheeler.ai/health             200        10s
Grafana                    https://grafana.wheeler.ai/api/health          200        5s
Healthchecks               https://healthchecks.wheeler.ai/api/v1/health  200        5s
Uptime Kuma                https://uptime.wheeler.ai                      200        5s
ChangeDetection            https://changedetect.wheeler.ai/health         200        5s
```

### 10.2 Internal Endpoints (Tailscale Only)

```
Service                    Health Check Method                            Expected
─────────────────────────  ────────────────────────────────────────────  ──────────
PostgreSQL (all instances) docker exec <container> pg_isready -U postgres  accepting
Redis (all instances)      docker exec <container> redis-cli PING         PONG
ClickHouse                 curl http://localhost:8123/ping                Ok.
NATS                       docker exec nats nats server check             healthy
RabbitMQ                   curl http://localhost:15672/api/health/checks/alarms  ok
Prometheus                 curl http://localhost:9090/-/healthy           healthy
Loki                       curl http://localhost:3100/ready               ready
Alertmanager               curl http://localhost:9093/-/healthy           healthy
Netdata                    curl http://localhost:19999/api/v1/info        200
Portainer                  curl -k https://localhost:9443/api/status      200
Qdrant                     curl http://localhost:6333/health              200
MinIO                      curl http://localhost:9000/minio/health/live   200
```

### 10.3 PM2 Health (AIOPS)

```
Service                    Check Command                                  Expected
─────────────────────────  ────────────────────────────────────────────  ──────────
frgcrm-agent-svc           pm2 show frgcrm-agent-svc | grep status        online
frgcrm-api                 pm2 show frgcrm-api | grep status              online
frgcrm-mirror-test         pm2 show frgcrm-mirror-test | grep status      online
insforge-agent-svc         pm2 show insforge-agent-svc | grep status      online
surplusai-scraper-agent-svc pm2 show surplusai-scraper-agent-svc | grep status online
voice-agent-svc            pm2 show voice-agent-svc | grep status         online
```

### 10.4 System-Level Checks

```
Check                      Command                                        Expected
─────────────────────────  ────────────────────────────────────────────  ──────────
Docker daemon              docker info > /dev/null                        exit 0
Tailscale                  tailscale status | grep connected               connected
UFW                        ufw status | grep active                       active
fail2ban                   systemctl is-active fail2ban                   active
Disk usage                 df -h / | tail -1 | awk '{print $5}'           < 90%
Memory                     free | awk '/^Mem:/{printf "%.0f", $3/$2*100}' < 90%
CPU load                   awk '{print $1}' /proc/loadavg                 < core_count
```

---

## 11. Quick-Access Commands

### 11.1 Emergency Diagnostic One-Liners

```bash
# Full health check across all servers
bash /root/infrastructure/enterprise/phase4-healthcheck/healthcheck-all.sh

# Check all Docker containers
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Check all PM2 services
pm2 status

# Check all listening ports
ss -tlnp

# Check disk usage
df -h / /var/lib/docker /opt/backups

# Check memory usage
free -h; cat /proc/pressure/memory

# Check logs for errors (last 100 lines, all containers)
for c in $(docker ps -q); do echo "=== $(docker inspect -f '{{.Name}}' $c) ==="; docker logs --tail 20 $c 2>&1 | grep -iE 'error|fail|panic' || echo "(no errors)"; done

# Check Tailscale status
tailscale status

# Check UFW status
ufw status verbose

# Check fail2ban status
fail2ban-client status

# Check SSL certs
for d in predictionradar.wheeler.ai ravynai.wheeler.ai grafana.wheeler.ai; do
  echo | openssl s_client -servername "$d" -connect "$d:443" 2>/dev/null | \
    openssl x509 -noout -dates | grep notAfter
done
```

### 11.2 Common Restart Commands

```bash
# Restart a single Docker service
docker compose -f /path/to/compose.yml restart <service-name>

# Restart entire Docker stack
docker compose -f /path/to/compose.yml down && docker compose -f /path/to/compose.yml up -d

# Restart a PM2 service
pm2 restart <app-name>

# Restart Traefik (graceful, no dropped connections)
docker exec traefik traefik healthcheck  # verify healthy first
docker restart traefik

# Restart fail2ban after config change
systemctl restart fail2ban

# Restart Tailscale
systemctl restart tailscaled

# Graceful server reboot procedure
pm2 save
docker compose ls --format json | jq -r '.[].ConfigFiles' | xargs -I{} dirname {} | \
  while read dir; do (cd "$dir" && docker compose stop); done
shutdown -r +5 "Planned maintenance reboot in 5 minutes"
```

---

## Document Control

| Version | Date       | Author   | Changes                          |
|---------|------------|----------|----------------------------------|
| 1.0.0   | 2026-05-23 | SRE Team | Initial infrastructure map       |

**Next Review:** 2026-08-23
