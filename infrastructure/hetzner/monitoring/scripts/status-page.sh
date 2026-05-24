#!/usr/bin/env bash
# =============================================================================
# status-page.sh — Quick Status Command for Wheeler AIOps Stack
# =============================================================================
# Shows:
#   - Health of every service in color-coded table
#   - Resource usage summary (CPU, RAM, Disk, Network)
#   - Last backup timestamp
#   - Any active alerts
#   - Uptime for each container
#
# Usage:
#   ./status-page.sh                  # Full status page
#   ./status-page.sh --quick           # Compact one-line summary
#   ./status-page.sh --watch           # Watch mode (refresh every 5s)
#   ./status-page.sh --alerts          # Show only active alerts
#   ./status-page.sh --containers      # Show only container status
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
CHECK_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/health-check-endpoints.sh"
HEARTBEAT_URL="http://100.121.230.28:3130/api/v1/cron/alertmanager-webhook"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
CLEAR_LINE='\033[2K\r'

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

format_uptime() {
  local seconds=$1
  local days=$((seconds / 86400))
  local hours=$(( (seconds % 86400) / 3600 ))
  local minutes=$(( (seconds % 3600) / 60 ))

  if [ "$days" -gt 0 ]; then
    echo "${days}d ${hours}h ${minutes}m"
  elif [ "$hours" -gt 0 ]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

format_bytes() {
  local bytes=$1
  if [ "$bytes" -gt 1073741824 ]; then
    echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1073741824}") GB"
  elif [ "$bytes" -gt 1048576 ]; then
    echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}") MB"
  elif [ "$bytes" -gt 1024 ]; then
    echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}") KB"
  else
    echo "${bytes} B"
  fi
}

# ---------------------------------------------------------------------------
# SECTION 1: HEADER
# ---------------------------------------------------------------------------
show_header() {
  echo ""
  echo -e "${BOLD}==============================================================${NC}"
  echo -e "${BOLD}  Wheeler AIOps — System Status${NC}"
  echo -e "${BOLD}  $(date '+%Y-%m-%d %H:%M:%S UTC')${NC}"
  echo -e "${BOLD}  Host: $(hostname)${NC}"
  echo -e "${BOLD}==============================================================${NC}"
  echo ""
}

