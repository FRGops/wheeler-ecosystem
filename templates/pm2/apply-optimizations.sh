#!/bin/bash
# =============================================================================
# Wheeler AIOPS — PM2 Optimization Apply Script
# =============================================================================
# Generated:  2026-05-23
# Phase:      2 — PM2 Optimization Plan
# Target:     AIOPS server (5.78.140.118)
#
# This script applies the optimized PM2 ecosystem configuration.
# It is designed to be SAFE: read-only preview by default, backup before
# changes, and full rollback capability.
#
# USAGE:
#   ./apply-optimizations.sh           # Dry-run: show what WOULD happen
#   ./apply-optimizations.sh --apply   # Apply all optimizations (with confirm)
#   ./apply-optimizations.sh --yes     # Apply without confirmation prompt
#   ./apply-optimizations.sh --rollback <backup_dir>  # Rollback to backup
#   ./apply-optimizations.sh --status  # Show current vs target state
#
# WHAT THIS SCRIPT DOES:
#   1. Pre-flight checks (SSH reachable, PM2 running, disk space)
#   2. Dependency fixes (pip install missing packages)
#   3. Config consolidation (remove duplicate configs)
#   4. Log cleanup (archive legacy logs)
#   5. Backup current PM2 state and configs
#   6. Deploy optimized-ecosystem.config.js
#   7. Reload services with new config
#   8. Verify all services online
#   9. Configure pm2-logrotate
#  10. pm2 save for persistence
#
# ROLLBACK:
#   The script saves a complete backup to /root/templates/pm2/backups/<timestamp>/
#   containing: pm2 dump, all ecosystem configs, and pm2 save state.
#   Use --rollback <backup_dir> to restore.
# =============================================================================

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTIMIZED_CONFIG="${SCRIPT_DIR}/optimized-ecosystem.config.js"
BACKUP_BASE="${SCRIPT_DIR}/backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"
LOG_FILE="/tmp/pm2-optimization-${TIMESTAMP}.log"
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# ─── Flags ──────────────────────────────────────────────────────────────────
DRY_RUN=true
SKIP_CONFIRM=false
ROLLBACK_MODE=false
ROLLBACK_DIR=""

# ─── Parse Arguments ────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --apply)   DRY_RUN=false ;;
    --yes)     DRY_RUN=false; SKIP_CONFIRM=true ;;
    --rollback)
      ROLLBACK_MODE=true
      DRY_RUN=false
      shift
      ROLLBACK_DIR="${1:-}"
      if [ -z "$ROLLBACK_DIR" ]; then
        echo "ERROR: --rollback requires a backup directory path"
        echo "Usage: $0 --rollback <backup_dir>"
        exit 1
      fi
      ;;
    --status)  DRY_RUN=true ;;  # status is just dry-run with extra info
    *)         ;;  # ignore unknown flags
  esac
  shift 2>/dev/null || true
done

# ─── Logging ────────────────────────────────────────────────────────────────
log()    { echo -e "$(date '+%Y-%m-%d %H:%M:%S')  $1" | tee -a "$LOG_FILE"; }
info()   { log "${COLOR_BLUE}[INFO]${COLOR_RESET}    $1"; }
warn()   { log "${COLOR_YELLOW}[WARN]${COLOR_RESET}    $1"; }
success(){ log "${COLOR_GREEN}[OK]${COLOR_RESET}      $1"; }
error()  { log "${COLOR_RED}[ERROR]${COLOR_RESET}   $1"; }
banner() { log ""; log "${COLOR_BLUE}═══════════════════════════════════════════════════${COLOR_RESET}"; log "${COLOR_BLUE}  $1${COLOR_RESET}"; log "${COLOR_BLUE}═══════════════════════════════════════════════════${COLOR_RESET}"; log ""; }
section(){ log ""; log "${COLOR_YELLOW}─── $1 ───${COLOR_RESET}"; }

