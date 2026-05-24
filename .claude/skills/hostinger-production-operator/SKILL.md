---
name: hostinger-production-operator
description: "Hostinger production operations: FRG ecosystem management, InsForge platform operations, prediction-radar management, production-safe deployment procedures, superpowers maintenance."
trigger: hostinger operator, hostinger production, srv1476866, frg ecosystem, insforge, prediction radar, hostinger deploy
---

# Skill: Hostinger Production Operator

Operations guide for srv1476866 — the Hostinger Production Node.

## Hostinger Role

- **FRG Ecosystem**: 18-engine platform, FRGops, FRGCRM
- **InsForge Platform**: Auth, storage, DB, edge functions, LLM gateway
- **Prediction Radar**: Trading platform with kill switch
- **Superpowers Hub**: Canonical source of superpowers skill and plugin
- **Claude Code**: Primary development environment (2.1.101)

## Key Services

### InsForge Platform
```bash
# Platform health
curl -s -X POST http://localhost:8013/agents/platform-health/run

# Services
# PostgreSQL :5435 (InsForge DB)
# PostgREST :5430
# Auth API :7130
# Edge Functions :7133
# Dashboard: https://insforge.frgops.io
```

### FRG Ecosystem
```bash
# Located at /opt/frg-ecosystem/
cd /opt/frg-ecosystem && git status

# Engine status
pm2 list | grep engine
```

### Superpowers
```bash
# Plugin version
ls /root/.claude/plugins/cache/claude-plugins-official/superpowers/

# Skill tree
find /root/.claude/skills/superpowers -name "SKILL.md"

# Health check
bash /root/scripts/superpowers-health.sh
```

## Production-Safe Profile

Hostinger gets a PRODUCTION-SAFE subset:
- **Slash commands**: audit, docker-health, pm2-health, db-lockdown, private-network, secrets-scan, daily-health, rollback, superpowers, goal, ecosystem-map, incident-response, no-false-greens
- **Skills**: docker-health, database-lockdown, private-network-check, pm2-recovery, secrets-scan, incident-response, hostinger-production-operator
- **Agents**: docker-expert, database-rls-auditor, engineering-sre, zero-false-green-auditor, devops-smoke-tester
- **MCP Profile**: Prod (read-only with approved exceptions)
- **NO**: deploy-safe (deploys require manual approval), cost-control (on AI Ops)

## Safety Constraints

- Hostinger is PRODUCTION — no experimental changes
- All deploys require AI Ops approval gate
- Database changes require backup + rollback plan
- Secrets never leave Hostinger
- Claude Code runs in acceptEdits mode (not bypass) for DeepSeek
- AI Sandbox used for high-autonomy tasks

## Sync with AI Ops

```bash
# Pull capabilities from AI Ops (receive updates)
wheeler-capabilities-sync --pull aiops

# Push superpowers to AI Ops (send canonical source)
wheeler-capabilities-sync --push superpowers
```

## Common Operations

| Operation | Command |
|-----------|---------|
| InsForge health | `curl -X POST localhost:8013/agents/platform-health/run` |
| Docker audit | `/docker-health` |
| DB lockdown | `/db-lockdown` |
| Secrets scan | `/secrets-scan` |
| Daily health | `/daily-health` |
| Superpowers check | `/superpowers` |
| Capability audit | `wheeler-capabilities-audit` |
