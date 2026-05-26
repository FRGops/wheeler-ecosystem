# Escalation Policy

## Escalation Ladder

```
Level 0: DeepSeek V4 (autonomous)
  ↓ (3 failures, security concern, or ambiguity)
Level 1: DeepSeek Reasoner (autonomous)
  ↓ (still unresolved, or architecture question)
Level 2: Claude Code (autonomous)
  ↓ (production, security, or legal implication)
Level 3: Human Review (required)
```

## Automatic Escalation Triggers

Escalate from DeepSeek to Claude Code when ANY of:

1. **Repeated failure**: DeepSeek produces 3+ incorrect solutions for the same problem.
2. **Security boundary**: The task touches auth, encryption, secrets handling, or input validation.
3. **Architecture impact**: Changes affect > 3 services or modify API contracts.
4. **Production proximity**: Editing deployment configs, Docker files, or CI/CD pipelines.
5. **Ambiguity**: The requirement is unclear and requires judgment calls.
6. **Hallucination detected**: DeepSeek references non-existent APIs, files, or libraries.

Escalate to HUMAN when ANY of:

1. **Production deploy**: Any action that pushes code to production.
2. **Database migration**: Any schema change to a live database.
3. **Secrets**: Creating, rotating, or reading secrets.
4. **Shell profiles**: Modifying `.zshrc`, `.bashrc`, `.profile`, `.bash_profile`.
5. **DeepSeek routing**: Changing model configuration.
6. **Auth flows**: Touching authentication or authorization logic.
7. **Payments**: Any payment/billing code path.
8. **Dependency upgrades**: Major version bumps.
9. **Cloud infrastructure**: Terraform, Kubernetes, server provisioning.
10. **Legal/compliance**: Any workflow with regulatory implications.

## Escalation Protocol

When escalating, include:
- **Original task**: What was requested.
- **What was tried**: Steps taken so far.
- **Why escalating**: Which trigger was hit.
- **Current state**: Files changed, branch, any errors.
- **Recommendation**: What you think should happen next.

## No Escalation Needed

Do NOT escalate for:
- Routine file edits within change budget.
- Test additions for existing code.
- Documentation updates.
- Linting/formatting fixes.
- Safe script creation (no deploy, no secrets).
- Adding comments or improving error messages.
