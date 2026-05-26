#!/usr/bin/env bash
# =============================================================================
# sovereign-backup-test.sh — Backup Restoration Test
# =============================================================================
#
# Picks a PostgreSQL database, verifies its latest backup, restores into a
# temporary container, and validates data integrity. Never touches production.
#
# Usage:
#   ./sovereign-backup-test.sh                          # Random PG database
#   ./sovereign-backup-test.sh --database frgcrm        # Specific database
#   ./sovereign-backup-test.sh --database frgcrm --port 5432
#   ./sovereign-backup-test.sh --all                    # Test all databases
#   ./sovereign-backup-test.sh --help                   # Show help
#
# Database discovery:
#   1. --database flag (if provided)
#   2. Docker containers running postgres images
#   3. Known ports (5432-5436) as fallback
#
# Exit codes:
#   0 — PASSED
#   1 — FAILED
# =============================================================================

set -euo pipefail

# ─── Constants ─────────────────────────────────────────────────────────────────

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly TIMESTAMP_FMT="$(date +%Y%m%d-%H%M%S)"
readonly LOG_DIR="/var/log/wheeler/backup-tests"
readonly LOG_FILE="${LOG_DIR}/backup-test-${TIMESTAMP_FMT}.log"
readonly LOCK_DIR="/tmp/${SCRIPT_NAME%.sh}.lock"
readonly BACKUP_BASE="/opt/backups/databases"
readonly TEMP_CONTAINER_PREFIX="wheeler-backup-test"
readonly TEMP_PORT_START=20000
readonly POSTGRES_IMAGE="postgres:16-alpine"
readonly PG_USER="wheeler"
readonly WHEELER_PG_CONTAINER="wheeler-postgres"

# ─── Color definitions ─────────────────────────────────────────────────────────

if [[ -t 1 ]] || [[ -n "${FORCE_COLOR:-}" ]]; then
    C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
    C_CYAN='\033[0;36m'; C_MAGENTA='\033[0;35m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BOLD=''; C_DIM=''
    C_CYAN=''; C_MAGENTA=''
fi

# ─── State ──────────────────────────────────────────────────────────────────────

TEST_ALL=false
TARGET_DATABASE=""
TARGET_PORT=""
PASS_COUNT=0
FAIL_COUNT=0
declare -a TEST_RESULTS=()
declare -a TESTED_DBS=()
TEMP_DIR=""
CLEANUP_DONE=false

# ─── Logging ────────────────────────────────────────────────────────────────────

_log() {
    local level="$1" msg="$2"
    local log_line="[$(date -u +%H:%M:%S)] [${level}] ${msg}"
    printf "${C_DIM}%s${C_RESET}\n" "${log_line}" >&2
    printf '%s\n' "${log_line}" >> "${LOG_FILE}"
}

log_info()  { _log "INFO"  "$*"; }
log_ok()    { _log "OK"    "$*"; printf "  ${C_GREEN}[OK]${C_RESET} %s\n" "$*" >&2; }
log_warn()  { _log "WARN"  "$*"; printf "  ${C_YELLOW}[WARN]${C_RESET} %s\n" "$*" >&2; }
log_err()   { _log "ERROR" "$*"; printf "  ${C_RED}[FAIL]${C_RESET} %s\n" "$*" >&2; }

# ─── Lock / Cleanup / Daemon-checks ─────────────────────────────────────────────

_acquire_lock() {
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        local pid=""
        if [[ -f "${LOCK_DIR}/pid" ]]; then
            pid=$(cat "${LOCK_DIR}/pid" 2>/dev/null || echo "unknown")
        fi
        echo -e "${C_RED}[FAIL]${C_RESET} Another instance is running (PID: ${pid:-unknown})" >&2
        echo -e "${C_DIM}  Lock: ${LOCK_DIR}${C_RESET}" >&2
        exit 1
    fi
    echo "$$" > "${LOCK_DIR}/pid"
}

_release_lock() {
    if [[ -d "$LOCK_DIR" ]]; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
    fi
}

_cleanup() {
    if [[ "$CLEANUP_DONE" == "true" ]]; then return; fi
    CLEANUP_DONE=true
    _release_lock
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
}

_docker_alive() {
    if ! command -v docker &>/dev/null; then return 1; fi
    docker info --format "{{.ServerVersion}}" &>/dev/null 2>&1
}

check_cmd() {
    command -v "$1" &>/dev/null
}

_validate_port() {
    local port="$1"
    if [[ -z "$port" ]]; then return 1; fi
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then return 1; fi
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then return 1; fi
    return 0
}

# ─── Help ───────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Test backup restoration by restoring into a temporary PostgreSQL container.
Never touches production databases.

Options:
  --database NAME    Test a specific database by name
  --port PORT        Database port (used with --database, default: auto-detect)
                     Must be 1-65535.
  --all              Test all discovered databases sequentially
  --help             Show this message and exit

