#!/usr/bin/env bash
# =============================================================================
# setup-log-rotation.sh — Configure Log Rotation for AIOps Stack
# =============================================================================
# Sets up logrotate for:
#   - /opt/logs/*.log: daily rotation, keep 7, compress
#   - Docker logs: handled by daemon.json (limit per-container)
#   - Journald logs: capped at 500M
#   - Nginx/Traefik access logs: daily, keep 14
#
# Usage:
#   ./setup-log-rotation.sh               # Apply all log rotation configs
#   ./setup-log-rotation.sh --dry-run     # Show what would be done
#   ./setup-log-rotation.sh --verify      # Verify current config
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
LOGROTATE_DIR="/etc/logrotate.d"
DOCKER_CONFIG_DIR="/etc/docker"
JOURNALD_CONFIG_DIR="/etc/systemd/journald.conf.d"

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --verify) VERIFY=true ;;
    --help)
      echo "Usage: $0 [--dry-run] [--verify]"
      exit 0
      ;;
  esac
done

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# 1. APP LOGS (/opt/logs)
# ---------------------------------------------------------------------------
setup_app_logs() {
  log_info "Configuring logrotate for /opt/logs/*.log..."

  run_cmd cat > "$LOGROTATE_DIR/opt-logs" << 'LOGROTATE'
# =============================================================================
# /opt/logs — Application and health check logs
# =============================================================================
# Location: /opt/logs/*.log
# Schedule: daily
# Retention: 7 days
# Compression: gzip (delayed, so the most recent log stays uncompressed)
# Postrotate: No service restart needed for plain file logs
# =============================================================================

/opt/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    dateext
    dateformat -%Y%m%d
    maxage 14
    sharedscripts
}
LOGROTATE

  log_info "  /etc/logrotate.d/opt-logs created."
}

# ---------------------------------------------------------------------------
# 2. DOCKER CONTAINER LOGS (via daemon.json)
# ---------------------------------------------------------------------------
setup_docker_logs() {
  log_info "Configuring Docker container log limits..."

  local daemon_json="$DOCKER_CONFIG_DIR/daemon.json"

  if [ ! -d "$DOCKER_CONFIG_DIR" ]; then
    run_cmd mkdir -p "$DOCKER_CONFIG_DIR"
  fi

  # Read existing daemon.json or create new one
  if [ -f "$daemon_json" ]; then
    log_info "  Updating existing $daemon_json..."
    # Use python3 to safely merge JSON
    run_cmd python3 -c "
import json

config = {}
try:
    with open('$daemon_json') as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    pass

# Set log driver and options (preserving existing config)
log_config = config.get('log-opts', {})
log_config['max-size'] = '10m'
log_config['max-file'] = '3'
config['log-driver'] = 'json-file'
config['log-opts'] = log_config

with open('$daemon_json', 'w') as f:
    json.dump(config, f, indent=2)

print('Docker daemon.json updated.')
print(f'Log driver: {config[\"log-driver\"]}')
print(f'Log options: max-size={log_config[\"max-size\"]}, max-file={log_config[\"max-file\"]}')
"
  else
    log_info "  Creating $daemon_json..."
    run_cmd cat > "$daemon_json" << 'DOCKER'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "iptables": true,
  "live-restore": true
}
DOCKER
  fi

  log_info "  Docker log configuration written."
  log_info "  NOTE: Docker daemon restart required to apply: systemctl restart docker"
  log_warn "  This will restart ALL containers. Schedule during maintenance window."
}

