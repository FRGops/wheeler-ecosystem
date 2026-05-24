#!/usr/bin/env bash
# =============================================================================
# deploy-monitoring-full.sh — Deploy/Upgrade Full Monitoring Stack
# =============================================================================
# This script idempotently deploys and configures the entire monitoring stack
# across both servers (Hetzner CPX51 + Hostinger VPS) via Tailscale.
#
# Usage:
#   ./deploy-monitoring-full.sh                    # Deploy everything
#   ./deploy-monitoring-full.sh --skip-prometheus  # Skip Prometheus
#   ./deploy-monitoring-full.sh --dry-run           # Show what would be done
#   ./deploy-monitoring-full.sh --upgrade           # Upgrade existing stack
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
HETZNER_TS="100.121.230.28"
HOSTINGER_TS="100.98.163.17"
MONITORING_NETWORK="monitoring-net"
DOCKER_COMPOSE_DIR="/opt/docker/monitoring"
PROMETHEUS_CONFIG_DIR="/opt/docker/monitoring/prometheus"
GRAFANA_CONFIG_DIR="/opt/docker/monitoring/grafana"
ALERTMANAGER_CONFIG_DIR="/opt/docker/monitoring/alertmanager"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $*"; }

DRY_RUN=false
SKIP_PROMETHEUS=false
UPGRADE_MODE=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --skip-prometheus) SKIP_PROMETHEUS=true ;;
    --upgrade) UPGRADE_MODE=true ;;
    --help)
      echo "Usage: $0 [--dry-run] [--skip-prometheus] [--upgrade]"
      exit 0
      ;;
  esac
done

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# STEP 0: PRECHECKS
# ---------------------------------------------------------------------------
prechecks() {
  log_step "Running prechecks..."

  # Check we're on Hetzner (or can reach it via SSH)
  if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed on this system."
    log_info "Install Docker first: https://docs.docker.com/engine/install/"
    exit 1
  fi

  if ! command -v docker compose &>/dev/null; then
    log_error "Docker Compose plugin not found."
    exit 1
  fi

  # Check Tailscale connectivity
  if ping -c 1 -W 2 "$HOSTINGER_TS" &>/dev/null; then
    log_info "Tailscale connectivity to Hostinger: OK"
  else
    log_warn "Cannot ping Hostinger via Tailscale ($HOSTINGER_TS)."
    log_warn "Continuing with Hetzner-only deployment. Hostinger exporters must be deployed manually."
  fi

  log_info "Prechecks passed."
}

# ---------------------------------------------------------------------------
# STEP 1: CREATE MONITORING NETWORK
# ---------------------------------------------------------------------------
setup_network() {
  log_step "Creating Docker network: $MONITORING_NETWORK"

  if docker network ls --format '{{.Name}}' | grep -q "^${MONITORING_NETWORK}$"; then
    log_info "Network $MONITORING_NETWORK already exists. Skipping."
  else
    run_cmd docker network create \
      --driver bridge \
      --subnet 172.30.0.0/24 \
      --label "app=monitoring" \
      "$MONITORING_NETWORK"
    log_info "Network created."
  fi
}