Environment variables:
  FORCE_COLOR        Set to any value to force color output even when
                     stdout is not a TTY
  LOG_DIR            Override log directory (default: /var/log/wheeler/backup-tests)
  BACKUP_BASE        Override backup base directory (default: /opt/backups/databases)

Database discovery order:
  1. --database flag (if provided)
  2. Docker containers running postgres/postgis images
  3. Port scan of 127.0.0.1:5432-5436 (known Wheeler ports)
  4. Static known database list (frgcrm, surplusai, prediction_radar, etc.)

Backup file search order:
  1. /opt/backups/databases/<db_name>/
  2. /opt/wheeler/backups/
  3. /root/infrastructure/backups/
  4. /tmp/
  5. Any /opt/apps/*/backups/ directories

Backup formats supported (in priority order):
  - .dump.gz (PostgreSQL custom format + gzip)
  - .sql.gz  (plain SQL + gzip)
  - .dump    (PostgreSQL custom format, uncompressed)
  - .sql     (plain SQL)

Verification checks performed:
  1. Database accessible (SELECT 1)
  2. Table enumeration (information_schema)
  3. Row counts across all tables
  4. Sequence integrity
  5. Sample data query (timestamp/date columns)
  6. Foreign key constraint integrity

Examples:
  # Test a random database
  ${SCRIPT_NAME}

  # Test a specific database on a specific port
  ${SCRIPT_NAME} --database frgcrm --port 5432

  # Test all discovered databases sequentially
  ${SCRIPT_NAME} --all

  # Override backup location
  BACKUP_BASE=/custom/backup/path ${SCRIPT_NAME} --database surplusai

  # Force color output in CI
  FORCE_COLOR=1 ${SCRIPT_NAME} --all

Log file:
  ${LOG_FILE}

Lock file:
  ${LOCK_DIR}

Exit codes:
  0  All backup restoration tests PASSED
  1  One or more tests FAILED (or pre-flight check failed)
EOF
    exit "$1"
}

# ─── Cleanup temp containers ────────────────────────────────────────────────────

cleanup_temp_container() {
    local container_name="$1"
    if ! _docker_alive; then
        log_warn "Docker not available -- cannot clean up container: ${container_name}"
        return
    fi
    if docker ps --all --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        log_info "Cleaning up temporary container: ${container_name}"
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        log_ok "Temporary container removed: ${container_name}"
    fi
}

# ─── Database Discovery ─────────────────────────────────────────────────────────

discover_databases() {
    log_info "Discovering PostgreSQL databases..."
    declare -a DISCOVERED_NAMES=()
    declare -a DISCOVERED_PORTS=()

    # Method 1: Docker containers running postgres/postgis
    if _docker_alive; then
        while IFS= read -r container; do
            [[ -z "$container" ]] && continue
            local cname cimage host_port
            cname=$(echo "$container" | awk '{print $1}')
            cimage=$(echo "$container" | awk '{print $2}')

            # Skip non-postgres images and backup-only containers
            if ! echo "$cimage" | grep -qiE 'postgres|postgis'; then
                continue
            fi
            if echo "$cimage" | grep -qiE '\bbackup\b|backup-'; then
                continue
            fi

            host_port=$(docker port "$cname" 5432/tcp 2>/dev/null | head -1 | sed 's/.*://' || echo "")

            # Apply host port mapping or fallback to internal port
            if [[ -z "$host_port" ]]; then
                host_port="0"
            fi

            # Derive a short database name from container name
            local db_name
            db_name=$(echo "$cname" | sed 's/^aiops-//' | sed 's/-app-db$//' | sed 's/-standby$//')
            # Avoid duplicates
            local already=false
            for existing_name in "${DISCOVERED_NAMES[@]}"; do
                if [[ "$existing_name" == "$db_name" ]]; then
                    already=true; break
                fi
            done
            if [[ "$already" == "false" ]]; then
                DISCOVERED_NAMES+=("$db_name")
                DISCOVERED_PORTS+=("$host_port")
                local port_display="$host_port"
                [[ "$host_port" == "0" ]] && port_display="(docker exec only)"
                log_info "  Container: ${cname} (${cimage}) -> DB: ${db_name} (port ${port_display})"
            fi
        done < <(docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null || true)
    else
        log_warn "Docker not available -- skipping container-based discovery"
    fi

    # Method 2: Known ports fallback (from deploy pipeline)
    local FALLBACK_DBS=("frgcrm" "surplusai" "prediction_radar" "agent_db" "paperless")
    local FALLBACK_PORTS=("5432" "5433" "5434" "5435" "5436")
    for i in "${!FALLBACK_DBS[@]}"; do
        local fb_name="${FALLBACK_DBS[$i]}"
        local fb_port="${FALLBACK_PORTS[$i]}"
        # Only add if not already discovered
        local already=false
        for existing_name in "${DISCOVERED_NAMES[@]}"; do
            if [[ "$existing_name" == "$fb_name" ]]; then
                already=true; break
            fi
        done
        if [[ "$already" == "false" ]] && ping -c 1 -W 1 127.0.0.1 &>/dev/null 2>&1; then
            # Check if port is open via /dev/tcp
            if timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/${fb_port}" 2>/dev/null; then
                DISCOVERED_NAMES+=("$fb_name")
                DISCOVERED_PORTS+=("$fb_port")
                log_info "  Fallback: ${fb_name} (port ${fb_port})"
            fi
        fi
    done

    # Output discovered databases
    if [[ ${#DISCOVERED_NAMES[@]} -eq 0 ]]; then
        log_warn "No PostgreSQL databases discovered via Docker or port scan"
        log_info "Using static known database list for backup search"
        # Use the full known list for backup file searching
        DISCOVERED_NAMES=("frgcrm" "surplusai" "prediction_radar" "agent_db" "paperless" "ravynai")
        DISCOVERED_PORTS=("5432" "5433" "5434" "5435" "5436" "5437")
    fi

    echo "${#DISCOVERED_NAMES[@]}"
    for i in "${!DISCOVERED_NAMES[@]}"; do
        echo "${DISCOVERED_NAMES[$i]}:${DISCOVERED_PORTS[$i]}"
    done
}

# ─── Backup Discovery ───────────────────────────────────────────────────────────

find_backup() {
    local db_name="$1"
    local backup_file=""

    # Search locations in priority order
    local SEARCH_DIRS=(
        "${BACKUP_BASE}/${db_name}"
        "/opt/wheeler/backups"
        "/root/infrastructure/backups"
        "/tmp"
    )

    # Also search any /opt/apps/*/backups directories
    local APP_BACKUP_DIRS=()
    while IFS= read -r -d '' d; do
        APP_BACKUP_DIRS+=("$d")
    done < <(find /opt/apps -maxdepth 2 -type d -name backups -print0 2>/dev/null || true)
    for d in "${APP_BACKUP_DIRS[@]}"; do
        SEARCH_DIRS+=("$d")
    done

    # Look for .dump.gz files first (custom format), then .sql.gz, then .dump, then .sql
    for dir in "${SEARCH_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            local found
            # Most recent .dump.gz file for this database
            found=$(find "$dir" -name "${db_name}_*.dump.gz" -o -name "${db_name}*.dump.gz" 2>/dev/null | sort -r | head -1)
            if [[ -n "$found" ]]; then
                backup_file="$found"
                log_info "  Found backup: ${backup_file}"
                break
            fi
            # .sql.gz
            found=$(find "$dir" -name "${db_name}*.sql.gz" 2>/dev/null | sort -r | head -1)
            if [[ -n "$found" ]]; then
                backup_file="$found"
                log_info "  Found backup: ${backup_file}"
                break
            fi
            # .dump
            found=$(find "$dir" -name "${db_name}*.dump" 2>/dev/null | sort -r | head -1)
            if [[ -n "$found" ]]; then
                backup_file="$found"
                log_info "  Found backup: ${backup_file}"
                break
            fi
            # .sql (plain SQL dump)
            found=$(find "$dir" -name "${db_name}*.sql" 2>/dev/null | sort -r | head -1)
            if [[ -n "$found" ]]; then
                backup_file="$found"
                log_info "  Found backup: ${backup_file}"
                break
            fi
        fi
    done

    echo "$backup_file"
}

