#!/usr/bin/env bash
# =============================================================================
# pre-migration-snapshot.sh — Full Pre-Migration Snapshot (Hetzner CPX51)
# =============================================================================
# Takes a FULL snapshot of EVERYTHING before any migration step:
#   - All databases
#   - All Docker compose files and .env files
#   - Docker inspect output for every container
#   - System info (packages, ufw rules, crontabs, disk, network)
# Creates a dated snapshot directory with complete manifest.
# Enables FULL ROLLBACK if migration goes wrong.
# =============================================================================
set -euo pipefail

# --- Source config -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/backup-config.sh" ]; then
    source "${SCRIPT_DIR}/backup-config.sh"
else
    echo "FATAL: backup-config.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

# --- Snapshot root (outside normal backup rotation for safety) ---------------
SNAPSHOT_ROOT="${BACKUP_ROOT}/pre-migration-snapshots"
SNAPSHOT_NAME="snapshot_$(date '+%Y%m%d_%H%M%S')"
SNAPSHOT_DIR="${SNAPSHOT_ROOT}/${SNAPSHOT_NAME}"
SNAPSHOT_LOG="${SNAPSHOT_DIR}/snapshot.log"

# --- Logging -----------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "${message}" | tee -a "${SNAPSHOT_LOG}"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# --- Ensure directories exist ------------------------------------------------
setup() {
    mkdir -p "${SNAPSHOT_DIR}"/{databases,volumes,configs,docker,system}
    log_info "Snapshot directory: ${SNAPSHOT_DIR}"
}

# === 1. DATABASES ===
snapshot_databases() {
    log_info "--- Database Snapshots ---"

    for db in "${DATABASES[@]}"; do
        log_info "Snapshotting database: ${db}"

        # Check if database exists
        if ! "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres -tAc \
            "SELECT 1 FROM pg_database WHERE datname='${db}';" 2>/dev/null | grep -q 1; then
            log_warn "Database '${db}' does not exist — skipping"
            continue
        fi

        local db_dump="${SNAPSHOT_DIR}/databases/${db}.dump"
        "${PG_DUMP_BIN}" \
            -h "${PGHOST}" \
            -p "${PGPORT}" \
            -U "${PGUSER}" \
            -d "${db}" \
            -F c \
            -v \
            --no-owner \
            --no-acl \
            -f "${db_dump}" 2>> "${SNAPSHOT_LOG}"

        # Get database metadata
        "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${db}" <<-EOF > "${SNAPSHOT_DIR}/databases/${db}_metadata.txt" 2>/dev/null || true
            SELECT current_database() AS database_name,
                   pg_size_pretty(pg_database_size(current_database())) AS size,
                   (SELECT count(*) FROM pg_stat_user_tables) AS user_tables,
                   (SELECT count(*) FROM pg_stat_user_indexes) AS user_indexes;
EOF
        log_info "  → ${db}.dump"
    done

    # Snapshot global objects (roles, tablespaces)
    "${PG_DUMP_BIN}" \
        -h "${PGHOST}" \
        -p "${PGPORT}" \
        -U "${PGUSER}" \
        --globals-only \
        -f "${SNAPSHOT_DIR}/databases/global_roles.dump" 2>> "${SNAPSHOT_LOG}" || true
    log_info "  → Global roles snapshotted"
}

