#!/usr/bin/env bash
# =============================================================================
# Repo Listener — Real-time GitHub repo ingestion for Wheeler Repo Intelligence
# =============================================================================
# Watches for new GitHub URLs and feeds them through the full 14-phase
# repo-router pipeline automatically. Bridges Claude Code sessions to the
# repo intelligence engine in real time.
#
# Modes:
#   --daemon    : Watch drop zone + session dirs continuously (PM2 mode)
#   --once      : Process drop zone + scan sessions, then exit
#   --intake    : Manual intake of specific URLs (args passed through)
#
# Drop zone:  .ai/repo-drop-zone.txt (written by PostToolUse hook)
# Sessions:   .ai/reports/sessions/
# State:      /root/deployment-engine/repo-router/config/router-state.json
# =============================================================================

set -euo pipefail

REPO_ROUTER="/root/deployment-engine/repo-router/orchestrator/repo-router.sh"
DROP_ZONE="/root/.ai/repo-drop-zone.txt"
SESSION_DIR="/root/.ai/reports/sessions"
STATE_FILE="/root/deployment-engine/repo-router/config/router-state.json"
PROCESSED_FILE="/root/.ai/repo-processed.txt"
LOG_FILE="/var/log/repo-router/listener.log"
REPO_PATTERN='https://github\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+'
POLL_INTERVAL="${REPO_LISTENER_INTERVAL:-5}"

# Ensure paths exist
mkdir -p "$(dirname "$DROP_ZONE")" "$SESSION_DIR" "$(dirname "$LOG_FILE")" "$(dirname "$PROCESSED_FILE")"
touch "$DROP_ZONE" "$PROCESSED_FILE" "$LOG_FILE"

log_msg() {
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "[$ts] $*" | tee -a "$LOG_FILE"
}

# Normalize a GitHub URL (strip .git, trailing slash, whitespace)
normalize_url() {
  echo "$1" | sed 's/\.git$//' | sed 's/\/$//' | xargs
}

# Check if a URL has already been processed
is_processed() {
  local url="$1"
  grep -qFx "$url" "$PROCESSED_FILE" 2>/dev/null
}

# Check if a repo is already registered in router state
is_registered() {
  local url="$1"
  local repo_name
  repo_name=$(echo "$url" | grep -oP '[^/]+/[^/]+$')

  if [[ -f "$STATE_FILE" ]]; then
    jq -e --arg name "$repo_name" '.repo_profiles[$name]' "$STATE_FILE" &>/dev/null && return 0
    jq -e --arg name "$repo_name" '.registered_repos[] | select(. == $name)' "$STATE_FILE" &>/dev/null && return 0
  fi
  return 1
}

# Mark a URL as processed
mark_processed() {
  local url="$1"
  echo "$url" >> "$PROCESSED_FILE"
}

# Ingest a single repo through the full 14-phase pipeline
ingest_repo() {
  local url="$1"
  local repo_name
  repo_name=$(echo "$url" | grep -oP '[^/]+/[^/]+$')

  log_msg "INGEST ▶ ${url} (${repo_name})"

  if is_processed "$url"; then
    log_msg "SKIP   ${repo_name}: already processed in this listener session"
    return 0
  fi

  if is_registered "$url"; then
    log_msg "SKIP   ${repo_name}: already registered in router state"
    mark_processed "$url"
    return 0
  fi

  # Run full 14-phase deploy pipeline
  log_msg "DEPLOY ${repo_name}: Starting full 14-phase pipeline..."

  if "$REPO_ROUTER" deploy "$url" >> "$LOG_FILE" 2>&1; then
    log_msg "PASS   ${repo_name}: 14/14 phases complete — LIVE"
    mark_processed "$url"
    return 0
  else
    local exit_code=$?
    log_msg "FAIL   ${repo_name}: Pipeline exited with code ${exit_code} (check router-state.json for phase)"
    # Still mark as processed to avoid infinite retry loops; use status command to check
    mark_processed "$url"
    return 1
  fi
}

# Scan session JSON files for GitHub URLs
scan_sessions() {
  local found=0
  for session_file in "$SESSION_DIR"/*.json; do
    [[ -f "$session_file" ]] || continue
    [[ "$session_file" == *".current-session"* ]] && continue

    local urls
    urls=$(grep -oP "$REPO_PATTERN" "$session_file" 2>/dev/null | sort -u || true)

    for url in $urls; do
      url=$(normalize_url "$url")
      if ! is_processed "$url" && ! is_registered "$url"; then
        echo "$url" >> "$DROP_ZONE"
        found=$((found + 1))
      fi
    done
  done
  if [[ $found -gt 0 ]]; then
    log_msg "SCAN   Found ${found} new repo(s) in session files"
  fi
}

# Process all URLs in the drop zone
process_drop_zone() {
  local ingested=0
  local failed=0

  if [[ ! -s "$DROP_ZONE" ]]; then
    return 0
  fi

  # Read drop zone, deduplicate, process each
  local urls
  urls=$(sort -u "$DROP_ZONE")

  # Clear drop zone (atomic-ish: write to temp, then mv)
  : > "$DROP_ZONE"

  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    url=$(normalize_url "$url")

    if ingest_repo "$url"; then
      ingested=$((ingested + 1))
    else
      failed=$((failed + 1))
    fi

    # Small delay between ingestions to avoid resource contention
    sleep 1
  done <<< "$urls"

  if [[ $ingested -gt 0 || $failed -gt 0 ]]; then
    log_msg "CYCLE  Ingested: ${ingested} | Failed: ${failed}"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "${1:-}" in
  --once)
    log_msg "START  Repo Listener — single scan cycle"
    scan_sessions
    process_drop_zone
    log_msg "DONE   Single scan complete"
    ;;

  --intake)
    shift
    for url in "$@"; do
      url=$(normalize_url "$url")
      echo "$url" >> "$DROP_ZONE"
      log_msg "QUEUE  ${url} added to drop zone"
    done
    process_drop_zone
    ;;

  --daemon|*)
    log_msg "START  Repo Listener daemon — polling every ${POLL_INTERVAL}s"
    log_msg "WATCH  Drop zone: ${DROP_ZONE}"
    log_msg "WATCH  Sessions: ${SESSION_DIR}"

    # On startup, scan existing sessions
    scan_sessions

    while true; do
      process_drop_zone

      # Periodically scan sessions for any missed repos
      if [[ $((SECONDS % 60)) -lt $POLL_INTERVAL ]]; then
        scan_sessions
      fi

      sleep "$POLL_INTERVAL"
    done
    ;;
esac
