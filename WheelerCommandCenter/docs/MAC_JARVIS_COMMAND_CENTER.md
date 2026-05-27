# Mac Jarvis Command Center

The Wheeler Jarvis Command Center transforms your terminal into a centralized command-and-control hub for the entire Wheeler ecosystem.

## Philosophy

- **One terminal, full control** — Every server, service, domain, and agent from a single CLI
- **Safe by default** — Dry-run deployments, read-only monitoring, proposed fixes only
- **Evidence-based** — No false greens, every claim verified
- **Expandable** — Add servers, repos, agents, and domains through config files

## Architecture

```
Your Terminal (Mac/Linux)
        │
        ├── wheeler health        → Local + Remote ecosystem health
        ├── wheeler ssh <s>       → Direct SSH to any server
        ├── wheeler docker all    → Docker status across the fleet
        ├── wheeler domains       → Public domain/SSL monitoring
        ├── wheeler repos         → Code repository status
        ├── wheeler deploy <app>  → Safe deployment preflight
        ├── wheeler smoke all     → Application smoke tests
        ├── wheeler backups       → Backup verification
        ├── wheeler ai <mode>     → AI model routing control
        ├── wheeler agents        → Agent workflow launcher
        ├── wheeler panic         → Emergency incident response
        └── wheeler scorecard     → 100/100 readiness scoring
```

## Key Workflows

### Morning CEO Routine
```bash
wheeler health       # Full ecosystem health
wheeler domains      # Public site health
wheeler smoke all    # App-level smoke tests
wheeler today        # AI-curated daily briefing
```

### Before Deployment
```bash
wheeler repos                   # Check repo status
wheeler deploy <app> --dry-run  # Preflight check
wheeler smoke <app>             # Pre-deploy smoke test
```

### Emergency
```bash
wheeler panic         # Instant triage
wheeler logs <svc>    # Investigate
wheeler docker all    # Check containers
```

## File Reference

| File | Purpose |
|------|---------|
| `bin/wheeler` | Main CLI router |
| `bin/wheeler-health` | System health checks |
| `bin/wheeler-ssh` | SSH connection handler |
| `bin/wheeler-docker` | Docker fleet management |
| `bin/wheeler-deploy` | Safe deployment preflight |
| `bin/wheeler-domains` | Domain/SSL checks |
| `bin/wheeler-logs` | Service log access |
| `bin/wheeler-smoke` | Smoke test runner |
| `bin/wheeler-backup-check` | Backup verification |
| `bin/wheeler-ai` | AI model routing |
| `bin/wheeler-agents` | Agent workflow launcher |
| `bin/wheeler-scorecard` | Readiness scoring |
| `config/servers.yml` | Server registry |
| `config/domains.yml` | Domain registry |
| `config/repos.yml` | Repository registry |
| `config/services.yml` | Service registry |
| `config/agents.yml` | Agent registry |
| `config/model-routing.yml` | AI model routing config |

## Extending

Add a new server:
1. `config/servers.yml` — add server entry
2. `~/.ssh/config` — add SSH Host block
3. Test: `wheeler ssh <new-server>`

Add a new command:
1. `bin/wheeler-<command>` — create script
2. `bin/wheeler` — add case in router
3. `chmod +x bin/wheeler-<command>`
