#!/usr/bin/env bash
#===============================================================================
# Wheeler Enterprise Infrastructure — Full Backup Script
#===============================================================================
# Backs up: PostgreSQL dbs, Redis snapshots, Docker volumes, PM2 configs,
#           Traefik configs, Nginx configs, environment files.
# Output:   Encrypted .tar.gz.gpg with SHA256 checksum.
# Rotation: Keeps last 7 daily backups.
# Logging:  JSON-structured logs to /var/log/wheeler/backup.log
# Metrics:  Prometheus textfile at /var/lib/node_exporter/textfile_collector/backup.prom
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

# -- Constants -------------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly BACKUP_ROOT="/root/infrastructure/backups"
readonly LOG_DIR="/var/log/wheeler"
readonly LOG_FILE="${LOG_DIR}/backup.log"
readonly PROM_DIR="/var/lib/node_exporter/textfile_collector"
readonly PROM_FILE="${PROM_DIR}/backup.prom"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR="${BACKUP_ROOT}/backup-${TIMESTAMP}"
readonly BACKUP_ARCHIVE="${BACKUP_ROOT}/backup-${TIMESTAMP}.tar.gz"
readonly BACKUP_ENCRYPTED="${BACKUP_ARCHIVE}.gpg"
readonly CHECKSUM_FILE="${BACKUP_ENCRYPTED}.sha256"
readonly ROTATION_KEEP=7

# Runtime state
START_TIME=""
PHASE_STATUS=""
BACKUP_SIZE_BYTES=0
BACKUP_STATUS=1  # 0=fail, 1=success
EXIT_TRAP_SET=0

# -- Logging ---------------------------------------------------------------------
init_logging() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
}

log_json() {
    local level="${1:-INFO}"
    local phase="${2:-}"
    local message="${3:-}"
    local extra="${4:-}"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local entry
    entry="$(jq -nc \
        --arg ts "$ts" \
        --arg level "$level" \
        --arg script "$SCRIPT_NAME" \
        --arg phase "$phase" \
        --arg msg "$message" \
        --arg extra "$extra" \
        '{timestamp: $ts, level: $level, script: $script, phase: $phase, message: $msg, extra: $extra}')"

    echo "$entry" >> "$LOG_FILE"

    # Also print to console
    local tag=""
    case "$level" in
        ERROR)  tag="ERR"  ;;
        WARN)   tag="WRN"  ;;
        SUCCESS)tag="OK"   ;;
        *)      tag="INF"  ;;
    esac
    echo "[${tag}] ${phase:+[${phase}] }${message}" >&2
}

check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_json "ERROR" "init" "Missing required dependency: ${cmd}" ""
        echo "ERROR: Required command '${cmd}' not found. Please install it." >&2
        exit 1
    fi
}

# -- Cleanup / Error Trap --------------------------------------------------------
cleanup() {
    local exit_code=$?
    local end_time
    end_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if [[ $exit_code -ne 0 && $BACKUP_STATUS -ne 0 ]]; then
        BACKUP_STATUS=0
        log_json "ERROR" "cleanup" "Backup script exited with code ${exit_code}" ""
    fi

    log_json "INFO" "summary" "Backup finished" \
        "{\"start_time\":\"${START_TIME}\",\"end_time\":\"${end_time}\",\"exit_code\":${exit_code},\"status\":${BACKUP_STATUS},\"size_bytes\":${BACKUP_SIZE_BYTES}}"

    write_prometheus_metric

    if [[ $exit_code -ne 0 ]]; then
        log_json "ERROR" "cleanup" "Backup FAILED — check logs at ${LOG_FILE}" ""
        echo "" >&2
        echo "============================================================" >&2
        echo " BACKUP FAILED with exit code ${exit_code}" >&2
        echo " Partial artifacts (if any) in: ${BACKUP_DIR}" >&2
        echo " Full log: ${LOG_FILE}" >&2
        echo "============================================================" >&2
    fi
}

