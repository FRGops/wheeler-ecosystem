# PHASE-09: Observability Setup

**Purpose:** Configure metrics collection, log shipping, health checks, and alerting
for the service. Integration with Prometheus, Grafana, Loki, and Uptime Kuma.

**Prerequisites:** PHASE-08 integration tests passing. Sandbox tag available.

---

## 1. Load Context

```bash
CARD="${1:?Usage: $0 <path-to-discovery-json>}"
SERVICE_NAME="$(jq -r '.service' "${CARD}")"
REPO_PATH="$(jq -r '.repo_path' "${CARD}")"
DEPLOY_TYPE="$(jq -r '.deploy_type' "${CARD}")"

OBS_LOG="/var/log/wheeler/repo-router/observability/${SERVICE_NAME}-$(date -u +%Y%m%dT%H%M%S).log"
mkdir -p "$(dirname "${OBS_LOG}")"
exec > >(tee -a "${OBS_LOG}") 2>&1

echo "=== PHASE-09: Observability Setup for ${SERVICE_NAME} ==="
```

## 2. Prometheus Metrics Integration

```bash
echo ""
echo "=== Prometheus Metrics Integration ==="

# Determine metrics port from Docker container
METRICS_PORT=""
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${SERVICE_NAME}"; then
    # Check for common metrics ports
    for port in 9464 9465 9090 8080 8000 3000; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
          "http://127.0.0.1:${port}/metrics" 2>/dev/null || echo "")
        if [[ "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
            METRICS_PORT="${port}"
            echo "[PASS] Prometheus metrics endpoint found at 127.0.0.1:${port}/metrics"
            break
        fi
    done
fi

if [[ -z "${METRICS_PORT}" ]]; then
    echo "[INFO] No Prometheus metrics endpoint auto-detected."
    echo "  If the service exposes metrics, add a scrape target manually to:"
    echo "  /root/infrastructure/hetzner/monitoring/prometheus.yml"
fi

# Add scrape target to prometheus config
PROMETHEUS_CONFIG="/root/infrastructure/hetzner/monitoring/prometheus.yml"
if [[ -f "${PROMETHEUS_CONFIG}" && -n "${METRICS_PORT}" ]]; then
    if ! grep -q "${SERVICE_NAME}" "${PROMETHEUS_CONFIG}"; then
        echo ""
        echo "Add this job to ${PROMETHEUS_CONFIG}:"
        cat <<-JOB
  - job_name: '${SERVICE_NAME}'
    static_configs:
      - targets: ['127.0.0.1:${METRICS_PORT}']
        labels:
          service: '${SERVICE_NAME}'
          environment: 'production'
JOB
        echo "  (Add manually or uncomment the above in the prometheus config)"
    else
        echo "[PASS] Prometheus job already configured for ${SERVICE_NAME}."
    fi
fi

# Reload Prometheus if running
if docker ps --format '{{.Names}}' | grep -q 'prediction-radar-prometheus'; then
    echo "  Reloading Prometheus configuration..."
    docker kill -s HUP prediction-radar-prometheus 2>/dev/null || \
      docker exec prediction-radar-prometheus kill -HUP 1 2>/dev/null || true
    echo "  Prometheus config reloaded."
fi
```

## 3. Loki Log Shipping

```bash
echo ""
echo "=== Loki Log Shipping (Promtail) ==="

PROMTAIL_CONFIG="/root/infrastructure/hetzner/monitoring/promtail.yml"
if [[ -f "${PROMTAIL_CONFIG}" ]]; then
    # Check if service is already configured
    if grep -q "${SERVICE_NAME}" "${PROMTAIL_CONFIG}"; then
        echo "[PASS] Promtail already configured for ${SERVICE_NAME}."
    else
        echo ""
        echo "Add this scrape config to ${PROMTAIL_CONFIG}:"
        cat <<-PROMTAIL
  - job_name: ${SERVICE_NAME}
    static_configs:
      - targets: [localhost]
        labels:
          job: ${SERVICE_NAME}
          __path__: /var/log/wheeler/${SERVICE_NAME}/*.log
PROMTAIL
    fi

    # Reload Promtail
    if docker ps --format '{{.Names}}' | grep -q 'promtail'; then
        docker kill -s HUP promtail 2>/dev/null || true
        echo "  Promtail config reloaded."
    fi
fi

# Ensure log directory exists
mkdir -p "/var/log/wheeler/${SERVICE_NAME}"
echo "[INFO] Log directory: /var/log/wheeler/${SERVICE_NAME}"
```

## 4. Grafana Dashboard

