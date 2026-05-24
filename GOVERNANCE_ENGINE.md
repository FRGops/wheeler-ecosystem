# Wheeler Brain OS — Governance Engine

**Version:** 2.0.0 | **Date:** 2026-05-24

## Governance Domains

### 1. Deployment Governance
- **Gate:** deploy-safety skill enforces 7 pre-flight checks
- **Enforcer:** deployment-intelligence agent
- **Rule:** No deploy without verified rollback path
- **Rule:** No deploy to unhealthy targets
- **Rule:** No deploy during incident response

### 2. Exposure Governance
- **Gate:** All Docker binds must be 127.0.0.1
- **Enforcer:** docker-intelligence agent + docker-health skill
- **Rule:** No public port exposure without nginx auth
- **Rule:** No admin panels on public internet

### 3. Infrastructure Governance
- **Gate:** Configuration must match known-good baselines
- **Enforcer:** drift-detection agent
- **Rule:** No unauthorized UFW rule changes
- **Rule:** No unauthorized nginx route changes
- **Rule:** No unauthorized PM2 config changes

### 4. Resource Governance
- **Gate:** Resource limits enforced per process
- **Enforcer:** infra-intelligence agent
- **Rule:** PM2 processes capped at 500MB
- **Rule:** Disk usage alerts at 80%
- **Rule:** Memory pressure alerts at 85%

### 5. Cost Governance
- **Gate:** Monthly budget thresholds
- **Enforcer:** cost-intelligence agent
- **Rule:** API spend tracked per model
- **Rule:** Idle resources flagged weekly
- **Rule:** Server right-sizing reviewed monthly

### 6. AI Governance
- **Gate:** Safety model enforcement
- **Enforcer:** ai-ecosystem-governance agent
- **Rule:** No agent has unrestricted autonomous execution
- **Rule:** All agent actions logged and auditable
- **Rule:** Secrets never pass through agent context

### 7. Rollback Governance
- **Gate:** Backup freshness verification
- **Enforcer:** rollback-intelligence agent
- **Rule:** Backups verified before every deployment
- **Rule:** Rollback plan documented for every service
- **Rule:** Restore tested monthly

## Enforcement Architecture

```
Policy Definition (this document)
        │
        ▼
Governance Agents (continuous monitoring)
        │
        ├── Pass → log + report
        │
        └── Violation → alert + block
                │
                ▼
        Incident Response (if critical)
```

## Audit Trail

All governance decisions logged to:
- PM2 logs for process-level events
- Neo4j for relationship changes
- Loki for operational events
- Command Center for health score history
