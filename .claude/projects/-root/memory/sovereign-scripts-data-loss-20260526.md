---
name: sovereign-scripts-data-loss-20260526
description: 6 of 8 sovereign scripts lost to worktree isolation bug — FULLY RESTORED on 2026-05-26
metadata:
  node_type: memory
  type: project
  originSessionId: 15e2f1fe-75ed-4a70-a746-b63a482f0d7f
---

6 of 8 sovereign scripts in /root/scripts/ were lost when a Claude Code agent with `isolation: "worktree"` completed and its worktree was cleaned up.

**RESOLVED on 2026-05-26:** All 6 scripts rebuilt to production-grade and committed to git (commit 057eb9a).

All 8 sovereign scripts now:
- sovereign-ecosystem-health-check.sh (39KB) — Full ecosystem health audit, original survived
- sovereign-backup-test.sh (42KB) — Backup restoration test with temp containers, original survived
- sovereign-kpi-dashboard.sh (21KB) — 66 KPIs across PM2/Docker/system/services/revenue/git (REBUILT)
- sovereign-compliance-evidence.sh (19KB) — Evidence bundles with manifest + SHA256 checksums (REBUILT)
- sovereign-investor-report.sh (14KB) — Board-ready financial reports with composite scoring (REBUILT)
- sovereign-staging-provision.sh (18KB) — Isolated staging deploy with --destroy/--status (REBUILT)
- sovereign-revenue-recovery.sh (18KB) — Revenue process monitoring + auto-recovery engine (REBUILT)
- sovereign-deploy-pipeline.sh (22KB) — 7-gate deploy pipeline with rollback plans (REBUILT)

Total: 194,617 bytes of production-grade shell scripting. All executable, all syntax-verified, all committed to git.

**Durability:** All scripts committed to git. Worktree isolation can no longer cause data loss.

**How to apply:** Scripts are at /root/scripts/sovereign-*.sh. All support --json, --help, lock files, cleanup traps.
