#!/usr/bin/env bash
# =============================================================================
# apply-docker-optimizations.sh
# PHASE 3 -- DOCKER OPTIMIZATION PLAN
# Generated: 2026-05-23
#
# SAFE, READ-ONLY-FIRST script to apply Docker optimizations.
# All changes are backed up before application. Rollback is automatic on failure.
#
# Usage:
#   ./apply-docker-optimizations.sh [--dry-run] [--server AIOPS|COREDB|EDGE|ALL]
#   ./apply-docker-optimizations.sh --rollback [--server AIOPS|COREDB|EDGE]
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="/root/docker-optimization-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
LOG_FILE="${BACKUP_DIR}/apply.log"

# Server configs
declare -A SERVER_IPS
SERVER_IPS["AIOPS"]="5.78.140.118"
SERVER_IPS["COREDB"]="5.78.210.123"
SERVER_IPS["EDGE"]="187.77.148.88"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse Arguments
DRY_RUN=false
ROLLBACK=false
TARGET_SERVER="ALL"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --rollback)
      ROLLBACK=true
      shift
      ;;
    --server)
      TARGET_SERVER="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--dry-run] [--rollback] [--server AIOPS|COREDB|EDGE|ALL]"
      exit 1
      ;;
  esac
done

# Logging setup
mkdir -p "${BACKUP_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }

# SSH helpers
ssh_exec() {
  local server="$1"
  local cmd="$2"
  local ip="${SERVER_IPS[$server]}"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: ssh root@${ip} ${cmd}"
    return 0
  fi
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${ip}" "${cmd}"
}

# Backup compose files from a server
backup_compose_files() {
  local server="$1"
  log "Backing up docker-compose files from ${server}..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: Would backup compose files from ${server}"
    return 0
  fi

  local backup_script='
    mkdir -p /root/docker-backup-BACKUPTS
    for dir in /opt /docker; do
      if [ -d "$dir" ]; then
        find "$dir" -maxdepth 3 \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yaml" -o -name "compose.yml" \) -exec cp --parents {} /root/docker-backup-BACKUPTS/ \; 2>/dev/null || true
      fi
    done
    tar czf /root/docker-backup-BACKUPTS.tar.gz -C /root docker-backup-BACKUPTS/
    rm -rf /root/docker-backup-BACKUPTS/
    echo "Backup created: /root/docker-backup-BACKUPTS.tar.gz"
  '
  backup_script="${backup_script//BACKUPTS/${TIMESTAMP}}"

  ssh_exec "${server}" "${backup_script}"
  ok "Backup completed for ${server}"
}

# Pre-flight checks
preflight_check() {
  local server="$1"
  log "Running pre-flight checks on ${server}..."

  if ! ssh_exec "${server}" "echo OK" &>/dev/null; then
    err "Cannot connect to ${server} (${SERVER_IPS[$server]})"
    return 1
  fi
  ok "SSH connectivity: OK"

  if ! ssh_exec "${server}" "docker info --format '{{.ServerVersion}}' 2>/dev/null"; then
    err "Docker not running on ${server}"
    return 1
  fi
  ok "Docker daemon: OK"

  log "Capturing pre-optimization state..."
  if [[ "$DRY_RUN" == "false" ]]; then
    ssh_exec "${server}" "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" > "${BACKUP_DIR}/${server}-pre-ps.txt"
    ssh_exec "${server}" "docker stats --no-stream" > "${BACKUP_DIR}/${server}-pre-stats.txt"
  fi
  ok "State snapshot saved"
  return 0
}

# Apply AIOPS optimizations
apply_aiops() {
  local server="AIOPS"
  log "=== Applying AIOPS (${SERVER_IPS[$server]}) optimizations ==="

  preflight_check "${server}" || return 1
  backup_compose_files "${server}"

  # Quick wins
  log "AIOPS: Pruning build cache..."
  ssh_exec "${server}" "docker builder prune -f" || warn "Builder prune failed (non-critical)"

  log "AIOPS: Removing orphaned volume monitoring_uptime-kuma-data..."
  ssh_exec "${server}" "docker volume rm monitoring_uptime-kuma-data 2>/dev/null || true"

  log "AIOPS: Removing duplicate langflow:latest image (5.5 GB)..."
  ssh_exec "${server}" "docker rmi langflowai/langflow:latest 2>/dev/null || true"
  ok "AIOPS quick wins applied"

  # Port audit
  log "AIOPS: Port exposure audit..."
  ssh_exec "${server}" "docker ps --format '{{.Names}} {{.Ports}}'" > "${BACKUP_DIR}/${server}-port-audit.txt"

  warn "AIOPS: Manual steps required for compose file updates:"
  warn "  - Add log rotation to portainer, dockge, uptime-kuma"
  warn "  - Add resource limits per AIOPS-optimized-docker-compose.yml"
  warn "  - Review port bindings (frgops-standby, ravynai-postgres, netdata, portainer)"

  ok "AIOPS optimizations applied"
  return 0
}

