#!/usr/bin/env bash
# ============================================
# audit-repos.sh — Repository health audit
# ============================================
set -euo pipefail

WHEELER_HOME="${WHEELER_HOME:-$HOME/WheelerCommandCenter}"
REPORT_DIR="$WHEELER_HOME/reports/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/audit-repos.txt"

{
  echo "=== Wheeler Repository Audit ==="
  echo "Date: $(date)"
  echo ""

  # Scan known locations
  REPO_ROOTS=("$HOME" "$HOME/deployment-engine" "/opt")
  for root in "${REPO_ROOTS[@]}"; do
    if [ -d "$root" ]; then
      find "$root" -maxdepth 3 -name ".git" -type d 2>/dev/null | while read gitdir; do
        repodir=$(dirname "$gitdir")
        echo "--- $(basename "$repodir") ---"
        echo "  Path: $repodir"
        cd "$repodir"
        echo "  Branch: $(git branch --show-current 2>/dev/null || echo '?')"
        echo "  Remote: $(git remote get-url origin 2>/dev/null || echo '?')"
        DIRTY=$(git status --porcelain 2>/dev/null | wc -l)
        if [ "$DIRTY" -eq 0 ]; then
          echo "  Status: [OK] clean"
        else
          echo "  Status: [WARN] $DIRTY uncommitted files"
        fi
        echo "  Last commit: $(git log -1 --format='%ci %s' 2>/dev/null || echo '?')"
        echo ""
      done
    fi
  done

  echo "=== Audit Complete ==="
} > "$REPORT" 2>&1

echo "Report saved: $REPORT"
cat "$REPORT"