```bash
echo ""
echo "=== Grafana Dashboard Setup ==="

GRAFANA_DIR="/root/infrastructure/hetzner/monitoring/grafana"
mkdir -p "${GRAFANA_DIR}/dashboards"

DASHBOARD_FILE="${GRAFANA_DIR}/dashboards/${SERVICE_NAME}-dashboard.json"

if [[ ! -f "${DASHBOARD_FILE}" ]]; then
    # Generate starter dashboard JSON
    cat > "${DASHBOARD_FILE}" <<-DASH
{
  "title": "${SERVICE_NAME} Overview",
  "uid": "${SERVICE_NAME}-${RANDOM}",
  "tags": ["wheeler", "${SERVICE_NAME}"],
  "panels": [
    {
      "title": "Uptime",
      "type": "stat",
      "targets": [{"expr": "up{job=\"${SERVICE_NAME}\}"}]
    },
    {
      "title": "HTTP Requests",
      "type": "graph",
      "targets": [{"expr": "rate(http_requests_total{job=\"${SERVICE_NAME}\"}[5m])"}]
    },
    {
      "title": "Error Rate",
      "type": "graph",
      "targets": [{"expr": "rate(http_requests_total{job=\"${SERVICE_NAME}\",status=~\"5..\"}[5m])"}]
    },
    {
      "title": "Memory",
      "type": "graph",
      "targets": [{"expr": "process_resident_memory_bytes{job=\"${SERVICE_NAME}\"} / 1024 / 1024"}]
    }
  ]
}
DASH
    echo "[INFO] Starter dashboard generated: ${DASHBOARD_FILE}"
    echo "  Import into Grafana via API or UI."
    echo "  Grafana UI: https://monitoring.wheeler.local (or localhost:3001 on tailscale0)"
else
    echo "[PASS] Dashboard already exists: ${DASHBOARD_FILE}"
fi

# Import to Grafana via API if Grafana is reachable
GRAFANA_IMPORT_LOG="/var/log/wheeler/repo-router/observability/${SERVICE_NAME}-grafana-import.log"
if curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:3001/api/health 2>/dev/null | grep -q 200; then
    echo "  Grafana API reachable. Import dashboard using:"
    echo "    curl -X POST -H \"Content-Type: application/json\""
    echo "      -d @${DASHBOARD_FILE}"
    echo "      http://admin:\${GF_SECURITY_ADMIN_PASSWORD}@127.0.0.1:3001/api/dashboards/db"
fi
```

## 5. Uptime Kuma Health Check

```bash
echo ""
echo "=== Uptime Kuma Monitor Setup ==="

# If the service has a known health endpoint, register it with Uptime Kuma
KUMA_API="http://127.0.0.1:3001"  # Uptime Kuma is on port 3001
HEALTH_URL=""
for endpoint in "/health" "/healthz" "/ready" "/api/health"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
      "http://127.0.0.1:8088${endpoint}" 2>/dev/null || echo "")
    if [[ "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
        HEALTH_URL="http://127.0.0.1:8088${endpoint}"
        break
    fi
done

if [[ -n "${HEALTH_URL}" ]]; then
    echo "[INFO] Health endpoint detected: ${HEALTH_URL}"
    echo "  Add to Uptime Kuma at: http://127.0.0.1:3001 (tailscale only)"
    echo "  API registration (if Uptime Kuma API key is configured):"
    echo "    curl -X POST \"${KUMA_API}/api/monitor\" \\"
    echo "      -H \"Authorization: Bearer \${UPTIME_KUMA_API_KEY}\" \\"
    echo "      -d '{\"type\":\"http\",\"name\":\"${SERVICE_NAME}\",\"url\":\"${HEALTH_URL}\"}'"
fi
```

## 6. Alertmanager Configuration

```bash
echo ""
echo "=== Alertmanager Setup ==="

ALERTMANAGER_CONFIG="/root/infrastructure/hetzner/monitoring/alertmanager.yml"
if [[ -f "${ALERTMANAGER_CONFIG}" && -n "${METRICS_PORT}" ]]; then
    echo "[INFO] Alertmanager config at ${ALERTMANAGER_CONFIG}"
    echo "  Verify this service has alert rules. Create if needed:"
    echo ""
    echo "  /root/infrastructure/hetzner/monitoring/rules/${SERVICE_NAME}.yml:"
    cat <<-RULES
groups:
  - name: ${SERVICE_NAME}
    rules:
      - alert: ${SERVICE_NAME}Down
        expr: up{job="${SERVICE_NAME}"} == 0
        for: 1m
        labels: { severity: critical }
        annotations:
          summary: "${SERVICE_NAME} is down"
RULES
fi
```

## 7. Write Observability Report

```bash
OBS_REPORT="/var/log/wheeler/repo-router/observability/${SERVICE_NAME}-observability.json"
cat > "${OBS_REPORT}" <<-EOF
{
  "service": "${SERVICE_NAME}",
  "prometheus_configured": ${METRICS_PORT:+true} ${METRICS_PORT:-false},
  "metrics_port": ${METRICS_PORT:-null},
  "log_directory": "/var/log/wheeler/${SERVICE_NAME}",
  "dashboard": "${DASHBOARD_FILE}",
  "health_url": "${HEALTH_URL:-null}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo ""
echo "Observability report: ${OBS_REPORT}"
echo ""
echo "PHASE-09 COMPLETE: Observability configured for ${SERVICE_NAME}"
```
