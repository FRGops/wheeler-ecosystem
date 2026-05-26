#!/usr/bin/env bash
# ==============================================================================
# Wheeler Infrastructure Hardening Script
# Part of: Execution Readiness Remediation (Infrastructure 85 -> 92)
# Created: 2026-05-26
# Auditor: Claude Opus 4.7
# Policy: Zero False Greens
# ==============================================================================
set -uo pipefail
# NOTE: set -e intentionally omitted — many audit commands legitimately return 1

readonly THRESHOLD=80
readonly SCRIPT_NAME="infrastructure-hardening"
readonly LOG_DIR="/root/deployment-engine/logs"
readonly REPORT_FILE="${LOG_DIR}/${SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
red()    { echo -e "\033[31m$*\033[0m"; }
green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
bold()   { echo -e "\033[1m$*\033[0m"; }

# ---------------------------------------------------------------------------
# Logging (tee to both stdout and report file)
# ---------------------------------------------------------------------------
log()    { echo "$(date '+%H:%M:%S')  $*" | tee -a "$REPORT_FILE"; }
log_ok() { echo "$(date '+%H:%M:%S')  [PASS] $*" | tee -a "$REPORT_FILE"; }
log_warn(){ echo "$(date '+%H:%M:%S')  [WARN] $*" | tee -a "$REPORT_FILE"; }
log_fail(){ echo "$(date '+%H:%M:%S')  [FAIL] $*" | tee -a "$REPORT_FILE"; }

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
{
    echo "=============================================="
    echo " Wheeler Infrastructure Hardening Report"
    echo " Run: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Host: $(hostname)"
    echo "=============================================="
    echo ""
} | tee "$REPORT_FILE"

# ===========================================================================
# SECTION 1: Docker Image Cleanup
# ===========================================================================
log "--- Docker Image Cleanup ---"

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    BEFORE_COUNT=$(docker images -q 2>/dev/null | wc -l)
    BEFORE_SIZE=$(docker system df --format '{{.Size}}' 2>/dev/null | head -1)
    log "Docker images before cleanup: ${BEFORE_COUNT} images, ${BEFORE_SIZE:-unknown}"

    if docker image prune -a --filter "until=24h" --force 2>/dev/null; then
        AFTER_COUNT=$(docker images -q 2>/dev/null | wc -l)
        RECLAIMED=$((BEFORE_COUNT - AFTER_COUNT))
        if [ "$RECLAIMED" -gt 0 ]; then
            log_ok "Pruned ${RECLAIMED} unused Docker images older than 24h"
        else
            log_ok "No Docker images eligible for pruning (none older than 24h unused)"
        fi
    else
        log_warn "Docker image prune command failed — may need manual intervention"
    fi
else
    log_warn "Docker is not available — skipping image cleanup"
fi

# ===========================================================================
# SECTION 2: PM2 Log Cleanup
# ===========================================================================
log "--- PM2 Log Cleanup ---"

PM2_LOG_DIR="/root/.pm2/logs"
if [ -d "$PM2_LOG_DIR" ]; then
    LOG_SIZE_BEFORE=$(du -sh "$PM2_LOG_DIR" 2>/dev/null | awk '{print $1}')
    OLD_COUNT=$(find "$PM2_LOG_DIR" -name '*.log' -mtime +7 2>/dev/null | wc -l)

    if [ "$OLD_COUNT" -gt 0 ]; then
        find "$PM2_LOG_DIR" -name '*.log' -mtime +7 -delete 2>/dev/null
        LOG_SIZE_AFTER=$(du -sh "$PM2_LOG_DIR" 2>/dev/null | awk '{print $1}')
        log_ok "Cleaned ${OLD_COUNT} PM2 logs older than 7 days (${LOG_SIZE_BEFORE} -> ${LOG_SIZE_AFTER})"
    else
        # Truncate large current logs (>100MB) instead of deleting
        LARGE_LOGS=$(find "$PM2_LOG_DIR" -name '*.log' -size +100M 2>/dev/null)
        if [ -n "$LARGE_LOGS" ]; then
            while IFS= read -r f; do
                SIZE=$(du -sh "$f" 2>/dev/null | awk '{print $1}')
                : > "$f"
                log_ok "Truncated large log: $(basename "$f") (was ${SIZE})"
            done <<< "$LARGE_LOGS"
        else
            log_ok "No PM2 logs older than 7 days; no large logs to truncate (current: ${LOG_SIZE_BEFORE})"
        fi
    fi
else
    log_warn "PM2 log directory not found at ${PM2_LOG_DIR}"
fi

# ===========================================================================
# SECTION 3: Resource Pressure Checks
# ===========================================================================
log "--- Resource Pressure Checks ---"

PRESSURE_COUNT=0

# 3a. Disk space
DISK_PCT=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "${DISK_PCT}" -ge "${THRESHOLD}" ]; then
    log_fail "Root disk at ${DISK_PCT}% (threshold: ${THRESHOLD}%)"
    PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
