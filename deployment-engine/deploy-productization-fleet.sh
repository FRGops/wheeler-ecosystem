#!/bin/bash
# Wheeler Productization Fleet — Master Deploy Script
# Deploys the entire 28-service productization layer defined in
# ecosystem-productization.config.js
#
# Usage: deploy-productization-fleet.sh [--phase <1-4>] [--dry-run]
# Phases: 1=SurplusAI, 2=Marketplaces, 3=AI Ops SaaS + Wheeler Brain, 4=Revenue + Dashboards
#
# Exit codes: 0=success, 1=preflight fail, 2=deploy fail, 3=rollback success, 4=catastrophic

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ECOSYSTEM_CONFIG="${SCRIPT_DIR}/ecosystem-productization.config.js"
BACKUP_DIR="/opt/backups/deployments/productization-fleet/$(date -u +%Y%m%dT%H%M%SZ)"
LOGFILE="/var/log/wheeler/deploy/productization-fleet-$(date -u +%Y%m%dT%H%M%SZ).log"

PHASE="${2:-all}"
DRY_RUN=false
[[ "${3:-}" == "--dry-run" ]] && DRY_RUN=true

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOGFILE"; }
fail() { log "FATAL: $*"; exit 2; }

# Service groups by phase
declare -A PHASE_SERVICES
PHASE_SERVICES[1]="surplusai-parser-svc,surplusai-scoring-svc,surplusai-crm-sync,surplusai-portal-frontend"
PHASE_SERVICES[2]="attorney-marketplace-api,attorney-onboarding-worker,attorney-license-worker,attorney-portal-frontend,partner-marketplace-api,referral-marketplace-api"
PHASE_SERVICES[3]="aiops-saas-api,aiops-saas-provisioner,aiops-saas-billing-worker,wheeler-brain-api,wheeler-brain-forecast-engine,wheeler-brain-strategy-advisor"
PHASE_SERVICES[4]="attorney-revenue-engine,attorney-document-worker,attorney-communications-worker,unified-payout-engine,revenue-metrics-collector,subscription-lifecycle-worker,executive-dashboard-api,data-enrichment-worker,ml-training-pipeline"

# =========================================================================
# Gate 1: Preflight Checks
# =========================================================================
log "GATE 1: Preflight checks"

# Verify ecosystem config exists
[ -f "$ECOSYSTEM_CONFIG" ] || fail "Ecosystem config not found: ${ECOSYSTEM_CONFIG}"

# Verify PM2 is running
pm2 ping >/dev/null 2>&1 || fail "PM2 daemon not running"

# Verify critical dependencies
declare -A DEPENDENCY_CHECKS
DEPENDENCY_CHECKS["LiteLLM"]="curl -sf http://127.0.0.1:4049/health >/dev/null 2>&1"
DEPENDENCY_CHECKS["FRGCRM"]="curl -sf http://127.0.0.1:8082/health >/dev/null 2>&1"
DEPENDENCY_CHECKS["PostgreSQL"]="pg_isready -h 127.0.0.1 -p 5433 -U frgops >/dev/null 2>&1"
DEPENDENCY_CHECKS["Neo4j"]="curl -sf http://127.0.0.1:7474 >/dev/null 2>&1"
DEPENDENCY_CHECKS["DocuSeal"]="curl -sf http://127.0.0.1:3010 >/dev/null 2>&1"

for dep in "${!DEPENDENCY_CHECKS[@]}"; do
    if eval "${DEPENDENCY_CHECKS[$dep]}"; then
        log "  DEPENDENCY OK: ${dep}"
    else
        log "  DEPENDENCY WARN: ${dep} (non-fatal, continuing)"
    fi
done

# Verify resource headroom
RAM_FREE=$(free -m | awk '/^Mem:/{print $7}')
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d. -f1)
DISK_FREE=$(df -m /opt | awk 'NR==2{print $4}')

log "  Resources: RAM free=${RAM_FREE}MB, CPU idle=${CPU_IDLE}%, Disk free=${DISK_FREE}MB"

if [ "$RAM_FREE" -lt 2048 ]; then
    fail "Insufficient RAM: ${RAM_FREE}MB free (need >2GB for full fleet)"
fi

# =========================================================================
# Gate 2: State Capture
# =========================================================================
log "GATE 2: Capturing pre-deployment state"
mkdir -p "$BACKUP_DIR"
pm2 jlist > "$BACKUP_DIR/pm2-pre.json"
pm2 save --force
docker ps --format json > "$BACKUP_DIR/docker-ps-pre.json" 2>/dev/null || true
ss -tlnp > "$BACKUP_DIR/ss-tlnp-pre.txt"

# =========================================================================
# Gate 3: Deploy
# =========================================================================
log "GATE 3: Deploying services (phase=${PHASE}, dry_run=${DRY_RUN})"

