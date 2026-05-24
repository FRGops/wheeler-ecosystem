#!/usr/bin/env bash
#===============================================================================
# Wheeler Enterprise Infrastructure — Full Restore Script
#===============================================================================
# Restores: PostgreSQL dbs, Redis snapshots, Docker volumes, PM2 configs,
#           Traefik configs, Nginx configs, environment files.
# Usage:    restore-all.sh [--list] [--dry-run] BACKUP_FILE BACKUP_PASSPHRASE
#           restore-all.sh --list-contents BACKUP_FILE
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

# -- Constants -------------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly BACKUP_ROOT="/root/infrastructure/backups"
readonly LOG_DIR="/var/log/wheeler"
readonly LOG_FILE="${LOG_DIR}/restore.log"
readonly HEALTHCHECK_SCRIPT="/root/infrastructure/enterprise/phase6-backup/healthcheck-all.sh"
readonly TEMP_ROOT="/tmp/wheeler-restore-$$"

# Runtime state
DRY_RUN=0
LIST_MODE=0
LIST_CONTENTS_MODE=0
RESTORE_SUMMARY=""
RESTORE_PASSED=0
RESTORE_FAILED=0

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

    local tag=""
    case "$level" in
        ERROR)  tag="ERR"  ;;
        WARN)   tag="WRN"  ;;
        SUCCESS)tag="OK"   ;;
        *)      tag="INF"  ;;
    esac
    echo "[${tag}] ${phase:+[${phase}] }${message}" >&2
}

# -- Utility ---------------------------------------------------------------------
dry_or_real() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would execute: $*" >&2
        return 0
    fi
    "$@"
}

check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_json "ERROR" "init" "Missing required dependency: ${cmd}" ""
        echo "ERROR: Required command '${cmd}' not found." >&2
        exit 1
    fi
}

