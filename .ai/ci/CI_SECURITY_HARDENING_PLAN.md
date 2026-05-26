# CI Security Hardening Plan

## Goals
- Validate every PR before merge
- Never deploy from CI
- Never expose secrets in CI logs
- Fail fast on security violations

## Workflow Overview

| Workflow | Trigger | Action |
|----------|---------|--------|
| `ai-quality-gates.yml` | PR, ai/** push | Lint, typecheck, test |
| `codeql-analysis.yml` | PR, main push | CodeQL scan (if compatible) |
| `dependency-review.yml` | PR (package.json changed) | Audit deps for CVEs, licenses |
| `secret-safety.yml` | PR | Scan diff for secret patterns |

## Security Rules for All Workflows

1. **Never deploy**: CI validates, human deploys.
2. **Never run migrations**: DB changes are reviewed but not executed by CI.
3. **No production secrets**: CI uses only `GITHUB_TOKEN` (built-in).
4. **Fail on .env changes**: PRs modifying `.env` files are blocked.
5. **Fail on secrets/ changes**: PRs touching `secrets/` are blocked.
6. **Warn on dependency changes**: Dependency changes without risk report get flagged.

## What CI CAN Do
- Run linters and formatters
- Run type checkers (TypeScript, mypy)
- Run unit and integration tests
- Run CodeQL analysis
- Run dependency audit (npm audit, pip audit)
- Scan diff for secret patterns (regex only, no values printed)
- Check for required files (CLAUDE.md, AGENTS.md, etc.)

## What CI CANNOT Do
- Deploy to any environment
- Access production secrets
- Run database migrations
- Modify infrastructure
- Push to protected branches
- Approve PRs automatically
