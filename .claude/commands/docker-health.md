# /docker-health — Docker Health Audit

Comprehensive Docker health check across all containers with security-focused port binding analysis.

## Execution (ALL in parallel)

```bash
# 1. All containers status
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null

# 2. Resource usage
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' 2>/dev/null

# 3. Port binding safety check (CRITICAL: flag all 0.0.0.0 bindings)
docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | while read line; do
  if echo "$line" | grep -qE '0\.0\.0\.0:[0-9]+'; then
    echo "[WARN] 0.0.0.0 binding: $line"
  fi
done

# 4. Restart policies
docker ps -a --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null
docker inspect $(docker ps -aq) --format '{{.Name}}: {{.HostConfig.RestartPolicy.Name}}' 2>/dev/null

# 5. Healthcheck status
docker ps --format '{{.Names}}: {{.Status}}' 2>/dev/null | grep -v healthy

# 6. Disk usage
docker system df 2>/dev/null

# 7. Network inspection
docker network ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}' 2>/dev/null

# 8. Image freshness
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}' 2>/dev/null | head -30
```

## Safety Flags

- **0.0.0.0 bindings**: Mark as HIGH risk unless explicitly approved
- **No healthcheck**: Mark as MEDIUM risk
- **No restart policy**: Mark as MEDIUM risk
- **Privileged containers**: Mark as CRITICAL risk
- **Host network mode**: Mark as HIGH risk

## Output Format

```
╔══════════════════════════════════════════════╗
║   Docker Health Audit — <timestamp>          ║
╚══════════════════════════════════════════════╝

CONTAINERS: <N> total, <N> running, <N> healthy
──────────────────────────────────────────────
PORT BINDING SAFETY:
  [PASS/FAIL] <N> 0.0.0.0 bindings found
  <list any flagged bindings with container name>

RESTART POLICIES:
  unless-stopped: <N>
  always: <N>
  no: <N> [WARN if production containers]

HEALTH:
  healthy:   <N>
  unhealthy: <N> [list names]
  none:      <N> [list names]

RESOURCES:
  Images:  <N>, <size>
  Volumes: <N>, <size>
  Containers: <size>

──────────────────────────────────────────────
OVERALL: [HEALTHY / NEEDS ATTENTION / CRITICAL]
```
