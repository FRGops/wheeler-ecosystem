#!/usr/bin/env bash
# ============================================
# audit-tailscale.sh — Tailscale mesh audit
# ============================================
set -euo pipefail

REPORT_DIR="$HOME/WheelerCommandCenter/reports/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/audit-tailscale.txt"

{
  echo "=== Wheeler Tailscale Mesh Audit ==="
  echo "Date: $(date)"
  echo ""

  if ! command -v tailscale &>/dev/null; then
    echo "  [FAIL] Tailscale not installed"
    echo "  Install: curl -fsSL https://tailscale.com/install.sh | sh"
    exit 0
  fi

  echo "--- Tailscale Status ---"
  tailscale status 2>/dev/null || echo "  [FAIL] tailscale status failed"
  echo ""

  echo "--- My Tailscale IP ---"
  tailscale ip -4 2>/dev/null || echo "  (could not determine)"
  echo ""

  echo "--- Connectivity Matrix ---"
  # Discover Tailscale IPs from config or TODO
  for server in hostinger hetzner coredb; do
    if ssh -G "$server" &>/dev/null 2>&1; then
      HOSTNAME=$(ssh -G "$server" | grep '^hostname ' | awk '{print $2}')
      echo "  Pinging $server ($HOSTNAME)..."
      if ping -c 2 -W 2 "$HOSTNAME" &>/dev/null 2>&1; then
        echo "    [OK] ICMP reachable"
      else
        echo "    [WARN] ICMP not reachable (may be blocked)"
      fi
      if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" "hostname" &>/dev/null 2>&1; then
        echo "    [OK] SSH reachable"
      else
        echo "    [WARN] SSH not reachable"
      fi
    else
      echo "  $server: [WARN] SSH alias not configured"
    fi
  done
  echo ""

  echo "=== Audit Complete ==="
} > "$REPORT" 2>&1

echo "Report saved: $REPORT"
cat "$REPORT"
