#!/bin/bash
# ============================================================================
# safe-apply-redis-tuning.sh
# Phase 5 -- Redis Optimization: Safe runtime tuning with backup and rollback
#
# Usage:
#   ./safe-apply-redis-tuning.sh <target>
#
# Targets:
#   wheeler-redis        COREDB (5.78.210.123)
#   docuseal-redis       AIOPS  (5.78.140.118)
#   prediction-radar     AIOPS  (5.78.140.118)
#   usesend-redis        EDGE   (187.77.148.88)
#
# Operations:
#   --apply     Apply optimized tuning (default)
#   --rollback  Rollback last applied tuning
#   --verify    Verify current settings against recommended
#   --status    Show current memory/stats without changes
#
# Example:
#   ./safe-apply-redis-tuning.sh wheeler-redis --apply
#   ./safe-apply-redis-tuning.sh usesend-redis --rollback
#   ./safe-apply-redis-tuning.sh docuseal-redis --verify
# ============================================================================

set -euo pipefail

# ---- Color Output ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $*"; }
log_data()  { echo -e "       $*"; }

# ---- Configuration per Target ----
declare -A TARGET_HOST
declare -A TARGET_CONTAINER
declare -A TARGET_AUTH
declare -A TARGET_PASSWORD

TARGET_HOST["wheeler-redis"]="5.78.210.123"
TARGET_CONTAINER["wheeler-redis"]="wheeler-redis"
TARGET_AUTH["wheeler-redis"]="yes"
TARGET_PASSWORD["wheeler-redis"]="FRGpassword1!"

TARGET_HOST["docuseal-redis"]="5.78.140.118"
TARGET_CONTAINER["docuseal-redis"]="docuseal-redis"
TARGET_AUTH["docuseal-redis"]="no"
TARGET_PASSWORD["docuseal-redis"]=""

TARGET_HOST["prediction-radar"]="5.78.140.118"
TARGET_CONTAINER["prediction-radar"]="prediction-radar-app-redis"
TARGET_AUTH["prediction-radar"]="no"
TARGET_PASSWORD["prediction-radar"]=""

TARGET_HOST["usesend-redis"]="187.77.148.88"
TARGET_CONTAINER["usesend-redis"]="usesend-redis"
TARGET_AUTH["usesend-redis"]="no"
TARGET_PASSWORD["usesend-redis"]=""

# ---- Recommended Settings per Target ----
# Format: "CONFIG_KEY=VALUE" space-separated
declare -A RECOMMENDED

RECOMMENDED["wheeler-redis"]="maxmemory=67108864 maxmemory-policy=allkeys-lru activedefrag=yes lazyfree-lazy-eviction=yes lazyfree-lazy-expire=yes lazyfree-lazy-server-del=yes appendonly=no save= timeout=300 tcp-keepalive=300 slowlog-log-slower-than=10000 latency-monitor-threshold=100"

RECOMMENDED["docuseal-redis"]="maxmemory=134217728 maxmemory-policy=allkeys-lru activedefrag=yes lazyfree-lazy-eviction=yes lazyfree-lazy-expire=yes lazyfree-lazy-server-del=yes save=900 1 3600 10 stop-writes-on-bgsave-error=no slowlog-log-slower-than=10000 latency-monitor-threshold=100"

RECOMMENDED["prediction-radar"]="maxmemory=33554432 maxmemory-policy=allkeys-lru activedefrag=yes lazyfree-lazy-eviction=yes lazyfree-lazy-expire=yes lazyfree-lazy-server-del=yes appendonly=no save= timeout=300 tcp-keepalive=300 slowlog-log-slower-than=10000 latency-monitor-threshold=100"

RECOMMENDED["usesend-redis"]="maxmemory=268435456 maxmemory-policy=allkeys-lru activedefrag=yes lazyfree-lazy-eviction=yes lazyfree-lazy-expire=yes lazyfree-lazy-server-del=yes lazyfree-lazy-user-del=yes save=900 1 3600 10 stop-writes-on-bgsave-error=no slowlog-log-slower-than=50000 latency-monitor-threshold=100 lua-time-limit=5000"

