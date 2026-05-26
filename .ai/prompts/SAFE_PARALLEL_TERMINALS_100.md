# Safe Parallel Terminals to 100/100

## Prompt Template

```
Set up parallel terminal sessions for independent workstreams:

WORKSTREAMS:
1. [Workstream A — scope, files, agent]
2. [Workstream B — scope, files, agent]
3. [Workstream C — scope, files, agent]

PARALLEL RULES:
1. Each workstream has a dedicated git worktree: git worktree add /tmp/wheeler-{name} -b ai/{name}-YYYYMMDD
2. No two workstreams touch the same files.
3. Each workstream runs its own preflight: bash .ai/session-launchers/preflight-ai-session.sh
4. Each workstream runs its own postflight: bash .ai/session-launchers/postflight-ai-session.sh
5. Merge worktrees sequentially (not in parallel) to avoid conflicts.
6. Final Boss reviews the merged result.

CLEANUP: Remove worktrees after merge: git worktree remove /tmp/wheeler-{name}

DEEPSEEK PROTECTION: Do not modify routing in any worktree.
NO FALSE GREENS: Each workstream verifies independently.
```
