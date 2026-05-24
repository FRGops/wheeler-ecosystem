#!/usr/bin/env bash
# ==============================================================================
# systemd-services.sh — Install and manage systemd service units
# ==============================================================================
#
# Installs systemd service files for the Wheeler AIOps stack:
#   - auto-restart-watchdog.service
#   - backup-scheduler.timer + backup-scheduler.service
#   - health-check.timer + health-check.service
#   - deploy-cleanup.timer (cleans old releases weekly)
#
# Usage:
#   ./systemd-services.sh [install|uninstall|status|logs]
#
# Examples:
#   ./systemd-services.sh install    # Install all services and enable timers
#   ./systemd-services.sh status     # Show status of all services
#   ./systemd-services.sh logs       # View logs for the services
#
# Unit file locations:
#   /etc/systemd/system/auto-restart-watchdog.service
#   /etc/systemd/system/wheeler-backup-scheduler.service
#   /etc/systemd/system/wheeler-backup-scheduler.timer
#   /etc/systemd/system/wheeler-health-check.service
#   /etc/systemd/system/wheeler-health-check.timer
#   /etc/systemd/system/wheeler-deploy-cleanup.service
#   /etc/systemd/system/wheeler-deploy-cleanup.timer
# ==============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
BASE_DIR="${BASE_DIR:-/opt/wheeler}"
SCRIPTS_DIR="${BASE_DIR}/scripts"
SYSTEMD_DIR="/etc/systemd/system"

# Script references (auto-detect Hetzner vs Hostinger)
if hostname | grep -qi "hetzner\|cpx51\|primary"; then
    WATCHDOG_SCRIPT="${BASE_DIR}/../hetzner/scripts/auto-restart-watchdog.sh"
else
    # Watchdog only runs on primary server
    WATCHDOG_SCRIPT=""
fi

BACKUP_SCRIPT="${SCRIPTS_DIR}/backup/run-backup.sh"
HEALTH_SCRIPT="${SCRIPTS_DIR}/monitoring/health-check.sh"
CLEANUP_SCRIPT="${SCRIPTS_DIR}/utils/cleanup-releases.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Pre-flight --------------------------------------------------------------
pre_flight() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (systemd unit installation)."
        exit 1
    fi

    if ! command -v systemctl &>/dev/null; then
        error "systemctl not found. This system does not appear to use systemd."
        exit 1
    fi
}

# --- Unit: auto-restart-watchdog.service -------------------------------------
create_watchdog_service() {
    if [[ -z "$WATCHDOG_SCRIPT" ]]; then
        info "Watchdog service: not applicable on this server (primary only)"
        return 0
    fi

    info "Creating auto-restart-watchdog.service..."

    # Ensure the watchdog script exists
    if [[ ! -f "$WATCHDOG_SCRIPT" ]]; then
        warn "Watchdog script not found at ${WATCHDOG_SCRIPT}"
        warn "Creating placeholder. Install the script manually."
    fi

    cat > "${SYSTEMD_DIR}/auto-restart-watchdog.service" <<UNIT
[Unit]
Description=Wheeler AIOps Container Auto-Restart Watchdog
Documentation=https://github.com/wheeler-io/infrastructure
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root

ExecStart=${WATCHDOG_SCRIPT} --interval 1
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
StartLimitIntervalSec=300
StartLimitBurst=3

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/wheeler/logs /var/run/docker.sock
PrivateTmp=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=wheeler-watchdog

[Install]
WantedBy=multi-user.target
UNIT
    success "Created: auto-restart-watchdog.service"
}

# --- Unit: backup-scheduler.service + .timer ----------------------------------
create_backup_service() {
    info "Creating backup scheduler service and timer..."

    # Service unit
    cat > "${SYSTEMD_DIR}/wheeler-backup-scheduler.service" <<UNIT
[Unit]
Description=Wheeler AIOps Database and Volume Backup
Documentation=https://github.com/wheeler-io/infrastructure
After=docker.service postgres.service
Wants=docker.service

[Service]
Type=oneshot
User=root
Group=root
ExecStart=${BACKUP_SCRIPT}
ExecStartPost=/bin/sh -c 'echo "Backup completed at \$(date -u)" >> ${BASE_DIR}/logs/backup.log'

# Security
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${BASE_DIR}/backups ${BASE_DIR}/logs

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=wheeler-backup
UNIT

    # Timer unit — runs daily at 03:00 UTC
    cat > "${SYSTEMD_DIR}/wheeler-backup-scheduler.timer" <<UNIT
[Unit]
Description=Wheeler AIOps Daily Backup Timer
Documentation=https://github.com/wheeler-io/infrastructure
Requires=wheeler-backup-scheduler.service

[Timer]
OnCalendar=daily
FixedRandomDelay=true
RandomizedDelaySec=600
Persistent=true

# Runs at ~03:00 UTC with up to 10min random delay
OnCalendar=*-*-* 03:00:00 UTC

[Install]
WantedBy=timers.target
UNIT
    success "Created: wheeler-backup-scheduler.service + .timer"
}

