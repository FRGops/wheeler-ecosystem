# Wheeler Deployment Runbook

## Safety First

ALL deployments default to **dry-run**. Use `--execute` only after verifying the preflight.

## Preflight Checklist

Before any deployment:
1. `wheeler health` — ecosystem healthy?
2. `wheeler repos` — repo clean?
3. `wheeler deploy <app> --dry-run` — preflight check
4. `wheeler smoke <app>` — current version working?
5. Verify backups: `wheeler backups`
6. Know the rollback: `wheeler deploy <app> --dry-run` shows rollback command

## Deploy Commands

```bash
# Dry run (safe — no changes made)
wheeler deploy <app> --dry-run

# Real deployment (use with caution)
wheeler deploy <app> --execute
```

## Rollback

Each app should have a `rollback_command` in `config/repos.yml`. After filling those in:

```bash
# Rollback is app-specific — check config
wheeler deploy <app> --dry-run  # Shows rollback command
```

## Post-Deploy Verification

```bash
wheeler smoke <app>     # Smoke test the app
wheeler domains         # Check domain health
wheeler docker <server> # Check container health
wheeler logs <service>  # Check for errors
```

## Emergency Rollback

If a deploy goes wrong:
1. `wheeler panic` — assess the situation
2. Run the rollback command from config
3. `wheeler smoke all` — verify recovery
4. `wheeler logs <service>` — root cause analysis

## Configuration

Deployment config is in `config/repos.yml`. Each repo needs:
- `path` — local repo path
- `server` — target server
- `deploy_command` — how to deploy
- `smoke_command` — how to verify
- `rollback_command` — how to undo