# ---------------------------------------------------------------------------
# STEP 2: CREATE CONFIG DIRECTORIES & COPY FILES
# ---------------------------------------------------------------------------
setup_configs() {
  log_step "Setting up configuration directories..."

  local config_dirs=(
    "$DOCKER_COMPOSE_DIR"
    "$PROMETHEUS_CONFIG_DIR"
    "$PROMETHEUS_CONFIG_DIR/rules"
    "$GRAFANA_CONFIG_DIR"
    "$GRAFANA_CONFIG_DIR/dashboards"
    "$ALERTMANAGER_CONFIG_DIR"
    "$ALERTMANAGER_CONFIG_DIR/templates"
  )

  for dir in "${config_dirs[@]}"; do
    run_cmd mkdir -p "$dir"
  done

  # Copy config files from repository
  local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local MONITORING_DIR="$(dirname "$SCRIPT_DIR")"

  log_info "Copying Prometheus config..."
  run_cmd cp "$MONITORING_DIR/prometheus/prometheus.yml" "$PROMETHEUS_CONFIG_DIR/prometheus.yml"
  run_cmd cp "$MONITORING_DIR/prometheus/alert-rules.yml" "$PROMETHEUS_CONFIG_DIR/rules/alert-rules.yml"

  log_info "Copying AlertManager config..."
  run_cmd cp "$MONITORING_DIR/prometheus/alertmanager.yml" "$ALERTMANAGER_CONFIG_DIR/alertmanager.yml"

  # Create Slack notification template for AlertManager
  if [ ! -f "$ALERTMANAGER_CONFIG_DIR/templates/slack.tmpl" ]; then
    log_info "Creating AlertManager Slack template..."
    run_cmd cat > "$ALERTMANAGER_CONFIG_DIR/templates/slack.tmpl" << 'TMPL'
{{ define "slack.default.title" }}
  [{{ .Status | toUpper }}] {{ .GroupLabels.alertname }} — {{ .GroupLabels.server }}
{{ end }}

{{ define "slack.default.text" }}
{{ range .Alerts }}
  • *Alert:* {{ .Labels.alertname }}
  • *Severity:* {{ .Labels.severity }}
  • *Instance:* {{ .Labels.instance }}
  • *Server:* {{ .Labels.server }}
  • *Description:* {{ .Annotations.description }}
  • *Graph:* {{ .Annotations.grafana_url }}
  • *Time:* {{ .StartsAt.Format "2006-01-02 15:04:05 UTC" }}
{{ end }}
{{ end }}

{{ define "slack.critical.text" }}
🚨 *CRITICAL ALERT* 🚨
{{ template "slack.default.text" . }}
{{ end }}

{{ define "slack.warning.text" }}
⚠️ *Warning Alert*
{{ template "slack.default.text" . }}
{{ end }}

{{ define "slack.ssl.text" }}
🔒 *SSL Certificate Alert*
{{ template "slack.default.text" . }}
{{ end }}

{{ define "pagerduty.default.description" }}
  {{ .GroupLabels.alertname }} on {{ .GroupLabels.server }}
  {{ range .Alerts }}
    • {{ .Annotations.description }}
  {{ end }}
{{ end }}
TMPL
  fi

  log_info "Copying Grafana config..."
  run_cmd cp "$MONITORING_DIR/grafana/datasources.yml" "$GRAFANA_CONFIG_DIR/datasources.yml"
  run_cmd cp "$MONITORING_DIR/grafana/dashboards.yml" "$GRAFANA_CONFIG_DIR/dashboards.yml"

  log_info "Copying Grafana dashboards..."
  run_cmd cp "$MONITORING_DIR/grafana/dashboards/"*.json "$GRAFANA_CONFIG_DIR/dashboards/"

  log_info "Copying Uptime Kuma backup..."
  run_cmd cp "$MONITORING_DIR/uptime-kuma/uptime-kuma-backup.json" "$DOCKER_COMPOSE_DIR/uptime-kuma-backup.json"

  log_info "Config files deployed."
}

