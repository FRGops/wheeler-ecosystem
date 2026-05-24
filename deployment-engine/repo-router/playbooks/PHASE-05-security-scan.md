# PHASE-05: Security Scan

**Purpose:** Scan the service for exposed secrets, vulnerable dependencies, open
network ports, firewall gaps, and container security posture before allowing deployment.

**Prerequisites:** PHASE-04 architecture review log.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

SEC_LOG="/var/log/wheeler/repo-router/security/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${SEC_LOG}")"
exec > >(tee -a "${SEC_LOG}") 2>&1

SCAN_PASS=0
SCAN_FAIL=0
SCAN_WARN=0
```

## 2. Secrets-in-Code Scan

```bash
echo "=== Secrets Scan ==="
cd "${REPO_PATH}"

SECRET_PATTERNS=(
    '["\x27]?(?:API[_-]?KEY|api[_-]?key|apikey)["\x27]?\s*[:=]\s*["\x27][^"\x27]+["\x27]'
    '["\x27]?(?:SECRET|secret|SECRET_KEY|secret_key)["\x27]?\s*[:=]\s*["\x27][^"\x27]+["\x27]'
    '["\x27]?(?:PASSWORD|password|PASS|pass)["\x27]?\s*[:=]\s*["\x27][^"\x27]+["\x27]'
    '["\x27]?(?:TOKEN|token|ACCESS_TOKEN|auth_token)["\x27]?\s*[:=]\s*["\x27][^"\x27]+["\x27]'
    '["\x27]?(?:DEEPSEEK|OPENAI|ANTHROPIC|GEMINI)_API_KEY["\x27]?\s*[:=]\s*["\x27][^"\x27]+["\x27]'
    '-----BEGIN (?:RSA |EC )?PRIVATE KEY-----'
    'sk-[a-zA-Z0-9]{20,}'
    'ghp_[a-zA-Z0-9]{36}'
)

for pattern in "${SECRET_PATTERNS[@]}"; do
    MATCHES=$(grep -rn --include="*.{js,ts,py,go,yml,yaml,env,sh,json,toml,conf}" \
      -E "${pattern}" "${REPO_PATH}" 2>/dev/null | \
      grep -v 'node_modules/' | grep -v '.git/' | grep -v '\.example\.' || true)
    if [[ -n "${MATCHES}" ]]; then
        echo "[WARN] Potential secret found:"
        echo "${MATCHES}" | head -5 | sed 's/^/  /'
        SCAN_WARN=$((SCAN_WARN + 1))
    fi
done

# Check for .env files committed or present
if [[ -f "${REPO_PATH}/.env" ]]; then
    echo "[FAIL] .env file present in repo! Remove or add to .gitignore."
    SCAN_FAIL=$((SCAN_FAIL + 1))
fi

if [[ -f "${REPO_PATH}/.gitignore" ]]; then
    if grep -q '\.env' "${REPO_PATH}/.gitignore"; then
        echo "[PASS] .env listed in .gitignore."
        SCAN_PASS=$((SCAN_PASS + 1))
    fi
fi

echo "[PASS] Secret scan completed."
```

## 3. Network Port Exposure Scan

```bash
echo ""
echo "=== Network Port Exposure Scan ==="

# Scan for listening ports on the service container
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SERVICE_NAME}"; then
    echo "--- Port bindings for ${SERVICE_NAME} ---"
    docker port "${SERVICE_NAME}" 2>/dev/null || echo "  (no published ports)"

    PUBLIC_PORTS=$(docker inspect "${SERVICE_NAME}" 2>/dev/null | \
      jq -r '.[0].NetworkSettings.Ports | to_entries[] | select(.value[]?.HostIp == "0.0.0.0") | .key')
    if [[ -n "${PUBLIC_PORTS}" ]]; then
        echo "[FAIL] Publicly bound ports detected: ${PUBLIC_PORTS}"
        echo "  All services should bind to 127.0.0.1. Traefik/nginx handles public ingress."
        SCAN_FAIL=$((SCAN_FAIL + 1))
    fi
fi

# UFW firewall audit
echo ""
echo "--- Firewall Rules (UFW) ---"
ufw status numbered 2>/dev/null || echo "UFW not active"
# Warn on rules allowing public 0.0.0.0/0 that aren't port 22/80/443
UFW_RISKY=$(ufw status 2>/dev/null | grep -E 'ALLOW.*Anywhere' | grep -v 'OpenSSH\|443/tcp\|80/tcp' | head -5)
if [[ -n "${UFW_RISKY}" ]]; then
    echo "[WARN] Potentially permissive UFW rules:"
    echo "${UFR_RISKY}" | sed 's/^/  /'
    SCAN_WARN=$((SCAN_WARN + 1))
else
    echo "[PASS] UFW rules look restrictive (only OpenSSH + 443 open to public)."
    SCAN_PASS=$((SCAN_PASS + 1))