# -- Prometheus metrics ----------------------------------------------------------
init_prometheus_dir() {
    if [[ -d "$PROM_DIR" ]]; then
        return 0
    fi
    # Attempt creation; if it fails, skip prom metrics
    mkdir -p "$PROM_DIR" 2>/dev/null || true
}

write_prometheus_metric() {
    if [[ ! -d "$PROM_DIR" ]]; then
        return 0
    fi
    local ts_epoch
    ts_epoch="$(date +%s)"
    cat > "${PROM_FILE}.tmp" <<EOF
# HELP wheeler_backup_last_timestamp_seconds Unix timestamp of last backup completion
# TYPE wheeler_backup_last_timestamp_seconds gauge
wheeler_backup_last_timestamp_seconds ${ts_epoch}
# HELP wheeler_backup_size_bytes Size of the encrypted backup in bytes
# TYPE wheeler_backup_size_bytes gauge
wheeler_backup_size_bytes ${BACKUP_SIZE_BYTES}
# HELP wheeler_backup_status 1=success, 0=failure
# TYPE wheeler_backup_status gauge
wheeler_backup_status ${BACKUP_STATUS}
EOF
    mv "${PROM_FILE}.tmp" "$PROM_FILE" 2>/dev/null || true
}

# -- Utility ---------------------------------------------------------------------
check_ok() {
    local rc=$1
    local phase="$2"
    local msg="$3"
    if [[ $rc -eq 0 ]]; then
        log_json "SUCCESS" "$phase" "$msg" ""
    else
        log_json "ERROR" "$phase" "$msg (rc=${rc})" ""
        BACKUP_STATUS=0
    fi
    return $rc
}

warn_skip() {
    local phase="$1"
    local msg="$2"
    log_json "WARN" "$phase" "$msg" ""
}

# -- PostgreSQL Backup -----------------------------------------------------------
backup_postgresql() {
    local phase="postgresql"
    log_json "INFO" "$phase" "Starting PostgreSQL backups" ""

    local pg_dir="${BACKUP_DIR}/postgresql"
    mkdir -p "$pg_dir"

    # Discover postgres containers
    local pg_containers
    pg_containers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i 'postgres' || true)

    if [[ -z "$pg_containers" ]]; then
        warn_skip "$phase" "No running PostgreSQL containers found"
        return 0
    fi

    local success_count=0
    local fail_count=0

    for container in $pg_containers; do
        log_json "INFO" "$phase" "Dumping PostgreSQL: ${container}" ""

        # Detect databases in this container — try pg_dumpall first, fall back to per-db
        local dump_file="${pg_dir}/${container}-dump.sql"
        local dump_gz="${dump_file}.gz"

        # Attempt pg_dumpall (single-file dump of all databases)
        if docker exec "$container" pg_dumpall -U postgres > "$dump_file" 2>/dev/null; then
            :
        else
            # Fall back: try with POSTGRES_USER env var or 'root'
            local pg_user
            pg_user=$(docker exec "$container" printenv POSTGRES_USER 2>/dev/null || echo "postgres")
            if ! docker exec "$container" pg_dumpall -U "$pg_user" > "$dump_file" 2>/dev/null; then
                log_json "ERROR" "$phase" "pg_dumpall failed for ${container}, trying per-database dump" ""
                # Try per-database approach
                local databases
                databases=$(docker exec "$container" psql -U "$pg_user" -tAc "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';" 2>/dev/null || true)
                if [[ -n "$databases" ]]; then
                    local combined="${pg_dir}/${container}-combined.sql"
                    > "$combined"
                    for db in $databases; do
                        docker exec "$container" pg_dump -U "$pg_user" "$db" >> "$combined" 2>/dev/null || true
                    done
                    if [[ -s "$combined" ]]; then
                        mv "$combined" "$dump_file"
                    fi
                fi
            fi
        fi

        if [[ -s "$dump_file" ]]; then
            gzip -f "$dump_file"
            if gunzip -t "$dump_gz" 2>/dev/null; then
                log_json "SUCCESS" "$phase" "PostgreSQL dump OK: ${container} ($(du -h "$dump_gz" | cut -f1))" ""
                ((success_count++))
            else
                log_json "ERROR" "$phase" "PostgreSQL dump integrity check FAILED: ${container}" ""
                ((fail_count++))
            fi
        else
            log_json "ERROR" "$phase" "PostgreSQL dump empty or missing: ${container}" ""
            ((fail_count++))
        fi
    done

    check_ok 0 "$phase" "PostgreSQL backups: ${success_count} succeeded, ${fail_count} failed"
    if [[ $fail_count -gt 0 ]]; then
        BACKUP_STATUS=0
    fi
}

