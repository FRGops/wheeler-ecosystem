# PHASE-14: Drift Detection & Dashboard

**Purpose:** Establish post-deployment baseline monitoring. Detect configuration drift,
container version drift, endpoint drift, and network drift. Update the deployment
dashboard and schedule recurring drift checks.

**Prerequisites:** PHASE-13 production deployment complete.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

DRIFT_LOG="/var/log/wheeler/repo-router/drift/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
DRIFT_BASELINE_DIR="/var/log/wheeler/repo-router/baselines"
mkdir -p "$(dirname "${DRIFT_LOG}")" "${DRIFT_BASELINE_DIR}"
exec > >(tee -a "${DRIFT_LOG}") 2>&1

echo "=== PHASE-14: Drift Detection & Dashboard for ${SERVICE_NAME} ==="
echo "Establishing baseline at: $(date -u)"
```

## 2. Capture Configuration Baseline

```bash
echo ""
echo "=== Baseline 1: Configuration Snapshot ==="
BASELINE_FILE="${DRIFT_BASELINE_DIR}/${SERVICE_NAME}-baseline-$(date -u +%Y%m%dT%H%M%S).json"

# Collect current config state
CONFIG_SNAPSHOT=$(mktemp)

# Docker config snapshot
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SERVICE_NAME}"; then
    {
        echo "--- Docker Container Config ---"
        docker inspect "${SERVICE_NAME}" 2>/dev/null | jq '.[0].Config'
        echo ""
        echo "--- Docker Host Config ---"
        docker inspect "${SERVICE_NAME}" 2>/dev/null | jq '.[0].HostConfig | {NetworkMode, RestartPolicy, Privileged, CapDrop, ReadonlyRootfs, Memory, NanoCpus, PortBindings: .PortBindings}'
        echo ""
        echo "--- Docker Network Settings ---"
        docker inspect "${SERVICE_NAME}" 2>/dev/null | jq '.[0].NetworkSettings.Networks'
        echo ""
        echo "--- Docker Labels ---"
        docker inspect "${SERVICE_NAME}" 2>/dev/null | jq '.[0].Config.Labels'
    } > "${CONFIG_SNAPSHOT}"
fi

# PM2 config snapshot
if pm2 jlist 2>/dev/null | jq -e ".[] | select(.name == \"${SERVICE_NAME}\")" >/dev/null 2>&1; then
    {
        echo "--- PM2 Config ---"
        pm2 jlist 2>/dev/null | jq ".[] | select(.name == \"${SERVICE_NAME}\") | {name, pm2_env: {status, exec_mode, max_memory_restart, autorestart, watch, instances}}"
    } >> "${CONFIG_SNAPSHOT}"
fi

# Copy to baseline directory
cp "${CONFIG_SNAPSHOT}" "${BASELINE_FILE}"
rm -f "${CONFIG_SNAPSHOT}"
echo "Baseline config captured: ${BASELINE_FILE}"
```

## 3. Capture Endpoint Baseline

```bash
echo ""
echo "=== Baseline 2: Endpoint Response Baseline ==="
ENDPOINT_BASELINE="${DRIFT_BASELINE_DIR}/${SERVICE_NAME}-endpoints-$(date -u +%Y%m%dT%H%M%S).json"

endpoint_baseline_data() {
    ENDPOINTS=("/health" "/healthz" "/ready" "/api/health" "/metrics" "/" "/api/v1")
    echo "{"
    echo "  \"service\": \"${SERVICE_NAME}\","
    echo "  \"captured_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"endpoints\": ["

    FIRST=true
    for endpoint in "${ENDPOINTS[@]}"; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
          "http://127.0.0.1:8088${endpoint}" 2>/dev/null || echo "000")
        CONTENT_TYPE=$(curl -s -I --max-time 5 "http://127.0.0.1:8088${endpoint}" 2>/dev/null | \
          grep -i 'content-type:' | sed 's/.*: //' | tr -d '\r' || echo "unknown")
        RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 \
          "http://127.0.0.1:8088${endpoint}" 2>/dev/null || echo "0")

        if [[ "${HTTP_CODE}" != "000" ]]; then
            [[ "${FIRST}" != true ]] && echo ","
            FIRST=false
            echo -n "    {"
            echo -n "\"path\": \"${endpoint}\", "
            echo -n "\"status\": ${HTTP_CODE}, "
            echo -n "\"content_type\": \"${CONTENT_TYPE}\", "
            echo -n "\"response_time\": ${RESPONSE_TIME}"
            echo -n "}"
        fi
    done
    echo ""
    echo "  ]"
    echo "}"
}