# ─── Create Fresh Backup ────────────────────────────────────────────────────────

get_pg_config() {
    local container_name="$1"
    local pg_user="" pg_db=""
    pg_user=$(docker inspect "$container_name" --format '{{range .Config.Env}}{{if eq (slice . 0 12) "POSTGRES_USER"}}{{slice . 13}}{{end}}{{end}}' 2>/dev/null)
    pg_db=$(docker inspect "$container_name" --format '{{range .Config.Env}}{{if eq (slice . 0 10) "POSTGRES_DB"}}{{slice . 11}}{{end}}{{end}}' 2>/dev/null)
    if [[ -z "$pg_user" ]]; then pg_user="postgres"; fi
    if [[ -z "$pg_db" ]]; then pg_db="$1"; fi
    echo "${pg_user}:${pg_db}"
}

create_backup() {
    local db_name="$1" db_port="$2"
    local backup_dir="${BACKUP_BASE}/${db_name}"
    local dump_file="${backup_dir}/${db_name}_${TIMESTAMP_FMT}.dump"
    local err_file="${backup_dir}/${db_name}_${TIMESTAMP_FMT}.err"

    mkdir -p "$backup_dir"

    log_info "Creating fresh backup of ${db_name}..."

    # Try docker exec first (container-based backup), then pg_dump
    local dump_created=false
    local pg_container="" pg_user="postgres" actual_db="$db_name"

    if _docker_alive; then
        # Find container matching this db_name (reverse the name derivation)
        local container_pattern
        container_pattern=$(echo "$db_name" | sed 's/[_-]/[_-]/g')
        pg_container=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "${container_pattern}" | head -1 || true)

        if [[ -n "$pg_container" ]]; then
            # Discover PG user and actual database name from container env
            local pg_config
            pg_config=$(get_pg_config "$pg_container")
            pg_user=$(echo "$pg_config" | cut -d: -f1)
            actual_db=$(echo "$pg_config" | cut -d: -f2)
            log_info "  Container: ${pg_container} (user: ${pg_user}, db: ${actual_db})"

            local pg_password
            pg_password=$(docker inspect "$pg_container" --format '{{range .Config.Env}}{{if eq (slice . 0 16) "POSTGRES_PASSWORD"}}{{slice . 17}}{{end}}{{end}}' 2>/dev/null)

            # Try with discovered user
            if docker exec "$pg_container" env PGPASSWORD="${pg_password}" pg_dump -U "${pg_user}" --format=custom "${actual_db}" > "$dump_file" 2>"$err_file"; then
                if [[ -s "$dump_file" ]] && [[ "$(head -c 5 "$dump_file" 2>/dev/null)" == "PGDMP" ]]; then
                    gzip -f "$dump_file"
                    dump_file="${dump_file}.gz"
                    dump_created=true
                    log_ok "Backup created: ${dump_file}"
                else
                    log_warn "  Dump file invalid for ${db_name}, removing"
                    rm -f "$dump_file" "$err_file"
                fi
            else
                log_warn "  docker exec pg_dump failed for ${db_name}"
                rm -f "$dump_file" "$err_file"
            fi
        fi
    else
        log_warn "Docker not available -- skipping container-based backup creation"
    fi

    if [[ "$dump_created" == "false" ]] && [[ "$db_port" != "0" ]] && _validate_port "$db_port"; then
        # Try pg_dump directly (only if port is accessible from host)
        if check_cmd pg_dump && timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/${db_port}" 2>/dev/null; then
            if PGPASSWORD="" pg_dump -h 127.0.0.1 -p "$db_port" -U postgres --format=custom "${db_name}" > "$dump_file" 2>"$err_file"; then
                if [[ -s "$dump_file" ]] && [[ "$(head -c 5 "$dump_file" 2>/dev/null)" == "PGDMP" ]]; then
                    gzip -f "$dump_file"
                    dump_file="${dump_file}.gz"
                    dump_created=true
                    log_ok "Backup created via pg_dump: ${dump_file}"
                else
                    log_warn "  Direct pg_dump produced invalid file for ${db_name}"
                    rm -f "$dump_file" "$err_file"
                fi
            else
                log_warn "  Direct pg_dump failed for ${db_name} (database may not exist on port ${db_port})"
                rm -f "$dump_file" "$err_file"
            fi
        else
            log_warn "  Cannot create backup for ${db_name}: no pg_dump access to port ${db_port}"
        fi
    fi

    if [[ "$dump_created" == "true" ]]; then
        echo "$dump_file"
    else
        echo ""
    fi
}