# -- Redis Backup ----------------------------------------------------------------
backup_redis() {
    local phase="redis"
    log_json "INFO" "$phase" "Starting Redis backups" ""

    local redis_dir="${BACKUP_DIR}/redis"
    mkdir -p "$redis_dir"

    local redis_containers
    redis_containers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i 'redis' || true)

    if [[ -z "$redis_containers" ]]; then
        warn_skip "$phase" "No running Redis containers found"
        return 0
    fi

    local success_count=0
    local fail_count=0

    for container in $redis_containers; do
        log_json "INFO" "$phase" "Triggering BGSAVE on Redis: ${container}" ""

        # Trigger BGSAVE
        if docker exec "$container" redis-cli BGSAVE &>/dev/null; then
            # Wait for BGSAVE to complete
            local waited=0
            while [[ $waited -lt 30 ]]; do
                local bgsave_status
                bgsave_status=$(docker exec "$container" redis-cli LASTSAVE 2>/dev/null || echo "0")
                if [[ "$bgsave_status" != "0" ]]; then
                    break
                fi
                sleep 1
                ((waited++))
            done
            sleep 1  # Extra grace period for file flush
        else
            # Try without redis-cli — some Redis images don't have it
            docker exec "$container" redis-cli -a "$(docker exec "$container" printenv REDIS_PASSWORD 2>/dev/null || echo "")" BGSAVE &>/dev/null || true
            sleep 3
        fi

        # Copy RDB file
        local rdb_path
        rdb_path=$(docker exec "$container" redis-cli CONFIG GET dir 2>/dev/null | tail -1 || echo "/data")
        local rdb_file
        rdb_file=$(docker exec "$container" redis-cli CONFIG GET dbfilename 2>/dev/null | tail -1 || echo "dump.rdb")

        local container_rdb="${redis_dir}/${container}-dump.rdb"

        if docker cp "${container}:${rdb_path}/${rdb_file}" "$container_rdb" 2>/dev/null; then
            if [[ -s "$container_rdb" ]]; then
                log_json "SUCCESS" "$phase" "Redis RDB saved: ${container} ($(du -h "$container_rdb" | cut -f1))" ""
                ((success_count++))
            else
                log_json "ERROR" "$phase" "Redis RDB empty: ${container}" ""
                ((fail_count++))
            fi
        else
            log_json "ERROR" "$phase" "Failed to copy RDB from ${container}" ""
            ((fail_count++))
        fi

        # Also backup AOF if enabled
        local aof_enabled
        aof_enabled=$(docker exec "$container" redis-cli CONFIG GET appendonly 2>/dev/null | tail -1 || echo "no")
        if [[ "$aof_enabled" == "yes" ]]; then
            local aof_file
            aof_file=$(docker exec "$container" redis-cli CONFIG GET appendfilename 2>/dev/null | tail -1 || echo "appendonly.aof")
            docker cp "${container}:${rdb_path}/${aof_file}" "${redis_dir}/${container}-appendonly.aof" 2>/dev/null || true
            log_json "INFO" "$phase" "AOF backed up for ${container}" ""
        fi
    done

    check_ok 0 "$phase" "Redis backups: ${success_count} succeeded, ${fail_count} failed"
}