# ---- Backup directory ----
BACKUP_DIR="/root/redis-backups/$(date +%Y%m%d_%H%M%S)"

# ---- Helper Functions ----

# Build redis-cli command with optional auth
redis_cli() {
    local target="$1"; shift
    local container="${TARGET_CONTAINER[$target]}"
    local ssh_host="${TARGET_HOST[$target]}"
    local has_auth="${TARGET_AUTH[$target]}"
    local password="${TARGET_PASSWORD[$target]}"

    if [ "$has_auth" = "yes" ] && [ -n "$password" ]; then
        ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${ssh_host}" \
            "docker exec ${container} redis-cli -a '${password}' --no-auth-warning $*" 2>&1
    else
        ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${ssh_host}" \
            "docker exec ${container} redis-cli --no-auth-warning $*" 2>&1
    fi
}

# Check container is running and reachable
preflight_check() {
    local target="$1"
    local ssh_host="${TARGET_HOST[$target]}"
    local container="${TARGET_CONTAINER[$target]}"

    log_step "Pre-flight check: ${target} (${ssh_host} / ${container})"

    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${ssh_host}" "echo OK" >/dev/null 2>&1; then
        log_error "Cannot SSH to ${ssh_host}"
        return 1
    fi
    log_info "SSH connectivity: OK"

    # Check container is running
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${ssh_host}" \
        "docker inspect -f '{{.State.Running}}' ${container}" 2>/dev/null | grep -q "true"; then
        log_error "Container ${container} is not running on ${ssh_host}"
        return 1
    fi
    log_info "Container running: OK"

    # Check redis-cli connectivity
    local ping_result
    ping_result=$(redis_cli "$target" PING 2>&1)
    if ! echo "$ping_result" | grep -q "PONG"; then
        log_error "Redis PING failed: ${ping_result}"
        return 1
    fi
    log_info "Redis PING: OK"

    return 0
}

# Backup current configuration
create_backup() {
    local target="$1"
    local target_backup_dir="${BACKUP_DIR}/${target}"

    log_step "Creating backup: ${target_backup_dir}"
    mkdir -p "$target_backup_dir"

    # Trigger BGSAVE for RDB snapshot
    log_info "Triggering BGSAVE..."
    local bgsave_result
    bgsave_result=$(redis_cli "$target" BGSAVE 2>&1)
    log_data "BGSAVE: ${bgsave_result}"

    # Wait for BGSAVE to complete
    sleep 2
    local save_status
    save_status=$(redis_cli "$target" INFO persistence 2>&1 | grep "rdb_bgsave_in_progress:1")
    local waited=2
    while [ -n "$save_status" ] && [ $waited -lt 30 ]; do
        sleep 2
        waited=$((waited + 2))
        save_status=$(redis_cli "$target" INFO persistence 2>&1 | grep "rdb_bgsave_in_progress:1")
    done
    log_info "BGSAVE completed after ${waited}s"

    # Export all current CONFIG
    log_info "Exporting current CONFIG..."
    redis_cli "$target" CONFIG GET "*" > "${target_backup_dir}/config-backup.txt" 2>&1
    log_info "CONFIG saved to ${target_backup_dir}/config-backup.txt"

    # Save memory stats
    redis_cli "$target" INFO memory > "${target_backup_dir}/memory-pre.txt" 2>&1
    redis_cli "$target" INFO stats > "${target_backup_dir}/stats-pre.txt" 2>&1
    redis_cli "$target" INFO keyspace > "${target_backup_dir}/keyspace-pre.txt" 2>&1
    redis_cli "$target" INFO persistence > "${target_backup_dir}/persistence-pre.txt" 2>&1
    log_info "Pre-change stats saved"
}