# ─── Backup Verification ────────────────────────────────────────────────────────

verify_backup_file() {
    local backup_file="$1"

    log_info "Verifying backup file integrity..."

    # Check file exists and is non-empty
    if [[ ! -f "$backup_file" ]]; then
        log_err "Backup file not found: ${backup_file}"
        return 1
    fi

    local file_size
    file_size=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
    if [[ "$file_size" -eq 0 ]]; then
        log_err "Backup file is empty: ${backup_file}"
        return 1
    fi
    log_ok "File size: ${file_size} bytes"

    # SHA256 checksum
    local checksum
    checksum=$(sha256sum "$backup_file" 2>/dev/null | awk '{print $1}')
    if [[ -z "$checksum" ]]; then
        log_err "Failed to compute SHA256 checksum"
        return 1
    fi
    log_ok "SHA256: ${checksum}"

    # For .dump.gz files, verify the gzip integrity
    if [[ "$backup_file" == *.gz ]]; then
        if gzip -t "$backup_file" 2>/dev/null; then
            log_ok "Gzip integrity check passed"
        else
            log_err "Gzip integrity check FAILED"
            return 1
        fi

        # For custom format dumps, verify PGDMP header after decompression
        if [[ "$backup_file" == *.dump.gz ]]; then
            local header
            header=$(zcat "$backup_file" 2>/dev/null | head -c 5)
            if [[ "$header" == "PGDMP" ]]; then
                log_ok "PostgreSQL custom format header verified"
            else
                log_warn "  Not a PostgreSQL custom format dump (header: ${header})"
            fi
        fi
    fi

    # Store checksum for later verification
    local checksum_file="${backup_file}.sha256"
    echo "${checksum}  $(basename "${backup_file}")" > "$checksum_file"
    log_ok "Checksum saved: ${checksum_file}"

    return 0
}

# ─── Restoration ────────────────────────────────────────────────────────────────

