#!/usr/bin/env bash
# ============================================
# audit-docker.sh — Docker audit across servers
# ============================================
set -euo pipefail

REPORT_DIR="$HOME/WheelerCommandCenter/reports/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/audit-docker.txt"

{
  echo "=== Wheeler Docker Audit ==="
  echo "Date: $(date)"
  echo ""

  # Local Docker
  echo "--- Docker: local ---"
  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    echo "[OK] Docker running"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null
    echo ""
    docker system df 2>/dev/null
    echo ""
    UNHEALTHY=$(docker ps --filter "health=unhealthy" -q 2>/dev/null | wc -l)
    if [ "$UNHEALTHY" -gt 0 ]; then
      echo "[FAIL] $UNHEALTHY unhealthy containers:"
      docker ps --filter "health=unhealthy" --format "  {{.Names}} {{.Status}}" 2>/dev/null
    fi
  else
    echo "[WARN] Docker not available locally"
  fi
  echo ""

  # Remote servers
  for server in hostinger hetzner coredb; do
    echo "--- Docker: $server ---"
    if ssh -G "$server" &>/dev/null 2>&1; then
      if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" "docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null; then
        echo "[OK] Docker check successful"
      else
        echo "[WARN] Cannot connect or Docker not running"
      fi
    else
      echo "[WARN] SSH alias not configured"
    fi
    echo ""
  done

  echo "=== Audit Complete ==="
} > "$REPORT" 2>&1

echo "Report saved: $REPORT"
cat "$REPORT"
