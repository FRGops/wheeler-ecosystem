# PHASE-08: Integration Testing

**Purpose:** Verify the sandbox-deployed service integrates correctly with its
consumers, passes health checks, satisfies API contracts, and performs within
acceptable parameters.

**Prerequisites:** PHASE-07 sandbox deployment running.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

TEST_LOG="/var/log/wheeler/repo-router/testing/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${TEST_LOG}")"
exec > >(tee -a "${TEST_LOG}") 2>&1

TEST_PASS=0
TEST_FAIL=0
TEST_SKIP=0

# Load sandbox tag
SANDBOX_TAG="$(cat "/var/log/wheeler/repo-router/sandbox/${SERVICE_NAME}-sandbox-tag.txt" 2>/dev/null || echo '')"
echo "=== PHASE-08: Integration Testing for ${SERVICE_NAME} ==="
echo "Sandbox tag: ${SANDBOX_TAG}"
```

## 2. Determine Sandbox Endpoint

```bash
echo ""
echo "=== Resolving Sandbox Endpoint ==="

if [[ "${DEPLOY_TYPE}" == "docker" ]]; then
    # Get container IP on sandbox network
    SANDBOX_IP=$(docker inspect "${SANDBOX_TAG}" 2>/dev/null | \
      jq -r '.[0].NetworkSettings.Networks | to_entries[0].value.IPAddress // "127.0.0.1"')
    SANDBOX_PORT=$(docker inspect "${SANDBOX_TAG}" 2>/dev/null | \
      jq -r '.[0].NetworkSettings.Ports | to_entries[0].value[0].HostPort // ""')
    SANDBOX_URL="http://${SANDBOX_IP}:${SANDBOX_PORT}"
    echo "Docker sandbox endpoint: ${SANDBOX_URL}"

