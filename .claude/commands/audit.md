# /audit — Full Ecosystem Audit

Run a comprehensive audit across all Wheeler ecosystem components. Executes all checks in parallel and produces a health report card.

## Execution (ALL in parallel)

```bash
# 1. Docker audit
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null

# 2. PM2 audit
pm2 list 2>/dev/null

# 3. Disk usage
df -h / /opt /var/lib/docker 2>/dev/null

# 4. Memory
free -h 2>/dev/null

# 5. Network ports (flag 0.0.0.0 bindings)
ss -tulpn 2>/dev/null | grep -E '0\.0\.0\.0|:::'

# 6. Firewall status
ufw status verbose 2>/dev/null

# 7. Tailscale mesh
tailscale status 2>/dev/null

# 8. System load
uptime && cat /proc/loadavg

# 9. Secrets scan (quick)
bash /opt/wheeler-ecosystem/security/secret-scan.sh 2>/dev/null || echo "No secrets scanner found"

# 10. Capability inventory
find /root/.claude/skills -name "SKILL.md" 2>/dev/null | wc -l
find /root/.claude/commands -name "*.md" 2>/dev/null | wc -l
find /root/.claude/agents -name "*.md" 2>/dev/null | wc -l

# 11. Systemd failed units
systemctl --failed 2>/dev/null

# 12. Docker healthcheck summary
docker ps --format '{{.Names}}: {{.Status}}' 2>/dev/null | grep -v 'healthy\|Up'
```

## Output Format

```
╔══════════════════════════════════════════════╗
║   Wheeler Ecosystem Audit — <timestamp>      ║
║   Node: <hostname> (<role>)                  ║
╚══════════════════════════════════════════════╝

SERVICES
  Docker:  <N> running, <N> healthy, <N> unhealthy
  PM2:     <N> online, <N> stopped, <N> errored

RESOURCES
  CPU:     <load> (<cores> cores)
  Memory:  <used> / <total> (<available> available)
  Disk:    <used> / <total> (<pct>%)

SECURITY
  [PASS/FAIL] No 0.0.0.0 port bindings (except approved)
  [PASS/FAIL] UFW active and configured
  [PASS/FAIL] Tailscale mesh healthy
  [PASS/FAIL] Secrets scan clean
  [PASS/FAIL] No failed systemd units

CAPABILITIES
  Skills:   <count>
  Commands: <count>
  Agents:   <count>
  MCP:      <count> configured

──────────────────────────────────────────────
OVERALL: [HEALTHY / DEGRADED / CRITICAL]
ISSUES: <count> requiring attention
```
