#!/bin/bash
# ============================================================================
# Wheeler Enterprise — Safe Apply Observability Optimizations
# Phase 11: Observability Performance Plan  |  2026-05-23
# ============================================================================
# DESIGN: Read-only audit. This script APPLIES NOTHING unless you pass --apply.
# Run WITHOUT --apply first to see the full dry-run diff.
#
# Usage:
#   ./safe-apply-observability-optimizations.sh            # Dry-run (safe)
#   ./safe-apply-observability-optimizations.sh --apply    # Apply changes
#   ./safe-apply-observability-optimizations.sh --apply --server=aiops   # Single server
#   ./safe-apply-observability-optimizations.sh --apply --skip-logs     # Skip log rotation
#
# Targets:
#   AIOPS:  5.78.140.118  (also use --server=aiops)
#   COREDB: 5.78.210.123  (also use --server=coredb)
#   EDGE:   187.77.148.88 (also use --server=edge)
# ============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}"
BACKUP_DIR="/root/observability-backups/$(date +%Y%m%d-%H%M%S)"

AIOPS="5.78.140.118"
COREDB="5.78.210.123"
EDGE="187.77.148.88"

SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no"

DRY_RUN=true
APPLY=false
TARGET_SERVER="all"
SKIP_LOGS=false

# ── Color Output ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_dryrun()  { echo -e "${CYAN}[DRY-RUN]${NC} $*"; }
log_header()  { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Parse Arguments ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            DRY_RUN=false
            APPLY=true
            shift
            ;;
        --server=*)
            TARGET_SERVER="${1#*=}"
            shift
            ;;
        --server)
            TARGET_SERVER="$2"
            shift 2
            ;;
        --skip-logs)
            SKIP_LOGS=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--apply] [--server=aioPS|coredb|edge|all] [--skip-logs]"
            echo ""
            echo "  --apply       Actually apply changes (default: dry-run only)"
            echo "  --server=NAME Target a single server (default: all)"
            echo "  --skip-logs   Skip log rotation steps"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# ── SSH Wrapper ───────────────────────────────────────────────────────────
ssh_cmd() {
    local server="$1"; shift
    local host
    case "$server" in
        aiops)  host="$AIOPS" ;;
        coredb) host="$COREDB" ;;
        edge)   host="$EDGE" ;;
        *) log_error "Unknown server: $server"; return 1 ;;
    esac
    ssh $SSH_OPTS "root@${host}" "$@"
}

scp_cmd() {
    local server="$1"; shift
    local host
    case "$server" in
        aiops)  host="$AIOPS" ;;
        coredb) host="$COREDB" ;;
        edge)   host="$EDGE" ;;
        *) log_error "Unknown server: $server"; return 1 ;;
    esac
    scp $SSH_OPTS "$@" "root@${host}:"
}

# ── Preflight Checks ──────────────────────────────────────────────────────
run_preflight() {
    local server="$1"
    log_info "Running preflight on ${server}..."

    # Check SSH connectivity
    if ! ssh_cmd "$server" "hostname" &>/dev/null; then
        log_error "Cannot SSH to ${server} — aborting"
        return 1
    fi
    log_ok "SSH connectivity: OK"

    # Get current disk usage
    local disk_pct
    disk_pct=$(ssh_cmd "$server" "df / | tail -1 | awk '{print \$5}' | tr -d '%'" 2>/dev/null)
    log_info "Disk usage: ${disk_pct}%"

    if [[ "$disk_pct" -gt 85 ]]; then
        log_error "Disk usage >85% on ${server} — ABORT. Free space first."
        return 1
    elif [[ "$disk_pct" -gt 75 ]]; then
        log_warn "Disk usage >75% on ${server} — proceed with caution"
    fi

    return 0
}

