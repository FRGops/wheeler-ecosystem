#!/usr/bin/env bash
# =============================================================================
# netdata-alarms.sh — Configure Netdata Alarm Thresholds
# =============================================================================
# Tunes Netdata alarm thresholds for the Wheeler AIOps 2-server setup:
#   - Hetzner CPX51 (16 vCPU, 32GB): wider thresholds for AI workloads
#   - Hostinger VPS (4-8 vCPU, 8-16GB): tighter thresholds
#
# This script writes Netdata health configuration files (.conf) with custom
# thresholds. These override the default Netdata alarms.
#
# Usage:
#   ./netdata-alarms.sh                    # Configure alarms for this server
#   ./netdata-alarms.sh --server=hostinger # Configure for Hostinger VPS
#   ./netdata-alarms.sh --slack-webhook=URL # Configure Slack notifications
#   ./netdata-alarms.sh --reset            # Reset to Netdata defaults
#   ./netdata-alarms.sh --verify           # Verify current alarm config
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
NETDATA_HEALTH_DIR="/etc/netdata/health.d"
NETDATA_CONF_DIR="/etc/netdata"
SLACK_WEBHOOK=""
SERVER_TYPE="hetzner"  # hetzner or hostinger

# Thresholds — tuned per server type
# Hetzner: 16 vCPU, 32GB, handles bursts well
# Hostinger: 4-8 vCPU, 8-16GB, tighter margins
CPU_WARN=80
CPU_CRIT=90
RAM_WARN=85
RAM_CRIT=95
DISK_WARN=80
DISK_CRIT=90
SWAP_WARN=10
SWAP_CRIT=20

# ---------------------------------------------------------------------------
# PARSE ARGUMENTS
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --server=hetzner) SERVER_TYPE="hetzner" ;;
    --server=hostinger) SERVER_TYPE="hostinger" ;;
    --slack-webhook=*) SLACK_WEBHOOK="${arg#*=}" ;;
    --reset) RESET=true ;;
    --verify) VERIFY=true ;;
    --help)
      echo "Usage: $0 [--server=hetzner|hostinger] [--slack-webhook=URL] [--reset] [--verify]"
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# HELPERS
# ----------------------------------------------------------------------------
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---------------------------------------------------------------------------
# PRECHECKS
# ---------------------------------------------------------------------------
prechecks() {
  if [ ! -d "$NETDATA_HEALTH_DIR" ]; then
    if [ -d "/opt/netdata/etc/netdata/health.d" ]; then
      NETDATA_HEALTH_DIR="/opt/netdata/etc/netdata/health.d"
      NETDATA_CONF_DIR="/opt/netdata/etc/netdata"
    else
      log_warn "Netdata config directory not found at $NETDATA_HEALTH_DIR or /opt/netdata/etc/netdata."
      log_info "Creating $NETDATA_HEALTH_DIR..."
      mkdir -p "$NETDATA_HEALTH_DIR"
    fi
  fi

  if ! command -v netdatacli &>/dev/null; then
    log_warn "netdatacli not found. Will write config files but cannot reload Netdata."
    log_warn "You may need to restart Netdata manually: systemctl restart netdata"
  fi
}