# ---------------------------------------------------------------------------
# 3. JOURNALD LOGS (systemd journal)
# ---------------------------------------------------------------------------
setup_journald() {
  log_info "Configuring systemd journald log limits..."

  run_cmd mkdir -p "$JOURNALD_CONFIG_DIR"

  run_cmd cat > "$JOURNALD_CONFIG_DIR/override.conf" << 'JOURNALD'
# =============================================================================
# journald.conf — Log Limits
# =============================================================================
# WHY: Prevent journal logs from filling /var/log (shared root partition).
# Max 500M total, 7 days retention. Forward to syslog disabled (no rsyslog
# running in container context).
# =============================================================================
[Journal]
# Maximum journal size
SystemMaxUse=500M

# Maximum individual journal file size
SystemMaxFileSize=100M

# Maximum time to keep journals
MaxRetentionSec=7day

# Don't forward to syslog (we use docker logs + journalctl)
ForwardToSyslog=no

# Compress journals
Compress=yes

# Seal journals for integrity checking
Seal=yes
JOURNALD

  log_info "  Journald configuration written."
  log_info "  Apply with: systemctl restart systemd-journald"
}

# ---------------------------------------------------------------------------
# 4. TRAEFIK / NGINX ACCESS LOGS
# ---------------------------------------------------------------------------
setup_traefik_logs() {
  log_info "Configuring logrotate for Traefik/Nginx access logs..."

  # Traefik logs (Docker) are handled by Docker log driver
  # But if Traefik writes to host-mounted files, add logrotate

  local traefik_log_paths=""
  local nginx_log_paths="/var/log/nginx/*.log /var/log/nginx/*/*.log"

  # Check if any Traefik log files exist on host
  if ls /var/log/traefik/*.log 2>/dev/null >/dev/null || \
     ls /opt/docker/traefik/logs/*.log 2>/dev/null >/dev/null; then
    traefik_log_paths="/var/log/traefik/*.log /opt/docker/traefik/logs/*.log"
  fi

  # Only create if paths exist
  if [ -n "$traefik_log_paths" ] || [ -d "/var/log/nginx" ]; then
    run_cmd cat > "$LOGROTATE_DIR/traefik-nginx" << LOGROTATE
# =============================================================================
# Traefik & Nginx — Access/Error Logs
# =============================================================================
# Traefik access logs: daily, keep 14, compress
# Nginx access logs: daily, keep 14, compress
# =============================================================================

$nginx_log_paths ${traefik_log_paths:-} {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    dateext
    dateformat -%Y%m%d
    maxage 30
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 \$(cat /var/run/nginx.pid) 2>/dev/null || true
        [ -f /var/run/traefik.pid ] && kill -USR1 \$(cat /var/run/traefik.pid) 2>/dev/null || true
    endscript
}
LOGROTATE
    log_info "  /etc/logrotate.d/traefik-nginx created."
  else
    log_info "  No Traefik/Nginx access log files found. Skipping."
  fi
}

# ---------------------------------------------------------------------------
# 5. PROMETHEUS & OTHER SERVICE LOGS
# ---------------------------------------------------------------------------
setup_service_logs() {
  log_info "Configuring logrotate for service logs..."

  run_cmd cat > "$LOGROTATE_DIR/services" << 'LOGROTATE'
# =============================================================================
# Service Logs — Prometheus, AlertManager, Netdata, etc.
# =============================================================================
# These are Docker containers whose logs are handled by Docker's json-file
# driver (max 10MB x 3 files). This entry is for any host-level logs that
# may appear in /var/log from these services.
# =============================================================================

/var/log/prometheus/*.log
/var/log/alertmanager/*.log
/var/log/netdata/*.log
{
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    dateext
    maxage 14
    sharedscripts
}
LOGROTATE

  log_info "  /etc/logrotate.d/services created."
}

# ---------------------------------------------------------------------------
# 6. BACKUP LOGS
# ---------------------------------------------------------------------------
setup_backup_logs() {
  log_info "Configuring logrotate for backup logs..."

  run_cmd cat > "$LOGROTATE_DIR/backups" << 'LOGROTATE'
# =============================================================================
# Backup Logs — Database dumps, volume backups
# =============================================================================
# Logs from backup scripts in /opt/logs/backup*.log
# =============================================================================

/opt/logs/backup*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    dateext
    maxage 30
    sharedscripts
}
LOGROTATE

  log_info "  /etc/logrotate.d/backups created."
}

# ---------------------------------------------------------------------------
# VERIFY CONFIGURATION
# ---------------------------------------------------------------------------
verify_config() {
  echo ""
  echo "=== Log Rotation Configuration ==="
  echo ""

  echo "--- Logrotate Config Files ---"
  for f in "$LOGROTATE_DIR"/opt-logs "$LOGROTATE_DIR"/traefik-nginx "$LOGROTATE_DIR"/services "$LOGROTATE_DIR"/backups; do
    if [ -f "$f" ]; then
      echo "  [EXISTS] $f"
    else
      echo "  [MISSING] $f"
    fi
  done

  echo ""
  echo "--- Docker Log Config ---"
  if [ -f "$DOCKER_CONFIG_DIR/daemon.json" ]; then
    echo "  [EXISTS] $DOCKER_CONFIG_DIR/daemon.json"
    python3 -c "
import json
with open('$DOCKER_CONFIG_DIR/daemon.json') as f:
    c = json.load(f)
print(f'  Log driver: {c.get(\"log-driver\", \"NOT SET\")}')
print(f'  Log opts: {c.get(\"log-opts\", \"NOT SET\")}')
" 2>/dev/null || echo "  (cannot parse)"
  else
    echo "  [MISSING] $DOCKER_CONFIG_DIR/daemon.json"
  fi

  echo ""
  echo "--- Journald Config ---"
  if [ -f "$JOURNALD_CONFIG_DIR/override.conf" ]; then
    echo "  [EXISTS] $JOURNALD_CONFIG_DIR/override.conf"
    grep -v '^#' "$JOURNALD_CONFIG_DIR/override.conf" | grep -v '^$' | while read -r line; do
      echo "    $line"
    done
  else
    echo "  [MISSING] $JOURNALD_CONFIG_DIR/override.conf"
  fi

  echo ""
  echo "--- Logrotate Test ---"
  logrotate -d "$LOGROTATE_DIR/opt-logs" 2>&1 | head -5 || echo "  (test skipped)"
  echo ""

  echo "--- Current Disk Usage for Logs ---"
  echo "  /opt/logs: $(du -sh /opt/logs 2>/dev/null || echo 'N/A')"
  echo "  /var/log/journal: $(du -sh /var/log/journal 2>/dev/null || echo 'N/A')"
  echo "  /var/lib/docker/containers: $(du -sh /var/lib/docker/containers 2>/dev/null || echo 'N/A')"

  echo ""
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo "========================================================"
  echo "  Log Rotation Setup — Wheeler AIOps"
  echo "========================================================"
  echo ""

  if [ "${VERIFY:-false}" = true ]; then
    verify_config
    exit 0
  fi

  setup_app_logs
  setup_docker_logs
  setup_journald
  setup_traefik_logs
  setup_service_logs
  setup_backup_logs

  echo ""
  log_info "Log rotation configuration complete!"
  echo ""
  echo "What was configured:"
  echo "  /opt/logs/*.log        → daily, keep 7, compress"
  echo "  Docker daemon.json     → max-size=10m, max-file=3"
  echo "  Journald               → max 500M, 7 day retention"
  echo "  Traefik/Nginx logs     → daily, keep 14, compress"
  echo "  Service logs           → daily, keep 7, compress"
  echo "  Backup logs            → daily, keep 30, compress"
  echo ""
  echo "Next steps:"
  if [ "$DRY_RUN" = false ]; then
    echo "  1. Force logrotate test: logrotate -f /etc/logrotate.d/opt-logs"
    echo "  2. Restart journald:    systemctl restart systemd-journald"
    echo "  3. Restart Docker:      systemctl restart docker (maintenance window)"
    echo "  4. Verify rotation:     ./setup-log-rotation.sh --verify"
  fi
  echo ""
}

main "$@"
