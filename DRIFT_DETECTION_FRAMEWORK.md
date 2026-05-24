# Wheeler Autonomous AI Ops — Drift Detection Framework
**Version:** 1.0
**Last Updated:** 2026-05-24
**Governance Engine Integration:** GOVERNANCE_ENGINE.md Section 4.1

---

## 1. Drift Detection Overview

### 1.1 What Is Infrastructure Drift

Infrastructure drift is the divergence between the **declared state** (configuration files, policies, and documentation) and the **actual state** (what is running on the server). In the Wheeler ecosystem, drift occurs when:

- Docker containers run with different configurations than docker-compose defines
- PM2 processes have different environment variables than ecosystem.config.js specifies
- nginx configs are modified without updating version control
- UFW rules are added or removed outside the approved rule set
- Port bindings change from the intended 127.0.0.1 to 0.0.0.0
- Secrets end up in git, in PM2 jlist, or world-readable
- Resources exceed expected baselines without clear cause

### 1.2 Why Drift Matters

Drift is the primary vector for three of the five Critical gaps identified in `/root/ENFORCEMENT_GAP_ANALYSIS.md`:

1. **Security Drift** (Gap 3: Docker UFW Bypass, Gap 4: UFW Rule Contradictions) — containers bind to 0.0.0.0 despite UFW DENY rules, creating exposure
2. **Configuration Drift** (Gap 7: Service Directory Drift) — 7 of 8 service directories in ecosystem.config.js do not exist on disk; processes run from undocumented paths
3. **Secret Drift** (Gap 5: Secret Management) — secrets leak into PM2 jlist, .env files, and Docker env vars despite policies forbidding it

All three False Green categories involving network exposure (FG-2: gateway bypass, FG-5: UFW bypass, FG-12: IPv6 wildcard) are drift problems — the system claims one state while reality diverged.

### 1.3 Drift Detection Philosophy

The framework follows the Governance Engine principle from `/root/WHEELER_BRAIN_OS/architecture/GOVERNANCE_ENGINE.md`:

```
Every policy is either:
  ✅ COMPLIANT — no action needed
  ⚠ EXEMPT — documented, justified, reviewed periodically
  ❌ VIOLATING — queued for remediation
```

Drift detection operates on a continuous **Detect → Report → Remediate → Verify** loop. No drift is allowed to persist unreported. No remediation is applied without verification.

### 1.4 Domain Coverage

| Domain | Baseline Source | Detection Method | Auto-Remediation |
|--------|----------------|-----------------|-----------------|
| Configuration Drift | docker-compose, ecosystem.config.js, nginx configs | Hash comparison, diff | Patch approved only |
| Port/Bind Drift | ss -tlnp baseline | Socket scan, IP comparison | Yes (rebind to 127.0.0.1) |
| Exposure Drift | UFW rules + port list | Cross-reference UFW vs actual binds | Yes (remove rules, rebind) |
| Service Drift | Authorized container list | Container image/PID validation | Manual only |
| Secret Drift | Known-good secret locations | Pattern scanning, jlist inspect | Yes (env -i delete+start) |
| Resource Drift | 7-day resource baseline | Prometheus metric comparison | Yes (update limits) |

---

## 2. Configuration Drift

Configuration drift detection ensures that running configurations match their declared definitions across Docker, PM2, nginx, and UFW.

### 2.1 Docker Configuration Drift

Detection script: `/opt/wheeler-ecosystem/scripts/config-drift-detector.sh`

**What is checked:**

```
For each running Docker container:
  1. Container name matches a known docker-compose service
  2. Image tag matches the pinned version in docker-compose
  3. Port mappings match 127.0.0.1 bind policy
  4. Resource limits (memory, CPU) match docker-compose declarations
  5. Environment variables match .env file references
  6. Container is not using :latest tag
```

**Detection mechanism:**

```bash
# Baseline: docker-compose.yml parsed to expected container states
# Current: docker inspect on all running containers
# Comparison: JSON diff between baseline and runtime state

CONFIG_BASELINE="/var/log/wheeler/config-baseline.json"
# Created with: config-drift-detector.sh --baseline
# Compared with: config-drift-detector.sh --check
```

**Baseline structure:**

```json
{
  "timestamp": "2026-05-24T00:00:00Z",
  "docker_containers": [
    "aiops-prometheus|prom/prometheus:v2.55.1",
    "aiops-grafana|grafana/grafana:11.5.1",
    "aiops-loki|grafana/loki:3.6.3",
    "aiops-alertmanager|prom/alertmanager:v0.28.1",
    "docuseal|docuseal/docuseal:3.0.0",
    "open-webui|ghcr.io/open-webui/open-webui:main",
    "aiops-healthchecks|lscr.io/linuxserver/healthchecks:v4.2-ls344",
    "aiops-changedetection|ghcr.io/dgtlmoon/changedetection.io:0.55.3",
    "uptime-kuma|louislam/uptime-kuma:1",
    "netdata|netdata/netdata",
    "aiops-clickhouse|clickhouse/clickhouse-server:24.3",
    "aiops-superset|apache/superset:4.1.1",
    "ecosystem-graph|neo4j:5.26-community",
    "temporal-server|temporalio/auto-setup:1.29.3",
    "aiops-ravynai-postgres|postgis/postgis:16-3.4",
    "frgops-standby|postgres:16-alpine",
    "langflow|langflowai/langflow:1.0.19"
  ],
  "ufw_rules": "59"
}
```