endpoint_baseline_data > "${ENDPOINT_BASELINE}"
echo "Endpoint baseline captured: ${ENDPOINT_BASELINE}"
```

## 4. Capture Container Image Baseline

```bash
echo ""
echo "=== Baseline 3: Container Image Baseline ==="
IMAGE_BASELINE="${DRIFT_BASELINE_DIR}/${SERVICE_NAME}-images-$(date -u +%Y%m%dT%H%M%S).json"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SERVICE_NAME}"; then
    docker inspect "${SERVICE_NAME}" --format '{{json .Config.Image}}' > /tmp/${SERVICE_NAME}-image.txt
    docker inspect "${SERVICE_NAME}" --format '{{json .Id}}' >> /tmp/${SERVICE_NAME}-image.txt
    docker inspect "${SERVICE_NAME}" --format '{{.Created}}' >> /tmp/${SERVICE_NAME}-image.txt
    docker image inspect "$(docker inspect "${SERVICE_NAME}" --format '{{.Config.Image}}')" \
      --format '{{.CreatedBy}}' 2>/dev/null >> /tmp/${SERVICE_NAME}-image.txt || true
fi

if pm2 jlist 2>/dev/null | jq -e ".[] | select(.name == \"${SERVICE_NAME}\")" >/dev/null 2>&1; then
    pm2 jlist 2>/dev/null | jq ".[] | select(.name == \"${SERVICE_NAME}\") | {pid, pm_uptime, exec_interpreter, node_args}" \
      > /tmp/${SERVICE_NAME}-pm2-baseline.json
fi

echo "Image baseline captured."
```

## 5. Schedule Drift Detection Cron Job

```bash
echo ""
echo "=== Schedule Recurring Drift Detection ==="

DRIFT_SCRIPT="/root/deployment-engine/repo-router/scripts/drift-check.sh"
DRIFT_CRON="/etc/cron.d/wheeler-drift-${SERVICE_NAME}"

# Create drift detection script if it doesn't exist
mkdir -p "$(dirname "${DRIFT_SCRIPT}")"
if [[ ! -f "${DRIFT_SCRIPT}" ]]; then
    cat > "${DRIFT_SCRIPT}" <<-'DRIFTSCRIPT'
#!/usr/bin/env bash
# Drift Detection Runner — compares current state vs baseline
set -euo pipefail
SERVICE_NAME="${1:?Usage: $0 <service-name>}"
BASELINE_DIR="/var/log/wheeler/repo-router/baselines"
DRIFT_LOG="/var/log/wheeler/repo-router/drift/${SERVICE_NAME}-drift-$(date +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${DRIFT_LOG}")"

# Find latest baseline
LATEST_CONFIG=$(ls -t ${BASELINE_DIR}/${SERVICE_NAME}-baseline-*.json 2>/dev/null | head -1)
LATEST_ENDPOINTS=$(ls -t ${BASELINE_DIR}/${SERVICE_NAME}-endpoints-*.json 2>/dev/null | head -1)

if [[ -z "${LATEST_CONFIG}" ]]; then
    echo "No baseline found for ${SERVICE_NAME}. Run PHASE-14 first." | tee "${DRIFT_LOG}"
    exit 0
fi

# Compare Docker config
if command -v docker &>/dev/null; then
    CURRENT_IMAGE=$(docker inspect "${SERVICE_NAME}" --format '{{.Config.Image}}' 2>/dev/null || echo "not-found")
    BASELINE_IMAGE=$(grep -o '"Image":"[^"]*"' "${LATEST_CONFIG}" 2>/dev/null | head -1 | sed 's/"Image":"//;s/"//')
    if [[ -n "${BASELINE_IMAGE}" && "${CURRENT_IMAGE}" != "${BASELINE_IMAGE}" ]]; then
        echo "DRIFT: Image changed from ${BASELINE_IMAGE} to ${CURRENT_IMAGE}" >> "${DRIFT_LOG}"
    fi
fi

# Compare endpoint responses
if [[ -f "${LATEST_ENDPOINTS}" && -n "${SERVICE_NAME}" ]]; then
    for endpoint in "/health" "/"; do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8088${endpoint}" 2>/dev/null || echo "000")
        BASELINE_STATUS=$(jq -r --arg ep "${endpoint}" '.endpoints[] | select(.path==$ep) | .status' "${LATEST_ENDPOINTS}" 2>/dev/null || echo "000")
        if [[ -n "${BASELINE_STATUS}" && "${STATUS}" != "${BASELINE_STATUS}" ]]; then
            echo "DRIFT: ${endpoint} status ${BASELINE_STATUS} -> ${STATUS}" >> "${DRIFT_LOG}"
        fi
    done
fi

if [[ -s "${DRIFT_LOG}" ]]; then
    echo "Drift detected for ${SERVICE_NAME}. See: ${DRIFT_LOG}"
else
    echo "No drift detected for ${SERVICE_NAME} at $(date)." >> "${DRIFT_LOG}"