confirm() {
    local prompt="$1"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would prompt: ${prompt} (auto-yes in dry-run)" >&2
        return 0
    fi
    read -rp "${prompt} [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# -- List Available Backups ------------------------------------------------------
list_available_backups() {
    echo "" >&2
    echo "============================================================" >&2
    echo " Available Backups in ${BACKUP_ROOT}" >&2
    echo "============================================================" >&2

    if [[ ! -d "$BACKUP_ROOT" ]]; then
        echo "  No backups directory found." >&2
        echo "============================================================" >&2
        echo "" >&2
        return 0
    fi

    local backups
    backups=$(find "$BACKUP_ROOT" -maxdepth 1 -name "backup-*.tar.gz.gpg" -type f 2>/dev/null | sort -r || true)

    if [[ -z "$backups" ]]; then
        echo "  No encrypted backups found." >&2
        echo "============================================================" >&2
        echo "" >&2
        return 0
    fi

    printf "  %-30s %10s %10s\n" "FILENAME" "SIZE" "CHECKSUM" >&2
    printf "  %-30s %10s %10s\n" "------------------------------" "----------" "----------" >&2

    while IFS= read -r backup_file; do
        local fname size checksum
        fname=$(basename "$backup_file")
        size=$(stat --printf="%s" "$backup_file" 2>/dev/null || echo "0")
        size_h=$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")
        if [[ -f "${backup_file}.sha256" ]]; then
            checksum=$(cut -d' ' -f1 "${backup_file}.sha256" 2>/dev/null || echo "N/A")
        else
            checksum="no-checksum"
        fi
        printf "  %-30s %10s %10s\n" "$fname" "$size_h" "${checksum:0:10}" >&2
    done <<< "$backups"

    echo "============================================================" >&2
    echo "" >&2
    echo "To restore: $0 <BACKUP_FILE> <PASSPHRASE>" >&2
    echo "            $0 --list-contents <BACKUP_FILE>" >&2
    echo "            $0 --dry-run <BACKUP_FILE> <PASSPHRASE>" >&2
    echo "" >&2
}

# -- List Backup Contents --------------------------------------------------------
list_backup_contents() {
    local encrypted_file="$1"
    local passphrase="${2:-}"

    if [[ ! -f "$encrypted_file" ]]; then
        echo "ERROR: Encrypted backup file not found: ${encrypted_file}" >&2
        return 1
    fi

    if [[ -z "$passphrase" ]]; then
        read -rsp "Enter backup decryption passphrase: " passphrase
        echo "" >&2
    fi

    if [[ -z "$passphrase" ]]; then
        echo "ERROR: Passphrase required." >&2
        return 1
    fi

    echo "============================================================" >&2
    echo " Contents of: $(basename "$encrypted_file")" >&2
    echo "============================================================" >&2

    # Decrypt and list contents without writing to disk
    gpg --decrypt --batch --passphrase "$passphrase" "$encrypted_file" 2>/dev/null | tar -tzf - 2>/dev/null || {
        echo "ERROR: Failed to decrypt or read archive. Check passphrase." >&2
        return 1
    }

    echo "============================================================" >&2
    echo "" >&2
}

# -- Decrypt and Extract ---------------------------------------------------------
decrypt_and_extract() {
    local encrypted_file="$1"
    local passphrase="$2"
    local extract_dir="$3"
    local phase="decrypt-extract"

    if [[ ! -f "$encrypted_file" ]]; then
        log_json "ERROR" "$phase" "Backup file not found: ${encrypted_file}" ""
        return 1
    fi

    if [[ -z "$passphrase" ]]; then
        log_json "ERROR" "$phase" "Passphrase is required" ""
        return 1
    fi

    log_json "INFO" "$phase" "Decrypting: ${encrypted_file}" ""

    mkdir -p "$extract_dir"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would decrypt and extract ${encrypted_file} to ${extract_dir}" >&2
        # For dry-run, simulate directory structure for inspection
        return 0
    fi

    # Decrypt and extract in one pipeline
    if gpg --decrypt --batch --passphrase "$passphrase" "$encrypted_file" 2>/dev/null | \
       tar -xzf - -C "$extract_dir" 2>/dev/null; then
        log_json "SUCCESS" "$phase" "Decrypted and extracted to ${extract_dir}" ""
    else
        log_json "ERROR" "$phase" "Decryption or extraction FAILED. Check passphrase and file integrity." ""
        return 1
    fi

    # Find the inner backup directory (backup-TIMESTAMP/)
    local inner_dir
    inner_dir=$(find "$extract_dir" -maxdepth 2 -type d -name "backup-*" 2>/dev/null | head -1)
    if [[ -z "$inner_dir" ]]; then
        # Maybe files are directly in extract_dir
        inner_dir="$extract_dir"
    fi
    echo "$inner_dir"
    return 0
}

# -- Restore PostgreSQL ----------------------------------------------------------
restore_postgresql() {
    local backup_inner_dir="$1"
    local phase="postgresql-restore"

    local pg_backup_dir="${backup_inner_dir}/postgresql"
    if [[ ! -d "$pg_backup_dir" ]]; then
        log_json "INFO" "$phase" "No PostgreSQL backups in this archive — skipping" ""
        return 0
    fi

    log_json "INFO" "$phase" "Starting PostgreSQL restore" ""

    local dumps
    dumps=$(find "$pg_backup_dir" -name "*.sql.gz" -type f 2>/dev/null || true)

    if [[ -z "$dumps" ]]; then
        log_json "INFO" "$phase" "No PostgreSQL dump files found" ""
        return 0
    fi

    while IFS= read -r dump_gz; do
        local dump_sql="${dump_gz%.gz}"
        local dump_name
        dump_name=$(basename "$dump_gz")
        # Derive container name from filename: container-dump.sql.gz -> container
        local container
        container=$(echo "$dump_name" | sed -E 's/-dump\.sql\.gz$//' | sed -E 's/-combined\.sql\.gz$//')

        if [[ -z "$container" ]]; then
            log_json "WARN" "$phase" "Could not determine container name from ${dump_name}" ""
            continue
        fi

        # Check if container exists (running or stopped)
        if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
            log_json "WARN" "$phase" "Container '${container}' not found — skipping PostgreSQL restore for this dump" ""
            log_json "INFO" "$phase" "Dump file ${dump_name} is available at ${dump_gz} for manual restore" ""
            continue
        fi

        log_json "INFO" "$phase" "Restoring PostgreSQL: ${container} from ${dump_name}" ""

        if [[ $DRY_RUN -eq 1 ]]; then
            echo "[DRY-RUN] Would restore PostgreSQL on container: ${container}" >&2
            continue
        fi

        # Decompress
        if ! gunzip -c "$dump_gz" > "$dump_sql" 2>/dev/null; then
            log_json "ERROR" "$phase" "Failed to decompress ${dump_name}" ""
            ((RESTORE_FAILED++))
            continue
        fi

        local pg_user
        pg_user=$(docker exec "$container" printenv POSTGRES_USER 2>/dev/null || echo "postgres")

        # Copy dump into container
        docker cp "$dump_sql" "${container}:/tmp/restore.sql" 2>/dev/null || {
            log_json "ERROR" "$phase" "Failed to copy dump into ${container}" ""
            ((RESTORE_FAILED++))
            rm -f "$dump_sql"
            continue
        }

        # Execute restore
        if docker exec "$container" psql -U "$pg_user" -f /tmp/restore.sql &>/dev/null; then
            log_json "SUCCESS" "$phase" "PostgreSQL restore succeeded: ${container}" ""
            ((RESTORE_PASSED++))
        else
            log_json "ERROR" "$phase" "PostgreSQL restore FAILED: ${container}" ""
            ((RESTORE_FAILED++))
        fi

        # Cleanup
        docker exec "$container" rm -f /tmp/restore.sql 2>/dev/null || true
        rm -f "$dump_sql"

        # Validate with pg_isready
        if docker exec "$container" pg_isready -U "$pg_user" &>/dev/null; then
            log_json "SUCCESS" "$phase" "PostgreSQL health check passed: ${container} (pg_isready OK)" ""
        else
            log_json "WARN" "$phase" "PostgreSQL health check FAILED on ${container} — may need manual intervention" ""
        fi

    done <<< "$dumps"

    return 0
}

# -- Restore Redis ---------------------------------------------------------------
restore_redis() {
    local backup_inner_dir="$1"
    local phase="redis-restore"

    local redis_backup_dir="${backup_inner_dir}/redis"
    if [[ ! -d "$redis_backup_dir" ]]; then
        log_json "INFO" "$phase" "No Redis backups in this archive — skipping" ""
        return 0
    fi

    log_json "INFO" "$phase" "Starting Redis restore" ""

    local rdb_files
    rdb_files=$(find "$redis_backup_dir" -name "*.rdb" -type f 2>/dev/null || true)

    if [[ -z "$rdb_files" ]]; then
        log_json "INFO" "$phase" "No Redis RDB files found" ""
        return 0
    fi

    while IFS= read -r rdb_file; do
        local rdb_name
        rdb_name=$(basename "$rdb_file")
        # Derive container name: container-dump.rdb -> container
        local container="${rdb_name%-dump.rdb}"

        if [[ -z "$container" ]]; then
            log_json "WARN" "$phase" "Could not determine container name from ${rdb_name}" ""
            continue
        fi

        if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
            log_json "WARN" "$phase" "Container '${container}' not found — skipping Redis restore" ""
            continue
        fi

        log_json "INFO" "$phase" "Restoring Redis: ${container} from ${rdb_name}" ""

        if [[ $DRY_RUN -eq 1 ]]; then
            echo "[DRY-RUN] Would restore Redis on container: ${container}" >&2
            continue
        fi

        # Get Redis data dir
        local rdb_path
        rdb_path=$(docker exec "$container" redis-cli CONFIG GET dir 2>/dev/null | tail -1 || echo "/data")
        local rdb_filename
        rdb_filename=$(docker exec "$container" redis-cli CONFIG GET dbfilename 2>/dev/null | tail -1 || echo "dump.rdb")

        # Stop Redis writes
        docker exec "$container" redis-cli CONFIG SET appendonly no 2>/dev/null || true

        # Copy RDB into container
        docker cp "$rdb_file" "${container}:${rdb_path}/${rdb_filename}" 2>/dev/null || {
            log_json "ERROR" "$phase" "Failed to copy RDB into ${container}" ""
            ((RESTORE_FAILED++))
            continue
        }

        # Restart Redis inside container (or restart container)
        docker exec "$container" redis-cli SHUTDOWN NOSAVE 2>/dev/null || true
        sleep 2

        # Wait for Redis to come back (Docker auto-restarts if restart policy is set)
        local waited=0
        while [[ $waited -lt 30 ]]; do
            if docker exec "$container" redis-cli PING 2>/dev/null | grep -q "PONG"; then
                break
            fi
            sleep 1
            ((waited++))
        done

        if docker exec "$container" redis-cli PING 2>/dev/null | grep -q "PONG"; then
            log_json "SUCCESS" "$phase" "Redis restore succeeded: ${container} (PING OK)" ""
            ((RESTORE_PASSED++))
        else
            # If container died and didn't restart, try starting it
            docker start "$container" 2>/dev/null || true
            sleep 3
            if docker exec "$container" redis-cli PING 2>/dev/null | grep -q "PONG"; then
                log_json "SUCCESS" "$phase" "Redis restore succeeded after container restart: ${container}" ""
                ((RESTORE_PASSED++))
            else
                log_json "ERROR" "$phase" "Redis restore FAILED: ${container} — Redis not responding" ""
                ((RESTORE_FAILED++))
            fi
        fi

        # Restore AOF if available
        local aof_file="${redis_backup_dir}/${container}-appendonly.aof"
        if [[ -f "$aof_file" ]]; then
            docker cp "$aof_file" "${container}:${rdb_path}/appendonly.aof" 2>/dev/null || true
            log_json "INFO" "$phase" "Restored AOF for ${container}" ""
        fi

    done <<< "$rdb_files"

    return 0
}

# -- Restore Docker Volumes ------------------------------------------------------
restore_docker_volumes() {
    local backup_inner_dir="$1"
    local phase="volumes-restore"

    local vol_backup_dir="${backup_inner_dir}/docker-volumes"
    if [[ ! -d "$vol_backup_dir" ]]; then
        log_json "INFO" "$phase" "No Docker volume backups in this archive — skipping" ""
        return 0
    fi

    log_json "INFO" "$phase" "Starting Docker volume restore" ""

    local vol_tars
    vol_tars=$(find "$vol_backup_dir" -name "*.tar.gz" -type f 2>/dev/null || true)

    if [[ -z "$vol_tars" ]]; then
        log_json "INFO" "$phase" "No volume tar files found" ""
        return 0
    fi

    while IFS= read -r vol_tar; do
        local tar_name vol_name
        tar_name=$(basename "$vol_tar")
        vol_name="${tar_name%.tar.gz}"

        log_json "INFO" "$phase" "Restoring volume: ${vol_name}" ""

        # Check if volume exists
        if ! docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^${vol_name}$"; then
            log_json "WARN" "$phase" "Volume '${vol_name}' does not exist — creating and restoring" ""
            if [[ $DRY_RUN -eq 0 ]]; then
                docker volume create "$vol_name" 2>/dev/null || true
            fi
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
            echo "[DRY-RUN] Would restore volume: ${vol_name}" >&2
            continue
        fi

        # Find containers using this volume and stop them
        local using_containers
        using_containers=$(docker ps -q --filter "volume=${vol_name}" 2>/dev/null || true)

        if [[ -n "$using_containers" ]]; then
            for uc in $using_containers; do
                local uc_name
                uc_name=$(docker inspect --format '{{.Name}}' "$uc" 2>/dev/null | sed 's|^/||')
                log_json "INFO" "$phase" "Stopping container '${uc_name}' for volume restore" ""
                dry_or_real docker stop "$uc" 2>/dev/null || true
            done
        fi

        # Get volume mountpoint
        local mount_point
        mount_point=$(docker volume inspect "$vol_name" --format '{{.Mountpoint}}' 2>/dev/null || true)

        if [[ -n "$mount_point" && -d "$mount_point" ]]; then
            # Clear existing content and extract
            dry_or_real rm -rf "${mount_point:?}"/* 2>/dev/null || true
            if dry_or_real tar -xzf "$vol_tar" -C "$mount_point" 2>/dev/null; then
                log_json "SUCCESS" "$phase" "Volume restore succeeded: ${vol_name}" ""
                ((RESTORE_PASSED++))
            else
                log_json "ERROR" "$phase" "Volume restore FAILED: ${vol_name}" ""
                ((RESTORE_FAILED++))
            fi
        else
            log_json "ERROR" "$phase" "Cannot determine mountpoint for volume: ${vol_name}" ""
            ((RESTORE_FAILED++))
        fi

        # Restart stopped containers
        if [[ -n "$using_containers" ]]; then
            for uc in $using_containers; do
                local uc_name
                uc_name=$(docker inspect --format '{{.Name}}' "$uc" 2>/dev/null | sed 's|^/||')
                log_json "INFO" "$phase" "Restarting container '${uc_name}'" ""
                dry_or_real docker start "$uc" 2>/dev/null || true
            done
        fi

    done <<< "$vol_tars"

    return 0
}

# -- Restore Configs -------------------------------------------------------------
restore_configs() {
    local backup_inner_dir="$1"
    local phase="configs-restore"

    log_json "INFO" "$phase" "Starting configuration restore" ""

    # -- Traefik configs --
    local traefik_dir="${backup_inner_dir}/traefik"
    if [[ -d "$traefik_dir" ]]; then
        log_json "INFO" "$phase" "Restoring Traefik configs" ""

        local traefik_tars
        traefik_tars=$(find "$traefik_dir" -name "*.tar.gz" -type f 2>/dev/null || true)

        if [[ -n "$traefik_tars" ]]; then
            while IFS= read -r tt; do
                local tt_name
                tt_name=$(basename "$tt")
                log_json "INFO" "$phase" "Extracting Traefik archive: ${tt_name}" ""

                if [[ $DRY_RUN -eq 0 ]]; then
                    # hetzner-traefik.tar.gz -> extract at /root/infrastructure/hetzner/
                    # hostinger-traefik.tar.gz -> extract at /root/infrastructure/hostinger/
                    # shared-traefik.tar.gz -> extract at /root/infrastructure/shared/
                    if [[ "$tt_name" == "hetzner-traefik.tar.gz" ]]; then
                        tar -xzf "$tt" -C /root/infrastructure/hetzner/ 2>/dev/null || true
                    elif [[ "$tt_name" == "hostinger-traefik.tar.gz" ]]; then
                        tar -xzf "$tt" -C /root/infrastructure/hostinger/ 2>/dev/null || true
                    elif [[ "$tt_name" == "shared-traefik.tar.gz" ]]; then
                        tar -xzf "$tt" -C /root/infrastructure/shared/ 2>/dev/null || true
                    else
                        # Generic: base name before .tar.gz is the folder to restore to
                        local base="${tt_name%.tar.gz}"
                        tar -xzf "$tt" -C /root/infrastructure/ 2>/dev/null || true
                    fi
                else
                    echo "[DRY-RUN] Would restore Traefik config from: ${tt_name}" >&2
                fi
            done <<< "$traefik_tars"
            ((RESTORE_PASSED++))
        fi
    else
        log_json "INFO" "$phase" "No Traefik configs in backup" ""
    fi

    # -- Nginx configs --
    local nginx_tar="${backup_inner_dir}/nginx/etc-nginx.tar.gz"
    if [[ -f "$nginx_tar" ]]; then
        log_json "INFO" "$phase" "Restoring Nginx configs" ""
        if [[ $DRY_RUN -eq 0 ]]; then
            if tar -xzf "$nginx_tar" -C /etc/ 2>/dev/null; then
                log_json "SUCCESS" "$phase" "Nginx configs restored" ""
                ((RESTORE_PASSED++))
                # Reload nginx if running
                nginx -t 2>/dev/null && nginx -s reload 2>/dev/null || true
            else
                log_json "ERROR" "$phase" "Nginx config restore FAILED" ""
                ((RESTORE_FAILED++))
            fi
        else
            echo "[DRY-RUN] Would restore Nginx configs from: ${nginx_tar}" >&2
        fi
    else
        log_json "INFO" "$phase" "No Nginx configs in backup" ""
    fi

    # -- PM2 configs --
    local pm2_dir="${backup_inner_dir}/pm2"
    if [[ -d "$pm2_dir" ]]; then
        log_json "INFO" "$phase" "Restoring PM2 configs" ""

        # Restore dump.pm2
        if [[ -f "${pm2_dir}/dump.pm2" ]]; then
            if [[ $DRY_RUN -eq 0 ]]; then
                mkdir -p /root/.pm2
                cp "${pm2_dir}/dump.pm2" /root/.pm2/dump.pm2
                if command -v pm2 &>/dev/null; then
                    pm2 resurrect 2>/dev/null || true
                fi
                ((RESTORE_PASSED++))
            else
                echo "[DRY-RUN] Would restore PM2 dump.pm2" >&2
            fi
        fi

        # Restore ecosystem files
        local ecosystem_files
        ecosystem_files=$(find "$pm2_dir" -name "ecosystem.config.*" -type f 2>/dev/null || true)
        if [[ -n "$ecosystem_files" ]]; then
            while IFS= read -r ef; do
                if [[ $DRY_RUN -eq 0 ]]; then
                    log_json "INFO" "$phase" "Ecosystem config available: $(basename "$ef") — restore manually if needed" ""
                else
                    echo "[DRY-RUN] Would note ecosystem config: $(basename "$ef")" >&2
                fi
            done <<< "$ecosystem_files"
        fi
    fi

    # -- Environment files --
    local env_dir="${backup_inner_dir}/env-files"
    if [[ -d "$env_dir" ]]; then
        log_json "INFO" "$phase" "Restoring environment files" ""

        local env_files
        env_files=$(find "$env_dir" -type f 2>/dev/null || true)

        if [[ -n "$env_files" ]]; then
            if [[ $DRY_RUN -eq 0 ]]; then
                while IFS= read -r env_f; do
                    local safe_name original_path
                    safe_name=$(basename "$env_f")
                    # Reverse the safe naming: replace _ back to /
                    # e.g., opt_stacks_02-aiops_.env -> /opt/stacks/02-aiops/.env
                    original_path="/${safe_name//_//}"
                    # But that's too aggressive — only restore to known locations
                    log_json "INFO" "$phase" "Env file available: $(basename "$env_f") (review before restoring)" ""
                done <<< "$env_files"
                log_json "SUCCESS" "$phase" "Environment files extracted to ${env_dir} — review and restore manually to prevent config drift" ""
                ((RESTORE_PASSED++))
            else
                echo "[DRY-RUN] Would extract environment files (review before applying)" >&2
            fi
        fi
    fi

    return 0
}

# -- Validation ------------------------------------------------------------------
run_validation() {
    local phase="validation"

    log_json "INFO" "$phase" "Running post-restore validation" ""

    echo "" >&2
    echo "============================================================" >&2
    echo " POST-RESTORE VALIDATION" >&2
    echo "============================================================" >&2

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY-RUN] Would run healthcheck-all.sh" >&2
        echo "============================================================" >&2
        echo "" >&2
        return 0
    fi

    # Quick Docker health check
    echo "" >&2
    echo "--- Docker Container Status ---" >&2
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null || true
    echo "" >&2

    # Run full healthcheck if available
    if [[ -x "$HEALTHCHECK_SCRIPT" ]]; then
        echo "--- Running healthcheck-all.sh ---" >&2
        if "$HEALTHCHECK_SCRIPT" 2>&1; then
            log_json "SUCCESS" "$phase" "Healthcheck passed" ""
            echo "HEALTHCHECK: PASSED" >&2
        else
            log_json "WARN" "$phase" "Healthcheck returned non-zero — review output above" ""
            echo "HEALTHCHECK: WARNINGS/FAILURES — review above" >&2
        fi
    else
        log_json "WARN" "$phase" "healthcheck-all.sh not found or not executable" ""
        echo "HEALTHCHECK: SKIPPED (script not found)" >&2
    fi

    # Quick connectivity validation
    echo "" >&2
    echo "--- Quick Connectivity Checks ---" >&2
    # Check each postgres container
    local pg_containers
    pg_containers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i 'postgres' || true)
    for pg in $pg_containers; do
        local pg_user
        pg_user=$(docker exec "$pg" printenv POSTGRES_USER 2>/dev/null || echo "postgres")
        if docker exec "$pg" pg_isready -U "$pg_user" &>/dev/null; then
            echo "  [OK] PostgreSQL ${pg}: pg_isready passed" >&2
        else
            echo "  [FAIL] PostgreSQL ${pg}: pg_isready FAILED" >&2
        fi
    done

    # Check each redis container
    local redis_containers
    redis_containers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i 'redis' || true)
    for rd in $redis_containers; do
        if docker exec "$rd" redis-cli PING 2>/dev/null | grep -q "PONG"; then
            echo "  [OK] Redis ${rd}: PONG" >&2
        else
            echo "  [FAIL] Redis ${rd}: not responding" >&2
        fi
    done

    # Check Traefik
    if curl -sf http://localhost:8080/api/rawdata &>/dev/null; then
        echo "  [OK] Traefik: API responding" >&2
    else
        echo "  [INFO] Traefik: API not reachable (may be expected)" >&2
    fi

    echo "============================================================" >&2
    echo "" >&2

    return 0
}

# -- Rollback Instructions -------------------------------------------------------
print_rollback_instructions() {
    local phase="rollback"

    echo "" >&2
    echo "============================================================" >&2
    echo " ROLLBACK INSTRUCTIONS" >&2
    echo "============================================================" >&2
    echo "" >&2
    echo " If the restore did not succeed, follow these steps:" >&2
    echo "" >&2
    echo " 1. List available backups:" >&2
    echo "      $0 --list" >&2
    echo "" >&2
    echo " 2. Choose the PREVIOUS backup (the one before this restore)" >&2
    echo "      and re-run restore:" >&2
    echo "      $0 <PREVIOUS_BACKUP_FILE> <PASSPHRASE>" >&2
    echo "" >&2
    echo " 3. After successful rollback, validate:" >&2
    echo "      $HEALTHCHECK_SCRIPT" >&2
    echo "" >&2
    echo " 4. To restore to the state BEFORE this restore attempt," >&2
    echo "    select a backup timestamped just prior to this run." >&2
    echo "" >&2
    echo "============================================================" >&2
    echo "" >&2
}

# -- Usage -----------------------------------------------------------------------
usage() {
    cat <<'EOF' >&2
Usage: restore-all.sh [OPTIONS] [BACKUP_FILE] [BACKUP_PASSPHRASE]

Options:
  --list                List all available backups (date, size, type)
  --list-contents FILE  List contents of a specific backup archive
  --dry-run             Simulate restore without making any changes

Arguments:
  BACKUP_FILE       Path to the encrypted .tar.gz.gpg backup file
  BACKUP_PASSPHRASE Decryption passphrase (reads from BACKUP_PASSPHRASE
                    env var if not provided)

Examples:
  restore-all.sh --list
  restore-all.sh --list-contents /root/infrastructure/backups/backup-20260523-120000.tar.gz.gpg
  restore-all.sh --dry-run /root/infrastructure/backups/backup-20260523-120000.tar.gz.gpg
  restore-all.sh /root/infrastructure/backups/backup-20260523-120000.tar.gz.gpg "mypassphrase"
  BACKUP_PASSPHRASE="secret" restore-all.sh /path/to/backup.tar.gz.gpg

Environment:
  BACKUP_PASSPHRASE   Decryption passphrase (avoids prompting)
EOF
}

# -- Main ------------------------------------------------------------------------
main() {
    local encrypted_file=""
    local passphrase=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list)
                LIST_MODE=1
                shift
                ;;
            --list-contents)
                LIST_CONTENTS_MODE=1
                shift
                if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                    encrypted_file="$1"
                    shift
                fi
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            -*)
                echo "ERROR: Unknown option: $1" >&2
                usage
                exit 1
                ;;
            *)
                if [[ -z "$encrypted_file" ]]; then
                    encrypted_file="$1"
                elif [[ -z "$passphrase" ]]; then
                    passphrase="$1"
                else
                    echo "ERROR: Unexpected argument: $1" >&2
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # --list mode: no further processing needed
    if [[ $LIST_MODE -eq 1 ]]; then
        list_available_backups
        exit 0
    fi

    # --list-contents mode
    if [[ $LIST_CONTENTS_MODE -eq 1 ]]; then
        if [[ -z "$encrypted_file" ]]; then
            echo "ERROR: --list-contents requires a backup file argument" >&2
            usage
            exit 1
        fi
        list_backup_contents "$encrypted_file" "$passphrase"
        exit $?
    fi

    # Normal restore mode: backup file is required
    if [[ -z "$encrypted_file" ]]; then
        echo "No backup file specified. Use --list to see available backups." >&2
        echo "" >&2
        list_available_backups
        usage
        exit 1
    fi

    # Resolve passphrase
    if [[ -z "$passphrase" ]]; then
        passphrase="${BACKUP_PASSPHRASE:-}"
    fi

    if [[ -z "$passphrase" ]]; then
        read -rsp "Enter backup decryption passphrase: " passphrase
        echo "" >&2
    fi

    if [[ -z "$passphrase" ]]; then
        echo "ERROR: Passphrase is required for decryption." >&2
        exit 1
    fi

    # Init
    init_logging

    log_json "INFO" "init" "=== Wheeler Enterprise Restore Started ===" \
        "{\"backup_file\":\"${encrypted_file}\",\"dry_run\":${DRY_RUN}}"

    # Check dependencies
    for dep in docker jq gpg tar gzip; do
        check_dependency "$dep"
    done

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "" >&2
        echo "============================================================" >&2
        echo " DRY RUN MODE — NO CHANGES WILL BE MADE" >&2
        echo "============================================================" >&2
        echo "" >&2
    else
        echo "" >&2
        echo "============================================================" >&2
        echo " RESTORE WILL MODIFY LIVE DATA" >&2
        echo "============================================================" >&2
        echo "" >&2
        if ! confirm "Proceed with restore?"; then
            log_json "INFO" "init" "Restore cancelled by user" ""
            exit 0
        fi
    fi

    mkdir -p "$TEMP_ROOT"

    # Step 1: Decrypt and Extract
    local backup_inner_dir
    backup_inner_dir=$(decrypt_and_extract "$encrypted_file" "$passphrase" "$TEMP_ROOT") || {
        log_json "ERROR" "init" "Decryption/extraction failed — aborting" ""
        rm -rf "$TEMP_ROOT"
        exit 1
    }

    log_json "INFO" "init" "Backup extracted. Inner directory: ${backup_inner_dir}" ""

    # Step 2: Restore PostgreSQL
    restore_postgresql "$backup_inner_dir"

    # Step 3: Restore Redis
    restore_redis "$backup_inner_dir"

    # Step 4: Restore Docker Volumes
    restore_docker_volumes "$backup_inner_dir"

    # Step 5: Restore Configs
    restore_configs "$backup_inner_dir"

    # Step 6: Validate
    run_validation

    # Step 7: Rollback instructions (always print)
    print_rollback_instructions

    # -- Summary --
    local total=$((RESTORE_PASSED + RESTORE_FAILED))

    echo "" >&2
    echo "============================================================" >&2
    echo " RESTORE SUMMARY" >&2
    echo "============================================================" >&2
    echo "  Operations passed:  ${RESTORE_PASSED}" >&2
    echo "  Operations failed:  ${RESTORE_FAILED}" >&2
    if [[ $total -gt 0 ]]; then
        echo "  Total:              ${total}" >&2
    fi
    echo "  Temp directory:     ${TEMP_ROOT}" >&2
    echo "  Log file:           ${LOG_FILE}" >&2
    echo "============================================================" >&2
    echo "" >&2

    log_json "SUCCESS" "summary" "Restore completed" \
        "{\"passed\":${RESTORE_PASSED},\"failed\":${RESTORE_FAILED},\"dry_run\":${DRY_RUN}}"

    # Clean temp files (keep on failure for inspection)
    if [[ $RESTORE_FAILED -eq 0 ]]; then
        rm -rf "$TEMP_ROOT" 2>/dev/null || true
        log_json "INFO" "cleanup" "Removed temp directory: ${TEMP_ROOT}" ""
    else
        log_json "WARN" "cleanup" "Temp directory kept for inspection: ${TEMP_ROOT}" ""
    fi

    if [[ $RESTORE_FAILED -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

# Actually run main only if this script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
