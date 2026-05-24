---
name: docker-health
description: "Comprehensive Docker health audit: container status, resource usage, port binding safety, restart policies, healthcheck validation, image freshness, disk usage."
trigger: docker health, docker audit, container health, docker check, check containers, container audit
---

# Skill: Docker Health

Comprehensive Docker health audit with security-focused port binding analysis. Flags all 0.0.0.0 bindings as HIGH risk unless explicitly approved.

## Critical Checks

### Port Binding Safety (HIGHEST PRIORITY)
Every 0.0.0.0 binding must be justified:
```bash
docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E '0\.0\.0\.0:[0-9]+'
```

### Healthcheck Status
Containers without healthchecks in production are a MEDIUM risk:
```bash
docker inspect $(docker ps -q) --format '{{.Name}}: {{.State.Health.Status}}' 2>/dev/null
```

### Restart Policies
Containers without restart policies will not recover from crashes:
```bash
docker inspect $(docker ps -aq) --format '{{.Name}}: {{.HostConfig.RestartPolicy.Name}}' 2>/dev/null
```

## Execution (ALL in parallel)

```bash
# Full parallel audit
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
docker system df
docker network ls
```

## Risk Classification

| Finding | Risk | Action |
|---------|------|--------|
| 0.0.0.0 binding on DB port | CRITICAL | Bind to 127.0.0.1 immediately |
| No healthcheck | MEDIUM | Add healthcheck |
| No restart policy | MEDIUM | Add unless-stopped |
| Privileged container | CRITICAL | Remove --privileged or justify |
| Host network mode | HIGH | Use bridge network |
| Root user in container | MEDIUM | Use non-root USER |

## Output Format

```
DOCKER HEALTH: <hostname>
──────────────────────────────────────
CONTAINERS: <N> total, <N> running, <N> healthy

PORT BINDINGS:
  [PASS/FAIL] 127.0.0.1 bindings: <N>
  [WARN/CRIT] 0.0.0.0 bindings: <N>
    <list flagged bindings>

HEALTH:
  healthy: <N>, unhealthy: <N>, none: <N>

RESTART POLICIES:
  unless-stopped: <N>, always: <N>, no: <N>

RESOURCES:
  Images: <N> (<size>), Volumes: <N> (<size>)

OVERALL: [HEALTHY / NEEDS ATTENTION / CRITICAL]
```
