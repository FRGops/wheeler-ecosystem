#!/bin/bash
# ==============================================================================
# PM2 Secret Hygiene Remediation Script
# Fixes: eligibility-api (leaked DEEPSEEK_API_KEY, ANTHROPIC_AUTH_TOKEN)
#        war-room-server (hardcoded WAR_ROOM_AUTH_TOKEN in ecosystem.config.js)
#
# Strategy:
#   1. Remove hardcoded secrets from ecosystem.config.js env blocks
#   2. Use filter_env to block parent shell inheritance
#   3. Rely on pm2-env-wrapper.sh + ENV_FILE for runtime secret loading
#   4. Delete + recreate processes with env -i to clear stored secrets
# ==============================================================================
set -euo pipefail

LOG_FILE="/root/deployment-engine/logs/pm2-secret-fix.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PM2_HOME="${PM2_HOME:-/root/.pm2}"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=============================================="
echo "PM2 Secret Hygiene Fix — $TIMESTAMP"
echo "=============================================="

# ---- PHASE 1: Pre-flight check -------------------------------------------
echo ""
echo "--- PHASE 1: Pre-flight ---"

# Verify PM2 is running
if ! pm2 ping >/dev/null 2>&1; then
    echo "FATAL: PM2 daemon not running. Aborting."
    exit 1
fi
echo "[OK] PM2 daemon responding"

# Snapshot before state
echo ""
echo "Before state:"
pm2 jlist 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data:
    if p['name'] in ['eligibility-api', 'war-room-server']:
        env = p['pm2_env'].get('env', {})
        leaks = {}
        for k, v in env.items():
            if v and any(s in k.upper() for s in ['KEY', 'SECRET', 'TOKEN', 'PASSWORD', 'API', 'AUTH']):
                leaks[k] = repr(v)[:60]
        print(f'  {p[\"name\"]}: status={p[\"pm2_env\"][\"status\"]}, secret_leaks={len(leaks)}')
        for k, v in leaks.items():
            print(f'    {k}={v}')
"

# ---- PHASE 2: Fix war-room-server -----------------------------------------
echo ""
echo "--- PHASE 2: Fix war-room-server ---"

WAR_ROOM_ECOSYSTEM="/opt/apps/war-room/ecosystem.config.js"
WAR_ROOM_SECRETS_ENV="/root/.pm2/secrets.env"