# -- Docker Volume Backup --------------------------------------------------------
backup_docker_volumes() {
    local phase="docker-volumes"
    log_json "INFO" "$phase" "Starting Docker volume backups" ""

    local vol_dir="${BACKUP_DIR}/docker-volumes"
    mkdir -p "$vol_dir"

    local volumes
    volumes=$(docker volume ls --format '{{.Name}}' 2>/dev/null || true)

    if [[ -z "$volumes" ]]; then
        warn_skip "$phase" "No Docker volumes found"
        return 0
    fi

    local success_count=0
    local skip_count=0
    local fail_count=0

    for vol in $volumes; do
        # Estimate size via mount inspection
        local mount_point
        mount_point=$(docker volume inspect "$vol" --format '{{.Mountpoint}}' 2>/dev/null || true)
        if [[ -z "$mount_point" ]]; then
            warn_skip "$phase" "Cannot determine mountpoint for volume: ${vol}"
            ((skip_count++))
            continue
        fi

        local vol_size_kb
        vol_size_kb=$(du -sk "$mount_point" 2>/dev/null | cut -f1 || echo "0")

        # 5 GB = 5,242,880 KB
        if [[ "$vol_size_kb" -gt 5242880 ]]; then
            warn_skip "$phase" "Volume '${vol}' is >5GB (${vol_size_kb}KB) — SKIPPING (needs separate handling)"
            ((skip_count++))
            continue
        fi

        log_json "INFO" "$phase" "Backing up volume: ${vol} ($(du -sh "$mount_point" 2>/dev/null | cut -f1))" ""
        local tar_file="${vol_dir}/${vol}.tar.gz"

        if tar -czf "$tar_file" -C "$mount_point" . 2>/dev/null; then
            if [[ -s "$tar_file" ]]; then
                ((success_count++))
            else
                warn_skip "$phase" "Volume '${vol}' tar is empty — may be unused"
                ((skip_count++))
            fi
        else
            log_json "ERROR" "$phase" "Failed to tar volume: ${vol}" ""
            ((fail_count++))
        fi
    done

    check_ok 0 "$phase" "Docker volumes: ${success_count} backed up, ${skip_count} skipped, ${fail_count} failed"
}

# -- PM2 Config Backup -----------------------------------------------------------
backup_pm2() {
    local phase="pm2"
    log_json "INFO" "$phase" "Starting PM2 config backup" ""

    local pm2_dir="${BACKUP_DIR}/pm2"
    mkdir -p "$pm2_dir"

    local count=0

    if [[ -f /root/.pm2/dump.pm2 ]]; then
        cp /root/.pm2/dump.pm2 "${pm2_dir}/dump.pm2"
        log_json "SUCCESS" "$phase" "Copied /root/.pm2/dump.pm2" ""
        ((count++))
    else
        warn_skip "$phase" "/root/.pm2/dump.pm2 not found"
    fi

    # Find ecosystem.config.js files
    local ecosystem_files
    ecosystem_files=$(find /root /opt /etc -maxdepth 4 -name "ecosystem.config.js" -o -name "ecosystem.config.cjs" 2>/dev/null || true)

    if [[ -n "$ecosystem_files" ]]; then
        while IFS= read -r ef; do
            local rel_path="${ef#/}"
            local dst="${pm2_dir}/$(echo "$rel_path" | tr '/' '_')"
            cp "$ef" "$dst"
            log_json "INFO" "$phase" "Copied ecosystem config: ${ef}" ""
            ((count++))
        done <<< "$ecosystem_files"
    fi

    if [[ $count -gt 0 ]]; then
        check_ok 0 "$phase" "PM2 configs backed up: ${count} files"
    else
        warn_skip "$phase" "No PM2 configs found to back up"
    fi
}