# Apply a single config setting
apply_config() {
    local target="$1"
    local key="$2"
    local value="$3"

    log_info "  Setting ${key} = ${value}"
    local result
    result=$(redis_cli "$target" CONFIG SET "$key" "$value" 2>&1)
    if echo "$result" | grep -q "OK"; then
        log_data "    -> OK"
    else
        log_error "    -> FAILED: ${result}"
        return 1
    fi
    return 0
}

# Apply all recommended settings
apply_tuning() {
    local target="$1"

    log_step "Applying optimized tuning for: ${target}"
    log_info "Recommended settings: ${RECOMMENDED[$target]}"

    local failed=0
    for setting in ${RECOMMENDED[$target]}; do
        local key="${setting%%=*}"
        local value="${setting#*=}"

        # Handle 'save ""' -> save= special case
        if [ "$key" = "save" ] && [ "$value" = '""' ]; then
            value=""
        fi

        if ! apply_config "$target" "$key" "$value"; then
            failed=1
        fi
    done

    if [ $failed -eq 1 ]; then
        log_error "Some settings failed to apply. Check output above."
        return 1
    fi

    log_info "All settings applied successfully"
    return 0
}

# Verify applied settings match recommended
verify_tuning() {
    local target="$1"

    log_step "Verifying applied settings for: ${target}"

    local mismatch=0
    for setting in ${RECOMMENDED[$target]}; do
        local key="${setting%%=*}"
        local expected="${setting#*=}"

        # Handle 'save ""' -> save='' special case
        if [ "$key" = "save" ] && [ "$expected" = '""' ]; then
            expected=""
        fi

        local actual
        actual=$(redis_cli "$target" CONFIG GET "$key" 2>&1 | tail -1)
        # CONFIG GET returns key on one line, value on next -- take second line
        actual=$(redis_cli "$target" CONFIG GET "$key" 2>&1 | tail -n +2 | head -1)

        if [ "$actual" = "$expected" ]; then
            log_data "  ${key}: ${actual} [MATCH]"
        else
            log_warn "  ${key}: got='${actual}' expected='${expected}' [MISMATCH]"
            mismatch=1
        fi
    done

    if [ $mismatch -eq 0 ]; then
        log_info "All settings verified: PASS"
    else
        log_warn "Some settings do not match expected values"
    fi
}

# Show current status
show_status() {
    local target="$1"

    echo ""
    echo "========== STATUS: ${target} =========="
    echo ""

    echo "--- Memory ---"
    redis_cli "$target" INFO memory 2>&1 | grep -E "used_memory_human|used_memory_rss_human|maxmemory_human|maxmemory_policy|mem_fragmentation_ratio|evicted_keys"
    echo ""

    echo "--- Keyspace ---"
    redis_cli "$target" INFO keyspace 2>&1
    echo ""

    echo "--- Key Eviction Policy ---"
    redis_cli "$target" CONFIG GET maxmemory-policy 2>&1
    redis_cli "$target" CONFIG GET maxmemory 2>&1
    redis_cli "$target" CONFIG GET activedefrag 2>&1
    echo ""

    echo "--- Cache Hit Rate ---"
    redis_cli "$target" INFO stats 2>&1 | grep -E "keyspace_hits|keyspace_misses|evicted_keys|expired_keys|instantaneous_ops_per_sec"
    echo ""

    echo "--- Persistence ---"
    redis_cli "$target" INFO persistence 2>&1 | grep -E "aof_enabled|rdb_last_bgsave_status|aof_current_size|rdb_changes_since_last_save"
    echo ""

    echo "--- Slow Log (last 5) ---"
    redis_cli "$target" SLOWLOG GET 5 2>&1 | head -40
    echo ""
}

