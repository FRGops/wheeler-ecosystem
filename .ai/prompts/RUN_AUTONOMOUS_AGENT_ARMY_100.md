# Run Autonomous Agent Army to 100/100

## Prompt Template

```
Deploy the Wheeler Agent Army for the following mission:

MISSION: [describe the multi-agent task]

DEPLOYMENT RULES:
1. Use .ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md to determine which agents to deploy.
2. Deploy only the agents needed — not the maximum possible.
3. Assign clear, non-overlapping scopes to each agent.
4. No two agents edit the same file simultaneously.
5. Orchestrator agent coordinates and merges outputs.
6. Final Boss Reviewer validates all outputs.

AUTONOMY LEVEL: [0-5, see .ai/autonomy/AUTONOMY_LEVELS.md]
CHANGE BUDGET: [files] files, [lines] lines maximum.

HARD GATES (stop and escalate):
- Production deploy
- DB migration
- Secrets
- Shell profiles
- DeepSeek routing
- Auth/security/payment changes

OUTPUT: Merged report with Final Boss verdict and 14-point response contract.

DEEPSEEK PROTECTION: Active. Do not touch model routing.
NO FALSE GREENS: Active. Evidence required for all claims.
```
