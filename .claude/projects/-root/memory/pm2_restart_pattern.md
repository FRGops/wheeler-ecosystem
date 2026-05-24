---
name: pm2-restart-pattern
description: How to safely restart PM2 processes in the Wheeler ops framework
metadata: 
  node_type: memory
  type: reference
  originSessionId: 4564ad90-b245-4bbf-91f9-e3f974daca94
---

The Wheeler autonomous ops layer restarts PM2 processes using a verify→act→verify safety pattern:

1. **Pre-check**: `pm2 jlist` → parse JSON → identify processes with status != "online"
2. **Action**: `pm2 restart <name>` per failed process (with 30s timeout)
3. **Post-check**: `pm2 jlist` again → verify all targeted processes are now "online"

This is implemented in `autoheal-engine/restart_failed_pm2.py:restart_failed_pm2()`.

**Why:** Blind restarts can mask root causes and trigger restart loops. The verify→act→verify pattern ensures we only touch processes that are actually down and confirms the restart worked.

**HealingAction** records include: pre_check_ok, action_succeeded, post_check_ok, rollback_info with previous state, and timestamps for audit trails. All actions default to dry-run unless `--execute` is explicitly passed to the orchestrator.