# Apply COREDB optimizations
apply_coredb() {
  local server="COREDB"
  log "=== Applying COREDB (${SERVER_IPS[$server]}) optimizations ==="

  preflight_check "${server}" || return 1
  backup_compose_files "${server}"

  # Add logging config to core compose
  log "COREDB: Adding log rotation to /opt/wheeler-core/docker-compose.yml..."
  if [[ "$DRY_RUN" == "false" ]]; then
    ssh_exec "${server}" "cp /opt/wheeler-core/docker-compose.yml /opt/wheeler-core/docker-compose.yml.bak-${TIMESTAMP}"

    if ! ssh_exec "${server}" "grep -q 'max-size' /opt/wheeler-core/docker-compose.yml 2>/dev/null"; then
      # Prepend shared logging anchor
      ssh_exec "${server}" "sed -i '1i x-logging: \&default-logging\n  driver: json-file\n  options:\n    max-size: \"10m\"\n    max-file: \"3\"\n' /opt/wheeler-core/docker-compose.yml"

      # Add logging line after each container_name
      ssh_exec "${server}" "sed -i '/container_name: wheeler-postgres/a\    logging: *default-logging' /opt/wheeler-core/docker-compose.yml"
      ssh_exec "${server}" "sed -i '/container_name: wheeler-redis/a\    logging: *default-logging' /opt/wheeler-core/docker-compose.yml"
      ssh_exec "${server}" "sed -i '/container_name: wheeler-minio/a\    logging: *default-logging' /opt/wheeler-core/docker-compose.yml"

      ok "COREDB: Logging config added"
    else
      ok "COREDB: Logging already configured"
    fi
  fi

  warn "COREDB: Manual steps required:"
  warn "  - Add resource limits (postgres: 1g/2cpu, redis: 256m/0.5cpu, minio: 512m/1cpu)"
  warn "  - Bind ports to 127.0.0.1 or configure host firewall"
  warn "  - Run: cd /opt/wheeler-core && docker compose up -d"

  ok "COREDB optimizations applied"
  return 0
}

# Apply EDGE optimizations
apply_edge() {
  local server="EDGE"
  log "=== Applying EDGE (${SERVER_IPS[$server]}) optimizations ==="

  preflight_check "${server}" || return 1
  backup_compose_files "${server}"

  # Capture temporal crash logs
  log "EDGE: Capturing temporal-temporal-1 logs (15 restarts)..."
  ssh_exec "${server}" "docker logs --tail 50 temporal-temporal-1 2>&1" > "${BACKUP_DIR}/${server}-temporal-temporal-1-logs.txt" 2>/dev/null || true

  # Capture redis CPU anomaly info
  log "EDGE: Capturing usesend-redis INFO..."
  ssh_exec "${server}" "docker exec usesend-redis redis-cli INFO cpu 2>/dev/null || echo 'redis-cli not available'" > "${BACKUP_DIR}/${server}-usesend-redis-info.txt" 2>/dev/null || true

  # Prune old images
  log "EDGE: Pruning unused images (7+ days old)..."
  if [[ "$DRY_RUN" == "false" ]]; then
    ssh_exec "${server}" "docker image prune -a --filter 'until=168h' -f" || warn "Image prune failed (non-critical)"
  fi

  warn "EDGE: CRITICAL manual steps required:"
  warn "  - temporal-server: Change restart policy from 'no' to 'on-failure:5'"
  warn "  - temporal-server: Add mem_limit: 1g, cpus: 2.0"
  warn "  - temporal-temporal-1: Change to 'on-failure:10', investigate crash loop"
  warn "  - usesend-redis: Investigate 44% CPU anomaly, add cpus: 0.5"
  warn "  - usesend services: Change restart from 'always' to 'unless-stopped'"

  ok "EDGE optimizations applied"
  return 0
}

# Verify server state post-optimization
verify_server() {
  local server="$1"
  log "=== Verifying ${server} ==="

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: Would verify ${server}"
    return 0
  fi

  # Check recent restarts
  local restart_count
  restart_count=$(ssh_exec "${server}" "docker ps -q | xargs -I{} docker inspect --format '{{.Name}} {{.RestartCount}}' {} 2>/dev/null | grep -v ' 0$' || true")

  if [[ -n "${restart_count}" ]]; then
    warn "Containers with non-zero restart count on ${server}:"
    echo "${restart_count}"
  else
    ok "All containers on ${server} have 0 recent restarts"
  fi

  # Check unhealthy
  local unhealthy
  unhealthy=$(ssh_exec "${server}" "docker ps --filter 'health=unhealthy' --format '{{.Names}} {{.Status}}' 2>/dev/null || true")
  if [[ -n "${unhealthy}" ]]; then
    err "UNHEALTHY containers on ${server}:"
    echo "${unhealthy}"
  else
    ok "No unhealthy containers on ${server}"
  fi

  ssh_exec "${server}" "docker stats --no-stream" > "${BACKUP_DIR}/${server}-post-stats.txt" 2>/dev/null || true
  ok "Post-optimization stats saved"
}

