#!/usr/bin/env bash
#
# autoheal.sh — Wheeler Enterprise Self-Healing Daemon
# Target: Ubuntu 24.04 | 16 cores | 30GB RAM | 338GB disk
# Schedule: every 60 seconds via cron (use --once)  or  --daemon for infinite loop
#
# Responsibilities:
#   1.  Restart crashed / unhealthy Docker containers
#   2.  Restart errored / stopped PM2 apps (with restart-loop detection)
#   3.  Restart-loop detection for containers (cooldown after 5 restarts in 10 min)
#   4.  Disk-pressure alerts & auto-prune
#   5.  Memory-pressure handling (low MemAvailable, swap usage)
#   6.  Stalled-container detection (curl health endpoints)
#   7.  Zombie-process reaping
#   8.  Network-failure detection (Tailscale mesh to EDGE)
#   9.  Tailscale reconnect
#  10.  Auto-snapshots before DB-container restarts
#  11.  Rollback triggers after repeated failures
#  12.  Stale-lock / cooldown cleanup
#
# Usage:
#   DRY_RUN=1 ./autoheal.sh --once      # cron entry
#   ./autoheal.sh --daemon              # foreground infinite loop
#   ./autoheal.sh --once                # single pass and exit
# ---------------------------------------------------------------------------

set -euo pipefail

# ------------------------------------------------------------------ config --
LOG_DIR="/var/log/wheeler"
LOG_FILE="${LOG_DIR}/autoheal.log"
LOCK_FILE="/tmp/autoheal.lock"
PM2_COUNT_FILE="/tmp/autoheal-pm2-counts.txt"
RESTART_WINDOW_SECONDS=600        # 10 minutes
MAX_RESTARTS_IN_WINDOW=5
STALE_LOCK_TIMEOUT=3600           # 1 hour
COOLDOWN_TIMEOUT=1800             # 30 minutes
DISK_WARN_PCT=85
DISK_PRUNE_PCT=92
DISK_CRITICAL_PCT=95
MEM_WARN_AVAILABLE_PCT=10
SWAP_WARN_PCT=50
ZOMBIE_WARN_COUNT=10
ZOMBIE_REAP_COUNT=50
STALL_TIMEOUT_SECONDS=10
PING_COUNT=3
EDGE_TAILSCALE_IP="100.98.163.17"

# Essential containers — never stop these for memory-pressure handling
ESSENTIAL_CONTAINERS=("postgres" "redis" "prometheus")

# Database containers that get a snapshot before restart
DB_CONTAINERS=("postgres" "redis")

# Known health-check URLs for stalled-container detection
# Format:  container_name|endpoint
declare -A HEALTH_ENDPOINTS=(
    ["frigate"]="http://localhost:5000/api/health"
    ["homeassistant"]="http://localhost:8123/api/"
    ["nodered"]="http://localhost:1880/health"
    ["prometheus"]="http://localhost:9090/-/healthy"
    ["grafana"]="http://localhost:3000/api/health"
)

# PM2 apps we expect to be running
EXPECTED_PM2_APPS=(
    "frgcrm-agent-svc"
    "frgcrm-api"
    "frgcrm-mirror-test"
    "insforge-agent-svc"
    "surplusai-scraper-agent-svc"
    "voice-agent-svc"
)

# ------------------------------------------------------------------ helpers --
now_ts()  { date +%s; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log_json() {
    # Args:  $1=action  $2=target  $3=status  $4=reason
    local action="${1:-unknown}"
    local target="${2:-unknown}"
    local status="${3:-info}"
    local reason="${4:-}"

    # Reason may contain quotes; escape them
    local escaped_reason
    escaped_reason=$(printf '%s' "${reason}" | sed 's/"/\\"/g' )

    printf '[%s] %s\n' "$(now_iso)" \
        "$(printf '{"timestamp":"%s","action":"%s","target":"%s","status":"%s","reason":"%s"}' \
            "$(now_iso)" "${action}" "${target}" "${status}" "${escaped_reason}")" \
        >> "${LOG_FILE}"
}

dry_run_check() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log_json "dry_run_skip" "$1" "skipped" "DRY_RUN=1"
        return 0   # "yes, this is a dry run"
    fi
    return 1       # "proceed with real action"
}

