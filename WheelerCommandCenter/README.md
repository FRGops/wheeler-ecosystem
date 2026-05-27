# Wheeler Jarvis Command Center

The **Wheeler Jarvis Command Center** is the central operations hub for the entire Wheeler ecosystem. From here you can monitor, control, audit, deploy, and operate all 4 servers (Mac, Hostinger, Hetzner, CoreDB), all 10+ business engines, and the complete AI agent fleet — from a single terminal.

## Quick Install

```bash
export WHEELER_HOME="$HOME/WheelerCommandCenter"
export PATH="$WHEELER_HOME/bin:$PATH"
```

Add to `~/.bashrc` or `~/.zshrc` for persistence.

## Commands

| Command | Description |
|---------|-------------|
| `wheeler` | Show main menu |
| `wheeler health` | Full ecosystem health dashboard |
| `wheeler ssh <server>` | SSH to hostinger/hetzner/coredb |
| `wheeler mesh` | Tailscale mesh status |
| `wheeler docker <s\|all>` | Docker status across servers |
| `wheeler domains` | Domain/SSL health checks |
| `wheeler repos` | Repository status |
| `wheeler services` | Service registry |
| `wheeler logs <service>` | View service logs |
| `wheeler deploy <app>` | Deployment preflight (dry-run default) |
| `wheeler smoke <app\|all>` | Smoke tests |
| `wheeler backups` | Backup verification |
| `wheeler ai <mode>` | AI model routing control |
| `wheeler agents` | Agent workflow launcher |
| `wheeler scorecard` | Readiness scorecard |
| `wheeler panic` | Emergency incident dashboard |
| `wheeler doctor` | Full system diagnostic |
| `wheeler today` | Daily CEO dashboard |
| `wheeler docs` | Open documentation |

## Daily Usage

```bash
# Morning routine
wheeler health
wheeler domains
wheeler smoke all
wheeler today
```

## Emergency Usage

```bash
wheeler panic        # Instant status of everything
wheeler logs <svc>   # Investigate specific service
wheeler docker all   # Check all Docker fleets
```

## Adding a New Server

1. Add to `config/servers.yml`
2. Add SSH alias in `~/.ssh/config`
3. Test: `wheeler ssh <new-server>`

## Adding a New Repo

1. Add entry to `config/repos.yml`
2. Fill in path, server, deploy/smoke/rollback commands
3. Verify: `wheeler repos`

## Adding a New Domain

1. Add entry to `config/domains.yml`
2. Specify server, health_path, expected_public
3. Verify: `wheeler domains`

## Adding a New Agent

1. Add definition to `config/agents.yml`
2. Follow safety protocol: detect→classify→propose→backup→patch→test→verify→rollback→document
3. List: `wheeler agents list`

## Structure

```
WheelerCommandCenter/
├── bin/          # CLI commands
├── config/       # YAML registries
├── docs/         # Documentation
├── scripts/      # Audit scripts
├── reports/      # Generated reports
├── logs/         # Log storage
├── backups/      # Backup storage
├── runbooks/     # Operational runbooks
├── agents/       # Agent definitions
└── scorecards/   # Generated scorecards
```

## Safety

- Default deploy mode is **dry-run** (use `--execute` for real)
- Agents follow propose-only safety protocol
- No secrets stored in committed files
- No production mutation without explicit confirmation
