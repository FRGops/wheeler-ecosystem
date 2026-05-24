#!/bin/bash
# =============================================================================
# Wheeler — Docker Pre-Backup Hook Script
# =============================================================================
#
# This script is executed BEFORE a backup operation takes place.  It prepares
# the system for a consistent, verifiable backup by:
#   1. Dumping Docker volumes to a staging directory.
#   2. Snapshotting databases (PostgreSQL, Redis) for transaction consistency.
#   3. Verifying backup integrity with SHA256 checksums.
#   4. Generating a manifest for audit and restore automation.
#
# Usage:
#   ./docker-backup-hooks.sh [--service <name>] [--output-dir <path>] [--dry-run]
#
# Options:
#   --service <name>    Back up only the specified service (default: all).
#   --output-dir <path> Directory to stage backup artifacts (default: /opt/backups/stage).
#   --dry-run           Validate configuration and connectivity without writing data.
#
# Exit Codes:
#   0   Backup preparation succeeded — staging directory is ready.
#   1   Non-critical warnings (some volumes skipped, but DB snapshot OK).
#   2   Preparation failed (DB snapshot failed, critical volume missing).
#   3   Script configuration error (missing dependencies, invalid args).
#
# This script is designed to be called by:
#   - A cron job
#   - Restic / Borg / rsync wrapper
#   - A CI/CD pipeline (e.g., "backup" stage before deploy)
#
# =============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

# Default staging directory.  This is the pre-backup staging area — NOT the
# final backup destination.  After this script returns 0, the backup tool
# (restic, borg, rsync) copies from here to the final destination.
STAGE_DIR="/opt/backups/stage"

# Timestamp for this backup run (ISO 8601, safe for file names).
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")

# Maximum age (seconds) of a DB snapshot before it's considered stale.
SNAPSHOT_TIMEOUT=300  # 5 minutes

# Maximum age of backup staging directories before they are eligible for
# cleanup (in days).  Staging dirs older than this are deleted.
STAGE_RETENTION_DAYS=7

# List of Docker volumes to back up.
# Each entry is "volume_name:container_name:mount_path".
# - volume_name:    Named Docker volume or bind-mount identifier.
# - container_name: Running container that has this volume mounted.
# - mount_path:     Path inside the container where the volume is mounted.
declare -a VOLUMES_TO_BACKUP=(
  "wheeler-api-data:wheeler-api:/data"
  "wheeler-ai-worker-models:wheeler-ai-worker:/models"
  "wheeler-litellm-cache:wheeler-litellm:/cache"
)

# List of databases to snapshot.
# Each entry is "db_type:container_name:database_name".
declare -a DATABASES_TO_SNAPSHOT=(
  "postgres:wheeler-postgres:wheeler"
  "postgres:wheeler-postgres:wheeler_analytics"
  "redis:wheeler-redis:0"
)

# ── Color Output ──────────────────────────────────────────────────────────────

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $(date '+%H:%M:%S') $*"; }

die() {
  log_error "$*"
  exit 2
}

# ── Argument Parsing ─────────────────────────────────────────────────────────

SERVICE_FILTER=""
DRY_RUN=false
OUTPUT_DIR="${STAGE_DIR}"
EXIT_CODE=0
WARNINGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)
      SERVICE_FILTER="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--service <name>] [--output-dir <path>] [--dry-run]"
      exit 3
      ;;
  esac
done

# Create a run-specific subdirectory so multiple concurrent backups don't clash.
BACKUP_RUN_DIR="${OUTPUT_DIR}/${TIMESTAMP}"

# ── Pre-flight Checks ────────────────────────────────────────────────────────

log_info "=============================================="
log_info "Wheeler Docker Pre-Backup Hook"
log_info "=============================================="
log_info "Timestamp:       ${TIMESTAMP}"
log_info "Staging dir:     ${BACKUP_RUN_DIR}"
log_info "Service filter:  ${SERVICE_FILTER:-all}"
log_info "Dry run:         ${DRY_RUN}"
log_info "=============================================="

# Check that Docker is running.
if ! docker info &>/dev/null; then
  die "Docker daemon is not running.  Cannot perform backup."
fi

# Check for required tools.
for tool in docker pg_dump redis-cli sha256sum tar jq; do
  if ! command -v "$tool" &>/dev/null; then
    log_warn "Missing tool: $tool (some backup features may be unavailable)"
    WARNINGS=$((WARNINGS + 1))
  fi
done

