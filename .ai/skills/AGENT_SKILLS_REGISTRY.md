# Agent Skills Registry

## Core Skills

### Coding
- **implementation**: Write production code (DeepSeek)
- **debugging**: Diagnose and fix bugs (DeepSeek Reasoner)
- **refactoring**: Safe structural changes (DeepSeek + review)
- **testing**: Write and run tests (Test QA Agent)

### Architecture
- **system-design**: Architecture planning (Claude Code)
- **code-review**: Review diffs for quality and safety (Final Boss)
- **dependency-audit**: Review dependency changes (Dependency Risk Agent)

### DevOps Safety
- **deploy-review**: Pre-deploy safety check (DevOps Safety Agent)
- **rollback-planning**: Create rollback procedures (DevOps Safety Agent)
- **secret-scanning**: Pattern-based secret detection (Security Secrets Agent)

### Repo Governance
- **repo-audit**: Full repository health check
- **compliance-check**: Verify policies are followed
- **memory-update**: Update .ai/memory/ with session learnings

### Quality
- **no-false-green**: Verify all health claims against evidence
- **final-boss-review**: Ultimate quality gate before merge
- **gate-runner**: Execute quality gate scripts

### UI/UX
- **ui-review**: Review UI for quality and consistency
- **accessibility-audit**: WCAG compliance check
- **performance-audit**: Speed and resource optimization

### Security
- **security-review**: OWASP Top 10 audit
- **cve-check**: Vulnerability database lookup
- **secret-scan**: Pattern-based secret detection (never prints values)

### Documentation
- **docs-generate**: Auto-generate documentation from code
- **runbook-create**: Create operational runbooks
- **index-update**: Update .ai/INDEX.md

## Skill Creation Template

See `SKILL_CREATION_TEMPLATE.md` for the standardized format.

## Skill Quality Standards

Every skill must:
1. Have a clear mission statement
2. Define allowed and forbidden actions
3. Include DeepSeek protection reminder
4. Include no-false-green reminder
5. Define escalation conditions
6. Specify report format