deploy_phase() {
    local phase_num=$1
    local services="${PHASE_SERVICES[$phase_num]}"
    log "Deploying Phase ${phase_num}: ${services}"

    IFS=',' read -ra SERVICE_ARRAY <<< "$services"

    # v2.1: Parallel service starts (eliminates sleep 2 between each)
    declare -a PIDS=()
    for svc in "${SERVICE_ARRAY[@]}"; do
        log "  Deploying: ${svc}"
        if [ "$DRY_RUN" = true ]; then
            log "    DRY RUN: would execute: pm2 start ${ECOSYSTEM_CONFIG} --only ${svc}"
            continue
        fi
        pm2 start "$ECOSYSTEM_CONFIG" --only "$svc" &
        PIDS+=($!)
    done

    # Wait for all starts to complete
    local failed=0
    for pid in "${PIDS[@]}"; do
        wait "$pid" || {
            log "  FAILED: a service start failed (pid=${pid})"
            failed=1
        }
    done
    return $failed
}

if [ "$PHASE" == "all" ]; then
    for p in 1 2 3 4; do
        deploy_phase "$p" || fail "Phase ${p} deployment failed"
    done
else
    deploy_phase "$PHASE" || fail "Phase ${PHASE} deployment failed"
fi

# =========================================================================
# Gate 4: Health Check
# =========================================================================
log "GATE 4: Post-deploy health check"

HEALTH_CHECKS=0
HEALTH_FAILURES=0

check_health() {
    local service=$1
    local port=$2
    local path=${3:-/health}

    HEALTH_CHECKS=$((HEALTH_CHECKS + 1))

    # Wait up to 15 seconds for service to start (poll every 0.5s)
    for i in $(seq 1 30); do
        if curl -sf -o /dev/null "http://127.0.0.1:${port}${path}" 2>/dev/null; then
            log "  HEALTH OK: ${service} http://127.0.0.1:${port}${path}"
            return 0
        fi
        sleep 0.5
    done

    log "  HEALTH FAIL: ${service} http://127.0.0.1:${port}${path} not responding"
    HEALTH_FAILURES=$((HEALTH_FAILURES + 1))
    return 1
}

# Phase 1 health checks
[[ "$PHASE" == "all" || "$PHASE" == "1" ]] && {
    check_health surplusai-parser-svc 8104 /health
    check_health surplusai-scoring-svc 8105 /health
}
# Phase 2 health checks
[[ "$PHASE" == "all" || "$PHASE" == "2" ]] && {
    check_health attorney-marketplace-api 8120 /api/v1/health
    check_health partner-marketplace-api 8130 /api/v1/health
    check_health referral-marketplace-api 8140 /api/v1/health
}
# Phase 3 health checks
[[ "$PHASE" == "all" || "$PHASE" == "3" ]] && {
    check_health aiops-saas-api 8150 /health
    check_health wheeler-brain-api 8160 /health
}
# Phase 4 health checks
[[ "$PHASE" == "all" || "$PHASE" == "4" ]] && {
    check_health revenue-metrics-collector 8170 /health
    check_health executive-dashboard-api 8180 /health
}

# =========================================================================
# Gate 5: Verify
# =========================================================================
log "GATE 5: Verification"

if [ "$HEALTH_FAILURES" -gt 0 ]; then
    log "HEALTH VERIFICATION FAILED: ${HEALTH_FAILURES}/${HEALTH_CHECKS} checks failed"
    log "Rolling back deployment..."

    if [ "$PHASE" == "all" ]; then
        for p in 4 3 2 1; do
            IFS=',' read -ra SERVICE_ARRAY <<< "${PHASE_SERVICES[$p]}"
            for svc in "${SERVICE_ARRAY[@]}"; do
                pm2 delete "$svc" 2>/dev/null || true
            done
        done
    fi

    pm2 resurrect
    log "Rollback complete via pm2 resurrect"
    exit 3
fi

# =========================================================================
# Gate 6: Governance Check
# =========================================================================
log "GATE 6: Governance check"

# Verify all new services bind to 127.0.0.1 only
NEW_PORTS=$(ss -tlnp | grep -E '81[0-9]{2}|81[0-9]{2}' | awk '{print $4}')
for bind in $NEW_PORTS; do
    if echo "$bind" | grep -qv '127.0.0.1'; then
        log "  GOVERNANCE FAIL: Port ${bind} not bound to 127.0.0.1"
        exit 4
    fi
done

# =========================================================================
# Gate 7: Finalize
# =========================================================================
log "GATE 7: Finalizing deployment"
pm2 save --force

# Capture post-deployment state
pm2 jlist > "$BACKUP_DIR/pm2-post.json"
docker ps --format json > "$BACKUP_DIR/docker-ps-post.json" 2>/dev/null || true

log "DEPLOYMENT SUCCESSFUL"
log "  Phase: ${PHASE}"
log "  Health checks: ${HEALTH_CHECKS}/${HEALTH_CHECKS} passed"
log "  Backup: ${BACKUP_DIR}"
log "  Log: ${LOGFILE}"

exit 0
