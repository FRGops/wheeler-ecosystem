# Rollback Runbook

## When to Rollback
- Deployment causes errors/alerts
- Smoke tests fail
- Health checks go red
- User reports of broken functionality
- Data corruption detected
- Security incident

## Rollback Decision Tree
```
Issue detected
  ├─ Critical (data loss, security, full outage)?
  │   → ROLLBACK IMMEDIATELY
  ├─ Major (broken feature, errors spiking)?
  │   → Rollback if fix > 10 min away
  └─ Minor (cosmetic, edge case)?
      → Fix forward, don't rollback
```

## Standard Rollback Procedures

### Git Rollback (last commit)
```bash
# View what will be reverted
git show HEAD

# Revert the last commit (creates new revert commit)
git revert HEAD

# Or reset if not pushed (DANGER: only if not pushed)
# git reset --hard HEAD~1  # NEVER on main/master
```

### Restore CLAUDE.md from Backup
```bash
cp CLAUDE.md.backup-* CLAUDE.md
```

### Restore AGENTS.md from Backup
```bash
cp AGENTS.md.backup-* AGENTS.md
```

### Disable Hooks
```bash
# Option 1: Remove project hook settings
# Edit .claude/settings.json and remove "hooks" key

# Option 2: Move hook scripts
mv .claude/hooks .claude/hooks.disabled.$(date +%Y%m%d)

# Option 3: Env var disable
export CLAUDE_CODE_DISABLE_HOOKS=1
```

### Remove Worktrees
```bash
# List worktrees
git worktree list

# Remove a specific worktree
git worktree remove /path/to/worktree

# Force remove (if dirty)
git worktree remove --force /path/to/worktree
```

### Docker Rollback
```bash
# Tag previous image as current
docker tag app:previous app:latest
docker compose up -d
```

## What NOT to Touch During Rollback
- DeepSeek routing configs
- Shell profiles (.zshrc, .bashrc)
- Production database (without DBA approval)
- Secrets (without security approval)
