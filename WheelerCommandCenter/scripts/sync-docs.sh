#!/usr/bin/env bash
# ============================================
# sync-docs.sh — Sync docs to remote servers
# ============================================
set -euo pipefail

WHEELER_HOME="${WHEELER_HOME:-$HOME/WheelerCommandCenter}"
echo "Syncing Wheeler Command Center docs to servers..."

for server in hostinger hetzner coredb; do
  echo -n "  $server: "
  if ssh -G "$server" &>/dev/null 2>&1; then
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" "mkdir -p /root/WheelerCommandCenter/docs" 2>/dev/null; then
      scp -r "$WHEELER_HOME/docs"/* "$server:/root/WheelerCommandCenter/docs/" 2>/dev/null && echo "[OK]" || echo "[FAIL]"
    else
      echo "[WARN] Cannot connect"
    fi
  else
    echo "[WARN] SSH alias not configured"
  fi
done

echo "Sync complete."
