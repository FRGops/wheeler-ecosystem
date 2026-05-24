---
name: mac-command-center-operator
description: "Mac-specific operator profile: local development workflow, macOS-specific tools, sync with AI Ops, Tailscale connectivity, backup strategy."
trigger: mac operator, mac setup, command center, mac dev, mac claude, mac tools, laptop setup
---

# Skill: Mac Command Center Operator

Mac-specific operator profile for the Wheeler ecosystem Command Center (wheelers-macbook-pro).

## Mac Command Center Role

The Mac is the primary operator cockpit:
- Local development environment
- Claude Code primary interface
- Ecosystem monitoring dashboard
- Manual intervention capability
- Deployment approval console

## Setup Requirements

### Core Tools
```bash
# Claude Code
npm install -g @anthropic-ai/claude-code

# Wheeler ecosystem tools (synced from AI Ops)
# Symlink from AI Ops via Tailscale or rsync

# Tailscale
# Install from https://tailscale.com/download/mac
tailscale up
```

### Sync with AI Ops
```bash
# Sync capabilities from AI Ops (run from AI Ops)
rsync -avz --exclude '.git' --exclude 'secrets*' --exclude '*.env' \
  /opt/wheeler-ecosystem/capabilities/ \
  wheelers-macbook-pro:/opt/wheeler-ecosystem/capabilities/

# Or use Wheeler sync tool
bash /opt/wheeler-ecosystem/capabilities/sync/wheeler-capabilities-sync --target mac
```

### macOS-Specific Considerations
- **Homebrew**: Prefer brew-installed tools over system
- **Alfred/Raycast**: Can integrate Wheeler CLI tools
- **iTerm2/Warp**: Terminal with Claude Code
- **Keychain**: Use for secrets, not .env files
- **Time Machine**: System-level backup complements Wheeler backups

## Operational Commands

| Action | Command |
|--------|---------|
| Health check | `wheeler-health --all` |
| Sync capabilities | `wheeler-capabilities-sync` |
| Deploy (approve only) | `wheeler-deploy --approve <component>` |
| Audit | `wheeler-capabilities-audit` |
| Status | `wheeler-capabilities-status` |

## Mac Profile

The Mac gets the FULL capability profile:
- All 19 slash commands
- All 18 skills
- All agents
- Dev MCP profile (not prod — deployment from Mac is approval only)
- All playbooks and workflows

## Safety Constraints

- Mac is approval cockpit, NOT auto-deploy source
- Production deploys require manual confirmation
- Secrets never synced to Mac (use Keychain or Tailscale SSH)
- Mac going idle is OK — no critical services run here
- Sync before each operator session: `wheeler-capabilities-sync`
