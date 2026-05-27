#!/usr/bin/env bash
# ============================================
# audit-servers.sh — Server connectivity audit
# ============================================
set -euo pipefail

REPORT_DIR="$HOME/WheelerCommandCenter/reports/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/audit-servers.txt"

ok()  { echo "  [OK]    $1"; }
warn(){ echo "  [WARN]  $1"; }
fail(){ echo "  [FAIL]  $1"; }

{
  echo "=== Wheeler Server Connectivity Audit ==="
  echo "Date: $(date)"
  echo ""

  for server in hostinger hetzner coredb; do
    echo "--- $server ---"
    if ssh -G "$server" &>/dev/null 2>&1; then
      HOSTNAME=$(ssh -G "$server" | grep '^hostname ' | awk '{print $2}')
      ok "SSH alias configured → $HOSTNAME"
      # Test connectivity safely
      if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" "hostname" 2>/dev/null; then
        ok "SSH connection successful"
        # Safe read-only checks
        ssh -o ConnectTimeout=5 "$server" "uptime" 2>/dev/null || true
        ssh -o ConnectTimeout=5 "$server" "df -h / | tail -1" 2>/dev/null || true
      else
        warn "SSH connection failed (key or network issue)"
      fi
    else
      warn "SSH alias not configured"
    fi
    echo ""
  done

  echo "=== Audit Complete ==="
} > "$REPORT" 2>&1

echo "Report saved: $REPORT"
cat "$REPORT"
