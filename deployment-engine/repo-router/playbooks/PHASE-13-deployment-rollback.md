# PHASE-13: Production Deployment & Rollback

**Purpose:** Execute the production deployment using the Wheeler Deployment Engine,
run post-deploy health verification, and maintain rollback readiness.
The deployment engine handles the full lifecycle: preflight -> backup -> deploy -> healthcheck -> rollback-on-fail.

**Prerequisites:** PHASE-12 readiness report with `ready: true`.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"
VERSION="${2:-latest}"

DEPLOY_LOG="/var/log/wheeler/repo-router/deploy/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${DEPLOY_LOG}")"
exec > >(tee -a "${DEPLOY_LOG}") 2>&1

echo "=== PHASE-13: Production Deployment for ${SERVICE_NAME} ==="
echo "Version: ${VERSION} | Type: ${DEPLOY_TYPE} | Repo: ${REPO_PATH}"
echo "Start time: $(date -u)"
```

## 2. Final Pre-Deployment Confirmation

```bash
echo ""
echo "=== Pre-Deployment Confirmation ==="

# Verify readiness report
READY_REPORT="/var/log/wheeler/repo-router/readiness/${SERVICE_NAME}-readiness.json"
if [[ -f "${READY_REPORT}" ]]; then
    READY=$(jq -r '.ready // false' "${READY_REPORT}")
    if [[ "${READY}" != "true" ]]; then
        echo "FATAL: Readiness report says NOT ready. Aborting."
        echo "  Resolve failures in ${READY_REPORT} and re-run PHASE-12."
        exit 1
    fi
    echo "[PASS] Readiness report confirms GO."
fi

# Confirm with operator (unless --force)
if [[ "$*" != *"--force"* ]]; then
    echo ""
    echo "Ready to deploy ${SERVICE_NAME} (${VERSION}) to PRODUCTION."
    echo "Type 'yes' to continue or 'no' to abort:"
    read -r CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo "Deployment aborted by user."
        exit 0
    fi
fi
```

## 3. Execute Production Deployment

```bash
echo ""
echo "=== Production Deployment ==="

DEPLOY_ENGINE="/root/deployment-engine"
DEPLOY_START=$(date +%s)

case "${DEPLOY_TYPE}" in
    docker)
        echo "Using deploy-docker-service.sh..."
        if [[ "${VERSION}" == "latest" ]]; then
            VERSION="$(date -u +%Y.%m.%d)-${SERVICE_NAME}"
        fi

        bash "${DEPLOY_ENGINE}/deploy-docker-service.sh" \
          "${SERVICE_NAME}" "production" "${VERSION}" 2>&1
        DEPLOY_EXIT=$?
        ;;

    pm2)
        echo "Using deploy-pm2-service.sh..."
        bash "${DEPLOY_ENGINE}/deploy-pm2-service.sh" \
          "${SERVICE_NAME}" "production" 2>&1
        DEPLOY_EXIT=$?
        ;;

    static)
        echo "Using deploy-service.sh (static)..."
        bash "${DEPLOY_ENGINE}/deploy-service.sh" \
          "${SERVICE_NAME}" "production" "${VERSION}" 2>&1
        DEPLOY_EXIT=$?
        ;;

    *)
        echo "Using generic deploy-service.sh..."
        bash "${DEPLOY_ENGINE}/deploy-service.sh" \
          "${SERVICE_NAME}" "production" "${VERSION}" 2>&1
        DEPLOY_EXIT=$?
        ;;
esac

DEPLOY_END=$(date +%s)
DEPLOY_DURATION=$((DEPLOY_END - DEPLOY_START))
echo "Deployment duration: ${DEPLOY_DURATION}s"
echo "Deployment exit code: ${DEPLOY_EXIT}"

