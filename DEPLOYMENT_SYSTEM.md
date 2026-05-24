# Wheeler Deployment & Release Engineering System

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        WHEELER ECOSYSTEM                              │
├───────────────────┬──────────────────────┬───────────────────────────┤
│   EDGE NODE        │   AIOPS NODE          │   COREDB NODE             │
│   Hostinger        │   Hetzner              │   Hetzner                 │
│   187.77.148.88    │   5.78.140.118         │   5.78.210.123            │
├───────────────────┼──────────────────────┼───────────────────────────┤
│ Traefik           │ PM2 Apps              │ PostgreSQL                │
│ Nginx             │ LiteLLM               │ Redis                     │
│ Frontend Apps     │ OpenClaw              │ MinIO                     │
│ Dashboards        │ AI Workers            │ Vector DBs                │
│                   │ APIs                  │ Backups                   │
│                   │ Orchestration         │ Observability Storage     │
├───────────────────┼──────────────────────┼───────────────────────────┤
│ Docker Deploy     │ PM2 + Docker Deploy   │ Docker Deploy (DB-safe)   │
│ Zero-downtime     │ Zero-downtime         │ Backup-first              │
│ Canary capable    │ Canary capable        │ Staged migrations         │
└───────────────────┴──────────────────────┴───────────────────────────┘
```

## Document Index

| Phase | Document | Purpose |
|-------|----------|---------|
| 1 | [DEPLOYMENT_ARCHITECTURE.md](docs/DEPLOYMENT_ARCHITECTURE.md) | Overall deployment topology and strategy |
| 2 | [ENV_STANDARDIZATION.md](docs/ENV_STANDARDIZATION.md) | Environment variable standards and policies |
| 4 | [CANARY_DEPLOYMENT_PLAN.md](docs/CANARY_DEPLOYMENT_PLAN.md) | Gradual traffic switching and canary strategy |
| 11 | [DEPLOYMENT_DASHBOARD_PLAN.md](docs/DEPLOYMENT_DASHBOARD_PLAN.md) | Deployment observability dashboard design |
| 12 | [AI_DEPLOYMENT_STRATEGY.md](docs/AI_DEPLOYMENT_STRATEGY.md) | AI service deployment and model routing |
| 13 | [DB_SAFE_DEPLOYMENTS.md](docs/DB_SAFE_DEPLOYMENTS.md) | Database migration safety rules |
| 14 | [DEPLOYMENT_PLAYBOOKS.md](docs/DEPLOYMENT_PLAYBOOKS.md) | Step-by-step deployment procedures |
| 15 | [EXECUTIVE_RELEASE_REPORT.md](docs/EXECUTIVE_RELEASE_REPORT.md) | Maturity assessment and roadmap |

## Scripts Index

| Directory | Contents |
|-----------|----------|
| `deployment-engine/` | Core deployment scripts (deploy, verify, rollback, preflight, healthcheck) |
| `rollback-engine/` | Rollback orchestration and recovery scripts |
| `scripts/` | Release validation, pre-deploy backup, backup manifest |
| `.github/workflows/` | CI/CD pipeline templates (build, lint, test, docker, deploy, health) |

## Templates Index

| Path | Purpose |
|------|---------|
| `templates/.env.example` | Canonical environment variable template |
| `templates/pm2/ecosystem.config.js` | Standardized PM2 ecosystem config |
| `templates/pm2/log-rotation.conf` | PM2 log rotation configuration |
| `templates/pm2/restart-policy.md` | PM2 restart policy documentation |
| `templates/pm2/detect-duplicates.sh` | PM2 duplicate/stale service detector |
| `templates/docker/docker-compose.template.yml` | Standardized docker-compose template |
| `templates/docker/docker-healthcheck.template` | Docker HEALTHCHECK templates |
| `templates/docker/docker-logging.conf` | Docker logging configuration |
| `templates/docker/docker-network-policy.md` | Network segmentation policy |
| `templates/docker/docker-backup-hooks.sh` | Pre-backup hook scripts |

## Quick Reference

### Deploy a service
```bash
./deployment-engine/deploy-service.sh <service> <environment> <version>
```

### Rollback a service
```bash
./rollback-engine/rollback.sh <service> <environment>
```

### Validate a release
```bash
./scripts/release-validation.sh --environment production --server aiops
```

### Pre-deploy backup
```bash
./scripts/pre-deploy-backup.sh <service> production
```

### Check PM2 health
```bash
./templates/pm2/detect-duplicates.sh
```

## Core Principles

1. **Backup Before Deploy** — Every deployment starts with a verified backup
2. **Validate Before Switching** — Configs and health are verified before traffic shifts
3. **Rollback-First Design** — Every deploy has a tested, automated rollback path
4. **Zero-Downtime** — Rolling updates, graceful shutdowns, health-check-gated traffic
5. **Observable Deployments** — Every deploy is logged, metered, and alertable
6. **No Destructive Auto-Migrations** — Database changes are staged, validated, and reversible
7. **Single Source of Truth** — Config keys are defined once, consumed everywhere
