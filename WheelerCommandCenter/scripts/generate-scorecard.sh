#!/usr/bin/env bash
# ============================================
# generate-scorecard.sh — Manual scorecard generation
# ============================================
set -euo pipefail

WHEELER_HOME="${WHEELER_HOME:-$HOME/WheelerCommandCenter}"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
REPORT="$WHEELER_HOME/reports/readiness-scorecard-$TIMESTAMP.md"

echo "Generating readiness scorecard..."
"$WHEELER_HOME/bin/wheeler-scorecard"

# Also run the main scorecard to populate
echo "Scorecard saved to $WHEELER_HOME/scorecards/"
ls -t "$WHEELER_HOME/scorecards/" | head -3
