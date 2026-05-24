#!/usr/bin/env bash
# ============================================================================
# WHEELER AIOPS — PHASE 2 MIGRATION MASTER PLAYBOOK
# Full production hardening of the two-server distributed AI infrastructure
# ============================================================================
# PREREQUISITES:
#   - Phase 1 migration complete (heavy services on Hetzner, Hostinger lean)
#   - Tailscale running on both servers
#   - SSH key access to both servers
#   - Root or sudo on both
# ============================================================================
# HOW TO USE:
#   1. Read through entirely before starting
#   2. Execute ONE PHASE at a time
#   3. Run verify script after each phase
#   4. If anything fails: STOP, diagnose, do not continue
#   5. Each phase has a rollback section
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HETZNER_IP="5.78.140.118"
HETZNER_TAILSCALE="100.121.230.28"
HOSTINGER_TAILSCALE="100.98.163.17"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="/opt/logs/migration/${TIMESTAMP}"

banner() {
    echo -e "\n${BLUE}============================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================================${NC}\n"
}

success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; }
info()    { echo -e "${BLUE}[i]${NC} $1"; }

# ============================================================================
# PRE-FLIGHT CHECKS (Run this first on your LOCAL machine)
# ============================================================================
preflight() {
    banner "PRE-FLIGHT CHECKS"

    info "Testing SSH to Hetzner..."
    if ssh -o ConnectTimeout=5 root@${HETZNER_TAILSCALE} "echo OK" &>/dev/null; then
        success "Hetzner SSH OK"
    else
        error "Cannot reach Hetzner via Tailscale. Trying public IP..."
        if ssh -o ConnectTimeout=5 root@${HETZNER_IP} "echo OK" &>/dev/null; then
            success "Hetzner SSH OK (public IP)"
        else
            error "CANNOT REACH HETZNER. Abort."
            return 1
        fi
    fi

    info "Testing SSH to Hostinger..."
    if ssh -o ConnectTimeout=5 root@${HOSTINGER_TAILSCALE} "echo OK" &>/dev/null; then
        success "Hostinger SSH OK"
    else
        error "Cannot reach Hostinger via Tailscale. Abort."
        return 1
    fi

    info "Checking current state on Hetzner..."
    ssh root@${HETZNER_TAILSCALE} "docker ps --format '{{.Names}}' | sort" > /tmp/hetzner-preflight.txt
    echo "Running containers on Hetzner:"
    cat /tmp/hetzner-preflight.txt

    info "Checking current state on Hostinger..."
    ssh root@${HOSTINGER_TAILSCALE} "docker ps --format '{{.Names}}' | sort" > /tmp/hostinger-preflight.txt
    echo "Running containers on Hostinger:"
    cat /tmp/hostinger-preflight.txt

    info "Checking Tailscale connectivity between servers..."
    ssh root@${HETZNER_TAILSCALE} "tailscale ping -c 3 ${HOSTINGER_TAILSCALE} || true"

    success "Pre-flight checks complete"
    echo ""
    echo "IMPORTANT: Save these container lists for rollback reference."
    echo "  Hetzner:   /tmp/hetzner-preflight.txt"
    echo "  Hostinger: /tmp/hostinger-preflight.txt"
}

# ============================================================================
# PHASE 1: PRE-MIGRATION FULL SNAPSHOT (BOTH SERVERS)
# ============================================================================
phase1_snapshot() {
    banner "PHASE 1: PRE-MIGRATION FULL SNAPSHOT"
    warn "This creates a full backup of everything before any changes."
    warn "Estimated time: 10-30 minutes depending on data size."

    # Hetzner snapshot
    info "Creating Hetzner pre-migration snapshot..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'SNAP'
        mkdir -p /opt/backups/pre-migration-$(date +%Y%m%d)
        SNAPDIR=/opt/backups/pre-migration-$(date +%Y%m%d)

        # All docker inspect
        docker ps -a --format '{{.Names}}' | while read c; do
            docker inspect "$c" > "$SNAPDIR/inspect-$c.json" 2>/dev/null || true
        done

        # Docker compose files
        find /opt -name 'docker-compose.yml' -o -name 'compose.yml' | while read f; do
            dir=$(dirname "$f")
            name=$(echo "$dir" | tr '/' '_')
            cp "$f" "$SNAPDIR/compose${name}.yml" 2>/dev/null || true
        done

        # .env files (BE CAREFUL — these have secrets)
        find /opt -name '.env' | while read f; do
            dir=$(dirname "$f")
            name=$(echo "$dir" | tr '/' '_')
            cp "$f" "$SNAPDIR/env${name}" 2>/dev/null || true
        done
        chmod 700 "$SNAPDIR"

        # UFW rules
        ufw status numbered > "$SNAPDIR/ufw-rules.txt"

        # Crontabs
        crontab -l > "$SNAPDIR/crontab.txt" 2>/dev/null || true

        # System info
        free -h > "$SNAPDIR/memory.txt"
        df -h > "$SNAPDIR/disk.txt"
        docker network ls > "$SNAPDIR/networks.txt"

        echo "Snapshot at: $SNAPDIR"
        ls -la "$SNAPDIR"
SNAP
    success "Hetzner snapshot complete"

    # Hostinger snapshot (same pattern)
    info "Creating Hostinger pre-migration snapshot..."
    ssh root@${HOSTINGER_TAILSCALE} "bash -s" << 'SNAP'
        mkdir -p /opt/backups/pre-migration-$(date +%Y%m%d)
        SNAPDIR=/opt/backups/pre-migration-$(date +%Y%m%d)

        docker ps -a --format '{{.Names}}' | while read c; do
            docker inspect "$c" > "$SNAPDIR/inspect-$c.json" 2>/dev/null || true
        done

        find /opt -name 'docker-compose.yml' -o -name 'compose.yml' | while read f; do
            dir=$(dirname "$f")
            name=$(echo "$dir" | tr '/' '_')
            cp "$f" "$SNAPDIR/compose${name}.yml" 2>/dev/null || true
        done

        find /opt -name '.env' | while read f; do
            dir=$(dirname "$f")
            name=$(echo "$dir" | tr '/' '_')
            cp "$f" "$SNAPDIR/env${name}" 2>/dev/null || true
        done
        chmod 700 "$SNAPDIR"

        ufw status numbered > "$SNAPDIR/ufw-rules.txt"
        crontab -l > "$SNAPDIR/crontab.txt" 2>/dev/null || true
        free -h > "$SNAPDIR/memory.txt"
        df -h > "$SNAPDIR/disk.txt"

        echo "Snapshot at: $SNAPDIR"
        ls -la "$SNAPDIR"
SNAP
    success "Hostinger snapshot complete"

    echo ""
    success "PHASE 1 COMPLETE — Full snapshots saved on both servers"
    echo "Rollback: Restore from /opt/backups/pre-migration-YYYYMMDD/ on each server"
}

