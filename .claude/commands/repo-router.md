# /repo-router — Repository Routing Intelligence

Route development requests to the correct repository in the Wheeler ecosystem. Uses embedded repo knowledge and keyword routing to determine the right target(s) and dependency order for any change.

## Execution

### Phase 1: Classify Request

Map the user's natural language request against these routing keywords. Find the closest pattern match:

| Request Keywords | Primary Repo | Node |
|----------------|--------------|------|
| CRM, leads, pipeline, claimants, ATTOM, contact, deal | frgcrm (API + frontend) | AI Ops |
| Frontend UI, dashboard, UX, components, React, Next.js, styling | frgcrm/frontend | AI Ops |
| Revenue, analytics, automation, scoring, outreach, marketplace | wheeler-revenue-automation | AI Ops |
| SurplusAI, surplus, scrapers, auction | frgops-surplusai | Hostinger |
| Prediction, radar, forecasting | prediction-radar-app | Hostinger |
| Fund recovery, public site, marketing, frg-site | frg-site / fundsrecoverygroup | Hostinger |
| AI agents, private AI, LLM, Claude, OpenAI, brain-os | private-ai / wheeler-brain-os | Hostinger |
| Infrastructure, Docker, PM2, networking, deployment, CI/CD | wheeler-ecosystem (capabilities) | AI Ops |
| Monitoring, dashboards, health checks, OpenClaw | openclaw-dashboard | AI Ops |
| Security, secrets, audit, vulnerability | hacker-lab | Hostinger |
| Trading, quant, market data | repos-catalog/trading/ | Hostinger |
| Horizon, agent service | horizon-agent-svc | Hostinger |
| RavynAI, opportunity graph | ravynai-opportunity-graph | Hostinger |
| War room | war-room | Hostinger |
| Codex, knowledge base, documentation | wheeler-codex | Hostinger |
| FRG ecosystem platform, engine portal | frg-ecosystem / engine-01-frontend | Hostinger |

**Cross-cutting detection**: If the request mentions multiple patterns (e.g. "revenue dashboard in CRM"), identify ALL affected repos and order by dependencies. Do not route to just one — list the full dependency chain.

### Phase 2: Verify Local Repos

```bash
# Confirm code exists for local repos
echo "=== AI OPS — LOCAL REPOS ==="
for r in /opt/wheeler/apps/frgcrm /opt/wheeler/apps/frgcrm/frontend /opt/wheeler-revenue-automation /opt/openclaw-dashboard /opt/wheeler-ecosystem; do
  if [ -d "$r" ]; then
    b=$(git -C "$r" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")
    h=$(git -C "$r" rev-parse --short HEAD 2>/dev/null || echo "")
    echo "  $r — $h ($b)" | sed "s|/opt/wheeler/apps/||;s|/opt/||"
  else
    echo "  $r — NOT FOUND"
  fi
done
echo ""
echo "=== HOSTINGER (100.98.163.17) ==="
echo "  Access repos via ssh: ssh hostinger 'ls /opt/apps/'"
echo "=== CORE-DB (100.118.166.117) ==="
echo "  No dev repos — data/backup node only"
```

### Phase 3: Build Routing Output

Using the classified request and ecosystem knowledge below, produce the Output Format with dependency ordering.

## Ecosystem Repo Knowledge

**AI Ops Node (this node — /opt):**
- `frgcrm` — path: `/opt/wheeler/apps/frgcrm` — remote: `FRGops/frgcrm` (main) — Python/Node monorepo (FastAPI backend + Next.js frontend + agents-service). Dependencies: none. Consumers: frgcrm/frontend, wheeler-revenue-automation.
- `frgcrm/frontend` — path: `/opt/wheeler/apps/frgcrm/frontend` — remote: `FRGops/frgops-audits` (main) — Next.js 16 TypeScript, dev on :3300. Dependencies: frgcrm API. Consumers: none.
- `wheeler-revenue-automation` — path: `/opt/wheeler-revenue-automation` — local-only (master) — Python AI workforce (analytics, attorney marketplace, CRM automation, lead intelligence, outreach, risk engine). Dependencies: frgcrm API. Consumers: frgcrm (UI embedding).
- `openclaw-dashboard` — path: `/opt/openclaw-dashboard` — remote: `tugcantopaloglu/openclaw-dashboard` (main) — Node.js monitoring. Dependencies: wheeler-ecosystem. Consumers: none.
- `wheeler-ecosystem` — path: `/opt/wheeler-ecosystem` — local — Capabilities layer: skills, hooks, safety gates, install, slash commands. Dependencies: none. Consumers: all repos (deployment/infra).

