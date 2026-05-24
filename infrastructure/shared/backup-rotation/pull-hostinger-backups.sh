#!/usr/bin/env bash
# =============================================================================
# pull-hostinger-backups.sh — Pull Backups from Hostinger VPS
# =============================================================================
# SSH to Hostinger via Tailscale, pg_dump all databases, pull dumps to local
# archive. Also pulls Docker compose files and .env files.
# Verifies each dump. Rotates: 7 daily, 4 weekly, 3 monthly.
#
# Hostinger databases:
#   frgops_production, frgcrm_local, shared_chatwoot_production,
#   shared_langfuse, shared_plausible, shared_usesend, shared_frgops_staging
# =============================================================================
set -euo pipefail

# --- Configuration -----------------------------------------------------------
# These should be set via environment or .env file
HOSTINGER_SSH_HOST="${HOSTINGER_SSH_HOST:-}"
HOSTINGER_SSH_USER="${HOSTINGER_SSH_USER:-root}"
HOSTINGER_SSH_PORT="${HOSTINGER_SSH_PORT:-22}"
HOSTINGER_TAILSCALE_IP="${HOSTINGER_TAILSCALE_IP:-}"

# Local archive directory (where dumps already land from Hostinger)
LOCAL_ARCHIVE_ROOT="${LOCAL_ARCHIVE_ROOT:-/root/backups/hostinger}"

# Default: use Tailscale IP if available, else hostname
if [ -n "${HOSTINGER_TAILSCALE_IP}" ]; then
    SSH_TARGET="${HOSTINGER_SSH_USER}@${HOSTINGER_TAILSCALE_IP}"
elif [ -n "${HOSTINGER_SSH_HOST}" ]; then
    SSH_TARGET="${HOSTINGER_SSH_USER}@${HOSTINGER_SSH_HOST}"
else
    SSH_TARGET=""
fi

# Remote temp directory for dumps on Hostinger
REMOTE_TEMP_DIR="/tmp/hostinger-backup-$$"

# Databases to back up on Hostinger
declare -A HOSTINGER_DATABASES
HOSTINGER_DATABASES=(
    ["frgops_production"]="frgops_production"
    ["frgcrm_local"]="frgcrm_local"
    ["shared_chatwoot_production"]="shared_chatwoot_production"
    ["shared_langfuse"]="shared_langfuse"
    ["shared_plausible"]="shared_plausible"
    ["shared_usesend"]="shared_usesend"
    ["shared_frgops_staging"]="shared_frgops_staging"
)

# Map databases to their Docker compose directories (for .env + config backup)
declare -A SERVICE_COMPOSE_DIRS
SERVICE_COMPOSE_DIRS=(
    ["frgops_production"]="/opt/frgops"
    ["shared_chatwoot_production"]="/opt/chatwoot"
    ["shared_langfuse"]="/opt/langfuse"
    ["shared_plausible"]="/opt/plausible"
    ["shared_usesend"]="/opt/usesend"
)

LOG_DIR="${LOG_DIR:-/opt/logs}"
BACKUP_LOG="${LOG_DIR}/hostinger-pull.log"

# --- Ensure directories ------------------------------------------------------
setup_directories() {
    mkdir -p "${LOCAL_ARCHIVE_ROOT}"
    mkdir -p "${LOG_DIR}"
}

# --- Logging -----------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "${message}" | tee -a "${BACKUP_LOG}"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# --- Healthcheck ping --------------------------------------------------------
healthcheck_ping() {
    local status="$1"
    local message="$2"

    if [ -n "${HEALTHCHECK_URL:-}" ]; then
        local ping_url="${HEALTHCHECK_URL}${status}"
        if [ -n "${message}" ]; then
            curl -fsS -m 10 --data-raw "${message}" "${ping_url}" >/dev/null 2>&1 || true
        else
            curl -fsS -m 10 "${ping_url}" >/dev/null 2>&1 || true
        fi
    fi
}

# --- Check SSH connectivity --------------------------------------------------
check_ssh() {
    if [ -z "${SSH_TARGET}" ]; then
        log_error "No SSH target configured. Set HOSTINGER_SSH_HOST or HOSTINGER_TAILSCALE_IP."
        return 1
    fi

    log_info "Checking SSH connectivity to ${SSH_TARGET}..."
    ssh -p "${HOSTINGER_SSH_PORT}" -o ConnectTimeout=10 -o BatchMode=yes \
        "${SSH_TARGET}" "echo connected" 2>/dev/null || {
        log_error "Cannot SSH to ${SSH_TARGET} — check Tailscale/VPN connectivity"
        return 1
    }
    log_info "SSH connection OK"
}

