#!/usr/bin/env bash
# =============================================================================
# backup-all.sh — Master Backup Orchestrator for Wheeler Ecosystem
# =============================================================================
# Calls all 4 backup scripts in sequence:
#   1. backup-postgres.sh — PostgreSQL databases
#   2. backup-redis.sh — Redis snapshots
#   3. backup-configs.sh — Configuration files + PM2 state
#   4. backup-neo4j.sh — Neo4j graph database
# Reports success/failure for each.
# Exit code: 0 only if ALL four pass.
# Logs summary to /root/backups/backup-summary.log
# =============================================================================
set -o pipefail
set -o nounset

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SUMMARY_LOG="/root/backups/backup-summary.log"
readonly START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
readonly START_EPOCH="$(date +%s)"

# ---- Results tracking ----
declare -A RESULTS
declare -A DURATIONS

# ---- Logging ----
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "${msg}" | tee -a "${SUMMARY_LOG}"
}

# ---- Run a backup script and capture result ----
run_backup() {
    local name="$1"
    local script="$2"
    local phase_start
    phase_start="$(date +%s)"

    log ">>> Starting: ${name}"
    log "    Script: ${script}"

    if [[ ! -x "${script}" ]]; then
        log "    ERROR: Script not found or not executable: ${script}"
        RESULTS["${name}"]="FAILED (missing script)"
        DURATIONS["${name}"]=0
        return 1
    fi

    # Run the script, capture output to both terminal and log
    if "${script}" >> "${SUMMARY_LOG}" 2>&1; then
        local rc=0
        RESULTS["${name}"]="PASSED"
    else
        local rc=$?
        RESULTS["${name}"]="FAILED (exit code: ${rc})"
    fi

    local phase_end
    phase_end="$(date +%s)"
    DURATIONS["${name}"]=$((phase_end - phase_start))

    log "    Result: ${RESULTS[${name}]} (took ${DURATIONS[${name}]}s)"
    return ${rc}
}

# ---- Main ----
main() {
    local overall_ok=true

    mkdir -p "$(dirname "${SUMMARY_LOG}")"
    mkdir -p /root/backups/postgres
    mkdir -p /root/backups/redis
    mkdir -p /root/backups/configs
    mkdir -p /root/backups/neo4j

    # Header
    log "============================================================"
    log "WHEELER ECOSYSTEM FULL BACKUP"
    log "Started: ${START_TIME}"
    log "Host: $(hostname)"
    log "============================================================"
    log ""

    # ---- Phase 1: PostgreSQL ----
    run_backup "PostgreSQL" "${SCRIPT_DIR}/backup-postgres.sh" || overall_ok=false

    # ---- Phase 2: Redis ----
    run_backup "Redis" "${SCRIPT_DIR}/backup-redis.sh" || overall_ok=false

    # ---- Phase 3: Configs ----
    run_backup "Configurations" "${SCRIPT_DIR}/backup-configs.sh" || overall_ok=false

    # ---- Phase 4: Neo4j ----
    run_backup "Neo4j" "${SCRIPT_DIR}/backup-neo4j.sh" || overall_ok=false

    # ---- Summary ----
    local end_epoch
    end_epoch="$(date +%s)"
    local total_duration=$((end_epoch - START_EPOCH))
    local end_time
    end_time="$(date '+%Y-%m-%d %H:%M:%S')"

    log ""
    log "============================================================"
    log "BACKUP SUMMARY"
    log "============================================================"
    log "Completed: ${end_time}"
    log "Total duration: ${total_duration}s"
    log ""

    for phase in "PostgreSQL" "Redis" "Configurations" "Neo4j"; do
        local status="${RESULTS[${phase}]:-NOT RUN}"
        local dur="${DURATIONS[${phase}]:-0}"
        log "  ${phase}: ${status} (${dur}s)"
    done

    log ""

    # Size report
    log "Backup storage usage:"
    for dir in postgres redis configs neo4j; do
        if [[ -d "/root/backups/${dir}" ]]; then
            local size
            size="$(du -sh "/root/backups/${dir}" 2>/dev/null | cut -f1)"
            log "  /root/backups/${dir}: ${size}"
        fi
    done
    log "  Total: $(du -sh /root/backups 2>/dev/null | cut -f1)"

    log ""
    if ${overall_ok}; then
        log "OVERALL RESULT: ALL BACKUPS PASSED"
        log "============================================================"
        return 0
    else
        log "OVERALL RESULT: SOME BACKUPS FAILED (see details above)"
        log "============================================================"
        return 1
    fi
}

main "$@"
