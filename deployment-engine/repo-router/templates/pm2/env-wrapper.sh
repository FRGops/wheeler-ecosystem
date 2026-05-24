#!/usr/bin/env bash
# =============================================================================
# Repo Router - PM2 Env Wrapper Template
# Source: templates/pm2/env-wrapper.sh
# Description: Shell wrapper that loads .env before starting PM2 app, with
#              error handling and credential verification.
# =============================================================================

set -euo pipefail

APP_NAME="${1:-}"
ENV_FILE="${2:-.env}"
STARTUP_TIMEOUT=30

if [[ -z "$APP_NAME" ]]; then
  echo "[ENV_WRAPPER] ERROR: No app name provided. Usage: $0 <app-name> [env-file]"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ENV_WRAPPER] WARNING: Env file '$ENV_FILE' not found for app '$APP_NAME'. Proceeding with existing environment."
else
  echo "[ENV_WRAPPER] Loading environment from '$ENV_FILE' for app '$APP_NAME'..."
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# Validate critical variables based on service type
if [[ "$APP_NAME" == *"surplusai"* ]] || [[ "$APP_NAME" == *"private-ai"* ]]; then
  if [[ -z "${SECRET_KEY:-}" ]]; then
    echo "[ENV_WRAPPER] ERROR: SECRET_KEY must be set for '$APP_NAME'. Aborting."
    exit 2
  fi
fi

if [[ "$APP_NAME" == *"prediction-radar"* ]]; then
  if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
    echo "[ENV_WRAPPER] WARNING: DEEPSEEK_API_KEY is not set for '$APP_NAME'. Prediction features may fail."
  fi
fi

if [[ "$APP_NAME" == "frgcrm-api" ]]; then
  required_vars=("DB_HOST" "DB_USER" "DB_PASSWORD" "DB_NAME")
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      echo "[ENV_WRAPPER] ERROR: $var is required for frgcrm-api. Aborting."
      exit 3
    fi
  done
fi

# Export NODE_PATH if applicable
if command -v node &>/dev/null; then
  NODE_PATH=$(npm root -g 2>/dev/null || true)
  if [[ -n "$NODE_PATH" ]]; then
    export NODE_PATH
  fi
fi

export APP_STARTED_AT
APP_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[ENV_WRAPPER] Starting PM2 app '$APP_NAME'..."
echo "[ENV_WRAPPER] Timestamp: $APP_STARTED_AT"
echo "[ENV_WRAPPER] Node: $(hostname)"
echo "[ENV_WRAPPER] PWD: $(pwd)"

# Execute the PM2 start command
exec pm2 start "$@" --update-env

# =============================================================================
# Usage examples:
#
#   # Basic usage
#   ./env-wrapper.sh my-app /opt/app/current/.env --name my-app dist/server.js
#
#   # With ecosystem file
#   ./env-wrapper.sh surplusai-api /data/surplusai/.env \
#     --name surplusai-api ecosystem.config.js --only surplusai-api
#
#   # For Python apps
#   ./env-wrapper.sh prediction-radar /opt/prediction-radar/.env \
#     --name prediction-radar --interpreter python3 -- app/main.py
# =============================================================================