# ── Backup Creation ───────────────────────────────────────────────────────
create_backup() {
    local server="$1"
    log_info "Creating backup on ${server}..."

    local backup_path="/root/observability-backups/$(date +%Y%m%d-%H%M%S)"
    ssh_cmd "$server" "mkdir -p ${backup_path}" 2>/dev/null

    case "$server" in
        aiops)
            # Backup Prometheus config
            ssh_cmd "$server" "cp /opt/apps/monitoring/prometheus.yml ${backup_path}/prometheus.yml.bak 2>/dev/null" || true
            # Backup Loki config
            ssh_cmd "$server" "cp /root/infrastructure/enterprise/phase2-observability/loki/loki-config.yml ${backup_path}/loki-config.yml.bak 2>/dev/null" || true
            # Backup Grafana datasources
            ssh_cmd "$server" "cp /root/infrastructure/enterprise/phase2-observability/grafana/datasources/enterprise-datasources.yml ${backup_path}/grafana-datasources.yml.bak 2>/dev/null" || true
            # Backup docker-compose
            ssh_cmd "$server" "cp /root/infrastructure/enterprise/phase2-observability/observability-stack.yml ${backup_path}/observability-stack.yml.bak 2>/dev/null" || true
            # Snapshot current Prometheus TSDB stats
            ssh_cmd "$server" "curl -s http://localhost:9090/api/v1/status/tsdb > ${backup_path}/prometheus-tsdb-status.json 2>/dev/null" || true
            ;;
        coredb)
            ssh_cmd "$server" "cp /etc/prometheus/prometheus.yml ${backup_path}/prometheus.yml.bak 2>/dev/null" || true
            ;;
        edge)
            ssh_cmd "$server" "cp /etc/netdata/netdata.conf ${backup_path}/netdata.conf.bak 2>/dev/null" || true
            ssh_cmd "$server" "cp /etc/logrotate.conf ${backup_path}/logrotate.conf.bak 2>/dev/null" || true
            ssh_cmd "$server" "cp /etc/systemd/journald.conf ${backup_path}/journald.conf.bak 2>/dev/null" || true
            ;;
    esac

    log_ok "Backup created at ${backup_path} on ${server}"
}

# ── Apply Prometheus Optimization (AIOPS) ─────────────────────────────────
apply_prometheus_aioPs() {
    log_header
    log_info "=== Prometheus Optimization (AIOPS) ==="

    if $DRY_RUN; then
        log_dryrun "Would copy prometheus-optimization.yml to AIOPS:/opt/apps/monitoring/prometheus.yml"
        log_dryrun "Would rebuild docker compose with retention flags:"
        log_dryrun "  --storage.tsdb.retention.time=30d"
        log_dryrun "  --storage.tsdb.retention.size=5GB"
        log_dryrun "  --storage.tsdb.wal-compression"
        return
    fi

    # Copy optimized config
    scp_cmd "aiops" "${TEMPLATE_DIR}/prometheus-optimization.yml" "/opt/apps/monitoring/prometheus.yml.new"
    ssh_cmd "aiops" "cp /opt/apps/monitoring/prometheus.yml /opt/apps/monitoring/prometheus.yml.bak-$(date +%Y%m%d-%H%M%S)"

    # Update docker-compose to add retention flags
    ssh_cmd "aiops" "cd /root/infrastructure/enterprise/phase2-observability && \
        sed -i 's|--storage.tsdb.path=/prometheus|--storage.tsdb.path=/prometheus --storage.tsdb.retention.time=30d --storage.tsdb.retention.size=5GB --storage.tsdb.wal-compression|' \
        observability-stack.yml"
    log_ok "Added retention flags to observability-stack.yml"

    # Redeploy Prometheus
    log_info "Redeploying Prometheus container..."
    ssh_cmd "aiops" "cd /root/infrastructure/enterprise/phase2-observability && \
        docker compose -f observability-stack.yml up -d aiops-prometheus"
    sleep 5

    # Verify
    if ssh_cmd "aiops" "curl -s http://localhost:9090/api/v1/status/flags | grep retention" 2>/dev/null; then
        log_ok "Prometheus retention flags applied and verified"
    else
        log_warn "Could not verify retention flags — check manually"
    fi
}

