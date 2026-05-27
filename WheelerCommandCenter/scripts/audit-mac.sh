#!/usr/bin/env bash
# ============================================
# audit-mac.sh — Mac system audit (safe, read-only)
# ============================================
set -euo pipefail

REPORT_DIR="$HOME/WheelerCommandCenter/reports/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/audit-mac.txt"

ok()  { echo "  [OK]    $1"; }
warn(){ echo "  [WARN]  $1"; }
fail(){ echo "  [FAIL]  $1"; }

{
  echo "=== Wheeler Mac Audit ==="
  echo "Date: $(date)"
  echo ""

  echo "--- System ---"
  uname -a
  echo "User: $(whoami)"
  echo "Shell: $SHELL"
  echo "Home: $HOME"
  echo "Terminal: ${TERM:-unknown}"
  echo ""

  echo "--- macOS Specific ---"
  sw_vers 2>/dev/null || echo "  (not macOS - Linux detected)"
  system_profiler SPSoftwareDataType 2>/dev/null | head -10 || true
  echo ""

  echo "--- Package Managers ---"
  command -v brew &>/dev/null && ok "Homebrew: $(brew --version 2>/dev/null | head -1)" || warn "Homebrew not found"
  command -v apt &>/dev/null && ok "apt: $(apt --version 2>/dev/null | head -1)" || warn "apt not found"
  echo ""

  echo "--- Core Tools ---"
  for cmd in git ssh docker tailscale gh claude node npm python3 curl; do
    command -v "$cmd" &>/dev/null && ok "$cmd: $(command -v "$cmd")" || warn "$cmd: not found"
  done
  echo ""

  echo "--- Node.js ---"
  node --version 2>/dev/null && npm --version 2>/dev/null && ok "Node.js OK" || warn "Node.js issue"
  echo ""

  echo "--- Python ---"
  python3 --version 2>/dev/null && ok "Python3 OK" || warn "Python3 issue"
  echo ""

  echo "--- Docker ---"
  if command -v docker &>/dev/null; then
    docker info --format '{{.ServerVersion}}' 2>/dev/null && ok "Docker daemon reachable" || warn "Docker daemon not reachable"
    docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || true
  fi
  echo ""

  echo "--- Disk ---"
  df -h / 2>/dev/null || df -h 2>/dev/null
  echo ""

  echo "--- Memory ---"
  free -h 2>/dev/null || vm_stat 2>/dev/null || true
  echo ""

  echo "--- Network (non-sensitive) ---"
  hostname -I 2>/dev/null | head -1 || hostname
  echo ""

  echo "--- SSH Config ---"
  if [ -f ~/.ssh/config ]; then
    grep -E '^Host ' ~/.ssh/config 2>/dev/null || echo "  (no Host entries)"
  else
    warn "No ~/.ssh/config"
  fi
  echo ""

  echo "--- Tailscale ---"
  command -v tailscale &>/dev/null && tailscale status 2>/dev/null | head -10 || warn "Tailscale not found"
  echo ""

  echo "=== Audit Complete ==="
} > "$REPORT" 2>&1

echo "Report saved: $REPORT"
head -30 "$REPORT"
