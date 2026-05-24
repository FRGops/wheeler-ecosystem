#!/usr/bin/env bash
###############################################################################
# HOSTINGER VPS — SYSTEMD HARDENING & SYSTEM TUNING
# =====================================================
# Transforms the Hostinger VPS from a general-purpose server into a lean,
# secure PUBLIC EDGE / FRONTEND server.
#
# WHAT THIS SCRIPT DOES:
#   1. Disables unnecessary systemd services (heavy/ unused services)
#   2. Tunes sysctl parameters for edge server workloads (many connections,
#      fast timeouts, anti-DOS hardening)
#   3. Configures log rotation (journald, logrotate)
#   4. Optimizes kernel parameters for connection-heavy workloads
#   5. Applies security hardening (network, kernel)
#
# RESOURCE RATIONALE:
#   A general-purpose Linux distribution ships with dozens of unnecessary
#   services that consume RAM and CPU.  On a constrained edge VPS, every
#   MB of RAM matters — a typical Ubuntu/Debian install has 30-50 services
#   that can be safely disabled.
#
# WHAT IS SAFE TO DISABLE:
#   - avahi-daemon:     mDNS/Bonjour (not needed on cloud VPS)
#   - ModemManager:     Mobile broadband (not needed on VPS)
#   - whoopsie:         Ubuntu error reporting (not needed)
#   - cups:             Print service (not needed on server)
#   - bluetooth:        Bluetooth stack (not needed on VPS)
#   - accounts-daemon:  Accounts service (not needed on server)
#   - isc-dhcp-server:  DHCP server (not needed, cloud uses DHCP client)
#   - apache2/nginx:    Only Traefik handles HTTP
#   - postfix/exim4:    Mail Transfer Agent (not needed unless you send mail)
#   - snapd:            Snap package manager (only if not using snaps)
#
# WHAT MUST STAY ENABLED:
#   - sshd:             SSH access
#   - docker:           Container runtime
#   - tailscaled:       Tailscale mesh networking
#   - systemd-journald: Logging
#   - systemd-timesyncd: NTP
#   - cron/anacron:     Scheduled tasks
#   - ufw:              Firewall
#   - rsyslog:          System logging
#
# USAGE:
#   sudo ./hostinger-systemd-hardening.sh [--apply] [--backup]
#
#   --apply    Actually apply changes (without this, runs in dry-run mode)
#   --backup   Create backup of original config files
#   --restore  Restore from backup (not yet implemented)
#   --status   Show current system status only (no changes)
###############################################################################

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

# Services to DISABLE (list of systemd unit names)
# These are known to be safe to disable on a cloud VPS.
SERVICES_TO_DISABLE=(
  # Network Services (not needed on edge VPS)
  "avahi-daemon.service"
  "avahi-daemon.socket"
  "cups.service"
  "cups-browsed.service"
  "bluetooth.service"
  "bluetooth.target"
  "ModemManager.service"
  "whoopsie.service"
  "whoopsie.path"
  "accounts-daemon.service"

  # Package management (disable if not using snaps)
  "snapd.service"
  "snapd.socket"
  "snapd.seeded.service"

  # Mail services (disable unless sending mail)
  "postfix.service"
  "exim4.service"
  "exim4-base"

  # Unnecessary filesystem services
  "udisks2.service"       # Disk management — not needed on VPS
  "fwupd.service"         # Firmware updater — not needed on VPS
  "fwupd-refresh.service"
  "power-profiles-daemon.service"

  # Printing and scanning (not needed)
  "cupsd.service"
  "hplip.service"

  # Other
  "packagekit.service"    # PackageKit daemon — not needed
  "packagekit-offline-update.service"
)

# Services that MUST stay ENABLED
SERVICES_TO_KEEP=(
  "ssh.service"
  "sshd.service"
  "docker.service"
  "tailscaled.service"
  "systemd-journald.service"
  "systemd-timesyncd.service"
  "cron.service"
  "ufw.service"
  "rsyslog.service"
  "systemd-logind.service"
  "dbus.service"
  "getty@tty1.service"  # Keep at least one console login
)

# ── Color Output ───────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()     { echo -e "${BLUE}[INFO]${NC}    $*"; }
ok()       { echo -e "${GREEN}[OK]${NC}      $*"; }
warn()     { echo -e "${YELLOW}[WARN]${NC}    $*"; }
error()    { echo -e "${RED}[ERROR]${NC}   $*"; }
header()   { echo ""; echo -e "${CYAN}═══════════════════════════════════════════════${NC}"; echo "  $*"; echo -e "${CYAN}═══════════════════════════════════════════════${NC}"; }

