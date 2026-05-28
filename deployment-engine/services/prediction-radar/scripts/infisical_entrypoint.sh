#!/bin/bash
# Infisical Entrypoint Wrapper for Prediction Radar API
#
# Fetches secrets from Infisical at container boot, injects them as env vars,
# then launches the real application. Uses only Python stdlib (no curl/wget).
#
# Falls back to .env file behavior when INFISICAL_TOKEN is not set.
#
# Usage (in docker-compose):
#   entrypoint: /app/infisical_entrypoint.sh
#   command: /app/migrate.sh

set -e

INFISICAL_API_URL="${INFISICAL_API_URL:-http://100.118.166.117:8443}"

if [ -n "${INFISICAL_TOKEN}" ] && [ -n "${INFISICAL_PROJECT_ID}" ]; then
    echo "[infisical] Fetching secrets from Infisical (${INFISICAL_API_URL})..."

    # Fetch secrets via Python stdlib (no curl dependency).
    # stdout → export statements for bash to eval
    # stderr → status messages for the operator
    EXPORTS=$(python3 -c "
import json, sys, urllib.request, urllib.error

url = '${INFISICAL_API_URL}/api/v3/secrets/raw?workspaceId=${INFISICAL_PROJECT_ID}&environment=prod'
req = urllib.request.Request(url)
req.add_header('Authorization', 'Bearer ${INFISICAL_TOKEN}')

try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
    secrets = data.get('secrets', [])
    count = 0
    for s in secrets:
        key = s.get('secretKey') or s.get('key') or s.get('name')
        val = s.get('secretValue') or s.get('value') or s.get('plainText')
        if key and val:
            escaped = val.replace(\"'\", \"'\\\\''\")
            print(f\"export {key}='{escaped}'\")
            count += 1
    print(f'  [infisical] Loaded {count} secrets from Infisical', file=sys.stderr)
except Exception as e:
    print(f'echo \"[infisical] ERROR: {e}\"', file=sys.stderr)
")

    # Eval the export statements into current shell
    if [ -n "$EXPORTS" ]; then
        eval "$EXPORTS"
    fi

else
    echo "[infisical] INFISICAL_TOKEN not set — using env_file/.env fallback"
fi

# Launch the real application with all args passed through
exec "$@"