# Interpret deployment engine exit codes
# 0 = success, 1 = preflight error, 2 = deploy failed, 3 = rollback succeeded, 4 = rollback failed, 5 = healthcheck failed
case "${DEPLOY_EXIT}" in
    0)  echo "Deployment succeeded." ;;
    1)  echo "Preflight validation failed. Check /var/log/wheeler/ for details." ;;
    2)  echo "Deployment failed (no rollback attempted)." ;;
    3)  echo "Deployment failed but rollback succeeded. Service is at previous state." ;;
    4)  echo "CRITICAL: Deployment failed AND rollback failed! Manual intervention required!" ;;
    5)  echo "Health check failed after deployment. Service deployed but may be unhealthy." ;;
esac
```

## 4. Post-Deploy Health Verification

```bash
echo ""
echo "=== Post-Deploy Health Verification ==="

if [[ "${DEPLOY_EXIT}" -eq 0 || "${DEPLOY_EXIT}" -eq 5 ]]; then
    # Run full verification
    if [[ -x "${DEPLOY_ENGINE}/verify-deployment.sh" ]]; then
        bash "${DEPLOY_ENGINE}/verify-deployment.sh" \
          "${SERVICE_NAME}" "production" --json 2>&1 | tail -20
        VERIFY_EXIT=$?
        if [[ "${VERIFY_EXIT}" -eq 0 ]]; then
            echo "[PASS] Production verification passed."
        else
            echo "[WARN] Production verification reported issues (exit ${VERIFY_EXIT})."
        fi
    fi

    # Run post-deploy health check window
    if [[ -x "${DEPLOY_ENGINE}/post-deploy-healthcheck.sh" ]]; then
        bash "${DEPLOY_ENGINE}/post-deploy-healthcheck.sh" \
          "${SERVICE_NAME}" "production" --monitor-window 30 --timeout 60 2>&1 | tail -15
    fi
fi
```

## 5. Rollback Procedure (if needed)

```bash
echo ""
echo "=== Rollback Procedure ==="

if [[ "${DEPLOY_EXIT}" -ne 0 && "${DEPLOY_EXIT}" -ne 5 ]]; then
    echo ""
    echo "** DEPLOYMENT FAILED (exit ${DEPLOY_EXIT}). Initiating rollback. **"

    ROLLBACK_SCRIPT="${DEPLOY_ENGINE}/rollback-deployment.sh"
    if [[ -x "${ROLLBACK_SCRIPT}" ]]; then
        bash "${ROLLBACK_SCRIPT}" "${SERVICE_NAME}" "production" 2>&1 | tail -20
        ROLLBACK_EXIT=$?

        if [[ "${ROLLBACK_EXIT}" -eq 0 ]]; then
            echo "[PASS] Rollback succeeded. Service restored to previous version."
        else
            echo "FATAL: Rollback failed (exit ${ROLLBACK_EXIT}). Manual intervention required!"
            echo "  Emergency rollback steps:"
            echo "  1) docker stop ${SERVICE_NAME}"
            echo "  2) docker start ${SERVICE_NAME}-previous"
            echo "  3) pm2 delete ${SERVICE_NAME} && pm2 start ${SERVICE_NAME}-backup"
            echo "  4) Notify on-call engineer immediately."
        fi
    fi
fi
```

## 6. Deployment Record

```bash
echo ""
echo "=== Recording Deployment ==="

DEPLOY_RECORD="/var/log/wheeler/repo-router/deploy/${SERVICE_NAME}-deploy-record.json"
cat > "${DEPLOY_RECORD}" <<-EOF
{
  "service": "${SERVICE_NAME}",
  "version": "${VERSION}",
  "deploy_type": "${DEPLOY_TYPE}",
  "exit_code": ${DEPLOY_EXIT},
  "duration_seconds": ${DEPLOY_DURATION},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deploy_log": "${DEPLOY_LOG}",
  "status": "$( [[ ${DEPLOY_EXIT} -eq 0 ]] && echo 'success' || echo 'failed' )"
}
EOF

echo "Deployment record: ${DEPLOY_RECORD}"
echo ""
echo "PHASE-13 COMPLETE: ${SERVICE_NAME} production deploy — exit ${DEPLOY_EXIT}"
echo "  Log: ${DEPLOY_LOG}"
echo "  Record: ${DEPLOY_RECORD}"
```
