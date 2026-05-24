---
name: pm2-restart-deploy-master
description: "Master PM2 restart and deploy playbook — all canonical patterns, danger thresholds, and config mappings"
metadata: 
  node_type: memory
  type: reference
  originSessionId: ecc0cddd-b2c8-4d99-9436-6f3f2f3937ac
---

## PM2 Restart/Deploy Master Reference — 2026-05-24

### Canonical Restart Pattern (safe)
```bash
# For unchanged code — plain restart preserves clean state
pm2 restart <name>
```

### Canonical Deploy Pattern (code or config changed)
```bash
# Step 1: Delete
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  PM2_HOME=/root/.pm2 pm2 delete <name>

# Step 2: Start with clean env
cd /opt/apps/<name>
env -i HOME=/root PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  NODE_ENV=production PM2_HOME=/root/.pm2 pm2 start ecosystem.config.js --only <name>

# Step 3: Persist
pm2 save --force
```

### DANGER: Never Use
- `pm2 restart --update-env` — injects shell secrets into PM2 stored state
- `pm2 restart <name>` after config change — reuses stale pm2_env.env
- `pm2 kill` — destroys process table, daemon auto-resurrects old state from dump.pm2

### ecosystem.config.js Rules
- **NEVER** use `process.env.VAR || ""` in `env: {}` blocks — captures shell secrets into PM2
- Only hardcoded non-sensitive values: PORT, URIs, booleans
- Secrets loaded via .env files at app runtime, not PM2 env

### Verification
```bash
# Secret scan (checks both key names AND values)
pm2 jlist | python3 -c "
import json, sys
real = ['API_KEY','AUTH_TOKEN','PASSWORD','MASTER_KEY','HCLOUD_TOKEN','SECRET']
for p in json.load(sys.stdin):
    env = p.get('pm2_env',{}).get('env',{})
    for k,v in env.items():
        if any(s in k.upper() for s in real) and v:
            print(f'LEAK: {p[\"name\"]}: {k}={v[:30]}')
print('CLEAN' if not any(
    v for p in json.load(sys.stdin) 
    for k,v in p.get('pm2_env',{}).get('env',{}).items()
    if any(s in k.upper() for s in real) and v
) else '')
"

# Verify process online
pm2 jlist | python3 -c "import json,sys;[print(p['name'],p['pm2_env']['status']) for p in json.load(sys.stdin)]"

# Save clean state
pm2 save --force
```

### Auto-Resurrect Guard
PM2 saves state to `/root/.pm2/dump.pm2`. Deleted processes auto-return if:
1. PM2 daemon restarts
2. System reboots
3. `pm2 resurrect` runs

Always `pm2 save --force` after deletions to persist.

### Known Process Map (24 total as of 2026-05-24)
| Process | Config Path | Port | Sensitive? |
|---------|------------|------|------------|
| command-center | /opt/apps/command-center/ecosystem.config.js | 8100 | No |
| ecosystem-guardian | /opt/apps/wheeler-brain-os/ecosystem.config.js | 8095 | No |
| event-bus-relay | /opt/apps/wheeler-brain-os/ecosystem.config.js | - | No |
| war-room-server | /opt/apps/war-room/ecosystem.config.js | 8091 | No |
| litellm | /opt/apps/litellm/ecosystem.config.js | 4049 | No |
| frgcrm-api | /opt/wheeler/apps/frgcrm/api/ecosystem.config.js | 8082 | No |
| surplusai-portal-api | /opt/apps/surplusai-portal/ecosystem.config.js | 8103 | No |
| openclaw-dashboard | /opt/openclaw-dashboard/ecosystem.config.js | 8110 | No |
| design-agent-svc | /opt/apps/design-agent-svc/ecosystem.config.js | 8020 | No |
| horizon-agent-svc | /opt/apps/horizon-agent-svc/ecosystem.config.js | 8006 | No |
| pred-radar-agent-svc | /opt/apps/prediction-radar-agent-svc/ecosystem.config.js | 8011 | No |
| paperless-agent-svc | /opt/apps/paperless-agent-svc/ecosystem.config.js | 8009 | No |
| ravyn-agent-svc | /opt/apps/ravyn-agent-svc/ecosystem.config.js | 8003 | No |
| frgcrm-agent-svc | /opt/apps/frgcrm-agent-svc/ecosystem.config.js | 8002 | No |
| surplusai-scraper-agent-svc | /opt/apps/surplusai-scraper-agent-svc/ecosystem.config.js | 8009 | No |
| insforge-agent-svc | /opt/apps/insforge-agent-svc/ecosystem.config.js | 8008 | No |
| voice-agent-svc | /opt/apps/voice-agent-svc/ecosystem.config.js | 8014 | No |
| voice-outreach-service | /opt/apps/frgcrm/voice_outreach_service/ecosystem.config.js | - | No |
| backup-verification | /opt/apps/wheeler-brain-os/ecosystem.config.js | - | No |
| revenue-metrics-collector | /opt/apps/revenue-metrics-collector/ecosystem.config.js | 8170 | No* |
| executive-dashboard-api | /opt/apps/executive-dashboard-api/ecosystem.config.js | 8180 | No* |
| aiops-saas-api | /opt/apps/aiops-saas-api/ecosystem.config.js | 8150 | No* |
| wheeler-brain-api | /opt/apps/wheeler-brain-api/ecosystem.config.js | 8160 | No* |

*Marked "No" for secrets in PM2 env. These apps load secrets via their own runtime config, not PM2 env.

### How to apply
When deploying or restarting any PM2 process, follow the canonical pattern. Always verify with the secret scan after. If any process shows secret values, the ecosystem config has `process.env.VAR` references that must be removed.

**Related:** [[pm2-env-i-pattern]] [[pm2-process-env-leak]] [[pm2-restart-canonical]] [[pm2-deploy-state]]
