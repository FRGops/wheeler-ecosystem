---
name: slay
description: "Full Wheeler ecosystem health audit + auto-remediation. Runs 45-endpoint health check, PM2 jlist secret scan, Docker :latest audit, network bind verification. Fixes any broken processes using env -i delete+start pattern. Target: 100/100 state."
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
# Phase 1b-1: Find all secrets in PM2 stored state
pm2 jlist | python3 -c "
import json, sys
real = ['API_KEY','AUTH_TOKEN','PASSWORD','MASTER_KEY','HCLOUD_TOKEN']
leaks = {}
for p in json.load(sys.stdin):
    env = p.get('pm2_env',{}).get('env',{})
    found = {k for k in env if any(s in k.upper() for s in real)}
    if found:
        leaks[p['name']] = sorted(found)
        print(f'LEAK: {p[\"name\"]}: {sorted(found)}')
if not leaks:
    print('CLEAN: 0 real secrets in PM2 stored state')
"
```
Target: 0 real secrets in jlist. If any found, classify them in Phase 1b-2.

```bash
# Phase 1b-2: Classify each leak as hardcoded (P0) or daemon-inherited (P1)
for proc in $(pm2 jlist 2>/dev/null | python3 -c "
import json, sys
real = ['API_KEY','AUTH_TOKEN','PASSWORD','MASTER_KEY','HCLOUD_TOKEN']
for p in json.load(sys.stdin):
    env = p.get('pm2_env',{}).get('env',{})
    found = {k for k in env if any(s in k.upper() for s in real)}
    if found:
        print(p['name'])
"); do
    config=$(pm2 jlist 2>/dev/null | python3 -c "
import json, sys, os
for p in json.load(sys.stdin):
    if p['name'] == '$proc':
        path = p['pm2_env'].get('pm_exec_path', '')
        if path:
            d = os.path.dirname(path)
            while d and d != '/':
                cfg = os.path.join(d, 'ecosystem.config.js')
                if os.path.exists(cfg):
                    print(cfg)
                    break
                d = os.path.dirname(d)
        break
")
    echo \"--- $proc ---\"
    if [ -n \"$config\" ] && grep -qE \"process\.env\.(ANTHROPIC|DEEPSEEK|API_KEY|AUTH_TOKEN|MASTER_KEY|HCLOUD_TOKEN|PASSWORD)\" \"$config\" 2>/dev/null; then
        echo \"TYPE: HARDCODED (P0) - process.env reference in $config\"
    else
        echo \"TYPE: DAEMON-INHERITED (P1) - not found in ecosystem.config.js\"
    fi
done
```

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
| frgcrm-api | 8082 | /health |
| surplusai-api | 8103 | /docs (200 = alive) |
| litellm | 4049 | /health (401 = alive) |
| war-room | 8091 | / |
| openclaw-dash | 8110 | / |
| executive-dashboard-api | 8180 | / |
| wheeler-brain-api | 8160 | /health |
| aiops-saas-api | 8150 | /health |
| frg-site | 3200 | / (Next.js, 404 = alive) |
| embedding-service | 8191 | /docs |
| ravyn-agent-svc | 8005 | /health |
| ravynai-opportunity-graph | 8014 | /health |
| frgcrm-agent-svc | 8003 | /health |
| horizon-agent-svc | 8006 | /health |
| surplusai-scraper-agent-svc | 8007 | /health |
| voice-agent-svc | 8008 | /health |
| paperless-agent-svc | 8009 | /health |
| pred-radar-agent-svc | 8011 | /health |
| insforge-agent-svc | 8013 | /health |
| design-agent-svc | 8020 | /health |
| wealth-personal-agent-svc | 8021 | /health |
| calendar-ai-agent-svc | 8022 | /health |
| productivity-coach-agent-svc | 8023 | /health |
| health-tracker-agent-svc | 8024 | /health |
| fitness-coach-agent-svc | 8025 | /health |
| nutrition-advisor-agent-svc | 8026 | /health |
| network-manager-agent-svc | 8027 | /health |
| travel-planner-agent-svc | 8028 | /health |
| logistics-coordinator-agent-svc | 8029 | /health |
| learning-coach-agent-svc | 8030 | /health |
| property-manager-agent-svc | 8031 | /health |
| home-automation-agent-svc | 8032 | /health |
| content-marketing-agent-svc | 8033 | /health |
| social-media-agent-svc | 8034 | /health |
| conversion-optimization-agent-svc | 8035 | /health |
| ad-management-agent-svc | 8036 | /health |
| link-building-agent-svc | 8037 | /health |
| brand-management-agent-svc | 8038 | /health |
| email-marketing-agent-svc | 8039 | /health |
| analytics-agent-svc | 8040 | /health |
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

### 2b-2: Fix Daemon-Inherited Secret Leak (P1)
If secrets are daemon-inherited (not in ecosystem config):
1. Verify the process actually needs them (check if it calls LLM APIs)
2. If YES: ensure it uses pm2-env-wrapper.sh or has its own .env file loaded via env_file in ecosystem.config.js
3. If NO: no action needed — will be clean after PM2 daemon env cleanup
4. Systemd fix: create /etc/systemd/system/pm2-root.service.d/clean-env.conf with UnsetEnvironment= directives
5. Run: systemctl daemon-reload && systemctl restart pm2-root
6. Re-scan: pm2 jlist should be clean

### 2c. Fix Docker :latest Image
```bash
# Find actual version
docker exec <container> /bin/sh -c "<binary> --version" 2>/dev/null

# Add to docker-compose.yml with pinned version
# Restart: docker compose up -d <service>
```

### 2d. PM2 Ecosystem Config Mapping (85 processes)
| Process | Config File |
|---------|------------|
| ad-management-agent-svc | /opt/apps/ad-management-agent-svc/ecosystem.config.js |
| aiops-saas-api | /opt/apps/aiops-saas-api/ecosystem.config.js |
| analytics-agent-svc | /opt/apps/analytics-agent-svc/ecosystem.config.js |
| backup-verification | /opt/apps/wheeler-brain-os/ecosystem.config.js |
| brand-management-agent-svc | /opt/apps/brand-management-agent-svc/ecosystem.config.js |
| calendar-ai-agent-svc | /opt/apps/calendar-ai-agent-svc/ecosystem.config.js |
| ceo-command-console-agent-svc | /opt/apps/ceo-command-console-agent-svc/ecosystem.config.js |
| command-center | /opt/apps/command-center/ecosystem.config.js |
| competitive-analysis-agent-svc | /opt/apps/competitive-analysis-agent-svc/ecosystem.config.js |
| content-marketing-agent-svc | /opt/apps/content-marketing-agent-svc/ecosystem.config.js |
| conversion-optimization-agent-svc | /opt/apps/conversion-optimization-agent-svc/ecosystem.config.js |
| customer-success-agent-svc | /opt/apps/customer-success-agent-svc/ecosystem.config.js |
| customer-support-agent-svc | /opt/apps/customer-support-agent-svc/ecosystem.config.js |
| dashboard | /root/wheeler-command-center (pm2 start server.js) — no ecosystem config |
| data-pipeline-agent-svc | /opt/apps/data-pipeline-agent-svc/ecosystem.config.js |
| data-quality-monitor-agent-svc | /opt/apps/data-quality-monitor-agent-svc/ecosystem.config.js |
| data-warehouse-agent-svc | /opt/apps/data-warehouse-agent-svc/ecosystem.config.js |
| database-rls-auditor-agent-svc | /opt/apps/database-rls-auditor-agent-svc/ecosystem.config.js |
| deployment-intelligence-agent-svc | /opt/apps/deployment-intelligence-agent-svc/ecosystem.config.js |
| design-agent-svc | /opt/apps/design-agent-svc/ecosystem.config.js |
| docker-intelligence-agent-svc | /opt/apps/docker-intelligence-agent-svc/ecosystem.config.js |
| ecosystem-guardian | /opt/apps/wheeler-brain-os/ecosystem.config.js |
| ecosystem-health-scoring-agent-svc | /opt/apps/ecosystem-health-scoring-agent-svc/ecosystem.config.js |
| eligibility-api | /opt/apps/eligibility-api/ecosystem.config.js |
| email-marketing-agent-svc | /opt/apps/email-marketing-agent-svc/ecosystem.config.js |
| embedding-service | /opt/apps/embedding-service/ecosystem.config.js |
| etl-orchestrator-agent-svc | /opt/apps/etl-orchestrator-agent-svc/ecosystem.config.js |
| event-bus-relay | /opt/apps/wheeler-brain-os/ecosystem.config.js |
| executive-dashboard-api | /opt/apps/executive-dashboard-api/ecosystem.config.js |
| experiment-tracker-agent-svc | /opt/apps/experiment-tracker-agent-svc/ecosystem.config.js |
| feature-prioritization-agent-svc | /opt/apps/feature-prioritization-agent-svc/ecosystem.config.js |
| feedback-collection-agent-svc | /opt/apps/feedback-collection-agent-svc/ecosystem.config.js |
| fitness-coach-agent-svc | /opt/apps/fitness-coach-agent-svc/ecosystem.config.js |
| frg-site | Direct start (pm2 start next -- start -p 3200 -H 127.0.0.1) — no ecosystem config |
| frgcrm-agent-svc | /opt/apps/frgcrm-agent-svc/ecosystem.config.js |
| frgcrm-api | /opt/wheeler/apps/frgcrm/api/ecosystem.config.js |
| health-tracker-agent-svc | /opt/apps/health-tracker-agent-svc/ecosystem.config.js |
| helpdesk-agent-svc | /opt/apps/helpdesk-agent-svc/ecosystem.config.js |
| home-automation-agent-svc | /opt/apps/home-automation-agent-svc/ecosystem.config.js |
| horizon-agent-svc | /opt/apps/horizon-agent-svc/ecosystem.config.js |
| incident-forensics-agent-svc | /opt/apps/incident-forensics-agent-svc/ecosystem.config.js |
| incident-response-agent-svc | /opt/apps/incident-response-agent-svc/ecosystem.config.js |
| infrastructure-optimization-agent-svc | /opt/apps/infrastructure-optimization-agent-svc/ecosystem.config.js |
| insforge-agent-svc | /opt/apps/insforge-agent-svc/ecosystem.config.js |
| learning-coach-agent-svc | /opt/apps/learning-coach-agent-svc/ecosystem.config.js |
| link-building-agent-svc | /opt/apps/link-building-agent-svc/ecosystem.config.js |
| litellm | /opt/apps/litellm/ecosystem.config.js |
| logistics-coordinator-agent-svc | /opt/apps/logistics-coordinator-agent-svc/ecosystem.config.js |
| ml-training-agent-svc | /opt/apps/ml-training-agent-svc/ecosystem.config.js |
| model-registry-agent-svc | /opt/apps/model-registry-agent-svc/ecosystem.config.js |
| monitoring-intelligence-agent-svc | /opt/apps/monitoring-intelligence-agent-svc/ecosystem.config.js |
| network-manager-agent-svc | /opt/apps/network-manager-agent-svc/ecosystem.config.js |
| nutrition-advisor-agent-svc | /opt/apps/nutrition-advisor-agent-svc/ecosystem.config.js |
| onboarding-agent-svc | /opt/apps/onboarding-agent-svc/ecosystem.config.js |
| openclaw-dashboard | /opt/openclaw-dashboard/ecosystem.config.js |
| paperless-agent-svc | /opt/apps/paperless-agent-svc/ecosystem.config.js |
| penetration-testing-agent-svc | /opt/apps/penetration-testing-agent-svc/ecosystem.config.js |
| pm2-logrotate | PM2 module (pm2 install) — no ecosystem config |
| prediction-radar-agent-svc | /opt/apps/prediction-radar-agent-svc/ecosystem.config.js |
| product-manager-agent-svc | /opt/apps/product-manager-agent-svc/ecosystem.config.js |
| production-readiness-agent-svc | /opt/apps/production-readiness-agent-svc/ecosystem.config.js |
| productivity-coach-agent-svc | /opt/apps/productivity-coach-agent-svc/ecosystem.config.js |
| property-manager-agent-svc | /opt/apps/property-manager-agent-svc/ecosystem.config.js |
| ravyn-agent-svc | /opt/apps/ravyn-agent-svc/ecosystem.config.js |
| ravynai-og-scheduler | /opt/apps/ravynai-opportunity-graph/ecosystem.config.js |
| ravynai-og-sync | /opt/apps/ravynai-opportunity-graph/ecosystem.config.js |
| ravynai-opportunity-graph | /opt/apps/ravynai-opportunity-graph/ecosystem.config.js |
| repo-engine | Shell script (/opt/wheeler-ecosystem/repo-router/repo-engine.sh) — no ecosystem config |
| repo-listener | Shell script (/root/scripts/repo-listener.sh) — no ecosystem config |
| revenue-metrics-collector | /opt/apps/revenue-metrics-collector/ecosystem.config.js |
| rollback-intelligence-agent-svc | /opt/apps/rollback-intelligence-agent-svc/ecosystem.config.js |
| security-operations-center-agent-svc | /opt/apps/security-operations-center-agent-svc/ecosystem.config.js |
| social-media-agent-svc | /opt/apps/social-media-agent-svc/ecosystem.config.js |
| surplusai-portal-api | /opt/apps/surplusai-portal/ecosystem.config.js |
| surplusai-scraper-agent-svc | /opt/apps/surplusai-scraper-agent-svc/ecosystem.config.js |
| threat-intelligence-agent-svc | /opt/apps/threat-intelligence-agent-svc/ecosystem.config.js |
| travel-planner-agent-svc | /opt/apps/travel-planner-agent-svc/ecosystem.config.js |
| user-research-agent-svc | /opt/apps/user-research-agent-svc/ecosystem.config.js |
| voice-agent-svc | /opt/apps/voice-agent-svc/ecosystem.config.js |
| voice-outreach-service | /opt/apps/frgcrm/voice_outreach_service/ecosystem.config.js |
| vulnerability-scanner-agent-svc | /opt/apps/vulnerability-scanner-agent-svc/ecosystem.config.js |
| war-room-server | /opt/apps/war-room/ecosystem.config.js |
| wealth-personal-agent-svc | /opt/apps/wealth-personal-agent-svc/ecosystem.config.js |
| wheeler-brain-api | /opt/apps/wheeler-brain-api/ecosystem.config.js |
| wheeler-brain-core-agent-svc | /opt/apps/wheeler-brain-core-agent-svc/ecosystem.config.js |

## Phase 3: Final Verification

```bash
# Re-run health check
/opt/wheeler-ecosystem/scripts/functional-healthcheck.sh

# Re-run Phase 1b-1: verify jlist clean
pm2 jlist | python3 -c "
import json, sys
real = ['API_KEY','AUTH_TOKEN','PASSWORD','MASTER_KEY','HCLOUD_TOKEN']
leaks = {}
for p in json.load(sys.stdin):
    env = p.get('pm2_env',{}).get('env',{})
    found = {k for k in env if any(s in k.upper() for s in real)}
    if found:
        leaks[p['name']] = sorted(found)
        print(f'LEAK: {p[\"name\"]}: {sorted(found)}')
if not leaks:
    print('CLEAN: 0 real secrets')
"

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
  Health:   XX/45
  PM2:      X crashed, X secret leaks (A hardcoded/P0, B daemon-inherited/P1)
  Docker:   X :latest
  Network:  [CLEAN / X issues]

PHASE 2: REMEDIATION
  [actions taken or "none needed"]

PHASE 3: VERIFICATION
  Health:   XX/45
  PM2:      CLEAN
  Docker:   CLEAN
  Network:  CLEAN
═══════════════════════════════════════
SCORE: [letter grade] ([issues remaining] remaining)
```