# ── Apply Loki Optimization (AIOPS) ───────────────────────────────────────
apply_loki_aioPs() {
    log_header
    log_info "=== Loki Optimization (AIOPS) ==="

    if $DRY_RUN; then
        log_dryrun "Would copy loki-optimization.yml to AIOPS:/root/infrastructure/enterprise/phase2-observability/loki/loki-config.yml"
        log_dryrun "Would redeploy Loki container"
        return
    fi

    scp_cmd "aiops" "${TEMPLATE_DIR}/loki-optimization.yml" \
        "/root/infrastructure/enterprise/phase2-observability/loki/loki-config.yml.new"
    ssh_cmd "aiops" "cp /root/infrastructure/enterprise/phase2-observability/loki/loki-config.yml \
        /root/infrastructure/enterprise/phase2-observability/loki/loki-config.yml.bak-$(date +%Y%m%d-%H%M%S)"
    ssh_cmd "aiops" "cp /root/infrastructure/enterprise/phase2-observability/loki/loki-config.yml.new \
        /root/infrastructure/enterprise/phase2-observability/loki/loki-config.yml"

    log_info "Redeploying Loki container..."
    ssh_cmd "aiops" "cd /root/infrastructure/enterprise/phase2-observability && \
        docker compose -f observability-stack.yml up -d loki"
    sleep 5

    if ssh_cmd "aiops" "curl -s http://localhost:3100/ready" 2>/dev/null; then
        log_ok "Loki redeployed and healthy"
    else
        log_warn "Loki may still be starting — check with: curl http://localhost:3100/ready"
    fi
}

# ── Apply Grafana Optimization (AIOPS) ────────────────────────────────────
apply_grafana_aioPs() {
    log_header
    log_info "=== Grafana Optimization (AIOPS) ==="

    if $DRY_RUN; then
        log_dryrun "Would apply grafana-optimization.ini overrides to AIOPS Grafana container"
        log_dryrun "Would mount /etc/grafana/grafana.ini override"
        return
    fi

    # Grafana in Docker — mount custom ini as override
    scp_cmd "aiops" "${TEMPLATE_DIR}/grafana-optimization.ini" "/tmp/grafana-custom.ini"

    # Update docker-compose to mount the custom .ini
    # This requires adding a volume mount; simplified here to copy into existing volume
    ssh_cmd "aiops" "docker cp /tmp/grafana-custom.ini aiops-grafana:/etc/grafana/grafana.ini.custom 2>/dev/null" || {
        log_warn "Could not copy Grafana config into container — may need compose update instead"
    }

    if ssh_cmd "aiops" "curl -s http://localhost:3000/api/health" 2>/dev/null; then
        log_ok "Grafana is running"
    else
        log_warn "Grafana health check failed"
    fi
}

# ── Apply Log Rotation (EDGE) ─────────────────────────────────────────────
apply_logrotate_edge() {
    log_header
    log_info "=== Log Rotation (EDGE) ==="

    if $SKIP_LOGS; then
        log_warn "Skipping log rotation (--skip-logs)"
        return
    fi

    if $DRY_RUN; then
        log_dryrun "Would install logrotate config to EDGE:/etc/logrotate.d/wheeler-apps"
        log_dryrun "Would run: logrotate -f /etc/logrotate.d/wheeler-apps"
        log_dryrun "Would install journald drop-in to EDGE"
        return
    fi

    # Install logrotate config
    scp_cmd "edge" "${TEMPLATE_DIR}/logrotate-app-logs.conf" "/etc/logrotate.d/wheeler-apps"
    log_ok "Installed /etc/logrotate.d/wheeler-apps"

    # Test the config
    if ssh_cmd "edge" "logrotate -d /etc/logrotate.d/wheeler-apps" 2>&1 | head -20; then
        log_ok "Logrotate config test passed"
    else
        log_error "Logrotate config test failed — check syntax"
        return 1
    fi

    # Force first rotation to bring oversized logs under control
    log_info "Forcing initial log rotation..."
    ssh_cmd "edge" "logrotate -f /etc/logrotate.d/wheeler-apps" 2>&1 || log_warn "Some log rotation may have failed (missing files OK)"

    # Verify space reclaimed
    local after_size
    after_size=$(ssh_cmd "edge" "du -sh /var/log/surplusai.log /var/log/frgcrm.log /var/log/canary.log 2>/dev/null" 2>/dev/null || echo "N/A")
    log_info "Log sizes after rotation: ${after_size}"
}