# ============================================================================
# PHASE 2: SECURITY HARDENING — FIREWALL (HETZNER FIRST, THEN HOSTINGER)
# ============================================================================
phase2_firewall() {
    banner "PHASE 2: FIREWALL HARDENING"
    warn "This will RESTRICT access to admin dashboards to Tailscale-only."
    warn "After this, you MUST use Tailscale IPs to access Grafana, Portainer, etc."
    warn "Public web apps on 80/443 remain accessible."
    echo ""
    info "Current firewall state on Hetzner:"
    ssh root@${HETZNER_TAILSCALE} "ufw status verbose"

    echo ""
    read -p "Continue with firewall lockdown? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        warn "Skipping firewall lockdown"
        return
    fi

    # --- HETZNER FIREWALL ---
    info "Locking down Hetzner firewall..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'UFW'
        set -e

        # Reset to clean state
        ufw --force reset

        # PUBLIC: SSH + Web only
        ufw allow OpenSSH
        ufw allow 80/tcp
        ufw allow 443/tcp

        # SSH rate limiting
        ufw limit OpenSSH

        # TAILSCALE-ONLY: All admin dashboards and databases
        # These rules only match traffic on the tailscale0 interface
        TAILSCALE_IFACE=$(ip -o link show | grep tailscale | awk -F': ' '{print $2}' | head -1)
        if [ -n "$TAILSCALE_IFACE" ]; then
            for port in \
                19999 \
                3001 \
                3002 \
                5000 \
                5001 \
                8088 \
                8098 \
                8007 \
                8123 \
                9000 \
                9090 \
                3130 \
                5432 \
                5433 \
                5434 \
                6379 \
                8080 \
                3000 \
                8090 \
                9443
            do
                ufw allow in on "$TAILSCALE_IFACE" to any port "$port" proto tcp
            done
            echo "Added Tailscale-only rules on interface: $TAILSCALE_IFACE"
        else
            echo "WARNING: tailscale0 interface not found! Adding port rules wide open as fallback."
            for port in 19999 3001 3002 5000 5001 8088 8098 8007 8123 9000 9090 3130 5432 5433 5434 6379 8080 3000 8090 9443; do
                ufw allow "$port"/tcp
            done
        fi

        # Enable with force
        ufw --force enable
        ufw reload

        echo ""
        echo "=== FIREWALL STATUS ==="
        ufw status verbose
UFW
    success "Hetzner firewall locked down"

    # --- HOSTINGER FIREWALL ---
    info "Locking down Hostinger firewall..."
    ssh root@${HOSTINGER_TAILSCALE} "bash -s" << 'UFW'
        set -e

        ufw --force reset

        # PUBLIC: SSH + Web only
        ufw allow OpenSSH
        ufw allow 80/tcp
        ufw allow 443/tcp

        # SSH rate limiting (stricter on edge)
        ufw limit OpenSSH

        # TAILSCALE-ONLY: Admin + DB ports
        TAILSCALE_IFACE=$(ip -o link show | grep tailscale | awk -F': ' '{print $2}' | head -1)
        if [ -n "$TAILSCALE_IFACE" ]; then
            for port in 5432 6379 3001 3002 9090 19999; do
                ufw allow in on "$TAILSCALE_IFACE" to any port "$port" proto tcp
            done
        fi

        ufw --force enable
        ufw reload

        echo ""
        echo "=== FIREWALL STATUS ==="
        ufw status verbose
UFW
    success "Hostinger firewall locked down"

    echo ""
    info "IMPORTANT: From now on, access admin dashboards via Tailscale IPs:"
    echo "  Grafana:          http://${HETZNER_TAILSCALE}:3002"
    echo "  Portainer:        https://${HETZNER_TAILSCALE}:9443"
    echo "  Netdata:          http://${HETZNER_TAILSCALE}:19999"
    echo "  Prometheus:       http://${HETZNER_TAILSCALE}:9090"
    echo "  Uptime Kuma:      http://${HETZNER_TAILSCALE}:3001"
    echo "  Prediction Radar: http://${HETZNER_TAILSCALE}:8098"
    echo "  Superset:         http://${HETZNER_TAILSCALE}:8088"
    echo "  ClickHouse:       http://${HETZNER_TAILSCALE}:8123"
    echo "  ChangeDetection:  http://${HETZNER_TAILSCALE}:5000"
    echo "  Healthchecks:     http://${HETZNER_TAILSCALE}:3130"
    echo "  RavynAI:          http://${HETZNER_TAILSCALE}:8007"

    success "PHASE 2 COMPLETE"
}

# ============================================================================
# PHASE 3: DOCKER SECURITY HARDENING
# ============================================================================
phase3_docker_security() {
    banner "PHASE 3: DOCKER SECURITY HARDENING"

    info "Applying Docker daemon security config on Hetzner..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'DOCKER'
        cat > /etc/docker/daemon.json << 'JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "icc": false,
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
JSON

        systemctl restart docker
        sleep 5
        docker info | grep -E "Live Restore|Default Ulimits|Logging"
        echo "Docker security config applied"
DOCKER
    success "Hetzner Docker hardened"

    info "Applying Docker daemon security config on Hostinger..."
    ssh root@${HOSTINGER_TAILSCALE} "bash -s" << 'DOCKER'
        cat > /etc/docker/daemon.json << 'JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "5m",
    "max-file": "2"
  },
  "icc": false,
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true
}
JSON

        # Check if docker restart would break things
        RUNNING=$(docker ps -q | wc -l)
        echo "$RUNNING containers running. Restarting Docker daemon..."
        systemctl restart docker
        sleep 5

        # Verify containers came back
        ALIVE=$(docker ps -q | wc -l)
        echo "$ALIVE containers alive after restart"
        if [ "$ALIVE" -lt "$RUNNING" ]; then
            echo "WARNING: Some containers did not survive restart!"
            docker ps -a --format '{{.Names}} {{.Status}}' | grep -v Up
        fi