**Drift detection output:**

```
Config Drift Report:
  Added containers:   [aiops-unauthorized-nginx]
  Removed containers: [aiops-pushgateway]
  Added PM2 procs:    [unknown-agent-svc]
  Removed PM2 procs:  [backup-verification]
  UFW rules changed:  true
  Total drift items:  5
```

### 2.2 PM2 Configuration Drift

**What is checked:**

```
For each PM2 process:
  1. process name matches ecosystem.config.js definition
  2. script path exists on disk (fixes Gap 7: service directory drift)
  3. environment variables match config (no extra/missing variables)
  4. no secrets leaked into PM2 jlist env
  5. restart count within threshold (< 3 in 5 minutes)
```

**PM2 env-var consistency check:**

```bash
# All agent processes must use pm2-env-wrapper.sh for secret loading
pm2 prettylist | grep -c "pm2-env-wrapper.sh"
# Expected: all agent processes use wrapper
# If missing: env drift detected — secrets may be hardcoded in config
```

**Service path validation (fixing Gap 7):**

```bash
# Ecosystem config defines these paths:
# /opt/wheeler/services/litellm
# /opt/wheeler/apps/frgcrm/api
# /opt/wheeler/services/surplusai-scraper-agent
# /opt/wheeler/services/prediction-radar
# /opt/wheeler/services/wheeler-brain-os
# /opt/wheeler/services/openclaw
# /opt/wheeler/services/voice-agent
# /opt/wheeler/services/browser-agent
#
# Actual runtime paths from pm2 jlist:
# /opt/apps/litellm/
# /opt/apps/frgcrm/api/
# /opt/apps/surplusai-scraper-agent-svc/
# /opt/apps/prediction-radar-agent-svc/
# /opt/apps/wheeler-brain-os/
# /opt/openclaw-dashboard/
# /opt/apps/voice-agent-svc/
# /opt/apps/browser-agent/

# Drift: 7 of 8 paths differ from declared config
# Enforcement: update ecosystem.config.js OR symlink /opt/wheeler/services → /opt/apps
```

### 2.3 nginx Configuration Drift

**What is checked:**

```bash
# Site configs in /etc/nginx/sites-enabled/
ls /etc/nginx/sites-enabled/
# Expected: aiops-gateway only

# Check for auth_basic on all admin paths
grep -l "auth_basic" /etc/nginx/sites-enabled/*
# All admin paths must have auth_basic protection

# Check rate limiting
grep "limit_req" /etc/nginx/sites-enabled/*
# All external endpoints must have limit_req zones defined

# Check for uncommitted changes
cd /etc/nginx && git status --porcelain 2>/dev/null
# Expected: clean (all changes tracked)
```

**Rate limiting drift (policy from GOVERNANCE_ENGINE.md Section 2.2):**

If any nginx site config is missing `limit_req` on an external endpoint, it is flagged as drift. Current exemption: internal Tailscale-only endpoints may skip rate limiting.

### 2.4 UFW Configuration Drift

**What is checked:**

```bash
# Baseline: 59 rules as of 2026-05-24
ufw status numbered | wc -l
# Drift: > 5 rule count difference from baseline

# Check for contradictory rules (Gap 4 from ENFORCEMENT_GAP_ANALYSIS.md)
# Signs of contradiction:
#   - Same port with BOTH "on tailscale0" AND bare "Anywhere" ALLOW
#   - Port with ALLOW on tailscale0 AND DENY Anywhere (intended but redundant)
ufw status numbered | sort | uniq -c | grep -v "^[[:space:]]*1 "
```

**Known UFW rule contradictions (baselined but flagged):**

- Ports 5433, 8089, 8005 have both DENY and ALLOW on tailscale0 for the same port (intentional: deny from internet, allow from Tailscale, but listed as two separate rules)

**UFW drift auto-remediation:**

If a new bare "Anywhere" ALLOW rule appears for any port that should be Tailscale-only, the lockdown watchdog flags it for removal.

---

## 3. Port/Bind Drift

Port/bind drift detection ensures every service listens only on its intended address. This is the primary defense against the Docker UFW bypass vulnerability (Gap 3).

### 3.1 Detection Mechanism

The lockdown watchdog (`/opt/wheeler-ecosystem/enforcement/wheeler-lockdown-watchdog.sh`) runs every 5 minutes via cron:

```
*/5 * * * * bash /opt/wheeler-ecosystem/enforcement/wheeler-lockdown-watchdog.sh >> /var/log/wheeler-watchdog.log 2>&1
```

**What it checks:**

```bash
# Scan all listening TCP ports
ss -tlnp | awk '$4 !~ /127.0.0.1|::1|100\.121\.230\.28/ && NR>1 {print}'
```

**Expected non-loopback listeners:**
- SSH: `0.0.0.0:22` (legitimate)
- Tailscale: `100.121.230.28:*` (mesh traffic)

**All other services must bind to 127.0.0.1** — this includes:
- ngixn gateway: `100.121.230.28:443` (legitimate, on Tailscale IP)
- usesend: `100.121.230.28:3007` (legitimate, on Tailscale IP)

### 3.2 Known-Good Port Bindings (Baseline)

This is the authoritative port map. Any deviation from these bindings constitutes drift:

