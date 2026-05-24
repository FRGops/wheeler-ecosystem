---
name: pm2-restart-patterns
description: PM2 process restart failures and DEEPSEEK_API_KEY root cause in Wheeler ecosystem
metadata: 
  node_type: memory
  type: project
  originSessionId: 8c22f255-6b41-4b4e-a3b2-8e74d3a1bdaf
---

Three revenue-critical PM2 processes are broken on AIOPS node (Hetzner 5.78.140.118):

- **frgcrm-api** (id 6): ERROED, 15 restarts, PID 0. Error: "Could not import module main"
- **surplusai-scraper-agent-svc** (id 1): WAITING, 282+ restarts, stuck in restart loop
- **voice-agent-svc** (id 2): WAITING, 282+ restarts, stuck in restart loop

**Root cause:** DEEPSEEK_API_KEY is configured in Prediction Radar Docker environment but NOT set in PM2 process environments. All 3 services likely depend on this key for AI agent logic, causing import failures or startup dependency hangs.

**Why:** PM2 ecosystem.config.js has its own env block separate from Docker env files. When services were moved or duplicated, the AI key wasn't carried over.

**How to apply:** Before any cutover, fix these by adding DEEPSEEK_API_KEY to PM2 ecosystem.config.js env for each process, then `pm2 restart all`. After fix, verify with `pm2 list` — all 3 should show "online" status. FRGCRM API recovery may cascade-fix the other two if they depend on CRM endpoints being available.

[[revenue-cutover-prerequisites]]