# -- Traefik Config Backup -------------------------------------------------------
backup_traefik() {
    local phase="traefik"
    log_json "INFO" "$phase" "Starting Traefik config backup" ""

    local traefik_dir="${BACKUP_DIR}/traefik"
    mkdir -p "$traefik_dir"

    local traefik_dirs=(
        "/root/infrastructure/hetzner/traefik"
        "/root/infrastructure/hostinger/traefik"
    )

    local count=0

    for td in "${traefik_dirs[@]}"; do
        if [[ -d "$td" ]]; then
            local folder_name
            folder_name=$(basename "$(dirname "$td")")-traefik
            local tar_file="${traefik_dir}/${folder_name}.tar.gz"
            if tar -czf "$tar_file" -C "$(dirname "$td")" "$(basename "$td")" 2>/dev/null; then
                log_json "SUCCESS" "$phase" "Backed up Traefik config: ${td}" ""
                ((count++))
            else
                log_json "ERROR" "$phase" "Failed to tar Traefik config: ${td}" ""
            fi
        else
            log_json "WARN" "$phase" "Traefik directory not found: ${td}" ""
        fi
    done

    if [[ -d /root/infrastructure/shared/traefik ]]; then
        tar -czf "${traefik_dir}/shared-traefik.tar.gz" -C /root/infrastructure/shared traefik 2>/dev/null || true
        ((count++))
    fi

    if [[ $count -gt 0 ]]; then
        check_ok 0 "$phase" "Traefik configs: ${count} directories backed up"
    else
        warn_skip "$phase" "No Traefik config directories found"
    fi
}

# -- Nginx Config Backup ---------------------------------------------------------
backup_nginx() {
    local phase="nginx"
    log_json "INFO" "$phase" "Starting Nginx config backup" ""

    local nginx_dir="${BACKUP_DIR}/nginx"

    if [[ -d /etc/nginx ]]; then
        mkdir -p "$nginx_dir"
        if tar -czf "${nginx_dir}/etc-nginx.tar.gz" -C /etc nginx 2>/dev/null; then
            check_ok 0 "$phase" "Nginx config backed up: /etc/nginx ($(du -h "${nginx_dir}/etc-nginx.tar.gz" | cut -f1))"
        else
            log_json "ERROR" "$phase" "Failed to tar /etc/nginx" ""
            BACKUP_STATUS=0
        fi
    else
        warn_skip "$phase" "/etc/nginx not found — skipping"
    fi
}

# -- Environment Files Backup ----------------------------------------------------
backup_env_files() {
    local phase="env-files"
    log_json "INFO" "$phase" "Starting environment files backup" ""

    local env_dir="${BACKUP_DIR}/env-files"
    mkdir -p "$env_dir"

    local env_files
    env_files=$(find /root /opt /etc -maxdepth 5 -name ".env" -o -name "*.env" 2>/dev/null | grep -v '.local.env' | grep -v 'node_modules' | grep -v '.cache' || true)

    local count=0

    if [[ -z "$env_files" ]]; then
        warn_skip "$phase" "No .env files found"
        return 0
    fi

    while IFS= read -r ef; do
        # Create a safe filename: replace / with _
        local safe_name="${ef#/}"
        safe_name="${safe_name//\//_}"
        cp "$ef" "${env_dir}/${safe_name}"
        log_json "INFO" "$phase" "Copied env: ${ef}" ""
        ((count++))
    done <<< "$env_files"

    check_ok 0 "$phase" "Environment files backed up: ${count} files"
}

