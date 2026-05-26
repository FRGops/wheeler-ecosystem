# DevOps Acceptance Rubric

## Score Ranges

| Score | Rating | Description |
|-------|--------|-------------|
| 90-100 | Production-Ready | Safe, reversible, monitored, documented |
| 75-89 | Good | Minor gaps in monitoring or rollback |
| 60-74 | Adequate | Works but missing safety nets |
| < 60 | Risky | Should not deploy |

## Dimensions

### Safety (30 points)
- Rollback plan exists and tested
- No single point of failure introduced
- Health check configured
- Resource limits set
- Graceful shutdown handled

### Observability (25 points)
- Health check endpoint exists
- Metrics exported (Prometheus or similar)
- Structured logging
- Alerts configured for failure modes
- Dashboard shows key metrics

### Security (20 points)
- No privileged mode (unless required)
- Minimal base image
- No secrets in image/layers
- Network policy appropriate
- Non-root user

### Automation (15 points)
- CI/CD pipeline defined
- Automated tests run before deploy
- Infrastructure as code
- Environment parity (dev/staging/prod)

### Documentation (10 points)
- Runbook for common issues
- Architecture diagram current
- Deploy procedure documented
- Rollback procedure documented

## Automatic Checks
- Container health check: pass
- Port binding: correct
- Resource limits: set
- Readiness probe: configured

## What Blocks 100/100
- No rollback plan
- No health check
- Running as root in container
- Secrets in image
- No resource limits
- Untested deploy procedure
