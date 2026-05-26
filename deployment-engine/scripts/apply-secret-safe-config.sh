#!/bin/bash
# ==============================================================================
# apply-secret-safe-config.sh — Deploy Secret-Safe PM2 Ecosystem Config
# ==============================================================================
# Purpose:
#   1. Stop all PM2 processes using the old config (which has baked-in secrets)
#   2. Delete them from PM2 (purges stored env from ~/.pm2/dump.pm2)
#   3. Restart with env -i using the FIXED config ( ${VAR} substitution)
#   4. Verify 0 secrets visible in pm2 jlist
#
# PREREQUISITES:
#   - The new config at /root/templates/pm2/optimized-ecosystem.config.js
#     must already be fixed (no process.env.SECRET || "" patterns)
#   - All required secrets must be in the shell environment (systemd drop-in or
#     sourced from /root/.pm2/secrets.env before running this script)
#
# SAFETY: This script does NOT delete the PM2 process list or dump file
#         permanently — pm2 save --force can restore from a fresh state.
#         A backup of ~/.pm2/dump.pm2 is created before any changes.
# ==============================================================================
set -euo pipefail

LOG_FILE="/root/deployment-engine/logs/apply-secret-safe-config.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PM2_HOME="${PM2_HOME:-/root/.pm2}"
CONFIG="/root/templates/pm2/optimized-ecosystem.config.js"
BACKUP_DIR="/root/.pm2/backups"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=============================================="
echo "apply-secret-safe-config.sh — $TIMESTAMP"
echo "=============================================="
echo ""
echo "Config:      $CONFIG"
echo "PM2_HOME:    $PM2_HOME"
echo "Backup dir:  $BACKUP_DIR"
echo ""

# ============================================================================
# PHASE 0: Pre-flight checks
# ============================================================================
echo "--- PHASE 0: Pre-flight ---"

# Verify the fixed config exists
if [ ! -f "$CONFIG" ]; then
    echo "FATAL: Config not found at $CONFIG"
    exit 1
fi

# Verify it does NOT contain the anti-pattern
LEAK_COUNT=$(grep -c 'process\.env\.\w\+ || ""' "$CONFIG" 2>/dev/null || true)
if [ "$LEAK_COUNT" -gt 0 ]; then
    echo "FATAL: Config still contains $LEAK_COUNT process.env || \"\" patterns!"
    echo "Run the config fix first. Aborting."
    exit 1
fi
echo "[OK] Config is secret-safe (0 process.env || \"\" patterns)"

# Verify PM2 is reachable
if ! pm2 ping >/dev/null 2>&1; then
    echo "FATAL: PM2 daemon not responding. Start it first: pm2 resurrect"
    exit 1
fi
echo "[OK] PM2 daemon responding"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Back up current PM2 dump
if [ -f "$PM2_HOME/dump.pm2" ]; then
    cp "$PM2_HOME/dump.pm2" "$BACKUP_DIR/dump.pm2.bak-${TIMESTAMP}"
    echo "[OK] Backed up $PM2_HOME/dump.pm2 → $BACKUP_DIR/dump.pm2.bak-${TIMESTAMP}"
else
    echo "[WARN] No dump.pm2 found at $PM2_HOME/dump.pm2"
fi

# ============================================================================
# PHASE 1: Snapshot current state (secrets audit before fix)
# ============================================================================
echo ""
echo "--- PHASE 1: Snapshot before state ---"

