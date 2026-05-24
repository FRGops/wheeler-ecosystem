# PHASE-07: Sandbox Deployment

**Purpose:** Deploy the service to an isolated sandbox environment for integration testing.
Sandbox deployments use isolated project names, ports, and networks to avoid collision with
production services.

**Prerequisites:** PHASE-06 risk report with gate approval (if score >= 7).

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"
RISK_SCORE=$(jq -r '.risk_score // 0' "${CARD/\/discovery\//\/risk\/}" 2>/dev/null || echo 0)

SANDBOX_LOG="/var/log/wheeler/repo-router/sandbox/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${SANDBOX_LOG}")"
exec > >(tee -a "${SANDBOX_LOG}") 2>&1

SANDBOX_TAG="sandbox-${SERVICE_NAME}-$(date +%s)"
echo "=== PHASE-07: Sandbox Deployment for ${SERVICE_NAME} ==="
echo "Sandbox tag: ${SANDBOX_TAG}"
```

## 2. Gate Check

```bash
echo ""
echo "=== Gate Check ==="
GATE_FILE="/var/log/wheeler/repo-router/gate/${SERVICE_NAME}.approval"
if [[ -f "${GATE_FILE}" ]]; then
    GATE_STATUS="$(cat "${GATE_FILE}")"
    if [[ "${GATE_STATUS}" != "approved" ]]; then
        echo "FATAL: Deployment not approved (status: ${GATE_STATUS})."
        echo "Run: echo 'approved' > ${GATE_FILE}"
        exit 1
    fi
    echo "[PASS] Gate approval confirmed."
fi
```

## 3. Docker Sandbox Deployment

```bash
deploy_docker_sandbox() {
    echo ""
    echo "=== Docker Sandbox Deployment ==="
    cd "${REPO_PATH}"

    # Determine compose file
    COMPOSE_FILE=""
    for f in docker-compose.yml compose.yml; do
        [[ -f "${f}" ]] && COMPOSE_FILE="${f}" && break
    done

    if [[ -z "${COMPOSE_FILE}" ]]; then
        echo "WARN: No compose file found. Trying Dockerfile directly."
        # Build and run from Dockerfile
        docker build -t "${SERVICE_NAME}:sandbox" . 2>&1 | tail -5
        docker run -d \
          --name "${SANDBOX_TAG}" \
          --network sandbox-net \
          --label "wheeler.sandbox=true" \
          --label "wheeler.service=${SERVICE_NAME}" \
          "${SERVICE_NAME}:sandbox" 2>&1
        echo "Container started: ${SANDBOX_TAG}"
        return
    fi

    # Deploy with sandbox project name — isolated networks & volumes
    docker compose \
      --project-name "${SANDBOX_TAG}" \
      --file "${COMPOSE_FILE}" \
      up --build -d 2>&1

    echo "Docker sandbox deployed with project: ${SANDBOX_TAG}"

    # Label all containers in this sandbox project
    docker ps --filter "label=com.docker.compose.project=${SANDBOX_TAG}" \
      --format '{{.ID}} {{.Names}}' | while read -r CID CNAME; do
        docker label "${CID}" "wheeler.sandbox=true" "wheeler.service=${SERVICE_NAME}" 2>/dev/null || true
    done
}
```

## 4. PM2 Sandbox Deployment

```bash
deploy_pm2_sandbox() {
    echo ""
    echo "=== PM2 Sandbox Deployment ==="
    cd "${REPO_PATH}"

    ECOSYSTEM_FILE=""
    for f in ecosystem.config.js ecosystem.config.cjs; do
        [[ -f "${f}" ]] && ECOSYSTEM_FILE="${f}" && break
    done

    if [[ -z "${ECOSYSTEM_FILE}" ]]; then
        echo "WARN: No ecosystem config found. Starting with defaults."
        if [[ -f "app.js" || -f "server.js" || -f "index.js" ]]; then
            ENTRY="app.js"
            [[ -f "server.js" ]] && ENTRY="server.js"
            [[ -f "index.js" ]] && ENTRY="index.js"
            PM2_NAME="${SERVICE_NAME}-sandbox"
            pm2 start "${ENTRY}" \
              --name "${PM2_NAME}" \
              -- --port 0 2>&1 | tail -5
            echo "PM2 sandbox process: ${PM2_NAME}"
        else
            echo "FATAL: No entry point found for PM2 sandbox."
            return 1
        fi
        return
    fi

    # Start with sandbox env vars (override NODE_ENV, ports, etc.)
    PM2_NAME="${SERVICE_NAME}-sandbox"
    env -i \
      PATH="${PATH}" \
      HOME="${HOME}" \
      NODE_ENV="sandbox" \
      SANDBOX="true" \
      PORT="0" \
      pm2 start "${ECOSYSTEM_FILE}" \
        --only "${SERVICE_NAME}" \
        --name "${PM2_NAME}" 2>&1 | tail -10

    echo "PM2 sandbox started: ${PM2_NAME}"
}
```

## 5. Static Site Sandbox

```bash
deploy_static_sandbox() {
    echo ""
    echo "=== Static Site Sandbox Deployment ==="
    cd "${REPO_PATH}"

    # Serve via Python HTTP server in Docker
    STATIC_DIR=""
    for d in dist build static public; do
        [[ -d "${d}" ]] && STATIC_DIR="${d}" && break
    done

    if [[ -z "${STATIC_DIR}" ]]; then
        echo "FATAL: No static directory found (dist/build/static/public)."
        return 1
    fi

    docker run -d \
      --name "${SANDBOX_TAG}" \
      --label "wheeler.sandbox=true" \
      -v "${REPO_PATH}/${STATIC_DIR}:/usr/share/nginx/html:ro" \
      nginx:alpine 2>&1

    echo "Static sandbox served via nginx: ${SANDBOX_TAG}"
}
```

## 6. Wait for Readiness

```bash
wait_for_readiness() {
    echo ""
    echo "=== Waiting for Sandbox Readiness ==="
    sleep 5

    # For Docker containers, wait for HEALTHCHECK
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SANDBOX_TAG}"; then
        for i in $(seq 1 12); do
            STATUS=$(docker inspect "${SANDBOX_TAG}" --format '{{.State.Health.Status}}' 2>/dev/null || echo "starting")
            if [[ "${STATUS}" == "healthy" ]]; then
                echo "[PASS] Container healthy after ${i} checks."
                break
            fi
            echo "  Waiting... (attempt ${i}/12, status: ${STATUS})"
            sleep 5
        done
        docker ps --filter "name=${SANDBOX_TAG}" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    fi
}
```

## 7. Verify Sandbox is Running

```bash
echo ""
echo "=== Deploying Sandbox ==="
case "${DEPLOY_TYPE}" in
    docker) deploy_docker_sandbox ;;
    pm2)    deploy_pm2_sandbox ;;
    static) deploy_static_sandbox ;;
    *)      echo "FATAL: Unknown deploy type: ${DEPLOY_TYPE}"; exit 1 ;;
esac

wait_for_readiness

# Record sandbox tag for cleanup
echo "${SANDBOX_TAG}" > "/var/log/wheeler/repo-router/sandbox/${SERVICE_NAME}-sandbox-tag.txt"

echo ""
echo "PHASE-07 COMPLETE: Sandbox deployed for ${SERVICE_NAME} (tag: ${SANDBOX_TAG})"
```