# Create staging directory structure.
if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "${BACKUP_RUN_DIR}/volumes"    || die "Failed to create volumes staging dir"
  mkdir -p "${BACKUP_RUN_DIR}/databases"  || die "Failed to create databases staging dir"
  mkdir -p "${BACKUP_RUN_DIR}/manifests"  || die "Failed to create manifests staging dir"
  log_ok "Staging directory created at ${BACKUP_RUN_DIR}"
else
  log_info "DRY RUN: Would create staging directory at ${BACKUP_RUN_DIR}"
fi

# ── Cleanup stale staging directories ────────────────────────────────────────
if [[ "$DRY_RUN" == false ]]; then
  STALE_DIRS=$(find "${OUTPUT_DIR}" -maxdepth 1 -type d -mtime "+${STAGE_RETENTION_DAYS}" 2>/dev/null | wc -l)
  if [[ "$STALE_DIRS" -gt 0 ]]; then
    log_info "Cleaning up ${STALE_DIRS} stale staging directories (older than ${STAGE_RETENTION_DAYS} days)..."
    find "${OUTPUT_DIR}" -maxdepth 1 -type d -mtime "+${STAGE_RETENTION_DAYS}" -exec rm -rf {} \; 2>/dev/null || true
    log_ok "Stale staging directories cleaned."
  fi
fi

# =============================================================================
# PHASE 1 — Dump Docker Volumes to Staging
# =============================================================================
#
# Each named volume or bind mount is archived to the staging directory.
# Named Docker volumes are read via a temporary Alpine helper container
# that mounts the volume read-only and streams a tar.gz to the host.
# Bind mounts are tar'd directly from the host path.

log_info ""
log_info "PHASE 1: Dumping Docker volumes to staging..."

VOLUMES_PROCESSED=0
VOLUMES_FAILED=0
VOLUMES_SKIPPED=0

