#!/usr/bin/env bash
# PostToolUse Hook — Real-time GitHub repo detection
# Detects github.com URLs from WebFetch/WebSearch calls and drops them
# into the repo-listener drop zone for automatic 14-phase ingestion.
# Safe: only processes public GitHub URLs, never logs secrets.

DROP_ZONE="/root/.ai/repo-drop-zone.txt"
REPO_PATTERN='https://github\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+'

# Read stdin JSON (Claude Code passes ALL tool data via stdin JSON)
INPUT=$(cat 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")

# Only process WebFetch and WebSearch tools
if [[ "$TOOL_NAME" != "WebFetch" && "$TOOL_NAME" != "WebSearch" ]]; then
  exit 0
fi

# Extract github.com URLs from the tool input JSON (robust against nested JSON)
URLS=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ti = data.get('tool_input', {})
# Concatenate all string values to search for URLs
text = ' '.join(str(v) for v in ti.values() if isinstance(v, str))
import re
urls = re.findall(r'https://github\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+', text)
for u in sorted(set(urls)):
    print(u)
" 2>/dev/null)

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
