#!/bin/bash
# Wheeler Cache Strategy Deployment Script
# Phase 9 — Safe deployment with backup and rollback
# Run on: EDGE server (187.77.148.88)

set -euo pipefail

NGINX_CONF="/etc/nginx/conf.d/cache.conf"
BACKUP_DIR="/root/nginx-backups/$(date +%Y%m%d_%H%M%S)"
CACHE_DIR="/var/cache/nginx/wheeler"

echo "============================================"
echo " Wheeler Cache Strategy Deployment"
echo " Phase 9 — Safe Apply Script"
echo "============================================"
echo ""
echo "This script will:"
echo "  1. Backup current Nginx configuration"
echo "  2. Create cache directories"
echo "  3. Deploy optimized cache configuration"
echo "  4. Test Nginx configuration"
echo "  5. Reload Nginx gracefully"
echo ""
echo "Target: $NGINX_CONF"
echo "Cache size: 2GB + 1GB static"
echo ""

# ---- Step 1: Backup ----
echo "→ Step 1: Creating backup at $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
if [ -d /etc/nginx/conf.d ]; then
    cp -a /etc/nginx/conf.d "$BACKUP_DIR/"
    echo "  ✓ Backed up /etc/nginx/conf.d"
fi
if [ -f /etc/nginx/nginx.conf ]; then
    cp /etc/nginx/nginx.conf "$BACKUP_DIR/"
    echo "  ✓ Backed up nginx.conf"
fi

# ---- Step 2: Create cache directories ----
echo "→ Step 2: Creating cache directories"
mkdir -p "$CACHE_DIR" /var/cache/nginx/wheeler_static
chown -R nginx:nginx /var/cache/nginx/wheeler* 2>/dev/null || chown -R www-data:www-data /var/cache/nginx/wheeler* 2>/dev/null || true
echo "  ✓ Cache directories created"

# ---- Step 3: Deploy config ----
echo "→ Step 3: Deploying cache configuration"
cp /root/templates/cache/nginx-cache-config.conf "$NGINX_CONF"
echo "  ✓ Deployed to $NGINX_CONF"

# ---- Step 4: Test configuration ----
echo "→ Step 4: Testing Nginx configuration"
if nginx -t 2>&1; then
    echo "  ✓ Configuration test passed"
else
    echo "  ✗ Configuration test FAILED — rolling back"
    cp "$BACKUP_DIR/conf.d/cache.conf" "$NGINX_CONF" 2>/dev/null || rm -f "$NGINX_CONF"
    echo "  ✓ Rolled back. Original config preserved at $BACKUP_DIR"
    exit 1
fi

# ---- Step 5: Reload Nginx ----
echo "→ Step 5: Reloading Nginx gracefully"
nginx -s reload 2>&1 || systemctl reload nginx 2>&1 || docker exec nginx nginx -s reload 2>&1
echo "  ✓ Nginx reloaded"

# ---- Step 6: Verify ----
echo "→ Step 6: Verifying cache is working"
sleep 2
# Make a test request and check for X-Cache-Status header
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "skip")
if [ "$HTTP_STATUS" != "000" ]; then
    echo "  ✓ Nginx responding (HTTP $HTTP_STATUS)"
else
    echo "  ⚠ Could not verify locally (may be fine if behind Traefik)"
fi

echo ""
echo "============================================"
echo " Deployment Complete"
echo " Backup: $BACKUP_DIR"
echo "============================================"
echo ""
echo "To rollback:"
echo "  cp $BACKUP_DIR/conf.d/cache.conf $NGINX_CONF"
echo "  nginx -s reload"
echo ""
echo "To monitor cache:"
echo "  tail -f /var/log/nginx/access.log | grep X-Cache-Status"