dump_volume() {
  local volume_name="$1"
  local container_name="$2"
  local mount_path="$3"

  # Apply service filter if specified.
  if [[ -n "${SERVICE_FILTER}" && "${container_name}" != *"${SERVICE_FILTER}"* ]]; then
    log_info "  Skipping ${volume_name} (does not match filter '${SERVICE_FILTER}')"
    VOLUMES_SKIPPED=$((VOLUMES_SKIPPED + 1))
    return 0
  fi

  local output_file="${BACKUP_RUN_DIR}/volumes/${volume_name}.tar.gz"
  log_info "  Backing up volume: ${volume_name} (container: ${container_name}:${mount_path})"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "    DRY RUN: Would create ${output_file}"
    VOLUMES_PROCESSED=$((VOLUMES_PROCESSED + 1))
    return 0
  fi

  # Strategy A: Named Docker volume.
  if docker volume inspect "${volume_name}" &>/dev/null 2>&1; then
    if docker run --rm \
      -v "${volume_name}:${mount_path}:ro" \
      -v "${BACKUP_RUN_DIR}/volumes:/backup" \
      alpine:latest \
      tar czf "/backup/${volume_name}.tar.gz" -C "${mount_path}" . 2>/dev/null; then
      sha256sum "${output_file}" > "${output_file}.sha256"
      log_ok "    Named volume dumped: ${output_file} ($(du -sh "${output_file}" | cut -f1))"
      VOLUMES_PROCESSED=$((VOLUMES_PROCESSED + 1))
    else
      log_error "    Failed to dump named volume: ${volume_name}"
      VOLUMES_FAILED=$((VOLUMES_FAILED + 1))
      return 1
    fi
    return 0
  fi

  # Strategy B: Bind mount (directory on the host).
  if docker inspect "${container_name}" &>/dev/null 2>&1; then
    local host_path
    host_path=$(docker inspect "${container_name}" | jq -r --arg mp "${mount_path}" '
      .[0].Mounts[] | select(.Destination == $mp) | .Source // empty' 2>/dev/null)

    if [[ -n "${host_path}" && -d "${host_path}" ]]; then
      if tar czf "${output_file}" -C "${host_path}" . 2>/dev/null; then
        sha256sum "${output_file}" > "${output_file}.sha256"
        log_ok "    Bind-mount dumped: ${host_path} -> ${output_file} ($(du -sh "${output_file}" | cut -f1))"
        VOLUMES_PROCESSED=$((VOLUMES_PROCESSED + 1))
      else
        log_error "    Failed to dump bind mount: ${host_path}"
        VOLUMES_FAILED=$((VOLUMES_FAILED + 1))
        return 1
      fi
    else
      log_warn "    Container '${container_name}' exists but mount '${mount_path}' not found.  Skipping."
      VOLUMES_SKIPPED=$((VOLUMES_SKIPPED + 1))
    fi
  else
    log_warn "    Volume '${volume_name}' not found and container '${container_name}' not running.  Skipping."
    VOLUMES_SKIPPED=$((VOLUMES_SKIPPED + 1))
  fi
}

for entry in "${VOLUMES_TO_BACKUP[@]}"; do
  IFS=':' read -r vol_name container mnt <<< "$entry"
  dump_volume "$vol_name" "$container" "$mnt" || true
done

log_info "Volume dump summary: ${VOLUMES_PROCESSED} processed, ${VOLUMES_FAILED} failed, ${VOLUMES_SKIPPED} skipped"

# =============================================================================
# PHASE 2 — Snapshot Databases
# =============================================================================
#
# Database snapshots guarantee transactional consistency for the backup.
# PostgreSQL:   pg_dump --format=custom (compressed, parallel-restorable).
# Redis:        BGSAVE then copy the RDB file via docker cp.

log_info ""
log_info "PHASE 2: Snapshotting databases..."

DBS_PROCESSED=0
DBS_FAILED=0
DBS_SKIPPED=0

snapshot_postgres() {
  local container="$1"
  local database="$2"
  local output_file="${BACKUP_RUN_DIR}/databases/${database}_${TIMESTAMP}.dump"

  # Apply service filter.
  if [[ -n "${SERVICE_FILTER}" && "${container}" != *"${SERVICE_FILTER}"* ]]; then
    log_info "  Skipping ${database} (does not match filter)"
    DBS_SKIPPED=$((DBS_SKIPPED + 1))
    return 0
  fi

  log_info "  Snapshotting PostgreSQL: ${database} (container: ${container})"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "    DRY RUN: Would create ${output_file}"
    DBS_PROCESSED=$((DBS_PROCESSED + 1))
    return 0
  fi

  # Verify container is running.
  if ! docker inspect --format='{{.State.Running}}' "${container}" 2>/dev/null | grep -q true; then
    log_error "    PostgreSQL container '${container}' is not running."
    DBS_FAILED=$((DBS_FAILED + 1))
    return 1
  fi

  # Issue CHECKPOINT to flush WAL for a clean starting point.
  docker exec "${container}" psql -U wheeler -c "CHECKPOINT;" &>/dev/null || true

  # Run pg_dump with a timeout.
  if timeout "${SNAPSHOT_TIMEOUT}" docker exec "${container}" \
    pg_dump \
      -U wheeler \
      -d "${database}" \
      --no-owner \
      --no-acl \
      --clean \
      --if-exists \
      --format=custom \
      --compress=9 \
      2>/tmp/pg_dump_error.log > "${output_file}"; then

    local dump_size
    dump_size=$(stat --format=%s "${output_file}" 2>/dev/null || echo 0)
    if [[ "${dump_size}" -lt 100 ]]; then
      log_error "    PostgreSQL dump for ${database} is too small (${dump_size} bytes) — may be empty."
      rm -f "${output_file}"
      DBS_FAILED=$((DBS_FAILED + 1))
      return 1
    fi

    sha256sum "${output_file}" > "${output_file}.sha256"
    log_ok "    PostgreSQL snapshot: ${output_file} ($(du -sh "${output_file}" | cut -f1))"
    DBS_PROCESSED=$((DBS_PROCESSED + 1))
  else
    local pg_error
    pg_error=$(cat /tmp/pg_dump_error.log 2>/dev/null || echo "unknown error")
    log_error "    PostgreSQL dump failed for ${database}: ${pg_error}"
    rm -f /tmp/pg_dump_error.log "${output_file}" 2>/dev/null || true
    DBS_FAILED=$((DBS_FAILED + 1))
    return 1
  fi
}

snapshot_redis() {
  local container="$1"
  local output_file="${BACKUP_RUN_DIR}/databases/redis_${TIMESTAMP}.rdb"

  # Apply service filter.
  if [[ -n "${SERVICE_FILTER}" && "${container}" != *"${SERVICE_FILTER}"* ]]; then
    log_info "  Skipping Redis (does not match filter)"
    DBS_SKIPPED=$((DBS_SKIPPED + 1))
    return 0
  fi

  log_info "  Snapshotting Redis (container: ${container})"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "    DRY RUN: Would trigger BGSAVE and copy RDB to ${output_file}"
    DBS_PROCESSED=$((DBS_PROCESSED + 1))
    return 0
  fi

  # Verify container is running.
  if ! docker inspect --format='{{.State.Running}}' "${container}" 2>/dev/null | grep -q true; then
    log_error "    Redis container '${container}' is not running."
    DBS_FAILED=$((DBS_FAILED + 1))
    return 1
  fi

  # Trigger BGSAVE.
  if ! docker exec "${container}" redis-cli BGSAVE &>/dev/null; then
    log_error "    Redis BGSAVE command failed."
    DBS_FAILED=$((DBS_FAILED + 1))
    return 1
  fi

  # Wait for BGSAVE to complete (poll LASTSAVE).
  local waited=0
  local start_ts
  start_ts=$(date +%s)
  while [[ ${waited} -lt 60 ]]; do
    local last_save_ts
    last_save_ts=$(docker exec "${container}" redis-cli LASTSAVE 2>/dev/null | tr -d '\r\n ')
    if [[ -n "${last_save_ts}" && "${last_save_ts}" -ge "${start_ts}" ]]; then
      log_info "    BGSAVE completed (waited ${waited}s)."
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  # Locate the RDB file.
  local rdb_path
  rdb_path=$(docker exec "${container}" redis-cli CONFIG GET dir 2>/dev/null | tail -1 | tr -d '\r')
  rdb_path="${rdb_path:-/data}/dump.rdb"

  # Copy RDB from container.
  if docker cp "${container}:${rdb_path}" "${output_file}" 2>/dev/null; then
    local rdb_size
    rdb_size=$(stat --format=%s "${output_file}" 2>/dev/null || echo 0)
    if [[ "${rdb_size}" -lt 50 ]]; then
      log_error "    Redis RDB file is too small (${rdb_size} bytes) — may be empty."
      rm -f "${output_file}"
      DBS_FAILED=$((DBS_FAILED + 1))
      return 1
    fi

    # Verify the RDB magic header bytes: "REDIS" = 0x52 0x45 0x44 0x49 0x53.
    local magic
    magic=$(xxd -l 5 -p "${output_file}" 2>/dev/null || echo "")
    if [[ "${magic}" != "5245444953" ]]; then
      log_error "    Redis RDB file has invalid magic bytes (expected 5245444953, got ${magic})."
      rm -f "${output_file}"
      DBS_FAILED=$((DBS_FAILED + 1))
      return 1
    fi

    sha256sum "${output_file}" > "${output_file}.sha256"
    log_ok "    Redis snapshot: ${output_file} ($(du -sh "${output_file}" | cut -f1))"
    DBS_PROCESSED=$((DBS_PROCESSED + 1))
  else
    log_error "    Failed to copy Redis RDB file from container."
    DBS_FAILED=$((DBS_FAILED + 1))
    return 1
  fi
}

# Dispatch snapshots by database type.
for entry in "${DATABASES_TO_SNAPSHOT[@]}"; do
  IFS=':' read -r db_type container db_name <<< "$entry"

  if [[ -n "${SERVICE_FILTER}" && "${container}" != *"${SERVICE_FILTER}"* ]]; then
    log_info "  Skipping ${db_type}/${db_name} (does not match filter)"
    DBS_SKIPPED=$((DBS_SKIPPED + 1))
    continue
  fi

  case "${db_type}" in
    postgres) snapshot_postgres "${container}" "${db_name}" || true ;;
    redis)    snapshot_redis    "${container}"              || true ;;
    *)
      log_warn "  Unknown database type: ${db_type} — skipping."
      DBS_SKIPPED=$((DBS_SKIPPED + 1))
      ;;
  esac