# === 2. DOCKER CONFIGURATION ===
snapshot_docker_configs() {
    log_info "--- Docker Configuration Snapshots ---"

    # Docker inspect for ALL containers
    log_info "Snapshotting container configurations..."
    local containers
    containers="$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)"
    for container in ${containers}; do
        docker inspect "${container}" > "${SNAPSHOT_DIR}/docker/${container}_inspect.json" 2>/dev/null || true
        docker logs --tail 100 "${container}" > "${SNAPSHOT_DIR}/docker/${container}_logtail.txt" 2>/dev/null || true
    done

    # Docker compose files
    log_info "Snapshotting compose files..."
    for compose_dir in "${COMPOSE_DIRS_HETZNER[@]}"; do
        if [ -d "${compose_dir}" ]; then
            local target_dir="${SNAPSHOT_DIR}/configs/compose-$(basename "${compose_dir}")"
            mkdir -p "${target_dir}"
            cp -r "${compose_dir}/" "${target_dir}/" 2>/dev/null || true
            log_info "  → Copied ${compose_dir}"
        fi
    done

    # .env files (search common locations)
    log_info "Snapshotting .env files..."
    find /opt /root -maxdepth 4 -name '.env' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | while read -r envfile; do
        local target="${SNAPSHOT_DIR}/configs/$(echo "${envfile}" | tr '/' '_')"
        cp "${envfile}" "${target}" 2>/dev/null || true
    done

    # Docker Compose files (broader search)
    find /opt /root -maxdepth 4 \( -name 'docker-compose.yml' -o -name 'compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yaml' \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | while read -r composefile; do
        local target="${SNAPSHOT_DIR}/configs/$(echo "${composefile}" | tr '/' '_')"
        cp "${composefile}" "${target}" 2>/dev/null || true
    done

    # Docker network info
    docker network ls > "${SNAPSHOT_DIR}/docker/networks.txt" 2>/dev/null || true
    docker volume ls > "${SNAPSHOT_DIR}/docker/volumes.txt" 2>/dev/null || true
    docker images --digests > "${SNAPSHOT_DIR}/docker/images.txt" 2>/dev/null || true

    log_info "  → Docker configuration snapshotted"
}

# === 3. DOCKER VOLUMES (tarball) ===
snapshot_volumes() {
    log_info "--- Volume Snapshots ---"

    local all_volumes
    all_volumes="$(docker volume ls -q 2>/dev/null || true)"

    for volume in ${all_volumes}; do
        log_info "Snapshotting volume: ${volume}"

        if docker run --rm \
            -v "${volume}":/source:ro \
            -v "${SNAPSHOT_DIR}/volumes":/backup \
            alpine:latest \
            tar czf "/backup/${volume}.tar.gz" \
                --ignore-failed-read \
                -C /source \
                . 2>/dev/null; then
            log_info "  → ${volume}.tar.gz"
        else
            log_warn "  → Failed to snapshot volume: ${volume}"
        fi
    done
}

# === 4. SYSTEM INFORMATION ===
snapshot_system() {
    log_info "--- System Information ---"

    # Hostname and kernel
    {
        echo "Hostname: $(hostname)"
        echo "Date: $(date)"
        echo "Kernel: $(uname -a)"
        echo "Uptime: $(uptime)"
    } > "${SNAPSHOT_DIR}/system/system_info.txt"

    # Package list
    dpkg -l > "${SNAPSHOT_DIR}/system/packages.txt" 2>/dev/null || rpm -qa > "${SNAPSHOT_DIR}/system/packages.txt" 2>/dev/null || true

    # Disk usage
    df -h > "${SNAPSHOT_DIR}/system/disk_usage.txt" 2>/dev/null || true
    lsblk > "${SNAPSHOT_DIR}/system/block_devices.txt" 2>/dev/null || true

    # Network configuration
    ip addr > "${SNAPSHOT_DIR}/system/network.txt" 2>/dev/null || ifconfig > "${SNAPSHOT_DIR}/system/network.txt" 2>/dev/null || true
    ip route > "${SNAPSHOT_DIR}/system/routing.txt" 2>/dev/null || route -n > "${SNAPSHOT_DIR}/system/routing.txt" 2>/dev/null || true
    ss -tulpn > "${SNAPSHOT_DIR}/system/listening_ports.txt" 2>/dev/null || netstat -tulpn > "${SNAPSHOT_DIR}/system/listening_ports.txt" 2>/dev/null || true

    # Firewall rules
    ufw status verbose > "${SNAPSHOT_DIR}/system/ufw_rules.txt" 2>/dev/null || iptables-save > "${SNAPSHOT_DIR}/system/iptables_rules.txt" 2>/dev/null || true

    # Crontabs
    crontab -l > "${SNAPSHOT_DIR}/system/crontab_root.txt" 2>/dev/null || true
    ls -la /etc/cron* > "${SNAPSHOT_DIR}/system/cron_dirs.txt" 2>/dev/null || true
    cat /etc/crontab > "${SNAPSHOT_DIR}/system/crontab_system.txt" 2>/dev/null || true
    for f in /etc/cron.d/*; do
        [ -f "$f" ] && cp "$f" "${SNAPSHOT_DIR}/system/cron.d-$(basename "$f")" 2>/dev/null || true
    done

    # System services
    systemctl list-units --type=service --state=running > "${SNAPSHOT_DIR}/system/services.txt" 2>/dev/null || true

    # Memory
    free -h > "${SNAPSHOT_DIR}/system/memory.txt" 2>/dev/null || true

    # Tailscale status
    tailscale status > "${SNAPSHOT_DIR}/system/tailscale_status.txt" 2>/dev/null || true

    # Docker system info
    docker info > "${SNAPSHOT_DIR}/system/docker_info.txt" 2>/dev/null || true
    docker system df > "${SNAPSHOT_DIR}/system/docker_disk.txt" 2>/dev/null || true

    log_info "  → System information snapshotted"
}

# === 5. CREATE MANIFEST ===
create_manifest() {
    local manifest="${SNAPSHOT_DIR}/manifest.json"

    log_info "Creating snapshot manifest..."

    # Calculate sizes
    local total_size
    total_size="$(du -sh "${SNAPSHOT_DIR}" 2>/dev/null | cut -f1 || echo "unknown")"

    cat > "${manifest}" <<-EOF
{
  "snapshot_name": "${SNAPSHOT_NAME}",
  "server": "hetzner-cpx51",
  "hostname": "$(hostname)",
  "created_at": "$(date '+%Y-%m-%dT%H:%M:%S%z')",
  "created_by": "${USER:-unknown}",
  "total_size": "${total_size}",
  "contents": {
    "databases": $(ls "${SNAPSHOT_DIR}/databases/" 2>/dev/null | wc -l),
    "volumes": $(ls "${SNAPSHOT_DIR}/volumes/" 2>/dev/null | wc -l),
    "docker_configs": $(ls "${SNAPSHOT_DIR}/docker/" 2>/dev/null | wc -l),
    "config_files": $(ls "${SNAPSHOT_DIR}/configs/" 2>/dev/null | wc -l),
    "system_files": $(ls "${SNAPSHOT_DIR}/system/" 2>/dev/null | wc -l)
  },
  "purpose": "pre-migration snapshot — full system state before migration"
}
EOF

    log_info "Manifest: ${manifest}"

    # List all files
    find "${SNAPSHOT_DIR}" -type f -not -name "manifest.json" | sort > "${SNAPSHOT_DIR}/file_listing.txt"
    log_info "File listing: ${SNAPSHOT_DIR}/file_listing.txt"
}

# === MAIN ===
main() {
    local start_time
    start_time="$(date +%s)"

    echo ""
    echo "=============================================="
    echo "  PRE-MIGRATION FULL SYSTEM SNAPSHOT"
    echo "=============================================="
    echo ""
    echo "This will create a complete snapshot of:"
    echo "  - All PostgreSQL databases (${DATABASES[*]})"
    echo "  - All Docker volumes"
    echo "  - All Docker compose and .env files"
    echo "  - Full Docker configuration (inspect, logs, networks)"
    echo "  - System information (packages, firewall, crontabs)"
    echo ""
    echo "Snapshot will be saved to: ${SNAPSHOT_ROOT}/${SNAPSHOT_NAME}"
    echo ""

    # Safety check: confirm before proceeding
    echo "WARNING: This is a PRE-MIGRATION snapshot."
    echo "Run this BEFORE making any migration changes."
    echo ""
    read -r -p "Create pre-migration snapshot? [y/N] " response
    if [[ ! "${response}" =~ ^[yY](es)?$ ]]; then
        echo "Snapshot cancelled."
        exit 0
    fi

    # Check for required tools
    local missing=0
    for cmd in pg_dump pg_restore psql docker; do
        if ! command -v "${cmd}" &>/dev/null; then
            # Check PostgreSQL version dirs
            local found=false
            for pgdir in /usr/lib/postgresql/*/bin; do
                if [ -x "${pgdir}/${cmd}" ]; then
                    found=true
                    break
                fi
            done
            if ! $found; then
                echo "Missing tool: ${cmd}"
                missing=1
            fi
        fi
    done

    if [ "${missing}" -ne 0 ]; then
        echo "ERROR: Missing required tools. Aborting."
        exit 1
    fi

    # Execute snapshot
    setup
    echo "" | tee -a "${SNAPSHOT_LOG}"

    snapshot_databases
    echo "" | tee -a "${SNAPSHOT_LOG}"

    snapshot_docker_configs
    echo "" | tee -a "${SNAPSHOT_LOG}"

    snapshot_volumes
    echo "" | tee -a "${SNAPSHOT_LOG}"

    snapshot_system
    echo "" | tee -a "${SNAPSHOT_LOG}"

    create_manifest

    # Summary
    local end_time
    end_time="$(date +%s)"
    local duration=$((end_time - start_time))
    local duration_hr
    duration_hr="$(date -u -d "@${duration}" '+%H:%M:%S' 2>/dev/null || echo "${duration}s")"
    local total_size
    total_size="$(du -sh "${SNAPSHOT_DIR}" 2>/dev/null | cut -f1 || echo "unknown")"

    echo ""
    echo "=============================================="
    echo "  SNAPSHOT COMPLETE"
    echo "=============================================="
    echo "  Duration: ${duration_hr}"
    echo "  Location: ${SNAPSHOT_DIR}"
    echo "  Total size: ${total_size}"
    echo "=============================================="
    echo ""
    echo "To roll back to this state, restore from:"
    echo "  Databases: ${SNAPSHOT_DIR}/databases/"
    echo "  Volumes:   ${SNAPSHOT_DIR}/volumes/"
    echo "  Configs:   ${SNAPSHOT_DIR}/configs/"
    echo ""
}

# --- Run ---------------------------------------------------------------------
main "$@"