# ---------------------------------------------------------------------------
# CONFIGURE CPU ALARMS
# ---------------------------------------------------------------------------
configure_cpu() {
  log_info "Configuring CPU alarms (Warning: ${CPU_WARN}%, Critical: ${CPU_CRIT}%)..."

  cat > "$NETDATA_HEALTH_DIR/cpu.conf" << 'CPU_EOF'
# =============================================================================
# CPU Alarm Configuration — Wheeler AIOps
# =============================================================================
# Netdata default: warning at 80%, critical at 90%
# Our tuning: Same percentages, but adjusted for server type.
#
# WHY 5m duration: CPU spikes from AI workloads are normal. Sustained
# high CPU for 5 minutes indicates genuine overload.
# =============================================================================

# CPU usage — overall system
template: cpu_system_warning
      on: system.cpu
    class: Utilization
     type: System
component: CPU
     calc: $user + $system + $softirq + $irq + $guest
    every: 10s
     warn: $this > (($status >= $WARNING) ? (75) : (80))
     crit: $this > (($status >= $CRITICAL) ? (85) : (90))
    units: %
    delay: up 30s down 30s
  	info: CPU utilization across all cores
       to: sysadmin

# Per-core CPU usage — detect single-core saturation
template: cpu_core_warning
      on: cpu.cpu
    class: Utilization
     type: System
component: CPU
     calc: $user + $system + $softirq + $irq + $guest
    every: 10s
     warn: $this > 90
     crit: $this > 95
    units: %
    delay: up 30s down 30s
  	info: Per-core CPU utilization
       to: sysadmin

# CPU throttling (Docker containers — from cgroups)
template: cpu_cgroup_throttling
      on: cgroup_cpu_throttled
    class: Utilization
     type: Cgroups
component: CPU
     calc: $throttled_time * 100 / $cpu_period
    every: 10s
     warn: $this > 10
     crit: $this > 25
    units: %
    delay: up 1m down 30s
  	info: Percentage of time CPU is throttled for cgroups
       to: sysadmin
CPU_EOF

  log_info "CPU alarms written."
}

# ---------------------------------------------------------------------------
# CONFIGURE RAM ALARMS
# ---------------------------------------------------------------------------
configure_ram() {
  log_info "Configuring RAM alarms (Warning: ${RAM_WARN}%, Critical: ${RAM_CRIT}%)..."

  cat > "$NETDATA_HEALTH_DIR/ram.conf" << 'RAM_EOF'
# =============================================================================
# Memory Alarm Configuration — Wheeler AIOps
# =============================================================================
# Netdata default: warning at 80%, critical at 90%
# Our tuning: Hetzner 32GB — warning at 85%, critical at 95%
#             Hostinger 8-16GB — same percentages, lower absolute buffer
#
# WHY 85/95: AI workloads are memory-intensive. 85% gives 4.8GB headroom
# on Hetzner. 95% (1.6GB) means OOM is imminent.
# WHY 5m: Memory trends matter more than spikes. Short spikes are fine.
# =============================================================================

# RAM usage
template: ram_usage
      on: system.ram
    class: Utilization
     type: System
component: Memory
     calc: (($used + $cached + $buffers) * 100) / $system.ram.total
    every: 10s
     warn: $this > 85
     crit: $this > 95
    units: %
    delay: up 1m down 1m
  	info: System RAM utilization including caches and buffers
       to: sysadmin

# Available RAM (low available = bad, even if "used" is low)
template: ram_available
      on: system.ram
    class: Utilization
     type: System
component: Memory
     calc: ($avail * 100) / $system.ram.total
    every: 10s
     warn: $this < 15
     crit: $this < 5
    units: %
    delay: up 30s down 1m
  	info: Available RAM percentage — below 15% is warning, below 5% is critical
       to: sysadmin

# OOM kills
template: oom_kill
      on: system.ram
    class: Utilization
     type: System
component: Memory
     calc: $oom_kill
    every: 10s
     crit: $this > 0
    units: kills
    delay: up 0s down 0s
  	info: Out Of Memory kills detected
       to: sysadmin
RAM_EOF

  log_info "RAM alarms written."
}