# ---------------------------------------------------------------------------
# SECTION 2: RESOURCE USAGE
# ---------------------------------------------------------------------------
show_resources() {
  echo -e "${BOLD}── System Resources ──────────────────────────────────────────${NC}"

  # CPU
  if command -v top &>/dev/null; then
    local cpu_idle
    cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/\..*//' || echo "0")
    local cpu_used=$((100 - cpu_idle))
    local cpu_color="$GREEN"
    if [ "$cpu_used" -gt 80 ]; then cpu_color="$YELLOW"; fi
    if [ "$cpu_used" -gt 90 ]; then cpu_color="$RED"; fi
    echo -e "  CPU:     ${cpu_color}${cpu_used}%${NC} used (${cpu_idle}% idle)"
  fi

  # Memory
  if command -v free &>/dev/null; then
    local mem_total mem_used mem_percent
    mem_total=$(free -b | awk '/^Mem:/ {print $2}')
    mem_used=$(free -b | awk '/^Mem:/ {print $3}')
    mem_percent=$((mem_used * 100 / mem_total))
    local mem_color="$GREEN"
    if [ "$mem_percent" -gt 85 ]; then mem_color="$YELLOW"; fi
    if [ "$mem_percent" -gt 95 ]; then mem_color="$RED"; fi
    echo -e "  RAM:     ${mem_color}${mem_percent}%${NC} used ($(format_bytes $mem_used) / $(format_bytes $mem_total))"
  fi

  # Swap
  if command -v free &>/dev/null; then
    local swap_total swap_used swap_percent
    swap_total=$(free -b | awk '/^Swap:/ {print $2}')
    swap_used=$(free -b | awk '/^Swap:/ {print $3}')
    if [ "$swap_total" -gt 0 ]; then
      swap_percent=$((swap_used * 100 / swap_total))
      local swap_color="$GREEN"
      if [ "$swap_percent" -gt 10 ]; then swap_color="$YELLOW"; fi
      if [ "$swap_percent" -gt 50 ]; then swap_color="$RED"; fi
      echo -e "  SWAP:    ${swap_color}${swap_percent}%${NC} used"
    else
      echo -e "  SWAP:    ${GREEN}Disabled${NC}"
    fi
  fi

  # Disk
  if command -v df &>/dev/null; then
    local disk_line disk_used disk_total disk_percent
    disk_line=$(df -h / 2>/dev/null | awk 'NR==2 {print $3, $2, $5}' || df -h / 2>/dev/null | awk 'NR==2 {print $3, $2, $5}')
    disk_used=$(echo "$disk_line" | awk '{print $1}')
    disk_total=$(echo "$disk_line" | awk '{print $2}')
    disk_percent=$(echo "$disk_line" | awk '{print $3}' | sed 's/%//')
    local disk_color="$GREEN"
    if [ "$disk_percent" -gt 80 ]; then disk_color="$YELLOW"; fi
    if [ "$disk_percent" -gt 90 ]; then disk_color="$RED"; fi
    echo -e "  Disk:    ${disk_color}${disk_percent}%${NC} used (${disk_used} / ${disk_total})"
  fi

  # System load
  if command -v uptime &>/dev/null; then
    local load
    load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    echo -e "  Load:    ${load}"
  fi

  # Uptime
  if command -v uptime &>/dev/null; then
    local sys_uptime
    sys_uptime=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk -F'up' '{print $2}' | awk -F',' '{print $1}')
    echo -e "  Uptime:  ${sys_uptime}"
  fi

  # Tailscale status
  if command -v tailscale &>/dev/null; then
    local ts_status
    ts_status=$(tailscale status --json 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    peers = d.get('Peer', {})
    online = sum(1 for p in peers.values() if p.get('Online', False))
    total = len(peers)
    print(f'Online: {online}/{total}')
except:
    print('Unknown')
" 2>/dev/null || echo "Unknown")
    echo -e "  Tailscale: ${ts_status}"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# SECTION 3: SERVICE HEALTH TABLE
# ---------------------------------------------------------------------------
show_services() {
  echo -e "${BOLD}── Service Health ───────────────────────────────────────────${NC}"

  if [ -f "$CHECK_SCRIPT" ]; then
    # Run the check script and parse its table output
    # But for cleaner display, we parse the JSON output
    local json_output
    json_output=$("$CHECK_SCRIPT" --json 2>/dev/null || echo '{"services":[],"summary":{"up":0,"down":0,"total":0}}')

    # Parse and display as table
    printf "  %-3s %-28s %-10s %s\n" "" "SERVICE" "STATUS" "DETAIL"
    echo "  ───────────────────────────────────────────────────────────"

    local up=0 degraded=0 down=0
    while IFS='|' read -r name status detail; do
      local status_display
      local icon
      case "$status" in
        UP)
          icon="${GREEN}✓${NC}"
          status_display="${GREEN}UP${NC}"
          up=$((up + 1))
          ;;
        DEGRADED)
          icon="${YELLOW}~${NC}"
          status_display="${YELLOW}DEGRADED${NC}"
          degraded=$((degraded + 1))
          ;;
        DOWN)
          icon="${RED}✗${NC}"
          status_display="${RED}DOWN${NC}"
          down=$((down + 1))
          ;;
        *)
          icon="?"
          status_display="UNKNOWN"
          ;;
      esac
      printf "  %b %-28s %-10b %s\n" "$icon" "$name" "$status_display" "$detail"
    done < <(echo "$json_output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for s in data.get('services', []):
    print(f\"{s['name']}|{s['status']}|{s['detail']}\")
" 2>/dev/null)

    echo ""
    echo -e "  ${GREEN}UP:${NC} $up  ${YELLOW}DEGRADED:${NC} $degraded  ${RED}DOWN:${NC} $down"

    # Overall status
    if [ "$down" -gt 0 ]; then
      echo -e "  ${BOLD}Status: ${RED}CRITICAL${NC} — $down service(s) DOWN${NC}"
    elif [ "$degraded" -gt 0 ]; then
      echo -e "  ${BOLD}Status: ${YELLOW}DEGRADED${NC} — $degraded service(s) degraded${NC}"
    else
      echo -e "  ${BOLD}Status: ${GREEN}HEALTHY${NC} — All services operational${NC}"
    fi
  else
    echo -e "  ${YELLOW}health-check-endpoints.sh not found at $CHECK_SCRIPT${NC}"
    echo -e "  Run health checks manually or deploy the check script first."
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# SECTION 4: DOCKER CONTAINERS
# ---------------------------------------------------------------------------
show_containers() {
  echo -e "${BOLD}── Container Status ──────────────────────────────────────────${NC}"

  if command -v docker &>/dev/null; then
    # Show running containers
    echo -e "  ${BOLD}Running Containers:${NC}"
    local container_count=0
    while IFS='|' read -r name status uptime ports; do
      if [ -z "$name" ]; then continue; fi
      container_count=$((container_count + 1))

      local status_color="$GREEN"
      local status_icon="${GREEN}●${NC}"
      if [ "$status" != "running" ]; then
        status_color="$RED"
        status_icon="${RED}●${NC}"
      fi

      printf "  %b %-35s %-8b %s\n" "$status_icon" "$name" "${status_color}${status}${NC}" "$uptime"
    done < <(docker ps --format '{{.Names}}|{{.Status}}|{{.RunningFor}}|{{.Ports}}' 2>/dev/null || true)

    if [ "$container_count" -eq 0 ]; then
      echo -e "  ${YELLOW}No running containers found.${NC}"
    fi

    # Show stopped/exited containers
    local stopped_count
    stopped_count=$(docker ps -a --filter "status=exited" --format '{{.Names}}' 2>/dev/null | wc -l)
    if [ "$stopped_count" -gt 0 ]; then
      echo -e "  ${RED}Stopped containers: ${stopped_count}${NC}"
      docker ps -a --filter "status=exited" --format '  └─ {{.Names}} (exited {{.ExitCode}}, {{.Status}})' 2>/dev/null | head -10
    fi
  else
    echo -e "  ${YELLOW}Docker not available.${NC}"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# SECTION 5: LAST BACKUP
# ---------------------------------------------------------------------------
show_backups() {
  echo -e "${BOLD}── Backup Status ─────────────────────────────────────────────${NC}"

  local backup_dir="/opt/backups/databases"

  if [ -d "$backup_dir" ]; then
    local latest_backup
    latest_backup=$(find "$backup_dir" -name "*.dump" -o -name "*.sql.gz" 2>/dev/null | sort -r | head -1)

    if [ -n "$latest_backup" ]; then
      local mtime age_hours
      mtime=$(stat -c %Y "$latest_backup")
      local now
      now=$(date +%s)
      age_hours=$(( (now - mtime) / 3600 ))

      local age_str
      if [ "$age_hours" -gt 24 ]; then
        age_str="${RED}$((age_hours / 24)) days ago${NC}"
      elif [ "$age_hours" -gt 2 ]; then
        age_str="${YELLOW}${age_hours} hours ago${NC}"
      else
        age_str="${GREEN}${age_hours} hours ago${NC}"
      fi

      echo -e "  Latest:     $(basename "$latest_backup")"
      echo -e "  Age:        ${age_str}"
      echo -e "  Directory:  $backup_dir"

      # Show backup sizes
      local backup_size
      backup_size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}')
      echo -e "  Total size: ${backup_size}"

      # Show backup count
      local backup_count
      backup_count=$(find "$backup_dir" -name "*.dump" -o -name "*.sql.gz" 2>/dev/null | wc -l)
      echo -e "  Files:      ${backup_count}"
    else
      echo -e "  ${YELLOW}No backup files found in $backup_dir${NC}"
    fi
  else
    echo -e "  ${YELLOW}Backup directory not found. Backups may not be configured yet.${NC}"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# SECTION 6: ACTIVE ALERTS
# ---------------------------------------------------------------------------
show_alerts() {
  echo -e "${BOLD}── Active Alerts ─────────────────────────────────────────────${NC}"

  local alert_count=0

  # Check Prometheus for active alerts
  if command -v curl &>/dev/null && curl -sf --max-time 2 "http://localhost:9090/api/v1/alerts" >/dev/null 2>&1; then
    local active_alerts
    active_alerts=$(curl -sf --max-time 2 "http://localhost:9090/api/v1/alerts" 2>/dev/null | \
      python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    alerts = data.get('data', {}).get('alerts', [])
    firing = [a for a in alerts if a.get('state') == 'firing']
    for a in firing:
        labels = a.get('labels', {})
        annotations = a.get('annotations', {})
        sev = labels.get('severity', 'unknown')
        name = labels.get('alertname', 'unknown')
        desc = annotations.get('description', '')
        print(f'{sev}|{name}|{desc}')
except:
    pass
" 2>/dev/null || true)

    if [ -n "$active_alerts" ]; then
      while IFS='|' read -r severity name description; do
        alert_count=$((alert_count + 1))
        local sev_color="$YELLOW"
        [ "$severity" = "critical" ] && sev_color="$RED"
        echo -e "  ${sev_color}!${NC} [${sev_color}${severity}${NC}] ${name}"
        if [ -n "$description" ]; then
          echo "        ${description}"
        fi
      done <<< "$active_alerts"
    fi

    if [ "$alert_count" -eq 0 ]; then
      echo -e "  ${GREEN}No active alerts.${NC}"
    fi
  else
    echo -e "  ${YELLOW}Prometheus not reachable. Alert status unavailable.${NC}"
  fi

  if [ "$alert_count" -gt 0 ]; then
    echo ""
    echo -e "  ${BOLD}Total active alerts: ${RED}${alert_count}${NC}"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# SECTION 7: DISK USAGE SUMMARY (Top Consumers)
# ---------------------------------------------------------------------------
show_disk_usage() {
  echo -e "${BOLD}── Disk Usage (Top 10 directories) ───────────────────────────${NC}"

  if command -v du &>/dev/null; then
    du -sh /opt/* /var/* 2>/dev/null | sort -rh | head -10 | while read -r size dir; do
      echo -e "  ${size}\t${dir}"
    done
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# WATCH MODE
# ---------------------------------------------------------------------------
watch_mode() {
  local interval=${1:-5}

  # Save terminal state
  tput smcup 2>/dev/null || true
  tput civis 2>/dev/null || true

  # Trap to restore terminal
  trap 'tput rmcup 2>/dev/null || true; tput cnorm 2>/dev/null || true; exit 0' INT TERM

  while true; do
    clear 2>/dev/null || true

    show_header
    show_resources

    # Quick service summary (compact)
    if [ -f "$CHECK_SCRIPT" ]; then
      local json_output
      json_output=$("$CHECK_SCRIPT" --json 2>/dev/null || echo '{"summary":{"up":0,"down":0,"total":0}}')
      local up down total
      up=$(echo "$json_output" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['summary']['up'])" 2>/dev/null || echo "0")
      down=$(echo "$json_output" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['summary']['down'])" 2>/dev/null || echo "0")
      total=$(echo "$json_output" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['summary']['total'])" 2>/dev/null || echo "0")

      local status_color="$GREEN"
      [ "$down" -gt 0 ] && status_color="$RED"
      echo -e "  Services: ${status_color}${up}/${total} UP${NC} (${down} DOWN)"
    fi

    # Show Docker container count
    if command -v docker &>/dev/null; then
      local running_containers total_containers
      running_containers=$(docker ps -q 2>/dev/null | wc -l)
      total_containers=$(docker ps -aq 2>/dev/null | wc -l)
      echo -e "  Containers: ${running_containers}/${total_containers} running"
    fi

    echo ""
    echo -e "  ${CYAN}Press Ctrl+C to exit watch mode. Refreshing every ${interval}s...${NC}"
    sleep "$interval"
  done
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
main() {
  case "${1:-}" in
    --quick)
      # One-line summary
      if [ -f "$CHECK_SCRIPT" ]; then
        local json_output
        json_output=$("$CHECK_SCRIPT" --json 2>/dev/null || echo '{"summary":{"up":0,"down":0,"total":0}}')
        local up down total
        up=$(echo "$json_output" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['summary']['up'])" 2>/dev/null || echo "0")
        down=$(echo "$json_output" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['summary']['down'])" 2>/dev/null || echo "0")
        total=$(echo "$json_output" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['summary']['total'])" 2>/dev/null || echo "0")
        local status="HEALTHY"
        [ "$down" -gt 0 ] && status="CRITICAL ($down DOWN)"
        echo "$(hostname) | $(date '+%H:%M:%S') | Services: ${up}/${total} | Status: ${status}"
      else
        echo "$(hostname) | $(date '+%H:%M:%S') | Check script not available"
      fi
      ;;
    --watch)
      watch_mode "${2:-5}"
      ;;
    --alerts)
      show_header
      show_alerts
      ;;
    --containers)
      show_header
      show_containers
      ;;
    --resources)
      show_header
      show_resources
      ;;
    *)
      show_header
      show_resources
      show_services
      show_containers
      show_backups
      show_alerts
      # Don't show disk usage in normal mode (too verbose)
      echo -e "${BOLD}── Use --watch for live updates ──────────────────────────────${NC}"
      echo ""
      ;;
  esac
}

main "$@"
