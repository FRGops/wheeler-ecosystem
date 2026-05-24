# Wheeler Brain OS — Ecosystem Graph Design

**Version:** 2.0.0 | **Date:** 2026-05-24

## Neo4j Schema

### Node Types

| Label | Count | Properties |
|---|---|---|
| **Server** | 3 | name, ip, role, cpu, ram, disk, os |
| **ClaudeAgent** | 52 | name, domain, safety, file |
| **Skill** | 20 | name, domain |
| **AgentService** | 9 | name, port, runtime, status, domain |
| **InfraService** | 9 | name, port, runtime, type |
| **Container** | 12 | name, image, port |

### Relationship Types

| Relationship | From | To | Meaning |
|---|---|---|---|
| RUNS_ON | AgentService, InfraService, Container | Server | Deployment location |
| HOSTED_ON | ClaudeAgent | Server | Agent hosting |
| DEPENDS_ON | AgentService | InfraService, AgentService | Runtime dependency |
| ROUTES_THROUGH | AgentService | InfraService (litellm) | LLM routing |
| USES / HAS_SKILL | ClaudeAgent | Skill | Skill association |
| OBSERVES | InfraService (command-center) | AgentService, Container | Monitoring target |
| MONITORS | InfraService (ecosystem-guardian) | AgentService | Health monitoring |

### Key Queries

```cypher
-- Blast radius: what breaks if a server goes down?
MATCH (s:Server {name: 'wheeler-aiops-01'})<-[:RUNS_ON]-(svc)
RETURN labels(svc), svc.name

-- Dependency chain: what does service X need?
MATCH (a:AgentService {name: 'frgcrm-agent-svc'})-[:DEPENDS_ON*1..3]->(dep)
RETURN dep.name, dep.type

-- Agent capability map: who has what skills?
MATCH (a:ClaudeAgent)-[:HAS_SKILL]->(s:Skill)
RETURN a.name, collect(s.name)

-- Health overview
MATCH (svc:AgentService)
RETURN svc.name, svc.status, svc.port
ORDER BY svc.port
```

## Data Freshness

- Agent data refreshed on each `/slay` run
- Container data synced from Docker API
- PM2 data synced from `pm2 jlist`
- Manual refresh via `ecosystem-memory` agent
