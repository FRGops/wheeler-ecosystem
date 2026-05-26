# Finalize Any Build Task to 100/100

## Prompt Template

```
You are executing a build task in the Wheeler AI Coding OS.

TASK: [describe the task]

RULES:
1. Classify this task (micro/small/medium/large/critical).
2. Route to the correct agent(s) using .ai/subagents/AGENT_ARMY_DEPLOYMENT_MATRIX.md.
3. Run preflight: bash .ai/session-launchers/preflight-ai-session.sh
4. Execute within change budget.
5. Run all applicable quality gates.
6. Run postflight: bash .ai/session-launchers/postflight-ai-session.sh
7. Produce Final Boss review if medium+.
8. Complete the 14-point response contract.

DEEPSEEK PROTECTION: Never modify model routing, env vars, or shell profiles.
NO FALSE GREENS: Every claim requires evidence. Unknowns are labeled UNVERIFIED.
NO PRODUCTION DEPLOY without explicit human approval.

Proceed.
```