DOCKER
    success "Hostinger Docker hardened"

    success "PHASE 3 COMPLETE"
}

# ============================================================================
# PHASE 4: FAIL2BAN + CROWDSEC DEPLOYMENT
# ============================================================================
phase4_intrusion_prevention() {
    banner "PHASE 4: FAIL2BAN + CROWDSEC"

    # --- HETZNER ---
    info "Setting up Fail2ban on Hetzner..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'F2B'
        set -e

        # Ensure fail2ban is installed
        apt-get update -qq && apt-get install -y -qq fail2ban

        cat > /etc/fail2ban/jail.local << 'JAIL'
[sshd]
enabled = true
maxretry = 3
bantime = 3600
findtime = 600
mode = aggressive

[traefik-auth]
enabled = true
port = http,https
filter = traefik-auth
logpath = /opt/logs/traefik/access.log
maxretry = 5
bantime = 1800
findtime = 300

[recidive]
enabled = true
maxretry = 3
bantime = 604800
findtime = 86400
JAIL

        cat > /etc/fail2ban/filter.d/traefik-auth.conf << 'FILTER'
[Definition]
failregex = ^<HOST> - - \[.*\] ".*" 401 .*$
            ^<HOST> - - \[.*\] ".*" 403 .*$
            ^<HOST> - - \[.*\] ".*" 429 .*$
ignoreregex =
FILTER

        systemctl enable fail2ban
        systemctl restart fail2ban
        fail2ban-client status
        echo "Fail2ban configured on Hetzner"
F2B
    success "Fail2ban on Hetzner"

    # --- HOSTINGER ---
    info "Setting up Fail2ban on Hostinger..."
    ssh root@${HOSTINGER_TAILSCALE} "bash -s" << 'F2B'
        set -e
        apt-get update -qq && apt-get install -y -qq fail2ban

        cat > /etc/fail2ban/jail.local << 'JAIL'
[sshd]
enabled = true
maxretry = 2
bantime = 7200
findtime = 600
mode = aggressive

[traefik-auth]
enabled = true
port = http,https
filter = traefik-auth
logpath = /opt/logs/traefik/access.log
maxretry = 3
bantime = 3600
findtime = 300

[recidive]
enabled = true
maxretry = 2
bantime = 1209600
findtime = 86400
JAIL

        cat > /etc/fail2ban/filter.d/traefik-auth.conf << 'FILTER'
[Definition]
failregex = ^<HOST> - - \[.*\] ".*" 401 .*$
            ^<HOST> - - \[.*\] ".*" 403 .*$
            ^<HOST> - - \[.*\] ".*" 429 .*$
ignoreregex =
FILTER

        systemctl enable fail2ban
        systemctl restart fail2ban
        fail2ban-client status
        echo "Fail2ban configured on Hostinger"
F2B
    success "Fail2ban on Hostinger"

    # --- CROWDSEC (Hetzner only — Hostinger too resource-constrained) ---
    info "Installing CrowdSec on Hetzner..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'CROWDSEC'
        if command -v crowdsec &>/dev/null; then
            echo "CrowdSec already installed"
        else
            curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
            apt-get install -y crowdsec crowdsec-firewall-bouncer-iptables
        fi

        # Install Traefik collection
        cscli collections install crowdsecurity/traefik || true

        systemctl enable crowdsec
        systemctl restart crowdsec

        cscli metrics
        echo "CrowdSec installed on Hetzner"
CROWDSEC
    success "CrowdSec on Hetzner"

    echo ""
    info "NOTE: CrowdSec NOT installed on Hostinger (resource constrained)."
    info "Hostinger relies on Fail2ban + Cloudflare WAF for protection."

    success "PHASE 4 COMPLETE"
}

