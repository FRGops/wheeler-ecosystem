# Readiness Score Schema

## Scoring Dimensions (each 0-10)

| Dimension | Weight | What It Measures |
|-----------|--------|-----------------|
| DeepSeek Protection | 10 | Model routing intact, env vars present, no unauthorized changes |
| Always-On Activation | 10 | CLAUDE.md/AGENTS.md wired, auto-bootstrap, session hooks |
| Model Routing | 10 | Decision matrix present, escalation policy, tool assignments |
| Subagent Templates | 10 | Agent templates complete, deployment matrix, roles defined |
| Preflight/Postflight | 10 | Scripts exist, checklists complete, session tracking |
| Hooks | 10 | SessionStart/Stop, PreToolUse safety, PostToolUse logging |
| CI/Security Templates | 10 | Quality gates workflow, secret scanning, dependency review |
| Quality Gates/No-False-Green | 10 | Gate scripts, no-false-green verifier, evidence requirements |
| Observability/Evals | 10 | Telemetry schema, eval rubrics, session summaries |
| Docs/Runbooks/Index | 10 | Runbooks, rollback docs, index, cheatsheet, manual |

## Total: 100 points

## Score Interpretation

| Score | Rating | Meaning |
|-------|--------|---------|
| 95-100 | A+ | Production-grade autonomous coding OS |
| 85-94 | A | Strong, minor gaps |
| 70-84 | B | Functional, needs hardening |
| 50-69 | C | Basic, significant gaps |
| < 50 | D | Not ready for autonomous use |

## Rules

- Never score 100 unless ALL validations pass
- Never round up — 94 is A, not A+
- Document every dimension's score with evidence
- Label unverified dimensions as UNVERIFIED (score 0)
