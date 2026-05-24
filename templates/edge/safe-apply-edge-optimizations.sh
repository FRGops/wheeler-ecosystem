#!/bin/bash
# =============================================================================
# EDGE Server — Safe Optimization Apply Script
# Target: EDGE @ 187.77.148.88
# Generated: 2026-05-23
#
# This script applies optimization configs with:
#   - Full backup of existing configs
#   - nginx -t validation before reload
#   - Automatic rollback on failure
#   - Verification checks after apply
#
# USAGE:
#   scp safe-apply-edge-optimizations.sh root@187.77.148.88:/root/
#   scp -r /root/templates/edge/*.conf root@187.77.148.88:/root/edge-optimizations/
#   ssh root@187.77.148.88 "bash /root/safe-apply-edge-optimizations.sh"
#
# OPTIONS:
#   --dry-run    Validate everything but don't apply changes
#   --rollback   Restore from most recent backup
#   --verify     Check current config validity without changes
# =============================================================================

set -euo pipefail

# ---- Configuration ----
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_CONF_D="/etc/nginx/conf.d"
SITES_ENABLED="/etc/nginx/sites-enabled"
SITES_AVAILABLE="/etc/nginx/sites-available"
OPTIMIZATIONS_DIR="/root/edge-optimizations"
BACKUP_DIR="/root/nginx-backup-$(date +%Y%m%d-%H%M%S)"
SYSCTL_CONF="/etc/sysctl.d/99-edge-tuning.conf"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${BLUE}==== $* ====${NC}\n"; }

# ---- Parse arguments ----
DRY_RUN=false
ROLLBACK=false
VERIFY_ONLY=false

for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        --rollback) ROLLBACK=true ;;
        --verify) VERIFY_ONLY=true ;;
        --help|-h)
            echo "Usage: $0 [--dry-run|--rollback|--verify]"
            echo "  --dry-run   Validate configs without applying"
            echo "  --rollback  Restore from most recent backup"
            echo "  --verify    Check current config without changes"
            exit 0
            ;;
        *) error "Unknown option: $arg"; exit 1 ;;
    esac
done

# ---- Pre-flight Checks ----
header "Pre-flight Checks"

if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
    exit 1
fi

if [ ! -f "$NGINX_CONF" ]; then
    error "nginx.conf not found at $NGINX_CONF"
    exit 1
fi

if [ ! -d "$OPTIMIZATIONS_DIR" ]; then
    error "Optimization files not found at $OPTIMIZATIONS_DIR"
    error "Copy them first: scp -r /root/templates/edge/*.conf root@187.77.148.88:/root/edge-optimizations/"
    exit 1
fi

# Check nginx binary
if ! command -v nginx &>/dev/null; then
    error "nginx not found in PATH"
    exit 1
fi

NGINX_VERSION=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')
log "Nginx version: $NGINX_VERSION"
log "Config directory: $(dirname $NGINX_CONF)"
log "Optimizations source: $OPTIMIZATIONS_DIR"

# Check current nginx config validity
if ! nginx -t &>/dev/null; then
    error "Current nginx config is INVALID. Fix before proceeding."
    nginx -t 2>&1
    exit 1
fi
log "Current nginx config: VALID"

