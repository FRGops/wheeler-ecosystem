# Model Routing Decision Matrix

## Decision Tree

```
Task received
  ├─ Is this a human approval gate? → STOP, request approval
  ├─ Is this architecture/planning? → Claude Code
  ├─ Is this bounded implementation? → DeepSeek V4 / Aider
  ├─ Is this complex debugging? → DeepSeek Reasoner
  ├─ Is this parallel terminal work? → OpenCode
  ├─ Is this IDE auto-approve flow? → Roo Code
  └─ Is this final review? → Claude Code (Final Boss)
```

## Tool Assignments by Task Type

### 1. DeepSeek V4 / Aider — Primary Implementer
**Use for:**
- Bounded file edits (1-5 files)
- Writing tests
- Small refactors
- Repetitive coding patterns
- Safe automation scripts
- Bug fixes with clear reproduction steps

**Do NOT use for:**
- Architecture decisions
- Security-sensitive code without review
- Production config changes
- Multi-repo orchestration
- Tasks requiring human judgment

### 2. DeepSeek Reasoner — Complex Diagnostics
**Use for:**
- Complex debugging sessions
- Architecture reasoning
- Multi-file diagnosis
- Tricky error investigations
- Performance profiling analysis

**Do NOT use for:**
- Simple one-line fixes
- Boilerplate generation
- Tasks a linter could catch

### 3. Claude Code — Architecture & Governance
**Use for:**
- System architecture design
- Final Boss review (all PRs)
- High-stakes decisions
- Repo governance enforcement
- Safety reviews
- Prompt compilation
- Complex multi-step planning
- Security audit review

**Do NOT use for:**
- Routine file edits (wasteful)
- Repetitive code generation
- Tasks DeepSeek can handle

### 4. OpenCode — Parallel Execution
**Use for:**
- Parallel terminal builds
- Multi-worktree sessions
- Provider-neutral agent work
- Bulk file operations

### 5. Roo Code — IDE Automation
**Use for:**
- IDE auto-approve workflows
- Local controlled repetitive coding
- VS Code-integrated tasks

### 6. Human Approval Required
**ALWAYS require human approval:**
- Production deploy
- Database migrations
- Secrets management
- Shell profile modifications
- DeepSeek routing changes
- Auth/security/payment flows
- Dependency upgrades (major)
- GitHub secrets
- Infrastructure changes (Terraform, Kubernetes)
- Legal/compliance workflows

## Cost-Control Rules

1. **Right-size the model**: Don't use Claude for tasks DeepSeek handles.
2. **Batch intelligently**: Group independent file writes.
3. **Cache-aware**: Stay within 5-min cache window for follow-up turns.
4. **Don't over-deploy agents**: One agent for a 3-file edit, not five.
5. **Small tasks (< 50 lines)**: Single model, no agent army.

## When to Escalate (DeepSeek → Claude)

Escalate when:
- DeepSeek produces 3+ incorrect answers for the same problem
- The task involves security-sensitive code paths
- Architecture decisions affect multiple services
- You're about to touch production config
- The error message is unclear and requires deep reasoning
- DeepSeek is hallucinating APIs or libraries

## When to Stop and Report

Stop and report (don't guess) when:
- You can't verify a fix without running the app
- The task requires access to a system you can't reach
- A file you need to edit doesn't exist
- Environment variables are missing
- You're asked to modify DeepSeek routing
- The task scope exceeds the change budget

## Change Budget by Task Size

| Size | Files | Lines | Max Agents | Review Required |
|------|-------|-------|------------|----------------|
| Micro | 1 | < 20 | 1 | None |
| Small | 1-3 | < 100 | 1 | Self-review |
| Medium | 3-10 | < 500 | 3 | Peer agent |
| Large | 10-25 | < 2000 | 5 | Final Boss |
| Critical | Any | Any | As needed | Final Boss + Human |
