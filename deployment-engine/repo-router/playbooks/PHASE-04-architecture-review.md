# PHASE-04: Architecture Review

**Purpose:** Review the service's architecture against Wheeler deployment standards.
Inspect Docker container configuration, PM2 process setup, reverse proxy rules,
and resource allocation to ensure compliance.

**Prerequisites:** PHASE-03 dependency map JSON.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

REVIEW_LOG="/var/log/wheeler/repo-router/arch/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${REVIEW_LOG}")"
exec > >(tee -a "${REVIEW_LOG}") 2>&1

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
```

## 2. Docker Architecture Inspection

```bash
review_docker() {
    echo "=== Docker Architecture Review ==="

    # Check if container is running
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SERVICE_NAME}"; then
        echo "[PASS] Container ${SERVICE_NAME} is running."
        PASS_COUNT=$((PASS_COUNT + 1))

        # Inspect container config
        docker inspect "${SERVICE_NAME}" 2>/dev/null | jq '.[0].Config' > /tmp/arch-${SERVICE_NAME}-config.json

        # Check restart policy
        RESTART_POLICY=$(docker inspect "${SERVICE_NAME}" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
        echo "  Restart policy: ${RESTART_POLICY}"
        if [[ "${RESTART_POLICY}" == "always" || "${RESTART_POLICY}" == "unless-stopped" ]]; then
            echo "  [PASS] Restart policy is appropriate."
        else
            echo "  [WARN] Restart policy is '${RESTART_POLICY}'. Recommend 'always' or 'unless-stopped'."
            WARN_COUNT=$((WARN_COUNT + 1))
        fi

        # Check network mode
        NET_MODE=$(docker inspect "${SERVICE_NAME}" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)
        echo "  Network mode: ${NET_MODE}"

        # Check port bindings
        PORTS=$(docker inspect "${SERVICE_NAME}" --format '{{json .HostConfig.PortBindings}}' 2>/dev/null)
        echo "  Port bindings: ${PORTS}"

        # Check bind mounts
        MOUNTS=$(docker inspect "${SERVICE_NAME}" --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null)
        echo "  Volumes/Mounts:"
        echo "${MOUNTS}" | sed 's/^/    /'

        # Verify healthcheck
        HEALTHCHECK=$(docker inspect "${SERVICE_NAME}" --format '{{json .Config.Healthcheck}}' 2>/dev/null)
        if [[ "${HEALTHCHECK}" != "null" ]]; then
            echo "  [PASS] HEALTHCHECK defined."
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo "  [FAIL] No HEALTHCHECK defined. Add one to Dockerfile."
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi

        # Check for :latest tag
        IMAGE_TAG=$(docker inspect "${SERVICE_NAME}" --format '{{.Config.Image}}' 2>/dev/null)
        if echo "${IMAGE_TAG}" | grep -q ':latest'; then
            echo "  [FAIL] Image uses :latest tag: ${IMAGE_TAG}. Pin to a specific version."
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            echo "  [PASS] Image uses pinned tag: ${IMAGE_TAG}"
            PASS_COUNT=$((PASS_COUNT + 1))
        fi

        # Resource limits
        MEM_LIMIT=$(docker inspect "${SERVICE_NAME}" --format '{{.HostConfig.Memory}}' 2>/dev/null)
        CPU_LIMIT=$(docker inspect "${SERVICE_NAME}" --format '{{.HostConfig.NanoCpus}}' 2>/dev/null)
        echo "  Memory limit: ${MEM_LIMIT} | CPU limit: ${CPU_LIMIT}"
        if [[ "${MEM_LIMIT}" == "0" ]]; then
            echo "  [WARN] No memory limit set. Recommend setting --memory."
            WARN_COUNT=$((WARN_COUNT + 1))
        fi
    else
        echo "[INFO] Container ${SERVICE_NAME} not currently running."
    fi
}
```

## 3. PM2 Architecture Inspection

```bash
review_pm2() {
    echo ""
    echo "=== PM2 Architecture Review ==="

    if pm2 jlist 2>/dev/null | jq -e ".[] | select(.name == \"${SERVICE_NAME}\")" >/dev/null 2>&1; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "[PASS] PM2 process ${SERVICE_NAME} exists."

        PM2_DATA=$(pm2 jlist 2>/dev/null | jq ".[] | select(.name == \"${SERVICE_NAME}\")")

        # Check status
        STATUS=$(echo "${PM2_DATA}" | jq -r '.pm2_env.status')
        echo "  Status: ${STATUS}"
        if [[ "${STATUS}" != "online" ]]; then
            echo "  [FAIL] Process is ${STATUS}, expected 'online'."
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi

        # Check execution mode
        EXEC_MODE=$(echo "${PM2_DATA}" | jq -r '.pm2_env.exec_mode')
        echo "  Exec mode: ${EXEC_MODE}"

        # Check max memory restart
        MAX_MEM=$(echo "${PM2_DATA}" | jq -r '.pm2_env.max_memory_restart // "unset"')
        echo "  max_memory_restart: ${MAX_MEM}"
        if [[ "${MAX_MEM}" == "unset" ]]; then
            echo "  [WARN] max_memory_restart not set. Recommend setting to prevent OOM."
            WARN_COUNT=$((WARN_COUNT + 1))
        fi

        # Check autorestart
        AUTORESTART=$(echo "${PM2_DATA}" | jq -r '.pm2_env.autorestart')
        echo "  autorestart: ${AUTORESTART}"
        if [[ "${AUTORESTART}" != "true" ]]; then
            echo "  [FAIL] autorestart is disabled. Enable it."
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi

        # Check restart count
        RESTARTS=$(echo "${PM2_DATA}" | jq -r '.pm2_env.restart_time // 0')
        if [[ "${RESTARTS}" -gt 10 ]]; then
            echo "  [WARN] ${RESTARTS} restarts detected. Investigate stability."
            WARN_COUNT=$((WARN_COUNT + 1))
        else
            echo "  [PASS] Restarts: ${RESTARTS} (stable)."
        fi

        # Resource usage
        CPU=$(echo "${PM2_DATA}" | jq -r '.monit.cpu // "?"')
        MEM=$(echo "${PM2_DATA}" | jq -r '.monit.memory // "?"')
        echo "  CPU: ${CPU}% | Memory: ${MEM}"
    else
        echo "[INFO] PM2 process ${SERVICE_NAME} not found."
    fi
}
```

## 4. Reverse Proxy / Network Architecture Review

```bash
review_network() {
    echo ""
    echo "=== Reverse Proxy & Network Architecture ==="

    # Check nginx config for this service
    if nginx -T 2>/dev/null | grep -q "${SERVICE_NAME}"; then
        echo "[INFO] nginx config references ${SERVICE_NAME}:"
        nginx -T 2>/dev/null | grep -B2 -A10 "server_name.*${SERVICE_NAME}\|proxy_pass.*${SERVICE_NAME}" | head -20
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[INFO] No nginx reference found for ${SERVICE_NAME}."
    fi

    # Check Traefik routing (Docker labels)
    if docker inspect "${SERVICE_NAME}" 2>/dev/null | jq -r '.[0].Config.Labels' | grep -q 'traefik'; then
        echo "[PASS] Traefik labels detected."
        docker inspect "${SERVICE_NAME}" 2>/dev/null | jq '.[0].Config.Labels' | grep traefik
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "[INFO] No Traefik labels on ${SERVICE_NAME}."
    fi

    # Verify internal-only binding (127.0.0.1)
    if docker inspect "${SERVICE_NAME}" 2>/dev/null | jq -r '.[0].NetworkSettings.Ports' | grep -q '0.0.0.0'; then
        echo "[FAIL] Ports bound to 0.0.0.0 (public). Should bind to 127.0.0.1."
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "[PASS] No public port bindings (traefik/nginx handles ingress)."
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
}
```

## 5. Architecture Summary

```bash
review_docker
review_pm2
review_network

echo ""
echo "=== Architecture Review Summary ==="
echo "  PASS: ${PASS_COUNT}"
echo "  FAIL: ${FAIL_COUNT}"
echo "  WARN: ${WARN_COUNT}"
echo ""

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    echo "NOTE: ${FAIL_COUNT} architecture failures must be resolved before production deployment."
fi

echo ""
echo "PHASE-04 COMPLETE: Architecture reviewed for ${SERVICE_NAME}"
```
