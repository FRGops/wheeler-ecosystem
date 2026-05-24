# Wheeler Brain OS — AI Decision Layer

**Version:** 2.0.0 | **Date:** 2026-05-24

## Architecture

52 Claude Code agents organized in 6 tiers, all routing through LiteLLM proxy at `127.0.0.1:4049/v1`.

### Model Routing

| Model | Provider | Rate Limit | Use Case |
|---|---|---|---|
| deepseek-chat | DeepSeek | 1000 RPM | Primary agent execution |
| deepseek-reasoner | DeepSeek | 500 RPM | Complex analysis |
| claude-sonnet-4 | Anthropic | 100 RPM | Code review, quality |
| claude-opus-4 | Anthropic | 50 RPM | Architecture, critical decisions |

### Agent Invocation Pattern

```
User Task → wheeler-brain-core (orchestrator)
  ├── Delegates to domain agent via Agent(subagent_type="agent-name")
  ├── Domain agent queries Neo4j for ecosystem context
  ├── Domain agent returns findings
  └── Orchestrator synthesizes final response
```

### Decision Categories

| Category | Agents | Output |
|---|---|---|
| **Infrastructure** | infra-intelligence, docker-intelligence, pm2-intelligence | Optimization opportunities, resource forecasting |
| **Deployment** | deployment-intelligence, rollback-intelligence | Go/no-go recommendation, risk score |
| **Security** | security-intelligence, wheeler-security-agent | CVE alerts, hardening recommendations |
| **Cost** | cost-intelligence | Spend analysis, savings opportunities |
| **Revenue** | revenue-intelligence | System health impact on revenue |
| **Architecture** | long-term-scaling, autonomous-optimization | Scaling timeline, consolidation plan |

### Safety Enforcement

Every agent has a defined safety model that constrains its actions:
- **READ-ONLY**: Analyze only, never modify
- **ADVISORY**: Recommend with justification, human approval required
- **PREFLIGHT-GATED**: Must pass 7 safety checks before action
- **GOVERNANCE**: Enforces policies on other agents
- **GATEKEEPER**: Can block unsafe operations

No agent can autonomously deploy, modify production configs, or access secrets.