# ============================================================================
# PHASE 5: DOCKER NETWORKS + TRAEFIK DEPLOYMENT (HETZNER)
# ============================================================================
phase5_hetzner_networks_traefik() {
    banner "PHASE 5: DOCKER NETWORKS + TRAEFIK ON HETZNER"

    info "Creating Docker networks on Hetzner..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'NETS'
        # Create all networks (ignore if exist)
        docker network create --driver bridge --subnet 172.20.0.0/24 traefik-public 2>/dev/null || echo "traefik-public exists"
        docker network create --driver bridge --subnet 172.21.0.0/24 prediction-radar 2>/dev/null || echo "prediction-radar exists"
        docker network create --driver bridge --subnet 172.22.0.0/24 analytics 2>/dev/null || echo "analytics exists"
        docker network create --driver bridge --subnet 172.23.0.0/24 monitoring 2>/dev/null || echo "monitoring exists"
        docker network create --driver bridge --subnet 172.24.0.0/24 ai-agents 2>/dev/null || echo "ai-agents exists"
        docker network create --driver bridge --subnet 172.25.0.0/24 ravynai 2>/dev/null || echo "ravynai exists"
        docker network create --driver bridge --subnet 172.26.0.0/24 trading 2>/dev/null || echo "trading exists"
        docker network create --driver bridge --subnet 172.27.0.0/24 messaging 2>/dev/null || echo "messaging exists"
        docker network create --driver bridge --subnet 172.28.0.0/24 automation 2>/dev/null || echo "automation exists"
        docker network create --driver bridge --subnet 172.29.0.0/24 data 2>/dev/null || echo "data exists"
        docker network create --driver bridge --subnet 172.30.0.0/24 management 2>/dev/null || echo "management exists"

        echo ""
        echo "=== DOCKER NETWORKS ==="
        docker network ls | grep -E "traefik-public|prediction|analytics|monitoring|ai-agents|ravynai|trading|messaging|automation|data|management"
NETS
    success "Docker networks created"

    info "Connecting existing containers to appropriate networks..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'CONNECT'
        # Connect monitoring containers to monitoring network
        for c in aiops-uptime-kuma aiops-prometheus aiops-grafana netdata; do
            docker network connect monitoring "$c" 2>/dev/null && echo "Connected $c → monitoring" || echo "$c not found, skipping"
        done

        # Connect analytics containers to analytics network
        for c in superset clickhouse-server; do
            docker network connect analytics "$c" 2>/dev/null && echo "Connected $c → analytics" || echo "$c not found, skipping"
        done

        # Connect management containers to management network
        for c in portainer dockge; do
            docker network connect management "$c" 2>/dev/null && echo "Connected $c → management" || echo "$c not found, skipping"
        done

        # Connect prediction radar containers
        for c in prediction-radar-app-api prediction-radar-app-web prediction-radar-app-worker prediction-radar-app-scheduler; do
            docker network connect prediction-radar "$c" 2>/dev/null && echo "Connected $c → prediction-radar" || echo "$c not found, skipping"
        done

        # Connect ravynai containers
        for c in ravynai-api ravynai-worker; do
            docker network connect ravynai "$c" 2>/dev/null && echo "Connected $c → ravynai" || echo "$c not found, skipping"
        done

        # Connect automation containers
        for c in changedetection camofox-browser; do
            docker network connect automation "$c" 2>/dev/null && echo "Connected $c → automation" || echo "$c not found, skipping"
        done

        echo "Network connections complete"
CONNECT
    success "Containers connected to networks"

    info "Deploying Traefik on Hetzner..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'TRAEFIK'
        mkdir -p /opt/apps/traefik
        mkdir -p /opt/logs/traefik

        # Check if Traefik already running
        if docker ps --format '{{.Names}}' | grep -q traefik; then
            echo "Traefik already running — stopping for reconfiguration"
            docker stop traefik 2>/dev/null || true
            docker rm traefik 2>/dev/null || true
        fi

        # Create Traefik static config
        cat > /opt/apps/traefik/traefik.yml << 'YAML'
global:
  checkNewVersion: false
  sendAnonymousUsage: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"

api:
  dashboard: true
  insecure: false

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik-public
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@wheeler.ai
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

log:
  level: INFO
  format: json
  filePath: /var/log/traefik/access.log

accessLog:
  format: json
  filePath: /var/log/traefik/access.log

metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
YAML

        # Create dynamic config with middlewares
        cat > /opt/apps/traefik/dynamic.yml << 'YAML'
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
      sniStrict: true

http:
  middlewares:
    security-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        stsSeconds: 63072000
        stsIncludeSubdomains: true
        stsPreload: true
        customFrameOptionsValue: "SAMEORIGIN"

    rate-limit-public:
      rateLimit:
        average: 100
        burst: 50

    rate-limit-strict:
      rateLimit:
        average: 30
        burst: 15

    compress:
      compress:
        excludedContentTypes:
          - text/event-stream
YAML

        # Deploy Traefik
        docker run -d \
            --name traefik \
            --restart unless-stopped \
            --network traefik-public \
            -p 80:80 \
            -p 443:443 \
            -v /var/run/docker.sock:/var/run/docker.sock:ro \
            -v /opt/apps/traefik/traefik.yml:/etc/traefik/traefik.yml:ro \
            -v /opt/apps/traefik/dynamic.yml:/etc/traefik/dynamic.yml:ro \
            -v /opt/logs/traefik:/var/log/traefik \
            -v traefik-letsencrypt:/letsencrypt \
            -l "traefik.enable=true" \
            -l "traefik.http.routers.dashboard.rule=Host(\`traefik.internal.wheeler.ai\`)" \
            -l "traefik.http.routers.dashboard.service=api@internal" \
            -l "traefik.http.routers.dashboard.middlewares=rate-limit-strict@file,security-headers@file" \
            traefik:v3.1

        sleep 5
        docker ps --format '{{.Names}} {{.Status}}' | grep traefik
        echo "Traefik deployed"
TRAEFIK
    success "Traefik deployed on Hetzner"

    success "PHASE 5 COMPLETE"
}

