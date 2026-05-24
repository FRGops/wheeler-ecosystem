# PHASE-02: Repo Discovery & Verification

**Purpose:** Verify the repository exists, check remotes and branches, validate
git health, and confirm the working tree is clean before proceeding with a deployment.

**Prerequisites:** PHASE-01 route card must exist at `/var/log/wheeler/repo-router/intake/`.

---

## 1. Load Route Card

```bash
PHASE_DIR="/var/log/wheeler/repo-router"
CARD="${1:?Usage: $0 <path-to-route-card.json>}"
SERVICE_NAME="$(jq -r '.service_name' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

DISCOVERY_LOG="${PHASE_DIR}/discovery/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${DISCOVERY_LOG}")"
exec > >(tee -a "${DISCOVERY_LOG}") 2>&1

echo "=== PHASE-02: Repo Discovery for ${SERVICE_NAME} ==="
echo "Repo path: ${REPO_PATH}"
```

## 2. Verify Repo Exists

```bash
if [[ ! -d "${REPO_PATH}" ]]; then
    echo "FATAL: Repository path ${REPO_PATH} does not exist."
    exit 1
fi

cd "${REPO_PATH}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "WARN: ${REPO_PATH} is not a git repository."
    echo "If this is an existing deployment, skip git checks."
    IS_GIT=false
else
    IS_GIT=true
    echo "Git repository verified at ${REPO_PATH}"
fi
```

## 3. Check Remote URLs

```bash
if [[ "${IS_GIT}" == true ]]; then
    echo ""
    echo "=== Git Remotes ==="
    git remote -v

    # Validate at least one remote exists
    REMOTE_COUNT="$(git remote | wc -l)"
    if [[ "${REMOTE_COUNT}" -eq 0 ]]; then
        echo "WARN: No git remotes configured. Deploy may lack upstream tracking."
    fi

    echo ""
    echo "=== Last 5 Commits ==="
    git log --oneline -5 2>/dev/null || echo "(no commits)"
fi
```

## 4. Check All Branches

```bash
if [[ "${IS_GIT}" == true ]]; then
    echo ""
    echo "=== Branches (local + remote) ==="
    git branch -a 2>/dev/null || echo "(no branches)"

    CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    echo ""
    echo "Current branch: ${CURRENT_BRANCH}"

    # Warn if not on main/master/release
    case "${CURRENT_BRANCH}" in
        main|master|release/*)
            echo "OK: On a primary branch (${CURRENT_BRANCH})"
            ;;
        *)
            echo "WARN: Not on main/master/release branch (${CURRENT_BRANCH})."
            echo "  Consider merging to main before deployment."
            ;;
    esac
fi
```

## 5. Check Working Tree Cleanliness

```bash
if [[ "${IS_GIT}" == true ]]; then
    echo ""
    echo "=== Working Tree Status ==="
    if git diff --stat 2>/dev/null | tail -1; then
        CHANGED_FILES="$(git diff --name-only 2>/dev/null | wc -l)"
        echo "WARN: ${CHANGED_FILES} unstaged changed files present."
        echo "  Uncommitted changes:"
        git diff --stat 2>/dev/null
        git diff --cached --stat 2>/dev/null
    else
        echo "Working tree clean (no unstaged changes)."
    fi

    # Check for untracked files (non-git)
    UNTRACKED="$(git ls-files --others --exclude-standard | wc -l)"
    if [[ "${UNTRACKED}" -gt 0 ]]; then
        echo "INFO: ${UNTRACKED} untracked file(s) present (may be build artifacts)."
    fi
fi
```

## 6. Verify Deploy-Specific Artifacts

```bash
echo ""
echo "=== Deployment Artifact Check ==="
case "${DEPLOY_TYPE}" in
    docker)
        if [[ -f "Dockerfile" ]]; then
            echo "Dockerfile found: $(head -1 Dockerfile)"
        fi
        if ls docker-compose.yml compose.yml >/dev/null 2>&1; then
            echo "Compose file(s) present."
        fi
        ;;
    pm2)
        if ls ecosystem.config.* 2>/dev/null; then
            echo "PM2 ecosystem config found."
        fi
        ;;
    static)
        for dir in dist build static public; do
            if [[ -d "${dir}" ]]; then
                echo "Static directory found: ${dir}/ ($(find "${dir}" -type f | wc -l) files)"
            fi
        done
        ;;
esac
```

## 7. Validate PATH Accessibility

```bash
echo ""
echo "=== PATH & Permissions ==="
ls -ld "${REPO_PATH}"
if [[ ! -r "${REPO_PATH}" ]]; then
    echo "FATAL: Repo path is not readable."
    exit 1
fi
echo "Disk usage: $(du -sh "${REPO_PATH}" 2>/dev/null | cut -f1)"
```

## 8. Write Discovery Report

```bash
if [[ "${IS_GIT}" == true ]]; then
    DISCOVERY_JSON="${DISCOVERY_LOG%.log}.json"
    jq -n \
      --arg svc "${SERVICE_NAME}" \
      --arg path "${REPO_PATH}" \
      --arg branch "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'none')" \
      --arg sha "$(git rev-parse --short HEAD 2>/dev/null || echo 'none')" \
      --arg remote "$(git remote get-url origin 2>/dev/null || echo 'none')" \
      --arg clean "$(git diff --stat | tail -1)" \
      --arg deploy "${DEPLOY_TYPE}" \
      '{service: $svc, repo_path: $path, branch: $branch, commit: $sha, remote: $remote, clean: $clean, deploy_type: $deploy}' \
      > "${DISCOVERY_JSON}"
    echo ""
    echo "Discovery report: ${DISCOVERY_JSON}"
fi

echo ""
echo "PHASE-02 COMPLETE: ${SERVICE_NAME} verified at ${REPO_PATH}"
```
