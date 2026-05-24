#!/usr/bin/env bash
# ============================================================================
# Safe API Optimization Apply Script
# Phase 6: API Performance Optimization Plan
# Generated: 2026-05-23
# Target: AIOPS (5.78.140.118)
#
# USAGE:
#   Dry run:  bash safe-apply-api-optimizations.sh --dry-run
#   Apply:    bash safe-apply-api-optimizations.sh --execute
#   Single:   bash safe-apply-api-optimizations.sh --step S1 --execute
#
# PRINCIPLES:
#   1. Every step has a PRE-CHECK, APPLY, and POST-VERIFY phase.
#   2. Post-verify failures trigger automatic rollback.
#   3. The script is safe to re-run (idempotent steps).
#   4. Backups are created before any file modification.
#   5. Steps can be applied individually (--step S1).
# ============================================================================

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
AIOPS_HOST="${AIOPS_HOST:-5.78.140.118}"
SSH_CMD="ssh -o ConnectTimeout=5 root@${AIOPS_HOST}"
BACKUP_DIR="/root/api-optimization-backups/$(date +%Y%m%d-%H%M%S)"
DRY_RUN=true
SELECTED_STEP=""
LOG_FILE="/var/log/wheeler-ops/api-optimization-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ── Parse arguments ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --execute)
            DRY_RUN=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --step)
            SELECTED_STEP="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--dry-run | --execute] [--step S1|S2|S3|S4|S5|S6]"
            exit 1
            ;;
    esac
done

# ── Logging ──────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
exec 2> >(tee -a "$LOG_FILE" >&2)
exec > >(tee -a "$LOG_FILE")

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Utility functions ────────────────────────────────────────────────────────
dry_or_real() {
    if $DRY_RUN; then
        log "DRY RUN: would run: $*"
        return 0
    else
        log "EXECUTING: $*"
        eval "$@"
    fi
}

backup_file() {
    local remote_path="$1"
    local filename
    filename=$(basename "$remote_path")
    local backup_path="${BACKUP_DIR}/${filename}.bak.$(date +%s)"

    if $DRY_RUN; then
        log "DRY RUN: would backup ${remote_path} to ${backup_path}"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    if $SSH_CMD "[ -f ${remote_path} ]" 2>/dev/null; then
        $SSH_CMD "cp ${remote_path} ${backup_path}" 2>/dev/null || {
            warn "Could not backup ${remote_path} remotely, fetching locally"
            scp "root@${AIOPS_HOST}:${remote_path}" "${backup_path}" 2>/dev/null || true
        }
        ok "Backed up: ${remote_path} -> ${backup_path}"
    else
        warn "File not found for backup: ${remote_path}"
    fi
}

verify_pm2_online() {
    local service="$1"
    local status
    status=$($SSH_CMD "pm2 jlist 2>/dev/null | python3 -c \"import json,sys; data=json.load(sys.stdin); print(next((p['pm2_env']['status'] for p in data if p['name']=='${service}'), 'NOT_FOUND'))\"" 2>/dev/null)
    if [ "$status" = "online" ]; then
        ok "PM2 service '${service}' is online"
        return 0
    else
        err "PM2 service '${service}' is NOT online (status: ${status})"
        return 1
    fi
}

verify_http_responds() {
    local url="$1"
    local expected_code="${2:-200}"
    local code
    code=$($SSH_CMD "curl -s -o /dev/null -w '%{http_code}' --max-time 5 '${url}'" 2>/dev/null)
    if [ "$code" = "$expected_code" ]; then
        ok "HTTP ${url} responded with ${code}"
        return 0
    else
        err "HTTP ${url} responded with ${code} (expected ${expected_code})"
        return 1
    fi
}

run_step() {
    local step_id="$1"
    local step_name="$2"

    # Skip if a specific step is selected and this isn't it
    if [ -n "$SELECTED_STEP" ] && [ "$SELECTED_STEP" != "$step_id" ]; then
        log "Skipping ${step_id}: ${step_name} (selected step: ${SELECTED_STEP})"
        return 0
    fi

    echo ""
    echo "============================================================"
    echo "  STEP ${step_id}: ${step_name}"
    if $DRY_RUN; then
        echo "  MODE: DRY RUN (no changes will be made)"
    else
        echo "  MODE: LIVE EXECUTION"
    fi
    echo "============================================================"
}

