---
name: wheeler
description: "Wheeler Jarvis Command Center — ecosystem health, Docker fleet, domains, SSH, deploy, logs, smoke tests, AI routing, agents, panic mode, scorecard"
trigger: wheeler, /wheeler, wheeler health, wheeler docker, wheeler domains, wheeler panic, wheeler scorecard, wheeler deploy, wheeler smoke, wheeler today, wheeler ssh, wheeler backups, command center, jarvis
---

# Skill: /wheeler — Wheeler Jarvis Command Center

The central command-and-control interface for the 4-server Wheeler ecosystem. Every subcommand maps to the actual `wheeler` CLI at `~/WheelerCommandCenter/bin/wheeler`.

## When to Use

- User types `/wheeler` or `wheeler` — show the command menu
- User asks about ecosystem health, server status, Docker, domains, deployment
- User needs panic/incident response
- User wants AI routing status or model switching
- User needs smoke tests, backups, or scorecard

## Direct Commands (run via Bash)

### Health & Status
```
wheeler          → Bash: ~/WheelerCommandCenter/bin/wheeler
wheeler health   → Bash: ~/WheelerCommandCenter/bin/wheeler-health
wheeler today    → Bash: ~/WheelerCommandCenter/bin/wheeler-health --ceo
wheeler doctor   → Bash: ~/WheelerCommandCenter/bin/wheeler-health --doctor
wheeler panic    → Bash: ~/WheelerCommandCenter/bin/wheeler-health --panic
```

### Server Access
```
wheeler ssh <s>     → Bash: ~/WheelerCommandCenter/bin/wheeler-ssh <s>
wheeler docker <s>  → Bash: ~/WheelerCommandCenter/bin/wheeler-docker <s>
wheeler mesh        → Bash: ~/WheelerCommandCenter/bin/wheeler-health --mesh-only
```

### Operations
```
wheeler domains              → Bash: ~/WheelerCommandCenter/bin/wheeler-domains
wheeler repos                → Bash: ~/WheelerCommandCenter/bin/wheeler-health --repos-only
wheeler deploy <app>         → Bash: ~/WheelerCommandCenter/bin/wheeler-deploy <app>
wheeler smoke <app|all>      → Bash: ~/WheelerCommandCenter/bin/wheeler-smoke <app|all>
wheeler logs <svc>           → Bash: ~/WheelerCommandCenter/bin/wheeler-logs <svc>
wheeler backups               → Bash: ~/WheelerCommandCenter/bin/wheeler-backup-check
```

### AI & Agents
```
wheeler ai <mode>    → Bash: ~/WheelerCommandCenter/bin/wheeler-ai <mode>
wheeler agents       → Bash: ~/WheelerCommandCenter/bin/wheeler-agents <action>
wheeler scorecard    → Bash: ~/WheelerCommandCenter/bin/wheeler-scorecard
```

## Standard Execution Pattern

ALWAYS use Bash to execute wheeler commands directly — never simulate or mock:

```bash
export WHEELER_HOME="$HOME/WheelerCommandCenter"
export PATH="$WHEELER_HOME/bin:$PATH"
wheeler <subcommand>
```

## Key Facts

- 4 servers: Mac (100.83.80.6), Hostinger (187.77.148.88 / TS 100.98.163.17), Hetzner (5.78.140.118 / TS 100.121.230.28), CoreDB (5.78.210.123 / TS 100.118.166.117)
- 47 Docker containers on Hetzner, 6 on Hostinger, 20 on CoreDB — all healthy
- 85 PM2 processes on Hetzner — all online
- ~60 AI agent services across the ecosystem
- Deployments are dry-run by default (use --execute for real)
- All agents follow safety protocol: detect→classify→propose→backup→patch→test→verify→rollback→document

## Quick Reference

| Need | Command |
|------|---------|
| Is everything up? | `wheeler health` |
| Sites working? | `wheeler domains` |
| Deploy something? | `wheeler deploy <app> --dry-run` |
| Emergency? | `wheeler panic` |
| Which AI model? | `wheeler ai status` |
| Daily briefing | `wheeler today` |
| Readiness score | `wheeler scorecard` |
