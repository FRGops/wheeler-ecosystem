# Wheeler Brain OS — Ecosystem Command Layer Architecture

**Version:** 2.0.0
**Date:** 2026-05-24 20:59 UTC
**Status:** DEPLOYED — 98.5/100 Operational
**Operator:** Wheeler AIOps Control Plane

---

## Executive Summary

Wheeler Brain OS is the centralized intelligence + command layer for the Wheeler ecosystem. Unified visibility across 3 servers, 42 Docker containers, 20 PM2 processes, 52 AI agents, and 20 skills.

**Architecture:** Two-tier intelligence — real-time (Command Center API :8100) + graph-knowledge (Neo4j Ecosystem Graph :7474). 52 specialized Claude Code agents form the decision layer.

---

## 1. SYSTEM ARCHITECTURE

```
┌─────────────────────────────────────────────────────────────────┐
│              NGINX GATEWAY (100.121.230.28:443)                 │
│   command.aiops │ clickhouse.aiops │ usesend.aiops │ default   │
│   basic_auth + rate_limiting + security_headers                  │
└───────────────────────────┬─────────────────────────────────────┘
                            │
    ┌───────────────────────┼───────────────────────────┐
    │                       │                           │
    ▼                       ▼                           ▼
┌───────────┐    ┌──────────────────┐    ┌──────────────────────┐
│ COMMAND   │    │  ECOSYSTEM-GRAPH │    │   PM2 AGENT FLEET    │
│ CENTER    │    │  (Neo4j:7474)    │    │   (19 daemons)       │
│ :8100     │    │  105 nodes       │    │   Ports 8003-8110    │
│ FastAPI   │    │  261 relationships│    │   Node.js + Python   │
└─────┬─────┘    └────────┬─────────┘    └──────────┬───────────┘
      │                   │                         │
      └───────────────────┼─────────────────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
              ▼                       ▼
    ┌──────────────────┐    ┌──────────────────┐
    │  CLAUDE CODE     │    │   OBSERVABILITY  │
    │  AGENT ARMY (52) │    │   STACK          │
    │  /root/.claude/  │    │   Prometheus     │
    │  agents/         │    │   Grafana        │
    └──────────────────┘    │   Loki           │
                            │   Uptime Kuma    │
                            │   Netdata        │
                            └──────────────────┘
```

### Server Inventory

| Server | Role | Specs |
|---|---|---|
| **wheeler-aiops-01** | App + AI Host | AMD EPYC, 30GB RAM, 338GB SSD |
| **wheeler-coredb-01** | Core DB | AMD EPYC, 16GB RAM, 160GB SSD |
| **hostinger-vps** | Legacy | Intel Xeon, 8GB RAM, 100GB SSD |

### Key Services

| Port | Service | Access |
|---|---|---|
| 8100 | Command Center API | basic_auth |
| 7474 | Neo4j Browser | localhost |
| 7687 | Neo4j Bolt | localhost |
| 4049 | LiteLLM Proxy | localhost |
| 3000 | Open WebUI | localhost |
| 7860 | Langflow | localhost |
| 8123 | ClickHouse | localhost + basic_auth |
| 8088 | Superset | localhost |
| 9090 | Prometheus | localhost |
| 3100 | Loki | localhost |
| 7233 | Temporal | localhost |

---

## 2. AGENT ARMY (52 DEPLOYED)

### Tier 1: Core Brain (8 agents)
wheeler-brain-core, ecosystem-memory, infra-intelligence, repo-intelligence, deployment-intelligence, ai-routing, agent-coordination, executive-dashboard

### Tier 2: Business Intelligence (5 agents)
revenue-intelligence, cost-intelligence, monitoring-intelligence, alert-correlation, drift-detection

### Tier 3: Infrastructure Intelligence (9 agents)
infra-graph, ecosystem-relationship-mapper, tailscale-mesh, gateway-intelligence, aiops-integration, pm2-intelligence, docker-intelligence, github-intelligence, observability-intelligence

### Tier 4: Security & Response (7 agents)
incident-response-agent, rollback-intelligence, no-false-greens-qa, autonomous-docs, multi-server-coordination, oss-intelligence, mcp-intelligence

### Tier 5: Executive & Strategy (8 agents)
wheeler-brain-dashboard, executive-workflow, ceo-command-console, ecosystem-health-scoring, production-readiness-agent, operational-forecasting, automation-recommendation, security-intelligence

### Tier 6: Governance & Optimization (3 agents)
ai-ecosystem-governance, long-term-scaling, autonomous-optimization

### Original Specialized Agents (12)
wheeler-db-agent, wheeler-deploy-agent, wheeler-infra-agent, wheeler-security-agent, wheeler-mac-agent, wheeler-worker-agent, engineering-sre, engineering-code-reviewer, docker-expert, devops-smoke-tester, database-rls-auditor, zero-false-green-auditor

---

## 3. SKILL FLEET (20)

slay, pm2-recovery, secrets-scan, docker-health, database-lockdown, deploy-safety, rollback-first, incident-response, cost-control, production-readiness, no-false-greens, superpowers, aiops-control-plane-operator, hostinger-production-operator, worker-routing-operator, agent-workflow-builder, mac-command-center-operator, private-network-check, open-source-repo-evaluator, repo-audit

---

## 4. HEALTH METRICS

| Metric | Value |
|---|---|
| Docker Containers | 42/42 healthy (100%) |
| PM2 Processes | 19 daemons + 1 cron job |
| Neo4j Nodes | 105 |
| Neo4j Relationships | 261 |
| Memory | 15.9GB / 31.3GB (50.6%) |
| Disk | 61GB / 338GB (19%) |
| Claude Agents | 52 deployed |
| Skills | 20 deployed |
| Nginx Routes | 4 active |
| UFW Rules | 26 |
| **Ecosystem Score** | **98.5/100** |

---

## 5. SAFETY ARCHITECTURE

Every agent has a defined safety model: READ-ONLY, ADVISORY, PREFLIGHT-GATED, COORDINATED, GOVERNANCE, or GATEKEEPER. No agent has unrestricted autonomous execution capability.