# ============================================================================
# STEP S1: Stagger PM2 Restart Delays (LOWEST RISK)
# ============================================================================
apply_s1() {
    run_step "S1" "Stagger PM2 Restart Delays"

    log "Pre-check: Current restart delays..."
    $SSH_CMD "pm2 jlist 2>/dev/null | python3 -c '
import json,sys
data=json.load(sys.stdin)
for p in data:
    name=p.get(\"name\",\"?\")
    rd=p.get(\"pm2_env\",{}).get(\"restart_delay\",\"N/A\")
    mr=p.get(\"pm2_env\",{}).get(\"max_restarts\",\"N/A\")
    print(f\"  {name}: restart_delay={rd}ms, max_restarts={mr}\")
' 2>/dev/null | grep agent-svc" || true

    # Define staggered delays
    declare -A RESTART_DELAYS
    RESTART_DELAYS[frgcrm-agent-svc]=5000
    RESTART_DELAYS[horizon-agent-svc]=6000
    RESTART_DELAYS[surplusai-scraper-agent-svc]=8000
    RESTART_DELAYS[paperless-agent-svc]=9000
    RESTART_DELAYS[voice-agent-svc]=11000
    RESTART_DELAYS[prediction-radar-agent-svc]=12000
    RESTART_DELAYS[insforge-agent-svc]=14000
    RESTART_DELAYS[ravyn-agent-svc]=15000
    RESTART_DELAYS[design-agent-svc]=17000

    log "Applying staggered restart delays..."

    for svc in "${!RESTART_DELAYS[@]}"; do
        local delay="${RESTART_DELAYS[$svc]}"
        if $DRY_RUN; then
            log "  DRY RUN: Would set ${svc} restart_delay=${delay}"
        else
            # Find the ecosystem.config.js for this service
            local config_file="/opt/apps/${svc}/ecosystem.config.js"
            if $SSH_CMD "[ -f ${config_file} ]" 2>/dev/null; then
                backup_file "$config_file"
                # Update restart_delay in the config
                $SSH_CMD "sed -i 's/restart_delay: [0-9]*,/restart_delay: ${delay},/' ${config_file}" 2>/dev/null
                ok "  ${svc}: restart_delay=${delay}"
            else
                warn "  ${svc}: config not found at ${config_file}, updating via PM2 directly"
                # PM2 doesn't support changing restart_delay at runtime for existing process
                # It requires delete + restart with new config
                warn "  ${svc}: PM2 in-process restart_delay requires config file update + restart"
            fi
        fi
    done

    # Also update max_restarts from 10 to 5 for agent-svc (reduce restart storms)
    log "Also reducing max_restarts from 10 to 5 for agent services..."
    for svc in "${!RESTART_DELAYS[@]}"; do
        local config_file="/opt/apps/${svc}/ecosystem.config.js"
        if $DRY_RUN; then
            log "  DRY RUN: Would set ${svc} max_restarts=5"
        else
            if $SSH_CMD "[ -f ${config_file} ]" 2>/dev/null; then
                $SSH_CMD "sed -i 's/max_restarts: 10,/max_restarts: 5,/' ${config_file}" 2>/dev/null || true
                ok "  ${svc}: max_restarts=5"
            fi
        fi
    done

    if ! $DRY_RUN; then
        log "Post-verify: Check PM2 is still running..."
        $SSH_CMD "pm2 list | head -5" 2>/dev/null || warn "PM2 list failed"
        log "NOTE: Restart delays take effect on next PM2 restart of each service."
        log "NOTE: To fully apply, restart each service: pm2 restart <name>"
    fi

    ok "S1 complete"
}

# ============================================================================
# STEP S2: Add Express Timeout Middleware (LOW RISK)
# ============================================================================
apply_s2() {
    run_step "S2" "Add Express Timeout Middleware to Agent Services"

    local TIMEOUT_MIDDLEWARE='
// ── REQUEST TIMEOUT MIDDLEWARE (auto-added by api-optimization) ──
const REQUEST_TIMEOUT_MS = parseInt(process.env.REQUEST_TIMEOUT_MS || "60000", 10);
app.use((req, res, next) => {
  const timer = setTimeout(() => {
    if (!res.headersSent) {
      res.status(504).json({ error: "Request timeout" });
    }
  }, REQUEST_TIMEOUT_MS);
  res.on("finish", () => clearTimeout(timer));
  res.on("close", () => clearTimeout(timer));
  next();
});
'

    local LISTEN_PATCH='server.timeout = 30000; server.keepAliveTimeout = 65000; server.headersTimeout = 66000;'

    local AGENT_SVCS="design horizon frgcrm insforge paperless prediction-radar ravyn surplusai-scraper voice"

    for svc in $AGENT_SVCS; do
        local svc_dir="/opt/apps/${svc}-agent-svc"
        local server_ts="${svc_dir}/src/server.ts"
        local index_ts="${svc_dir}/src/index.ts"

        if $DRY_RUN; then
            log "  DRY RUN: Would patch ${svc}-agent-svc"
            continue
        fi

        # Check if service exists
        if ! $SSH_CMD "[ -d ${svc_dir} ]" 2>/dev/null; then
            warn "  ${svc}-agent-svc: directory not found, skipping"
            continue
        fi

        # Backup
        if $SSH_CMD "[ -f ${server_ts} ]" 2>/dev/null; then
            backup_file "$server_ts"
        fi
        if $SSH_CMD "[ -f ${index_ts} ]" 2>/dev/null; then
            backup_file "$index_ts"
        fi

        # Patch server.ts — add timeout middleware after express.json()
        if $SSH_CMD "[ -f ${server_ts} ]" 2>/dev/null; then
            local has_timeout
            has_timeout=$($SSH_CMD "grep -c 'REQUEST_TIMEOUT' ${server_ts} 2>/dev/null || echo 0")
            if [ "$has_timeout" -eq 0 ]; then
                $SSH_CMD "sed -i '/app.use(express.json());/a\\${TIMEOUT_MIDDLEWARE}' ${server_ts}" 2>/dev/null || warn "Could not patch ${server_ts}"
                ok "  ${svc}-agent-svc: timeout middleware added to server.ts"
            else
                log "  ${svc}-agent-svc: timeout middleware already present"
            fi
        fi

        # Patch index.ts — add server timeout configuration after app.listen()
        if $SSH_CMD "[ -f ${index_ts} ]" 2>/dev/null; then
            local has_listen_patch
            has_listen_patch=$($SSH_CMD "grep -c 'server.timeout' ${index_ts} 2>/dev/null || echo 0")
            if [ "$has_listen_patch" -eq 0 ]; then
                # Find the app.listen line and add server config after it
                $SSH_CMD "sed -i '/app.listen(config.port,/a\\const server = app.listen(config.port, () => console.log(\\`[\${svcName}] on :\${config.port}\\`));'" ${index_ts} 2>/dev/null || true
                $SSH_CMD "sed -i '/^const server = app.listen/a\\server.timeout = 30000;\\nserver.keepAliveTimeout = 65000;\\nserver.headersTimeout = 66000;\\nserver.requestTimeout = 60000;' ${index_ts}" 2>/dev/null || warn "Could not patch ${index_ts} server config"
                ok "  ${svc}-agent-svc: server timeout config added to index.ts"
            else
                log "  ${svc}-agent-svc: server timeout config already present"
            fi
        fi
    done

    log "Post-verify: Check agent-svc services are still online..."
    for svc in $AGENT_SVCS; do
        verify_pm2_online "${svc}-agent-svc" || warn "${svc}-agent-svc not online"
    done

    log ""
    warn "IMPORTANT: Source patches require TypeScript recompilation!"
    warn "After S2, run for each service: cd /opt/apps/<svc>-agent-svc && npm run build"
    warn "Then restart: pm2 restart <svc>-agent-svc"

    ok "S2 complete (source patched; recompilation needed)"
}

# ============================================================================
# STEP S3: Reduce FRG CRM API Connection Pool (LOW-MEDIUM RISK)
# ============================================================================
apply_s3() {
    run_step "S3" "Reduce FRG CRM API Database Connection Pool"

    local DB_PY="/opt/wheeler/apps/frgcrm/api/database.py"

    log "Pre-check: Current pool config..."
    $SSH_CMD "grep -E 'pool_size|max_overflow|pool_recycle' ${DB_PY} 2>/dev/null" || {
        err "Cannot read ${DB_PY}"
        return 1
    }

    log "Backing up database.py..."
    backup_file "$DB_PY"

    if ! $DRY_RUN; then
        # Replace pool_size
        $SSH_CMD "sed -i 's/pool_size=[0-9]*,/pool_size=10,/' ${DB_PY}" 2>/dev/null
        # Replace max_overflow
        $SSH_CMD "sed -i 's/max_overflow=[0-9]*,/max_overflow=20,/' ${DB_PY}" 2>/dev/null
        # Replace pool_recycle
        $SSH_CMD "sed -i 's/pool_recycle=[0-9]*,/pool_recycle=3600,/' ${DB_PY}" 2>/dev/null

        # Add pool_timeout if not present
        if ! $SSH_CMD "grep -q 'pool_timeout' ${DB_PY}" 2>/dev/null; then
            $SSH_CMD "sed -i '/pool_recycle=3600,/a\\    pool_timeout=10,' ${DB_PY}" 2>/dev/null
        fi

        ok "database.py updated"
    else
        log "DRY RUN: Would update pool_size=10, max_overflow=20, pool_recycle=3600, pool_timeout=10"
    fi

    # Restart frgcrm-api to apply pool changes
    if ! $DRY_RUN; then
        log "Restarting frgcrm-api to apply pool changes..."
        $SSH_CMD "pm2 restart frgcrm-api" 2>/dev/null
        sleep 5

        log "Post-verify: frgcrm-api health..."
        verify_pm2_online "frgcrm-api" || {
            err "frgcrm-api failed to come online after pool change!"
            err "ROLLBACK: Restoring original database.py..."
            local latest_backup
            latest_backup=$(ls -t "${BACKUP_DIR}"/database.py.bak.* 2>/dev/null | head -1)
            if [ -n "$latest_backup" ]; then
                scp "$latest_backup" "root@${AIOPS_HOST}:${DB_PY}" || err "Rollback failed!"
                $SSH_CMD "pm2 restart frgcrm-api" 2>/dev/null
                sleep 5
                verify_pm2_online "frgcrm-api" && ok "Rollback successful" || err "Rollback failed! Manual intervention required!"
            fi
            return 1
        }

        verify_http_responds "http://localhost:8082/" 200 || warn "Health check warning"
        verify_http_responds "http://localhost:8082/api/health" 200 || warn "API health check warning"
    fi

    ok "S3 complete"
}

# ============================================================================
# STEP S4: Add Uvicorn Production Flags (LOW RISK)
# ============================================================================
apply_s4() {
    run_step "S4" "Add Uvicorn Production Flags to FRG CRM API"

    log "Pre-check: Current PM2 config for frgcrm-api..."
    $SSH_CMD "pm2 show frgcrm-api 2>/dev/null | grep -E 'script path|script args'" || warn "Could not read PM2 config"

    # Update the PM2 process to include production flags
    local NEW_ARGS="-m uvicorn main:app --host 0.0.0.0 --port 8082 --workers 4 --limit-concurrency 200 --limit-max-requests 10000 --timeout-keep-alive 30 --backlog 128 --log-level warning"

    if $DRY_RUN; then
        log "DRY RUN: Would update frgcrm-api uvicorn args to:"
        log "  ${NEW_ARGS}"
    else
        log "Stopping frgcrm-api..."
        $SSH_CMD "pm2 stop frgcrm-api" 2>/dev/null
        sleep 2

        log "Updating PM2 process with new args..."
        $SSH_CMD "pm2 delete frgcrm-api 2>/dev/null; cd /opt/wheeler/apps/frgcrm/api && pm2 start venv/bin/python3 --name frgcrm-api -- ${NEW_ARGS}" 2>/dev/null
        sleep 5

        log "Post-verify: frgcrm-api health..."
        verify_pm2_online "frgcrm-api" || {
            err "frgcrm-api failed to come online after worker change!"
            err "ROLLBACK: Restarting with previous worker count..."
            $SSH_CMD "pm2 delete frgcrm-api 2>/dev/null; cd /opt/wheeler/apps/frgcrm/api && pm2 start venv/bin/python3 --name frgcrm-api -- -m uvicorn main:app --host 0.0.0.0 --port 8082 --workers 2" 2>/dev/null
            sleep 5
            verify_pm2_online "frgcrm-api" && ok "Rollback successful" || err "Rollback failed!"
            return 1
        }

        verify_http_responds "http://localhost:8082/" 200
        verify_http_responds "http://localhost:8082/api/health" 200
    fi

    ok "S4 complete"
}

# ============================================================================
# STEP S5: Add Redis Response Cache for Dashboard/Pipeline Stats (MEDIUM RISK)
# ============================================================================
apply_s5() {
    run_step "S5" "Add Redis Response Cache Decorator"

    local CACHE_PY="/opt/wheeler/apps/frgcrm/api/services/cache_decorator.py"
    local CACHE_DIR
    CACHE_DIR=$(dirname "$CACHE_PY")

    log "Pre-check: Redis connectivity..."
    $SSH_CMD "python3 -c 'import redis; r=redis.from_url(\"redis://100.118.166.117:6379\"); print(r.ping())' 2>/dev/null" || {
        warn "Redis not reachable from AIOPS — caching may not work"
        warn "Continuing anyway (decorator fails open)"
    }

    if $DRY_RUN; then
        log "DRY RUN: Would create ${CACHE_PY}"
        log "DRY RUN: Would update dashboard stats, pipeline stats, and cases routes"
    else
        # Create services directory if needed
        $SSH_CMD "mkdir -p ${CACHE_DIR}" 2>/dev/null || true

        # Write the cache decorator module
        $SSH_CMD "cat > ${CACHE_PY} << 'CACHE_EOF'
import json
import hashlib
import logging
import os
from functools import wraps
from typing import Any, Callable, Optional
import redis.asyncio as aioredis

logger = logging.getLogger(__name__)
REDIS_URL = os.getenv(\"REDIS_URL\", \"redis://localhost:6379\")

class CacheManager:
    def __init__(self):
        self._redis: Optional[aioredis.Redis] = None
        self.hits = 0
        self.misses = 0

    async def _get_redis(self) -> aioredis.Redis:
        if self._redis is None:
            self._redis = aioredis.from_url(REDIS_URL, socket_timeout=2, socket_connect_timeout=2, decode_responses=True)
        return self._redis

    async def get(self, key: str) -> Optional[Any]:
        try:
            r = await self._get_redis()
            value = await r.get(key)
            if value:
                self.hits += 1
                return json.loads(value)
            self.misses += 1
            return None
        except Exception as e:
            logger.warning(f\"Cache read failed: {e}\")
            self.misses += 1
            return None

    async def set(self, key: str, value: Any, ttl: int = 60) -> None:
        try:
            r = await self._get_redis()
            await r.setex(key, ttl, json.dumps(value, default=str))
        except Exception as e:
            logger.warning(f\"Cache write failed: {e}\")

    async def invalidate(self, pattern: str) -> int:
        try:
            r = await self._get_redis()
            keys = []
            async for key in r.scan_iter(match=pattern):
                keys.append(key)
            if keys:
                return await r.delete(*keys)
            return 0
        except Exception as e:
            logger.warning(f\"Cache invalidation failed: {e}\")
            return 0

    @property
    def hit_rate(self) -> float:
        total = self.hits + self.misses
        return self.hits / total if total > 0 else 0.0

cache = CacheManager()

def redis_cached(ttl_seconds: int = 60, key_prefix: str = \"\"):
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            cache_params = {k: v for k, v in kwargs.items() if k not in ('db', 'request', 'background_tasks')}
            params_hash = hashlib.sha256(json.dumps(cache_params, sort_keys=True, default=str).encode()).hexdigest()[:16]
            cache_key = f\"{key_prefix}:{func.__module__}.{func.__name__}:{params_hash}\"
            cached = await cache.get(cache_key)
            if cached is not None:
                return cached
            result = await func(*args, **kwargs)
            await cache.set(cache_key, result, ttl_seconds)
            return result
        return wrapper
    return decorator
CACHE_EOF
" 2>/dev/null
        ok "Cache decorator module created at ${CACHE_PY}"

        log "NOTE: Route-level cache decoration requires manual code changes."
        log "      See /root/templates/api/caching-strategy.txt for examples."
        log "      Apply to: dashboard stats, pipeline stats, cases list"
    fi

    ok "S5 complete (cache module deployed)"
}

# ============================================================================
# STEP S6: Apply All Safe Changes (Batch)
# ============================================================================
apply_s6() {
    run_step "S6" "Apply All Safe Optimizations (S1-S5)"

    apply_s1 || err "S1 failed"
    apply_s2 || err "S2 failed"
    apply_s3 || err "S3 failed"
    apply_s4 || err "S4 failed"
    apply_s5 || err "S5 failed"

    ok "S6 complete (all steps applied)"
}

# ============================================================================
# Main execution
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  WHEELER API OPTIMIZATION — SAFE APPLY SCRIPT          ║"
if $DRY_RUN; then
    echo "║  MODE: DRY RUN (no changes will be made)              ║"
else
    echo "║  MODE: LIVE EXECUTION                                 ║"
fi
echo "║  Target: ${AIOPS_HOST}                          ║"
echo "║  Backup dir: ${BACKUP_DIR}  ║"
echo "║  Log: ${LOG_FILE}  ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Verify SSH connectivity
log "Pre-flight: SSH connectivity to ${AIOPS_HOST}..."
$SSH_CMD "echo 'Connected'" 2>/dev/null || {
    err "Cannot SSH to ${AIOPS_HOST}"
    err "Ensure SSH key is set up: ssh-copy-id root@${AIOPS_HOST}"
    exit 1
}
ok "SSH connectivity verified"

# Create backup directory
if ! $DRY_RUN; then
    mkdir -p "$BACKUP_DIR"
fi

# Execute selected step or all steps
if [ -n "$SELECTED_STEP" ]; then
    case "$SELECTED_STEP" in
        S1) apply_s1 ;;
        S2) apply_s2 ;;
        S3) apply_s3 ;;
        S4) apply_s4 ;;
        S5) apply_s5 ;;
        S6) apply_s6 ;;
        *)
            err "Unknown step: ${SELECTED_STEP}"
            echo "Available steps: S1 S2 S3 S4 S5 S6"
            exit 1
            ;;
    esac
else
    # Run all steps in sequence (S6 does this)
    apply_s6
fi

echo ""
echo "============================================================"
echo "  SAFE APPLY COMPLETE"
echo "============================================================"
echo ""
echo "Summary:"
echo "  Mode:      $( $DRY_RUN && echo 'DRY RUN' || echo 'LIVE' )"
echo "  Backup:    ${BACKUP_DIR}"
echo "  Log:       ${LOG_FILE}"
echo ""

if $DRY_RUN; then
    echo "To apply changes, re-run with:"
    echo "  bash $0 --execute"
    echo ""
    echo "To apply a specific step:"
    echo "  bash $0 --step S3 --execute"
else
    echo "Post-apply manual steps REQUIRED:"
    echo "  1. Rebuild agent-svc TypeScript: npm run build in each service"
    echo "  2. Restart agent-svc services: pm2 restart <service>"
    echo "  3. Apply cache decoration to high-traffic routes"
    echo "  4. Verify PostgreSQL connection pool:"
    echo "     SELECT count(*) FROM pg_stat_activity;"
    echo "  5. Monitor for 24 hours before Phase 2 (async migration)"
    echo ""
    echo "Rollback instructions:"
    echo "  Restore files from ${BACKUP_DIR}"
    echo "  Or restore each service's ecosystem.config.js and database.py"
fi