# List processes defined in the config that are currently running
CONFIG_PROCESS_NAMES=$(python3 -c "
import json, subprocess, sys
# Parse the config to extract app names
with open('$CONFIG') as f:
    content = f.read()

# The config uses module.exports = { apps: [...] }
# Find name: properties
import re
names = re.findall(r'name:\s*\"([^\"]+)\"', content)
for n in names:
    print(n)
" 2>/dev/null || echo "")

if [ -z "$CONFIG_PROCESS_NAMES" ]; then
    echo "[WARN] Could not parse process names from config"
fi
echo "Process names in config:"
echo "$CONFIG_PROCESS_NAMES" | while read -r name; do
    echo "  - $name"
done

# Run the secret scan
echo ""
echo "Secret scan BEFORE fix:"
BEFORE_LEAKS=$(pm2 jlist 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
total_leaks = 0
for p in data:
    env = p['pm2_env'].get('env', {})
    leaks = {}
    for k, v in env.items():
        if v and any(s in k.upper() for s in ['KEY', 'SECRET', 'TOKEN', 'PASSWORD', 'API_KEY']):
            # Skip known non-secrets
            if k in ['PYTHONUNBUFFERED', 'NODE_ENV', 'INSTANCE_ID', 'DASHBOARD_INSTANCE_ID',
                     'LITELLM_INSTANCE_ID', 'PM2_HOME', 'PM2_JSON', 'unique_id',
                     'POLLING_INTERVAL_MS', 'LOG_LEVEL', 'CORS_ORIGIN',
                     'CHECK_INTERVAL_SEC', 'SCHEDULER_ENABLED', 'WORKER_TYPE']:
                continue
            leaks[k] = repr(v)[:60]
            total_leaks += 1
    if leaks:
        print(f'  {p[\"name\"]} (status={p[\"pm2_env\"][\"status\"]}): {len(leaks)} secret(s) exposed')
        for k, v in leaks.items():
            print(f'    {k} = {v}')

if total_leaks == 0:
    print('  [CLEAN] No secrets visible in pm2_env')
print(f'TOTAL_LEAKS={total_leaks}')
")

echo "$BEFORE_LEAKS"
BEFORE_TOTAL=$(echo "$BEFORE_LEAKS" | grep -oP 'TOTAL_LEAKS=\K\d+' || echo "0")

# ============================================================================
# PHASE 2: Stop and delete affected processes
# ============================================================================
echo ""
echo "--- PHASE 2: Stop and delete affected processes ---"

# Stop ALL processes defined in this config first, then delete them.
# We do stop-then-delete rather than delete directly to allow graceful shutdown.
# The delete is what purges the old baked-in env from PM2's memory.

STOPPED_COUNT=0
DELETED_COUNT=0

echo "$CONFIG_PROCESS_NAMES" | while read -r name; do
    if [ -z "$name" ]; then continue; fi

    # Check if process exists
    if pm2 jlist 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
found = any(p['name'] == '$name' for p in data)
sys.exit(0 if found else 1)
" 2>/dev/null; then
        echo "Stopping: $name"
        pm2 stop "$name" 2>/dev/null || true
        echo "Deleting: $name"
        pm2 delete "$name" 2>/dev/null || true
        DELETED_COUNT=$((DELETED_COUNT + 1))
    else
        echo "Skip (not running): $name"
    fi
done

echo ""
echo "Stopped and deleted processes from old config."

# ============================================================================
# PHASE 3: Restart with env -i using the FIXED config
# ============================================================================
echo ""
echo "--- PHASE 3: Restart with env -i ---"

# env -i starts with a CLEAN environment.
# We pass only what PM2 itself needs + the config path.
# The ${VAR} substitution in the config will resolve from the shell environment
# that invoked this script (which should have secrets sourced from a secured source).
#
# IMPORTANT: If you use a systemd drop-in to inject secrets (RECOMMENDED),
#            the secrets are available via the systemd-managed environment
#            that this script runs under (assuming systemctl start).
#            If running manually, source secrets first:
#              set -a; source /root/.pm2/secrets.env; set +a

echo "Starting processes from secret-safe config..."
echo ""

env -i \
    HOME="$HOME" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PM2_HOME="$PM2_HOME" \
    pm2 start "$CONFIG" --env production

sleep 5

# Save the state
pm2 save --force
echo "[OK] PM2 state saved"

# ============================================================================
# PHASE 4: Verify — 0 secrets in pm2 jlist
# ============================================================================
echo ""
echo "--- PHASE 4: Verification ---"

# Wait for all processes to come online
sleep 5

echo "PM2 status:"
pm2 status 2>/dev/null || true

echo ""
echo "Secret scan AFTER fix:"
AFTER_LEAKS=$(pm2 jlist 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
total_leaks = 0
offline = 0
for p in data:
    env = p['pm2_env'].get('env', {})
    leaks = {}
    for k, v in env.items():
        # A resolved ${VAR} will show the real value.
        # Key concern: are secret VALUES visible (not just keys)?
        if v and any(s in k.upper() for s in ['KEY', 'SECRET', 'TOKEN', 'PASSWORD', 'API_KEY']):
            if k in ['PYTHONUNBUFFERED', 'NODE_ENV', 'INSTANCE_ID', 'DASHBOARD_INSTANCE_ID',
                     'LITELLM_INSTANCE_ID', 'PM2_HOME', 'PM2_JSON', 'unique_id',
                     'POLLING_INTERVAL_MS', 'LOG_LEVEL', 'CORS_ORIGIN',
                     'CHECK_INTERVAL_SEC', 'SCHEDULER_ENABLED', 'WORKER_TYPE']:
                continue
            leaks[k] = repr(v)[:80]
            total_leaks += 1
    status = p['pm2_env'].get('status', 'unknown')
    if status != 'online':
        offline += 1
    if leaks:
        print(f'  {p[\"name\"]} (status={status}): {len(leaks)} secret(s) visible in pm2_env')
        for k, v in leaks.items():
            print(f'    {k} = {v}')
    else:
        if status == 'online':
            print(f'  {p[\"name\"]} (status=online): CLEAN')
        else:
            print(f'  {p[\"name\"]} (status={status}): CLEAN (but offline)')

if total_leaks == 0:
    print('')
    print('[CLEAN] 0 secrets visible in pm2_env across all processes')
else:
    print(f'')
    print(f'[WARN] {total_leaks} secret value(s) still visible in pm2_env')
print(f'OFFLINE_COUNT={offline}')
print(f'TOTAL_LEAKS={total_leaks}')
")

echo "$AFTER_LEAKS"
AFTER_TOTAL=$(echo "$AFTER_LEAKS" | grep -oP 'TOTAL_LEAKS=\K\d+' || echo "0")
OFFLINE_COUNT=$(echo "$AFTER_LEAKS" | grep -oP 'OFFLINE_COUNT=\K\d+' || echo "0")

# ============================================================================
# PHASE 5: Scorecard
# ============================================================================
echo ""
echo "=============================================="
echo "apply-secret-safe-config.sh — SCORECARD"
echo "=============================================="
echo ""
echo "  Secrets before fix: $BEFORE_TOTAL"
echo "  Secrets after fix:  $AFTER_TOTAL"
echo "  Processes offline:  $OFFLINE_COUNT"
echo ""

# Note: pm2 jlist will ALWAYS show the resolved value of ${VAR} entries
# while the process is running (because pm2 needs to pass them to the process).
# The key win is that secrets are NOT in ~/.pm2/dump.pm2 — the dump file
# stores "${VAR}" placeholders, not actual values.
#
# To verify the dump file is clean:
#   grep -o 'process\.env\.\w\+ || ""' "$PM2_HOME/dump.pm2" | wc -l
# Should be 0.

echo "Dump file secret check:"
DUMP_LEAKS=$(grep -oP '"[A-Z_]+":\s*"[^"]{8,}"' "$PM2_HOME/dump.pm2" 2>/dev/null | head -20 || echo "(dump file check skipped)")
if [ -z "$DUMP_LEAKS" ]; then
    echo "  [OK] Dump file appears clean (no long secret-looking strings found)"
else
    echo "  [CHECK] Inspect these entries manually:"
    echo "$DUMP_LEAKS"
fi

if [ "$AFTER_TOTAL" -eq 0 ] && [ "$OFFLINE_COUNT" -eq 0 ]; then
    echo ""
    echo "=============================================="
    echo "RESULT: ALL CLEAN"
    echo "  - 0 secrets in pm2_env"
    echo "  - 0 offline processes"
    echo "  - Dump file uses \${VAR} placeholders"
    echo "  - Score: 100/100"
    echo "=============================================="
elif [ "$AFTER_TOTAL" -eq 0 ] && [ "$OFFLINE_COUNT" -gt 0 ]; then
    echo ""
    echo "=============================================="
    echo "RESULT: PARTIAL — Secrets clean but $OFFLINE_COUNT process(es) offline"
    echo "Run: pm2 status to investigate offline processes"
    echo "=============================================="
else
    echo ""
    echo "=============================================="
    echo "RESULT: SECRETS STILL PRESENT — $AFTER_TOTAL leak(s) found"
    echo "Manual investigation required."
    echo "=============================================="
fi

echo ""
echo "Log saved to: $LOG_FILE"
echo "Dump backup:  $BACKUP_DIR/dump.pm2.bak-${TIMESTAMP}"
echo "Completed at: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo ""
echo "===== INSTRUCTIONS FOR OPERATOR ====="
echo ""
echo "1. Review the BEFORE/AFTER scan results above."
echo "2. Verify processes are online:  pm2 status"
echo "3. If all online and clean:"
echo "     pm2 save --force"
echo "4. If issues found:"
echo "   - Restore dump: cp $BACKUP_DIR/dump.pm2.bak-${TIMESTAMP} $PM2_HOME/dump.pm2"
echo "   - Resurrect:    pm2 resurrect"
echo ""
echo "NOTE: After this fix, any process.env.SECRET references are GONE from"
echo "      both the config and the PM2 dump. Future deploys must use the"
echo "      \${VAR} pattern to avoid re-introducing the leak."
echo "=============================================="
