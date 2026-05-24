---
name: open-source-repo-evaluator
description: "Evaluate any GitHub repo: code quality, maintenance status, community health, security posture, license compliance, dependency freshness. Produces adoption recommendation (adopt/caution/avoid)."
trigger: evaluate repo, repo evaluation, check repo, repo quality, should I use, github audit, repo review, open source check
---

# Skill: Open Source Repository Evaluator

Evaluate any open-source repository for production suitability. Produces a scored recommendation: Adopt / Caution / Avoid.

## Evaluation Dimensions

### 1. Maintenance Health (score /25)
- Last commit date: < 1 month (10pts), < 6 months (5pts), > 1 year (0pts)
- Release frequency: regular cadence (10pts), sporadic (5pts), abandoned (0pts)
- Response to issues: median time to first response

### 2. Community Health (score /20)
- Contributors: > 10 active (10pts), 3-10 (5pts), < 3 (0pts)
- Stars/forks ratio
- Issue resolution rate: > 70% (10pts), 40-70% (5pts), < 40% (0pts)
- Healthy discussion in issues/PRs

### 3. Code Quality (score /20)
- Tests present and passing
- CI/CD configured
- Linting/formatting enforced
- Type safety
- Documentation quality

### 4. Security Posture (score /20)
- No critical CVEs in dependencies
- Security policy present (SECURITY.md)
- Dependabot/Renovate configured
- No secrets in repo
- Supply chain: signed commits, provenance

### 5. License & Compliance (score /15)
- Clear OSI-approved license
- License compatible with your stack
- Dependency licenses audited
- No restrictive clauses

## Quick Checks (run in parallel)

```bash
# Clone and quick-audit
REPO=<repo-url>
gh repo view "$REPO" --json name,description,licenseInfo,createdAt,updatedAt,stargazerCount,forkCount,openIssues,watchers
gh api "repos/$REPO/commits?per_page=5" --jq '.[0].commit.author.date'
gh api "repos/$REPO/releases?per_page=5" --jq '.[].tag_name'
gh api "repos/$REPO/issues?state=open&per_page=5" --jq '.[].title'
```

## Scoring

| Total Score | Recommendation |
|-------------|---------------|
| 80-100 | **ADOPT** — Production-ready, well-maintained |
| 60-79 | **CAUTION** — Usable but monitor, may need patches |
| 40-59 | **RISKY** — Significant gaps, heavy lifting required |
| < 40 | **AVOID** — Abandoned, insecure, or poorly built |

## Output Format

```
REPO EVALUATION: <org/repo>
──────────────────────────────────────
URL: <github-url>
DESCRIPTION: <description>

MAINTENANCE:   <score>/25 [ADOPT/CAUTION/AVOID]
COMMUNITY:     <score>/20 [ADOPT/CAUTION/AVOID]
CODE QUALITY:  <score>/20 [ADOPT/CAUTION/AVOID]
SECURITY:      <score>/20 [ADOPT/CAUTION/AVOID]
LICENSE:       <score>/15 [ADOPT/CAUTION/AVOID]
──────────────────────────────────────
TOTAL: <N>/100

RECOMMENDATION: [ADOPT / CAUTION / RISKY / AVOID]
KEY CONCERNS: <list or "none">
```
