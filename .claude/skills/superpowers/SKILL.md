---
name: superpowers
description: "Meta-skill: best practices for Claude Code power usage — parallel agents, plans, worktrees, systematic debugging"
trigger: superpowers, how to use claude code, best practices, parallel agents, write a plan, git worktrees, subagent, dispatching agents, code review request, verification, systematic debugging, TDD, test driven
---

# Skill: Superpowers

Meta-skill for Claude Code best practices. Reference when setting up complex workflows or explaining advanced patterns.

## Core Patterns

### Dispatching Parallel Agents
```
When tasks are independent, send multiple Agent() calls in one message — they run concurrently.
- Research + implementation in parallel
- Multiple file searches simultaneously
- Independent test suites
See: /root/.claude/skills/superpowers/dispatching-parallel-agents/
```

### Writing Plans (`/plan`)
```
1. Explore phase: launch up to 3 Explore agents in parallel
2. Design phase: launch Plan agent(s)
3. Review: AskUserQuestion for blockers
4. ExitPlanMode to request approval
Plan file: /root/.claude/plans/<name>.md
```

### Git Worktrees (Parallel Feature Work)
```bash
git worktree add /tmp/feature-branch -b feature/name
# Work in isolated copy — no conflict with main working tree
git worktree remove /tmp/feature-branch
```

### Systematic Debugging
```
1. Read the actual error (don't guess)
2. Identify the assumption that's wrong
3. Find the minimal reproduction
4. Fix root cause, not symptom
5. Verify the fix doesn't regress
```

### Verification Before Completion
```
Never report task complete without:
- Running the code (or curl/test)
- Checking for errors in logs
- Verifying the golden path works
```

### Subagent-Driven Development
```
- Use Explore agent for open-ended codebase searches
- Use Plan agent for implementation design
- Use general-purpose agent for multi-step execution tasks
- Don't delegate understanding — include file paths and line numbers in agent prompts
```

### Test-Driven Development
```
1. Write failing test first
2. Write minimal code to pass
3. Refactor (no new tests failing)
Pytest for Python, Jest for TypeScript, Playwright for E2E
```

## Reference
- `/root/.claude/skills/superpowers/` — full pattern library with worked examples
- `/root/docs/claude/COMMANDS_AND_SKILLS_INDEX.md` — all slash commands + skills