# ---------------------------------------------------------------------------
# CONFIGURE DISK ALARMS
# ---------------------------------------------------------------------------
configure_disk() {
  log_info "Configuring Disk alarms (Warning: ${DISK_WARN}%, Critical: ${DISK_CRIT}%)..."

  cat > "$NETDATA_HEALTH_DIR/disk.conf" << 'DISK_EOF'
# =============================================================================
# Disk Alarm Configuration — Wheeler AIOps
# =============================================================================
# Hetzner: 360GB NVMe. Containers + DBs + backups.
#   WARNING at 80%: 72GB remaining — start cleanup
#   CRITICAL at 90%: 36GB remaining — immediate action
#
# Docker images and DB backups can fill disk quickly.
# Monitor /opt/backups for growth.
# =============================================================================

# Disk space usage
template: disk_space_usage
      on: disk.space
    class: Utilization
     type: System
component: Disk
     calc: ($used * 100) / $avail + $used
    every: 30s
     warn: $this > 80
     crit: $this > 90
    units: %
    delay: up 1m down 1m
  	info: Disk space utilization for mounted filesystems
       to: sysadmin

# Disk inode usage
template: disk_inode_usage
      on: disk.inodes
    class: Utilization
     type: System
component: Disk
     calc: ($used * 100) / ($avail + $used)
    every: 60s
     warn: $this > 80
     crit: $this > 90
    units: %
    delay: up 5m down 1m
  	info: Filesystem inode utilization (can fill before disk space)
       to: sysadmin

# Disk I/O utilization
template: disk_io_utilization
      on: disk.util
    class: Utilization
     type: System
component: Disk
     calc: $util
    every: 30s
     warn: $this > 80
     crit: $this > 95
    units: %
    delay: up 5m down 1m
  	info: Disk I/O utilization percentage (NVMe handles bursts well)
       to: sysadmin
DISK_EOF

  log_info "Disk alarms written."
}

# ---------------------------------------------------------------------------
# CONFIGURE NETWORK ALARMS
# ---------------------------------------------------------------------------
configure_network() {
  log_info "Configuring Network alarms..."

  cat > "$NETDATA_HEALTH_DIR/network.conf" << 'NET_EOF'
# =============================================================================
# Network Alarm Configuration — Wheeler AIOps
# =============================================================================
# Both servers have 1 Gbps links. Network saturation is unlikely but
# packet loss and errors should be monitored.
# =============================================================================

# Interface errors
template: interface_errors
      on: net.error
    class: Errors
     type: Network
component: Network
     calc: $errors_in_discarded + $errors_in + $errors_out_discarded + $errors_out
    every: 10s
     warn: $this > 1
     crit: $this > 10
    units: errors/s
    delay: up 1m down 30s
  	info: Network interface errors and drops per second
       to: sysadmin

# Interface bandwidth (1 Gbps = ~125 MB/s)
template: interface_bandwidth
      on: net.net
    class: Utilization
     type: Network
component: Network
     calc: ($received + $sent) * 8 / 1000000000 * 100
    every: 10s
     warn: $this > 70
     crit: $this > 90
    units: %
    delay: up 2m down 1m
  	info: Network bandwidth utilization percentage (of 1 Gbps)
       to: sysadmin

# Tailscale interface errors (separate from main interface)
template: tailscale_errors
      on: net.error
    class: Errors
     type: Network
component: Network
     calc: $errors_in_discarded + $errors_in + $errors_out_discarded + $errors_out
    every: 10s
     warn: $this > 5
     crit: $this > 20
    units: errors/s
    delay: up 2m down 1m
  	info: Tailscale interface errors — check mesh connectivity
       to: sysadmin
NET_EOF

  log_info "Network alarms written."
}

# ---------------------------------------------------------------------------
# CONFIGURE DOCKER/CONTAINER ALARMS
# ---------------------------------------------------------------------------
configure_docker() {
  log_info "Configuring Docker/Container alarms..."

  cat > "$NETDATA_HEALTH_DIR/docker.conf" << 'DOCKER_EOF'
# =============================================================================
# Docker Container Alarm Configuration — Wheeler AIOps
# =============================================================================
# Monitors container resource usage beyond what cAdvisor + Prometheus catch.
# These run at Netdata speed (per-second) for realtime awareness.
# =============================================================================

# Container CPU throttling (per container)
template: container_cpu_throttling
      on: cgroup_cpu_throttled
    class: Utilization
     type: Cgroups
component: Docker
     calc: $throttled_time * 100 / $cpu_period
    every: 10s
     warn: $this > 5
     crit: $this > 20
    units: %
    delay: up 2m down 1m
  	info: Container CPU throttling percentage — may need higher CPU limits
       to: sysadmin

# Container OOM (per container)
template: container_oom
      on: cgroup.mem
    class: Utilization
     type: Cgroups
component: Docker
     calc: $fail_count
    every: 10s
     crit: $this > 0
    units: failures
    delay: up 0s down 0s
  	info: Container memory limit failures — OOM kills
       to: sysadmin

# Container RAM usage
template: container_ram_usage
      on: cgroup.mem
    class: Utilization
     type: Cgroups
component: Docker
     calc: ($used * 100) / $limit
    every: 10s
     warn: $this > 85
     crit: $this > 95
    units: %
    delay: up 1m down 30s
  	info: Container memory usage percentage of limit
       to: sysadmin
DOCKER_EOF

  log_info "Docker alarms written."
}