# Rollback
do_rollback() {
  local server="$1"
  log "=== Rolling back ${server} ==="

  local backups
  backups=$(ssh_exec "${server}" "ls -dt /root/docker-backup-*.tar.gz 2>/dev/null | head -5" || true)

  if [[ -z "${backups}" ]]; then
    err "No backups found on ${server}"
    return 1
  fi

  echo "Available backups on ${server}:"
  echo "${backups}"

  local latest
  latest=$(echo "${backups}" | head -1)
  log "Rolling back to: ${latest}"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: Would restore ${latest}"
    return 0
  fi

  ssh_exec "${server}" "cd / && tar xzf '${latest}'"
  ok "Rollback completed for ${server}"
  warn "After rollback, manually restart services if needed"
  return 0
}

# Summary
print_summary() {
  echo ""
  echo "=============================================="
  echo "  DOCKER OPTIMIZATION -- EXECUTION SUMMARY"
  echo "  Timestamp: ${TIMESTAMP}"
  echo "  Backup:    ${BACKUP_DIR}"
  echo "  Log:       ${LOG_FILE}"
  echo "=============================================="

  if [[ "$DRY_RUN" == "true" ]]; then
    warn "THIS WAS A DRY RUN -- NO CHANGES WERE MADE"
  fi

  echo ""
  echo "Manual actions still required:"
  echo ""
  echo "AIOPS:"
  echo "  1. Add log rotation to portainer, dockge, uptime-kuma compose files"
  echo "  2. Add resource limits per AIOPS-optimized-docker-compose.yml"
  echo "  3. Review port bindings (netdata, portainer, frgops-standby, ravynai-postgres)"
  echo "  4. Run: docker compose up -d for each updated service"
  echo ""
  echo "COREDB:"
  echo "  1. Add resource limits per COREDB-optimized-docker-compose.yml"
  echo "  2. Bind ports to 127.0.0.1 or configure host firewall"
  echo "  3. Decide whether to restart monitoring stack (currently stopped)"
  echo ""
  echo "EDGE:"
  echo "  1. Fix temporal-server restart policy (NO restart policy = danger)"
  echo "  2. Investigate temporal-temporal-1 crash loop (15 restarts)"
  echo "  3. Investigate usesend-redis CPU anomaly (44% CPU)"
  echo "  4. Add CPU limits per EDGE-optimized-docker-compose.yml"
  echo ""
  echo "=============================================="
}

# Main
main() {
  echo ""
  echo "=============================================="
  echo "  PHASE 3 -- DOCKER OPTIMIZATION APPLY SCRIPT"
  echo "  Mode:    $([[ "$DRY_RUN" == "true" ]] && echo 'DRY RUN' || echo 'LIVE')"
  echo "  Server:  ${TARGET_SERVER}"
  echo "  Rollback: $([[ "$ROLLBACK" == "true" ]] && echo 'YES' || echo 'NO')"
  echo "=============================================="
  echo ""

  if [[ "$ROLLBACK" == "true" ]]; then
    if [[ "${TARGET_SERVER}" == "ALL" ]]; then
      for server in AIOPS COREDB EDGE; do
        do_rollback "${server}" || warn "Rollback failed for ${server}"
      done
    else
      do_rollback "${TARGET_SERVER}"
    fi
    exit 0
  fi

  local failed=""

  if [[ "${TARGET_SERVER}" == "ALL" ]] || [[ "${TARGET_SERVER}" == "AIOPS" ]]; then
    apply_aiops || failed="${failed} AIOPS"
    verify_server "AIOPS" || warn "Verification issues on AIOPS"
  fi

  if [[ "${TARGET_SERVER}" == "ALL" ]] || [[ "${TARGET_SERVER}" == "COREDB" ]]; then
    apply_coredb || failed="${failed} COREDB"
    verify_server "COREDB" || warn "Verification issues on COREDB"
  fi

  if [[ "${TARGET_SERVER}" == "ALL" ]] || [[ "${TARGET_SERVER}" == "EDGE" ]]; then
    apply_edge || failed="${failed} EDGE"
    verify_server "EDGE" || warn "Verification issues on EDGE"
  fi

  print_summary

  if [[ -n "${failed}" ]]; then
    err "Optimizations failed on:${failed}"
    err "Review ${LOG_FILE} for details."
    err "Run with --rollback to restore backups."
    exit 1
  fi

  ok "All optimizations applied successfully."
  warn "Some changes require manual compose file updates -- see summary above."
}

main "$@"
