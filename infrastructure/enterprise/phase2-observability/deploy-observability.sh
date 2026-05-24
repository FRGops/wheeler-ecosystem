#!/usr/bin/env bash
# =============================================================================
# Wheeler Enterprise — Observability Stack Deploy Script
# =============================================================================
# Usage: bash deploy-observability.sh [--up|--down|--status]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:---up}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }

preflight() {
    log "Running preflight checks..."

    # Check Docker
    if ! docker info &>/dev/null; then
        warn "Docker is not running. Start Docker first."
        exit 1
    fi

    # Check required networks
    for net in monitoring traefik-public; do
        if ! docker network inspect "$net" &>/dev/null; then
            warn "Network '$net' does not exist. Creating..."
            docker network create "$net"
        fi
    done

    # Check environment variables
    if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
        warn "GRAFANA_ADMIN_PASSWORD not set. Using default (change immediately!)."
    fi

    # Verify config files exist
    for cfg in \
        "$SCRIPT_DIR/prometheus/prometheus.yml" \
        "$SCRIPT_DIR/alertmanager/alertmanager-config.yml" \
        "$SCRIPT_DIR/loki/loki-config.yml" \
        "$SCRIPT_DIR/promtail/promtail-config.yml"; do
        if [ ! -f "$cfg" ]; then
            warn "Missing config: $cfg"
        else
            log "Found: $cfg"
        fi
    done

    log "Preflight complete."
}

case "$ACTION" in
    --up|up)
        preflight
        log "Starting observability stack..."
        docker compose -f "$SCRIPT_DIR/observability-stack.yml" up -d

        log "Waiting for services to become healthy..."
        sleep 10

        for svc in prometheus grafana loki promtail alertmanager uptime-kuma; do
            if docker ps --filter "name=$svc" --filter "health=healthy" -q | grep -q .; then
                log "$svc: healthy"
            else
                warn "$svc: starting or unhealthy"
            fi
        done

        log "Stack deployed. Access:"
        log "  Grafana:      https://grafana.wheeler.ai"
        log "  Uptime Kuma:  https://uptime.wheeler.ai"
        log "  Prometheus:   http://<tailscale-ip>:9090 (admin)"
        ;;

    --down|down)
        log "Stopping observability stack..."
        docker compose -f "$SCRIPT_DIR/observability-stack.yml" down
        log "Stack stopped (volumes preserved)."
        ;;

    --status|status)
        docker compose -f "$SCRIPT_DIR/observability-stack.yml" ps
        ;;

    --restart)
        log "Restarting stack..."
        docker compose -f "$SCRIPT_DIR/observability-stack.yml" restart
        log "Stack restarted."
        ;;

    *)
        echo "Usage: $0 [--up|--down|--status|--restart]"
        exit 1
        ;;
esac
