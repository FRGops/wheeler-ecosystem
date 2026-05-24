#!/usr/bin/env bash
# =============================================================================
# health-check-cron.sh — Cron-based Health Reporter
# =============================================================================
# Runs every 60 seconds via cron. Checks all services via
# health-check-endpoints.sh. If any service is DOWN for >2 consecutive checks,
# sends alert via webhook.
#
# Logs to /opt/logs/health-check.log with rotation (handled by logrotate).
#
# Install:
#   crontab -e
#   * * * * * /root/infrastructure/hetzner/monitoring/scripts/health-check-cron.sh
#
# For 60-second intervals (cron minimum is 1 min):
#   In cron, runs every minute but checks are lightweight.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/health-check-endpoints.sh"
LOG_DIR="/opt/logs"
LOG_FILE="$LOG_DIR/health-check.log"
STATE_DIR="/var/lib/health-check-cron"
STATE_FILE="$STATE_DIR/down-counts.json"
ALERT_WEBHOOK="https://healthchecks.wheeler.ai/api/v1/cron/health-check/heartbeat"
ALERT_THRESHOLD=2  # Number of consecutive failures before alerting
RETENTION_DAYS=7

# Healthchecks.io ping URL (for dead man's switch)
# This tells Healthchecks.io that the cron job is alive
HEARTBEAT_URL="https://healthchecks.wheeler.ai/api/v1/cron/health-check/heartbeat"

# Slack webhook for alerting (fallback)
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-}"

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------
mkdir -p "$LOG_DIR" "$STATE_DIR"

log_message() {
  local level="$1"
  shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# STATE MANAGEMENT
# ---------------------------------------------------------------------------
# Track consecutive down counts per service in a JSON state file
# Format: {"Service Name": 2, "Other Service": 0}
init_state() {
  if [ ! -f "$STATE_FILE" ]; then
    echo '{}' > "$STATE_FILE"
  fi
}

get_down_count() {
  local service="$1"
  python3 -c "
import json
with open('$STATE_FILE') as f:
    state = json.load(f)
print(state.get('$service', 0))
" 2>/dev/null || echo "0"
}

set_down_count() {
  local service="$1"
  local count="$2"
  python3 -c "
import json
with open('$STATE_FILE') as f:
    state = json.load(f)
state['$service'] = $count
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f)
" 2>/dev/null
}

reset_down_count() {
  local service="$1"
  set_down_count "$service" 0
}

increment_down_count() {
  local service="$1"
  local current
  current=$(get_down_count "$service")
  local new=$((current + 1))
  set_down_count "$service" "$new"
  echo "$new"
}

# ---------------------------------------------------------------------------
# ALERTING
# ---------------------------------------------------------------------------
send_alert() {
  local service="$1"
  local details="$2"
  local count="$3"

  log_message "ALERT" "Service DOWN: $service (${count}x consecutive) — $details"

  # Send via healthchecks.io heartbeat (marks as "down" with status)
  if command -v curl &>/dev/null; then
    # Healthchecks.io: POST body = status details
    curl -sf --max-time 5 \
      -X POST \
      -H "Content-Type: text/plain" \
      -d "DOWN: $service — Consecutive failures: $count — $details" \
      "$HEARTBEAT_URL" \
      2>/dev/null || true

    # Slack notification (if configured)
    if [ -n "$SLACK_WEBHOOK" ]; then
      curl -sf --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{
          \"channel\": \"#alerts\",
          \"username\": \"HealthCheck Cron\",
          \"text\": \"⚠️ *Service DOWN*: $service\n> Consecutive failures: $count\n> Details: $details\",
          \"icon_emoji\": \":warning:\"
        }" \
        "$SLACK_WEBHOOK" \
        2>/dev/null || true
    fi
  fi
}

send_recovery() {
  local service="$1"

  log_message "RECOVERY" "Service UP: $service"

  if command -v curl &>/dev/null; then
    # Send recovery notification to Slack
    if [ -n "$SLACK_WEBHOOK" ]; then
      curl -sf --max-time 5 \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{
          \"channel\": \"#alerts\",
          \"username\": \"HealthCheck Cron\",
          \"text\": \"✅ *Service Recovered*: $service\n> Service is now UP\",
          \"icon_emoji\": \":white_check_mark:\"
        }" \
        "$SLACK_WEBHOOK" \
        2>/dev/null || true
    fi
  fi
}

