---
trigger: /slay
description: Sync the current Claude Code session into the Wheeler Command Brain vault
---

# /slay — Sync Brain

Runs the full Wheeler Command Brain OS sync pipeline after a coding session.

## Usage
```
/slay
```

## What happens
1. Export Claude Code sessions from ~/.claude/history.jsonl
2. Import any AI exports if present
3. Scan for secrets — **halts on RED findings**
4. Create agent slices (10 balanced batches)
5. Consolidate: topics, tools, entities, company rollups
6. Run validation (16 checks)
7. Report what changed

## Shell equivalent
```bash
VAULT=/root/backups/wheeler-command-brain /root/backups/wheeler-command-brain/_build/scripts/sync_brain.sh
```

## Rules
- Do NOT run automatically every prompt — manual only
- Do NOT sync if RED secrets are found
- Do NOT modify ~/.claude/projects/*.jsonl raw files
- Always check SECURITY-REDACTION-REPORT.md after sync

## Post-sync checklist
- [ ] Secret scan: GREEN
- [ ] Sessions exported
- [ ] Topics/entities generated
- [ ] Validation: GREEN or YELLOW

## If vault missing
```bash
# Build vault first
mkdir -p ~/WheelerCommandBrain/_build/scripts
# (Scripts should already exist from initial build)
python3 ~/WheelerCommandBrain/_build/scripts/export_claude_code_sessions.py --dry-run
```

## Note for AI Ops
The Wheeler Command Brain vault (`/root/backups/wheeler-command-brain/`) does not exist on this node yet.
Run `/slay` on Hostinger for the canonical brain sync. To enable on AI Ops, replicate the vault from Hostinger:
```bash
scp -r hostinger:/root/backups/wheeler-command-brain/ /root/backups/wheeler-command-brain/
```