# -- Tar.xz / Encrypt / Checksum -------------------------------------------------
compress_and_encrypt() {
    local phase="compress-encrypt"
    log_json "INFO" "$phase" "Compressing backup directory" ""

    # Stage 1: Compress entire backup directory
    if tar -czf "$BACKUP_ARCHIVE" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")" 2>/dev/null; then
        local size
        size=$(stat --printf="%s" "$BACKUP_ARCHIVE" 2>/dev/null || echo "0")
        log_json "SUCCESS" "$phase" "Compressed to ${BACKUP_ARCHIVE} ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size} bytes"))" "{\"size_bytes\":${size}}"
    else
        log_json "ERROR" "$phase" "Compression FAILED" ""
        BACKUP_STATUS=0
        return 1
    fi

    # Stage 2: Encrypt
    local passphrase="${BACKUP_PASSPHRASE:-}"
    if [[ -z "$passphrase" ]]; then
        log_json "WARN" "$phase" "No BACKUP_PASSPHRASE env var set — prompting for passphrase"
        read -rsp "Enter backup encryption passphrase: " passphrase
        echo "" >&2
        if [[ -z "$passphrase" ]]; then
            log_json "ERROR" "$phase" "Empty passphrase — encryption ABORTED" ""
            BACKUP_STATUS=0
            return 1
        fi
    fi

    if gpg --symmetric --cipher-algo AES256 --batch --passphrase "$passphrase" \
           --output "$BACKUP_ENCRYPTED" "$BACKUP_ARCHIVE" 2>/dev/null; then
        log_json "SUCCESS" "$phase" "Encrypted: ${BACKUP_ENCRYPTED}" ""
    else
        log_json "ERROR" "$phase" "Encryption FAILED" ""
        BACKUP_STATUS=0
        return 1
    fi

    # Stage 3: SHA256 checksum
    if sha256sum "$BACKUP_ENCRYPTED" > "$CHECKSUM_FILE" 2>/dev/null; then
        log_json "SUCCESS" "$phase" "SHA256 checksum written: ${CHECKSUM_FILE}" ""
    else
        log_json "ERROR" "$phase" "SHA256 checksum generation FAILED" ""
        BACKUP_STATUS=0
        return 1
    fi

    # Stage 4: Verify decrypt-ability
    log_json "INFO" "$phase" "Verifying encrypted file can be decrypted" ""
    if gpg --decrypt --batch --passphrase "$passphrase" "$BACKUP_ENCRYPTED" > /dev/null 2>&1; then
        log_json "SUCCESS" "$phase" "Decryption verification PASSED" ""
    else
        log_json "ERROR" "$phase" "Decryption verification FAILED — encrypted backup may be corrupt" ""
        BACKUP_STATUS=0
        return 1
    fi

    # Stage 5: Remove unencrypted archive
    rm -f "$BACKUP_ARCHIVE"
    log_json "INFO" "$phase" "Removed unencrypted archive (keeping only .gpg)" ""

    # Capture final size
    BACKUP_SIZE_BYTES=$(stat --printf="%s" "$BACKUP_ENCRYPTED" 2>/dev/null || echo "0")
}

# -- Offsite Copy ----------------------------------------------------------------
offsite_copy() {
    local phase="offsite"
    if [[ -z "${RSYNC_DEST:-}" ]]; then
        log_json "INFO" "$phase" "No RSYNC_DEST set — skipping offsite copy" ""
        return 0
    fi

    log_json "INFO" "$phase" "Copying encrypted backup to: ${RSYNC_DEST}" ""
    if rsync -avz "$BACKUP_ENCRYPTED" "$CHECKSUM_FILE" "${RSYNC_DEST}/" 2>/dev/null; then
        log_json "SUCCESS" "$phase" "Offsite copy succeeded: ${RSYNC_DEST}" ""
    else
        log_json "ERROR" "$phase" "Offsite copy FAILED to ${RSYNC_DEST}" ""
        # Non-fatal: backup is already local
    fi
}

# -- Rotation --------------------------------------------------------------------
rotate_backups() {
    local phase="rotation"
    log_json "INFO" "$phase" "Rotating backups (keeping last ${ROTATION_KEEP})" ""

    local all_backups
    all_backups=$(find "$BACKUP_ROOT" -maxdepth 1 -name "backup-*.tar.gz.gpg" -type f 2>/dev/null | sort || true)

    local count
    count=$(echo "$all_backups" | grep -c '.' || echo "0")

    if [[ $count -le $ROTATION_KEEP ]]; then
        log_json "INFO" "$phase" "No rotation needed (${count} backups, keep=${ROTATION_KEEP})" ""
        return 0
    fi

    local to_delete
    to_delete=$(echo "$all_backups" | head -n $((count - ROTATION_KEEP)))

    if [[ -n "$to_delete" ]]; then
        while IFS= read -r old_backup; do
            if [[ -f "$old_backup" ]]; then
                local old_base="${old_backup%.gpg}"
                rm -f "$old_backup" "${old_backup}.sha256" "$old_base" 2>/dev/null || true
                log_json "INFO" "$phase" "Removed old backup: $(basename "$old_backup")" ""
            fi
        done <<< "$to_delete"
        log_json "SUCCESS" "$phase" "Rotation complete — removed $((count - ROTATION_KEEP)) old backup(s)" ""
    fi
}

