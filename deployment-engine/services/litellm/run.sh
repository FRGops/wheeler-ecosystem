#!/bin/bash
if [ -f /opt/apps/litellm/.env ]; then
  set -a
  source /opt/apps/litellm/.env
  set +a
fi
exec litellm --config /root/.claude/litellm-deepseek.yaml --port 4049 --host 127.0.0.1