# --- Unit: health-check.service + .timer -------------------------------------
create_health_service() {
    info "Creating health check service and timer..."

    # Service unit
    cat > "${SYSTEMD_DIR}/wheeler-health-check.service" <<UNIT
[Unit]
Description=Wheeler AIOps Health Check Runner
Documentation=https://github.com/wheeler-io/infrastructure
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
User=root
Group=root
ExecStart=${HEALTH_SCRIPT}
ExecStartPost=/bin/sh -c 'echo "Health check completed at \$(date -u)" >> ${BASE_DIR}/logs/health-check.log'

# Security
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths=${BASE_DIR}/logs

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=wheeler-health
UNIT

    # Timer — runs every 5 minutes
    cat > "${SYSTEMD_DIR}/wheeler-health-check.timer" <<UNIT
[Unit]
Description=Wheeler AIOps Periodic Health Check Timer
Documentation=https://github.com/wheeler-io/infrastructure
Requires=wheeler-health-check.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
UNIT
    success "Created: wheeler-health-check.service + .timer"
}

# --- Unit: deploy-cleanup.service + .timer -----------------------------------
create_cleanup_service() {
    info "Creating deploy cleanup service and timer..."

    # Create the cleanup script if it doesn't exist
    mkdir -p "$(dirname "$CLEANUP_SCRIPT")"
    if [[ ! -f "$CLEANUP_SCRIPT" ]]; then
        cat > "$CLEANUP_SCRIPT" <<'CLEANUP'
#!/usr/bin/env bash
# cleanup-releases.sh — Remove old release directories
# Keeps the most recent N releases per app.
set -euo pipefail

BASE_DIR="${BASE_DIR:-/opt/wheeler}"
RELEASE_ROOT="${BASE_DIR}/releases"
KEEP="${KEEP_RELEASES:-3}"
LOG_FILE="${BASE_DIR}/logs/cleanup.log"

mkdir -p "$(dirname "$LOG_FILE")"
echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] Cleaning releases (keeping ${KEEP})" >> "$LOG_FILE"