| Port | Service | Container/Process | Expected Bind | Status |
|------|---------|------------------|---------------|--------|
| 22 | SSH | systemd | 0.0.0.0 | LEGITIMATE |
| 443 | nginx gateway | system nginx | 100.121.230.28 | LEGITIMATE |
| 3007 | usesend | usesend | 127.0.0.1 + 100.121.230.28 | LEGITIMATE |
| 5432 | PostgreSQL (internal) | frgops-standby | 127.0.0.1 | CORRECT |
| 5434 | RavynAI Postgres | aiops-ravynai-postgres | 127.0.0.1 | CORRECT |
| 5433 | Standby PostgreSQL | frgops-standby | 127.0.0.1 | CORRECT |
| 3001 | Uptime Kuma | uptime-kuma | 127.0.0.1 | CORRECT |
| 3002 | Grafana | aiops-grafana | 127.0.0.1 | CORRECT |
| 3010 | DocuSeal | docuseal | 127.0.0.1 | CORRECT |
| 3100 | Loki | aiops-loki | 127.0.0.1 | CORRECT |
| 3130 | Healthchecks | aiops-healthchecks | 127.0.0.1 | CORRECT |
| 4049 | LiteLLM | litellm (PM2) | 127.0.0.1 | CORRECT |
| 5000 | Changedetection | aiops-changedetection | 127.0.0.1 | CORRECT |
| 7233 | Temporal Server | temporal-server | 127.0.0.1 | CORRECT |
| 7474 | Neo4j (ecosystem-graph) | ecosystem-graph | 127.0.0.1 | CORRECT |
| 7687 | Neo4j Bolt | ecosystem-graph | 127.0.0.1 | CORRECT |
| 7860 | Langflow | langflow | 127.0.0.1 | CORRECT |
| 8003 | frgcrm-agent-svc | PM2 (node) | 127.0.0.1 | CORRECT |
| 8005 | ravyn-agent-svc | PM2 (node) | 127.0.0.1 | WAS [::]:8005 — FIXED |
| 8006 | horizon-agent-svc | PM2 (node) | 127.0.0.1 | CORRECT |
| 8007 | surplusai-agent-svc | PM2 (node) | 127.0.0.1 | CORRECT |
| 8008 | voice-agent-svc | PM2 (node) | 127.0.0.1 | CORRECT |
| 8009 | paperless-agent-svc | PM2 (node) | 127.0.0.1 | CORRECT |
| 8011 | prediction-radar-agent-svc | PM2 (node) | 127.0.0.1 | CORRECT |
| 8013 | insforge-agent-svc | PM2 (node) | 127.0.0.1 | CORRECT |
| 8020 | design-agent-svc | PM2 (node) | 127.0.0.1 | CORRECT |
| 8082 | frgcrm-api | PM2 (python) | 127.0.0.1 | CORRECT |
| 8085 | webhook-relay | aiops-webhook-relay | 127.0.0.1 | CORRECT |
| 8088 | Superset | aiops-superset | 127.0.0.1 | CORRECT |
| 8089 | Temporal UI | temporal-ui | 127.0.0.1 | CORRECT |
| 8090 | 1Panel | 1panel | 127.0.0.1 | CORRECT |
| 8091 | war-room-server | PM2 (python) | 127.0.0.1 | CORRECT |
| 8095 | voice-outreach-service | PM2 (python) | 127.0.0.1 | CORRECT |
| 8098 | pred-radar-web | prediction-radar-app-web | 127.0.0.1 | CORRECT |
| 8099 | command-center | PM2 (python) | 127.0.0.1 | CORRECT |
| 8100 | war-room | command-center (PM2) | 127.0.0.1 | CORRECT |
| 8103 | surplusai-portal-api | PM2 (uvicorn) | 127.0.0.1 | CORRECT |
| 8110 | openclaw-dashboard | PM2 (node) | 127.0.0.1 | CORRECT |
| 8123 | ClickHouse HTTP | aiops-clickhouse | 127.0.0.1 | CORRECT |
| 9090 | Prometheus | aiops-prometheus | 127.0.0.1 | CORRECT |
| 9091 | Hostinger Exporter | hostinger-health-exporter | 127.0.0.1 | CORRECT |
| 9092 | Pushgateway | aiops-pushgateway | 127.0.0.1 | CORRECT |
| 9093 | Alertmanager | aiops-alertmanager | 127.0.0.1 | CORRECT |
| 9100 | Node Exporter | system | 127.0.0.1 | CORRECT |
| 19999 | Netdata | netdata | 127.0.0.1 | CORRECT |
| 3000 | Open WebUI | open-webui | 127.0.0.1 | CORRECT |

### 3.3 Drift Detection Logic

```python
# Pseudo-code for port/bind drift detection
def detect_port_drift():
    known_good = load_baseline("port-baseline.json")
    current = scan_listening_sockets()  # ss -tlnp

    drift = []
    for port, info in current.items():
        if port not in known_good:
            drift.append(NEW_PORT(port, info))
        elif info.bind != known_good[port].bind:
            drift.append(BIND_CHANGED(port, known_good[port].bind, info.bind))

    for port in known_good:
        if port not in current:
            drift.append(PORT_MISSING(port, known_good[port].service))

    return drift
```

### 3.4 Auto-Remediation for Port/Bind Drift

When a previously-correct 127.0.0.1 bind changes to 0.0.0.0:

```bash
# 1. Identify which container/process changed
# 2. If Docker container: update docker-compose.yml, recreate
docker compose up -d <service_name>
# 3. If PM2 process: update source code bind address, restart
env -i HOME=/root PATH="..." PM2_HOME=/root/.pm2 pm2 delete <name>
env -i HOME=/root PATH="..." PM2_HOME=/root/.pm2 pm2 start <config> --only <name>
# 4. Verify
ss -tlnp | grep <port> | grep 127.0.0.1
```

---

## 4. Exposure Drift

Exposure drift is a subset of port/bind drift specifically focused on security boundaries — services that become publicly accessible when they should be Tailscale-only.

### 4.1 Exposure Detection

The exposure surface is computed at `/opt/wheeler-ecosystem/enforcement/wheeler-public-surface` and checked by the lockdown watchdog.

```bash
# Cross-reference UFW rules with actual port bindings
# Any port that is BOTH:
#   - Listening on 0.0.0.0 (or non-Tailscale address)
#   - NOT explicitly DENIED by UFW
# → EXPOSED — potential security gap

# Additionally:
# - Any port ALLOW Anywhere in UFW that should be tailscale0-only
# - Any container binding 0.0.0.0 that the gateway should proxy
```

### 4.2 Exposure Report Format

```
Wheeler Exposure Report — 2026-05-24
═══════════════════════════════════════
Public Surface:
  0.0.0.0:22        → SSH (LEGITIMATE)
  100.121.230.28:443 → nginx gateway (LEGITIMATE)
  100.121.230.28:3007 → usesend (LEGITIMATE)

Admin Panels Exposed to Tailscale (intended):
  127.0.0.1:8090    → 1Panel administration
  127.0.0.1:8088    → Superset analytics
  127.0.0.1:3002    → Grafana dashboards
  127.0.0.1:3001    → Uptime Kuma
  127.0.0.1:19999   → Netdata

Exposure Drift: NONE
UFW Rule Contradictions: 3 (known, baselined)
  - 5433: DENY Anywhere + ALLOW tailscale0 (intentional)
  - 8089: DENY Anywhere + ALLOW tailscale0 (intentional)
  - 8005: DENY Anywhere + ALLOW tailscale0 (intentional)
```

### 4.3 Admin Panel Exposure Policy

From `/root/.claude/skills/slay/SKILL.md` and the lockdown status at `/opt/wheeler-ecosystem/enforcement/wheeler-lockdown-status`:

All admin dashboards must be either:
1. Bound to 127.0.0.1 (accessible via Tailscale SSH tunnel only)
2. Behind nginx reverse proxy with basic auth and rate limiting

**Currently protected behind nginx basic auth:**
- 1Panel (127.0.0.1:8090)
- Superset (127.0.0.1:8088) — placeholder key flagged as FG-9
- Grafana (127.0.0.1:3002)
- Uptime Kuma (127.0.0.1:3001) — behind nginx

### 4.4 Exposure Drift Scoring

| Exposure Type | Severity | Auto-Remediation |
|--------------|----------|-----------------|
| Admin panel on 0.0.0.0 | CRITICAL | Rebind to 127.0.0.1, add nginx auth |
| Internal API on 0.0.0.0 | CRITICAL | Rebind to 127.0.0.1 |
| UFW "Anywhere ALLOW" for tailscale port | HIGH | Remove Anywhere rule |
| Container :latest with new port mapping | MEDIUM | Pin version, verify bind |
| UFW rule count changed > 5 | LOW | Review, accept or revert |

---

## 5. Service Drift

Service drift covers unauthorized, duplicate, and stale services across both Docker and PM2.

### 5.1 Unauthorized Containers (Drone Containers)

Detection script: `/opt/wheeler-ecosystem/scripts/drone-container-hunter.sh`

**Authorized container list (known-good baseline):**

```
aiops-prometheus, aiops-alertmanager, aiops-grafana, aiops-loki,
aiops-webhook-relay, aiops-pushgateway, aiops-healthchecks,
aiops-changedetection, aiops-clickhouse, aiops-superset, aiops-ravynai-app,
aiops-ravynai-postgres, aiops-webhook-relay,
ecosystem-graph, docuseal, docuseal-redis,
open-webui, langflow, temporal-server, temporal-ui,
usesend, frgops-standby, netdata, netdata-backup,
uptime-kuma, uptime-kuma-backup,
hostinger-health-exporter, promtail,
prediction-radar-app-api, prediction-radar-app-worker,
prediction-radar-app-scheduler, prediction-radar-app-db,
prediction-radar-app-db-backup-1, prediction-radar-app-redis,
prediction-radar-app-web, prediction-radar-grafana,
prediction-radar-prometheus, prediction-radar-alertmanager,
prediction-radar-crowdsec, prediction-radar-fail2ban,
prediction-radar-dashboard-v2, prediction-radar-fincept
```

**Risk classification for unauthorized containers:**

```bash
# Risk scored by:
# - Privileged mode → HIGH
# - Host network mode → HIGH
# - Docker socket mount → HIGH
# - Sensitive volume (/etc/shadow, /root/.ssh) → HIGH
# - Non-127.0.0.1 port bind → MEDIUM
# - Otherwise → LOW
```

**Detection output:**

```
Drone Container Hunter — 2026-05-24
═══════════════════════════════════════
  [LOW]  prediction-radar-dashboard-v2 — new container, not in baseline

Summary: 1 unauthorized container(s)
  HIGH:   0
  MEDIUM: 0
  LOW:    1
```