done

log_info "Database snapshot summary: ${DBS_PROCESSED} processed, ${DBS_FAILED} failed, ${DBS_SKIPPED} skipped"

# Hard failure: all database snapshots failed.
if [[ "${DBS_FAILED}" -gt 0 && "${DBS_PROCESSED}" -eq 0 && "${DRY_RUN}" == false ]]; then
  die "All database snapshots failed.  Backup cannot proceed."
fi

# =============================================================================
# PHASE 3 — Verify Backup Integrity with Checksums
# =============================================================================
#
# Every artifact generated above has a companion .sha256 file.
# This phase verifies all checksums and ensures no file is empty or corrupt.

log_info ""
log_info "PHASE 3: Verifying backup integrity with checksums..."

VERIFY_ERRORS=0

if [[ "$DRY_RUN" == false ]]; then
  # Verify each SHA256 checksum file.
  while IFS= read -r -d '' checksum_file; do
    local base_file="${checksum_file%.sha256}"
    local filename
    filename=$(basename "$base_file")

    if [[ ! -f "${base_file}" ]]; then
      log_error "  Orphaned checksum file (no data file): ${checksum_file}"
      VERIFY_ERRORS=$((VERIFY_ERRORS + 1))
      continue
    fi

    local dir
    dir=$(dirname "${checksum_file}")
    if (cd "${dir}" && sha256sum -c "$(basename "${checksum_file}")" --status 2>/dev/null); then
      log_ok "  Checksum verified: ${filename} ($(du -sh "${base_file}" | cut -f1))"
    else
      log_error "  Checksum mismatch: ${base_file}"
      VERIFY_ERRORS=$((VERIFY_ERRORS + 1))
    fi
  done < <(find "${BACKUP_RUN_DIR}" -name '*.sha256' -print0)

  # Additional integrity: verify PostgreSQL dumps are valid archives.
  while IFS= read -r -d '' dump_file; do
    if pg_restore -l "${dump_file}" &>/dev/null; then
      local table_count
      table_count=$(pg_restore -l "${dump_file}" 2>/dev/null | grep -c "TABLE DATA" || echo "0")
      log_ok "  PostgreSQL dump valid: $(basename "${dump_file}") (${table_count} table data entries)"
    else
      log_error "  Invalid PostgreSQL dump: ${dump_file}"
      VERIFY_ERRORS=$((VERIFY_ERRORS + 1))
    fi
  done < <(find "${BACKUP_RUN_DIR}/databases" -name '*.dump' -print0 2>/dev/null)

  # Additional integrity: verify Redis RDB magic bytes.
  while IFS= read -r -d '' rdb_file; do
    local magic
    magic=$(xxd -l 5 -p "${rdb_file}" 2>/dev/null || echo "")
    if [[ "${magic}" == "5245444953" ]]; then
      log_ok "  Redis RDB valid: $(basename "${rdb_file}") ($(du -sh "${rdb_file}" | cut -f1))"
    else
      log_error "  Invalid Redis RDB magic bytes: ${rdb_file} (got: ${magic})"
      VERIFY_ERRORS=$((VERIFY_ERRORS + 1))
    fi
  done < <(find "${BACKUP_RUN_DIR}/databases" -name '*.rdb' -print0 2>/dev/null)

  # Total artifact count.
  local total_files
  total_files=$(find "${BACKUP_RUN_DIR}" -type f ! -name '*.sha256' | wc -l)
  local total_size
  total_size=$(du -sh "${BACKUP_RUN_DIR}" 2>/dev/null | cut -f1)

  log_info ""
  log_info "Total backup artifacts: ${total_files} (${total_size})"

  if [[ "${VERIFY_ERRORS}" -gt 0 ]]; then
    log_error "Integrity verification found ${VERIFY_ERRORS} error(s)."
  else
    log_ok "All backup artifacts passed integrity verification."
  fi
