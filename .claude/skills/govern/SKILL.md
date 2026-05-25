---
name: govern
description: Wheeler Execution Governance — automated enforcement of repo, deployment, agent, infrastructure, automation, product, and operational policies. Zero-trust by default, rollback-first, audit everything.
metadata:
  type: skill
  version: "1.0.0"
  author: Wheeler Brain OS
  tags:
    - governance
    - compliance
    - security
    - audit
---

# Execution Governance

Automated governance enforcement for the Wheeler ecosystem. Full framework at `/root/EXECUTION_GOVERNANCE_FRAMEWORK.md`.

## Subcommands

### `/govern check`
Run all governance checks across all 8 domains.

**Checks performed:**
1. Repo governance — standard structure, branch protection, security scanning
2. Deployment governance — 7-gate pipeline compliance, rollback readiness
3. Agent governance — registration status, capability boundaries, cost tracking
4. Infrastructure governance — port allocation, image policy, resource limits, network exposure
5. Automation governance — registry compliance, human-in-the-loop for P1, kill switches
6. Product governance — launch gates, Stripe live mode, SSL, monitoring
7. Operational governance — change management, incident response, SLAs
8. Enforcement — violation detection and escalation

### `/govern audit <domain>`
Deep audit of a specific governance domain.

**Domains:** repos, deploys, agents, infra, automation, products, operations

### `/govern enforce`
Enforce governance rules — block violators.

**Enforcement layers:**
1. Automated checks (per-deploy, per-commit)
2. Agent-based verification (daily scans)
3. Manual review (weekly audit)

**Consequences:**
- Warn — first violation, documented
- Block deploy — deploy governance violation
- Block agent — agent governance violation
- Revoke access — repeated or severe violation

### `/govern report`
Generate governance compliance report.

**Output:** Per-domain compliance %, violation count, aging violations, risk assessment.

### `/govern bypass <reason>`
Emergency governance bypass (logged, auto-expires 24h).

**Valid reasons:** Security fix, outage recovery, data loss prevention.
**Invalid reasons:** Convenience, speed, "I know what I'm doing."

## Key Governance Rules

### Repo Governance
- Prefer adding to existing repos over creating new ones
- Standard structure: README.md, .env.example, deploy config, health check
- Branch protection on main/develop
- Code review required: 1 approver (low risk), 2 approvers (high risk)
- Abandoned: 90 days no commits → archive

### Deployment Governance (7 Gates)
1. State Capture — snapshot current state
2. Health Check Green — all health checks passing
3. Resource Headroom — CPU/RAM/Disk sufficient
4. Config Valid — syntax check, env vars present
5. Secret Hygiene — no secrets in code, no hardcoded keys
6. Rollback Path Verified — documented and tested rollback procedure
7. Governance Compliance — all governance checks pass

### Agent Governance
- Agent creation requires: spec → safety model → approval
- 6 safety models with explicit permitted/prohibited actions
- Registration: PM2 config + .claude/agents/ + Neo4j registry
- Retirement: 30d flag → 60d warn → 90d archive
- No uncontrolled agent spawning

### Infrastructure Governance
- No :latest Docker tags — must pin SHA
- 127.0.0.1 by default — only SSH/Nginx on 0.0.0.0
- Every container must have memory/CPU limits
- Disk thresholds: 80% warn, 90% critical, 95% emergency
- New infrastructure requires decommission plan for old

### Network Exposure Policy
- All services bind 127.0.0.1 by default
- Only Nginx reverse proxy on Tailscale IP
- Only SSH on public interface
- No direct container port exposure to internet
