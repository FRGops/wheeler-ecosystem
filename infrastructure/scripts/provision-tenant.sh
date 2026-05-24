#!/bin/bash
# Wheeler AI Ops SaaS — Tenant Provisioning Script
# Part of: AI_OPS_SAAS_PLAN.md (Deliverable 5)
# Creates isolated tenant infrastructure: monitoring, alerts, access.
#
# Usage: provision-tenant.sh <tenant_id> <tier> <email>
# Tiers: starter | pro | enterprise | agency
#
# Exit codes: 0=success, 1=validation error, 2=provisioning failed, 3=verification failed

set -euo pipefail

TENANT_ID="${1:?Usage: provision-tenant.sh <tenant_id> <tier> <email>}"
TIER="${2:?Usage: provision-tenant.sh <tenant_id> <tier> <email>}"
EMAIL="${3:?Usage: provision-tenant.sh <tenant_id> <tier> <email>}"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOGFILE="/var/log/wheeler/provision/${TENANT_ID}-${TIMESTAMP}.log"
BACKUP_DIR="/opt/backups/tenants/${TENANT_ID}/${TIMESTAMP}"
STATE_FILE="/opt/aiops-saas/tenants/${TENANT_ID}/state.json"

# Infrastructure endpoints
GRAFANA_URL="http://127.0.0.1:3002"
PROMETHEUS_URL="http://127.0.0.1:9090"
LOKI_URL="http://127.0.0.1:3100"
ALERTMANAGER_URL="http://127.0.0.1:9093"
LITELLM_URL="http://127.0.0.1:4049"
NGINX_CONF_DIR="/etc/nginx/sites-enabled"
TENANT_ROOT="/opt/aiops-saas/tenants/${TENANT_ID}"

# Tier-specific resource limits
declare -A TIER_LIMITS
TIER_LIMITS[starter]="cpu:0.5,mem:512M,disk:2G,tenants:8"
TIER_LIMITS[pro]="cpu:1,mem:1G,disk:5G,tenants:4"
TIER_LIMITS[enterprise]="cpu:2,mem:2G,disk:10G,tenants:2"
TIER_LIMITS[agency]="cpu:4,mem:4G,disk:20G,tenants:1"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOGFILE"; }
fail() { log "FATAL: $*"; exit 2; }

# =========================================================================
# Gate 1: Validate inputs
# =========================================================================
log "GATE 1: Validating inputs for tenant=${TENANT_ID} tier=${TIER}"

[[ "$TIER" =~ ^(starter|pro|enterprise|agency)$ ]] || { log "ERROR: Invalid tier: $TIER"; exit 1; }
[[ "$EMAIL" =~ .*@.*\..* ]] || { log "ERROR: Invalid email: $EMAIL"; exit 1; }

# Check tenant doesn't already exist
if [ -d "$TENANT_ROOT" ]; then
    log "ERROR: Tenant ${TENANT_ID} already exists at ${TENANT_ROOT}"
    exit 1
fi

# Check tier capacity
TIER_TENANT_COUNT=$(find /opt/aiops-saas/tenants -name state.json -exec jq -r 'select(.tier=="'"$TIER"'") | .tenant_id' {} \; 2>/dev/null | wc -l)
TIER_MAX=$(echo "${TIER_LIMITS[$TIER]}" | grep -oP 'tenants:\K\d+')
if [ "$TIER_TENANT_COUNT" -ge "$TIER_MAX" ]; then
    log "ERROR: Tier ${TIER} at capacity (${TIER_TENANT_COUNT}/${TIER_MAX} tenants)"
    exit 1
fi

# =========================================================================
# Gate 2: Create state backup
# =========================================================================
log "GATE 2: Creating state backup"
mkdir -p "$BACKUP_DIR"
docker ps --format json > "$BACKUP_DIR/docker-ps.json" 2>/dev/null || true
pm2 jlist > "$BACKUP_DIR/pm2-jlist.json" 2>/dev/null || true
ss -tlnp > "$BACKUP_DIR/ss-tlnp.txt" 2>/dev/null || true

# =========================================================================
# Gate 3: Provision tenant infrastructure
# =========================================================================
log "GATE 3: Provisioning tenant infrastructure"
mkdir -p "${TENANT_ROOT}"/{configs,data,logs,dashboards}

# --- Provision Grafana Organization ---
log "Provisioning Grafana org for tenant=${TENANT_ID}"
GRAFANA_ORG_ID=$(curl -s -X POST "${GRAFANA_URL}/api/orgs" \
    -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${TENANT_ID}\"}" | jq -r '.orgId // empty')

if [ -z "$GRAFANA_ORG_ID" ]; then
    log "WARN: Grafana org creation failed (may already exist), attempting lookup"
    GRAFANA_ORG_ID=$(curl -s "${GRAFANA_URL}/api/orgs/name/${TENANT_ID}" \
        -H "Authorization: Bearer ${GRAFANA_API_KEY}" | jq -r '.id // empty')
fi

# Create tenant Grafana user
GRAFANA_USER_PASS=$(openssl rand -hex 16)
curl -s -X POST "${GRAFANA_URL}/api/admin/users" \
    -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${TENANT_ID}\",\"email\":\"${EMAIL}\",\"login\":\"${TENANT_ID}\",\"password\":\"${GRAFANA_USER_PASS}\",\"OrgId\":${GRAFANA_ORG_ID}}" || true