else
  log_info "DRY RUN: Would verify all backup artifacts and checksums."
fi

# =============================================================================
# PHASE 4 — Generate Backup Manifest
# =============================================================================
#
# The manifest is a JSON file listing every backup artifact with its metadata:
# path, size, SHA256 checksum, and type.  This is used for:
#   - Automated restore procedures.
#   - Audit trails (prove what was backed up and when).
#   - Incremental backup tooling.

log_info ""
log_info "PHASE 4: Generating backup manifest..."

MANIFEST_FILE="${BACKUP_RUN_DIR}/manifests/backup-manifest.json"

if [[ "$DRY_RUN" == false ]]; then
  # Build the manifest JSON.
  cat > "${MANIFEST_FILE}" <<MANIFEST_BEGIN
{
  "backup_run": "${TIMESTAMP}",
  "hostname": "$(hostname)",
  "server_role": "${SERVER_ROLE:-unknown}",
  "service_filter": "${SERVICE_FILTER:-all}",
  "started_at": "$(date -u -Iseconds)",
  "summary": {
    "volumes_processed": ${VOLUMES_PROCESSED},
    "volumes_failed": ${VOLUMES_FAILED},
    "volumes_skipped": ${VOLUMES_SKIPPED},
    "databases_processed": ${DBS_PROCESSED},
    "databases_failed": ${DBS_FAILED},
    "databases_skipped": ${DBS_SKIPPED},
    "verification_errors": ${VERIFY_ERRORS},
    "warnings": ${WARNINGS},
    "total_size": "$(du -sb "${BACKUP_RUN_DIR}" 2>/dev/null | cut -f1 || echo 0)"
  },
  "artifacts": [
MANIFEST_BEGIN

  # Walk artifacts and add each to the manifest.
  local first=true
  while IFS= read -r -d '' artifact; do
    local rel_path="${artifact#${BACKUP_RUN_DIR}/}"
    local art_size sha

    art_size=$(stat --format=%s "${artifact}" 2>/dev/null || echo 0)
    sha=$(sha256sum "${artifact}" 2>/dev/null | awk '{print $1}' || echo "unknown")

    if [[ "${first}" == true ]]; then
      first=false
    else
      echo "    ," >> "${MANIFEST_FILE}"
    fi

    # Determine artifact type.
    local art_type="unknown"
    case "${rel_path}" in
      volumes/*.tar.gz)  art_type="volume_tarball" ;;
      databases/*.dump)  art_type="postgresql_dump" ;;
      databases/*.rdb)   art_type="redis_rdb" ;;
      manifests/*.json)  art_type="manifest" ;;
    esac

    cat >> "${MANIFEST_FILE}" <<ARTIFACT
    {
      "path": "${rel_path}",
      "type": "${art_type}",
      "size_bytes": ${art_size},
      "sha256": "${sha}"
    }
ARTIFACT
  done < <(find "${BACKUP_RUN_DIR}" -type f ! -name '*.sha256' ! -path '*/manifests/*' -print0)

  # Close the JSON arrays/objects.
  cat >> "${MANIFEST_FILE}" <<MANIFEST_END
  ],
  "completed_at": "$(date -u -Iseconds)",
  "exit_code": 0
}
MANIFEST_END

  sha256sum "${MANIFEST_FILE}" > "${MANIFEST_FILE}.sha256"
  log_ok "Backup manifest written: ${MANIFEST_FILE}"
else
  log_info "DRY RUN: Would generate manifest at ${MANIFEST_FILE}"
fi

# =============================================================================
# FINAL — Determine Exit Code and Report
# =============================================================================

log_info ""
log_info "=============================================="
log_info "PRE-BACKUP HOOK COMPLETE"
log_info "=============================================="
log_info "Staging directory: ${BACKUP_RUN_DIR}"
log_info "Volumes:           ${VOLUMES_PROCESSED} OK, ${VOLUMES_FAILED} failed, ${VOLUMES_SKIPPED} skipped"
log_info "Databases:         ${DBS_PROCESSED} OK, ${DBS_FAILED} failed, ${DBS_SKIPPED} skipped"
log_info "Integrity errors:  ${VERIFY_ERRORS}"
log_info "Warnings:          ${WARNINGS}"
log_info "=============================================="

if [[ "${VOLUMES_FAILED}" -gt 0 || "${DBS_FAILED}" -gt 0 ]] && [[ "${DRY_RUN}" == false ]]; then
  log_error "Backup preparation failed.  Exit code: 2"
  log_info "Staging directory retained at: ${BACKUP_RUN_DIR}"
  log_info "Review the errors above before re-running."
  exit 2
elif [[ "${VERIFY_ERRORS}" -gt 0 ]] && [[ "${DRY_RUN}" == false ]]; then
  log_error "Integrity verification failed.  Exit code: 2"
  log_info "Staging directory retained at: ${BACKUP_RUN_DIR}"
  log_info "Re-run with --dry-run to debug."
  exit 2
elif [[ "${WARNINGS}" -gt 0 ]]; then
  log_warn "Backup preparation completed with ${WARNINGS} warning(s).  Exit code: 1"
  log_info ""
  log_info "NEXT STEP: The backup tool can proceed with the staged data."
  log_info "  rsync -avz ${BACKUP_RUN_DIR}/ user@backup-server:/backups/wheeler/"
  log_info "  restic backup ${BACKUP_RUN_DIR}"
  log_info "  aws s3 sync ${BACKUP_RUN_DIR} s3://wheeler-backups/${TIMESTAMP}/"
  exit 1
else
  log_ok "Backup preparation succeeded.  Exit code: 0"
  log_info ""
  log_info "NEXT STEP: The staging directory is ready.  Proceed with backup:"
  log_info "  rsync -avz ${BACKUP_RUN_DIR}/ user@backup-server:/backups/wheeler/"
  log_info "  restic backup ${BACKUP_RUN_DIR}"
  log_info "  aws s3 sync ${BACKUP_RUN_DIR} s3://wheeler-backups/${TIMESTAMP}/"
  exit 0
fi
