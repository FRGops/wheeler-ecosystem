---
name: repo-audit
description: "Audit any repository for structure, dependencies, security, code quality, test coverage, and documentation. Produces a scored report card."
trigger: repo audit, audit repo, repository audit, code audit, project audit, audit codebase, repo health
---

# Skill: Repository Audit

Comprehensive repository audit producing a scored report card across 6 dimensions.

## Audit Dimensions

### 1. Structure (score /10)
- Clear directory layout (src, tests, docs, config)
- Consistent naming conventions
- Monorepo vs polyrepo appropriateness
- Config file organization

### 2. Dependencies (score /10)
- Up-to-date packages (no critical CVEs)
- Minimal dependency bloat
- Lock files present and committed
- Internal dependency graph understood

### 3. Security (score /20)
- No secrets in code or git history
- No hardcoded credentials
- Authentication/authorization properly implemented
- Input validation present
- OWASP top 10 addressed

### 4. Code Quality (score /20)
- Consistent code style (linting configured)
- Type safety (TypeScript, Python type hints)
- Error handling present
- No obvious anti-patterns
- Complexity under control

### 5. Testing (score /20)
- Test framework configured
- Unit tests present and passing
- Integration tests where appropriate
- Coverage ≥ 60% (or documented reason)
- CI runs tests automatically

### 6. Documentation (score /10)
- README with setup instructions
- API documentation if applicable
- Architecture decision records
- Runbook for operations
- Contributing guide

## Execution

Run Wheeler ecosystem scans:
```bash
# Secrets scan
bash /opt/wheeler-ecosystem/security/secret-scan.sh

# Dependency audit
npm audit 2>/dev/null || pip audit 2>/dev/null || echo "No package audit available"

# Test suite
npm test 2>/dev/null || pytest 2>/dev/null || echo "No test suite found"

# Coverage
# (framework-specific)
```

## Output Format

```
╔══════════════════════════════════════════════╗
║   Repository Audit — <repo-name>             ║
╚══════════════════════════════════════════════╝

STRUCTURE:     <score>/10 [PASS/FAIL]
DEPENDENCIES:  <score>/10 [PASS/FAIL]
SECURITY:      <score>/20 [PASS/FAIL]
CODE QUALITY:  <score>/20 [PASS/FAIL]
TESTING:       <score>/20 [PASS/FAIL]
DOCUMENTATION: <score>/10 [PASS/FAIL]
──────────────────────────────────────────────
TOTAL: <N>/90 (<pct>%)
GRADE: [A/B/C/D/F]
──────────────────────────────────────────────
CRITICAL ISSUES:
  <list items that must be fixed immediately>
RECOMMENDATIONS:
  <list suggested improvements>
```
