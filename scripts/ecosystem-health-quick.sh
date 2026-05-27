#!/usr/bin/env bash
#===============================================================================
# WHEELER ECOSYSTEM -- Daily CEO Health Check
#   One command. One glance. Everything OK?
#   Usage: ./ecosystem-health-quick.sh [--json]
#   Runtime target: <30 seconds
#===============================================================================
set -o pipefail

MODE="${1:-text}"
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS_LABEL="${GREEN}PASS${NC}"
FAIL_LABEL="${RED}FAIL${NC}"
WARN_LABEL="${YELLOW}WARN${NC}"

pass() { echo -e "  [$PASS_LABEL] $1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "  [$FAIL_LABEL] $1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
warn() { echo -e "  [$WARN_LABEL] $1"; WARN_COUNT=$((WARN_COUNT+1)); }

redact() { sed -E 's/([Bb]earer\s+|api[_-]?key["=: ]*|token["=: ]*|secret["=: ]*|password["=: ]*|Authorization["=: ]*)[a-zA-Z0-9_\.\-]{8,}/\1***REDACTED***/g'; }

START_TS=$(date +%s)

echo ""
echo -e "${BOLD}WHEELER ECOSYSTEM HEALTH -- $(date -u)${NC}"
echo -e "${BOLD}$(printf '=%.0s' {1..65})${NC}"
echo ""

# --- 1. TAILSCALE ---
echo -e "${BOLD}[1] TAILSCALE TUNNEL${NC}"
if command -v tailscale &>/dev/null; then
  TS_OUT=$(tailscale status 2>&1 | redact)
  TS_LINES=$(echo "$TS_OUT" | grep -c . 2>/dev/null || echo 0)
  TS_OFFLINE=$(echo "$TS_OUT" | grep -c 'offline' 2>/dev/null || true)
  if [ "$TS_LINES" -gt 0 ]; then
    echo "  Nodes: $TS_LINES"
    if [ "$TS_OFFLINE" -gt 0 ]; then
      fail "Tailscale: $TS_OFFLINE node(s) offline"
      echo "  $TS_OUT" | head -10
    else
      pass "Tailscale: $TS_LINES node(s) all online"
    fi
  else
    warn "Tailscale: no output from status"
  fi
else
  fail "Tailscale: command not found"
fi
echo ""

# --- 2. REVENUE: fundsrecoverygroup.com ---
echo -e "${BOLD}[2] REVENUE: fundsrecoverygroup.com${NC}"
HTTP_CODE=$(curl -sIk --max-time 10 https://fundsrecoverygroup.com 2>/dev/null | head -1 | redact)
HTTP_NUM=$(echo "$HTTP_CODE" | grep -oE '[0-9]{3}' | head -1)
if [ -n "$HTTP_NUM" ] && [ "$HTTP_NUM" -ge 200 ] && [ "$HTTP_NUM" -lt 400 ]; then
  pass "fundsrecoverygroup.com $HTTP_CODE"
elif [ -n "$HTTP_NUM" ]; then
  fail "fundsrecoverygroup.com $HTTP_CODE"
else
  fail "fundsrecoverygroup.com -- no response (timeout or unreachable)"
fi
echo ""

# --- 3. REVENUE: predictionradar.app ---
echo -e "${BOLD}[3] REVENUE: predictionradar.app${NC}"
HTTP_CODE2=$(curl -sIk --max-time 10 https://predictionradar.app 2>/dev/null | head -1 | redact)
HTTP_NUM2=$(echo "$HTTP_CODE2" | grep -oE '[0-9]{3}' | head -1)
if [ -n "$HTTP_NUM2" ] && [ "$HTTP_NUM2" -ge 200 ] && [ "$HTTP_NUM2" -lt 400 ]; then
  pass "predictionradar.app $HTTP_CODE2"
elif [ -n "$HTTP_NUM2" ]; then
  fail "predictionradar.app $HTTP_CODE2"
else
  fail "predictionradar.app -- no response (timeout or unreachable)"
fi
echo ""

# --- 4. DOCKER unhealthy ---
echo -e "${BOLD}[4] DOCKER HEALTH${NC}"
UNHEALTHY=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" 2>/dev/null)
if [ -z "$UNHEALTHY" ]; then
  pass "Docker: 0 unhealthy containers"
else
  UNHEALTHY_COUNT=$(echo "$UNHEALTHY" | grep -c .)
  fail "Docker: $UNHEALTHY_COUNT unhealthy container(s)"
  echo "  $UNHEALTHY" | sed 's/^/    /'
fi
echo ""

# --- 5. DOCKER count ---
echo -e "${BOLD}[5] DOCKER: Container Count${NC}"
DOCKER_COUNT=$(docker ps -q 2>/dev/null | wc -l)
DOCKER_ALL=$(docker ps -a -q 2>/dev/null | wc -l)
echo "  Running: $DOCKER_COUNT / $DOCKER_ALL total"
pass "Docker running: $DOCKER_COUNT"
echo ""

# --- 6. PM2 ---
echo -e "${BOLD}[6] PM2 PROCESS SUMMARY${NC}"
PM2_LIST=$(pm2 jlist 2>/dev/null || echo "[]")
if [ "$PM2_LIST" != "[]" ] && [ -n "$PM2_LIST" ]; then
  PM2_SUMMARY=$(echo "$PM2_LIST" | python3 /root/scripts/pm2-summarize.py 2>/dev/null)
  if [ -z "$PM2_SUMMARY" ] || ! echo "$PM2_SUMMARY" | grep -qE '^[0-9]+\|[0-9]+\|'; then
    warn "PM2: could not parse process list"
    PM2_ONLINE_N=0; PM2_TOTAL_N=0; PM2_STOPPED=0; PM2_ERRORED=0; PM2_RESTARTS=0
  else
    IFS='|' read -r PM2_ONLINE_N PM2_TOTAL_N PM2_STOPPED PM2_ERRORED PM2_RESTARTS PM2_OLDEST <<< "$PM2_SUMMARY"
  fi
  echo "  Processes: ${PM2_ONLINE_N:-0} / ${PM2_TOTAL_N:-0} online  |  Stopped: ${PM2_STOPPED:-0}  |  Errored: ${PM2_ERRORED:-0}  |  Total restarts: ${PM2_RESTARTS:-0}"
  if [ "${PM2_ERRORED:-0}" -gt 0 ] || [ "${PM2_STOPPED:-0}" -gt 0 ]; then
    fail "PM2: ${PM2_ERRORED:-0} errored + ${PM2_STOPPED:-0} stopped processes"
    echo "$PM2_LIST" | python3 -c "
import json, sys
procs = json.load(sys.stdin)
bad = [p for p in procs if p.get('pm2_env', {}).get('status') in ('stopped', 'errored')]
for p in bad:
    name = p.get('name', '?')
    pid = p.get('pm2_env', {}).get('pid', '?')
    status = p.get('pm2_env', {}).get('status', '?')
    print(f'    {name} (pid={pid}, status={status})')
" 2>/dev/null
  elif [ "${PM2_TOTAL_N:-0}" -gt 0 ] && [ "${PM2_ONLINE_N:-0}" -lt "${PM2_TOTAL_N:-0}" ]; then
    warn "PM2: ${PM2_ONLINE_N:-0}/${PM2_TOTAL_N:-0} online -- some processes not running"
  else
    pass "PM2: ${PM2_ONLINE_N:-0}/${PM2_TOTAL_N:-0} online (0 errored, 0 stopped)"
  fi
else
  warn "PM2: no processes or jlist empty"
fi
echo ""

# --- 7. PROMETHEUS ---
echo -e "${BOLD}[7] MONITORING: Prometheus Alerts${NC}"
ALERTS_JSON=$(curl -s --max-time 5 http://127.0.0.1:9090/api/v1/alerts 2>/dev/null)
if [ -n "$ALERTS_JSON" ]; then
  FIRING_COUNT=$(echo "$ALERTS_JSON" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    alerts = data.get('data', {}).get('alerts', [])
    firing = [a for a in alerts if a.get('state') == 'firing']
    print(len(firing))
except Exception:
    print('err')
" 2>/dev/null)
  if [ "$FIRING_COUNT" = "err" ] || [ -z "$FIRING_COUNT" ]; then
    warn "Prometheus: could not parse alert response"
  elif [ "$FIRING_COUNT" -eq 0 ]; then
    pass "Prometheus: 0 firing alerts"
  elif [ "$FIRING_COUNT" -le 3 ]; then
    warn "Prometheus: $FIRING_COUNT firing alert(s)"
    echo "$ALERTS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data.get('data', {}).get('alerts', []):
    if a.get('state') == 'firing':
        lbls = a.get('labels', {})
        name = lbls.get('alertname', '?')
        sev = lbls.get('severity', '?')
        print(f'    {name} (severity={sev})')
" 2>/dev/null
  else
    fail "Prometheus: $FIRING_COUNT firing alerts"
    echo "$ALERTS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data.get('data', {}).get('alerts', []):
    if a.get('state') == 'firing':
        lbls = a.get('labels', {})
        name = lbls.get('alertname', '?')
        sev = lbls.get('severity', '?')
        print(f'    {name} (severity={sev})')
" 2>/dev/null
  fi
else
  warn "Prometheus: unreachable at 127.0.0.1:9090"
fi
echo ""

# --- 8. DISK ---
echo -e "${BOLD}[8] SYSTEM: Disk Usage${NC}"
DISK_LINE=$(df -h / 2>/dev/null | tail -1)
if [ -n "$DISK_LINE" ]; then
  DISK_PCT=$(echo "$DISK_LINE" | awk '{print $5}' | tr -d '%')
  echo "  $DISK_LINE"
  if [ "$DISK_PCT" -lt 70 ]; then
    pass "Disk: ${DISK_PCT}% used"
  elif [ "$DISK_PCT" -lt 90 ]; then
    warn "Disk: ${DISK_PCT}% used"
  else
    fail "Disk: ${DISK_PCT}% used -- near capacity"
  fi
else
  fail "Disk: could not get usage"
fi
echo ""

# --- 9. MEMORY ---
echo -e "${BOLD}[9] SYSTEM: Memory${NC}"
MEM_LINE=$(free -h 2>/dev/null | grep Mem)
if [ -n "$MEM_LINE" ]; then
  MEM_PCT=$(echo "$MEM_LINE" | awk '{printf "%.0f", $3/$2 * 100}')
  echo "  $MEM_LINE"
  if [ "$MEM_PCT" -lt 70 ]; then
    pass "Memory: ${MEM_PCT}% used"
  elif [ "$MEM_PCT" -lt 90 ]; then
    warn "Memory: ${MEM_PCT}% used"
  else
    fail "Memory: ${MEM_PCT}% used -- high usage"
  fi
else
  warn "Memory: could not get usage"
fi
echo ""

# --- 10. LOAD ---
echo -e "${BOLD}[10] SYSTEM: Load Average${NC}"
UPTIME_OUT=$(uptime)
if [ -n "$UPTIME_OUT" ]; then
  LOAD_1=$(echo "$UPTIME_OUT" | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
  CPU_CORES=$(nproc 2>/dev/null || echo 1)
  LOAD_THRESH_HIGH=$(echo "$CPU_CORES * 2" | bc 2>/dev/null || echo 100)
  LOAD_THRESH_WARN=$(echo "$CPU_CORES * 0.8" | bc 2>/dev/null || echo 4)
  echo "  $UPTIME_OUT"
  echo "  Cores: $CPU_CORES  |  Load thresholds: warn>${LOAD_THRESH_WARN}, fail>${LOAD_THRESH_HIGH}"
  USE_BC=$(echo "$LOAD_1 < $LOAD_THRESH_WARN" | bc -l 2>/dev/null || echo 1)
  if [ "$USE_BC" -eq 1 ]; then
    pass "Load: $LOAD_1 (1m) within range"
  else
    USE_BC2=$(echo "$LOAD_1 < $LOAD_THRESH_HIGH" | bc -l 2>/dev/null || echo 1)
    if [ "$USE_BC2" -eq 1 ]; then
      warn "Load: $LOAD_1 (1m) elevated"
    else
      fail "Load: $LOAD_1 (1m) critically high"
    fi
  fi
else
  warn "Load: uptime command failed"
fi
echo ""

# --- 11. COREDB ---
echo -e "${BOLD}[11] COREDB (100.118.166.117)${NC}"
COREDB_OUT=$(ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no root@100.118.166.117 'docker ps -q 2>/dev/null | wc -l' 2>&1)
if [ -n "$COREDB_OUT" ] && echo "$COREDB_OUT" | grep -qE '^[0-9]+$'; then
  pass "COREDB: $(echo "$COREDB_OUT" | tr -d ' ') running container(s)"
elif echo "$COREDB_OUT" | grep -qiE "timeout|refused|unreachable|Permission denied"; then
  fail "COREDB: SSH connection failed"
else
  fail "COREDB: unexpected response -- $(echo "$COREDB_OUT" | redact | head -1)"
fi
echo ""

# --- SUMMARY ---
END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))

echo -e "${BOLD}$(printf '=%.0s' {1..65})${NC}"
echo -e "${BOLD}HEALTH SUMMARY${NC}"
echo -e "  ${GREEN}PASS${NC}: $PASS_COUNT   ${RED}FAIL${NC}: $FAIL_COUNT   ${YELLOW}WARN${NC}: $WARN_COUNT"
TOTAL_CHECKS=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
if [ "$TOTAL_CHECKS" -gt 0 ]; then
  SCORE=$(( PASS_COUNT * 100 / TOTAL_CHECKS ))
else
  SCORE=0
fi
echo -e "  Score: ${BOLD}${SCORE}${NC}% ($PASS_COUNT/$TOTAL_CHECKS checks passing)"
echo -e "  Duration: ${DURATION}s"

if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
  echo -e "  Verdict: ${GREEN}ALL CLEAN${NC}"
elif [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -gt 0 ]; then
  echo -e "  Verdict: ${YELLOW}DEGRADED${NC} -- $WARN_COUNT warning(s) need attention"
elif [ "$FAIL_COUNT" -le 2 ]; then
  echo -e "  Verdict: ${YELLOW}ATTENTION REQUIRED${NC} -- $FAIL_COUNT failure(s), $WARN_COUNT warning(s)"
else
  echo -e "  Verdict: ${RED}CRITICAL${NC} -- $FAIL_COUNT failure(s), immediate action needed"
fi

echo ""
echo -e "${BOLD}Note:${NC} All tokens, keys, and secrets have been redacted from output."
echo -e "${BOLD}$(printf '=%.0s' {1..65})${NC}"
echo ""

if [ "$MODE" = "--json" ]; then
  STATUS="healthy"
  [ "$FAIL_COUNT" -gt 0 ] && STATUS="critical"
  [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -gt 0 ] && STATUS="degraded"
  printf '{"timestamp":"%s","status":"%s","score":%d,"passed":%d,"warnings":%d,"failures":%d,"duration_seconds":%d}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$STATUS" "$SCORE" "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT" "$DURATION"
fi

exit $(( FAIL_COUNT > 0 ? 1 : 0 ))
