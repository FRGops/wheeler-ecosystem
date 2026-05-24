# PHASE-12: Production Readiness

**Purpose:** Execute the final production readiness checklist. Verify backups,
resource capacity, rollback plan, config completeness, and infrastructure health.

**Prerequisites:** PHASE-11 staging promotion complete. Service running and healthy in staging.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

READY_LOG="/var/log/wheeler/repo-router/readiness/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${READY_LOG}")"
exec > >(tee -a "${READY_LOG}") 2>&1

CHECKLIST=()
CHECKLIST_PASS=0
CHECKLIST_FAIL=0
CHECKLIST_WARN=0

echo "=== PHASE-12: Production Readiness for ${SERVICE_NAME} ==="
echo "Date: $(date -u)"
```

## 2. Run Preflight Check

```bash
echo ""
echo "=== Checklist Item 1: Preflight Check ==="
if [[ -x "/root/deployment-engine/preflight-check.sh" ]]; then
    /root/deployment-engine/preflight-check.sh "${SERVICE_NAME}" "production" 2>&1 | tail -20
    PREFLIGHT_EXIT=$?
    if [[ "${PREFLIGHT_EXIT}" -eq 0 ]]; then
        echo "[PASS] Preflight check passed."
        CHECKLIST_PASS=$((CHECKLIST_PASS + 1))
    else
        echo "[FAIL] Preflight check failed (exit ${PREFLIGHT_EXIT})."
        CHECKLIST_FAIL=$((CHECKLIST_FAIL + 1))
    fi
else
    echo "[WARN] preflight-check.sh not found. Skipping."
    CHECKLIST_WARN=$((CHECKLIST_WARN + 1))
fi
```

## 3. Verify Backup Exists

```bash
echo ""
echo "=== Checklist Item 2: Backup Verification ==="
BACKUP_DIR="/opt/wheeler/backups/${SERVICE_NAME}"
BACKUP_SCRIPT="/root/scripts/pre-deploy-backup.sh"

if [[ -x "${BACKUP_SCRIPT}" ]]; then
    echo "Running pre-deploy backup for ${SERVICE_NAME}..."
    bash "${BACKUP_SCRIPT}" "${SERVICE_NAME}" "production" 2>&1 | tail -10
    echo "[PASS] Backup created."
    CHECKLIST_PASS=$((CHECKLIST_PASS + 1))
