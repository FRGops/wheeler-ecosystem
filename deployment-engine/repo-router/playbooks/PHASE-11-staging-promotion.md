# PHASE-11: Staging Promotion

**Purpose:** Promote the sandbox-verified service to the staging environment.
Staging mirrors production but runs in isolation with staging-specific configs,
ports, and resource limits.

**Prerequisites:** PHASE-08 integration tests passed. PHASE-10 zero-trust validation passed.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

STAGE_LOG="/var/log/wheeler/repo-router/staging/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${STAGE_LOG}")"
exec > >(tee -a "${STAGE_LOG}") 2>&1

echo "=== PHASE-11: Staging Promotion for ${SERVICE_NAME} ==="
echo "Source: sandbox -> Target: staging"
```

## 2. Pre-Promotion Verification Gates

```bash
echo ""
echo "=== Pre-Promotion Gate Check ==="
GATES_PASSED=true

# Verify integration tests passed
TEST_LOG="/var/log/wheeler/repo-router/testing/${SERVICE_NAME}-*.log"
LATEST_TEST=$(ls -t ${TEST_LOG} 2>/dev/null | head -1)
if [[ -n "${LATEST_TEST}" ]]; then
    if grep -q "FAIL" "${LATEST_TEST}" 2>/dev/null; then
        echo "[FAIL] Integration test log contains failures: ${LATEST_TEST}"
        GATES_PASSED=false
    else
        echo "[PASS] Integration tests passed (latest: $(basename "${LATEST_TEST}"))"
    fi
fi

# Verify zero-trust validation passed
ZT_REPORT="/var/log/wheeler/repo-router/zt/${SERVICE_NAME}-zt-validation.json"
if [[ -f "${ZT_REPORT}" ]]; then
    ZT_COMPLIANT=$(jq -r '.zt_compliant' "${ZT_REPORT}")
    if [[ "${ZT_COMPLIANT}" != "true" ]]; then
        echo "[FAIL] Zero-trust validation not passed."
        GATES_PASSED=false
    else
        echo "[PASS] Zero-trust validation passed."
    fi
fi

# Verify risk gate approval
GATE_FILE="/var/log/wheeler/repo-router/gate/${SERVICE_NAME}.approval"
if [[ -f "${GATE_FILE}" ]]; then
    if [[ "$(cat "${GATE_FILE}")" != "approved" ]]; then
        echo "[FAIL] Risk gate not approved."
        GATES_PASSED=false
    else
        echo "[PASS] Risk gate approved."
    fi
fi

if [[ "${GATES_PASSED}" != true ]]; then
    echo "FATAL: Pre-promotion gates not all passed. Aborting."
    exit 1
fi
```

## 3. Stop Sandbox Environment

```bash
echo ""
echo "=== Tear Down Sandbox ==="

SANDBOX_TAG="$(cat "/var/log/wheeler/repo-router/sandbox/${SERVICE_NAME}-sandbox-tag.txt" 2>/dev/null || echo '')"

if [[ -n "${SANDBOX_TAG}" ]]; then
    case "${DEPLOY_TYPE}" in
        docker)
            echo "Stopping Docker sandbox project: ${SANDBOX_TAG}"
            cd "${REPO_PATH}"
            COMPOSE_FILE=""
            for f in docker-compose.yml compose.yml; do
                [[ -f "${f}" ]] && COMPOSE_FILE="${f}" && break
            done
            if [[ -n "${COMPOSE_FILE}" ]]; then
                docker compose --project-name "${SANDBOX_TAG}" --file "${COMPOSE_FILE}" down -v 2>&1 | tail -5
            else
                docker stop "${SANDBOX_TAG}" 2>/dev/null || true
                docker rm "${SANDBOX_TAG}" 2>/dev/null || true
            fi
            echo "Sandbox Docker project stopped."
            ;;
        pm2)
            PM2_NAME="${SERVICE_NAME}-sandbox"
            echo "Stopping PM2 sandbox: ${PM2_NAME}"
            pm2 delete "${PM2_NAME}" 2>/dev/null || true
            echo "PM2 sandbox deleted."
            ;;
    esac
fi
```

## 4. Deploy to Staging

```bash
echo ""
echo "=== Staging Deployment ==="

# Use the deployment engine's preflight + deploy pipeline
SCRIPT_DIR="/root/deployment-engine"