# --- Remote pg_dump all databases --------------------------------------------
remote_backup_databases() {
    local timestamp="$1"
    local remote_dir="${REMOTE_TEMP_DIR}/${timestamp}"

    log_info "Creating remote temp directory: ${remote_dir}"
    ssh -p "${HOSTINGER_SSH_PORT}" "${SSH_TARGET}" \
        "mkdir -p '${remote_dir}'" || return 1

    local success=0
    local failed=0

    for db_key in "${!HOSTINGER_DATABASES[@]}"; do
        local db_name="${HOSTINGER_DATABASES[${db_key}]}"
        local remote_file="${remote_dir}/${timestamp}_${db_name}.dump"

        log_info "Dumping remote database: ${db_name}..."

        # Get PostgreSQL connection details from remote .env or use defaults
        # Try common Docker Postgres connection patterns
        local pg_host="localhost"
        local pg_port="5432"
        local pg_user="postgres"

        # Attempt to extract from docker-compose .env if available
        local compose_dir="${SERVICE_COMPOSE_DIRS[${db_key}]:-}"
        if [ -n "${compose_dir}" ]; then
            local env_file="${compose_dir}/.env"
            local detected_host
            detected_host="$(ssh -p "${HOSTINGER_SSH_PORT}" "${SSH_TARGET}" \
                "grep -E '^POSTGRES_HOST=|^PGHOST=' '${env_file}' 2>/dev/null | tail -1 | cut -d= -f2" 2>/dev/null || true)"
            [ -n "${detected_host}" ] && pg_host="${detected_host}"

            local detected_port
            detected_port="$(ssh -p "${HOSTINGER_SSH_PORT}" "${SSH_TARGET}" \
                "grep -E '^POSTGRES_PORT=|^PGPORT=' '${env_file}' 2>/dev/null | tail -1 | cut -d= -f2" 2>/dev/null || true)"
            [ -n "${detected_port}" ] && pg_port="${detected_port}"

            local detected_user
            detected_user="$(ssh -p "${HOSTINGER_SSH_PORT}" "${SSH_TARGET}" \
                "grep -E '^POSTGRES_USER=|^PGUSER=' '${env_file}' 2>/dev/null | tail -1 | cut -d= -f2" 2>/dev/null || true)"
            [ -n "${detected_user}" ] && pg_user="${detected_user}"
        fi

        # Get the Postgres password (try .env first, then PGPASSWORD env)
        local pg_password
        pg_password="$(ssh -p "${HOSTINGER_SSH_PORT}" "${SSH_TARGET}" \
            "grep -E '^POSTGRES_PASSWORD=|^PGPASSWORD=' '${compose_dir}/.env' 2>/dev/null | tail -1 | cut -d= -f2" 2>/dev/null || true)"

        # Build pg_dump command (custom format)
        local pg_dump_cmd="PGPASSWORD='${pg_password}' pg_dump -h '${pg_host}' -p '${pg_port}' -U '${pg_user}' -d '${db_name}' -F c -v --no-owner --no-acl -f '${remote_file}'"

        # Run pg_dump remotely
        if ssh -p "${HOSTINGER_SSH_PORT}" "${SSH_TARGET}" \
            "PGHOST='${pg_host}' PGPORT='${pg_port}' PGUSER='${pg_user}' PGPASSWORD='${pg_password}' pg_dump -h '${pg_host}' -p '${pg_port}' -U '${pg_user}' -d '${db_name}' -F c -v --no-owner --no-acl -f '${remote_file}' 2>&1"; then
            log_info "  Dump of '${db_name}' completed remotely"
            success=$((success + 1))
        else
            log_warn "  pg_dump for '${db_name}' had issues (may not exist or be accessible)"
            failed=$((failed + 1))
        fi
    done

    echo "${success} ${failed}"
}

# --- Pull dumps from Hostinger to local archive ------------------------------
pull_dumps() {
    local remote_dir="${REMOTE_TEMP_DIR}"
    local local_dir="${LOCAL_ARCHIVE_ROOT}"

    log_info "Pulling dumps from ${SSH_TARGET}:${remote_dir} → ${local_dir}"

    # Use rsync over SSH for efficient transfer
    rsync -avz -e "ssh -p ${HOSTINGER_SSH_PORT}" \
        "${SSH_TARGET}:${remote_dir}/" "${local_dir}/" 2>&1 | tee -a "${BACKUP_LOG}"

    local rsync_exit=$?
    if [ "${rsync_exit}" -ne 0 ]; then
        log_warn "rsync exited with code ${rsync_exit}"
        return 1
    fi

    log_info "Pull complete"
}