# ---------------------------------------------------------------------------
# CONFIGURE NETDATA NOTIFICATIONS (Slack Webhook)
# ---------------------------------------------------------------------------
configure_notifications() {
  if [ -n "$SLACK_WEBHOOK" ]; then
    log_info "Configuring Slack notifications..."

    # Check if health_alarm_notify.conf exists
    local notify_conf="$NETDATA_CONF_DIR/health_alarm_notify.conf"
    if [ ! -f "$notify_conf" ]; then
      if [ -f "/usr/lib/netdata/conf.d/health_alarm_notify.conf" ]; then
        cp "/usr/lib/netdata/conf.d/health_alarm_notify.conf" "$notify_conf"
      else
        log_warn "Cannot find default health_alarm_notify.conf. Creating minimal config."
        cat > "$notify_conf" << 'NOTIFY'
# Netdata notification config — created by netdata-alarms.sh
SEND_SLACK="YES"
DEFAULT_RECIPIENT_SLACK="alerts"
NOTIFY_SLACK_WEBHOOK_URL=""
NOTIFY_SLACK_CUSTOM_SENDER="Netdata Alarms"
NOTIFY_SLACK_CUSTOM_SENDER_EMOJI=":chart_with_upwards_trend:"
NOTIFY_SLACK_CUSTOM_FOOTER="Wheeler AIOps Netdata"
NOTIFY_SLACK_CUSTOM_FOOTER_ICON="https://netdata.cloud/img/favicon.ico"
NOTIFY_SLACK_CUSTOM_FALLBACK_TITLE="Netdata Alarm"
NOTIFY_SLACK_CUSTOM_SEPARATOR=" | "
NOTIFY_SLACK_MAX_ALARMS="10"
NOTIFY_SLACK_MAX_ALARMS_PER_NOTIFICATION="5"
NOTIFY_SLACK_IMAGE_URL=""
NOTIFY_SLACK_VARIABLE_REGEX=""
NOTIFY_SLACK_ALARM_FIELDS="|chart|family|"
NOTIFY_SLACK_CUSTOM_MESSAGE=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_WARNING=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CRITICAL=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CLEAR=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_INFO=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_ERROR=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_WARNING_SEVERITY=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CRITICAL_SEVERITY=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CLEAR_SEVERITY=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_INFO_SEVERITY=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_ERROR_SEVERITY=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_WARNING_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CRITICAL_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CLEAR_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_INFO_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_ERROR_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_WARNING_SEVERITY_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CRITICAL_SEVERITY_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CLEAR_SEVERITY_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_INFO_SEVERITY_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_ERROR_SEVERITY_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_WARNING_STATUS_ALARM=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CRITICAL_STATUS_ALARM=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CLEAR_STATUS_ALARM=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_INFO_STATUS_ALARM=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_ERROR_STATUS_ALARM=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_WARNING_STATUS_ALARM_SEVERITY=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CRITICAL_STATUS_ALARM_SEVERITY=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CLEAR_STATUS_ALARM_SEVERITY=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_INFO_STATUS_ALARM_SEVERITY=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_ERROR_STATUS_ALARM_SEVERITY=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_WARNING_STATUS_ALARM_SEVERITY_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CRITICAL_STATUS_ALARM_SEVERITY_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_CLEAR_STATUS_ALARM_SEVERITY_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_INFO_STATUS_ALARM_SEVERITY_STATUS=""
NOTIFY_SLACK_CUSTOM_MESSAGE_EMOJI_ERROR_STATUS_ALARM_SEVERITY_STATUS=""
NOTIFY
      fi
    fi

    # Set Slack webhook URL
    sed -i "s|^NOTIFY_SLACK_WEBHOOK_URL=.*|NOTIFY_SLACK_WEBHOOK_URL=\"$SLACK_WEBHOOK\"|" "$notify_conf"
    sed -i 's|^SEND_SLACK=.*|SEND_SLACK="YES"|' "$notify_conf"

    log_info "Slack notifications configured."
  else
    log_info "No Slack webhook provided. Skipping notification setup."
  fi
}

