# Wheeler Deployment & Release Engineering Architecture

**Version:** 1.0.0
**Last Updated:** 2026-05-23
**Owner:** Platform Engineering / Release Engineering
**Scope:** All Wheeler services across Hostinger (Edge), Hetzner AIOPS, and Hetzner COREDB nodes

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Deployment Topology](#deployment-topology)
3. [Node Specifications](#node-specifications)
4. [Service Catalog](#service-catalog)
5. [Deployment Patterns](#deployment-patterns)
6. [Zero-Downtime Deployment Strategy](#zero-downtime-deployment-strategy)
7. [Rollback-First Strategy](#rollback-first-strategy)
8. [Health Check Strategy](#health-check-strategy)
9. [Backup-Before-Deploy Policy](#backup-before-deploy-policy)
10. [Traffic Flow During Deployment](#traffic-flow-during-deployment)
11. [Service Dependency Ordering](#service-dependency-ordering)
12. [CI/CD Pipeline Integration](#cicd-pipeline-integration)
13. [Emergency Procedures](#emergency-procedures)

---

## Architecture Overview

The Wheeler platform is deployed across three physically and logically separated nodes, each serving a distinct role in the system architecture. This separation enforces security boundaries, failure isolation, and resource optimization.

### Design Principles

1. **Separation of Concerns**: Edge, Compute, and Data tiers are isolated
2. **Defense in Depth**: Each node has its own firewall, monitoring, and access control
3. **Graceful Degradation**: Each tier can operate in a degraded mode independently
4. **Rollback-First**: Every deployment MUST have a tested, automated rollback path
5. **Observability Built-In**: Health checks, metrics, and logging are non-negotiable
6. **Infrastructure as Code**: All configurations are versioned and auditable

---

## Deployment Topology

```
                                INTERNET / PUBLIC TRAFFIC
                                       |
                               Cloudflare DNS / WAF
                                       |
                                       v
                    +--------------------------------------+
                    |                                      |
                    v                                      v
         +------------------+              +----------------------------+
         |  EDGE NODE        |              |  INTERNAL ADMIN ACCESS     |
         |  (Hostinger)      |              |  (VPN / SSH Bastion)       |
         |  187.77.148.88    |              +----------------------------+
         +------------------+
         |                  |
         |  TRAEFIK (80/443)|
         |  - Reverse Proxy |
         |  - SSL Term      |
         |  - Rate Limiting |
         |  - WAF Rules     |
         |                  |
         |  NGINX (8080)    |
         |  - Static Assets |
         |  - Cache Proxy   |
         |  - Gzip/Brotli   |
         |                  |
         |  FRONTEND APPS:  |
         |  - Wheeler Hub   |
         |  - Ops Dashboard |
         |  - Admin Panel   |
         |  - Client Portal |
         |  - Status Page   |
         +--------+---------+
                  |
                  | HTTPS (internal API calls)
                  | over WireGuard VPN tunnel
                  |
                  v
         +------------------+              +----------------------------+
         |  AIOPS NODE       |              |  COREDB NODE               |
         |  (Hetzner)        |<------------>|  (Hetzner)                 |
         |  5.78.140.118     |   internal    |  5.78.210.123              |
         +------------------+   10.x.x.x    +----------------------------+
         |                  |               |                            |
         |  PM2 PROCESSES:  |               |  PostgreSQL (5432)          |
         |                  |               |  - Wheeler Core DB          |
         |  -- API Layer -- |               |  - Analytics DB             |
         |  Wheeler API     |               |  - Log DB                   |
         |  Revenue API     |               |                            |
         |  Webhook Gateway |               |  Redis (6379)               |
         |  Admin API       |               |  - Session Store            |
         |  GraphQL Gateway |               |  - Rate Limit Cache         |
         |                  |               |  - Job Queue (BullMQ)       |
         |  -- AI Layer --  |               |  - Pub/Sub Events           |
         |  LiteLLM Proxy   |               |                            |
         |  OpenClaw Engine |               |  MinIO (9000/9001)          |
         |  ML Workers (xN) |               |  - Document Storage         |
         |  Inference API   |               |  - Model Artifacts          |
         |  Model Cache     |               |  - Backup Storage           |
         |                  |               |  - Log Archives             |
         |  -- Ops Layer -- |               |                            |
         |  Orchestrator    |               |  Vector DB (Qdrant:6333)    |
         |  Autoheal Engine |               |  - Embedding Storage        |
         |  Alert Engine    |               |  - Semantic Search          |
         |  Cost Monitor    |               |  - RAG Knowledge Base       |
         |  Eco Health Eng  |               |                            |
         |                  |               |  Observability Stack:       |
         |  DOCKER:         |               |  - Grafana (3000)           |
         |  - ChangeDetect  |               |  - Prometheus (9090)        |
         |  - HealthChecks  |               |  - Loki (3100)              |
         |  - N8n (if used) |               |  - Tempo (3200)             |
         |                  |               |  - AlertManager (9093)      |
         +------------------+               +----------------------------+

    Communication Legend:
    ===================    HTTPS/TLS (public internet)
    - - - - - - - - - -    Internal VPN tunnel (WireGuard)
    <--------------->      Direct internal network (private IPs)
    .....................   Database protocol connections (authenticated)
```

---

## Node Specifications

### EDGE NODE — Hostinger VPS (187.77.148.88)

| Attribute    | Value                        |
|-------------|------------------------------|
| **Role**    | Public-facing edge routing    |
| **OS**      | Ubuntu 22.04 LTS              |
| **CPU**     | 4 vCPU                        |
| **RAM**     | 8 GB                          |
| **Storage** | 160 GB SSD                    |
| **Network** | 1 Gbps, public IP             |
| **Firewall**| UFW: 80, 443, 22 (restricted) |

**Running Services:**
- **Traefik v3** — Edge reverse proxy, SSL termination via Let's Encrypt
- **Nginx** — Static asset serving, cache proxy, compression
- **Frontend Applications** — Wheeler Hub, Ops Dashboard, Admin Panel, Client Portal, Status Page
- **WireGuard** — VPN tunnel endpoint to Hetzner nodes

**Deployment Mechanism:** Docker Compose (Traefik, Nginx) + PM2 (frontend Node.js apps)

---

### AIOPS NODE — Hetzner VPS (5.78.140.118)

| Attribute    | Value                        |
|-------------|------------------------------|
| **Role**    | API + AI compute + orchestration |
| **OS**      | Ubuntu 22.04 LTS              |
| **CPU**     | 8 vCPU (dedicated)            |
| **RAM**     | 32 GB                         |
| **Storage** | 240 GB NVMe                   |
| **Network** | 1 Gbps, public IP (restricted)|

**Running Services:**
- **Wheeler API Server** — PM2-managed Node.js/Express
- **Revenue API** — PM2-managed Node.js/Fastify
- **Webhook Gateway** — PM2-managed Node.js
- **Admin API** — PM2-managed Node.js
- **GraphQL Gateway** — PM2-managed Node.js/Apollo
- **LiteLLM Proxy** — PM2-managed Python uvicorn
- **OpenClaw Engine** — PM2-managed Python
- **ML Workers (x4)** — PM2-managed Python/Celery-style
- **Inference API** — PM2-managed Python/FastAPI
- **Orchestrator** — PM2-managed Node.js worker
- **Autoheal Engine** — PM2-managed Python
- **Alert Engine** — PM2-managed Python
- **Cost Monitor** — PM2-managed Python
- **Ecosystem Health Engine** — PM2-managed Python
- **ChangeDetection** — Docker container
- **HealthChecks** — Docker container

**Deployment Mechanism:** PM2 (dominant) + Docker Compose (utility services)

---

### COREDB NODE — Hetzner VPS (5.78.210.123)

| Attribute    | Value                        |
|-------------|------------------------------|
| **Role**    | Data persistence, storage, observability |
| **OS**      | Ubuntu 22.04 LTS              |
| **CPU**     | 4 vCPU (dedicated)            |
| **RAM**     | 16 GB                         |
| **Storage** | 160 GB NVMe + 200 GB block volume |
| **Network** | 1 Gbps, public IP (restricted)|

**Running Services:**
- **PostgreSQL 16** — Primary database (systemd)
- **Redis 7** — Cache, queues, pub/sub (systemd)
- **MinIO** — S3-compatible object storage (systemd)
- **Qdrant** — Vector database (Docker)
- **Grafana** — Dashboards (Docker)
- **Prometheus** — Metrics collection (Docker)
- **Loki** — Log aggregation (Docker)
- **Tempo** — Distributed tracing (Docker)
- **AlertManager** — Alert routing (Docker)

**Deployment Mechanism:** systemd (critical data services) + Docker Compose (observability stack)

**Critical Rule:** NEVER restart PostgreSQL or Redis as part of an application deployment. The COREDB node has its own maintenance window and procedures.

---

## Service Catalog

### Edge Services (Hostinger)

| Service ID           | Type         | Runtime    | Port  | Health Endpoint      | Dependencies                    |
|---------------------|-------------|-----------|-------|---------------------|----------------------------------|
| `traefik`           | Reverse Proxy| Docker    | 80,443| `/ping` (Traefik API)| None (entry point)              |
| `nginx`             | Static/Cache | Docker    | 8080  | `/nginx-health`      | Traefik                        |
| `wheeler-hub`       | Frontend     | PM2       | 3000  | `/api/health`        | nginx, wheeler-api (AIOPS)     |
| `ops-dashboard`     | Frontend     | PM2       | 3001  | `/api/health`        | nginx, wheeler-api (AIOPS)     |
| `admin-panel`       | Frontend     | PM2       | 3002  | `/api/health`        | nginx, admin-api (AIOPS)       |
| `client-portal`     | Frontend     | PM2       | 3003  | `/api/health`        | nginx, revenue-api (AIOPS)     |
| `status-page`       | Frontend     | PM2       | 3004  | `/api/health`        | nginx (static)                 |

### API Services (Hetzner AIOPS)

| Service ID           | Type         | Runtime    | Port  | Health Endpoint      | Dependencies                    |
|---------------------|-------------|-----------|-------|---------------------|----------------------------------|
| `wheeler-api`       | REST API     | PM2/Node  | 4000  | `/health`            | PostgreSQL, Redis, LiteLLM      |
| `revenue-api`       | REST API     | PM2/Node  | 4001  | `/health`            | PostgreSQL, Redis               |
| `webhook-gateway`   | Webhook      | PM2/Node  | 4002  | `/health`            | PostgreSQL, Redis               |
| `admin-api`         | REST API     | PM2/Node  | 4003  | `/health`            | PostgreSQL, Redis               |
| `graphql-gateway`   | GraphQL      | PM2/Node  | 4004  | `/health`            | wheeler-api, revenue-api        |

### AI Worker Services (Hetzner AIOPS)

| Service ID           | Type         | Runtime    | Port  | Health Endpoint      | Dependencies                    |
|---------------------|-------------|-----------|-------|---------------------|----------------------------------|
| `litellm-proxy`     | LLM Proxy    | PM2/Python| 5000  | `/health`            | Redis (rate limiting)           |
| `openclaw-engine`   | AI Engine    | PM2/Python| 5001  | `/health`            | PostgreSQL, Redis, Qdrant       |
| `ml-workers`        | ML Workers   | PM2/Python| N/A   | PM2 status           | PostgreSQL, Redis, MinIO        |
| `inference-api`     | ML Inference | PM2/Python| 5003  | `/health`            | Redis, MinIO (models)           |
| `model-cache`       | Cache        | PM2/Node  | 5004  | `/health`            | MinIO                           |

### Ops Services (Hetzner AIOPS)

| Service ID           | Type         | Runtime    | Port  | Health Endpoint      | Dependencies                    |
|---------------------|-------------|-----------|-------|---------------------|----------------------------------|
| `orchestrator`      | Orchestrator | PM2/Node  | 6000  | `/health`            | PostgreSQL, Redis               |
| `autoheal-engine`   | Auto-Remed.  | PM2/Python| 6001  | `/health`            | PostgreSQL, Prometheus          |
| `alert-engine`      | Alerts       | PM2/Python| 6002  | `/health`            | PostgreSQL, Redis, AlertManager |
| `cost-monitor`      | Cost Track.  | PM2/Python| 6003  | `/health`            | PostgreSQL                      |
| `eco-health-eng`    | Health Mon.  | PM2/Python| 6004  | `/health`            | Prometheus, Loki, Grafana       |

### Docker Services (Hetzner AIOPS)

| Service ID           | Type         | Runtime    | Port  | Health Endpoint      | Dependencies                    |
|---------------------|-------------|-----------|-------|---------------------|----------------------------------|
| `changedetection`   | Monitoring   | Docker    | 5000  | `/api/health`        | PostgreSQL                      |
| `healthchecks`      | Monitoring   | Docker    | 8000  | `/health`            | PostgreSQL                      |

### Data Services (Hetzner COREDB)

| Service ID           | Type         | Runtime    | Port  | Health Check         | Dependencies                    |
|---------------------|-------------|-----------|-------|---------------------|----------------------------------|
| `postgresql`         | Database     | systemd   | 5432  | pg_isready           | None (foundational)             |
| `redis`              | Cache/Queue  | systemd   | 6379  | redis-cli PING       | None (foundational)             |
| `minio`              | Object Store | systemd   | 9000  | `/minio/health/live` | None (foundational)             |
| `qdrant`             | Vector DB    | Docker    | 6333  | `/health`            | None (foundational)             |
| `grafana`            | Dashboards   | Docker    | 3000  | `/api/health`        | Prometheus, Loki                |
| `prometheus`         | Metrics      | Docker    | 9090  | `/-/healthy`         | None                            |
| `loki`               | Logs         | Docker    | 3100  | `/ready`             | MinIO (S3 backend)              |
| `tempo`              | Tracing      | Docker    | 3200  | `/ready`             | MinIO (S3 backend)              |
| `alertmanager`       | Alerts       | Docker    | 9093  | `/-/healthy`         | None                            |

---

## Deployment Patterns

### Pattern 1: Docker Deployment (Traefik, Nginx, Utility Services)

```
DEPLOYMENT FLOW:
  preflight-check  -->  backup-configs  -->  docker pull <new-image>
  -->  docker-compose up -d --no-deps <service> (creates new container)
  -->  health-check (new container)  -->  verify-deployment
  -->  [on failure] rollback-deployment
  -->  log-deploy-event

KEY CHARACTERISTICS:
  - Image is pulled BEFORE stopping the old container
  - New container starts alongside old on temporary port
  - Health check validates new container BEFORE traffic switch
  - Traefik/Nginx configs are updated atomically (mv, not cp)
  - Old container is stopped only after new container passes health check
  - Old container is kept for 60 seconds (quick rollback window)
  - Container images are never deleted — they accumulate for fast rollback
```

#### Docker Zero-Downtime Strategy

```
Phase 1: PREPARE
  docker pull <image>:<new-tag>
  docker-compose config validation
  Backup current configs/volumes

Phase 2: DEPLOY (blue-green)
  docker-compose up -d --no-deps --scale <service>=2 <service>
  # Now both old and new containers are running
  # New container is on a temporary internal port

Phase 3: VERIFY
  curl http://localhost:<temp-port>/health (with retries)
  Check container logs for errors
  Check resource usage

Phase 4: SWITCH
  Update Traefik/Nginx config to point to new container port
  Reload Traefik/Nginx (graceful, < 1s disruption)
  Wait for connections to drain from old container

Phase 5: CLEANUP
  Stop old container
  Remove old container (keep image for rollback)
```

### Pattern 2: PM2 Deployment (Node.js APIs, Python Workers)

```
DEPLOYMENT FLOW:
  preflight-check  -->  backup-configs  -->  git pull / rsync code
  -->  npm install / pip install (if needed)
  -->  pm2 reload <service-name> (zero-downtime if in cluster mode)
  -->  health-check  -->  verify-deployment
  -->  [on failure] rollback-deployment
  -->  log-deploy-event

KEY CHARACTERISTICS:
  - Code is deployed to a timestamped directory
  - Symlink is updated atomically to point to new code
  - PM2 graceful reload sends SIGTERM, waits, then SIGKILL
  - PM2 cluster mode enables true zero-downtime
  - Environment variables are reloaded (--update-env)
  - Pre/post deploy scripts run in sequence
```

#### PM2 Zero-Downtime Strategy

```
Phase 1: PREPARE
  Deploy new code to /opt/wheeler/<service>/releases/<timestamp>/
  Run npm install --production / pip install -r requirements.txt
  Symlink ../../shared/.env -> .env (shared config)

Phase 2: ATOMIC SWITCH
  ln -sfn /opt/wheeler/<service>/releases/<timestamp> /opt/wheeler/<service>/current
  # PM2 ecosystem is configured to use /opt/wheeler/<service>/current

Phase 3: GRACEFUL RELOAD
  pm2 reload <service-name> --update-env
  # PM2 sends SIGINT to old process, waits for graceful shutdown
  # New process starts while old is draining
  # When old process exits, new process is already accepting connections

Phase 4: VERIFY
  curl http://localhost:<port>/health
  pm2 show <service-name> (check status, restarts, uptime)
  Check logs: pm2 logs <service-name> --lines 50 --nostream

Phase 5: CLEANUP (deferred)
  Keep last 5 releases for rollback
  pm2 save (persist process list)
```

### Pattern 3: DB-Safe Deployment (PostgreSQL, Redis, MinIO)

```
CRITICAL RULE: Database services follow a DIFFERENT deployment cadence.
They are NOT deployed alongside application services.

DEPLOYMENT FLOW (for config changes only):
  maintenance-window-check  -->  notify-stakeholders
  -->  backup-database (pg_dumpall / redis BGSAVE / minio mirror)
  -->  verify-backup  -->  apply-config-change
  -->  validate-connections  -->  notify-complete

DEPLOYMENT FLOW (for version upgrades):
  maintenance-window-check  -->  notify-stakeholders
  -->  backup-database (FULL)  -->  verify-backup
  -->  stop-application-services (drain connections)
  -->  upgrade-database-software  -->  start-database
  -->  validate-data-integrity  -->  start-application-services
  -->  run-smoke-tests  -->  notify-complete

KEY CHARACTERISTICS:
  - Database deployments happen in DECLARED MAINTENANCE WINDOWS
  - All application services are drained before DB changes
  - pgBouncer (if used) provides connection pooling and graceful failover
  - WAL archiving is enabled for point-in-time recovery
  - Replication lag is checked before promotion
```

---

## Zero-Downtime Deployment Strategy

### Strategy Matrix by Service Type

| Service Category | Strategy          | Max Downtime | Rollback Time | Risk Level |
|-----------------|-------------------|-------------|---------------|------------|
| Frontend (PM2)  | Blue-green deploy | 0s          | < 30s         | Low        |
| API (PM2)       | Rolling reload    | 0s (cluster) | < 30s         | Low        |
| AI Workers (PM2)| Graceful restart  | < 5s         | < 30s         | Medium     |
| Docker (stateless)| Container swap  | 0s           | < 60s         | Low        |
| Docker (stateful) | Drain + redeploy| < 10s       | < 120s        | Medium     |
| Database (systemd)| Maintenance win. | Planned     | Per plan      | High       |

### Rolling Update Procedure (PM2 Cluster)

```
Given: wheeler-api running in cluster mode with 4 instances

Step 1: Deploy new code to releases/<timestamp>/
Step 2: Run pre-deploy validation
Step 3: pm2 reload wheeler-api --update-env
        └─ PM2 internally:
           ├─ Spawns instance-5 with new code (old instances 1-4 still running)
           ├─ Instance-5 signals "ready"
           ├─ PM2 sends SIGINT to instance-1 (oldest)
           ├─ Instance-1 drains connections, exits
           ├─ PM2 spawns instance-6 with new code
           ├─ PM2 sends SIGINT to instance-2
           ├─ ... continues until all 4 instances are new code
Step 4: Health check against ALL instances
Step 5: Verify metrics (error rate, latency, throughput)
Step 6: If healthy, mark deployment complete
Step 7: If unhealthy, pm2 reload wheeler-api (rollback to previous release)
```

### Graceful Shutdown Contract

Every service MUST implement this shutdown sequence:

```javascript
// Node.js example
process.on('SIGINT', async () => {
  console.log('Received SIGINT, shutting down gracefully...');
  server.close(() => {
    console.log('HTTP server closed');
  });
  await database.disconnect();
  await messageQueue.disconnect();
  // Allow in-flight requests to complete (max 25 seconds)
  await sleep(25000);
  process.exit(0);
});
```

```python
# Python example
import signal, sys

def graceful_shutdown(signum, frame):
    logger.info(f"Received signal {signum}, shutting down...")
    server.shutdown()  # Stop accepting new connections
    drain_connections(timeout=25)
    db.disconnect()
    mq.disconnect()
    sys.exit(0)

signal.signal(signal.SIGTERM, graceful_shutdown)
```

---

## Rollback-First Strategy

### Core Principle

**Every deployment MUST have a tested, automated rollback path BEFORE the deploy command is executed.**

### Rollback Decision Tree

```
DEPLOYMENT INITIATED
       |
       v
  Pre-flight checks pass?
       |
   No  |  Yes
    v       v
  ABORT  Deploy new version
         |
         v
    Health check pass?
         |
     No  |  Yes
      v       v
  AUTO-ROLLBACK  Monitor (5 min)
      |              |
      v              v
  Verify rollback  Anomaly detected?
      |              |
      v          No  |  Yes
  Log incident       v      v
                  STABLE  AUTO-ROLLBACK
```

### Rollback Methods by Service Type

| Service Type | Rollback Method                                | Time to Complete |
|-------------|------------------------------------------------|-------------------|
| PM2 App     | `pm2 reload` with previous release symlink      | < 30 seconds      |
| Docker      | `docker-compose up -d` with previous image tag  | < 60 seconds      |
| DB Config   | Revert config file, SIGHUP or restart           | < 120 seconds     |
| DB Migration | Run down migration (MUST be tested first)       | Per migration     |

### Rollback Commands Reference

```bash
# PM2 Application Rollback
./deployment-engine/rollback-deployment.sh wheeler-api production

# Docker Service Rollback
./deployment-engine/rollback-deployment.sh changedetection production

# Emergency Global Rollback (all services on a node)
./deployment-engine/rollback-deployment.sh --all --node=aiops production
```

### Rollback Validation Checklist

After every rollback, the following MUST be verified:

- [ ] Service responds to health check (HTTP 200)
- [ ] All dependencies are reachable
- [ ] Error rate returns to pre-deployment baseline
- [ ] No data corruption (spot-check critical records)
- [ ] Queue backlog begins processing
- [ ] Alert silence period ends normally
- [ ] Log rollback event to audit trail

---

## Health Check Strategy

### Health Check Hierarchy

```
LEVEL 0: Process Alive     — Is the process running? (ps, pm2 status, docker ps)
LEVEL 1: Port Listening    — Is the port bound? (ss -tlnp, netstat)
LEVEL 2: HTTP Responding   — Does /health return 200? (curl)
LEVEL 3: Dependency Check  — Can it reach DB, Redis, etc.? (internal check)
LEVEL 4: Functional Check  — Can it perform a representative operation?
LEVEL 5: Business Check    — Are key business metrics within SLA?
```

### Health Endpoint Specification

Every service MUST expose a `/health` endpoint returning this JSON structure:

```json
{
  "status": "healthy",
  "service": "wheeler-api",
  "version": "2.4.1",
  "uptime": 123456,
  "timestamp": "2026-05-23T12:00:00Z",
  "checks": {
    "database": {
      "status": "ok",
      "latency_ms": 2.3
    },
    "redis": {
      "status": "ok",
      "latency_ms": 0.8
    },
    "disk": {
      "status": "ok",
      "usage_percent": 45
    },
    "memory": {
      "status": "ok",
      "usage_percent": 62,
      "heap_mb": 512
    }
  }
}
```

### Health Check Configuration

```bash
# Defaults used by deployment scripts
HEALTH_CHECK_TIMEOUT=30          # Max seconds to wait for health
HEALTH_CHECK_INTERVAL=2          # Seconds between retries
HEALTH_CHECK_RETRIES=15          # Max retry attempts
HEALTH_CHECK_ENDPOINT="/health"  # Default endpoint
```

### Traefik Health Checks (Edge)

```yaml
# traefik dynamic config
http:
  services:
    wheeler-api:
      loadBalancer:
        healthCheck:
          path: /health
          interval: 10s
          timeout: 3s
          scheme: http
        servers:
          - url: http://5.78.140.118:4000
```

### PM2 Health Monitoring

```bash
# PM2 health command used in scripts
pm2 show <service-name> | grep -E "status|restarts|uptime|cpu|memory"
pm2 jlist | jq '.[] | select(.name=="<service-name>") | {status, restarts, cpu, memory}'
```

---

## Backup-Before-Deploy Policy

### Policy Statement

**Rule**: No deployment to production or staging shall proceed without a verified backup of the current state.

### What Gets Backed Up

| Target               | Method                          | Retention     | Verification       |
|---------------------|---------------------------------|---------------|--------------------|
| Application configs | `tar czf` of config directory   | 30 days       | sha256 checksum    |
| PM2 state           | `pm2 save` + copy dump.pm2      | 30 days       | pm2 resurrect test |
| Docker volumes      | `docker run --rm -v` tar        | 30 days       | tar tf             |
| .env files          | Encrypted copy (gpg)            | 90 days       | gpg --decrypt test |
| Nginx/Traefik conf  | `tar czf` of /etc/nginx, /etc/traefik | 30 days  | config test (nginx -t) |
| Database (if schema change) | pg_dump of affected tables | 90 days | pg_restore dry-run |

### Backup Procedure (Automated)

```bash
# Executed by deploy-service.sh before any deployment
backup_dir="/opt/wheeler/backups/$(date +%Y%m%d_%H%M%S)_${SERVICE_NAME}_predeploy"
mkdir -p "$backup_dir"

# 1. Backup application configs
tar czf "$backup_dir/configs.tar.gz" -C /opt/wheeler/$SERVICE_NAME configs/

# 2. Backup PM2 state (if PM2 service)
pm2 save
cp ~/.pm2/dump.pm2 "$backup_dir/pm2_dump.pm2"

# 3. Backup .env files (encrypted)
gpg --encrypt --recipient ops@wheeler.dev \
    /opt/wheeler/$SERVICE_NAME/.env \
    -o "$backup_dir/env.gpg"

# 4. Calculate checksums
sha256sum "$backup_dir"/* > "$backup_dir/checksums.sha256"

# 5. Log backup
echo "Backup completed: $backup_dir" >> /var/log/wheeler/deploy.log
```

---

## Traffic Flow During Deployment

### Normal Operation

```
Client --> Cloudflare --> Traefik (Edge) --> [Route based on Host/Path]
                                              |
                    +-------------------------+------------------------+
                    |                         |                        |
              Frontend Apps             API Backend               Static Assets
              (Edge PM2)          (AIOPS via WireGuard)         (Edge Nginx)
```

### During Frontend Deployment (PM2 on Edge)

```
1. New code deployed to release directory (no traffic impact)
2. pm2 reload starts new instance while old still serves
3. Traefik continues routing to ALL instances (old + new)
4. Old instances drain and exit
5. All instances now running new code
6. Trafik health checks confirm all instances healthy
```

### During API Deployment (PM2 on AIOPS)

```
1. New code deployed to release directory
2. pm2 reload performs rolling update
3. During reload:
   - Edge Traefik routes to healthy instances only (via health checks)
   - Failing instances are automatically removed from load balancer
   - At least 50% capacity maintained throughout
4. All instances updated, Traefik confirms routing
```

### During Docker Service Deployment (Edge or AIOPS)

```
1. New container started (blue) alongside old container (green)
2. New container verified via internal health check
3. Traefik/Nginx config updated to point to new container
4. Reload proxy gracefully (config test first)
5. Traffic flows to new container
6. Old container drained (30s grace period)
7. Old container stopped, image kept for rollback
```

---

## Service Dependency Ordering

### Startup Order (Cold Start / Full Cluster Recovery)

```
PHASE 0: INFRASTRUCTURE (T=0)
  1. COREDB: PostgreSQL
  2. COREDB: Redis
  3. COREDB: MinIO
  4. COREDB: Qdrant (after MinIO)

PHASE 1: DATA SERVICES (T+30s)
  5. COREDB: Prometheus
  6. COREDB: Loki
  7. COREDB: Tempo
  8. COREDB: AlertManager
  9. COREDB: Grafana

PHASE 2: AI/AIOPS CORE (T+60s, wait for all Phase 0 healthy)
  10. AIOPS: LiteLLM Proxy
  11. AIOPS: Model Cache
  12. AIOPS: Orchestrator

PHASE 3: API LAYER (T+90s, wait for all Phase 2 healthy)
  13. AIOPS: Wheeler API
  14. AIOPS: Revenue API
  15. AIOPS: Admin API
  16. AIOPS: Webhook Gateway
  17. AIOPS: GraphQL Gateway

PHASE 4: AI WORKERS (T+120s, wait for all Phase 3 healthy)
  18. AIOPS: OpenClaw Engine
  19. AIOPS: ML Workers
  20. AIOPS: Inference API

PHASE 5: OPS SERVICES (T+150s, wait for all Phase 4 healthy)
  21. AIOPS: Autoheal Engine
  22. AIOPS: Alert Engine
  23. AIOPS: Cost Monitor
  24. AIOPS: Eco Health Engine

PHASE 6: UTILITY SERVICES (T+180s)
  25. AIOPS: ChangeDetection (Docker)
  26. AIOPS: HealthChecks (Docker)

PHASE 7: EDGE / FRONTEND (T+210s, wait for all API services healthy)
  27. EDGE: Nginx
  28. EDGE: Wheeler Hub
  29. EDGE: Ops Dashboard
  30. EDGE: Admin Panel
  31. EDGE: Client Portal
  32. EDGE: Status Page

PHASE 8: EDGE ROUTING (T+240s, last)
  33. EDGE: Traefik (start accepting public traffic)
```

### Deployment Order (Single Service Update)

When deploying a single service update, deploy in this dependency order to minimize risk:

```
Leaf services first (no downstream dependents):
  status-page, client-portal, change-detection, healthchecks

Worker services (async consumers):
  ml-workers, cost-monitor, eco-health-eng

Mid-tier services:
  alert-engine, autoheal-engine, inference-api

API services (upstream of many):
  webhook-gateway, graphql-gateway, admin-api, revenue-api

Core API (last, most dependencies):
  wheeler-api, openclaw-engine, orchestrator

Never deploy these without a change window:
  postgresql, redis, minio, traefik (unless config-only)
```

---

## CI/CD Pipeline Integration

### Pipeline Stages

```
TRIGGER: Push to main / PR merge / Manual trigger
         |
         v
[1] LINT & TEST
    - ESLint, Black, ShellCheck, YAML lint
    - Unit tests, integration tests
    - Security scan (Trivy, npm audit, pip audit)
         |
         v
[2] BUILD
    - Docker: docker build + push to registry
    - PM2: npm pack / create release tarball
    - Tag with git SHA + timestamp
         |
         v
[3] PREFLIGHT (per environment)
    - ./deployment-engine/preflight-check.sh <service> <env>
    - Config validation, deps check, disk space
         |
         v
[4] BACKUP
    - Automated backup of current state
    - Verification of backup integrity
         |
         v
[5] DEPLOY (staging first, then production)
    - ./deployment-engine/deploy-service.sh <service> <env> <version>
    - Rolling deploy with health checks
         |
         v
[6] VERIFY
    - ./deployment-engine/verify-deployment.sh <service> <env>
    - HTTP health, PM2/Docker status, logs, resources
         |
    Failure?  Yes --> [ROLLBACK]
         |            ./deployment-engine/rollback-deployment.sh
         |            Alert on-call
         v
[7] SMOKE TEST
    - ./scripts/smoke-test-all.sh --service=<service>
    - Key user journeys
         |
         v
[8] MONITOR (15 min)
    - Watch error rates, latency, resource usage
    - Auto-rollback if anomaly detected
         |
         v
[9] COMPLETE
    - Log deploy event
    - Update status page
    - Notify team (Slack/Discord)
```

---

## Emergency Procedures

### Emergency Rollback Command

```bash
# Full node rollback (AIOPS)
ssh aiops-node "cd /opt/wheeler && ./deployment-engine/rollback-deployment.sh --all --emergency production"

# Full node rollback (Edge)
ssh edge-node "cd /opt/wheeler && ./deployment-engine/rollback-deployment.sh --all --emergency production"
```

### Emergency Contacts

| Role               | Method         | Escalation (15 min no response)  |
|-------------------|----------------|----------------------------------|
| Release Engineer  | PagerDuty       | Platform Lead                    |
| DB Admin          | PagerDuty       | CTO                              |
| Security Lead     | PagerDuty       | CISO                             |
| On-Call SRE       | PagerDuty       | SRE Manager                      |

---

## Appendix A: Directory Structure

```
/opt/wheeler/
├── deployment-engine/           # All deployment scripts
│   ├── common.sh                # Shared utilities
│   ├── deploy-service.sh        # Generic deploy orchestrator
│   ├── deploy-docker-service.sh # Docker-specific deploy
│   ├── deploy-pm2-service.sh    # PM2-specific deploy
│   ├── verify-deployment.sh     # Health verification
│   ├── rollback-deployment.sh   # Rollback automation
│   ├── preflight-check.sh       # Pre-deploy validation
│   └── post-deploy-healthcheck.sh # Post-deploy monitoring
├── backups/                     # Pre-deploy backups
│   └── YYYYMMDD_HHMMSS_<service>_predeploy/
├── configs/                     # Shared config templates
├── docs/                        # Documentation
│   ├── DEPLOYMENT_ARCHITECTURE.md
│   └── ENV_STANDARDIZATION.md
├── infrastructure/              # IaC (Ansible, Terraform)
├── scripts/                     # Operational scripts
├── templates/                   # Docker, PM2, systemd templates
│   ├── docker/
│   └── pm2/
├── wheeler-autonomous-ops/      # AIOps service code
└── wheeler-intelligence-platform/ # Intelligence platform code
```

## Appendix B: Key URLs and Ports

### Public URLs (via Traefik on Edge)

| Service          | URL                                      |
|-----------------|------------------------------------------|
| Wheeler Hub     | https://hub.wheeler.dev                  |
| Ops Dashboard   | https://ops.wheeler.dev                  |
| Admin Panel     | https://admin.wheeler.dev                |
| Client Portal   | https://portal.wheeler.dev               |
| Status Page     | https://status.wheeler.dev               |
| Wheeler API     | https://api.wheeler.dev                  |
| Revenue API     | https://revenue.wheeler.dev              |
| Webhook Gateway | https://webhooks.wheeler.dev             |

### Internal Ports (AIOPS + COREDB)

| Service          | Port | Node     |
|-----------------|------|----------|
| Wheeler API     | 4000 | AIOPS    |
| Revenue API     | 4001 | AIOPS    |
| LiteLLM Proxy   | 5000 | AIOPS    |
| PostgreSQL      | 5432 | COREDB   |
| Redis           | 6379 | COREDB   |
| MinIO API       | 9000 | COREDB   |
| Qdrant          | 6333 | COREDB   |
