#!/usr/bin/env bash
# =============================================================================
# Wheeler Enterprise — UFW Firewall Policy Generator
# =============================================================================
# Generates per-server-role UFW policy.
# Usage: bash 02-ufw-policies.sh [edge|aiops|coredb] [--apply]
#   --dry-run (default): prints rules, does not apply
#   --apply: applies rules via ufw
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE="${1:-}"
ACTION="${2:---dry-run}"

# Tailscale subnet — always allowed
TAILSCALE_SUBNET="100.64.0.0/10"

# Server IPs (from the architecture definition)
EDGE_IP="187.77.148.88"
AIOPS_IP="5.78.140.118"
COREDB_IP="5.78.210.123"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }

generate_edge_rules() {
    cat <<'RULES'
# ==================== EDGE SERVER (Hostinger) ====================
# Role: Public-facing reverse proxy + frontend only
# Allowed: SSH, HTTP, HTTPS, Tailscale
# Denied: Everything else (no databases, no APIs exposed directly)

# Default policies
ufw default deny incoming
ufw default allow outgoing

# SSH — restrict to Tailscale + specific admin IPs only
ufw allow from 100.64.0.0/10 to any port 22 proto tcp

# HTTP/HTTPS — public, but rate-limited by fail2ban
ufw allow 80/tcp
ufw allow 443/tcp

# Tailscale full mesh (all ports between Tailscale nodes)
ufw allow from 100.64.0.0/10

# Rate-limit SSH from non-Tailscale (allow tunnel connections)
ufw limit 22/tcp

# Enable logging for denied connections (drops after rate limit)
ufw logging high
RULES
}

generate_aiops_rules() {
    cat <<'RULES'
# ==================== AIOPS SERVER (Hetzner) ====================
# Role: AI, APIs, Workers, Orchestration
# Allowed: SSH, HTTP, HTTPS, API ports, monitoring ports, Tailscale
# Denied: Direct database ports from public internet

# Default policies
ufw default deny incoming
ufw default allow outgoing

# SSH — Tailscale only
ufw allow from 100.64.0.0/10 to any port 22 proto tcp

# HTTP/HTTPS for API and dashboards
ufw allow 80/tcp
ufw allow 443/tcp

# API port (direct, for internal services)
ufw allow from 100.64.0.0/10 to any port 3000 proto tcp

# WebSocket port (real-time services)
ufw allow from 100.64.0.0/10 to any port 3001 proto tcp

# Grafana (only via Tailscale or localhost)
ufw allow from 100.64.0.0/10 to any port 3000 proto tcp

# Prometheus (only from trusted IPs + Tailscale)
ufw allow from 100.64.0.0/10 to any port 9090 proto tcp

# LiteLLM proxy (only from AIOPS itself and Tailscale)
ufw allow from 100.64.0.0/10 to any port 4000 proto tcp

# Netdata monitoring (Tailscale only)
ufw allow from 100.64.0.0/10 to any port 19999 proto tcp

# Uptime Kuma status page
ufw allow from 100.64.0.0/10 to any port 3001 proto tcp

# Tailscale full mesh
ufw allow from 100.64.0.0/10

# Docker internal networks
ufw allow from 172.16.0.0/12
ufw allow from 10.0.0.0/8

# Log denied connections
ufw logging high
RULES
}

generate_coredb_rules() {
    cat <<'RULES'
# ==================== COREDB SERVER (Hetzner) ====================
# Role: Databases, Redis, MinIO, Vector Stores, Backups
# Allowed: SSH (Tailscale), Postgres (AIOPS only), Redis (AIOPS only)
# Denied: ALL public traffic, no HTTP/HTTPS exposed

# Default policies — MOST RESTRICTIVE
ufw default deny incoming
ufw default deny outgoing
# Allow only necessary outbound (updates, DNS, NTP, Tailscale)
ufw allow out 53/udp
ufw allow out 123/udp
ufw allow out 80/tcp
ufw allow out 443/tcp

# SSH — Tailscale only
ufw allow from 100.64.0.0/10 to any port 22 proto tcp

# PostgreSQL — only from AIOPS server
ufw allow from 100.64.0.0/10 to any port 5432 proto tcp

# Redis — only from AIOPS server
ufw allow from 100.64.0.0/10 to any port 6379 proto tcp

# MinIO S3 API — only from AIOPS
ufw allow from 100.64.0.0/10 to any port 9000 proto tcp
ufw allow from 100.64.0.0/10 to any port 9001 proto tcp

# ClickHouse native — only from AIOPS
ufw allow from 100.64.0.0/10 to any port 9000 proto tcp

# Qdrant vector DB — only from AIOPS
ufw allow from 100.64.0.0/10 to any port 6333 proto tcp

# Node Exporter — monitoring pull from AIOPS
ufw allow from 100.64.0.0/10 to any port 9100 proto tcp

# PostgreSQL Exporter — monitoring pull from AIOPS
ufw allow from 100.64.0.0/10 to any port 9187 proto tcp

# Redis Exporter — monitoring pull from AIOPS
ufw allow from 100.64.0.0/10 to any port 9121 proto tcp

# Tailscale full mesh
ufw allow from 100.64.0.0/10

# Log denied connections
ufw logging high
RULES
}

print_usage() {
    cat <<EOF
Usage: $(basename "$0") <role> [--apply]

Roles:
  edge    — Hostinger public-facing server
  aiops   — Hetzner AI/API server (this server)
  coredb  — Hetzner database server

Flags:
  --dry-run  Prints rules only (default)
  --apply    Applies rules via ufw (requires root)

Examples:
  $(basename "$0") edge
  $(basename "$0") aiops --apply
EOF
}

# ── Main ──────────────────────────────────────────────────────────────────

case "$ROLE" in
    edge|EDGE)
        generate_edge_rules
        ;;
    aiops|AIOPS)
        generate_aiops_rules
        ;;
    coredb|COREDB)
        generate_coredb_rules
        ;;
    *)
        print_usage
        exit 1
        ;;
esac

if [ "$ACTION" = "--apply" ]; then
    log "Applying $ROLE firewall rules..."
    if [ "$(id -u)" -ne 0 ]; then
        warn "Must be root to apply UFW rules. Re-run with sudo."
        exit 1
    fi
    # The rules above are sourced, not piped. Re-execute ourselves.
    bash "$0" "$ROLE" --dry-run | bash
    ufw enable
    ufw status verbose
    log "UFW rules applied for role: $ROLE"
fi