fi
```

## 4. Container Security Audit

```bash
echo ""
echo "=== Container Security Posture ==="

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SERVICE_NAME}"; then
    # Check if running as root
    USER=$(docker inspect "${SERVICE_NAME}" --format '{{.Config.User}}' 2>/dev/null)
    if [[ -z "${USER}" || "${USER}" == "" || "${USER}" == "0" ]]; then
        echo "[WARN] Container running as root. Consider using a non-root USER."
        SCAN_WARN=$((SCAN_WARN + 1))
    else
        echo "[PASS] Container running as user: ${USER}"
        SCAN_PASS=$((SCAN_PASS + 1))
    fi

    # Check for privileged mode
    PRIVILEGED=$(docker inspect "${SERVICE_NAME}" --format '{{.HostConfig.Privileged}}' 2>/dev/null)
    if [[ "${PRIVILEGED}" == "true" ]]; then
        echo "[FAIL] Container running in privileged mode!"
        SCAN_FAIL=$((SCAN_FAIL + 1))
    else
        echo "[PASS] Not privileged."
        SCAN_PASS=$((SCAN_PASS + 1))
    fi

    # Check CapDrop
    CAP_DROP=$(docker inspect "${SERVICE_NAME}" --format '{{.HostConfig.CapDrop}}' 2>/dev/null)
    if echo "${CAP_DROP}" | grep -q 'ALL'; then
        echo "[PASS] cap_drop: ALL configured."
        SCAN_PASS=$((SCAN_PASS + 1))
    else
        echo "[WARN] cap_drop: ALL not set. Consider adding for defense-in-depth."
        SCAN_WARN=$((SCAN_WARN + 1))
    fi

    # Check read-only rootfs
    READONLY=$(docker inspect "${SERVICE_NAME}" --format '{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null)
    echo "  Readonly rootfs: ${READONLY}"
fi
```

## 5. Dependency Vulnerability Scan

```bash
echo ""
echo "=== Known Vulnerability Scan ==="

if [[ -f "${REPO_PATH}/package.json" ]]; then
    echo "Running npm audit on ${SERVICE_NAME}..."
    cd "${REPO_PATH}"
    npm audit --audit-level=high 2>/dev/null | tail -20 || echo "  npm audit skipped (no package-lock or network)"
fi

if [[ -f "${REPO_PATH}/requirements.txt" ]]; then
    echo "Python dependencies listed. Run safety check manually:"
    echo "  safety check -r ${REPO_PATH}/requirements.txt"
fi

# Check image age
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SERVICE_NAME}"; then
    CREATED=$(docker inspect "${SERVICE_NAME}" --format '{{.Created}}' 2>/dev/null)
    echo "Container created: ${CREATED}"
    CREATED_UNIX=$(date -d "${CREATED}" +%s 2>/dev/null || echo 0)
    NOW_UNIX=$(date +%s)
    AGE_DAYS=$(( (NOW_UNIX - CREATED_UNIX) / 86400 ))
    if [[ "${AGE_DAYS}" -gt 30 ]]; then
        echo "[WARN] Container image is ${AGE_DAYS} days old. Consider rebuilding."
        SCAN_WARN=$((SCAN_WARN + 1))
    fi
fi
```

## 6. TLS / Certificate Check

```bash
echo ""
echo "=== TLS Certificate Check ==="
if docker inspect "${SERVICE_NAME}" 2>/dev/null | grep -q '443'; then
    # Check if cert paths exist
    for cert_path in /etc/letsencrypt/live /etc/ssl/certs /opt/wheeler/configs/certs; do
        if [[ -d "${cert_path}" ]]; then
            echo "Cert directory present: ${cert_path}"
            ls "${cert_path}" 2>/dev/null | head -5 | sed 's/^/  /'
        fi
    done
fi
```

## 7. Write Security Report

```bash
SEC_REPORT="/var/log/wheeler/repo-router/security/${SERVICE_NAME}-security.json"
cat > "${SEC_REPORT}" <<-EOF
{
  "service": "${SERVICE_NAME}",
  "pass": ${SCAN_PASS},
  "fail": ${SCAN_FAIL},
  "warn": ${SCAN_WARN},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "overall": "$( [[ ${SCAN_FAIL} -eq 0 ]] && echo 'PASS' || echo 'FAIL' )"
}
EOF

echo ""
echo "=== Security Scan Summary ==="
echo "  PASS: ${SCAN_PASS} | FAIL: ${SCAN_FAIL} | WARN: ${SCAN_WARN}"
echo ""
if [[ ${SCAN_FAIL} -gt 0 ]]; then
    echo "** ${SCAN_FAIL} security failures must be resolved before production deployment. **"
fi

echo ""
echo "PHASE-05 COMPLETE: Security scan finished for ${SERVICE_NAME}"
echo "Report: ${SEC_REPORT}"
```
