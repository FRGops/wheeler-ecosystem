# Default Future Agent Response Contract

Every coding/build response from any AI agent MUST end with this 14-point format.

```
## Response Contract

1. **Task Classification**: [micro / small / medium / large / critical]

2. **Workflow / Agents Used**: [list of agents deployed, or "solo"]

3. **Files Changed**: [list with +N/-N line counts]

4. **Gates Run**: [list of quality gates executed]

5. **Gates Passed**: [count] / [total]

6. **Gates Failed**: [list of failed gates — empty if none]

7. **What Is Verified**: [what you actually checked, with evidence]

8. **What Is UNVERIFIED**: [what you couldn't check — be honest]

9. **DeepSeek Routing Touched?**: yes / no

10. **Secrets Touched?**: yes / no

11. **Production Deploy Touched?**: yes / no

12. **Dependency Changes?**: yes / no

13. **Readiness Score**: [0-100] — see scoring rules below

14. **Next Best Action**: [one clear next move]
```

## Truth Rules

### NO "live" unless you hit a live endpoint/UI
If you can't curl the endpoint or load the page, say "not verified live."

### NO "deployed" unless you have a deploy log
"Files were written" is not deployed. "Container restarted" is not deployed. Show the deploy command and its output.

### NO "100/100" unless ALL required checks pass
See `.ai/observability/READINESS_SCORE_SCHEMA.md` for scoring rules.

### NO hiding failures
If a gate failed, say so. If you're unsure about something, say so. Honesty over appearance.

## Examples

### Good (honest, evidence-based)
```
7. What Is Verified: All 12 tests pass (pasted output below). Lint clean. No secrets in diff.
8. What Is UNVERIFIED: Could not test the /api/webhook endpoint (needs Stripe test key). UI looks correct but not tested on mobile.
13. Readiness Score: 85/100 — deduction for unverified endpoint and mobile UI.
```

### Bad (false green)
```
7. What Is Verified: Everything works.
8. What Is UNVERIFIED: Nothing.
13. Readiness Score: 100/100
```
