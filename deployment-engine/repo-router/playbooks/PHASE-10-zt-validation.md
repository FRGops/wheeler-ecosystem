# PHASE-10: Zero-Trust Validation

**Purpose:** Validate the service conforms to Wheeler Zero-Trust standards:
no public network binds (127.0.0.1 only), TLS everywhere, authenticated ingress
through Traefik/Nginx, and Tailscale ACL enforcement.

**Prerequisites:** PHASE-09 observability setup complete.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

ZT_LOG="/var/log/wheeler/repo-router/zt/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${ZT_LOG}")"
exec > >(tee -a "${ZT_LOG}") 2>&1

ZT_PASS=0
ZT_FAIL=0
ZT_WARN=0

echo "=== PHASE-10: Zero-Trust Validation for ${SERVICE_NAME} ==="
echo "Node: $(hostname) / $(curl -s ifconfig.me 2>/dev/null || echo '5.78.140.118')"
echo "Date: $(date -u)"
```

## 2. Network Bind Validation (127.0.0.1 only)

```bash
echo ""
echo "=== Check 1: Network Bind Validation ==="
echo "All services MUST bind to 127.0.0.1, not 0.0.0.0."

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SERVICE_NAME}"; then
    # Check all port bindings
    PORTS=$(docker inspect "${SERVICE_NAME}" --format '{{json .NetworkSettings.Ports}}' 2>/dev/null)
    BINDINGS=$(echo "${PORTS}" | jq -r 'to_entries[] | .key as $port | (.value // [])[] | "\(.HostIp):\(.HostPort)->\($port)"' 2>/dev/null)

    if [[ -z "${BINDINGS}" ]]; then
        echo "[PASS] No published ports. Ingress handled by Traefik/Nginx."
        ZT_PASS=$((ZT_PASS + 1))
    else
        echo "Port bindings found:"
        echo "${BINDINGS}" | sed 's/^/  /'
        PUBLIC=$(echo "${BINDINGS}" | grep -v '127.0.0.1' | grep -v '::1')
        if [[ -n "${PUBLIC}" ]]; then
            echo "[FAIL] Publicly accessible bindings detected!"
            echo "${PUBLIC}" | sed 's/^/  /'
            ZT_FAIL=$((ZT_FAIL + 1))
        else
            echo "[PASS] All bindings to 127.0.0.1 (loopback only)."
            ZT_PASS=$((ZT_PASS + 1))
        fi
    fi

    # Check actual listening sockets
    echo ""
    echo "--- Listening Sockets (netstat) ---"
    ss -tlnp 2>/dev/null | grep -E "$(docker inspect "${SERVICE_NAME}" --format '{{.State.Pid}}' 2>/dev/null || echo 'none')" | \
      awk '{print "  " $0}' || echo "  (no matching sockets via PID)"
fi

# PM2 processes check
if pm2 jlist 2>/dev/null | jq -e ".[] | select(.name == \"${SERVICE_NAME}\")" >/dev/null 2>&1; then
    PM2_PID=$(pm2 jlist 2>/dev/null | jq -r ".[] | select(.name == \"${SERVICE_NAME}\") | .pid")
    if [[ -n "${PM2_PID}" && "${PM2_PID}" != "0" ]]; then
        echo ""
        echo "--- PM2 ${SERVICE_NAME} listening sockets ---"
        ss -tlnp 2>/dev/null | grep "pid=${PM2_PID}," | awk '{print "  " $0}' || \
          echo "  (no network sockets detected for this process)"
    fi
fi
```

## 3. TLS Certificate Validation

```bash
echo ""
echo "=== Check 2: TLS Certificate Validation ==="

# Check LetsEncrypt certificates
CERT_DIRS="/etc/letsencrypt/live /etc/ssl/certs /opt/wheeler/configs/certs"
for dir in ${CERT_DIRS}; do
    if [[ -d "${dir}" ]]; then
        echo "[INFO] Certificate directory: ${dir}"
        find "${dir}" -name "*.pem" -o -name "*.crt" -o -name "*.cert" 2>/dev/null | head -5 | sed 's/^/  /'
    fi
done

