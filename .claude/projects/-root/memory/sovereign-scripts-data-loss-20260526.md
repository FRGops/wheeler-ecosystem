---
name: sovereign-scripts-data-loss-20260526
description: 6 of 8 sovereign scripts lost to worktree isolation bug — FULLY RESTORED + 14 critical bugs fixed on 2026-05-26
metadata:
  node_type: memory
  type: project
  originSessionId: 15e2f1fe-75ed-4a70-a746-b63a482f0d7f
---

6 of 8 sovereign scripts in /root/scripts/ were lost when a Claude Code agent with `isolation: "worktree"` completed and its worktree was cleaned up.

**RESOLVED on 2026-05-26:** All 6 scripts rebuilt to production-grade and committed to git.

**BUG FIX WAVE (2026-05-26):** Deep audit found 14 critical bugs across all 8 scripts:
- C1: URL colon-parsing broken (IFS=":" on http:// URLs) — fixed in deploy-pipeline + kpi-dashboard
- C2: Non-atomic file locking in 6 scripts — replaced with noclobber + guard pattern
- C3: pipefail kills error handling in backup-test.sh — wrapped in if/else
- C4: Python $svc_name never interpolated in staging-provision — fixed string concat
- C5: docker volume prune -f destroyed ALL volumes — now targets staging only
- C6: --gate skip conditions missing for gates 4-7 in deploy-pipeline — added
- C7: Gate counting always 0/1 due to echo|grep -c — fixed with array loop
- C9: JSON injection from unescaped variables in 3 scripts — all fields escaped
- usage(): 5 scripts dumped source code instead of help text — replaced with heredocs
- compliance-evidence --json crashed on $4 unbound variable — fixed call sites
- ecosystem-health-check stale lock blocked all runs — kill -0 liveness check added

Commits: 057eb9a (initial restore), fdbb14e (local bug fix), 741e216 (14 critical bugs)

All 8 sovereign scripts now:
- sovereign-ecosystem-health-check.sh (39KB) — Stale lock fix with liveness check
- sovereign-backup-test.sh (42KB) — pipefail-safe restore pipelines
- sovereign-kpi-dashboard.sh (21KB) — Fixed endpoint checks, locking, usage()
- sovereign-compliance-evidence.sh (19KB) — Fixed --json crash, locking, usage()
- sovereign-investor-report.sh (14KB) — Fixed JSON escaping, locking, usage()
- sovereign-staging-provision.sh (18KB) — Fixed container names, volume prune, locking
- sovereign-revenue-recovery.sh (18KB) — Fixed JSON escaping, locking, usage(), local bugs
- sovereign-deploy-pipeline.sh (22KB) — Fixed colon-parsing, locking, gate skip, gate counting, usage()

All 8: bash -n clean, --help clean, --json valid, committed to git.

**Durability:** All scripts committed to git. Worktree isolation can no longer cause data loss.

**How to apply:** Scripts are at /root/scripts/sovereign-*.sh. All support --json, --help, lock files, cleanup traps.