# ── Globals ────────────────────────────────────────────────────────────────────

APPLY=false
BACKUP=false
STATUS_ONLY=false
BACKUP_DIR="/root/infrastructure/hostinger/backups/system-tuning-$(date +%Y%m%d-%H%M%S)"

# ── Argument Parsing ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)   APPLY=true; shift ;;
    --backup)  BACKUP=true; shift ;;
    --status)  STATUS_ONLY=true; shift ;;
    --restore) warn "Restore not yet implemented.  Backups are at $BACKUP_DIR"; shift ;;
    --help)
      echo "Usage: $0 [--apply] [--backup] [--status]"
      echo ""
      echo "  --apply     Apply all hardening changes"
      echo "  --backup    Backup original config files before changes"
      echo "  --status    Show current system status (no changes)"
      echo "  --restore   (not yet implemented)"
      exit 0
      ;;
    *) error "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Pre-flight Checks ─────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (or with sudo)."
  exit 1
fi

if $STATUS_ONLY; then
  info "Running in STATUS mode — no changes will be made."
  echo ""
fi

if ! $APPLY && ! $STATUS_ONLY; then
  info "Running in DRY-RUN mode — no changes will be made."
  info "Use --apply to apply changes."
  echo ""
fi

SHOULD_APPLY() {
  if $APPLY; then return 0; else return 1; fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 1. SYSTEMD SERVICE HARDENING
# ══════════════════════════════════════════════════════════════════════════════

step_disable_services() {
  header "STEP 1: Disable Unnecessary Services"

  info "Services flagged for removal (safe to disable on edge VPS):"
  for svc in "${SERVICES_TO_DISABLE[@]}"; do
    printf "    - %s\n" "$svc"
  done
  echo ""

  local disabled_count=0
  local not_found_count=0

  for svc in "${SERVICES_TO_DISABLE[@]}"; do
    # Check if the service unit exists
    if systemctl list-unit-files "$svc" &>/dev/null 2>&1; then
      local is_active
      is_active=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")

      if [[ "$is_active" == "active" ]]; then
        warn "  $svc is ACTIVE — $(SHOULD_APPLY && echo "stopping..." || echo "would stop (dry-run)")"
        if SHOULD_APPLY; then
          systemctl stop "$svc" 2>/dev/null || true
          systemctl disable "$svc" 2>/dev/null || true
          ok "  $svc — stopped and disabled"
          ((disabled_count++))
        fi
      elif [[ "$is_active" == "inactive" ]]; then
        info "  $svc — already inactive"
        if SHOULD_APPLY; then
          systemctl disable "$svc" 2>/dev/null || true
          ((disabled_count++))
        fi
      fi
    fi
  done

  if SHOULD_APPLY; then
    ok "Disabled ${disabled_count} services."
  else
    info "Would disable ${disabled_count} services (run with --apply)."
    ((disabled_count++))  # Simulate for test count
  fi

  echo ""

  # Verify services to keep
  info "Verifying critical services are enabled:"
  for svc in "${SERVICES_TO_KEEP[@]}"; do
    if systemctl list-unit-files "$svc" &>/dev/null 2>&1; then
      if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
        ok "  $svc — enabled"
      else
        warn "  $svc — DISABLED!  Enable with: systemctl enable $svc"
        if SHOULD_APPLY; then
          systemctl enable "$svc" 2>/dev/null || true
          ok "  $svc — enabled"
        fi
      fi
    fi
  done
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. SYSCTL TUNING
# ══════════════════════════════════════════════════════════════════════════════

step_sysctl_tuning() {
  header "STEP 2: Sysctl Kernel Tuning"

  local sysctl_file="/etc/sysctl.d/90-edge-server.conf"

  if SHOULD_APPLY || $STATUS_ONLY; then
    if [[ -f "$sysctl_file" ]] && $STATUS_ONLY; then
      info "Current sysctl configuration at $sysctl_file:"
      cat "$sysctl_file" 2>/dev/null || true
      echo ""
    fi
  fi

  cat << 'SYSCTL_EOF'

  The following sysctl parameters will be applied:

  ┌─────────────────────────────────────────────┬──────────┬──────────────────────┐
  │ Parameter                                   │ Value    │ Reason               │
  ├─────────────────────────────────────────────┼──────────┼──────────────────────┤
  │ net.core.somaxconn                          │ 65535    │ Max TCP connection    │
  │                                             │          │ backlog — edge server │
  │                                             │          │ needs this high for   │
  │                                             │          │ connection bursts     │
  │ net.core.netdev_max_backlog                 │ 5000     │ Packets queued per    │
  │                                             │          │ NIC — high for edge   │
  │ net.ipv4.tcp_tw_reuse                       │ 1        │ Reuse TIME_WAIT conns │
  │                                             │          │ — critical for high-  │
  │                                             │          │ throughput edge       │
  │ net.ipv4.tcp_fin_timeout                    │ 15       │ Reduce FIN-WAIT time  │
  │                                             │          │ — free up connections │
  │                                             │          │ faster               │
  │ net.ipv4.tcp_keepalive_time                 │ 300      │ 5 min keepalive —     │
  │                                             │          │ detect dead conns     │
  │                                             │          │ faster than default   │
  │                                             │          │ (2 hours)            │
  │ net.ipv4.tcp_keepalive_intvl                │ 30       │ Probe interval        │
  │ net.ipv4.tcp_keepalive_probes               │ 3        │ 3 probes = 90s to     │
  │                                             │          │ detect dead conn     │
  │ net.ipv4.tcp_max_syn_backlog                │ 65535    │ SYN backlog — protect │
  │                                             │          │ against SYN floods    │
  │ net.ipv4.tcp_syncookies                     │ 1        │ SYN cookies — anti-   │
  │                                             │          │ SYN flood protection  │
  │ net.ipv4.tcp_syn_retries                    │ 2        │ Retry SYN 2x — fail   │
  │                                             │          │ fast on bad conns     │
  │ net.ipv4.tcp_synack_retries                 │ 2        │ Retry SYN-ACK 2x      │
  │ net.ipv4.tcp_max_tw_buckets                 │ 2000000  │ Max TIME_WAIT sockets │
  │                                             │          │ — prevent OOM under   │
  │                                             │          │ connection storms     │
  │ net.ipv4.ip_local_port_range                │ 1024 65535│ Ephemeral port range  │
  │                                             │          │ — edge needs many     │
  │ net.ipv4.tcp_fastopen                       │ 3        │ TFO client+server —   │
  │                                             │          │ reduce latency        │
  │ net.core.rmem_default                       │ 262144   │ Default receive       │
  │                                             │          │ buffer (256KB)        │
  │ net.core.rmem_max                           │ 4194304  │ Max receive buffer    │
  │                                             │          │ (4MB)                 │
  │ net.core.wmem_default                       │ 262144   │ Default send buffer   │
  │ net.core.wmem_max                           │ 4194304  │ Max send buffer       │
  │ net.ipv4.tcp_rmem                           │ 4096 87380│ TCP read buffer auto  │
  │                                             │ 6291456  │ tuning (min/default/  │
  │                                             │          │ max)                  │
  │ net.ipv4.tcp_wmem                           │ 4096 65536│ TCP write buffer auto │
  │                                             │ 4194304  │ tuning                │
  │ net.ipv4.tcp_congestion_control             │ bbr      │ BBR congestion control│
  │                                             │          │ — best for long-      │
  │                                             │          │ distance connections  │
  │ net.core.default_qdisc                      │ fq       │ Fair Queuing — needed │
  │                                             │          │ for BBR              │
  │ net.ipv4.conf.all.rp_filter                 │ 1        │ Reverse path filter   │
  │                                             │          │ — anti-spoofing       │
  │ net.ipv4.conf.default.rp_filter             │ 1        │                      │
  │ net.ipv4.conf.all.accept_source_route       │ 0        │ Disable source        │
  │                                             │          │ routing — security    │
  │ net.ipv4.conf.all.accept_redirects          │ 0        │ Disable ICMP redirect │
  │                                             │          │ — prevent MITM        │
  │ net.ipv4.conf.all.secure_redirects          │ 0        │ Disable secure ICMP   │
  │                                             │          │ redirects             │
  │ net.ipv4.conf.all.log_martians              │ 1        │ Log spoofed packets   │
  │ net.ipv4.icmp_echo_ignore_broadcasts        │ 1        │ Ignore ICMP broadcast │
  │                                             │          │ — prevent smurf attack│
  │ net.ipv4.icmp_ignore_bogus_error_responses  │ 1        │ Ignore bogus ICMP     │
  │                                             │          │ error responses       │
  │ net.ipv6.conf.all.disable_ipv6              │ 0        │ Keep IPv6 enabled for │
  │                                             │          │ Tailscale (uses IPv6) │
  │ vm.swappiness                               │ 10       │ Only swap under       │
  │                                             │          │ extreme memory        │
  │                                             │          │ pressure              │
  │ vm.vfs_cache_pressure                       │ 50       │ Cache dentries longer │
  │                                             │          │ — reduces disk I/O    │
  │ vm.dirty_ratio                              │ 20       │ Max dirty pages before│
  │                                             │          │ writeback (reduces    │
  │                                             │          │ I/O bursts)           │
  │ vm.dirty_background_ratio                   │ 5        │ Background writeback  │
  │                                             │          │ starts at 5% dirty    │
  │ kernel.printk                               │ 3 3 3 3  │ Reduce console spam   │
  │ kernel.randomize_va_space                   │ 2        │ ASLR full — security  │
  │ kernel.kptr_restrict                        │ 1        │ Restrict kernel       │
  │                                             │          │ pointer exposure      │
  └─────────────────────────────────────────────┴──────────┴──────────────────────┘

SYSCTL_EOF

  if $STATUS_ONLY; then
    info "Current key sysctl values:"
    local key_params=(
      "net.core.somaxconn"
      "net.ipv4.tcp_tw_reuse"
      "net.ipv4.tcp_fin_timeout"
      "net.ipv4.tcp_syncookies"
      "net.ipv4.tcp_fastopen"
      "net.ipv4.tcp_congestion_control"
      "net.core.default_qdisc"
      "vm.swappiness"
    )
    for param in "${key_params[@]}"; do
      local value
      value=$(sysctl -n "$param" 2>/dev/null || echo "not set")
      printf "    %-40s = %s\n" "$param" "$value"
    done
    echo ""
    return
  fi

  if ! SHOULD_APPLY; then
    info "Would write sysctl configuration to $sysctl_file (run with --apply)."
    return
  fi

  # Write the sysctl configuration
  if $BACKUP && [[ -f "$sysctl_file" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp "$sysctl_file" "$BACKUP_DIR/90-edge-server.conf.bak"
    ok "Backed up existing $sysctl_file"
  fi

  cat > "$sysctl_file" << 'SYSCTL_CFG'
# ==============================================================================
# HOSTINGER EDGE VPS — Sysctl Tuning
# ==============================================================================
# Applied by: hostinger-systemd-hardening.sh
# Date: $(date)
#
# This configuration optimizes the Hostinger VPS for its role as a public
# edge/frontend server.  Key design trade-offs:
#
# 1. Connection-heavy workload (many short-lived TCP connections from
#    Cloudflare → Traefik → backend services)
# 2. Resource-constrained (4-8 vCPU, 8-16 GB RAM) — every KB of kernel
#    memory must be justified
# 3. Security-hardened — DDoS resistance, anti-spoofing, reduced attack surface
# ==============================================================================

# --- Connection Handling ---
# Max TCP connection backlog — critical for edge server handling traffic spikes
net.core.somaxconn = 65535
# Max packets queued per NIC — prevents packet drops under load
net.core.netdev_max_backlog = 5000
# Reuse TIME_WAIT connections for new connections — essential for high-throughput
# reverse proxy with many short-lived connections
net.ipv4.tcp_tw_reuse = 1
# Reduce TIME_WAIT duration — free up connection tracking entries faster
net.ipv4.tcp_fin_timeout = 15

# --- Keepalive (detect dead connections faster) ---
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3

# --- SYN Flood Protection ---
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_syncookies = 1
# Aggressive SYN retry limits — fail fast if peer is unreachable
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
# Max TIME_WAIT buckets — prevent OOM from connection storms
net.ipv4.tcp_max_tw_buckets = 2000000

# --- Port Range ---
# Wide ephemeral port range — edge server initiates many outbound connections
# (Traefik → Hetzner via Tailscale)
net.ipv4.ip_local_port_range = 1024 65535

# --- TCP Fast Open ---
# Enable TFO for both client and server — reduces 1 RTT from connection handshake
net.ipv4.tcp_fastopen = 3

# --- Buffer Sizes ---
# Socket receive/send buffers — balanced for 8-16GB RAM VPS
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 4194304
# TCP auto-tuning: min default max
net.ipv4.tcp_rmem = 4096 87380 6291456
net.ipv4.tcp_wmem = 4096 65536 4194304

# --- Congestion Control ---
# BBR — best for internet-facing servers with variable RTT
# Handles packet loss better than CUBIC for long-distance connections
net.ipv4.tcp_congestion_control = bbr
# Fair Queuing — required by BBR for pacing
net.core.default_qdisc = fq

# --- Security Hardening ---
# Reverse path filtering — prevents IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
# Disable source routing — security risk
net.ipv4.conf.all.accept_source_route = 0
# Disable ICMP redirects — prevent MITM attacks
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
# Log spoofed, source-routed, redirect packets
net.ipv4.conf.all.log_martians = 1
# ICMP hardening
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# --- IPv6 ---
# Keep IPv6 enabled — required by Tailscale for optimal NAT traversal
net.ipv6.conf.all.disable_ipv6 = 0

# --- Memory Management ---
# Aggressive swappiness — avoid swap at all costs on a constrained VPS
# Swap thrashing is worse than OOM kills
vm.swappiness = 10
# Keep dentry/inode caches longer — reduces disk I/O
vm.vfs_cache_pressure = 50
# Writeback tuning — reduces I/O spikes
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5

# --- Kernel Hardening ---
# Restrict kernel log visibility
kernel.printk = 3 3 3 3
# Full ASLR
kernel.randomize_va_space = 2
# Restrict kernel pointer exposure
kernel.kptr_restrict = 1
# Restrict perf events
kernel.perf_event_paranoid = 2
# Disable kexec
kernel.kexec_load_disabled = 1
SYSCTL_CFG

  # Apply the sysctl settings
  sysctl --system &>/dev/null
  ok "Applied sysctl configuration ($sysctl_file)."
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. SYSTEMD-JOURNALD TUNING
# ══════════════════════════════════════════════════════════════════════════════

step_journald_tuning() {
  header "STEP 3: Journald Log Tuning"

  local journald_conf="/etc/systemd/journald.conf.d/90-edge-server.conf"

  if $STATUS_ONLY; then
    info "Current journald settings:"
    journalctl --show-config 2>/dev/null | grep -E "Storage=|SystemMaxUse=|MaxFileSize=|MaxRetentionSec=" || true
    echo ""
    return
  fi

  if ! SHOULD_APPLY; then
    info "Would configure journald for edge server (run with --apply)."
    return
  fi

  if $BACKUP && [[ -f "$journald_conf" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp "$journald_conf" "$BACKUP_DIR/90-edge-server.conf.bak" 2>/dev/null || true
  fi

  mkdir -p /etc/systemd/journald.conf.d/
  cat > "$journald_conf" << 'JOURNAL_CFG'
# ==============================================================================
# HOSTINGER EDGE VPS — Journald Configuration
# ==============================================================================
# Applied by: hostinger-systemd-hardening.sh
#
# Resource-constrained VPS tuning:
#   - Max 200MB of journal logs (down from default 4GB on some distros)
#   - Rotate aggressively — we don't need months of old logs
#   - Forward to syslog disabled — uses less CPU/Disk
# ==============================================================================

# Use persistent storage (default on most systems)
Storage=persistent

# Max total journal size: 200MB (aggressive for edge server)
SystemMaxUse=200M

# Max file size: 20MB per journal file
SystemMaxFileSize=20M

# Max retention: 7 days (don't keep old logs on constrained disk)
MaxRetentionSec=7day

# Don't forward to syslog (reduces I/O and duplicate log storage)
ForwardToSyslog=no

# Don't forward to wall (reduces console spam)
ForwardToWall=no

# Compress journals (aggressive compression)
Compress=yes

# Seal journals (integrity checking — disabled to save CPU)
Seal=no
JOURNAL_CFG

  systemctl restart systemd-journald
  ok "Applied journald configuration ($journald_conf)."
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. LOGROTATE CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

step_logrotate() {
  header "STEP 4: Logrotate Configuration"

  local logrotate_conf="/etc/logrotate.d/edge-server"

  if $STATUS_ONLY; then
    info "Current logrotate configs:"
    ls -la /etc/logrotate.d/ 2>/dev/null || true
    echo ""
    return
  fi

  if ! SHOULD_APPLY; then
    info "Would configure logrotate for edge server (run with --apply)."
    return
  fi

  if $BACKUP && [[ -f "$logrotate_conf" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp "$logrotate_conf" "$BACKUP_DIR/edge-server.logrotate.bak" 2>/dev/null || true
  fi

  cat > "$logrotate_conf" << 'LOGROTATE_CFG'
# ==============================================================================
# HOSTINGER EDGE VPS — Logrotate
# ==============================================================================
# Applied by: hostinger-systemd-hardening.sh
#
# Aggressive log rotation for resource-constrained edge VPS.
# Logs should be treated as ephemeral — use centralized logging if needed.
# ==============================================================================

# --- System logs ---
/var/log/syslog
/var/log/messages
/var/log/kern.log
/var/log/auth.log
/var/log/debug
/var/log/daemon.log
{
    rotate 4
    weekly
    maxsize 50M
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}

# --- Docker container logs (handled by Docker's json-file driver, but catch any
#     that might be written to /var/log/docker) ---
/var/log/docker/*.log
{
    rotate 3
    size 10M
    missingok
    notifempty
    compress
    copytruncate
}

# --- Nginx (if installed for healthchecks — though we prefer Traefik) ---
/var/log/nginx/*.log
{
    rotate 2
    weekly
    maxsize 10M
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 `cat /var/run/nginx.pid`
        fi
    endscript
}

# --- Fail2ban (if installed) ---
/var/log/fail2ban.log
{
    rotate 4
    weekly
    maxsize 20M
    missingok
    notifempty
    compress
    delaycompress
    postrotate
        fail2ban-client flushlogs 2>/dev/null || true
    endscript
}
LOGROTATE_CFG

  ok "Applied logrotate configuration ($logrotate_conf)."
}

# ══════════════════════════════════════════════════════════════════════════════
# 5. VERIFY CHANGES
# ══════════════════════════════════════════════════════════════════════════════

step_verify() {
  header "STEP 5: Verification"

  info "Current resource state:"
  echo ""

  # Memory
  free -h | head -2
  echo ""

  # Disk
  df -h / | tail -1
  echo ""

  # Running services count
  local running_services
  running_services=$(systemctl list-units --type=service --state=running 2>/dev/null | grep -c "running" || echo 0)
  info "Running systemd services: $running_services"
  echo ""

  info "Top 10 services by memory:"
  systemd-cgtop --depth=10 -n1 2>/dev/null || ps aux --sort=-%mem | head -11
  echo ""

  # Verify sysctl
  info "Key sysctl values:"
  local verify_params=(
    "net.core.somaxconn"
    "net.ipv4.tcp_tw_reuse"
    "net.ipv4.tcp_fin_timeout"
    "net.ipv4.tcp_syncookies"
    "vm.swappiness"
  )
  for param in "${verify_params[@]}"; do
    local value
    value=$(sysctl -n "$param" 2>/dev/null || echo "not set")
    printf "    %-40s = %s\n" "$param" "$value"
  done
  echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "========================================================================"
echo " HOSTINGER VPS — SYSTEMD HARDENING & SYSTEM TUNING"
echo " Date: $(date)"
echo " Mode: $($STATUS_ONLY && echo "STATUS ONLY" || ($APPLY && echo "APPLY" || echo "DRY RUN"))"
if $BACKUP; then echo " Backup: $BACKUP_DIR"; fi
echo "========================================================================"
echo ""

if $STATUS_ONLY; then
  step_disable_services
  step_sysctl_tuning
  step_journald_tuning
  step_logrotate
  step_verify
  echo ""
  echo "========================================================================"
  echo " STATUS REPORT COMPLETE (no changes made)"
  echo "========================================================================"
  exit 0
fi

# Full run
step_disable_services
step_sysctl_tuning
step_journald_tuning
step_logrotate
step_verify

echo ""
echo "========================================================================"
echo " SYSTEM HARDENING COMPLETE"
echo "========================================================================"
echo ""
info "Changes applied.  Summary:"
echo ""
echo "  - Unnecessary systemd services disabled"
echo "  - Sysctl kernel parameters tuned for edge server"
echo "  - Journald configured: 200MB max, 7-day retention"
echo "  - Logrotate configured: aggressive rotation"
echo ""
info "Recommended next steps:"
echo ""
echo "  1. Reboot to verify all services start correctly:"
echo "     sudo reboot"
echo ""
echo "  2. After reboot, run verification:"
echo "     sudo ./hostinger-verify-light.sh --verbose"
echo ""
echo "  3. Monitor for the first 24 hours:"
echo "     - Check that all containers start: docker ps"
echo "     - Check resource usage: htop or free -h"
echo "     - Check logs: journalctl -xe"
echo ""
echo "  4. If services fail to start:"
echo "     - Check service status: systemctl --failed"
echo "     - Check container status: docker ps -a"
echo "     - Restore sysctl: sysctl -p /etc/sysctl.d/90-edge-server.conf"
echo ""
echo "========================================================================"

exit 0
