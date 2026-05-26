# Autonomy Levels

## Level Summary

| Level | Name | Agent Can... | Agent Cannot... |
|-------|------|-------------|-----------------|
| 0 | Advisory | Read, analyze, suggest | Edit any file |
| 1 | Docs & Planning | Create docs, plans, tickets | Edit source code |
| 2 | Safe Repo Edits | Edit source, run tests | Push, deploy, change configs |
| 3 | Build & Test Fixes | Fix builds/tests, refactor | Deploy, migrate, change auth |
| 4 | Multi-Agent Build | Full feature build on AI branch | Merge to main, deploy |
| 5 | Production Review | Review production configs | Deploy autonomously |

## Level Details

### Level 0 — Advisory Only
- Read files, analyze code, answer questions
- Suggest approaches and trade-offs
- Cannot: edit, create, delete, or run side-effect commands

### Level 1 — Docs and Planning
- Everything in Level 0
- Create/update documentation
- Create tickets and implementation plans
- Cannot: edit source code, run tests

### Level 2 — Safe Repo Edits
- Everything in Level 1
- Edit source code within change budget
- Run tests and linters
- Create commits on AI branches
- Cannot: push, deploy, modify configs

### Level 3 — Tests & Build Fixes
- Everything in Level 2
- Fix broken builds and tests
- Safe refactoring (behavior-preserving)
- Cannot: deploy, run migrations, change auth

### Level 4 — Multi-Agent Feature Build
- Everything in Level 3
- Deploy agent army for multi-file features
- Create and manage worktrees
- Run full CI pipeline locally
- Cannot: merge to main, deploy to production

### Level 5 — Production-Sensitive Review
- Everything in Level 4
- Review production configs for safety
- Create deploy plans and rollback procedures
- Cannot: execute production deploy autonomously

## Setting Autonomy Level

Per session:
```
Level 2: "Edit the login component"
Level 4: "Build the user dashboard feature"
```

Default level: **Level 2** (safe repo edits)

Escalate to human for anything above the current level.
