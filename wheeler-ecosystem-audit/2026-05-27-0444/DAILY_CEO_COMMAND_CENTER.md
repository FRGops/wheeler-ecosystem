# Wheeler Ecosystem -- Daily CEO Command Center

## One Command. Every Morning. Full Visibility.

The Daily CEO Health Check is the single command the Wheeler CEO runs each morning to verify that every critical system is operational.

## Quick Start

```bash
/root/scripts/ecosystem-health-quick.sh
```

No arguments. No configuration. Run it from the Hetzner CPX51 control plane.

## What It Checks (in order)

| # | Check | What It Tells You |
|---|-------|-------------------|
| 1 | Tailscale tunnel | Number of mesh nodes, any offline peers |
| 2 | fundsrecoverygroup.com | Revenue site HTTP status |
| 3 | predictionradar.app | Revenue site HTTP status |
| 4 | Docker unhealthy containers | Any containers failing health checks |
| 5 | Docker container count | Running vs total containers |
| 6 | PM2 process summary | Online/stopped/errored counts + restarts |
| 7 | Prometheus alerts | Firing alert count with names |
| 8 | Disk usage | Root partition fill percentage |
| 9 | Memory usage | RAM consumption |
| 10 | Load average | CPU load vs core count |
| 11 | COREDB (100.118.166.117) | Remote container count via SSH |

## Reading the Output

```
[PASS]  Service is healthy
[FAIL]  Service is down or degraded -- investigate immediately
[WARN]  Service is operational but outside ideal range -- review
```

At the bottom, a summary block shows:
- **Score**: Percentage of checks passing
- **Verdict**: ALL CLEAN / DEGRADED / ATTENTION REQUIRED / CRITICAL

## Color Coding

- **Green** = PASS -- everything nominal
- **Red** = FAIL -- needs investigation
- **Yellow** = WARN -- not failing but worth watching

## Secrets Safety

All output is run through a redaction filter. Bearer tokens, API keys, passwords, and authorization headers are replaced with `***REDACTED***`. The script never writes to disk, creates no temporary files, and modifies nothing on the system.

## Runtime Target

The script is designed to complete in under 30 seconds:
- 10s HTTP checks (2 x 5s timeouts)
- 10s SSH to COREDB (8s timeout + command)
- 10s local checks (docker, pm2, system, tailscale)

## Prerequisites

- Tailscale CLI (`tailscale`)
- Docker CLI (`docker`)
- PM2 (`pm2`)
- Python 3 (`python3`)
- SSH access to root@100.118.166.117 (COREDB)
- Prometheus on 127.0.0.1:9090 (optional -- skipped if unavailable)

## Exit Code

- `0` = zero failures (warns are OK)
- `1` = one or more checks failed

## Location

- Script: `/root/scripts/ecosystem-health-quick.sh`
- This file: `/root/wheeler-ecosystem-audit/2026-05-27-0444/DAILY_CEO_COMMAND_CENTER.md`