alert_wall() {
    local msg="$1"
    if command -v wall &>/dev/null; then
        echo "AUTOHEAL ALERT: ${msg}" | wall 2>/dev/null || true
    fi
}

ensure_log_dir() {
    if [[ ! -d "${LOG_DIR}" ]]; then
        mkdir -p "${LOG_DIR}" 2>/dev/null || {
            echo "FATAL: cannot create log directory ${LOG_DIR}" >&2
            exit 1
        }
    fi
    if [[ ! -f "${LOG_FILE}" ]]; then
        touch "${LOG_FILE}" 2>/dev/null || true
    fi
}

# Write a run-level summary header
print_summary_header() {
    local header
    header="================================================================"
    printf '%s\n' "${header}" >> "${LOG_FILE}"
    printf '[%s] AUTOHEAL RUN START -- mode=%s pid=%s\n' \
        "$(now_iso)" "${RUN_MODE:-once}" "$$" >> "${LOG_FILE}"
    printf '%s\n' "${header}" >> "${LOG_FILE}"
}

print_summary_footer() {
    local header
    header="================================================================"
    printf '%s\n' "${header}" >> "${LOG_FILE}"
    printf '[%s] AUTOHEAL RUN END   -- healed=%d actions=%d alerts=%d\n' \
        "$(now_iso)" "${HEAL_COUNT:-0}" "${ACTION_COUNT:-0}" "${ALERT_COUNT:-0}" >> "${LOG_FILE}"
    printf '%s\n\n' "${header}" >> "${LOG_FILE}"
}

# Increment a counter (global, numeric)
inc_counter() {
    local varname="$1"
    printf -v "${varname}" '%d' "$(( ${!varname:-0} + 1 ))"
}

# ------------------------------------------------------------------ locks ----
acquire_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_age
        lock_age=$(($(now_ts) - $(stat -c %Y "${LOCK_FILE}" 2>/dev/null || echo 0)))
        if [[ ${lock_age} -lt 120 ]]; then
            echo "Another autoheal instance holds the lock (age=${lock_age}s). Exiting." >&2
            exit 0
        fi
        # Stale lock — take it over
        log_json "lock_override" "lock" "warning" "stale lock age=${lock_age}s, overriding"
    fi
    echo "$$" > "${LOCK_FILE}"
}

release_lock() {
    rm -f "${LOCK_FILE}" 2>/dev/null || true
}

cleanup_stale_locks() {
    log_json "cleanup" "stale_locks" "info" "purging stale lock/cooldown files"

    # Clean *-counts tmp files older than 1 hour
    find /tmp -maxdepth 1 -name 'autoheal-*.tmp' -mmin +60 -delete 2>/dev/null || true

    # Clean cooldown files older than 30 minutes
    find /tmp -maxdepth 1 -name 'autoheal-cooldown-*' -mmin +30 -delete 2>/dev/null || true

    # Clean snapshots older than 2 hours
    find /tmp -maxdepth 1 -name 'autoheal-snapshot-*' -mmin +120 -delete 2>/dev/null || true
}

