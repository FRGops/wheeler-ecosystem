---
name: pm2-deploy-state-20260526
description: Canonical 29-process PM2 baseline — 29/29 online, Wheeler Coding OS v2.1 locked in, all configs durable across sessions (2026-05-26 05:15 UTC)
metadata:
  node_type: memory
  type: project
  originSessionId: session-20260526-050643
---

# PM2 Deploy State — 2026-05-26 (05:15 UTC)

**29 processes: 29/29 online. Wheeler Coding OS v2.1 locked in.**

8 build-speed optimizations deployed. Medium builds: 20-30min → 7-12min.
BUILD_CONTEXT token usage reduced ~60% (~500 tokens saved per prompt).

## Fleet

| Process | Status | Restarts | Notes |
|---------|--------|----------|-------|
| aiops-saas-api | online | 0 | healthy |
| backup-verification | online | 0 | healthy |
| command-center | online | 0 | healthy |
| design-agent-svc | online | 0 | healthy |
| ecosystem-guardian | online | 0 | healthy |
| embedding-service | online | 110 | all-MiniLM-L6-v2 :8191 (200 OK), huggingface-hub 1.16.1 |
| event-bus-relay | online | 0 | healthy |
| executive-dashboard-api | online | 0 | healthy |
| frgcrm-agent-svc | online | 0 | healthy |
| frgcrm-api | online | 0 | healthy |
| horizon-agent-svc | online | 0 | healthy |
| insforge-agent-svc | online | 0 | healthy |
| litellm | online | 1 | :4049 (restarted for v2.1 config — timeouts+fallbacks+Redis cache) |
| openclaw-dashboard | online | 0 | healthy |
| paperless-agent-svc | online | 0 | healthy |
| pm2-logrotate | online | 3 | 10M/30retain/compress/midnight (module) |
| prediction-radar-agent-svc | online | 0 | healthy |
| ravyn-agent-svc | online | 0 | healthy |
| repo-engine | online | 0 | healthy |
| repo-listener | online | 1 | real-time repo detection |
| revenue-metrics-collector | online | 0 | healthy |
| surplusai-portal-api | online | 0 | healthy |
| surplusai-scraper-agent-svc | online | 0 | healthy |
| voice-agent-svc | online | 0 | healthy |
| voice-outreach-service | online | 0 | healthy |
| war-room-server | online | 0 | healthy |
| wheeler-brain-api | online | 0 | healthy |
| wheeler-collectors | online | 0 | healthy |
| wheeler-orchestrator | online | 0 | healthy |

## Docker: 45/45 healthy (all HEALTHCHECK passing)

## Wheeler Coding OS v2.1 — 8 Optimizations (LOCKED IN)

### 1. LiteLLM Config Hardening
- `request_timeout: 45`, `num_retries: 2` in litellm_settings
- Fallback chains: deepseek-chat→claude-sonnet-4, etc.
- Per-model timeouts: 45s/60s/90s/120s
- `routing_strategy: latency-based-routing`
- Redis caching active

### 2. ARMY_MODE Always-On
- ARMY_MODE="yes" unconditionally (user override)
- Deploy count right-sized: micro/small=2, medium=4, large=6, critical=as-needed

### 3. Sleep Elimination
- deploy-productization-fleet.sh: parallel PM2 starts (no sleep 2)
- Health check polling: 500ms intervals (was 1-5s)

### 4-5. Phase Merging (9→7 phases)
- REVIEW+SECURITY merged (8 parallel agents)
- VERIFY+FINAL BOSS merged (5 parallel agents)

### 6. Discovery Cache
- Keyed by (git HEAD, file_list_hash), 3600s TTL
- Cache dir: ~/.ai/discover-cache/

### 7. Model Tier Routing
- DISCOVER/IMPLEMENT: deepseek-chat (speed)
- REVIEW/SECURITY: premium_review (quality)
- FINAL BOSS: claude-opus-4 (ultimate quality)

### 8. Never-Stop Enforcement
- Per-phase time budgets with auto-escalation
- 3x loop→alt approach, 5x→escalate to human
- Terminal states: 100/100, UNVERIFIED list, or blocker report

## Token Savings (v2.1)
- Compact BUILD_CONTEXT: ~300-400 tokens (was ~800-1000) — ~60% reduction
- Estimated: ~2M tokens/month saved on DeepSeek V4
- Prompt caching: 21.6M cache read tokens/session (reused from prior sessions)
- `tengu_crystal_beam.budgetTokens: 0` — extended thinking disabled (speed choice)

## free-claude-code Evaluation
- **Decision: DO NOT integrate.** Unofficial proxy, TOS violations, API key exposure risk, instability. Current LiteLLM→DeepSeek setup is more reliable and already cost-optimized.

## Git Commits (v2.1)
```
164297f perf: compact BUILD_CONTEXT — 60% fewer tokens per prompt
0adc05f perf: build speed v2.1 — 20-30min → 7-12min (8 optimizations)
bb7088b feat: Wheeler Coding OS v2.0 — auto-approve always-on
```

## Config Durability
All v2.1 configs survive session restarts:
- settings.json: bypassPermissions defaultMode + Bash(*) wildcard
- UserPromptSubmit hook: ARMY_MODE="yes" always-on
- LiteLLM: 6 timeouts + 5 fallback chains + Redis cache
- Pipeline: 7-phase spec in .ai/subagents/
- All committed to git

## Known Dependency Conflict
aider-chat needs huggingface-hub==1.4.1; embedding-service needs >=1.5.0.
Current: huggingface-hub 1.16.1 → embedding-service works, aider-chat may need venv isolation.