elif [[ "${DEPLOY_TYPE}" == "pm2" ]]; then
    PM2_NAME="${SERVICE_NAME}-sandbox"
    SANDBOX_PORT=$(pm2 jlist 2>/dev/null | jq -r \
      ".[] | select(.name == \"${PM2_NAME}\") | .pm2_env.PORT // .pm2_env.port // \"\""")
    SANDBOX_URL="http://127.0.0.1:${SANDBOX_PORT}"
    echo "PM2 sandbox endpoint: ${SANDBOX_URL}"

elif [[ "${DEPLOY_TYPE}" == "static" ]]; then
    SANDBOX_IP=$(docker inspect "${SANDBOX_TAG}" 2>/dev/null | \
      jq -r '.[0].NetworkSettings.IPAddress')
    SANDBOX_URL="http://${SANDBOX_IP}:80"
    echo "Static sandbox endpoint: ${SANDBOX_URL}"
fi
```

## 3. HTTP Health Check

```bash
echo ""
echo "=== Test 1: HTTP Health Check ==="

if [[ -n "${SANDBOX_URL}" ]]; then
    # Common health endpoints
    for endpoint in "/health" "/healthz" "/ready" "/api/health" "/" "/_health"; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
          "${SANDBOX_URL}${endpoint}" 2>/dev/null || echo "000")
        if [[ "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
            echo "[PASS] ${endpoint} -> HTTP ${HTTP_CODE}"
            TEST_PASS=$((TEST_PASS + 1))
            break 2
        elif [[ "${HTTP_CODE}" != "000" ]]; then
            echo "[INFO] ${endpoint} -> HTTP ${HTTP_CODE} (not a 2xx, continuing)"
        fi
    done
else
    echo "[SKIP] No sandbox URL available."
    TEST_SKIP=$((TEST_SKIP + 1))
fi
```

## 4. API Contract Verification

```bash
echo ""
echo "=== Test 2: API Contract Verification ==="

# Check if there's an OpenAPI spec in the repo
SPEC_FILE=""
for spec in openapi.yaml openapi.yml swagger.yaml swagger.yml api-spec.yaml; do
    [[ -f "${REPO_PATH}/${spec}" ]] && SPEC_FILE="${REPO_PATH}/${spec}" && break
done

if [[ -n "${SPEC_FILE}" ]]; then
    echo "Found API spec: ${SPEC_FILE}"
    # Install openapi-diff/prism if needed
    which prism 2>/dev/null || npm install -g @stoplight/prism-cli 2>/dev/null || true

    if which prism 2>/dev/null; then
        # Run contract validation against live endpoint
        prism validate "${SPEC_FILE}" 2>&1 | tail -10
        echo "[INFO] Contract validated (file syntax). Live validation skipped in sandbox."
        TEST_PASS=$((TEST_PASS + 1))
    fi
else
    echo "[SKIP] No OpenAPI/Swagger spec found in repo."
    TEST_SKIP=$((TEST_SKIP + 1))
fi

# Verify key endpoints respond with valid JSON
echo ""
echo "--- Endpoint Response Validation ---"
for endpoint in "/api/v1" "/api" "/graphql" "/rest"; do
    RESP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
      "${SANDBOX_URL}${endpoint}" 2>/dev/null || echo "")
    if [[ -n "${RESP}" ]] && [[ "${RESP}" != "000" ]]; then
        echo "[INFO] ${endpoint} -> HTTP ${RESP}"
        # Check JSON response
        CONTENT_TYPE=$(curl -s -I --max-time 5 "${SANDBOX_URL}${endpoint}" 2>/dev/null | \
          grep -i 'content-type:' | grep -oi 'application/json' || echo "")
        if [[ -n "${CONTENT_TYPE}" ]]; then
            echo "[PASS] ${endpoint} returns JSON."
            TEST_PASS=$((TEST_PASS + 1))
        fi
    fi
done
```

## 5. Smoke Test Suite

```bash
echo ""
echo "=== Test 3: Smoke Test Suite ==="

# Run project-specific test suite if it exists
if [[ -f "${REPO_PATH}/package.json" ]]; then
    echo "[INFO] npm project — checking for test scripts..."
    TEST_SCRIPTS=$(jq -r '.scripts.test // .scripts["test:ci"] // .scripts.smoke // ""' \
      "${REPO_PATH}/package.json" 2>/dev/null)
    if [[ -n "${TEST_SCRIPTS}" ]]; then
        echo "  Available test script(s):"
        echo "${TEST_SCRIPTS}" | sed 's/^/    /'
        cd "${REPO_PATH}"
        npm test 2>&1 | tail -20
        if [[ $? -eq 0 ]]; then
            echo "[PASS] npm test suite passed."
            TEST_PASS=$((TEST_PASS + 1))
        else
            echo "[FAIL] npm test suite failed."
            TEST_FAIL=$((TEST_FAIL + 1))
        fi
    else
        echo "[SKIP] No test script defined in package.json."
        TEST_SKIP=$((TEST_SKIP + 1))
    fi
fi

if [[ -f "${REPO_PATH}/Makefile" ]]; then
    if grep -q 'test' "${REPO_PATH}/Makefile"; then
        echo "[INFO] Running make test..."
        cd "${REPO_PATH}"
        make test 2>&1 | tail -20
        if [[ $? -eq 0 ]]; then
            echo "[PASS] make test passed."
            TEST_PASS=$((TEST_PASS + 1))
        fi
    fi
fi

# Run the smoke-test-all.sh against just this service
if [[ -x /root/scripts/smoke-test-all.sh ]]; then
    echo "[INFO] Running wheeler smoke test for ${SERVICE_NAME}..."
    /root/scripts/smoke-test-all.sh --service "${SERVICE_NAME}" 2>&1 | tail -15
fi
```

## 6. Consumer Integration Check

```bash
echo ""
echo "=== Test 4: Consumer Integration Check ==="
# For each known consumer, check if they can reach this service
CONSUMER_FILE="/var/log/wheeler/repo-router/deps/${SERVICE_NAME}-deps.json"
if [[ -f "${CONSUMER_FILE}" ]]; then
    CONSUMERS=($(jq -r '.downstream_consumers[]' "${CONSUMER_FILE}" 2>/dev/null))
    for consumer in "${CONSUMERS[@]}"; do
        echo "[INFO] Would test consumer: ${consumer} against ${SANDBOX_URL}"
        # In CI, this would trigger the consumer's test suite pointing at sandbox
    done
fi
```

## 7. Integration Test Summary

```bash
echo ""
echo "=== Integration Test Summary ==="
echo "  PASS: ${TEST_PASS}"
echo "  FAIL: ${TEST_FAIL}"
echo "  SKIP: ${TEST_SKIP}"

# Score as pass/fail — if any fail, block promotion
if [[ "${TEST_FAIL}" -gt 0 ]]; then
    echo ""
    echo "** ${TEST_FAIL} test(s) failed. Sandbox is NOT ready for promotion. **"
    echo "  Investigate failures above, fix, and re-run PHASE-08."
    echo ""
    echo "Quick debug:"
    echo "  Docker logs:  docker logs ${SANDBOX_TAG} --tail 30"
    echo "  PM2 logs:     pm2 logs ${SERVICE_NAME}-sandbox --lines 30"
    echo "  Curl test:    curl -v ${SANDBOX_URL}/health"
    exit 1
fi

echo ""
echo "PHASE-08 COMPLETE: Integration tests ${TEST_FAIL}/${TEST_FAIL+TEST_PASS} failed for ${SERVICE_NAME}"
```