**Hostinger Node (100.98.163.17) — Production:**
- `fundsrecoverygroup` — /opt/apps/fundsrecoverygroup — FRGops/fundsrecoverygroup (main) — Node.js
- `frg-site` — /opt/apps/frg-site — FRGops/frg-site (master) — Node.js, SSH remote
- `frgcrm-prod` — /opt/apps/frgcrm — FRGops/frgcrm (main) — Node.js production CRM
- `frgops-surplusai` — /opt/apps/frgops-surplusai — FRGops/frgops-surplusai (fix/remove-hardcoded-db-credentials) — Python
- `horizon-agent-svc` — /opt/apps/horizon-agent-svc — FRGops/horizon-agent-svc (master) — Node.js, SSH
- `prediction-radar-app` — /opt/apps/prediction-radar-app — FRGops/prediction-radar-app (main) — Docker, SSH
- `private-ai` — /opt/apps/private-ai — FRGops/private-ai (main) — Python/Docker
- `ravynai-opportunity-graph` — /opt/apps/ravynai-opportunity-graph — FRGops/ravynai-opportunity-graph (master) — Node/Docker, SSH
- `war-room` — /opt/apps/war-room — FRGops/war-room (master) — SSH
- `wheeler-brain-os` — /opt/apps/wheeler-brain-os — FRGops/wheeler-brain-os (main) — Node.js, SSH
- `frg-ecosystem` — /opt/frg-ecosystem — FRGops/frg-ecosystem (main) — Node.js
- `engine-01-frontend` — /opt/frg-ecosystem/engine-01-frontend — FRGops/engine-01-frontend (main) — Node.js
- `wheeler-codex` — /root/wheeler-codex — FRGops/wheeler-codex (main) — Node.js
- `hacker-lab` — Security/audit tools
- `trading/` — /opt/repos-catalog/trading/ — Quant/trading repos

**Core-DB Node (100.118.166.117):** No development repos. Data/backup only (PostgreSQL, Redis, MinIO, Temporal).

## Dependency Ordering

Order affected repos by this sequence:
1. **Data/schema layer first** — model changes before anything consuming them
2. **API/backend second** — deploy endpoints before consumers integrate
3. **Frontend/UI last** — final consumer of all backend changes
4. **Infra/DevOps in parallel** — Docker, PM2, configs are independent

**Common cross-repo chains:**
- Revenue dashboard in CRM: wheeler-revenue-automation (analytics endpoints) → frgcrm API (gateway) → frgcrm/frontend (dashboard UI)
- New SurplusAI scraper: frgops-surplusai (scraper) → frgcrm (data model on AI Ops) → frgcrm-prod (deploy to Hostinger)
- New AI agent: private-ai (LLM infra) → wheeler-brain-os (orchestration) → frgcrm (integration)
- Infra change: wheeler-ecosystem (capabilities) → openclaw-dashboard (monitoring)

## Output Format

```
REQUEST: <user's description>
ROUTED TO: <primary repo path>
NODE: <AI Ops / Hostinger / Core-DB>
──────────────────────────────────────
STACK:         <language/framework>
REPO TYPE:     <frontend/backend/fullstack/infra/research>
DEPENDENCIES:  <what this repo depends on>
CONSUMERS:     <what depends on this>
AFFECTED:      <all repos needing changes, dependency-ordered>
──────────────────────────────────────
RECOMMENDED ORDER:
  1. <repo-A> — <why first>
  2. <repo-B> — <why second (depends on A)>
  3. <repo-C> — <why third>
```
