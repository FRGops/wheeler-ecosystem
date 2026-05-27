# Wheeler Ecosystem Architecture
**Audit Date:** 2026-05-27 | **Overall Score:** 87/100
**Source data:** `/root/wheeler-ecosystem-audit/2026-05-27-0444/`

A living document describing the physical and logical architecture of the Wheeler AIOps ecosystem. Every claim is backed by audit evidence. Every section includes verification commands.

---

## 1. Server Role Summary

| Server | Provider | Tailscale IP | Public IP | Role | OS | Specs |
|--------|----------|-------------|-----------|------|----|-------|
| wheeler-aiops-01 | Hetzner CPX51 | 100.121.230.28 | 2a01:4ff:1f0:7add::1 | AIOps/build/automation/control plane | Ubuntu 24.04 | 16C/30G/338G |
| srv1476866 | Hostinger VPS | 100.98.163.17 | 2a02:4780:5e:44c2::1 | Public production/revenue apps | Ubuntu 24.04 | 8C/31G/387G |
| wheeler-core-db-01 | Hetzner (CoreDB) | 100.118.166.117 | 2a01:4ff:1f0:8839::1 | Database/storage/memory layer | Ubuntu 26.04 | 16C/30G/338G |
| wheelers-macbook-pro | MacBook Pro | 100.83.80.6 | -- | CEO/dev/operator command center | macOS | -- |

**Verification:**
```bash
tailscale status  # shows all 4 nodes and connectivity state
```

**Findings:** 3/4 servers fully online. Mac is pingable (33ms) but shows "-" status in Tailscale -- not fully connected. SSH to Hostinger and Mac both fail with "Permission denied (publickey)".

---

## 2. Network Topology

```
                            Internet
                               |
                        [Cloudflare]
                        /            \
             [fundsrecoverygroup.com]  [predictionradar.app]  (DNS)
                       |                         |
                       |                   [Cloudflare Tunnel]
                       v                         |
               +-------------+                   |
               |  Hostinger  |<------------------+
               |  srv1476866 |
               |  :80/:443   |
               +------+------+
                      |  (179ms, direct)
               +------+------+          +------------------+
               |   Hetzner   |==========|    CoreDB        |
               | aiops-01    |   (1ms)  | wheeler-core-db  |
               | 100.121.230 |          | 100.118.166      |
               +------+------+          +------------------+
                      |   (33ms)
               +------+------+
               |  MacBook    |
               |  100.83.80  |  (partially offline)
               +-------------+

    Legend:  === Tailscale mesh   --- Internet/Cloudflare   ... Degraded
```

**Verification:**
```bash
tailscale ping 100.98.163.17     # Hetzner -> Hostinger: 179ms
tailscale ping 100.118.166.117   # Hetzner -> CoreDB: 1ms
tailscale ping 100.83.80.6       # Hetzner -> Mac: 33ms
```

---

## 3. Service-to-Server Mapping

### Hetzner (47 Docker containers + 62 PM2 agents)
**Public ports:** 80 (Nginx), 443 (Nginx). Everything else on 127.0.0.1 or Tailscale.

| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| Nginx | 80/443 | Public | Reverse proxy, SSL termination |
| OpenWebUI | 3000 | 127.0.0.1 | LLM chat UI |
| Uptime Kuma | 3001 | Tailscale | Monitoring dashboard |
| Grafana | 3002 | Tailscale | Metrics dashboards |
| Uptime Kuma backup | 3001 | -- | HA monitoring |
| DocuSeal | 3010 | 127.0.0.1 | Document signing |
| Loki | 3100 | 127.0.0.1 | Log aggregation |
| Healthchecks | 3130 | Tailscale | Cron job monitoring |
| LiteLLM | 4049 | 127.0.0.1 | LLM proxy/router |
| ChangeDetection | 5000 | Tailscale | Website change monitoring |
| Temporal Server | 7233 | 127.0.0.1 | Workflow engine |
| Neo4j (ecosystem-graph) | 7474/7687 | 127.0.0.1 | Knowledge graph |
| Langflow | 7860 | 127.0.0.1 | Visual LLM builder |
| RavynAI app | 8007 | Tailscale | RavynAI backend |
| Webhook Relay | 8085 | 127.0.0.1 | Webhook forwarding |
| Superset | 8088 | Tailscale | Data exploration |
| Temporal UI | 8089 | Tailscale | Workflow UI |
| War Room | 8091 | 127.0.0.1 | Incident response |
| Prediction Radar web | 8098 | Tailscale | Prediction radar frontend |
| ClickHouse | 8123 | Tailscale | Analytics database |
| Executive Dashboard | 8180 | 127.0.0.1 | Business dashboard |
| Embedding Service | 8191 | 127.0.0.1 | Vector embeddings |
| Prometheus | 9090 | Tailscale | Metrics collection |
| Alertmanager | 9093 | 127.0.0.1 | Alert routing |
| Cadvisor | 9099 | 127.0.0.1 | Container metrics |
| Node Exporter | 9100 | 127.0.0.1 | Host metrics |
| Netdata | 19999 | Tailscale | Real-time monitoring |
| PM2 agent services | various | 127.0.0.1 | 62 agent processes |
| Claude Code agents | -- | -- | 153 agent profiles |

**Verification:**
```bash
docker ps | wc -l                    # should show 47
pm2 jlist | jq '. | length'          # should show 62+
ls .claude/agents/*.md | wc -l       # should show 153
sudo ufw status numbered             # verify public exposure
ss -tlnp | grep -E '0.0.0.0:|:::|100\.'  # find public listeners
```

### Hostinger (7 Docker containers + Nginx + native services)
**Public ports:** 80 (Nginx), 443 (Nginx). SSH on Tailscale CGNAT only.

| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| Nginx | 80/443 | Public | Reverse proxy, 30+ sites |
| Nginx internal | 8765 | 127.0.0.1 | Internal proxy (broken, 502) |
| Cadvisor | 9099 | **0.0.0.0** | Container metrics (exposed!) |
| Temporal UI | 8080 | 127.0.0.1 | Workflow UI |
| Pushgateway | 9092 | 127.0.0.1 | Metrics push gateway |
| OpenClaw Gateway | 18789 | 127.0.0.1 | API gateway |
| OpenFang | 4200 | 127.0.0.1 | Application server |
| Cloudflared | 20241 | 127.0.0.1 | Cloudflare tunnel |
| Netdata | 19999 | 127.0.0.1 | Real-time monitoring |
| Shared PostgreSQL | 5432 | 127.0.0.1 | App database |
| Shared PostgreSQL (socat) | 5433 | Tailscale | Cross-server DB access |
| Redis | 6379 | 127.0.0.1 | Cache |
| PgBouncer | 6432 | 127.0.0.1 | Connection pooling |
| Python app | 8002 | **0.0.0.0** | Publicly exposed! |
| Obscura | 9222 | 127.0.0.1 | Headless browser |

**Verification:**
```bash
docker ps | wc -l                    # should show 7
ls /etc/nginx/sites-enabled/ | wc -l # should show 37
curl -sI https://fundsrecoverygroup.com | head -1  # HTTP 200
curl -sI https://predictionradar.app | head -1     # HTTP 502 (broken)
ss -tlnp | grep 0.0.0.0             # find public exposure
```

### CoreDB (21 Docker containers)
**Public:** None. All services on 127.0.0.1 or Tailscale IP.

| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| PostgreSQL | 5432 | Tailscale IP | Primary database |
| Redis | 6379 | Tailscale IP | Cache/queue |
| Qdrant | 6333-6334 | Tailscale IP | Vector database |
| MinIO | 9000-9001 | 127.0.0.1 | S3-compatible storage |
| Temporal Server | 7233 | 127.0.0.1 | Workflow engine |
| Temporal UI | 8080 | 127.0.0.1 | Workflow dashboard |
| Infisical | 8089 | 127.0.0.1 | Secrets management |
| Infisical Nginx | 8443 | 127.0.0.1 | Infisical reverse proxy |
| UseSend | 3007 | 127.0.0.1 | Secure file sharing |
| Loki | 3100 | 127.0.0.1 | Log aggregation |
| Prometheus | -- | internal | Metrics (no public port) |
| Grafana | -- | internal | Dashboards (no public port) |
| Uptime Kuma | 3001 | 127.0.0.1 | Monitoring |
| Node Exporter | 9100 | host port | Metrics exporter |

**Note:** PostgreSQL, Redis, and Qdrant bind to the Tailscale IP `100.118.166.117`, NOT 127.0.0.1. This means they are accessible over the Tailscale mesh -- which is intentional for cross-server DB access. They are **not** on 0.0.0.0 so they have no public exposure.

**Verification:**
```bash
docker ps | wc -l                    # should show 21
ss -tlnp | grep 100.118.166          # verify DB services on Tailscale only
sudo ufw status numbered             # verify no public ports
```

---

## 4. Data Flow Diagrams

### 4a. FRG User Request Flow (fundsrecoverygroup.com)

```
User Browser
     |
     | HTTPS
     v
Cloudflare (CDN + SSL)
     |
     | Cloudflare proxied (not tunnel)
     v
Hostinger Nginx (:80/:443)
     |
     | proxy_pass to backend
     v
FRG application (native, not Docker)
     |
     | PostgreSQL queries
     v
Shared PostgreSQL (127.0.0.1:5432)
```

**Verification:**
```bash
curl -sI https://fundsrecoverygroup.com  # HTTP 200
ssh root@100.118.166.117 "tailscale status"  # verify mesh is up
```

### 4b. Agent Workflow Request (Claude Code -> DeepSeek)

```
Developer / Cron / Hook
     |
     | starts Claude Code session
     v
Claude Code (CLI)
     |
     | ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic/
     | ANTHROPIC_MODEL=deepseek-v4-pro
     | ANTHROPIC_AUTH_TOKEN=sk-4ac726fce256...
     v
DeepSeek V4 Pro API (api.deepseek.com)
     |
     | response returned
     v
Claude Code processes result
     |
     | optional: PM2 agent services
     v
Hetzner PM2 Fleet (62 online services)
     |
     | queries for context
     v
Neo4j / ClickHouse / Qdrant / PostgreSQL (via Tailscale to CoreDB)
```

**Verification:**
```bash
echo $ANTHROPIC_BASE_URL              # should point to deepseek
echo $ANTHROPIC_MODEL                 # should be deepseek-v4-pro
pm2 jlist | jq '.[].pm2_env.status' | sort | uniq -c  # all "online"
```

### 4c. Nightly Backup Flow

```
CoreDB Cron (0 3 * * *)
     |
     | /opt/backups/backup-postgres.sh
     v
PostgreSQL dump -> local file
     |
     | docker volume
     v
MinIO (wheeler-minio on 127.0.0.1:9000)
     |
     S3-compatible object storage
```

**Verification:**
```bash
crontab -l | grep backup              # verify cron entry
ls /var/log/postgres-backup.log 2>/dev/null && tail -5 /var/log/postgres-backup.log
```

---

## 5. Domain Routing Table

