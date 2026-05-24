# PHASE-03: Dependency Mapping

**Purpose:** Map all upstream dependencies (libraries, services, databases, networks)
that this repo depends on and identify all downstream consumers that depend on it.

**Prerequisites:** PHASE-02 discovery JSON at `/var/log/wheeler/repo-router/discovery/`.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

DEP_MAP_LOG="/var/log/wheeler/repo-router/deps/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${DEP_MAP_LOG}")"
exec > >(tee -a "${DEP_MAP_LOG}") 2>&1

echo "=== PHASE-03: Dependency Mapping for ${SERVICE_NAME} ==="
cd "${REPO_PATH}"
```

## 2. Language-Specific Dependency Extraction

```bash
echo ""
echo "=== Extracting Dependencies ==="

if [[ -f "package.json" ]]; then
    echo "--- npm/node dependencies ---"
    jq -r '.dependencies // {} | to_entries[] | "\(.key)@\(.value)"' package.json 2>/dev/null | head -30
    echo "--- devDependencies (count) ---"
    jq -r '.devDependencies // {} | length' package.json 2>/dev/null
    echo "--- Peer Dependencies ---"
    jq -r '.peerDependencies // {} | to_entries[] | "\(.key)@\(.value)"' package.json 2>/dev/null
fi

if [[ -f "go.mod" ]]; then
    echo "--- Go dependencies ---"
    grep -E '^\t[a-zA-Z]' go.mod | head -30 || echo "(none listed in go.mod)"
fi

if [[ -f "requirements.txt" ]]; then
    echo "--- Python dependencies ---"
    head -30 requirements.txt
fi

if [[ -f "Cargo.toml" ]]; then
    echo "--- Rust dependencies ---"
    grep -E '^\[dependencies' -A 30 Cargo.toml | grep -E '^\w' | head -20
fi
```

## 3. Internal Service Dependency Scan

```bash
echo ""
echo "=== Internal Import References ==="
# Scan for internal module/service references
for pattern in "wheeler-" "frgcrm-" "surplusai-" "prediction-radar-" "ravyn-" "horizon-" \
               "insforge-" "paperless-" "voice-" "openclaw-" "litellm"; do
    RESULTS=$(grep -r --include="*.{js,ts,py,go,rs,yaml,yml,json,toml}" \
              -l "${pattern}" "${REPO_PATH}" 2>/dev/null | head -10)
    if [[ -n "${RESULTS}" ]]; then
        echo "Referenced: ${pattern}"
        echo "${RESULTS}" | sed 's/^/  /'
    fi
done
```

## 4. Docker Network Dependency Mapping

```bash
echo ""
echo "=== Docker Network Analysis ==="
if [[ -f "docker-compose.yml" ]]; then
    echo "--- External networks referenced ---"
    grep -E 'external:' -A 2 docker-compose.yml 2>/dev/null || echo "(none declared external)"

    echo "--- depends_on (service deps) ---"
    grep -A 10 'depends_on:' docker-compose.yml 2>/dev/null | grep -v 'depends_on:' | \
      grep -E '^\s+- ' | sed 's/^[[:space:]]*- //' || echo "(none declared)"

    echo "--- Port mappings (exposed to host) ---"
    grep -E 'ports:' -A 5 docker-compose.yml 2>/dev/null | grep -E '^\s+- ' || echo "(none)"
fi

# Check running Docker container links
echo ""
echo "--- Docker network connections for ${SERVICE_NAME} ---"
docker network ls --format '{{.Name}}' 2>/dev/null | while read -r net; do
    CONNECTED="$(docker network inspect "${net}" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)"
    if echo "${CONNECTED}" | grep -q "${SERVICE_NAME}"; then
        echo "  Network: ${net} -> connected to: ${CONNECTED}"
    fi
done
```

## 5. Config & Environment Dependency Detection

```bash
echo ""
echo "=== Config/Environment Dependency Scan ==="
# Detect references to known env vars
ENV_REFS=$(grep -roh --include="*.{js,ts,py,go,env,yml,yaml,sh}" \
  'process\.env\.\w\+\|os\.getenv("\w\+")\|\$\{\w\+:-\?\w*\}\|env\.\w\+' \
  "${REPO_PATH}" 2>/dev/null | sort -u | head -30)
if [[ -n "${ENV_REFS}" ]]; then
    echo "Environment variables used:"
    echo "${ENV_REFS}" | sed 's/^/  /'
fi

# Check for .env.example or .env.template
for env_tpl in .env.example .env.template .env.sample; do
    if [[ -f "${env_tpl}" ]]; then
        echo ""
        echo "--- ${env_tpl} ---"
        cat "${env_tpl}"
    fi
done
```

## 6. Downstream Consumer Detection

```bash
echo ""
echo "=== Downstream Consumers (what depends on ${SERVICE_NAME}) ==="
# Scan all wheeler repos for references to this service
CONSUMER_DIRS=("/opt/wheeler/apps" "/opt/wheeler-revenue-automation" "/opt/wheeler" "/root")
for consumer_dir in "${CONSUMER_DIRS[@]}"; do
    if [[ -d "${consumer_dir}" ]]; then
        FOUND=$(grep -rl --include="*.{js,ts,py,go,yml,yaml,json,env}" \
          "${SERVICE_NAME}" "${consumer_dir}" 2>/dev/null | grep -v "node_modules" | \
          grep -v ".git/" | grep -v "${REPO_PATH}" | head -10)
        if [[ -n "${FOUND}" ]]; then
            echo "Consumers in ${consumer_dir}:"
            echo "${FOUND}" | sed 's/^/  /'
        fi
    fi
done
```

## 7. Write Dependency Map

```bash
DEP_FILE="/var/log/wheeler/repo-router/deps/${SERVICE_NAME}-deps.json"
# Collect into structured JSON
{
  echo "{"
  echo "  \"service\": \"${SERVICE_NAME}\","
  echo "  \"repo_path\": \"${REPO_PATH}\","
  echo "  \"lang_dep_files_found\": ["
  for f in package.json go.mod requirements.txt Cargo.toml; do
    [[ -f "${f}" ]] && echo "    \"${f}\","
  done | sed '$s/,$//'
  echo "  ],"
  echo "  \"external_services\": [],"
  echo "  \"downstream_consumers\": []"
  echo "}"
} > "${DEP_FILE}"
echo ""
echo "Dependency map: ${DEP_FILE}"

echo ""
echo "PHASE-03 COMPLETE: Dependencies mapped for ${SERVICE_NAME}"
```
