# /daily-health — Daily Ecosystem Health Check

Quick daily health pulse across all Wheeler ecosystem components. Runs all checks in parallel and produces a one-page status.

## Execution (ALL in parallel)

```bash
# Quick health pulse — all checks run concurrently

# 1. Docker summary
echo "=== DOCKER ==="
docker ps --format '{{.Names}}: {{.Status}}' 2>/dev/null | grep -c "healthy"
docker ps --format '{{.Names}}: {{.Status}}' 2>/dev/null | grep -v "healthy" || echo "  All healthy"

# 2. PM2 summary
echo "=== PM2 ==="
pm2 list 2>/dev/null | grep -c "online"
pm2 list 2>/dev/null | grep -c "stopped\|errored"

# 3. Resources
echo "=== RESOURCES ==="
free -h | awk 'NR==2{print $3"/"$2" ("$7" available)"}'
df -h / | awk 'NR==2{print $3"/"$2" ("$5" used)"}'
uptime | awk '{print $NF}'  # load average

# 4. Network
echo "=== NETWORK ==="
tailscale status 2>/dev/null | grep -c "active"
ss -tulpn 2>/dev/null | grep -c '0.0.0.0'  # public ports count

# 5. Security quick scan
echo "=== SECURITY ==="
ufw status 2>/dev/null | head -1
bash /opt/wheeler-ecosystem/security/secret-scan.sh 2>/dev/null | grep -c "CRITICAL\|HIGH" || echo "  Clean"

# 6. Backups
echo "=== BACKUPS ==="
find /opt/wheeler-ecosystem/backups -mtime -1 -type f 2>/dev/null | wc -l
find /root/backups -mtime -1 -type f 2>/dev/null | wc -l

# 7. Recent errors
echo "=== RECENT ERRORS ==="
journalctl --since "24 hours ago" -p err --no-pager 2>/dev/null | wc -l
dmesg --level=err,warn 2>/dev/null | tail -5
```

## Output Format (One-Page Status)

```
╔══════════════════════════════════════════════╗
║   DAILY HEALTH — <date> <time>               ║
║   Node: <hostname>                           ║
╚══════════════════════════════════════════════╝

DOCKER:   [✓] <N> healthy, <N> issues
PM2:      [✓] <N> online, <N> stopped/errored
MEMORY:   [✓] <used>/<total> (<available> available)
DISK:     [✓] <used>/<total> (<pct>%)
LOAD:     [✓] <load> (<cores> cores)
TAILSCALE:[✓] <N> peers active
FIREWALL: [✓] Active, <N> public ports
SECRETS:  [✓] Clean / [✗] <N> issues
BACKUPS:  [✓] <N> in last 24h / [✗] NONE!
ERRORS:   [✓] <N> in last 24h / [✗] <N> HIGH

──────────────────────────────────────────────
  [✓] [✓] [✓] [✓] [✓] [✓] [✓] [✓] [✓] [✓]
  ALL SYSTEMS NOMINAL
──────────────────────────────────────────────
```
