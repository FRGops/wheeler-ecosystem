# Agent Army Deployment Matrix

## When to Deploy Agents

### Task Size → Agent Count

| Task Size | Files | Lines | Max Agents | Review Level |
|-----------|-------|-------|------------|-------------|
| Micro | 1 | < 20 | 1 (DeepSeek) | Self |
| Small | 1-3 | < 100 | 1 (DeepSeek) | Self |
| Medium | 3-10 | < 500 | 3 | Peer agent |
| Large | 10-25 | < 2000 | 5 | Final Boss |
| Critical | Any | Any | As needed | Final Boss + Human |

### Task Type → Agent Routing

| Task Type | Primary Agent | Secondary Agent | Reviewer |
|-----------|--------------|----------------|----------|
| **Backend API** | Backend API Agent | Test QA Agent | Final Boss |
| **Frontend UI** | Frontend UI Agent | Accessibility Agent | Final Boss |
| **Database** | Database Agent | DevOps Safety Agent | Final Boss |
| **DevOps** | DevOps Safety Agent | Security Secrets Agent | Final Boss |
| **Security** | Security Secrets Agent | Dependency Risk Agent | Final Boss |
| **Performance** | Performance Agent | Observability Agent | Final Boss |
| **Documentation** | Docs Playbook Agent | — | Self |
| **Bug Fix (simple)** | DeepSeek Implementer | — | Test QA Agent |
| **Bug Fix (complex)** | DeepSeek Implementer | Test QA Agent | Final Boss |
| **Refactor (safe)** | DeepSeek Implementer | Test QA Agent | Self |
| **Refactor (risky)** | DeepSeek Implementer | Test QA Agent | Final Boss |
| **Production-sensitive** | Orchestrator | All relevant | Final Boss + Human |
| **Architecture** | Orchestrator | — | Final Boss + Human |
| **SEO/Conversion** | SEO Conversion Agent | Frontend UI Agent | Self |

### Solo Tasks (1 Agent Only)

These tasks never need an agent army:
- Single-file typo fix
- Adding a comment
- Updating a docstring
- Running a linter
- Formatting code
- Simple variable rename
- Adding a console.log for debugging

### Army Mode (Multiple Agents)

Trigger army mode when:
- Multi-file feature implementation
- Cross-cutting concern (auth, logging, error handling)
- Database migration + API + frontend changes
- Security audit + remediation
- Production incident response
- Major version upgrade
- New service/module creation

### Anti-Patterns

**Do NOT:**
- Deploy 5 agents for a 20-line change
- Run 2 agents that edit the same file
- Deploy agents without clear task boundaries
- Let agents run unbounded (no change budget)
- Skip the Final Boss review on medium+ tasks
- Deploy agents and walk away (always review outputs)

### Cost Awareness

Running agents costs tokens. Be frugal:
- 1 agent for micro/small tasks
- 2-3 agents for medium tasks
- 5 max for large tasks
- Sequential agents (not parallel) when outputs depend on each other
- Cancel idle agents promptly
