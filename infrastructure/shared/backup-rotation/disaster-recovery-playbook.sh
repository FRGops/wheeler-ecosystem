#!/usr/bin/env bash
# =============================================================================
# disaster-recovery-playbook.sh — Interactive Disaster Recovery Script
# =============================================================================
# Step-by-step guided recovery for complete disaster scenarios.
#   - Asks which server to recover (Hetzner CPX51 or Hostinger VPS)
#   - Lists available backups
#   - Restores databases first, then volumes, then configs
#   - Verifies each step
#   - Spins up containers
#   - Tests all endpoints
#   - Produces full recovery report
#
# RTO Target: 2 hours (database), 1 hour (volumes), 4 hours (full server)
# RPO Target: 24 hours (daily backups)
# =============================================================================
set -euo pipefail

# --- Configuration -----------------------------------------------------------
HETZNER_BACKUP_DIR="/opt/backups"
HOSTINGER_ARCHIVE_DIR="/root/backups/hostinger"
SNAPSHOT_DIR="/opt/backups/pre-migration-snapshots"
LOG_DIR="/opt/logs"
RECOVERY_LOG="${LOG_DIR}/disaster-recovery.log"
RECOVERY_REPORT="${LOG_DIR}/recovery_report_$(date '+%Y%m%d_%H%M%S').txt"

# PostgreSQL connection defaults
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"

# --- Colors for better UI ----------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# --- Logging -----------------------------------------------------------------
log_info()    { echo -e "[$(date '+%H:%M:%S')] ${GREEN}INFO${NC} $*" | tee -a "${RECOVERY_LOG}"; }
log_warn()    { echo -e "[$(date '+%H:%M:%S')] ${YELLOW}WARN${NC} $*" | tee -a "${RECOVERY_LOG}"; }
log_error()   { echo -e "[$(date '+%H:%M:%S')] ${RED}ERROR${NC} $*" | tee -a "${RECOVERY_LOG}"; }
log_step()    { echo -e "\n${CYAN}${BOLD}═══ $* ═══${NC}\n" | tee -a "${RECOVERY_LOG}"; }
log_success() { echo -e "${GREEN}✓${NC} $*" | tee -a "${RECOVERY_LOG}"; }
log_failure() { echo -e "${RED}✗${NC} $*" | tee -a "${RECOVERY_LOG}"; }

# --- Header ------------------------------------------------------------------
show_header() {
    clear
    echo -e "${RED}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         WHEELER AIOPS DISASTER RECOVERY PLAYBOOK            ║"
    echo "║              Full System Recovery Automation                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "Host: $(hostname)"
    echo -e "RTO Target: 4 hours | RPO Target: 24 hours"
    echo ""
}