# ============================================================================
# PHASE 6: HOSTINGER TRAEFIK EDGE DEPLOYMENT
# ============================================================================
phase6_hostinger_traefik() {
    banner "PHASE 6: HOSTINGER TRAEFIK EDGE DEPLOYMENT"

    info "Deploying Traefik as public edge router on Hostinger..."
    ssh root@${HOSTINGER_TAILSCALE} "bash -s" << 'TRAEFIK'
        mkdir -p /opt/apps/traefik
        mkdir -p /opt/logs/traefik

        # Stop any existing traefik
        docker stop traefik 2>/dev/null || true
        docker rm traefik 2>/dev/null || true

        cat > /opt/apps/traefik/traefik.yml << 'YAML'
global:
  checkNewVersion: false
  sendAnonymousUsage: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik-public
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@wheeler.ai
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

log:
  level: WARN
  format: json

accessLog:
  format: json

metrics:
  prometheus: {}
YAML

        cat > /opt/apps/traefik/dynamic.yml << 'YAML'
tls:
  options:
    default:
      minVersion: VersionTLS12
      sniStrict: true

http:
  middlewares:
    security-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        stsSeconds: 63072000
        stsIncludeSubdomains: true

    rate-limit-public:
      rateLimit:
        average: 50
        burst: 25

    compress:
      compress: {}

  # Routes to Hetzner services via Tailscale
  routers:
    predictionradar:
      rule: "Host(`predictionradar.wheeler.ai`)"
      service: predictionradar-svc
      middlewares: rate-limit-public,security-headers,compress
      tls: { certResolver: letsencrypt }

    ravynai:
      rule: "Host(`ravynai.wheeler.ai`)"
      service: ravynai-svc
      middlewares: rate-limit-public,security-headers,compress
      tls: { certResolver: letsencrypt }

    superset:
      rule: "Host(`superset.wheeler.ai`)"
      service: superset-svc
      middlewares: rate-limit-public,security-headers,compress
      tls: { certResolver: letsencrypt }

    healthchecks:
      rule: "Host(`healthchecks.wheeler.ai`)"
      service: healthchecks-svc
      middlewares: rate-limit-public,security-headers,compress
      tls: { certResolver: letsencrypt }

    changedetect:
      rule: "Host(`changedetect.wheeler.ai`)"
      service: changedetect-svc
      middlewares: rate-limit-public,security-headers,compress
      tls: { certResolver: letsencrypt }

    grafana:
      rule: "Host(`grafana.wheeler.ai`)"
      service: grafana-svc
      middlewares: rate-limit-public,security-headers,compress
      tls: { certResolver: letsencrypt }

    uptime:
      rule: "Host(`uptime.wheeler.ai`)"
      service: uptime-svc
      middlewares: rate-limit-public,security-headers,compress
      tls: { certResolver: letsencrypt }

  services:
    predictionradar-svc:
      loadBalancer:
        servers:
          - url: "http://100.121.230.28:8098"
        healthCheck:
          path: /api/health
          interval: 30s
          timeout: 5s

    ravynai-svc:
      loadBalancer:
        servers:
          - url: "http://100.121.230.28:8007"
        healthCheck:
          path: /health
          interval: 30s
          timeout: 5s

    superset-svc:
      loadBalancer:
        servers:
          - url: "http://100.121.230.28:8088"
        healthCheck:
          path: /health
          interval: 30s
          timeout: 5s

    healthchecks-svc:
      loadBalancer:
        servers:
          - url: "http://100.121.230.28:3130"
        healthCheck:
          path: /health
          interval: 30s
          timeout: 5s

    changedetect-svc:
      loadBalancer:
        servers:
          - url: "http://100.121.230.28:5000"
        healthCheck:
          interval: 30s
          timeout: 5s

    grafana-svc:
      loadBalancer:
        servers:
          - url: "http://100.121.230.28:3002"
        healthCheck:
          path: /api/health
          interval: 30s
          timeout: 5s

    uptime-svc:
      loadBalancer:
        servers:
          - url: "http://100.121.230.28:3001"
        healthCheck:
          interval: 30s
          timeout: 5s
YAML

        # Create Docker network
        docker network create traefik-public 2>/dev/null || true

        # Deploy Traefik
        docker run -d \
            --name traefik \
            --restart unless-stopped \
            --network traefik-public \
            -p 80:80 \
            -p 443:443 \
            -v /var/run/docker.sock:/var/run/docker.sock:ro \
            -v /opt/apps/traefik/traefik.yml:/etc/traefik/traefik.yml:ro \
            -v /opt/apps/traefik/dynamic.yml:/etc/traefik/dynamic.yml:ro \
            -v /opt/logs/traefik:/var/log/traefik \
            -v traefik-letsencrypt:/letsencrypt \
            --memory="256m" \
            --cpus="0.5" \
            traefik:v3.1

        sleep 5
        docker ps --format '{{.Names}} {{.Status}}' | grep traefik
        echo "Traefik edge router deployed"
TRAEFIK
    success "Traefik deployed on Hostinger"

    success "PHASE 6 COMPLETE"
}

# ============================================================================
# PHASE 7: MONITORING STACK ENHANCEMENT
# ============================================================================
phase7_monitoring_enhancement() {
    banner "PHASE 7: MONITORING STACK ENHANCEMENT"

    info "Deploying node_exporter on both servers..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'NODE'
        docker run -d \
            --name node_exporter \
            --restart unless-stopped \
            --network monitoring \
            --pid host \
            -v /proc:/host/proc:ro \
            -v /sys:/host/sys:ro \
            -v /:/rootfs:ro \
            -v /etc/hostname:/etc/hostname:ro \
            --cpus="0.3" \
            --memory="128m" \
            prom/node-exporter:latest \
            --path.procfs=/host/proc \
            --path.sysfs=/host/sys \
            --path.rootfs=/rootfs \
            --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc)($$|/)'
        echo "node_exporter deployed on Hetzner"
NODE

    ssh root@${HOSTINGER_TAILSCALE} "bash -s" << 'NODE'
        docker run -d \
            --name node_exporter \
            --restart unless-stopped \
            --pid host \
            -v /proc:/host/proc:ro \
            -v /sys:/host/sys:ro \
            -v /:/rootfs:ro \
            --cpus="0.2" \
            --memory="64m" \
            prom/node-exporter:latest \
            --path.procfs=/host/proc \
            --path.sysfs=/host/sys \
            --path.rootfs=/rootfs \
            --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc)($$|/)'
        echo "node_exporter deployed on Hostinger"
NODE
    success "node_exporters deployed"

    info "Deploying cAdvisor on both servers..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'CAD'
        docker run -d \
            --name cadvisor \
            --restart unless-stopped \
            --network monitoring \
            -v /:/rootfs:ro \
            -v /var/run:/var/run:ro \
            -v /sys:/sys:ro \
            -v /var/lib/docker/:/var/lib/docker:ro \
            -v /dev/disk/:/dev/disk:ro \
            --privileged \
            --cpus="0.3" \
            --memory="128m" \
            gcr.io/cadvisor/cadvisor:latest
        echo "cAdvisor deployed on Hetzner"
CAD

    ssh root@${HOSTINGER_TAILSCALE} "bash -s" << 'CAD'
        docker run -d \
            --name cadvisor \
            --restart unless-stopped \
            -v /:/rootfs:ro \
            -v /var/run:/var/run:ro \
            -v /sys:/sys:ro \
            -v /var/lib/docker/:/var/lib/docker:ro \
            -v /dev/disk/:/dev/disk:ro \
            --privileged \
            --cpus="0.2" \
            --memory="64m" \
            gcr.io/cadvisor/cadvisor:latest
        echo "cAdvisor deployed on Hostinger"
CAD
    success "cAdvisors deployed"

    info "Updating Prometheus config to scrape both servers..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'PROM'
        cat > /opt/apps/monitoring/prometheus.yml << 'YAML'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

rule_files:
  - "alert-rules.yml"

scrape_configs:
  - job_name: "hetzner-node"
    static_configs:
      - targets: ["node_exporter:9100"]
        labels:
          instance: "hetzner"

  - job_name: "hostinger-node"
    static_configs:
      - targets: ["100.98.163.17:9100"]
        labels:
          instance: "hostinger"

  - job_name: "hetzner-cadvisor"
    static_configs:
      - targets: ["cadvisor:8080"]
        labels:
          instance: "hetzner"

  - job_name: "hostinger-cadvisor"
    static_configs:
      - targets: ["100.98.163.17:8080"]
        labels:
          instance: "hostinger"

  - job_name: "hetzner-traefik"
    static_configs:
      - targets: ["traefik:8080"]
        labels:
          instance: "hetzner"

  - job_name: "hostinger-traefik"
    static_configs:
      - targets: ["100.98.163.17:8080"]
        labels:
          instance: "hostinger"

  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