### 5.2 Unauthorized PM2 Processes

**Known-good PM2 process list (baseline, 19 processes):**

```
command-center, design-agent-svc, ecosystem-guardian,
event-bus-relay, frgcrm-agent-svc, frgcrm-api,
horizon-agent-svc, insforge-agent-svc, litellm,
openclaw-dashboard, paperless-agent-svc,
prediction-radar-agent-svc, ravyn-agent-svc,
surplusai-portal-api, surplusai-scraper-agent-svc,
voice-agent-svc, voice-outreach-service, war-room-server,
backup-verification (documented stopped)
```

**Detection:**

```bash
# Any PM2 process not in the known-good list
pm2 jlist | python3 -c "
import json, sys
known = ['command-center','design-agent-svc','ecosystem-guardian','event-bus-relay',
         'frgcrm-agent-svc','frgcrm-api','horizon-agent-svc','insforge-agent-svc',
         'litellm','openclaw-dashboard','paperless-agent-svc',
         'prediction-radar-agent-svc','ravyn-agent-svc','surplusai-portal-api',
         'surplusai-scraper-agent-svc','voice-agent-svc','voice-outreach-service',
         'war-room-server','backup-verification']
processes = json.load(sys.stdin)
rogue = [p['name'] for p in processes if p['name'] not in known]
if rogue:
    print(f'ROGUE PROCESSES: {rogue}')
else:
    print('PM2: CLEAN')
"
```

### 5.3 Duplicate Service Detection

```bash
# Check for multiple containers on the same port
ss -tlnp | awk '{print $4}' | awk -F: '{print $NF}' | sort -n | uniq -d
# If any port appears twice → duplicate service

# Check for multiple PM2 processes with same name
pm2 jlist | python3 -c "
import json,sys
names=[p['name'] for p in json.load(sys.stdin)]
from collections import Counter
dupes=[n for n,c in Counter(names).items() if c>1]
if dupes: print(f'DUPLICATE PM2: {dupes}')
else: print('No PM2 duplicates')
"
```

### 5.4 Stale Service Detection

Detection script: `/opt/wheeler-ecosystem/scripts/stale-service-terminator.sh`

This is a read-only scanner that identifies candidates for cleanup:

```bash
# Stopped PM2 processes not in safelist → candidates for removal
# Docker containers with zero network traffic → candidates for investigation
# Long-running (30+ days, zero restarts) non-critical processes → review
```

**Current stale services:** `backup-verification` (PM2, status=stopped, documented)

### 5.5 Service Drift Reporting

All service drift findings are pushed to the Pushgateway:

```bash
echo "drone_container_count $count" | curl -s --data-binary @- http://127.0.0.1:9092/metrics/job/drone_hunter/instance/aiops
echo "drone_high_risk_count $high" | curl -s --data-binary @- http://127.0.0.1:9092/metrics/job/drone_hunter/instance/aiops
```

---

## 6. Secret Drift

Secret drift is the most sensitive category. It detects when secrets migrate from approved storage locations (`.env` files with `chmod 600`) to unapproved locations (code, PM2 jlist, Docker inspect, git history).

### 6.1 PM2 Jlist Secret Drift

Detection is built into the `/slay` audit (from `/root/.claude/skills/slay/SKILL.md`):

```bash
pm2 jlist | python3 -c "
import json, sys
real = ['API_KEY','AUTH_TOKEN','PASSWORD','MASTER_KEY','HCLOUD_TOKEN']
for p in json.load(sys.stdin):
    env = p.get('pm2_env',{}).get('env',{})
    found = {k for k in env if any(s in k.upper() for s in real)}
    if found: print(f'LEAK: {p[\"name\"]}: {sorted(found)}')
"
```

**Target:** 0 real secrets in jlist.
**Drift:** If any secret appears, it came from a non-env-i restart. The env -i delete+start pattern must be used to clear this drift.

**Known-secret patterns in jlist (never reported, but notable):**
- `NODE_ENV`, `HOST`, `PORT` — configuration, not secrets
- Empty values or environment variable references — not leaks

### 6.2 .env File Permission Drift

**Policy:** All `.env` files must be `chmod 600` (owner read/write only).

```bash
find /opt /root -name ".env" -not -perm 600 -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null

# Expected: 0 files with non-600 permissions
# If found: critical drift — secrets potentially world-readable
```

### 6.3 Git History Secret Drift

```bash
for repo in $(find /opt/wheeler* /opt/apps -name ".git" -maxdepth 3 -type d 2>/dev/null); do
  cd "$(dirname "$repo")"
  git log --all -20 --pretty=format:'%h %s' 2>/dev/null
  # Check for committed .env files
  git rev-list --all | xargs git diff-tree --diff-filter=A -r --name-only | grep -i "\.env$" || echo "CLEAN"
done
```

### 6.4 Docker Environment Secret Drift

```bash
docker inspect $(docker ps -q) --format '{{.Name}}: {{range .Config.Env}}{{.}} {{end}}' 2>/dev/null | grep -iE 'key|secret|token|password|credential'
```

**Known acceptable findings (not drift):**
- Container referencing `.env` file (not inline secret)
- Docker secret mounts (not environment variables)