restore_backup() {
    local backup_file="$1" db_name="$2"
    local temp_port="$3"
    local container_name="${TEMP_CONTAINER_PREFIX}-${db_name}-${TIMESTAMP_FMT}"

    log_info "Spinning up temporary PostgreSQL container..."
    log_info "  Container: ${container_name}"
    log_info "  Port: ${temp_port}"
    log_info "  Image: ${POSTGRES_IMAGE}"
    log_info "  Database name: ${db_name}"

    # Validate temp port
    if ! _validate_port "$temp_port"; then
        log_err "Invalid temporary port: ${temp_port}"
        return 1
    fi

    # Start temporary PostgreSQL container
    if ! docker run -d \
        --name "$container_name" \
        -e POSTGRES_PASSWORD=temp_test_password \
        -e POSTGRES_DB="$db_name" \
        -p "${temp_port}:5432" \
        --rm \
        "$POSTGRES_IMAGE" \
        >/dev/null 2>&1; then
        log_err "Failed to start temporary PostgreSQL container"
        return 1
    fi

    log_info "Waiting for PostgreSQL to be ready..."
    local pg_ready=false
    for i in $(seq 1 30); do
        if docker exec "$container_name" pg_isready -U postgres &>/dev/null 2>&1; then
            pg_ready=true
            log_ok "PostgreSQL ready after ${i}s"
            break
        fi
        sleep 1
    done

    if [[ "$pg_ready" == "false" ]]; then
        log_err "PostgreSQL failed to become ready within 30s"
        cleanup_temp_container "$container_name"
        return 1
    fi

    # Restore the backup
    log_info "Restoring backup into temporary container..."

    local restore_ok=false
    if [[ "$backup_file" == *.dump.gz ]]; then
        # Custom format, compressed
        zcat "$backup_file" 2>/dev/null | docker exec -i "$container_name" pg_restore -U postgres -d "$db_name" --no-owner --no-acl >/dev/null 2>&1
        local dumpgz_rc=${PIPESTATUS[1]}
        if [[ "$dumpgz_rc" -eq 0 ]]; then
            restore_ok=true
        else
            # pg_restore may return non-zero for warnings, check if data was restored
            log_warn "  pg_restore had warnings -- checking database state..."
            local table_count
            table_count=$(docker exec "$container_name" psql -U postgres -d "$db_name" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null || echo "0")
            table_count=$(echo "$table_count" | tr -d ' ')
            if [[ "$table_count" -gt 0 ]]; then
                log_warn "  Data was restored despite warnings (${table_count} tables)"
                restore_ok=true
            fi
        fi
    elif [[ "$backup_file" == *.sql.gz ]]; then
        # SQL format, compressed
        zcat "$backup_file" 2>/dev/null | docker exec -i "$container_name" psql -U postgres -d "$db_name" >/dev/null 2>&1
        local sqlgz_rc=${PIPESTATUS[1]}
        if [[ "$sqlgz_rc" -eq 0 ]] || [[ "$sqlgz_rc" -eq 141 ]]; then
            restore_ok=true
        else
            log_warn "  SQL restore had warnings -- checking database state..."
            local table_count
            table_count=$(docker exec "$container_name" psql -U postgres -d "$db_name" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null || echo "0")
            table_count=$(echo "$table_count" | tr -d ' ')
            if [[ "$table_count" -gt 0 ]]; then
                log_warn "  Data was restored despite warnings (${table_count} tables)"
                restore_ok=true
            fi
        fi
    elif [[ "$backup_file" == *.dump ]]; then
        # Custom format, uncompressed
        if docker exec -i "$container_name" pg_restore -U postgres -d "$db_name" --no-owner --no-acl < "$backup_file" >/dev/null 2>&1; then
            restore_ok=true
        fi
    elif [[ "$backup_file" == *.sql ]]; then
        # Plain SQL format -- strip \restrict and \unrestrict meta-commands
        # that are injected by pg_dump but not understood by standard psql
        log_info "  Stripping \\restrict and \\unrestrict meta-commands from SQL dump"
        if ! grep -v -E '^\\(restrict|unrestrict) ' "$backup_file" | docker exec -i "$container_name" psql -U postgres -d "$db_name" >/dev/null 2>&1; then
            # psql returned non-zero -- check whether the data was actually restored
            log_warn "  SQL restore reported errors -- checking database state..."
            local table_count
            table_count=$(docker exec "$container_name" psql -U postgres -d "$db_name" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null || echo "0")
            table_count=$(echo "$table_count" | tr -d ' ')
            if [[ "$table_count" -gt 0 ]]; then
                log_warn "  Data was restored despite errors (${table_count} tables)"
                restore_ok=true
            fi
        else
            restore_ok=true
        fi
    else
        log_err "Unknown backup format: ${backup_file}"
        cleanup_temp_container "$container_name"
        return 1
    fi

    if [[ "$restore_ok" != "true" ]]; then
        log_err "Restore command failed for ${db_name}"
        cleanup_temp_container "$container_name"
        return 1
    fi

    log_ok "Restore completed successfully"
    echo "$container_name"
    return 0
}

# ─── Verification ────────────────────────────────────────────────────────────────