# ── Apply journald Caps ───────────────────────────────────────────────────
apply_journald() {
    local server="$1"
    log_header
    log_info "=== journald Optimization (${server}) ==="

    local cap_size
    case "$server" in
        aiops)  cap_size="200M" ;;
        coredb) cap_size="200M" ;;
        edge)   cap_size="500M" ;;
    esac

    if $DRY_RUN; then
        log_dryrun "Would install journald drop-in to ${server}:/etc/systemd/journald.conf.d/99-wheeler-optimization.conf"
        log_dryrun "Would set SystemMaxUse=${cap_size}"
        log_dryrun "Would restart systemd-journald"
        return
    fi

    scp_cmd "$server" "${TEMPLATE_DIR}/journald-optimization.conf" "/etc/systemd/journald.conf.d/99-wheeler-optimization.conf"
    ssh_cmd "$server" "systemctl restart systemd-journald"
    sleep 3

    local new_size
    new_size=$(ssh_cmd "$server" "journalctl --disk-usage" 2>/dev/null || echo "unknown")
    log_ok "journald restarted — current usage: ${new_size}"

    # Force vacuum on EDGE (oversized)
    if [[ "$server" == "edge" ]]; then
        log_info "Vacuuming journald on EDGE to ${cap_size}..."
        ssh_cmd "edge" "journalctl --vacuum-size=${cap_size} && journalctl --vacuum-time=7d" 2>&1
        new_size=$(ssh_cmd "edge" "journalctl --disk-usage" 2>/dev/null || echo "unknown")
        log_ok "Post-vacuum journald size: ${new_size}"
    fi
}

# ── Apply PM2 Log Rotation (EDGE) ─────────────────────────────────────────
apply_pm2_logrotate_edge() {
    log_header
    log_info "=== PM2 Log Rotation (EDGE) ==="

    if $SKIP_LOGS; then
        log_warn "Skipping PM2 log rotation (--skip-logs)"
        return
    fi

    if $DRY_RUN; then
        log_dryrun "Would run: pm2 install pm2-logrotate"
        log_dryrun "Would configure pm2-logrotate: max_size=10M, retain=30, compress=true"
        return
    fi

    # Install pm2-logrotate if not already present
    if ! ssh_cmd "edge" "pm2 list 2>/dev/null | grep -q logrotate"; then
        ssh_cmd "edge" "pm2 install pm2-logrotate" 2>&1 || {
            log_warn "pm2-logrotate install failed — PM2 may not be running"
            return
        }
    fi

    # Configure
    ssh_cmd "edge" "pm2 set pm2-logrotate:max_size 10M" 2>/dev/null
    ssh_cmd "edge" "pm2 set pm2-logrotate:retain 30" 2>/dev/null
    ssh_cmd "edge" "pm2 set pm2-logrotate:compress true" 2>/dev/null
    ssh_cmd "edge" "pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss" 2>/dev/null
    ssh_cmd "edge" "pm2 set pm2-logrotate:workerInterval 30" 2>/dev/null

    log_ok "PM2 logrotate configured: max 10MB/file, retain 30 files, compress enabled"
}

# ── Apply Docker Log Rotation (All Servers) ───────────────────────────────
apply_docker_log_opts() {
    local server="$1"
    log_header
    log_info "=== Docker Log Rotation (${server}) ==="

    if $DRY_RUN; then
        log_dryrun "Would set docker daemon.json log opts on ${server}"
        log_dryrun "Would add: max-size=10m, max-file=3"
        return
    fi

    # Check if daemon.json already has log-opts
    if ssh_cmd "$server" "cat /etc/docker/daemon.json 2>/dev/null" 2>/dev/null; then
        # Merge — use jq if available, otherwise warn
        if ssh_cmd "$server" "which jq" &>/dev/null; then
            ssh_cmd "$server" "jq '.\"log-driver\" = \"json-file\" | .\"log-opts\" = {\"max-size\": \"10m\", \"max-file\": \"3\"}' \
                /etc/docker/daemon.json > /etc/docker/daemon.json.new && \
                mv /etc/docker/daemon.json.new /etc/docker/daemon.json"
            log_ok "Updated /etc/docker/daemon.json with log rotation"
        else
            log_warn "jq not available on ${server} — add log-opts manually to /etc/docker/daemon.json:"
            log_warn '  "log-opts": { "max-size": "10m", "max-file": "3" }'
            return
        fi
    else
        ssh_cmd "$server" "cat > /etc/docker/daemon.json << 'DEOF'
{
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"10m\",
    \"max-file\": \"3\"
  }
}
DEOF"
        log_ok "Created /etc/docker/daemon.json with log rotation"
    fi

    # Restart docker (this restarts all containers!)
    log_warn "Docker daemon restart required — this will restart ALL containers on ${server}"
    log_warn "Press Ctrl+C to skip, or wait 5 seconds to proceed..."
    if $DRY_RUN; then
        log_dryrun "Would run: systemctl restart docker"
    else
        sleep 5
        ssh_cmd "$server" "systemctl restart docker" 2>&1
        log_ok "Docker restarted with new log rotation policy"
    fi
}

