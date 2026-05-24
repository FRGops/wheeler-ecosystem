#!/bin/bash
# =============================================================================
# safe-apply-postgres-tuning.sh
# Safe PostgreSQL configuration deployment with automatic backup and rollback.
#
# Usage:
#   ./safe-apply-postgres-tuning.sh <instance-name>
#
# Where <instance-name> is one of:
#   wheeler-postgres          (COREDB, 5.78.210.123)
#   frgops-standby            (AIOPS, 5.78.140.118)
#   prediction-radar-app-db   (AIOPS, 5.78.140.118)
#   aiops-ravynai-postgres    (AIOPS, 5.78.140.118)
#   all-coredb                (apply wheeler-postgres only)
#   all-aiops                 (apply all 3 AIOPS instances)
#
# Procedures:
#   1. Backup current postgresql.conf
#   2. Copy optimized config
#   3. Restart container
#   4. Verify connectivity + pg_stat_statements
#   5. Report success or provide rollback command
#
# Generated: 2026-05-23
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/pg_config_backups/${TIMESTAMP}"
LOG_FILE="/root/pg_config_backups/apply_${TIMESTAMP}.log"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[INFO]${NC}  $(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE"; }

# Instance configurations
# Format: name|server_ip|container_name|pg_user|pg_db|config_file|postgresql_conf_path_in_container
declare -A INSTANCES

INSTANCES["wheeler-postgres"]="5.78.210.123|wheeler-postgres|wheeler|wheeler_core|optimized-wheeler-postgres.conf|/var/lib/postgresql/data/postgresql.conf"
INSTANCES["frgops-standby"]="5.78.140.118|frgops-standby|frgops|frgops|optimized-frgops-standby.conf|/var/lib/postgresql/data/postgresql.conf"
INSTANCES["prediction-radar-app-db"]="5.78.140.118|prediction-radar-app-db|prediction_radar|prediction_radar|optimized-prediction-radar-app-db.conf|/var/lib/postgresql/data/postgresql.conf"
INSTANCES["aiops-ravynai-postgres"]="5.78.140.118|aiops-ravynai-postgres|ravynai|ravynai|optimized-aiops-ravynai-postgres.conf|/var/lib/postgresql/data/postgresql.conf"

# =============================================================================
# Utility Functions
# =============================================================================

check_instance_exists() {
    local name="$1"
    if [[ -z "${INSTANCES[$name]:-}" ]]; then
        error "Unknown instance: $name"
        echo ""
        echo "Valid instances:"
        for key in "${!INSTANCES[@]}"; do
            echo "  - $key"
        done
        echo "  - all-coredb      (apply wheeler-postgres)"
        echo "  - all-aiops       (apply frgops-standby, prediction-radar-app-db, aiops-ravynai-postgres)"
        exit 1
    fi
}

parse_instance_config() {
    local name="$1"
    local config="${INSTANCES[$name]}"
    IFS='|' read -r SERVER_IP CONTAINER PGUSER PGDB CONFIG_FILE PG_CONF_PATH <<< "$config"
}

verify_ssh() {
    local server="$1"
    log "Verifying SSH connectivity to $server..."
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${server}" "echo OK" > /dev/null 2>&1; then
        error "Cannot SSH to $server. Check connectivity and SSH keys."
        exit 1
    fi
    log "SSH to $server: OK"
}

verify_container() {
    local server="$1"
    local container="$2"
    log "Verifying container $container is running..."
    local status
    status=$(ssh -o ConnectTimeout=5 "root@${server}" "docker inspect -f '{{.State.Status}}' ${container}" 2>&1)
    if [[ "$status" != "running" ]]; then
        error "Container $container is not running (status: $status)"
        exit 1
    fi
    log "Container $container: running"
}

verify_psql() {
    local server="$1"
    local container="$2"
    local pguser="$3"
    local pgdb="$4"
    log "Verifying psql connectivity to $container ($pguser@$pgdb)..."
    if ! ssh -o ConnectTimeout=5 "root@${server}" "docker exec ${container} psql -U ${pguser} -d ${pgdb} -c 'SELECT 1;'" > /dev/null 2>&1; then
        error "Cannot connect to PostgreSQL in $container"
        exit 1
    fi
    log "psql connectivity: OK"
}

backup_config() {
    local server="$1"
    local container="$2"
    local pg_conf_path="$3"
    local instance_name="$4"

    mkdir -p "$BACKUP_DIR"
    log "Backing up postgresql.conf from $container..."

    ssh -o ConnectTimeout=5 "root@${server}" \
        "docker cp ${container}:${pg_conf_path} /tmp/postgresql.conf.${instance_name}.bak" 2>&1 | tee -a "$LOG_FILE"

    scp -o ConnectTimeout=5 "root@${server}:/tmp/postgresql.conf.${instance_name}.bak" \
        "${BACKUP_DIR}/${instance_name}_postgresql.conf.bak" 2>&1 | tee -a "$LOG_FILE"

    # Also save a copy on the server itself
    ssh -o ConnectTimeout=5 "root@${server}" \
        "mkdir -p /root/pg_config_backups/${TIMESTAMP} && cp /tmp/postgresql.conf.${instance_name}.bak /root/pg_config_backups/${TIMESTAMP}/" 2>&1 | tee -a "$LOG_FILE"

    log "Backup saved to: ${BACKUP_DIR}/${instance_name}_postgresql.conf.bak"
}

apply_config() {
    local server="$1"
    local container="$2"
    local pg_conf_path="$3"
    local config_file="$4"

    local local_conf="${SCRIPT_DIR}/${config_file}"

    if [[ ! -f "$local_conf" ]]; then
        error "Config file not found: $local_conf"
        exit 1
    fi

    log "Applying $config_file to $container..."
    log "Local config: $local_conf"

    # Copy config to server
    scp -o ConnectTimeout=5 "$local_conf" "root@${server}:/tmp/${config_file}" 2>&1 | tee -a "$LOG_FILE"

    # Copy into container
    ssh -o ConnectTimeout=5 "root@${server}" \
        "docker cp /tmp/${config_file} ${container}:${pg_conf_path}" 2>&1 | tee -a "$LOG_FILE"

    log "Config file copied into container at $pg_conf_path"
}

restart_container() {
    local server="$1"
    local container="$2"

    log "Restarting container $container..."
    ssh -o ConnectTimeout=5 "root@${server}" "docker restart ${container}" 2>&1 | tee -a "$LOG_FILE"

    log "Waiting for PostgreSQL to be ready..."
    sleep 5

    # Wait up to 30 seconds for PostgreSQL to accept connections
    local waited=0
    while [[ $waited -lt 30 ]]; do
        if ssh -o ConnectTimeout=5 "root@${server}" \
            "docker exec ${container} pg_isready -q" 2>/dev/null; then
            log "PostgreSQL is ready after ${waited}s"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    error "PostgreSQL did not become ready within 30 seconds!"
    return 1
}

verify_after_restart() {
    local server="$1"
    local container="$2"
    local pguser="$3"
    local pgdb="$4"

    log "Running post-restart verification..."

    # Test basic connectivity
    if ! ssh -o ConnectTimeout=5 "root@${server}" \
        "docker exec ${container} psql -U ${pguser} -d ${pgdb} -c 'SELECT version();'" 2>&1 | tee -a "$LOG_FILE"; then
        error "Post-restart connectivity check FAILED"
        return 1
    fi

    # Check pg_stat_statements is loaded (if we added it to shared_preload_libraries)
    log "Checking pg_stat_statements availability..."
    local pgss
    pgss=$(ssh -o ConnectTimeout=5 "root@${server}" \
        "docker exec ${container} psql -U ${pguser} -d ${pgdb} -t -c \"SELECT extname FROM pg_extension WHERE extname = 'pg_stat_statements';\"" 2>&1)
    log "pg_stat_statements extension: ${pgss:-not installed yet (needs CREATE EXTENSION)}"

    # Check shared_buffers was applied
    log "Checking shared_buffers was applied..."
    ssh -o ConnectTimeout=5 "root@${server}" \
        "docker exec ${container} psql -U ${pguser} -d ${pgdb} -c \"SHOW shared_buffers;\"" 2>&1 | tee -a "$LOG_FILE"

    # Connections check
    log "Connection count:"
    ssh -o ConnectTimeout=5 "root@${server}" \
        "docker exec ${container} psql -U ${pguser} -d ${pgdb} -c \"SELECT count(*) FROM pg_stat_activity;\"" 2>&1 | tee -a "$LOG_FILE"

    log "Post-restart verification PASSED"
    return 0
}

# =============================================================================
# Apply procedure for one instance
# =============================================================================

apply_one() {
    local instance_name="$1"

    parse_instance_config "$instance_name"

    echo ""
    echo "=============================================================================="
    log "APPLYING: $instance_name"
    log "  Server:    $SERVER_IP"
    log "  Container: $CONTAINER"
    log "  Config:    $CONFIG_FILE"
    echo "=============================================================================="

    # Step 1: Pre-flight checks
    verify_ssh "$SERVER_IP"
    verify_container "$SERVER_IP" "$CONTAINER"
    verify_psql "$SERVER_IP" "$CONTAINER" "$PGUSER" "$PGDB"

    # Step 2: Backup
    backup_config "$SERVER_IP" "$CONTAINER" "$PG_CONF_PATH" "$instance_name"

    # Step 3: Apply
    apply_config "$SERVER_IP" "$CONTAINER" "$PG_CONF_PATH" "$CONFIG_FILE"

    # Step 4: Restart
    if ! restart_container "$SERVER_IP" "$CONTAINER"; then
        error "Container restart FAILED for $instance_name!"
        warn "ROLLBACK: docker cp ${BACKUP_DIR}/${instance_name}_postgresql.conf.bak ${CONTAINER}:${PG_CONF_PATH}"
        warn "ROLLBACK: docker restart ${CONTAINER}"
        return 1
    fi

    # Step 5: Verify
    if ! verify_after_restart "$SERVER_IP" "$CONTAINER" "$PGUSER" "$PGDB"; then
        error "Post-restart verification FAILED for $instance_name!"
        warn "ROLLBACK COMMAND:"
        warn "  scp ${BACKUP_DIR}/${instance_name}_postgresql.conf.bak root@${SERVER_IP}:/tmp/rollback.conf"
        warn "  ssh root@${SERVER_IP} \"docker cp /tmp/rollback.conf ${CONTAINER}:${PG_CONF_PATH}\""
        warn "  ssh root@${SERVER_IP} \"docker restart ${CONTAINER}\""
        return 1
    fi

    log "SUCCESS: $instance_name configuration applied and verified."
    echo ""
    echo "Backup saved: ${BACKUP_DIR}/${instance_name}_postgresql.conf.bak"
    echo "Rollback if needed:"
    echo "  scp ${BACKUP_DIR}/${instance_name}_postgresql.conf.bak root@${SERVER_IP}:/tmp/rollback.conf"
    echo "  ssh root@${SERVER_IP} \"docker cp /tmp/rollback.conf ${CONTAINER}:${PG_CONF_PATH} && docker restart ${CONTAINER}\""
}

# =============================================================================
# Post-apply: CREATE EXTENSION pg_stat_statements (if preload was changed)
# =============================================================================

create_pg_stat_statements() {
    local instance_name="$1"
    parse_instance_config "$instance_name"

    log "Creating pg_stat_statements extension on $instance_name (if not exists)..."
    ssh -o ConnectTimeout=5 "root@${SERVER_IP}" \
        "docker exec ${CONTAINER} psql -U ${PGUSER} -d ${PGDB} -c \"CREATE EXTENSION IF NOT EXISTS pg_stat_statements;\"" 2>&1 | tee -a "$LOG_FILE"

    # Verify
    ssh -o ConnectTimeout=5 "root@${SERVER_IP}" \
        "docker exec ${CONTAINER} psql -U ${PGUSER} -d ${PGDB} -c \"SELECT extname, extversion FROM pg_extension WHERE extname='pg_stat_statements';\"" 2>&1 | tee -a "$LOG_FILE"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        echo "Usage: $0 <instance-name>"
        echo ""
        echo "Single instances:"
        for key in "${!INSTANCES[@]}"; do
            echo "  $key"
        done
        echo ""
        echo "Groups:"
        echo "  all-coredb      Apply wheeler-postgres on COREDB server"
        echo "  all-aiops       Apply all 3 instances on AIOPS server"
        exit 1
    fi

    mkdir -p "$BACKUP_DIR"
    echo "Backup directory: $BACKUP_DIR"
    echo "Log file: $LOG_FILE"

    case "$target" in
        all-coredb)
            apply_one "wheeler-postgres" && \
            create_pg_stat_statements "wheeler-postgres"
            ;;
        all-aiops)
            local failed=0
            for instance in frgops-standby prediction-radar-app-db aiops-ravynai-postgres; do
                if ! apply_one "$instance"; then
                    failed=1
                    error "$instance failed -- continuing with others"
                fi
            done
            # Create extensions on successful applies
            create_pg_stat_statements "frgops-standby" || true
            create_pg_stat_statements "prediction-radar-app-db" || true
            create_pg_stat_statements "aiops-ravynai-postgres" || true
            if [[ $failed -eq 1 ]]; then
                error "One or more AIOPS instances failed. Check log: $LOG_FILE"
                exit 1
            fi
            ;;
        *)
            check_instance_exists "$target"
            apply_one "$target" && \
            create_pg_stat_statements "$target"
            ;;
    esac

    echo ""
    echo "=============================================================================="
    log "DONE. All operations completed."
    log "Backups: $BACKUP_DIR"
    log "Log:     $LOG_FILE"
    echo "=============================================================================="
}

main "$@"
