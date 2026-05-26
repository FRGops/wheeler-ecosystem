#!/usr/bin/env bash
# PostToolUse Hook — Real-time GitHub repo detection
# Detects github.com URLs from WebFetch/WebSearch calls and drops them
# into the repo-listener drop zone for automatic 14-phase ingestion.
# Safe: only processes public GitHub URLs, never logs secrets.

TOOL_NAME="$1"
DROP_ZONE="/root/.ai/repo-drop-zone.txt"
REPO_PATTERN='https://github\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+'

# Only process WebFetch and WebSearch tools — they're the ones that hit GitHub
if [[ "$TOOL_NAME" != "WebFetch" && "$TOOL_NAME" != "WebSearch" ]]; then
  exit 0
fi

# Read stdin JSON (Claude Code passes tool input/output via stdin)
INPUT=$(cat)

# Extract github.com URLs from the tool input
URLS=$(echo "$INPUT" | grep -oP "$REPO_PATTERN" | sort -u)

if [[ -z "$URLS" ]]; then
  exit 0
fi

# Ensure drop zone exists
mkdir -p "$(dirname "$DROP_ZONE")"
touch "$DROP_ZONE"

# Append new URLs to drop zone (listener deduplicates)
while IFS= read -r url; do
  # Normalize: strip trailing slash, .git suffix
  url=$(echo "$url" | sed 's/\.git$//' | sed 's/\/$//')
  echo "$url" >> "$DROP_ZONE"
done <<< "$URLS"

exit 0