# --- Pull Docker compose files and .env files --------------------------------
pull_configs() {
    local config_dir="${LOCAL_ARCHIVE_ROOT}/configs/$(date '+%Y%m%d_%H%M%S')"
    mkdir -p "${config_dir}"

    log_info "Pulling configuration files to ${config_dir}"

    # Pull compose files and .env from known service directories
    for service_dir in "${SERVICE_COMPOSE_DIRS[@]}"; do
        local service_name
        service_name="$(basename "${service_dir}")"

        log_info "Pulling configs for ${service_name}..."

        # Pull docker-compose.yml
        rsync -avz -e "ssh -p ${HOSTINGER_SSH_PORT}" \
            "${SSH_TARGET}:${service_dir}/docker-compose.yml" \
            "${config_dir}/${service_name}_docker-compose.yml" 2>/dev/null || true

        # Pull compose.yml
        rsync -avz -e "ssh -p ${HOSTINGER_SSH_PORT}" \
            "${SSH_TARGET}:${service_dir}/compose.yml" \
            "${config_dir}/${service_name}_compose.yml" 2>/dev/null || true

        # Pull .env
        rsync -avz -e "ssh -p ${HOSTINGER_SSH_PORT}" \
            "${SSH_TARGET}:${service_dir}/.env" \
            "${config_dir}/${service_name}.env" 2>/dev/null || true

        # Pull any other .env.* files
        rsync -avz -e "ssh -p ${HOSTINGER_SSH_PORT}" \
            --include='.env*' --exclude='*' \
            "${SSH_TARGET}:${service_dir}/" \
            "${config_dir}/${service_name}_env/" 2>/dev/null || true
    done

    log_info "Configuration files pulled to ${config_dir}"
}

# --- Verify dump integrity locally -------------------------------------------
verify_dumps() {
    log_info "Verifying dump integrity..."

    local verified=0
    local corrupted=0

    for dump in "${LOCAL_ARCHIVE_ROOT}/"*.dump; do
        [ -f "${dump}" ] || continue

        local fname
        fname="$(basename "${dump}")"

        if pg_restore --list "${dump}" >/dev/null 2>> "${BACKUP_LOG}"; then
            local toc_count
            toc_count="$(pg_restore --list "${dump}" 2>/dev/null | grep -c "^[0-9]" || true)"
            log_info "  OK: ${fname} (${toc_count} TOC entries)"
            verified=$((verified + 1))
        else
            log_error "  CORRUPT: ${fname}"
            corrupted=$((corrupted + 1))
        fi
    done

    echo "${verified} ${corrupted}"
}

