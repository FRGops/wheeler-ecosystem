# Wheeler Ecosystem — Cross-Server Load Balance Audit
## 2026-05-28 | AIOPS (100.121.230.28) as Build Server

---

## EXECUTIVE SUMMARY: EXTREME IMBALANCE — "1-Server Madness" Confirmed

AIOPS carries **200 workloads** (136 PM2 + 64 Docker). COREDB carries **23 workloads** (0 PM2 + 23 Docker). That's **8.7:1 ratio** on identical hardware (16-core, 30GB RAM each). AIOPS is actively swapping 7.4GB; COREDB sits at 13% RAM utilization. This is a single-server concentration risk that violates the 3-server balanced architecture.

---

## 1. WORKLOAD DISTRIBUTION

| Server | Role | PM2 Processes | Docker Containers | Total Workloads | % of Fleet |
|--------|------|:------------:|:-----------------:|:---------------:|:----------:|
| **AIOPS** (100.121.230.28) | Brain & Orchestrator | **136** (134 online, 2 down) | **64** | **200** | **78.4%** |
| **COREDB** (100.118.166.117) | Database & Pipelines | **0** | **23** | **23** | **9.0%** |
| **Hostinger** (100.98.163.17) | Production API Gateway | **18** (18 online) | **14** | **32** | **12.5%** |
| **TOTAL** | | **154** | **101** | **255** | **100%** |

## 2. RESOURCE PRESSURE PER SERVER

| Server | CPU Cores | RAM Total | RAM Used | RAM Free | Load Avg | Swap Used | Status |
|--------|:---------:|:---------:|:--------:|:--------:|:--------:|:---------:|--------|
| AIOPS | 16 | 30 GiB | **22 GiB (73%)** | 2.9 GiB | **9.48** | **7.4 GiB** | CRITICAL |
| COREDB | 16 | 30 GiB | 3.8 GiB (13%) | 25 GiB | 0.80 | 0 | IDLE |
| Hostinger | 8 | 31 GiB | 6.4 GiB (21%) | 23 GiB | 1.61 | minimal | COMFORTABLE |

**AIOPS has 7.4GB of active swap across two swapfiles. This is the #1 performance risk in the ecosystem.**

## 3. AIOPS: WHAT'S EATING THE RAM?

### Top Memory Consumers (Process Level)
| Process | RAM | % of System |
|---------|-----|:-----------:|
| Java (Neo4j ecosystem-graph) | 1.1 GiB | 3.7% |
| Uvicorn API server | 900 MiB | 3.0% |
| embedding-service (Python) | 852 MiB | 2.7% |
| ClickHouse server | 510 MiB | 1.7% |
| 4× Claude CLI instances | ~380 MiB each (1.5 GiB total) | 5.0% |
| LiteLLM proxy | 320 MiB | 1.0% |
| Docker daemon | 270 MiB | 0.9% |
| Playwright driver | 240 MiB | 0.8% |
| FRGCRM (2 workers) | 240 MiB each | 1.6% |
| 62× PM2 AI agents | ~85 MiB each (~5.2 GiB collective) | 17.3% |

### Top Docker Memory Consumers
| Container | RAM | % of Limit |
|-----------|-----|:----------:|
| prediction-radar-app-api | 970 MiB | **96% of 1 GiB limit** |
| wheeler-metabase | 706 MiB | unlimited |
| crawl4ai-crawl4ai-1 | 669 MiB | 17% of 4 GiB |
| aiops-clickhouse | 643 MiB | 16% of 4 GiB |
| ecosystem-graph (Neo4j) | 457 MiB | 46% of 1 GiB |
| temporal-server | 390 MiB | 20% of 2 GiB |
| wheeler-novu-api | 304 MiB | unlimited |
| aiops-loki | 250 MiB | 49% of 512 MiB |

## 4. TRIPLE-DUPLICATED SERVICES (Wasteful)

These services run on ALL THREE servers simultaneously:

| Service | AIOPS | COREDB | Hostinger | Annual Waste |
|---------|:-----:|:------:|:---------:|:------------:|
| **temporal-server** | 390 MiB | 442 MiB | 87 MiB | ~900 MiB RAM |
| **temporal-ui** | :8089 | :8080 | :8080 | 3 copies |
| **promtail** (log shipper) | 37% CPU spike | ✓ | ✓ | CPU waste |
| **pushgateway** | :9092 | :9092 | :9092 | 3 copies |
| **cadvisor** | :9099 | :8080 (privileged) | :9099 | 3 copies |

## 5. DUPLICATE PM2 SERVICES (AIOPS ↔ Hostinger)

| Service | AIOPS | Hostinger |
|---------|:-----:|:---------:|
| surplusai-parser | ✓ | surplusai-parser-svc |
| surplusai-scoring | ✓ | surplusai-scoring-svc |
| surplusai-crm-sync | ✓ | surplusai-crm-sync |
| frgcrm-api | 235 MiB | 320 MiB |
| repowire-daemon | ✓ | ✓ |
| proxy-broker | ✓ | ✓ |

