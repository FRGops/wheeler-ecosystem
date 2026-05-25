#!/bin/bash
if [ -f /opt/apps/wheeler-brain-api/.env ]; then
  set -a
  source /opt/apps/wheeler-brain-api/.env
  set +a
fi
exec python3 main.py