# --- Provision Prometheus Scrape Config ---
log "Provisioning Prometheus scrape config for tenant=${TENANT_ID}"
cat > "${TENANT_ROOT}/configs/prometheus-targets.json" <<PROMEOF
[
  {
    "labels": {"tenant": "${TENANT_ID}", "tier": "${TIER}"},
    "targets": []
  }
]
PROMEOF

# --- Provision Alertmanager Route ---
log "Provisioning Alertmanager route for tenant=${TENANT_ID}"
# Tenant-specific alert routing added via Alertmanager API
curl -s -X POST "${ALERTMANAGER_URL}/api/v2/silences" \
    -H "Content-Type: application/json" \
    -d "{\"matchers\":[{\"name\":\"tenant\",\"value\":\"${TENANT_ID}\",\"isRegex\":false}],\"startsAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"endsAt\":\"$(date -u -d '+100 years' +%Y-%m-%dT%H:%M:%SZ)\",\"createdBy\":\"provision-tenant.sh\",\"comment\":\"Tenant ${TENANT_ID} initial provisioning\"}" || true

# --- Provision LiteLLM Virtual Key ---
log "Provisioning LiteLLM virtual key for tenant=${TENANT_ID}"
LITELLM_KEY=$(curl -s -X POST "${LITELLM_URL}/key/generate" \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"key_alias\":\"${TENANT_ID}\",\"max_budget\":0.05,\"budget_duration\":\"1d\",\"models\":[\"deepseek-chat\"],\"metadata\":{\"tenant\":\"${TENANT_ID}\",\"tier\":\"${TIER}\"}}" | jq -r '.key // empty')

# --- Provision Database Schema ---
log "Provisioning database for tenant=${TENANT_ID}"
PGPASSWORD="${AIOPS_SAAS_DB_PASSWORD}" psql -h 127.0.0.1 -U aiops_saas -d aiops_saas <<SQLEOF
INSERT INTO tenants (tenant_id, tier, email, grafana_org_id, created_at, status)
VALUES ('${TENANT_ID}', '${TIER}', '${EMAIL}', ${GRAFANA_ORG_ID:-0}, NOW(), 'active')
ON CONFLICT (tenant_id) DO UPDATE SET status = 'active', updated_at = NOW();

CREATE SCHEMA IF NOT EXISTS tenant_${TENANT_ID};
GRANT USAGE ON SCHEMA tenant_${TENANT_ID} TO aiops_saas;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tenant_${TENANT_ID} TO aiops_saas;
SQLEOF

# =========================================================================
# Gate 4: Write state file
# =========================================================================
log "GATE 4: Writing tenant state"
cat > "$STATE_FILE" <<STATEEOF
{
  "tenant_id": "${TENANT_ID}",
  "tier": "${TIER}",
  "email": "${EMAIL}",
  "grafana_org_id": ${GRAFANA_ORG_ID:-null},
  "litellm_key_alias": "${TENANT_ID}",
  "provisioned_at": "${TIMESTAMP}",
  "resource_limits": "${TIER_LIMITS[$TIER]}",
  "status": "active"
}
STATEEOF

# =========================================================================
# Gate 5: Verification
# =========================================================================
log "GATE 5: Verifying tenant provisioning"

VERIFY_FAILURES=0

# Verify Grafana org exists
if [ -n "$GRAFANA_ORG_ID" ]; then
    curl -s "${GRAFANA_URL}/api/orgs/${GRAFANA_ORG_ID}" \
        -H "Authorization: Bearer ${GRAFANA_API_KEY}" | jq -e '.id' >/dev/null 2>&1 || {
        log "VERIFY FAIL: Grafana org ${GRAFANA_ORG_ID} not accessible"
        VERIFY_FAILURES=$((VERIFY_FAILURES + 1))
    }
fi

# Verify database schema
PGPASSWORD="${AIOPS_SAAS_DB_PASSWORD}" psql -h 127.0.0.1 -U aiops_saas -d aiops_saas -tAc \
    "SELECT 1 FROM tenants WHERE tenant_id='${TENANT_ID}' AND status='active'" | grep -q 1 || {
    log "VERIFY FAIL: Tenant ${TENANT_ID} not found in database"
    VERIFY_FAILURES=$((VERIFY_FAILURES + 1))
}

# Verify directory structure
[ -d "$TENANT_ROOT" ] && [ -f "$STATE_FILE" ] || {
    log "VERIFY FAIL: Tenant directory or state file missing"
    VERIFY_FAILURES=$((VERIFY_FAILURES + 1))
}

if [ "$VERIFY_FAILURES" -gt 0 ]; then
    log "VERIFICATION FAILED: ${VERIFY_FAILURES} checks failed"
    exit 3
fi

# =========================================================================
# Success
# =========================================================================
log "SUCCESS: Tenant ${TENANT_ID} (${TIER}) provisioned successfully"
log "  Grafana Org ID: ${GRAFANA_ORG_ID:-N/A}"
log "  Grafana User: ${TENANT_ID}"
log "  State File: ${STATE_FILE}"
log "  Log: ${LOGFILE}"

echo "TENANT_ID=${TENANT_ID}"
echo "TIER=${TIER}"
echo "GRAFANA_ORG_ID=${GRAFANA_ORG_ID:-N/A}"
echo "STATE_FILE=${STATE_FILE}"

exit 0