## 6. UNHEALTHY PROCESSES (Need Immediate Fix)

| Process | Server | Status | Action |
|---------|--------|--------|--------|
| command-center | AIOPS | waiting restart | delete+start recovery |
| pnl-dashboard | AIOPS | errored | delete+start recovery |

## 7. SECURITY & HEALTH CHECK GAPS

| Issue | AIOPS | COREDB | Hostinger |
|-------|:-----:|:------:|:---------:|
| Containers without HEALTHCHECK | 11 | 3 | **12 (86%)** |
| Privileged containers | 0 | 1 (cadvisor) | 0 |
| 0.0.0.0 binds | 0 | 0 | 0 |

## 8. KEY ISSUES IDENTIFIED

### P0 — AIOPS Memory Crisis
7.4 GiB swapped, prediction-radar-app-api at 96% memory limit, 4 concurrent Claude instances consuming 1.5 GiB. Risk: OOM killer may terminate critical services.

### P0 — COREDB is a Ghost Town
16 cores, 30 GiB RAM, 13% utilization. ZERO PM2 processes. This server is the most expensive idle asset in the ecosystem. It should be running 30-40 PM2 agents and additional pipeline containers.

### P1 — Ecosystem Registry is Blind
The discovery API at :8190 returns 1 capability (prediction-radar). The anti-duplication prebuild check cannot prevent duplicate work because it has no data. 255 workloads exist but the registry catalogs effectively none of them.

### P1 — Triple-Duplicated Infrastructure
Temporal, cadvisor, pushgateway, and promtail run on all 3 servers. Consolidating to one server each frees ~1 GiB RAM across the ecosystem.

### P2 — 26 Containers Without HEALTHCHECK
Docker cannot auto-restart unhealthy containers without HEALTHCHECK directives. Hostinger is worst at 86% unmonitored.

### P2 — 2 PM2 Processes Down
command-center and pnl-dashboard need delete+start recovery per the pm2-recovery skill.

## 9. RECOMMENDED TARGET DISTRIBUTION

| Server | Current PM2 | Target PM2 | Current Docker | Target Docker | Target RAM |
|--------|:-----------:|:----------:|:--------------:|:-------------:|:----------:|
| AIOPS | 136 | **~85** | 64 | **~45** | ~18 GiB (60%) |
| COREDB | 0 | **~40** | 23 | **~35** | ~15 GiB (50%) |
| Hostinger | 18 | **~30** | 14 | **~22** | ~12 GiB (38%) |

### Migration Priorities
1. **Move 15-20 low-impact AI agents** from AIOPS → COREDB (marketing, analytics, productivity agents)
2. **Move prediction-radar-questdb-ingestion** (195 MiB, 11% CPU) → COREDB (closer to QuestDB)
3. **Consolidate Temporal** to COREDB only (it already runs there, has the DB backends)
4. **Consolidate monitoring stack** — promtail/cadvisor/pushgateway to single instances
5. **Decommission duplicate PM2 services** — Hostinger serves production, AIOPS serves dev/internal
6. **Populate ecosystem registry** — catalog all 255 workloads so anti-duplication works

## 10. ACTION PLAN

### Immediate (Today)
- [ ] Recover command-center and pnl-dashboard via pm2-recovery skill
- [ ] Investigate prediction-radar-app-api at 96% memory limit (risk of OOM)

### Short-term (This Week)
- [ ] Migrate 15-20 PM2 agents from AIOPS to COREDB
- [ ] Consolidate Temporal to COREDB only
- [ ] Add HEALTHCHECK to 26 containers across fleet
- [ ] Fix cadvisor privileged mode on COREDB

### Medium-term (Next 2 Weeks)
- [ ] Populate ecosystem registry with all 255 workloads
- [ ] Rationalize duplicate PM2 services (6 pairs)
- [ ] Deploy PM2 on COREDB with first 30-40 agent processes
- [ ] Add memory limits to unlimited containers on Hostinger

### Long-term (Ongoing)
- [ ] Maintain 60-50-38% workload distribution across AIOPS-COREDB-Hostinger
- [ ] Auto-balance new deployments via ecosystem discovery prebuild check
- [ ] Monthly cross-server audit cadence

---

**Audit performed by:** 4-agent parallel swarm (infra-intelligence, docker-intelligence, pm2-intelligence, multi-server-coordination)
**Data integrity:** All numbers from live server queries at 2026-05-28 ~06:50 UTC
**Verdict:** 1-SERVER MADNESS CONFIRMED — AIOPS at 78.4% of all workloads with active swap, COREDB at 9% near-idle. Requires workload migration to restore balance.