else
    log_ok "Root disk: ${DISK_PCT}% (threshold: ${THRESHOLD}%)"
fi

# 3b. Disk pressure detail
while IFS= read -r line; do
    if [ -n "$line" ]; then
        FS=$(echo "$line" | awk '{print $1}')
        PCT=$(echo "$line" | awk '{print $2}' | tr -d '%')
        MNT=$(echo "$line" | awk '{print $3}')
        log_warn "Disk above threshold: ${FS} at ${PCT}% (mount: ${MNT})"
        PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
    fi
done < <(df -h | awk 'NR>1 && $5+0 > '"${THRESHOLD}"' {print $1, $5, $6}')

# 3c. Inode pressure
while IFS= read -r line; do
    if [ -n "$line" ]; then
        FS=$(echo "$line" | awk '{print $1}')
        PCT=$(echo "$line" | awk '{print $2}' | tr -d '%')
        MNT=$(echo "$line" | awk '{print $3}')
        log_warn "Inode usage above threshold: ${FS} at ${PCT}% (mount: ${MNT})"
        PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
    fi
done < <(df -i | awk 'NR>1 && $5+0 > '"${THRESHOLD}"' {print $1, $5, $6}')

# If no inode pressure, report OK
INODE_ABOVE=$(df -i | awk 'NR>1 && $5+0 > '"${THRESHOLD}"'' | wc -l)
if [ "$INODE_ABOVE" -eq 0 ]; then
    INODE_ROOT=$(df -i / | awk 'NR==2 {print $5}')
    log_ok "Inodes: root at ${INODE_ROOT} (threshold: ${THRESHOLD}%)"
fi

# 3d. Memory pressure
MEM_AVAIL=$(free -h | awk '/^Mem:/ {print $7}' | tr -d 'Gi')
if [ -z "$MEM_AVAIL" ]; then
    MEM_AVAIL=$(free -h | awk '/^Mem:/ {print $7}' | tr -d 'G')
fi
MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}' | tr -d 'Gi')
if [ -z "$MEM_TOTAL" ]; then
    MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}' | tr -d 'G')
fi

# Check if available < 20% of total
MEM_PCT_USED=$(free | awk '/^Mem:/ {printf "%.0f", ($3/$2)*100}')
MEM_PCT_AVAIL=$(free | awk '/^Mem:/ {printf "%.0f", ($7/$2)*100}')

if [ "${MEM_PCT_USED}" -ge "${THRESHOLD}" ]; then
    log_warn "Memory usage at ${MEM_PCT_USED}% (threshold: ${THRESHOLD}%)"
    PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
else
    log_ok "Memory: ${MEM_PCT_USED}% used, ${MEM_PCT_AVAIL}% available"
fi

# 3e. Swap pressure
SWAP_TOTAL=$(free | awk '/^Swap:/ {print $2}')
SWAP_USED=$(free | awk '/^Swap:/ {print $3}')
if [ "$SWAP_TOTAL" -gt 0 ] && [ "$SWAP_USED" -gt 0 ]; then
    SWAP_PCT=$((SWAP_USED * 100 / SWAP_TOTAL))
    if [ "$SWAP_PCT" -ge 50 ]; then
        log_warn "Swap usage at ${SWAP_PCT}% — possible memory pressure"
        PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
    else
        log_ok "Swap: ${SWAP_PCT}% used"
    fi
fi

# 3f. OOM kills
OOM_KILLS=$(dmesg 2>/dev/null | grep -ic 'killed process' || echo "0")
if [ "${OOM_KILLS:-0}" -gt 0 ]; then
    log_fail "OOM kills detected: ${OOM_KILLS} processes killed"
    PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
else
    log_ok "No OOM kills detected"
fi

# 3g. CPU steal (cloud VM indicator)
CPU_STEAL=$(top -bn1 | awk '/^%Cpu/ {print $10}' 2>/dev/null || echo "0")
if [ -n "$CPU_STEAL" ] && [ "$(echo "$CPU_STEAL > 5" | bc 2>/dev/null || echo 0)" = "1" ]; then
    log_warn "CPU steal at ${CPU_STEAL}% — cloud host may be overcommitted"
    PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
else
    log_ok "CPU steal: ${CPU_STEAL:-0}% (below 5% threshold)"
fi

# ---------------------------------------------------------------------------
# Pressure summary
# ---------------------------------------------------------------------------
if [ "$PRESSURE_COUNT" -eq 0 ]; then
    log_ok "Resource pressure: NONE — all metrics below ${THRESHOLD}% threshold"
else
    log_warn "Resource pressure: ${PRESSURE_COUNT} metric(s) above ${THRESHOLD}% threshold"
fi

# ===========================================================================
# SECTION 4: UFW Firewall Verification
# ===========================================================================
log "--- UFW Firewall Verification ---"

