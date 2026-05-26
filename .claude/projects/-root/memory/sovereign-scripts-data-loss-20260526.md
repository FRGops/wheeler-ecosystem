---
name: sovereign-scripts-data-loss-20260526
description: 6 of 8 sovereign scripts lost due to worktree isolation bug on 2026-05-26
metadata: 
  node_type: memory
  type: project
  originSessionId: 15e2f1fe-75ed-4a70-a746-b63a482f0d7f
---

6 of 8 sovereign scripts in /root/scripts/ were lost when a Claude Code agent with `isolation: "worktree"` completed and its worktree was cleaned up.

**Surviving scripts:**
- sovereign-ecosystem-health-check.sh (recovered from compliance evidence snapshot at /var/log/wheeler/compliance/)
- sovereign-backup-test.sh (remained in original location)

**Lost scripts (no backup exists):**
- sovereign-kpi-dashboard.sh
- sovereign-compliance-evidence.sh
- sovereign-investor-report.sh
- sovereign-staging-provision.sh
- sovereign-revenue-recovery.sh
- sovereign-deploy-pipeline.sh

**Why:** None of the scripts were ever committed to git. The worktree isolation mechanism appears to have cleaned up untracked files from the original working tree when the worktree was removed.

**How to apply:** Before using worktree isolation with untracked files, commit them first. The compliance evidence script's snapshot mechanism saved the health-check script because it copied it as evidence — this pattern should be used more broadly.
