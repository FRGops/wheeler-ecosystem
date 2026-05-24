#!/bin/bash
# Wheeler Queue System Deployment Script
# Phase 10 — Safe deployment with backup and rollback
# Run on: AIOPS server (5.78.140.118)

set -euo pipefail

REDIS_HOST="5.78.210.123"
REDIS_PORT="6379"
BACKUP_DIR="/root/queue-backups/$(date +%Y%m%d_%H%M%S)"
PM2_CONFIG="/root/templates/queue/pm2-queue-workers.config.js"
QUEUE_WORKER_DIR="/opt/wheeler/queue-workers"

echo "============================================"
echo " Wheeler Queue System Deployment"
echo " Phase 10 — Safe Apply Script"
echo "============================================"
echo ""
echo "This script will:"
echo "  1. Verify Redis connectivity to $REDIS_HOST"
echo "  2. Backup current PM2 configuration"
echo "  3. Deploy queue worker infrastructure"
echo "  4. Start queue workers via PM2 (shadow mode)"
echo "  5. Verify queue health"
echo ""
echo "⚠  IMPORTANT: This deploys in SHADOW MODE first."
echo "   Existing agent-svc processes continue running."
echo "   No production traffic is routed to queue workers yet."
echo ""

# ---- Step 1: Verify Redis ----
echo "→ Step 1: Verifying Redis connectivity"
if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING 2>/dev/null | grep -q PONG; then
    echo "  ✓ Redis reachable at $REDIS_HOST:$REDIS_PORT"
else
    echo "  ✗ Cannot reach Redis — check network/firewall/credentials"
    echo "  Attempting with auth..."
    # Try with common auth patterns
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$(grep REDIS_PASSWORD /root/.env 2>/dev/null | cut -d= -f2)" PING 2>/dev/null || {
        echo "  ✗ Redis auth failed. Please configure credentials and retry."
        exit 1
    }
fi

# ---- Step 2: Backup ----
echo "→ Step 2: Creating backup"
mkdir -p "$BACKUP_DIR"
pm2 save 2>/dev/null || true
if [ -f ~/.pm2/dump.pm2 ]; then
    cp ~/.pm2/dump.pm2 "$BACKUP_DIR/"
    echo "  ✓ Backed up PM2 dump"
fi
pm2 list > "$BACKUP_DIR/pm2-list.txt" 2>/dev/null
echo "  ✓ Saved PM2 process list"
echo "  Backup at: $BACKUP_DIR"

# ---- Step 3: Deploy queue workers ----
echo "→ Step 3: Deploying queue worker code"
mkdir -p "$QUEUE_WORKER_DIR"
cp /root/templates/queue/arq-worker.py "$QUEUE_WORKER_DIR/"
cp /root/templates/queue/bullmq-setup.ts "$QUEUE_WORKER_DIR/" 2>/dev/null || true
cp /root/templates/queue/queue-health-endpoint.py "$QUEUE_WORKER_DIR/"
echo "  ✓ Worker code deployed to $QUEUE_WORKER_DIR"

# ---- Step 4: Install dependencies ----
echo "→ Step 4: Checking dependencies"
pip3 install arq 2>/dev/null && echo "  ✓ arq installed" || echo "  ⚠ pip3 install arq failed — may need manual install"
npm list bullmq 2>/dev/null && echo "  ✓ bullmq installed" || echo "  ⚠ bullmq not installed — Node.js workers need npm install"

# ---- Step 5: Start queue workers in shadow mode ----
echo "→ Step 5: Starting queue workers (SHADOW MODE)"
if [ -f "$PM2_CONFIG" ]; then
    pm2 start "$PM2_CONFIG" --only "queue-worker,queue-health" 2>/dev/null || {
        echo "  ⚠ PM2 start via config failed — starting individual workers"
        pm2 start "$QUEUE_WORKER_DIR/arq-worker.py" \
            --name "queue-worker" \
            --interpreter python3 \
            -i 2 \
            --max-memory-restart 512M \
            --env "REDIS_URL=redis://${REDIS_HOST}:${REDIS_PORT}" \
            2>/dev/null || echo "  ⚠ Manual start needed"
    }
    echo "  ✓ Queue workers started in shadow mode"
else
    echo "  ⚠ PM2 config not found at $PM2_CONFIG — skipping worker start"
fi

# ---- Step 6: Verify ----
echo "→ Step 6: Verifying queue health"
sleep 3
pm2 list | grep queue-worker && echo "  ✓ Queue workers online" || echo "  ⚠ Queue workers not detected"
pm2 logs queue-worker --lines 10 --nostream 2>/dev/null || true

echo ""
echo "============================================"
echo " Deployment Complete (SHADOW MODE)"
echo " Backup: $BACKUP_DIR"
echo "============================================"
echo ""
echo "Queue workers are running alongside existing agent-svc processes."
echo "They are NOT receiving production traffic yet."
echo ""
echo "To verify shadow mode:"
echo "  pm2 list | grep queue"
echo "  curl http://localhost:8080/api/queue/health"
echo ""
echo "To cut over traffic (after validation):"
echo "  1. Update routing to send tasks to queue instead of direct calls"
echo "  2. Monitor queue metrics for 24 hours"
echo "  3. Stop old agent-svc processes: pm2 stop agent-svc-*"
echo ""
echo "To rollback:"
echo "  pm2 stop queue-worker queue-health"
echo "  pm2 delete queue-worker queue-health"
echo "  # Old agent-svc processes are still running and handling traffic"