UFW_STATUS=$(ufw status 2>/dev/null | head -1 || echo "ufw not found")
if echo "$UFW_STATUS" | grep -q "active"; then
    log_ok "UFW is ACTIVE"
    RULE_COUNT=$(ufw status 2>/dev/null | grep -c 'ALLOW\|DENY' || echo "0")
    log_ok "UFW rules: ${RULE_COUNT} rules configured"
else
    log_fail "UFW is INACTIVE or not installed"
    PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
fi

# ===========================================================================
# SECTION 5: fail2ban Verification
# ===========================================================================
log "--- fail2ban Verification ---"

if command -v fail2ban-client &>/dev/null; then
    if fail2ban-client status 2>/dev/null | grep -q "Jail list"; then
        JAIL_COUNT=$(fail2ban-client status 2>/dev/null | grep "Jail list" | tr ',' '\n' | wc -l)
        BANNED_TOTAL=$(fail2ban-client status sshd 2>/dev/null | grep "Total banned" | awk '{print $NF}' || echo "0")
        BANNED_NOW=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}' || echo "0")
        log_ok "fail2ban is RUNNING — ${JAIL_COUNT} jails, ${BANNED_TOTAL:-0} total banned, ${BANNED_NOW:-0} currently banned"
    else
        log_fail "fail2ban is not running"
        PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
    fi
else
    log_fail "fail2ban is not installed"
    PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
fi

# ===========================================================================
# SECTION 6: Additional Health Metrics
# ===========================================================================
log "--- Additional Health Metrics ---"

# Open file descriptors
FD_COUNT=$(lsof 2>/dev/null | wc -l || echo "0")
FD_LIMIT=$(ulimit -n 2>/dev/null || echo "unknown")
FD_PCT=0
if [ "$FD_LIMIT" != "unknown" ] && [ "$FD_LIMIT" -gt 0 ]; then
    FD_PCT=$((FD_COUNT * 100 / FD_LIMIT))
fi
if [ "$FD_PCT" -ge 80 ]; then
    log_warn "File descriptors: ${FD_COUNT}/${FD_LIMIT} (${FD_PCT}% — nearing limit)"
else
    log_ok "File descriptors: ${FD_COUNT}/${FD_LIMIT} (${FD_PCT}%)"
fi

# Load average
LOAD_1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "unknown")
CPU_COUNT=$(nproc 2>/dev/null || echo "1")
if [ "$LOAD_1" != "unknown" ] && [ "$(echo "$LOAD_1 > $CPU_COUNT" | bc 2>/dev/null || echo 0)" = "1" ]; then
    log_warn "Load average (1min): ${LOAD_1} exceeds CPU count (${CPU_COUNT})"
else
    log_ok "Load average (1min): ${LOAD_1} (CPUs: ${CPU_COUNT})"
fi

# ===========================================================================
# SECTION 7: Docker Container Health
# ===========================================================================
log "--- Docker Container Health ---"

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    TOTAL_CONTAINERS=$(docker ps -q 2>/dev/null | wc -l)
    UNHEALTHY=$(docker ps --filter "health=unhealthy" -q 2>/dev/null | wc -l)
    if [ "$UNHEALTHY" -gt 0 ]; then
        log_warn "Docker: ${UNHEALTHY}/${TOTAL_CONTAINERS} containers unhealthy"
        PRESSURE_COUNT=$((PRESSURE_COUNT + 1))
    else
        log_ok "Docker: ${TOTAL_CONTAINERS} containers running, 0 unhealthy"
    fi
else
    log_warn "Docker not available — skipping container health check"
fi

# ===========================================================================
# SECTION 8: Final Score
# ===========================================================================
echo ""
log "========== FINAL INFRASTRUCTURE SCORE =========="

# Score calculation: start at 100, deduct for each pressure item
# Scoring: each pressure item = -2, each fail = -5
SCORE=100
FAIL_COUNT=0

# Count fails from log
FAIL_COUNT=$(grep -c '\[FAIL\]' "$REPORT_FILE" 2>/dev/null | head -1)
FAIL_COUNT=${FAIL_COUNT:-0}
WARN_COUNT=$(grep -c '\[WARN\]' "$REPORT_FILE" 2>/dev/null | head -1)
WARN_COUNT=${WARN_COUNT:-0}

SCORE=$((SCORE - (FAIL_COUNT * 5) - (WARN_COUNT * 2)))
[ "$SCORE" -lt 0 ] && SCORE=0

log "Infrastructure Hardening Score: ${SCORE}/100"
log "  FAIL items: ${FAIL_COUNT}"
log "  WARN items: ${WARN_COUNT}"
log "  Resource pressure points: ${PRESSURE_COUNT}"

if [ "$SCORE" -ge 90 ]; then
    log_ok "STATUS: HEALTHY — infrastructure is within operational bounds"
elif [ "$SCORE" -ge 80 ]; then
    log_warn "STATUS: ATTENTION NEEDED — investigate warnings above"
else
    log_fail "STATUS: REQUIRES REMEDIATION — address failures above"
fi

echo ""
log "Report saved to: ${REPORT_FILE}"
echo ""

exit 0