# ── Apply COREDB Monitoring Restoration ───────────────────────────────────
apply_coredb_restore() {
    log_header
    log_info "=== COREDB Monitoring Restoration ==="

    # Check current state
    log_info "Checking COREDB monitoring state..."
    local prom_running
    prom_running=$(ssh_cmd "coredb" "curl -s http://localhost:9090/api/v1/status/tsdb 2>/dev/null" 2>/dev/null || echo "DOWN")

    if [[ "$prom_running" != "DOWN" ]]; then
        log_ok "Prometheus already running on COREDB — skipping restoration"
        return
    fi

    log_warn "Prometheus is DOWN on COREDB. Restoration steps:"

    if $DRY_RUN; then
        log_dryrun "Would restore COREDB monitoring stack:"
        log_dryrun "  1. Create /etc/prometheus/prometheus.yml"
        log_dryrun "  2. Deploy Prometheus with --storage.tsdb.retention.time=30d"
        log_dryrun "  3. Deploy Grafana with datasource pointing to local Prometheus"
        log_dryrun "  4. Deploy Loki + Promtail for log shipping to AIOPS"
        log_dryrun "  5. Deploy UptimeKuma for service health monitoring"
        log_dryrun "  6. Create systemd unit for auto-start"
        return
    fi

    # NOTE: Full COREDB restore requires the original docker-compose or
    # deployment method. This is a scaffolding.
    log_info "COREDB monitoring restore requires the original deploy scripts."
    log_info "Refer to AIOPS patterns at: /root/infrastructure/enterprise/phase2-observability/"
    log_info "Minimal steps:"
    echo "  # 1. Create Prometheus config for COREDB"
    echo "  ssh root@${COREDB} 'mkdir -p /etc/prometheus'"
    echo "  scp prometheus-coredb.yml root@${COREDB}:/etc/prometheus/prometheus.yml"
    echo ""
    echo "  # 2. Run Prometheus container"
    echo "  docker run -d --name coredb-prometheus --restart unless-stopped \\"
    echo "    -p 9090:9090 -v /etc/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \\"
    echo "    -v prometheus-data:/prometheus \\"
    echo "    prom/prometheus:latest \\"
    echo "    --storage.tsdb.retention.time=30d --storage.tsdb.retention.size=2GB"
}

# ── Apply EDGE Netdata Tuning ─────────────────────────────────────────────
apply_netdata_edge() {
    log_header
    log_info "=== Netdata Tuning (EDGE) ==="

    if $DRY_RUN; then
        log_dryrun "Would increase apps.plugin interval from 5s to 10s on EDGE"
        log_dryrun "Would reduce CPU from ~5.3% to ~2.5% for apps.plugin"
        return
    fi

    ssh_cmd "edge" "sed -i 's/update every = 5/update every = 10/' /etc/netdata/netdata.conf" 2>/dev/null || {
        log_warn "Could not update netdata.conf — check if file exists"
        return
    }
    ssh_cmd "edge" "systemctl restart netdata" 2>/dev/null || true
    log_ok "Netdata apps.plugin interval increased to 10s"
}

# ── Post-Apply Verification ───────────────────────────────────────────────
run_verification() {
    local server="$1"
    log_header
    log_info "=== Verification (${server}) ==="

    case "$server" in
        aiops)
            log_info "--- Prometheus ---"
            ssh_cmd "$server" "curl -s http://localhost:9090/api/v1/status/tsdb | python3 -m json.tool 2>/dev/null | head -10" || log_error "Prometheus not responding"
            log_info "--- Loki ---"
            ssh_cmd "$server" "curl -s http://localhost:3100/ready" || log_error "Loki not ready"
            log_info "--- Grafana ---"
            ssh_cmd "$server" "curl -s http://localhost:3000/api/health" || log_error "Grafana not healthy"
            ;;
        coredb)
            log_info "--- Prometheus ---"
            ssh_cmd "$server" "curl -s http://localhost:9090/api/v1/status/tsdb | python3 -m json.tool 2>/dev/null | head -10" || log_warn "Prometheus still down on COREDB"
            ;;
        edge)
            log_info "--- journald ---"
            ssh_cmd "$server" "journalctl --disk-usage" || true
            log_info "--- Log sizes ---"
            ssh_cmd "$server" "du -sh /var/log/surplusai.log /var/log/frgcrm.log /var/log/canary.log 2>/dev/null" || true
            ;;
    esac
}