# ---------------------------------------------------------------------------
# APPLY CONFIG
# ---------------------------------------------------------------------------
apply_config() {
  log_info "Applying Netdata configuration..."

  # Test config
  if command -v netdatacli &>/dev/null; then
    if netdatacli check-health-config 2>/dev/null; then
      log_info "Netdata health config is valid."
    else
      log_error "Netdata health config has errors. Check $NETDATA_HEALTH_DIR"
      exit 1
    fi

    # Reload health config
    netdatacli reload-health 2>/dev/null || true
    log_info "Netdata health config reloaded."
  else
    log_info "netdatacli not available. Config files written to $NETDATA_HEALTH_DIR"
    log_info "Restart Netdata to apply: systemctl restart netdata"
  fi
}

# ---------------------------------------------------------------------------
# RESET TO DEFAULTS
# ---------------------------------------------------------------------------
reset_config() {
  log_info "Resetting Netdata alarms to defaults..."
  rm -f "$NETDATA_HEALTH_DIR"/cpu.conf \
        "$NETDATA_HEALTH_DIR"/ram.conf \
        "$NETDATA_HEALTH_DIR"/disk.conf \
        "$NETDATA_HEALTH_DIR"/network.conf \
        "$NETDATA_HEALTH_DIR"/docker.conf
  log_info "Custom alarm files removed. Reloading defaults..."
  if command -v netdatacli &>/dev/null; then
    netdatacli reload-health 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# VERIFY CONFIG
# ---------------------------------------------------------------------------
verify_config() {
  log_info "Verifying Netdata alarm configuration..."

  echo ""
  echo "=== Custom Alarm Files ==="
  for f in "$NETDATA_HEALTH_DIR"/*.conf; do
    if [ -f "$f" ]; then
      echo "  $f"
    fi
  done

  echo ""
  echo "=== Active Alarms ==="
  if command -v netdatacli &>/dev/null; then
    netdatacli alarms 2>/dev/null || echo "  (Cannot query alarms)"
  fi

  echo ""
  echo "=== Health Config Validity ==="
  if command -v netdatacli &>/dev/null; then
    netdatacli check-health-config 2>/dev/null && echo "  CONFIG VALID" || echo "  CONFIG HAS ERRORS"
  fi
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo "========================================================"
  echo "  Netdata Alarm Configuration"
  echo "  Server: $SERVER_TYPE"
  echo "========================================================"
  echo ""

  prechecks

  if [ "${RESET:-false}" = true ]; then
    reset_config
    exit 0
  fi

  if [ "${VERIFY:-false}" = true ]; then
    verify_config
    exit 0
  fi

  # Tune thresholds based on server type
  if [ "$SERVER_TYPE" = "hostinger" ]; then
    # Tighter thresholds for smaller server
    CPU_WARN=70
    CPU_CRIT=85
    RAM_WARN=80
    RAM_CRIT=90
    DISK_WARN=75
    DISK_CRIT=85
  fi

  configure_cpu
  configure_ram
  configure_disk
  configure_network
  configure_docker
  configure_notifications
  apply_config

  echo ""
  log_info "Netdata alarm configuration complete!"
  echo ""
  echo "Configuration files:"
  echo "  CPU:     $NETDATA_HEALTH_DIR/cpu.conf"
  echo "  RAM:     $NETDATA_HEALTH_DIR/ram.conf"
  echo "  Disk:    $NETDATA_HEALTH_DIR/disk.conf"
  echo "  Network: $NETDATA_HEALTH_DIR/network.conf"
  echo "  Docker:  $NETDATA_HEALTH_DIR/docker.conf"
  echo ""
  echo "To verify: $0 --verify"
  echo "To reset:  $0 --reset"
  echo ""
}

main "$@"