# ------------------------------------------------------------------ restart counters ---
# Update restart count for a given key.  Returns 0 if under threshold, 1 if over.
# Format in count file:   <key>:<epoch_restart1>,<epoch_restart2>,...
update_restart_count() {
    local key="$1"           # e.g. "container:foo" or "pm2:bar"
    local now
    now=$(now_ts)
    local cutoff=$(( now - RESTART_WINDOW_SECONDS ))

    local entries=""
    if [[ -f "${PM2_COUNT_FILE}" ]]; then
        entries=$(grep "^${key}:" "${PM2_COUNT_FILE}" 2>/dev/null || true)
    fi

    if [[ -z "${entries}" ]]; then
        # First restart for this key
        echo "${key}:${now}" >> "${PM2_COUNT_FILE}"
        return 0
    fi

    # Extract existing timestamps, filter to window, append new
    local timestamps
    timestamps=$(echo "${entries}" | cut -d: -f2)
    local new_list=()
    IFS=',' read -ra TS_ARRAY <<< "${timestamps}"
    for ts in "${TS_ARRAY[@]}"; do
        if [[ ${ts} -ge ${cutoff} ]]; then
            new_list+=("${ts}")
        fi
    done
    new_list+=("${now}")

    # Rebuild the line
    local new_entry
    new_entry="${key}:$(IFS=','; echo "${new_list[*]}")"

    # Write updated file
    grep -v "^${key}:" "${PM2_COUNT_FILE}" > "${PM2_COUNT_FILE}.tmp" 2>/dev/null || true
    echo "${new_entry}" >> "${PM2_COUNT_FILE}.tmp"
    mv "${PM2_COUNT_FILE}.tmp" "${PM2_COUNT_FILE}"

    if [[ ${#new_list[@]} -gt ${MAX_RESTARTS_IN_WINDOW} ]]; then
        return 1   # over threshold
    fi
    return 0
}

in_cooldown() {
    local key="$1"
    local file="/tmp/autoheal-cooldown-${key}"
    [[ -f "${file}" ]]
}

set_cooldown() {
    local key="$1"
    local file="/tmp/autoheal-cooldown-${key}"
    touch "${file}"
    log_json "cooldown_set" "${key}" "cooldown" "exceeded ${MAX_RESTARTS_IN_WINDOW} restarts in ${RESTART_WINDOW_SECONDS}s"
    alert_wall "Cooldown activated for ${key} — manual intervention required"
}

# ------------------------------------------------------------------ (1) Docker containers ---
heal_containers() {
    inc_counter ACTION_COUNT
    log_json "check" "docker_containers" "info" "scanning for exited/unhealthy containers"

    local containers
    containers=$(docker ps -a --format '{{.Names}}|{{.Status}}' 2>/dev/null || true)

    if [[ -z "${containers}" ]]; then
        log_json "check" "docker_containers" "warn" "docker ps returned no output; is Docker running?"
        return
    fi

    while IFS='|' read -r name status; do
        [[ -z "${name}" ]] && continue

        # Check exited
        if echo "${status}" | grep -qi "exited"; then
            handle_unhealthy_container "${name}" "exited"
            continue
        fi

        # Check unhealthy
        if echo "${status}" | grep -qi "unhealthy"; then
            handle_unhealthy_container "${name}" "unhealthy"
            continue
        fi

        # Check restarting (potentially stuck)
        if echo "${status}" | grep -qi "restarting"; then
            log_json "detect" "${name}" "warn" "container is restarting — may be stuck in a loop"
        fi
    done <<< "${containers}"
}

handle_unhealthy_container() {
    local name="$1"
    local reason="$2"

    inc_counter HEAL_COUNT
    log_json "detect" "${name}" "unhealthy" "container status=${reason}"

    # Cooldown check
    if in_cooldown "container-${name}"; then
        log_json "skip" "${name}" "cooldown" "container is in cooldown"
        return
    fi

    # Restart counter
    if ! update_restart_count "container:${name}"; then
        # Over threshold — cooldown and possibly rollback
        log_json "threshold" "${name}" "critical" "restarted >${MAX_RESTARTS_IN_WINDOW} times in ${RESTART_WINDOW_SECONDS}s"
        alert_wall "Container ${name} restart loop detected"
        set_cooldown "container-${name}"

        # Rollback trigger (requirement 11)
        local rollback_file="/tmp/autoheal-rollback-request"
        printf '[%s] ROLLBACK REQUEST: container=%s restarts=%d window=%ds\n' \
            "$(now_iso)" "${name}" "${MAX_RESTARTS_IN_WINDOW}" "${RESTART_WINDOW_SECONDS}" \
            >> "${rollback_file}"
        log_json "rollback" "${name}" "requested" "written to ${rollback_file}"
        alert_wall "Rollback requested for container ${name} — check /tmp/autoheal-rollback-request"
        return
    fi

    # --- Snapshot DB containers before restart (requirement 10) ---
    if is_db_container "${name}"; then
        snapshot_db_container "${name}"
    fi

    # --- Restart ---
    if dry_run_check "restart_container:${name}"; then
        return
    fi

    log_json "restart" "${name}" "attempt" "docker restart ${name}"
    if docker restart "${name}" &>/dev/null; then
        log_json "restart" "${name}" "success" "docker restart completed"
    else
        inc_counter ALERT_COUNT
        log_json "restart" "${name}" "failure" "docker restart command failed"
        alert_wall "Failed to restart container ${name}"
    fi
}

# ------------------------------------------------------------------ (2) PM2 processes ---
heal_pm2() {
    inc_counter ACTION_COUNT
    log_json "check" "pm2_processes" "info" "scanning PM2 list"

    if ! command -v pm2 &>/dev/null; then
        log_json "check" "pm2_processes" "warn" "pm2 command not found, skipping"
        return
    fi

    local pm2_output
    pm2_output=$(pm2 list 2>/dev/null || true)

    if [[ -z "${pm2_output}" ]]; then
        log_json "check" "pm2_processes" "warn" "pm2 list empty — PM2 may not be running"
        return
    fi

    for app in "${EXPECTED_PM2_APPS[@]}"; do
        # PM2 output format varies; match on app name and status
        local status_line
        status_line=$(echo "${pm2_output}" | grep -F "${app}" || true)

        if [[ -z "${status_line}" ]]; then
            log_json "detect" "${app}" "missing" "PM2 app not found in pm2 list"
            continue
        fi

        # Status keywords: errored, stopped, waiting (restart loop)
        if echo "${status_line}" | grep -qiE "errored|stopped|waiting"; then
            handle_pm2_app "${app}" "${status_line}"
        fi
    done
}

handle_pm2_app() {
    local app="$1"
    local status_line="$2"

    inc_counter HEAL_COUNT
    log_json "detect" "${app}" "unhealthy" "PM2 status: $(echo "${status_line}" | tr -s ' ')"

    # Cooldown check
    if in_cooldown "pm2-${app}"; then
        log_json "skip" "${app}" "cooldown" "PM2 app in cooldown"
        return
    fi

    # Restart counter
    if ! update_restart_count "pm2:${app}"; then
        log_json "threshold" "${app}" "critical" "restarted >${MAX_RESTARTS_IN_WINDOW} times in ${RESTART_WINDOW_SECONDS}s"
        alert_wall "PM2 app ${app} restart loop detected — STOPPING auto-heal attempts"
        set_cooldown "pm2-${app}"

        local rollback_file="/tmp/autoheal-rollback-request"
        printf '[%s] ROLLBACK REQUEST: pm2_app=%s restarts=%d window=%ds\n' \
            "$(now_iso)" "${app}" "${MAX_RESTARTS_IN_WINDOW}" "${RESTART_WINDOW_SECONDS}" \
            >> "${rollback_file}"
        log_json "rollback" "${app}" "requested" "PM2 restart loop — manual intervention needed"
        alert_wall "Rollback requested for PM2 app ${app} — check /tmp/autoheal-rollback-request"
        return
    fi

    # Restart PM2 app
    if dry_run_check "restart_pm2:${app}"; then
        return
    fi

    log_json "restart" "${app}" "attempt" "pm2 restart ${app}"
    if pm2 restart "${app}" &>/dev/null; then
        log_json "restart" "${app}" "success" "pm2 restart completed"
    else
        inc_counter ALERT_COUNT
        log_json "restart" "${app}" "failure" "pm2 restart command failed"
        alert_wall "Failed to restart PM2 app ${app}"
    fi
}

# ------------------------------------------------------------------ (3) restart-loop detection integrated in (1) and (2) above ---

# ------------------------------------------------------------------ (4) disk pressure ---
heal_disk() {
    inc_counter ACTION_COUNT
    log_json "check" "disk_usage" "info" "checking disk pressure"

    local df_output
    df_output=$(df -h / 2>/dev/null || true)

    if [[ -z "${df_output}" ]]; then
        log_json "check" "disk_usage" "warn" "df command failed"
        return
    fi

    # Parse usage percentage (second line, fifth column)
    local pct
    pct=$(echo "${df_output}" | awk 'NR==2 {gsub(/%/,""); print $5}' 2>/dev/null || true)

    if [[ -z "${pct}" ]]; then
        log_json "check" "disk_usage" "warn" "could not parse usage percentage"
        return
    fi

    log_json "check" "disk_usage" "info" "disk usage=${pct}%"

    if [[ ${pct} -ge ${DISK_CRITICAL_PCT} ]]; then
        inc_counter ALERT_COUNT
        log_json "disk" "root_fs" "critical" "usage=${pct}% — stopping non-essential containers"
        alert_wall "DISK CRITICAL at ${pct}% — stopping non-essential containers to prevent DB corruption"

        if ! dry_run_check "stop_nonessential_containers:disk_critical"; then
            stop_nonessential_containers "disk_critical"
        fi
        return
    fi

    if [[ ${pct} -ge ${DISK_PRUNE_PCT} ]]; then
        inc_counter ALERT_COUNT
        log_json "disk" "root_fs" "warning" "usage=${pct}% — pruning Docker images"
        alert_wall "DISK WARNING at ${pct}% — pruning Docker images"

        if ! dry_run_check "docker_image_prune:disk_warn"; then
            docker image prune -a -f 2>&1 | tail -1 >> "${LOG_FILE}" 2>/dev/null || true
            log_json "disk" "root_fs" "pruned" "docker image prune -a -f executed"
        fi
        return
    fi

    if [[ ${pct} -ge ${DISK_WARN_PCT} ]]; then
        inc_counter ALERT_COUNT
        log_json "disk" "root_fs" "warning" "usage=${pct}% >= warn threshold ${DISK_WARN_PCT}%"
        alert_wall "Disk usage at ${pct}% — consider cleanup"
    fi
}

# ------------------------------------------------------------------ (5) memory pressure ---
heal_memory() {
    inc_counter ACTION_COUNT
    log_json "check" "memory_pressure" "info" "checking memory and swap"

    # MemAvailable
    local mem_total mem_available mem_available_pct
    mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    mem_available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)

    if [[ ${mem_total} -gt 0 ]]; then
        mem_available_pct=$(( mem_available * 100 / mem_total ))
    else
        mem_available_pct=100
    fi

    log_json "memory" "MemAvailable" "info" "available=${mem_available_pct}% of total"

    if [[ ${mem_available_pct} -lt ${MEM_WARN_AVAILABLE_PCT} ]]; then
        inc_counter ALERT_COUNT
        log_json "memory" "MemAvailable" "critical" "only ${mem_available_pct}% available — restarting memory-heavy non-essential containers"
        alert_wall "Memory critical: only ${mem_available_pct}% available — restarting non-essential containers"

        if ! dry_run_check "restart_memory_hungry"; then
            restart_memory_hungry_containers
        fi
    fi

    # Swap usage
    local swap_total swap_free swap_used swap_used_pct
    swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    swap_free=$(awk '/^SwapFree:/  {print $2}' /proc/meminfo 2>/dev/null || echo 0)

    if [[ ${swap_total} -gt 0 ]]; then
        swap_used=$(( swap_total - swap_free ))
        swap_used_pct=$(( swap_used * 100 / swap_total ))
    else
        swap_used_pct=0
    fi

    log_json "memory" "swap" "info" "swap_used=${swap_used_pct}%"

    if [[ ${swap_used_pct} -gt ${SWAP_WARN_PCT} ]]; then
        inc_counter ALERT_COUNT
        log_json "memory" "swap" "warning" "swap usage ${swap_used_pct}% > ${SWAP_WARN_PCT}%"
        alert_wall "High swap usage: ${swap_used_pct}% — system may be under memory pressure"
    fi
}

# Find the most memory-hungry non-essential containers and restart them
restart_memory_hungry_containers() {
    local top_mem_containers
    # docker stats returns: NAME CPU% MEM USAGE/LIMIT MEM% NET I/O BLOCK I/O PIDS
    top_mem_containers=$(docker stats --no-stream --format '{{.Name}}|{{.MemPerc}}' 2>/dev/null \
        | sort -t'|' -k2 -rn \
        | head -5 \
        || true)

    if [[ -z "${top_mem_containers}" ]]; then
        log_json "memory" "restart" "fail" "docker stats returned no data"
        return
    fi

    while IFS='|' read -r name mem_pct; do
        [[ -z "${name}" ]] && continue

        # Skip essential containers
        if is_essential_container "${name}"; then
            log_json "memory" "${name}" "skipped" "essential container — will not restart for memory pressure"
            continue
        fi

        inc_counter HEAL_COUNT
        log_json "memory" "${name}" "restart" "memory_hungry at ${mem_pct}"

        if dry_run_check "restart_mem:${name}"; then
            continue
        fi

        if docker restart "${name}" &>/dev/null; then
            log_json "restart" "${name}" "success" "restarted due to memory pressure"
        else
            log_json "restart" "${name}" "failure" "restart failed during memory pressure handling"
        fi
    done <<< "${top_mem_containers}"
}

# Stop all non-essential containers (used when disk is critically full)
stop_nonessential_containers() {
    local reason="${1:-unknown}"

    local all_containers
    all_containers=$(docker ps --format '{{.Names}}' 2>/dev/null || true)

    if [[ -z "${all_containers}" ]]; then
        return
    fi

    while IFS= read -r name; do
        [[ -z "${name}" ]] && continue

        if is_essential_container "${name}"; then
            log_json "disk_stop" "${name}" "skipped" "essential container preserved during disk-critical stop (${reason})"
            continue
        fi

        if dry_run_check "stop_container:${name}:${reason}"; then
            continue
        fi

        inc_counter HEAL_COUNT
        log_json "disk_stop" "${name}" "stopped" "non-essential container stopped due to ${reason}"
        docker stop "${name}" &>/dev/null || true
    done <<< "${all_containers}"
}

# ------------------------------------------------------------------ (6) stalled containers ---
heal_stalled_containers() {
    inc_counter ACTION_COUNT
    log_json "check" "stalled_containers" "info" "checking container health endpoints"

    for container_name in "${!HEALTH_ENDPOINTS[@]}"; do
        local endpoint="${HEALTH_ENDPOINTS[${container_name}]}"

        # Verify container is running
        local running
        running=$(docker ps --filter "name=${container_name}" --format '{{.Status}}' 2>/dev/null || true)
        if [[ -z "${running}" ]]; then
            # Container not running — handled by heal_containers()
            continue
        fi

        if ! echo "${running}" | grep -qi "up"; then
            continue
        fi

        # Try health endpoint
        local http_code
        http_code=$(curl -s -o /dev/null -w '%{http_code}' \
            --max-time "${STALL_TIMEOUT_SECONDS}" "${endpoint}" 2>/dev/null || echo "000")

        if [[ "${http_code}" == "000" ]]; then
            inc_counter HEAL_COUNT
            log_json "stalled" "${container_name}" "unresponsive" "health check to ${endpoint} timed out after ${STALL_TIMEOUT_SECONDS}s"
            alert_wall "Container ${container_name} appears stalled (health check timeout)"

            if in_cooldown "container-${container_name}"; then
                log_json "skip" "${container_name}" "cooldown" "stalled but in cooldown"
                continue
            fi

            if dry_run_check "restart_stalled:${container_name}"; then
                continue
            fi

            if docker restart "${container_name}" &>/dev/null; then
                log_json "restart" "${container_name}" "success" "restarted stalled container"
            else
                log_json "restart" "${container_name}" "failure" "failed to restart stalled container"
            fi
        elif [[ "${http_code}" -ge 500 ]]; then
            log_json "stalled" "${container_name}" "degraded" "health check returned HTTP ${http_code}"
        else
            log_json "stalled" "${container_name}" "healthy" "health check returned HTTP ${http_code}"
        fi
    done
}

# ------------------------------------------------------------------ (7) zombie processes ---
heal_zombies() {
    inc_counter ACTION_COUNT
    log_json "check" "zombie_processes" "info" "scanning for defunct processes"

    local zombie_count
    zombie_count=$(ps aux 2>/dev/null | grep -c '[d]efunct' | head -1)
    zombie_count=${zombie_count:-0}

    log_json "zombie" "count" "info" "zombie processes=${zombie_count}"

    if [[ ${zombie_count} -gt ${ZOMBIE_REAP_COUNT} ]]; then
        inc_counter ALERT_COUNT
        log_json "zombie" "reap" "critical" "zombie_count=${zombie_count} > ${ZOMBIE_REAP_COUNT} — restarting Docker daemon with live-restore"
        alert_wall "CRITICAL: ${zombie_count} zombie processes — restarting Docker daemon"

        if dry_run_check "docker_daemon_restart:zombies"; then
            return
        fi

        # Restart Docker daemon (containers stay up with live-restore)
        log_json "zombie" "docker" "attempt" "systemctl reload docker (with live-restore)"
        if systemctl reload docker &>/dev/null; then
            log_json "zombie" "docker" "success" "Docker daemon reloaded — zombies should be reaped"
        else
            log_json "zombie" "docker" "failure" "systemctl reload docker failed"
        fi
        return
    fi

    if [[ ${zombie_count} -gt ${ZOMBIE_WARN_COUNT} ]]; then
        inc_counter ALERT_COUNT
        log_json "zombie" "count" "warning" "zombie_count=${zombie_count} > ${ZOMBIE_WARN_COUNT}"
        alert_wall "Warning: ${zombie_count} zombie processes detected"
    fi
}

# ------------------------------------------------------------------ (8) network failure detection ---
heal_network() {
    inc_counter ACTION_COUNT
    log_json "check" "network" "info" "pinging EDGE Tailscale IP ${EDGE_TAILSCALE_IP}"

    local fail_count=0
    for ((i=1; i<=PING_COUNT; i++)); do
        if ! ping -c 1 -W 2 "${EDGE_TAILSCALE_IP}" &>/dev/null; then
            fail_count=$(( fail_count + 1 ))
        fi
    done

    if [[ ${fail_count} -ge ${PING_COUNT} ]]; then
        inc_counter ALERT_COUNT
        log_json "network" "${EDGE_TAILSCALE_IP}" "failure" "all ${PING_COUNT} pings failed"
        alert_wall "Network failure: cannot reach EDGE server (${EDGE_TAILSCALE_IP}) — attempting Tailscale reconnect"

        if dry_run_check "tailscale_up:network_fail"; then
            return
        fi

        log_json "network" "tailscale" "attempt" "running tailscale up"
        if tailscale up &>/dev/null; then
            log_json "network" "tailscale" "success" "tailscale up completed"
        else
            log_json "network" "tailscale" "failure" "tailscale up command failed"
        fi
    else
        log_json "network" "${EDGE_TAILSCALE_IP}" "ok" "pings: ${fail_count}/${PING_COUNT} failed"
    fi
}

# ------------------------------------------------------------------ (9) Tailscale status check ---
heal_tailscale() {
    inc_counter ACTION_COUNT
    log_json "check" "tailscale_status" "info" "checking tailscale status"

    if ! command -v tailscale &>/dev/null; then
        log_json "check" "tailscale" "warn" "tailscale command not found — skipping"
        return
    fi

    local ts_status
    ts_status=$(tailscale status 2>/dev/null || echo "offline")

    log_json "tailscale" "status" "info" "tailscale status: $(echo "${ts_status}" | head -1)"

    if echo "${ts_status}" | grep -qiE "stopped|offline|not.*running"; then
        inc_counter ALERT_COUNT
        log_json "tailscale" "reconnect" "attempt" "tailscale appears stopped/offline"
        alert_wall "Tailscale appears stopped/offline — attempting tailscale up"

        if dry_run_check "tailscale_up:status_offline"; then
            return
        fi

        if tailscale up &>/dev/null; then
            log_json "tailscale" "reconnect" "success" "tailscale up executed"
        else
            log_json "tailscale" "reconnect" "failure" "tailscale up failed"
        fi
    fi
}

# ------------------------------------------------------------------ (10) DB snapshots ---
is_db_container() {
    local name="$1"
    for db in "${DB_CONTAINERS[@]}"; do
        if echo "${name}" | grep -qi "${db}"; then
            return 0
        fi
    done
    return 1
}

snapshot_db_container() {
    local name="$1"
    local snapshot_file="/tmp/autoheal-snapshot-$(now_ts).sql"

    log_json "snapshot" "${name}" "attempt" "creating DB snapshot before restart"

    if echo "${name}" | grep -qi "postgres"; then
        if dry_run_check "snapshot:${name}"; then
            return
        fi

        # Try to get database name or use default
        local dbname
        dbname=$(docker exec "${name}" psql -U postgres -tAc "SELECT datname FROM pg_database WHERE datname NOT IN ('template0','template1') LIMIT 1;" 2>/dev/null || echo "postgres")

        if docker exec "${name}" pg_dump -U postgres "${dbname}" > "${snapshot_file}" 2>/dev/null; then
            log_json "snapshot" "${name}" "success" "pg_dump saved to ${snapshot_file} (db=${dbname})"
        else
            log_json "snapshot" "${name}" "failure" "pg_dump failed — proceeding with restart anyway"
        fi
        return
    fi

    if echo "${name}" | grep -qi "redis"; then
        if dry_run_check "snapshot:${name}"; then
            return
        fi

        if docker exec "${name}" redis-cli BGSAVE &>/dev/null; then
            log_json "snapshot" "${name}" "success" "redis BGSAVE triggered"
        else
            log_json "snapshot" "${name}" "failure" "redis BGSAVE failed — proceeding with restart anyway"
        fi
        return
    fi
}

# ------------------------------------------------------------------ (11) rollback triggers — integrated into handle_unhealthy_container / handle_pm2_app ---

# ------------------------------------------------------------------ helper checks ---
is_essential_container() {
    local name="$1"
    for essential in "${ESSENTIAL_CONTAINERS[@]}"; do
        if echo "${name}" | grep -qi "${essential}"; then
            return 0
        fi
    done
    return 1
}

# ------------------------------------------------------------------ environment checks ---
verify_environment() {
    log_json "env" "preflight" "info" "verifying environment"

    # Check Docker daemon
    if ! docker info &>/dev/null; then
        inc_counter ALERT_COUNT
        log_json "env" "docker" "critical" "Docker daemon is not reachable"
        alert_wall "AUTOHEAL: Cannot reach Docker daemon"
        return 1
    fi

    # Check that we are running as root or have docker privileges
    if ! docker ps &>/dev/null; then
        log_json "env" "docker_perms" "warn" "may not have Docker permissions"
    fi

    return 0
}

# ------------------------------------------------------------------ main run ---
do_run() {
    acquire_lock
    trap release_lock EXIT

    # Ensure log directory + file exist
    ensure_log_dir

    # Initialize counters
    HEAL_COUNT=0
    ACTION_COUNT=0
    ALERT_COUNT=0

    print_summary_header

    # Preflight
    if ! verify_environment; then
        log_json "run" "abort" "critical" "environment check failed — aborting run"
        print_summary_footer
        release_lock
        return 1
    fi

    # --- Execute all heal checks ---
    # Each function logs its own JSON entries; we run them in sequence.
    # Order matters: network first (we need connectivity), then disk/memory (infra),
    # then containers/PM2 (services), zombies last.

    heal_network        # (8)
    heal_tailscale      # (9) — depends on Tailscale being up
    heal_disk           # (4) — must catch disk pressure before triggering container ops
    heal_memory         # (5) — free memory before container work
    heal_containers     # (1,3,10,11) — restarts, loop detection, snapshots, rollbacks
    heal_stalled_containers  # (6) — health endpoint checks for "up but stuck" containers
    heal_pm2            # (2) — PM2 processes
    heal_zombies        # (7)
    cleanup_stale_locks # (12)

    print_summary_footer
    release_lock
}

# ------------------------------------------------------------------ CLI ---
usage() {
    cat <<'EOF'
Usage: autoheal.sh [--once | --daemon]

  Wheeler Enterprise Self-Healing Daemon

Options:
  --once      Run a single pass and exit (for cron: * * * * * /path/autoheal.sh --once)
  --daemon    Run in an infinite loop, sleeping 60 seconds between passes

Environment:
  DRY_RUN=1   Skip all destructive actions (restarts, stops, prunes)
              Logs and alerts are still produced.

Files:
  Log:         /var/log/wheeler/autoheal.log
  Lock:        /tmp/autoheal.lock
  Counts:      /tmp/autoheal-pm2-counts.txt
  Cooldown:    /tmp/autoheal-cooldown-<name>
  Rollback:    /tmp/autoheal-rollback-request
  Snapshots:   /tmp/autoheal-snapshot-<epoch>.sql
EOF
    exit 0
}

# --- entry point ---
RUN_MODE="once"

if [[ $# -eq 0 ]]; then
    RUN_MODE="once"
elif [[ "$1" == "--once" ]]; then
    RUN_MODE="once"
elif [[ "$1" == "--daemon" ]]; then
    RUN_MODE="daemon"
elif [[ "$1" == "--help" || "$1" == "-h" ]]; then
    usage
else
    echo "Unknown option: $1" >&2
    usage
fi

if [[ "${RUN_MODE}" == "daemon" ]]; then
    echo "AUTOHEAL daemon starting (interval=60s, pid=$$)"
    while true; do
        do_run
        sleep 60
    done
else
    # Single pass for cron
    do_run
fi
