#!/bin/bash
# Wheeler Legal/Compliance OS — Health API Endpoint
# Serves compliance-health.json as HTTP JSON on port 8199
# Lightweight health endpoint for dashboard consumption (Grafana, Prometheus, Executive Dashboard :8180)
#
# Usage: bash /root/scripts/compliance-api.sh [start|stop|status]
# The aggregator script MUST be run before this to populate scores:
#   bash /root/scripts/compliance-health-aggregator.sh

set -euo pipefail

PORT="${COMPLIANCE_API_PORT:-8199}"
PID_FILE="/tmp/compliance-api.pid"
HEALTH_FILE="/root/scripts/aiops-watchdog/compliance-health.json"

status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "[compliance-api] RUNNING (pid=$pid, port=$PORT)"
            return 0
        fi
    fi
    echo "[compliance-api] NOT RUNNING"
    return 1
}

stop() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            rm -f "$PID_FILE"
            echo "[compliance-api] Stopped (pid=$pid)"
            return 0
        fi
        rm -f "$PID_FILE"
    fi
    echo "[compliance-api] Not running"
}

start() {
    if status &>/dev/null; then
        echo "[compliance-api] Already running"
        return 0
    fi

    # Ensure health file exists
    if [[ ! -f "$HEALTH_FILE" ]]; then
        echo "[compliance-api] Health file missing — running aggregator..."
        bash /root/scripts/compliance-health-aggregator.sh
    fi

    echo "[compliance-api] Starting on port $PORT..."

    # Simple nc-based HTTP server
    while true; do
        if [[ -f "$HEALTH_FILE" ]]; then
            BODY=$(cat "$HEALTH_FILE")
            LENGTH=$(echo -n "$BODY" | wc -c)
        else
            BODY='{"error":"health file not found","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}'
            LENGTH=$(echo -n "$BODY" | wc -c)
        fi

        RESPONSE="HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: $LENGTH\r\nConnection: close\r\n\r\n$BODY"

        echo -ne "$RESPONSE" | nc -l -p "$PORT" -w 1 2>/dev/null || true
    done &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    sleep 0.5

    if kill -0 "$pid" 2>/dev/null; then
        echo "[compliance-api] Started (pid=$pid, port=$PORT)"
        echo "[compliance-api] Health endpoint: http://localhost:$PORT/health"
    else
        echo "[compliance-api] Failed to start"
        rm -f "$PID_FILE"
        return 1
    fi
}

case "${1:-status}" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 1; start ;;
    status) status ;;
    *) echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