# Rollback to previous backup
rollback_tuning() {
    local target="$1"

    # Find latest backup
    local latest_backup
    latest_backup=$(ls -dt /root/redis-backups/*/ 2>/dev/null | head -1)
    if [ -z "$latest_backup" ]; then
        log_error "No backups found in /root/redis-backups/"
        return 1
    fi

    local config_file="${latest_backup}${target}/config-backup.txt"
    if [ ! -f "$config_file" ]; then
        log_error "No backup found for target '${target}' in ${latest_backup}"
        log_error "Available backups:"
        ls -la /root/redis-backups/*/
        return 1
    fi

    log_step "Rolling back ${target} from backup: ${config_file}"
    log_warn "This will restore ALL config settings to their pre-tuning values."

    read -p "Proceed with rollback? [y/N] " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Rollback cancelled"
        return 0
    fi

    local key value failed=0
    while IFS= read -r line; do
        # Parse "key" then "value" pairs from CONFIG GET output
        if [ -z "${key:-}" ]; then
            key="$line"
        else
            value="$line"
            if ! apply_config "$target" "$key" "$value"; then
                failed=1
            fi
            key=""
        fi
    done < "$config_file"

    if [ $failed -eq 1 ]; then
        log_error "Some rollback settings failed. Manual intervention may be needed."
        return 1
    fi

    log_info "Rollback complete"
    return 0
}

# ---- Main ----
main() {
    local target="${1:-}"
    local action="${2:---apply}"

    if [ -z "$target" ]; then
        echo "Usage: $0 <target> [--apply|--rollback|--verify|--status]"
        echo ""
        echo "Targets:"
        echo "  wheeler-redis        COREDB (5.78.210.123)"
        echo "  docuseal-redis       AIOPS  (5.78.140.118)"
        echo "  prediction-radar     AIOPS  (5.78.140.118)"
        echo "  usesend-redis        EDGE   (187.77.148.88)"
        echo ""
        echo "Actions:"
        echo "  --apply     Apply optimized tuning (default)"
        echo "  --rollback  Rollback last applied tuning"
        echo "  --verify    Verify current settings against recommended"
        echo "  --status    Show current memory/stats without changes"
        exit 1
    fi

    if [ -z "${TARGET_HOST[$target]:-}" ]; then
        log_error "Unknown target: ${target}"
        echo "Valid targets: wheeler-redis, docuseal-redis, prediction-radar, usesend-redis"
        exit 1
    fi

    case "$action" in
        --apply)
            echo ""
            echo "=========================================="
            echo "  REDIS TUNING: ${target}"
            echo "  Action: APPLY"
            echo "  Host: ${TARGET_HOST[$target]}"
            echo "  Container: ${TARGET_CONTAINER[$target]}"
            echo "=========================================="
            echo ""

            preflight_check "$target" || exit 1
            create_backup "$target" || exit 1
            apply_tuning "$target" || exit 1

            echo ""
            log_info "Waiting 5 seconds for settings to stabilize..."
            sleep 5

            verify_tuning "$target"
            echo ""
            show_status "$target"

            echo ""
            log_info "=========================================="
            log_info "Tuning complete for: ${target}"
            log_info "Backup stored at: ${BACKUP_DIR}/${target}/"
            log_info ""
            log_info "To rollback: $0 ${target} --rollback"
            log_info "To verify:   $0 ${target} --verify"
            log_info ""
            log_warn "NOTE: These are RUNTIME changes. Container restart will"
            log_warn "      revert them unless the config file is mounted."
            log_warn "      For permanent changes, mount the generated .conf file"
            log_warn "      at /usr/local/etc/redis/redis.conf in the container."
            log_info "=========================================="
            ;;

        --rollback)
            echo ""
            echo "=========================================="
            echo "  REDIS ROLLBACK: ${target}"
            echo "=========================================="
            echo ""

            preflight_check "$target" || exit 1
            rollback_tuning "$target" || exit 1

            echo ""
            log_info "Verifying post-rollback..."
            show_status "$target"
            ;;

        --verify)
            preflight_check "$target" || exit 1
            verify_tuning "$target"
            show_status "$target"
            ;;

        --status)
            preflight_check "$target" || exit 1
            show_status "$target"
            ;;

        *)
            log_error "Unknown action: ${action}"
            echo "Valid actions: --apply, --rollback, --verify, --status"
            exit 1
            ;;
    esac
}

main "$@"