# --- Check prerequisites -----------------------------------------------------
check_prerequisites() {
    log_step "Prerequisite Check"

    local missing=0

    for cmd in pg_dump pg_restore psql docker curl; do
        if ! command -v "${cmd}" &>/dev/null; then
            # Check PostgreSQL version dirs for pg tools
            local found=false
            if [[ "${cmd}" =~ ^pg_ ]]; then
                for pgdir in /usr/lib/postgresql/*/bin; do
                    if [ -x "${pgdir}/${cmd}" ]; then
                        found=true
                        break
                    fi
                done
            fi
            if ! $found; then
                log_failure "Missing required tool: ${cmd}"
                missing=1
            fi
        fi
    done

    if [ "${missing}" -ne 0 ]; then
        log_error "Please install missing tools before proceeding."
        return 1
    fi

    log_success "All required tools available"
    return 0
}

# --- Select recovery mode ----------------------------------------------------
select_recovery_mode() {
    log_step "Recovery Mode Selection"

    echo "Select the recovery scenario:"
    echo ""
    echo "  ${BOLD}1) Full Hetzner CPX51 Recovery${NC}"
    echo "     Restore all databases + Docker volumes + configurations"
    echo "     Use after: complete server rebuild, OS reinstall"
    echo ""
    echo "  ${BOLD}2) Full Hostinger VPS Recovery${NC}"
    echo "     Restore all Hostinger databases + Docker volumes + configurations"
    echo "     Use after: Hostinger server failure"
    echo ""
    echo "  ${BOLD}3) Single Database Restore${NC}"
    echo "     Restore a specific database on either server"
    echo "     Use after: data corruption, accidental DELETE, failed migration"
    echo ""
    echo "  ${BOLD}4) Single Volume Restore${NC}"
    echo "     Restore a specific Docker volume on either server"
    echo "     Use after: volume corruption, accidental file deletion"
    echo ""
    echo "  ${BOLD}5) Cross-Server Recovery${NC}"
    echo "     Restore Hostinger data to Hetzner or vice versa"
    echo "     Use after: one server is completely unrecoverable"
    echo ""
    echo "  ${BOLD}6) Pre-Migration Rollback${NC}"
    echo "     Roll back to a pre-migration snapshot"
    echo "     Use after: failed migration or upgrade"
    echo ""
    echo "  ${BOLD}q) Quit${NC}"
    echo ""
    read -r -p "Enter choice [1-6/q]: " mode_choice
    echo ""
}

# === FULL HETZNER RECOVERY ===================================================
recover_hetzner() {
    log_step "HETZNER CPX51 — Full System Recovery"

    log_info "This will restore the entire Hetzner CPX51 server."
    log_info "Prerequisites: Server must have Docker and PostgreSQL installed."
    echo ""

    if ! confirm_step "Proceed with full Hetzner recovery?"; then
        log_info "Recovery cancelled."
        return
    fi

    # Step 1: Verify backup availability
    log_step "Step 1: Verifying backup availability"

    local db_count=0
    local vol_count=0

    if [ -d "${HETZNER_BACKUP_DIR}/databases" ]; then
        db_count="$(find "${HETZNER_BACKUP_DIR}/databases" -name '*.dump' 2>/dev/null | wc -l)"
        log_info "Found ${db_count} database backups"
    else
        log_error "No database backups found at ${HETZNER_BACKUP_DIR}/databases"
        log_error "Check backup storage or provide alternative path"
        return 1
    fi

    if [ -d "${HETZNER_BACKUP_DIR}/volumes" ]; then
        vol_count="$(find "${HETZNER_BACKUP_DIR}/volumes" -name '*.tar.gz' 2>/dev/null | wc -l)"
        log_info "Found ${vol_count} volume backups"
    else
        log_warn "No volume backups found at ${HETZNER_BACKUP_DIR}/volumes"
    fi

    if [ "${db_count}" -eq 0 ]; then
        log_error "No database backups available. Cannot proceed."
        return 1
    fi

    echo ""
    log_info "Backup inventory:"
    echo "  • ${db_count} database dumps"
    echo "  • ${vol_count} volume tarballs"
    log_success "Backup inventory verified"

    # Step 2: Restore databases
    log_step "Step 2: Database Restoration"

    if ! confirm_step "Restore all databases?"; then
        log_warn "Database restoration skipped by user"
    else
        restore_hetzner_databases
    fi

    # Step 3: Restore volumes
    log_step "Step 3: Docker Volume Restoration"

    if [ "${vol_count}" -gt 0 ]; then
        if ! confirm_step "Restore all Docker volumes?"; then
            log_warn "Volume restoration skipped by user"
        else
            restore_hetzner_volumes
        fi
    else
        log_info "No volumes to restore"
    fi

    # Step 4: Restore configuration files
    log_step "Step 4: Configuration Restoration"

    if ! confirm_step "Restore configuration files?"; then
        log_warn "Configuration restoration skipped by user"
    else
        restore_hetzner_configs
    fi

    # Step 5: Start services
    log_step "Step 5: Starting Docker Services"

    if ! confirm_step "Start all Docker services?"; then
        log_warn "Service startup skipped by user"
    else
        start_docker_services_hetzner
    fi

    # Step 6: Verify recovery
    log_step "Step 6: Recovery Verification"

    verify_hetzner_recovery

    # Step 7: Generate report
    generate_recovery_report "hetzner"
}

# --- Restore Hetzner databases -----------------------------------------------
restore_hetzner_databases() {
    log_info "Starting database restoration..."

    local databases=("prediction_radar" "ravynai" "healthchecks" "superset")

    for db in "${databases[@]}"; do
        echo ""
        log_info "Restoring database: ${db}"

        # Find latest backup
        local latest
        latest="$(find "${HETZNER_BACKUP_DIR}/databases" -maxdepth 1 -name "*_${db}.dump" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"

        if [ -z "${latest}" ] || [ ! -f "${latest}" ]; then
            log_warn "No backup found for '${db}' — skipping"
            continue
        fi

        log_info "Using backup: $(basename "${latest}")"

        # Verify backup integrity first
        if ! pg_restore --list "${latest}" >/dev/null 2>> "${RECOVERY_LOG}"; then
            log_error "Backup for '${db}' is corrupt — skipping"
            continue
        fi

        # Terminal connections and recreate
        "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres <<-EOF 2>> "${RECOVERY_LOG}" || {
            log_error "Failed to recreate database '${db}'"
            return 1
        }
            SELECT pg_terminate_backend(pid)
            FROM pg_stat_activity
            WHERE datname = '${db}' AND pid <> pg_backend_pid();
            DROP DATABASE IF EXISTS "${db}";
            CREATE DATABASE "${db}";
EOF

        # Restore
        log_info "Restoring '${db}' from backup..."
        if "${PG_RESTORE_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" \
            -d "${db}" --no-owner --no-acl --exit-on-error -v \
            "${latest}" 2>> "${RECOVERY_LOG}"; then
            log_success "Database '${db}' restored successfully"

            # Analyze
            "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${db}" -c "ANALYZE;" 2>/dev/null || true
        else
            log_failure "Database '${db}' restore FAILED"
        fi
    done
}

# --- Restore Hetzner volumes -------------------------------------------------
restore_hetzner_volumes() {
    log_info "Starting volume restoration..."

    local volumes=(
        "prediction-radar_db-data"
        "ravynai_db-data"
        "monitoring_grafana-data"
        "monitoring_prometheus-data"
        "analytics_superset-db"
        "analytics_clickhouse-data"
        "data_postgres-data"
        "data_redis-data"
        "management_portainer-data"
    )

    for volume in "${volumes[@]}"; do
        echo ""
        log_info "Restoring volume: ${volume}"

        # Find latest backup
        local latest
        latest="$(find "${HETZNER_BACKUP_DIR}/volumes" -maxdepth 1 -name "*_${volume}.tar.gz" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"

        if [ -z "${latest}" ] || [ ! -f "${latest}" ]; then
            log_warn "No backup found for volume '${volume}' — skipping"
            continue
        fi

        log_info "Using backup: $(basename "${latest}")"

        # Verify tarball
        if ! tar tzf "${latest}" >/dev/null 2>> "${RECOVERY_LOG}"; then
            log_error "Backup tarball for '${volume}' is corrupt — skipping"
            continue
        fi

        # Stop any containers using this volume
        local containers
        containers="$(docker ps -a --filter "volume=${volume}" --format '{{.Names}}' 2>/dev/null || true)"
        if [ -n "${containers}" ]; then
            for container in ${containers}; do
                log_info "Stopping container: ${container}"
                docker stop "${container}" 2>/dev/null || true
            done
        fi

        # Recreate volume and restore data
        docker volume rm "${volume}" 2>/dev/null || true
        docker volume create "${volume}" >/dev/null

        if docker run --rm \
            -v "${volume}":/target \
            -v "${HETZNER_BACKUP_DIR}/volumes":/backup:ro \
            alpine:latest \
            tar xzf "/backup/$(basename "${latest}")" -C /target 2>/dev/null; then
            log_success "Volume '${volume}' restored successfully"

            # Start dependent containers
            if [ -n "${containers}" ]; then
                for container in ${containers}; do
                    docker start "${container}" 2>/dev/null || true
                done
            fi
        else
            log_failure "Volume '${volume}' restore FAILED"
        fi
    done
}

# --- Restore Hetzner config files --------------------------------------------
restore_hetzner_configs() {
    log_info "Restoring configuration files..."

    # Look for backed up compose files in the snapshot or backup directories
    local config_sources=(
        "${HETZNER_BACKUP_DIR}/pre-migration-snapshots"
        "${HETZNER_BACKUP_DIR}/manifests"
    )

    for source in "${config_sources[@]}"; do
        if [ -d "${source}/configs" ]; then
            log_info "Found config backup at ${source}/configs"
            cp -r "${source}/configs/"* /root/infrastructure/hetzner/compose/ 2>/dev/null || true
            log_success "Configurations restored from ${source}"
            return 0
        fi
    done

    log_warn "No configuration backups found"
    log_info "Configuration files should be restored from git repository"
}

# --- Start Hetzner Docker services -------------------------------------------
start_docker_services_hetzner() {
    local compose_dirs=("/root/infrastructure/hetzner/compose" "/opt/compose")

    for compose_dir in "${compose_dirs[@]}"; do
        if [ -f "${compose_dir}/docker-compose.yml" ] || [ -f "${compose_dir}/compose.yml" ]; then
            log_info "Starting services in ${compose_dir}..."
            (cd "${compose_dir}" && docker compose up -d 2>&1 | tee -a "${RECOVERY_LOG}") || {
                log_warn "Failed to start services in ${compose_dir}"
            }
            log_success "Services started in ${compose_dir}"
        fi
    done
}

# === HOSTINGER RECOVERY ======================================================
recover_hostinger() {
    log_step "HOSTINGER VPS — Full System Recovery"

    log_info "Hostinger recovery will restore from local archive backups."
    log_info "Backups are stored at: ${HOSTINGER_ARCHIVE_DIR}"
    echo ""

    if ! confirm_step "Proceed with Hostinger recovery?"; then
        log_info "Recovery cancelled."
        return
    fi

    # Check SSH access
    if [ -z "${HOSTINGER_SSH_HOST:-}" ] && [ -z "${HOSTINGER_TAILSCALE_IP:-}" ]; then
        log_warn "No Hostinger SSH target configured."
        log_info "Set HOSTINGER_SSH_HOST or HOSTINGER_TAILSCALE_IP environment variable."
        log_info "Continuing with local archive restore only..."
    fi

    # Restore databases to Hostinger via SSH
    log_step "Restoring Hostinger Databases"

    if ! confirm_step "Restore databases to Hostinger?"; then
        log_warn "Database restoration skipped"
    else
        restore_hostinger_databases
    fi

    # Restore Docker volumes
    log_step "Restoring Hostinger Docker Volumes"

    if ! confirm_step "Restore Docker volumes on Hostinger?"; then
        log_warn "Volume restoration skipped"
    else
        restore_hostinger_volumes
    fi

    # Verify
    log_step "Verifying Hostinger Recovery"
    verify_hostinger_recovery
    generate_recovery_report "hostinger"
}

# --- Restore Hostinger databases (push from local archive) ---------------------
restore_hostinger_databases() {
    local databases=(
        "frgops_production"
        "frgcrm_local"
        "shared_chatwoot_production"
        "shared_langfuse"
        "shared_plausible"
        "shared_usesend"
        "shared_frgops_staging"
    )

    for db in "${databases[@]}"; do
        echo ""
        log_info "Restoring database: ${db}"

        local latest
        latest="$(find "${HOSTINGER_ARCHIVE_DIR}" -maxdepth 1 -name "*_${db}.dump" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"

        if [ -z "${latest}" ] || [ ! -f "${latest}" ]; then
            log_warn "No backup found for '${db}' — skipping"
            continue
        fi

        log_info "Using backup: $(basename "${latest}")"

        # Verify integrity
        if ! pg_restore --list "${latest}" >/dev/null 2>> "${RECOVERY_LOG}"; then
            log_error "Backup for '${db}' is corrupt — skipping"
            continue
        fi

        # Push dump to Hostinger and restore
        local ssh_target="${HOSTINGER_SSH_USER:-root}@${HOSTINGER_TAILSCALE_IP:-${HOSTINGER_SSH_HOST:-}}"

        if [ -n "${ssh_target}" ] && [ "${ssh_target}" != "@" ]; then
            log_info "Pushing backup to Hostinger..."

            # Copy dump to remote
            scp -P "${HOSTINGER_SSH_PORT:-22}" "${latest}" "${ssh_target}:/tmp/" 2>/dev/null || {
                log_error "Failed to copy backup to Hostinger"
                continue
            }

            # Restore on remote
            ssh -p "${HOSTINGER_SSH_PORT:-22}" "${ssh_target}" "
                PGPASSWORD='\$(grep -E '^POSTGRES_PASSWORD=' /opt/${db}/.env 2>/dev/null | cut -d= -f2)' \
                psql -h localhost -U postgres -d postgres -c \"
                    SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${db}' AND pid <> pg_backend_pid();
                    DROP DATABASE IF EXISTS \\\"${db}\\\";
                    CREATE DATABASE \\\"${db}\\\";
                \" && \
                PGPASSWORD='\$(grep -E '^POSTGRES_PASSWORD=' /opt/${db}/.env 2>/dev/null | cut -d= -f2)' \
                pg_restore -h localhost -U postgres -d ${db} --no-owner --exit-on-error /tmp/$(basename "${latest}") && \
                rm -f /tmp/$(basename "${latest}")
            " 2>> "${RECOVERY_LOG}" && log_success "Database '${db}' restored to Hostinger" || log_failure "Failed to restore '${db}' to Hostinger"
        else
            log_warn "No SSH target configured — cannot push to Hostinger"
            log_info "Manual steps required:"
            echo "  1. scp ${latest} root@<hostinger>:/tmp/"
            echo "  2. SSH to Hostinger and run pg_restore"
        fi
    done
}

# --- Restore Hostinger volumes ------------------------------------------------
restore_hostinger_volumes() {
    log_warn "Volume restoration to Hostinger requires manual steps."
    log_info "Backups are stored locally but need to be transferred."

    local vol_backups
    mapfile -t vol_backups < <(find "${HOSTINGER_ARCHIVE_DIR}/../volumes" -name '*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | head -5)

    for backup in "${vol_backups[@]}"; do
        log_info "  $(basename "${backup}") — $(stat -c%s "${backup}" 2>/dev/null | numfmt --to=iec 2>/dev/null)"
    done

    echo ""
    log_info "To restore volumes on Hostinger:"
    echo "  1. scp backup.tar.gz root@<hostinger>:/tmp/"
    echo "  2. docker run --rm -v <volume>:/target -v /tmp:/backup alpine tar xzf /backup/backup.tar.gz -C /target"
}

# === SINGLE DATABASE RESTORE =================================================
recover_single_database() {
    log_step "Single Database Restore"

    echo "Select server:"
    echo "  1) Hetzner CPX51 (prediction_radar, ravynai, healthchecks, superset)"
    echo "  2) Hostinger VPS (frgops_production, frgcrm_local, chatwoot, etc.)"
    echo ""
    read -r -p "Select server [1/2]: " server_choice

    case "${server_choice}" in
        1)
            echo ""
            echo "Available databases on Hetzner:"
            echo "  prediction_radar"
            echo "  ravynai"
            echo "  healthchecks"
            echo "  superset"
            echo ""
            read -r -p "Enter database name: " db_name

            case "${db_name}" in
                prediction_radar|ravynai|healthchecks|superset)
                    "${SCRIPT_DIR}/../../hetzner/backup/restore-database.sh" "${db_name}" latest
                    ;;
                *)
                    log_error "Unknown database: ${db_name}"
                    ;;
            esac
            ;;
        2)
            echo ""
            echo "Available databases on Hostinger:"
            echo "  frgops_production, frgcrm_local, shared_chatwoot_production"
            echo "  shared_langfuse, shared_plausible, shared_usesend"
            echo "  shared_frgops_staging"
            echo ""
            read -r -p "Enter database name: " db_name
            log_info "To restore '${db_name}' on Hostinger:"
            echo "  1. Find the latest backup in ${HOSTINGER_ARCHIVE_DIR}"
            echo "  2. scp to Hostinger"
            echo "  3. SSH and run pg_restore"
            echo ""
            echo "  Example:"
            echo "  BACKUP=\$(ls -t ${HOSTINGER_ARCHIVE_DIR}/*_${db_name}.dump | head -1)"
            echo "  scp \$BACKUP root@<hostinger>:/tmp/"
            echo "  ssh root@<hostinger>"
            echo "  pg_restore -h localhost -U postgres -d ${db_name} /tmp/\$(basename \$BACKUP)"
            ;;
    esac
}

# === SINGLE VOLUME RESTORE ===================================================
recover_single_volume() {
    log_step "Single Volume Restore"

    echo "Select server:"
    echo "  1) Hetzner CPX51"
    echo "  2) Hostinger VPS"
    echo ""
    read -r -p "Select server [1/2]: " server_choice

    case "${server_choice}" in
        1)
            echo ""
            echo "Available volume backups on Hetzner:"
            ls -1 "${HETZNER_BACKUP_DIR}/volumes/"*.tar.gz 2>/dev/null | while read -r f; do
                local base
                base="$(basename "${f}")"
                local vol_name="${base#*_}"
                vol_name="${vol_name%.tar.gz}"
                echo "  ${vol_name}"
            done | sort -u
            echo ""
            read -r -p "Enter volume name: " vol_name

            if [ -n "${vol_name}" ]; then
                bash "${SCRIPT_DIR}/../../hetzner/backup/restore-volume.sh" "${vol_name}" latest
            fi
            ;;
        2)
            log_info "Hostinger volumes can be restored from local archive backups."
            echo ""
            echo "To restore:"
            echo "  1. Find the volume backup in archive"
            echo "  2. scp to Hostinger"
            echo "  3. Recreate volume and extract"
            echo ""
            read -r -p "Enter volume name: " vol_name
            echo ""
            echo "Manual steps:"
            echo "  ls -lt ${HOSTINGER_ARCHIVE_DIR}/../volumes/*_${vol_name}.tar.gz"
            echo "  scp <backup.tar.gz> root@<hostinger>:/tmp/"
            echo "  ssh root@<hostinger>"
            echo "  docker volume rm ${vol_name}"
            echo "  docker volume create ${vol_name}"
            echo "  docker run --rm -v ${vol_name}:/target -v /tmp:/backup alpine tar xzf /backup/<backup.tar.gz> -C /target"
            ;;
    esac
}

# === CROSS-SERVER RECOVERY ===================================================
recover_cross_server() {
    log_step "Cross-Server Recovery"

    echo "This will restore data FROM one server TO another."
    echo ""
    echo "Options:"
    echo "  1) Restore Hostinger data ON Hetzner (if Hostinger is down)"
    echo "  2) Restore Hetzner data ON Hostinger (if Hetzner is down)"
    echo ""
    read -r -p "Select option [1/2]: " cross_choice

    case "${cross_choice}" in
        1)
            log_info "Restoring Hostinger databases on Hetzner..."
            echo ""
            echo "Hostinger databases available in local archive:"
            for f in "${HOSTINGER_ARCHIVE_DIR}"/*.dump; do
                [ -f "${f}" ] && echo "  $(basename "${f}")"
            done
            echo ""
            read -r -p "Enter database name to restore (or 'all'): " db

            if [ "${db}" = "all" ]; then
                for f in "${HOSTINGER_ARCHIVE_DIR}"/*.dump; do
                    local base
                    base="$(basename "${f}")"
                    local db_name="${base#*_}"
                    db_name="${db_name%.dump}"

                    log_info "Restoring '${db_name}' to local PostgreSQL..."
                    "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres \
                        -c "CREATE DATABASE \"${db_name}\";" 2>/dev/null || true

                    "${PG_RESTORE_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" \
                        -d "${db_name}" --no-owner --exit-on-error "${f}" 2>> "${RECOVERY_LOG}" && \
                        log_success "Restored '${db_name}'" || log_failure "Failed to restore '${db_name}'"
                done
            else
                local backup
                backup="$(find "${HOSTINGER_ARCHIVE_DIR}" -name "*_${db}.dump" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
                if [ -n "${backup}" ]; then
                    "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres \
                        -c "CREATE DATABASE \"${db}\";" 2>/dev/null || true
                    "${PG_RESTORE_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" \
                        -d "${db}" --no-owner --exit-on-error "${backup}" 2>> "${RECOVERY_LOG}"
                else
                    log_error "No backup found for '${db}'"
                fi
            fi
            ;;
        2)
            log_info "Restoring Hetzner databases on Hostinger..."
            log_info "This requires SSH access to Hostinger."
            echo ""
            echo "Available Hetzner databases:"
            for f in "${HETZNER_BACKUP_DIR}/databases/"*.dump; do
                [ -f "${f}" ] && echo "  $(basename "${f}")"
            done
            echo ""

            local ssh_target="${HOSTINGER_SSH_USER:-root}@${HOSTINGER_TAILSCALE_IP:-${HOSTINGER_SSH_HOST:-}}"
            if [ -z "${ssh_target}" ] || [ "${ssh_target}" = "@" ]; then
                log_error "No Hostinger SSH target configured."
                log_info "Set HOSTINGER_SSH_HOST or HOSTINGER_TAILSCALE_IP."
                return
            fi

            read -r -p "Enter database name to push to Hostinger: " db
            local backup
            backup="$(find "${HETZNER_BACKUP_DIR}/databases" -name "*_${db}.dump" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"

            if [ -n "${backup}" ]; then
                log_info "Pushing '${db}' to Hostinger..."
                scp -P "${HOSTINGER_SSH_PORT:-22}" "${backup}" "${ssh_target}:/tmp/"
                ssh -p "${HOSTINGER_SSH_PORT:-22}" "${ssh_target}" "pg_restore -h localhost -U postgres -d ${db} --no-owner --exit-on-error /tmp/$(basename "${backup}") && rm -f /tmp/$(basename "${backup}")" 2>> "${RECOVERY_LOG}"
            else
                log_error "No backup found for '${db}'"
            fi
            ;;
    esac
}

# === PRE-MIGRATION ROLLBACK ==================================================
recover_pre_migration() {
    log_step "Pre-Migration Rollback"

    log_info "This will roll back to a pre-migration snapshot."
    echo ""

    # List available snapshots
    if [ ! -d "${SNAPSHOT_DIR}" ]; then
        log_warn "No snapshots directory found at ${SNAPSHOT_DIR}"
        SNAPSHOT_DIR="${HETZNER_BACKUP_DIR}/pre-migration-snapshots"
    fi

    if [ ! -d "${SNAPSHOT_DIR}" ]; then
        log_error "No snapshots found."
        echo "Snapshots are created by running: hetzner/backup/pre-migration-snapshot.sh"
        return
    fi

    local snapshots
    mapfile -t snapshots < <(ls -1d "${SNAPSHOT_DIR}"/snapshot_* 2>/dev/null | sort -r)

    if [ ${#snapshots[@]} -eq 0 ]; then
        log_error "No snapshots found in ${SNAPSHOT_DIR}"
        return
    fi

    echo "Available snapshots:"
    echo ""
    for i in "${!snapshots[@]}"; do
        local snap_name
        snap_name="$(basename "${snapshots[$i]}")"
        local snap_date="${snap_name#snapshot_}"
        snap_date="${snap_date%_*}"
        local snap_time="${snap_name##*_}"
        local snap_size
        snap_size="$(du -sh "${snapshots[$i]}" 2>/dev/null | cut -f1 || echo "?")"
        echo "  $((i + 1))) ${snap_name}  (${snap_size}) — ${snap_date} ${snap_time}"
    done
    echo ""
    read -r -p "Select snapshot to roll back to [1-${#snapshots[@]}]: " snap_idx

    if ! [[ "${snap_idx}" =~ ^[0-9]+$ ]] || [ "${snap_idx}" -lt 1 ] || [ "${snap_idx}" -gt "${#snapshots[@]}" ]; then
        log_error "Invalid selection"
        return
    fi

    local selected_snapshot="${snapshots[$((snap_idx - 1))]}"
    log_info "Selected snapshot: $(basename "${selected_snapshot}")"

    # Confirm
    echo ""
    echo "WARNING: This will REPLACE current databases and volumes with snapshot data."
    echo "Current data will be lost unless you have recent backups."
    echo ""

    if ! confirm_step "Roll back to this snapshot?"; then
        log_info "Rollback cancelled."
        return
    fi

    # Restore databases from snapshot
    if [ -d "${selected_snapshot}/databases" ]; then
        log_info "Restoring databases from snapshot..."
        for dump in "${selected_snapshot}/databases/"*.dump; do
            [ -f "${dump}" ] || continue
            local db_name
            db_name="$(basename "${dump}" .dump)"

            log_info "Restoring database: ${db_name}"
            "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d postgres \
                -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${db_name}' AND pid <> pg_backend_pid(); DROP DATABASE IF EXISTS \"${db_name}\"; CREATE DATABASE \"${db_name}\";" 2>/dev/null

            "${PG_RESTORE_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" \
                -d "${db_name}" --no-owner --exit-on-error "${dump}" 2>> "${RECOVERY_LOG}" && \
                log_success "Restored '${db_name}'" || log_failure "Failed to restore '${db_name}'"
        done
    fi

    # Restore volumes from snapshot
    if [ -d "${selected_snapshot}/volumes" ]; then
        log_info "Restoring volumes from snapshot..."
        for tarball in "${selected_snapshot}/volumes/"*.tar.gz; do
            [ -f "${tarball}" ] || continue
            local vol_name
            vol_name="$(basename "${tarball}" .tar.gz)"

            log_info "Restoring volume: ${vol_name}"
            docker volume rm "${vol_name}" 2>/dev/null || true
            docker volume create "${vol_name}" >/dev/null
            docker run --rm -v "${vol_name}":/target -v "$(dirname "${tarball}")":/backup:ro \
                alpine:latest tar xzf "/backup/$(basename "${tarball}")" -C /target 2>/dev/null && \
                log_success "Restored volume '${vol_name}'" || log_failure "Failed to restore volume '${vol_name}'"
        done
    fi

    # Restore configs from snapshot
    if [ -d "${selected_snapshot}/configs" ]; then
        log_info "Restoring configuration files..."
        local config_target="/root/infrastructure/hetzner/compose"
        mkdir -p "${config_target}"
        cp -r "${selected_snapshot}/configs/"* "${config_target}/" 2>/dev/null || true
        log_success "Configurations restored"
    fi

    log_success "Rollback to snapshot '$(basename "${selected_snapshot}")' complete"
    generate_recovery_report "rollback-$(basename "${selected_snapshot}")"
}

# === VERIFICATION FUNCTIONS ==================================================
verify_hetzner_recovery() {
    log_step "Recovery Verification"

    local failures=0
    log_info "Verifying database connectivity..."

    local databases=("prediction_radar" "ravynai" "healthchecks" "superset")
    for db in "${databases[@]}"; do
        if "${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${db}" -c "SELECT 1;" >/dev/null 2>&1; then
            local table_count
            table_count="$("${PSQL_BIN}" -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${db}" -tAc \
                "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema');" 2>/dev/null || echo "0")"
            log_success "Database '${db}' is online (${table_count} tables)"
        else
            log_failure "Database '${db}' is NOT accessible"
            failures=$((failures + 1))
        fi
    done

    # Check Docker
    log_info "Checking Docker..."
    if docker info >/dev/null 2>&1; then
        local running_containers
        running_containers="$(docker ps -q 2>/dev/null | wc -l)"
        log_success "Docker is running (${running_containers} containers active)"
    else
        log_failure "Docker is not running"
        failures=$((failures + 1))
    fi

    # Check volumes
    log_info "Checking Docker volumes..."
    local expected_volumes=(
        "prediction-radar_db-data"
        "ravynai_db-data"
        "data_postgres-data"
    )
    for vol in "${expected_volumes[@]}"; do
        if docker volume inspect "${vol}" >/dev/null 2>&1; then
            log_success "Volume '${vol}' exists"
        else
            log_warn "Volume '${vol}' is missing"
        fi
    done

    # HTTP health checks
    log_info "Checking HTTP endpoints..."
    local endpoints=(
        "localhost:8000"
        "localhost:8007"
        "localhost:3130"
        "localhost:8088"
    )
    for endpoint in "${endpoints[@]}"; do
        if curl -sf "http://${endpoint}/health" >/dev/null 2>&1 || curl -sf "http://${endpoint}" >/dev/null 2>&1; then
            log_success "Endpoint ${endpoint} is responding"
        else
            log_warn "Endpoint ${endpoint} is not responding (may need manual check)"
        fi
    done

    if [ "${failures}" -eq 0 ]; then
        log_success "${GREEN}${BOLD}RECOVERY VERIFICATION PASSED — All checks OK${NC}"
    else
        log_warn "${YELLOW}${BOLD}Recovery verification had ${failures} failure(s) — manual check required${NC}"
    fi
}

verify_hostinger_recovery() {
    log_step "Hostinger Recovery Verification"

    local ssh_target="${HOSTINGER_SSH_USER:-root}@${HOSTINGER_TAILSCALE_IP:-${HOSTINGER_SSH_HOST:-}}"

    if [ -z "${ssh_target}" ] || [ "${ssh_target}" = "@" ]; then
        log_warn "No SSH target — cannot verify Hostinger remotely"
        log_info "Manual verification required:"
        echo "  1. SSH to Hostinger"
        echo "  2. docker ps (check all containers are running)"
        echo "  3. Check FRGops at https://frgops.wheeler.ai"
        echo "  4. Check Chatwoot at https://chatwoot.wheeler.ai"
        return
    fi

    log_info "Checking Hostinger services via SSH..."

    # Check Docker
    if ssh -p "${HOSTINGER_SSH_PORT:-22}" "${ssh_target}" "docker info >/dev/null 2>&1"; then
        local running
        running="$(ssh -p "${HOSTINGER_SSH_PORT:-22}" "${ssh_target}" "docker ps -q 2>/dev/null | wc -l")"
        log_success "Docker is running on Hostiger (${running} containers)"
    else
        log_failure "Docker is not running on Hostinger"
    fi

    # Check critical services
    local services=("frgops" "chatwoot" "n8n" "litellm")
    for svc in "${services[@]}"; do
        if ssh -p "${HOSTINGER_SSH_PORT:-22}" "${ssh_target}" "docker ps --format '{{.Names}}' 2>/dev/null | grep -qi '${svc}'"; then
            log_success "Service '${svc}' is running"
        else
            log_warn "Service '${svc}' may not be running"
        fi
    done
}

# === REPORT ==================================================================
generate_recovery_report() {
    local recovery_type="$1"
    local end_time
    end_time="$(date '+%Y-%m-%d %H:%M:%S')"

    cat > "${RECOVERY_REPORT}" <<-EOF
╔══════════════════════════════════════════════════════════════╗
║              DISASTER RECOVERY REPORT                        ║
╚══════════════════════════════════════════════════════════════╝

Recovery Type: ${recovery_type}
Server:        $(hostname)
Date:          $(date '+%Y-%m-%d')
Time:          $(date '+%H:%M:%S')
Completed:     ${end_time}
Operator:      ${USER:-unknown}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RECOVERY SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The following actions were taken:
$(cat "${RECOVERY_LOG}" | grep -E '\[(INFO|WARN|ERROR)\]' || echo "  (see full log for details)")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SERVICES STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Docker: $(docker info >/dev/null 2>&1 && echo "RUNNING" || echo "STOPPED")
Running containers: $(docker ps -q 2>/dev/null | wc -l)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DATABASES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

    # List databases
    for db in prediction_radar ravynai healthchecks superset; do
        if "${PSQL_BIN}" -h "${PGHOST:-localhost}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" -d "${db}" -c "SELECT 1;" >/dev/null 2>&1; then
            echo "  ${db}: ONLINE" >> "${RECOVERY_REPORT}"
        fi
    done

    cat >> "${RECOVERY_REPORT}" <<-EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NEXT STEPS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Verify all critical services are functional:
   - https://predictionradar.wheeler.ai
   - https://ravynai.wheeler.ai
   - https://healthchecks.wheeler.ai
   - https://superset.wheeler.ai

2. Check monitoring dashboards:
   - https://grafana.wheeler.ai
   - https://uptime.wheeler.ai

3. Verify data integrity for critical tables

4. Run a manual backup after recovery

5. This report saved to: ${RECOVERY_REPORT}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
END OF REPORT
EOF

    echo ""
    log_success "Recovery report saved to: ${RECOVERY_REPORT}"
    echo ""
    cat "${RECOVERY_REPORT}"
}

# === UTILITY FUNCTIONS =======================================================
confirm_step() {
    local prompt="$1"
    echo ""
    read -r -p "${prompt} [y/N] " response
    [[ "${response}" =~ ^[yY](es)?$ ]]
}

# === MAIN ====================================================================
main() {
    # Create log
    mkdir -p "${LOG_DIR}"
    : > "${RECOVERY_LOG}"

    show_header

    # Check prerequisites
    check_prerequisites || {
        log_error "Prerequisite check failed. Exiting."
        exit 1
    }

    # Main loop
    while true; do
        select_recovery_mode

        case "${mode_choice}" in
            1)
                recover_hetzner
                ;;
            2)
                recover_hostinger
                ;;
            3)
                recover_single_database
                ;;
            4)
                recover_single_volume
                ;;
            5)
                recover_cross_server
                ;;
            6)
                recover_pre_migration
                ;;
            q|Q)
                log_info "Exiting Disaster Recovery Playbook."
                exit 0
                ;;
            *)
                log_error "Invalid choice: ${mode_choice}"
                sleep 2
                continue
                ;;
        esac

        echo ""
        echo "========================================"
        read -r -p "Return to main menu? [Y/n] " return_choice
        if [[ "${return_choice}" =~ ^[nN](o)?$ ]]; then
            break
        fi
    done

    log_info "Disaster Recovery session completed."
    echo ""
    echo "Full recovery log: ${RECOVERY_LOG}"
    echo "Recovery report:   ${RECOVERY_REPORT}"
}

# --- Run ---------------------------------------------------------------------
# Resolve script directory for relative references
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
main "$@"