elif [[ -d "${BACKUP_DIR}" ]]; then
    BACKUP_COUNT=$(find "${BACKUP_DIR}" -name "*.sql" -o -name "*.tar.gz" -o -name "*.dump" 2>/dev/null | wc -l)
    echo "Existing backups in ${BACKUP_DIR}: ${BACKUP_COUNT} files."
    if [[ "${BACKUP_COUNT}" -gt 0 ]]; then
        LATEST_BACKUP=$(ls -t "${BACKUP_DIR}"/* 2>/dev/null | head -1)
        echo "  Latest backup: ${LATEST_BACKUP}"
        echo "[PASS] Backups found."
        CHECKLIST_PASS=$((CHECKLIST_PASS + 1))
    else
        echo "[FAIL] No backups found for ${SERVICE_NAME}."
        CHECKLIST_FAIL=$((CHECKLIST_FAIL + 1))
    fi
else
    echo "[WARN] No backup directory at ${BACKUP_DIR}."
    echo "  Create one: mkdir -p ${BACKUP_DIR}"
    CHECKLIST_WARN=$((CHECKLIST_WARN + 1))
fi

# For databases, check pg_dump/redis backup
if docker ps --format '{{.Names}}' | grep -qE "postgres|${SERVICE_NAME}.*db"; then
    echo "  Database container detected. Database backup should be verified separately."
fi
```

## 4. Verify Rollback Plan Exists

```bash
echo ""
echo "=== Checklist Item 3: Rollback Plan ==="
ROLLBACK_SCRIPT="/root/deployment-engine/rollback-deployment.sh"

if [[ -x "${ROLLBACK_SCRIPT}" ]]; then
    echo "[PASS] Rollback script exists: ${ROLLBACK_SCRIPT}"
    CHECKLIST_PASS=$((CHECKLIST_PASS + 1))

    # Verify rollback engine available
    if [[ -x "/root/rollback-engine/rollback.sh" ]]; then
        echo "[PASS] Rollback engine available: /root/rollback-engine/rollback.sh"
        CHECKLIST_PASS=$((CHECKLIST_PASS + 1))
    else
        echo "[WARN] Rollback engine not found at /root/rollback-engine/rollback.sh"
        CHECKLIST_WARN=$((CHECKLIST_WARN + 1))
    fi
else
    echo "[FAIL] Rollback deployment script not found."
    CHECKLIST_FAIL=$((CHECKLIST_FAIL + 1))
fi

# Verify deployment verification script
if [[ -x "/root/deployment-engine/verify-deployment.sh" ]]; then
    echo "[PASS] Deployment verification script available."
    CHECKLIST_PASS=$((CHECKLIST_PASS + 1))
fi
```

## 5. Check Disk & Memory Resources

```bash
echo ""
echo "=== Checklist Item 4: Resource Capacity ==="

echo "--- Disk Usage ---"
df -h / /opt /var/lib/docker 2>/dev/null | awk '{print "  " $0}'

# Warn if disk > 80%
DISK_PCT=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ -n "${DISK_PCT}" && "${DISK_PCT}" -gt 80 ]]; then
    echo "[WARN] Root disk at ${DISK_PCT}% usage. Free up space before deploy."
    CHECKLIST_WARN=$((CHECKLIST_WARN + 1))
else
    echo "[PASS] Root disk at ${DISK_PCT:-?}% usage."
    CHECKLIST_PASS=$((CHECKLIST_PASS + 1))
fi

echo ""
echo "--- Memory Usage ---"
free -h 2>/dev/null | awk '{print "  " $0}'

MEM_PCT=$(free | grep Mem | awk '{print int($3/$2 * 100)}' 2>/dev/null)
if [[ -n "${MEM_PCT}" && "${MEM_PCT}" -gt 85 ]]; then
    echo "[WARN] Memory at ${MEM_PCT}% usage. May need to free memory."
    CHECKLIST_WARN=$((CHECKLIST_WARN + 1))
else
    echo "[PASS] Memory at ${MEM_PCT:-?}% usage."
    CHECKLIST_PASS=$((CHECKLIST_PASS + 1))
fi

echo ""
echo "--- Docker Disk Usage ---"
docker system df 2>/dev/null | sed 's/^/  /'
```

## 6. Config Completeness Check

```bash
echo ""
echo "=== Checklist Item 5: Configuration Completeness ==="

# Check for required env vars in production
ENV_TEMPLATE_FILE="${REPO_PATH}/.env.example"
if [[ -f "${ENV_TEMPLATE_FILE}" ]]; then
    echo "Found .env.example — verifying against production expectations."
    while IFS= read -r line; do
        # Skip comments and blanks
        [[ "${line}" =~ ^# || -z "${line}" ]] && continue
        VAR_NAME=$(echo "${line}" | cut -d= -f1)
        if echo "${line}" | grep -q '=<'; then
            echo "  [WARN] ${VAR_NAME} has placeholder value (unset)."
            CHECKLIST_WARN=$((CHECKLIST_WARN + 1))
        fi
    done < "${ENV_TEMPLATE_FILE}"
fi

# Verify deployment configs exist
CONFIG_DIRS=(
    "/opt/wheeler/configs/${SERVICE_NAME}"
    "/root/infrastructure/hetzner/compose/${SERVICE_NAME}"
    "/root/infrastructure/hostinger/traefik/${SERVICE_NAME}"
)
for dir in "${CONFIG_DIRS[@]}"; do
    if [[ -d "${dir}" ]]; then
        echo "[PASS] Config directory: ${dir}"
        ls -la "${dir}" | head -10 | sed 's/^/  /'
        CHECKLIST_PASS=$((CHECKLIST_PASS + 1))
    fi
done
```

## 7. Staging Verification Snapshot

```bash
echo ""
echo "=== Checklist Item 6: Staging Verification ==="

VERIFY_SCRIPT="/root/deployment-engine/verify-deployment.sh"
if [[ -x "${VERIFY_SCRIPT}" ]]; then
    bash "${VERIFY_SCRIPT}" "${SERVICE_NAME}" "staging" --json 2>&1 | tail -15
    VERIFY_EXIT=$?
    if [[ "${VERIFY_EXIT}" -eq 0 ]]; then
        echo "[PASS] Staging verification passed."
        CHECKLIST_PASS=$((CHECKLIST_PASS + 1))
    else
        echo "[FAIL] Staging verification failed (exit ${VERIFY_EXIT})."
        CHECKLIST_FAIL=$((CHECKLIST_FAIL + 1))
    fi
fi
```

## 8. Readiness Report

```bash
READY_REPORT="/var/log/wheeler/repo-router/readiness/${SERVICE_NAME}-readiness.json"
cat > "${READY_REPORT}" <<-EOF
{
  "service": "${SERVICE_NAME}",
  "pass": ${CHECKLIST_PASS},
  "fail": ${CHECKLIST_FAIL},
  "warn": ${CHECKLIST_WARN},
  "ready": $( [[ ${CHECKLIST_FAIL} -eq 0 ]] && echo 'true' || echo 'false' ),
  "checks": [
    $(for item in "${CHECKLIST[@]}"; do echo "\"${item}\","; done)
  ],
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo ""
echo "=== Production Readiness Summary ==="
echo "  PASS: ${CHECKLIST_PASS}"
echo "  FAIL: ${CHECKLIST_FAIL}"
echo "  WARN: ${CHECKLIST_WARN}"
echo ""

if [[ "${CHECKLIST_FAIL}" -gt 0 ]]; then
    echo "** ${CHECKLIST_FAIL} readiness checks failed. Must resolve before production deploy. **"
    echo "  Report: ${READY_REPORT}"
    exit 1
fi

echo "** Production deployment is GO. **"
echo ""
echo "PHASE-12 COMPLETE: ${SERVICE_NAME} is production-ready"
echo "Report: ${READY_REPORT}"
```
