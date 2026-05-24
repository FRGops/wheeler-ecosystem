# Wheeler Brain OS

## Ecosystem Command & Intelligence Layer

```
WHEELER BRAIN OS
──────────────────────────────────────────────────
Jarvis + Palantir + Bloomberg Terminal + AI COO
──────────────────────────────────────────────────
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                 CEO COMMAND CONSOLE                      │
│         One pane of glass for everything                 │
├─────────────────────────────────────────────────────────┤
│              AI DECISION LAYER                           │
│     Recommendations · Drift Detection · Forecasting     │
├─────────────────────────────────────────────────────────┤
│            ECOSYSTEM CONTROL PLANE                       │
│     Docker · PM2 · Deployments · Rollbacks · Routing    │
├─────────────────────────────────────────────────────────┤
│          OBSERVABILITY FUSION LAYER                      │
│     Grafana · Prometheus · Loki · Uptime Kuma · PM2     │
├─────────────────────────────────────────────────────────┤
│           ECOSYSTEM MEMORY GRAPH                         │
│     Servers · Services · Repos · Agents · Relationships │
├─────────────────────────────────────────────────────────┤
│           GOVERNANCE & ENFORCEMENT                       │
│     Security · Resources · Secrets · Exposure · QA      │
└─────────────────────────────────────────────────────────┘
```

## Directory Structure

```
WHEELER_BRAIN_OS/
├── README.md                          ← This file
├── architecture/                      ← System design documents
│   ├── WHEELER_BRAIN_OS_ARCHITECTURE.md
│   ├── ECOSYSTEM_GRAPH_DESIGN.md
│   ├── CONTROL_PLANE_ARCHITECTURE.md
│   └── AI_DECISION_LAYER.md
├── agents/                            ← Agent fleet specifications
├── dashboards/                        ← Dashboard configurations
├── control-plane/                     ← Orchestration layer
├── memory/                            ← Ecosystem memory graph
│   ├── servers.json
│   ├── services.json
│   ├── agents.json
│   └── relationships.json
├── observability/                     ← Monitoring fusion specs
├── governance/                        ← Policy & enforcement
├── automation/                        ← Self-healing recipes
└── reports/                           ← Intelligence reports
    ├── 01_infrastructure_map.md
    ├── 02_repo_intelligence.md
    ├── 03_agent_fleet_intelligence.md
    └── 04_business_systems_intelligence.md
```

## Servers

| Server | Tailscale IP | Role | Containers |
|--------|-------------|------|------------|
| AIOPS | 100.121.230.28 | Primary app server | 40 Docker + 17 PM2 |
| COREDB | 100.118.166.117 | Database & core services | 18 Docker |

## Quick Health

Run `/slay` for full ecosystem health audit.
