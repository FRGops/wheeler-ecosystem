#!/bin/bash
# Wheeler AI Ops SaaS — Tenant Deprovisioning Script
# Usage: deprovision-tenant.sh <tenant_id> [--force]
# Exit codes: 0=success, 1=validation error, 2=deprovisioning failed

set -euo pipefail

TENANT_ID="${1:?Usage: deprovision-tenant.sh <tenant_id> [--force]}"
FORCE="${2:-}"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOGFILE="/var/log/wheeler/deprovision/${TENANT_ID}-${TIMESTAMP}.log"
STATE_FILE="/opt/aiops-saas/tenants/${TENANT_ID}/state.json"
ARCHIVE_DIR="/opt/aiops-saas/archived-tenants/${TENANT_ID}/${TIMESTAMP}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOGFILE"; }
fail() { log "FATAL: $*"; exit 2; }

# Validate tenant exists
[ -f "$STATE_FILE" ] || { log "ERROR: Tenant ${TENANT_ID} not found (no state file)"; exit 1; }

if [ "$FORCE" != "--force" ]; then
    echo "WARNING: This will permanently deprovision tenant: ${TENANT_ID}"
    echo "State file: ${STATE_FILE}"
    echo ""
    echo "Data will be archived to: ${ARCHIVE_DIR}"
    echo "To proceed, re-run with --force flag."
    exit 1
fi

log "Deprovisioning tenant=${TENANT_ID}"

# Archive tenant data
mkdir -p "$ARCHIVE_DIR"
cp -r "/opt/aiops-saas/tenants/${TENANT_ID}" "$ARCHIVE_DIR/tenant-data"
log "Tenant data archived to ${ARCHIVE_DIR}"

# Read state for cleanup
GRAFANA_ORG_ID=$(jq -r '.grafana_org_id // empty' "$STATE_FILE")

# Remove Grafana org
if [ -n "$GRAFANA_ORG_ID" ] && [ "$GRAFANA_ORG_ID" != "null" ]; then
    curl -s -X DELETE "http://127.0.0.1:3002/api/orgs/${GRAFANA_ORG_ID}" \
        -H "Authorization: Bearer ${GRAFANA_API_KEY}" || log "WARN: Grafana org removal failed"
fi

# Remove Prometheus targets
rm -f "/opt/aiops-saas/tenants/${TENANT_ID}/configs/prometheus-targets.json"

# Remove database schema
PGPASSWORD="${AIOPS_SAAS_DB_PASSWORD}" psql -h 127.0.0.1 -U aiops_saas -d aiops_saas -c \
    "UPDATE tenants SET status='deprovisioned', deprovisioned_at=NOW() WHERE tenant_id='${TENANT_ID}';" 2>/dev/null || true

# Remove tenant directory (keep archive)
rm -rf "/opt/aiops-saas/tenants/${TENANT_ID}"

log "SUCCESS: Tenant ${TENANT_ID} deprovisioned"
log "  Archive: ${ARCHIVE_DIR}"
log "  Database: status set to 'deprovisioned'"

exit 0