| Domain | DNS | Proxy | Backend Server | Status |
|--------|-----|-------|---------------|--------|
| fundsrecoverygroup.com | Cloudflare | Cloudflare proxied | Hostinger Nginx | HTTP 200 |
| www.fundsrecoverygroup.com | Cloudflare | Cloudflare proxied | Hostinger Nginx | HTTP 200 (301? -> apex) |
| predictionradar.app | Cloudflare | Cloudflare proxied -> tunnel | Hostinger Nginx -> missing upstream | **HTTP 502** |
| www.predictionradar.app | Cloudflare | 301 redirect | -> predictionradar.app | redirect OK |
| horizonfederalservices.com | External | Caddy | Not our infra | external |
| ravyn.ai | Squarespace | Squarespace | Squarespace | external |
| *.frgops.io | Cloudflare | DNS only? | Hostinger Nginx | varies |
| frgcrm.* | Cloudflare | -- | Hostinger Nginx | HTTP 307 |
| surplusai.io / ai | Cloudflare | -- | Hostinger Nginx | HTTP 307 |
| insforge | Cloudflare | -- | Hostinger Nginx | HTTP 307 |

**Key Finding:** predictionradar.app is a revenue application returning 502. Nginx terminates SSL but the `proxy_pass` upstream is missing. The backend (prediction-radar containers) lives on Hetzner, not Hostinger. Fix: add proxy_pass to `http://100.121.230.28:8098;` in Hostinger Nginx config for prediction-radar.

**Verification:**
```bash
curl -sI https://fundsrecoverygroup.com | grep -i "HTTP/"
curl -sI https://predictionradar.app | grep -i "HTTP/"
ls /etc/nginx/sites-enabled/ | grep prediction
```

---

## 6. Critical Service Health Endpoints

| Service | Endpoint | Expected | Server |
|---------|----------|----------|--------|
| Nginx (Hostinger) | `curl -sI https://fundsrecoverygroup.com` | 200 | Hostinger |
| Nginx (Hetzner) | `curl -sI http://localhost:80` | 200 | Hetzner |
| Docker Health | `docker ps --filter health=healthy` | all healthy | All |
| PM2 | `pm2 jlist \| jq '.[].pm2_env.status'` | all "online" | Hetzner |
| Prometheus | `curl -s http://127.0.0.1:9090/api/v1/targets \| jq '.data.activeTargets\|length'` | 12 | Hetzner |
| LiteLLM | `curl -s http://127.0.0.1:4049/health` | 200 (needs auth) | Hetzner |
| OpenClaw Gateway | `curl -s http://127.0.0.1:18789/api` | `{"ok":true,"status":"live"}` | Hostinger |
| Temporal | `curl -s http://127.0.0.1:7233` | responds | Both |
| Neo4j | `curl -s http://127.0.0.1:7474` | responds | Hetzner |
| PostgreSQL | `pg_isready -h 127.0.0.1 -p 5432` | accepting | CoreDB |
| Qdrant | `curl -s http://100.118.166.117:6333` | responds | CoreDB |
| Infisical | `curl -s http://127.0.0.1:8089/api/status` | healthy | CoreDB |

**Monitoring Stack:**
- Prometheus: 12/12 targets up, 0 alerts firing
- Loki: log aggregation across all 3 servers
- Grafana: dashboards on :3002 (Hetzner) and internal (CoreDB)
- Uptime Kuma: :3001 on both Hetzner and CoreDB
- Alertmanager: running on :9093, needs alert routing configuration
- Netdata: real-time metrics on :19999 (all servers)
- War Room: incident response at :8091 (Hetzner)

---

## 7. Key Architectural Decisions (and Why)

### 7.1. Three-Tier Architecture
**Decision:** Separate AIOps (Hetzner), Production (Hostinger), and Storage (CoreDB).
**Why:** Security isolation. If production (Hostinger) is compromised, the AI agent fleet and database layer remain isolated on Tailscale-only networks. Hostinger has only 7 Docker containers vs Hetzner's 47 -- the attack surface is intentionally minimized.

### 7.2. Tailscale as the Backplane
**Decision:** All cross-server traffic goes through Tailscale mesh.
**Why:** No public ports needed for inter-service communication. Hetzner->Hostinger is direct 179ms, Hetzner->CoreDB is 1ms (same datacenter). UFW rules lock everything to `tailscale0` interface -- even if Docker publishes on 0.0.0.0, the firewall blocks non-Tailscale traffic.

