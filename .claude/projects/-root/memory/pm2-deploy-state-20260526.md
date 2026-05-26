---
name: pm2-deploy-state-20260526
description: Canonical 29-process PM2 baseline — 28/29 online, 46 plugins loaded, 10 MCP servers (2026-05-26 03:52 UTC)
metadata:
  node_type: memory
  type: project
  originSessionId: session-20260526-034800
---

# PM2 Deploy State — 2026-05-26 (03:52 UTC)

**29 processes: 28 online, 1 waiting restart (embedding-service)**

Supersedes earlier 28-process snapshot. Now tracks 29 processes including `repo-listener`.

## Fleet

| Process | Status | Notes |
|---------|--------|-------|
| aiops-saas-api | online | healthy |
| backup-verification | online | healthy |
| command-center | online | healthy |
| design-agent-svc | online | healthy |
| ecosystem-guardian | online | healthy |
| embedding-service | waiting restart | 2 restarts (all-MiniLM-L6-v2 :8191) |
| event-bus-relay | online | healthy |
| executive-dashboard-api | online | healthy |
| frgcrm-agent-svc | online | healthy |
| frgcrm-api | online | healthy |
| horizon-agent-svc | online | healthy |
| insforge-agent-svc | online | healthy |
| litellm | online | healthy (:4049) |
| openclaw-dashboard | online | healthy |
| paperless-agent-svc | online | healthy |
| pm2-logrotate | online | 3 restarts (10M/30retain/compress/midnight) |
| prediction-radar-agent-svc | online | healthy |
| ravyn-agent-svc | online | healthy |
| repo-engine | online | healthy |
| repo-listener | online | 1 restart |
| revenue-metrics-collector | online | healthy |
| surplusai-portal-api | online | healthy |
| surplusai-scraper-agent-svc | online | healthy |
| voice-agent-svc | online | healthy |
| voice-outreach-service | online | healthy |
| war-room-server | online | healthy |
| wheeler-brain-api | online | healthy |
| wheeler-collectors | online | healthy |
| wheeler-orchestrator | online | healthy |

## Plugins (03:52 reload)

46 plugins, 173 agents, 45 skills, 15 hooks, 10 MCP servers, 12 LSP servers

New since last snapshot: playwright, semgrep, sourcegraph, context7, greptile, remember, postman, supabase, notion, figma, github

210MB plugin cache disk usage.

## Need Attention

- embedding-service: "waiting restart" — 2 restarts. Verify with /slay if still in this state next session.
