# Wheeler A+ Remediation — Remaining Work

## Context
Wheeler ecosystem audit scored D+ (67/100). 12 false greens found. Major remediation completed (COREDB fixed, alertmanager deployed, gateway hardened, cron fixed, secrets rotated). 16/20 functional health checks passing. 4 minor issues remain to reach A+.

## Status: 16/20 health checks passing (80%)

### What's Already Fixed (Tasks #1-13)
- FG-1: frgcrm-api → COREDB PostgreSQL binds fixed, HTTP 200
- FG-2: Gateway bypass → All Docker binds on 127.0.0.1
- FG-3: Alertmanager → Deployed, Prometheus connected, alerts flowing
- FG-4: Discord bridge → Host-side forwarder, cron every 30s
- FG-5: UFW bypass → 0.0.0.0 binds eliminated
- FG-6: event-bus-relay → COREDB Redis fixed
- FG-7: loki → Container recreated (healthcheck needs docker-compose approach)
- FG-8: autoheal wall → Cron output to log files, Discord forwarder
- FG-9: superset secret → Rotated
- FG-10: lockdown watchdog → Rewritten for auto-discovery
- FG-11: prediction-radar memory → 1GiB→2GiB
- FG-12: ravyn-agent → Confirmed on 127.0.0.1

### Remaining Work

1. **Fix loki healthcheck** — `grafana/loki` doesn't support `--health-cmd` flag. Solution: Add loki to monitoring docker-compose.yml with proper HEALTHCHECK directive.

2. **Fix health check paths** — surplusai-api uses /docs (200), not /health (404). Accept litellm /health 401 and war-room / 200 as alive.

3. **Update final scorecard** — Re-run full audit with new scores.

4. **Pin remaining :latest images** — monitoring compose still uses :latest for prometheus, grafana.

### Verification
- Run `functional-healthcheck.sh` → expect 20/20
- Run `pm2 list` → all online
- Run `docker ps` → all healthy
- Run `ss -tlnp | grep '0.0.0.0'` → only SSH and system services
- Verify Discord receives alerts from forwarder cron