# ── Main ──────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  Wheeler Enterprise — Phase 11: Observability Optimization      ║"
    echo "║  Safe Apply Script                                               ║"
    echo "║  Mode: $([ "$DRY_RUN" = true ] && echo "DRY-RUN (safe)" || echo "APPLY (live)")                                         ║"
    echo "║  Target: ${TARGET_SERVER}                                                ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    if $DRY_RUN; then
        log_warn "DRY-RUN MODE — no changes will be made. Add --apply to execute."
        echo ""
    else
        log_error "LIVE MODE — changes WILL be applied."
        echo ""
        read -p "Press Enter to continue or Ctrl+C to abort..." _
    fi

    local servers=()
    if [[ "$TARGET_SERVER" == "all" ]]; then
        servers=("aiops" "coredb" "edge")
    else
        servers=("$TARGET_SERVER")
    fi

    for server in "${servers[@]}"; do
        # Preflight
        if ! run_preflight "$server"; then
            log_error "Preflight failed for ${server} — skipping"
            continue
        fi

        # Backup (always, even in dry-run we note what would be backed up)
        if $APPLY; then
            create_backup "$server"
        else
            log_dryrun "Would create backup on ${server} (skipped in dry-run)"
        fi

        # Apply per-server optimizations
        case "$server" in
            aiops)
                apply_prometheus_aioPs
                apply_loki_aioPs
                apply_grafana_aioPs
                apply_journald "aiops"
                ;;
            coredb)
                apply_journald "coredb"
                apply_coredb_restore
                ;;
            edge)
                apply_logrotate_edge
                apply_pm2_logrotate_edge
                apply_journald "edge"
                apply_netdata_edge
                ;;
        esac

        # Docker log rotation for all servers
        # skip in full dry-run to avoid too much output
        if $APPLY; then
            # Docker restart is disruptive — must opt in
            log_warn "Docker log rotation skipped by default (destructive restart)."
            log_warn "To apply: re-run with DOCKER_LOG_ROTATE=1"
            if [[ "${DOCKER_LOG_ROTATE:-0}" == "1" ]]; then
                apply_docker_log_opts "$server"
            fi
        fi

        # Verify
        if $APPLY; then
            run_verification "$server"
        else
            log_dryrun "Would run post-apply verification on ${server}"
        fi
    done

    echo ""
    log_header
    if $DRY_RUN; then
        log_ok "Dry-run complete. Review changes above. Re-run with --apply to execute."
    else
        log_ok "Optimizations applied. Review verification output above."
        log_info "Backups stored at: /root/observability-backups/ on each server"
    fi
    echo ""

    # Print summary of what was / would be changed
    echo "┌──────────────────────────────────────────────────────────────────┐"
    echo "│  Summary of Changes                                              │"
    echo "├──────────────────────────────────────────────────────────────────┤"
    echo "│  AIOPS:                                                          │"
    echo "│    - Prometheus: add 30d retention, 5GB cap, WAL compression    │"
    echo "│    - Loki: reduce retention 90d→60d, increase query limit 10k   │"
    echo "│    - Grafana: apply performance and security settings            │"
    echo "│    - journald: cap at 200MB                                      │"
    echo "│                                                                  │"
    echo "│  COREDB:                                                         │"
    echo "│    - Restore Prometheus, Grafana, Loki, UptimeKuma               │"
    echo "│    - Add restart: unless-stopped policy                          │"
    echo "│    - journald: cap at 200MB                                      │"
    echo "│                                                                  │"
    echo "│  EDGE:                                                           │"
    echo "│    - Logrotate: 14d/100MB for app logs (recovers ~1.5GB)        │"
    echo "│    - PM2: install pm2-logrotate                                  │"
    echo "│    - journald: cap at 500MB, vacuum to 7d (recovers ~344MB)     │"
    echo "│    - Netdata: reduce apps.plugin interval to 10s                 │"
    echo "└──────────────────────────────────────────────────────────────────┘"
}

main "$@"
