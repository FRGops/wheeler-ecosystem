#!/usr/bin/env bash
# =============================================================================
# backup-cron-setup.sh — CRON Job Installer for Backup System
# =============================================================================
# Installs crontab entries for:
#   - Full backup (databases + volumes) daily at 03:00 UTC
#   - Hostinger pull daily at 04:00 UTC
#   - Rotation weekly on Sunday at 05:00 UTC
#   - Backup integrity verification weekly on Sunday at 06:00 UTC
#
# Usage: ./backup-cron-setup.sh [--install|--uninstall|--status]
#   --install   Install cron jobs (default)
#   --uninstall Remove all backup cron jobs
#   --status    Show current backup cron jobs
# =============================================================================
set -euo pipefail

# --- Configuration -----------------------------------------------------------
# These paths match the backup scripts
SCRIPTS_DIR_HETZNER="/opt/scripts/backup"
SCRIPTS_DIR_SHARED="/opt/scripts/backup"
LOG_DIR="/opt/logs"

# Allow override via environment
SCRIPTS_DIR_HETZNER="${SCRIPTS_DIR_HETZNER:-/root/infrastructure/hetzner/backup}"
SCRIPTS_DIR_SHARED="${SCRIPTS_DIR_SHARED:-/root/infrastructure/shared/backup-rotation}"
LOG_DIR="${LOG_DIR:-/opt/logs}"

# Cron job definitions
CRON_JOBS=(
    # Full backup: daily at 03:00 UTC
    "0 3 * * * ${SCRIPTS_DIR_HETZNER}/full-backup.sh >> ${LOG_DIR}/backup-cron.log 2>&1"
    # Hostinger pull: daily at 04:00 UTC
    "0 4 * * * ${SCRIPTS_DIR_SHARED}/pull-hostinger-backups.sh >> ${LOG_DIR}/hostinger-pull.log 2>&1"
    # Rotation: weekly Sunday at 05:00 UTC
    "0 5 * * 0 ${SCRIPTS_DIR_SHARED}/rotate-backups.sh --dir /opt/backups/databases --pattern '*.dump' --force >> ${LOG_DIR}/rotate.log 2>&1"
    # Additional rotation for volumes
    "30 5 * * 0 ${SCRIPTS_DIR_SHARED}/rotate-backups.sh --dir /opt/backups/volumes --pattern '*.tar.gz' --force >> ${LOG_DIR}/rotate.log 2>&1"
    # Backup integrity verification: weekly Sunday at 06:00 UTC
    "0 6 * * 0 ${SCRIPTS_DIR_SHARED}/verify-backup-integrity.sh >> ${LOG_DIR}/verify-backup.log 2>&1"
    # Hostinger archive rotation: daily at 04:30 UTC
    "30 4 * * * ${SCRIPTS_DIR_SHARED}/rotate-backups.sh --dir /root/backups/hostinger --pattern '*.dump' --days 7 --force >> ${LOG_DIR}/rotate.log 2>&1"
)

# Marker comment for identification in crontab
MARKER_START="# === AIOps Backup System (installed by backup-cron-setup.sh) ==="
MARKER_END="# === End AIOps Backup System ==="

# --- Check scripts exist before installing -----------------------------------
check_scripts() {
    local missing=0

    if [ ! -f "${SCRIPTS_DIR_HETZNER}/full-backup.sh" ]; then
        echo "WARNING: ${SCRIPTS_DIR_HETZNER}/full-backup.sh not found"
        missing=1
    fi
    if [ ! -f "${SCRIPTS_DIR_SHARED}/pull-hostinger-backups.sh" ]; then
        echo "WARNING: ${SCRIPTS_DIR_SHARED}/pull-hostinger-backups.sh not found"
        missing=1
    fi
    if [ ! -f "${SCRIPTS_DIR_SHARED}/rotate-backups.sh" ]; then
        echo "WARNING: ${SCRIPTS_DIR_SHARED}/rotate-backups.sh not found"
        missing=1
    fi
    if [ ! -f "${SCRIPTS_DIR_SHARED}/verify-backup-integrity.sh" ]; then
        echo "WARNING: ${SCRIPTS_DIR_SHARED}/verify-backup-integrity.sh not found"
        missing=1
    fi

    if [ "${missing}" -ne 0 ]; then
        echo ""
        echo "Some scripts are missing. Cron jobs will still be installed but may fail."
        echo "Install all scripts first for proper operation."
        echo ""
    fi
}

# --- Ensure directories exist ------------------------------------------------
setup_directories() {
    mkdir -p "${LOG_DIR}"
    echo "Ensuring log directory exists: ${LOG_DIR}"
}