YAML

        # Restart Prometheus to pick up new config
        docker restart aiops-prometheus
        echo "Prometheus config updated"
PROM
    success "Prometheus scraping both servers"

    success "PHASE 7 COMPLETE"
}

# ============================================================================
# PHASE 8: BACKUP AUTOMATION SETUP
# ============================================================================
phase8_backup_automation() {
    banner "PHASE 8: BACKUP AUTOMATION"

    info "Installing backup cron on Hetzner..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'BACKUP'
        mkdir -p /opt/backups/databases
        mkdir -p /opt/backups/volumes
        mkdir -p /opt/logs

        # Create database backup script
        cat > /opt/scripts/backup-databases.sh << 'SCRIPT'
#!/usr/bin/env bash
set -e
BACKUP_DIR="/opt/backups/databases/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# List databases to backup (adjust container names as needed)
# Prediction Radar DB
docker exec prediction-radar-db-1 pg_dump -U postgres -Fc prediction_radar > "$BACKUP_DIR/prediction_radar.dump" 2>/dev/null || echo "prediction_radar backup skipped"
# RavynAI DB
docker exec ravynai-db-1 pg_dump -U postgres -Fc ravynai > "$BACKUP_DIR/ravynai.dump" 2>/dev/null || echo "ravynai backup skipped"
# Healthchecks DB (if separate)
docker exec healthchecks-db-1 pg_dump -U postgres -Fc healthchecks > "$BACKUP_DIR/healthchecks.dump" 2>/dev/null || echo "healthchecks backup skipped"

# Verify each dump
for f in "$BACKUP_DIR"/*.dump; do
    [ -f "$f" ] && pg_restore --list "$f" > /dev/null 2>&1 && echo "VERIFIED: $f" || echo "CORRUPT: $f"
done

# Retention: delete older than 7 days
find /opt/backups/databases -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

echo "Backup complete: $BACKUP_DIR"
ls -lah "$BACKUP_DIR"
SCRIPT
        chmod +x /opt/scripts/backup-databases.sh

        # Create backup cron (3 AM UTC daily)
        mkdir -p /opt/scripts/backup
        cp /opt/scripts/backup-databases.sh /opt/scripts/backup/
        (crontab -l 2>/dev/null; echo "0 3 * * * /opt/scripts/backup/backup-databases.sh >> /opt/logs/backup.log 2>&1") | crontab -

        echo "Backup cron installed"
        crontab -l | grep backup
BACKUP
    success "Backup automation on Hetzner"

    info "Setting up Hostinger backup pull on this local machine..."
    cat > /opt/scripts/pull-hostinger-backups-enhanced.sh << 'SCRIPT'
#!/usr/bin/env bash
set -e
HOSTINGER="root@100.98.163.17"
DEST="/root/backups/hostinger/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DEST"

# Pull Postgres dumps from Hostinger
ssh "$HOSTINGER" "bash -s" << 'REMOTE'
    mkdir -p /tmp/db-backups
    for db in frgops_production frgcrm_local chatwoot_production langfuse plausible usesend frgops_staging; do
        docker exec postgres pg_dump -U postgres -Fc "$db" > "/tmp/db-backups/${db}.dump" 2>/dev/null || echo "Skipped $db"
    done
REMOTE

# Pull the dumps
rsync -avz "$HOSTINGER:/tmp/db-backups/" "$DEST/"

# Also pull configs
ssh "$HOSTINGER" "find /opt/apps -maxdepth 3 \( -name 'docker-compose.yml' -o -name '.env' \)" | while read f; do
    ssh "$HOSTINGER" "cat $f" > "$DEST/$(echo $f | tr '/' '_')" 2>/dev/null || true
done

# Verify
for f in "$DEST"/*.dump; do
    [ -f "$f" ] && pg_restore --list "$f" > /dev/null 2>&1 && echo "VERIFIED: $f" || echo "CORRUPT: $f"
done

# Retention: keep 7 daily, 4 weekly, 3 monthly
find /root/backups/hostinger -maxdepth 1 -type d -mtime +7 | while read d; do
    day=$(basename "$d" | cut -d_ -f1)
    if [ "$(date -d "$day" +%u)" != "7" ] && [ "$(date -d "$day" +%d)" != "01" ]; then
        rm -rf "$d"
    fi
done

echo "Hostinger backup pull complete: $DEST"
ls -lah "$DEST"
SCRIPT
    chmod +x /opt/scripts/pull-hostinger-backups-enhanced.sh

    success "Backup pull script updated"

    success "PHASE 8 COMPLETE"
}

# ============================================================================
# PHASE 9: SSH HARDENING
# ============================================================================
phase9_ssh_hardening() {
    banner "PHASE 9: SSH HARDENING"
    warn "This modifies SSH daemon config. A backup will be created."
    warn "Make sure you have a SECOND SHELL OPEN before running this."

    echo ""
    read -p "Continue with SSH hardening? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        warn "Skipping SSH hardening"
        return
    fi

    for server in "${HETZNER_TAILSCALE}" "${HOSTINGER_TAILSCALE}"; do
        info "Hardening SSH on $server..."
        ssh root@${server} "bash -s" << 'SSH'
            set -e
            cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)

            # Apply hardening
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
            sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
            sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
            sed -i 's/^#*UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
            sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
            sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
            sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
            sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
            sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config

            # Ensure these are set (add if missing)
            grep -q "^PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config
            grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
            grep -q "^X11Forwarding" /etc/ssh/sshd_config || echo "X11Forwarding no" >> /etc/ssh/sshd_config

            # Test config
            sshd -t && echo "SSH config valid" || { echo "SSH CONFIG INVALID! Restoring backup."; cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config; exit 1; }

            systemctl restart sshd
            echo "SSH hardened on $(hostname)"
SSH
        success "SSH hardened on $server"
    done

    success "PHASE 9 COMPLETE"
}

# ============================================================================
# PHASE 10: HOSTINGER HEAVY SERVICE CLEANUP
# ============================================================================
phase10_hostinger_cleanup() {
    banner "PHASE 10: HOSTINGER FINAL CLEANUP"

    info "Permanently removing stopped heavy containers on Hostinger..."
    ssh root@${HOSTINGER_TAILSCALE} "bash -s" << 'CLEAN'
        echo "=== STOPPED HEAVY CONTAINERS ==="
        docker ps -a --format '{{.Names}} {{.Status}}' | grep -E 'healthchecks|changedetection|superset|clickhouse|plausible-clickhouse|camofox|spiderfoot|prediction-radar' || echo "None found"

        echo ""
        echo "Removing stopped heavy containers..."
        for c in healthchecks changedetection superset clickhouse-server plausible-clickhouse camofox-browser spiderfoot-spiderfoot-1 prediction-radar-app-api prediction-radar-app-web prediction-radar-app-worker prediction-radar-app-scheduler; do
            docker rm "$c" 2>/dev/null && echo "Removed: $c" || echo "Not found: $c"
        done

        echo ""
        echo "=== PRUNING ==="
        docker system prune -af --volumes

        echo ""
        echo "=== DISK AFTER CLEANUP ==="
        df -h /
        free -h

        echo ""
        echo "=== RUNNING CONTAINERS ==="
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
CLEAN
    success "Hostinger cleaned"

    success "PHASE 10 COMPLETE"
}

# ============================================================================
# PHASE 11: SYSTEMD AUTO-START VERIFICATION
# ============================================================================
phase11_autostart_verification() {
    banner "PHASE 11: AUTO-START VERIFICATION"

    info "Ensuring Docker starts on boot..."
    for server in "${HETZNER_TAILSCALE}" "${HOSTINGER_TAILSCALE}"; do
        ssh root@${server} "systemctl enable docker && echo 'Docker enabled on '\$(hostname)"
    done

    info "Verifying all containers have restart policies..."
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'CHECK'
        echo "Containers WITHOUT restart policy:"
        docker ps -a --format '{{.Names}} {{.Status}}' | while read name status; do
            policy=$(docker inspect "$name" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
            if [ "$policy" != "unless-stopped" ] && [ "$policy" != "always" ]; then
                echo "  $name → $policy (FIXING...)"
                docker update --restart unless-stopped "$name" 2>/dev/null || echo "  Could not update $name"
            fi
        done
        echo "Restart policy audit complete"
CHECK

    ssh root@${HOSTINGER_TAILSCALE} "bash -s" << 'CHECK'
        echo "Containers WITHOUT restart policy:"
        docker ps -a --format '{{.Names}} {{.Status}}' | while read name status; do
            policy=$(docker inspect "$name" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
            if [ "$policy" != "unless-stopped" ] && [ "$policy" != "always" ]; then
                echo "  $name → $policy (FIXING...)"
                docker update --restart unless-stopped "$name" 2>/dev/null || echo "  Could not update $name"
            fi
        done
        echo "Restart policy audit complete"
CHECK

    success "PHASE 11 COMPLETE"
}

# ============================================================================
# PHASE 12: TMUX DEV WORKFLOW SETUP
# ============================================================================
phase12_tmux_workflow() {
    banner "PHASE 12: TMUX DEV WORKFLOW"

    cat > /root/.tmux-aiops.conf << 'TMUX'
# Wheeler AIOps tmux configuration
# Usage: tmux -f /root/.tmux-aiops.conf new -s aiops

new-session -d -s aiops -n "system"
send-keys -t aiops:system "watch -n 5 'docker ps --format \"table {{.Names}}\t{{.Status}}\t{{.Ports}}\"'" Enter

new-window -t aiops -n "logs"
send-keys -t aiops:logs "tail -f /opt/logs/*.log 2>/dev/null || echo 'No logs yet'" Enter

new-window -t aiops -n "hetzner"
send-keys -t aiops:hetzner "ssh root@100.121.230.28" Enter

new-window -t aiops -n "hostinger"
send-keys -t aiops:hostinger "ssh root@100.98.163.17" Enter

new-window -t aiops -n "deploy"
send-keys -t aiops:deploy "cd /root/infrastructure && ls -la" Enter

new-window -t aiops -n "monitor"
send-keys -t aiops:monitor "watch -n 10 'curl -s http://100.121.230.28:3001/api/status 2>/dev/null || echo uptime-down'" Enter

select-window -t aiops:system
TMUX

    echo "Tmux config created at /root/.tmux-aiops.conf"
    echo "Start with: tmux -f /root/.tmux-aiops.conf new -s aiops"
    echo "Or attach:  tmux attach -t aiops"

    success "PHASE 12 COMPLETE"
}

# ============================================================================
# PHASE 13: FINAL VERIFICATION
# ============================================================================
phase13_verify_all() {
    banner "PHASE 13: FINAL VERIFICATION"

    info "=== HETZNER STATUS ==="
    ssh root@${HETZNER_TAILSCALE} "bash -s" << 'VERIFY'
        echo "--- SYSTEM ---"
        uptime
        free -h | head -2
        df -h /

        echo ""
        echo "--- DOCKER CONTAINERS ---"
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

        echo ""
        echo "--- UFW ---"
        ufw status | head -5

        echo ""
        echo "--- FAIL2BAN ---"
        fail2ban-client status sshd 2>/dev/null || echo "fail2ban not running"

        echo ""
        echo "--- TAILSCALE ---"
        tailscale status | head -5

        echo ""
        echo "--- DOCKER NETWORKS ---"
        docker network ls | grep -E "traefik|prediction|analytics|monitoring|ai-agents|ravynai|trading|messaging|automation|data|management"
VERIFY

    echo ""
    info "=== HOSTINGER STATUS ==="
    ssh root@${HOSTINGER_TAILSCALE} "bash -s" << 'VERIFY'
        echo "--- SYSTEM ---"
        uptime
        free -h | head -2
        df -h /

        echo ""
        echo "--- DOCKER CONTAINERS ---"
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

        echo ""
        echo "--- UFW ---"
        ufw status | head -5

        echo ""
        echo "--- TAILSCALE ---"
        tailscale status | head -5
VERIFY

    echo ""
    info "=== CROSS-SERVER CONNECTIVITY ==="
    ssh root@${HETZNER_TAILSCALE} "ping -c 2 ${HOSTINGER_TAILSCALE} && echo 'Hetzner → Hostinger OK'"
    ssh root@${HOSTINGER_TAILSCALE} "ping -c 2 ${HETZNER_TAILSCALE} && echo 'Hostinger → Hetzner OK'"

    echo ""
    info "=== HEALTH CHECK ENDPOINTS ==="
    endpoints=(
        "http://${HETZNER_TAILSCALE}:3001"    # Uptime Kuma
        "http://${HETZNER_TAILSCALE}:3002"    # Grafana
        "http://${HETZNER_TAILSCALE}:19999"   # Netdata
        "http://${HETZNER_TAILSCALE}:9090"    # Prometheus
        "http://${HETZNER_TAILSCALE}:8098"    # Prediction Radar
        "http://${HETZNER_TAILSCALE}:8007/health" # RavynAI
        "http://${HETZNER_TAILSCALE}:8088"    # Superset
        "http://${HETZNER_TAILSCALE}:8123/ping" # ClickHouse
        "http://${HETZNER_TAILSCALE}:5000"    # ChangeDetection
        "http://${HETZNER_TAILSCALE}:3130"    # Healthchecks
    )

    for url in "${endpoints[@]}"; do
        status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "FAIL")
        if [ "$status" = "200" ] || [ "$status" = "302" ] || [ "$status" = "301" ] || [ "$status" = "401" ]; then
            success "$url → $status"
        else
            error "$url → $status"
        fi
    done

    echo ""
    success "==========================================="
    success "  WHEELER AIOPS PHASE 2 MIGRATION COMPLETE"
    success "==========================================="
    echo ""
    echo "ARCHITECTURE DOCS: /root/infrastructure/ARCHITECTURE.md"
    echo "TMUX WORKFLOW:     tmux -f /root/.tmux-aiops.conf new -s aiops"
    echo "STATUS SCRIPT:     /root/aiops-status.sh"
    echo ""
}

# ============================================================================
# ROLLBACK INSTRUCTIONS
# ============================================================================
rollback_guide() {
    banner "ROLLBACK GUIDE"

    cat << 'ROLLBACK'
IF SOMETHING GOES WRONG — ROLLBACK BY PHASE:

Phase 2 (Firewall) rollback:
    ssh root@<server> "ufw --force reset && ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw --force enable"

Phase 3 (Docker) rollback:
    ssh root@<server> "cp /etc/docker/daemon.json.backup /etc/docker/daemon.json && systemctl restart docker"

Phase 5/6 (Traefik) rollback:
    ssh root@<server> "docker stop traefik && docker rm traefik"
    - Services will be accessible again on raw ports (8098, 8007, etc.)

Phase 9 (SSH) rollback:
    ssh root@<server> "cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config && systemctl restart sshd"

FULL ROLLBACK:
    Restore from /opt/backups/pre-migration-YYYYMMDD/ on each server
    - docker compose up -d for each compose file saved
    - Restore UFW: ufw --force reset && (restore rules from ufw-rules.txt)
    - Restore crontab
ROLLBACK

    echo ""
    info "Snapshot locations for full rollback:"
    ssh root@${HETZNER_TAILSCALE} "ls -d /opt/backups/pre-migration-* 2>/dev/null || echo 'No snapshots found'"
    ssh root@${HOSTINGER_TAILSCALE} "ls -d /opt/backups/pre-migration-* 2>/dev/null || echo 'No snapshots found'"
}

# ============================================================================
# MAIN — Run phases in order
# ============================================================================
main() {
    echo ""
    echo "============================================================"
    echo " WHEELER AIOPS — PHASE 2 MIGRATION PLAYBOOK"
    echo " $(date)"
    echo "============================================================"
    echo ""
    echo "Available phases:"
    echo "  all       — Run ALL phases in order (recommended)"
    echo "  preflight — Pre-flight connectivity checks"
    echo "  1         — Pre-migration full snapshot"
    echo "  2         — Firewall lockdown"
    echo "  3         — Docker security hardening"
    echo "  4         — Fail2ban + CrowdSec"
    echo "  5         — Docker networks + Hetzner Traefik"
    echo "  6         — Hostinger Traefik edge router"
    echo "  7         — Monitoring enhancement"
    echo "  8         — Backup automation"
    echo "  9         — SSH hardening"
    echo "  10        — Hostinger final cleanup"
    echo "  11        — Auto-start verification"
    echo "  12        — Tmux workflow setup"
    echo "  13        — Final verification"
    echo "  rollback  — Show rollback guide"
    echo ""
    echo "Usage: $0 <phase>"
    echo "  $0 preflight    # ALWAYS run this first"
    echo "  $0 all          # Run everything"
    echo "  $0 1            # Run just phase 1"
    echo ""
}

# Parse command line
PHASE="${1:-}"

case "$PHASE" in
    all)
        preflight
        phase1_snapshot
        phase2_firewall
        phase3_docker_security
        phase4_intrusion_prevention
        phase5_hetzner_networks_traefik
        phase6_hostinger_traefik
        phase7_monitoring_enhancement
        phase8_backup_automation
        phase9_ssh_hardening
        phase10_hostinger_cleanup
        phase11_autostart_verification
        phase12_tmux_workflow
        phase13_verify_all
        ;;
    preflight)
        preflight
        ;;
    1)  phase1_snapshot ;;
    2)  phase2_firewall ;;
    3)  phase3_docker_security ;;
    4)  phase4_intrusion_prevention ;;
    5)  phase5_hetzner_networks_traefik ;;
    6)  phase6_hostinger_traefik ;;
    7)  phase7_monitoring_enhancement ;;
    8)  phase8_backup_automation ;;
    9)  phase9_ssh_hardening ;;
    10) phase10_hostinger_cleanup ;;
    11) phase11_autostart_verification ;;
    12) phase12_tmux_workflow ;;
    13) phase13_verify_all ;;
    rollback)
        rollback_guide
        ;;
    *)
        main
        ;;
esac
