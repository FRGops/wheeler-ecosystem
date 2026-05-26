# Dynamic Capability Matcher — Fully Automated Discovery

## How It Works

The intelligence hook doesn't hardcode agent names. Instead, it uses **keyword-to-domain matching**. When a prompt contains keywords matching a domain, the hook recommends deploying agents from that domain. The model knows which specific agents exist and maps the domain recommendation to actual agent names.

**New agents auto-participate** because they share domain keywords with their category. Install a new security agent, and it automatically matches security-related prompts.

## Capability Domains → Trigger Keywords

### Implementation Domains

| Domain | Trigger Keywords | Agent Types to Use |
|--------|-----------------|-------------------|
| `backend-api` | api, endpoint, rest, graphql, route, controller, middleware, fastapi, express, django | general-purpose, feature-dev:code-architect |
| `frontend-ui` | ui, component, react, vue, angular, css, tailwind, layout, button, form, modal, page | general-purpose, frontend-design, feature-dev:code-architect |
| `database` | database, sql, postgres, prisma, schema, migration, query, index, table, column | general-purpose, wheeler-db-agent, database-rls-auditor |
| `devops` | docker, container, compose, kubernetes, deploy, ci/cd, pipeline, build | general-purpose, docker-expert, wheeler-deploy-agent |
| `cli-tool` | cli, script, bash, shell, command, tool, utility | general-purpose |
| `config` | config, settings, env, environment, variable, hook, permission | general-purpose, update-config |

### Quality Domains

| Domain | Trigger Keywords | Agent Types to Use |
|--------|-----------------|-------------------|
| `testing` | test, spec, jest, pytest, coverage, mock, stub, assert, e2e, integration | code-modernization:test-engineer, general-purpose |
| `security` | security, secret, token, auth, vulnerability, owasp, cve, ssl, tls, injection, xss | code-modernization:security-auditor, wheeler-security-agent, secrets-scan |
| `review` | review, audit, check, quality, lint, code quality | Code Reviewer, code-simplifier, pr-review-toolkit:* |
| `performance` | performance, optimize, slow, fast, memory, cpu, latency, cache | general-purpose, infrastructure-optimization |
| `observability` | log, monitor, alert, metric, dashboard, health, check, prometheus, grafana | observability-intelligence, monitoring-intelligence |

### Architecture Domains

| Domain | Trigger Keywords | Agent Types to Use |
|--------|-----------------|-------------------|
| `architecture` | architecture, design, pattern, structure, system, refactor, module | Plan, feature-dev:code-architect, code-modernization:architecture-critic |
| `legacy` | legacy, old, cobol, migrate, modernize, rewrite | code-modernization:legacy-analyst, code-modernization:business-rules-extractor |
| `documentation` | docs, document, readme, comment, docstring, wiki | autonomous-docs, general-purpose |

### Wheeler Ecosystem Domains

| Domain | Trigger Keywords | Agent Types to Use |
|--------|-----------------|-------------------|
| `pm2` | pm2, process, restart, crashed, jlist, daemon | pm2-intelligence, wheeler-infra-agent, /slay |
| `docker-health` | docker, container, health, image, port | docker-intelligence, docker-health, docker-expert |
| `ecosystem-health` | health, score, ecosystem, readiness, scorecard | ecosystem-health-scoring, /slay, no-false-greens |
| `deploy` | deploy, release, ship, production, rollback | wheeler-deploy-agent, deployment-intelligence, rollback-intelligence |
| `infra` | infrastructure, server, network, ufw, nginx, proxy, gateway | wheeler-infra-agent, gateway-intelligence, infra-intelligence |
| `financial` | revenue, cost, mrr, arr, stripe, billing, invoice, payment | revenue-intelligence, stripe-revenue, cost-intelligence |
| `github` | github, pr, pull request, issue, commit, push, repo | github-intelligence, commit-commands:* |
| `multi-agent` | agent, orchestrate, coordinate, fleet, army, parallel | agent-coordination, autonomous-execution-engine |

### AI/LLM Domains

| Domain | Trigger Keywords | Agent Types to Use |
|--------|-----------------|-------------------|
| `ai-routing` | llm, model, routing, deepseek, claude, openai, token, cost | ai-routing, ai-token-cost |
| `rag` | rag, embedding, vector, pgvector, qdrant, semantic, search | rag-architecture, embedding-pipeline, vector-database |
| `agent-sdk` | sdk, agent sdk, anthropic, claude api | agent-sdk-dev:agent-sdk-verifier-ts, agent-sdk-dev:agent-sdk-verifier-py |

## How New Capabilities Auto-Discover

### Adding a New Agent (zero config needed)
1. Agent is installed/created (via plugin or manual)
2. Agent's name/description contains domain keywords (e.g., "security-auditor" matches `security`)
3. Next prompt with matching keywords → agent is recommended
4. **No changes needed to any file**

### Adding a New Skill (zero config needed)
1. Skill is installed
2. Skill name matches domain keywords (e.g., "docker-health" matches `docker`)
3. Next prompt with matching keywords → skill is recommended

### Adding a New Plugin (zero config needed)
1. Plugin is enabled in settings.json
2. Plugin's agents/skills auto-match via keywords

### Adding a New Domain (one-line addition)
1. Add a row to the domain table above
2. New domain is instantly active for all future prompts

## Self-Updating

The `capability-scanner.sh` script runs at SessionStart and:
1. Reads the current domain table
2. Checks for newly available agents/skills that match existing domains
3. Reports any unmatched capabilities (potential new domains to add)
4. Outputs: "N capabilities auto-matched, M unmatched — consider adding domains for: [...]"

This ensures the system never misses new capabilities without requiring manual configuration.