**Known drift (from ENFORCEMENT_GAP_ANALYSIS.md):**
- AWS Access Keys in usesend container env vars — 2 keys
- Anthropic API Key in prediction-radar env vars — 1 key
- Database passwords in Docker env vars — 6+ instances
- API Tokens (OANDA, ODDS, GDELT) — 3 keys

### 6.5 Secret Drift Auto-Remediation

For PM2 jlist secret leaks (the most common and most dangerous drift):

```bash
# Step 1: Delete the process with env -i to clear stored env
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 delete <name>

# Step 2: Start fresh from ecosystem.config.js
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 start <config> --only <name>

# Step 3: Save clean state
pm2 save --force

# Step 4: Verify no secrets
pm2 jlist | python3 -c "import json,sys; ..."  # (same detection as above)
```

### 6.6 Secret Drift Severity

| Drift Type | Severity | Auto-Remediation |
|-----------|----------|-----------------|
| Secret in PM2 jlist | CRITICAL | env -i delete+start |
| .env file world-readable | CRITICAL | chmod 600 |
| Secret in git history | CRITICAL | git filter-branch / BFG |
| Secret in Docker env var | HIGH | Move to .env, rotate key |
| Placeholder secret in config | MEDIUM | Replace with real secret |
| Hardcoded credential in code | MEDIUM | Extract to env variable |
| Example/dummy credential | LOW | Mark as non-production |

---

## 7. Resource Drift

Resource drift detects unexpected changes in CPU, RAM, and disk consumption that may indicate problems before they become incidents.

### 7.1 Resource Baseline Management

**Baseline source:** 7-day rolling average from Prometheus (`127.0.0.1:9090`) and Pushgateway (`127.0.0.1:9092`).

**Metrics tracked:**

| Resource | Tool | Prometheus Metric | Threshold |
|----------|------|-------------------|-----------|
| Container memory | Prometheus + cAdvisor | `container_memory_usage_bytes` | < 2x 7-day avg |
| PM2 memory | PM2 metrics | (pm2_monit) | < 2x baseline |
| CPU usage | Prometheus node_exporter | `node_cpu_seconds_total` | > 80% sustained |
| Disk usage | Prometheus node_exporter | `node_filesystem_avail_bytes` | < 20% free |
| Disk IO | Prometheus node_exporter | `node_disk_io_time_seconds_total` | > 2x baseline |
| Network IO | Docker stats | `container_network_receive_bytes_total` | > 3x baseline |

### 7.2 Container Resource Drift Detection

**Detection from GOVERNANCE_ENGINE.md Section 2.1:**

```
Policy: resource_limits
Check: docker inspect --format='Mem={{.HostConfig.Memory}} CPU={{.HostConfig.NanoCpus}}' <container>
Expected: "Mem > 0 and CPU > 0"
Drift: Any container running without resource limits
```

Current known-good state: 37 Docker containers, all with `mem_limit` and `cpus` configured.

**Reference memory baselines (notable containers):**

| Container | Limit | Current Usage | % Used | Drift Risk |
|-----------|-------|--------------|--------|-----------|
| aiops-ravynai-app | 2GB | ~600MB | 30% | LOW |
| prediction-radar-app-api | 1GB | 554MB | 54% | MEDIUM (FG-11) |
| aiops-prometheus | 4GB | ~1.2GB | 30% | LOW |
| aiops-loki | 4GB | ~800MB | 20% | LOW |
| aiops-grafana | 1GB | ~200MB | 20% | LOW |
| litellm (PM2) | N/A | 377MB | PM2 managed | MEDIUM |
| frgcrm-api (PM2) | N/A | 235MB | PM2 managed | MEDIUM |

### 7.3 PM2 Resource Drift Detection

**From GOVERNANCE_ENGINE.md Section 2.4:**

```
Policy: memory_baseline
Check: compare current memory vs pm2_monit_7day_avg
Expected: "< 2x baseline"
Drift: process exceeding 2x its 7-day average memory
```

### 7.4 Disk Resource Drift

```bash
# Check disk usage per mount point
df -h | grep -v tmpfs | grep -v overlay
# Drift: any mount < 20% free space

# Check docker disk usage
docker system df
# Drift: unexpected growth in container layers or volumes

# Check log rotation health
ls -la /var/log/wheeler/*.log
# Drift: single log file > 500MB without rotation
```

**Resource trend data is exported by scripts at:**
- `/opt/wheeler-ecosystem/scripts/resource-trend-exporter.sh`
- `/opt/wheeler-ecosystem/scripts/health-score-calculator.sh`

---

## 8. Baseline Management

### 8.1 What Is a Baseline

A baseline is a snapshot of the "known-good" state of the ecosystem at a point in time. Baselines are the reference against which drift is measured.

### 8.2 Baseline Files

| Baseline | File Path | Created By | Update Trigger |
|----------|-----------|-----------|----------------|
| Config Baseline | `/var/log/wheeler/config-baseline.json` | `config-drift-detector.sh --baseline` | After intentional config change |
| Port Baseline | `/opt/wheeler-ecosystem/enforcement/wheeler-port-audit` | lockdown watchdog | After intentional port change |
| Exposure Baseline | `/opt/wheeler-ecosystem/enforcement/wheeler-public-surface` | lockdown watchdog | After intentional network change |
| PM2 Baseline | (derived from pm2 jlist at known-good time) | `/slay` audit | After PM2 ecosystem change |
| Resource Baseline | Prometheus 7-day rolling window | Built-in | Continuous |

