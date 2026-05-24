#!/bin/bash
# =============================================================================
# Wheeler — PM2 Duplicate Service Detector
# =============================================================================
#
# Detects issues in the PM2 process ecosystem:
#   1. Duplicate service names (same name, multiple instances with different
#      configs that should be the same).
#   2. Stale/stopped services that have been dead for an extended period.
#   3. Services running on the wrong server (cross-server validation).
#   4. Services with mismatched configurations (env mismatch, port conflicts).
#
# Usage:
#   ./detect-duplicates.sh [--fix] [--verbose] [--server <edge|aiops|coredb>]
#
# Options:
#   --fix       Attempt to auto-fix detected issues (stop stale services,
#               remove duplicates keeping the most recent).
#   --verbose   Show detailed output including raw PM2 JSON data.
#   --server    Specify which server this check runs on.
#               Valid values: edge, aiops, coredb.
#               Default: auto-detected from hostname.
#
# Exit Codes:
#   0   Clean — no issues detected.
#   1   Warnings — issues detected but none critical.
#   2   Critical — duplicate services or cross-server issues detected.
#   3   Error — the script itself encountered an error.
#
# =============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

# Services that are EXPECTED to be on this server.
# Modify this array based on the server this script runs on.
declare -A EXPECTED_SERVICES_BY_SERVER
EXPECTED_SERVICES_BY_SERVER["edge"]="nginx traefik frgops-dashboard wheeler-frontend"
EXPECTED_SERVICES_BY_SERVER["aiops"]="litellm frgcrm-api surplusai-scraper-agent-svc prediction-radar-worker prediction-radar-scheduler wheeler-brain-os openclaw-gateway voice-agent-svc browser-agent-svc"
EXPECTED_SERVICES_BY_SERVER["coredb"]=""  # COREDB typically has no PM2 processes (uses Docker/systemd)

# Stale threshold: services stopped/errored longer than this (seconds) are
# considered stale and should be cleaned up.
STALE_THRESHOLD_SECONDS=$(( 7 * 24 * 60 * 60 ))  # 7 days

# Max duplicate count before it's considered critical
MAX_DUPLICATE_WARNING=1
MAX_DUPLICATE_CRITICAL=3

# ── Color Output ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ── Argument Parsing ─────────────────────────────────────────────────────────

FIX_MODE=false
VERBOSE=false
SERVER="auto"
EXIT_CODE=0
ISSUES_FOUND=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)     FIX_MODE=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --server)  SERVER="$2"; shift 2 ;;
    *)         echo "Unknown option: $1"; exit 3 ;;
  esac
done

# Auto-detect server
if [[ "$SERVER" == "auto" ]]; then
  HOSTNAME=$(hostname)
  if [[ "$HOSTNAME" == *"edge"* ]]; then
    SERVER="edge"
  elif [[ "$HOSTNAME" == *"aiops"* ]]; then
    SERVER="aiops"
  elif [[ "$HOSTNAME" == *"coredb"* ]]; then
    SERVER="coredb"
  else
    echo "WARNING: Could not auto-detect server from hostname '${HOSTNAME}'."
    echo "         Defaulting to 'aiops'.  Use --server to specify."
    SERVER="aiops"
  fi
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Wheeler PM2 Duplicate & Stale Service Detector              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Server:    %-49s ║\n" "$SERVER"
printf "║  Fix mode:  %-49s ║\n" "$FIX_MODE"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Check PM2 is Running ────────────────────────────────────────────────────

if ! pm2 list &>/dev/null; then
  echo -e "${RED}[ERROR]${NC} PM2 is not running or not installed."
  echo "       Install PM2: npm install -g pm2@latest"
  exit 3
fi

# ── Fetch PM2 Process Data ───────────────────────────────────────────────────

echo -e "${BLUE}[INFO]${NC} Fetching PM2 process list..."

if ! PM2_JSON=$(pm2 jlist 2>/dev/null); then
  echo -e "${RED}[ERROR]${NC} Failed to fetch PM2 process list."
  exit 3
fi