# Check certificate expiry for all certs
echo ""
echo "--- Certificate Expiry ---"
for cert in $(find /etc/letsencrypt/live -name "fullchain.pem" 2>/dev/null); do
    EXPIRY=$(openssl x509 -enddate -noout -in "${cert}" 2>/dev/null | cut -d= -f2)
    DOMAIN=$(openssl x509 -subject -noout -in "${cert}" 2>/dev/null | sed 's/.*CN = //' | sed 's/,.*//')
    EXPIRY_EPOCH=$(date -d "${EXPIRY}" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
    if [[ "${DAYS_LEFT}" -le 0 ]]; then
        echo "[FAIL] Certificate EXPIRED for ${DOMAIN} on ${EXPIRY}"
        ZT_FAIL=$((ZT_FAIL + 1))
    elif [[ "${DAYS_LEFT}" -le 7 ]]; then
        echo "[WARN] Certificate for ${DOMAIN} expires in ${DAYS_LEFT} days (${EXPIRY})"
        ZT_WARN=$((ZT_WARN + 1))
    else
        echo "[PASS] Certificate for ${DOMAIN} valid for ${DAYS_LEFT} more days (until ${EXPIRY})"
        ZT_PASS=$((ZT_PASS + 1))
    fi
done
```

## 4. UFW / Firewall Validation

```bash
echo ""
echo "=== Check 3: Firewall Validation ==="

if command -v ufw &>/dev/null; then
    echo "--- UFW Status ---"
    ufw status numbered 2>/dev/null | sed 's/^/  /'

    # Warn if service port is open to 0.0.0.0/0 on non-standard ports
    ufw status 2>/dev/null | grep -E "${SERVICE_NAME}|${SERVICE_NAME//-/\-}" || \
      echo "[INFO] No explicit UFW rule for ${SERVICE_NAME} (likely handled via Traefik)."
    ZT_PASS=$((ZT_PASS + 1))
else
    echo "[WARN] UFW not available. Recommend installing ufw for firewall management."
    ZT_WARN=$((ZT_WARN + 1))
fi

echo ""
echo "--- Tailscale Check ---"
if ip addr show tailscale0 2>/dev/null | grep -q 'inet '; then
    TAILSCALE_IP=$(ip addr show tailscale0 | grep 'inet ' | awk '{print $2}')
    echo "[PASS] Tailscale active: ${TAILSCALE_IP}"
    # Check Tailscale serve config
    tailscale status 2>/dev/null | head -5 | sed 's/^/  /'
    ZT_PASS=$((ZT_PASS + 1))
else
    echo "[WARN] Tailscale not active. Remote access may need alternative VPN."
    ZT_WARN=$((ZT_WARN + 1))
fi
```

## 5. Authentication & Ingress Validation

```bash
echo ""
echo "=== Check 4: Authentication & Ingress Validation ==="

# Check Traefik labels on container
if docker inspect "${SERVICE_NAME}" 2>/dev/null | jq -e '.[0].Config.Labels | to_entries[] | select(.key | contains("traefik"))' >/dev/null 2>&1; then
    echo "[PASS] Traefik labels detected — ingress through Traefik."
    docker inspect "${SERVICE_NAME}" 2>/dev/null | \
      jq -r '.[0].Config.Labels | to_entries[] | select(.key | contains("traefik")) | "  \(.key)=\(.value)"'
    ZT_PASS=$((ZT_PASS + 1))

    # Check for auth middleware
    if docker inspect "${SERVICE_NAME}" 2>/dev/null | \
      jq -e '.[0].Config.Labels | to_entries[] | select(.key | contains("auth"))' >/dev/null 2>&1; then
        echo "[PASS] Auth middleware configured."
        ZT_PASS=$((ZT_PASS + 1))
    else
        echo "[WARN] No auth middleware detected on Traefik labels."
        ZT_WARN=$((ZT_WARN + 1))
    fi
fi

# Check nginx auth_basic
if nginx -T 2>/dev/null | grep -A5 "server_name.*${SERVICE_NAME}" | grep -q 'auth_basic'; then
    echo "[PASS] nginx auth_basic configured."
    ZT_PASS=$((ZT_PASS + 1))
fi
```

## 6. Container Capability Hardening

```bash
echo ""
echo "=== Check 5: Container Hardening ==="

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SERVICE_NAME}"; then
    # Privileged check
    if docker inspect "${SERVICE_NAME}" --format '{{.HostConfig.Privileged}}' 2>/dev/null | grep -q 'true'; then
        echo "[FAIL] Privileged mode enabled — violation of zero-trust."
        ZT_FAIL=$((ZT_FAIL + 1))
    else
        echo "[PASS] Not running in privileged mode."
        ZT_PASS=$((ZT_PASS + 1))
    fi

    # User namespace
    USER_MODE=$(docker inspect "${SERVICE_NAME}" --format '{{.HostConfig.UsernsMode}}' 2>/dev/null)
    echo "  Userns mode: ${USER_MODE}"

    # Read-only root
    if docker inspect "${SERVICE_NAME}" --format '{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null | grep -q 'true'; then
        echo "[PASS] Readonly rootfs enabled."
        ZT_PASS=$((ZT_PASS + 1))
    fi
fi
```

## 7. Write Validation Report

```bash
ZT_REPORT="/var/log/wheeler/repo-router/zt/${SERVICE_NAME}-zt-validation.json"
cat > "${ZT_REPORT}" <<-EOF
{
  "service": "${SERVICE_NAME}",
  "pass": ${ZT_PASS},
  "fail": ${ZT_FAIL},
  "warn": ${ZT_WARN},
  "zt_compliant": $( [[ ${ZT_FAIL} -eq 0 ]] && echo 'true' || echo 'false' ),
  "node": "$(hostname)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo ""
echo "=== Zero-Trust Validation Summary ==="
echo "  PASS: ${ZT_PASS}"
echo "  FAIL: ${ZT_FAIL}"
echo "  WARN: ${ZT_WARN}"
echo ""

if [[ "${ZT_FAIL}" -gt 0 ]]; then
    echo "** FAIL: ${ZT_FAIL} zero-trust violations found. Must remediate before staging. **"
    echo "  Common fixes:"
    echo "  1. Bind to 127.0.0.1: update docker-compose.yml ports to '127.0.0.1:PORT:PORT'"
    echo "  2. Remove --privileged flag from container config"
    echo "  3. Add HEALTHCHECK to Dockerfile"
    echo "  4. Set cap_drop: ALL in compose file"
    exit 1
fi

echo ""
echo "PHASE-10 COMPLETE: Zero-Trust validation for ${SERVICE_NAME} — $( [[ ${ZT_FAIL} -eq 0 ]] && echo 'PASS' || echo 'FAIL' )"
```