### 8.3 Creating a New Baseline

After any intentional configuration change, baselines must be updated:

```bash
# 1. Make the intended change
# 2. Verify everything is healthy
/opt/wheeler-ecosystem/scripts/functional-healthcheck.sh
# 3. Create new baseline
/opt/wheeler-ecosystem/scripts/config-drift-detector.sh --baseline
# 4. Update port audit
ss -tlnp > /opt/wheeler-ecosystem/enforcement/wheeler-port-audit
```

### 8.4 Baseline vs Drift Decision Matrix

| Scenario | Is It Drift? | Action |
|----------|-------------|--------|
| New Docker container added intentionally | No (if baseline updated) | Update baseline after deploy |
| New Docker container from unauthorized deploy | Yes | Flag, investigate, remove |
| Port bind changes from config change | No (if documented) | Update baseline |
| Port bind changes from auto-config | Yes | Investigate, revert or update baseline |
| PM2 process stopped intentionally | No (e.g., backup-verification) | Document exemption |
| PM2 process crashed unexpectedly | Yes | Auto-remediate, update baseline if needed |
| CPU/memory spike during job processing | No (transient) | Monitor, no action |
| CPU/memory spike sustained > 2x baseline | Yes | Investigate, adjust limits |

### 8.5 Baseline Rotation and Expiry

- Config baselines expire after 7 days without update
- Port baselines expire after 30 days without update
- Resource baselines are rolling (7-day window, continuous)
- PM2 baselines are validated on every `/slay` run

---

## 9. Drift Detection Schedule

### 9.1 Continuous Detection

The following drift checks run continuously (process restarts, event-driven, or on every cron iteration):

| Drift Check | Mechanism | Interval | Tool |
|------------|-----------|----------|------|
| Port bind drift | ss -tlnp scan | Every 5 min | `wheeler-lockdown-watchdog.sh` |
| Docker health drift | Docker health check | Every 2 min | `autoheal.sh` |
| PM2 status drift | pm2 jlist | Every 2 min | `ecosystem-guardian` |
| UFW rule drift | ufw status | Every 5 min | `wheeler-lockdown-watchdog.sh` |
| Exposure drift | Port cross-reference | Every 5 min | `wheeler-lockdown-watchdog.sh` |
| Dead man's switch | Pushgateway metric | Every 2 min | `dead-mans-switch.sh` |

### 9.2 Periodic Detection

The following drift checks run on a scheduled basis:

| Drift Check | Interval | Tool | Notes |
|------------|----------|------|-------|
| Config drift (full) | Every 60 min | `config-drift-detector.sh --check` | Full container/process/port diff |
| Container drift | Every 60 min | `drone-container-hunter.sh` | Unauthorized container scan |
| Secret drift | Every 60 min | PM2 jlist inspect | Secret leak detection |
| Service drift | Every 120 min | `stale-service-terminator.sh` | Stale/duplicate service scan |
| Resource drift | Every 15 min | Prometheus queries | CPU/memory/disk trend |
| .env permission drift | Every 240 min | `find -perm` scan | World-readable secrets |
| git history drift | Every 1440 min (daily) | git log scan | Secrets in version control |
| Compliance score | Every 1440 min (daily) | Full governance audit | Scorecard update |

### 9.3 Event-Driven Detection

The following events trigger immediate drift detection:

- Docker container start/stop (event hook)
- PM2 process status change (ecosystem-guardian)
- UFW rule change (inotify on /etc/ufw/)
- nginx config reload
- Deployment or configuration change
- Manual /slay invocation

### 9.4 Drift Detection Logging

All drift detections are logged to:
- `/var/log/wheeler/config-drift.log` — configuration and port drift
- `/var/log/wheeler/drone-hunter.log` — unauthorized container detection
- `/var/log/wheeler/stale-services.log` — stale service detection
- `/var/log/wheeler-watchdog.log` — lockdown watchdog output
- `/var/log/wheeler/self-healing.log` — remediation actions

---

## 10. Auto-Remediation of Drift

### 10.1 Can Auto-Heal (No Approval Required)

These drifts can be auto-remediated because the fix is deterministic and carries low risk:

| Drift Type | Auto-Remediation | Timeout |
|-----------|-----------------|---------|
| Port bind changed from 127.0.0.1 to 0.0.0.0 | Recreate container with correct bind | 5 min |
| PM2 process crashed (no config change) | `pm2 restart <name>` | 2 min |
| Docker container unhealthy | `docker restart <name>` | 2 min |
| Docker container exited | `docker start <name>` | 2 min |
| PM2 memory > 2x baseline | Increase memory limit or restart | 5 min |
| Container memory approaching limit | `docker update --memory <new_limit>` | 2 min |
| .env file permissions not 600 | `chmod 600 <file>` | 1 min |
| PM2 jlist secret leak | env -i delete+start | 5 min |

### 10.2 Requires Approval

These drifts require manual approval because the remediation is potentially destructive or requires judgment:

| Drift Type | Why Needs Approval | Approval Path |
|-----------|-------------------|---------------|
| New unauthorized container (HIGH risk) | Could be legitimate deploy; don't kill blindly | Review, add to authorized list or remove |
| Rogue PM2 process | Could be intentional deploy from another config | Investigate, add to ecosystem.config or terminate |
| UFW rule unauthorized change | Network security — revert could break connectivity | Review change, revert if malicious |
| nginx config changed | Could be intentional update | Compare with git, accept or revert |
| Container :latest tag detected | Needs version pin and verification | Pin version, test, deploy |
| Disk > 80% full | Can't just delete — need to identify what to clean | Investigate, clean specific data |