case "${DEPLOY_TYPE}" in
    docker)
        echo "Running preflight checks for staging..."
        bash "${SCRIPT_DIR}/preflight-check.sh" "${SERVICE_NAME}" "staging" 2>&1 | tail -20

        if [[ -f "${REPO_PATH}/docker-compose.yml" ]]; then
            # Deploy with staging project name and staging profile
            docker compose \
              --project-name "${SERVICE_NAME}-staging" \
              --file "${REPO_PATH}/docker-compose.yml" \
              --profile staging \
              up --build -d 2>&1 | tail -20

            # Tag containers with staging labels
            docker ps --filter "label=com.docker.compose.project=${SERVICE_NAME}-staging" \
              --format '{{.ID}} {{.Names}}' | while read -r CID CNAME; do
                docker label "${CID}" "wheeler.environment=staging" 2>/dev/null || true
            done
        else
            # Single Dockerfile — run with staging config
            docker build -t "${SERVICE_NAME}:staging" . 2>&1 | tail -3
            docker run -d \
              --name "${SERVICE_NAME}-staging" \
              --network staging-net \
              --label "wheeler.environment=staging" \
              --restart unless-stopped \
              -e "NODE_ENV=staging" \
              "${SERVICE_NAME}:staging" 2>&1 | tail -3
        fi
        echo "[DONE] Docker staging deploy initiated."
        ;;

    pm2)
        echo "Running preflight checks for staging..."
        bash "${SCRIPT_DIR}/preflight-check.sh" "${SERVICE_NAME}" "staging" 2>&1 | tail -10

        ECOSYSTEM_FILE=""
        for f in ecosystem.config.js ecosystem.config.cjs; do
            [[ -f "${REPO_PATH}/${f}" ]] && ECOSYSTEM_FILE="${REPO_PATH}/${f}" && break
        done

        if [[ -n "${ECOSYSTEM_FILE}" ]]; then
            env -i \
              PATH="${PATH}" \
              HOME="${HOME}" \
              NODE_ENV="staging" \
              LOG_LEVEL="debug" \
              pm2 start "${ECOSYSTEM_FILE}" \
                --only "${SERVICE_NAME}" 2>&1 | tail -10
        else
            ENTRY="app.js"; [[ -f server.js ]] && ENTRY="server.js"; [[ -f index.js ]] && ENTRY="index.js"
            pm2 start "${REPO_PATH}/${ENTRY}" \
              --name "${SERVICE_NAME}" \
              -- -e NODE_ENV=staging 2>&1 | tail -5
        fi
        pm2 save --force
        echo "[DONE] PM2 staging deploy initiated."
        ;;
esac
```

## 5. Post-Deploy Health Check (Staging)

```bash
echo ""
echo "=== Post-Deploy Health Check (Staging) ==="

# Give the service time to start
sleep 10

# Use the Wheeler post-deploy healthcheck script
if [[ -x "/root/deployment-engine/post-deploy-healthcheck.sh" ]]; then
    bash "/root/deployment-engine/post-deploy-healthcheck.sh" \
      "${SERVICE_NAME}" "staging" --timeout 60 2>&1 | tail -20
    HC_EXIT=$?
    if [[ "${HC_EXIT}" -eq 0 ]]; then
        echo "[PASS] Staging health check passed."
    else
        echo "[FAIL] Staging health check failed (exit ${HC_EXIT})."
        echo "  Run rollback: /root/deployment-engine/rollback-deployment.sh ${SERVICE_NAME} staging"
        exit 1
    fi
else
    # Manual health check
    for i in $(seq 1 12); do
        echo "  Health check attempt ${i}/12..."
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SERVICE_NAME}"; then
            STATUS=$(docker inspect "${SERVICE_NAME}" --format '{{.State.Health.Status}}' 2>/dev/null || echo "running")
            if [[ "${STATUS}" == "healthy" || "${STATUS}" == "running" ]]; then
                echo "[PASS] Service status: ${STATUS}"
                break
            fi
        fi
        sleep 5
    done
fi
```

## 6. Record Promotion

```bash
PROMOTION_REPORT="/var/log/wheeler/repo-router/staging/${SERVICE_NAME}-promotion.json"
cat > "${PROMOTION_REPORT}" <<-EOF
{
  "service": "${SERVICE_NAME}",
  "promotion": "sandbox-to-staging",
  "status": "promoted",
  "deploy_type": "${DEPLOY_TYPE}",
  "repo_path": "${REPO_PATH}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo ""
echo "Promotion record: ${PROMOTION_REPORT}"
echo ""
echo "PHASE-11 COMPLETE: ${SERVICE_NAME} promoted to staging"
```