# --- Apply rotation -----------------------------------------------------------
apply_rotation() {
    local archive_root="${LOCAL_ARCHIVE_ROOT}"
    local keep_daily=7
    local keep_weekly=4
    local keep_monthly=3

    log_info "Applying rotation to ${archive_root}..."
    log_info "Retention: daily=${keep_daily}, weekly=${keep_weekly}, monthly=${keep_monthly}"

    # Group dumps by database name and apply retention per database
    local dumps
    mapfile -t dumps < <(find "${archive_root}" -maxdepth 1 -name '*.dump' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    declare -A db_dumps
    for dump in "${dumps[@]}"; do
        local fname
        fname="$(basename "${dump}")"
        # Extract db name from filename: TIMESTAMP_dbname.dump
        local db_name="${fname#*_}"
        db_name="${db_name%.dump}"
        db_dumps["${db_name}"]+="${dump} "
    done

    for db_name in "${!db_dumps[@]}"; do
        local count=0
        for dump in ${db_dumps["${db_name}"]}; do
            count=$((count + 1))

            # Determine if this is a monthly (1st) or weekly (Sunday) backup
            local dump_dom
            dump_dom="$(date -r "${dump}" '+%d' 2>/dev/null || echo "99")"
            local dump_dow
            dump_dow="$(date -r "${dump}" '+%u' 2>/dev/null || echo "0")"

            # Keep monthly backups (1st of month) beyond daily retention
            if [ "${dump_dom}" = "01" ] && [ "${count}" -gt "${keep_daily}" ]; then
                # Count how many monthly we're keeping
                local monthly_count=0
                for d in ${db_dumps["${db_name}"]}; do
                    [ "$(date -r "${d}" '+%d' 2>/dev/null)" = "01" ] && monthly_count=$((monthly_count + 1))
                done
                if [ "${monthly_count}" -gt "${keep_monthly}" ]; then
                    log_info "  Removing monthly backup (past retention): $(basename "${dump}")"
                    rm -f "${dump}" 2>/dev/null || true
                fi
                continue
            fi

            # Keep weekly backups (Sunday) beyond daily retention
            if [ "${dump_dow}" = "7" ] && [ "${count}" -gt "${keep_daily}" ]; then
                local weekly_count=0
                for d in ${db_dumps["${db_name}"]}; do
                    [ "$(date -r "${d}" '+%u' 2>/dev/null)" = "7" ] && weekly_count=$((weekly_count + 1))
                done
                if [ "${weekly_count}" -gt "${keep_weekly}" ]; then
                    log_info "  Removing weekly backup (past retention): $(basename "${dump}")"
                    rm -f "${dump}" 2>/dev/null || true
                fi
                continue
            fi

            # Normal daily retention
            if [ "${count}" -gt "${keep_daily}" ]; then
                log_info "  Removing daily backup (past retention): $(basename "${dump}")"
                rm -f "${dump}" 2>/dev/null || true
            fi
        done
    done

    # Clean up old config directories
    find "${archive_root}/configs" -maxdepth 1 -type d -mtime +"${keep_daily}" -exec rm -rf {} + 2>/dev/null || true

    log_info "Rotation complete"
}

# --- Cleanup remote temp dir --------------------------------------------------
cleanup_remote() {
    log_info "Cleaning up remote temp directory..."
    ssh -p "${HOSTINGER_SSH_PORT}" "${SSH_TARGET}" \
        "rm -rf '${REMOTE_TEMP_DIR}'" 2>/dev/null || true
}

# --- Create manifest ----------------------------------------------------------
create_manifest() {
    local manifest="${LOCAL_ARCHIVE_ROOT}/manifest_latest.txt"

    log_info "Creating manifest at ${manifest}"

    {
        echo "============================================"
        echo "Hostinger VPS Backup Pull Manifest"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Source: ${SSH_TARGET}"
        echo "Local Archive: ${LOCAL_ARCHIVE_ROOT}"
        echo "============================================"
        echo ""

        local total_size=0
        local count=0

        echo "--- Database Dumps ---"
        for dump in $(find "${LOCAL_ARCHIVE_ROOT}" -maxdepth 1 -name '*.dump' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-); do
            local fname
            fname="$(basename "${dump}")"
            local fsize
            fsize="$(stat -c%s "${dump}" 2>/dev/null || stat -f%z "${dump}" 2>/dev/null)"
            local fsize_hr
            fsize_hr="$(numfmt --to=iec "${fsize}" 2>/dev/null || echo "${fsize} bytes")"
            echo "  ${fname}  |  ${fsize_hr}"
            total_size=$((total_size + fsize))
            count=$((count + 1))
        done

        echo ""
        echo "Total Dumps: ${count}"
        echo "Total Size: $(numfmt --to=iec "${total_size}" 2>/dev/null || echo "${total_size} bytes")"
        echo "============================================"
    } > "${manifest}"

    log_info "Manifest created"
}

# === MAIN ===
main() {
    local start_time
    start_time="$(date +%s)"

    log_info "=============================================="
    log_info "Hostinger VPS Backup Pull Starting"
    log_info "=============================================="

    # Send healthcheck start
    healthcheck_ping "" "Hostinger backup pull started at $(date)"

    # Setup
    setup_directories

    # Check SSH
    check_ssh || {
        healthcheck_ping "/fail" "Hostinger backup pull failed: SSH connectivity issue"
        exit 1
    }

    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"

    # Step 1: Remote backup all databases
    log_info "Step 1/4: Backing up databases on Hostinger..."
    local remote_result
    remote_result="$(remote_backup_databases "${timestamp}")"
    log_info "Remote backup result: ${remote_result}"

    # Step 2: Pull dumps to local archive
    log_info "Step 2/4: Pulling dumps to local archive..."
    pull_dumps || log_warn "Some dumps may not have been pulled successfully"

    # Step 3: Pull configuration files
    log_info "Step 3/4: Pulling configuration files..."
    pull_configs

    # Step 4: Verify integrity
    log_info "Step 4/4: Verifying dump integrity..."
    local verify_result
    verify_result="$(verify_dumps)"
    log_info "Verification: ${verify_result}"

    # Apply rotation
    apply_rotation

    # Create manifest
    create_manifest

    # Cleanup remote
    cleanup_remote

    # Summary
    local end_time
    end_time="$(date +%s)"
    local duration=$((end_time - start_time))
    local duration_hr
    duration_hr="$(date -u -d "@${duration}" '+%H:%M:%S' 2>/dev/null || echo "${duration}s")"

    log_info "=============================================="
    log_info "Hostinger Backup Pull Complete"
    log_info "Duration: ${duration_hr}"
    log_info "Target: ${SSH_TARGET}"
    log_info "Archive: ${LOCAL_ARCHIVE_ROOT}"
    log_info "=============================================="

    # Healthcheck
    healthcheck_ping "" "Hostinger backup pull completed in ${duration_hr}"

    # Rotate old backup logs (keep 30 days)
    find "${LOG_DIR}" -name 'hostinger-pull.log*' -mtime +30 -delete 2>/dev/null || true
}

# --- Run ---------------------------------------------------------------------
main "$@"