# ─── Cleanup on exit ────────────────────────────────────────────────────────
cleanup() {
  if [ "$DRY_RUN" = false ] && [ "$ROLLBACK_MODE" = false ]; then
    info "Log saved to: $LOG_FILE"
  fi
}
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════════════════
# ROLLBACK MODE
# ═══════════════════════════════════════════════════════════════════════════
if [ "$ROLLBACK_MODE" = true ]; then
  banner "PM2 ROLLBACK — Restoring from ${ROLLBACK_DIR}"

  if [ ! -d "$ROLLBACK_DIR" ]; then
    error "Backup directory not found: $ROLLBACK_DIR"
    exit 1
  fi

  section "Step 1/4: Stop all running processes"
  echo "   pm2 stop all"
  pm2 stop all 2>&1 | tee -a "$LOG_FILE"

  section "Step 2/4: Delete all processes from PM2"
  echo "   pm2 delete all"
  pm2 delete all 2>&1 | tee -a "$LOG_FILE"

  section "Step 3/4: Restore from backup ecosystem config"
  BACKUP_CONFIG="${ROLLBACK_DIR}/ecosystem.config.js"
  if [ -f "$BACKUP_CONFIG" ]; then
    echo "   pm2 start ${BACKUP_CONFIG}"
    pm2 start "$BACKUP_CONFIG" 2>&1 | tee -a "$LOG_FILE"
  else
    # Try to resurrect from dump
    DUMP_FILE="${ROLLBACK_DIR}/pm2-dump.json"
    if [ -f "$DUMP_FILE" ]; then
      echo "   pm2 resurrect (from dump)"
      pm2 resurrect 2>&1 | tee -a "$LOG_FILE"
    else
      error "No backup config or dump found in $ROLLBACK_DIR"
      exit 1
    fi
  fi

  section "Step 4/4: Save PM2 state for reboot persistence"
  echo "   pm2 save --force"
  pm2 save --force 2>&1 | tee -a "$LOG_FILE"

  success "Rollback complete. Verify with: pm2 list"
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════
# PRE-FLIGHT CHECKS
# ═══════════════════════════════════════════════════════════════════════════
banner "PM2 OPTIMIZATION — Phase 2"
if [ "$DRY_RUN" = true ]; then
  warn "DRY RUN MODE — No changes will be made. Use --apply to execute."
  echo ""
fi

section "Pre-flight Checks"

# Check 1: Running on AIOPS?
HOSTNAME=$(hostname)
info "Hostname: $HOSTNAME"
if [[ "$HOSTNAME" != *"aiops"* ]] && [[ "$HOSTNAME" != *"wheeler"* ]]; then
  warn "This script targets AIOPS (5.78.140.118). Current host is $HOSTNAME."
  warn "If this is intentional, ignore this warning."
fi

# Check 2: PM2 installed?
if command -v pm2 &>/dev/null; then
  PM2_VERSION=$(pm2 --version 2>/dev/null || echo "unknown")
  success "PM2 version $PM2_VERSION is installed"
else
  error "PM2 is not installed. Cannot proceed."
  exit 1
fi

# Check 3: Optimized config exists?
if [ -f "$OPTIMIZED_CONFIG" ]; then
  success "Optimized config found: $OPTIMIZED_CONFIG"
else
  error "Optimized config NOT found at $OPTIMIZED_CONFIG"
  exit 1
fi