# ---- Rollback Mode ----
if $ROLLBACK; then
    header "Rollback Mode"
    LATEST_BACKUP=$(ls -dt /root/nginx-backup-* 2>/dev/null | head -1)
    if [ -z "$LATEST_BACKUP" ]; then
        error "No backup found to rollback to"
        exit 1
    fi
    log "Rolling back to: $LATEST_BACKUP"

    # Restore nginx.conf
    if [ -f "$LATEST_BACKUP/nginx.conf" ]; then
        cp "$LATEST_BACKUP/nginx.conf" "$NGINX_CONF"
        log "Restored nginx.conf"
    fi

    # Restore conf.d
    if [ -d "$LATEST_BACKUP/conf.d" ]; then
        rm -rf "$NGINX_CONF_D"/*
        cp -r "$LATEST_BACKUP/conf.d/"* "$NGINX_CONF_D/" 2>/dev/null || true
        log "Restored conf.d/"
    fi

    # Restore sites-enabled (only files that were in backup)
    if [ -d "$LATEST_BACKUP/sites-enabled" ]; then
        for f in "$LATEST_BACKUP/sites-enabled"/*; do
            if [ -f "$f" ]; then
                bname=$(basename "$f")
                # Only restore if it's not a symlink (symlinks point to sites-available)
                if [ -L "$SITES_ENABLED/$bname" ]; then
                    cp "$f" "${SITES_ENABLED}/${bname}.restored"
                    log "Restored $bname (as .restored — original was a symlink)"
                else
                    cp "$f" "$SITES_ENABLED/$bname"
                    log "Restored $bname"
                fi
            fi
        done
    fi

    # Validate restored config
    if nginx -t 2>&1; then
        log "Restored config: VALID. Reloading nginx..."
        systemctl reload nginx
        log "Rollback complete."
    else
        error "Restored config is INVALID. Manual intervention required."
        error "Do NOT reload nginx. Backup is at $LATEST_BACKUP"
        exit 1
    fi
    exit 0
fi

# ---- Verify-Only Mode ----
if $VERIFY_ONLY; then
    header "Verification Mode"

    log "Current nginx config test..."
    nginx -t 2>&1
    echo ""

    log "Current worker_connections:"
    grep -r "worker_connections" "$NGINX_CONF" 2>/dev/null || echo "  Not found in nginx.conf"
    echo ""

    log "Current gzip settings:"
    grep -A 10 "gzip" "$NGINX_CONF" | head -15 || echo "  No gzip settings found"
    echo ""

    log "Current SSL session cache zones:"
    grep -rho "ssl_session_cache [^;]*" /etc/nginx/ 2>/dev/null | sort -u || echo "  None found"
    echo ""

    log "Current rate limit zones:"
    grep -r "limit_req_zone" "$NGINX_CONF" 2>/dev/null || echo "  None found"
    echo ""

    log "Current OCSP stapling:"
    if grep -rq "ssl_stapling on" /etc/nginx/ 2>/dev/null; then
        grep -r "ssl_stapling" /etc/nginx/ 2>/dev/null
    else
        echo "  NOT ENABLED anywhere"
    fi
    echo ""

    log "Current kernel network settings:"
    sysctl net.core.somaxconn net.ipv4.tcp_fastopen net.core.netdev_max_backlog net.ipv4.tcp_slow_start_after_idle
    echo ""

    log "Nginx stub_status (if enabled):"
    curl -s http://127.0.0.1:8765/nginx_status 2>/dev/null || echo "  stub_status not accessible on :8765"
    echo ""

    log "Verification complete. No changes applied."
    exit 0
fi

# ---- Backup ----
header "Creating Backup"
mkdir -p "$BACKUP_DIR"

# Backup nginx.conf
cp "$NGINX_CONF" "$BACKUP_DIR/nginx.conf"
log "Backed up: $NGINX_CONF"

# Backup conf.d
if [ -d "$NGINX_CONF_D" ] && [ "$(ls -A "$NGINX_CONF_D" 2>/dev/null)" ]; then
    cp -r "$NGINX_CONF_D" "$BACKUP_DIR/conf.d"
    log "Backed up: $NGINX_CONF_D ($(ls "$NGINX_CONF_D" | wc -l) files)"
fi

# Backup sites-enabled (non-symlink files)
mkdir -p "$BACKUP_DIR/sites-enabled"
BACKED_UP_SITES=0
for f in "$SITES_ENABLED"/*; do
    if [ -f "$f" ] && [ ! -L "$f" ]; then
        cp "$f" "$BACKUP_DIR/sites-enabled/"
        BACKED_UP_SITES=$((BACKED_UP_SITES + 1))
    fi
done
log "Backed up: $SITES_ENABLED ($BACKED_UP_SITES regular files backed up)"

# Backup sysctl (if exists)
if [ -f "$SYSCTL_CONF" ]; then
    cp "$SYSCTL_CONF" "$BACKUP_DIR/99-edge-tuning.conf.bak"
    log "Backed up: existing $SYSCTL_CONF"
fi

# Save current kernel settings
sysctl net.core.somaxconn net.core.netdev_max_backlog net.ipv4.tcp_max_syn_backlog \
       net.ipv4.tcp_slow_start_after_idle net.ipv4.tcp_fastopen net.ipv4.tcp_fin_timeout \
       net.ipv4.tcp_keepalive_time net.ipv4.tcp_tw_reuse net.core.rmem_max net.core.wmem_max \
       > "$BACKUP_DIR/sysctl-current.txt"
log "Saved current kernel settings"

log "Backup location: $BACKUP_DIR"

if $DRY_RUN; then
    header "Dry-Run Mode"

    log "Would apply: optimized-nginx.conf -> $NGINX_CONF"
    log "Would install conf.d files:"
    ls -la "$OPTIMIZATIONS_DIR"/*.conf 2>/dev/null || log "  (no .conf files found)"

    log "Would remove per-vhost ssl_session_cache from all vhosts"

    log "Would apply kernel tuning"

    # Test merge
    TMP_TEST="/tmp/nginx-test-merged.conf"
    cp "$OPTIMIZATIONS_DIR/optimized-nginx.conf" "$TMP_TEST" 2>/dev/null
    if nginx -t -c "$TMP_TEST" 2>&1; then
        log "Dry-run nginx test: WOULD PASS"
    else
        warn "Dry-run nginx test: WOULD FAIL (may need per-vhost SSL directive cleanup)"
    fi
    rm -f "$TMP_TEST"

    log "Dry-run complete. No changes applied."
    exit 0
fi

# ---- Apply Phase 1: nginx.conf ----
header "Phase 1: Applying optimized nginx.conf"

# Create a backup of existing conf.d as .bak files
for f in "$NGINX_CONF_D"/*.conf; do
    [ -f "$f" ] && cp "$f" "${f}.bak-$(date +%Y%m%d)" 2>/dev/null || true
done

# Install optimized config snippets into conf.d
log "Installing config snippets to $NGINX_CONF_D..."

# Only install files that exist in optimization dir
for conf_file in optimized-global-ssl optimized-gzip optimized-proxy \
                  optimized-cache optimized-rate-limiting optimized-security; do
    SRC="$OPTIMIZATIONS_DIR/${conf_file}.conf"
    DST="$NGINX_CONF_D/${conf_file}.conf"
    if [ -f "$SRC" ]; then
        cp "$SRC" "$DST"
        log "  Installed: ${conf_file}.conf"
    else
        warn "  Skipped (not found): ${conf_file}.conf"
    fi
done

# ---- Apply Phase 2: nginx.conf replacement ----
header "Phase 2: Replacing nginx.conf"

if [ -f "$OPTIMIZATIONS_DIR/optimized-nginx.conf" ]; then
    cp "$OPTIMIZATIONS_DIR/optimized-nginx.conf" "$NGINX_CONF"
    log "Replaced $NGINX_CONF with optimized version"
else
    warn "optimized-nginx.conf not found in $OPTIMIZATIONS_DIR"
    warn "Skipping nginx.conf replacement. Only conf.d snippets were installed."
fi

# ---- Phase 3: Vhost Cleanup (manual) ----
header "Phase 3: Vhost SSL Directive Cleanup"

warn "The following per-vhost directives should be MANUALLY removed"
warn "from ALL vhosts in $SITES_ENABLED to avoid conflicts:"
echo ""
echo "  ssl_session_cache shared:XXXX:10m;     # Now global: SSL:40m"
echo "  ssl_session_timeout 10m;               # Now global"
echo "  ssl_protocols TLSv1.2 TLSv1.3;         # Now global"
echo "  ssl_ciphers ...;                        # Now global"
echo "  ssl_prefer_server_ciphers off;          # Now global"
echo "  gzip on; / gzip_types ...;              # Now global"
echo ""
warn "Run this script with --verify after cleanup to validate."

# Count affected vhosts
AFFECTED=$(grep -rl "ssl_session_cache" "$SITES_ENABLED" 2>/dev/null | wc -l)
log "Found $AFFECTED vhosts with ssl_session_cache that need cleanup."

# ---- Phase 4: Validate and Reload ----
header "Phase 4: Validation"

log "Testing nginx configuration..."
if nginx -t 2>&1; then
    log "Configuration test: PASSED"

    header "Phase 5: Reloading Nginx"
    systemctl reload nginx
    sleep 2

    # Verify nginx is running
    if systemctl is-active --quiet nginx; then
        log "Nginx reloaded successfully and is running."
        log "New configuration is ACTIVE."
    else
        error "Nginx failed to reload properly."
        error "Rolling back..."
        systemctl stop nginx 2>/dev/null || true
        cp "$BACKUP_DIR/nginx.conf" "$NGINX_CONF"
        nginx -t && systemctl start nginx
        error "Rollback complete. Nginx is running with previous config."
        exit 1
    fi
else
    error "Configuration test: FAILED"
    error "Rolling back nginx.conf..."

    # Restore from backup
    cp "$BACKUP_DIR/nginx.conf" "$NGINX_CONF"
    log "Restored original nginx.conf"

    # Remove newly installed conf.d files
    for conf_file in optimized-global-ssl optimized-gzip optimized-proxy \
                      optimized-cache optimized-rate-limiting optimized-security; do
        rm -f "$NGINX_CONF_D/${conf_file}.conf"
    done
    log "Removed new conf.d files"

    # Validate restored config
    if nginx -t 2>&1; then
        log "Original config: VALID"
        systemctl reload nginx 2>/dev/null || systemctl start nginx
        log "Nginx restored to original state."
    else
        error "CRITICAL: Original config also fails validation!"
        error "Manual intervention required. Backup at: $BACKUP_DIR"
        exit 1
    fi
    exit 1
fi

# ---- Phase 6: Sysctl ----
header "Phase 6: Kernel Network Tuning (sysctl)"

if [ -f "$OPTIMIZATIONS_DIR/sysctl-edge-tuning.conf" ]; then
    cp "$OPTIMIZATIONS_DIR/sysctl-edge-tuning.conf" "$SYSCTL_CONF"
    log "Installed: $SYSCTL_CONF"

    # Apply immediately
    log "Applying kernel settings..."
    if sysctl -p "$SYSCTL_CONF" 2>&1; then
        log "Kernel settings applied successfully."
    else
        warn "Some kernel settings may not have applied. Check above for errors."
    fi
else
    warn "sysctl-edge-tuning.conf not found. Skipping kernel tuning."
fi

# ---- Phase 7: Post-Apply Verification ----
header "Phase 7: Post-Apply Verification"

log "Running post-apply checks..."

echo ""
echo "  Nginx Status: $(systemctl is-active nginx)"
echo "  Nginx Workers: $(ps aux | grep 'nginx: worker' | grep -v grep | wc -l)"
echo "  Listening Ports:"
ss -tlnp 2>/dev/null | grep nginx | awk '{print "    "$4}' || echo "    (could not check)"
echo "  Active Connections:"
curl -s http://127.0.0.1:8765/nginx_status 2>/dev/null | head -5 || echo "    (stub_status not accessible)"
echo ""

log "Congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)"
log "TCP Fast Open: $(sysctl -n net.ipv4.tcp_fastopen)"
log "somaxconn: $(sysctl -n net.core.somaxconn)"

# ---- Summary ----
header "Apply Complete"

echo ""
echo "  Backup location:    $BACKUP_DIR"
echo "  To rollback:        $0 --rollback"
echo "  Log files:          /var/log/nginx/error.log"
echo "  Check SSL stapling: echo | openssl s_client -connect localhost:443 -status | grep 'OCSP response'"
echo ""
echo "  NEXT STEPS (MANUAL):"
echo "  1. Remove ssl_session_cache from per-vhost configs"
echo "  2. Test sites: curl -I https://wheeler.frgops.io"
echo "  3. Monitor nginx error log: tail -f /var/log/nginx/error.log"
echo "  4. Check cache hit rates after 24h"
echo ""
echo "  CRITICAL: CPU steal is ~70-90% — contact hosting provider."
echo "  Nginx optimization helps but won't fix the hypervisor issue."
echo ""
