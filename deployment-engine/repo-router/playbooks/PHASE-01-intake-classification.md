# PHASE-01: Intake & Classification

**Purpose:** Accept a repo/service request, verify it exists, classify its language,
framework, and deployment type, then assign a routing decision (docker, pm2, static, systemd).

**Exit Criteria:** A classified route card written to `/var/log/wheeler/repo-router/intake/` with
all metadata fields populated.

---

## 1. Receive Request

```bash
# Expect: service-name, source-repo (optional), requested-environment
SERVICE_NAME="${1:?Usage: $0 <service-name> [git-url] [environment]}"
SOURCE_REPO="${2:-}"
ENVIRONMENT="${3:-production}"

# Create intake session
INTAKE_ID="intake-$(date -u +%Y%m%dT%H%M%S)-${SERVICE_NAME}"
INTAKE_DIR="/var/log/wheeler/repo-router/intake"
mkdir -p "${INTAKE_DIR}"
echo "[${INTAKE_ID}] Starting intake for ${SERVICE_NAME}" | tee "${INTAKE_DIR}/${INTAKE_ID}.log"
```

## 2. Determine Repository Path

```bash
# Check standard locations in priority order
if [[ -d "/opt/wheeler/apps/${SERVICE_NAME}" ]]; then
    REPO_PATH="/opt/wheeler/apps/${SERVICE_NAME}"
elif [[ -d "/opt/wheeler-revenue-automation/${SERVICE_NAME}" ]]; then
    REPO_PATH="/opt/wheeler-revenue-automation/${SERVICE_NAME}"
elif [[ -d "/opt/wheeler/${SERVICE_NAME}" ]]; then
    REPO_PATH="/opt/wheeler/${SERVICE_NAME}"
elif [[ -n "${SOURCE_REPO}" ]]; then
    REPO_PATH="/tmp/repo-router/$(basename "${SOURCE_REPO}" .git)"
    git clone --depth 1 "${SOURCE_REPO}" "${REPO_PATH}" 2>&1
else
    echo "FATAL: Cannot locate repo for ${SERVICE_NAME}. Provide git-url or pre-clone."
    exit 1
fi
echo "REPO_PATH=${REPO_PATH}" >> "${INTAKE_DIR}/${INTAKE_ID}.log"
```

## 3. Language Detection

```bash
cd "${REPO_PATH}"

LANG=""
if [[ -f "package.json" ]]; then
    LANG="node"
elif [[ -f "go.mod" ]]; then
    LANG="go"
elif [[ -f "requirements.txt" || -f "setup.py" || -f "pyproject.toml" ]]; then
    LANG="python"
elif [[ -f "Cargo.toml" ]]; then
    LANG="rust"
elif [[ -f "Gemfile" ]]; then
    LANG="ruby"
elif [[ -f "composer.json" ]]; then
    LANG="php"
elif [[ -f "build.gradle" || -f "pom.xml" ]]; then
    LANG="java"
elif [[ -f "Dockerfile" ]]; then
    LANG="docker"  # Container-first, language unknown
else
    LANG="unknown"
fi
echo "LANG=${LANG}" >> "${INTAKE_DIR}/${INTAKE_ID}.log"
```

## 4. Framework Detection

```bash
FRAMEWORK="none"
case "${LANG}" in
    node)
        if jq -e '.dependencies.next // .devDependencies.next' package.json >/dev/null 2>&1; then
            FRAMEWORK="nextjs"
        elif jq -e '.dependencies.express' package.json >/dev/null 2>&1; then
            FRAMEWORK="express"
        elif jq -e '.dependencies.fastify' package.json >/dev/null 2>&1; then
            FRAMEWORK="fastify"
        elif jq -e '.dependencies.nuxt' package.json >/dev/null 2>&1; then
            FRAMEWORK="nuxt"
        else
            FRAMEWORK="node-other"
        fi
        ;;
    python)
        if [[ -f "manage.py" ]]; then FRAMEWORK="django"
        elif [[ -f "app.py" || -f "wsgi.py" ]]; then FRAMEWORK="flask"
        elif [[ -f "main.py" ]]; then FRAMEWORK="fastapi"
        else FRAMEWORK="python-other"
        fi
        ;;
    go)
        if [[ -f "main.go" ]]; then FRAMEWORK="go-api"; else FRAMEWORK="go-other"; fi
        ;;
esac
echo "FRAMEWORK=${FRAMEWORK}" >> "${INTAKE_DIR}/${INTAKE_ID}.log"
```

## 5. Deployment Type Classification

```bash
# Decide how this service runs
DEPLOY_TYPE=""
if [[ -f "docker-compose.yml" || -f "compose.yml" || -f "Dockerfile" ]]; then
    DEPLOY_TYPE="docker"
elif [[ -f "ecosystem.config.js" || -f "ecosystem.config.cjs" ]]; then
    DEPLOY_TYPE="pm2"
elif [[ -f "nginx.conf" || -d "static" || -d "dist" || -d "build" ]]; then
    DEPLOY_TYPE="static"
elif [[ -f "${SERVICE_NAME}.service" || -d "systemd" ]]; then
    DEPLOY_TYPE="systemd"
else
    # Fallback: check PM2 list for this name
    if pm2 list 2>/dev/null | grep -q "${SERVICE_NAME}"; then
        DEPLOY_TYPE="pm2"
    else
        DEPLOY_TYPE="unknown"
    fi
fi
echo "DEPLOY_TYPE=${DEPLOY_TYPE}" >> "${INTAKE_DIR}/${INTAKE_ID}.log"
```

## 6. Check Git Remote & Branch

```bash
if git rev-parse --git-dir >/dev/null 2>&1; then
    GIT_REMOTE="$(git remote get-url origin 2>/dev/null || echo 'none')"
    GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
    GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
else
    GIT_REMOTE="none"
    GIT_BRANCH="unknown"
    GIT_SHA="unknown"
fi
echo "GIT_REMOTE=${GIT_REMOTE}" >> "${INTAKE_DIR}/${INTAKE_ID}.log"
echo "GIT_BRANCH=${GIT_BRANCH}" >> "${INTAKE_DIR}/${INTAKE_ID}.log"
echo "GIT_SHA=${GIT_SHA}" >> "${INTAKE_DIR}/${INTAKE_ID}.log"
```

## 7. Write Route Card

```bash
cat > "${INTAKE_DIR}/${INTAKE_ID}.json" <<-EOF
{
  "intake_id": "${INTAKE_ID}",
  "service_name": "${SERVICE_NAME}",
  "repo_path": "${REPO_PATH}",
  "language": "${LANG}",
  "framework": "${FRAMEWORK}",
  "deploy_type": "${DEPLOY_TYPE}",
  "git_remote": "${GIT_REMOTE}",
  "git_branch": "${GIT_BRANCH}",
  "git_sha": "${GIT_SHA}",
  "environment": "${ENVIRONMENT}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "classified"
}
EOF

echo "Route card written: ${INTAKE_DIR}/${INTAKE_ID}.json"
echo "PHASE-01 COMPLETE: ${SERVICE_NAME} classified as ${DEPLOY_TYPE} (${LANG}/${FRAMEWORK})"
```