TOTAL_PROCESSES=$(echo "$PM2_JSON" | jq '. | length')
echo -e "${BLUE}[INFO]${NC} Total PM2 processes: ${TOTAL_PROCESSES}"

if [[ "$TOTAL_PROCESSES" -eq 0 ]]; then
  echo -e "${GREEN}[PASS]${NC} No PM2 processes running.  Nothing to check."
  exit 0
fi

# ── Check 1: Duplicate Service Names ─────────────────────────────────────────

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  CHECK 1: Duplicate Service Names"
echo "───────────────────────────────────────────────────────────────"

# Build a map of service names and their count
DUPLICATE_NAMES=$(echo "$PM2_JSON" | jq -r '
  [.[] | .name] |
  group_by(.) |
  map(select(length > 1) | {name: .[0], count: length, instances: .}) |
  sort_by(.count) | reverse |
  .[]
')

if [[ -z "$DUPLICATE_NAMES" ]]; then
  echo -e "${GREEN}[PASS]${NC} No duplicate service names found."
else
  echo "$DUPLICATE_NAMES" | while IFS= read -r line; do
    # Parse the JSON object for each duplicate group
    NAME=$(echo "$line" | jq -r '.name' 2>/dev/null || true)
    COUNT=$(echo "$line" | jq -r '.count' 2>/dev/null || true)

    if [[ -z "$NAME" || -z "$COUNT" ]]; then
      continue
    fi

    ISSUES_FOUND=$((ISSUES_FOUND + 1))

    if [[ "$COUNT" -ge "$MAX_DUPLICATE_CRITICAL" ]]; then
      echo -e "${RED}[CRITICAL]${NC} Service '${NAME}' has ${COUNT} duplicate instances!"
      EXIT_CODE=2
    else
      echo -e "${YELLOW}[WARNING]${NC} Service '${NAME}' has ${COUNT} instances (expected 1)."
      if [[ "$EXIT_CODE" -lt 1 ]]; then
        EXIT_CODE=1
      fi
    fi

    # Show details of each instance
    echo "$line" | jq -r '.instances[] | "  - pid=\(.pid) status=\(.pm2_env.status) uptime=\(.pm2_env.pm_uptime // "N/A") memory=\(.monit.memory // "N/A")"'

    # Auto-fix: keep the most recent, stop the others
    if [[ "$FIX_MODE" == true ]]; then
      echo -e "${YELLOW}[FIX]${NC} Attempting to resolve duplicates for '${NAME}'..."

      # Get PIDs sorted by uptime (keep the oldest/newest based on preference)
      # Strategy: keep the "online" one; stop the rest
      ONLINE_PIDS=$(echo "$line" | jq -r '.instances[] | select(.pm2_env.status == "online") | .pid')
      STOPPED_PIDS=$(echo "$line" | jq -r '.instances[] | select(.pm2_env.status != "online") | .pid')

      # If multiple online, keep the first, stop others
      ONLINE_COUNT=$(echo "$ONLINE_PIDS" | wc -l)
      if [[ "$ONLINE_COUNT" -gt 1 ]]; then
        KEEP_PID=$(echo "$ONLINE_PIDS" | head -1)
        STOP_PIDS=$(echo "$ONLINE_PIDS" | tail -n +2)
        for PID in $STOP_PIDS; do
          echo "  Stopping duplicate instance (pid=${PID})..."
          pm2 stop "$PID" 2>/dev/null || true
          pm2 delete "$PID" 2>/dev/null || true
        done
      fi

      # Clean up already-stopped duplicates
      for PID in $STOPPED_PIDS; do
        echo "  Removing stopped duplicate (pid=${PID})..."
        pm2 delete "$PID" 2>/dev/null || true
      done
    fi
  done
fi

# ── Check 2: Stale / Stopped Services ────────────────────────────────────────

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  CHECK 2: Stale / Stopped Services"
echo "───────────────────────────────────────────────────────────────"

STALE_SERVICES=$(echo "$PM2_JSON" | jq -r --argjson threshold "$STALE_THRESHOLD_SECONDS" '
  [.[] |
    select(.pm2_env.status == "stopped" or .pm2_env.status == "errored") |
    {
      name: .name,
      status: .pm2_env.status,
      pid: .pid,
      stopped_at: (.pm2_env.pm_uptime // 0),
      stale_seconds: ((now - (.pm2_env.created_at / 1000)) // 0)
    } |
    select(.stale_seconds > ($threshold / 1000))
  ] |
  sort_by(.stale_seconds) | reverse
')

STALE_COUNT=$(echo "$STALE_SERVICES" | jq '. | length')

if [[ "$STALE_COUNT" -eq 0 ]]; then
  echo -e "${GREEN}[PASS]${NC} No stale or stopped services found."
else
  echo "$STALE_SERVICES" | jq -r '.[] | "\(.name) | status=\(.status) | pid=\(.pid) | stale_for_days=\((.stale_seconds / 86400) | floor)"' | while IFS= read -r line; do
    echo -e "${YELLOW}[WARNING]${NC} Stale service: ${line}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  done

  if [[ "$EXIT_CODE" -lt 1 ]]; then
    EXIT_CODE=1
  fi

  if [[ "$FIX_MODE" == true ]]; then
    echo ""
    echo -e "${YELLOW}[FIX]${NC} Removing stale services..."
    echo "$STALE_SERVICES" | jq -r '.[].name' | while read -r name; do
      echo "  Deleting stale service: ${name}"
      pm2 delete "$name" 2>/dev/null || true
    done
  fi
fi

# ── Check 3: Services on Wrong Server ────────────────────────────────────────

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  CHECK 3: Cross-Server Service Validation"
echo "───────────────────────────────────────────────────────────────"

EXPECTED="${EXPECTED_SERVICES_BY_SERVER[$SERVER]:-}"
if [[ -z "$EXPECTED" ]]; then
  echo -e "${BLUE}[INFO]${NC} No expected services defined for server '${SERVER}'.  Skipping cross-server check."
else
  # Build list of unexpected services (running services NOT in expected list)
  RUNNING_SERVICES=$(echo "$PM2_JSON" | jq -r '[.[] | select(.pm2_env.status == "online") | .name] | join(" ")')

  UNEXPECTED_SERVICES=""
  for SERVICE in $RUNNING_SERVICES; do
    if ! echo "$EXPECTED" | grep -qw "$SERVICE"; then
      UNEXPECTED_SERVICES="${UNEXPECTED_SERVICES} ${SERVICE}"
    fi
  done

  if [[ -z "$UNEXPECTED_SERVICES" ]]; then
    echo -e "${GREEN}[PASS]${NC} All running services match expected server assignment."
  else
    echo -e "${RED}[CRITICAL]${NC} Services running on wrong server (${SERVER}):"
    for SERVICE in $UNEXPECTED_SERVICES; do
      echo "  - ${SERVICE}"
      ISSUES_FOUND=$((ISSUES_FOUND + 1))
    done
    EXIT_CODE=2

    if [[ "$FIX_MODE" == true ]]; then
      echo ""
      echo -e "${YELLOW}[FIX]${NC} Stopping services on wrong server..."
      for SERVICE in $UNEXPECTED_SERVICES; do
        echo "  Stopping: ${SERVICE}"
        pm2 stop "$SERVICE" 2>/dev/null || true
      done
    fi
  fi
fi

# ── Check 4: Port Conflicts ──────────────────────────────────────────────────

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  CHECK 4: Port Conflict Detection"
echo "───────────────────────────────────────────────────────────────"

# Extract ports from PM2 environment variables by checking PORT and args
declare -A PORT_MAP
PORT_CONFLICTS=0

while IFS= read -r line; do
  NAME=$(echo "$line" | jq -r '.name')
  # Try to extract PORT from env vars or args
  PORT=$(echo "$line" | jq -r '(.pm2_env.env.PORT // .pm2_env.args // "")' 2>/dev/null | grep -oP '\d{4,5}' | head -1 || true)

  if [[ -n "$PORT" ]]; then
    if [[ -n "${PORT_MAP[$PORT]:-}" ]]; then
      echo -e "${RED}[CRITICAL]${NC} Port conflict: ${NAME} and ${PORT_MAP[$PORT]} both claim port ${PORT}"
      ISSUES_FOUND=$((ISSUES_FOUND + 1))
      PORT_CONFLICTS=$((PORT_CONFLICTS + 1))
      EXIT_CODE=2
    else
      PORT_MAP[$PORT]="$NAME"
    fi
  fi
done < <(echo "$PM2_JSON" | jq -c '.[]')

if [[ "$PORT_CONFLICTS" -eq 0 ]]; then
  echo -e "${GREEN}[PASS]${NC} No port conflicts detected among PM2 services."
fi

# ── Check 5: Resource Thresholds ─────────────────────────────────────────────

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  CHECK 5: Resource Usage Warnings"
echo "───────────────────────────────────────────────────────────────"

MEMORY_WARNINGS=0
CPU_WARNINGS=0

echo "$PM2_JSON" | jq -c '.[] | select(.pm2_env.status == "online")' | while IFS= read -r line; do
  NAME=$(echo "$line" | jq -r '.name')
  MEMORY=$(echo "$line" | jq -r '.monit.memory // 0')
  CPU=$(echo "$line" | jq -r '.monit.cpu // 0')
  RESTARTS=$(echo "$line" | jq -r '.pm2_env.restart_time // 0')

  # Memory warning (> 1GB in bytes)
  if [[ "$(echo "$MEMORY > 1073741824" | bc -l 2>/dev/null || echo 0)" == "1" ]]; then
    MEMORY_GB=$(echo "scale=2; $MEMORY / 1073741824" | bc)
    echo -e "${YELLOW}[WARNING]${NC} ${NAME}: High memory usage (${MEMORY_GB} GB)"
  fi

  # CPU warning (> 50%)
  if [[ "$(echo "$CPU > 50" | bc -l 2>/dev/null || echo 0)" == "1" ]]; then
    echo -e "${YELLOW}[WARNING]${NC} ${NAME}: High CPU usage (${CPU}%)"
  fi

  # Restart warning
  if [[ "$RESTARTS" -gt 50 ]]; then
    echo -e "${YELLOW}[WARNING]${NC} ${NAME}: High restart count (${RESTARTS})"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SCAN COMPLETE                                               ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Processes scanned:  %-39s ║\n" "$TOTAL_PROCESSES"
printf "║  Issues found:       %-39s ║\n" "$ISSUES_FOUND"
printf "║  Exit code:          %-39s ║\n" "$EXIT_CODE"

case "$EXIT_CODE" in
  0) printf "║  Status:             %-39s ║\n" "${GREEN}CLEAN${NC}" ;;
  1) printf "║  Status:             %-39s ║\n" "${YELLOW}WARNINGS${NC}" ;;
  2) printf "║  Status:             %-39s ║\n" "${RED}CRITICAL${NC}" ;;
esac

echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Verbose Output ──────────────────────────────────────────────────────────

if [[ "$VERBOSE" == true ]]; then
  echo "───────────────────────────────────────────────────────────────"
  echo "  VERBOSE: Full PM2 Process List (JSON)"
  echo "───────────────────────────────────────────────────────────────"
  echo "$PM2_JSON" | jq '.'
fi

# ── Save Report ──────────────────────────────────────────────────────────────

REPORT_FILE="/opt/wheeler/logs/pm2-duplicate-report-$(date +%Y%m%d-%H%M%S).txt"
{
  echo "PM2 Duplicate Detection Report"
  echo "=============================="
  echo "Server:    $SERVER"
  echo "Date:      $(date)"
  echo "Fix mode:  $FIX_MODE"
  echo "Issues:    $ISSUES_FOUND"
  echo "Exit code: $EXIT_CODE"
  echo ""
  echo "Process list:"
  pm2 list
} > "$REPORT_FILE" 2>/dev/null || true

echo -e "${BLUE}[INFO]${NC} Report saved to: ${REPORT_FILE}"

exit "$EXIT_CODE"