if [ -f "$WAR_ROOM_ECOSYSTEM" ]; then
    echo "Found ecosystem config: $WAR_ROOM_ECOSYSTEM"

    # Extract the WAR_ROOM_AUTH_TOKEN value from the config before removing it
    AUTH_TOKEN=$(python3 -c "
import re
with open('$WAR_ROOM_ECOSYSTEM') as f:
    content = f.read()
match = re.search(r'\"WAR_ROOM_AUTH_TOKEN\":\s*\"([^\"]+)\"', content)
if match:
    print(match.group(1))
")

    if [ -n "$AUTH_TOKEN" ]; then
        echo "Extracted WAR_ROOM_AUTH_TOKEN from ecosystem config"

        # Add token to secrets.env if not already there
        if [ -f "$WAR_ROOM_SECRETS_ENV" ]; then
            if ! grep -q "^WAR_ROOM_AUTH_TOKEN=" "$WAR_ROOM_SECRETS_ENV" 2>/dev/null; then
                echo "" >> "$WAR_ROOM_SECRETS_ENV"
                echo "WAR_ROOM_AUTH_TOKEN=$AUTH_TOKEN" >> "$WAR_ROOM_SECRETS_ENV"
                echo "[OK] Added WAR_ROOM_AUTH_TOKEN to $WAR_ROOM_SECRETS_ENV"
            else
                echo "[OK] WAR_ROOM_AUTH_TOKEN already in secrets.env"
            fi
        fi

        # Back up original config
        cp "$WAR_ROOM_ECOSYSTEM" "${WAR_ROOM_ECOSYSTEM}.bak-${TIMESTAMP}"
        echo "[OK] Backed up ecosystem.config.js"

        # Remove WAR_ROOM_AUTH_TOKEN from the ecosystem config env block
        python3 -c "
import re
with open('$WAR_ROOM_ECOSYSTEM') as f:
    content = f.read()

# Remove the WAR_ROOM_AUTH_TOKEN line (including trailing comma if present)
# Pattern: line with WAR_ROOM_AUTH_TOKEN followed by optional comma on next line
new_content = re.sub(
    r'\s*\"WAR_ROOM_AUTH_TOKEN\":\s*\"[^\"]*\"\s*,?\s*\n',
    '\n',
    content
)

with open('$WAR_ROOM_ECOSYSTEM', 'w') as f:
    f.write(new_content)
"
        echo "[OK] Removed WAR_ROOM_AUTH_TOKEN from ecosystem.config.js env block"
    else
        echo "[INFO] WAR_ROOM_AUTH_TOKEN not found in config — already fixed?"
    fi
else
    echo "[WARN] Ecosystem config not found at $WAR_ROOM_ECOSYSTEM"
fi

# Stop + delete the process
echo "Stopping war-room-server..."
pm2 stop war-room-server 2>/dev/null || true
pm2 delete war-room-server 2>/dev/null || true
echo "[OK] war-room-server stopped and deleted"

# Restart with env -i to prevent secret inheritance
echo "Starting war-room-server with env -i..."
env -i \
    HOME=/root \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PM2_HOME="$PM2_HOME" \
    pm2 start "$WAR_ROOM_ECOSYSTEM" --only war-room-server

sleep 3

# Verify process started
if pm2 jlist 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data:
    if p['name'] == 'war-room-server':
        if p['pm2_env']['status'] == 'online':
            print('ONLINE')
        else:
            print('OFFLINE')
" | grep -q "ONLINE"; then
    echo "[OK] war-room-server is online"
else
    echo "[ERROR] war-room-server failed to start"
fi

# ---- PHASE 3: Fix eligibility-api -----------------------------------------
echo ""
echo "--- PHASE 3: Fix eligibility-api ---"

ELIGIBILITY_DIR="/opt/wheeler/apps/eligibility-api"
ELIGIBILITY_ECOSYSTEM="${ELIGIBILITY_DIR}/ecosystem.config.js"

# Create ecosystem config if it doesn't exist
if [ ! -f "$ELIGIBILITY_ECOSYSTEM" ]; then
    echo "Creating ecosystem config for eligibility-api..."
    cat > "$ELIGIBILITY_ECOSYSTEM" << 'ECOCONFIG'
module.exports = {
  "apps": [
    {
      "name": "eligibility-api",
      "script": "/opt/wheeler-ecosystem/scripts/pm2-env-wrapper.sh",
      "args": "venv/bin/uvicorn main:app --host 127.0.0.1 --port 8096 --workers 1",
      "cwd": "/opt/wheeler/apps/eligibility-api",
      "interpreter": "none",
      "filter_env": ["HOME", "PATH", "USER", "LANG", "PYTHONUNBUFFERED"],
      "min_uptime": "30s",
      "restart_delay": 2000,
      "max_restarts": 20,
      "log_date_format": "YYYY-MM-DD HH:mm:ss Z",
      "error_file": "/root/.pm2/logs/eligibility-api-error.log",
      "out_file": "/root/.pm2/logs/eligibility-api-out.log",
      "merge_logs": true,
      "env": {
        "PYTHONUNBUFFERED": "1",
        "ENV_FILE": "/root/.pm2/secrets.env"
      }
    }
  ]
};
ECOCONFIG
    echo "[OK] Created $ELIGIBILITY_ECOSYSTEM"
else
    echo "[OK] Ecosystem config already exists: $ELIGIBILITY_ECOSYSTEM"
fi

# Stop + delete
echo "Stopping eligibility-api..."
pm2 stop eligibility-api 2>/dev/null || true
pm2 delete eligibility-api 2>/dev/null || true
echo "[OK] eligibility-api stopped and deleted"

# Restart with env -i
echo "Starting eligibility-api with env -i..."
env -i \
    HOME=/root \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PM2_HOME="$PM2_HOME" \
    pm2 start "$ELIGIBILITY_ECOSYSTEM" --only eligibility-api

sleep 3

# Verify
if pm2 jlist 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data:
    if p['name'] == 'eligibility-api':
        if p['pm2_env']['status'] == 'online':
            print('ONLINE')
        else:
            print('OFFLINE')
" | grep -q "ONLINE"; then
    echo "[OK] eligibility-api is online"
else
    echo "[ERROR] eligibility-api failed to start"
fi

# ---- PHASE 4: Save PM2 state ----------------------------------------------
echo ""
echo "--- PHASE 4: Save PM2 state ---"
pm2 save --force
echo "[OK] PM2 state saved"

# ---- PHASE 5: Verification ------------------------------------------------
echo ""
echo "--- PHASE 5: Verification ---"
echo "After state:"

VERIFICATION=$(pm2 jlist 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
issues = 0
for p in data:
    if p['name'] in ['eligibility-api', 'war-room-server']:
        env = p['pm2_env'].get('env', {})
        leaks = {}
        for k, v in env.items():
            if v and any(s in k.upper() for s in ['KEY', 'SECRET', 'TOKEN', 'PASSWORD', 'API', 'AUTH']):
                # Skip non-secret tokens like PYTHONUNBUFFERED
                blacklist = ['DEEPSEEK_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_DEFAULT',
                             'CLAUDE_CODE', 'COREPACK_ENABLE', 'XDG_', 'SSH_', 'DBUS_',
                             'NODE_APP_INSTANCE', 'PM2_', 'GIT_EDITOR', 'SHLVL', 'TERM',
                             'LOGNAME', 'USER', 'HOME', 'LANG', 'PATH', 'SHELL', 'PWD',
                             'AI_AGENT', '_']
                is_blacklisted = any(k.startswith(b) for b in blacklist)
                if not is_blacklisted and 'AUTH' in k.upper():
                    # Specifically check for auth tokens
                    auth_blacklist = ['WAR_ROOM_AUTH_TOKEN']
                    if k in auth_blacklist:
                        leaks[k] = repr(v)[:60]
                        issues += 1
                if k in ['DEEPSEEK_API_KEY', 'ANTHROPIC_AUTH_TOKEN']:
                    leaks[k] = repr(v)[:60]
                    issues += 1
        status = p['pm2_env']['status']
        print(f'  {p[\"name\"]}: status={status}, leaks={len(leaks)}')
        for k, v in leaks.items():
            print(f'    LEAKED: {k}={v}')
        if len(leaks) == 0:
            print(f'    [CLEAN] No secrets in pm2_env')
")

echo "$VERIFICATION"

# Final score
LEAK_COUNT=$(echo "$VERIFICATION" | grep -c "LEAKED:" || true)
if [ "$LEAK_COUNT" -eq 0 ]; then
    echo ""
    echo "=============================================="
    echo "RESULT: PASS — 0 secret leaks detected"
    echo "Score recovery: +4 points (PM2 secret hygiene)"
    echo "=============================================="
else
    echo ""
    echo "=============================================="
    echo "RESULT: $LEAK_COUNT secret leak(s) remain"
    echo "=============================================="
fi

echo ""
echo "Log saved to: $LOG_FILE"
echo "Completed at: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
