---
name: slay
description: "Full Wheeler ecosystem health audit + auto-remediation. Runs 20-endpoint health check, PM2 jlist secret scan, Docker :latest audit, network bind verification. Fixes any broken processes using env -i delete+start pattern. Target: 100/100 state."
trigger: slay, /slay, slay all, health audit, full audit, fix everything, ecosystem check
---

# Skill: /slay — Full Ecosystem Audit + Auto-Remediation

Runs a complete health audit across all 7 QA domains and fixes any issues found. This is the operator command that maintains the 100/100 A+ state documented at `/root/STAGE2_QA_SCORECARD_FINAL.md`.

## Phase 1: Audit (read-only)

### 1a. Functional Health Check
```bash
/opt/wheeler-ecosystem/scripts/functional-healthcheck.sh
```

### 1b. PM2 Jlist Secret Scan
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
Target: 0 real secrets in jlist. If any found, they came from a non-env-i restart and must be remediated.

### 1c. PM2 Status
```bash
pm2 list
```
Check for: crashed processes (status != "online"), restart loops (> 5 restarts in current uptime).

### 1d. Docker :latest Audit
```bash
docker ps --format '{{.Image}}' | grep ':latest' || echo "CLEAN"
```
Target: 0 `:latest` images. If any found, pin and recreate via docker-compose.

### 1e. Network Bind Verification
```bash
ss -tlnp | awk '$4 !~ /127.0.0.1|::1|100\.121\.230\.28/ && NR>1 {print}'
```
Target: only SSH (0.0.0.0:22) and Tailscale on non-loopback.

### 1f. Health Check Paths
All services on 127.0.0.1 with these endpoints:
| Service | Port | Health Path |
|---------|------|-------------|
| frgcrm-api | 8001 | /health |
| surplusai-api | 8103 | /docs |
| litellm | 4049 | /health (401 = alive) |
| war-room | 8021 | / |
| openclaw-dash | 8110 | / |
| ravyn-agent | 8003 | /health |
| frgcrm-agent | 8002 | /health |
| horizon-agent | 8006 | /health |
| surplusai-agent | 8009 | /health |
| voice-agent | 8014 | /health |
| paperless-agent | 8012 | /health |
| pred-radar-agent | 8011 | /health |
| insforge-agent | 8008 | /health |
| design-agent | 8020 | /health |
| prometheus | 9090 | /-/healthy |
| alertmanager | 9093 | /-/healthy |
| grafana | 3002 | /api/health |
| loki | 3100 | /ready |
| coredb-pg | 5432 | (TCP) |
| coredb-redis | 6379 | (TCP) |

## Phase 2: Remediation

### 2a. Fix Crashed PM2 Process
```bash
# Check logs for root cause
pm2 logs <name> --nostream --lines 50 | tail -20

# If config/code unchanged → plain restart (preserves clean state)
pm2 restart <name>

# If ecosystem config changed → env -i delete + start
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 delete <name>
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 start <config> --only <name>
```

### 2b. Fix PM2 Jlist Secret Leak
If any process shows secrets in jlist:
```bash
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 delete <name>
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PM2_HOME=/root/.pm2 pm2 start <config> --only <name>
pm2 save --force
```
**Never use `pm2 restart --update-env`** — it injects shell secrets into PM2's stored state.

### 2c. Fix Docker :latest Image
```bash
# Find actual version
docker exec <container> /bin/sh -c "<binary> --version" 2>/dev/null

# Add to docker-compose.yml with pinned version
# Restart: docker compose up -d <service>
```

### 2d. PM2 Ecosystem Config Mapping
| Process | Config File |
|---------|------------|
| design-agent-svc | /opt/apps/design-agent-svc/ecosystem.config.js |
| horizon-agent-svc | /opt/apps/horizon-agent-svc/ecosystem.config.js |
| prediction-radar-agent-svc | /opt/apps/prediction-radar-agent-svc/ecosystem.config.js |
| paperless-agent-svc | /opt/apps/paperless-agent-svc/ecosystem.config.js |
| ravyn-agent-svc | /opt/apps/ravyn-agent-svc/ecosystem.config.js |
| frgcrm-agent-svc | /opt/apps/frgcrm-agent-svc/ecosystem.config.js |
| surplusai-scraper-agent-svc | /opt/apps/surplusai-scraper-agent-svc/ecosystem.config.js |
| insforge-agent-svc | /opt/apps/insforge-agent-svc/ecosystem.config.js |
| voice-agent-svc | /opt/apps/voice-agent-svc/ecosystem.config.js |
| openclaw-dashboard | /opt/openclaw-dashboard/ecosystem.config.js |
| voice-outreach-service | /opt/apps/frgcrm/voice_outreach_service/ecosystem.config.js |
| frgcrm-api | /opt/wheeler/apps/frgcrm/api/ecosystem.config.js |
| ecosystem-guardian | /opt/apps/wheeler-brain-os/ecosystem.config.js |
| event-bus-relay | /opt/apps/wheeler-brain-os/ecosystem.config.js |
| backup-verification | /opt/apps/wheeler-brain-os/ecosystem.config.js |
| war-room-server | /opt/apps/war-room/ecosystem.config.js |
| litellm | /opt/apps/litellm/ecosystem.config.js |
| surplusai-portal-api | /opt/apps/surplusai-portal/ecosystem.config.js |

## Phase 3: Final Verification

```bash
# Re-run health check
/opt/wheeler-ecosystem/scripts/functional-healthcheck.sh

# Verify jlist clean
pm2 jlist | python3 -c "..." # (same as Phase 1b)

# Verify no :latest
docker ps --format '{{.Image}}' | grep ':latest' | wc -l  # → 0

# Save state
pm2 save --force
```

## Output Format

```
/slay — ECOSYSTEM AUDIT
═══════════════════════════════════════
PHASE 1: AUDIT
  Health:   XX/20
  PM2:      X crashed, X secret leaks
  Docker:   X :latest
  Network:  [CLEAN / X issues]

PHASE 2: REMEDIATION
  [actions taken or "none needed"]

PHASE 3: VERIFICATION
  Health:   XX/20
  PM2:      CLEAN
  Docker:   CLEAN
  Network:  CLEAN
═══════════════════════════════════════
SCORE: [letter grade] ([issues remaining] remaining)
```