# ---------------------------------------------------------------------------
# STEP 3: WRITE DOCKER COMPOSE FOR MONITORING STACK
# ---------------------------------------------------------------------------
setup_docker_compose() {
  log_step "Creating Docker Compose file..."

  if [ ! -f "$DOCKER_COMPOSE_DIR/docker-compose.yml" ] || [ "$UPGRADE_MODE" = true ]; then
    run_cmd cat > "$DOCKER_COMPOSE_DIR/docker-compose.yml" << 'COMPOSE'
# =============================================================================
# Monitoring Stack — Docker Compose
# =============================================================================
# Components:
#   - Prometheus (metrics + alert evaluation)
#   - AlertManager (notification routing)
#   - Grafana (dashboards + visualizations)
#   - Node Exporter (system metrics — runs on host too)
#   - cAdvisor (container metrics)
#   - Postgres Exporter (DB metrics)
#   - Redis Exporter (cache metrics)
#   - Blackbox Exporter (synthetic checks)
#   - Uptime Kuma (synthetic monitoring + status page)
# =============================================================================

version: '3.8'

networks:
  monitoring-net:
    external: true
    name: monitoring-net

volumes:
  prometheus_data:
    driver: local
  grafana_data:
    driver: local
  alertmanager_data:
    driver: local
  uptime_kuma_data:
    driver: local

services:

  # ---------------------------------------------------------------------------
  # PROMETHEUS — Metrics collection & alert evaluation
  # ---------------------------------------------------------------------------
  prometheus:
    image: prom/prometheus:v2.47.0
    container_name: prometheus
    restart: unless-stopped
    networks:
      - monitoring-net
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/rules:/etc/prometheus/rules:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--storage.tsdb.retention.size=10GB'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.enable-lifecycle'  # Allow reload via curl -X POST localhost:9090/-/reload
      - '--web.enable-admin-api'  # For snapshot/delete API
    labels:
      - "app=monitoring"
      - "component=prometheus"
    healthcheck:
      test: ["CMD", "wget", "-q", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ---------------------------------------------------------------------------
  # ALERTMANAGER — Alert routing to Slack, PagerDuty, Email
  # ---------------------------------------------------------------------------
  alertmanager:
    image: prom/alertmanager:v0.26.0
    container_name: alertmanager
    restart: unless-stopped
    networks:
      - monitoring-net
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - ./alertmanager/templates:/etc/alertmanager/templates:ro
      - alertmanager_data:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
      - '--web.external-url=https://alertmanager.wheeler.ai'
      - '--cluster.listen-address='  # Disable clustering for single instance
      - '--log.level=info'
    labels:
      - "app=monitoring"
      - "component=alertmanager"
    healthcheck:
      test: ["CMD", "wget", "-q", "http://localhost:9093/-/healthy"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ---------------------------------------------------------------------------
  # GRAFANA — Dashboards & visualizations
  # ---------------------------------------------------------------------------
  grafana:
    image: grafana/grafana:10.2.3
    container_name: grafana
    restart: unless-stopped
    networks:
      - monitoring-net
    ports:
      - "3002:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
      - GF_USERS_DEFAULT_THEME=dark
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
      - GF_SERVER_ROOT_URL=https://grafana.wheeler.ai
      - GF_SERVER_SERVE_FROM_SUB_PATH=false
      - GF_AUTH_ANONYMOUS_ENABLED=false
      - GF_PROVISIONING_ENABLED=true
      - GF_DATE_FORMATS_DEFAULT_TIMEZONE=UTC
    volumes:
      - ./grafana/datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml:ro
      - ./grafana/dashboards.yml:/etc/grafana/provisioning/dashboards/dashboards.yml:ro
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards/dashboards:ro
      - grafana_data:/var/lib/grafana
    labels:
      - "app=monitoring"
      - "component=grafana"
    healthcheck:
      test: ["CMD", "wget", "-q", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ---------------------------------------------------------------------------
  # POSTGRES EXPORTER — Multiple instances via different ports
  # ---------------------------------------------------------------------------
  postgres-exporter-aiops:
    image: prometheuscommunity/postgres-exporter:v0.14.0
    container_name: postgres-exporter-aiops
    restart: unless-stopped
    networks:
      - monitoring-net
    ports:
      - "9187:9187"
    environment:
      DATA_SOURCE_NAME: "postgresql://postgres:${POSTGRES_AIOPS_PASSWORD}@100.121.230.28:5432/postgres?sslmode=disable"
    labels:
      - "app=monitoring"
      - "component=postgres-exporter"
      - "db=aiops"

  postgres-exporter-radar:
    image: prometheuscommunity/postgres-exporter:v0.14.0
    container_name: postgres-exporter-radar
    restart: unless-stopped
    networks:
      - monitoring-net
    ports:
      - "9188:9187"
    environment:
      DATA_SOURCE_NAME: "postgresql://postgres:${POSTGRES_RADAR_PASSWORD}@100.121.230.28:5433/postgres?sslmode=disable"
    labels:
      - "app=monitoring"
      - "component=postgres-exporter"
      - "db=prediction_radar"

  postgres-exporter-ravynai:
    image: prometheuscommunity/postgres-exporter:v0.14.0
    container_name: postgres-exporter-ravynai
    restart: unless-stopped
    networks:
      - monitoring-net
    ports:
      - "9189:9187"
    environment:
      DATA_SOURCE_NAME: "postgresql://postgres:${POSTGRES_RAVYNAI_PASSWORD}@100.121.230.28:5434/postgres?sslmode=disable"
    labels:
      - "app=monitoring"
      - "component=postgres-exporter"
      - "db=ravynai"

  # ---------------------------------------------------------------------------
  # REDIS EXPORTER — Multiple instances
  # ---------------------------------------------------------------------------
  redis-exporter-aiops:
    image: oliver006/redis_exporter:v1.56.0
    container_name: redis-exporter-aiops
    restart: unless-stopped
    networks:
      - monitoring-net
    ports:
      - "9121:9121"
    command:
      - '--redis.addr=redis://100.121.230.28:6379'
      - '--redis.password=${REDIS_AIOPS_PASSWORD}'
    labels:
      - "app=monitoring"
      - "component=redis-exporter"
      - "redis=aiops"

  redis-exporter-radar:
    image: oliver006/redis_exporter:v1.56.0
    container_name: redis-exporter-radar
    restart: unless-stopped
    networks:
      - monitoring-net
    ports:
      - "9122:9121"
    command:
      - '--redis.addr=redis://100.121.230.28:6380'
      - '--redis.password=${REDIS_RADAR_PASSWORD}'
    labels:
      - "app=monitoring"
      - "component=redis-exporter"
      - "redis=prediction_radar"

  # ---------------------------------------------------------------------------
  # BLACKBOX EXPORTER — Synthetic checks
  # ---------------------------------------------------------------------------
  blackbox-exporter:
    image: prom/blackbox-exporter:v0.24.0
    container_name: blackbox-exporter
    restart: unless-stopped
    networks:
      - monitoring-net
    ports:
      - "9115:9115"
    command:
      - '--config.file=/config/blackbox.yml'
    volumes:
      - ./blackbox/blackbox.yml:/config/blackbox.yml:ro
    labels:
      - "app=monitoring"
      - "component=blackbox"

  # ---------------------------------------------------------------------------
  # UPTIME KUMA — Synthetic monitoring + status page
  # ---------------------------------------------------------------------------
  uptime-kuma:
    image: louislam/uptime-kuma:1.23
    container_name: uptime-kuma
    restart: unless-stopped
    networks:
      - monitoring-net
    ports:
      - "3001:3001"
    volumes:
      - uptime_kuma_data:/app/data
    labels:
      - "app=monitoring"
      - "component=uptime-kuma"
    healthcheck:
      test: ["CMD", "node", "extra/healthcheck.js"]
      interval: 30s
      timeout: 10s
      retries: 3
COMPOSE

    # Create blackbox exporter config
    mkdir -p "$DOCKER_COMPOSE_DIR/blackbox"
    cat > "$DOCKER_COMPOSE_DIR/blackbox/blackbox.yml" << 'BLACKBOX'
modules:
  http_2xx:
    prober: http
    timeout: 10s
    http:
      preferred_ip_protocol: ip4
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 201, 202, 204, 301, 302, 303, 307, 308]
      follow_redirects: true
      fail_if_ssl: false
      tls_config:
        insecure_skip_verify: false

  http_post_2xx:
    prober: http
    timeout: 10s
    http:
      method: POST
      preferred_ip_protocol: ip4
      valid_status_codes: [200, 201, 202, 204]

  tcp_connect:
    prober: tcp
    timeout: 5s

  icmp:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: ip4
BLACKBOX

    log_info "Docker Compose file written."
  else
    log_info "Docker Compose file exists. Use --upgrade to overwrite."
  fi
}

# ---------------------------------------------------------------------------
# STEP 4: DEPLOY NODE EXPORTER ON BOTH SERVERS
# ---------------------------------------------------------------------------
deploy_node_exporter() {
  log_step "Deploying Node Exporter..."

  local TARGET_IP="$1"
  local TARGET_NAME="$2"

  # Deploy via SSH or locally
  if [ "$TARGET_IP" = "localhost" ]; then
    deploy_node_exporter_local
  else
    if [ "$DRY_RUN" = true ]; then
      echo -e "${YELLOW}[DRY-RUN]${NC} Would deploy Node Exporter on $TARGET_NAME ($TARGET_IP)"
      echo -e "${YELLOW}[DRY-RUN]${NC}   docker run -d ... prom/node-exporter on $TARGET_IP"
    else
      # Use systemd service for node_exporter (preferred — runs standalone, no Docker dependency)
      log_info "Deploying node_exporter systemd service on $TARGET_NAME..."
      ssh -o StrictHostKeyChecking=no "root@$TARGET_IP" bash -s << 'NODE_SETUP'
        set -euo pipefail

        # Download node_exporter if not present
        if [ ! -f /usr/local/bin/node_exporter ]; then
          cd /tmp
          wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
          tar xzf node_exporter-1.7.0.linux-amd64.tar.gz
          cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/node_exporter
          chmod 755 /usr/local/bin/node_exporter
          rm -rf node_exporter-1.7.0*
        fi

        # Create systemd service
        cat > /etc/systemd/system/node_exporter.service << 'SERVICE'
[Unit]
Description=Prometheus Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address=:9100 \
  --path.rootfs=/ \
  --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($|/) \
  --collector.textfile.directory=/var/lib/node_exporter/textfile_collector \
  --no-collector.softnet \
  --no-collector.nfs \
  --no-collector.nfsd
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

        # Create textfile collector directory for scripts
        mkdir -p /var/lib/node_exporter/textfile_collector

        # Reload and enable
        systemctl daemon-reload
        systemctl enable node_exporter
        systemctl restart node_exporter

        # Verify
        sleep 2
        if systemctl is-active --quiet node_exporter; then
          echo "node_exporter is RUNNING on $(hostname)"
        else
          echo "node_exporter FAILED to start"
          systemctl status node_exporter --no-pager
          exit 1
        fi
NODE_SETUP
      log_info "Node exporter deployed on $TARGET_NAME."
    fi
  fi
}

deploy_node_exporter_local() {
  # Same as above but local — skip SSH
  if [ ! -f /usr/local/bin/node_exporter ]; then
    cd /tmp
    wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
    tar xzf node_exporter-1.7.0.linux-amd64.tar.gz
    cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/node_exporter
    chmod 755 /usr/local/bin/node_exporter
    rm -rf node_exporter-1.7.0*
  fi

  cat > /etc/systemd/system/node_exporter.service << 'SERVICE'
[Unit]
Description=Prometheus Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address=:9100 \
  --path.rootfs=/ \
  --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($|/) \
  --collector.textfile.directory=/var/lib/node_exporter/textfile_collector \
  --no-collector.softnet \
  --no-collector.nfs \
  --no-collector.nfsd
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

  mkdir -p /var/lib/node_exporter/textfile_collector
  systemctl daemon-reload
  systemctl enable node_exporter
  systemctl restart node_exporter

  sleep 2
  if systemctl is-active --quiet node_exporter; then
    log_info "node_exporter is RUNNING locally."
  else
    log_error "node_exporter FAILED to start locally."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# STEP 5: DEPLOY CADVISOR ON BOTH SERVERS
# ---------------------------------------------------------------------------
deploy_cadvisor() {
  log_step "Deploying cAdvisor..."

  local TARGET_IP="$1"
  local TARGET_NAME="$2"

  local RUN_CMD="docker run -d --restart=always \
    --name=cadvisor \
    --network=monitoring-net \
    -p 8080:8080 \
    -v /:/rootfs:ro \
    -v /var/run:/var/run:ro \
    -v /sys:/sys:ro \
    -v /var/lib/docker/:/var/lib/docker:ro \
    -v /dev/disk/:/dev/disk:ro \
    --privileged \
    --device=/dev/kmsg \
    gcr.io/cadvisor/cadvisor:v0.47.2 \
    --docker_only=true \
    --housekeeping_interval=10s"

  if [ "$TARGET_IP" = "localhost" ]; then
    if docker ps --format '{{.Names}}' | grep -q "^cadvisor$"; then
      log_info "cAdvisor already running locally. Restarting..."
      run_cmd docker restart cadvisor
    else
      run_cmd $RUN_CMD
      log_info "cAdvisor started locally."
    fi
  else
    if [ "$DRY_RUN" = true ]; then
      echo -e "${YELLOW}[DRY-RUN]${NC} Would deploy cAdvisor on $TARGET_NAME"
    else
      ssh -o StrictHostKeyChecking=no "root@$TARGET_IP" "$RUN_CMD" || log_warn "cAdvisor deployment on $TARGET_NAME may have failed."
    fi
  fi
}

# ---------------------------------------------------------------------------
# STEP 6: DEPLOY PROMETHEUS/ALERTMANAGER/GRAFANA STACK
# ---------------------------------------------------------------------------
deploy_monitoring_stack() {
  log_step "Deploying monitoring stack (Prometheus, AlertManager, Grafana, etc.)..."

  if [ "$SKIP_PROMETHEUS" = true ]; then
    log_info "Skipping Prometheus stack deployment (--skip-prometheus)."
    return
  fi

  # Create environment file if not exists
  if [ ! -f "$DOCKER_COMPOSE_DIR/.env" ]; then
    log_info "Creating .env file with placeholder passwords..."
    cat > "$DOCKER_COMPOSE_DIR/.env" << 'ENV'
# PostgreSQL passwords — REPLACE with actual passwords
POSTGRES_AIOPS_PASSWORD=change_me
POSTGRES_RADAR_PASSWORD=change_me
POSTGRES_RAVYNAI_PASSWORD=change_me

# Redis passwords — REPLACE with actual passwords
REDIS_AIOPS_PASSWORD=change_me
REDIS_RADAR_PASSWORD=change_me

# Grafana admin password
GRAFANA_ADMIN_PASSWORD=admin

# Slack webhook — REPLACE with actual URL
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/your/webhook/here

# PagerDuty — REPLACE with actual key
PAGERDUTY_ROUTING_KEY=your_pagerduty_key_here
ENV
    log_warn ".env file created with placeholder values. Edit $DOCKER_COMPOSE_DIR/.env before starting."
  fi

  # Pull images and start
  cd "$DOCKER_COMPOSE_DIR"
  run_cmd docker compose pull
  run_cmd docker compose up -d

  log_info "Monitoring stack deployed. Waiting for services to be healthy..."

  # Wait for Prometheus
  for i in {1..12}; do
    if curl -sf http://localhost:9090/-/healthy >/dev/null 2>&1; then
      log_info "Prometheus is healthy."
      break
    fi
    sleep 5
  done

  # Wait for AlertManager
  for i in {1..6}; do
    if curl -sf http://localhost:9093/-/healthy >/dev/null 2>&1; then
      log_info "AlertManager is healthy."
      break
    fi
    sleep 5
  done

  # Wait for Grafana
  for i in {1..12}; do
    if curl -sf http://localhost:3002/api/health >/dev/null 2>&1; then
      log_info "Grafana is healthy."
      break
    fi
    sleep 5
  done
}

# ---------------------------------------------------------------------------
# STEP 7: DEPLOY BACKUP TIMESTAMP COLLECTOR
# ---------------------------------------------------------------------------
setup_backup_collector() {
  log_step "Setting up backup timestamp collector..."

  # Create a textfile collector that exposes backup timestamp
  mkdir -p /var/lib/node_exporter/textfile_collector

  run_cmd cat > /usr/local/bin/backup_timestamp_collector.sh << 'COLLECTOR'
#!/usr/bin/env bash
# Exposes last backup timestamp for Prometheus node_exporter textfile collector
set -euo pipefail

OUTPUT_FILE="/var/lib/node_exporter/textfile_collector/backup.prom"
BACKUP_DIR="/opt/backups/databases"

if [ -d "$BACKUP_DIR" ]; then
  LATEST_BACKUP=$(find "$BACKUP_DIR" -name "*.dump" -o -name "*.sql.gz" 2>/dev/null | sort -r | head -1)
  if [ -n "$LATEST_BACKUP" ]; then
    MTIME=$(stat -c %Y "$LATEST_BACKUP" 2>/dev/null || echo 0)
    echo "node_textfile_mtime_seconds{file=\"backup_timestamp\"} $MTIME" > "$OUTPUT_FILE"
    echo "backup_latest_file{path=\"$LATEST_BACKUP\"} 1" >> "$OUTPUT_FILE"
  else
    echo "node_textfile_mtime_seconds{file=\"backup_timestamp\"} 0" > "$OUTPUT_FILE"
  fi
else
  echo "node_textfile_mtime_seconds{file=\"backup_timestamp\"} 0" > "$OUTPUT_FILE"
fi
COLLECTOR
  chmod +x /usr/local/bin/backup_timestamp_collector.sh

  # Add cron job (runs every 5 minutes)
  if ! crontab -l 2>/dev/null | grep -q "backup_timestamp_collector"; then
    (crontab -l 2>/dev/null || true; echo "*/5 * * * * /usr/local/bin/backup_timestamp_collector.sh") | crontab -
    log_info "Backup timestamp collector cron installed."
  fi

  # Run once immediately
  /usr/local/bin/backup_timestamp_collector.sh
  log_info "Backup timestamp collected."
}

# ---------------------------------------------------------------------------
# STEP 8: VERIFY ALL TARGETS
# ---------------------------------------------------------------------------
verify_targets() {
  log_step "Verifying all monitoring targets..."

  echo ""
  echo "========================================================"
  echo "  Monitoring Stack — Target Verification"
  echo "========================================================"
  echo ""

  # Check Prometheus targets via API
  if command -v curl &>/dev/null; then
    echo "Prometheus Targets:"
    curl -sf 'http://localhost:9090/api/v1/targets' 2>/dev/null | \
      python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    status = 'UP' if t['health'] == 'up' else 'DOWN'
    job = t['labels']['job']
    instance = t['labels']['instance']
    print(f'  [{status:4s}] {job:20s} {instance}')
" 2>/dev/null || echo "  (Unable to query Prometheus API)"
  fi

  echo ""
  echo "Local Docker Containers:"
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" --filter "label=app=monitoring" 2>/dev/null || true

  echo ""
  echo "Grafana Datasources:"
  curl -sf -u "admin:$GRAFANA_ADMIN_PASSWORD" 'http://localhost:3002/api/datasources' 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for d in data:
    print(f'  {d[\"name\"]:25s} type={d[\"type\"]:15s} url={d[\"url\"]}')
" 2>/dev/null || echo "  (Unable to query Grafana API)"

  echo ""
  echo "========================================================"
  echo "  Verification Complete"
  echo "========================================================"
}

# ---------------------------------------------------------------------------
# STEP 9: OUTPUT DASHBOARD URLS
# ---------------------------------------------------------------------------
output_urls() {
  echo ""
  echo "========================================================"
  echo "  Monitoring Stack — Dashboard URLs"
  echo "========================================================"
  echo ""
  echo "  Grafana:        https://grafana.wheeler.ai"
  echo "  Prometheus:     http://100.121.230.28:9090  (Tailscale only)"
  echo "  AlertManager:   http://100.121.230.28:9093  (Tailscale only)"
  echo "  Uptime Kuma:    https://uptime.wheeler.ai"
  echo "  Netdata:        http://100.121.230.28:19999 (Tailscale only)"
  echo ""
  echo "  AIOps Overview:     https://grafana.wheeler.ai/d/aiops-overview"
  echo "  Prediction Radar:   https://grafana.wheeler.ai/d/prediction-radar"
  echo "  RavynAI:            https://grafana.wheeler.ai/d/ravynai"
  echo "  Trading Engine:     https://grafana.wheeler.ai/d/trading"
  echo ""
  echo "  Status Page:        https://uptime.wheeler.ai/status"
  echo ""
  echo "========================================================"
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo "========================================================"
  echo "  Monitoring Stack — Full Deployment"
  echo "  Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "LIVE")"
  echo "========================================================"
  echo ""

  prechecks
  setup_network
  setup_configs
  setup_docker_compose

  # Deploy node_exporter locally (Hetzner)
  deploy_node_exporter "localhost" "hetzner-cpx51"

  # Deploy node_exporter on Hostinger via Tailscale SSH
  if ping -c 1 -W 2 "$HOSTINGER_TS" &>/dev/null; then
    deploy_node_exporter "$HOSTINGER_TS" "hostinger-vps"
  else
    log_warn "Cannot reach Hostinger. Deploy node_exporter manually:"
    log_warn "  ssh root@$HOSTINGER_TS 'bash -s' < deploy-monitoring-full.sh"
  fi

  # Deploy cAdvisor
  deploy_cadvisor "localhost" "hetzner-cpx51"
  if ping -c 1 -W 2 "$HOSTINGER_TS" &>/dev/null; then
    deploy_cadvisor "$HOSTINGER_TS" "hostinger-vps"
  fi

  # Deploy the Docker Compose monitoring stack
  deploy_monitoring_stack

  # Setup backup collector
  setup_backup_collector

  # Verify everything
  verify_targets
  output_urls

  echo ""
  log_info "Deployment complete!"
  echo ""
  log_info "Next steps:"
  echo "  1. Edit $DOCKER_COMPOSE_DIR/.env with actual passwords"
  echo "  2. docker compose -f $DOCKER_COMPOSE_DIR/docker-compose.yml restart"
  echo "  3. Configure Slack webhook in AlertManager config"
  echo "  4. Import Uptime Kuma backup from $DOCKER_COMPOSE_DIR/uptime-kuma-backup.json"
  echo "  5. Run ./health-check-endpoints.sh to verify all health endpoints"
  echo ""
}

main "$@"