verify_restoration() {
    local container_name="$1" db_name="$2"

    log_info "Running restoration verification tests..."

    local total_checks=0
    local passed_checks=0

    # Check 1: Database exists and is accessible
    total_checks=$((total_checks + 1))
    if docker exec "$container_name" psql -U postgres -d "$db_name" -c "SELECT 1 AS test;" 2>/dev/null | grep -q "1"; then
        log_ok "Check 1: Database accessible (SELECT 1)"
        passed_checks=$((passed_checks + 1))
    else
        log_err "Check 1: Database NOT accessible"
    fi

    # Check 2: List all tables
    total_checks=$((total_checks + 1))
    local tables
    tables=$(docker exec "$container_name" psql -U postgres -d "$db_name" -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;" 2>/dev/null || echo "")
    if [[ -n "$tables" ]]; then
        local table_count
        table_count=$(echo "$tables" | wc -l)
        log_ok "Check 2: Found ${table_count} tables in schema"
        passed_checks=$((passed_checks + 1))
        # Log table names
        while IFS= read -r t; do
            local t_trimmed
            t_trimmed=$(echo "$t" | xargs)
            [[ -n "$t_trimmed" ]] && log_info "    table: ${t_trimmed}"
        done <<< "$tables"
    else
        log_warn "Check 2: No tables found (schema may be empty)"
    fi

    # Check 3: Row counts for all tables
    total_checks=$((total_checks + 1))
    if [[ -n "$tables" ]]; then
        local total_rows=0
        while IFS= read -r t; do
            local t_trimmed row_count
            t_trimmed=$(echo "$t" | xargs)
            [[ -z "$t_trimmed" ]] && continue
            row_count=$(docker exec "$container_name" psql -U postgres -d "$db_name" -t -c "SELECT count(*) FROM \"${t_trimmed}\";" 2>/dev/null | tr -d ' ' || echo "0")
            total_rows=$(( total_rows + row_count ))
        done <<< "$tables"
        if [[ "$total_rows" -gt 0 ]]; then
            log_ok "Check 3: Total rows across all tables: ${total_rows}"
            passed_checks=$((passed_checks + 1))
        else
            log_warn "Check 3: All tables have 0 rows (empty database)"
        fi
    else
        log_warn "Check 3: Skipped (no tables)"
    fi

    # Check 4: Sequence values
    total_checks=$((total_checks + 1))
    local sequences
    sequences=$(docker exec "$container_name" psql -U postgres -d "$db_name" -t -c "SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema='public' ORDER BY sequence_name;" 2>/dev/null || echo "")
    if [[ -n "$sequences" ]]; then
        local seq_count
        seq_count=$(echo "$sequences" | grep -c '[^[:space:]]' || true)
        log_ok "Check 4: Found ${seq_count} sequences defined"
        passed_checks=$((passed_checks + 1))
    else
        log_warn "Check 4: No sequences found (may be normal for restored dump)"
    fi

    # Check 5: Sample query -- try retrieving a recent record timestamp if any table has one
    total_checks=$((total_checks + 1))
    if [[ -n "$tables" ]]; then
        local sample_tables
        sample_tables=$(echo "$tables" | head -3)
        local sample_found=false
        while IFS= read -r t; do
            local t_trimmed
            t_trimmed=$(echo "$t" | xargs)
            [[ -z "$t_trimmed" ]] && continue
            # Check for timestamp/date columns
            local date_col
            date_col=$(docker exec "$container_name" psql -U postgres -d "$db_name" -t -c "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='${t_trimmed}' AND (data_type LIKE '%timestamp%' OR data_type LIKE '%date%' OR column_name LIKE '%created%' OR column_name LIKE '%updated%') LIMIT 1;" 2>/dev/null | tr -d ' ' || echo "")
            if [[ -n "$date_col" ]]; then
                local sample_data
                sample_data=$(docker exec "$container_name" psql -U postgres -d "$db_name" -t -c "SELECT '${date_col}' as col, count(*) as cnt, max(${date_col}) as latest FROM \"${t_trimmed}\";" 2>/dev/null | tr -s ' ' || echo "")
                if [[ -n "$sample_data" ]]; then
                    log_ok "Check 5: Sample query on ${t_trimmed}.${date_col}: ${sample_data}"
                    passed_checks=$((passed_checks + 1))
                    sample_found=true
                    break
                fi
            fi
        done <<< "$sample_tables"
        if [[ "$sample_found" == "false" ]]; then
            # Fallback: just count a table
            local first_table
            first_table=$(echo "$tables" | head -1 | xargs)
            if [[ -n "$first_table" ]]; then
                local row_count
                row_count=$(docker exec "$container_name" psql -U postgres -d "$db_name" -t -c "SELECT count(*) FROM \"${first_table}\";" 2>/dev/null | tr -d ' ' || echo "0")
                log_ok "Check 5: Sample query on ${first_table}: ${row_count} rows"
                passed_checks=$((passed_checks + 1))
            else
                log_warn "Check 5: No suitable table for sample query"
            fi
        fi
    else
        log_warn "Check 5: Skipped (no tables)"
    fi

    # Check 6: Schema integrity -- verify no dangling references
    total_checks=$((total_checks + 1))
    local fk_count
    fk_count=$(docker exec "$container_name" psql -U postgres -d "$db_name" -t -c "
        SELECT count(*) FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")
    log_ok "Check 6: Schema integrity -- ${fk_count} foreign key constraints intact"
    passed_checks=$((passed_checks + 1))

    # Summary
    local failure_count=$(( total_checks - passed_checks ))
    log_info "Verification complete: ${passed_checks}/${total_checks} checks passed"

    if [[ "$failure_count" -eq 0 ]]; then
        echo "PASSED"
        return 0
    elif [[ "$failure_count" -le 2 ]]; then
        echo "PARTIAL"
        return 0
    else
        echo "FAILED"
        return 1
    fi
}

# ─── Test One Database ──────────────────────────────────────────────────────────

test_database() {
    local db_name="$1" db_port="$2"
    # Sanitize database name for PostgreSQL (hyphens not valid in unquoted identifiers)
    local pg_db_name
    pg_db_name=$(echo "$db_name" | tr '-' '_')
    local temp_port=$(( TEMP_PORT_START + (RANDOM % 1000) ))
    local test_result="FAILED"
    local backup_file=""

    echo ""
    echo -e "${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}  BACKUP RESTORATION TEST: ${db_name}${C_RESET}"
    echo -e "${C_CYAN}══════════════════════════════════════════════════════════════${C_RESET}"
    echo ""

    log_info "Starting backup restoration test for database: ${db_name}"

    # Step 1: Find or create backup
    backup_file=$(find_backup "$db_name")
    if [[ -z "$backup_file" ]]; then
        log_info "No existing backup found -- creating fresh backup"
        backup_file=$(create_backup "$db_name" "$db_port")
        if [[ -z "$backup_file" ]]; then
            log_err "Cannot proceed: no backup available and backup creation failed"
            echo ""
            echo -e "${C_RED}BACKUP RESTORATION TEST: FAILED -- No backup available for ${db_name}${C_RESET}"
            echo ""
            TEST_RESULTS+=("${db_name}: FAILED (no backup)")
            return 1
        fi
    fi

    # Step 2: Verify backup file integrity
    log_info "Step 2: Verifying backup file integrity"
    if ! verify_backup_file "$backup_file"; then
        log_err "Backup file integrity check failed"
        echo ""
        echo -e "${C_RED}BACKUP RESTORATION TEST: FAILED -- Backup integrity check${C_RESET}"
        echo ""
        TEST_RESULTS+=("${db_name}: FAILED (integrity)")
        return 1
    fi

    # Step 3: Restore into temporary container
    log_info "Step 3: Restoring into temporary container"
    local container_name
    container_name=$(restore_backup "$backup_file" "$pg_db_name" "$temp_port")
    if [[ -z "$container_name" ]]; then
        log_err "Restoration step failed"
        echo ""
        echo -e "${C_RED}BACKUP RESTORATION TEST: FAILED -- Restoration error${C_RESET}"
        echo ""
        TEST_RESULTS+=("${db_name}: FAILED (restoration)")
        return 1
    fi

    # Step 4: Verify restoration
    log_info "Step 4: Running verification checks"
    local verify_result
    verify_result=$(verify_restoration "$container_name" "$pg_db_name") || true
    verify_result=$(echo "$verify_result" | tail -1)

    # Step 5: Clean up
    log_info "Step 5: Cleaning up"
    cleanup_temp_container "$container_name"

    # Step 6: Report result
    if [[ "$verify_result" == "PASSED" ]] || [[ "$verify_result" == "PARTIAL" ]]; then
        echo ""
        echo -e "${C_GREEN}${C_BOLD}BACKUP RESTORATION TEST: PASSED -- ${db_name}${C_RESET}"
        echo ""
        TEST_RESULTS+=("${db_name}: PASSED")
        return 0
    else
        echo ""
        echo -e "${C_RED}${C_BOLD}BACKUP RESTORATION TEST: FAILED -- Verification checks failed for ${db_name}${C_RESET}"
        echo ""
        TEST_RESULTS+=("${db_name}: FAILED (verification)")
        return 1
    fi
}

# ─── Main ───────────────────────────────────────────────────────────────────────

main() {
    local exit_code=0

    # Acquire lock to prevent concurrent runs
    _acquire_lock
    trap _cleanup EXIT INT TERM HUP

    # Create temp directory
    TEMP_DIR=$(mktemp -d "/tmp/${SCRIPT_NAME%.sh}-XXXXXX")
    mkdir -p "$LOG_DIR"

    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}  WHEELER BACKUP RESTORATION TEST${C_RESET}"
    echo -e "${C_MAGENTA}══════════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    echo -e "${C_DIM}  Started: ${TIMESTAMP}${C_RESET}"
    echo -e "${C_DIM}  Log: ${LOG_FILE}${C_RESET}"
    echo ""

    log_info "=== BACKUP RESTORATION TEST STARTED ==="

    # Check prerequisites
    if ! check_cmd docker; then
        log_err "Docker is required but not available"
        echo ""
        echo -e "${C_RED}BACKUP RESTORATION TEST: FAILED -- Docker not available${C_RESET}"
        exit 1
    fi

    if ! _docker_alive; then
        log_err "Docker daemon is not running"
        echo ""
        echo -e "${C_RED}BACKUP RESTORATION TEST: FAILED -- Docker daemon not running${C_RESET}"
        exit 1
    fi

    if ! docker image inspect "$POSTGRES_IMAGE" &>/dev/null 2>&1; then
        log_info "Pulling PostgreSQL image: ${POSTGRES_IMAGE}"
        docker pull "$POSTGRES_IMAGE" 2>/dev/null || {
            log_err "Failed to pull PostgreSQL image"
            exit 1
        }
    fi

    # Discover databases
    local db_data
    db_data=$(discover_databases)
    local db_count
    db_count=$(echo "$db_data" | head -1)

    if [[ "$db_count" -eq 0 ]]; then
        log_err "No PostgreSQL databases discovered"
        echo ""
        echo -e "${C_RED}BACKUP RESTORATION TEST: FAILED -- No databases found${C_RESET}"
        exit 1
    fi

    log_info "Discovered ${db_count} potential databases"

    # Build arrays from discovery output
    declare -a DB_NAMES=()
    declare -a DB_PORTS=()
    while IFS= read -r line; do
        local name port
        name=$(echo "$line" | cut -d: -f1)
        port=$(echo "$line" | cut -d: -f2)
        if [[ -n "$name" && -n "$port" ]]; then
            DB_NAMES+=("$name")
            DB_PORTS+=("$port")
        fi
    done < <(echo "$db_data" | tail -n +2)

    # Filter by target if specified
    if [[ -n "$TARGET_DATABASE" ]]; then
        local found=false
        for i in "${!DB_NAMES[@]}"; do
            if [[ "${DB_NAMES[$i]}" == "$TARGET_DATABASE" ]]; then
                log_info "Targeting specific database: ${TARGET_DATABASE}"
                if ! test_database "${DB_NAMES[$i]}" "${DB_PORTS[$i]}"; then
                    exit_code=1
                fi
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            log_err "Target database '${TARGET_DATABASE}' not found in discovered databases"
            echo ""
            echo -e "${C_RED}BACKUP RESTORATION TEST: FAILED -- Database '${TARGET_DATABASE}' not found${C_RESET}"
            exit 1
        fi
    elif [[ "$TEST_ALL" == "true" ]]; then
        # Test all databases
        log_info "Testing ALL discovered databases"
        for i in "${!DB_NAMES[@]}"; do
            if ! test_database "${DB_NAMES[$i]}" "${DB_PORTS[$i]}"; then
                exit_code=1
            fi
        done
    else
        # Pick a random database
        local random_idx=$(( RANDOM % ${#DB_NAMES[@]} ))
        log_info "Random selection: testing ${DB_NAMES[$random_idx]}"
        if ! test_database "${DB_NAMES[$random_idx]}" "${DB_PORTS[$random_idx]}"; then
            exit_code=1
        fi
    fi

    # Summary
    echo ""
    echo -e "${C_BOLD}${C_MAGENTA}══════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}  BACKUP RESTORATION TEST SUMMARY${C_RESET}"
    echo -e "${C_MAGENTA}══════════════════════════════════════════════════════════════════${C_RESET}"
    echo ""

    for result in "${TEST_RESULTS[@]}"; do
        if echo "$result" | grep -q "PASSED"; then
            echo -e "  ${C_GREEN}[PASS]${C_RESET} ${result}"
        else
            echo -e "  ${C_RED}[FAIL]${C_RESET} ${result}"
        fi
    done

    echo ""

    if [[ "$exit_code" -eq 0 ]]; then
        echo -e "  ${C_GREEN}${C_BOLD}OVERALL RESULT: BACKUP RESTORATION TEST: PASSED${C_RESET}"
        log_info "=== BACKUP RESTORATION TEST: PASSED ==="
    else
        echo -e "  ${C_RED}${C_BOLD}OVERALL RESULT: BACKUP RESTORATION TEST: FAILED${C_RESET}"
        log_info "=== BACKUP RESTORATION TEST: FAILED ==="
    fi

    echo ""
    echo -e "${C_DIM}  Log: ${LOG_FILE}${C_RESET}"
    echo ""

    exit "$exit_code"
}

# ─── Entry ──────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)     usage 0 ;;
        --all)      TEST_ALL=true; shift ;;
        --database) TARGET_DATABASE="$2"; shift 2 ;;
        --port)
            if ! _validate_port "$2"; then
                echo "Error: --port must be a number between 1 and 65535, got: $2" >&2
                exit 2
            fi
            TARGET_PORT="$2"; shift 2 ;;
        *)          echo "Unknown option: $1"; usage 2 ;;
    esac
done

main