### 10.3 Auto-Remediation Safety Rules

From `/opt/wheeler-ecosystem/scripts/auto-approval-gate.sh`:

1. **3-strike limit**: If the same service requires auto-remediation 3 times within 10 minutes, auto-remediation stops and the incident escalates to SEV1
2. **No destructive auto-actions**: Never auto-approve delete, drop, purge, or force operations
3. **No critical target auto-remediation**: Never auto-remediate postgres, redis, prometheus, alertmanager, or frgcrm-api at SEV2+
4. **Verification required**: Every auto-remediation must be verified within 60 seconds. If verification fails, escalate
5. **State recorded**: Every auto-remediation action is recorded in `/var/log/wheeler/healing-state.json`

### 10.4 Drift Remediation Verification

All drift remediations must pass verification (Zero False Green policy):

```bash
# Example: Port bind drift fix verification
EVIDENCE_LEVEL="CONFIRMED"
COMMAND="ss -tlnp | grep <port> | grep 127.0.0.1"
OUTPUT=$(ss -tlnp | grep <port> | grep 127.0.0.1)
if [ -n "$OUTPUT" ]; then
  echo "VERIFIED: Port $port is now on 127.0.0.1"
else
  echo "FAILED: Port $port still exposed"
fi
```

---

## 11. Integration with Ecosystem Graph (Neo4j)

The ecosystem graph at `127.0.0.1:7687` (container `ecosystem-graph`, image `neo4j:5.26-community`) stores the topology of the Wheeler ecosystem. Drift detection compares the current state against the graph.

### 11.1 Graph Schema for Drift

The Neo4j graph models the ecosystem with these node types:

```
(:Service {name, port, bind, type, status})
(:Container {name, image, status, memory_limit, cpu_limit})
(:Process {name, pid, status, type, config_path})
(:Host {name, ip, tailscale_ip})
(:Dependency {source, target, protocol, port})

(:Service)-[:RUNS_ON]->(:Host)
(:Service)-[:DEPENDS_ON]->(:Service)
(:Container)-[:HOSTS]->(:Service)
(:Process)-[:MANAGED_BY]->(:PM2)
```

### 11.2 Topology Comparison

```cypher
// Find services in the graph that are not running
MATCH (s:Service {host: 'aiops'})
WHERE s.status = 'online'
  AND NOT EXISTS {
    MATCH (n:Process {name: s.name})
    WHERE n.status = 'online'
  }
  AND NOT EXISTS {
    MATCH (c:Container {name: s.name})
    WHERE c.status CONTAINS 'Up'
  }
RETURN s.name, s.port, 'MISSING' AS drift_type
```

```cypher
// Find running services not in the graph
// (potential unauthorized services)
MATCH (p:Process {host: 'aiops', status: 'online'})
WHERE NOT EXISTS {
  MATCH (s:Service {name: p.name})
}
RETURN p.name, 'UNKNOWN' AS drift_type
```

### 11.3 Dependency Graph Drift

When a dependency changes (a service moves, a port changes, a database migrates), the ecosystem graph detects it as drift:

```cypher
// Detect dependency port changes
MATCH (a:Service)-[d:DEPENDS_ON]->(b:Service)
WHERE d.port <> b.port
  AND b.status = 'online'
RETURN a.name, b.name, d.port AS expected_port, b.port AS actual_port
```

### 11.4 Graph Update on Drift Remediation

After a drift is remediated, the graph is updated:

```bash
# POST to ecosystem graph API at 127.0.0.1:7474
curl -X POST http://127.0.0.1:7474/db/data/transaction/commit \
  -H "Content-Type: application/json" \
  -d '{
    "statements": [{
      "statement": "MATCH (s:Service {name: $name}) SET s.status = $status, s.last_updated = datetime()",
      "parameters": {"name": "frgcrm-api", "status": "online"}
    }]
  }'
```

### 11.5 Drift History in Graph

All drift events are recorded as nodes in the graph for trend analysis:

```cypher
CREATE (d:DriftEvent {
  id: 'DRIFT-20260524-001',
  type: 'port_bind',
  service: 'ravyn-agent-svc',
  expected: '127.0.0.1:8005',
  actual: '[::]:8005',
  detected_at: datetime('2026-05-24T04:36:00Z'),
  remediated: true,
  remediated_at: datetime('2026-05-24T05:00:00Z'),
  auto_remediated: true
})

// Query drift history
MATCH (d:DriftEvent)
WHERE d.detected_at > datetime() - duration('P7D')
RETURN d.type, count(*) AS frequency, sum(CASE WHEN d.auto_remediated THEN 1 ELSE 0 END) AS auto_fixed
ORDER BY frequency DESC
```

---

*End of Drift Detection Framework. Integrates with `/root/WHEELER_BRAIN_OS/architecture/GOVERNANCE_ENGINE.md`, `/opt/wheeler-ecosystem/scripts/config-drift-detector.sh`, `/opt/wheeler-ecosystem/enforcement/wheeler-lockdown-watchdog.sh`, and `/opt/wheeler-ecosystem/scripts/drone-container-hunter.sh`.*