fi
DRIFTSCRIPT
    chmod +x "${DRIFT_SCRIPT}"
    echo "Drift detection script created: ${DRIFT_SCRIPT}"
fi

# Install cron job (every 6 hours)
if [[ ! -f "${DRIFT_CRON}" ]]; then
    echo "0 */6 * * * root ${DRIFT_SCRIPT} ${SERVICE_NAME}" > "${DRIFT_CRON}"
    chmod 644 "${DRIFT_CRON}"
    echo "Cron installed: ${DRIFT_CRON} (runs every 6 hours)"
fi
```

## 6. Update Deployment Dashboard

```bash
echo ""
echo "=== Update Deployment Dashboard ==="

DASHBOARD_DIR="/opt/wheeler/configs/dashboards"
mkdir -p "${DASHBOARD_DIR}"

DASHBOARD_FILE="${DASHBOARD_DIR}/${SERVICE_NAME}-deployment.json"

# Record deployment for dashboard consumption
cat > "${DASHBOARD_FILE}" <<-EOF
{
  "service": "${SERVICE_NAME}",
  "deploy_type": "${DEPLOY_TYPE}",
  "repo_path": "${REPO_PATH}",
  "latest_deploy": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "baseline_config": "$(basename "${BASELINE_FILE}")",
  "baseline_endpoints": "$(basename "${ENDPOINT_BASELINE}")",
  "status": "deployed",
  "drift_checks_enabled": true,
  "drift_cron": "${DRIFT_CRON}",
  "monitored": true
}
EOF

echo "Dashboard entry: ${DASHBOARD_FILE}"

# Refresh the main deployment dashboard index
MASTER_DASHBOARD="/opt/wheeler/configs/dashboards/index.json"
if [[ -f "${MASTER_DASHBOARD}" ]]; then
    # Add/update this service in the index
    jq --arg svc "${SERVICE_NAME}" --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.[$svc] = {"last_deploy": $time, "status": "deployed"}' \
      "${MASTER_DASHBOARD}" > "${MASTER_DASHBOARD}.tmp" && \
      mv "${MASTER_DASHBOARD}.tmp" "${MASTER_DASHBOARD}"
    echo "Master dashboard index updated."
else
    echo "{\"${SERVICE_NAME}\": {\"last_deploy\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"status\": \"deployed\"}}" \
      > "${MASTER_DASHBOARD}"
    echo "Master dashboard index created."
fi
```

## 7. Final Verification & Report

```bash
echo ""
echo "=== Final Verification ==="

# Quick-smoke check all Wheeler services to ensure no regressions
if [[ -x "/root/scripts/smoke-test-all.sh" ]]; then
    echo "Running full ecosystem smoke test..."
    bash "/root/scripts/smoke-test-all.sh" 2>&1 | tail -10 || true
fi

# Record the deployment as complete in the repo-router pipeline
PIPELINE_STATUS="/var/log/wheeler/repo-router/pipeline/${SERVICE_NAME}-complete.json"
mkdir -p "$(dirname "${PIPELINE_STATUS}")"

cat > "${PIPELINE_STATUS}" <<-EOF
{
  "service": "${SERVICE_NAME}",
  "pipeline": "repo-router",
  "phases_completed": [
    "PHASE-01: Intake & Classification",
    "PHASE-02: Repo Discovery & Verification",
    "PHASE-03: Dependency Mapping",
    "PHASE-04: Architecture Review",
    "PHASE-05: Security Scan",
    "PHASE-06: Risk Scoring",
    "PHASE-07: Sandbox Deployment",
    "PHASE-08: Integration Testing",
    "PHASE-09: Observability Setup",
    "PHASE-10: Zero-Trust Validation",
    "PHASE-11: Staging Promotion",
    "PHASE-12: Production Readiness",
    "PHASE-13: Production Deployment & Rollback",
    "PHASE-14: Drift Detection & Dashboard"
  ],
  "status": "operational",
  "drift_monitoring": "active",
  "completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo ""
echo "Pipeline completion record: ${PIPELINE_STATUS}"
echo ""
echo "=== PHASE-14 COMPLETE: ${SERVICE_NAME} fully deployed and baseline monitored ==="
echo ""
echo "Summary:"
echo "  Config baseline:   ${BASELINE_FILE}"
echo "  Endpoint baseline: ${ENDPOINT_BASELINE}"
echo "  Drift detection:   ${DRIFT_SCRIPT} (cron: ${DRIFT_CRON})"
echo "  Dashboard:          ${DASHBOARD_FILE}"
echo "  Pipeline record:    ${PIPELINE_STATUS}"
echo ""
echo "The Wheeler Repo Router pipeline has completed all 14 phases for ${SERVICE_NAME}."
```