# Group releases by app name
for app_dir in "${RELEASE_ROOT}"/*/; do
    app_name=$(basename "$app_dir")

    # Find all releases for this app, sorted newest first
    releases=$(ls -d "${RELEASE_ROOT}/"*"-${app_name}" 2>/dev/null | sort -r || true)

    count=0
    for release in $releases; do
        count=$((count + 1))
        if [[ $count -gt $KEEP ]]; then
            echo "  Removing: $(basename "$release")" >> "$LOG_FILE"
            rm -rf "$release"
        fi
    done
done

echo "Cleanup complete." >> "$LOG_FILE"
CLEANUP
        chmod 755 "$CLEANUP_SCRIPT"
        success "Created cleanup script: ${CLEANUP_SCRIPT}"
    fi

    cat > "${SYSTEMD_DIR}/wheeler-deploy-cleanup.service" <<UNIT
[Unit]
Description=Wheeler AIOps Deploy Cleanup — Remove Old Releases
Documentation=https://github.com/wheeler-io/infrastructure

[Service]
Type=oneshot
User=root
Group=root
ExecStart=${CLEANUP_SCRIPT}

# Security
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths=${BASE_DIR}/releases ${BASE_DIR}/logs

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=wheeler-cleanup
UNIT

    # Timer — runs weekly on Sunday at 04:00 UTC
    cat > "${SYSTEMD_DIR}/wheeler-deploy-cleanup.timer" <<UNIT
[Unit]
Description=Wheeler AIOps Weekly Release Cleanup Timer
Documentation=https://github.com/wheeler-io/infrastructure
Requires=wheeler-deploy-cleanup.service

[Timer]
OnCalendar=Sun *-*-* 04:00:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
UNIT
    success "Created: wheeler-deploy-cleanup.service + .timer"
}

# --- Install all units -------------------------------------------------------
install_units() {
    info "Creating systemd unit files..."

    create_watchdog_service
    create_backup_service
    create_health_service
    create_cleanup_service

    info "Reloading systemd daemon..."
    systemctl daemon-reload

    # Enable and start services
    info "Enabling and starting services..."

    # Watchdog (if applicable)
    if [[ -n "$WATCHDOG_SCRIPT" ]]; then
        systemctl enable auto-restart-watchdog.service 2>/dev/null || true
        systemctl restart auto-restart-watchdog.service 2>/dev/null || true
        success "auto-restart-watchdog.service: enabled and started"
    fi

    # Backup timer
    systemctl enable wheeler-backup-scheduler.timer 2>/dev/null || true
    systemctl restart wheeler-backup-scheduler.timer 2>/dev/null || true
    success "wheeler-backup-scheduler.timer: enabled and started"

    # Health check timer
    systemctl enable wheeler-health-check.timer 2>/dev/null || true
    systemctl restart wheeler-health-check.timer 2>/dev/null || true
    success "wheeler-health-check.timer: enabled and started"

    # Cleanup timer
    systemctl enable wheeler-deploy-cleanup.timer 2>/dev/null || true
    systemctl restart wheeler-deploy-cleanup.timer 2>/dev/null || true
    success "wheeler-deploy-cleanup.timer: enabled and started"

    echo ""
    success "All systemd units installed and enabled!"

    # Show timer schedule
    echo ""
    info "Active timers:"
    systemctl list-timers --all | grep wheeler || true
    echo ""

    info "Next steps:"
    info "  Create the backup script at: ${BACKUP_SCRIPT}"
    info "  Create the health script at: ${HEALTH_SCRIPT}"
    info "  Monitor with: systemctl status wheeler-*"
}

# --- Uninstall all units -----------------------------------------------------
uninstall_units() {
    warn "Uninstalling all Wheeler systemd units..."

    local units=(
        "auto-restart-watchdog.service"
        "wheeler-backup-scheduler.service"
        "wheeler-backup-scheduler.timer"
        "wheeler-health-check.service"
        "wheeler-health-check.timer"
        "wheeler-deploy-cleanup.service"
        "wheeler-deploy-cleanup.timer"
    )

    for unit in "${units[@]}"; do
        if systemctl is-enabled "$unit" &>/dev/null; then
            systemctl disable "$unit" 2>/dev/null || true
            info "Disabled: ${unit}"
        fi
        if systemctl is-active "$unit" &>/dev/null; then
            systemctl stop "$unit" 2>/dev/null || true
            info "Stopped: ${unit}"
        fi
        if [[ -f "${SYSTEMD_DIR}/${unit}" ]]; then
            rm -f "${SYSTEMD_DIR}/${unit}"
            info "Removed: ${unit}"
        fi
    done

    systemctl daemon-reload
    success "All Wheeler systemd units uninstalled."
}

# --- Show status -------------------------------------------------------------
show_status() {
    echo ""
    echo "=============================================="
    echo "  Systemd Unit Status — Wheeler AIOps"
    echo "=============================================="
    echo ""

    local units=(
        "auto-restart-watchdog.service"
        "wheeler-backup-scheduler.service"
        "wheeler-backup-scheduler.timer"
        "wheeler-health-check.service"
        "wheeler-health-check.timer"
        "wheeler-deploy-cleanup.service"
        "wheeler-deploy-cleanup.timer"
    )

    for unit in "${units[@]}"; do
        if [[ -f "${SYSTEMD_DIR}/${unit}" ]]; then
            echo "── ${unit} ──"
            systemctl is-active "$unit" 2>/dev/null | tr '\n' ' '
            systemctl is-enabled "$unit" 2>/dev/null || true
            echo ""
            echo ""
        fi
    done

    echo ""
    info "Active timers:"
    systemctl list-timers --all 2>/dev/null | grep -E "wheeler|TIMER" || echo "  (none)"
    echo ""
}

# --- Show logs ---------------------------------------------------------------
show_logs() {
    echo ""
    echo "=============================================="
    echo "  Journal Logs — Wheeler AIOps Services"
    echo "=============================================="
    echo ""

    local units=(
        "wheeler-watchdog"
        "wheeler-backup"
        "wheeler-health"
        "wheeler-cleanup"
    )

    for identifier in "${units[@]}"; do
        echo "── ${identifier} (last 10 lines) ──"
        journalctl -t "$identifier" --no-pager -n 10 2>/dev/null || echo "  (no logs)"
        echo ""
    done
}

# --- Main --------------------------------------------------------------------
main() {
    pre_flight

    case "${1:-install}" in
        install)
            install_units
            ;;
        uninstall)
            uninstall_units
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        --help|-h)
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  install     Install and enable all systemd units (default)"
            echo "  uninstall   Disable and remove all systemd units"
            echo "  status      Show status of all units"
            echo "  logs        Show recent journal logs"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown command: $1"
            echo "Usage: $0 [install|uninstall|status|logs]"
            exit 1
            ;;
    esac
}

main "$@"
