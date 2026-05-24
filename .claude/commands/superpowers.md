# /superpowers — Wheeler AI Operator Superpowers

Invoke the superpowers meta-skill to access advanced Claude Code patterns. Mirrors and extends the canonical superpowers plugin.

## Execution

When invoked, run these steps in parallel:

### 1. Inventory Superpowers from Filesystem
```bash
ls -d /root/.claude/skills/superpowers/*/
```

### 2. Count Ecosystem Assets
```bash
echo "Skills: $(ls -d /root/.claude/skills/*/ 2>/dev/null | wc -l)"
echo "Agents: $(ls /opt/wheeler-ecosystem/capabilities/agents/*.md 2>/dev/null | wc -l)"
echo "MCP envs: $(ls /opt/wheeler-ecosystem/capabilities/mcp/ 2>/dev/null | wc -l)"
echo "Commands: $(ls /opt/wheeler-ecosystem/capabilities/slash-commands/*.md 2>/dev/null | wc -l)"
```

### 3. Quick Reference by Category

**Parallelism & Execution:**
- `dispatching-parallel-agents` — Run independent Agent() calls concurrently
- `executing-plans` — Plan -> Verify -> Gate -> Execute
- `subagent-driven-development` — Explore, Plan, Implement via specialized agents
- `using-git-worktrees` — Isolated parallel feature branches

**Quality & Verification:**
- `systematic-debugging` — Read error -> Find assumption -> Minimal repro -> Root cause -> Verify
- `verification-before-completion` — Never claim done without evidence
- `test-driven-development` — Red -> Green -> Refactor
- `receiving-code-review` — Structured code review receipts
- `requesting-code-review` — Structured code review requests

**Planning & Workflow:**
- `writing-plans` — Explore -> Design -> Review -> Approve workflow
- `writing-skills` — Create new skills with proper format
- `brainstorming` — Open-ended exploration and ideation
- `finishing-a-development-branch` — Clean branch completion workflow
- `using-superpowers` — How to find and invoke skills

## Output Format

```
WHEELER SUPERPOWERS — Inventory
  Skills loaded:      <N>  (/root/.claude/skills/)
  Superpower skills:  <N>  (/root/.claude/skills/superpowers/)
  Available agents:   <N>  (/opt/wheeler-ecosystem/capabilities/agents/)
  MCP environments:   <N>  (/opt/wheeler-ecosystem/capabilities/mcp/)
  Slash commands:     <N>  (/opt/wheeler-ecosystem/capabilities/slash-commands/)

SUPERPOWER PATTERNS:
  [PARALLEL]    dispatching-parallel-agents    executing-plans
                subagent-driven-development    using-git-worktrees
  [QUALITY]     systematic-debugging           verification-before-completion
                test-driven-development        receiving-code-review
                requesting-code-review
  [PLANNING]    writing-plans                  writing-skills
                brainstorming                  finishing-a-development-branch
                using-superpowers

TIP: Invoke any superpower by name in Claude Code or read it from /root/.claude/skills/superpowers/<name>/
```