# --- Install cron jobs -------------------------------------------------------
install_cron() {
    echo ""
    echo "Installing AIOps Backup System cron jobs..."
    echo ""

    check_scripts
    setup_directories

    # Get existing crontab (or empty)
    local existing_crontab=""
    existing_crontab="$(crontab -l 2>/dev/null || true)"

    # Check if already installed
    if echo "${existing_crontab}" | grep -q "${MARKER_START}"; then
        echo "Backup cron jobs already installed. Updating..."
        # Remove existing backup section
        existing_crontab="$(echo "${existing_crontab}" | sed "/${MARKER_START}/,/${MARKER_END}/d")"
    fi

    # Build new crontab
    local new_crontab="${existing_crontab}"
    new_crontab+="${new_crontab:+$'\n'}${MARKER_START}"$'\n'

    for job in "${CRON_JOBS[@]}"; do
        new_crontab+="${job}"$'\n'
        echo "  + ${job}"
    done

    new_crontab+="${MARKER_END}"$'\n'

    # Install
    echo "${new_crontab}" | crontab -

    echo ""
    echo "Cron jobs installed successfully."
    echo ""

    # Show current crontab
    echo "Current crontab:"
    echo "----------------------------------------"
    crontab -l 2>/dev/null || echo "(empty)"
    echo "----------------------------------------"
}

# --- Uninstall cron jobs -----------------------------------------------------
uninstall_cron() {
    echo ""
    echo "Removing AIOps Backup System cron jobs..."
    echo ""

    local existing_crontab
    existing_crontab="$(crontab -l 2>/dev/null || true)"

    if ! echo "${existing_crontab}" | grep -q "${MARKER_START}"; then
        echo "No backup cron jobs found to remove."
        return 0
    fi

    # Show what we're removing
    echo "Removing these jobs:"
    echo "${existing_crontab}" | sed -n "/${MARKER_START}/,/${MARKER_END}/p"
    echo ""

    # Remove backup section
    existing_crontab="$(echo "${existing_crontab}" | sed "/${MARKER_START}/,/${MARKER_END}/d")"

    # Install remaining
    echo "${existing_crontab}" | crontab -

    echo "Backup cron jobs removed."
    echo ""

    # Show remaining crontab
    echo "Remaining crontab:"
    echo "----------------------------------------"
    crontab -l 2>/dev/null || echo "(empty)"
    echo "----------------------------------------"
}

# --- Show status --------------------------------------------------------------
show_status() {
    echo ""
    echo "AIOps Backup System — Current Cron Status"
    echo "==========================================="
    echo ""

    local crontab_content
    crontab_content="$(crontab -l 2>/dev/null || echo "(no crontab)")"

    if echo "${crontab_content}" | grep -q "${MARKER_START}"; then
        echo "Status: INSTALLED"
        echo ""
        echo "Backup cron jobs:"
        echo "${crontab_content}" | sed -n "/${MARKER_START}/,/${MARKER_END}/p"
    else
        echo "Status: NOT INSTALLED"
    fi

    echo ""
    echo "Full crontab:"
    echo "----------------------------------------"
    echo "${crontab_content}"
    echo "----------------------------------------"
    echo ""

    # Check if script files exist
    echo "Script status:"
    echo "  Hetzner backup:       $([ -f "${SCRIPTS_DIR_HETZNER}/full-backup.sh" ] && echo "OK" || echo "MISSING")"
    echo "  Hostinger pull:       $([ -f "${SCRIPTS_DIR_SHARED}/pull-hostinger-backups.sh" ] && echo "OK" || echo "MISSING")"
    echo "  Rotation:             $([ -f "${SCRIPTS_DIR_SHARED}/rotate-backups.sh" ] && echo "OK" || echo "MISSING")"
    echo "  Integrity verify:     $([ -f "${SCRIPTS_DIR_SHARED}/verify-backup-integrity.sh" ] && echo "OK" || echo "MISSING")"
    echo ""
    echo "Log directory:         ${LOG_DIR} ($([ -d "${LOG_DIR}" ] && echo "OK" || echo "MISSING"))"
}

# === MAIN ===
main() {
    local action="${1:-install}"

    case "${action}" in
        --install|-i|install)
            install_cron
            ;;
        --uninstall|-u|uninstall|remove)
            uninstall_cron
            ;;
        --status|-s|status)
            show_status
            ;;
        --help|-h)
            echo "Usage: $(basename "$0") [--install|--uninstall|--status]"
            echo ""
            echo "  --install     Install cron jobs (default)"
            echo "  --uninstall   Remove backup cron jobs"
            echo "  --status      Show current backup cron status"
            ;;
        *)
            echo "Unknown action: ${action}"
            echo "Usage: $(basename "$0") [--install|--uninstall|--status]"
            exit 1
            ;;
    esac
}

# --- Run ---------------------------------------------------------------------
main "$@"