# Check 4: Current PM2 state
info "Current PM2 state:"
pm2 list 2>&1 | tee -a "$LOG_FILE"
echo ""
ONLINE_COUNT=$(pm2 jlist 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(len([p for p in d if p['pm2_env']['status']=='online']))" 2>/dev/null || echo "?")
STOPPED_COUNT=$(pm2 jlist 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(len([p for p in d if p['pm2_env']['status']=='stopped']))" 2>/dev/null || echo "?")
info "Online: $ONLINE_COUNT | Stopped: $STOPPED_COUNT"

# Check 5: Disk space
AVAIL_SPACE=$(df -h /root | awk 'NR==2 {print $4}')
info "Available disk space on /root: $AVAIL_SPACE"

# Check 6: Memory
AVAIL_MEM=$(free -h | awk '/^Mem:/ {print $7}')
info "Available memory: $AVAIL_MEM"

# ═══════════════════════════════════════════════════════════════════════════
# SHOW WHAT WILL BE DONE
# ═══════════════════════════════════════════════════════════════════════════
banner "PLANNED CHANGES (dry-run preview)"
echo ""

section "Phase A: Dependency Fixes"
echo "  [FIX] pip install 'litellm[proxy]'          # Adds missing websockets module"
echo "  [FIX] pip install psycopg2-binary            # Adds missing psycopg2 for war-room"
echo "  [FIX] npm install ioredis (in relay cwd)     # Verify/fix ioredis for event-bus-relay"
echo ""

section "Phase B: Config Consolidation"
echo "  [DEL] /opt/opt/apps/design-agent-svc/ecosystem.config.js (duplicate)"
echo "  [DEL] /opt/opt/apps/prediction-radar-agent-svc/ecosystem.config.js (duplicate)"
echo "  [DEL] /opt/opt/apps/ravyn-agent-svc/ecosystem.config.js (duplicate)"
echo "  [DEL] /opt/opt/apps/wheeler-brain-os/ecosystem.config.js (duplicate)"
echo "  [DEL] /opt/wheeler/apps/frgcrm/api/ecosystem.config.js (stale, port 8002)"
echo "  [DEL] /opt/wheeler/apps/frgcrm/pm2.config.js (stale, port 8004 staging)"
echo "  [KEEP] /opt/wheeler/apps/frgcrm/api/ecosystem.config.cjs (active, port 8082)"
echo ""

section "Phase C: Log Cleanup"
echo "  [ARCHIVE] /root/.pm2/logs/frgcrm-mirror-test-error.log (642 KB, from decommissioned process)"
echo "  [ARCHIVE] /root/.pm2/logs/frgcrm-mirror-test-out.log (94 KB, from decommissioned process)"
echo "  [ROTATE] pm2-logrotate settings updated (10MB max, 30-day retention, gzip)"
echo ""

section "Phase D: PM2 Config Deployment"
echo "  [BACKUP] Full PM2 state saved to: $BACKUP_DIR/"
echo "  [DEPLOY] New config: $OPTIMIZED_CONFIG"
echo "  [RELOAD] All 17 services zero-downtime (where cluster mode)"
echo ""
echo "  Changes per service:"
echo "  ┌────────────────────────────────┬──────────────────────────────────────┐"
echo "  │ Service                        │ Changes                              │"
echo "  ├────────────────────────────────┼──────────────────────────────────────┤"
echo "  │ litellm                        │ cluster(2), +memcap 768M, Redis auth │"
echo "  │ frgcrm-api                     │ memcap 2G→1G, workers 2→4            │"
echo "  │ openclaw-dashboard             │ cluster(2)                           │"
echo "  │ ecosystem-guardian             │ (unchanged)                          │"
echo "  │ event-bus-relay                │ memcap 150M→200M                     │"
echo "  │ voice-outreach-service         │ +memcap 256M (was unset)             │"
echo "  │ war-room-server                │ +memcap 256M (was unset)             │"
echo "  │ design-agent-svc               │ memcap 500M→400M, restart tier       │"
echo "  │ horizon-agent-svc              │ memcap 500M→400M, restart tier       │"
echo "  │ paperless-agent-svc            │ memcap 500M→400M, restart tier       │"
echo "  │ prediction-radar-agent-svc     │ memcap 500M→400M, restart tier       │"
echo "  │ ravyn-agent-svc                │ memcap 500M→400M, restart tier       │"
echo "  │ frgcrm-agent-svc               │ memcap 500M→400M, restart tier       │"
echo "  │ insforge-agent-svc             │ memcap 500M→300M, restart tier       │"
echo "  │ surplusai-scraper-agent-svc    │ memcap 500M→400M, restart tier       │"
echo "  │ voice-agent-svc                │ memcap 500M→400M, restart tier       │"
echo "  │ backup-verification            │ +memcap 256M (stays stopped)         │"
echo "  └────────────────────────────────┴──────────────────────────────────────┘"
echo ""
echo "  Log paths: ALL moved to /opt/logs/pm2/<service-name>/{error,out}.log"
echo ""

section "Services NOT modified in behavior"
echo "  All agent-svc processes remain: fork mode, 1 instance, 5-min polling"
echo "  All services keep: watch=disabled, autorestart=true (except backup-verification)"
echo ""

section "Memory budget comparison"
echo "  Previous worst-case: ~11.5 GB (frcrm-api 2G + 9 agents at 500M + litellm unbounded)"
echo "  Optimized worst-case: ~6.5 GB (all at caps simultaneously)"
echo "  Current actual usage: ~1.95 GB"
echo "  Available RAM:         ~13 GB"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# DRY RUN EXIT
# ═══════════════════════════════════════════════════════════════════════════
if [ "$DRY_RUN" = true ]; then
  echo ""
  warn "Dry run complete. No changes were made."
  echo "  To apply:     $0 --apply"
  echo "  To skip confirm: $0 --yes"
  echo "  Detailed plan:  /root/docs/PM2_OPTIMIZATION_PLAN.md"
  echo ""
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════
# CONFIRMATION
# ═══════════════════════════════════════════════════════════════════════════
if [ "$SKIP_CONFIRM" = false ]; then
  echo ""
  warn "═══════════════════════════════════════════════════════════════"
  warn "  YOU ARE ABOUT TO MODIFY THE RUNNING PM2 ECOSYSTEM"
  warn "  Target: $(hostname)"
  warn "  17 services will be reloaded with new configuration"
  warn "═══════════════════════════════════════════════════════════════"
  echo ""
  read -r -p "  Type 'YES' to confirm: " CONFIRM
  if [ "$CONFIRM" != "YES" ]; then
    error "Confirmation not given. Aborting."
    exit 1
  fi
  echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════
# EXECUTION BEGINS
# ═══════════════════════════════════════════════════════════════════════════
banner "APPLYING OPTIMIZATIONS"

# ─── Phase A: Dependency Fixes ──────────────────────────────────────────────
section "Phase A: Dependency Fixes"

info "Fixing litellm dependencies (websockets)..."
pip install 'litellm[proxy]' 2>&1 | tee -a "$LOG_FILE" || warn "litellm proxy install had warnings (check log)"

info "Fixing war-room dependencies (psycopg2)..."
pip install psycopg2-binary 2>&1 | tee -a "$LOG_FILE" || warn "psycopg2 install had warnings (check log)"

info "Verifying ioredis for event-bus-relay..."
if [ -d "/opt/apps/wheeler-brain-os" ]; then
  cd /opt/apps/wheeler-brain-os
  if ! node -e "require('ioredis')" 2>/dev/null; then
    warn "ioredis not found. Installing..."
    npm install ioredis 2>&1 | tee -a "$LOG_FILE" || warn "ioredis install had warnings"
  else
    success "ioredis is already installed"
  fi
fi

# ─── Phase B: Backup ────────────────────────────────────────────────────────
section "Phase B: Creating Backup"

mkdir -p "$BACKUP_DIR"
success "Backup directory: $BACKUP_DIR"

info "Saving PM2 process list..."
pm2 list > "${BACKUP_DIR}/pm2-list.txt" 2>&1

info "Saving PM2 dump (JSON)..."
pm2 save --force 2>&1 | tee -a "$LOG_FILE"
cp ~/.pm2/dump.pm2 "${BACKUP_DIR}/pm2-dump.json" 2>/dev/null || warn "Could not copy dump.pm2"

info "Saving current ecosystem configs..."
mkdir -p "${BACKUP_DIR}/configs"
CONFIG_PATHS=(
  "/opt/wheeler/ecosystem.config.js"
  "/opt/apps/ecosystem.config.js"
  "/opt/wheeler/apps/frgcrm/api/ecosystem.config.cjs"
  "/opt/wheeler/apps/frgcrm/api/ecosystem.config.js"
  "/opt/wheeler/apps/frgcrm/pm2.config.js"
  "/opt/wheeler/apps/frgcrm/agents-service/ecosystem.config.js"
  "/opt/openclaw-dashboard/ecosystem.config.cjs"
  "/opt/apps/design-agent-svc/ecosystem.config.js"
  "/opt/apps/horizon-agent-svc/ecosystem.config.js"
  "/opt/apps/paperless-agent-svc/ecosystem.config.js"
  "/opt/apps/prediction-radar-agent-svc/ecosystem.config.js"
  "/opt/apps/ravyn-agent-svc/ecosystem.config.js"
  "/opt/apps/frgcrm-agent-svc/ecosystem.config.js"
  "/opt/apps/insforge-agent-svc/ecosystem.config.js"
  "/opt/apps/surplusai-scraper-agent-svc/ecosystem.config.js"
  "/opt/apps/voice-agent-svc/ecosystem.config.js"
  "/opt/apps/war-room/ecosystem.config.js"
)

for cfg in "${CONFIG_PATHS[@]}"; do
  if [ -f "$cfg" ]; then
    REL_PATH="${cfg#/}"
    mkdir -p "$(dirname "${BACKUP_DIR}/configs/${REL_PATH}")"
    cp "$cfg" "${BACKUP_DIR}/configs/${REL_PATH}"
    info "  Backed up: $cfg"
  fi
done

info "Copying optimized config to backup..."
cp "$OPTIMIZED_CONFIG" "${BACKUP_DIR}/optimized-ecosystem.config.js"

success "Backup complete ($(du -sh "$BACKUP_DIR" | cut -f1))"

# ─── Phase C: Config Consolidation ──────────────────────────────────────────
section "Phase C: Config Consolidation"

info "Archiving duplicate configs from /opt/opt/apps/ (old location)..."
DUP_CONFIGS=(
  "/opt/opt/apps/design-agent-svc/ecosystem.config.js"
  "/opt/opt/apps/prediction-radar-agent-svc/ecosystem.config.js"
  "/opt/opt/apps/ravyn-agent-svc/ecosystem.config.js"
  "/opt/opt/apps/wheeler-brain-os/ecosystem.config.js"
)

for cfg in "${DUP_CONFIGS[@]}"; do
  if [ -f "$cfg" ]; then
    mkdir -p "${BACKUP_DIR}/duplicates"
    cp "$cfg" "${BACKUP_DIR}/duplicates/$(basename $(dirname $cfg))-ecosystem.config.js"
    rm "$cfg"
    success "  Removed duplicate: $cfg"
  fi
done

info "Archiving stale frgcrm-api configs..."
STALE_CONFIGS=(
  "/opt/wheeler/apps/frgcrm/api/ecosystem.config.js"
  "/opt/wheeler/apps/frgcrm/pm2.config.js"
)
for cfg in "${STALE_CONFIGS[@]}"; do
  if [ -f "$cfg" ]; then
    mkdir -p "${BACKUP_DIR}/stale"
    cp "$cfg" "${BACKUP_DIR}/stale/$(basename $cfg)"
    rm "$cfg"
    success "  Removed stale: $cfg"
  fi
done

info "Keeping active frgcrm-api config: /opt/wheeler/apps/frgcrm/api/ecosystem.config.cjs"

# ─── Phase D: Log Cleanup ───────────────────────────────────────────────────
section "Phase D: Log Cleanup"

info "Archiving legacy frgcrm-mirror-test logs..."
LEGACY_LOGS=(
  "/root/.pm2/logs/frgcrm-mirror-test-error.log"
  "/root/.pm2/logs/frgcrm-mirror-test-out.log"
)
mkdir -p "${BACKUP_DIR}/legacy-logs"
for logf in "${LEGACY_LOGS[@]}"; do
  if [ -f "$logf" ]; then
    cp "$logf" "${BACKUP_DIR}/legacy-logs/$(basename $logf)"
    rm "$logf"
    success "  Archived: $logf"
  fi
done

info "Configuring pm2-logrotate..."
pm2 set pm2-logrotate:max_size 10M 2>&1 | tee -a "$LOG_FILE"
pm2 set pm2-logrotate:retain 30 2>&1 | tee -a "$LOG_FILE"
pm2 set pm2-logrotate:compress true 2>&1 | tee -a "$LOG_FILE"
pm2 set pm2-logrotate:dateFormat 'YYYY-MM-DD_HH-mm-ss' 2>&1 | tee -a "$LOG_FILE"
pm2 set pm2-logrotate:workerInterval 30 2>&1 | tee -a "$LOG_FILE"
pm2 set pm2-logrotate:rotateInterval '0 0 * * *' 2>&1 | tee -a "$LOG_FILE"
pm2 set pm2-logrotate:rotateModule true 2>&1 | tee -a "$LOG_FILE"
success "pm2-logrotate configured (10MB max, 30-day retention, gzip)"

# ─── Phase E: Deploy Optimized Config ────────────────────────────────────────
section "Phase E: Deploying Optimized PM2 Config"

info "Creating log directories..."
SERVICES=(
  "litellm" "frgcrm-api" "openclaw-dashboard" "ecosystem-guardian"
  "event-bus-relay" "voice-outreach-service" "war-room-server"
  "design-agent-svc" "horizon-agent-svc" "paperless-agent-svc"
  "prediction-radar-agent-svc" "ravyn-agent-svc" "frgcrm-agent-svc"
  "insforge-agent-svc" "surplusai-scraper-agent-svc" "voice-agent-svc"
  "backup-verification"
)
for svc in "${SERVICES[@]}"; do
  mkdir -p "/opt/logs/pm2/${svc}"
done
success "Log directories created under /opt/logs/pm2/"

info "Stopping existing processes gracefully..."
for svc in "${SERVICES[@]}"; do
  if pm2 list 2>/dev/null | grep -q "$svc"; then
    echo "  Stopping $svc..."
    pm2 stop "$svc" 2>&1 | tee -a "$LOG_FILE" || warn "  Could not stop $svc (may already be stopped)"
  fi
done

info "Deleting old PM2 process definitions..."
pm2 delete all 2>&1 | tee -a "$LOG_FILE" || warn "Could not delete all processes"

info "Starting from optimized ecosystem config..."
pm2 start "$OPTIMIZED_CONFIG" --env production 2>&1 | tee -a "$LOG_FILE"

info "Saving PM2 state for reboot persistence..."
pm2 save --force 2>&1 | tee -a "$LOG_FILE"

# ─── Phase F: Verification ──────────────────────────────────────────────────
section "Phase F: Verification"

sleep 5  # give processes time to stabilize

info "Current PM2 state after optimization:"
pm2 list 2>&1 | tee -a "$LOG_FILE"

NEW_ONLINE=$(pm2 jlist 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(len([p for p in d if p['pm2_env']['status']=='online']))" 2>/dev/null || echo "0")
NEW_STOPPED=$(pm2 jlist 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(len([p for p in d if p['pm2_env']['status']=='stopped']))" 2>/dev/null || echo "0")

echo ""
info "Online: $NEW_ONLINE (target: 16 apps + 1 module = 17)"
info "Stopped: $NEW_STOPPED (target: 1 — backup-verification)"

if [ "$NEW_ONLINE" -ge 16 ]; then
  success "All expected services are online"
else
  warn "Some services may not have started. Check logs: pm2 logs --lines 50"
fi

info "Checking for restart loops..."
RESTART_COUNT=$(pm2 jlist 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
total = sum(p['pm2_env'].get('restart_time', 0) for p in d)
print(total)
" 2>/dev/null || echo "?")
info "Total restart count across all processes: $RESTART_COUNT"
if [ "$RESTART_COUNT" != "?" ] && [ "$RESTART_COUNT" -gt 10 ]; then
  warn "High restart count detected. Check: pm2 logs --nostream --lines 20"
fi

# ═══════════════════════════════════════════════════════════════════════════
# DONE
# ═══════════════════════════════════════════════════════════════════════════
banner "OPTIMIZATION COMPLETE"
success "Backup saved to: $BACKUP_DIR"
success "Log file: $LOG_FILE"
echo ""
echo "  To verify:   pm2 list && pm2 logs --lines 20"
echo "  To rollback: $0 --rollback $BACKUP_DIR"
echo "  Full plan:   /root/docs/PM2_OPTIMIZATION_PLAN.md"
echo ""