# ---------------------------------------------------------------------------
# HEARTBEAT — Dead man's switch
# ---------------------------------------------------------------------------
send_heartbeat() {
  if command -v curl &>/dev/null; then
    # Healthchecks.io: GET ping = "I'm alive"
    curl -sf --max-time 5 "$HEARTBEAT_URL" >/dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# MAIN CHECK LOOP
# ---------------------------------------------------------------------------
run_checks() {
  init_state

  log_message "INFO" "Starting health check cycle..."

  # Run the check script in JSON mode
  local json_output
  json_output=$("$CHECK_SCRIPT" --json 2>/dev/null || echo '{"services":[],"summary":{"down":999}}')

  # Parse JSON output
  local down_services
  down_services=$(echo "$json_output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
down = [s for s in data.get('services', []) if s.get('status') == 'DOWN']
for s in down:
    print(f\"{s['name']}|{s['detail']}\")
" 2>/dev/null || echo "")

  local has_downs=false
  local alert_triggered=false

  if [ -n "$down_services" ]; then
    has_downs=true
    log_message "WARN" "Services down detected."

    while IFS='|' read -r service detail; do
      if [ -z "$service" ]; then
        continue
      fi

      local count
      count=$(increment_down_count "$service")

      log_message "WARN" "  $service is DOWN (count: $count) — $detail"

      if [ "$count" -ge "$ALERT_THRESHOLD" ]; then
        send_alert "$service" "$detail" "$count"
        alert_triggered=true
      fi
    done <<< "$down_services"
  fi

  # Reset counters for services that are now UP
  local all_services
  all_services=$(echo "$json_output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for s in data.get('services', []):
    print(f\"{s['name']}|{s['status']}\")
" 2>/dev/null || echo "")

  if [ -n "$all_services" ]; then
    while IFS='|' read -r service status; do
      if [ -z "$service" ]; then
        continue
      fi

      if [ "$status" != "DOWN" ]; then
        local prev_count
        prev_count=$(get_down_count "$service")
        if [ "$prev_count" -gt 0 ]; then
          # Service was down before, now it's up — send recovery
          send_recovery "$service"
        fi
        reset_down_count "$service"
      fi
    done <<< "$all_services"
  fi

  # Send heartbeat to Healthchecks.io
  send_heartbeat

  # Summary
  local total
  total=$(echo "$json_output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('summary', {}).get('total', 0))
" 2>/dev/null || echo "0")

  local up
  up=$(echo "$json_output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('summary', {}).get('up', 0))
" 2>/dev/null || echo "0")

  local down
  down=$(echo "$json_output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('summary', {}).get('down', 0))
" 2>/dev/null || echo "0")

  log_message "INFO" "Check complete: $up UP / $down DOWN / $total TOTAL"

  if [ "$alert_triggered" = true ]; then
    log_message "ALERT" "Alert(s) sent for sustained down services."
  fi

  # Cleanup old log entries (logrotate also handles this)
  # Trim log file to last 10000 lines as safety
  if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 20000 ]; then
    tail -n 10000 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
    log_message "INFO" "Log trimmed to last 10000 lines."
  fi
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
main() {
  case "${1:-}" in
    --check)
      # One-shot check with table output
      exec "$CHECK_SCRIPT"
      ;;
    --force-alert)
      # Test alerting
      log_message "TEST" "Forced alert test"
      send_alert "TEST_SERVICE" "This is a test alert" 999
      echo "Test alert sent. Check $LOG_FILE"
      exit 0
      ;;
    --status)
      # Show current state
      echo "=== Health Check Status ==="
      echo "State file: $STATE_FILE"
      echo "Contents:"
      cat "$STATE_FILE" 2>/dev/null || echo "{}"
      echo ""
      echo "Recent log entries:"
      tail -20 "$LOG_FILE" 2>/dev/null || echo "(no log entries yet)"
      exit 0
      ;;
    *)
      run_checks
      ;;
  esac
}

main "$@"