# -- Healthcheck -----------------------------------------------------------------
run_healthcheck() {
    local healthcheck_script="/root/infrastructure/enterprise/phase6-backup/healthcheck-all.sh"
    if [[ -x "$healthcheck_script" ]]; then
        log_json "INFO" "healthcheck" "Running post-backup healthcheck" ""
        if "$healthcheck_script" 2>/dev/null; then
            log_json "SUCCESS" "healthcheck" "Healthcheck passed" ""
        else
            log_json "WARN" "healthcheck" "Healthcheck returned non-zero — review output" ""
        fi
    else
        log_json "INFO" "healthcheck" "healthcheck-all.sh not found or not executable — skipping" ""
    fi
}

# -- Main ------------------------------------------------------------------------
main() {
    START_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Pre-flight
    init_logging
    init_prometheus_dir

    log_json "INFO" "init" "=== Wheeler Enterprise Backup Started ===" \
        "{\"timestamp\":\"${TIMESTAMP}\",\"backup_dir\":\"${BACKUP_DIR}\"}"

    # Check dependencies
    for dep in docker jq gpg tar gzip sha256sum stat du cut; do
        check_dependency "$dep"
    done

    log_json "INFO" "init" "All dependencies satisfied" ""

    # Create backup work dir and ensure root exists
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_ROOT"

    # Set trap after dirs exist so cleanup can reference them
    trap cleanup EXIT
    EXIT_TRAP_SET=1

    # Phase 1: PostgreSQL
    backup_postgresql || true

    # Phase 2: Redis
    backup_redis || true

    # Phase 3: Docker volumes
    backup_docker_volumes || true

    # Phase 4: PM2 configs
    backup_pm2 || true

    # Phase 5: Traefik configs
    backup_traefik || true

    # Phase 6: Nginx configs
    backup_nginx || true

    # Phase 7: Environment files
    backup_env_files || true

    # Phase 8: Compress + Encrypt + Verify
    compress_and_encrypt || true

    # Phase 9: Offsite copy
    offsite_copy || true

    # Phase 10: Rotation
    rotate_backups || true

    # Phase 11: Healthcheck
    run_healthcheck || true

    # Remove raw backup directory (keep only encrypted archive)
    rm -rf "$BACKUP_DIR"
    log_json "INFO" "cleanup" "Removed raw backup directory ${BACKUP_DIR}" ""

    # Collect final metadata
    if [[ -f "$BACKUP_ENCRYPTED" ]]; then
        BACKUP_SIZE_BYTES=$(stat --printf="%s" "$BACKUP_ENCRYPTED" 2>/dev/null || echo "0")
    fi

    local end_time
    end_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    echo "" >&2
    echo "============================================================" >&2
    if [[ $BACKUP_STATUS -eq 1 ]]; then
        echo " BACKUP COMPLETED SUCCESSFULLY" >&2
    else
        echo " BACKUP COMPLETED WITH ERRORS — check log: ${LOG_FILE}" >&2
    fi
    echo " Encrypted archive: ${BACKUP_ENCRYPTED}" >&2
    echo " SHA256 checksum:   ${CHECKSUM_FILE}" >&2
    echo " Size:              $(numfmt --to=iec "${BACKUP_SIZE_BYTES}" 2>/dev/null || echo "${BACKUP_SIZE_BYTES} bytes")" >&2
    echo " Start:             ${START_TIME}" >&2
    echo " End:               ${end_time}" >&2
    echo "============================================================" >&2
    echo "" >&2

    log_json "SUCCESS" "summary" "Backup complete" \
        "{\"encrypted_file\":\"${BACKUP_ENCRYPTED}\",\"size_bytes\":${BACKUP_SIZE_BYTES},\"start\":\"${START_TIME}\",\"end\":\"${end_time}\"}"

    exit $((1 - BACKUP_STATUS))
}

# Actually run main only if this script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
