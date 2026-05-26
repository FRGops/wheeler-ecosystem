# Army Mode Policy

## When Army Mode Activates

Army mode (multi-agent deployment) activates when:
- Task is classified as **medium** or larger
- Task spans **multiple domains** (e.g., backend + frontend + database)
- Task requires **independent parallel workstreams**
- Task is a **cross-cutting concern** (auth, logging, error handling)
- Task is a **production incident** requiring coordinated response

## Army Mode Rules

### 1. Right-Size the Army
- Medium task: 2-3 agents
- Large task: 4-5 agents
- Critical task: As needed but justify each agent
- Never deploy 5 agents for what 1 can do

### 2. No Same-File Collisions
- Assign disjoint file scopes to each agent
- Use `git worktree` for truly parallel work
- Merge worktrees sequentially, not in parallel

### 3. Avoid Token Waste
- Don't spawn agents to "check on things" for the sake of it
- Each agent must have a clear, bounded deliverable
- Cancel idle agents promptly

### 4. Split Large Work into Tickets
- Large tasks → break into medium tickets
- Each ticket is independently verifiable
- Tickets chain: Ticket 2 depends on Ticket 1's output

### 5. Always Produce Final Boss Verdict
- Every army mode session ends with a Final Boss review
- No merging until Final Boss approves
- Verdict is binding

## Army Mode Anti-Patterns

| Bad | Good |
|-----|------|
| 5 agents for a 20-line change | 1 agent (DeepSeek) |
| 2 agents editing the same file | 1 agent for that file, or sequential |
| Agents with vague "investigate" scopes | Clear deliverables per agent |
| Army deployed, then walking away | Review every agent's output |
| Skipping Final Boss for "simple" armies | Review everything |