### 7.3. DeepSeek V4 as Primary Model
**Decision:** All Claude Code sessions route through `api.deepseek.com/anthropic` with model `deepseek-v4-pro`.
**Why:** Cost. DeepSeek V4 provides comparable capabilities to Claude Opus at a fraction of the cost. LiteLLM is deployed as a proxy fallback on :4049 but is currently unauthenticated (LITELLM_MASTER_KEY missing).

### 7.4. PM2 for Agent Services
**Decision:** 62 agent services run as PM2 processes on Hetzner, not in Docker.
**Why:** PM2 provides auto-restart, log management, and process clustering without the overhead of containerizing 60+ single-purpose agents. Docker is reserved for infrastructure services that need network isolation.

### 7.5. CoreDB Doubles as Storage + Compute
**Decision:** Temporal, MinIO, Gafana, Prometheus, and Uptime Kuma run on the same server as PostgreSQL/Redis/Qdrant.
**Why:** Hetzner Hetzner provides 30GB RAM at the same cost as running a separate server -- consolidating monitoring and workflow tooling on CoreDB uses 3.2GB/30GB (11%) leaving headroom.

### 7.6. Cloudflare in Front of Hostinger
**Decision:** Cloudflare proxies all production traffic to Hostinger.
**Why:** DDoS protection, SSL termination, caching, and hiding the origin IP. predictionradar.app uses Cloudflare Tunnel (cloudflared) for additional security. FRG uses direct Cloudflare proxying.

### 7.7. One Container with 0.0.0.0 Exposure is Too Many
**Finding:** Hostinger port 8002 (Python app) and 9099 (cadvisor) are on 0.0.0.0.
**Assessment:** Medium severity. Cadvisor exposes container metrics. Python app on 8002 depends on what the app does. Both should be bound to 127.0.0.1 like the rest of the deployment.

### 7.8. Security Posture Summary
- **Hetzner:** 2 public ports (80/443), SSH rate-limited but on 0.0.0.0 (should be Tailscale-only)
- **Hostinger:** 2 public ports (80/443), SSH locked to CGNAT (good), 2 exposed services (needs fix)
- **CoreDB:** 0 public ports, SSH on 0.0.0.0 (needs Tailscale-only), fail2ban active
- **Mac:** Partially offline, SSH key mismatch

---

## Quick-Reference: Top Issues to Fix

| Priority | Issue | Impact | Fix Command / Action |
|----------|-------|--------|---------------------|
| P0 | predictionradar.app 502 | Revenue lost | Add to Hostinger Nginx: `proxy_pass http://100.121.230.28:8098;` |
| P1 | Mac offline on Tailscale | No command center | `sudo tailscale up` on Mac |
| P1 | LITELLM_MASTER_KEY missing | No admin access | Generate via `openssl rand -base64 32`, add to LiteLLM config |
| P2 | Port 8002 on 0.0.0.0 | Python app exposed | Change bind to 127.0.0.1 |
| P2 | Cadvisor on 0.0.0.0:9099 | Metrics exposed | Change bind to 127.0.0.1 |
| P2 | changedetection 19 restarts | Instability | `docker logs aiops-changedetection --tail 50` and investigate |
| P3 | CoreDB SSH on 0.0.0.0 | Unnecessary surface | Add UFW: `sudo ufw deny 22/tcp; sudo ufw allow in on tailscale0 to any port 22` |
| P3 | Hetzner SSH on 0.0.0.0 | Unnecessary surface | Same pattern as CoreDB fix |

---

**Related documentation:**
- `/root/wheeler-ecosystem-audit/2026-05-27-0444/00-EXECUTIVE_SUMMARY.md` -- Full executive summary with scores
- `/root/wheeler-ecosystem-audit/2026-05-27-0444/17-100-READINESS_SCORECARD.md` -- 30-category scorecard
- `/root/CLAUDE.md` -- Wheeler Brain OS project instructions
- `/root/.ai/INDEX.md` -- Full ecosystem index
