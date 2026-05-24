#!/usr/bin/env bash
# =============================================================================
# Backup Configuration — sourced by all backup/restore scripts
# Server: Hetzner CPX51 — Primary AIOps Orchestrator
# =============================================================================
# RPO (Recovery Point Objective): 24 hours (daily full backups)
# RTO (Recovery Time Objective): 2 hours for database, 1 hour for volumes
# =============================================================================
set -o allexport

# --- Paths -------------------------------------------------------------------
BACKUP_ROOT="/opt/backups"
BACKUP_DATABASE_DIR="${BACKUP_ROOT}/databases"
BACKUP_VOLUME_DIR="${BACKUP_ROOT}/volumes"
BACKUP_MANIFEST_DIR="${BACKUP_ROOT}/manifests"
BACKUP_TEMP_DIR="${BACKUP_ROOT}/.tmp"
LOG_DIR="/opt/logs"
BACKUP_LOG="${LOG_DIR}/backup.log"
RESTORE_LOG="${LOG_DIR}/restore.log"

# --- Retention ---------------------------------------------------------------
RETENTION_DAYS=7
RETENTION_WEEKS=4
RETENTION_MONTHS=3
RETENTION_DAILY_COUNT=7
RETENTION_WEEKLY_COUNT=4
RETENTION_MONTHLY_COUNT=3

# --- Databases (Hetzner CPX51) -----------------------------------------------
DATABASES=("prediction_radar" "ravynai" "healthchecks" "superset")

# --- Docker Volumes to back up (Hetzner CPX51) --------------------------------
# Format: "volume_name" or "namespace/volume_name:label"
# List only non-ephemeral volumes that contain persistent data.
# Cache/tmp volumes are excluded.
VOLUMES_TO_BACKUP=(
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

# --- Volumes to SKIP (caches, tmp, ephemeral) ---------------------------------
VOLUMES_SKIP=(
    "prediction-radar_redis-data"
    "ravynai_redis-data"
)

# --- PostgreSQL Connection (Hetzner) ------------------------------------------
# IMPORTANT: Set these environment variables before running scripts:
#   PGHOST, PGPORT, PGUSER, PGPASSWORD, PGSSLMODE
# These can also be set in a .pgpass file or via a .env file sourced here.
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGSSLMODE="${PGSSLMODE:-prefer}"

# --- Healthchecks.io ----------------------------------------------------------
# Ping URL for backup success/failure notifications.
# Format: https://healthchecks.wheeler.ai/ping/<UUID>
# Set HEALTHCHECK_UUID or HEALTHCHECK_URL in environment or .env
HEALTHCHECK_BASE="${HEALTHCHECK_URL:-https://healthchecks.wheeler.ai/ping}"
HEALTHCHECK_UUID="${HEALTHCHECK_UUID:-}"
if [ -n "$HEALTHCHECK_UUID" ]; then
    HEALTHCHECK_URL="${HEALTHCHECK_BASE}/${HEALTHCHECK_UUID}"
fi

# --- Remote Backup Target -----------------------------------------------------
# Set these to rsync backups to a remote archive server.
REMOTE_BACKUP_HOST="${REMOTE_BACKUP_HOST:-}"
REMOTE_BACKUP_PATH="${REMOTE_BACKUP_PATH:-/backups/wheeler-aiops}"
REMOTE_BACKUP_USER="${REMOTE_BACKUP_USER:-backup}"
REMOTE_SSH_PORT="${REMOTE_SSH_PORT:-22}"

# --- Docker Compose paths (for config backups) --------------------------------
COMPOSE_DIRS_HETZNER=(
    "/root/infrastructure/hetzner/compose"
    "/opt/compose"
)

# --- Tooling ------------------------------------------------------------------
PG_DUMP="$(command -v pg_dump 2>/dev/null || echo /usr/lib/postgresql/*/bin/pg_dump)"
PG_RESTORE="$(command -v pg_restore 2>/dev/null || echo /usr/lib/postgresql/*/bin/pg_restore)"
PSQL="$(command -v psql 2>/dev/null || echo /usr/lib/postgresql/*/bin/psql)"

# --- Lock file ----------------------------------------------------------------
BACKUP_LOCK_FILE="/var/run/aiops-backup.lock"

set +o allexport
